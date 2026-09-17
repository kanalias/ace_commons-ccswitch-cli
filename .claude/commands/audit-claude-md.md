---
name: audit-claude-md
description: Audit file CLAUDE.md — phát hiện nội dung trùng lặp, link chết (dead link), và bảo vệ BLOCK harness rules do install.sh quản lý (giữa marker BEGIN/END HARNESS RULES). Nếu phát hiện trùng lặp thì edit gộp lại, LUÔN ưu tiên giữ nội dung trong BLOCK harness. Dùng khi user gõ /audit-claude-md hoặc yêu cầu "kiểm tra CLAUDE.md", "audit CLAUDE.md", "dọn CLAUDE.md trùng lặp".
user-invocable: true
---

# /audit-claude-md — audit CLAUDE.md (trùng lặp + dead link + bảo vệ BLOCK harness)

## Args

```text
/audit-claude-md [path]
```

`path` mặc định `./CLAUDE.md` nếu không truyền. File không tồn tại → báo user, dừng.

## Bất biến — BLOCK harness (ĐỌC TRƯỚC)

CLAUDE.md có 1 khối managed do `install.sh` sinh, nằm giữa 2 marker:

```text
<!-- BEGIN HARNESS RULES (managed by install.sh — do not edit inside) -->
...
<!-- END HARNESS RULES -->
```

- **KHÔNG bao giờ xoá/sửa nội dung BÊN TRONG 2 marker.** install.sh overwrite lại khi re-sync — sửa tay là mất công + lệch source-of-truth.
- Khi resolve trùng lặp: nếu 1 nội dung xuất hiện cả TRONG block lẫn NGOÀI block → **giữ bản trong block, xoá/thay bản ngoài** bằng pointer (link tới `.claude/rules/...` hoặc `[[name]]`).
- Marker mất/hỏng (chỉ có 1 trong 2, hoặc thứ tự sai) → flag báo user chạy lại `harness/install.sh`, KHÔNG tự vá tay.

## Bước 1 — Đọc + định vị block

```bash
CMD="${1:-./CLAUDE.md}"
[ -f "$CMD" ] || { echo "KHÔNG tìm thấy $CMD"; exit 1; }
grep -n "BEGIN HARNESS RULES\|END HARNESS RULES" "$CMD"
```

Đọc toàn bộ file bằng Read. Ghi nhận số dòng của [begin, end] — mọi thao tác sửa phải NẰM NGOÀI khoảng này.

## Bước 2 — Phát hiện dead link

Trích mọi link Markdown `[text](target)` và wiki-link `[[name]]`, phân loại target:

1. **Đường dẫn nội bộ tương đối** (`.claude/...`, `./...`, `../...`, `path/file.md`) — kiểm tra tồn tại thật bằng `test -e` (relative tới thư mục chứa CLAUDE.md). Không tồn tại → **DEAD**.
2. **Anchor cùng file** (`#heading`) — verify heading khớp (slugify) tồn tại trong file. Không khớp → **DEAD**.
3. **`[[name]]` wiki-link** — resolve tới rule slug (`.claude/rules/**/<name>.md` hoặc global `~/.claude/rules/<name>.md`). Không tìm thấy file nào → flag **WIKI-UNRESOLVED** (cảnh báo, không tự xoá — có thể là placeholder chủ ý).
4. **URL http(s)** — KHÔNG fetch mạng (tránh chậm/false-positive). Chỉ liệt kê, không chấm dead.

Dead link nằm TRONG block → chỉ báo (không sửa), khuyến nghị re-run install.sh.

## Bước 3 — Phát hiện trùng lặp

So sánh theo Ý (semantic), không chỉ khớp chuỗi:

1. **Trùng nội-file** — 2+ đoạn/section trong CLAUDE.md nói cùng 1 quy tắc bằng lời khác nhau.
2. **Trùng với block** — nội dung NGOÀI block lặp lại điều đã có TRONG block (vd nhắc lại "rules tách 2 tầng", "common synced / project preserve").
3. **Trùng với rule file** — CLAUDE.md nhắc lại nguyên văn nội dung đã có trong `.claude/rules/**` → nên thay bằng link/`[[name]]`.

Mỗi finding ghi: dòng, nội dung tóm tắt, bản nào nên GIỮ, bản nào THAY.

## Bước 4 — Báo cáo (chưa sửa)

```text
## Audit CLAUDE.md — <path>

### BLOCK harness
- Marker: OK / HỎNG (chi tiết)
- Dòng block: [begin]–[end]

### Dead link
| # | Dòng | Link | Loại | Trạng thái |
|---|------|------|------|-----------|

### Trùng lặp
| # | Dòng | Nội dung | Giữ | Thay |
|---|------|----------|-----|------|

### Đề xuất sửa (ngoài block)
<liệt kê edit cụ thể>
```

## Bước 5 — Áp fix (sau khi user chọn `[a]ll / [s]elect / [n]one`)

Chỉ sửa phần NGOÀI block. Nguyên tắc ưu tiên khi resolve trùng:

1. Nội dung cũng có TRONG block → **giữ block**, xoá bản ngoài (hoặc thay bằng pointer 1 dòng).
2. Trùng với rule file → thay đoạn dài bằng link `[.claude/rules/...]` hoặc `[[name]]`.
3. Trùng nội-file thuần → gộp về 1 chỗ, chỗ còn lại tham chiếu.
4. Dead link ngoài block → sửa target đúng nếu tìm được, không thì xoá link giữ lại text + flag.

Sau khi sửa: chạy lại Bước 1 (grep marker) xác nhận block còn nguyên vẹn, báo số dòng giảm.
