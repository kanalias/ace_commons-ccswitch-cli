---
name: production-deploy
description: Deploy prod tại chỗ an toàn cho host nhiều service — chỉ pull + rebuild + up đúng service ĐÍCH, snapshot trước / verify mọi service sau, tự động rollback khi healthcheck fail. Dùng khi user nói "deploy prod", "đẩy lên production", hoặc chạy /production-deploy.
user-invocable: true
disable-model-invocation: true
---
> **Confirmation gate:** Gọi lệnh rõ ràng không phải là xác nhận. Trước bất kỳ hành động phá huỷ, thay đổi production, hoặc publish ra remote nào, liệt kê rõ target, scope, và tác động; hỏi user xác nhận rõ ràng trong conversation này và chờ. Giữ nguyên mọi xác nhận chặt hơn theo từng workflow bên dưới.


# /production-deploy — Deploy production tại chỗ an toàn

Deploy `<service-name>` trên `<deploy-ssh-host>` bằng cách pull + rebuild + `up` đúng MỘT
service đó tại chỗ. Host này chạy nhiều service — một service chết (image lỗi, healthcheck lỗi)
KHÔNG BAO GIỜ được kéo sập các service hàng xóm. Command này snapshot trạng thái trước, verify mọi service
(target + hàng xóm) sau, và tự động rollback service target khi healthcheck fail.

> ⛔ **QUY TẮC CỨNG — không bao giờ phá huỷ dữ liệu:**
> - Deploy luôn là pull + rebuild + `up` **tại chỗ**. KHÔNG BAO GIỜ `down -v`, `docker volume rm`,
>   `rm -rf`, `docker system prune --volumes`, hay dừng cả host.
> - **Service isolation** — chỉ đụng đúng `<service-name>`. Các service/container khác trên host
>   KHÔNG được restart, recreate, hay mất volume.
> - Prune (nếu cần giải phóng disk) = CHỈ build-cache + dangling image. Không `-a`, không `--volumes`.

## Các bước

0. **Project guard — verify repo identity trước mọi hành động SSH/cloud/git production.**
   - Project slug kỳ vọng: `ccswitch-cli-claude`; remote identity kỳ vọng: `github.com/kanalias/ace_commons-ccswitch-cli`
     (đã sanitize `host/owner/repo`, lowercase; deploy host `<deploy-ssh-host>`, service `<service-name>`).
   - Tính repo-root slug từ `basename "$(git rev-parse --show-toplevel)"` (lowercase,
     ký tự non-alnum → `-`) và yêu cầu khớp `ccswitch-cli-claude`.
   - Đọc `git config --get remote.origin.url`, nhưng KHÔNG BAO GIỜ in hoặc lưu URL gốc. Thiếu origin → STOP.
   - Sanitize origin về lowercase `host/owner/repo`: hỗ trợ `git@host:org/repo.git`,
     `https://[userinfo@]host/org/repo.git`, và `ssh://[userinfo@]host/org/repo.git`; bỏ userinfo,
     dấu `/` đầu, và `.git` cuối.
   - Yêu cầu sanitized origin identity khớp CHÍNH XÁC `github.com/kanalias/ace_commons-ccswitch-cli`. Nếu `github.com/kanalias/ace_commons-ccswitch-cli`
     có dạng placeholder (`<...>`), origin không parse được, repo-root slug lệch, hoặc remote identity
     lệch → STOP ngay lập tức; báo user command này thuộc về `ccswitch-cli-claude` / `github.com/kanalias/ace_commons-ccswitch-cli`,
     repo/root/origin hiện tại là `<repo identity>` — không chạy deploy. Không có override.
   - Nếu bất kỳ config nào command này dùng vẫn còn dạng placeholder (`<...>`) — `<deploy-ssh-host>`, `<service-name>`, `<remote-repo-path>`, `<healthcheck-cmd>` — STOP;
     deploy config chưa đủ (chạy lại install.sh với env var HARNESS_DEPLOY_*).

1. **Verify branch + working tree.**
   - `git branch --show-current` phải là `main`. Nếu không, báo user merge vào
     `main` trước — không tiến hành.
   - `git status --short` — cảnh báo nếu dirty (uncommitted work sẽ không được deploy).
   - **Commit sẽ ship:** `git log origin/main..main --oneline`.
     Rỗng → báo user không có gì để deploy rồi dừng.

2. **Confirm (prod, gây downtime — dừng chờ user OK trừ khi đã pre-authorize sẵn trong prompt).**
   In ra:
   - Commit sẽ ship (từ bước 1, số lượng + tóm tắt 1 dòng mỗi commit).
   - Loại thay đổi: code/runtime · config · docs · mix (`git diff origin/main..main --stat`).
   - Tác động: rebuild + restart `<service-name>` → downtime ngắn chỉ trên service đó.
   Chờ user OK rõ ràng trước khi tiến hành, trừ khi request của user đã pre-authorize sẵn
   một lượt chạy end-to-end.

3. **Snapshot trước khi deploy** (để rollback + verify multi-service có baseline):
   ```bash
   ssh <deploy-ssh-host> 'echo "=== services ==="; docker ps --format "{{.Names}}\t{{.Status}}"; \
     echo "=== disk ==="; df -h /; docker system df; \
     echo "=== rollback ref ==="; docker inspect --format "{{.Image}}" <service-name>'
   ```
   Ghi lại: `docker ps` đầy đủ (mọi service), disk %, và rollback image ref (image id hiện tại của
   `<service-name>`). Disk > ~80% → gợi ý chạy `/production-cleanup` trước.

4. **Push + deploy.**
   ```bash
   git push origin main
   ssh <deploy-ssh-host> 'cd <remote-repo-path> && (bash bootstrap.sh || (git pull origin main && docker compose up -d --build <service-name>))'
   ```
   Dùng cái nào có sẵn trên host — `bootstrap.sh` (pull + rebuild + up tại chỗ) nếu repo có,
   không thì `git pull` + `docker compose up -d --build <service-name>` trực tiếp. Dù cách nào thì cũng
   chỉ đụng đúng `<service-name>`; named volume được giữ nguyên.

5. **Verify target.**
   ```bash
   ssh <deploy-ssh-host> '<healthcheck-cmd>'
   ```
   Kỳ vọng kết quả healthy/200.

6. **Verify multi-service (kiểm tra regression lan sang service khác).** Chạy lại `docker ps` trên host và diff với
   snapshot ở bước 3 — mọi service KHÁC phải vẫn `Up`/healthy với cùng container id
   (không bị recreate). Bất kỳ hàng xóm nào bị regress hoặc restart → cảnh báo lớn, đây chính xác là failure
   mode mà command này sinh ra để bắt.

7. **Fail → tự động rollback.** Nếu healthcheck ở bước 5 fail:
   ```bash
   ssh <deploy-ssh-host> 'docker service update --image <rollback-ref> <service-name> || docker compose up -d --no-build <service-name>'
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
- Chỉ push lên `origin`.
- KHÔNG đụng service nào khác ngoài `<service-name>`.
