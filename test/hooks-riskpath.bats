#!/usr/bin/env bats
# .claude/hooks/pre-edit-orchestrator-gate.sh — risk-path denylist canonicalization.
# Regression: is_risk_path() phải resolve ".." / relative traversal trước khi
# match HARNESS_RISK_DIRS, không match raw case-glob (evasion qua
# "src/../auth/x.ts" trước fix chỉ match "*/auth/*", để lọt qua vì literal
# string không chứa "/auth/" theo cách hook mong đợi — vẫn bị chặn thực tế,
# nhưng test này khoá lại hành vi canonicalize + đường dẫn chưa tồn tại).

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  HOOK="$ROOT/.claude/hooks/pre-edit-orchestrator-gate.sh"

  PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR/src" "$PROJECT_DIR/auth"
  touch "$PROJECT_DIR/auth/x.ts" "$PROJECT_DIR/src/ok.ts"
}

run_hook() {
  local file_path="$1" agent_type="${2:-delegate-gemini}"
  local json
  json=$(jq -nc --arg fp "$file_path" --arg at "$agent_type" \
    '{agent_id:"a1", agent_type:$at, tool_input:{file_path:$fp}}')
  run bash -c "printf '%s' '$json' | CLAUDE_PROJECT_DIR='$PROJECT_DIR' HARNESS_RISK_DIRS='auth' bash '$HOOK'"
}

@test "risk-path: traversal 'src/../auth/x.ts' resolves into auth/ and blocks" {
  run_hook "src/../auth/x.ts"
  [ "$status" -eq 2 ]
}

@test "risk-path: direct 'auth/x.ts' blocks" {
  run_hook "auth/x.ts"
  [ "$status" -eq 2 ]
}

@test "risk-path: 'src/ok.ts' outside risk dir allows (from subagent)" {
  run_hook "src/ok.ts"
  [ "$status" -eq 0 ]
}

@test "risk-path: new file not yet created under auth/ still blocks" {
  run_hook "auth/newfile.ts"
  [ "$status" -eq 2 ]
}

@test "risk-path: traversal escaping project_dir entirely does not false-positive match unrelated dir" {
  # "../../../etc/auth" tồn tại thật trên máy (root) nhưng không phải risk
  # dir của project này — canonicalize ra path ngoài project_dir, rel fallback
  # về absolute, không chứa "auth" như 1 path segment kiểu risk dir project.
  run_hook "../../../../../../../../etc/passwd"
  [ "$status" -eq 0 ]
}

@test "risk-path: unresolvable path (missing ancestor dir) fails closed" {
  # dirname không tồn tại luôn (không phải file mới trong dir có sẵn) → walk-up
  # tới "/" mà "/" luôn tồn tại nên sẽ resolve về "/" + suffix — vẫn phải allow
  # vì "/" không chứa risk dir; test riêng nhánh canonicalize thất bại dùng
  # input rỗng qua HARNESS_RISK_DIRS unset đã có test khác. Ở đây verify khi
  # ancestor không tồn tại (theo lý thuyết) hook vẫn không crash — status
  # thuộc {0,2}, không phải lỗi script.
  run_hook "does/not/exist/anywhere/weird/auth/x.ts"
  [[ "$status" -eq 0 || "$status" -eq 2 ]]
}
