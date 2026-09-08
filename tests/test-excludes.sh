#!/bin/sh
# The bundled patterns keep junk and credentials out of the checkpoint -- and,
# unlike 1.x, do it without editing the user's repository.
. "$(dirname "$0")/lib.sh"

new_world

it "n'ecrit pas dans le .gitignore du depot"
printf 'du travail\n' >> file.txt
run_stop >/dev/null
[ ! -f .gitignore ] || fail ".gitignore a ete cree dans le depot de l'utilisateur"

it "exclut les secrets et le bruit du checkpoint"
printf 'SECRET=1\n' > .env
printf 'cle privee\n' > deploy.pem
printf 'jeton\n' > aws-credentials
mkdir -p node_modules && printf 'x\n' > node_modules/junk.js
printf 'vrai code\n' >> file.txt
run_stop >/dev/null
CKPT=$(sync_branch_sha git-sync/main)
files=$(git ls-tree -r --name-only "$CKPT")
assert_contains "$files" "file.txt" "le vrai fichier est bien la"
for bad in .env deploy.pem aws-credentials node_modules/junk.js; do
  case "$files" in *"$bad"*) fail "$bad est parti dans le checkpoint" ;; esac
done

it "n'exclut pas un fichier deja suivi par le depot"
git add -f .env && git commit -qm "l'utilisateur a choisi de suivre .env"
printf 'SECRET=2\n' > .env
run_stop >/dev/null
CKPT=$(sync_branch_sha git-sync/main)
assert_contains "$(git show "$CKPT:.env")" "SECRET=2" ".env suivi"

cleanup_world
exit $FAILURES
