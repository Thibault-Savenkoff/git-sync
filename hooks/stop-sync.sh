#!/bin/sh
# Push the work tree to a checkpoint branch on session stop.
#
# Checkpoint mode (the default) never runs `git commit`: it builds the commit
# object with plumbing, against a throwaway index, and pushes that. The local
# repository is left byte-for-byte as the user left it -- HEAD where it was,
# their staged changes still staged, the work tree still dirty. Only the remote
# learns anything, on a branch that exists solely to be overwritten.
#
# That is the whole point of 2.0: the sync stops borrowing the project's
# history as a transport and stops leaving "WIP: auto-sync" behind in it.
set -e

. "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"

gs_enabled || exit 0

REPO_ROOT=$(gs_repo_root)
MSG=""
CONTEXT=""

if [ "$(gs_mode)" = "checkpoint" ]; then
  SYNC_BRANCH=$(gs_sync_branch || true)
  if [ -z "$SYNC_BRANCH" ]; then
    gs_json Stop "git-sync: HEAD detache, pas de checkpoint (aucune branche a suivre)." ""
    exit 0
  fi
  if ! gs_has_remote; then
    gs_json Stop "git-sync: aucun remote configure, checkpoint impossible." ""
    exit 0
  fi

  # Snapshot the work tree through an index of our own, so the user's staged
  # changes are neither read nor disturbed.
  TMP_INDEX=$(mktemp)
  trap 'rm -f "$TMP_INDEX"' EXIT
  GIT_INDEX_FILE="$TMP_INDEX"; export GIT_INDEX_FILE
  git read-tree HEAD
  # 1.x appended these patterns to the repo's own .gitignore and committed it --
  # editing the user's project to protect our own push. Here they are applied as
  # an extra exclude file for this snapshot only, which protects the same things
  # and changes nothing in the repo. Already-tracked files are unaffected: if a
  # key is committed, that was a deliberate act and not ours to override.
  EXCLUDES="${CLAUDE_PLUGIN_ROOT}/hooks/ignore-patterns.txt"
  if [ -f "$EXCLUDES" ]; then
    git -c core.excludesFile="$EXCLUDES" add -A
  else
    git add -A
  fi
  TREE=$(git write-tree)
  unset GIT_INDEX_FILE

  HEAD_SHA=$(git rev-parse HEAD)
  if [ "$TREE" = "$(git rev-parse "HEAD^{tree}")" ]; then
    # Nothing differs from the last real commit; a checkpoint would say nothing.
    MSG="git-sync: rien a synchroniser."
  else
    STAT=$(git diff --shortstat "$HEAD_SHA" "$TREE" 2>/dev/null || echo "")
    SKIP_CI=" [skip ci]"
    if gs_bool checkpointCi; then SKIP_CI=""; fi
    MACHINE=$(gs_machine)
    BODY="sync depuis $MACHINE${SKIP_CI}

Etat de travail non committe, pousse automatiquement par git-sync.
A integrer avec /git-sync:land, jamais a merger tel quel.

Git-Sync-Base: $HEAD_SHA
Git-Sync-Machine: $MACHINE
Git-Sync-Branch: $(gs_branch)"

    CKPT=$(GIT_AUTHOR_NAME="git-sync" GIT_AUTHOR_EMAIL="git-sync@localhost" \
           GIT_COMMITTER_NAME="git-sync" GIT_COMMITTER_EMAIL="git-sync@localhost" \
           git -c commit.gpgsign=false commit-tree "$TREE" -p "$HEAD_SHA" -m "$BODY")

    # The lease is what stops us overwriting a checkpoint the other machine
    # pushed while we were working. We remember what we last put there rather
    # than fetching, so the hook stays inside its timeout.
    LEASE=$(gs_known_push "$SYNC_BRANCH")
    LOG="$REPO_ROOT/.git/git-sync-push-error.log"
    if git push --force-with-lease="refs/heads/$SYNC_BRANCH:$LEASE" \
           origin "$CKPT:refs/heads/$SYNC_BRANCH" >"$LOG" 2>&1; then
      rm -f "$LOG"
      gs_remember_push "$SYNC_BRANCH" "$CKPT"
      MSG="git-sync: checkpoint pousse sur $SYNC_BRANCH ($STAT)."
    elif grep -q "stale info" "$LOG" 2>/dev/null; then
      MSG="git-sync: checkpoint refuse -- une autre machine a pousse sur $SYNC_BRANCH. Rien n'a ete ecrase. Lance /git-sync:land ou resous la divergence a la main."
    else
      MSG="git-sync: push du checkpoint echoue -- voir .git/git-sync-push-error.log"
    fi
  fi
else
  # Legacy mode: commit straight onto the current branch. Kept for repos that
  # genuinely want it (scratch repos where history is noise anyway).
  . "${CLAUDE_PLUGIN_ROOT}/hooks/legacy-commit.sh"
fi

# Opt-in project notes. In checkpoint mode this is how the *narrative* reaches
# the other machine: the checkpoint carries bytes, CLAUDE.md carries the why,
# and CLAUDE.md is reloaded for free at the next session start.
if gs_bool notes "$([ "$(gs_mode)" = "checkpoint" ] && echo true || echo false)"; then
  STAMP="$REPO_ROOT/.git/git-sync-notes-stamp"
  if [ ! -f "$STAMP" ] || [ -z "$(find "$STAMP" -mmin -30 2>/dev/null)" ]; then
    : > "$STAMP"
    CONTEXT="git-sync: si quelque chose de durable a ete decide ou construit depuis la derniere mise a jour, invoque la skill git-sync:notes pour rafraichir la section '## Etat courant' de CLAUDE.md. C'est ce fichier qui transporte le pourquoi vers l'autre machine -- le checkpoint ne transporte que le code. Sinon ne touche a rien et n'en parle pas."
  fi
fi

gs_json Stop "$MSG" "$CONTEXT"
exit 0
