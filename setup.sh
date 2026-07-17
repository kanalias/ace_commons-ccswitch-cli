#!/usr/bin/env bash
# ccswitch setup (macOS / Linux).
# Installs ccswitch.sh + profile templates + SessionStart health hook into ~/.claude,
# then wires a `ccswitch` shell alias. Never overwrites existing profiles that already
# hold real keys — templates are only copied when the target file is missing.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
PROFILES="$CLAUDE_DIR/profiles"
HOOKS="$CLAUDE_DIR/hooks"

echo "▶ ccswitch setup — installing into $CLAUDE_DIR"

command -v jq  >/dev/null 2>&1 || { echo "❌ 'jq' required. Install: brew install jq  (mac) / apt install jq (linux)"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ 'curl' required."; exit 1; }

mkdir -p "$PROFILES" "$HOOKS"

# 1. tool + hook (always refreshed — no secrets inside)
cp "$SRC/ccswitch.sh"        "$CLAUDE_DIR/ccswitch.sh"
cp "$SRC/hooks/check-router.sh" "$HOOKS/check-router.sh"
chmod +x "$CLAUDE_DIR/ccswitch.sh" "$HOOKS/check-router.sh"
echo "  ✓ ccswitch.sh + hooks/check-router.sh"

# 2. profile templates — copy ONLY if missing (never clobber a real key).
# 2 router profiles (claude, deepseek), both via 9router, sharing ONE token (fill the same key into both).
# `subscription` is the env-clear fallback (no file, no key).
PROFILE_TARGETS=(claude deepseek)
for p in "${PROFILE_TARGETS[@]}"; do
  if [ -f "$PROFILES/$p.json" ]; then
    echo "  • profiles/$p.json exists — kept (edit manually or run: ccswitch set-key $p)"
  else
    cp "$SRC/profiles/$p.json" "$PROFILES/$p.json"
    echo "  ✓ profiles/$p.json (template — fill in your key)"
  fi
done

# 2b. prompt for each target's key (interactive only — never echoed, never clobbers silently).
# Each target is INDEPENDENT: a user who only uses one can skip the others with Enter.
prompt_key() {
  local target="$1" dst="$PROFILES/$1.json"
  local cur
  cur=$(jq -r '.ANTHROPIC_AUTH_TOKEN // empty' "$dst" 2>/dev/null || true)

  # A real key = non-empty and not the placeholder. Ask to overwrite; default No.
  if [ -n "$cur" ] && ! printf '%s' "$cur" | grep -q '<your-9router-key>'; then
    printf "  • profiles/%s.json already holds a key. Overwrite? [y/N] " "$target"
    local ans; read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) echo "    kept existing key."; return ;; esac
  fi

  local key
  printf "  ▸ Paste key for '%s' (input hidden, Enter to skip): " "$target"
  read -rs key; echo
  [ -n "$key" ] || { echo "    skipped — kept placeholder (fill later: ccswitch set-key $target)."; return; }

  cp "$dst" "$dst.bak" 2>/dev/null || true
  jq --arg k "$key" '.ANTHROPIC_AUTH_TOKEN = $k' "$dst" > "$dst.tmp" \
    && mv "$dst.tmp" "$dst" \
    && echo "  ✓ key saved to profiles/$target.json" \
    || { echo "  ❌ failed to write key (profile unchanged)"; rm -f "$dst.tmp"; }
  unset key
}
if [ -t 0 ]; then
  echo "  ── enter tokens (each independent — Enter to skip a target you don't use) ──"
  for p in "${PROFILE_TARGETS[@]}"; do prompt_key "$p"; done
else
  # non-interactive (piped install / CI) — keep template placeholders.
  echo "  • non-interactive shell — skipped key prompts (fill later: ccswitch set-key <target>)"
fi

# 3. ensure settings.json exists + wire SessionStart hook idempotently
SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
HOOK_CMD="bash ~/.claude/hooks/check-router.sh"
if ! jq -e --arg c "$HOOK_CMD" \
     '.hooks.SessionStart[]?.hooks[]? | select(.command == $c)' "$SETTINGS" >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak"
  jq --arg c "$HOOK_CMD" '
    .hooks //= {} |
    .hooks.SessionStart //= [] |
    .hooks.SessionStart += [ { "hooks": [ { "type": "command", "command": $c } ] } ]
  ' "$SETTINGS.bak" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  ✓ wired SessionStart auto-switch hook into settings.json (disable: export CCSWITCH_NO_AUTO=1)"
else
  echo "  • SessionStart hook already wired — skipped"
fi

# 3b. default model — set only if the user hasn't already chosen one (never clobber a pref).
if ! jq -e '.model' "$SETTINGS" >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak"
  jq '.model = "sonnet"' "$SETTINGS.bak" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  ✓ set default model to sonnet in settings.json"
else
  echo "  • settings.json already has a model preference — skipped"
fi

# 4. shell alias — pick rc by the user's LOGIN shell ($SHELL), not the interpreter running
#    this script (setup.sh always runs under bash, so $BASH_VERSION is a false signal → it
#    would always pick .bashrc even for zsh users). Fall back to .zshrc (macOS default).
case "${SHELL:-}" in
  */bash) SHELL_RC="$HOME/.bashrc" ;;
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  *)      SHELL_RC="$HOME/.zshrc" ;;
esac
ALIAS_LINE="alias ccswitch='bash ~/.claude/ccswitch.sh'"
if ! grep -qF "$ALIAS_LINE" "$SHELL_RC" 2>/dev/null; then
  echo "$ALIAS_LINE" >> "$SHELL_RC"
  echo "  ✓ added alias to $SHELL_RC (run: source $SHELL_RC)"
else
  echo "  • alias already in $SHELL_RC — skipped"
fi

# 4b. parallel-launcher aliases — one per target. Each spawns a SEPARATE Claude Code
#     instance pinned to that vendor via process env. Open N terminals + run N of these
#     = N vendors in parallel (single-instance switch can only hold one at a time).
# (bash 3.2 compat — macOS ships old bash; no associative arrays)
for pair in claude:cc deepseek:ds; do
  t=${pair%%:*}; short=${pair##*:}
  spawn_line="alias claude-${short}='bash ~/.claude/ccswitch.sh spawn ${t}'"
  if ! grep -qF "$spawn_line" "$SHELL_RC" 2>/dev/null; then
    echo "$spawn_line" >> "$SHELL_RC"
    echo "  ✓ added launcher alias claude-${short} ($t)"
  else
    echo "  • launcher claude-${short} already in $SHELL_RC — skipped"
  fi
done

echo
echo "✅ Installed. Next steps:"
echo "   1. (if you skipped a prompt) Fill a key:  ccswitch set-key <claude|deepseek>  (same 9router key for both)"
echo "   2. Activate:        source $SHELL_RC && ccswitch claude   (or: deepseek)"
echo "   3. Restart Claude Code (quit + reopen) to load the new env."
echo "   4. Parallel:        open 3 terminals → claude-cc / claude-cx / claude-ds"
echo "                       (2 vendors at once — same 9router account = shared quota)"
