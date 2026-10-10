---
name: deploy-security
description: P0 khi deploy/publish — web root/image/package CHỈ chứa file public (allowlist), web server chặn dotfile + file nhạy cảm, probe live sau deploy; 200 có nội dung thật = FAIL + rollback
status: live
updated: 2026-10-08
paths:
  - ".gitlab-ci.yml"
  - ".github/workflows/**"
  - "Dockerfile*"
  - ".dockerignore"
  - "docker-compose*"
  - "compose*.y*ml"
  - "**/nginx/**"
  - "**/*.conf"
  - "Caddyfile"
  - "ecosystem.config.*"
  - "**/deploy*"
  - "package.json"
  - ".npmignore"
  - ".claude/skills/production-*/**"
  - ".claude/skills/git-push-safety/**"
metadata:
  type: reference
---

# Deploy security — chỉ public cái cần public (cross-project, P0)

Áp mọi lần **deploy web/service**, **build image**, **publish package**. Bổ sung [[secrets-no-printout]], [[git-workflow]].

## 1. Allowlist, KHÔNG denylist

- Web root / static dir / image / package **chỉ** chứa file build/public liệt kê rõ. Thêm file public mới → thêm vào allowlist.
- ❌ CẤM web root (nginx `root`, `express.static`, `serve`, symlink deploy) trỏ vào **repo checkout** hoặc thư mục cha của source. Repo luôn có `.claude/`, `CLAUDE.md`, `.git`, `package.json`, source, script nội bộ.
- Static site: copy allowlist sang thư mục release riêng → trỏ symlink vào đó (giữ N release để rollback).
- Express/Node: `express.static('public')` dir riêng, KHÔNG `express.static(__dirname)` / `'.'`.
- Docker: `COPY` từng path cần thiết, hoặc `COPY . .` **kèm** `.dockerignore` loại `.env*`, `.git`, `.claude`, `CLAUDE.md`, `*.pem`, `*.key`, `node_modules`, test/docs.
- npm lib: `package.json` có `files: [...]` (allowlist). Không có → `npm publish` đẩy mọi thứ không gitignore. Verify `npm pack --dry-run`.

## 2. Web server chặn lớp thứ 2 (phòng allowlist sót)

nginx (mỗi `server` public):

```nginx
server_tokens off;
autoindex off;
location ~ /\.(?!well-known/) { return 404; }
location ~* \.(env|ini|conf|cfg|ya?ml|toml|md|sh|py|rb|php|sql|bak|old|orig|swp|log|pem|key|crt|p12|zip|tar|gz|7z|map)$ { return 404; }
location ~* /(package(-lock)?\.json|composer\.(json|lock)|Dockerfile|docker-compose[^/]*|server\.js|ecosystem\.config\.[a-z]+)$ { return 404; }
```

Site cần serve `.json`/`.zip`/`.map` thật → whitelist path cụ thể trước block trên, không bỏ block. Caddy/Express tương đương: `respond 404` / middleware chặn `^/\.` + extension.

Service nội bộ (DB, redis, admin, metrics): bind `127.0.0.1` hoặc network nội bộ, KHÔNG `0.0.0.0` / `ports: "5432:5432"` ra public.

## 3. Probe live SAU deploy (bắt buộc)

```bash
BASE=https://<domain>   # mỗi domain/subdomain đã deploy
nf=$(curl -s "$BASE/__probe_$RANDOM" | shasum | cut -c1-40)   # trang 404 custom có thể trả 200
for p in /.env /.env.local /.env.production /.git/config /.git/HEAD /.claude/settings.json /CLAUDE.md \
         /README.md /package.json /package-lock.json /server.js /Dockerfile /docker-compose.yml \
         /.gitlab-ci.yml /.mcp.json /plan.md /config.json /ecosystem.config.js /.DS_Store /backup.zip; do
  code=$(curl -s -o /tmp/probe.$$ -w '%{http_code}' "$BASE$p")
  [ "$code" = 200 ] && [ "$(shasum < /tmp/probe.$$ | cut -c1-40)" != "$nf" ] && echo "LEAK $code $p"
done; rm -f /tmp/probe.$$
```

- Không in body ra output (có thể chứa secret) — chỉ path + code.
- Có dòng `LEAK` → **FAIL**: rollback (đổi symlink/image về release trước) rồi sửa allowlist/nginx. Path lộ có thể chứa secret → coi secret đó compromised, rotate ([[secrets-no-printout]]).
- Thêm path đặc thù project (vd `/cloudflare/`, `/scripts/`, `/template_ui/`) vào list.

## 4. Trước push / deploy

- gitleaks + `/check-hardcode` qua `/git-push-safety` (hook chặn raw `git push`).
- `.env*`, `*.pem`, `*.key`, `credentials*` KHÔNG tracked: `git ls-files | grep -Ei '(^|/)\.env|\.pem$|\.key$|credential|id_rsa'` (trừ `.env.example`) phải rỗng.
- Container KHÔNG mount nguyên `~/.ssh`, `~/.claude`, `~/.config/gh`, `~/.aws` — chỉ mount đúng file cần, `:ro`.
- GitHub Actions: khai báo `permissions:` top-level (mặc định `contents: read`), job nào cần ghi mới mở rộng; token deps chỉ quyền read.
- Secret vào runtime qua env/secret store của CI/host — KHÔNG `ENV`/`ARG` literal trong Dockerfile, KHÔNG literal trong compose, KHÔNG `echo $SECRET` trong CI log.
- **Site public — scan nội dung** (khác scan leak file): text/ảnh/meta mới hoặc đổi phải qua kiểm tra pháp lý VN (quảng cáo, cờ bạc, tuyển dụng, dữ liệu cá nhân), lộ danh tính/địa chỉ/thông tin nội bộ, nội dung nhạy cảm. Có vấn đề → dừng deploy, báo user. Project có file rule content riêng (vd `careers-content.md`) → áp file đó.

## 5. Khi review/thêm deploy mới

Checklist 1 dòng mỗi mục trong báo cáo deploy: allowlist ✓ · web-server block ✓ · port nội bộ không public ✓ · probe sạch ✓ · nội dung public đã scan ✓ (nếu có site public). Thiếu mục nào → nêu rõ, không claim "deploy an toàn".
