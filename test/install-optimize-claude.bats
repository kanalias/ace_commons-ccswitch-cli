#!/usr/bin/env bats
# install-optimize-claude.sh: reads .env next to the script, writes ~/.claude/settings.json.
# The script resolves .env from its own dir, so every test stages a copy of the script
# into a tmpdir with a FAKE .env — the real repo .env is never read.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  STAGE="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$STAGE" "$HOME/.claude"
  cp "$ROOT/install-optimize-claude.sh" "$STAGE/install-optimize-claude.sh"
  OPT="$STAGE/install-optimize-claude.sh"
  S="$HOME/.claude/settings.json"
  echo '{}' > "$S"
}

@test "denyTools alone (no disableWorkflows) is applied — keys are independent" {
  echo 'denyTools=Artifact, CronCreate,NotebookEdit' > "$STAGE/.env"
  run "$OPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"không có disableWorkflows — bỏ qua"* ]]
  [ "$(jq -c '.permissions.deny' "$S")" = '["Artifact","CronCreate","NotebookEdit"]' ]
  [ "$(jq 'has("disableWorkflows")' "$S")" = "false" ]
}

@test "denyTools is idempotent and preserves pre-existing deny entries + order" {
  echo '{"permissions":{"deny":["Bash(rm -rf *)","CronCreate"],"allow":["Read"]}}' > "$S"
  echo 'denyTools=Artifact,CronCreate,Artifact' > "$STAGE/.env"
  run "$OPT"; [ "$status" -eq 0 ]
  run "$OPT"; [ "$status" -eq 0 ]
  [ "$(jq -c '.permissions.deny' "$S")" = '["Bash(rm -rf *)","CronCreate","Artifact"]' ]
  [ "$(jq -c '.permissions.allow' "$S")" = '["Read"]' ]
}

@test "denyTools rejects non-bare-name values and leaves settings untouched" {
  echo 'denyTools=Artifact,Bash(rm -rf *)' > "$STAGE/.env"
  run "$OPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"denyTools trong .env phải là tên tool"* ]]
  [ "$(cat "$S")" = "{}" ]
}

@test "disableWorkflows=true and denyTools both applied in one run" {
  printf 'disableWorkflows=true\ndenyTools=Artifact\n' > "$STAGE/.env"
  run "$OPT"
  [ "$status" -eq 0 ]
  [ "$(jq '.disableWorkflows' "$S")" = "true" ]
  [ "$(jq -c '.permissions.deny' "$S")" = '["Artifact"]' ]
}

@test "no known keys in .env → exit 0, settings untouched" {
  echo 'proxy_host=https://x.test/v1' > "$STAGE/.env"
  run "$OPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"không có denyTools — bỏ qua"* ]]
  [ "$(cat "$S")" = "{}" ]
}
