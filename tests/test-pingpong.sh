#!/bin/sh
# The actual daily loop: laptop, desktop, laptop, desktop -- with nobody ever
# committing, resetting, or typing a git command in between. That is the whole
# promise of the plugin, and it is the one thing the round-trip test quietly
# stepped around by resetting the work tree first.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "A works and stops"
printf 'A: first pass\n' >> file.txt
run_stop >/dev/null

it "B picks it up, continues, and stops"
cd "$B"; git pull -q --ff-only 2>/dev/null
run_start >/dev/null
assert_contains "$(cat file.txt)" "A: first pass" "A's work received"
printf 'B: second pass\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pushed" "B a pousse"

it "A opens a session and receives B's addition, typing nothing"
cd "$A"
out=$(run_start)
assert_contains "$(cat file.txt)" "B: second pass" "B's addition received by A"
assert_contains "$(cat file.txt)" "A: first pass" "travail de A conserve"

it "A continues and hands back"
printf 'A: third pass\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "checkpoint pushed" "A a repousse"

it "B receives the next turn"
cd "$B"
out=$(run_start)
assert_contains "$(cat file.txt)" "A: third pass" "third pass received"

cleanup_world
exit $FAILURES
