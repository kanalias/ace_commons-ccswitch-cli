---
name: doctor-memory
description: Audit + auto-fix auto-memory system — quét mọi memory dir (global tới project hiện tại, từ ~/.claude/projects/<slug>/memory), phát hiện broken link/orphan/naming lệch/nội dung nhét thẳng MEMORY.md/thừa-trùng/stale/not-memory-worthy, tự sửa case chắc chắn (cấu trúc, không mất nội dung), liệt kê + hỏi confirm trước khi xoá. Thêm `--report-only` để chỉ audit + report, không tự sửa gì (dùng khi chỉ muốn xem tình trạng memory). BỎ QUA `harness/templates/` khi verify claim. Chạy /doctor-memory, /doctor-memory --report-only, hoặc khi user hỏi "dọn memory", "memory nào thừa", "health check memory", "audit memory system", "memory nào nạp ngay memory nào nạp động", "chuyển memory sang load động".
user-invocable: true
---

# doctor-memory — audit + auto-fix auto-memory system (global → project hiện tại)

Cross-project: memory dir nằm ở `~/.claude/projects/<cwd-slug>/memory`, khoá theo path cwd chính xác (không tự merge ancestor). Mỗi dir có `MEMORY.md` (index, nạp TĨNH mọi session) + N file `user_*/feedback_*/project_*/reference_*.md` (nạp ĐỘNG, chỉ khi Claude Read/recall). Mục tiêu: MEMORY.md càng gọn càng tốt (chỉ 1 dòng/entry trỏ file), nội dung thật nằm trong file riêng.

Memory dir KHÔNG phải git repo — xoá không khôi phục được. Mặc định: fix cấu trúc (broken link, rename, tách file) auto làm luôn; xoá nội dung (file thừa/trùng/stale) BẮT BUỘC liệt kê + hỏi confirm trước, không tự xoá. Với `--report-only`: KHÔNG sửa gì cả, kể cả auto-fix cấu trúc — chỉ audit + report.

Khác [[audit-context-memory]] (audit **cái gì được nạp vào context mỗi session** — global rules, CLAUDE.md, project rules ALWAYS/LAZY, và MEMORY.md **index**): command này audit **bên trong memory system tự nó** — từng file `user_*/feedback_*/project_*/reference_*.md`, không chỉ index. Hai phạm vi không chồng nhau.

## Args

- (không tham số) — audit + auto-fix cấu trúc + hỏi confirm trước xoá nội dung.
- `--report-only` — chỉ liệt kê vấn đề, không sửa file nào (kể cả auto-fix cấu trúc).

## Phạm vi

- Quét: mọi memory dir ứng với ancestor path từ `$HOME` tới cwd hiện tại (chỉ dir thật tồn tại — KHÔNG tạo mới).
- **BỎ QUA `harness/templates/`** trong repo khi verify nội dung memory (grep xem claim còn đúng không) — dir này là template cài cho project khác, không phản ánh state thật của project đang chạy, dễ tạo false positive (vd thấy path/tên file trùng trong template rồi tưởng memory đúng/sai nhầm).

## Bước 1 — Tìm memory dir liên quan (ancestor chain)

```bash
p="$PWD"; chain=()
while true; do
  chain=("$p" "${chain[@]}")
  parent="$(dirname "$p")"
  [ "$parent" = "$p" ] && break
  p="$parent"
done
for d in "${chain[@]}"; do
  slug="$(printf '%s' "$d" | sed 's/[\/_]/-/g')"
  mdir="$HOME/.claude/projects/${slug}/memory"
  [ -d "$mdir" ] && echo "FOUND $mdir"
done
```

Kết quả thường 2 dòng: memory global (`$HOME`, `-Users-<user>`) + memory project hiện tại. Có thể nhiều hơn nếu user từng chạy Claude Code ở cấp thư mục trung gian. Audit từng dir tìm được.

## Bước 2 — Quét từng memory dir

Với mỗi dir, đọc `MEMORY.md` + `ls *.md` (trừ MEMORY.md), rồi phân loại:

1. **Broken link** — MEMORY.md trỏ file không tồn tại → sửa/xoá dòng index.
2. **Orphan file** — file tồn tại, không dòng nào trong MEMORY.md trỏ tới → thêm dòng index (nếu còn giá trị) hoặc xoá file.
3. **Naming lệch** — filename ≠ `<name:>` trong frontmatter, hoặc prefix không khớp `metadata.type` (`user_`, `feedback_`, `project_`, `reference_`) → rename file + sync lại link trong MEMORY.md, KHÔNG đổi nội dung body.
4. **Nội dung nhét thẳng MEMORY.md** — dòng index không phải format `- [Title](file.md) — hook` (vd nguyên đoạn văn bản, block dài) → case "tĩnh nên chuyển động": tách ra file riêng đúng type prefix.
5. **Thừa/trùng** — 2+ file `description` overlap rõ cùng chủ đề → đề xuất merge, hỏi user trước khi xoá.
6. **Stale** — memory có `<system-reminder>` "N days old" hoặc nội dung có claim kiểm chứng được (path/file/hành vi code) nhưng không còn đúng ở codebase hiện tại → verify bằng Read/grep thực tế (loại trừ `harness/templates/`), không đoán. Còn đúng thì giữ, sai thì flag update/xoá.
7. **Not-memory-worthy** — nội dung lẽ ra nên nằm trong CLAUDE.md/rule chứ không phải memory (code convention, kiến trúc suy ra được từ code, hoặc trùng nội dung đã có trong CLAUDE.md) → flag xoá khỏi memory, nói rõ nên add vào CLAUDE.md/rule thay vì memory nếu còn giá trị.

## Bước 3 — Auto-fix (không hỏi) vs liệt kê-hỏi (destructive)

Nếu chạy với `--report-only`: bỏ qua toàn bộ bước này, chỉ đưa report Bước 2 + đề xuất, KHÔNG sửa file nào.

**Auto-fix ngay, không cần hỏi từng cái** (thuần cấu trúc, không mất nội dung):

- Broken link → sửa lại path hoặc xoá dòng index (nếu file thật sự mất).
- Orphan file có giá trị → thêm dòng index trỏ tới.
- Naming lệch → rename file khớp `name:` frontmatter + sync lại link trong MEMORY.md. KHÔNG đổi nội dung body.
- Nội dung nhét thẳng MEMORY.md → tách ra file riêng đúng type prefix (`user_/feedback_/project_/reference_`) với frontmatter chuẩn, rút MEMORY.md còn 1 dòng link. Đây chính là "chuyển tĩnh → động".

**Liệt kê + hỏi confirm trước khi xoá** (mất nội dung, không undo được):

- Orphan file không còn giá trị.
- Thừa/trùng — đề xuất giữ file nào, xoá file nào.
- Stale — đã verify claim sai/lỗi thời.
- Not-memory-worthy — đề xuất xoá khỏi memory (và nói rõ nên add vào CLAUDE.md/rule thay vì memory nếu còn giá trị).

Format hỏi: liệt kê từng file kèm lý do 1 dòng, rồi hỏi `[a]ll xoá hết / [s]elect chọn từng cái / [n]one giữ nguyên`.

Sau fix: đọc lại MEMORY.md, đảm bảo mọi link còn trỏ đúng file tồn tại.

## Bước 4 — Thống kê tĩnh vs động

Cho mỗi memory dir tìm được ở Bước 1:

- **Nạp tĩnh (mọi session)**: nội dung `MEMORY.md` — số dòng, số entry, ước lượng token sau khi đã gọn (nếu vừa fix).
- **Nạp động (chỉ khi recall)**: từng file `user_*/feedback_*/project_*/reference_*.md` còn lại — tên + type + kích thước (dòng/byte), tổng số file.
- So sánh tỷ lệ: context "bảo đảm load mỗi session" (MEMORY.md) vs context "tiềm năng nếu đọc hết" (tổng toàn bộ file) — giúp user thấy khi nào MEMORY.md phình cần dọn.
- Nếu vừa auto-fix: so sánh trước/sau — bao nhiêu token tĩnh tiết kiệm được nhờ tách nội dung ra file riêng.

## Report

- Bảng ancestor chain: dir → tồn tại hay không → số memory file → số vấn đề tìm thấy theo loại (broken-link / orphan / naming / duplicate / stale / not-memory-worthy).
- Mỗi vấn đề: loại → file liên quan → hành động (ĐÃ SỬA tự động / ĐÃ XOÁ sau confirm / FLAG chờ user / chỉ report nếu `--report-only`).
- Thống kê Bước 4 cho từng memory dir (trước/sau nếu có fix).
- Nếu có xoá/rename: liệt kê rõ danh sách + xác nhận MEMORY.md đã sync.
