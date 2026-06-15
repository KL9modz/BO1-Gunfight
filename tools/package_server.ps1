param(
    [Parameter(Position = 0)][string]$Version = ("0.0.0-dev." + (Get-Date -Format "yyyyMMdd")),
    [string]$GameRoot = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740",
    [string]$ModName = "mp_gunfight",
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$SkipBuild,
    [switch]$IncludeRconTool,
    [switch]$SanitizeConfig
)

$ErrorActionPreference = "Stop"

# Build a PRIVATE VPS deployment bundle (NOT for public release):
#   t5/
#     mods/mp_gunfight/   full mod (mod.ff + mod.csv + ALL gameplay GSC,
#                         including _gf_bridge for RCON and _bot - the server
#                         keeps the dev tools; bare-bones is only the player zip)
#     dedicated.cfg       your server config (CONTAINS rcon_password unless -SanitizeConfig)
#     gamesettings/gf.cfg production gametype cfg (spawn recorder disabled)
#     tools/rcon/         optional web RCON panel (-IncludeRconTool)
#   DEPLOY.txt            where each file goes on the VPS + required edits
#
# Output: tools\dist\mp_gunfight-server-<version>.zip  (gitignored)
#
# Usage:
#   tools\package_server.ps1                       # snapshot bundle (config as-is)
#   tools\package_server.ps1 1.0.0                 # versioned bundle
#   tools\package_server.ps1 1.0.0 -SanitizeConfig # blank rcon_password in the copy
#   tools\package_server.ps1 -IncludeRconTool      # also bundle the web RCON panel

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Copy-Into {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -Force -LiteralPath $Source -Destination $Destination
}

# -- Resolve paths ------------------------------------------------------------
$ModRoot = $WorkspaceRoot                                   # repo root IS the mod folder
$T5Root = (Resolve-Path (Join-Path $WorkspaceRoot "..\..")).Path  # storage\t5
$ModFf = Join-Path $ModRoot "mod.ff"
$ModCsv = Join-Path $ModRoot "mod.csv"
$DedCfg = Join-Path $T5Root "dedicated.cfg"
$DistDir = Join-Path $WorkspaceRoot "tools\dist"
$StageRoot = Join-Path $DistDir "server-stage"
$ZipPath = Join-Path $DistDir "$ModName-server-$Version.zip"

Write-Host "Packaging $ModName SERVER bundle"
Write-Host "Version: $Version"
Write-Host "Mod:     $ModRoot"
Write-Host "T5 root: $T5Root"

# -- Build mod.ff -------------------------------------------------------------
if (-not $SkipBuild) {
    $buildScript = Join-Path $PSScriptRoot "build_ff.ps1"
    if (!(Test-Path -LiteralPath $buildScript)) { throw "build_ff.ps1 not found: $buildScript" }
    Write-Host ""
    Write-Host "Building mod.ff ..."
    & $buildScript -GameRoot $GameRoot -ModName $ModName
    if ($LASTEXITCODE -ne 0) { throw "build_ff.ps1 failed (exit $LASTEXITCODE)" }
}
if (!(Test-Path -LiteralPath $ModFf)) { throw "mod.ff not found (build it first): $ModFf" }

# -- Fresh staging ------------------------------------------------------------
if (Test-Path -LiteralPath $StageRoot) { Remove-Item -Recurse -Force -LiteralPath $StageRoot }
$StageMod = Join-Path $StageRoot "t5\mods\$ModName"
New-Item -ItemType Directory -Force -Path $StageMod | Out-Null

# -- Full mod: mod.ff + mod.csv + every .gsc under maps\ (dev tools INCLUDED) --
Copy-Into $ModFf (Join-Path $StageMod "mod.ff")
Copy-Into $ModCsv (Join-Path $StageMod "mod.csv")
$gsc = Get-ChildItem -Recurse -File -LiteralPath (Join-Path $ModRoot "maps") -Filter *.gsc
foreach ($f in $gsc) {
    $rel = $f.FullName.Substring($ModRoot.Length).TrimStart('\', '/')
    Copy-Into $f.FullName (Join-Path $StageMod $rel)
}
Write-Host "  + mod.ff, mod.csv, $($gsc.Count) GSC file(s) (full set, dev tools included)"

# -- dedicated.cfg (optionally blank the rcon_password) -----------------------
$cfgIncluded = $false
$cfgSanitized = $false
if (Test-Path -LiteralPath $DedCfg) {
    $cfgContent = [System.IO.File]::ReadAllText($DedCfg)
    if ($SanitizeConfig) {
        $cfgContent = [regex]::Replace($cfgContent, '(?m)^(\s*set\s+rcon_password\s+)".*?"', '$1"CHANGEME"')
        $cfgSanitized = $true
    }
    [System.IO.File]::WriteAllText((Join-Path $StageRoot "t5\dedicated.cfg"), $cfgContent, $Utf8NoBom)
    $cfgIncluded = $true
    $sanNote = ""
    if ($cfgSanitized) { $sanNote = " (rcon_password blanked)" }
    Write-Host "  + dedicated.cfg$sanNote"
}
else {
    Write-Warning "dedicated.cfg not found at $DedCfg - bundle will not include it."
}

# No gamesettings/gf.cfg: its only purpose was the dev spawn recorder, which is
# off by default (gf_debug_spawns unset -> 0). Production needs no gametype cfg.

# -- Optional web RCON panel --------------------------------------------------
if ($IncludeRconTool) {
    $rconSrc = Join-Path $WorkspaceRoot "tools\rcon"
    if (Test-Path -LiteralPath $rconSrc) {
        $rconFiles = Get-ChildItem -Recurse -File -LiteralPath $rconSrc | Where-Object { $_.FullName -notmatch '\\node_modules\\' }
        foreach ($f in $rconFiles) {
            $rel = $f.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/')
            Copy-Into $f.FullName (Join-Path $StageRoot $rel)
        }
        Write-Host "  + tools/rcon ($($rconFiles.Count) file(s); run 'npm install' on the host)"
    }
    else { Write-Warning "tools\rcon not found; skipping RCON tool." }
}

# -- DEPLOY.txt ---------------------------------------------------------------
$secretWarn = ""
if ($cfgIncluded -and -not $cfgSanitized) {
    $secretWarn = "This zip contains dedicated.cfg WITH your live rcon_password. Keep it private."
}
$rconLine = ""
if ($IncludeRconTool) {
    $rconLine = "  tools\rcon\             -> web RCON panel (Node.js; run 'npm install' then start.bat/node server.js)"
}
$deploy = @"
mp_gunfight - VPS SERVER deployment bundle
Version: $Version

>>> PRIVATE BUNDLE - DO NOT upload to a public GitHub Release. <<<
$secretWarn

WHERE FILES GO (relative to your Plutonium T5 storage dir):
  t5\mods\$ModName\      -> the mod (server runs the gametype from here)
  t5\dedicated.cfg       -> server config
$rconLine
Extract this zip so the 't5' folder lands inside your Plutonium 'storage' directory.

EDIT dedicated.cfg FOR THE VPS BEFORE GOING LIVE:
  1. rcon_password  - set a NEW strong password (rotate the bundled one).
  2. rconWhitelistAdd lines - the bundled IPs are a home LAN. Set them to the IP
     of wherever your RCON tool runs, OR remove them all to allow loopback + any.
  3. party_minplayers "2"   - "1" is only for solo testing.
  4. g_log "logs/games_mp.log" - use a forward slash on a Linux VPS.

REMEMBER: Plutonium's T5 client cannot download mods from a server. Every player
must install the player package locally to join. This bundle is the SERVER side.

Base server files (Black Ops 1 game files + Plutonium server binaries) are
obtained ON the VPS per the Plutonium docs - they are NOT in this bundle.
"@
[System.IO.File]::WriteAllText((Join-Path $StageRoot "DEPLOY.txt"), $deploy, $Utf8NoBom)

# -- Zip ----------------------------------------------------------------------
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -Force -LiteralPath $ZipPath }
Compress-Archive -Path (Join-Path $StageRoot "*") -DestinationPath $ZipPath -Force

$zip = Get-Item -LiteralPath $ZipPath
Write-Host ""
Write-Host "Zip:    $($zip.FullName) ($([math]::Round($zip.Length / 1KB, 1)) KB)"
Write-Host "Stage:  $StageRoot  (left for inspection)"
if ($cfgIncluded -and -not $cfgSanitized) {
    Write-Host ""
    Write-Host "*** SECURITY: this bundle contains dedicated.cfg WITH your rcon_password. ***" -ForegroundColor Yellow
    Write-Host "*** Keep it private; never attach it to a public GitHub Release.          ***" -ForegroundColor Yellow
    Write-Host "*** Re-run with -SanitizeConfig to produce a password-blanked copy.       ***" -ForegroundColor Yellow
}
