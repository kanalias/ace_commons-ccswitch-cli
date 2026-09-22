#!/usr/bin/env bats
# .claude/hooks/pre-task-dispatch-gate.sh: PreToolUse hook chặn dispatch
# subagent delegate-* với prompt không self-contained (thiếu repo path /
# verify / scope / no-commit marker, hoặc quá ngắn).

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.claude/hooks/pre-task-dispatch-gate.sh"
  # PROJECT_DIR isolado: repo thật có .claude/state/task-graph/*.md sống (graph
  # của task đang chạy) — nếu để hook đọc graph thật, mọi test không-liên-quan
  # task-graph sẽ bị graph đó ăn vào. Test không cần graph → point vào tmpdir
  # rỗng (không có task-graph/) để giữ hành vi cũ (exit 0, không gate).
  PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR/.claude/state"
}

# Prompt đủ 4 marker + đủ dài (>200 ký tự).
FULL_PROMPT='Repo /Users/admin/proj branch main. Spec: implement X in src/foo.js per file paths listed. Acceptance: run test suite bats test/foo.bats and verify pass. NO commit — produce diff only, return summary under 300 words.'

run_hook() {
  # $1 = subagent_type, $2 = prompt, $3 = cwd (optional — mô phỏng session
  # đang ở worktree nào; rỗng = main repo, không worktree).
  local subagent="$1" prompt="$2" cwd="${3:-}"
  local json
  json=$(jq -nc --arg s "$subagent" --arg p "$prompt" --arg c "$cwd" '{tool_input:{subagent_type:$s,prompt:$p},cwd:$c}')
  run bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$SCRIPT'"
}

write_graph() {
  # $1 = slug (định danh file, FORMAT v1.3: .claude/state/task-graph/<slug>.md),
  # $2 = header (canonical hoặc lệch), $3 = row đầy đủ (mặc định W/locked=yes)
  local slug="$1" header="$2" row="${3:-| 1 | foo | delegate-sonnet | W | yes | - | 1 | pending | verify x |}"
  mkdir -p "$PROJECT_DIR/.claude/state/task-graph"
  cat > "$PROJECT_DIR/.claude/state/task-graph/${slug}.md" << EOF
# task-graph: ${slug}
status: dispatched
integration-verify: -
integration-status: pending

${header}
${row}
EOF
}

@test "dispatch-gate: full compliant prompt allows" {
  run_hook "delegate-sonnet" "$FULL_PROMPT"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: missing verify marker blocks and names it" {
  prompt='Repo /Users/admin/proj branch main. Spec: implement X in src/foo.js per file paths listed. NO commit — produce diff only, return summary under 300 words. Extra padding text to reach length requirement for this case here now please.'
  run_hook "delegate-sonnet" "$prompt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"verify"* ]]
}

@test "dispatch-gate: missing repo path blocks" {
  prompt='Spec: implement X in foo.js per file paths listed. Acceptance: run test suite bats and verify pass. NO commit — produce diff only, return summary under 300 words padding text more more.'
  run_hook "delegate-sonnet" "$prompt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"repo path"* ]]
}

@test "dispatch-gate: short prompt (<200 chars) blocks" {
  run_hook "delegate-sonnet" "Repo /Users/admin/proj. Verify test. file path. commit no."
  [ "$status" -eq 2 ]
  [[ "$output" == *"quá ngắn"* ]]
}

@test "dispatch-gate: non-delegate subagent_type (Explore) allows regardless" {
  run_hook "Explore" "short"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: missing subagent_type allows" {
  json='{"tool_input":{"prompt":"short"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: non-JSON payload fails open" {
  run bash -c "printf 'not json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: HARNESS_DELEGATE=0 allows regardless" {
  run bash -c "printf 'not json' | HARNESS_DELEGATE=0 bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  json=$(jq -nc --arg s "delegate-sonnet" --arg p "too short" '{tool_input:{subagent_type:$s,prompt:$p}}')
  run bash -c "printf '%s' '$json' | HARNESS_DELEGATE=0 bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

# ── FORMAT v1.3: per-worktree graph (slug từ cwd) + header validation ──────
# Slug KHÔNG còn đọc từ nội dung file / marker — suy trực tiếp từ field `cwd`
# trong payload. Marker prompt quay lại v1 đơn giản: "task-graph #<id>" (không
# slug) vì mỗi session chỉ đọc đúng 1 file của mình, không còn khả năng lệch.

CANON_HEADER='| id | subtask | persona | rw | locked | deps | wave | status | verify |
|----|---------|---------|----|--------|------|------|--------|--------|'

@test "dispatch-gate: main-repo session (no worktree cwd) reads task-graph/main.md, marker #id allows" {
  write_graph "main" "$CANON_HEADER"
  prompt="${FULL_PROMPT} task-graph #1."
  run_hook "delegate-sonnet" "$prompt" "/Users/admin/repo"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: worktree session cwd resolves to matching slug graph, marker #id allows" {
  write_graph "close-graph-gaps" "$CANON_HEADER"
  prompt="${FULL_PROMPT} task-graph #1."
  run_hook "delegate-sonnet" "$prompt" "/Users/admin/repo/.claude/worktrees/close-graph-gaps"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: worktree session never sees another slug's graph (cross-contamination blocked)" {
  # main.md has row id=1 W/locked=no (would block); close-graph-gaps.md has id=1 W/locked=yes (would allow).
  # Session cwd'd into worktree "close-graph-gaps" — MUST read close-graph-gaps.md, not main.md.
  write_graph "main" "$CANON_HEADER" "| 1 | foo | delegate-sonnet | W | no | - | 1 | pending | verify x |"
  write_graph "close-graph-gaps" "$CANON_HEADER" "| 1 | foo | delegate-sonnet | W | yes | - | 1 | pending | verify x |"
  prompt="${FULL_PROMPT} task-graph #1."
  run_hook "delegate-sonnet" "$prompt" "/Users/admin/repo/.claude/worktrees/close-graph-gaps"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: main-repo session never sees a worktree's graph (cross-contamination blocked)" {
  # Inverse of above: main.md allows (locked=yes), close-graph-gaps.md would block (locked=no).
  # Session cwd on main repo (no worktree) — MUST read main.md.
  write_graph "main" "$CANON_HEADER" "| 1 | foo | delegate-sonnet | W | yes | - | 1 | pending | verify x |"
  write_graph "close-graph-gaps" "$CANON_HEADER" "| 1 | foo | delegate-sonnet | W | no | - | 1 | pending | verify x |"
  prompt="${FULL_PROMPT} task-graph #1."
  run_hook "delegate-sonnet" "$prompt" "/Users/admin/repo"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: missing task-graph marker blocks when graph exists for session's own slug" {
  write_graph "close-graph-gaps" "$CANON_HEADER"
  run_hook "delegate-sonnet" "$FULL_PROMPT" "/Users/admin/repo/.claude/worktrees/close-graph-gaps"
  [ "$status" -eq 2 ]
  [[ "$output" == *"task-graph"* ]]
}

@test "dispatch-gate: WRITE row locked=no blocks dispatch" {
  write_graph "close-graph-gaps" "$CANON_HEADER" "| 1 | foo | delegate-sonnet | W | no | - | 1 | pending | verify x |"
  prompt="${FULL_PROMPT} task-graph #1."
  run_hook "delegate-sonnet" "$prompt" "/Users/admin/repo/.claude/worktrees/close-graph-gaps"
  [ "$status" -eq 2 ]
  [[ "$output" == *"locked"* ]]
}

@test "dispatch-gate: marker id not present in graph blocks" {
  write_graph "close-graph-gaps" "$CANON_HEADER"
  prompt="${FULL_PROMPT} task-graph #99."
  run_hook "delegate-sonnet" "$prompt" "/Users/admin/repo/.claude/worktrees/close-graph-gaps"
  [ "$status" -eq 2 ]
}

@test "dispatch-gate: task-graph header mismatch fails open" {
  bad_header='| id | subtask | persona | extra | rw | locked | deps | wave | status | verify |
|----|---------|---------|----|--|--------|------|------|--------|--------|'
  write_graph "close-graph-gaps" "$bad_header"
  # Không có marker nào — với header canonical đây sẽ BLOCK (thiếu marker),
  # nhưng header lệch → gate tự tắt (fail-open), nên phải allow.
  run_hook "delegate-sonnet" "$FULL_PROMPT" "/Users/admin/repo/.claude/worktrees/close-graph-gaps"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: no graph file for session's own slug → allow (no gate)" {
  write_graph "some-other-slug" "$CANON_HEADER"
  run_hook "delegate-sonnet" "$FULL_PROMPT" "/Users/admin/repo/.claude/worktrees/close-graph-gaps"
  [ "$status" -eq 0 ]
}

@test "dispatch-gate: slug sanitizes trailing slash / nested path after worktree segment" {
  write_graph "close-graph-gaps" "$CANON_HEADER" "| 1 | foo | delegate-sonnet | W | no | - | 1 | pending | verify x |"
  prompt="${FULL_PROMPT} task-graph #1."
  run_hook "delegate-sonnet" "$prompt" "/Users/admin/repo/.claude/worktrees/close-graph-gaps/sub/dir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"locked"* ]]
}
