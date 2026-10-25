---
name: ace-security-scan
description: "Quét security READ-ONLY cho máy tính (macOS/Linux: SIP, FileVault, firewall, persistence LaunchAgent/cron, SSH key, port mở, secret trong shell rc, quyền file credential), code (gitleaks history + working tree, file nhạy cảm bị track, semgrep, osv-scanner/npm audit, trivy) và cấu hình Claude Code (hook/skill nguy hiểm, bypassPermissions, secret trong settings, MCP server). Không in giá trị secret. Dùng /ace-security-scan [machine|code|claude|all] [path], hoặc khi user nói \"quét security\", \"scan bảo mật\", \"máy có bị nhiễm không\", \"audit bảo mật code\", \"check secret lộ\"."
user-invocable: true
---

# ace-security-scan — quét security máy + code + Claude config

> **Nhóm skill bảo mật (`ace-*`)** — nguồn phát triển là nhánh `ace-skill` của repo ccswitch, CHỈ push lên remote `kane` (repo private `kanalias/ccswitch-kane`). KHÔNG push nhánh `ace-skill` lên `origin` (public). Gate: `.claude/private-branches.txt` + `.git/hooks/pre-push` + ruleset GitHub. Xem rule `private-branch-kane`.

Script cố định `scan.sh` (cùng thư mục skill) đo đạc; AI chỉ chạy, đọc report, phân tích và đề xuất cách sửa. **Read-only tuyệt đối**: không sửa, không xoá, không cài tool, không `sudo`, không gửi mẫu ra ngoài.

## Bước 0 — chọn mode

| Arg | Quét |
|---|---|
| `machine` | Máy local + cấu hình Claude global (`~/.claude`) |
| `code [path]` | Repo/thư mục (mặc định cwd) |
| `claude [path]` | `~/.claude` + `<path>/.claude` + MCP (`~/.claude.json`, `.mcp.json`) |
| `all [path]` (mặc định) | Cả 3 |

Thiếu arg mà ý user không rõ → hỏi bằng AskUserQuestion (4 lựa chọn trên).

## Bước 1 — chạy script

```bash
SKILL_DIR="<thư mục chứa SKILL.md này>"   # ~/.claude/skills/ace-security-scan hoặc <repo>/.claude/skills/ace-security-scan
bash "$SKILL_DIR/scan.sh" <mode> [path]
```

- Report Markdown in ra stdout + lưu `~/.ace-security-scan/<timestamp>-<mode>.md` (dir 0700, file 0600). Đổi chỗ lưu: `ACE_SECSCAN_OUT`.
- Thêm thư mục cần kiểm quyền `.env*`/`*.pem` (others-read): `ACE_SECSCAN_ENV_ROOTS="<dir1> <dir2>"`.
- Dòng cuối `SUMMARY: critical=N warn=N info=N ok=N`.
- Cài/đồng bộ bản global (`~/.claude/skills`): `bash <ccswitch>/install-global-skills.sh` — sửa template xong chạy lại.
- Tool tuỳ chọn thiếu (semgrep, osv-scanner, trivy) → script ghi `info` kèm lệnh `brew install`. **KHÔNG tự cài** — hỏi user trước (cài = thêm dependency, theo `dep-ladder-check` nếu có).

## Bước 2 — phân tích + báo cáo (tiếng Việt)

1. Bảng **critical → warn**: mỗi dòng = rủi ro thực tế là gì + lệnh/cách sửa cụ thể. `info` chỉ tóm gọn những mục đáng để ý.
2. Đánh giá false positive trước khi kết luận:
   - SIP tắt: hỏi user có chủ ý không (dev kernel ext/VM) rồi mới khuyên bật (`csrutil enable` trong Recovery).
   - Port 22/5900 mở: Remote Login/Screen Sharing có thể là cố ý — khuyên giới hạn bằng firewall/chỉ LAN/VPN.
   - SSH key không passphrase: khuyên `ssh-keygen -p -f <key>` + `ssh-add --apple-use-keychain`; key deploy cho máy tự động có thể chấp nhận — để user quyết.
   - "Pattern nguy hiểm trong hook/skill": đọc đúng file:line, phân biệt docs/ví dụ với lệnh thật.
   - LaunchAgent target không tồn tại = rác của app đã gỡ, không phải malware.
3. Finding secret (gitleaks / secret trong rc / settings): coi như **đã lộ** nếu nằm trong git history hoặc đã push → khuyến nghị rotate (skill `rotate-secret` nếu có) + xoá khỏi history có hỏi user. KHÔNG mở file để xem value.
4. Kết: 1 dòng mức rủi ro tổng + path report.

## Bước 3 — sửa (chỉ khi user đồng ý)

Đề xuất lệnh sửa theo từng finding; chỉ chạy những lệnh user chọn. Sửa file AI không có quyền (`.env*`, `~/.ssh`, settings) → viết sẵn lệnh idempotent cho user copy (skill `copy-data-cmd` nếu có). Không tự đổi cấu hình hệ thống (SIP, FileVault, firewall).

## Quét sâu hơn (tuỳ chọn)

- SAST theo ngôn ngữ + supply chain: plugin Trail of Bits (`/plugin marketplace add trailofbits/skills` → `static-analysis`, `supply-chain-risk-auditor`). License CC-BY-SA 4.0 → cài dạng plugin, không copy vào harness.
- Malware có chữ ký: script chỉ là heuristic (không phải antivirus). Cần quét thật → KnockKnock/BlockBlock (Objective-See) hoặc ClamAV, user tự cài.

## Không làm

- ❌ In giá trị secret (script chỉ in rule, file:line, tên biến, đếm; gitleaks chạy `--redact`). Không `cat` file mà report nêu tên.
- ❌ Gửi report ra ngoài (Telegram/Notion/MCP) mà chưa hỏi user — report chứa tên host, đường dẫn, danh sách key.
- ❌ Coi "0 finding" là an toàn tuyệt đối khi tool tuỳ chọn còn thiếu — nêu rõ phần nào chưa quét.

Nguồn tham khảo: checklist machine/malware dựa trên [claude-mac-guardian](https://github.com/dennisonbertram/claude-mac-guardian) (MIT, © 2026 Dennison Bertram), viết lại thành script; quy tắc semgrep `--metrics=off` theo [trailofbits/skills](https://github.com/trailofbits/skills).
