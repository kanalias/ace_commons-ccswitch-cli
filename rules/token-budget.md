---
name: token-budget
description: Context window budget per-conversation — ngưỡng 195K cảnh báo trước khi Claude Code auto-compact (~200K) tự trigger
status: live
updated: 2026-07-16
metadata:
  type: reference
---

# Context Window Budget (P0, cross-project)

Session %/Weekly % không có API đọc thật (chỉ ước lượng mơ hồ) nên bỏ, không track. Chỉ giữ context window vì đo được trực tiếp (độ dài conversation).

| Context | Mode |
|---|---|
| < 100K | Normal |
| 100–195K | Cautious (ưu tiên đọc memory/reference vs re-read source) |
| ≥ 195K | **Warning**: chủ động `/compact` HOẶC new session HOẶC delegate remaining — trước khi Claude Code auto-compact (~200K) tự trigger và mất control point chọn giữ gì |
| > 300K | Critical: commit + report + HARD recommend /compact |

Empirical: quality degrade rõ > 200K (recall yếu, tool selection sai, repeat work). KHÔNG hard cutoff — silent degrade. Ngưỡng 195K canh sớm hơn auto-compact built-in (~200K) để chủ động chọn compact tay hoặc delegate phần còn lại thay vì bị tool tự cắt.

Size-S (4 case Opus tự làm) và routing S/M/L: xem [[orchestrator]] — không lặp lại ở đây.

> **Project-specific:** repo có thể extend file này (hook enforcement, env var check). Xem `.claude/rules/token-budget-<project>.md` nếu có.
