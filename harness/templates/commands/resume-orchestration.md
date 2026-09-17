---
name: resume-orchestration
description: Đọc ledger orchestration dở dang (.claude/state/orchestrator-ledger.md), tái tạo bảng phân rã, chỉ re-dispatch subtask failed/pending. Dùng khi user nói "resume orchestration", "tiếp tục task dở dang", hoặc chạy /resume-orchestration.
user-invocable: true
---

# resume-orchestration — resume orchestration ledger sau khi session bị cắt ngang

Pattern giống LangGraph checkpoint / Mastra suspend-resume: ledger ghi lại
subagent nào đã xong, orchestrator đọc lại để biết tiếp tục từ đâu thay vì
chạy lại toàn bộ từ đầu.

## 0. Plan file (blackboard)

Task M+ multi-agent WRITE ghi blackboard `.claude/state/plan-<slug>.md` lúc
dispatch (xem [[orchestrator]] Planning gate). Nếu file này tồn tại → dùng nó
làm nguồn **CONTEXT/contract** (bảng subtask + contract đã lock + decisions +
Questions) — **KHÔNG** dùng làm nguồn trạng thái. Trạng thái (status/wave/verdict)
sống DUY NHẤT ở `.claude/state/task-graph.md` (dual-artifact: xem [[orchestrator]]
mục "Task-graph artifact") — plan file không tự giữ máy trạng thái riêng nữa.
Ledger (`orchestrator-ledger.md`) chỉ để đối chiếu completion (mục 2 dưới).
Template chuẩn:

```markdown
# Plan: <slug>
(trạng thái xem .claude/state/task-graph.md — file này KHÔNG có field status riêng)
## Contract (LOCKED — subagent không tự sửa)
<signatures, types, ranh giới file/module>
## Edge cases (đã quyết)
## Decisions log
- [ts] <quyết định> — <lý do>
## Subtasks
| # | subtask | persona | agent_id | interface✅ | phụ thuộc | wave | verify cmd |
## Questions (subagent ghi mâu thuẫn spec rồi STOP — orchestrator trả lời rồi resume)
```

Không có plan file (task M đơn-agent hoặc READ-only) → bỏ qua mục này, đi
thẳng mục 1.

## 1. Đọc ledger

Đọc `.claude/state/orchestrator-ledger.md`. File không tồn tại → báo user
không có orchestration nào dở dang, dừng ở đây.

## 2. Tái tạo bảng phân rã

Ledger có 2 loại dòng:

- Dòng orchestrator ghi lúc dispatch (bảng phân rã gốc — xem quy ước ghi ở
  mục 4 bên dưới): subtask nào, persona nào, wave nào.
- Dòng hook `subagent-stop-record.sh` tự append lúc subagent xong:
  `- [<ts>] subagent done: agent_id=<id> type=<subagent_type>`.

Đối chiếu 2 loại dòng: subtask nào có dòng "subagent done" tương ứng →
**done**; subtask trong bảng gốc mà KHÔNG có dòng done tương ứng →
**pending/failed**. Không chắc match được (agent_id không rõ subtask nào)
→ hỏi user xác nhận trạng thái trước khi re-dispatch, không đoán.

Nhiều dòng `subagent done` cùng `agent_id` = iterations qua SendMessage
resume (REVISE lặp lại cùng agent) — lấy dòng CUỐI làm trạng thái, không phải
duplicate.

## 3. Re-dispatch CHỈ phần pending/failed

Theo routing rules ở `.claude/rules/common/orchestrator.md` (size/loại →
persona, fallback chain, planning gate, fan-out ≤15 concurrent). Subtask đã
done → KHÔNG chạy lại. Áp dụng lại đúng persona + fallback chain đã định,
không tự ý đổi persona trừ khi lần trước đã fail hết chain (khi đó theo loop
guard: re-decompose, không quay lại model đã fail).

## 4. Quy ước ghi ledger (orchestrator side)

Ledger = audit-trail PHỤ, append-only, TTL 48h tự prune — KHÔNG phải state
machine (state machine là `task-graph.md`, xem [[orchestrator]]). Hook
`subagent-stop-record.sh` CHỈ ghi dòng "subagent done" khi subagent kết
thúc — nó không biết bảng phân rã. Vì vậy tại thời điểm dispatch, orchestrator
NÊN tự ghi bảng phân rã (subtask/persona/wave) vào
`.claude/state/orchestrator-ledger.md` trước khi gọi Agent, để bước 2 ở trên
có cái để đối chiếu. Không bắt buộc bằng hook (hook chỉ record completion),
nhưng bỏ qua bước này làm ledger vô dụng khi resume.

## 5. Hoàn tất

Khi task-graph chuyển `status: done` (tất cả subtask done + integration
verify pass) → xoá `.claude/state/task-graph.md` **và**
`.claude/state/plan-<slug>.md` (nếu có) cùng lúc, báo user orchestration đã
hoàn tất. Ledger giữ nguyên (TTL 48h tự prune riêng) — graph/plan đã xoá mà
ledger còn dòng cũ là bình thường, không phải bug.
