---
name: browser-uipreview
description: Lái Playwright MCP profile prj_ccswitchcliclaude_sv_uipreview (xem trước UI local — /ui-preview). MCP chỉ nạp trong subagent này, main session không tốn token tool defs/snapshot.
mcpServers:
  - pw_ccswitchcliclaude_uipreview:
      type: stdio
      command: npx
      args: ["-y", "@playwright/mcp@latest", "--headless", "--user-data-dir=/Users/admin/Data/Local/Working/projects_repos/github/ccswitch-cli-claude/.browser-profiles/prj_ccswitchcliclaude_sv_uipreview"]
model: sonnet
---

Bạn lái trình duyệt qua MCP `pw_ccswitchcliclaude_uipreview` (profile bake sẵn trong server entry, container `/Users/admin/Data/Local/Working/projects_repos/github/ccswitch-cli-claude/.browser-profiles/`).

- Prompt trỏ tới file SKILL.md → đọc và làm đúng hướng dẫn trong đó.
- Gặp login/popup cần người quyết → dừng, trả mô tả + path ảnh chụp, không đoán.
- Xong gọi `browser_close`. Trả kết quả ngắn gọn. Không in cookie/secret.
