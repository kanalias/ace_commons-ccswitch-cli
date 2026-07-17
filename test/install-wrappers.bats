#!/usr/bin/env bats
# install-9router-proxy.sh / install-claude-memory.sh: OS-detecting dispatchers.
# We only assert dispatch logic (which backend gets invoked), not the backend's own
# behavior (covered by setup-rules.bats / setup.sh's own testing).

load test_helper.bash

setup() {
  ROOT="$(repo_root)"
}

@test "install-9router-proxy.sh runs setup.sh on non-Windows OSTYPE" {
  run env OSTYPE="darwin23" bash -c "cd '$ROOT' && echo N | bash install-9router-proxy.sh"
  [ "$status" -eq 0 ]
}

@test "install-claude-memory.sh runs setup-rules.sh on non-Windows OSTYPE" {
  run env OSTYPE="darwin23" bash -c "cd '$ROOT' && echo N | bash install-claude-memory.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}

@test "install-9router-proxy.sh errors clearly when cygpath missing on msys" {
  # Simulate Git Bash without cygpath on PATH by stripping it out.
  stub_dir="$BATS_TEST_TMPDIR/stubpath"
  mkdir -p "$stub_dir"
  for tool in bash cat mkdir cp jq curl grep sed tr basename dirname; do
    p=$(command -v "$tool")
    ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  run env OSTYPE="msys" PATH="$stub_dir" bash -c "cd '$ROOT' && bash install-9router-proxy.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cygpath"* ]]
}

@test "install-claude-memory.sh errors clearly when cygpath missing on msys" {
  stub_dir="$BATS_TEST_TMPDIR/stubpath2"
  mkdir -p "$stub_dir"
  for tool in bash cat mkdir cp jq curl grep sed tr basename dirname; do
    p=$(command -v "$tool")
    ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  run env OSTYPE="cygwin" PATH="$stub_dir" bash -c "cd '$ROOT' && bash install-claude-memory.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cygpath"* ]]
}

@test "setup.sh sets default model to sonnet on a fresh install" {
  setup_fake_home
  run bash -c "cd '$ROOT' && echo N | bash setup.sh"
  [ "$status" -eq 0 ]
  model=$(jq -r '.model' "$HOME/.claude/settings.json")
  [ "$model" = "sonnet" ]
}

@test "setup.sh does not clobber an existing model preference" {
  setup_fake_home
  mkdir -p "$HOME/.claude"
  echo '{"model":"opus"}' > "$HOME/.claude/settings.json"
  run bash -c "cd '$ROOT' && echo N | bash setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already has a model preference"* ]]
  model=$(jq -r '.model' "$HOME/.claude/settings.json")
  [ "$model" = "opus" ]
}
