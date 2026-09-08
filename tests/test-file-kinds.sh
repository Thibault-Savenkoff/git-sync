#!/bin/sh
# A checkpoint is a git tree, so anything git records in a tree has to survive
# the round trip -- and anything it does not record is a silent loss.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "un lien symbolique traverse le checkpoint en restant un lien"
ln -s file.txt lien.txt
printf 'contenu\n' >> file.txt
run_stop >/dev/null
cd "$B"; git pull -q --ff-only 2>/dev/null; run_start >/dev/null
[ -L lien.txt ] || fail "lien.txt n'est pas un lien symbolique sur B"
assert_eq "file.txt" "$(readlink lien.txt)" "cible du lien"

it "le bit executable est conserve"
cd "$A"
printf '#!/bin/sh\necho hi\n' > script.sh
chmod +x script.sh
run_stop >/dev/null
cd "$B"; run_start >/dev/null
[ -x script.sh ] || fail "script.sh n'est pas executable sur B"

it "un fichier ignore localement par B arrive quand meme s'il vient de A"
# Le .gitignore fait partie du checkpoint, donc les deux machines finissent par
# partager les memes regles -- mais entre deux syncs elles peuvent differer.
cd "$B"; printf 'local.txt\n' > .gitignore
cd "$A"; printf 'donnee\n' > local.txt
run_stop >/dev/null
cd "$B"
out=$(run_start)
# B a un .gitignore local non pousse : le garde doit refuser, pas ecraser
assert_contains "$out" "modifications locales" "refus attendu"
assert_eq "local.txt" "$(cat .gitignore)" "le .gitignore de B est intact"

it "et une fois B propre, le fichier arrive malgre la regle d'ignore"
rm -f .gitignore
out=$(run_start)
[ -f local.txt ] || fail "local.txt n'est pas arrive"
assert_eq "donnee" "$(cat local.txt)" "contenu"

cleanup_world
exit $FAILURES
