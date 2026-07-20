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

load_env_chain
# Gemini CLI uses OAuth by default; GEMINI_API_KEY optional override.

WT="$(ensure_worktree delegate-gemini "$FEAT")"
delegate_log gemini "worktree: $WT"
trap 'delegate_log gemini "exit trap — cleaning empty worktree if clean"; cleanup_worktree_if_clean "$WT"' EXIT

# Auto-detect highest-tier model available on Code Assist tier.
# Cached 24h in ~/.gemini/highest-model.cache. Override per-call: GEMINI_MODEL=<id>.
# Force re-probe: rm ~/.gemini/highest-model.cache (or bash probe-gemini-highest.sh --force).
if [[ -z "${GEMINI_MODEL:-}" ]]; then
  GEMINI_MODEL="$("$DIR/probe-gemini-highest.sh" 2>/dev/null || echo gemini-2.5-pro)"
fi
delegate_log gemini "model: $GEMINI_MODEL"

# P0 deny-list: never pump secret-bearing files into prompts.
is_secret_path() {
  case "$1" in
    *.env|*.env.*|*/.env|*/.env.*|*/_vault_/*|_vault_/*|*/.env-bootstrap|.env-bootstrap) return 0 ;;
    *id_rsa*|*id_ed25519*|*.pem|*.key|*credentials*.json) return 0 ;;
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

# Multi-account rotation. Falls back to single-account mode if gemini-account.sh missing
# or accounts dir empty (backwards compat with pre-rotation setup).
ACCOUNTS_SCRIPT="$DIR/gemini-account.sh"
USE_ROTATION=0
if [[ -x "$ACCOUNTS_SCRIPT" ]] && [[ -d "$HOME/.gemini/accounts" ]]; then
  ACC_COUNT=$(find "$HOME/.gemini/accounts" -maxdepth 1 -name "*.json" \
    ! -name "config.json" ! -name "state.json" | wc -l | tr -d ' ')
  if [[ "$ACC_COUNT" -gt 0 ]]; then
    USE_ROTATION=1
    MAX_ATTEMPTS="$ACC_COUNT"
  fi
fi

# Agentic edit mode: gemini reads+edits files in cwd (the worktree).
# --approval-mode auto_edit auto-approves edit tools only (not arbitrary shell) —
# safer than --yolo. P0: pass prompt via -p argv is required for agentic mode
# (stdin -p - is single-shot text-only, no tool use); worktree isolation is the
# containment boundary instead of avoiding argv (prompt has no secrets — see deny-list above).
run_gemini_edit() {
  gemini -p "$FULL_PROMPT" --approval-mode auto_edit -m "$GEMINI_MODEL"
}

if [[ "$USE_ROTATION" -eq 0 ]]; then
  run_gemini_edit
else
  attempt=0
  ok=0
  while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
    (( attempt++ ))

    next_email="$("$ACCOUNTS_SCRIPT" next 2>/dev/null || true)"
    if [[ -z "$next_email" ]]; then
      delegate_log gemini "ERROR: all accounts on cooldown"
      exit 1
    fi

    current_email="$("$ACCOUNTS_SCRIPT" current 2>/dev/null || echo '')"
    if [[ "$current_email" != "$next_email" ]]; then
      "$ACCOUNTS_SCRIPT" use "$next_email" 2>/dev/null || {
        delegate_log gemini "ERROR: failed to switch to $next_email"
        exit 1
      }
    fi
    delegate_log gemini "attempt $attempt/$MAX_ATTEMPTS account=$next_email"

    stderr_tmp="$(mktemp)"
    if run_gemini_edit 2>"$stderr_tmp"; then
      cat "$stderr_tmp" >&2
      rm -f "$stderr_tmp"
      "$ACCOUNTS_SCRIPT" clear-cooldown "$next_email" >/dev/null 2>&1 || true
      ok=1
      break
    fi

    if grep -qiE 'RESOURCE_EXHAUSTED|429|quota exceeded|quota|rate.?limit' "$stderr_tmp"; then
      delegate_log gemini "quota hit on $next_email — cooldown 3600s"
      "$ACCOUNTS_SCRIPT" cooldown "$next_email" 3600 >/dev/null 2>&1 || true
      rm -f "$stderr_tmp"
      continue
    fi

    # Non-quota error — fail fast, don't burn accounts.
    delegate_log gemini "non-quota error on $next_email:"
    head -c 4096 "$stderr_tmp" >&2
    rm -f "$stderr_tmp"
    exit 1
  done

  if [[ "$ok" -ne 1 ]]; then
    delegate_log gemini "ERROR: exhausted $MAX_ATTEMPTS attempts, all accounts hit quota"
    exit 1
  fi
fi

delegate_log gemini "diff summary:"
git -C "$WT" diff --stat >&2 || true
echo "WORKTREE=$WT"
