#!/usr/bin/env bash
# install-global-skills.sh — cài/đồng bộ skill từ harness/templates/skills vào ~/.claude/skills
# (dùng được ở mọi project). Mặc định chỉ các skill trong GLOBAL_SKILLS; truyền tên để cài skill khác.
# Bản global khác template → backup sang ~/.claude/skills/.trash/<name>-<timestamp> rồi mới ghi đè.
# Skill chứa token @@...@@ (cần bake theo project) → từ chối, phải cài qua install-harness.sh.
set -euo pipefail

GLOBAL_SKILLS="ace-security-scan"
SRC="$(cd "$(dirname "$0")" && pwd)/harness/templates/skills"
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"

case "${1:-}" in -h|--help) sed -n '2,5p' "$0"; exit 0 ;; esac
[ $# -gt 0 ] && names="$*" || names="$GLOBAL_SKILLS"

mkdir -p "$DEST"
rc=0
for n in $names; do
  if [ ! -f "$SRC/$n/SKILL.md" ]; then echo "✗ $n: không có trong harness/templates/skills" >&2; rc=1; continue; fi
  if grep -rqE '@@[A-Z_]+@@' "$SRC/$n"; then echo "✗ $n: có token @@..@@ — cài theo project bằng install-harness.sh" >&2; rc=1; continue; fi
  if [ -d "$DEST/$n" ]; then
    if diff -rq "$SRC/$n" "$DEST/$n" >/dev/null 2>&1; then echo "= $n: đã mới nhất"; continue; fi
    mkdir -p "$DEST/.trash"
    bak="$DEST/.trash/$n-$(date +%Y%m%d-%H%M%S)"
    mv "$DEST/$n" "$bak"
    echo "↻ $n: backup bản cũ → $bak"
  fi
  cp -R "$SRC/$n" "$DEST/$n"
  echo "✓ $n → $DEST/$n"
done
exit $rc
