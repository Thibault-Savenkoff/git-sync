---
description: Turn the current checkpoint into real, reviewed commits on this branch
allowed-tools: Bash(git:*), Bash(sh:*), AskUserQuestion, Read
---

!`sh "${CLAUDE_PLUGIN_ROOT}/commands/land-context.sh"`

The user asked: $ARGUMENTS

This is where work in progress becomes history. It is the only place in the
plugin where anything enters the project's branch, and nothing enters it
without the user having approved the message.

## How to proceed

1. **If there is no checkpoint**, say so in one line and stop. If there is one
   but its base does not match the local HEAD, attempt nothing automatic:
   explain the divergence and offer `git diff HEAD refs/git-sync/current`.

2. **If the local work tree is already dirty**, that is the normal case when
   landing from the machine that just did the work: the checkpoint's content is
   already there. Work from the work tree. Otherwise apply the checkpoint first
   with `git read-tree -u --reset refs/git-sync/current && git reset`.

3. **Read the diff** (`git diff HEAD refs/git-sync/current`) and decide whether
   it carries one subject or several. Unrelated directories, or different
   conventional prefixes (`feat` / `fix` / `docs` / `chore`), are the signal to
   split.

   - One subject: propose **one** commit, without ceremony.
   - Several: propose a split, giving each commit its message and its files, in
     an order where each commit stands on its own. Put unrelated changes first,
     so a feature and its documentation stay adjacent.

4. **Point out what should not be committed**: a leftover `print` or
   `console.log`, a TODO left in place, a temporary file, a secret. Ask before
   removing anything.

5. **Get the split and the messages approved** before committing. The user may
   adjust them.

6. **Commit by path** (`git add <files>` then `git commit`), push the branch,
   then delete the checkpoint that has served its purpose:
   `git push <remote> --delete <checkpoint ref>`, using the remote and ref named
   in the context above. Do not delete `.git/git-sync-pushed` wholesale: it
   holds every branch's state. The hooks clear the stale line themselves at the
   next session start, so there is nothing else to do here.

7. **If the checkpoint came from another machine** -- that is, if `Origin`
   differs from `This machine` -- tell the user to run `git pull` there. That
   machine still holds this work uncommitted and does not know it has landed.
   Its next session would say so anyway, but a `git pull` saves the confusion.
   **When the two are the same, say nothing**: sending someone to the machine
   they are already sitting at makes them doubt everything else.

## Rules

- Messages follow the convention already visible in the repository's
  `git log`. Go and read it rather than imposing your own.
- Never split inside a file (`git add -p`). If two subjects are tangled in one
  file, make a single commit and say why.
- Never commit without the user having seen the messages.
- Only delete the checkpoint after a successful push.
- End with one line: what was committed, and that the checkpoint is gone.
