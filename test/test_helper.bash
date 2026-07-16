# Shared setup for all .bats files: fake $HOME so scripts under test never touch the
# real ~/.claude of the machine running the tests.
setup_fake_home() {
  export ORIG_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}
