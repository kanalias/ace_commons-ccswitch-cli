#!/bin/sh
# Evidence-based push gate (harness-managed — sửa upstream ở harness ccswitch).
# Runs the mechanical steps of .claude/skills/git-push-safety/SKILL.md
# automatically (NO confirmation prompt — user đã chốt), then (and only
# then) performs the push itself. The hook .claude/hooks/pre-bash-gate.sh
# exempts exactly this invocation from the "no raw git push" block.
#
# usage (from the repo root, or with a `cd <repo> &&` prefix):
#   sh .claude/skills/git-push-safety/push-safe.sh [--full] <remote> <branch>
#   --full   also scan the WHOLE history with gitleaks (read-only, nice,
#            --redact). Slow on big repos — only when explicitly asked.
#
# Order (STOP on first failure, clear message, nothing pushed):
#   0) refuse --force/--all/--mirror/--tags (and -f/--force-with-lease)
#   0.5) private-branch gate (.claude/private-branches.txt)
#   a) gitleaks must be installed (hard stop if missing)
#   b) repo tests (auto-detect: bats / npm test / pytest / go test /
#      cargo test; none found -> say so, do not guess, do not fail)
#   c) gitleaks on the push range only (<remote-sha>..HEAD, or
#      `HEAD --not --remotes` for a brand-new branch) — skipped here when the
#      harness .git/hooks/pre-push (GITLEAKS_FULL-aware) will scan the same
#      range during the push (no double scan) — plus `git diff HEAD |
#      gitleaks stdin` for uncommitted changes
#   d) .claude/sensitive-patterns.txt grep over the push diff, if present
#   e) forbidden/oversized file check (>=95,000,000 byte files in the
#      working tree or in blobs introduced by the push range; tracked
#      .env*/*.pem/*.key/private-key/security_envs paths)
#   f) deploy-surface / RBAC / README-drift: DETECT + report only. Judgment
#      calls (deploy-security.md, rbac-security.md, README compare) that
#      cannot be fully scripted — flagged for the agent to read, never
#      silently treated as "pass".
#
# Right before pushing it prints `git diff --stat` + changed files of the push
# range (informational, for the manual read the skill calls for).
#
# On success: writes .claude/state/push-ok-<HEAD sha>-<remote> (only if
# .claude/state is gitignored), pushes with
#   GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=60}"
# and, if the push cannot connect and PUSH_SAFE_PROXY_JUMP=<host> is set, retries
# once over `ssh -o ProxyJump=<host>` (ssh remotes only). Then verifies
# `git ls-remote <remote> <branch>` == HEAD and prints one summary line.
#
# Bypass (USER-ORDERED ONLY, never added by an agent):
#   GIT_PUSH_GATE_OK=1 git push <remote> <branch>
set -eu

stop() { echo "STOP: $*" >&2; exit 1; }

# ── 0) parse args, refuse dangerous flags ───────────────────────────────────
FULL=0
REMOTE=
BRANCH=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --full) FULL=1 ;;
    --force|--force-with-lease|--force-with-lease=*|-f)
      stop "refuses force-push flags ($1) — not allowed via push-safe.sh" ;;
    --all) stop "refuses --all" ;;
    --mirror) stop "refuses --mirror" ;;
    --tags) stop "refuses --tags" ;;
    -*) stop "unknown/forbidden flag: $1" ;;
    *)
      if [ -z "$REMOTE" ]; then REMOTE=$1
      elif [ -z "$BRANCH" ]; then BRANCH=$1
      else stop "unexpected extra argument: $1"
      fi ;;
  esac
  shift
done
[ -n "$REMOTE" ] && [ -n "$BRANCH" ] || stop "usage: sh .claude/skills/git-push-safety/push-safe.sh [--full] <remote> <branch>"

# ── repo root = the repo of the current directory (works in worktrees) ─────
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || stop "not inside a git repo: $(pwd)"
cd "$ROOT" || stop "cannot cd to repo root: $ROOT"

git remote get-url "$REMOTE" >/dev/null 2>&1 || stop "unknown remote: $REMOTE (git remote -v to list)"
case "$BRANCH" in ''|*[[:space:]]*|*:*) stop "invalid branch name: $BRANCH (no refspec, push one local branch)" ;; esac
git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || stop "local branch not found: $BRANCH"
# scan + push the branch tip (not necessarily HEAD — auto-push may push main + working branch)
TIP=$(git rev-parse "refs/heads/$BRANCH")
CUR_BRANCH=$(git symbolic-ref -q --short HEAD 2>/dev/null || true)

echo "push-safe: repo=$ROOT remote=$REMOTE branch=$BRANCH full=$FULL"

# ── 0.5) private-branch gate (.claude/private-branches.txt, no bypass) ─────
# Format: <branch> <remote|remote…> <url-substring|…> — allowed if the target
# remote NAME is listed or its URL contains any listed substring.
PB_LIST="$ROOT/.claude/private-branches.txt"
if [ -s "$PB_LIST" ]; then
  REMOTE_URL_SELF=$(git remote get-url "$REMOTE" 2>/dev/null || printf '%s' "$REMOTE")
  while IFS=' ' read -r pb_br pb_remote pb_url || [ -n "$pb_br" ]; do
    case "$pb_br" in ''|\#*) continue ;; esac
    [ "$pb_br" = "$BRANCH" ] || continue
    case "|$pb_remote|" in *"|$REMOTE|"*) continue ;; esac
    ok=0
    old_ifs=$IFS
    IFS='|'
    for alt in $pb_url; do
      [ -n "$alt" ] || continue
      case "$REMOTE_URL_SELF" in *"$alt"*) ok=1 ;; esac
    done
    IFS=$old_ifs
    [ "$ok" = 1 ] && continue
    stop "private-branch gate: branch '$pb_br' may only push to remote '$pb_remote' ($pb_url) — refusing push to '$REMOTE'. See .claude/private-branches.txt"
  done < "$PB_LIST"
fi

# ── a) gitleaks must be installed ───────────────────────────────────────────
echo "== [a] gitleaks installed =="
command -v gitleaks >/dev/null 2>&1 || stop "gitleaks not installed. Install: macOS 'brew install gitleaks'; Linux 'apt install gitleaks' / 'pacman -S gitleaks'; any OS with Go 'go install github.com/gitleaks/gitleaks/v8@latest'. Then re-run."

# ── b) repo tests (auto-detect, skill step 1 order) ─────────────────────────
echo "== [b] repo tests =="
if [ "${PUSH_SAFE_SKIP_TESTS:-}" = 1 ]; then
  echo "NOTE: PUSH_SAFE_SKIP_TESTS=1 — tests skipped (user-ordered only)." >&2
elif ls test/*.bats >/dev/null 2>&1; then
  NCPU=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
  if command -v parallel >/dev/null 2>&1; then
    bats -j "$NCPU" test/*.bats || stop "tests failed (bats -j $NCPU test/*.bats)"
  else
    echo "WARN: GNU parallel missing (brew install parallel) — running bats serially" >&2
    BATS_SERIAL_OK=1 bats test/*.bats || stop "tests failed (bats, serial fallback)"
  fi
elif [ -f package.json ] && command -v node >/dev/null 2>&1 && node -e "var p=require('./package.json'); process.exit(p.scripts && p.scripts.test && !/no test specified/.test(p.scripts.test) ? 0 : 1)" 2>/dev/null; then
  npm test || stop "tests failed (npm test)"
elif [ -f pytest.ini ] || { [ -f pyproject.toml ] && grep -q 'pytest' pyproject.toml 2>/dev/null; } || { [ -d tests ] && ls tests/test_*.py tests/*_test.py >/dev/null 2>&1; }; then
  pytest || stop "tests failed (pytest)"
elif [ -f go.mod ]; then
  go test ./... || stop "tests failed (go test ./...)"
elif [ -f Cargo.toml ]; then
  cargo test || stop "tests failed (cargo test)"
else
  echo "NOTE: no standard test command detected (test/*.bats, package.json scripts.test, pytest config, go.mod, Cargo.toml) — automated tests skipped (skill step 1: do not guess). Run repo-specific tests by hand if this push touches them." >&2
fi

# ── c) gitleaks on the push range only ──────────────────────────────────────
echo "== [c] gitleaks (push range) =="
git fetch -q "$REMOTE" "$BRANCH" 2>/dev/null || true
REMOTE_SHA=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH" 2>/dev/null || true)
[ -n "$REMOTE_SHA" ] || REMOTE_SHA=$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1; exit}')

if [ -n "$REMOTE_SHA" ] && git cat-file -e "${REMOTE_SHA}^{commit}" 2>/dev/null; then
  RANGE="$REMOTE_SHA..$TIP"
  HAVE_REMOTE_COMMIT=1
  git merge-base --is-ancestor "$REMOTE_SHA" "$TIP" \
    || stop "non-fast-forward: $REMOTE/$BRANCH ($REMOTE_SHA) is not an ancestor of $BRANCH — remote diverged. Do not force-push; sync first (fetch + merge/rebase) after checking what is on the remote."
else
  RANGE="$TIP --not --remotes"
  HAVE_REMOTE_COMMIT=0
fi
# shellcheck disable=SC2086
PUSH_COMMIT_COUNT=$(git rev-list --count $RANGE 2>/dev/null || echo 0)
PREPUSH_HOOK="$(git rev-parse --git-path hooks)/pre-push"
if [ "$PUSH_COMMIT_COUNT" -gt 0 ]; then
  if [ -x "$PREPUSH_HOOK" ] && grep -q 'GITLEAKS_FULL' "$PREPUSH_HOOK" 2>/dev/null; then
    echo "push range ($PUSH_COMMIT_COUNT commit): scanned by .git/hooks/pre-push during push (no double scan)"
  else
    # shellcheck disable=SC2086
    nice -n 10 gitleaks git --no-banner --redact -v --max-target-megabytes 10 --log-opts="$RANGE" "$ROOT" \
      || stop "gitleaks found a secret in push range ($RANGE). Fix the leak — do not bypass on the user's behalf."
  fi
else
  echo "no new commits in range ($RANGE)"
fi
if [ "$CUR_BRANCH" = "$BRANCH" ]; then
  git diff HEAD | gitleaks stdin --no-banner --redact -v \
    || stop "gitleaks found a secret in the uncommitted working-tree diff (git diff HEAD)."
fi

if [ "$FULL" = 1 ]; then
  echo "-- --full: scanning entire history (read-only) --"
  nice -n 10 gitleaks git --no-banner --redact "$ROOT" \
    || stop "gitleaks found a secret in full-history scan (--full)."
fi

# ── d) .claude/sensitive-patterns.txt grep over the push diff ───────────────
echo "== [d] sensitive-patterns.txt =="
SP="$ROOT/.claude/sensitive-patterns.txt"
EMPTY_TREE=$(git hash-object -t tree /dev/null)
if [ -s "$SP" ]; then
  if [ "$HAVE_REMOTE_COMMIT" = 1 ]; then
    SP_HIT=$(git diff "${REMOTE_SHA}...$TIP" 2>/dev/null | grep '^+' | grep -cEf "$SP" || true)
  else
    SP_HIT=$(git diff "$EMPTY_TREE" "$TIP" 2>/dev/null | grep '^+' | grep -cEf "$SP" || true)
  fi
  if [ "${SP_HIT:-0}" -gt 0 ]; then
    stop ".claude/sensitive-patterns.txt matched $SP_HIT added line(s) in push diff — review before pushing (match not printed to avoid leaking content; inspect manually with the same grep)."
  fi
  echo "sensitive-patterns.txt: no match"
else
  echo "sensitive-patterns.txt: N/A (file absent or empty)"
fi

# ── e) forbidden / oversized file check ─────────────────────────────────────
echo "== [e] forbidden / oversized files =="
BIG=$(git ls-files -co --exclude-standard -z 2>/dev/null \
  | xargs -0 -I{} find {} -maxdepth 0 -type f -size +94999999c 2>/dev/null || true)
[ -z "$BIG" ] || stop "file(s) >= 95,000,000 bytes tracked/untracked in working tree (not allowed to push, no LFS without explicit request): $(printf '%s' "$BIG" | tr '\n' ' ')"

if [ "$PUSH_COMMIT_COUNT" -gt 0 ]; then
  # shellcheck disable=SC2086
  BIGBLOB=$(git rev-list --objects $RANGE 2>/dev/null \
    | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' 2>/dev/null \
    | awk '$1=="blob" && $2+0>=95000000 {print $3" ("$2" bytes)"}' || true)
  [ -z "$BIGBLOB" ] || stop "blob(s) >= 95,000,000 bytes introduced in push range ($RANGE): $BIGBLOB"
fi

FORBIDDEN=$(git ls-files \
  | grep -E '(^|/)\.env([.][A-Za-z0-9_.-]*)?$|\.pem$|\.key$|(^|/)(id_rsa|id_ed25519|id_ecdsa|id_dsa)$|security_envs' \
  | grep -Ev '(^|/)\.env([.][A-Za-z0-9_-]+)*\.(example|sample|template)$' || true)
[ -z "$FORBIDDEN" ] || stop "forbidden tracked path(s) (.env*/*.pem/*.key/private key/security_envs): $FORBIDDEN"

echo "no oversized/forbidden files found"

# ── f) deploy-surface / RBAC / README-drift — detect + report only ─────────
echo "== [f] deploy-surface / RBAC / README-drift (detect only, not fully scripted) =="
if [ "$HAVE_REMOTE_COMMIT" = 1 ]; then
  TOUCHED=$(git diff --name-only "${REMOTE_SHA}...$TIP" 2>/dev/null || true)
else
  TOUCHED=$(git diff --name-only "$EMPTY_TREE" "$TIP" 2>/dev/null || true)
fi

if git ls-files | grep -qE '(^|/)rbac\.json$' \
  || git grep -qE 'lib-notion-rbac|NotionRbac|AceLoginTicket|verifyTicket' -- . ':!.claude' ':!*.md' 2>/dev/null; then
  echo "RBAC: DETECTED — manual review required (.claude/rules/common/rbac-security.md mục 2-3). NOT fully scripted here."
else
  echo "RBAC: N/A"
fi

if printf '%s\n' "$TOUCHED" | grep -Eq '(^|/)(Dockerfile|docker-compose|compose\.ya?ml|\.dockerignore|nginx/|[^/]*\.conf$|Caddyfile|ecosystem\.config\.|package\.json|\.gitlab-ci\.yml|\.github/workflows/)'; then
  echo "deploy-surface: diff touches CI/Docker/nginx/package.json — manual review required (.claude/rules/common/deploy-security.md mục 1,2,4). NOT fully scripted here."
else
  echo "deploy-surface: N/A"
fi

if [ -f "$ROOT/README.md" ] && printf '%s\n' "$TOUCHED" | grep -Eq '\.(sh|mjs|js|ts|py|json)$|(^|/)README\.md$'; then
  echo "README-drift: diff touches code/README — manual check: README command/flag/env examples still match (skill step 3.5). NOT fully scripted here."
else
  echo "README-drift: N/A"
fi

# ── judgment (manual read) — informational only, not a pass/fail gate ──────
echo "== judgment: git diff --stat (read these — not scripted) =="
if [ "$HAVE_REMOTE_COMMIT" = 1 ]; then
  git diff --stat "${REMOTE_SHA}...$TIP" | tail -40 || true
else
  git log --oneline $RANGE 2>/dev/null | head -40 || true
fi

# ── all mechanical checks passed: evidence file, then push ─────────────────
HEAD_SHA=$TIP
if git check-ignore -q ".claude/state/push-ok-probe" 2>/dev/null; then
  mkdir -p "$ROOT/.claude/state"
  EVIDENCE_FILE="$ROOT/.claude/state/push-ok-${HEAD_SHA}-${REMOTE}"
  {
    echo "sha=$HEAD_SHA"
    echo "branch=$BRANCH"
    echo "remote=$REMOTE"
    echo "full=$FULL"
    echo "checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$EVIDENCE_FILE"
  echo "evidence written: $EVIDENCE_FILE"
else
  echo "NOTE: .claude/state/ not gitignored — evidence file skipped" >&2
fi

echo "== pushing $HEAD_SHA → $REMOTE $BRANCH =="
SSH_CMD=${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=60}
[ "$FULL" = 1 ] && export GITLEAKS_FULL=1
PUSH_LOG=$(mktemp "${TMPDIR:-/tmp}/push-safe.XXXXXX")
trap 'rm -f "$PUSH_LOG"' EXIT
set +e
GIT_SSH_COMMAND="$SSH_CMD" git push "$REMOTE" "$BRANCH" >"$PUSH_LOG" 2>&1
rc=$?
set -e
cat "$PUSH_LOG"
if [ "$rc" -ne 0 ]; then
  URL=$(git remote get-url --push "$REMOTE")
  case "$URL" in ssh://*|*@*:*) IS_SSH=1 ;; *) IS_SSH=0 ;; esac
  if [ -n "${PUSH_SAFE_PROXY_JUMP:-}" ] && [ "$IS_SSH" = 1 ] \
     && grep -Eqi "couldn't connect|could not resolve|connection (timed out|refused|closed)|operation timed out|no route to host|network is unreachable" "$PUSH_LOG" \
     && ! grep -Eq 'rejected|non-fast-forward|pre-push' "$PUSH_LOG"; then
    echo "push could not connect — retrying via ProxyJump=$PUSH_SAFE_PROXY_JUMP" >&2
    SSH_CMD="ssh -o ProxyJump=$PUSH_SAFE_PROXY_JUMP -o BatchMode=yes -o ConnectTimeout=60"
    GIT_SSH_COMMAND="$SSH_CMD" git push "$REMOTE" "$BRANCH" || stop "git push failed (also via ProxyJump=$PUSH_SAFE_PROXY_JUMP)"
  else
    # Server-side race (e.g. "cannot lock ref ... is at <our sha>") can fail the
    # push after the ref already moved; accept only if ls-remote shows our tip.
    LANDED=$(GIT_SSH_COMMAND="$SSH_CMD" git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1; exit}')
    if [ "$LANDED" = "$HEAD_SHA" ] && ! grep -Eq 'rejected|non-fast-forward|pre-push' "$PUSH_LOG"; then
      echo "WARN: git push exit $rc but remote $BRANCH already at $HEAD_SHA — treating as pushed" >&2
    else
      stop "git push failed (exit $rc, see output above)"
    fi
  fi
fi

REMOTE_AFTER=$(GIT_SSH_COMMAND="$SSH_CMD" git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1; exit}')
[ "$REMOTE_AFTER" = "$HEAD_SHA" ] \
  || stop "post-push verify failed: ls-remote $REMOTE $BRANCH = ${REMOTE_AFTER:-<none>}, expected $HEAD_SHA"

echo "PUSH-SAFE OK: repo=$(basename "$ROOT") branch=$BRANCH sha=$HEAD_SHA remote=$REMOTE result=PASS (verified via git ls-remote)"
