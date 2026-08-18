param(
    [string]$TestRoot = "C:\gftest",
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [switch]$Force,
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# LOCAL TEST BOX - one-time setup of an ISOLATED Plutonium storage tree.
#
# WHY A SEPARATE TREE. Plutonium resolves its whole storage tree from
# %LOCALAPPDATA%, so pointing that at a different directory before launch gives
# the test server its own cfg, its own logs, and its own players\ profile. That
# is the same lever the VPS uses (its GF-GameServer task pins LOCALAPPDATA to
# Administrator's profile before running the bat), so this is a documented
# Plutonium behaviour, not a trick.
#
# What isolation actually buys, in order of how much it matters here:
#   1. players\  - the archived config_mp.cfg and the stats profile. The shared
#      dedicated.cfg ships modStats 0, meaning the server reads and writes your
#      REAL Black Ops profile. A test box running 5x XP, bot farming and the
#      _gf_fun account editors has no business anywhere near that file.
#   2. logs\     - a test run's GF_* diagnostics are not interleaved with the
#      ones from whatever else you were doing.
#   3. dedicated.cfg - the panel's save button on the test box cannot rewrite
#      the cfg you keep as the VPS mirror.
#
# WHAT IS SHARED, AND WHY IT IS SAFE. Everything large and read-only is a
# DIRECTORY JUNCTION back to the real install: bin, games, launcher, the zone
# fastfiles, the demonware cache. Junctions need no admin rights and no disk,
# and none of it is written during normal play.
#
# THE MOD FOLDER IS A JUNCTION TO THIS REPO, which is the point: you edit GSC in
# the repo and the test server loads exactly those files, with no copy step.
#
#   Usage:  .\tools\local\setup_test_box.ps1              create it
#           .\tools\local\setup_test_box.ps1 -Force       re-link an existing one
#           .\tools\local\setup_test_box.ps1 -Remove      tear it down
#           .\tools\local\setup_test_box.ps1 -TestRoot D:\gftest
# ---------------------------------------------------------------------------

$RealLocal = $env:LOCALAPPDATA
$RealPluto = Join-Path $RealLocal "Plutonium"
$TestPluto = Join-Path $TestRoot  "Plutonium"
$TestT5    = Join-Path $TestPluto "storage\t5"

function Ok($m)   { Write-Host "  [ ok ] $m" -ForegroundColor Green }
function Info($m) { Write-Host "  [ .. ] $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  GF LOCAL TEST BOX - isolated storage tree" -ForegroundColor White
Write-Host "  real : $RealPluto" -ForegroundColor DarkGray
Write-Host "  test : $TestPluto" -ForegroundColor DarkGray
Write-Host ""

# --- teardown ---------------------------------------------------------------
if ($Remove) {
    if (-not (Test-Path -LiteralPath $TestRoot)) { Ok "nothing to remove"; exit 0 }
    # Remove junctions FIRST and individually. A recursive delete over a junction
    # can follow it into the target, which here would eat the real install and
    # this repo. Deleting the reparse point itself never touches the target.
    Get-ChildItem -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            Info "unlink $($_.FullName)"
            [void](cmd /c rmdir "`"$($_.FullName)`"" 2>&1)
        }
    Remove-Item -LiteralPath $TestRoot -Recurse -Force
    Ok "removed $TestRoot"
    exit 0
}

# --- preflight --------------------------------------------------------------
if (-not (Test-Path -LiteralPath $RealPluto)) { throw "No Plutonium install at $RealPluto" }
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "maps\mp\gametypes\gf.gsc"))) {
    throw "RepoRoot does not look like the mod: $RepoRoot"
}
if ((Test-Path -LiteralPath $TestRoot) -and -not $Force) {
    Warn "$TestRoot already exists. Re-run with -Force to re-link, or -Remove to tear it down."
    exit 1
}

# Junction helper. Idempotent: an existing correct link is left alone, an
# existing wrong one is replaced, a real directory in the way is refused rather
# than deleted (it may hold something you meant to keep).
function New-Junction($Link, $Target) {
    if (-not (Test-Path -LiteralPath $Target)) { Warn "skip (no target): $Target"; return }
    $parent = Split-Path -Parent $Link
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (Test-Path -LiteralPath $Link) {
        $item = Get-Item -LiteralPath $Link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [void](cmd /c rmdir "`"$Link`"" 2>&1)
        } else {
            Warn "not a junction, leaving alone: $Link"
            return
        }
    }
    $out = cmd /c mklink /J "`"$Link`"" "`"$Target`"" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "mklink failed for $Link -> $Target : $out" }
    Ok "link  $(Split-Path -Leaf $Link)  ->  $Target"
}

# --- shared, read-only: junction back to the real install -------------------
Write-Host "  Shared (junctions to the real install):" -ForegroundColor Cyan
foreach ($d in @("bin", "games", "launcher")) {
    New-Junction (Join-Path $TestPluto $d) (Join-Path $RealPluto $d)
}

# --- the RENAMED bootstrapper: what lets you play while the server runs -----
# Plutonium refuses to start a game CLIENT while a process named
# plutonium-bootstrapper-win32.exe is already running, and a dedicated server is
# that same executable. The guard is one-directional, which is what makes it so
# easy to misdiagnose: an already-running client happily tolerates a server
# started afterwards, so testing in that order shows no problem at all. Start
# the server first and the launcher dies instantly (exit 11, a 0-byte
# console.log, and nothing else to go on).
#
# The guard keys on the PROCESS NAME, so running the server from a renamed copy
# defeats it outright. Verified live: with the server up as gfserver.exe the
# game launched normally, and putting it back under the stock name blocked the
# launcher again in the very next attempt.
#
# It has to be a real COPY in a real directory - bin\ is a junction, so writing
# a renamed exe "into" it would land in the real install. The DLLs must sit
# beside it (an exe loads its dependencies from its own directory first), which
# is why the whole bin is copied rather than just the one file. ~54MB.
Write-Host ""
Write-Host "  Renamed bootstrapper (lets you play while the server runs):" -ForegroundColor Cyan
$binTest = Join-Path $TestPluto "bintest"
$srvExe  = Join-Path $binTest "gfserver.exe"
$realBin = Join-Path $RealPluto "bin"
if ($Force -and (Test-Path -LiteralPath $binTest)) { Remove-Item -LiteralPath $binTest -Recurse -Force }
if (-not (Test-Path -LiteralPath $srvExe)) {
    New-Item -ItemType Directory -Path $binTest -Force | Out-Null
    Copy-Item -Path (Join-Path $realBin "*") -Destination $binTest -Recurse -Force
    $stock = Join-Path $binTest "plutonium-bootstrapper-win32.exe"
    if (-not (Test-Path -LiteralPath $stock)) { throw "bootstrapper missing from the bin copy at $binTest" }
    Rename-Item -LiteralPath $stock -NewName "gfserver.exe" -Force
    Ok "copy  bin -> bintest, bootstrapper renamed to gfserver.exe"
} else {
    Info "bintest\gfserver.exe already present, left alone (-Force re-copies)"
}
# A stock-named bootstrapper left in the copy would be picked up by nothing, but
# its presence means the rename silently did not happen on a re-copy.
if (Test-Path -LiteralPath (Join-Path $binTest "plutonium-bootstrapper-win32.exe")) {
    Warn "bintest still contains a stock-named bootstrapper - re-run with -Force"
}
New-Junction (Join-Path $TestPluto "storage\demonware") (Join-Path $RealPluto "storage\demonware")
foreach ($d in @("zone", "raw", "plutonium")) {
    New-Junction (Join-Path $TestT5 $d) (Join-Path $RealPluto "storage\t5\$d")
}

# --- the mod folder IS this repo -------------------------------------------
Write-Host ""
Write-Host "  Mod folder:" -ForegroundColor Cyan
New-Junction (Join-Path $TestT5 "mods\mp_gunfight") $RepoRoot

# --- private to the test box ------------------------------------------------
Write-Host ""
Write-Host "  Private to the test box (real directories):" -ForegroundColor Cyan
foreach ($d in @("players", "logs", "demos")) {
    $p = Join-Path $TestT5 $d
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    Ok "dir   $d"
}

# Plutonium's own top-level files. info.json is the updater's revision marker;
# copy it so the test tree does not look like a fresh install that needs a full
# download. config.json is deliberately NOT copied - it carries the launcher's
# account token, and a dedicated server authenticates with a server KEY instead.
foreach ($f in @("info.json")) {
    $src = Join-Path $RealPluto $f
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $TestPluto $f) -Force; Ok "copy  $f" }
}

# dedicated.cfg: seed from the real one so the test box starts as a faithful
# VPS mirror, then local_test.cfg overrides only what must differ. Never
# overwrite an existing one - it is yours to edit from here on.
$realCfg = Join-Path $RealPluto "storage\t5\dedicated.cfg"
$testCfg = Join-Path $TestT5 "dedicated.cfg"
if (-not (Test-Path -LiteralPath $testCfg)) {
    if (Test-Path -LiteralPath $realCfg) {
        Copy-Item -LiteralPath $realCfg -Destination $testCfg -Force
        Ok "copy  dedicated.cfg  (seeded from the real one)"
    } else {
        $ex = Join-Path $RepoRoot "server\dedicated.cfg.example"
        if (Test-Path -LiteralPath $ex) { Copy-Item -LiteralPath $ex -Destination $testCfg -Force; Ok "copy  dedicated.cfg  (from the repo example - fill in rcon_password)" }
        else { Warn "no dedicated.cfg to seed from - put one at $testCfg" }
    }
} else { Info "dedicated.cfg already present, left alone" }

# local_test.cfg: the override layer.
$testOverride = Join-Path $TestT5 "local_test.cfg"
if (-not (Test-Path -LiteralPath $testOverride)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "local_test.cfg.example") -Destination $testOverride -Force
    Ok "copy  local_test.cfg  (the override layer)"
} else { Info "local_test.cfg already present, left alone" }

# bots.txt drives bot names/clantags and is read at process start.
$realBots = Join-Path $RealPluto "storage\t5\bots.txt"
$testBots = Join-Path $TestT5 "bots.txt"
if ((Test-Path -LiteralPath $realBots) -and -not (Test-Path -LiteralPath $testBots)) {
    Copy-Item -LiteralPath $realBots -Destination $testBots -Force; Ok "copy  bots.txt"
}

Write-Host ""
Write-Host ("-" * 66) -ForegroundColor DarkCyan
Ok "test box ready at $TestRoot"
Write-Host ""
Write-Host "  Next:" -ForegroundColor White
Write-Host "    1. Put a server key in tools\local\local.env.bat  (see local.env.bat.example)." -ForegroundColor DarkGray
Write-Host "       A dedicated server needs one to finish Demonware auth - without it it" -ForegroundColor DarkGray
Write-Host "       sits at 'Early out of maprotate, waiting for WAD!' forever." -ForegroundColor DarkGray
Write-Host "    2. tools\local\start_local_server.bat" -ForegroundColor DarkGray
Write-Host "    3. Join from your client:  connect 127.0.0.1:28965" -ForegroundColor DarkGray
Write-Host ""
exit 0
