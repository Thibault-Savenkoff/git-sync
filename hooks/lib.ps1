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

# See lib.sh: git refuses refs/heads/a/b while refs/heads/a exists, so the
# branch name is encoded into a single segment under git-sync/.
function Gs-Encode([string]$Name) { $Name.Replace("%", "%25").Replace("/", "%2F") }
function Gs-Decode([string]$Name) { $Name.Replace("%2F", "/").Replace("%25", "%") }

function Gs-SyncBranch {
  $b = Gs-Branch
  if ([string]::IsNullOrWhiteSpace($b)) { return $null }
  return "git-sync/" + (Gs-Encode $b)
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

function Gs-WorktreeTree {
  $tmp = [System.IO.Path]::GetTempFileName(); Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  try {
    $env:GIT_INDEX_FILE = $tmp
    git read-tree HEAD 2>$null
    $ex = Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/ignore-patterns.txt"
    if (Test-Path $ex) { git -c core.excludesFile="$ex" add -A 2>$null } else { git add -A 2>$null }
    return (git write-tree 2>$null).Trim()
  } finally {
    Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Gs-MineFile { Join-Path (Gs-RepoRoot) ".git/git-sync-mine" }

function Gs-RememberMine([string]$SyncBranch, [string]$Tree) {
  $f = Gs-MineFile
  $lines = @()
  if (Test-Path $f) { $lines = @(Get-Content $f | Where-Object { $_ -notmatch "^$([regex]::Escape($SyncBranch)) " }) }
  $lines += "$SyncBranch $Tree"
  Set-Content -Path $f -Value $lines
}

function Gs-KnownMine([string]$SyncBranch) {
  $f = Gs-MineFile
  if (-not (Test-Path $f)) { return "" }
  foreach ($line in Get-Content $f) {
    if ($line -match "^$([regex]::Escape($SyncBranch)) (.+)$") { return $Matches[1].Trim() }
  }
  return ""
}

function Gs-ForgetPush([string]$SyncBranch) {
  $f = Gs-StateFile
  if (-not (Test-Path $f)) { return }
  $lines = @(Get-Content $f | Where-Object { $_ -notmatch "^$([regex]::Escape($SyncBranch)) " })
  Set-Content -Path $f -Value $lines
}

function Gs-RemoteRef([string]$SyncBranch) {
  $line = (git ls-remote origin "refs/heads/$SyncBranch" 2>$null | Select-Object -First 1)
  if (-not $line) { return "" }
  return ($line -split "\s+")[0]
}

function Gs-Json([string]$Event, [string]$Message, [string]$Context) {
  if ([string]::IsNullOrWhiteSpace($Message) -and [string]::IsNullOrWhiteSpace($Context)) { return }
  $out = @{ hookEventName = $Event }
  if ($Message) { $out.systemMessage = $Message }
  if ($Context) { $out.additionalContext = $Context }
  @{ hookSpecificOutput = $out } | ConvertTo-Json -Compress -Depth 5
}

# Gs-PruneOrphans -- drop checkpoints whose branch no longer exists locally.
# See lib.sh: a rename or a delete otherwise strands one on the remote forever.
function Gs-PruneOrphans {
  $f = Gs-StateFile
  if (-not (Test-Path $f)) { return "" }
  $pruned = @()
  foreach ($line in @(Get-Content $f)) {
    if ($line -notmatch "^(git-sync/\S+) (\S+)") { continue }
    $sb = $Matches[1]; $sha = $Matches[2]
    $name = Gs-Decode ($sb -replace "^git-sync/", "")
    git show-ref --verify --quiet "refs/heads/$name"
    if ($LASTEXITCODE -eq 0) { continue }
    git push "--force-with-lease=refs/heads/${sb}:${sha}" origin ":refs/heads/$sb" *> $null
    if ($LASTEXITCODE -eq 0) { $pruned += $name }
    Gs-ForgetPush $sb
  }
  return ($pruned -join " ")
}
