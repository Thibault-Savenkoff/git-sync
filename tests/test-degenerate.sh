#!/bin/sh
# Repositories that do not yet look like repositories. None of these should
# produce a stack trace, a raw git error, or -- worst of all -- a success
# message for something that did not happen.
. "$(dirname "$0")/lib.sh"

it "un depot sans aucun commit refuse proprement"
WORLD=$(mktemp -d); REMOTE="$WORLD/remote.git"; A="$WORLD/A"
git init -q --bare "$REMOTE"; git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git init -q -b main "$A"; cd "$A"
git config user.email a@test; git config user.name A; git config git-sync.machine machineA
git remote add origin "$REMOTE"
printf 'jamais committe\n' > file.txt
out=$(run_stop)
assert_contains "$out" "aucun commit" "message explicite"
assert_not_contains "$out" "checkpoint pousse" "faux succes"
assert_not_contains "$out" "fatal" "erreur git brute"
assert_not_contains "$out" "Exception" "trace PowerShell"
assert_eq "" "$(git ls-remote "$REMOTE" 'refs/heads/git-sync/*')" "rien n'a ete pousse"

it "et le demarrage de session n'y touche pas non plus"
out=$(run_start)
assert_not_contains "$out" "fatal" "erreur git brute"
assert_not_contains "$out" "Exception" "trace PowerShell"
assert_contains "$(cat file.txt)" "jamais committe" "fichier intact"
cleanup_world

it "un depot sans remote refuse proprement"
new_world
git remote remove origin
printf 'du travail\n' >> file.txt
out=$(run_stop)
assert_not_contains "$out" "checkpoint pousse" "faux succes"
assert_not_contains "$out" "fatal" "erreur git brute"
cleanup_world

it "deux sessions simultanees sur le meme depot ne s'alarment pas mutuellement"
new_world
printf 'du travail\n' >> file.txt
o1=$(run_stop); o2=$(run_stop)
# La seconde voit un remote deja porteur de son contenu exact : rien ne manque.
assert_not_contains "$o2" "echoue" "message alarmant pour rien"
assert_eq "$(awk '{print $2}' .git/git-sync-pushed)" \
          "$(sync_branch_sha git-sync/main)" "etat local coherent avec le remote"
printf 'la suite\n' >> file.txt
o3=$(run_stop)
assert_contains "$o3" "checkpoint pousse" "le push suivant fonctionne"
cleanup_world

exit $FAILURES
