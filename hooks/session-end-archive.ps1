# Archive the session transcript on SessionEnd. See session-end-archive.sh for
# why this exists and why the archive stays outside the work tree.
if ((git config --get git-sync.archive) -ne "true") { exit 0 }
if ($env:GIT_SYNC_DISABLED) { exit 0 }

$input_json = [Console]::In.ReadToEnd()
try { $payload = $input_json | ConvertFrom-Json } catch { exit 0 }
$transcript = $payload.transcript_path
if (-not $transcript -or -not (Test-Path $transcript)) { exit 0 }

$dest = Join-Path $env:USERPROFILE ".claude/git-sync-sessions"
New-Item -ItemType Directory -Path $dest -Force | Out-Null

$root = (git rev-parse --show-toplevel) 2>$null
$slug = if ($root) { Split-Path $root -Leaf } else { "no-repo" }
$name = "{0}-{1}-{2}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $slug, (Split-Path $transcript -Leaf)
Copy-Item $transcript (Join-Path $dest $name)

# ponytail: 30-day window, plain mtime prune.
Get-ChildItem $dest -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
  Remove-Item -Force -ErrorAction SilentlyContinue

@{ hookSpecificOutput = @{
    hookEventName = "SessionEnd"
    systemMessage = "git-sync: session transcript archived to ~/.claude/git-sync-sessions (local only)."
} } | ConvertTo-Json -Compress
