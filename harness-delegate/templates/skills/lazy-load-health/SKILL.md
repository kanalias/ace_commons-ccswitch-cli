---
name: lazy-load-health
description: Tự động kiểm tra + SỬA project rule files trong .claude/rules không đạt chuẩn lazy-load. Scan ALWAYS vs LAZY, chấm theo gate, auto thêm paths: cho rule phân loại chắc chắn + đồng bộ index, flag case không chắc glob. Chạy /lazy-load-health, hoặc khi user hỏi "rule nào đang always-load", "giảm context session", "kiểm tra + sửa lazy load", "rule nào nên lazy".
user-invocable: true
---

# lazy-load-health — auto kiểm tra + sửa rule load discipline

Mỗi session nuốt vào context: global rules (always) + **project rules** + CLAUDE.md + MEMORY.md index. Project rule always-load không kiểm soát → mọi task bơm hàng trăm dòng bất kể có liên quan không → context lớn, degrade recall. Skill này **tự động scan rule không đạt chuẩn lazy-load, sửa luôn những case phân loại chắc chắn** (thêm `paths:` + đồng bộ index), chỉ dừng hỏi khi không tự suy được glob an toàn.

Nguồn chân lý: `rule-loading-policy` trong `~/.claude/rules/` (global, không nằm trong project — installer này không cài rule đó). Skill KHÔNG lặp lại policy — chỉ **áp dụng** thành check+fix chạy được. Gate/định nghĩa lệch policy → theo policy.

## Khái niệm

- **LAZY** — rule có `paths:` (list glob) trong frontmatter. Chỉ load khi task chạm file khớp glob. Mặc định BẮT BUỘC cho project rule.
- **ALWAYS** — rule KHÔNG có `paths:`. Load mọi turn. Chỉ hợp lệ khi vượt gate P0-mọi-turn.
- **Gate always-load (đúng CẢ 2):** (1) P0 guardrail — vi phạm gây mất data / leak secret / phá scope; (2) áp mọi-turn — không gắn được vào 1 vùng code cụ thể. Thiếu 1 trong 2 → phải LAZY (kể cả P0 nếu chỉ chạm 1 vùng).
- **Global rule** (`~/.claude/rules/`) KHÔNG audit ở đây — luôn always theo bản chất tầng global, KHÔNG bao giờ gán `paths:`.

## "Không đạt chuẩn" = trigger sửa

Một project rule cần sửa nếu rơi vào 1 trong 3:

1. **ALWAYS nhưng rớt gate** — không phải P0 guardrail, HOẶC chỉ chạm 1 vùng code cụ thể → phải chuyển LAZY (thêm `paths:`).
2. **Fake-lazy** — có `paths:` nhưng glob quá rộng (`"**"` / `"**/*"` / `"*"`) → khớp mọi file → luôn load = ALWAYS trá hình → phải thu hẹp glob.
3. **Index lệch** — `00-index.md` có cột Load nhưng ghi sai trạng thái thật của rule sau khi sửa → phải sync.

## Bước 1 — Auto-scan (chỉ project rules)

Chạy trong repo, liệt kê trạng thái + cờ fake-lazy:

```bash
cd .claude/rules 2>/dev/null || { echo "no .claude/rules — bỏ qua"; exit 0; }
# head -20: frontmatter chuẩn ~8 dòng, paths: nằm sau — head -5 báo nhầm lazy thành ALWAYS.
for f in *.md; do
  [ "$f" = "00-index.md" ] && continue
  hdr="$(head -20 "$f")"
  if echo "$hdr" | grep -q "^paths:"; then
    # fake-lazy: glob rộng khớp mọi file
    if echo "$hdr" | grep -qE '^[[:space:]]*-[[:space:]]*"?(\*\*|\*\*/\*|\*)"?[[:space:]]*$'; then
      echo "FAKE-LAZY $f"
    else
      echo "LAZY      $f"
    fi
  else
    echo "ALWAYS    $f"
  fi
done
```

Đọc output: mỗi `ALWAYS` và `FAKE-LAZY` là candidate cần sửa. Nếu 0 candidate → báo "đã đạt chuẩn" và dừng.

## Bước 2 — Chấm từng candidate theo gate

Với MỖI file `ALWAYS`/`FAKE-LAZY`, mở đọc (frontmatter + heading) rồi phân loại thành 1 trong 3 nhóm:

- **GIỮ ALWAYS** — vượt cả 2 gate. Điển hình: index/mục lục (`00-index`), scope-isolation, secret/vault guard, token-budget hook. KHÔNG sửa.
- **SỬA ĐƯỢC (confident)** — nội dung rule rõ ràng chỉ chạm 1 vùng code / 1 loại infra → glob suy ra chắc chắn từ bảng dưới:
  - convention vùng X → glob vùng X (vd `"src/**"`, `"lib/**"`)
  - test/spec → `"test/**"`, `"**/*.test.*"`, `"spec/**"`
  - infra/CI → `"infra/**"`, `"Dockerfile*"`, `".github/**"`, `"*.yml"`
  - meta (viết rule) → `".claude/rules/**"`
  - delegate infra → `"scripts/delegate/**"`
- **KHÔNG CHẮC glob** — không suy được vùng áp dụng an toàn từ nội dung rule. Case này **KHÔNG auto-sửa** (glob đoán sai quá hẹp → rule không bao giờ load khi cần = tệ hơn ALWAYS). Ghi vào danh sách flag để user quyết.

## Bước 3 — Auto-fix (nhóm confident) + flag (nhóm không chắc)

Đây là bước có thay đổi file. Làm đúng thứ tự sau cho từng rule thuộc nhóm **SỬA ĐƯỢC (confident)** — không cần hỏi confirm từng file (đó là mục đích "tự động"):

1. Thêm khối `paths:` vào frontmatter, ngay trước `metadata:` (quote từng glob):
   ```yaml
   paths:
     - "src/**"
     - "test/**"
   ```
   Với **FAKE-LAZY**: thay glob rộng bằng glob hẹp đúng vùng, KHÔNG thêm block mới.
2. **Đồng bộ index** — nếu repo có `.claude/rules/00-index.md` với cột Load, cập nhật cột đó khớp (ALWAYS→LAZY). Quên sync index = policy anti-pattern.
3. Không đổi nội dung body rule, không đổi `name`/`description` trừ khi user yêu cầu.

Với nhóm **KHÔNG CHẮC glob**: KHÔNG chạm file. Chỉ nêu trong report để user xác nhận vùng áp dụng — sửa ở lần chạy sau khi user cho glob.

## Verify

Chạy lại lệnh Bước 1. Mọi file vừa auto-fix phải hiện `LAZY` (không còn `ALWAYS`/`FAKE-LAZY`). File flag vẫn giữ nguyên trạng thái cũ là đúng.

## Report

- Bảng: mỗi rule → trạng thái trước (ALWAYS/FAKE-LAZY/LAZY) → hành động (ĐÃ SỬA + glob đã ghi / GIỮ ALWAYS / FLAG chờ user) → lý do 1 dòng (gate nào rớt).
- Tổng: bao nhiêu candidate, bao nhiêu ĐÃ auto-sửa, bao nhiêu FLAG chờ user, ước lượng dòng context tiết kiệm mỗi session.
- Xác nhận: index đã sync + kết quả verify Bước 1 (0 ALWAYS ngoài các rule GIỮ ALWAYS hợp lệ).
- Danh sách FLAG: mỗi rule nêu rõ cần user xác nhận vùng áp dụng nào (không tự đoán glob).
