#!/usr/bin/env bats
# ai-proxy/statusline-context.sh: JSON stdin → colored progress bar + percentage.

load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/ai-proxy/statusline-context.sh"
}

# --- jq missing ---

@test "statusline-context: prints 'jq missing' when jq not available and exits 0" {
  stub_dir="$BATS_TEST_TMPDIR/stubpath"
  mkdir -p "$stub_dir"
  for tool in bash cat head tr printf; do
    p=$(command -v "$tool")
    [ -n "$p" ] && ln -s "$p" "$stub_dir/$(basename "$p")"
  done
  run env PATH="$stub_dir" bash -c "echo '{\"context_window\": {\"used_percentage\": 50}}' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq missing"* ]]
}

# --- threshold: <50% (green, no tag) ---

@test "statusline-context: less than 50 percent renders green bar with no tag" {
  json='{"context_window":{"used_percentage":30,"total_input_tokens":60000,"context_window_size":200000},"model":{"display_name":"Opus"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"30%"* ]]
}

@test "statusline-context: 49 percent still green" {
  json='{"context_window":{"used_percentage":49},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"49%"* ]]
}

# --- threshold: 50-74% (yellow, "↑ delegate" tag) ---

@test "statusline-context: 50 percent renders yellow with delegate tag" {
  json='{"context_window":{"used_percentage":50},"model":{"display_name":"Sonnet"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"50%"* ]]
  [[ "$output" == *"delegate"* ]]
}

@test "statusline-context: 60 percent shows yellow and delegate tag" {
  json='{"context_window":{"used_percentage":60},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"60%"* ]]
  [[ "$output" == *"delegate"* ]]
}

@test "statusline-context: 74 percent still yellow" {
  json='{"context_window":{"used_percentage":74},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"74%"* ]]
  [[ "$output" == *"delegate"* ]]
}

# --- threshold: >=75% (red, warning tag) ---

@test "statusline-context: 75 percent renders red with warning" {
  json='{"context_window":{"used_percentage":75},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"75%"* ]]
}

@test "statusline-context: 99 percent red" {
  json='{"context_window":{"used_percentage":99},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"99%"* ]]
}

@test "statusline-context: 100 percent red" {
  json='{"context_window":{"used_percentage":100},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"100%"* ]]
}

# --- progress bar rendering (10 blocks) ---

@test "statusline-context: 0 percent renders empty bar" {
  json='{"context_window":{"used_percentage":0},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"░░░░░░░░░░"* ]]
}

@test "statusline-context: 5 percent renders mostly empty" {
  json='{"context_window":{"used_percentage":5},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"░"* ]]
}

@test "statusline-context: 10 percent renders 1 filled" {
  json='{"context_window":{"used_percentage":10},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▓"* ]]
}

@test "statusline-context: 50 percent renders 5 filled 5 empty" {
  json='{"context_window":{"used_percentage":50},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▓▓▓▓▓░░░░░"* ]]
}

@test "statusline-context: 99 percent renders 9 filled 1 empty" {
  json='{"context_window":{"used_percentage":99},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▓▓▓▓▓▓▓▓▓░"* ]]
}

@test "statusline-context: 100 percent renders full bar" {
  json='{"context_window":{"used_percentage":100},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▓▓▓▓▓▓▓▓▓▓"* ]]
}

@test "statusline-context: bar caps at 10 blocks" {
  json='{"context_window":{"used_percentage":150},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▓▓▓▓▓▓▓▓▓▓"* ]]
}

# --- K notation for tokens ---

@test "statusline-context: 60000 tokens to 60K" {
  json='{"context_window":{"used_percentage":30,"total_input_tokens":60000,"context_window_size":200000},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"60K"* ]]
}

@test "statusline-context: context_window_size 200000 to 200K" {
  json='{"context_window":{"used_percentage":30,"total_input_tokens":10000,"context_window_size":200000},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"200K"* ]]
}

@test "statusline-context: rounds up tokens 1500 to 2K" {
  json='{"context_window":{"used_percentage":30,"total_input_tokens":1500},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2K"* ]]
}

# --- defaults for missing fields ---

@test "statusline-context: missing used_percentage defaults to 0" {
  json='{"context_window":{"context_window_size":200000},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0%"* ]]
}

@test "statusline-context: missing total_input_tokens defaults to 0" {
  json='{"context_window":{"used_percentage":30,"context_window_size":200000},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0K"* ]]
}

@test "statusline-context: missing context_window_size defaults to 200000" {
  json='{"context_window":{"used_percentage":50},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"200K"* ]]
}

@test "statusline-context: missing display_name defaults to question" {
  json='{"context_window":{"used_percentage":50},"model":{}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"?"* ]]
}

@test "statusline-context: missing model object uses all defaults" {
  json='{"context_window":{"used_percentage":50}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"50%"* ]]
}

# --- edge: empty/malformed JSON ---

@test "statusline-context: empty JSON object uses all defaults" {
  json='{}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0%"* ]]
}

# --- model display name in output ---

@test "statusline-context: displays model name in brackets at start" {
  json='{"context_window":{"used_percentage":50},"model":{"display_name":"Claude Opus"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Claude Opus"* ]]
}

# --- ANSI color codes present (basic check) ---

@test "statusline-context: output contains color codes" {
  json='{"context_window":{"used_percentage":50},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]
}

@test "statusline-context: yellow color includes indicator" {
  json='{"context_window":{"used_percentage":60},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]
}

@test "statusline-context: red color includes indicator" {
  json='{"context_window":{"used_percentage":75},"model":{"display_name":"test"}}'
  run bash -c "printf '%s' '$json' | bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]
}
