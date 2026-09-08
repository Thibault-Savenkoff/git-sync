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

# gs_encode / gs_decode -- branch name <-> one safe ref path segment.
#
# Git refuses refs/heads/a/b while refs/heads/a exists, so deriving the
# checkpoint ref straight from the branch name makes "feat" and "feat/sub"
# mutually exclusive: whichever comes second can never sync, and says only that
# the push failed. Percent-encoding the separator keeps every checkpoint at
# exactly one level under git-sync/, where no such conflict can arise.
gs_encode() { printf '%s' "$1" | sed 's/%/%25/g; s|/|%2F|g'; }
gs_decode() { printf '%s' "$1" | sed 's|%2F|/|g; s/%25/%/g'; }

# gs_sync_branch -- where this branch's checkpoint lives. Empty when there is
# no branch to hang it off (detached HEAD), which disables checkpoint mode.
gs_sync_branch() {
  _b=$(gs_branch) || return 1
  [ -n "$_b" ] || return 1
  printf 'git-sync/%s' "$(gs_encode "$_b")"
}

# gs_mode -- "checkpoint" (default) or "commit" (the pre-2.0 behaviour).
gs_mode() { gs_config mode checkpoint; }

gs_machine() { gs_config machine "$(hostname 2>/dev/null || echo unknown)"; }

# gs_head_tree -- the tree of HEAD, empty in a repo with no commits yet.
gs_head_tree() { git rev-parse -q --verify "HEAD^{tree}" 2>/dev/null || true; }

gs_has_remote() { [ -n "$(gs_remote)" ]; }

# gs_remote -- which remote to sync against. "origin" was hardcoded, which left
# the plugin silently inoperative on any repo whose remote is named otherwise --
# and all the user saw was that the push had failed. Preference order: the
# branch's own upstream, then origin, then the only remote if there is just one.
gs_remote() {
  _b=$(gs_branch)
  if [ -n "$_b" ]; then
    _r=$(git config --get "branch.$_b.remote" 2>/dev/null || true)
    if [ -n "$_r" ]; then printf '%s' "$_r"; return 0; fi
  fi
  _all=$(git remote 2>/dev/null)
  case "
$_all
" in *"
origin
"*) printf 'origin'; return 0 ;; esac
  if [ "$(printf '%s\n' "$_all" | grep -c .)" = "1" ]; then
    printf '%s' "$_all"
  fi
}

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

# gs_snapshot_tree -- the tree the work tree would produce, computed through an
# index of our own so the user's staging area is neither read nor disturbed.
#
# The stop hook and the ping-pong safety check both need this, and they must
# agree exactly: the check asks "is my dirty tree the one I already pushed?",
# which is only meaningful if both sides build the tree the same way. Hence one
# function, not two similar blocks.
#
# Sets GS_TREE and GS_SUBMODULES rather than printing: a command substitution
# would run the whole thing in a subshell and drop GS_SUBMODULES on the floor.
#
# GS_SUBMODULES lists the submodule paths whose checkout has moved. Their
# gitlinks are pinned back to HEAD, because the commit they point at lives only
# in this machine's submodule clone: shipping it would promise the other machine
# something it can never fetch.
gs_snapshot_tree() {
  GS_SUBMODULES=""
  _tmp=$(mktemp)
  GIT_INDEX_FILE="$_tmp"; export GIT_INDEX_FILE
  git read-tree HEAD 2>/dev/null
  _ex="${CLAUDE_PLUGIN_ROOT}/hooks/ignore-patterns.txt"
  if [ -f "$_ex" ]; then
    git -c core.excludesFile="$_ex" add -A 2>/dev/null
  else
    git add -A 2>/dev/null
  fi
  for _p in $(git ls-files -s 2>/dev/null | awk '$1 == "160000" { print $4 }'); do
    _head=$(git rev-parse -q --verify "HEAD:$_p" 2>/dev/null || true)
    _now=$(git ls-files -s -- "$_p" 2>/dev/null | awk '{print $2}')
    [ "$_head" = "$_now" ] && continue
    GS_SUBMODULES="${GS_SUBMODULES:+$GS_SUBMODULES }$_p"
    if [ -n "$_head" ]; then
      git update-index --cacheinfo "160000,$_head,$_p" 2>/dev/null
    else
      git update-index --force-remove "$_p" 2>/dev/null
    fi
  done
  GS_TREE=$(git write-tree 2>/dev/null)
  unset GIT_INDEX_FILE
  rm -f "$_tmp"
}

# gs_worktree_tree -- printing wrapper, for the one caller that only wants the
# tree and can afford a subshell.
gs_worktree_tree() { gs_snapshot_tree; printf '%s' "$GS_TREE"; }

# gs_remember_mine / gs_known_mine <sync-branch> [tree] -- the tree of the last
# checkpoint *we* pushed. Distinct from gs_remember_push, which records what the
# ref holds: this one answers "are my uncommitted changes already safely on the
# remote?", which is what makes it safe to accept an incoming checkpoint over a
# dirty work tree.
gs_remember_mine() {
  _f="$(gs_repo_root)/.git/git-sync-mine"
  _t=$(mktemp)
  if [ -f "$_f" ]; then grep -v "^$1 " "$_f" > "$_t" 2>/dev/null || true; fi
  printf '%s %s\n' "$1" "$2" >> "$_t"
  mv "$_t" "$_f"
}

gs_known_mine() {
  _f="$(gs_repo_root)/.git/git-sync-mine"
  [ -f "$_f" ] || return 0
  sed -n "s|^$1 ||p" "$_f" | head -1
}

# gs_remote_ref <sync-branch> -- the sha the remote actually holds, "" if none.
gs_remote_ref() {
  git ls-remote "$(gs_remote)" "refs/heads/$1" 2>/dev/null | cut -f1 | head -1
}

# gs_prune_orphans -- drop checkpoints whose branch no longer exists locally.
#
# Renaming or deleting a branch moves the target out from under a checkpoint we
# pushed, and nothing else would ever clean it up: it would sit on the remote
# forever. Only refs we recorded pushing are considered, and each deletion
# carries its lease, so a checkpoint the other machine owns is never touched.
gs_prune_orphans() {
  _f="$(gs_repo_root)/.git/git-sync-pushed"
  [ -f "$_f" ] || return 0
  _pruned=""
  while read -r _sb _sha; do
    [ -n "$_sb" ] || continue
    case "$_sb" in git-sync/*) ;; *) continue ;; esac
    _name=$(gs_decode "${_sb#git-sync/}")
    git show-ref --verify --quiet "refs/heads/$_name" && continue
    if git push --force-with-lease="refs/heads/$_sb:$_sha" \
           "$(gs_remote)" ":refs/heads/$_sb" >/dev/null 2>&1; then
      _pruned="${_pruned:+$_pruned }$_name"
    fi
    gs_forget_push "$_sb"
  done < "$_f"
  printf '%s' "$_pruned"
}
