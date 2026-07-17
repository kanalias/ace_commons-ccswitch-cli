# Secrets — KHÔNG expose ra chat/output (cross-project, P0)

⭐⭐⭐ Áp dụng MỌI project, MỌI turn. Ngang [[vault-no-mcp]].

## Cấm tuyệt đối

❌ In nguyên văn (full hoặc đủ đoạn để dùng lại được) ra chat/terminal-output/file log cho: API key, token, password, private key, connection string có credential, session cookie.

❌ Không chỉ cấm tự tạo ra secret — cấm cả việc **echo lại** secret user vừa paste vào chat (vd user gõ thẳng key vào message: vẫn phải redact khi nhắc lại, không copy nguyên văn ra response).

❌ Không dùng lệnh thiếu redact khi biết trước output có thể chứa secret (`cat` file credentials, `env`, `git log -p` vùng có key, response body chứa token) — luôn pipe qua mask/redact hoặc chỉ lấy phần không nhạy cảm (tên field, exit code, độ dài) trước khi in.

## Cách đúng

1. **Trước khi chạy lệnh** có khả năng in secret (`cat .env`, `cat credentials`, `jq` trên file chứa token…): tự hỏi "output này có secret không" — nếu có, thêm redact (`sed`, `jq` chỉ lấy key names, hoặc chỉ check `grep -q` trả exit code) thay vì in raw.
2. **Phát hiện secret đã lỡ in ra** (do lệnh trước đó, hoặc user tự paste vào chat): dừng lại, cảnh báo rõ với user là secret đã lộ trong conversation/log, khuyến nghị rotate — không lặp lại secret đó thêm lần nào nữa trong response tiếp theo.
3. **Cần xác nhận secret tồn tại/đúng định dạng** mà không cần xem giá trị: dùng cách kiểm tra gián tiếp — độ dài (`wc -c`), prefix/pattern (`grep -oE '^sk-[a-z0-9]{6}'`), exit code của lệnh test kết nối — không `cat` toàn bộ giá trị.
4. **Khi user hỏi "key này có dùng ở đâu không?"**: search theo pattern/hash, chỉ báo TÌM THẤY hay KHÔNG + vị trí file (path, tên biến), không in lại giá trị đầy đủ trong câu trả lời.

## Áp dụng cho

- Đọc file `.env*`, `credentials`, `*.pem`, `id_rsa*`, `settings.json` có field `*_TOKEN`/`*_KEY`/`*_SECRET`.
- Output của `env`, `printenv`, `git log -p`, `git show` chạm file/commit có secret.
- Debug log, stack trace có thể chứa Authorization header hoặc query string mang token.
- Kết quả API test (`curl -v`) — luôn `-H "Authorization: Bearer <redacted>"` khi echo lại lệnh, không in token thật trong output hiển thị cho user.

## Khi phát hiện secret ĐÃ lộ (trong chat, log, hoặc vừa commit)

- Coi secret đó là **compromised ngay lập tức** — khuyến nghị rotate/revoke, không chỉ xoá dòng chat.
- Không cố "xoá" secret khỏi lịch sử conversation (không xoá được) — hướng dẫn user hành động tiếp theo (đổi password, revoke key) thay vì giả vờ như chưa thấy.

## Tránh

- ❌ "Chỉ đang debug thôi, redact sau" — redact NGAY tại lệnh in ra, không có bước "sau".
- ❌ Dùng `sed`/`awk` redact nhưng để lỗi cú pháp khiến lệnh in nguyên văn — verify redact pattern trước khi chạy trên file thật chứa secret (test trên chuỗi giả lập trước nếu không chắc regex).
- ❌ Nhắc lại secret user paste vào chat "để xác nhận" — xác nhận bằng cách mô tả (độ dài, prefix, vị trí tìm thấy), không lặp lại giá trị.

Liên quan: [[vault-no-mcp]] (vault CRUD riêng, không qua MCP), [[feature-redflags]] (red-flag rationalization nói chung).
