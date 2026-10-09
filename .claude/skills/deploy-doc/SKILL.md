---
name: deploy-doc
description: "Dùng khi thay đổi làm lệch tài liệu deploy của service (env bắt buộc, lịch/cron, process manager, host, quy trình deploy), khi thêm service mới, hoặc khi vừa deploy xong. Gọi /deploy-doc <service>|all|--check."
user-invocable: true
---

# deploy-doc — tạo/cập nhật `deploy.md` ở thư mục gốc từng service

Mỗi service (đơn vị deploy được) có một `deploy.md` ở thư mục gốc của nó, gồm 3 phần: phần riêng của service, phần quy trình deploy chung, bảng nhật ký thay đổi.

Repo không deploy lên host nào (thư viện, tool chạy local) → báo "không áp dụng" rồi dừng, không tạo file.

## Tham số

- `<service>`: chỉ service đó.
- `all`: mọi service.
- `--check`: chỉ báo file nào lệch, không sửa.

## Cấu hình theo project (harness không ghi đè 2 file này)

- `.claude/skills/deploy-doc/project.md` — khai báo: glob thư mục service, danh sách nguồn sự thật, heading mở đầu và heading kết thúc của phần chung, file mẫu bố cục.
- `.claude/skills/deploy-doc/deploy-common.md` — bản duy nhất của phần quy trình deploy chung.

Chưa có `project.md` → lần chạy đầu: dò thư mục service (vd `src/features/*`, `services/*`, `apps/*`, `packages/*`; repo một service → gốc repo), dò nguồn sự thật (skill `deploy-*` / `production-deploy` của project, cấu hình PM2/systemd/docker/CI, chỗ code validate env, file lịch/cron), trình user xác nhận một lần rồi ghi `project.md`. Chưa có `deploy-common.md` → soạn từ skill deploy của project, user xác nhận rồi ghi.

## Các bước

1. Đọc `project.md`, rồi đọc lại nguồn sự thật — không dựa trí nhớ.
2. **Phần riêng** (cách service chạy, lịch, env bắt buộc, phiên đăng nhập/credential cần có, cách kiểm tra sau deploy, cách chạy lại): so từng giá trị với nguồn sự thật, sửa chỗ lệch. Service mới → theo bố cục file mẫu khai báo trong `project.md`.
3. **Phần chung**: chép nguyên văn từ `deploy-common.md`. Quy trình đổi → sửa `deploy-common.md` trước, rồi chép lại vào **mọi** `deploy.md`.
4. **Nhật ký thay đổi** (bảng cuối file): thêm 1 dòng `| YYYY-MM-DD | <đổi gì, 1 câu> |`. Chỉ ghi thay đổi ảnh hưởng deploy/vận hành; refactor và sửa logic nghiệp vụ đã có `git log`. Không sửa dòng cũ.
5. **Verify**: phần chung của mọi `deploy.md` trùng md5 với `deploy-common.md`; mọi tên env/service nhắc tới grep ra được trong code hoặc README.

## Ràng buộc

- Không đọc `.env*`. Chỉ ghi **tên** biến; không IP, token, chat id, id nội bộ.
- Giá trị không kiểm chứng được từ nguồn sự thật → bỏ, không đoán.
- Project chặn main agent ghi vào thư mục source → ghi `deploy.md` qua delegate subagent; main agent soạn nội dung và review.
- Cập nhật `deploy.md` trong cùng commit với thay đổi gây lệch.
- Chỉ sửa tài liệu; skill này không chạy deploy.

## Report

Bảng: file → mục đã sửa → dòng nhật ký đã thêm; kèm kết quả so md5 phần chung.
