#!/usr/bin/env bash
# Delegate hard reasoning / algo / deep security task to Codex CLI (OpenAI o-series).
# Usage: run-codex.sh <feat-slug> "<task>" [edit|review]
#   edit   → runs in worktree, codex may modify files (no auto-commit)
#   review → read-only, codex outputs analysis text
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_common.sh
source "$DIR/_common.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <feat-slug> \"<task>\" [edit|review]" >&2
  exit 1
fi

FEAT="$1"; TASK="$2"; MODE="${3:-review}"

scan_task_for_secrets "$TASK" || exit 1

load_env_chain
harden_cli_env
# Codex CLI: typically authed via `codex login` (ChatGPT) or OPENAI_API_KEY env.

# Endpoint selection (2026-07-20) — mirror run-aider-deepseek.sh: presence of
# PROXY_9ROUTER_TOKEN + PROXY_9ROUTER_BASE_URL alone decides routing, no opt-in
# flag. route cx/* qua 9router responses API bằng Codex `-c` inline provider
# override (ephemeral — KHÔNG đụng ~/.codex/config.toml global).
# Model map: cx/gpt-5.6-sol = strongest, cx/gpt-5.6-terra = default high,
# cx/gpt-5.6-luna = fastest small-scope. Token qua env_key ref, KHÔNG qua argv.
CODEX_PROVIDER_ARGS=()
if [[ -n "${PROXY_9ROUTER_TOKEN:-}" && -n "${PROXY_9ROUTER_BASE_URL:-}" ]]; then
  export PROXY_CODEX_9R_KEY="$PROXY_9ROUTER_TOKEN"   # env_key ref — token never in argv
  # Default high/balanced Codex model. Override qua PROXY_CODEX_MODEL:
  # cx/gpt-5.6-sol strongest; cx/gpt-5.6-terra default high; cx/gpt-5.6-luna fastest small-scope.
  CODEX_MODEL="${PROXY_CODEX_MODEL:-cx/gpt-5.6-terra}"
  CODEX_PROVIDER_ARGS=(
    -c 'model_providers.nexus9r.name="9router"'
    -c "model_providers.nexus9r.base_url=\"${PROXY_9ROUTER_BASE_URL}\""
    -c 'model_providers.nexus9r.env_key="PROXY_CODEX_9R_KEY"'
    -c 'model_providers.nexus9r.wire_api="responses"'
    -c 'model_provider="nexus9r"'
    -c "model=\"${CODEX_MODEL}\""
  )
  delegate_log codex "endpoint: 9router (opt-in, model=$CODEX_MODEL)"
else
  # OpenAI gốc: set model trực tiếp (không prefix cx/ — đó chỉ là alias 9router).
  # Default baked in at harness-install time from source repo's .env;
  # override qua CODEX_MODEL nếu cần.
  # P1: validate SOME auth mechanism resolves before spawning the CLI — either
  # OPENAI_API_KEY env, or a prior `codex login` (ChatGPT) leaving auth.json.
  # Don't hard-require OPENAI_API_KEY: `codex login` is a legitimate,
  # documented auth path with no env var involved.
  if [[ -z "${OPENAI_API_KEY:-}" && ! -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]]; then
    echo "ERROR: no Codex auth found — set OPENAI_API_KEY or run 'codex login'" >&2
    exit 1
  fi
  CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-terra}"
  CODEX_PROVIDER_ARGS=(-m "$CODEX_MODEL")
  delegate_log codex "endpoint: OpenAI gốc (codex login / OPENAI_API_KEY), model=$CODEX_MODEL"
fi

delegate_log codex "mode: $MODE"

# P0: enforce wall-clock timeout so a hung/looping CLI never blocks the
# orchestrator indefinitely. Override: DELEGATE_TIMEOUT_SECS=<seconds>.
DELEGATE_TIMEOUT_SECS="${DELEGATE_TIMEOUT_SECS:-600}"

if [[ "$MODE" == "edit" ]]; then
  WT="$(ensure_worktree delegate-codex "$FEAT")"
  delegate_log codex "worktree: $WT"
  trap 'delegate_log codex "exit trap — cleaning empty worktree if clean"; cleanup_worktree_if_clean "$WT"' EXIT
  cd "$WT"
  # exec mode = non-interactive single-shot; auto-edit allowed inside worktree only.
  # ${ARR[@]+…} guard = safe empty-array expansion under `set -u` (bash 3.2 compat).
  _HEAD_BEFORE="$(git -C "$WT" rev-parse HEAD 2>/dev/null || echo "")"
  _START_EPOCH="$(date +%s)"
  set +e
  run_logged codex "$FEAT" with_timeout "$DELEGATE_TIMEOUT_SECS" codex exec ${CODEX_PROVIDER_ARGS[@]+"${CODEX_PROVIDER_ARGS[@]}"} --full-auto "$TASK"
  _CODEX_STATUS=$?
  set -e
  delegate_log codex "diff summary:"
  git -C "$WT" diff --stat >&2 || true
  report_run_status "$WT" "$_START_EPOCH"
  delegate_log codex "log saved: $DELEGATE_RUN_LOG"
  echo "WORKTREE=$WT"
  if ! check_no_new_commits "$WT" "$_HEAD_BEFORE"; then
    delegate_log codex "FAIL: codex auto-committed inside worktree"
    exit 1
  fi
  if [[ "$_CODEX_STATUS" -eq 124 ]]; then
    delegate_log codex "FAIL: codex timed out after ${DELEGATE_TIMEOUT_SECS}s"
    exit 124
  elif [[ "$_CODEX_STATUS" -ne 0 ]]; then
    delegate_log codex "FAIL: codex exited $_CODEX_STATUS"
    exit "$_CODEX_STATUS"
  fi
else
  # Read-only review: run from repo root, no file changes.
  cd "$REPO_ROOT"
  set +e
  run_logged codex "$FEAT" with_timeout "$DELEGATE_TIMEOUT_SECS" codex exec ${CODEX_PROVIDER_ARGS[@]+"${CODEX_PROVIDER_ARGS[@]}"} --sandbox read-only "$TASK"
  _CODEX_STATUS=$?
  set -e
  delegate_log codex "log saved: $DELEGATE_RUN_LOG"
  if [[ "$_CODEX_STATUS" -eq 124 ]]; then
    delegate_log codex "FAIL: codex timed out after ${DELEGATE_TIMEOUT_SECS}s"
    exit 124
  elif [[ "$_CODEX_STATUS" -ne 0 ]]; then
    delegate_log codex "FAIL: codex exited $_CODEX_STATUS"
    exit "$_CODEX_STATUS"
  fi
fi
