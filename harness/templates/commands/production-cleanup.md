---
name: production-cleanup
description: Giải phóng disk trên prod host — chỉ prune Docker build cache + dangling image, sau đó verify service mục tiêu và các service lân cận. An toàn, không downtime, không mất dữ liệu. Dùng khi user nói "dọn disk prod", "cleanup production", hoặc chạy /production-cleanup.
user-invocable: true
disable-model-invocation: true
---
> **Confirmation gate:** Việc gọi command rõ ràng KHÔNG phải là xác nhận. Trước mọi hành động phá huỷ, thay đổi production, hoặc publish ra remote, liệt kê rõ target, scope, và impact; hỏi user xác nhận rõ ràng trong hội thoại này và chờ. Giữ nguyên mọi xác nhận chặt hơn riêng của workflow bên dưới.


# /production-cleanup — Giải phóng disk trên prod host (an toàn, không downtime)

Docker build cache tích luỹ sau mỗi lần build deploy, cùng với dangling image, có thể lấp đầy
`/` tới gần 100% → ENOSPC → cả host bị kẹt cứng. Command này giải phóng không gian đó **an toàn, tại
chỗ, không downtime và không mất dữ liệu** — chỉ prune build cache + dangling image, không đụng
volume hay container đang chạy.

> ⛔ **QUY TẮC CỨNG — không đụng dữ liệu:**
> - **KHÔNG BAO GIỜ** chạy `docker system prune --volumes`, `docker volume rm`, `down -v`, `rm -rf`, hoặc `-a`
>   trên image/system prune (có thể xoá image vẫn đang được container đã dừng tham chiếu).
> - Phạm vi prune = **CHỈ build cache + dangling image**. Container đang chạy, named volume, và
>   image đang dùng giữ nguyên, không đụng tới.
> - Không stop/restart/recreate `@@DEPLOY_SERVICE@@` hay bất kỳ service nào khác trong lúc cleanup.

## Steps

0. **Project guard — verify repo identity trước mọi thao tác SSH/cloud/git trên production.**
   - Project slug kỳ vọng: `@@PROJECT_SLUG@@`; remote identity kỳ vọng: `@@PROJECT_REMOTE_ID@@`
     (đã sanitize `host/owner/repo`, chữ thường; deploy host `@@DEPLOY_SSH_HOST@@`, service `@@DEPLOY_SERVICE@@`).
   - Tính repo-root slug từ `basename "$(git rev-parse --show-toplevel)"` (chữ thường,
     ký tự non-alnum → `-`) và yêu cầu khớp `@@PROJECT_SLUG@@`.
   - Đọc `git config --get remote.origin.url`, nhưng KHÔNG BAO GIỜ in ra hay lưu lại URL gốc. Thiếu origin → STOP.
   - Sanitize origin về `host/owner/repo` chữ thường: hỗ trợ `git@host:org/repo.git`,
     `https://[userinfo@]host/org/repo.git`, và `ssh://[userinfo@]host/org/repo.git`; bỏ userinfo,
     dấu `/` đầu, và `.git` cuối.
   - Yêu cầu origin identity đã sanitize khớp CHÍNH XÁC `@@PROJECT_REMOTE_ID@@`. Nếu `@@PROJECT_REMOTE_ID@@`
     có dạng placeholder (`<...>`), origin không parse được, repo-root slug không khớp, hoặc remote identity
     không khớp → STOP ngay; báo user command này thuộc về `@@PROJECT_SLUG@@` / `@@PROJECT_REMOTE_ID@@`,
     repo/root/origin hiện tại là `<repo identity>` — không chạy cleanup. Không có override.
   - Nếu config nào dùng bởi command này vẫn còn dạng placeholder (`<...>`) — `@@DEPLOY_SSH_HOST@@`, `@@DEPLOY_SERVICE@@`, `@@DEPLOY_HEALTHCHECK@@` — STOP;
     deploy config chưa đầy đủ (chạy lại install.sh với biến env HARNESS_DEPLOY_*).

1. **Đánh giá disk + không gian có thể giải phóng.**
   ```bash
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ 'echo "=== DISK ==="; df -h / | tail -1; echo; echo "=== DOCKER DF ==="; docker system df'
   ```
   Báo `Use%` và cột `RECLAIMABLE`. Nếu disk còn thoải mái (< ~75%) và reclaimable
   nhỏ, báo user không có gì đáng prune và dừng.

2. **Prune build cache + dangling image (an toàn — không volume, không `-a`).**
   ```bash
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ 'echo "=== builder cache ==="; docker builder prune -af | tail -3; echo "=== dangling images ==="; docker image prune -f | tail -3; echo "=== disk after ==="; df -h / | tail -1'
   ```
   - `docker builder prune -af` → chỉ xoá BuildKit cache (an toàn).
   - `docker image prune -f` (không `-a`) → chỉ xoá dangling image; image được bất kỳ
     container nào tham chiếu, kể cả container đã dừng, vẫn được giữ lại.

3. **Verify service mục tiêu VÀ mọi service khác không bị đụng tới + vẫn healthy.**
   ```bash
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ 'docker ps --format "{{.Names}}\t{{.Status}}"'
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ '@@DEPLOY_HEALTHCHECK@@'
   ```
   Mọi service trong `docker ps` vẫn phải hiện `Up`/`healthy`, cùng container id như trước (command
   này không được restart bất cứ gì). Healthcheck của target phải trả về healthy/200.

4. **Báo cáo** disk trước/sau (vd `92% → 71%, freed ~8GB`) và xác nhận mọi service vẫn healthy.

## Guardrails

- CHỈ prune build cache + dangling image. Không bao giờ `--volumes`, không bao giờ `docker volume rm`, không bao giờ `-a`
  trên image prune, không bao giờ `down -v` / `rm -rf`.
- Không bao giờ restart/recreate service nào ở đây — đây là dọn disk, không phải deploy.
- Nếu host bị kẹt cứng hoàn toàn (SSH treo ở banner exchange), cleanup không chạy được — dùng
  [/production-reboot](production-reboot.md) trước để lấy lại SSH, rồi mới chạy cái này.
