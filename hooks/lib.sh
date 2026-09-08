# Shared helpers for the git-sync hooks. Sourced, never executed directly.
#
# Both the Stop and the SessionStart hooks need the same notions -- am I in a
# repo, is git-sync switched off here, which branch carries the checkpoint --
# and they used to answer them with copy-pasted snippets that drifted apart.

# gs_config <name> [default] -- read git-sync.<name> from the repo's config.
gs_config() {
  # `git config --get` exits 1 on a missing key. Under `set -e` in the caller
  # that kills the command substitution we are running inside, and the function
  # silently returns "" instead of the default -- so swallow it explicitly.
  _v=$(git config --get "git-sync.$1" 2>/dev/null || true)
  if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "${2-}"; fi
}

# gs_bool <name> [default] -- true when the setting reads "true".
gs_bool() {
  [ "$(gs_config "$1" "${2-false}")" = "true" ]
}

# gs_enabled -- false outside a work tree, or when disabled per repo/session.
gs_enabled() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  if gs_bool disabled; then return 1; fi
  if [ -n "${GIT_SYNC_DISABLED:-}" ]; then return 1; fi
  return 0
}

gs_repo_root() { git rev-parse --show-toplevel 2>/dev/null; }

# gs_branch -- the checked-out branch, empty on a detached HEAD.
gs_branch() { git symbolic-ref --quiet --short HEAD 2>/dev/null; }

# gs_sync_branch -- where this branch's checkpoint lives. Empty when there is
# no branch to hang it off (detached HEAD), which disables checkpoint mode.
gs_sync_branch() {
  _b=$(gs_branch) || return 1
  [ -n "$_b" ] || return 1
  printf 'git-sync/%s' "$_b"
}

# gs_mode -- "checkpoint" (default) or "commit" (the pre-2.0 behaviour).
gs_mode() { gs_config mode checkpoint; }

gs_machine() { gs_config machine "$(hostname 2>/dev/null || echo unknown)"; }

# gs_head_tree -- the tree of HEAD, empty in a repo with no commits yet.
gs_head_tree() { git rev-parse -q --verify "HEAD^{tree}" 2>/dev/null || true; }

gs_has_remote() { [ -n "$(git remote 2>/dev/null)" ]; }

# gs_trailer <commit> <key> -- read one trailer out of a commit message.
gs_trailer() {
  git log -1 --format=%B "$1" 2>/dev/null \
    | sed -n "s/^$2:[[:space:]]*\(.*\)/\1/p" | head -1
}

# gs_json <event> <systemMessage> <additionalContext> -- emit hook output.
# Plain stdout from a hook only reaches the debug log, so anything the user or
# the model should see has to go out as JSON.
gs_json() {
  _esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//'; }
  [ -n "$2" ] || [ -n "$3" ] || return 0
  _out="{\"hookSpecificOutput\":{\"hookEventName\":\"$1\""
  [ -n "$2" ] && _out="$_out,\"systemMessage\":\"$(_esc "$2")\""
  [ -n "$3" ] && _out="$_out,\"additionalContext\":\"$(_esc "$3")\""
  printf '%s}}\n' "$_out"
}

# gs_remember_push <sync-branch> <sha> -- record what we believe the remote ref
# holds, for the next push's --force-with-lease. Kept in .git, so it is local
# to this machine and never travels.
gs_remember_push() {
  _f="$(gs_repo_root)/.git/git-sync-pushed"
  _t=$(mktemp)
  if [ -f "$_f" ]; then grep -v "^$1 " "$_f" > "$_t" 2>/dev/null || true; fi
  printf '%s %s\n' "$1" "$2" >> "$_t"
  mv "$_t" "$_f"
}

# gs_known_push <sync-branch> -- the sha recorded above, empty if none.
gs_known_push() {
  _f="$(gs_repo_root)/.git/git-sync-pushed"
  [ -f "$_f" ] || return 0
  sed -n "s|^$1 ||p" "$_f" | head -1
}

# gs_forget_push <sync-branch> -- drop our record of that ref. Used when the
# checkpoint is gone from the remote: keeping a lease on a sha nobody holds any
# more makes every future push fail forever.
gs_forget_push() {
  _f="$(gs_repo_root)/.git/git-sync-pushed"
  [ -f "$_f" ] || return 0
  _t=$(mktemp)
  grep -v "^$1 " "$_f" > "$_t" 2>/dev/null || true
  mv "$_t" "$_f"
}

# gs_remote_ref <sync-branch> -- the sha the remote actually holds, "" if none.
gs_remote_ref() {
  git ls-remote origin "refs/heads/$1" 2>/dev/null | cut -f1 | head -1
}
