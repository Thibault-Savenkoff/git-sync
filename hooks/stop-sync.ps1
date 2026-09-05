if (-not ((git rev-parse --is-inside-work-tree) 2>$null)) { exit 0 }

# Opt-out: per-repo (git config git-sync.disabled true) or per-session
# (GIT_SYNC_DISABLED=1).
if ((git config --get git-sync.disabled) -eq "true") { exit 0 }
if ($env:GIT_SYNC_DISABLED) { exit 0 }

$repoRoot = (git rev-parse --show-toplevel)
$gitignore = Join-Path $repoRoot ".gitignore"
$patternsFile = Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/ignore-patterns.txt"
$marker = "# git-sync managed patterns"
$msg = ""

$alreadyMerged = (Test-Path $gitignore) -and (Select-String -Path $gitignore -Pattern ([regex]::Escape($marker)) -Quiet)
if ((Test-Path $patternsFile) -and -not $alreadyMerged) {
  if ((Test-Path $gitignore) -and (Get-Item $gitignore).Length -gt 0) {
    Add-Content -Path $gitignore -Value ""
  }
  Add-Content -Path $gitignore -Value $marker
  Get-Content $patternsFile | Add-Content -Path $gitignore
  $msg = "git-sync: added a .gitignore with common ignore patterns to this repo."
}

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  # Default: attributed to a bot identity and left unsigned, so auto-commits
  # stay visibly distinct from the ones you actually wrote. Set
  # `git config git-sync.identity self` to commit as yourself instead.
  $signArgs = @("-c", "commit.gpgsign=false")
  if ((git config --get git-sync.identity) -eq "self") {
    $signArgs = @()
  } else {
    $botName = (git config --get git-sync.botName)
    if (-not $botName) { $botName = "git-sync bot" }
    $botEmail = (git config --get git-sync.botEmail)
    if (-not $botEmail) { $botEmail = "325430966+gitsync-bot@users.noreply.github.com" }
    $env:GIT_AUTHOR_NAME = $botName
    $env:GIT_AUTHOR_EMAIL = $botEmail
    $env:GIT_COMMITTER_NAME = $botName
    $env:GIT_COMMITTER_EMAIL = $botEmail
  }
  $trailer = "Committed automatically by git-sync`nhttps://github.com/Thibault-Savenkoff/git-sync"
  git @signArgs commit -m "WIP: auto-sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -m $trailer *> $null
  if (-not (git remote)) {
    $msg = "$msg git-sync: committed changes locally (no remote configured, not pushed)."
  } else {
    $logFile = Join-Path $repoRoot ".git/git-sync-push-error.log"
    git push *> $logFile
    if ($LASTEXITCODE -eq 0) {
      Remove-Item -Force $logFile -ErrorAction SilentlyContinue
      $msg = "$msg git-sync: committed and pushed changes."
    } else {
      $msg = "$msg git-sync: committed changes but push failed -- see .git/git-sync-push-error.log"
    }
  }
}

$msg = $msg.Trim()
if ($msg) {
  @{ hookSpecificOutput = @{ hookEventName = "Stop"; systemMessage = $msg } } | ConvertTo-Json -Compress
}
