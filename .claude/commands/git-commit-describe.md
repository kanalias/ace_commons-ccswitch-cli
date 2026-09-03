---
name: git-commit-describe
description: Soạn PR title và body từ commit và diff so với base branch, rồi tuỳ chọn tạo/update bằng gh. Dùng khi user nói "write PR description", "generate pull request body", hoặc chạy /git-commit-describe.
user-invocable: true
---

# git-commit-describe — soạn PR title + body từ commit/diff

## 1. Xác định base branch

Thử `git symbolic-ref refs/remotes/origin/HEAD` và lấy basename. Nếu
chưa set, hỏi user PR này target branch nào — không giả định
`main` vs `master` vs release branch.

## 2. Thu thập change set

Chạy:

- `git log <base>..HEAD --oneline` — các commit mà PR này giới thiệu
- `git diff <base>...HEAD --stat` — file bị chạm và mức độ

Nếu không có commit nào ahead của base, DỪNG và báo user chưa có gì
để mô tả.

## 3. Soạn title + body

**Title** — imperative mood, suy ra từ commit hoặc tên branch (bỏ
prefix như `feat/`), ≤70 ký tự.

**Body**, theo cấu trúc này:

- **Summary** — 1-3 câu: cái gì đã đổi và tại sao, ngôn ngữ đơn giản.
- **Changes** — bullet nhóm theo vùng/module bị chạm (dùng output diff
  --stat để xác định vùng, không dump commit-by-commit thô).
- **Test plan** — chỉ phản ánh test thực sự tồn tại trong diff hoặc repo
  (file test mới/đã update, hoặc lệnh user có thể chạy). ĐỪNG claim test
  đã chạy hoặc pass trừ khi bạn thực sự đã chạy chúng trong session này —
  nếu không có test cho thay đổi này, nói rõ vậy thay vì bịa ra 1 plan.
- **Notes/risks** — bất cứ gì reviewer nên biết: breaking change,
  follow-up work, thứ cố tình để ngoài scope.

## 4. Tạo hoặc update PR

Check xem `gh` đã cài và authenticated chưa (`gh auth status`).

- **Có `gh`:** hỏi user muốn tạo PR mới
  (`gh pr create --title ... --body ...`) hay update PR có sẵn
  (`gh pr edit <number> --body ...`) — tạo hoặc sửa PR là
  outward-facing, nên xin xác nhận rõ ràng trước khi chạy lệnh nào.
  Không bao giờ push commit hoặc force-push như một phần của command này.
- **Không có `gh`:** in title + body đã soạn dạng markdown để
  user tự copy vào PR thủ công. Không thử tool khác để mở
  PR thay họ.
