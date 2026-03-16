# ai-cli plugin - AI CLI 工具快捷封装
# 依赖: cc-switch-cli (https://github.com/SaladDay/cc-switch-cli)

if ! command -v cc-switch &>/dev/null; then
  echo "⚠️  ai-cli: cc-switch not found. Install:"
  echo "   curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash"
  return 1
fi

# === 基础别名 ===
alias ccs='cc-switch'

# === Claude 便捷调用函数 ===
function deepseek() { cc-switch provider switch DeepSeek; command claude "$@"; }
function glm() { cc-switch provider switch "Zhipu GLM"; command claude "$@"; }
function modelscope() { cc-switch provider switch ModelScope; command claude "$@"; }
function minimaxi() { cc-switch provider switch MiniMax; command claude "$@"; }
function hybgzs() { cc-switch provider switch "黑与白"; command claude "$@"; }
function nvidia() { cc-switch provider switch Nvidia; command claude "$@"; }

# === Codex 便捷调用函数 ===
function codex-cpa() { cc-switch -a codex provider switch CPA; command codex "$@"; }
function codex-hyb() { cc-switch -a codex provider switch "黑与白公益站"; command codex "$@"; }

# === 未配置的函数（占位符，需要先在 cc-switch 中配置）===
# function kimi() { cc-switch provider switch Kimi; command claude "$@"; }
# function ccr-code() { cc-switch provider switch CCR; command claude "$@"; }
# function gemini() { cc-switch -a gemini provider switch default; command gemini "$@"; }
