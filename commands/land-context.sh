#!/bin/sh
# Context block for /git-sync:land.
#
# This lived as six inline `!` expansions in land.md, which quietly missed two
# fixes the hooks had already had: it hardcoded "origin", and it derived the
# checkpoint ref straight from the branch name without encoding it -- so on a
# branch like feat/sub it looked for git-sync/feat/sub while the hook had
# pushed git-sync/feat%2Fsub, and the command simply never found the
# checkpoint. Sharing lib.sh is what stops that happening a third time.
. "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh" 2>/dev/null || {
  echo "git-sync: library not found (CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-vide})"
  exit 0
}

if ! gs_enabled; then
  echo "git-sync: disabled on this repository, or not a git repository."
  exit 0
fi
if ! gs_has_commits; then
  echo "git-sync: this repository has no commits."
  exit 0
fi

BRANCH=$(gs_branch)
if [ -z "$BRANCH" ]; then
  echo "Current branch: (detached HEAD -- no checkpoint possible)"
  exit 0
fi
SYNC_BRANCH=$(gs_sync_branch)
REMOTE=$(gs_remote)
MACHINE=$(gs_machine)

echo "Current branch: $BRANCH"
echo "This machine: $MACHINE"
echo "Remote: ${REMOTE:-(cannot determine)}"
echo "Checkpoint ref: $SYNC_BRANCH"

if [ -z "$REMOTE" ]; then
  echo "Checkpoint: (no usable remote)"
  exit 0
fi

git fetch -q "$REMOTE" "+refs/heads/$SYNC_BRANCH:refs/git-sync/current" 2>/dev/null || true
CKPT=$(git rev-parse -q --verify refs/git-sync/current 2>/dev/null || true)
if [ -z "$CKPT" ]; then
  echo "Checkpoint: (none)"
  exit 0
fi

echo "Checkpoint: $CKPT"
echo "Origin: $(gs_trailer "$CKPT" Git-Sync-Machine)"
echo "Checkpoint base: $(gs_trailer "$CKPT" Git-Sync-Base)"
echo "Local HEAD: $(git rev-parse HEAD)"
echo "Summary:"
git diff --stat HEAD "$CKPT" 2>/dev/null | tail -30
