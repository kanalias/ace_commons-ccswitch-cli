---
name: auto-commit
description: Tự động commit local ngay sau khi 1 task/feature/fix làm xong (todo hoàn tất, test pass), tránh quên commit rồi dồn nhiều thay đổi không liên quan vào 1 commit. Tự stage đúng scope + tự soạn message + tự chạy `git commit`, không dừng hỏi xác nhận — chỉ báo lại hash+subject sau khi commit xong. Dùng khi vừa xong 1 vòng sửa code còn uncommitted changes, hoặc user nói "auto commit", "nhớ commit giúp", "đừng để tôi quên commit".
user-invocable: true
---

# auto-commit — tự commit local sau khi xong task/feature

Task/feature làm xong dễ bị quên commit → dồn nhiều thay đổi không liên quan vào 1 commit, khó revert/review riêng lẻ. Skill này chủ động rà soát + commit ngay sau khi 1 đơn vị việc hoàn tất, không cần user gõ `/commit`, không dừng hỏi xác nhận từng lần.

Đây là override có chủ đích cho riêng skill này (user đã xác nhận) đối với rule mặc định "chỉ commit khi được yêu cầu rõ" — chỉ áp dụng khi skill này được trigger, không áp dụng cho các thao tác git khác (push, merge, force vẫn theo rule global bình thường).

## Khi trigger

- Ngay sau khi 1 task/feature/fix được đánh dấu xong (todo hoàn tất, test pass) mà repo còn uncommitted changes liên quan đúng việc đó.
- User nói "auto commit", "nhớ commit giúp", "đừng để quên commit".

## Các bước

1. `git status` + `git diff` (staged + unstaged) — xác nhận đây là 1 đơn vị việc hoàn chỉnh, không commit dở dang (test pass, todo done).
2. Quét nhanh trước khi stage: file lạ/nhạy cảm (`.env`, `*.bak`, credential dump, editor swap file) → loại khỏi commit này, nêu rõ trong report.
3. Stage theo tên file cụ thể đúng phạm vi vừa xong — không `git add -A`/`.` mù.
4. Soạn commit message khớp style repo (`git log --oneline -5`) — `type(scope): subject`, imperative, không thừa.
5. Chạy `git commit` ngay, không dừng hỏi xác nhận.
6. Không push — commit local only, push thuộc `/push-to-git`.

## Không làm

- Không stage/commit mù toàn bộ working tree.
- Không commit khi task chưa xong hoặc test đang fail — trường hợp này dừng lại, báo user thay vì tự commit.
- Không amend, không force, không bypass hook (`--no-verify`).
- Không tự push, không tự merge — auto chỉ tới `git commit` local.

## Report

Sau khi commit xong, báo 1 dòng: commit hash + subject. File nào bị loại khỏi commit (nghi secret/junk) nêu rõ lý do.
