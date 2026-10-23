---
name: web-ui-datatables
description: Mọi bảng/danh sách đọc data trên web UI (admin, dashboard) — 10 dòng/trang, tải trước 30 dòng (3 trang), quá 30 mới gọi tiếp theo cursor. LAZY, load khi chạm HTML/JS/CSS frontend.
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

# Web UI — bảng dữ liệu (datatable)

Áp MỌI bảng/danh sách đọc data (Notion, DB, API, log, IP, member, request…) ở mọi app, kể cả section riêng của app nhúng trong console lib.

- **10 dòng/trang.** Không 20/50/100, không đổ hết 1 trang.
- **Tải trước 30 dòng** (3 trang đầu) trong 1 lần đọc nguồn rồi cache; lật trang 1–3 không gọi lại nguồn.
- **Quá 30** → đọc batch 30 tiếp theo bằng cursor/offset của nguồn (Notion `start_cursor`, SQL keyset), không đọc toàn bộ bảng để cắt trang.
- Nguồn chỉ trả 1 cục (vd set IP trong 1 rule WAF) → vẫn hiển thị 10 dòng/trang, cắt trong bộ nhớ.
- Tìm kiếm/lọc chạy ở nguồn (filter query) khi nguồn hỗ trợ; kết quả cũng 10 dòng/trang.
- Pager hiện: trang hiện tại, tổng (hoặc "còn nữa" khi chưa biết tổng), nút trước/sau; tải trang mới có trạng thái loading.
