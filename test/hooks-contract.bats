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
  for name in pre-bash-gate pre-edit-orchestrator-gate pre-task-dispatch-gate post-edit-advisor post-bash-stuck-detector subagent-stop-record pre-compact-guard; do
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

@test "bash gate blocks serial multi-file bats only in the real bats segment" {
  for blocked in 'bats test/*.bats' 'bats test/a.bats test/b.bats' 'cd repo && bats test/*.bats' 'make -j4 && bats test/*.bats' 'FOO=1 bats test/a.bats test/b.bats' 'env bats test/*.bats' 'time bats test/*.bats'; do
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$(jq -nc --arg c "$blocked" '{tool_input:{command:$c}}')" "$HOOKS/pre-bash-gate.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"serial-test-gate"* ]]
  done
  for allowed in 'bats -j 10 test/*.bats' 'bats -j10 test/*.bats' 'bats --jobs=4 test/*.bats' 'bats -T -j 10 test/*.bats' 'bats -f "x" test/a.bats' 'BATS_SERIAL_OK=1 bats test/*.bats' 'ls bats-core/' 'echo bats test/*.bats' 'grep -rn "bats test/x.bats" README.md' 'bats --version'; do
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$(jq -nc --arg c "$allowed" '{tool_input:{command:$c}}')" "$HOOKS/pre-bash-gate.sh"
    [ "$status" -eq 0 ]
  done
  # heredoc text mentioning .bats files must not count toward the real single-file run below it
  local multi=$'python3 - <<PY\nx = "a.bats b.bats"\nPY\nbats -f r test/one.bats'
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$(jq -nc --arg c "$multi" '{tool_input:{command:$c}}')" "$HOOKS/pre-bash-gate.sh"
  [ "$status" -eq 0 ]
}

@test "statusline tolerates malformed input missing graph and failing global chain" {
  mkdir -p "$HOME/.claude"
  printf '#!/bin/bash\nexit 1\n' > "$HOME/.claude/statusline-context.sh"
  run bash -c 'printf "%s" "{malformed" | bash "$1"' _ "$ROOT/harness/templates/statusline-orchestration.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
