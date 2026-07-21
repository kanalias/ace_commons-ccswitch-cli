#!/usr/bin/env bats
# harness-delegate/install.sh: interactive installer that copies the
# orchestrator/delegate mechanism (subagents + hooks) into another project.
# Non-interactive mode is driven entirely via HARNESS_* env vars (see the
# header comment in harness-delegate/install.sh) — every test below uses that,
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
  run bash "$ROOT/harness-delegate/install.sh" </dev/null
}

@test "installs 3 default groups: files land, no @@ tokens, settings.json wired" {
  run_install
  [ "$status" -eq 0 ]

  # subagents + wrappers
  [ -f "$TARGET/.claude/agents/delegate-deepseek.md" ]
  [ -f "$TARGET/.claude/agents/delegate-sonnet.md" ]
  [ -f "$TARGET/scripts/delegate/_common.sh" ]
  [ -x "$TARGET/scripts/delegate/run-gemini.sh" ]

  # guard + quality hooks
  [ -x "$TARGET/.claude/hooks/pre-edit-orchestrator-gate.sh" ]
  [ -x "$TARGET/.claude/hooks/pre-edit-secret-scan.sh" ]
  [ -x "$TARGET/.claude/hooks/post-edit-syntax-check.sh" ]
  [ -x "$TARGET/.claude/hooks/session-start-banner.sh" ]

  # session-limit group was declined — must NOT be installed
  [ ! -e "$TARGET/.claude/hooks/check-session-limit.sh" ]

  # skills group (default Y, not overridden above) — must land
  [ -f "$TARGET/.claude/skills/lazy-load-health/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/dep-ladder-check/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/auto-commit/SKILL.md" ]
  [ -f "$TARGET/.claude/skills/check-hardcode/SKILL.md" ]

  # commands group (default Y) — must land, non-empty, generic (no 9router leak)
  [ -s "$TARGET/.claude/commands/push-to-git.md" ]
  [ -f "$TARGET/.claude/commands/loop-feature.md" ]
  [ -f "$TARGET/.claude/commands/lazy-load-audit.md" ]
  [ -f "$TARGET/.claude/commands/audit-memory-harness.md" ]
  [ -f "$TARGET/.claude/commands/commit.md" ]
  ! grep -q '9router' "$TARGET/.claude/commands/push-to-git.md" || false

  # rules group (default Y) — must land, core-dirs substituted into paths: frontmatter
  [ -f "$TARGET/.claude/rules/git-workflow.md" ]
  [ -f "$TARGET/.claude/rules/skill-superpowers.md" ]
  grep -q '"src/\*\*"' "$TARGET/.claude/rules/skill-superpowers.md"
  grep -q '"lib/\*\*"' "$TARGET/.claude/rules/skill-superpowers.md"

  # no leftover placeholder tokens or 9router-specific hardcoding
  ! grep -rq '@@' "$TARGET" || false
  ! grep -rq 'open-sse\|ace_9router\|claude-code-9router\|decolua' "$TARGET" || false

  # settings.json valid + hooks wired under the right events
  run jq empty "$TARGET/.claude/settings.json"
  [ "$status" -eq 0 ]
  pre_count=$(jq '.hooks.PreToolUse[0].hooks | length' "$TARGET/.claude/settings.json")
  [ "$pre_count" -eq 2 ]
  post_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$TARGET/.claude/settings.json")
  [[ "$post_cmd" == *"post-edit-syntax-check.sh" ]]
  session_cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$TARGET/.claude/settings.json")
  [[ "$session_cmd" == *"session-start-banner.sh" ]]

  # slug substitution actually happened
  grep -q 'claude-code-testproj' "$TARGET/.claude/hooks/pre-edit-orchestrator-gate.sh"

  # branch substitution actually happened
  grep -q '`dev`' "$TARGET/.claude/rules/git-workflow.md"
}

@test "check-session-limit.sh has no leftover Session%/Weekly% mechanism" {
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
  run bash "$ROOT/harness-delegate/install.sh" </dev/null
  [ "$status" -eq 0 ]

  installed="$TARGET/.claude/hooks/check-session-limit.sh"
  [ -x "$installed" ]

  ! grep -q 'CLAUDE_SESSION_PCT' "$installed"
  ! grep -q 'session_pct' "$installed"
  ! grep -q 'orchestrator-hard' "$installed"
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
  [ "$events_len" -eq 1 ]
}
