---
description: Run smoke tests, gitleaks, and a sensitive-content scan; only push if all three pass
---

Run this exact pipeline, in order, stopping at the first failure. Do not skip a
step or proceed past a failure. Report each step's result to the user as it
completes.

## 1. Smoke test

Run: `bats test/*.bats`

If any test fails (non-zero exit), STOP. Report the failing test name(s) and
do not proceed to step 2. Do not attempt to fix and retry automatically —
surface the failure and ask the user how to proceed.

## 2. gitleaks scan

Run: `gitleaks detect --source "$(git rev-parse --show-toplevel)" --redact -v`

If gitleaks is not installed, STOP and tell the user to run
`brew install gitleaks` (or their platform's equivalent) — do not silently skip
this step for a push command (unlike the advisory pre-push hook, this command
should treat a missing scanner as a hard stop, since the user explicitly asked
for a gated push).

If gitleaks finds any leak, STOP. Show the redacted finding(s) and do not
proceed. Do not use `GITLEAKS_SKIP=1` on behalf of the user — that bypass is
their call to make manually, not something this command decides.

## 3. Sensitive-content scan

Run `git status` and `git diff --stat` (against the upstream/main branch, or
`HEAD` if there are uncommitted changes) to see everything about to be pushed.
Then read through the actual changed files and check for:

- Real API keys, tokens, or credentials (not placeholders like
  `<your-9router-key>`)
- Hardcoded internal URLs, hostnames, or infra details not already present
  elsewhere in the repo
- Personal information (emails, names) that isn't already public in the repo's
  git history
- Any file that looks like it was accidentally staged (e.g. `.env`,
  `*.bak`, credentials files)

This is a judgment-based review on top of gitleaks (gitleaks catches known
secret patterns; this step catches things like internal-only URLs or accidental
file inclusion that aren't classic "secrets"). If you find something
concerning, STOP and describe it — do not decide unilaterally that it's fine.

## 4. Push

Only if steps 1-3 all passed: show the user exactly what will be pushed
(`git status`, current branch, remote) and ask for explicit confirmation
before running `git push`. Never force-push as part of this command unless the
user's request in this conversation explicitly asked for a force push.
