---
name: git-commit
description: Stage và commit thay đổi vào local git only, không push. Thêm `--conventional` để soạn message theo Conventional Commit (type prefix). Dùng khi user nói "commit", "commit local", "commit this", "gen commit message", "write conventional commit", hoặc chạy /commit, /commit --conventional.
user-invocable: true
---

# commit — local git commit, không push

1. `git status` + `git diff` (staged và unstaged) + `git log --oneline -5` để xem thay đổi gì và khớp style commit hiện có.
2. Nếu chưa có gì staged: stage file liên quan theo tên (không bao giờ `-A`/`.` mù quáng — check secrets/junk trước).
3. Soạn commit message:
   - **Mặc định**: message ngắn khớp style hiện có của repo (xem log gần đây). Không viết body dài trừ khi thay đổi cần.
   - **`--conventional`**: prefix `type: mô tả` (imperative, ≤72 ký tự, không dấu chấm cuối). Chọn type khớp nhất thay đổi chủ đạo:
     - **feat** — thêm khả năng mới hoặc hành vi user-facing
     - **fix** — sửa bug hoặc hành vi sai
     - **refactor** — cấu trúc lại code, không đổi behavior
     - **chore** — bảo trì (deps, config, tooling), không đổi source/behavior
     - **docs** — chỉ documentation (`*.md`, comment, README)
     - **test** — chỉ file test, không đổi production code
     - **style** — chỉ format/whitespace/lint, không đổi logic
     - **perf** — cải thiện performance, cùng behavior
     - **build** — thay đổi build system hoặc dependency manifest
     - **ci** — thay đổi config CI/CD pipeline
     - Diff trải nhiều type → chọn type của thay đổi chính, không ghép nhiều prefix.
     - Chỉ thêm body nếu thêm thông tin thật (bullet `-` giải thích *tại sao*, không diễn lại diff). Không thêm trailer mà repo chưa dùng (vd `Signed-off-by`, `Co-Authored-By`) trừ khi history gần đây cho thấy convention đó.
4. Hiện message đã soạn cho user, xác nhận trước khi chạy `git commit -m "..."`. Không bao giờ commit mà chưa có xác nhận, không tự sửa message thành thứ user chưa duyệt.
5. Không push.
6. Report kết quả 1 dòng: commit hash + subject. Không giải thích thêm.

Không bao giờ force, amend, hoặc skip hook. Nếu commit fail (hook reject), fix root cause rồi retry — không `--no-verify`.
