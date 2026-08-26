if (-not ((git rev-parse --is-inside-work-tree) 2>$null)) { exit 0 }

$repoRoot = (git rev-parse --show-toplevel)
$gitignore = Join-Path $repoRoot ".gitignore"
$patternsFile = Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/ignore-patterns.txt"
$marker = "# git-sync managed patterns"

$alreadyMerged = (Test-Path $gitignore) -and (Select-String -Path $gitignore -Pattern ([regex]::Escape($marker)) -Quiet)
if ((Test-Path $patternsFile) -and -not $alreadyMerged) {
  if ((Test-Path $gitignore) -and (Get-Item $gitignore).Length -gt 0) {
    Add-Content -Path $gitignore -Value ""
  }
  Add-Content -Path $gitignore -Value $marker
  Get-Content $patternsFile | Add-Content -Path $gitignore
}

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git commit -m "WIP: auto-sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" *> $null
  if (-not (git remote)) {
    Write-Output "git-sync: no remote configured, committed locally only (not pushed)."
  } else {
    git push *> $null
    if ($LASTEXITCODE -ne 0) {
      Write-Output "git-sync: commit made but push failed (check remote/auth)."
    }
  }
}
