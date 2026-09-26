#!/usr/bin/env bash
# PreCompact hook (matcher: auto). Chặn AUTO-compact khi task-graph của đúng
# session (FORMAT v1.3, slug từ cwd) đang dở (status ≠ done) — compact lossy
# giữa task L/M làm mất invariant/interface-lock. Manual /compact luôn qua
# (không wire matcher manual). Advisory khi không có graph: exit 0.
#
# exit 2 = BLOCK. Claude Code proactive compact bị skip, conversation tiếp tục
# uncompacted → orchestrator phải commit + handoff sang session mới (xem
# token-budget.md). Nếu compact do API context-limit error thì request fail —
# chỉ xảy ra khi autoCompactWindow sát trần model; mặc định harness set thấp hơn.
set -u

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null || true)
[ -n "$payload" ] || exit 0
trigger=$(printf '%s' "$payload" | jq -r '.trigger // empty' 2>/dev/null) || exit 0
[ "$trigger" = "auto" ] || exit 0
cwd_in=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null) || cwd_in=""

graph_slug() {
  local c="$1" rest s
  case "$c" in
    */.claude/worktrees/*) rest="${c#*/.claude/worktrees/}"; s="${rest%%/*}" ;;
    *) s="" ;;
  esac
  s="$(printf '%s' "$s" | tr -cd 'A-Za-z0-9._-')"
  printf '%s' "${s:-main}"
}

project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
slug=$(graph_slug "$cwd_in")
graph="$project_dir/.claude/state/task-graph/$slug.md"
[ -f "$graph" ] || exit 0

status=$(grep -m1 '^status:' "$graph" 2>/dev/null | sed 's/^status:[[:space:]]*//; s/[[:space:]]*$//') || status=""
[ -n "$status" ] && [ "$status" != "done" ] || exit 0

log_dir="${HOME}/.cache/claude-code-@@PROJECT_SLUG@@"
mkdir -p "$log_dir" 2>/dev/null && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) BLOCK auto-compact slug=$slug status=$status" >>"$log_dir/compact-guard.log" 2>/dev/null || true

cat >&2 <<MSG
🛑 AUTO-COMPACT bị chặn: task-graph '$slug' đang '$status' (compact lossy giữa task lớn mất invariant).
   Hành động: commit phần xong → update $graph + plan-$slug.md → mở session mới, /orchestrate --resume.
   Cần compact ngay: gõ /compact <giữ: file đã sửa, chữ ký đổi, test chưa chạy> (manual không bị chặn).
MSG
exit 2
