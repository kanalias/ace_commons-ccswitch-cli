---
name: token-budget
description: Context window budget — auto-compact bật ở autoCompactWindow (harness set 300K cho model 1M), task L dở → handoff session mới thay vì compact
status: live
updated: 2026-09-26
metadata:
  type: reference
---

# Context Window Budget (P0, cross-project)

Chỉ track context window (đo được trực tiếp qua độ dài conversation). Session %/Weekly % không đo được → bỏ.

**Auto-compact:** trigger tại `autoCompactWindow` (project `.claude/settings.json`; harness đặt **300K** — model 1M mặc định ~967K, không bao giờ chạm). Chỉ chạy giữa các turn. Sau compact context về ~30K nên không lặp liên tục. Hook `pre-compact-guard.sh` (PreCompact `auto`) **chặn** auto-compact khi task-graph session đang dở (`status ≠ done`) — compact lossy giữa task L mất invariant. Manual `/compact <giữ gì>` luôn qua.

| Context | Hành động |
| --- | --- |
| < 100K | Bình thường |
| ≥ 100K | Hạn chế re-read source; ưu tiên memory/reference; output lớn → subagent (Explore/delegate-gemini), không nạp vào main |
| ≥ 250K + task L dở | Commit phần xong → update task-graph + plan → **session mới** `/orchestrate --resume`. KHÔNG đợi compact |
| 300K | Auto-compact (nếu không có graph dở); có graph dở → hook chặn, làm dòng trên |

Quality degrade rõ khi context gần đầy (recall yếu, chọn sai tool, lặp việc) — degrade âm thầm, không hard cutoff. Vì vậy vẫn giữ discipline ở ≥ 100K thay vì dựa hoàn toàn vào auto-compact.

Routing S/M/L: xem [[orchestrator]].

> **Project-specific:** extend qua `.claude/rules/token-budget-<project>.md` nếu có.
