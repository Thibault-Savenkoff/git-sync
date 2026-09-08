# git-sync

Claude Code plugin that carries work in progress between your machines — start
something on the laptop, keep going on the desktop — **without leaving
`WIP: auto-sync` commits in the project's history**.

Repo: <https://github.com/Thibault-Savenkoff/git-sync>

## The idea

Moving work between machines and writing history are two different jobs. They
have different lifetimes, different audiences, and different standards. The
usual auto-commit plugin conflates them: it borrows the project's history as a
transport and leaves its litter behind.

git-sync separates them.

- **Transport** — on session stop, your work tree is pushed to a throwaway
  branch `git-sync/<branch>`. It is *not* committed: the commit object is built
  with plumbing against a temporary index, so your `HEAD`, your staged changes
  and your work tree are left exactly as you had them. The branch carries a
  single checkpoint, overwritten each time, so it never grows.
- **Arrival** — on session start, the other machine applies that checkpoint into
  its work tree, still uncommitted, and tells Claude what changed and where it
  came from.
- **History** — `/git-sync:land` is the one place anything enters your branch.
  Claude reads the diff, proposes a message (or a split into several commits
  when the diff covers unrelated subjects), you approve, it commits.

`main` never sees a checkpoint. Your history contains only commits you approved.

## What it does

- **On session start**: fast-forward pull, then apply the other machine's
  checkpoint if there is one — and refuse, loudly, if the work tree is dirty or
  the histories have diverged. It never overwrites local work.
- **On session stop**: push a checkpoint of the work tree. `[skip ci]` by
  default, so intermediate states don't burn CI minutes.
- **`/git-sync:land`**: turn the checkpoint into reviewed commits, then delete it.
- **Project notes**: the `git-sync:notes` skill writes an `## État courant`
  section into `CLAUDE.md`. This matters more than it looks: **a checkpoint
  carries code, `CLAUDE.md` carries the reasoning.** It is reloaded automatically
  at every session start, so the other machine gets the decisions and the traps,
  not just a diff. On by default in checkpoint mode.
- **Transcript archive** (opt-in): on session end, copies the session transcript
  to `~/.claude/git-sync-sessions/`. Kept 30 days, mode `600`, deliberately
  **outside** the work tree — a transcript holds whatever was read that session,
  so it is never staged and never pushed.

Both hooks are no-ops outside a git repo, and fail silently (15s timeout) so
they never block a session.

## Install

```
/plugin marketplace add Thibault-Savenkoff/git-sync
/plugin install git-sync
```

## Configuration

Run `/git-sync:config` to see and change the settings. Everything lives in the
repo's `.git/config`, so it is per-repo, local to your machine, never committed.

| Setting | Default | What it does |
| --- | --- | --- |
| `git-sync.mode` | `checkpoint` | `commit` restores the pre-2.0 behaviour: auto-commit onto the current branch |
| `git-sync.disabled` | `false` | `true` turns both hooks off for this repo |
| `git-sync.machine` | the hostname | Name shown for this machine in checkpoints |
| `git-sync.checkpointCi` | `false` | `true` drops `[skip ci]`, so CI runs on checkpoints |
| `git-sync.notes` | on in checkpoint mode | Nudge Claude to refresh `CLAUDE.md` on session stop |
| `git-sync.archive` | `false` | `true` archives session transcripts locally |
| `git-sync.identity` | `bot` | Commit mode only: `self` commits under your own name |

```sh
# Skip git-sync for one session only (not a stored setting)
GIT_SYNC_DISABLED=1 claude

# Give this machine a readable name
git config git-sync.machine "portable"

# Let CI run on checkpoints too
git config git-sync.checkpointCi true
```

Undo any of them with `git config --unset git-sync.<name>`.

## Safety

The checkpoint is force-pushed, which is safe only because that branch belongs
to you alone — but "alone" still means two machines, so every push carries a
`--force-with-lease`. If the other machine pushed while you were working, your
push is **refused** and nothing is overwritten; git-sync says so and leaves the
resolution to you.

On the receiving side the guards refuse rather than guess: a checkpoint is not
applied if it came from this same machine, if it is based on a different commit
than local `HEAD`, or if the work tree holds modifications that are not already
in a checkpoint you pushed yourself. That last exception is what makes the
ordinary ping-pong work — coming back to the laptop, its dirty tree *is* what it
last pushed, and the incoming checkpoint was built on top of it — while still
refusing to touch work that has never left the machine. A machine that refused
an incoming checkpoint does not get to overwrite it either: the lease is
recorded when work is taken in, not when it is merely seen.

Checkpoints clean up after themselves. One whose content has since been
committed is retired, and so is one whose branch was renamed or deleted —
otherwise every branch you ever synced would leave a dead `git-sync/*` behind,
which is exactly the clutter this mode exists to avoid.

## Upgrading from 1.x

Checkpoint mode is the new default, and it is a breaking change: sessions stop
producing commits. If you actually want the old behaviour on a given repo —
a scratch repo where history is noise anyway — set `git config git-sync.mode commit`.

Any `WIP: auto-sync` commits already in your history stay there; git-sync does
not rewrite what it did before.

## Tests

```sh
sh tests/run.sh        # both implementations
sh tests/run.sh sh     # POSIX hooks only, when pwsh is not installed
```

The suite builds a real bare remote and one or two clones per case and runs the
hooks against them — a lease that should have been refused, or a deletion that
failed to propagate, only shows up against an actual repository.

Every case runs twice, once against the shell hooks and once against the
PowerShell ones, plus a mixed round trip in both directions: a laptop and a
desktop are rarely the same OS, so a checkpoint written on one has to be
readable on the other. `pwsh` missing simply skips those runs.

Measured on a 20,000-file repository, the stop hook takes ~0.6s (shell) and
~1.4s (PowerShell), against a 15s timeout.
