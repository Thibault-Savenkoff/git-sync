#!/bin/sh
# The bundled patterns keep junk and credentials out of the checkpoint -- and,
# unlike 1.x, do it without editing the user's repository.
. "$(dirname "$0")/lib.sh"

new_world

it "does not write into the repository's own .gitignore"
printf 'some work\n' >> file.txt
run_stop >/dev/null
[ ! -f .gitignore ] || fail ".gitignore was created in the user's repository"

it "keeps secrets and noise out of the checkpoint"
printf 'SECRET=1\n' > .env
printf 'cle privee\n' > deploy.pem
printf 'jeton\n' > aws-credentials
mkdir -p node_modules && printf 'x\n' > node_modules/junk.js
printf 'vrai code\n' >> file.txt
run_stop >/dev/null
CKPT=$(sync_branch_sha git-sync/main)
files=$(git ls-tree -r --name-only "$CKPT")
assert_contains "$files" "file.txt" "the real file is there"
for bad in .env deploy.pem aws-credentials node_modules/junk.js; do
  case "$files" in *"$bad"*) fail "$bad went into the checkpoint" ;; esac
done

it "does not exclude a file the repository already tracks"
git add -f .env && git commit -qm "l'utilisateur a choisi de suivre .env"
printf 'SECRET=2\n' > .env
run_stop >/dev/null
CKPT=$(sync_branch_sha git-sync/main)
assert_contains "$(git show "$CKPT:.env")" "SECRET=2" "tracked .env"

cleanup_world
exit $FAILURES
