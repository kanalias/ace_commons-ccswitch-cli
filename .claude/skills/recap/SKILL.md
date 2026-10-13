---
name: recap
description: "Tóm tắt chi tiết công việc đã làm (từ git log + diff + fix-ledger) thành báo cáo tiếng Việt cho người khác đọc (sếp/khách/team). Dùng /recap [since] [--save], hoặc khi user nói \"tóm tắt công việc\", \"báo cáo hôm nay/tuần này\", \"recap\"."
user-invocable: true
---

# recap — báo cáo công việc đã làm

Nguồn dữ liệu = git (sự thật đã commit). KHÔNG bịa việc không có trong commit/diff.

## Tham số

- `since` (mặc định `1.day`): `1.day`, `1.week`, ngày dạng `YYYY-MM-DD`, hoặc ref (`v1.2`, `abc123`).
- `--save`: ghi ra `docs/recap/recap-<YYYY-MM-DD>.md` (mặc định chỉ in chat).
- Branch: mặc định branch hiện tại (`git branch --show-current`); không xác định được (detached HEAD) → dùng `main`. Dưới đây ký hiệu `<branch>`.

## Bước

1. Thu dữ liệu (chạy song song, 1 message):
   ```bash
   git log <branch> --no-merges --since="<since>" --pretty='%h|%ad|%s' --date=short   # ref → dùng <ref>..<branch>
   git log <branch> --no-merges --since="<since>" --stat --pretty='--- %h %s'
   git log <branch> --merges --since="<since>" --pretty='%h %s'                        # feature/fix branch đã merge
   git status --short                                                                  # việc dở chưa commit
   ```
   - Có `.claude/fix-ledger.md` → đọc entry trong khoảng ngày.
   - Commit mơ hồ (subject không đủ hiểu) → `git show <hash> --stat` + đọc diff phần chính. Diff lớn → chỉ đọc file chính, không nạp hết.
   - **Không in secret**: diff chạm `.env*`/credentials → chỉ nêu tên file, không trích nội dung.
2. Nhóm theo **tính năng/kết quả**, không theo commit (nhiều commit cùng 1 việc → 1 mục). Bỏ commit chore vặt (format, typo) trừ khi là toàn bộ công việc.
3. Viết báo cáo theo mẫu dưới. Ngôn ngữ cho người không đọc code: nói **tác động** (người dùng thấy gì, lỗi gì hết), tên file chỉ để ở phần chi tiết.
4. `--save` → ghi file, báo path. Không tự commit.

## Mẫu

```markdown
# Báo cáo công việc — <từ ngày> → <đến ngày>

## Tóm tắt
- <2-5 gạch đầu dòng: kết quả chính>

## Chi tiết
### 1. <Tên việc> (feat|fix)
- **Vấn đề / mục tiêu:** …
- **Đã làm:** …
- **Kết quả / tác động:** …
- **Commit:** `<hash>` … · **File chính:** …

## Đang dở / chưa commit
- <từ git status, hoặc "Không có">

## Rủi ro / cần theo dõi
- <deploy chưa? cần restart service? migration? — hoặc "Không có">

## Số liệu
- <N> commit · <M> branch merge · +<add>/-<del> dòng · <K> file
```

Khoảng thời gian không có commit → báo "Không có commit từ <since>", không tạo file.
