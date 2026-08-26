#!/bin/sh
# Auto-commit + push on session stop. Merges bundled ignore patterns into the
# repo's tracked .gitignore, so auto-commits never sweep up .DS_Store,
# node_modules, .env, etc. -- and other clones/collaborators get it too.
#
# Plain stdout from a Stop hook only reaches the debug log, not Claude or the
# user -- so any activity worth reporting is emitted as JSON systemMessage.
set -e

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

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
  git commit -m "WIP: auto-sync $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1 || true
  if [ -z "$(git remote)" ]; then
    MSG="${MSG:+$MSG }git-sync: committed changes locally (no remote configured, not pushed)."
  elif git push >/dev/null 2>&1; then
    MSG="${MSG:+$MSG }git-sync: committed and pushed changes."
  else
    MSG="${MSG:+$MSG }git-sync: committed changes but push failed (check remote/auth)."
  fi
fi

if [ -n "$MSG" ]; then
  ESCAPED=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"Stop","systemMessage":"%s"}}\n' "$ESCAPED"
fi
exit 0
