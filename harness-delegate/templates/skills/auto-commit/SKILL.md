---
name: auto-commit
description: Chủ động kiểm tra + chuẩn bị commit local ngay sau khi 1 task/feature/fix làm xong, tránh quên commit rồi dồn nhiều thay đổi không liên quan vào 1 commit. KHÔNG tự ý commit khi chưa hỏi — vẫn xác nhận message + file trước khi chạy `git commit`. Dùng khi vừa xong 1 vòng sửa code còn uncommitted changes, hoặc user nói "auto commit", "nhớ commit giúp", "đừng để tôi quên commit".
user-invocable: true
---

# auto-commit — nhắc + chuẩn bị commit local sau khi xong task/feature

Task/feature làm xong dễ bị quên commit → dồn nhiều thay đổi không liên quan vào 1 commit, khó revert/review riêng lẻ. Skill này chủ động rà soát ngay sau khi 1 đơn vị việc hoàn tất, không cần user gõ `/commit`.

KHÔNG override rule global "không commit khi chưa được yêu cầu" — skill chỉ chủ động phát hiện + soạn sẵn, vẫn dừng lại hỏi xác nhận trước khi tạo commit thật.

## Khi trigger

- Ngay sau khi 1 task/feature/fix được đánh dấu xong (todo hoàn tất, test pass) mà repo còn uncommitted changes liên quan đúng việc đó.
- User nói "auto commit", "nhớ commit giúp", "đừng để quên commit".

## Các bước

1. `git status` + `git diff` (staged + unstaged) — xác nhận đây là 1 đơn vị việc hoàn chỉnh, không commit dở dang.
2. Quét nhanh trước khi stage: file lạ/nhạy cảm (`.env`, `*.bak`, credential dump, editor swap file) → loại khỏi commit này, báo riêng cho user.
3. Stage theo tên file cụ thể đúng phạm vi vừa xong — không `git add -A`/`.` mù.
4. Soạn commit message khớp style repo (`git log --oneline -5`) — `type(scope): subject`, imperative, không thừa.
5. Đưa message + danh sách file cho user xác nhận. Chỉ `git commit` sau khi user đồng ý.
6. Không push — commit local only, push thuộc `/push-to-git`.

## Không làm

- Không stage/commit mù toàn bộ working tree.
- Không commit khi task chưa xong hoặc test đang fail.
- Không tự quyết message mà user chưa duyệt.
- Không amend, không force, không bypass hook (`--no-verify`).

## Report

1 dòng: commit hash + subject. File nào bị loại khỏi commit (nghi secret/junk) nêu rõ lý do.
