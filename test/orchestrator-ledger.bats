#!/usr/bin/env bats
# subagent-stop-record.sh (section a, ledger append+rotate) + session-start.sh
# (ledger inject block): F2 orchestration state ledger + resume (LangGraph
# checkpoint / Mastra suspend-resume pattern). Port từ subagent-stop-ledger.sh
# + session-start-ledger.sh (đã xoá, merge vào 2 hook trên trong
# consolidation 17→8 — session-start.sh còn thêm banner section, không test
# ở đây).

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  STOP_SCRIPT="$ROOT/.claude/hooks/subagent-stop-record.sh"
  START_SCRIPT="$ROOT/.claude/hooks/session-start.sh"

  PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR/.claude"
  LEDGER="$PROJECT_DIR/.claude/state/orchestrator-ledger.md"

  # cache hygiene block hardcodes cache dir under $HOME (not CLAUDE_PROJECT_DIR)
  CACHE_DIR="$HOME/.cache/claude-code-ccswitch-cli-claude"
}

run_stop() {
  local json="$1"
  run bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$STOP_SCRIPT'"
}

run_start() {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$START_SCRIPT'"
}

@test "stop-ledger: appends line + creates state dir" {
  [ ! -d "$PROJECT_DIR/.claude/state" ]
  run_stop '{"agent_id":"a1-b2","agent_type":"delegate-sonnet"}'
  [ "$status" -eq 0 ]
  [ -f "$LEDGER" ]
  grep -q "agent_id=a1-b2 type=delegate-sonnet session=?" "$LEDGER"
}

@test "stop-ledger: subagent_type field (wrong/legacy key) does NOT populate type" {
  run_stop '{"agent_id":"a2","subagent_type":"delegate-sonnet"}'
  [ "$status" -eq 0 ]
  grep -q "agent_id=a2 type=?" "$LEDGER"
}

@test "stop-ledger: missing agent_id → ledger NOT appended" {
  run_stop '{}'
  [ "$status" -eq 0 ]
  [ ! -f "$LEDGER" ]
}

@test "stop-ledger: missing agent_id but verdict text present → last-verdict still written" {
  run_stop '{"last_assistant_message":"VERDICT: APPROVE all good"}'
  [ "$status" -eq 0 ]
  [ ! -f "$LEDGER" ]
  grep -q "^APPROVE " "$PROJECT_DIR/.claude/state/last-verdict"
}

@test "stop-ledger: session_id field populates session" {
  run_stop '{"agent_id":"a3","agent_type":"delegate-codex","session_id":"sess-xyz"}'
  [ "$status" -eq 0 ]
  grep -q "agent_id=a3 type=delegate-codex session=sess-xyz" "$LEDGER"
}

@test "stop-ledger: rotates and caps at 200 lines" {
  mkdir -p "$(dirname "$LEDGER")"
  for i in $(seq 1 205); do echo "- [x] line $i" >>"$LEDGER"; done
  run_stop '{"agent_id":"last","subagent_type":"t"}'
  [ "$status" -eq 0 ]
  lines=$(wc -l <"$LEDGER" | tr -d ' ')
  [ "$lines" -eq 200 ]
  # dòng vừa append phải còn (tail giữ mới nhất)
  grep -q "agent_id=last" "$LEDGER"
  # dòng cũ nhất phải đã bị rotate ra
  ! grep -q "line 1$" "$LEDGER"
}

@test "stop-ledger: non-JSON payload fails open" {
  run bash -c "printf 'not json at all' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$STOP_SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "stop-ledger: HARNESS_DELEGATE=0 silent no-op" {
  run bash -c "printf '%s' '{\"agent_id\":\"x\"}' | HARNESS_DELEGATE=0 CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$STOP_SCRIPT'"
  [ "$status" -eq 0 ]
  [ ! -f "$LEDGER" ]
}

@test "session-start-ledger: prints last lines when ledger fresh" {
  mkdir -p "$(dirname "$LEDGER")"
  fresh_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "- [$fresh_ts] subagent done: agent_id=a1 type=delegate-sonnet session=s1" >"$LEDGER"
  run_start
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orchestrator ledger dở dang"* ]]
  [[ "$output" == *"agent_id=a1"* ]]
}

@test "session-start-ledger: silent (no ledger block) when ledger absent" {
  run_start
  [ "$status" -eq 0 ]
  [[ "$output" != *"Orchestrator ledger dở dang"* ]]
}

@test "session-start-ledger: prunes stale entry, keeps fresh entry only" {
  mkdir -p "$(dirname "$LEDGER")"
  old_ts=$(date -u -v-3d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
  fresh_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    echo "- [$old_ts] subagent done: agent_id=stale type=t session=?"
    echo "- [$fresh_ts] subagent done: agent_id=fresh type=t session=?"
  } >"$LEDGER"
  run_start
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orchestrator ledger dở dang"* ]]
  [[ "$output" == *"agent_id=fresh"* ]]
  [[ "$output" != *"agent_id=stale"* ]]
  lines=$(wc -l <"$LEDGER" | tr -d ' ')
  [ "$lines" -eq 1 ]
}

@test "session-start-ledger: all-stale entries → ledger removed, no header" {
  mkdir -p "$(dirname "$LEDGER")"
  old_ts=$(date -u -v-3d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
  echo "- [$old_ts] subagent done: agent_id=stale type=t session=?" >"$LEDGER"
  run_start
  [ "$status" -eq 0 ]
  [[ "$output" != *"Orchestrator ledger dở dang"* ]]
  [[ "$output" != *"agent_id=stale"* ]]
  [ ! -f "$LEDGER" ]
}

@test "session-start-ledger: HARNESS_DELEGATE=0 fully silent even when ledger fresh" {
  mkdir -p "$(dirname "$LEDGER")"
  echo "- fresh entry" >"$LEDGER"
  run bash -c "HARNESS_DELEGATE=0 CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$START_SCRIPT'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop-ledger: path fallback resolves to repo root when CLAUDE_PROJECT_DIR unset" {
  run bash -c "cd '$ROOT' && printf '%s' '{\"agent_id\":\"root-check\",\"agent_type\":\"t\"}' | bash '$STOP_SCRIPT'"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/.claude/state/orchestrator-ledger.md" ]
  grep -q "agent_id=root-check" "$ROOT/.claude/state/orchestrator-ledger.md"
  # cleanup: khỏi rớt dòng test vào ledger thật của repo
  sed -i.bak '/agent_id=root-check/d' "$ROOT/.claude/state/orchestrator-ledger.md" && rm -f "$ROOT/.claude/state/orchestrator-ledger.md.bak"
}

# ── cache hygiene (session-start.sh) ────────────────────────────────────────

@test "session-start-cache: stuck-window file older than 7 days is deleted" {
  mkdir -p "$CACHE_DIR"
  old_file="$CACHE_DIR/stuck-window-old-session"
  touch "$old_file"
  touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$old_file"
  run_start
  [ "$status" -eq 0 ]
  [ ! -f "$old_file" ]
}

@test "session-start-cache: fresh stuck-window file is kept" {
  mkdir -p "$CACHE_DIR"
  fresh_file="$CACHE_DIR/stuck-window-fresh-session"
  touch "$fresh_file"
  run_start
  [ "$status" -eq 0 ]
  [ -f "$fresh_file" ]
}

@test "session-start-cache: oversized log file rotated to last 500 lines" {
  mkdir -p "$CACHE_DIR"
  log="$CACHE_DIR/orchestrator-gate.log"
  yes "line" | head -n 200000 >"$log"
  size_before=$(wc -c <"$log" | tr -d ' ')
  [ "$size_before" -gt 512000 ]
  run_start
  [ "$status" -eq 0 ]
  lines_after=$(wc -l <"$log" | tr -d ' ')
  [ "$lines_after" -eq 500 ]
}

@test "session-start-cache: small log file left untouched (byte-identical)" {
  mkdir -p "$CACHE_DIR"
  log="$CACHE_DIR/dispatch-gate.log"
  printf 'short log line\n' >"$log"
  before_hash=$(cksum "$log")
  run_start
  [ "$status" -eq 0 ]
  after_hash=$(cksum "$log")
  [ "$before_hash" = "$after_hash" ]
}

@test "session-start-cache: cache dir absent → hook still exits 0, no stdout noise" {
  [ ! -d "$CACHE_DIR" ]
  run_start
  [ "$status" -eq 0 ]
  [[ "$output" != *"cache"* ]]
  [[ "$output" != *"stuck-window"* ]]
}

# ── jq-missing loud warning (session-start.sh banner) ───────────────────────

@test "session-start-jq-warn: jq missing → stderr warns, exit 0" {
  stub_dir="$BATS_TEST_TMPDIR/stubpath"
  mkdir -p "$stub_dir"
  for tool in bash date awk mv rm find wc tr tail grep dirname mkdir cat; do
    p=$(command -v "$tool")
    [ -n "$p" ] && ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  run env PATH="$stub_dir" bash -c "CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$START_SCRIPT' 2>&1 1>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq"* ]]
}

@test "session-start-jq-warn: jq present → no warning on stderr" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$START_SCRIPT' 2>&1 1>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"jq KHÔNG có trong PATH"* ]]
}
