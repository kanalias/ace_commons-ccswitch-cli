#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write).
# Block edit nếu nội dung định ghi chứa pattern giống secret.
#
# Input: stdin = JSON với fields tool_input.{file_path,content,new_string}
# Output:
#   exit 0 → allow
#   exit 2 → block (stderr feedback shown to model)
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)

# Nếu không có jq thì fail-open (allow).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // empty')
content=$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // empty')

# Skip .env / .env.* — quản qua deny list của settings.json.
case "$file_path" in
  */.env|*/.env.*|.env|.env.*) exit 0 ;;
esac

# Common provider API key shapes (OpenAI/Anthropic/Google/xAI/GitHub) + JWT + PEM.
if echo "$content" | grep -E -q \
    -e 'sk-ant-[A-Za-z0-9_-]{20,}' \
    -e 'sk-[A-Za-z0-9]{32,}' \
    -e 'AIza[0-9A-Za-z_-]{35}' \
    -e 'ghp_[A-Za-z0-9]{36}' \
    -e 'xai-[A-Za-z0-9]{20,}' \
    -e '"private_key": *"-----BEGIN' \
    -e 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'; then
  echo "🚨 pre-edit-secret-scan: nội dung chứa pattern giống secret. Hủy ghi vào $file_path." >&2
  echo "Nếu là false positive, dùng Bash để ghi (đi qua deny list của settings)." >&2
  exit 2
fi

exit 0
