---
name: project-routing-chain-2026-08
description: "Routing chain updates 2026-08-04 — read-only sonnet-first, web-research row, git-ops executor tiers"
metadata: 
  node_type: memory
  type: project
  originSessionId: d3143933-c770-4bd3-8743-d334f7ebf9f4
---

Quyết định routing 2026-08-04 (user chốt sau verify context windows):

- **Context verified 2026-08**: sonnet-5 = 1M; gemini-3.1-pro-preview = 1M trên giấy nhưng degrade >~200K + chậm (free tier); deepseek-v4-pro = 1M (wrapper đã trỏ, không cần chunk); Codex CLI harness cap ~258-400K.
- **read-only chain**: `delegate-sonnet → gemini → deepseek → STOP` (sonnet-first vì Gemini chậm + degrade; commit c23de2e).
- **web-research row mới**: subagent in-harness `fable → opus → sonnet → gemini`, ≤2 query main tự làm; wrapper ngoài không có WebSearch harness (commit 23453bc).
- **git-ops executor tiers**: git mechanical → Haiku (Sonnet trần); deploy flow → Sonnet; CẢ HAI in-harness only — wrapper ngoài chỉ sản xuất diff, không đụng git state.
- Sửa rule LUÔN cả 2 nơi: `harness/templates/rules/common/` (upstream) + `.claude/rules/common/` (synced) — install.sh overwrite bản synced.

**Why:** goal nhanh+chất lượng ([[feedback-orchestration-goal-speed-quality]]); Gemini thực tế chậm/degrade nên mất vị trí đầu chain read-only.

**How to apply:** route theo chain trên; khi nghi model/context info stale → verify web trước khi sửa routing.
