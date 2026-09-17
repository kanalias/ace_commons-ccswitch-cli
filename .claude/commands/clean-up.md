---
name: clean-up
description: Dọn dẹp project an toàn theo dry-run, phân loại rác/dead code/worktree/branch, yêu cầu xác nhận trước thao tác phá huỷ.
user-invocable: true
---

# /clean-up — cleanup project đúng nghĩa

## Mục tiêu

Dọn project theo hướng an toàn, có kiểm soát:

- Nhìn rõ trạng thái repo trước khi đụng file.
- Tìm và phân loại rác: file tạm, build artifacts, log cũ, generated junk, orphan worktrees, merged temp branches, dead code nghi vấn.
- Chạy dry-run trước, trình danh sách candidate cho user duyệt.
- Chỉ xoá/sửa sau khi user xác nhận rõ.
- Không đụng secrets, `.env*`, `_vault_/`, Notion records, protected branches, hoặc deploy/push nếu user không yêu cầu.

## Cách dùng / args

```text
/clean-up
/clean-up dry-run
/clean-up apply
/clean-up scope=<repo|worktree|branches|artifacts|logs|dead-code|all>
/clean-up workers=<N>
/clean-up --workers <N>
/clean-up --workers=<N>
/clean-up agents=<N>
/clean-up subagents=<N>
/clean-up since=<7d|30d|90d>
```

Mặc định nếu thiếu args:

```text
/clean-up dry-run scope=all workers=10
```

Quy ước args:

- `dry-run`: chỉ audit, không xoá, không sửa.
- `apply`: chỉ chạy sau khi đã có dry-run và user xác nhận danh sách cụ thể.
- `scope`: giới hạn nhóm cleanup.
- `workers` / `--workers` / `agents` / `subagents`: số subagent chạy song song. Default `10`, nhận integer, dùng value đầu tiên tìm thấy, clamp `1..20`; invalid/missing fallback `10` và báo trong report.
- `since`: ngưỡng tuổi cho log/artifact stale; mặc định `30d` nếu không nói.

## Quy trình dry-run

1. Đọc rule trong scope trước khi action: project scope, git workflow, secrets/vault, feature safety.
2. Parse worker count từ args. Default `10`; accepted forms: `workers=N`, `--workers N`, `--workers=N`, `agents=N`, `subagents=N`; clamp `1..20`; invalid fallback `10`.
3. Xác nhận branch hiện tại bằng `git branch --show-current`.
   - Nếu không phải `dev` và user không chỉ định branch/worktree riêng: dừng, báo mismatch.
4. Audit repo status:
   ```sh
   git status --short
   git diff --stat
   git worktree list
   ```
5. Loại trừ vùng cấm trước khi scan:
   - `.env*`
   - `_vault_/`
   - `node_modules/`
   - `.git/`
   - `.claude/worktrees/` khi grep/find source, trừ khi scope là `worktree`
   - `src/app/modules/sync/git_backup/**`
   - `src/app/modules/_private/**`
   - `src/app/modules/sub-git/**`
   - audit/gateway/PII logs
   - secrets/credentials/private keys
6. Thu candidate theo từng category, chỉ in path + lý do, không in nội dung file nhạy cảm.
7. Gom report dry-run theo output format bên dưới.
8. Hỏi user xác nhận trước mọi thao tác phá huỷ.

## Cleanup categories

### 1. Repo status audit

Mục tiêu: biết repo đang bẩn ở đâu trước khi cleanup.

Checklist:

- Modified/untracked files.
- Diff ngoài scope.
- File generated hoặc junk đang untracked.
- File cần giữ vì là work in progress.

Không tự revert, không tự reset, không tự commit.

### 2. Trash files

Candidate thường gặp:

- `.DS_Store`
- `*.tmp`
- `*.bak`
- `*.swp`
- editor crash files
- empty orphan dirs

Safe dry-run ví dụ:

```sh
find . -path ./.git -prune -o -path ./node_modules -prune -o -path ./.worktrees -prune -o -name .DS_Store -print
find . -path ./.git -prune -o -path ./node_modules -prune -o -path ./.worktrees -prune -o \( -name '*.tmp' -o -name '*.bak' -o -name '*.swp' \) -print
```

Apply chỉ xoá path đã duyệt. Không dùng `rm -rf`.

### 3. Build artifacts / generated junk

Candidate:

- `dist/`, `build/`, coverage output, cache dirs, generated report tạm.
- Chỉ xoá nếu repo quy ước generated và có thể tái tạo.

Dry-run ưu tiên:

```sh
git clean -ndX
```

Không chạy `git clean -fdx` trong command này. Nếu cần apply, đề xuất xoá từng path đã duyệt hoặc dùng lệnh scoped cực hẹp sau xác nhận.

### 4. Orphan worktrees

Mục tiêu: dọn `.claude/worktrees/` đúng rule, tránh xoá nhầm worktree hợp lệ.

Dry-run:

```sh
git worktree list
git worktree prune --dry-run
cd .worktrees && for d in */; do [ -e "$d/.git" ] || echo "ORPHAN non-worktree: $d"; done
```

Apply rules:

- Registered stale: dùng `git worktree prune` sau xác nhận.
- Orphan dir rỗng, không `.git`: dùng `rmdir <dir>`.
- Dir không rỗng: dừng, báo user.
- `.DS_Store`: được xoá sau xác nhận.
- `*.bundle`: move ra ngoài repo, không xoá.

### 5. Merged temp branches

Chỉ xem xét branch prefix whitelist:

- `feat/`
- `fix/`
- `hotfix/`
- `chore/`
- `refactor/`

Cấm đụng:

- `dev`
- `main`
- `stable`
- `prod`
- `release/*`
- branch ngoài whitelist
- branch commit cuối < 24h
- branch chưa merge vào current branch

Dry-run:

```sh
git branch --merged
git for-each-ref --format='%(refname:short) %(committerdate:iso8601)' refs/heads
```

Apply sau confirm:

```sh
git branch -d <branch>
git push origin --delete <branch>
```

Remote delete là best-effort, chỉ `origin`, chỉ sau user xác nhận.

### 6. Stale logs

Candidate:

- log file trong thư mục log/cache của project.
- file quá ngưỡng `since`.

Không mở/in log nếu có khả năng chứa token, Authorization header, cookie, webhook URL, connection string. Chỉ báo path, size, mtime.

### 7. Dead code nghi vấn

Dead code không xoá ngay chỉ vì grep ít thấy.

Dry-run cần phân loại:

- Export không còn import trong repo.
- File không được require/import.
- Script không được package.json gọi.
- TODO/legacy folder có owner không rõ.

Quy tắc:

- Subagent/read-only audit được dùng để tạo candidate.
- Không xoá code runtime nếu chưa có test/verify bao phủ.
- Nếu xoá dead code thật, phải có diff nhỏ, lý do rõ, verify chạy pass.

## Subagent routing

Mặc định chạy `10` read-only subagent song song cho discovery. Nếu prompt có `workers` / `agents` / `subagents`, dùng số đã parse và clamp `1..20`.

Agent ưu tiên cho discovery:

1. `delegate-gemini` — broad read-only audit.
2. `Explore` — fallback read-only search.
3. `general-purpose` — fallback cuối, phải ghi rõ read-only trong prompt.

Scope mặc định:

1. `repo-status`: git status, diff, untracked.
2. `trash-artifacts`: `.DS_Store`, tmp, cache, generated junk.
3. `worktrees`: `.claude/worktrees/`, stale registered worktree, orphan dirs.
4. `branches`: merged temp branches theo whitelist.
5. `logs`: stale logs, chỉ path/size/mtime.
6. `dead-code`: read-only candidate list.
7. `src/app/modules/hr/**` + `src/app/modules/iam/**`.
8. `src/app/modules/finance/**` + scheduler files.
9. `src/app/services/**` + `src/app/notion/**` + `src/app/llm/**`.
10. `test/**` + `.claude/**` docs/rules/commands read-only.

Nếu workers > scope count, split large scopes sau khi mỗi scope có 1 worker. Nếu workers < scope count, group adjacent scopes, không drop scope nào.

Rules cho subagent:

- Launch trong một message parallel tool calls.
- Prompt phải self-contained: repo path, branch, scope, denylist, output format.
- Discovery subagent chỉ dry-run và trả candidate.
- Không cho subagent xoá/sửa trực tiếp nếu user chưa xác nhận apply.
- Kết quả subagent phải được main agent tổng hợp, dedupe, rồi hỏi confirm.

Sau confirmation, route implementation:

- Mechanical/batch cleanup: `delegate-deepseek`.
- Normal source cleanup: `delegate-sonnet`.
- Security-sensitive cleanup hoặc invariant tinh vi: `delegate-codex`.

Delegate edit prompt bắt buộc có exact paths/actions, protected paths, verify commands, `NO commit — produce diff only`, summary `<300 words`. Main agent review diff trước report.

## Confirmation / destructive safety

Trước apply, luôn hiển thị bảng:

```text
[category] [action] [path/branch] [reason] [risk] [command]
```

Hỏi user chọn:

```text
Apply cleanup? [a]ll / [s]elect / [n]one
```

Quy tắc hard-stop:

- Không `rm -rf`.
- Không `git reset --hard`.
- Không `git clean -fdx`.
- Không sửa/xoá `.env*`, `_vault_/`, private keys, tokens, credentials.
- Không xoá Notion records.
- Không commit/push/deploy nếu user không yêu cầu.
- Không xoá protected branch.
- Không bypass hook hoặc permission deny.
- Không đọc/in nội dung file có thể chứa secret; chỉ dùng metadata/path.

Nếu phát hiện secret đã tracked hoặc lộ trong diff/log: dừng, báo compromised risk ngắn gọn, khuyến nghị rotate, không in lại secret.

## Verify

Sau dry-run:

```sh
git status --short
git diff --stat
```

Sau apply:

```sh
git status --short
git diff --stat
git worktree list
npm run lint --silent
npm test --silent || npm test
npm run typecheck --silent
git diff --check
```

Sau cleanup, invoke `/check-hardcode`. Trước mọi push/commit request, invoke `/audit-git-leak`.

Nếu scope chỉ markdown/config và repo không có test phù hợp, dùng verify tối thiểu:

```sh
git diff --check
```

Nếu cleanup chạm code runtime, phải chạy test/lint/typecheck phù hợp theo package hiện có. Behavior change cần ít nhất 1 happy-path test + 1 edge/error-path test. Không thêm test runner mới.

Nếu user yêu cầu push sau cleanup, trước push phải chạy sensitive scan/gitleaks theo command/project rule hiện có. Không push thô nếu slash command `/git-push-safety` phù hợp hơn.

## Output format

Dry-run output:

```text
CLEANUP DRY-RUN
Branch: <branch>
Scope: <scope>
Repo status: <clean|dirty summary>

Candidates:
1. [category] <path/branch> — <reason> — risk: <low|medium|high>

Need confirmation:
- <action list>

Skipped:
- <path/category> — <reason>

Suggested next step:
- Reply "apply all", "apply 1,3,5", or "stop".
```

Apply output:

```text
CLEANUP APPLY RESULT
Applied:
- [category] <path/branch> — <command/action>

Skipped:
- <path/branch> — <reason>

Verification:
- <command>: PASS/FAIL <summary>

Diff summary:
<git diff --stat>

Remaining risk / TODO:
- <item or none>
```
