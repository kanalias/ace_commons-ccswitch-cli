#!/usr/bin/env bash
# Install global Claude Code rules (rules/*.md) into ~/.claude/rules/.
# Always copies and overwrites — no symlinks (symlinking personal rules into a
# repo-tracked path is a leak risk if the repo is ever shared/forked).
# Run standalone: bash setup-rules.sh
set -e

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rules"
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$SRC" ]; then
  echo "no rules/ dir found next to this script — nothing to install"
  exit 0
fi

printf "── copy global rules into %s/rules/ (overwrites existing)? [y/N]: " "$CLAUDE_DIR"
read -r ans || ans=""

case "$ans" in
  y|Y) : ;;
  *) echo "skipped"; exit 0 ;;
esac

mkdir -p "$CLAUDE_DIR/rules"
for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  # Remove any existing symlink first so a stale link doesn't turn a copy into
  # writing through it to the old target.
  [ -L "$CLAUDE_DIR/rules/$name" ] && rm -f "$CLAUDE_DIR/rules/$name"
  cp "$f" "$CLAUDE_DIR/rules/$name"
  echo "  ✓ rules/$name (copied)"
done
