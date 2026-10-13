#!/usr/bin/env bats
# harness/install.sh: (1) project-owned files with colliding names are kept on
# update (ownership = previous manifest syncFiles); (2) delegate model defaults
# are not silently reset to built-in literals (worktree .env fallback + manifest
# modelDefaults replay). Targets and harness copies live in BATS_TEST_TMPDIR only.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  TARGET="$BATS_TEST_TMPDIR/target-repo"
  mkdir -p "$TARGET"
  git init -q "$TARGET"
  # isolated harness copy (non-git, no .env above it) so the real checkout's .env never leaks in
  HCOPY="$BATS_TEST_TMPDIR/hcopy"
  mkdir -p "$HCOPY"
  cp -R "$ROOT/harness" "$HCOPY/harness"
  unset HARNESS_GEMINI_MODEL_DEFAULT HARNESS_CODEX_MODEL_DEFAULT HARNESS_DEEPSEEK_MODEL_DEFAULT HARNESS_ADOPT_FILES
}

inst() { # inst <install.sh path>
  HARNESS_ROUTE_DIR="$TARGET" HARNESS_CORE_DIRS="src" HARNESS_PROJECT_SLUG="testproj" \
  HARNESS_BRANCH="dev" HARNESS_TEST_CMD="npm test" HARNESS_OVERWRITE="all" \
  run bash "$1" </dev/null
}

M() { echo "$TARGET/.claude/harness-manifest.json"; }

# --- Bug 1: project-owned files -------------------------------------------

@test "project-owned file (not in previous syncFiles) is kept, in preservePaths, with NOTE" {
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  f=".claude/agents/browser-web.md"
  # simulate: file was hand-written by the project, manifest never claimed it
  jq --arg p "$f" '.syncFiles |= map(select(.path != $p))' "$(M)" > "$BATS_TEST_TMPDIR/m.json" && mv "$BATS_TEST_TMPDIR/m.json" "$(M)"
  echo "MY OWN CONTENT" > "$TARGET/$f"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(cat "$TARGET/$f")" = "MY OWN CONTENT" ]
  jq -e --arg p "$f" '.preservePaths | index($p)' "$(M)" >/dev/null
  ! jq -e --arg p "$f" '.syncFiles[] | select(.path==$p)' "$(M)" >/dev/null
  [[ "$output" == *"NOTE"*"$f"*"HARNESS_ADOPT_FILES"* ]]
}

@test "previously preserved path stays kept across updates" {
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  f=".claude/skills/web-browse/SKILL.md"
  jq --arg p "$f" '.syncFiles |= map(select(.path != $p)) | .preservePaths += [$p]' "$(M)" > "$BATS_TEST_TMPDIR/m.json" && mv "$BATS_TEST_TMPDIR/m.json" "$(M)"
  echo "MINE" > "$TARGET/$f"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(cat "$TARGET/$f")" = "MINE" ]
  jq -e --arg p "$f" '.preservePaths | index($p)' "$(M)" >/dev/null
}

@test "harness-owned file (in previous syncFiles) is still overwritten" {
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  f=".claude/agents/browser-web.md"; r=".claude/rules/common/general.md"
  echo "LOCAL EDIT" > "$TARGET/$f"; echo "LOCAL EDIT" > "$TARGET/$r"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(cat "$TARGET/$f")" != "LOCAL EDIT" ]
  [ "$(cat "$TARGET/$r")" != "LOCAL EDIT" ]
  jq -e --arg p "$f" '.syncFiles[] | select(.path==$p)' "$(M)" >/dev/null
  [[ "$output" != *"HARNESS_ADOPT_FILES"* ]]
}

@test "first install (no manifest) keeps legacy behaviour: HARNESS_OVERWRITE=all overwrites" {
  mkdir -p "$TARGET/.claude/agents"
  echo "PRE-EXISTING" > "$TARGET/.claude/agents/browser-web.md"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(cat "$TARGET/.claude/agents/browser-web.md")" != "PRE-EXISTING" ]
  [[ "$output" != *"HARNESS_ADOPT_FILES"* ]]
}

@test "HARNESS_ADOPT_FILES adopts the harness version of a project-owned file" {
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  f=".claude/agents/browser-web.md"; g=".claude/skills/seo/SKILL.md"
  jq '.syncFiles |= map(select(.path != ".claude/agents/browser-web.md"))' "$(M)" > "$BATS_TEST_TMPDIR/m.json" && mv "$BATS_TEST_TMPDIR/m.json" "$(M)"
  echo "MINE" > "$TARGET/$f"
  HARNESS_ADOPT_FILES="x/other.md,$f" inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(cat "$TARGET/$f")" != "MINE" ]
  jq -e --arg p "$f" '.syncFiles[] | select(.path==$p)' "$(M)" >/dev/null
  ! jq -e --arg p "$f" '.preservePaths | index($p)' "$(M)" >/dev/null
}

# --- Bug 2: model defaults --------------------------------------------------

@test "model defaults from .env are baked and recorded in manifest.modelDefaults" {
  printf 'GEMINI_MODEL=g-env\nCODEX_MODEL=c-env\nDEEPSEEK_MODEL=d-env\n' > "$HCOPY/.env"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(jq -r '.modelDefaults.gemini' "$(M)")" = "g-env" ]
  grep -q "g-env" "$TARGET/scripts/delegate/run-gemini.sh"
  [[ "$output" != *"g-env"* ]]
}

@test "update with only built-in default keeps the target's existing model + NOTE" {
  printf 'GEMINI_MODEL=g-env\nCODEX_MODEL=c-env\nDEEPSEEK_MODEL=d-env\n' > "$HCOPY/.env"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  rm "$HCOPY/.env"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(jq -r '.modelDefaults.gemini' "$(M)")" = "g-env" ]
  [ "$(jq -r '.modelDefaults.codex' "$(M)")" = "c-env" ]
  grep -q "g-env" "$TARGET/scripts/delegate/run-gemini.sh"
  [[ "$output" == *"NOTE"*"gemini"* ]]
}

@test "old manifest without modelDefaults still works (built-in literal used)" {
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  jq 'del(.modelDefaults)' "$(M)" > "$BATS_TEST_TMPDIR/m.json" && mv "$BATS_TEST_TMPDIR/m.json" "$(M)"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  jq -e '.modelDefaults.gemini | type == "string" and length > 0' "$(M)" >/dev/null
}

@test "explicit env override wins over preserved model; .env key wins too" {
  printf 'GEMINI_MODEL=g-env\n' > "$HCOPY/.env"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  HARNESS_GEMINI_MODEL_DEFAULT="g-override" inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(jq -r '.modelDefaults.gemini' "$(M)")" = "g-override" ]
  printf 'GEMINI_MODEL=g-new\n' > "$HCOPY/.env"
  inst "$HCOPY/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(jq -r '.modelDefaults.gemini' "$(M)")" = "g-new" ]
}

@test "linked worktree without .env falls back to the main checkout's .env" {
  MAIN="$BATS_TEST_TMPDIR/mainrepo"
  mkdir -p "$MAIN"; git init -q -b main "$MAIN"
  cp -R "$ROOT/harness" "$MAIN/harness"
  git -C "$MAIN" add -A >/dev/null
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q -m init
  git -C "$MAIN" worktree add -q "$BATS_TEST_TMPDIR/wt" -b wt
  printf 'GEMINI_MODEL=g-main-env\n' > "$MAIN/.env"
  [ ! -e "$BATS_TEST_TMPDIR/wt/.env" ]
  inst "$BATS_TEST_TMPDIR/wt/harness/install.sh"; [ "$status" -eq 0 ]
  [ "$(jq -r '.modelDefaults.gemini' "$(M)")" = "g-main-env" ]
  [[ "$output" != *"g-main-env"* ]]
}

@test "ownership: rules/common file missing from previous syncFiles is still overwritten" {
  local t="$BATS_TEST_TMPDIR/common-exempt"; mkdir -p "$t"; git -C "$t" init -q
  HARNESS_ROUTE_DIR="$t" HARNESS_CONFIRM_PATH=y HARNESS_INSTALL_ALL=y HARNESS_OVERWRITE=all bash "$(repo_root)/harness/install.sh" </dev/null >/dev/null 2>&1
  local m="$t/.claude/harness-manifest.json" f="$t/.claude/rules/common/general.md"
  jq '.syncFiles |= map(select(.path != ".claude/rules/common/general.md"))' "$m" > "$m.tmp" && mv "$m.tmp" "$m"
  echo "local edit" > "$f"
  HARNESS_ROUTE_DIR="$t" HARNESS_CONFIRM_PATH=y HARNESS_INSTALL_ALL=y HARNESS_OVERWRITE=all bash "$(repo_root)/harness/install.sh" </dev/null >/dev/null 2>&1
  ! grep -qx "local edit" "$f"
  jq -e '.syncFiles | map(.path) | index(".claude/rules/common/general.md")' "$m"
}
