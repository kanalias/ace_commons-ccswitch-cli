---
name: orchestrate
description: "Quy trình orchestration task M+: plan-first, task-graph, fan-out Sonnet theo wave, review + integration verify, resume dở dang. Dùng khi \"orchestrate\", chia task song song, /orchestrate --resume."
user-invocable: true
---

# orchestrate — task-graph driven orchestration

Routing/persona chi tiết xem `[[orchestrator]]` (`.claude/rules/common/orchestrator.md`) — skill này KHÔNG lặp lại bảng routing, chỉ quy trình dùng artifact `.claude/state/task-graph/<slug>.md` (per-worktree — `<slug>` tự suy từ cwd/worktree của session, xem orchestrator.md "Task-graph artifact") để hook (`pre-task-dispatch-gate.sh`, `pre-bash-gate.sh`, `session-start.sh`) enforce/track được.

## Task-graph format v1.3

```
# task-graph: <slug>
status: planning|dispatched|review|integrating|done
integration-verify: <command hoặc ->
integration-status: pending|pass|fail

| id | subtask | persona | rw | locked | deps | wave | status | verify |
|----|---------|---------|----|--------|------|------|--------|--------|
| 1 | <nhỏ nhất còn độc lập> | delegate-sonnet | W | yes | - | 1 | pending | <command> |
```

- `rw`: `R` (read-only) hoặc `W` (write).
- `locked`: `yes`/`no` — interface/contract của subtask đã chốt chưa. `W` + `locked=no` → dispatch-gate hard-block.
- `deps`: id subtask khác phải xong trước, `-` nếu không.
- `wave`: nhóm dispatch cùng lượt (đồng thời trong 1 message).
- row `status`: `pending|dispatched|pass|revise|done`.
- Marker bắt buộc trong mọi prompt dispatch subtask thuộc graph: `task-graph #<id>` khớp row trong file graph của ĐÚNG session đang dispatch. Không còn cần slug trong marker (v1.3) — mỗi worktree đã có graph file riêng (`.claude/state/task-graph/<slug>.md`), không còn khả năng dispatch nhầm sang graph session khác nên không cần detect-mismatch. Thiếu marker/id sai → dispatch-gate block; header bảng bị reformat → gate fail-open + WARN log (không hard-block khi parse thất bại).
- Icon map v1.1 (chỉ khi IN bảng ra chat/progress report): `⬜ pending · 🔄 dispatched · ✅ pass · ♻️ revise · ✔️ done`. File graph luôn giữ text thuần ở cột status — icon là lớp hiển thị, không ghi vào file.
- **Dual-artifact:** graph = state machine duy nhất (trạng thái luôn thắng). Blackboard `plan-<slug>.md` (nếu có) chỉ giữ contract/spec/Questions — không có field status riêng, xem `[[orchestrator]]` mục "Task-graph artifact".

## 1. Analyze

Đọc code liên quan, xác định scope thật của task. Task size S (xem `[[orchestrator]]`) hoặc reasoning-only (design/debug/review không kèm edit) → KHÔNG cần graph, dừng skill ở đây, làm trực tiếp.

## 2. Lock interfaces

Trước khi chẻ: chốt signature/types/ranh giới file/module, quyết sẵn edge case cho từng mảnh WRITE. Mảnh nào còn ambiguity thiết kế → chưa lock — không được set `locked: yes`, không dispatch.

## 3. Decompose + ghi graph

Chẻ tới đơn vị nhỏ nhất còn **độc lập thật** — đạt cả 5: spec riêng, paths riêng, verify riêng, zero file chung, không phụ thuộc interface chưa lock. Thiếu 1 tiêu chí → dừng ở mức đó, không chẻ tiếp.

- Tạo/ghi `.claude/state/task-graph/<slug>.md` (`<slug>` = tự suy từ cwd/worktree session hiện tại, `main` nếu làm thẳng trên repo chính) theo format ở trên. `status: planning`.
- Subtask cùng chạm 1 file → gộp thành 1 row hoặc set `deps` (không fan-out song song 2 row đụng cùng file).
- Task M+ multi-agent WRITE (≥2 subtask WRITE, hoặc có subtask L/XL) → cũng ghi blackboard `.claude/state/plan-<slug>.md` theo template mục "Blackboard template" bên dưới, trước khi dispatch.
- Trước khi chuyển sang dispatch: `status: dispatched`.

## 4. Dispatch theo wave

- In banner ngắn trước mỗi lượt gọi Agent: persona + subtask id + timeout dự kiến.
- Mọi row cùng `wave` và không còn `deps` chưa xong → gửi **chung 1 message, nhiều tool-call** (Agent tool chạy concurrent). Trần 15 đồng thời — vượt → chia wave kế.
- Prompt mỗi subtask self-contained: repo path tuyệt đối + branch, spec đã lock (không để subagent tự đoán thiết kế), file paths, acceptance/verify command, "NO commit — produce diff only", marker `task-graph #<id>`. Thiếu marker/spec → `pre-task-dispatch-gate.sh` block.
- Cập nhật row `status: dispatched` ngay khi gửi.

## 5. Collect + review

- Mỗi subtask return → cập nhật row: `pass` (đạt) hoặc `revise` (cần sửa).
- `revise` → `SendMessage` tới ĐÚNG agent cũ (giữ context đã có), không spawn agent mới trừ khi đổi persona hẳn.
- Generator ≠ verifier: mảnh lớn/nhạy cảm (security, cross-module, >~300 dòng diff) → review pass riêng (Opus reasoning-only hoặc persona khác implementer), không để agent tự chấm diff của chính nó.
- Sau mỗi verdict cập nhật row, IN LẠI bảng graph ra chat với icon map v1.1 (progress table) để user thấy tiến độ không cần hỏi: bảng ≤15 row in nguyên, lớn hơn in tóm tắt đếm `✅n 🔄n ♻️n ⬜n`.

## 6. Integration verify

Sau khi merge ≥2 mảnh về cây làm việc:

1. `status: integrating`.
2. Chạy command ghi ở `integration-verify:` trên cây đã ghép.
3. Pass → `integration-status: pass` (mở khoá `git commit` tổng — `pre-bash-gate.sh` block commit khi `integrating` + status khác `pass`). Báo user dòng `✔️ integration pass`.
4. Fail → chẩn đoán mảnh lệch, mở vòng REVISE mới (quay bước 5) — KHÔNG merge đè tiếp lên fail.

## 7. Cleanup

- Commit sau khi review xong (không phải subagent tự commit).
- Set `status: done` — `session-start.sh` tự xoá graph file khi thấy `done` ở session sau (plan file KHÔNG tự xoá); xoá tay ngay cả hai: `rm .claude/state/task-graph/<slug>.md .claude/state/plan-<slug>.md`.
- Cleanup worktree/branch theo `[[git-workflow]]` (worktree remove, branch delete sau merge).
- Fix/feature có rủi ro bị merge đè sau này → ghi `fix-ledger` nếu áp dụng.

## Blackboard template (plan-<slug>.md)

Pattern giống LangGraph checkpoint / Mastra suspend-resume: blackboard giữ
context/contract shared cho mọi subagent; task-graph giữ trạng thái. Task M+
multi-agent WRITE ghi blackboard `.claude/state/plan-<slug>.md` lúc dispatch
(xem [[orchestrator]] Planning gate) làm nguồn **CONTEXT/contract** (bảng
subtask + contract đã lock + decisions + Questions) — **KHÔNG** dùng làm nguồn
trạng thái. Trạng thái (status/wave/verdict) sống DUY NHẤT ở
`.claude/state/task-graph/<slug>.md` (per-worktree — `<slug>` tự suy từ
cwd/worktree của session hiện tại, `main` nếu làm thẳng trên repo chính;
dual-artifact: xem [[orchestrator]] mục "Task-graph artifact") — plan file
không tự giữ máy trạng thái riêng.

Template chuẩn:

```markdown
# Plan: <slug>
(trạng thái xem .claude/state/task-graph/<slug>.md — file này KHÔNG có field status riêng)
## Contract (LOCKED — subagent không tự sửa)
<signatures, types, ranh giới file/module>
## Edge cases (đã quyết)
## Decisions log
- [ts] <quyết định> — <lý do>
## Subtasks
| # | subtask | persona | agent_id | interface✅ | phụ thuộc | wave | verify cmd |
## Questions (subagent ghi mâu thuẫn spec rồi STOP — orchestrator trả lời rồi resume)
```

Không có plan file (task M đơn-agent hoặc READ-only) → bỏ qua mục này.

## Resume (/orchestrate --resume)

1. **Nguồn trạng thái ưu tiên** = task-graph của slug session hiện tại. Session
   mới thấy banner `📊 Task-graph dở dang (status: ...)` (từ `session-start.sh`)
   → đọc `.claude/state/task-graph/<slug>.md`, tiếp tục đúng bước khớp
   `status` hiện tại (`planning`→bước 3, `dispatched`→bước 4/5, `review`→bước
   5, `integrating`→bước 6) — KHÔNG phân tích lại từ đầu, KHÔNG tạo graph
   mới đè lên graph dở dang.
2. **Có blackboard** `plan-<slug>.md` → đọc để lấy contract/edge-cases/decisions/Questions
   đã lock, tránh hỏi lại subagent những gì đã quyết.
3. **Không có graph nhưng có ledger** (`.claude/state/orchestrator-ledger.md`)
   → tái tạo bảng phân rã từ ledger: ledger có 2 loại dòng — dòng orchestrator
   ghi lúc dispatch (subtask/persona/wave, xem quy ước mục 5 dưới) và dòng
   hook `subagent-stop-record.sh` tự append lúc subagent xong
   (`- [<ts>] subagent done: agent_id=<id> type=<subagent_type>`). Đối chiếu
   2 loại dòng: subtask có dòng "subagent done" tương ứng → **done**; subtask
   trong bảng gốc không có dòng done tương ứng → **pending/failed**. Nhiều
   dòng "subagent done" cùng `agent_id` = iterations qua SendMessage resume
   (REVISE lặp lại) — lấy dòng CUỐI làm trạng thái, không phải duplicate.
   Không chắc match được → hỏi user xác nhận trước khi re-dispatch, không đoán.
   Không có cả graph lẫn ledger → báo user không có orchestration nào dở
   dang, dừng ở đây.
4. **Re-dispatch CHỈ phần pending/failed.** Theo routing rules ở
   `[[orchestrator]]` (persona, fallback chain, planning gate, fan-out ≤15
   concurrent). Subtask đã done → KHÔNG chạy lại. Áp lại đúng persona +
   fallback chain đã định, không tự ý đổi persona trừ khi lần trước đã fail
   hết chain (khi đó theo loop guard: re-decompose, không quay lại model đã
   fail).
5. **Quy ước ghi ledger (orchestrator side).** Ledger = audit-trail PHỤ,
   append-only, TTL 48h tự prune — KHÔNG phải state machine (state machine
   là `task-graph/<slug>.md`). Hook `subagent-stop-record.sh` CHỈ ghi dòng
   "subagent done" khi subagent kết thúc — nó không biết bảng phân rã. Vì
   vậy tại thời điểm dispatch, orchestrator NÊN tự ghi bảng phân rã
   (subtask/persona/wave) vào `.claude/state/orchestrator-ledger.md` trước
   khi gọi Agent, để mục 3 ở trên có cái để đối chiếu khi resume.
6. **Hoàn tất.** Khi task-graph chuyển `status: done` (tất cả subtask done +
   integration verify pass) → xoá `.claude/state/task-graph/<slug>.md` **và**
   `.claude/state/plan-<slug>.md` (nếu có) cùng lúc, báo user orchestration
   đã hoàn tất. Ledger giữ nguyên (TTL 48h tự prune riêng) — graph/plan đã
   xoá mà ledger còn dòng cũ là bình thường, không phải bug.
