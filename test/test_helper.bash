# Shared setup for all .bats files: fake $HOME so scripts under test never touch the
# real ~/.claude of the machine running the tests.
setup_fake_home() {
  export ORIG_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # Tests that don't explicitly wrap with `env` rely on a clean process env —
  # unset any router vars leaking from the real machine running the suite.
  unset ANTHROPIC_BASE_URL ANTHROPIC_DEFAULT_OPUS_MODEL
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}
