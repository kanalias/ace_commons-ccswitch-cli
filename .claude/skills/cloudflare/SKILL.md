---
name: cloudflare
description: Quản lý Cloudflare — DNS, WAF/firewall/redirect rules, chặn/mở bot (AI bots), cache purge, Zero Trust/Access, tunnel ingress, quyền API token. Ưu tiên API token từ env, dashboard qua subagent browser chỉ khi API không làm được. Dữ kiện zone/account đọc từ `.claude/cloudflare-targets.md`. Dùng khi user gõ /cloudflare [yêu cầu], hoặc nói "cloudflare", "DNS", "WAF", "cache purge", "bot bị 403", "chặn quốc gia", "token cloudflare thiếu quyền".
user-invocable: true
disable-model-invocation: true
---

# /cloudflare — DNS, WAF, cache, config

Không có yêu cầu → chạy `check` (chỉ đọc). Skill đổi được DNS/WAF production: gọi `/cloudflare` rõ ràng **không phải là xác nhận** cho thao tác ghi. Trước mỗi ghi: liệt kê zone/target, scope, tác động, diff before/after → hỏi user → chờ trả lời.

## Dữ kiện theo project (harness không cài, không ghi đè)

Đọc `.claude/cloudflare-targets.md` trước mọi bước. File vắng, hoặc còn `<...>` chưa điền → **dừng**, in mẫu dưới cho user điền, không đoán giá trị.

```markdown
# Cloudflare targets
- Zones: <zone> (id <zone_id>), ...
- Account id: <account_id>
- Env var token: <CLOUDFLARE_API_TOKEN | tên khác>; file env: <đường dẫn, ngoài repo>
- Browser: <MCP/agent + profile dir, tương đối repo> (nếu cần dashboard)
- Chính sách: <zone nào mở bot / chặn quốc gia / whitelist IP ...>
- Ghi chú: <rule id/tên cần giữ, record KHÔNG xoá, tunnel, v.v.>
```

## API trước, dashboard sau

1. Token từ env/file khai báo trong targets. Nạp trong subshell, bỏ khoảng trắng/dấu nháy, `unset` sau dùng. KHÔNG in token/cookie/client secret; chỉ in `success`/`errors`/id/số đếm.
2. Gọi `https://api.cloudflare.com/client/v4`. Shell profile chèn output thừa vào curl → dùng `/usr/bin/curl -s -o <file>` rồi parse bằng jq/python.
3. API trả `Authentication error` (10000) hoặc 403 `request is not authorized` → token thiếu quyền. Cách xử lý, theo thứ tự: (a) báo user quyền cần thêm (Zone Read, DNS Edit, Zone WAF Edit, Bot Management Edit, Cache Purge, Access…); (b) nếu targets cho phép tự thêm quyền → dùng session dashboard của browser agent: `GET /api/v4/user/tokens/permission_groups`, rồi `PUT /api/v4/user/tokens/<id>` thêm đúng nhóm quyền tối thiểu (giữ `id` policy, header `x-atok` từ `/api/v4/system/bootstrap`). Không tạo/roll token.
4. Dashboard qua subagent browser (profile khai báo trong targets, đúng profile, 1 profile = 1 process): chưa đăng nhập/Turnstile/2FA → mở headed, nhờ user đăng nhập tay, KHÔNG nhập credential/OTP thay. Snapshot trước mỗi click, tìm theo text (UI đổi thường). Profile lock → dừng, báo user.

## Chế độ

| Lệnh | Việc | Ghi? |
|---|---|---|
| `check` (mặc định) | Liệt kê zone, DNS, WAF/redirect rules (ON/OFF, mô tả), bot_management, host DNS-only (rule không có tác dụng); probe `curl -A '<UA>'` nếu hỏi về bot | không |
| `dns` | GET trước (tránh trùng), POST/PATCH/DELETE record; TXT verify: `dig +short TXT <domain>` sau khi ghi | confirm |
| `waf` | Thêm rule: `POST /zones/<id>/rulesets/<rs>/rules`; sửa: `PATCH` đúng 1 rule, gửi đủ field. KHÔNG `PUT` entrypoint khi đã có rule (xoá rule khác); `PUT` chỉ khi phase chưa có ruleset (404) | confirm |
| `bots` | `bot_management` (ai_bots_protection, robots.txt managed): PUT **mỗi lần 1 field**; probe lại UA sau ~30s | confirm |
| `cache` | Purge theo URL/host/tag; purge everything cần nhắc tác động tải origin | confirm |
| `access` | Zero Trust/Access app, policy, MCP portal, service token, tunnel ingress (backup config, validate `OK` trước restart; báo trước gián đoạn) | confirm |

## Quy tắc an toàn

- Trước ghi WAF: lưu ruleset hiện tại ra backup ngoài repo (`before/`), sau ghi lưu `after/`. Dry-run diff trước, `--apply` sau confirm. Sau ghi: đọc lại live và probe.
- Xoá rule → chỉ disable, ghi tên rule vào báo cáo. Không xoá record/rule do project khai báo "giữ" trong targets.
- Không publish hostname cho service nội bộ trước khi Access policy chặn đã active và verify `401`/redirect khi chưa đăng nhập.
- Đổi SSL, security level, Bot Fight Mode, nâng gói trả phí/nhập thẻ: ngoài phạm vi trừ khi user yêu cầu rõ; gói trả phí → dừng hỏi.
- Trang có secret (service token, client secret): không print text trang kể cả qua regex; parse trong script, ghi thẳng file env (umask 077), chỉ in `SAVED`/độ dài.
- Chạy thử nhiều lần: cache response, không spam API.
