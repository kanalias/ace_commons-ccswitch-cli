#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit|NotebookEdit).
# Orchestrator gate: chặn MAIN agent (orchestrator — mọi model) tự Edit/Write file source core.
# Ép execution route qua delegate subagent (per .claude/rules/common/orchestrator.md).
#
# Ranh giới (path-coarse, không đoán size — nghi ngờ → chặn):
#   - Chặn khi: caller = MAIN agent  VÀ  file_path thuộc core source dirs (src/)
#   - Cho phép: mọi tool call từ SUBAGENT (delegate-sonnet/deepseek/... edit thẳng OK)
#   - Cho phép: main agent sửa .claude/, docs/, tests/, config root (size-S exception)
#   - Chặn LUÔN (kể cả từ subagent): risk-path denylist bên dưới.
#
# Discriminator main vs subagent: dùng agent_id — field này CHỈ có ở subagent
# call. Không dùng agent_type để phân biệt main/subagent (field đó cũng xuất
# hiện khi MAIN session chạy kèm flag `--agent`, false-negative gate) — nhưng
# agent_type VẪN dùng được để biết ĐÚNG persona nào (giá trị = frontmatter
# `name` của subagent, vd "delegate-gemini") cho risk-path denylist dưới đây.
#
# Escape hatch cho size-S 1-line fix thật sự trong core dirs:
#   ORCHESTRATOR_GATE_BYPASS=1  → allow + ghi audit log.
#   (KHÔNG áp dụng cho risk-path denylist — đó là security boundary, không phải tiện lợi.)
#
# Output: exit 0 = allow · exit 2 = block (stderr shown to model).
# Fail-open: thiếu jq → allow (không chặn mù).
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

# Risk-tagged dirs (auth/payment/wallet/...) — đọc RUNTIME từ env.HARNESS_RISK_DIRS
# trong .claude/settings.json (giống hệt HARNESS_DELEGATE ở trên), KHÔNG bake
# lúc install. Sửa domain nhạy cảm = sửa 1 dòng JSON, có hiệu lực ngay, không
# cần re-run installer. Rỗng/unset (mặc định) → is_risk_path() luôn false, nhánh
# risk-path bên dưới tự no-op.
project_dir="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

# Canonicalize file_path trước khi match risk-dir — chặn evasion qua "..",
# symlink (vd "src/../auth/x.ts" hoặc symlink trỏ vào risk dir). Portable
# macOS+Linux: file tồn tại → realpath (fallback `cd + pwd -P` nếu thiếu
# realpath — một số bash cũ trên macOS không có). File CHƯA tồn tại (Write
# tạo mới) → canonicalize ancestor dir gần nhất tồn tại, ghép lại basename.
# Không canonicalize được → return 1 (caller fail-CLOSED, coi như risk-path).
canonicalize_path() {
  local input="$1" pd="$2" abs cur suffix resolved
  [ -z "$input" ] && return 1
  case "$input" in
    /*) abs="$input" ;;
    *) abs="$pd/$input" ;;
  esac

  cur="$abs"
  suffix=""
  while [ ! -e "$cur" ]; do
    if [ "$cur" = "/" ] || [ "$cur" = "." ]; then
      return 1
    fi
    suffix="$(basename "$cur")${suffix:+/$suffix}"
    cur="$(dirname "$cur")"
  done

  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "$cur" 2>/dev/null)" || return 1
  else
    resolved="$(cd "$cur" 2>/dev/null && pwd -P)" || return 1
  fi
  [ -z "$resolved" ] && return 1

  if [ -n "$suffix" ]; then
    printf '%s/%s\n' "$resolved" "$suffix"
  else
    printf '%s\n' "$resolved"
  fi
}

is_risk_path() {
  local fp="$1" csv="${HARNESS_RISK_DIRS:-}" d trimmed canon rel
  [ -z "$csv" ] && return 1
  [ -z "$fp" ] && return 1

  # Canonicalize thất bại → fail-CLOSED (security boundary, khác fail-open jq
  # ở trên) — coi file_path là risk, buộc route lại đúng persona.
  canon="$(canonicalize_path "$fp" "$project_dir")" || return 0
  case "$canon" in
    "$project_dir"/*) rel="${canon#"$project_dir"/}" ;;
    *) rel="$canon" ;;
  esac

  local IFS=','
  local raw
  read -ra raw <<< "$csv"
  for d in "${raw[@]}"; do
    trimmed="$(printf '%s' "$d" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#/+$##')"
    [ -z "$trimmed" ] && continue
    # Match cả canonical absolute lẫn path tương-đối-so-với-project-dir.
    case "$canon" in
      */"$trimmed"/*|"$trimmed"/*) return 0 ;;
    esac
    case "$rel" in
      */"$trimmed"/*|"$trimmed"/*) return 0 ;;
    esac
  done
  return 1
}

LOG="${HOME}/.cache/claude-code-ccswitch-cli-claude/orchestrator-gate.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

payload=$(cat)

# Thiếu jq → fail-open (nhất quán với pre-edit-secret-scan.sh).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Payload không phải JSON hợp lệ → fail-open (không chặn mù, không error mã lạ).
if ! printf '%s' "$payload" | jq empty >/dev/null 2>&1; then
  exit 0
fi

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
# Subagent call mang agent_id. Main agent thì rỗng (kể cả main chạy --agent).
agent_id=$(echo "$payload"   | jq -r '.agent_id // empty')
# Tên persona thật (frontmatter `name`, vd "delegate-gemini") khi call từ subagent.
agent_type=$(echo "$payload" | jq -r '.agent_type // empty')

ts() { date '+%Y-%m-%dT%H:%M:%S'; }

# 0) Risk-path denylist — chặn dù đang chạy trong subagent (persona không đủ
#    reasoning cho domain nhạy cảm vẫn bị chặn, kể cả có agent_id hợp lệ).
case "$agent_type" in
  delegate-gemini|delegate-deepseek)
    if is_risk_path "$file_path"; then
      echo "$(ts) BLOCK risk-path edit by $agent_type → $file_path" >> "$LOG" 2>/dev/null || true
      cat >&2 << EOF
🚦 orchestrator-gate: persona "$agent_type" KHÔNG được sửa risk-tagged path.
   File: $file_path

   Domain nhạy cảm (${HARNESS_RISK_DIRS:-}) chỉ cho phép:
     • delegate-codex   (hard-reasoning-code — ưu tiên cho security-sensitive edit)
     • delegate-sonnet  (L/XL fallback)

   Gemini (read-only by design) và DeepSeek (mechanical/bulk only) không đủ
   reasoning cho domain này — gọi lại đúng persona. Không có bypass cho nhánh
   này (security boundary, không phải size-S convenience).
EOF
      exit 2
    fi
    ;;
esac

# 1) Tool call từ subagent → luôn allow (delegate được phép edit).
if [ -n "$agent_id" ]; then
  exit 0
fi

# 2) Escape hatch: size-S 1-line fix thật sự.
if [ "${ORCHESTRATOR_GATE_BYPASS:-}" = "1" ]; then
  echo "$(ts) BYPASS main-agent edit → $file_path" >> "$LOG" 2>/dev/null || true
  exit 0
fi

# 3) Allow-list trước — harness surface (.claude/), test/, harness/ luôn cho
#    main agent sửa trực tiếp (không phải "source core" cần delegate).
case "$file_path" in
  */.claude/*|.claude/*|*/test/*|test/*|*/harness/*|harness/*)
    exit 0
    ;;
esac

# 4) Chỉ gate file source core (src/). Path khác (docs/, config)
#    → allow (rơi qua case dưới, fall-through exit 0 cuối file).
#    Match cả absolute path lẫn repo-relative.
case "$file_path" in
  */src/*|src/*)
    echo "$(ts) BLOCK main-agent edit → $file_path" >> "$LOG" 2>/dev/null || true
    cat >&2 << EOF
🚦 orchestrator-gate: MAIN agent (orchestrator — mọi model) KHÔNG tự Edit/Write vào source core.
   File: $file_path

   Rule: .claude/rules/common/orchestrator.md — Opus = pure orchestrator.
   Execution (edit src/) PHẢI route qua delegate subagent:
     • L/XL algo / refactor / fix sau chẩn đoán → delegate-sonnet (fb: delegate-codex)
     • M mechanical / batch edit / boilerplate   → delegate-deepseek
     • read-only audit / cross-file / grep rộng  → delegate-gemini

   Nếu ĐÚNG là size-S (1-line + 0 read context), chạy lại với:
     ORCHESTRATOR_GATE_BYPASS=1
EOF
    exit 2
    ;;
esac

exit 0
