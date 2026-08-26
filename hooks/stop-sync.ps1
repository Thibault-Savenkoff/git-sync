if (-not ((git rev-parse --is-inside-work-tree) 2>$null)) { exit 0 }

$gitDir = (git rev-parse --git-dir)
$excludeFile = Join-Path $gitDir "info/exclude"
$patternsFile = Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/ignore-patterns.txt"
$marker = "# git-sync managed patterns"

$alreadyMerged = (Test-Path $excludeFile) -and (Select-String -Path $excludeFile -Pattern ([regex]::Escape($marker)) -Quiet)
if ((Test-Path $patternsFile) -and -not $alreadyMerged) {
  New-Item -ItemType Directory -Force -Path (Split-Path $excludeFile) | Out-Null
  Add-Content -Path $excludeFile -Value ""
  Add-Content -Path $excludeFile -Value $marker
  Get-Content $patternsFile | Add-Content -Path $excludeFile
}

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git commit -m "WIP: auto-sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" *> $null
  git push *> $null
}
