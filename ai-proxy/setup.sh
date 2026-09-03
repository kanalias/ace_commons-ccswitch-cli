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
ln -sfn "$SRC/ccswitch.sh" "$CLAUDE_DIR/ccswitch.sh"
cp "$SRC/hooks/check-router.sh" "$HOOKS/check-router.sh"
chmod +x "$SRC/ccswitch.sh" "$HOOKS/check-router.sh"
echo "  ✓ ccswitch.sh linked + hooks/check-router.sh"
printf '%s\n' "$(dirname "$SRC")" > "$CLAUDE_DIR/.ccswitch-repo"
echo "  ✓ repo path recorded (ccswitch install)"
cp "$SRC/statusline-context.sh" "$CLAUDE_DIR/statusline-context.sh"
chmod +x "$CLAUDE_DIR/statusline-context.sh"
echo "  ✓ statusline-context.sh (context-usage early-warning bar)"

# 2. profile templates — copy ONLY if missing (never clobber a real key).
# 4 profiles: claude/codex/deepseek/kimi via 9router share ONE token.
# kimi_api_key_force_subscription=1 switches kimi to Kimi's own direct Anthropic-compatible endpoint instead.
# `subscription` is the env-clear fallback (no file, no key).
PROFILE_TARGETS=(claude codex deepseek kimi)
ROUTER_TARGETS=(claude codex deepseek kimi)
for p in "${PROFILE_TARGETS[@]}"; do
  if [ -f "$PROFILES/$p.json" ]; then
    echo "  • profiles/$p.json exists — kept (edit manually or run: ccswitch set-key $p)"
  else
    cp "$SRC/profiles/$p.json" "$PROFILES/$p.json"
    echo "  ✓ profiles/$p.json (template — fill in your key)"
  fi
done

# 2b. fill credentials into all 3 router profiles (claude/codex/deepseek share ONE 9router token).
# Preferred source: `.env` at repo root (one level up from this script's dir, gitignored)
# holding `proxy_host=` + `proxy_key=`. When both are present, ALWAYS overwrite host + key
# in all three router profiles — no prompt, no placeholder check, interactive or not. `.env` is the
# source of truth; re-run this script any time it changes to resync. No `.env` (or missing
# fields) falls back to the manual prompts (host, then key). Key values are never echoed.
ENV_PRO="$(dirname "$SRC")/.env"

env_pro_val() {  # env_pro_val <name> — first `name=value` line; strips CR + optional quotes
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$ENV_PRO" 2>/dev/null \
    | head -n1 | tr -d '\r' | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

any_real_key() {  # true if any profile already holds a non-placeholder token
  local target cur
  for target in "${ROUTER_TARGETS[@]}"; do
    cur=$(jq -r '.ANTHROPIC_AUTH_TOKEN // empty' "$PROFILES/$target.json" 2>/dev/null || true)
    if [ -n "$cur" ] && ! printf '%s' "$cur" | grep -q '<your-9router-key>'; then return 0; fi
  done
  return 1
}

mask_secret() {  # mask_secret <value> — first4...last4 + length; never the full value
  local v="$1" len=${#1}
  if [ "$len" -le 8 ]; then printf '%s' "****"; else printf '%s...%s (len=%d)' "${v:0:4}" "${v: -4}" "$len"; fi
}

apply_env_pro() {  # write proxy_host + proxy_key from .env into all router profiles
  local failed=0 target dst
  for target in "${ROUTER_TARGETS[@]}"; do
    dst="$PROFILES/$target.json"
    cp "$dst" "$dst.bak" 2>/dev/null || true
    jq --arg u "$ENV_PRO_HOST" --arg k "$ENV_PRO_KEY" \
      '.ANTHROPIC_BASE_URL = $u | .ANTHROPIC_AUTH_TOKEN = $k' "$dst" > "$dst.tmp" \
      && mv "$dst.tmp" "$dst" \
      || { echo "  ❌ failed to write .env values to profiles/$target.json (profile unchanged)"; rm -f "$dst.tmp"; failed=1; }
  done
  if [ "$failed" -eq 0 ]; then
    echo "  ✓ .env proxy_host + proxy_key applied to profiles/{$(IFS=,; echo "${ROUTER_TARGETS[*]}")}.json"
    echo "    1. proxy_key : $(mask_secret "$ENV_PRO_KEY")"
    echo "    2. proxy_host: $ENV_PRO_HOST"
    echo "    3. updated  : ${#ROUTER_TARGETS[@]} profile(s)"
    for target in "${ROUTER_TARGETS[@]}"; do
      echo "       - $PROFILES/$target.json"
    done
  fi
}

apply_kimi_env() {  # write kimi_api_key from .env into kimi profile only when forced
  [ "${KIMI_FORCE_SUBSCRIPTION:-0}" = "1" ] || return 0
  if [ -z "${KIMI_ENV_KEY:-}" ]; then
    echo "  • kimi_api_key_force_subscription=1 but kimi_api_key missing — kimi profile kept"
    return
  fi
  local dst="$PROFILES/kimi.json"
  [ -f "$dst" ] || cp "$SRC/profiles/kimi.json" "$dst"
  cp "$dst" "$dst.bak" 2>/dev/null || true
  jq --arg k "$KIMI_ENV_KEY" '.ANTHROPIC_BASE_URL = "https://api.moonshot.ai/anthropic" | .ANTHROPIC_AUTH_TOKEN = $k | .ANTHROPIC_DEFAULT_OPUS_MODEL = "kimi-k3" | .ANTHROPIC_DEFAULT_SONNET_MODEL = "kimi-k3" | .ANTHROPIC_DEFAULT_HAIKU_MODEL = "kimi-k3" | .ANTHROPIC_DEFAULT_FABLE_MODEL = "kimi-k3"' "$dst" > "$dst.tmp" \
    && mv "$dst.tmp" "$dst" \
    || { echo "  ❌ failed to write .env kimi key to profiles/kimi.json (profile unchanged)"; rm -f "$dst.tmp"; return; }
  echo "  ✓ .env kimi_api_key applied to profiles/kimi.json (direct endpoint mode)"
}

prompt_host() {  # manual base-URL prompt — Enter keeps whatever the profiles already have
  local cur host failed=0 target dst
  cur=$(jq -r '.ANTHROPIC_BASE_URL // empty' "$PROFILES/claude.json" 2>/dev/null || true)
  printf "  ▸ Router base URL [%s] (Enter to keep): " "${cur:-none}"
  read -r host
  if [ -z "$host" ]; then echo "    kept current base URL."; return; fi
  for target in "${ROUTER_TARGETS[@]}"; do
    dst="$PROFILES/$target.json"
    cp "$dst" "$dst.bak" 2>/dev/null || true
    jq --arg u "$host" '.ANTHROPIC_BASE_URL = $u' "$dst" > "$dst.tmp" \
      && mv "$dst.tmp" "$dst" \
      || { echo "  ❌ failed to write base URL to profiles/$target.json (profile unchanged)"; rm -f "$dst.tmp"; failed=1; }
  done
  [ "$failed" -eq 0 ] && echo "  ✓ base URL saved to profiles/{$(IFS=,; echo "${ROUTER_TARGETS[*]}")}.json"
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
  for target in "${ROUTER_TARGETS[@]}"; do
    local dst="$PROFILES/$target.json"
    cp "$dst" "$dst.bak" 2>/dev/null || true
    jq --arg k "$key" '.ANTHROPIC_AUTH_TOKEN = $k' "$dst" > "$dst.tmp" \
      && mv "$dst.tmp" "$dst" \
      || { echo "  ❌ failed to write key to profiles/$target.json (profile unchanged)"; rm -f "$dst.tmp"; failed=1; }
  done
  unset key
  [ "$failed" -eq 0 ] && echo "  ✓ shared key saved to profiles/{$(IFS=,; echo "${ROUTER_TARGETS[*]}")}.json"
}

ENV_PRO_HOST=""; ENV_PRO_KEY=""; KIMI_FORCE_SUBSCRIPTION="0"; KIMI_ENV_KEY=""
if [ -f "$ENV_PRO" ]; then
  ENV_PRO_HOST=$(env_pro_val proxy_host)
  ENV_PRO_KEY=$(env_pro_val proxy_key)
  KIMI_FORCE_SUBSCRIPTION=$(env_pro_val kimi_api_key_force_subscription)
  KIMI_ENV_KEY=$(env_pro_val kimi_api_key)
fi

USE_ENV_PRO=0
if [ -n "$ENV_PRO_HOST" ] && [ -n "$ENV_PRO_KEY" ]; then
  USE_ENV_PRO=1
  any_real_key && echo "  • profiles already hold a key — .env always overrides host+key (by design, no prompt)."
elif [ -f "$ENV_PRO" ]; then
  echo "  • .env found but missing proxy_host/proxy_key — ignored"
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
apply_kimi_env
unset ENV_PRO_KEY KIMI_ENV_KEY

# 3. ensure settings.json exists + wire SessionStart hook (upsert by basename, not full-string
#    match) — a stale entry pointing at a different path/wording for check-router.sh would
#    otherwise never get cleaned up and re-installs would pile up duplicate hook entries.
SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
HOOK_CMD="bash ~/.claude/hooks/check-router.sh"
cp "$SETTINGS" "$SETTINGS.bak"
jq --arg c "$HOOK_CMD" '
  .hooks //= {} |
  .hooks.SessionStart //= [] |
  .hooks.SessionStart = [ .hooks.SessionStart[]? | .hooks |= [ .[]? | select(.command? | test("check-router\\.sh") | not) ] | select((.hooks | length) > 0) ] |
  .hooks.SessionStart += [ { "hooks": [ { "type": "command", "command": $c } ] } ]
' "$SETTINGS.bak" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS" && rm -f "$SETTINGS.bak"
echo "  ✓ synced SessionStart auto-switch hook into settings.json (disable: export CCSWITCH_NO_AUTO=1)"

# 3a. wire statusLine (context-usage early-warning bar) idempotently
SL_CMD="bash ~/.claude/statusline-context.sh"
if [ "$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)" != "$SL_CMD" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  jq --arg c "$SL_CMD" '.statusLine = { "type": "command", "command": $c }' \
    "$SETTINGS.bak" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  ✓ wired statusLine (context-usage bar) into settings.json"
else
  echo "  • statusLine already wired — skipped"
fi

# 3b. default model — intentionally NOT set. Let Claude Code pick per its own default
#     (last-used / account default). Forcing a `.model` here caused a stale pin (e.g. sonnet)
#     to be requested even after the active endpoint changed. The user chooses via /model.

# 4. shell alias — pick rc by the user's LOGIN shell ($SHELL), not the interpreter running
#    this script (setup.sh always runs under bash, so $BASH_VERSION is a false signal → it
#    would always pick .bashrc even for zsh users). Fall back to .zshrc (macOS default).
case "${SHELL:-}" in
  */bash) SHELL_RC="$HOME/.bashrc" ;;
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  *)      SHELL_RC="$HOME/.zshrc" ;;
esac

# upsert_alias <key-pattern (ERE, anchored)> <full alias line>
# Re-installs must converge to the CURRENT line even if content changed (e.g. a moved
# ccswitch.sh path) — a plain "skip if present" check would leave the stale line behind
# and append a second, conflicting one. So: drop any line matching the key, then append.
upsert_alias() {
  local key="$1" line="$2"
  [ -f "$SHELL_RC" ] || : > "$SHELL_RC"
  if grep -qE "$key" "$SHELL_RC"; then
    sed -i.bak -E "/$key/d" "$SHELL_RC" && rm -f "$SHELL_RC.bak"
  fi
  echo "$line" >> "$SHELL_RC"
}

if grep -qF "alias ccswitch='bash ~/.claude/ccswitch.sh'" "$SHELL_RC" 2>/dev/null; then
  echo "  • alias already in $SHELL_RC — skipped"
else
  upsert_alias "^alias ccswitch=" "alias ccswitch='bash ~/.claude/ccswitch.sh'"
  echo "  ✓ synced alias in $SHELL_RC (run: source $SHELL_RC)"
fi

# 4b. parallel-launcher aliases — one per target. Each spawns a SEPARATE Claude Code
#     instance pinned to that vendor via process env. Open N terminals + run N of these
#     = N vendors in parallel (single-instance switch can only hold one at a time).
# (bash 3.2 compat — macOS ships old bash; no associative arrays)
for pair in claude:cc codex:cx deepseek:ds kimi:km; do
  t=${pair%%:*}; short=${pair##*:}
  spawn_line="alias claude-${short}='bash ~/.claude/ccswitch.sh spawn ${t}'"
  if grep -qF "$spawn_line" "$SHELL_RC" 2>/dev/null; then
    echo "  • launcher claude-${short} already in $SHELL_RC — skipped"
  else
    upsert_alias "^alias claude-${short}=" "$spawn_line"
    echo "  ✓ synced launcher alias claude-${short} ($t)"
  fi
done

# 5. auto-activate 'claude' — only if it now holds a real (non-placeholder) key, so
#    settings.json is ready to use without a separate manual `ccswitch claude` step.
echo
AUTO_SWITCHED=0
claude_tok=$(jq -r '.ANTHROPIC_AUTH_TOKEN // empty' "$PROFILES/claude.json" 2>/dev/null || true)
if [ -n "$claude_tok" ] && ! printf '%s' "$claude_tok" | grep -q '<your-9router-key>'; then
  echo "▶ auto-activating 'claude' profile into settings.json ..."
  if bash "$CLAUDE_DIR/ccswitch.sh" claude; then
    AUTO_SWITCHED=1
  else
    echo "  ⚠️  auto-switch failed — activate manually: ccswitch claude"
  fi
else
  echo "  • profiles/claude.json still has a placeholder key — skipping auto-switch"
fi
unset claude_tok

echo
echo "✅ Installed. Next steps:"
echo "   1. (if you skipped the prompt) Fill a key:  ccswitch set-key <claude|codex|deepseek|kimi>  (same 9router key for all four)"
if [ "$AUTO_SWITCHED" -eq 1 ]; then
  echo "   2. Activate:        already done above (claude profile applied to settings.json)"
else
  echo "   2. Activate:        source $SHELL_RC && ccswitch claude   (or: codex / deepseek / kimi)"
fi
echo "   3. Restart Claude Code (quit + reopen) to load the new env."
echo "   4. Parallel:        open 4 terminals → claude-cc / claude-cx / claude-ds / claude-km"
echo "                       (4 vendors at once — all four share 9router quota; force-subscription Kimi uses its own Moonshot key)"
