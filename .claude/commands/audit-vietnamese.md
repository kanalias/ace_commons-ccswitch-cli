---
name: audit-vietnamese
description: Dịch nội dung file .md sang tiếng Việt tại path do user chỉ định. Dùng khi user gõ /audit-vietnamese <path> hoặc yêu cầu "dịch file .md này sang tiếng Việt".
user-invocable: true
---

# /audit-vietnamese — dịch file .md sang tiếng Việt

## Args

```text
/audit-vietnamese <path-or-glob>
```

`path-or-glob` bắt buộc — không hardcode scope mặc định. Thiếu arg → hỏi user path/glob trước khi làm gì (không tự đoán, không quét toàn repo).

## Giữ nguyên, KHÔNG dịch

- Code identifier: tên hàm, biến, class, export.
- File path, URL, command shell, error string nguyên văn.
- Nội dung bên trong code block (```` ``` ````) — chỉ dịch comment trong code block nếu comment đó là văn xuôi giải thích, không đụng code thật.
- Frontmatter keys (`name`, `paths`, `user-invocable`, `allowed-tools`, `metadata`, ...) và mọi value không phải văn xuôi tự do (slug, glob, boolean).

## Dịch

- Toàn bộ văn xuôi (heading, đoạn văn, bullet, bảng, chú thích).
- Frontmatter field `description:` — dịch value sang tiếng Việt, giữ nguyên key.

## Quy trình

1. Resolve `path-or-glob` → danh sách file `.md` thật có. Không match file nào → báo user, dừng.
2. Đọc từng file, dịch trực tiếp (không hỏi confirm từng đoạn) theo quy tắc giữ nguyên/dịch ở trên.
3. Ghi lại bằng Edit — giữ cấu trúc heading/bảng/code block y nguyên, chỉ thay nội dung văn xuôi.
4. Số file ≤ 3 và mỗi file < 200 dòng → Opus tự dịch trực tiếp (size-S/M nhỏ).
   Số file nhiều hoặc dài → M-mechanical (dịch không đổi logic/code) → `delegate-deepseek` trước, fallback `delegate-sonnet`, không quá 2 lần fallback (xem `[[orchestrator]]`).
5. Sau khi ghi xong toàn bộ file trong scope, verify (3 bước):

   **a. `git diff --check`** — whitespace/conflict marker cơ bản:
   ```sh
   git diff --check
   git diff --stat -- <path-or-glob>
   ```

   **b. Code block + frontmatter key bất biến** — so từng file đã tracked (`git show HEAD:<file>`) với bản mới, chỉ diff phần fenced code block (```` ``` ````) và frontmatter key (loại trừ value của `description:`). Khác nhau dù 1 ký tự → FAIL, in rõ file + block/key lệch, KHÔNG tự sửa — báo user. File mới (chưa tracked) bỏ qua bước này (không có bản gốc để so).

   Script tối thiểu (Node stdlib, không thêm dependency):
   ```js
   const fs = require('fs');
   const { execSync } = require('child_process');
   function extractBlocks(text) {
     return [...text.matchAll(/```[\s\S]*?```/g)].map(m => m[0]);
   }
   function extractFrontmatter(text) {
     const m = text.match(/^---\n([\s\S]*?)\n---/);
     if (!m) return '';
     return m[1].split('\n').filter(l => !l.startsWith('description:')).join('\n');
   }
   for (const file of process.argv.slice(2)) {
     let before;
     try { before = execSync(`git show HEAD:${file}`, { encoding: 'utf8' }); }
     catch { console.log(`SKIP (untracked): ${file}`); continue; }
     const after = fs.readFileSync(file, 'utf8');
     const bBlocks = extractBlocks(before), aBlocks = extractBlocks(after);
     const bFm = extractFrontmatter(before), aFm = extractFrontmatter(after);
     const codeOk = JSON.stringify(bBlocks) === JSON.stringify(aBlocks);
     const fmOk = bFm === aFm;
     console.log(`${file}: code-blocks=${codeOk ? 'OK' : 'MISMATCH'} frontmatter-keys=${fmOk ? 'OK' : 'MISMATCH'}`);
   }
   ```
   Chạy: `node -e "<script trên>" -- <file1> <file2> ...` hoặc lưu tạm rồi xoá sau verify.

   **c. Leftover English sweep** — report-only, không auto-fix (false positive cao: acronym, tên riêng). Strip code block trước khi grep:
   ```sh
   for f in <file...>; do
     sed '/^```/,/^```/d' "$f" | grep -noE '\b(the|and|should|must|when|before|after|does|this)\b' | sed "s#^#$f:#"
   done
   ```
   Có match → liệt kê file:line:từ trong report, để user tự quyết định, không tự sửa thêm vòng 2.

## Report

```text
AUDIT-VIETNAMESE — <path-or-glob>
Files dịch: <N>
1. <path> — <số dòng đổi>
...

Verify:
- git diff --check: <PASS/FAIL>
- Code block bất biến: <PASS/FAIL, liệt kê file lệch nếu có>
- Frontmatter key bất biến: <PASS/FAIL>
- Leftover English sweep: <N match, liệt kê file:line hoặc "sạch">
```

Không tự commit/push. User tự quyết sau khi xem diff.
