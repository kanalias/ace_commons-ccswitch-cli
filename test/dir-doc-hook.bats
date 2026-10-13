#!/usr/bin/env bats
# harness/templates/hooks/pre-read-inject-dir-doc.sh + post-edit-advisor.sh (dir-doc reminder).

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  INJECT="$ROOT/harness/templates/hooks/pre-read-inject-dir-doc.sh"
  ADVISOR="$ROOT/harness/templates/hooks/post-edit-advisor.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/src/mods/alpha" "$PROJ/src/mods/beta"
  printf '# Alpha\nINVARIANT-ALPHA-XYZ\n' >"$PROJ/src/mods/alpha/MODULE.md"
  echo 'x' >"$PROJ/src/mods/alpha/a.ts"
  echo 'x' >"$PROJ/src/mods/beta/b.ts"
  export HARNESS_DIR_DOC_ROOTS="src/mods"
  unset HARNESS_DIR_DOC_NAME HARNESS_DELEGATE
}

payload() { # file_path [session_id]
  jq -n --arg f "$1" --arg c "$PROJ" --arg s "${2:-}" \
    '{tool_input:{file_path:$f}, cwd:$c} + (if $s=="" then {} else {session_id:$s} end)'
}

run_inject() { run bash -c "printf '%s' '$1' | bash '$INJECT' 2>&1"; }

@test "inject: ROOTS unset → silent exit 0" {
  unset HARNESS_DIR_DOC_ROOTS
  run_inject "$(payload "$PROJ/src/mods/alpha/a.ts" s1)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "inject: file under root with doc → valid JSON with doc text" {
  run_inject "$(payload "$PROJ/src/mods/alpha/a.ts" s1)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("INVARIANT-ALPHA-XYZ")' >/dev/null
}

@test "inject: relative file_path resolves against payload cwd" {
  run_inject "$(payload "src/mods/alpha/a.ts" s1)"
  [ "$status" -eq 0 ]
  [[ "$output" == *INVARIANT-ALPHA-XYZ* ]]
}

@test "inject: second call same session → silent; different session → injects" {
  p1="$(payload "$PROJ/src/mods/alpha/a.ts" s1)"
  run_inject "$p1"; [[ "$output" == *INVARIANT-ALPHA-XYZ* ]]
  run_inject "$p1"; [ "$status" -eq 0 ]; [ -z "$output" ]
  run_inject "$(payload "$PROJ/src/mods/alpha/a.ts" s2)"
  [[ "$output" == *INVARIANT-ALPHA-XYZ* ]]
}

@test "inject: missing session_id → injects every time (no marker)" {
  p="$(payload "$PROJ/src/mods/alpha/a.ts")"
  run_inject "$p"; [[ "$output" == *INVARIANT-ALPHA-XYZ* ]]
  run_inject "$p"; [[ "$output" == *INVARIANT-ALPHA-XYZ* ]]
}

@test "inject: doc missing → silent" {
  run_inject "$(payload "$PROJ/src/mods/beta/b.ts" s1)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "inject: editing the doc itself → silent" {
  run_inject "$(payload "$PROJ/src/mods/alpha/MODULE.md" s1)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "inject: file outside any root → silent" {
  echo x >"$PROJ/other.ts"
  run_inject "$(payload "$PROJ/other.ts" s1)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "inject: custom HARNESS_DIR_DOC_NAME honoured" {
  printf 'CUSTOM-DOC-TEXT\n' >"$PROJ/src/mods/alpha/NOTES.md"
  export HARNESS_DIR_DOC_NAME=NOTES.md
  run_inject "$(payload "$PROJ/src/mods/alpha/a.ts" s1)"
  [[ "$output" == *CUSTOM-DOC-TEXT* ]]
}

@test "inject: path inside .claude/worktrees/<slug> (cwd = main repo)" {
  wt="$PROJ/.claude/worktrees/w1"
  mkdir -p "$wt/src/mods/alpha"
  printf 'WORKTREE-DOC\n' >"$wt/src/mods/alpha/MODULE.md"
  echo x >"$wt/src/mods/alpha/a.ts"
  run_inject "$(payload "$wt/src/mods/alpha/a.ts" s1)"
  [[ "$output" == *WORKTREE-DOC* ]]
}

@test "inject: doc longer than 200 lines is truncated and says so" {
  seq 1 300 >"$PROJ/src/mods/alpha/MODULE.md"
  run_inject "$(payload "$PROJ/src/mods/alpha/a.ts" s1)"
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *truncated* ]]
  [[ "$ctx" == *$'\n200'* ]]
  [[ "$ctx" != *$'\n201'* ]]
}

@test "inject: non-JSON payload → exit 0, no output" {
  run bash -c "printf 'not json {' | bash '$INJECT' 2>&1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "advisor: doc older than edited file → reminder" {
  touch -t 202001010000 "$PROJ/src/mods/alpha/MODULE.md"
  run bash -c "printf '%s' '$(payload "$PROJ/src/mods/alpha/a.ts")' | bash '$ADVISOR' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/mods/alpha/MODULE.md"* ]]
  [[ "$output" == *Reminder* ]]
}

@test "advisor: doc newer than edited file → quiet" {
  touch -t 202001010000 "$PROJ/src/mods/alpha/a.ts"
  run bash -c "printf '%s' '$(payload "$PROJ/src/mods/alpha/a.ts")' | bash '$ADVISOR' 2>&1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "advisor: ROOTS unset → quiet even when doc is older" {
  unset HARNESS_DIR_DOC_ROOTS
  touch -t 202001010000 "$PROJ/src/mods/alpha/MODULE.md"
  run bash -c "printf '%s' '$(payload "$PROJ/src/mods/alpha/a.ts")' | bash '$ADVISOR' 2>&1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
