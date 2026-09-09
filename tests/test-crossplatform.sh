#!/bin/sh
# The case the plugin actually exists for: the two machines are not the same OS.
# A checkpoint written by the shell hooks has to be readable by the PowerShell
# ones, and the other way round -- same trailers, same refspec, same lease file.

# This file drives both implementations itself; running it once per shell would
# just repeat the same work.
[ "${GS_SHELL:-sh}" = "sh" ] || exit 0
. "$(dirname "$0")/lib.sh"

if ! command -v pwsh >/dev/null 2>&1; then
  printf '  (pwsh not installed -- cases skipped)\n'; exit 0
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

  it "$FROM writes a checkpoint $TO can read"
  printf 'written by %s\n' "$FROM" >> file.txt
  printf 'added by %s\n' "$FROM" > added.txt
  stop_as "$FROM" >/dev/null
  [ -n "$(sync_branch_sha git-sync/main)" ] || fail "$FROM did not push"

  cd "$B"
  git pull -q --ff-only 2>/dev/null
  out=$(start_as "$TO")
  assert_contains "$(cat file.txt)" "written by $FROM" "restored content"
  [ -f added.txt ] || fail "the added file did not arrive"
  assert_contains "$out" "machineA" "Git-Sync-Machine trailer read by $TO"
  assert_contains "$out" "applied from git-sync/main" "message from $TO"

  it "$TO can then push its own checkpoint"
  printf 'replied by %s\n' "$TO" >> file.txt
  out=$(stop_as "$TO")
  assert_contains "$out" "checkpoint pushed" "$TO pushed"

  it "and $FROM gets it back"
  cd "$A"
  out=$(start_as "$FROM")
  assert_contains "$(cat file.txt)" "replied by $TO" "full round trip"

  cleanup_world
done

exit $FAILURES
