#!/usr/bin/env bats

setup() {
  export TEMPLATE_ROOT="${SKILLS_TEMPLATE_ROOT:-$BATS_TEST_DIRNAME/../harness/templates}"
  export REPO_ROOT="${SKILLS_REPO_ROOT:-$BATS_TEST_DIRNAME/..}"
}

@test "harness/templates/commands does not exist" {
  [ ! -e "$TEMPLATE_ROOT/commands" ]
  [ ! -e "$REPO_ROOT/.claude/commands" ]
}

@test "merged-away skills are not in templates" {
  for name in auto-commit audit-git-leak lazy-load-health resume-orchestration; do
    [ ! -e "$TEMPLATE_ROOT/skills/$name" ]
  done
}

@test "skills have valid discovery frontmatter and unique directory-matching names" {
  python3 - <<'PY'
import os, re
from pathlib import Path
names = set()
for skill in (Path(os.environ['TEMPLATE_ROOT']) / 'skills').glob('*/SKILL.md'):
    text = skill.read_text()
    parts = text.split('---', 2)
    assert len(parts) == 3 and not parts[0], f'Missing frontmatter: {skill}'
    fields = {}
    for line in parts[1].strip().splitlines():
        key, sep, value = line.partition(':')
        assert sep and key not in fields, f'Invalid/duplicate field: {skill}: {line}'
        fields[key] = value.strip()
    name = fields.get('name', '')
    assert re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', name), skill
    assert name == skill.parent.name and name not in names, f'Duplicate/mismatched name: {skill}'
    names.add(name)
    assert fields.get('description') and len(fields['description']) <= 1024, skill
    assert fields.get('user-invocable') == 'true', skill
    assert parts[2].strip(), f'Empty workflow: {skill}'
    assert not {'mcp', 'mcp-servers', 'plugin', 'plugins'} & fields.keys(), skill
PY
}

@test "research skill locks report provenance and preflight guards" {
  python3 - <<'PY'
import os
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
path = root / 'skills' / 'research' / 'SKILL.md'
assert path.is_file(), path
text = path.read_text()
for contract in (
    'docs/research/research-<slug>.md',
    'WebSearch',
    'WebFetch',
    'owner/repo',
    'License',
    'Commit/tag',
    'Provenance',
    'chưa xác minh',
    '$ARGUMENTS` rỗng',
    'Preflight collision trước mọi research',
    'Không overwrite, append, đổi suffix',
    'project/repo hiện tại trước',
    'fork candidate',
    'fork thực tế',
):
    assert contract in text, f'Missing research contract {contract!r}: {path}'
assert text.index('Preflight collision trước mọi research') < text.index('### 1. Research project/repo hiện tại trước')
lower = text.lower()
assert 'không sửa source/config/test' in lower
assert 'không tạo fork' in lower
assert 'không commit, push hoặc publish' in lower
PY
}

@test "production deploy accepts pushed gate evidence or pending gated commits without rerunning full suites" {
  python3 - <<'PY'
import os
from pathlib import Path
path = Path(os.environ['TEMPLATE_ROOT']) / 'skills' / 'production-deploy' / 'SKILL.md'
text = path.read_text()
for contract in (
    'validation duy nhất trong phase deploy',
    '/git-push-safety',
    'KHÔNG invoke',
    'không fallback sang full suite',
    'remote HEAD',
    'pending commit',
    'không có evidence',
    'GIT_PUSH_GATE_OK=1 git push',
):
    assert contract in text, f'Missing production deploy gate contract {contract!r}: {path}'
for forbidden in ('npm test', 'pytest', 'go test ./...', 'cargo test'):
    assert forbidden not in text, f'Production deploy must not run full-suite command {forbidden!r}: {path}'
assert text.index('không có evidence') < text.index('GIT_PUSH_GATE_OK=1 git push')
assert 'docker compose up -d --build @@DEPLOY_SERVICE@@' in text, 'Docker rebuild is an allowed deploy action'
assert 'if [ -f bootstrap.sh ]; then bash bootstrap.sh; else' in text
assert 'bootstrap.sh ||' not in text, 'Bootstrap failure must not trigger fallback deploy'
assert 'bootstrap.sh` tồn tại nhưng fail' in text
PY
}

@test "production deploy verifies the exact Compose rollback container before smoke and success" {
  python3 - <<'PY'
import os
from pathlib import Path
path = Path(os.environ['TEMPLATE_ROOT']) / 'skills' / 'production-deploy' / 'SKILL.md'
text = path.read_text()
rollback = text.split('7. **Fail → tự động rollback.**', 1)[1].split('8. **Báo cáo.**', 1)[0]
for contract in (
    "rollback_ref='<rollback-ref>'",
    "service='@@DEPLOY_SERVICE@@'",
    'docker compose up -d --no-build',
    'docker compose ps --all --quiet',
    "docker inspect --format '{{.Image}}'",
    '$actual',
    '$rollback_ref',
    "ssh @@DEPLOY_SSH_HOST@@ '@@DEPLOY_HEALTHCHECK@@'",
    'FAIL + đã rollback',
):
    assert contract in rollback, f'Missing production deploy rollback contract {contract!r}: {path}'
order = (
    'docker compose up -d --no-build',
    'docker compose ps --all --quiet',
    "docker inspect --format '{{.Image}}'",
    '$actual',
    "ssh @@DEPLOY_SSH_HOST@@ '@@DEPLOY_HEALTHCHECK@@'",
    'FAIL + đã rollback',
)
positions = [rollback.index(item) for item in order]
assert positions == sorted(positions), f'Rollback verification order is unsafe: {positions}'
PY
}

@test "production deploy treats every rollback verification failure as incomplete and unhealthy" {
  python3 - <<'PY'
import os
from pathlib import Path
path = Path(os.environ['TEMPLATE_ROOT']) / 'skills' / 'production-deploy' / 'SKILL.md'
text = path.read_text()
rollback = text.split('7. **Fail → tự động rollback.**', 1)[1].split('8. **Báo cáo.**', 1)[0]
for failure in (
    'Không có container',
    'nhiều container',
    '`docker inspect` lỗi',
    'image không khớp',
    'Smoke fail/timeout',
):
    assert failure in rollback, f'Missing rollback failure contract {failure!r}: {path}'
assert rollback.count('FAIL + rollback unhealthy/incomplete') >= 2
assert 'target **unhealthy — STOP**' in rollback
assert rollback.index('Smoke pass') < rollback.index('FAIL + đã rollback')
assert 'không claim đã rollback' in rollback
PY
}

@test "production deploy template and installed copy stay semantically synchronized" {
  python3 - <<'PY'
import os
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
repo = Path(os.environ['REPO_ROOT'])
template = (root / 'skills' / 'production-deploy' / 'SKILL.md').read_text()
installed = (repo / '.claude' / 'skills' / 'production-deploy' / 'SKILL.md').read_text()
replacements = {
    '@@PROJECT_SLUG@@': 'ccswitch-cli-claude',
    '@@PROJECT_REMOTE_ID@@': 'github.com/kanalias/ace_commons-ccswitch-cli',
    '@@DEPLOY_SSH_HOST@@': '<deploy-ssh-host>',
    '@@DEPLOY_SERVICE@@': '<service-name>',
    '@@DEPLOY_PATH@@': '<remote-repo-path>',
    '@@DEPLOY_BRANCH@@': 'main',
    '@@DEPLOY_REMOTE@@': 'origin',
    '@@DEPLOY_HEALTHCHECK@@': '<healthcheck-cmd>',
}
for token, value in replacements.items():
    template = template.replace(token, value)
assert installed == template
PY
}

@test "production deploy stops when smoke configuration is missing" {
  python3 - <<'PY'
import os
from pathlib import Path
path = Path(os.environ['TEMPLATE_ROOT']) / 'skills' / 'production-deploy' / 'SKILL.md'
text = path.read_text()
assert 'smoke/healthcheck config thiếu' in text
assert 'STOP trước push/deploy' in text
assert 'không chạy full suite thay thế' in text
PY
}

@test "destructive and publishing workflows require explicit invocation and confirmation" {
  python3 - <<'PY'
import os, re
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
destructive = ('clean-up-project', 'doctor-memory', 'git-cleanup-branch', 'git-force-snapshot',
               'git-push-safety', 'production-cleanup', 'production-deploy', 'production-reboot')
for name in destructive:
    path = root / 'skills' / name / 'SKILL.md'
    assert path.is_file(), f'Missing workflow: {path}'
    _, frontmatter, body = path.read_text().split('---', 2)
    assert re.search(r'^disable-model-invocation: true$', frontmatter, re.M), path
    # gate wording may be EN or VI (repo docs are being translated) — both must say invocation != confirmation
    assert re.search(r'Explicit invocation is not confirmation|không phải là xác nhận', body, re.I), path
    assert re.search(r'confirm|xác nhận', body, re.I), path
# Local commits/PR publishing should not be triggered implicitly either.
for name in ('git-commit', 'git-commit-describe'):
    path = root / 'skills' / name / 'SKILL.md'
    assert path.is_file(), path
    assert 'disable-model-invocation: true' in path.read_text().split('---', 2)[1], path
PY
}

@test "templates contain no org/machine hardcodes" {
  python3 - <<'PY'
import os, re
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
files = list((root / 'skills').glob('**/*.md'))
assert files, 'No template markdown found'
patterns = [
    ('acegalaxy', re.compile(r'acegalaxy', re.I)),
    ('/Users/', re.compile(r'/Users/')),
    ('/opt/homebrew', re.compile(r'/opt/homebrew')),
    ('com.user.', re.compile(r'com\.user\.')),
    ('claude-ctxbar', re.compile(r'claude-ctxbar')),
    ('9router (lowercase)', re.compile(r'9router')),
    ('absolute date YYYY-MM-DD', re.compile(r'\b20\d\d-\d\d-\d\d\b')),
]
violations = []
for path in files:
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        for label, pattern in patterns:
            # ace-library is org-specific by design; its libs are public
            if label == 'acegalaxy' and path.parent.name == 'ace-library':
                continue
            if pattern.search(line):
                violations.append(f'{path}:{lineno}: {label}: {line.strip()}')
assert not violations, '\n'.join(violations)
PY
}

@test "templates use current command names and worktree path" {
  python3 - <<'PY'
import os, re
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
files = list((root / 'skills').glob('**/*.md'))
assert files, 'No template markdown found'
patterns = [
    ('stale /commit', re.compile(r'(?<![\w-])/commit(?![\w-])')),
    ('stale /clean-up', re.compile(r'(?<![\w-])/clean-up(?![\w-])')),
    ('stale .worktrees', re.compile(r'\.worktrees')),
]
violations = []
for path in files:
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        for label, pattern in patterns:
            if pattern.search(line):
                violations.append(f'{path}:{lineno}: {label}: {line.strip()}')
assert not violations, '\n'.join(violations)
PY
}

@test "relative markdown links in templates resolve" {
  python3 - <<'PY'
import os, re
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT']).resolve()
files = list((root / 'skills').glob('**/*.md'))
assert files, 'No template markdown found'
link_re = re.compile(r'\[[^\]]*\]\(([^)]+)\)')
violations = []
for path in files:
    in_fence = False
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        if line.strip().startswith('```'):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        # Drop inline code spans so example link syntax inside backticks isn't checked.
        line_no_code = re.sub(r'`[^`]*`', '', line)
        for m in link_re.finditer(line_no_code):
            target = m.group(1).strip()
            if not target or target.startswith(('http://', 'https://', 'mailto:', '#')):
                continue
            target_path = target.split('#', 1)[0].strip()
            if not target_path.endswith('.md'):
                continue
            resolved = (path.parent / target_path).resolve()
            try:
                resolved.relative_to(root)
            except ValueError:
                violations.append(f'{path}:{lineno}: link target outside TEMPLATE_ROOT: {target}')
                continue
            if not resolved.is_file():
                violations.append(f'{path}:{lineno}: broken relative link: {target}')
assert not violations, '\n'.join(violations)
PY
}

@test "installed copies mirror templates" {
  python3 - <<'PY'
import os
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT']).resolve()
repo = Path(os.environ['REPO_ROOT']).resolve()
files = list((root / 'skills').glob('**/*'))
files = [f for f in files if f.is_file()]
assert files, 'No template files found'
checked = 0
violations = []
for path in files:
    content = path.read_bytes()
    if b'@@' in content:
        continue
    rel = path.relative_to(root)
    installed = repo / '.claude' / rel
    if not installed.is_file():
        continue
    checked += 1
    if installed.read_bytes() != content:
        violations.append(f'drift: {installed} != {path}')
assert checked > 0, 'No installed/template pairs found to compare'
assert not violations, '\n'.join(violations)
PY
}

@test "task-loop-feature uses @@TEST_CMD@@ placeholder" {
  python3 - <<'PY'
import os
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
path = root / 'skills' / 'task-loop-feature' / 'SKILL.md'
assert path.is_file(), path
text = path.read_text()
assert '@@TEST_CMD@@' in text, f'Missing @@TEST_CMD@@ placeholder: {path}'
assert 'chưa cấu hình' not in text, f'Baked Vietnamese TEST_CMD phrase leaked into template: {path}'
PY
}
