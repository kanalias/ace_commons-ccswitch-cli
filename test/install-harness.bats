#!/usr/bin/env bats
# harness/install.sh: interactive installer that copies the
# orchestrator/delegate mechanism (subagents + hooks) into another project.
# Non-interactive mode is driven entirely via HARNESS_* env vars (see the
# header comment in harness/install.sh) — every test below uses that,
# never real stdin/terminal prompts.

load test_helper.bash

setup() {
  setup_fake_home
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

@test "dry run leaves missing target and temporary directory untouched" {
  export HARNESS_DRY_RUN=1
  export TMPDIR="$BATS_TEST_TMPDIR/dry-tmp"
  mkdir -p "$TMPDIR"
  TARGET="$BATS_TEST_TMPDIR/absent/nested"
  run_install
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET" ]
  [ -z "$(find "$TMPDIR" -mindepth 1 -print)" ]
  [[ "$output" == *"DRY RUN"* ]]
}

@test "dry run preserves existing files byte for byte" {
  mkdir -p "$TARGET/.claude"
  printf '{"env":{"CUSTOM":"keep"}}\n' > "$TARGET/.claude/settings.json"
  printf 'User instructions\n' > "$TARGET/CLAUDE.md"
  before="$(find "$TARGET" -type f -exec shasum {} \; | sort)"
  HARNESS_DRY_RUN=1 run_install
  [ "$status" -eq 0 ]
  after="$(find "$TARGET" -type f -exec shasum {} \; | sort)"
  [ "$before" = "$after" ]
}

@test "target branch is detected and source-only sync rule is excluded" {
  git -C "$TARGET" symbolic-ref HEAD refs/heads/custom-main
  HARNESS_ROUTE_DIR="$TARGET" run bash "$ROOT/harness/install.sh" </dev/null
  [ "$status" -eq 0 ]
  grep -q '`custom-main`' "$TARGET/.claude/rules/project/git-workflow.md"
  [ ! -e "$TARGET/.claude/rules/project/sync-template.md" ]
  grep -qi 'native.*rules' "$TARGET/CLAUDE.md"
  ! grep -q 'không có cơ chế.*built-in' "$TARGET/CLAUDE.md"
}

@test "guard and quality groups both disabled still writes a valid manifest (empty deny/env)" {
  HARNESS_ROUTE_DIR="$TARGET" \
  HARNESS_CORE_DIRS="src,lib" \
  HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" \
  HARNESS_TEST_CMD="npm test" \
  HARNESS_GROUP_SUBAGENTS="N" \
  HARNESS_GROUP_GUARD="N" \
  HARNESS_GROUP_QUALITY="N" \
  HARNESS_GROUP_SESSIONLIMIT="N" \
  HARNESS_OVERWRITE="all" \
  run bash "$ROOT/harness/install.sh" </dev/null
  [ "$status" -eq 0 ]

  manifest="$TARGET/.claude/harness-manifest.json"
  [ -f "$manifest" ]
  run jq empty "$manifest"
  [ "$status" -eq 0 ]
  jq -e '.schemaVersion == 1 and (.settings.deny == []) and (.settings.env == {})' "$manifest"
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
  [ ! -e "$TARGET/.claude/skills/lazy-load-health" ]
  [ -f "$TARGET/.claude/skills/dep-ladder-check/SKILL.md" ]
  [ ! -e "$TARGET/.claude/skills/auto-commit" ]
  [ -f "$TARGET/.claude/skills/check-hardcode/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/fix-ledger/SKILL.md" ]
  # merged into audit-context-memory / git-commit --auto / git-push-safety --scan-only
  [ ! -e "$TARGET/.claude/skills/audit-git-leak" ]

  # production-* skills are deploy-group opt-in (default N) — must NOT land
  [ ! -e "$TARGET/.claude/skills/production-deploy" ]
  [ ! -e "$TARGET/.claude/skills/production-cleanup" ]
  [ ! -e "$TARGET/.claude/skills/production-reboot" ]

  # commands group (default Y) — every former slash-command now ships ONLY as a
  # same-name skill; .claude/commands must never be created
  [ -s "$TARGET/.claude/skills/git-push-safety/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/task-loop-feature/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/update-claude/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/update-codex/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/update-gemini/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/update-deepseek/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/doctor-memory/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/git-commit/SKILL.md" ]
  # resume-orchestration was merged into the orchestrate skill — must NOT land
  [ ! -e "$TARGET/.claude/skills/resume-orchestration" ]
  [ -f "$TARGET/.claude/skills/orchestrate/SKILL.md" ]
  ! grep -q '9router' "$TARGET/.claude/skills/git-push-safety/SKILL.md" || false
  [ ! -e "$TARGET/.claude/commands" ]

  # rules group (default Y) — common/ (synced) + project/ (preserved)
  [ -f "$TARGET/.claude/rules/common/orchestrator.md" ]
  [ -f "$TARGET/.claude/rules/project/git-workflow.md" ]
  [ -f "$TARGET/.claude/rules/project/skill-superpowers.md" ]
  grep -q '"src/\*\*"' "$TARGET/.claude/rules/project/skill-superpowers.md"
  grep -q '"lib/\*\*"' "$TARGET/.claude/rules/project/skill-superpowers.md"

  # memory mirror index — scaffolded with rules group, slug substituted (preserve mode)
  [ -f "$TARGET/.claude/memory/MEMORY.md" ]
  grep -q 'testproj' "$TARGET/.claude/memory/MEMORY.md"
  ! grep -q '@@PROJECT_SLUG@@' "$TARGET/.claude/memory/MEMORY.md" || false

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

  # @@TEST_CMD@@ substituted into the Vietnamese phrase, no leftover token
  grep -q 'lệnh test của project: `npm test`' "$TARGET/.claude/skills/task-loop-feature/SKILL.md"
  ! grep -q '@@' "$TARGET/.claude/skills/task-loop-feature/SKILL.md" || false
}

@test "pre-existing .claude/memory/MEMORY.md custom content is kept unchanged, even with HARNESS_OVERWRITE=all" {
  mkdir -p "$TARGET/.claude/memory"
  printf '# My custom memory\n\n- [entry](entry.md) — do not clobber\n' > "$TARGET/.claude/memory/MEMORY.md"
  before="$(cat "$TARGET/.claude/memory/MEMORY.md")"
  run_install
  [ "$status" -eq 0 ]
  after="$(cat "$TARGET/.claude/memory/MEMORY.md")"
  [ "$before" = "$after" ]
}

@test "HARNESS_GROUP_DEPLOY=y installs production-* skills" {
  HARNESS_ROUTE_DIR="$TARGET" \
  HARNESS_CORE_DIRS="src,lib" \
  HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" \
  HARNESS_TEST_CMD="npm test" \
  HARNESS_GROUP_SUBAGENTS="Y" \
  HARNESS_GROUP_GUARD="Y" \
  HARNESS_GROUP_QUALITY="Y" \
  HARNESS_GROUP_SESSIONLIMIT="N" \
  HARNESS_GROUP_DEPLOY="y" \
  HARNESS_OVERWRITE="all" \
  run bash "$ROOT/harness/install.sh" </dev/null
  [ "$status" -eq 0 ]

  [ ! -e "$TARGET/.claude/commands" ]
  [ -f "$TARGET/.claude/skills/production-deploy/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/production-cleanup/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/production-reboot/SKILL.md" ]
}

run_install_deploy() {
  HARNESS_ROUTE_DIR="$TARGET" \
  HARNESS_CORE_DIRS="src,lib" \
  HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" \
  HARNESS_TEST_CMD="npm test" \
  HARNESS_GROUP_SUBAGENTS="Y" \
  HARNESS_GROUP_GUARD="Y" \
  HARNESS_GROUP_QUALITY="Y" \
  HARNESS_GROUP_SESSIONLIMIT="N" \
  HARNESS_GROUP_DEPLOY="y" \
  HARNESS_OVERWRITE="all" \
  run bash "$ROOT/harness/install.sh" </dev/null
}

@test "PROJECT_REMOTE_ID: remote renamed to 'original' (only remote) is used" {
  git -C "$TARGET" remote add original https://github.com/foo/bar.git
  git -C "$TARGET" commit --allow-empty -qm init
  run_install_deploy
  [ "$status" -eq 0 ]
  grep -q 'github.com/foo/bar' "$TARGET/.claude/skills/production-deploy/SKILL.md"
  ! grep -q '<project-remote-id>' "$TARGET/.claude/skills/production-deploy/SKILL.md"
}

@test "PROJECT_REMOTE_ID: two remotes, branch upstream is non-origin, uses upstream" {
  git -C "$TARGET" remote add upstreamx https://github.com/foo/up.git
  git -C "$TARGET" remote add original https://github.com/foo/bar.git
  git -C "$TARGET" commit --allow-empty -qm init
  git -C "$TARGET" symbolic-ref HEAD refs/heads/dev
  git -C "$TARGET" config branch.dev.remote upstreamx
  run_install_deploy
  [ "$status" -eq 0 ]
  grep -q 'github.com/foo/up' "$TARGET/.claude/skills/production-deploy/SKILL.md"
  ! grep -q 'github.com/foo/bar' "$TARGET/.claude/skills/production-deploy/SKILL.md"
}

@test "PROJECT_REMOTE_ID: >=2 remotes, no upstream, no origin falls back to placeholder" {
  git -C "$TARGET" remote add a https://github.com/foo/a.git
  git -C "$TARGET" remote add b https://github.com/foo/b.git
  git -C "$TARGET" commit --allow-empty -qm init
  run_install_deploy
  [ "$status" -eq 0 ]
  grep -q '<project-remote-id>' "$TARGET/.claude/skills/production-deploy/SKILL.md"
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
  # Edit|Write|MultiEdit|NotebookEdit + Bash + Task + mcp-browser gate = 4 matchers; no legacy Edit|Write orphan
  [ "$events_len" -eq 4 ]
  [ "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write")] | length' "$TARGET/.claude/settings.json")" -eq 0 ]
}

@test "migration: unmodified legacy .claude/commands/<name>.md (owned per previous manifest) is removed on reinstall" {
  run_install
  [ "$status" -eq 0 ]
  # simulate a pre-skills-only install that still shipped this command,
  # by hand-crafting a legacy commands/ file + manifest entry matching it.
  mkdir -p "$TARGET/.claude/commands"
  printf 'legacy content\n' > "$TARGET/.claude/commands/git-commit.md"
  sha=$(shasum -a 256 "$TARGET/.claude/commands/git-commit.md" | cut -d' ' -f1)
  tmp=$(mktemp)
  jq --arg p ".claude/commands/git-commit.md" --arg h "$sha" \
    '.syncFiles += [{path:$p, sha256:$h}]' "$TARGET/.claude/harness-manifest.json" > "$tmp"
  mv "$tmp" "$TARGET/.claude/harness-manifest.json"

  run_install
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET/.claude/commands/git-commit.md" ]
  [[ "$output" == *"removed"* ]]
}

@test "migration: modified legacy .claude/commands/<name>.md is kept with a warning" {
  run_install
  [ "$status" -eq 0 ]
  mkdir -p "$TARGET/.claude/commands"
  printf 'legacy content\n' > "$TARGET/.claude/commands/git-commit.md"
  sha=$(shasum -a 256 "$TARGET/.claude/commands/git-commit.md" | cut -d' ' -f1)
  tmp=$(mktemp)
  jq --arg p ".claude/commands/git-commit.md" --arg h "$sha" \
    '.syncFiles += [{path:$p, sha256:$h}]' "$TARGET/.claude/harness-manifest.json" > "$tmp"
  mv "$tmp" "$TARGET/.claude/harness-manifest.json"
  # user modified the file after our previous install — must be kept
  printf 'user edited this\n' > "$TARGET/.claude/commands/git-commit.md"

  run_install
  [ "$status" -eq 0 ]
  [ -f "$TARGET/.claude/commands/git-commit.md" ]
  grep -q 'user edited this' "$TARGET/.claude/commands/git-commit.md"
  [[ "$output" == *"WARN"*"git-commit.md modified — kept"* ]]
}

@test "migration: unmodified legacy skill (owned per previous manifest) is removed and dir gone on reinstall" {
  run_install
  [ "$status" -eq 0 ]
  # simulate a pre-merge install that still shipped this skill, by hand-crafting
  # a legacy skill dir + manifest entry matching it (mirrors legacy-command tests).
  mkdir -p "$TARGET/.claude/skills/lazy-load-health"
  printf 'legacy content\n' > "$TARGET/.claude/skills/lazy-load-health/SKILL.md"
  sha=$(shasum -a 256 "$TARGET/.claude/skills/lazy-load-health/SKILL.md" | cut -d' ' -f1)
  tmp=$(mktemp)
  jq --arg p ".claude/skills/lazy-load-health/SKILL.md" --arg h "$sha" \
    '.syncFiles += [{path:$p, sha256:$h}]' "$TARGET/.claude/harness-manifest.json" > "$tmp"
  mv "$tmp" "$TARGET/.claude/harness-manifest.json"

  run_install
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET/.claude/skills/lazy-load-health/SKILL.md" ]
  [ ! -d "$TARGET/.claude/skills/lazy-load-health" ]
  [[ "$output" == *"removed — merged into audit-context-memory"* ]]
}

@test "migration: modified legacy skill is kept with a warning" {
  run_install
  [ "$status" -eq 0 ]
  mkdir -p "$TARGET/.claude/skills/lazy-load-health"
  printf 'legacy content\n' > "$TARGET/.claude/skills/lazy-load-health/SKILL.md"
  sha=$(shasum -a 256 "$TARGET/.claude/skills/lazy-load-health/SKILL.md" | cut -d' ' -f1)
  tmp=$(mktemp)
  jq --arg p ".claude/skills/lazy-load-health/SKILL.md" --arg h "$sha" \
    '.syncFiles += [{path:$p, sha256:$h}]' "$TARGET/.claude/harness-manifest.json" > "$tmp"
  mv "$tmp" "$TARGET/.claude/harness-manifest.json"
  # user modified the file after our previous install — must be kept
  printf 'user edited this\n' > "$TARGET/.claude/skills/lazy-load-health/SKILL.md"

  run_install
  [ "$status" -eq 0 ]
  [ -f "$TARGET/.claude/skills/lazy-load-health/SKILL.md" ]
  grep -q 'user edited this' "$TARGET/.claude/skills/lazy-load-health/SKILL.md"
  [[ "$output" == *"WARN"*"lazy-load-health/SKILL.md modified — kept"* ]]
}

@test "migration: legacy skill dir with an extra file removes SKILL.md but keeps the dir with a warning" {
  run_install
  [ "$status" -eq 0 ]
  mkdir -p "$TARGET/.claude/skills/lazy-load-health"
  printf 'legacy content\n' > "$TARGET/.claude/skills/lazy-load-health/SKILL.md"
  sha=$(shasum -a 256 "$TARGET/.claude/skills/lazy-load-health/SKILL.md" | cut -d' ' -f1)
  tmp=$(mktemp)
  jq --arg p ".claude/skills/lazy-load-health/SKILL.md" --arg h "$sha" \
    '.syncFiles += [{path:$p, sha256:$h}]' "$TARGET/.claude/harness-manifest.json" > "$tmp"
  mv "$tmp" "$TARGET/.claude/harness-manifest.json"
  # extra user file left in the dir — rmdir must fail, dir stays
  printf 'notes\n' > "$TARGET/.claude/skills/lazy-load-health/notes.txt"

  run_install
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET/.claude/skills/lazy-load-health/SKILL.md" ]
  [ -d "$TARGET/.claude/skills/lazy-load-health" ]
  [ -f "$TARGET/.claude/skills/lazy-load-health/notes.txt" ]
  [[ "$output" == *"WARN: legacy skill dir .claude/skills/lazy-load-health/ has extra files — kept"* ]]
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
