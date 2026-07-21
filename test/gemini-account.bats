#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/scripts/delegate/gemini-account.sh"
}

@test "gemini-account: no command shows usage" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage"* ]]
  [[ "$output" == *"save"* ]]
}

@test "gemini-account: unknown command errors" {
  run bash "$SCRIPT" badcmd
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "gemini-account: save requires email" {
  run bash "$SCRIPT" save
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "gemini-account: save errors if oauth_creds.json missing" {
  run bash "$SCRIPT" save test@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "gemini-account: save snapshots valid oauth_creds.json to email.json" {
  mkdir -p "$HOME/.gemini"
  id_token=$(python3 -c "
import json, base64
header = json.dumps({'alg': 'RS256'})
payload = json.dumps({'email': 'test@example.com'})
sig = 'fake'
encoded = base64.urlsafe_b64encode(header.encode()).decode().rstrip('=')
encoded += '.' + base64.urlsafe_b64encode(payload.encode()).decode().rstrip('=')
encoded += '.' + sig
print(encoded)
  ")
  jq -n --arg tok "$id_token" '{id_token: $tok, access_token: "fake-access"}' > "$HOME/.gemini/oauth_creds.json"
  
  run bash "$SCRIPT" save test@example.com
  [ "$status" -eq 0 ]
  [ -f "$HOME/.gemini/accounts/test@example.com.json" ]
}

@test "gemini-account: use requires email" {
  run bash "$SCRIPT" use
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "gemini-account: use sets active email in state.json" {
  mkdir -p "$HOME/.gemini/accounts"
  echo '{}' > "$HOME/.gemini/accounts/acc1@test.com.json"
  echo '{}' > "$HOME/.gemini/accounts/acc2@test.com.json"
  
  run bash "$SCRIPT" use acc1@test.com
  [ "$status" -eq 0 ]
  active=$(jq -r '.active' "$HOME/.gemini/accounts/state.json")
  [ "$active" = "acc1@test.com" ]
}

@test "gemini-account: use nonexistent email errors" {
  mkdir -p "$HOME/.gemini/accounts"
  run bash "$SCRIPT" use nonexist@test.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "gemini-account: current prints active email" {
  mkdir -p "$HOME/.gemini/accounts"
  echo '{}' > "$HOME/.gemini/accounts/test@example.com.json"
  bash "$SCRIPT" use test@example.com >/dev/null
  
  run bash "$SCRIPT" current
  [ "$status" -eq 0 ]
  [[ "$output" == *"test@example.com"* ]]
}

@test "gemini-account: current errors when no active set" {
  run bash "$SCRIPT" current
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]] || [[ "$output" == *"no active"* ]]
}

@test "gemini-account: list shows all accounts" {
  mkdir -p "$HOME/.gemini/accounts"
  echo '{}' > "$HOME/.gemini/accounts/acc1@test.com.json"
  echo '{}' > "$HOME/.gemini/accounts/acc2@test.com.json"
  
  run bash "$SCRIPT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"acc1@test.com"* ]]
  [[ "$output" == *"acc2@test.com"* ]]
}

@test "gemini-account: list shows no accounts when dir empty" {
  mkdir -p "$HOME/.gemini/accounts"
  run bash "$SCRIPT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no accounts"* ]] || [[ "$output" == *"found"* ]]
}

@test "gemini-account: cooldown requires email and seconds" {
  run bash "$SCRIPT" cooldown
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "gemini-account: cooldown sets expiry time in state.json" {
  mkdir -p "$HOME/.gemini/accounts"
  
  run bash "$SCRIPT" cooldown test@example.com 60
  [ "$status" -eq 0 ]
  expiry=$(jq -r '.cooldowns["test@example.com"]' "$HOME/.gemini/accounts/state.json")
  [ "$expiry" != "null" ]
  [ "$expiry" -gt 0 ]
}

@test "gemini-account: clear-cooldown requires email" {
  run bash "$SCRIPT" clear-cooldown
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "gemini-account: clear-cooldown removes cooldown entry" {
  mkdir -p "$HOME/.gemini/accounts"
  bash "$SCRIPT" cooldown test@example.com 60 >/dev/null
  
  run bash "$SCRIPT" clear-cooldown test@example.com
  [ "$status" -eq 0 ]
  expiry=$(jq -r '.cooldowns["test@example.com"] // "null"' "$HOME/.gemini/accounts/state.json")
  [ "$expiry" = "null" ]
}

@test "gemini-account: next returns first account without cooldown" {
  mkdir -p "$HOME/.gemini/accounts"
  echo '{}' > "$HOME/.gemini/accounts/acc1@test.com.json"
  echo '{}' > "$HOME/.gemini/accounts/acc2@test.com.json"
  
  bash "$SCRIPT" cooldown acc1@test.com 60 >/dev/null
  
  run bash "$SCRIPT" next
  [ "$status" -eq 0 ]
  [[ "$output" == *"acc2@test.com"* ]]
}

@test "gemini-account: next errors when all accounts cooling" {
  mkdir -p "$HOME/.gemini/accounts"
  echo '{}' > "$HOME/.gemini/accounts/acc1@test.com.json"
  echo '{}' > "$HOME/.gemini/accounts/acc2@test.com.json"
  
  bash "$SCRIPT" cooldown acc1@test.com 60 >/dev/null
  bash "$SCRIPT" cooldown acc2@test.com 60 >/dev/null
  
  run bash "$SCRIPT" next
  [ "$status" -ne 0 ]
}

@test "gemini-account: state.json initialized with active=null, cooldowns={}" {
  [ ! -d "$HOME/.gemini/accounts" ]
  bash "$SCRIPT" current 2>/dev/null || true
  [ -f "$HOME/.gemini/accounts/state.json" ]
  active=$(jq -r '.active' "$HOME/.gemini/accounts/state.json")
  [ "$active" = "null" ] || [ -z "$active" ]
}
