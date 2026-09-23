---
name: update-codex
description: Kiểm tra + cập nhật OpenAI Codex CLI lên bản mới nhất trên macOS — so version binary đang chạy (Homebrew Cask) với bản mới nhất, chạy `brew upgrade codex` nếu cũ, và kiểm tra LaunchAgent auto-upgrade hàng giờ còn sống. Chạy /update-codex, hoặc khi user hỏi "codex đã cập nhật chưa", "update codex", "cron cập nhật codex".
user-invocable: true
---

# update-codex — kiểm tra + cập nhật OpenAI Codex CLI

## Bối cảnh (chỉ 1 bản cài trên máy này)

| Bản | Path | Ai cập nhật |
|---|---|---|
| **Homebrew Cask** (bản duy nhất trên PATH) | `/opt/homebrew/bin/codex` → symlink vào `/opt/homebrew/Caskroom/codex/<version>/bin/codex` | LaunchAgent `com.user.brew-upgrade-codex` — `brew upgrade codex` mỗi 3600s + lúc login, log `/tmp/brew-upgrade-codex.log` |

Không có bản npm-global (`@openai/codex`) hay standalone nào khác trên máy — kiểm tra vẫn nên chạy đủ để phát hiện nếu có bản thứ 2 xuất hiện sau này (npm global thường che PATH trước brew).

`codex` có subcommand `codex update` riêng (tự tải bản mới), nhưng bản cài trên máy là **Homebrew Cask** — dùng `brew upgrade codex` làm cách chính để path/version khớp với cơ chế cask (symlink Caskroom). Không trộn 2 cơ chế update trên cùng 1 install.

Cùng pattern còn có `com.user.brew-upgrade-claude-code` và `com.user.brew-upgrade-gemini-cli`. Xem `/update-claude` cho Claude Code.

**Lưu ý delegate wrapper:** `scripts/delegate/` (persona `delegate-codex`) gọi thẳng binary `codex` trên PATH. Sau khi upgrade, chỉ session/process CLI mới spawn sau đó mới dùng bản mới — wrapper process đang chạy dở vẫn giữ binary cũ trong bộ nhớ.

## Bước 1 — Trạng thái hiện tại

```bash
echo "running : $(which codex) → $(codex --version 2>/dev/null)"
echo "cask    : $(/opt/homebrew/bin/brew info --cask codex 2>/dev/null | head -1)"
echo "agents  :"; launchctl list | grep -E "brew-upgrade" || echo "  (không agent nào loaded!)"
stat -f "brew log sửa lần cuối: %Sm" /tmp/brew-upgrade-codex.log 2>/dev/null
tail -n 2 /tmp/brew-upgrade-codex.log 2>/dev/null
echo "npm-global (nên rỗng): $(npm ls -g --depth=0 2>/dev/null | grep -i codex)"
```

## Bước 2 — Cập nhật (brew cask)

```bash
/opt/homebrew/bin/brew upgrade codex 2>&1 | tail -n 10
echo "sau update: $(codex --version)"
```

## Bước 3 — (tuỳ chọn) Nếu cần bản mới hơn brew-cask đã publish

`brew upgrade codex` phụ thuộc cask đã cập nhật lên homebrew-cask repo — có thể trễ vài giờ so với release GitHub. Cần bản mới nhất ngay:

```bash
codex update 2>&1 | tail -n 10
echo "sau codex update: $(codex --version)"
```

Cảnh báo: `codex update` có thể ghi binary ra ngoài path quản lý bởi brew (ví dụ `~/.local/bin` hoặc tương tự) — sau khi dùng cách này, chạy lại Bước 1 để xác nhận `which codex` vẫn trỏ đúng chỗ mong muốn, tránh 2 bản song song.

## Bước 4 — Báo cáo

Bảng ngắn: version trước → sau, cask version, trạng thái LaunchAgent (loaded? log gần nhất lúc nào?). Nhắc: session/wrapper `delegate-codex` đang chạy vẫn dùng binary cũ cho tới lần spawn tiếp theo.

## Xử lý sự cố

- Agent không có trong `launchctl list` → load lại: `launchctl load ~/Library/LaunchAgents/com.user.brew-upgrade-codex.plist`
- Log brew báo lỗi (không phải "already installed") → hiện lỗi cho user, KHÔNG tự sửa plist.
- `brew upgrade codex` fail → báo lỗi ngắn gọn (bản chất + nguồn), không dán log dài.
- Thấy cả brew cask lẫn npm-global cùng có codex → cảnh báo user có 2 bản, `which -a codex` để xác định bản nào thắng PATH trước khi update.
