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
      jq) _ai_cli_die 'missing required command: jq\nInstall jq: brew install jq' ;;
      codex) _ai_cli_die 'missing required command: codex' ;;
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

_ai_cli_config_json() {
  local output json

  if ! output=$(command cc-switch config show 2>&1); then
    _ai_cli_die "failed to read cc-switch config"
    [[ -n "$output" ]] && print -u2 -- "$output"
    return 1
  fi

  json=$(printf '%s\n' "$output" | sed -n '/^[[:space:]]*{/,$p')
  [[ -n "$json" ]] || {
    _ai_cli_die "cc-switch config output did not contain JSON"
    return 1
  }

  if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
    _ai_cli_die "failed to parse cc-switch config JSON"
    return 1
  fi

  print -r -- "$json"
}

_ai_cli_codex_provider_matches() {
  local config_json="$1"
  local provider_name="$2"

  jq -c \
    --arg name "$provider_name" \
    '[ (.codex.providers // {}) | to_entries[]
       | select(.value.name == $name)
       | {id: .key, provider: .value} ]' \
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

_ai_cli_clear_codex_env() {
  local provider_env_key="${1-}"

  unset CUSTOM_API_KEY
  unset AI_CLI_CODEX_API_KEY
  unset OPENAI_API_KEY
  unset OPENAI_BASE_URL
  unset CODEX_API_KEY
  unset CODEX_ACCESS_TOKEN
  unset CODEX_SQLITE_HOME
  unset HYB_API_KEY
  unset WJ_API_KEY
  unset CPA_API_KEY
  if [[ -n "$provider_env_key" ]]; then
    unset "$provider_env_key"
  fi
  return 0
}

_ai_cli_codex_model_provider() {
  local config_toml="$1"

  printf '%s\n' "$config_toml" | sed -n \
    's/^[[:space:]]*model_provider[[:space:]]*=[[:space:]]*"\([^" ]*\)"[[:space:]]*#.*$/\1/p; s/^[[:space:]]*model_provider[[:space:]]*=[[:space:]]*"\([^" ]*\)"[[:space:]]*$/\1/p' \
    | head -n 1
}

_ai_cli_codex_config_env_key() {
  local config_toml="$1"
  local model_provider="$2"

  printf '%s\n' "$config_toml" | awk -v target="$model_provider" '
    BEGIN {
      target_re = "^[[:space:]]*\\[model_providers\\." target "\\][[:space:]]*$"
      in_target = 0
    }

    {
      if ($0 ~ /^[[:space:]]*\[/) {
        in_target = ($0 ~ target_re)
      }
      if (in_target && $0 ~ /^[[:space:]]*env_key[[:space:]]*=/) {
        value = $0
        sub(/^[^\"]*\"/, "", value)
        sub(/\".*$/, "", value)
        print value
        exit
      }
    }
  ' | head -n 1
}

_ai_cli_codex_auth_value() {
  local provider_json="$1"
  local configured_env_key="$2"

  jq -r \
    --arg env_key "$configured_env_key" \
    '
      (.provider.settingsConfig.auth // {}) as $auth
      | ($auth[$env_key] // null) as $configured_value
      | if ($env_key != "" and ($configured_value | type) == "string" and ($configured_value | length) > 0) then
          $configured_value
        else
          [ $auth | to_entries[]
            | select(.key | test("(^|_)API_KEY$"))
            | select((.value | type) == "string" and (.value | length) > 0)
            | .value ][0] // empty
        end
    ' \
    <<<"$provider_json"
}

_ai_cli_prepare_codex_env_profile() {
  local config_toml="$1"
  local model_provider="$2"

  printf '%s\n' "$config_toml" | awk -v target="$model_provider" '
    function flush_target() {
      if (!saw_requires) {
        print "requires_openai_auth = false"
      }
      if (!saw_env_key) {
        print "env_key = \"CUSTOM_API_KEY\""
      }
    }

    function fail(message, code) {
      print "ai-cli: " message > "/dev/stderr"
      failed = code
      exit code
    }

    BEGIN {
      target_re = "^[[:space:]]*\\[model_providers\\." target "\\][[:space:]]*$"
      nested_re = "^[[:space:]]*\\[model_providers\\." target "\\."
      in_target = 0
      found_target = 0
      saw_requires = 0
      saw_env_key = 0
      failed = 0
    }

    {
      if ($0 ~ nested_re && $0 !~ target_re) {
        fail("provider auth table cannot be switched to environment auth", 2)
      }

      if ($0 ~ /^[[:space:]]*\[/) {
        if (in_target && $0 !~ target_re) {
          flush_target()
        }
        in_target = ($0 ~ target_re)
        if (in_target) {
          found_target = 1
          saw_requires = 0
          saw_env_key = 0
        }
      }

      if (in_target && $0 ~ /^[[:space:]]*requires_openai_auth[[:space:]]*=/) {
        print "requires_openai_auth = false"
        saw_requires = 1
        next
      }
      if (in_target && $0 ~ /^[[:space:]]*env_key[[:space:]]*=/) {
        print "env_key = \"CUSTOM_API_KEY\""
        saw_env_key = 1
        next
      }
      if (in_target && $0 ~ /^[[:space:]]*experimental_bearer_token[[:space:]]*=/) {
        fail("provider bearer token cannot be switched to environment auth", 2)
      }

      print
    }

    END {
      if (failed) {
        exit failed
      }
      if (in_target) {
        flush_target()
      }
      if (!found_target) {
        print "ai-cli: provider model table not found" > "/dev/stderr"
        exit 3
      }
    }
  '
}

_ai_cli_write_codex_profile() {
  local codex_home="$1"
  local provider_id="$2"
  local config_toml="$3"
  local profile_file temp_file

  mkdir -p -- "$codex_home" || {
    _ai_cli_die "failed to create CODEX_HOME: $codex_home"
    return 1
  }

  profile_file="$codex_home/$provider_id.config.toml"
  if [[ -L "$profile_file" ]]; then
    _ai_cli_die "refusing to overwrite symlinked Codex profile: $profile_file"
    return 1
  fi

  temp_file=$(mktemp "$codex_home/.ai-cli-profile.XXXXXX") || {
    _ai_cli_die "failed to create temporary Codex profile"
    return 1
  }

  if ! print -r -- "$config_toml" >"$temp_file"; then
    rm -f -- "$temp_file"
    _ai_cli_die "failed to write temporary Codex profile"
    return 1
  fi
  chmod 600 "$temp_file" || {
    rm -f -- "$temp_file"
    _ai_cli_die "failed to protect temporary Codex profile"
    return 1
  }

  if ! mv -f -- "$temp_file" "$profile_file"; then
    rm -f -- "$temp_file"
    _ai_cli_die "failed to install Codex profile: $profile_file"
    return 1
  fi

  print -r -- "$profile_file"
}

_ai_cli_reject_codex_profile_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --profile|-p|--profile=*)
        _ai_cli_die "--profile is managed by the provider alias; resume with the same alias instead"
        return 1
        ;;
    esac
  done
}

_ai_cli_run_codex() {
  local provider_name="$1"
  shift

  local config_json provider_matches provider_json provider_id
  local config_toml profile_toml auth_value model_provider configured_env_key codex_home
  local match_count

  _ai_cli_require_commands cc-switch jq codex || return 1
  _ai_cli_reject_codex_profile_arg "$@" || return 1

  config_json=$(_ai_cli_config_json) || return 1
  provider_matches=$(_ai_cli_codex_provider_matches "$config_json" "$provider_name") || {
    _ai_cli_die "failed to find Codex provider '$provider_name'"
    return 1
  }

  match_count=$(jq -r 'length' <<<"$provider_matches") || {
    _ai_cli_die "failed to inspect Codex provider '$provider_name'"
    return 1
  }
  if (( match_count == 0 )); then
    _ai_cli_missing_provider codex "$provider_name"
    return 1
  fi
  if (( match_count > 1 )); then
    _ai_cli_die "multiple Codex providers are named '$provider_name'; use a unique provider name"
    return 1
  fi

  provider_json=$(jq -c '.[0]' <<<"$provider_matches") || {
    _ai_cli_die "failed to read Codex provider '$provider_name'"
    return 1
  }
  provider_id=$(jq -r '.id // empty' <<<"$provider_json") || return 1
  config_toml=$(jq -r '.provider.settingsConfig.config // empty' <<<"$provider_json") || return 1
  [[ -n "$provider_id" ]] || {
    _ai_cli_die "Codex provider '$provider_name' has no provider ID"
    return 1
  }
  if [[ ! "$provider_id" =~ '^[A-Za-z0-9_-]+$' ]]; then
    _ai_cli_die "Codex provider '$provider_name' has an unsupported provider ID: $provider_id"
    return 1
  fi
  [[ -n "$config_toml" ]] || {
    _ai_cli_die "provider '$provider_name' does not define Codex config"
    return 1
  }

  model_provider=$(_ai_cli_codex_model_provider "$config_toml")
  configured_env_key=""
  if [[ -n "$model_provider" && "$model_provider" =~ '^[A-Za-z0-9_-]+$' ]]; then
    configured_env_key=$(_ai_cli_codex_config_env_key "$config_toml" "$model_provider")
  fi
  if [[ -n "$configured_env_key" && ! "$configured_env_key" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]]; then
    _ai_cli_die "provider '$provider_name' has an unsupported env_key: $configured_env_key"
    return 1
  fi

  auth_value=$(_ai_cli_codex_auth_value "$provider_json" "$configured_env_key") || {
    _ai_cli_die "failed to read auth settings for Codex provider '$provider_name'"
    return 1
  }

  profile_toml="$config_toml"
  if [[ -n "$auth_value" ]]; then
    [[ -n "$model_provider" ]] || {
      _ai_cli_die "provider '$provider_name' has an API key but no model_provider in Codex config"
      return 1
    }
    if [[ ! "$model_provider" =~ '^[A-Za-z0-9_-]+$' ]]; then
      _ai_cli_die "provider '$provider_name' has an unsupported model_provider: $model_provider"
      return 1
    fi
    if ! profile_toml=$(_ai_cli_prepare_codex_env_profile "$config_toml" "$model_provider"); then
      _ai_cli_die "failed to prepare environment-auth profile for Codex provider '$provider_name'"
      return 1
    fi
  fi

  codex_home="${CODEX_HOME:-${HOME:-$PWD}/.codex}"
  _ai_cli_write_codex_profile "$codex_home" "$provider_id" "$profile_toml" >/dev/null || return 1

  (
    export CODEX_HOME="$codex_home"
    _ai_cli_clear_codex_env "$configured_env_key"
    if [[ -n "$auth_value" ]]; then
      export CUSTOM_API_KEY="$auth_value"
    fi
    command codex --profile "$provider_id" "$@"
  )
}

deepseek() { _ai_cli_start claude 'DeepSeek' "$@"; }
glm() { _ai_cli_start claude 'Zhipu GLM' "$@"; }
modelscope() { _ai_cli_start claude 'ModelScope' "$@"; }
minimaxi() { _ai_cli_start claude 'MiniMax' "$@"; }
hybgzs() { _ai_cli_start claude '黑与白' "$@"; }
nvidia() { _ai_cli_start claude 'Nvidia' "$@"; }
ccwj() { _ai_cli_start claude '万界方舟' "$@"; }

codex-cpa() { _ai_cli_run_codex 'CPA' "$@"; }
codex-hyb() { _ai_cli_run_codex '黑与白' "$@"; }
codex-hc() { _ai_cli_run_codex 'hc' "$@"; }
codex-s2a() { _ai_cli_run_codex 'sub2api' "$@"; }
codex-ds() { _ai_cli_run_codex 'DeepSeek' "$@"; }
codex-openai() { _ai_cli_run_codex 'OpenAI Official' "$@"; }
codex-wj() { _ai_cli_run_codex '万界方舟' "$@"; }
