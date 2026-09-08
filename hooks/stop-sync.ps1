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
  if (-not (Gs-HasRemote)) {
    Gs-Json "Stop" "git-sync: aucun remote configure, checkpoint impossible." ""
    exit 0
  }

  # Snapshot through an index of our own, so the user's staging area is
  # neither read nor disturbed.
  $tmpIndex = [System.IO.Path]::GetTempFileName()
  Remove-Item $tmpIndex -Force -ErrorAction SilentlyContinue
  try {
    $env:GIT_INDEX_FILE = $tmpIndex
    git read-tree HEAD
    # See stop-sync.sh: applied as an extra exclude file for this snapshot only,
    # rather than written into the user's own .gitignore as 1.x did.
    $excludes = Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/ignore-patterns.txt"
    if (Test-Path $excludes) { git -c core.excludesFile="$excludes" add -A } else { git add -A }
    $tree = (git write-tree).Trim()
  } finally {
    Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue
    Remove-Item $tmpIndex -Force -ErrorAction SilentlyContinue
  }

  $headSha = (git rev-parse HEAD).Trim()
  $headTree = (git rev-parse "HEAD^{tree}").Trim()

  if ($tree -eq $headTree) {
    $msg = "git-sync: rien a synchroniser."
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
    git push "--force-with-lease=refs/heads/${syncBranch}:${lease}" origin "${ckpt}:refs/heads/$syncBranch" *> $log
    if ($LASTEXITCODE -eq 0) {
      Remove-Item -Force $log -ErrorAction SilentlyContinue
      Gs-RememberPush $syncBranch $ckpt
      $msg = "git-sync: checkpoint pousse sur $syncBranch ($stat)."
    } elseif ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match "stale info") {
      $msg = "git-sync: checkpoint refuse -- une autre machine a pousse sur $syncBranch. Rien n'a ete ecrase. Lance /git-sync:land ou resous la divergence a la main."
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
