#!/usr/bin/env bash
# Preflight/diagnostic check cho delegate wrapper setup — kiểu `brew doctor`.
# Đọc-only: KHÔNG bao giờ sửa/tạo file, KHÔNG auto-fix bất kỳ thứ gì. Chạy hết
# mọi check dù check trước fail (không set -e) để báo đầy đủ 1 lần thay vì
# dừng ở lỗi đầu tiên.
#
# Usage: scripts/delegate/doctor.sh
# Exit: 0 nếu tất cả pass, 1 nếu có check fail (chỉ để script hoá — bản thân
#       doctor.sh không có hành động destructive dù exit code nào).
set -uo pipefail

PASS=0
FAIL=0

# In dòng ✓/✗ + tăng counter. Không bao giờ nhận giá trị secret làm arg —
# chỉ nhận 0/1 + label mô tả.
check() {
  local ok="$1" label="$2"
  if [[ "$ok" -eq 1 ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "CLI:"
for bin in git jq aider codex gemini; do
  if command -v "$bin" >/dev/null 2>&1; then
    check 1 "$bin"
  else
    check 0 "$bin"
  fi
done

# timeout/gtimeout thiếu KHÔNG hard-fail (wrapper vẫn chạy được) — chỉ WARN,
# vì _common.sh's with_timeout() degrade câm khi thiếu cả hai: delegate CLI
# treo sẽ KHÔNG bị kill, invariant "timeout quá hạn = FAIL" bị vô hiệu.
if command -v timeout >/dev/null 2>&1; then
  echo "  ✓ timeout (via timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  echo "  ✓ timeout (via gtimeout)"
else
  echo "  ⚠ timeout/gtimeout not found — with_timeout degrades silently: hung delegate CLI will NOT be killed. macOS: brew install coreutils (gtimeout)"
fi

echo
echo "Git repo:"
IN_GIT_REPO=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT_REPO=1
  check 1 "cwd is inside a git work tree"
else
  check 0 "cwd is inside a git work tree"
fi

echo
echo "Env keys (presence only — never print values):"

# Read-only KEY=VALUE line lookup, quote-stripped — mirror logic của
# _common.sh's load_env_chain() nhưng KHÔNG export, KHÔNG side effect.
# Không source _common.sh trực tiếp ở đây: file đó `set -euo pipefail` +
# `git rev-parse --show-toplevel` fail-hard khi ngoài git repo → sẽ giết
# doctor.sh sớm, mất hết các check còn lại. Standalone parser tránh phụ thuộc
# đó — pragmatic hơn subshell isolation cho 1 lookup đơn giản thế này.
lookup_env_key() {
  local key="$1" f line v pattern
  if [[ -n "${!key:-}" ]]; then
    echo 1
    return
  fi
  pattern="^[[:space:]]*${key}=(.*)$"
  for f in "$REPO_ROOT/.env.local" "$REPO_ROOT/.env"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ $pattern ]]; then
        v="${BASH_REMATCH[1]}"
        [[ "$v" =~ ^\"(.*)\"$ ]] && v="${BASH_REMATCH[1]}"
        [[ "$v" =~ ^\'(.*)\'$ ]] && v="${BASH_REMATCH[1]}"
        if [[ -n "$v" ]]; then
          echo 1
          return
        fi
      fi
    done < "$f"
  done
  echo 0
}

# Trả 1 nếu bất kỳ key nào trong list resolve được (process env hoặc .env chain).
resolved_any() {
  local k
  for k in "$@"; do
    if [[ "$(lookup_env_key "$k")" == "1" ]]; then
      echo 1
      return
    fi
  done
  echo 0
}

if [[ "$IN_GIT_REPO" -eq 1 ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  ROUTER_BASE_OK="$(resolved_any proxy_host PROXY_9ROUTER_BASE_URL)"
  ROUTER_TOKEN_OK="$(resolved_any proxy_key PROXY_9ROUTER_TOKEN)"
  if [[ "$ROUTER_BASE_OK" == "1" && "$ROUTER_TOKEN_OK" == "1" ]]; then
    ROUTER_OK=1
  else
    ROUTER_OK=0
  fi
  check "$ROUTER_OK" "9router (proxy_host + proxy_key) resolved"

  DS_OK="$(resolved_any deepseek_api_key DEEPSEEK_API_KEY PROXY_DEEPSEEK_API_KEY)"
  check "$DS_OK" "deepseek fallback key resolved"

  if [[ "$ROUTER_OK" -ne 1 && "$DS_OK" -ne 1 ]]; then
    echo "  ⚠ neither 9router nor deepseek fallback resolved — delegate-deepseek wrapper will fail"
  fi
else
  echo "  – skipped — no git repo to locate .env"
fi

echo
echo "Hooks:"
if [[ "$IN_GIT_REPO" -eq 1 ]]; then
  HOOKS_DIR="$REPO_ROOT/.claude/hooks"
  SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"
  TEMPLATE_HOOKS_DIR="$REPO_ROOT/harness/templates/hooks"
  WIRED_NAMES=""
  if command -v jq >/dev/null 2>&1; then
    if [[ -f "$SETTINGS_JSON" ]]; then
      if jq -e 'type == "object"' "$SETTINGS_JSON" >/dev/null 2>&1; then
        check 1 "settings JSON"
      else
        check 0 "settings JSON"
      fi
      WIRED_NAMES="$(jq -r '(.hooks // {}) | .. | strings | select(test("\\.claude/hooks/.*\\.sh$"))' "$SETTINGS_JSON" 2>/dev/null | sed -E 's#.*/##' | sort -u)"

      while IFS= read -r hook_name; do
        [[ -z "$hook_name" ]] && continue
        hook_file="$HOOKS_DIR/$hook_name"
        if [[ -f "$hook_file" && -x "$hook_file" ]]; then
          check 1 "wired: $hook_name"
        else
          check 0 "wired: $hook_name"
        fi
      done <<< "$WIRED_NAMES"
    fi
  else
    echo "  – wiring check skipped (jq missing)"
  fi

  # Orphans: hook file on disk but not referenced anywhere in settings.json — warn only.
  if [[ -n "$WIRED_NAMES" && -d "$HOOKS_DIR" ]]; then
    for hook_file in "$HOOKS_DIR"/*.sh; do
      [[ -f "$hook_file" ]] || continue
      hook_name="$(basename "$hook_file")"
      [[ -f "$TEMPLATE_HOOKS_DIR/$hook_name" ]] || continue
      grep -qx "$hook_name" <<< "$WIRED_NAMES" || echo "  ⚠ unwired hook: $hook_name"
    done
  fi

  # Syntax: bash -n each live hook script.
  if [[ -d "$HOOKS_DIR" ]]; then
    for hook_file in "$HOOKS_DIR"/*.sh; do
      [[ -f "$hook_file" ]] || continue
      hook_name="$(basename "$hook_file")"
      if bash -n "$hook_file" >/dev/null 2>&1; then
        check 1 "syntax: $hook_name"
      else
        check 0 "syntax: $hook_name"
      fi
    done
  fi

  # Template drift: live hook vs harness/templates/hooks counterpart,
  # ignoring any line where the template carries an install-time token
  # (PROJECT_SLUG, CORE_DIRS_ALT, CORE_DIRS_HUMAN, etc. wrapped in double-at
  # markers) — that substitution is expected at install time, not drift. Line-pairwise
  # compare (not NR==FNR diff trick) so an empty template file still
  # correctly reports drift against a non-empty live file.
  if [[ -d "$TEMPLATE_HOOKS_DIR" && ! -f "$REPO_ROOT/.claude/harness-manifest.json" ]]; then
    if [[ -d "$HOOKS_DIR" ]]; then
      for hook_file in "$HOOKS_DIR"/*.sh; do
        [[ -f "$hook_file" ]] || continue
        hook_name="$(basename "$hook_file")"
        tmpl_file="$TEMPLATE_HOOKS_DIR/$hook_name"
        if [[ -f "$tmpl_file" ]]; then
          token_at='@'
          if awk -v tmpl="$tmpl_file" -v at="$token_at$token_at" '
              BEGIN {
                n = 0
                while ((getline line < tmpl) > 0) { n++; t[n] = line }
                close(tmpl)
                re = at "[A-Z_]+" at
              }
              {
                if (FNR > n) { drift = 1; exit }
                if ($0 != t[FNR] && t[FNR] !~ re) { drift = 1; exit }
              }
              END { if (FNR < n) drift = 1; exit drift }
            ' "$hook_file"; then
            check 1 "template match: $hook_name"
          else
            check 0 "template match: $hook_name"
          fi
        fi
      done
    fi
    for tmpl_file in "$TEMPLATE_HOOKS_DIR"/*.sh; do
      [[ -f "$tmpl_file" ]] || continue
      hook_name="$(basename "$tmpl_file")"
      [[ -f "$HOOKS_DIR/$hook_name" ]] || echo "  ⚠ template hook missing live counterpart: $hook_name"
    done
  fi
else
  echo "  – skipped — no git repo to locate .claude/hooks"
fi

# The install manifest is the expected inventory, not the source template tree:
# optional groups and preserved project files must not cause false drift reports.
echo
echo "Installed harness:"
if [[ "$IN_GIT_REPO" -eq 1 ]] && command -v jq >/dev/null 2>&1; then
  manifest="$REPO_ROOT/.claude/harness-manifest.json"
  if [[ -f "$manifest" ]]; then
    if jq -e '
      .schemaVersion == 1 and
      (.syncFiles | type == "array") and
      (.preservePaths | type == "array") and
      (.settings | type == "object") and
      all(.syncFiles[]; (.path | type == "string") and
        (.path | test("^(\\.claude/|scripts/delegate/|\\.git/hooks/)[A-Za-z0-9_./-]+$")) and
        (.path | split("/") | all(. != ".." and . != ".")) and
        (.sha256 | type == "string" and test("^[a-fA-F0-9]{64}$")))
    ' "$manifest" >/dev/null 2>&1; then
      check 1 "harness manifest schema"
      while IFS=$'\t' read -r installed_path expected_hash; do
        [[ -n "$installed_path" ]] || continue
        # Never inspect a preserved path even if a malformed inventory lists both.
        jq -e --arg path "$installed_path" '.preservePaths | index($path) != null' "$manifest" >/dev/null 2>&1 && continue
        actual_hash=""
        if [[ -f "$REPO_ROOT/$installed_path" ]]; then
          if command -v shasum >/dev/null 2>&1; then
            actual_hash="$(shasum -a 256 "$REPO_ROOT/$installed_path" 2>/dev/null)"
          elif command -v sha256sum >/dev/null 2>&1; then
            actual_hash="$(sha256sum "$REPO_ROOT/$installed_path" 2>/dev/null)"
          fi
          actual_hash="${actual_hash%% *}"
        fi
        if [[ -n "$actual_hash" && "$actual_hash" == "$expected_hash" ]]; then
          check 1 "installed: $installed_path"
        else
          check 0 "installed: $installed_path"
        fi
      done < <(jq -r '.syncFiles[] | [.path,.sha256] | @tsv' "$manifest" 2>/dev/null)

      # Only emit a result label, never commands, permission values or env values.
      if jq -e --slurpfile manifest "$manifest" '
        . as $live | $manifest[0].settings as $owned |
        all(($owned.hooks // [])[]; . as $h |
          any($live.hooks[$h.event][]?;
            (.matcher // "") == ($h.matcher // "") and
            any(.hooks[]?; .type == "command" and .command == $h.command))) and
        all(($owned.deny // [])[]; . as $deny |
          ($live.permissions.deny // [] | index($deny)) != null) and
        all(($owned.env // {} | to_entries)[]; . as $entry |
          $live.env[$entry.key] == $entry.value) and
        (if $owned.statusLineCommand == null then true else
          $live.statusLine.type == "command" and
          $live.statusLine.command == $owned.statusLineCommand end)
      ' "$SETTINGS_JSON" >/dev/null 2>&1; then
        check 1 "manifest settings contributions"
      else
        check 0 "manifest settings contributions"
      fi
    else
      check 0 "harness manifest schema"
    fi
  else
    echo "  – no install manifest; legacy hook diagnostics only"
  fi
else
  echo "  – inventory check skipped (git repo or jq missing)"
fi

echo
echo "$PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]]
