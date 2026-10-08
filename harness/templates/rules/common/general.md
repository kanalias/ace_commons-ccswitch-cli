# General (cross-project, áp mọi turn)

## Ngôn ngữ

- **Mặc định: tiếng Việt** — mọi câu trả lời cho user (chat, report, câu hỏi xác nhận, tóm tắt), bất kể prompt/rule/tài liệu/tool output viết bằng ngôn ngữ nào.
- Giữ nguyên tiếng Anh cho: code, lệnh, tên file/biến/branch, log, commit message, thuật ngữ kỹ thuật không có từ Việt thông dụng.
- **User muốn đổi ngôn ngữ** (vd "trả lời bằng tiếng Anh", "from now on reply in English", "switch to English"):
  - Chỉ trong turn/task hiện tại → đổi tạm, KHÔNG sửa rule.
  - Đổi lâu dài ("từ giờ", "luôn", "mặc định", "from now on", "always") → áp ngay + **tự cập nhật** dòng "Mặc định" ở trên (sửa upstream `harness/templates/rules/common/general.md` nếu repo có harness, rồi sync sang `.claude/rules/common/general.md`), báo user 1 dòng đã đổi.
- Không suy diễn đổi ngôn ngữ chỉ vì user gõ prompt bằng ngôn ngữ khác — cần yêu cầu rõ.

## Telegram service alert — format đồng nhất (BẮT BUỘC)

- Mọi alert/báo cáo Telegram của service/job/cron PHẢI đi qua `formatServiceAlert`/`sendServiceAlert` của `@acegalaxy/lib-ott-gateway/service-alert` (bash: CLI `service-alert`). Mẫu trong lib là nguồn duy nhất:
  `[<Env>][<Project>] [<icon> <status>] Service <service>` → `<title>` → `key: value` → `---` → detail
  Ví dụ: `[MacMini2][Crawler] [⏳ queued] Service nhadathue-tiktok`.
- `<Env>` = `HOST_LABEL`; `<Project>` + `<service>` tự gợi ý từ tên folder (git root / folder có `package.json`) ở lần dùng đầu rồi lưu `~/.config/acegalaxy/service-alert.json` (lib ≥ v0.9.0; đổi tên: `service-alert init`). `ALERT_PROJECT` / `--project` chỉ để ghi đè (vd container không có `.git`). Status ∈ `ok|fail|warn|info|queued|running`. Tên tự gợi ý > 16 ký tự được lib tự rút gọn (cắt từ dài nhất, giữ từ ngắn); muốn tên đẹp hơn → rút gọn tay nhưng vẫn giữ nguyên ý nghĩa, vd `share-fp2group-fb-personal` → `fp2g-fb-personal`; đặt bằng `service-alert init`.
- CẤM tự dựng chuỗi header, tự gọi `api.telegram.org`, hoặc fork format trong project. Cần đổi mẫu → sửa trong lib `lib-ott-gateway` + release tag, rồi bump version ở các project dùng.
