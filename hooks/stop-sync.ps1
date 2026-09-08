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
    Gs-Json "Stop" "git-sync: HEAD detache, pas de checkpoint (aucune branche a suivre)." ""
    exit 0
  }
  if (-not (Gs-HasCommits)) {
    Gs-Json "Stop" "git-sync: ce depot n'a encore aucun commit, il n'y a pas de base sur laquelle poser un checkpoint. Fais un premier commit." ""
    exit 0
  }

  $remote = Gs-Remote
  if (-not $remote) {
    Gs-Json "Stop" "git-sync: impossible de choisir un remote (plusieurs configures, aucun nomme origin, et la branche n'a pas d'upstream). Fixe-le avec: git branch --set-upstream-to=<remote>/$(Gs-Branch)" ""
    exit 0
  }

  $pruned = Gs-PruneOrphans
  if ($pruned) { $msg = "git-sync: checkpoints retires pour des branches disparues ($pruned)." }

  # See Gs-SnapshotTree: one implementation, shared with the ping-pong check
  # that has to agree with it byte for byte.
  $snap = Gs-SnapshotTree
  $tree = $snap.Tree
  if ($snap.Submodules.Count -gt 0) {
    $msg = (@($msg, "git-sync: le contenu des sous-modules n'est pas transporte ($($snap.Submodules -join ' ')) -- committe et pousse-les dans leur propre depot.") | Where-Object { $_ }) -join " "
  }

  $headSha = (git rev-parse HEAD).Trim()
  $headTree = (git rev-parse "HEAD^{tree}").Trim()

  if ($tree -eq $headTree) {
    # See stop-sync.sh: retire our own now-meaningless checkpoint rather than
    # leave a dead git-sync/* branch behind. The lease keeps it from touching a
    # fresh checkpoint the other machine pushed meanwhile.
    $msg = (@($msg, "git-sync: rien a synchroniser.") | Where-Object { $_ }) -join " "
    $ours = Gs-KnownPush $syncBranch
    if ($ours) {
      git push "--force-with-lease=refs/heads/${syncBranch}:${ours}" $remote ":refs/heads/$syncBranch" *> $null
      if ($LASTEXITCODE -eq 0) {
        Gs-ForgetPush $syncBranch
        $msg = "git-sync: travail committe, checkpoint obsolete retire de $syncBranch."
      }
    }
  } else {
    $stat = (git diff --shortstat $headSha $tree 2>$null) -join ""
    $skipCi = if (Gs-Bool "checkpointCi") { "" } else { " [skip ci]" }
    $machine = Gs-Machine
    $body = @"
sync depuis $machine$skipCi

Etat de travail non committe, pousse automatiquement par git-sync.
A integrer avec /git-sync:land, jamais a merger tel quel.

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
      $msg = (@($msg, "git-sync: checkpoint pousse sur $syncBranch ($stat).") | Where-Object { $_ }) -join " "
    } elseif ((Gs-RemoteTree $syncBranch) -eq $tree) {
      # See stop-sync.sh: someone got there first with exactly our content.
      Gs-RememberPush $syncBranch (Gs-RemoteRef $syncBranch)
      Gs-RememberMine $syncBranch $tree
      $msg = (@($msg, "git-sync: checkpoint deja a jour sur $syncBranch.") | Where-Object { $_ }) -join " "
    } elseif ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match "stale info") {
      # See stop-sync.sh: a refused lease has two very different causes, and the
      # remote is the only thing that can tell them apart.
      if (-not (Gs-RemoteRef $syncBranch)) {
        Gs-ForgetPush $syncBranch
        $msg = "git-sync: le checkpoint de $syncBranch a ete integre puis supprime depuis une autre machine. Rien n'a ete pousse cette fois-ci -- verifie avec 'git pull' que ton travail local n'est pas deja dans l'historique, puis relance une session."
      } else {
        $msg = "git-sync: checkpoint refuse -- une autre machine a pousse sur $syncBranch. Rien n'a ete ecrase. Lance /git-sync:land ou resous la divergence a la main."
      }
    } else {
      $msg = "git-sync: push du checkpoint echoue -- voir .git/git-sync-push-error.log"
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
    $context = "git-sync: si quelque chose de durable a ete decide ou construit depuis la derniere mise a jour, invoque la skill git-sync:notes pour rafraichir la section '## Etat courant' de CLAUDE.md. C'est ce fichier qui transporte le pourquoi vers l'autre machine -- le checkpoint ne transporte que le code. Sinon ne touche a rien et n'en parle pas."
  }
}

Gs-Json "Stop" $msg $context
exit 0
