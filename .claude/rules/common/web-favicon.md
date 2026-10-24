---
name: web-favicon
description: Làm website/web UI mà chưa có favicon hoặc đang dùng favicon default của framework → tự gen favicon hợp nội dung site, không hỏi. LAZY, load khi chạm HTML/static/layout.
status: live
updated: 2026-10-20
paths:
  - "**/*.html"
  - "**/public/**"
  - "**/static/**"
  - "**/app/layout.*"
  - "**/pages/_document.*"
  - "**/*.webmanifest"
  - "**/manifest.json"
  - "**/favicon*"
metadata:
  type: reference
---

# Web favicon — thiếu hoặc default thì tự gen

## Khi nào áp

Task làm/sửa website, admin UI, landing page → check favicon. Tự gen (không hỏi user) khi:

- Không có favicon: thiếu file và thiếu `<link rel="icon">` (trình duyệt 404 `/favicon.ico`).
- Đang dùng favicon default của framework/template: logo Vite, React, Next.js, Vue, Angular, Spring, Tomcat, CRA… (nhận biết qua tên file `vite.svg`, `react.svg`, `next.svg` hoặc hash trùng file trong `node_modules`/template gốc).

Đã có favicon riêng của project/brand → giữ nguyên, KHÔNG gen đè.

## Cách gen

1. Suy nội dung từ project: tên app, mục đích, màu chủ đạo (CSS variable/theme), logo brand có sẵn trong repo → có logo thì dựng favicon từ logo đó, không gen mới.
2. Không có logo → ưu tiên **SVG tay** (chữ cái/biểu tượng đơn giản + màu theme): nhẹ, nét ở mọi size, không tốn quota. Chỉ dùng skill `ace-gen-image` khi cần hình minh hoạ phức tạp.
3. Xuất tối thiểu: `favicon.svg` + `favicon.ico` (hoặc PNG 32×32) + `apple-touch-icon.png` 180×180. Raster từ SVG bằng tool có sẵn (`rsvg-convert`, `magick`, `sips`) — không thêm dependency.
4. Đặt đúng chỗ framework phục vụ static (`public/`, `static/`, `src/main/resources/static/`, `app/icon.*` của Next) + khai `<link rel="icon">` / manifest `icons`. Thay thế file default thì xoá file default cũ.
5. Verify: mở trang (hoặc `curl -I` path icon) → 200 + đúng `Content-Type`. Service có nhiều port (vd admin tách riêng) → chỉ gắn ở port có UI.

## Tránh

- ❌ Gen đè favicon brand đã có.
- ❌ Icon chung chung không liên quan nội dung (quả địa cầu, chữ "A" xám) khi đã biết tên/mục đích app.
- ❌ Ảnh nặng (> 50 KB) làm favicon.
