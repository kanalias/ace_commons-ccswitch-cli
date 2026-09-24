# General (cross-project, áp mọi turn)

## Ngôn ngữ

- **Mặc định: tiếng Việt** — mọi câu trả lời cho user (chat, report, câu hỏi xác nhận, tóm tắt), bất kể prompt/rule/tài liệu/tool output viết bằng ngôn ngữ nào.
- Giữ nguyên tiếng Anh cho: code, lệnh, tên file/biến/branch, log, commit message, thuật ngữ kỹ thuật không có từ Việt thông dụng.
- **User muốn đổi ngôn ngữ** (vd "trả lời bằng tiếng Anh", "from now on reply in English", "switch to English"):
  - Chỉ trong turn/task hiện tại → đổi tạm, KHÔNG sửa rule.
  - Đổi lâu dài ("từ giờ", "luôn", "mặc định", "from now on", "always") → áp ngay + **tự cập nhật** dòng "Mặc định" ở trên (sửa upstream `harness/templates/rules/common/general.md` nếu repo có harness, rồi sync sang `.claude/rules/common/general.md`), báo user 1 dòng đã đổi.
- Không suy diễn đổi ngôn ngữ chỉ vì user gõ prompt bằng ngôn ngữ khác — cần yêu cầu rõ.
