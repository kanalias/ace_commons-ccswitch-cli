---
name: production-deploy
description: Safe in-place prod deploy for a multi-service host — pull + rebuild + up the TARGET service only, snapshot before / verify all services after, auto-rollback on healthcheck fail. Dùng khi user nói "deploy prod", "đẩy lên production", hoặc chạy /production-deploy.
user-invocable: true
---

# /production-deploy — Safe in-place production deploy

Deploy `@@DEPLOY_SERVICE@@` on `@@DEPLOY_SSH_HOST@@` by pulling + rebuilding + `up`-ing that ONE
service in place. The host runs multiple services — one service dying (bad image, bad healthcheck)
must never take down its neighbors. This command snapshots state before, verifies every service
(target + neighbors) after, and auto-rolls-back the target on healthcheck failure.

> ⛔ **HARD RULES — never destructive:**
> - Deploy is always pull + rebuild + `up` **in place**. NEVER `down -v`, `docker volume rm`,
>   `rm -rf`, `docker system prune --volumes`, or stop the whole host.
> - **Service isolation** — only touch `@@DEPLOY_SERVICE@@`. Other services/containers on the host
>   must not be restarted, recreated, or lose volumes.
> - Prune (if needed for disk) = build-cache + dangling images ONLY. No `-a`, no `--volumes`.

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
     current repo/root/origin is `<repo identity>` — not running deploy. No override.
   - If any config used by this command is still placeholder-shaped (`<...>`) — `@@DEPLOY_SSH_HOST@@`, `@@DEPLOY_SERVICE@@`, `@@DEPLOY_PATH@@`, `@@DEPLOY_HEALTHCHECK@@` — STOP;
     deploy config is incomplete (re-run install.sh with HARNESS_DEPLOY_* env vars).

1. **Verify branch + working tree.**
   - `git branch --show-current` must be `@@DEPLOY_BRANCH@@`. If not, tell the user to merge into
     `@@DEPLOY_BRANCH@@` first — do not proceed.
   - `git status --short` — warn if dirty (uncommitted work won't be deployed).
   - **Commits to ship:** `git log @@DEPLOY_REMOTE@@/@@DEPLOY_BRANCH@@..@@DEPLOY_BRANCH@@ --oneline`.
     Empty → tell the user there's nothing to deploy and stop.

2. **Confirm (prod, downtime-causing — pause for user OK unless pre-authorized in the prompt).**
   Print:
   - Commits to ship (from step 1, count + one-liner each).
   - Change type: code/runtime · config · docs · mix (`git diff @@DEPLOY_REMOTE@@/@@DEPLOY_BRANCH@@..@@DEPLOY_BRANCH@@ --stat`).
   - Impact: rebuild + restart `@@DEPLOY_SERVICE@@` → short downtime on that service only.
   Wait for explicit user OK before proceeding, unless the user's request already pre-authorized
   an end-to-end run.

3. **Pre-deploy snapshot** (so rollback + multi-service verify have a baseline):
   ```bash
   ssh @@DEPLOY_SSH_HOST@@ 'echo "=== services ==="; docker ps --format "{{.Names}}\t{{.Status}}"; \
     echo "=== disk ==="; df -h /; docker system df; \
     echo "=== rollback ref ==="; docker inspect --format "{{.Image}}" @@DEPLOY_SERVICE@@'
   ```
   Record: full `docker ps` (every service), disk %, and the rollback image ref (current image id of
   `@@DEPLOY_SERVICE@@`). Disk > ~80% → suggest running `/production-cleanup` first.

4. **Push + deploy.**
   ```bash
   git push @@DEPLOY_REMOTE@@ @@DEPLOY_BRANCH@@
   ssh @@DEPLOY_SSH_HOST@@ 'cd @@DEPLOY_PATH@@ && (bash bootstrap.sh || (git pull @@DEPLOY_REMOTE@@ @@DEPLOY_BRANCH@@ && docker compose up -d --build @@DEPLOY_SERVICE@@))'
   ```
   Use whichever exists on the host — a `bootstrap.sh` (pull + rebuild + up in place) if the repo has
   one, else `git pull` + `docker compose up -d --build @@DEPLOY_SERVICE@@` directly. Either way this
   only touches `@@DEPLOY_SERVICE@@`; named volumes are preserved.

5. **Verify target.**
   ```bash
   ssh @@DEPLOY_SSH_HOST@@ '@@DEPLOY_HEALTHCHECK@@'
   ```
   Expect a healthy/200 result.

6. **Verify multi-service (regression-spill check).** Re-run `docker ps` on the host and diff against
   the step-3 snapshot — every OTHER service must still be `Up`/healthy with the same container id
   (not recreated). Any neighbor regressed or restarted → warn loudly, this is exactly the failure
   mode this command exists to catch.

7. **Fail → auto-rollback.** If step 5's healthcheck fails:
   ```bash
   ssh @@DEPLOY_SSH_HOST@@ 'docker service update --image <rollback-ref> @@DEPLOY_SERVICE@@ || docker compose up -d --no-build @@DEPLOY_SERVICE@@'
   ```
   `<rollback-ref>` = the image id recorded in step 3. Re-run step 5's healthcheck; report **FAIL +
   rolled back** — do not leave the host half-deployed.

8. **Report.** Commits shipped · disk before/after · state of ALL services (target + neighbors,
   before/after).

## Guardrails

- The environment's permission layer still gates SSH/deploy Bash calls at runtime — if a call is
  denied or the host is unreachable, fall back to printing the host commands for the user to run
  manually rather than forcing it.
- Never wipe data — no `down -v`, no `docker volume rm`, no `rm -rf`, no `--volumes` prune.
- Push only to `@@DEPLOY_REMOTE@@`.
- Do not touch any service other than `@@DEPLOY_SERVICE@@`.
