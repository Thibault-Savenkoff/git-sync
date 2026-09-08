# Test harness for the git-sync hooks.
#
# Every case gets a throwaway world: a bare "remote", a clone A, and -- when it
# needs to prove two machines agree -- a clone B. The hooks are then run for
# real against it, because the things that can go wrong here (a lease that
# should have rejected, a deletion that should have propagated) only show up
# against an actual repository.

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

FAILURES=0
CURRENT=""

fail() { printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; FAILURES=$((FAILURES + 1)); }

assert_eq() {
  [ "$1" = "$2" ] && return 0
  fail "${3:-valeur}: attendu [$1], obtenu [$2]"
}

assert_contains() {
  case "$1" in *"$2"*) return 0 ;; esac
  fail "${3:-sortie}: [$2] absent de [$1]"
}

assert_not_contains() {
  case "$1" in *"$2"*) fail "${3:-sortie}: [$2] present alors qu'il ne devrait pas" ;; esac
}

it() { CURRENT="$1"; printf '  - %s\n' "$1"; }

# new_world -- bare remote + clone A, cd into A. Sets $WORLD, $REMOTE, $A.
new_world() {
  WORLD=$(mktemp -d)
  REMOTE="$WORLD/remote.git"
  A="$WORLD/A"
  git init -q --bare "$REMOTE"
  # Without this the bare repo's HEAD stays on whatever `git init` defaulted to,
  # and `git clone` lands on a branch that does not exist -- an empty checkout
  # that makes every later assertion fail for the wrong reason.
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$A"
  cd "$A" || exit 1
  git config user.email a@test; git config user.name "Machine A"
  git config git-sync.machine machineA
  git remote add origin "$REMOTE"
  printf 'ligne 1\n' > file.txt
  git add -A && git commit -qm "init"
  git push -q origin main 2>/dev/null
  git branch -q --set-upstream-to=origin/main main 2>/dev/null
}

# clone_b -- a second machine on the same remote. Sets $B.
clone_b() {
  B="$WORLD/B"
  git clone -q "$REMOTE" "$B"
  ( cd "$B" && git config user.email b@test && git config user.name "Machine B" \
      && git config git-sync.machine machineB )
}

cleanup_world() { [ -n "${WORLD:-}" ] && rm -rf "$WORLD"; cd "$PLUGIN_ROOT" || exit 1; }

# run_stop / run_start -- invoke a hook the way Claude Code does.
run_stop()  { sh "$PLUGIN_ROOT/hooks/stop-sync.sh" 2>&1; }
run_start() { sh "$PLUGIN_ROOT/hooks/session-start.sh" 2>&1; }

sync_branch_sha() { git ls-remote "$REMOTE" "refs/heads/$1" 2>/dev/null | cut -f1; }
