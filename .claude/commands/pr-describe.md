---
name: pr-describe
description: Draft a PR title and body from the commits and diff against the base branch, and optionally create/update it with gh. Use when the user says "write PR description", "generate pull request body", or runs /pr-describe.
user-invocable: true
---

# pr-describe — draft a PR title + body from commits/diff

## 1. Determine the base branch

Try `git symbolic-ref refs/remotes/origin/HEAD` and take the basename. If
that's not set, ask the user which branch this PR targets — do not assume
`main` vs `master` vs a release branch.

## 2. Gather the change set

Run:

- `git log <base>..HEAD --oneline` — the commits this PR introduces
- `git diff <base>...HEAD --stat` — files touched and how much

If there are no commits ahead of base, STOP and tell the user there's nothing
to describe yet.

## 3. Draft title + body

**Title** — imperative mood, derived from the commits or branch name (strip
prefixes like `feat/`), ≤70 chars.

**Body**, in this structure:

- **Summary** — 1-3 sentences: what changed and why, in plain language.
- **Changes** — bullets grouped by area/module touched (use the diff --stat
  output to identify areas, not a raw commit-by-commit dump).
- **Test plan** — reflect only tests that actually exist in the diff or repo
  (new/updated test files, or a command the user can run). Do NOT claim tests
  were run or passed unless you've actually run them in this session — if no
  tests exist for the change, say so plainly instead of inventing a plan.
- **Notes/risks** — anything reviewers should know: breaking changes,
  follow-up work, things intentionally left out of scope.

## 4. Create or update the PR

Check whether `gh` is installed and authenticated (`gh auth status`).

- **`gh` available:** ask the user whether to create a new PR
  (`gh pr create --title ... --body ...`) or update an existing one
  (`gh pr edit <number> --body ...`) — creating or editing a PR is
  outward-facing, so get explicit confirmation before running either command.
  Never push commits or force-push as part of this command.
- **`gh` unavailable:** print the drafted title + body as markdown for the
  user to copy into their PR manually. Don't attempt any other tool to open
  a PR on their behalf.
