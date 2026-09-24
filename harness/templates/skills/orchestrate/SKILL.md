---
name: orchestrate
description: "Quy trình orchestration task M+: plan-first, task-graph, fan-out Sonnet song song theo wave, review + integration verify. Dùng khi \"orchestrate\" hoặc chia task chạy song song."
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
- Set `status: done` — `session-start.sh` tự xoá graph file khi thấy `done` ở session sau; xoá tay ngay cũng được (`rm .claude/state/task-graph/<slug>.md`).
- Cleanup worktree/branch theo `[[git-workflow]]` (worktree remove, branch delete sau merge).
- Fix/feature có rủi ro bị merge đè sau này → ghi `fix-ledger` nếu áp dụng.

## Resume

Session mới thấy banner `📊 Task-graph dở dang (status: ...)` (từ `session-start.sh`, in kèm nội dung file — chỉ file khớp slug session hiện tại) → đọc `.claude/state/task-graph/<slug>.md`, tiếp tục đúng bước khớp `status` hiện tại (`planning`→bước 3, `dispatched`→bước 4/5, `review`→bước 5, `integrating`→bước 6) — không phân tích lại từ đầu, không tạo graph mới đè lên graph dở dang.
