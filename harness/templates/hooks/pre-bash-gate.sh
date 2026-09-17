#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Merge of pre-bash-orchestrator-gate.sh +
# pre-bash-git-push-gate.sh + pre-bash-merge-verdict-gate.sh.
#
# Order matters:
#   1) git-push gate    — runs for EVERYONE (main + subagent), no agent_id check.
#   2) merge-verdict gate — runs for EVERYONE (main + subagent), no agent_id check.
#   2.5) integration-verify gate — main-agent only. Blocks `git commit` while
#      .claude/state/task-graph.md says status: integrating and
#      integration-status != pass (orchestrator.md: Integration verify).
#   3) orchestrator gate  — subagent (agent_id set) short-circuit allow, THEN
#      direct-CLI bypass block, THEN ORCHESTRATOR_GATE_BYPASS=1 hatch, THEN
#      bash-write-core pattern block.
#
# INVARIANT: only step 3 discriminates main vs subagent. Steps 1-2 fire
# regardless of agent_id (their original scripts never checked it).
#
# THREAT MODEL (step 3): chống Opus lười/nhầm vô ý, KHÔNG chống adversary —
# command-string heuristic, không phải sandbox.
#
# Output: exit 0 = allow · exit 2 = block (stderr shown to model).
# Fail-open: thiếu jq / payload không JSON → allow.
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

LOG="${HOME}/.cache/claude-code-@@PROJECT_SLUG@@/orchestrator-gate.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
ts() { date '+%Y-%m-%dT%H:%M:%S'; }

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0

cmd=$(echo "$payload"      | jq -r '.tool_input.command // empty')
agent_id=$(echo "$payload" | jq -r '.agent_id // empty')

[ -z "$cmd" ] && exit 0

# ── 1) git-push gate (everyone) ─────────────────────────────────────────────
if ! echo "$cmd" | grep -Eq 'GIT_PUSH_GATE_OK=1'; then
  if echo "$cmd" | grep -Eq '(^|[;&|]|[[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-]+)?)*[[:space:]]+push([[:space:]]|$)'; then
    echo "🚨 pre-bash-git-push-gate: raw 'git push' bị chặn." >&2
    echo "Chạy /git-push-safety (test + gitleaks + /check-hardcode + hỏi confirm) thay vì push thẳng." >&2
    echo "Nếu đã qua gate và user đã confirm, push với prefix: GIT_PUSH_GATE_OK=1 git push ..." >&2
    exit 2
  fi
fi

# ── 2) merge-verdict gate (everyone) ────────────────────────────────────────
if echo "$cmd" | grep -Eq '\bgit\b.*\bmerge\b' && echo "$cmd" | grep -Eq '(feat|fix|chore|refactor|hotfix)/|\.claude/worktrees/'; then
  project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
  verdict_file="$project_dir/.claude/state/last-verdict"
  if [ -f "$verdict_file" ] && find "$verdict_file" -mmin -240 2>/dev/null | grep -q . && grep -q 'REVISE' "$verdict_file"; then
    cat >&2 << 'EOF'
❌ merge chặn: code-reviewer verdict REVISE — chạy lại review tới APPROVE hoặc xoá .claude/state/last-verdict
EOF
    exit 2
  fi
fi

# ── 2.5) integration-verify gate (main-agent only) ──────────────────────────
if [ -z "$agent_id" ] && echo "$cmd" | grep -Eq '(^|[;&|]|[[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-]+)?)*[[:space:]]+commit([[:space:]]|$)'; then
  project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
  graph_file="$project_dir/.claude/state/task-graph.md"
  if [ -f "$graph_file" ]; then
    graph_status=$(grep '^status:' "$graph_file" 2>/dev/null | head -1 | awk -F: '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    integ_status=$(grep '^integration-status:' "$graph_file" 2>/dev/null | head -1 | awk -F: '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    if [ "$graph_status" = "integrating" ] && [ "$integ_status" != "pass" ]; then
      echo "$(ts) BLOCK main-agent git-commit-during-integrating (integration-status=${integ_status:-<empty>}) → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
      cat >&2 << EOF
🚦 integration-verify-gate: task-graph đang integrating nhưng integration-status=${integ_status:-<empty>} — chạy integration verify (test suite/build) trên branch đã ghép, set integration-status: pass trong .claude/state/task-graph.md rồi mới commit tổng (orchestrator.md: Integration verify)
EOF
      exit 2
    fi
  fi
fi

# ── 3) orchestrator gate (main-agent only) ──────────────────────────────────
# Subagent Bash → luôn allow (delegate wrapper tự chạy CLI hợp lệ trong đây).
[ -n "$agent_id" ] && exit 0

# Direct-CLI bypass — chặn aider/gemini/codex gọi như command word từ main.
# KHÔNG có bypass (isolation boundary). Anchor vào vị trí command để tránh
# match path/substring (vd "gemini/foo", "mycodex").
if echo "$cmd" | grep -Eq '(^|[;&|(]|&&|\|\||[[:space:]](env|sudo|time|xargs|nice|nohup)[[:space:]])[[:space:]]*(aider|gemini|codex)([[:space:]]|$)'; then
  echo "$(ts) BLOCK main-agent direct-CLI → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
  cat >&2 << 'EOF'
🚦 orchestrator-gate: MAIN agent KHÔNG gọi thẳng aider/gemini/codex qua Bash.
   Bypass delegate wrapper = mất worktree isolation + secret redaction.

   Rule: .claude/rules/delegate-llm.md — route qua persona subagent (Task tool):
     • delegate-codex   (hard-reasoning-code / security-sensitive)
     • delegate-sonnet  (L/XL execute)
     • delegate-deepseek (M mechanical / batch)
     • delegate-gemini  (read-only audit / cross-file)

   Không có bypass cho nhánh này (isolation boundary, không phải size-S convenience).
EOF
  exit 2
fi

# Escape hatch cho Bash-write core (size-S 1-line thật sự).
if [ "${ORCHESTRATOR_GATE_BYPASS:-}" = "1" ]; then
  echo "$(ts) BYPASS main-agent bash-write → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
  exit 0
fi

# Bash-write vào core source. Mỗi pattern tự-đủ (đã bao hàm "target = core"):
# core dir alternation = @@CORE_DIRS_ALT@@ (vd src|lib). Rỗng → skip (no core).
ALT='@@CORE_DIRS_ALT@@'
if [ -n "$ALT" ]; then
  P=(
    "(>>?|[0-9]+>)[[:space:]]*(\./)?($ALT)/"          # redirect vào core (kể cả 2> src/)
    "\bsed\b.*(-i|--in-place).*($ALT)/"               # sed inplace target core
    "\btee\b[[:space:]].*(\./)?($ALT)/"               # tee ghi file core
    "\bpatch\b.*($ALT)/"                              # patch chạm core
    "\bgit[[:space:]]+apply\b.*($ALT)/"               # git apply patch core
    "\bdd\b.*of=[\"']?(\./)?($ALT)/"                  # dd of= core
    "\b(perl|ruby)\b.*-i.*($ALT)/"                    # perl/ruby inplace core
    "\bpython[0-9.]*\b.*-c\b.*($ALT)/"                # python -c ... core
    "\b(cp|mv|install|rsync)\b.*[[:space:]](\./)?($ALT)/[^[:space:]]*[[:space:]]*$"  # dest = core (arg cuối)
  )
  for pat in "${P[@]}"; do
    if echo "$cmd" | grep -Eq "$pat"; then
      echo "$(ts) BLOCK main-agent bash-write → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
      cat >&2 << EOF
🚦 orchestrator-gate: MAIN agent (orchestrator — mọi model) KHÔNG ghi vào source core qua Bash.
   Command: ${cmd:0:160}

   Rule: .claude/rules/orchestrator.md — Opus = pure orchestrator. Edit core
   (@@CORE_DIRS_HUMAN@@) PHẢI route qua delegate subagent (Task tool):
     • L/XL algo / refactor / fix sau chẩn đoán → delegate-sonnet (fb: delegate-codex)
     • M mechanical / batch edit / boilerplate   → delegate-deepseek

   Nếu ĐÚNG size-S (1-line + 0 read context), chạy lại với:
     ORCHESTRATOR_GATE_BYPASS=1
EOF
      exit 2
    fi
  done
fi

exit 0
