# Bring the other machine's work into this one at session start.
# See hooks/session-start.sh for the reasoning behind each guard.
. (Join-Path $env:CLAUDE_PLUGIN_ROOT "hooks/lib.ps1")

if (-not (Gs-Enabled)) { exit 0 }
if (-not (Gs-HasRemote)) { exit 0 }

if ((Gs-Mode) -ne "checkpoint") { git pull --ff-only *> $null; exit 0 }

$branch = Gs-Branch
if (-not $branch) { exit 0 }
$syncBranch = "git-sync/$branch"

git pull --ff-only *> $null

# The leading "+" is not optional: a checkpoint is force-pushed, so its update
# is never a fast-forward.
git fetch -q origin "+refs/heads/${syncBranch}:refs/git-sync/$syncBranch" *> $null
$ckpt = (git rev-parse -q --verify "refs/git-sync/$syncBranch" 2>$null)
if (-not $ckpt) { exit 0 }
$ckpt = $ckpt.Trim()

Gs-RememberPush $syncBranch $ckpt

$base = Gs-Trailer $ckpt "Git-Sync-Base"
$machine = Gs-Trailer $ckpt "Git-Sync-Machine"
$headSha = (git rev-parse HEAD).Trim()

if ($machine -eq (Gs-Machine)) { exit 0 }
if ((git rev-parse "$ckpt^{tree}").Trim() -eq (git rev-parse "HEAD^{tree}").Trim()) { exit 0 }

if ($base -ne $headSha) {
  Gs-Json "SessionStart" "git-sync: un checkpoint de $machine existe sur $syncBranch mais part d'un autre commit ($base vs $headSha). Rien n'a ete applique -- inspecte-le avec: git diff HEAD refs/git-sync/$syncBranch" ""
  exit 0
}

if ((git status --porcelain) -join "") {
  Gs-Json "SessionStart" "git-sync: un checkpoint de $machine attend sur $syncBranch, mais ce work tree a des modifications locales. Rien n'a ete applique. Compare avec: git diff HEAD refs/git-sync/$syncBranch" ""
  exit 0
}

# Computed before applying: afterwards, files the checkpoint added read as
# untracked and `git diff HEAD` stops mentioning them.
$stat = ((git diff --stat HEAD $ckpt) | Select-Object -Last 20) -join "`n"

git read-tree -u -m HEAD $ckpt *> $null
if ($LASTEXITCODE -ne 0) {
  Gs-Json "SessionStart" "git-sync: application du checkpoint de $machine impossible (conflit avec des fichiers locaux). Rien n'a change." ""
  exit 0
}
git reset -q

Gs-Json "SessionStart" "git-sync: travail de $machine applique depuis $syncBranch (non committe)." @"
git-sync a restaure le travail en cours de la machine $machine. Ces modifications sont dans le work tree, non committees, et ne sont pas de toi :

$stat

Le pourquoi de ces changements est dans la section '## Etat courant' de CLAUDE.md si elle existe. Ne recommence pas ce travail : continue-le.
"@
exit 0
