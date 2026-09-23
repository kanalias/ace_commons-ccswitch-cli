# Claude Code harness template

`templates/` là source of truth cho harness portable. `install.sh` thay giá trị
project, copy các surface đã chọn vào project đích, và merge wiring của chúng
vào `.claude/settings.json`. `VERSION` chứa version release của harness
(semantic versioning), không phải version Claude Code.

## Install, sync, preview, uninstall

Yêu cầu: Bash và `jq`; Git cho worktree và Git hook. Chạy từ root của repo
này, dùng project đích riêng (KHÔNG BAO GIỜ install vào `harness/`).

```bash
# Preview: zero writes, including no target-directory creation.
HARNESS_ROUTE_DIR=/path/to/project HARNESS_DRY_RUN=1 bash harness/install.sh

# Install or sync: the default action. Explicit noninteractive confirmation.
HARNESS_ROUTE_DIR=/path/to/project HARNESS_ASSUME_YES=1 bash harness/install.sh

# Preview removal, then remove only installer-owned, unchanged material.
HARNESS_ROUTE_DIR=/path/to/project HARNESS_DRY_RUN=1 bash harness/install.sh uninstall
HARNESS_ROUTE_DIR=/path/to/project HARNESS_ASSUME_YES=1 bash harness/install.sh uninstall
```

Redirect stdin từ `/dev/null` **KHÔNG PHẢI** dry run. Dùng `HARNESS_DRY_RUN=1`.
Review plan trước khi confirm writes. Cấu hình `HARNESS_CORE_DIRS`,
`HARNESS_RISK_DIRS`, `HARNESS_PROJECT_SLUG`, `HARNESS_BRANCH`, và
`HARNESS_TEST_CMD` cho target; xem installer header để biết group switch.
KHÔNG mặc định defaults của nó mô tả đúng repo bạn hay tự bật secret check
cho mọi dir nhạy cảm.

Lifecycle contract bên dưới được installer implement; chỉ check documentation
không verify được removal safety. Chạy installer lifecycle test trước khi
release thay đổi cho implementation đó.

## Ownership và nâng cấp

Manifest `.claude/` của target ghi lại schema và version harness, sync path đã
install kèm sha256 checksum, preserve path, và ownership chính xác của
settings. Giữ manifest đó: nó là ownership record, không phải runtime log
dùng-xong-bỏ.

- **Sync files:** surface do template sở hữu được refresh mỗi lần
  install/sync. Rule chung dưới `.claude/rules/common/` được quản lý; sửa đổi
  tái dùng được thì làm upstream ở `templates/rules/common/`, không sửa bản đã
  install. Backup edit local trước khi sync; cơ chế bảo vệ modified-file của
  uninstall không phải chiến lược merge nâng cấp.
- **Preserve files:** rule project có sẵn dưới `.claude/rules/project/` và
  `.claude/allowed-hosts.txt` vẫn thuộc project. Template chỉ seed file còn
  thiếu; sync không ghi đè customization đã có.
- **Shared configuration:** setting và text không liên quan nằm ngoài block
  `CLAUDE.md` được quản lý thuộc về project. Ownership settings của harness là
  chính xác (exact), không phải ownership toàn bộ settings file hay hook
  event.
- **Uninstall:** chỉ xoá sync file chưa đổi mà checksum đã ghi khớp, và nội
  dung settings/`CLAUDE.md` được quản lý đúng phạm vi sở hữu. Giữ lại file đã
  sửa, file preserve-mode, và user content không liên quan. KHÔNG thay
  operation này bằng xoá đệ quy `.claude/` hay `scripts/`.

Reinstall là sync, không phải reset project đích. Review installer plan và
diff sau khi nâng cấp. Giữ runtime state, secret, và config đặc thù máy ngoài
phạm vi template phân phối; `.DS_Store` bị ignore và KHÔNG được ship.

## Load rule native so với enforcement

Claude Code cung cấp discovery **native** cho rule Markdown, đệ quy dưới
`.claude/rules/`. Rule không có `paths:` load unconditionally; glob list YAML
`paths:` scope rule vào file khớp. Rule path-scoped load khi file khớp được
đọc, không phải executable check trên mỗi tool invocation. Tham khảo: tài
liệu chính thức Claude Code, *How Claude remembers your project*, mục
*Organize rules with .claude/rules/* và *Path-specific rules*.

Load instruction không phải runtime enforcement. Rule mô tả governance;
feature execution vẫn thuộc về 5 harness surface: slash command, hook,
subagent, MCP server, và permission deny setting. Dùng hook hoặc permission
boundary khi operation thật sự cần bị block. Markdown link chỉ là navigation,
không phải cơ chế khiến native project rule discoverable.

## Extension tuỳ chọn và giới hạn

- Delegate wrapper cần external CLI tương ứng, credential, và model được hỗ
  trợ cấu hình riêng. Install template không install provider, không cấp
  quota, không chứng minh network access. KHÔNG BAO GIỜ embed credential.
- Production deployment command là opt-in (`HARNESS_GROUP_DEPLOY=Y`). Cấu
  hình host, service, remote path, branch, và health check trước khi dùng.
  Install command không phải approval để deploy và không provision
  infrastructure.
- Git pre-push scanning cần Git và scanner dependency của nó; copy hook
  không install dependency đó. Hook project có sẵn vẫn là vấn đề ownership,
  không phải permission để thay automation không liên quan.
- MCP server, browser profile, và plugin bên thứ ba cần setup và permission
  riêng. Installer này không phải plugin manager. Rule `skill-superpowers` đi
  kèm chỉ mượn methodology; nó không install plugin đó.
- Workflow skill cung cấp instruction, không phải scheduler, service
  supervisor, hay đảm bảo mọi tool đều sẵn có. Diagnostic không phải
  remediation hay authorization để sửa production resource.

## Verify

```bash
bats test/harness-docs.bats
```

Suite tập trung này check release metadata, package hygiene, và documentation
contract. Installer và hook test suite verify executable behavior riêng.
