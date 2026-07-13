param(
    [string]$GameRoot = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740",
    [string]$ModName = "mp_gunfight",
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$SkipNamedZone,
    [switch]$NoRootCopy
)

$ErrorActionPreference = "Stop"

function Resolve-RequiredPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "$Description not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Convert-AssetPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ($Path.Trim() -replace "/", "\")
}

function Find-SourceFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $assetPath = Convert-AssetPath $RelativePath
    $candidates = @(
        (Join-Path $WorkspaceRoot $assetPath),
        (Join-Path $WorkspaceRoot (Join-Path "mods\$ModName" $assetPath))
    )

    $existing = @($candidates | Where-Object { Test-Path -LiteralPath $_ })
    if ($existing.Count -eq 0) {
        return $null
    }

    return @($existing | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc } -Descending)[0]
}

function Copy-StagedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Ensure-Directory (Split-Path -Parent $Destination)
    Copy-Item -Force -LiteralPath $Source -Destination $Destination
}

function Invoke-Linker {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    Write-Host ""
    Write-Host "linker_pc.exe $($Arguments -join ' ')"
    $output = & $script:Linker @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }

    if ($exitCode -ne 0 -or ($output -match "^ERROR:")) {
        throw "linker_pc.exe failed for arguments: $($Arguments -join ' ')"
    }
}

# This script may live either at the repo root (…\tools\) where the mod is a
# subfolder (mods\$ModName), or inside the mod folder itself
# (mods\$ModName\tools\). Pick the deployed mod folder accordingly so we never
# double-nest into mods\$ModName\mods\$ModName.
if ((Split-Path -Leaf $WorkspaceRoot) -eq $ModName) {
    $ModRoot = $WorkspaceRoot
} else {
    $ModRoot = Join-Path $WorkspaceRoot "mods\$ModName"
}
$RawRoot = Join-Path $GameRoot "raw"
$ZoneSourceRoot = Join-Path $GameRoot "zone_source"
$ZoneEnglishRoot = Join-Path $GameRoot "zone\english"
$BinRoot = Join-Path $GameRoot "bin"
$script:Linker = Resolve-RequiredPath (Join-Path $BinRoot "linker_pc.exe") "Black Ops linker"

$manifestSource = Find-SourceFile "mod.csv"
if (!$manifestSource) {
    throw "No mod.csv found in workspace root or mods\$ModName"
}

Write-Host "Building $ModName"
Write-Host "Workspace: $WorkspaceRoot"
Write-Host "Game root: $GameRoot"
Write-Host "Manifest:  $manifestSource"

$manifestLines = Get-Content -LiteralPath $manifestSource
$assetsToStage = New-Object System.Collections.Generic.List[string]

foreach ($line in $manifestLines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("//") -or $trimmed.StartsWith("#")) {
        continue
    }

    $parts = $trimmed.Split(",", 2)
    if ($parts.Count -lt 2) {
        continue
    }

    $type = $parts[0].Trim().ToLowerInvariant()
    $name = $parts[1].Trim()

    switch ($type) {
        "rawfile" { $assetsToStage.Add($name) }
        "menufile" { $assetsToStage.Add($name) }
        "stringtable" { $assetsToStage.Add($name) }
        "localize" { $assetsToStage.Add("localizedstrings\$name.str") }
        # An `image,<name>` entry sources OUR <workspace>\images\<name>.iwi. Staged (and
        # cleaned) like any other asset -- a leftover raw\images\*.iwi would override the
        # stock game's image even with no mod loaded.
        "image" { $assetsToStage.Add("images\$name.iwi") }
        # A `material,<name>` entry sources OUR <workspace>\materials\<name> if we ship one,
        # else the linker just reads the stock definition already in the game's raw\materials.
        # NOTE: staging a material OVERWRITES a stock modtools source file -- see the
        # backup/restore below, which puts the original back instead of deleting it.
        "material" { $assetsToStage.Add("materials\$name") }
    }
}

# hud_gf_health.menu is loaded TRANSITIVELY via hud_gf.txt's loadMenu directive, so it
# is intentionally NOT a mod.csv menufile entry (a duplicate menufile entry double-
# registers the menu and crashes the whole UI). The linker still reads it from raw/
# when it expands hud_gf.txt, so it must be staged (and cleaned) like everything else
# -- otherwise edits to it silently never reach mod.ff and the linker compiles a stale
# raw/ copy. Add it to the stage/clean list explicitly.
$assetsToStage.Add("ui_mp/hud_gf_health.menu")

# Staging can OVERWRITE a stock file that already lives in the game's raw/ (a material is the
# case that matters: we ship a patched copy of the stock net_disconnect). The cleanup pass below
# deletes staged files, which for those would silently REMOVE a stock modtools source from the
# game install. So back up anything that already existed and restore it instead of deleting.
$stockBackups = @{}
$backupRoot = Join-Path ([IO.Path]::GetTempPath()) "gf_build_stock_backup"
if (Test-Path -LiteralPath $backupRoot) { Remove-Item -Recurse -Force -LiteralPath $backupRoot }

$stagedCount = 0
foreach ($asset in ($assetsToStage | Select-Object -Unique)) {
    $source = Find-SourceFile $asset
    if (!$source) {
        Write-Warning "No local source for $asset; leaving any stock/raw copy in place."
        continue
    }

    $assetPath = Convert-AssetPath $asset
    $destination = Join-Path $RawRoot $assetPath

    if (Test-Path -LiteralPath $destination) {
        $backupPath = Join-Path $backupRoot $assetPath
        Ensure-Directory (Split-Path -Parent $backupPath)
        Copy-Item -Force -LiteralPath $destination -Destination $backupPath
        $stockBackups[$assetPath] = $backupPath
        Write-Host "backed up stock $asset"
    }

    Copy-StagedFile $source $destination
    $stagedCount++
    Write-Host "staged $asset"
}

Copy-StagedFile $manifestSource (Join-Path $GameRoot "mods\$ModName\mod.csv")
Copy-StagedFile $manifestSource (Join-Path $ZoneSourceRoot "mods\$ModName.csv")
Copy-StagedFile $manifestSource (Join-Path $ZoneSourceRoot "mod.csv")
Copy-StagedFile $manifestSource (Join-Path $ZoneSourceRoot "english\assetlist\mods\$ModName.csv")
Copy-StagedFile $manifestSource (Join-Path $ZoneSourceRoot "english\assetlist\mod.csv")

Write-Host "Staged $stagedCount asset file(s)."

Push-Location $BinRoot
try {
    if (!$SkipNamedZone) {
        Invoke-Linker @("-nopause", "-language", "english", "-compress", "-cleanup", "mods/$ModName")
    }

    Invoke-Linker @("-nopause", "-language", "english", "-moddir", $ModName, "mod")
}
finally {
    Pop-Location
}

# Remove staged files from raw/ so they don't override the stock game between builds.
# Plutonium reads raw/ as a fallback over IWD files, even without a mod loaded.
$cleanedCount = 0
$restoredCount = 0
foreach ($asset in ($assetsToStage | Select-Object -Unique)) {
    $assetPath = Convert-AssetPath $asset
    $stagedPath = Join-Path $RawRoot $assetPath
    if (!(Test-Path -LiteralPath $stagedPath)) { continue }

    if ($stockBackups.ContainsKey($assetPath)) {
        # We overwrote a stock file -- put the original back rather than deleting it.
        Copy-Item -Force -LiteralPath $stockBackups[$assetPath] -Destination $stagedPath
        $restoredCount++
    } else {
        Remove-Item -Force -LiteralPath $stagedPath
        $cleanedCount++
    }
}
if (Test-Path -LiteralPath $backupRoot) { Remove-Item -Recurse -Force -LiteralPath $backupRoot }
Write-Host "Cleaned $cleanedCount staged file(s) from raw/; restored $restoredCount stock file(s)."

$builtModFf = Resolve-RequiredPath (Join-Path $ZoneEnglishRoot "mod.ff") "Built mod.ff"
Copy-StagedFile $builtModFf (Join-Path $ModRoot "mod.ff")

if (!$NoRootCopy) {
    Copy-StagedFile $builtModFf (Join-Path $WorkspaceRoot "mod.ff")
}

$built = Get-Item -LiteralPath $builtModFf
$local = Get-Item -LiteralPath (Join-Path $ModRoot "mod.ff")
Write-Host ""
Write-Host "Done."
Write-Host "Built:  $($built.FullName) ($($built.Length) bytes)"
Write-Host "Copied: $($local.FullName) ($($local.Length) bytes)"

if (!$NoRootCopy) {
    $rootCopy = Get-Item -LiteralPath (Join-Path $WorkspaceRoot "mod.ff")
    Write-Host "Copied: $($rootCopy.FullName) ($($rootCopy.Length) bytes)"
}
