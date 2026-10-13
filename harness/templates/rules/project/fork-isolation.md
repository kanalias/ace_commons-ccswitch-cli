---
name: fork-isolation
description: P0 cho repo là FORK có remote `upstream` — tính năng riêng của fork nằm trong 1 thư mục `<fork-dir>`; code upstream chỉ thêm hook mỏng đánh dấu `<fork-marker>`. Giảm conflict khi merge upstream + lỗi fork không làm sập luồng chính. LAZY, load khi chạm code source.
status: live
updated: 2026-10-13
paths:
@@CORE_DIRS_YAML@@
metadata:
  type: reference
---

# Fork isolation (P0)

Chỉ áp khi repo có remote `upstream` (`git remote | grep -qx upstream`); không có → bỏ qua rule này. Điền `<fork-dir>` và `<fork-marker>` sau khi cài (vd `src/<org>/`, `// <org>:`).

## Quy tắc

- **Tính năng mới cho fork → `<fork-dir>/<feature>/`.** Logic, config, schema, script, job, handler, test helper — tất cả ở đây. KHÔNG tạo file logic mới trong thư mục của upstream.
- **Code upstream** (mọi thứ ngoài `<fork-dir>`) chỉ được sửa để thêm **hook mỏng** (≤ ~5 dòng/điểm), đánh dấu comment `<fork-marker> <mục đích>`.
- Feature cần sửa sâu logic upstream (không hook được) → STOP, hỏi user trước.

## Hook an toàn

- Lỗi hoặc thiếu module fork KHÔNG được làm hỏng luồng chính (request path, startup, build).
- Hook gọi vào `<fork-dir>` kiểu lazy + bắt lỗi (dynamic import / fire-and-forget), module fork tự try/catch và tự check env bật/tắt.
- Cấm trong hook:
  - `await` chặn request path.
  - throw ra ngoài.
  - import tĩnh top-level vào file upstream nóng.
  - sửa signature hàm upstream.

## Bên trong `<fork-dir>`

- Export qua 1 entry (`index`) cho mỗi feature.
- Bật/tắt bằng env — mặc định tắt khi thiếu env, không crash.
- Không import sâu vào internals upstream khi có API công khai; không đổi schema upstream (schema riêng ghi tài liệu riêng trong `<fork-dir>`).

## Khi merge upstream

Conflict ngoài `<fork-dir>` chỉ nên là các dòng `<fork-marker>` — grep marker trong file upstream để re-apply hook. Liệt kê hook hiện có:

```bash
grep -rn "<fork-marker>" . --exclude-dir=node_modules --exclude-dir=.git | grep -v "^./<fork-dir>/"
```

Liên quan: [[feature-redflags]], [[git-workflow]].
