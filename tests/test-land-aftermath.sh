#!/bin/sh
# What happens to the machine that did NOT land.
#
# /git-sync:land deletes the checkpoint once its content is committed. The other
# machine still holds that work uncommitted and still believes the ref exists.
# It must recover on its own: a plugin that deadlocks after a normal, documented
# workflow is worse than one that never worked.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "A pousse, B recupere"
printf 'work from A\n' >> file.txt
run_stop >/dev/null
cd "$B"; git pull -q --ff-only 2>/dev/null; run_start >/dev/null
assert_contains "$(cat file.txt)" "work from A" "arrival on B"

it "B lands the work and deletes the checkpoint (what /git-sync:land does)"
git add -A && git commit -qm "feat: the real commit" && git push -q origin main
git push -q origin --delete git-sync/main
assert_eq "" "$(sync_branch_sha git-sync/main)" "checkpoint supprime"

it "A diagnoses it correctly: the work landed, not a machine conflict"
cd "$A"
out=$(run_stop)
assert_not_contains "$out" "another machine pushed" "faux diagnostic"

it "A is not deadlocked: it can push again"
git reset -q --hard origin/main 2>/dev/null || git fetch -q origin && git reset -q --hard origin/main
printf 'new work from A\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pushed" "A took the lead back"

cleanup_world
exit $FAILURES
