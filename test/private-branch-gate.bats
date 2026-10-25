#!/usr/bin/env bats
# private-branch gate: nhánh trong .claude/private-branches.txt chỉ push đúng remote.
# 2 lớp local: pre-bash-gate.sh bước 1.1 (trong Claude) + git-hooks/pre-push (mọi git push).
load test_helper

setup() {
  setup_fake_home
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
  printf '# c\nace-skill kane kanalias/ccswitch-kane\n' > "$CLAUDE_PROJECT_DIR/.claude/private-branches.txt"
  ROOT="$(repo_root)"
  GATE="$ROOT/harness/templates/hooks/pre-bash-gate.sh"
  PREPUSH="$ROOT/harness/templates/git-hooks/pre-push"
}

gate() { bash -c 'printf "%s" "$1" | bash "$2"' _ "$(jq -nc --arg c "$1" '{tool_input:{command:$c}}')" "$GATE"; }

@test "bash-gate: push ace-skill toi origin -> block (exit 2)" {
  run gate 'GIT_PUSH_GATE_OK=1 git push origin ace-skill'
  [ "$status" -eq 2 ]; [[ "$output" == *private-branch-gate* ]]
}

@test "bash-gate: push ace-skill:other toi origin -> block" {
  run gate 'GIT_PUSH_GATE_OK=1 git push origin ace-skill:main'
  [ "$status" -eq 2 ]
}

@test "bash-gate: push origin --all / --mirror -> block" {
  run gate 'GIT_PUSH_GATE_OK=1 git push origin --all'; [ "$status" -eq 2 ]
  run gate 'GIT_PUSH_GATE_OK=1 git push --mirror origin'; [ "$status" -eq 2 ]
}

@test "bash-gate: push ace-skill toi kane -> allow" {
  run gate 'GIT_PUSH_GATE_OK=1 git push kane ace-skill'
  [ "$status" -eq 0 ]
}

@test "bash-gate: push main toi origin -> allow (khong cham nhanh rieng)" {
  run gate 'GIT_PUSH_GATE_OK=1 git push origin main'
  [ "$status" -eq 0 ]
}

@test "bash-gate: khong co private-branches.txt -> no-op" {
  rm "$CLAUDE_PROJECT_DIR/.claude/private-branches.txt"
  run gate 'GIT_PUSH_GATE_OK=1 git push origin ace-skill'
  [ "$status" -eq 0 ]
}

# ── git pre-push hook (PATH không có gitleaks → bước 2 advisory, chỉ test bước 1) ──
@test "pre-push: ace-skill -> origin public -> exit 1" {
  mkdir -p "$BATS_TEST_TMPDIR/nobin"
  run bash -c "cd '$CLAUDE_PROJECT_DIR' && git init -q . && echo 'refs/heads/ace-skill 1111 refs/heads/ace-skill 0000' | PRIVATE_BRANCHES_FILE='$CLAUDE_PROJECT_DIR/.claude/private-branches.txt' PATH='$BATS_TEST_TMPDIR/nobin:/usr/bin:/bin' bash '$PREPUSH' origin git@github.com:kanalias/ace_commons-ccswitch-cli.git"
  [ "$status" -eq 1 ]; [[ "$output" == *private-branch-gate* ]]
}

@test "pre-push: ace-skill -> kane private -> qua gate (exit 0, gitleaks vang = advisory)" {
  mkdir -p "$BATS_TEST_TMPDIR/nobin"
  run bash -c "cd '$CLAUDE_PROJECT_DIR' && git init -q . && echo 'refs/heads/ace-skill 1111 refs/heads/ace-skill 0000' | PRIVATE_BRANCHES_FILE='$CLAUDE_PROJECT_DIR/.claude/private-branches.txt' PATH='$BATS_TEST_TMPDIR/nobin:/usr/bin:/bin' bash '$PREPUSH' kane git@github.com:kanalias/ccswitch-kane.git"
  [ "$status" -eq 0 ]
}

@test "pre-push: ace-skill:main -> origin (doi ten ref) -> exit 1" {
  mkdir -p "$BATS_TEST_TMPDIR/nobin"
  run bash -c "cd '$CLAUDE_PROJECT_DIR' && git init -q . && echo 'refs/heads/ace-skill 1111 refs/heads/main 0000' | PRIVATE_BRANCHES_FILE='$CLAUDE_PROJECT_DIR/.claude/private-branches.txt' PATH='$BATS_TEST_TMPDIR/nobin:/usr/bin:/bin' bash '$PREPUSH' origin git@github.com:kanalias/ace_commons-ccswitch-cli.git"
  [ "$status" -eq 1 ]
}

# ── private-path gate (pre-push 1b) ─────────────────────────────────────────
@test "pre-push: commit chua harness/templates-ace -> origin public -> exit 1; -> kane -> qua" {
  mkdir -p "$BATS_TEST_TMPDIR/nobin"
  printf 'harness/templates-ace kanalias/ccswitch-kane\n' >"$BATS_TEST_TMPDIR/pp.txt"
  : >"$BATS_TEST_TMPDIR/empty.txt"
  cd "$CLAUDE_PROJECT_DIR" && git init -q . && git config user.email t@t && git config user.name t
  mkdir -p harness/templates-ace/skills/x && echo a >harness/templates-ace/skills/x/SKILL.md
  git add harness && git commit -qm t && sha=$(git rev-parse HEAD)
  run bash -c "echo 'refs/heads/main $sha refs/heads/main 0000' | PRIVATE_BRANCHES_FILE='$BATS_TEST_TMPDIR/empty.txt' PRIVATE_PATHS_FILE='$BATS_TEST_TMPDIR/pp.txt' PATH='$BATS_TEST_TMPDIR/nobin:/usr/bin:/bin' bash '$PREPUSH' origin git@github.com:kanalias/ace_commons-ccswitch-cli.git"
  [ "$status" -eq 1 ]; [[ "$output" == *private-path-gate* ]]
  run bash -c "echo 'refs/heads/main $sha refs/heads/main 0000' | PRIVATE_BRANCHES_FILE='$BATS_TEST_TMPDIR/empty.txt' PRIVATE_PATHS_FILE='$BATS_TEST_TMPDIR/pp.txt' PATH='$BATS_TEST_TMPDIR/nobin:/usr/bin:/bin' bash '$PREPUSH' kane git@github.com:kanalias/ccswitch-kane.git"
  [ "$status" -eq 0 ]
}
