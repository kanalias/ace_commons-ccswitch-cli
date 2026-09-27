---
name: diagram
description: "Render diagram Mermaid cho 1 module/tính năng, mọi ngôn ngữ: cấu trúc (import graph qua tool native khi có, ~0 token) + luồng chi tiết (sequence/flowchart do LLM đọc đúng file liên quan). Có diagram sẵn và còn mới → mở luôn; chưa có/cũ → sinh rồi render. Dùng /diagram <path|tính năng> [structure|flow|all], hoặc khi user nói \"vẽ sơ đồ\", \"diagram\", \"workflow\", \"chi tiết luồng\", \"cấu trúc module\"."
user-invocable: true
---

# diagram — render sơ đồ cấu trúc + luồng tính năng

Output: `docs/diagrams/<slug>.md` (Mermaid; GitHub/GitLab + VS Code preview render sẵn). Project đã có thư mục diagram khác (`doc/`, `docs/architecture/`…) → dùng thư mục đó. `<slug>` = path module thay `/` bằng `-`, bỏ prefix chung vô nghĩa (`src-`, `app-`, `lib-`).

## Tham số

- `<target>`: path (`src/modules/billing`) hoặc tên tính năng ("billing retry") → tự `ls`/grep ra path, không chắc thì hỏi user.
- mode: `structure` (chỉ import graph) | `flow` (luồng nghiệp vụ) | `all` (mặc định).

## Bước 1 — Check có sẵn chưa

```bash
f=docs/diagrams/<slug>.md
[ -f "$f" ] && [ -z "$(find <target> -type f -newer "$f" -not -path '*/node_modules/*' | head -1)" ] && echo FRESH
```

- `FRESH` + user không yêu cầu vẽ lại → nhảy Bước 4. KHÔNG đọc source.
- Không có / source mới hơn → Bước 2.

## Bước 2 — Chọn tool structure theo ngôn ngữ

Không add dependency vào repo — chạy ephemeral (`npx -y`, `uvx`, `go run`). Tool không chạy được → fallback grep (cuối bảng), không cài global.

| Ngôn ngữ | Lệnh (output Mermaid / DOT) |
|---|---|
| JS/TS | `NODE_PATH=$PWD/node_modules npx -y dependency-cruiser@latest <target> --no-config --output-type mermaid` (+ `--ts-config tsconfig.json` nếu TS) |
| Python | `uvx pydeps <target> --show-dot --no-output --max-bacon 2` → DOT, convert tay sang `flowchart` |
| Go | `go list -f '{{.ImportPath}}: {{join .Imports " "}}' ./<target>/...` → lọc import nội bộ (prefix module) |
| Khác / fail | grep import (dưới bảng) → LLM dựng `flowchart LR`, chỉ edge nội bộ |

Fallback: `grep -rnE '^\s*(import|from|require|use|#include)' <target>`

Gotcha dependency-cruiser: npx cache không thấy `typescript` → quét `.ts` ra 0 module; `NODE_PATH` ở trên là bắt buộc. Check: `... --info 2>&1 | grep -q '✔ typescript'`, thiếu → `npm install` trước.

Không cần graphviz (đích là Mermaid). **Preview Mermaid trong VS Code — chưa có thì cài, có rồi thì check + update** (tự chạy, không hỏi):

- VS Code **≥1.121**: Mermaid là built-in (`mermaid-markdown-features`); `bierner.markdown-mermaid` đã deprecated (1.32.1, "merged into VS Code") và **xung đột** built-in → khung trắng (vscode#317870). "Cài/update" = update VS Code; extension cũ còn → gỡ.
- VS Code **<1.121**: dùng extension `bierner.markdown-mermaid` — thiếu thì cài, có rồi thì `--force` lên bản mới nhất.

```bash
v=$(code --version | head -1)
latest=$(curl -fsS https://update.code.visualstudio.com/api/releases/stable 2>/dev/null | tr -d '[]"' | cut -d, -f1)
if [ "$(printf '%s\n1.121.0\n' "$v" | sort -V | head -1)" = "1.121.0" ]; then
  code --list-extensions | grep -qx bierner.markdown-mermaid && code --uninstall-extension bierner.markdown-mermaid && echo "RESTART: gỡ extension deprecated xung đột built-in → Cmd+Q mở lại VS Code"
  [ -n "$latest" ] && [ "$v" != "$latest" ] && echo "UPDATE: VS Code $v → $latest (Code > Check for Updates; brew: brew upgrade --cask visual-studio-code)"
else
  code --install-extension bierner.markdown-mermaid --force   # cài mới hoặc update lên latest
  echo "UPDATE khuyến nghị: VS Code $v < 1.121 — nâng VS Code để dùng Mermaid built-in"
fi
```

## Bước 3 — Sinh diagram

**structure**: chạy lệnh Bước 2 > `/tmp/dc.mmd`. Chỉ giữ module nội bộ (bỏ stdlib/third-party). >40 node → gom theo folder (dependency-cruiser: `--collapse '^<src-root>/[^/]+/[^/]+'`; cách khác: gộp tay theo thư mục cấp 1 dưới `<target>`).

**flow** (tốn token — giữ tối thiểu):

1. Khoanh vùng file bằng structure graph + entry point (route/controller, CLI main, cron/scheduler, event/queue handler). Đọc `README`/`MODULE.md` trong `<target>` nếu có trước.
2. Chỉ đọc file nằm trên luồng chính; grep chữ ký hàm thay vì đọc toàn file khi đủ.
3. Viết `sequenceDiagram` (trigger → module → external: DB/API/queue/LLM…) + `flowchart TD` cho nhánh điều kiện/lỗi nếu có. Chỉ vẽ lời gọi có thật trong code — không bịa bước.
4. Trước khi ghi: đối chiếu từng nguồn dữ liệu/actor với code (grep lời gọi client DB/HTTP/queue/SDK thật) — README/MODULE.md có thể lệch code (vd thứ doc gọi là "bảng riêng" thực ra là relation/field).
5. Nhiều trigger (vd cron ngày + webhook) → mỗi trigger 1 `sequenceDiagram` riêng, không gộp.

Ghi file:

````markdown
# <target> — diagram

> Sinh bởi /diagram <ngày>. Source: `<target>`

## Cấu trúc (import graph)
```mermaid
<nội dung /tmp/dc.mmd>
```

## Luồng
```mermaid
sequenceDiagram
...
```
````

## Bước 4 — Render (mở tab preview luôn)

Có preview Mermaid (built-in hoặc extension, xem Bước 2) → mở thẳng tab preview, KHÔNG bắt user bấm Cmd/Ctrl+Shift+V. Cơ chế: `.vscode/settings.json` gán thư mục diagram mở bằng preview editor (merge key, không ghi đè file):

```json
"workbench.editorAssociations": { "**/docs/diagrams/*.md": "vscode.markdown.preview.editor" }
```

```bash
grep -q 'docs/diagrams' .vscode/settings.json 2>/dev/null || echo "THIẾU editorAssociations → merge key trên vào .vscode/settings.json"
code -r docs/diagrams/<slug>.md
```

- `-r` = mở tab trong window hiện tại. Cần sửa source → chuột phải tab → "Reopen Editor With… → Text Editor".
- Không dùng VS Code → GitHub/GitLab render Mermaid sẵn khi xem file.

Báo user: path file + 1 dòng tóm tắt luồng.

### Preview trắng / lỗi render

1. Validate cú pháp bằng mermaid-cli (tải Chromium lần đầu ~1 phút), chạy trong `/tmp` để ảnh không rơi vào repo:
   ```bash
   (cd /tmp && npx -y @mermaid-js/mermaid-cli -i "$OLDPWD/docs/diagrams/<slug>.md" -o /tmp/<slug>.md -e png)
   ```
   Có `❌`/parse error → sửa block đó.
2. Render OK mà preview trắng → gần như luôn do `bierner.markdown-mermaid` còn cài trên VS Code ≥1.121 (xung đột built-in): gỡ extension + restart hẳn VS Code (Cmd+Q, không chỉ Reload Window).
3. Vẫn trắng → sequence dài lệch viewport: bấm nút fit (góc phải block) hoặc `Developer: Reload Window`. Vẫn trắng → mở `/tmp/<slug>-N.png` cho user xem.
4. Giảm rủi ro: tránh `;`, `#`, `{}` chưa escape trong message; label có `()`/`:` → quote; label dài dùng `<br/>`.

## Không làm

- Không commit diagram tự động — user quyết.
- Không ghi ảnh SVG/PNG vào repo trừ khi user yêu cầu.
- Không vẽ cả repo 1 lần (graph vô nghĩa) — luôn theo module/tính năng.
- Không thêm dependency / config tool vào repo.
