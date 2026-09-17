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

load_env_chain
# Codex CLI: typically authed via `codex login` (ChatGPT) or OPENAI_API_KEY env.

# Endpoint selection (2026-07-20) — mirror run-aider-deepseek.sh: presence of
# PROXY_9ROUTER_TOKEN + PROXY_9ROUTER_BASE_URL alone decides routing, no opt-in
# flag. route cx/* qua 9router responses API bằng Codex `-c` inline provider
# override (ephemeral — KHÔNG đụng ~/.codex/config.toml global).
# ✅ Verified working 2026-07-15 với cx/gpt-5.5 + cx/gpt-5.4-mini qua Codex CLI thật.
# ⚠️ cx/gpt-5.6-sol (top-tier) route tới upstream reject Codex full-payload
# `input[].content` (HTTP 400) — dùng 5.5 default, tránh sol tới khi 9router fix.
# Token qua env_key ref, KHÔNG qua argv.
CODEX_PROVIDER_ARGS=()
if [[ -n "${PROXY_9ROUTER_TOKEN:-}" && -n "${PROXY_9ROUTER_BASE_URL:-}" ]]; then
  export PROXY_CODEX_9R_KEY="$PROXY_9ROUTER_TOKEN"   # env_key ref — token never in argv
  # Default cx/gpt-5.5 (verified working qua Codex CLI 2026-07-15). cx/gpt-5.6-sol
  # (top-tier) route tới upstream reject Codex full-payload `input[].content` (HTTP 400);
  # 5.5 + 5.4-mini nhận OK. Override qua PROXY_CODEX_MODEL nếu cần.
  CODEX_MODEL="${PROXY_CODEX_MODEL:-cx/gpt-5.5}"
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
  delegate_log codex "endpoint: OpenAI gốc (codex login / OPENAI_API_KEY)"
fi

delegate_log codex "mode: $MODE"

if [[ "$MODE" == "edit" ]]; then
  WT="$(ensure_worktree delegate-codex "$FEAT")"
  delegate_log codex "worktree: $WT"
  trap 'delegate_log codex "exit trap — cleaning empty worktree if clean"; cleanup_worktree_if_clean "$WT"' EXIT
  cd "$WT"
  # exec mode = non-interactive single-shot; auto-edit allowed inside worktree only.
  # ${ARR[@]+…} guard = safe empty-array expansion under `set -u` (bash 3.2 compat).
  codex exec ${CODEX_PROVIDER_ARGS[@]+"${CODEX_PROVIDER_ARGS[@]}"} --full-auto "$TASK"
  delegate_log codex "diff summary:"
  git -C "$WT" diff --stat >&2 || true
  echo "WORKTREE=$WT"
else
  # Read-only review: run from repo root, no file changes.
  cd "$REPO_ROOT"
  codex exec ${CODEX_PROVIDER_ARGS[@]+"${CODEX_PROVIDER_ARGS[@]}"} --sandbox read-only "$TASK"
fi
