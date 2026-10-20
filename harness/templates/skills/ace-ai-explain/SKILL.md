---
name: ace-ai-explain
description: Thêm nút "AI giải thích / Hỏi AI về trang này" vào web admin/dashboard ACE Galaxy (Node hoặc Java) theo 1 contract chung — registry tính năng, POST /api/ai/explain, prompt + JSON schema cố định, cache/cooldown/audit, popup an toàn. Hỏi user phạm vi trước khi code. Dùng /ace-ai-explain [repo|path], hoặc khi user nói "thêm Hỏi AI", "nút AI giải thích", "AI phân tích trang này".
user-invocable: true
---

# /ace-ai-explain — Nút "Hỏi AI" chuẩn chung

Không có lib: mỗi site tự cài theo contract dưới (Node + Java khác ngôn ngữ, phần dùng chung < 100 dòng). Contract này là nguồn duy nhất — đổi prompt/schema thì sửa upstream `harness/templates/skills/ace-ai-explain/SKILL.md` (repo harness), `install.sh update-all`, rồi sync các site.

**Bản tham chiếu (copy từ đây, đừng viết lại từ đầu):**

| Stack | Server | UI |
|---|---|---|
| Node (gsebot) | `imba/ace_ace_island-bot-player/soak/monitor/explain-ai.mjs` (prompt/normalize/redact, pure) + `ai-features.mjs` (registry) + handler `fleet-ui.mjs` (tìm `/api/ai/explain`) + `bots-ai.mjs` `resolve()` (chọn nguồn AI) | `fleet-ui.html` (`.ai-btn`) |
| Java Spring (mm-director) | `imba/ace_ace_matching-service/mm-director/.../ai/AiExplainService.java` + `AdminController` `@PostMapping("/ai/explain")` | `static/admin/ai.js` |

## Bước 0 — Hỏi user (BẮT BUỘC, 1 lần AskUserQuestion)

Khảo sát repo trước (stack, router, auth/CSRF, trang/tab, docs có sẵn), rồi hỏi gộp:

1. **Phạm vi nút**: mỗi tab/tính năng 1 nút (registry) / 1 nút chung "Hỏi AI về trang này" (feature = tab đang active).
2. **Ngữ cảnh gửi AI**: docs + source / thêm số liệu live (snapshot, đã redact) / chỉ docs.
3. **Ai được bấm**: mọi user đã login / chỉ admin.
4. **Có cần mode "đề xuất cấu hình" (tune)** không — mặc định KHÔNG (chỉ explain, read-only). Cần → xem `tune-ai.mjs`, AI chỉ đề xuất, user tự bấm áp dụng.

Liệt kê đề xuất registry (feature id → title, docs heading, src files) trong câu hỏi để user sửa.

## Contract

### API
`POST <prefix>/api/ai/explain` — cần login + CSRF như các POST khác.
- Body: `{ feature: string, note?: string (≤500), refresh?: bool }`
- 200: `{ feature, title, model, cached, at, explain: { summary, mechanism, usage, strengths[], weaknesses[], gaps[], suggestions[], dataNotes } }`
- Lỗi: `400` feature lạ · `401` → UI chuyển trang login · `429 {retryAfter}` cooldown · `503 AI_DISABLED` thiếu config · `502 AI_FAILED {message}` LLM lỗi/JSON hỏng.

### Registry tính năng (server, không nhận path từ client)
`feature → { title, page, docs: [heading...], src: ["file" | "file#from-to"], data: getterKey|null }`. Luôn kèm heading "Tổng quan hệ thống" (hoặc tương đương). Client CHỈ gửi `feature` id — server tự đọc file (chống path traversal).

### Context gửi LLM (user message)
Thứ tự: `# Tính năng` → `# Câu hỏi/ghi chú của admin` (nếu có) → `# TÀI LIỆU` (mỗi section ≤6000) → `# SOURCE` (mỗi file ≤12000, tổng ≤40000) → `# SỐ LIỆU HIỆN TẠI` (JSON đã `stripSensitive`, ≤8000).

Redact bắt buộc trước khi gửi: bỏ key khớp `/csrf|token|secret|passw|cookie|authorization|api_?key|private|^key$/i` (mọi độ sâu); trong string: userinfo URL, query `token|key|secret|sig|auth|code|pass`, hex ≥32, base64 ≥40. Số liệu cache dùng chung mọi viewer → không đưa identity/row từng user.

### System prompt (copy nguyên, chỉ thay `<mô tả site>`)
```
Bạn là kỹ sư review tính năng của <mô tả site>. Admin bấm nút "AI giải thích" để hiểu một tính năng.
CHỈ dựa trên TÀI LIỆU, SOURCE và SỐ LIỆU được cấp trong tin nhắn người dùng. Không bịa; chỗ nào không chắc hoặc không có trong nguồn thì nói rõ là không chắc.
Viết tiếng Việt, rõ ràng, dùng gạch đầu dòng ngắn khi cần. Trả về JSON THUẦN, không giải thích ngoài JSON, đúng định dạng:
{"summary":"<≤600 ký tự: tính năng này là gì>","mechanism":"<≤3500 ký tự: cơ chế hoạt động từ đầu đến cuối, dẫn tên hàm/file/route thật>","usage":"<≤1500 ký tự: cách dùng, khi nào dùng>","strengths":["<≤400 ký tự mỗi mục (1–2 câu hoàn chỉnh), ≤8 mục>"],"weaknesses":["..."],"gaps":["..."],"suggestions":["..."],"dataNotes":"<≤1200 ký tự: nhận xét số liệu hiện tại nếu có>"}
Giới hạn độ dài là cứng: viết GỌN trong giới hạn, mỗi mục của strengths/weaknesses/gaps/suggestions gồm 1–2 câu hoàn chỉnh (không bỏ lửng giữa câu), không vượt số ký tự đã nêu.
gaps = thứ còn thiếu, rủi ro, hoặc chỗ tài liệu lệch với code. suggestions = đề xuất cụ thể, khả thi. Nếu admin có câu hỏi/ghi chú thì trả lời nó trong mechanism/usage.
```

### Normalize output
Cap lại phía server dù prompt đã dặn: summary 600, mechanism 3500, usage 1500, dataNotes 1200, list ≤8 mục × 400. Cắt tại ranh giới câu/mệnh đề (`. ` `; ` `, `) + `…`, không cắt giữa từ. `summary` và `mechanism` đều rỗng → 502.

### Chọn nguồn AI (env, mỗi site tự resolve ~10 dòng)
1. `AI_GATEWAY_URL` + `AI_GATEWAY_KEY` + `AI_MODEL_DEFAULT` (OpenAI-compatible)
2. `AI_PROXY=1` → `AI_9ROUTER_BASE_URL` + `AI_9ROUTER_TOKEN` + `AI_MODEL_9ROUTER` (fallback `AI_MODEL_DEFAULT`). `AI_9ROUTER_API_KEY` = tên cũ, chỉ đọc fallback ở site đã có, site mới không dùng.
3. `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` + `AI_MODEL_ANTHROPIC` (fallback `AI_MODEL_DEFAULT`)

Site Node đã dùng `@acegalaxy/lib-ai-gateway` → gọi qua lib thay vì tự resolve. Thêm tên biến vào `.env.example`. Thiếu config → 503 + `console.warn` + `sendServiceAlert` `warn` 1 lần/ngày (chỉ TÊN biến thiếu, không value). Timeout gọi LLM 60s.

### Cache / cooldown / audit
- Cache theo `feature`, TTL 6h, tối đa 200 entry (evict cũ nhất) — CHỈ khi `note` rỗng và `refresh=false`.
- Cooldown mỗi user giữa 2 lần gọi LLM thật (env `<APP>_AI_COOL_MS`) → 429 `retryAfter` (giây). Cache hit không tính cooldown.
- Audit mỗi lần bấm: event `ai_explain { user, feature, cached, model }` vào log/DB audit sẵn có của site.

### UI
- Nút `.ai-btn` (style chung theme tối), popup `<dialog>` tự dựng — KHÔNG `alert/confirm/prompt` native.
- Ô `note` tuỳ chọn + nút "Hỏi lại (bỏ cache)" (`refresh:true`).
- Render 100% qua `textContent` (KHÔNG innerHTML với dữ liệu AI). Section: Tóm tắt · Cơ chế · Cách dùng · Điểm mạnh · Điểm yếu · Thiếu sót & rủi ro · Đề xuất cải tiến · Nhận xét số liệu. Hiện `model`, `cached`, `at`.
- Lịch sử hỏi trong phiên theo feature (mới nhất trên), disable nút khi đang chờ.
- Map lỗi: 503 "AI chưa cấu hình" · 429 "Chờ N giây rồi thử lại" · 502 `message`.

## Bước làm
1. Bước 0 hỏi user.
2. Copy server + UI từ bản tham chiếu cùng stack, đổi registry + `<mô tả site>`.
3. Test 1 file (không framework mới): normalize cap + cắt câu, `stripSensitive` (key lồng + chuỗi có token), feature lạ → 400, thiếu config → 503.
4. Verify thật: login site local/staging, bấm nút 1 feature → có kết quả; bấm lại → `cached:true`; tắt env AI → 503 hiện đúng chữ.
5. Nếu site có trang tài liệu (`/docs`) → thêm section mô tả nút + API.
6. Đổi contract (prompt/schema/cap) → sửa upstream skill (repo harness) + sync mọi site trong bảng tham chiếu cùng lượt.
