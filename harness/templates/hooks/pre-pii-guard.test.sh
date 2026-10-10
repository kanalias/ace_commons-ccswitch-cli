#!/usr/bin/env bash
# Self-check pre-pii-guard.sh: bash <hooks-dir>/pre-pii-guard.test.sh
D="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_PROJECT_DIR="$(mktemp -d)"; trap 'rm -rf "$CLAUDE_PROJECT_DIR"' EXIT
H="$D/pre-pii-guard.sh"; fail=0
t(){ printf '%s' "$3" | "$H" >/dev/null 2>&1; r=$?; [ $r = $2 ] || { echo "FAIL $1 (got $r want $2)"; fail=1; }; }
t phone   2 '{"tool_name":"Write","tool_input":{"file_path":"x.html","content":"Gọi 0912 345 678"}}'
t cccd    2 '{"tool_name":"Edit","tool_input":{"file_path":"a.md","new_string":"CCCD 001203004567"}}'
t address 2 '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"VP 12 đường Lê Lợi"}}'
t gps     2 '{"tool_name":"Bash","tool_input":{"command":"echo 16.4637, 107.5909"}}'
t mail    2 '{"tool_name":"mcp__cloak_x__cloak_type","tool_input":{"text":"abc.nguyen@gmail.com"}}'
t safe    0 '{"tool_name":"Write","tool_input":{"file_path":"x.html","content":"noreply@anthropic.com you@example.com v1.2.3 2026-10-09"}}'
t envfile 0 '{"tool_name":"Write","tool_input":{"file_path":"/p/.env","content":"P=0912345678"}}'
t bypass  0 '{"tool_name":"Bash","tool_input":{"command":"PII_GUARD_BYPASS=1 true 0912345678"}}'
[ $fail = 0 ] && echo "pii-guard: all pass"; exit $fail
