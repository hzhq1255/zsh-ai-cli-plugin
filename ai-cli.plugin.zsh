# ai-cli plugin - AI CLI 工具快捷封装
# 依赖: cc-switch-cli (https://github.com/SaladDay/cc-switch-cli)

if ! command -v cc-switch &>/dev/null; then
  echo "⚠️  ai-cli: cc-switch not found. Install:"
  echo "   curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash"
  return 1
fi

# === 基础别名 ===
alias ccs='cc-switch'

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
    cc-switch -a "$app" provider list 2>/dev/null | \
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

# === Provider 静默切换辅助函数 ===
# 静默切换 provider，失败时显示错误
# 参数: $1 = provider_id, $2 = app (默认 claude)
_ai_cli_switch_provider_silent() {
    local provider_id="$1"
    local app="${2:-claude}"
    local error_output

    # 切换 provider，抑制成功消息，捕获错误
    if ! error_output=$(cc-switch -a "$app" provider switch "$provider_id" 2>&1 >/dev/null); then
        echo "$error_output" >&2
        return 1
    fi
    return 0
}

# === Claude 便捷调用函数 ===
function deepseek() {
    _ai_cli_ensure_provider "DeepSeek" "claude" || return 1
    local id=$(_ai_cli_get_provider_id "DeepSeek" "claude")
    _ai_cli_switch_provider_silent "$id" "claude" && command claude "$@"
}

function glm() {
    _ai_cli_ensure_provider "Zhipu GLM" "claude" || return 1
    local id=$(_ai_cli_get_provider_id "Zhipu GLM" "claude")
    _ai_cli_switch_provider_silent "$id" "claude" && command claude "$@"
}

function modelscope() {
    _ai_cli_ensure_provider "ModelScope" "claude" || return 1
    local id=$(_ai_cli_get_provider_id "ModelScope" "claude")
    _ai_cli_switch_provider_silent "$id" "claude" && command claude "$@"
}

function minimaxi() {
    _ai_cli_ensure_provider "MiniMax" "claude" || return 1
    local id=$(_ai_cli_get_provider_id "MiniMax" "claude")
    _ai_cli_switch_provider_silent "$id" "claude" && command claude "$@"
}

function hybgzs() {
    _ai_cli_ensure_provider "黑与白" "claude" || return 1
    local id=$(_ai_cli_get_provider_id "黑与白" "claude")
    _ai_cli_switch_provider_silent "$id" "claude" && command claude "$@"
}

function nvidia() {
    _ai_cli_ensure_provider "Nvidia" "claude" || return 1
    local id=$(_ai_cli_get_provider_id "Nvidia" "claude")
    _ai_cli_switch_provider_silent "$id" "claude" && command claude "$@"
}

# === Codex 便捷调用函数 ===
function codex-cpa() {
    _ai_cli_ensure_provider "CPA" "codex" || return 1
    local id=$(_ai_cli_get_provider_id "CPA" "codex")
    _ai_cli_switch_provider_silent "$id" "codex" && command codex "$@"
}

function codex-hyb() {
    _ai_cli_ensure_provider "黑与白公益站" "codex" || return 1
    local id=$(_ai_cli_get_provider_id "黑与白公益站" "codex")
    _ai_cli_switch_provider_silent "$id" "codex" && command codex "$@"
}

# === 未配置的函数（占位符，需要先在 cc-switch 中配置）===
# function kimi() { cc-switch provider switch Kimi; command claude "$@"; }
# function ccr-code() { cc-switch provider switch CCR; command claude "$@"; }
# function gemini() { cc-switch -a gemini provider switch default; command gemini "$@"; }
