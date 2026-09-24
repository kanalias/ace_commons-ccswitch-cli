---
name: orchestrator-blackboard-upgrade
description: "Orchestrator rule có blackboard plan file + SendMessage resume + brainstorm READ-only pass (commit ba975d9, 2026-08-03); harness (ex harness-delegate) KHÔNG còn là nested repo"
metadata: 
  node_type: memory
  type: project
  originSessionId: 82dba21d-b9c8-4283-b69c-782271aaf4de
---

Commit `ba975d9` (2026-08-03): orchestrator.md + resume-orchestration.md thêm 3 cơ chế mô phỏng shared context:
- Blackboard `.claude/state/plan-<slug>.md` BẮT BUỘC cho task M+ multi-agent WRITE (template chuẩn ở `/resume-orchestration` mục 0); xoá cùng ledger khi task xong.
- REVISE cùng mảnh → SendMessage agent cũ, không spawn mới; nhiều dòng ledger cùng agent_id = iterations, lấy dòng cuối.
- Brainstorm READ-only pass optional (XL/ambiguity cao), orchestrator một mình merge findings rồi mới lock interface.

**Topology quan trọng:** `harness/` (rename từ `harness-delegate/` 2026-08-03) KHÔNG phải nested git repo — `harness/.git` chỉ là dir leftover chứa hooks, không có HEAD/refs; toàn bộ track trong repo outer duy nhất (branch `main`, không phải `dev`). "Commit nested trước, outer sau" trong sync-template.md không còn áp dụng — 1 commit sequence duy nhất. Sync template→installed bằng `cp` (không chạy install.sh: self-install guard + commands mode keep-existing).

Liên quan: [[feedback_orchestration_goal_speed_quality]]
