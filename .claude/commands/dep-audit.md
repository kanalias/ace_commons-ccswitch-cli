---
name: dep-audit
description: Detect the project's package ecosystem and run a read-only vulnerability + outdated-dependency audit, then summarize findings. Use when the user says "audit dependencies", "check for vulnerable packages", "outdated deps", or runs /dep-audit.
user-invocable: true
---

# dep-audit — read-only vulnerability + outdated dependency audit

This command never upgrades anything. It only detects, runs, and summarizes.

## 1. Detect the ecosystem

Check the repo root, in this order, and stop at the first match:

- `pnpm-lock.yaml` → pnpm
- `yarn.lock` → yarn
- `package.json` (no pnpm/yarn lockfile) → npm
- `uv.lock` or `pyproject.toml` → uv/pip
- `requirements.txt` → pip
- `go.mod` → go
- `Cargo.toml` → cargo
- `Gemfile` → bundler
- `composer.json` → composer

If none match, do not guess — ask the user what ecosystem/tooling this
project uses.

## 2. Run the audit for the detected ecosystem

- **npm:** `npm audit` then `npm outdated`
- **pnpm:** `pnpm audit` then `pnpm outdated`
- **yarn:** `yarn npm audit` (Yarn Berry) or `yarn audit` (Yarn Classic), then
  `yarn outdated`
- **pip:** `pip-audit` if installed, else note it's missing (see step 3);
  then `pip list --outdated`
- **uv:** `uv pip list --outdated`, plus `pip-audit` if present in the
  environment
- **go:** `govulncheck ./...` if installed; then `go list -m -u all`
- **cargo:** `cargo audit` if installed; `cargo outdated` if installed
- **bundler:** `bundle audit`
- **composer:** `composer audit` then `composer outdated`

## 3. Missing tools

If a required tool (`pip-audit`, `govulncheck`, `cargo-audit`,
`cargo-outdated`, `bundle-audit`) isn't installed, tell the user exactly how
to install it (package manager command for their platform) and still run
whatever audits/outdated checks don't require it. Do not silently skip a
check without telling the user it didn't run.

## 4. Summarize

- Group vulnerabilities by severity (critical/high/moderate/low), naming the
  affected package and the fixed version if the tool reports one.
- List outdated packages as `current → latest`, flagging any that also have
  an open vulnerability.
- Recommend which upgrades look safe (patch/minor) vs. risky (major, likely
  breaking).

## 5. No auto-upgrade

This command is read-only. Never run an upgrade/install command
(`npm update`, `cargo update`, `pip install -U`, etc.) as part of this
audit — present the summary and ask the user before changing anything.
