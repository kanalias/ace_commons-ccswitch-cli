---
name: private-branch-kane
description: Nhánh riêng tư `ace-skill` (nhóm skill bảo mật ace-*) CHỈ push lên remote `kane` = repo private kanalias/ccswitch-kane; KHÔNG bao giờ lên origin public. P0 mọi lệnh push.
status: live
updated: 2026-10-25
metadata:
  type: reference
---

# Nhánh riêng tư `ace-skill` → chỉ remote `kane`

Repo này có 2 remote với quyền đọc khác nhau:

| Remote | URL | Ai đọc được | Nhánh |
|---|---|---|---|
| `origin` | github.com `kanalias/ace_commons-ccswitch-cli` | **PUBLIC** + collaborator | `main`, `feat/*`, `fix/*`, `chore/*` |
| `kane` | github.com `kanalias/ccswitch-kane` | **chỉ kanalias** (private, 0 collaborator) | `ace-skill` |

Git không có quyền đọc theo nhánh → nội dung riêng tư PHẢI nằm ở repo private riêng. Nhánh `ace-skill` chứa nhóm skill bảo mật `ace-*` (`ace-security-scan`, `ace-notion-rbac`, `ace-ai-explain`, `ace-library`, `ace-gen-image`, và skill ace-* thêm sau).

## Luật (P0)

- `git push` nhánh `ace-skill` → **chỉ** `git push kane ace-skill` (qua `/git-push-safety`, prefix `GIT_PUSH_GATE_OK=1`). Nhánh đã cấu hình `branch.ace-skill.remote=kane` + `pushRemote=kane`; `git push` trần trên nhánh này cũng đi `kane`.
- KHÔNG `git push origin ace-skill`, KHÔNG `git push origin --all|--mirror|--tags` (kéo theo nhánh riêng), KHÔNG `git push origin ace-skill:<tên-khác>`.
- KHÔNG merge `ace-skill` vào `main` (main public). Chiều ngược `main` → `ace-skill` (merge/rebase lấy harness mới) thì được.
- Thêm nhánh riêng tư mới → thêm dòng vào `.claude/private-branches.txt` (format `<branch> <remote-name> <url-substring>`) + thêm pattern vào ruleset `block-private-branches` trên origin.
- Nhánh `ace-skill` KHÔNG được tạo worktree chung với session đang sửa `main` nếu nội dung riêng tư chưa commit (tránh `git add -A` nhầm vào main).

## Gate (3 lớp, không bypass)

1. **Ruleset GitHub `block-private-branches`** trên origin: chặn creation/update `refs/heads/ace-skill`, `refs/heads/kane`, `refs/heads/kane/**`, không bypass actor. Lớp cuối phía server.
2. **`.git/hooks/pre-push`** (template `harness/templates/git-hooks/pre-push`): đọc `.claude/private-branches.txt`, từ chối push ref riêng tư tới remote có URL không khớp. Chạy cả ngoài Claude Code. `GITLEAKS_SKIP=1` không tắt gate này.
3. **`.claude/hooks/pre-bash-gate.sh` bước 1.1**: chặn sớm lệnh `git push <remote≠kane> …ace-skill…` và `git push <remote≠kane> --all|--mirror|--tags` ngay trong Claude, kèm thông báo rõ.

Lỡ push nhầm nội dung riêng tư lên origin → coi là lộ: báo user ngay, không tự force-push xoá ([[secrets-no-printout]] mục secret đã lộ).

Liên quan: [[git-workflow]], [[git-conventions]].
