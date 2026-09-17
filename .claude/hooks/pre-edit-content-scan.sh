#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit|NotebookEdit).
# Merge of pre-edit-secret-scan.sh + pre-edit-host-scan.sh — parse payload
# once, run secret check first, host check second.
#
# Input: stdin = JSON với fields tool_input.{file_path,content,new_string,edits}
# Output: exit 0 → allow · exit 2 → block (stderr feedback shown to model)
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)

# Nếu không có jq thì fail-open (allow).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
# Write→content · Edit→new_string · MultiEdit→edits[].new_string (gom hết về 1 chuỗi).
content=$(echo "$payload" | jq -r '
  .tool_input.content
  // .tool_input.new_string
  // .tool_input.new_source
  // ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
  // empty')

# Skip .env / .env.* — quản qua deny list của settings.json.
case "$file_path" in
  */.env|*/.env.*|.env|.env.*) exit 0 ;;
esac

# ── 1) secret scan ───────────────────────────────────────────────────────────
# High-confidence secret shapes (low false-positive). Broad patterns
# (IP/domain/email/generic assignment) belong to the /check-hardcode skill,
# NOT here — auto-blocking those would false-positive constantly.
if echo "$content" | grep -E -q \
    -e 'sk-ant-[A-Za-z0-9_-]{20,}' \
    -e 'sk-[A-Za-z0-9]{32,}' \
    -e 'AIza[0-9A-Za-z_-]{35}' \
    -e 'gh[posru]_[A-Za-z0-9]{36}' \
    -e 'xai-[A-Za-z0-9]{20,}' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
    -e '(sk|rk)_live_[A-Za-z0-9]{24,}' \
    -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
    -e '[a-z][a-z0-9+.-]*://[^:@/[:space:]]+:[^@/[:space:]]+@[^[:space:]/]+' \
    -e 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'; then
  echo "🚨 pre-edit-secret-scan: nội dung chứa pattern giống secret. Hủy ghi vào $file_path." >&2
  echo "Nếu là false positive, dùng Bash để ghi (đi qua deny list của settings)." >&2
  exit 2
fi

# ── 2) host/IP scan ──────────────────────────────────────────────────────────
# Scope: chỉ bắt host trong URL (http(s)://...) + bare IPv4. Bare domain
# không kèm scheme KHÔNG bắt — false-positive quá cao.
case "$file_path" in
  */allowed-hosts.txt|allowed-hosts.txt) exit 0 ;;
esac

[ -z "$content" ] && exit 0

# --- load allowlist (fail-open nếu thiếu file) ---
project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
allowlist_file="$project_dir/.claude/allowed-hosts.txt"
allowlist=""
if [ -f "$allowlist_file" ]; then
  allowlist=$(grep -vE '^\s*(#|\s*$)' "$allowlist_file" || true)
fi

is_allowlisted() {
  local host="$1"
  [ -z "$allowlist" ] && return 1
  grep -qxF "$host" <<<"$allowlist"
}

# --- safe-pattern check (placeholder / local / private) ---
is_safe_host() {
  local host="$1"

  # IPv4 dotted-quad → range check.
  if [[ "$host" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}"
    case "$host" in
      0.0.0.0|255.255.255.255) return 0 ;;
    esac
    [ "$o1" = "127" ] && return 0
    [ "$o1" = "10" ] && return 0
    [ "$o1" = "169" ] && [ "$o2" = "254" ] && return 0
    if [ "$o1" = "192" ] && [ "$o2" = "168" ]; then return 0; fi
    if [ "$o1" = "172" ] && [ "$o2" -ge 16 ] 2>/dev/null && [ "$o2" -le 31 ] 2>/dev/null; then
      return 0
    fi
    return 1
  fi

  # Domain-style safe suffixes.
  case "$host" in
    localhost|*.local|*.test|*.example) return 0 ;;
    *example.*) return 0 ;;
  esac

  return 1
}

# --- extract candidate hosts ---
candidates=""

# 1) URL host (http/https).
while IFS= read -r match; do
  [ -z "$match" ] && continue
  host="${match#http://}"
  host="${host#https://}"
  host="${host%%[:/?[:space:]]*}"
  [ -n "$host" ] && candidates="$candidates
$host"
done < <(echo "$content" | grep -oiE 'https?://[a-zA-Z0-9._-]+' || true)

# 2) Bare IPv4.
while IFS= read -r ip; do
  [ -z "$ip" ] && continue
  candidates="$candidates
$ip"
done < <(echo "$content" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)

# --- decide ---
suspects=""
while IFS= read -r cand; do
  [ -z "$cand" ] && continue
  is_safe_host "$cand" && continue
  is_allowlisted "$cand" && continue
  suspects="$suspects
$cand"
done <<<"$candidates"

suspects=$(echo "$suspects" | grep -v '^\s*$' | sort -u || true)

if [ -n "$suspects" ]; then
  {
    echo "🚨 pre-edit-host-scan: nội dung chứa host/IP nghi là PRODUCTION, chưa được duyệt:"
    echo "$suspects" | sed 's/^/  /'
    echo "File: $file_path"
    echo "Nếu đây là host/IP production thật: HỎI USER xác nhận, rồi thêm host vào"
    echo ".claude/allowed-hosts.txt (1 host/dòng) và ghi lại. Nếu là placeholder/test,"
    echo "đổi sang dạng an toàn (example.com, *.test, *.local, 127.0.0.1)."
  } >&2
  exit 2
fi

exit 0
