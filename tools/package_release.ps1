param(
    [Parameter(Position = 0)][string]$Version = ("0.0.0-dev." + (Get-Date -Format "yyyyMMdd")),
    [string]$GameRoot = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740",
    [string]$ModName = "mp_gunfight",
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$SkipBuild,
    [switch]$Publish,
    [switch]$PublishBranch,
    [string]$ReleaseBranch = "release"
)

$ErrorActionPreference = "Stop"

# Two public content profiles, both staged from the full 'main' source:
#   ZIP    "ultra bare bones" deliverable -> excludes bots + RCON + debug
#   BRANCH "a little less dev" snapshot    -> excludes debug only (keeps bots + RCON)
# ('main' keeps everything; this script never modifies it.)
#
# Dev wiring in source is wrapped in CATEGORY markers this script strips:
#   // #strip-begin features ...  // #strip-end   (RCON bridge + bot init)
#   // #strip-begin debug    ...  // #strip-end   (_gf_debug include + blocks)
# Marker COMMENT lines are always removed from staged files; the body between
# them is removed only when that category is in the profile's strip list.
#
# Usage:
#   tools\package_release.ps1                        # build the bare-bones zip
#   tools\package_release.ps1 1.0.0                  # versioned zip
#   tools\package_release.ps1 1.0.0 -Publish         # zip + GitHub Release
#   tools\package_release.ps1 1.0.0 -PublishBranch   # also push 'release' branch
#   tools\package_release.ps1 -SkipBuild             # reuse the existing mod.ff

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Files excluded per category (forward-slash, repo-relative).
$FeatureFiles = @(
    "maps/mp/gametypes/_bot.gsc",
    "maps/mp/bots/_bot_loadout.gsc",
    "maps/mp/bots/_bot_script.gsc",
    "maps/mp/bots/_bot_utility.gsc",
    "maps/mp/gametypes/_gf_bridge.gsc"
)
$DebugFiles = @( "maps/mp/gametypes/_gf_debug.gsc" )

$ZipExclude = $FeatureFiles + $DebugFiles
$ZipStrip = @("features", "debug")
$BranchExclude = $DebugFiles
$BranchStrip = @("debug")

function Strip-Regions {
    param([string]$Content, [string[]]$StripCategories)
    foreach ($cat in $StripCategories) {
        $pat = "(?ms)^[^\r\n]*#strip-begin\s+" + [regex]::Escape($cat) + "\b.*?#strip-end[^\r\n]*\r?\n?"
        $Content = [regex]::Replace($Content, $pat, "")
    }
    # Drop leftover marker comment lines (kept categories), keeping their body.
    $Content = [regex]::Replace($Content, "(?m)^[^\r\n]*#strip-(begin|end)[^\r\n]*\r?\n?", "")
    return $Content
}

function Build-Staging {
    param(
        [string]$StageMod,
        [string[]]$ExcludeFiles,
        [string[]]$StripCats,
        [string]$Label,
        [switch]$IncludeRconTool
    )
    if (Test-Path -LiteralPath $StageMod) { Remove-Item -Recurse -Force -LiteralPath $StageMod }
    New-Item -ItemType Directory -Force -Path $StageMod | Out-Null

    Copy-Item -Force -LiteralPath $ModFf -Destination (Join-Path $StageMod "mod.ff")

    $gscFiles = Get-ChildItem -Recurse -File -LiteralPath (Join-Path $ModRoot "maps") -Filter *.gsc
    $n = 0
    foreach ($file in $gscFiles) {
        $rel = $file.FullName.Substring($ModRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if ($ExcludeFiles -contains $rel) { continue }
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $content = Strip-Regions $content $StripCats
        $dest = Join-Path $StageMod ($rel -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        [System.IO.File]::WriteAllText($dest, $content, $Utf8NoBom)
        $n++
    }

    $csvLines = Get-Content -LiteralPath $ModCsv
    $keptCsv = foreach ($line in $csvLines) {
        $norm = $line.Replace('\', '/')
        $excluded = $false
        foreach ($ex in $ExcludeFiles) { if ($norm -match [regex]::Escape($ex)) { $excluded = $true; break } }
        if (-not $excluded) { $line }
    }
    [System.IO.File]::WriteAllLines((Join-Path $StageMod "mod.csv"), $keptCsv, $Utf8NoBom)

    $readme = @'
# mp_gunfight

Gunfight gametype for **Call of Duty: Black Ops 1** (Plutonium T5) - one life per
round, shared random loadouts, six rounds to win the match.

**Version __VERSION__**

## Install (required for every player AND the server)

Plutonium's T5 client cannot download mods from a server, so everyone joining must
install the mod locally. Without it you get no HUD, blank text, and missing effects.

1. Open your Plutonium storage mods folder: `%localappdata%\Plutonium\storage\t5\mods\`
2. Extract so the path is `...\storage\t5\mods\mp_gunfight\mod.ff`
3. In the Plutonium console (or your server config):

       loadMod mp_gunfight
       map_restart

4. Start a match:

       g_gametype gf
       map mp_havoc

## Source

Full source and development are on the
[`main`](https://github.com/KL9modz/gunfight/tree/main) branch.
'@ -replace '__VERSION__', $Version
    [System.IO.File]::WriteAllText((Join-Path $StageMod "README.md"), $readme, $Utf8NoBom)

    $rconCount = 0
    if ($IncludeRconTool) {
        $rconSrc = Join-Path $WorkspaceRoot "tools\rcon"
        if (Test-Path -LiteralPath $rconSrc) {
            $rconFiles = Get-ChildItem -Recurse -File -LiteralPath $rconSrc | Where-Object { $_.FullName -notmatch '\\node_modules\\' }
            foreach ($rf in $rconFiles) {
                $rrel = $rf.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/')
                $rdest = Join-Path $StageMod $rrel
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $rdest) | Out-Null
                Copy-Item -Force -LiteralPath $rf.FullName -Destination $rdest
                $rconCount++
            }
        }
    }

    Write-Host ("  [{0}] {1} GSC file(s); excluded {2} file(s); stripped [{3}]; rcon tool {4} file(s)" -f $Label, $n, $ExcludeFiles.Count, ($StripCats -join "+"), $rconCount)
    return $n
}

# -- Resolve paths ------------------------------------------------------------
$ModRoot = $WorkspaceRoot
$ModFf = Join-Path $ModRoot "mod.ff"
$ModCsv = Join-Path $ModRoot "mod.csv"
$DistDir = Join-Path $WorkspaceRoot "tools\dist"
$ZipStageMod = Join-Path $DistDir "stage\$ModName"
$BranchStageMod = Join-Path $DistDir "branch-stage\$ModName"
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

# -- Stage + zip the ultra-bare-bones deliverable -----------------------------
Write-Host ""
Build-Staging $ZipStageMod $ZipExclude $ZipStrip "zip (bare bones)" | Out-Null
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -Force -LiteralPath $ZipPath }
Compress-Archive -Path $ZipStageMod -DestinationPath $ZipPath -Force
$zip = Get-Item -LiteralPath $ZipPath
Write-Host ("Zip:    {0} ({1} KB)" -f $zip.FullName, [math]::Round($zip.Length / 1KB, 1))

# -- Optional: publish 'release' branch (a-little-less-dev profile) ------------
# Force-pushed as a single orphan commit (mod.ff included), so history never
# accumulates binaries. Temp index + git plumbing -> working tree untouched.
if ($PublishBranch) {
    Write-Host ""
    Write-Host "Staging 'less dev' snapshot for branch '$ReleaseBranch' ..."
    Build-Staging $BranchStageMod $BranchExclude $BranchStrip "branch (keeps bots+RCON)" -IncludeRconTool | Out-Null

    $tmpIndex = Join-Path ([System.IO.Path]::GetTempPath()) ("gf_relidx_" + [System.Guid]::NewGuid().ToString("N"))
    $prevIndex = $env:GIT_INDEX_FILE
    try {
        $env:GIT_INDEX_FILE = $tmpIndex
        & git -C $WorkspaceRoot read-tree --empty
        if ($LASTEXITCODE -ne 0) { throw "git read-tree failed" }
        & git -C $WorkspaceRoot --work-tree=$BranchStageMod add --force --all
        if ($LASTEXITCODE -ne 0) { throw "git add (snapshot) failed" }
        $tree = (& git -C $WorkspaceRoot write-tree).Trim()
        if (-not $tree) { throw "git write-tree produced no tree" }
        $commit = (& git -C $WorkspaceRoot commit-tree $tree -m "Release $Version (clean snapshot)").Trim()
        if (-not $commit) { throw "git commit-tree produced no commit" }
        $refspec = $commit + ":refs/heads/" + $ReleaseBranch
        & git -C $WorkspaceRoot push -f origin $refspec
        if ($LASTEXITCODE -ne 0) { throw "git push to '$ReleaseBranch' failed" }
        Write-Host "Published branch '$ReleaseBranch' -> $commit"
    }
    finally {
        if ($null -ne $prevIndex) { $env:GIT_INDEX_FILE = $prevIndex }
        else { Remove-Item env:GIT_INDEX_FILE -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $tmpIndex) { Remove-Item -Force -LiteralPath $tmpIndex }
    }
}

# -- Optional GitHub Release (the ultra-bare-bones zip) -----------------------
if ($Publish) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "gh CLI not found; cannot publish. Install GitHub CLI or omit -Publish."
    }
    Write-Host ""
    Write-Host "Publishing GitHub Release '$Version' ..."
    & gh release create $Version $ZipPath --target $ReleaseBranch --title "$ModName $Version" --notes "Gunfight $Version. Install: extract into ...\storage\t5\mods\ then 'loadMod mp_gunfight'. See README.txt."
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed (exit $LASTEXITCODE)" }
    Write-Host "Published."
}
else {
    Write-Host ""
    Write-Host "Not published. GitHub Release: re-run with -Publish (or run gh release create $Version manually)."
}
