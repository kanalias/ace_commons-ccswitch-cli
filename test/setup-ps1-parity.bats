#!/usr/bin/env bats
# setup.ps1: Windows PowerShell parity with setup.sh's .env proxy flow + no .model pin.
# Skips entirely if pwsh isn't installed (CI machine may not have it).
# Every test stages a throwaway copy of ai-proxy/ + a fake $env:USERPROFILE home, so the
# real .env / real ~/.claude of the machine running the tests is never touched.

load test_helper.bash

TEST_HOST="https://fake-proxy.test/v1"
TEST_KEY="fake-test-key-12345"

stage_repo() {
  ROOT="$(repo_root)"
  STAGE="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE/ai-proxy/hooks" "$STAGE/ai-proxy/profiles"
  cp "$ROOT/ai-proxy/setup.ps1" "$STAGE/ai-proxy/setup.ps1"
  cp "$ROOT/ai-proxy/ccswitch.ps1" "$STAGE/ai-proxy/ccswitch.ps1"
  cp "$ROOT/ai-proxy/statusline-context.sh" "$STAGE/ai-proxy/statusline-context.sh"
  cp "$ROOT/ai-proxy/hooks/check-router.sh" "$STAGE/ai-proxy/hooks/check-router.sh"
  cp "$ROOT/ai-proxy/profiles/claude.json" "$ROOT/ai-proxy/profiles/codex.json" "$ROOT/ai-proxy/profiles/deepseek.json" "$ROOT/ai-proxy/profiles/kimi.json" "$STAGE/ai-proxy/profiles/"
}

write_fake_env_pro() {
  # $1 = host line (empty to omit), $2 = key line (empty to omit)
  : > "$STAGE/.env"
  [ -n "${1:-}" ] && echo "proxy_host=$1" >> "$STAGE/.env"
  [ -n "${2:-}" ] && echo "proxy_key=$2" >> "$STAGE/.env"
}

write_fake_kimi_env() {
  : > "$STAGE/.env"
  echo "kimi_api_key_force_subscription=1" >> "$STAGE/.env"
  if [ -n "${1:-}" ]; then echo "kimi_api_key=$1" >> "$STAGE/.env"; fi
}

setup() {
  command -v pwsh >/dev/null 2>&1 || skip "pwsh not installed"
  setup_fake_home
  stage_repo
  # setup.ps1 reads $env:USERPROFILE, not $HOME — point it at the same fake home.
  export USERPROFILE="$HOME"
}

@test "non-interactive: complete .env applies host+key AND reaches later install steps (Bug A regression)" {
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  run bash -c "cd '$STAGE' && env USERPROFILE='$HOME' pwsh -NoProfile -File ai-proxy/setup.ps1 </dev/null"
  [ "$status" -eq 0 ]

  host=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/claude.json")
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$host" = "$TEST_HOST" ]
  [ "$key" = "$TEST_KEY" ]

  # Regression for Bug A: before the fix, [Environment]::UserInteractive always
  # claimed "interactive" and the script stalled on Read-Host -AsSecureString,
  # never reaching settings.json hook wiring or profile function registration.
  [[ "$(jq -e '.hooks.SessionStart' "$HOME/.claude/settings.json")" != "null" ]]
  [[ "$output" == *"synced ccswitch function"* || "$output" == *"already in"* ]]
}

@test "non-interactive: no .env present skips key prompt, still reaches later install steps" {
  rm -f "$STAGE/.env"
  run bash -c "cd '$STAGE' && env USERPROFILE='$HOME' pwsh -NoProfile -File ai-proxy/setup.ps1 </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-interactive session — skipped key prompt"* ]]

  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [[ "$key" == *"<your-9router-key>"* ]]
  [[ "$(jq -e '.hooks.SessionStart' "$HOME/.claude/settings.json")" != "null" ]]
}

@test "settings.json after full install has no .model key (Bug B regression)" {
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  run bash -c "cd '$STAGE' && env USERPROFILE='$HOME' pwsh -NoProfile -File ai-proxy/setup.ps1 </dev/null"
  [ "$status" -eq 0 ]

  run jq -e '.model' "$HOME/.claude/settings.json"
  [ "$status" -ne 0 ]
  [[ "$output" != *"set default model to sonnet"* ]]
}

@test "non-interactive: .env ALWAYS overrides even when a profile already holds a real key" {
  write_fake_env_pro "$TEST_HOST" "$TEST_KEY"
  mkdir -p "$HOME/.claude/profiles"
  jq '.ANTHROPIC_AUTH_TOKEN = "existing-real-key"' "$STAGE/ai-proxy/profiles/claude.json" > "$HOME/.claude/profiles/claude.json"
  run bash -c "cd '$STAGE' && env USERPROFILE='$HOME' pwsh -NoProfile -File ai-proxy/setup.ps1 </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env always overrides"* ]]

  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$key" = "$TEST_KEY" ]
}

@test "non-interactive: kimi force subscription applies kimi_api_key only to kimi profile" {
  write_fake_kimi_env "$TEST_KEY"
  run bash -c "cd '$STAGE' && env USERPROFILE='$HOME' pwsh -NoProfile -File ai-proxy/setup.ps1 </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *".env kimi_api_key applied to profiles\kimi.json"* ]]
  base=$(jq -r '.ANTHROPIC_BASE_URL' "$HOME/.claude/profiles/kimi.json")
  key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/kimi.json")
  claude_key=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/claude.json")
  [ "$base" = "https://api.moonshot.ai/anthropic" ]
  [ "$key" = "$TEST_KEY" ]
  [[ "$claude_key" == *"<your-9router-key>"* ]]
}
