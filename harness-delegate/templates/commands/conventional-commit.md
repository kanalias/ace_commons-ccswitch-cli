---
name: conventional-commit
description: Draft a Conventional Commit message from the staged diff and confirm before committing. Use when the user says "gen commit message", "write a conventional commit", "draft a commit message for me", or runs /conventional-commit.
user-invocable: true
---

# conventional-commit — draft a Conventional Commit message from staged changes

## 1. Inspect the staged diff

Run `git diff --cached --stat` and `git diff --cached`.

If nothing is staged, STOP. Tell the user there's nothing staged and ask
whether to stage everything (`git add -A`) or specific files — do not guess
what they meant to commit. Do not stage anything without their answer.

## 2. Infer the commit type

Pick the type that best matches the dominant change in the diff:

- **feat** — new capability or user-facing behavior added
- **fix** — corrects a bug or wrong behavior
- **refactor** — restructures code with no behavior change
- **chore** — maintenance (deps, config, tooling) with no source/behavior change
- **docs** — documentation only (`*.md`, comments, README)
- **test** — test files only, no production code change
- **style** — formatting/whitespace/lint only, no logic change
- **perf** — performance improvement, same behavior
- **build** — build system or dependency manifest changes
- **ci** — CI/CD pipeline config changes

If the diff spans multiple types, pick the type of the primary change and
mention the rest in the body — don't invent a combined type.

## 3. Infer an optional scope

Look at the dominant top-level directory or module touched by the diff (e.g.
`auth`, `api`, `cli`). If changes are spread across unrelated areas with no
clear common scope, omit the scope rather than guessing one.

## 4. Format the message

`type(scope): subject` (scope optional) — imperative mood ("add", not "added"
or "adds"), subject ≤72 chars, no trailing period.

Add a body only if it adds real information: `- ` bullets explaining *why*
the change was made, not a restatement of the diff. Check `git log --oneline -5`
first and match the repo's existing style (trailers, body usage, punctuation).
Do not add trailers the repo doesn't already use (e.g. `Signed-off-by`,
`Co-Authored-By`) unless its recent history shows the convention.

## 5. Confirm before committing

Show the drafted message to the user and ask for explicit confirmation before
running `git commit -m "..."`. Never commit without that confirmation, and
never edit the message into something the user didn't approve.
