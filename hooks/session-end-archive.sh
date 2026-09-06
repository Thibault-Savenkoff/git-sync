#!/bin/sh
# Archive the session transcript on SessionEnd, as crash insurance for the case
# the Stop-hook notes never covered: a session that dies before the model got a
# chance to write anything down.
#
# SessionEnd cannot inject context -- nothing runs after it -- so this hook does
# the only useful thing left: it keeps the raw material.
#
# The archive deliberately lives OUTSIDE the work tree. stop-sync.sh runs
# `git add -A` and pushes, and a transcript holds whatever was read that session
# (tokens, .env contents, keys). It stays local, per-machine, never synced.
set -e

[ "$(git config --get git-sync.archive)" = "true" ] || exit 0
[ -n "$GIT_SYNC_DISABLED" ] && exit 0

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

DEST="$HOME/.claude/git-sync-sessions"
mkdir -p "$DEST"
chmod 700 "$DEST"

SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo no-repo)")
OUT="$DEST/$(date '+%Y%m%d-%H%M%S')-$SLUG-$(basename "$TRANSCRIPT")"
cp "$TRANSCRIPT" "$OUT"
chmod 600 "$OUT"

# ponytail: 30-day window, plain mtime prune. Enough for "I lost yesterday's
# session"; swap for a size cap if the directory ever grows past caring.
find "$DEST" -type f -mtime +30 -delete 2>/dev/null || true

printf '{"hookSpecificOutput":{"hookEventName":"SessionEnd","systemMessage":"git-sync: session transcript archived to ~/.claude/git-sync-sessions (local only)."}}\n'
exit 0
