#!/usr/bin/env bats
# harness/templates/hooks/pre-compact-guard.sh — PreCompact (auto) guard:
# block (exit 2) khi task-graph của đúng slug session đang dở; mọi trường hợp
# khác exit 0 im lặng. Manual /compact không bao giờ bị chặn.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  HOOK="$ROOT/harness/templates/hooks/pre-compact-guard.sh"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state/task-graph"
}

write_graph() { # write_graph <slug> <status>
  printf '# task-graph: %s\nstatus: %s\nintegration-verify: -\nintegration-status: pending\n' "$1" "$2" \
    > "$CLAUDE_PROJECT_DIR/.claude/state/task-graph/$1.md"
}

run_hook() { # run_hook <trigger> [cwd]
  local json
  json=$(jq -nc --arg t "$1" --arg c "${2:-$CLAUDE_PROJECT_DIR}" '{hook_event_name:"PreCompact",trigger:$t,cwd:$c}')
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$HOOK"
}

@test "compact-guard: auto + graph dispatched → BLOCK exit 2, stderr names slug" {
  write_graph main dispatched
  run_hook auto
  [ "$status" -eq 2 ]
  [[ "$output" == *"main"* ]]
  [[ "$output" == *"/compact"* ]]
}

@test "compact-guard: auto + no graph → allow silently" {
  run_hook auto
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "compact-guard: auto + graph done → allow" {
  write_graph main done
  run_hook auto
  [ "$status" -eq 0 ]
}

@test "compact-guard: manual trigger never blocked even with graph in progress" {
  write_graph main integrating
  run_hook manual
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "compact-guard: slug from worktree cwd — only that worktree's graph counts" {
  write_graph main dispatched
  run_hook auto "$CLAUDE_PROJECT_DIR/.claude/worktrees/feat-x/src"
  [ "$status" -eq 0 ]
  write_graph feat-x review
  run_hook auto "$CLAUDE_PROJECT_DIR/.claude/worktrees/feat-x/src"
  [ "$status" -eq 2 ]
  [[ "$output" == *"feat-x"* ]]
}

@test "compact-guard: HARNESS_DELEGATE=0 off-switch allows" {
  write_graph main dispatched
  json='{"trigger":"auto"}'
  run bash -c 'printf "%s" "$1" | HARNESS_DELEGATE=0 bash "$2"' _ "$json" "$HOOK"
  [ "$status" -eq 0 ]
}

@test "compact-guard: malformed JSON fails open silently" {
  write_graph main dispatched
  run bash -c 'printf "%s" "{malformed" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
