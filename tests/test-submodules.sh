#!/bin/sh
# A submodule's content lives in its own repository, so a checkpoint cannot
# carry it. What it must not do is pretend otherwise: shipping the local gitlink
# points the other machine at a commit only this machine has.
. "$(dirname "$0")/lib.sh"

git config --global protocol.file.allow always 2>/dev/null

new_world
git init -q --bare "$WORLD/sub.git"
git -C "$WORLD/sub.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$WORLD/subsrc"
( cd "$WORLD/subsrc" && git config user.email s@t && git config user.name S \
    && echo v1 > lib.txt && git add -A && git commit -qm v1 \
    && git push -q "$WORLD/sub.git" main ) 2>/dev/null
git submodule add -q "$WORLD/sub.git" vendor 2>/dev/null
git commit -qm "add submodule" && git push -q origin main 2>/dev/null

it "warns that submodule content does not travel"
printf 'some work\n' >> file.txt
( cd vendor && echo v2 > lib.txt && git add -A \
    && git -c user.email=s@t -c user.name=S commit -qm v2 ) >/dev/null 2>&1
out=$(run_stop)
assert_contains "$out" "submodule contents" "warning"
assert_contains "$out" "vendor" "submodule path"

it "does not ship a pointer the other machine cannot resolve"
git fetch -q origin "+refs/heads/git-sync/main:refs/probe" 2>/dev/null
assert_eq "$(git ls-tree HEAD vendor | awk '{print $3}')" \
          "$(git ls-tree refs/probe vendor | awk '{print $3}')" "gitlink pinned to HEAD"

it "and the rest of the work still gets through"
assert_contains "$(git show refs/probe:file.txt)" "some work" "file.txt"

cleanup_world
exit $FAILURES
