---
name: feature-redflags
description: Safe minimal changes + RED FLAGS cognitive wedge — câu tự bào chữa để skip quy trình → STOP
status: live
updated: 2026-07-16
metadata:
  type: reference
---

# Feature — Safe Minimal Changes + RED FLAGS (cross-project)

## Safe minimal changes

- Chỉ sửa phần cần cho task; tránh refactor lan hoặc thêm file không cần.
- Không tạo file `.md` mới (kể cả README) trừ khi user yêu cầu rõ.
- Không commit secret; không hardcode API key/chat_id — dùng env + config hiện có.

## RED FLAGS — dấu hiệu đang rationalize → STOP

| Suy nghĩ (Rationalization) | Thực tế (Reality) |
|---|---|
| "Task đơn giản, không cần plan" | Việc đơn giản vẫn là task. Plan lock interface trước khi code. |
| "Explore code trước rồi tính" | Đọc rule scope trước, explore sau. |
| "Mình nhớ rule này rồi" | Rule có thể đã đổi. Đọc lại file rule trong scope hiện tại. |
| "Task không cần test" | Task **đổi behavior code** không test = chưa xong: ≥1 happy + ≥1 edge/error, cùng commit. (Size-S thuần config/rename/doc miễn.) |
| "Cứ thử fix xem sao" | Fix chưa biết root cause = thrashing. Investigate → root cause → fix → verify. |
| "Chỉ sửa 1 dòng, không cần audit" | Audit (grep hardcode, scope leak, secret) là gate trước commit, không tuỳ diff size. |
| "File ngoài scope đọc tham khảo thôi" | Nếu project có scope-isolation rule: đọc = vi phạm. Cần thật → dừng, hỏi user whitelist. |
| "Mock cho nhanh, lát fix sau" | "Lát fix sau" thường không xảy ra. Phải mock → ghi rõ + follow-up todo. |
| "User chắc OK với cách này" | Đừng đoán ý user. Vượt scope task gốc → hỏi xác nhận. |
| "Code trông đúng rồi" | "Trông đúng" ≠ "chạy đúng". Phải có verify step đã chạy thành công. |
| "Refactor luôn cho gọn" | Refactor ngoài scope = block merge. Tách PR riêng. |
| "Skip hook --no-verify cho nhanh" | Hook fail = có lý do. Investigate root cause, không bypass. |
| "Code trước plan đỡ phí thời gian" | Task M trở lên: code trước plan = rework, đợi plan approve. (Size-S làm trực tiếp, không cần plan.) |
| "Subagent tự lo, prompt ngắn được" | Subagent không có session context. Prompt self-contained: spec + paths + verify (xem [[orchestrator]]). |

**Cách dùng:** trước mỗi action lớn (edit, dispatch subagent, commit, merge) rà nhanh bảng. Match 1 dòng → áp "Reality". Cognitive wedge, không phải checklist tick.
