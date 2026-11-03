#!/usr/bin/env bats
# push-safe.sh (skills/git-push-safety) + pre-bash-gate allow-list cho nó.
load test_helper

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  GATE="$ROOT/harness/templates/hooks/pre-bash-gate.sh"
  SCRIPT="$ROOT/harness/templates/skills/git-push-safety/push-safe.sh"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # gitleaks giả: luôn sạch (test logic script, không test gitleaks)
  printf '#!/bin/sh\ncat >/dev/null 2>&1 || true\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/gitleaks"
  chmod +x "$BATS_TEST_TMPDIR/bin/gitleaks"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git init -q -b main "$CLAUDE_PROJECT_DIR"
  cd "$CLAUDE_PROJECT_DIR"
  git config user.email t@t; git config user.name t
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  echo a > a.txt; git add a.txt; git commit -qm init
}

gate() { bash -c 'printf "%s" "$1" | bash "$2"' _ "$(jq -nc --arg c "$1" '{tool_input:{command:$c}}')" "$GATE"; }

@test "gate: push-safe.sh -> allow" {
  run gate 'sh .claude/skills/git-push-safety/push-safe.sh origin main'
  [ "$status" -eq 0 ]
}

@test "gate: cd <repo> && bash push-safe.sh -> allow" {
  run gate 'cd /abs/repo && bash .claude/skills/git-push-safety/push-safe.sh origin main'
  [ "$status" -eq 0 ]
}

@test "gate: push-safe.sh chained with raw git push -> block" {
  run gate 'sh .claude/skills/git-push-safety/push-safe.sh origin main && git push origin main'
  [ "$status" -eq 2 ]; [[ "$output" == *push-safe.sh* ]]
}

@test "gate: raw git push -> block, message points to push-safe.sh" {
  run gate 'git push origin main'
  [ "$status" -eq 2 ]; [[ "$output" == *push-safe.sh* ]]
}

@test "gate: tools/push-safe.sh lookalike outside .claude/skills -> not special (raw push inside still blocked)" {
  run gate 'sh evil/push-safe.sh origin main; git push origin main'
  [ "$status" -eq 2 ]
}

@test "script: refuses --force / --all / --tags" {
  run sh "$SCRIPT" --force origin main; [ "$status" -ne 0 ]; [[ "$output" == *refuses* ]]
  run sh "$SCRIPT" --all origin main;   [ "$status" -ne 0 ]
  run sh "$SCRIPT" --tags origin main;  [ "$status" -ne 0 ]
}

@test "script: new branch -> push + ls-remote verify PASS" {
  run sh "$SCRIPT" origin main
  [ "$status" -eq 0 ]; [[ "$output" == *"PUSH-SAFE OK"* ]]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$(git rev-parse HEAD)" ]
}

@test "script: second push fast-forward -> PASS" {
  sh "$SCRIPT" origin main >/dev/null
  echo b > b.txt; git add b.txt; git commit -qm b
  run sh "$SCRIPT" origin main
  [ "$status" -eq 0 ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$(git rev-parse HEAD)" ]
}

@test "script: remote diverged -> STOP, nothing pushed" {
  sh "$SCRIPT" origin main >/dev/null
  other="$BATS_TEST_TMPDIR/other"; git clone -q -b main "$BATS_TEST_TMPDIR/remote.git" "$other"
  (cd "$other" && git config user.email t@t && git config user.name t && echo x > x && git add x && git commit -qm x && git push -q origin main)
  remote_sha=$(git ls-remote origin refs/heads/main | cut -f1)
  echo c > c.txt; git add c.txt; git commit -qm c
  run sh "$SCRIPT" origin main
  [ "$status" -ne 0 ]; [[ "$output" == *non-fast-forward* ]]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$remote_sha" ]
}

@test "script: private branch to wrong remote -> STOP" {
  mkdir -p .claude
  printf 'ace-skill kane|backup kanalias/ccswitch-kane\n' > .claude/private-branches.txt
  git checkout -qb ace-skill
  run sh "$SCRIPT" origin ace-skill
  [ "$status" -ne 0 ]; [[ "$output" == *private-branch* ]]
  [ -z "$(git ls-remote origin refs/heads/ace-skill)" ]
}

@test "script: tracked .env -> STOP" {
  echo X=1 > .env; git add -f .env; git commit -qm env
  run sh "$SCRIPT" origin main
  [ "$status" -ne 0 ]; [[ "$output" == *forbidden* ]]
}

@test "script: push non-current branch tip" {
  git branch side
  git checkout -qb work
  echo w > w.txt; git add w.txt; git commit -qm w
  run sh "$SCRIPT" origin side
  [ "$status" -eq 0 ]
  [ "$(git ls-remote origin refs/heads/side | cut -f1)" = "$(git rev-parse side)" ]
}
