#!/bin/sh
# The context block /git-sync:land is driven by. Its six inline expansions had
# drifted away from the hooks -- hardcoded remote, unencoded branch name -- so
# the command could not find a checkpoint the hook had just pushed.
. "$(dirname "$0")/lib.sh"

# Ce fichier teste un script shell, pas les hooks : une seule passe suffit.
[ "${GS_SHELL:-sh}" = "sh" ] || exit 0

ctx() { sh "$PLUGIN_ROOT/commands/land-context.sh" 2>&1; }

new_world

it "annonce l'absence de checkpoint quand il n'y en a pas"
out=$(ctx)
assert_contains "$out" "Checkpoint : (aucun)" "aucun checkpoint"

it "trouve le checkpoint et lit ses trailers"
printf 'du travail\n' >> file.txt
run_stop >/dev/null
out=$(ctx)
assert_contains "$out" "$(sync_branch_sha git-sync/main)" "sha du checkpoint"
assert_contains "$out" "Origine : machineA" "machine d'origine"
assert_contains "$out" "Cette machine : machineA" "machine courante"
assert_contains "$out" "Base du checkpoint : $(git rev-parse HEAD)" "base"
assert_contains "$out" "file.txt" "resume du diff"

it "fonctionne avec un remote qui ne s'appelle pas origin"
git remote rename origin github
git branch -q --set-upstream-to=github/main main 2>/dev/null
out=$(ctx)
assert_contains "$out" "Remote : github" "remote detecte"
assert_contains "$out" "Origine : machineA" "checkpoint toujours trouve"
cleanup_world

it "trouve le checkpoint d'une branche imbriquee (nom encode)"
new_world
git checkout -q -b feat/sub
printf 'du travail\n' >> file.txt
run_stop >/dev/null
out=$(ctx)
assert_contains "$out" "Ref du checkpoint : git-sync/feat%2Fsub" "ref encode"
assert_contains "$out" "Origine : machineA" "checkpoint trouve"
cleanup_world

it "refuse proprement sur un HEAD detache"
new_world
git checkout -q --detach HEAD
out=$(ctx)
assert_contains "$out" "HEAD detache" "message"
cleanup_world

it "refuse proprement quand git-sync est desactive"
new_world
git config git-sync.disabled true
out=$(ctx)
assert_contains "$out" "desactive" "message"
cleanup_world

exit $FAILURES
