#!/bin/sh
# The context block /git-sync:land is driven by. Its six inline expansions had
# drifted away from the hooks -- hardcoded remote, unencoded branch name -- so
# the command could not find a checkpoint the hook had just pushed.
. "$(dirname "$0")/lib.sh"

# Ce fichier teste un script shell, pas les hooks : une seule passe suffit.
[ "${GS_SHELL:-sh}" = "sh" ] || exit 0

ctx() { sh "$PLUGIN_ROOT/commands/land-context.sh" 2>&1; }

new_world

it "reports no checkpoint when there is none"
out=$(ctx)
assert_contains "$out" "Checkpoint: (none)" "no checkpoint"

it "finds the checkpoint and reads its trailers"
printf 'some work\n' >> file.txt
run_stop >/dev/null
out=$(ctx)
assert_contains "$out" "$(sync_branch_sha git-sync/main)" "checkpoint sha"
assert_contains "$out" "Origin: machineA" "origin machine"
assert_contains "$out" "This machine: machineA" "current machine"
assert_contains "$out" "Checkpoint base: $(git rev-parse HEAD)" "base"
assert_contains "$out" "file.txt" "diff summary"

it "works with a remote not named origin"
git remote rename origin github
git branch -q --set-upstream-to=github/main main 2>/dev/null
out=$(ctx)
assert_contains "$out" "Remote: github" "remote detected"
assert_contains "$out" "Origin: machineA" "checkpoint still found"
cleanup_world

it "finds a nested branch's checkpoint (encoded name)"
new_world
git checkout -q -b feat/sub
printf 'some work\n' >> file.txt
run_stop >/dev/null
out=$(ctx)
assert_contains "$out" "Checkpoint ref: git-sync/feat%2Fsub" "encoded ref"
assert_contains "$out" "Origin: machineA" "checkpoint found"
cleanup_world

it "refuses cleanly on a detached HEAD"
new_world
git checkout -q --detach HEAD
out=$(ctx)
assert_contains "$out" "detached HEAD" "message"
cleanup_world

it "refuses cleanly when git-sync is disabled"
new_world
git config git-sync.disabled true
out=$(ctx)
assert_contains "$out" "disabled" "message"
cleanup_world

exit $FAILURES
