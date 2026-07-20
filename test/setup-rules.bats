#!/usr/bin/env bats
# setup-rules.sh: mirror rules/*.md into $HOME/.claude/rules/ — always overwriting
# (no symlink mode), and removing any *.md at the destination not present in rules/.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/ai-memory-rules/setup-rules.sh"
}

@test "copy mode installs all rules/*.md" {
  run bash -c "echo y | '$SCRIPT'"
  [ "$status" -eq 0 ]
  count=$(ls "$HOME/.claude/rules"/*.md 2>/dev/null | wc -l | tr -d ' ')
  expected=$(ls "$ROOT/ai-memory-rules/rules"/*.md | wc -l | tr -d ' ')
  [ "$count" -eq "$expected" ]
}

@test "copy mode produces regular files, not symlinks" {
  bash -c "echo y | '$SCRIPT'" >/dev/null
  [ ! -L "$HOME/.claude/rules/orchestrator.md" ]
  [ -f "$HOME/.claude/rules/orchestrator.md" ]
}

@test "existing file is overwritten with repo content" {
  mkdir -p "$HOME/.claude/rules"
  echo "MY CUSTOM CONTENT" > "$HOME/.claude/rules/orchestrator.md"
  run bash -c "echo y | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"orchestrator.md (copied)"* ]]
  ! grep -q "MY CUSTOM CONTENT" "$HOME/.claude/rules/orchestrator.md"
  diff -q "$HOME/.claude/rules/orchestrator.md" "$ROOT/ai-memory-rules/rules/orchestrator.md"
}

@test "dangling symlink at destination is replaced with a real file" {
  mkdir -p "$HOME/.claude/rules"
  ln -s "/nonexistent/target" "$HOME/.claude/rules/orchestrator.md"
  run bash -c "echo y | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.claude/rules/orchestrator.md" ]
  [ -f "$HOME/.claude/rules/orchestrator.md" ]
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
  bash -c "echo y | '$SCRIPT'" >/dev/null
  run bash -c "echo y | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(copied)"* ]]
  count=$(ls "$HOME/.claude/rules"/*.md 2>/dev/null | wc -l | tr -d ' ')
  expected=$(ls "$ROOT/ai-memory-rules/rules"/*.md | wc -l | tr -d ' ')
  [ "$count" -eq "$expected" ]
}

@test "removes a destination rule not present in repo rules/" {
  mkdir -p "$HOME/.claude/rules"
  echo "orphan content" > "$HOME/.claude/rules/no-longer-in-repo.md"
  run bash -c "echo y | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-longer-in-repo.md (removed — not in repo)"* ]]
  [ ! -e "$HOME/.claude/rules/no-longer-in-repo.md" ]
}

@test "removes a destination symlink not present in repo rules/" {
  mkdir -p "$HOME/.claude/rules"
  ln -s "/nonexistent/target" "$HOME/.claude/rules/from-elsewhere.md"
  run bash -c "echo y | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"from-elsewhere.md (removed — not in repo)"* ]]
  [ ! -e "$HOME/.claude/rules/from-elsewhere.md" ]
  [ ! -L "$HOME/.claude/rules/from-elsewhere.md" ]
}

@test "mirror leaves destination exactly matching repo rules/ after run" {
  mkdir -p "$HOME/.claude/rules"
  echo "stale" > "$HOME/.claude/rules/orphan-one.md"
  ln -s "/nonexistent/target" "$HOME/.claude/rules/orphan-two.md"
  run bash -c "echo y | '$SCRIPT'"
  [ "$status" -eq 0 ]
  actual=$(cd "$HOME/.claude/rules" && ls *.md | sort)
  expected=$(cd "$ROOT/ai-memory-rules/rules" && ls *.md | sort)
  [ "$actual" = "$expected" ]
}
