#!/usr/bin/env bats
# scripts/delegate/_common.sh + run-{aider-deepseek,gemini,codex}.sh: worktree
# isolation, env-alias chain, 9router vs fallback endpoint selection, and the
# gemini secret-path deny-list. Stubs the aider/gemini/codex binaries — never
# invokes a real LLM CLI, never touches the real ~/.gemini or the repo's own
# .worktrees/ (everything runs against a throwaway git repo + fake $HOME).

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
  grep -q "ARG: openai/ds/deepseek-v4-pro-max" "$CALLLOG"
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

# --- run-codex.sh: mode dispatch + endpoint selection ---------------------

@test "run-codex.sh: review mode is read-only, no worktree created" {
  write_stub codex
  run bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task review"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: review"* ]]
  grep -q -- "ARG: --sandbox" "$CALLLOG"
  grep -q "ARG: read-only" "$CALLLOG"
  [ ! -d "$STAGE/.worktrees" ]
}

@test "run-codex.sh: edit mode creates isolated worktree" {
  write_stub codex
  run bash -c "cd '$STAGE' && bash scripts/delegate/run-codex.sh feat task edit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: edit"* ]]
  [[ "$output" == *"WORKTREE="* ]]
  grep -q -- "ARG: --full-auto" "$CALLLOG"
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
  [[ "$output" == *".worktrees/agentx/featx"* ]]
  [ -d "$STAGE/.worktrees/agentx/featx" ]
  git -C "$STAGE" branch --list "delegate/agentx-featx" | grep -q delegate
}

@test "_common.sh ensure_worktree: refuses a dirty existing worktree on reuse (tracked change)" {
  bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx" >/dev/null
  # Modify a tracked file (unstaged) — this is what the dirty check inspects
  # (git diff / git diff --cached); untracked files are deliberately ignored.
  echo "# dirty" >> "$STAGE/.worktrees/agentx/featx/scripts/delegate/_common.sh"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is dirty"* ]]
}

@test "_common.sh ensure_worktree: reuse succeeds when only untracked files present" {
  bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx" >/dev/null
  echo dirty > "$STAGE/.worktrees/agentx/featx/untracked.txt"
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && ensure_worktree agentx featx"
  [ "$status" -eq 0 ]
}

@test "_common.sh require_env: fails with a clear message when var unset" {
  run bash -c "cd '$STAGE' && source scripts/delegate/_common.sh && require_env SOME_UNSET_VAR_XYZ"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SOME_UNSET_VAR_XYZ"* ]]
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
