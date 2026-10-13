---
name: web-browse
description: Duyệt web cho task thường (đọc trang, tra cứu, kiểm tra site public, điền form đơn giản) qua CloakBrowser MCP `cloak_@@PROFILE_SLUG@@_web` gắn profile prj_@@PROFILE_SLUG@@_sv_web. Dùng khi user gõ /web-browse [yêu cầu], hoặc task cần mở trình duyệt mà không cần profile đăng nhập của dịch vụ riêng.
user-invocable: true
context: fork
agent: browser-web
background: false
---

# /web-browse — Web task thường (CloakBrowser, profile `web`)

Thực hiện yêu cầu đi kèm `/web-browse [yêu cầu]`. Không có yêu cầu → hỏi user cần làm gì.

## Phạm vi

- Dùng cho: đọc/tra cứu trang, kiểm tra site public, đọc docs, thao tác form không nhạy cảm.
- KHÔNG dùng cho:
  - Chụp/xem UI local → `/ui-preview`.
  - Việc cần profile đã đăng nhập của dịch vụ khác → dùng browser agent riêng của dịch vụ đó (mỗi dịch vụ 1 profile).
- Chỉ cần đọc nội dung tĩnh, không cần JS/login → ưu tiên `WebFetch`/`WebSearch` (rẻ hơn), không mở browser.

## Registry

- MCP: `cloak_@@PROFILE_SLUG@@_web` (inline trong `.claude/agents/browser-web.md`). Không dùng MCP cloak của dịch vụ khác.
- Profile: `user_data_dir=@@REPO_DIR@@/.browser-profiles/prj_@@PROFILE_SLUG@@_sv_web` — absolute, KHÔNG `~` (hook `pre-browser-profile-gate.sh` chặn nếu thiếu/sai). Governance: [browser-mcp-profiles](../../rules/project/browser-mcp-profiles.md).
- Guard: `@@REPO_DIR@@/.gitignore` có dòng `/.browser-profiles/`; thiếu → thêm.
- Xong → cập nhật `last-used` dòng `prj_@@PROFILE_SLUG@@_sv_web` trong `.browser-profiles/_registry.md` (chưa có dòng/file → tạo theo header `| profile | project | service | created | last-used | note |`).

## Browser contract

1. `cloak_launch`: `user_data_dir=<profile trên>`, `humanize=true`. Mặc định `headless=true`; cần user nhìn/login tay → `headless=false`. Timezone/locale: theo yêu cầu task, không đặt mặc định.
2. `cloak_navigate` → đọc bằng `cloak_read_page`; tương tác: `cloak_snapshot` trước mỗi click/type, lấy ref mới sau DOM mutation. Screenshot chỉ khi snapshot không đủ (ảnh, layout, captcha).
3. Gặp login/2FA/captcha → dừng, nhờ user thao tác tay (`headless=false`); không tự nhập credential, không giải captcha.
4. Profile bị lock (`SingletonLock`/"already in use") → dừng, báo user đóng browser đang giữ; không kill process, không xoá lock.
5. Không in cookie/token/password ra chat; không `cloak_get_cookies` trừ khi user yêu cầu rõ (và redact giá trị).
6. Hành động outward-facing (submit form, đăng bài, gửi tin, thanh toán, xoá) → hỏi user confirm trước.
7. `cloak_close` khi xong hoặc dừng.

## Báo cáo

Trả kết quả ngắn gọn + URL nguồn (markdown link bấm được). Thao tác có thay đổi → nêu rõ đã làm gì, đã verify (reload + đọc lại) hay chưa.
