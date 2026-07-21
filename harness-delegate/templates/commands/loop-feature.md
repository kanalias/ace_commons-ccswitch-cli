---
name: loop-feature
description: Runs iterative code → fix → write testcase → test loop for an assigned task until it's genuinely done (tests green, acceptance criteria met). Use when user says "làm tới khi xong", "loop code test fix cho đến khi hoàn thiện", "cứ lặp sửa cho tới khi pass", or runs /loop-feature <task>. Not for one-shot edits — only for tasks that need repeated implement/verify cycles.
user-invocable: true
---

# loop-feature — implement/fix/test cho tới khi task xong thật

Vòng lặp: viết/sửa code → viết testcase → chạy test → nếu fail thì tìm root cause rồi sửa tiếp → lặp lại tới khi tất cả test pass và acceptance criteria của task đã đạt. Không dừng ở "trông có vẻ đúng" — chỉ dừng khi verify chạy thật pass.

Method dùng ở đây build trên [skill-superpowers.md](../rules/skill-superpowers.md) (TDD red-green-refactor + systematic debugging, lazy-load khi chạm code source) — không lặp lại nội dung, chỉ áp dụng thành loop cụ thể.

## Input cần có

Task mô tả rõ (từ user) + acceptance criteria.

- **Không có mô tả tính năng nào** (chạy `/loop-feature` trơn, hoặc arg rỗng/chỉ là placeholder) → hỏi ngay user tính năng cần làm là gì, KHÔNG tự đoán, KHÔNG bắt đầu loop.
- Có mô tả tính năng nhưng thiếu acceptance criteria rõ ràng → suy ra từ task + code hiện có, không hỏi lại nếu Auto Mode cho phép tự quyết; chỉ hỏi khi task mơ hồ tới mức không đoán được "xong" nghĩa là gì.

## Vòng lặp (lặp lại từ bước 2 tới khi xong)

1. **Hiểu task + baseline.** Đọc code/test liên quan trong scope. Xác định acceptance criteria cụ thể (input→output đúng là gì).
2. **RED — viết testcase trước khi sửa code chính.** Test phải fail đúng lý do (chưa có behavior, không phải lỗi test). Theo pattern test có sẵn trong repo (tìm file test tương tự cùng thư mục/module trước khi viết mới).
3. **GREEN — code tối thiểu cho test pass.** Không thêm gì ngoài yêu cầu.
4. **Chạy test suite thật:** @@TEST_CMD@@ (hoặc file test cụ thể vừa sửa). Không suy đoán kết quả — chạy và đọc output.
5. **Fail?** → Đây là debugging thật, không phải "thử lại": reproduce lỗi chính xác, isolate vùng sai (bisect log/code), xác định root cause (giải thích được VÌ SAO sai), sửa đúng chỗ đó, quay lại bước 4.
6. **Pass?** → Kiểm tra còn thiếu edge case nào của acceptance criteria không (lỗi input, giá trị biên, guard cũ). Thiếu → quay lại bước 2 cho case đó.
7. **Refactor** (dọn code) chỉ khi test đang xanh; chạy lại bước 4 sau refactor để confirm vẫn xanh.
8. Đủ acceptance criteria + tất cả test pass → thoát loop, sang Report.

## Guard chống loop vô hạn

- Tối đa 3 lần fail liên tiếp trên CÙNG một lỗi → dừng, báo user thay vì thử thêm (nghi ngờ spec sai hoặc thiếu thông tin, không phải thiếu effort).
- Mỗi vòng phải có thay đổi thật (code hoặc test) — nếu chạy lại y hệt không sửa gì mà mong kết quả khác, dừng lại và chẩn đoán lại từ bước 5.

## Report

- Task nào đã hoàn thiện, bao nhiêu vòng lặp, test nào được thêm/sửa.
- Lệnh verify cuối cùng đã chạy + kết quả (pass/fail thật, không phải suy đoán).
- Nếu dừng do guard (chưa xong) → nói rõ đang kẹt ở đâu, cần gì từ user để tiếp tục.
