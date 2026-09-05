# git-sync

Claude Code plugin that keeps a git repo in sync automatically, so projects
stay up to date across machines without manual `git pull`/`push`.

Repo: <https://github.com/Thibault-Savenkoff/git-sync>

## What it does

- **On session start** (startup, resume, clear, or compact): runs
  `git pull --ff-only` if the current directory is a git repo.
- **On session stop**: stages all changes, and if there's anything staged,
  commits with message `WIP: auto-sync <date> <time>` and pushes.

Auto-commits are attributed to a `git-sync bot` identity and made without a
signature, so they stay easy to tell apart from the commits you wrote
yourself -- on GitHub, yours keep their "Verified" badge and these don't.

Both hooks are no-ops outside a git repo, and fail silently (15s timeout) so
they never block a session.

## Install

```
/plugin marketplace add Thibault-Savenkoff/git-sync
/plugin install git-sync
```

## Turning it off for a repo or a session

Some projects shouldn't be auto-committed. Two ways to opt out:

```sh
# Per repo -- persistent, stored in .git/config, never committed
git config git-sync.disabled true

# Per session -- one-off
GIT_SYNC_DISABLED=1 claude
```

Either one disables both hooks: no pull on start, no commit or push on stop.
Re-enable a repo with `git config --unset git-sync.disabled`.

## Notes

- Auto-commits use a generic `WIP: auto-sync` message — intended for
  personal/scratch repos, not for shared branches where commit history
  matters.
- Pull uses `--ff-only`, so it won't clobber local changes with a merge; it
  simply skips if a fast-forward isn't possible.
