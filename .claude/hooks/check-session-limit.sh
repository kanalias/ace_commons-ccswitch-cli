#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook — check context-window size BEFORE action.
# Enforces the project's context-window budget rule (ai-memory-rules/rules/token-budget.md
# or your own rule doc, if named differently). Session%/Weekly% dropped — not measurable
# from hook stdin; transcript-file byte size is used as a rough token-count proxy instead.
# Output: advisory guidance on stderr when context is large. Exit 0 always (advisory).

set -u

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)

# Thiếu jq → fail-open (không chặn mù, nhất quán với pre-edit-orchestrator-gate.sh).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Payload không phải JSON hợp lệ → fail-open.
if ! printf '%s' "$payload" | jq empty >/dev/null 2>&1; then
  exit 0
fi

transcript_path=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
[ -z "$transcript_path" ] && exit 0
[ -f "$transcript_path" ] || exit 0

bytes=$(wc -c < "$transcript_path" 2>/dev/null | tr -d ' ')
[[ "$bytes" =~ ^[0-9]+$ ]] || exit 0

# ponytail: ~4 chars/token là ước lượng thô, không có API đếm token chính xác
# qua hook stdin — chấp nhận được vì hook này advisory, không phải budgeting chính xác.
# ~100K tokens ≈ 400_000 bytes · ~200K tokens ≈ 800_000 bytes
TIER_100K=400000
TIER_200K=800000

if (( bytes < TIER_100K )); then
  exit 0
fi

if (( bytes < TIER_200K )); then
  cat >&2 << 'EOF'
📊 Context ≥ ~100K tokens (ước lượng qua transcript size): hạn chế re-read source;
   ưu tiên memory/reference; phần việc lớn còn lại → delegate hoặc new session.
EOF
  exit 0
fi

cat >&2 << 'EOF'
📊 Context ~200K tokens (ước lượng qua transcript size): auto-compact tự chạy — không cần làm gì.
EOF
exit 0
