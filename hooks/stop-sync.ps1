# Push the work tree to a checkpoint branch on session stop.
# See hooks/stop-sync.sh for why this never runs `git commit`.
. (Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/lib.ps1")

if (-not (Gs-Enabled)) { exit 0 }

$repoRoot = Gs-RepoRoot
$msg = ""
$context = ""

if ((Gs-Mode) -eq "checkpoint") {
  $syncBranch = Gs-SyncBranch
  if (-not $syncBranch) {
    Gs-Json "Stop" "git-sync: detached HEAD, no branch to hang a checkpoint off." ""
    exit 0
  }
  if (-not (Gs-HasCommits)) {
    Gs-Json "Stop" "git-sync: this repository has no commits yet, so there is no base for a checkpoint. Make a first commit." ""
    exit 0
  }

  $remote = Gs-Remote
  if (-not $remote) {
    Gs-Json "Stop" "git-sync: cannot pick a remote (several configured, none named origin, and this branch has no upstream). Set one with: git branch --set-upstream-to=<remote>/$(Gs-Branch)" ""
    exit 0
  }

  $pruned = Gs-PruneOrphans
  if ($pruned) { $msg = "git-sync: retired checkpoints for branches that no longer exist ($pruned)." }

  # See Gs-SnapshotTree: one implementation, shared with the ping-pong check
  # that has to agree with it byte for byte.
  $snap = Gs-SnapshotTree
  $tree = $snap.Tree
  if ($snap.Submodules.Count -gt 0) {
    $msg = (@($msg, "git-sync: submodule contents do not travel with a checkpoint ($($snap.Submodules -join ' ')) -- commit and push them in their own repository.") | Where-Object { $_ }) -join " "
  }

  $headSha = (git rev-parse HEAD).Trim()
  $headTree = (git rev-parse "HEAD^{tree}").Trim()

  if ($tree -eq $headTree) {
    # See stop-sync.sh: retire our own now-meaningless checkpoint rather than
    # leave a dead git-sync/* branch behind. The lease keeps it from touching a
    # fresh checkpoint the other machine pushed meanwhile.
    $msg = (@($msg, "git-sync: nothing to sync.") | Where-Object { $_ }) -join " "
    $ours = Gs-KnownPush $syncBranch
    if ($ours) {
      git push "--force-with-lease=refs/heads/${syncBranch}:${ours}" $remote ":refs/heads/$syncBranch" *> $null
      if ($LASTEXITCODE -eq 0) {
        Gs-ForgetPush $syncBranch
        $msg = "git-sync: work is committed, retired the stale checkpoint on $syncBranch."
      }
    }
  } else {
    $stat = (git diff --shortstat $headSha $tree 2>$null) -join ""
    $skipCi = if (Gs-Bool "checkpointCi") { "" } else { " [skip ci]" }
    $machine = Gs-Machine
    $body = @"
sync from $machine$skipCi

Uncommitted work in progress, pushed automatically by git-sync.
Land it with /git-sync:land; never merge this branch as it stands.

Git-Sync-Base: $headSha
Git-Sync-Machine: $machine
Git-Sync-Branch: $(Gs-Branch)
"@
    $env:GIT_AUTHOR_NAME = "git-sync"; $env:GIT_AUTHOR_EMAIL = "git-sync@localhost"
    $env:GIT_COMMITTER_NAME = "git-sync"; $env:GIT_COMMITTER_EMAIL = "git-sync@localhost"
    $ckpt = (git -c commit.gpgsign=false commit-tree $tree -p $headSha -m $body).Trim()

    $lease = Gs-KnownPush $syncBranch
    $log = Join-Path $repoRoot ".git/git-sync-push-error.log"
    git push "--force-with-lease=refs/heads/${syncBranch}:${lease}" $remote "${ckpt}:refs/heads/$syncBranch" *> $log
    if ($LASTEXITCODE -eq 0) {
      Remove-Item -Force $log -ErrorAction SilentlyContinue
      Gs-RememberPush $syncBranch $ckpt
      Gs-RememberMine $syncBranch $tree
      $msg = (@($msg, "git-sync: checkpoint pushed to $syncBranch ($stat).") | Where-Object { $_ }) -join " "
    } elseif ((Gs-RemoteTree $syncBranch) -eq $tree) {
      # See stop-sync.sh: someone got there first with exactly our content.
      Gs-RememberPush $syncBranch (Gs-RemoteRef $syncBranch)
      Gs-RememberMine $syncBranch $tree
      $msg = (@($msg, "git-sync: checkpoint already up to date on $syncBranch.") | Where-Object { $_ }) -join " "
    } elseif ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match "stale info") {
      # See stop-sync.sh: a refused lease has two very different causes, and the
      # remote is the only thing that can tell them apart.
      if (-not (Gs-RemoteRef $syncBranch)) {
        Gs-ForgetPush $syncBranch
        $msg = "git-sync: the checkpoint on $syncBranch was landed and deleted from another machine. Nothing was pushed this time -- check with 'git pull' whether your local work is already in the history, then start a new session."
      } else {
        $msg = "git-sync: checkpoint refused -- another machine pushed to $syncBranch. Nothing was overwritten. Run /git-sync:land, or resolve the divergence by hand."
      }
    } else {
      $msg = "git-sync: pushing the checkpoint failed -- see .git/git-sync-push-error.log"
    }
  }
} else {
  . (Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/legacy-commit.ps1")
}

$notesDefault = if ((Gs-Mode) -eq "checkpoint") { "true" } else { "false" }
if (Gs-Bool "notes" $notesDefault) {
  $stamp = Join-Path $repoRoot ".git/git-sync-notes-stamp"
  $stale = -not (Test-Path $stamp) -or ((Get-Item $stamp).LastWriteTime -lt (Get-Date).AddMinutes(-30))
  if ($stale) {
    New-Item -ItemType File -Path $stamp -Force | Out-Null
    $context = "git-sync: if anything durable was decided or built since the last update, invoke the git-sync:notes skill to refresh the '## Current state' section of CLAUDE.md. That file is what carries the reasoning to the other machine -- the checkpoint carries only the code. Otherwise change nothing and do not mention this."
  }
}

Gs-Json "Stop" $msg $context
exit 0
