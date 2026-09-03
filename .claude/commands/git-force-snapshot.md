---
name: git-force-snapshot
description: Squash toàn bộ git history thành 1 commit duy nhất để cắt đứt vĩnh viễn secret bị lộ khỏi history. Destructive và irreversible sau khi force-push — mọi collaborator phải re-clone. Chỉ dùng khi user nói rõ "force snapshot", "squash history", "xoá lịch sử git", "reset history vì leak", hoặc chạy /git-force-snapshot.
user-invocable: true
---

# git-force-snapshot — squash toàn bộ history thành 1 commit (destructive)

Đây là nuclear option: nó bỏ hết mọi commit và thay toàn bộ history
repo bằng 1 snapshot duy nhất của working tree hiện tại. Chỉ dùng khi
leak rải rác qua nhiều commit cũ và rewrite có mục tiêu
(`git filter-repo`/BFG chỉ trên path bị leak) không đủ. Không bao giờ chạy
lệnh này mà chưa được user yêu cầu rõ ràng trong conversation này.

## 1. Xác nhận ý định

Hỏi user xác nhận, và nhắc phương án nhẹ hơn: nếu leak chỉ giới hạn
1 file/pattern, `git filter-repo --path <file> --invert-paths`
(hoặc BFG) xoá đúng phần đó khỏi history và ít gây gián đoạn hơn nhiều.
Chỉ tiến hành full squash khi user vẫn muốn sau khi nghe điều đó.

Cũng xác nhận: branch nào, và họ đã rotate/revoke secret bị lộ chưa.
Squash history không undo được việc đã bị scrape, cache, hoặc fork bởi
GitHub hoặc bất kỳ ai đã pull — rotation mới là fix thật sự; command này
chỉ ngăn leak hiển thị công khai từ giờ trở đi.

## 2. Pre-flight

- `git status` — phải clean. Có thay đổi chưa commit → hỏi user commit
  hoặc stash (`git stash push -u`) trước; không tự ý discard bất cứ gì.
- Từ chối trên protected branch (xem rule git-workflow của project: `main`,
  `stable`, `prod`, hoặc branch nào repo đánh dấu protected) trừ khi user
  chỉ định rõ branch đó làm target. Squash history của protected branch
  là blast radius lớn hơn nhiều — flag rõ điều này trước khi tiếp tục.
- Ghi lại tên branch hiện tại và remote (`git remote -v`) cho bước sau.

## 3. Backup trước khi rewrite

Safety net bắt buộc — tạo trước khi đụng vào bất cứ gì:

```bash
git branch backup/pre-force-snapshot-$(date +%Y%m%d%H%M%S)
```

Báo user backup branch này tồn tại local và sẽ không push; đây là
đường rollback nếu squash có vấn đề.

## 4. Squash qua orphan branch

```bash
git checkout --orphan _force-snapshot-tmp
git add -A
git commit -m "<message — hỏi user, default: 'chore: squash history (force-snapshot)'>"
git branch -D <original-branch>
git branch -m <original-branch>
```

## 5. Re-check commit mới cho leak

Squash xoá *history* nhưng secret bị lộ có thể vẫn còn nằm trong
working tree hiện tại. Chạy skill audit-git-leak (gitleaks + sensitive-content
scan) trên state 1-commit mới này trước khi push bất cứ gì. Bất kỳ finding
nào → DỪNG, fix trong working tree, amend snapshot commit, scan lại.

## 6. Force-push — cần xác nhận rõ ràng

Bước này rewrite remote history cho tất cả mọi người. Nói rõ với user,
bằng ngôn ngữ đơn giản, trước khi chạy:

- Remote + branch chính xác sẽ bị force-push.
- Rằng local clone của mọi collaborator sẽ diverge và cần `git fetch` +
  reset (hoặc clone lại) sau đó.
- Rằng commit cũ trở nên unreachable từ default ref nhưng có thể vẫn
  tồn tại trong internal storage/cache của GitHub một thời gian — rotation
  của secret bị lộ vẫn cần thiết bất kể push này.

Chỉ sau khi user xác nhận rõ ràng (không phải approval trước đó
đã cho — hỏi lại riêng cho lần push cụ thể này):

```bash
git push --force origin <branch>
```

## 7. Report

Tóm tắt: tên backup branch (giữ lại tạm thời), commit đã squash tới,
scan leak ở bước 5 có sạch không, và nhắc user (a) báo collaborator
re-clone hoặc hard-reset, (b) rotate credential bị lộ ban đầu nếu chưa
làm, (c) xoá local backup branch sau khi họ đã xác nhận remote state đúng.
