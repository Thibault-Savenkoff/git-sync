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
  REMOTE=$(gs_remote)
  if [ -z "$REMOTE" ]; then
    gs_json Stop "git-sync: impossible de choisir un remote (plusieurs configures, aucun nomme origin, et la branche n'a pas d'upstream). Fixe-le avec: git branch --set-upstream-to=<remote>/$(gs_branch)" ""
    exit 0
  fi

  PRUNED=$(gs_prune_orphans)
  if [ -n "$PRUNED" ]; then
    MSG="git-sync: checkpoints retires pour des branches disparues ($PRUNED)."
  fi

  # Snapshot the work tree. See gs_snapshot_tree: one implementation, shared
  # with the ping-pong check that has to agree with it byte for byte.
  gs_snapshot_tree
  TREE="$GS_TREE"
  if [ -n "$GS_SUBMODULES" ]; then
    MSG="${MSG:+$MSG }git-sync: le contenu des sous-modules n'est pas transporte ($GS_SUBMODULES) -- committe et pousse-les dans leur propre depot."
  fi

  HEAD_SHA=$(git rev-parse HEAD)
  if [ "$TREE" = "$(git rev-parse "HEAD^{tree}")" ]; then
    # Nothing differs from the last real commit, so a checkpoint would say
    # nothing -- and if one of ours is still out there it is now describing work
    # that has been committed. Retire it, or every branch ever synced leaves a
    # dead git-sync/* behind, which is the clutter this whole mode exists to
    # avoid. The lease makes this safe: it deletes only the exact object we
    # pushed, never a fresh checkpoint the other machine put there meanwhile.
    MSG="${MSG:+$MSG }git-sync: rien a synchroniser."
    OURS=$(gs_known_push "$SYNC_BRANCH")
    if [ -n "$OURS" ]; then
      if git push --force-with-lease="refs/heads/$SYNC_BRANCH:$OURS" \
             "$REMOTE" ":refs/heads/$SYNC_BRANCH" >/dev/null 2>&1; then
        gs_forget_push "$SYNC_BRANCH"
        MSG="${MSG% }git-sync: travail committe, checkpoint obsolete retire de $SYNC_BRANCH."
      fi
    fi
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
           "$REMOTE" "$CKPT:refs/heads/$SYNC_BRANCH" >"$LOG" 2>&1; then
      rm -f "$LOG"
      gs_remember_push "$SYNC_BRANCH" "$CKPT"
      gs_remember_mine "$SYNC_BRANCH" "$TREE"
      MSG="${MSG:+$MSG }git-sync: checkpoint pousse sur $SYNC_BRANCH ($STAT)."
    elif grep -q "stale info" "$LOG" 2>/dev/null; then
      # A refused lease has two very different causes, and telling the user the
      # wrong one is worse than saying nothing. Ask the remote which it is --
      # one extra round trip, only ever on the error path.
      REMOTE_SHA=$(gs_remote_ref "$SYNC_BRANCH")
      if [ -z "$REMOTE_SHA" ]; then
        # The checkpoint is gone: /git-sync:land committed its content and
        # deleted it. Holding the old lease would block every future push.
        gs_forget_push "$SYNC_BRANCH"
        MSG="git-sync: le checkpoint de $SYNC_BRANCH a ete integre puis supprime depuis une autre machine. Rien n'a ete pousse cette fois-ci -- verifie avec 'git pull' que ton travail local n'est pas deja dans l'historique, puis relance une session."
      else
        MSG="git-sync: checkpoint refuse -- une autre machine a pousse sur $SYNC_BRANCH. Rien n'a ete ecrase. Lance /git-sync:land ou resous la divergence a la main."
      fi
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
