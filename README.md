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

## Configuration

Run `/git-sync:config` in Claude Code to see the current settings and change
them. Everything lives in the repo's `.git/config`, so it is per-repo, local
to your machine, and never committed.

| Setting | Default | What it does |
| --- | --- | --- |
| `git-sync.disabled` | `false` | `true` turns both hooks off for this repo |
| `git-sync.identity` | `bot` | `self` commits under your own name, signed if you sign |
| `git-sync.botName` | `git-sync bot` | Author name used in bot mode |
| `git-sync.botEmail` | the plugin's machine account | Author email used in bot mode |

```sh
# Don't auto-commit this repo at all
git config git-sync.disabled true

# Skip git-sync for one session only (not a stored setting)
GIT_SYNC_DISABLED=1 claude

# Auto-commit under your own name instead of the bot
git config git-sync.identity self
```

Undo any of them with `git config --unset git-sync.<name>`.

## Notes

- Auto-commits use a generic `WIP: auto-sync` message — intended for
  personal/scratch repos, not for shared branches where commit history
  matters.
- Pull uses `--ff-only`, so it won't clobber local changes with a merge; it
  simply skips if a fast-forward isn't possible.
