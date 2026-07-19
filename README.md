# ccswitch — Claude Code endpoint switcher + rules + hooks

Repo này gồm 3 phần độc lập, cài theo thứ tự:

1. **[`install-9router-proxy.sh`](#phần-1--ccswitch-endpoint-switcher)** — `ccswitch` CLI, đổi endpoint auth của Claude Code (9router / subscription).
2. **[`install-claude-memory.sh`](#phần-2--global-claude-rules)** — copy 7 rule cá nhân (cross-project) vào `~/.claude/rules/`.
3. **[`install-hooks.sh`](#phần-3--git-hooks--push-to-github)** — git hook pre-push (gitleaks scan) cho *repo này*.

Mỗi phần tự detect OS (macOS/Linux chạy bash trực tiếp; Windows qua Git Bash/WSL/Cygwin tự gọi PowerShell) — không cần chọn `.sh` hay `.ps1` thủ công.

---

## Phần 1 — ccswitch (endpoint switcher)

Đổi nhanh endpoint auth của **Claude Code** giữa các model qua **9router** và **subscription** (OAuth login gốc của Claude Code) — chỉ thay block `env` trong `~/.claude/settings.json`, không đụng phần còn lại (hooks, permissions...).

| Target | Cơ chế | Vai trò |
|---|---|---|
| **`claude`** | `env` = 9router + model `cc/*` (claude) | ⭐ **DEFAULT** — Claude qua 9router |
| `codex` | 9router + model `cx/*` | Codex/GPT qua 9router |
| `deepseek` | 9router + model `ds/*` | DeepSeek qua 9router |
| `subscription` | **gỡ block `env`** | Safe-harbor fallback — Claude Code dùng OAuth subscription login (không cần key) |

> `claude` / `codex` / `deepseek` **chung 1 base URL** `https://9router.acegalaxy.co/v1` **và chung 1 key** (điền cùng 1 token 9router vào cả 3 profile); khác nhau **chỉ ở model prefix** (`cc/` vs `cx/` vs `ds/`).
>
> `subscription` KHÔNG phải profile file: nó xóa block `env` để Claude Code quay về OAuth login gốc.
> Alias tương thích ngược: `original` / `direct` / `clear` → `subscription`.

### 1.1 Cài đặt

```bash
git clone git@github.com:acegalaxy-co/ace_commons-ccswitch-cli.git
cd ace_commons-ccswitch-cli
bash install-9router-proxy.sh
```

Windows: chạy lệnh trên trong Git Bash / WSL / Cygwin — script tự gọi `powershell.exe -File setup.ps1` bên dưới. Cần `jq` + `curl` (mac: `brew install jq`; ubuntu/debian: `sudo apt install -y jq curl`).

> Health-check hook dùng `bash` (Git Bash / WSL). Không có cũng không sao — hook tự bỏ qua, `ccswitch` vẫn chạy.

Installer sẽ:
1. Copy `ccswitch` + hook + **profile template** vào `~/.claude/`.
2. Wire hook `SessionStart` (probe endpoint, cảnh báo nếu DOWN) — idempotent.
3. Set `settings.json` field `model` = `sonnet` **chỉ khi chưa có** (không ghi đè nếu bạn đã tự chọn model khác).
4. Thêm alias/function `ccswitch` vào shell profile.
5. **KHÔNG ghi đè** profile đã có key thật (chỉ copy template khi file thiếu).

### 1.2 Điền key (1 key dùng chung cho cả 3 profile)

**Cách nhanh nhất — `.env.pro`:** tạo file `.env.pro` (gitignored) trong `ai-proxy/`, cạnh `ai-proxy/setup.sh`:

```bash
proxy_host=https://9router.acegalaxy.co/v1
proxy_key=<your-9router-key>
```

(mẫu có sẵn ở `.env.example`). Khi `setup.sh`/`setup.ps1` chạy và thấy file này có đủ cả 2 biến, nó hỏi:

```text
▸ Use proxy_host + proxy_key from .env.pro for all profiles (claude/codex/deepseek)? [Y/n]
```

**Enter (hoặc `y`) = mặc định Yes** → ghi thẳng `proxy_host` + `proxy_key` vào cả 3 file (`claude.json` / `codex.json` / `deepseek.json`). Trả lời `n` → rơi về flow nhập tay như cũ (hỏi base URL rồi hỏi key, từng cái). Chạy non-interactive (piped install, CI) cũng áp dụng mặc định Yes — **trừ khi** một profile đã có key thật (khi đó `.env.pro` bị bỏ qua để không ghi đè âm thầm, cần chạy lại trong terminal thật hoặc dùng `set-key`).

Không có `.env.pro`, hoặc thiếu 1 trong 2 biến → bỏ qua bước này, dùng flow nhập tay:

```bash
# mac/linux — nhập ẩn rồi apply luôn. claude + codex + deepseek dùng CÙNG 1 key 9router.
ccswitch set-key claude       # key cho Claude qua 9router
ccswitch set-key codex        # Codex/GPT qua 9router — điền cùng token với claude
ccswitch set-key deepseek     # DeepSeek qua 9router — điền cùng token với claude
```

Hoặc sửa file trực tiếp:

```bash
$EDITOR ~/.claude/profiles/deepseek.json     # thay <your-9router-key>
```
```powershell
notepad $env:USERPROFILE\.claude\profiles\deepseek.json
```

> 🔑 Xin key từ lead. `claude` + `codex` + `deepseek` **chung 1 token** (điền giống nhau vào cả 3 file). **Không commit key** — `~/.claude/profiles/*.json` và `.env.pro` đều local, không đẩy git.

Đã đổi key/host của `claude` và muốn đồng bộ lại `codex`/`deepseek` cho khớp (không phải setup lần đầu)? Dùng `update`:

```bash
ccswitch update claude    # copy ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN từ claude.json sang codex.json + deepseek.json
                           # hỏi [y/N] trước khi ghi đè từng file — model prefix (cc/cx/ds) giữ nguyên
```

### 1.3 Dùng

```bash
ccswitch                # xem target đang active (theo model prefix) + health + subscription note
ccswitch claude         # → Claude qua 9router (default)
ccswitch codex          # → Codex/GPT qua 9router
ccswitch deepseek       # → DeepSeek qua 9router
ccswitch subscription   # → gỡ env block, dùng OAuth subscription login
ccswitch spawn <target> # → mở 1 instance RIÊNG ghim target đó (settings.json không đổi)
ccswitch check          # probe health cả 3 profile + verify subscription OAuth
ccswitch fallback       # giữ target đang active nếu router healthy; router chết → subscription
ccswitch set-key [t]    # nhập key mới (ẩn) cho target t (default claude) rồi apply
ccswitch update [src]   # đồng bộ host+key từ profile src (default claude) sang các profile còn lại — hỏi [y/N] từng cái
ccswitch clear          # alias của subscription (gỡ block env)
ccswitch help           # (hoặc -h) in bảng lệnh + target đầy đủ
```

Windows: cú pháp giống hệt (`ccswitch claude`, ...).

> ⚠️ **Sau mỗi lần switch phải RESTART Claude Code** (quit + mở lại) — env chỉ load lúc khởi động.

#### Auto-switch khi timeout/lỗi

Hook `SessionStart` (`hooks/check-router.sh`) probe endpoint đang active mỗi lần mở session. Nếu nó **timeout hoặc lỗi** (health ≠ 200), hook **tự chạy `ccswitch fallback`** → ghi profile healthy đầu tiên vào `settings.json`.

- **Giới hạn:** env nạp lúc process start, **trước** hook → switch heal cho lần mở **kế tiếp**; session hiện tại có thể còn endpoint cũ tới khi Reload Window / restart.
- **Mid-session** (đang chat mà API lỗi) **không** auto-switch được (Claude Code không có hook on-error) — đó là việc của router upstream-failover.
- **Tắt auto-switch** (chỉ cảnh báo như cũ): `export CCSWITCH_NO_AUTO=1`.

Ví dụ output `ccswitch`:
```
── effective source (Claude Code precedence §2) ──
▶ ③ settings.json  →  claude (https://9router.acegalaxy.co/v1, cc/claude-opus-4-8)
── các tầng khác ──
  claude: 200 OK
  codex: 200 OK
  deepseek: 200 OK
  subscription: ✓ logged in (you@acegalaxy.co, max) [keychain] → safe-harbor OK
profiles: claude codex deepseek
```

#### Chạy nhiều vendor SONG SONG

`ccswitch <target>` chỉ đổi **1 instance** — 1 process Claude Code đọc 1 block `env` → 1 model. Muốn **nhiều vendor cùng active** thì cần **nhiều process riêng**. Dùng `spawn` (hoặc 3 alias `setup` tạo sẵn):

```
# mỗi lệnh trong 1 terminal riêng → 3 vendor chạy đồng thời
claude-cc      # = ccswitch spawn claude    → Claude (cc/*)
claude-cx      # = ccswitch spawn codex     → Codex/GPT (cx/*)
claude-ds      # = ccswitch spawn deepseek  → DeepSeek (ds/*)
```

`spawn` export model vào **process env** (tầng ① — thắng mọi settings file) rồi gọi `claude`, nên **KHÔNG đụng `settings.json`** — target đang switch-in-place của bạn giữ nguyên. Không cần restart: mỗi instance sinh ra đã pin sẵn vendor.

> ⚠️ **Quota chung.** Cả 3 target cùng đi qua 1 account 9router (chung 1 key) → **share chung 1 quota**. Chạy song song = đốt quota nhanh hơn tương ứng số instance. Chung 1 token, KHÔNG tách quota (1 email = 1 quota); tách thật cần account 9router khác email.
>
> `spawn subscription` bị từ chối — subscription là env-clear (gỡ block), không có gì để export. Muốn subscription thì `ccswitch subscription` rồi chạy `claude` thường.

### 1.4 Model — prefix theo target

Model qua 9router **phải** có prefix. Mỗi profile map sẵn 4 tier (Opus/Sonnet/Haiku/Fable) vì Claude Code luôn request theo tier:

| Target | Prefix | Ví dụ (Opus tier) |
|---|---|---|
| `claude` | `cc/` (claude) | `cc/claude-opus-4-8` |
| `codex` | `cx/` | `cx/gpt-5.6-sol` |
| `deepseek` | `ds/` | `ds/deepseek-v4-pro-max` |

Thiếu prefix → lỗi `model_not_found`. Xem model id đầy đủ trong `~/.claude/profiles/<target>.json`, hoặc list live: `curl -s https://9router.acegalaxy.co/v1/models -H "Authorization: Bearer <key>" | jq -r '.data[].id'`. (Ở `subscription` — không có env block — Claude Code tự dùng model mặc định của tài khoản, không cần prefix.)

### 1.5 Troubleshoot

**`ccswitch` báo `claude: 000 DOWN` nhưng endpoint vẫn sống**
Thường do **IPv6 route hỏng** — host resolve ra cả A (IPv4) + AAAA (IPv6), nhưng path IPv6 timeout. Claude Code (Node) tự né sang IPv4 nên vẫn chạy; chỉ `curl`/health-probe bị kẹt. Xác minh:
```bash
curl -4 --resolve 9router.acegalaxy.co:443:172.66.43.28 https://9router.acegalaxy.co/v1/models -H "Authorization: Bearer <key>"
```
Nếu IPv4 trả `200` → endpoint OK, bỏ qua cảnh báo. Muốn dứt điểm: pin IPv4 vào `/etc/hosts`.

**`No active credentials for provider` / `model_not_found`**
Sai model id — thêm prefix đúng target (`cc/` claude, `cx/` codex, `ds/` deepseek — xem mục 1.4).

**`API key required for remote API access`**
Key trong profile là placeholder hoặc key local nhầm sang remote. Điền đúng key 9router.

**Switch xong không đổi**
Chưa restart Claude Code. Quit hẳn rồi mở lại.

**Khôi phục settings**
Mỗi lần switch tạo backup `~/.claude/settings.json.bak`. Lỗi thì:
```bash
cp ~/.claude/settings.json.bak ~/.claude/settings.json
```

### 1.6 Bảo mật

- Profile `~/.claude/profiles/*.json` chứa key thật → **local only**, không commit.
- Template trong repo này chỉ có placeholder `<your-...-key>`.
- `setup` không bao giờ ghi đè profile đã có key.

---

## Phần 2 — global Claude rules

Copy 8 file rule cá nhân (cross-project — orchestrator, delegate-llm, budget, vault guard, secrets...) từ `rules/*.md` vào `~/.claude/rules/`, để mọi project mở Claude Code đều load cùng bộ convention.

### 2.1 Cài đặt

```bash
bash install-claude-memory.sh
```

Windows: chạy trong Git Bash / WSL / Cygwin — tự gọi `powershell.exe -File setup-rules.ps1`.

Script hỏi `[y/N]`, trả lời `y` sẽ **mirror toàn bộ thư mục**: ghi đè mọi `rules/*.md` vào `~/.claude/rules/` (kể cả file đã tồn tại), **và xoá** bất kỳ `*.md` nào ở `~/.claude/rules/` không còn tồn tại trong `rules/` của repo — kể cả file không phải do repo này tạo ra ban đầu. Không có mode symlink (symlink trỏ ngược vào file trong repo là rủi ro rò rỉ nếu repo này từng bị share/fork cho người khác). Mỗi lần chạy lại = đồng bộ `~/.claude/rules/` khớp chính xác với `rules/` trong repo.

> ⚠️ Nếu `~/.claude/rules/` có rule khác không thuộc repo này (vd cài từ nguồn khác), mirror sẽ **xoá luôn** — kiểm tra output `✗ rules/<name>.md (removed — not in repo)` sau khi chạy.

### 2.2 Nội dung

```
rules/
├── orchestrator.md         # Opus giữ vai pure orchestrator, routing S/M/L/XL qua delegate
├── delegate-llm.md         # 4 delegate subagent (deepseek/gemini/codex/sonnet), anti-pattern
├── git-conventions.md      # push/publish GitHub dưới org acegalaxy-co
├── vault-no-mcp.md          # cấm dùng MCP Notion connector cho vault chứa secret
├── secrets-no-printout.md  # cấm in secret ra chat/output, cách redact đúng
├── feature-redflags.md      # safe minimal changes + bảng "red flags" rationalization
├── token-budget.md          # ngưỡng context cần compact/delegate
└── rule-loading-policy.md   # always-load vs lazy (paths:) cho project rule
```

> ⚠️ Đây là convention nội bộ cá nhân, không chứa secret/key — nhưng vẫn là nội dung riêng của 1 người dùng. Nếu bạn fork repo này cho team khác, xoá hoặc thay `rules/*.md` bằng convention của team đó trước khi cài.

---

## Phần 3 — git hooks + push-to-github

Hook `pre-push` của *repo ccswitch này* (không phải hook cho project khác) — chặn push nếu `gitleaks` phát hiện secret.

### 3.1 Cài đặt

```bash
bash install-hooks.sh
```

Symlink `dev-hooks/git-hooks/pre-push` → `.git/hooks/pre-push` (copy nếu máy không hỗ trợ symlink). Cần chạy 1 lần sau mỗi lần `git clone` mới (hook không tự nhân bản qua clone).

Cần `gitleaks` (`brew install gitleaks`) — thiếu thì hook chỉ cảnh báo advisory, không chặn push.

### 3.2 Dùng

Hook tự chạy mỗi `git push`:
```bash
git push                    # gitleaks scan trước, chặn nếu có leak
GITLEAKS_SKIP=1 git push    # bypass có chủ đích (chắc chắn false-positive)
```

### 3.3 Slash command `/push-to-github`

Trong Claude Code, gõ `/push-to-github` để chạy pipeline gate đầy đủ trước khi push:

1. **Smoke test** — `bats test/*.bats` (24 test, coverage cho `ccswitch.sh` + `setup-rules.sh` + 2 install wrapper).
2. **gitleaks scan** — hard-stop nếu thiếu `gitleaks` hoặc phát hiện leak (khác hook `pre-push` advisory-skip khi thiếu tool).
3. **Sensitive-content review** — đọc diff, tìm key/URL nội bộ/thông tin cá nhân ngoài phạm vi gitleaks pattern.
4. **Push** — chỉ hỏi xác nhận và push nếu 3 bước trên đều pass.

Định nghĩa lệnh: [`.claude/commands/push-to-github.md`](.claude/commands/push-to-github.md).

### 3.4 Chạy test thủ công

```bash
brew install bats-core   # 1 lần, nếu chưa có
bats test/*.bats
```

Test dùng `$HOME` giả (`$BATS_TEST_TMPDIR`) — không đụng `~/.claude` thật của máy chạy test.

---

## File trong package

```
ccswitch-cli/
├── README.md                    # tài liệu này
├── MECHANISM.md                 # tài liệu kỹ thuật đầy đủ (dev handoff)
│
├── install-9router-proxy.sh     # Phần 1 — entry point, tự detect OS
├── ai-proxy/
│   ├── ccswitch.sh / ccswitch.ps1  # Phần 1 — tool (mac/linux / windows)
│   ├── setup.sh / setup.ps1        # Phần 1 — installer chạy bên dưới wrapper
│   ├── hooks/check-router.sh       # Phần 1 — SessionStart health probe
│   └── profiles/                   # Phần 1 — TEMPLATE (placeholder key, an toàn để commit)
│       ├── claude.json                # claude cc/*
│       ├── codex.json                 # codex cx/*  (same key as claude.json)
│       └── deepseek.json              # deepseek ds/*  (same key as claude.json)
│                                       # subscription không có file — nó là env-clear
│
├── install-claude-memory.sh     # Phần 2 — entry point, tự detect OS
├── ai-memory-rules/
│   ├── setup-rules.sh / setup-rules.ps1  # Phần 2 — installer chạy bên dưới wrapper
│   └── rules/*.md                         # Phần 2 — 7 rule cá nhân, copy nguyên văn
│
├── install-hooks.sh              # Phần 3 — cài git hook của repo này
├── dev-hooks/git-hooks/pre-push  # Phần 3 — gitleaks scan trước push
├── .claude/commands/push-to-github.md  # Phần 3 — slash command gate pipeline
└── test/*.bats                    # Phần 3 — bats suite (chạy qua /push-to-github hoặc thủ công)
```
