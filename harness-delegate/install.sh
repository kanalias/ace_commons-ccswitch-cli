#!/usr/bin/env bash
# Interactive installer — copies the orchestrator/delegate "harness" mechanism
# (subagents + guard hooks + quality hooks + optional session-limit hook) into
# another project. Reads templates/*, substitutes @@TOKEN@@ placeholders with
# project-specific values, writes files + wires hooks into .claude/settings.json
# (idempotent jq merge — safe to re-run).
#
# NON-INTERACTIVE MODE (for scripts/tests): every prompt has a matching env var
# override — set it and the prompt is skipped. Any prompt left unset falls back
# to `read -r` (which, fed from /dev/null or a closed pipe, returns empty →
# the documented default is used, so `install.sh </dev/null` is a safe all-defaults
# dry run).
#
#   HARNESS_INSTALL_METHOD       1|2 — 1=enter path, 2=cwd          (default: 1; ignored if HARNESS_ROUTE_DIR set)
#   HARNESS_ROUTE_DIR            project directory                  (default: .; set = skip method menu)
#   HARNESS_CONFIRM_PATH         y/n — confirm resolved path        (default: Y)
#   HARNESS_INSTALL_ALL          y/n — install everything + overwrite all existing files (default: Y); "n" aborts the install
#   HARNESS_CORE_DIRS            CSV of core source dirs, read directly (no prompt) (default: src)
#   HARNESS_PROJECT_SLUG         project slug, read directly (no prompt) (default: basename of route dir)
#   HARNESS_BRANCH               working branch name, read directly (no prompt) (default: dev)
#   HARNESS_TEST_CMD             test command, or "none", read directly (no prompt) (default: none)
#   HARNESS_GROUP_SUBAGENTS      y/n — delegate subagents+wrappers, no prompt (default: Y)
#   HARNESS_GROUP_GUARD          y/n — guard hooks, no prompt        (default: Y)
#   HARNESS_GROUP_QUALITY        y/n — quality hooks, no prompt      (default: Y)
#   HARNESS_GROUP_SESSIONLIMIT   y/n — session-limit hook, no prompt (default: Y)
#   HARNESS_GROUP_COMMANDS       y/n — push-to-git + conventional-commit + branch-cleanup + pr-describe + dep-audit + loop-feature + lazy-load-audit + audit-memory-harness + commit + force-snapshot slash-commands, no prompt (default: Y)
#   HARNESS_GROUP_SKILLS         y/n — lazy-load-health + dep-ladder-check + auto-commit + check-hardcode + audit-git-leak skills, no prompt (default: Y)
#   HARNESS_GROUP_RULES          y/n — git-workflow + skill-superpowers project rules, no prompt (default: Y)
#   HARNESS_OVERWRITE            forced to "all" once HARNESS_INSTALL_ALL confirms (per-file overwrite prompt removed)
set -euo pipefail

TEMPLATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"

command -v jq >/dev/null 2>&1 || { echo "❌ 'jq' required. Install: brew install jq (mac) / apt install jq (linux)"; exit 1; }
command -v git >/dev/null 2>&1 || echo "⚠️ 'git' not found — recommended (delegate wrappers need worktrees to run, though installer itself will still work)."

# ── prompt helpers ──────────────────────────────────────────────────────
prompt_val() { # prompt_val <ENV_VAR_NAME> <prompt-text> <default> → echoes value
  local envname="$1" msg="$2" default="$3" val="${!1:-}"
  if [ -n "$val" ]; then printf '%s\n' "$val"; return; fi
  printf '%s [%s]: ' "$msg" "$default" >&2
  local ans; read -r ans || ans=""
  printf '%s\n' "${ans:-$default}"
}

prompt_yn() { # prompt_yn <ENV_VAR_NAME> <prompt-text> <Y|N default> → 0=yes 1=no
  local envname="$1" msg="$2" defaultyn="$3" val="${!1:-}"
  if [ -n "$val" ]; then
    case "$val" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
  fi
  local hint="[Y/n]"; [ "$defaultyn" = "N" ] && hint="[y/N]"
  printf '%s %s: ' "$msg" "$hint" >&2
  local ans; read -r ans || ans=""
  ans="${ans:-$defaultyn}"
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ── 1. route dir ────────────────────────────────────────────────────────
# Two install methods: 1) type a project root path, 2) use the current dir.
# HARNESS_ROUTE_DIR (if set) overrides both and skips the method menu.
if [ -n "${HARNESS_ROUTE_DIR:-}" ]; then
  ROUTE_RAW="$HARNESS_ROUTE_DIR"
else
  METHOD="$(prompt_val HARNESS_INSTALL_METHOD 'Cài harness vào project nào — 1) nhập đường dẫn project (ROOT folder)  2) cài vào project đang mở ở terminal này (ROOT folder)' '1')"
  case "$METHOD" in
    2) ROUTE_RAW="$PWD" ;;
    *) ROUTE_RAW="$(prompt_val __HARNESS_ROUTE_INPUT 'Đường dẫn project root' '.')" ;;
  esac
fi
case "$ROUTE_RAW" in
  "~") ROUTE_RAW="$HOME" ;;
  "~/"*) ROUTE_RAW="$HOME/${ROUTE_RAW#\~/}" ;;
esac
# resolve to absolute for display WITHOUT creating anything (so a typo'd path
# that the user rejects leaves no stray dir behind)
if [ -d "$ROUTE_RAW" ]; then
  ROUTE_DIR="$(cd "$ROUTE_RAW" && pwd)"
else
  case "$ROUTE_RAW" in /*) ROUTE_DIR="$ROUTE_RAW" ;; *) ROUTE_DIR="$PWD/$ROUTE_RAW" ;; esac
fi

# ── verify resolved path before writing anything ─────────────────────────
echo "📁 Install target: $ROUTE_DIR" >&2
if ! prompt_yn HARNESS_CONFIRM_PATH "Cài harness vào đúng đường dẫn này" "Y"; then
  echo "❌ Hủy cài đặt."
  exit 1
fi
mkdir -p "$ROUTE_DIR"
ROUTE_DIR="$(cd "$ROUTE_DIR" && pwd)"   # normalize (collapse .. and symlinks) post-create

if git -C "$ROUTE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1
else
  IS_GIT=0
  echo "⚠️  $ROUTE_DIR không phải git repo — delegate wrapper cần git worktree để hoạt động." >&2
fi

# ── gate: install everything + overwrite all, or abort ──────────────────
if ! prompt_yn HARNESS_INSTALL_ALL "Cài toàn bộ harness và override mọi file đã tồn tại" "Y"; then
  echo "❌ Hủy cài đặt."
  exit 1
fi
export HARNESS_OVERWRITE=all

# ── 2. substitution values (no prompt — env override or default) ────────
CORE_DIRS_CSV="${HARNESS_CORE_DIRS:-src}"
PROJECT_SLUG_RAW="${HARNESS_PROJECT_SLUG:-$(basename "$ROUTE_DIR")}"
BRANCH="${HARNESS_BRANCH:-dev}"
TEST_CMD_RAW="${HARNESS_TEST_CMD:-none}"

join_by() { local d="$1"; shift; local IFS="$d"; printf '%s' "$*"; }

build_core_dirs() {
  local csv="$1" d trimmed
  local -a case_parts=() human_parts=()
  local IFS=','
  local -a raw=($csv)
  CORE_DIRS_YAML=""
  for d in "${raw[@]}"; do
    trimmed="$(printf '%s' "$d" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#/+$##')"
    [ -z "$trimmed" ] && continue
    case_parts+=("*/$trimmed/*" "$trimmed/*")
    human_parts+=("$trimmed/")
    CORE_DIRS_YAML="${CORE_DIRS_YAML}  - \"$trimmed/**\""$'\n'
  done
  CORE_DIRS_CASE="$(join_by '|' "${case_parts[@]}")"
  CORE_DIRS_HUMAN="$(join_by ' · ' "${human_parts[@]}")"
  CORE_DIRS_YAML="${CORE_DIRS_YAML%$'\n'}"
}
build_core_dirs "$CORE_DIRS_CSV"

PROJECT_SLUG="$(printf '%s' "$PROJECT_SLUG_RAW" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[ -z "$PROJECT_SLUG" ] && PROJECT_SLUG="project"

TEST_CMD_LOWER="$(printf '%s' "$TEST_CMD_RAW" | tr '[:upper:]' '[:lower:]')"
if [ "$TEST_CMD_LOWER" = "none" ] || [ -z "$TEST_CMD_RAW" ]; then
  TEST_CMD_PHRASE="the project's test command (none configured — infer from README/CI, or ask before assuming)"
else
  TEST_CMD_PHRASE="the project's test command: \`$TEST_CMD_RAW\`"
fi

# ── 3. component menu ───────────────────────────────────────────────────
# group_on <ENV_VAR_NAME> → 0=install (default when unset/empty), 1=skip on a no-ish value
group_on() {
  case "${!1:-y}" in n|N|no|NO|No|nO) return 1 ;; *) return 0 ;; esac
}

SEL_SUBAGENTS=0; SEL_GUARD=0; SEL_QUALITY=0; SEL_SESSIONLIMIT=0; SEL_COMMANDS=0; SEL_SKILLS=0; SEL_RULES=0
group_on HARNESS_GROUP_SUBAGENTS    && SEL_SUBAGENTS=1
group_on HARNESS_GROUP_GUARD        && SEL_GUARD=1
group_on HARNESS_GROUP_QUALITY      && SEL_QUALITY=1
group_on HARNESS_GROUP_SESSIONLIMIT && SEL_SESSIONLIMIT=1
group_on HARNESS_GROUP_COMMANDS     && SEL_COMMANDS=1
group_on HARNESS_GROUP_SKILLS       && SEL_SKILLS=1
group_on HARNESS_GROUP_RULES        && SEL_RULES=1

# ── 4. copy + substitute ────────────────────────────────────────────────
should_overwrite() {
  local rel="$1"
  case "${HARNESS_OVERWRITE:-}" in
    all|overwrite) return 0 ;;
    none|keep) return 1 ;;
  esac
  if [ ! -t 0 ]; then return 1; fi
  printf '  %s đã tồn tại — overwrite? [y/N]: ' "$rel" >&2
  local ans; read -r ans || ans=""
  case "$ans" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

substitute_file() {
  local src="$1" dest="$2" tmp line
  tmp="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//@@CORE_DIRS_CASE@@/$CORE_DIRS_CASE}"
    line="${line//@@CORE_DIRS_HUMAN@@/$CORE_DIRS_HUMAN}"
    line="${line//@@CORE_DIRS_YAML@@/$CORE_DIRS_YAML}"
    line="${line//@@PROJECT_SLUG@@/$PROJECT_SLUG}"
    line="${line//@@BRANCH@@/$BRANCH}"
    line="${line//@@TEST_CMD@@/$TEST_CMD_PHRASE}"
    printf '%s\n' "$line" >> "$tmp"
  done < "$src"
  mv "$tmp" "$dest"
}

WRITTEN=()
install_file() { # install_file <src-rel-under-templates/> <dest-rel-under-route/>
  local src_rel="$1" dest_rel="$2"
  local src="$TEMPLATES_DIR/$src_rel" dest="$ROUTE_DIR/$dest_rel"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && ! should_overwrite "$dest_rel"; then
    echo "  • $dest_rel (kept existing)"
    return 0
  fi
  substitute_file "$src" "$dest"
  case "$dest" in *.sh) chmod +x "$dest" ;; esac
  WRITTEN+=("$dest_rel")
  echo "  ✓ $dest_rel"
}

echo "▶ Cài harness vào $ROUTE_DIR"

if [ "$SEL_SUBAGENTS" -eq 1 ]; then
  echo "── delegate subagents + wrappers ──"
  for a in deepseek gemini codex sonnet; do
    install_file "agents/delegate-$a.md" ".claude/agents/delegate-$a.md"
  done
  for s in _common run-aider-deepseek run-codex run-gemini probe-gemini-highest gemini-account doctor; do
    install_file "scripts/delegate/$s.sh" "scripts/delegate/$s.sh"
  done
fi

if [ "$SEL_GUARD" -eq 1 ]; then
  echo "── guard hooks ──"
  install_file "hooks/pre-edit-orchestrator-gate.sh" ".claude/hooks/pre-edit-orchestrator-gate.sh"
  install_file "hooks/pre-edit-secret-scan.sh"        ".claude/hooks/pre-edit-secret-scan.sh"
fi

if [ "$SEL_QUALITY" -eq 1 ]; then
  echo "── quality hooks ──"
  install_file "hooks/post-edit-syntax-check.sh" ".claude/hooks/post-edit-syntax-check.sh"
  install_file "hooks/session-start-banner.sh"   ".claude/hooks/session-start-banner.sh"
fi

if [ "$SEL_SESSIONLIMIT" -eq 1 ]; then
  echo "── session-limit hook ──"
  install_file "hooks/check-session-limit.sh" ".claude/hooks/check-session-limit.sh"
fi

if [ "$SEL_COMMANDS" -eq 1 ]; then
  echo "── commands ──"
  install_file "commands/push-to-git.md"     ".claude/commands/push-to-git.md"
  install_file "commands/conventional-commit.md" ".claude/commands/conventional-commit.md"
  install_file "commands/branch-cleanup.md"      ".claude/commands/branch-cleanup.md"
  install_file "commands/pr-describe.md"          ".claude/commands/pr-describe.md"
  install_file "commands/dep-audit.md"            ".claude/commands/dep-audit.md"
  install_file "commands/loop-feature.md"         ".claude/commands/loop-feature.md"
  install_file "commands/lazy-load-audit.md"      ".claude/commands/lazy-load-audit.md"
  install_file "commands/audit-memory-harness.md" ".claude/commands/audit-memory-harness.md"
  install_file "commands/commit.md"               ".claude/commands/commit.md"
  install_file "commands/force-snapshot.md"       ".claude/commands/force-snapshot.md"
fi

if [ "$SEL_SKILLS" -eq 1 ]; then
  echo "── skills ──"
  install_file "skills/lazy-load-health/SKILL.md" ".claude/skills/lazy-load-health/SKILL.md"
  install_file "skills/dep-ladder-check/SKILL.md" ".claude/skills/dep-ladder-check/SKILL.md"
  install_file "skills/auto-commit/SKILL.md"      ".claude/skills/auto-commit/SKILL.md"
  install_file "skills/check-hardcode/SKILL.md"   ".claude/skills/check-hardcode/SKILL.md"
  install_file "skills/audit-git-leak/SKILL.md"   ".claude/skills/audit-git-leak/SKILL.md"
fi

if [ "$SEL_RULES" -eq 1 ]; then
  echo "── rules ──"
  install_file "rules/git-workflow.md"      ".claude/rules/git-workflow.md"
  install_file "rules/skill-superpowers.md" ".claude/rules/skill-superpowers.md"
fi

# ── 5. wire settings.json (idempotent) ──────────────────────────────────
HOOKS_WIRED=()
if [ "$SEL_GUARD" -eq 1 ] || [ "$SEL_QUALITY" -eq 1 ] || [ "$SEL_SESSIONLIMIT" -eq 1 ]; then
  mkdir -p "$ROUTE_DIR/.claude"
  SETTINGS="$ROUTE_DIR/.claude/settings.json"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

  wire_hook() { # wire_hook <event> <matcher-or-empty> <command>
    local event="$1" matcher="$2" cmd="$3" tmp
    tmp="$(mktemp)"
    jq --arg ev "$event" --arg matcher "$matcher" --arg cmd "$cmd" '
      .hooks //= {}
      | .hooks[$ev] //= []
      | ( [ .hooks[$ev][] | select((.matcher // "") == $matcher) ] | length ) as $matchCount
      | if $matchCount > 0 then
          .hooks[$ev] |= map(
            if (.matcher // "") == $matcher then
              if ([.hooks[]?.command] | index($cmd)) then .
              else .hooks += [{type:"command", command:$cmd}]
              end
            else .
            end
          )
        else
          .hooks[$ev] += [ (if $matcher == "" then {hooks:[{type:"command",command:$cmd}]} else {matcher:$matcher, hooks:[{type:"command",command:$cmd}]} end) ]
        end
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    HOOKS_WIRED+=("$event${matcher:+ ($matcher)}: $cmd")
  }

  echo "── wiring .claude/settings.json ──"
  if [ "$SEL_GUARD" -eq 1 ]; then
    wire_hook PreToolUse 'Edit|Write' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-edit-orchestrator-gate.sh'
    wire_hook PreToolUse 'Edit|Write' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-edit-secret-scan.sh'
  fi
  if [ "$SEL_QUALITY" -eq 1 ]; then
    wire_hook PostToolUse 'Edit|Write' '$CLAUDE_PROJECT_DIR/.claude/hooks/post-edit-syntax-check.sh'
    wire_hook SessionStart '' '$CLAUDE_PROJECT_DIR/.claude/hooks/session-start-banner.sh'
  fi
  if [ "$SEL_SESSIONLIMIT" -eq 1 ]; then
    wire_hook UserPromptSubmit '*' '$CLAUDE_PROJECT_DIR/.claude/hooks/check-session-limit.sh'
  fi
  # discoverable off-switch — set once if absent, never clobber a user's existing "0"
  tmp="$(mktemp)"
  jq '.env //= {} | if (.env.HARNESS_DELEGATE == null) then .env.HARNESS_DELEGATE = "1" else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  jq empty "$SETTINGS" || { echo "❌ settings.json bị hỏng sau merge — kiểm tra lại"; exit 1; }
  echo "  ✓ .claude/settings.json"
fi

# ── 6. report ────────────────────────────────────────────────────────────
echo
echo "✅ Xong. ${#WRITTEN[@]} file ghi vào $ROUTE_DIR."
if [ "${#HOOKS_WIRED[@]}" -gt 0 ]; then
  echo "Hooks wired:"
  for h in "${HOOKS_WIRED[@]}"; do echo "  • $h"; done
  echo "ℹ️  Off-switch: set env.HARNESS_DELEGATE=0 in .claude/settings.json to disable the harness without uninstalling."
fi
if [ "$IS_GIT" -eq 0 ]; then
  echo "⚠️  $ROUTE_DIR không phải git repo — delegate wrapper (worktree) sẽ lỗi tới khi có git."
fi
echo "ℹ️  Delegate wrapper là bash-only — Windows cần WSL hoặc Git-Bash."
