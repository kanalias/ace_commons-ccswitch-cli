---
name: system-ott
description: Inbound OTT (Telegram, Slack, Teams, WhatsApp...) BẮT BUỘC qua dispatchInbound() của @acegalaxy/lib-ott-gateway (5 security layer, audit log); outbound exempt, theo mục service-alert của general. LAZY, load khi chạm code OTT/telegram.
status: live
updated: 2026-10-13
paths:
  - "src/**"
  - "**/*telegram*"
  - "**/*ott*"
metadata:
  type: reference
---

# OTT Gateway — mọi inbound OTT BẮT BUỘC qua gateway

Mọi code xử lý **inbound message** từ nền tảng OTT (Telegram, WhatsApp, MS Teams, WeChat, Slack, Discord...) PHẢI đi qua gateway. Gateway là git-dependency `@acegalaxy/lib-ott-gateway` (pin tag, cài theo mục "Lib `@acegalaxy/*`" của [[general]]), project KHÔNG tự implement gateway in-repo.

## Scope

**Áp dụng — inbound only** (user → bot → hệ thống), BẮT BUỘC qua `dispatchInbound()`:
- Message từ user (`/command`, text, media) qua polling `getUpdates` hoặc webhook.
- Callback query, inline query, `my_chat_member`, `chat_member` update.
- Audit log (L5) bắt buộc cho mọi inbound.

**Outbound — EXEMPT** (bot → user/chat): `sendMessage`, `editMessageText`, `answerCallbackQuery`, `setMyCommands`, `getMe`... Outbound không bắt buộc qua gateway. Alert/báo cáo service gửi qua Telegram theo mục "Telegram service alert" của [[general]] — không lặp lại format ở đây.

**Không áp dụng:** webhook non-OTT (payment, git host, email) — có security layer riêng; IPC nội bộ (CLI → daemon).

**Marker trong code:** đường outbound có thể ghi inline comment `// outbound <action> — exempt (inbound-only rule)` để audit grep nhận ra.

## Shared gateway qua git dependency

Mọi callsite `require("@acegalaxy/lib-ott-gateway")` hoặc subpath của nó (`.../adapters/telegram`...) là consume qua dependency chính thức (`node_modules`) — **hợp lệ, KHÔNG phải cross-project deep-import bị cấm**.

**Update gateway = 1 nơi:** sửa repo lib → build + commit dist → tag mới → bump `#vX.Y.Z` trong `package.json` của project → `npm install` (kiểm lockfile `resolved` là `git+ssh://…`). Pin tag an toàn hơn auto-latest.

## 5 security layers (BẮT BUỘC đủ — implement trong lib, project consume qua entry point)

```text
┌─────────────────────────────────────────────────────────┐
│ L1 — Adapter (platform-specific)                        │
│     - Verify signature/webhook secret                   │
│     - Parse raw payload → normalized InboundMessage     │
└────────────┬────────────────────────────────────────────┘
             ▼
┌─────────────────────────────────────────────────────────┐
│ L2 — Identity Resolver                                  │
│     - platform-userid → internal identity               │
│     - Reject unknown identity (default-deny)            │
└────────────┬────────────────────────────────────────────┘
             ▼
┌─────────────────────────────────────────────────────────┐
│ L3 — Authz (role-based + ACL)                           │
│     - Default-deny, whitelist per command/chat/platform │
└────────────┬────────────────────────────────────────────┘
             ▼
┌─────────────────────────────────────────────────────────┐
│ L4 — Rate Limit + Replay Guard                          │
│     - Per-identity quota + message_id dedup             │
└────────────┬────────────────────────────────────────────┘
             ▼
┌─────────────────────────────────────────────────────────┐
│ L5 — Audit Log (append-only, persistent)                │
│     - Log EVERY inbound + outcome (allow/deny/error)    │
└────────────┬────────────────────────────────────────────┘
             ▼
   ✅ Handoff to business logic (skills, commands, ...)
```

## Entry point — `dispatchInbound()`

```js
const { dispatchInbound } = require("@acegalaxy/lib-ott-gateway");

const outcome = await dispatchInbound(rawPayload, "telegram", headers);
// outcome.allowed === true  → handoff to business logic
// outcome.allowed === false → outcome.denyReason
```

## Audit log

- Mỗi inbound (allow hay deny) PHẢI để lại 1 dòng `OutcomeRecord` — lib tự ghi, append-only.
- Path mặc định của lib resolve vào thư mục log sẵn có của project; chỉ override khi path mặc định không ghi được.
- Retention: không xoá (archive thì được).

## Cấm tuyệt đối

- ❌ `require('node-telegram-bot-api')` (hoặc SDK OTT khác: `@slack/bolt`, `@microsoft/teams`...) NGOÀI package `@acegalaxy/lib-ott-gateway`.
- ❌ Parse raw webhook payload ngoài lib.
- ❌ Bypass identity resolution / authz / audit log.
- ❌ Skip audit log cho bất kỳ inbound nào — kể cả message "test".

## Audit trước commit (bắt buộc)

Lệnh dưới target `src/`; chỉnh theo thư mục source thật của project.

```bash
# SDK OTT import ngoài lib
grep -rn "node-telegram-bot-api\|@slack/bolt\|@microsoft/teams" src/ \
  --include="*.js" --include="*.ts"

# gọi thẳng Bot API ở code inbound (outbound exempt đã đánh marker thì bỏ qua)
grep -rn "api.telegram.org" src/ --include="*.js" --include="*.ts"
```

Match ngoài đường outbound exempt → fix hoặc dừng hỏi user.

## Thêm platform mới

Implement adapter + verify signature + authz policy trong repo lib, bump tag, `npm install` ở project. Không viết adapter OTT in-repo.

Liên quan: [[general]] (outbound service alert, lib `@acegalaxy/*`), [[secrets-no-printout]] (bot token).
