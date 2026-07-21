#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write).
# Nếu file vừa edit là *.js / *.mjs / *.cjs / *.json, chạy quick syntax check.
# Non-blocking warning để model thấy + sửa, KHÔNG block (chỉ check node-parseable file).
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)
if ! command -v jq >/dev/null 2>&1; then exit 0; fi

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0
[ ! -f "$file_path" ] && exit 0

case "$file_path" in
  *.json)
    if ! jq empty "$file_path" 2>/dev/null; then
      echo "⚠️ post-edit-syntax-check: $file_path JSON parse lỗi" >&2
    fi
    ;;
  *.js|*.mjs|*.cjs)
    if ! node --check "$file_path" 2>/dev/null; then
      err=$(node --check "$file_path" 2>&1 | tail -3)
      echo "⚠️ post-edit-syntax-check: $file_path — $err" >&2
    fi
    ;;
esac

exit 0
