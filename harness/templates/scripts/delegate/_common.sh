#!/usr/bin/env bash
# Shared helpers for LLM delegate wrappers (deepseek/gemini/codex).
# Loaded via: source "$(dirname "$0")/_common.sh"
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not inside a git repository — refusing to run" >&2
  exit 1
}

# Load env chain (delegate wrapper scope only) — provide LLM API keys cho
# Aider/Codex/Gemini CLI. Production runtime code KHÔNG đọc qua hàm này;
# code Nexus đọc trực tiếp từ `_vault_/oauth/` + dotenv.config() chain
# trong server.js.
# Order: .env.local → .env  (2026-07-09 consolidation: former vault cache
#       .env.runtime + trust-root .env-bootstrap now merged into .env.
#       2026-07-20 consolidation: ai-proxy/.env.pro moved to repo root as
#       .env — dropped from this loop, already covered by the 2nd entry).
# Holds 9router creds as proxy_host/proxy_key (ccswitch's own var names);
# aliased below to PROXY_9ROUTER_BASE_URL/_TOKEN.
# Only if files exist. Never echo values.
load_env_chain() {
  local f
  for f in .env.local .env; do
    if [[ -f "$REPO_ROOT/$f" ]]; then
      # Manual parser — `set -a; source` fails on values with unquoted spaces
      # (e.g. paths with spaces in env). Read line-by-line, export KEY=VALUE only.
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
          local k="${BASH_REMATCH[1]}" v="${BASH_REMATCH[2]}"
          # Strip surrounding quotes
          [[ "$v" =~ ^\"(.*)\"$ ]] && v="${BASH_REMATCH[1]}"
          [[ "$v" =~ ^\'(.*)\'$ ]] && v="${BASH_REMATCH[1]}"
          export "$k=$v"
        fi
      done < "$REPO_ROOT/$f"
    fi
  done

  # ai-proxy/.env.pro var names (proxy_host/proxy_key) → PROXY_9ROUTER_* generic
  # names delegate wrappers expect. Only set if not already set by host env.
  : "${PROXY_9ROUTER_BASE_URL:=${proxy_host:-}}"
  : "${PROXY_9ROUTER_TOKEN:=${proxy_key:-}}"
  export PROXY_9ROUTER_BASE_URL PROXY_9ROUTER_TOKEN

  # Project-prefix → generic alias (Aider/Codex/Gemini CLIs expect generic names).
  # Only set generic if currently empty (don't override host-level env).
  # deepseek_api_key = raw var name in ai-proxy/.env.pro; PROXY_DEEPSEEK_API_KEY
  # kept as alt override name for host-level env.
  : "${DEEPSEEK_API_KEY:=${PROXY_DEEPSEEK_API_KEY:-${deepseek_api_key:-}}}"
  : "${OPENAI_API_KEY:=${PROXY_OPENAI_API_KEY:-}}"
  : "${ANTHROPIC_API_KEY:=${PROXY_ANTHROPIC_API_KEY:-}}"
  # GEMINI_USE_OAUTH=1 → route Gemini CLI qua OAuth Workspace + GOOGLE_CLOUD_PROJECT
  # (Code Assist paid tier). Skip alias để CLI không thấy API key.
  if [[ "${GEMINI_USE_OAUTH:-0}" != "1" ]]; then
    : "${GEMINI_API_KEY:=${PROXY_GOOGLE_API_KEY:-}}"
    : "${GOOGLE_API_KEY:=${PROXY_GOOGLE_API_KEY:-}}"
    export GEMINI_API_KEY GOOGLE_API_KEY
  else
    unset GEMINI_API_KEY GOOGLE_API_KEY
  fi
  export DEEPSEEK_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY
}

# Ensure agent worktree per rules/system/12-parallel-subagent.md.
# Usage: ensure_worktree <agent-id> <feat-slug>
# Echoes worktree path to stdout.
ensure_worktree() {
  local agent_id="$1" feat="${2:-adhoc}"
  # P0 security: feat-slug + agent-id chỉ chấp nhận alphanumeric + dash/underscore.
  # Tránh path traversal (`../`) hoặc git branch name injection.
  if [[ ! "$agent_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: agent-id invalid chars (alphanumeric/-/_ only): $agent_id" >&2
    return 1
  fi
  if [[ ! "$feat" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: feat-slug invalid chars (alphanumeric/-/_ only): $feat" >&2
    return 1
  fi
  local wt="$REPO_ROOT/.claude/worktrees/$agent_id/$feat"
  local branch="delegate/$agent_id-$feat"
  if [[ ! -d "$wt" ]]; then
    mkdir -p "$(dirname "$wt")"
    git -C "$REPO_ROOT" worktree add -b "$branch" "$wt" HEAD >&2
  else
    # P1: refuse to reuse a dirty worktree — contamination risk.
    if ! git -C "$wt" diff --quiet || ! git -C "$wt" diff --cached --quiet; then
      echo "ERROR: worktree $wt is dirty — clean or remove before re-running" >&2
      return 1
    fi
  fi
  echo "$wt"
}

# Cleanup a worktree if it has no changes (idempotent best-effort).
cleanup_worktree_if_clean() {
  local wt="$1"
  [[ -d "$wt" ]] || return 0
  if git -C "$wt" diff --quiet && git -C "$wt" diff --cached --quiet \
     && [[ -z "$(git -C "$wt" status --porcelain)" ]]; then
    delegate_log cleanup "removing empty worktree: $wt"
    if ! git -C "$REPO_ROOT" worktree remove --force "$wt" >&2; then
      delegate_log cleanup "WARNING: worktree remove failed for $wt — pruning stale entries"
      git -C "$REPO_ROOT" worktree prune >&2 || true
    fi
  fi
}

# Run a command with a timeout, if a timeout binary is available.
# macOS ships neither `timeout` (GNU coreutils) nor `gtimeout` by default
# (needs `brew install coreutils`) — degrade gracefully instead of hard-failing
# every delegate call on stock macOS.
# Usage: with_timeout <seconds> <cmd...>
with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    delegate_log timeout "WARNING: no timeout/gtimeout binary found — running without a time limit (brew install coreutils to enable)"
    "$@"
  fi
}

# Progress visibility: delegate CLI runs are long (5-10 min) and Claude Code only
# shows Bash output after exit. Tee everything to a log file the user (or a
# Monitor tail) can follow live, and emit a heartbeat line every 30s so the log
# visibly moves even when the CLI is silent.
# Usage: run_logged <agent-id> <feat-slug> <cmd...>
# Sets: DELEGATE_RUN_LOG (path). Returns the command's exit status.
run_logged() {
  local agent_id="$1" feat="$2"; shift 2
  local log_dir="$REPO_ROOT/.claude/state/delegate-runs"
  mkdir -p "$log_dir"
  # Light rotation — drop logs older than 7 days. Best-effort: never blocks a run.
  find "$log_dir" -type f -name '*.log' -mtime +7 -delete 2>/dev/null || true

  local log="$log_dir/${agent_id}-${feat}-$(date +%s).log"
  DELEGATE_RUN_LOG="$log"
  export DELEGATE_RUN_LOG
  : > "$log"
  delegate_log "$agent_id" "▶ live log: tail -f $log"

  local start_epoch hb_pid
  start_epoch="$(date +%s)"
  # `{ ...; } </dev/null >/dev/null 2>&1 &` (brace group), NOT `( ... ) &`
  # (subshell): on bash 3.2 (macOS default) a backgrounded `( ... )` subshell
  # still holds the parent's stdout/stderr pipe open even after redirecting
  # its own fds, so anything capturing this function's output (bats `run`,
  # command substitution) hangs waiting for that pipe to close until the
  # 30s heartbeat loop itself dies. The brace form doesn't fork a subshell
  # and closes cleanly.
  { while sleep 30; do
      printf '[delegate:%s %s] ⏳ running %ds\n' \
        "$agent_id" "$(date +%H:%M:%S)" "$(( $(date +%s) - start_epoch ))" >> "$log"
    done; } </dev/null >/dev/null 2>&1 &
  hb_pid=$!
  # RETURN trap covers early-return paths too, not just the normal fallthrough
  # below — belt-and-suspenders against an orphaned heartbeat subshell.
  trap 'kill "$hb_pid" 2>/dev/null; wait "$hb_pid" 2>/dev/null' RETURN

  "$@" 2>&1 | tee -a "$log"
  local status="${PIPESTATUS[0]}"

  kill "$hb_pid" 2>/dev/null || true
  wait "$hb_pid" 2>/dev/null || true
  trap - RETURN

  return "$status"
}

# Require a non-empty env var without printing its value.
require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: env $name not set (load .env-bootstrap chain or vault row)" >&2
    return 1
  fi
}

# Log line to stderr with timestamp + delegate id.
delegate_log() {
  local id="$1"; shift
  printf '[delegate:%s %s] %s\n' "$id" "$(date +%H:%M:%S)" "$*" >&2
}

# Parent-shell env can override our safety CLI flags. Aider reads AIDER_* from
# env/dotenv, so a leaked AIDER_AUTO_COMMITS=true would beat --no-auto-commits.
# Unset only the *safety-critical* knobs; keep model/endpoint override vars
# (DEEPSEEK_MODEL, GEMINI_MODEL, PROXY_9ROUTER_*) which are legitimate overrides.
harden_cli_env() {
  unset AIDER_AUTO_COMMITS AIDER_GIT AIDER_YES AIDER_YES_ALWAYS \
        AIDER_AUTO_LINT AIDER_AUTO_TEST AIDER_DRY_RUN \
        CODEX_UNSAFE_ALLOW_NO_SANDBOX 2>/dev/null || true
}

# `exit 0` from a delegate CLI does NOT prove work was done — it can silently
# no-op (permission wall, drifted off-task, unparseable diff format). Label
# the run so the caller (Opus) can tell "done" from "looked fine but nothing
# changed". Advisory only: never fails, never prints file contents.
# Usage: report_run_status <worktree_path> <start_epoch> [expected_file...]
report_run_status() {
  local wt="$1" start="$2"
  shift 2 || true
  local expected=("$@")

  if [[ ${#expected[@]} -eq 0 ]]; then
    if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
      echo "STATUS=done"
    else
      echo "STATUS=degraded (worktree clean — likely silent no-op)"
    fi
    return 0
  fi

  local f path mtime touched=0 missing=()
  for f in "${expected[@]}"; do
    case "$f" in
      /*) path="$f" ;;
      *) path="$wt/$f" ;;
    esac
    mtime="$(stat -f%m "$path" 2>/dev/null || stat -c%Y "$path" 2>/dev/null || echo "")"
    if [[ -n "$mtime" && "$mtime" -ge "$start" ]]; then
      touched=$((touched + 1))
    else
      missing+=("$f")
    fi
  done

  local total=${#expected[@]}
  if [[ "$touched" -eq "$total" ]]; then
    echo "STATUS=done"
  elif [[ "$touched" -eq 0 ]]; then
    echo "STATUS=degraded (0/$total — likely silent no-op)"
  else
    local csv
    csv="$(IFS=,; echo "${missing[*]}")"
    echo "STATUS=partial ($touched/$total modified; missing: $csv)"
  fi
  return 0
}

# Only aider has --no-auto-commits; codex/gemini CLIs have no equivalent flag,
# so they could silently commit inside the worktree without the wrapper
# noticing. Capture HEAD before running the CLI (`git -C "$wt" rev-parse HEAD`
# — a fresh worktree branch always has one), then diff after. Wrapper adds
# aider too for defense-in-depth (cheap).
# Usage: check_no_new_commits <worktree_dir> <head_before>
# Returns 0 if HEAD unchanged (safe), 1 if the CLI committed. Prints a warning
# to stderr on detection — never prints commit contents.
check_no_new_commits() {
  local wt="$1" before="$2" after
  after="$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "")"
  if [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
    echo "WARNING: CLI committed inside worktree ($before -> $after) — delegate wrappers must never auto-commit (Opus reviews diff before merge/discard)." >&2
    return 1
  fi
  return 0
}

# TASK prompt flows into CLI argv (visible ps aux) + gets teed into
# .claude/state/delegate-runs/*.log by run_logged — neither path is scanned
# for secrets otherwise. High-confidence regexes kept in sync manually with
# hooks/pre-edit-content-scan.sh (see .claude/rules/common/secrets-no-printout.md).
# Usage: scan_task_for_secrets "$TASK"  — call BEFORE the CLI/log ever see it.
# Prints which pattern matched to stderr (never the matched substring).
# Returns 1 on match, 0 if clean.
scan_task_for_secrets() {
  local task="$1"
  local -a _regexes=(
    'sk-ant-[A-Za-z0-9_-]{20,}'
    'sk-[A-Za-z0-9]{32,}'
    'AIza[0-9A-Za-z_-]{35}'
    'gh[posru]_[A-Za-z0-9]{36}'
    'xai-[A-Za-z0-9]{20,}'
    'AKIA[0-9A-Z]{16}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    '(sk|rk)_live_[A-Za-z0-9]{24,}'
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    '[a-z][a-z0-9+.-]*://[^:@/[:space:]]+:[^@/[:space:]]+@[^[:space:]/]+'
    'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
  )
  local -a _names=(
    "Anthropic key (sk-ant-)"
    "OpenAI-style key (sk-)"
    "Google API key (AIza)"
    "GitHub token (gh[posru]_)"
    "xAI key (xai-)"
    "AWS access key (AKIA)"
    "Slack token (xox[baprs]-)"
    "Stripe-style live key (sk|rk_live_)"
    "PEM private key block"
    "URL với credential nhúng (user:pass@host)"
    "JWT (eyJ...)"
  )
  local i
  for i in "${!_regexes[@]}"; do
    if echo "$task" | grep -E -q -- "${_regexes[$i]}"; then
      echo "ERROR: TASK chứa pattern giống secret (${_names[$i]}) — KHÔNG pass key vào prompt (rule delegate-llm.md), dùng env thay thế" >&2
      return 1
    fi
  done
  return 0
}
