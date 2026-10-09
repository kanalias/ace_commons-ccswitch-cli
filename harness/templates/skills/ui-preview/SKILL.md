---
name: ui-preview
description: Xem trước layout web local sau khi sửa UI — tự tìm dev server (package.json), mở qua Playwright MCP per-project `pw_<slug>_uipreview`, chụp mobile 420px + desktop 1280px, trả ảnh. Lần đầu tự setup MCP entry + profile. Dùng /ui-preview [path|url] [selector], hoặc khi user nói "xem thử layout", "preview UI", "chụp màn hình giao diện".
user-invocable: true
model: sonnet
---

# /ui-preview — Xem trước layout web (local)

Arg: `[path|url]` (mặc định `/`) + `[selector]` tuỳ chọn để scroll tới vùng vừa sửa.

Ký hiệu: `<repo>` = root checkout chính (worktree → `git rev-parse --path-format=absolute --git-common-dir` bỏ `/.git`); `<s>` = tên folder `<repo>` lowercase, bỏ mọi ký tự ngoài `[a-z0-9]` (vd `bds-hue` → `bdshue`).

## Các bước

1. **Setup lần đầu** — chỉ khi chưa có tool `mcp__pw_<s>_uipreview__*`:
   - `<repo>/.gitignore` + `.dockerignore` (nếu có) phải có dòng `/.browser-profiles/`; thiếu → thêm.
   - `mkdir -p <repo>/.browser-profiles/prj_<s>_sv_uipreview` + thêm dòng `prj_<s>_sv_uipreview | <s> | uipreview | <today> | <today> | /ui-preview` vào `<repo>/.browser-profiles/_registry.md` (chưa có file → tạo header bảng `profile | project | service | created | last-used | note`).
   - Chạy (`-s project` ghi `<repo>/.mcp.json`, path tuyệt đối vì `.mcp.json` không expand env):
     ```bash
     claude mcp add -s project pw_<s>_uipreview -- npx -y @playwright/mcp@latest --headless --user-data-dir=<repo>/.browser-profiles/prj_<s>_sv_uipreview
     ```
   - STOP, báo user: restart session (hoặc `/mcp` reconnect) rồi gọi lại `/ui-preview`. MCP chỉ nạp lúc khởi động session.
2. **Dev server** — arg là URL đầy đủ → dùng luôn, bỏ bước này. Không thì tìm port:
   - `package.json` (root hoặc `apps/*`, `src/apps/*`) script `dev` có `-p N` / `--port N` / `PORT=N` → dùng N; không có → mặc định framework (Next/Nuxt 3000, Vite 5173, Astro 4321, CRA 3000).
   - `curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>/` → 2xx/3xx dùng luôn. Không chạy → start script `dev` đó bằng Bash `run_in_background`, poll tới khi lên (tối đa ~60s). KHÔNG kill server đang chạy. Không xác định được port/script → hỏi user.
3. **Chụp mobile**: `browser_resize` 420×900 → `browser_navigate` `http://localhost:<port><path>` → có selector thì `browser_evaluate` `() => document.querySelector('<selector>')?.scrollIntoView({block:'center'})` → `browser_take_screenshot` `filename=/tmp/ui-preview-mobile.png` → `Read` ảnh.
4. **Chụp desktop**: `browser_resize` 1280×900, lặp bước 3 với `/tmp/ui-preview-desktop.png`. Bỏ nếu user chỉ cần mobile.
5. `browser_close`; cập nhật `last-used` dòng `prj_<s>_sv_uipreview` trong `_registry.md`.

## Báo cáo

Ngắn: URL đã mở dạng markdown link bấm được (không bọc backtick), 2 đường dẫn ảnh dạng link, nhận xét layout (lệch so với mockup/ảnh user đưa nếu có). Không tự sửa code trừ khi user yêu cầu.
