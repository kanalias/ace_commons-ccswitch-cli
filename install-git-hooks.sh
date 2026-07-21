#!/usr/bin/env bash
# Cài git hooks của repo này vào .git/hooks/ (symlink). Chạy 1 lần sau clone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$ROOT/dev-hooks/git-hooks/pre-push"
HOOK_DST="$ROOT/.git/hooks/pre-push"

[ -f "$HOOK_SRC" ] || { echo "❌ không thấy $HOOK_SRC"; exit 1; }
chmod +x "$HOOK_SRC"
mkdir -p "$ROOT/.git/hooks"

if ln -sf "../../dev-hooks/git-hooks/pre-push" "$HOOK_DST" 2>/dev/null; then
  echo "✅ symlinked .git/hooks/pre-push → git-hooks/pre-push"
else
  cp "$HOOK_SRC" "$HOOK_DST" && chmod +x "$HOOK_DST"
  echo "✅ copied pre-push (symlink unsupported)"
fi

if command -v gitleaks >/dev/null 2>&1; then
  echo "  gitleaks: $(gitleaks version)"
else
  echo "  ⚠️ gitleaks chưa cài — brew install gitleaks (hook sẽ advisory-skip tới khi cài)"
fi
