# Claude Code harness template

`templates/` is the source of truth for the portable harness. `install.sh`
substitutes project values, copies selected surfaces into a target project, and
merges their wiring into `.claude/settings.json`. `VERSION` contains the harness
release version (semantic versioning), not the Claude Code version.

## Install, sync, preview, uninstall

Requirements: Bash and `jq`; Git for worktrees and Git hooks. Run from this
repository's root, using a separate target project (never install into `harness/`).

```bash
# Preview: zero writes, including no target-directory creation.
HARNESS_ROUTE_DIR=/path/to/project HARNESS_DRY_RUN=1 bash harness/install.sh

# Install or sync: the default action. Explicit noninteractive confirmation.
HARNESS_ROUTE_DIR=/path/to/project HARNESS_ASSUME_YES=1 bash harness/install.sh

# Preview removal, then remove only installer-owned, unchanged material.
HARNESS_ROUTE_DIR=/path/to/project HARNESS_DRY_RUN=1 bash harness/install.sh uninstall
HARNESS_ROUTE_DIR=/path/to/project HARNESS_ASSUME_YES=1 bash harness/install.sh uninstall
```

Redirecting stdin from `/dev/null` is **not** a dry run. Use `HARNESS_DRY_RUN=1`.
Review the plan before confirming writes. Configure `HARNESS_CORE_DIRS`,
`HARNESS_RISK_DIRS`, `HARNESS_PROJECT_SLUG`, `HARNESS_BRANCH`, and
`HARNESS_TEST_CMD` for the target; see the installer header for group switches.
Do not assume its defaults describe your repository or enable secret checks for
all sensitive directories automatically.

The lifecycle contract below is implemented by the installer; documentation
checks alone do not verify removal safety. Run installer lifecycle tests before
releasing changes to that implementation.

## Ownership and upgrades

The target's `.claude/` manifest records the schema and harness version, installed
sync paths with sha256 checksums, preserve paths, and exact settings ownership.
Keep that manifest: it is the ownership record, not a disposable runtime log.

- **Sync files:** template-owned surfaces are refreshed on install/sync. Common
  rules under `.claude/rules/common/` are managed; make reusable changes upstream
  in `templates/rules/common/`, not in installed copies. Back up local edits before
  syncing; uninstall's modified-file protection is not an upgrade merge strategy.
- **Preserve files:** existing project rules under `.claude/rules/project/` and
  `.claude/allowed-hosts.txt` remain project-owned. Templates seed missing files;
  sync does not replace existing customizations.
- **Shared configuration:** unrelated settings and text outside the managed
  `CLAUDE.md` block belong to the project. Harness settings ownership is exact,
  not ownership of the entire settings file or hooks event.
- **Uninstall:** remove only unchanged sync files whose recorded checksums match
  and exact owned settings/managed `CLAUDE.md` content. Preserve modified files,
  preserve-mode files, and unrelated user content. Do not replace this operation
  with recursive deletion of `.claude/` or `scripts/`.

A reinstall is a sync, not a reset of the target project. Review the installer
plan and diff after upgrades. Keep runtime state, secrets, and machine-specific
configuration out of distributable templates; `.DS_Store` is ignored and must not
be shipped.

## Native rules loading versus enforcement

Claude Code provides **native** discovery of Markdown rules recursively under
`.claude/rules/`. Rules without `paths:` load unconditionally; YAML `paths:` glob
lists scope rules to matching files. Path-scoped rules load when matching files
are read, not as an executable check on every tool invocation. Reference:
official Claude Code documentation, *How Claude remembers your project*, sections
*Organize rules with .claude/rules/* and *Path-specific rules*.

Instruction loading is not runtime enforcement. Rules describe governance;
feature execution still belongs to the five harness surfaces: slash commands,
hooks, subagents, MCP servers, and permission deny settings. Use a hook or
permission boundary when an operation must actually be blocked. Markdown links
are navigation, not the mechanism that makes native project rules discoverable.

## Optional extensions and limits

- Delegate wrappers need their corresponding external CLIs, credentials, and
  supported models configured separately. Installing templates does not install
  providers, grant quotas, or prove network access. Never embed credentials.
- Production deployment commands are opt-in (`HARNESS_GROUP_DEPLOY=Y`). Configure
  the host, service, remote path, branch, and health check before use. Installing
  a command is not approval to deploy and does not provision infrastructure.
- Git pre-push scanning requires Git and its scanner dependency; copying a hook
  does not install that dependency. Existing project hooks remain an ownership
  concern, not permission to replace unrelated automation.
- MCP servers, browser profiles, and third-party plugins require separate setup
  and permissions. This installer is not a plugin manager. The bundled
  `skill-superpowers` rule borrows methodology; it does not install that plugin.
- Workflow skills provide instructions, not a scheduler, service supervisor, or
  guarantee that every tool is available. Diagnostics are not remediation or
  authorization to modify production resources.

## Verify

```bash
bats test/harness-docs.bats
```

This focused suite checks release metadata, package hygiene, and documentation
contracts. Installer and hook test suites separately verify executable behavior.
