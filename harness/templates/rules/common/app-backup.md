---
name: app-backup
description: Chuẩn backup data app (DB/state/config) cho mọi project — job launchd hằng ngày trên macmini2, snapshot nhất quán + retention, mirror macmini1, bản mã hoá AES-256-GCM lên Google Drive qua rclone, Telegram service-alert mỗi lần chạy
status: live
updated: 2026-10-19
paths:
  - "**/*backup*"
  - "**/*backup*/**"
  - "**/*.plist"
  - "**/launchd/**"
metadata:
  type: reference
---

# App backup — chuẩn dùng chung (cross-project)

Thêm backup cho app/DB mới → làm theo cơ chế này, KHÔNG tự chế lịch/đích/alert riêng. Mẫu tham chiếu đang chạy: `soak/monitor/dbbackup.mjs` + `dbbackup-install.sh` trong repo BotControl (`acegalaxy-co/ace_ace_island-bot-player`) — copy rồi đổi nguồn dữ liệu.

## Chạy ở đâu

- **Host chạy job: macmini2** (máy 24/7), launchd LaunchAgent `co.acegalaxy.<app>-backup`, `StartCalendarInterval` 1 lần/ngày giờ thấp tải (vd 03:30, lệch giờ giữa các app), `Nice 15`, `Umask 63`. Máy ngủ lỡ giờ → launchd chạy bù khi thức.
- Script backup **self-contained** (chỉ import `node:`/stdlib), rsync riêng vào `~/apps/<app>-backup/` — không chạy từ source app (deploy app không làm vỡ backup).
- Installer có **dry-run mặc định**, `--apply` mới ghi; `--run-now` chạy thật 1 lần để verify sau cài.

## Bản backup

1. **Snapshot nhất quán**, không copy file đang ghi: SQLite → `VACUUM INTO` + `PRAGMA integrity_check`; Postgres → `pg_dump`; file JSON → đọc rồi ghi tmp + rename. Mở nguồn read-only.
2. Output `~/apps/<app>-backup/backups/<YYYY-MM-DD>/`, dir `0700`, file `0600`, gzip. Chạy lại trong ngày → ghi đè ngày đó (idempotent).
3. **Retention local:** giữ 30 ngày + bản đầu tháng 12 tháng. Lịch sử thay đổi quan trọng (đổi tên, xoá…) → `history/*.jsonl` append-only, không bao giờ prune.

## Bản off-host (chỉ khi mọi bản local OK)

- **Mirror macmini1:** `rsync -a` (KHÔNG `--delete`, không prune) sang `macmini1:apps/<app>-backup-mirror/macmini2/`.
- **Google Drive qua rclone** (không dùng Google Drive app — cần GUI/admin, dễ ngừng sync):
  - rclone binary `~/.local/bin/rclone` trên macmini2, config `~/.config/rclone/rclone.conf` (0600). Remote dùng chung `gdrive-fleet-backup:` (root = folder backup của org; account + folder id ghi trong memory project, KHÔNG ghi vào rule/repo). App mới → subfolder riêng `gdrive-fleet-backup:<app>/`.
  - Login OAuth: chạy `rclone authorize drive` trên máy có browser, ghi output thẳng file `umask 077`, parse token trong script rồi pipe qua ssh vào `rclone.conf` — KHÔNG in token ([[secrets-no-printout]]). Xoá file token tạm sau khi ghi.
  - **Luôn mã hoá trước khi upload** (data có secret/PII): tar.gz bản ngày + `history/` → AES-256-GCM (`node:crypto`; layout `FDB1` + IV 12B + tag 16B + ciphertext). Key 32 byte hex tạo 1 lần trên host (`openssl rand -hex 32`, `0600`), không in ra; **sao lưu key** ra máy local + vault (mất key = mất mọi bản Drive).
  - Verify: decrypt lại file tmp so sha256 trước upload; `rclone copyto` rồi `rclone lsjson` so size. Không prune trên Drive.
  - Có lệnh restore (`--decrypt FILE --to OUT`) + ghi bước restore ở header script.

## Báo cáo

- **Mỗi lần chạy gửi 1 tin Telegram** qua `service-alert` (service `<app>-backup`, [[general]] mục Telegram service alert): `ok` khi tất cả OK; `fail` khi DB/snapshot lỗi HOẶC upload Drive lỗi; `warn` khi chỉ mirror lỗi. Field: số bản ghi, dung lượng, số ngày đang giữ, trạng thái mirror/Drive. Gửi best-effort, timeout, không làm job crash.
- Log 1 dòng JSON/lần vào `~/apps/<app>-backup/logs/` (không chứa secret); exit ≠ 0 khi có lỗi.
- Test bắt buộc: happy + DB lỗi + đích off-host lỗi (fake rclone/rsync) — không gọi Drive thật trong test.
