---
name: update-gemini
description: "Kiểm tra + cập nhật Google Gemini CLI (Homebrew/npm), check agent auto-upgrade còn sống. Dùng /update-gemini hoặc \"update gemini\"."
user-invocable: true
---

# update-gemini — kiểm tra + cập nhật Gemini CLI

## Bối cảnh (thường 1 bản cài, qua Homebrew)

| Bản | Path | Ai cập nhật |
|---|---|---|
| **Homebrew** (nếu đây là cách cài trên máy) | `$(command -v gemini)`, formula `gemini-cli` | Agent auto-upgrade định kỳ (nếu có) — `brew upgrade gemini-cli` |

Nếu có thêm bản npm-global (`@google/gemini-cli`) song song, kiểm tra Bước 1 sẽ phát hiện — khác `update-claude` chỉ khi máy không có bẫy 2-bản này.

**Bẫy khác, nghiêm trọng hơn:** formula `gemini-cli` trên homebrew-core có thể bị **deprecated** — không còn được upstream support, có ngày sẽ bị **disable** (xem ngày cụ thể ghi trong `brew info gemini-cli`, dòng Deprecated/Disabled), thay thế đề xuất là `brew install --cask antigravity-cli`. Ngoài ra bottled version của brew có thể **lag phía sau** bản thật trên npm registry (`@google/gemini-cli`) — brew không tự bắt kịp release cadence của Google. Luôn so cả 2 nguồn, không chỉ tin `brew upgrade` "already installed".

`delegate-gemini` (`scripts/delegate/run-gemini.sh`) dùng CLI này để chạy task read-only large-context — session `delegate-gemini` đang chạy vẫn dùng binary cũ cho tới khi được respawn sau khi upgrade.

## Bước 1 — Trạng thái hiện tại

```bash
echo "running : $(which gemini) → $(gemini --version 2>/dev/null)"
if command -v brew >/dev/null; then
  echo "brew    : $(brew info gemini-cli 2>/dev/null | head -1)"
else
  echo "brew không có — kiểm tra cách cài khác (npm/pipx/native)"
fi
echo "npm mới nhất: $(npm view @google/gemini-cli version 2>/dev/null)"
echo "agents  :"
case "$(uname)" in
  Darwin) launchctl list | grep -iE "brew-upgrade|gemini" || echo "  (không agent nào loaded)" ;;
  *) { crontab -l 2>/dev/null | grep -i gemini; systemctl --user list-timers 2>/dev/null | grep -i gemini; } || echo "  (không cron/timer nào cho gemini)" ;;
esac
```

So sánh version brew vs npm: khác nhau → brew đang lag, cân nhắc Bước 3.

## Bước 2 — Cập nhật bản brew, không chờ cron

```bash
command -v brew >/dev/null && brew upgrade gemini-cli 2>&1 | tail -n 10 || echo "brew không có — bỏ qua bước này"
echo "sau update: $(gemini --version)"
```

## Bước 3 — (tuỳ chọn) Nếu brew vẫn lag xa npm hoặc gần ngày disable

Xem ngày disable ghi trong `brew info gemini-cli` (dòng Deprecated/Disabled). Gần ngày đó hoặc brew lag xa npm: cân nhắc chuyển sang cài trực tiếp qua npm (`npm install -g @google/gemini-cli`) hoặc migrate sang `antigravity-cli` — đây là quyết định đổi install method, KHÔNG tự làm, chỉ đề xuất cho user quyết.

## Bước 4 — Báo cáo

Bảng ngắn: version brew trước → sau, version npm mới nhất, trạng thái agent auto-upgrade (loaded? log gần nhất lúc nào?), ngày formula bị disable (nếu `brew info` có ghi). Nhắc: session `gemini`/`delegate-gemini` đang mở vẫn chạy binary cũ — bản mới chỉ áp cho process mở sau.

## Xử lý sự cố

- Agent auto-upgrade không thấy trong listing → nếu có plist cũ, load lại: `launchctl load ~/Library/LaunchAgents/<label>.plist` (label lấy từ tên file thực tế, macOS only). Linux dùng `systemctl --user enable --now <timer>` hoặc thêm dòng crontab tương ứng.
- Log brew báo lỗi (không phải "already installed") → hiện lỗi cho user, KHÔNG tự sửa agent/plist.
- `brew upgrade gemini-cli` báo formula deprecated/disabled → đây là tín hiệu cần migrate (xem Bước 3), không phải lỗi tạm thời.
