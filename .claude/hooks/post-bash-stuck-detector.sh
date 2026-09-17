#!/usr/bin/env bash
# PostToolUse hook (matcher: Bash).
# OpenHands StuckDetector pattern: cùng 1 lệnh Bash chạy lặp N lần liên tiếp
# (không đổi approach) → có thể model đang thrashing/retry mù. Cảnh báo model
# tự đổi hướng thay vì lặp lại.
#
# LƯU Ý: PostToolUse exit 2 KHÔNG undo lệnh đã chạy (đã chạy rồi) — chỉ
# surface stderr cho model để đổi hướng ở turn kế tiếp (advisory-hard, không
# phải rollback thật).
#
# ponytail: window file dùng chung mọi session của user (không phân biệt theo
# session) khi payload không có .session_id → false positive nếu 2 session
# song song vô tình gõ trùng lệnh. Có .session_id thì đã key riêng theo
# session. Nâng cấp: nếu Claude Code sau này luôn cấp session_id ổn định thì
# bỏ nhánh fallback plain filename.
set -euo pipefail

# harness off-switch
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0   # fail-open (consistent w/ other gates)

cmd=$(echo "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0

session_id=$(echo "$payload" | jq -r '.session_id // empty' 2>/dev/null) || session_id=""

# normalize: trim + collapse runs of whitespace thành 1 space
norm=$(echo "$cmd" | tr -s '[:space:]' ' ' | sed -e 's/^ *//' -e 's/ *$//')
[ -z "$norm" ] && exit 0

if command -v shasum >/dev/null 2>&1; then
  hash=$(printf '%s' "$norm" | shasum -a 256 | cut -d' ' -f1)
else
  hash=$(printf '%s' "$norm" | cksum | cut -d' ' -f1)
fi

cache_dir="$HOME/.cache/claude-code-ccswitch-cli-claude"
mkdir -p "$cache_dir"

if [ -n "$session_id" ]; then
  window_file="$cache_dir/stuck-window-$session_id"
else
  window_file="$cache_dir/stuck-window"
fi

touch "$window_file"
echo "$hash" >>"$window_file"

# rotate: giữ tối đa 20 dòng cuối
tmp_file="$window_file.tmp.$$"
tail -n 20 "$window_file" >"$tmp_file" && mv "$tmp_file" "$window_file"

# 4 dòng cuối giống nhau hết → loop detected
last4=$(tail -n 4 "$window_file")
if [ "$(echo "$last4" | wc -l | tr -d ' ')" -eq 4 ] && [ "$(echo "$last4" | sort -u | wc -l | tr -d ' ')" -eq 1 ]; then
  echo "🔁 Loop detected: cùng lệnh Bash chạy 4 lần liên tiếp — đổi approach, investigate root cause thay vì retry (xem feature-redflags). Reset: xoá $window_file" >&2
  exit 2
fi

exit 0
