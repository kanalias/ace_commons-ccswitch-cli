---
name: production-reboot
description: Recover a WEDGED prod host (TCP open but HTTP=000 / SSH banner-timeout — usually disk-full ENOSPC) via out-of-band provider reboot, then cleanup + verify. Dùng khi user nói "prod bị treo", "host wedged", hoặc chạy /production-reboot.
user-invocable: true
---

# /production-reboot — Out-of-band recovery of a wedged prod host

Use when `<deploy-ssh-host>` is **wedged at the userspace layer**: TCP ports accept fast but no
service returns data — `ssh` hangs at "banner exchange", the healthcheck times out (HTTP `000`).
Kernel is alive (TCP SYN answered) but userspace is starved — almost always **disk full (ENOSPC)**
from Docker build cache filling `/`. SSH is unreachable, so the only lever left is an **out-of-band
reboot** via the provider's API/console.

> ⛔ **HARD RULES**
> - **Reboot only** — never stop/start the instance if its public IP is not guaranteed static
>   (stop/start can change the IP and break DNS/access). If the provider guarantees a static IP,
>   confirm that before considering stop/start; default to reboot.
> - **NEVER wipe data** — reboot preserves the root disk + named volumes. Do not `down -v` /
>   `docker volume rm` / `rm -rf` anything.
> - Reboot causes **downtime on every service on the host**. Production → confirm with the user
>   before issuing the reboot.

## Steps

0. **Project guard — verify repo identity before any SSH/cloud/git production action.**
   - Expected project slug: `ccswitch-cli-claude`; expected remote identity: `github.com/acegalaxy-co/ace_commons-ccswitch-cli`
     (sanitized `host/owner/repo`, lowercase; deploy host `<deploy-ssh-host>`, service `<service-name>`).
   - Compute repo-root slug from `basename "$(git rev-parse --show-toplevel)"` (lowercase,
     non-alnum → `-`) and require it to match `ccswitch-cli-claude`.
   - Read `git config --get remote.origin.url`, but never print or persist the raw URL. Missing origin → STOP.
   - Sanitize origin to lowercase `host/owner/repo`: support `git@host:org/repo.git`,
     `https://[userinfo@]host/org/repo.git`, and `ssh://[userinfo@]host/org/repo.git`; strip userinfo,
     leading slash, and trailing `.git`.
   - Require sanitized origin identity to exactly match `github.com/acegalaxy-co/ace_commons-ccswitch-cli`. If expected identity
     is placeholder-shaped (`<...>`), origin is unparseable, repo-root slug mismatches, or remote identity
     mismatches → STOP immediately; tell the user this command belongs to `ccswitch-cli-claude` / `github.com/acegalaxy-co/ace_commons-ccswitch-cli`,
     current repo/root/origin is `<repo identity>` — not running reboot. No override.
   - If any config used by this command is still placeholder-shaped (`<...>`) — `<deploy-ssh-host>`, `<service-name>` — STOP;
     deploy config is incomplete (re-run install.sh with HARNESS_DEPLOY_* env vars).

1. **Confirm it's actually wedged (not just slow).** From local, probe TCP + SSH banner:
   ```bash
   ssh -o ConnectTimeout=15 <deploy-ssh-host> 'echo SSH_OK; uptime' 2>&1 | head -2
   ```
   - **If SSH returns `SSH_OK`** → host is NOT wedged. Do **not** reboot. Run
     [/production-cleanup](production-cleanup.md) instead (likely just disk pressure).
   - Wedged signature: port open (TCP connects) but SSH banner-timeout and the healthcheck times out.

2. **Out-of-band reboot — example, adapt to your cloud provider.** SSH/console are unreachable, so
   this must go through the provider's control-plane API. Example for AWS EC2 (adapt instance id,
   region, and auth profile to your actual setup — do not hardcode real values here):
   ```bash
   # example only — replace <instance-id> / <region> / <profile>
   aws ec2 describe-instance-status --profile <profile> --region <region> \
     --instance-ids <instance-id> \
     --query 'InstanceStatuses[].{State:InstanceState.Name,Inst:InstanceStatus.Status,Sys:SystemStatus.Status}' --output table
   aws ec2 reboot-instances --profile <profile> --region <region> --instance-ids <instance-id>
   ```
   `reboot-instances` (not stop/start) keeps the IP. For other providers, use the equivalent
   reboot-only API/console action (never a stop+start / power-cycle-that-reassigns-IP action).

3. **Confirm with the user before issuing the reboot** — this is production downtime on every
   service on the host. Get explicit OK unless already pre-authorized.

4. **Poll SSH until the host is back:**
   ```bash
   for i in $(seq 1 12); do
     if out=$(ssh -o ConnectTimeout=10 <deploy-ssh-host> 'echo SSH_OK; uptime; df -h / | tail -1' 2>/dev/null); then
       echo "UP"; echo "$out"; break
     else echo "attempt $i: not yet"; sleep 15; fi
   done
   ```

5. **Cleanup + verify.** The reboot regains SSH but does NOT free disk on its own — run
   [/production-cleanup](production-cleanup.md) to prune build cache/dangling images and verify
   `<service-name>` plus every other service on the host.

## Guardrails

- Reboot only — never a stop/start (or equivalent) that could change the host's IP.
- Never wipe data: no `down -v`, no `docker volume rm`, no `rm -rf`.
- Confirm with the user before issuing the reboot (production downtime on the whole host).
- If SSH is actually reachable, do NOT reboot — go straight to /production-cleanup.
