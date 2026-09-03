---
name: dep-ladder-check
description: Đi qua thang build-vs-buy trước khi thêm dependency mới hoặc viết code mới không tầm thường. Dùng trước khi chạy npm install / pip install / go get / cargo add / gem install / composer require, trước khi thêm một thư viện dependency mới, hoặc trước khi viết một abstraction/helper mới không tầm thường.
user-invocable: true
---

# dep-ladder-check — thang build-vs-buy trước khi thêm code hoặc dependency

Dừng ở nấc thang đầu tiên giải quyết được vấn đề. Đừng nhảy thẳng lên "viết một
thư viện" hoặc "thêm một dependency" mà chưa kiểm tra các nấc rẻ hơn trước.

## 1. Cái này có cần tồn tại không? (YAGNI)

Nó đang giải quyết một vấn đề thật, hiện tại, hay một vấn đề giả định trong tương
lai? Nếu nhu cầu chỉ mang tính suy đoán ("có thể sau này cần"), dừng ở đây — đừng
xây nó.

## 2. Kiểm tra stdlib

Standard library của ngôn ngữ đã làm được việc này chưa?

- **Node:** `fs`, `path`, `crypto`, `structuredClone`, `AbortController`,
  các method `Array.prototype` (`flatMap`, `group` qua `Object.groupBy` ở
  runtime mới hơn), `util.parseArgs`. Kiểm tra phiên bản Node đích — giả định
  "cần một thư viện" thường đã lỗi thời một khi runtime hỗ trợ nó natively.
- **Python:** `itertools`, `functools`, `pathlib`, `dataclasses`, `enum`,
  `contextlib`, `json`, `re`.
- **Go:** stdlib thường là đủ — chạy `go doc <pkg>` trước khi với tới một
  module bên thứ ba.
- **Ruby:** stdlib (`Set`, `Comparable`, `Struct`, `ostruct`) trước khi dùng gem.

## 3. Tính năng native của platform

Ưu tiên một primitive của platform hơn một thư viện cấp ứng dụng:

- CSS thay vì một thư viện JS — flexbox/grid layout, `:has()`, container
  queries, `prefers-color-scheme`.
- Ràng buộc DB thay vì validation cấp ứng dụng — `UNIQUE`, `CHECK`, `FOREIGN
  KEY ... ON DELETE`.
- Tính năng OS/runtime thay vì một thư viện — `cron`/`launchd` thay cho một
  package scheduler, `flock` thay cho một thư viện file-locking.

## 4. Dependency đã cài sẵn

Trước khi thêm một package mới, kiểm tra xem một direct dependency hiện có đã
phơi bày khả năng này chưa:

- npm/pnpm/yarn → `dependencies`/`devDependencies` trong `package.json`
- Python → deps trong `requirements.txt` hoặc `pyproject.toml`
- Go → block `require` trong `go.mod`
- Rust → `[dependencies]` trong `Cargo.toml`
- Ruby → `Gemfile`

## 5. Một dòng

Cái này có thể là một biểu thức đơn hoặc một hàm nhỏ thay vì một thư viện không?
Debounce khoảng 6 dòng, slugify là một regex, deep clone là `structuredClone`.
Nếu toàn bộ mục đích của thư viện chỉ là một hàm, inline hàm đó.

## 6. Code custom tối thiểu

Chỉ khi không nấc nào ở trên áp dụng được: viết implementation đúng nhỏ nhất.
Đừng bỏ qua edge case hay error handling mà một thư viện đã xử lý tại trust
boundary (input rỗng, encoding, truy cập đồng thời).

## Khi một dependency mới THỰC SỰ chính đáng

Thang ở trên dành cho plumbing, không phải cho logic quan trọng về tính đúng đắn
hay bảo mật. Dùng một thư viện đã được kiểm chứng cho những thứ này — đừng coi
chúng là ứng viên một-dòng, dù một phiên bản ngây thơ trông có vẻ ngắn:

- Cryptography, hashing, sinh random token
- Ký/xác minh JWT
- Sanitize HTML/SQL và xây query an toàn với injection
- Toán học ngày/timezone (DST, giây nhuận, parse theo locale)
- Parse Markdown/HTML/YAML
- Password hashing (bcrypt/argon2/scrypt — không bao giờ tự viết tay)

## Gắn cờ vi phạm hiện có

Khi review code, nếu phát hiện một dependency được thêm cho thứ mà một lời gọi
stdlib hoặc một dòng đã giải quyết được, gắn cờ và đề xuất gỡ bỏ —
đừng gỡ nó tự động. Gỡ một dependency có thể phá vỡ các call site khác;
hỏi user trước.
