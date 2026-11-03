---
name: git-push-safety
description: "Chạy test, gitleaks (chỉ commit sắp push), sensitive-content scan; chỉ push nếu cả 3 pass — qua script `push-safe.sh`, không hỏi confirm. `--scan-only` chỉ scan, không test/push; `--full` quét toàn bộ history. Dùng khi \"audit git leak\", \"check leak trước khi push\", hoặc trước mọi lệnh push GitHub."
disable-model-invocation: true
user-invocable: true
---
> **Push KHÔNG cần hỏi confirm (user đã chốt):** chế độ push = chạy script
> `push-safe.sh` bên dưới — script tự chạy đủ bước 1–3 + kiểm file lớn/cấm, pass mới push,
> rồi verify `ls-remote`. Không hỏi user trước khi push. Vẫn cấm force-push / `--all` /
> `--mirror` / `--tags`, vẫn tôn trọng gate nhánh riêng tư (`.claude/private-branches.txt`).
> Hành động phá huỷ khác (xoá branch/remote, rewrite history, force-push): gọi lệnh không phải là xác nhận —
> liệt kê target + tác động, hỏi user xác nhận rõ và chờ.

## Cách chạy (mặc định) — `push-safe.sh`

```bash
cd <repo tuyệt đối> && sh .claude/skills/git-push-safety/push-safe.sh [--full] <remote> <branch>
```

- Hook `pre-bash-gate.sh` cho qua đúng lệnh này (không nối thêm `git push` thô); raw `git push` vẫn bị chặn.
- Script: chặn flag nguy hiểm → gate nhánh riêng tư → gitleaks có cài → test auto-detect → gitleaks phạm vi push
  (để `.git/hooks/pre-push` quét nếu hook harness đã cài, không quét 2 lần) + diff chưa commit → `sensitive-patterns.txt`
  → file ≥ 95 MB / `.env*`/key tracked → detect RBAC/deploy-surface/README (in ra, agent PHẢI đọc + làm bước 3.5–3.7 nếu
  báo DETECTED) → push → verify `ls-remote` = SHA. Remote diverged (non-fast-forward) → STOP, không force.
- Push không kết nối được + đặt `PUSH_SAFE_PROXY_JUMP=<host>` → tự thử lại 1 lần qua `ssh -o ProxyJump=<host>`.
- Nhiều branch/remote → gọi script lần lượt từng `<remote> <branch>` (remote chính trước).
- Bước `/check-hardcode` + đọc diff (bước 3) là phán đoán: diff lớn/lạ → chạy trước khi gọi script.

Các mục dưới mô tả chi tiết từng bước (script đã tự động hoá phần cơ học).

## Chế độ `--scan-only`

Khi được gọi với `--scan-only` (hoặc user chỉ muốn check leak, không push):
chạy CHỈ bước 2 (gitleaks) + bước 3 (sensitive-content scan, gồm
`/check-hardcode`) bên dưới — 2 bước này song song. Bỏ qua bước 1 (tests), 3.5 (README drift) và
bước 4 (push). Đây là chế độ read-only — không stage, không commit, không
push gì. Dùng trước `/git-force-snapshot`, sau `/clean-up-project`, hoặc bất
cứ khi nào user chỉ muốn xác nhận không có leak. Kết thúc: báo PASS/FAIL
từng bước đã chạy (2 và 3) kèm finding đã redact.

Bước 1 (tests), 2 (gitleaks), 3 (sensitive scan) **độc lập nhau → chạy song
song**: gửi chung 1 message 3 Bash tool-call (hoặc `run_in_background` từng
bước rồi gom). Bất kỳ bước nào fail → DỪNG, không push, báo ĐỦ mọi bước fail
(không chỉ bước đầu). Bước 3.5 chờ diff từ bước 3; bước 4 chờ cả 1–3.5 pass.
Không skip bước. Report kết quả từng bước cho user khi hoàn thành.

## 1. Tests

Đầu tiên phát hiện lệnh test của project bằng cách kiểm tra repo (theo
thứ tự này, dừng ở match đầu tiên):

- có `test/*.bats` → chạy song song max: `bats -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" test/*.bats`.
  Nếu bats báo thiếu GNU parallel (`-j` cần `parallel`/`rush`) → fallback `BATS_SERIAL_OK=1 bats test/*.bats`
  (hook chặn bats nhiều file không `-j`) và cảnh báo user cài `parallel` (macOS `brew install parallel`). Xem `[[test-parallel]]`.
- `package.json` có field `scripts.test` → `npm test`
- có `pyproject.toml`, `pytest.ini`, hoặc thư mục `tests/` → `pytest`
- có `go.mod` → `go test ./...`
- có `Cargo.toml` → `cargo test`
- không cái nào ở trên → KHÔNG đoán. Check README / CI config để tìm
  lệnh test, hoặc hỏi user. Không im lặng skip bước này.

Chạy lệnh đã phát hiện (song song với bước 2, 3). Nếu bất kỳ test nào fail
(exit code khác 0), DỪNG — không push. Báo tên test fail. Không tự fix hay
retry — báo lỗi rõ ràng và hỏi user cách xử lý tiếp.

## 2. gitleaks scan — chỉ phạm vi push, MỘT lần

**Không full scan history** trừ khi user yêu cầu rõ (`--full`). Commit đã lên
remote = đã quét ở lần push trước; quét lại toàn bộ history mỗi lần push rất nặng
(repo game vài GB).

**Chế độ push (mặc định): KHÔNG tự chạy gitleaks ở bước này.** Hook
`.git/hooks/pre-push` (harness) quét đúng các commit sắp push ở bước 4
(`<remote-sha>..<local-sha>`, nhánh mới `<sha> --not --remotes`) — chạy gitleaks ở
đây nữa là quét 2 lần. Bước này chỉ kiểm điều kiện:

```bash
command -v gitleaks >/dev/null || echo MISSING-gitleaks
grep -q 'GITLEAKS_FULL' "$(git rev-parse --git-path hooks)/pre-push" 2>/dev/null || echo MISSING-hook
```

- `MISSING-gitleaks` → DỪNG, báo user cài (xem dưới). Không im lặng skip.
- `MISSING-hook` (hook chưa cài / bản cũ quét full) → báo user chạy lại harness
  `install.sh update`; trong lúc chờ, tự quét phạm vi push 1 lần bằng lệnh `--scan-only`
  bên dưới thay cho hook.
- Bước 4 push mà hook báo `❌ gitleaks phát hiện secret` → push đã bị chặn: DỪNG,
  hiện finding đã redact, không push lại.

**Chế độ `--scan-only`** (không push → không có hook): quét commit chưa lên remote +
thay đổi chưa commit, không quét history cũ:

```bash
ROOT="$(git rev-parse --show-toplevel)"
[ "$(git rev-list --count HEAD --not --remotes)" -gt 0 ] &&
  nice -n 10 gitleaks git --no-banner --redact -v --max-target-megabytes 10 --log-opts="HEAD --not --remotes" "$ROOT"
git diff HEAD | gitleaks stdin --no-banner --redact -v
```

**`--full`** (chỉ khi user yêu cầu rõ "full scan", "quét toàn bộ history"):
`--scan-only --full` → `nice -n 10 gitleaks git --no-banner --redact -v "$ROOT"`;
push `--full` → push với `GITLEAKS_FULL=1` để hook quét toàn bộ (không chạy thêm ở bước này).

Nếu gitleaks chưa cài, DỪNG và báo user cài đặt. Đề xuất lệnh theo platform của họ:

- macOS: `brew install gitleaks`
- Linux: package manager của distro (`apt install gitleaks`, `pacman -S gitleaks`, …)
- Windows: `scoop install gitleaks` hoặc `choco install gitleaks`
- OS nào có Go: `go install github.com/gitleaks/gitleaks/v8@latest`

(Khác với advisory pre-push hook, command này coi scanner bị thiếu là hard stop,
vì user đã yêu cầu rõ ràng push có gate.)

Nếu gitleaks tìm thấy bất kỳ leak nào, DỪNG. Hiện finding đã redact và không
tiếp tục. Không dùng `GITLEAKS_SKIP=1` thay mặt user — bypass đó
là quyết định họ tự làm thủ công, không phải command tự quyết.

## 3. Sensitive-content scan

Trước tiên invoke skill `/check-hardcode` (quét rộng: IP/domain/email/generic
hardcode mà hook auto-block cố ý bỏ qua vì false-positive). Nếu skill report
finding đáng ngại, DỪNG — không tiếp tục sang phán đoán thủ công bên dưới.

Rồi chạy `git status` và `git diff --stat` (so với branch upstream/main, hoặc
`HEAD` nếu có thay đổi chưa commit) để xem mọi thứ sắp được push. Rồi
đọc qua các file đã đổi thật và check:

- API key, token, credential thật (không phải placeholder như `<your-api-key>`
  hoặc `sk-...`)
- URL, hostname, chi tiết infra nội bộ hardcode chưa từng xuất hiện
  ở nơi khác trong repo — gồm **production IP** (IP thật gắn server
  production, kể cả dải private `10.*`/`172.16-31.*`/`192.168.*` khi có
  context server thật, không phải IP ví dụ như `127.0.0.1`/`0.0.0.0`/doc
  example), **production domain/hostname thật** (endpoint router/proxy/API
  thật, không phải placeholder `example.com`/`<your-domain>`), và
  **domain/subdomain nội bộ của org** — kể cả trong comment, log mẫu,
  config sample. Danh sách domain nội bộ cần cảnh giác lấy từ config
  project (vd `.claude/allowed-hosts.txt` là host ĐÃ duyệt; host nội bộ
  khác chưa duyệt → nghi ngờ), không hardcode tên org trong skill.
  Có file `.claude/sensitive-patterns.txt` (gitignored, 1 regex/dòng: IP
  production, domain thật, domain nội bộ org) → `git diff <base>...HEAD | grep -nEf`
  file đó; hit → DỪNG. Không có file → chỉ dựa phán đoán thủ công, KHÔNG bịa pattern.- Thông tin cá nhân (email, tên) chưa public trong git history của repo
- File nào trông như bị stage nhầm (vd `.env`, `*.bak`, file swap editor,
  credential dump)

Đây là bước phán đoán vượt ngoài regex pattern của gitleaks — nó bắt được
những thứ như URL nội bộ và file bị include nhầm, không phải "secret" điển
hình. Nếu tìm thấy gì đáng ngại, DỪNG và mô tả nó — không tự
quyết định đơn phương là ổn.

Diff lớn hoặc nghi ngờ leak sâu hơn regex bắt được (secret ẩn trong history,
pattern lạ) → dispatch subagent `secret-scanner` để quét kỹ hơn trước khi
kết luận pass.

## 3.6. Deploy-surface check (nếu diff chạm CI/Docker/nginx/package.json)

Áp [[deploy-security]] mục 1, 2, 4: web root/static không trỏ repo checkout, `.dockerignore` loại `.env*`/`.git`/`.claude`/`CLAUDE.md`, npm lib có `files`, không file nhạy cảm tracked. Vi phạm → STOP trước push.

## 3.7. RBAC Scan (nếu repo có RBAC)

Đọc `.claude/rules/common/rbac-security.md`, chạy mục 1 (detect); có RBAC → mục 2 trên range sắp push. Fail → STOP trước push. In bảng mục 4.

## 3.5. README drift check (nếu repo có README ở root)

Chỉ chạy khi diff sắp push (bước 3) chạm tới thứ README mô tả:
CLI flag/command name, install/setup step, usage example, config key,
env var, hoặc public API. Diff chỉ đụng internal (test, refactor, comment)
mà không đổi behavior user-facing → SKIP bước này.

Nếu có: đọc README root, đối chiếu với thay đổi thật trong diff. Tìm:

- Command/flag đã đổi tên/xoá nhưng README còn ghi cũ
- Install/setup step lệch với script thực tế
- Usage example dùng syntax không còn đúng
- Env var / config key đã rename mà README chưa cập nhật

Lệch → DỪNG, báo user chính xác dòng nào sai + sửa đề xuất. KHÔNG tự
push với README stale (user cài theo hướng dẫn sai → lỗi thật). User
xác nhận sửa README (cùng commit hoặc commit riêng) rồi mới push.

## 4. Push

Chế độ mặc định: `push-safe.sh` tự push sau khi bước 1–3 pass (không hỏi confirm), push đúng
SHA đầu branch đã scan, rồi verify `ls-remote`. Không bao giờ force-push trong skill này trừ khi
user yêu cầu rõ trong conversation hiện tại.

`GIT_PUSH_GATE_OK=1 git push ...` là bypass do USER tự ra lệnh riêng — agent không tự thêm prefix
này để lách script. Hook `.git/hooks/pre-push` vẫn quét gitleaks phạm vi push lúc push
(`--full` → script đặt `GITLEAKS_FULL=1`).
