# git-sync

Claude Code plugin that keeps a git repo in sync automatically, so projects
stay up to date across machines without manual `git pull`/`push`.

Repo: <https://github.com/Thibault-Savenkoff/git-sync>

## What it does

- **On session start** (startup, resume, clear, or compact): runs
  `git pull --ff-only` if the current directory is a git repo.
- **On session stop**: stages all changes, and if there's anything staged,
  commits with message `WIP: auto-sync <date> <time>` and pushes.
- **Project notes**: the `git-sync:notes` skill writes an `## État courant`
  section into the repo's `CLAUDE.md` — decisions and why, what's in flight,
  traps hit. `CLAUDE.md` is reloaded automatically at every session start, and
  the sync hooks commit and push it like anything else, so a `/compact`, a
  `/clear`, or a lost session doesn't take the project's state with it.
  Ask for it ("fais un compte rendu"), or let Claude reach for it after a
  milestone lands. Set `git config git-sync.notes true` to also get a periodic
  nudge on session stop, at most every 30 minutes.
- **Transcript archive** (opt-in): on session end, copies the session
  transcript to `~/.claude/git-sync-sessions/`, for the crash that beats the
  notes to it. Kept 30 days, mode `600`, and deliberately **outside** the work
  tree — a transcript holds whatever was read that session, so it is never
  staged and never pushed. `git-sync:notes` can then reconstruct a write-up
  from one of those archives, for the session that died before writing
  anything down.

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
| `git-sync.notes` | `false` | `true` nudges Claude to refresh `CLAUDE.md` on session stop |
| `git-sync.archive` | `false` | `true` archives session transcripts locally |

```sh
# Don't auto-commit this repo at all
git config git-sync.disabled true

# Skip git-sync for one session only (not a stored setting)
GIT_SYNC_DISABLED=1 claude

# Auto-commit under your own name instead of the bot
git config git-sync.identity self

# Nudge Claude to refresh CLAUDE.md's "Etat courant" (at most every 30 min).
# The git-sync:notes skill works without this -- the setting only adds the nudge.
git config git-sync.notes true

# Archive session transcripts to ~/.claude/git-sync-sessions (local only)
git config git-sync.archive true
```

Undo any of them with `git config --unset git-sync.<name>`.

## Notes

- Auto-commits use a generic `WIP: auto-sync` message — intended for
  personal/scratch repos, not for shared branches where commit history
  matters.
- Pull uses `--ff-only`, so it won't clobber local changes with a merge; it
  simply skips if a fast-forward isn't possible.
