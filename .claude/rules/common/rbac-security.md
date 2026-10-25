---
name: rbac-security
description: P0 app có tích hợp RBAC (lib-notion-rbac / port Java…) — BẮT BUỘC RBAC Scan (leak + chặn quyền) trước push VÀ lúc deploy (probe live không cookie); fail = không push / rollback
status: live
updated: 2026-10-21
paths:
  - "**/rbac.json"
  - "**/*rbac*"
  - "**/*Rbac*"
  - "**/*login*"
  - "**/*Login*"
  - "**/admin/**"
  - ".gitlab-ci.yml"
  - ".github/workflows/**"
  - "Dockerfile*"
  - "docker-compose*"
  - "ecosystem.config.*"
  - "**/deploy*"
  - ".claude/skills/production-*/**"
  - ".claude/skills/git-push-safety/**"
  - ".claude/skills/ace-rbac-notion/**"
metadata:
  type: reference
---

# RBAC security — scan bắt buộc khi app có phân quyền (cross-project, P0)

RBAC chạm login, session, admin, data nhân sự → lộ token/id Notion/email HR hoặc route admin không chặn = rò rỉ. Bổ sung [[deploy-security]], [[secrets-no-printout]], [[staff-view-no-sensitive]].

## 1. Detect — app có RBAC?

```bash
git ls-files | grep -qE '(^|/)rbac\.json$' || git grep -qE 'lib-notion-rbac|NotionRbac|AceLoginTicket|verifyTicket' -- . ':!.claude' ':!*.md' && echo RBAC
```

Có `RBAC` → mọi push + mọi deploy (staging/prod, mọi skill deploy) PHẢI chạy mục 2 + 3. Không skip, không "diff nhỏ".

## 2. Scan trước push (code)

Trên range sắp push (`git diff <upstream>..HEAD`). Fail bước nào → DỪNG, sửa, chạy lại:

- `/audit-git-leak` + `/check-hardcode` + subagent `secret-scanner`.
- Không tracked: `.env*`, token, id page/DB Notion thật (chỉ qua env), output dry-run/`--apply` của `setup.js`, dump HR/email nhân sự (ngoài 3 email owner cố định).
- Chặn quyền phía server: mọi route `./admin`, API admin, `/api/ai/explain`, trang chỉ xem → không login / không quyền / `ban` ra 401/403/redirect, kể cả gọi API trực tiếp (ẩn nút ≠ chặn). Có test từ chối tương ứng.
- Response/log không lộ: lỗi không trả stack, token, id Notion, email người khác; cookie phiên không chứa quyền; log không in token/ticket.
- Lỗi Notion → fail closed (từ chối), không mở quyền. Login cũ vẫn chạy.

## 3. Scan lúc deploy (live — bắt buộc mỗi lần deploy)

Sau healthcheck, trên MỌI domain vừa deploy, request KHÔNG cookie:

```bash
BASE=https://<domain>
for p in /admin /admin/ /admin/api/roles /admin/api/members /api/ai/explain <route-admin-đặc-thù>; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE$p")
  case $code in 401|403|404|301|302|303|307|308) echo "OK $code $p";; *) echo "OPEN $code $p";; esac
done
curl -s -X POST "$BASE/api/ai/explain" -o /dev/null -w '%{http_code}\n'   # cũng phải 401/403
```

- Redirect phải về trang login, không phải trang admin. Không in body (có thể chứa data) — chỉ path + code.
- Có `OPEN` → deploy **FAIL**: rollback như smoke fail, báo route lộ; data đã lộ qua route đó → coi compromised.
- Kèm probe leak file theo [[deploy-security]] mục 3.

## 4. Báo cáo

In bảng `mục | PASS/FAIL | bằng chứng` (leak scan · hardcode · secret-scanner · chặn quyền test · probe live) trước push và trong báo cáo deploy. Thiếu mục → không claim "an toàn".
