#!/usr/bin/env bats
# Regression: lỗ khiến main agent tự sửa core thay vì delegate (audit bds-hue 2026-10-10).
#  1) prefix ORCHESTRATOR_GATE_BYPASS=1 trong lệnh Bash không có tác dụng (hook đọc env của chính nó)
#  2) Edit trong .claude/worktrees/<slug>/<core>/ lọt qua allowlist */.claude/*
#  3) Bash ghi core qua interpreter heredoc / node -e / cd <core>; sed -i / perl -0pi lọt
#  3b) ngược lại: chuỗi "> src/" trong pattern grep / heredoc ghi file ngoài core bị chặn oan
#  4) SessionStart không đưa luật delegate vào context model (banner chỉ ở stderr)
load test_helper.bash

setup() {
  setup_fake_home
  ROOT="$(repo_root)"
  R="$BATS_TEST_TMPDIR/hooks"; mkdir -p "$R"
  for h in pre-bash-gate pre-edit-orchestrator-gate session-start; do
    sed -e 's#@@CORE_DIRS_CASE@@#*/src/*|src/*#g' -e 's#@@CORE_DIRS_ALT@@#src#g' \
        -e 's#@@CORE_DIRS_HUMAN@@#src/#g' -e 's#@@PROJECT_SLUG@@#t#g' \
        "$ROOT/harness/templates/hooks/$h.sh" > "$R/$h.sh"
  done
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"; mkdir -p "$CLAUDE_PROJECT_DIR"
  unset ORCHESTRATOR_GATE_BYPASS HARNESS_DELEGATE
}

bash_gate() {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "$(jq -nc --arg c "$1" --arg a "${2:-}" '{tool_input:{command:$c}} + (if $a=="" then {} else {agent_id:$a} end)')" \
    "$R/pre-bash-gate.sh"
}
edit_gate() {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "$(jq -nc --arg f "$1" --arg a "${2:-}" '{tool_input:{file_path:$f}} + (if $a=="" then {} else {agent_id:$a} end)')" \
    "$R/pre-edit-orchestrator-gate.sh"
}

@test "1) bypass prefix inside the Bash command is honoured and audited" {
  for c in "ORCHESTRATOR_GATE_BYPASS=1 sed -i '' 's/a/b/' src/x.ts" \
           "export ORCHESTRATOR_GATE_BYPASS=1; sed -i '' 's/a/b/' src/x.ts" \
           "cd /r && ORCHESTRATOR_GATE_BYPASS=1 perl -0pi -e 's/a/b/' src/x.ts"; do
    bash_gate "$c"; [ "$status" -eq 0 ] || { echo "should allow: $c"; false; }
  done
  grep -q ' BYPASS main-agent bash-write' "$HOME/.cache/claude-code-t/orchestrator-gate.log"
  # bypass KHÔNG mở direct-CLI (isolation boundary)
  bash_gate "ORCHESTRATOR_GATE_BYPASS=1 codex exec hi"; [ "$status" -eq 2 ]
  # chuỗi bypass không đứng ở vị trí assignment → không tính
  bash_gate "echo xORCHESTRATOR_GATE_BYPASS=1 > src/x.ts"; [ "$status" -eq 2 ]
}

@test "2) main-agent Edit of core inside a worktree is blocked; non-core allowed" {
  for f in /r/.claude/worktrees/foo/src/a.ts .claude/worktrees/foo/src/a.ts /r/src/a.ts; do
    edit_gate "$f"; [ "$status" -eq 2 ] || { echo "should block: $f"; false; }
  done
  # Edit không có bypass → message phải chỉ đường thật (delegate hoặc Bash prefix)
  [[ "$output" == *"Bash"* ]]
  for f in /r/.claude/worktrees/foo/.claude/skills/x/SKILL.md /r/.claude/worktrees/foo/docs/a.md \
           /r/.claude/skills/x/SKILL.md /r/test/a.bats /r/.claude/worktrees/foo/test/a.bats; do
    edit_gate "$f"; [ "$status" -eq 0 ] || { echo "should allow: $f"; false; }
  done
  edit_gate /r/.claude/worktrees/foo/src/a.ts sub1; [ "$status" -eq 0 ]
}

@test "3) Bash writes into core via interpreter / cd-into-core / perl -0pi are blocked" {
  local nl=$'\n'
  for c in "python3 - <<'EOF'${nl}p='src/a.ts'; s=open(p).read(); open(p,'w').write(s)${nl}EOF" \
           "python3 -c \"open('src/a.ts','w').write('x')\"" \
           "node -e \"require('fs').writeFileSync('src/a.ts','x')\"" \
           "cd src/apps/web; sed -i '' 's/a/b/' app/x.tsx" \
           "cd /abs/repo/src/apps/web && perl -0pi -e 's/a/b/' x.ts" \
           "perl -0pi -e 's/a/b/' src/x.ts" \
           "cd src/apps/web; python3 - <<'EOF'${nl}open('app/x.tsx','w').write('')${nl}EOF" \
           "cd src/apps/web && cat > app/x.tsx <<'EOF'${nl}x${nl}EOF" \
           "cat > src/x.ts <<'EOF'${nl}x${nl}EOF"; do
    bash_gate "$c"; [ "$status" -eq 2 ] || { echo "should block: $c"; false; }
  done
}

@test "3b) read-only / non-core Bash stays allowed (no false positives)" {
  local nl=$'\n'
  for c in "sed -n 1,20p src/x.ts | grep -n 'sed -i\\|src/'" \
           "grep -n 'sed -i\\|tee\\|src/' .claude/hooks/pre-bash-gate.sh" \
           "cd src/apps/web; npx tsc --noEmit 2>&1 | head" \
           "cd src/apps/web; grep -rn foo . > /tmp/out" \
           "python3 - <<'EOF'${nl}print(open('src/a.ts').read())${nl}EOF" \
           "cat > test/a.bats <<'EOF'${nl}echo x > src/y.ts${nl}EOF" \
           "git status" "sed -i '' 's/a/b/' docs/x.md" \
           "cd src && npm test 2>/dev/null" \
           "cd src/p && npm install --no-audit x 2>&1 | tail -1; git diff" \
           "rm -f l.fifo && ( sleep 900 > l.fifo & ) && ( cd /r/src/t && npm run login < /p/l.fifo > /p/out.txt 2>&1 & )" \
           "S=src/p; rsync -az --delete \$S/ host:/apps/r/\$S/" \
           "rsync -az src/p/a.ts host:/apps/r/src/p/a.ts && echo DONE" \
           "python3 - <<'EOF'${nl}p='.github/workflows/ci.yml'; s=open(p).read()${nl}s=s.replace('context: src','file: src/apps/x')${nl}open(p,'w').write(s)${nl}EOF" \
           "git add src/a.ts && git commit -q -m \"feat: x${nl}${nl}cd src/p && sed -i y\"" \
           "cd /r/src/f; cat > /tmp/d.mts <<'EOF'${nl}import x from 'y';${nl}EOF${nl}npx tsx /tmp/d.mts" \
           "cd src/w; curl -s u | python3 -c \"import json,sys${nl}print(sys.stdin.read().replace('a','b'))\"" \
           "cd src/p && npm test && cd /r/repo && rm -f x && echo ok > .claude/state/x.md"; do
    bash_gate "$c"; [ "$status" -eq 0 ] || { echo "false positive: $c"; echo "$output"; false; }
  done
  bash_gate "cd src/apps/web; sed -i '' 's/a/b/' app/x.tsx" sub1; [ "$status" -eq 0 ]
}

@test "3c) session cwd already inside core: relative write blocked, read allowed" {
  local pd="$CLAUDE_PROJECT_DIR" nl=$'\n'
  run_cwd() { run bash -c 'printf "%s" "$1" | bash "$2"' _ "$(jq -nc --arg c "$1" --arg d "$2" '{tool_input:{command:$c},cwd:$d}')" "$R/pre-bash-gate.sh"; }
  for d in "$pd/src/apps/web" "$pd/.claude/worktrees/foo/src/apps/web"; do
    run_cwd "sed -i '' 's/a/b/' app/x.tsx" "$d"; [ "$status" -eq 2 ] || { echo "should block in $d"; false; }
    run_cwd "python3 - <<'EOF'${nl}open('app/x.tsx','w').write('')${nl}EOF" "$d"; [ "$status" -eq 2 ]
    run_cwd "npx tsc --noEmit 2>&1 | head; grep -rn foo app > /tmp/o" "$d"; [ "$status" -eq 0 ]
  done
  run_cwd "sed -i '' 's/a/b/' docs/x.md" "$pd"; [ "$status" -eq 0 ]
  run_cwd "sed -i '' 's/a/b/' x.md" "$pd/.claude/worktrees/foo/docs"; [ "$status" -eq 0 ]
}

@test "4) SessionStart puts the delegate routing rule on stdout (model context)" {
  run bash -c 'echo "{}" | bash "$1" 2>/dev/null' _ "$R/session-start.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delegate-sonnet"* ]]
  [[ "$output" == *"src/"* ]]
  [[ "$output" == *"ORCHESTRATOR_GATE_BYPASS=1"* ]]
}
