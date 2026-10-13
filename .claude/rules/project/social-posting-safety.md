---
name: social-posting-safety
description: Giới hạn khi đăng bài lên Facebook Page/Group/LinkedIn/TikTok bằng code hoặc agent — kênh hợp lệ, nhịp đăng tối đa, checklist mỗi bài, xử lý checkpoint. LAZY, load khi chạm code/skill/agent đăng bài.
status: live
updated: 2026-10-13
paths:
  - "**/*facebook*"
  - "**/*linkedin*"
  - "**/*tiktok*"
  - "**/*poster*"
  - ".claude/agents/browser-*.md"
  - ".claude/rules/project/social-posting-safety.md"
metadata:
  type: reference
---

# Social posting safety — giới hạn khi đăng bài

Rule này là GIỚI HẠN, không phải hướng dẫn cách đăng. Điều khoản nền tảng khảo sát 2026-10-09 — ngày đã cũ thì kiểm tra lại điều khoản hiện hành của từng nền tảng trước khi tin các mục dưới.

## Điều khoản (khảo sát 2026-10-09)

- Meta Terms of Service cấm truy cập bằng "automated means" khi chưa có phép bằng văn bản; Community Standards coi đăng/share tần suất rất cao, nội dung lặp lại là spam. Meta KHÔNG công bố ngưỡng.
- LinkedIn User Agreement cấm bot/automation để tạo, comment, like, share bài; cấm profile không phải người thật. Profile mang tên công ty dễ bị auto-logout rồi restricted.
- Lái browser (kể cả stealth) để đăng = vi phạm điều khoản nền tảng. Stealth chỉ giảm khả năng bị phát hiện, KHÔNG làm hoạt động này hợp lệ.

## Kênh được phép (theo thứ tự ưu tiên)

1. API chính thức của nền tảng (Graph API cho Page, Posts API cho Company Page) hoặc scheduler gốc (Meta Business Suite, hẹn giờ LinkedIn) hoặc đăng tay.
2. Browser automation: tạm thời, CHỈ khi user cho phép rõ từng lần, trên tài khoản/Page do user chỉ định, theo nhịp dưới.
3. Cấm: đăng bằng profile cá nhân mang tên tổ chức; đăng dồn cụm; caption giống hệt hàng loạt; dùng script đăng nhập lại hoặc vượt checkpoint. Group không có API → chỉ share tay hoặc bot theo nhịp, khi user cho start.
4. Chưa có kênh hợp lệ cho nền tảng đó (vd chưa có Company Page) → KHÔNG đăng bằng automation.

## Nhịp tối đa (số thận trọng, không phải ngưỡng chính thức)

| | Tối đa | Khoảng cách tối thiểu |
|---|---|---|
| FB Page | 2–3 bài/ngày | 2–3 giờ |
| FB Group (profile cá nhân) | 5–8 group/ngày; mỗi group ≤1 bài/tuần; profile mới 2–3/ngày trong 2 tuần đầu | 20–45 phút, jitter ngẫu nhiên |
| LinkedIn | 2 bài/ngày, 5–7 bài/tuần | 4 giờ |

- Nhiều bài cùng lúc → gom 1 album/carousel hoặc hẹn giờ trải nhiều ngày. KHÔNG đăng N bài liên tiếp.
- Mỗi bài caption riêng (không chỉ đổi tên); share group đổi câu mở đầu theo group.
- Giữ cố định thiết bị + profile + IP; không chạy song song 2 phiên cùng tài khoản (MCP và bot dùng chung profile → chỉ chạy 1).

## Checklist MỖI bài

1. Đếm bài đã đăng hôm nay + giờ bài gần nhất → vượt nhịp thì hẹn giờ / để hôm sau.
2. Tài khoản không dính block/checkpoint trong 48h (Facebook) / 7 ngày (LinkedIn) — check memory.
3. Không có phiên automation khác đang chạy cùng profile.
4. Caption khác các bài gần nhất; nội dung đã qua kiểm duyệt của project.
5. Đăng 1 bài → xác nhận (xem dưới) → mới tới bài kế, đúng khoảng cách tối thiểu.
6. Sự cố → dừng theo mục checkpoint, ghi memory.

## Xác nhận đăng thành công

Nút Post biến mất ≠ đã đăng. Sau mỗi bài phải kiểm tra bài thật sự xuất hiện (text caption) VÀ không có toast lỗi ("problem sharing", "going too fast", "temporarily blocked"). Fail → dừng cả lượt, không retry ngay.

## Gặp block / checkpoint / captcha / unusual-activity

1. Dừng NGAY mọi automation trên tài khoản đó; KHÔNG retry, KHÔNG đổi proxy/fingerprint để vượt.
2. User tự xác minh qua giao diện chính thức (browser headed, tay người).
3. Nghỉ automation ≥48h (Facebook) / ≥7 ngày (LinkedIn); những ngày đầu chỉ lướt xem, thao tác tay mức thấp.
4. Báo user + ghi memory trạng thái tài khoản.

## Hành động công khai không đảo ngược

Xoá bài / xoá thông tin đã đăng công khai → HỎI user trước, nêu rõ bài nào, tài khoản nào. Không tự quyết kể cả khi để dọn lỗi.

## Quảng cáo / boost

Ads thuộc danh mục đặc biệt (tuyển dụng, tài chính, nhà ở...) phải chọn đúng Special Ad Category của Meta; bài thường không boost chỉ cần tuân Community Standards.

Liên quan: [[browser-mcp-profiles]] (profile).
