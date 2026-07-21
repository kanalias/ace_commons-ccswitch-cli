---
name: audit-git-leak
description: Gate bắt buộc trước mỗi lần push GitHub — gitleaks + quét thông tin nhạy cảm (production IP, production domain, domain nội bộ acegalaxy...). Dùng khi user nói "audit git leak", "check leak trước khi push", hoặc trước bất kỳ lệnh push GitHub nào.
user-invocable: true
---

# audit-git-leak — gate leak trước khi push GitHub

Chạy **mỗi lần** sắp push lên GitHub. Dừng ngay khi nghi ngờ — không tự sửa rồi push tiếp, không tự quyết "chắc an toàn".

## 1. gitleaks

`gitleaks detect --source "$(git rev-parse --show-toplevel)" --redact -v`

Chưa cài → STOP, hướng dẫn cài, không âm thầm bỏ qua bước này:
- macOS: `brew install gitleaks`
- Linux: package manager distro (`apt install gitleaks`, `pacman -S gitleaks`...)
- Go: `go install github.com/gitleaks/gitleaks/v8@latest`

gitleaks báo finding → STOP, mô tả finding cho user, không tự quyết false positive.

## 2. Sensitive-content scan (ngoài phạm vi regex gitleaks)

Xem `git status` + `git diff --stat` (so với upstream/main, hoặc `HEAD` nếu chưa commit) để biết đúng phạm vi sắp push. Đọc qua từng file thay đổi, tìm:

- **Production IP** — IP thật gắn server production (vd dải private `10.*`/`172.16-31.*`/`192.168.*` kèm context server thật), không phải IP ví dụ (`127.0.0.1`, `0.0.0.0`, doc example).
- **Production domain / hostname thật** — endpoint router/proxy/API thật, không phải placeholder (`example.com`, `proxy.com`, `<your-domain>`).
- **Domain nội bộ công ty acegalaxy** (hoặc domain/subdomain nội bộ khác của org) — kể cả xuất hiện trong comment, log mẫu, config sample.
- API key/token/credential thật (không phải placeholder `<your-api-key>`, `sk-...`).
- File lỡ stage: `.env*`, `*.bak`, swap file editor, credential dump.
- Thông tin cá nhân (email/tên thật) chưa từng public trong git history repo.

Nghi ngờ bất kỳ điều nào → STOP, mô tả rõ cho user, không tự quyết là an toàn.

## 3. Push

Chỉ khi bước 1-2 đều sạch: show user `git status`, branch hiện tại, remote — hỏi xác nhận trước khi `git push`. Không force-push trừ khi user yêu cầu rõ trong hội thoại này.
