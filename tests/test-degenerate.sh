#!/bin/sh
# Repositories that do not yet look like repositories. None of these should
# produce a stack trace, a raw git error, or -- worst of all -- a success
# message for something that did not happen.
. "$(dirname "$0")/lib.sh"

it "a repository with no commits refuses cleanly"
WORLD=$(mktemp -d); REMOTE="$WORLD/remote.git"; A="$WORLD/A"
git init -q --bare "$REMOTE"; git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git init -q -b main "$A"; cd "$A"
git config user.email a@test; git config user.name A; git config git-sync.machine machineA
git remote add origin "$REMOTE"
printf 'never committed\n' > file.txt
out=$(run_stop)
assert_contains "$out" "no commits yet" "explicit message"
assert_not_contains "$out" "checkpoint pushed" "false success"
assert_not_contains "$out" "fatal" "raw git error"
assert_not_contains "$out" "Exception" "PowerShell stack trace"
assert_eq "" "$(git ls-remote "$REMOTE" 'refs/heads/git-sync/*')" "nothing was pushed"

it "and session start leaves it alone too"
out=$(run_start)
assert_not_contains "$out" "fatal" "raw git error"
assert_not_contains "$out" "Exception" "PowerShell stack trace"
assert_contains "$(cat file.txt)" "never committed" "file intact"
cleanup_world

it "a repository with no remote refuses cleanly"
new_world
git remote remove origin
printf 'some work\n' >> file.txt
out=$(run_stop)
assert_not_contains "$out" "checkpoint pushed" "false success"
assert_not_contains "$out" "fatal" "raw git error"
cleanup_world

it "two concurrent sessions in one repository do not alarm each other"
new_world
printf 'some work\n' >> file.txt
o1=$(run_stop); o2=$(run_stop)
# La seconde voit un remote deja porteur de son contenu exact : rien ne manque.
assert_not_contains "$o2" "failed" "needlessly alarming message"
assert_eq "$(awk '{print $2}' .git/git-sync-pushed)" \
          "$(sync_branch_sha git-sync/main)" "local state consistent with the remote"
printf 'more\n' >> file.txt
o3=$(run_stop)
assert_contains "$o3" "checkpoint pushed" "the next push works"
cleanup_world

exit $FAILURES
