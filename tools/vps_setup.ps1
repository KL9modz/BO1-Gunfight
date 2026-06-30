param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$WebDryRun
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# READ-ONLY VPS readiness check. Run ONCE on the VPS after cloning, from inside
# the clone:
#       cd C:\gfdeploy\BO1-Gunfight
#       .\tools\vps_setup.ps1   (the leading .\ is required by Windows PowerShell)
#
# It changes nothing. It verifies git + the clone, locates the live Plutonium
# mod folder and the IIS site path (so account naming doesn't matter), confirms
# GitHub connectivity, and prints the exact deploy commands you'll use.
# Add -WebDryRun to also run a no-op `deploy.ps1 -Web -DryRun` preview.
# ---------------------------------------------------------------------------

function Section { param([string]$Title) Write-Host ""; Write-Host "== $Title ==" -ForegroundColor Cyan }

Section "git"
$git = Get-Command git -ErrorAction SilentlyContinue
if (!$git) {
    throw "git is not on PATH. Install Git for Windows first (see the bootstrap snippet), then re-run."
}
Write-Host (git --version)

Section "repo clone"
& git -C $RepoRoot rev-parse --is-inside-work-tree > $null 2>&1
if ($LASTEXITCODE -ne 0) { throw "Not a git work tree: $RepoRoot" }
Write-Host ("repo:   {0}" -f $RepoRoot)
Write-Host ("branch: {0}" -f ((git -C $RepoRoot rev-parse --abbrev-ref HEAD)))
Write-Host ("remote: {0}" -f ((git -C $RepoRoot remote get-url origin)))
Write-Host ("head:   {0}" -f ((git -C $RepoRoot log --oneline -1)))

# GitHub reachability (read-only; public repo so no credentials needed)
& git -C $RepoRoot ls-remote --heads origin > $null 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "github reachable: OK (outbound 443 working - pulls will succeed)"
} else {
    Write-Host "github reachable: FAILED - check outbound network/proxy" -ForegroundColor Yellow
}

$deploy = Join-Path $RepoRoot "tools\deploy.ps1"
Write-Host ("deploy.ps1: {0}" -f $(if (Test-Path $deploy) { "present" } else { "MISSING (run 'git pull')" }))
$webSrc = Join-Path $RepoRoot "site\wwwroot"
Write-Host ("site\wwwroot: {0}" -f $(if (Test-Path $webSrc) { "present" } else { "MISSING (run 'git pull')" }))

Section "Plutonium mod folder (target for -Mod deploys)"
$rel = "AppData\Local\Plutonium\storage\t5\mods\mp_gunfight"
$cur = Join-Path $env:LOCALAPPDATA "Plutonium\storage\t5\mods\mp_gunfight"
$candidates = @($cur)
$profiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
foreach ($p in $profiles) { $candidates += (Join-Path $p.FullName $rel) }
$modHits = @()
foreach ($c in ($candidates | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $c) { $modHits += $c }
}
if ($modHits.Count -eq 0) {
    Write-Host "No mp_gunfight mod folder found under any user profile." -ForegroundColor Yellow
    Write-Host "  The server may not be installed yet, or it's under a profile this account can't read."
    Write-Host "  Run this script as the account that runs the server (gfsvc), or deploy with an explicit -ModDest."
} else {
    foreach ($m in $modHits) { Write-Host ("  found: {0}" -f $m) }
}

Section "IIS site (target for -Web deploys)"
$web = "C:\inetpub\wwwroot"
Write-Host ("  default wwwroot: {0}" -f $(if (Test-Path $web) { "exists ($web)" } else { "NOT at $web" }))
try {
    Import-Module WebAdministration -ErrorAction Stop
    $sites = Get-Website
    if ($sites) { $sites | ForEach-Object { Write-Host ("  IIS site '{0}' (state {1}) -> {2}" -f $_.name, $_.state, $_.physicalPath) } }
    else { Write-Host "  (no IIS sites registered)" }
} catch {
    Write-Host "  (WebAdministration module unavailable - can't enumerate IIS sites; default path assumed)"
}

Section "Ready-to-go deploy commands"
Write-Host "WEBSITE (no restart):"
Write-Host "  .\tools\deploy.ps1 -Web -DryRun        # preview what would change"
Write-Host "  .\tools\deploy.ps1 -Web                # publish (git pull + mirror to wwwroot)"
Write-Host ""
Write-Host "MOD (restarts the server). Run as the server account, or pass -ModDest:"
if ($modHits.Count -gt 0 -and ($modHits -notcontains $cur)) {
    Write-Host ("  .\tools\deploy.ps1 -Mod -ModDest `"{0}`"" -f $modHits[0])
    Write-Host "  (the mod folder isn't under THIS account's profile, so -ModDest is required here)"
} else {
    Write-Host "  .\tools\deploy.ps1 -Mod"
}

if ($WebDryRun) {
    if (Test-Path $deploy) {
        Section "deploy.ps1 -Web -DryRun"
        & $deploy -Web -DryRun
    } else {
        Write-Host "Skipping -WebDryRun: deploy.ps1 not present yet." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "VPS readiness check complete." -ForegroundColor Green
