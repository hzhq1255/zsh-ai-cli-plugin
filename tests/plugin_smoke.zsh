#!/usr/bin/env zsh

set -euo pipefail

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"

  [[ "$haystack" != *"$needle"* ]] || fail "expected output to not contain: $needle"
}

assert_file_contains() {
  local file="$1"
  local needle="$2"

  [[ -f "$file" ]] || fail "expected file to exist: $file"
  assert_contains "$(cat "$file")" "$needle"
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_FILE="$SCRIPT_DIR/../ai-cli.plugin.zsh"

TEST_ROOT=$(mktemp -d "/tmp/ai-cli-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

MOCK_BIN="$TEST_ROOT/bin"
WORK_HOME="$TEST_ROOT/home"
CODEX_HOME="$WORK_HOME/.codex"
mkdir -p "$MOCK_BIN" "$WORK_HOME/.claude" "$CODEX_HOME"

export AI_CLI_TEST_CONFIG="$TEST_ROOT/config.json"
export PATH="$MOCK_BIN:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cat >"$AI_CLI_TEST_CONFIG" <<'EOF'
{
  "claude": {
    "providers": {}
  },
  "codex": {
    "providers": {
      "hyb-id": {
        "name": "黑与白",
        "settingsConfig": {
          "auth": {
            "OPENAI_API_KEY": "hyb-key"
          },
          "config": "model_provider = \"custom\"\nmodel = \"gpt-5.4\"\n[model_providers.custom]\nname = \"custom\"\nwire_api = \"responses\"\nrequires_openai_auth = true\nbase_url = \"https://ai.hybgzs.com/v1\"\n"
        }
      },
      "sub2api-id": {
        "name": "sub2api",
        "settingsConfig": {
          "auth": {
            "OPENAI_API_KEY": "sub2api-key"
          },
          "config": "model_provider = \"custom\"\nmodel = \"gpt-5.6-luna\"\nmodel_reasoning_effort = \"max\"\ndisable_response_storage = true\n[model_providers.custom]\nname = \"custom\"\nwire_api = \"responses\"\nrequires_openai_auth = true\nbase_url = \"https://sub2api.example/v1\"\n[sandbox_workspace_write]\nnetwork_access = true\n[tui]\nstatus_line = [\"model-with-reasoning\"]\n[mcp_servers.stale]\ncommand = \"stale-mcp-command\"\n[projects.\"/tmp/stale-project\"]\ntrust_level = \"trusted\"\n"
        }
      },
      "deepseek-id": {
        "name": "DeepSeek",
        "settingsConfig": {
          "auth": {
            "OPENAI_API_KEY": "deepseek-key"
          },
          "config": "model_provider = \"custom\"\nmodel = \"gpt-5.6\"\nmodel_reasoning_effort = \"high\"\n[model_providers.custom]\nname = \"custom\"\nwire_api = \"responses\"\nrequires_openai_auth = true\nbase_url = \"https://api.deepseek.com\"\n",
          "modelCatalog": {
            "models": [
              {
                "model": "deepseek-v4-flash",
                "displayName": "DeepSeek V4 Flash",
                "contextWindow": 1048576
              },
              {
                "model": "deepseek-v4-pro",
                "displayName": "DeepSeek V4 Pro",
                "contextWindow": 1048576
              }
            ]
          }
        }
      },
      "official-id": {
        "name": "OpenAI Official",
        "settingsConfig": {
          "auth": {
            "OPENAI_API_KEY": null,
            "auth_mode": "chatgpt",
            "tokens": {
              "access_token": "official-token"
            }
          },
          "config": "model_provider = \"custom\"\nmodel = \"gpt-5.4\"\n[model_providers.custom]\nname = \"custom\"\nwire_api = \"responses\"\nrequires_openai_auth = true\nbase_url = \"https://api.openai.com/v1\"\n"
        }
      },
      "future-id": {
        "name": "Future Env",
        "settingsConfig": {
          "auth": {
            "CUSTOM_TOKEN": "future-key"
          },
          "config": "model_provider = \"custom\"\nmodel = \"future-model\"\n[model_providers.custom]\nname = \"custom\"\nwire_api = \"responses\"\nenv_key = \"CUSTOM_TOKEN\"\nbase_url = \"https://future.example/v1\"\n"
        }
      }
    }
  }
}
EOF

cat >"$MOCK_BIN/cc-switch" <<'EOF'
#!/usr/bin/env zsh
set -eo pipefail

if [[ "$1" == "config" && "$2" == "show" ]]; then
  print -- "Current Configuration"
  print -- "=================================================="
  cat "$AI_CLI_TEST_CONFIG"
  exit 0
fi

if [[ "$1" != "start" ]]; then
  print -u2 -- "unexpected cc-switch invocation: $*"
  exit 1
fi

app="$2"
selector="$3"
shift 3
[[ "$1" == "--" ]] || {
  print -u2 -- "missing native argument separator"
  exit 1
}
shift

if [[ "$selector" == "Zhipu GLM" ]]; then
  print -u2 -- "provider '$selector' is not configured for $app"
  exit 1
fi

print -- "CLI=$app"
print -- "SELECTOR=$selector"
print -- "ARG_COUNT=$#"
index=1
for arg in "$@"; do
  print -- "ARG_$index=$arg"
  (( index += 1 ))
done
EOF
chmod +x "$MOCK_BIN/cc-switch"

cat >"$MOCK_BIN/codex" <<'EOF'
#!/usr/bin/env zsh
set -eo pipefail

env_value() {
  printenv "$1" 2>/dev/null || true
}

profile=""
config_args=()
args=()
while (( $# )); do
  case "$1" in
    --profile|-p)
      profile="$2"
      shift 2
      ;;
    -c|--config)
      config_args+=("$2")
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

profile_file="$CODEX_HOME/$profile.config.toml"
print -- "CLI=codex"
print -- "CODEX_HOME=$CODEX_HOME"
print -- "PROFILE=$profile"
print -- "PROFILE_FILE=$profile_file"
if [[ -n "$profile" && -f "$profile_file" ]]; then
  print -- "PROFILE_CONTENT=$(tr '\n' ' ' <"$profile_file")"
fi
print -- "OPENAI_API_KEY=$(env_value OPENAI_API_KEY)"
print -- "CUSTOM_API_KEY=$(env_value CUSTOM_API_KEY)"
print -- "AI_CLI_CODEX_API_KEY=$(env_value AI_CLI_CODEX_API_KEY)"
print -- "CODEX_API_KEY=$(env_value CODEX_API_KEY)"
print -- "CODEX_ACCESS_TOKEN=$(env_value CODEX_ACCESS_TOKEN)"
print -- "CODEX_SQLITE_HOME=$(env_value CODEX_SQLITE_HOME)"
print -- "OPENAI_BASE_URL=$(env_value OPENAI_BASE_URL)"
print -- "HYB_API_KEY=$(env_value HYB_API_KEY)"
print -- "WJ_API_KEY=$(env_value WJ_API_KEY)"
print -- "CPA_API_KEY=$(env_value CPA_API_KEY)"
print -- "CUSTOM_TOKEN=$(env_value CUSTOM_TOKEN)"

config_count=0
for arg in $config_args; do
  (( config_count += 1 ))
  print -- "CONFIG_$config_count=$arg"
done
print -- "CONFIG_COUNT=$config_count"

arg_count=0
for arg in $args; do
  (( arg_count += 1 ))
  print -- "ARG_$arg_count=$arg"
done
print -- "ARG_COUNT=$arg_count"
EOF
chmod +x "$MOCK_BIN/codex"

cat >"$CODEX_HOME/auth.json" <<'EOF'
{
  "auth_mode": "chatgpt",
  "tokens": {
    "access_token": "official-token"
  }
}
EOF
auth_before=$(cat "$CODEX_HOME/auth.json")

export HOME="$WORK_HOME"
export CODEX_HOME="$CODEX_HOME"
source "$PLUGIN_FILE"

removed_claude_alias="cc"wj
if (( $+functions[$removed_claude_alias] )); then
  fail "removed Claude alias should not be defined"
fi

claude_output=$(deepseek --dangerously-skip-permissions "hello world")
assert_contains "$claude_output" "CLI=claude"
assert_contains "$claude_output" "SELECTOR=DeepSeek"
assert_contains "$claude_output" "ARG_COUNT=2"
assert_contains "$claude_output" "ARG_1=--dangerously-skip-permissions"
assert_contains "$claude_output" "ARG_2=hello world"

export OPENAI_API_KEY="stale-openai-key"
export CUSTOM_API_KEY="stale-custom-api-key"
export AI_CLI_CODEX_API_KEY="stale-ai-cli-key"
export CODEX_API_KEY="stale-codex-key"
export CODEX_ACCESS_TOKEN="stale-access-token"
export CODEX_SQLITE_HOME="/tmp/stale-codex-sqlite"
export OPENAI_BASE_URL="https://stale.example/v1"
export HYB_API_KEY="stale-hyb-key"
export CUSTOM_TOKEN="stale-custom-token"

codex_hyb_output=$(codex-hyb --model "gpt-5.4" "start shared session")
assert_contains "$codex_hyb_output" "CLI=codex"
assert_contains "$codex_hyb_output" "CODEX_HOME=$CODEX_HOME"
assert_contains "$codex_hyb_output" "PROFILE=hyb-id"
assert_contains "$codex_hyb_output" "PROFILE_FILE=$CODEX_HOME/hyb-id.config.toml"
assert_contains "$codex_hyb_output" "OPENAI_API_KEY="
assert_contains "$codex_hyb_output" "CUSTOM_API_KEY=hyb-key"
assert_contains "$codex_hyb_output" "AI_CLI_CODEX_API_KEY="
assert_contains "$codex_hyb_output" "CODEX_API_KEY="
assert_contains "$codex_hyb_output" "CODEX_ACCESS_TOKEN="
assert_contains "$codex_hyb_output" "CODEX_SQLITE_HOME="
assert_contains "$codex_hyb_output" "OPENAI_BASE_URL="
assert_contains "$codex_hyb_output" "HYB_API_KEY="
assert_contains "$codex_hyb_output" "PROFILE_CONTENT="
assert_contains "$codex_hyb_output" "requires_openai_auth = false"
assert_contains "$codex_hyb_output" 'env_key = "CUSTOM_API_KEY"'
assert_contains "$codex_hyb_output" "CONFIG_COUNT=0"
assert_contains "$codex_hyb_output" "ARG_COUNT=3"
assert_contains "$codex_hyb_output" "ARG_1=--model"
assert_contains "$codex_hyb_output" "ARG_2=gpt-5.4"
assert_contains "$codex_hyb_output" "ARG_3=start shared session"
assert_not_contains "$codex_hyb_output" "model_catalog_json ="
assert_file_contains "$CODEX_HOME/hyb-id.config.toml" 'base_url = "https://ai.hybgzs.com/v1"'
assert_file_contains "$CODEX_HOME/hyb-id.config.toml" "requires_openai_auth = false"
assert_file_contains "$CODEX_HOME/hyb-id.config.toml" 'env_key = "CUSTOM_API_KEY"'
[[ "$OPENAI_API_KEY" == "stale-openai-key" ]] || fail "provider auth leaked into the parent shell"
[[ "$CUSTOM_API_KEY" == "stale-custom-api-key" ]] || fail "custom auth leaked into the parent shell"
[[ "$AI_CLI_CODEX_API_KEY" == "stale-ai-cli-key" ]] || fail "legacy auth leaked into the parent shell"

codex_s2a_output=$(codex-s2a resume "019fd0c7-9ced-7732-b365-c429ce57e706")
assert_contains "$codex_s2a_output" "CODEX_HOME=$CODEX_HOME"
assert_contains "$codex_s2a_output" "PROFILE=sub2api-id"
assert_contains "$codex_s2a_output" "OPENAI_API_KEY="
assert_contains "$codex_s2a_output" "CUSTOM_API_KEY=sub2api-key"
assert_contains "$codex_s2a_output" "AI_CLI_CODEX_API_KEY="
assert_contains "$codex_s2a_output" "requires_openai_auth = false"
assert_contains "$codex_s2a_output" 'env_key = "CUSTOM_API_KEY"'
assert_not_contains "$codex_s2a_output" "disable_response_storage = true"
assert_not_contains "$codex_s2a_output" "[sandbox_workspace_write]"
assert_not_contains "$codex_s2a_output" "[tui]"
assert_not_contains "$codex_s2a_output" "stale-mcp-command"
assert_not_contains "$codex_s2a_output" "stale-project"
assert_contains "$codex_s2a_output" "CONFIG_COUNT=0"
assert_contains "$codex_s2a_output" "ARG_COUNT=2"
assert_contains "$codex_s2a_output" "ARG_1=resume"
assert_contains "$codex_s2a_output" "ARG_2=019fd0c7-9ced-7732-b365-c429ce57e706"
assert_file_contains "$CODEX_HOME/sub2api-id.config.toml" 'base_url = "https://sub2api.example/v1"'
assert_file_contains "$CODEX_HOME/sub2api-id.config.toml" "requires_openai_auth = false"
assert_file_contains "$CODEX_HOME/sub2api-id.config.toml" 'env_key = "CUSTOM_API_KEY"'

codex_ds_output=$(codex-ds mcp list)
assert_contains "$codex_ds_output" "CODEX_HOME=$CODEX_HOME"
assert_contains "$codex_ds_output" "PROFILE=deepseek-id"
assert_contains "$codex_ds_output" "CUSTOM_API_KEY=deepseek-key"
assert_contains "$codex_ds_output" "requires_openai_auth = false"
assert_contains "$codex_ds_output" 'env_key = "CUSTOM_API_KEY"'
assert_contains "$codex_ds_output" 'base_url = "https://api.deepseek.com"'
assert_contains "$codex_ds_output" 'model_catalog_json = "deepseek-id.model_catalog.json"'
assert_contains "$codex_ds_output" 'model = "deepseek-v4-flash"'
assert_contains "$codex_ds_output" 'model_reasoning_effort = "high"'
assert_contains "$codex_ds_output" "ARG_1=mcp"
assert_contains "$codex_ds_output" "ARG_2=list"
assert_file_contains "$CODEX_HOME/deepseek-id.config.toml" 'base_url = "https://api.deepseek.com"'
assert_file_contains "$CODEX_HOME/deepseek-id.config.toml" 'env_key = "CUSTOM_API_KEY"'
assert_file_contains "$CODEX_HOME/deepseek-id.config.toml" 'model_catalog_json = "deepseek-id.model_catalog.json"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"model": "deepseek-v4-flash"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"slug": "deepseek-v4-flash"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"display_name": "DeepSeek V4 Flash"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"context_window": 1048576'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"model": "deepseek-v4-pro"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"effort": "low"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"effort": "high"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"effort": "max"'
assert_file_contains "$CODEX_HOME/deepseek-id.model_catalog.json" '"default_reasoning_level": "high"'

deepseek_catalog_json=$(<"$CODEX_HOME/deepseek-id.model_catalog.json")
saved_deepseek_selection=$(_ai_cli_codex_model_catalog_selection \
  "$deepseek_catalog_json" \
  "deepseek-v4-pro" \
  "max" \
  "high")
assert_contains "$saved_deepseek_selection" '"model":"deepseek-v4-pro"'
assert_contains "$saved_deepseek_selection" '"reasoning_effort":"max"'

selection_profile=$(_ai_cli_prepare_codex_model_selection_profile \
  'model_provider = "custom"
model = "gpt-5.6"
model_reasoning_effort = "high"
[model_providers.custom]' \
  "deepseek-v4-pro" \
  "max")
assert_contains "$selection_profile" 'model = "deepseek-v4-pro"'
assert_contains "$selection_profile" 'model_reasoning_effort = "max"'

invalid_context_catalog='{"provider":{"settingsConfig":{"modelCatalog":{"models":[{"model":"fallback-model","displayName":"Fallback Model","contextWindow":"not-a-number"}]}}}}'
invalid_context_output=$(_ai_cli_codex_model_catalog_json "$invalid_context_catalog")
assert_contains "$invalid_context_output" '"context_window": 262144'

codex_official_output=$(codex-openai resume "019fd0c7-9ced-7732-b365-c429ce57e706")
assert_contains "$codex_official_output" "CODEX_HOME=$CODEX_HOME"
assert_contains "$codex_official_output" "PROFILE=official-id"
assert_contains "$codex_official_output" "OPENAI_API_KEY="
assert_contains "$codex_official_output" "CUSTOM_API_KEY="
assert_contains "$codex_official_output" "AI_CLI_CODEX_API_KEY="
assert_contains "$codex_official_output" "CODEX_API_KEY="
assert_contains "$codex_official_output" "CODEX_ACCESS_TOKEN="
assert_contains "$codex_official_output" "CODEX_SQLITE_HOME="
assert_contains "$codex_official_output" "OPENAI_BASE_URL="
assert_contains "$codex_official_output" "CONFIG_COUNT=0"
assert_contains "$codex_official_output" "requires_openai_auth = true"
assert_not_contains "$codex_official_output" 'env_key = "CUSTOM_API_KEY"'
assert_contains "$codex_official_output" "ARG_1=resume"
assert_contains "$codex_official_output" "ARG_2=019fd0c7-9ced-7732-b365-c429ce57e706"
assert_file_contains "$CODEX_HOME/official-id.config.toml" "requires_openai_auth = true"
[[ "$(cat "$CODEX_HOME/auth.json")" == "$auth_before" ]] || fail "official auth.json was modified"

future_output=$(_ai_cli_run_codex "Future Env" mcp list)
assert_contains "$future_output" "PROFILE=future-id"
assert_contains "$future_output" "CUSTOM_API_KEY=future-key"
assert_contains "$future_output" "AI_CLI_CODEX_API_KEY="
assert_contains "$future_output" "CUSTOM_TOKEN="
assert_contains "$future_output" "requires_openai_auth = false"
assert_contains "$future_output" 'env_key = "CUSTOM_API_KEY"'
assert_file_contains "$CODEX_HOME/future-id.config.toml" 'base_url = "https://future.example/v1"'
assert_file_contains "$CODEX_HOME/future-id.config.toml" 'env_key = "CUSTOM_API_KEY"'
[[ "$CUSTOM_TOKEN" == "stale-custom-token" ]] || fail "provider env leaked into the parent shell"

profile_arg_log="$TEST_ROOT/profile-arg.log"
if codex-s2a --profile other >"$profile_arg_log" 2>&1; then
  fail "expected provider alias to reject a conflicting --profile"
fi
profile_arg_output=$(cat "$profile_arg_log")
assert_contains "$profile_arg_output" "--profile is managed by the provider alias"

missing_provider_log="$TEST_ROOT/missing-provider.log"
if codex-cpa >"$missing_provider_log" 2>&1; then
  fail "expected codex-cpa to fail when provider is missing"
fi
missing_provider_output=$(cat "$missing_provider_log")
assert_contains "$missing_provider_output" "provider 'CPA' is not configured for codex"

missing_claude_provider_log="$TEST_ROOT/missing-claude-provider.log"
if glm >"$missing_claude_provider_log" 2>&1; then
  fail "expected glm to fail when provider is missing"
fi
missing_claude_provider_output=$(cat "$missing_claude_provider_log")
assert_contains "$missing_claude_provider_output" "provider 'Zhipu GLM' is not configured for claude"

missing_command_log="$TEST_ROOT/missing-command.log"
saved_path="$PATH"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
if deepseek >"$missing_command_log" 2>&1; then
  fail "expected deepseek to fail when cc-switch is missing"
fi
missing_command_output=$(cat "$missing_command_log")
assert_contains "$missing_command_output" "missing required command: cc-switch"
export PATH="$saved_path"

print -- "plugin smoke tests passed"
