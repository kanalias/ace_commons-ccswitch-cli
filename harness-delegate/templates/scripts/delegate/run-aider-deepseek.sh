#!/usr/bin/env bash
# Delegate edit task to Aider + DeepSeek inside an isolated worktree.
# Usage: run-aider-deepseek.sh <feat-slug> "<task spec>" <file1> [file2 ...]
# Output: prints worktree path + diff summary; never auto-commits.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_common.sh
source "$DIR/_common.sh"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <feat-slug> \"<task>\" <file...>" >&2
  exit 1
fi

FEAT="$1"; TASK="$2"; shift 2

load_env_chain

# Endpoint selection (2026-07-15) — deliberate scope override: route delegate
# DeepSeek qua 9router prod để đồng bộ với ccswitch (CLI session) + runtime
# deepseek-api adapter. PROXY_9ROUTER_TOKEN + PROXY_9ROUTER_BASE_URL set trong
# .env → dùng 9router (LiteLLM openai-compat driver, model prefix ds/). Nếu 2
# var trống → fallback DeepSeek API gốc (api.deepseek.com) giữ backward-compat.
if [[ -n "${PROXY_9ROUTER_TOKEN:-}" && -n "${PROXY_9ROUTER_BASE_URL:-}" ]]; then
  # 9router path: LiteLLM openai/ prefix + ds/ model prefix (9router routes ds/* → DeepSeek upstream).
  export OPENAI_API_BASE="$PROXY_9ROUTER_BASE_URL"
  export OPENAI_API_KEY="$PROXY_9ROUTER_TOKEN"
  DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-openai/ds/deepseek-v4-pro-max}"
  delegate_log deepseek "endpoint: 9router (via PROXY_9ROUTER_BASE_URL)"
else
  # Fallback: DeepSeek API gốc (aider auto-detects DEEPSEEK_API_KEY).
  require_env DEEPSEEK_API_KEY
  DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek/deepseek-v4-pro}"
  delegate_log deepseek "endpoint: api.deepseek.com (direct fallback)"
fi

WT="$(ensure_worktree delegate-deepseek "$FEAT")"
delegate_log deepseek "worktree: $WT"
delegate_log deepseek "model: $DEEPSEEK_MODEL"
trap 'delegate_log deepseek "exit trap — cleaning empty worktree if clean"; cleanup_worktree_if_clean "$WT"' EXIT

cd "$WT"

# Aider headless: no auto-commit, no git suggestions, no analytics, single shot.
# P0: pass key via env — never via argv (leaks to `ps aux`). 9router path uses
# OPENAI_API_* (exported above); fallback path uses DEEPSEEK_API_KEY (aider auto-detects).
aider \
  --model "$DEEPSEEK_MODEL" \
  --yes-always \
  --no-auto-commits \
  --no-analytics \
  --no-show-model-warnings \
  --message "$TASK" \
  "$@"

delegate_log deepseek "diff summary:"
git -C "$WT" diff --stat >&2 || true
echo "WORKTREE=$WT"
