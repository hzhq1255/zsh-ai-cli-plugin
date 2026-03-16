# ai-cli plugin - AI CLI 工具快捷封装
# 依赖: cc-switch-cli (https://github.com/SaladDay/cc-switch-cli)

# 检查 cc-switch 是否安装
if ! command -v cc-switch &>/dev/null; then
  echo "⚠️  ai-cli: cc-switch not found. Install:"
  echo "   curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash"
  return 1
fi

# === 基础别名 ===
alias cc='cc-switch'

# === Claude 便捷调用函数 ===
# 使用 cc-switch 切换提供商后调用 claude

function deepseek() { cc-switch provider switch deepseek; command claude "$@"; }
function glm() { cc-switch provider switch bigmodel; command claude "$@"; }
function kimi() { cc-switch provider switch kimi; command claude "$@"; }
function modelscope() { cc-switch provider switch modelscope; command claude "$@"; }
function minimaxi() { cc-switch provider switch minimaxi; command claude "$@"; }
function hybgzs() { cc-switch provider switch hybgzs; command claude "$@"; }
function ccr-code() { cc-switch provider switch ccr; command claude "$@"; }

# === Gemini 便捷调用函数 ===
function gemini() { cc-switch --app gemini provider switch default; command gemini "$@"; }

# === Codex 便捷调用函数 ===
function codex-cpa() { cc-switch provider switch cpa; command codex "$@"; }
function codex-hyb() { cc-switch provider switch hyb; command codex "$@"; }
