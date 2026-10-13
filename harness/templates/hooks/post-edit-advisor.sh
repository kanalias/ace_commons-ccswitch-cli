#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write|MultiEdit). Merge of
# post-edit-syntax-check.sh + remind-lazy-load-health.sh +
# post-write-memory-mirror.sh — all 3 advisory-only, exit 0 always.
set -euo pipefail

# harness off-switch — set HARNESS_DELEGATE=0 in .claude/settings.local.json to disable
[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0

# ── 1) syntax check (*.json/*.js/*.mjs/*.cjs) ───────────────────────────────
if [ -f "$file_path" ]; then
  case "$file_path" in
    *.json)
      if ! jq empty "$file_path" 2>/dev/null; then
        echo "⚠️ post-edit-syntax-check: $file_path JSON parse lỗi" >&2
      fi
      ;;
    *.js|*.mjs|*.cjs)
      if ! node --check "$file_path" 2>/dev/null; then
        err=$(node --check "$file_path" 2>&1 | tail -3) || true
        echo "⚠️ post-edit-syntax-check: $file_path — $err" >&2
      fi
      ;;
  esac
fi

# ── 2) lazy-load reminder (.claude/rules/*.md) ──────────────────────────────
# Guarded with || true — REPO/rel computation must not abort other sections under -e.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null)" || REPO=""
if [ -n "$REPO" ]; then
  rel="${file_path#$REPO/}"
  case "$rel" in
    .claude/rules/*.md)
      cat >&2 <<MSG
📋 Reminder: vừa sửa $rel — chạy /audit-context-memory --rules-only để kiểm tra rule này còn đạt chuẩn lazy-load không (paths: frontmatter, gate P0-mọi-turn). Quyết định sửa hay bỏ qua là của bạn.
MSG
      ;;
  esac
fi

# ── 3) memory-mirror reminder (auto-memory type: project) ──────────────────
case "$file_path" in
  */.claude/projects/*/memory/*.md)
    if [ -f "$file_path" ] && [ "$(basename "$file_path")" != "MEMORY.md" ]; then
      mem_type=$(head -15 "$file_path" | grep -E '^(  )?type:' | head -1 | sed -E 's/^(  )?type:[[:space:]]*//')
      case "$mem_type" in
        *project*)
          echo "📝 post-write-memory-mirror: '$file_path' is project-type memory. Mirror it to repo: .claude/memory-mirror/<name>.md (audit for secrets first, per [[memory-mirror]] rule)." >&2
          ;;
      esac
    fi
    ;;
esac

# ── 4) per-directory doc reminder (HARNESS_DIR_DOC_ROOTS / HARNESS_DIR_DOC_NAME) ──
# Source file edited under <root>/<subdir>/ whose doc exists and is OLDER than the file → remind.
if [ -n "${HARNESS_DIR_DOC_ROOTS:-}" ] && [ -f "$file_path" ]; then
  _dd_name="${HARNESS_DIR_DOC_NAME:-MODULE.md}"
  _dd_cwd=$(echo "$payload" | jq -r '.cwd // empty' 2>/dev/null) || _dd_cwd=""
  [ -z "$_dd_cwd" ] && _dd_cwd="$PWD"
  case "$file_path" in /*) _dd_abs="$file_path" ;; *) _dd_abs="$_dd_cwd/$file_path" ;; esac
  _dd_skip=0
  case "$_dd_abs" in
    *.md|*.json|*.yaml|*.yml|*.snap|*.test.*|*.spec.*|*/__fixtures__/*|*/__snapshots__/*) _dd_skip=1 ;;
  esac
  if [ "$_dd_skip" = "0" ]; then
    _dd_bases=("$_dd_cwd")
    case "$_dd_abs" in
      */.claude/worktrees/*/*)
        _dd_bases+=("${_dd_abs%%/.claude/worktrees/*}/.claude/worktrees/$(printf '%s' "${_dd_abs#*/.claude/worktrees/}" | cut -d/ -f1)")
        ;;
    esac
    _dd_top=$(cd "$_dd_cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || _dd_top=""
    [ -n "$_dd_top" ] && _dd_bases+=("$_dd_top")
    _dd_doc=""; _dd_dir=""
    IFS=':' read -r -a _dd_roots <<<"$HARNESS_DIR_DOC_ROOTS"
    for _dd_base in "${_dd_bases[@]}"; do
      _dd_rel="${_dd_abs#"$_dd_base"/}"
      [ "$_dd_rel" = "$_dd_abs" ] && continue
      for _dd_root in "${_dd_roots[@]}"; do
        _dd_root="${_dd_root#./}"; _dd_root="${_dd_root%/}"
        [ -z "$_dd_root" ] && continue
        case "$_dd_rel" in
          "$_dd_root"/*/*)
            _dd_sub=$(printf '%s' "${_dd_rel#"$_dd_root"/}" | cut -d/ -f1)
            _dd_doc="$_dd_base/$_dd_root/$_dd_sub/$_dd_name"
            _dd_dir="$_dd_root/$_dd_sub"
            break 2
            ;;
        esac
      done
    done
    if [ -n "$_dd_doc" ] && [ -f "$_dd_doc" ]; then
      _dd_doc_m=$(stat -f %m "$_dd_doc" 2>/dev/null || stat -c %Y "$_dd_doc" 2>/dev/null || echo 0)
      _dd_src_m=$(stat -f %m "$_dd_abs" 2>/dev/null || stat -c %Y "$_dd_abs" 2>/dev/null || echo 0)
      if [ "$_dd_doc_m" -lt "$_dd_src_m" ]; then
        echo "📝 Reminder: vừa sửa $_dd_dir/$(basename "$_dd_abs") nhưng $_dd_dir/$_dd_name cũ hơn — cập nhật doc trong CÙNG commit (tối thiểu dòng 'Last updated'). Xem rule module-md." >&2
      fi
    fi
  fi
fi

exit 0
