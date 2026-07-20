#!/usr/bin/env bash
# Claude Code SessionStart hook — announce orchestrator-gate (+ session-budget rule
# if you wired check-session-limit.sh too). Fire 1 per session start. Exit 0 advisory.

set -u

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

cat >&2 << 'EOF'

═══════════════════════════════════════════════════════════════════════════
🚦 Orchestrator Gate ACTIVE (.claude/rules/orchestrator.md)
═══════════════════════════════════════════════════════════════════════════

Opus = pure orchestrator. Trước MỖI execution: tuyên bố [nhãn] → target.
  • [S: 1-line/config/plan/read<50] → Opus tự làm
  • [M mechanical] → delegate-deepseek   • [read-only] → delegate-gemini
  • [L/XL execute] → delegate-sonnet (fb: delegate-codex)

HARD GATE: main-agent Edit/Write vào @@CORE_DIRS_HUMAN@@ bị chặn (exit 2).
  Subagent edit OK. Size-S 1-line thật → ORCHESTRATOR_GATE_BYPASS=1.
  Hook: .claude/hooks/pre-edit-orchestrator-gate.sh

═══════════════════════════════════════════════════════════════════════════
📊 Context-Window Budget Rule (nếu đã cài check-session-limit.sh — optional group)
═══════════════════════════════════════════════════════════════════════════

Mỗi turn check context-window size trước action (nếu hook được wire), qua
UserPromptSubmit → .claude/hooks/check-session-limit.sh (ước lượng token count
từ transcript-file byte size).

Rule tiers (ai-memory-rules/rules/token-budget.md, mirror ~/.claude/rules/token-budget.md):
  • < 100K tokens  → Bình thường
  • ≥ 100K tokens  → Hạn chế re-read source; ưu tiên memory/reference; delegate hoặc new session
  • ~200K tokens   → Auto-compact tự chạy — không cần làm gì

Session%/Weekly% (không đo được qua hook stdin) đã bỏ khỏi rule này.

═══════════════════════════════════════════════════════════════════════════

EOF

# C — audit surfacing: nếu gate từng chặn, cho biết đã chặn bao nhiêu lần (all-time).
GATE_LOG="${HOME}/.cache/claude-code-@@PROJECT_SLUG@@/orchestrator-gate.log"
if [ -f "$GATE_LOG" ]; then
  n_block=$(grep -c ' BLOCK ' "$GATE_LOG" 2>/dev/null); n_block=${n_block:-0}
  n_bypass=$(grep -c ' BYPASS ' "$GATE_LOG" 2>/dev/null); n_bypass=${n_bypass:-0}
  if [ "${n_block:-0}" -gt 0 ] || [ "${n_bypass:-0}" -gt 0 ]; then
    echo "🚦 orchestrator-gate history: ${n_block} block · ${n_bypass} bypass (${GATE_LOG})" >&2
  fi
fi

exit 0
