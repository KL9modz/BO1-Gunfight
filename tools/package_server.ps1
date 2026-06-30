param(
    [Parameter(Position = 0)][string]$Version = ("0.0.0-dev." + (Get-Date -Format "yyyyMMdd")),
    [string]$GameRoot = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740",
    [string]$ModName = "mp_gunfight",
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$SkipBuild,
    [switch]$IncludeRconTool,
    [switch]$SanitizeConfig,
    [switch]$RotateRcon
)

$ErrorActionPreference = "Stop"

# Build a PRIVATE VPS deployment bundle (NOT for public release):
#   t5/
#     mods/mp_gunfight/   COMPLETE mirror of the 'main' branch: every git-tracked
#                         file (all gameplay + dev GSC, mod.csv, the UI/strings/csv
#                         source, gf.cfg, notes/, tools/ incl. the RCON panel +
#                         wager catalogs, .claude/, README, ...) PLUS the compiled
#                         mod.ff (a gitignored build output the runtime needs).
#                         This is the whole point of the server bundle vs release:
#                         release ships a stripped, comment-free public subset; the
#                         server gets EVERYTHING from main.
#     dedicated.cfg       your server config (CONTAINS rcon_password unless -SanitizeConfig)
#     tools/rcon/         optional top-level copy of the web RCON panel (-IncludeRconTool;
#                         the panel also lives inside the mod folder now via the full tree)
#   DEPLOY.txt            where each file goes on the VPS + required edits
#
# Output: tools\dist\mp_gunfight-server-<version>.zip  (gitignored)
#
# Usage:
#   tools\package_server.ps1                       # snapshot bundle (config as-is)
#   tools\package_server.ps1 1.0.0                 # versioned bundle
#   tools\package_server.ps1 1.0.0 -RotateRcon     # generate+inject a fresh rcon_password, print it
#   tools\package_server.ps1 1.0.0 -SanitizeConfig # blank rcon_password in the copy
#   tools\package_server.ps1 -IncludeRconTool      # also bundle the web RCON panel

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Copy-Into {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -Force -LiteralPath $Source -Destination $Destination
}

# Cryptographically-random alphanumeric password. Alnum only on purpose: no quotes,
# spaces, or shell/cfg metacharacters that could break the cfg line or the RCON protocol.
# Length <= 23: Plutonium truncates the rcon password at 23 chars on login, so any longer
# value is silently chopped and never matches. 20 keeps a safe margin (~119 bits of entropy).
function New-RconPassword {
    param([int]$Length = 20)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
    $bytes = New-Object 'System.Byte[]' $Length
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    -join ($bytes | ForEach-Object { $chars[ $_ % $chars.Length ] })
}

# -- Resolve paths ------------------------------------------------------------
$ModRoot = $WorkspaceRoot                                   # repo root IS the mod folder
$T5Root = (Resolve-Path (Join-Path $WorkspaceRoot "..\..")).Path  # storage\t5
$ModFf = Join-Path $ModRoot "mod.ff"
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

# -- Full mod: mod.ff + EVERYTHING tracked on 'main' (complete source tree) -----
# Unlike the release zip (a stripped public subset), the server bundle mirrors the
# entire 'main' branch. We enumerate via `git ls-files` so the file set IS "main"
# by definition: it auto-excludes gitignored junk (tools/dist, logs, raw/ FX
# source, dedicated.cfg, ...) and needs no hand-maintained include list. Files are
# copied from the live work tree, so uncommitted local edits ship too. mod.ff is
# gitignored (build output) so it is added explicitly -- the runtime needs it.
Copy-Into $ModFf (Join-Path $StageMod "mod.ff")

$tracked = @(& git -C $ModRoot -c core.quotepath=false ls-files) | Where-Object { $_ -ne "" }
if ($LASTEXITCODE -ne 0) { throw "git ls-files failed (is '$ModRoot' a git work tree?)" }
if ($tracked.Count -eq 0) { throw "git ls-files returned no files; refusing to build an empty server bundle." }
$copied = 0
$skipped = 0
foreach ($rel in $tracked) {
    $win = $rel -replace '/', '\'
    $src = Join-Path $ModRoot $win
    if (!(Test-Path -LiteralPath $src)) { $skipped++; continue }   # tracked but absent in work tree
    Copy-Into $src (Join-Path $StageMod $win)
    $copied++
}
$skipNote = ""
if ($skipped -gt 0) { $skipNote = " ($skipped tracked path(s) absent in work tree, skipped)" }
Write-Host "  + mod.ff + $copied tracked file(s) from main (complete source tree)$skipNote"

# -- Safety guard: no committed secret in the staged GSC ----------------------
# gf.gsc/any .gsc must NEVER hardcode an rcon_password: dedicated.cfg is the sole owner on the
# VPS. A setDvar("rcon_password","<nonempty>") in a staged script would silently override the
# cfg every map_restart with a value that is committed (public) in git. Fail the build if found.
$staged = Get-ChildItem -Recurse -File -LiteralPath $StageMod -Filter *.gsc
foreach ($g in $staged) {
    $txt = [System.IO.File]::ReadAllText($g.FullName)
    if ($txt -match 'setDvar\s*\(\s*"rcon_password"\s*,\s*"[^"]+"\s*\)') {
        throw "SECURITY: staged $($g.FullName) hardcodes an rcon_password. Remove it from GSC (dedicated.cfg owns it) before bundling."
    }
}
Write-Host "  + secret guard: no hardcoded rcon_password in staged GSC"

# -- dedicated.cfg (rotate / blank / pass through the rcon_password) -----------
# Rotation rewrites ONLY the bundled copy; the source dedicated.cfg is the template
# and stays untouched. The deployed copy is the live source of truth on the VPS, so
# the live password is never the one sitting in git history.
$cfgIncluded = $false
$cfgSanitized = $false
$cfgRotated = $false
$newRcon = ""
$rconRe = '(?m)^(\s*set\s+rcon_password\s+)".*?"'
if (Test-Path -LiteralPath $DedCfg) {
    $cfgContent = [System.IO.File]::ReadAllText($DedCfg)
    if ($RotateRcon) {
        if ($SanitizeConfig) { Write-Warning "-RotateRcon and -SanitizeConfig both set; -RotateRcon wins (a real password is injected)." }
        $newRcon = New-RconPassword
        if ([regex]::IsMatch($cfgContent, $rconRe)) {
            $cfgContent = [regex]::Replace($cfgContent, $rconRe, ('$1"' + $newRcon + '"'))
        }
        else {
            Write-Warning "no 'set rcon_password' line in dedicated.cfg; appending one."
            if ($cfgContent.Length -gt 0 -and -not $cfgContent.EndsWith("`n")) { $cfgContent += "`r`n" }
            $cfgContent += ('set rcon_password "' + $newRcon + '"' + "`r`n")
        }
        $cfgRotated = $true
    }
    elseif ($SanitizeConfig) {
        $cfgContent = [regex]::Replace($cfgContent, $rconRe, '$1"CHANGEME"')
        $cfgSanitized = $true
    }
    [System.IO.File]::WriteAllText((Join-Path $StageRoot "t5\dedicated.cfg"), $cfgContent, $Utf8NoBom)
    $cfgIncluded = $true
    $cfgNote = ""
    if ($cfgRotated) { $cfgNote = " (rcon_password ROTATED)" }
    elseif ($cfgSanitized) { $cfgNote = " (rcon_password blanked)" }
    Write-Host "  + dedicated.cfg$cfgNote"
}
else {
    Write-Warning "dedicated.cfg not found at $DedCfg - bundle will not include it."
    if ($RotateRcon) { Write-Warning "-RotateRcon had no effect: there is no dedicated.cfg to inject the password into." }
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
$rconStep = "  1. rcon_password  - set a NEW strong password (rotate the bundled one)."
if ($cfgRotated) {
    $rconStep = "  1. rcon_password  - already auto-rotated to a fresh value for this bundle (also" + "`r`n" + "     printed during packaging). No action needed unless you want to change it." + "`r`n" + "     Paste the same value into your RCON client / web panel."
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
$rconStep
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
if ($cfgRotated) {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host " NEW rcon_password (injected into the bundled dedicated.cfg):" -ForegroundColor Green
    Write-Host ""
    Write-Host "     $newRcon" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " Save this now. Paste it into your RCON client / web panel after" -ForegroundColor Green
    Write-Host " deploying. It is live the moment this cfg is loaded on the VPS." -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green
}
if ($cfgIncluded -and -not $cfgSanitized) {
    Write-Host ""
    Write-Host "*** SECURITY: this bundle contains dedicated.cfg WITH a live rcon_password. ***" -ForegroundColor Yellow
    Write-Host "*** Keep it private; never attach it to a public GitHub Release.            ***" -ForegroundColor Yellow
    if (-not $cfgRotated) {
        Write-Host "*** Re-run with -RotateRcon to inject a fresh password, or -SanitizeConfig  ***" -ForegroundColor Yellow
        Write-Host "*** to produce a password-blanked copy.                                    ***" -ForegroundColor Yellow
    }
}
