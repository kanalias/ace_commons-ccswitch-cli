---
name: dep-ladder-check
description: Walk the build-vs-buy ladder before adding a new dependency or writing non-trivial new code. Use before running npm install / pip install / go get / cargo add / gem install / composer require, before adding a new library dependency, or before writing a non-trivial new abstraction/helper.
user-invocable: true
---

# dep-ladder-check — build-vs-buy ladder before adding code or a dependency

Stop at the first rung that solves the problem. Don't skip ahead to "write a
library" or "add a dependency" without checking the cheaper rungs first.

## 1. Does this need to exist? (YAGNI)

Is this solving a real, current problem, or a hypothetical future one? If the
need is speculative ("we might need this later"), stop here — don't build it.

## 2. Stdlib check

Does the language's standard library already do this?

- **Node:** `fs`, `path`, `crypto`, `structuredClone`, `AbortController`,
  `Array.prototype` methods (`flatMap`, `group` via `Object.groupBy` in newer
  runtimes), `util.parseArgs`. Check the target Node version — a "need a
  library" assumption is often stale once the runtime added it natively.
- **Python:** `itertools`, `functools`, `pathlib`, `dataclasses`, `enum`,
  `contextlib`, `json`, `re`.
- **Go:** stdlib usually suffices — run `go doc <pkg>` before reaching for a
  third-party module.
- **Ruby:** stdlib (`Set`, `Comparable`, `Struct`, `ostruct`) before a gem.

## 3. Native platform feature

Prefer a platform primitive over an application-level library:

- CSS instead of a JS library — flexbox/grid layout, `:has()`, container
  queries, `prefers-color-scheme`.
- DB constraint instead of app-level validation — `UNIQUE`, `CHECK`, `FOREIGN
  KEY ... ON DELETE`.
- OS/runtime feature instead of a library — `cron`/`launchd` instead of a
  scheduler package, `flock` instead of a file-locking library.

## 4. Already-installed dependency

Before adding a new package, check whether an existing direct dependency
already exposes this capability:

- npm/pnpm/yarn → `dependencies`/`devDependencies` in `package.json`
- Python → deps in `requirements.txt` or `pyproject.toml`
- Go → `require` block in `go.mod`
- Rust → `[dependencies]` in `Cargo.toml`
- Ruby → `Gemfile`

## 5. One-liner

Can this be a single expression or a small function instead of a library?
Debounce is ~6 lines, slugify is a regex, deep clone is `structuredClone`.
If the whole point of the library is one function, inline that function.

## 6. Minimal custom code

Only if none of the above apply: write the smallest correct implementation.
Don't skip edge cases or error handling a library would have handled at trust
boundaries (empty input, encoding, concurrent access).

## When a new dependency IS justified

The ladder above is for plumbing, not for correctness-critical or
security-critical logic. Use an established library for these — do not treat
them as one-liner candidates, even if a naive version looks short:

- Cryptography, hashing, random token generation
- JWT signing/verification
- HTML/SQL sanitization and injection-safe query building
- Date/timezone math (DST, leap seconds, locale-aware parsing)
- Markdown/HTML/YAML parsing
- Password hashing (bcrypt/argon2/scrypt — never hand-rolled)

## Flagging existing violations

When reviewing code, if you find a dependency was added for something a
stdlib call or a one-liner would have solved, flag it and suggest removal —
do not remove it automatically. Removing a dependency can break other call
sites; ask the user first.
