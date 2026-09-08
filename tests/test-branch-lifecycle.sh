#!/bin/sh
# Branches get renamed, deleted and nested. The checkpoint ref is derived from
# the branch name, so all three move the target under the plugin's feet.
. "$(dirname "$0")/lib.sh"

new_world

it "une branche renommee ne laisse pas son checkpoint orphelin"
git checkout -q -b feature/x
printf 'travail\n' >> file.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha 'git-sync/feature%2Fx')" ] || fail "pas de checkpoint initial"
git branch -q -m feature/y
out=$(run_stop)
assert_eq "" "$(sync_branch_sha 'git-sync/feature%2Fx')" "checkpoint de l'ancien nom"
[ -n "$(sync_branch_sha 'git-sync/feature%2Fy')" ] || fail "pas de checkpoint sous le nouveau nom"
assert_contains "$out" "branches disparues" "l'utilisateur est informe"

it "une branche supprimee ne laisse pas son checkpoint orphelin"
git checkout -q main
git branch -q -D feature/y
run_stop >/dev/null
assert_eq "" "$(sync_branch_sha 'git-sync/feature%2Fy')" "checkpoint de la branche supprimee"

it "deux branches imbriquees peuvent coexister entre machines (conflit D/F)"
# refs/heads/a/b est impossible tant que refs/heads/a existe. Un nom de branche
# encode en un seul segment sous git-sync/ rend le conflit inatteignable.
cleanup_world
new_world
clone_b
git checkout -q -b feat
printf 'sur feat\n' >> file.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha 'git-sync/feat')" ] || fail "pas de checkpoint pour feat"

cd "$B"
git checkout -q -b feat/sub
printf 'sur feat/sub\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pousse" "feat/sub doit pouvoir se synchroniser"
[ -n "$(sync_branch_sha 'git-sync/feat%2Fsub')" ] || fail "feat/sub absent du remote"
[ -n "$(sync_branch_sha 'git-sync/feat')" ] || fail "le checkpoint de feat a disparu"

cleanup_world
exit $FAILURES
