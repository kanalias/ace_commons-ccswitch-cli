---
name: production-cleanup
description: Reclaim disk on the prod host — prune Docker build cache + dangling images only, then verify the target service and its neighbors. Safe, no downtime, no data loss. Dùng khi user nói "dọn disk prod", "cleanup production", hoặc chạy /production-cleanup.
user-invocable: true
---

# /production-cleanup — Reclaim disk on the prod host (safe, no downtime)

Docker build cache accumulates on every deploy build and, together with dangling images, can fill
`/` toward 100% → ENOSPC → the whole host wedges. This command reclaims that space **safely, in
place, with no downtime and no data loss** — it prunes only build cache + dangling images, never
volumes or running containers.

> ⛔ **HARD RULES — never touch data:**
> - **NEVER** `docker system prune --volumes`, `docker volume rm`, `down -v`, `rm -rf`, or `-a` on
>   image/system prune (that can drop images still referenced by stopped containers).
> - Prune scope = **build cache + dangling images ONLY**. Running containers, named volumes, and
>   in-use images stay untouched.
> - Do not stop/restart/recreate `@@DEPLOY_SERVICE@@` or any other service as part of cleanup.

## Steps

0. **Project guard — verify repo identity before any SSH/cloud/git production action.**
   - Expected project slug: `@@PROJECT_SLUG@@`; expected remote identity: `@@PROJECT_REMOTE_ID@@`
     (sanitized `host/owner/repo`, lowercase; deploy host `@@DEPLOY_SSH_HOST@@`, service `@@DEPLOY_SERVICE@@`).
   - Compute repo-root slug from `basename "$(git rev-parse --show-toplevel)"` (lowercase,
     non-alnum → `-`) and require it to match `@@PROJECT_SLUG@@`.
   - Read `git config --get remote.origin.url`, but never print or persist the raw URL. Missing origin → STOP.
   - Sanitize origin to lowercase `host/owner/repo`: support `git@host:org/repo.git`,
     `https://[userinfo@]host/org/repo.git`, and `ssh://[userinfo@]host/org/repo.git`; strip userinfo,
     leading slash, and trailing `.git`.
   - Require sanitized origin identity to exactly match `@@PROJECT_REMOTE_ID@@`. If `@@PROJECT_REMOTE_ID@@`
     is placeholder-shaped (`<...>`), origin is unparseable, repo-root slug mismatches, or remote identity
     mismatches → STOP immediately; tell the user this command belongs to `@@PROJECT_SLUG@@` / `@@PROJECT_REMOTE_ID@@`,
     current repo/root/origin is `<repo identity>` — not running cleanup. No override.
   - If any config used by this command is still placeholder-shaped (`<...>`) — `@@DEPLOY_SSH_HOST@@`, `@@DEPLOY_SERVICE@@`, `@@DEPLOY_HEALTHCHECK@@` — STOP;
     deploy config is incomplete (re-run install.sh with HARNESS_DEPLOY_* env vars).

1. **Assess disk + reclaimable space.**
   ```bash
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ 'echo "=== DISK ==="; df -h / | tail -1; echo; echo "=== DOCKER DF ==="; docker system df'
   ```
   Report `Use%` and the `RECLAIMABLE` column. If disk is comfortably low (< ~75%) and reclaimable
   is small, tell the user there's nothing worth pruning and stop.

2. **Prune build cache + dangling images (safe — no volumes, no `-a`).**
   ```bash
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ 'echo "=== builder cache ==="; docker builder prune -af | tail -3; echo "=== dangling images ==="; docker image prune -f | tail -3; echo "=== disk after ==="; df -h / | tail -1'
   ```
   - `docker builder prune -af` → clears BuildKit cache only (safe).
   - `docker image prune -f` (no `-a`) → removes dangling images only; images referenced by any
     container, including stopped ones, are kept.

3. **Verify the target service AND every other service is untouched + healthy.**
   ```bash
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ 'docker ps --format "{{.Names}}\t{{.Status}}"'
   ssh -o ConnectTimeout=15 @@DEPLOY_SSH_HOST@@ '@@DEPLOY_HEALTHCHECK@@'
   ```
   Every service in `docker ps` should still show `Up`/`healthy`, same container ids as before (this
   command should not have restarted anything). Target healthcheck should return healthy/200.

4. **Report** disk before/after (e.g. `92% → 71%, freed ~8GB`) and that every service stayed healthy.

## Guardrails

- Prune build cache + dangling images ONLY. Never `--volumes`, never `docker volume rm`, never `-a`
  on image prune, never `down -v` / `rm -rf`.
- Never restart/recreate any service here — this is disk cleanup, not a deploy.
- If the host is fully wedged (SSH hangs at banner exchange), cleanup can't run — use
  [/production-reboot](production-reboot.md) first to regain SSH, then run this.
