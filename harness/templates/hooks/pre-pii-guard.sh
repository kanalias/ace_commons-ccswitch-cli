#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit|NotebookEdit · Bash · mcp browser).
# Chặn action/text lộ địa chỉ hoặc thân phận (SĐT, CCCD, email cá nhân, địa chỉ VN, toạ độ GPS).
# git push → scan luôn diff sắp đẩy (@{u}..HEAD).
#
# exit 0 allow · exit 2 block (stderr cho model).
# OPT-IN (HARNESS_GROUP_PII=y khi cài). Off-switch: HARNESS_DELEGATE=0.
# Bypass (user-only): command/text chứa PII_GUARD_BYPASS=1 → allow + audit log
#   + action ra ngoài (git push / browser) → báo qua service-alert CLI nếu có cài.
# False positive cố định → thêm chuỗi vào .claude/allowed-pii.txt (1 dòng/chuỗi).
set -uo pipefail

[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
project_dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
tool=$(jq -r '.tool_name // empty' <<<"$payload")
file_path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$payload")

case "$file_path" in
  */.env|*/.env.*|*/security_envs/*|*/node_modules/*|*/allowed-pii.txt) exit 0 ;;
esac

# Edit/Write: chỉ nội dung mới (không chặn việc xoá PII cũ). Tool khác: toàn bộ input.
case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    content=$(jq -r '.tool_input.content // .tool_input.new_string // .tool_input.new_source
      // ((.tool_input.edits // []) | map(.new_string // "") | join("\n")) // empty' <<<"$payload") ;;
  *) content=$(jq -r '.tool_input | tostring' <<<"$payload") ;;
esac

outbound=0
cmd=""
if [ "$tool" = "Bash" ]; then
  cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")
  if grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push' <<<"$cmd"; then
    outbound=1
    content="$content
$(git -C "$project_dir" diff '@{u}..HEAD' 2>/dev/null | grep '^+' || true)"
  fi
  grep -qE 'curl .*(-d|--data|-F|-X ?POST)' <<<"$cmd" && outbound=1
fi
case "$tool" in mcp__*) outbound=1 ;; esac

[ -z "$content" ] && exit 0

hits=$(PII_TEXT="$content" "$(dirname "$0")/pii-scan.pl" "$project_dir/.claude/allowed-pii.txt")
[ -z "$hits" ] && exit 0

log="$project_dir/.claude/state/pii-guard.log"
mkdir -p "$(dirname "$log")"
ts=$(date -u +%FT%TZ)
# Chỉ log loại phát hiện, không log value (tránh chính log thành nơi lộ PII).
kinds=$(cut -d: -f1 <<<"$hits" | sort -u | paste -sd, -)

if grep -q 'PII_GUARD_BYPASS=1' <<<"$content$cmd"; then
  echo "$ts BYPASS tool=$tool kinds=$kinds file=${file_path:-}" >>"$log"
  if [ "$outbound" = 1 ]; then
    alert="$project_dir/node_modules/.bin/service-alert"
    [ -x "$alert" ] || alert="$(command -v service-alert 2>/dev/null || true)"
    [ -n "$alert" ] && [ -x "$alert" ] && (cd "$project_dir" && printf 'tool=%s\nfile=%s\n' "$tool" "${file_path:--}" |
      "$alert" --service pii-guard --status warn --title "PII đã đi ra ngoài (bypass)" \
        --field "kinds=$kinds" --env-file .env >/dev/null 2>&1 &)
  fi
  exit 0
fi

echo "$ts BLOCK tool=$tool kinds=$kinds file=${file_path:-}" >>"$log"
{
  echo "🚨 pii-guard: nội dung có thể lộ địa chỉ/thân phận — đã chặn."
  sed 's/^/  /' <<<"$hits"
  echo "Bỏ/ẩn dữ liệu đó (SĐT, CCCD, email cá nhân, địa chỉ, toạ độ GPS)."
  echo "False positive → thêm chuỗi vào .claude/allowed-pii.txt. User đồng ý cho qua → thêm PII_GUARD_BYPASS=1 (sẽ báo Telegram nếu ra ngoài)."
} >&2
exit 2
