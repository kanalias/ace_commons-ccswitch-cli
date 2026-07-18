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
# 3 router profiles (claude, codex, deepseek), all via 9router, sharing ONE token (fill the same key into all three).
# `subscription` is the env-clear fallback (no file, no key).
PROFILE_TARGETS=(claude codex deepseek)
for p in "${PROFILE_TARGETS[@]}"; do
  if [ -f "$PROFILES/$p.json" ]; then
    echo "  • profiles/$p.json exists — kept (edit manually or run: ccswitch set-key $p)"
  else
    cp "$SRC/profiles/$p.json" "$PROFILES/$p.json"
    echo "  ✓ profiles/$p.json (template — fill in your key)"
  fi
done

# 2b. fill credentials into all 3 profiles (claude/codex/deepseek share ONE 9router token).
# Preferred source: `.env.pro` next to this script (gitignored) holding `proxy_host=` +
# `proxy_key=`. When both are present we ask ONCE — Enter / yes (default) writes host + key
# into all three profiles; no falls back to the manual prompts (host, then key). Key values
# are never echoed. Non-interactive: .env.pro is applied only while the profiles still hold
# placeholders — a real key is never clobbered without a terminal to confirm.
ENV_PRO="$SRC/.env.pro"

env_pro_val() {  # env_pro_val <name> — first `name=value` line; strips CR + optional quotes
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$ENV_PRO" 2>/dev/null \
    | head -n1 | tr -d '\r' | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

any_real_key() {  # true if any profile already holds a non-placeholder token
  local target cur
  for target in "${PROFILE_TARGETS[@]}"; do
    cur=$(jq -r '.ANTHROPIC_AUTH_TOKEN // empty' "$PROFILES/$target.json" 2>/dev/null || true)
    if [ -n "$cur" ] && ! printf '%s' "$cur" | grep -q '<your-9router-key>'; then return 0; fi
  done
  return 1
}

apply_env_pro() {  # write proxy_host + proxy_key from .env.pro into all 3 profiles
  local failed=0 target dst
  for target in "${PROFILE_TARGETS[@]}"; do
    dst="$PROFILES/$target.json"
    cp "$dst" "$dst.bak" 2>/dev/null || true
    jq --arg u "$ENV_PRO_HOST" --arg k "$ENV_PRO_KEY" \
      '.ANTHROPIC_BASE_URL = $u | .ANTHROPIC_AUTH_TOKEN = $k' "$dst" > "$dst.tmp" \
      && mv "$dst.tmp" "$dst" \
      || { echo "  ❌ failed to write .env.pro values to profiles/$target.json (profile unchanged)"; rm -f "$dst.tmp"; failed=1; }
  done
  [ "$failed" -eq 0 ] && echo "  ✓ .env.pro proxy_host + proxy_key applied to profiles/{$(IFS=,; echo "${PROFILE_TARGETS[*]}")}.json"
}

prompt_host() {  # manual base-URL prompt — Enter keeps whatever the profiles already have
  local cur host failed=0 target dst
  cur=$(jq -r '.ANTHROPIC_BASE_URL // empty' "$PROFILES/claude.json" 2>/dev/null || true)
  printf "  ▸ Router base URL [%s] (Enter to keep): " "${cur:-none}"
  read -r host
  if [ -z "$host" ]; then echo "    kept current base URL."; return; fi
  for target in "${PROFILE_TARGETS[@]}"; do
    dst="$PROFILES/$target.json"
    cp "$dst" "$dst.bak" 2>/dev/null || true
    jq --arg u "$host" '.ANTHROPIC_BASE_URL = $u' "$dst" > "$dst.tmp" \
      && mv "$dst.tmp" "$dst" \
      || { echo "  ❌ failed to write base URL to profiles/$target.json (profile unchanged)"; rm -f "$dst.tmp"; failed=1; }
  done
  [ "$failed" -eq 0 ] && echo "  ✓ base URL saved to profiles/{$(IFS=,; echo "${PROFILE_TARGETS[*]}")}.json"
}

prompt_shared_key() {
  # A real key already exists somewhere. Ask to overwrite ALL THREE at once; default No.
  if any_real_key; then
    printf "  • one or more profiles already hold a key. Overwrite all with a new shared key? [y/N] "
    local ans; read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) echo "    kept existing keys."; return ;; esac
  fi

  local key
  printf "  ▸ Paste the shared 9router key (input hidden, Enter to skip): "
  read -rs key; echo
  if [ -z "$key" ]; then
    echo "    skipped — kept placeholders (fill later: ccswitch set-key <target>)."
    return
  fi

  local failed=0
  for target in "${PROFILE_TARGETS[@]}"; do
    local dst="$PROFILES/$target.json"
    cp "$dst" "$dst.bak" 2>/dev/null || true
    jq --arg k "$key" '.ANTHROPIC_AUTH_TOKEN = $k' "$dst" > "$dst.tmp" \
      && mv "$dst.tmp" "$dst" \
      || { echo "  ❌ failed to write key to profiles/$target.json (profile unchanged)"; rm -f "$dst.tmp"; failed=1; }
  done
  unset key
  [ "$failed" -eq 0 ] && echo "  ✓ shared key saved to profiles/{$(IFS=,; echo "${PROFILE_TARGETS[*]}")}.json"
}

ENV_PRO_HOST=""; ENV_PRO_KEY=""
if [ -f "$ENV_PRO" ]; then
  ENV_PRO_HOST=$(env_pro_val proxy_host)
  ENV_PRO_KEY=$(env_pro_val proxy_key)
fi

USE_ENV_PRO=0
if [ -n "$ENV_PRO_HOST" ] && [ -n "$ENV_PRO_KEY" ]; then
  if [ -t 0 ]; then
    any_real_key && echo "  • profiles already hold a key — answering Yes overwrites all three."
    printf "  ▸ Use proxy_host + proxy_key from .env.pro for all profiles (claude/codex/deepseek)? [Y/n] "
    read -r ans
    case "$ans" in n|N|no|NO) ;; *) USE_ENV_PRO=1 ;; esac
  else
    if any_real_key; then
      echo "  • .env.pro found but profiles already hold a key — kept (overwrite: re-run in a terminal, or ccswitch set-key)"
    else
      USE_ENV_PRO=1
      echo "  • non-interactive shell — using proxy_host + proxy_key from .env.pro (default Yes)"
    fi
  fi
elif [ -f "$ENV_PRO" ]; then
  echo "  • .env.pro found but missing proxy_host/proxy_key — ignored"
fi

if [ "$USE_ENV_PRO" -eq 1 ]; then
  apply_env_pro
elif [ -t 0 ]; then
  echo "  ── enter router base URL + one shared key for claude+codex+deepseek ──"
  prompt_host
  prompt_shared_key
else
  # non-interactive (piped install / CI) — keep template placeholders.
  echo "  • non-interactive shell — skipped key prompt (fill later: ccswitch set-key <target>)"
fi
unset ENV_PRO_KEY

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
for pair in claude:cc codex:cx deepseek:ds; do
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
echo "   1. (if you skipped the prompt) Fill a key:  ccswitch set-key <claude|codex|deepseek>  (same 9router key for all three)"
echo "   2. Activate:        source $SHELL_RC && ccswitch claude   (or: codex / deepseek)"
echo "   3. Restart Claude Code (quit + reopen) to load the new env."
echo "   4. Parallel:        open 3 terminals → claude-cc / claude-cx / claude-ds"
echo "                       (3 vendors at once — same 9router account = shared quota)"
