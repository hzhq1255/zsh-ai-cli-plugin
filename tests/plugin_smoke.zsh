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

SCRIPT_DIR=${0:A:h}
PLUGIN_FILE="$SCRIPT_DIR/../ai-cli.plugin.zsh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ai-cli-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

MOCK_BIN="$TEST_ROOT/bin"
mkdir -p "$MOCK_BIN"

export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

cat >"$MOCK_BIN/cc-switch" <<'EOF'
#!/usr/bin/env zsh
set -euo pipefail
if [[ "${1-}" != "start" ]]; then
  print -u2 -- "unexpected cc-switch invocation: $*"
  exit 1
fi
app="${2-}"
selector="${3-}"
shift 3
[[ "${1-}" == "--" ]] || {
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

source "$PLUGIN_FILE"

claude_output=$(deepseek --dangerously-skip-permissions "hello world")
assert_contains "$claude_output" "CLI=claude"
assert_contains "$claude_output" "SELECTOR=DeepSeek"
assert_contains "$claude_output" "ARG_COUNT=2"
assert_contains "$claude_output" "ARG_1=--dangerously-skip-permissions"
assert_contains "$claude_output" "ARG_2=hello world"

ccwj_output=$(ccwj "hello")
assert_contains "$ccwj_output" "CLI=claude"
assert_contains "$ccwj_output" "SELECTOR=万界方舟"

codex_custom_output=$(codex-hyb --model "gpt-5.4" "ship it")
assert_contains "$codex_custom_output" "CLI=codex"
assert_contains "$codex_custom_output" "SELECTOR=黑与白"
assert_contains "$codex_custom_output" "ARG_COUNT=3"
assert_contains "$codex_custom_output" "ARG_1=--model"
assert_contains "$codex_custom_output" "ARG_2=gpt-5.4"
assert_contains "$codex_custom_output" "ARG_3=ship it"

codex_hc_output=$(codex-hc "hc prompt")
assert_contains "$codex_hc_output" "CLI=codex"
assert_contains "$codex_hc_output" "SELECTOR=hc"
assert_contains "$codex_hc_output" "ARG_COUNT=1"
assert_contains "$codex_hc_output" "ARG_1=hc prompt"

codex_official_output=$(codex-openai "official")
assert_contains "$codex_official_output" "CLI=codex"
assert_contains "$codex_official_output" "SELECTOR=OpenAI Official"

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
