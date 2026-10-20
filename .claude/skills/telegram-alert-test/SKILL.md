---
name: telegram-alert-test
description: Gửi thử 1 alert Telegram qua CLI `service-alert` (lib-ott-gateway) để kiểm format/kênh trước khi gắn vào code thật — không curl thô, không tự đọc token. Dùng khi user nói "test thử format telegram", "gửi thử alert", "gửi thử vào group alert", /telegram-alert-test.
user-invocable: true
---

# telegram-alert-test — gửi thử alert

Đi đúng đường production: CLI `service-alert` của lib-ott-gateway (format `[Env][Project] [icon status] Service <name>`, token/chat đọc từ env, never throws, token redact). KHÔNG `curl api.telegram.org`, KHÔNG `cat .env`.

## Các bước

1. Project chưa có lib → cài theo skill `ace-library` (lib-ott-gateway ≥ v0.13.0: thiếu chat id thì gửi kênh alert mặc định).
2. Ghi detail cần test vào file tạm ngoài repo (`mktemp`), vd nội dung có `<pre>`, link, ký tự `& < >`.
3. Gửi (từ root project):
   ```bash
   npx service-alert --service <svc> --status info --title "format test" \
     [--field k=v ...] [--photo <png>] --env-file .env < "$TMP"
   ```
   Không có `--service` → lib tự gợi ý từ tên folder (lần đầu lưu lại; đổi bằng `npx service-alert init`).
4. Báo user kết quả `sent`/lý do (CLI không in token/chat id). Nhắc mở Telegram xem bằng mắt — API ok chỉ nghĩa là parse được.

## Lỗi format hay gặp

- `& < >` thô PHẢI escape (`&amp; &lt; &gt;`), không thì cả tin lỗi `can't parse entities`.
- Cột căn thẳng → `<pre>` (block), pad bằng code, không gõ cứng dấu cách.
- ≤ 4096 ký tự/tin; caption ảnh ≤ 1024 (lib tự tách).

## Lưu ý

- Chỉ gửi vào kênh alert/test; KHÔNG đổi chat id sang kênh public.
- Link demo → `example.com` (hook chặn host production chưa duyệt).
- Tin test để lại trong kênh; xoá → hỏi user trước.
