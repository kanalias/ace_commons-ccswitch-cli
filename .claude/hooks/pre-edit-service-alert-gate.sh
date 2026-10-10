#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit|NotebookEdit) + repo check (`--scan`).
# Code gửi Telegram PHẢI đi qua format chung @acegalaxy/lib-ott-gateway/service-alert
# (TS: sendServiceAlert, bash: CLI `service-alert`). Tự gọi Bot API (`api.telegram.org`) → BLOCK.
#
#   hook:  stdin = JSON tool payload → exit 2 nếu vi phạm
#   scan:  bash .claude/hooks/pre-edit-service-alert-gate.sh --scan → exit 1 nếu có vi phạm
# Bỏ qua: .md, .claude/, node_modules, test/fixtures, và repo @acegalaxy/lib-ott-gateway
# (package.json name) — nơi duy nhất được gọi Bot API.
# Off-switch: HARNESS_DELEGATE=0 · bypass (user-only): BYPASS_SERVICE_ALERT_GATE=1.
set -uo pipefail

[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0
[ "${BYPASS_SERVICE_ALERT_GATE:-0}" = "1" ] && exit 0

PATTERN='api\.telegram\.org'
MSG='dùng format chung: TS `import sa from "@acegalaxy/lib-ott-gateway/service-alert"` → sa.sendServiceAlert(); bash → CLI `service-alert`.'
LIB_NAME='@acegalaxy/lib-ott-gateway'

project_dir="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# repo của chính lib → được phép
if [ -f "$project_dir/package.json" ] && command -v jq >/dev/null 2>&1 \
   && [ "$(jq -r '.name // empty' "$project_dir/package.json" 2>/dev/null)" = "$LIB_NAME" ]; then
  [ "${1:-}" = "--scan" ] && echo "✅ service-alert-gate: repo $LIB_NAME — bỏ qua"
  exit 0
fi

# skip_path <path> → 0 nếu path không cần quét
skip_path() {
  case "$1" in
    *.md|*.markdown|*.mdx) return 0 ;;
    */node_modules/*|node_modules/*|*/.claude/*|.claude/*|*/.git/*) return 0 ;;
    */test/*|test/*|*/tests/*|tests/*|*/__tests__/*|*/fixtures/*|fixtures/*|*/__fixtures__/*) return 0 ;;
    *.test.*|*.spec.*) return 0 ;;
  esac
  return 1
}

if [ "${1:-}" = "--scan" ]; then
  hits=""
  while IFS= read -r f; do
    [ -f "$project_dir/$f" ] || continue
    skip_path "$f" && continue
    h=$(grep -nE "$PATTERN" "$project_dir/$f" 2>/dev/null | sed "s|^|$f:|" || true)
    [ -n "$h" ] && hits="$hits$h"$'\n'
  done < <(git -C "$project_dir" ls-files 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "❌ service-alert-gate: code tự gọi Telegram Bot API:" >&2
    printf '%s' "$hits" >&2
    echo "$MSG" >&2
    exit 1
  fi
  echo "✅ service-alert-gate: không có chỗ nào tự gọi Telegram Bot API"
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0
file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -n "$file_path" ] || exit 0
skip_path "$file_path" && exit 0
content=$(printf '%s' "$payload" | jq -r '
  .tool_input.content
  // .tool_input.new_string
  // .tool_input.new_source
  // ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
  // empty')

if printf '%s' "$content" | grep -qE "$PATTERN"; then
  echo "🚦 service-alert-gate: $file_path tự gọi Telegram Bot API — $MSG (bypass user-only: BYPASS_SERVICE_ALERT_GATE=1)" >&2
  exit 2
fi
exit 0
