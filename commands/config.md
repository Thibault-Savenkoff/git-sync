---
description: Show and change git-sync settings for the current repo
allowed-tools: Bash(git config:*), Bash(git rev-parse:*), Bash(git symbolic-ref:*), AskUserQuestion
---

Current git-sync settings in this repo:

- repo: !`git rev-parse --show-toplevel 2>/dev/null || echo "(not a git repo)"`
- branch: !`git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(detached HEAD)"`
- mode: !`git config --get git-sync.mode || echo "checkpoint (default)"`
- disabled: !`git config --get git-sync.disabled || echo "false (default)"`
- machine name: !`git config --get git-sync.machine || hostname 2>/dev/null || echo "(hostname)"`
- CI on checkpoints: !`git config --get git-sync.checkpointCi || echo "false (default) -- [skip ci] is added"`
- project notes nudge: !`git config --get git-sync.notes || echo "on in checkpoint mode, off in commit mode (default)"`
- transcript archive: !`git config --get git-sync.archive || echo "false (default)"`
- commit-mode identity: !`git config --get git-sync.identity || echo "bot (default)"`

The user asked: $ARGUMENTS

Show the settings above as a short table.

If they asked for a specific change, apply it and stop there.

If they asked for nothing (the line above is empty), use AskUserQuestion to ask
what they want to change -- one question for the mode, one for syncing on/off,
one for CI on checkpoints, one for the transcript archive, each defaulting to
whatever is currently set. Offer a way to leave everything as it is. Then apply
only what they picked.

Settings live in this repo's `.git/config`, so they are per-repo and never
committed. Apply changes with:

- checkpoint mode (default): `git config --unset git-sync.mode`
- legacy commit mode: `git config git-sync.mode commit`
- turn syncing off/on: `git config git-sync.disabled true` / `git config --unset git-sync.disabled`
- run CI on checkpoints: `git config git-sync.checkpointCi true`
- name this machine: `git config git-sync.machine "portable"`
- project notes nudge off: `git config git-sync.notes false`
- transcript archive on: `git config git-sync.archive true`
- commit mode, as yourself: `git config git-sync.identity self`

Two things worth telling them when relevant:

- **The two modes are genuinely different products.** In `checkpoint` mode
  nothing is ever committed automatically: the work tree is pushed to a
  throwaway `git-sync/<branch>` and lands on the other machine as uncommitted
  work. The project's history stays clean, and `/git-sync:land` is what turns a
  checkpoint into real commits. In `commit` mode every session stop leaves a
  `WIP: auto-sync` commit on the branch -- fine for a scratch repo, a mess on
  anything shared.
- In checkpoint mode the `git-sync:notes` skill is on by default and is not
  decoration: the checkpoint carries the code, `CLAUDE.md` carries the reasoning.
  Turn it off and the other machine gets a diff with no explanation.
- To disable git-sync for a single session, they run `GIT_SYNC_DISABLED=1 claude`.
  That is not a stored setting, so it will not show up in the table above.
- The transcript archive stays in `~/.claude/git-sync-sessions/`, local to this
  machine, never committed, because a transcript can contain secrets that were
  read during the session.

Keep the answer short. Confirm what changed in one line.
