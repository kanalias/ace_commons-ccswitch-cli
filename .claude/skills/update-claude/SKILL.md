---
name: update-claude
description: Kiểm tra + cập nhật Claude Code CLI lên bản mới nhất trên macOS — so version bản đang chạy (native ~/.local/bin) với bản Homebrew, chạy `claude update` nếu cũ, và kiểm tra LaunchAgent auto-upgrade hàng giờ còn sống. Chạy /update-claude, hoặc khi user hỏi "claude đã cập nhật chưa", "update claude", "cron cập nhật claude".
user-invocable: true
---

# update-claude — kiểm tra + cập nhật Claude Code CLI

## Bối cảnh (máy này có 2 bản cài song song)

| Bản | Path | Ai cập nhật |
|---|---|---|
| **Native** (bản `claude` thực sự chạy trên PATH) | `~/.local/bin/claude` | `claude update` (tự update theo cơ chế riêng, KHÔNG do cron) |
| **Homebrew** | `/opt/homebrew` (formula `claude-code`) | LaunchAgent `com.user.brew-upgrade-claude-code` — `brew upgrade claude-code` mỗi 3600s + lúc login, log `/tmp/brew-upgrade-claude-code.log` |

Bẫy: cron brew chỉ lo bản brew. Bản native đang chạy có thể cũ hơn dù brew báo "already installed". Luôn check cả 2.

Cùng pattern còn có `com.user.brew-upgrade-codex` và `com.user.brew-upgrade-gemini-cli` (cho Codex/Gemini CLI).

## Bước 1 — Trạng thái hiện tại

```bash
echo "running : $(which claude) → $(claude --version 2>/dev/null)"
echo "brew    : $(/opt/homebrew/bin/brew info claude-code 2>/dev/null | head -1)"
echo "agents  :"; launchctl list | grep -E "brew-upgrade|claude-ctxbar" || echo "  (không agent nào loaded!)"
stat -f "brew log sửa lần cuối: %Sm" /tmp/brew-upgrade-claude-code.log 2>/dev/null
tail -n 2 /tmp/brew-upgrade-claude-code.log 2>/dev/null
```

## Bước 2 — Cập nhật bản native (bản đang chạy)

```bash
~/.local/bin/claude update 2>&1 | tail -n 10
echo "sau update: $(~/.local/bin/claude --version)"
```

Warning "Multiple installations found (npm-global + native cùng path)" là bình thường — không phải lỗi.

## Bước 3 — (tuỳ chọn) Ép brew upgrade ngay, không chờ cron

```bash
/opt/homebrew/bin/brew upgrade claude-code 2>&1 | tail -n 5
```

## Bước 4 — Báo cáo

Bảng ngắn: bản native trước → sau, bản brew, trạng thái LaunchAgent (loaded? log gần nhất lúc nào?). Nhắc: session `claude` đang mở vẫn chạy binary cũ — bản mới chỉ áp cho session mở sau.

## Xử lý sự cố

- Agent không có trong `launchctl list` → load lại: `launchctl load ~/Library/LaunchAgents/com.user.brew-upgrade-claude-code.plist`
- Log brew báo lỗi (không phải "already installed") → hiện lỗi cho user, KHÔNG tự sửa plist.
- `claude update` fail → báo lỗi ngắn gọn (bản chất + nguồn), không dán log dài.
