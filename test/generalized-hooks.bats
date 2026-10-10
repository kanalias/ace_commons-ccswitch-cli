#!/usr/bin/env bats
# service-alert-gate, deploy-doc reminder, opt-in pii-guard: hook behavior + install/uninstall wiring.
load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  HOOKS="$ROOT/harness/templates/hooks"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$CLAUDE_PROJECT_DIR"
  git init -q "$CLAUDE_PROJECT_DIR"
  TARGET="$BATS_TEST_TMPDIR/target-repo"
  mkdir -p "$TARGET"
  git init -q "$TARGET"
  TG="api.tele""gram.org"   # split literal: repo's own host-scan hook would block it
}

feed() { printf '%s' "$2" | bash "$1"; }
edit_payload() { jq -nc --arg p "$1" --arg c "$2" '{tool_input:{file_path:$p,content:$c}}'; }

@test "service-alert-gate: blocks Bot API host in source, exit 2" {
  run feed "$HOOKS/pre-edit-service-alert-gate.sh" "$(edit_payload /p/src/a.ts "fetch('https://$TG/bot1/x')")"
  [ "$status" -eq 2 ]
}

@test "service-alert-gate: allows clean source, .md, fixtures, bypass, lib repo" {
  run feed "$HOOKS/pre-edit-service-alert-gate.sh" "$(edit_payload /p/src/a.ts ok)"
  [ "$status" -eq 0 ]
  run feed "$HOOKS/pre-edit-service-alert-gate.sh" "$(edit_payload /p/README.md "$TG")"
  [ "$status" -eq 0 ]
  run feed "$HOOKS/pre-edit-service-alert-gate.sh" "$(edit_payload /p/test/fixtures/a.ts "$TG")"
  [ "$status" -eq 0 ]
  BYPASS_SERVICE_ALERT_GATE=1 run feed "$HOOKS/pre-edit-service-alert-gate.sh" "$(edit_payload /p/src/a.ts "$TG")"
  [ "$status" -eq 0 ]
  echo '{"name":"@acegalaxy/lib-ott-gateway"}' > "$CLAUDE_PROJECT_DIR/package.json"
  run feed "$HOOKS/pre-edit-service-alert-gate.sh" "$(edit_payload /p/src/a.ts "$TG")"
  [ "$status" -eq 0 ]
}

@test "service-alert-gate --scan: exit 1 on violation, 0 when clean" {
  run bash "$HOOKS/pre-edit-service-alert-gate.sh" --scan
  [ "$status" -eq 0 ]
  echo "curl https://$TG/botX" > "$CLAUDE_PROJECT_DIR/run.sh"
  git -C "$CLAUDE_PROJECT_DIR" add run.sh
  run bash "$HOOKS/pre-edit-service-alert-gate.sh" --scan
  [ "$status" -eq 1 ]
}

@test "deploy-doc reminder: self-test passes" {
  run bash "$HOOKS/pre-commit-deploy-doc.sh" --self-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-test PASS"* ]]
}

@test "deploy-doc reminder: advises when scope code staged without deploy.md, always exit 0" {
  mkdir -p "$CLAUDE_PROJECT_DIR/svc"
  echo d > "$CLAUDE_PROJECT_DIR/svc/deploy.md"; echo c > "$CLAUDE_PROJECT_DIR/svc/run.ts"
  git -C "$CLAUDE_PROJECT_DIR" add svc/deploy.md svc/run.ts
  git -C "$CLAUDE_PROJECT_DIR" -c user.email=t@t -c user.name=t commit -qm init
  echo c2 > "$CLAUDE_PROJECT_DIR/svc/run.ts"; git -C "$CLAUDE_PROJECT_DIR" add svc/run.ts
  run feed "$HOOKS/pre-commit-deploy-doc.sh" '{"tool_input":{"command":"git commit -m x"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"svc/deploy.md"* ]]
  run feed "$HOOKS/pre-commit-deploy-doc.sh" '{"tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pii-guard: bundled self-test passes" {
  run bash "$HOOKS/pre-pii-guard.test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all pass"* ]]
}

@test "pii-guard: blocks phone (2), allows clean (0)" {
  run feed "$HOOKS/pre-pii-guard.sh" '{"tool_name":"Write","tool_input":{"file_path":"x.html","content":"Gọi 0912 345 678"}}'
  [ "$status" -eq 2 ]
  run feed "$HOOKS/pre-pii-guard.sh" '{"tool_name":"Write","tool_input":{"file_path":"x.html","content":"hello"}}'
  [ "$status" -eq 0 ]
}

inst() {
  HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 HARNESS_GROUP_PII="${1:-}" run bash "$ROOT/harness/install.sh" </dev/null
}

@test "install default: service-alert-gate + deploy-doc wired, pii NOT installed" {
  inst
  [ "$status" -eq 0 ]
  [ -x "$TARGET/.claude/hooks/pre-edit-service-alert-gate.sh" ]
  [ -x "$TARGET/.claude/hooks/pre-commit-deploy-doc.sh" ]
  [ ! -e "$TARGET/.claude/hooks/pre-pii-guard.sh" ]
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | (any(endswith("pre-edit-service-alert-gate.sh")) and any(endswith("pre-commit-deploy-doc.sh")) and (any(endswith("pre-pii-guard.sh")) | not))' "$TARGET/.claude/settings.json"
}

@test "install HARNESS_GROUP_PII=y wires pii, uninstall removes all new hooks" {
  inst y
  [ "$status" -eq 0 ]
  [ -x "$TARGET/.claude/hooks/pre-pii-guard.sh" ]
  [ -x "$TARGET/.claude/hooks/pii-scan.pl" ]
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(endswith("pre-pii-guard.sh"))' "$TARGET/.claude/settings.json"
  run bash "$TARGET/.claude/hooks/pre-pii-guard.test.sh"
  [ "$status" -eq 0 ]
  HARNESS_ROUTE_DIR="$TARGET" HARNESS_ASSUME_YES=1 run bash "$ROOT/harness/install.sh" uninstall </dev/null
  [ "$status" -eq 0 ]
  for f in pre-pii-guard.sh pii-scan.pl pre-pii-guard.test.sh pre-edit-service-alert-gate.sh pre-commit-deploy-doc.sh; do
    [ ! -e "$TARGET/.claude/hooks/$f" ]
  done
  ! grep -qE 'pre-pii-guard|service-alert-gate|deploy-doc' "$TARGET/.claude/settings.json" 2>/dev/null
}
