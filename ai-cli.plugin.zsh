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

_ai_cli_prepare_codex_profile() {
  local config_toml="$1"
  local model_provider="$2"

  printf '%s\n' "$config_toml" | awk -v target="$model_provider" '
    BEGIN {
      target_re = "^[[:space:]]*\\[model_providers\\." target "\\][[:space:]]*$"
      in_target = 0
      found_target = 0
      saw_model_provider = 0
    }

    /^[[:space:]]*\[/ {
      if ($0 ~ target_re) {
        print ""
        print "[model_providers." target "]"
        in_target = 1
        found_target = 1
      } else {
        in_target = 0
      }
      next
    }

    {
      if (in_target) {
        if ($0 ~ /^[[:space:]]*(name|wire_api|requires_openai_auth|base_url|env_key|experimental_bearer_token)[[:space:]]*=/) {
          print
        }
        next
      }

      if ($0 ~ /^[[:space:]]*(model_provider|model|model_reasoning_effort)[[:space:]]*=/) {
        print
        if ($0 ~ /^[[:space:]]*model_provider[[:space:]]*=/) {
          saw_model_provider = 1
        }
      }
    }

    END {
      if (!saw_model_provider) {
        print "ai-cli: provider config has no model_provider" > "/dev/stderr"
        exit 3
      }
      if (!found_target) {
        print "ai-cli: provider model table not found" > "/dev/stderr"
        exit 3
      }
    }
  '
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

_ai_cli_codex_top_level_string_value() {
  local config_toml="$1"
  local key="$2"

  printf '%s\n' "$config_toml" | awk -v key="$key" '
    /^[[:space:]]*\[/ {
      exit
    }

    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value = $0
      sub(/^[^"]*"/, "", value)
      sub(/".*$/, "", value)
      print value
      exit
    }
  ' | head -n 1
}

_ai_cli_codex_top_level_reasoning_effort() {
  local config_toml="$1"
  local value

  value=$(_ai_cli_codex_top_level_string_value "$config_toml" model_reasoning_effort)
  case "$value" in
    minimal|low|medium|high|xhigh|max|ultra) print -r -- "$value" ;;
  esac
}

_ai_cli_codex_model_catalog_selection() {
  local catalog_json="$1"
  local existing_model="$2"
  local existing_reasoning_effort="$3"
  local configured_reasoning_effort="$4"

  jq -c \
    --arg existing_model "$existing_model" \
    --arg existing_reasoning_effort "$existing_reasoning_effort" \
    --arg configured_reasoning_effort "$configured_reasoning_effort" \
    '
      (.models // []) as $models
      | (($models | map(select(.model == $existing_model)) | .[0]) // $models[0]) as $selected
      | ($selected.supported_reasoning_levels // [] | map(.effort)) as $supported
      | (if ($existing_reasoning_effort != "" and ($supported | index($existing_reasoning_effort)) != null) then
           $existing_reasoning_effort
         elif ($configured_reasoning_effort != "" and ($supported | index($configured_reasoning_effort)) != null) then
           $configured_reasoning_effort
         elif (($selected.default_reasoning_level // "") != "" and
               ($supported | index($selected.default_reasoning_level)) != null) then
           $selected.default_reasoning_level
         else
           $supported[0] // "high"
         end) as $reasoning_effort
      | {model: ($selected.model // ""), reasoning_effort: $reasoning_effort}
    ' <<<"$catalog_json"
}

_ai_cli_codex_model_catalog_template() {
  jq -cn '
    {
      model: "ai-cli-template",
      slug: "ai-cli-template",
      display_name: "ai-cli-template",
      description: "ai-cli-template",
      base_instructions: "You are Codex, a coding agent.",
      default_reasoning_level: "high",
      supported_reasoning_levels: [
        {effort: "none", description: "Disable Thinking"},
        {effort: "high", description: "Enabled Thinking"}
      ],
      shell_type: "shell_command",
      visibility: "list",
      supported_in_api: true,
      priority: 0,
      supports_reasoning_summaries: true,
      default_reasoning_summary: "none",
      support_verbosity: false,
      truncation_policy: {mode: "bytes", limit: 10000},
      supports_parallel_tool_calls: false,
      supports_image_detail_original: false,
      context_window: 262144,
      max_context_window: 262144,
      effective_context_window_percent: 95,
      experimental_supported_tools: [],
      input_modalities: ["text", "image"],
      supports_search_tool: false
    }
  '
}

_ai_cli_codex_model_catalog_json() {
  local provider_json="$1"
  local config_toml="${2-}"
  local template_json model_count configured_reasoning_effort

  configured_reasoning_effort="high"
  if [[ -n "$config_toml" ]]; then
    configured_reasoning_effort=$(_ai_cli_codex_top_level_reasoning_effort "$config_toml")
    [[ -n "$configured_reasoning_effort" ]] || configured_reasoning_effort="high"
  fi

  model_count=$(jq -r '
    (.provider.settingsConfig.modelCatalog.models // [])
    | if type == "array" then length else 0 end
  ' <<<"$provider_json") || return 1
  (( model_count > 0 )) || return 0

  template_json=$(_ai_cli_codex_model_catalog_template) || return 1
  jq \
    --argjson template "$template_json" \
    --arg configured_reasoning_effort "$configured_reasoning_effort" \
    '
    def trim_string($value):
      $value | gsub("^[[:space:]]+|[[:space:]]+$"; "");

    def context_window($value; $fallback):
      if (($value | type) == "number") then
        if $value > 0 then $value else $fallback end
      elif (($value | type) == "string") then
        ($value | try tonumber catch null) as $number
        | if (($number | type) == "number" and $number > 0) then
            $number
          else
            $fallback
          end
      else
        $fallback
      end;

    (.provider.settingsConfig.modelCatalog.models // []) as $source
    | reduce $source[] as $entry (
        [];
        ($entry.model // null) as $model_value
        | if (($model_value | type) != "string") then
            .
          else
            ($model_value | trim_string(.)) as $model
            | if (($model | length) == 0 or any(.[]; .model == $model)) then
                .
              else
                ($entry.displayName // $entry.display_name // null) as $display_value
                | (if (($display_value | type) == "string") then
                     ($display_value | trim_string(.))
                   else
                     ""
                   end) as $display_candidate
                | if (($display_candidate | length) > 0) then
                    $display_candidate
                  else
                    $model
                  end as $display_name
                | context_window(
                    ($entry.contextWindow // $entry.context_window // null);
                    $template.context_window
                  ) as $context_window
                | (1000 + length) as $priority
                | . + [(
                    $template
                    | .model = $model
                    | .slug = $model
                    | .display_name = $display_name
                    | .description = $display_name
                    | .context_window = $context_window
                    | .max_context_window = $context_window
                    | .priority = $priority
                    | if ($model | startswith("deepseek-")) then
                        .default_reasoning_level = $configured_reasoning_effort
                        | .supported_reasoning_levels = [
                            {effort: "low", description: "Fast responses with lighter reasoning"},
                            {effort: "high", description: "Greater reasoning depth for complex problems"},
                            {effort: "max", description: "Maximum reasoning depth for the hardest problems"}
                          ]
                      elif any(.supported_reasoning_levels[]; .effort == $configured_reasoning_effort) then
                        .default_reasoning_level = $configured_reasoning_effort
                      else
                        .default_reasoning_level = $configured_reasoning_effort
                        | .supported_reasoning_levels += [{
                            effort: $configured_reasoning_effort,
                            description: "Configured reasoning effort"
                          }]
                      end
                  )]
              end
          end
      )
    | {models: .}
  ' <<<"$provider_json"
}

_ai_cli_prepare_codex_model_catalog_profile() {
  local config_toml="$1"
  local catalog_filename="$2"

  awk -v catalog_filename="$catalog_filename" '
    function insert_catalog() {
      print "model_catalog_json = \"" catalog_filename "\""
      inserted = 1
    }

    BEGIN {
      inserted = 0
    }

    /^[[:space:]]*\[/ {
      if (!inserted) {
        insert_catalog()
      }
    }

    /^[[:space:]]*model_catalog_json[[:space:]]*=/ {
      next
    }

    {
      print
    }

    END {
      if (!inserted) {
        insert_catalog()
      }
    }
  ' <<<"$config_toml"
}

_ai_cli_prepare_codex_model_selection_profile() {
  local config_toml="$1"
  local selected_model="$2"
  local selected_reasoning_effort="$3"

  awk \
    -v selected_model="$selected_model" \
    -v selected_reasoning_effort="$selected_reasoning_effort" \
    '
      function insert_missing() {
        if (!saw_model) {
          print "model = \"" selected_model "\""
        }
        if (!saw_reasoning_effort) {
          print "model_reasoning_effort = \"" selected_reasoning_effort "\""
        }
        inserted = 1
      }

      BEGIN {
        in_table = 0
        inserted = 0
        saw_model = 0
        saw_reasoning_effort = 0
      }

      /^[[:space:]]*\[/ {
        if (!inserted) {
          insert_missing()
        }
        in_table = 1
      }

      {
        if (!in_table && $0 ~ /^[[:space:]]*model[[:space:]]*=/) {
          print "model = \"" selected_model "\""
          saw_model = 1
          next
        }
        if (!in_table && $0 ~ /^[[:space:]]*model_reasoning_effort[[:space:]]*=/) {
          print "model_reasoning_effort = \"" selected_reasoning_effort "\""
          saw_reasoning_effort = 1
          next
        }
        print
      }

      END {
        if (!inserted) {
          insert_missing()
        }
      }
    ' <<<"$config_toml"
}

_ai_cli_write_codex_model_catalog() {
  local codex_home="$1"
  local catalog_filename="$2"
  local catalog_json="$3"
  local catalog_file temp_file

  mkdir -p -- "$codex_home" || {
    _ai_cli_die "failed to create CODEX_HOME: $codex_home"
    return 1
  }

  catalog_file="$codex_home/$catalog_filename"
  if [[ -L "$catalog_file" ]]; then
    _ai_cli_die "refusing to overwrite symlinked Codex model catalog: $catalog_file"
    return 1
  fi

  temp_file=$(mktemp "$codex_home/.ai-cli-catalog.XXXXXX") || {
    _ai_cli_die "failed to create temporary Codex model catalog"
    return 1
  }

  if ! print -r -- "$catalog_json" >"$temp_file"; then
    rm -f -- "$temp_file"
    _ai_cli_die "failed to write temporary Codex model catalog"
    return 1
  fi
  chmod 600 "$temp_file" || {
    rm -f -- "$temp_file"
    _ai_cli_die "failed to protect temporary Codex model catalog"
    return 1
  }

  if ! mv -f -- "$temp_file" "$catalog_file"; then
    rm -f -- "$temp_file"
    _ai_cli_die "failed to install Codex model catalog: $catalog_file"
    return 1
  fi

  print -r -- "$catalog_file"
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
  local config_toml profile_toml catalog_json catalog_filename
  local existing_profile_file existing_profile_toml selection_json
  local existing_model existing_reasoning_effort configured_reasoning_effort
  local selected_model selected_reasoning_effort
  local auth_value model_provider configured_env_key codex_home
  local match_count catalog_count

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
  [[ -n "$model_provider" ]] || {
    _ai_cli_die "provider '$provider_name' has no model_provider in Codex config"
    return 1
  }
  if [[ ! "$model_provider" =~ '^[A-Za-z0-9_-]+$' ]]; then
    _ai_cli_die "provider '$provider_name' has an unsupported model_provider: $model_provider"
    return 1
  fi

  configured_env_key=""
  configured_env_key=$(_ai_cli_codex_config_env_key "$config_toml" "$model_provider")
  if [[ -n "$configured_env_key" && ! "$configured_env_key" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]]; then
    _ai_cli_die "provider '$provider_name' has an unsupported env_key: $configured_env_key"
    return 1
  fi

  auth_value=$(_ai_cli_codex_auth_value "$provider_json" "$configured_env_key") || {
    _ai_cli_die "failed to read auth settings for Codex provider '$provider_name'"
    return 1
  }

  profile_toml=$(_ai_cli_prepare_codex_profile "$config_toml" "$model_provider") || {
    _ai_cli_die "failed to prepare provider overlay for Codex provider '$provider_name'"
    return 1
  }
  if [[ -n "$auth_value" ]]; then
    if ! profile_toml=$(_ai_cli_prepare_codex_env_profile "$profile_toml" "$model_provider"); then
      _ai_cli_die "failed to prepare environment-auth profile for Codex provider '$provider_name'"
      return 1
    fi
  fi

  codex_home="${CODEX_HOME:-${HOME:-$PWD}/.codex}"
  catalog_json=$(_ai_cli_codex_model_catalog_json "$provider_json" "$profile_toml") || {
    _ai_cli_die "failed to generate model catalog for Codex provider '$provider_name'"
    return 1
  }
  if [[ -n "$catalog_json" ]]; then
    catalog_count=$(jq -r '.models | length' <<<"$catalog_json") || {
      _ai_cli_die "failed to inspect model catalog for Codex provider '$provider_name'"
      return 1
    }
    if (( catalog_count > 0 )); then
      catalog_filename="$provider_id.model_catalog.json"
      existing_profile_file="$codex_home/$provider_id.config.toml"
      if [[ -L "$existing_profile_file" ]]; then
        _ai_cli_die "refusing to read symlinked Codex profile: $existing_profile_file"
        return 1
      fi
      existing_profile_toml=""
      if [[ -f "$existing_profile_file" ]]; then
        existing_profile_toml=$(<"$existing_profile_file")
      fi

      existing_model=$(_ai_cli_codex_top_level_string_value "$existing_profile_toml" model)
      existing_reasoning_effort=$(_ai_cli_codex_top_level_reasoning_effort "$existing_profile_toml")
      configured_reasoning_effort=$(_ai_cli_codex_top_level_reasoning_effort "$profile_toml")
      [[ -n "$configured_reasoning_effort" ]] || configured_reasoning_effort="high"
      selection_json=$(_ai_cli_codex_model_catalog_selection \
        "$catalog_json" \
        "$existing_model" \
        "$existing_reasoning_effort" \
        "$configured_reasoning_effort") || {
        _ai_cli_die "failed to select model for Codex provider '$provider_name'"
        return 1
      }
      selected_model=$(jq -r '.model // empty' <<<"$selection_json")
      selected_reasoning_effort=$(jq -r '.reasoning_effort // empty' <<<"$selection_json")
      [[ -n "$selected_model" && -n "$selected_reasoning_effort" ]] || {
        _ai_cli_die "Codex provider '$provider_name' has no usable model selection"
        return 1
      }
      profile_toml=$(_ai_cli_prepare_codex_model_selection_profile \
        "$profile_toml" \
        "$selected_model" \
        "$selected_reasoning_effort") || {
        _ai_cli_die "failed to prepare model selection for Codex provider '$provider_name'"
        return 1
      }
      profile_toml=$(_ai_cli_prepare_codex_model_catalog_profile "$profile_toml" "$catalog_filename") || {
        _ai_cli_die "failed to prepare model catalog profile for Codex provider '$provider_name'"
        return 1
      }
      _ai_cli_write_codex_model_catalog "$codex_home" "$catalog_filename" "$catalog_json" >/dev/null || return 1
    fi
  fi
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

codex-cpa() { _ai_cli_run_codex 'CPA' "$@"; }
codex-hyb() { _ai_cli_run_codex '黑与白' "$@"; }
codex-hc() { _ai_cli_run_codex 'hc' "$@"; }
codex-s2a() { _ai_cli_run_codex 'sub2api' "$@"; }
codex-ds() { _ai_cli_run_codex 'DeepSeek' "$@"; }
codex-openai() { _ai_cli_run_codex 'OpenAI Official' "$@"; }
