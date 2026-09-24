# Project Guidelines

<!-- BEGIN HARNESS RULES (managed by install.sh — do not edit inside) -->
## Quick links — rules QUAN TRỌNG

- ⭐⭐⭐ [.claude/rules/common/vault-no-mcp.md](.claude/rules/common/vault-no-mcp.md) — **P0**: Vault CRUD KHÔNG qua MCP, Notion API direct
- ⭐⭐⭐ [.claude/rules/common/token-budget.md](.claude/rules/common/token-budget.md) — **P0**: context-window budget
- [.claude/rules/project/git-workflow.md](.claude/rules/project/git-workflow.md) — branching, working branch rule, protected-branch deploy confirm, worktree, cleanup
- [.claude/rules/common/feature-redflags.md](.claude/rules/common/feature-redflags.md) — safe minimal changes + RED FLAGS cognitive wedge
- Thêm/sửa rule → đọc [.claude/rules/common/rule-loading-policy.md](.claude/rules/common/rule-loading-policy.md) trước (rule mới mặc định LAZY `paths:`)
- Ghi memory type project → mirror vào [.claude/memory/](.claude/memory/) theo [.claude/rules/common/memory-mirror.md](.claude/rules/common/memory-mirror.md)
- ⭐⭐⭐ **Harness Architecture (P0)** — xem section dưới

## ⭐⭐⭐ Harness Architecture (P0 — đọc kỹ)

Project follows **Anthropic Claude Code "Harness Engineer"** pattern. Mọi feature mới
BẮT BUỘC route qua 1 trong **5 surfaces** dưới đây. KHÔNG add ad-hoc scripts ngoài surface.

| Surface | Path | Khi nào dùng |
|---|---|---|
| **Skill (slash)** | `.claude/skills/<name>/SKILL.md` (gọi `/<name>`, vd `/deploy`, `/test`) | Workflow lặp lại user gõ `/<name>` |
| **Hook** | `.claude/hooks/<name>.sh` + wire `.claude/settings.json` (vd `protect-backup.sh`, `session-start.sh`) | Auto-action khi event (Pre/Post/SessionStart/Stop/SubagentStop) |
| **Subagent** | `.claude/agents/<name>.md` (vd `smoke-tester`) | Persona isolated context |
| **MCP server** | `mcp-servers/<name>/` + `.mcp.json` ở root project | External tool / structured I/O |
| **Permission deny** | `.claude/settings.json` `permissions.deny` | Hard guardrail (push prod, rm backup, edit `secrets/`, edit `.env`) |

**Quy trình thêm feature:**

1. **Identify surface** từ bảng. Không match → STOP, hỏi user.
2. **Implement** theo pattern surface đó.
3. **Wire** (hook → `.claude/settings.json`).
4. **Document** trong commit message rõ surface nào đã thêm.

**Hook exit code policy:**

- `exit 0` — advisory (log/inject context)
- `exit 2` — **BLOCK** (abort tool, AI buộc phải sửa) — surface stderr
- khác — error

**Skip mechanism (user-only):** prompt chứa `SKIP_HOOKS` / `BYPASS_<HOOK>` / "ignore <hook> safety" → hook exit 0 + log audit.

**Native rules loading.** Claude Code tự động khám phá Markdown trong `.claude/rules/`: rule không có `paths:` được nạp luôn; rule có `paths:` chỉ nạp khi đọc file khớp glob. Rules cung cấp instructions, không phải executable hooks hay permission enforcement. Feature logic → 5 surfaces ở trên; governance → rules.

**Harness rules (bundled, self-contained).** Mọi session PHẢI đọc + tuân thủ trước khi action:
- [.claude/rules/common/](.claude/rules/common/) — invariant guardrails (general/ngôn ngữ, secret, vault, budget, orchestrator, delegate, git, red-flags, rule-loading, memory-mirror). Managed by harness install.sh: **overwrite** khi re-sync — KHÔNG sửa trực tiếp trong project (sửa upstream ở harness repo).
- [.claude/rules/project/](.claude/rules/project/) — rule riêng repo, LAZY trừ khi vượt gate P0-mọi-turn; install.sh **giữ nguyên** khi re-sync.
<!-- END HARNESS RULES -->

## Project rules — quick links (ngoài block harness)

- [.claude/rules/project/browser-mcp-profiles.md](.claude/rules/project/browser-mcp-profiles.md) — Cloak/Playwright qua MCP, profile `prj_xx_sv_yy` isolation tránh lock session, container resolve `BROWSER_PROFILES_DIR` → repo-root `./.browser-profiles/` (opt-in, Docker) → `~/.browser-profiles`, MCP per-project. LAZY.
