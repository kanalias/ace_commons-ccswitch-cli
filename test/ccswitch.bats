#!/usr/bin/env bats
# Core ccswitch.sh behavior: profile switching, subscription clear, guards.
# Network-probing paths (health check http codes) are not asserted on — they hit a real
# endpoint and are not deterministic in CI; we only assert the local file-mutation logic.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  CC="$ROOT/ccswitch.sh"
  mkdir -p "$HOME/.claude/profiles"
  cp "$ROOT/profiles/claude.json" "$HOME/.claude/profiles/claude.json"
  cp "$ROOT/profiles/deepseek.json" "$HOME/.claude/profiles/deepseek.json"
  echo '{}' > "$HOME/.claude/settings.json"
}

@test "apply claude writes env block into settings.json" {
  run "$CC" claude
  [ "$status" -eq 0 ]
  model=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$HOME/.claude/settings.json")
  [ "$model" = "cc/claude-opus-4-8" ]
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
