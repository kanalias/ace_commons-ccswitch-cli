# ccswitch — Claude Code endpoint switcher + rules + hooks

## Tổng quan

Bộ script cá nhân/team quản lý setup Claude Code: đổi endpoint auth nhanh (subscription ↔ proxy 9router ↔ vendor khác), đồng bộ convention (rules) qua nhiều máy, chặn leak secret trước push, và cài mechanism "orchestrator + delegate subagent" cho project khác dùng. 5 phần **độc lập** — chỉ cần phần nào thì cài phần đó, không phụ thuộc dây chuyền (trừ Phần 3 dùng cho chính repo này).

| Muốn... | Cài phần |
|---|---|
| Đổi model/endpoint Claude Code nhanh (Claude/Codex/DeepSeek qua proxy, hoặc quay lại subscription) | **Phần 1** |
| Đồng bộ 8 rule cá nhân (orchestrator, secret guard...) ra mọi máy/mọi project | **Phần 2** |
| Chặn commit chứa secret trước khi push (cho *repo ccswitch này*) | **Phần 3** |
| Cài mechanism delegate subagent (Aider/Codex/Gemini) vào **project khác** | **Phần 4** |
| Chỉnh mốc Claude Code tự nén hội thoại (hoặc tắt hẳn) | **Phần 5** |

### Yêu cầu hệ thống

| Dependency | Cần cho | Cài |
|---|---|---|
| `bash` | Tất cả (mac/linux native; Windows qua Git Bash/WSL/Cygwin) | có sẵn mac/linux; Windows: Git Bash hoặc WSL |
| `jq` | Phần 1 (profile JSON), Phần 4 (wire `settings.json`), Phần 5 (`autoCompactWindow`) | `brew install jq` / `apt install jq` |
| `curl` | Phần 1 (health-check proxy) | có sẵn hầu hết hệ thống |
| `git` | Phần 3, Phần 4 (worktree isolation cho delegate wrapper) | `brew install git` / `apt install git` |
| `gitleaks` | Phần 3 (pre-push scan) | `brew install gitleaks` — thiếu thì hook advisory-skip, không chặn |
| `bats-core` | Chạy test suite (dev, không cần cho user cuối) | `brew install bats-core` |
| `aider`/`codex`/`gemini` CLI | Phần 4 — chỉ cần trên **project đích** nếu thật sự gọi delegate subagent tương ứng, không cần lúc cài | xem persona `delegate-*.md` sau khi cài |

Repo này gồm 5 phần độc lập, cài theo thứ tự:

1. **[`install-9router-proxy.sh`](#phần-1--ccswitch-endpoint-switcher)** — `ccswitch` CLI, đổi endpoint auth của Claude Code (9router / subscription).
2. **[`install-claude-memory.sh`](#phần-2--global-claude-rules)** — copy 8 rule chung tối thiểu (cross-project) vào `~/.claude/rules/`.
3. **[`install-git-hooks.sh`](#phần-3--git-hooks--push-to-git)** — git hook pre-push (gitleaks scan) cho *repo này*.
4. **[`install-harness-delegate.sh`](#phần-4--harness-delegate-orchestrator--subagent)** — cài mechanism orchestrator + delegate subagent (hooks, agent persona, wrapper script) vào **project khác**.
5. **[`install-auto-compact.sh`](#phần-5--auto-compact-window)** — chỉnh mốc `autoCompactWindow` (khi nào Claude Code tự nén context) hoặc tắt hẳn tính năng, qua `~/.claude/settings.json` (hoặc `./.claude/settings.json` cho riêng project).

Mỗi phần tự detect OS (macOS/Linux chạy bash trực tiếp; Windows qua Git Bash/WSL/Cygwin tự gọi PowerShell) — không cần chọn `.sh` hay `.ps1` thủ công. (Riêng Phần 4 — delegate wrapper bash-only, Windows cần WSL/Git-Bash, không chạy CMD/PowerShell thuần. Phần 5 — thuần bash + `jq`, không có bản `.ps1`, chạy trên Windows cần Git Bash/WSL.)

---

## Phần 1 — ccswitch (endpoint switcher)

Đổi nhanh endpoint auth của **Claude Code** giữa các model qua **9router** và **subscription** (OAuth login gốc của Claude Code) — chỉ thay block `env` trong `~/.claude/settings.json`, không đụng phần còn lại (hooks, permissions...).

| Target | Cơ chế | Vai trò |
|---|---|---|
| **`claude`** | `env` = 9router + model `cc/*` (claude) | ⭐ **DEFAULT** — Claude qua 9router |
| `codex` | 9router + model `cx/*` | Codex/GPT qua 9router |
| `deepseek` | 9router + model `ds/*` | DeepSeek qua 9router |
| `subscription` | **gỡ block `env`** | Safe-harbor fallback — Claude Code dùng OAuth subscription login (không cần key) |

> `claude` / `codex` / `deepseek` **chung 1 base URL** `https://proxy.example.com/v1` **và chung 1 key** (điền cùng 1 token 9router vào cả 3 profile); khác nhau **chỉ ở model prefix** (`cc/` vs `cx/` vs `ds/`).
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

**Cách nhanh nhất — `.env`:** tạo file `.env` (gitignored) ở repo root:

```bash
proxy_host=https://9router.proxy.example.com/v1
proxy_key=<your-9router-key>
```

(mẫu có sẵn ở `.env.example`). Khi `setup.sh`/`setup.ps1` chạy và thấy file này có đủ cả 2 biến, nó hỏi:

```text
▸ Use proxy_host + proxy_key from .env for all profiles (claude/codex/deepseek)? [Y/n]
```

**Enter (hoặc `y`) = mặc định Yes** → ghi thẳng `proxy_host` + `proxy_key` vào cả 3 file (`claude.json` / `codex.json` / `deepseek.json`). Trả lời `n` → rơi về flow nhập tay như cũ (hỏi base URL rồi hỏi key, từng cái). Chạy non-interactive (piped install, CI) cũng áp dụng mặc định Yes — **trừ khi** một profile đã có key thật (khi đó `.env` bị bỏ qua để không ghi đè âm thầm, cần chạy lại trong terminal thật hoặc dùng `set-key`).

Không có `.env`, hoặc thiếu 1 trong 2 biến → bỏ qua bước này, dùng flow nhập tay:

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

> 🔑 Xin key từ lead. `claude` + `codex` + `deepseek` **chung 1 token** (điền giống nhau vào cả 3 file). **Không commit key** — `~/.claude/profiles/*.json` và `.env` đều local, không đẩy git.

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
▶ ③ settings.json  →  claude (https://9router.proxy.example.com/v1, cc/claude-opus-4-8)
── các tầng khác ──
  claude: 200 OK
  codex: 200 OK
  deepseek: 200 OK
  subscription: ✓ logged in (you@example.com, max) [keychain] → safe-harbor OK
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

Thiếu prefix → lỗi `model_not_found`. Xem model id đầy đủ trong `~/.claude/profiles/<target>.json`, hoặc list live: `curl -s https://9router.proxy.example.com/v1/models -H "Authorization: Bearer <key>" | jq -r '.data[].id'`. (Ở `subscription` — không có env block — Claude Code tự dùng model mặc định của tài khoản, không cần prefix.)

### 1.5 Troubleshoot

**`ccswitch` báo `claude: 000 DOWN` nhưng endpoint vẫn sống**
Thường do **IPv6 route hỏng** — host resolve ra cả A (IPv4) + AAAA (IPv6), nhưng path IPv6 timeout. Claude Code (Node) tự né sang IPv4 nên vẫn chạy; chỉ `curl`/health-probe bị kẹt. Xác minh:
```bash
curl -4 --resolve 9router.proxy.example.com:443:<proxy-ipv4> https://9router.proxy.example.com/v1/models -H "Authorization: Bearer <key>"
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

Copy 8 file rule cá nhân (cross-project — orchestrator, delegate-llm, budget, vault guard, secrets...) từ `ai-memory-rules/rules/*.md` vào `~/.claude/rules/`, để mọi project mở Claude Code đều load cùng bộ convention.

### 2.1 Cài đặt

```bash
bash install-claude-memory.sh
```

Windows: chạy trong Git Bash / WSL / Cygwin — tự gọi `powershell.exe -File setup-rules.ps1`.

Script hỏi `[y/N]`, trả lời `y` sẽ **mirror toàn bộ thư mục**: ghi đè mọi `rules/*.md` vào `~/.claude/rules/` (kể cả file đã tồn tại), **và xoá** bất kỳ `*.md` nào ở `~/.claude/rules/` không còn tồn tại trong `rules/` của repo — kể cả file không phải do repo này tạo ra ban đầu. Không có mode symlink (symlink trỏ ngược vào file trong repo là rủi ro rò rỉ nếu repo này từng bị share/fork cho người khác). Mỗi lần chạy lại = đồng bộ `~/.claude/rules/` khớp chính xác với `rules/` trong repo.

> ⚠️ Nếu `~/.claude/rules/` có rule khác không thuộc repo này (vd cài từ nguồn khác), mirror sẽ **xoá luôn** — kiểm tra output `✗ rules/<name>.md (removed — not in repo)` sau khi chạy.

Ví dụ output khi chạy (trả lời `y`):

```
── mirror global rules into /Users/you/.claude/rules/ (overwrites + removes anything not in rules/)? [y/N]: y
  ✗ rules/old-unused-rule.md (removed — not in repo)
  ✓ rules/orchestrator.md (copied)
  ✓ rules/delegate-llm.md (copied)
  ✓ rules/git-conventions.md (copied)
  ✓ rules/vault-no-mcp.md (copied)
  ✓ rules/secrets-no-printout.md (copied)
  ✓ rules/feature-redflags.md (copied)
  ✓ rules/token-budget.md (copied)
  ✓ rules/rule-loading-policy.md (copied)
```

### 2.2 Nội dung

```
ai-memory-rules/rules/
├── orchestrator.md         # Opus giữ vai pure orchestrator, routing S/M/L/XL qua delegate
├── delegate-llm.md         # 4 delegate subagent (deepseek/gemini/codex/sonnet), anti-pattern
├── git-conventions.md      # push/publish GitHub dưới org acegalaxy-co
├── vault-no-mcp.md          # cấm dùng MCP Notion connector cho vault chứa secret
├── secrets-no-printout.md  # cấm in secret ra chat/output, cách redact đúng
├── feature-redflags.md      # safe minimal changes + bảng "red flags" rationalization
├── token-budget.md          # ngưỡng context cần compact/delegate
└── rule-loading-policy.md   # always-load vs lazy (paths:) cho project rule
```

> ⚠️ Đây là convention nội bộ cá nhân, không chứa secret/key — nhưng vẫn là nội dung riêng của 1 người dùng. Nếu bạn fork repo này cho team khác, xoá hoặc thay `ai-memory-rules/rules/*.md` bằng convention của team đó trước khi cài.

### 2.3 Troubleshoot

**Chạy xong không thấy rule load trong Claude Code**
Rule global chỉ load khi mở **session mới** — reload/restart Claude Code sau khi mirror.

**Muốn giữ 1 rule tự thêm ở `~/.claude/rules/` (không có trong repo)**
Mirror sẽ xoá nó ở lần chạy kế tiếp vì cơ chế là đồng bộ 1-chiều (repo → home). Copy rule đó vào `ai-memory-rules/rules/` trong repo trước khi chạy lại, hoặc trả lời `N` để bỏ qua lần mirror đó.

**Script không hỏi gì, thoát luôn**
Không thấy dir `ai-memory-rules/rules/` cạnh script — chạy đúng path repo, không chạy bản copy lẻ của `setup-rules.sh`.

---

## Phần 3 — git hooks + push-to-git

Hook `pre-push` của *repo ccswitch này* (không phải hook cho project khác) — chặn push nếu `gitleaks` phát hiện secret.

### 3.1 Cài đặt

```bash
bash install-git-hooks.sh
```

Symlink `dev-hooks/git-hooks/pre-push` → `.git/hooks/pre-push` (copy nếu máy không hỗ trợ symlink). Cần chạy 1 lần sau mỗi lần `git clone` mới (hook không tự nhân bản qua clone).

Cần `gitleaks` (`brew install gitleaks`) — thiếu thì hook chỉ cảnh báo advisory, không chặn push.

### 3.2 Dùng

Hook tự chạy mỗi `git push`:

```bash
git push                    # gitleaks scan trước, chặn nếu có leak
GITLEAKS_SKIP=1 git push    # bypass có chủ đích (chắc chắn false-positive)
```

Ví dụ khi hook chặn push (phát hiện leak):

```text
🔍 Scanning for secrets with gitleaks...
Finding:     proxy_key=sk-abc123...
File:        .env
Line:        3
Rule:        generic-api-key

❌ Phát hiện secret trong commit — push bị chặn.
   False positive? Chạy: GITLEAKS_SKIP=1 git push
```

### 3.3 Slash command `/push-to-git`

Trong Claude Code, gõ `/push-to-git` để chạy pipeline gate đầy đủ trước khi push:

1. **Smoke test** — `bats test/*.bats` (166 test trên 11 file, coverage cho `ccswitch.sh` + `setup-rules.sh` + install wrapper + `harness-delegate/install.sh` + delegate wrapper scripts + `.env` prompt flow + auto-compact/statusline/gemini-account scripts).
2. **gitleaks scan** — hard-stop nếu thiếu `gitleaks` hoặc phát hiện leak (khác hook `pre-push` advisory-skip khi thiếu tool).
3. **Sensitive-content review** — đọc diff, tìm key/URL nội bộ/thông tin cá nhân ngoài phạm vi gitleaks pattern.
4. **Push** — chỉ hỏi xác nhận và push nếu 3 bước trên đều pass.

Định nghĩa lệnh: [`.claude/commands/push-to-git.md`](.claude/commands/push-to-git.md).

### 3.4 Chạy test thủ công

```bash
brew install bats-core   # 1 lần, nếu chưa có
bats test/*.bats
```

Test dùng `$HOME` giả (`$BATS_TEST_TMPDIR`) — không đụng `~/.claude` thật của máy chạy test.

### 3.5 Troubleshoot

**Push vẫn qua dù không cài `install-git-hooks.sh`**
Đúng — chưa cài thì `.git/hooks/pre-push` không tồn tại, không có gì chặn. Chạy lại `bash install-git-hooks.sh`.

**`git clone` lại repo trên máy khác, hook biến mất**
Hook không nằm trong `.git/` do git track (git không track nội dung `.git/hooks/`) — phải chạy `install-git-hooks.sh` lại sau mỗi clone mới.

**Hook chạy nhưng không chặn dù có secret thật**
Kiểm tra `gitleaks version` — thiếu tool thì hook chỉ in cảnh báo advisory, không hard-stop (khác `/push-to-git` luôn hard-stop khi thiếu `gitleaks`).

**Symlink lỗi trên filesystem lạ (vd một số mount network)**
Script tự fallback `cp` khi `ln -sf` fail — nếu vẫn lỗi, kiểm tra quyền ghi `.git/hooks/`.

---

## Phần 4 — harness-delegate (orchestrator + subagent)

Cài mechanism "orchestrator giữ vai reasoning + delegate subagent thực thi" (xem [`ai-memory-rules/rules/orchestrator.md`](ai-memory-rules/rules/orchestrator.md)) vào **project khác** (không phải repo này) — copy hooks + agent persona + delegate wrapper script + skill, rồi wire vào `.claude/settings.json` của project đích.

### 4.1 Cài đặt

```bash
bash install-harness-delegate.sh
```

Interactive: hỏi cài vào project nào (nhập path, hoặc dùng project đang mở ở terminal), rồi hỏi cài toàn bộ + overwrite file cũ hay huỷ. Non-interactive (script/CI): mọi câu hỏi có env var override tương ứng — xem comment đầu file [`harness-delegate/install.sh`](harness-delegate/install.sh) (`HARNESS_ROUTE_DIR`, `HARNESS_PROJECT_SLUG`, `HARNESS_GROUP_*`...).

Delegate wrapper là **bash-only** — Windows cần WSL hoặc Git Bash (không chạy CMD/PowerShell thuần).

### 4.2 Cài gì vào project đích

7 nhóm, mỗi nhóm bật/tắt độc lập (mặc định tất cả Y):

| Nhóm | File cài vào project đích |
|---|---|
| **subagents + wrappers** | `.claude/agents/delegate-{deepseek,gemini,codex,sonnet}.md` + `scripts/delegate/*.sh` (7 script: `_common`, `run-aider-deepseek`, `run-codex`, `run-gemini`, `probe-gemini-highest`, `gemini-account`, `doctor`) |
| **guard hooks** | `.claude/hooks/pre-edit-orchestrator-gate.sh` + `pre-edit-secret-scan.sh` (wire vào `PreToolUse` cho `Edit`/`Write`) |
| **quality hooks** | `.claude/hooks/post-edit-syntax-check.sh` (wire `PostToolUse`) + `session-start-banner.sh` (wire `SessionStart`) |
| **session-limit hook** | `.claude/hooks/check-session-limit.sh` (wire `UserPromptSubmit`) |
| **commands** | `.claude/commands/{push-to-git,conventional-commit,branch-cleanup,pr-describe,dep-audit,loop-feature,lazy-load-audit,audit-memory-harness}.md` |
| **skills** | `.claude/skills/{lazy-load-health,dep-ladder-check}/SKILL.md` |
| **rules** | `.claude/rules/{git-workflow,skill-superpowers}.md` |

Wiring `.claude/settings.json` dùng `jq` merge **idempotent** — chạy lại không tạo hook trùng lặp. Off-switch không cần gỡ cài: set `env.HARNESS_DELEGATE=0` trong `.claude/settings.json` của project đích.

Template gốc nằm ở `harness-delegate/templates/` — installer thay placeholder `@@PROJECT_SLUG@@`/`@@CORE_DIRS_CASE@@`/`@@CORE_DIRS_HUMAN@@`/`@@CORE_DIRS_YAML@@`/`@@BRANCH@@`/`@@TEST_CMD@@` bằng giá trị của project đích trước khi ghi file.

Ví dụ chạy interactive (chọn cài vào project đang mở ở terminal, giữ mặc định Y cho mọi câu hỏi):

```text
$ bash install-harness-delegate.sh
Cài harness vào project nào — 1) nhập đường dẫn project ...  2) cài vào project đang mở ở terminal này [1]: 2
📁 Install target: /Users/you/projects/my-app
Cài harness vào đúng đường dẫn này [Y/n]: y
Cài toàn bộ harness và override mọi file đã tồn tại [Y/n]: y
  ✓ .claude/agents/delegate-deepseek.md
  ✓ .claude/agents/delegate-gemini.md
  ✓ .claude/agents/delegate-codex.md
  ✓ .claude/agents/delegate-sonnet.md
  ✓ scripts/delegate/_common.sh
  ✓ scripts/delegate/doctor.sh
  ... (toàn bộ 7 script)
  ✓ .claude/hooks/pre-edit-orchestrator-gate.sh
  ✓ .claude/commands/audit-memory-harness.md
  ✓ .claude/rules/git-workflow.md
✅ Wired .claude/settings.json (hooks: PreToolUse, PostToolUse, SessionStart, UserPromptSubmit)
✅ Xong. Chạy scripts/delegate/doctor.sh trong project đích để kiểm tra CLI + env key.
```

Sau khi cài, chạy `scripts/delegate/doctor.sh` (trong project đích) để kiểm tra preflight — CLI `git`/`jq`/`aider`/`codex`/`gemini` có cài chưa, có đang trong git repo không, key 9router/`deepseek_api_key` resolve được không (không bao giờ in giá trị secret thật):

```text
$ scripts/delegate/doctor.sh
CLI:
  ✓ git
  ✓ jq
  ✓ aider
  ✗ codex
  ✓ gemini

Git repo:
  ✓ cwd is inside a git work tree

Env keys (presence only — never print values):
  ✓ 9router (proxy_host + proxy_key) resolved
  ✓ deepseek fallback key resolved

4 pass, 1 fail
```

### 4.3 Troubleshoot

**Cài xong nhưng hook không chạy trong project đích**
Kiểm tra `.claude/settings.json` project đích có block `hooks.PreToolUse`/`PostToolUse`/... trỏ đúng script không — `jq . .claude/settings.json` xem JSON còn hợp lệ. Restart Claude Code sau khi wire hook (hook load lúc session start).

**Muốn tắt tạm mechanism mà không gỡ cài**
Set `env.HARNESS_DELEGATE=0` trong `.claude/settings.json` của project đích — không cần chạy lại installer hay xoá file.

**Chạy lại installer, sợ mất tuỳ chỉnh đã sửa tay trong project đích**
`HARNESS_INSTALL_ALL=Y` (mặc định) ghi đè mọi file đã cài — nếu bạn từng sửa tay 1 hook/command sau khi cài, sửa đó sẽ mất khi chạy lại. Diff trước khi chạy lại, hoặc set `HARNESS_GROUP_<NHÓM>=n` để bỏ qua đúng nhóm đã tự sửa.

**`delegate-deepseek`/`delegate-codex`/`delegate-gemini` báo lỗi thiếu CLI/key**
Chạy `scripts/delegate/doctor.sh` trong project đích trước — báo rõ CLI nào thiếu, key 9router/deepseek có resolve không, mà không lộ giá trị secret.

**Windows CMD/PowerShell thuần chạy installer báo lỗi cú pháp bash**
Đúng hành vi — Phần 4 bash-only. Chạy qua Git Bash hoặc WSL.

---

## Phần 5 — auto-compact window

Chỉnh khi nào Claude Code tự nén (compact) hội thoại để tránh tràn context, hoặc tắt hẳn tính năng — đứng riêng, không phụ thuộc Phần 1-4 (không cài `ccswitch`).

Key config: `autoCompactWindow` (số token tuyệt đối). Ngưỡng thực compact = `min(autoCompactWindow, model max context)`. Ví dụ Opus context ~200k → set `190000` ≈ 95%. Anthropic khuyến nghị để **auto** (Claude tự chọn theo model) — đặt mốc thấp = compact sớm hơn, có thể mất context giữa task nặng.

### 5.1 Dùng

```bash
install-auto-compact.sh [--global|--project] <command>
```

Target (mặc định `--global` → `~/.claude/settings.json`; `--project` → `./.claude/settings.json`, đè global cho riêng project hiện tại):

```bash
install-auto-compact.sh set 190000    # đặt mốc compact ở 190k token (~95%, khuyến nghị cho task nặng)
install-auto-compact.sh set 170000    # mốc sớm hơn (~85%), dư địa an toàn hơn
install-auto-compact.sh auto          # bỏ mốc cứng, trả về Claude tự chọn (mặc định khuyến nghị)
install-auto-compact.sh off           # TẮT HẲN auto-compact (env.DISABLE_AUTO_COMPACT=1) — tự /compact thủ công
install-auto-compact.sh on            # bật lại
install-auto-compact.sh status        # xem mốc + trạng thái on/off hiện tại
install-auto-compact.sh --project set 170000   # chỉ áp cho project hiện tại, không đụng global
```

`off` khác `set`/`auto`: `off` tắt cả tính năng; `set`/`auto` chỉ đổi mốc (tính năng vẫn bật). Có thể `set` mốc rồi `off` cùng lúc — `off` thắng tới khi `on` lại. Script yêu cầu `jq`; tự tạo `settings.json` (`{}`) nếu file chưa tồn tại.

> Liên quan: `ai-proxy/statusline-context.sh` (cài kèm ở Phần 1 §1.1) hiển thị % context-window đã dùng ngay trên statusLine — theo dõi trực quan mốc `autoCompactWindow` đang chỉnh ở đây.

Bash-only, không có bản `.ps1` — Windows chạy qua Git Bash/WSL.

Ví dụ `status`:

```text
$ install-auto-compact.sh status
file: /Users/you/.claude/settings.json
  autoCompactWindow   : 190000
  DISABLE_AUTO_COMPACT: unset (enabled)
```

### 5.2 Troubleshoot

**`jq: command not found`**
Script hard-require `jq` — cài `brew install jq` (mac) / `apt install jq` (linux) rồi chạy lại.

**Set `--project` nhưng vẫn thấy hành vi global**
`--project` ghi vào `./.claude/settings.json` — chạy lệnh đúng tại **project root**, không phải thư mục con. `status` không kèm cờ nào mặc định đọc global; kiểm tra đúng file bằng `install-auto-compact.sh --project status`.

**Set mốc xong Claude Code không đổi hành vi compact**
Cần **session mới** để đọc lại `settings.json` — reload/restart Claude Code sau khi `set`/`auto`/`off`/`on`.

**Set mốc rồi mà vẫn compact sớm bất thường**
Kiểm tra `env.DISABLE_AUTO_COMPACT` — nếu vẫn có giá trị cũ hoặc mốc `autoCompactWindow` bị project-level `settings.json` đè lại global (project thắng global).

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
│   ├── statusline-context.sh       # Phần 1 — statusLine context-usage bar (cài kèm setup.sh)
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
├── install-git-hooks.sh          # Phần 3 — cài git hook của repo này
├── dev-hooks/git-hooks/pre-push  # Phần 3 — gitleaks scan trước push
├── .claude/commands/push-to-git.md  # Phần 3 — slash command gate pipeline
├── test/*.bats                    # Phần 3 — bats suite (chạy qua /push-to-git hoặc thủ công)
│
├── install-harness-delegate.sh   # Phần 4 — entry point (interactive + non-interactive)
├── harness-delegate/
│   ├── install.sh                     # Phần 4 — installer chạy bên dưới wrapper, wire settings.json qua jq
│   └── templates/                     # Phần 4 — template gốc, placeholder @@...@@ thay theo project đích
│       ├── agents/delegate-{codex,deepseek,gemini,sonnet}.md
│       ├── scripts/delegate/               # 7 wrapper script (_common, run-aider-deepseek, run-codex, run-gemini, probe-gemini-highest, gemini-account, doctor)
│       ├── hooks/{pre-edit-orchestrator-gate,pre-edit-secret-scan,post-edit-syntax-check,session-start-banner,check-session-limit}.sh
│       ├── commands/{push-to-git,conventional-commit,branch-cleanup,pr-describe,dep-audit,loop-feature,lazy-load-audit,audit-memory-harness}.md
│       ├── skills/{lazy-load-health,dep-ladder-check}/
│       └── rules/{git-workflow,skill-superpowers}.md
│
└── install-auto-compact.sh       # Phần 5 — set/auto/off/on/status autoCompactWindow, đứng riêng
```
