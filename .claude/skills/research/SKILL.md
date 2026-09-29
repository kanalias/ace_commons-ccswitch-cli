---
name: research
description: Research một chủ đề từ project hiện tại trước, rồi đối chiếu nguồn web/repository bằng WebSearch/WebFetch; ghi report có provenance và quyết định tại docs/research/research-<slug>.md. Dùng /research <chủ đề>, "research", "nghiên cứu", "khảo sát giải pháp".
user-invocable: true
---

# research — khảo sát có provenance, ưu tiên project trước

Input: chủ đề trong `$ARGUMENTS`.

## Guard trước research

1. `$ARGUMENTS` rỗng hoặc chỉ có khoảng trắng → hỏi user chủ đề cần research rồi **dừng**. Không search, không đọc source, không tạo file.
2. Tạo `<slug>` ASCII kebab-case từ chủ đề: lowercase, chuyển ký tự có dấu sang ASCII gần nhất, thay chuỗi ký tự không phải `a-z0-9` bằng `-`, gộp `-` liên tiếp, bỏ `-` đầu/cuối. Slug rỗng → hỏi user một tên ASCII ngắn rồi dừng.
3. Đích cố định: `docs/research/research-<slug>.md`. **Preflight collision trước mọi research:** nếu file hoặc path đó đã tồn tại thì dừng, báo nguyên path. Không overwrite, append, đổi suffix hay tự chọn tên khác.

## Quy trình

### 1. Research project/repo hiện tại trước

- Đọc `CLAUDE.md`, README/MODULE/AGENTS liên quan và rule trong scope trước source.
- Grep code, test, dependency, config công khai, git remote/log cần thiết để xác định hiện trạng, constraint, giải pháp đã có và khoảng trống.
- Không đọc `.env*`, credentials, vault, private key, session hay file có thể chứa secret. Không in secret nếu vô tình gặp.
- Ghi lại file/symbol/commit làm bằng chứng; chưa đủ bằng chứng thì ghi literal `chưa xác minh`.

### 2. Brainstorm câu hỏi và hướng tìm

Từ hiện trạng project, chốt mục tiêu, câu hỏi cần trả lời, giả thuyết và tiêu chí so sánh. Tách rõ fact, suy luận, ý tưởng. Chưa kết luận trước khi đối chiếu nguồn ngoài.

### 3. Research web/repository sau

- Dùng **WebSearch** để tìm tài liệu chính thức, issue/PR/release và repository liên quan; dùng **WebFetch** để đọc nguồn đã chọn. Ưu tiên nguồn gốc, code/test/release notes hơn bài tổng hợp.
- Với repository: xác minh `owner/repo`, README/source liên quan, license, commit/tag nếu truy cập được. Không xác minh được trường nào thì ghi literal `chưa xác minh`; không suy đoán API, license hoặc quyền reuse.
- Chỉ trích đoạn ngắn cần thiết; chủ yếu diễn giải và dẫn URL. Không quote dài.
- Mỗi nguồn phải ghi: URL hoặc `owner/repo`; ý tưởng/phát hiện; `Áp dụng` hoặc `Bỏ qua` kèm lý do; license; commit/tag nếu có.
- Provenance repo phải ghi đúng quan hệ: `tham khảo`, `lấy ý tưởng`, `fork candidate`, hoặc `fork thực tế`. Chỉ ghi `fork thực tế` khi đã có bằng chứng repo thật sự được fork; không gọi là fork chỉ vì dự định hoặc copy ý tưởng.

### 4. Tổng hợp rồi mới ghi report

Chỉ sau khi research hoàn tất, tạo thư mục `docs/research/` nếu cần và ghi đúng một file đích đã preflight. Report:

```markdown
# Research: <chủ đề>

- Ngày: <ngày hiện tại>
- Phạm vi: <project/repo trước; web/repository sau>

## Mục tiêu và câu hỏi
...

## Brainstorm và findings
...

## Nguồn
| Nguồn | Ý tưởng/phát hiện | Quyết định | License | Commit/tag | Provenance |
|---|---|---|---|---|---|
| <URL hoặc owner/repo> | ... | Áp dụng/Bỏ qua — <lý do> | <license hoặc chưa xác minh> | <commit/tag hoặc chưa xác minh> | tham khảo/lấy ý tưởng/fork candidate/fork thực tế |

## Phương án cherry-pick ý tưởng
- <ý tưởng độc lập có thể áp dụng; file/module dự kiến; lợi ích; rủi ro>

## Quyết định và kết luận
...

## Giới hạn và chưa xác minh
...
```

`cherry-pick ý tưởng` nghĩa là chọn lọc concept/pattern; không mặc định chạy `git cherry-pick`, copy code, hay có quyền reuse.

## Không làm

- Không sửa source/config/test; không tạo fork; không commit, push hoặc publish.
- Không tự cài dependency, tạo script/hook/MCP hay gọi API cần secret.
- Không đọc/in secret. Không quote dài hoặc chép code đáng kể từ nguồn ngoài.
- Không tạo report nếu input rỗng, slug không hợp lệ, collision, hoặc research chưa chạy xong.

Kết thúc: báo path report, kết luận 1–3 dòng, các mục `chưa xác minh`. Không thực thi phương án đề xuất.
