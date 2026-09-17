---
name: sync-template
description: Sửa xong bất kỳ harness surface LIVE (.claude/ + scripts/delegate/ + .git/hooks/pre-push) phải mirror ngược vào harness/templates/ — template là source-of-truth để install.sh cài sang project khác. LAZY, load khi chạm harness surface hoặc template.
status: live
updated: 2026-07-27
paths:
  - ".claude/hooks/**"
  - ".claude/agents/**"
  - ".claude/commands/**"
  - ".claude/skills/**"
  - ".claude/rules/**"
  - "harness/**"
  - "scripts/delegate/**"
metadata:
  type: reference
---

# Sync live harness → template (BẮT BUỘC)

`harness/templates/` là **source-of-truth** để `install.sh` cài harness sang project khác. Live `.claude/` (+ `scripts/delegate/`, `.git/hooks/pre-push`) chỉ là bản đã cài của repo này. Sửa live mà không mirror → template stale → mọi project cài sau nhận bản cũ.

**Quy tắc:** sửa/thêm/xoá bất kỳ file harness LIVE → mirror ngược vào template **cùng commit**. KHÔNG để 2 bên diverge qua session.

## Mapping (live ↔ template)

| Live | Template |
|---|---|
| `.claude/hooks/*.sh` | `harness/templates/hooks/*.sh` |
| `.claude/agents/*.md` | `harness/templates/agents/*.md` |
| `.claude/commands/*.md` | `harness/templates/commands/*.md` |
| `.claude/skills/<name>/` | `harness/templates/skills/<name>/` |
| `.claude/rules/common/*.md` | `harness/templates/rules/common/*.md` |
| `.claude/rules/project/*.md` | `harness/templates/rules/project/*.md` |
| `scripts/delegate/*` | `harness/templates/scripts/delegate/*` |
| `.git/hooks/pre-push` | `harness/templates/git-hooks/pre-push` |

## Reverse-bake token (QUAN TRỌNG — không copy thô)

Install-time `install.sh` thay `@@TOKEN@@` → giá trị repo. Mirror ngược phải **đảo lại**: giá trị baked của repo này → `@@TOKEN@@`. Copy thô = leak giá trị repo cụ thể vào template dùng chung.

| Baked (live repo) | Token (template) |
|---|---|
| `<working-branch>` (vd `main`) | `@@BRANCH@@` |
| `<repo-slug>` (vd `my-project`) | `@@PROJECT_SLUG@@` |
| core-dir literals (src…) | `@@CORE_DIRS_*@@` (YAML/CASE/ALT/HUMAN) |
| test command | `@@TEST_CMD@@` |
| model default từ `.env` | `@@GEMINI_MODEL_DEFAULT@@` / `@@CODEX_MODEL_DEFAULT@@` / `@@DEEPSEEK_MODEL_DEFAULT@@` |

Token đầy đủ: `grep -rhoE '@@[A-Z_]+@@' harness/templates | sort -u`.

## Overwrite policy (khớp install.sh)

- `templates/rules/common/` — install **overwrite** khi re-sync → sửa nội dung guardrail chỉ ở template, KHÔNG sửa live trực tiếp (live sẽ bị đè lần cài sau).
- `templates/rules/project/` — install **giữ nguyên** nếu file đã tồn tại ở target → rule riêng repo an toàn ở live, vẫn mirror để project mới có bản seed.

## Verify sau mirror

```bash
# Không còn giá trị repo-specific lọt vào template
grep -rn "@@PROJECT_SLUG@@" harness/templates >/dev/null && echo "token present" || echo "check token"
# Installer chạy all-defaults không lỗi (dry run)
( cd harness && bash install.sh </dev/null >/dev/null 2>&1 ) && echo "install OK" || echo "install FAIL"
```

## Tránh

- ❌ Sửa live hook/rule/skill rồi quên template → drift âm thầm.
- ❌ Copy live → template không reverse-bake (leak `dev`/slug/model vào bản dùng chung).
- ❌ Sửa `common/` ở live (bị đè lần cài sau) — sửa ở template.
