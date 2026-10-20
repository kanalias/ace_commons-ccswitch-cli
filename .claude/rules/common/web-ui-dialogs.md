---
name: web-ui-dialogs
description: Web UI KHÔNG dùng confirm()/alert()/prompt() của browser — dùng <dialog> + CSS riêng. LAZY, load khi chạm HTML/JS/CSS frontend.
status: live
paths:
  - "**/*.html"
  - "**/public/**"
  - "**/*.css"
  - "**/*.jsx"
  - "**/*.tsx"
  - "**/*.vue"
metadata:
  type: reference
---

# Web UI — không dùng dialog native của browser

- CẤM `window.confirm()` / `alert()` / `prompt()` trong UI: chặn luồng, không style được, browser automation/E2E dễ treo, mobile hiển thị lệch.
- Dùng `<dialog>` (native HTML, `showModal()`) + CSS của site: nút chính/phụ rõ, `Esc` đóng, focus trả về nút mở, có `aria-labelledby`.
- Thông báo không cần trả lời → toast/inline message, không modal.
- Hành động phá huỷ (xoá, ban) → dialog xác nhận nêu rõ đối tượng; form POST vẫn kiểm quyền server-side (dialog chỉ là UX).
