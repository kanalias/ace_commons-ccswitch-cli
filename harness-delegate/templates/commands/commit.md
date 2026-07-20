---
name: commit
description: Stage and commit changes to local git only, no push. Use when user says "commit", "commit local", "commit this", or runs /commit.
user-invocable: true
---

# commit — local git commit, no push

1. `git status` + `git diff` (staged and unstaged) + `git log --oneline -5` to see what's changing and match commit style.
2. Stage relevant files by name (never `-A`/`.` blind — check for secrets/junk first).
3. Write a short commit message matching repo's existing style (see recent log). No lengthy body unless changes need it.
4. Run `git commit -m "..."`. Do not push.
5. Report result in one line: commit hash + subject. No further explanation.

Never force, amend, or skip hooks. If commit fails (hook rejection), fix root cause and retry — don't `--no-verify`.
