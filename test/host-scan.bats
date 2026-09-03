#!/usr/bin/env bats
# .claude/hooks/pre-edit-content-scan.sh (section 2 — host/IP scan, sau khi
# merge pre-edit-secret-scan.sh + pre-edit-host-scan.sh): PreToolUse hook
# chặn edit đưa host/IP nghi production vào file, trừ khi đã trong allowlist.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.claude/hooks/pre-edit-content-scan.sh"

  # Project dir riêng cho test, không phụ thuộc allowlist thật của repo.
  PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR/.claude"
  cat >"$PROJECT_DIR/.claude/allowed-hosts.txt" <<'EOF'
# comment
github.com
api.moonshot.ai
EOF
}

run_hook() {
  local json="$1"
  run bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$SCRIPT'"
}

@test "host-scan: prod host in URL not allowlisted blocks" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"https://api.secret-prod.io/v1"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"api.secret-prod.io"* ]]
}

@test "host-scan: allowlisted host allows" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"https://github.com/x"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: example.com safe domain allows" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"https://api.example.com"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: .test suffix allows" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"https://foo.test/x"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: private IP 192.168.x bare allows" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"192.168.1.50"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: public IP bare blocks" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"8.8.8.8"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"8.8.8.8"* ]]
}

@test "host-scan: .env file path skipped" {
  run_hook '{"tool_input":{"file_path":"/x/.env","content":"https://api.secret-prod.io"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: jq missing fails open" {
  stub_dir="$BATS_TEST_TMPDIR/stubpath"
  mkdir -p "$stub_dir"
  for tool in bash cat grep sed sort; do
    p=$(command -v "$tool")
    [ -n "$p" ] && ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  json='{"tool_input":{"file_path":"x.md","content":"https://api.secret-prod.io"}}'
  run env PATH="$stub_dir" bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "host-scan: editing allowed-hosts.txt itself skipped" {
  run_hook '{"tool_input":{"file_path":"/x/.claude/allowed-hosts.txt","content":"api.secret-prod.io"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: localhost URL allows" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"http://localhost:3000"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: 172.16-31 private range allows" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"172.20.5.5"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: 172.15 outside private range blocks" {
  run_hook '{"tool_input":{"file_path":"x.md","content":"172.15.5.5"}}'
  [ "$status" -eq 2 ]
}

@test "host-scan: missing allowlist file fails open (no allowlist match, still scans safe patterns)" {
  empty_project="$BATS_TEST_TMPDIR/empty-project"
  mkdir -p "$empty_project/.claude"
  json='{"tool_input":{"file_path":"x.md","content":"https://api.example.com"}}'
  run bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$empty_project' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "host-scan: no content field allows (empty)" {
  run_hook '{"tool_input":{"file_path":"x.md"}}'
  [ "$status" -eq 0 ]
}

@test "host-scan: NotebookEdit new_source field scanned and blocks" {
  host="api.secret-prod""."io
  run_hook "{\"tool_input\":{\"notebook_path\":\"x.ipynb\",\"new_source\":\"https://${host}/v1\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$host"* ]]
}

@test "host-scan: path fallback resolves to repo root when CLAUDE_PROJECT_DIR unset" {
  json='{"tool_input":{"file_path":"x.md","content":"http://localhost:3000"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}
