---
name: copy-data-cmd
description: Khi cần copy/ghi/thêm data (env, secret, token, file, cấu hình) từ nơi này sang nơi khác mà Claude thiếu quyền hoặc bị chặn — KHÔNG hỏi nguồn/đích, tự suy ra rồi sinh câu lệnh/script cho user chạy. Dùng cho mọi project, mọi file, mọi hướng (local, host, server, Mac, container).
user-invocable: true
---

# copy-data-cmd — tự sinh lệnh copy, không hỏi, không vòng quyền

## Khi nào dùng
- User nói "cho câu lệnh copy", "chuyển sang ...", "thêm biến này vào ...".
- Claude cần ghi/copy data nhưng thiếu quyền: permission/classifier chặn, ghi vào host/prod/secret store, file ngoài scope.
- Bất kỳ file nào, bất kể từ đâu sang đâu. Không giới hạn project.

## Quy tắc
1. KHÔNG hỏi "copy từ đâu tới đâu / thêm vào file nào". Tự suy nguồn và đích từ ngữ cảnh (repo, memory, config deploy, host đã biết). Chỉ hỏi khi thật sự không suy ra được đích.
2. Có quyền thì tự chạy; bị chặn quyền thì KHÔNG vòng qua (không đổi tool, chia nhỏ lệnh, đổi host/encoding). Chuyển sang sinh lệnh để user tự chạy.
3. Sau khi user chạy, verify chỉ-đọc nếu được phép.

## Cách sinh lệnh
- Đơn giản: 1 lệnh một dòng (`scp`, `rsync`, `cp`, `ssh host 'cat >> file'`).
- Nhiều bước hoặc có secret: đưa thành 1 khối `bash <<'EOF'` để user dán, hoặc script tạm ở `$HOME` (không trong repo). Script phải:
  - `set -euo pipefail`; đọc giá trị từ nguồn bằng `grep`/`cut`, KHÔNG hardcode giá trị.
  - Gửi secret qua stdin của ssh, không đưa vào argv hay lịch sử shell.
  - Backup đích trước khi sửa: `cp -p file file.bak-$(date +%Y%m%d%H%M%S)`.
  - Upsert key: xoá dòng `KEY=` cũ rồi append dòng mới; `chmod 600` cho file secret.
  - Verify không in giá trị: chỉ độ dài, số biến, username từ `getMe`, exit code.
  - `unset` biến chứa secret; script tạm tự xoá cuối (`rm -- "$0"`).
- File .txt tạm: `mktemp`, quyền 600, xoá ngay sau khi copy.

## Ràng buộc secret
- Không in/echo giá trị vào chat, log, output. Không commit script/file chứa secret.
- Không đẩy file env/secret lên git remote. Không dùng MCP connector cho vault.
- Lỡ in ra → báo user là secret đã lộ, khuyến nghị rotate.

## Sau khi chạy
- Verify chỉ-đọc: độ dài biến, trạng thái service, log vài dòng (đã redact). Báo kết quả ngắn gọn.
