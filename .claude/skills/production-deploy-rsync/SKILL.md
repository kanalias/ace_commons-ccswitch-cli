---
name: production-deploy-rsync
description: "Deploy prod bằng rsync cho host KHÔNG có git checkout: đẩy code local lên host, restart đúng process PM2 hoặc service Compose đã khai báo, verify, báo cáo. Dữ kiện từng target nằm ở .claude/deploy-targets/<target>.md (project sở hữu). Dùng /production-deploy-rsync <target> hoặc khi nói \"deploy rsync\"."
user-invocable: true
disable-model-invocation: true
---
> **Confirmation gate:** Gọi lệnh rõ ràng không phải là xác nhận. Trước bất kỳ hành động phá huỷ, thay đổi production, hoặc publish ra remote nào, liệt kê rõ target, scope, và tác động; hỏi user xác nhận rõ ràng trong conversation này và chờ. Giữ nguyên mọi xác nhận chặt hơn theo từng workflow bên dưới.


# /production-deploy-rsync — Deploy production bằng rsync

Dùng khi host đích **không có git checkout** (không `git pull` được): code đi từ máy local lên host
qua `rsync`, rồi restart ĐÚNG process/service đã khai báo. Host thường chạy nhiều app — chỉ đụng app của target.

Cú pháp: `/production-deploy-rsync <target>`. Mọi dữ kiện riêng của target (host, path, process, exclude...)
KHÔNG nằm trong skill này — đọc từ `.claude/deploy-targets/<target>.md`, file do **project sở hữu**
(harness không cài, không ghi đè). Skill có sẵn mẫu file ở mục "Mẫu target file".

> ⛔ **QUY TẮC CỨNG:**
> - KHÔNG BAO GIỜ `pm2 restart all`, `pm2 delete` (kể cả `delete all`), `pm2 kill`. Chỉ restart process có tên trong target file.
> - KHÔNG ghi đè `.env`/secret/runtime state/browser profile trên host. KHÔNG đọc hoặc copy `.env`/audit log từ host về.
> - Chưa liệt kê đủ đường dẫn runtime vào exclude → KHÔNG dùng `--delete` (xem bước 4).
> - SSH báo `Permission denied` / `Repository not found` → STOP, báo user. KHÔNG chuyển sang HTTPS + token.
> - In secret/giá trị env: cấm. Chỉ in tên biến + `ok`/`MISSING`.

## Các bước

**Song song (xem [[orchestrator]] rule 7):** bước 1 (local) ‖ 2 (host, read-only) chạy chung 1 message nhiều
tool-call TRƯỚC confirm. Tuần tự bắt buộc: 0 → (1 ‖ 2) → 3 (chờ user) → 4 → 5 → 6 → 7 → 8.

0. **Project guard + load target.**
   - Project slug kỳ vọng `ccswitch-cli-claude`; remote identity kỳ vọng `github.com/kanalias/ace_commons-ccswitch-cli`.
     Tính `basename "$(git rev-parse --show-toplevel)"` (lowercase, non-alnum → `-`) phải khớp slug; sanitize URL remote chính
     về `host/owner/repo` lowercase (bỏ userinfo, `.git`), KHÔNG in URL gốc, phải khớp chính xác. Lệch, `github.com/kanalias/ace_commons-ccswitch-cli`
     còn dạng placeholder (`<...>`), hoặc không parse được → STOP, không có override.
   - `$ARGUMENTS` rỗng → STOP, liệt kê file có trong `.claude/deploy-targets/` rồi hỏi target.
   - Đọc `.claude/deploy-targets/<target>.md`. **Thiếu file hoặc còn placeholder `<...>` ở field bắt buộc** → STOP,
     in mẫu ở mục "Mẫu target file" để user điền (không tự đoán giá trị, không tự tạo file với giá trị bịa).
   - `supervisor` phải là `pm2` hoặc `compose`; giá trị khác → STOP.

1. **Local preflight.**
   - `git status --short`: dirty → liệt kê (file dirty VẪN được rsync vì rsync gửi working tree, không phải commit — nói rõ cho user).
   - Chạy test: `lệnh test của project (chưa cấu hình — suy ra từ README/CI, hoặc hỏi trước khi giả định)`. Đỏ → STOP.
   - Xác nhận `local source dir` tồn tại; nếu là worktree mới tạo, cảnh báo: `rsync --delete` từ worktree sạch có thể xoá
     `node_modules`/build output đã có trên host (worktree chưa cài deps) — dependency phải nằm trong exclude hoặc cài sẵn trước.

2. **Host preflight (read-only).**
   - SSH vào `ssh host alias`; lỗi `Permission denied` / `Repository not found` → STOP (xem quy tắc cứng).
   - SSH non-login KHÔNG nạp PATH của shell: mọi lệnh `pm2`/`node`/`docker` qua SSH phải set PATH tường minh
     (field `ssh PATH prefix` trong target file), vd `ssh <host> 'export PATH=<dirs>:$PATH; pm2 ls'`.
   - Với mỗi tên trong `required env var NAMES`: kiểm tồn tại trong `.env` của host bằng `grep -q '^NAME=' <file>`,
     in CHỈ `NAME ok` hoặc `NAME MISSING`. KHÔNG `cat`, KHÔNG in value.
   - Phát hiện biến còn là placeholder/localhost (value rỗng, bắt đầu `<`, chứa `localhost`/`127.0.0.1`/`changeme`) bằng
     `grep -qE` trên file host, in CHỈ `NAME suspicious` — không in value.
   - `supervisor: pm2` → `pm2 ls` lấy trạng thái process đích + app khác (baseline để so sau). `compose` → `docker compose ps`.
   - Có `MISSING`/`suspicious` → cảnh báo lớn, đưa lệnh thêm biến (theo [[general]] mục thiếu quyền ghi) rồi hỏi user có tiếp tục.

3. **Confirm (prod — dừng chờ user OK trừ khi đã pre-authorize rõ trong prompt).** In ra:
   - Commit sẽ ship, mỗi dòng `<sha> <type>: <summary>` (`git log --oneline` của range chưa lên host; không biết range → 10 commit cuối + nói rõ).
   - File dirty (nếu có) — sẽ ship cùng.
   - Đường dẫn sẽ ship: output `rsync -n` (dry-run, cùng cờ như bước 4) rút gọn — nhất là danh sách `deleting ...` nếu có `--delete`.
   - Tác động: process/service sẽ restart, downtime dự kiến, cron app có chạy ngay không.
   - Loại thay đổi: code/runtime · config · docs · mix.
   Chờ user OK rõ ràng.

4. **Rsync.**
   - Cờ gốc: `rsync -az` + toàn bộ `--exclude` trong target file. Có `--delete` khi và chỉ khi target file ghi `rsync --delete: yes`.
   - **Điều kiện cho `--delete`:** MỌI đường dẫn gitignored/runtime (build output như `dist/`, `data/`, `logs/`, state file,
     browser profile, evidence/cache, file credential sinh runtime) PHẢI có trong exclude list. Đối chiếu `.gitignore` với exclude trước khi chạy;
     thiếu → STOP, đề xuất bổ sung (đã từng mất sạch build output vì thiếu một exclude).
   - Mặc định luôn exclude: `.git/`, `.claude/`, `.env*`, `.DS_Store`, cùng mọi mục trong `never-overwrite paths`.
   - `rsync -n` đã chạy ở bước 3; chạy thật chỉ sau confirm; so output với dry-run.
   - Rsync fail giữa chừng → STOP, KHÔNG restart (code host có thể lệch nửa vời); báo user.

5. **Pre-restart check.** Chạy `pre-restart check command` trong target file trên host (vd build/syntax/preflight).
   Fail → STOP, KHÔNG restart; process cũ vẫn chạy bản code đang nạp trong bộ nhớ. Field để trống → bỏ qua nhưng ghi vào báo cáo.

6. **Restart CHỈ process đã đặt tên.**
   - `pm2`: chạy đúng `restart command` trong target file, luôn kèm `--update-env` (pm2 cache env, không có cờ này thì `.env` mới không được nạp)
     và chỉ trỏ tên process của target (`--only <names>` hoặc `pm2 restart <name>`). Rồi `pm2 save` nếu target file yêu cầu.
     - Process đang `stopped` mà target file không liệt kê → KHÔNG start.
     - `pm2 startOrRestart` trên app **cron** (`cron_restart`) chạy app NGAY lập tức, không đợi lịch — chỉ dùng khi user chủ đích; ngược lại ưu tiên `restart`.
     - Mọi lệnh có PATH prefix như bước 2.
   - `compose`: `docker compose up -d --build <service>` chỉ cho service có tên; KHÔNG `down`, `down -v`, `docker volume rm`.
   - **Chạy đúng một nơi:** app có singleton (crawler, poller, bot token...) KHÔNG được chạy đồng thời ở 2 nơi. Cutover từ local/host cũ sang host này →
     dừng nơi cũ TRƯỚC khi start nơi mới; xác nhận nơi cũ đã stop. Rollback cũng phải kết thúc với đúng một nơi chạy.

7. **Verify.**
   - Chạy `verify command` trong target file; hoặc `pm2 ls` + `pm2 logs <name> --nostream --lines 20` và khớp `log pattern`. KHÔNG in file log chứa audit/secret ra chat — lọc theo pattern.
   - **Crash loop** (restart count tăng liên tục, status `errored`/`waiting restart`, log lặp lỗi khởi động) → `pm2 stop <name>` NGAY (chỉ process đó), rồi mới chẩn đoán; không để loop chạy tiếp.
   - Diff `pm2 ls`/`docker compose ps` với baseline bước 2: app KHÁC phải không đổi (uptime/restart count). Có thay đổi ngoài ý muốn → cảnh báo lớn.
   - Verify fail → làm theo `rollback note` trong target file (khôi phục bản trước, vẫn đảm bảo chỉ một nơi chạy), rồi verify lại. Không có rollback note → STOP và báo user, không tự bịa.

8. **Báo cáo.** Target · commit đã ship (`<sha> <type>: <summary>`) · số file rsync/xoá · kết quả env check (chỉ tên + ok/MISSING) · pre-restart check ·
   process đã restart + trạng thái trước/sau · app khác có đổi không · verify · rollback (nếu có).

## Mẫu target file

Khi file thiếu hoặc chưa điền, in mẫu này (không tự điền). Lưu tại `.claude/deploy-targets/<target>.md`; project quản lý, harness không đụng.

```markdown
# Deploy target: <target>

- ssh host alias: <alias khai báo trong ~/.ssh/config — không ghi host/IP/port ở đây>
- ssh PATH prefix: <các thư mục chứa pm2/node/docker trên host, ngăn bằng ':'>
- remote app dir: <đường dẫn app trên host>
- local source dir: <đường dẫn nguồn, tương đối repo, vd ./>
- supervisor: <pm2 | compose>
- process name(s): <tên process pm2 hoặc service compose, ngăn bằng dấu phẩy>
- rsync --delete: <yes | no>
- exclude list:
  - <pattern, mỗi dòng một cái; gồm build output, state, profile, evidence, log...>
- required env var NAMES (chỉ tên, KHÔNG value):
  - <TÊN_BIẾN>
- never-overwrite paths (trên host):
  - <đường dẫn: .env, file cấu hình riêng host, state runtime, browser profile...>
- pre-restart check command: <lệnh chạy trên host, exit 0 = ok; để trống nếu không có>
- restart command: <lệnh đầy đủ, vd pm2 restart <config> --only <names> --update-env>
- verify command / log pattern: <lệnh + chuỗi/regex log cho thấy khởi động thành công>
- rollback note: <cách khôi phục bản trước, và cách đảm bảo chỉ một nơi chạy>
```

Field bắt buộc (không được để placeholder): ssh host alias, remote app dir, local source dir, supervisor,
process name(s), rsync --delete, restart command, verify command / log pattern. Field còn lại có thể để trống nhưng phải ghi rõ "không áp dụng".

## Guardrails

- Permission layer của môi trường vẫn gate các Bash call SSH/rsync tại runtime — bị deny hoặc host không reachable → in lệnh để user tự chạy, không ép.
- Skill này KHÔNG push git, KHÔNG invoke `/git-push-safety`; gate test/scan là bước độc lập của project.
- KHÔNG đụng process/service nào ngoài danh sách đã đặt tên; KHÔNG sửa target file trong lúc deploy.
- Target file sai/lệch thực tế → dừng và báo user sửa file, không tự sửa rồi chạy tiếp.
