---
name: test-parallel
description: Mọi lần chạy test suite BẮT BUỘC song song max (auto ncpu worker) — không chạy tuần tự (phí core). KHÔNG fan-out subagent để test. LAZY, load khi chạm test.
status: live
updated: 2026-07-31
paths:
  - "test/**"
  - "*.bats"
metadata:
  type: reference
---

# Test — chạy multi-worker song song (BẮT BUỘC)

Nếu suite parallel-safe (mỗi test state isolate qua tmpdir + `HOME` fake) → chạy tuần tự = phí core. Song song hoá xuống nhiều lần thời gian.

## Quy tắc

- **BẮT BUỘC** mọi lần chạy full suite ở worker count = số core máy. Với bats:
  ```bash
  bats -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" test/*.bats
  ```
  KHÔNG chạy runner trần tuần tự (bỏ phí core rảnh).
- **Worker = ncpu auto** — KHÔNG hardcode con số. Auto khớp mọi máy, không oversubscribe.
- **Prereq**: runner cần backend song song (bats `-j` cần GNU `parallel`/`rush`). Thiếu → fallback tuần tự + **báo user cài**, KHÔNG im lặng bỏ song song.

## KHÔNG fan-out subagent để chạy test (sai công cụ)

"Song song test" = flag `-j` của runner, KHÔNG phải spawn nhiều subagent. Fan-out subagent (≤15, xem [[orchestrator]]) chỉ dành cho **edit task độc lập trong worktree riêng**.

| | Subagent mỗi file | runner `-j` |
|---|---|---|
| Overhead | spawn ctx + prompt self-contained + gom output thủ công | in-process, 0 |
| Token Claude | tốn quota | 0 |
| Song song | qua N process rời | test / ncpu core, 1 process |
| Kết quả | rời rạc, merge tay | gộp sẵn |

→ Subagent chạy test **chậm hơn** + tốn token. Cấm dùng cho test.

## Parallel-safe invariant (test MỚI phải giữ)

- State phải isolate qua tmpdir per-test + `HOME` fake (bats: `$BATS_TEST_TMPDIR` + `setup_fake_home` ở `test/test_helper.bash`).
- Test chạm global state cố định (`~/.claude` thật, file path fixed dùng chung) = **vỡ khi song song** → cấm. Nghi share state → isolate file đó (bats: `--no-parallelize-within-files`), không bỏ `-j` toàn cục.

Surface thực thi: `/git-push-safety`. Mirror template: [[sync-template]].
