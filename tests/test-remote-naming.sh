#!/bin/sh
# "origin" is a convention, not a guarantee. A repo cloned under another name,
# or one with a fork plus an upstream, used to leave the plugin inoperative --
# every push failing, with nothing but "push failed" to go on.
. "$(dirname "$0")/lib.sh"

it "works with a remote not named origin"
new_world
git remote rename origin github
git branch -q --set-upstream-to=github/main main 2>/dev/null
printf 'some work\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pushed" "push via 'github'"
[ -n "$(sync_branch_sha git-sync/main)" ] || fail "no checkpoint on the remote"
cleanup_world

it "picks the branch's upstream when several remotes exist"
new_world
git remote add upstream "$WORLD/remote.git"
git branch -q --set-upstream-to=origin/main main 2>/dev/null
printf 'some work\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pushed" "push via the upstream"
cleanup_world

it "refuses clearly when no remote can be picked"
new_world
git remote rename origin fork
git remote add autre "$WORLD/remote.git"
git branch -q --unset-upstream main 2>/dev/null
printf 'some work\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "cannot pick a remote" "explicit message"
cleanup_world

exit $FAILURES
