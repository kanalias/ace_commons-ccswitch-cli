# General (cross-project, áp mọi turn)

## Ngôn ngữ

- **Mặc định: tiếng Việt** — mọi câu trả lời cho user (chat, report, câu hỏi xác nhận, tóm tắt), bất kể prompt/rule/tài liệu/tool output viết bằng ngôn ngữ nào.
- Giữ nguyên tiếng Anh cho: code, lệnh, tên file/biến/branch, log, commit message, thuật ngữ kỹ thuật không có từ Việt thông dụng.
- **User muốn đổi ngôn ngữ** (vd "trả lời bằng tiếng Anh", "from now on reply in English", "switch to English"):
  - Chỉ trong turn/task hiện tại → đổi tạm, KHÔNG sửa rule.
  - Đổi lâu dài ("từ giờ", "luôn", "mặc định", "from now on", "always") → áp ngay + **tự cập nhật** dòng "Mặc định" ở trên (sửa upstream `harness/templates/rules/common/general.md` nếu repo có harness, rồi sync sang `.claude/rules/common/general.md`), báo user 1 dòng đã đổi.
- Không suy diễn đổi ngôn ngữ chỉ vì user gõ prompt bằng ngôn ngữ khác — cần yêu cầu rõ.

## Thiếu quyền ghi file → viết sẵn lệnh cho user

- Cần thêm/sửa giá trị trong file mà AI không có quyền hoặc bị chặn (`.env*`, `secrets/`, file trên server, file ngoài workspace) → KHÔNG chỉ mô tả "bạn thêm dòng X vào file Y". Viết sẵn lệnh/script hoàn chỉnh trong 1 code block để user copy chạy ngay (theo skill `copy-data-cmd`).
- Lệnh phải idempotent: chạy lại không nhân đôi dòng (vd `grep -q '^KEY=' f || echo 'KEY=…' >> f`, hoặc thay thế nếu đã có). Kèm bước nạp lại nếu cần (restart service, `--update-env`).
- Giá trị là secret mà AI không biết → để placeholder `<điền-token>` rõ ràng, KHÔNG tự đọc/in secret ([[secrets-no-printout]]).

## Link → luôn clickable

- Nhắc tới URL/host/domain (local port, domain, link Notion, dashboard) trong câu trả lời → viết dạng markdown link có scheme đầy đủ, vd [http://localhost:6001](http://localhost:6001), [https://example.com](https://example.com).
- Ngoại lệ: bên trong code block / lệnh để copy chạy → giữ nguyên chuỗi gốc.

## Vận hành an toàn

- **Deploy → so tên biến env.** Trước/sau deploy so danh sách TÊN biến (không giá trị) giữa `.env` local và server; biến code dùng mà server thiếu → cảnh báo user + đưa lệnh thêm (mục trên).
- **Fail-open phải lên tiếng.** Code fallback mặc định khi thiếu config/env/Notion → ngoài `console.warn` còn gửi 1 alert `warn` qua `sendServiceAlert` (dedupe theo ngày). Fallback im lặng = lỗi ẩn nhiều ngày.
- **Config DB Notion có mô tả.** Mỗi DB/page config ghi trong phần description: ý nghĩa từng cột, giá trị hợp lệ, nguồn dữ liệu, độ trễ cache, cái gì phải sửa code. Thêm/đổi cột → cập nhật description cùng lúc.
- **Không đốt quota thật khi thử.** Chạy thử nhiều lần với API có quota (GitHub anonymous, LLM, Notion…) → cache response hoặc stub/mock; chỉ gọi thật ở lần verify cuối.
- **Preview trước khi gửi ra ngoài.** Hành động outward (gửi Telegram, ghi Notion hàng loạt, deploy) → dry-run in kết quả cho user xem trước, rồi mới chạy thật.

## Telegram service alert — format đồng nhất (BẮT BUỘC)

- Mọi alert/báo cáo Telegram của service/job/cron PHẢI đi qua `formatServiceAlert`/`sendServiceAlert` của `@acegalaxy/lib-ott-gateway/service-alert` (bash: CLI `service-alert`). Mẫu trong lib là nguồn duy nhất:
  `[<Env>][<Project>] [<icon> <status>] Service <service>` → `<title>` → `key: value` → `---` → detail
  Ví dụ: `[MacMini2][Crawler] [⏳ queued] Service nhadathue-tiktok`.
- `<Env>` = `HOST_LABEL`; `<Project>` + `<service>` tự gợi ý từ tên folder (git root / folder có `package.json`) ở lần dùng đầu rồi lưu `~/.config/acegalaxy/service-alert.json` (lib ≥ v0.9.0; đổi tên: `service-alert init`). `ALERT_PROJECT` / `--project` chỉ để ghi đè (vd container không có `.git`). Status ∈ `ok|fail|warn|info|queued|running`. Tên tự gợi ý > 16 ký tự được lib tự rút gọn (cắt từ dài nhất, giữ từ ngắn); muốn tên đẹp hơn → rút gọn tay nhưng vẫn giữ nguyên ý nghĩa, vd `share-fp2group-fb-personal` → `fp2g-fb-personal`; đặt bằng `service-alert init`.
- CẤM tự dựng chuỗi header, tự gọi `api.telegram.org`, hoặc fork format trong project. Cần đổi mẫu → sửa trong lib `lib-ott-gateway` + release tag, rồi bump version ở các project dùng.
