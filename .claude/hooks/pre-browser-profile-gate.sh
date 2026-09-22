#!/usr/bin/env bash
# PreToolUse hook — enforce browser profile isolation (Cloak + Playwright).
# Wired to matchers: MCP browser tools (mcp__pw_*, mcp__cloak*, mcp__playwright*)
# + Bash (catch direct `@playwright/mcp` / cloak launch).
#
# Rule: .claude/rules/project/browser-mcp-profiles.md
#   Mọi action Cloak/Playwright PHẢI gắn 1 profile prj_<xx>_sv_<yy> trong container.
#   - MCP: server name = <pw|cloak>_<xx>_<yy> (profile bake vào --user-data-dir lúc
#     launch). Server generic (playwright / cloak / browser) = CHƯA scope profile → BLOCK.
#   - Bash launch: phải có --user-data-dir=.../prj_<xx>_sv_<yy> → thiếu = BLOCK.
#
# THREAT MODEL: chống tạo profile tùm lum vô ý (default cache, tên bừa), KHÔNG chống
# adversary — name/command heuristic, không sandbox.
#
# Output: exit 0 = allow · exit 2 = block (stderr shown to model).
# Fail-open: thiếu jq / payload không JSON → allow.
set -euo pipefail

# harness off-switch
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

# Profile naming: server key <pw|cloak>_<xx>_<yy>; dir prj_<xx>_sv_<yy>.
RE_SERVER='^(pw|cloak)_[a-z0-9]+_[a-z0-9]+$'
RE_PROFILE='prj_[a-z0-9]+_sv_[a-z0-9]+'

msg_block() {
  cat >&2 << EOF
🚦 browser-profile-gate: action Cloak/Playwright thiếu profile hợp lệ — BLOCK.
   $1

   Rule: .claude/rules/project/browser-mcp-profiles.md (GATE P0)
     • MCP server phải đặt tên <pw|cloak>_<xx>_<yy> (1 entry / profile,
       --user-data-dir=<container>/prj_<xx>_sv_<yy> bake lúc launch).
     • KHÔNG dùng server generic (playwright / cloak) hay launch thiếu --user-data-dir
       (rơi vào default cache, ngoài container, không track được → tùm lum).
   Tạo/chọn profile prj_<xx>_sv_<yy> rồi thao tác lại.
EOF
}

# verdict <tool_name> <cmd>  → prints ALLOW or "BLOCK:<reason>" (used by main + self-test)
verdict() {
  local tool="$1" cmd="${2:-}" server

  # ── MCP browser tool ────────────────────────────────────────────────
  if [[ "$tool" == mcp__* ]]; then
    server="${tool#mcp__}"; server="${server%%__*}"
    # chỉ quan tâm server browser
    case "$server" in
      pw_*|cloak_*|cloak|playwright|browser|*[Bb]rowser*)
        if [[ "$server" =~ $RE_SERVER ]]; then
          echo ALLOW
        else
          echo "BLOCK:MCP server '$server' chưa scope profile (đặt tên <pw|cloak>_<xx>_<yy>)."
        fi
        ;;
      *) echo ALLOW ;;  # MCP non-browser (notion...) — không đụng
    esac
    return
  fi

  # ── Bash launch playwright/cloak MCP ────────────────────────────────
  if [ "$tool" = "Bash" ] && [ -n "$cmd" ]; then
    if echo "$cmd" | grep -Eq '@playwright/mcp|[[:space:]]cloak(-mcp)?[[:space:]]|playwright.*mcp'; then
      # phải có --user-data-dir=...prj_<xx>_sv_<yy>
      if echo "$cmd" | grep -Eq -- "--user-data-dir=[^[:space:]]*${RE_PROFILE}"; then
        echo ALLOW
      else
        echo "BLOCK:launch browser MCP thiếu --user-data-dir=.../prj_<xx>_sv_<yy>."
      fi
      return
    fi
  fi

  echo ALLOW
}

# ── self-test ───────────────────────────────────────────────────────────
if [ "${1:-}" = "--self-test" ]; then
  fail=0
  check() { # check <expect-prefix> <tool> <cmd>
    local got; got=$(verdict "$2" "${3:-}")
    case "$got" in
      "$1"*) ;;
      *) echo "FAIL: verdict($2,'${3:-}')='$got' expected '$1*'"; fail=1 ;;
    esac
  }
  check ALLOW  "mcp__pw_myapp_auth__browser_navigate"
  check ALLOW  "mcp__cloak_shop_checkout__click"
  check BLOCK  "mcp__playwright__browser_navigate"
  check BLOCK  "mcp__cloak__click"
  check BLOCK  "mcp__pw_myapp__navigate"           # thiếu _yy
  check ALLOW  "mcp__claude_ai_Notion__notion-search"  # non-browser MCP
  check ALLOW  "Bash" "npx -y @playwright/mcp --user-data-dir=/Users/you/.browser-profiles/prj_myapp_sv_auth"
  check BLOCK  "Bash" "npx -y @playwright/mcp --headless"
  check BLOCK  "Bash" "npx -y @playwright/mcp --user-data-dir=/tmp/scratch"  # tên không phải prj_
  check ALLOW  "Bash" "ls -la"                      # bash thường
  [ "$fail" = 0 ] && echo "self-test PASS" || { echo "self-test FAIL"; exit 1; }
  exit 0
fi

# ── main ────────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0

tool=$(echo "$payload" | jq -r '.tool_name // empty')
cmd=$(echo "$payload"  | jq -r '.tool_input.command // empty')
[ -z "$tool" ] && exit 0

res=$(verdict "$tool" "$cmd")
if [[ "$res" == BLOCK:* ]]; then
  msg_block "${res#BLOCK:}"
  exit 2
fi
exit 0
