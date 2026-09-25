---
name: update-harness-ccswitch
description: "Quét Data/Local/Working/projects_repos tìm project có .claude/harness-manifest.json (cài từ harness ccswitch), reconstruct deploy config còn thiếu (manifest cũ chưa có installEnv), rồi chạy harness/install.sh update cho từng project — không xoá mất production-deploy/-cleanup/-reboot skill. Dùng /update-harness-ccswitch hoặc \"update harness ccswitch\"."
user-invocable: true
---

# update-harness-ccswitch — sync harness mới ra mọi project đã cài

Harness nguồn: `harness/install.sh` trong repo này (ccswitch-cli-claude). `install.sh update-all`
chỉ replay đúng cho project có `.installEnv` trong manifest — project cũ (cài trước khi field này
tồn tại) sẽ bị **skip**, và chạy `install.sh` trực tiếp với default sẽ **xoá** 3 skill
`production-deploy/-cleanup/-reboot` (default `HARNESS_GROUP_DEPLOY=N`).

## Bước 1 — Quét project có manifest

```bash
find /Users/admin/Data/Local/Working/projects_repos -maxdepth 4 -name harness-manifest.json 2>/dev/null
```

Loại `ccswitch-cli-claude` (chính nó, không phải target). `.claude` không có manifest → không phải
do harness này cài, bỏ qua (đừng đụng).

## Bước 2 — Check installEnv, reconstruct nếu thiếu

```bash
jq -e '.installEnv | type == "object"' "<project>/.claude/harness-manifest.json"
```

- Có → dùng thẳng `update-all` (bước 3a).
- Không có → project có `production-deploy` skill không:
  `ls "<project>/.claude/skills" | grep -i production` — nếu có, đọc
  `<project>/.claude/skills/production-deploy/SKILL.md` lấy ssh host / service / repo path /
  healthcheck (thường ở dạng `ssh <host> ...`, `docker compose -p <service>`, path tuyệt đối trong
  script) để set `HARNESS_DEPLOY_*` khi chạy install (bước 3b). Không tự đoán — không tìm thấy giá
  trị rõ ràng thì hỏi user thay vì set bừa.

## Bước 3a — Replay qua registry (có installEnv)

```bash
cd /Users/admin/Data/Local/Working/projects_repos/github/ccswitch-cli-claude
echo "<abs-project-path>" >> .repo-inused   # nếu chưa có trong registry
bash harness/install.sh update-all
```

## Bước 3b — Install thủ công (thiếu installEnv, có deploy)

```bash
cd /Users/admin/Data/Local/Working/projects_repos/github/ccswitch-cli-claude
HARNESS_ROUTE_DIR="<abs-project-path>" \
HARNESS_CONFIRM_PATH=y HARNESS_INSTALL_ALL=y \
HARNESS_GROUP_DEPLOY=y \
HARNESS_DEPLOY_SSH_HOST="<reconstructed>" \
HARNESS_DEPLOY_SERVICE="<reconstructed>" \
HARNESS_DEPLOY_PATH="<reconstructed>" \
HARNESS_DEPLOY_HEALTHCHECK="<reconstructed>" \
bash harness/install.sh </dev/null
```

`HARNESS_PROJECT_SLUG`/`HARNESS_TEST_CMD`/`HARNESS_CORE_DIRS` giữ default trừ khi project có giá trị
khác biệt rõ ràng cần giữ (check `.claude/settings.json` cũ trước khi ghi đè).

## Bước 4 — Verify sau update

Mỗi project:
```bash
ls "<project>/.claude/skills" | grep -i production   # 3 skill deploy còn nguyên
git -C "<project>" status --short .claude            # review diff trước khi để user commit
```

KHÔNG tự commit ở project khác — đây là repo của user, chỉ báo diff + để user tự commit
(hoặc hỏi nếu muốn tự động).

## Confirm trước khi chạy hàng loạt

Liệt kê danh sách project target + action (update-all / install thủ công) → hỏi user
`[a]ll / [s]elect / [n]one` trước khi thực thi, theo [[git-workflow]] tinh thần "confirm trước xoá/ghi đè hàng loạt".
