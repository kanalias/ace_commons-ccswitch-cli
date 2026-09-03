---
name: audit-dependency
description: Phát hiện package ecosystem của project và chạy audit read-only vulnerability + outdated-dependency, rồi tóm tắt kết quả. Dùng khi user nói "audit dependencies", "check for vulnerable packages", "outdated deps", hoặc chạy /audit-dependency.
user-invocable: true
---

# audit-dependency — audit read-only vulnerability + outdated dependency

Command này không bao giờ upgrade bất cứ thứ gì. Chỉ detect, chạy, và tóm tắt.

## 1. Phát hiện ecosystem

Check repo root, theo thứ tự này, dừng ở match đầu tiên:

- `pnpm-lock.yaml` → pnpm
- `yarn.lock` → yarn
- `package.json` (không có lockfile pnpm/yarn) → npm
- `uv.lock` hoặc `pyproject.toml` → uv/pip
- `requirements.txt` → pip
- `go.mod` → go
- `Cargo.toml` → cargo
- `Gemfile` → bundler
- `composer.json` → composer

Nếu không match cái nào, không đoán — hỏi user project dùng ecosystem/tooling gì.

## 2. Chạy audit cho ecosystem đã phát hiện

- **npm:** `npm audit` rồi `npm outdated`
- **pnpm:** `pnpm audit` rồi `pnpm outdated`
- **yarn:** `yarn npm audit` (Yarn Berry) hoặc `yarn audit` (Yarn Classic), rồi
  `yarn outdated`
- **pip:** `pip-audit` nếu đã cài, không thì ghi chú thiếu (xem bước 3);
  rồi `pip list --outdated`
- **uv:** `uv pip list --outdated`, cộng `pip-audit` nếu có sẵn trong
  environment
- **go:** `govulncheck ./...` nếu đã cài; rồi `go list -m -u all`
- **cargo:** `cargo audit` nếu đã cài; `cargo outdated` nếu đã cài
- **bundler:** `bundle audit`
- **composer:** `composer audit` rồi `composer outdated`

## 3. Tool bị thiếu

Nếu tool bắt buộc (`pip-audit`, `govulncheck`, `cargo-audit`,
`cargo-outdated`, `bundle-audit`) chưa cài, báo user rõ cách cài
(lệnh package manager theo platform của họ) và vẫn chạy các audit/outdated
check nào không cần tool đó. Không im lặng skip check mà không báo user.

## 4. Tóm tắt

- Nhóm vulnerability theo severity (critical/high/moderate/low), nêu rõ
  package bị ảnh hưởng và version đã fix nếu tool báo có.
- Liệt kê package outdated dạng `current → latest`, đánh dấu package nào
  cũng có vulnerability đang mở.
- Đề xuất upgrade nào an toàn (patch/minor) vs rủi ro (major, có khả năng breaking).

## 5. Không tự upgrade

Command này chỉ read-only. Không bao giờ chạy lệnh upgrade/install
(`npm update`, `cargo update`, `pip install -U`, v.v) như một phần của
audit này — trình bày tóm tắt và hỏi user trước khi thay đổi bất cứ gì.
