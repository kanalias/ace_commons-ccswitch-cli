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
  # basename/sed/tr/sort/diff/grep/cat/chmod/printf: assumed-present coreutils
  # doctor.sh's Hooks: section uses internally — NOT probed for
  # presence/absence like the CLI: section above, so they belong in every
  # test's PATH rather than being toggled on/off per test.
  for bin in basename sed tr sort diff grep cat chmod printf mkdir awk; do
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

@test "doctor.sh: no timeout/gtimeout binary → WARN (not fail), mentions consequence + fix" {
  # STUBBIN deliberately has no timeout/gtimeout stub.
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"timeout/gtimeout not found"* ]]
  [[ "$output" == *"gtimeout"* ]]
}

@test "doctor.sh: timeout binary present → reports OK, not WARN" {
  ln -s "$(command -v timeout || command -v gtimeout || echo /usr/bin/true)" "$STUBBIN/timeout"
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ timeout (via timeout)"* ]]
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

# --- Hooks: section fixtures -----------------------------------------------
# doctor.sh computes its "baked slug" as claude-code-<basename of repo root>.
# STAGE's basename is "stage" (bats tmpdir layout), so fixture hook bodies use
# the literal "claude-code-stage" where a real hook would carry the baked slug.

stage_hook() {
  local name="$1" body="$2"
  mkdir -p "$STAGE/.claude/hooks"
  printf '%s\n' "$body" > "$STAGE/.claude/hooks/$name"
  chmod +x "$STAGE/.claude/hooks/$name"
}

stage_template_hook() {
  local name="$1" body="$2"
  mkdir -p "$STAGE/harness/templates/hooks"
  printf '%s\n' "$body" > "$STAGE/harness/templates/hooks/$name"
}

stage_settings_wiring() {
  # Wires whatever hook names are passed as args into a minimal settings.json.
  local name json_hooks="["
  local first=1
  for name in "$@"; do
    [[ "$first" -eq 1 ]] || json_hooks+=","
    first=0
    json_hooks+="{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"\$CLAUDE_PROJECT_DIR/.claude/hooks/$name\"}]}"
  done
  json_hooks+="]"
  mkdir -p "$STAGE/.claude"
  printf '{"hooks":{"PreToolUse":%s}}\n' "$json_hooks" > "$STAGE/.claude/settings.json"
}

@test "doctor.sh: hook wired + executable + syntax-ok + no drift → those checks pass" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  stage_hook "foo.sh" '#!/usr/bin/env bash
echo "claude-code-stage marker"
exit 0'
  stage_template_hook "foo.sh" '#!/usr/bin/env bash
echo "@@PROJECT_SLUG@@ marker"
exit 0'
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ wired: foo.sh"* ]]
  [[ "$output" == *"✓ syntax: foo.sh"* ]]
  [[ "$output" == *"✓ template match: foo.sh"* ]]
  [[ "$output" != *"unwired hook: foo.sh"* ]]
}

@test "doctor.sh: wired hook missing exec bit → FAIL counted, exit 1" {
  stage_hook "foo.sh" '#!/usr/bin/env bash
exit 0'
  chmod -x "$STAGE/.claude/hooks/foo.sh"
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ wired: foo.sh"* ]]
}

@test "doctor.sh: unwired extra hook file → warn line present, exit still 0" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  stage_hook "foo.sh" '#!/usr/bin/env bash
exit 0'
  stage_hook "extra.sh" '#!/usr/bin/env bash
exit 0'
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠ unwired hook: extra.sh"* ]]
}

@test "doctor.sh: template drift (real content change) → FAIL naming the file" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  stage_hook "foo.sh" '#!/usr/bin/env bash
echo "claude-code-stage marker"
echo "live-only behavior change"
exit 0'
  stage_template_hook "foo.sh" '#!/usr/bin/env bash
echo "@@PROJECT_SLUG@@ marker"
exit 0'
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ template match: foo.sh"* ]]
}

@test "doctor.sh: slug-vs-placeholder difference alone → NOT drift, passes" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  stage_hook "foo.sh" '#!/usr/bin/env bash
cache_dir="claude-code-stage/cache"
echo "$cache_dir"
exit 0'
  stage_template_hook "foo.sh" '#!/usr/bin/env bash
cache_dir="@@PROJECT_SLUG@@/cache"
echo "$cache_dir"
exit 0'
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ template match: foo.sh"* ]]
}

@test "doctor.sh: non-slug install-time token (@@CORE_DIRS_ALT@@) diff alone → NOT drift, passes" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  stage_hook "foo.sh" '#!/usr/bin/env bash
core_dirs="src"
echo "$core_dirs"
exit 0'
  stage_template_hook "foo.sh" '#!/usr/bin/env bash
core_dirs="@@CORE_DIRS_ALT@@"
echo "$core_dirs"
exit 0'
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ template match: foo.sh"* ]]
}

@test "doctor.sh: live has extra trailing line vs template → drift, FAIL" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  stage_hook "foo.sh" '#!/usr/bin/env bash
exit 0
echo "live-only extra line"'
  stage_template_hook "foo.sh" '#!/usr/bin/env bash
exit 0'
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ template match: foo.sh"* ]]
}

@test "doctor.sh: live missing a line the template has → drift, FAIL" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  stage_hook "foo.sh" '#!/usr/bin/env bash
exit 0'
  stage_template_hook "foo.sh" '#!/usr/bin/env bash
echo "template-only line"
exit 0'
  stage_settings_wiring "foo.sh"
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ template match: foo.sh"* ]]
}

@test "doctor.sh: jq missing → wiring subsection skipped, not fail, rest still runs" {
  rm -f "$STUBBIN/jq"
  stage_hook "foo.sh" '#!/usr/bin/env bash
exit 0'
  stage_settings_wiring "foo.sh"
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key-abc123
deepseek_api_key=fake-ds-key-def456
EOF
  run bash -c "cd '$STAGE' && PATH='$STUBBIN' bash scripts/delegate/doctor.sh"
  [[ "$output" == *"skipped (jq missing)"* ]]
  # jq also absent from the env-key resolution check earlier in the script —
  # this doctor.sh version doesn't use jq there, so status is unaffected by
  # jq alone; assert the hooks section specifically degraded gracefully.
  [[ "$output" == *"Hooks:"* ]]
}
