#!/usr/bin/env bash
# Claude Code SessionStart hook. Merge of session-start-ledger.sh (stdout
# inject, unchanged) + session-start-banner.sh (rút gọn — routing table đầy
# đủ đã có ở .claude/rules/common/orchestrator.md always-load, budget section
# đã có ở token-budget.md always-load, không cần lặp ở đây).
set -u

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

# ── ledger (stdout — Claude Code inject làm context đầu session) ───────────
project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
ledger="$project_dir/.claude/state/orchestrator-ledger.md"

if [ -f "$ledger" ]; then
  # Per-entry TTL prune (48h) — ISO-8601 UTC timestamps compare lexicographically,
  # no per-line date parsing needed. Fail-open: any prune error leaves file as-is.
  cutoff=$(date -u -v-48H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || cutoff=$(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || cutoff=""

  if [ -n "$cutoff" ] && command -v awk >/dev/null 2>&1; then
    tmp="$ledger.tmp.$$"
    if awk -v cutoff="$cutoff" '
      /^- \[/ {
        rest = substr($0, 4)
        p = index(rest, "]")
        if (p > 0) {
          ts = substr(rest, 1, p - 1)
          if (ts >= cutoff) print $0
        }
      }
    ' "$ledger" >"$tmp" 2>/dev/null; then
      mv "$tmp" "$ledger" 2>/dev/null || rm -f "$tmp"
    else
      rm -f "$tmp" 2>/dev/null || true
    fi
  fi

  if [ -f "$ledger" ]; then
    if [ -s "$ledger" ]; then
      echo "📋 Orchestrator ledger dở dang từ session trước (xoá file .claude/state/orchestrator-ledger.md nếu đã xong):"
      tail -n 30 "$ledger"
    else
      rm -f "$ledger"
    fi
  fi
fi

# ── task-graph banner (stdout — resume hint từ orchestrator plan) ──────────
graph="$project_dir/.claude/state/task-graph.md"
if [ -f "$graph" ]; then
  status=$(grep -m1 '^status:' "$graph" 2>/dev/null | sed 's/^status:[[:space:]]*//') || status=""
  if [ -n "$status" ] && [ "$status" != "done" ]; then
    echo "📊 Task-graph dở dang (status: $status) — đọc .claude/state/task-graph.md để resume:"
    cat "$graph"
  elif [ "$status" = "done" ]; then
    rm -f "$graph"
  fi
fi

# ── cache hygiene (silent, fail-open — advisory hook, no stdout) ────────────
{
  cache_dir="${HOME}/.cache/claude-code-ccswitch-cli-claude"
  if [ -d "$cache_dir" ]; then
    find "$cache_dir" -maxdepth 1 -name 'stuck-window-*' -type f -mtime +7 -delete 2>/dev/null || true

    for _logname in orchestrator-gate.log dispatch-gate.log orchestration.jsonl; do
      _logf="$cache_dir/$_logname"
      if [ -f "$_logf" ]; then
        _size=$(wc -c <"$_logf" 2>/dev/null | tr -d ' ')
        if [ -n "$_size" ] && [ "$_size" -gt 512000 ] 2>/dev/null; then
          _tmp="$_logf.tmp.$$"
          if tail -n 500 "$_logf" >"$_tmp" 2>/dev/null; then
            mv "$_tmp" "$_logf" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
          else
            rm -f "$_tmp" 2>/dev/null
          fi
        fi
      fi
    done
  fi
} >/dev/null 2>&1 || true

# ── banner (stderr — advisory, rút gọn) ─────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  jq KHÔNG có trong PATH — mọi gate hook (orchestrator/bash/dispatch/verdict) đang fail-open = KHÔNG enforcement. brew install jq" >&2
fi

echo "🚦 Orchestrator gate ACTIVE — routing: .claude/rules/common/orchestrator.md" >&2

if [ -n "${HARNESS_RISK_DIRS:-}" ]; then
  echo "🚦 RISK-PATH DENYLIST: ${HARNESS_RISK_DIRS} — delegate-gemini/delegate-deepseek bị chặn (exit 2) dù đang chạy trong subagent." >&2
  echo "   Chỉ delegate-codex/delegate-sonnet được sửa. Không có bypass (security boundary, không phải size-S convenience)." >&2
fi

GATE_LOG="${HOME}/.cache/claude-code-ccswitch-cli-claude/orchestrator-gate.log"
if [ -f "$GATE_LOG" ]; then
  n_block=$(grep -c ' BLOCK ' "$GATE_LOG" 2>/dev/null); n_block=${n_block:-0}
  n_bypass=$(grep -c ' BYPASS ' "$GATE_LOG" 2>/dev/null); n_bypass=${n_bypass:-0}
  if [ "$n_block" -gt 0 ] || [ "$n_bypass" -gt 0 ]; then
    echo "🚦 orchestrator-gate history: ${n_block} block · ${n_bypass} bypass (${GATE_LOG})" >&2
  fi
fi

exit 0
