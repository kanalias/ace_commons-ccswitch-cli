---
name: audit-context-memory
description: "Audit context load mỗi session (rules, CLAUDE.md, MEMORY.md): phát hiện trùng lặp/phình, đề xuất lazy `paths:`, fix sau khi user xác nhận. Dùng /audit-context-memory [--rules-only]."
user-invocable: true
---

# audit-context-memory — inventory + audit + fix static context mỗi session

Mỗi session nạp tĩnh (không cần Claude chủ động Read) từ nhiều nguồn: global rules (`~/.claude/rules/`, luôn ALWAYS), `CLAUDE.md` project, project rules (`.claude/rules/*.md`, ALWAYS trừ khi có `paths:`), và `MEMORY.md` index (auto-memory, luôn load). Command này liệt kê hết, đọc nội dung thật, audit theo gate của [[rule-loading-policy]] + "what NOT to save" của memory system, rồi — sau khi user xác nhận — áp fix trực tiếp cho phần project rules.

Nguồn chân lý cho gate: `rule-loading-policy` trong `~/.claude/rules/` (global, không nằm trong project — installer này không cài rule đó). Command KHÔNG lặp lại policy — chỉ **áp dụng** thành audit + fix chạy được. Gate/định nghĩa lệch policy → theo policy.

Khác [[doctor-memory]] (chỉ memory content — broken link, orphan, naming, stale bên trong từng memory dir): command này audit **cái gì được nạp vào context**, doctor-memory audit **memory system tự nó có sạch không**. Hai phạm vi không chồng nhau: command này chỉ đọc `MEMORY.md` (index), không đọc/sửa từng file `user_*/feedback_*/project_*/reference_*.md` bên trong.

## Args

- (mặc định) — full audit như mô tả trên: tất cả nguồn (global rules, CLAUDE.md, project rules, MEMORY.md), chỉ sửa sau khi user chọn `[a]ll/[s]elect/[n]one` ở Bước 5.
- `--rules-only` — chỉ audit project rules (`.claude/rules/**`): chạy phần PROJECT RULES của Bước 1, chấm theo gate ở Bước 3 mục 1 (gate always-load) + mục 7 (LAZY giả), rồi **tự áp fix không hỏi** cho case confident — rule ALWAYS rớt gate mà glob suy được chắc chắn từ bảng glob ở Bước 3 mục 1, và rule FAKE-LAZY (thu hẹp glob rộng). Case KHÔNG CHẮC glob → KHÔNG chạm file, chỉ flag hỏi user vùng áp dụng. Vẫn tuân Write-boundary dưới: rule `common/**` → sửa template `harness/templates/rules/common/<same>.md`, KHÔNG sửa live; repo không có `harness/templates/` → chỉ flag, không tự sửa. Bỏ qua global rules, CLAUDE.md, MEMORY.md — không đọc, không audit trong mode này. Report theo format: bảng mỗi rule → trạng thái trước (ALWAYS/FAKE-LAZY/LAZY) → hành động (ĐÃ SỬA + glob đã ghi / GIỮ ALWAYS / FLAG chờ user) → lý do 1 dòng (gate nào rớt); tổng số candidate/đã sửa/flag; kết quả verify chạy lại lệnh Bước 1.

## Khái niệm (project rules)

- **LAZY** — rule có `paths:` (list glob) trong frontmatter. Chỉ load khi task chạm file khớp glob. Mặc định BẮT BUỘC cho project rule.
- **ALWAYS** — rule KHÔNG có `paths:`. Load mọi turn. Chỉ hợp lệ khi vượt gate P0-mọi-turn.
- **Gate always-load (đúng CẢ 2):** (1) P0 guardrail — vi phạm gây mất data / leak secret / phá scope; (2) áp mọi-turn — không gắn được vào 1 vùng code cụ thể. Thiếu 1 trong 2 → phải LAZY (kể cả P0 nếu chỉ chạm 1 vùng).
- **Global rule** (`~/.claude/rules/`) miễn gate này — luôn always theo bản chất tầng global, KHÔNG bao giờ gán `paths:`.

## Write-boundary (BẮT BUỘC đọc trước Bước 5)

Không phải file nào audit được cũng sửa được tại chỗ. 3 vùng, 3 cách sửa khác nhau:

| Vùng | Sửa ở đâu | Lý do |
|---|---|---|
| `.claude/rules/project/**` | sửa LIVE trực tiếp | `install.sh` mode `preserve` — không bị đè |
| `.claude/rules/common/**` | sửa `harness/templates/rules/common/<same>.md`, KHÔNG sửa live | `install.sh` mode `sync` (**overwrite**) — sửa live mất trắng lần re-sync sau |
| `CLAUDE.md` giữa `<!-- BEGIN HARNESS RULES ... -->` / `<!-- END HARNESS RULES -->` | KHÔNG sửa — sửa heredoc `ensure_claude_md()` trong `harness/install.sh` | block do install.sh generate, replace-in-place mỗi lần sync |

`CLAUDE.md` NGOÀI block → sửa live bình thường. Repo không có `harness/templates/` (project đã cài harness từ nơi khác) → `common/` và block CLAUDE.md thành **read-only**: chỉ flag ở report, hướng user sửa upstream ở harness repo.

Sửa bất kỳ harness surface LIVE nào → mirror vào template cùng commit: [[sync-template]].

## Bước 1 — Liệt kê file load tĩnh

```bash
echo "=== GLOBAL RULES (~/.claude/rules/, luôn ALWAYS) ==="
# find, không glob: zsh abort cả lệnh với "no matches found" khi dir vắng.
find ~/.claude/rules -maxdepth 1 -name '*.md' 2>/dev/null | sort | xargs -r wc -l || true
[ -d ~/.claude/rules ] || echo "(không có global rules)"

echo "=== PROJECT CLAUDE.md ==="
wc -l ./CLAUDE.md 2>/dev/null

echo "=== PROJECT RULES (.claude/rules/**) — phân loại ALWAYS/LAZY + tier ==="
# Rule nằm trong .claude/rules/common/ + .claude/rules/project/, KHÔNG phẳng ở tầng rules/.
# `cd .claude/rules && for f in *.md` KHÔNG match gì → báo 0 rule im lặng. Dùng find.
# head -20: frontmatter chuẩn ~8 dòng, paths: nằm sau — head -5 báo nhầm lazy thành ALWAYS.
find .claude/rules -name '*.md' ! -name '00-index.md' 2>/dev/null | sort | while read -r f; do
  n=$(wc -l < "$f")
  case "$f" in */common/*) tier="common:SYNC-overwrite" ;; *) tier="project:PRESERVE" ;; esac
  hdr="$(head -20 "$f")"
  if echo "$hdr" | grep -q "^paths:"; then
    # fake-lazy: glob rộng khớp mọi file (LAZY giả)
    if echo "$hdr" | grep -qE '^[[:space:]]*-[[:space:]]*"?(\*\*|\*\*/\*|\*)"?[[:space:]]*$'; then
      echo "FAKE-LAZY $f [$tier] ($n dòng)"
    else
      echo "LAZY      $f [$tier] ($n dòng)"
    fi
  else
    echo "ALWAYS    $f [$tier] ($n dòng)"
  fi
done

echo "=== MEMORY.md index (auto-memory, luôn load) ==="
p="$PWD"; slug="$(printf '%s' "$p" | sed 's/[\/_]/-/g')"
mdir="$HOME/.claude/projects/${slug}/memory"
[ -f "$mdir/MEMORY.md" ] && wc -l "$mdir/MEMORY.md"

echo "=== Memory con (lazy — chỉ load khi recall, KHÔNG tính vào static budget) ==="
[ -d "$mdir" ] && ls "$mdir"/*.md 2>/dev/null | grep -v MEMORY.md | wc -l
```

Kết quả bước này là danh sách file **thật sự load mỗi session** (global ALWAYS + CLAUDE.md + project rules ALWAYS + MEMORY.md). Memory con và project rules LAZY chỉ ghi nhận số lượng, KHÔNG đọc nội dung ở bước audit (chúng không tốn context nếu không được recall).

Đọc output phần project rules riêng: `ALWAYS` list dài hơn ~4–5 file → gần như chắc có rule nên chuyển lazy.

## Bước 2 — Đọc hết nội dung file ALWAYS-load

Read từng file trong danh sách ALWAYS ở Bước 1 (global rules, CLAUDE.md, project rules ALWAYS, MEMORY.md). Đây là nội dung thật nạp vào context mọi session — audit phải dựa trên nội dung thật, không suy đoán từ tên file.

## Bước 3 — Audit nội dung đã đọc

Với từng file, chấm theo các tiêu chí:

1. **Gate always-load** (theo [[rule-loading-policy]]) — file có vượt CẢ 2: (a) P0 guardrail (vi phạm gây mất data/leak secret/phá scope), (b) áp mọi-turn (không gắn được vào 1 vùng code cụ thể)? Global rule miễn gate này. Project rule/CLAUDE.md section rớt gate → flag CHUYỂN LAZY. Với mỗi rule ALWAYS rớt gate, xác định luôn glob đề xuất:
   - convention vùng X → glob vùng X (vd `"src/**"`, `"lib/**"`)
   - test/spec → `"test/**"`, `"**/*.test.*"`, `"spec/**"`
   - infra/CI → `"infra/**"`, `"Dockerfile*"`, `".github/**"`, `"*.yml"`
   - meta (viết rule) → `".claude/rules/**"`
   - delegate infra → `"scripts/delegate/**"`
   - KHÔNG CHẮC rule chạm đâu → KHÔNG tự đoán glob, KHÔNG mặc định always. Flag HỎI USER vùng áp dụng.
2. **Trùng lặp nội dung** — 2+ file (global vs global, global vs project, hoặc CLAUDE.md vs project rule) nói cùng 1 quy tắc bằng lời khác nhau → flag MERGE, giữ 1 nguồn, còn lại link `[[name]]`.
3. **Có thể derive từ code** — đoạn nào trong CLAUDE.md/rule chỉ mô tả lại thứ đọc được từ code/git log (path, convention hiển nhiên từ cấu trúc dir) → flag XOÁ (theo "what NOT to save" của memory system, áp dụng tương tự cho rule).
4. **MEMORY.md phình** — nếu MEMORY.md > 150 dòng hoặc entry mô tả dài hơn 1 dòng → flag rút gọn (entry chỉ nên là hook 1 dòng trỏ file, không phải nội dung).
5. **Rule/section quá dài cho tần suất dùng** — file > 150 dòng nhưng chỉ áp dụng 1 tình huống hiếm → flag tách phần chi tiết ra file riêng, chỉ giữ tóm tắt + link trong bản always-load (nếu buộc phải always) hoặc chuyển hẳn sang LAZY.
6. **Broken/stale reference** — `[[name]]` trỏ rule/memory không tồn tại, hoặc claim path/lệnh cụ thể đã đổi (verify nhanh bằng grep/Read code thật) → flag SỬA.
7. **LAZY giả** — rule đã có `paths:` nhưng glob quá rộng (`"**"` / `"**/*"`, khớp mọi file → luôn load) → flag thu hẹp glob.

## Bước 4 — Đề xuất tối ưu

Không tự sửa ở bước này. Với mỗi finding ở Bước 3, đề xuất 1 trong:

- **CHUYỂN LAZY** (project rule only) — thêm `paths:` glob đúng vùng.
- **MERGE** — gộp nội dung trùng vào 1 file nguồn, các chỗ còn lại thay bằng `[[name]]`.
- **RÚT GỌN** — cắt nội dung derivable/dài dòng, giữ ý cốt lõi.
- **TÁCH FILE** — chi tiết ít dùng chuyển ra file riêng (project rule LAZY hoặc memory `reference_*`), always-load chỉ giữ pointer.
- **GIỮ NGUYÊN** — vượt gate, không đổi.

Mỗi đề xuất ghi rõ: file, dòng hiện tại → dòng sau tối ưu (ước lượng), lý do 1 dòng, **và target sửa theo Write-boundary** (live / `harness/templates/rules/common/...` / `install.sh ensure_claude_md()`).

## Bước 5 — Áp fix (chỉ sau khi user chọn `[a]ll/[s]elect/[n]one`)

Trước mỗi Edit, route target theo **Write-boundary** ở trên. Finding chạm `.claude/rules/common/**` → Edit file template tương ứng rồi copy sang live (để session hiện tại có hiệu lực). Finding chạm CLAUDE.md managed block → KHÔNG Edit, báo user sửa `harness/install.sh`.

Cho mỗi finding **CHUYỂN LAZY** user đồng ý:

1. Thêm khối `paths:` vào frontmatter, ngay trước `metadata:` (quote từng glob):

   ```yaml
   paths:
     - "src/**"
     - "test/**"
   ```

2. **Đồng bộ index** — nếu repo có `.claude/rules/00-index.md` với cột Load, cập nhật cột đó khớp (ALWAYS→LAZY). Quên sync index = policy anti-pattern.
3. Không đổi nội dung body rule, không đổi `name`/`description` trừ khi user yêu cầu.

Cho **MERGE/RÚT GỌN/TÁCH FILE** user đồng ý: Edit trực tiếp theo đề xuất Bước 4, giữ nội dung cốt lõi, thay chỗ trùng bằng `[[name]]`.

Verify lại bằng lệnh Bước 1 — file vừa sửa phải hiện đúng trạng thái mới (LAZY, dòng giảm).

## Report

```markdown
## Context Load Audit — <cwd>, <ngày>

### Static (load mỗi session)
| Nguồn | File | Dòng | Trạng thái |
|---|---|---|---|
| global | orchestrator.md | N | ALWAYS (miễn gate) |
| project rule | git-workflow.md | N | ALWAYS |
| project | CLAUDE.md | N | ALWAYS |
| memory | MEMORY.md | N | ALWAYS (index) |
...

Tổng dòng static: N (global: Na, project rule ALWAYS: Nb, CLAUDE.md: Nc, MEMORY.md: Nd)

### Lazy (không tính vào static, chỉ ghi nhận số lượng)
- Project rules LAZY: N file
- Memory con (feedback/project/reference/user): N file

### Findings
| # | File | Vấn đề | Đề xuất | Ước lượng tiết kiệm |
|---|---|---|---|---|
...

### Chờ user xác nhận
<liệt kê MERGE/CHUYỂN LAZY/TÁCH FILE cần approve trước khi sửa — KHÔNG tự thực hiện>
```

Sau khi user chọn `[a]ll/[s]elect/[n]one`, thực hiện Bước 5, verify lại bằng lệnh Bước 1, và báo dòng context tiết kiệm thật sau khi sửa.
