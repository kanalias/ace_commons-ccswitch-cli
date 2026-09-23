---
name: production-reboot
description: Khôi phục host prod bị WEDGED (TCP mở nhưng HTTP=000 / SSH banner-timeout — thường do disk-full ENOSPC) qua reboot out-of-band từ provider, sau đó cleanup + verify. Dùng khi user nói "prod bị treo", "host wedged", hoặc chạy /production-reboot.
user-invocable: true
disable-model-invocation: true
---
> **Confirmation gate:** Việc gọi command rõ ràng KHÔNG phải là xác nhận. Trước mọi hành động phá huỷ, thay đổi production, hoặc publish ra remote, liệt kê rõ target, scope, và impact; hỏi user xác nhận rõ ràng trong hội thoại này và chờ. Giữ nguyên mọi xác nhận chặt hơn riêng của workflow bên dưới.


# /production-reboot — Khôi phục out-of-band cho host prod bị wedged

Dùng khi `<deploy-ssh-host>` **bị wedged ở tầng userspace**: TCP port accept nhanh nhưng không
service nào trả data — `ssh` treo ở "banner exchange", healthcheck timeout (HTTP `000`).
Kernel vẫn sống (TCP SYN có trả lời) nhưng userspace bị đói tài nguyên — gần như luôn do **disk full (ENOSPC)**
vì Docker build cache lấp đầy `/`. SSH không truy cập được, nên đòn bẩy duy nhất còn lại là **reboot
out-of-band** qua API/console của provider.

> ⛔ **QUY TẮC CỨNG**
> - **Chỉ reboot** — không bao giờ stop/start instance nếu IP public không được đảm bảo static
>   (stop/start có thể đổi IP và làm hỏng DNS/truy cập). Nếu provider đảm bảo static IP,
>   xác nhận điều đó trước khi cân nhắc stop/start; mặc định dùng reboot.
> - **KHÔNG BAO GIỜ xoá data** — reboot giữ nguyên root disk + named volume. Không `down -v` /
>   `docker volume rm` / `rm -rf` bất cứ gì.
> - Reboot gây **downtime cho mọi service trên host**. Production → xác nhận với user
>   trước khi issue lệnh reboot.

## Các bước

0. **Project guard — verify repo identity trước mọi hành động SSH/cloud/git trên production.**
   - Project slug kỳ vọng: `ccswitch-cli-claude`; remote identity kỳ vọng: `github.com/kanalias/ace_commons-ccswitch-cli`
     (đã sanitize `host/owner/repo`, lowercase; deploy host `<deploy-ssh-host>`, service `<service-name>`).
   - Tính repo-root slug từ `basename "$(git rev-parse --show-toplevel)"` (lowercase,
     non-alnum → `-`) và yêu cầu nó khớp `ccswitch-cli-claude`.
   - Đọc `git config --get remote.origin.url`, nhưng KHÔNG bao giờ in hoặc lưu raw URL. Thiếu origin → STOP.
   - Sanitize origin về lowercase `host/owner/repo`: hỗ trợ `git@host:org/repo.git`,
     `https://[userinfo@]host/org/repo.git`, và `ssh://[userinfo@]host/org/repo.git`; strip userinfo,
     leading slash, và trailing `.git`.
   - Yêu cầu sanitized origin identity khớp CHÍNH XÁC `github.com/kanalias/ace_commons-ccswitch-cli`. Nếu `github.com/kanalias/ace_commons-ccswitch-cli`
     có dạng placeholder (`<...>`), origin không parse được, repo-root slug không khớp, hoặc remote identity
     không khớp → STOP ngay; báo user rằng command này thuộc về `ccswitch-cli-claude` / `github.com/kanalias/ace_commons-ccswitch-cli`,
     repo/root/origin hiện tại là `<repo identity>` — không chạy reboot. Không có override.
   - Nếu bất kỳ config nào command này dùng vẫn còn dạng placeholder (`<...>`) — `<deploy-ssh-host>`, `<service-name>` — STOP;
     deploy config chưa đầy đủ (chạy lại install.sh với biến env HARNESS_DEPLOY_*).

1. **Xác nhận host thật sự bị wedged (không chỉ chậm).** Từ local, probe TCP + SSH banner:
   ```bash
   ssh -o ConnectTimeout=15 <deploy-ssh-host> 'echo SSH_OK; uptime' 2>&1 | head -2
   ```
   - **Nếu SSH trả về `SSH_OK`** → host KHÔNG bị wedged. **Không** reboot. Chạy
     [/production-cleanup](../production-cleanup/SKILL.md) thay thế (nhiều khả năng chỉ là disk pressure).
   - Dấu hiệu wedged: port mở (TCP connect được) nhưng SSH banner-timeout và healthcheck timeout.

2. **Reboot out-of-band — ví dụ, tự điều chỉnh theo cloud provider của bạn.** SSH/console không truy cập được, nên
   phải đi qua control-plane API của provider. Ví dụ cho AWS EC2 (điều chỉnh instance id,
   region, và auth profile theo setup thật của bạn — không hardcode giá trị thật ở đây):
   ```bash
   # example only — replace <instance-id> / <region> / <profile>
   aws ec2 describe-instance-status --profile <profile> --region <region> \
     --instance-ids <instance-id> \
     --query 'InstanceStatuses[].{State:InstanceState.Name,Inst:InstanceStatus.Status,Sys:SystemStatus.Status}' --output table
   aws ec2 reboot-instances --profile <profile> --region <region> --instance-ids <instance-id>
   ```
   `reboot-instances` (không phải stop/start) giữ nguyên IP. Với provider khác, dùng action
   reboot-only API/console tương đương (không bao giờ dùng stop+start / power-cycle làm đổi IP).

3. **Xác nhận với user trước khi issue lệnh reboot** — đây là production downtime cho mọi
   service trên host. Lấy OK rõ ràng trừ khi đã được pre-authorize.

4. **Poll SSH đến khi host trở lại:**
   ```bash
   for i in $(seq 1 12); do
     if out=$(ssh -o ConnectTimeout=10 <deploy-ssh-host> 'echo SSH_OK; uptime; df -h / | tail -1' 2>/dev/null); then
       echo "UP"; echo "$out"; break
     else echo "attempt $i: not yet"; sleep 15; fi
   done
   ```

5. **Cleanup + verify.** Reboot lấy lại được SSH nhưng KHÔNG tự giải phóng disk — chạy
   [/production-cleanup](../production-cleanup/SKILL.md) để prune build cache/dangling image và verify
   `<service-name>` cùng mọi service khác trên host.

## Guardrails

- Chỉ reboot — không bao giờ stop/start (hoặc tương đương) có thể làm đổi IP host.
- Không bao giờ xoá data: không `down -v`, không `docker volume rm`, không `rm -rf`.
- Xác nhận với user trước khi issue lệnh reboot (production downtime cho toàn bộ host).
- Nếu SSH thực tế vẫn truy cập được, KHÔNG reboot — đi thẳng tới /production-cleanup.
