#!/usr/bin/env bats
# scripts/delegate/_common.sh + run-{aider-deepseek,gemini,codex}.sh: worktree
# isolation, env-alias chain, 9router vs fallback endpoint selection, and the
# gemini secret-path deny-list. Stubs the aider/gemini/codex binaries — never
# invokes a real LLM CLI, never touches the real ~/.gemini or the repo's own
# .claude/worktrees/ (everything runs against a throwaway git repo + fake $HOME).

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
  CALLLOG="$BATS_TEST_TMPDIR/calls.log"
  export CALLLOG
  PATH="$STUBBIN:$PATH"
  export PATH
}

# Fake LLM CLI binary: records its argv (one per line) + presence (not value)
# of a few env vars we care about, into $CALLLOG. Never prints secrets.
write_stub() {
  local name="$1" code="${2:-0}"
  cat > "$STUBBIN/$name" <<EOF
#!/usr/bin/env bash
{
  echo "=== \$0 called ==="
  for a in "\$@"; do echo "ARG: \$a"; done
  [[ -n "\${OPENAI_API_BASE:-}" ]] && echo "OPENAI_API_BASE_SET"
  [[ -n "\${OPENAI_API_KEY:-}" ]] && echo "OPENAI_API_KEY_SET"
  [[ -n "\${DEEPSEEK_API_KEY:-}" ]] && echo "DEEPSEEK_API_KEY_SET"
} >> "$CALLLOG"
exit $code
EOF
  chmod +x "$STUBBIN/$name"
}

# --- usage guards --------------------------------------------------------

@test "run-aider-deepseek.sh: usage guard exits 1 with <3 args" {
  run bash "$STAGE/scripts/delegate/run-aider-deepseek.sh" onlyfeat
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "run-gemini.sh: usage guard exits 1 with <2 args" {
  run bash "$STAGE/scripts/delegate/run-gemini.sh" onlyfeat
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "run-codex.sh: usage guard exits 1 with <2 args" {
  run bash "$STAGE/scripts/delegate/run-codex.sh" onlyfeat
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

# --- run-aider-deepseek.sh: endpoint selection ----------------------------

@test "run-aider-deepseek.sh: routes via 9router when PROXY_9ROUTER_* set" {
  write_stub aider
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key
EOF
  run bash -c "cd '$STAGE' && bash scripts/delegate/run-aider-deepseek.sh feat task file.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"endpoint: 9router"* ]]
  grep -q "OPENAI_API_BASE_SET" "$CALLLOG"
  grep -q "OPENAI_API_KEY_SET" "$CALLLOG"
  grep -q "ARG: openai/ds/deepseek-v4-pro" "$CALLLOG"
}

@test "run-aider-deepseek.sh: errors clearly when no 9router and no DEEPSEEK_API_KEY" {
  write_stub aider
  run bash -c "cd '$STAGE' && bash scripts/delegate/run-aider-deepseek.sh feat task file.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DEEPSEEK_API_KEY"* ]]
  [ ! -f "$CALLLOG" ]
}

@test "run-aider-deepseek.sh: falls back to direct DEEPSEEK_API_KEY when set" {
  write_stub aider
  run env DEEPSEEK_API_KEY=fake-direct-key bash -c "cd '$STAGE' && bash scripts/delegate/run-aider-deepseek.sh feat task file.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"endpoint: api.deepseek.com"* ]]
  grep -q "ARG: deepseek/deepseek-v4-pro" "$CALLLOG"
}

# Regression: aider's vendored GitRepo.__init__ calls
# `git.Repo(fname, search_parent_directories=True)` on the target file path.
# If the file's parent dir doesn't exist yet (fresh worktree, new subdir),
# GitPython raises NoSuchPathError, git detection silently fails, and aider
# falls back to using the file's own dirname as repo root — doubling nested
# paths (e.g. scripts/lib/scripts/lib/x.sh) and leaving the real target
# empty, despite aider reporting "Applied edit" successfully. Fix: wrapper
# mkdir -p's every file arg's parent dir before invoking aider.
@test "run-aider-deepseek.sh: pre-creates parent dir of a target file in a new subdir" {
  # Stub writes a marker file so the worktree isn't "clean" and doesn't get
  # auto-removed by the wrapper's exit-trap cleanup before we can inspect it.
  cat > "$STUBBIN/aider" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  [[ "$a" == *.sh ]] && [[ -d "$(dirname "$a")" ]] && echo marker > "$(dirname "$a")/.mkdir-ok"
done
exit 0
EOF
  chmod +x "$STUBBIN/aider"
  run env DEEPSEEK_API_KEY=fake-direct-key bash -c "cd '$STAGE' && bash scripts/delegate/run-aider-deepseek.sh feat task new/nested/dir/file.sh"
  [ "$status" -eq 0 ]
  worktree_dir=$(echo "$output" | grep -oE '/[^ ]*\.claude/worktrees/delegate-deepseek/feat' | head -1)
  [ -f "$worktree_dir/new/nested/dir/.mkdir-ok" ]
}

# --- run-codex.sh: mode dispatch + endpoint selection ---------------------

@test "run-codex.sh: review mode is read-only, no worktree created" {
  write_stub codex
  run env OPENAI_API_KEY=fake-openai-key bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task review"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: review"* ]]
  grep -q -- "ARG: --sandbox" "$CALLLOG"
  grep -q "ARG: read-only" "$CALLLOG"
  [ ! -d "$STAGE/.claude/worktrees" ]
}

@test "run-codex.sh: edit mode creates isolated worktree" {
  write_stub codex
  run env OPENAI_API_KEY=fake-openai-key bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task edit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: edit"* ]]
  [[ "$output" == *"WORKTREE="* ]]
  grep -q -- "ARG: --full-auto" "$CALLLOG"
}

@test "run-codex.sh: OpenAI-direct path errors clearly when no OPENAI_API_KEY and no codex login auth.json" {
  write_stub codex
  run bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task review"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no Codex auth found"* ]]
  [ ! -f "$CALLLOG" ]
}

@test "run-codex.sh: OpenAI-direct path succeeds when auth.json exists (no OPENAI_API_KEY needed)" {
  write_stub codex
  mkdir -p "$HOME/.codex"
  echo '{"fake":"auth"}' > "$HOME/.codex/auth.json"
  run bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task review"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: review"* ]]
}

@test "run-codex.sh: adds 9router provider args when PROXY_9ROUTER_* set" {
  write_stub codex
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key
EOF
  run bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task review"
  [ "$status" -eq 0 ]
  [[ "$output" == *"endpoint: 9router"* ]]
  grep -q 'model_provider="nexus9r"' "$CALLLOG"
}

# --- run-gemini.sh: secret deny-list + dispatch ---------------------------

@test "run-gemini.sh: refuses a secret-bearing context path" {
  echo "SECRET=x" > "$STAGE/.env"
  run bash -c "cd '$STAGE' && GEMINI_MODEL=test-model bash scripts/delegate/run-gemini.sh feat task .env"
  [ "$status" -eq 2 ]
  [[ "$output" == *"REFUSED secret-bearing path"* ]]
}

@test "run-gemini.sh: dispatches task prompt to gemini CLI (no account rotation)" {
  write_stub gemini
  run bash -c "cd '$STAGE' && GEMINI_MODEL=test-model bash scripts/delegate/run-gemini.sh feat 'do the thing'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WORKTREE="* ]]
  grep -q "ARG: do the thing" "$CALLLOG"
  grep -q "ARG: test-model" "$CALLLOG"
}

# --- _common.sh: ensure_worktree + require_env + load_env_chain ----------

@test "_common.sh ensure_worktree: rejects invalid agent-id chars" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree 'bad id' feat"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid chars"* ]]
}

@test "_common.sh ensure_worktree: rejects invalid feat-slug chars" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree goodagent 'bad feat'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid chars"* ]]
}

@test "_common.sh ensure_worktree: creates worktree + branch on first call" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx"
  [ "$status" -eq 0 ]
  [[ "$output" == *".claude/worktrees/agentx/featx"* ]]
  [ -d "$STAGE/.claude/worktrees/agentx/featx" ]
  git -C "$STAGE" branch --list "delegate/agentx-featx" | grep -q delegate
}

@test "_common.sh ensure_worktree: refuses a dirty existing worktree on reuse (tracked change)" {
  bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx" >/dev/null
  # Modify a tracked file (unstaged) — this is what the dirty check inspects
  # (git diff / git diff --cached); untracked files are deliberately ignored.
  echo "# dirty" >> "$STAGE/.claude/worktrees/agentx/featx/scripts/delegate/_common.sh"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is dirty"* ]]
}

@test "_common.sh ensure_worktree: reuse succeeds when only untracked files present" {
  bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx" >/dev/null
  echo dirty > "$STAGE/.claude/worktrees/agentx/featx/untracked.txt"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx"
  [ "$status" -eq 0 ]
}

@test "_common.sh require_env: fails with a clear message when var unset" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && require_env SOME_UNSET_VAR_XYZ"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SOME_UNSET_VAR_XYZ"* ]]
}

# --- _common.sh: report_run_status + harden_cli_env ----------------------

@test "_common.sh report_run_status: STATUS=done when all expected files touched after start" {
  mkdir -p "$STAGE/wt"
  start=$(date +%s)
  sleep 1
  touch "$STAGE/wt/a.txt"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && report_run_status '$STAGE/wt' $start a.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == "STATUS=done" ]]
}

@test "_common.sh report_run_status: STATUS=degraded when expected file not touched" {
  mkdir -p "$STAGE/wt"
  touch "$STAGE/wt/old.txt"
  sleep 1
  start=$(date +%s)
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && report_run_status '$STAGE/wt' $start old.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=degraded"* ]]
}

@test "_common.sh report_run_status: STATUS=partial when some but not all expected files touched" {
  mkdir -p "$STAGE/wt"
  touch "$STAGE/wt/old.txt"
  sleep 1
  start=$(date +%s)
  sleep 1
  touch "$STAGE/wt/new.txt"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && report_run_status '$STAGE/wt' $start old.txt new.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=partial (1/2 modified; missing: old.txt)"* ]]
}

@test "_common.sh report_run_status: no expected files — worktree-dirty fallback" {
  mkdir -p "$STAGE/wt2"
  git init -q "$STAGE/wt2"
  start=$(date +%s)
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && report_run_status '$STAGE/wt2' $start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=degraded (worktree clean"* ]]
  echo dirty > "$STAGE/wt2/x.txt"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && report_run_status '$STAGE/wt2' $start"
  [ "$status" -eq 0 ]
  [[ "$output" == "STATUS=done" ]]
}

@test "_common.sh harden_cli_env: unsets AIDER_AUTO_COMMITS, keeps legit override DEEPSEEK_MODEL" {
  run bash -c "cd '$STAGE' && export AIDER_AUTO_COMMITS=true DEEPSEEK_MODEL=custom-model && source scripts/delegate/_common.sh && harden_cli_env && echo AIDER=\${AIDER_AUTO_COMMITS:-unset} && echo DS=\$DEEPSEEK_MODEL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AIDER=unset"* ]]
  [[ "$output" == *"DS=custom-model"* ]]
}

# --- wrapper integration: STATUS= line reflects real file-touch outcome --

@test "run-aider-deepseek.sh: prints STATUS=degraded when aider touches none of the target files" {
  write_stub aider
  run env DEEPSEEK_API_KEY=fake-direct-key bash -c "cd '$STAGE' && bash scripts/delegate/run-aider-deepseek.sh feat task file.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=degraded"* ]]
}

@test "run-aider-deepseek.sh: prints STATUS=done when aider touches the target file" {
  cat > "$STUBBIN/aider" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  [[ "$a" == *.txt ]] && echo edited >> "$a"
done
exit 0
EOF
  chmod +x "$STUBBIN/aider"
  run env DEEPSEEK_API_KEY=fake-direct-key bash -c "cd '$STAGE' && bash scripts/delegate/run-aider-deepseek.sh feat task file.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=done"* ]]
}

# --- _common.sh: run_logged ----------------------------------------------

@test "_common.sh run_logged: creates log file, preserves cmd exit status + output" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && run_logged deepseek feat echo hello; echo STATUS=\$?; echo LOG=\$DELEGATE_RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=0"* ]]
  logpath=$(echo "$output" | grep -oE 'LOG=.*' | cut -d= -f2)
  [ -f "$logpath" ]
  grep -q "hello" "$logpath"
  [[ "$logpath" == *".claude/state/delegate-runs/deepseek-feat-"* ]]
}

@test "_common.sh run_logged: propagates a failing command's exit status" {
  # set +e after sourcing: _common.sh's `set -euo pipefail` is inherited by
  # this script (sourced, not subshelled) — without it, run_logged's nonzero
  # return kills the script before `echo STATUS=$?` runs.
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && set +e; run_logged deepseek feat false; echo STATUS=\$?"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=1"* ]]
}

@test "_common.sh run_logged: heartbeat subshell does not survive the call" {
  run bash -c "
    cd '$STAGE' && source scripts/delegate/_common.sh
    run_logged deepseek feat echo hi
    # Any bg job left in this shell after run_logged returns = orphaned heartbeat.
    jobs -p | wc -l | tr -d ' '
  "
  [ "$status" -eq 0 ]
  last_line=$(echo "$output" | tail -1)
  [ "$last_line" -eq 0 ]
}

@test "_common.sh load_env_chain: aliases proxy_host/proxy_key + deepseek_api_key" {
  cat > "$STAGE/.env" <<EOF
proxy_host=https://fake-9router.test/v1
proxy_key=fake-9router-key
deepseek_api_key=fake-ds-direct-key
EOF
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && load_env_chain && echo BASE=\$PROXY_9ROUTER_BASE_URL && echo HASKEY=\${PROXY_9ROUTER_TOKEN:+yes} && echo HASDS=\${DEEPSEEK_API_KEY:+yes}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BASE=https://fake-9router.test/v1"* ]]
  [[ "$output" == *"HASKEY=yes"* ]]
  [[ "$output" == *"HASDS=yes"* ]]
}

# --- P0 timeout enforcement (_common.sh with_timeout + wrapper wiring) ----

@test "_common.sh with_timeout: uses timeout binary when present, forwards seconds + command" {
  cat > "$STUBBIN/timeout" <<'EOF'
#!/usr/bin/env bash
echo "TIMEOUT_CALLED secs=$1" >> "$CALLLOG"
shift
exec "$@"
EOF
  chmod +x "$STUBBIN/timeout"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && with_timeout 5 echo hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  grep -q "TIMEOUT_CALLED secs=5" "$CALLLOG"
}

@test "_common.sh with_timeout: degrades to running without limit + warns when no timeout/gtimeout binary" {
  # STUBBIN deliberately has no timeout/gtimeout stub — PATH also excludes
  # any real system timeout by relying on the fake $HOME/stubbin-only PATH.
  run bash -c "cd '$STAGE' && PATH='$STUBBIN:/usr/bin:/bin' source scripts/delegate/_common.sh && with_timeout 5 echo hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  [[ "$output" == *"WARNING: no timeout/gtimeout binary found"* ]]
}

@test "run-aider-deepseek.sh: aider invocation is wrapped by timeout binary" {
  cat > "$STUBBIN/timeout" <<'EOF'
#!/usr/bin/env bash
echo "TIMEOUT_CALLED secs=$1" >> "$CALLLOG"
shift
exec "$@"
EOF
  chmod +x "$STUBBIN/timeout"
  write_stub aider
  run env DEEPSEEK_API_KEY=fake-direct-key bash -c "cd '$STAGE' && bash scripts/delegate/run-aider-deepseek.sh feat task file.txt"
  [ "$status" -eq 0 ]
  grep -q "TIMEOUT_CALLED secs=600" "$CALLLOG"
}

@test "run-codex.sh: codex invocation is wrapped by timeout binary + respects DELEGATE_TIMEOUT_SECS override" {
  cat > "$STUBBIN/timeout" <<'EOF'
#!/usr/bin/env bash
echo "TIMEOUT_CALLED secs=$1" >> "$CALLLOG"
shift
exec "$@"
EOF
  chmod +x "$STUBBIN/timeout"
  write_stub codex
  run env OPENAI_API_KEY=fake-openai-key DELEGATE_TIMEOUT_SECS=42 bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task review"
  [ "$status" -eq 0 ]
  grep -q "TIMEOUT_CALLED secs=42" "$CALLLOG"
}

@test "run-codex.sh: FAIL logged + exit 124 when codex times out" {
  cat > "$STUBBIN/timeout" <<'EOF'
#!/usr/bin/env bash
exit 124
EOF
  chmod +x "$STUBBIN/timeout"
  write_stub codex
  run env OPENAI_API_KEY=fake-openai-key bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task review"
  [ "$status" -eq 124 ]
  [[ "$output" == *"FAIL: codex timed out after"* ]]
}

@test "run-gemini.sh: gemini invocation is wrapped by timeout binary" {
  cat > "$STUBBIN/timeout" <<'EOF'
#!/usr/bin/env bash
echo "TIMEOUT_CALLED secs=$1" >> "$CALLLOG"
shift
exec "$@"
EOF
  chmod +x "$STUBBIN/timeout"
  write_stub gemini
  run bash -c "cd '$STAGE' && GEMINI_MODEL=test-model bash scripts/delegate/run-gemini.sh feat 'do the thing'"
  [ "$status" -eq 0 ]
  grep -q "TIMEOUT_CALLED secs=600" "$CALLLOG"
}

# --- P1 worktree path standardized under .claude/worktrees ---------------

@test "_common.sh ensure_worktree: worktree path lives under .claude/worktrees, not top-level .worktrees" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agenty featy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.claude/worktrees/agenty/featy" ]]
  [ -d "$STAGE/.claude/worktrees/agenty/featy" ]
  [ ! -d "$STAGE/.worktrees" ]
}

# --- P1 cleanup_worktree_if_clean: surfaces failure instead of swallowing -

@test "_common.sh cleanup_worktree_if_clean: warns + falls back to prune when worktree remove fails on a locked worktree" {
  run bash -c "
    cd '$STAGE' && source scripts/delegate/_common.sh
    WT=\$(ensure_worktree agentw featw)
    # Lock the worktree so 'git worktree remove --force' errors out (clean
    # diff/status still succeed — only 'remove' refuses), exercising the
    # warning + prune fallback branch instead of the old silent '|| true'.
    git -C \"\$REPO_ROOT\" worktree lock \"\$WT\"
    cleanup_worktree_if_clean \"\$WT\"
  "
  [[ "$output" == *"WARNING: worktree remove failed"* ]]
}

# --- P0 scan_task_for_secrets + check_no_new_commits ----------------------

@test "_common.sh scan_task_for_secrets: blocks TASK containing a fake Anthropic-shaped key" {
  # Fake key assembled at runtime via concatenation so the literal pattern
  # never sits whole in this source file (would itself trip the secret-scan
  # PreToolUse hook when this test file is edited/committed).
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && fake_key=\"sk-ant-\"\"abcdefghij1234567890ABCD\" && scan_task_for_secrets \"please use \$fake_key to auth\""
  [ "$status" -ne 0 ]
  [[ "$output" == *"TASK chứa pattern giống secret"* ]]
  [[ "$output" != *"abcdefghij1234567890ABCD"* ]]
}

@test "_common.sh scan_task_for_secrets: allows a clean TASK prompt through" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && scan_task_for_secrets 'refactor the auth middleware to fix the token expiry check'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_common.sh check_no_new_commits: detects HEAD change (CLI auto-committed) in a scratch git repo" {
  run bash -c "
    cd '$STAGE' && source scripts/delegate/_common.sh
    before=\$(git -C '$STAGE' rev-parse HEAD)
    echo more >> README_TEST.txt 2>/dev/null || echo more > README_TEST.txt
    git -C '$STAGE' add -A
    git -C '$STAGE' commit -q -m 'sneaky auto-commit'
    check_no_new_commits '$STAGE' \"\$before\"
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARNING: CLI committed inside worktree"* ]]
}
