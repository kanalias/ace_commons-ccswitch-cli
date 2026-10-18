#!/usr/bin/env bats

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

install_harness() {
  HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 run bash "$ROOT/harness/install.sh" </dev/null
}

uninstall_harness() {
  HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 run bash "$ROOT/harness/install.sh" uninstall </dev/null
}

@test "install writes atomic ownership manifest with complete schema" {
  install_harness
  [ "$status" -eq 0 ]
  manifest="$TARGET/.claude/harness-manifest.json"
  [ -f "$manifest" ]
  jq -e '.schemaVersion == 1 and (.harnessVersion | type == "string") and
    (.syncFiles | type == "array") and (.preservePaths | type == "array") and
    (.settings.hooks | type == "array") and (.settings.deny | type == "array") and
    (.settings.env | type == "object") and
    ((.settings.statusLineCommand == null) or (.settings.statusLineCommand | type == "string"))' "$manifest"
  [ "$(jq '[.syncFiles[] | select(.path == ".claude/harness-manifest.json")] | length' "$manifest")" -eq 0 ]
  [ "$(find "$TARGET/.claude" -name '.harness-manifest.json.*' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "settings manifest records only newly added conservative deny entries" {
  mkdir -p "$TARGET/.claude"
  printf '%s\n' '{"permissions":{"deny":["Read(./.env)","User(custom)"]}}' > "$TARGET/.claude/settings.json"
  install_harness
  [ "$status" -eq 0 ]
  [ "$(jq '.permissions.deny | length' "$TARGET/.claude/settings.json")" -eq 16 ]
  [ "$(jq '[.settings.deny[] | select(. == "Read(./.env)")] | length' "$TARGET/.claude/harness-manifest.json")" -eq 0 ]
  [ "$(jq '.settings.deny | length' "$TARGET/.claude/harness-manifest.json")" -eq 14 ]
  jq -e '.permissions.deny | index("Read(./.env.*)") and index("Edit(./secrets/**)") and index("Write(./**/*.pem)") and index("Bash(git push -f:*)")' "$TARGET/.claude/settings.json"
}

@test "install adds project-local Bash allow, records ownership, uninstall removes only it" {
  mkdir -p "$TARGET/.claude"
  printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$TARGET/.claude/settings.json"
  install_harness
  [ "$status" -eq 0 ]
  jq -e '.permissions.allow | index("Bash") and index("Bash(ls:*)")' "$TARGET/.claude/settings.json"
  jq -e '.settings.allow == ["Bash"]' "$TARGET/.claude/harness-manifest.json"
  install_harness
  [ "$(jq '[.permissions.allow[] | select(. == "Bash")] | length' "$TARGET/.claude/settings.json")" -eq 1 ]
  jq -e '.settings.allow == ["Bash"]' "$TARGET/.claude/harness-manifest.json"

  uninstall_harness
  [ "$status" -eq 0 ]
  jq -e '.permissions.allow == ["Bash(ls:*)"]' "$TARGET/.claude/settings.json"
}

@test "preexisting Bash allow is not claimed; HARNESS_ALLOW_BASH=0 skips it" {
  mkdir -p "$TARGET/.claude"
  printf '%s\n' '{"permissions":{"allow":["Bash"]}}' > "$TARGET/.claude/settings.json"
  install_harness
  [ "$status" -eq 0 ]
  jq -e '.settings.allow == []' "$TARGET/.claude/harness-manifest.json"
  uninstall_harness
  jq -e '.permissions.allow == ["Bash"]' "$TARGET/.claude/settings.json"

  other="$BATS_TEST_TMPDIR/optout"; mkdir -p "$other"; git -C "$other" init -q
  HARNESS_ALLOW_BASH=0 HARNESS_ROUTE_DIR="$other" HARNESS_ASSUME_YES=1 run bash "$ROOT/harness/install.sh" </dev/null
  [ "$status" -eq 0 ]
  jq -e '(.permissions.allow // []) | index("Bash") | not' "$other/.claude/settings.json"
}

@test "custom statusline and preexisting env are not claimed or removed" {
  mkdir -p "$TARGET/.claude"
  printf '%s\n' '{"env":{"HARNESS_DELEGATE":"0","HARNESS_RISK_DIRS":"custom"},"statusLine":{"type":"command","command":"custom-status"}}' > "$TARGET/.claude/settings.json"
  install_harness
  [ "$status" -eq 0 ]
  [ "$(jq '.settings.env | length' "$TARGET/.claude/harness-manifest.json")" -eq 0 ]
  [ "$(jq -r '.settings.statusLineCommand' "$TARGET/.claude/harness-manifest.json")" = "null" ]

  uninstall_harness
  [ "$status" -eq 0 ]
  jq -e '.env.HARNESS_DELEGATE == "0" and .env.HARNESS_RISK_DIRS == "custom" and .statusLine.command == "custom-status"' "$TARGET/.claude/settings.json"
}

@test "positional uninstall removes exact owned files and settings but preserves user data" {
  mkdir -p "$TARGET/.claude"
  printf '%s\n' '{"env":{"CUSTOM":"keep"},"permissions":{"deny":["User(custom)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"user-hook"}]}]}}' > "$TARGET/.claude/settings.json"
  install_harness
  [ "$status" -eq 0 ]
  [ -f "$TARGET/.claude/agents/delegate-sonnet.md" ]

  uninstall_harness
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET/.claude/harness-manifest.json" ]
  [ ! -e "$TARGET/.claude/agents/delegate-sonnet.md" ]
  jq -e '.env.CUSTOM == "keep" and (.permissions.deny | index("User(custom)")) and ([.hooks.PreToolUse[]?.hooks[]? | select(.command == "user-hook")] | length == 1)' "$TARGET/.claude/settings.json"
  [ "$(jq '[.. | objects | .command? // empty | select(contains(".claude/hooks/"))] | length' "$TARGET/.claude/settings.json")" -eq 0 ]
}

@test "uninstall removes only the managed block from preexisting CLAUDE.md" {
  printf 'User preface\n\nUser suffix\n' > "$TARGET/CLAUDE.md"
  install_harness
  [ "$status" -eq 0 ]
  grep -q 'BEGIN HARNESS RULES' "$TARGET/CLAUDE.md"

  uninstall_harness
  [ "$status" -eq 0 ]
  grep -q 'User preface' "$TARGET/CLAUDE.md"
  grep -q 'User suffix' "$TARGET/CLAUDE.md"
  ! grep -q 'HARNESS RULES' "$TARGET/CLAUDE.md"
}

@test "--uninstall preserves modified sync files and preserve-path files" {
  install_harness
  [ "$status" -eq 0 ]
  printf '\nlocal edit\n' >> "$TARGET/.claude/hooks/pre-bash-gate.sh"
  printf '\nlocal allowlist\n' >> "$TARGET/.claude/allowed-hosts.txt"

  HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 run bash "$ROOT/harness/install.sh" --uninstall </dev/null
  [ "$status" -eq 0 ]
  grep -q 'local edit' "$TARGET/.claude/hooks/pre-bash-gate.sh"
  grep -q 'local allowlist' "$TARGET/.claude/allowed-hosts.txt"
  [ ! -e "$TARGET/.claude/harness-manifest.json" ]
}

@test "dry-run uninstall makes no changes" {
  install_harness
  [ "$status" -eq 0 ]
  before="$(find "$TARGET" -type f -exec shasum {} \; | sort)"
  HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 HARNESS_DRY_RUN=1 run bash "$ROOT/harness/install.sh" uninstall </dev/null
  [ "$status" -eq 0 ]
  after="$(find "$TARGET" -type f -exec shasum {} \; | sort)"
  [ "$before" = "$after" ]
}
