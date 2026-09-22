#!/usr/bin/env bats
load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$CLAUDE_PROJECT_DIR"
  HOOKS="$ROOT/harness/templates/hooks"
}

@test "hook templates and statusline have valid shell syntax" {
  for script in "$HOOKS"/*.sh "$ROOT/harness/templates/statusline-orchestration.sh"; do
    run bash -n "$script"
    [ "$status" -eq 0 ]
  done
}

@test "JSON consuming hooks fail open silently on malformed JSON" {
  for name in pre-bash-gate pre-edit-orchestrator-gate pre-task-dispatch-gate post-edit-advisor post-bash-stuck-detector subagent-stop-record; do
    run bash -c 'printf "%s" "{malformed" | bash "$1"' _ "$HOOKS/$name.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "content scan preserves loud error for malformed JSON" {
  run bash -c 'printf "%s" "{malformed" | bash "$1"' _ "$HOOKS/pre-edit-content-scan.sh"
  [ "$status" -ne 0 ]
  [ -n "$output" ]
}

@test "content scan allows ordinary content and blocks secrets without printing values" {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ '{"tool_input":{"file_path":"notes.txt","content":"ordinary text"}}' "$HOOKS/pre-edit-content-scan.sh"
  [ "$status" -eq 0 ]
  local synthetic="sk-ant-$(printf 'x%.0s' {1..30})"
  local payload
  payload="$(jq -nc --arg value "$synthetic" '{tool_input:{file_path:"notes.txt",content:$value}}')"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOKS/pre-edit-content-scan.sh"
  [ "$status" -eq 2 ]
  [[ "$output" != *"$synthetic"* ]]
}

@test "bash gate allows inspection and blocks direct delegate CLI" {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ '{"tool_input":{"command":"git status"}}' "$HOOKS/pre-bash-gate.sh"
  [ "$status" -eq 0 ]
  run bash -c 'printf "%s" "$1" | bash "$2"' _ '{"tool_input":{"command":"codex exec hello"}}' "$HOOKS/pre-bash-gate.sh"
  [ "$status" -eq 2 ]
}

@test "statusline tolerates malformed input missing graph and failing global chain" {
  mkdir -p "$HOME/.claude"
  printf '#!/bin/bash\nexit 1\n' > "$HOME/.claude/statusline-context.sh"
  run bash -c 'printf "%s" "{malformed" | bash "$1"' _ "$ROOT/harness/templates/statusline-orchestration.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
