#!/usr/bin/env bats
# Simulation suite: chạy chuỗi hook TEMPLATE (harness/templates/hooks/)
# nối tiếp nhau như 1 orchestration flow thật (dispatch -> ledger -> verdict ->
# merge), thay vì unit-test từng hook riêng lẻ (đã có dispatch-gate.bats /
# stuck-detector.bats / orchestrator-ledger.bats). Mục đích: đo end-to-end
# behavior + performance tax của toàn bộ harness trên mỗi turn.
#
# post-task-trace.sh (JSONL orchestration trace) bị bỏ hẳn trong consolidation
# 17→8 (dcd189d) — không merge vào hook nào, không thay thế. Test trace đã bị
# xoá khỏi suite này (xem test/agent-trace.bats đã xoá cùng lý do).
#
# Test TEMPLATE path (chưa install-substitute @@PROJECT_SLUG@@) — literal
# placeholder text vẫn là 1 tên thư mục hợp lệ cho bash, không cần render.

load test_helper.bash

SLUG='@@PROJECT_SLUG@@'

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  HOOKS="$ROOT/harness/templates/hooks"

  DISPATCH="$HOOKS/pre-task-dispatch-gate.sh"
  MERGE_GATE="$HOOKS/pre-bash-gate.sh"
  STUCK="$HOOKS/post-bash-stuck-detector.sh"
  STOP_LEDGER="$HOOKS/subagent-stop-record.sh"
  START_LEDGER="$HOOKS/session-start.sh"
  VERDICT_REC="$HOOKS/subagent-stop-record.sh"

  PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR/.claude"

  STUCK_WINDOW="$HOME/.cache/claude-code-$SLUG/stuck-window"
  LEDGER="$PROJECT_DIR/.claude/state/orchestrator-ledger.md"
  VERDICT_FILE="$PROJECT_DIR/.claude/state/last-verdict"
}

FULL_PROMPT='Repo /Users/admin/proj branch main. Spec: implement X in src/foo.js per file paths listed. Acceptance: run test suite bats test/foo.bats and verify pass. NO commit — produce diff only, return summary under 300 words.'

run_dispatch() {
  local subagent="$1" prompt="$2"
  local json
  json=$(jq -nc --arg s "$subagent" --arg p "$prompt" '{tool_input:{subagent_type:$s,prompt:$p}}')
  run bash -c "printf '%s' '$json' | HOME='$HOME' bash '$DISPATCH'"
}

run_stop_ledger() {
  run bash -c "printf '%s' '$1' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$STOP_LEDGER'"
}

run_start_ledger() {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$START_LEDGER'"
}

run_verdict_record() {
  run bash -c "printf '%s' '$1' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$VERDICT_REC'"
}

run_merge_gate() {
  run bash -c "printf '%s' '$1' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$MERGE_GATE'"
}

run_stuck() {
  run bash -c "printf '%s' '$1' | HOME='$HOME' bash '$STUCK'"
}

cmd_json() {
  printf '{"tool_input":{"command":"%s"}}' "$1"
}

# avg ms/call over N calls of: printf json | env $extra_env bash script
time_hook_ms() {
  local script="$1" json="$2" extra_env="$3" iters=10
  local start end total=0 i
  for i in $(seq 1 "$iters"); do
    start=$(date +%s%N)
    printf '%s' "$json" | env $extra_env bash "$script" >/dev/null 2>&1
    end=$(date +%s%N)
    total=$((total + (end - start)))
  done
  echo $(( total / iters / 1000000 ))
}

# ---------------------------------------------------------------------------
# 1. Happy path: dispatch -> subagent-stop-record ledger -> verdict APPROVE
#    -> merge allowed. Round-trip đọc lại ledger/verdict.
# ---------------------------------------------------------------------------

@test "sim1: happy path dispatch -> ledger round-trip" {
  run_dispatch "delegate-sonnet" "$FULL_PROMPT"
  [ "$status" -eq 0 ]

  run_stop_ledger '{"agent_id":"sim-agent-1","agent_type":"delegate-sonnet"}'
  [ "$status" -eq 0 ]
  [ -f "$LEDGER" ]
  grep -q "agent_id=sim-agent-1 type=delegate-sonnet" "$LEDGER"
}

@test "sim1: verdict APPROVE recorded then merge of feat/ branch allowed" {
  run_verdict_record '{"last_assistant_message":"review ok\nVERDICT: APPROVE"}'
  [ "$status" -eq 0 ]
  [ -f "$VERDICT_FILE" ]
  grep -q APPROVE "$VERDICT_FILE"

  run_merge_gate '{"tool_input":{"command":"git merge feat/sim-task"}}'
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2. Under-specified dispatch bị chặn, sửa xong pass.
# ---------------------------------------------------------------------------

@test "sim2: dispatch missing verify marker blocks with guidance" {
  prompt='Repo /Users/admin/proj branch main. Spec: implement X in src/foo.js per file paths listed. NO commit — produce diff only, return summary under 300 words. Extra padding text to reach length requirement for this case here now please.'
  run_dispatch "delegate-sonnet" "$prompt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"verify"* ]]
}

@test "sim2: same prompt fixed with verify marker passes" {
  run_dispatch "delegate-sonnet" "$FULL_PROMPT"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. REVISE verdict chặn merge; PASS mới lại cho merge.
# ---------------------------------------------------------------------------

@test "sim3: REVISE verdict blocks merge, new APPROVE unblocks" {
  run_verdict_record '{"last_assistant_message":"found bug\nVERDICT: REVISE — race condition"}'
  [ "$status" -eq 0 ]
  grep -q REVISE "$VERDICT_FILE"

  run_merge_gate '{"tool_input":{"command":"git merge feat/sim-task"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"REVISE"* ]]

  run_verdict_record '{"last_assistant_message":"fixed\nVERDICT: APPROVE"}'
  [ "$status" -eq 0 ]
  grep -q APPROVE "$VERDICT_FILE"

  run_merge_gate '{"tool_input":{"command":"git merge feat/sim-task"}}'
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 4. Stuck/thrashing detection.
# ---------------------------------------------------------------------------

@test "sim4: same Bash command 4x in a row warns on 4th call" {
  run_stuck "$(cmd_json 'npm test')"
  [ "$status" -eq 0 ]
  run_stuck "$(cmd_json 'npm test')"
  [ "$status" -eq 0 ]
  run_stuck "$(cmd_json 'npm test')"
  [ "$status" -eq 0 ]
  run_stuck "$(cmd_json 'npm test')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Loop detected"* ]]
}

@test "sim4: varying commands never warn" {
  run_stuck "$(cmd_json 'npm test')"
  run_stuck "$(cmd_json 'npm run build')"
  run_stuck "$(cmd_json 'git status')"
  run_stuck "$(cmd_json 'npm test')"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5. Session resume: ledger 2 subagent dở dang -> banner -> xoá -> im lặng.
# ---------------------------------------------------------------------------

@test "sim5: resume banner shows both dangling subagents then clears" {
  run_stop_ledger '{"agent_id":"resume-a1","agent_type":"delegate-sonnet"}'
  [ "$status" -eq 0 ]
  run_stop_ledger '{"agent_id":"resume-a2","agent_type":"delegate-codex"}'
  [ "$status" -eq 0 ]

  run_start_ledger
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orchestrator ledger dở dang"* ]]
  [[ "$output" == *"agent_id=resume-a1"* ]]
  [[ "$output" == *"agent_id=resume-a2"* ]]

  # session-start.sh (merged ledger+banner) luôn in banner routing trên stderr
  # bất kể ledger có hay không — chỉ phần "ledger dở dang" mất đi khi ledger rỗng.
  rm -f "$LEDGER"
  run_start_ledger
  [ "$status" -eq 0 ]
  [[ "$output" != *"Orchestrator ledger dở dang"* ]]
  [[ "$output" != *"agent_id=resume"* ]]
}

# ---------------------------------------------------------------------------
# 6. Performance benchmark: 4 hook nóng nhất, 10 lần/hook, avg < 500ms/call.
# ---------------------------------------------------------------------------

@test "sim6: perf — pre-task-dispatch-gate avg < 500ms/call" {
  json=$(jq -nc --arg s "delegate-sonnet" --arg p "$FULL_PROMPT" '{tool_input:{subagent_type:$s,prompt:$p}}')
  avg=$(time_hook_ms "$DISPATCH" "$json" "HOME=$HOME")
  echo "# timing: pre-task-dispatch-gate avg=${avg}ms/call (10 calls)"
  [ "$avg" -lt 500 ]
}

@test "sim6: perf — pre-bash-gate (merge-verdict path) avg < 500ms/call" {
  json='{"tool_input":{"command":"git merge feat/perf"}}'
  avg=$(time_hook_ms "$MERGE_GATE" "$json" "CLAUDE_PROJECT_DIR=$PROJECT_DIR")
  echo "# timing: pre-bash-gate avg=${avg}ms/call (10 calls)"
  [ "$avg" -lt 500 ]
}

@test "sim6: perf — post-bash-stuck-detector avg < 500ms/call" {
  local start end total=0 i avg
  total=0
  for i in $(seq 1 10); do
    start=$(date +%s%N)
    printf '%s' "$(cmd_json "perf-cmd-$i")" | env HOME="$HOME" bash "$STUCK" >/dev/null 2>&1
    end=$(date +%s%N)
    total=$((total + (end - start)))
  done
  avg=$(( total / 10 / 1000000 ))
  echo "# timing: post-bash-stuck-detector avg=${avg}ms/call (10 calls)"
  [ "$avg" -lt 500 ]
}
