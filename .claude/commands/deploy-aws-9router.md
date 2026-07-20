---
name: deploy-aws-9router
description: Install/refresh ccswitch on aws-prod and apply the 9router proxy host+key from .env.aws. Use for "deploy/cài ccswitch lên aws", "update aws-prod proxy key/host", or /deploy-aws-9router. Writes to PRODUCTION — needs confirmation.
user-invocable: true
---

# deploy-aws-9router — push ccswitch + 9router creds to aws-prod

## Facts

| Thing | Value |
|---|---|
| SSH alias | `aws-prod` |
| Repo path (server) | `/home/kane/ai-control/ccswitch-cli-claude` |
| Creds (local, gitignored) | `.env.aws` (repo root) — `proxy_host` + `proxy_key`, label "Ace Nexus prod" |
| Installer | `install-9router-proxy.sh` → `ai-proxy/setup.sh` |
| Writes to | `~/.claude/settings.json` + `~/.claude/profiles/{claude,codex,deepseek}.json` |
| User | `kane` (only user this deploys to — see memory `reference_env_aws.md`) |

**Gotcha:** `setup.sh` only reads a file literally named `.env` at repo root — never `.env.aws`.
Must `scp .env.aws → server:.env` before running the installer, or it silently no-ops.

## Safety rails

- Every write step is a **production** write. Confirm the plan with the user before step 1.
- Never print secrets. Transfer via `scp`, not echo. Mask any output with
  `sed -E 's/(proxy_key[[:space:]]*:[[:space:]]*).*/\1<redacted>/'`; mask JSON fields with
  `jq 'with_entries(if (.key|test("TOKEN|KEY|SECRET")) then .value="<redacted>" else . end)'`.
- If local `.env.aws` is missing or incomplete, stop and ask — don't prompt for the key inline.

## Steps (confirm with user first)

1. **Update server code:**
   `ssh aws-prod 'cd <repo> && git fetch origin && git merge --ff-only origin/main'`
   Stop if server has local changes (don't force).

2. **Copy creds:**
   `scp <local-repo>/.env.aws aws-prod:<repo>/.env`
   Verify both keys present (redacted) and host matches expectation.

3. **Run installer:**
   `ssh aws-prod 'cd <repo> && bash install-9router-proxy.sh' | sed -E 's/(proxy_key[[:space:]]*:[[:space:]]*).*/\1<redacted>/'`
   Expect: profiles applied, `claude` auto-activated, `ping OK (HTTP 200)`.

4. **Restart Claude Code on server** (new env only loads on fresh launch):
   ⚠ Never bare `pkill -f claude` — it self-matches the ssh command AND kills the
   `claude-code-telegram` bot (must stay running). Use:

   ```bash
   ssh aws-prod 'pgrep -af "[c]laude" | grep -v claude-code-telegram > /tmp/cc.pids || true
     if [ -s /tmp/cc.pids ]; then awk "{print \$1}" /tmp/cc.pids | xargs -r kill; fi
     rm -f /tmp/cc.pids'
   ```

   If auto-mode blocks this (shared prod host), hand the restart to the user instead.

## Verify (after step 4)

```bash
ssh aws-prod 'cd <repo>
  jq ".env | with_entries(if (.key|test(\"TOKEN|KEY|SECRET\")) then .value=\"<redacted>\" else . end)" ~/.claude/settings.json
  for p in claude codex deepseek; do
    f=~/.claude/profiles/$p.json
    echo "$p: url=$(jq -r .ANTHROPIC_BASE_URL $f) token_len=$(jq -r ".ANTHROPIC_AUTH_TOKEN|length" $f)"
  done
  bash ~/.claude/ccswitch.sh status 2>&1 | grep -E "settings.json|claude:|codex:|deepseek:|subscription:"'
```
Pass: base URL matches `.env.aws` host, all 3 profiles have a real key, all `200 OK`.

## Model ping (last, proves each model id actually resolves)

```bash
ssh aws-prod 'S=~/.claude/settings.json
  url=$(jq -r .env.ANTHROPIC_BASE_URL "$S"); tok=$(jq -r .env.ANTHROPIC_AUTH_TOKEN "$S")
  for m in $(jq -r ".env | to_entries[] | select(.key|test(\"DEFAULT_.*_MODEL\")) | .value" "$S"); do
    code=$(curl -sS -o /tmp/r.json -w "%{http_code}" "$url/messages" \
      -H "x-api-key: $tok" -H "authorization: Bearer $tok" \
      -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
      -d "{\"model\":\"$m\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with just: OK\"}]}")
    reply=$(jq -r "(.content[0].text // .error.message // \"?\")" /tmp/r.json | tr -d "\n" | cut -c1-60)
    printf "%-32s HTTP %s  reply=%s\n" "$m" "$code" "$reply"
  done
  rm -f /tmp/r.json'
```
Pass: every configured model returns `HTTP 200` with a non-error reply.

## Report to user

Confirm host applied (masked) + 3 profiles + ping result. Remind: env only loads after
restart (`.bak` files exist for rollback). If local HEAD is unpushed vs what's deployed,
mention it — don't push unprompted.
