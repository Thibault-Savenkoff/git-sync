#!/bin/sh
# Auto-commit + push on session stop. Merges bundled ignore patterns into the
# repo's tracked .gitignore, so auto-commits never sweep up .DS_Store,
# node_modules, .env, etc. -- and other clones/collaborators get it too.
#
# Plain stdout from a Stop hook only reaches the debug log, not Claude or the
# user -- so any activity worth reporting is emitted as JSON systemMessage.
set -e

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Opt-out: per-repo (git config git-sync.disabled true) or per-session
# (GIT_SYNC_DISABLED=1 claude).
[ "$(git config --get git-sync.disabled)" = "true" ] && exit 0
[ -n "$GIT_SYNC_DISABLED" ] && exit 0

REPO_ROOT=$(git rev-parse --show-toplevel)
GITIGNORE="$REPO_ROOT/.gitignore"
PATTERNS_FILE="${CLAUDE_PLUGIN_ROOT}/hooks/ignore-patterns.txt"
MARKER="# git-sync managed patterns"
MSG=""

if [ -f "$PATTERNS_FILE" ] && ! grep -qF "$MARKER" "$GITIGNORE" 2>/dev/null; then
  {
    [ -s "$GITIGNORE" ] && echo ""
    echo "$MARKER"
    cat "$PATTERNS_FILE"
  } >> "$GITIGNORE"
  MSG="git-sync: added a .gitignore with common ignore patterns to this repo."
fi

git add -A
if ! git diff --cached --quiet; then
  # Default: attributed to a bot identity and left unsigned, so auto-commits
  # stay visibly distinct from the ones you actually wrote. Set
  # `git config git-sync.identity self` to commit as yourself instead.
  SIGN="-c commit.gpgsign=false"
  if [ "$(git config --get git-sync.identity)" = "self" ]; then
    SIGN=""
  else
    GIT_AUTHOR_NAME=$(git config --get git-sync.botName || echo "git-sync bot")
    GIT_AUTHOR_EMAIL=$(git config --get git-sync.botEmail \
      || echo "325430966+gitsync-bot@users.noreply.github.com")
    GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
    GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
    export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  fi
  git $SIGN \
    commit -m "WIP: auto-sync $(date '+%Y-%m-%d %H:%M')" \
           -m "Committed automatically by git-sync
https://github.com/Thibault-Savenkoff/git-sync" >/dev/null 2>&1 || true
  if [ -z "$(git remote)" ]; then
    MSG="${MSG:+$MSG }git-sync: committed changes locally (no remote configured, not pushed)."
  elif git push >"$REPO_ROOT/.git/git-sync-push-error.log" 2>&1; then
    rm -f "$REPO_ROOT/.git/git-sync-push-error.log"
    MSG="${MSG:+$MSG }git-sync: committed and pushed changes."
  else
    MSG="${MSG:+$MSG }git-sync: committed changes but push failed -- see .git/git-sync-push-error.log"
  fi
fi

# Opt-in project notes: `git config git-sync.notes true`.
#
# A hook is a shell script -- it cannot summarise a session itself, only ask the
# model to. Stop is the one event that both fires while the session is still
# alive and accepts additionalContext; PreCompact and SessionEnd accept only
# systemMessage, so injecting there is a silent no-op. Throttled through an
# untracked stamp in .git, so a long session is asked now and then rather than
# after every turn.
CONTEXT=""
if [ "$(git config --get git-sync.notes)" = "true" ]; then
  STAMP="$REPO_ROOT/.git/git-sync-notes-stamp"
  # ponytail: fixed 30 min; make it git config git-sync.notesInterval if anyone asks.
  if [ ! -f "$STAMP" ] || [ -z "$(find "$STAMP" -mmin -30 2>/dev/null)" ]; then
    : > "$STAMP"
    CONTEXT="git-sync: avant que ce contexte parte en compaction, mets a jour la section '## Etat courant' de CLAUDE.md a la racine du repo (cree le fichier ou la section s'ils sont absents) avec les decisions prises, ce qui est en cours, et les pieges rencontres. Uniquement le macro et le non-derivable: jamais l'arborescence, jamais du code recopie. Si rien de durable n'a ete decide depuis la derniere mise a jour, ne touche a rien et n'en parle pas."
  fi
fi

if [ -n "$MSG" ] || [ -n "$CONTEXT" ]; then
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  OUT='{"hookSpecificOutput":{"hookEventName":"Stop"'
  [ -n "$MSG" ] && OUT="$OUT,\"systemMessage\":\"$(esc "$MSG")\""
  [ -n "$CONTEXT" ] && OUT="$OUT,\"additionalContext\":\"$(esc "$CONTEXT")\""
  printf '%s}}\n' "$OUT"
fi
exit 0
