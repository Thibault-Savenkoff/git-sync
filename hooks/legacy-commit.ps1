# Pre-2.0 behaviour: commit onto the current branch and push.
# Dot-sourced by stop-sync.ps1 when `git config git-sync.mode commit` is set.
git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  $signArgs = @("-c", "commit.gpgsign=false")
  if ((Gs-Config "identity" "bot") -eq "self") {
    $signArgs = @()
  } else {
    $env:GIT_AUTHOR_NAME = Gs-Config "botName" "git-sync bot"
    $env:GIT_AUTHOR_EMAIL = Gs-Config "botEmail" "325430966+gitsync-bot@users.noreply.github.com"
    $env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME
    $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL
  }
  $trailer = "Committed automatically by git-sync`nhttps://github.com/Thibault-Savenkoff/git-sync"
  git @signArgs commit -m "WIP: auto-sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -m $trailer *> $null
  if (-not (Gs-HasRemote)) {
    $msg = "git-sync: committed locally (no remote configured)."
  } else {
    $logFile = Join-Path $repoRoot ".git/git-sync-push-error.log"
    git push *> $logFile
    if ($LASTEXITCODE -eq 0) {
      Remove-Item -Force $logFile -ErrorAction SilentlyContinue
      $msg = "git-sync: committed and pushed."
    } else {
      $msg = "git-sync: committed but the push failed -- see .git/git-sync-push-error.log"
    }
  }
}
