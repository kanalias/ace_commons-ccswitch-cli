#!/usr/bin/env bash
# Preflight/diagnostic check cho delegate wrapper setup — kiểu `brew doctor`.
# Đọc-only: KHÔNG bao giờ sửa/tạo file, KHÔNG auto-fix bất kỳ thứ gì. Chạy hết
# mọi check dù check trước fail (không set -e) để báo đầy đủ 1 lần thay vì
# dừng ở lỗi đầu tiên.
#
# Usage: scripts/delegate/doctor.sh
# Exit: 0 nếu tất cả pass, 1 nếu có check fail (chỉ để script hoá — bản thân
#       doctor.sh không có hành động destructive dù exit code nào).
set -uo pipefail

PASS=0
FAIL=0

# In dòng ✓/✗ + tăng counter. Không bao giờ nhận giá trị secret làm arg —
# chỉ nhận 0/1 + label mô tả.
check() {
  local ok="$1" label="$2"
  if [[ "$ok" -eq 1 ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "CLI:"
for bin in git jq aider codex gemini; do
  if command -v "$bin" >/dev/null 2>&1; then
    check 1 "$bin"
  else
    check 0 "$bin"
  fi
done

echo
echo "Git repo:"
IN_GIT_REPO=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT_REPO=1
  check 1 "cwd is inside a git work tree"
else
  check 0 "cwd is inside a git work tree"
fi

echo
echo "Env keys (presence only — never print values):"

# Read-only KEY=VALUE line lookup, quote-stripped — mirror logic của
# _common.sh's load_env_chain() nhưng KHÔNG export, KHÔNG side effect.
# Không source _common.sh trực tiếp ở đây: file đó `set -euo pipefail` +
# `git rev-parse --show-toplevel` fail-hard khi ngoài git repo → sẽ giết
# doctor.sh sớm, mất hết các check còn lại. Standalone parser tránh phụ thuộc
# đó — pragmatic hơn subshell isolation cho 1 lookup đơn giản thế này.
lookup_env_key() {
  local key="$1" f line v pattern
  if [[ -n "${!key:-}" ]]; then
    echo 1
    return
  fi
  pattern="^[[:space:]]*${key}=(.*)$"
  for f in "$REPO_ROOT/.env.local" "$REPO_ROOT/.env"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ $pattern ]]; then
        v="${BASH_REMATCH[1]}"
        [[ "$v" =~ ^\"(.*)\"$ ]] && v="${BASH_REMATCH[1]}"
        [[ "$v" =~ ^\'(.*)\'$ ]] && v="${BASH_REMATCH[1]}"
        if [[ -n "$v" ]]; then
          echo 1
          return
        fi
      fi
    done < "$f"
  done
  echo 0
}

# Trả 1 nếu bất kỳ key nào trong list resolve được (process env hoặc .env chain).
resolved_any() {
  local k
  for k in "$@"; do
    if [[ "$(lookup_env_key "$k")" == "1" ]]; then
      echo 1
      return
    fi
  done
  echo 0
}

if [[ "$IN_GIT_REPO" -eq 1 ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  ROUTER_BASE_OK="$(resolved_any proxy_host PROXY_9ROUTER_BASE_URL)"
  ROUTER_TOKEN_OK="$(resolved_any proxy_key PROXY_9ROUTER_TOKEN)"
  if [[ "$ROUTER_BASE_OK" == "1" && "$ROUTER_TOKEN_OK" == "1" ]]; then
    ROUTER_OK=1
  else
    ROUTER_OK=0
  fi
  check "$ROUTER_OK" "9router (proxy_host + proxy_key) resolved"

  DS_OK="$(resolved_any deepseek_api_key DEEPSEEK_API_KEY PROXY_DEEPSEEK_API_KEY)"
  check "$DS_OK" "deepseek fallback key resolved"

  if [[ "$ROUTER_OK" -ne 1 && "$DS_OK" -ne 1 ]]; then
    echo "  ⚠ neither 9router nor deepseek fallback resolved — delegate-deepseek wrapper will fail"
  fi
else
  echo "  – skipped — no git repo to locate .env"
fi

echo
echo "$PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]]
