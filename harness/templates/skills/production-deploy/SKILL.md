---
name: production-deploy
description: "Deploy prod tại chỗ cho host nhiều service: pull + rebuild + up đúng service đích, verify, tự rollback khi healthcheck fail. Dùng khi \"deploy prod\" hoặc /production-deploy."
user-invocable: true
disable-model-invocation: true
---
> **Confirmation gate:** Gọi lệnh rõ ràng không phải là xác nhận. Trước bất kỳ hành động phá huỷ, thay đổi production, hoặc publish ra remote nào, liệt kê rõ target, scope, và tác động; hỏi user xác nhận rõ ràng trong conversation này và chờ. Giữ nguyên mọi xác nhận chặt hơn theo từng workflow bên dưới.


# /production-deploy — Deploy production tại chỗ an toàn

Deploy `@@DEPLOY_SERVICE@@` trên `@@DEPLOY_SSH_HOST@@` bằng cách pull + rebuild + `up` đúng MỘT
service đó tại chỗ. Host này chạy nhiều service — một service chết (image lỗi, healthcheck lỗi)
KHÔNG BAO GIỜ được kéo sập các service hàng xóm. Command này snapshot trạng thái trước, verify mọi service
(target + hàng xóm) sau, và tự động rollback service target khi healthcheck fail.

> ⛔ **QUY TẮC CỨNG — không bao giờ phá huỷ dữ liệu:**
> - Deploy luôn là pull + rebuild + `up` **tại chỗ**. KHÔNG BAO GIỜ `down -v`, `docker volume rm`,
>   `rm -rf`, `docker system prune --volumes`, hay dừng cả host.
> - **Service isolation** — chỉ đụng đúng `@@DEPLOY_SERVICE@@`. Các service/container khác trên host
>   KHÔNG được restart, recreate, hay mất volume.
> - Prune (nếu cần giải phóng disk) = CHỈ build-cache + dangling image. Không `-a`, không `--volumes`.

## Các bước

0. **Project guard — verify repo identity trước mọi hành động SSH/cloud/git production.**
   - Project slug kỳ vọng: `@@PROJECT_SLUG@@`; remote identity kỳ vọng: `@@PROJECT_REMOTE_ID@@`
     (đã sanitize `host/owner/repo`, lowercase; deploy host `@@DEPLOY_SSH_HOST@@`, service `@@DEPLOY_SERVICE@@`).
   - Tính repo-root slug từ `basename "$(git rev-parse --show-toplevel)"` (lowercase,
     ký tự non-alnum → `-`) và yêu cầu khớp `@@PROJECT_SLUG@@`.
   - Resolve remote chính (`$R`) bằng snippet chuẩn:
     ```sh
     b=$(git branch --show-current)
     R=$(git config --get "branch.$b.remote" 2>/dev/null || true)
     [ "$R" = "." ] && R=
     [ -z "$R" ] && git remote | grep -qx origin && R=origin
     [ -z "$R" ] && [ "$(git remote | wc -l | tr -d ' ')" = 1 ] && R=$(git remote)
     [ -z "$R" ] && echo "STOP: không xác định được remote chính — hỏi user" >&2
     ```
   - Đọc `git config --get "remote.$R.url"`, nhưng KHÔNG BAO GIỜ in hoặc lưu URL gốc. Không resolve được `$R` hoặc thiếu URL → STOP.
   - Sanitize URL của remote chính về lowercase `host/owner/repo`: hỗ trợ `git@host:org/repo.git`,
     `https://[userinfo@]host/org/repo.git`, và `ssh://[userinfo@]host/org/repo.git`; bỏ userinfo,
     dấu `/` đầu, và `.git` cuối.
   - Yêu cầu sanitized remote-chính identity khớp CHÍNH XÁC `@@PROJECT_REMOTE_ID@@`. Nếu `@@PROJECT_REMOTE_ID@@`
     có dạng placeholder (`<...>`), remote chính không parse được, repo-root slug lệch, hoặc remote identity
     lệch → STOP ngay lập tức; báo user command này thuộc về `@@PROJECT_SLUG@@` / `@@PROJECT_REMOTE_ID@@`,
     repo/root/remote chính hiện tại là `<repo identity>` — không chạy deploy. Không có override.
   - Nếu bất kỳ config nào command này dùng vẫn còn dạng placeholder (`<...>`) — `@@DEPLOY_SSH_HOST@@`, `@@DEPLOY_SERVICE@@`, `@@DEPLOY_PATH@@`, `@@DEPLOY_HEALTHCHECK@@` — STOP;
     deploy config chưa đủ (chạy lại install.sh với env var HARNESS_DEPLOY_*).

1. **Verify branch + working tree.**
   - `git branch --show-current` phải là `@@DEPLOY_BRANCH@@`. Nếu không, báo user merge vào
     `@@DEPLOY_BRANCH@@` trước — không tiến hành.
   - `git status --short` — cảnh báo nếu dirty (uncommitted work sẽ không được deploy).
   - **Commit sẽ ship:** `git log @@DEPLOY_REMOTE@@/@@DEPLOY_BRANCH@@..@@DEPLOY_BRANCH@@ --oneline`.
     Rỗng → báo user không có gì để deploy rồi dừng.

2. **Confirm (prod, gây downtime — dừng chờ user OK trừ khi đã pre-authorize sẵn trong prompt).**
   In ra:
   - Commit sẽ ship (từ bước 1, số lượng + tóm tắt 1 dòng mỗi commit).
   - Loại thay đổi: code/runtime · config · docs · mix (`git diff @@DEPLOY_REMOTE@@/@@DEPLOY_BRANCH@@..@@DEPLOY_BRANCH@@ --stat`).
   - Tác động: rebuild + restart `@@DEPLOY_SERVICE@@` → downtime ngắn chỉ trên service đó.
   Chờ user OK rõ ràng trước khi tiến hành, trừ khi request của user đã pre-authorize sẵn
   một lượt chạy end-to-end.

3. **Snapshot trước khi deploy** (để rollback + verify multi-service có baseline):
   ```bash
   ssh @@DEPLOY_SSH_HOST@@ 'echo "=== services ==="; docker ps --format "{{.Names}}\t{{.Status}}"; \
     echo "=== disk ==="; df -h /; docker system df; \
     echo "=== rollback ref ==="; docker inspect --format "{{.Image}}" @@DEPLOY_SERVICE@@'
   ```
   Ghi lại: `docker ps` đầy đủ (mọi service), disk %, và rollback image ref (image id hiện tại của
   `@@DEPLOY_SERVICE@@`). Disk > ~80% → gợi ý chạy `/production-cleanup` trước.

4. **Push + deploy.**
   ```bash
   git push @@DEPLOY_REMOTE@@ @@DEPLOY_BRANCH@@
   ssh @@DEPLOY_SSH_HOST@@ 'cd @@DEPLOY_PATH@@ && (bash bootstrap.sh || (git pull @@DEPLOY_REMOTE@@ @@DEPLOY_BRANCH@@ && docker compose up -d --build @@DEPLOY_SERVICE@@))'
   ```
   Dùng cái nào có sẵn trên host — `bootstrap.sh` (pull + rebuild + up tại chỗ) nếu repo có,
   không thì `git pull` + `docker compose up -d --build @@DEPLOY_SERVICE@@` trực tiếp. Dù cách nào thì cũng
   chỉ đụng đúng `@@DEPLOY_SERVICE@@`; named volume được giữ nguyên.

5. **Verify target.**
   ```bash
   ssh @@DEPLOY_SSH_HOST@@ '@@DEPLOY_HEALTHCHECK@@'
   ```
   Kỳ vọng kết quả healthy/200.

6. **Verify multi-service (kiểm tra regression lan sang service khác).** Chạy lại `docker ps` trên host và diff với
   snapshot ở bước 3 — mọi service KHÁC phải vẫn `Up`/healthy với cùng container id
   (không bị recreate). Bất kỳ hàng xóm nào bị regress hoặc restart → cảnh báo lớn, đây chính xác là failure
   mode mà command này sinh ra để bắt.

7. **Fail → tự động rollback.** Nếu healthcheck ở bước 5 fail:
   ```bash
   ssh @@DEPLOY_SSH_HOST@@ 'docker service update --image <rollback-ref> @@DEPLOY_SERVICE@@ || docker compose up -d --no-build @@DEPLOY_SERVICE@@'
   ```
   `<rollback-ref>` = image id đã ghi ở bước 3. Chạy lại healthcheck bước 5; báo cáo **FAIL +
   đã rollback** — không được để host deploy dở dang.

8. **Báo cáo.** Commit đã ship · disk trước/sau · trạng thái TẤT CẢ service (target + hàng xóm,
   trước/sau).

## Guardrails

- Permission layer của môi trường vẫn gate các Bash call SSH/deploy tại runtime — nếu call
  bị deny hoặc host không reachable, fallback về in ra host command để user tự chạy
  thủ công thay vì ép chạy.
- KHÔNG BAO GIỜ xoá data — không `down -v`, không `docker volume rm`, không `rm -rf`, không prune `--volumes`.
- Chỉ push lên `@@DEPLOY_REMOTE@@`.
- KHÔNG đụng service nào khác ngoài `@@DEPLOY_SERVICE@@`.
