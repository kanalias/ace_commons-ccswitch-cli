#!/usr/bin/env bash
# ccswitch — swap Claude Code auth profile.
# Only replaces the `env` block in ~/.claude/settings.json; leaves everything else intact.
#
# Targets (priority order):
#   claude        (DEFAULT)  https://9router.proxy.example.com/v1  cc/* claude   — Claude via 9router
#   codex                    (same base)                      cx/* gpt      — Codex/GPT via 9router
#   deepseek                 (same base)                      ds/* deepseek — DeepSeek via 9router
#   kimi                     (same base)                      kimi/*       — Kimi via 9router
#   subscription             (no env block)                   — Claude Code OAuth login (safe-harbor)
#
# claude / codex / deepseek / kimi hit the SAME base URL through 9router; they differ ONLY in the
# ANTHROPIC_DEFAULT_*_MODEL block (model prefix cc/ vs cx/ vs ds/ vs kimi/) and SHARE ONE 9router
# key (fill the same token into all four router profiles). Router outage takes the 9router
# profiles down → fallback is `subscription`.
#
# `subscription` is NOT a profile file: it removes the env block so Claude Code falls back to its
# own OAuth subscription login. It needs no key and is never probed — it is the guaranteed terminal.
# Aliases (backward compat): original->subscription, direct->subscription, clear==subscription.
#
# Usage:
#   ccswitch                # show current target + router-family health + subscription note
#   ccswitch claude         # Claude via 9router (default)
#   ccswitch codex          # Codex/GPT via 9router (cx/* models)
#   ccswitch deepseek       # DeepSeek via 9router (ds/* models)
#   ccswitch kimi           # Kimi via 9router (kimi/* models)
#   ccswitch subscription   # remove env block -> Claude Code OAuth subscription
#   ccswitch spawn <target> # launch a SEPARATE Claude Code instance pinned to <target> via process
#                           #   env (settings.json untouched). Open N terminals + spawn N targets =
#                           #   N vendors running IN PARALLEL. NOTE: same 9router account = shared quota.
#   ccswitch check          # probe router health (all profiles) + verify subscription OAuth credential
#   ccswitch fallback       # active router profile if healthy, else fall back to subscription
#   ccswitch set-key [p]    # prompt (hidden) for a new key, write it into profile p (default claude), then apply
#   ccswitch set-host <url> [p]  # write a new base URL into profile p (default claude), then apply
#   ccswitch update [src]   # sync ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN from profile src (default
#                           #   claude) into the other profiles — asks [y/N] before overwriting
#   ccswitch install <name>  # run repo installer (proxy|auto-compact|optimize|harness)
#   ccswitch clear          # alias of subscription (remove env block)
#
# Every apply() to a router profile (claude/codex/deepseek/kimi/set-key/set-host/fallback) ends with
# ping_verify(): a real /v1/messages "Ping" request using the profile's own base URL + token,
# confirming the just-written env actually authenticates end-to-end (probe() only checks /models).
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
PROFILES="$CLAUDE_DIR/profiles"

# real profile files; subscription is env-clear, not a file.
ORDER=(claude codex deepseek kimi)

die() { echo "❌ $*" >&2; exit 1; }

# resolve alias -> canonical target name
canon() {
  case "$1" in
    original|direct|clear) echo subscription ;;
    *)                     echo "$1" ;;
  esac
}

# probe a router profile's /models endpoint; echoes http code.
# Only the router is a probeable HTTP endpoint — subscription (OAuth) has no URL to probe.
probe() {
  local prof="$PROFILES/$1.json"
  [ -f "$prof" ] || { echo "000"; return; }
  local base tok
  base=$(jq -r '.ANTHROPIC_BASE_URL // empty' "$prof" 2>/dev/null || true)
  tok=$(jq -r '.ANTHROPIC_AUTH_TOKEN // empty' "$prof" 2>/dev/null || true)
  [ -n "$base" ] || { echo "000"; return; }
  # Moonshot (kimi force-subscription) splits its endpoint layout: Anthropic messages live
  # under /anthropic/v1, but the models list lives at the root /v1/models — NOT under
  # /anthropic. Router bases already end in /v1, so <base>/models is correct there.
  local models_url
  case "$base" in
    *moonshot.ai*) models_url="https://api.moonshot.ai/v1/models" ;;
    *)             models_url="${base%/}/models" ;;
  esac
  local code
  code=$(curl -s -m 4 "$models_url" \
    ${tok:+-H "Authorization: Bearer $tok"} \
    -o /dev/null -w "%{http_code}" 2>/dev/null)
  [ -n "$code" ] && echo "$code" || echo "000"
}

# Resolve which layer wins per Claude Code's precedence (MECHANISM §2):
#   ① process env         (exported before `claude` launched)      — beats everything
#   ② settings.local.json .env  (project-scoped, gitignored)
#   ③ settings.json       .env  (global ~/.claude, ccswitch-managed)
#   ④ (none)              → Claude Code OAuth subscription login
# Prints the effective source + base URL, then lists the other layers for context.
current() {
  local pe_url="${ANTHROPIC_BASE_URL:-}"
  local pe_model="${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
  local local_settings="$CLAUDE_DIR/settings.local.json"
  local sl_url="" sg_url="" sl_model="" sg_model=""
  if [ -f "$local_settings" ]; then
    sl_url=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$local_settings" 2>/dev/null || true)
    sl_model=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL // empty' "$local_settings" 2>/dev/null || true)
  fi
  sg_url=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$SETTINGS" 2>/dev/null || true)
  sg_model=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL // empty' "$SETTINGS" 2>/dev/null || true)

  # tag (url, model) as a known target name. The router profiles share one base URL (9router),
  # so the model prefix (cc/ vs cx/ vs ds/ vs kimi/) is what tells them apart.
  tag() {
    local url="$1" model="$2"
    case "$url" in
      *9router.proxy.example.com*)
        case "$model" in
          cx/*) echo "codex" ;;
          ds/*) echo "deepseek" ;;
          cc/*) echo "claude" ;;
          kimi*) echo "kimi" ;;
          *)    echo "claude" ;;
        esac ;;
      "") echo "subscription" ;;
      *)  echo "custom" ;;
    esac
  }

  echo "── effective source (Claude Code precedence §2) ──"
  if [ -n "$pe_url" ]; then
    echo "▶ ① PROCESS ENV  →  $(tag "$pe_url" "$pe_model") ($pe_url${pe_model:+, $pe_model})"
    echo "     ⚠ env đã export đè mọi file settings; ccswitch sửa settings sẽ KHÔNG có tác dụng đến khi restart Claude Code với env sạch."
  elif [ -n "$sl_url" ]; then
    echo "▶ ② settings.local.json  →  $(tag "$sl_url" "$sl_model") ($sl_url${sl_model:+, $sl_model})"
  elif [ -n "$sg_url" ]; then
    echo "▶ ③ settings.json  →  $(tag "$sg_url" "$sg_model") ($sg_url${sg_model:+, $sg_model})"
  else
    echo "▶ ④ subscription (no env block anywhere) → Claude Code OAuth login"
  fi
  echo "     (caveat: ① chỉ thấy được nếu ccswitch chạy trong shell có sẵn biến; Claude Code process thật có thể khác — verify: env | grep ANTHROPIC_BASE_URL)"

  echo "── các tầng khác ──"
  echo "  ① process env         : ${pe_url:-(unset)}${pe_model:+  [$pe_model]}"
  echo "  ② settings.local.json : ${sl_url:-(no env block)}${sl_model:+  [$sl_model]}"
  echo "  ③ settings.json       : ${sg_url:-(no env block → subscription)}${sg_model:+  [$sg_model]}"
}

# Verify the subscription safe-harbor: subscription is env-clear (no URL to probe), but it only
# actually rescues Claude when the machine has an OAuth login (§6). We can check for that credential:
#   mac   -> Keychain service "Claude Code-credentials"
#   linux -> ~/.claude/.credentials.json
# Account email + subscriptionType come from ~/.claude.json (oauthAccount) when present.
# Echoes a one-line status; never prints tokens.
probe_subscription() {
  local cred="" src=""
  if command -v security >/dev/null 2>&1; then
    cred=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
    [ -n "$cred" ] && src="keychain"
  fi
  if [ -z "$cred" ]; then
    for f in "$CLAUDE_DIR/.credentials.json" "$CLAUDE_DIR/credentials.json"; do
      [ -f "$f" ] && { cred=$(cat "$f" 2>/dev/null); src="file"; break; }
    done
  fi

  if [ -z "$cred" ]; then
    echo "✗ NO OAuth credential — safe-harbor will prompt login on first use (run 'claude' + login)"
    return
  fi

  # credential present: try to surface subscriptionType (from cred) + account (from ~/.claude.json)
  local sub acct
  sub=$(printf '%s' "$cred" | jq -r '.claudeAiOauth.subscriptionType // empty' 2>/dev/null || true)
  acct=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null || true)
  local detail=""
  [ -n "$acct" ] && detail="$acct"
  [ -n "$sub" ] && detail="${detail:+$detail, }$sub"
  echo "✓ logged in${detail:+ ($detail)} [$src] → safe-harbor OK"
}

# remove the env block -> Claude Code reverts to its own OAuth subscription login.
clear_env() {
  [ -f "$SETTINGS" ] || die "settings not found: $SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak"
  jq 'del(.env)' "$SETTINGS.bak" > "$SETTINGS.tmp" \
    || die "jq del failed (settings unchanged, see $SETTINGS.bak)"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "✅ switched to 'subscription' — removed env block (backup: $SETTINGS.bak)."
  echo "   Claude Code will use its OAuth subscription login (run 'claude' + login if needed)."
  echo "↻ restart Claude Code (quit + reopen) to load new env."
}

apply() {
  local name; name=$(canon "$1")
  # subscription is not a profile file — it is the absence of an env block.
  if [ "$name" = "subscription" ]; then clear_env; return; fi
  local prof="$PROFILES/$name.json"
  [ -f "$prof" ] || die "profile not found: $prof"
  [ -f "$SETTINGS" ] || die "settings not found: $SETTINGS"
  jq empty "$prof" 2>/dev/null || die "profile $prof is not valid JSON"
  cp "$SETTINGS" "$SETTINGS.bak"
  jq --slurpfile e "$prof" '.env = $e[0]' "$SETTINGS.bak" > "$SETTINGS.tmp" \
    || die "jq merge failed (settings unchanged, see $SETTINGS.bak)"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "✅ switched to '$name' profile (backup: $SETTINGS.bak)"
  echo "↻ restart Claude Code (quit + reopen) to load new env."
  ping_verify "$prof"
}

# ping_verify <profile-json> — send a real "Ping" chat completion to /v1/messages using the
# profile's own base URL + token + haiku model (cheapest tier), to prove the just-applied
# env actually authenticates end-to-end — not just that the endpoint is up (probe() only
# checks /models). Never prints the token; redacts it even from curl -v style diagnostics.
ping_verify() {
  local prof="$1"
  local base tok model
  base=$(jq -r '.ANTHROPIC_BASE_URL // empty' "$prof" 2>/dev/null || true)
  tok=$(jq -r '.ANTHROPIC_AUTH_TOKEN // empty' "$prof" 2>/dev/null || true)
  model=$(jq -r '.ANTHROPIC_DEFAULT_HAIKU_MODEL // .ANTHROPIC_DEFAULT_SONNET_MODEL // empty' "$prof" 2>/dev/null || true)
  if [ -z "$base" ] || [ -z "$tok" ] || [ -z "$model" ]; then
    echo "⏭  ping skipped: profile missing base URL / token / model"
    return
  fi

  # Build the messages URL the same way the real client does, per target shape:
  #   router base ends in /v1  → messages at <base>/messages   (e.g. .../v1/messages)
  #   kimi base is .../anthropic → messages at <base>/v1/messages (Moonshot's Anthropic
  #     endpoint; base deliberately omits /v1 because Claude Code appends /v1/messages).
  local msg_url
  case "$base" in
    *moonshot.ai*) msg_url="${base%/}/v1/messages" ;;
    *)             msg_url="${base%/}/messages" ;;
  esac
  echo "📡 pinging '$model' via $msg_url …"
  local body http_code text tmp_resp
  tmp_resp=$(mktemp) || { echo "⏭  ping skipped: mktemp failed"; return; }
  body=$(jq -n --arg m "$model" '{model:$m, max_tokens:16, messages:[{role:"user",content:"Ping"}]}')
  # `|| true`: curl exits nonzero on an unreachable host (e.g. 6 DNS fail). Under
  # `set -e` that would abort the whole switch — but the local settings.json write
  # already succeeded. Ping is a diagnostic, not a gate: swallow curl's exit, keep
  # the "%{http_code}" (000 on failure) and let the HTTP-code branch below report.
  http_code=$(curl -s -m 15 "$msg_url" \
    -H "Authorization: Bearer $tok" \
    -H "content-type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "$body" \
    -o "$tmp_resp" -w "%{http_code}" 2>/dev/null || true)

  if [ "$http_code" = "200" ]; then
    text=$(jq -r '.content[0].text // empty' "$tmp_resp" 2>/dev/null || true)
    echo "✅ ping OK (HTTP 200) — reply: ${text:-<empty>}"
  else
    echo "❌ ping FAILED (HTTP $http_code) — env may not actually be usable; check key/host"
  fi
  rm -f "$tmp_resp"
}

# which router profile is currently applied? echoes claude|codex|deepseek|kimi (default claude)
# by reading the active model prefix from settings.json. Used by `fallback`.
active_router_profile() {
  local m
  m=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL // empty' "$SETTINGS" 2>/dev/null || true)
  case "$m" in
    cx/*) echo codex ;;
    ds/*) echo deepseek ;;
    kimi*) echo kimi ;;
    *)    echo claude ;;
  esac
}

# set-key [profile] — prompt (hidden) for a new key, write it into the profile, then apply.
# claude/codex/deepseek/kimi share ONE 9router key — fill the same token into all four router
# profiles. subscription is env-clear (rejected below).
set_key() {
  local name; name=$(canon "${1:-claude}")
  [ "$name" = "subscription" ] && \
    die "subscription uses Claude Code's OAuth login — no key to set. Run: ccswitch subscription, then 'claude' + login."
  local prof="$PROFILES/$name.json"
  [ -f "$prof" ] || die "profile not found: $prof (run setup first)"
  jq empty "$prof" 2>/dev/null || die "profile $prof is not valid JSON"

  local field="ANTHROPIC_AUTH_TOKEN"

  [ -t 0 ] || die "set-key needs an interactive terminal (no TTY)."
  local key
  printf "▸ Paste new key for '%s' → %s (input hidden): " "$name" "$field"
  read -rs key; echo
  [ -n "$key" ] || die "no key entered — profile unchanged."

  cp "$prof" "$prof.bak"
  jq --arg f "$field" --arg k "$key" '.[$f] = $k' "$prof" > "$prof.tmp" \
    && mv "$prof.tmp" "$prof" \
    || { rm -f "$prof.tmp"; die "failed to write key (profile unchanged, see $prof.bak)"; }
  unset key
  echo "✅ key updated in profiles/$name.json (backup: $prof.bak)"
  apply "$name"
}

# set-host <url> [profile] — write a new ANTHROPIC_BASE_URL directly into the profile, then apply.
# URL is a required positional arg (not prompted): unlike a key, a base URL isn't a secret,
# so it's safe to pass on the command line / have it sit in shell history.
set_host() {
  local host="${1:-}"
  [ -n "$host" ] || die "usage: ccswitch set-host <url> [profile]"
  local name; name=$(canon "${2:-claude}")
  [ "$name" = "subscription" ] && \
    die "subscription uses Claude Code's OAuth login — no host to set."
  local prof="$PROFILES/$name.json"
  [ -f "$prof" ] || die "profile not found: $prof (run setup first)"
  jq empty "$prof" 2>/dev/null || die "profile $prof is not valid JSON"

  local field="ANTHROPIC_BASE_URL"

  cp "$prof" "$prof.bak"
  jq --arg f "$field" --arg u "$host" '.[$f] = $u' "$prof" > "$prof.tmp" \
    && mv "$prof.tmp" "$prof" \
    || { rm -f "$prof.tmp"; die "failed to write host (profile unchanged, see $prof.bak)"; }
  echo "✅ host updated in profiles/$name.json (backup: $prof.bak)"
  apply "$name"
}

# update [src] — sync ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN from router profile `src` (default claude)
# into the other router profiles. Only these two fields are copied — model-prefix fields
# (ANTHROPIC_DEFAULT_*_MODEL) stay untouched, since that's what makes claude/codex/deepseek/kimi
# distinct despite sharing one 9router host+token. Asks [y/N].
update_profiles() {
  local src; src=$(canon "${1:-claude}")
  [ "$src" = "subscription" ] && die "subscription has no host/key to copy from."
  case "$src" in claude|codex|deepseek|kimi) ;; *) die "update only syncs router profiles (claude|codex|deepseek|kimi)." ;; esac
  local src_prof="$PROFILES/$src.json"
  [ -f "$src_prof" ] || die "profile not found: $src_prof"
  jq empty "$src_prof" 2>/dev/null || die "profile $src_prof is not valid JSON"

  local base tok
  base=$(jq -r '.ANTHROPIC_BASE_URL // empty' "$src_prof" 2>/dev/null || true)
  tok=$(jq -r '.ANTHROPIC_AUTH_TOKEN // empty' "$src_prof" 2>/dev/null || true)
  [ -n "$base" ] || die "profile $src_prof has no ANTHROPIC_BASE_URL to copy."
  [ -n "$tok" ] || die "profile $src_prof has no ANTHROPIC_AUTH_TOKEN to copy."
  [ -t 0 ] || die "update needs an interactive terminal to confirm overwrites (no TTY)."

  local updated=0
  for p in claude codex deepseek kimi; do
    [ "$p" = "$src" ] && continue
    local dst="$PROFILES/$p.json"
    [ -f "$dst" ] || { echo "  • profiles/$p.json not found — skipped"; continue; }
    printf "  overwrite host+key in profiles/%s.json from '%s'? [y/N] " "$p" "$src"
    local ans; read -r ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "    skipped $p."; continue ;;
    esac
    cp "$dst" "$dst.bak"
    jq --arg u "$base" --arg k "$tok" \
      '.ANTHROPIC_BASE_URL = $u | .ANTHROPIC_AUTH_TOKEN = $k' "$dst.bak" > "$dst.tmp" \
      && mv "$dst.tmp" "$dst" \
      || { rm -f "$dst.tmp"; echo "  ❌ failed to update profiles/$p.json (unchanged, see $dst.bak)"; continue; }
    updated=$((updated + 1))
    echo "  ✓ profiles/$p.json synced from '$src' (backup: $dst.bak)"
  done
  [ "$updated" -gt 0 ] || { echo "no profiles updated."; return; }
  echo "✅ synced host+key from '$src' into $updated profile(s)."
}

# spawn <target> [claude-args…] — launch a SEPARATE Claude Code instance pinned to <target>
# via PROCESS ENV (precedence tier ①, MECHANISM §2), leaving ~/.claude/settings.json untouched.
# Open N terminals + spawn N different targets = N vendors running IN PARALLEL — the only way
# to have >1 vendor active at once (a single instance reads one env → one model).
# subscription is env-clear (no profile to export) → rejected; use `ccswitch subscription` + plain `claude`.
# NOTE: claude/codex/deepseek/kimi share one 9router quota.
spawn() {
  local name; name=$(canon "${1:-claude}")
  [ "$name" = "subscription" ] && \
    die "spawn needs a real router target (claude|codex|deepseek|kimi). subscription is env-clear — run: ccswitch subscription, then plain 'claude'."
  local prof="$PROFILES/$name.json"
  [ -f "$prof" ] || die "profile not found: $prof (run setup first)"
  jq empty "$prof" 2>/dev/null || die "profile $prof is not valid JSON"

  local c; c=$(probe "$name")
  [ "$c" = "200" ] || echo "⚠️  '$name' health=$c (not 200) — spawning anyway, may be down"

  # export every field from the profile into this shell's env, then exec claude.
  local k v
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] && export "$k=$v"
  done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$prof")

  # distinguish the terminal so parallel windows are readable
  printf '\033]0;claude:%s\007' "$name"

  # resolve the real binary (user may have a stale `claude` alias — don't rely on it)
  local bin; bin=$(command -v claude 2>/dev/null || true)
  [ -n "$bin" ] || bin="$HOME/.local/bin/claude"
  [ -x "$bin" ] || die "claude binary not found (looked at: command -v claude, ~/.local/bin/claude)"

  echo "▶ spawning claude pinned to '$name' (process env only — settings.json untouched)"
  exec "$bin" "${@:2}"
}

# resolve_repo — find the ccswitch-cli-claude repo root so `ccswitch install <name>` can run
# a repo installer script from anywhere. `ccswitch.sh` itself is a standalone copy in
# ~/.claude (setup.sh `cp`s it, no symlink) so it has no built-in idea where the repo lives —
# setup.sh records the path at install time into ~/.claude/.ccswitch-repo.
resolve_repo() {
  if [ -f "$CLAUDE_DIR/.ccswitch-repo" ]; then
    local repo; repo=$(cat "$CLAUDE_DIR/.ccswitch-repo" 2>/dev/null || true)
    if [ -n "$repo" ] && [ -f "$repo/install-9router-proxy.sh" ]; then
      echo "$repo"; return
    fi
  fi
  if [ -f "$PWD/install-9router-proxy.sh" ]; then
    echo "$PWD"; return
  fi
  die "repo root chưa biết — chạy lại setup: bash <repo>/install-9router-proxy.sh (ghi lại ~/.claude/.ccswitch-repo)"
}

case "${1:-status}" in
  claude|codex|deepseek|kimi)
    # all are profile files routing through 9router (differ only by model prefix).
    t="$1"
    c=$(probe "$t")
    [ "$c" = "200" ] || echo "⚠️  '$t' health=$c (not 200) — switching anyway, may be down"
    apply "$t" ;;
  subscription|original|direct|clear)
    # all resolve to subscription (env-clear -> Claude Code OAuth login)
    apply subscription ;;
  check)
    for p in "${ORDER[@]}"; do
      c=$(probe "$p"); echo "  $p: $c $([ "$c" = 200 ] && echo OK || echo DOWN)"
    done
    echo "  subscription: $(probe_subscription)" ;;
  fallback)
    # Keep the currently-active router profile if healthy (don't force claude when the user is on
    # deepseek). Resolve active target from settings.json's model prefix; default claude.
    # `subscription` is the guaranteed SAFE-HARBOR terminal: removes the env block so Claude Code
    # uses its own OAuth login — always reachable, no key/probe. Claude never stays stuck on a
    # dead router. All profiles share one router, so a router outage means subscription.
    t=$(active_router_profile)
    c=$(probe "$t")
    if [ "$c" = "200" ]; then echo "→ router healthy: $t"; apply "$t"; exit 0; fi
    echo "  $t down ($c) → safe-harbor: subscription (OAuth)"
    apply subscription ;;
  spawn)
    # launch a separate instance pinned to the target via process env (settings.json untouched);
    # forward any remaining args to claude. Open multiple terminals to run vendors in parallel.
    spawn "${2:-claude}" "${@:3}" ;;
  set-key)
    set_key "${2:-claude}" ;;
  set-host)
    set_host "${2:-}" "${3:-claude}" ;;
  update)
    update_profiles "${2:-claude}" ;;
  install)
    sub="${2:-}"
    case "$sub" in
      proxy|first-time|auto-compact|optimize|harness) repo=$(resolve_repo) ;;
    esac
    case "$sub" in
      # first-time = alias of proxy: same setup, clearer name for the initial bootstrap.
      proxy|first-time) exec bash "$repo/install-9router-proxy.sh" "${@:3}" ;;
      auto-compact) exec bash "$repo/install-auto-compact.sh" "${@:3}" ;;
      optimize)     exec bash "$repo/install-optimize-claude.sh" "${@:3}" ;;
      harness)      exec bash "$repo/install-harness.sh" "${@:3}" ;;
      ""|list)
        cat <<'EOF'
ccswitch install <name> — chạy script cài đặt của repo (từ mọi nơi sau khi đã setup)
  first-time    bootstrap lần đầu = proxy (lần đầu thật phải: bash install-first-time.sh)
  proxy         cài lại 9router proxy + profiles (OS-detect)
  auto-compact  chỉnh mốc auto-compact của Claude Code
  optimize      tắt feature Claude Code để giảm context window
  harness [dir] cài orchestrator+delegate harness sang project khác
EOF
        ;;
      *) die "unknown: ccswitch install {first-time|proxy|auto-compact|optimize|harness}" ;;
    esac ;;
  help|--help|-h)
    cat <<'EOF'
ccswitch — swap Claude Code auth (edits only the `env` block in ~/.claude/settings.json)

USAGE
  ccswitch [command]

TARGETS (switch-in-place; RESTART Claude Code after — env loads at launch)
  claude              Claude via 9router          (cc/* models)   ⭐ default
  codex               Codex/GPT via 9router       (cx/* models)
  deepseek            DeepSeek via 9router         (ds/* models)
  kimi                Kimi via 9router             (kimi/* models)
  subscription        remove env block → Claude Code OAuth login  (safe-harbor, no key)
                      aliases: original | direct | clear

  every apply (claude|codex|deepseek|kimi|set-key|set-host|fallback) sends a REAL "Ping" chat
  request to the profile's own base URL + token, proving the env is actually usable —
  not just that the endpoint responds to /models.

  claude + codex + deepseek + kimi share ONE 9router base URL AND ONE token
  (fill the same key into all four profiles). Router down → all down → subscription.

COMMANDS
  status  (default)   show active target (by model prefix) + health + subscription
  check               probe health of every router profile + verify subscription
  fallback            keep active router if healthy, else drop to subscription
  spawn <target> [..] launch a SEPARATE pinned instance (settings.json untouched)
  set-key [profile]   paste a key (hidden) into a profile, then apply  (default: claude)
  set-host <url> [p]  write a base URL into a profile, then apply      (default: claude)
  update [src]        sync host+key from profile src into the others  (default: claude)
                      asks [y/N] before overwriting each target profile
  help | -h           this help

KEYS
  ccswitch set-key claude       # then: set-key codex, set-key deepseek, set-key kimi with the SAME token
  ccswitch set-host https://9router.proxy.example.com/v1 claude   # then: same URL for codex, deepseek, kimi
  ccswitch update claude        # or just re-sync: copies claude's host+key into codex + deepseek + kimi
  profiles live at ~/.claude/profiles/*.json  (local, never committed)

INSTALL (chạy script cài đặt của repo — mọi nơi sau khi setup)
  install first-time     bootstrap = proxy (lần đầu thật: bash install-first-time.sh)
  install proxy          cài lại 9router proxy + profiles
  install auto-compact   chỉnh mốc auto-compact
  install optimize       tắt feature giảm context
  install harness [dir]  cài harness sang project khác
  install                (không arg) liệt kê option trên
EOF
    exit 0 ;;
  status|"")
    current
    for p in "${ORDER[@]}"; do
      c=$(probe "$p"); echo "  $p: $c $([ "$c" = 200 ] && echo OK || echo DOWN)"
    done
    echo "  subscription: $(probe_subscription)"
    echo "profiles: $(ls "$PROFILES" 2>/dev/null | sed 's/\.json//' | tr '\n' ' ')" ;;
  *)
    die "usage: ccswitch [claude|codex|deepseek|kimi|subscription|spawn <target>|check|fallback|set-key [profile]|set-host <url> [profile]|update [src]|install <name>|clear|status|help]" ;;
esac
