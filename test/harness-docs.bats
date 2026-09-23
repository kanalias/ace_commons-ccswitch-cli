#!/usr/bin/env bats

load test_helper.bash

setup() {
  ROOT="$(repo_root)"
}

@test "harness version is a single semantic version line" {
  [ -f "$ROOT/harness/VERSION" ]
  [ "$(wc -l < "$ROOT/harness/VERSION" | tr -d ' ')" = 1 ]
  run grep -Ex '[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/harness/VERSION"
  [ "$status" -eq 0 ]
}

@test "harness has no macOS metadata and ignores future metadata" {
  run find "$ROOT/harness" -name .DS_Store -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run git -C "$ROOT" check-ignore --no-index harness/templates/.DS_Store
  [ "$status" -eq 0 ]
}

@test "lifecycle documentation includes dry run uninstall and ownership" {
  [ -f "$ROOT/harness/README.md" ]
  for contract in 'HARNESS_DRY_RUN=1' 'HARNESS_ASSUME_YES=1' 'uninstall' 'sha256' 'preserve' 'VERSION'; do
    run grep -F "$contract" "$ROOT/harness/README.md"
    [ "$status" -eq 0 ]
  done
}

@test "rule loading documentation distinguishes native loading from enforcement" {
  run grep -F 'native' "$ROOT/harness/templates/rules/common/rule-loading-policy.md"
  [ "$status" -eq 0 ]
  run grep -F 'native' "$ROOT/harness/README.md"
  [ "$status" -eq 0 ]
  run grep -R -F 'không có cơ chế "rule loading" built-in nào cả' "$ROOT/harness/templates/rules"
  [ "$status" -eq 1 ]
}

@test "relative markdown links in live .claude commands and skills resolve" {
  run python3 - "$ROOT" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1]) / '.claude'
bad = []
for f in list(root.glob('commands/*.md')) + list(root.glob('skills/*/SKILL.md')):
    for link in re.findall(r'\]\((\.{1,2}/[^)#]+)', f.read_text()):
        if not (f.parent / link).exists():
            bad.append(f'{f.relative_to(root.parent)} -> {link}')
print('\n'.join(bad))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
