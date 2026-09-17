#!/usr/bin/env bash
# Probe Gemini CLI for the highest-tier model currently available on this account.
# Stable-first ranking: prefer `gemini-3-pro` > `gemini-2.5-pro` > flash variants.
# Caches result in ~/.gemini/highest-model.cache for 24h to avoid per-call latency.
#
# Usage:  highest=$(probe-gemini-highest.sh)   # prints model id to stdout
# Force:  probe-gemini-highest.sh --force      # bypass cache
# Fallback: prints "gemini-2.5-pro" if probe fails entirely.
set -euo pipefail

CACHE="${HOME}/.gemini/highest-model.cache"
TTL_SEC=86400  # 24h
FALLBACK="gemini-2.5-pro"

# Stable-first rank: index 0 = highest priority. Add new tiers at the top as Google ships them.
# Within same major+tier: stable (no suffix) before -latest before -exp/-preview/-002.
CANDIDATES=(
  "gemini-3-pro"
  "gemini-3-flash"
  "gemini-2.5-pro"
  "gemini-2.5-pro-latest"
  "gemini-2.5-flash"
  "gemini-2.0-pro"
  "gemini-2.0-flash"
)

force=0
[[ "${1:-}" == "--force" ]] && force=1

# Cache hit + fresh → reuse.
if [[ $force -eq 0 && -f "$CACHE" ]]; then
  # macOS stat: -f %m → mtime in epoch seconds.
  mtime=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$((now - mtime))
  if [[ $age -lt $TTL_SEC ]]; then
    cached=$(head -n1 "$CACHE" 2>/dev/null || true)
    if [[ -n "$cached" ]]; then
      echo "$cached"
      exit 0
    fi
  fi
fi

# Force OAuth path during probe (regardless of caller env).
unset GOOGLE_API_KEY GEMINI_API_KEY 2>/dev/null || true

# Probe each candidate; pick first that returns non-error.
picked=""
for m in "${CANDIDATES[@]}"; do
  # Tiny prompt, 5s timeout per try via `gemini` itself (no portable timeout w/o brew coreutils).
  resp=$(printf "1" | gemini -p - -m "$m" 2>&1 | tail -3 || true)
  if echo "$resp" | grep -qiE "error|404|critical|invalid"; then
    continue
  fi
  picked="$m"
  break
done

# Fallback if nothing matched.
[[ -z "$picked" ]] && picked="$FALLBACK"

# Write cache atomically.
mkdir -p "$(dirname "$CACHE")"
printf '%s\n' "$picked" > "${CACHE}.tmp"
mv "${CACHE}.tmp" "$CACHE"

echo "$picked"
