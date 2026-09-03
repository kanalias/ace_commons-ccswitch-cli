# ccswitch — Claude Code endpoint switcher + harness delegate

## Tổng quan

Bộ script cá nhân/team quản lý setup Claude Code: đổi endpoint auth nhanh (subscription ↔ proxy 9router ↔ vendor khác), cài mechanism "orchestrator + delegate subagent" (kèm rules, hooks, git pre-push scan) cho project khác dùng, và tinh chỉnh context window của Claude Code. Các phần **độc lập** — chỉ cần phần nào thì cài phần đó, không phụ thuộc dây chuyền.

| Muốn... | Cài phần |
|---|---|
| Đổi model/endpoint Claude Code nhanh (Claude/Codex/DeepSeek/Kimi qua proxy 9router, hoặc quay lại subscription) | **Phần 1** |
| Cài mechanism delegate subagent + rules + guard hooks + git pre-push scan vào **project khác** | **Phần 2** |
| Chỉnh mốc Claude Code tự nén hội thoại (hoặc tắt hẳn) | **Phần 3** |
| Giảm context window bằng cách tắt tính năng Claude Code không cần (`disableWorkflows`) | **Phần 4** |

### Yêu cầu hệ thống

| Dependency | Cần cho | Cài |
|---|---|---|
| `bash` | Tất cả (mac/linux native; Windows qua Git Bash/WSL/Cygwin) | có sẵn mac/linux; Windows: Git Bash hoặc WSL |
| `jq` | Phần 1 (profile JSON), Phần 2 (wire `settings.json`), Phần 3 (`autoCompactWindow`), Phần 4 (`disableWorkflows`) | `brew install jq` / `apt install jq` |
| `curl` | Phần 1 (health-check proxy) | có sẵn hầu hết hệ thống |
| `git` | Phần 2 (worktree isolation cho delegate wrapper + git pre-push hook) | `brew install git` / `apt install git` |
| `gitleaks` | Phần 2 (git pre-push scan) | `brew install gitleaks` — thiếu thì hook advisory-skip, không chặn |
| `bats-core` | Chạy test suite (dev, không cần cho user cuối) | `brew install bats-core` |
| `aider`/`codex`/`gemini` CLI | Phần 2 — chỉ cần trên **project đích** nếu thật sự gọi delegate subagent tương ứng, không cần lúc cài | xem persona `delegate-*.md` sau khi cài |

Repo này gồm 4 phần độc lập:

1. **[`install-9router-proxy.sh`](#phần-1--ccswitch-endpoint-switcher)** — `ccswitch` CLI, đổi endpoint auth của Claude Code (9router / subscription). Lần đầu clone chạy [`install-first-time.sh`](#phần-1--ccswitch-endpoint-switcher) (alias của script này, tên rõ nghĩa hơn).
2. **[`install-harness.sh`](#phần-2--harness-orchestrator--subagent)** — cài mechanism orchestrator + delegate subagent (agent persona, wrapper script, rules, guard/quality hooks, slash commands, skills, git pre-push hook) vào **project khác**.
3. **[`install-auto-compact.sh`](#phần-3--auto-compact-window)** — chỉnh mốc `autoCompactWindow` (khi nào Claude Code tự nén context) hoặc tắt hẳn tính năng, qua `~/.claude/settings.json` (hoặc `./.claude/settings.json` cho riêng project).
4. **[`install-optimize-claude.sh`](#phần-4--optimize-claude)** — đọc `.env` (repo root), ghi `~/.claude/settings.json` để tắt tính năng nặng (vd `disableWorkflows`) nhằm giảm context window.

Phần 1 tự detect OS (macOS/Linux chạy bash trực tiếp; Windows qua Git Bash/WSL/Cygwin tự gọi PowerShell) — không cần chọn `.sh` hay `.ps1` thủ công. Phần 2 — delegate wrapper bash-only, Windows cần WSL/Git-Bash, không chạy CMD/PowerShell thuần. Phần 3 và 4 — thuần bash + `jq`, không có bản `.ps1`, chạy trên Windows cần Git Bash/WSL.

---

## Phần 1 — ccswitch (endpoint switcher)

Đổi nhanh endpoint auth của **Claude Code** giữa các model qua **9router** và **subscription** (OAuth login gốc của Claude Code) — chỉ thay block `env` trong `~/.claude/settings.json`, không đụng phần còn lại (hooks, permissions...).

| Target | Cơ chế | Vai trò |
|---|---|---|
| **`claude`** | `env` = 9router + model `cc/*` (claude) | ⭐ **DEFAULT** — Claude qua 9router |
| `codex` | 9router + model `cx/*` | Codex/GPT qua 9router |
| `deepseek` | 9router + model `ds/*` | DeepSeek qua 9router |
| `kimi` | 9router + model `kimi/*` | Kimi qua 9router |
| `subscription` | **gỡ block `env`** | Safe-harbor fallback — Claude Code dùng OAuth subscription login (không cần key) |

> `claude` / `codex` / `deepseek` / `kimi` **chung 1 base URL** `https://9router.proxy.example.com/v1` **và chung 1 key** (điền cùng 1 token 9router vào cả 4 profile); khác nhau **chỉ ở model prefix** (`cc/` vs `cx/` vs `ds/` vs `kimi/`).
>
> `subscription` KHÔNG phải profile file: nó xóa block `env` để Claude Code quay về OAuth login gốc.
> Alias tương thích ngược: `original` / `direct` / `clear` → `subscription`.
>
> Kimi có mode phụ **direct-endpoint** (`kimi_api_key_force_subscription=1` trong `.env`): profile `kimi.json` trỏ thẳng endpoint Anthropic-compatible của Kimi `https://api.moonshot.ai/anthropic` với key Kimi riêng, không đi qua 9router. Mặc định (`=0`) → Kimi đi qua 9router như 3 target còn lại.

### 1.1 Cài đặt

```bash
git clone git@github.com:acegalaxy-co/ace_commons-ccswitch-cli.git
cd ace_commons-ccswitch-cli
bash install-first-time.sh    # bootstrap lần đầu — alias của install-9router-proxy.sh, tên rõ nghĩa
```

> Phải chạy bằng **đường dẫn script** lần đầu vì lệnh global `ccswitch` chưa tồn tại tới khi bootstrap xong. Sau đó re-sync mọi nơi bằng `ccswitch install proxy` (xem [1.4](#14-cài-lại--các-installer-khác-qua-ccswitch-install)).

Windows: chạy lệnh trên trong Git Bash / WSL / Cygwin — script tự gọi `powershell.exe -File setup.ps1` bên dưới. Cần `jq` + `curl` (mac: `brew install jq`; ubuntu/debian: `sudo apt install -y jq curl`).

> Health-check hook dùng `bash` (Git Bash / WSL). Không có cũng không sao — hook tự bỏ qua, `ccswitch` vẫn chạy.

Installer sẽ:
1. Copy `ccswitch` + hook + **profile template** vào `~/.claude/`.
2. Wire hook `SessionStart` (probe endpoint, cảnh báo nếu DOWN) — idempotent.
3. Cài `statusline-context.sh` (statusLine hiển thị % context-window đã dùng).
4. Thêm alias/function `ccswitch` vào shell profile.
5. **KHÔNG ghi đè** profile đã có key thật (chỉ copy template khi file thiếu).

### 1.2 Điền key (1 key dùng chung cho cả 4 profile)

**Cách nhanh nhất — `.env`:** tạo file `.env` (gitignored) ở repo root:

```bash
proxy_host=https://9router.proxy.example.com/v1
proxy_key=<your-9router-key>

# optional: Kimi direct-endpoint mode (bypass 9router, dùng endpoint Kimi thật)
kimi_api_key_force_subscription=1
kimi_api_key=<your-kimi-key>
```

(mẫu có sẵn ở `.env.example`). Khi `setup.sh`/`setup.ps1` chạy và thấy file này có đủ cả 2 biến, nó **ghi thẳng** `proxy_host` + `proxy_key` vào cả 4 file (`claude.json` / `codex.json` / `deepseek.json` / `kimi.json`) — không hỏi, interactive hay non-interactive đều như nhau. Nếu `kimi_api_key_force_subscription=1` + `kimi_api_key` có mặt, nó ghi riêng `~/.claude/profiles/kimi.json` với endpoint Anthropic-compatible thật của Kimi `https://api.moonshot.ai/anthropic` (bỏ qua 9router). `.env` là source of truth: một profile đã có key thật vẫn bị ghi đè (có in thông báo overwrite), chạy lại script bất kỳ lúc nào để resync theo `.env` mới nhất.

Không có `.env`, hoặc thiếu 1 trong 2 biến → bỏ qua bước này, dùng flow nhập tay:

```bash
# mac/linux — nhập ẩn rồi apply luôn. claude + codex + deepseek + kimi dùng CÙNG 1 key 9router.
ccswitch set-key claude       # key cho Claude qua 9router
ccswitch set-key codex        # Codex/GPT qua 9router — điền cùng token với claude
ccswitch set-key deepseek     # DeepSeek qua 9router — điền cùng token với claude
ccswitch set-key kimi         # Kimi qua 9router — điền cùng token với claude
```

Hoặc sửa file trực tiếp:

```bash
$EDITOR ~/.claude/profiles/deepseek.json     # thay <your-9router-key>
```
```powershell
notepad $env:USERPROFILE\.claude\profiles\deepseek.json
```

> 🔑 Xin key từ lead. `claude` + `codex` + `deepseek` + `kimi` **chung 1 token** (điền giống nhau vào cả 4 file). **Không commit key** — `~/.claude/profiles/*.json` và `.env` đều local, không đẩy git.

Đã đổi key/host của `claude` và muốn đồng bộ lại các profile khác cho khớp (không phải setup lần đầu)? Dùng `update`:

```bash
ccswitch update claude    # copy ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN từ claude.json sang codex/deepseek/kimi.json
                           # hỏi [y/N] trước khi ghi đè từng file — model prefix (cc/cx/ds/kimi) giữ nguyên
```

### 1.3 Dùng

```bash
ccswitch                # xem target đang active (theo model prefix) + health + subscription note
ccswitch claude         # → Claude qua 9router (default)
ccswitch codex          # → Codex/GPT qua 9router
ccswitch deepseek       # → DeepSeek qua 9router
ccswitch kimi           # → Kimi qua 9router
ccswitch subscription   # → gỡ env block, dùng OAuth subscription login
ccswitch spawn <target> # → mở 1 instance RIÊNG ghim target đó (settings.json không đổi)
ccswitch check          # probe health các profile + verify subscription OAuth
ccswitch fallback       # giữ target đang active nếu router healthy; router chết → subscription
ccswitch set-key [t]    # nhập key mới (ẩn) cho target t (default claude) rồi apply
ccswitch set-host <url> [t]  # ghi base URL vào profile t (default claude) rồi apply
ccswitch update [src]   # đồng bộ host+key từ profile src (default claude) sang các profile còn lại — hỏi [y/N] từng cái
ccswitch clear          # alias của subscription (gỡ block env)
ccswitch install [name] # chạy lại installer từ bất kỳ đâu (xem 1.4)
ccswitch help           # (hoặc -h) in bảng lệnh + target đầy đủ
```

Windows: cú pháp giống hệt (`ccswitch claude`, ...).

> ⚠️ **Sau mỗi lần switch phải RESTART Claude Code** (quit + mở lại) — env chỉ load lúc khởi động.

### 1.4 Cài lại / các installer khác qua `ccswitch install`

Sau bootstrap lần đầu, lệnh `ccswitch` global gọi lại được mọi `install-*.sh` từ **bất kỳ đâu** (không cần `cd` về repo). Setup ghi đường dẫn repo vào `~/.claude/.ccswitch-repo` để `ccswitch` tìm lại script.

```bash
ccswitch install               # in danh sách installer + mô tả 1 dòng
ccswitch install first-time    # bootstrap lại (= install-9router-proxy.sh)
ccswitch install proxy         # re-sync ccswitch + profiles + hook (OS-detect)
ccswitch install auto-compact  # chỉnh mốc auto-compact của Claude Code
ccswitch install optimize      # tắt feature nuốt context
ccswitch install harness [...] # cài harness sang project khác (forward args)
```

> Chạy được mọi nơi vì repo path đã lưu ở `~/.claude/.ccswitch-repo`. Nếu xoá file đó / đổi chỗ repo → chạy lại `bash <repo>/install-9router-proxy.sh` một lần để ghi lại path.

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
  kimi: 200 OK
  subscription: ✓ logged in (you@example.com, max) [keychain] → safe-harbor OK
profiles: claude codex deepseek kimi
```

#### Chạy nhiều vendor SONG SONG

`ccswitch <target>` chỉ đổi **1 instance** — 1 process Claude Code đọc 1 block `env` → 1 model. Muốn **nhiều vendor cùng active** thì cần **nhiều process riêng**. Dùng `spawn` (hoặc 4 alias `setup` tạo sẵn):

```
# mỗi lệnh trong 1 terminal riêng → 4 vendor chạy đồng thời
claude-cc      # = ccswitch spawn claude    → Claude (cc/*)
claude-cx      # = ccswitch spawn codex     → Codex/GPT (cx/*)
claude-ds      # = ccswitch spawn deepseek  → DeepSeek (ds/*)
claude-km      # = ccswitch spawn kimi      → Kimi (kimi/*)
```

`spawn` export model vào **process env** (tầng ① — thắng mọi settings file) rồi gọi `claude`, nên **KHÔNG đụng `settings.json`** — target đang switch-in-place của bạn giữ nguyên. Không cần restart: mỗi instance sinh ra đã pin sẵn vendor.

> ⚠️ **Quota chung.** Cả 4 target cùng đi qua 1 account 9router (chung 1 key) → **share chung 1 quota**. Chạy song song = đốt quota nhanh hơn tương ứng số instance. Chung 1 token, KHÔNG tách quota (1 email = 1 quota); tách thật cần account 9router khác email.
>
> `spawn subscription` bị từ chối — subscription là env-clear (gỡ block), không có gì để export. Muốn subscription thì `ccswitch subscription` rồi chạy `claude` thường.

### 1.4 Model — prefix theo target

Model qua 9router **phải** có prefix. Mỗi profile map sẵn 4 tier (Opus/Sonnet/Haiku/Fable) vì Claude Code luôn request theo tier:

| Target | Prefix | Ví dụ (Opus tier) |
|---|---|---|
| `claude` | `cc/` (claude) | `cc/claude-opus-4-8` |
| `codex` | `cx/` | `cx/gpt-5.6-sol` |
| `deepseek` | `ds/` | `ds/deepseek-v4-pro-max` |
| `kimi` | `kimi/` | `kimi/kimi-k3` |

Thiếu prefix → lỗi `model_not_found`. Xem model id đầy đủ trong `~/.claude/profiles/<target>.json`, hoặc list live: `curl -s https://9router.proxy.example.com/v1/models -H "Authorization: Bearer <key>" | jq -r '.data[].id'`. (Ở `subscription` — không có env block — Claude Code tự dùng model mặc định của tài khoản, không cần prefix.)

### 1.5 Troubleshoot

**`ccswitch` báo `claude: 000 DOWN` nhưng endpoint vẫn sống**
Thường do **IPv6 route hỏng** — host resolve ra cả A (IPv4) + AAAA (IPv6), nhưng path IPv6 timeout. Claude Code (Node) tự né sang IPv4 nên vẫn chạy; chỉ `curl`/health-probe bị kẹt. Xác minh:
```bash
curl -4 --resolve 9router.proxy.example.com:443:<proxy-ipv4> https://9router.proxy.example.com/v1/models -H "Authorization: Bearer <key>"
```
Nếu IPv4 trả `200` → endpoint OK, bỏ qua cảnh báo. Muốn dứt điểm: pin IPv4 vào `/etc/hosts`.

**`No active credentials for provider` / `model_not_found`**
Sai model id — thêm prefix đúng target (`cc/` claude, `cx/` codex, `ds/` deepseek, `kimi/` kimi — xem mục 1.4).

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

## Phần 2 — harness (orchestrator + subagent)

Cài mechanism "orchestrator giữ vai reasoning + delegate subagent thực thi" (xem [`.claude/rules/common/orchestrator.md`](.claude/rules/common/orchestrator.md)) vào **project khác** (không phải repo này) — copy agent persona + delegate wrapper script + rules + guard/quality hooks + slash commands + skills + git pre-push hook, rồi wire vào `.claude/settings.json` của project đích.

### 2.1 Cài đặt

```bash
bash install-harness.sh
```

Interactive: hỏi cài vào project nào (nhập path, hoặc dùng project đang mở ở terminal), rồi hỏi cài toàn bộ + overwrite file cũ hay huỷ. Non-interactive (script/CI): mọi câu hỏi có env var override tương ứng — xem comment đầu file [`harness/install.sh`](harness/install.sh) (`HARNESS_ROUTE_DIR`, `HARNESS_PROJECT_SLUG`, `HARNESS_GROUP_*`...).

Delegate wrapper là **bash-only** — Windows cần WSL hoặc Git Bash (không chạy CMD/PowerShell thuần).

### 2.2 Cài gì vào project đích

8 nhóm, mỗi nhóm bật/tắt độc lập (mặc định tất cả Y):

| Nhóm | Env override | File cài vào project đích |
|---|---|---|
| **subagents + wrappers** | `HARNESS_GROUP_SUBAGENTS` | `.claude/agents/delegate-{deepseek,gemini,codex,sonnet}.md` + `scripts/delegate/*.sh` (`_common`, `run-aider-deepseek`, `run-codex`, `run-gemini`, `doctor` + `lib/`) |
| **guard hooks** | `HARNESS_GROUP_GUARD` | `.claude/hooks/{pre-edit-orchestrator-gate,pre-bash-orchestrator-gate,pre-edit-secret-scan}.sh` (wire `PreToolUse` cho `Edit`/`Write`/`MultiEdit`/`Bash`) |
| **quality hooks** | `HARNESS_GROUP_QUALITY` | `.claude/hooks/post-edit-syntax-check.sh` (wire `PostToolUse`) + `session-start-banner.sh` (wire `SessionStart`) |
| **commands** | `HARNESS_GROUP_COMMANDS` | `.claude/commands/{git-push-safety,git-commit,git-commit-describe,git-cleanup-branch,git-force-snapshot,clean-up,doctor-memory,audit-context-memory,audit-dependency,audit-vietnamese,audit-claude-md,task-loop-feature}.md` |
| **skills** | `HARNESS_GROUP_SKILLS` | `.claude/skills/{lazy-load-health,dep-ladder-check,auto-commit,check-hardcode,audit-git-leak,fix-ledger}/SKILL.md` |
| **rules** | `HARNESS_GROUP_RULES` | `.claude/rules/common/*.md` (8 invariant guardrail — always overwrite) + `.claude/rules/project/{git-workflow,skill-superpowers}.md` (giữ nguyên nếu đã tồn tại) |
| **git pre-push hook** | `HARNESS_GROUP_GITHOOKS` | `.git/hooks/pre-push` (gitleaks secret scan) — bỏ qua nếu target không phải git repo |

Wiring `.claude/settings.json` dùng `jq` merge **idempotent** — chạy lại không tạo hook trùng lặp. Off-switch không cần gỡ cài: set `env.HARNESS_DELEGATE=0` trong `.claude/settings.json` của project đích.

Template gốc nằm ở `harness/templates/` — installer thay placeholder `@@PROJECT_SLUG@@`/`@@CORE_DIRS_CASE@@`/`@@CORE_DIRS_HUMAN@@`/`@@CORE_DIRS_YAML@@`/`@@BRANCH@@`/`@@TEST_CMD@@` bằng giá trị của project đích trước khi ghi file.

Ví dụ chạy interactive (chọn cài vào project đang mở ở terminal, giữ mặc định Y cho mọi câu hỏi):

```text
$ bash install-harness.sh
Cài harness vào project nào — 1) nhập đường dẫn project ...  2) cài vào project đang mở ở terminal này [1]: 2
📁 Install target: /Users/you/projects/my-app
Cài harness vào đúng đường dẫn này [Y/n]: y
Cài toàn bộ harness và override mọi file đã tồn tại [Y/n]: y
  ✓ .claude/agents/delegate-deepseek.md
  ✓ scripts/delegate/_common.sh
  ... (toàn bộ script + hooks + commands + skills + rules)
  ✓ .git/hooks/pre-push
✅ Wired .claude/settings.json (hooks: PreToolUse, PostToolUse, SessionStart, UserPromptSubmit)
✅ Xong. Chạy scripts/delegate/doctor.sh trong project đích để kiểm tra CLI + env key.
```

Sau khi cài, chạy `scripts/delegate/doctor.sh` (trong project đích) để kiểm tra preflight — CLI `git`/`jq`/`aider`/`codex`/`gemini` có cài chưa, có đang trong git repo không, key 9router/`deepseek_api_key` resolve được không (không bao giờ in giá trị secret thật) — và health của hooks: wiring trong `settings.json`, orphan (hook có file nhưng chưa wire), cú pháp `bash -n` từng hook, và có bị drift so với template gốc trong `harness/templates/hooks/` không:

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

Hooks:
  ✓ wired: pre-bash-gate.sh
  ✓ syntax: session-start.sh
  ✓ template match: pre-edit-orchestrator-gate.sh
  ... (lặp cho từng hook: wired/syntax/template match)

30 pass, 1 fail
```

### 2.3 git pre-push hook (nhóm GITHOOKS)

Nhóm `GITHOOKS` cài `.git/hooks/pre-push` vào project đích — chặn `git push` nếu `gitleaks` phát hiện secret. Cần chạy lại installer sau mỗi lần `git clone` mới (hook không tự nhân bản qua clone). Thiếu `gitleaks` → hook chỉ cảnh báo advisory, không chặn.

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

Slash command `/git-push-safety` (cài trong nhóm `COMMANDS`) gom pipeline gate đầy đủ trước push: smoke test → gitleaks scan → sensitive-content review → push (chỉ khi cả 3 pass).

### 2.4 Chạy test thủ công (dev repo này)

```bash
brew install bats-core   # 1 lần, nếu chưa có
bats test/*.bats
```

Test dùng `$HOME` giả (`$BATS_TEST_TMPDIR`) — không đụng `~/.claude` thật của máy chạy test.

### 2.5 Troubleshoot

**Cài xong nhưng hook không chạy trong project đích**
Kiểm tra `.claude/settings.json` project đích có block `hooks.PreToolUse`/`PostToolUse`/... trỏ đúng script không — `jq . .claude/settings.json` xem JSON còn hợp lệ. Restart Claude Code sau khi wire hook (hook load lúc session start).

**Muốn tắt tạm mechanism mà không gỡ cài**
Set `env.HARNESS_DELEGATE=0` trong `.claude/settings.json` của project đích — không cần chạy lại installer hay xoá file.

**Chạy lại installer, sợ mất tuỳ chỉnh đã sửa tay trong project đích**
`HARNESS_INSTALL_ALL=Y` (mặc định) ghi đè mọi file đã cài — nếu bạn từng sửa tay 1 hook/command sau khi cài, sửa đó sẽ mất khi chạy lại. Diff trước khi chạy lại, hoặc set `HARNESS_GROUP_<NHÓM>=n` để bỏ qua đúng nhóm đã tự sửa. (Rule `.claude/rules/project/` luôn được giữ nguyên khi re-sync; chỉ `.claude/rules/common/` bị overwrite.)

**`delegate-deepseek`/`delegate-codex`/`delegate-gemini` báo lỗi thiếu CLI/key**
Chạy `scripts/delegate/doctor.sh` trong project đích trước — báo rõ CLI nào thiếu, key 9router/deepseek có resolve không, mà không lộ giá trị secret.

**Windows CMD/PowerShell thuần chạy installer báo lỗi cú pháp bash**
Đúng hành vi — Phần 2 bash-only. Chạy qua Git Bash hoặc WSL.

---

## Phần 3 — auto-compact window

Chỉnh khi nào Claude Code tự nén (compact) hội thoại để tránh tràn context, hoặc tắt hẳn tính năng — đứng riêng, không phụ thuộc phần khác (không cài `ccswitch`).

Key config: `autoCompactWindow` (số token tuyệt đối). Ngưỡng thực compact = `min(autoCompactWindow, model max context)`. Ví dụ Opus context ~200k → set `190000` ≈ 95%. Anthropic khuyến nghị để **auto** (Claude tự chọn theo model) — đặt mốc thấp = compact sớm hơn, có thể mất context giữa task nặng.

### 3.1 Dùng

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

### 3.2 Troubleshoot

**`jq: command not found`**
Script hard-require `jq` — cài `brew install jq` (mac) / `apt install jq` (linux) rồi chạy lại.

**Set `--project` nhưng vẫn thấy hành vi global**
`--project` ghi vào `./.claude/settings.json` — chạy lệnh đúng tại **project root**, không phải thư mục con. `status` không kèm cờ nào mặc định đọc global; kiểm tra đúng file bằng `install-auto-compact.sh --project status`.

**Set mốc xong Claude Code không đổi hành vi compact**
Cần **session mới** để đọc lại `settings.json` — reload/restart Claude Code sau khi `set`/`auto`/`off`/`on`.

**Set mốc rồi mà vẫn compact sớm bất thường**
Kiểm tra `env.DISABLE_AUTO_COMPACT` — nếu vẫn có giá trị cũ hoặc mốc `autoCompactWindow` bị project-level `settings.json` đè lại global (project thắng global).

---

## Phần 4 — optimize claude

Giảm context window bằng cách tắt tính năng nặng của Claude Code không dùng đến — đọc config từ `.env` (repo root), ghi `~/.claude/settings.json`. Đứng riêng, không phụ thuộc phần khác.

### 4.1 Dùng

```bash
install-optimize-claude.sh
```

Script đọc key `disableWorkflows` trong `.env` (repo root):

```bash
# trong .env
disableWorkflows=true
```

- `disableWorkflows=true` → ghi `settings.json` tắt "Dynamic workflows" (script JS Claude tự viết để orchestrate nhiều subagent quy mô lớn — KHÁC `.claude/workflows/` CI/CD). Tắt xong `/deep-research`, keyword `ultracode`, `/workflows` view không dùng được. KHÔNG ảnh hưởng Subagent (Agent tool), Skill, `/loop`, orchestrator routing rule.
- `.env` không có `disableWorkflows` → script bỏ qua, không đụng gì.

Yêu cầu `jq`. Tự tạo `settings.json` (`{}`) nếu chưa có. Cần **session mới** để Claude Code đọc lại settings sau khi chạy.

Bash-only, không có bản `.ps1` — Windows chạy qua Git Bash/WSL.

---

## File trong package

```
ccswitch-cli-claude/
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
│       ├── deepseek.json              # deepseek ds/*  (same key as claude.json)
│       └── kimi.json                  # kimi kimi/*  (same key; direct-endpoint mode nếu force-subscription)
│                                       # subscription không có file — nó là env-clear
│
├── install-harness.sh   # Phần 2 — entry point (thin wrapper, exec harness/install.sh)
├── harness/
│   ├── install.sh                     # Phần 2 — installer thật, wire settings.json qua jq
│   └── templates/                     # Phần 2 — template gốc, placeholder @@...@@ thay theo project đích
│       ├── agents/delegate-{codex,deepseek,gemini,sonnet}.md
│       ├── scripts/delegate/               # wrapper script (_common, run-aider-deepseek, run-codex, run-gemini, doctor + lib/)
│       ├── hooks/{pre-edit-orchestrator-gate,pre-bash-orchestrator-gate,pre-edit-secret-scan,post-edit-syntax-check,session-start-banner}.sh
│       ├── commands/*.md                   # 12 slash command
│       ├── skills/{lazy-load-health,dep-ladder-check,auto-commit,check-hardcode,audit-git-leak,fix-ledger}/
│       ├── rules/{common,project}/*.md     # common (8 guardrail) + project (git-workflow, skill-superpowers)
│       └── git-hooks/pre-push              # gitleaks scan trước push (cài vào .git/hooks/ project đích)
│
├── install-auto-compact.sh       # Phần 3 — set/auto/off/on/status autoCompactWindow, đứng riêng
├── install-optimize-claude.sh    # Phần 4 — disableWorkflows từ .env, đứng riêng
│
├── scripts/delegate/             # bản wrapper THẬT dùng trong repo này (đồng bộ với harness/templates/scripts/delegate/)
├── .claude/                      # harness bản THẬT của repo này (agents, hooks, commands, skills, rules)
└── test/*.bats                   # bats suite (9 file, 130 test) — chạy qua /git-push-safety hoặc thủ công
```
