#!/usr/bin/env bats
# 3 tầng skill: common (templates/skills) · ace (overlay HARNESS_ACE_DIR, private) · local (skill project tự tạo, không bị ghi đè/xoá).
load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  TARGET="$BATS_TEST_TMPDIR/proj"; mkdir -p "$TARGET"; git -C "$TARGET" init -q
  ACE="$BATS_TEST_TMPDIR/ace"; mkdir -p "$ACE/skills/ace-fake"
  printf -- '---\nname: ace-fake\ndescription: fake ace skill\nuser-invocable: true\n---\nbody\n' >"$ACE/skills/ace-fake/SKILL.md"
}
inst() { env HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 HARNESS_CONFIRM_PATH=y HARNESS_INSTALL_ALL=y HARNESS_ACE_DIR="${ACE_OVERRIDE-$ACE}" bash "$ROOT/harness/install.sh" </dev/null; }

@test "main public khong chua skill ace-* trong templates" {
  run bash -c "ls '$ROOT/harness/templates/skills' | grep -c '^ace-'"
  [ "$output" = "0" ]
}

@test "khong overlay -> cai ok, khong co ace-*, co NOTE" {
  ACE_OVERRIDE=/nonexistent run inst
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET/.claude/skills/ace-fake" ]
  [[ "$output" == *"overlay"* ]]
}

@test "co overlay -> ace-* duoc cai va ghi vao manifest" {
  run inst
  [ "$status" -eq 0 ]
  [ -f "$TARGET/.claude/skills/ace-fake/SKILL.md" ]
  jq -e '.syncFiles[] | select(.path==".claude/skills/ace-fake/SKILL.md")' "$TARGET/.claude/harness-manifest.json" >/dev/null
  jq -e --arg a "$ACE" '.installEnv.HARNESS_ACE_DIR==$a' "$TARGET/.claude/harness-manifest.json" >/dev/null
}

@test "local: skill project tu tao trung ten KHONG bi de o lan cai dau" {
  mkdir -p "$TARGET/.claude/skills/ace-fake" "$TARGET/.claude/skills/diagram"
  echo 'LOCAL ace-fake' >"$TARGET/.claude/skills/ace-fake/SKILL.md"
  echo 'LOCAL diagram' >"$TARGET/.claude/skills/diagram/SKILL.md"
  run inst
  [ "$status" -eq 0 ]
  grep -qx 'LOCAL ace-fake' "$TARGET/.claude/skills/ace-fake/SKILL.md"
  grep -qx 'LOCAL diagram' "$TARGET/.claude/skills/diagram/SKILL.md"
}

@test "local: skill khong co trong template giu nguyen qua re-sync va uninstall" {
  mkdir -p "$TARGET/.claude/skills/my-local"
  echo 'mine' >"$TARGET/.claude/skills/my-local/SKILL.md"
  run inst; [ "$status" -eq 0 ]
  run inst; [ "$status" -eq 0 ]
  grep -qx mine "$TARGET/.claude/skills/my-local/SKILL.md"
  run env HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 bash "$ROOT/harness/install.sh" uninstall </dev/null
  [ "$status" -eq 0 ]
  grep -qx mine "$TARGET/.claude/skills/my-local/SKILL.md"
}

@test "local: HARNESS_ADOPT_FILES ep lay ban harness" {
  mkdir -p "$TARGET/.claude/skills/ace-fake"
  echo 'LOCAL' >"$TARGET/.claude/skills/ace-fake/SKILL.md"
  run env HARNESS_ADOPT_FILES=.claude/skills/ace-fake/SKILL.md HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 HARNESS_CONFIRM_PATH=y HARNESS_INSTALL_ALL=y HARNESS_ACE_DIR="$ACE" bash "$ROOT/harness/install.sh" </dev/null
  [ "$status" -eq 0 ]
  grep -q 'fake ace skill' "$TARGET/.claude/skills/ace-fake/SKILL.md"
}
