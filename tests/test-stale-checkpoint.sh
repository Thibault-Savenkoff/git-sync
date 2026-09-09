#!/bin/sh
# A checkpoint that nobody landed, and that reality moved past.
#
# The likeliest way this happens is not exotic: you push a checkpoint on the
# laptop, then next day on that same laptop you just commit and push yourself,
# the way you always have, never touching /git-sync:land. The checkpoint stays
# behind with a base nobody is on any more -- and it is the *other* machine
# that gets nagged about it, at every single session start, forever.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "A pushes a checkpoint, then commits by hand without landing"
printf 'some work\n' >> file.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha git-sync/main)" ] || fail "no checkpoint"
git add -A && git commit -qm "feat: committed by hand" && git push -q origin main

it "A retires its own now-meaningless checkpoint"
out=$(run_stop)
assert_eq "" "$(sync_branch_sha git-sync/main)" "stale checkpoint deleted"

it "B is not nagged by a stale checkpoint"
cd "$B"; git pull -q --ff-only 2>/dev/null
out=$(run_start)
assert_not_contains "$out" "based on a different commit" "needless warning"

it "but leaves a fresh checkpoint from the other machine alone"
cd "$B"; git pull -q --ff-only 2>/dev/null
printf 'travail de B\n' >> file.txt
run_stop >/dev/null
ckpt_b=$(sync_branch_sha git-sync/main)
[ -n "$ckpt_b" ] || fail "B did not push"
cd "$A"; git pull -q --ff-only 2>/dev/null
run_stop >/dev/null
assert_eq "$ckpt_b" "$(sync_branch_sha git-sync/main)" "B's checkpoint survived"

cleanup_world
exit $FAILURES
