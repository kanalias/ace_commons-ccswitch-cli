---
description: Run tests, gitleaks, sensitive-content scan; only push if all three pass
---

Run this exact pipeline, in order, stopping at the first failure. Do not skip a
step or proceed past a failure. Report each step's result to the user as you
complete it.

## 1. Tests

First detect the project's test command by inspecting the repo (in this order,
stop at the first match):

- `test/*.bats` exists → `bats test/*.bats`
- `package.json` has a `scripts.test` field → `npm test`
- `pyproject.toml`, `pytest.ini`, or a `tests/` dir → `pytest`
- `go.mod` exists → `go test ./...`
- `Cargo.toml` exists → `cargo test`
- none of the above → do NOT guess. Check the README / CI config for the test
  command, or ask the user. Do not skip this step silently.

Run the detected command. If any test fails (non-zero exit), STOP. Report the
failing test name(s) and do not proceed to step 2. Do not attempt a fix or
retry automatically — surface the failure and ask the user how to proceed.

## 2. gitleaks scan

Run: `gitleaks detect --source "$(git rev-parse --show-toplevel)" --redact -v`

If gitleaks is not installed, STOP and tell the user to install it — do not
silently skip. Suggest the command for their platform:

- macOS: `brew install gitleaks`
- Linux: distro package manager (`apt install gitleaks`, `pacman -S gitleaks`, …)
- Windows: `scoop install gitleaks` or `choco install gitleaks`
- any OS with Go: `go install github.com/gitleaks/gitleaks/v8@latest`

(Unlike an advisory pre-push hook, this command should treat a missing scanner
as a hard stop, since the user explicitly asked for a gated push.)

If gitleaks finds any leak, STOP. Show the redacted finding(s) and do not
proceed. Do not use `GITLEAKS_SKIP=1` on behalf of the user — that bypass is
a call they make manually, not something the command decides.

## 3. Sensitive-content scan

Run `git status` and `git diff --stat` (against the upstream/main branch, or
`HEAD` if there are uncommitted changes) to see everything about to be pushed.
Then read through the actual changed files and check for:

- Real API keys, tokens, credentials (not placeholders like `<your-api-key>`
  or `sk-...`)
- Hardcoded internal URLs, hostnames, or infra details not already present
  elsewhere in the repo
- Personal information (emails, names) that isn't already public in the repo's
  git history
- Any file that looks accidentally staged (e.g. `.env`, `*.bak`, editor swap
  files, credential dumps)

This is a judgment step beyond what gitleaks' regex patterns catch — it catches
things like internal-only URLs and accidental file inclusion that aren't classic
"secrets". If you find something concerning, STOP and describe it — do not
decide unilaterally that it's fine.

## 4. Push

Only if steps 1-3 all passed: show the user exactly what will be pushed
(`git status`, current branch, remote) and ask for explicit confirmation
before running `git push`. Never force-push as part of this command unless the
user's request in this conversation explicitly asked for a force push.
