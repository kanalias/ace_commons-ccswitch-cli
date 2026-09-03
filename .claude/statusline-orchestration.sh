#!/usr/bin/env bash
# Statusline: hiển thị tiến độ task-graph (xem .claude/state/task-graph.md)
# nối sau global context-budget statusline (~/.claude/statusline-context.sh),
# nếu global script tồn tại — project statusLine OVERRIDE global nên phải tự chain.
#
# Nhận session JSON qua stdin (không cần parse ở đây — chỉ forward cho global
# script). Fail-open triệt để: mọi lỗi (graph vắng/hỏng, global script lỗi,
# thiếu jq...) vẫn in được phần còn lại, KHÔNG exit non-zero, KHÔNG stderr rác.
set -u

input_json="$(cat 2>/dev/null)"

# ── 1. chain global statusline (nếu có) ─────────────────────────────────
global_output=""
if [ -f "$HOME/.claude/statusline-context.sh" ]; then
  global_output="$(printf '%s' "$input_json" | bash "$HOME/.claude/statusline-context.sh" 2>/dev/null)"
fi

# ── 2. locate task-graph.md ──────────────────────────────────────────────
project_dir="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$project_dir" ]; then
  project_dir="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
fi
graph="${project_dir:-.}/.claude/state/task-graph.md"

segment=""
if [ -r "$graph" ]; then
  # Header validation (FORMAT v1.2) — không tin field index ($9 status) nếu
  # bảng bị reformat (cột thêm/xoá/đổi thứ tự). Lệch → im lặng bỏ segment,
  # không in rác/sai vào statusline (fail-open, nhất quán dispatch-gate).
  header_line="$(grep -m1 -E '^\|[[:space:]]*id[[:space:]]*\|' "$graph" 2>/dev/null || true)"
  header_norm="$(printf '%s' "$header_line" | sed -E 's/[[:space:]]+/ /g; s/^ *//; s/ *$//')"
  header_canonical="| id | subtask | persona | rw | locked | deps | wave | status | verify |"

  slug="$(sed -n '1p' "$graph" 2>/dev/null | sed -e 's/^# task-graph: *//' -e 's/[[:space:]]*$//')"
  status_val="$(grep -m1 '^status:' "$graph" 2>/dev/null | sed -e 's/^status: *//' -e 's/[[:space:]]*$//')"
  integ_val="$(grep -m1 '^integration-status:' "$graph" 2>/dev/null | sed -e 's/^integration-status: *//' -e 's/[[:space:]]*$//')"

  if [ "$header_norm" = "$header_canonical" ] && [ -n "$status_val" ] && [ "$status_val" != "done" ]; then
    counts="$(grep '^|' "$graph" 2>/dev/null | awk -F'|' '
      {
        s=$9; gsub(/^[ \t]+|[ \t]+$/, "", s)
        if (s=="pass" || s=="done")  p++
        else if (s=="dispatched")    d++
        else if (s=="revise")        r++
        else if (s=="pending")       q++
      }
      END { printf "%d %d %d %d", p+0, d+0, r+0, q+0 }
    ')"
    read -r c_pass c_disp c_rev c_pend <<EOF
$counts
EOF
    c_pass="${c_pass:-0}"; c_disp="${c_disp:-0}"; c_rev="${c_rev:-0}"; c_pend="${c_pend:-0}"

    icons=""
    [ "$c_pass" -gt 0 ] 2>/dev/null && icons="${icons}✅${c_pass} "
    [ "$c_disp" -gt 0 ] 2>/dev/null && icons="${icons}🔄${c_disp} "
    [ "$c_rev" -gt 0 ] 2>/dev/null && icons="${icons}♻️${c_rev} "
    [ "$c_pend" -gt 0 ] 2>/dev/null && icons="${icons}⬜${c_pend} "
    icons="${icons% }"

    segment="📊 ${slug} │ ${icons} │ ${status_val}"
    [ "$integ_val" = "pass" ] && segment="${segment} ✔️integration"
  fi
fi

# ── 3. assemble ──────────────────────────────────────────────────────────
if [ -n "$global_output" ] && [ -n "$segment" ]; then
  printf '%s │ %s' "$global_output" "$segment"
elif [ -n "$segment" ]; then
  printf '%s' "$segment"
else
  printf '%s' "$global_output"
fi

exit 0
