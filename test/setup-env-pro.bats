#!/usr/bin/env bats
# setup.sh: .env proxy flow (proxy_host + proxy_key applied to all 3 profiles).
# .env is gitignored and may hold a real key on this machine — every test stages
# a throwaway copy repo into a FAKE .env, so the real file is never touched.

load test_helper.bash

TEST_HOST="https://fake-proxy.test/v1"
TEST_KEY="fake-test-key-12345"

stage_repo() {
  ROOT="$(repo_root)"
  STAGE="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE/ai-proxy/hooks" "$STAGE/ai-proxy/profiles"
  cp "$ROOT/ai-proxy/setup.sh" "$STAGE/ai-proxy/setup.sh"
  cp "$ROOT/ai-proxy/ccswitch.sh" "$STAGE/ai-proxy/ccswitch.sh"
  cp "$ROOT/ai-proxy/statusline-context.sh" "$STAGE/ai-proxy/statusline-context.sh"
  cp "$ROOT/ai-proxy/hooks/check-router.sh" "$STAGE/ai-proxy/hooks/check-router.sh"
  cp "$ROOT/ai-proxy/profiles/claude.json" "$ROOT/ai-proxy/profiles/codex.json" "$ROOT/ai-proxy/profiles/deepseek.json" "$ROOT/ai-proxy/profiles/kimi.json" "$STAGE/ai-proxy/profiles/"
}

write_fake_env_pro() {
  # $1 = host line (empty to omit), $2 = key line (empty to omit)
  : > "$STAGE/.env"
  if [ -n "${1:-}" ]; then echo "proxy_host=$1" >> "$STAGE/.env"; fi
  if [ -n "${2:-}" ]; then echo "proxy_key=$2" >> "$STAGE/.env"; fi
}

write_fake_kimi_env() {
  : > "$STAGE/.env"
  echo "kimi_api_key_force_subscription=1" >> "$STAGE/.env"
  if [ -n "${1:-}" ]; then echo "kimi_api_key=$1" >> "$STAGE/.env"; fi
}

setup() {
  setup_fake_home
  stage_repo
}

@test "non-interactive: .env with both values is applied to all 3 profiles by default" {
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  run bash -c "cd '$STAGE' && bash ai-proxy/setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-interactive shell — using proxy_host + proxy_key from .env (default Yes)"* ]]
  [[ "$output" == *".env proxy_host + proxy_key applied to profiles/"* ]]
  for p in claude codex deepseek; do
    host=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/$p.json")
    key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/$p.json")
    [ "$host" = "$TEST_HOST" ]
    [ "$key" = "$TEST_KEY" ]
  done
}

@test "non-interactive: .env is ignored when proxy_key is missing" {
  write_fake_env_pro "$TEST_HOST" ""
  run bash -c "cd '$STAGE' && bash ai-proxy/setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env found but missing proxy_host/proxy_key — ignored"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [[ "$key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: .env is ignored when proxy_host is missing" {
  write_fake_env_pro "" "$TEST_KEY"
  run bash -c "cd '$STAGE' && bash ai-proxy/setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env found but missing proxy_host/proxy_key — ignored"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [[ "$key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: missing .env falls through untouched (no crash, placeholders kept)" {
  run bash -c "cd '$STAGE' && bash ai-proxy/setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *".env "* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [[ "$key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: .env ALWAYS overrides even when a profile already holds a real key" {
  # design (setup.sh 2b): .env is the source of truth. When both proxy_host and
  # proxy_key are present it overwrites all three profiles unconditionally — a
  # pre-existing real key is replaced, and a notice is printed so the override
  # is not silent.
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  mkdir -p "$HOME/.claude/profiles"
  jq '.ANTHROPIC_AUTH_TOKEN = "existing-real-key"' "$STAGE/ai-proxy/profiles/claude.json" > "$HOME/.claude/profiles/claude.json"
  run bash -c "cd '$STAGE' && bash ai-proxy/setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env always overrides"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$key" = "$TEST_KEY" ]
}

@test "interactive: a complete .env auto-applies to all 3 profiles with no prompt (pty)" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  # With both proxy_host + proxy_key present, setup.sh applies unconditionally — there is
  # no interactive confirmation to answer, even on a real tty. It should reach eof on its own.
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  run expect -c "
    set timeout 10
    spawn bash -c \"cd '$STAGE' && bash ai-proxy/setup.sh\"
    expect \".env proxy_host + proxy_key applied to profiles/*\"
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

@test "interactive: no .env falls back to manual host+key prompts, Enter-skip keeps placeholders (pty)" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  # With no .env present, an interactive tty gets the manual prompts (base URL, then
  # shared key). Enter at each keeps the current placeholders untouched.
  rm -f "$STAGE/.env"
  run expect -c "
    set timeout 10
    spawn bash -c \"cd '$STAGE' && bash ai-proxy/setup.sh\"
    expect \"Router base URL*\"
    send \"\r\"
    expect \"Paste the shared 9router key*\"
    send \"\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  orig_host=$(jq -r '.ANTHROPIC_BASE_URL' "$STAGE/ai-proxy/profiles/claude.json")
  host=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/claude.json")
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$host" = "$orig_host" ]
  [[ "$key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: kimi force subscription applies kimi_api_key only to kimi profile" {
  write_fake_kimi_env "$TEST_KEY"
  run bash -c "cd '$STAGE' && bash ai-proxy/setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env kimi_api_key applied to profiles/kimi.json"* ]]
  base=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/kimi.json")
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/kimi.json")
  claude_key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$base" = "https://api.moonshot.ai/anthropic" ]
  [ "$key" = "$TEST_KEY" ]
  [[ "$claude_key" == *"<your-9router-key>"* ]]
}

@test "non-interactive: kimi force subscription without key leaves placeholder" {
  write_fake_kimi_env ""
  run bash -c "cd '$STAGE' && bash ai-proxy/setup.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kimi_api_key_force_subscription=1 but kimi_api_key missing"* ]]
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/kimi.json")
  [[ "$key" == *"<your-9router-key>"* ]]
}
