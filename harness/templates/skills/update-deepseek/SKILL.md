---
name: update-deepseek
description: Kiểm tra + cập nhật công cụ đứng sau delegate-deepseek (Aider CLI qua Homebrew) trên macOS, và kiểm tra read-only endpoint DeepSeek (9router hoặc endpoint DeepSeek trực tiếp) còn reachable — không in secret. Chạy /update-deepseek, hoặc khi user hỏi "update deepseek", "update aider", "aider đã cập nhật chưa".
user-invocable: true
---

# update-deepseek — kiểm tra + cập nhật Aider (backend delegate-deepseek)

## Bối cảnh

`delegate-deepseek` KHÔNG có "DeepSeek CLI" riêng — nó chạy Aider (Python CLI) trỏ vào model DeepSeek qua `scripts/delegate/run-aider-deepseek.sh`. Model + endpoint chọn động lúc chạy (không phải cài đặt cần update):

| Thành phần | Path | Ai cập nhật |
|---|---|---|
| **Aider CLI** | `/opt/homebrew/bin/aider` (Homebrew formula `aider`) | Thủ công `brew upgrade aider` — máy này KHÔNG có LaunchAgent auto-upgrade riêng cho aider (khác `claude-code`/`codex`/`gemini-cli`) |
| **Model/endpoint** | resolved runtime trong wrapper qua `PROXY_9ROUTER_TOKEN`/`PROXY_9ROUTER_BASE_URL` (ưu tiên) hoặc `DEEPSEEK_API_KEY` (fallback endpoint DeepSeek trực tiếp — mặc định của aider/LiteLLM); tên model mặc định `DEEPSEEK_MODEL` | Sửa trong `.env`, không phải "update" |

Không có LaunchAgent nghĩa là aider có thể cũ âm thầm — luôn check version trước khi tin nó mới nhất.

## Bước 1 — Trạng thái hiện tại (read-only)

```bash
echo "aider bin : $(which -a aider)"
echo "aider ver : $(aider --version 2>&1 | head -1)"
/opt/homebrew/bin/brew info aider 2>&1 | head -6
echo "outdated  :"; /opt/homebrew/bin/brew outdated 2>&1 | grep -i aider || echo "  (không outdated, hoặc chưa check được)"
echo "agents    :"; launchctl list | grep -iE "aider|deepseek" || echo "  (không có LaunchAgent auto-upgrade cho aider)"
```

Kiểm tra env var cấu hình model/endpoint có tồn tại hay không, đọc từ chain `.env.local` → `.env` mà wrapper dùng (`scripts/delegate/_common.sh` `load_env_chain`) — **KHÔNG in giá trị**, chỉ tên biến. Tương thích cả zsh lẫn bash (không dùng `${!v}` bash-only):

```bash
cd "$(git rev-parse --show-toplevel)"
for k in DEEPSEEK_MODEL DEEPSEEK_API_KEY PROXY_9ROUTER_TOKEN PROXY_9ROUTER_BASE_URL; do
  if grep -qE "^${k}=.+" .env.local 2>/dev/null || grep -qE "^${k}=.+" .env 2>/dev/null; then
    echo "$k: set"
  else
    echo "$k: (unset)"
  fi
done
```

## Bước 2 — Cập nhật Aider qua Homebrew

```bash
/opt/homebrew/bin/brew upgrade aider 2>&1 | tail -n 10
echo "sau update: $(aider --version 2>&1 | head -1)"
```

## Bước 3 — (tuỳ chọn) Kiểm tra endpoint DeepSeek reachable

Chỉ lấy HTTP status code, không bao giờ echo URL/token:

```bash
cd "$(git rev-parse --show-toplevel)"
url="$(grep -E '^PROXY_9ROUTER_BASE_URL=' .env.local .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//" | tr -d '\r')"
if [ -n "$url" ]; then
  curl -s -o /dev/null -w "9router status: %{http_code}\n" "$url"
else
  echo "PROXY_9ROUTER_BASE_URL chưa set — wrapper sẽ dùng endpoint DeepSeek trực tiếp (mặc định của aider/LiteLLM), bỏ qua check reachability"
fi
```

Status 200/401/404 đều coi là "reachable" (server trả lời); timeout/000 mới là vấn đề mạng thật sự.

## Bước 4 — Báo cáo

Bảng ngắn: version aider trước → sau, env var nào đã set (chỉ tên, không giá trị), kết quả reachability check. Nhắc: worktree `delegate-deepseek` đang chạy dở (nếu có) không bị ảnh hưởng — Aider chỉ ảnh hưởng lần gọi kế tiếp.

## Xử lý sự cố

- `brew upgrade aider` fail dependency conflict → báo lỗi brew nguyên văn, không tự `brew reinstall`/`--force`.
- Muốn auto-upgrade định kỳ như `claude-code`/`codex`/`gemini-cli` → có thể tạo LaunchAgent mới theo pattern `com.user.brew-upgrade-<formula>` (xem `~/Library/LaunchAgents/com.user.brew-upgrade-codex.plist` làm mẫu) — KHÔNG tự tạo trong command này, chỉ gợi ý, để user quyết.
- Reachability check trả `000`/timeout → có thể do IPv6 blackhole đã note trong `scripts/delegate/lib/sitecustomize.py` (wrapper aider tự ép AF_INET) — không phải lỗi cấu hình endpoint. Endpoint DeepSeek trực tiếp không có script check sẵn trong command này — nếu cần, tự curl HTTP status code, không in URL/token.
- Nghi ngờ model DeepSeek đổi tên/deprecated → không tự đổi `DEEPSEEK_MODEL` trong `.env`, báo user để họ quyết định giá trị mới.
