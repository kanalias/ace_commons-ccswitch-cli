---
name: ace-library
description: Cập nhật + discovery thư viện nội bộ @acegalaxy/lib-* (acegalaxy-co) trong project ACE Galaxy. Không tham số → check lib đang dùng + nâng cấp nếu tương thích, rồi quét lib-* chưa dùng và đánh giá lib đáng tích hợp. Có yêu cầu → tìm lib cho tính năng đó. Dùng /ace-library [yêu cầu], "dùng ace library", "update ace library".
user-invocable: true
---

# ace-library — discovery + cập nhật thư viện nội bộ ACE Galaxy

Input: yêu cầu tính năng (`$ARGUMENTS`, có thể rỗng) + source/deps/lockfile/stack project hiện tại.

**Mode theo `$ARGUMENTS`:**

- **Rỗng (mặc định)** → KHÔNG hỏi lại user yêu cầu tính năng. Chạy ngay:
  1. **A** — kiểm tra lib `lib-*` đang dùng, nâng cấp nếu tương thích.
  2. **C** — quét toàn bộ `acegalaxy-co/lib-*` chưa dùng, đánh giá lib nào đáng tích hợp.
- **Có yêu cầu** → **A** rồi **B** (discovery cho tính năng đó).

Thứ tự ưu tiên: **code sẵn trong project → thư viện ACE Galaxy → thư viện ngoài
(qua [/dep-ladder-check](../dep-ladder-check/SKILL.md)) → tự viết phần còn thiếu.**

## Danh mục (điểm khởi đầu, KHÔNG phải bằng chứng)

**Quy ước tên:** mọi thư viện ACE Galaxy PHẢI có repo `acegalaxy-co/lib-<name>` và package
`@acegalaxy/lib-<name>`. Repo không prefix `lib-` (vd `ace-commons`) không phải thư viện để
tích hợp. Lib mới / đề xuất tách lib → đặt tên `lib-<name>`.

Tất cả là private git-dep, cài bằng tag: `"@acegalaxy/lib-<name>": "github:acegalaxy-co/lib-<name>#vX.Y.Z"`.
Clone local thường ở `~/Data/Local/Working/projects_repos/github/<repo>`. Mục lục chung:
`acegalaxy-co/ace-commons` README.

| Repo | Package | Dùng cho |
|---|---|---|
| `lib-security-utils` | `@acegalaxy/lib-security-utils` | audit append-only, caller validation, rate-limit sliding-window, replay guard |
| `lib-db-gateway` | `@acegalaxy/lib-db-gateway` | adapter Postgres/SQLite/Notion + gateway default-deny, dryRun |
| `lib-ott-gateway` | `@acegalaxy/lib-ott-gateway` | gateway tin nhắn inbound cho bot (Telegram/OTT) |
| `lib-ai-gateway` | `@acegalaxy/lib-ai-gateway` | gọi LLM: authz theo skill, token budget, circuit breaker, proxy routing |
| `lib-model-registry` | `@acegalaxy/lib-model-registry` | cấu hình model AI từ Notion, fallback Notion→cache→defaults |
| `lib-notion-vault` | `@acegalaxy/lib-notion-vault` | nạp secret từ Notion vault vào `process.env` |
| `lib-vault-sync` | `@acegalaxy/lib-vault-sync` | CLI sync vault → `.env` (chmod 600) |
| `lib-scheduler-runtime` | `@acegalaxy/lib-scheduler-runtime` | cron catalog trên Notion, track status/last run/error |
| `lib-voice-gateway` | `@acegalaxy/lib-voice-gateway` | Whisper STT có cost cap, rate limit, queue, audit |
| `lib-node-utils` | `@acegalaxy/lib-node-utils` | file-lock, kill process-group, normalize string (0 deps) |
| `lib-browser-crawler` | `@acegalaxy/lib-browser-crawler` | CloakBrowser profile path/pool, scraper engine |
| `lib-facebook-auth` | `@acegalaxy/facebook-auth` ⚠ lệch quy ước (chưa `lib-`) | Facebook session reauth, preflight, profile-lock |

Bảng chỉ để khoanh vùng. Khả năng thật phải xác minh từ source (bước 2).

## A. Cập nhật lib đã dùng

1. **Kiểm kê:** grep `@acegalaxy/` trong mọi `package.json` (kể cả workspace) → danh sách
   `<package> → <repo>#<tag hiện tại>`. Không có → bỏ qua A.
2. **Tag mới nhất:** `git ls-remote --tags --refs git@github.com:acegalaxy-co/<repo>.git | sort -V`
   (bỏ tag pre-release `-rc/-beta` trừ khi project đang pin pre-release). Đang pin branch/commit
   thay vì tag → báo, không tự đổi.
3. **Đọc thay đổi** `<tag cũ>..<tag mới>`: CHANGELOG/release notes, hoặc
   `git -C <clone> log --oneline <old>..<new>` + diff `package.json` (`engines`, `peerDependencies`,
   `exports`, `type`) + diff public API mà project đang gọi (grep call site).
4. **Phân loại:**
   - patch/minor, không đổi API đang dùng, engines/peer vẫn khớp → **nâng cấp**.
   - major / breaking chạm call site → nâng cấp **chỉ khi** sửa call site gọn trong scope;
     không thì báo user kèm danh sách breaking, KHÔNG nâng.
   - Không đọc được repo / changelog → **chưa xác minh**, KHÔNG nâng.
5. **Nâng cấp:** sửa tag trong `package.json`, cài lại bằng package manager của project để cập nhật
   lockfile, mỗi lib 1 bước riêng → verify (build/typecheck/test). Fail → revert lib đó, báo output.
   KHÔNG đụng dep ngoài `@acegalaxy/*`.

## C. Đánh giá lib chưa dùng (mode mặc định)

1. **Danh sách lib:** `gh repo list acegalaxy-co --limit 200 --json name,description,updatedAt,isArchived`
   lọc `lib-*`, bỏ archived, bỏ lib đã dùng (từ A). `gh` lỗi → dùng bảng danh mục, ghi **chưa xác minh**.
2. **Khoanh ứng viên:** so mô tả lib với project — stack (Node/ESM/TS), module hiện có
   (grep logic tương tự: lock file, rate-limit, audit, gọi LLM, Notion, Telegram, cron, `.env` loader...).
   Không có điểm chạm → loại ngay, ghi 1 dòng lý do.
3. **Đánh giá sâu** chỉ ứng viên có điểm chạm: đọc README + public exports + `package.json` lib
   (như bước B.2–B.3), rồi so với code tự viết tương ứng trong project:
   - **Lợi:** xoá được bao nhiêu code tự viết, bug/edge case lib đã xử lý mà project chưa, bảo mật.
   - **Chi phí:** công sửa call site, dep/peer mới, env/config bắt buộc, rủi ro hành vi đổi.
   - **Tương thích:** runtime, ESM/CJS, types, xung đột stack.
4. **Xếp hạng:** `Nên tích hợp` / `Cân nhắc` / `Không`. **KHÔNG tự cài** — chỉ báo cáo, user chọn
   lib nào thì chạy tiếp bước B.4–B.6 cho lib đó.

## B. Discovery cho tính năng mới (khi có yêu cầu)

0. **Làm mới danh mục:** `gh repo list acegalaxy-co --limit 200 --json name,description,updatedAt`
   lọc `lib-*` → so với bảng trên; lib mới/bỏ/lệch → ghi vào **Đề xuất cải tiến**.
1. **Project trước.** Grep code + `package.json`/lockfile tìm logic/`@acegalaxy/*` đã có.
   Đã có → dùng lại, dừng.
2. **Chỉ đọc repo liên quan** tới tính năng: README, `package.json` (`exports`, `main`,
   `types`, `engines`, `peerDependencies`), public exports (`src/index.*`), source của
   API định dùng, test/ví dụ. KHÔNG suy khả năng từ tên. Lấy version thật:
   `git ls-remote --tags git@github.com:acegalaxy-co/<repo>.git` (hoặc `git -C <clone> describe --tags`
   + `rev-parse HEAD`). Clone local cũ → `git fetch --tags` trước khi kết luận.
3. **Check tương thích:** runtime/Node version, ESM vs CJS, TypeScript types, peer deps,
   env/config bắt buộc, xác thực (Notion token, API key — tên biến, KHÔNG in giá trị),
   xung đột với stack đã chốt.
4. **Quyết định:**
   - Đáp ứng đủ → tích hợp.
   - Một phần → dùng phần hợp, viết adapter/logic thiếu **trong project**.
   - Không hợp → nói rõ điểm thiếu, sang thư viện ngoài / tự viết.
5. **Tích hợp:** dùng đúng package manager + lockfile của project (npm/pnpm/yarn/bun),
   pin tag như consumer khác. Chỉ thêm package có call site cụ thể. KHÔNG nâng cấp dep
   không liên quan, KHÔNG đổi stack, KHÔNG viết lại thứ lib đã làm.
6. **Verify:** chạy build / typecheck / test liên quan; báo kết quả thật (fail → dán output).

## Cấm

- Sửa repo thư viện dùng chung khi task chỉ là tích hợp — cần sửa lib → báo user, tách task.
- Bịa API khi thiếu docs — đọc source + test.
- Kết luận "lib thiếu tính năng" khi không truy cập được repo — ghi **chưa xác minh**.
- Cài cả danh mục "cho chắc".

## Output

```text
Mode: mặc định (A+C) | yêu cầu "<...>" (A+B)
Cập nhật: <package> <tag cũ> → <tag mới> (nâng | giữ: <lý do>) — mỗi lib 1 dòng
Đánh giá (mode mặc định): <lib> — Nên tích hợp|Cân nhắc|Không — <lợi/chi phí 1 dòng, chỗ thay trong project>
Kết luận: <lib nào> — đáp ứng <phần nào>; thiếu <gì> → <xử lý>
Bằng chứng: <repo>@<tag|commit> — <file/API đã đọc>
Tích hợp: <file đổi, dep thêm>
Verify: <lệnh> → <pass/fail>
Đề xuất cải tiến: <danh sách, hoặc "không có">
```

## Đề xuất cải tiến (BẮT BUỘC mỗi lần dùng)

Cuối output luôn có mục **Đề xuất cải tiến** — chỉ đề xuất, KHÔNG tự sửa. Ghi khi gặp:

- **Lib:** thiếu API/tính năng phải viết adapter, bug, docs/types thiếu, peer dep lệch, tên
  sai quy ước `lib-` → ghi `acegalaxy-co/lib-<name>`: <việc cần làm> (ứng viên issue/PR riêng).
- **Adapter viết trong project dùng lại được** → đề xuất đưa vào lib nào (hoặc lib mới `lib-<name>`).
- **Skill này:** danh mục thiếu/sai (lib mới, lib bỏ, mô tả lệch source), bước quy trình thừa/thiếu
  → ghi rõ dòng cần sửa trong `harness/templates/skills/ace-library/SKILL.md` (repo ccswitch,
  rồi `/update-harness-ccswitch` để sync).

Bị chặn (thiếu quyền repo, thiếu env/config thiết yếu) → hỏi user đúng thông tin cần, dừng.
