---
name: project-ai-memory-kit
description: "ai-memory-kit v4.2 = business-only template, đồng bộ 2 chiều với Drive kane-ai-memory; nut-bam/.obsidian/.github đã purge (37821a0), Drive khớp bundle"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2c6ec1df-eb99-4349-b18c-4b6628e515d0
---

`ai-memory-kit/` (v4.2, commit 37821a0, 2026-08-13) = template business-rules memory của `Shared drives/kane-ai-memory` (MemoryOS). Bundle ↔ Drive KHỚP nhau (sync 2026-08-13, rsync --delete, exclude .obsidian/HANDBOOK.md/.git/.cleanup-state.json/.khoa-engine.lock). Team cài 1 lần: `bash "<Drive path>/cai-dat.sh"`.

- Đã vá (bundle + Drive): CRLF-tolerant frontmatter (7 script), SECRET_RE mở rộng, `tools/test-fixes.mjs` 27 case, `cai-dat.sh` one-shot global installer + `CAI-DAT-1-LAN.md`, handbook-gate cache tmpdir, `khoa-vault.mjs` lock đa-phiên cùng máy (mkdir atomic, stale-break 10p, fail-open) + **SIGINT/SIGTERM nhả lock** (hết orphan lock Ctrl-C), `moi-so-nang-luc.mjs` slug mồi pricing (hết dev slug feature-flag).
- **v4.2 purge**: `addons/` XOÁ (git 97bc7e9 khôi phục); `nut-bam/` 7 launcher + `.obsidian/` + `.github/workflows/secret-scan.yml` XOÁ theo user (git 5fa1e7f user tự xoá, refs dọn ở 37821a0). `nang-luc-registry.json` = 12 capability business.
- `.obsidian` trên Drive GIỮ NGUYÊN (exclude rsync chủ ý — team mở Obsidian); bundle không còn .obsidian.
- Rename `Memories/` → lowercase đã bác (tên là API của kit, 12 script hardcode).
- P2 chấp nhận (docs/multi-session.md): lock KHÔNG bảo vệ 2 máy khác nhau qua Drive sync; mirror-ngoài-cloud = convention + cai-dat.sh enforce path local.

**Why:** quyết định scope từ user "chỉ mục tiêu là business memory thôi" + "loại bỏ nội dung cũ của các project" + "Xoá có chủ ý" (nut-bam).
**How to apply:** sửa kit → sửa bundle trong repo này rồi rsync sang Drive (precheck Drive == bundle tại commit baseline 37821a0 trước khi --delete); sync ngược upstream → gói qua `tools/dong-gop.mjs`.
