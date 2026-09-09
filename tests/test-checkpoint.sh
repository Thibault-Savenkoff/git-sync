#!/bin/sh
# Checkpoint mode: what it pushes, and what it must never touch locally.
. "$(dirname "$0")/lib.sh"

new_world

it "does nothing when the work tree is clean"
out=$(run_stop)
assert_eq "" "$(sync_branch_sha git-sync/main)" "no checkpoint"

it "pushes a checkpoint when the work tree is dirty"
printf 'ligne 2\n' >> file.txt
printf 'new\n' > added.txt
HEAD_BEFORE=$(git rev-parse HEAD)
out=$(run_stop)
CKPT=$(sync_branch_sha git-sync/main)
[ -n "$CKPT" ] || fail "no checkpoint pushed -- output: $out"
assert_contains "$out" "checkpoint pushed" "message"

it "does not move HEAD"
assert_eq "$HEAD_BEFORE" "$(git rev-parse HEAD)" "HEAD"

it "creates no commit on the current branch"
assert_eq "1" "$(git rev-list --count HEAD)" "commit count"

it "leaves the work tree dirty"
[ -n "$(git status --porcelain)" ] || fail "the work tree was cleaned"

it "does not disturb the user's index"
git diff --cached --quiet || fail "files were left staged"

it "the checkpoint carries the uncommitted files"
content=$(git show "$CKPT:file.txt" 2>/dev/null)
assert_contains "$content" "ligne 2" "checkpoint's file.txt"
git show "$CKPT:added.txt" >/dev/null 2>&1 || fail "added.txt missing from the checkpoint"

it "the checkpoint carries the expected trailers"
body=$(git log -1 --format=%B "$CKPT")
assert_contains "$body" "Git-Sync-Base: $HEAD_BEFORE" "Base trailer"
assert_contains "$body" "Git-Sync-Machine: machineA" "Machine trailer"
assert_contains "$body" "[skip ci]" "skip ci by default"

it "checkpointCi=true drops [skip ci]"
git config git-sync.checkpointCi true
printf 'ligne 3\n' >> file.txt
run_stop >/dev/null
body=$(git log -1 --format=%B "$(sync_branch_sha git-sync/main)")
assert_not_contains "$body" "[skip ci]" "message"
git config --unset git-sync.checkpointCi

it "preserves what the user had staged"
printf 'stage me\n' > staged.txt
git add staged.txt
run_stop >/dev/null
assert_contains "$(git diff --cached --name-only)" "staged.txt" "staging after the hook"

it "honours git-sync.disabled"
git config git-sync.disabled true
before=$(sync_branch_sha git-sync/main)
printf 'ignore me\n' >> file.txt
run_stop >/dev/null
assert_eq "$before" "$(sync_branch_sha git-sync/main)" "checkpoint unchanged"
git config --unset git-sync.disabled

it "honours GIT_SYNC_DISABLED"
before=$(sync_branch_sha git-sync/main)
GIT_SYNC_DISABLED=1 run_stop >/dev/null
assert_eq "$before" "$(sync_branch_sha git-sync/main)" "checkpoint unchanged"

it "refuses politely on a detached HEAD"
git stash -q -u 2>/dev/null || true
git checkout -q --detach HEAD
printf 'detached\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "detached HEAD" "message"
git checkout -q main && git checkout -q -- . 2>/dev/null || true

cleanup_world
exit $FAILURES
