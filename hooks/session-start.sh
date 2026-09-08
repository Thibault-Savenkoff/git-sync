#!/bin/sh
# Bring the other machine's work into this one at session start.
#
# In checkpoint mode a plain `git pull` is not enough: the work lives on a
# throwaway branch and must land in the work tree *without* becoming a commit,
# so it stays exactly what it was -- work in progress you happen to be
# continuing somewhere else.
#
# Every one of the guards below refuses rather than guesses. Silently
# overwriting a work tree is the one failure mode that loses work outright.
set -e

. "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"

gs_enabled || exit 0
gs_has_remote || exit 0

if [ "$(gs_mode)" != "checkpoint" ]; then
  git pull --ff-only >/dev/null 2>&1 || true
  exit 0
fi

BRANCH=$(gs_branch || true)
[ -n "$BRANCH" ] || exit 0
SYNC_BRANCH="git-sync/$BRANCH"

git pull --ff-only >/dev/null 2>&1 || true

# The leading "+" is not optional: a checkpoint is force-pushed, so its update
# is never a fast-forward. Without it the fetch is rejected and this machine
# quietly stops seeing anything after the very first checkpoint.
git fetch -q origin "+refs/heads/$SYNC_BRANCH:refs/git-sync/$SYNC_BRANCH" 2>/dev/null || exit 0
CKPT=$(git rev-parse -q --verify "refs/git-sync/$SYNC_BRANCH" 2>/dev/null) || CKPT=""
if [ -z "$CKPT" ]; then
  # Nothing on the remote. If we still hold a lease for it, the checkpoint was
  # landed and deleted elsewhere -- forget it now rather than deadlock at the
  # next push.
  if [ -n "$(gs_known_push "$SYNC_BRANCH")" ]; then
    gs_forget_push "$SYNC_BRANCH"
  fi
  exit 0
fi

BASE=$(gs_trailer "$CKPT" Git-Sync-Base)
MACHINE=$(gs_trailer "$CKPT" Git-Sync-Machine)
HEAD_SHA=$(git rev-parse HEAD)

# Our own checkpoint: nothing to bring in, and re-applying it would undo
# whatever we have done locally since.
if [ "$MACHINE" = "$(gs_machine)" ]; then exit 0; fi

# Already applied, or the branch moved on past it.
if [ "$(git rev-parse "$CKPT^{tree}")" = "$(gs_head_tree)" ]; then exit 0; fi

if [ "$BASE" != "$HEAD_SHA" ]; then
  gs_json SessionStart \
    "git-sync: un checkpoint de $MACHINE existe sur $SYNC_BRANCH mais part d'un autre commit ($BASE vs $HEAD_SHA). Rien n'a ete applique -- inspecte-le avec: git diff HEAD refs/git-sync/$SYNC_BRANCH" ""
  exit 0
fi

# A dirty work tree normally means "refuse" -- but there is one case where the
# dirt is not unique work at all: it is exactly what we ourselves last pushed,
# and the incoming checkpoint was built on top of it. That is the ordinary
# laptop/desktop ping-pong, and refusing there strands both machines.
RESET=""
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  MINE=$(gs_known_mine "$SYNC_BRANCH")
  if [ -n "$MINE" ] && [ "$MINE" = "$(gs_worktree_tree)" ]; then
    RESET="--reset"
  else
    gs_json SessionStart \
      "git-sync: un checkpoint de $MACHINE attend sur $SYNC_BRANCH, mais ce work tree a des modifications locales qui ne sont pas dans le dernier checkpoint que tu as pousse. Rien n'a ete applique. Compare avec: git diff HEAD refs/git-sync/$SYNC_BRANCH" ""
    exit 0
  fi
fi

# `git checkout <ckpt> -- .` would be the reflex and would be wrong: it does not
# remove files the other machine deleted. A two-way read-tree does, then the
# reset puts the index back on HEAD so the result reads as uncommitted work.
# Computed before applying: once the checkpoint is in and the index is reset,
# files it added read as untracked and `git diff HEAD` stops mentioning them.
STAT=$(git diff --stat HEAD "$CKPT" | tail -20)

# Two distinct applications, because -m and --reset are mutually exclusive:
#   clean tree  -> two-way merge against HEAD, which refuses on any conflict
#   our own dirt -> single-tree reset, discarding changes we have proven are
#                   already on the remote in a checkpoint we pushed ourselves
if [ -n "$RESET" ]; then
  APPLY_OK=$(git read-tree -u --reset "$CKPT" 2>/dev/null && echo yes)
else
  APPLY_OK=$(git read-tree -u -m HEAD "$CKPT" 2>/dev/null && echo yes)
fi
if [ "$APPLY_OK" != "yes" ]; then
  gs_json SessionStart \
    "git-sync: application du checkpoint de $MACHINE impossible (conflit avec des fichiers locaux). Rien n'a change." ""
  exit 0
fi
git reset -q
# We have taken the incoming work in, so overwriting this checkpoint next time
# is legitimate. Until that happens the lease stays stale on purpose -- that is
# what stops a machine that refused the checkpoint from clobbering it.
gs_remember_push "$SYNC_BRANCH" "$CKPT"
gs_remember_mine "$SYNC_BRANCH" "$(git rev-parse "$CKPT^{tree}")"

gs_json SessionStart \
  "git-sync: travail de $MACHINE applique depuis $SYNC_BRANCH (non committe)." \
  "git-sync a restaure le travail en cours de la machine $MACHINE. Ces modifications sont dans le work tree, non committees, et ne sont pas de toi :

$STAT

Le pourquoi de ces changements est dans la section '## Etat courant' de CLAUDE.md si elle existe. Ne recommence pas ce travail : continue-le."
exit 0
