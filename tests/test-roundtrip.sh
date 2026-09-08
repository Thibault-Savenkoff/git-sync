#!/bin/sh
# The whole point of the plugin: work left on machine A shows up on machine B,
# as uncommitted work, with nothing lost and nothing committed along the way.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "A pousse un checkpoint (modif, ajout, suppression)"
printf 'ligne 2 depuis A\n' >> file.txt
printf 'nouveau depuis A\n' > added.txt
printf 'a supprimer\n' > doomed.txt
git add doomed.txt && git commit -qm "add doomed" && git push -q origin main
rm doomed.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha git-sync/main)" ] || fail "pas de checkpoint"

it "B recupere le travail de A dans son work tree"
cd "$B"
git pull -q --ff-only 2>/dev/null
out=$(run_start)
assert_contains "$(cat file.txt)" "ligne 2 depuis A" "file.txt modifie"
[ -f added.txt ] || fail "added.txt n'est pas arrive"
[ ! -f doomed.txt ] || fail "doomed.txt aurait du etre supprime"

it "B annonce l'arrivee et decrit ce qui a change"
assert_contains "$out" "applique depuis git-sync/main" "systemMessage"
assert_contains "$out" "machineA" "machine d'origine"
assert_contains "$out" "added.txt" "le diff --stat injecte"

it "sur B le travail est non committe, HEAD n'a pas bouge"
assert_eq "$(git rev-parse origin/main)" "$(git rev-parse HEAD)" "HEAD"
[ -n "$(git status --porcelain)" ] || fail "le travail devrait etre non committe"

it "B ne rejoue pas son propre checkpoint"
printf 'ligne 3 depuis B\n' >> file.txt
run_stop >/dev/null
before=$(cat file.txt)
run_start >/dev/null
assert_eq "$before" "$(cat file.txt)" "file.txt apres re-lecture"

it "A refuse d'ecraser le checkpoint de B (lease perime)"
cd "$A"
printf 'ligne 4 depuis A\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "autre machine a pousse" "message de refus"

it "et le checkpoint de B est intact sur le remote"
body=$(git fetch -q origin "refs/heads/git-sync/main:refs/probe/x" 2>/dev/null; git log -1 --format=%B refs/probe/x)
assert_contains "$body" "Git-Sync-Machine: machineB" "proprietaire du checkpoint"

cleanup_world

# Les deux refus se testent sur un monde neuf : les cas precedents laissent
# volontairement A et B en divergence, ce qui masquerait ce qu'on veut voir.
new_world
clone_b

it "B refuse d'appliquer par dessus des modifications qui ne sont pas les siennes"
# La distinction qui compte : du travail deja pousse par soi-meme peut etre
# ecrase sans rien perdre, du travail jamais pousse ne le peut pas.
printf 'travail de A\n' >> file.txt
run_stop >/dev/null
cd "$B"; git pull -q --ff-only 2>/dev/null
printf 'travail local jamais pousse\n' >> file.txt
out=$(run_start)
assert_contains "$out" "modifications locales" "refus"
assert_contains "$(cat file.txt)" "travail local jamais pousse" "le travail de B est intact"
assert_not_contains "$(cat file.txt)" "travail de A" "rien n'a ete applique"

it "B refuse quand les bases divergent"
git checkout -q -- .; git clean -qfd 2>/dev/null
git commit -q --allow-empty -m "commit local de B"
out=$(run_start)
assert_contains "$out" "part d'un autre commit" "refus"

cleanup_world
exit $FAILURES
