param(
    [Parameter(Position = 0)][string]$Version = ("0.0.0-dev." + (Get-Date -Format "yyyyMMdd")),
    [string]$GameRoot = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740",
    [string]$ModName = "mp_gunfight",
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$SkipBuild,
    [switch]$Publish
)

$ErrorActionPreference = "Stop"

# Produce a clean, player-ready release zip of the mod:
#   - rebuilds mod.ff (unless -SkipBuild)
#   - stages mod.ff + gameplay GSC + mod.csv into a mp_gunfight\ folder
#   - removes the dev tools: deletes _bot/_gf_debug/_gf_bridge files and strips
#     their wiring via the "// #release-strip-begin / -end" markers in source
#   - generates a player INSTALL README
#   - zips to tools\dist\mp_gunfight-<version>.zip
#   - with -Publish, creates a GitHub Release for tag <version> via gh
#
# Usage:
#   tools\package_release.ps1                 # snapshot zip, no publish
#   tools\package_release.ps1 1.0.0           # versioned zip, no publish
#   tools\package_release.ps1 1.0.0 -Publish  # build, zip, and gh release create
#   tools\package_release.ps1 -SkipBuild      # reuse the existing mod.ff

# Dev-only files excluded from the release (forward-slash, repo-relative).
$DevFiles = @(
    "maps/mp/gametypes/_bot.gsc",
    "maps/mp/bots/_bot_loadout.gsc",
    "maps/mp/bots/_bot_script.gsc",
    "maps/mp/bots/_bot_utility.gsc",
    "maps/mp/gametypes/_gf_debug.gsc",
    "maps/mp/gametypes/_gf_bridge.gsc"
)

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Strip-ReleaseMarkers {
    param([Parameter(Mandatory = $true)][string]$Content)

    # Remove everything from a line containing #release-strip-begin through the
    # next line containing #release-strip-end (inclusive of both marker lines
    # and the trailing newline).
    $pattern = '(?ms)^[^\r\n]*#release-strip-begin.*?#release-strip-end[^\r\n]*\r?\n?'
    return [regex]::Replace($Content, $pattern, "")
}

function Copy-GscStripped {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $content = [System.IO.File]::ReadAllText($Source)
    if ($content -match "#release-strip-begin") {
        $content = Strip-ReleaseMarkers $content
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    [System.IO.File]::WriteAllText($Destination, $content, $Utf8NoBom)
}

# -- Resolve paths ------------------------------------------------------------
$ModRoot = $WorkspaceRoot   # repo root IS the mod folder (tools\ lives under it)
$ModFf = Join-Path $ModRoot "mod.ff"
$ModCsv = Join-Path $ModRoot "mod.csv"
$DistDir = Join-Path $WorkspaceRoot "tools\dist"
$StageRoot = Join-Path $DistDir "stage"
$StageMod = Join-Path $StageRoot $ModName
$ZipPath = Join-Path $DistDir "$ModName-$Version.zip"

Write-Host "Packaging $ModName release"
Write-Host "Version: $Version"
Write-Host "Mod:     $ModRoot"

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

# -- Fresh staging dir --------------------------------------------------------
if (Test-Path -LiteralPath $StageRoot) { Remove-Item -Recurse -Force -LiteralPath $StageRoot }
New-Item -ItemType Directory -Force -Path $StageMod | Out-Null

# -- mod.ff (binary copy) -----------------------------------------------------
Copy-Item -Force -LiteralPath $ModFf -Destination (Join-Path $StageMod "mod.ff")

# -- Gameplay GSC (every .gsc under maps\ minus the dev files; strip markers) --
$gscFiles = Get-ChildItem -Recurse -File -LiteralPath (Join-Path $ModRoot "maps") -Filter *.gsc
$includedGsc = 0
foreach ($file in $gscFiles) {
    $rel = $file.FullName.Substring($ModRoot.Length).TrimStart('\', '/').Replace('\', '/')
    if ($DevFiles -contains $rel) { continue }
    Copy-GscStripped $file.FullName (Join-Path $StageMod ($rel -replace '/', '\'))
    $includedGsc++
    Write-Host "  + $rel"
}

# -- mod.csv (drop dev rawfile lines) -----------------------------------------
$csvLines = Get-Content -LiteralPath $ModCsv
$keptCsv = foreach ($line in $csvLines) {
    $norm = $line.Replace('\', '/')
    $isDev = $false
    foreach ($dev in $DevFiles) { if ($norm -match [regex]::Escape($dev)) { $isDev = $true; break } }
    if (-not $isDev) { $line }
}
[System.IO.File]::WriteAllLines((Join-Path $StageMod "mod.csv"), $keptCsv, $Utf8NoBom)

# -- Player INSTALL README ----------------------------------------------------
$readme = @"
mp_gunfight - Gunfight gametype for Call of Duty: Black Ops 1 (Plutonium T5)
Version: $Version

IMPORTANT: Plutonium's T5 client cannot download mods from a server. EVERY
player who wants to play - and the server host - must install these files
locally. Joining a server running this mod without it installed means missing
HUD, blank text, and missing effects.

INSTALL
  1. Open your Plutonium storage mods folder:
       %localappdata%\Plutonium\storage\t5\mods\
  2. Extract this zip there so the path looks like:
       ...\storage\t5\mods\mp_gunfight\mod.ff
  3. In the Plutonium client console (or in your server config):
       loadMod mp_gunfight
       map_restart
  4. Start a match on Gunfight:
       g_gametype gf
       map mp_havoc        (or any supported map)

CONTENTS
  mod.ff      compiled client assets (HUD, text, effects, gametype)
  mod.csv     asset manifest
  maps\       server-side gametype scripts

Source & updates: https://github.com/KL9modz/gunfight
"@
[System.IO.File]::WriteAllText((Join-Path $StageMod "README.txt"), $readme, $Utf8NoBom)

# -- Zip ----------------------------------------------------------------------
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -Force -LiteralPath $ZipPath }
Compress-Archive -Path $StageMod -DestinationPath $ZipPath -Force

$zip = Get-Item -LiteralPath $ZipPath
Write-Host ""
Write-Host "Staged $includedGsc gameplay GSC file(s) (excluded $($DevFiles.Count) dev file(s))."
Write-Host "Zip:    $($zip.FullName) ($([math]::Round($zip.Length / 1KB, 1)) KB)"
Write-Host "Stage:  $StageMod  (left for inspection)"

# -- Optional GitHub Release --------------------------------------------------
if ($Publish) {
    $gh = (Get-Command gh -ErrorAction SilentlyContinue)
    if (-not $gh) { throw "gh CLI not found; cannot publish. Install GitHub CLI or omit -Publish." }
    Write-Host ""
    Write-Host "Publishing GitHub Release '$Version' ..."
    & gh release create $Version $ZipPath --title "$ModName $Version" --notes "Gunfight $Version. Install: extract into ...\storage\t5\mods\ then 'loadMod mp_gunfight'. See README.txt."
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed (exit $LASTEXITCODE)" }
    Write-Host "Published."
}
else {
    Write-Host ""
    Write-Host "Not published. To create the GitHub Release:"
    Write-Host "  gh release create $Version `"$ZipPath`" --title `"$ModName $Version`" --notes `"...`""
    Write-Host "  (or re-run with -Publish)"
}
