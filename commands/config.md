---
description: Show and change git-sync settings for the current repo
allowed-tools: Bash(git config:*), Bash(git rev-parse:*), AskUserQuestion
---

Current git-sync settings in this repo:

- repo: !`git rev-parse --show-toplevel 2>/dev/null || echo "(not a git repo)"`
- disabled: !`git config --get git-sync.disabled || echo "false (default)"`
- identity: !`git config --get git-sync.identity || echo "bot (default)"`
- bot name: !`git config --get git-sync.botName || echo "git-sync bot (default)"`
- bot email: !`git config --get git-sync.botEmail || echo "325430966+gitsync-bot@users.noreply.github.com (default)"`

The user asked: $ARGUMENTS

Show the settings above as a short table.

If they asked for a specific change, apply it and stop there.

If they asked for nothing (the line above is empty), use AskUserQuestion to ask
what they want to change — one question for syncing (on/off), one for the commit
identity (bot/self), each defaulting to whatever is currently set. Offer a way to
leave everything as it is. Then apply only what they picked.

Settings live in this repo's `.git/config`, so they are per-repo and never
committed. Apply changes with:

- turn syncing off/on: `git config git-sync.disabled true` / `git config --unset git-sync.disabled`
- commit as the user: `git config git-sync.identity self`
- commit as the bot (default): `git config --unset git-sync.identity`
- custom bot identity: `git config git-sync.botName "..."` and `git config git-sync.botEmail "..."`

Two things worth telling them when relevant:

- With `identity self`, auto-commits carry their own name and are signed if
  they have commit signing enabled — indistinguishable from hand-written ones.
- To disable git-sync for a single session instead of the whole repo, they run
  `GIT_SYNC_DISABLED=1 claude`. That is not a stored setting, so it will not
  show up in the table above.

Keep the answer short. Confirm what changed in one line.
