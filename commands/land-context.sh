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
  echo "git-sync: bibliotheque introuvable (CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-vide})"
  exit 0
}

if ! gs_enabled; then
  echo "git-sync: desactive sur ce depot, ou pas un depot git."
  exit 0
fi
if ! gs_has_commits; then
  echo "git-sync: ce depot n'a aucun commit."
  exit 0
fi

BRANCH=$(gs_branch)
if [ -z "$BRANCH" ]; then
  echo "Branche courante : (HEAD detache -- pas de checkpoint possible)"
  exit 0
fi
SYNC_BRANCH=$(gs_sync_branch)
REMOTE=$(gs_remote)
MACHINE=$(gs_machine)

echo "Branche courante : $BRANCH"
echo "Cette machine : $MACHINE"
echo "Remote : ${REMOTE:-(indeterminable)}"
echo "Ref du checkpoint : $SYNC_BRANCH"

if [ -z "$REMOTE" ]; then
  echo "Checkpoint : (aucun remote utilisable)"
  exit 0
fi

git fetch -q "$REMOTE" "+refs/heads/$SYNC_BRANCH:refs/git-sync/current" 2>/dev/null || true
CKPT=$(git rev-parse -q --verify refs/git-sync/current 2>/dev/null || true)
if [ -z "$CKPT" ]; then
  echo "Checkpoint : (aucun)"
  exit 0
fi

echo "Checkpoint : $CKPT"
echo "Origine : $(gs_trailer "$CKPT" Git-Sync-Machine)"
echo "Base du checkpoint : $(gs_trailer "$CKPT" Git-Sync-Base)"
echo "HEAD local : $(git rev-parse HEAD)"
echo "Resume :"
git diff --stat HEAD "$CKPT" 2>/dev/null | tail -30
