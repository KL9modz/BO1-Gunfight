# Publish this box's non-reproducible state to the PRIVATE backup repo, daily (task GF-Backup).
#
#   .\backup_box_state.ps1 -GitDir C:\gfbackup\BO1-Server-Backup
#   .\backup_box_state.ps1 -GitDir ... -WhatIf      # collect + report, publish nothing
#
# ⚠ THIS SCRIPT OWNS PUBLISHING, NOT COLLECTING. What counts as box-local state is decided in ONE
# place - tools\carry.ps1, whose authority is .gitignore and which carries a per-item restore note
# plus the deliberate exclusions (security_state.json must NOT travel: it is the security watcher's
# learned baseline, and a copied one produces false alarms on the new box forever). This script
# shells out to it. An earlier version of this file kept a parallel list and drifted immediately -
# it collected the very files carry.ps1 refuses on purpose, and missed bots.txt,
# gamestats.local.json and players.local.json entirely. Two lists cannot both be right; there is
# one, and it is carry.ps1.
#
# WHAT LANDS IN THE REPO: a mirrored PLAINTEXT tree under state\ (owner's decision, 2026-08-18),
# because git then stores each append-only day-file once and the tree stays diffable and restorable
# file by file - where an opaque archive would be a fresh incompressible blob on every run.
#
# ⚠ The repo therefore holds LIVE CREDENTIALS (rcon + g_password, panel passwords, Discord webhook
# URLs) and PLAYER PII (IPs + GUIDs). The only thing protecting them is the repo staying PRIVATE,
# and git history is permanent: if it is ever exposed, deleting files does not undo it - rotate
# everything MANIFEST.txt marks SECRET, and the player data cannot be recalled. "Is this repo still
# private" is a standing check, not a setup step.
#
# ⚠ For a bundle that leaves the box by any other route (scp to a laptop, USB), use
# `carry.ps1 -Zip` and follow its own instructions. This script deliberately has no encryption of
# its own: a second crypto implementation is a liability, and the repo path is plaintext anyway.
[CmdletBinding()]
param(
    [string] $GitDir          = 'C:\gfbackup\BO1-Server-Backup',
    [switch] $IncludeGeoCache,  # PII, and it regenerates on its own - carry.ps1's default is off
    [switch] $WhatIf
)
$ErrorActionPreference = 'Stop'

$carry = Join-Path $PSScriptRoot 'carry.ps1'
if (-not (Test-Path $carry)) { throw "carry.ps1 not found next to this script: $carry" }

# ── guards ─────────────────────────────────────────────────────────────────────────────────────
# This publishes credentials and player PII to a git remote, and a push cannot be recalled. The
# PUBLIC BO1-Gunfight clone lives on this same box, so a mistyped -GitDir is a plausible route to
# publishing all of it. Fail closed, loudly, and never guess.
function Assert-BackupRepo($gitDir) {
    if (-not (Test-Path $gitDir)) { throw "backup repo clone not found: $gitDir" }
    if (-not (Test-Path (Join-Path $gitDir '.gf-backup-repo'))) {
        throw "refusing to publish: $gitDir has no .gf-backup-repo marker. That marker is what distinguishes the private backup clone from every other git tree on this box."
    }
    $r = (& git -C $gitDir remote get-url origin 2>$null)
    if (-not $r) { throw "no origin remote in $gitDir" }
    if ($r -match 'BO1-Gunfight(\.git)?$') {
        throw "refusing to publish: origin of $gitDir is the PUBLIC mod repo ($r)"
    }
    return $r
}
$remote = Assert-BackupRepo $GitDir

# ── collect (carry.ps1 owns the list) ──────────────────────────────────────────────────────────
$outRoot = Join-Path $env:TEMP ("gf_backup_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
# -SkipHitchBaseline: that file is ~6MB re-extracted from the live game log every run, i.e. 93%
# of every commit, to carry a derived diagnostic. Migration still gets it (carry.ps1's default);
# the daily push does not need it.
$carryArgs = @('-OutRoot', $outRoot, '-SkipHitchBaseline')
if ($IncludeGeoCache) { $carryArgs += '-IncludeGeoCache' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $carry @carryArgs | Out-Null
if ($LASTEXITCODE -ne 0) { throw "carry.ps1 failed (exit $LASTEXITCODE)" }

# carry.ps1 writes into a TIMESTAMPED subdir (carry-<stamp>). Mirror its CONTENTS, not the stamped
# folder itself - otherwise every run would add a whole new directory and the repo would become a
# pile of snapshots instead of one tree whose history IS the snapshots.
$made = @(Get-ChildItem $outRoot -Directory | Sort-Object Name -Descending)
if ($made.Count -eq 0) { throw "carry.ps1 produced no output under $outRoot" }
$staging = $made[0].FullName

$files = @(Get-ChildItem $staging -Recurse -File)
$kb = [math]::Round((($files | Measure-Object Length -Sum).Sum / 1KB), 0)

if ($WhatIf) {
    Write-Host "WhatIf: collected $($files.Count) file(s), $kb KB at $staging"
    Write-Host "        would mirror into $GitDir\state and push to $remote"
    return
}

# ── publish ────────────────────────────────────────────────────────────────────────────────────
# MIRROR, not merge: a file that stops being collected must leave the tip too, or the tree becomes
# a museum of paths that no longer exist. History still holds it, which is the point of using git.
$stateDir = Join-Path $GitDir 'state'
$null = robocopy $staging $stateDir /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1
if ($LASTEXITCODE -ge 8) { throw "robocopy failed mirroring into $stateDir (exit $LASTEXITCODE)" }
Remove-Item $outRoot -Recurse -Force -ErrorAction SilentlyContinue

if (-not (Test-Path (Join-Path $GitDir 'README.md'))) {
    @(
        '# BO1-Gunfight box state'
        ''
        'Everything the mod repo cannot rebuild: connect history, combat stats, Discord links,'
        'panel prefs, bot names, box config, scheduled task definitions, and the live credentials'
        'the server runs on. Written daily by `tools/backup_box_state.ps1` on the game server and'
        'collected by `tools/carry.ps1`, which is the single source of truth for what is box-local.'
        ''
        '**This repo must stay private.** It holds live credentials and player IPs/GUIDs in'
        'plaintext. If it is ever exposed, rotate everything `state/MANIFEST.txt` marks SECRET;'
        'the player data cannot be recalled.'
        ''
        'Every file carries a restore note in `state/MANIFEST.txt`. Pair it with `docs/MIGRATION.md`'
        'in the mod repo, which owns the order to do things in.'
        ''
        '`mod.ff` and `mp_gunfight.iwd` are deliberately absent: they live on the mod repo'
        '`release` branch (`git checkout origin/release -- mod.ff mp_gunfight.iwd`).'
    ) -join "`r`n" | Set-Content -Path (Join-Path $GitDir 'README.md') -Encoding UTF8
}

& git -C $GitDir add -A | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
& git -C $GitDir -c user.name='GF-Backup' -c user.email='gf-backup@localhost' commit -q -m "box state $stamp" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "no changes since the last backup ($($files.Count) files, $kb KB) - nothing to push"
    return
}
& git -C $GitDir push -q origin HEAD 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    # Not fatal to the DATA: the commit is local and the next run pushes it. Say that plainly
    # rather than implying the backup itself failed.
    throw "git push FAILED (deploy key revoked, or no network) - the commit is local and the next run will push it"
}
Write-Host ("published {0} file(s), {1} KB to {2} (commit {3})" -f `
    $files.Count, $kb, $remote, (& git -C $GitDir rev-list --count HEAD).Trim())
