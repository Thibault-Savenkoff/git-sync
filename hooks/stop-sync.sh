#!/bin/sh
# Auto-commit + push on session stop. Merges bundled ignore patterns into the
# repo's local (untracked) git exclude file, so auto-commits never sweep up
# .DS_Store, node_modules, .env, etc. across whatever project this runs in.
set -e

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

GIT_DIR=$(git rev-parse --git-dir)
EXCLUDE_FILE="$GIT_DIR/info/exclude"
PATTERNS_FILE="${CLAUDE_PLUGIN_ROOT}/hooks/ignore-patterns.txt"
MARKER="# git-sync managed patterns"

if [ -f "$PATTERNS_FILE" ] && ! grep -qF "$MARKER" "$EXCLUDE_FILE" 2>/dev/null; then
  mkdir -p "$(dirname "$EXCLUDE_FILE")"
  {
    echo ""
    echo "$MARKER"
    cat "$PATTERNS_FILE"
  } >> "$EXCLUDE_FILE"
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -m "WIP: auto-sync $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1 && git push >/dev/null 2>&1
fi
exit 0
