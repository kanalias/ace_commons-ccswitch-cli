#!/usr/bin/env bats
# harness/templates/hooks/pre-browser-profile-gate.sh — Bash branch must only gate
# commands that LAUNCH the browser MCP, not read-only/text commands that merely
# mention the word. MCP-tool branch unchanged.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  HOOK="$ROOT/harness/templates/hooks/pre-browser-profile-gate.sh"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$CLAUDE_PROJECT_DIR"
}

run_bash_cmd() { # run_bash_cmd <command text>
  local json
  json=$(jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$HOOK"
}

run_tool() { # run_tool <tool_name> [user_data_dir]
  local json
  json=$(jq -nc --arg t "$1" --arg u "${2:-}" '{tool_name:$t,tool_input:{user_data_dir:$u}}')
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$HOOK"
}

# ── false positives: must pass (exit 0) ─────────────────────────────────

@test "browser-gate: grep for the word playwright passes" {
  run_bash_cmd 'grep -rn playwright .'
  [ "$status" -eq 0 ]
}

@test "browser-gate: git log --grep passes" {
  run_bash_cmd 'git log --grep=playwright --oneline'
  [ "$status" -eq 0 ]
}

@test "browser-gate: git commit message mentioning playwright mcp passes" {
  run_bash_cmd 'git commit -m "fix: playwright mcp profile gate false positive"'
  [ "$status" -eq 0 ]
}

@test "browser-gate: cat of playwright-notes doc about mcp passes" {
  run_bash_cmd 'cat docs/playwright-mcp-notes.md'
  [ "$status" -eq 0 ]
}

@test "browser-gate: jq over path containing playwright and mcp passes" {
  run_bash_cmd 'jq . .claude/playwright/mcp.json'
  [ "$status" -eq 0 ]
}

@test "browser-gate: npm ls / npm install of the package passes (not a launch)" {
  run_bash_cmd 'npm ls playwright'
  [ "$status" -eq 0 ]
  run_bash_cmd 'npm install --save-dev @playwright/mcp'
  [ "$status" -eq 0 ]
}

@test "browser-gate: grep for @playwright/mcp piped to head passes" {
  run_bash_cmd 'grep -rn "@playwright/mcp" . | head -5'
  [ "$status" -eq 0 ]
}

# ── true positives: must still block (exit 2) ───────────────────────────

@test "browser-gate: npx launch without profile blocks" {
  run_bash_cmd 'npx -y @playwright/mcp --headless'
  [ "$status" -eq 2 ]
}

@test "browser-gate: npx launch with profile outside container blocks" {
  run_bash_cmd 'npx -y @playwright/mcp --user-data-dir=/tmp/prj_myapp_sv_auth'
  [ "$status" -eq 2 ]
}

@test "browser-gate: launch behind env prefix / chain still blocks" {
  run_bash_cmd 'cd /tmp && FOO=1 npx @playwright/mcp --headless'
  [ "$status" -eq 2 ]
}

@test "browser-gate: pnpm dlx / direct binary launch without profile blocks" {
  run_bash_cmd 'pnpm dlx @playwright/mcp@latest'
  [ "$status" -eq 2 ]
  run_bash_cmd 'playwright-mcp --headless'
  [ "$status" -eq 2 ]
}

@test "browser-gate: shell -c wrapper around launch blocks (ambiguous, kept strict)" {
  run_bash_cmd 'bash -c "npx @playwright/mcp"'
  [ "$status" -eq 2 ]
}

@test "browser-gate: valid launch with container profile passes" {
  run_bash_cmd "npx -y @playwright/mcp --user-data-dir=$BATS_TEST_TMPDIR/repo/.browser-profiles/prj_myapp_sv_auth"
  [ "$status" -eq 0 ]
}

# ── MCP-tool branch unchanged ───────────────────────────────────────────

@test "browser-gate: MCP generic playwright server blocks, scoped pw server passes" {
  run_tool mcp__playwright__browser_navigate
  [ "$status" -eq 2 ]
  run_tool mcp__pw_myapp_auth__browser_navigate
  [ "$status" -eq 0 ]
}

@test "browser-gate: cloak_launch without matching user_data_dir blocks" {
  run_tool mcp__cloak_shop_checkout__cloak_launch ""
  [ "$status" -eq 2 ]
}

@test "browser-gate: --self-test passes" {
  run bash "$HOOK" --self-test
  [ "$status" -eq 0 ]
}

@test "browser-gate: docker run of the playwright mcp image without profile still blocks" {
  run_bash_cmd "docker run -i --rm mcr.microsoft.com/playwright/mcp"
  [ "$status" -eq 2 ]
}
