#!/bin/sh
# Auto-commit + push on session stop. Merges bundled ignore patterns into the
# repo's tracked .gitignore, so auto-commits never sweep up .DS_Store,
# node_modules, .env, etc. -- and other clones/collaborators get it too.
set -e

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel)
GITIGNORE="$REPO_ROOT/.gitignore"
PATTERNS_FILE="${CLAUDE_PLUGIN_ROOT}/hooks/ignore-patterns.txt"
MARKER="# git-sync managed patterns"

if [ -f "$PATTERNS_FILE" ] && ! grep -qF "$MARKER" "$GITIGNORE" 2>/dev/null; then
  {
    [ -s "$GITIGNORE" ] && echo ""
    echo "$MARKER"
    cat "$PATTERNS_FILE"
  } >> "$GITIGNORE"
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -m "WIP: auto-sync $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1 || true
  git push >/dev/null 2>&1 || true
fi
exit 0
