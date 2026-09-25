---
name: processes-layout
description: Layout code chạy nền — processes/jobs (cron; chung 1 package + 1 image nhưng MỖI job = 1 entry + 1 compose service chạy riêng) vs processes/services (worker chạy liên tục, package độc lập, pm2/supervisor); naming job <verb>-<source>-to-<target>-<table>, log prefix [job=<name>]. LAZY, load khi chạm processes/, apps/, compose, ecosystem.
status: live
updated: 2026-09-25
paths:
  - "**/processes/**"
  - "**/apps/**"
  - "**/*compose*.{yaml,yml}"
  - "**/ecosystem.config.*"
metadata:
  type: reference
---

# Layout `processes/` — code chạy nền (cross-project)

Áp cho repo có code chạy nền (cron job, worker, poller). Root có thể là `processes/` hoặc `<platform>/processes/` — quy ước dưới tính từ root đó.

| Dir | Chứa | KHÔNG chứa |
|---|---|---|
| `apps/` | app phục vụ request user trực tiếp (server, web, auth, mobile) | job/worker nền |
| `processes/` | mọi process chạy nền, không phục vụ request user trực tiếp | HTTP handler cho user |
| `packages/` | code dùng chung giữa `apps/` và `processes/` | logic riêng 1 app/process |

## `processes/jobs/` — chạy theo lịch, MỖI job 1 process riêng

- Gom chung **1 package** (member workspace root) + **1 Dockerfile** (1 image). Nhưng **mỗi job chạy thành process riêng**: 1 compose service (hoặc 1 pm2 app) riêng — KHÔNG gom nhiều job vào 1 scheduler chung (1 job treo/crash không kéo job khác; interval, env, deploy độc lập).
- Mỗi job = 3 file khớp tên `<name>`:
  - `src/jobs/<name>.ts` — logic thuần, export hàm run + `jobConfig` (spread `sharedConfig` + env riêng job: DB id, interval…). KHÔNG khai báo cron ở đây.
  - `src/entry-<name>.ts` — scheduler cho ĐÚNG 1 job: đăng ký cron, hỗ trợ `--once` (chạy 1 vòng rồi thoát) để test/debug tay. Không import job khác.
  - `test/jobs/<name>.test.ts`.
- `src/config.shared.ts` — env dùng chung mọi job (token, API base URL, rate limit) + helper `required()`. KHÔNG có `config.ts` tổng gom env của mọi job.
- `package.json` scripts theo bộ 3 mỗi job: `dev:<short>`, `start:<short>`, `<short>:once` (`<short>` = tên rút gọn, vd `lead-sync`).
- Compose: service `<package-role>-<short>` (vd `crawler-lead-sync`), cùng `build.dockerfile`, chỉ khác `command: ["npm", "run", "start:<short>"]` + env riêng job. Dockerfile `CMD` = 1 job mặc định, compose override.
- Interval: env riêng mỗi job, không dùng chung 1 biến cho nhiều job.
- Naming `<name>` kebab-case `<verb>-<source>-to-<target>-<table>`:
  - `sync-*` — đồng bộ giữa 2 hệ thống khác nhau (vd `sync-notion-to-pg-notion-lead`).
  - `transform-*` — biến đổi trong cùng DB (vd `transform-pg-notion-lead-to-candidate`).
  - Tên hệ thống viết thường (`pg`, `notion`, `gsheet`), không `PG`/`Pg`.
- Log prefix BẮT BUỘC `[job=<name>]` ở cả entry lẫn file job — gộp log nhiều service vẫn tách được.

## `processes/services/` — chạy liên tục

- Worker loop/poll/queue, KHÔNG theo lịch cố định. Supervisor giữ tiến trình sống: pm2 `autorestart: true`, hoặc systemd / compose `restart: unless-stopped`.
- Mỗi service = **package độc lập**: `package.json` + lockfile riêng, KHÔNG là member workspace root (deploy/rollback độc lập, dep không kéo nhau).
- `ecosystem.config.*` (hoặc unit/compose tương đương) đặt ngay trong dir service; log ra `logs/` trong dir đó (gitignored). Mọi service trỏ **cùng 1** `.env` — path tương đối từ dir service phải giống nhau giữa các service (di chuyển dir → sửa path, không để trỏ file không tồn tại).

## jobs vs services — chọn gì

| | `jobs/` | `services/` |
|---|---|---|
| Nhịp | cron, có lúc nghỉ | liên tục |
| Package / image | chung 1 | riêng từng service |
| Tách package riêng khi | dep/tài nguyên khác hẳn (browser, GPU…) | mặc định đã riêng |

## Tránh

- ❌ Job nền nằm trong `apps/` (vd `apps/scheduler`, `apps/crawler`) → chuyển vào `processes/jobs`.
- ❌ 1 `main.ts` gom lịch nhiều job / 1 compose service chạy nhiều job.
- ❌ Entry import 2+ job, hoặc cron khai báo trong file job.
- ❌ Thêm service vào workspace root "cho tiện" → mất độc lập lockfile.
- ❌ Log không prefix `[job=<name>]`.
