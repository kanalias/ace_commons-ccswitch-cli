---
name: browser-mcp-profiles
description: Cloak (antidetect browser) + Playwright qua MCP — mỗi service 1 profile prj_xx_sv_yy tách biệt tránh lock session; container resolve env → <repo>/.browser-profiles; MCP đăng ký per-project. LAZY, load khi chạm .mcp.json / playwright / spec.
status: live
updated: 2026-09-23
paths:
  - ".mcp.json"
  - ".claude/rules/project/browser-mcp-profiles.md"
  - "**/*.spec.ts"
  - "**/playwright*"
metadata:
  type: reference
---

# Browser MCP — Profile isolation (Cloak + Playwright)

> **CONTAINER PATH (resolve TRƯỚC mọi thao tác profile) — chain 2 bước, dừng ở bước đầu tiên khớp:**
>
> 1. env `BROWSER_PROFILES_DIR` có giá trị → dùng path tuyệt đối đó (thắng tất cả; dùng cho Docker/CI khi cần override).
> 2. Không có override → dùng `<repo>/.browser-profiles/`, với `<repo>` là root checkout chính kể cả khi đang ở worktree.
>
> Container = folder chứa các profile `prj_<xx>_sv_<yy>/`. Trước mọi `mkdir`, cả `<repo>/.gitignore` và `<repo>/.dockerignore` PHẢI có dòng `/.browser-profiles/`; thiếu guard và không được phép sửa → STOP hỏi user.

Governance dùng chung cho **Cloak** (antidetect browser) và **Playwright** qua MCP. Mục tiêu: profile tách biệt tránh lock session · quản lý tập trung 1 nơi · MCP gọn.

## GATE — BẮT BUỘC trước MỌI action Cloak/Playwright (P0)

MỌI thao tác chạm Cloak/Playwright (navigate, click, screenshot, launch, login, scrape, test...) PHẢI gắn với **đúng 1 profile hợp lệ** trong container. KHÔNG có ngoại lệ "chỉ mở nhanh xem thử".

Pre-flight bắt buộc — chạy đủ 5 bước theo thứ tự TRƯỚC khi gọi tool đầu tiên:

1. **Resolve container** theo chain trên. Trong worktree vẫn resolve `<repo>` về root checkout chính, không phải root worktree.
2. **Guard trước khi tạo.** Xác nhận cả `<repo>/.gitignore` và `<repo>/.dockerignore` có `/.browser-profiles/` trước BẤT KỲ `mkdir` nào; thiếu → thêm trước hoặc STOP hỏi user.
3. **Xác định `(xx, yy)`** = (project, service) của action này. Không suy ra được từ context → STOP hỏi user, KHÔNG tự đặt tên bừa.
4. **Profile = `prj_<xx>_sv_<yy>`**, validate regex `^prj_[a-z0-9]+_sv_[a-z0-9]+$`. Đã có trong `_registry.md`/container → tái dùng. Chưa có → sau guard bước 2 mới tạo dir + thêm dòng registry TRƯỚC khi dùng.
5. **Bind profile vào tool**: `--user-data-dir=<container>/prj_<xx>_sv_<yy>` (MCP entry có sẵn → dùng entry đó; chưa có → thêm entry theo snippet dưới). Xong action → cập nhật `last-used`.

**Cảnh báo:** `git clean -xfd` xoá cả file ignored, gồm `<repo>/.browser-profiles/`. Preview bằng `git clean -ndx` và exclude container, hoặc backup có chủ đích trước khi cleanup.

**CẤM tuyệt đối** (mọi cái dưới = tạo profile lung tung, mất kiểm soát):

- ❌ Launch Cloak/Playwright **không** `--user-data-dir` (rơi vào default cache ngoài container, không track được).
- ❌ Tạo profile **ngoài** container hoặc tên **không** khớp regex.
- ❌ 1 profile cho >1 `(xx,yy)`, hoặc 1 action dùng profile của service khác "cho tiện".
- ❌ Tạo profile mới khi profile đúng `(xx,yy)` đã tồn tại (phải tái dùng).
- ❌ Dùng `--isolated` **không** `--storage-state` cho action cần giữ session (mất auth mỗi lần).
- ❌ Bỏ qua registry — mọi profile tạo/dùng PHẢI có dòng trong `_registry.md`.

Mâu thuẫn / không chắc `(xx,yy)` / container lạ → **STOP hỏi user**, KHÔNG tự đoán rồi tạo.

**Enforce cứng (hook):** `pre-browser-profile-gate.sh` (PreToolUse, matcher MCP browser tools + Bash) chặn `exit 2` khi: MCP server name không khớp `<pw|cloak>_<xx>_<yy>` (server generic `playwright`/`cloak` → block), hoặc Bash launch `@playwright/mcp`/cloak thiếu `--user-data-dir=.../prj_<xx>_sv_<yy>`. Off-switch: `HARNESS_DELEGATE=0`. Hook chỉ chặn được cái đi qua MCP tool / Bash — còn lại vẫn tự giác theo GATE trên.

## Naming — `prj_<xx>_sv_<yy>`

- Regex hợp lệ: `^prj_[a-z0-9]+_sv_[a-z0-9]+$` (lowercase, no space, no ký tự thừa). `xx`=tên project, `yy`=tên service.
- Mỗi profile = 1 dir con: `<container>/prj_<xx>_sv_<yy>/` sau khi resolve override/default.
- Ví dụ: `prj_myapp_sv_auth`, `prj_shop_sv_checkout`.
- Tên sai regex → sửa trước khi tạo, KHÔNG tạo dir rác.

## Profile isolation (mục tiêu #1)

- 1 profile = 1 `user-data-dir` riêng → cookie / session / fingerprint tách hẳn giữa service.
- **Single-writer lock**: mỗi profile CHỈ 1 browser process tại 1 thời điểm. Chromium/Cloak lock `user-data-dir`; mở trùng → session corrupt / crash. Đóng session cũ TRƯỚC khi tái dùng profile.
- **Parallel subagent / worktree**: mọi worktree resolve cùng container ở root checkout chính. Mỗi service vẫn dùng đúng profile; hai task cần cùng profile → serialize, KHÔNG mở đồng thời.

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
               "--user-data-dir=/path/to/repo/.browser-profiles/prj_myapp_sv_auth"]
    },
    "cloak_myapp_auth": {
      "command": "<cloak-mcp-cmd>",
      "args": ["--user-data-dir=/path/to/repo/.browser-profiles/prj_myapp_sv_auth"]
    }
  }
}
```

- `.mcp.json` **không expand** `${HOME}`/`$BROWSER_PROFILES_DIR` — dùng **path tuyệt đối đã resolve** (`/path/to/repo/...`). Env `BROWSER_PROFILES_DIR` chỉ để người/script build path, không phải để MCP đọc.
- **Ephemeral + auth replay (nhẹ hơn persistent):** Playwright `--isolated --storage-state=<container>/prj_xx_sv_yy/state.json` — không giữ profile trên disk, chỉ nạp cookie/localStorage. Dùng khi không cần fingerprint bền.
- KHÔNG nhét >1 profile vào 1 entry (không switch per-call được).

## Session persistence — KHÔNG login lại (P0)

Profile nặng + chứa auth → **mọi setup phải giữ được session qua restart/rebuild/deploy**. Bốn nguyên nhân mất session, mỗi cái một cách chặn:

| Mất session vì | Chặn bằng |
|---|---|
| Launch thiếu `--user-data-dir` → rơi default cache | Luôn bake `--user-data-dir=<container>/prj_xx_sv_yy` (hook chặn cứng) |
| `git clean -xfd` xoá container repo-root | Preview bằng `git clean -ndx`; exclude container hoặc backup trước khi clean |
| Profile host macOS dùng trong container Linux → cookie không giải mã | Login 1 lần **trong** container, hoặc chuyển qua `state.json` (xem Migrate) |
| 2 process cùng 1 profile → lock corrupt | 1 profile = 1 process, đóng cái cũ trước |

### Case A — Local thuần (không Docker)

Setup mặc định: container `<repo>/.browser-profiles/` (chain bước 2), mỗi service 1 profile, mọi launch có `--user-data-dir`.

Bền qua đổi branch/restart khi giữ nguyên checkout. Vì container nằm trong repo-root và bị ignore, `git clean -xfd` hoặc xoá checkout **sẽ xoá session**; luôn preview/exclude hoặc backup trước. Worktree dùng container root checkout chính, không tạo bản riêng.

Verify session đã nằm trên disk: `ls <repo>/.browser-profiles/prj_<xx>_sv_<yy>/` thấy file `Cookies` → xong.

### Case B — Local qua Docker

**Bind mount thẳng container gốc của host**, KHÔNG copy profile vào image:

```yaml
# docker-compose.yml
services:
  app:
    environment:
      BROWSER_PROFILES_DIR: /data/profiles      # chain bước 1 thắng → resolve trong container
    volumes:
      - ./.browser-profiles:/data/profiles      # project path: session ghi thẳng ra repo-root host
```

- **Bind mount project path (`./.browser-profiles:/data/profiles`), KHÔNG named volume.** `docker compose down -v` xoá named volume → mất sạch session; bind mount không bị đụng. Với `docker run`, dùng path tuyệt đối `<repo>/.browser-profiles:/data/profiles`.
- Profile **không bao giờ vào image** — `.dockerignore` loại nó khỏi build context; cookie bake vào layer = leak + image phình hàng trăm MB.
- Rebuild image / `down` / restart → session còn nguyên vì nó sống ở host disk, không ở container layer.

**Login lần đầu PHẢI chạy từ trong container.** Container là Linux kể cả trên Docker Desktop for Mac; Chromium mã hoá `Cookies` bằng key từ keyring của OS (macOS Keychain vs Linux `basic`/gnome-keyring). Profile login ở host macOS mount vào Linux → **file còn nguyên nhưng cookie giải mã không ra, vẫn phải login lại**. Login trong container → profile sinh ra đúng OS đích, bind mount giữ lại trên host, từ đó về sau không login nữa.

**Scale:** 2 replica cùng mount 1 profile = lock corrupt. Nhiều replica → nhiều `prj_xx_sv_yy` khác nhau, không share.

### Migrate profile đã có auth (đỡ login lại)

Trước migrate: đóng browser nguồn/đích, resolve destination, bảo đảm `.gitignore` + `.dockerignore` có guard trước khi tạo destination, và không merge hai profile trùng tên/registry mâu thuẫn. Chỉ copy nguyên profile khi **OS + arch nguồn khớp đích** (Linux→Linux). Cross-OS (macOS→container Linux) → copy vô dụng, dùng `state.json`:

```bash
# Chạy TRÊN máy profile đang hoạt động, browser đã ĐÓNG HẲN (profile lock = đọc ra bản corrupt)
P=/path/to/repo/.browser-profiles/prj_<xx>_sv_<yy> node -e '
const {chromium} = require("playwright");
(async () => {
  const d = process.env.P;
  const ctx = await chromium.launchPersistentContext(d, {headless: true});
  await ctx.storageState({path: `${d}/state.json`});
  await ctx.close();
})();'
```

`state.json` = cookie + localStorage dạng JSON thuần → **portable mọi OS**. Dùng lại qua `--isolated --storage-state=<container>/prj_xx_sv_yy/state.json` (xem mục MCP registration). Đánh đổi: mất fingerprint bền của profile persistent — site nhạy fingerprint có thể vẫn bắt verify lại.

Ba cách theo tình huống: **cùng OS** → `rsync -a` nguyên profile (đóng browser trước). **Khác OS** → `state.json`. **Cần fingerprint bền thật** → login lại 1 lần ở OS đích, giữ bind mount.

### Deploy runbook — bảo toàn session (theo case)

> **Invariant:** session sống ở `<container>/prj_xx_sv_yy/` trên **disk host**, mặc định `<repo>/.browser-profiles/`, không ở container layer. Mọi thao tác deploy phải giữ container này → không phải login lại. Thao tác xoá/recreate checkout hoặc `git clean -xfd` có thể phá invariant.

**Case A (local thuần) — deploy = pull code + restart app:**

1. `git pull` / đổi branch / rebuild app không xoá ignored files nên session nguyên vẹn. Không chạy `git clean -xfd` nếu chưa exclude/backup container.
2. Verify: `ls <repo>/.browser-profiles/prj_<xx>_sv_<yy>/Cookies` — có file = OK.

**Case B (local Docker) — deploy = rebuild image + up lại:**

1. Xác nhận `.gitignore` và `.dockerignore` có `/.browser-profiles/`.
2. Xác nhận compose dùng **bind mount** `./.browser-profiles:/data/profiles`, không phải named volume.
3. `docker compose build && docker compose up -d` — image mới, session cũ vì nằm ở project path trên host.
4. **KHÔNG dùng `docker compose down -v`.** Dùng `down` (không `-v`) hoặc `restart`.
5. Verify trong container: `docker compose exec app ls /data/profiles/prj_<xx>_sv_<yy>/Cookies`.

**Lần đầu setup Case B (chỉ 1 lần duy nhất):**

1. Thêm `/.browser-profiles/` vào cả `.gitignore` và `.dockerignore`.
2. `mkdir -p <repo>/.browser-profiles/prj_<xx>_sv_<yy>` trên host.
3. `docker compose up -d` với bind mount + env như snippet trên.
4. Login **từ trong container** (headed qua VNC/CDP, hoặc script login headless) → profile Linux sinh ra, ghi xuyên bind mount ra host.
5. Thêm dòng vào `_registry.md`; mọi deploy sau theo runbook Case B ở trên.

**Bảng lệnh — an toàn vs phá session:**

| Lệnh | Case A | Case B | Ghi chú |
|---|---|---|---|
| `git pull`, đổi branch | ✅ an toàn | ✅ an toàn | Không xoá ignored container |
| `git clean -xfd` | 🛑 **MẤT** | 🛑 **MẤT** | Xoá `<repo>/.browser-profiles`; preview/exclude hoặc backup trước |
| `docker compose build` / `up -d` / `restart` | — | ✅ an toàn | Session ở project path host, không ở layer |
| `docker compose down` (không `-v`) | — | ✅ an toàn | Bind mount không bị xoá |
| `docker compose down -v` | — | ⚠️ an toàn **chỉ khi** bind mount | Named volume → **MẤT SẠCH** |
| `docker system prune -a --volumes` | — | ⚠️ như trên | Bind mount sống; named volume chết |
| Xoá `<repo>/.browser-profiles` | 🛑 **MẤT** | 🛑 **MẤT** | Không hoàn tác được |
| Đổi máy / xoá checkout / đổi OS | 🛑 cần migrate | 🛑 cần migrate | Xem mục Migrate |

**Trước mọi thao tác có `-v` / `prune` / `rm`:** dừng, xác nhận với user là profile có bị ảnh hưởng không. Mất session = login lại thủ công toàn bộ, không undo được.

**Backup (khuyên làm sau khi login xong):** đóng browser, tạo archive từ `<repo>/.browser-profiles` vào vị trí bảo mật **ngoài repo**. File backup chứa auth → mã hoá, giới hạn quyền truy cập, không commit, không upload artifact thường.

`state.json` là auth material: gitignore, không commit, không đẩy qua dịch vụ bên thứ ba. Chuyển sang máy khác = credential rời máy local — máy đích phải được tin ở mức tương đương.

### Container repo-root — chuẩn mặc định

`<repo>/.browser-profiles/` (chain bước 2) là container chuẩn cho local, Docker và deploy theo checkout. Trước khi tạo profile đầu tiên, PHẢI đủ 3 việc:

1. `.gitignore` → `/.browser-profiles/` (cookie trong cây repo, 1 lần `git add -f` là lộ).
2. `.dockerignore` → `/.browser-profiles/` (chặn phình build context + bake cookie vào layer).
3. Báo user: **`git clean -xfd` xoá sạch container này** (gitignored = đúng target của `-x`) → mất toàn bộ session, không undo.

Deploy sang máy khác không mang profile theo Git/image. Backup/migrate riêng hoặc provision persistent host path rồi set `BROWSER_PROFILES_DIR` tuyệt đối trên máy đích.

**Worktree:** repo fan-out `.claude/worktrees/<slug>/` vẫn resolve `<repo>` về root checkout chính, nên dùng chung container + registry. Hai task đụng cùng profile phải serialize vì single-writer lock.

## Registry — quản lý tập trung (mục tiêu #2/#3)

`<container>/_registry.md` — 1 bảng nguồn-sự-thật:

```text
| profile              | project  | service | created    | last-used  | note |
|----------------------|----------|---------|------------|------------|------|
| prj_myapp_sv_auth    | myapp    | auth    | 2026-09-21 | 2026-09-21 |      |
```

Tạo / dùng profile → cập nhật dòng (nhất là `last-used`). Không có registry → task đầu tiên tạo file.

## Secret guard

- Profile dir chứa cookie / session / auth token → **coi là secret**. KHÔNG `cat`/print nội dung profile ra chat. KHÔNG commit.
- Container mặc định `<repo>/.browser-profiles/` → BẮT BUỘC `.gitignore` + `.dockerignore` trước khi tạo profile. Override qua `BROWSER_PROFILES_DIR` vẫn giữ guard này để profile không bao giờ bị track hoặc vào Docker context.
- Tie [[secrets-no-printout]], [[vault-no-mcp]].

## Cleanup / TTL

- Profile `last-used` cũ > 30 ngày → candidate dọn. Liệt kê + confirm user TRƯỚC khi xoá (destructive). KHÔNG auto-`rm`.
- Xoá profile → xoá luôn dòng trong `_registry.md`.

## Tránh

- ❌ 2 process cùng 1 profile (lock corrupt).
- ❌ Dùng chung 1 profile cho nhiều service (mục tiêu isolation vỡ).
- ❌ Đăng ký browser MCP global (mọi project gánh tool defs).
- ❌ Commit profile dir / print cookie.
- ❌ `mkdir` container trước khi cả `.gitignore` và `.dockerignore` có `/.browser-profiles/`.
- ❌ Quên `git clean -xfd` xoá container ignored; luôn preview/exclude hoặc backup trước.
- ❌ Tạo container riêng trong từng worktree; mọi worktree phải resolve về root checkout chính.
- ❌ **Named volume** cho profile (`docker compose down -v` xoá sạch session) — dùng bind mount.
- ❌ `COPY .browser-profiles` vào Dockerfile (cookie bake vào image layer + phình image).
- ❌ Copy profile macOS → container Linux rồi tưởng còn session (cookie không giải mã được — dùng `state.json`).
- ❌ Export `state.json` khi browser còn mở profile đó (lock → đọc ra bản corrupt).
