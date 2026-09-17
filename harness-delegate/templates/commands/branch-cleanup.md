---
name: branch-cleanup
description: Audit merged local branches and stale worktrees, then delete only what the user confirms. Use when the user says "clean up merged branches", "delete stale branches", "prune worktrees", or runs /branch-cleanup.
user-invocable: true
---

# branch-cleanup — audit + confirm-delete merged branches and stale worktrees

## 1. Determine the default branch

Run `git symbolic-ref refs/remotes/origin/HEAD` and take the basename (e.g.
`main`). If that fails (no remote tracking ref set), ask the user which
branch is the default — do not guess between `main`/`master`.

## 2. List merge candidates

Run `git branch --merged <default>` to list branches already merged into it.

For each candidate, check:

- **PROTECTED (HARD BLOCK, never offer to delete):** `main`, `master`,
  `stable`, `prod`, `develop`, `backup`, and whatever branch is currently
  checked out. Exclude these from the candidate list entirely.
- **Eligible prefixes:** `feat/`, `fix/`, `chore/`, `refactor/`, `hotfix/`.
  Branches outside these prefixes are merged but not auto-offered — list them
  separately as "merged, outside cleanup whitelist" and let the user decide.
- **Age guard:** skip (list as "too recent") any branch whose last commit is
  less than 24h old — check with `git log -1 --format=%cr <branch>`.
- Anything not actually merged (`git branch --merged` already filters this,
  but double check on ambiguous detached-HEAD setups) stays out of the
  deletable list.

## 3. List stale worktrees

Run `git worktree list`. Flag entries pointing at directories that no longer
exist or branches already deleted. Offer `git worktree prune` for these — this
only removes stale registrations, not directories with real content, so it's
low-risk, but still ask before running it.

## 4. Present candidates and confirm

Show three groups: (a) eligible-prefix branches safe to delete, (b) merged
branches outside the whitelist (info only, no deletion offered), (c) stale
worktree entries. Ask the user `[a]ll / [s]elect / [n]one` before deleting
anything in group (a). Never delete without this confirmation, and never
touch group (b) branches at all.

## 5. Delete confirmed branches

For each confirmed branch: `git branch -d <branch>` (safe delete only). If git
refuses because it's unmerged, STOP, report the branch, and do NOT force with
`-D` — that decision belongs to the user, not this command.

Then attempt remote cleanup, best-effort, `origin` only:
`git push origin --delete <branch>`. If that fails (branch already gone,
permission issue, etc.), log a warning and continue — don't fail the whole
run over one remote delete.

## 6. Report

List what was deleted (local + remote), what was skipped and why (age,
unmerged, outside whitelist), and any worktrees pruned.
