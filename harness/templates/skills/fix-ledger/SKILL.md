---
name: fix-ledger
description: Ghi lại fix/feature quan trọng đã merge vào .claude/fix-ledger.md (repo-tracked, không phải Claude memory global) để lần merge sau không vô tình đè mất fix — VÀ check ledger trước khi merge branch khác vào working branch/protected branch. Dùng khi 1 bugfix/feature có rủi ro bị branch cũ đè lại vừa xong (test pass), hoặc trước git merge, hoặc user nói "ghi vào fix ledger", "check có bị đè fix không", "nhớ tính năng này tránh mất khi merge".
user-invocable: true
---

# fix-ledger — ledger chống merge đè lên fix/feature đã xong

Khác với Claude auto-memory (`~/.claude/projects/.../memory`, scoped theo máy/user, không theo git) — `.claude/fix-ledger.md` là file **tracked trong git**, đi theo branch/commit, để lần merge sau đọc được và so khớp.

## Chế độ RECORD — ghi entry sau khi fix/feature xong

Trigger: 1 bugfix đã từng xảy ra thật xong (test pass, sắp/đã commit) VÀ có rủi ro bị branch cũ/stale đè lại khi merge sau này — HOẶC user yêu cầu rõ. KHÔNG ghi cho mọi commit (chore/refactor/feature không có rủi ro bị đè thì bỏ qua — ledger phình vô nghĩa làm mất giá trị lọc).

1. Xác định: đây có phải fix cho bug đã xảy ra thật, hoặc feature dễ bị branch cũ/hotfix/conflict-resolve-sai đè lại không? Không rõ → hỏi user trước khi ghi, không tự đoán.
2. Soạn entry (không tạo schema JSON, markdown đủ — agent đọc, không phải script parse):
   ```
   ## <YYYY-MM-DD> — <tên ngắn fix/feature>
   - **Files:** path/to/file.ext (function/region nếu có)
   - **Root cause / behavior:** 1-2 câu — bug gì hoặc feature giữ hành vi gì
   - **Guard:** pattern/đoạn code cụ thể grep được PHẢI còn tồn tại, hoặc trỏ tới test đã viết (path:test-name) — ưu tiên tái dùng test có sẵn từ TDD (`skill-superpowers`), KHÔNG tạo verify mechanism mới trùng lặp
   - **Verify:** lệnh chạy xác nhận guard còn đúng
   ```
3. File `.claude/fix-ledger.md` chưa tồn tại → tạo mới với 1 dòng mô tả đầu file + entry đầu tiên. Đã tồn tại → append cuối file, không sửa entry cũ.
4. Show entry cho user, hỏi xác nhận trước khi ghi (giống `auto-commit` — chủ động soạn sẵn, không tự ý ghi khi chưa hỏi).

## Chế độ CHECK — trước khi merge branch khác vào working/protected branch

Trigger: trước `git merge <branch>` (xem [[git-workflow]], mọi điểm merge vào `dev` hoặc protected branch) — HOẶC user hỏi "check fix ledger", "có bị đè fix không".

1. `.claude/fix-ledger.md` không tồn tại/rỗng → báo "chưa có ledger, không có gì để check", dừng — không tạo file rỗng trước.
2. Lấy danh sách file sắp đổi: `git diff --name-only <target>...<branch>` (branch sắp merge vào target hiện tại).
3. Đọc ledger, với mỗi entry có `Files:` overlap danh sách trên: kiểm tra guard pattern còn tồn tại trong bản của `<branch>` không (`git show <branch>:<file> | grep '<guard-pattern>'`), hoặc nếu entry trỏ test — chạy/soát test đó trên trạng thái sau merge (dry-run merge vào worktree tạm nếu cần, không merge thật vào working tree đang dùng).
4. Entry nào guard/test biến mất hoặc đổi khác → flag "có khả năng merge này đè lên fix: <tên entry>", show diff đoạn liên quan cho user quyết định — KHÔNG tự block merge, KHÔNG tự sửa. Đây là skill cảnh báo, không phải hard gate.
5. Không entry nào overlap → báo "không phát hiện overlap với ledger", cho phép merge tiếp tục theo flow `git-workflow` bình thường.

## Không làm

- Không ghi ledger cho mọi commit — chỉ fix/feature có rủi ro bị đè.
- Không tự block/huỷ merge — chỉ cảnh báo, user quyết.
- Không tạo schema/parser riêng — markdown thuần, agent đọc trực tiếp.
- Không trùng lặp với test suite — guard/verify ưu tiên trỏ tới test đã có.

## Report

- RECORD: entry đã ghi (title + file ledger).
- CHECK: bảng entry nào overlap → guard còn đúng hay flag, kèm khuyến nghị.
