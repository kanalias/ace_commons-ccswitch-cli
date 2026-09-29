---
name: production-deploy
description: "Deploy prod tại chỗ cho host nhiều service: pull + rebuild + up đúng service đích, verify, tự rollback khi healthcheck fail. Dùng khi \"deploy prod\" hoặc /production-deploy."
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

**Boundary validation:** production smoke/healthcheck `<healthcheck-cmd>` là validation duy nhất trong phase deploy.
Full unit/integration/E2E/typecheck/app-build/export suite thuộc gate `/git-push-safety` độc lập trước deploy;
Docker image rebuild ở bước deploy vẫn được phép. `/production-deploy` KHÔNG invoke skill đó và không chạy full
suite thay thế. Chấp nhận đúng một trong hai preflight state, tránh vòng lặp gate/push:
- Branch đã được `/git-push-safety` gate + push: local `HEAD` phải bằng `origin/main`;
  deploy đúng remote HEAD đó, không push lại.
- Có pending commit chưa push: evidence gate phải nêu đúng range `origin/main..HEAD` và
  PASS; sau confirm mới dùng hook-approved push ở bước 4.
Smoke config thiếu/không resolve được, hoặc không có evidence phù hợp state trên → STOP trước push/deploy;
không fallback sang full suite. Evidence phải có trong conversation hiện tại hoặc artifact tin cậy user chỉ rõ;
không tự suy diễn từ CI xanh cũ.

**Song song (bắt buộc, xem [[orchestrator]] rule 7):** bước 0 + 1 + 3 đều read-only → chạy chung
1 message nhiều tool-call TRƯỚC confirm, để bước 2 in luôn disk % + snapshot cho user quyết. Bước 5 ‖ 6
(verify target ‖ verify hàng xóm) chạy chung 1 message. Tuần tự bắt buộc: preflight evidence → 2 (chờ user)
→ 4 → (5 ‖ 6) → 7.


0. **Project guard — verify repo identity trước mọi hành động SSH/cloud/git production.**
   - Project slug kỳ vọng: `ccswitch-cli-claude`; remote identity kỳ vọng: `github.com/kanalias/ace_commons-ccswitch-cli`
     (đã sanitize `host/owner/repo`, lowercase; deploy host `<deploy-ssh-host>`, service `<service-name>`).
   - Tính repo-root slug từ `basename "$(git rev-parse --show-toplevel)"` (lowercase,
     ký tự non-alnum → `-`) và yêu cầu khớp `ccswitch-cli-claude`.
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
   - Yêu cầu sanitized remote-chính identity khớp CHÍNH XÁC `github.com/kanalias/ace_commons-ccswitch-cli`. Nếu `github.com/kanalias/ace_commons-ccswitch-cli`
     có dạng placeholder (`<...>`), remote chính không parse được, repo-root slug lệch, hoặc remote identity
     lệch → STOP ngay lập tức; báo user command này thuộc về `ccswitch-cli-claude` / `github.com/kanalias/ace_commons-ccswitch-cli`,
     repo/root/remote chính hiện tại là `<repo identity>` — không chạy deploy. Không có override.
   - Nếu bất kỳ config nào command này dùng vẫn còn dạng placeholder (`<...>`) — `<deploy-ssh-host>`, `<service-name>`, `<remote-repo-path>`, `<healthcheck-cmd>` — STOP;
     deploy config chưa đủ (chạy lại install.sh với env var HARNESS_DEPLOY_*).
   - Nếu smoke/healthcheck config thiếu, rỗng, hoặc không thể chạy như configured → STOP trước push/deploy;
     không chạy full suite thay thế.

1. **Verify branch + working tree.**
   - `git branch --show-current` phải là `main`. Nếu không, báo user merge vào
     `main` trước — không tiến hành.
   - `git status --short` — cảnh báo nếu dirty (uncommitted work sẽ không được deploy).
   - Fetch remote ref read-only, rồi phân loại preflight state:
     - `HEAD == origin/main`: remote HEAD đã push; yêu cầu evidence gate cho chính commit đó.
     - `HEAD` đi trước remote: **Commit sẽ ship:** `git log origin/main..HEAD --oneline`;
       yêu cầu evidence gate đúng range này.
     - Local đi sau/diverge remote → STOP, không tự merge/rebase/deploy.

2. **Confirm (prod, gây downtime — dừng chờ user OK trừ khi đã pre-authorize sẵn trong prompt).**
   In ra:
   - Commit sẽ deploy: remote HEAD hiện tại hoặc pending commit từ bước 1; số lượng + tóm tắt 1 dòng mỗi commit.
   - Loại thay đổi: code/runtime · config · docs · mix (diff range tương ứng state ở bước 1).
   - Tác động: rebuild + restart `<service-name>` → downtime ngắn chỉ trên service đó.
   Chờ user OK rõ ràng trước khi tiến hành, trừ khi request của user đã pre-authorize sẵn
   một lượt chạy end-to-end.

3. **Snapshot trước khi deploy** (để rollback + verify multi-service có baseline):
   ```bash
   ssh <deploy-ssh-host> 'echo "=== services ==="; docker ps --format "{{.Names}}\t{{.Status}}"; \
     echo "=== disk ==="; df -h /; docker system df; \
     echo "=== rollback ref ==="; docker inspect --format "{{.Image}}" <service-name>; \
     echo "=== compose image ref ==="; docker inspect --format "{{.Config.Image}}" <service-name>'
   ```
   Ghi lại: `docker ps` đầy đủ, disk %, immutable `<rollback-ref>` (image ID hiện tại), và
   `<compose-image-ref>` (`Config.Image`) của `<service-name>`. Thiếu một trong hai ref → STOP trước deploy;
   không thể đảm bảo rollback Compose. Disk > ~80% → gợi ý chạy `/production-cleanup` trước.

4. **Push + deploy.** Chỉ sau preflight evidence phù hợp + confirm ở bước 2. Branch đã gate/push thì bỏ qua push;
   pending commit mới dùng raw push đã được hook approve:
   ```bash
   GIT_PUSH_GATE_OK=1 git push origin main
   ssh <deploy-ssh-host> 'cd <remote-repo-path> && if [ -f bootstrap.sh ]; then bash bootstrap.sh; else git pull origin main && docker compose up -d --build <service-name>; fi'
   ```
   Không set `GIT_PUSH_GATE_OK=1` trước khi cả hai gate pass; không push lại branch đã gate/push. Nếu
   `bootstrap.sh` tồn tại thì chỉ chạy script đó; `bootstrap.sh` tồn tại nhưng fail → deploy fail, STOP — không
   fallback sang path khác. Chỉ khi file không tồn tại mới chạy `git pull` +
   `docker compose up -d --build <service-name>`. Dù cách nào thì cũng chỉ đụng đúng
   `<service-name>`; named volume được giữ nguyên.

5. **Verify target — production smoke duy nhất.**
   ```bash
   ssh <deploy-ssh-host> '<healthcheck-cmd>'
   ```
   Exit 0 = healthy. Non-zero hoặc timeout = deploy failure, chuyển ngay bước 7; không chạy validation suite khác.

6. **Verify multi-service (kiểm tra regression lan sang service khác).** Chạy lại `docker ps` trên host và diff với
   snapshot ở bước 3 — mọi service KHÁC phải vẫn `Up`/healthy với cùng container id
   (không bị recreate). Bất kỳ hàng xóm nào bị regress hoặc restart → cảnh báo lớn, đây chính xác là failure
   mode mà command này sinh ra để bắt.

7. **Fail → tự động rollback.** Nếu smoke ở bước 5 non-zero hoặc timeout, pin Compose về immutable image ID,
   rồi xác định đúng container target và chứng minh nó chạy image đó trước healthcheck:
   ```bash
   ssh <deploy-ssh-host> "rollback_ref='<rollback-ref>'; compose_image_ref='<compose-image-ref>'; service='<service-name>'; docker tag \"\$rollback_ref\" \"\$compose_image_ref\" && cd <remote-repo-path> && docker compose up -d --no-build \"\$service\" && ids=\$(docker compose ps --all --quiet \"\$service\") && count=\$(printf '%s\\n' \"\$ids\" | grep -c .) && [ \"\$count\" -eq 1 ] && cid=\$ids && actual=\$(docker inspect --format '{{.Image}}' \"\$cid\") && [ \"\$actual\" = \"\$rollback_ref\" ]"
   ssh <deploy-ssh-host> '<healthcheck-cmd>'
   ```
   `<rollback-ref>` và `<compose-image-ref>` lấy từ bước 3. `docker compose ps --all --quiet` resolve container
   của đúng Compose service, kể cả container đã dừng. Rollback chỉ hoàn thành khi có đúng MỘT container ID,
   `docker inspect --format '{{.Image}}'` thành công, và image bằng chính xác immutable `<rollback-ref>`.
   Không có container, nhiều container, `docker inspect` lỗi, image không khớp, `docker tag` lỗi, hoặc Compose
   non-zero → báo **FAIL + rollback unhealthy/incomplete**, target **unhealthy — STOP**; không chạy healthcheck,
   không claim đã rollback. Identity pass mới chạy lại đúng production smoke. Smoke pass mới báo cáo
   **FAIL + đã rollback**. Smoke fail/timeout → báo **FAIL + rollback unhealthy/incomplete**, target
   **unhealthy — STOP**; không chạy full suite, không tiếp tục action production khác.

8. **Báo cáo.** Commit đã ship · disk trước/sau · trạng thái TẤT CẢ service (target + hàng xóm,
   trước/sau).

## Guardrails

- Permission layer của môi trường vẫn gate các Bash call SSH/deploy tại runtime — nếu call
  bị deny hoặc host không reachable, fallback về in ra host command để user tự chạy
  thủ công thay vì ép chạy.
- KHÔNG BAO GIỜ xoá data — không `down -v`, không `docker volume rm`, không `rm -rf`, không prune `--volumes`.
- Chỉ push pending commit lên `origin`; raw push phải là `GIT_PUSH_GATE_OK=1 git push ...` sau preflight + confirm. Branch đã gate/push thì deploy remote HEAD, không push lại.
- KHÔNG invoke `/git-push-safety` từ skill này; thiếu evidence gate phù hợp thì STOP.
- KHÔNG đụng service nào khác ngoài `<service-name>`.
