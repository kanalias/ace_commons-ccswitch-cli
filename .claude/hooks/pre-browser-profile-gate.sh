#!/usr/bin/env bash
# PreToolUse hook — enforce browser profile isolation (Cloak + Playwright).
# Wired to matchers: MCP browser tools (mcp__pw_*, mcp__cloak*, mcp__playwright*)
# + Bash (catch direct `@playwright/mcp` / cloak launch).
#
# Rule: .claude/rules/project/browser-mcp-profiles.md
#   Mọi action Cloak/Playwright PHẢI gắn 1 profile prj_<xx>_sv_<yy> trong container.
#   - MCP: server name = <pw|cloak>_<xx>_<yy>. Cloak launch phải truyền đúng
#     user_data_dir=.../prj_<xx>_sv_<yy>; Playwright bake profile vào server entry.
#   - Bash Playwright launch: phải có --user-data-dir=.../prj_<xx>_sv_<yy> → thiếu = BLOCK.
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

profile_root() {
  local root="${BROWSER_PROFILES_DIR:-}"
  if [[ -z "$root" ]]; then
    [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] || return 1
    root="$CLAUDE_PROJECT_DIR/.browser-profiles"
  fi
  [[ "$root" == /* ]] || return 1
  printf '%s' "${root%/}"
}

valid_profile_dir() {
  local user_data_dir="$1" expected="$2" root
  [[ "$user_data_dir" == /* ]] || return 1
  root="$(profile_root)" || return 1
  [[ "$user_data_dir" == "$root/$expected" ]]
}

msg_block() {
  cat >&2 << EOF
🚦 browser-profile-gate: action Cloak/Playwright thiếu profile hợp lệ — BLOCK.
   $1

   Rule: .claude/rules/project/browser-mcp-profiles.md (GATE P0)
     • MCP server phải đặt tên <pw|cloak>_<xx>_<yy> (1 entry / profile).
     • Cloak launch phải truyền user_data_dir=<container>/prj_<xx>_sv_<yy> khớp server;
       Playwright server phải bake --user-data-dir vào entry.
     • KHÔNG dùng server generic hay launch thiếu profile (rơi default/ephemeral).
   Tạo/chọn profile prj_<xx>_sv_<yy> rồi thao tác lại.
EOF
}

# verdict <tool_name> <cmd> <user_data_dir> → ALLOW hoặc "BLOCK:<reason>"
verdict() {
  local tool="$1" cmd="${2:-}" user_data_dir="${3:-}" server expected

  # ── MCP browser tool ────────────────────────────────────────────────
  if [[ "$tool" == mcp__* ]]; then
    server="${tool#mcp__}"; server="${server%%__*}"
    # chỉ quan tâm server browser
    case "$server" in
      pw_*|cloak_*|cloak|playwright|browser|*[Bb]rowser*)
        if ! [[ "$server" =~ $RE_SERVER ]]; then
          echo "BLOCK:MCP server '$server' chưa scope profile (đặt tên <pw|cloak>_<xx>_<yy>)."
          return
        fi
        if [[ "$server" == cloak_* && "$tool" == *"__cloak_launch" ]]; then
          local pair="${server#cloak_}" xx yy
          xx="${pair%%_*}"; yy="${pair#*_}"
          expected="prj_${xx}_sv_${yy}"
          if ! valid_profile_dir "$user_data_dir" "$expected"; then
            echo "BLOCK:cloak_launch trên '$server' phải truyền user_data_dir=<container>/$expected, đúng container đã resolve."

          else
            echo ALLOW
          fi
        else
          echo ALLOW
        fi
        ;;
      *) echo ALLOW ;;  # MCP non-browser (notion...) — không đụng
    esac
    return
  fi

  # ── Bash launch Playwright MCP ──────────────────────────────────────
  # Cloak không bind profile qua CLI; gate nó tại tool cloak_launch ở trên.
  if [ "$tool" = "Bash" ] && [ -n "$cmd" ]; then
    if echo "$cmd" | grep -Eq '@playwright/mcp|playwright.*mcp'; then
      # phải có --user-data-dir=...prj_<xx>_sv_<yy>
      if [[ "$cmd" =~ --user-data-dir=([^[:space:]]+) ]] && valid_profile_dir "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]##*/}" && [[ "${BASH_REMATCH[1]##*/}" =~ ^$RE_PROFILE$ ]]; then
        echo ALLOW
      else
        echo "BLOCK:launch Playwright MCP phải có --user-data-dir=<container>/prj_<xx>_sv_<yy>."
      fi
      return
    fi
  fi

  echo ALLOW
}

# ── self-test ───────────────────────────────────────────────────────────
if [ "${1:-}" = "--self-test" ]; then
  BROWSER_PROFILES_DIR=/profiles
  export BROWSER_PROFILES_DIR
  fail=0
  check() { # check <expect-prefix> <tool> <cmd> <user_data_dir>
    local got; got=$(verdict "$2" "${3:-}" "${4:-}")
    case "$got" in
      "$1"*) ;;
      *) echo "FAIL: verdict($2,'${3:-}')='$got' expected '$1*'"; fail=1 ;;
    esac
  }
  check ALLOW  "mcp__pw_myapp_auth__browser_navigate"
  check ALLOW  "mcp__cloak_shop_checkout__click"
  check BLOCK  "mcp__cloak_shop_checkout__cloak_launch"
  check BLOCK  "mcp__cloak_shop_checkout__cloak_launch" "" "/profiles/prj_shop_sv_other"
  check ALLOW  "mcp__cloak_shop_checkout__cloak_launch" "" "/profiles/prj_shop_sv_checkout"
  check BLOCK  "mcp__cloak_shop_checkout__cloak_launch" "" "relative/prj_shop_sv_checkout"
  check BLOCK  "mcp__cloak_shop_checkout__cloak_launch" "" "/tmp/prj_shop_sv_checkout"
  check BLOCK  "mcp__cloak_shop_checkout__cloak_launch" "" "/profiles/prj_shop_sv_checkout/extra"
  check BLOCK  "mcp__playwright__browser_navigate"
  check BLOCK  "mcp__cloak__click"
  check BLOCK  "mcp__pw_myapp__navigate"           # thiếu _yy
  check ALLOW  "mcp__claude_ai_Notion__notion-search"  # non-browser MCP
  check ALLOW  "Bash" "npx -y @playwright/mcp --user-data-dir=/profiles/prj_myapp_sv_auth"
  check BLOCK  "Bash" "npx -y @playwright/mcp --user-data-dir=/tmp/prj_myapp_sv_auth"
  check BLOCK  "Bash" "npx -y @playwright/mcp --user-data-dir=relative/prj_myapp_sv_auth"
  check BLOCK  "Bash" "npx -y @playwright/mcp --headless"
  check BLOCK  "Bash" "npx -y @playwright/mcp --user-data-dir=/tmp/scratch"  # tên không phải prj_
  check ALLOW  "Bash" "git commit -m 'configure cloak per repo'" # không phải browser launch
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
user_data_dir=$(echo "$payload" | jq -r '.tool_input.user_data_dir // empty')
[ -z "$tool" ] && exit 0

res=$(verdict "$tool" "$cmd" "$user_data_dir")
if [[ "$res" == BLOCK:* ]]; then
  msg_block "${res#BLOCK:}"
  exit 2
fi
exit 0
