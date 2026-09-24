---
name: update-claude
description: "Kiểm tra + cập nhật Claude Code CLI lên bản mới nhất (Homebrew/npm/native), check agent auto-upgrade còn sống. Dùng /update-claude hoặc \"update claude\"."
user-invocable: true
---

# update-claude — kiểm tra + cập nhật Claude Code CLI

## Bối cảnh (có thể có 2 bản cài song song)

| Bản | Path | Ai cập nhật |
|---|---|---|
| **Native** (bản `claude` thực sự chạy trên PATH) | `~/.local/bin/claude` | `claude update` (tự update theo cơ chế riêng, KHÔNG do cron) |
| **Homebrew** (nếu cài qua brew) | prefix Homebrew (`brew --prefix`), formula `claude-code` | Agent auto-upgrade định kỳ (nếu có) — `brew upgrade claude-code` |

Bẫy: agent auto-upgrade (nếu có) chỉ lo bản brew. Bản native đang chạy có thể cũ hơn dù brew báo "already installed". Luôn check cả 2.

Cùng pattern (nếu máy có cấu hình tương tự) còn áp dụng cho Codex/Gemini CLI — xem `/update-codex`, `/update-gemini`.

## Bước 1 — Trạng thái hiện tại

```bash
echo "running : $(which claude) → $(claude --version 2>/dev/null)"
if command -v brew >/dev/null; then
  echo "brew    : $(brew info claude-code 2>/dev/null | head -1)"
else
  echo "brew không có — kiểm tra cách cài khác (npm/pipx/native)"
fi
echo "agents  :"
case "$(uname)" in
  Darwin) launchctl list | grep -iE "brew-upgrade|claude" || echo "  (không agent nào loaded)" ;;
  *) { crontab -l 2>/dev/null | grep -i claude; systemctl --user list-timers 2>/dev/null | grep -i claude; } || echo "  (không cron/timer nào cho claude)" ;;
esac
```

Nếu tìm thấy agent/timer ở trên, lấy log gần nhất qua tên/label thực tế vừa liệt kê (vd `tail -n 2` trên log path plist khai báo `StandardOutPath`, hoặc `journalctl --user -u <timer>` trên Linux).

## Bước 2 — Cập nhật bản native (bản đang chạy)

```bash
~/.local/bin/claude update 2>&1 | tail -n 10
echo "sau update: $(~/.local/bin/claude --version)"
```

Warning "Multiple installations found (npm-global + native cùng path)" là bình thường — không phải lỗi.

## Bước 3 — (tuỳ chọn) Ép brew upgrade ngay, không chờ cron

```bash
command -v brew >/dev/null && brew upgrade claude-code 2>&1 | tail -n 5 || echo "brew không có — bỏ qua bước này"
```

## Bước 4 — Báo cáo

Bảng ngắn: bản native trước → sau, bản brew (nếu có), trạng thái agent auto-upgrade (loaded? log gần nhất lúc nào?). Nhắc: session `claude` đang mở vẫn chạy binary cũ — bản mới chỉ áp cho session mở sau.

## Xử lý sự cố

- Agent auto-upgrade không thấy trong listing → nếu có plist cũ, load lại: `launchctl load ~/Library/LaunchAgents/<label>.plist` (label lấy từ tên file thực tế trong thư mục đó, macOS only). Linux dùng `systemctl --user enable --now <timer>` hoặc thêm dòng crontab tương ứng.
- Log brew báo lỗi (không phải "already installed") → hiện lỗi cho user, KHÔNG tự sửa agent/plist.
- `claude update` fail → báo lỗi ngắn gọn (bản chất + nguồn), không dán log dài.
