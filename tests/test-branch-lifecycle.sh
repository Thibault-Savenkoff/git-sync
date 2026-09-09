#!/bin/sh
# Branches get renamed, deleted and nested. The checkpoint ref is derived from
# the branch name, so all three move the target under the plugin's feet.
. "$(dirname "$0")/lib.sh"

new_world

it "a renamed branch does not strand its checkpoint"
git checkout -q -b feature/x
printf 'work\n' >> file.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha 'git-sync/feature%2Fx')" ] || fail "no initial checkpoint"
git branch -q -m feature/y
out=$(run_stop)
assert_eq "" "$(sync_branch_sha 'git-sync/feature%2Fx')" "old name's checkpoint"
[ -n "$(sync_branch_sha 'git-sync/feature%2Fy')" ] || fail "no checkpoint under the new name"
assert_contains "$out" "no longer exist" "the user is told"

it "a deleted branch does not strand its checkpoint"
git checkout -q main
git branch -q -D feature/y
run_stop >/dev/null
assert_eq "" "$(sync_branch_sha 'git-sync/feature%2Fy')" "deleted branch's checkpoint"

it "nested branches coexist across machines (D/F conflict)"
# refs/heads/a/b est impossible tant que refs/heads/a existe. Un nom de branche
# encode en un seul segment sous git-sync/ rend le conflit inatteignable.
cleanup_world
new_world
clone_b
git checkout -q -b feat
printf 'on feat\n' >> file.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha 'git-sync/feat')" ] || fail "no checkpoint for feat"

cd "$B"
git checkout -q -b feat/sub
printf 'on feat/sub\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pushed" "feat/sub doit pouvoir se synchroniser"
[ -n "$(sync_branch_sha 'git-sync/feat%2Fsub')" ] || fail "feat/sub missing from the remote"
[ -n "$(sync_branch_sha 'git-sync/feat')" ] || fail "feat's checkpoint disappeared"

cleanup_world
exit $FAILURES
