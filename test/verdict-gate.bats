#!/usr/bin/env bats
# subagent-stop-record.sh (SubagentStop, section b) + pre-bash-gate.sh
# (PreToolUse Bash, section 2 merge-verdict gate): ghi verdict code-reviewer +
# chặn merge khi REVISE. Xem .claude/agents/code-reviewer.md output contract.
# Port từ stop-verdict-record.sh + pre-bash-merge-verdict-gate.sh (đã xoá,
# merge vào 2 hook trên trong consolidation 17→8).

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  RECORD_SCRIPT="$ROOT/.claude/hooks/subagent-stop-record.sh"
  GATE_SCRIPT="$ROOT/.claude/hooks/pre-bash-gate.sh"

  PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR/.claude"
}

run_record() {
  local json="$1"
  run bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$RECORD_SCRIPT'"
}

run_gate() {
  local json="$1"
  run bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$GATE_SCRIPT'"
}

@test "verdict-record: APPROVE message writes APPROVE to state file" {
  run_record '{"last_assistant_message":"review ok\nVERDICT: APPROVE"}'
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.claude/state/last-verdict" ]
  grep -q "APPROVE" "$PROJECT_DIR/.claude/state/last-verdict"
}

@test "verdict-record: REVISE message writes REVISE to state file" {
  run_record '{"last_assistant_message":"found bug\nVERDICT: REVISE — race condition in auth"}'
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.claude/state/last-verdict" ]
  grep -q "REVISE" "$PROJECT_DIR/.claude/state/last-verdict"
}

@test "verdict-record: no VERDICT token found writes no file" {
  run_record '{"last_assistant_message":"just some chatter, no verdict here"}'
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT_DIR/.claude/state/last-verdict" ]
}

@test "verdict-record: HARNESS_DELEGATE=0 skips recording" {
  run bash -c "printf '%s' '{\"last_assistant_message\":\"VERDICT: REVISE — x\"}' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' HARNESS_DELEGATE=0 bash '$RECORD_SCRIPT'"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT_DIR/.claude/state/last-verdict" ]
}

@test "merge-gate: blocks merge of feat/ branch on fresh REVISE" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "REVISE 2026-07-31T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  run_gate '{"tool_input":{"command":"git merge feat/foo"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"REVISE"* ]]
}

@test "merge-gate: allows merge of feat/ branch on APPROVE" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "APPROVE 2026-07-31T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  run_gate '{"tool_input":{"command":"git merge feat/foo"}}'
  [ "$status" -eq 0 ]
}

@test "merge-gate: allows merge when verdict file is stale (>4h)" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "REVISE 2026-07-30T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  # Force mtime 5h in the past (portable BSD/GNU: touch -t).
  stale_ts=$(date -u -v-5H +%Y%m%d%H%M.%S 2>/dev/null || date -u -d '5 hours ago' +%Y%m%d%H%M.%S)
  touch -t "$stale_ts" "$PROJECT_DIR/.claude/state/last-verdict"
  run_gate '{"tool_input":{"command":"git merge feat/foo"}}'
  [ "$status" -eq 0 ]
}

@test "merge-gate: allows non-merge commands regardless of verdict" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "REVISE 2026-07-31T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  run_gate '{"tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]
}

@test "merge-gate: allows merge of protected branch (no matching prefix) regardless of verdict" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "REVISE 2026-07-31T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  run_gate '{"tool_input":{"command":"git merge dev"}}'
  [ "$status" -eq 0 ]
}

@test "merge-gate: no verdict file allows merge" {
  run_gate '{"tool_input":{"command":"git merge feat/foo"}}'
  [ "$status" -eq 0 ]
}

@test "merge-gate: fail-open when jq missing" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "REVISE 2026-07-31T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  stub_dir="$BATS_TEST_TMPDIR/stubpath"
  mkdir -p "$stub_dir"
  for tool in bash cat grep sed find date mkdir dirname; do
    p=$(command -v "$tool")
    [ -n "$p" ] && ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  json='{"tool_input":{"command":"git merge feat/foo"}}'
  run env PATH="$stub_dir" bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$GATE_SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "merge-gate: HARNESS_DELEGATE=0 allows even on fresh REVISE" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "REVISE 2026-07-31T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git merge feat/foo\"}}' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' HARNESS_DELEGATE=0 bash '$GATE_SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "merge-gate: blocks merge of .claude/worktrees path on fresh REVISE" {
  mkdir -p "$PROJECT_DIR/.claude/state"
  echo "REVISE 2026-07-31T00:00:00Z" > "$PROJECT_DIR/.claude/state/last-verdict"
  run_gate '{"tool_input":{"command":"git -C .claude/worktrees/foo merge origin/feat-foo"}}'
  [ "$status" -eq 2 ]
}

@test "verdict-record: path fallback resolves to repo root when CLAUDE_PROJECT_DIR unset" {
  run bash -c "cd '$ROOT' && printf '%s' '{\"last_assistant_message\":\"VERDICT: APPROVE\"}' | bash '$RECORD_SCRIPT'"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/.claude/state/last-verdict" ]
  rm -f "$ROOT/.claude/state/last-verdict"
}

@test "merge-gate: path fallback resolves to repo root when CLAUDE_PROJECT_DIR unset" {
  run bash -c "cd '$ROOT' && printf '%s' '{\"tool_input\":{\"command\":\"git merge feat/foo\"}}' | bash '$GATE_SCRIPT'"
  [ "$status" -eq 0 ]
}
