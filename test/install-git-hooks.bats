#!/usr/bin/env bats
# install-git-hooks.sh: symlinks (or copies) pre-push hook into .git/hooks/

load test_helper.bash

setup() {
  ROOT="$(repo_root)"
  TEST_REPO="$BATS_TEST_TMPDIR/test-repo"
  mkdir -p "$TEST_REPO"
  git init -q "$TEST_REPO"
}

teardown() {
  # Clean up test repo
  rm -rf "$TEST_REPO"
}

@test "symlinks pre-push into .git/hooks/pre-push, executable, correct content" {
  # Arrange: stage script + dev-hooks into test repo
  cp "$ROOT/install-git-hooks.sh" "$TEST_REPO/"
  mkdir -p "$TEST_REPO/dev-hooks/git-hooks"
  cp "$ROOT/dev-hooks/git-hooks/pre-push" "$TEST_REPO/dev-hooks/git-hooks/"
  
  # Act
  run bash -c "cd '$TEST_REPO' && bash install-git-hooks.sh"
  
  # Assert
  [ "$status" -eq 0 ]
  # Should print success (symlink or copy)
  [[ "$output" == *"symlinked"* ]] || [[ "$output" == *"copied"* ]]
  
  # Hook must exist and be executable
  [ -f "$TEST_REPO/.git/hooks/pre-push" ]
  [ -x "$TEST_REPO/.git/hooks/pre-push" ]
  
  # Content matches source
  cmp "$ROOT/dev-hooks/git-hooks/pre-push" "$TEST_REPO/.git/hooks/pre-push"
}

@test "idempotent — running twice succeeds, hook valid both times" {
  cp "$ROOT/install-git-hooks.sh" "$TEST_REPO/"
  mkdir -p "$TEST_REPO/dev-hooks/git-hooks"
  cp "$ROOT/dev-hooks/git-hooks/pre-push" "$TEST_REPO/dev-hooks/git-hooks/"
  
  # First run
  run bash -c "cd '$TEST_REPO' && bash install-git-hooks.sh"
  [ "$status" -eq 0 ]
  first_hook="$TEST_REPO/.git/hooks/pre-push"
  [ -x "$first_hook" ]
  first_content=$(cat "$first_hook")
  
  # Second run
  run bash -c "cd '$TEST_REPO' && bash install-git-hooks.sh"
  [ "$status" -eq 0 ]
  second_content=$(cat "$first_hook")
  
  # Hook unchanged, still executable
  [ "$first_content" = "$second_content" ]
  [ -x "$first_hook" ]
}

@test "missing gitleaks binary on PATH: script exits 0 with advisory warning only" {
  cp "$ROOT/install-git-hooks.sh" "$TEST_REPO/"
  mkdir -p "$TEST_REPO/dev-hooks/git-hooks"
  cp "$ROOT/dev-hooks/git-hooks/pre-push" "$TEST_REPO/dev-hooks/git-hooks/"
  
  # Create stub PATH without gitleaks
  stub_dir="$BATS_TEST_TMPDIR/stubpath"
  mkdir -p "$stub_dir"
  for tool in bash cat mkdir cp ln chmod git; do
    p=$(command -v "$tool")
    [ -n "$p" ] && ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  
  # Run with restricted PATH (no gitleaks)
  run env PATH="$stub_dir" bash -c "cd '$TEST_REPO' && bash install-git-hooks.sh"
  
  # Exit 0 (not failure — gitleaks missing is advisory)
  [ "$status" -eq 0 ]
  
  # Warning about missing gitleaks
  [[ "$output" == *"gitleaks"* ]]
  [[ "$output" == *"⚠️"* ]]
  
  # Hook still installed despite missing gitleaks
  [ -f "$TEST_REPO/.git/hooks/pre-push" ]
  [ -x "$TEST_REPO/.git/hooks/pre-push" ]
}

@test "missing source hook file: script exits 1 with clear error" {
  cp "$ROOT/install-git-hooks.sh" "$TEST_REPO/"
  # Deliberately do NOT copy dev-hooks/git-hooks/pre-push
  
  run bash -c "cd '$TEST_REPO' && bash install-git-hooks.sh"
  
  # Exit non-zero
  [ "$status" -ne 0 ]
  
  # Clear error message mentioning missing file
  [[ "$output" == *"không thấy"* ]] || [[ "$output" == *"❌"* ]]
  [[ "$output" == *"pre-push"* ]]
}
