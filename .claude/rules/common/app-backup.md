---
name: app-backup
description: Chuẩn backup data app (DB/state/config/secret) cho mọi project — dùng lib @acegalaxy/lib-backup-ace-db, khai báo manifest JSON, 1 runner launchd chạy tuần tự trên macmini2, mã hoá AES-256-GCM, rclone Drive giới hạn băng thông, mirror macmini1, Telegram ok/fail
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

Thêm backup cho app/DB mới → **khai báo manifest cho lib `@acegalaxy/lib-backup-ace-db`** (repo private `acegalaxy-co/lib-backup-ace-db`, cài từ git tag). KHÔNG viết script/launchd/alert backup riêng trong project.

## Cơ chế

- **1 runner duy nhất trên macmini2**: launchd `co.acegalaxy.ace-backup` (`ace-backup install-launchd`), chạy 1 lần/đêm trong khung thấp tải, **các app nối tiếp nhau** (không song song), lock toàn cục. `ProcessType Background`, `Nice 15`, `LowPriorityIO`, child process bọc `nice` + `taskpolicy -b`.
- **Host config** `~/.config/acegalaxy/backup-host.json` (workDir, keyFile, remote rclone + `bwlimit`, mirror, alert). **Manifest mỗi app** `~/.config/acegalaxy/backup.d/<app>.json` (hoặc `backup.json` trong repo app nếu host config trỏ tới). Bản gốc host config + manifest version trong repo lib `hosts/<host>/`.
- Manifest: `app`, `folder` (folder Drive, mặc định = app), `priority` P1/P2/P3, `retention` {local, remote, mirror} (days ≥ 1; `null` = không prune), `sources[]`.
- Source types: `sqlite` (online backup 1 bước / `VACUUM INTO`, chạy trong worker, `quick_check`), `files` (tar giữ layout tuyệt đối, `exclude`, profile trình duyệt đang mở → `lockedPolicy: copy` + `sqliteInside` cho Cookies/Login Data), `redis` (BGSAVE → `docker cp` RDB), `pgdump` (`-Fc`, password qua env), `command` (escape hatch). Source `required` rỗng/thiếu → fail, không pack, không prune.

## Bắt buộc

1. **Mã hoá trước khi rời máy**: tar → zstd → AES-256-GCM streaming (`ACB1` + IV + ct + tag), verify decrypt-to-hash trước khi ghi đè bản cùng ngày. Key 1 file 64 hex `0600` trên host, **sao lưu key ra máy local + vault** (mất key = mất mọi bản). Restore: `ace-backup decrypt` vào dir `0700`, xoá plaintext sau dùng.
2. **Upload chậm, không tranh tài nguyên**: rclone `--bwlimit` nhỏ (timetable ngày/đêm), `--transfers 1 --checkers 1`; rsync mirror `--bwlimit`. Không đặt lịch trùng job nặng khác của host.
3. **Mỗi app 1 folder Drive** ngang hàng trong folder backup cha của org (account + folder id ghi trong memory/config private, KHÔNG ghi vào rule/repo public).
4. **Telegram mỗi lần chạy** qua `service-alert` (service `<app>-backup`, [[general]] mục Telegram service alert): `ok` / `fail` (source bắt buộc, pack/verify, upload lỗi) / `warn` (source tuỳ chọn, mirror, prune lỗi). Không tìm thấy manifest nào → fail.
5. **Secret không bao giờ vào argv/log/alert** ([[secrets-no-printout]]); OAuth rclone: `rclone authorize drive` trên máy có browser, ghi token thẳng file `umask 077`, pipe vào `rclone.conf` host, xoá file tạm.
6. Thêm app mới: viết manifest → `ace-backup run --dry-run --app <app>` → chạy thật `--app <app> --alert` 1 lần, kiểm file trên Drive + tin Telegram → commit manifest vào repo lib `hosts/<host>/backup.d/`.

## Không backup

Dữ liệu tạo lại được (node_modules, build, image, cache trình duyệt, log), mirror phái sinh từ DB đã backup, kho đã tự có bản sao ngoài host (vd git mirror có remote dự phòng) — chỉ backup secret/state của chúng.
