#!/usr/bin/env bash
# install-optimize-claude.sh — đọc config từ .env (repo root), ghi đè ~/.claude/settings.json.
# Mục đích: giảm context window bằng cách tắt tính năng / tool Claude Code không cần
# (disableWorkflows, denyTools — xem .env.example cho giải thích chi tiết).
# Mỗi key độc lập: thiếu key nào thì bỏ qua key đó, không dừng cả script.
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

jq_write() {  # jq_write <jq-args...> — ghi SETTINGS in-place (tmp + mv)
  local tmp; tmp="$(mktemp)"
  jq "$@" "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
}

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
jq empty "$SETTINGS" >/dev/null 2>&1 || { echo "❌ $SETTINGS không phải JSON hợp lệ" >&2; exit 1; }

# --- disableWorkflows: true/false → .disableWorkflows ---
DW="$(env_val disableWorkflows)"
if [ -z "$DW" ]; then
  echo "• .env không có disableWorkflows — bỏ qua"
else
  case "$DW" in
    true|false) ;;
    *) echo "❌ disableWorkflows trong .env phải là true/false, đang là: $DW" >&2; exit 1 ;;
  esac
  jq_write --argjson v "$DW" '.disableWorkflows = $v'
  echo "✓ disableWorkflows = $DW  ($SETTINGS)"
fi

# --- denyTools: tên tool built-in cách nhau dấu phẩy → union vào .permissions.deny ---
# Deny theo tên trần = Claude Code không nạp schema tool đó vào context. Giữ nguyên
# entry deny có sẵn + thứ tự; không gỡ tool đã bỏ khỏi list (tự sửa settings.json).
DT="$(env_val denyTools)"
if [ -z "$DT" ]; then
  echo "• .env không có denyTools — bỏ qua"
else
  [[ "$DT" =~ ^[A-Za-z0-9_]+([[:space:]]*,[[:space:]]*[A-Za-z0-9_]+)*$ ]] || {
    echo "❌ denyTools trong .env phải là tên tool cách nhau dấu phẩy (vd Artifact,CronCreate), đang là: $DT" >&2
    exit 1; }
  jq_write --arg s "$DT" '
    (.permissions.deny // []) as $cur
    | ($s | split(",") | map(gsub("^\\s+|\\s+$"; "")) | unique) as $new
    | .permissions.deny = $cur + ($new - $cur)'
  echo "✓ permissions.deny ∪= {$DT}  ($SETTINGS)"
fi
