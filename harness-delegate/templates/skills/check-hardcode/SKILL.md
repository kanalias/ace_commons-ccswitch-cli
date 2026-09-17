---
name: check-hardcode
description: Scan code source tìm hardcode secret/credential (token, password, key, connection string, url, ip, domain, email...) rồi báo cáo + gợi ý fix, KHÔNG tự sửa. Dùng khi user hỏi "check hardcode", "quét secret trong code", trước commit/push, hoặc review diff.
user-invocable: true
---

# check-hardcode — quét hardcode secret/credential trong code source

Chỉ **báo cáo + gợi ý fix**. KHÔNG tự sửa — false positive nhiều (biến tên giống secret nhưng không phải, giá trị test/mock, placeholder).

## Phạm vi quét

- Code source đã track + file mới/rename trong diff hiện tại (dùng path glob, không chỉ liệt kê tên file cụ thể).
- Tìm: API key, token, password, private key, connection string có credential, url/ip/domain/email hardcode thay vì đọc từ config/env.

## Loại trừ (false positive nhiều nếu check)

- File config/infra (`.env*`, `*.yml`, `Dockerfile*`, IaC) — không phải code source, có rule riêng.
- Comment/README/docs.
- Code generated (build output, lockfile, codegen).
- Code 3rd-party (`vendor/`, `node_modules/`, submodule).
- Code test (giá trị mock/fixture thường trông giống secret nhưng không phải).

## Cách chạy

1. `git diff --name-only` (hoặc path glob nếu quét toàn repo) → lọc theo phạm vi ở trên.
2. Grep pattern nghi vấn theo file còn lại: `(api[_-]?key|secret|token|password|passwd|private[_-]?key)\s*[:=]\s*['"][^'"]{8,}`, cộng thêm literal IP/domain/email không qua biến config.
3. Với mỗi match: đọc ngữ cảnh quanh dòng, loại bỏ case rõ ràng false positive (test fixture, placeholder như `xxx`/`changeme`/`example.com`) trước khi đưa vào report.

## Report

- Liệt kê: file:line, đoạn code (redact phần giá trị nhạy cảm nếu là secret thật — xem `secrets-no-printout`), lý do nghi hardcode.
- Gợi ý fix: đọc từ env/config hiện có (không đề xuất thêm dependency mới).
- Không tìm thấy gì → báo "không phát hiện hardcode trong phạm vi quét", không tạo report rỗng dài dòng.
