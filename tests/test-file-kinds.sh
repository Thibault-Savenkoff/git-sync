#!/bin/sh
# A checkpoint is a git tree, so anything git records in a tree has to survive
# the round trip -- and anything it does not record is a silent loss.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "a symlink survives the checkpoint as a symlink"
ln -s file.txt lien.txt
printf 'content\n' >> file.txt
run_stop >/dev/null
cd "$B"; git pull -q --ff-only 2>/dev/null; run_start >/dev/null
[ -L lien.txt ] || fail "lien.txt is not a symlink on B"
assert_eq "file.txt" "$(readlink lien.txt)" "symlink target"

it "the executable bit is preserved"
cd "$A"
printf '#!/bin/sh\necho hi\n' > script.sh
chmod +x script.sh
run_stop >/dev/null
cd "$B"; run_start >/dev/null
[ -x script.sh ] || fail "script.sh is not executable on B"

it "a file B ignores locally still arrives when it comes from A"
# Le .gitignore fait partie du checkpoint, donc les deux machines finissent par
# partager les memes regles -- mais entre deux syncs elles peuvent differer.
cd "$B"; printf 'local.txt\n' > .gitignore
cd "$A"; printf 'data\n' > local.txt
run_stop >/dev/null
cd "$B"
out=$(run_start)
# B a un .gitignore local non pousse : le garde doit refuser, pas ecraser
assert_contains "$out" "local changes" "refusal expected"
assert_eq "local.txt" "$(cat .gitignore)" "B's .gitignore is intact"

it "and once B is clean, the file arrives despite the ignore rule"
rm -f .gitignore
out=$(run_start)
[ -f local.txt ] || fail "local.txt did not arrive"
assert_eq "data" "$(cat local.txt)" "content"

cleanup_world
exit $FAILURES
