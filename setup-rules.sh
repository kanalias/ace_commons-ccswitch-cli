#!/usr/bin/env bash
# Install global Claude Code rules (rules/*.md) into ~/.claude/rules/.
# Existing files are never clobbered. Run standalone: bash setup-rules.sh
set -e

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rules"
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$SRC" ]; then
  echo "no rules/ dir found next to this script — nothing to install"
  exit 0
fi

echo "── install global rules into $CLAUDE_DIR/rules/ ?"
printf "   [c]opy / [s]ymlink / [N]o: "
read -r ans || ans=""

case "$ans" in
  c|C) mode=copy ;;
  s|S) mode=symlink ;;
  *) echo "skipped"; exit 0 ;;
esac

mkdir -p "$CLAUDE_DIR/rules"
for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  if [ -e "$CLAUDE_DIR/rules/$name" ] || [ -L "$CLAUDE_DIR/rules/$name" ]; then
    echo "  • rules/$name exists — kept"
    continue
  fi
  if [ "$mode" = copy ]; then
    cp "$f" "$CLAUDE_DIR/rules/$name"
    echo "  ✓ rules/$name (copied)"
  else
    ln -s "$f" "$CLAUDE_DIR/rules/$name"
    echo "  ✓ rules/$name (symlinked → $f)"
  fi
done
