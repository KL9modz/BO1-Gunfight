param(
    [switch]$Mod,
    [switch]$Web,
    [string]$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$ModName    = "mp_gunfight",
    [string]$ModDest    = (Join-Path $env:LOCALAPPDATA "Plutonium\storage\t5\mods\mp_gunfight"),
    [string]$WebDest    = "C:\inetpub\wwwroot",
    [string]$ReleaseRef = "release",
    [switch]$NoPull,
    [switch]$NoRestart,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# VPS-side apply step for the git-pull deploy model. Runs INSIDE the clone on
# the VPS (e.g. C:\gfdeploy\BO1-Gunfight). The laptop pushes; this pulls and
# copies into the two live locations.
#
#   .\tools\deploy.ps1 -Web              # mirror site\wwwroot -> IIS wwwroot (no restart)
#   .\tools\deploy.ps1 -Mod              # pull GSC + release mod.ff -> Plutonium mods, restart
#   .\tools\deploy.ps1 -Mod -Web         # both
#   .\tools\deploy.ps1 -Web -DryRun      # show what robocopy WOULD do (no changes)
#   .\tools\deploy.ps1 -Mod -NoRestart   # copy mod files but leave the server running
#
# Run as the SAME account that runs the game server (gfsvc) so $env:LOCALAPPDATA
# resolves to that profile's Plutonium storage. If you run it as a different
# account, pass -ModDest with the explicit path, e.g.
#   -ModDest C:\Users\gfsvc\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight
#
# Guardrails:
#   - Never touches dedicated.cfg (lives in storage\t5\, not the mod folder; it
#     is the sole owner of rcon_password and stays VPS-local).
#   - Refuses to publish the website if it finds a secret (rcon password etc.).
#   - tools\rcon\ (the private admin panel) is part of the mod tree, NOT the
#     site; it is never copied to wwwroot.
# ---------------------------------------------------------------------------

# Secrets that must never reach the world-readable marketing page. These are
# FATAL if found anywhere under site\wwwroot.
$WebSecretPatterns = @(
    'aBHguGlfMQA9NcqEO1YJ5WKm',                                              # the historically leaked rcon password literal
    '(?i)rcon_password',                                                     # the dvar name
    '(?i)\b(password|passwd|secret|api[_-]?key|private[_-]?key|client[_-]?secret)\b["'']?\s*[:=]'  # assignment-looking secrets (incl. JSON "key":)
)

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & git -C $RepoRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed (exit $LASTEXITCODE)"
    }
    return $output
}

function Invoke-Robocopy {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$ExtraArgs = @()
    )

    $rcArgs = @($Source, $Destination, "/MIR", "/R:1", "/W:1", "/NP") + $ExtraArgs
    if ($DryRun) {
        $rcArgs += "/L"                  # list only - do not copy/delete anything
    } else {
        $rcArgs += @("/NFL", "/NDL")     # quiet: summary table only, no per-file spam
    }

    Write-Host "robocopy $Source -> $Destination $($ExtraArgs -join ' ')$(if ($DryRun) { ' (DRY RUN /L)' })"
    & robocopy @rcArgs
    $rc = $LASTEXITCODE
    # robocopy: 0-7 = success (8+ = at least one failure). Reset so callers and
    # $ErrorActionPreference don't treat a normal copy as an error.
    if ($rc -ge 8) {
        throw "robocopy failed (exit $rc) copying $Source -> $Destination"
    }
    $global:LASTEXITCODE = 0
}

function Assert-GitRepo {
    & git -C $RepoRoot rev-parse --is-inside-work-tree > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Not a git repository: $RepoRoot"
    }
}

function Update-Repo {
    if ($NoPull) {
        Write-Host "Skipping pull (-NoPull)."
        return
    }
    Write-Host "Pulling latest..."
    Invoke-Git @("pull", "--ff-only") | ForEach-Object { Write-Host "  $_" }
}

function Find-WebSecrets {
    param([Parameter(Mandatory = $true)][string]$Root)

    $textExt = @(".html", ".htm", ".css", ".js", ".mjs", ".json", ".txt", ".xml", ".svg",
                 ".config", ".md", ".yml", ".yaml", ".ini", ".cfg", ".conf", ".env", ".webmanifest")
    $hits = @()

    $files = Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $textExt -contains $_.Extension.ToLowerInvariant() }

    foreach ($file in $files) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
            $lineNo++
            foreach ($pat in $WebSecretPatterns) {
                if ($line -match $pat) {
                    $rel = $file.FullName.Substring($Root.Length).TrimStart('\')
                    $hits += "  $rel : $lineNo : matched /$pat/"
                }
            }
        }
    }
    return $hits
}

function Deploy-Web {
    $webSrc = Join-Path $RepoRoot "site\wwwroot"
    if (!(Test-Path -LiteralPath $webSrc)) {
        throw "Website source not found: $webSrc"
    }
    if (!(Test-Path -LiteralPath $WebDest)) {
        throw "Web destination not found: $WebDest (create it or pass -WebDest)"
    }

    Write-Host ""
    Write-Host "== WEB =="
    Write-Host "Secret-scanning $webSrc ..."
    $secrets = Find-WebSecrets $webSrc
    if ($secrets.Count -gt 0) {
        Write-Host "REFUSING TO PUBLISH - possible secret(s) in the public site:" -ForegroundColor Red
        $secrets | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        throw "Web deploy aborted: remove the secret(s) above (the page is world-readable)."
    }
    Write-Host "No secrets found."

    # web.config is VPS-owned (carries the hardened HTTP->HTTPS redirect + HSTS).
    # Only mirror it if the repo deliberately tracks one; otherwise exclude it so
    # /MIR never purges the live hardened copy.
    $extra = @()
    if (!(Test-Path -LiteralPath (Join-Path $webSrc "web.config"))) {
        $extra += @("/XF", "web.config")
        Write-Host "Preserving VPS-owned web.config (none tracked in repo)."
    }

    Invoke-Robocopy -Source $webSrc -Destination $WebDest -ExtraArgs $extra
    Write-Host "Website deployed$(if ($DryRun) { ' (dry run - nothing changed)' }). No restart needed (static IIS content)."
}

function Get-ReleaseModFf {
    # mod.ff is a gitignored binary on main; it travels on the release branch.
    # Fetch it and check the binary out into the working tree (binary-safe; git
    # handles it). Unstage afterward so the gitignored file leaves status clean.
    Write-Host "Fetching mod.ff from '$ReleaseRef' branch..."
    Invoke-Git @("fetch", "origin", $ReleaseRef) | Out-Null
    Invoke-Git @("checkout", "FETCH_HEAD", "--", "mod.ff") | Out-Null
    & git -C $RepoRoot reset -q -- mod.ff > $null 2>&1

    $modFf = Join-Path $RepoRoot "mod.ff"
    if (!(Test-Path -LiteralPath $modFf)) {
        throw "mod.ff was not produced by the release checkout - did you run package_release.ps1 -PublishBranch?"
    }
    $size = (Get-Item -LiteralPath $modFf).Length
    Write-Host "Got mod.ff ($size bytes)."
}

function Restart-Server {
    if ($NoRestart -or $DryRun) {
        Write-Host "Skipping server restart$(if ($DryRun) { ' (dry run)' }) - relaunch manually to load the new mod."
        return
    }
    Write-Host "Restarting game server (the restart-loop bat relaunches it under gfsvc)..."
    & taskkill /IM "plutonium-bootstrapper-win32.exe" /F > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Bootstrapper killed; restart loop will bring it back up."
    } else {
        Write-Host "Bootstrapper was not running (nothing to kill) - start it manually if needed."
    }
    $global:LASTEXITCODE = 0
}

function Deploy-Mod {
    # Safety: never let a typo'd -ModDest mirror over the wrong directory.
    if (($ModDest -notlike "*$ModName*")) {
        throw "Refusing to deploy: -ModDest does not contain '$ModName' ($ModDest). Pass the correct mod-folder path."
    }
    if (!(Test-Path -LiteralPath $ModDest)) {
        throw "Mod destination not found: $ModDest (is Plutonium installed for this account? pass -ModDest if running as a different user)"
    }

    Write-Host ""
    Write-Host "== MOD =="
    Get-ReleaseModFf

    # Mirror the tracked tree (GSC/menus/strings/csv) + the release mod.ff into
    # the live mod folder. Exclude .git, the website, build junk, and the game
    # raw tree (none of which belong in the runtime mod folder). dedicated.cfg
    # lives in storage\t5\, NOT here, so /MIR never touches it.
    $xd = @(
        (Join-Path $RepoRoot ".git"),
        (Join-Path $RepoRoot "site"),
        (Join-Path $RepoRoot "tools\dist"),
        (Join-Path $RepoRoot "raw")
    )
    Invoke-Robocopy -Source $RepoRoot -Destination $ModDest -ExtraArgs (@("/XD") + $xd)
    Write-Host "Mod tree + mod.ff deployed$(if ($DryRun) { ' (dry run - nothing changed)' }) to $ModDest"

    Restart-Server

    Write-Host ""
    Write-Host "NOTE: players must install the matching public package themselves -" -ForegroundColor Yellow
    Write-Host "      T5 has no client mod download. Re-cut it with package_release.ps1 -Publish." -ForegroundColor Yellow
}

# --- main -------------------------------------------------------------------

if (!$Mod -and !$Web) {
    Write-Host "Nothing to do. Pass -Mod and/or -Web."
    Write-Host "  .\tools\deploy.ps1 -Web      # publish the website (no restart)"
    Write-Host "  .\tools\deploy.ps1 -Mod      # deploy the mod + restart the server"
    Write-Host "  .\tools\deploy.ps1 -Mod -Web # both"
    Write-Host "  add -DryRun to preview, -NoPull to skip git pull, -NoRestart to keep the server up"
    return
}

Assert-GitRepo
Write-Host "Repo: $RepoRoot"
Update-Repo

if ($Web) { Deploy-Web }
if ($Mod) { Deploy-Mod }

Write-Host ""
Write-Host "Done."
