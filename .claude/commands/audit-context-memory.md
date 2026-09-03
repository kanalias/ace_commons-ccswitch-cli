---
name: audit-context-memory
description: Audit toàn bộ static context load mỗi session — global rules (~/.claude/rules/), CLAUDE.md project, project rules trong .claude/rules (phân loại ALWAYS vs LAZY, chấm gate, đề xuất paths:), và MEMORY.md index (auto-memory) — đọc nội dung thật, phát hiện trùng lặp/derivable/phình, rồi sau khi user xác nhận thì áp fix trực tiếp (thêm paths:, sync index). Dùng khi user hỏi "context session có gì", "tối ưu context window", "file nào đang load", "rule nào đang always-load", "giảm context session", "kiểm tra lazy load", "rule nào nên lazy", hoặc chạy /audit-context-memory.
user-invocable: true
---

# audit-context-memory — inventory + audit + fix static context mỗi session

Mỗi session nạp tĩnh (không cần Claude chủ động Read) từ nhiều nguồn: global rules (`~/.claude/rules/`, luôn ALWAYS), `CLAUDE.md` project, project rules (`.claude/rules/*.md`, ALWAYS trừ khi có `paths:`), và `MEMORY.md` index (auto-memory, luôn load). Command này liệt kê hết, đọc nội dung thật, audit theo gate của [[rule-loading-policy]] + "what NOT to save" của memory system, rồi — sau khi user xác nhận — áp fix trực tiếp cho phần project rules.

Nguồn chân lý cho gate: `rule-loading-policy` trong `~/.claude/rules/` (global, không nằm trong project — installer này không cài rule đó). Command KHÔNG lặp lại policy — chỉ **áp dụng** thành audit + fix chạy được. Gate/định nghĩa lệch policy → theo policy.

Khác [[doctor-memory]] (chỉ memory content — broken link, orphan, naming, stale bên trong từng memory dir): command này audit **cái gì được nạp vào context**, doctor-memory audit **memory system tự nó có sạch không**. Hai phạm vi không chồng nhau: command này chỉ đọc `MEMORY.md` (index), không đọc/sửa từng file `user_*/feedback_*/project_*/reference_*.md` bên trong.

## Khái niệm (project rules)

- **LAZY** — rule có `paths:` (list glob) trong frontmatter. Chỉ load khi task chạm file khớp glob. Mặc định BẮT BUỘC cho project rule.
- **ALWAYS** — rule KHÔNG có `paths:`. Load mọi turn. Chỉ hợp lệ khi vượt gate P0-mọi-turn.
- **Gate always-load (đúng CẢ 2):** (1) P0 guardrail — vi phạm gây mất data / leak secret / phá scope; (2) áp mọi-turn — không gắn được vào 1 vùng code cụ thể. Thiếu 1 trong 2 → phải LAZY (kể cả P0 nếu chỉ chạm 1 vùng).
- **Global rule** (`~/.claude/rules/`) miễn gate này — luôn always theo bản chất tầng global, KHÔNG bao giờ gán `paths:`.

## Bước 1 — Liệt kê file load tĩnh

```bash
echo "=== GLOBAL RULES (~/.claude/rules/, luôn ALWAYS) ==="
wc -l ~/.claude/rules/*.md 2>/dev/null

echo "=== PROJECT CLAUDE.md ==="
wc -l ./CLAUDE.md 2>/dev/null

echo "=== PROJECT RULES (.claude/rules/) — phân loại ALWAYS/LAZY ==="
cd .claude/rules 2>/dev/null && for f in *.md; do
  [ "$f" = "00-index.md" ] && continue
  n=$(wc -l < "$f")
  # head -20: frontmatter chuẩn ~8 dòng, paths: nằm sau — head -5 báo nhầm lazy thành ALWAYS.
  head -20 "$f" | grep -q "^paths:" && echo "LAZY   $f ($n dòng)" || echo "ALWAYS $f ($n dòng)"
done; cd - >/dev/null

echo "=== MEMORY.md index (auto-memory, luôn load) ==="
p="$PWD"; slug="$(printf '%s' "$p" | sed 's/[\/_]/-/g')"
mdir="$HOME/.claude/projects/${slug}/memory"
[ -f "$mdir/MEMORY.md" ] && wc -l "$mdir/MEMORY.md"

echo "=== Memory con (lazy — chỉ load khi recall, KHÔNG tính vào static budget) ==="
[ -d "$mdir" ] && ls "$mdir"/*.md 2>/dev/null | grep -v MEMORY.md | wc -l
```

Kết quả bước này là danh sách file **thật sự load mỗi session** (global ALWAYS + CLAUDE.md + project rules ALWAYS + MEMORY.md). Memory con và project rules LAZY chỉ ghi nhận số lượng, KHÔNG đọc nội dung ở bước audit (chúng không tốn context nếu không được recall).

Đọc output phần project rules riêng: `ALWAYS` list dài hơn ~4–5 file → gần như chắc có rule nên chuyển lazy.

## Bước 2 — Đọc hết nội dung file ALWAYS-load

Read từng file trong danh sách ALWAYS ở Bước 1 (global rules, CLAUDE.md, project rules ALWAYS, MEMORY.md). Đây là nội dung thật nạp vào context mọi session — audit phải dựa trên nội dung thật, không suy đoán từ tên file.

## Bước 3 — Audit nội dung đã đọc

Với từng file, chấm theo các tiêu chí:

1. **Gate always-load** (theo [[rule-loading-policy]]) — file có vượt CẢ 2: (a) P0 guardrail (vi phạm gây mất data/leak secret/phá scope), (b) áp mọi-turn (không gắn được vào 1 vùng code cụ thể)? Global rule miễn gate này. Project rule/CLAUDE.md section rớt gate → flag CHUYỂN LAZY. Với mỗi rule ALWAYS rớt gate, xác định luôn glob đề xuất:
   - convention vùng X → glob vùng X (vd `"src/**"`, `"lib/**"`)
   - infra/CI → `"infra/**"`, `"Dockerfile*"`, `".github/**"`, `"*.yml"`
   - meta (viết rule) → `".claude/rules/**"`
   - delegate infra → `"scripts/delegate/**"`
   - KHÔNG CHẮC rule chạm đâu → KHÔNG tự đoán glob, KHÔNG mặc định always. Flag HỎI USER vùng áp dụng.
2. **Trùng lặp nội dung** — 2+ file (global vs global, global vs project, hoặc CLAUDE.md vs project rule) nói cùng 1 quy tắc bằng lời khác nhau → flag MERGE, giữ 1 nguồn, còn lại link `[[name]]`.
3. **Có thể derive từ code** — đoạn nào trong CLAUDE.md/rule chỉ mô tả lại thứ đọc được từ code/git log (path, convention hiển nhiên từ cấu trúc dir) → flag XOÁ (theo "what NOT to save" của memory system, áp dụng tương tự cho rule).
4. **MEMORY.md phình** — nếu MEMORY.md > 150 dòng hoặc entry mô tả dài hơn 1 dòng → flag rút gọn (entry chỉ nên là hook 1 dòng trỏ file, không phải nội dung).
5. **Rule/section quá dài cho tần suất dùng** — file > 150 dòng nhưng chỉ áp dụng 1 tình huống hiếm → flag tách phần chi tiết ra file riêng, chỉ giữ tóm tắt + link trong bản always-load (nếu buộc phải always) hoặc chuyển hẳn sang LAZY.
6. **Broken/stale reference** — `[[name]]` trỏ rule/memory không tồn tại, hoặc claim path/lệnh cụ thể đã đổi (verify nhanh bằng grep/Read code thật) → flag SỬA.
7. **LAZY giả** — rule đã có `paths:` nhưng glob quá rộng (`"**"` / `"**/*"`, khớp mọi file → luôn load) → flag thu hẹp glob.

## Bước 4 — Đề xuất tối ưu

Không tự sửa ở bước này. Với mỗi finding ở Bước 3, đề xuất 1 trong:

- **CHUYỂN LAZY** (project rule only) — thêm `paths:` glob đúng vùng.
- **MERGE** — gộp nội dung trùng vào 1 file nguồn, các chỗ còn lại thay bằng `[[name]]`.
- **RÚT GỌN** — cắt nội dung derivable/dài dòng, giữ ý cốt lõi.
- **TÁCH FILE** — chi tiết ít dùng chuyển ra file riêng (project rule LAZY hoặc memory `reference_*`), always-load chỉ giữ pointer.
- **GIỮ NGUYÊN** — vượt gate, không đổi.

Mỗi đề xuất ghi rõ: file, dòng hiện tại → dòng sau tối ưu (ước lượng), lý do 1 dòng.

## Bước 5 — Áp fix (chỉ sau khi user chọn `[a]ll/[s]elect/[n]one`)

Cho mỗi finding **CHUYỂN LAZY** user đồng ý:

1. Thêm khối `paths:` vào frontmatter, ngay trước `metadata:` (quote từng glob):

   ```yaml
   paths:
     - "src/**"
     - "test/**"
   ```

2. **Đồng bộ index** — nếu repo có `.claude/rules/00-index.md` với cột Load, cập nhật cột đó khớp (ALWAYS→LAZY). Quên sync index = policy anti-pattern.
3. Không đổi nội dung body rule, không đổi `name`/`description` trừ khi user yêu cầu.

Cho **MERGE/RÚT GỌN/TÁCH FILE** user đồng ý: Edit trực tiếp theo đề xuất Bước 4, giữ nội dung cốt lõi, thay chỗ trùng bằng `[[name]]`.

Verify lại bằng lệnh Bước 1 — file vừa sửa phải hiện đúng trạng thái mới (LAZY, dòng giảm).

## Report

```markdown
## Context Load Audit — <cwd>, <ngày>

### Static (load mỗi session)
| Nguồn | File | Dòng | Trạng thái |
|---|---|---|---|
| global | orchestrator.md | N | ALWAYS (miễn gate) |
| project rule | git-workflow.md | N | ALWAYS |
| project | CLAUDE.md | N | ALWAYS |
| memory | MEMORY.md | N | ALWAYS (index) |
...

Tổng dòng static: N (global: Na, project rule ALWAYS: Nb, CLAUDE.md: Nc, MEMORY.md: Nd)

### Lazy (không tính vào static, chỉ ghi nhận số lượng)
- Project rules LAZY: N file
- Memory con (feedback/project/reference/user): N file

### Findings
| # | File | Vấn đề | Đề xuất | Ước lượng tiết kiệm |
|---|---|---|---|---|
...

### Chờ user xác nhận
<liệt kê MERGE/CHUYỂN LAZY/TÁCH FILE cần approve trước khi sửa — KHÔNG tự thực hiện>
```

Sau khi user chọn `[a]ll/[s]elect/[n]one`, thực hiện Bước 5, verify lại bằng lệnh Bước 1, và báo dòng context tiết kiệm thật sau khi sửa.
