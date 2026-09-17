---
name: git-conventions
description: Commit format + cleanup branch/worktree trong .claude/worktrees sau khi merge feature vào working branch
status: live
updated: 2026-09-17
metadata:
  type: reference
---

# Git Conventions (cross-project)

## Commit format

```text
feat|fix|refactor|chore|docs: <mô tả>
```

## Branch cleanup sau merge (BẮT BUỘC)

Xong tính năng → merge vào `dev` → cleanup NGAY trong cùng session, KHÔNG để branch/worktree rác:

1. **Worktree** — `git worktree remove .claude/worktrees/<slug>`. Stale → `git worktree prune`.
2. **Local branch** — `git branch -d feat/<slug>` (safe delete). Git từ chối (unmerged) → dừng, báo user. KHÔNG `-D` force.

Chi tiết đầy đủ (whitelist prefix, confirm trước xoá, remote branch, ngoại lệ): [[git-workflow]] mục "Cleanup sau merge".

Liên quan: [[delegate-llm]] (delegate infra), [[orchestrator]] (routing).
