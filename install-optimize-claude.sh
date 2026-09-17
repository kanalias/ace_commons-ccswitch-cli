#!/usr/bin/env bash
# install-optimize-claude.sh — đọc config từ .env (repo root), ghi đè ~/.claude/settings.json.
# Mục đích: giảm context window bằng cách tắt tính năng Claude Code không cần thiết
# (vd disableWorkflows — xem .env cho giải thích chi tiết).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SRC/.env"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { echo "❌ cần jq — brew install jq" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "❌ thiếu $ENV_FILE" >&2; exit 1; }

env_val() {  # env_val <name> — dòng name=value đầu tiên, strip CR + quote
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$ENV_FILE" \
    | head -n1 | tr -d '\r' | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
jq empty "$SETTINGS" >/dev/null 2>&1 || { echo "❌ $SETTINGS không phải JSON hợp lệ" >&2; exit 1; }

DW="$(env_val disableWorkflows)"
if [ -z "$DW" ]; then
  echo "• .env không có disableWorkflows — bỏ qua"
  exit 0
fi
case "$DW" in
  true|false) ;;
  *) echo "❌ disableWorkflows trong .env phải là true/false, đang là: $DW" >&2; exit 1 ;;
esac

tmp="$(mktemp)"
jq --argjson v "$DW" '.disableWorkflows = $v' "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
echo "✓ disableWorkflows = $DW  ($SETTINGS)"
