---
name: git-workflow
description: Branch strategy (working branch + protected branches) + working-branch discipline, protected-branch deploy confirm, worktree lifecycle, cleanup-sau-merge. P0 guardrail cho mọi git op có tính destructive/outward-facing.
status: live
updated: 2026-07-19
metadata:
  type: reference
---

# Git Workflow

Bổ sung [[git-conventions]] (org default + commit format). Phần này = branching + merge/deploy guardrail.

## Branching strategy

- **@@BRANCH@@** — working branch, phát triển hàng ngày, sửa trực tiếp.
- **Protected branches** (vd `stable`, `prod`, `release` — điền theo thực tế project) — CHỈ merge từ `@@BRANCH@@`, KHÔNG push trực tiếp.

## Working branch (QUAN TRỌNG)

- **Sửa trực tiếp trên `@@BRANCH@@`.** KHÔNG sửa trên protected branch/`feat/*`/`fix/*` trừ khi user yêu cầu rõ.
- Nhận task mới → check `git branch --show-current` trước → khác `@@BRANCH@@` thì checkout `@@BRANCH@@` (trừ khi user chỉ định).
- Merge về protected branch chỉ khi user xác nhận. Sau merge → cleanup ở dưới.

## Protected branch deploy (nếu project có)

- **KHÔNG push thẳng protected branch.** Mọi commit trên đó PHẢI từ `git merge @@BRANCH@@`.
- **KHÔNG tự động merge `@@BRANCH@@` → protected branch hoặc push protected branch.** Chỉ khi user chỉ thị rõ ("deploy", "đẩy lên prod"...).
- Trước push protected branch, BẮT BUỘC dừng hỏi user **confirm** kèm:
  - Số commit sẽ đẩy + tóm tắt 1 dòng mỗi commit (`git log origin/<protected>..<protected> --oneline`)
  - Loại thay đổi: code/runtime / docs / config / mix
  - Tác động: cần restart service? có downtime?
- **Worktree bắt buộc** khi merge `@@BRANCH@@` → protected branch: dùng `.worktrees/<protected>-deploy/` để giữ working tree ở `@@BRANCH@@`. Push xong → `git worktree remove`.

## Worktree (task song song)

- Đặt **trong** project tại `.worktrees/<slug>` (đã gitignored, không xoá thủ công).
- Grep/find phải loại trừ `.worktrees/` tránh context pollution.
- Tự tạo khi task độc lập / user có nhiều việc dở / user nói rõ:
  1. Branch mới: `git worktree add .worktrees/<slug> -b feat/<slug>` (branch từ `@@BRANCH@@`).
     Branch có sẵn (vd deploy): `git worktree add .worktrees/<slug> <existing-branch>` (KHÔNG `-b`).
  2. Báo user path + lệnh `cd`.
- Naming: `feat/`, `fix/`, `chore/`, `refactor/`, `hotfix/` + slug kebab-case ngắn.
- Worktree đã tồn tại cho cùng task → dùng lại, không chồng.
- Delegate wrapper worktree (`.worktrees/delegate-*/`) do wrapper quản lý riêng — xem [[delegate-llm]].

### Dọn `.worktrees/` — orphan dir + junk

`git worktree prune` CHỈ dọn worktree registered stale — KHÔNG đụng dir rác không-phải-worktree (leftover parent delegate `.worktrees/delegate-*/`, `.DS_Store`, bundle backup lạc chỗ). Cleanup-sau-merge không cover các thứ này.

- Trước khi kết session / khi thấy `.worktrees/` bẩn, audit:
  ```bash
  cd .worktrees && git worktree list        # danh sách worktree HỢP LỆ
  for d in */; do [ -e "$d/.git" ] || echo "ORPHAN non-worktree: $d"; done
  ```
- Orphan dir rỗng (0B, không `.git`) → `rmdir <dir>` (chỉ xoá được nếu rỗng).
- File lạc chỗ: `.DS_Store` → xoá; `*.bundle` có giá trị → **move ra ngoài repo** (`../`), KHÔNG xoá.
- Chỉ `rmdir` (không `rm -rf`) cho orphan — dir không rỗng → dừng, báo user.

## Cleanup sau merge (BẮT BUỘC, in-session)

**Cốt lõi**: branch tạm (`feat/`, `fix/`, `hotfix/`, `chore/`, `refactor/`) sau khi merge vào branch chính (`@@BRANCH@@` hoặc protected branch) trong CÙNG SESSION phải cleanup ngay. KHÔNG để branch rác qua session.

**Trigger**: ngay sau `git merge feat/<slug>` thành công — 3 bước theo thứ tự:

1. **Worktree** — `git worktree remove <wt-path>`. Stale → `git worktree prune`.
2. **Local branch** — `git branch -d feat/<slug>` (safe delete). Git từ chối (unmerged) → dừng, báo user. KHÔNG `-D` force.
3. **Remote branch** — `git push origin --delete feat/<slug>` (best-effort). Lỗi → log warning, không fail flow. CHỈ trên `origin`.

**Whitelist cleanup**: `feat/`, `fix/`, `hotfix/`, `chore/`, `refactor/`.
**Protected (HARD BLOCK)**: `@@BRANCH@@` + mọi protected/release branch khác của project (vd `stable`, `prod`, `release` — điền theo thực tế repo).

**Slash command**: [/push-to-git](../commands/push-to-git.md) để gom push + smoke test + gitleaks + sensitive scan. Tránh `git push` thô (dễ quên cleanup).

**Confirm trước xoá**: BẮT BUỘC liệt kê candidates + hỏi `[a]ll / [s]elect / [n]one` trước delete. Destructive → không auto-execute không xác nhận.

**Không cleanup khi**:
- User explicit "giữ branch <slug>" / "keep ...".
- Branch chưa merge thật (`git branch --merged <current>`).
- Branch ngoài 5 prefix whitelist (`release/`, `experiment/` → user tự quyết).
- Commit cuối < 24h.

## Env files — KHÔNG push remote

`.env*` (đã gitignored) chỉ giữ **LOCAL**. KHÔNG push env/secret lên bất kỳ remote nào (kể cả private repo). Xem [[secrets-no-printout]], [[vault-no-mcp]].
