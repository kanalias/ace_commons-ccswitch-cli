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

# stub_security_none — fake macOS `security` that never finds a keychain item, so the OAuth
# credential check is decided only by the fake $HOME (never the real keychain of the test machine).
stub_security_none() {
  local dir="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\nexit 44\n' > "$dir/security"
  chmod +x "$dir/security"
  export PATH="$dir:$PATH"
}

# fake_oauth_cred — this machine HAS a Claude Code OAuth login (linux-style credential file).
fake_oauth_cred() {
  mkdir -p "$HOME/.claude"
  echo '{"claudeAiOauth":{"subscriptionType":"max"}}' > "$HOME/.claude/.credentials.json"
}

setup() {
  setup_fake_home
  stub_security_none
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
  fake_oauth_cred
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
  fake_oauth_cred
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

# Incident 2026-10-12 (MacMini2): router restarted for ~2 min, a `claude` spawn hit the
# SessionStart hook, fallback dropped to subscription on a machine with NO OAuth login ->
# every later `claude` said "Not logged in" for 16h (fallback never promotes back).

@test "fallback on active router + dead stub but NO OAuth credential keeps the router (no dead harbor)" {
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
  before=$(cat "$HOME/.claude/settings.json")
  stub_curl 000
  run "$CC" fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO OAuth credential"* ]]
  after=$(cat "$HOME/.claude/settings.json")
  [ "$before" = "$after" ]
  marker=$(cat "$HOME/.claude/.ccswitch-target")
  [ "$marker" = "claude" ]
}

@test "check-router.sh: dead router + NO OAuth credential -> no mutation, no restart hint" {
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
  before=$(cat "$HOME/.claude/settings.json")
  stub_curl 000
  run env -u ANTHROPIC_BASE_URL -u ANTHROPIC_DEFAULT_OPUS_MODEL HOME="$HOME" bash "$CHECK_ROUTER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO OAuth credential"* ]]
  [[ "$output" != *"để nạp endpoint mới"* ]]
  after=$(cat "$HOME/.claude/settings.json")
  [ "$before" = "$after" ]
  marker=$(cat "$HOME/.claude/.ccswitch-target")
  [ "$marker" = "claude" ]
}

@test "ccswitch subscription (manual) still works without an OAuth credential" {
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
  run "$CC" subscription
  [ "$status" -eq 0 ]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
}

# Custom-host regression: real installs route through a router host that is NOT the repo's
# placeholder (*9router.proxy.example.com*) — set via setup.sh .env AI_9ROUTER_BASE_URL / `ccswitch
# set-host`. is_router_url() must still recognize it (host matches a profile's
# ANTHROPIC_BASE_URL), not fall through to "custom".

@test "ccswitch check/current tags a custom router host (not the placeholder) as its target, not custom" {
  local custom="https://router.custom.test/v1"
  for p in claude codex deepseek kimi; do
    tmp=$(mktemp)
    jq --arg url "$custom" '.ANTHROPIC_BASE_URL = $url' "$HOME/.claude/profiles/$p.json" > "$tmp"
    mv "$tmp" "$HOME/.claude/profiles/$p.json"
  done
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
  stub_curl 000
  run "$CC" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"→  claude"* ]]
  [[ "$output" != *"→  custom"* ]]
}

@test "check-router.sh: custom router host active + dead stub still auto-switches to subscription" {
  fake_oauth_cred
  local custom="https://router.custom.test/v1"
  for p in claude codex deepseek kimi; do
    tmp=$(mktemp)
    jq --arg url "$custom" '.ANTHROPIC_BASE_URL = $url' "$HOME/.claude/profiles/$p.json" > "$tmp"
    mv "$tmp" "$HOME/.claude/profiles/$p.json"
  done
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

@test "check-router.sh: settings.json env points to an unrelated non-router host -> no mutation" {
  echo '{"env":{"ANTHROPIC_BASE_URL":"https://other.test/v1"}}' > "$HOME/.claude/settings.json"
  stub_curl 000
  run env -u ANTHROPIC_BASE_URL -u ANTHROPIC_DEFAULT_OPUS_MODEL HOME="$HOME" bash "$CHECK_ROUTER"
  [ "$status" -eq 0 ]
  after=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$HOME/.claude/settings.json")
  [ "$after" = "https://other.test/v1" ]
}

@test "check-router.sh: process env on custom-host router but settings.json is subscription -> warns, no mutation" {
  local custom="https://router.custom.test/v1"
  for p in claude codex deepseek kimi; do
    tmp=$(mktemp)
    jq --arg url "$custom" '.ANTHROPIC_BASE_URL = $url' "$HOME/.claude/profiles/$p.json" > "$tmp"
    mv "$tmp" "$HOME/.claude/profiles/$p.json"
  done
  echo '{}' > "$HOME/.claude/settings.json"
  stub_curl 000
  run env ANTHROPIC_BASE_URL="$custom" \
      ANTHROPIC_DEFAULT_OPUS_MODEL="cc/claude-opus-5" \
      HOME="$HOME" bash "$CHECK_ROUTER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cần restart Claude Code"* ]]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
}
