#!/usr/bin/env bash
# Multi-account Gemini OAuth manager.
# Usage:
#   gemini-account.sh save <email>           snapshot current oauth_creds
#   gemini-account.sh use <email>            switch active account
#   gemini-account.sh list                   table of accounts + cooldown status
#   gemini-account.sh cooldown <email> <sec> set cooldown duration
#   gemini-account.sh clear-cooldown <email> remove cooldown
#   gemini-account.sh next                   print next available (non-cooling)
#   gemini-account.sh current                print active email
set -euo pipefail

ACCOUNTS_DIR="$HOME/.gemini/accounts"
CONFIG_FILE="$ACCOUNTS_DIR/config.json"
STATE_FILE="$ACCOUNTS_DIR/state.json"
CREDS_FILE="$HOME/.gemini/oauth_creds.json"

DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$DIR/_common.sh" ]]; then
  # shellcheck source=_common.sh
  source "$DIR/_common.sh" 2>/dev/null || true
fi

log_msg() {
  if declare -f delegate_log >/dev/null 2>&1; then
    delegate_log "gemini-account" "$@"
  else
    printf '[gemini-account] %s\n' "$*" >&2
  fi
}

init_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p "$ACCOUNTS_DIR"
    printf '{"active":null,"cooldowns":{}}\n' > "$STATE_FILE"
  fi
}

get_active() {
  init_state
  jq -r '.active // empty' "$STATE_FILE" 2>/dev/null || echo ""
}

jq_update() {
  local file="$1" filter="$2"
  local tmp
  tmp=$(mktemp)
  jq "$filter" "$file" > "$tmp"
  mv "$tmp" "$file"
}

set_active() {
  local email="$1"
  init_state
  jq_update "$STATE_FILE" ".active = \"$email\""
}

list_accounts_ordered() {
  if [[ ! -d "$ACCOUNTS_DIR" ]]; then
    return
  fi

  local priority_list=()
  local has_config=0
  if [[ -f "$CONFIG_FILE" ]]; then
    has_config=1
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && priority_list+=("$line")
    done < <(jq -r '.priority[]? // empty' "$CONFIG_FILE" 2>/dev/null)
  fi

  local seen=()
  local result=()

  for email in "${priority_list[@]:-}"; do
    [[ -z "$email" ]] && continue
    if [[ -f "$ACCOUNTS_DIR/$email.json" ]]; then
      result+=("$email")
      seen+=("$email")
    fi
  done

  # If config.json has an explicit priority list, treat it as an allowlist —
  # do NOT append alphabetical remainder (that would re-enable disabled accounts).
  if [[ $has_config -eq 1 ]] && [[ ${#priority_list[@]} -gt 0 ]]; then
    printf '%s\n' "${result[@]:-}"
    return
  fi

  while IFS= read -r -d '' file; do
    local base email
    base="${file##*/}"
    email="${base%.json}"
    [[ "$email" == "config" || "$email" == "state" ]] && continue
    local skip=0
    for s in "${seen[@]:-}"; do
      [[ "$s" == "$email" ]] && skip=1 && break
    done
    [[ $skip -eq 0 ]] && result+=("$email")
  done < <(find "$ACCOUNTS_DIR" -maxdepth 1 -name "*.json" -print0 2>/dev/null | LC_ALL=C sort -z)

  printf '%s\n' "${result[@]:-}"
}

cmd_save() {
  local email="${1:-}"
  if [[ -z "$email" ]]; then
    log_msg "ERROR: save requires <email>"
    return 1
  fi
  if [[ ! -f "$CREDS_FILE" ]]; then
    log_msg "ERROR: oauth_creds.json not found at $CREDS_FILE"
    return 1
  fi

  local cred_email=""
  cred_email=$(jq -r '.id_token' "$CREDS_FILE" 2>/dev/null | \
    python3 -c "import sys,json,base64
try:
    tok=sys.stdin.read().strip()
    parts=tok.split('.')
    if len(parts) >= 2:
        pad=parts[1]+'='*(-len(parts[1])%4)
        print(json.loads(base64.urlsafe_b64decode(pad)).get('email',''))
except Exception:
    pass" 2>/dev/null || echo "")

  if [[ -z "$cred_email" ]]; then
    log_msg "WARNING: could not extract email from id_token; proceeding anyway"
  elif [[ "$cred_email" != "$email" ]]; then
    log_msg "ERROR: id_token email ($cred_email) does not match requested email ($email)"
    return 1
  fi

  mkdir -p "$ACCOUNTS_DIR"
  cp "$CREDS_FILE" "$ACCOUNTS_DIR/$email.json"
  chmod 600 "$ACCOUNTS_DIR/$email.json"
  log_msg "saved: $email"
}

cmd_use() {
  local email="${1:-}"
  if [[ -z "$email" ]]; then
    log_msg "ERROR: use requires <email>"
    return 1
  fi
  if [[ ! -f "$ACCOUNTS_DIR/$email.json" ]]; then
    log_msg "ERROR: account file not found: $ACCOUNTS_DIR/$email.json"
    return 1
  fi

  local tmp
  tmp=$(mktemp)
  cp "$ACCOUNTS_DIR/$email.json" "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CREDS_FILE"

  if [[ -f "$HOME/.gemini/google_accounts.json" ]]; then
    jq_update "$HOME/.gemini/google_accounts.json" ".active = \"$email\""
  fi

  set_active "$email"
  log_msg "active: $email"
}

cmd_current() {
  local active
  active=$(get_active)
  if [[ -z "$active" ]]; then
    log_msg "no active account"
    return 1
  fi
  echo "$active"
}

cmd_cooldown() {
  local email="${1:-}" secs="${2:-}"
  if [[ -z "$email" || -z "$secs" ]]; then
    log_msg "ERROR: cooldown requires <email> <seconds>"
    return 1
  fi
  init_state
  local now_ms
  now_ms=$(( $(date +%s) * 1000 ))
  local expire_ms=$(( now_ms + secs * 1000 ))
  jq_update "$STATE_FILE" ".cooldowns[\"$email\"] = $expire_ms"
  log_msg "cooldown set: $email expires in ${secs}s"
}

cmd_clear_cooldown() {
  local email="${1:-}"
  if [[ -z "$email" ]]; then
    log_msg "ERROR: clear-cooldown requires <email>"
    return 1
  fi
  init_state
  jq_update "$STATE_FILE" "del(.cooldowns[\"$email\"])"
  log_msg "cooldown cleared: $email"
}

cmd_next() {
  init_state
  local now_ms
  now_ms=$(( $(date +%s) * 1000 ))
  local cooldowns
  cooldowns=$(jq -c '.cooldowns // {}' "$STATE_FILE")

  while IFS= read -r email; do
    [[ -z "$email" ]] && continue
    local expire_ms
    expire_ms=$(echo "$cooldowns" | jq -r --arg e "$email" '.[$e] // 0')
    if [[ $expire_ms -le $now_ms ]]; then
      echo "$email"
      return 0
    fi
  done < <(list_accounts_ordered)

  return 1
}

cmd_list() {
  init_state
  local active
  active=$(get_active)
  local now_ms
  now_ms=$(( $(date +%s) * 1000 ))
  local cooldowns
  cooldowns=$(jq -c '.cooldowns // {}' "$STATE_FILE")

  printf '%-2s %-32s %-10s %-24s\n' "*" "EMAIL" "PRIORITY" "COOLDOWN"
  printf '%s\n' "----------------------------------------------------------------------"

  local rank=1
  local any=0
  while IFS= read -r email; do
    [[ -z "$email" ]] && continue
    any=1
    local expire_ms
    expire_ms=$(echo "$cooldowns" | jq -r --arg e "$email" '.[$e] // 0')
    local cooldown_str="ready"
    if [[ $expire_ms -gt $now_ms ]]; then
      local remaining_s=$(( (expire_ms - now_ms) / 1000 ))
      cooldown_str="${remaining_s}s remaining"
    fi
    local marker=" "
    [[ "$email" == "$active" ]] && marker="*"
    printf '%-2s %-32s %-10s %-24s\n' "$marker" "$email" "$rank" "$cooldown_str"
    (( rank++ ))
  done < <(list_accounts_ordered)

  if [[ $any -eq 0 ]]; then
    log_msg "no accounts found in $ACCOUNTS_DIR (use 'save <email>' first)"
  fi
}

if [[ $# -lt 1 ]]; then
  cat >&2 <<'EOF'
Usage: gemini-account.sh <command> [args]
  save <email>           snapshot current oauth_creds as <email>.json
  use <email>            switch active account (atomic)
  current                print active email
  list                   show all accounts with cooldown status
  cooldown <email> <sec> set cooldown
  clear-cooldown <email> remove cooldown
  next                   print next available (non-cooling) email
EOF
  exit 1
fi

cmd="$1"; shift || true
case "$cmd" in
  save)            cmd_save "$@" ;;
  use)             cmd_use "$@" ;;
  current)         cmd_current "$@" ;;
  list)            cmd_list "$@" ;;
  cooldown)        cmd_cooldown "$@" ;;
  clear-cooldown)  cmd_clear_cooldown "$@" ;;
  next)            cmd_next "$@" ;;
  *)               log_msg "ERROR: unknown command: $cmd"; exit 1 ;;
esac
