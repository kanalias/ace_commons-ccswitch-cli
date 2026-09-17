#!/usr/bin/env bats
# install-auto-compact.sh: set/auto/off/on/status commands targeting
# ~/.claude/settings.json (--global) or ./.claude/settings.json (--project).
# Tests jq validation, file creation, JSON integrity, error handling.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/install-auto-compact.sh"
  mkdir -p "$HOME/.claude"
}

# --- help & usage guards ---

@test "install-auto-compact: help flag shows usage" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-auto-compact.sh"* ]]
  [[ "$output" == *"set <tokens>"* ]]
  [[ "$output" == *"--global"* ]]
}

@test "install-auto-compact: --help flag shows usage" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"set <tokens>"* ]]
}

@test "install-auto-compact: help command shows usage" {
  run bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto"* ]]
}

@test "install-auto-compact: no command shows usage and exits 1" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"Cú pháp"* ]]
}

@test "install-auto-compact: unknown command errors and shows usage" {
  run bash "$SCRIPT" badcmd
  [ "$status" -eq 1 ]
  [[ "$output" == *"lạ"* ]] || [[ "$output" == *"unknown"* ]]
  [[ "$output" == *"set"* ]]
}

# --- jq missing guard ---

@test "install-auto-compact: errors clearly when jq missing" {
  stub_dir="$BATS_TEST_TMPDIR/stubpath"
  mkdir -p "$stub_dir"
  for tool in bash cat mkdir mktemp mv dirname; do
    p=$(command -v "$tool")
    [ -n "$p" ] && ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  run env PATH="$stub_dir" bash "$SCRIPT" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq"* ]]
}

# --- set command ---

@test "install-auto-compact: set <tokens> writes autoCompactWindow to global settings" {
  run bash "$SCRIPT" --global set 190000
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
  [[ "$output" == *"190000"* ]]
  val=$(jq -r '.autoCompactWindow' "$HOME/.claude/settings.json")
  [ "$val" = "190000" ]
}

@test "install-auto-compact: set without --global defaults to --global" {
  run bash "$SCRIPT" set 150000
  [ "$status" -eq 0 ]
  val=$(jq -r '.autoCompactWindow' "$HOME/.claude/settings.json")
  [ "$val" = "150000" ]
}

@test "install-auto-compact: set <tokens> to project settings with --project" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  run bash -c "cd '$BATS_TEST_TMPDIR' && bash '$SCRIPT' --project set 170000"
  [ "$status" -eq 0 ]
  val=$(jq -r '.autoCompactWindow' "$BATS_TEST_TMPDIR/.claude/settings.json")
  [ "$val" = "170000" ]
}

@test "install-auto-compact: set creates settings.json with {} if missing" {
  rm -f "$HOME/.claude/settings.json"
  run bash "$SCRIPT" set 100000
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/settings.json" ]
  val=$(jq -r '.autoCompactWindow' "$HOME/.claude/settings.json")
  [ "$val" = "100000" ]
}

@test "install-auto-compact: set rejects non-numeric arg" {
  run bash "$SCRIPT" set abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"int > 0"* ]]
}

@test "install-auto-compact: set rejects zero" {
  run bash "$SCRIPT" set 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"int > 0"* ]]
}

@test "install-auto-compact: set rejects negative" {
  run bash "$SCRIPT" set -100
  [ "$status" -eq 1 ]
  [[ "$output" == *"int > 0"* ]]
}

@test "install-auto-compact: set with no argument errors" {
  run bash "$SCRIPT" set
  [ "$status" -eq 1 ]
  [[ "$output" == *"int > 0"* ]]
}

@test "install-auto-compact: set overwrites previous autoCompactWindow" {
  bash "$SCRIPT" set 190000 >/dev/null
  run bash "$SCRIPT" set 100000
  [ "$status" -eq 0 ]
  val=$(jq -r '.autoCompactWindow' "$HOME/.claude/settings.json")
  [ "$val" = "100000" ]
}

@test "install-auto-compact: set preserves other JSON keys" {
  mkdir -p "$HOME/.claude"
  jq '.someOtherKey = "value"' <(echo '{}') > "$HOME/.claude/settings.json"
  run bash "$SCRIPT" set 180000
  [ "$status" -eq 0 ]
  other=$(jq -r '.someOtherKey' "$HOME/.claude/settings.json")
  [ "$other" = "value" ]
}

# --- auto command ---

@test "install-auto-compact: auto deletes autoCompactWindow key" {
  bash "$SCRIPT" set 190000 >/dev/null
  run bash "$SCRIPT" auto
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
  val=$(jq -r '.autoCompactWindow // "unset"' "$HOME/.claude/settings.json")
  [ "$val" = "unset" ]
}

@test "install-auto-compact: auto on empty file succeeds idempotently" {
  run bash "$SCRIPT" auto
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/settings.json" ]
}

# --- off command ---

@test "install-auto-compact: off sets env.DISABLE_AUTO_COMPACT=1" {
  run bash "$SCRIPT" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
  val=$(jq -r '.env.DISABLE_AUTO_COMPACT' "$HOME/.claude/settings.json")
  [ "$val" = "1" ]
}

@test "install-auto-compact: off creates .env object if missing" {
  rm -f "$HOME/.claude/settings.json"
  run bash "$SCRIPT" off
  [ "$status" -eq 0 ]
  val=$(jq -r '.env.DISABLE_AUTO_COMPACT' "$HOME/.claude/settings.json")
  [ "$val" = "1" ]
}

@test "install-auto-compact: off preserves other env keys" {
  jq '.env.OTHER_KEY = "val"' <(echo '{}') > "$HOME/.claude/settings.json"
  run bash "$SCRIPT" off
  [ "$status" -eq 0 ]
  other=$(jq -r '.env.OTHER_KEY' "$HOME/.claude/settings.json")
  [ "$other" = "val" ]
}

# --- on command ---

@test "install-auto-compact: on removes DISABLE_AUTO_COMPACT key" {
  bash "$SCRIPT" off >/dev/null
  run bash "$SCRIPT" on
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
  val=$(jq -r '.env.DISABLE_AUTO_COMPACT // "unset"' "$HOME/.claude/settings.json")
  [ "$val" = "unset" ]
}

@test "install-auto-compact: on deletes .env object if it becomes empty after DISABLE_AUTO_COMPACT removal" {
  bash "$SCRIPT" off >/dev/null
  run bash "$SCRIPT" on
  [ "$status" -eq 0 ]
  val=$(jq -r '.env // "unset"' "$HOME/.claude/settings.json")
  [ "$val" = "unset" ]
}

@test "install-auto-compact: on preserves .env if other keys remain" {
  jq '.env.KEEP_ME = "value"' <(echo '{}') > "$HOME/.claude/settings.json"
  bash "$SCRIPT" off >/dev/null
  run bash "$SCRIPT" on
  [ "$status" -eq 0 ]
  keep=$(jq -r '.env.KEEP_ME' "$HOME/.claude/settings.json")
  [ "$keep" = "value" ]
}

@test "install-auto-compact: on succeeds idempotently when already enabled" {
  run bash "$SCRIPT" on
  [ "$status" -eq 0 ]
  val=$(jq -r '.env.DISABLE_AUTO_COMPACT // "unset"' "$HOME/.claude/settings.json")
  [ "$val" = "unset" ]
}

# --- status command ---

@test "install-auto-compact: status prints current autoCompactWindow + DISABLE state (unset)" {
  bash "$SCRIPT" set 190000 >/dev/null
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"190000"* ]]
  [[ "$output" == *"unset"* ]] || [[ "$output" == *"enabled"* ]]
}

@test "install-auto-compact: status prints autoCompactWindow as auto when unset" {
  bash "$SCRIPT" auto >/dev/null
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto"* ]]
}

@test "install-auto-compact: status prints DISABLE_AUTO_COMPACT when off" {
  bash "$SCRIPT" off >/dev/null
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
}

@test "install-auto-compact: status shows file path" {
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *".claude/settings.json"* ]]
}

# --- invalid JSON guard ---

@test "install-auto-compact: errors when settings.json is not valid JSON" {
  mkdir -p "$HOME/.claude"
  echo "{ broken json" > "$HOME/.claude/settings.json"
  run bash "$SCRIPT" set 100000
  [ "$status" -eq 1 ]
  [[ "$output" == *"JSON"* ]]
}

# --- edge case: target flag variants ---

@test "install-auto-compact: --project works with all commands" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  run bash -c "cd '$BATS_TEST_TMPDIR' && bash '$SCRIPT' --project set 175000"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/settings.json" ]
}

@test "install-auto-compact: --global and --project use different files" {
  bash "$SCRIPT" --global set 190000 >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  bash -c "cd '$BATS_TEST_TMPDIR' && bash '$SCRIPT' --project set 100000" >/dev/null
  
  global_val=$(jq -r '.autoCompactWindow' "$HOME/.claude/settings.json")
  project_val=$(jq -r '.autoCompactWindow' "$BATS_TEST_TMPDIR/.claude/settings.json")
  
  [ "$global_val" = "190000" ]
  [ "$project_val" = "100000" ]
}
