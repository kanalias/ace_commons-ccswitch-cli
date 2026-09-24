---
name: git-cleanup-branch
description: "Audit branch đã merge và worktree stale, chỉ xoá những gì user xác nhận. Dùng khi \"clean up merged branches\", \"prune worktrees\" hoặc /git-cleanup-branch."
user-invocable: true
disable-model-invocation: true
---
> **Confirmation gate:** Gọi lệnh rõ ràng không phải là xác nhận. Trước bất kỳ hành động phá huỷ, thay đổi production, hoặc publish ra remote nào, liệt kê rõ target, scope, và tác động; hỏi user xác nhận rõ ràng trong conversation này và chờ. Giữ nguyên mọi xác nhận chặt hơn theo từng workflow bên dưới.


# git-cleanup-branch — audit + confirm-delete branch đã merge và worktree stale

## 1. Xác định remote chính + default branch

Resolve remote chính (`$R`):

```sh
b=$(git branch --show-current)
R=$(git config --get "branch.$b.remote" 2>/dev/null || true)
[ "$R" = "." ] && R=
[ -z "$R" ] && git remote | grep -qx origin && R=origin
[ -z "$R" ] && [ "$(git remote | wc -l | tr -d ' ')" = 1 ] && R=$(git remote)
[ -z "$R" ] && echo "STOP: không xác định được remote chính — hỏi user" >&2
```

Chạy `git symbolic-ref refs/remotes/$R/HEAD` và lấy basename (vd
`main`). Nếu lệnh fail (không có remote tracking ref), hỏi user branch
nào là default — không đoán giữa `main`/`master`.

## 2. Liệt kê merge candidate

Chạy `git branch --merged <default>` để liệt kê branch đã merge vào nó.

Với mỗi candidate, check:

- **PROTECTED (HARD BLOCK, không bao giờ đề xuất xoá):** `main`, `master`,
  `stable`, `prod`, `develop`, `backup`, và branch đang checkout hiện tại.
  Loại hoàn toàn khỏi candidate list.
- **Prefix hợp lệ:** `feat/`, `fix/`, `chore/`, `refactor/`, `hotfix/`.
  Branch ngoài các prefix này đã merge nhưng không tự động đề xuất — liệt kê
  riêng dạng "merged, outside cleanup whitelist" và để user quyết.
- **Age guard:** bỏ qua (liệt kê là "too recent") branch nào có commit cuối
  dưới 24h — check bằng `git log -1 --format=%cr <branch>`.
- Branch nào thực sự chưa merge (`git branch --merged` đã filter sẵn,
  nhưng double check ở setup detached-HEAD mơ hồ) giữ ngoài deletable list.

## 3. Liệt kê worktree stale

Chạy `git worktree list`. Đánh dấu entry nào trỏ tới thư mục không còn
tồn tại hoặc branch đã bị xoá. Đề xuất `git worktree prune` cho các case này —
lệnh này chỉ xoá registration stale, không đụng thư mục có nội dung thật, nên
rủi ro thấp, nhưng vẫn hỏi trước khi chạy.

## 4. Trình bày candidate và xác nhận

Hiện 3 nhóm: (a) branch prefix hợp lệ an toàn để xoá, (b) branch đã merge
ngoài whitelist (chỉ thông tin, không đề xuất xoá), (c) worktree entry stale.
Hỏi user `[a]ll / [s]elect / [n]one` trước khi xoá bất kỳ gì trong nhóm (a).
Không bao giờ xoá mà chưa có xác nhận này, và không bao giờ đụng branch
nhóm (b).

## 5. Xoá branch đã xác nhận

Với mỗi branch đã xác nhận: `git branch -d <branch>` (chỉ safe delete). Nếu
git từ chối vì unmerged, DỪNG, báo branch đó, và KHÔNG force bằng
`-D` — quyết định đó thuộc về user, không phải command này.

Sau đó thử cleanup remote, best-effort, chỉ remote chính (`$R`):
`git push $R --delete <branch>`. Nếu fail (branch đã mất, vấn đề
permission, v.v), log warning và tiếp tục — không fail toàn bộ run vì một
lần xoá remote lỗi.

## 6. Report

Liệt kê những gì đã xoá (local + remote), những gì bị skip và lý do (age,
unmerged, ngoài whitelist), và worktree nào đã prune.
