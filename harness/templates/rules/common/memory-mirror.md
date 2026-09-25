---
name: memory-mirror
description: Project-type memory (fact/decision công việc) có bản mirror git-tracked tại .claude/memory-mirror/ trong repo — CHỈ để xem/review, KHÔNG nạp vào context. Auto-memory private (~/.claude/projects/<hash>/memory/) vẫn là source-of-truth. Write/edit order khác delete order.
paths:
  - ".claude/memory-mirror/**"
  - ".claude/rules/**"
---

# Memory mirror — auto-memory ↔ `.claude/memory-mirror/`

Auto-memory (`~/.claude/projects/<hash>/memory/`) là **private per-máy**, không git-tracked — chỉ session Claude trên máy đó đọc được. Loại **project** (fact/decision/state công việc) có thêm bản mirror **git-tracked** tại `.claude/memory-mirror/` trong repo này, để team clone repo đọc được.

## `.claude/memory-mirror/` CHỈ ĐỂ XEM — KHÔNG nạp vào context

- Dir này là **bản sao để review qua git** (diff, PR, đọc bằng mắt). Claude Code **không tự đọc** nó khi khởi động session, và Claude **KHÔNG được** chủ động Read/recall từ đây thay cho auto-memory.
- Index nạp vào context mỗi session là `MEMORY.md` trong **auto-memory**, không phải `.claude/memory-mirror/MEMORY.md`.
- Không thêm hook/skill/rule nào cat dir này vào context. Skill audit memory ([[doctor-memory]], [[audit-context-memory]]) chỉ audit auto-memory — bỏ qua dir mirror.
- Cần recall fact project → đọc auto-memory. Mirror lệch auto-memory → auto-memory đúng, sửa mirror theo.

**Chỉ áp dụng cho project-type.** Loại `user`/`feedback`/`reference` (cách làm việc, thông tin về user, tra cứu external) **không mirror** — ở lại auto-memory only, vì đó là ngữ cảnh riêng giữa user và Claude, team không cần đọc.

## Thứ tự thao tác (quan trọng — 2 chiều khác nhau)

- **Ghi mới / sửa nội dung** project memory → `.claude/memory-mirror/<name>.md` (repo) TRƯỚC → patch cùng nội dung sang auto-memory SAU.
  - Lý do: nội dung còn tồn tại → repo (nơi user review được ngay) đi trước.
- **Xoá** project memory → auto-memory TRƯỚC → xoá bản copy `.claude/memory-mirror/<name>.md` (repo) SAU.
  - Lý do: nội dung biến mất hẳn → source-of-truth (auto-memory) xoá trước, repo chỉ là bản sao nên xoá sau.

## Khác

- Update `.claude/memory-mirror/MEMORY.md` (index) đồng bộ mỗi lần thêm/sửa/xoá — dùng để browse nhanh qua link Markdown, không phải nguồn dữ liệu.
- Trước khi copy bất kỳ file `project_*.md` nào sang repo (git-tracked, ai cũng đọc được) — PHẢI audit nội dung không chứa secret/key/token giá trị thật (chỉ mô tả/pattern là OK). Xem global `[[secrets-no-printout]]`.
- Không cần Skill riêng cho việc này — hành vi tự áp dụng mỗi lần ghi/sửa/xoá, không phải user-facing repeatable workflow gõ `/lệnh`.
