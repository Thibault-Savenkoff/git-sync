---
name: notes
description: Write or refresh the "État courant" section of the repo's CLAUDE.md, so a compaction, a /clear, or a lost session does not take the project's state with it. Use when the user asks for a project write-up, a recap, notes, a "compte rendu", or to save the project state -- and proactively after a milestone lands: a feature implemented, a refactor finished, an architecture decision made, a nasty bug root-caused. Also use to recover state from a past session archived by git-sync. Not for writing a commit message, a changelog, or a PR body.
---

# Notes

Keeps the durable state of a project in one file the next session reloads for
free. `CLAUDE.md` at the repo root is read automatically at every session
start, and git-sync's own hooks commit and push it -- so what is written here
survives compaction, `/clear`, a crash, and a change of machine.

## Two modes

Pick by what the user gives you.

| Input | Mode | Source |
| --- | --- | --- |
| nothing, or "recap this" | **live** | this conversation |
| a session file, a date, "the session from yesterday" | **recover** | `~/.claude/git-sync-sessions/` |

### Live

**Do not read this session's transcript.** You are the context; re-reading it
costs tokens to learn what you already know, and the file runs to megabytes.
Write from the conversation directly.

### Recover

For a session that is already dead and whose state was never written down.

1. List what is there: `ls -lt ~/.claude/git-sync-sessions/`. The names are
   `<date>-<time>-<repo>-<transcript>.jsonl`. Show the candidates and let the
   user pick when the reference is ambiguous.
2. Extract, never `cat`. A raw transcript does not fit in context and is mostly
   tool output:
   ```sh
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/notes/extract-transcript.py" <file>
   ```
   It keeps user turns and assistant prose, drops tool results, and truncates.
   Pass `--max-chars` if the default is not enough.
3. Write the section from that, and say in one line that it came from an
   archived session rather than from live memory.

## What goes in

The macro and the non-derivable. The reader is a future session that can read
the code but was not there for the reasoning.

- Decisions taken, **and why** -- especially options rejected and the reason.
- What is in flight, and the next concrete step.
- Traps hit: what broke, what the real cause was, what not to try again.
- Constraints that bind the project and live nowhere in the code.

Never a file tree, never recopied code, never a restated schema, never what
`git log` already says. Point at the code instead of duplicating it.

## Format

One `## État courant` section in `CLAUDE.md` at the repo root, created with the
file if either is missing. Short bullets. Overwrite the section in place --
this is current state, not a journal, so stale entries get removed rather than
appended to. Leave the rest of `CLAUDE.md` alone.

```markdown
## État courant

_Mis à jour le 2026-09-06._

### Décisions
- ...

### En cours
- ...

### Pièges
- ...
```

Drop a heading with nothing under it rather than leaving it empty.

## Rules

- Nothing durable since the last update? Say so in one line and write nothing.
  A no-op is a valid outcome.
- Never invent. Only what this conversation or the transcript actually shows.
- The write-up is worth ~20 lines. If it grows past a screen, it is a journal
  and needs cutting.
- `CLAUDE.md` is tracked and gets pushed. Nothing secret goes in it -- no
  tokens, no keys, no `.env` values. Reference them by name.
- Confirm with the user before writing when the repo is not theirs, or when
  `CLAUDE.md` already has an `## État courant` written by someone else.
- End with one line naming what changed.
