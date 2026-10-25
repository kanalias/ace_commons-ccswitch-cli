#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Merge of pre-bash-orchestrator-gate.sh +
# pre-bash-git-push-gate.sh + pre-bash-merge-verdict-gate.sh.
#
# Order matters:
#   1) git-push gate    — runs for EVERYONE (main + subagent), no agent_id check.
#   1.5) serial-test gate — EVERYONE. bats ≥2 file without -j → block (test-parallel.md).
#   2) merge-verdict gate — runs for EVERYONE (main + subagent), no agent_id check.
#   2.5) integration-verify gate — main-agent only. Blocks `git commit` while
#      .claude/state/task-graph/<slug>.md (slug từ cwd, xem graph_slug() dưới)
#      says status: integrating and integration-status != pass
#      (orchestrator.md: Integration verify).
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

# Slug từ session cwd — mỗi worktree 1 state file riêng (FORMAT v1.3, xem
# orchestrator.md "Task-graph artifact"), không còn race read-modify-write
# giữa 2 session cùng repo. cwd rỗng/không khớp worktree → "main".
graph_slug() {
  local c="$1" rest s
  case "$c" in
    */.claude/worktrees/*) rest="${c#*/.claude/worktrees/}"; s="${rest%%/*}" ;;
    *) s="" ;;
  esac
  s="$(printf '%s' "$s" | tr -cd 'A-Za-z0-9._-')"
  printf '%s' "${s:-main}"
}

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
# Không exit ngay: protected-path guard (0.5) là data-safety boundary, chạy cả khi off.
harness_off=0
[ "${HARNESS_DELEGATE:-1}" = "0" ] && harness_off=1

LOG="${HOME}/.cache/claude-code-@@PROJECT_SLUG@@/orchestrator-gate.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
ts() { date '+%Y-%m-%dT%H:%M:%S'; }

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0

cmd=$(echo "$payload"      | jq -r '.tool_input.command // empty')
agent_id=$(echo "$payload" | jq -r '.agent_id // empty')

[ -z "$cmd" ] && exit 0

# ── 0.5) protected-path delete guard (everyone, KHÔNG bypass) ───────────────
# Chặn lệnh XOÁ (rm/rmdir/shred/truncate, find -delete|-exec rm, git clean,
# rsync --delete*) chạm chuỗi con path trong <project>/.claude/protected-paths.txt.
# Chạy cho mọi agent, không bị ORCHESTRATOR_GATE_BYPASS / HARNESS_DELEGATE=0 tắt
# (đặt TRƯỚC off-switch vì lý do đó). File vắng/không đọc được/không entry → no-op.
# Heuristic, không phải sandbox. Lỗ đã biết: path động ($(…), $VAR, glob build lúc
# chạy), script con (`bash x.sh`), `cd dir && rm *` (path tương đối không chứa entry),
# alias/function; `xargs rm` chỉ xét theo cả lệnh.
find_protected_list() {
  local d="$1" parent
  case "$d" in */.claude/worktrees/*) d="${d%%/.claude/worktrees/*}" ;; esac
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/.claude/protected-paths.txt" ]; then printf '%s' "$d/.claude/protected-paths.txt"; return 0; fi
    [ -e "$d/.git" ] && return 1
    parent="${d%/*}"; [ "$parent" = "$d" ] && return 1; d="$parent"
  done
  return 1
}
protected_guard() {
  local cwd_pg list norm seg entry hit=""
  cwd_pg=$(printf '%s' "$payload" | jq -r '.cwd // empty')
  list=""
  if [ -n "$cwd_pg" ]; then list=$(find_protected_list "$cwd_pg") || list=""; fi
  if [ -z "$list" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/protected-paths.txt" ]; then
    list="$CLAUDE_PROJECT_DIR/.claude/protected-paths.txt"
  fi
  { [ -n "$list" ] && [ -r "$list" ]; } || return 0
  local entries=()
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry%$'\r'}"
    entry="${entry#"${entry%%[![:space:]]*}"}"; entry="${entry%"${entry##*[![:space:]]}"}"
    case "$entry" in ""|\#*) continue ;; esac
    entries+=("$entry")
  done < "$list"
  [ "${#entries[@]}" -gt 0 ] || return 0
  # bỏ quote/backslash (path trong "…"); `\;` của find -exec không tách segment
  norm=$(printf '%s\n' "$cmd" | sed -e 's/\\;/ /g' -e "s/[\"'\\\\]//g" | tr ';|&()`' '\n\n\n\n\n\n')
  local V='(^|[[:space:]/{])(rm|rmdir|shred|truncate)([[:space:]]|$)'
  V="$V|(^|[[:space:]/])find[[:space:]].*(-delete|-exec[[:space:]]+(/[^[:space:]]*/)?rm([[:space:]]|\$))"
  V="$V|(^|[[:space:]/])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+clean([[:space:]]|\$)"
  V="$V|(^|[[:space:]/])rsync[[:space:]].*--(delete|remove-source-files)"
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    printf '%s' "$seg" | grep -Eq "$V" || continue
    for entry in "${entries[@]}"; do
      case "$seg" in *"$entry"*) hit="$entry"; break 2 ;; esac
    done
  done <<< "$norm"
  # `… | xargs rm`: verb và path nằm 2 segment khác nhau → xét cả lệnh
  if [ -z "$hit" ] && printf '%s' "$cmd" | grep -Eq 'xargs[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(rm|rmdir|shred|truncate)([[:space:]]|$)'; then
    for entry in "${entries[@]}"; do
      case "$cmd" in *"$entry"*) hit="$entry"; break ;; esac
    done
  fi
  [ -n "$hit" ] || return 0
  echo "$(ts) BLOCK protected-path delete (${hit}) agent=${agent_id:-main} → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
  cat >&2 << EOF
🛑 protected-path-guard: lệnh xoá chạm path được bảo vệ "${hit}" (khai báo trong .claude/protected-paths.txt).
   Command: ${cmd:0:160}

   DỪNG và hỏi user — không tự xoá, không lách bằng cách đổi lệnh. Áp cho mọi agent,
   không có bypass (ORCHESTRATOR_GATE_BYPASS / HARNESS_DELEGATE=0 đều không tắt được).
   User thật sự muốn xoá → tự chạy lệnh ngoài Claude Code.
EOF
  exit 2
}
protected_guard
[ "$harness_off" = 1 ] && exit 0

# ── 1) git-push gate (everyone) ─────────────────────────────────────────────
if ! echo "$cmd" | grep -Eq 'GIT_PUSH_GATE_OK=1'; then
  if echo "$cmd" | grep -Eq '(^|[;&|]|[[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-]+)?)*[[:space:]]+push([[:space:]]|$)'; then
    echo "🚨 pre-bash-git-push-gate: raw 'git push' bị chặn." >&2
    echo "Chạy /git-push-safety (test + gitleaks + /check-hardcode + hỏi confirm) thay vì push thẳng." >&2
    echo "Nếu đã qua gate và user đã confirm, push với prefix: GIT_PUSH_GATE_OK=1 git push ..." >&2
    exit 2
  fi
fi

# ── 1.1) private-branch gate (everyone, KHÔNG bypass) ───────────────────────
# Nhánh trong <project>/.claude/private-branches.txt (`<branch> <remote> <url-substr>`)
# chỉ được push tới đúng <remote>. Chặn sớm `git push <remote-khác> …<branch>…` và
# `git push <remote-khác> --all|--mirror|--tags` (kéo theo nhánh riêng). Lớp cuối là
# .git/hooks/pre-push + ruleset GitHub — gate này chỉ để báo sớm, rõ ràng.
pb_list="${CLAUDE_PROJECT_DIR:-}/.claude/private-branches.txt"
if [ -r "$pb_list" ] && printf '%s\n' "$cmd" | grep -Eq '(^|[;&|]|[[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-]+)?)*[[:space:]]+push([[:space:]]|$)'; then
  while IFS=' ' read -r pb_br pb_remote pb_url || [ -n "$pb_br" ]; do
    case "$pb_br" in ""|\#*) continue ;; esac
    while IFS= read -r seg; do
      printf '%s' "$seg" | grep -Eq '(^|[[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-]+)?)*[[:space:]]+push([[:space:]]|$)' || continue
      # remote = từ đầu tiên không bắt đầu bằng '-' sau "push"
      pb_target=$(printf '%s' "$seg" | sed -E 's/.*[[:space:]]push[[:space:]]+//' | tr ' ' '\n' | grep -v '^-' | head -1)
      [ -n "$pb_target" ] || continue
      [ "$pb_target" = "$pb_remote" ] && continue
      case "$pb_target" in *"$pb_url"*) continue ;; esac
      if printf '%s' "$seg" | grep -Eq "(^|[[:space:]:])$pb_br([[:space:]:]|$)|[[:space:]](--all|--mirror|--tags)([[:space:]]|$)"; then
        echo "$(ts) BLOCK private-branch push ($pb_br → $pb_target) agent=${agent_id:-main} → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
        cat >&2 <<EOF
🛑 private-branch-gate: nhánh riêng tư "$pb_br" CHỈ push lên remote "$pb_remote" ($pb_url). Lệnh đang push tới "$pb_target".
   Command: ${cmd:0:160}
   Không có bypass. Đúng: GIT_PUSH_GATE_OK=1 git push $pb_remote $pb_br
   Rule: .claude/rules/project/private-branch-kane.md
EOF
        exit 2
      fi
    done < <(printf '%s\n' "$cmd" | tr ';|&' '\n\n\n')
  done < "$pb_list"
fi

# ── 1.5) serial-test gate (everyone) ────────────────────────────────────────
# bats ≥2 file / glob mà không -j = tuần tự, phí core (rules/project/test-parallel.md).
# Chỉ xét ĐOẠN lệnh bats thật (command-word `bats` tới ;/&/|) — không đếm chuỗi
# ".bats" trong heredoc/grep pattern, không nhận -j của lệnh khác (make -j4 && bats).
# Thiếu GNU parallel hoặc false-positive (text lệnh chứa "&& bats x.bats" trong
# heredoc) → prefix BATS_SERIAL_OK=1 (có chủ đích, log audit).
if ! echo "$cmd" | grep -Eq 'BATS_SERIAL_OK=1'; then
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    echo "$seg" | grep -Eq '(^|[[:space:]])(-j|--jobs)([[:space:]]|=|[0-9]|$)' && continue
    if echo "$seg" | grep -q '\*\.bats' || [ "$(echo "$seg" | grep -oE '[^[:space:]]+\.bats([[:space:]]|$)' | wc -l | tr -d ' ')" -ge 2 ]; then
      echo "$(ts) BLOCK serial-bats → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
      cat >&2 << 'EOF'
🚦 serial-test-gate: bats nhiều file KHÔNG có -j = tuần tự, phí core.
   Chạy: bats -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" test/*.bats
   Thiếu GNU parallel (brew install parallel) hoặc false-positive → BATS_SERIAL_OK=1 <lệnh>
EOF
      exit 2
    fi
  done < <(echo "$cmd" | grep -oE '(^|[;&|(])[[:space:]]*((env|time|nice|nohup)[[:space:]]+)?([A-Z_][A-Z_0-9]*=[^[:space:]]*[[:space:]]+)*bats[[:space:]][^;&|]*')
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
  cwd_in=$(echo "$payload" | jq -r '.cwd // empty')
  slug=$(graph_slug "$cwd_in")
  graph_file="$project_dir/.claude/state/task-graph/$slug.md"
  if [ -f "$graph_file" ]; then
    graph_status=$(grep '^status:' "$graph_file" 2>/dev/null | head -1 | awk -F: '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    integ_status=$(grep '^integration-status:' "$graph_file" 2>/dev/null | head -1 | awk -F: '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    if [ "$graph_status" = "integrating" ] && [ "$integ_status" != "pass" ]; then
      echo "$(ts) BLOCK main-agent git-commit-during-integrating (integration-status=${integ_status:-<empty>}) → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
      cat >&2 << EOF
🚦 integration-verify-gate: task-graph đang integrating nhưng integration-status=${integ_status:-<empty>} — chạy integration verify (test suite/build) trên branch đã ghép, set integration-status: pass trong $graph_file rồi mới commit tổng (orchestrator.md: Integration verify)
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
if echo "$cmd" | grep -Eq '(^|[;&|(]|&&|\|\||[[:space:]](env|sudo|time|xargs|nice|nohup)[[:space:]])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(aider|gemini|codex)([[:space:]]|$)'; then
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

# Tách heredoc: thân heredoc của cat/tee = DATA (bỏ, tránh match oan nội dung);
# của bash/sh/zsh = shell (gộp vào shell part); của python/node/ruby/perl = code.
# $1 = shell|code. awk POSIX (BSD awk macOS OK), không dùng \x27 trong regex.
split_heredoc() {
  printf '%s\n' "$cmd" | awk -v mode="$1" -v q="'" '
    BEGIN { re = "(^|[^<])<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*[\"" q "]?" }
    inhd {
      t = $0; if (strip) sub(/^\t+/, "", t)
      if (t == tag) { inhd = 0; next }
      if ((mode == "code" && kind == "code") || (mode == "shell" && kind == "sh")) print
      next
    }
    {
      if (mode == "shell") print
      if (match($0, re)) {
        h = substr($0, RSTART, RLENGTH); sub(/^[^<]/, "", h)
        strip = (h ~ /^<<-/); gsub(/^<<-?[ \t]*/, "", h); gsub(/["\047]/, "", h)
        tag = h; inhd = 1; kind = "data"
        if ($0 ~ /(^|[^A-Za-z0-9_.\/-])(python[0-9.]*|node|ruby|perl|deno|bun)([ \t]|$)/) kind = "code"
        else if ($0 !~ /ssh[ \t]/ && $0 ~ /(^|[^A-Za-z0-9_.\/-])(bash|sh|zsh)([ \t]|$)/) kind = "sh"
      }
    }'
}

shell_part=$(split_heredoc shell)
code_part=$(split_heredoc code)

# Escape hatch cho Bash-write core (size-S 1-line thật sự). Nhận CẢ prefix trong
# chính lệnh (`ORCHESTRATOR_GATE_BYPASS=1 sed ...`, `export ...=1; ...`) — env của
# process hook KHÔNG nhận assignment trong lệnh, trước đây bypass vô hiệu.
if [ "${ORCHESTRATOR_GATE_BYPASS:-}" = "1" ] || \
   printf '%s\n' "$shell_part" | grep -Eq '(^|[;&|(]|[[:space:]])(export[[:space:]]+)?ORCHESTRATOR_GATE_BYPASS=1([[:space:];&|]|$)'; then
  echo "$(ts) BYPASS main-agent bash-write → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
  exit 0
fi

block_core_write() {
  echo "$(ts) BLOCK main-agent bash-write ($1) → ${cmd:0:120}" >> "$LOG" 2>/dev/null || true
  cat >&2 << EOF
🚦 orchestrator-gate: MAIN agent (orchestrator — mọi model) KHÔNG ghi vào source core qua Bash ($1).
   Command: ${cmd:0:160}

   Rule: .claude/rules/common/orchestrator.md — main = pure orchestrator. Sửa core
   (@@CORE_DIRS_HUMAN@@) PHẢI giao delegate subagent (Agent tool), prompt self-contained
   (repo path + file paths + spec + verify + không commit):
     • L/XL algo / refactor / fix sau chẩn đoán → delegate-sonnet (fb: delegate-codex)
     • M mechanical / batch edit / boilerplate   → delegate-deepseek

   Chỉ khi ĐÚNG size-S (1 dòng, đã biết chính xác chỗ sửa): đặt prefix ngay trong lệnh
     ORCHESTRATOR_GATE_BYPASS=1 <lệnh>      (ghi audit log)
EOF
  exit 2
}

# Bash-write vào core source. core dir alternation = @@CORE_DIRS_ALT@@ (vd src|lib).
# Rỗng → skip (no core).
ALT='@@CORE_DIRS_ALT@@'
if [ -n "$ALT" ]; then
  # Bỏ chuỗi quote dạng pattern/text (chứa space, \, |, ;, newline) — vd grep 'sed -i\|src/',
  # commit message nhiều dòng — không phải thao tác ghi. Giữ quote dạng path ("src/x.ts").
  # State machine qua CẢ lệnh (quote nhiều dòng, quote lồng '…"…'), rồi chẻ theo ; | & newline.
  segs=$(printf '%s\n' "$shell_part" | awk '
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
      sq = sprintf("%c", 39); dq = "\""; out = ""; q = ""; tok = ""; n = length(buf)
      for (i = 1; i <= n; i++) {
        ch = substr(buf, i, 1)
        if (q == "") {
          if (ch == "\\") { out = out ch substr(buf, i + 1, 1); i++; continue }
          if (ch == sq || ch == dq) { q = ch; tok = ch; continue }
          out = out ch; continue
        }
        if (q == dq && ch == "\\") { tok = tok ch substr(buf, i + 1, 1); i++; continue }
        tok = tok ch
        if (ch == q) { out = out (tok ~ /[ \t\n\\|;&]/ ? "Q" : tok); q = "" }
      }
      printf "%s\n", out (q == "" ? "" : tok)
    }' | tr ';|&' '\n\n\n')

  # Vị trí command word: đầu segment, sau "(" / do / then / else / sudo / env.
  CMDPOS='^[[:space:]]*(\([[:space:]]*)?((do|then|else|sudo|env|command|time|git)[[:space:]]+)*'

  # (a) ghi trực tiếp vào path core. Dest dạng host:/path (rsync/scp remote) KHÔNG
  #     phải core local → loại token chứa ':'.
  P=(
    "(>>?|[0-9]+>)[[:space:]]*[\"']?(\./)?($ALT)/"                   # redirect vào core (kể cả 2> src/)
    "(>>?|[0-9]+>)[[:space:]]*[\"']?/[^[:space:]]*/($ALT)/"          # redirect abs path vào core
    "${CMDPOS}sed[[:space:]]+(.*[[:space:]])?(-[A-Za-z]*i|--in-place).*($ALT)/"    # sed inplace target core
    "${CMDPOS}(perl|ruby)[[:space:]]+(.*[[:space:]])?-[A-Za-z0-9]*i.*($ALT)/"      # perl/ruby inplace (-i, -pi, -0pi)
    "(^|[[:space:]])tee[[:space:]]+([^[:space:]]+[[:space:]]+)*[\"']?[^[:space:]:]*($ALT)/"  # tee ghi file core
    "${CMDPOS}patch[[:space:]].*($ALT)/"                             # patch chạm core
    "${CMDPOS}apply[[:space:]].*($ALT)/"                             # git apply patch core
    "${CMDPOS}dd[[:space:]].*of=[\"']?[^[:space:]]*($ALT)/"          # dd of= core
    "${CMDPOS}(cp|mv|install|rsync)[[:space:]].*[[:space:]][\"']?[^[:space:]:]*($ALT)/[^[:space:]:]*[[:space:]]*$"  # dest = core (arg cuối)
  )
  for pat in "${P[@]}"; do
    printf '%s\n' "$segs" | grep -Eq "$pat" && block_core_write "ghi path core"
  done

  # (b) đang đứng trong core (cwd của session — Bash giữ cwd giữa các lệnh) hoặc
  #     cd vào core trong lệnh này → ghi path tương đối = ghi core. Chỉ xét segment
  #     TỪ lệnh cd đó trở đi (redirect trước cd không tính).
  cwd_core=0
  cwd_in=$(echo "$payload" | jq -r '.cwd // empty')
  pd="${CLAUDE_PROJECT_DIR:-}"
  if [ -n "$cwd_in" ] && [ -n "$pd" ]; then
    case "$cwd_in" in
      "$pd"/*)
        rel="${cwd_in#"$pd"/}"
        case "$rel" in .claude/worktrees/*/*) rel="${rel#.claude/worktrees/}"; rel="${rel#*/}" ;; esac
        printf '%s' "$rel" | grep -Eq "^($ALT)(/|$)" && cwd_core=1 ;;
    esac
  fi
  if [ "$cwd_core" = 1 ]; then
    after_cd="$segs"
  else
    # cd vào core → bật; cd tuyệt đối ra ngoài core → tắt (cd tương đối giữ nguyên).
    after_cd=$(printf '%s\n' "$segs" | awk -v alt="$ALT" '
      match($0, /(^|[[:space:]])cd[[:space:]]+[^[:space:]]+/) {
        a = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*cd[[:space:]]+/, "", a); gsub(/["\047]/, "", a)
        if (a ~ ("(^|/)(" alt ")(/|$)")) on = 1
        else if (a ~ /^[\/~]/) on = 0
      }
      on')
  fi
  in_core=0; [ -n "$after_cd" ] && in_core=1
  if [ "$in_core" = 1 ]; then
    R=(
      "(>>?|[0-9]>)[[:space:]]*[^/&~\$[:space:]>]"                  # redirect tương đối (/tmp, /dev/null, >&2, $VAR OK)
      "${CMDPOS}sed[[:space:]]+(.*[[:space:]])?(-[A-Za-z]*i|--in-place)([[:space:]]|$)"
      "${CMDPOS}(perl|ruby)[[:space:]]+(.*[[:space:]])?-[A-Za-z0-9]*i([[:space:]]|$)"
      "(^|[[:space:]])tee[[:space:]]+(-a[[:space:]]+)?[^/[:space:]-]"
      "${CMDPOS}(cp|mv|install|patch)[[:space:]]"
      "${CMDPOS}rsync[[:space:]].*[[:space:]][^[:space:]:]+[[:space:]]*$"   # rsync dest local (không host:)
      "${CMDPOS}apply[[:space:]]"
    )
    for pat in "${R[@]}"; do
      printf '%s\n' "$after_cd" | grep -Eq "$pat" && block_core_write "cd vào core rồi ghi"
    done
  fi

  # (c) code interpreter (heredoc python/node… hoặc -c/-e inline) có thao tác ghi
  #     + chạm core: path core là string literal ('src/x', "/abs/src/x") hoặc đang
  #     đứng trong core. "src/" xuất hiện trong nội dung (yaml, markdown) không tính.
  code="$code_part"
  if printf '%s\n' "$shell_part" | grep -Eq "(^|[^A-Za-z0-9_./-])(python[0-9.]*|node|ruby|perl|deno|bun)[[:space:]]([^;|&]*[[:space:]])?-(c|e|p)([[:space:]]|$)"; then
    code="$code"$'\n'"$shell_part"
  fi
  if [ -n "$code" ] && printf '%s\n' "$code" | grep -Eq "open\([^)]*,[[:space:]]*(mode=)?[\"'][^\"']*[wax+]|\.write(_text|_bytes)?\(|writeFile(Sync)?\(|appendFile(Sync)?\(|createWriteStream|(os|fs|fsp)\.(replace|rename|renameSync)\(|shutil\.(copy|move)|File\.write"; then
    if [ "$in_core" = 1 ] || printf '%s\n' "$code" | grep -Eq "[\"'\`]([^\"'\`[:space:]]*/)?($ALT)/[^\"'\`[:space:]]*[\"'\`]"; then
      block_core_write "script ghi file core"
    fi
  fi
fi

exit 0
