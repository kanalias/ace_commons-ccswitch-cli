---
name: production-deploy
description: Safe in-place prod deploy for a multi-service host — pull + rebuild + up the TARGET service only, snapshot before / verify all services after, auto-rollback on healthcheck fail. Dùng khi user nói "deploy prod", "đẩy lên production", hoặc chạy /production-deploy.
user-invocable: true
---

# /production-deploy — Safe in-place production deploy

Deploy `<service-name>` on `<deploy-ssh-host>` by pulling + rebuilding + `up`-ing that ONE
service in place. The host runs multiple services — one service dying (bad image, bad healthcheck)
must never take down its neighbors. This command snapshots state before, verifies every service
(target + neighbors) after, and auto-rolls-back the target on healthcheck failure.

> ⛔ **HARD RULES — never destructive:**
> - Deploy is always pull + rebuild + `up` **in place**. NEVER `down -v`, `docker volume rm`,
>   `rm -rf`, `docker system prune --volumes`, or stop the whole host.
> - **Service isolation** — only touch `<service-name>`. Other services/containers on the host
>   must not be restarted, recreated, or lose volumes.
> - Prune (if needed for disk) = build-cache + dangling images ONLY. No `-a`, no `--volumes`.

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
     current repo/root/origin is `<repo identity>` — not running deploy. No override.
   - If any config used by this command is still placeholder-shaped (`<...>`) — `<deploy-ssh-host>`, `<service-name>`, `<remote-repo-path>`, `<healthcheck-cmd>` — STOP;
     deploy config is incomplete (re-run install.sh with HARNESS_DEPLOY_* env vars).

1. **Verify branch + working tree.**
   - `git branch --show-current` must be `main`. If not, tell the user to merge into
     `main` first — do not proceed.
   - `git status --short` — warn if dirty (uncommitted work won't be deployed).
   - **Commits to ship:** `git log origin/main..main --oneline`.
     Empty → tell the user there's nothing to deploy and stop.

2. **Confirm (prod, downtime-causing — pause for user OK unless pre-authorized in the prompt).**
   Print:
   - Commits to ship (from step 1, count + one-liner each).
   - Change type: code/runtime · config · docs · mix (`git diff origin/main..main --stat`).
   - Impact: rebuild + restart `<service-name>` → short downtime on that service only.
   Wait for explicit user OK before proceeding, unless the user's request already pre-authorized
   an end-to-end run.

3. **Pre-deploy snapshot** (so rollback + multi-service verify have a baseline):
   ```bash
   ssh <deploy-ssh-host> 'echo "=== services ==="; docker ps --format "{{.Names}}\t{{.Status}}"; \
     echo "=== disk ==="; df -h /; docker system df; \
     echo "=== rollback ref ==="; docker inspect --format "{{.Image}}" <service-name>'
   ```
   Record: full `docker ps` (every service), disk %, and the rollback image ref (current image id of
   `<service-name>`). Disk > ~80% → suggest running `/production-cleanup` first.

4. **Push + deploy.**
   ```bash
   git push origin main
   ssh <deploy-ssh-host> 'cd <remote-repo-path> && (bash bootstrap.sh || (git pull origin main && docker compose up -d --build <service-name>))'
   ```
   Use whichever exists on the host — a `bootstrap.sh` (pull + rebuild + up in place) if the repo has
   one, else `git pull` + `docker compose up -d --build <service-name>` directly. Either way this
   only touches `<service-name>`; named volumes are preserved.

5. **Verify target.**
   ```bash
   ssh <deploy-ssh-host> '<healthcheck-cmd>'
   ```
   Expect a healthy/200 result.

6. **Verify multi-service (regression-spill check).** Re-run `docker ps` on the host and diff against
   the step-3 snapshot — every OTHER service must still be `Up`/healthy with the same container id
   (not recreated). Any neighbor regressed or restarted → warn loudly, this is exactly the failure
   mode this command exists to catch.

7. **Fail → auto-rollback.** If step 5's healthcheck fails:
   ```bash
   ssh <deploy-ssh-host> 'docker service update --image <rollback-ref> <service-name> || docker compose up -d --no-build <service-name>'
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
- Push only to `origin`.
- Do not touch any service other than `<service-name>`.
