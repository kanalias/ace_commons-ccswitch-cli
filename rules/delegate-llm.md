---
name: delegate-llm
description: Offload work từ Opus qua 3 delegate subagent (deepseek/gemini/codex); KHÔNG bash aider/gemini/codex CLI trực tiếp; worktree isolation + no auto-commit
status: live
updated: 2026-07-16
metadata:
  type: reference
---

# Delegate LLM Subagents (cross-project)

Offload work từ main Claude (Opus) → 3 pre-built delegate subagent. **KHÔNG** call `aider`/`gemini`/`codex` CLI trực tiếp từ main agent.

| Subagent | Backend | Strength | Khi dùng |
|---|---|---|---|
| `delegate-deepseek` | Aider + DeepSeek | Cheap + edit-in-place | Large refactor, batch edit |
| `delegate-gemini` | Gemini CLI | Large context | Read-only audit, cross-file summary |
| `delegate-codex` | Codex CLI (o-series) | Deep reasoning | Hard bug, algo, security review |
| `delegate-sonnet` | In-harness Sonnet | Reasoning + edit | L/XL primary (không đụng Opus budget) |

Routing chi tiết (size S/M/L, fallback chain): [[orchestrator]].

## Mandatory

1. KHÔNG bypass subagent — không Bash `aider/gemini/codex` từ main agent.
2. **Isolated worktree** — wrapper tạo `.worktrees/<agent-id>/<feat>/`.
3. **No auto-commit** — wrapper truyền `--no-auto-commits`. Main agent quyết định merge/discard.
4. **Secrets** — wrapper load `.env` chain; KHÔNG pass keys vào prompt; KHÔNG echo values.
5. **Scope check** — sau delegation, main agent BẮT BUỘC `git diff` worktree trước merge; reject nếu edits ngoài scope.

## Anti-patterns

- ❌ Main agent gõ `aider --model ...` trong Bash (bypass persona + mất worktree isolation).
- ❌ Delegate edit trên main worktree (phải `.worktrees/`).
- ❌ Pass `$*_API_KEY` vào task prompt.
- ❌ Auto-merge worktree về branch chính không diff review.

Routing S/M/L đầy đủ: [[orchestrator]]. Budget gate: [[token-budget]].

## GitHub org default

Mọi repo publish/push GitHub PHẢI dưới org **`acegalaxy-co`**, không username cá nhân. Remote `git@github.com:acegalaxy-co/<repo>.git`. KHÔNG tạo dưới `lanhnk/` hoặc username khác.

> **Project-specific:** wrapper path (`scripts/delegate/`), persona file khai báo trong repo.
