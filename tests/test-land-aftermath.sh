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
printf 'du travail de A\n' >> file.txt
run_stop >/dev/null
cd "$B"; git pull -q --ff-only 2>/dev/null; run_start >/dev/null
assert_contains "$(cat file.txt)" "du travail de A" "arrivee sur B"

it "B fait atterrir le travail et supprime le checkpoint (ce que fait /git-sync:land)"
git add -A && git commit -qm "feat: le vrai commit" && git push -q origin main
git push -q origin --delete git-sync/main
assert_eq "" "$(sync_branch_sha git-sync/main)" "checkpoint supprime"

it "A diagnostique correctement : le travail a atterri, pas un conflit de machines"
cd "$A"
out=$(run_stop)
assert_not_contains "$out" "autre machine a pousse" "faux diagnostic"

it "A n'est pas bloque definitivement : il peut a nouveau pousser"
git reset -q --hard origin/main 2>/dev/null || git fetch -q origin && git reset -q --hard origin/main
printf 'nouveau travail de A\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pousse" "A a repris la main"

cleanup_world
exit $FAILURES
