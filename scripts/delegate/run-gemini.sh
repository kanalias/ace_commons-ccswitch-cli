#!/usr/bin/env bash
# Delegate edit task to Gemini CLI inside an isolated worktree.
# Usage: run-gemini.sh <feat-slug> "<task prompt>" [context-file...]
# Output: prints worktree path + diff summary; never auto-commits.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_common.sh
source "$DIR/_common.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <feat-slug> \"<task>\" [context-file...]" >&2
  exit 1
fi

FEAT="$1"; TASK="$2"; shift 2

scan_task_for_secrets "$TASK" || exit 1

load_env_chain
harden_cli_env
# Gemini CLI uses OAuth by default; GEMINI_API_KEY optional override.

WT="$(ensure_worktree delegate-gemini "$FEAT")"
delegate_log gemini "worktree: $WT"
trap 'delegate_log gemini "exit trap — cleaning empty worktree if clean"; cleanup_worktree_if_clean "$WT"' EXIT

# Hardcoded (2026-07-22): per-call probe spawned the CLI once per candidate
# model to find the "highest tier" — each spawn pays full CLI cold-start
# (~15-60s), so a cold cache made every delegate call take minutes. User
# picked a fixed default (baked in at harness-install time from the source
# repo's .env); override per-call: GEMINI_MODEL=<id>.
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"
delegate_log gemini "model: $GEMINI_MODEL"

# P0 deny-list: never pump secret-bearing files into prompts.
is_secret_path() {
  case "$1" in
    *.env|*.env.*|*/.env|*/.env.*|*/_vault_/*|_vault_/*|*/.env-bootstrap|.env-bootstrap) return 0 ;;
    *id_rsa*|*id_ed25519*|*.pem|*.key|*credentials*.json) return 0 ;;
    *.gpg|*.asc|*/.kube/*|*credentials*|*secret*) return 0 ;;
  esac
  return 1
}

# Build context block from optional paths (cap each file to keep prompt sane).
CTX=""
for p in "$@"; do
  if is_secret_path "$p"; then
    delegate_log gemini "REFUSED secret-bearing path: $p"
    exit 2
  fi
  if [[ -f "$p" ]]; then
    CTX+=$'\n\n--- FILE: '"$p"$' ---\n'
    CTX+="$(head -c 200000 "$p")"
  elif [[ -d "$p" ]]; then
    CTX+=$'\n\n--- DIR LISTING: '"$p"$' ---\n'
    CTX+="$(find "$p" -maxdepth 3 -type f | head -200)"
  fi
done

FULL_PROMPT="$TASK"
[[ -n "$CTX" ]] && FULL_PROMPT="$TASK"$'\n'"$CTX"

cd "$WT"

# Single account, no rotation (2026-07-22): rotation across 6 accounts made a
# quota/error on the first one burn through 5 more full CLI cold-starts
# (~15-60s each) before failing or succeeding. Calls `gemini` CLI directly —
# uses whatever OAuth cred is already active in ~/.gemini/oauth_creds.json.

# Agentic edit mode: gemini reads+edits files in cwd (the worktree).
# --approval-mode auto_edit auto-approves edit tools only (not arbitrary shell) —
# safer than --yolo. P0: pass prompt via -p argv is required for agentic mode
# (stdin -p - is single-shot text-only, no tool use); worktree isolation is the
# containment boundary instead of avoiding argv (prompt has no secrets — see deny-list above).
# --allowed-mcp-server-names none-such-server: delegate task never needs user's
# personal MCP servers (notion/gdrive/etc) — skipping their handshake cuts ~10s
# off every call (measured 2026-07-22). Override: GEMINI_MCP_SERVERS=<names...>.
# P0: enforce wall-clock timeout so a hung/looping CLI never blocks the
# orchestrator indefinitely. Override: DELEGATE_TIMEOUT_SECS=<seconds>.
DELEGATE_TIMEOUT_SECS="${DELEGATE_TIMEOUT_SECS:-600}"
_HEAD_BEFORE="$(git -C "$WT" rev-parse HEAD 2>/dev/null || echo "")"
_START_EPOCH="$(date +%s)"
set +e
run_logged gemini "$FEAT" with_timeout "$DELEGATE_TIMEOUT_SECS" gemini \
  -p "$FULL_PROMPT" --approval-mode auto_edit -m "$GEMINI_MODEL" \
  --allowed-mcp-server-names "${GEMINI_MCP_SERVERS:-none-such-server}"
_GEMINI_STATUS=$?
set -e

delegate_log gemini "diff summary:"
git -C "$WT" diff --stat >&2 || true
report_run_status "$WT" "$_START_EPOCH"
delegate_log gemini "log saved: $DELEGATE_RUN_LOG"
echo "WORKTREE=$WT"
if ! check_no_new_commits "$WT" "$_HEAD_BEFORE"; then
  delegate_log gemini "FAIL: gemini auto-committed inside worktree"
  exit 1
fi
if [[ "$_GEMINI_STATUS" -eq 124 ]]; then
  delegate_log gemini "FAIL: gemini timed out after ${DELEGATE_TIMEOUT_SECS}s"
  exit 124
elif [[ "$_GEMINI_STATUS" -ne 0 ]]; then
  delegate_log gemini "FAIL: gemini exited $_GEMINI_STATUS"
  exit "$_GEMINI_STATUS"
fi
