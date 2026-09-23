# Harness research — sources, findings, improvement directions

Snapshot from the design phase before `feat: production-ready harness template`
(commit `9ffd54b`). Two read-only research agents ran in parallel
(`model: fable`, WebSearch/WebFetch only) on 2026-09-17; findings below are
their synthesized output, not re-verified against current upstream state —
treat repo/star-count facts as a point-in-time snapshot.

## Research sources

**Agent 1 — community harness/template ecosystem** (~850-word synthesis,
19 tool calls, 150s). Scope: survey GitHub community "harness template" repos
(rules+hooks+commands+agents+skills+settings bundles) to find what a
state-of-the-art template contained in late 2026.

**Agent 2 — official Anthropic guidance** (14 tool calls, 230s). Scope:
docs.claude.com/code.claude.com, anthropic.com/engineering, anthropics/*
GitHub orgs — authoritative surface list, hook event catalogue, plugin
mechanics, settings precedence, best practices.

## What was referenced

### From community survey (Agent 1)

- Plugins (`.claude-plugin/marketplace.json`) are the 2026 default
  distribution mechanism, vs this repo's `install.sh` overwrite-sync model.
- `disler/claude-code-hooks-mastery` — exit-code (0 advisory / 2 block) +
  structured JSON output (`decision`, `reason`, `suppressOutput`); per-event
  JSONL logging; builder/validator (generator≠verifier) split.
- `davila7/claude-code-templates` — harness-wide doctor/health-check command
  (this repo only had `doctor-memory`, scoped to memory).
- `affaan-m/everything-claude-code` — AgentShield: security-scan the harness
  itself (hooks/prompts/MCP configs as attack surface); manifest-driven
  installer tracking state to skip duplicate installs.
- `wshobson/agents` — multi-harness compile from one Markdown source;
  plugin-eval quality scoring before install.
- `steipete/agent-rules` — global vs project rules split (same shape as this
  repo's `rules/common` vs `rules/project`).
- Checklist of what "complete" harnesses share: all 5 surfaces + deny lists,
  exit-2 blocking hooks, SessionStart context injection, modular/lazy rules,
  generator≠verifier pairs, statusline reading session state, JSONL event
  logging, versioned distribution, security gates.
- Assessment: this repo was already ahead on orchestration enforcement
  (task-graph state machine, interface-lock gates, verdict-aware merge
  blocking); behind on packaging, hook testing, typed hooks, self-diagnostics.

### From official guidance survey (Agent 2)

- Skills are now the *preferred* replacement for commands (commands remain
  "legacy, still supported") — frontmatter incl. `disable-model-invocation`,
  `user-invocable`, `allowed-tools`, `paths`.
- Hook event catalogue grew to 33 events (was ~13); JSON output fields
  (`systemMessage`, `additionalContext`, `hookSpecificOutput`);
  `${CLAUDE_PROJECT_DIR}`/`${CLAUDE_PLUGIN_ROOT}` placeholders; `args`
  exec-form recommended over shell string for injection safety.
- Plugins can bundle skills/commands/agents/hooks/`.mcp.json`/`bin/` — but
  **cannot** carry CLAUDE.md content, `.claude/rules/`, or permission deny
  rules. Those must stay as repo files or managed settings regardless of
  plugin adoption — confirms Decision #1 (installer stays canonical).
- Settings precedence: managed > `--settings` CLI > `settings.local.json` >
  `settings.json` > `~/.claude/settings.json`; list keys merge, scalar keys
  (`fallbackModel` etc.) take highest source.
- Best practices: CLAUDE.md advisory only, hooks are the enforcement layer;
  give Claude a runnable check; generator≠evaluator; skills over commands for
  new work with `disable-model-invocation: true` on destructive ones.

## Improvement directions

**Applied** (shipped in `9ffd54b`/`8dccf30`/`59412a1`):
- Legacy commands → skills migration with `disable-model-invocation: true`
  gates on destructive workflows (Agent 2's skills-over-commands guidance;
  Decision #3).
- `harness-doctor`-equivalent diagnostics (`scripts/delegate/doctor.sh`,
  `test/doctor.bats`) — direct response to the davila7 doctor-command gap.
- Real `HARNESS_DRY_RUN=1` (zero-mutation) + idempotent confirmation-gated
  uninstall + manifest-tracked ownership (sync/preserve/CLAUDE.md-markers/
  settings) — echoes the manifest-driven-installer idea from
  everything-claude-code, adapted to this repo's overwrite-sync model rather
  than switching to plugins.
- Kept installer canonical instead of migrating to a plugin, per Decision #1
  — directly justified by Agent 2's finding that plugins cannot carry
  CLAUDE.md/rules/deny-list content, which are load-bearing here.
- `sync-template.md` excluded from downstream installs (Decision #9).

**Deferred / not implemented** (candidates for future work, not started):
- Plugin-marketplace packaging as an *additional* optional distribution
  surface (Decision #2 allows non-duplicating plugin metadata; not built —
  README documents this as a conscious install.sh-vs-plugin tradeoff, not an
  oversight).
- Structured JSON hook output (`decision`/`reason`/`suppressOutput`) —
  current hooks still use exit-code-only (0/2); Decision #10 explicitly
  scoped this out unless tests prove no stderr-semantics regression.
- Harness self-audit / AgentShield-style scan of hooks+prompts+MCP configs as
  attack surface — no equivalent exists yet.
- Cross-harness compile (one Markdown source → Claude/Codex/Cursor artifacts)
  — out of scope, this repo is Claude-Code-only by design.
- Continuous-learning "instincts" (confidence-scored pattern extraction from
  sessions re-injected as context) — no equivalent; auto-memory system here
  is user-turn-triggered, not autonomous pattern mining.
- Typed/TypeScript hooks — hooks remain bash, per repo convention.
