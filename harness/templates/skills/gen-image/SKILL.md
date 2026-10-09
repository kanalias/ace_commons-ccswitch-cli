---
name: gen-image
description: Tạo ảnh AI dùng chung mọi repo — gen qua proxy `ANTHROPIC_BASE_URL` (random `cx/gpt-image-2.5` / `cx/gpt-5.6-terra-image`; lỗi fallback model cx còn lại → `ag/gemini-3.1-flash-image` → `gemini/gemini-3-pro-image-preview`), crop nhiều size, overlay tuỳ chọn tiêu đề/phụ đề/footer/logo. Dùng /gen-image <prompt> [size...], hoặc khi user nói "tạo ảnh", "gen ảnh", "generate image", "ảnh banner/thumbnail/post".
user-invocable: true
---

# /gen-image — Generator ảnh dùng chung

## Các bước

1. **Prompt**: mô tả chủ thể (EN). Style mặc định navy/isometric + "no text, no logos" tự nối; `--style "<s>"` thay, `--no-style` bỏ.
2. **Chạy** (≈1 phút/ảnh; nhiều ảnh → mỗi ảnh 1 lệnh background song song):
   ```
   python3 .claude/skills/gen-image/gen.py "<prompt>" \
     [--size 1200x628 --size 1080x1080 ...] [--out <dir>] [--name img] \
     [--title "..."] [--subtitle "..."] [--footer "..."] [--logo path/logo.png]
   ```
   Output: `<out>/<name>-raw.jpg` + `<name>-<W>x<H>.jpg` mỗi size. Khung gen theo aspect size đầu tiên.
   Size thường dùng: LinkedIn 1200x628, FB/IG vuông 1080x1080, story 1080x1920, OG 1200x630.
3. **Review**: `Read` ảnh. Có chữ lạ / vật thể sai ý → gen lại.

## Lưu ý

- Key + endpoint đọc `~/.claude/settings.json` `.env.ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` (proxy OpenAI-compatible có `/images/generations`, vd sau `ccswitch`) lúc chạy, KHÔNG in key.
- Output mặc định: env `GEN_IMAGE_OUT` → Shared drive `media` của Google Drive đã mount (`~/Library/CloudStorage/GoogleDrive-*/Shared drives/media`) → `./gen-image-out`; `--out` để đổi.
- Cần: `python3` + Pillow (`pip3 install pillow`), font macOS Arial Bold (chỉ khi overlay chữ). Không commit vào repo trừ khi user yêu cầu.
- Logo/nội dung theo repo truyền qua tham số; rule nội dung riêng repo (vd careers-content) vẫn áp.
- Self-check: `gen.py --selftest`.
