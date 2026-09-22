#!/usr/bin/env bash
# PreToolUse hook (matcher: Task).
# Dispatch-quality gate: chặn Opus dispatch subagent delegate-* với prompt
# under-specified — không self-contained (per .claude/rules/common/orchestrator.md
# section "Sub-task prompt"). Subagent không có session context, prompt thiếu
# spec = delegate đoán mò, kết quả sai/lệch scope, tốn 1 vòng fallback.
#
# THREAT MODEL: heuristic marker check (grep-based), KHÔNG phải semantic
# validation — chống prompt under-specified VÔ Ý, không chống adversary. Prompt
# có đủ 4 keyword nhưng nội dung rỗng tuếch vẫn lọt qua (không đo được "đủ ý"
# bằng regex) — đó là giới hạn chấp nhận được của gate này.
#
# Chỉ act khi tool_input.subagent_type bắt đầu "delegate-" (Explore, general-
# purpose, code-reviewer... KHÔNG phải delegate execution → exit 0, không gate).
#
# Output: exit 0 = allow · exit 2 = block (stderr shown to model, liệt kê đúng
# marker nào thiếu).
# Fail-open: thiếu jq / payload không JSON / thiếu subagent_type → exit 0.
set -euo pipefail

# Slug từ session cwd — mỗi worktree 1 state file riêng (FORMAT v1.3, xem
# orchestrator.md "Task-graph artifact"), không còn race read-modify-write
# giữa 2 session cùng repo. cwd rỗng/không khớp worktree → "main".
graph_slug() {
  local c="$1" rest s
  case "$c" in
    */.claude/worktrees/*) rest="${c#*/.claude/worktrees/}"; s="${rest%%/*}" ;;
    *) s="" ;;
  esac
  s="$(printf '%s' "$s" | tr -cd 'A-Za-z0-9._-')"
  printf '%s' "${s:-main}"
}

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

LOG="${HOME}/.cache/claude-code-ccswitch-cli-claude/dispatch-gate.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
ts() { date '+%Y-%m-%dT%H:%M:%S'; }

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0

subagent_type=$(echo "$payload" | jq -r '.tool_input.subagent_type // empty')
prompt=$(echo "$payload"        | jq -r '.tool_input.prompt // empty')

# Không phải delegate-* dispatch (Explore, general-purpose, thiếu field...) → skip.
case "$subagent_type" in
  delegate-*) : ;;
  *) exit 0 ;;
esac

# Prompt quá ngắn (< 200 ký tự) → không đủ chỗ để self-contained thật sự.
if [ "${#prompt}" -lt 200 ]; then
  echo "$(ts) BLOCK $subagent_type dispatch → prompt quá ngắn (${#prompt} chars)" >> "$LOG" 2>/dev/null || true
  cat >&2 << EOF
🚦 dispatch-gate: prompt gửi "$subagent_type" quá ngắn (${#prompt} ký tự, cần ≥200) — không đủ self-contained.
   Sub-task prompt phải self-contained (xem orchestrator.md): repo path + spec + file paths + acceptance/verify + no-commit + summary <300 words.
EOF
  exit 2
fi

missing=()

echo "$prompt" | grep -qiE '(/Users/|/home/|/opt/|\brepo\b)' || missing+=("repo path (absolute path hoặc từ 'repo')")
echo "$prompt" | grep -qiE '\b(verify|test|bats|acceptance)\b' || missing+=("verify/acceptance criteria")
echo "$prompt" | grep -qiE '\b(file|path|scope)\b' || missing+=("file paths / scope")
echo "$prompt" | grep -qiE '\bcommit\b' || missing+=("no-commit instruction (phải nhắc từ 'commit')")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "$(ts) BLOCK $subagent_type dispatch → thiếu: ${missing[*]}" >> "$LOG" 2>/dev/null || true
  {
    echo "🚦 dispatch-gate: prompt gửi \"$subagent_type\" thiếu marker self-contained:"
    for m in "${missing[@]}"; do
      echo "   - $m"
    done
    echo ""
    echo "   Sub-task prompt phải self-contained (xem orchestrator.md): repo path + spec + file paths + acceptance/verify + no-commit + summary <300 words."
  } >&2
  exit 2
fi

# ── Task-graph aware gate (đọc .claude/rules/common/orchestrator.md
#    "Interface-lock gate") ─────────────────────────────────────────────────
# Không có graph file → task nhỏ, không cần graph, giữ hành vi cũ (exit 0).
# Graph unreadable / parse lỗi bất kỳ → fail-open exit 0 (threat model: chống
# vô ý, không chống adversary — như mọi check khác trong hook này).
#
# FORMAT v1.3: graph per-worktree tại .claude/state/task-graph/<slug>.md —
# slug tự suy ra từ `cwd` thật của session (payload.cwd, KHÔNG phải
# CLAUDE_PROJECT_DIR — field đó luôn trỏ về repo root kể cả khi session đang
# cwd trong worktree). Mỗi session chỉ đọc/ghi ĐÚNG file của mình → không còn
# file dùng chung → không còn race read-modify-write giữa 2 session song song.
# Loại bỏ hẳn cơ chế slug-marker v1.2 (band-aid detect-mismatch-sau-khi-xảy-ra)
# vì giờ collision KHÔNG THỂ xảy ra nữa — không cần detect. Marker quay lại
# format v1 đơn giản: "task-graph #<id>" (không slug).
cwd_in=$(echo "$payload" | jq -r '.cwd // empty')
slug=$(graph_slug "$cwd_in")
project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
graph_file="$project_dir/.claude/state/task-graph/$slug.md"

if [ -f "$graph_file" ] && [ -r "$graph_file" ]; then
  # Header validation — không tin field index ($2 id / $5 rw / $6 locked) nếu
  # bảng bị reformat (cột thêm/xoá/đổi thứ tự) → silent wrong-field. Header
  # lệch = graph không đáng tin → fail-open exit 0 (WARN log), KHÔNG block.
  header_line=$(grep -m1 -E '^\|[[:space:]]*id[[:space:]]*\|' "$graph_file" 2>/dev/null || true)
  header_norm=$(printf '%s' "$header_line" | sed -E 's/[[:space:]]+/ /g; s/^ *//; s/ *$//')
  header_canonical="| id | subtask | persona | rw | locked | deps | wave | status | verify |"

  if [ "$header_norm" != "$header_canonical" ]; then
    echo "$(ts) WARN task-graph header không khớp format chuẩn (graph: $graph_file) → fail-open, bỏ qua task-graph gate" >> "$LOG" 2>/dev/null || true
  else
    marker_id=$(echo "$prompt" | grep -oE 'task-graph #[0-9]+' | head -1 | grep -oE '[0-9]+' || true)

    if [ -z "$marker_id" ]; then
      echo "$(ts) BLOCK $subagent_type dispatch → thiếu task-graph marker (graph file: $graph_file)" >> "$LOG" 2>/dev/null || true
      cat >&2 << EOF
🚦 dispatch-gate: task-graph tồn tại ($graph_file) nhưng prompt không có marker "task-graph #<id>" khớp row trong file.
   Thêm marker "task-graph #<id>" khớp đúng subtask, hoặc xoá graph file nếu task này không thuộc graph.
EOF
      exit 2
    fi

    row=$(awk -F'|' -v id="$marker_id" '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      { if (trim($2) == id) { print; exit } }
    ' "$graph_file" 2>/dev/null || true)

    if [ -z "$row" ]; then
      echo "$(ts) BLOCK $subagent_type dispatch → id $marker_id không có trong task-graph" >> "$LOG" 2>/dev/null || true
      echo "🚦 dispatch-gate: id $marker_id (từ marker task-graph) không có row nào trong $graph_file." >&2
      exit 2
    fi

    rw=$(echo "$row"     | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $5); print $5 }' 2>/dev/null || true)
    locked=$(echo "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6 }' 2>/dev/null || true)

    if [ "$rw" = "W" ] && [ "$locked" != "yes" ]; then
      echo "$(ts) BLOCK $subagent_type dispatch → subtask #$marker_id là WRITE, locked=$locked" >> "$LOG" 2>/dev/null || true
      cat >&2 << EOF
🚦 dispatch-gate: subtask #$marker_id là WRITE nhưng interface chưa lock (locked=no) — lock interface trong spec trước khi dispatch (orchestrator.md Interface-lock gate).
EOF
      exit 2
    fi
  fi
fi

exit 0
