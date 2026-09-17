---
name: force-snapshot
description: Squash all git history into a single commit to permanently cut off leaked secrets from history. Destructive and irreversible once force-pushed — every collaborator must re-clone. Use only when the user explicitly says "force snapshot", "squash history", "xoá lịch sử git", "reset history vì leak", or runs /force-snapshot.
user-invocable: true
---

# force-snapshot — squash entire history into one commit (destructive)

This is the nuclear option: it discards every commit and replaces the whole
repo history with a single snapshot of the current working tree. Only reach
for it when the leak is spread across many old commits and a targeted rewrite
(`git filter-repo`/BFG on just the leaked path) isn't enough. Never run this
without the user explicitly asking for it in this conversation.

## 1. Confirm intent

Ask the user to confirm, and mention the lighter alternative: if the leak is
confined to one file/pattern, `git filter-repo --path <file> --invert-paths`
(or BFG) removes just that from history and is far less disruptive. Proceed
with the full squash only if the user still wants it after hearing that.

Also confirm: which branch, and whether they've already rotated/revoked the
leaked secret. Squashing history does not undo exposure that's already been
scraped, cached, or forked by GitHub or anyone who pulled — rotation is the
actual fix; this command only stops the leak from being visible going
forward.

## 2. Pre-flight

- `git status` — must be clean. Uncommitted changes → ask the user to commit
  or stash (`git stash push -u`) first; do not silently discard anything.
- Refuse on protected branches (see project's git-workflow rule: `main`,
  `stable`, `prod`, or whatever the repo marks protected) unless the user
  explicitly names that branch as the target. Squashing a protected branch's
  history is a much bigger blast radius — flag this clearly before continuing.
- Note current branch name and remote (`git remote -v`) for later steps.

## 3. Backup before rewriting

Non-negotiable safety net — create it before touching anything:

```bash
git branch backup/pre-force-snapshot-$(date +%Y%m%d%H%M%S)
```

Tell the user this backup branch exists locally and won't be pushed; it's
their rollback path if the squash goes wrong.

## 4. Squash via orphan branch

```bash
git checkout --orphan _force-snapshot-tmp
git add -A
git commit -m "<message — ask user, default: 'chore: squash history (force-snapshot)'>"
git branch -D <original-branch>
git branch -m <original-branch>
```

## 5. Re-check the new single commit for leaks

Squashing removes *history* but the leaked secret may still be sitting in the
current working tree. Run the audit-git-leak skill (gitleaks + sensitive-content
scan) against this new one-commit state before anything is pushed. Any finding
→ STOP, fix it in the working tree, amend the snapshot commit, re-scan.

## 6. Force-push — explicit confirmation required

This step rewrites remote history for everyone. State clearly to the user,
in plain language, before running it:

- Exact remote + branch this will force-push to.
- That every collaborator's local clone will diverge and need `git fetch` +
  reset (or a fresh clone) afterward.
- That old commits become unreachable from the default refs but may still
  exist in GitHub's internal storage/cache for a period — rotation of the
  leaked secret is still required regardless of this push.

Only after the user gives explicit confirmation (not a prior blanket
approval — ask again for this specific push):

```bash
git push --force origin <branch>
```

## 7. Report

Summarize: backup branch name (kept for now), commit squashed to, whether the
leak scan in step 5 was clean, and remind the user to (a) tell collaborators
to re-clone or hard-reset, (b) rotate the originally leaked credential if not
already done, (c) delete the local backup branch once they've confirmed the
remote state is correct.
