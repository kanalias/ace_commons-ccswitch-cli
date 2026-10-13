---
name: audit-presence
description: Audit read-only hiện diện public của công ty (website, trang social) — thông tin có nhất quán giữa các kênh, không lộ PII, không dính từ cấm. Bảng chuẩn đọc từ `.claude/presence-reference.md` của project. Dùng khi user gõ /audit-presence [<kênh>|all], hoặc nói "audit fanpage / website", "kiểm tra lại mọi thứ public".
user-invocable: true
---

# /audit-presence — audit hiện diện public

Không tham số → `all` (mọi kênh trong bảng chuẩn). Skill **read-only**: chỉ đọc kênh và lập báo cáo, **không ghi gì lên bất kỳ kênh nào** (không sửa info, không đăng/xoá bài, không commit web). Sửa kênh là việc riêng, chỉ làm khi user xác nhận trong session.

## Bảng chuẩn theo project (harness không cài, không ghi đè)

Đọc `.claude/presence-reference.md` trước. File vắng, hoặc còn `<...>` chưa điền → **dừng**, in mẫu dưới đây cho user điền, không tự bịa giá trị.

```markdown
# Presence reference
## Thông tin đúng (mọi kênh phải khớp)
| Trường | Giá trị đúng |
|---|---|
| Tên | <tên công ty, cách viết hoa> |
| Định vị | <mô tả 1 câu> |
| Địa điểm | <mức chi tiết được phép public> |
| Email liên hệ | <email duy nhất được public> |
| Giờ làm việc | <...> |
## Kênh
| Kênh | URL | Cách đọc (agent browser / curl / file repo) |
|---|---|---|
| <website> | <url> | <...> |
| <social> | <url> | <...> |
## Từ cấm / quảng cáo tuyệt đối
- <danh sách>
## Mẫu PII
- <regex hoặc mô tả: SĐT, email ngoài danh sách, tên người thật, địa chỉ cụ thể...>
```

Muốn đổi thông tin chuẩn → **sửa bảng chuẩn trước, rồi mới sửa kênh**. Kênh lệch bảng = finding; bảng lỗi thời thì sửa bảng, không "sửa" kênh cho khớp bảng sai.

## Các bước

1. Đọc bảng chuẩn. Mỗi kênh một lượt đọc (kênh cần đăng nhập dùng subagent browser của project; kênh khác nhau chạy song song được). Gặp màn login → dừng, nhờ user tự đăng nhập; không nhập password, không bypass captcha/2FA, không lấy cookie.
2. Với từng kênh, đối chiếu từng trường của bảng chuẩn: tên, định vị, địa điểm, email, giờ, link chéo giữa các kênh (không chết, đúng URL).
3. Quét từ cấm và quảng cáo tuyệt đối trong nội dung kênh (bio, bài đăng, metadata trang).
4. Quét PII theo mẫu trong bảng chuẩn, gồm cả thông tin người vận hành tài khoản (tên/ảnh cá nhân, email cá nhân). Phát hiện PII đã public → báo user ngay, đề xuất gỡ.
5. Đối chiếu chéo: bảng kênh × trường, đánh dấu ô lệch.
6. Nội dung repo (nếu website là file trong repo) so với bản live: repo đúng mà live chưa có → ghi "chưa deploy", không coi là lỗi nội dung.

## Output

Báo cáo tiếng Việt, ngắn, bảng finding theo kênh:

```
## Audit presence — <ngày>
| Kênh | Mục | Mức ưu tiên | Ghi chú / đề xuất |
|---|---|---|---|
| <kênh> | <trường> | P1 / P2 / P3 | <lệch gì, đề xuất> |
Việc cần làm (xếp theo ưu tiên): 1. ... 2. ...
```

Thứ tự ưu tiên: **P1 lộ PII / từ cấm** > **P2 lệch thông tin** > **P3 thiếu sót trình bày** (bio trống, link chết, thiếu link apply...).

## Khi cần sửa (chỉ sau khi user OK)

- Thứ tự: bảng chuẩn → kênh → báo cáo lại.
- Xoá bài/xoá thông tin public là **không hoàn tác** → liệt kê rõ từng mục và hỏi xác nhận **mỗi lần**; bài trùng lặp thì hỏi user giữ bài nào, không tự xoá.
- Push/deploy website do user chạy.
