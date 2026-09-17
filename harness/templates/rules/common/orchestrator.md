---
name: orchestrator
description: Main agent = pure orchestrator; plan-first (lock interface + spec) rồi fan-out ≤15 Sonnet song song; REVISE → SendMessage agent cũ. Fable-main: cấm mọi code kể cả size-S trừ khi user cho phép explicit
status: live
updated: 2026-08-04
metadata:
  type: reference
---

# Orchestrator Mode (cross-project)

**"Opus" trong file này = main agent giữ vai orchestrator**, bất kể model thật (Opus/Fable/Sonnet-main) — vai gắn vào vị trí, không vào tên model. Fable-main chặt hơn: xem section dưới.

Main agent LUÔN là **pure orchestrator** — always-on mọi task, bất kể quota. Mục tiêu = **nhanh + chất lượng**, không phải tiết kiệm token: orchestrator giữ context sạch cho phân tích/lock-interface/spec/review; execution đẩy xuống subagent song song trong worktree riêng. Ranh giới cố định: **size-S** + **reasoning-only** → orchestrator tự làm; mọi execution còn lại → MUST delegate.

## Plan-first, rồi fan-out tối đa (P0, ưu tiên cao nhất)

Fan-out chỉ hiệu quả khi plan đã kỹ — chẻ WRITE work trước khi interface lock → các mảnh lệch nhau, merge conflict. Trình tự bắt buộc: **phân tích toàn cục → lock interface/contract → chẻ nhỏ nhất còn độc lập → viết spec kỹ → fan-out**. Spec thiếu là nguyên nhân fail chính của delegation.

```text
Fable/Opus:  phân tích → lock interfaces → chẻ subtask độc lập nhỏ nhất → viết spec
     │
     ├── Sonnet #1 (worktree A) ─┐
     ├── Sonnet #2 (worktree B) ─┼─ song song, không đụng file nhau
     ├── Sonnet #3 (worktree C) ─┘
     │
Fable/Opus:  review diff từng worktree → merge / reject → integration verify
```

> **Brainstorm READ-only pass (optional — task XL hoặc ambiguity cao):** trước interface-lock, fan-out 2-4 agent READ-only, mỗi agent 1 khía cạnh: risk / API-design options / edge cases / prior art trong repo. Orchestrator MỘT MÌNH merge findings vào blackboard rồi mới lock interface. ❌ CẤM nhiều agent WRITE "tự thống nhất" interface với nhau. ❌ CẤM brainstorm agent có quyền Edit/Write. Task 1 approach hiển nhiên → bỏ qua pass này.

**Interface-lock gate (BẮT BUỘC trước mọi fan-out WRITE):** trước khi dispatch subtask WRITE nào, orchestrator PHẢI: (a) phân tích xong toàn cục, (b) lock interface/contract giữa các mảnh (signature, types, ranh giới file/module), (c) quyết sẵn edge cases trong spec — KHÔNG để Sonnet tự đoán quyết định thiết kế. Mảnh còn ambiguity → KHÔNG dispatch, giải quyết trước. READ-only fan-out KHÔNG cần gate này — dispatch tự do.

**Hard rules:**

1. **Decompose nhỏ nhất còn độc lập.** Mỗi mảnh: spec riêng + paths riêng + verify riêng + **zero file chung** + không phụ thuộc interface chưa lock. Đạt cả 5 → chẻ tiếp; thiếu 1 → dừng.
2. **Fan-out tối đa.** Subtask không phụ thuộc nhau → dispatch **cùng một lượt, 1 message nhiều tool-call**. KHÔNG dispatch tuần tự rồi chờ.
3. **Trần đồng thời = 15 subagent.** >15 độc lập → chia **wave**.
4. **Nghi ngờ độc lập: WRITE ≠ READ.** WRITE nghi đụng interface/file chung → coi là **PHỤ THUỘC** (gộp hoặc serialize). READ-only nghi ngờ → coi là **độc lập** (fan-out). Không bịa dependency cho READ; không bịa độc lập cho WRITE.
5. **Song song vẫn theo routing + worktree isolation.** Mỗi delegate worktree riêng; persona theo bảng Routing dưới.
6. **Không fan-out subtask chạm cùng file.** ≥2 subtask cùng sửa 1 file → gộp hoặc serialize.

**Planning gate + blackboard (BẮT BUỘC trước dispatch):** task M trở lên → in bảng phân rã TRƯỚC khi gọi Agent nào:

| # | subtask (nhỏ nhất còn độc lập) | persona | interface locked? | phụ thuộc (# nào) | wave | verify command |
|---|---|---|---|---|---|---|

≥2 dòng cùng wave → PHẢI gửi chung 1 message. Bảng 1 dòng duy nhất → giải thích tại sao không chẻ được. WRITE subtask chưa ✅ interface-locked → KHÔNG dispatch.

- Task **M+ multi-agent WRITE** (≥2 subtask WRITE, hoặc có subtask L/XL) → PHẢI ghi blackboard `.claude/state/plan-<slug>.md` (cấu trúc: `/resume-orchestration` mục 0): contract/interface đã lock, edge cases, decisions log, bảng phân rã (kèm cột `agent_id` cho SendMessage resume — KHÔNG cột `status`, trạng thái sống ở `task-graph.md`), section `## Questions`. Blackboard = shared source-of-truth cho mọi subagent.
- Task M đơn-agent hoặc READ-only fan-out → chỉ in bảng chat, blackboard optional.
- Lifecycle: task xong → xoá plan file cùng lúc ledger. Plan file >48h không đụng → stale, audit trước khi tin.

**Enforcement:** behavioral (self-binding) — bảng phân rã in ra là bằng chứng kiểm được. Bỏ qua fan-out khi task tách được = vi phạm P0.

**Tránh:** ❌ 1 subagent ôm nguyên task lớn khi tách được. ❌ dispatch tuần tự khi A/B độc lập. ❌ bịa dependency để làm ít việc phân rã. ❌ vượt 15 concurrent. ❌ fan-out WRITE khi interface chưa lock. ❌ chẻ quá ranh giới độc lập chỉ để tăng số subagent.

## Task-graph artifact (BẮT BUỘC task M trở lên)

Task M trở lên → bảng phân rã PHẢI ghi vào `.claude/state/task-graph.md` (sống sót qua compact/session, ledger resume đọc được).

**Phân vai 2 artifact (không trộn):** `task-graph.md` = state machine DUY NHẤT (status/tiến độ/wave/verdict) — hook parse, luôn thắng khi mâu thuẫn trạng thái. Blackboard `plan-<slug>.md` = contract/spec/edge-cases/decisions/Questions — KHÔNG giữ máy trạng thái riêng. Cả 2 xoá cùng lúc khi graph `status: done`.

**Format (TASK-GRAPH FORMAT v1.2):**

```text
File: .claude/state/task-graph.md (runtime state, không commit vào git)
Header lines:
  # task-graph: <slug>
  status: planning|dispatched|review|integrating|done
  integration-verify: <command hoặc ->
  integration-status: pending|pass|fail
Table header đúng: | id | subtask | persona | rw | locked | deps | wave | status | verify |
Row values: id=int · rw=R|W · locked=yes|no · deps=- hoặc ids phẩy · wave=int · status=pending|dispatched|pass|revise|done · verify=command
Prompt marker (v1.2): mọi dispatch delegate-* PHẢI chứa literal `task-graph <slug>#<id>` — slug khớp đúng header `# task-graph: <slug>` của file graph hiện tại (chống graph của task khác còn sót lại / session song song đè nhầm). Marker v1 cũ `task-graph #<id>` (không slug) vẫn được tolerate — backward-compat, không hard-fail.
```

- Hook `pre-task-dispatch-gate.sh` HARD-BLOCK dispatch khi: graph tồn tại mà prompt thiếu marker, id không có trong bảng, slug lệch header (marker v1.2), hoặc row `rw=W` có `locked≠yes` — interface-lock enforce cứng. Marker v1 (không slug) → tolerate. Header bảng bị reformat → gate **fail-open + WARN log**.
- Orchestrator update cột `status` row ngay sau mỗi verdict (pass/revise). Sau integration verify → set `integration-status: pass`. Task hoàn tất → `status: done`; `session-start.sh` dọn file khi done.
- Hook `pre-bash-gate.sh` chặn `git commit` main-agent khi graph `status: integrating` mà `integration-status` chưa `pass`.
- **Render block v1.2** (thay icon map bản trước):
  - Icon map RENDER-ONLY (hiển thị chat/statusline, KHÔNG ghi vào file graph): `⬜ queued · 🚀 spawned · 🔄 running · 📥 returned · 👀 reviewing · ♻️ revise · ✅ pass · ✔️ done · 🛑 fail · ⏳ pending · 🧪 verify · 🔀 merging · 🧠 orchestrator · 🤖 agents · 📊 header`.
  - Mapping row-status (file, text thuần) → render-status: orchestrator suy ra từ session knowledge, KHÔNG ghi state mới vào file: `pending`→⬜ (hoặc 🚀 vừa spawn) · `dispatched`→🔄 (hoặc 📥 đã return chờ review / 👀 đang review) · `revise`→♻️ kèm số vòng · `pass`→✅ · `done`→✔️ · fail hết fallback chain→🛑.
  - Template block chat (in trong code block ```text để font mono):

    ```text
    ╭─ 📊 task-graph: <slug> ── wave n/m ──────────────╮
    │  🧠 ORCHESTRATOR: <state> · integration: <icon>   │
    │  🤖 AGENTS                                        │
    │  ├─ #1 <subtask>  <persona>  ✅ pass              │
    │  ├─ #2 <subtask>  <persona>  🔄 running           │
    │  └─ #4 <subtask>  <persona>  ⬜ queued (w3)       │
    │  ✅n · 🔄n · ♻️n · ⬜n                             │
    ╰───────────────────────────────────────────────────╯
    ```

  - Graph >8 rows → chỉ render wave hiện tại + queued kế tiếp, còn lại gộp vào footer đếm.
  - Trigger: in block sau MỖI event orchestration — dispatch (kèm banner Dispatch visibility mục 1), subagent return, verdict, merge, wave transition. Lý do: VSCode plugin KHÔNG render statusline — block chat là kênh hiển thị chính cho user plugin; statusline chỉ là bonus CLI.
  - GIỮ nguyên: file graph luôn text thuần ở cột status (hook parse text, không parse icon); KHÔNG thêm cột vào bảng graph (hooks parse field index cứng — thêm cột làm gate fail-open âm thầm); statusline script `.claude/statusline-orchestration.sh` đọc graph → render segment `📊` dưới prompt (chain sau global statusline nếu project có).

## Fable-main (P0 — chặt hơn Opus)

Khi main agent chạy **Fable**: **pure orchestrator tuyệt đối — cấm mọi code, kể cả size-S**. Fable KHÔNG Edit/Write/MultiEdit/Bash-write BẤT KỲ đâu (kể cả commit, rename, 1-line, config tweak). Chỉ được: TodoWrite/planning, delegate execution, synthesize output → report. Ngoại lệ 2 loại: (1) Write vào memory dir (`~/.claude/projects/*/memory/`, gồm MEMORY.md) — memory không phải code, không phải harness file; (2) Write vào `.claude/state/` (task-graph, ledger) — planning/state artifact, không phải code, orchestrator phải tự ghi được graph để dispatch/resume hoạt động. Mọi thứ chạm file khác (kể cả 4 case size-S dưới) → delegate hoặc STOP hỏi user.

**Escape hatch (user-only):** user cho phép rõ trong prompt ("Fable cứ sửa trực tiếp", "cho phép code") → Fable làm theo routing thường như Opus. KHÔNG tự suy diễn "task nhỏ chắc OK" — im lặng = cấm. Permission chỉ hiệu lực trong turn/task được cho phép — turn sau user im lặng = cấm lại, KHÔNG suy diễn "user đã cho phép lúc nãy".

**Lưu ý enforcement:** Claude Code không expose current-model vào hook payload → hook orchestrator-gate KHÔNG phân biệt được Opus vs Fable (chỉ chặn main-vs-subagent theo `agent_id`). Ràng buộc Fable này là **behavioral (self-binding)**, không có hard-block — Fable phải tự tuân, không dựa hook đỡ.

**Chi phí — KHÔNG phải constraint.** Routing chỉ theo nhanh + chất lượng; Sonnet = executor chính, Gemini/DeepSeek/Codex phụ trợ — không dùng thay Sonnet chỉ vì rẻ hơn.

## Size-S — Opus làm trực tiếp (4 case)

1. TodoWrite / planning
2. 1-line edit + 0 read context (commit, push, rename, config tweak) — >1 dòng diff HOẶC phải đọc file trước → hết là S, route theo bảng dưới
3. Read < 50 dòng, single file
4. Synthesize delegate output → user report

## Routing (size + loại → delegate + fallback chain)

| Nhãn | Loại | Giao cho | Fallback (theo thứ tự, không quay vòng) |
|---|---|---|---|
| **S** | 4 case trên | **Opus main** | — |
| **reasoning-only** | architecture design, debug chẩn đoán root cause, code review (KHÔNG kèm edit) | **Opus main** | — |
| **M-mechanical** | boilerplate / batch edit | `delegate-deepseek` | → sonnet → re-classify L/XL (1 lần) → STOP + báo user |
| **read-only** | audit, cross-file summary, grep rộng, risk analysis | `delegate-sonnet` | → gemini (free, chậm hơn; degrade >200K) → deepseek → STOP + báo user |
| **web-research** | research web nhiều nguồn, so sánh options, đọc docs dài | subagent in-harness `model: fable` (WebSearch/WebFetch) | → opus → sonnet → gemini (search grounding, chỉ gom nguồn URL) → STOP + báo user. ≤2 query → main tự làm |
| **hard-reasoning-code** | bug khó đã resist fix thường, algo design phức tạp, security-sensitive edit, refactor invariant tinh vi (concurrency, transaction) | `delegate-codex` | → sonnet → STOP: Opus re-decompose spec |
| **L/XL** | code/edit thật theo spec rõ: implement feature, refactor thường, fix bug sau khi đã chẩn đoán rõ nguyên nhân | `delegate-sonnet` | → codex → STOP: Opus re-decompose spec (KHÔNG rơi về DeepSeek) |

**Heuristic M vs L/XL** (ranh giới routing quan trọng nhất): chạm ≤3 file + pattern lặp lại + KHÔNG đổi logic/behavior (rename, đổi signature hàng loạt, format, boilerplate) → **M-mechanical**. Đổi behavior, thêm/sửa algo, refactor đụng invariant, fix bug cần suy luận → **L/XL**. Nghi ngờ giữa 2 nhãn → chọn nhãn cao hơn (L/XL) vì under-provision subagent tốn 1 vòng fallback.

**Heuristic L/XL vs hard-reasoning-code**: tín hiệu "đã thử fix không được", "security review", "concurrency/race condition", "thiết kế thuật toán phức tạp" → **hard-reasoning-code** (Codex trước). Spec rõ, biết ngay cách làm (thêm field, implement theo design có sẵn, refactor cơ học có suy luận nhẹ) → **L/XL** (Sonnet trước). Nghi ngờ → chọn hard-reasoning-code (Codex mạnh hơn, an toàn hơn khi under-provision). M-mechanical ưu tiên DeepSeek trước (sai cũng dễ reject), fallback Sonnet ngay khi fail.

**Git-ops executor (khi main không tự chạy được — vd Fable-main):** git mechanical (commit/push/branch/tag, lệnh exact do main soạn sẵn) → subagent in-harness `model: haiku` (Sonnet trần; agent Sonnet cùng task còn sống → dùng lại). Deploy flow (merge protected + smoke test + push safety) → subagent in-harness Sonnet. CẢ HAI in-harness ONLY — wrapper ngoài (deepseek/gemini/codex) chỉ sản xuất diff, KHÔNG đụng git state (`check_no_new_commits` enforce). Confirm gate deploy (số commit, tác động, downtime) vẫn ở main + user TRƯỚC dispatch — executor không tự quyết.

**Repo KHÔNG có delegate wrapper** (`scripts/delegate/` vắng): chỉ `delegate-sonnet` (in-harness) chạy được — mọi nhánh cần execute route thẳng sang Sonnet, KHÔNG STOP, KHÔNG Opus tự ôm. Ghi rõ trong report là repo thiếu wrapper.

### Code-level enforcement

Ranh giới "execution vào core → MUST delegate" có hook chặn cứng (exit 2), phủ mọi write surface:

| Hook | Matcher | Chặn gì |
|---|---|---|
| `pre-edit-orchestrator-gate.sh` | `Edit\|Write\|MultiEdit\|NotebookEdit` | Main-agent Edit/Write vào core (dir bake install-time từ `HARNESS_CORE_DIRS`). Subagent → allow. + risk-path denylist cho persona `delegate-gemini`/`delegate-deepseek` (chặn dù trong subagent). |
| `pre-bash-gate.sh` | `Bash` | Main-agent Bash-write core (`sed -i`, `>`, `tee`, `patch`, `git apply`, `python -c`...) + gọi thẳng `aider`/`gemini`/`codex` (bypass wrapper). |

- Discriminator main vs subagent: field `agent_id` (chỉ có ở subagent).
- Escape hatch size-S 1-line thật: `ORCHESTRATOR_GATE_BYPASS=1` → allow + audit log. KHÔNG áp cho direct-CLI và risk-path (security boundary).
- Risk-path (auth/payment/wallet/...): khai báo `env.HARNESS_RISK_DIRS` trong `.claude/settings.json` — đọc runtime. Opus vẫn phải chọn đúng persona (Codex/Sonnet) cho domain nhạy cảm ngay từ đầu — hook chỉ là lưới cuối.
- Fail-open khi thiếu jq / payload không JSON. Off-switch: `HARNESS_DELEGATE=0`.

## Reasoning vs execution

- **Opus tự làm reasoning:** thiết kế architecture (đưa approach, không viết code), chẩn đoán debug (root cause, không tự sửa), review diff/PR (findings, không tự apply fix).
- Diff > ~500 dòng: `delegate-gemini` first-pass summary + hotspot list trước, Opus review trên summary.
- Reasoning xong cần code/edit thật → giao delegate (L/XL), kết quả reasoning làm spec đầu vào.
- Opus KHÔNG tự viết/sửa code L/XL dù đã tự chẩn đoán root cause — chẩn đoán và implement là 2 bước tách biệt.

## Generator ≠ verifier (review split)

Subagent implement KHÔNG được là subagent review — người viết có bias xác nhận diff của mình; verify do persona khác chạy.

- **L/XL + security-sensitive / cross-module / >~300 dòng diff**: sau khi implementer xong, dispatch **1 review pass riêng** — Opus tự review (reasoning-only) HOẶC delegate persona khác implementer.
- Review pass **read-only**: đưa findings, KHÔNG tự apply fix. Fix = vòng execute mới (route lại theo bảng).
- Task S/M thường: Opus review trực tiếp là đủ.

**Integration verify (BẮT BUỘC sau merge nhiều worktree):** mỗi mảnh verify pass riêng ≠ ghép lại chạy đúng. Sau merge ≥2 worktree cùng task, PHẢI chạy verify tích hợp (test/build/smoke của project) trên branch đã ghép TRƯỚC khi coi task xong hoặc commit tổng. Fail → xử lý như REVISE: chẩn đoán mảnh lệch, vòng execute mới — KHÔNG merge đè tiếp.

**Reasoning-effort knob (Codex):** model map: `gpt-5.6-sol` strongest (large refactors, architecture, hard bugs, security, long multi-file tasks); `gpt-5.6-terra` balanced default high (features, bug fixes, PR review, tests); `gpt-5.6-luna` fastest small-scope (rename, config edits, single tests, docs/code lookup). Task khó → `-c model_reasoning_effort="high|xhigh"` trong sub-task prompt; `max` chỉ khi thật cần. Smoke/lint nhẹ → `low`.

## Loop guard (hard rules)

- Mỗi task tối đa **2 lần fallback**; hết chain → STOP + báo user, KHÔNG quay lại model đã fail.
- Cả 2 model đầu chain L/XL fail → mặc định lỗi ở **spec/prompt** → re-decompose trước khi retry.
- Re-classify (M → L/XL) chỉ được **1 lần** per task.
- Resume-fix xong PHẢI có review pass mới ra `VERDICT: APPROVE` trước khi merge — `pre-bash-gate.sh` chặn `git merge` khi verdict gần nhất còn REVISE.

### Revise = SendMessage, không spawn mới

Vòng REVISE cho cùng subtask → `SendMessage` tới ĐÚNG subagent đã implement (theo tên hoặc `agent_id`) — giữ nguyên context diff, không tốn vòng đọc lại repo. CHỈ spawn agent mới khi: (a) đổi persona theo fallback chain, hoặc (b) review pass (generator ≠ verifier). Agent name resolve latest-wins; trùng tên → dùng `agent_id` raw. Ledger có NHIỀU dòng `subagent done` cùng `agent_id` = iterations, không phải duplicate.

## Sub-task prompt (orchestrator → delegate) — self-contained

Delegate KHÔNG có session context. Mỗi prompt PHẢI đủ: (1) repo path + branch absolute, (2) spec đầy đủ (interface/contract đã lock + edge cases đã quyết — KHÔNG để delegate tự đoán quyết định thiết kế), (3) file paths, (4) acceptance criteria, (5) verify command, (6) NO commit — produce diff only, (7) worktree isolation cho edit task, (8) return summary <300 words, (9) timeout mặc định 10 phút (wrapper kill quá hạn = FAIL → sang fallback).

**Pointer-prompt (khi có blackboard):** prompt trỏ absolute path plan file, NHƯNG vẫn PHẢI inline tối thiểu: repo path absolute, scope file paths, verify command, "NO commit — diff only", acceptance 1-2 dòng — `pre-task-dispatch-gate.sh` grep 4 marker (path `/Users/`|`repo`, `verify|test`, `file|path|scope`, `commit`) + ≥200 chars; pointer trần bị chặn. Subagent gặp mâu thuẫn spec ↔ code → ghi section `## Questions` plan file + STOP, KHÔNG tự đoán. Orchestrator trả lời (update plan file) → resume qua SendMessage.

## Dispatch visibility (chống chờ câm)

1. **Banner trước dispatch (BẮT BUỘC mọi lần gọi Agent/wrapper):** in 1 dòng: persona + task slug + timeout dự kiến + (wrapper delegate) log path — vd `⏳ Dispatching delegate-codex — task <slug>, timeout 600s, log: .claude/state/delegate-runs/<agent>-<feat>-<epoch>.log`. Fan-out nhiều agent → 1 dòng mỗi agent hoặc bảng ngắn.

2. **Wrapper delegate (deepseek/gemini/codex) — live progress qua Monitor:** wrapper tee output + heartbeat 30s vào `.claude/state/delegate-runs/<agent>-<feat>-<epoch>.log`. Pattern: chạy wrapper qua `Bash run_in_background`; arm `Monitor` với `tail -f <log> | grep -E --line-buffered "⏳ running|STATUS=|FAIL|ERROR"` (log path từ dòng `▶ live log:` wrapper in lúc start, hoặc glob file mới nhất); xong → TaskStop monitor nếu còn sống.

3. **In-harness subagent (delegate-sonnet, Agent tool):** không có log để tail. Bù: banner lúc dispatch + báo ước lượng thời gian + tóm kết quả ngay khi return. KHÔNG bịa progress giả.

4. **Tránh:** ❌ dispatch câm không banner. ❌ foreground Bash chạy wrapper 10 phút (luôn `run_in_background` + Monitor). ❌ Monitor filter quá rộng (raw log spam chat) — chỉ heartbeat + terminal signals.

5. **Progress table:** sau MỖI event (dispatch/return/verdict/merge/wave transition) — không chỉ sau verdict — cập nhật row trong task-graph rồi in Render block v1.2 (xem section Task-graph artifact) ra chat. Bảng lớn (>8 rows) → fallback dòng đếm tóm tắt `✅n 🔄n ♻️n ⬜n`. Lý do in mọi event: VSCode plugin không có statusline, block chat là kênh hiển thị chính — user thấy tiến độ không cần hỏi.

## Delegate mandatory (wrapper infra)

| Subagent | Backend | Strength |
|---|---|---|
| `delegate-deepseek` | Aider + DeepSeek | Cheap + edit-in-place |
| `delegate-gemini` | Gemini CLI | Large context |
| `delegate-codex` | Codex CLI (o-series) | Deep reasoning |
| `delegate-sonnet` | In-harness Sonnet | Reasoning + edit |

1. KHÔNG bypass subagent — không Bash `aider/gemini/codex` từ main agent.
2. **Isolated worktree** — wrapper tạo `.claude/worktrees/<agent-id>/<feat>/`.
3. **No auto-commit** — aider dùng `--no-auto-commits`; codex/gemini không có flag tương đương nên wrapper post-run check `check_no_new_commits` (HEAD trước/sau CLI đổi → FAIL). Main agent quyết định merge/discard.
4. **Secrets** — wrapper load `.env` chain; KHÔNG pass keys vào prompt; KHÔNG echo values.
5. **Scope check** — sau delegation, main agent BẮT BUỘC `git diff` worktree trước merge; reject nếu edits ngoài scope.

Anti-patterns: ❌ main agent gõ `aider --model ...` trong Bash. ❌ delegate edit trên main worktree. ❌ pass `$*_API_KEY` vào task prompt. ❌ auto-merge worktree không diff review.

## Hard constraints

- KHÔNG gọi trực tiếp `aider`/`gemini`/`codex` CLI từ shell để bypass delegate wrapper.
- KHÔNG để delegate auto-commit; Opus review diff trước, commit sau.
- KHÔNG merge delegate worktree nếu diff chạm ngoài scope.
- Fallback theo đúng chain khai báo ở trên, KHÔNG nhảy cóc.

Context window (~200K auto-compact): xem [[token-budget]] — orchestrator luôn bật, không liên quan on/off.

> **Project-specific:** delegate wrapper path (`scripts/delegate/`), persona (`.claude/agents/delegate-*`) khai báo trong repo. Chi tiết wrapper: `.claude/rules/common/delegate-llm.md` (lazy, `paths: scripts/delegate/**`).

## Hooks bổ trợ orchestration

| Hook | Event | Vai trò |
|---|---|---|
| `pre-task-dispatch-gate.sh` | PreToolUse (Task) | Chặn dispatch khi prompt under-specified (thiếu spec/path/verify) + graph marker gates |
| `pre-bash-gate.sh` | PreToolUse (Bash) | Chặn `git merge` khi verdict gần nhất REVISE; chặn commit khi integrating chưa pass |
| `post-bash-stuck-detector.sh` | PostToolUse (Bash) | Cảnh báo lặp cùng lệnh ≥4 lần (thrashing) |
| `subagent-stop-record.sh` | SubagentStop | Ghi verdict (PASS/REVISE) vào ledger + append metrics JSONL; nhiều dòng cùng `agent_id` = resume iterations |
| `session-start.sh` | SessionStart | Đọc ledger, hiển thị task dở dang qua `/resume-orchestration` |

**Vai ledger (`orchestrator-ledger.md`):** audit-trail PHỤ, append-only, TTL 48h tự prune — KHÔNG phải state machine. `task-graph.md` là nguồn TRẠNG THÁI chính; ledger chỉ đối chiếu completion khi resume. Graph đã xoá mà ledger còn dòng cũ → bình thường.

**Metrics JSONL:** `subagent-stop-record.sh` append mỗi verdict vào `~/.cache/claude-code-<slug>/orchestration.jsonl` (fields: `ts`, `agent_id`, `type`, `verdict`) — audit định kỳ revise-rate/fallback-rate.
