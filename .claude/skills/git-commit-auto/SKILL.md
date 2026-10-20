---
name: git-commit-auto
description: Tự commit local ngay khi 1 task/feature/fix xong (todo hoàn tất, test pass) để không dồn nhiều việc không liên quan vào 1 commit. Tự stage đúng scope, soạn message, chạy `git commit` không hỏi; chỉ báo hash + subject. Dùng khi vừa xong 1 đơn vị việc còn uncommitted, hoặc user nói "auto commit", "nhớ commit giúp", "đừng để tôi quên commit", /git-commit-auto.
user-invocable: true
---

# git-commit-auto — tự commit local sau mỗi đơn vị việc

Override có chủ đích (user đã chốt) cho "chỉ commit khi được yêu cầu": CHỈ áp cho `git commit` local trong skill này. Push / merge / amend / force vẫn theo rule thường.

## Khi trigger

- 1 task/feature/fix vừa xong (todo done, test pass) và repo còn thay đổi của đúng việc đó.
- User nói "auto commit", "nhớ commit giúp", "đừng để quên commit".

## Các bước

1. `git status` + `git diff` (staged + unstaged) + `git log --oneline -5` — xác nhận đơn vị việc hoàn chỉnh và style message của repo.
2. Thay đổi lạ không do mình (session khác đang sửa cùng repo) → KHÔNG commit chung, chỉ stage file mình sửa; nghi ngờ → dừng, báo user.
3. Loại file nhạy cảm/rác (`.env*`, `*.bak`, credential dump, editor swap) — nêu trong report.
4. Stage theo tên file đúng phạm vi, KHÔNG `git add -A`/`.`. Nhiều việc không liên quan → tách nhiều commit.
5. Message theo [[git-conventions]] (`feat|fix|refactor|chore|docs: <mô tả>`), khớp style repo.
6. `git commit` ngay, không hỏi.

## Không làm

- Không commit khi task dở / test fail → dừng, báo user.
- Không amend, không force, không `--no-verify` (hook fail → sửa root cause).
- Không push (push qua `/git-push-safety`), không merge.

## Report

1 dòng: hash + subject; file bị loại kèm lý do.
