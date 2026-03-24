alias ccs='cc-switch'

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
      jq) _ai_cli_die 'missing required command: jq\nInstall jq: brew install jq' ;;
      yj) _ai_cli_die 'missing required command: yj\nInstall yj: brew install yj' ;;
      claude) _ai_cli_die 'missing required command: claude' ;;
      codex) _ai_cli_die 'missing required command: codex' ;;
      *) _ai_cli_die "missing required command: $cmd" ;;
    esac
    return 1
  done
}

_ai_cli_config_json() {
  local output json

  if ! output=$(command cc-switch config show 2>&1); then
    _ai_cli_die "failed to read cc-switch config"
    [[ -n "$output" ]] && print -u2 -- "$output"
    return 1
  fi

  json=$(printf '%s\n' "$output" | sed -n '/^{/,$p')
  [[ -n "$json" ]] || _ai_cli_die "cc-switch config output did not contain JSON" || return 1
  jq -e . >/dev/null 2>&1 <<<"$json" || _ai_cli_die "failed to parse cc-switch config JSON" || return 1
  print -r -- "$json"
}

_ai_cli_provider_json() {
  local config_json="$1"
  local app="$2"
  local provider_name="$3"

  jq -ec \
    --arg app "$app" \
    --arg name "$provider_name" \
    '.[$app].providers // {} | to_entries[] | .value | select(.name == $name)' \
    <<<"$config_json"
}

_ai_cli_missing_provider() {
  local app="$1"
  local provider_name="$2"

  _ai_cli_die "provider '$provider_name' is not configured for $app"
  print -u2 -- "List providers: ccs -a $app provider list"
  print -u2 -- "Add providers: ccs"
  return 1
}

_ai_cli_clear_claude_env() {
  unset ANTHROPIC_AUTH_TOKEN
  unset ANTHROPIC_BASE_URL
  unset ANTHROPIC_MODEL
  unset ANTHROPIC_DEFAULT_HAIKU_MODEL
  unset ANTHROPIC_DEFAULT_OPUS_MODEL
  unset ANTHROPIC_DEFAULT_SONNET_MODEL
}

_ai_cli_clear_codex_env() {
  unset OPENAI_API_KEY
  unset OPENAI_BASE_URL
  unset HYB_API_KEY
  unset WJ_API_KEY
  unset CPA_API_KEY
}

_ai_cli_codex_config_args() {
  local config_toml="$1"

  printf '%s\n' "$config_toml" | yj -tj | jq -r '
    def key_part:
      if type == "number" then tostring
      elif test("^[A-Za-z0-9_-]+$") then .
      else @json
      end;

    . as $doc
    | paths as $path
    | ($doc | getpath($path)) as $value
    | select(($path[0] // "") != "projects")
    | select(($path[0] // "") != "notice")
    | select(($value | type) != "object")
    | select((($path | length) == 0) or (($path[-1] | type) != "number"))
    | [$path | map(key_part) | join("."), ($value | tojson)]
    | @tsv
  '
}

_ai_cli_codex_env_key() {
  local provider_name="$1"

  case "$provider_name" in
    '黑与白') print -r -- 'HYB_API_KEY' ;;
    '万界方舟') print -r -- 'WJ_API_KEY' ;;
    'CPA') print -r -- 'CPA_API_KEY' ;;
    *) print -r -- 'OPENAI_API_KEY' ;;
  esac
}

_ai_cli_run_claude() {
  local provider_name="$1"
  shift

  local config_json provider_json env_tsv settings_file real_settings

  _ai_cli_require_commands cc-switch jq claude || return 1

  config_json=$(_ai_cli_config_json) || return 1
  provider_json=$(_ai_cli_provider_json "$config_json" claude "$provider_name") || {
    _ai_cli_missing_provider claude "$provider_name"
    return 1
  }

  env_tsv=$(jq -r '.settingsConfig.env // {} | to_entries[]? | [.key, (.value | tostring)] | @tsv' <<<"$provider_json")
  [[ -n "$env_tsv" ]] || _ai_cli_die "provider '$provider_name' does not define Claude env settings" || return 1

  settings_file=$(mktemp "${TMPDIR:-/tmp}/ai-cli-claude-settings.XXXXXX.json") || return 1
  real_settings="$HOME/.claude/settings.json"

  (
    trap 'rm -f -- "$settings_file"' EXIT INT TERM

    if [[ -f "$real_settings" ]]; then
      jq '.env = {}' "$real_settings" >"$settings_file" || {
        _ai_cli_die "failed to sanitize ~/.claude/settings.json"
        return 1
      }
    else
      print -r -- '{"env":{}}' >"$settings_file"
    fi

    _ai_cli_clear_claude_env

    local key value
    while IFS=$'\t' read -r key value; do
      [[ -n "$key" ]] && export "$key=$value"
    done <<<"$env_tsv"

    command claude --setting-sources project,local --settings "$settings_file" "$@"
  )
}

_ai_cli_run_codex() {
  local provider_name="$1"
  shift

  local config_json provider_json auth_json config_toml api_key model_provider env_key
  local -a config_args

  _ai_cli_require_commands cc-switch jq yj codex || return 1

  config_json=$(_ai_cli_config_json) || return 1
  provider_json=$(_ai_cli_provider_json "$config_json" codex "$provider_name") || {
    _ai_cli_missing_provider codex "$provider_name"
    return 1
  }

  auth_json=$(jq -c '.settingsConfig.auth // {}' <<<"$provider_json")
  config_toml=$(jq -r '.settingsConfig.config // ""' <<<"$provider_json")
  [[ -n "$config_toml" ]] || _ai_cli_die "provider '$provider_name' does not define Codex config" || return 1
  model_provider=$(printf '%s\n' "$config_toml" | yj -tj | jq -r '.model_provider // empty') || {
    _ai_cli_die "failed to parse provider codex model_provider"
    return 1
  }

  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] && config_args+=(-c "$key=$value")
  done <<<"$(_ai_cli_codex_config_args "$config_toml")" || {
    _ai_cli_die "failed to parse provider codex config TOML"
    return 1
  }

  api_key=$(jq -r '.OPENAI_API_KEY // empty' <<<"$auth_json")
  env_key=$(_ai_cli_codex_env_key "$provider_name")

  (
    _ai_cli_clear_codex_env

    if [[ -n "$api_key" && "$api_key" != "null" ]]; then
      export "$env_key=$api_key"
      if [[ -n "$model_provider" ]]; then
        config_args+=(-c "model_providers.${model_provider}.env_key=\"$env_key\"")
      fi
    fi

    command codex "${config_args[@]}" "$@"
  )
}

deepseek() { _ai_cli_run_claude 'DeepSeek' "$@"; }
glm() { _ai_cli_run_claude 'Zhipu GLM' "$@"; }
modelscope() { _ai_cli_run_claude 'ModelScope' "$@"; }
minimaxi() { _ai_cli_run_claude 'MiniMax' "$@"; }
hybgzs() { _ai_cli_run_claude '黑与白' "$@"; }
nvidia() { _ai_cli_run_claude 'Nvidia' "$@"; }
ccwj() { _ai_cli_run_claude '万界方舟' "$@"; }

codex-cpa() { _ai_cli_run_codex 'CPA' "$@"; }
codex-hyb() { _ai_cli_run_codex '黑与白' "$@"; }
codex-openai() { _ai_cli_run_codex 'OpenAI Official' "$@"; }
codex-wj() { _ai_cli_run_codex '万界方舟' "$@"; }
