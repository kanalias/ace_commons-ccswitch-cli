#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write).
# Orchestrator gate: chặn MAIN agent (Opus) tự Edit/Write file source core.
# Ép execution route qua delegate subagent (per .claude/rules/orchestrator.md).
#
# Ranh giới (path-coarse, không đoán size — nghi ngờ → chặn):
#   - Chặn khi: caller = MAIN agent  VÀ  file_path thuộc core source dirs (src/)
#   - Cho phép: mọi tool call từ SUBAGENT (delegate-sonnet/deepseek/... edit thẳng OK)
#   - Cho phép: main agent sửa .claude/, docs/, tests/, config root (size-S exception)
#
# Discriminator main vs subagent: dùng agent_id — field này CHỈ có ở subagent
# call. Không dùng agent_type: field đó cũng xuất hiện khi MAIN session chạy
# kèm flag `--agent` (main vẫn là main), fallback qua nó gây false-negative gate.
#
# Escape hatch cho size-S 1-line fix thật sự trong core dirs:
#   ORCHESTRATOR_GATE_BYPASS=1  → allow + ghi audit log.
#
# Output: exit 0 = allow · exit 2 = block (stderr shown to model).
# Fail-open: thiếu jq → allow (không chặn mù).
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

LOG="${HOME}/.cache/claude-code-ccswitch-cli-claude/orchestrator-gate.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

payload=$(cat)

# Thiếu jq → fail-open (nhất quán với pre-edit-secret-scan.sh).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Payload không phải JSON hợp lệ → fail-open (không chặn mù, không error mã lạ).
if ! printf '%s' "$payload" | jq empty >/dev/null 2>&1; then
  exit 0
fi

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // empty')
# Subagent call mang agent_id. Main agent thì rỗng (kể cả main chạy --agent).
agent_id=$(echo "$payload"   | jq -r '.agent_id // empty')

ts() { date '+%Y-%m-%dT%H:%M:%S'; }

# 1) Tool call từ subagent → luôn allow (delegate được phép edit).
if [ -n "$agent_id" ]; then
  exit 0
fi

# 2) Escape hatch: size-S 1-line fix thật sự.
if [ "${ORCHESTRATOR_GATE_BYPASS:-}" = "1" ]; then
  echo "$(ts) BYPASS main-agent edit → $file_path" >> "$LOG" 2>/dev/null || true
  exit 0
fi

# 3) Chỉ gate file source core. Path khác (.claude/, docs/, tests/, config) → allow.
#    Match cả absolute path lẫn repo-relative.
case "$file_path" in
  */src/*|src/*)
    echo "$(ts) BLOCK main-agent edit → $file_path" >> "$LOG" 2>/dev/null || true
    cat >&2 << EOF
🚦 orchestrator-gate: MAIN agent (Opus) KHÔNG tự Edit/Write vào source core.
   File: $file_path

   Rule: .claude/rules/orchestrator.md — Opus = pure orchestrator.
   Execution (edit src/) PHẢI route qua delegate subagent:
     • L/XL algo / refactor / fix sau chẩn đoán → delegate-sonnet (fb: delegate-codex)
     • M mechanical / batch edit / boilerplate   → delegate-deepseek
     • read-only audit / cross-file / grep rộng  → delegate-gemini

   Nếu ĐÚNG là size-S (1-line + 0 read context), chạy lại với:
     ORCHESTRATOR_GATE_BYPASS=1
EOF
    exit 2
    ;;
esac

exit 0
