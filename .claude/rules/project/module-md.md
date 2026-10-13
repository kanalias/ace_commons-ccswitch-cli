---
name: module-md
description: Mỗi thư mục con cấp 1 dưới root cấu hình (HARNESS_DIR_DOC_ROOTS) có MODULE.md ghi intent + invariants; code đổi thì doc đổi cùng commit. LAZY, load khi chạm MODULE.md.
status: live
updated: 2026-10-13
paths:
  - "**/MODULE.md"
metadata:
  type: reference
---

# MODULE.md — doc theo thư mục (intent + invariants)

> Code cho thấy WHAT; MODULE.md cho thấy WHY + invariants. AI session không có trí nhớ dài hạn về module — doc này là cách inject context có chủ đích, không phụ thuộc grep may rủi.

## Enforcement

- 2 hook, cấu hình bằng `HARNESS_DIR_DOC_ROOTS` (thư mục tương đối repo, ngăn bằng `:`, vd `src/app/modules`) trong `.claude/settings.json` → `env`; `HARNESS_DIR_DOC_NAME` đổi tên doc (mặc định `MODULE.md`):
  - `pre-read-inject-dir-doc.sh` (PreToolUse Read|Edit|Write|MultiEdit): tự inject doc của thư mục con cấp 1 khi chạm file trong đó (1 lần/session/doc, cắt 200 dòng đầu).
  - `post-edit-advisor.sh`: sau khi sửa file source mà doc cũ hơn → nhắc cập nhật doc.
- Env chưa đặt → rule này chỉ là advisory (không hook nào chạy). Không có chặn push/commit.

## Phạm vi

- Chỉ thư mục con **cấp 1** dưới mỗi root: `<root>/<name>/MODULE.md`. Thư mục sâu hơn không bắt buộc.
- Tên đúng `MODULE.md` (uppercase) — dễ grep, nổi bật so với README. README cho người mới, MODULE.md cho AI + invariants; không thay thế nhau.
- Module mới đang scaffold: cho grace period tới khi cấu trúc ổn định.

## Section bắt buộc (đúng thứ tự)

```markdown
# <Module Name> Module

**Last updated:** YYYY-MM-DD

## 1. Purpose
<1-3 câu: module làm gì, vì sao tồn tại, ai dùng>

## 2. Entry points
<hàm/class export chính + path:line>

## 3. Flow
<ASCII diagram / sequence cho golden path — không thay bằng prose>

## 4. Invariants
<luật RIÊNG của module; không lặp lại rule đã có ở .claude/rules/>

## 5. Test path
<vị trí test + 1 dòng cách chạy>

## 6. Anti-patterns
<3-5 sai lầm phổ biến/đã gặp, dạng bullet>
```

Tuỳ chọn: Cross-references, Incidents, LOCAL vs PROD, File map (khi >10 file).

## Workflow cho AI

**Module chưa có doc** khi chạm vào:

1. Đọc entry file + 2-3 file quan trọng nhất.
2. Draft theo template 6 section.
3. **Hỏi user confirm** nội dung nêu intent/invariants trước khi lưu — user là source-of-truth.
4. Lưu + commit cùng thay đổi code.

**Sửa hành vi module đã có doc:** đọc doc trước (hook đã inject) → sau khi sửa, cập nhật phần bị chạm (entry point → §2, flow → §3, invariant → §4) + dòng `Last updated`.

## Single-commit rule

Commit chạm source trong `<root>/<X>/` thì stage kèm `<root>/<X>/MODULE.md` **cùng commit** — tối thiểu bump dòng `**Last updated:**` (chứng minh đã đối chiếu doc với code).

- ❌ Commit code, "doc commit sau" (commit sau thường không xảy ra)
- ❌ Commit doc trước, code sau (doc lệch khỏi code đang chạy)
- Không cần doc update cho: file test, `*.md`, config snapshot, fixtures/snapshots.

## Anti-patterns

| Suy nghĩ | Thực tế |
|---|---|
| "Module nhỏ, code đọc được, không cần MODULE.md" | Code cho WHAT; invariants + WHY không thấy từ code. |
| "Đã có README rồi" | README cho người mới; MODULE.md là flow + invariants cho AI. Khác mục đích. |
| "Fix bug xong rồi viết MODULE.md sau" | "Sau" không xảy ra. Code + doc cùng commit. |
| "Copy MODULE.md của module khác cho nhanh" | Mỗi module có invariants riêng — copy = junk + drift. |
| "Section Flow viết prose cho nhanh" | ASCII diagram bắt buộc; prose dễ thiếu sequence + edge case. |
| "Code đổi nhỏ, không đụng doc" | Tối thiểu bump `Last updated`. |
| "Tự viết invariants, khỏi hỏi user" | Doc phản ánh intent — user xác nhận trước khi lưu. |

## Backfill (Boy Scout)

Không đua viết doc cho mọi module cũ. Chạm file trong module chưa có `MODULE.md` → viết doc cho module đó trong cùng PR.

## Audit nhanh

```bash
test -f <root>/<X>/MODULE.md || echo "MISSING"
grep "Last updated:" <root>/<X>/MODULE.md
grep -cE "^## [1-6]\." <root>/<X>/MODULE.md   # expect 6
```
