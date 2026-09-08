#!/bin/sh
# The actual daily loop: laptop, desktop, laptop, desktop -- with nobody ever
# committing, resetting, or typing a git command in between. That is the whole
# promise of the plugin, and it is the one thing the round-trip test quietly
# stepped around by resetting the work tree first.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "A travaille et s'arrete"
printf 'A: premiere passe\n' >> file.txt
run_stop >/dev/null

it "B recupere, continue, et s'arrete"
cd "$B"; git pull -q --ff-only 2>/dev/null
run_start >/dev/null
assert_contains "$(cat file.txt)" "A: premiere passe" "travail de A recu"
printf 'B: deuxieme passe\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pousse" "B a pousse"

it "A rouvre une session et recoit l'ajout de B, sans rien taper"
cd "$A"
out=$(run_start)
assert_contains "$(cat file.txt)" "B: deuxieme passe" "ajout de B recu par A"
assert_contains "$(cat file.txt)" "A: premiere passe" "travail de A conserve"

it "A continue et repasse la main"
printf 'A: troisieme passe\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pousse" "A a repousse"

it "B recoit le tour suivant"
cd "$B"
out=$(run_start)
assert_contains "$(cat file.txt)" "A: troisieme passe" "troisieme passe recue"

cleanup_world
exit $FAILURES
