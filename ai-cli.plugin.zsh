# ai-cli plugin - AI CLI 工具快捷封装
# 依赖: cc-switch-cli (https://github.com/SaladDay/cc-switch-cli)

# === 基础别名 ===
alias ccs='cc-switch'

# cc-switch 包装函数：惰性依赖检查
# 使用此函数替代直接调用 cc-switch 命令
_cc_switch() {
    if ! command -v cc-switch &>/dev/null; then
        echo "❌ 未安装 cc-switch" >&2
        echo "请执行: curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash" >&2
        return 1
    fi
    command cc-switch "$@"
}

# === Provider 检测辅助函数 ===

# 获取指定 provider 名称的 ID
# 参数: $1 = provider_name, $2 = app (默认 claude)
# 输出: provider ID 或空字符串
_ai_cli_get_provider_id() {
    local provider_name="$1"
    local app="${2:-claude}"

    # 从表格中精确匹配 provider 名称并提取其 UUID
    # 表格格式: ┆ UUID ┆ Name ┆ API URL
    # 使用 awk 进行精确匹配，忽略表格边框字符
    _cc_switch -a "$app" provider list 2>/dev/null | \
        awk -v name="$provider_name" '
        BEGIN { found=0; id="" }
        {
            # 查找包含 UUID 格式的行
            if (match($0, /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/)) {
                id = substr($0, RSTART, RLENGTH)
                # 检查该行是否包含目标 provider 名称
                # 注意：provider 名称可能在 UUID 之后出现
                if (index($0, name) > 0) {
                    print id
                    found = 1
                    exit
                }
            }
        }
        END { if (!found) print "" }
    '
}

# 检测指定的 provider 是否已配置
# 参数: $1 = provider_name, $2 = app (默认 claude)
# 返回: 0 = 已配置, 1 = 未配置
_ai_cli_check_provider() {
    local provider_name="$1"
    local app="${2:-claude}"

    [[ -n "$(_ai_cli_get_provider_id "$provider_name" "$app")" ]]
}

# Provider 检测和配置引导
# 参数: $1 = provider_name, $2 = app (默认 claude)
_ai_cli_ensure_provider() {
    local provider_name="$1"
    local app="${2:-claude}"

    if ! _ai_cli_check_provider "$provider_name" "$app"; then
        echo "⚠️  Provider '$provider_name' 未配置"
        echo ""
        echo "请先配置 provider:"
        echo "  运行: ccs"
        echo "  然后: provider -> add -> 添加 '$provider_name'"
        echo ""
        return 1
    fi
    return 0
}

# === Provider 环境变量提取函数 ===

# 从 cc-switch config show 输出中提取指定 provider 的环境变量
# 参数: $1 = provider_name, $2 = app (claude/codex)
# 输出: key=value 格式的环境变量，每行一个
_ai_cli_get_provider_env() {
    local provider_name="$1"
    local app="${2:-claude}"

    # 检查 jq 是否可用（惰性检查，不阻塞 shell）
    if ! command -v jq &>/dev/null; then
        echo "❌ 未安装 jq，请执行: brew install jq" >&2
        return 1
    fi

    # 获取完整配置 JSON
    local config=$(_cc_switch config show 2>/dev/null | sed -n '/^{/,$p')

    if [[ -z "$config" ]]; then
        echo "❌ 无法获取 cc-switch 配置" >&2
        return 1
    fi

    # 使用单次 jq 调用提取环境变量，避免多行字符串解析问题
    # Claude: .settingsConfig.env (包含 BASE_URL)
    # Codex: .settingsConfig.auth (API_KEY) + .meta.custom_endpoints (BASE_URL)
    local env_vars=$(jq -r --arg app "$app" --arg name "$provider_name" '
        .[$app].providers |
        to_entries[] |
        select(.value.name == $name) |
        .value |
        (
            # 提取 auth/env 中的环境变量
            .settingsConfig |
            (.env // .auth // empty) |
            to_entries[] |
            "\(.key)=\(.value)"
        ),
        (
            # 对于 Codex，从 custom_endpoints 提取 base_url
            if $app == "codex" then
                .meta.custom_endpoints // empty |
                to_entries[0].value.url // empty |
                if . != "null" and . != "" then
                    "OPENAI_BASE_URL=\(.)"
                else
                    empty
                end
            else
                empty
            end
        )
    ' <<< "$config")

    echo "$env_vars"
}

# 设置 provider 环境变量并启动 CLI（新方式，不使用 switch）
# 参数: $1 = provider_name, $2 = app (claude), $3.. = CLI 参数
_ai_cli_launch_with_provider() {
    local provider_name="$1"
    local app="${2:-claude}"
    shift 2  # 移除前两个参数，剩余为 CLI 参数

    # 检查 provider 是否存在
    _ai_cli_ensure_provider "$provider_name" "$app" || return 1

    # 获取环境变量
    local env_vars=$(_ai_cli_get_provider_env "$provider_name" "$app")

    if [[ -z "$env_vars" ]]; then
        echo "❌ 无法获取 provider '$provider_name' 的环境变量配置" >&2
        return 1
    fi

    # 批量设置环境变量并启动 CLI
    # 使用 env 子进程确保环境变量只影响当前命令
    env $(echo "$env_vars") command claude "$@"
}

# 设置 provider 环境变量并启动 Codex CLI
# 参数: $1 = provider_name, $2.. = CLI 参数
_ai_cli_launch_codex_with_provider() {
    local provider_name="$1"
    shift  # 移除第一个参数，剩余为 CLI 参数

    # 检查 provider 是否存在
    _ai_cli_ensure_provider "$provider_name" "codex" || return 1

    # 获取环境变量
    local env_vars=$(_ai_cli_get_provider_env "$provider_name" "codex")

    if [[ -z "$env_vars" ]]; then
        echo "❌ 无法获取 provider '$provider_name' 的环境变量配置" >&2
        return 1
    fi

    # 批量设置环境变量并启动 CLI
    env $(echo "$env_vars") command codex "$@"
}

# === Claude 便捷调用函数 ===
# 注意：使用新方式，直接从配置读取环境变量，不调用 switch
# 这样可以实现 session 级别隔离，并支持 cc-switch 的故障转移功能

function deepseek() {
    _ai_cli_launch_with_provider "DeepSeek" "claude" "$@"
}

function glm() {
    _ai_cli_launch_with_provider "Zhipu GLM" "claude" "$@"
}

function modelscope() {
    _ai_cli_launch_with_provider "ModelScope" "claude" "$@"
}

function minimaxi() {
    _ai_cli_launch_with_provider "MiniMax" "claude" "$@"
}

function hybgzs() {
    _ai_cli_launch_with_provider "黑与白" "claude" "$@"
}

function nvidia() {
    _ai_cli_launch_with_provider "Nvidia" "claude" "$@"
}

# === Codex 便捷调用函数 ===
function codex-cpa() {
    _ai_cli_launch_codex_with_provider "CPA" "$@"
}

function codex-hyb() {
    _ai_cli_launch_codex_with_provider "黑与白" "$@"
}

function codex-openai() {
    _ai_cli_launch_codex_with_provider "OpenAI Official" "$@"
}

# === 未配置的函数（占位符，需要先在 cc-switch 中配置）===
# function kimi() { cc-switch provider switch Kimi; command claude "$@"; }
# function ccr-code() { cc-switch provider switch CCR; command claude "$@"; }
# function gemini() { cc-switch -a gemini provider switch default; command gemini "$@"; }

# 惰性加载 completions，不阻塞插件加载
command -v cc-switch &>/dev/null && source <(cc-switch completions zsh 2>/dev/null) || true 
