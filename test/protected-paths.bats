#!/usr/bin/env bats
# Protected-path delete guard trong template pre-bash-gate.sh (task-graph #15).
load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  R="$BATS_TEST_TMPDIR/hooks"; mkdir -p "$R"
  sed -e 's#@@CORE_DIRS_CASE@@#*/src/*|src/*#g' -e 's#@@CORE_DIRS_ALT@@#src#g' \
      -e 's#@@CORE_DIRS_HUMAN@@#src/#g' -e 's#@@PROJECT_SLUG@@#t#g' \
      "$ROOT/harness/templates/hooks/pre-bash-gate.sh" > "$R/pre-bash-gate.sh"
  P="$BATS_TEST_TMPDIR/proj"; mkdir -p "$P/.claude"
  unset CLAUDE_PROJECT_DIR ORCHESTRATOR_GATE_BYPASS HARNESS_DELEGATE
}

# gate <cmd> [agent_id] [cwd]
gate() {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "$(jq -nc --arg c "$1" --arg a "${2:-}" --arg w "${3:-$P}" \
       '{tool_input:{command:$c},cwd:$w} + (if $a=="" then {} else {agent_id:$a} end)')" \
    "$R/pre-bash-gate.sh"
}
list() { printf '%s\n' "$@" > "$P/.claude/protected-paths.txt"; }

@test "no list file: rm -rf passes" {
  gate "rm -rf x"; [ "$status" -eq 0 ]
}

@test "comment-only / blank list is a no-op" {
  list "# data/backup" "" "   "
  gate "rm -rf data/backup/2024"; [ "$status" -eq 0 ]
}

@test "rm -rf on protected path blocks and names the entry" {
  list "# c" "data/backup"
  gate "rm -rf data/backup/2024"; [ "$status" -eq 2 ]
  [[ "$output" == *"data/backup"* ]]
}

@test "find -delete / find -exec rm block" {
  list "data/backup"
  gate "find data/backup -delete"; [ "$status" -eq 2 ]
  gate "find data/backup -name x -exec rm {} \\;"; [ "$status" -eq 2 ]
}

@test "rsync --delete and git clean block" {
  list "data/backup"
  gate "rsync -a --delete src/ data/backup/"; [ "$status" -eq 2 ]
  gate "git clean -fdx data/backup"; [ "$status" -eq 2 ]
}

@test "chained / quoted / subshell / xargs forms block" {
  list "data/backup"
  gate "cd /tmp && rm -rf \"data/backup/x\""; [ "$status" -eq 2 ]
  gate "ls; (rm -rf 'data/backup')"; [ "$status" -eq 2 ]
  gate "ls data/backup | xargs rm"; [ "$status" -eq 2 ]
}

@test "read-only access to protected path is allowed" {
  list "data/backup"
  gate "ls data/backup"; [ "$status" -eq 0 ]
  gate "cat data/backup/a"; [ "$status" -eq 0 ]
  gate "cp data/backup/a /tmp/a"; [ "$status" -eq 0 ]
  gate "grep -r foo data/backup"; [ "$status" -eq 0 ]
}

@test "rm on unrelated path is allowed" {
  list "data/backup"
  gate "rm -rf other/dir"; [ "$status" -eq 0 ]
}

@test "subagent (agent_id) is blocked too" {
  list "data/backup"
  gate "rm -rf data/backup/x" sub-123; [ "$status" -eq 2 ]
}

@test "ORCHESTRATOR_GATE_BYPASS=1 (env and in-command) does not bypass" {
  list "data/backup"
  ORCHESTRATOR_GATE_BYPASS=1 gate "rm -rf data/backup"; [ "$status" -eq 2 ]
  gate "ORCHESTRATOR_GATE_BYPASS=1 rm -rf data/backup"; [ "$status" -eq 2 ]
}

@test "HARNESS_DELEGATE=0 does not disable the guard" {
  list "data/backup"
  HARNESS_DELEGATE=0 gate "rm -rf data/backup"; [ "$status" -eq 2 ]
  HARNESS_DELEGATE=0 gate "rm -rf other"; [ "$status" -eq 0 ]
}

@test "cwd inside .claude/worktrees/<slug>/ uses the main repo list" {
  list "data/backup"
  mkdir -p "$P/.claude/worktrees/x/sub"
  gate "rm -rf data/backup" "" "$P/.claude/worktrees/x/sub"; [ "$status" -eq 2 ]
}

@test "cwd in a subdirectory walks up to the list" {
  list "data/backup"
  mkdir -p "$P/a/b"
  gate "rm -rf data/backup" "" "$P/a/b"; [ "$status" -eq 2 ]
}

@test "non-JSON payload fails open" {
  list "data/backup"
  run bash -c 'printf "%s" "rm -rf data/backup" | bash "$1"' _ "$R/pre-bash-gate.sh"
  [ "$status" -eq 0 ]
}
