#!/usr/bin/env python3
"""Reduce an archived session transcript to what a write-up actually needs.

A .jsonl session runs to megabytes and is mostly tool results -- file contents,
command output, search hits. None of that belongs in a recap, and all of it
would blow the context window. This keeps the conversation: user turns and
assistant prose, tool *calls* named but not their output.

    python3 extract-transcript.py <file.jsonl> [--max-chars N]
"""
import argparse
import json
import sys

# ponytail: budget by characters, not tokens. Close enough to keep a transcript
# inside a context window, and it needs no tokeniser.
DEFAULT_MAX = 60000
TURN_CAP = 2000  # a single turn never eats the whole budget


def text_of(content):
    """Pull readable text out of a message's content, whatever shape it is."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    out = []
    for block in content:
        if not isinstance(block, dict):
            continue
        kind = block.get("type")
        if kind == "text":
            out.append(block.get("text", ""))
        elif kind == "thinking":
            pass  # reasoning is not the record
        elif kind == "tool_use":
            out.append(f"[tool: {block.get('name', '?')}]")
        # tool_result is deliberately dropped -- that is the bulk of the file
    return "\n".join(p for p in out if p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--max-chars", type=int, default=DEFAULT_MAX)
    args = ap.parse_args()

    turns, skipped = [], 0
    try:
        with open(args.path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    skipped += 1
                    continue
                msg = entry.get("message") or entry
                role = msg.get("role") or entry.get("type")
                if role not in ("user", "assistant"):
                    continue
                body = text_of(msg.get("content", "")).strip()
                if not body:
                    continue
                if len(body) > TURN_CAP:
                    body = body[:TURN_CAP] + "\n[... turn truncated ...]"
                turns.append(f"### {role}\n{body}")
    except OSError as exc:
        sys.exit(f"cannot read {args.path}: {exc}")

    if not turns:
        sys.exit("no conversation turns found -- wrong file?")

    # Keep the tail: the end of a session holds the conclusions, the start holds
    # setup noise. Walk backwards until the budget is spent, then restore order.
    kept, used = [], 0
    for turn in reversed(turns):
        if used + len(turn) > args.max_chars:
            break
        kept.append(turn)
        used += len(turn)
    kept.reverse()

    dropped = len(turns) - len(kept)
    print(f"# {args.path}")
    print(f"# {len(turns)} turns, {len(kept)} kept"
          + (f", {dropped} older ones dropped" if dropped else "")
          + (f", {skipped} unreadable lines" if skipped else ""))
    print()
    print("\n\n".join(kept))


if __name__ == "__main__":
    main()
