---
name: ace-notion-rbac
description: Tích hợp phân quyền Notion (`@acegalaxy/lib-notion-rbac`) vào project ACE Galaxy — cài lib theo tag, rbac.json tối thiểu chỉ cần prefix, env chuẩn, dựng bảng trong 1 page container Notion (dry-run → --apply), tuỳ chọn nối Login Center + trang admin. App không phải JS (Java, Go, Python…) → tự viết bản port access + verify ticket theo ngôn ngữ project. Dùng /ace-notion-rbac [prefix], hoặc khi user nói "thêm phân quyền", "tích hợp rbac", "notion rbac", "phân quyền cho app".
user-invocable: true
---

# /ace-notion-rbac — phân quyền Notion cho 1 phần mềm

Nguồn API duy nhất: `node_modules/@acegalaxy/lib-notion-rbac/README.md` (đọc sau khi cài). Skill chỉ giữ các bước, KHÔNG chép API vào đây.

## Các bước

0. **Ngôn ngữ app** — JS/TS (Node ≥ 20, Cloudflare Worker) → làm từ bước 1. Ngôn ngữ khác (Java, Kotlin, Go, Python…) → lib JS không nạp được, làm theo mục "App không phải JS" bên dưới.
1. **Cài lib** — tag mới nhất: `git ls-remote --tags git@github.com:acegalaxy-co/lib-notion-rbac.git | tail -1`. Khai `"@acegalaxy/lib-notion-rbac": "github:acegalaxy-co/lib-notion-rbac#vX.Y.Z"` (≥ v0.7.0), cài + kiểm lockfile theo skill `ace-library`.
2. **`rbac.json`** ở root app — tối thiểu `{ "prefix": "<Prefix>" }`. Prefix: tên project, chữ/số, bắt đầu bằng chữ, ≤ 12 ký tự; gợi ý từ tên folder, user sửa được. Mặc định lib: quyền `add`/`approve`/`remove`/`manage_roles`, role `basic` (Default)/`admin`/`owner`/`ban`. Chỉ khai `perms`/`roles` khi app cần khác (khai là THAY hẳn bộ mặc định). Mã quyền KHÔNG tiền tố app.
3. **Env** — thêm vào `.env.example` (tên + comment, không value): `NOTION_PAGE_RBAC_ID` (page container), `NOTION_TOKEN_RBAC` (token integration), `NOTION_DB_HR_ID` (DB HR dùng chung). Project đã có biến cùng mục đích tên khác → khai `containerEnv`/`tokenEnv`/`hrDbEnv` trong rbac.json trỏ biến đó, không tạo biến trùng. Value vào `.env` → viết sẵn lệnh idempotent cho user (skill `copy-data-cmd`), KHÔNG tự đọc/in token.
4. **Container** — user tạo 1 page Notion cho phần mềm (vd "Cloudflare IP Whitelist"), share cho integration của token, lấy id vào `NOTION_PAGE_RBAC_ID`.
5. **Dựng bảng** — dry-run, in plan cho user:
   ```bash
   node --env-file=.env node_modules/@acegalaxy/lib-notion-rbac/setup.js rbac.json
   ```
   User đồng ý → chạy lại thêm `--apply` (ghi Notion = outward, hỏi trước). Chạy lại an toàn.
6. **Code** (hỏi user cần phần nào): `createRbac` kiểm quyền (`access(email)`), `./login` (Login Center — đăng ký callback trong `ACE_LOGIN_APPS`), `./admin` (console gán role/guest/log). Theo README lib; mỗi phần ≥ 1 test happy + 1 test từ chối (không quyền / ban).
   - **App đã có login khác** (password, OAuth, magic link, SSO…) → GIỮ NGUYÊN, Login Center chỉ THÊM 1 lựa chọn (nút/route riêng). KHÔNG xoá/thay route, session, middleware, user store cũ; mọi cách login cùng ra session cũ của app. Test: login cũ vẫn chạy sau khi tích hợp.

## App không phải JS — tự viết bản port theo ngôn ngữ project

Không bọc Node sidecar, không gate bằng proxy khi app tự kiểm quyền được. Viết bản port tối thiểu ngay trong project:

1. **Tìm port sẵn cùng ngôn ngữ trước** — có thì copy + đổi prefix, KHÔNG viết lại. Port đã có:
   - Java: `ace_ace_matching-service` → `mm-director/src/main/java/co/acegalaxy/mm/director/security/` `NotionRbac.java` (access) + `AceLoginTicket.java` (verify ticket), test cùng tên `*Test.java`; Login Center chạy song song user/pass cũ.
2. **Clone lib đúng tag** làm nguồn sự thật (không cài vào project): `git clone --depth 1 --branch vX.Y.Z git@github.com:acegalaxy-co/lib-notion-rbac.git /tmp/lib-notion-rbac`. Đọc `README.md` (mục Permission rules), `index.js` (`access`), `login.js` (`verifyTicket`, cookie phiên).
3. **Chỉ port phần app dùng**, mặc định 2 phần:
   - `access(email)` → `{ found, kind, perms, banned }`: HR Working (mọi email trong `emailProps`) hoặc Guest Authen; Default role chỉ cho staff; Map Roles `Active` + `ExpiresAt` trống/còn hạn; Role/Permission `Active` tắt → không tính; `Ban` thắng hết. Đọc Notion mỗi request (chỉ cache id bảng), lỗi Notion → throw, caller từ chối (fail closed).
   - `verifyTicket` (nếu dùng Login Center): Ed25519 trên `p`, `v=1`, `iss=ace-login`, `aud=appId`, `exp > now`, `iat ≤ now+30s`, `kind ∈ staff|guest`, `sub` có `@`, `nonce` UUIDv4 chưa dùng (giữ ~2 phút). Phiên = cookie HMAC chứa email + hạn, KHÔNG nhét quyền vào cookie.
   - Console admin (`./admin`) KHÔNG port — sửa role/guest thẳng trên Notion. Cần UI thật → hỏi user trước.
4. **Dựng bảng vẫn bằng setup.js của lib** (bước 2–5 ở trên, chạy từ bản clone): `node --env-file=.env /tmp/lib-notion-rbac/setup.js rbac.json` → dry-run, user đồng ý → `--apply`.
5. **Test** — port lại các case trong `test/rbac.test.js` + `test/login-admin.test.js` của lib bằng test framework sẵn có của project, HTTP Notion fake (không gọi thật): staff Default có quyền, map Active cộng quyền, Ban → rỗng, người lạ/nghỉ việc → rỗng, map hết hạn bị bỏ, lỗi Notion → throw; ticket sai chữ ký / sai `aud` / hết hạn / replay → từ chối.
6. **Đầu file port** ghi comment: port từ `lib-notion-rbac vX.Y.Z`, phần nào port, phần nào bỏ. Lib bump tag đổi luật quyền → cập nhật port + test theo.

## Lưu ý

- Vault/secret: KHÔNG dùng MCP Notion ([[vault-no-mcp]]); token chỉ qua env.
- Quyền riêng từng phần mềm nằm ở container của phần mềm đó, không dồn sang IAM chung.
- Đổi quy ước bảng/role → sửa lib + bump tag, không vá trong project.
