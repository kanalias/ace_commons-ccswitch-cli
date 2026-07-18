---
name: rule-loading-policy
description: Project rule chỉ always-load khi P0-mọi-turn; còn lại BẮT BUỘC paths: lazy-load để mọi project mở lên không nuốt context lớn
status: live
updated: 2026-07-16
metadata:
  type: reference
---

# Context Budget — Project rule loading discipline (cross-project)

Mỗi session nuốt vào context: global rules (always) + project rules + CLAUDE.md + MEMORY.md index. Project rule **always-load** không kiểm soát → mọi project mở lên bơm hàng trăm dòng bất kể task → context lớn, degrade recall (xem [[token-budget]]).

Quy tắc: **project rule mặc định LAZY (`paths:`)**. Chỉ always-load nếu vượt được gate P0 dưới đây.

## Gate — rule nào được always-load

Always-load CHỈ khi rule đúng **cả 2**:

1. **P0 guardrail** — vi phạm gây mất data / leak secret / phá scope (không phải "nên đọc").
2. **Áp mọi-turn** — không gắn được vào 1 vùng code cụ thể (scope isolation, secret guard, budget hook, mục lục index).

Ví dụ được always: `00-index` (mục lục), scope-isolation, vault/secret guard, token-budget hook.

Mọi rule khác → **LAZY**. Kể cả P0 nếu chỉ chạm 1 vùng (vd test-mandatory `paths: test,src`, module-md `paths: modules/**`).

## Gán `paths:` — cách làm

```yaml
---
paths:
  - "src/app/schedulers/**"   # glob, quote từng dòng
  - "server.js"
---
```

- Rule về convention code vùng X → `paths: <vùng X>`.
- Rule về infra/CI → `paths: infra/**,Dockerfile*,.github/**,*.yml`.
- Rule về cách viết rule (meta) → `paths: .claude/rules/**`.
- Rule về delegate infra → `paths: scripts/delegate/**`.
- Rule về team/skill ownership → `paths: <skill dir>`.

Không chắc rule chạm đâu → hỏi user, KHÔNG mặc định always (mặc định always = rò rỉ context âm thầm).

## Global rule — KHÔNG bao giờ `paths:`

Global (`~/.claude/rules/`) luôn always mọi project — đó là bản chất tầng global. Đừng gán `paths:` cho global. Muốn giảm global → chắt nội dung ngắn, ref chi tiết qua `[[...]]`, KHÔNG lazy-hoá.

## Audit định kỳ mỗi project

```bash
cd <repo>/.claude/rules
for f in *.md; do head -5 "$f" | grep -q "^paths:" && echo "LAZY  $f" || echo "ALWAYS $f"; done
```

`ALWAYS` list dài hơn ~4-5 file → soi lại: file nào không vượt gate P0-mọi-turn → chuyển lazy. Cập nhật cột Load trong `00-index.md` khớp.

## Tránh

- ❌ Rule mới mặc định always "cho chắc" — mặc định phải LAZY.
- ❌ Gán `paths:` cho global rule.
- ❌ Rule 200+ dòng always-load (module-md, ai-gateway, ott → luôn lazy).
- ❌ Quên update `00-index.md` cột Load sau khi đổi frontmatter.
