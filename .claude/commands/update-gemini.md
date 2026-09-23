---
name: update-gemini
description: Kiểm tra + cập nhật Google Gemini CLI trên macOS — so version brew (`/opt/homebrew`, formula `gemini-cli`) đang chạy trên PATH với bản mới nhất trên npm registry, chạy `brew upgrade gemini-cli` nếu cũ, và kiểm tra LaunchAgent auto-upgrade hàng giờ còn sống. Chạy /update-gemini, hoặc khi user hỏi "gemini đã cập nhật chưa", "update gemini", "cron cập nhật gemini cli".
user-invocable: true
---

# update-gemini — kiểm tra + cập nhật Gemini CLI

## Bối cảnh (chỉ 1 bản cài, qua Homebrew)

| Bản | Path | Ai cập nhật |
|---|---|---|
| **Homebrew** (bản `gemini` thực sự chạy trên PATH) | `/opt/homebrew/bin/gemini` (formula `gemini-cli`) | LaunchAgent `com.user.brew-upgrade-gemini-cli` — `brew upgrade gemini-cli` mỗi 3600s + lúc login, log `/tmp/brew-upgrade-gemini-cli.log` |

Không có bản npm-global song song trên máy này (`npm ls -g` không thấy `@google/gemini-cli`) — khác `update-claude` (không có bẫy 2-bản).

**Bẫy khác, nghiêm trọng hơn:** formula `gemini-cli` trên homebrew-core đã bị **deprecated** — không còn được upstream support, sẽ bị **disable ngày 2026-12-18**, thay thế đề xuất là `brew install --cask antigravity-cli`. Ngoài ra bottled version của brew (`0.46.0` tại thời điểm viết) có thể **lag phía sau** bản thật trên npm registry (`@google/gemini-cli`, có thể đã lên `0.60.0`+) — brew không tự bắt kịp release cadence của Google. Luôn so cả 2 nguồn, không chỉ tin `brew upgrade` "already installed".

`delegate-gemini` (`scripts/delegate/run-gemini.sh`) dùng CLI này để chạy task read-only large-context — session `delegate-gemini` đang chạy vẫn dùng binary cũ cho tới khi được respawn sau khi upgrade.

## Bước 1 — Trạng thái hiện tại

```bash
echo "running : $(which gemini) → $(gemini --version 2>/dev/null)"
echo "brew    : $(/opt/homebrew/bin/brew info gemini-cli 2>/dev/null | head -1)"
echo "npm mới nhất: $(npm view @google/gemini-cli version 2>/dev/null)"
echo "agents  :"; launchctl list | grep -E "brew-upgrade" || echo "  (không agent nào loaded!)"
stat -f "brew log sửa lần cuối: %Sm" /tmp/brew-upgrade-gemini-cli.log 2>/dev/null
tail -n 2 /tmp/brew-upgrade-gemini-cli.log 2>/dev/null
```

So sánh version brew vs npm: khác nhau → brew đang lag, cân nhắc Bước 3.

## Bước 2 — Cập nhật bản brew, không chờ cron

```bash
/opt/homebrew/bin/brew upgrade gemini-cli 2>&1 | tail -n 10
echo "sau update: $(gemini --version)"
```

## Bước 3 — (tuỳ chọn) Nếu brew vẫn lag xa npm hoặc gần ngày disable (2026-12-18)

Cân nhắc chuyển sang cài trực tiếp qua npm (`npm install -g @google/gemini-cli`) hoặc migrate sang `antigravity-cli` — đây là quyết định đổi install method, KHÔNG tự làm, chỉ đề xuất cho user quyết.

## Bước 4 — Báo cáo

Bảng ngắn: version brew trước → sau, version npm mới nhất, trạng thái LaunchAgent (loaded? log gần nhất lúc nào?), còn bao lâu tới ngày formula bị disable. Nhắc: session `gemini`/`delegate-gemini` đang mở vẫn chạy binary cũ — bản mới chỉ áp cho process mở sau.

## Xử lý sự cố

- Agent không có trong `launchctl list` → load lại: `launchctl load ~/Library/LaunchAgents/com.user.brew-upgrade-gemini-cli.plist`
- Log brew báo lỗi (không phải "already installed") → hiện lỗi cho user, KHÔNG tự sửa plist.
- `brew upgrade gemini-cli` báo formula deprecated/disabled → đây là tín hiệu cần migrate (xem Bước 3), không phải lỗi tạm thời.
