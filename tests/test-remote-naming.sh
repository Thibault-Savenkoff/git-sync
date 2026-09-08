#!/bin/sh
# "origin" is a convention, not a guarantee. A repo cloned under another name,
# or one with a fork plus an upstream, used to leave the plugin inoperative --
# every push failing, with nothing but "push echoue" to go on.
. "$(dirname "$0")/lib.sh"

it "fonctionne avec un remote qui ne s'appelle pas origin"
new_world
git remote rename origin github
git branch -q --set-upstream-to=github/main main 2>/dev/null
printf 'du travail\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pousse" "push via 'github'"
[ -n "$(sync_branch_sha git-sync/main)" ] || fail "aucun checkpoint sur le remote"
cleanup_world

it "choisit l'upstream de la branche quand il y a plusieurs remotes"
new_world
git remote add upstream "$WORLD/remote.git"
git branch -q --set-upstream-to=origin/main main 2>/dev/null
printf 'du travail\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pousse" "push via l'upstream"
cleanup_world

it "refuse clairement quand aucun remote ne peut etre choisi"
new_world
git remote rename origin fork
git remote add autre "$WORLD/remote.git"
git branch -q --unset-upstream main 2>/dev/null
printf 'du travail\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "impossible de choisir un remote" "message explicite"
cleanup_world

exit $FAILURES
