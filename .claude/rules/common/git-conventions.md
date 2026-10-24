---
name: git-conventions
description: Commit format + cleanup branch/worktree sau merge + auto-push main/working branch qua git-push-safety + merge ≠ deploy + đổi tên remote → hỏi đổi folder local
status: live
updated: 2026-10-24
metadata:
  type: reference
---

# Git Conventions (cross-project)

## Commit format

```text
feat|fix|refactor|chore|docs: <mô tả>
```

## GitHub org mặc định

Repo mới / push GitHub → tạo dưới org `acegalaxy-co`, KHÔNG dưới username cá nhân (trừ khi user nói rõ). Lib: `acegalaxy-co/lib-<name>`.

## Branch cleanup sau merge (BẮT BUỘC)

Xong tính năng → merge vào `main` → cleanup worktree + branch NGAY trong cùng session, KHÔNG để rác qua session. Quy trình đầy đủ (3 bước, whitelist prefix, confirm trước xoá, ngoại lệ): [[git-workflow]] mục "Cleanup sau merge".

## Auto-push sau merge + cleanup (BẮT BUỘC, mọi project)

Merge + cleanup xong (kể cả branch merge vào là `main` hay `main`) → **tự push luôn**, không hỏi lại:

1. **Đồng bộ branch chính (`main`, theo `origin/HEAD`) và branch dev `main` về cùng SHA, chỉ fast-forward**: merge vào `main` → `git fetch . main:main`; merge vào `main` → `git fetch . main:main` (branch đang checkout → `git merge --ff-only <kia>`). `main` = `main` → chỉ 1 branch. Không ff được (diverged) → DỪNG, báo user, KHÔNG tự merge/rebase.
2. **Chạy quy trình `/git-push-safety`** (đọc `.claude/skills/git-push-safety/SKILL.md`, làm đúng các bước): tests + gitleaks + sensitive scan. Bước nào fail → DỪNG, không push.
3. **Push mọi branch đã nhận merge/ff**: `GIT_PUSH_GATE_OK=1 git push <remote> main main`. Rule này = xác nhận sẵn của user cho bước Push của skill trong luồng này; xong in branch + range commit đã push. KHÔNG force-push. Protected branch deploy (`stable`/`prod`/`release`...) KHÔNG nằm trong luồng này — theo mục dưới.

Không áp khi: user nói "chưa push"/"giữ local", hoặc session khác đang dở trên branch đích ([[git-workflow]] mục Đa session).

## Đổi tên project / remote → hỏi đổi luôn folder local

Đổi tên repo trên remote (rename project, đổi group/path, đổi URL `origin`) → sau khi xong phần remote, **HỎI user** có đổi luôn tên folder local của repo trên máy này cho khớp không. KHÔNG tự đổi (đổi path làm vỡ nhiều thứ ngoài repo).

Câu hỏi phải kèm danh sách chỗ bị ảnh hưởng (grep path cũ trước khi hỏi, chỉ liệt kê chỗ thật sự có):

- Memory Claude Code `~/.claude/projects/<path-encoded>/` — khoá theo path, đổi folder = session mới không thấy memory cũ → phải move dir sang key mới.
- `*.code-workspace`, `additionalDirectories`, path tuyệt đối trong `.claude/settings*.json`, launchd plist / cron / pm2, skill, docs, script.
- Worktree đang mở (`git worktree list`) → `git worktree repair` sau khi đổi.
- Session/terminal/editor đang mở ở path cũ → phải mở lại.

User đồng ý → đổi folder + sửa hết chỗ trên trong cùng lượt (theo "Đổi tên → sweep 1 lần" ở [[general]]), báo danh sách đã sửa. Cập nhật `git remote set-url` nếu chưa làm.

## Merge ≠ deploy

- Merge (+ auto-push ở trên) và deploy là 2 bước. Deploy staging/prod (và push protected branch deploy) cần user xác nhận riêng — "Merge đi" KHÔNG bao gồm deploy.
- **Ngoại lệ:** prompt hiện tại cho phép rõ deploy (vd "làm xong thì merge push và deploy") → deploy luôn không hỏi lại, vẫn in danh sách commit/tác động theo mẫu confirm deploy ([[git-workflow]]) trước khi chạy. Chỉ áp cho task trong prompt đó, KHÔNG kéo sang task sau.
- Deploy prod xong + chạy ổn → tag `stable-<semver>` tại đúng SHA đã deploy, và cập nhật config service trên Notion (nếu project có Notion config).

Liên quan: [[delegate-llm]] (delegate infra), [[orchestrator]] (routing).
