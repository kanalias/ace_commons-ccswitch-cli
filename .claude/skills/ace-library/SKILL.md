---
name: ace-library
description: Trước khi viết tính năng mới / logic dùng chung trong project ACE Galaxy, kiểm tra thư viện nội bộ @acegalaxy/* (acegalaxy-co) có tái sử dụng được không, rồi tích hợp + verify. Dùng /ace-library <yêu cầu> hoặc "dùng ace library".
user-invocable: true
---

# ace-library — tái sử dụng thư viện nội bộ ACE Galaxy

Input: yêu cầu tính năng (`$ARGUMENTS`) + source/deps/lockfile/stack project hiện tại.

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

## Quy trình

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
