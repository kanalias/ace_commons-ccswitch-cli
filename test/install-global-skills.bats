#!/usr/bin/env bats
# install-global-skills.sh — đồng bộ skill template → ~/.claude/skills, backup bản lệch, từ chối skill có token.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/install-global-skills.sh"
  # tầng ace nằm ngoài template public → dùng overlay giả để test cơ chế, không phụ thuộc nhánh private
  export HARNESS_ACE_DIR="$BATS_TEST_TMPDIR/ace"
  mkdir -p "$HARNESS_ACE_DIR/skills/ace-security-scan"
  printf -- '---\nname: ace-security-scan\ndescription: fake\n---\n' >"$HARNESS_ACE_DIR/skills/ace-security-scan/SKILL.md"
}

@test "install-global-skills: default installs ace-security-scan, rerun is no-op" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  diff -rq "$HARNESS_ACE_DIR/skills/ace-security-scan" "$HOME/.claude/skills/ace-security-scan"
  run bash "$SCRIPT"
  [[ "$output" == *"= ace-security-scan: đã mới nhất"* ]]
  [ ! -d "$HOME/.claude/skills/.trash" ]
}

@test "install-global-skills: drifted global copy is backed up then replaced" {
  mkdir -p "$HOME/.claude/skills/ace-security-scan"
  echo old >"$HOME/.claude/skills/ace-security-scan/SKILL.md"
  run bash "$SCRIPT" ace-security-scan
  [ "$status" -eq 0 ]
  diff -rq "$HARNESS_ACE_DIR/skills/ace-security-scan" "$HOME/.claude/skills/ace-security-scan"
  grep -qx old "$HOME"/.claude/skills/.trash/ace-security-scan-*/SKILL.md
}

@test "install-global-skills: ace skill without overlay fails clearly" {
  export HARNESS_ACE_DIR="$BATS_TEST_TMPDIR/none"
  run bash "$SCRIPT" ace-security-scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"overlay ace"* ]]
}

@test "install-global-skills: unknown skill fails" {
  run bash "$SCRIPT" no-such-skill
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.claude/skills/no-such-skill" ]
}

@test "install-global-skills: skill with @@TOKEN@@ is refused" {
  name="$(grep -rlE '@@[A-Z_]+@@' "$ROOT/harness/templates/skills"/*/ | head -1 | sed -E 's#.*/skills/([^/]+)/.*#\1#')"
  [ -n "$name" ] || skip "không có skill template chứa token"
  run bash "$SCRIPT" "$name"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.claude/skills/$name" ]
}
