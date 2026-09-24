---
name: task-graph-upgrade
description: "Orchestration level-up 2026-08-03 (commit 31d5c82): task-graph artifact v1 + graph-aware hard gates + skill /orchestrate + metrics JSONL"
metadata: 
  node_type: memory
  type: project
  originSessionId: ee7a5484-fe57-4e9c-ba5a-77d9d319ccb4
---

Nâng cấp orchestration 2026-08-03, commit `31d5c82` (13 files, template+live mirror đủ):

- **Task-graph v1** — `.claude/state/task-graph.md` (gitignored): header `status:`/`integration-verify:`/`integration-status:` + bảng `| id | subtask | persona | rw | locked | deps | wave | status | verify |`. Plan artifact survive compact/session.
- **Hard gates mới**: `pre-task-dispatch-gate.sh` block dispatch delegate-* khi graph tồn tại mà prompt thiếu marker `task-graph #<id>` / id lạ / row W chưa `locked=yes` (interface-lock → enforce cứng). `pre-bash-gate.sh` block `git commit` main-agent khi `status: integrating` + `integration-status != pass`.
- **Skill `/orchestrate`** — quy trình 7 bước (analyze → lock → decompose+graph → dispatch wave → collect/review → integration verify → cleanup) + resume theo banner session-start. Wired vào install.sh.
- **Metrics**: `subagent-stop-record.sh` ghi `verdict=` vào ledger + JSONL `~/.cache/claude-code-<slug>/orchestration.jsonl` (ts, agent_id, type, verdict) — audit revise-rate định kỳ.
- **Revise = SendMessage** tới đúng agent cũ (giữ context), không spawn mới trừ đổi persona/review pass — đã bake vào rule + dùng thật trong chính lần nâng cấp này.
- Fable-main exception mở rộng: được Write `.claude/state/` (planning artifact).

Follow-up cùng ngày: `cc1b1ad` statusline segment 📊 (`.claude/statusline-orchestration.sh`, chain global statusline, icon map v1.1 hiển thị — file graph vẫn text thuần cho hook parse) + `4bd7fce` blackboard `plan-<slug>.md` cho M+ multi-agent WRITE, brainstorm READ-only pass, pointer-prompt (blackboard edits xuất hiện từ session song song — user xác nhận giữ, commit tách riêng).

Verify 2026-08-03 (sau 3 commit): E2E 8 nhóm test PASS toàn bộ (dispatch-gate 8 case, bash-gate 5, verdict record, session-start, statusline, installer idempotent 2 lượt, mirror 0 drift 0 leak, bats 256/256). Audit consistency ~70%: format v1 khớp 3 consumer ($5 rw/$6 locked/$9 status); gaps còn mở (chưa fix, user chưa quyết): (1) dual-artifact task-graph vs blackboard plan-<slug>.md chưa phân vai/lifecycle rõ — 2 state machine song song; (2) gate hook đọc cột theo index cứng, không validate header (reformat bảng = silent wrong-field); (3) graph cũ sót (fixed-path, không slug-check) có thể validate nhầm dispatch task mới; (4) ledger orphan sau khi graph xoá; planning-gate/fan-out vẫn behavioral-only (đã ghi nhận trong rule).

Xem [[orchestration-goal-speed-quality]], [[project-harness-score]].
