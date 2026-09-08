#!/bin/sh
# The case the plugin actually exists for: the two machines are not the same OS.
# A checkpoint written by the shell hooks has to be readable by the PowerShell
# ones, and the other way round -- same trailers, same refspec, same lease file.

# This file drives both implementations itself; running it once per shell would
# just repeat the same work.
[ "${GS_SHELL:-sh}" = "sh" ] || exit 0
. "$(dirname "$0")/lib.sh"

if ! command -v pwsh >/dev/null 2>&1; then
  printf '  (pwsh absent -- cas ignores)\n'; exit 0
fi

# stop_as / start_as <shell> -- run one hook under a named implementation.
stop_as()  { GS_SHELL="$1" run_stop; }
start_as() { GS_SHELL="$1" run_start; }

for pair in "sh pwsh" "pwsh sh"; do
  set -- $pair
  FROM=$1; TO=$2
  printf '  [%s -> %s]\n' "$FROM" "$TO"

  new_world
  clone_b

  it "$FROM ecrit un checkpoint que $TO sait lire"
  printf 'ecrit par %s\n' "$FROM" >> file.txt
  printf 'ajoute par %s\n' "$FROM" > added.txt
  stop_as "$FROM" >/dev/null
  [ -n "$(sync_branch_sha git-sync/main)" ] || fail "$FROM n'a pas pousse"

  cd "$B"
  git pull -q --ff-only 2>/dev/null
  out=$(start_as "$TO")
  assert_contains "$(cat file.txt)" "ecrit par $FROM" "contenu restaure"
  [ -f added.txt ] || fail "le fichier ajoute n'est pas arrive"
  assert_contains "$out" "machineA" "trailer Git-Sync-Machine lu par $TO"
  assert_contains "$out" "applique depuis git-sync/main" "message de $TO"

  it "$TO peut ensuite pousser son propre checkpoint"
  printf 'repondu par %s\n' "$TO" >> file.txt
  out=$(stop_as "$TO")
  assert_contains "$out" "checkpoint pousse" "$TO a pousse"

  it "et $FROM le recupere en retour"
  cd "$A"
  out=$(start_as "$FROM")
  assert_contains "$(cat file.txt)" "repondu par $TO" "aller-retour complet"

  cleanup_world
done

exit $FAILURES
