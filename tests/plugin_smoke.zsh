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

SCRIPT_DIR=${0:A:h}
PLUGIN_FILE="$SCRIPT_DIR/../ai-cli.plugin.zsh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ai-cli-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

MOCK_BIN="$TEST_ROOT/bin"
WORK_HOME="$TEST_ROOT/home"
mkdir -p "$MOCK_BIN" "$WORK_HOME/.claude"

export AI_CLI_TEST_CONFIG="$TEST_ROOT/config.json"
export PATH="$MOCK_BIN:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cat >"$AI_CLI_TEST_CONFIG" <<'EOF'
{
  "claude": {
    "providers": {
      "claude-1": {
        "name": "DeepSeek",
        "settingsConfig": {
          "env": {
            "ANTHROPIC_AUTH_TOKEN": "deepseek-token",
            "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
            "ANTHROPIC_MODEL": "deepseek-chat"
          }
        }
      },
      "claude-2": {
        "name": "万界方舟",
        "settingsConfig": {
          "env": {
            "ANTHROPIC_AUTH_TOKEN": "ccwj-token",
            "ANTHROPIC_BASE_URL": "https://wj.example.com/anthropic",
            "ANTHROPIC_MODEL": "wanjie-claude"
          }
        }
      }
    }
  },
  "codex": {
    "providers": {
      "codex-1": {
        "name": "黑与白",
        "settingsConfig": {
          "auth": {
            "OPENAI_API_KEY": "hyb-key"
          },
          "config": "model_provider = \"custom\"\nmodel = \"gpt-5.4\"\n[model_providers.custom]\nname = \"custom\"\nwire_api = \"responses\"\nrequires_openai_auth = true\nbase_url = \"https://ai.hybgzs.com/v1\"\n\n[mcp_servers.context7]\nargs = [\"-y\", \"@upstash/context7-mcp\"]\n"
        }
      },
      "codex-2": {
        "name": "OpenAI Official",
        "settingsConfig": {
          "auth": {
            "OPENAI_API_KEY": null,
            "auth_mode": "chatgpt",
            "tokens": {
              "access_token": "token"
            }
          },
          "config": "model = \"gpt-5.4\"\n"
        }
      }
    }
  }
}
EOF

cat >"$MOCK_BIN/cc-switch" <<'EOF'
#!/usr/bin/env zsh
set -euo pipefail
if [[ "${1-}" == "config" && "${2-}" == "show" ]]; then
  print -- "Current Configuration"
  print -- "=================================================="
  cat "$AI_CLI_TEST_CONFIG"
  exit 0
fi
print -u2 -- "unexpected cc-switch invocation: $*"
exit 1
EOF
chmod +x "$MOCK_BIN/cc-switch"

cat >"$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env zsh
set -euo pipefail
settings_file=""
setting_sources=""
args=()
while (( $# )); do
  case "$1" in
    --settings)
      settings_file="$2"
      shift 2
      ;;
    --setting-sources)
      setting_sources="$2"
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
print -- "CLI=claude"
print -- "HOME=$HOME"
print -- "SETTING_SOURCES=$setting_sources"
print -- "SETTINGS_FILE=$settings_file"
print -- "ANTHROPIC_AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN-}"
print -- "ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL-}"
print -- "ANTHROPIC_MODEL=${ANTHROPIC_MODEL-}"
print -- "SETTINGS_ENV=$(jq -c '.env' "$settings_file")"
print -- "ARGS=${args[*]}"
EOF
chmod +x "$MOCK_BIN/claude"

cat >"$MOCK_BIN/codex" <<'EOF'
#!/usr/bin/env zsh
set -euo pipefail
config_args=()
args=()
while (( $# )); do
  case "$1" in
    -c)
      config_args+=("$2")
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
print -- "CLI=codex"
print -- "HOME=$HOME"
print -- "OPENAI_API_KEY=${OPENAI_API_KEY-}"
print -- "HYB_API_KEY=${HYB_API_KEY-}"
print -- "WJ_API_KEY=${WJ_API_KEY-}"
print -- "CPA_API_KEY=${CPA_API_KEY-}"
print -- "CONFIG_ARGS=${config_args[*]}"
print -- "ARGS=${args[*]}"
EOF
chmod +x "$MOCK_BIN/codex"

cat >"$MOCK_BIN/yj" <<'EOF'
#!/usr/bin/env zsh
set -euo pipefail
[[ "${1-}" == "-tj" ]] || {
  print -u2 -- "unexpected yj invocation: $*"
  exit 1
}
python3 -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(sys.stdin.buffer)))'
EOF
chmod +x "$MOCK_BIN/yj"

cat >"$WORK_HOME/.claude/settings.json" <<'EOF'
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "persisted-token"
  },
  "statusLine": {
    "type": "command"
  }
}
EOF

export HOME="$WORK_HOME"
source "$PLUGIN_FILE"

export ANTHROPIC_AUTH_TOKEN="old-token"
claude_output=$(deepseek "hello")
assert_contains "$claude_output" "CLI=claude"
assert_contains "$claude_output" "ANTHROPIC_AUTH_TOKEN=deepseek-token"
assert_contains "$claude_output" "ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic"
assert_contains "$claude_output" "SETTING_SOURCES=project,local"
assert_contains "$claude_output" "SETTINGS_FILE=/"
assert_contains "$claude_output" 'SETTINGS_ENV={}'

ccwj_output=$(ccwj "hello")
assert_contains "$ccwj_output" "CLI=claude"
assert_contains "$ccwj_output" "ANTHROPIC_AUTH_TOKEN=ccwj-token"
assert_contains "$ccwj_output" "ANTHROPIC_BASE_URL=https://wj.example.com/anthropic"

codex_custom_output=$(codex-hyb "ship it")
assert_contains "$codex_custom_output" "CLI=codex"
assert_contains "$codex_custom_output" "OPENAI_API_KEY="
assert_contains "$codex_custom_output" "HYB_API_KEY=hyb-key"
assert_contains "$codex_custom_output" 'model_provider="custom"'
assert_contains "$codex_custom_output" 'model_providers.custom.base_url="https://ai.hybgzs.com/v1"'
assert_contains "$codex_custom_output" 'model_providers.custom.env_key="HYB_API_KEY"'
assert_contains "$codex_custom_output" 'mcp_servers.context7.args=["-y","@upstash/context7-mcp"]'

codex_official_output=$(codex-openai "official")
assert_contains "$codex_official_output" "CLI=codex"
assert_contains "$codex_official_output" "OPENAI_API_KEY="
assert_contains "$codex_official_output" 'model="gpt-5.4"'

missing_provider_log="$TEST_ROOT/missing-provider.log"
if glm >"$missing_provider_log" 2>&1; then
  fail "expected glm to fail when provider is missing"
fi
missing_provider_output=$(cat "$missing_provider_log")
assert_contains "$missing_provider_output" "provider 'Zhipu GLM' is not configured for claude"

cc_switch_path="$MOCK_BIN/cc-switch"
mv "$cc_switch_path" "$cc_switch_path.disabled"
missing_command_log="$TEST_ROOT/missing-command.log"
if deepseek >"$missing_command_log" 2>&1; then
  fail "expected deepseek to fail when cc-switch is missing"
fi
missing_command_output=$(cat "$missing_command_log")
assert_contains "$missing_command_output" "missing required command: cc-switch"
mv "$cc_switch_path.disabled" "$cc_switch_path"

print -- "plugin smoke tests passed"
