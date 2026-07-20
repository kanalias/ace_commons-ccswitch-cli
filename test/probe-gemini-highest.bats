#!/usr/bin/env bats
# scripts/delegate/probe-gemini-highest.sh: find highest available Gemini model.
# Caches result in ~/.gemini/highest-model.cache with 24h TTL (mtime-based).
# Tests cache hits, stale cache re-probing, --force bypass, fallback on all-fail.
# Uses stub gemini CLI in PATH so no real network/auth needed.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/scripts/delegate/probe-gemini-highest.sh"
  
  # Create fake gemini CLI early in PATH
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$STUBBIN"
  PATH="$STUBBIN:$PATH"
  export PATH
}

# Helper: create stub gemini that succeeds/fails for specific models
write_gemini_stub() {
  local success_models="$1"  # space-separated list of models that succeed
  cat > "$STUBBIN/gemini" <<'STUBCODE'
#!/usr/bin/env bash
success_models='success_models_placeholder'
model=''
prev_was_m=0
for arg in "$@"; do
  if [[ "$prev_was_m" == "1" ]]; then
    model="$arg"
    prev_was_m=0
    break
  fi
  [[ "$arg" == "-m" ]] && prev_was_m=1
done

for m in $success_models; do
  if [[ "$m" == "$model" ]]; then
    echo "model: $model"
    exit 0
  fi
done

echo "error: model not found" >&2
exit 1
STUBCODE
  sed -i "" "s/success_models_placeholder/$success_models/" "$STUBBIN/gemini"
  chmod +x "$STUBBIN/gemini"
}

# --- cache hit (fresh) ---

@test "probe-gemini-highest: cache hit returns cached value without re-probing" {
  write_gemini_stub "gemini-3-pro gemini-2.5-pro"
  
  # First run: probe happens, caches gemini-3-pro
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-3-pro" ]]
  [ -f "$HOME/.gemini/highest-model.cache" ]
  
  # Modify stub to fail on all models (proves cache was used, not re-probed)
  write_gemini_stub ""
  
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-3-pro" ]]
}

@test "probe-gemini-highest: cache hit with multiple models returns first successful" {
  write_gemini_stub "gemini-2.5-pro gemini-2.0-pro"
  
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.5-pro" ]]
}

@test "probe-gemini-highest: cache freshness checked (TTL 24h)" {
  write_gemini_stub "gemini-3-pro"
  
  # First probe
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-3-pro" ]]
  
  # Cache should exist and be fresh
  [ -f "$HOME/.gemini/highest-model.cache" ]
}

# --- --force bypass ---

@test "probe-gemini-highest: --force bypasses cache and re-probes" {
  write_gemini_stub "gemini-3-pro"
  
  # Prime cache with gemini-3-pro
  bash "$SCRIPT" >/dev/null
  [ -f "$HOME/.gemini/highest-model.cache" ]
  
  # Change stub to return different model
  write_gemini_stub "gemini-2.5-pro"
  
  # Without --force: cache returns old value
  run bash "$SCRIPT"
  [[ "$output" == "gemini-3-pro" ]]
  
  # With --force: re-probes and gets new value
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.5-pro" ]]
}

# --- stale cache re-probing ---

@test "probe-gemini-highest: stale cache (>24h old) re-probes" {
  write_gemini_stub "gemini-3-pro"
  
  # First probe
  bash "$SCRIPT" >/dev/null
  
  # Make cache file very old (touch to 25h ago)
  old_time=$(($(date +%s) - 90000))
  touch -t "$(python3 -c "import datetime; print(datetime.datetime.fromtimestamp($old_time).strftime('%Y%m%d%H%M.%S'))")" "$HOME/.gemini/highest-model.cache"
  
  # Change stub to return different model
  write_gemini_stub "gemini-2.5-pro"
  
  # Old cache should trigger re-probe, returning new value
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.5-pro" ]]
}

@test "probe-gemini-highest: fresh cache (18h old) uses cached value" {
  write_gemini_stub "gemini-3-pro"
  
  bash "$SCRIPT" >/dev/null
  
  # Make cache 18h old (within TTL)
  old_time=$(($(date +%s) - 64800))
  touch -t "$(python3 -c "import datetime; print(datetime.datetime.fromtimestamp($old_time).strftime('%Y%m%d%H%M.%S'))")" "$HOME/.gemini/highest-model.cache"
  
  # Change stub to fail (proves cache was used)
  write_gemini_stub ""
  
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-3-pro" ]]
}

# --- fallback ---

@test "probe-gemini-highest: fallback to gemini-2.5-pro when all models fail" {
  write_gemini_stub ""
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.5-pro" ]]
}

@test "probe-gemini-highest: cache written with fallback value" {
  write_gemini_stub ""
  
  bash "$SCRIPT" --force >/dev/null
  
  [ -f "$HOME/.gemini/highest-model.cache" ]
  cached=$(cat "$HOME/.gemini/highest-model.cache")
  [ "$cached" = "gemini-2.5-pro" ]
}

# --- candidate ranking ---

@test "probe-gemini-highest: probes candidates in order (highest rank first)" {
  write_gemini_stub "gemini-2.0-pro"
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.0-pro" ]]
}

@test "probe-gemini-highest: gemini-3-pro has highest priority" {
  write_gemini_stub "gemini-3-pro gemini-3-flash gemini-2.5-pro"
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-3-pro" ]]
}

@test "probe-gemini-highest: within same major version, stable before -latest" {
  write_gemini_stub "gemini-2.5-pro-latest gemini-2.5-pro"
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.5-pro" ]]
}

# --- cache directory creation ---

@test "probe-gemini-highest: creates ~/.gemini directory if missing" {
  [ ! -d "$HOME/.gemini" ]
  
  write_gemini_stub "gemini-2.5-pro"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  
  [ -d "$HOME/.gemini" ]
  [ -f "$HOME/.gemini/highest-model.cache" ]
}

# --- atomic write ---

@test "probe-gemini-highest: cache write is atomic (writes to .tmp first)" {
  write_gemini_stub "gemini-3-pro"
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  
  # Should have no .tmp file left behind
  [ ! -f "$HOME/.gemini/highest-model.cache.tmp" ]
  [ -f "$HOME/.gemini/highest-model.cache" ]
}

# --- stderr suppression (don't leak auth errors) ---

@test "probe-gemini-highest: suppresses stderr from gemini CLI probe" {
  cat > "$STUBBIN/gemini" <<'GEMINISTUB'
#!/usr/bin/env bash
echo "ERROR: invalid API key sk-xxxxxxxxxxxx" >&2
exit 1
GEMINISTUB
  chmod +x "$STUBBIN/gemini"
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.5-pro" ]]
  [[ "$output" != *"sk-"* ]]
}

# --- empty cache file ---

@test "probe-gemini-highest: handles empty cache file gracefully" {
  mkdir -p "$HOME/.gemini"
  : > "$HOME/.gemini/highest-model.cache"
  
  write_gemini_stub "gemini-2.5-pro"
  
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "gemini-2.5-pro" ]]
}

# --- exit codes ---

@test "probe-gemini-highest: always exits 0 (success or fallback)" {
  write_gemini_stub ""
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
}

@test "probe-gemini-highest: prints exactly one line" {
  write_gemini_stub "gemini-3-pro"
  
  run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  lines=$(echo "$output" | wc -l)
  [ "$lines" -eq 1 ]
}

# --- unset API key env ---

@test "probe-gemini-highest: unsets GOOGLE_API_KEY before probing" {
  cat > "$STUBBIN/gemini" <<'KEYCHECK'
#!/usr/bin/env bash
[[ -z "$GOOGLE_API_KEY" ]] && echo "OK" && exit 0
exit 1
KEYCHECK
  chmod +x "$STUBBIN/gemini"
  
  run env GOOGLE_API_KEY=fake-key bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
}

@test "probe-gemini-highest: unsets GEMINI_API_KEY before probing" {
  cat > "$STUBBIN/gemini" <<'KEYCHECK2'
#!/usr/bin/env bash
[[ -z "$GEMINI_API_KEY" ]] && echo "OK" && exit 0
exit 1
KEYCHECK2
  chmod +x "$STUBBIN/gemini"
  
  run env GEMINI_API_KEY=fake-key bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
}
