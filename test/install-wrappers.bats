#!/usr/bin/env bats
# install-9router-proxy.sh: OS-detecting dispatcher.
# We only assert dispatch logic (which backend gets invoked), not the backend's own
# behavior (covered by setup.sh's own testing).

load test_helper.bash

setup() {
  ROOT="$(repo_root)"
}

stage_setup_checkout() {
  checkout="$BATS_TEST_TMPDIR/staged-checkout"
  foreign_cwd="$BATS_TEST_TMPDIR/foreign-cwd"
  mkdir -p "$checkout/ai-proxy" "$foreign_cwd"
  cp "$ROOT/ai-proxy/setup.sh" "$ROOT/ai-proxy/ccswitch.sh" \
    "$ROOT/ai-proxy/statusline-context.sh" "$checkout/ai-proxy/"
  cp -R "$ROOT/ai-proxy/hooks" "$ROOT/ai-proxy/profiles" "$checkout/ai-proxy/"
}

@test "install-9router-proxy.sh runs setup.sh on non-Windows OSTYPE" {
  run env OSTYPE="darwin23" bash -c "cd '$ROOT' && echo N | bash install-9router-proxy.sh"
  [ "$status" -eq 0 ]
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

@test "setup.sh does NOT pin a default model on a fresh install" {
  # By design (setup.sh 3b): no `.model` is written — Claude Code picks per its own
  # default. Forcing a pin caused a stale model to be requested after endpoint switches.
  setup_fake_home
  run bash -c "cd '$ROOT' && echo N | bash ai-proxy/setup.sh"
  [ "$status" -eq 0 ]
  model=$(jq -r '.model // "unset"' "$HOME/.claude/settings.json")
  [ "$model" = "unset" ]
}

@test "setup.sh does not clobber an existing model preference" {
  setup_fake_home
  mkdir -p "$HOME/.claude"
  echo '{"model":"opus"}' > "$HOME/.claude/settings.json"
  run bash -c "cd '$ROOT' && echo N | bash ai-proxy/setup.sh"
  [ "$status" -eq 0 ]
  # setup.sh never touches .model, so a pre-existing preference survives untouched.
  model=$(jq -r '.model' "$HOME/.claude/settings.json")
  [ "$model" = "opus" ]
}

@test "setup.sh links ccswitch.sh from a staged checkout when invoked from foreign CWD" {
  setup_fake_home
  stage_setup_checkout

  run env HOME="$HOME" SHELL="/bin/zsh" bash -c "cd '$foreign_cwd' && printf 'N\\n' | bash '$checkout/ai-proxy/setup.sh'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/ccswitch.sh" ]
  [ "$(readlink "$HOME/.claude/ccswitch.sh")" = "$checkout/ai-proxy/ccswitch.sh" ]
}

@test "setup.sh replaces stale ccswitch.sh and converges aliases on rerun" {
  setup_fake_home
  stage_setup_checkout
  mkdir -p "$HOME/.claude"
  printf 'stale file\n' > "$HOME/.claude/ccswitch.sh"

  run env HOME="$HOME" SHELL="/bin/zsh" bash -c "cd '$foreign_cwd' && printf 'N\\n' | bash '$checkout/ai-proxy/setup.sh'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/ccswitch.sh" ]
  [ "$(readlink "$HOME/.claude/ccswitch.sh")" = "$checkout/ai-proxy/ccswitch.sh" ]

  run env HOME="$HOME" SHELL="/bin/zsh" bash -c "cd '$foreign_cwd' && printf 'N\\n' | bash '$checkout/ai-proxy/setup.sh'"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^alias ccswitch=' "$HOME/.zshrc")" -eq 1 ]
}
