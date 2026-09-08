# Pre-2.0 behaviour: commit everything onto the current branch and push.
# Sourced by stop-sync.sh when `git config git-sync.mode commit` is set.
#
# This leaves "WIP: auto-sync" commits in the project's history, which is the
# problem checkpoint mode exists to solve -- but on a scratch repo where the
# history is disposable anyway, it is simpler and needs no landing step.

git add -A
if ! git diff --cached --quiet; then
  SIGN="-c commit.gpgsign=false"
  if [ "$(gs_config identity bot)" = "self" ]; then
    SIGN=""
  else
    GIT_AUTHOR_NAME=$(gs_config botName "git-sync bot")
    GIT_AUTHOR_EMAIL=$(gs_config botEmail "325430966+gitsync-bot@users.noreply.github.com")
    GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
    GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
    export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  fi
  git $SIGN commit -m "WIP: auto-sync $(date '+%Y-%m-%d %H:%M')" \
      -m "Committed automatically by git-sync
https://github.com/Thibault-Savenkoff/git-sync" >/dev/null 2>&1 || true
  if ! gs_has_remote; then
    MSG="git-sync: commit local (aucun remote configure)."
  elif git push >"$REPO_ROOT/.git/git-sync-push-error.log" 2>&1; then
    rm -f "$REPO_ROOT/.git/git-sync-push-error.log"
    MSG="git-sync: commit et push effectues."
  else
    MSG="git-sync: commit effectue mais push echoue -- voir .git/git-sync-push-error.log"
  fi
fi
