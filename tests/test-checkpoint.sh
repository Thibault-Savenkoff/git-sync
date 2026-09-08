#!/bin/sh
# Checkpoint mode: what it pushes, and what it must never touch locally.
. "$(dirname "$0")/lib.sh"

new_world

it "ne fait rien quand le work tree est propre"
out=$(run_stop)
assert_eq "" "$(sync_branch_sha git-sync/main)" "aucun checkpoint"

it "pousse un checkpoint quand le work tree est sale"
printf 'ligne 2\n' >> file.txt
printf 'nouveau\n' > added.txt
HEAD_BEFORE=$(git rev-parse HEAD)
out=$(run_stop)
CKPT=$(sync_branch_sha git-sync/main)
[ -n "$CKPT" ] || fail "aucun checkpoint pousse -- sortie: $out"
assert_contains "$out" "checkpoint pousse" "message"

it "ne deplace pas HEAD"
assert_eq "$HEAD_BEFORE" "$(git rev-parse HEAD)" "HEAD"

it "ne cree aucun commit sur la branche courante"
assert_eq "1" "$(git rev-list --count HEAD)" "nombre de commits"

it "laisse le work tree sale"
[ -n "$(git status --porcelain)" ] || fail "le work tree a ete nettoye"

it "ne touche pas a l'index de l'utilisateur"
git diff --cached --quiet || fail "des fichiers ont ete laisses en staging"

it "le checkpoint contient bien les fichiers non committes"
content=$(git show "$CKPT:file.txt" 2>/dev/null)
assert_contains "$content" "ligne 2" "file.txt du checkpoint"
git show "$CKPT:added.txt" >/dev/null 2>&1 || fail "added.txt absent du checkpoint"

it "le checkpoint porte les trailers attendus"
body=$(git log -1 --format=%B "$CKPT")
assert_contains "$body" "Git-Sync-Base: $HEAD_BEFORE" "trailer Base"
assert_contains "$body" "Git-Sync-Machine: machineA" "trailer Machine"
assert_contains "$body" "[skip ci]" "skip ci par defaut"

it "checkpointCi=true retire [skip ci]"
git config git-sync.checkpointCi true
printf 'ligne 3\n' >> file.txt
run_stop >/dev/null
body=$(git log -1 --format=%B "$(sync_branch_sha git-sync/main)")
assert_not_contains "$body" "[skip ci]" "message"
git config --unset git-sync.checkpointCi

it "preserve les modifications deja en staging par l'utilisateur"
printf 'stage moi\n' > staged.txt
git add staged.txt
run_stop >/dev/null
assert_contains "$(git diff --cached --name-only)" "staged.txt" "staging apres le hook"

it "respecte git-sync.disabled"
git config git-sync.disabled true
before=$(sync_branch_sha git-sync/main)
printf 'ignore moi\n' >> file.txt
run_stop >/dev/null
assert_eq "$before" "$(sync_branch_sha git-sync/main)" "checkpoint inchange"
git config --unset git-sync.disabled

it "respecte GIT_SYNC_DISABLED"
before=$(sync_branch_sha git-sync/main)
GIT_SYNC_DISABLED=1 run_stop >/dev/null
assert_eq "$before" "$(sync_branch_sha git-sync/main)" "checkpoint inchange"

it "refuse poliment sur un HEAD detache"
git stash -q -u 2>/dev/null || true
git checkout -q --detach HEAD
printf 'detache\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "HEAD detache" "message"
git checkout -q main && git checkout -q -- . 2>/dev/null || true

cleanup_world
exit $FAILURES
