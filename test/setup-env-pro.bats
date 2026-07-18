#!/usr/bin/env bats
# setup.sh: .env.pro flow (proxy_host + proxy_key applied to all 3 profiles).
# .env.pro is gitignored and may hold a real key on this machine — every test here stages
# a throwaway copy of the repo with a FAKE .env.pro, so the real file is never read or touched.

load test_helper.bash

TEST_HOST="https://fake-proxy.test/v1"
TEST_KEY="fake-test-key-12345"

stage_repo() {
  ROOT="$(repo_root)"
  STAGE="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE/hooks" "$STAGE/profiles"
  cp "$ROOT/setup.sh" "$STAGE/setup.sh"
  cp "$ROOT/ccswitch.sh" "$STAGE/ccswitch.sh"
  cp "$ROOT/hooks/check-router.sh" "$STAGE/hooks/check-router.sh"
  cp "$ROOT/profiles/claude.json" "$ROOT/profiles/codex.json" "$ROOT/profiles/deepseek.json" "$STAGE/profiles/"
}

write_fake_env_pro() {
  # $1 = host line (empty to omit), $2 = key line (empty to omit)
  : > "$STAGE/.env.pro"
  if [ -n "${1:-}" ]; then echo "proxy_host=$1" >> "$STAGE/.env.pro"; fi
  if [ -n "${2:-}" ]; then echo "proxy_key=$2" >> "$STAGE/.env.pro"; fi
}

setup() {
  setup_fake_home
  stage_repo
}

@test "non-interactive: .env.pro with both values is applied to all 3 profiles by default" {
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  run bash -c "cd '$STAGE' && bash setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-interactive shell — using proxy_host + proxy_key from .env.pro (default Yes)"* ]]
  [[ "$output" == *".env.pro proxy_host + proxy_key applied to profiles/"* ]]
  for p in claude codex deepseek; do
    host=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/$p.json")
    key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/$p.json")
    [ "$host" = "$TEST_HOST" ]
    [ "$key" = "$TEST_KEY" ]
  done
}

@test "non-interactive: .env.pro is ignored when proxy_key is missing" {
  write_fake_env_pro "$TEST_HOST" ""
  run bash -c "cd '$STAGE' && bash setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env.pro found but missing proxy_host/proxy_key — ignored"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [[ "$key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: .env.pro is ignored when proxy_host is missing" {
  write_fake_env_pro "" "$TEST_KEY"
  run bash -c "cd '$STAGE' && bash setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env.pro found but missing proxy_host/proxy_key — ignored"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [[ "$key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: missing .env.pro falls through untouched (no crash, placeholders kept)" {
  run bash -c "cd '$STAGE' && bash setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *".env.pro"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [[ "$key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: .env.pro is NOT applied when a profile already holds a real key" {
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  mkdir -p "$HOME/.claude/profiles"
  jq '.ANTHROPIC_AUTH_TOKEN = "existing-real-key"' "$STAGE/profiles/claude.json" > "$HOME/.claude/profiles/claude.json"
  run bash -c "cd '$STAGE' && bash setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profiles already hold a key — kept"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$key" = "existing-real-key" ]
}

@test "interactive: default Enter (Yes) applies .env.pro to all 3 profiles (pty)" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  run expect -c "
    set timeout 10
    spawn bash -c \"cd '$STAGE' && bash setup.sh\"
    expect \"Use proxy_host + proxy_key from .env.pro*\"
    send \"\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  for p in claude codex deepseek; do
    host=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/$p.json")
    key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/$p.json")
    [ "$host" = "$TEST_HOST" ]
    [ "$key" = "$TEST_KEY" ]
  done
}

@test "interactive: answering no falls back to manual host+key prompts, Enter-skip keeps placeholders (pty)" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  run expect -c "
    set timeout 10
    spawn bash -c \"cd '$STAGE' && bash setup.sh\"
    expect \"Use proxy_host + proxy_key from .env.pro*\"
    send \"n\r\"
    expect \"Router base URL*\"
    send \"\r\"
    expect \"Paste the shared 9router key*\"
    send \"\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  orig_host=$(jq -r '.ANTHROPIC_BASE_URL' "$STAGE/profiles/claude.json")
  host=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/claude.json")
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$host" = "$orig_host" ]
  [[ "$key" == *"<your-9router-key>"* ]]
}
