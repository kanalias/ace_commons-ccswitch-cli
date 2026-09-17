#!/usr/bin/env bash
# Statusline: cảnh báo sớm context window (thay cho "hook cảnh báo" — hook KHÔNG đọc được token count).
# Ngưỡng khớp token-budget.md: <50% xanh | 50-75% vàng | >=75% đỏ (window 200k → 100K / 150K).
# Nhận session JSON qua stdin (field: context_window.*, model.display_name).
set -uo pipefail

in=$(cat)
command -v jq >/dev/null 2>&1 || { printf '%s' "$in" | head -c 0; echo "ctx: (jq missing)"; exit 0; }

read -r pct used max model < <(
  printf '%s' "$in" | jq -r '
    [ (.context_window.used_percentage // 0)
    , (.context_window.total_input_tokens // 0)
    , (.context_window.context_window_size // 200000)
    , (.model.display_name // "?")
    ] | @tsv' | tr '\t' ' '
)

pcti=${pct%.*}; [ -z "$pcti" ] && pcti=0
usedk=$(( (used + 500) / 1000 ))       # K, làm tròn
maxk=$((  max / 1000 ))

# màu ANSI theo ngưỡng
if   [ "$pcti" -ge 75 ]; then c=$'\033[31m'; tag="⚠ NÉN GẦN KỀ"      # đỏ
elif [ "$pcti" -ge 50 ]; then c=$'\033[33m'; tag="↑ delegate/new session"  # vàng
else                          c=$'\033[32m'; tag=""                     # xanh
fi
r=$'\033[0m'

# thanh 10 ô
fill=$(( pcti / 10 )); [ "$fill" -gt 10 ] && fill=10
bar=""; for ((i=0;i<10;i++)); do [ "$i" -lt "$fill" ] && bar+="▓" || bar+="░"; done

printf '%s[%s] %s%s %d%% (%dK/%dK)%s %s' \
  "$c" "$model" "$bar" "$r$c" "$pcti" "$usedk" "$maxk" "$r" "$tag"
