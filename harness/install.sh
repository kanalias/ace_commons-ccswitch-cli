#!/usr/bin/env bash
# Interactive installer — copies the orchestrator/delegate "harness" mechanism
# (subagents + guard hooks + quality hooks) into
# another project. Reads templates/*, substitutes @@TOKEN@@ placeholders with
# project-specific values, writes files + wires hooks into .claude/settings.json
# (idempotent jq merge — safe to re-run).
#
# NON-INTERACTIVE MODE (for scripts/tests): every prompt has a matching env var
# override — set it and the prompt is skipped. Any prompt left unset falls back
# to `read -r` (which, fed from /dev/null or a closed pipe, returns empty →
# the documented default is used). Closed stdin still performs a real install;
# set HARNESS_DRY_RUN=1 for a zero-write preview.
#
#   HARNESS_DRY_RUN              1 — report target without writing anything
#   HARNESS_ASSUME_YES           1 — accept confirmation prompts
#   install.sh uninstall|--uninstall — remove only manifest-owned content
#
#   HARNESS_INSTALL_METHOD       1|2 — 1=enter path, 2=cwd          (default: 1; ignored if HARNESS_ROUTE_DIR set)
#   HARNESS_ROUTE_DIR            project directory                  (default: .; set = skip method menu)
#   HARNESS_CONFIRM_PATH         y/n — confirm resolved path        (default: Y)
#   HARNESS_INSTALL_ALL          y/n — install everything + overwrite all existing files (default: Y); "n" aborts the install
#   HARNESS_CORE_DIRS            CSV of core source dirs, read directly (no prompt) (default: src)
#   HARNESS_RISK_DIRS            CSV of risk-sensitive dirs (auth/payment/wallet/...), read directly (no prompt) (default: empty = risk-path denylist disabled)
#   HARNESS_PROJECT_SLUG         project slug, read directly (no prompt) (default: basename of route dir)
#   HARNESS_BRANCH               working branch override (default: target HEAD branch, or main)
#   HARNESS_TEST_CMD             test command, or "none", read directly (no prompt) (default: none)
#   HARNESS_GROUP_SUBAGENTS      y/n — delegate subagents+wrappers, no prompt (default: Y)
#   HARNESS_GROUP_GUARD          y/n — guard hooks, no prompt        (default: Y)
#   HARNESS_GROUP_QUALITY        y/n — quality hooks, no prompt      (default: Y)
#   HARNESS_GROUP_COMMANDS       y/n — push-to-git + conventional-commit + branch-cleanup + clean-up-project + pr-describe + dep-audit + loop-feature + lazy-load-audit + audit-memory-harness + commit + force-snapshot + update-claude slash-commands, no prompt (default: Y)
#   HARNESS_GROUP_SKILLS         y/n — lazy-load-health + dep-ladder-check + auto-commit + check-hardcode + audit-git-leak + orchestrate skills, no prompt (default: Y)
#   HARNESS_GROUP_RULES          y/n — rules: common/ (9 invariant guardrails, always overwrite) + project/ (git-workflow, skill-superpowers — kept if exist), no prompt (default: Y)
#   HARNESS_GROUP_GITHOOKS       y/n — git pre-push hook (gitleaks secret scan) into .git/hooks/, no prompt (default: Y; skipped if target not a git repo)
#   HARNESS_GROUP_DEPLOY         y/n — production-deploy/-cleanup/-reboot slash-commands, no prompt (default: N — opt-in, most repos don't deploy to a prod host)
#   HARNESS_DEPLOY_SSH_HOST      ssh alias of the prod host                (default: <deploy-ssh-host>)
#   HARNESS_DEPLOY_SERVICE       target container/compose service name    (default: <service-name>)
#   HARNESS_DEPLOY_PATH          repo path on the host                    (default: <remote-repo-path>)
#   HARNESS_DEPLOY_BRANCH        branch to deploy                         (default: same as HARNESS_BRANCH)
#   HARNESS_DEPLOY_REMOTE        git remote the host pulls from           (default: origin)
#   HARNESS_DEPLOY_HEALTHCHECK   healthcheck command/URL                  (default: <healthcheck-cmd>)
#   HARNESS_OVERWRITE            forced to "all" once HARNESS_INSTALL_ALL confirms (per-file overwrite prompt removed)
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEMPLATES_DIR="$HARNESS_DIR/templates"
ACTION="install"
case "${1:-}" in uninstall|--uninstall) ACTION="uninstall" ;; "") ;; *) echo "Usage: $0 [uninstall|--uninstall]" >&2; exit 2 ;; esac
MANIFEST_REL=".claude/harness-manifest.json"
HARNESS_VERSION="1"

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1
  fi
}

# Bake delegate model defaults from THIS repo's .env at install time — the
# target project won't have this .env, so templates can't read it at runtime.
# _common.sh:load_env_chain() only exports names matching ^[A-Za-z_][A-Za-z0-9_]*=,
# so read directly here instead of sourcing that parser.
read_dotenv_var() { # read_dotenv_var <VAR_NAME> <default>
  local name="$1" default="$2" f="$HARNESS_DIR/../.env" val
  [ -f "$f" ] || { printf '%s' "$default"; return; }
  val="$(grep -E "^${name}=" "$f" | tail -n1 | cut -d= -f2-)"
  printf '%s' "${val:-$default}"
}
GEMINI_MODEL_DEFAULT="${HARNESS_GEMINI_MODEL_DEFAULT:-$(read_dotenv_var GEMINI_MODEL gemini-3.5-flash)}"
CODEX_MODEL_DEFAULT="${HARNESS_CODEX_MODEL_DEFAULT:-$(read_dotenv_var CODEX_MODEL gpt-5.6-luna)}"
DEEPSEEK_MODEL_DEFAULT="${HARNESS_DEEPSEEK_MODEL_DEFAULT:-$(read_dotenv_var DEEPSEEK_MODEL openai/ds/deepseek-v4-pro)}"

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
  if [ "${HARNESS_ASSUME_YES:-0}" = "1" ]; then return 0; fi
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
if [ "${HARNESS_DRY_RUN:-0}" = "1" ]; then
  printf 'DRY RUN: %s target %s; no files will be written.\n' "$ACTION" "$ROUTE_DIR"
  exit 0
fi
mkdir -p "$ROUTE_DIR"
ROUTE_DIR="$(cd "$ROUTE_DIR" && pwd -P)"   # normalize (collapse .., resolve symlinks) post-create

# guard: never install into the harness source dir itself — that scatters .claude/,
# scripts/, CLAUDE.md as untracked leftovers on every dry-run/test. Route elsewhere.
if [ "$ROUTE_DIR" = "$HARNESS_DIR" ]; then
  echo "❌ ROUTE_DIR trùng harness source ($HARNESS_DIR). Không tự-cài vào source dir. Chọn project khác." >&2
  exit 1
fi

uninstall_harness() {
  local manifest="$ROUTE_DIR/$MANIFEST_REL" settings="$ROUTE_DIR/.claude/settings.json"
  local rel expected actual tmp
  if [ ! -f "$manifest" ]; then
    echo "❌ Không tìm thấy $MANIFEST_REL; từ chối đoán ownership." >&2
    return 1
  fi
  jq -e '.schemaVersion == 1' "$manifest" >/dev/null || { echo "❌ Manifest schema không hỗ trợ." >&2; return 1; }
  prompt_yn HARNESS_CONFIRM_UNINSTALL "Gỡ các file/settings do harness sở hữu" "N" || { echo "❌ Hủy gỡ cài đặt."; return 1; }

  # Remove only files whose current content still matches the installed hash.
  while IFS=$'\t' read -r rel expected; do
    [ -n "$rel" ] || continue
    case "/$rel/" in */../*|*//*) echo "⚠️  Bỏ qua manifest path không an toàn: $rel" >&2; continue ;; esac
    case "$rel" in /*) echo "⚠️  Bỏ qua manifest path không an toàn: $rel" >&2; continue ;; esac
    [ -f "$ROUTE_DIR/$rel" ] || continue
    actual="$(sha256_file "$ROUTE_DIR/$rel")"
    if [ "$actual" = "$expected" ]; then rm -f "$ROUTE_DIR/$rel"; else echo "  • $rel (kept modified)"; fi
  done < <(jq -r '.syncFiles[] | [.path,.sha256] | @tsv' "$manifest")

  # CLAUDE.md can predate installation. In that case preserve the user's file and
  # remove only our exactly delimited managed block.
  if jq -e '.preservePaths | index("CLAUDE.md")' "$manifest" >/dev/null && [ -f "$ROUTE_DIR/CLAUDE.md" ]; then
    tmp="$(mktemp)"
    awk '$0=="<!-- BEGIN HARNESS RULES (managed by install.sh — do not edit inside) -->" {skip=1; next} skip && $0=="<!-- END HARNESS RULES -->" {skip=0; next} !skip {print}' "$ROUTE_DIR/CLAUDE.md" > "$tmp"
    mv "$tmp" "$ROUTE_DIR/CLAUDE.md"
  fi

  if [ -f "$settings" ]; then
    tmp="$(mktemp)"
    jq --slurpfile own "$manifest" '
      $own[0].settings as $o
      | reduce $o.hooks[] as $h (.;
          if .hooks[$h.event] then
            .hooks[$h.event] |= (map(
              if ((.matcher // "") == $h.matcher) then .hooks |= map(select(.command != $h.command)) else . end
            ) | map(select((.hooks // []) | length > 0)))
          else . end)
      | if .hooks then .hooks |= with_entries(select(.value | length > 0)) else . end
      | if (.hooks == {}) then del(.hooks) else . end
      | reduce $o.deny[] as $d (.;
          if .permissions.deny then .permissions.deny |= map(select(. != $d)) else . end)
      | if .permissions.deny == [] then del(.permissions.deny) else . end
      | if .permissions == {} then del(.permissions) else . end
      | reduce ($o.env | to_entries[]) as $e (.;
          if .env[$e.key] == $e.value then del(.env[$e.key]) else . end)
      | if .env == {} then del(.env) else . end
      | if ($o.statusLineCommand != null and .statusLine.command == $o.statusLineCommand) then del(.statusLine) else . end
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
  fi
  rm -f "$manifest"
  echo "✅ Đã gỡ nội dung harness còn nguyên ownership; giữ lại file đã sửa và preserve paths."
}

if [ "$ACTION" = "uninstall" ]; then uninstall_harness; exit $?; fi

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
RISK_DIRS_CSV="${HARNESS_RISK_DIRS:-}"
PROJECT_SLUG_RAW="${HARNESS_PROJECT_SLUG:-$(basename "$ROUTE_DIR")}"
DETECTED_BRANCH="$(git -C "$ROUTE_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
BRANCH="${HARNESS_BRANCH:-${DETECTED_BRANCH:-main}}"
TEST_CMD_RAW="${HARNESS_TEST_CMD:-none}"
DEPLOY_SSH_HOST="${HARNESS_DEPLOY_SSH_HOST:-<deploy-ssh-host>}"
DEPLOY_SERVICE="${HARNESS_DEPLOY_SERVICE:-<service-name>}"
DEPLOY_PATH="${HARNESS_DEPLOY_PATH:-<remote-repo-path>}"
DEPLOY_BRANCH="${HARNESS_DEPLOY_BRANCH:-$BRANCH}"
DEPLOY_REMOTE="${HARNESS_DEPLOY_REMOTE:-origin}"
DEPLOY_HEALTHCHECK="${HARNESS_DEPLOY_HEALTHCHECK:-<healthcheck-cmd>}"

sanitize_remote_id() { # sanitize_remote_id <remote-url> → host/owner/repo lowercase, or placeholder
  local raw="$1" id host path
  case "$raw" in
    ssh://*|http://*|https://*) id="${raw#*://}"; id="${id##*@}"; host="${id%%/*}"; path="${id#*/}" ;;
    *@*:*) id="${raw#*@}"; host="${id%%:*}"; path="${id#*:}" ;;
    *) host=""; path="" ;;
  esac
  path="${path#/}"
  path="${path%.git}"
  if [ -n "$host" ] && [ -n "$path" ] && [ "$path" != "$host" ]; then
    printf '%s/%s' "$host" "$path" | tr '[:upper:]' '[:lower:]'
  else
    printf '<project-remote-id>'
  fi
}
PROJECT_REMOTE_ID="$(sanitize_remote_id "$(git -C "$ROUTE_DIR" config --get remote.origin.url 2>/dev/null || true)")"

join_by() { local d="$1"; shift; local IFS="$d"; printf '%s' "$*"; }

build_core_dirs() {
  local csv="$1" d trimmed
  local -a case_parts=() human_parts=() alt_parts=()
  local IFS=','
  local -a raw=($csv)
  CORE_DIRS_YAML=""
  for d in "${raw[@]}"; do
    trimmed="$(printf '%s' "$d" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#/+$##')"
    [ -z "$trimmed" ] && continue
    case_parts+=("*/$trimmed/*" "$trimmed/*")
    human_parts+=("$trimmed/")
    # ERE-escape dir name for CORE_DIRS_ALT (Bash-gate command regex). Dir names
    # are normally [a-z0-9._-] but escape ERE metachars to be safe.
    # BSD/macOS sed: '\]' inside a bracket expr does NOT escape ']' — the class
    # closes early and trailing '*+?' become bare repetition operators (RE error).
    # POSIX-safe: put ']' first in the class, use '#' delim so '/' needs no escape,
    # and escape backslash in a separate pass (can't live safely in the bracket).
    alt_parts+=("$(printf '%s' "$trimmed" | sed -E 's#\\#\\\\#g; s#[]./[(){}*+?^$|]#\\&#g')")
    CORE_DIRS_YAML="${CORE_DIRS_YAML}  - \"$trimmed/**\""$'\n'
  done
  CORE_DIRS_CASE="$(join_by '|' "${case_parts[@]}")"
  CORE_DIRS_HUMAN="$(join_by ' · ' "${human_parts[@]}")"
  CORE_DIRS_ALT="$(join_by '|' "${alt_parts[@]}")"
  CORE_DIRS_YAML="${CORE_DIRS_YAML%$'\n'}"
}
build_core_dirs "$CORE_DIRS_CSV"

# Risk-sensitive dirs (auth/payment/wallet/...) — NOT baked into the hook file.
# Written into .claude/settings.json's env.HARNESS_RISK_DIRS instead (same
# runtime-read mechanism as env.HARNESS_DELEGATE below) so a user can edit
# the denylist later with a 1-line JSON change, no reinstall needed. See
# is_risk_path() in hooks/pre-edit-orchestrator-gate.sh.

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

SEL_SUBAGENTS=0; SEL_GUARD=0; SEL_QUALITY=0; SEL_COMMANDS=0; SEL_SKILLS=0; SEL_RULES=0; SEL_GITHOOKS=0; SEL_DEPLOY=0
group_on HARNESS_GROUP_SUBAGENTS    && SEL_SUBAGENTS=1
group_on HARNESS_GROUP_GUARD        && SEL_GUARD=1
group_on HARNESS_GROUP_QUALITY      && SEL_QUALITY=1
group_on HARNESS_GROUP_COMMANDS     && SEL_COMMANDS=1
group_on HARNESS_GROUP_SKILLS       && SEL_SKILLS=1
group_on HARNESS_GROUP_RULES        && SEL_RULES=1
group_on HARNESS_GROUP_GITHOOKS     && SEL_GITHOOKS=1
prompt_yn HARNESS_GROUP_DEPLOY "Cài production-deploy/-cleanup/-reboot slash-commands (chỉ nếu repo này deploy lên 1 host multi-service)" "N" && SEL_DEPLOY=1

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
  tmp="$(mktemp)" || { echo "ERROR: mktemp failed" >&2; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//@@CORE_DIRS_CASE@@/$CORE_DIRS_CASE}"
    line="${line//@@CORE_DIRS_ALT@@/$CORE_DIRS_ALT}"
    line="${line//@@CORE_DIRS_HUMAN@@/$CORE_DIRS_HUMAN}"
    line="${line//@@CORE_DIRS_YAML@@/$CORE_DIRS_YAML}"
    line="${line//@@PROJECT_SLUG@@/$PROJECT_SLUG}"
    line="${line//@@PROJECT_REMOTE_ID@@/$PROJECT_REMOTE_ID}"
    line="${line//@@BRANCH@@/$BRANCH}"
    line="${line//@@TEST_CMD@@/$TEST_CMD_PHRASE}"
    line="${line//@@GEMINI_MODEL_DEFAULT@@/$GEMINI_MODEL_DEFAULT}"
    line="${line//@@CODEX_MODEL_DEFAULT@@/$CODEX_MODEL_DEFAULT}"
    line="${line//@@DEEPSEEK_MODEL_DEFAULT@@/$DEEPSEEK_MODEL_DEFAULT}"
    line="${line//@@DEPLOY_SSH_HOST@@/$DEPLOY_SSH_HOST}"
    line="${line//@@DEPLOY_SERVICE@@/$DEPLOY_SERVICE}"
    line="${line//@@DEPLOY_PATH@@/$DEPLOY_PATH}"
    line="${line//@@DEPLOY_BRANCH@@/$DEPLOY_BRANCH}"
    line="${line//@@DEPLOY_REMOTE@@/$DEPLOY_REMOTE}"
    line="${line//@@DEPLOY_HEALTHCHECK@@/$DEPLOY_HEALTHCHECK}"
    printf '%s\n' "$line" >> "$tmp"
  done < "$src"
  mv "$tmp" "$dest"
}

WRITTEN=()
SYNC_WRITTEN=()
PRESERVE_PATHS=()
install_file() { # install_file <src-rel-under-templates/> <dest-rel-under-route/> [mode]
  # mode (default ""): honor should_overwrite / HARNESS_OVERWRITE (legacy behavior for all callers)
  #   sync     → always overwrite (source-of-truth wins), ignores should_overwrite
  #   preserve → hard-keep: if dest exists, never overwrite (protects per-repo customization),
  #              independent of HARNESS_OVERWRITE=all
  local src_rel="$1" dest_rel="$2" mode="${3:-}"
  local src="$TEMPLATES_DIR/$src_rel" dest="$ROUTE_DIR/$dest_rel"
  mkdir -p "$(dirname "$dest")"
  if [ "$mode" = "preserve" ] && [ -e "$dest" ]; then
    PRESERVE_PATHS+=("$dest_rel")
    echo "  • $dest_rel (kept existing)"
    return 0
  fi
  if [ "$mode" != "sync" ] && [ -e "$dest" ] && ! should_overwrite "$dest_rel"; then
    PRESERVE_PATHS+=("$dest_rel")
    echo "  • $dest_rel (kept existing)"
    return 0
  fi
  substitute_file "$src" "$dest"
  case "$dest" in *.sh) chmod +x "$dest" ;; esac
  WRITTEN+=("$dest_rel")
  if [ "$mode" = "preserve" ]; then PRESERVE_PATHS+=("$dest_rel"); else SYNC_WRITTEN+=("$dest_rel"); fi
  echo "  ✓ $dest_rel"
}

echo "▶ Cài harness vào $ROUTE_DIR"

if [ "$SEL_SUBAGENTS" -eq 1 ]; then
  echo "── delegate subagents + wrappers ──"
  for a in deepseek gemini codex sonnet; do
    install_file "agents/delegate-$a.md" ".claude/agents/delegate-$a.md"
  done
  for s in _common run-aider-deepseek run-codex run-gemini doctor; do
    install_file "scripts/delegate/$s.sh" "scripts/delegate/$s.sh"
  done
  # IPv4-only DNS shim loaded via PYTHONPATH by run-aider-deepseek.sh (P0 perf).
  install_file "scripts/delegate/lib/sitecustomize.py" "scripts/delegate/lib/sitecustomize.py"
fi

if [ "$SEL_GUARD" -eq 1 ]; then
  echo "── guard hooks ──"
  install_file "hooks/pre-edit-orchestrator-gate.sh" ".claude/hooks/pre-edit-orchestrator-gate.sh"
  # merged: pre-bash-orchestrator-gate + pre-bash-git-push-gate + pre-bash-merge-verdict-gate
  install_file "hooks/pre-bash-gate.sh"               ".claude/hooks/pre-bash-gate.sh"
  # merged: pre-edit-secret-scan + pre-edit-host-scan
  install_file "hooks/pre-edit-content-scan.sh"       ".claude/hooks/pre-edit-content-scan.sh"
  # allowlist for content-scan hook — per-repo customizable → keep existing edits
  install_file "allowed-hosts.txt"                    ".claude/allowed-hosts.txt" preserve
  # orchestration gate — block under-specified Task dispatch
  install_file "hooks/pre-task-dispatch-gate.sh"      ".claude/hooks/pre-task-dispatch-gate.sh"
  # browser profile gate — force Cloak/Playwright qua profile prj_<xx>_sv_<yy>
  install_file "hooks/pre-browser-profile-gate.sh"    ".claude/hooks/pre-browser-profile-gate.sh"
fi

if [ "$SEL_QUALITY" -eq 1 ]; then
  echo "── quality hooks ──"
  # merged: post-edit-syntax-check + remind-lazy-load-health + post-write-memory-mirror
  install_file "hooks/post-edit-advisor.sh"       ".claude/hooks/post-edit-advisor.sh"
  # merged: session-start-banner + session-start-ledger
  install_file "hooks/session-start.sh"           ".claude/hooks/session-start.sh"
  # review/security subagents (independent second opinion — not delegate personas)
  install_file "agents/code-reviewer.md"  ".claude/agents/code-reviewer.md"
  install_file "agents/secret-scanner.md" ".claude/agents/secret-scanner.md"
  # orchestration recorders — stuck-command detection + merged subagent verdict/ledger
  install_file "hooks/post-bash-stuck-detector.sh" ".claude/hooks/post-bash-stuck-detector.sh"
  # merged: stop-verdict-record + subagent-stop-ledger
  install_file "hooks/subagent-stop-record.sh"    ".claude/hooks/subagent-stop-record.sh"
  install_file "commands/resume-orchestration.md" ".claude/commands/resume-orchestration.md"
  # statusline — shows task-graph progress, chains ~/.claude/statusline-context.sh if present
  install_file "statusline-orchestration.sh"      ".claude/statusline-orchestration.sh"
fi

if [ "$SEL_COMMANDS" -eq 1 ]; then
  echo "── commands ──"
  install_file "commands/git-push-safety.md"     ".claude/commands/git-push-safety.md"
  install_file "commands/git-commit.md"           ".claude/commands/git-commit.md"
  install_file "commands/git-commit-describe.md"  ".claude/commands/git-commit-describe.md"
  install_file "commands/git-cleanup-branch.md"   ".claude/commands/git-cleanup-branch.md"
  install_file "commands/git-force-snapshot.md"   ".claude/commands/git-force-snapshot.md"
  install_file "commands/clean-up-project.md"     ".claude/commands/clean-up-project.md"
  install_file "commands/doctor-memory.md"        ".claude/commands/doctor-memory.md"
  install_file "commands/audit-context-memory.md" ".claude/commands/audit-context-memory.md"
  install_file "commands/audit-dependency.md"     ".claude/commands/audit-dependency.md"
  install_file "commands/audit-vietnamese.md"     ".claude/commands/audit-vietnamese.md"
  install_file "commands/audit-claude-md.md"      ".claude/commands/audit-claude-md.md"
  install_file "commands/task-loop-feature.md"    ".claude/commands/task-loop-feature.md"
  install_file "commands/update-claude.md"        ".claude/commands/update-claude.md"
fi

if [ "$SEL_DEPLOY" -eq 1 ]; then
  echo "── production deploy commands ──"
  install_file "commands/production-deploy.md"  ".claude/commands/production-deploy.md"
  install_file "commands/production-cleanup.md" ".claude/commands/production-cleanup.md"
  install_file "commands/production-reboot.md"  ".claude/commands/production-reboot.md"
  deploy_config_incomplete=0
  for deploy_config_value in "$DEPLOY_SSH_HOST" "$DEPLOY_SERVICE" "$DEPLOY_PATH" "$DEPLOY_HEALTHCHECK"; do
    case "$deploy_config_value" in
      \<*\>) deploy_config_incomplete=1 ;;
    esac
  done
  if [ "$deploy_config_incomplete" -eq 1 ]; then
    echo "  ⚠ Deploy config chưa đầy đủ — /production-* sẽ tự STOP (project guard). Set HARNESS_DEPLOY_SSH_HOST/HARNESS_DEPLOY_SERVICE/HARNESS_DEPLOY_PATH/HARNESS_DEPLOY_HEALTHCHECK rồi chạy lại để kích hoạt."
  fi
fi

if [ "$SEL_SKILLS" -eq 1 ]; then
  echo "── skills ──"
  while IFS= read -r skill_file; do
    skill_rel="${skill_file#$TEMPLATES_DIR/}"
    install_file "$skill_rel" ".claude/$skill_rel"
  done < <(find "$TEMPLATES_DIR/skills" -type f | sort)
fi

if [ "$SEL_RULES" -eq 1 ]; then
  echo "── rules ──"
  # common/ = invariant guardrails, source-of-truth = templates → always overwrite (sync)
  for f in "$TEMPLATES_DIR"/rules/common/*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    install_file "rules/common/$b" ".claude/rules/common/$b" sync
  done
  # project/ = per-repo customizable → keep existing (don't clobber local edits)
  for f in "$TEMPLATES_DIR"/rules/project/*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    [ "$b" = "sync-template.md" ] && continue # source-repository maintenance only
    install_file "rules/project/$b" ".claude/rules/project/$b" preserve
  done
fi

if [ "$SEL_GITHOOKS" -eq 1 ]; then
  echo "── git hooks ──"
  if [ "$IS_GIT" -eq 1 ]; then
    # git-native pre-push (gitleaks secret scan) — guards every `git push`, even outside Claude.
    # source-of-truth = template → sync overwrite. install_file only chmod +x on *.sh, so do it here.
    install_file "git-hooks/pre-push" ".git/hooks/pre-push" sync
    chmod +x "$ROUTE_DIR/.git/hooks/pre-push"
  else
    echo "  • skip pre-push ($ROUTE_DIR không phải git repo)"
  fi
fi

# ── 4b. CLAUDE.md navigation for natively discovered rules. Managed block: created
#        if missing, appended once if absent, replaced in place on re-sync. ──
ensure_claude_md() {
  local cmd="$ROUTE_DIR/CLAUDE.md"
  local existed=0
  [ -e "$cmd" ] && existed=1
  local begin="<!-- BEGIN HARNESS RULES (managed by install.sh — do not edit inside) -->"
  local end="<!-- END HARNESS RULES -->"
  local block tmp
  block="$begin
## Quick links — rules QUAN TRỌNG

- ⭐⭐⭐ [.claude/rules/common/vault-no-mcp.md](.claude/rules/common/vault-no-mcp.md) — **P0**: Vault CRUD KHÔNG qua MCP, Notion API direct
- ⭐⭐⭐ [.claude/rules/common/token-budget.md](.claude/rules/common/token-budget.md) — **P0**: context-window budget
- [.claude/rules/project/git-workflow.md](.claude/rules/project/git-workflow.md) — branching, working branch rule, protected-branch deploy confirm, worktree, cleanup
- [.claude/rules/common/feature-redflags.md](.claude/rules/common/feature-redflags.md) — safe minimal changes + RED FLAGS cognitive wedge
- Thêm/sửa rule → đọc [.claude/rules/common/rule-loading-policy.md](.claude/rules/common/rule-loading-policy.md) trước (rule mới mặc định LAZY \`paths:\`)
- Ghi memory type project → mirror vào [.claude/memory/](.claude/memory/) theo [.claude/rules/common/memory-mirror.md](.claude/rules/common/memory-mirror.md)
- ⭐⭐⭐ **Harness Architecture (P0)** — xem section dưới

## ⭐⭐⭐ Harness Architecture (P0 — đọc kỹ)

Project follows **Anthropic Claude Code \"Harness Engineer\"** pattern. Mọi feature mới
BẮT BUỘC route qua 1 trong **5 surfaces** dưới đây. KHÔNG add ad-hoc scripts ngoài surface.

| Surface | Path | Khi nào dùng |
|---|---|---|
| **Slash command** | \`.claude/commands/<name>.md\` (vd \`/deploy\`, \`/test\`) | Workflow lặp lại user gõ \`/<name>\` |
| **Hook** | \`.claude/hooks/<name>.sh\` + wire \`.claude/settings.json\` (vd \`protect-backup.sh\`, \`session-start.sh\`) | Auto-action khi event (Pre/Post/SessionStart/Stop/SubagentStop) |
| **Subagent** | \`.claude/agents/<name>.md\` (vd \`smoke-tester\`) | Persona isolated context |
| **MCP server** | \`mcp-servers/<name>/\` + \`.mcp.json\` ở root project | External tool / structured I/O |
| **Permission deny** | \`.claude/settings.json\` \`permissions.deny\` | Hard guardrail (push prod, rm backup, edit \`secrets/\`, edit \`.env\`) |

**Quy trình thêm feature:**

1. **Identify surface** từ bảng. Không match → STOP, hỏi user.
2. **Implement** theo pattern surface đó.
3. **Wire** (hook → \`.claude/settings.json\`).
4. **Document** trong commit message rõ surface nào đã thêm.

**Hook exit code policy:**

- \`exit 0\` — advisory (log/inject context)
- \`exit 2\` — **BLOCK** (abort tool, AI buộc phải sửa) — surface stderr
- khác — error

**Skip mechanism (user-only):** prompt chứa \`SKIP_HOOKS\` / \`BYPASS_<HOOK>\` / \"ignore <hook> safety\" → hook exit 0 + log audit.

**Native rules loading.** Claude Code tự động khám phá Markdown trong \`.claude/rules/\`: rule không có \`paths:\` được nạp luôn; rule có \`paths:\` chỉ nạp khi đọc file khớp glob. Rules cung cấp instructions, không phải executable hooks hay permission enforcement. Feature logic → 5 surfaces ở trên; governance → rules.

**Harness rules (bundled, self-contained).** Mọi session PHẢI đọc + tuân thủ trước khi action:
- [.claude/rules/common/](.claude/rules/common/) — invariant guardrails (secret, vault, budget, orchestrator, delegate, git, red-flags, rule-loading, memory-mirror). Managed by harness install.sh: **overwrite** khi re-sync — KHÔNG sửa trực tiếp trong project (sửa upstream ở harness repo).
- [.claude/rules/project/](.claude/rules/project/) — rule riêng repo, LAZY trừ khi vượt gate P0-mọi-turn; install.sh **giữ nguyên** khi re-sync.
$end"

  if [ ! -e "$cmd" ]; then
    printf '# Project Guidelines\n\n%s\n' "$block" > "$cmd"
    echo "  ✓ CLAUDE.md (created)"
    WRITTEN+=("CLAUDE.md")
    SYNC_WRITTEN+=("CLAUDE.md")
    return 0
  fi
  if grep -qF "$begin" "$cmd"; then
    # replace existing managed block in place (awk: skip old block, splice new)
    # $block is multi-line → pass via ENVIRON, not -v (awk -v chokes on literal
    # newline in the value: "awk: newline in string").
    tmp="$(mktemp)"
    REPL="$block" awk -v b="$begin" -v e="$end" '
      $0==b {print ENVIRON["REPL"]; skip=1; next}
      skip && $0==e {skip=0; next}
      !skip {print}
    ' "$cmd" > "$tmp" && mv "$tmp" "$cmd"
    echo "  ✓ CLAUDE.md (block re-synced)"
  else
    printf '\n%s\n' "$block" >> "$cmd"
    echo "  ✓ CLAUDE.md (block appended)"
  fi
  WRITTEN+=("CLAUDE.md")
  if [ "$existed" -eq 1 ]; then PRESERVE_PATHS+=("CLAUDE.md"); else SYNC_WRITTEN+=("CLAUDE.md"); fi
}
ensure_claude_md

# ── 5. wire settings.json (idempotent) ──────────────────────────────────
HOOKS_WIRED=()
OWNED_HOOKS=()
OWNED_DENY=()
OWNED_ENV_KEYS=()
OWNED_STATUSLINE=""
PREVIOUS_MANIFEST="$ROUTE_DIR/$MANIFEST_REL"
if [ -f "$PREVIOUS_MANIFEST" ] && jq -e '.schemaVersion == 1' "$PREVIOUS_MANIFEST" >/dev/null 2>&1; then
  while IFS=$'\t' read -r event matcher command; do OWNED_HOOKS+=("$event" "$matcher" "$command"); done < <(jq -r '.settings.hooks[]? | [.event,.matcher,.command] | @tsv' "$PREVIOUS_MANIFEST")
  while IFS= read -r deny; do OWNED_DENY+=("$deny"); done < <(jq -r '.settings.deny[]?' "$PREVIOUS_MANIFEST")
  while IFS= read -r key; do OWNED_ENV_KEYS+=("$key"); done < <(jq -r '.settings.env | keys[]?' "$PREVIOUS_MANIFEST")
  OWNED_STATUSLINE="$(jq -r '.settings.statusLineCommand // empty' "$PREVIOUS_MANIFEST")"
fi

array_contains() { local needle="$1" item; shift; for item in "$@"; do [ "$item" = "$needle" ] && return 0; done; return 1; }

if [ "$SEL_GUARD" -eq 1 ] || [ "$SEL_QUALITY" -eq 1 ]; then
  mkdir -p "$ROUTE_DIR/.claude"
  SETTINGS="$ROUTE_DIR/.claude/settings.json"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

  wire_hook() { # wire_hook <event> <matcher-or-empty> <command> [legacy-matchers-space-separated]
    local event="$1" matcher="$2" cmd="$3" legacy="${4:-}" tmp
    local existed
    existed="$(jq --arg ev "$event" --arg matcher "$matcher" --arg cmd "$cmd" '[.hooks[$ev][]? | select((.matcher // "") == $matcher) | .hooks[]? | select(.command == $cmd)] | length' "$SETTINGS")"
    tmp="$(mktemp)"
    jq --arg ev "$event" --arg matcher "$matcher" --arg cmd "$cmd" --arg legacy "$legacy" '
      ($legacy | split(" ") | map(select(length > 0))) as $legacyList
      | .hooks //= {}
      | .hooks[$ev] //= []
      # self-heal: drop this command from any legacy matcher block (leave
      # unrelated commands under that block untouched), then drop the block
      # entirely if it ends up empty.
      | .hooks[$ev] |= (
          map(
            (.matcher // "") as $m
            | if ($legacyList | index($m)) != null then
                .hooks |= map(select(.command != $cmd))
              else .
              end
          )
          | map(select((.hooks // []) | length > 0))
        )
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
    if [ "$existed" -eq 0 ] || { [ -f "$PREVIOUS_MANIFEST" ] && jq -e --arg e "$event" --arg m "$matcher" --arg c "$cmd" '.settings.hooks[]? | select(.event==$e and .matcher==$m and .command==$c)' "$PREVIOUS_MANIFEST" >/dev/null; }; then
      OWNED_HOOKS+=("$event" "$matcher" "$cmd")
    fi
    HOOKS_WIRED+=("$event${matcher:+ ($matcher)}: $cmd")
  }

  # ── migration cleanup: remove hooks merged away in the 16→8 consolidation ──
  # (a) delete old hook files from the target if still present
  OLD_HOOKS=(
    pre-bash-orchestrator-gate.sh pre-bash-git-push-gate.sh pre-bash-merge-verdict-gate.sh
    pre-edit-secret-scan.sh pre-edit-host-scan.sh
    post-edit-syntax-check.sh remind-lazy-load-health.sh post-write-memory-mirror.sh
    post-task-trace.sh
    stop-verdict-record.sh subagent-stop-ledger.sh
    session-start-banner.sh session-start-ledger.sh
  )
  for oh in "${OLD_HOOKS[@]}"; do
    of="$ROUTE_DIR/.claude/hooks/$oh"
    [ -e "$of" ] && { rm -f "$of"; echo "  🗑  .claude/hooks/$oh (removed — merged in consolidation)"; }
  done
  # (b) unwire from settings.json — same self-heal pattern as wire_hook()'s
  # legacy-matcher cleanup: drop any hooks entry whose .command ends in one of
  # the old basenames (any event, any matcher block), then drop empty blocks.
  tmp="$(mktemp)"
  jq --argjson old "$(printf '%s\n' "${OLD_HOOKS[@]}" | jq -R . | jq -s .)" '
    .hooks //= {}
    | .hooks |= with_entries(
        .value |= (
          map(.hooks |= map(select(([.command // ""] | any(. as $c | $old | any(. as $b | $c | endswith($b))) ) | not)))
          | map(select((.hooks // []) | length > 0))
        )
      )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  echo "── wiring .claude/settings.json ──"
  if [ "$SEL_GUARD" -eq 1 ]; then
    wire_hook PreToolUse 'Edit|Write|MultiEdit|NotebookEdit' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-edit-orchestrator-gate.sh' 'Edit|Write'
    wire_hook PreToolUse 'Bash' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-bash-gate.sh'
    wire_hook PreToolUse 'Edit|Write|MultiEdit|NotebookEdit' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-edit-content-scan.sh' 'Edit|Write'
    # orchestration gate — under-specified dispatch
    wire_hook PreToolUse 'Task' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-task-dispatch-gate.sh'
    # browser profile gate — MCP browser tools + Bash launch
    wire_hook PreToolUse 'mcp__(pw_|cloak|playwright|browser).*' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-browser-profile-gate.sh'
    wire_hook PreToolUse 'Bash' '$CLAUDE_PROJECT_DIR/.claude/hooks/pre-browser-profile-gate.sh'
  fi
  if [ "$SEL_QUALITY" -eq 1 ]; then
    wire_hook PostToolUse 'Edit|Write|MultiEdit' '$CLAUDE_PROJECT_DIR/.claude/hooks/post-edit-advisor.sh' 'Edit|Write Write'
    wire_hook SessionStart '' '$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh'
    # orchestration recorders — stuck-command detection + merged subagent verdict/ledger
    wire_hook PostToolUse 'Bash' '$CLAUDE_PROJECT_DIR/.claude/hooks/post-bash-stuck-detector.sh'
    wire_hook SubagentStop '' '$CLAUDE_PROJECT_DIR/.claude/hooks/subagent-stop-record.sh'
  fi
  # discoverable off-switch — set once if absent, never clobber a user's existing "0"
  delegate_missing="$(jq 'if .env.HARNESS_DELEGATE == null then 1 else 0 end' "$SETTINGS")"
  tmp="$(mktemp)"
  jq '.env //= {} | if (.env.HARNESS_DELEGATE == null) then .env.HARNESS_DELEGATE = "1" else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  if [ "$delegate_missing" -eq 1 ] || { [ "${#OWNED_ENV_KEYS[@]}" -gt 0 ] && array_contains HARNESS_DELEGATE "${OWNED_ENV_KEYS[@]}"; }; then OWNED_ENV_KEYS+=(HARNESS_DELEGATE); fi

  # risk-path denylist CSV — same runtime pattern as HARNESS_DELEGATE above,
  # set once if absent so re-running the installer never clobbers a user's
  # later manual edit to this field.
  risk_missing="$(jq 'if .env.HARNESS_RISK_DIRS == null then 1 else 0 end' "$SETTINGS")"
  tmp="$(mktemp)"
  jq --arg risk "$RISK_DIRS_CSV" '.env //= {} | if (.env.HARNESS_RISK_DIRS == null) then .env.HARNESS_RISK_DIRS = $risk else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  if [ "$risk_missing" -eq 1 ] || { [ "${#OWNED_ENV_KEYS[@]}" -gt 0 ] && array_contains HARNESS_RISK_DIRS "${OWNED_ENV_KEYS[@]}"; }; then OWNED_ENV_KEYS+=(HARNESS_RISK_DIRS); fi

  # Conservative project-local protection; record only entries first added by us.
  DENY_ENTRIES=(
    'Read(./.env)' 'Read(./.env.*)' 'Read(./secrets/**)' 'Read(./**/*.pem)'
    'Edit(./.env)' 'Edit(./.env.*)' 'Edit(./secrets/**)' 'Edit(./**/*.pem)'
    'Write(./.env)' 'Write(./.env.*)' 'Write(./secrets/**)' 'Write(./**/*.pem)'
    'Bash(rm -rf .git:*)' 'Bash(git push --force:*)' 'Bash(git push -f:*)'
  )
  for deny in "${DENY_ENTRIES[@]}"; do
    deny_existed="$(jq --arg d "$deny" '[.permissions.deny[]? | select(. == $d)] | length' "$SETTINGS")"
    tmp="$(mktemp)"
    jq --arg d "$deny" '.permissions //= {} | .permissions.deny //= [] | if (.permissions.deny | index($d)) then . else .permissions.deny += [$d] end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    if [ "$deny_existed" -eq 0 ] || { [ "${#OWNED_DENY[@]}" -gt 0 ] && array_contains "$deny" "${OWNED_DENY[@]}"; }; then OWNED_DENY+=("$deny"); fi
  done

  # statusline — set once if absent, never clobber a user's own statusLine override
  if [ "$SEL_QUALITY" -eq 1 ]; then
    status_before="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
    tmp="$(mktemp)"
    jq 'if (.statusLine == null) then .statusLine = {type: "command", command: "bash $CLAUDE_PROJECT_DIR/.claude/statusline-orchestration.sh"} else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    if [ -z "$status_before" ] || [ "$OWNED_STATUSLINE" = "$status_before" ]; then OWNED_STATUSLINE='bash $CLAUDE_PROJECT_DIR/.claude/statusline-orchestration.sh'; fi
  fi

  jq empty "$SETTINGS" || { echo "❌ settings.json bị hỏng sau merge — kiểm tra lại"; exit 1; }
  echo "  ✓ .claude/settings.json"
fi

# ── 6. atomic ownership manifest ─────────────────────────────────────────
write_manifest() {
  local manifest="$ROUTE_DIR/$MANIFEST_REL" tmp files_json preserve_json hooks_json deny_json env_json
  mkdir -p "$(dirname "$manifest")"

  files_json='[]'
  if [ "${#SYNC_WRITTEN[@]}" -gt 0 ]; then
    files_json="$(for rel in "${SYNC_WRITTEN[@]}"; do
      [ -f "$ROUTE_DIR/$rel" ] && jq -n --arg p "$rel" --arg h "$(sha256_file "$ROUTE_DIR/$rel")" '{path:$p,sha256:$h}'
    done | jq -s 'unique_by(.path)')"
  fi
  preserve_json='[]'
  if [ "${#PRESERVE_PATHS[@]}" -gt 0 ]; then
    preserve_json="$(printf '%s\n' "${PRESERVE_PATHS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')"
  fi
  hooks_json="$(for ((i=0; i<${#OWNED_HOOKS[@]}; i+=3)); do
    jq -n --arg e "${OWNED_HOOKS[i]}" --arg m "${OWNED_HOOKS[i+1]}" --arg c "${OWNED_HOOKS[i+2]}" '{event:$e,matcher:$m,command:$c}'
  done | jq -s 'unique_by([.event,.matcher,.command])')"
  deny_json='[]'
  if [ "${#OWNED_DENY[@]}" -gt 0 ]; then
    deny_json="$(printf '%s\n' "${OWNED_DENY[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')"
  fi
  env_json='{}'
  if [ -f "$ROUTE_DIR/.claude/settings.json" ] && [ "${#OWNED_ENV_KEYS[@]}" -gt 0 ]; then
    for key in "${OWNED_ENV_KEYS[@]}"; do
      value="$(jq -r --arg k "$key" '.env[$k] // empty' "$ROUTE_DIR/.claude/settings.json")"
      env_json="$(jq --arg k "$key" --arg v "$value" '. + {($k):$v}' <<<"$env_json")"
    done
  fi

  tmp="$(mktemp "${manifest}.XXXXXX")"
  jq -n --arg hv "$HARNESS_VERSION" \
    --argjson files "$files_json" --argjson preserve "$preserve_json" \
    --argjson hooks "$hooks_json" --argjson deny "$deny_json" --argjson env "$env_json" \
    --arg status "$OWNED_STATUSLINE" \
    '{schemaVersion:1,harnessVersion:$hv,syncFiles:$files,preservePaths:$preserve,settings:{hooks:$hooks,deny:$deny,env:$env,statusLineCommand:(if $status=="" then null else $status end)}}' > "$tmp"
  mv "$tmp" "$manifest"
  echo "  ✓ $MANIFEST_REL"
}
write_manifest

# ── 7. report ────────────────────────────────────────────────────────────
echo
echo "✅ Xong. ${#WRITTEN[@]} file ghi vào $ROUTE_DIR."
if [ "${#HOOKS_WIRED[@]}" -gt 0 ]; then
  echo "Hooks wired:"
  for h in "${HOOKS_WIRED[@]}"; do echo "  • $h"; done
  echo "ℹ️  Off-switch: set env.HARNESS_DELEGATE=0 in .claude/settings.json to disable the harness without uninstalling."
  echo "ℹ️  Risk-path denylist: edit env.HARNESS_RISK_DIRS in .claude/settings.json (CSV, e.g. \"auth,wallet\") — takes effect immediately, no reinstall."
fi
if [ "$IS_GIT" -eq 0 ]; then
  echo "⚠️  $ROUTE_DIR không phải git repo — delegate wrapper (worktree) sẽ lỗi tới khi có git."
fi
echo "ℹ️  Delegate wrapper là bash-only — Windows cần WSL hoặc Git-Bash."
