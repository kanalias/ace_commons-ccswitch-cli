#!/usr/bin/env bats
# setup-rules.sh: install rules/*.md into $HOME/.claude/rules/ via copy or symlink,
# never clobbering existing files.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/setup-rules.sh"
}

@test "copy mode installs all rules/*.md" {
  run bash -c "echo c | '$SCRIPT'"
  [ "$status" -eq 0 ]
  count=$(ls "$HOME/.claude/rules"/*.md 2>/dev/null | wc -l | tr -d ' ')
  expected=$(ls "$ROOT/rules"/*.md | wc -l | tr -d ' ')
  [ "$count" -eq "$expected" ]
}

@test "copy mode produces regular files, not symlinks" {
  bash -c "echo c | '$SCRIPT'" >/dev/null
  [ ! -L "$HOME/.claude/rules/orchestrator.md" ]
  [ -f "$HOME/.claude/rules/orchestrator.md" ]
}

@test "symlink mode installs rules as symlinks to source" {
  run bash -c "echo s | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/rules/orchestrator.md" ]
}

@test "existing file is kept, not overwritten" {
  mkdir -p "$HOME/.claude/rules"
  echo "MY CUSTOM CONTENT" > "$HOME/.claude/rules/orchestrator.md"
  run bash -c "echo c | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exists — kept"* ]]
  grep -q "MY CUSTOM CONTENT" "$HOME/.claude/rules/orchestrator.md"
}

@test "dangling symlink at destination is treated as existing, not crashed on" {
  mkdir -p "$HOME/.claude/rules"
  ln -s "/nonexistent/target" "$HOME/.claude/rules/orchestrator.md"
  run bash -c "echo c | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exists — kept"* ]]
}

@test "no input (EOF) skips install without crashing" {
  run bash -c ": | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}

@test "answer N skips install" {
  run bash -c "echo N | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
  [ ! -d "$HOME/.claude/rules" ] || [ -z "$(ls -A "$HOME/.claude/rules" 2>/dev/null)" ]
}

@test "is idempotent across two copy runs" {
  bash -c "echo c | '$SCRIPT'" >/dev/null
  run bash -c "echo c | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exists — kept"* ]]
}
