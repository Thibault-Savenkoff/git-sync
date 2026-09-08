# Shared helpers for the git-sync hooks, PowerShell side.
# Mirrors hooks/lib.sh -- keep the two in step.

function Gs-Config([string]$Name, [string]$Default = "") {
  $v = (git config --get "git-sync.$Name" 2>$null)
  if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
  return $v.Trim()
}

function Gs-Bool([string]$Name, [string]$Default = "false") {
  return (Gs-Config $Name $Default) -eq "true"
}

function Gs-Enabled {
  if (-not ((git rev-parse --is-inside-work-tree 2>$null))) { return $false }
  if (Gs-Bool "disabled") { return $false }
  if ($env:GIT_SYNC_DISABLED) { return $false }
  return $true
}

function Gs-RepoRoot { (git rev-parse --show-toplevel 2>$null) }
function Gs-Branch { (git symbolic-ref --quiet --short HEAD 2>$null) }
function Gs-Mode { Gs-Config "mode" "checkpoint" }
function Gs-Machine { Gs-Config "machine" $env:COMPUTERNAME }
function Gs-HasRemote { -not [string]::IsNullOrWhiteSpace((git remote 2>$null) -join "") }

function Gs-SyncBranch {
  $b = Gs-Branch
  if ([string]::IsNullOrWhiteSpace($b)) { return $null }
  return "git-sync/$b"
}

function Gs-Trailer([string]$Commit, [string]$Key) {
  $body = (git log -1 --format=%B $Commit 2>$null) -join "`n"
  foreach ($line in $body -split "`n") {
    if ($line -match "^$Key\s*:\s*(.+)$") { return $Matches[1].Trim() }
  }
  return ""
}

function Gs-StateFile { Join-Path (Gs-RepoRoot) ".git/git-sync-pushed" }

function Gs-RememberPush([string]$SyncBranch, [string]$Sha) {
  $f = Gs-StateFile
  $lines = @()
  if (Test-Path $f) { $lines = @(Get-Content $f | Where-Object { $_ -notmatch "^$([regex]::Escape($SyncBranch)) " }) }
  $lines += "$SyncBranch $Sha"
  Set-Content -Path $f -Value $lines
}

function Gs-KnownPush([string]$SyncBranch) {
  $f = Gs-StateFile
  if (-not (Test-Path $f)) { return "" }
  foreach ($line in Get-Content $f) {
    if ($line -match "^$([regex]::Escape($SyncBranch)) (.+)$") { return $Matches[1].Trim() }
  }
  return ""
}

function Gs-Json([string]$Event, [string]$Message, [string]$Context) {
  if ([string]::IsNullOrWhiteSpace($Message) -and [string]::IsNullOrWhiteSpace($Context)) { return }
  $out = @{ hookEventName = $Event }
  if ($Message) { $out.systemMessage = $Message }
  if ($Context) { $out.additionalContext = $Context }
  @{ hookSpecificOutput = $out } | ConvertTo-Json -Compress -Depth 5
}
