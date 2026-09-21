---
name: browser-mcp-profiles
description: Cloak (antidetect browser) + Playwright qua MCP — mỗi service 1 profile prj_xx_sv_yy tách biệt tránh lock session; container tập trung ~/.browser-profiles; MCP đăng ký per-project. LAZY, load khi chạm .mcp.json / playwright / spec.
status: live
updated: 2026-09-21
paths:
  - ".mcp.json"
  - ".claude/rules/project/browser-mcp-profiles.md"
  - "**/*.spec.ts"
  - "**/playwright*"
metadata:
  type: reference
---

# Browser MCP — Profile isolation (Cloak + Playwright)

> **CONTAINER PATH (resolve TRƯỚC mọi thao tác profile):**
> Đọc env `BROWSER_PROFILES_DIR`; thiếu → fallback default **`~/.browser-profiles`**.
> Container = folder chứa các profile `prj_<xx>_sv_<yy>/`.
> **Path không tồn tại → STOP, hỏi user** container path thực. KHÔNG tự tạo path đoán, KHÔNG `mkdir` đại.

Governance dùng chung cho **Cloak** (antidetect browser) và **Playwright** qua MCP. Mục tiêu: profile tách biệt tránh lock session · quản lý tập trung 1 nơi · MCP gọn.

## GATE — BẮT BUỘC trước MỌI action Cloak/Playwright (P0)

MỌI thao tác chạm Cloak/Playwright (navigate, click, screenshot, launch, login, scrape, test...) PHẢI gắn với **đúng 1 profile hợp lệ** trong container. KHÔNG có ngoại lệ "chỉ mở nhanh xem thử".

Pre-flight bắt buộc — chạy đủ 4 bước theo thứ tự TRƯỚC khi gọi tool đầu tiên:

1. **Resolve container** (header trên). Không tồn tại → STOP hỏi user, KHÔNG `mkdir` đại.
2. **Xác định `(xx, yy)`** = (project, service) của action này. Không suy ra được từ context → STOP hỏi user, KHÔNG tự đặt tên bừa.
3. **Profile = `prj_<xx>_sv_<yy>`**, validate regex `^prj_[a-z0-9]+_sv_[a-z0-9]+$`. Đã có trong `_registry.md`/container → tái dùng. Chưa có → tạo dir + thêm dòng registry TRƯỚC khi dùng.
4. **Bind profile vào tool**: `--user-data-dir=<container>/prj_<xx>_sv_<yy>` (MCP entry có sẵn → dùng entry đó; chưa có → thêm entry theo snippet dưới). Xong action → cập nhật `last-used`.

**CẤM tuyệt đối** (mọi cái dưới = tạo profile lung tung, mất kiểm soát):

- ❌ Launch Cloak/Playwright **không** `--user-data-dir` (rơi vào default cache `~/Library/Caches/ms-playwright/...` — ngoài container, không track được).
- ❌ Tạo profile **ngoài** container hoặc tên **không** khớp regex.
- ❌ 1 profile cho >1 `(xx,yy)`, hoặc 1 action dùng profile của service khác "cho tiện".
- ❌ Tạo profile mới khi profile đúng `(xx,yy)` đã tồn tại (phải tái dùng).
- ❌ Dùng `--isolated` **không** `--storage-state` cho action cần giữ session (mất auth mỗi lần).
- ❌ Bỏ qua registry — mọi profile tạo/dùng PHẢI có dòng trong `_registry.md`.

Mâu thuẫn / không chắc `(xx,yy)` / container lạ → **STOP hỏi user**, KHÔNG tự đoán rồi tạo.

**Enforce cứng (hook):** `pre-browser-profile-gate.sh` (PreToolUse, matcher MCP browser tools + Bash) chặn `exit 2` khi: MCP server name không khớp `<pw|cloak>_<xx>_<yy>` (server generic `playwright`/`cloak` → block), hoặc Bash launch `@playwright/mcp`/cloak thiếu `--user-data-dir=.../prj_<xx>_sv_<yy>`. Off-switch: `HARNESS_DELEGATE=0`. Hook chỉ chặn được cái đi qua MCP tool / Bash — còn lại vẫn tự giác theo GATE trên.

## Naming — `prj_<xx>_sv_<yy>`

- Regex hợp lệ: `^prj_[a-z0-9]+_sv_[a-z0-9]+$` (lowercase, no space, no ký tự thừa). `xx`=tên project, `yy`=tên service.
- Mỗi profile = 1 dir con: `$BROWSER_PROFILES_DIR/prj_<xx>_sv_<yy>/`.
- Ví dụ: `prj_myapp_sv_auth`, `prj_shop_sv_checkout`.
- Tên sai regex → sửa trước khi tạo, KHÔNG tạo dir rác.

## Profile isolation (mục tiêu #1)

- 1 profile = 1 `user-data-dir` riêng → cookie / session / fingerprint tách hẳn giữa service.
- **Single-writer lock**: mỗi profile CHỈ 1 browser process tại 1 thời điểm. Chromium/Cloak lock `user-data-dir`; mở trùng → session corrupt / crash. Đóng session cũ TRƯỚC khi tái dùng profile.
- **Parallel subagent** (orchestrator fan-out) → mỗi task 1 profile riêng, KHÔNG share. Khớp worktree-isolation [[git-workflow]]. Nghi 2 task đụng cùng profile → tách profile hoặc serialize.

## Cloak vs Playwright — dùng cái nào

| Tool | Khi nào | Không dùng cho |
|---|---|---|
| **Cloak** | Session thật cần antidetect / fingerprint bền: login site nhạy fingerprint, giữ session lâu | E2E test xác định |
| **Playwright** | Automation / E2E test xác định, không cần antidetect | Session người-thật nhạy fingerprint |

Cả hai trỏ **CÙNG container + CÙNG naming** → quản lý 1 nơi.

## MCP registration — per-project (KHÔNG global)

Đăng ký trong `.mcp.json` của repo cần browser, KHÔNG global. Lý do: scope security hẹp theo repo + tiết kiệm token (chỉ repo browser mới nạp tool defs, repo khác không gánh).

> **Profile bake lúc launch, KHÔNG chọn per tool-call.** Playwright MCP cố định `user-data-dir` per server instance (flag `--user-data-dir`, hoặc env `PLAYWRIGHT_MCP_USER_DATA_DIR`). Nó **không đọc** `BROWSER_PROFILES_DIR` — env này chỉ là convention để build path. Antidetect browser (Cloak) cũng bind profile lúc mở. → **1 profile = 1 server entry**. "Tập trung" đạt qua 1 file config + N entry + 1 container, KHÔNG phải 1 server switch profile.

Snippet mẫu — mỗi service 1 entry (server key = `pw|cloak _ <xx> _ <yy>`), `user-data-dir` bake lúc launch. `.mcp.json` là **strict JSON — KHÔNG comment**; copy nguyên rồi điền `<cloak-mcp-cmd>` + path tuyệt đối:

```json
{
  "mcpServers": {
    "pw_myapp_auth": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp",
               "--user-data-dir=/Users/you/.browser-profiles/prj_myapp_sv_auth"]
    },
    "cloak_myapp_auth": {
      "command": "<cloak-mcp-cmd>",
      "args": ["--user-data-dir=/Users/you/.browser-profiles/prj_myapp_sv_auth"]
    }
  }
}
```

- `.mcp.json` **không expand** `${HOME}`/`$BROWSER_PROFILES_DIR` — dùng **path tuyệt đối** (`/Users/you/...`). Env `BROWSER_PROFILES_DIR` chỉ để người/script build path, không phải để MCP đọc.
- **Ephemeral + auth replay (nhẹ hơn persistent):** Playwright `--isolated --storage-state=<container>/prj_xx_sv_yy/state.json` — không giữ profile trên disk, chỉ nạp cookie/localStorage. Dùng khi không cần fingerprint bền.
- KHÔNG nhét >1 profile vào 1 entry (không switch per-call được).

## Registry — quản lý tập trung (mục tiêu #2/#3)

`$BROWSER_PROFILES_DIR/_registry.md` — 1 bảng nguồn-sự-thật:

```text
| profile              | project  | service | created    | last-used  | note |
|----------------------|----------|---------|------------|------------|------|
| prj_myapp_sv_auth    | myapp    | auth    | 2026-09-21 | 2026-09-21 |      |
```

Tạo / dùng profile → cập nhật dòng (nhất là `last-used`). Không có registry → task đầu tiên tạo file.

## Secret guard

- Profile dir chứa cookie / session / auth token → **coi là secret**. KHÔNG `cat`/print nội dung profile ra chat. KHÔNG commit.
- Container ngoài repo (`~/.browser-profiles`) nên không dính git. Nếu ai đặt profile trong repo → BẮT BUỘC gitignore.
- Tie [[secrets-no-printout]], [[vault-no-mcp]].

## Cleanup / TTL

- Profile `last-used` cũ > 30 ngày → candidate dọn. Liệt kê + confirm user TRƯỚC khi xoá (destructive). KHÔNG auto-`rm`.
- Xoá profile → xoá luôn dòng trong `_registry.md`.

## Tránh

- ❌ 2 process cùng 1 profile (lock corrupt).
- ❌ Dùng chung 1 profile cho nhiều service (mục tiêu isolation vỡ).
- ❌ Đăng ký browser MCP global (mọi project gánh tool defs).
- ❌ Commit profile dir / print cookie.
- ❌ Tự tạo container path khi không tồn tại — phải hỏi user.
