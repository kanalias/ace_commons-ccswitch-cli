# General (cross-project, áp mọi turn)

## Ngôn ngữ

- **Mặc định: tiếng Việt** — mọi câu trả lời cho user (chat, report, câu hỏi xác nhận, tóm tắt), bất kể prompt/rule/tài liệu/tool output viết bằng ngôn ngữ nào.
- Giữ nguyên tiếng Anh cho: code, lệnh, tên file/biến/branch, log, commit message, thuật ngữ kỹ thuật không có từ Việt thông dụng.
- **User muốn đổi ngôn ngữ** (vd "trả lời bằng tiếng Anh", "from now on reply in English", "switch to English"):
  - Chỉ trong turn/task hiện tại → đổi tạm, KHÔNG sửa rule.
  - Đổi lâu dài ("từ giờ", "luôn", "mặc định", "from now on", "always") → áp ngay + **tự cập nhật** dòng "Mặc định" ở trên (sửa upstream `harness/templates/rules/common/general.md` nếu repo có harness, rồi sync sang `.claude/rules/common/general.md`), báo user 1 dòng đã đổi.
- Không suy diễn đổi ngôn ngữ chỉ vì user gõ prompt bằng ngôn ngữ khác — cần yêu cầu rõ.

## Cách làm việc

- **Chạy liền mạch.** User nói "tiếp tục" / "làm hết" / "làm lần lượt" / "tự làm, đã có quyền" → làm hết các bước còn lại, không dừng hỏi giữa chừng. Vẫn dừng hỏi trước deploy, push, xoá, ghi data nhạy cảm.
- **Báo "xong" kèm bằng chứng.** Nêu đã verify gì trên môi trường thật (trang live, log, Telegram, output test) — không chỉ "code đã sửa". Task nhiều bước → 1 tóm tắt ngắn cuối, không rải nhiều báo cáo dài.
- **Tự ghi memory.** Gặp quyết định / cấu hình / quy ước mới user chốt → tự ghi memory ngay, không đợi user nói "ghi nhớ".
- **Đổi tên → sweep 1 lần.** Đổi tên host / service / profile / env → grep + sửa hết repo, skill, docs, memory, Notion trong cùng lượt; báo danh sách chỗ đã đổi. Không sửa rải rác theo từng lần user nhắc.
- **Không hardcode.** Path, model, profile, ID, URL không gắn cứng trong code — lấy từ env / Notion config / convention (vd `resolveServiceProfilePath`). Secret xem [[secrets-no-printout]].

## Tên biến `.env` / config — PREFIX = supplier (BẮT BUỘC)

Quy tắc chung, áp MỌI supplier (danh sách mở, không giới hạn: Anthropic/Claude, OpenAI, Google, Facebook/Meta, Cloudflare, Notion, Telegram, AWS, GitHub, TikTok, Zalo…).

- Format: `<SUPPLIER>_<LOẠI>_<MỤC_ĐÍCH>`, viết HOA, `_` ngăn cách. Mọi biến trong `.env*` và config (JSON/YAML, Notion config) PHẢI có PREFIX supplier.
  - Đúng: `NOTION_TOKEN_VAULT`, `NOTION_PAGE_CONFIG_ID`, `TELEGRAM_BOT_TOKEN_ALERT`, `TELEGRAM_CHANNEL_ALERT_ID`, `ANTHROPIC_API_KEY`, `CLOUDFLARE_API_TOKEN_DNS`, `GOOGLE_OAUTH_CLIENT_ID`, `FACEBOOK_PAGE_TOKEN_SHOP`.
  - Sai: `TOKEN`, `BOT_TOKEN`, `CHAT_ID`, `PAGE_ID`, `API_KEY`, `VAULT_TOKEN` (không rõ supplier).
- **Tự detect supplier** khi thêm biến — không hỏi user: suy từ SDK/package import, domain URL gọi tới (`api.cloudflare.com` → `CLOUDFLARE_`), docs vendor. Supplier có tên env chuẩn chính thức (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `GITHUB_TOKEN`) → dùng đúng tên đó để SDK tự đọc.
- **Dò trước, tạo sau:** grep `.env.example` + code xem supplier đã có prefix chưa → có thì dùng lại đúng prefix đó (không tạo biến thể `CF_` khi repo đã dùng `CLOUDFLARE_`); chưa có → tạo prefix mới theo tên supplier đầy đủ, phổ biến nhất.
- Config AI không gắn 1 supplier (chọn model, routing, gateway/proxy đa provider) → prefix `AI_` (vd `AI_MODEL_DEFAULT`, `AI_GATEWAY_URL`).
- Nhiều instance cùng supplier → hậu tố mục đích, KHÔNG đánh số mơ hồ (`TELEGRAM_BOT_TOKEN_ALERT`, không `TELEGRAM_BOT_TOKEN_2`).
- Biến nội bộ app (không thuộc supplier) → prefix tên project/app (vd `CRAWLER_CONCURRENCY`). Biến chuẩn ecosystem (`NODE_ENV`, `PORT`, `HOST_LABEL`) giữ nguyên.
- Thêm biến mới → ghi luôn vào `.env.example` (tên + comment supplier/mục đích, KHÔNG value thật). Biến cũ sai convention → đề xuất rename (sweep theo mục "Đổi tên → sweep 1 lần"), không tự đổi khi chưa hỏi vì ảnh hưởng `.env` trên server.

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
- **Vượt scope project → hỏi 1 lần.** Sửa/commit/push/release ở repo khác ngoài project đang mở (vd lib dùng chung) → hỏi user đồng ý 1 lần (nêu repo + việc định làm); đã đồng ý → làm tiếp repo đó suốt session, không hỏi lại. Chỉ đọc tham khảo thì không cần hỏi.
- **Preview trước khi gửi ra ngoài.** Hành động outward (gửi Telegram, ghi Notion hàng loạt, deploy) → dry-run in kết quả cho user xem trước, rồi mới chạy thật.

## Telegram service alert — format đồng nhất (BẮT BUỘC)

- Mọi alert/báo cáo Telegram của service/job/cron PHẢI đi qua `formatServiceAlert`/`sendServiceAlert` của `@acegalaxy/lib-ott-gateway/service-alert` (bash: CLI `service-alert`). Mẫu trong lib là nguồn duy nhất:
  `[<Env>][<Project>] [<icon> <status>] Service <service>` → `<title>` → `key: value` → `---` → detail
  Ví dụ: `[MacMini2][Crawler] [⏳ queued] Service nhadathue-tiktok`.
- `<Env>` = `HOST_LABEL`; `<Project>` + `<service>` tự gợi ý từ tên folder (git root / folder có `package.json`) ở lần dùng đầu rồi lưu `~/.config/acegalaxy/service-alert.json` (lib ≥ v0.9.0; đổi tên: `service-alert init`). `ALERT_PROJECT` / `--project` chỉ để ghi đè (vd container không có `.git`). Status ∈ `ok|fail|warn|info|queued|running`. Tên tự gợi ý > 16 ký tự được lib tự rút gọn (cắt từ dài nhất, giữ từ ngắn); muốn tên đẹp hơn → rút gọn tay nhưng vẫn giữ nguyên ý nghĩa, vd `share-fp2group-fb-personal` → `fp2g-fb-personal`; đặt bằng `service-alert init`.
- CẤM tự dựng chuỗi header, tự gọi `api.telegram.org`, hoặc fork format trong project. Cần đổi mẫu → sửa trong lib `lib-ott-gateway` + release tag, rồi bump version ở các project dùng.
