---
name: meta-2tier
description: Rule 2-tier — global (~/.claude/rules/ symlink Drive) áp mọi project; project (.claude/rules/) áp riêng; rule inheritance ≠ code import cross-scope
status: live
updated: 2026-07-16
metadata:
  type: reference
---

# Rule 2-tier — Global vs Project (cross-project)

## Hai tầng rule

| Tầng | Location | Auto-load | Nội dung |
|---|---|---|---|
| **Global** | `~/.claude/rules/*.md` (symlink → Drive `kane-ai-memory/claude-rules/`) | MỌI project | Nguyên tắc cross-project: budget, orchestrator, delegate, vault, aws-tz, red-flags |
| **Project** | `<repo>/.claude/rules/*.md` | Chỉ project đó | Rule riêng: scope, code convention, gateway path, scheduler, module-md |

Claude Code load global TRƯỚC, project SAU (project priority cao hơn). Project rule có thể **extend** global (file `<rule>-<project>.md` bổ sung chi tiết repo-specific).

## Rule inheritance ≠ code import (QUAN TRỌNG)

Cross-project **rule inheritance** (global rule áp mọi project) là HỢP LỆ — đây là guidance/convention, không phải code.

Cross-scope **code import** (require/đọc/sửa file source project khác) vẫn **CẤM** — xem [[project-scope]] mỗi repo. Hai thứ khác nhau:
- ✅ Global rule "dùng UTC internal" áp cho Nexus + 9router — inheritance OK.
- ❌ Nexus `require('../../other-project/src/x')` — code import cross-scope, CẤM.

## Add rule mới

1. **Cross-project?** → thêm vào Drive `claude-rules/` (convention MemoryOS frontmatter). Auto-load mọi project qua symlink.
2. **Project-only?** → thêm vào `<repo>/.claude/rules/`. Có `paths:` frontmatter nếu chỉ liên quan vùng code cụ thể (lazy-load, tiết kiệm context).
3. Update index (`00-index.md` project, hoặc catalog Drive).

## Đặt tên

- Slug kebab-case, không prefix số.
- File extend: `<global-name>-<project>.md` (vd `token-budget-nexus.md`).

## Tránh

- ❌ Nhét rule vào `CLAUDE.md` body (CLAUDE.md là entry point).
- ❌ Duplicate rule global + project cùng nội dung — pick 1 tầng authoritative, tầng kia ref qua `[[...]]`.
- ❌ Đặt `paths:` cho global rule (global luôn load-always mọi project).

## Source-of-truth

Drive `kane-ai-memory/claude-rules/` = source rule global. `~/.claude/rules/` symlink tới đó. Edit Drive → mọi máy có symlink thấy ngay (khi Drive sync). HANDBOOK.md (Tầng 0) chắt nguyên tắc; `claude-rules/` là bản Claude-Code-auto-load.
