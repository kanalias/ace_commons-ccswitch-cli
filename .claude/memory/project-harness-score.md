---
name: project-harness-score
description: Harness score ~9.5/10 sau vòng hygiene 2026-08-02; 0.5 còn lại là giới hạn platform Claude Code, không fix được từ repo
metadata:
  type: project
---

Harness đạt ~9.5/10 sau vòng hygiene 2026-08-02 (commit `27beca2`): ledger skip junk `agent_id=?` + TTL prune 48h, cache dir hygiene (stuck-window >7d, log rotate 512KB), jq-missing loud warning, doctor.sh section Hooks (wiring/orphan/syntax/template-drift token-aware).

**Why:** tránh session sau lặp lại audit từ đầu hoặc cố "đóng nốt 0.5" bằng complexity giả.

**How to apply:** 0.5 còn lại KHÔNG fix được từ phía repo — (1) hook không nhận model name trong payload nên ràng buộc Fable-main mãi là behavioral; (2) bash gate là string heuristic, threat model đã chấp nhận (chống lười, không chống adversary). Đề xuất "nâng lên 10" chạm 2 điểm này → từ chối, dẫn memory này. Baseline verify: `bats -j 10 test/*.bats` (256 pass) + `scripts/delegate/doctor.sh` (0 fail).
