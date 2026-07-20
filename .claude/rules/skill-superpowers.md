---
name: skill-superpowers
description: Dev-methodology chắt từ obra/superpowers — 4-phase debugging, TDD red-green, plan bite-size, brainstorm spec. LAZY, chỉ load khi chạm code source. KHÔNG cài plugin gốc (SessionStart inject + mandatory override đè [[orchestrator]] + rule-loading-policy).
status: live
updated: 2026-07-19
paths:
  - "src/**"
metadata:
  type: reference
---

# Skill: Superpowers (cherry-picked)

Chắt từ [obra/superpowers](https://github.com/obra/superpowers) — KHÔNG cài plugin. Plugin gốc SessionStart-inject mỗi session + skills "mandatory" → đè [[orchestrator]] (Opus pure-orchestrator) và rule-loading-policy (lazy-load). Chỉ lấy 4 methodology dưới làm checklist khi Opus/delegate execute.

Overlap đã có → dùng bản repo, KHÔNG dựng song song: worktree/cleanup → [[git-workflow]], push → `/push-to-git`. Delegate/subagent → [[orchestrator]] (KHÔNG dùng subagent-driven-dev generic của superpowers).

## 1. Systematic debugging (4-phase)

Không "cứ thử fix" (red-flag [[feature-redflags]]). Thứ tự:

1. **Reproduce** — dựng repro tối thiểu, xác định input→output sai chính xác.
2. **Isolate** — nhị phân thu hẹp vùng lỗi (bisect commit / comment block / log biên).
3. **Root cause** — giải thích *vì sao* sai, không phải *chỗ nào* sai. Chưa giải thích được = chưa tìm ra.
4. **Fix + verify** — sửa đúng root cause, chạy repro lại PASS + ≥1 edge.

Chẩn đoán ≠ implement (routing [[orchestrator]]): Opus chẩn đoán → giao delegate code fix, root-cause làm spec.

## 2. TDD red-green-refactor

Task đổi behavior code (red-flag [[feature-redflags]]): test trước.

- **RED** — viết test fail trước, xác nhận nó fail đúng lý do.
- **GREEN** — code tối thiểu cho pass, không thêm.
- **REFACTOR** — dọn khi xanh, test vẫn xanh.
- Anti-pattern: test viết sau code (bám impl, không bám spec); assert trên mock thay hành vi thật; skip test "lát thêm".
- Tối thiểu: ≥1 happy + ≥1 edge/error, cùng commit.

## 3. Writing plans (bite-size)

Task M+: plan lock interface trước code. Mỗi bước:
- 1 task = 2–5 phút, file path chính xác, verify command kèm.
- Không plan mơ hồ "improve X" — phải actionable + kiểm chứng được.
- Plan approve xong mới code (red-flag "code trước plan = rework").

## 4. Brainstorm spec (trước plan, khi mơ hồ)

Yêu cầu chưa rõ → Socratic hỏi thu hẹp trước khi plan:
- Hỏi từng chunk nhỏ, không đổ 1 loạt.
- Chốt scope + acceptance TRƯỚC khi thiết kế.
- Đừng đoán ý user (red-flag "user chắc OK") — mơ hồ thì hỏi.

## 5. Verify before done

Trước khi báo xong: chạy the project's test command (none configured — infer from README/CI, or ask before assuming), quan sát hành vi thật (không chỉ "code trông đúng"). Mất verify step = chưa xong.
