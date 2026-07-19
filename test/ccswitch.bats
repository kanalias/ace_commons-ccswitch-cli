#!/usr/bin/env bats
# Core ccswitch.sh behavior: profile switching, subscription clear, guards.
# Network-probing paths (health check http codes) are not asserted on — they hit a real
# endpoint and are not deterministic in CI; we only assert the local file-mutation logic.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  CC="$ROOT/ai-proxy/ccswitch.sh"
  mkdir -p "$HOME/.claude/profiles"
  cp "$ROOT/ai-proxy/profiles/claude.json" "$HOME/.claude/profiles/claude.json"
  cp "$ROOT/ai-proxy/profiles/codex.json" "$HOME/.claude/profiles/codex.json"
  cp "$ROOT/ai-proxy/profiles/deepseek.json" "$HOME/.claude/profiles/deepseek.json"
  echo '{}' > "$HOME/.claude/settings.json"
}

@test "apply claude writes env block into settings.json" {
  run "$CC" claude
  [ "$status" -eq 0 ]
  model=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$HOME/.claude/settings.json")
  [ "$model" = "cc/claude-opus-4-8" ]
}

@test "apply codex writes codex env block" {
  run "$CC" codex
  [ "$status" -eq 0 ]
  model=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$HOME/.claude/settings.json")
  [ "$model" = "cx/gpt-5.6-sol" ]
}

@test "apply deepseek writes deepseek env block" {
  run "$CC" deepseek
  [ "$status" -eq 0 ]
  model=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$HOME/.claude/settings.json")
  [ "$model" = "ds/deepseek-v4-pro-max" ]
}

@test "apply backs up settings.json before mutating" {
  run "$CC" claude
  [ -f "$HOME/.claude/settings.json.bak" ]
}

@test "subscription removes env block" {
  "$CC" claude >/dev/null
  run "$CC" subscription
  [ "$status" -eq 0 ]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
}

@test "aliases original/direct/clear resolve to subscription" {
  "$CC" claude >/dev/null
  run "$CC" clear
  [ "$status" -eq 0 ]
  has_env=$(jq 'has("env")' "$HOME/.claude/settings.json")
  [ "$has_env" = "false" ]
}

@test "apply on missing profile dies with non-zero exit" {
  rm "$HOME/.claude/profiles/claude.json"
  run "$CC" claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"profile not found"* ]]
}

@test "apply on invalid JSON profile dies without mutating settings" {
  echo 'not json' > "$HOME/.claude/profiles/claude.json"
  cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.orig"
  run "$CC" claude
  [ "$status" -ne 0 ]
  diff "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.orig"
}

@test "set-key on subscription is rejected" {
  run "$CC" set-key subscription
  [ "$status" -ne 0 ]
  [[ "$output" == *"OAuth login"* ]]
}

@test "set-host on subscription is rejected" {
  run "$CC" set-host https://example.com/v1 subscription
  [ "$status" -ne 0 ]
  [[ "$output" == *"OAuth login"* ]]
}

@test "set-host with no URL fails with usage message" {
  run "$CC" set-host
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "update on subscription is rejected" {
  run "$CC" update subscription
  [ "$status" -ne 0 ]
  [[ "$output" == *"no host/key to copy from"* ]]
}

@test "update requires an interactive terminal (no TTY under bats run)" {
  run "$CC" update claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"interactive terminal"* ]]
}

@test "update syncs host+key from claude into codex+deepseek, preserving model prefixes (interactive pty)" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  jq '.ANTHROPIC_AUTH_TOKEN = "claude-real-key"' "$HOME/.claude/profiles/claude.json" > /tmp/claude.json.$$ \
    && mv /tmp/claude.json.$$ "$HOME/.claude/profiles/claude.json"
  run expect -c "
    set timeout 10
    spawn \"$CC\" update claude
    expect \"overwrite host+key in profiles/codex.json*\"
    send \"y\r\"
    expect \"overwrite host+key in profiles/deepseek.json*\"
    send \"y\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  codex_token=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/codex.json")
  codex_model=$(jq -r '.ANTHROPIC_DEFAULT_OPUS_MODEL' "$HOME/.claude/profiles/codex.json")
  ds_token=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/deepseek.json")
  [ "$codex_token" = "claude-real-key" ]
  [ "$codex_model" = "cx/gpt-5.6-sol" ]
  [ "$ds_token" = "claude-real-key" ]
}

@test "update declining a target leaves that profile unchanged" {
  command -v expect >/dev/null 2>&1 || skip "expect not installed"
  jq '.ANTHROPIC_AUTH_TOKEN = "claude-real-key"' "$HOME/.claude/profiles/claude.json" > /tmp/claude.json.$$ \
    && mv /tmp/claude.json.$$ "$HOME/.claude/profiles/claude.json"
  jq '.ANTHROPIC_AUTH_TOKEN = "codex-existing"' "$HOME/.claude/profiles/codex.json" > /tmp/codex.json.$$ \
    && mv /tmp/codex.json.$$ "$HOME/.claude/profiles/codex.json"
  run expect -c "
    set timeout 10
    spawn \"$CC\" update claude
    expect \"overwrite host+key in profiles/codex.json*\"
    send \"N\r\"
    expect \"overwrite host+key in profiles/deepseek.json*\"
    send \"y\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  codex_token=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/codex.json")
  ds_token=$(jq -r '.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude/profiles/deepseek.json")
  [ "$codex_token" = "codex-existing" ]
  [ "$ds_token" = "claude-real-key" ]
}

@test "spawn on subscription is rejected" {
  run "$CC" spawn subscription
  [ "$status" -ne 0 ]
  [[ "$output" == *"env-clear"* ]]
}

@test "unknown command exits non-zero with usage" {
  run "$CC" bogus-target
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "status (default) runs without crashing on a clean settings.json" {
  run "$CC" status
  [ "$status" -eq 0 ]
}

@test "help prints usage and exits 0" {
  run "$CC" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"ccswitch"* ]]
}
