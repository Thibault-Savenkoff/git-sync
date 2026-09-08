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

it "A pousse un checkpoint, puis committe a la main sans passer par land"
printf 'du travail\n' >> file.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha git-sync/main)" ] || fail "pas de checkpoint"
git add -A && git commit -qm "feat: committe a la main" && git push -q origin main

it "A nettoie son propre checkpoint devenu inutile"
out=$(run_stop)
assert_eq "" "$(sync_branch_sha git-sync/main)" "checkpoint obsolete supprime"

it "B n'est pas harcele par un checkpoint perime"
cd "$B"; git pull -q --ff-only 2>/dev/null
out=$(run_start)
assert_not_contains "$out" "part d'un autre commit" "avertissement inutile"

it "mais ne touche pas a un checkpoint frais de l'autre machine"
cd "$B"; git pull -q --ff-only 2>/dev/null
printf 'travail de B\n' >> file.txt
run_stop >/dev/null
ckpt_b=$(sync_branch_sha git-sync/main)
[ -n "$ckpt_b" ] || fail "B n'a pas pousse"
cd "$A"; git pull -q --ff-only 2>/dev/null
run_stop >/dev/null
assert_eq "$ckpt_b" "$(sync_branch_sha git-sync/main)" "le checkpoint de B a survecu"

cleanup_world
exit $FAILURES
