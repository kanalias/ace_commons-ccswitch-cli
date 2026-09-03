# ccswitch — Cơ chế & Setup (dev handoff)

> Tài liệu kỹ thuật đầy đủ cho team dev. README.md là quickstart cho người dùng cuối; file này giải thích **cơ chế bên trong**, **auto-switch**, **giới hạn**, và **cách test**.
>
> **Last updated:** 2026-07-27

---

## 1. ccswitch là gì

CLI đổi endpoint auth của **Claude Code** giữa nhiều "profile" — chỉ thay block `env` trong `settings.json`, giữ nguyên phần còn lại (hooks, permissions, statusLine…).

5 target (theo thứ tự ưu tiên fallback):

| Target | Cơ chế | Vai trò |
|---|---|---|
| `claude` | `env` = base 9router + token + model `cc/*` | ⭐ DEFAULT — claude qua remote router |
| `codex` | cùng base 9router + **cùng token** + model `cx/*` | Codex/GPT qua 9router |
| `deepseek` | cùng base 9router + **cùng token** + model `ds/*` | DeepSeek qua 9router |
| `kimi` | cùng base 9router + **cùng token** + model `kimi/*` | Kimi qua 9router |
| `subscription` | **gỡ block `env`** khỏi `settings.json` | Safe-harbor fallback (cuối cùng) — Claude Code dùng OAuth subscription login, **không cần key** |

`claude` / `codex` / `deepseek` / `kimi` dùng **CÙNG base URL** `https://9router.proxy.example.com/v1` qua 9router **và CÙNG 1 token** (điền giống nhau vào cả 4 profile); chỉ khác block `ANTHROPIC_DEFAULT_*_MODEL` (prefix `cc/` vs `cx/` vs `ds/` vs `kimi/`). Vì chung 1 router, router chết = cả 4 chết → fallback duy nhất là `subscription`.

> **Kimi direct-endpoint mode (phụ):** khi `.env` có `kimi_api_key_force_subscription=1` + `kimi_api_key`, `setup` ghi `kimi.json` trỏ thẳng endpoint Anthropic-compatible của Kimi `https://api.moonshot.ai/anthropic` (key Kimi riêng, bypass 9router). `ccswitch.sh` xử riêng case `*moonshot.ai*` cho URL `/models` và `/v1/messages` khi probe. Mặc định (`=0`) → kimi đi qua 9router như 3 target còn lại.

Phân biệt các target khi cùng base URL:

> **Phân biệt target:** URL các profile giống nhau nên `current()`/hook không đọc URL để nhận diện — đọc **model prefix** (`.env.ANTHROPIC_DEFAULT_OPUS_MODEL` trong settings.json): `cx/*`=codex, `ds/*`=deepseek, `kimi/*`=kimi, `cc/*`=claude.

`subscription` KHÔNG phải profile file — nó là *sự vắng mặt* của block `env`. Không có URL để probe, không có key; là terminal luôn về được. Alias tương thích ngược: `original` / `direct` / `clear` → `subscription`.

> **2026-07-15:** (a) tier `local` (`http://127.0.0.1:20128/v1`) đã gỡ. (b) fallback đổi từ `original` (Anthropic-direct + `ANTHROPIC_API_KEY`) → `subscription` (clear env / OAuth) — đồng bộ với chủ trương "fallback luôn dùng subscription, không dùng API key".

---

## 2. Claude Code đọc endpoint từ đâu — thứ tự ưu tiên (QUAN TRỌNG)

Đây là điểm hay gây nhầm. Claude Code lấy `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` theo thứ tự (cao → thấp):

```
1. Process env      (biến shell export TRƯỚC khi chạy `claude`)   ← THẮNG TẤT CẢ
2. settings.local.json  .env   (project-scoped, gitignored)
3. settings.json        .env   (project shared, hoặc ~/.claude global)
4. (không có) → Claude Code OAuth subscription login mặc định
```

Hệ quả thực tế:

- **Env đã export trong terminal đè mọi file settings.** Nếu terminal có `ANTHROPIC_BASE_URL=...` (do rc file, launchctl, hoặc export tay), ccswitch sửa `settings.json` sẽ **không có tác dụng**. Kiểm tra: `env | grep ANTHROPIC`.
- **Env nạp lúc process khởi động**, không đọc lại giữa chừng → **phải restart Claude Code** (quit + mở lại) sau mỗi lần switch.
- ccswitch có 2 chế độ target (xem §3): global `~/.claude/settings.json` (mặc định của module) hoặc project `.claude/settings.local.json` (bản project-scoped).

---

## 3. Kiến trúc file

```
ccswitch-cli-claude/
├── README.md                    # quickstart người dùng
├── MECHANISM.md                 # tài liệu này (dev handoff)
├── install-9router-proxy.sh     # entry point Phần 1, tự detect OS
├── install-harness.sh  # entry point Phần 2 — thin wrapper, exec harness/install.sh
├── install-auto-compact.sh      # Phần 3 — chỉnh autoCompactWindow / DISABLE_AUTO_COMPACT trong settings.json (đứng riêng)
├── install-optimize-claude.sh   # Phần 4 — disableWorkflows từ .env, ghi settings.json (đứng riêng)
├── ai-proxy/
│   ├── ccswitch.sh            # CLI mac/linux — target ~/.claude/settings.json
│   ├── ccswitch.ps1           # CLI windows (PowerShell) — parity với .sh
│   ├── setup.sh               # installer mac/linux
│   ├── setup.ps1              # installer windows
│   ├── statusline-context.sh  # statusLine script hiển thị context-window usage
│   ├── kimi-anthropic-adapter.py  # adapter local (chỉ dùng cho direct-endpoint mode nếu cần; mặc định kimi đi qua 9router)
│   ├── hooks/
│   │   └── check-router.sh    # SessionStart hook: probe + AUTO-SWITCH khi down
│   └── profiles/              # TEMPLATE placeholder key (an toàn commit)
│       ├── claude.json       # claude cc/*
│       ├── codex.json        # codex cx/*  (cùng key với claude.json)
│       ├── deepseek.json     # deepseek ds/*  (cùng key với claude.json)
│       └── kimi.json         # kimi kimi/*  (cùng key; direct-endpoint mode nếu force-subscription)
│                              # subscription không có file — env-clear
├── harness/           # Phần 2 — cài orchestrator+delegate mechanism vào project KHÁC
│   ├── install.sh              # installer thật (install-harness.sh chỉ exec file này)
│   └── templates/              # nguồn @@TOKEN@@ template, copy+substitute vào project đích
│       ├── agents/delegate-{codex,deepseek,gemini,sonnet}.md
│       ├── hooks/{pre-edit-orchestrator-gate,pre-bash-orchestrator-gate,pre-edit-secret-scan,post-edit-syntax-check,session-start-banner}.sh
│       ├── scripts/delegate/{_common,run-aider-deepseek,run-codex,run-gemini,doctor}.sh + lib/
│       ├── commands/*.md                 # 12 slash command
│       ├── skills/{lazy-load-health,dep-ladder-check,auto-commit,check-hardcode,audit-git-leak,fix-ledger}/SKILL.md
│       ├── rules/{common,project}/*.md   # common (8 guardrail) + project (git-workflow, skill-superpowers)
│       └── git-hooks/pre-push            # gitleaks scan trước push (cài vào .git/hooks/ project đích)
├── scripts/delegate/            # bản wrapper THẬT dùng trong repo này (đồng bộ nội dung với harness/templates/scripts/delegate/)
│   ├── _common.sh               # source chung: resolve API key theo thứ tự DEEPSEEK_API_KEY → PROXY_DEEPSEEK_API_KEY → deepseek_api_key
│   ├── run-aider-deepseek.sh    # Aider + DeepSeek, worktree isolation, --no-auto-commits
│   ├── run-codex.sh             # Codex CLI (o-series) wrapper
│   ├── run-gemini.sh            # Gemini CLI wrapper — gọi thẳng CLI (không probe, không account rotation)
│   ├── doctor.sh                # preflight check: CLI cài chưa, git repo chưa, env key resolve chưa — không sửa gì
│   └── lib/                     # python sitecustomize helper dùng chung
├── .claude/                     # harness bản THẬT của repo này (đồng bộ với harness/templates/)
│   ├── agents/delegate-{codex,deepseek,gemini,sonnet}.md  # persona 4 delegate subagent
│   ├── hooks/*.sh               # 6 hook: pre-edit-gate, pre-bash-gate, secret-scan, syntax-check, session-banner, session-limit
│   ├── commands/*.md            # 12 slash command
│   ├── skills/{lazy-load-health,dep-ladder-check,auto-commit,check-hardcode,audit-git-leak,fix-ledger}/SKILL.md
│   └── rules/{common,project}/*.md  # common (8 guardrail overwrite khi re-sync) + project (giữ nguyên)
└── test/                        # 9 file bats, 130 test — xem §8
```

Sau `setup.sh`, các file được cài vào `~/.claude/`:

```
~/.claude/
├── ccswitch.sh                 # copy từ module (refresh mỗi lần setup)
├── hooks/check-router.sh       # copy từ module
├── profiles/*.json             # copy CHỈ KHI thiếu (không đè key thật)
└── settings.json               # được wire hook + đổi block env
```

---

## 4. Lệnh ccswitch

```bash
ccswitch              # effective source (tầng nào đang thắng §2, tag theo model prefix) + health + verify subscription
ccswitch claude       # switch → Claude qua 9router (cc/*)
ccswitch codex        # switch → Codex/GPT qua 9router (cx/*)
ccswitch deepseek     # switch → DeepSeek qua 9router (ds/*)
ccswitch kimi         # switch → Kimi qua 9router (kimi/*)
ccswitch subscription # gỡ block env → Claude Code OAuth subscription login
ccswitch check        # probe health các profile (claude/codex/deepseek/kimi) + verify subscription
ccswitch fallback     # giữ target đang active nếu router healthy; router chết → subscription (safe-harbor)
ccswitch set-key [p]  # nhập key mới (ẩn) cho profile p (mặc định claude; claude/codex/deepseek/kimi share CHUNG 1 token — chạy set-key lại cho các target còn lại với CÙNG giá trị, hoặc dùng `ccswitch update` để sync) rồi apply
ccswitch update [src] # đồng bộ ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN từ profile src (mặc định claude)
                       #   sang các profile còn lại trong ORDER — hỏi [y/N] trước khi ghi đè TỪNG file;
                       #   chỉ copy 2 field host/key, KHÔNG đụng ANTHROPIC_DEFAULT_*_MODEL (giữ prefix riêng)
ccswitch clear        # alias của subscription (gỡ block env)
```

Mỗi lần `apply`/clear tạo backup `settings.json.bak`. Health probe:
- Router (`9router`): `GET {base}/models` + `Authorization: Bearer <token>`. Timeout 4s → coi như `000` (down).
- `subscription`: KHÔNG probe HTTP (không có URL/key — là env-clear) NHƯNG **verify OAuth credential** để biết safe-harbor có thật sự cứu được không (§6 điều kiện):
  - mac → Keychain service `Claude Code-credentials`
  - linux → `~/.claude/.credentials.json`
  - Có credential → `✓ logged in (email, subscriptionType) [nguồn]`. Email lấy từ `~/.claude.json` `.oauthAccount`, `subscriptionType` từ credential.
  - Không → `✗ NO OAuth credential — safe-harbor will prompt login on first use`. Đây là cảnh báo thật: nếu fallback về subscription mà chưa từng login, Claude sẽ hiện màn đăng nhập.
  - KHÔNG in token — chỉ metadata.

---

## 5. Auto-switch khi timeout / lỗi

Hook `hooks/check-router.sh` chạy ở sự kiện **SessionStart** (đã wire vào `settings.json` bởi `setup.sh`).

**Banner (LUÔN in đầu session):** mỗi lần mở session hook in ngay: endpoint đang chạy (đọc `$ANTHROPIC_BASE_URL` env — endpoint session thực dùng — fallback settings.json), thứ tự fallback, và lệnh sơ lược. Ví dụ:

```
━━━ ccswitch ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Endpoint đang chạy: claude (via 9router)  (https://9router.proxy.example.com/v1)
  Fallback (khi router chết): claude/codex/deepseek → subscription (OAuth)
    • subscription = safe-harbor: gỡ env → Claude Code dùng OAuth login (luôn về được)
  Lệnh: ccswitch [check | claude | codex | deepseek | subscription | fallback | clear]
        đổi endpoint xong → RESTART Claude Code (env nạp lúc khởi động)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ health=200 OK
```

### Flow

```
SessionStart
   │
   ▼
đọc .env.ANTHROPIC_BASE_URL từ settings.json
   │
   ├─ base KHÔNG phải router (9router) → exit 0 (bỏ qua)
   │
   ▼
probe {base}/models  (curl -m 4)
   │
   ├─ health = 200 → exit 0 (khỏe, không làm gì)
   │
   ▼ (health ≠ 200: timeout=000 hoặc error code)
   ├─ CCSWITCH_NO_AUTO=1  hoặc  ccswitch.sh không executable
   │     → chỉ CẢNH BÁO (warn-only, hành vi cũ) → exit 0
   │
   ▼ (auto-switch enabled)
   chạy `ccswitch fallback`
   │
   ├─ router hiện tại (claude/codex/deepseek) healthy? → apply, xong
   └─ router chết → apply `subscription` (gỡ block env, safe-harbor, KHÔNG probe)
        → Claude Code dùng OAuth subscription login, không bao giờ kẹt trên router chết
        → không cần key: subscription là env-clear, luôn thành công
```

### Giới hạn (đọc kỹ — tránh hiểu nhầm)

1. **Không heal session hiện tại ngay.** Env nạp lúc process launch, **trước** khi hook chạy. Switch trong hook ghi `settings.json` cho lần mở **kế tiếp**. Session đang mở vẫn dùng endpoint cũ đến khi **Reload Window / restart Claude Code**. → lần đầu gặp outage bạn mất 1 nhịp; các session sau tự đúng.
2. **Không cover mid-session.** Đang chat mà API timeout/lỗi → hook KHÔNG chạy lại (nó chỉ ở SessionStart). Claude Code không expose hook "on API error". Muốn zero-downtime giữa phiên → phải để **router upstream-failover** lo (việc của service router, không phải ccswitch).
3. **Chỉ engage khi đang ở router.** Nếu đang `subscription` (không có env block) thì hook bỏ qua — không có "cấp trên" để fallback tới.

### Tắt auto-switch (về warn-only)

```bash
export CCSWITCH_NO_AUTO=1
```

---

## 6. Fallback chain & safe-harbor (KHÔNG để Claude chết)

Thứ tự: **router hiện tại (claude/codex/deepseek) → subscription**.

- **router (claude/codex/deepseek)**: giữ target đang active nếu probe **200** (fallback không ép về claude khi bạn đang ở codex/deepseek).
- **`subscription` = SAFE-HARBOR cuối cùng**: nếu router chết, `fallback` **luôn apply `subscription`** = gỡ block `env` khỏi `settings.json`. Không probe, không cần key. Claude Code quay về **OAuth subscription login gốc** → luôn về được, không bao giờ kẹt trên router chết. (4 target chung 1 router 9router → router chết là cả 4 chết.)

- ✅ Đã test (xem §8): fallback bỏ qua router chết rồi gỡ env block; `settings.json` không còn `.env` → Claude Code dùng subscription.

⚠️ **Điều kiện để safe-harbor thật sự cứu Claude:** máy đã **đăng nhập OAuth subscription** (chạy `claude` + login ít nhất 1 lần). subscription chỉ gỡ endpoint override — nó KHÔNG tự tạo phiên login. Nếu chưa từng login, Claude Code sẽ nhắc đăng nhập lần đầu.

```bash
ccswitch subscription   # gỡ env block
claude                  # nếu chưa login → làm theo prompt OAuth
```

Không có key nào để điền — đây chính là điểm khác `original` cũ: fallback dùng subscription (OAuth), không dùng `ANTHROPIC_API_KEY`.

---

## 6b. Chạy nhiều vendor song song (`spawn`)

`ccswitch <target>` sửa 1 block `env` trong `settings.json` → **1 instance = 1 model**. Nhiều vendor active cùng lúc là **bất khả trong 1 process** (nó chỉ đọc 1 `ANTHROPIC_DEFAULT_OPUS_MODEL`). Muốn song song → **nhiều process**, mỗi cái pin 1 vendor.

`spawn` dựa vào **precedence §2**: process env là **tầng ①**, thắng mọi settings file. Nên thay vì ghi `settings.json`, `spawn` export model vào env của chính shell rồi `exec claude`:

```text
spawn deepseek:
  1. đọc profiles/deepseek.json
  2. export ANTHROPIC_BASE_URL / _AUTH_TOKEN / _DEFAULT_*_MODEL  (ds/*)  vào process env
  3. printf title "claude:deepseek"  (phân biệt terminal)
  4. exec claude   → instance mới thừa kế env → chạy DeepSeek
```

`settings.json` **không bị đụng** → switch-in-place hiện tại (dù đang ở target nào) giữ nguyên. Không cần restart: instance vừa sinh đã pin sẵn.

```text
Terminal 1: claude-cc   (spawn claude)   → process env cc/*  → Claude    } 3 vendor
Terminal 2: claude-cx   (spawn codex)    → process env cx/*  → Codex/GPT } đồng thời
Terminal 3: claude-ds   (spawn deepseek) → process env ds/*  → DeepSeek  }
                         settings.json    ← KHÔNG đổi (vẫn target switch-in-place cũ)
```

- `subscription` **không spawn được**: nó là env-clear (gỡ block), không có gì để export → `spawn subscription` báo lỗi, hướng dẫn dùng `ccswitch subscription` + `claude` thường.
- Binary resolve qua `command -v claude` (fallback `~/.local/bin/claude`) — **không** dựa alias `claude` (user có thể có alias cũ bị override).
- Alias tiện: `setup` tạo `claude-cc` / `claude-cx` / `claude-ds` (short-name cc/cx/ds).

⚠️ **Quota chung.** 4 target = 1 account 9router = **1 quota**. Song song 4 = đốt nhanh ~4×. Chung 1 token, KHÔNG tách quota (1 email = 1 quota). Tách thật cần account 9router khác email — ngoài phạm vi ccswitch.

---

## 7. Setup

### macOS / Linux

```bash
cd ccswitch-cli-claude
bash ai-proxy/setup.sh
# điền token: $EDITOR ~/.claude/profiles/claude.json
source ~/.zshrc && ccswitch claude
# restart Claude Code
```

Yêu cầu: `jq` + `curl` (`brew install jq` / `apt install -y jq curl`).

**Điền key nhanh qua `.env`** (gitignored, ở repo root):

```bash
proxy_host=https://9router.proxy.example.com/v1
proxy_key=<your-9router-key>

# optional: Kimi direct-endpoint mode (bypass 9router, hit api.moonshot.ai)
kimi_api_key_force_subscription=1
kimi_api_key=<your-kimi-key>
```

Nếu file có đủ cả 2 biến, `setup.sh`/`setup.ps1` **ghi thẳng** cả `proxy_host` lẫn `proxy_key` vào cả 4 profile (`claude`/`codex`/`deepseek`/`kimi`) — không hỏi, `.env` là source of truth (ghi đè cả profile đã có key thật, in thông báo overwrite). Nếu `kimi_api_key_force_subscription=1` + `kimi_api_key` có mặt → `kimi.json` ghi riêng endpoint Kimi thật thay vì 9router. Thiếu 1 trong 2 biến `proxy_*` → bỏ qua, coi như không có `.env`.

### Windows (PowerShell)

```powershell
cd ccswitch-cli-claude
powershell -ExecutionPolicy Bypass -File .\ai-proxy\setup.ps1
```

> Hook health-check dùng `bash` (Git Bash / WSL). Không có bash → hook tự bỏ qua, `ccswitch` vẫn chạy (mất auto-switch).

`setup` là idempotent: refresh tool+hook, chỉ copy profile khi thiếu (không đè key thật), wire hook SessionStart 1 lần, thêm alias `ccswitch`.

---

## 8. Cách test (tái lập được)

Test **không đụng `~/.claude` thật** — dùng `HOME` sandbox tạm. Đây là các test đã chạy khi build tính năng auto-switch.

### 8.1 Syntax

```bash
bash -n ai-proxy/ccswitch.sh && bash -n ai-proxy/hooks/check-router.sh
```

### 8.2 Fallback tới safe-harbor: 9router chết → gỡ env block

Ý tưởng: cho 9router trỏ port chết → xác nhận fallback gỡ block `env` (subscription), `settings.json` không còn `.env`.

```bash
T=$(mktemp -d)/home; mkdir -p "$T/.claude/profiles" "$T/.claude/hooks"
cp ai-proxy/ccswitch.sh "$T/.claude/ccswitch.sh"; chmod +x "$T/.claude/ccswitch.sh"
cp ai-proxy/hooks/check-router.sh "$T/.claude/hooks/"; chmod +x "$T/.claude/hooks/check-router.sh"
printf '{"ANTHROPIC_BASE_URL":"https://proxy.example.com:9/v1","ANTHROPIC_AUTH_TOKEN":"x"}\n' > "$T/.claude/profiles/9router.json"
printf '{"permissions":{"allow":["Bash(*)"]},"env":{"ANTHROPIC_BASE_URL":"https://proxy.example.com:9/v1"}}\n' > "$T/.claude/settings.json"

HOME="$T" bash "$T/.claude/hooks/check-router.sh"
jq -e '.env == null' "$T/.claude/settings.json" && echo "PASS: env block removed"   # EXPECT: PASS
jq -e '.permissions != null' "$T/.claude/settings.json" && echo "PASS: rest intact"  # phần còn lại giữ nguyên
```

Kết quả mong đợi: hook in `router (...) health=... — có thể đang DOWN` rồi auto-switch `→ safe-harbor: subscription (OAuth)`, và `settings.json` mất `.env` nhưng giữ nguyên `permissions`/hooks. → **fallback safe-harbor chạy đúng**.

### 8.3 set-key subscription bị từ chối

```bash
HOME="$T" bash "$T/.claude/ccswitch.sh" set-key subscription; echo "exit=$?"
# EXPECT: ❌ ... no key to set ... + exit=1
```

### 8.4 Tắt auto-switch

```bash
HOME="$T" CCSWITCH_NO_AUTO=1 bash "$T/.claude/hooks/check-router.sh"
# EXPECT: chỉ cảnh báo, KHÔNG switch
```

> subscription là env-clear (OAuth) — không cần key nào để test. Mock server không còn cần thiết như bản `original` cũ.

### 8.5 Codex / DeepSeek target — apply đúng model prefix + tag đúng tên

```bash
T=$(mktemp -d)/home; mkdir -p "$T/.claude/profiles"
cp ai-proxy/ccswitch.sh "$T/.claude/ccswitch.sh"; chmod +x "$T/.claude/ccswitch.sh"
for p in claude codex deepseek; do cp ai-proxy/profiles/$p.json "$T/.claude/profiles/"; done
printf '{"permissions":{"allow":["Bash(*)"]}}\n' > "$T/.claude/settings.json"

# apply claude → settings.json có model cc/*
HOME="$T" bash "$T/.claude/ccswitch.sh" claude >/dev/null
jq -e '.env.ANTHROPIC_DEFAULT_OPUS_MODEL | startswith("cc/")' "$T/.claude/settings.json" >/dev/null && echo "PASS: claude applied (cc/*)"
# status phân biệt đúng claude qua model prefix (KHÔNG qua URL — 3 base giống nhau)
HOME="$T" bash "$T/.claude/ccswitch.sh" status | grep -qi 'claude' && echo "PASS: current tags claude"

# apply codex → cx/*
HOME="$T" bash "$T/.claude/ccswitch.sh" codex >/dev/null
jq -e '.env.ANTHROPIC_DEFAULT_OPUS_MODEL | startswith("cx/")' "$T/.claude/settings.json" >/dev/null && echo "PASS: codex applied (cx/*)"
HOME="$T" bash "$T/.claude/ccswitch.sh" status | grep -qi 'codex' && echo "PASS: current tags codex"

# apply deepseek → ds/*
HOME="$T" bash "$T/.claude/ccswitch.sh" deepseek >/dev/null
jq -e '.env.ANTHROPIC_DEFAULT_OPUS_MODEL | startswith("ds/")' "$T/.claude/settings.json" >/dev/null && echo "PASS: deepseek applied (ds/*)"
```

Kết quả mong đợi: 5 dòng PASS. Xác nhận target phân biệt bằng model prefix, không phải URL (các profile chung base 9router).

### 8.6 `spawn` — export đúng model prefix + KHÔNG đụng settings.json

```bash
T=$(mktemp -d)/home; mkdir -p "$T/.claude/profiles" "$T/bin"
cp ai-proxy/profiles/deepseek.json "$T/.claude/profiles/"
sed -i '' 's/<your-9router-key>/sk-test/' "$T/.claude/profiles/deepseek.json" 2>/dev/null || \
  sed -i 's/<your-9router-key>/sk-test/' "$T/.claude/profiles/deepseek.json"
cp ai-proxy/ccswitch.sh "$T/.claude/ccswitch.sh"

# stub `claude` in dumps ANTHROPIC_* env → chứng minh spawn export ds/*
printf '#!/usr/bin/env bash\nenv | grep ^ANTHROPIC_ | sort\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
HOME="$T" PATH="$T/bin:$PATH" bash "$T/.claude/ccswitch.sh" spawn deepseek 2>&1 \
  | grep -q 'ANTHROPIC_DEFAULT_OPUS_MODEL=ds/deepseek-v4-pro-max' && echo "PASS: spawn exports ds/*"

# spawn subscription → reject
HOME="$T" bash "$T/.claude/ccswitch.sh" spawn subscription 2>&1 \
  | grep -qi 'subscription\|real target' && echo "PASS: spawn subscription rejected"

# settings.json KHÔNG bị đụng bởi spawn
printf '{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"cc/claude-opus-4-8"}}\n' > "$T/.claude/settings.json"
b=$(cat "$T/.claude/settings.json")
HOME="$T" PATH="$T/bin:$PATH" bash "$T/.claude/ccswitch.sh" spawn deepseek >/dev/null 2>&1
[ "$b" = "$(cat "$T/.claude/settings.json")" ] && echo "PASS: settings.json untouched by spawn"
```

Kết quả mong đợi: 3 dòng PASS. `spawn` chỉ tác động process env, giữ nguyên settings switch-in-place.

### 8.7 `.env` flow trong `setup.sh`/`setup.ps1`

Covered bởi `test/setup-env-pro.bats` (7 test, chạy trên repo được stage vào thư mục tạm với `.env` giả — không bao giờ đụng `.env` thật của máy): áp mặc định Yes (interactive Enter + non-interactive), bỏ qua khi thiếu `proxy_host`/`proxy_key`, bỏ qua khi thiếu file, **không ghi đè** khi 1 profile đã có key thật, và trả lời `n` rơi đúng về flow nhập tay (host rồi key).

### 8.8 Toàn bộ bats suite — 130 test / 9 file

```bash
bats test/*.bats
```

| File | # test | Phủ |
|---|---|---|
| `ccswitch.bats` | 22 | `ccswitch.sh` — apply/status/spawn/set-key/update, model prefix per target |
| `delegate-scripts.bats` | 19 | `scripts/delegate/*.sh` — key resolution order, worktree isolation, `--no-auto-commits` |
| `doctor.bats` | 4 | `scripts/delegate/doctor.sh` — preflight check: CLI present, git repo, env key resolve, không leak secret value |
| `install-auto-compact.bats` | 32 | `install-auto-compact.sh` — `set`/`auto`/`off`/`on`/`status`, `--global`/`--project`, validate `jq`, tạo file + giữ JSON toàn vẹn |
| `install-harness.bats` | 6 | `harness/install.sh` — cài đủ nhóm mặc định, idempotent khi chạy lại 2 lần (không tạo hook trùng trong `settings.json`) |
| `install-wrappers.bats` | 4 | `install-9router-proxy.sh` — dispatch logic theo `$OSTYPE`, lỗi rõ khi thiếu `cygpath` trên `msys` |
| `setup-env-pro.bats` | 9 | xem §8.7 |
| `setup-ps1-parity.bats` | 5 | `ai-proxy/setup.ps1` — parity `.env` apply + wire settings/statusLine (skip nếu máy không có `pwsh`) |
| `statusline-context.bats` | 29 | `ai-proxy/statusline-context.sh` — JSON stdin → progress bar + %, làm tròn token, màu theo ngưỡng, default khi thiếu field |

Không có test nào đụng `$HOME` hay `.claude/` thật của máy chạy CI/dev — tất cả sandbox qua `$BATS_TEST_TMPDIR`.

---

## 9. Troubleshoot

| Triệu chứng | Nguyên nhân / xử lý |
|---|---|
| Switch xong không đổi | Chưa restart Claude Code. Quit hẳn rồi mở lại. |
| `env | grep ANTHROPIC` có giá trị lạ | Process env đang đè settings (§2). `unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN` hoặc quit hẳn VSCode/terminal rồi mở lại. |
| `check` báo `000 DOWN` nhưng endpoint sống | IPv6 route hỏng — Node né sang IPv4 nên vẫn chạy; chỉ curl kẹt. Verify: `curl -4 ... /v1/models`. Muốn dứt điểm: pin IPv4 vào `/etc/hosts`. |
| `model_not_found` | Với 9router model phải có prefix `cc/` (vd `cc/claude-opus-4-8`). Ở `subscription` (env-clear) Claude Code tự dùng model tài khoản, không prefix. |
| Sau `ccswitch subscription` Claude đòi login | subscription = OAuth; máy chưa từng login. Chạy `claude` + làm theo prompt đăng nhập. Không có key để điền. |
| Auto-switch spam mỗi lần mở | Endpoint active đang down thật. Sửa router hoặc `ccswitch <profile khỏe>`. Tạm tắt: `export CCSWITCH_NO_AUTO=1`. |
| Khôi phục settings | `cp ~/.claude/settings.json.bak ~/.claude/settings.json` |

---

## 10. Bảo mật

- `profiles/*.json` trong `~/.claude/` chứa token thật → **local only, không commit**.
- Template trong repo chỉ có placeholder `<your-...>`.
- `setup` không bao giờ đè profile đã có key.
- Token không bao giờ được truyền qua CLI arg / prompt; chỉ nằm trong file profile + header `Authorization` khi probe.

---

## 11. Changelog

- **2026-07-31** — **Xoá `check-session-limit.sh` — hook advisory vô dụng.** Hook in cảnh báo ra stderr nên model không đọc được (chỉ user thấy trong terminal, không vào context) — không tạo tác dụng gate thật. Đồng thời proxy đo transcript-size sai lệch sau auto-compact (transcript reset nhưng hook vẫn cộng dồn theo file cũ), và nội dung cảnh báo trùng lặp hoàn toàn với rule `token-budget.md` (đã always-load, cùng ngưỡng ~200K). Xoá hẳn thay vì sửa lại: rule đã cover, hook chỉ là lớp advisory thừa. Files: xoá `.claude/hooks/check-session-limit.sh` + `harness/templates/hooks/check-session-limit.sh`; gỡ wiring `UserPromptSubmit` khỏi `.claude/settings.json`; gỡ nhóm cài `SEL_SESSIONLIMIT`/`HARNESS_GROUP_SESSIONLIMIT` + toàn bộ logic liên quan khỏi `harness/install.sh`; cập nhật `CLAUDE.md` + README.md + MECHANISM.md (bỏ reference hook, giữ nguyên changelog lịch sử 2026-07-20).
- **2026-07-27** — **Đồng bộ README + MECHANISM với state hiện tại + `kimi` 9router-native.** (1) `kimi` giờ là router-target thứ 4 chung base 9router + chung token (`ORDER=(claude codex deepseek kimi)`, model prefix `kimi/*`), bỏ local adapter làm default — direct-endpoint mode (`api.moonshot.ai/anthropic`) còn lại như optional qua `.env` `kimi_api_key_force_subscription=1` (refactor d8f30a4). Docs cập nhật: 5 target (4 router + subscription), 4 profile, `claude-km` spawn alias, bảng model prefix `cc/`/`cx/`/`ds/`/`kimi/`. (2) README restructure 5-part → 4-part: ccswitch endpoint switcher / harness / auto-compact-window / optimize-claude; gỡ 2 phần cũ (`install-claude-memory.sh`+`ai-memory-rules/`, `install-git-hooks.sh`+`dev-hooks/`) — đã fold vào harness group RULES + GITHOOKS. (3) MECHANISM §3 file tree viết lại: 4 install script, harness templates, `.claude/` 6 hook/12 command/6 skill; §8.8 bats table đồng bộ counts thật **130 test / 9 file**. Files: `README.md` + `MECHANISM.md` (docs-only, không đụng code). Verify: `grep -c '^@test' test/*.bats` = 130/9, hostname canonical `9router.proxy.example.com` khớp `ai-proxy/ccswitch.sh`.
- **2026-07-22** — **Fix `setup.ps1` — 3 bug parity vs `setup.sh` chặn cài đặt Windows non-interactive.** (1) `[Environment]::UserInteractive` luôn trả `True` kể cả khi stdin bị pipe/redirect (verified thật qua `pwsh`) → script tưởng nhầm session tương tác, gọi `Read-Host -AsSecureString` treo vô thời hạn dưới piped stdin, không bao giờ tới đoạn wire settings.json/statusLine/đăng ký PowerShell profile function. Đổi sang `[Console]::IsInputRedirected` (đúng: `True` khi non-interactive). (2) Xoá code set `.model = "sonnet"` (dòng 186-195 cũ) — tái lập bug cũ đã cố ý bỏ ở `setup.sh` (stale model pin sau khi đổi endpoint), thay bằng comment parity giống hệt bash. (3) `.env` proxy flow lỗi thời — `.ps1` vẫn hỏi `[Y/n]` khi có đủ `proxy_host`+`proxy_key`, trong khi `setup.sh` đã đổi sang unconditional-apply (không hỏi, `.env` luôn là source of truth) từ trước — đồng bộ lại logic. Files: `ai-proxy/setup.ps1` + `test/setup-ps1-parity.bats` (4 test mới, skip nếu máy không có `pwsh`). Verify: `bats test/*.bats` (137/137 pass).
- **2026-07-22** — **Xoá `gemini-account.sh` — bỏ account rotation, gọi thẳng CLI.** Sau khi hardcode model vẫn còn hiện tượng "vẫn chậm?" (16s vs >2 phút giữa 2 lần gọi liên tiếp) — root cause thật: rotation-on-failure quét tuần tự tới 6 account (`~/.gemini/accounts/config.json` priority list), mỗi account retry lại pay full CLI cold-start (~15-60s), quota/error ở account đầu kéo theo 5 cold-start nữa trước khi thành công/fail hẳn. User yêu cầu xoá hẳn account script (không chỉ pin 1 account) — `run-gemini.sh` gọi thẳng `gemini` CLI, dùng nguyên OAuth cred đang active trong `~/.gemini/oauth_creds.json`, không còn switch/rotate account nào. Xoá `gemini-account.sh` (2 bản) + `test/gemini-account.bats` (19 test) + mọi reference (`install.sh`, README, MECHANISM). Bats suite còn 132 test / 10 file (từ 151/11). Files: `scripts/delegate/run-gemini.sh` + xoá `scripts/delegate/gemini-account.sh` + `harness/templates/scripts/delegate/gemini-account.sh` + `test/gemini-account.bats` + `harness/install.sh` + README.md + MECHANISM.md. Verify: `bats test/*.bats` (132/132 pass).
- **2026-07-22** — **Xoá `probe-gemini-highest.sh` — cold-start bottleneck.** Probe loop tuần tự qua 8 candidate model, mỗi candidate spawn 1 lần CLI cold-start thật (~15-60s/lần) để tìm model "cao nhất" còn quota — cold cache khiến 1 lần delegate call tốn tới ~4 phút (đo thật: `time bash probe-gemini-highest.sh --force` = 3:55). Xoá hẳn script + test (`probe-gemini-highest.bats`, 19 test) + mọi reference (`install.sh`, README, MECHANISM). `run-gemini.sh` hardcode `GEMINI_MODEL` default = `gemini-3.5-flash` (chọn theo yêu cầu user, không phụ thuộc probe/cache), override per-call vẫn qua `GEMINI_MODEL=<id>`. Files: `scripts/delegate/run-gemini.sh` + xoá `scripts/delegate/probe-gemini-highest.sh` + `harness/templates/scripts/delegate/probe-gemini-highest.sh` + `test/probe-gemini-highest.bats` + `harness/install.sh` + README.md + MECHANISM.md. Verify: `bats test/delegate-scripts.bats`.
- **2026-07-21** — **`fix-ledger` skill — ledger chống merge đè lên fix/feature đã xong.** `.claude/skills/fix-ledger/SKILL.md`: 2 chế độ RECORD (ghi entry sau bugfix/feature có rủi ro bị branch cũ đè) và CHECK (trước `git merge`, so file trong diff sắp merge với `Files:` của từng entry, flag nếu guard/test biến mất). Ledger là file `.claude/fix-ledger.md` tracked-in-git (khác Claude auto-memory global, không theo git) — tạo lần đầu bởi skill khi ghi entry đầu tiên, không ship sẵn. `.claude/rules/git-workflow.md` thêm mục "Trước khi merge — check fix ledger" trỏ tới skill này. Cài được vào project khác qua harness installer (nhóm `skills`). Files: `.claude/skills/fix-ledger/SKILL.md` + `harness/templates/skills/fix-ledger/SKILL.md` + `harness/install.sh` + `.claude/rules/git-workflow.md` + `harness/templates/rules/git-workflow.md` + `test/install-harness.bats` + README.md. Verify: `bats test/install-harness.bats` (3/3 pass).
- **2026-07-20** — **`doctor.sh` — preflight check cho delegate wrapper setup.** Script mới `scripts/delegate/doctor.sh` (đồng bộ `harness/templates/scripts/delegate/doctor.sh`): kiểu `brew doctor`, read-only, không auto-fix, không `set -e` để chạy hết mọi check dù check trước fail. Kiểm tra CLI presence (`git`/`jq`/`aider`/`codex`/`gemini`), cwd có trong git work tree không, và env key resolve được không (9router `proxy_host`+`proxy_key`, deepseek fallback) — chỉ báo "resolved"/"missing", KHÔNG bao giờ in giá trị secret thật. Env-key check dùng standalone read-only parser (không side-effect, không export) thay vì source trực tiếp `_common.sh` — file đó `set -euo pipefail` + hard-exit khi ngoài git repo sẽ giết doctor.sh sớm và mất các check còn lại. `harness/install.sh` thêm `doctor` vào danh sách script cài (nhóm subagents+wrappers giờ 7 script). Files: `scripts/delegate/doctor.sh` + `harness/templates/scripts/delegate/doctor.sh` + `harness/install.sh` + `test/doctor.bats` (4 test mới) + README + MECHANISM. Verify: `bats test/doctor.bats` (4/4 pass), `bats test/*.bats` (170/170 pass).
- **2026-07-20** — **Audit `harness/templates/commands/` — sửa link vỡ + genericize rule templates.** Fix relative-link vỡ trong `lazy-load-audit.md` (trỏ tới `rule-loading-policy.md` — rule global, không bao giờ cài vào project đích — đổi thành plain-text reference). Xoá `commands/sync-harness-memory.md` (orphan, nội dung tự-tham-chiếu repo này, không generalize được cho project khác). Genericize `templates/rules/git-workflow.md` (bỏ hardcode `main/stable/prod`+AWS+`acegalaxy-co`, dùng `@@BRANCH@@` + mô tả protected-branch chung chung) và `templates/rules/skill-superpowers.md` (bỏ hardcode `paths:` frontmatter của riêng ccswitch, dùng token mới `@@CORE_DIRS_YAML@@`). Thêm nhóm cài thứ 7 **`rules`** (`HARNESS_GROUP_RULES`) vào `install.sh`, cài `git-workflow.md`+`skill-superpowers.md` vào `.claude/rules/` project đích. `loop-feature.md` bỏ hardcode `test/ccswitch.bats`/`bats`, dùng `@@TEST_CMD@@`. Cập nhật `test/install-harness.bats` (assertion cũ trỏ `.claude/skills/loop-feature/SKILL.md` — stale từ khi loop-feature còn là skill, nay đã là command) + README/MECHANISM (bảng 6→7 nhóm, danh sách file commands/skills/rules đúng hiện trạng). Verify: `bats test/install-harness.bats` (3/3 pass).
- **2026-07-20** — **Bats suite mở rộng 166 test / 11 file** (từ 35). Thêm `install-harness.bats` (3, cài đủ nhóm mặc định + idempotent), `install-wrappers.bats` (6, `install-9router-proxy.sh`/`install-claude-memory.sh` dispatch theo `$OSTYPE`), `install-git-hooks.bats` (4, dispatch OS + advisory thiếu `gitleaks`), `install-auto-compact.bats` (32), `gemini-account.bats` (19), `probe-gemini-highest.bats` (19), `statusline-context.bats` (29). Xem §8.8. Verify: `bats test/*.bats` (166/166 pass).
- **2026-07-20** — **Hook budget đổi Session%/Weekly% → context-window.** `check-session-limit.sh` bỏ gate theo %-quota (session/weekly không đo được trực tiếp qua tool), chuyển theo dõi context window hội thoại (~200K auto-compact tự trigger). Files: `.claude/hooks/check-session-limit.sh` + `harness/templates/hooks/check-session-limit.sh`.
- **2026-07-20** — **Delegate scripts — 9router alias, Gemini account probe, DeepSeek fallback key.** `scripts/delegate/_common.sh` thêm alias `9router` vào chain resolve env key; `probe-gemini-highest.sh`/`gemini-account.sh` chọn account Gemini CLI còn quota cao nhất; routing Codex hợp nhất qua 9router giống DeepSeek, thêm `deepseek_api_key` làm fallback khi thiếu key riêng. Files: `scripts/delegate/_common.sh` + `scripts/delegate/probe-gemini-highest.sh` + `scripts/delegate/gemini-account.sh`. Verify: `bats test/delegate-scripts.bats`.
- **2026-07-20** — **Gộp `.env` — bỏ `ai-proxy/.env.pro` riêng.** Mọi script (`ccswitch.sh`, `setup.sh`, delegate scripts) đọc chung 1 file `.env` ở repo root thay vì `ai-proxy/.env.pro`. Cập nhật path reference trong README + MECHANISM.
- **2026-07-20** — **`loop-feature` skill — vòng lặp implement/test/fix tới khi xong.** `.claude/skills/loop-feature/SKILL.md`: loop RED (viết test trước) → GREEN (code tối thiểu) → chạy test thật → fail thì tìm root cause sửa tiếp, dựa trên `skill-superpowers.md` (TDD) đã always-load. Guard: tối đa 3 lần fail liên tiếp cùng lỗi (nâng từ 2) thì dừng báo user thay vì thử thêm. Cài được vào project khác qua harness installer (nhóm `skills`, env `HARNESS_GROUP_SKILLS`). Files: `.claude/skills/loop-feature/SKILL.md` + `harness/templates/skills/loop-feature/SKILL.md` + `harness/install.sh`.
- **2026-07-19** — **`harness/` — cài orchestrator+delegate mechanism vào project khác.** `install-harness.sh` (thin wrapper) exec `harness/install.sh`: copy agent persona (`delegate-{codex,deepseek,gemini,sonnet}.md`), guard/quality/session-limit hooks, `scripts/delegate/*.sh`, skill `loop-feature` vào project đích, wire `.claude/settings.json` qua `jq` merge idempotent, thay placeholder `@@PROJECT_SLUG@@`/`@@CORE_DIRS_*@@`/`@@BRANCH@@`/`@@TEST_CMD@@` bằng giá trị project đích. 7 nhóm cài độc lập bật/tắt qua env override (`HARNESS_GROUP_*`, xem changelog 2026-07-20 cho nhóm `rules` thêm sau), off-switch `env.HARNESS_DELEGATE=0` không cần gỡ cài. Repo này tự cài chính mình làm nguồn gốc — `.claude/agents/delegate-*.md` + `scripts/delegate/*.sh` là bản THẬT, đồng bộ nội dung với `harness/templates/`. Files: `install-harness.sh` + `harness/install.sh` + `harness/templates/**` + `scripts/delegate/*.sh` + `.claude/{agents,hooks,commands}/*`. Verify: `bats test/install-harness.bats` (idempotent re-run không tạo hook trùng trong `settings.json`).
- **2026-07-19** — **`install-auto-compact.sh` + statusline context-usage bar.** `install-auto-compact.sh` chỉnh `autoCompactWindow`/`env.DISABLE_AUTO_COMPACT` trong `~/.claude/settings.json` hoặc `./.claude/settings.json` (lệnh `set <tokens>`/`auto`/`off`/`on`/`status`). `ai-proxy/statusline-context.sh` hiển thị % context-window đã dùng ngay trên statusLine, cài kèm khi chạy `ai-proxy/setup.sh`. Files: `install-auto-compact.sh` + `ai-proxy/statusline-context.sh` + `ai-proxy/setup.sh`.
- **2026-07-19** — **Refactor cấu trúc thư mục theo nhóm tính năng.** Gom file rời rạc ở root vào `ai-proxy/` (ccswitch + hooks + profiles + setup), `ai-memory-rules/` (rules + setup-rules), `dev-hooks/` (git-hooks). Cập nhật mọi path reference trong README + MECHANISM.
- **2026-07-18** — **`.env.pro` — điền proxy_host + proxy_key từ file, không cần gõ tay.** `setup.sh`/`setup.ps1` giờ đọc `.env.pro` (gitignored, cạnh script) nếu có đủ 2 biến `proxy_host`/`proxy_key`; hỏi `[Y/n]` — **Enter/y (mặc định) ghi cả 2 giá trị vào cả 3 profile** (`claude`/`codex`/`deepseek`), `n` rơi về flow nhập tay cũ (hỏi base URL rồi hỏi key riêng, Enter giữ nguyên). Non-interactive (CI/piped) cũng mặc định Yes — **trừ khi** một profile đã có key thật, khi đó `.env.pro` bị bỏ qua để không ghi đè âm thầm ngoài TTY (an toàn tương tự `prompt_shared_key` cũ). Thiếu 1 trong 2 biến, hoặc không có file → bỏ qua, coi như trước đây. Key không bao giờ echo ra output. Files: `setup.sh` (`env_pro_val`/`any_real_key`/`apply_env_pro`/`prompt_host`) + `setup.ps1` parity (`Get-EnvProValue`/`Test-AnyRealKey`/`Set-AllProfiles`) + `.env.example` (mẫu, tracked) + `test/setup-env-pro.bats` (7 test mới, stage repo vào tmp dir để không đụng `.env.pro` thật) + README + MECHANISM. Verify: `bash -n`, `bats test/*.bats` (42/42 pass, gồm 2 test dùng `expect` pty cho prompt `[Y/n]` + fallback host/key).
- **2026-07-18** — **Thêm lệnh `ccswitch update [src]`.** Kiến trúc "chung 1 token" nghĩa là claude/codex/deepseek phải luôn khớp `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`, nhưng sau khi `set-key`/`set-host` chỉ sửa 1 profile, 2 profile kia dễ lệch — trước đây phải chạy `set-key`/`set-host` lại thủ công cho từng target còn lại. `update` tự động hoá: đọc host+key từ profile `src` (mặc định `claude`), rồi với từng profile khác trong `ORDER` hỏi `[y/N]` trước khi ghi đè (backup `.bak` từng file); **chỉ copy `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`**, không đụng `ANTHROPIC_DEFAULT_*_MODEL` (đó là phần giữ cho các profile khác nhau dù chung host+token). Từ chối nếu `src=subscription` (không có host/key) hoặc chạy ngoài TTY (cùng pattern với `set_key`). Files: `ccswitch.sh` (`update_profiles()` + dispatch case + help) + `ccswitch.ps1` (`Update-Profiles` parity) + `test/ccswitch.bats` (3 test mới, 2 test dùng `expect` pty vì cần trả lời `[y/N]`) + README + MECHANISM. Verify: `bash -n`, `bats test/*.bats` (35/35 pass), sandbox test qua `expect` xác nhận sync đúng + model prefix giữ nguyên + decline 1 profile không bị ghi đè.
- **2026-07-18** — **Thêm lại target `codex` (`cx/*` GPT).** 9router giờ đã có lớp dịch sang Anthropic format cho `cx/*` (blocker của 2026-07-16 đã hết) — an toàn để phục hồi codex ngang hàng `claude`/`deepseek`. Khôi phục theo đúng cấu trúc trước khi bỏ (`git show 15d58df^`): `profiles/codex.json` (model `cx/gpt-5.6-sol` Opus tier), `ORDER=(claude codex deepseek)`, `tag()`/`active_router_profile()` thêm case `cx/*`, dispatch `claude|codex|deepseek)`, `spawn`/`set-key`/`set-host`/help/usage đều thêm `codex`, hook banner thêm `codex (gpt via 9router)`. **Khác bản gốc:** giữ nguyên kiến trúc "chung 1 token" (không quay lại "mỗi target token riêng" của 2026-07-15e) — mở rộng ra cả 3 profile thay vì chỉ 2. **Đổi UX cấp key:** `setup.sh` xoá `prompt_key()` hỏi từng target, thay bằng `prompt_shared_key()` hỏi **1 lần duy nhất** rồi ghi cùng giá trị vào cả 3 file (backup từng file trước khi ghi). **Nâng `setup.ps1` lên parity đầy đủ** với `setup.sh` — trước đó `.ps1` chỉ wire profile `claude` (TODO comment cũ), giờ loop `$ProfileTargets = @("claude","codex","deepseek")` + prompt 1 key dùng chung, thêm launcher function `claude-cx`. Files: `profiles/codex.json` (new) + `ccswitch.sh` + `ccswitch.ps1` + `hooks/check-router.sh` + `setup.sh` + `setup.ps1` + `test/ccswitch.bats` (test mới `apply codex`) + README + MECHANISM. Verify: `bash -n` toàn bộ script, `bats test/*.bats` (28/28 pass), sandbox test `setup.sh` qua pty (`expect`) xác nhận 1 key ghi đúng vào cả 3 profile.
- **2026-07-16** — **Bỏ target `codex` (`cx/*` GPT).** 9router trả **raw OpenAI wire format** cho `cx/*` (`.choices[].message.content`) trong khi Claude Code chỉ parse Anthropic Messages (`.content[].text`) → codex active làm session vỡ (verified qua `/v1/messages` probe: cả 3 `cx/*` model đều OPENAI-raw; `cc/*` + `ds/*` đều ANTHROPIC-native OK). Xoá `profiles/codex.json` + mọi ref `codex`/`cx/` khỏi `ORDER`, `canon`/`tag`, dispatch case, `active_router_profile`, spawn-die, usage, banner, verify sandbox §8.5/§8.6. **Đổi model design:** `claude` + `deepseek` giờ **chung 1 token 9router** (điền cùng key vào cả 2 profile) — bỏ "token độc lập per-target" của 2026-07-15e (vì cùng 1 account 9router = 1 quota, token riêng vô nghĩa). Files: `ccswitch.sh` + `ccswitch.ps1` + `hooks/check-router.sh` + `setup.sh` + `setup.ps1` + README + MECHANISM. Thêm lại `codex` khi 9router có lớp dịch cx/* → Anthropic format.
- **2026-07-15g** — **`spawn <target>` — chạy nhiều vendor SONG SONG.** Single-instance switch chỉ giữ 1 vendor active (1 process → 1 env → 1 model). `spawn` export model từ `profiles/<target>.json` vào **process env** (tầng ① precedence §2) rồi `exec claude`, **KHÔNG đụng `settings.json`** → mở N terminal + spawn N target = N vendor đồng thời. `subscription` bị từ chối (env-clear, không có gì export). Binary resolve qua `command -v claude` (không dựa alias). `setup` wire 3 alias `claude-cc`/`claude-cx`/`claude-ds`. Cảnh báo quota chung (1 account 9router = 1 quota). Thêm §6b + §8.6. Parity `.ps1` (`Spawn-Target` + case) + `setup.ps1` (3 launcher function).

- **2026-07-15f** — **Rename target `9router` → `claude`** (đặt tên theo model family cho khớp `codex`/`deepseek`, không theo transport). Bỏ hẳn tên `9router` làm target — **KHÔNG** giữ alias (gõ `ccswitch 9router` giờ là unknown → usage error). Đổi: `profiles/9router.json` → `profiles/claude.json` (git mv), `ORDER=(claude codex deepseek)`, `active_router_profile` default `claude`, dispatch `claude|codex|deepseek)`, `set-key` default `claude`, `tag()` → `claude`/`codex`/`deepseek` thuần (transport hiện ở dòng URL), usage/banner/hint. **GIỮ nguyên:** hostname `proxy.example.com` (URL router thật) + key placeholder `<your-9router-key>` + chữ "via 9router" mô tả transport. Files: `ccswitch.sh` + `ccswitch.ps1` + `hooks/check-router.sh` + `setup.sh` + `setup.ps1` + README + MECHANISM. Verify sandbox §8.5 (apply cc/, tag `claude`, old name `9router` → exit 1). **Parity note:** `setup.ps1` mới rename filename, vẫn wire 1 profile `claude` (codex/deepseek trên Windows copy tay) — cùng lag `probe_subscription` 2026-07-15c.
- **2026-07-15e** — Thêm 2 target router **`codex`** (`cx/*` GPT) + **`deepseek`** (`ds/*`) qua CÙNG 9router. Chung base URL, khác block `ANTHROPIC_DEFAULT_*_MODEL`; mỗi profile **token độc lập** (user có thể chỉ xài 1). `ORDER=(9router codex deepseek)`; `current()`/`tag()`/hook phân biệt target bằng **model prefix** (không phải URL — 3 base giống nhau); dispatch case `codex)`/`deepseek)`; `fallback` giữ router đang active (đọc model prefix từ settings.json) rồi mới về subscription; `set-key <target>` ghi token riêng từng profile (không share). `setup.sh` copy 3 profile + prompt token per-target (Enter để skip cái không dùng). Files: `profiles/{codex,deepseek}.json` (new) + `ccswitch.sh` + `ccswitch.ps1` + `hooks/check-router.sh` + `setup.sh` + README + MECHANISM. Verify sandbox §8.5. **Parity note:** `.ps1` đã có ORDER/dispatch/fallback/tag; riêng `probe_subscription` (2026-07-15c) `.ps1` vẫn TODO.
- **2026-07-15d** — `ccswitch` (status) giờ **show tầng nguồn đang thắng** thay vì chỉ đọc `settings.json`. `current()` resolve theo precedence §2: ① process env → ② settings.local.json → ③ settings.json → ④ subscription; đánh dấu `▶` tầng effective + cảnh báo khi ① process env đè settings (bẫy §9), liệt kê cả các tầng khác. Caveat: ① chỉ thấy nếu ccswitch chạy trong shell có sẵn biến — nhắc verify `env | grep ANTHROPIC_BASE_URL`. Cập nhật §4. **TODO parity:** `ccswitch.ps1` chưa có tương đương.
- **2026-07-15c** — `ccswitch check` (+ `status`) giờ **verify subscription safe-harbor** thay vì in dòng cứng "no probe". Thêm hàm `probe_subscription()` trong `ccswitch.sh`: đọc OAuth credential (mac Keychain `Claude Code-credentials` / linux `~/.claude/.credentials.json`), in `✓ logged in (email, subscriptionType) [nguồn]` hoặc `✗ NO OAuth credential — will prompt login`. Email từ `~/.claude.json` `.oauthAccount`, không in token. Verify sandbox: keychain ✓, no-cred ✗, linux-file ✓. Cập nhật §4 + comment header. **TODO parity:** `ccswitch.ps1` chưa có tương đương (Windows dùng `cmdkey`/DPAPI cho credential — cần impl riêng); hiện `.ps1` vẫn in dòng cứng.
- **2026-07-15b** — Fallback đổi `original` (Anthropic-direct + `ANTHROPIC_API_KEY`) → `subscription` (gỡ block `env` → Claude Code OAuth login). Chủ trương: fallback luôn dùng subscription, KHÔNG dùng API key. Xóa `profiles/original.json` + mọi đường `ANTHROPIC_API_KEY`/`x-api-key`/`api.anthropic.com`. Thêm lệnh `ccswitch set-key [profile]` (nhập key ẩn → apply) + prompt nhập key 9router trong `setup.sh`/`setup.ps1`. Alias `original`/`direct`/`clear` → `subscription`. Cập nhật `ccswitch.sh` + `ccswitch.ps1` + `hooks/check-router.sh` + `setup.sh` + `setup.ps1` + README + MECHANISM. Verify sandbox (§8): fallback gỡ env block, giữ nguyên phần còn lại; `set-key subscription` bị từ chối.
- **2026-07-15** — Remove tier `local` (`:20128`): đồng bộ 2-tier (`9router → original`) khớp launcher `scripts/9router-claude.sh` ở Nexus root. Bỏ alias `router` (giữ `direct → original`). Xóa `profiles/local.json`. Cập nhật `ccswitch.sh` + `ccswitch.ps1` + `hooks/check-router.sh` + `setup.sh` + `setup.ps1` + README + MECHANISM. Verify sandbox test 2-tier (§8).
- **2026-07-14** — Auto-switch: hook `check-router.sh` nâng từ warn-only → tự `ccswitch fallback` khi timeout/lỗi (tắt bằng `CCSWITCH_NO_AUTO=1`). Thêm lệnh `ccswitch clear`. Probe fix header `anthropic-version` cho `original`. Fix hiển thị health `000` (trước bị `000000`). Parity PowerShell (probe header + `clear`). Verify bằng sandbox test (§8).
- **Init** — ccswitch CLI 9router/local/original + warn-only SessionStart hook + cross-platform setup.
