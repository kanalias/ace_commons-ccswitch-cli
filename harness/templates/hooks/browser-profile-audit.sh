#!/usr/bin/env bash
# Browser profile audit — mọi profile (Cloak/Playwright MCP + code runtime) phải ở
# <repo>/.browser-profiles/prj_<xx>_sv_<yy>. Rule: .claude/rules/project/browser-mcp-profiles.md
# Phủ chỗ pre-browser-profile-gate.sh không thấy (path bake trong agent/.mcp.json, .env,
# code tự ghép path, registry lệch, profile rơi ra ngoài repo).
#   (không arg)  advisory — in cảnh báo ra stderr, exit 0 (gọi từ session-start.sh)
#   --strict     exit 1 nếu có vấn đề (chạy tay / trước push)
# Không in giá trị env (chỉ tên biến + file).
set -u
strict=0; [ "${1:-}" = "--strict" ] && strict=1

root="${CLAUDE_PROJECT_DIR:-$PWD}"
common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
case "$common" in */.git) repo="$(cd "${common%/.git}" && pwd -P)" ;; *) exit 0 ;; esac
C="$repo/.browser-profiles"
RE_PROFILE='prj_[a-z0-9]+_sv_[a-z0-9]+'
issues=()
add() { issues+=("$1"); }

# 1. Path bake trong agent / .mcp.json (cả Cloak --user-data-dir lẫn Playwright)
for f in "$repo"/.claude/agents/*.md "$repo/.mcp.json"; do
  [ -f "$f" ] || continue
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    rel="${f#$repo/}"
    # so sau resolve symlink (macOS /tmp → /private/tmp); dir chưa tạo → resolve dir cha
    pd="${p%/}"; pr="$(cd "${pd%/*}" 2>/dev/null && pwd -P)/${pd##*/}"
    if ! [[ "$pr" =~ ^$C/$RE_PROFILE$ ]]; then
      add "$rel: user-data-dir ngoài container hoặc sai tên ($p) — phải là $C/prj_<xx>_sv_<yy>"
    fi
  done < <(grep -oE '(--user-data-dir=|user_data_dir=)[^" ,`)]+' "$f" | sed -E 's/^(--user-data-dir=|user_data_dir=)//')
  # pw_<xx>_<yy> phải khớp prj_<xx>_sv_<yy> trong cùng file
  while IFS= read -r s; do
    pair="${s#pw_}"; xx="${pair%%_*}"; yy="${pair#*_}"
    grep -q "prj_${xx}_sv_${yy}" "$f" || add "${f#$repo/}: server $s không bake profile prj_${xx}_sv_${yy}"
  done < <(grep -oE '\bpw_[a-z0-9]+_[a-z0-9]+\b' "$f" | sort -u)
done

# 2. Container: guard ignore + registry khớp dir
if [ -d "$C" ]; then
  for ig in .gitignore .dockerignore; do
    [ -f "$repo/$ig" ] || continue
    grep -qxE '/?\.browser-profiles/?' "$repo/$ig" || add "$ig thiếu dòng /.browser-profiles/"
  done
  reg="$C/_registry.md"
  if [ ! -f "$reg" ]; then
    add ".browser-profiles/_registry.md chưa có"
  else
    for d in "$C"/prj_*; do
      [ -d "$d" ] || continue
      n="${d##*/}"
      case "$n" in *.lock*) continue ;; esac
      [[ "$n" =~ ^$RE_PROFILE$ ]] || { add "profile sai tên: .browser-profiles/$n"; continue; }
      grep -qE "^\| *$n *\|" "$reg" || add "registry thiếu dòng $n"
    done
    while IFS= read -r n; do
      [ -d "$C/$n" ] || add "registry có $n nhưng dir không tồn tại"
    done < <(grep -oE "^\| *$RE_PROFILE *\|" "$reg" | tr -d '| ')
  fi
fi

# 3. .env*: biến *PROFILE*DIR có giá trị = relocate profile (lib v0.5.0+ sẽ throw)
for f in "$repo"/.env* "$repo"/src/.env* "$repo"/src/config.env; do
  [ -f "$f" ] || continue
  case "$f" in *.example) continue ;; esac
  while IFS= read -r v; do
    add "${f#$repo/}: $v đang set — bỏ đi (profile luôn ở .browser-profiles)"
  done < <(grep -oE '^[A-Z0-9_]*PROFILES?_DIR=.+' "$f" | cut -d= -f1)
done

# 4. Code tự ghép path profile thay vì resolveServiceProfilePath (lib-browser-crawler)
while IFS= read -r hit; do
  add "code tự ghép path profile: $hit — dùng resolveServiceProfilePath"
done < <(git -C "$root" grep -nE "join\([^)]*['\"]\.browser-profiles['\"]|\.cloakbrowser/|homedir\(\)[^;]*[Pp]rofile" \
  -- '*.ts' '*.js' '*.mjs' '*.cjs' '*.py' ':!*test*' ':!**/dist/**' ':!**/node_modules/**' ':!.claude/**' 2>/dev/null | cut -d: -f1,2 | head -10)

# 5. Profile rơi ngoài repo (CloakBrowser default dir)
for d in "$HOME"/.cloakbrowser/*profile*; do
  [ -d "$d" ] && add "profile ngoài repo: $d — backup tar rồi move vào .browser-profiles/prj_<xx>_sv_<yy>"
done

[ "${#issues[@]}" -eq 0 ] && exit 0
{
  echo "🧭 browser-profile-audit: ${#issues[@]} vấn đề (rule .claude/rules/project/browser-mcp-profiles.md)"
  for i in "${issues[@]}"; do echo "   • $i"; done
} >&2
[ "$strict" -eq 1 ] && exit 1
exit 0
