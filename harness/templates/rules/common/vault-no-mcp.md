---
name: vault-no-mcp
description: P0 GLOBAL — Vault CRUD KHÔNG qua MCP connector Anthropic; dùng Notion REST API direct + bootstrap token LOCAL
status: live
updated: 2026-07-16
metadata:
  type: reference
---

# Vault CRUD KHÔNG qua MCP connector Anthropic (P0 GLOBAL)

⭐⭐⭐ Áp dụng MỌI project. Ngang secrets-no-printout.

## Cấm tuyệt đối

❌ Dùng `mcp__claude_ai_Notion__*` (notion-search / notion-fetch / notion-update-page / notion-query-data-sources / notion-create-pages) để search / fetch / update / create row trong vault DB chứa secrets.

❌ **Lý do:** MCP connector route qua Anthropic backend → row name + value (kể cả masked) vào Anthropic logs + có thể vào training data. Vault phải isolated khỏi mọi external infra ngoài Notion API direct + LOCAL machine.

## Cách đúng

1. **Direct Notion REST API** qua bootstrap token LOCAL (`curl` + `Authorization: Bearer $<VAULT_BOOTSTRAP_TOKEN>`, header `Notion-Version` lấy version stable mới nhất — khai báo trong `.env`/config repo, không hardcode ở rule). Đọc value từ file vault (không paste inline), `unset` sau dùng.
2. **Script Node** `scripts/vault/update-row.js` — dùng `@notionhq/client` + bootstrap token, không print value, chỉ OK/FAIL.
3. **User tự update qua Notion UI** (an toàn nhất) — AI chỉ cung cấp direct URL row + tên field + source value reference.

## Edge cases

- Read-only check (verify row tồn tại): vẫn KHÔNG dùng MCP — curl + extract `id`.
- Schema discovery: `GET /v1/databases/{id}` qua curl, không MCP fetch.
- Non-secret row trong vault DB: vẫn áp rule — vault DB = boundary, không phân loại row-by-row.

> **Project-specific:** env var name (`<PROJECT>_NOTION_VAULT_DB_ID`, bootstrap token name), vault DB id khai báo trong repo `.claude/rules/` + `.env`. Xem `.claude/rules/vault-<project>.md` nếu có.
