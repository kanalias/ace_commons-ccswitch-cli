---
name: update-codex
description: "Kiểm tra + cập nhật OpenAI Codex CLI lên bản mới nhất (Homebrew/npm), check agent auto-upgrade còn sống. Dùng /update-codex hoặc \"update codex\"."
user-invocable: true
---

# update-codex — kiểm tra + cập nhật OpenAI Codex CLI

## Bối cảnh (thường 1 bản cài, qua Homebrew Cask)

| Bản | Path | Ai cập nhật |
|---|---|---|
| **Homebrew Cask** (nếu đây là cách cài trên máy) | `$(command -v codex)` → symlink vào `$(brew --prefix)/Caskroom/codex/<version>/bin/codex` | Agent auto-upgrade định kỳ (nếu có) — `brew upgrade codex` |

Nếu có thêm bản npm-global (`@openai/codex`) hay standalone khác trên máy, kiểm tra Bước 1 sẽ phát hiện (npm global thường che PATH trước brew).

`codex` có subcommand `codex update` riêng (tự tải bản mới), nhưng nếu bản cài trên máy là **Homebrew Cask** thì dùng `brew upgrade codex` làm cách chính để path/version khớp với cơ chế cask (symlink Caskroom). Không trộn 2 cơ chế update trên cùng 1 install.

Cùng pattern (nếu máy có cấu hình tương tự) còn áp dụng cho Claude Code/Gemini CLI — xem `/update-claude`.

**Lưu ý delegate wrapper:** `scripts/delegate/` (persona `delegate-codex`) gọi thẳng binary `codex` trên PATH. Sau khi upgrade, chỉ session/process CLI mới spawn sau đó mới dùng bản mới — wrapper process đang chạy dở vẫn giữ binary cũ trong bộ nhớ.

## Bước 1 — Trạng thái hiện tại

```bash
echo "running : $(which codex) → $(codex --version 2>/dev/null)"
if command -v brew >/dev/null; then
  echo "cask    : $(brew info --cask codex 2>/dev/null | head -1)"
else
  echo "brew không có — kiểm tra cách cài khác (npm/pipx/native)"
fi
echo "agents  :"
case "$(uname)" in
  Darwin) launchctl list | grep -iE "brew-upgrade|codex" || echo "  (không agent nào loaded)" ;;
  *) { crontab -l 2>/dev/null | grep -i codex; systemctl --user list-timers 2>/dev/null | grep -i codex; } || echo "  (không cron/timer nào cho codex)" ;;
esac
echo "npm-global (nên rỗng nếu chỉ dùng cask): $(npm ls -g --depth=0 2>/dev/null | grep -i codex)"
```

## Bước 2 — Cập nhật (brew cask)

```bash
command -v brew >/dev/null && brew upgrade codex 2>&1 | tail -n 10 || echo "brew không có — bỏ qua bước này"
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

Bảng ngắn: version trước → sau, cask version, trạng thái agent auto-upgrade (loaded? log gần nhất lúc nào?). Nhắc: session/wrapper `delegate-codex` đang chạy vẫn dùng binary cũ cho tới lần spawn tiếp theo.

## Xử lý sự cố

- Agent auto-upgrade không thấy trong listing → nếu có plist cũ, load lại: `launchctl load ~/Library/LaunchAgents/<label>.plist` (label lấy từ tên file thực tế, macOS only). Linux dùng `systemctl --user enable --now <timer>` hoặc thêm dòng crontab tương ứng.
- Log brew báo lỗi (không phải "already installed") → hiện lỗi cho user, KHÔNG tự sửa agent/plist.
- `brew upgrade codex` fail → báo lỗi ngắn gọn (bản chất + nguồn), không dán log dài.
- Thấy cả brew cask lẫn npm-global cùng có codex → cảnh báo user có 2 bản, `which -a codex` để xác định bản nào thắng PATH trước khi update.
