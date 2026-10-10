#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — advisory only, exit 0 always.
# On `git commit`: mỗi deploy.md (tìm bằng `git ls-files`) có scope = thư mục chứa nó
# (deploy.md ở root = cả repo; doc lồng nhau → doc gần nhất thắng). Commit đổi file code
# trong scope mà không đổi deploy.md đó → nhắc chạy /deploy-doc. Không block, không ghi file.
# Bỏ qua .md, .claude/, test/, node_modules khi tính "file code".
# Off-switch: HARNESS_DELEGATE=0.
set -uo pipefail

[ "${HARNESS_DELEGATE:-1}" = "0" ] && exit 0

# stale_docs <docs-file> : đọc changed paths ở stdin, in mỗi deploy.md cần refresh
stale_docs() {
  local docs_file="$1" f d best bl touched="" hit="" dir
  local -a docs=()
  while IFS= read -r d; do [ -n "$d" ] && docs+=("$d"); done < "$docs_file"
  [ "${#docs[@]}" -gt 0 ] || return 0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      deploy.md|*/deploy.md) touched="$touched|$f|"; continue ;;
      *.md|*.markdown|*.mdx|.claude/*|test/*|*/test/*|tests/*|*/tests/*|*node_modules/*) continue ;;
    esac
    best=""; bl=-1
    for d in "${docs[@]}"; do
      dir="${d%deploy.md}"   # "" (root) or "a/b/"
      case "$f" in "$dir"*) [ "${#dir}" -gt "$bl" ] && { best="$d"; bl="${#dir}"; } ;; esac
    done
    [ -n "$best" ] && case "|$hit|" in *"|$best|"*) ;; *) hit="$hit|$best" ;; esac
  done
  for d in $(printf '%s' "$hit" | tr '|' '\n'); do
    [ -z "$d" ] && continue
    case "$touched" in *"|$d|"*) ;; *) echo "$d" ;; esac
  done
}

if [ "${1:-}" = "--self-test" ]; then
  fail=0; tmp=$(mktemp); printf 'deploy.md\nsvc/a/deploy.md\n' > "$tmp"
  check() { local got; got=$(printf '%s\n' "$2" | stale_docs "$tmp" | tr '\n' ' ' | sed 's/ $//'); [ "$got" = "$1" ] || { echo "FAIL [$2] → '$got' want '$1'"; fail=1; }; }
  check "svc/a/deploy.md" "svc/a/run.ts"
  check "" $'svc/a/run.ts\nsvc/a/deploy.md'
  check "deploy.md" "src/x.ts"
  check "deploy.md svc/a/deploy.md" $'src/x.ts\nsvc/a/run.ts'
  check "" "README.md"
  check "" "test/x.ts"
  check "" ""
  rm -f "$tmp"
  [ "$fail" = 0 ] && echo "self-test PASS" || { echo "self-test FAIL"; exit 1; }
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
printf '%s' "$payload" | jq empty >/dev/null 2>&1 || exit 0
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' || exit 0

repo="${CLAUDE_PROJECT_DIR:-$(pwd)}"
docs=$(mktemp); trap 'rm -f "$docs"' EXIT
git -C "$repo" ls-files '**/deploy.md' 'deploy.md' 2>/dev/null | sort -u > "$docs" || true
[ -s "$docs" ] || exit 0

changed=$(git -C "$repo" diff --cached --name-only 2>/dev/null || true)
# `git commit -a` / `-am` stages tracked changes at commit time.
if printf '%s' "$cmd" | grep -Eq 'commit[[:space:]]+(.*[[:space:]])?-[a-zA-Z]*a'; then
  changed="$changed"$'\n'"$(git -C "$repo" diff --name-only 2>/dev/null || true)"
fi

stale=$(printf '%s\n' "$changed" | stale_docs "$docs" | tr '\n' ' ' | sed 's/ $//')
[ -z "$stale" ] && exit 0

msg="📋 deploy-doc: commit này đổi file trong scope deploy doc nhưng chưa cập nhật: ${stale}. Nếu thay đổi ảnh hưởng env/lịch/process manager/host/quy trình deploy thì chạy skill deploy-doc và thêm 1 dòng nhật ký trong cùng commit; nếu không thì bỏ qua."
jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
