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
FILES=("$@")

scan_task_for_secrets "$TASK" || exit 1

load_env_chain
harden_cli_env

# Endpoint selection (2026-07-15) — deliberate scope override: route delegate
# DeepSeek qua 9router prod để đồng bộ với ccswitch (CLI session) + runtime
# deepseek-api adapter. PROXY_9ROUTER_TOKEN + PROXY_9ROUTER_BASE_URL set trong
# .env → dùng 9router (LiteLLM openai-compat driver, model prefix ds/). Nếu 2
# var trống → fallback DeepSeek API gốc (api.deepseek.com) giữ backward-compat.
if [[ -n "${PROXY_9ROUTER_TOKEN:-}" && -n "${PROXY_9ROUTER_BASE_URL:-}" ]]; then
  # 9router path: LiteLLM openai/ prefix + ds/ model prefix (9router routes ds/* → DeepSeek upstream).
  export OPENAI_API_BASE="$PROXY_9ROUTER_BASE_URL"
  export OPENAI_API_KEY="$PROXY_9ROUTER_TOKEN"
  # v4-pro (not -max): user preference 2026-07-22 — both measured ~3min on
  # smoke test (reasoning-model THINKING trace dominates latency either way,
  # -max slightly faster in that one run but user opted for -pro anyway).
  # Default baked in at harness-install time from source repo's .env;
  # override per-call: DEEPSEEK_MODEL=openai/ds/deepseek-v4-pro-max.
  DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-@@DEEPSEEK_MODEL_DEFAULT@@}"
  delegate_log deepseek "endpoint: 9router (via PROXY_9ROUTER_BASE_URL)"
else
  # Fallback: DeepSeek API gốc (aider auto-detects DEEPSEEK_API_KEY).
  require_env DEEPSEEK_API_KEY
  DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek/deepseek-v4-pro}"
  delegate_log deepseek "endpoint: api.deepseek.com (direct fallback)"
fi

# P0 perf fix (2026-07-22) — root-caused via faulthandler.dump_traceback_later
# stack dumps across two separate ~3min-latency smoke runs. Two stacked causes,
# both are the same underlying issue (see PYTHONPATH fix below):
#
# 1. litellm's get_model_cost_map() (litellm_core_utils/get_model_cost_map.py)
#    httpx.get()s raw.githubusercontent.com on every litellm import. Its
#    timeout=5 does NOT bound the underlying TCP connect (httpx/httpcore call
#    socket.create_connection with no deadline there), so this can still block
#    far longer than 5s. LITELLM_LOCAL_MODEL_COST_MAP=True skips the fetch
#    entirely (measured: import litellm 21.8s -> 1.3s). No functional loss —
#    our custom 9router model aliases (ds/deepseek-v4-pro etc.) aren't in the
#    cost map either way, so pricing lookup already fell through before this.
export LITELLM_LOCAL_MODEL_COST_MAP=True

# 2. The real bottleneck: 9router.proxy.com is dual-stack (Cloudflare),
#    and its IPv6 route is blackholed from this network (SYN sent, silently
#    dropped — not a fast reject). Python's synchronous socket.create_connection
#    has no happy-eyeballs: it tries getaddrinfo()'s address list in order
#    (IPv6 first here) and blocks on each until OS-level TCP timeout before
#    trying the next. Every actual completion request paid this tax. Verified
#    directly: raw connect to the resolved IPv6 address timed out (8s cap);
#    same host's IPv4 address connected in 0.11s. lib/sitecustomize.py
#    monkeypatches socket.getaddrinfo to AF_INET-only inside the aider
#    subprocess only (via PYTHONPATH) — scoped fix, no system-wide IPv6
#    disable, no edits to vendored litellm/httpx (which `brew upgrade aider`
#    would wipe out anyway).
export PYTHONPATH="$DIR/lib${PYTHONPATH:+:$PYTHONPATH}"

WT="$(ensure_worktree delegate-deepseek "$FEAT")"
delegate_log deepseek "worktree: $WT"
delegate_log deepseek "model: $DEEPSEEK_MODEL"
trap 'delegate_log deepseek "exit trap — cleaning empty worktree if clean"; cleanup_worktree_if_clean "$WT"' EXIT

cd "$WT"

# P0 bug workaround: aider's GitRepo.__init__ (vendored, not ours to patch)
# calls `git.Repo(fname, search_parent_directories=True)` on the target file
# path when it doesn't exist yet. If the parent dir ALSO doesn't exist (fresh
# worktree, new subdir), GitPython raises NoSuchPathError, git detection
# silently fails ("Git repo: none"), and aider's root falls back to the
# file's own dirname — doubling the path (scripts/lib/scripts/lib/x.sh) and
# leaving the real target empty. Pre-creating parent dirs avoids the failure.
for f in "$@"; do
  mkdir -p "$(dirname "$f")"
done

# Aider headless: no auto-commit, no git suggestions, no analytics, single shot.
# P0: pass key via env — never via argv (leaks to `ps aux`). 9router path uses
# OPENAI_API_* (exported above); fallback path uses DEEPSEEK_API_KEY (aider auto-detects).
# --edit-format diff: aider auto-picks format by matching model name against
# hardcoded patterns in models.py (only "deepseek"+"v3" matches → diff). Our
# 9router alias "openai/ds/deepseek-v4-pro-max" matches none of them, so it
# silently fell back to "whole" (full-file rewrite) while DeepSeek kept
# replying with unified-diff hunks anyway → unparseable, edits silently
# dropped. Forcing diff here makes aider's parser match what the model
# actually outputs, for both the 9router alias and the plain fallback model.
# P0: enforce wall-clock timeout so a hung/looping CLI never blocks the
# orchestrator indefinitely. Override: DELEGATE_TIMEOUT_SECS=<seconds>.
DELEGATE_TIMEOUT_SECS="${DELEGATE_TIMEOUT_SECS:-600}"
_HEAD_BEFORE="$(git -C "$WT" rev-parse HEAD 2>/dev/null || echo "")"
_START_EPOCH="$(date +%s)"
set +e
run_logged deepseek "$FEAT" with_timeout "$DELEGATE_TIMEOUT_SECS" aider \
  --model "$DEEPSEEK_MODEL" \
  --edit-format diff \
  --yes-always \
  --no-auto-commits \
  --no-analytics \
  --no-show-model-warnings \
  --message "$TASK" \
  "$@"
_AIDER_STATUS=$?
set -e
if ! check_no_new_commits "$WT" "$_HEAD_BEFORE"; then
  delegate_log deepseek "FAIL: aider auto-committed inside worktree despite --no-auto-commits"
  exit 1
fi
if [[ "$_AIDER_STATUS" -eq 124 ]]; then
  delegate_log deepseek "FAIL: aider timed out after ${DELEGATE_TIMEOUT_SECS}s"
  exit 124
elif [[ "$_AIDER_STATUS" -ne 0 ]]; then
  delegate_log deepseek "FAIL: aider exited $_AIDER_STATUS"
  exit "$_AIDER_STATUS"
fi

delegate_log deepseek "diff summary:"
git -C "$WT" diff --stat >&2 || true
report_run_status "$WT" "$_START_EPOCH" ${FILES[@]+"${FILES[@]}"}
delegate_log deepseek "log saved: $DELEGATE_RUN_LOG"
echo "WORKTREE=$WT"
