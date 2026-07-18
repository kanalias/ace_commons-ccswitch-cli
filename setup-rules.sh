#!/usr/bin/env bash
# Install global Claude Code rules (rules/*.md) into ~/.claude/rules/.
# Mirrors the directory: always copies and overwrites, and removes any *.md in
# the destination that no longer exists in rules/ (e.g. a rule deleted from
# this repo). No symlinks — symlinking personal rules into a repo-tracked path
# is a leak risk if the repo is ever shared/forked.
# Run standalone: bash setup-rules.sh
set -e

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rules"
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$SRC" ]; then
  echo "no rules/ dir found next to this script — nothing to install"
  exit 0
fi

printf "── mirror global rules into %s/rules/ (overwrites + removes anything not in rules/)? [y/N]: " "$CLAUDE_DIR"
read -r ans || ans=""

case "$ans" in
  y|Y) : ;;
  *) echo "skipped"; exit 0 ;;
esac

mkdir -p "$CLAUDE_DIR/rules"

for f in "$CLAUDE_DIR/rules"/*.md; do
  [ -e "$f" ] || [ -L "$f" ] || continue
  name="$(basename "$f")"
  if [ ! -e "$SRC/$name" ]; then
    rm -f "$f"
    echo "  ✗ rules/$name (removed — not in repo)"
  fi
done

for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  # Remove any existing symlink first so a stale link doesn't turn a copy into
  # writing through it to the old target.
  [ -L "$CLAUDE_DIR/rules/$name" ] && rm -f "$CLAUDE_DIR/rules/$name"
  cp "$f" "$CLAUDE_DIR/rules/$name"
  echo "  ✓ rules/$name (copied)"
done
