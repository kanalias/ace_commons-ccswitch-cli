#!/usr/bin/env bats
# Regression: `ccswitch fallback` and check-router.sh must never PROMOTE subscription
# back to a router profile, and setup.sh must never re-activate `claude` on a re-install
# once the user has a persisted target (marker file or settings.json env block).
#
# Root cause: with no env block (= subscription), `fallback` resolved
# active_router_profile() -> defaulted to "claude", probed it, got 200, and APPLIED it —
# silently putting the 9router env back into settings.json under a still-running session.

load test_helper.bash

# stub_curl <http-code> — prepend a fake `curl` on PATH that ignores its args and always
# reports <http-code> via -w "%{http_code}" (writes an empty JSON body to -o's target file
# when one is given, so `jq` on the response doesn't choke).
stub_curl() {
  local code="$1"
  local dir="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$dir"
  cat > "$dir/curl" <<STUB
#!/usr/bin/env bash
out=""
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-o" ]; then out="\$a"; fi
  prev="\$a"
done
if [ -n "\$out" ] && [ "\$out" != "/dev/null" ]; then
  printf '{}' > "\$out"
fi
printf '%s' "$code"
STUB
  chmod +x "$dir/curl"
  export PATH="$dir:$PATH"
}

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  CC="$ROOT/ai-proxy/ccswitch.sh"
  CHECK_ROUTER="$ROOT/ai-proxy/hooks/check-router.sh"
  mkdir -p "$HOME/.claude/profiles"
  cp "$ROOT/ai-proxy/profiles/claude.json" "$HOME/.claude/profiles/claude.json"
  cp "$ROOT/ai-proxy/profiles/codex.json" "$HOME/.claude/profiles/codex.json"
  cp "$ROOT/ai-proxy/profiles/deepseek.json" "$HOME/.claude/profiles/deepseek.json"
  cp "$ROOT/ai-proxy/profiles/kimi.json" "$HOME/.claude/profiles/kimi.json"
  cp "$ROOT/ai-proxy/ccswitch.sh" "$HOME/.claude/ccswitch.sh"
  chmod +x "$HOME/.claude/ccswitch.sh"
}

@test "fallback on subscription (healthy router stub) does NOT promote back to router" {
  echo '{}' > "$HOME/.claude/settings.json"
  stub_curl 200
  run "$CC" fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"fallback never promotes to a router"* ]]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
  # marker untouched by a no-op fallback (still absent — nothing was ever applied)
  [ ! -f "$HOME/.claude/.ccswitch-target" ]
}

@test "fallback on active router + healthy stub leaves settings.json byte-identical" {
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
  before=$(cat "$HOME/.claude/settings.json")
  before_marker=$(cat "$HOME/.claude/.ccswitch-target")
  stub_curl 200
  run "$CC" fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"router healthy: claude (no change)"* ]]
  after=$(cat "$HOME/.claude/settings.json")
  [ "$before" = "$after" ]
  after_marker=$(cat "$HOME/.claude/.ccswitch-target")
  [ "$before_marker" = "$after_marker" ]
}

@test "fallback on active router + dead stub (000) drops to subscription and marks it" {
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
  stub_curl 000
  run "$CC" fallback
  [ "$status" -eq 0 ]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
  marker=$(cat "$HOME/.claude/.ccswitch-target")
  [ "$marker" = "subscription" ]
}

@test "ccswitch subscription writes marker 'subscription'" {
  echo '{}' > "$HOME/.claude/settings.json"
  run "$CC" subscription
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/.ccswitch-target" ]
  marker=$(cat "$HOME/.claude/.ccswitch-target")
  [ "$marker" = "subscription" ]
}

@test "ccswitch claude writes marker 'claude'" {
  echo '{}' > "$HOME/.claude/settings.json"
  run "$CC" claude
  [ "$status" -eq 0 ]
  marker=$(cat "$HOME/.claude/.ccswitch-target")
  [ "$marker" = "claude" ]
}

@test "check-router.sh: process env still router but settings.json is subscription -> no mutation, exit 0" {
  echo '{}' > "$HOME/.claude/settings.json"
  stub_curl 000
  run env ANTHROPIC_BASE_URL="https://9router.proxy.example.com/v1" \
      ANTHROPIC_DEFAULT_OPUS_MODEL="cc/claude-opus-5" \
      HOME="$HOME" bash "$CHECK_ROUTER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cần restart Claude Code"* ]]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
}

@test "check-router.sh: router active in settings.json + dead stub auto-switches to subscription" {
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
  stub_curl 000
  run env -u ANTHROPIC_BASE_URL -u ANTHROPIC_DEFAULT_OPUS_MODEL HOME="$HOME" bash "$CHECK_ROUTER"
  [ "$status" -eq 0 ]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
  marker=$(cat "$HOME/.claude/.ccswitch-target")
  [ "$marker" = "subscription" ]
}
