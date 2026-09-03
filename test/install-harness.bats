#!/usr/bin/env bats
# harness/install.sh: interactive installer that copies the
# orchestrator/delegate mechanism (subagents + hooks) into another project.
# Non-interactive mode is driven entirely via HARNESS_* env vars (see the
# header comment in harness/install.sh) — every test below uses that,
# never real stdin/terminal prompts.

load test_helper.bash

setup() {
  ROOT="$(repo_root)"
  TARGET="$BATS_TEST_TMPDIR/target-repo"
  mkdir -p "$TARGET"
  git init -q "$TARGET"
  git -C "$TARGET" config user.email test@test.com
  git -C "$TARGET" config user.name test
}

run_install() {
  HARNESS_ROUTE_DIR="$TARGET" \
  HARNESS_CORE_DIRS="src,lib" \
  HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" \
  HARNESS_TEST_CMD="npm test" \
  HARNESS_GROUP_SUBAGENTS="Y" \
  HARNESS_GROUP_GUARD="Y" \
  HARNESS_GROUP_QUALITY="Y" \
  HARNESS_GROUP_SESSIONLIMIT="N" \
  HARNESS_OVERWRITE="all" \
  run bash "$ROOT/harness/install.sh" </dev/null
}

@test "installs 3 default groups: files land, no @@ tokens, settings.json wired" {
  run_install
  [ "$status" -eq 0 ]

  # subagents + wrappers
  [ -f "$TARGET/.claude/agents/delegate-deepseek.md" ]
  [ -f "$TARGET/.claude/agents/delegate-sonnet.md" ]
  [ -f "$TARGET/scripts/delegate/_common.sh" ]
  [ -x "$TARGET/scripts/delegate/run-gemini.sh" ]

  # guard hooks (merged 16->8: pre-edit-secret-scan+pre-edit-host-scan -> pre-edit-content-scan;
  # pre-bash-orchestrator-gate+pre-bash-git-push-gate+pre-bash-merge-verdict-gate -> pre-bash-gate)
  [ -x "$TARGET/.claude/hooks/pre-edit-orchestrator-gate.sh" ]
  [ -x "$TARGET/.claude/hooks/pre-bash-gate.sh" ]
  [ -x "$TARGET/.claude/hooks/pre-edit-content-scan.sh" ]
  [ -x "$TARGET/.claude/hooks/pre-task-dispatch-gate.sh" ]

  # quality hooks (merged: post-edit-syntax-check+remind-lazy-load-health+post-write-memory-mirror
  # -> post-edit-advisor; session-start-banner+session-start-ledger -> session-start;
  # stop-verdict-record+subagent-stop-ledger -> subagent-stop-record)
  [ -x "$TARGET/.claude/hooks/post-edit-advisor.sh" ]
  [ -x "$TARGET/.claude/hooks/session-start.sh" ]
  [ -x "$TARGET/.claude/hooks/post-bash-stuck-detector.sh" ]
  [ -x "$TARGET/.claude/hooks/subagent-stop-record.sh" ]

  # session-limit hook fully removed (not merged) in the consolidation — must NOT be installed
  [ ! -e "$TARGET/.claude/hooks/check-session-limit.sh" ]

  # skills group (default Y, not overridden above) — must land
  [ -f "$TARGET/.claude/skills/lazy-load-health/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/dep-ladder-check/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/auto-commit/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/check-hardcode/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/fix-ledger/SKILL.md" ]

  # commands group (default Y) — must land, non-empty, generic (no 9router leak)
  [ -s "$TARGET/.claude/commands/git-push-safety.md" ]
  [ -f "$TARGET/.claude/commands/task-loop-feature.md" ]
  [ -f "$TARGET/.claude/commands/doctor-memory.md" ]
  [ -f "$TARGET/.claude/commands/git-commit.md" ]
  ! grep -q '9router' "$TARGET/.claude/commands/git-push-safety.md" || false

  # rules group (default Y) — common/ (synced) + project/ (preserved)
  [ -f "$TARGET/.claude/rules/common/orchestrator.md" ]
  [ -f "$TARGET/.claude/rules/project/git-workflow.md" ]
  [ -f "$TARGET/.claude/rules/project/skill-superpowers.md" ]
  grep -q '"src/\*\*"' "$TARGET/.claude/rules/project/skill-superpowers.md"
  grep -q '"lib/\*\*"' "$TARGET/.claude/rules/project/skill-superpowers.md"

  # no leftover placeholder tokens or 9router-specific hardcoding
  # (sync-template.md is a doc *about* the @@TOKEN@@ mechanism, so it intentionally
  # contains @@ as illustration — exclude only that one file, nothing else)
  ! grep -rq '@@' --exclude='sync-template.md' "$TARGET" || false
  ! grep -rq 'open-sse\|ace_9router\|claude-code-9router\|decolua' "$TARGET" || false

  # settings.json valid + hooks wired under the right events
  run jq empty "$TARGET/.claude/settings.json"
  [ "$status" -eq 0 ]
  pre_count=$(jq '.hooks.PreToolUse[0].hooks | length' "$TARGET/.claude/settings.json")
  [ "$pre_count" -eq 2 ]
  post_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$TARGET/.claude/settings.json")
  [[ "$post_cmd" == *"post-edit-advisor.sh" ]]
  session_cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$TARGET/.claude/settings.json")
  [[ "$session_cmd" == *"session-start.sh" ]]

  # slug substitution actually happened
  grep -q 'claude-code-testproj' "$TARGET/.claude/hooks/pre-edit-orchestrator-gate.sh"

  # branch substitution actually happened
  grep -q '`dev`' "$TARGET/.claude/rules/project/git-workflow.md"
}

# check-session-limit.sh (old Session%/Weekly% mechanism) was fully removed
# in the 16->8 hook consolidation, not merged into another hook — advisory-only,
# superseded by the always-load token-budget.md rule (see MECHANISM.md 2026-07-31).
# HARNESS_GROUP_SESSIONLIMIT is a no-op leftover env var; must not resurrect the hook.
@test "check-session-limit.sh stays removed even if HARNESS_GROUP_SESSIONLIMIT=Y is set" {
  HARNESS_ROUTE_DIR="$TARGET" \
  HARNESS_CORE_DIRS="src,lib" \
  HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" \
  HARNESS_TEST_CMD="npm test" \
  HARNESS_GROUP_SUBAGENTS="Y" \
  HARNESS_GROUP_GUARD="Y" \
  HARNESS_GROUP_QUALITY="Y" \
  HARNESS_GROUP_SESSIONLIMIT="Y" \
  HARNESS_OVERWRITE="all" \
  run bash "$ROOT/harness/install.sh" </dev/null
  [ "$status" -eq 0 ]

  [ ! -e "$TARGET/.claude/hooks/check-session-limit.sh" ]
  ! grep -q 'check-session-limit.sh' "$TARGET/.claude/settings.json"
}

@test "risk-path denylist: HARNESS_RISK_DIRS wires into settings.json env, hook reads it at runtime" {
  HARNESS_ROUTE_DIR="$TARGET" \
  HARNESS_CORE_DIRS="src,lib" \
  HARNESS_RISK_DIRS="auth,wallet" \
  HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" \
  HARNESS_TEST_CMD="npm test" \
  HARNESS_GROUP_SUBAGENTS="Y" \
  HARNESS_GROUP_GUARD="Y" \
  HARNESS_GROUP_QUALITY="N" \
  HARNESS_GROUP_SESSIONLIMIT="N" \
  HARNESS_OVERWRITE="all" \
  run bash "$ROOT/harness/install.sh" </dev/null
  [ "$status" -eq 0 ]

  hook="$TARGET/.claude/hooks/pre-edit-orchestrator-gate.sh"
  [ -x "$hook" ]
  ! grep -q '@@\|RISK_DIRS_CASE\|RISK_DIRS_HUMAN' "$hook"

  # not baked into the hook file — lives in settings.json's env block instead
  risk=$(jq -r '.env.HARNESS_RISK_DIRS' "$TARGET/.claude/settings.json")
  [ "$risk" = "auth,wallet" ]

  # hook reads it live from the process environment (how Claude Code injects
  # settings.json's env block at hook-invocation time) — simulate that here.
  export HARNESS_RISK_DIRS="auth,wallet"

  run bash -c "echo '{\"agent_id\":\"a1\",\"agent_type\":\"delegate-gemini\",\"tool_input\":{\"file_path\":\"src/auth/login.ts\"}}' | bash '$hook'"
  [ "$status" -eq 2 ]

  run bash -c "echo '{\"agent_id\":\"a2\",\"agent_type\":\"delegate-deepseek\",\"tool_input\":{\"file_path\":\"wallet/balance.ts\"}}' | bash '$hook'"
  [ "$status" -eq 2 ]

  run bash -c "echo '{\"agent_id\":\"a3\",\"agent_type\":\"delegate-codex\",\"tool_input\":{\"file_path\":\"src/auth/login.ts\"}}' | bash '$hook'"
  [ "$status" -eq 0 ]

  run bash -c "echo '{\"agent_id\":\"a4\",\"agent_type\":\"delegate-gemini\",\"tool_input\":{\"file_path\":\"src/utils/format.ts\"}}' | bash '$hook'"
  [ "$status" -eq 0 ]

  # editing settings.json later (no reinstall) takes effect immediately
  export HARNESS_RISK_DIRS=""
  run bash -c "echo '{\"agent_id\":\"a5\",\"agent_type\":\"delegate-gemini\",\"tool_input\":{\"file_path\":\"src/auth/login.ts\"}}' | bash '$hook'"
  [ "$status" -eq 0 ]
  unset HARNESS_RISK_DIRS
}

@test "risk-path denylist defaults to no-op when HARNESS_RISK_DIRS unset" {
  run_install
  [ "$status" -eq 0 ]

  hook="$TARGET/.claude/hooks/pre-edit-orchestrator-gate.sh"
  [ -x "$hook" ]
  ! grep -q '@@' "$hook"

  risk=$(jq -r '.env.HARNESS_RISK_DIRS' "$TARGET/.claude/settings.json")
  [ "$risk" = "" ]

  run bash -c "echo '{\"agent_id\":\"a1\",\"agent_type\":\"delegate-gemini\",\"tool_input\":{\"file_path\":\"src/auth/login.ts\"}}' | bash '$hook'"
  [ "$status" -eq 0 ]
}

@test "re-running is idempotent — no duplicate hook entries" {
  run_install
  [ "$status" -eq 0 ]
  first_len=$(jq '.hooks.PreToolUse[0].hooks | length' "$TARGET/.claude/settings.json")

  run_install
  [ "$status" -eq 0 ]
  second_len=$(jq '.hooks.PreToolUse[0].hooks | length' "$TARGET/.claude/settings.json")
  events_len=$(jq '.hooks.PreToolUse | length' "$TARGET/.claude/settings.json")

  [ "$first_len" -eq "$second_len" ]
  # Edit|Write|MultiEdit|NotebookEdit + Bash + Task gate = 3 matchers; no legacy Edit|Write orphan
  [ "$events_len" -eq 3 ]
  [ "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write")] | length' "$TARGET/.claude/settings.json")" -eq 0 ]
}

@test "self-install guard blocks symlink pointing at harness source dir" {
  LINK="$BATS_TEST_TMPDIR/harness-link"
  ln -s "$ROOT/harness" "$LINK"

  HARNESS_ROUTE_DIR="$LINK" \
  HARNESS_CORE_DIRS="src" \
  HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" \
  HARNESS_GROUP_SUBAGENTS="Y" \
  HARNESS_OVERWRITE="all" \
  run bash "$ROOT/harness/install.sh" </dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *"Không tự-cài vào source dir"* ]]
  # guard must fire BEFORE any file gets written through the symlink
  [ ! -e "$ROOT/harness/.claude" ]
}

@test "git-hooks group installs executable gitleaks pre-push into .git/hooks/" {
  run_install
  [ "$status" -eq 0 ]
  [ -f "$TARGET/.git/hooks/pre-push" ]
  [ -x "$TARGET/.git/hooks/pre-push" ]
  grep -q 'gitleaks' "$TARGET/.git/hooks/pre-push"
  cmp "$ROOT/harness/templates/git-hooks/pre-push" "$TARGET/.git/hooks/pre-push"
}
