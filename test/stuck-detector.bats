#!/usr/bin/env bats
# .claude/hooks/post-bash-stuck-detector.sh: PostToolUse hook cảnh báo khi
# cùng 1 lệnh Bash chạy 4 lần liên tiếp (loop/thrashing detection).

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.claude/hooks/post-bash-stuck-detector.sh"
  WINDOW_FILE="$HOME/.cache/claude-code-ccswitch-cli-claude/stuck-window"
}

run_hook() {
  local json="$1"
  run bash -c "printf '%s' '$json' | HOME='$HOME' bash '$SCRIPT'"
}

cmd_json() {
  printf '{"tool_input":{"command":"%s"}}' "$1"
}

@test "stuck-detector: same command 4x in a row → 4th call exits 2" {
  run_hook "$(cmd_json 'echo hi')"
  [ "$status" -eq 0 ]
  run_hook "$(cmd_json 'echo hi')"
  [ "$status" -eq 0 ]
  run_hook "$(cmd_json 'echo hi')"
  [ "$status" -eq 0 ]
  run_hook "$(cmd_json 'echo hi')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Loop detected"* ]]
}

@test "stuck-detector: same command 3x only → exits 0" {
  run_hook "$(cmd_json 'echo hi')"
  run_hook "$(cmd_json 'echo hi')"
  run_hook "$(cmd_json 'echo hi')"
  [ "$status" -eq 0 ]
}

@test "stuck-detector: identical run interrupted by different command → exits 0" {
  run_hook "$(cmd_json 'echo hi')"
  run_hook "$(cmd_json 'echo hi')"
  run_hook "$(cmd_json 'echo hi')"
  run_hook "$(cmd_json 'echo different')"
  [ "$status" -eq 0 ]
  run_hook "$(cmd_json 'echo hi')"
  [ "$status" -eq 0 ]
}

@test "stuck-detector: window rotation caps at 20 lines" {
  for i in $(seq 1 25); do
    run_hook "$(cmd_json "echo run-$i")"
  done
  [ "$status" -eq 0 ]
  lines=$(wc -l <"$WINDOW_FILE" | tr -d ' ')
  [ "$lines" -eq 20 ]
}

@test "stuck-detector: normalization — extra whitespace still counts as same command" {
  run_hook "$(cmd_json 'echo   hi')"
  run_hook "$(cmd_json 'echo hi')"
  run_hook "$(cmd_json '  echo hi  ')"
  [ "$status" -eq 0 ]
  run_hook "$(cmd_json 'echo hi')"
  [ "$status" -eq 2 ]
}

@test "stuck-detector: non-JSON stdin fails open (exit 0)" {
  run bash -c "printf 'not json at all' | HOME='$HOME' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "stuck-detector: empty command allows (exit 0)" {
  run_hook '{"tool_input":{"file_path":"x.md"}}'
  [ "$status" -eq 0 ]
}

@test "stuck-detector: HARNESS_DELEGATE=0 disables hook (exit 0) even after 4x" {
  run bash -c "printf '%s' '$(cmd_json "echo hi")' | HARNESS_DELEGATE=0 HOME='$HOME' bash '$SCRIPT'"
  run bash -c "printf '%s' '$(cmd_json "echo hi")' | HARNESS_DELEGATE=0 HOME='$HOME' bash '$SCRIPT'"
  run bash -c "printf '%s' '$(cmd_json "echo hi")' | HARNESS_DELEGATE=0 HOME='$HOME' bash '$SCRIPT'"
  run bash -c "printf '%s' '$(cmd_json "echo hi")' | HARNESS_DELEGATE=0 HOME='$HOME' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "stuck-detector: session_id present keys window file per-session" {
  json='{"session_id":"sess-abc","tool_input":{"command":"echo hi"}}'
  run bash -c "printf '%s' '$json' | HOME='$HOME' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.cache/claude-code-ccswitch-cli-claude/stuck-window-sess-abc" ]
  [ ! -f "$WINDOW_FILE" ]
}
