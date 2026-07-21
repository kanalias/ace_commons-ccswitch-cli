#!/usr/bin/env bash
# claude-auto-compact.sh — chỉnh mốc auto-compact của Claude Code qua settings.json.
#
# Key config: autoCompactWindow (số token tuyệt đối). Ngưỡng thực compact =
#   min(autoCompactWindow, model max context). Opus window ~200k → set 190000 ≈ 95%.
# Tắt hẳn auto-compact: env.DISABLE_AUTO_COMPACT="1" (tự gõ /compact thủ công).
#
# LƯU Ý: Anthropic khuyến nghị để "auto" (Claude tự chọn window theo model).
# Đặt cứng mốc thấp = compact sớm hơn, có thể mất context khi task nặng skill/file.
set -euo pipefail

usage() {
  cat <<'EOF'
claude-auto-compact.sh — chỉnh mốc auto-compact của Claude Code (settings.json)

Auto-compact = Claude tự tóm tắt hội thoại khi context gần đầy, để không tràn.
Script này chỉnh 2 thứ trong settings.json:
  • autoCompactWindow      — MỐC token để bắt đầu compact (số tuyệt đối)
  • env.DISABLE_AUTO_COMPACT — công tắc TẮT HẲN tính năng

Ngưỡng thực = min(autoCompactWindow, max context của model).
  Opus context ~200k → set 190000 = compact ở 190k (~95%).

Cú pháp:
  claude-auto-compact.sh [--global|--project] <command>

Target (mặc định --global):
  --global     ~/.claude/settings.json   (áp mọi project)
  --project    ./.claude/settings.json   (chỉ project hiện tại, đè global)

═══════════════════════════════════════════════════════════════════
 SET MỐC xxk  (compact sớm/muộn)
═══════════════════════════════════════════════════════════════════
  set <tokens>   Đặt autoCompactWindow. <tokens> là int > 0.
                 Số CÀNG NHỎ → compact CÀNG SỚM (giữ ít context, an toàn tràn).
                 Số càng lớn (sát 200k) → compact muộn, giữ nhiều context hơn.
     set 190000  →  compact ở 190k  (~95%, khuyến nghị cho task nặng)
     set 170000  →  compact ở 170k  (~85%, sớm hơn, dư địa an toàn)
     set 150000  →  compact ở 150k  (~75%, rất sớm)

  auto           Bỏ mốc cứng → Claude TỰ chọn window theo model.
                 (Anthropic khuyến nghị. Xoá key autoCompactWindow.)

═══════════════════════════════════════════════════════════════════
 MỞ / TẮT auto-compact  (bật tắt cả tính năng)
═══════════════════════════════════════════════════════════════════
  off            TẮT HẲN auto-compact → env.DISABLE_AUTO_COMPACT="1".
                 Claude KHÔNG tự tóm tắt nữa; bạn tự gõ /compact khi cần.
  on             MỞ lại auto-compact (xoá DISABLE_AUTO_COMPACT).

  Lưu ý: 'off' khác 'set/auto'. off = tắt tính năng; set/auto = chỉ đổi MỐC
  (tính năng vẫn bật). Có thể set mốc VÀ off cùng lúc — off sẽ thắng
  (đã off thì mốc không có tác dụng tới khi 'on' lại).

═══════════════════════════════════════════════════════════════════
 XEM
═══════════════════════════════════════════════════════════════════
  status         In autoCompactWindow + trạng thái on/off hiện tại.

VD nhanh:
  claude-auto-compact.sh set 190000          # global: compact ở 190k
  claude-auto-compact.sh --project set 170000 # chỉ project này
  claude-auto-compact.sh auto                 # trả về Claude tự quyết
  claude-auto-compact.sh off                  # tắt hẳn, tự /compact tay
  claude-auto-compact.sh on                   # bật lại
  claude-auto-compact.sh status               # kiểm tra
EOF
}

command -v jq >/dev/null 2>&1 || { echo "❌ cần jq — brew install jq" >&2; exit 1; }

# jq_write <file> <filter> [args...] — ghi in-place, ưu tiên sponge, fallback tmp+mv.
jq_write() {
  local f="$1"; shift
  local tmp; tmp="$(mktemp)"
  jq "$@" "$f" >"$tmp" && mv "$tmp" "$f"
}

# --- parse target flag ---
TARGET="global"
case "${1:-}" in
  --global)  TARGET="global"; shift ;;
  --project) TARGET="project"; shift ;;
esac

if [ "$TARGET" = "project" ]; then
  S="$PWD/.claude/settings.json"
else
  S="$HOME/.claude/settings.json"
fi

CMD="${1:-}"; shift || true
[ -n "$CMD" ] || { usage; exit 1; }

# đảm bảo file tồn tại + là JSON hợp lệ (tạo {} nếu thiếu)
mkdir -p "$(dirname "$S")"
[ -f "$S" ] || echo '{}' >"$S"
jq empty "$S" >/dev/null 2>&1 || { echo "❌ $S không phải JSON hợp lệ" >&2; exit 1; }

case "$CMD" in
  set)
    TOK="${1:-}"
    [[ "$TOK" =~ ^[0-9]+$ ]] && [ "$TOK" -gt 0 ] || {
      echo "❌ set cần int > 0 (VD: set 190000)" >&2; exit 1; }
    jq_write "$S" --argjson n "$TOK" '.autoCompactWindow = $n'
    echo "✅ autoCompactWindow = $TOK  ($S)"
    ;;
  auto)
    jq_write "$S" 'del(.autoCompactWindow)'
    echo "✅ về AUTO — xoá autoCompactWindow  ($S)"
    ;;
  off)
    jq_write "$S" '.env.DISABLE_AUTO_COMPACT = "1"'
    echo "✅ TẮT auto-compact (DISABLE_AUTO_COMPACT=1)  ($S)"
    ;;
  on)
    jq_write "$S" 'if .env then .env |= del(.DISABLE_AUTO_COMPACT) else . end
                   | if (.env // {}) == {} then del(.env) else . end'
    echo "✅ BẬT lại auto-compact  ($S)"
    ;;
  status)
    echo "file: $S"
    echo "  autoCompactWindow   : $(jq -r '.autoCompactWindow // "auto (unset)"' "$S")"
    echo "  DISABLE_AUTO_COMPACT: $(jq -r '.env.DISABLE_AUTO_COMPACT // "unset (enabled)"' "$S")"
    ;;
  -h|--help|help)
    usage ;;
  *)
    echo "❌ command lạ: $CMD" >&2; usage; exit 1 ;;
esac
