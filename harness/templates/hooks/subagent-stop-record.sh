#!/usr/bin/env bash
# SubagentStop hook (no matcher — fires for every subagent). Merge of
# stop-verdict-record.sh + subagent-stop-ledger.sh — parse payload once:
#   (a) append 1 dòng ledger (kèm verdict) vào .claude/state/orchestrator-ledger.md + rotate 200 dòng
#   (b) nếu text có VERDICT: APPROVE|REVISE → ghi .claude/state/last-verdict
#   (c) append metrics JSONL vào ~/.cache/claude-code-@@PROJECT_SLUG@@/orchestration.jsonl
# Advisory-only, luôn exit 0.
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

agent_id=$(echo "$payload" | jq -r '.agent_id // "?"' 2>/dev/null) || exit 0
subagent_type=$(echo "$payload" | jq -r '.agent_type // "?"' 2>/dev/null) || exit 0
session_id=$(echo "$payload" | jq -r '.session_id // "?"' 2>/dev/null) || session_id="?"
text=$(echo "$payload" | jq -r '
  .last_assistant_message
  // .transcript_summary
  // (. | tostring)
  // empty' 2>/dev/null || true)

project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
state_dir="$project_dir/.claude/state"
mkdir -p "$state_dir"

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── parse verdict once — dùng cho cả ledger + last-verdict + metrics ───────
verdict="-"
if [ -n "$text" ]; then
  v=$(echo "$text" | grep -oE 'VERDICT:[[:space:]]*(APPROVE|REVISE)' | tail -1 | grep -oE 'APPROVE|REVISE' || true)
  [ -n "$v" ] && verdict="$v"
fi

# ── (a) ledger append + rotate ──────────────────────────────────────────────
# Skip entirely when payload had no agent_id — avoids junk "agent_id=?" lines.
ledger="$state_dir/orchestrator-ledger.md"
if [ "$agent_id" != "?" ]; then
  echo "- [$ts] subagent done: agent_id=$agent_id type=$subagent_type session=$session_id verdict=$verdict" >>"$ledger"

  if [ -f "$ledger" ]; then
    line_count=$(wc -l <"$ledger" | tr -d ' ')
    if [ "${line_count:-0}" -gt 200 ]; then
      tmp="$ledger.tmp.$$"
      tail -n 200 "$ledger" >"$tmp" && mv "$tmp" "$ledger"
    fi
  fi
fi

# ── (b) verdict record ──────────────────────────────────────────────────────
if [ "$verdict" != "-" ]; then
  echo "$verdict $ts" > "$state_dir/last-verdict"
fi

# ── (c) metrics JSONL — skip khi không có agent_id ──────────────────────────
if [ "$agent_id" != "?" ]; then
  cache_dir="${HOME}/.cache/claude-code-@@PROJECT_SLUG@@"
  mkdir -p "$cache_dir" 2>/dev/null && jq -nc \
    --arg ts "$ts" \
    --arg agent_id "$agent_id" \
    --arg type "$subagent_type" \
    --arg verdict "$verdict" \
    '{ts:$ts, agent_id:$agent_id, type:$type, verdict:$verdict}' \
    >>"$cache_dir/orchestration.jsonl" 2>/dev/null || true
fi

exit 0
