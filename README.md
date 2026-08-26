# git-sync

Claude Code plugin that keeps a git repo in sync automatically, so projects
stay up to date across machines without manual `git pull`/`push`.

## What it does

- **On session start** (startup, resume, clear, or compact): runs
  `git pull --ff-only` if the current directory is a git repo.
- **On session stop**: stages all changes, and if there's anything staged,
  commits with message `WIP: auto-sync <date> <time>` and pushes.

Both hooks are no-ops outside a git repo, and fail silently (15s timeout) so
they never block a session.

## Install

Add this plugin to your Claude Code plugin marketplace/config, then enable
it for any project you want auto-synced.

## Notes

- Auto-commits use a generic `WIP: auto-sync` message — intended for
  personal/scratch repos, not for shared branches where commit history
  matters.
- Pull uses `--ff-only`, so it won't clobber local changes with a merge; it
  simply skips if a fast-forward isn't possible.
