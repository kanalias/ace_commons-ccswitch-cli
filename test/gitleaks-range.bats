#!/usr/bin/env bats
# pre-push gitleaks: chỉ quét commit sắp push (không full history); full chỉ khi GITLEAKS_FULL=1.
load test_helper

setup() {
  command -v gitleaks >/dev/null || skip "gitleaks chưa cài"
  setup_fake_home
  W="$BATS_TEST_TMPDIR/w"
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git init -q "$W"
  git -C "$W" config user.email t@t; git -C "$W" config user.name t
  git -C "$W" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  cp "$(repo_root)/harness/templates/git-hooks/pre-push" "$W/.git/hooks/pre-push"
  chmod +x "$W/.git/hooks/pre-push"
  commit a clean
  git -C "$W" push -q origin HEAD:main 2>/dev/null
  # leak cũ đã lên remote (bypass có chủ đích)
  echo "token = \"$(tok)\"" > "$W/old.cfg"; git -C "$W" add old.cfg; git -C "$W" commit -qm old
  GITLEAKS_SKIP=1 git -C "$W" push -q origin HEAD:main 2>/dev/null
}

tok() { echo "ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"; }
commit() { echo "$2" > "$W/$1"; git -C "$W" add "$1"; git -C "$W" commit -qm "$1"; }

@test "gitleaks pre-push: commit sach tren nen leak cu da push -> pass (khong quet lai history)" {
  commit b clean
  run git -C "$W" push origin HEAD:main
  [ "$status" -eq 0 ]; [[ "$output" == *"1 commit sắp push"* ]]
}

@test "gitleaks pre-push: commit moi co leak -> block" {
  commit new.cfg "token2 = \"$(tok)\""
  run git -C "$W" push origin HEAD:main
  [ "$status" -ne 0 ]; [[ "$output" == *"CHẶN push"* ]]
}

@test "gitleaks pre-push: nhanh moi chi quet commit chua co tren remote" {
  git -C "$W" checkout -q -b feat/x; commit c clean
  run git -C "$W" push origin feat/x
  [ "$status" -eq 0 ]; [[ "$output" == *"1 commit sắp push"* ]]
}

@test "gitleaks pre-push: GITLEAKS_FULL=1 quet full history -> bat leak cu" {
  commit d clean
  GITLEAKS_FULL=1 run git -C "$W" push origin HEAD:main
  [ "$status" -ne 0 ]; [[ "$output" == *"FULL history"* ]]
}
