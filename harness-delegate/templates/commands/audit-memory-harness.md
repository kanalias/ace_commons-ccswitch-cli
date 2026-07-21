---
name: audit-memory-harness
description: Audit toàn bộ auto-memory system — từ global (~/.claude/projects/<home-slug>/memory) tới memory của project đang chạy — phát hiện file thừa/trùng/stale, tên file lệch chuẩn lazy-load (không khớp `name:` frontmatter hoặc thiếu type prefix), link MEMORY.md gãy/orphan, rồi thống kê memory nạp tĩnh (MEMORY.md, mọi session) vs nạp động (từng file, chỉ đọc khi recall). BỎ QUA `harness-delegate/templates/` khi verify claim (dir mẫu cho project khác, không phải state thật). Chạy /audit-memory-harness, hoặc khi user hỏi "dọn memory", "memory nào đang thừa", "audit memory system", "memory nào nạp ngay memory nào nạp động".
user-invocable: true
---

# audit-memory-harness — audit auto-memory system (global → project hiện tại)

Memory system nằm ở `~/.claude/projects/<slug>/memory`, khoá theo path cwd chính xác (không tự merge ancestor). Mỗi memory dir có `MEMORY.md` (index, LUÔN nạp mỗi session — tương đương ALWAYS trong [[lazy-load-audit]]) + N file riêng theo type (`user_*`, `feedback_*`, `project_*`, `reference_*`) — CHỈ nạp khi Claude chủ động Read/recall (tương đương LAZY). "Từ global tới project" = quét MỌI slug tồn tại trong chain thư mục cha từ `$HOME` xuống tới cwd hiện tại, không chỉ memory của project hiện tại.

## Phạm vi

- Quét: mọi memory dir ứng với ancestor path từ `$HOME` tới cwd hiện tại (chỉ dir thật tồn tại — KHÔNG tạo mới).
- **BỎ QUA `harness-delegate/templates/`** trong repo khi verify nội dung memory (grep xem claim còn đúng không) — dir này là template cài cho project khác, không phản ánh state thật của project đang chạy, dễ tạo false positive (vd thấy path/tên file trùng trong template rồi tưởng memory đúng/sai nhầm).

## Bước 1 — liệt kê ancestor chain + memory dir tồn tại

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

Kết quả thường 2 dòng: memory global (`$HOME`, "-Users-<user>") + memory project hiện tại. Có thể nhiều hơn nếu user từng chạy Claude Code ở cấp thư mục trung gian.

## Bước 2 — audit từng memory dir tìm được

1. **Index vs file thật** — đọc `MEMORY.md`, list link `(file.md)`; đối chiếu `ls *.md` (trừ `MEMORY.md`).
   - **Broken link**: MEMORY.md trỏ file không tồn tại → sửa/xoá dòng index.
   - **Orphan file**: file tồn tại, không dòng nào trong MEMORY.md trỏ tới → thêm dòng index (nếu còn giá trị) hoặc xoá file.

2. **Filename vs convention lazy-load** — đọc `name:` trong frontmatter mỗi file:
   - Filename PHẢI = `<name>.md`.
   - Filename nên bắt đầu bằng prefix khớp `metadata.type` (`user_`, `feedback_`, `project_`, `reference_`).
   - Lệch → rename file + sync lại link trong MEMORY.md, KHÔNG đổi nội dung body.

3. **Thừa / trùng lặp** — 2+ file `description` overlap rõ (cùng chủ đề) → đề xuất merge, hỏi user trước khi xoá.

4. **Stale** — memory có `<system-reminder>` "N days old" + nội dung có claim kiểm chứng được (file/path/hành vi code) → verify nhanh bằng grep/Read trên code thật (loại trừ `harness-delegate/templates/`) → còn đúng thì giữ, sai thì flag update/xoá.

5. **Vi phạm "what NOT to save"** — file chỉ chứa thứ derivable từ code/git-log, hoặc trùng nội dung đã có trong CLAUDE.md → flag xoá (thuộc diện thừa).

## Bước 3 — fix (liệt kê trước, KHÔNG tự xoá không hỏi)

- Rename file lệch convention + sync MEMORY.md: liệt kê mapping cũ→mới, hỏi xác nhận `[a]ll/[s]elect/[n]one` trước khi đổi (memory dir không phải git repo — không có history khôi phục).
- Xoá file thừa/trùng/stale: BẮT BUỘC hỏi xác nhận trước khi xoá, kể cả khi rõ ràng thừa.
- Sau fix: đọc lại MEMORY.md, đảm bảo mọi link còn trỏ đúng file tồn tại.

## Bước 4 — thống kê nạp tĩnh vs nạp động

Với mỗi memory dir tìm được ở Bước 1:

- **Nạp ngay từ đầu (static, mọi session)**: nội dung `MEMORY.md` — số dòng, số entry.
- **Nạp động (lazy, chỉ khi recall)**: từng file `user_*/feedback_*/project_*/reference_*.md` còn lại — tên + type + kích thước (dòng/byte), tổng số file.
- So sánh tỷ lệ: context "bảo đảm load mỗi session" (MEMORY.md) vs context "tiềm năng nếu đọc hết" (tổng toàn bộ file) — giúp user thấy khi nào MEMORY.md phình cần dọn.

## Report

- Bảng ancestor chain: dir → tồn tại hay không → số memory file → số vấn đề tìm thấy.
- Mỗi vấn đề: loại (broken-link / orphan / naming / duplicate / stale / not-memory-worthy) → file liên quan → hành động (ĐÃ SỬA / ĐÃ XOÁ sau confirm / FLAG chờ user).
- Thống kê Bước 4 cho từng memory dir.
- Nếu có xoá/rename: liệt kê rõ danh sách + xác nhận MEMORY.md đã sync.
