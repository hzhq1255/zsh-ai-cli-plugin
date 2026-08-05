alias ccs='NO_COLOR=1 cc-switch'

_ai_cli_die() {
  print -u2 -- "ai-cli: $*"
  return 1
}

_ai_cli_require_commands() {
  local cmd

  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 && continue

    case "$cmd" in
      cc-switch) _ai_cli_die 'missing required command: cc-switch\nInstall cc-switch: curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash' ;;
      *) _ai_cli_die "missing required command: $cmd" ;;
    esac
    return 1
  done
}

_ai_cli_start() {
  local app="$1"
  local provider_name="$2"
  shift 2

  _ai_cli_require_commands cc-switch || return 1
  command cc-switch start "$app" "$provider_name" -- "$@"
}

deepseek() { _ai_cli_start claude 'DeepSeek' "$@"; }
glm() { _ai_cli_start claude 'Zhipu GLM' "$@"; }
modelscope() { _ai_cli_start claude 'ModelScope' "$@"; }
minimaxi() { _ai_cli_start claude 'MiniMax' "$@"; }
hybgzs() { _ai_cli_start claude '黑与白' "$@"; }
nvidia() { _ai_cli_start claude 'Nvidia' "$@"; }
ccwj() { _ai_cli_start claude '万界方舟' "$@"; }

codex-cpa() { _ai_cli_start codex 'CPA' "$@"; }
codex-hyb() { _ai_cli_start codex '黑与白' "$@"; }
codex-hc() { _ai_cli_start codex 'hc' "$@"; }
codex-openai() { _ai_cli_start codex 'OpenAI Official' "$@"; }
codex-wj() { _ai_cli_start codex '万界方舟' "$@"; }
