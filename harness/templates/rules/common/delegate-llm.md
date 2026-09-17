---
name: delegate-llm
description: Offload work từ Opus qua 4 delegate subagent (deepseek/gemini/codex/sonnet); KHÔNG bash aider/gemini/codex CLI trực tiếp; worktree isolation + no auto-commit
status: live
updated: 2026-08-04
paths:
  - "scripts/delegate/**"
metadata:
  type: reference
---

# Delegate LLM Subagents (cross-project)

> Bảng subagent + 5 mục Mandatory + Anti-patterns đã merge vào [[orchestrator]] section "Delegate mandatory" (always-load). File này lazy — chỉ load khi task chạm `scripts/delegate/**`; giữ chi tiết wrapper-infra bổ sung dưới.

Offload work từ main Claude (Opus) → 4 pre-built delegate subagent. **KHÔNG** call `aider`/`gemini`/`codex` CLI trực tiếp từ main agent.

| Subagent | Backend | Strength | Khi dùng |
|---|---|---|---|
| `delegate-deepseek` | Aider + DeepSeek | Cheap + edit-in-place | Large refactor, batch edit |
| `delegate-gemini` | Gemini CLI | Large context | Read-only audit, cross-file summary |
| `delegate-codex` | Codex CLI (o-series) | Deep reasoning | Hard bug/algo/security — primary route khi cần code thật (hard-reasoning-code) |
| `delegate-sonnet` | In-harness Sonnet | Reasoning + edit | L/XL thường (spec rõ) primary; fallback cho hard-reasoning-code |

Routing chi tiết (size S/M/L, fallback chain) + Mandatory + Anti-patterns: [[orchestrator]]. Budget gate: [[token-budget]]. Org push default: [[git-conventions]].

> **Project-specific:** wrapper path (`scripts/delegate/`), persona file khai báo trong repo.
