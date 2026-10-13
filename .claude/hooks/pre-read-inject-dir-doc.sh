#!/usr/bin/env bash
# PreToolUse hook (matcher: Read|Edit|Write|MultiEdit). Inject the per-directory
# doc (default MODULE.md) of the first sub-directory under a configured root
# whenever the AI touches a file there. Advisory: ALWAYS exit 0.
#
# Config (runtime env, set in .claude/settings.json "env"):
#   HARNESS_DIR_DOC_ROOTS  repo-relative dirs separated by ':' (e.g. src/app/modules). Empty/unset → no-op.
#   HARNESS_DIR_DOC_NAME   doc filename (default MODULE.md)
# Rule: .claude/rules/project/module-md.md
set -u

# harness off-switch
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0
[ -z "${HARNESS_DIR_DOC_ROOTS:-}" ] && exit 0

payload=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0

file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -z "$file_path" ] && exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
[ -z "$cwd" ] && cwd="$PWD"
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || session_id=""

DOC_NAME="${HARNESS_DIR_DOC_NAME:-MODULE.md}"
MAX_LINES=200

case "$file_path" in
  /*) abs="$file_path" ;;
  *) abs="$cwd/$file_path" ;;
esac

# Candidate base dirs: payload cwd, enclosing .claude/worktrees/<slug>, git toplevel
bases=("$cwd")
case "$abs" in
  */.claude/worktrees/*/*)
    wt="${abs%%/.claude/worktrees/*}/.claude/worktrees/$(printf '%s' "${abs#*/.claude/worktrees/}" | cut -d/ -f1)"
    bases+=("$wt")
    ;;
esac
top=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || top=""
[ -n "$top" ] && bases+=("$top")

doc="" ; subdir_rel=""
IFS=':' read -r -a roots <<<"$HARNESS_DIR_DOC_ROOTS"
for base in "${bases[@]}"; do
  rel="${abs#"$base"/}"
  [ "$rel" = "$abs" ] && continue
  for root in "${roots[@]}"; do
    root="${root#./}"; root="${root%/}"
    [ -z "$root" ] && continue
    case "$rel" in
      "$root"/*/*)
        sub=$(printf '%s' "${rel#"$root"/}" | cut -d/ -f1)
        doc="$base/$root/$sub/$DOC_NAME"
        subdir_rel="$root/$sub"
        break 2
        ;;
    esac
  done
done
[ -z "$doc" ] && exit 0
[ -f "$doc" ] || exit 0
# touching the doc itself → nothing to inject
[ "$abs" = "$doc" ] && exit 0

# dedup: once per session per doc
if [ -n "$session_id" ]; then
  cache_dir="$HOME/.cache/claude-code-ccswitch-cli-claude"
  mkdir -p "$cache_dir" 2>/dev/null || true
  if command -v shasum >/dev/null 2>&1; then
    h=$(printf '%s' "$doc" | shasum -a 256 | cut -d' ' -f1)
  else
    h=$(printf '%s' "$doc" | cksum | cut -d' ' -f1)
  fi
  sid=$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9_-' '_')
  marker="$cache_dir/dir-doc-$sid-$h"
  [ -f "$marker" ] && exit 0
  : >"$marker" 2>/dev/null || true
fi

total=$(wc -l <"$doc" | tr -d ' ')
content=$(head -n "$MAX_LINES" "$doc")
note=""
if [ "$total" -gt "$MAX_LINES" ]; then
  note="
[... truncated: showing first $MAX_LINES of $total lines — read the full file for the rest]"
fi

jq -n --arg ctx "📘 $DOC_NAME for $subdir_rel/ (auto-injected by pre-read-inject-dir-doc hook — read before editing):

$content$note" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}' 2>/dev/null || true
exit 0
