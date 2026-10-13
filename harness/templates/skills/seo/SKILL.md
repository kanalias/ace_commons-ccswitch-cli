---
name: seo
description: Google Search Console + Bing Webmaster Tools qua subagent browser Cloak — sitemap, index, URL Inspection, Performance. Dữ kiện site đọc từ `.claude/seo-targets.md` của project. Dùng khi user gõ /seo [report|inspect <url>|daily], hoặc hỏi "Google/Bing index chưa", "check Search Console / Bing Webmaster".
user-invocable: true
context: fork
agent: browser-web
background: false
---

# /seo — Search Console + Bing Webmaster

Không có yêu cầu → chạy `report`. Agent mặc định `browser-web` (Cloak chung). Project có agent riêng (vd `browser-seo`, tự tạo, profile riêng cho Google) → ghi tên vào `seo-targets.md` và đổi `agent:` ở frontmatter bản cài của project.

## Dữ kiện theo project (harness không cài, không ghi đè)

Đọc `.claude/seo-targets.md` trước mọi bước. File vắng, hoặc còn `<...>` chưa điền → **dừng**, in mẫu dưới đây cho user điền, không đoán giá trị, không mở browser.

```markdown
# SEO targets
- Domain site: <example.com>
- Search Console property: <sc-domain:example.com hoặc https://example.com/>
- Bing site: <https://example.com/>
- Sitemap URL: <https://www.example.com/sitemap.xml>
- Browser agent: <browser-web | browser-seo>
- Profile dir: <đường dẫn profile Cloak của agent, tương đối repo, vd .browser-profiles/prj_<slug>_sv_seo>
```

## Browser contract

1. Mở browser qua agent khai báo trong file, đúng profile dir đã khai báo, headless.
2. Gặp màn đăng nhập Google/Bing → dừng, báo user tự đăng nhập trong profile đó. `manual_required` / `profile_in_use` / bất kỳ lỗi nào → dừng và báo; không bypass captcha/2FA, không kill process, không xoá lock.
3. Đọc số liệu bằng đọc nội dung trang; tìm theo text menu, không hardcode ref.
4. Không lấy/in cookie, token. Đóng browser khi xong hoặc dừng.

## Chế độ

| Lệnh | Việc | Ghi ra ngoài? |
|---|---|---|
| `report` (mặc định) | GSC: Sitemaps (status, last read, discovered), Pages (Indexed / Not indexed + lý do), Performance 28 ngày. Bing: Sitemaps, Site Explorer (indexed, crawl errors), Search Performance | không, read-only |
| `inspect <url>` | URL Inspection GSC + Bing: indexed?, canonical, last crawl, lỗi | không |
| `daily` | Chạy tự động, không ai confirm — xem dưới | không, chỉ ghi file báo cáo local |
| submit sitemap / request indexing | Chỉ khi user yêu cầu rõ trong session | có — confirm user trước |

## `daily` (không người giám sát)

1. Login hỏng → ghi báo cáo `status: blocked` + lý do, dừng.
2. Chạy `report`, so với báo cáo `daily` gần nhất → delta (indexed / not-indexed, clicks, impressions, crawl errors).
3. Đề xuất tối đa 5 việc, xếp theo tác động, mỗi việc ghi file/route cần sửa. Sitemap "Couldn't fetch" mà cột Last read trống < 3 ngày → chỉ ghi "chờ Google fetch".
4. Ghi báo cáo vào thư mục docs của project (`docs/seo/daily-YYYY-MM-DD.md`): `status`, bảng số liệu + delta, lỗi/cảnh báo, việc đề xuất.
5. **CẤM trong `daily`**: submit sitemap, Request indexing, Submit URL, đổi Settings/Crawl Control/Block URL, sửa code, commit, mọi ghi lên Google/Bing.
6. Tin nhắn cuối (stdout) ≤ 10 dòng tiếng Việt — runner chuyển tiếp đi.

## Tránh

- Xoá sitemap/site, Removals, Block URLs — chỉ khi user yêu cầu rõ + confirm.
- Dùng profile khác profile khai báo trong `seo-targets.md`.
