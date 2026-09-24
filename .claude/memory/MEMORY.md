# Memory index — ccswitch-cli-claude (project, git-tracked)

Nguồn: mirror 1 chiều từ auto-memory (`~/.claude/projects/<hash>/memory/`, loại `project`). Ghi mới → viết vào đây TRƯỚC, patch sang auto-memory SAU. Xoá → xoá ở auto-memory TRƯỚC, repo SAU. Xem [memory-mirror](../rules/common/memory-mirror.md).

- [ai-memory-kit](project_ai_memory_kit.md) — v4.2 business-only (37821a0), bundle ↔ Drive khớp, addons/+nut-bam/+.obsidian purge, P2 vá hết (gate cache, lock + SIGINT release), cài qua cai-dat.sh
- [Harness score](project-harness-score.md) — ~9.5/10 sau hygiene 2026-08-02; 0.5 còn lại là giới hạn platform, không fix từ repo
- [Orchestrator blackboard](project_orchestrator_blackboard.md) — blackboard plan file + SendMessage resume + brainstorm pass (ba975d9); harness/ (ex harness-delegate) KHÔNG phải nested repo, branch là main
- [Routing chain 2026-08](project_routing_chain_2026-08.md) — read-only sonnet-first, web-research fable→opus→sonnet→gemini, git-ops haiku/sonnet in-harness only; context windows verified
- [Task-graph upgrade](project-task-graph-upgrade.md) — task-graph v1 + graph-aware hard gates + /orchestrate skill + metrics JSONL (commit 31d5c82, 2026-08-03)
