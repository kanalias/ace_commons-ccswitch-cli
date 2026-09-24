---
name: update-deepseek
description: "Kiểm tra + cập nhật Aider CLI (đứng sau delegate-deepseek) và check endpoint DeepSeek reachable, không in secret. Dùng /update-deepseek hoặc \"update aider\"."
user-invocable: true
---

# update-deepseek — kiểm tra + cập nhật Aider (backend delegate-deepseek)

## Bối cảnh

`delegate-deepseek` KHÔNG có "DeepSeek CLI" riêng — nó chạy Aider (Python CLI) trỏ vào model DeepSeek qua `scripts/delegate/run-aider-deepseek.sh`. Model + endpoint chọn động lúc chạy (không phải cài đặt cần update):

| Thành phần | Path | Ai cập nhật |
|---|---|---|
| **Aider CLI** | `$(command -v aider)` (Homebrew formula `aider`, nếu cài qua brew) | Thủ công `brew upgrade aider` — nếu máy này không có agent auto-upgrade riêng cho aider (khác `claude-code`/`codex`/`gemini-cli` nếu các tool đó có) |
| **Model/endpoint** | resolved runtime trong wrapper qua `PROXY_9ROUTER_TOKEN`/`PROXY_9ROUTER_BASE_URL` (ưu tiên) hoặc `DEEPSEEK_API_KEY` (fallback endpoint DeepSeek trực tiếp — mặc định của aider/LiteLLM); tên model mặc định `DEEPSEEK_MODEL` | Sửa trong `.env`, không phải "update" |

Không có agent auto-upgrade nghĩa là aider có thể cũ âm thầm — luôn check version trước khi tin nó mới nhất.

## Bước 1 — Trạng thái hiện tại (read-only)

```bash
echo "aider bin : $(which -a aider)"
echo "aider ver : $(aider --version 2>&1 | head -1)"
if command -v brew >/dev/null; then
  brew info aider 2>&1 | head -6
  echo "outdated  :"; brew outdated 2>&1 | grep -i aider || echo "  (không outdated, hoặc chưa check được)"
else
  echo "brew không có — kiểm tra cách cài khác (pipx/pip)"
fi
echo "agents    :"
case "$(uname)" in
  Darwin) launchctl list | grep -iE "aider|deepseek" || echo "  (không agent nào loaded cho aider)" ;;
  *) { crontab -l 2>/dev/null | grep -iE "aider|deepseek"; systemctl --user list-timers 2>/dev/null | grep -iE "aider|deepseek"; } || echo "  (không cron/timer nào cho aider)" ;;
esac
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
command -v brew >/dev/null && brew upgrade aider 2>&1 | tail -n 10 || echo "brew không có — cập nhật qua pipx/pip nếu áp dụng"
echo "sau update: $(aider --version 2>&1 | head -1)"
```

## Bước 3 — (tuỳ chọn) Kiểm tra proxy/endpoint DeepSeek reachable

Chỉ lấy HTTP status code, không bao giờ echo URL/token:

```bash
cd "$(git rev-parse --show-toplevel)"
url="$(grep -E '^PROXY_9ROUTER_BASE_URL=' .env.local .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//" | tr -d '\r')"
if [ -n "$url" ]; then
  curl -s -o /dev/null -w "proxy status: %{http_code}\n" "$url"
else
  echo "PROXY_9ROUTER_BASE_URL chưa set — wrapper sẽ dùng endpoint DeepSeek trực tiếp (mặc định của aider/LiteLLM), bỏ qua check reachability"
fi
```

Status 200/401/404 đều coi là "reachable" (server trả lời); timeout/000 mới là vấn đề mạng thật sự.

## Bước 4 — Báo cáo

Bảng ngắn: version aider trước → sau, env var nào đã set (chỉ tên, không giá trị), kết quả reachability check. Nhắc: worktree `delegate-deepseek` đang chạy dở (nếu có) không bị ảnh hưởng — Aider chỉ ảnh hưởng lần gọi kế tiếp.

## Xử lý sự cố

- `brew upgrade aider` fail dependency conflict → báo lỗi brew nguyên văn, không tự `brew reinstall`/`--force`.
- Muốn auto-upgrade định kỳ như các CLI khác (nếu có sẵn pattern trên máy) → có thể tạo agent mới theo cùng pattern (LaunchAgent trên macOS, cron/systemd timer trên Linux) — KHÔNG tự tạo trong command này, chỉ gợi ý, để user quyết.
- Reachability check trả `000`/timeout → có thể do IPv6 blackhole đã note trong `scripts/delegate/lib/sitecustomize.py` (wrapper aider tự ép AF_INET) — không phải lỗi cấu hình endpoint. Endpoint DeepSeek trực tiếp không có script check sẵn trong command này — nếu cần, tự curl HTTP status code, không in URL/token.
- Nghi ngờ model DeepSeek đổi tên/deprecated → không tự đổi `DEEPSEEK_MODEL` trong `.env`, báo user để họ quyết định giá trị mới.
