---
name: token-budget
description: Context window budget — auto-compact luôn bật, tự trigger khi context gần đầy (~200K), không cần compact tay
status: live
updated: 2026-07-18
metadata:
  type: reference
---

# Context Window Budget (P0, cross-project)

Chỉ track context window (đo được trực tiếp qua độ dài conversation). Session %/Weekly % không đo được → bỏ.

**Auto-compact:** luôn bật mặc định, tự trigger khi context gần đầy (~200K) — KHÔNG phải trước mỗi task, và chỉ chạy giữa các turn (không cắt ngang task). Hệ thống tự quyết giữ gì. Không cần can thiệp thủ công.

| Context | Hành động |
| --- | --- |
| < 100K | Bình thường |
| ≥ 100K | Hạn chế re-read source; ưu tiên memory/reference; phần việc lớn còn lại → delegate hoặc new session |
| ~200K | Auto-compact tự chạy — không cần làm gì |

Quality degrade rõ khi context gần đầy (recall yếu, chọn sai tool, lặp việc) — degrade âm thầm, không hard cutoff. Vì vậy vẫn giữ discipline ở ≥ 100K thay vì dựa hoàn toàn vào auto-compact.

Routing S/M/L: xem [[orchestrator]].

> **Project-specific:** extend qua `.claude/rules/token-budget-<project>.md` nếu có.
