#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write|MultiEdit). Merge of
# post-edit-syntax-check.sh + remind-lazy-load-health.sh +
# post-write-memory-mirror.sh — all 3 advisory-only, exit 0 always.
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0

# ── 1) syntax check (*.json/*.js/*.mjs/*.cjs) ───────────────────────────────
if [ -f "$file_path" ]; then
  case "$file_path" in
    *.json)
      if ! jq empty "$file_path" 2>/dev/null; then
        echo "⚠️ post-edit-syntax-check: $file_path JSON parse lỗi" >&2
      fi
      ;;
    *.js|*.mjs|*.cjs)
      if ! node --check "$file_path" 2>/dev/null; then
        err=$(node --check "$file_path" 2>&1 | tail -3) || true
        echo "⚠️ post-edit-syntax-check: $file_path — $err" >&2
      fi
      ;;
  esac
fi

# ── 2) lazy-load-health reminder (.claude/rules/*.md) ───────────────────────
# Guarded with || true — REPO/rel computation must not abort other sections under -e.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null)" || REPO=""
if [ -n "$REPO" ]; then
  rel="${file_path#$REPO/}"
  case "$rel" in
    .claude/rules/*.md)
      cat >&2 <<MSG
📋 Reminder: vừa sửa $rel — chạy /lazy-load-health để kiểm tra rule này còn đạt chuẩn lazy-load không (paths: frontmatter, gate P0-mọi-turn). Quyết định sửa hay bỏ qua là của bạn.
MSG
      ;;
  esac
fi

# ── 3) memory-mirror reminder (auto-memory type: project) ──────────────────
case "$file_path" in
  */.claude/projects/*/memory/*.md)
    if [ -f "$file_path" ] && [ "$(basename "$file_path")" != "MEMORY.md" ]; then
      mem_type=$(head -15 "$file_path" | grep -E '^(  )?type:' | head -1 | sed -E 's/^(  )?type:[[:space:]]*//')
      case "$mem_type" in
        *project*)
          echo "📝 post-write-memory-mirror: '$file_path' is project-type memory. Mirror it to repo: .claude/memory/<name>.md (audit for secrets first, per [[memory-mirror]] rule)." >&2
          ;;
      esac
    fi
    ;;
esac

exit 0
