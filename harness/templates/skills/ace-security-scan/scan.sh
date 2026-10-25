#!/usr/bin/env bash
# ace-security-scan — quét security READ-ONLY: máy (macOS/Linux), code, cấu hình Claude Code.
# Usage: scan.sh <machine|code|claude|all> [path]
# Không sửa/xoá/cài gì; không in giá trị secret (chỉ rule, file:line, tên biến, đếm).
# Bash 3.2 compatible (macOS /bin/bash).
set -u
shopt -s nullglob

MODE="${1:-all}"
TARGET="${2:-$PWD}"
OUT_DIR="${ACE_SECSCAN_OUT:-$HOME/.ace-security-scan}"
MAX_LIST="${ACE_SECSCAN_MAX_LIST:-30}"
OS="$(uname -s)"

case "$MODE" in
  machine|code|claude|all) ;;
  -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
  *) echo "usage: scan.sh <machine|code|claude|all> [path]" >&2; exit 2 ;;
esac
if [ "$MODE" != machine ] && [ ! -d "$TARGET" ]; then
  echo "path không tồn tại: $TARGET" >&2; exit 2
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd || echo "$TARGET")"

umask 077
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d "$OUT_DIR/.tmp.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$OUT_DIR/$STAMP-$MODE.md"
ROWS="$TMP/rows"; : >"$ROWS"
N_CRIT=0; N_WARN=0; N_INFO=0; N_OK=0

have() { command -v "$1" >/dev/null 2>&1; }
clean() { printf '%s' "$*" | tr '\n|' ' /' | cut -c1-300; }
# add <critical|warn|info|ok> <section> <check> <detail>
add() {
  case "$1" in
    critical) N_CRIT=$((N_CRIT+1)) ;; warn) N_WARN=$((N_WARN+1)) ;;
    info) N_INFO=$((N_INFO+1)) ;; ok) N_OK=$((N_OK+1)) ;;
  esac
  printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$(clean "$4")" >>"$ROWS"
}
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }
# Pattern shell nguy hiểm (download-exec, reverse shell, persistence)
DANGER_RE='(curl|wget)[^|#]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh|base64[[:space:]]+(-d|-D|--decode)[^|]*\|[[:space:]]*(ba|z)?sh|eval[[:space:]]+"?\$\((curl|wget)|/dev/tcp/|nc[[:space:]]+(-[a-z]*e|.*-e[[:space:]])|chmod[[:space:]]+(-R[[:space:]]+)?777|rm[[:space:]]+-rf[[:space:]]+(~|\$HOME|/)([[:space:]]|$)|>>?[[:space:]]*~?/?[^[:space:]]*authorized_keys'

# ─────────────────────────── machine ───────────────────────────
scan_machine() {
  local S=machine
  if [ "$OS" = Darwin ]; then
    if csrutil status 2>/dev/null | grep -qi enabled; then add ok $S SIP "enabled"; else add critical $S SIP "System Integrity Protection không bật"; fi
    if spctl --status 2>/dev/null | grep -q 'assessments enabled'; then add ok $S Gatekeeper "enabled"; else add warn $S Gatekeeper "Gatekeeper tắt"; fi
    case "$(fdesetup status 2>/dev/null)" in
      *"is On"*) add ok $S FileVault "On" ;;
      *"is Off"*) add critical $S FileVault "FileVault tắt — ổ đĩa không mã hoá" ;;
      *) add info $S FileVault "không xác định" ;;
    esac
    local fw; fw="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)"
    case "$fw" in *enabled*) add ok $S Firewall "enabled" ;; *disabled*) add warn $S Firewall "Application Firewall tắt" ;; *) add info $S Firewall "không đọc được" ;; esac
    local au; au="$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)"
    [ "$au" = 1 ] && add ok $S AutoUpdate "auto check on" || add info $S AutoUpdate "auto check update tắt/không đọc được"

    # LaunchAgents user: binary chưa ký / bundle id adware
    local p prog n=0 bad=0
    for p in "$HOME"/Library/LaunchAgents/*.plist; do
      n=$((n+1))
      prog="$(plutil -extract Program raw -o - "$p" 2>/dev/null || plutil -extract ProgramArguments.0 raw -o - "$p" 2>/dev/null)"
      [ -n "$prog" ] || continue
      if [ ! -e "$prog" ]; then
        add info $S LaunchAgent "$(basename "$p") → target không tồn tại: $prog"
      elif file -b "$prog" 2>/dev/null | grep -q 'Mach-O' && ! codesign --verify "$prog" >/dev/null 2>&1; then
        add warn $S LaunchAgent "$(basename "$p") → binary không ký/ký lỗi: $prog"; bad=$((bad+1))
      fi
    done
    [ $bad -eq 0 ] && add ok $S LaunchAgents "$n agent user, không có binary unsigned"
    local recent; recent="$(find /Library/LaunchAgents /Library/LaunchDaemons "$HOME/Library/LaunchAgents" -type f -mtime -7 2>/dev/null | head -"$MAX_LIST")"
    [ -n "$recent" ] && add info $S "Persistence mới (7 ngày)" "$(echo "$recent" | tr '\n' ' ')"
    local kb; kb="$(grep -lE 'com\.(pcv|searchmine|MyShopCoupon|genieo|installmac|inkeepr|vsearch|conduit|cinemaplus|trovi)\.' /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist "$HOME"/Library/LaunchAgents/*.plist 2>/dev/null)"
    [ -n "$kb" ] && add critical $S "Adware bundle id" "$(echo "$kb" | tr '\n' ' ')"
    local li; li="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)"
    [ -n "$li" ] && add info $S "Login items" "$li"
  else
    add info $S "macOS checks" "bỏ qua (OS=$OS) — chỉ chạy check portable"
  fi

  # Process chạy từ thư mục tạm
  local tp; tp="$(ps -axo pid=,comm= 2>/dev/null | awk '$2 ~ /^\/(tmp|private\/tmp|var\/tmp)\// {print $1":"$2}' | head -"$MAX_LIST")"
  [ -n "$tp" ] && add warn $S "Process từ /tmp" "$(echo "$tp" | tr '\n' ' ')" || add ok $S "Process từ /tmp" "không có"

  # Port lắng nghe mọi interface
  local lis=""
  if [ "$OS" = Darwin ]; then
    lis="$(netstat -anv -p tcp 2>/dev/null | awk '$6=="LISTEN" && ($4 ~ /^\*\./ || $4 ~ /^0\.0\.0\.0\./) {n=split($4,a,"."); print a[n]}' | sort -un | tr '\n' ' ')"
  elif have ss; then
    lis="$(ss -ltnH 2>/dev/null | awk '$4 ~ /^(0\.0\.0\.0|\*|\[::\]):/ {n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')"
  fi
  if [ -n "$lis" ]; then
    local x risky=""
    for x in $lis; do
      case "$x" in 22|23|445|548|3389|5900|5432|3306|6379|27017|9200) risky="$risky$x " ;; esac
    done
    [ -n "$risky" ] && add warn $S "Port nhạy cảm mở mọi interface" "$risky(kiểm firewall/bind 127.0.0.1)"
    add info $S "Port LISTEN 0.0.0.0/*" "$lis"
  fi

  # Cron (chỉ đếm, không in nội dung — có thể chứa token)
  local cn; cn="$(crontab -l 2>/dev/null | grep -cvE '^[[:space:]]*(#|$)')"
  [ "${cn:-0}" -gt 0 ] && add info $S Crontab "$cn dòng (xem: crontab -l)"

  # SSH
  if [ -d "$HOME/.ssh" ]; then
    local m; m="$(mode_of "$HOME/.ssh")"
    [ "$m" = 700 ] || add warn $S "~/.ssh quyền" "mode $m (nên 700)"
    local k unenc=0
    for k in "$HOME"/.ssh/*; do
      [ -f "$k" ] || continue
      case "$k" in *.pub|*known_hosts*|*config|*authorized_keys*) continue ;; esac
      grep -q 'PRIVATE KEY' "$k" 2>/dev/null || continue
      m="$(mode_of "$k")"
      case "$m" in 600|400) ;; *) add warn $S "SSH key quyền" "$(basename "$k") mode $m (nên 600)" ;; esac
      if ssh-keygen -y -P '' -f "$k" >/dev/null 2>&1; then
        add warn $S "SSH key không passphrase" "$(basename "$k")"; unenc=$((unenc+1))
      fi
    done
    [ $unenc -eq 0 ] && add ok $S "SSH key" "không có key private thiếu passphrase"
    if [ -f "$HOME/.ssh/authorized_keys" ]; then
      add info $S authorized_keys "$(grep -cvE '^[[:space:]]*(#|$)' "$HOME/.ssh/authorized_keys") key được phép login vào máy này"
    fi
  fi

  # Shell rc: download-exec + secret plaintext (chỉ in file:line + tên biến)
  local rc hits sec
  for rc in "$HOME"/.zshrc "$HOME"/.zprofile "$HOME"/.zshenv "$HOME"/.bashrc "$HOME"/.bash_profile "$HOME"/.profile; do
    [ -f "$rc" ] || continue
    hits="$(grep -nE "$DANGER_RE" "$rc" 2>/dev/null | cut -d: -f1 | tr '\n' ',')"
    [ -n "$hits" ] && add warn $S "Shell rc download-exec" "$(basename "$rc") dòng ${hits%,}"
    sec="$(grep -nE '^[[:space:]]*export[[:space:]]+[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY)[A-Z0-9_]*=["'\'']?[^$"'\''[:space:]]{8,}' "$rc" 2>/dev/null \
      | sed -E 's/^([0-9]+):[[:space:]]*export[[:space:]]+([A-Z0-9_]+)=.*/\2(dòng \1)/' | tr '\n' ' ')"
    [ -n "$sec" ] && add warn $S "Secret plaintext trong rc" "$(basename "$rc"): ${sec}— chuyển sang file env 0600/Keychain"
  done

  # File credential đọc được bởi user khác (others-read)
  local f wr=""
  for f in "$HOME"/.netrc "$HOME"/.aws/credentials "$HOME"/.docker/config.json "$HOME"/.kube/config "$HOME"/.npmrc "$HOME"/.pypirc "$HOME"/.git-credentials; do
    [ -f "$f" ] || continue
    m="$(mode_of "$f")"
    case "$m" in *[4567]) wr="$wr${f#$HOME/}($m) " ;; esac
  done
  local root
  for root in ${ACE_SECSCAN_ENV_ROOTS:-}; do
    [ -d "$root" ] || continue
    while IFS= read -r f; do wr="$wr$f "; done < <(find "$root" -maxdepth 5 \( -name node_modules -o -name .git -o -name worktrees \) -prune -o -type f \( -name '.env' -o -name '.env.*' -o -name '*.pem' \) ! -name '*.example' ! -name '*.sample' -perm -004 -print 2>/dev/null | head -"$MAX_LIST")
  done
  [ -n "$wr" ] && add warn $S "Credential world-readable" "${wr}— chmod 600" || add ok $S "Credential file quyền" "không có file others-read"
}

# ─────────────────────────── code ───────────────────────────
scan_code() {
  local S=code D="$TARGET" isgit=0
  git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1 && isgit=1

  if [ $isgit -eq 1 ]; then
    local tr; tr="$(git -C "$D" ls-files 2>/dev/null | grep -E '(^|/)\.env($|\.)|\.(pem|p12|pfx|jks|keystore|key)$|(^|/)id_(rsa|ed25519|ecdsa)$|(^|/)secrets?/|credentials[^/]*\.json$|service-account[^/]*\.json$' \
      | grep -vE '\.(example|sample|template|dist)$|\.env\.(example|sample|template)' | head -"$MAX_LIST" | tr '\n' ' ')"
    [ -n "$tr" ] && add critical $S "File nhạy cảm bị git track" "$tr" || add ok $S "File nhạy cảm bị git track" "không có"
    if ! git -C "$D" check-ignore -q .env 2>/dev/null; then add info $S ".gitignore" ".env chưa bị ignore"; fi
  fi

  if have gitleaks; then
    local rep="$TMP/gl.json" sub
    if [ $isgit -eq 1 ]; then sub="git"; else sub="dir"; fi
    gitleaks "$sub" --redact --no-banner --log-level error --exit-code 0 --report-format json --report-path "$rep" "$D" >/dev/null 2>&1
    if [ -s "$rep" ] && have jq; then
      local cnt; cnt="$(jq 'length' "$rep")"
      if [ "$cnt" -gt 0 ]; then
        add critical $S "gitleaks ($sub$( [ $isgit -eq 1 ] && echo ' + history'))" "$cnt finding: $(jq -r '.[] | "\(.RuleID)@\(.File):\(.StartLine)\(if .Commit != "" then "#"+(.Commit[0:8]) else "" end)"' "$rep" | sort -u | head -"$MAX_LIST" | tr '\n' ' ')"
      else add ok $S gitleaks "0 finding"; fi
    else add ok $S gitleaks "0 finding"; fi
    # working tree: file chứa secret CHƯA bị gitignore (sắp bị commit); file ignored chỉ kiểm quyền
    if [ $isgit -eq 1 ] && have jq; then
      gitleaks dir --redact --no-banner --log-level error --exit-code 0 --report-format json --report-path "$TMP/gld.json" "$D" >/dev/null 2>&1
      local rf rl pending="" loose=""
      if [ -s "$TMP/gld.json" ]; then
        while IFS=$'\t' read -r rf rl; do
          rf="${rf#$D/}"
          if git -C "$D" check-ignore -q "$rf" 2>/dev/null; then
            case "$(mode_of "$D/$rf")" in 600|400) ;; *) loose="$loose$rf($(mode_of "$D/$rf")) " ;; esac
          else
            pending="$pending$rl "
          fi
        done < <(jq -r '.[] | "\(.File)\t\(.RuleID)@\(.File|tostring):\(.StartLine)"' "$TMP/gld.json" | sed "s|$D/||g" | sort -u)
      fi
      [ -n "$pending" ] && add critical $S "Secret trong file chưa ignore" "$(printf '%s' "$pending" | tr ' ' '\n' | head -"$MAX_LIST" | tr '\n' ' ')— thêm .gitignore/chuyển sang env"
      loose="$(printf '%s' "$loose" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
      [ -n "${loose// /}" ] && add warn $S "File secret ignored quyền rộng" "${loose}— chmod 600"
    fi
  else
    add info $S gitleaks "chưa cài — brew install gitleaks"
  fi

  if have semgrep; then
    local sr="$TMP/sg.json"
    semgrep scan --metrics=off --quiet --json --config p/security-audit --config p/secrets "$D" >"$sr" 2>/dev/null
    if [ -s "$sr" ] && have jq; then
      local e w
      e="$(jq '[.results[] | select(.extra.severity=="ERROR")] | length' "$sr")"; w="$(jq '[.results[] | select(.extra.severity=="WARNING")] | length' "$sr")"
      if [ "$e" -gt 0 ] || [ "$w" -gt 0 ]; then
        add "$( [ "$e" -gt 0 ] && echo critical || echo warn)" $S semgrep "ERROR=$e WARNING=$w: $(jq -r '.results[] | select(.extra.severity!="INFO") | "\(.check_id|split(".")|last)@\(.path):\(.start.line)"' "$sr" | sed "s|$D/||" | head -"$MAX_LIST" | tr '\n' ' ')"
      else add ok $S semgrep "0 finding ERROR/WARNING"; fi
    else add info $S semgrep "chạy lỗi/không có output (cần mạng để tải ruleset)"; fi
  else
    add info $S semgrep "chưa cài — brew install semgrep (SAST: injection, XSS, crypto yếu...)"
  fi

  # Dependency vuln
  if have osv-scanner; then
    local orp="$TMP/osv.json"
    osv-scanner scan source -r --format json "$D" >"$orp" 2>/dev/null
    if [ -s "$orp" ] && have jq; then
      local vc; vc="$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "$orp" 2>/dev/null || echo 0)"
      [ "${vc:-0}" -gt 0 ] && add warn $S "osv-scanner" "$vc vuln: $(jq -r '.results[]?.packages[]? | select((.vulnerabilities|length)>0) | "\(.package.name)@\(.package.version)"' "$orp" | sort -u | head -"$MAX_LIST" | tr '\n' ' ')" || add ok $S osv-scanner "0 vuln"
    fi
  else
    local lf any=0
    while IFS= read -r lf; do
      any=1
      local dir; dir="$(dirname "$lf")"
      if have npm && have jq; then
        local na; na="$(cd "$dir" && npm audit --json --omit=dev 2>/dev/null | jq -r '.metadata.vulnerabilities | "critical=\(.critical) high=\(.high) moderate=\(.moderate)"' 2>/dev/null)"
        case "$na" in
          "") add info $S "npm audit" "${dir#$D/}: không chạy được" ;;
          critical=0\ high=0*) add ok $S "npm audit" "${dir#$D/}: $na" ;;
          *) add warn $S "npm audit" "${dir#$D/}: $na" ;;
        esac
      fi
    done < <(find "$D" -maxdepth 3 \( -name node_modules -o -name .git -o -name worktrees \) -prune -o -name package-lock.json -print 2>/dev/null | head -10)
    add info $S "Dependency scan" "osv-scanner chưa cài — brew install osv-scanner (npm/pip/go/maven/cargo)$( [ $any -eq 1 ] && echo '; đã fallback npm audit')"
  fi

  if have trivy; then
    local tv="$TMP/trivy.json"
    trivy fs --quiet --scanners misconfig --format json "$D" >"$tv" 2>/dev/null
    if [ -s "$tv" ] && have jq; then
      local mc; mc="$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL")] | length' "$tv")"
      [ "${mc:-0}" -gt 0 ] && add warn $S "trivy misconfig" "$mc HIGH/CRITICAL: $(jq -r '.Results[]? | select(.Misconfigurations) | .Target as $t | .Misconfigurations[] | select(.Severity=="HIGH" or .Severity=="CRITICAL") | "\(.ID)@\($t)"' "$tv" | sort -u | head -"$MAX_LIST" | tr '\n' ' ')" || add ok $S "trivy misconfig" "0 HIGH/CRITICAL"
    fi
  else
    add info $S trivy "chưa cài — brew install trivy (Dockerfile/compose/k8s/terraform misconfig)"
  fi
}

# ─────────────────────────── claude ───────────────────────────
scan_claude() {
  local S=claude f m
  local settings="$HOME/.claude/settings.json $HOME/.claude/settings.local.json"
  if [ "$MODE" != machine ]; then settings="$settings $TARGET/.claude/settings.json $TARGET/.claude/settings.local.json"; fi
  for f in $settings; do
    [ -f "$f" ] || continue
    local short="${f/#$HOME/~}"
    m="$(mode_of "$f")"
    if have jq && jq -e . "$f" >/dev/null 2>&1; then
      [ "$(jq -r '.permissions.defaultMode // ""' "$f")" = bypassPermissions ] && add warn $S "bypassPermissions" "$short — mọi tool chạy không hỏi"
      [ "$(jq -r '.skipDangerousModePermissionPrompt // false' "$f")" = true ] && add info $S "skipDangerousModePermissionPrompt" "$short"
      local sk; sk="$(jq -r '.env // {} | to_entries[] | select(.key|test("TOKEN|SECRET|KEY|PASSWORD";"i")) | select((.value|tostring|length) >= 8) | .key' "$f" 2>/dev/null | tr '\n' ' ')"
      if [ -n "$sk" ]; then
        case "$m" in 600|400) add info $S "Secret trong settings env" "$short: $sk(mode $m OK)" ;;
          *) add warn $S "Secret trong settings env" "$short: ${sk}— mode $m, nên chmod 600" ;; esac
      fi
      local hk; hk="$(jq -r '[.hooks // {} | .. | objects | select(.command?) | .command] | .[]' "$f" 2>/dev/null)"
      if [ -n "$hk" ]; then
        local hd; hd="$(printf '%s\n' "$hk" | grep -nE "$DANGER_RE" | cut -d: -f1 | tr '\n' ',')"
        [ -n "$hd" ] && add critical $S "Hook command nguy hiểm" "$short hook #${hd%,}"
        add info $S "Hooks" "$short: $(printf '%s\n' "$hk" | grep -c .) command"
      fi
    else
      add info $S settings "$short: không parse được JSON"
    fi
  done

  # Script hook/skill/agent/command: pattern download-exec, reverse shell, persistence
  local dirs="$HOME/.claude/hooks $HOME/.claude/skills $HOME/.claude/agents $HOME/.claude/commands"
  [ "$MODE" != machine ] && dirs="$dirs $TARGET/.claude/hooks $TARGET/.claude/skills $TARGET/.claude/agents $TARGET/.claude/commands"
  local d hits=""
  for d in $dirs; do
    [ -d "$d" ] || continue
    hits="$hits$(grep -rnIE "$DANGER_RE" "$d" --exclude-dir=.trash --exclude-dir=synced --exclude=scan.sh 2>/dev/null | cut -d: -f1,2 | sed "s|$HOME|~|" | head -"$MAX_LIST" | tr '\n' ' ')"
  done
  [ -n "$hits" ] && add warn $S "Pattern nguy hiểm trong hook/skill" "$hits(đọc kỹ — có thể là docs/ví dụ)" || add ok $S "Hook/skill/agent" "không thấy download-exec/reverse-shell"

  # MCP servers: liệt kê tên + lệnh (KHÔNG in env/headers)
  local mcpf mcps=""
  for mcpf in "$HOME/.claude.json" "$TARGET/.mcp.json"; do
    [ -f "$mcpf" ] && have jq || continue
    mcps="$mcps$(jq -r '[.mcpServers // {}, (.projects // {} | .[]? | .mcpServers // {})] | add // {} | to_entries[] | "\(.key)=\(.value.command // .value.url // "?" | tostring | split("?")[0])"' "$mcpf" 2>/dev/null | sort -u | tr '\n' ' ')"
  done
  if [ -n "$mcps" ]; then
    add info $S "MCP servers" "$mcps"
    local insecure; insecure="$(printf '%s' "$mcps" | tr ' ' '\n' | grep -E '=http://' | grep -vE 'http://(localhost|127\.0\.0\.1)' | tr '\n' ' ')"
    [ -n "$insecure" ] && add warn $S "MCP qua HTTP thường" "$insecure"
  fi
}

case "$MODE" in
  machine) scan_machine; scan_claude ;;
  code) scan_code ;;
  claude) scan_claude ;;
  all) scan_machine; scan_code; scan_claude ;;
esac

{
  echo "# ace-security-scan — $MODE"
  echo
  echo "- Thời điểm: $(date '+%Y-%m-%d %H:%M:%S %Z') · Host: $(hostname -s) · OS: $OS"
  [ "$MODE" != machine ] && echo "- Target: $TARGET"
  echo "- Tổng: critical=$N_CRIT warn=$N_WARN info=$N_INFO ok=$N_OK"
  echo
  echo "| Mức | Nhóm | Check | Chi tiết |"
  echo "|---|---|---|---|"
  for s in critical warn info ok; do grep "^| $s |" "$ROWS"; done
} >"$REPORT"
chmod 600 "$REPORT"
cat "$REPORT"
echo
echo "REPORT: $REPORT"
echo "SUMMARY: critical=$N_CRIT warn=$N_WARN info=$N_INFO ok=$N_OK"
