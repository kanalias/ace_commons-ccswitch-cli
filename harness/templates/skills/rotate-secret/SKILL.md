---
name: rotate-secret
description: "Xoay (rotate) 1 secret/token trong env file mà giá trị mới KHÔNG bao giờ vào chat/argv/history/log: khảo sát nơi dùng, sinh lệnh idempotent cho user tự chạy (đọc giá trị bằng read -rs trên máy đích), reload service, verify không lộ giá trị. Dùng /rotate-secret <TÊN_BIẾN> [local | <ssh-host> <env-file> <service>]."
user-invocable: true
disable-model-invocation: true
---
> **Confirmation gate:** Gọi lệnh rõ ràng không phải là xác nhận. Trước bất kỳ bước nào chạm server (ssh, sửa env file từ xa, restart service), liệt kê rõ host, file, service, tác động; hỏi user xác nhận rõ ràng trong conversation này và chờ.

# /rotate-secret — xoay secret an toàn

Tuân [[secrets-no-printout]]. Bất biến: **giá trị mới không đi qua Claude** — không vào chat, không vào argument của lệnh, không vào shell history, không vào log/file ghi lại. Claude KHÔNG BAO GIỜ yêu cầu user paste giá trị.

## Tham số

- `NAME` (bắt buộc): tên biến env cần xoay (vd `<SUPPLIER>_TOKEN_<MỤC_ĐÍCH>`).
- Target (tuỳ chọn): `local` (mặc định) hoặc `<ssh-host> <env-file> <service>`. Thiếu → hỏi user, không đoán.

## Bước

1. **Khảo sát read-only** — chỉ in tên file/host/path, KHÔNG in value:
   ```bash
   grep -rlE '^(export )?<NAME>=' --include='.env*' . 2>/dev/null     # file local chứa biến
   grep -rn  '<NAME>' --include='*.md' --include='*.json' --include='*.yml' -l . 2>/dev/null  # docs/CI/config nhắc tới tên
   ```
   Server: `ssh <host> "grep -lE '^(export )?<NAME>=' <env-file>"` (chỉ exit code + tên file). Liệt kê kết quả, hỏi user xác nhận target.
2. **User revoke/cấp lại ở provider** — Claude không làm thay. Placeholder: `<mở trang quản trị của supplier → revoke key cũ → tạo key mới>`. Nhắc các nơi khác có thể còn giá trị cũ: `.env` local, password manager, vault, CI secrets, tài liệu deploy, shell history cũ.
3. **User tự chạy lệnh cập nhật env file** (khối dưới, thay `<NAME>`, `<ENV_FILE>`). Target server: user `ssh` vào host (có tty) rồi chạy khối này ngay trên host đó — KHÔNG truyền giá trị qua `ssh host '…'`.
   ```bash
   # chạy trong terminal của user; prompt ẩn, giá trị không echo, không vào history/argv
   # bọc trong subshell ( … ): lỗi chỉ thoát subshell, KHÔNG đóng shell tương tác của user
   (
     NAME='<NAME>'; ENV_FILE='<ENV_FILE>'
     umask 077
     printf 'Nhập giá trị mới cho %s (ẩn): ' "$NAME"
     IFS= read -rs NEWVAL; echo
     [ -n "$NEWVAL" ] || { echo "rỗng, huỷ"; unset NEWVAL; exit 1; }
     TMP="$(mktemp "${ENV_FILE}.XXXXXX")" || exit 1
     export NAME NEWVAL
     # awk đọc qua ENVIRON (không qua argv); thay dòng nếu có, thêm cuối nếu chưa
     awk 'BEGIN{n=ENVIRON["NAME"]; v=ENVIRON["NEWVAL"]; done=0}
          $0 ~ "^(export )?" n "=" {print n "=" v; done=1; next}
          {print}
          END{if(!done) print n "=" v}' "$ENV_FILE" > "$TMP" && mv "$TMP" "$ENV_FILE"
     [ "$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %Lp "$ENV_FILE")" = 600 ] || chmod 600 "$ENV_FILE"
     LEN=${#NEWVAL}; unset NEWVAL; export -n NAME
     echo "đã cập nhật $NAME trong $ENV_FILE (độ dài: $LEN)"
   )
   ```
   Idempotent: chạy lại chỉ thay đúng dòng `NAME=`, không nhân đôi. Không bật `set -x`. Muốn tự điền giá trị sau → để `<điền-token>` trong tài liệu, đừng gõ giá trị vào lệnh.
4. **Reload** (tham số hoá theo service; pm2 cache env nên `restart` thường KHÔNG đủ):
   - pm2: `pm2 restart <app> --update-env`
   - docker compose: `docker compose up -d <service>` (recreate để nạp env mới)
   - khác: `systemctl restart <unit>` / lệnh tương đương của project.
5. **Verify không cần giá trị**:
   - độ dài: số `LEN` ở bước 3 khớp độ dài kỳ vọng của supplier.
   - pattern prefix công khai (nếu supplier có): `grep -qE '^<NAME>=<prefix-công-khai>' <ENV_FILE> && echo OK` (chỉ exit code, không in dòng).
   - kết nối: chạy lệnh test của service/healthcheck, chỉ báo exit code/HTTP status; credential nếu cần truyền thì qua env/file, KHÔNG qua argv hay `-v` log.
6. **Report** (tiếng Việt, ngắn): biến nào, file/host nào đã đổi, service đã reload, kết quả verify (độ dài/exit code), việc còn lại (revoke giá trị cũ ở provider đã làm chưa, nơi khác còn giá trị cũ).

## Nếu secret đã bị paste vào chat/log

Coi là **compromised**: dừng, cảnh báo user, xoay lại từ bước 2 với giá trị MỚI (cái cũ coi như lộ), tuyệt đối không nhắc lại giá trị đó trong bất kỳ response nào.

## Cấm

- ❌ Hỏi/nhận giá trị mới trong chat; ❌ đặt giá trị trong argument (`--token X`, `echo X >> file`, `sed -i "s/…/X/"`); ❌ `cat`/`grep` in dòng chứa value; ❌ `set -x`/`curl -v` khi có credential.
- ❌ Dùng MCP Notion cho vault ([[vault-no-mcp]]).
