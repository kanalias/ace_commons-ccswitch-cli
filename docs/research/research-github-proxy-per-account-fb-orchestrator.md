# Research: Proxy mã nguồn mở theo account cho framework orchestrator profile Facebook

- Ngày: 2026-10-05
- Phạm vi: project trước (bds-hue, kane-crawler qua khảo sát subagent + grep; repo ccswitch hiện tại), web/repository sau (WebSearch, WebFetch, `gh api` đọc metadata).
- Slug rút gọn từ chủ đề gốc (chủ đề dài vượt giới hạn tên file hợp lý).

## Mục tiêu và câu hỏi

Framework chung (lease/health/state machine) cho bds-hue + kane-crawler cần **proxy sticky 1:1 theo account**, fail-closed.

1. Hiện trạng proxy trong 2 project?
2. Chromium không nhận username/password nhúng trong `--proxy-server` → cần forwarder nội bộ hay dùng option native?
3. Công cụ OSS nào cho: forwarder, health/exit-IP/geo/ASN check, quản lý pool?
4. Căn chỉnh timezone/locale/WebRTC với exit IP: CloakBrowser đã có sẵn gì?

## Brainstorm và findings

**Hiện trạng project (fact, có bằng chứng):**
- kane-crawler: không có proxy theo profile; chỉ `AI_GATEWAY_PROXY_CONFIG` cho LLM gateway (báo cáo subagent). Grep `proxy-server|proxyUrl|PROXY_URL|socks5|--proxy` trên code/config không ra kết quả (2026-10-05).
- bds-hue: không có proxy theo profile (grep tương tự; chỉ khớp từ "proxy" trong file SEO không liên quan).
- Cả hai dùng chung host/IP, dùng CloakBrowser persistent context, fingerprint seed `<profile>/.fingerprint-seed`, locale vi-VN, timezone Asia/Ho_Chi_Minh.
- Repo ccswitch: `install-9router-proxy.sh` là proxy LLM, không liên quan.

**Phát hiện ngoài:**
- CloakBrowser (wrapper JS/Python) nhận option `proxy` là URL HTTP hoặc SOCKS5 (credential nằm trong URL, theo README), có `geoip: true` (tự suy ra timezone/locale từ exit IP, cần dependency geoip tùy chọn, gọi HTTP qua proxy, timeout mặc định 5 giây) và tự thêm `--fingerprint-webrtc-ip` khi bật geoip. `launchPersistentContext` hỗ trợ cùng option. → Phần căn chỉnh geo/WebRTC **đã có sẵn**, framework chỉ cần truyền proxy + kiểm chứng, không cần tự viết.
- Playwright native: trường `username`/`password` riêng trong object `proxy`; Chromium bỏ qua credential nhúng trong URL (nguồn thứ cấp, chưa đối chiếu docs chính thức). Có mâu thuẫn nhỏ với README CloakBrowser (credential trong URL) → **cần test thực tế** với CloakBrowser trước khi chốt.
- apify/proxy-chain: `anonymizeProxy()` mở local proxy không mật khẩu, forward lên upstream có auth (HTTP/HTTPS/SOCKS4/4a/5), `closeAnonymizedProxy()`. Chỉ Basic auth. Là fallback sạch nếu launcher không nhận credential trực tiếp.
- gost (MIT, v3.3.0) và 3proxy: forwarder ngoài tiến trình, hợp khi cần proxy-bridge dạng sidecar, dùng chung nhiều ngôn ngữ (có cả Python driver `lib-facebook-auth`). glider là GPL-3.0 → tránh nhúng/phân phối chung.
- Checker: các CLI/lib (proxycheck-cli, proxyprobe, Scrapium/proxy-scraper-checker, 1ort/checkr) đo liveness, latency, exit IP, ASN/geo; đa số hướng proxy public list, **không hợp** với proxy trả phí sticky. Với sticky 1:1 chỉ cần 1 probe nhỏ tự viết (gọi endpoint IP-echo qua proxy, so ASN/country), không cần thêm dependency.
- Rủi ro license: binary CloakBrowser v148+ cần subscription Pro (wrapper MIT). Release mới nhất tag `-pro`. Cần xác nhận bản đang dùng có hợp lệ.

## Nguồn

| Nguồn | Ý tưởng/phát hiện | Quyết định | License | Commit/tag | Provenance |
|---|---|---|---|---|---|
| CloakHQ/CloakBrowser | proxy + geoip + webrtc-ip + persistent context sẵn có | Áp dụng — dùng native, không bọc lại | MIT (wrapper); binary v148+ cần Pro | chromium-v152.0.7977.82.1-pro (2026-09-23) | tham khảo |
| apify/proxy-chain | `anonymizeProxy` local forwarder cho upstream auth | Áp dụng có điều kiện — chỉ nếu native auth lỗi | Apache-2.0 | v3.0.1 (2026-09-08) | tham khảo |
| go-gost/gost | forwarder/chain độc lập tiến trình | Dự phòng — sidecar nếu cần dùng chung đa ngôn ngữ | MIT | v3.3.0 (2026-08-30) | tham khảo |
| 3proxy/3proxy | forwarder nhẹ | Bỏ qua — license `NOASSERTION` trên API, chưa xác minh | chưa xác minh | 1.0.0 (2026-08-22) | tham khảo |
| nadoo/glider | forwarder, load-balance | Bỏ qua — GPL-3.0, không cần thiết | GPL-3.0 | v0.16.4 (2024-08-14) | tham khảo |
| MetaCubeX/mihomo | proxy kernel theo rule | Bỏ qua — quá nặng cho sticky 1:1 | MIT | v1.19.32 (2026-09-30) | tham khảo |
| proxycheck-cli / proxyprobe / Scrapium/proxy-scraper-checker / 1ort/checkr | ý tưởng probe: liveness, latency, exit IP, ASN, geo | Lấy ý tưởng — tự viết probe nhỏ | chưa xác minh | chưa xác minh | lấy ý tưởng |
| Playwright docs + bài hướng dẫn thứ cấp (shifter.io, browserstack) | `proxy.{server,username,password}`; per-context cần placeholder `per-context` | Lấy ý tưởng — kiểm chứng lại với docs chính thức | chưa xác minh | chưa xác minh | lấy ý tưởng |

## Phương án cherry-pick ý tưởng

- **Native-first:** orchestrator tạo `ProxyBinding{ref,type,geo}` từ registry, truyền vào `launchPersistentContext({proxy, geoip:true})`. Lợi ích: không thêm tiến trình. Rủi ro: cần test credential có hoạt động trong CloakBrowser.
- **Adapter forwarder (dự phòng):** interface `ProxyBridge.open(binding)` trả local URL, `close()` để đóng; cài đặt mặc định native, cài đặt thay thế dùng `proxy-chain`. Chỉ bật khi test native fail. Vòng đời bridge gắn vào lease (mở khi acquire, đóng khi release).
- **Probe exit-IP tự viết** trong module `health`: kiểm tra liveness, exit IP, country, ASN so với `ProxyGeo`; lưu `lastExitIP/lastASN`; đổi ngoài dự kiến → pause. Fail-closed, không fallback IP máy.
- **State machine:** thêm `proxy_down`, thoát chỉ qua đổi proxy thủ công trong registry (giữ sticky).
- **Lease key kép:** khóa theo `profile` và `proxy` để chống 2 account/2 project dùng chung một proxy.
- **Hook gate:** mở rộng `pre-browser-profile-gate.sh` chặn launch thiếu proxy khi `RequireProxy`.

## Quyết định và kết luận

- Không cần framework proxy riêng: **dùng native của CloakBrowser** (proxy + geoip + WebRTC), cộng probe tự viết. `apify/proxy-chain` (Apache-2.0) là adapter dự phòng; gost là sidecar thay thế. Tránh glider (GPL-3.0).
- Credential proxy lưu `.env`/vault theo slug (biến `PROXY_URL_<SLUG>`), Notion chỉ giữ `ProxyRef`.
- Migrate account hiện có sang proxy cần từng account một, cùng thành phố/ISP, có hạn mức reauth (reauth đốt recovery code dùng một lần).

## Giới hạn và chưa xác minh

- chưa xác minh: cách CloakBrowser xử lý credential proxy (trong URL hay trường riêng), cần chạy thử.
- chưa xác minh: tác động của đổi IP lên checkpoint Facebook (chỉ suy luận từ khảo sát).
- chưa xác minh: license/commit của proxycheck-cli, proxyprobe, Scrapium/proxy-scraper-checker, 1ort/checkr; license thật của 3proxy (API trả `NOASSERTION`).
- chưa xác minh: đối chiếu Playwright docs chính thức (chỉ đọc bài thứ cấp qua kết quả tìm kiếm).
- chưa xác minh: dự án đang dùng binary CloakBrowser bản nào và có subscription Pro không.
- Chưa tìm nhà cung cấp proxy cụ thể (residential/mobile VN) và chưa đọc ruột `lib-browser-crawler`, `lib-facebook-auth`.
- Bằng chứng project dựa trên báo cáo subagent + grep, chưa đọc trực tiếp từng file.
