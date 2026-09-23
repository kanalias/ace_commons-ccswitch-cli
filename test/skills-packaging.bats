#!/usr/bin/env bats

setup() {
  export TEMPLATE_ROOT="${SKILLS_TEMPLATE_ROOT:-$BATS_TEST_DIRNAME/../harness/templates}"
}

@test "every legacy command has exactly one same-name first-class skill" {
  python3 - <<'PY'
import os
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
commands = list((root / 'commands').glob('*.md'))
assert commands, 'No legacy commands found'
for command in commands:
    matches = list((root / 'skills').glob(f'{command.stem}/SKILL.md'))
    assert len(matches) == 1, f'Missing skill: {command.stem}'
PY
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

@test "skill equivalents preserve command workflows and confirmation gates" {
  python3 - <<'PY'
import os, re
from pathlib import Path
root = Path(os.environ['TEMPLATE_ROOT'])
def body(path):
    text = path.read_text().split('---', 2)[2]
    # Relative Markdown references must resolve from the deeper skill directory.
    text = re.sub(r'\]\(\.\./([^/()]+?)/SKILL\.md\)', r'](\1.md)', text)
    text = text.replace('](../../rules/', '](../rules/')
    return text
for command in (root / 'commands').glob('*.md'):
    skill = root / 'skills' / command.stem / 'SKILL.md'
    assert skill.is_file(), f'Missing skill: {command.stem}'
    assert body(command) == body(skill), f'Workflow drift: {command.stem}'
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
    for path in (root / 'commands' / f'{name}.md', root / 'skills' / name / 'SKILL.md'):
        assert path.is_file(), f'Missing workflow: {path}'
        _, frontmatter, body = path.read_text().split('---', 2)
        assert re.search(r'^disable-model-invocation: true$', frontmatter, re.M), path
        assert 'Explicit invocation is not confirmation' in body, path
        assert re.search(r'confirm|xác nhận', body, re.I), path
# Local commits/PR publishing should not be triggered implicitly either.
for name in ('auto-commit', 'git-commit', 'git-commit-describe'):
    path = root / 'skills' / name / 'SKILL.md'
    assert path.is_file(), path
    assert 'disable-model-invocation: true' in path.read_text().split('---', 2)[1], path
PY
}
