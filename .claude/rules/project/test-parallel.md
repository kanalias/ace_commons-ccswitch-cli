---
name: test-parallel
description: Mọi lần chạy bats suite BẮT BUỘC song song max `bats -j $(sysctl -n hw.ncpu)` — không chạy tuần tự (phí core). KHÔNG fan-out subagent để test. LAZY, load khi chạm test.
status: live
updated: 2026-07-31
paths:
  - "test/**"
  - "*.bats"
metadata:
  type: reference
---

# Test — chạy multi-worker song song (BẮT BUỘC)

Suite bats parallel-safe (mỗi test `HOME=$BATS_TEST_TMPDIR/home` riêng, temp `$$`/`$BATS_TEST_TMPDIR`). Chạy tuần tự = phí core: đo thực tế **69s tuần tự → 22s song song** (149 test, máy 10 core).

## Quy tắc

- **BẮT BUỘC** mọi lần chạy full suite:
  ```bash
  bats -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" test/*.bats
  ```
  KHÔNG chạy `bats test/*.bats` trần (tuần tự, bỏ phí core rảnh).
- **Worker = ncpu auto** — KHÔNG hardcode con số (12 hay khác). Auto khớp mọi máy, không oversubscribe. Máy này = 10.
- **Prereq GNU `parallel`** (bats `-j` cần `parallel`/`rush`). Thiếu → bats báo lỗi → fallback `bats test/*.bats` tuần tự + **báo user cài** (`brew install parallel`), KHÔNG im lặng bỏ `-j`.

## KHÔNG fan-out subagent để chạy test (sai công cụ)

"Song song test" = `bats -j`, KHÔNG phải spawn nhiều subagent. Fan-out subagent (≤15, xem [[orchestrator]]) chỉ dành cho **edit task độc lập trong worktree riêng**.

| | Subagent mỗi file | `bats -j` |
|---|---|---|
| Overhead | spawn ctx + prompt self-contained + gom output thủ công | in-process, 0 |
| Token Claude | tốn quota | 0 |
| Song song | qua N process rời | 149 test / ncpu core, 1 process |
| Kết quả | rời rạc, merge tay | gộp sẵn |

→ Subagent chạy test **chậm hơn** + tốn token. Cấm dùng cho test.

## Parallel-safe invariant (test MỚI phải giữ)

- State phải isolate qua `$BATS_TEST_TMPDIR` + `HOME` fake — dùng `setup_fake_home` ở [test/test_helper.bash](../../../test/test_helper.bash).
- Test chạm global state cố định (`~/.claude` thật, file path fixed dùng chung) = **vỡ khi `-j`** → cấm. Nghi share state → `--no-parallelize-within-files` cho file đó, không bỏ `-j` toàn cục.

Surface thực thi: [/git-push-safety](../../commands/git-push-safety.md). Mirror template: [[sync-template]].
