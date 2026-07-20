#!/usr/bin/env bats
# scripts/delegate/doctor.sh: preflight/diagnostic script — read-only, never
# modifies anything, never auto-fixes. Runs all checks even when some fail,
# never prints secret values. Stubs CLI binaries in a fake PATH — never
# invokes a real LLM CLI.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  STAGE="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE/scripts/delegate"
  cp "$ROOT"/scripts/delegate/*.sh "$STAGE/scripts/delegate/"
  chmod +x "$STAGE"/scripts/delegate/*.sh
  git init -q "$STAGE"
  git -C "$STAGE" config user.email test@test.com
  git -C "$STAGE" config user.name test
  git -C "$STAGE" add -A
  git -C "$STAGE" commit -q -m init

  STUBBIN="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$STUBBIN"
  for bin in bash git jq aider codex gemini; do
    real="$(command -v "$bin")"
    ln -s "$real" "$STUBBIN/$bin"
  done
}

@test "doctor.sh: all CLI present + git repo + env keys set → all pass, exit 0" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ git"* ]]
  [[ "$output" == *"✓ jq"* ]]
  [[ "$output" == *"✓ aider"* ]]
  [[ "$output" == *"✓ codex"* ]]
  [[ "$output" == *"✓ gemini"* ]]
  [[ "$output" == *"✓ cwd is inside a git work tree"* ]]
  [[ "$output" == *"✓ 9router (proxy_host + proxy_key) resolved"* ]]
  [[ "$output" == *"0 fail"* ]]
}

@test "doctor.sh: missing codex CLI → fails that line only, still runs rest, exit 1" {
  rm -f "$STUBBIN/codex"
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ codex"* ]]
  [[ "$output" == *"✓ git"* ]]
  [[ "$output" == *"✓ cwd is inside a git work tree"* ]]
  [[ "$output" == *"✓ 9router"* ]]
  [[ "$output" == *"fail"* ]]
}

@test "doctor.sh: outside a git repo → git-repo check fails, script completes, env section skipped" {
  NONGIT="$BATS_TEST_TMPDIR/nongit"
  mkdir -p "$NONGIT"
  run bash -c "cd '$NONGIT' && PATH='$STUBBIN' bash '$STAGE/scripts/delegate/doctor.sh'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ cwd is inside a git work tree"* ]]
  [[ "$output" == *"skipped — no git repo to locate .env"* ]]
  [[ "$output" == *"pass, "*"fail"* ]]
}

@test "doctor.sh: never leaks the actual secret value into stdout/stderr" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=SUPER-SECRET-VALUE-xyz789
deepseek_api_key=ANOTHER-SECRET-987
EOF
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  ! echo "$output" | grep -q "SUPER-SECRET-VALUE-xyz789"
  ! echo "$output" | grep -q "ANOTHER-SECRET-987"
}
