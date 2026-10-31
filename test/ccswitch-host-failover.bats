#!/usr/bin/env bats
# Router host failover: priority = hosts in ~/.claude/.ccswitch-hosts order (9router → 9router2 …)
# → subscription. TTY asks the user; non-TTY (SessionStart hook) follows priority on its own.
# Every host change must be announced (CLI notice + hook systemMessage).

load test_helper.bash

PRIMARY="https://9router.proxy.example.com/v1"
BACKUP="https://9router2.proxy.example.com/v1"

# stub_curl_hosts — fake curl: URL containing any substring in $STUB_DOWN (space-separated)
# → 530, otherwise 200. Writes '{}' to -o target so jq on the response never chokes.
stub_curl_hosts() {
  local dir="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$dir"
  cat > "$dir/curl" <<'STUB'
#!/usr/bin/env bash
out=""; prev=""; url=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  case "$a" in http*) url="$a" ;; esac
  prev="$a"
done
[ -n "$out" ] && [ "$out" != "/dev/null" ] && printf '{}' > "$out"
for d in ${STUB_DOWN:-}; do
  case "$url" in *"$d"*) printf '530'; exit 0 ;; esac
done
printf '200'
STUB
  chmod +x "$dir/curl"
  printf '#!/usr/bin/env bash\nexit 44\n' > "$dir/security"
  chmod +x "$dir/security"
  export PATH="$dir:$PATH"
}

fake_oauth_cred() {
  echo '{"claudeAiOauth":{"subscriptionType":"max"}}' > "$HOME/.claude/.credentials.json"
}

setup() {
  setup_fake_home
  stub_curl_hosts
  ROOT="$(repo_root)"
  CC="$HOME/.claude/ccswitch.sh"
  CHECK_ROUTER="$ROOT/ai-proxy/hooks/check-router.sh"
  mkdir -p "$HOME/.claude/profiles"
  for p in claude codex deepseek; do
    jq --arg u "$PRIMARY" '.ANTHROPIC_BASE_URL = $u | .ANTHROPIC_AUTH_TOKEN = "k"' \
      "$ROOT/ai-proxy/profiles/$p.json" > "$HOME/.claude/profiles/$p.json"
  done
  printf '%s\n%s\n' "$PRIMARY" "$BACKUP" > "$HOME/.claude/.ccswitch-hosts"
  cp "$ROOT/ai-proxy/ccswitch.sh" "$CC"
  chmod +x "$CC"
  echo '{}' > "$HOME/.claude/settings.json"
  "$CC" claude >/dev/null
}

@test "fallback (no TTY): primary down, backup healthy → switches host + announces it" {
  STUB_DOWN="9router.proxy" run "$CC" fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"ĐÃ ĐỔI HOST router: $PRIMARY → $BACKUP"* ]]
  [ "$(jq -r '.env.ANTHROPIC_BASE_URL' "$HOME/.claude/settings.json")" = "$BACKUP" ]
  for p in claude codex deepseek; do
    [ "$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/$p.json")" = "$BACKUP" ]
  done
  # failover order unchanged: primary keeps priority
  [ "$(head -1 "$HOME/.claude/.ccswitch-hosts")" = "$PRIMARY" ]
}

@test "fallback keeps the active profile (codex) when switching host" {
  "$CC" codex >/dev/null
  STUB_DOWN="9router.proxy" run "$CC" fallback
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$HOME/.claude/settings.json")" == cx/* ]]
  [ "$(jq -r '.env.ANTHROPIC_BASE_URL' "$HOME/.claude/settings.json")" = "$BACKUP" ]
}

@test "fallback: all hosts down + OAuth login → subscription" {
  fake_oauth_cred
  STUB_DOWN="9router.proxy 9router2.proxy" run "$CC" fallback
  [ "$status" -eq 0 ]
  [ "$(jq 'has("env")' "$HOME/.claude/settings.json")" = "false" ]
  [ "$(cat "$HOME/.claude/.ccswitch-target")" = "subscription" ]
}

@test "fallback: all hosts down + no OAuth login → keeps router unchanged" {
  before=$(cat "$HOME/.claude/settings.json")
  STUB_DOWN="9router.proxy 9router2.proxy" run "$CC" fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"Keeping router"* ]]
  [ "$before" = "$(cat "$HOME/.claude/settings.json")" ]
}

@test "fallback: on backup host and primary recovered → returns to primary + announces" {
  STUB_DOWN="9router.proxy" "$CC" fallback >/dev/null
  run "$CC" fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"ĐÃ ĐỔI HOST router: $BACKUP → $PRIMARY"* ]]
  [ "$(jq -r '.env.ANTHROPIC_BASE_URL' "$HOME/.claude/settings.json")" = "$PRIMARY" ]
}

@test "use-host without hosts file seeds the old host first, then the new one" {
  rm -f "$HOME/.claude/.ccswitch-hosts"
  run "$CC" use-host "$BACKUP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ĐÃ ĐỔI HOST"* ]]
  [ "$(sed -n 1p "$HOME/.claude/.ccswitch-hosts")" = "$PRIMARY" ]
  [ "$(sed -n 2p "$HOME/.claude/.ccswitch-hosts")" = "$BACKUP" ]
  [ "$(jq -r '.env.ANTHROPIC_BASE_URL' "$HOME/.claude/settings.json")" = "$BACKUP" ]
}

@test "use-host does not rewrite a non-router profile (kimi direct endpoint)" {
  jq '.ANTHROPIC_BASE_URL = "https://kimi.direct.test/anthropic"' "$ROOT/ai-proxy/profiles/kimi.json" \
    > "$HOME/.claude/profiles/kimi.json"
  run "$CC" use-host "$BACKUP"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/kimi.json")" = "https://kimi.direct.test/anthropic" ]
}

@test "use-host with no URL fails with usage" {
  run "$CC" use-host
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: ccswitch use-host"* ]]
}

@test "hosts list shows failover order with health" {
  STUB_DOWN="9router.proxy" run "$CC" hosts
  [ "$status" -eq 0 ]
  [[ "$output" == *"1) $PRIMARY  [530 DOWN]"* ]]
  [[ "$output" == *"2) $BACKUP  [200 OK]"* ]]
}

@test "check-router.sh: primary down → switches to backup and tells the user via systemMessage" {
  run env HOME="$HOME" STUB_DOWN="9router.proxy" bash "$CHECK_ROUTER"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.env.ANTHROPIC_BASE_URL' "$HOME/.claude/settings.json")" = "$BACKUP" ]
  json=$(printf '%s\n' "$output" | grep '^{"systemMessage"')
  [[ "$(printf '%s' "$json" | jq -r .systemMessage)" == *"ĐÃ ĐỔI HOST sang $BACKUP"* ]]
}

@test "check-router.sh: backup host is still recognised as router (banner warns backup in use)" {
  STUB_DOWN="9router.proxy" "$CC" fallback >/dev/null
  run env HOME="$HOME" STUB_DOWN="9router.proxy" bash "$CHECK_ROUTER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HOST DỰ PHÒNG"* ]]
  [[ "$output" == *"health=200 OK"* ]]
}

@test "fallback (TTY): primary down → menu asks, default = healthy backup" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  run env STUB_DOWN="9router.proxy" expect -c "
    set timeout 10
    spawn \"$CC\" fallback
    expect \"chọn*:\"
    send \"\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"đổi host → $BACKUP"* ]]
  [ "$(jq -r '.env.ANTHROPIC_BASE_URL' "$HOME/.claude/settings.json")" = "$BACKUP" ]
}

@test "fallback (TTY): user picks subscription from the menu" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  run env STUB_DOWN="9router.proxy" expect -c "
    set timeout 10
    spawn \"$CC\" fallback
    expect \"chọn*:\"
    send \"s\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  [ "$(jq 'has("env")' "$HOME/.claude/settings.json")" = "false" ]
}
