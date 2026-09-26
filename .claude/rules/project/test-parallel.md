---
name: test-parallel
description: Mọi lần chạy test BẮT BUỘC song song max — worker = ncpu auto, nhiều suite độc lập chạy cùng lúc, chỉ chạy file vừa sửa trong vòng lặp fix. KHÔNG fan-out subagent để test. LAZY, load khi chạm test.
status: live
updated: 2026-09-26
paths:
  - "test/**"
  - "tests/**"
  - "*.bats"
  - "**/*.test.*"
  - "**/*.spec.*"
metadata:
  type: reference
---

# Test — chạy song song max (BẮT BUỘC)

Suite parallel-safe (state isolate per-test) mà chạy tuần tự = phí core, chờ lâu. "Song song test" = flag của **runner**, KHÔNG phải spawn subagent.

## Quy tắc

- **Worker = ncpu auto** (`sysctl -n hw.ncpu` / `nproc`), KHÔNG hardcode số, KHÔNG chạy runner trần khi runner mặc định tuần tự.
- **Nhiều suite độc lập** (unit ‖ e2e ‖ lint ‖ typecheck ‖ build) → chạy cùng lúc: 1 message nhiều Bash tool-call, hoặc `run_in_background` từng cái rồi gom. Tuần tự CHỈ khi suite B cần output suite A.
- **Vòng lặp fix** chỉ chạy đúng file/test vừa sửa (`bats test/x.bats`, `-f`, `--test-name-pattern`) — full suite là gate trước push, không phải mỗi vòng.
- Runner thiếu backend song song → fallback tuần tự có prefix rõ + **báo user cài**, KHÔNG im lặng bỏ song song.

## Lệnh theo runner

| Runner | Lệnh song song | Ghi chú |
|---|---|---|
| bats | `bats -j "$(sysctl -n hw.ncpu 2>/dev/null \|\| nproc 2>/dev/null \|\| echo 4)" test/*.bats` | cần GNU `parallel` (`brew install parallel`). Thiếu → `BATS_SERIAL_OK=1 bats test/*.bats`. Hook `pre-bash-gate.sh` chặn bats ≥2 file không `-j`. |
| node --test | `node --test` — mặc định đã song song theo file (ncpu-1) | ép: `--test-concurrency=N`; test trong 1 file vẫn tuần tự |
| jest | `jest --maxWorkers=100%` | `--runInBand` chỉ khi debug 1 test |
| vitest | `vitest run` — mặc định song song | `--pool=threads` khi ít RAM |
| pytest | `pytest -n auto` | cần `pytest-xdist`; thiếu → báo cài, fallback `pytest` |
| go | `go test ./...` — mặc định song song theo package | `-parallel N` cho `t.Parallel()` |
| cargo | `cargo test` — mặc định song song | `--test-threads=N` ép |

## KHÔNG fan-out subagent để chạy test (sai công cụ)

Fan-out subagent (≤20, xem [[orchestrator]]) chỉ dành cho **edit task độc lập trong worktree riêng** hoặc **N target độc lập cần suy luận** — không phải để chạy runner.

| | Subagent mỗi file | runner `-j` |
|---|---|---|
| Overhead | spawn ctx + prompt self-contained + gom output thủ công | in-process, 0 |
| Token Claude | tốn quota | 0 |
| Song song | qua N process rời | test / ncpu core, 1 process |
| Kết quả | rời rạc, merge tay | gộp sẵn |

→ Subagent chạy test **chậm hơn** + tốn token. Cấm dùng cho test.

## Parallel-safe invariant (test MỚI phải giữ)

- State phải isolate qua tmpdir per-test + `HOME` fake (bats: `$BATS_TEST_TMPDIR` + `setup_fake_home` ở `test/test_helper.bash`).
- KHÔNG `sleep` để tạo chênh mtime/thời gian — dùng `touch -t <quá khứ>` (mỗi `sleep 1` × N test = N giây chết trên critical path).
- Test chạm global state cố định (`~/.claude` thật, file path fixed dùng chung) = **vỡ khi song song** → cấm. Nghi share state → isolate file đó (bats: `--no-parallelize-within-files`), không bỏ `-j` toàn cục.

Surface thực thi: `/git-push-safety`. Mirror template: [[sync-template]].
