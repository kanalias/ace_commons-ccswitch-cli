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

Xong tính năng → merge vào `main` → cleanup worktree + branch NGAY trong cùng session, KHÔNG để rác qua session. Quy trình đầy đủ (3 bước, whitelist prefix, confirm trước xoá, ngoại lệ): [[git-workflow]] mục "Cleanup sau merge".

Liên quan: [[delegate-llm]] (delegate infra), [[orchestrator]] (routing).
