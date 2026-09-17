---
name: lazy-load-audit
description: Audit project rule files trong .claude/rules — phân loại ALWAYS vs LAZY load, recommend rule nào nên chuyển sang lazy (paths:), hướng dẫn setup frontmatter + đồng bộ index. Chạy /lazy-load-audit, hoặc khi user hỏi "rule nào đang always-load", "giảm context session", "kiểm tra lazy load", "rule nào nên lazy".
user-invocable: true
---

# lazy-load-audit — soi rule load discipline (ALWAYS vs LAZY)

Mỗi session nuốt vào context: global rules (always) + **project rules** + CLAUDE.md + MEMORY.md index. Project rule always-load không kiểm soát → mọi task bơm hàng trăm dòng bất kể có liên quan không → context lớn, degrade recall. Skill này audit rule nào đang always-load, chấm theo gate, recommend cái nào nên chuyển LAZY, và setup giúp.

Nguồn chân lý: `rule-loading-policy` trong `~/.claude/rules/` (global, không nằm trong project — installer này không cài rule đó). Skill KHÔNG lặp lại policy — chỉ **áp dụng** thành audit chạy được. Gate/định nghĩa lệch policy → theo policy.

## Khái niệm

- **LAZY** — rule có `paths:` (list glob) trong frontmatter. Chỉ load khi task chạm file khớp glob. Mặc định BẮT BUỘC cho project rule.
- **ALWAYS** — rule KHÔNG có `paths:`. Load mọi turn. Chỉ hợp lệ khi vượt gate P0-mọi-turn.
- **Gate always-load (đúng CẢ 2):** (1) P0 guardrail — vi phạm gây mất data / leak secret / phá scope; (2) áp mọi-turn — không gắn được vào 1 vùng code cụ thể. Thiếu 1 trong 2 → phải LAZY (kể cả P0 nếu chỉ chạm 1 vùng).
- **Global rule** (`~/.claude/rules/`) KHÔNG audit ở đây — luôn always theo bản chất tầng global, KHÔNG bao giờ gán `paths:`.

## Bước 1 — Liệt kê ALWAYS vs LAZY

Chạy trong repo (chỉ project rules):

```bash
cd .claude/rules 2>/dev/null || { echo "no .claude/rules — bỏ qua"; exit 0; }
# head -20: frontmatter chuẩn ~8 dòng, paths: nằm sau — head -5 báo nhầm lazy thành ALWAYS.
for f in *.md; do
  [ "$f" = "00-index.md" ] && continue
  head -20 "$f" | grep -q "^paths:" && echo "LAZY   $f" || echo "ALWAYS $f"
done
```

Đọc output, đếm số ALWAYS. `ALWAYS` list dài hơn ~4–5 file → gần như chắc có rule nên chuyển lazy.

## Bước 2 — Chấm từng ALWAYS theo gate → recommend

Với MỖI file ALWAYS, mở đọc (frontmatter + heading) rồi phân loại:

- **GIỮ ALWAYS** — vượt cả 2 gate. Điển hình: index/mục lục (`00-index`), scope-isolation, secret/vault guard, token-budget hook. Không đề xuất đổi.
- **CHUYỂN LAZY** — chỉ chạm 1 vùng code cụ thể, HOẶC không phải P0 guardrail (chỉ "nên đọc"). Điển hình: convention code 1 module, test-mandatory, infra/CI, meta (cách viết rule). Đề xuất `paths:` bám đúng vùng rule điều chỉnh:
  - convention vùng X → glob vùng X (vd `"src/**"`, `"lib/**"`)
  - infra/CI → `"infra/**"`, `"Dockerfile*"`, `".github/**"`, `"*.yml"`
  - meta (viết rule) → `".claude/rules/**"`
  - delegate infra → `"scripts/delegate/**"`
- **KHÔNG CHẮC rule chạm đâu** → KHÔNG tự đoán glob, KHÔNG mặc định always. Hỏi user vùng áp dụng trước khi đề xuất (mặc định always = rò rỉ context âm thầm).

Cũng soi LAZY hiện có: glob quá rộng (`"**"` / `"**/*"`) = lazy giả (khớp mọi file → luôn load). Flag lại, đề xuất thu hẹp.

## Bước 3 — Setup rule chuyển sang LAZY

Với mỗi rule user đồng ý chuyển (confirm trước khi sửa file):

1. Thêm khối `paths:` vào frontmatter, ngay trước `metadata:` (quote từng glob):
   ```yaml
   paths:
     - "src/**"
     - "test/**"
   ```
2. **Đồng bộ index** — nếu repo có `.claude/rules/00-index.md` với cột Load, cập nhật cột đó khớp (ALWAYS→LAZY). Quên sync index = policy anti-pattern.
3. Không đổi nội dung body rule, không đổi `name`/`description` trừ khi user yêu cầu.

Verify lại bằng lệnh Bước 1 — file vừa sửa phải hiện `LAZY`.

## Report

- Bảng: mỗi rule → trạng thái hiện tại (ALWAYS/LAZY) → khuyến nghị (GIỮ / CHUYỂN LAZY + glob đề xuất / HỎI USER) → lý do 1 dòng (gate nào rớt).
- Tổng: bao nhiêu ALWAYS, bao nhiêu nên chuyển, ước lượng dòng context tiết kiệm mỗi session.
- Nếu đã sửa file: liệt kê file đã đổi + xác nhận index đã sync + kết quả verify Bước 1.
- Rule "HỎI USER": nêu rõ cần user xác nhận vùng áp dụng nào.
