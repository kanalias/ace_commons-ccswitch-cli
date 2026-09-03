---
name: git-workflow
description: Branch strategy (working branch + protected branches) + working-branch discipline, protected-branch deploy confirm, worktree lifecycle, cleanup-sau-merge. P0 guardrail cho mọi git op có tính destructive/outward-facing.
status: live
updated: 2026-08-04
metadata:
  type: reference
---

# Git Workflow

Bổ sung [[git-conventions]] (org default + commit format). Phần này = branching + merge/deploy guardrail.

## Branching strategy

- **@@BRANCH@@** — working branch, phát triển hàng ngày, sửa trực tiếp.
- **Protected branches** (vd `stable`, `prod`, `release` — theo thực tế project) — CHỈ merge từ `@@BRANCH@@`, KHÔNG push trực tiếp.

## Working branch (QUAN TRỌNG)

- **Sửa trực tiếp trên `@@BRANCH@@`.** KHÔNG sửa trên protected branch/`feat/*`/`fix/*` trừ khi user yêu cầu rõ. **Chỉ áp khi 1 session duy nhất chạm repo** — đa session xem block dưới.
- Nhận task mới → check `git branch --show-current` → khác `@@BRANCH@@` thì checkout `@@BRANCH@@` (trừ khi user chỉ định).
- Merge về protected branch chỉ khi user xác nhận. Sau merge → cleanup ở dưới.

## Đa session song song (QUAN TRỌNG)

Nhiều session mở cùng repo dir = chung working tree + chung `HEAD`/index → đè uncommitted lẫn nhau, race `git add`/`commit`, cả 2 đều thấy `@@BRANCH@@` nên không biết đối phương tồn tại.

- **≥2 session cùng repo → mỗi session PHẢI worktree riêng** `.claude/worktrees/<slug>` + branch `feat/<slug>` (hoặc `fix/`, `chore/`...). KHÔNG session nào sửa trực tiếp `@@BRANCH@@`.
- Áp **kể cả khi task disjoint** — chung working tree vẫn race index/HEAD. Nghi ngờ overlap → coi là overlap, tách.
- Ngoại lệ duy nhất: user nói rõ chấp nhận rủi ro chung `@@BRANCH@@`.
- Thấy uncommitted changes lạ / `@@BRANCH@@` nhảy commit không do mình → dừng, cảnh báo user có session khác.

## Protected branch deploy (nếu project có)

- **KHÔNG push thẳng protected branch.** Mọi commit trên đó PHẢI từ `git merge @@BRANCH@@`.
- **KHÔNG tự động merge/push protected branch.** Chỉ khi user chỉ thị rõ ("deploy", "đẩy lên prod"...).
- Trước push protected branch, BẮT BUỘC dừng hỏi user **confirm** kèm:
  - Số commit + tóm tắt 1 dòng mỗi commit (`git log origin/<protected>..<protected> --oneline`)
  - Loại thay đổi: code/runtime / docs / config / mix
  - Tác động: cần restart service? có downtime?
- **Worktree bắt buộc** khi merge `@@BRANCH@@` → protected branch: dùng `.claude/worktrees/<protected>-deploy/` để giữ working tree ở `@@BRANCH@@`. Push xong → `git worktree remove`.

## Worktree (task song song)

- Đặt tại `.claude/worktrees/<slug>` (gitignored, không xoá thủ công) — path hardcode trong `EnterWorktree`. Grep/find loại trừ dir này.
- Tự tạo khi task độc lập / user nhiều việc dở / user nói rõ:
  - Branch mới: `git worktree add .claude/worktrees/<slug> -b feat/<slug>` (từ `@@BRANCH@@`).
  - Branch có sẵn (deploy): `git worktree add .claude/worktrees/<slug> <existing-branch>` (KHÔNG `-b`).
  - Báo user path + lệnh `cd`.
- Naming: `feat/`, `fix/`, `chore/`, `refactor/`, `hotfix/` + slug kebab-case. Worktree cùng task đã có → dùng lại.
- Delegate wrapper worktree (`.claude/worktrees/delegate-*/`) do wrapper tự quản — xem [[delegate-llm]].
- **Nhiều subagent song song → mỗi task 1 worktree riêng.** KHÔNG 2+ subagent cùng edit chung file/worktree. Nghi ngờ → tách riêng.

### Dọn orphan dir + junk

`git worktree prune` CHỈ dọn worktree registered stale — không đụng dir rác. Trước kết session hoặc khi dir bẩn:

```bash
cd .claude/worktrees && git worktree list  # worktree HỢP LỆ
for d in */; do [ -e "$d/.git" ] || echo "ORPHAN non-worktree: $d"; done
```

- Orphan rỗng → `rmdir` (chỉ `rmdir`, không `rm -rf`); không rỗng → dừng, báo user.
- `.DS_Store` → xoá; `*.bundle` giá trị → move ra `../` (KHÔNG xoá).

## Trước khi merge — check fix ledger

Trước `git merge` vào `@@BRANCH@@`/protected branch — chạy skill `fix-ledger` (CHECK) nếu project có `.claude/fix-ledger.md` (tránh merge branch stale đè bugfix). Sau fix/feature có rủi ro bị đè → `fix-ledger` (RECORD).

## Cleanup sau merge (BẮT BUỘC, in-session)

Branch tạm (`feat/`, `fix/`, `hotfix/`, `chore/`, `refactor/`) sau merge vào branch chính trong CÙNG SESSION → cleanup ngay, KHÔNG để branch rác qua session.

**Trigger**: ngay sau `git merge feat/<slug>` thành công — 3 bước theo thứ tự:

1. **Worktree** — `git worktree remove <wt-path>`. Stale → `git worktree prune`.
2. **Local branch** — `git branch -d feat/<slug>` (safe delete). Git từ chối (unmerged) → dừng, báo user. KHÔNG `-D` force.
3. **Remote branch** — `git push origin --delete feat/<slug>` (best-effort). Lỗi → log warning, không fail flow. CHỈ trên `origin`.

**Whitelist cleanup**: `feat/`, `fix/`, `hotfix/`, `chore/`, `refactor/`.
**Protected (HARD BLOCK)**: `@@BRANCH@@` + mọi protected/release branch khác.

**Slash command**: [/git-push-safety](../commands/git-push-safety.md) gom push + smoke test + gitleaks + sensitive scan — tránh `git push` thô.

**Confirm trước xoá**: BẮT BUỘC liệt kê candidates + hỏi `[a]ll / [s]elect / [n]one` trước delete. Destructive → không auto-execute không xác nhận.

**Không cleanup khi**:
- User explicit "giữ branch <slug>" / "keep ...".
- Branch chưa merge thật (`git branch --merged <current>`).
- Branch ngoài 5 prefix whitelist (`release/`, `experiment/` → user tự quyết).
- Commit cuối < 24h.

## Env files — KHÔNG push remote

`.env*` (đã gitignored) chỉ giữ **LOCAL**. KHÔNG push env/secret lên bất kỳ remote nào (kể cả private repo). Xem [[secrets-no-printout]], [[vault-no-mcp]].
