# Harness research — nguồn, phát hiện, hướng cải tiến

Snapshot từ giai đoạn thiết kế trước `feat: production-ready harness template`
(commit `9ffd54b`). Hai subagent research read-only chạy song song
(`model: fable`, chỉ dùng WebSearch/WebFetch) vào 2026-09-17; phát hiện dưới
đây là output đã tổng hợp của chúng, chưa re-verify lại với upstream hiện tại
— coi các fact về repo/star-count là snapshot tại 1 thời điểm.

## Nguồn research

**Agent 1 — community harness/template ecosystem** (tổng hợp ~850 từ,
19 tool call, 150s). Scope: khảo sát repo "harness template" cộng đồng trên
GitHub (bundle rules+hooks+commands+agents+skills+settings) để tìm
state-of-the-art template chứa gì vào cuối 2026.

**Agent 2 — official Anthropic guidance** (14 tool call, 230s). Scope:
docs.claude.com/code.claude.com, anthropic.com/engineering, anthropics/*
GitHub orgs — danh sách surface chính thức, catalogue hook event, cơ chế
plugin, thứ tự ưu tiên settings, best practices.

## Đã tham khảo gì

### Từ khảo sát cộng đồng (Agent 1)

- Plugins (`.claude-plugin/marketplace.json`) là cơ chế phân phối mặc định
  năm 2026, so với model `install.sh` overwrite-sync của repo này.
- `disler/claude-code-hooks-mastery` — exit-code (0 advisory / 2 block) +
  structured JSON output (`decision`, `reason`, `suppressOutput`); logging
  JSONL theo từng event; tách builder/validator (generator≠verifier).
- `davila7/claude-code-templates` — command doctor/health-check phủ toàn
  harness (repo này trước chỉ có `doctor-memory`, scope riêng memory).
- `affaan-m/everything-claude-code` — AgentShield: security-scan chính
  harness (hooks/prompts/MCP configs là attack surface); installer
  manifest-driven track state để skip cài trùng.
- `wshobson/agents` — compile multi-harness từ 1 nguồn Markdown; chấm điểm
  quality plugin-eval trước khi install.
- `steipete/agent-rules` — tách rule global vs project (cùng shape với
  `rules/common` vs `rules/project` của repo này).
- Checklist điểm chung của harness "complete": đủ 5 surface + deny list,
  hook block bằng exit-2, inject context ở SessionStart, rule modular/lazy,
  cặp generator≠verifier, statusline đọc session state, logging JSONL theo
  event, phân phối có version, security gate.
- Đánh giá: repo này đã đi trước về enforcement orchestration (state machine
  task-graph, interface-lock gate, block merge theo verdict); đi sau về
  packaging, test hook, hook có type, self-diagnostics.

### Từ khảo sát official guidance (Agent 2)

- Skills giờ là lựa chọn *ưu tiên* thay commands (commands vẫn "legacy,
  still supported") — frontmatter gồm `disable-model-invocation`,
  `user-invocable`, `allowed-tools`, `paths`.
- Catalogue hook event tăng lên 33 event (trước ~13); field JSON output
  (`systemMessage`, `additionalContext`, `hookSpecificOutput`); placeholder
  `${CLAUDE_PROJECT_DIR}`/`${CLAUDE_PLUGIN_ROOT}`; khuyến nghị `args`
  exec-form thay vì shell string để an toàn injection.
- Plugins bundle được skills/commands/agents/hooks/`.mcp.json`/`bin/` —
  nhưng **không** mang được nội dung CLAUDE.md, `.claude/rules/`, hay rule
  permission deny. Các thứ này phải ở lại dạng repo file hoặc managed
  settings dù có dùng plugin hay không — xác nhận Decision #1 (installer
  vẫn canonical).
- Thứ tự ưu tiên settings: managed > `--settings` CLI >
  `settings.local.json` > `settings.json` > `~/.claude/settings.json`; key
  dạng list thì merge, key scalar (`fallbackModel` v.v.) lấy theo source ưu
  tiên cao nhất.
- Best practices: CLAUDE.md chỉ advisory, hook mới là enforcement layer;
  đưa Claude 1 runnable check; generator≠evaluator; ưu tiên skills hơn
  commands cho việc mới, `disable-model-invocation: true` cho workflow
  destructive.

## Hướng cải tiến

**Đã áp dụng** (đã ship trong `9ffd54b`/`8dccf30`/`59412a1`):
- Migrate legacy commands → skills, gate `disable-model-invocation: true`
  cho workflow destructive (theo guidance skills-over-commands của Agent 2;
  Decision #3).
- Diagnostics tương đương `harness-doctor` (`scripts/delegate/doctor.sh`,
  `test/doctor.bats`) — phản hồi trực tiếp gap doctor-command của davila7.
- `HARNESS_DRY_RUN=1` thật (zero-mutation) + uninstall idempotent có
  confirmation-gate + ownership manifest-tracked (sync/preserve/CLAUDE.md-
  markers/settings) — echo lại ý tưởng manifest-driven-installer từ
  everything-claude-code, chỉnh cho hợp model overwrite-sync của repo này
  thay vì chuyển sang plugin.
- Giữ installer canonical thay vì migrate sang plugin, theo Decision #1 —
  được justify trực tiếp bởi phát hiện của Agent 2 rằng plugin không mang
  được nội dung CLAUDE.md/rules/deny-list, vốn load-bearing ở đây.
- `sync-template.md` bị loại khỏi downstream install (Decision #9).

**Deferred / chưa implement** (ứng viên cho việc tương lai, chưa bắt đầu):
- Đóng gói plugin-marketplace như 1 surface phân phối optional *thêm vào*
  (Decision #2 cho phép plugin metadata không duplicate; chưa build —
  README ghi rõ đây là tradeoff install.sh-vs-plugin có chủ đích, không
  phải bỏ sót).
- Structured JSON hook output (`decision`/`reason`/`suppressOutput`) — hook
  hiện tại vẫn dùng exit-code-only (0/2); Decision #10 loại rõ phần này ra
  khỏi scope trừ khi test chứng minh không regression stderr-semantics.
- Harness self-audit / scan kiểu AgentShield cho hooks+prompts+MCP configs
  như attack surface — chưa có tương đương.
- Compile cross-harness (1 nguồn Markdown → artifact Claude/Codex/Cursor) —
  out of scope, repo này thiết kế chỉ cho Claude Code.
- "Instincts" continuous-learning (trích pattern có confidence-score từ
  session, re-inject làm context) — chưa có tương đương; hệ thống
  auto-memory ở đây trigger theo user-turn, không tự động mining pattern.
- Hook có type/TypeScript — hook vẫn giữ bash, theo convention repo.
