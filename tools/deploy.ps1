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
    [switch]$NoFastDL,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# VPS-side apply step for the git-pull deploy model. Runs INSIDE the clone on
# the VPS (e.g. C:\gfdeploy\BO1-Gunfight). The laptop pushes; this pulls and
# copies into the two live locations.
#
#   .\tools\deploy.ps1 -Web              # mirror site\wwwroot -> IIS wwwroot (no restart)
#   .\tools\deploy.ps1 -Mod              # pull GSC + release mod.ff -> Plutonium mods,
#                                        #   publish mod.ff to IIS for FastDL, restart
#   .\tools\deploy.ps1 -Mod -Web         # both
#   .\tools\deploy.ps1 -Web -DryRun      # show what robocopy WOULD do (no changes)
#   .\tools\deploy.ps1 -Mod -NoRestart   # copy mod files but leave the server running
#   .\tools\deploy.ps1 -Mod -NoFastDL    # deploy the mod but skip the FastDL copy
#
# Run as the SAME account that runs the game server so $env:LOCALAPPDATA resolves
# to that profile's Plutonium storage. On the current VPS the server runs as
# ADMINISTRATOR (confirmed 2026-07-02 via the bootstrapper process owner; no gfsvc
# account exists - the low-priv gfsvc in docs/VPS_DEPLOY.md is aspirational hardening).
# A wrong-account deploy SILENTLY mirrors into that account's own profile while the
# server keeps loading old files. Find the real account any time:
#   Get-CimInstance Win32_Process | ? Name -match bootstrapper   # check the owner
# If deploying from a different account, pass -ModDest explicitly, e.g.
#   -ModDest C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight
#
# FastDL (client auto-download): -Mod also copies the release mod.ff to
#   <WebDest>\mods\<ModName>\mod.ff  so connecting clients download it over HTTP.
# Two ONE-TIME VPS prereqs deploy.ps1 does NOT do (they live outside the repo):
#   1. dedicated.cfg:  set sv_wwwBaseURL "https://gunfight.us/"  (latches at start;
#      must be in the cfg before launch, NOT set over RCON). Verify the startup
#      dump shows a non-empty value - an empty sv_wwwBaseURL is why the client got
#      "Invalid download response" before (it had no URL to fetch from).
#      Use https:// (NOT http://): the hardened IIS 301-redirects http->https, and
#      the client may not follow the redirect. https serves the file directly.
#   2. IIS must serve the .ff MIME type, else IIS 404s mod.ff. One-time:
#      %windir%\system32\inetsrv\appcmd set config /section:staticContent ^
#        /+"[fileExtension='.ff',mimeType='application/octet-stream']"
#      (.iwd/.iwi too if you later ship custom maps). HFS on a separate port is
#      the staff-recommended alt that auto-handles MIME. See docs/VPS_DEPLOY.md Phase 8.
#
# Guardrails:
#   - Never touches dedicated.cfg (lives in storage\t5\, not the mod folder; it
#     is the sole owner of rcon_password and stays VPS-local).
#   - Refuses to publish the website if it finds a secret (rcon password etc.).
#   - tools\rcon\ (the private admin panel) is part of the mod tree, NOT the
#     site; it is never copied to wwwroot.
#   - FastDL publishes ONLY mod.ff (the public artifact players already get),
#     never the mod tree - so .git/tools/notes/etc. are never world-readable.
#   - -Web's /MIR excludes mods\ + usermaps\ (FastDL copy) and live\/admin\live\
#     (status snapshots) so it never purges box-local files that aren't in the repo.
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
    $before = (& git -C $RepoRoot rev-parse HEAD 2>$null)
    Write-Host "Pulling latest..."
    Invoke-Git @("pull", "--ff-only") | ForEach-Object { Write-Host "  $_" }
    $after = (& git -C $RepoRoot rev-parse HEAD 2>$null)

    # Self-update trap: PowerShell parsed THIS script into memory before the pull.
    # If the pull just changed deploy.ps1, the running process is still the OLD code
    # (stale functions + line numbers). Stop now so the user re-runs the new version
    # instead of executing a half-old script. Re-run with -NoPull to use the on-disk
    # copy directly without pulling again.
    if ($before -and $after -and ($before -ne $after)) {
        $changed = Invoke-Git @("diff", "--name-only", "$before..$after")
        if ($changed -contains "tools/deploy.ps1") {
            Write-Host ""
            Write-Host "deploy.ps1 was updated by this pull - re-run the SAME command so the" -ForegroundColor Yellow
            Write-Host "NEW version executes (this run is still the old in-memory copy)." -ForegroundColor Yellow
            exit 0
        }
    }
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
    # Never purge the ACME http-01 challenge dir (Let's Encrypt renewal). It isn't in the
    # repo, so excluding the name keeps /MIR from deleting it off the live wwwroot.
    $extra += @("/XD", ".well-known")
    # Never purge the FastDL payload dirs either - mod.ff (mods\) and any custom maps
    # (usermaps\) are published by Deploy-Mod, not by the website source, so /MIR
    # must leave them alone or the next -Web would delete the client-download files.
    $extra += @("/XD", (Join-Path $WebDest "mods"), (Join-Path $WebDest "usermaps"))
    # Never purge live\ - the status service (tools\status_service) writes the public
    # status.json snapshot there on the box; it isn't in the repo, so /MIR would delete it.
    $extra += @("/XD", (Join-Path $WebDest "live"))
    # Never purge admin\live\ either - it holds the auth-gated admin.json snapshot AND the
    # .secured marker (created by setup_admin_auth.ps1). Purging it would silently disable
    # the admin view. admin\admin.html itself IS tracked and mirrors normally.
    $extra += @("/XD", (Join-Path $WebDest "admin\live"))

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

function Publish-FastDL {
    # Copy the (clean, release) mod.ff into the IIS web root so connecting clients
    # auto-download it: <WebDest>\mods\<ModName>\mod.ff, fetched by the engine at
    # <sv_wwwBaseURL>/mods/<ModName>/mod.ff. The server's own log confirms the mod
    # download set is exactly ONE file (mod.ff), so that is all we publish - never
    # the mod tree (keeps .git/tools/notes out of the world-readable web root).
    if ($NoFastDL) {
        Write-Host "Skipping FastDL publish (-NoFastDL)."
        return
    }
    $modFf = Join-Path $RepoRoot "mod.ff"
    if (!(Test-Path -LiteralPath $modFf)) {
        Write-Host "No mod.ff in the working tree - skipping FastDL publish."
        return
    }
    if (!(Test-Path -LiteralPath $WebDest)) {
        Write-Host "Web root not found ($WebDest) - skipping FastDL publish (no IIS on this box?)."
        return
    }

    $fastDlDir = Join-Path $WebDest (Join-Path "mods" $ModName)
    $fastDlFf  = Join-Path $fastDlDir "mod.ff"

    Write-Host ""
    Write-Host "== FastDL =="
    if ($DryRun) {
        Write-Host "(dry run) would publish mod.ff -> $fastDlFf"
        return
    }
    New-Item -ItemType Directory -Force -Path $fastDlDir | Out-Null
    Copy-Item -LiteralPath $modFf -Destination $fastDlFf -Force
    $size = (Get-Item -LiteralPath $fastDlFf).Length
    Write-Host "Published mod.ff ($size bytes) -> $fastDlFf"
    Write-Host "Client fetch URL: <sv_wwwBaseURL>/mods/$ModName/mod.ff"
    Write-Host "If clients still can't download: confirm dedicated.cfg has a NON-empty" -ForegroundColor Yellow
    Write-Host "sv_wwwBaseURL and IIS serves the .ff MIME type (see docs/VPS_DEPLOY.md Phase 8)." -ForegroundColor Yellow
}

function Set-Maintenance {
    # Drop a short, SELF-EXPIRING marker the box watchdog (tools\vps_services\watchdog.ps1)
    # honors so a PLANNED restart doesn't page. Killing the bootstrapper makes the launcher
    # bat re-run `plutonium.exe -update-only`, which routinely takes ~2 min - long enough to
    # trip the watchdog's updater-wedge/staleness checks and fire a false alarm mid-deploy
    # (observed 2026-07-10). The marker stands the watchdog down for the window; it auto-
    # expires so an aborted deploy can never leave the watchdog disabled. Written into the
    # DEPLOYED mod folder ($ModDest), where the SYSTEM watchdog reads it - NOT the clone.
    param([int]$Minutes = 5, [string]$Reason = 'deploy')
    if ($DryRun) { return }
    $dir = Join-Path $ModDest "tools\vps_services"
    if (!(Test-Path -LiteralPath $dir)) { return }   # watchdog not deployed on this box
    $marker = Join-Path $dir "watchdog_maintenance.json"
    $until  = (Get-Date).AddMinutes($Minutes).ToString('o')
    (@{ until = $until; reason = $Reason } | ConvertTo-Json -Compress) |
        Set-Content -LiteralPath $marker -Encoding UTF8
    Write-Host "Watchdog maintenance window set ($Minutes min) - the planned restart won't page."
}

function Test-GamePortUp {
    # UDP 28960 bound = the game server is live and serving. The launcher bat only
    # opens it once the bootstrapper (not the -update-only step) is actually running.
    return [bool](Get-NetUDPEndpoint -LocalPort 28960 -ErrorAction SilentlyContinue)
}

function Get-UpdaterActivity {
    # Liveness of the update-only process (name exactly 'plutonium.exe', NOT the
    # 'plutonium-bootstrapper-win32.exe' game server - the exact filter never matches it).
    # Returns @{ Cpu = <CPU-seconds>; IO = <total read+write bytes> }, or $null when it
    # isn't running. A WEDGED updater is flat on BOTH; a LIVE update grows CPU (apply/verify)
    # or I/O (download) even when CPU is low. Requiring BOTH to be flat is what lets us kill
    # early without ever aborting a still-working update (the old CPU-only check had to wait
    # a conservative 150s because a network-bound download can sit at ~0 CPU).
    $wp = Get-CimInstance Win32_Process -Filter "Name='plutonium.exe'" -ErrorAction SilentlyContinue
    if (-not $wp) { return $null }
    $cpu = 0.0
    $p = Get-Process -Name plutonium -ErrorAction SilentlyContinue
    if ($p) { $cpu = ($p | Measure-Object -Property CPU -Sum).Sum }
    $io = 0.0
    foreach ($w in $wp) { $io += [double]$w.ReadTransferCount + [double]$w.WriteTransferCount }
    return @{ Cpu = $cpu; IO = $io }
}

function Wait-ForServerBack {
    # Killing the bootstrapper makes the launcher bat's :server loop re-run
    # `plutonium.exe -update-only` (normally ~2 min) BEFORE relaunching the server.
    # That update step occasionally WEDGES - flat CPU + flat I/O, port never opens, server
    # stays DOWN (observed 2026-07-10; recovered by hand with `Stop-Process -Name plutonium`).
    # Nothing else recovers it: the deploy's own watchdog-maintenance window suppresses the
    # box watchdog for exactly this span, so deploy OWNS the recovery. Poll for the game port;
    # if the updater goes FLAT on both CPU and I/O for a sustained streak (past a short warmup),
    # kill it so the bat loops on to launch the bootstrapper. The dual-signal + streak guard is
    # what keeps us from ever killing a working update, so the warmup can be short (~45s) instead
    # of the old blanket 150s wait - a wedge now heals in ~45-60s instead of ~170s.
    param(
        [int]$MinGraceSeconds = 45,    # never kill in the first 45s - the updater needs to spin up
        [int]$FlatKillSeconds = 40,    # sustained flat CPU *and* I/O beyond this => wedged
        [int]$CeilingSeconds  = 300    # hard stop - report failure past this
    )
    $sw   = [System.Diagnostics.Stopwatch]::StartNew()
    $poll = 5
    $prev = $null
    $flatFor = 0
    Write-Host "Waiting for the game server to come back (UDP 28960)..."
    while ($sw.Elapsed.TotalSeconds -lt $CeilingSeconds) {
        if (Test-GamePortUp) {
            Write-Host "Game server is back up (UDP 28960 listening after $([int]$sw.Elapsed.TotalSeconds)s)." -ForegroundColor Green
            return $true
        }
        $act = Get-UpdaterActivity
        if ($null -eq $act) {
            $prev = $null; $flatFor = 0        # updater not running (bootstrapper phase) - reset
        }
        else {
            if ($null -ne $prev) {
                $cpuAdvanced = ($act.Cpu - $prev.Cpu) -ge 1.0
                $ioAdvanced  = ($act.IO  - $prev.IO)  -ge 65536   # >=64KB moved => still downloading/applying
                if ($cpuAdvanced -or $ioAdvanced) { $flatFor = 0 } else { $flatFor += $poll }
            }
            $prev = $act
            if ($sw.Elapsed.TotalSeconds -ge $MinGraceSeconds -and $flatFor -ge $FlatKillSeconds) {
                Write-Host ("Updater appears WEDGED (plutonium.exe flat on CPU AND I/O for {0}s). Killing it so the bat relaunches the server..." -f $flatFor) -ForegroundColor Yellow
                Get-Process -Name plutonium -ErrorAction SilentlyContinue | Stop-Process -Force
                $prev = $null; $flatFor = 0
            }
        }
        Start-Sleep -Seconds $poll
    }
    return $false
}

function Restart-Server {
    if ($NoRestart -or $DryRun) {
        Write-Host "Skipping server restart$(if ($DryRun) { ' (dry run)' }) - relaunch manually to load the new mod."
        return
    }
    # 7 min (> Wait-ForServerBack's 5 min ceiling) so the recovery poll never runs past the
    # watchdog-maintenance window and trips a false page as it's healing a wedge.
    Set-Maintenance -Minutes 7 -Reason 'deploy'
    Write-Host "Restarting game server (the restart-loop bat relaunches it under the server account)..."
    # Use Get-Process/Stop-Process, NOT taskkill: under $ErrorActionPreference='Stop'
    # taskkill's stderr ("process not found", emitted when the server is already
    # down) is promoted to a terminating NativeCommandError and aborts the deploy
    # before it finishes. Get-Process -ErrorAction SilentlyContinue is clean.
    $boot = Get-Process -Name "plutonium-bootstrapper-win32" -ErrorAction SilentlyContinue
    if ($boot) {
        $boot | Stop-Process -Force
        Write-Host "Bootstrapper killed; the restart-loop bat will bring it back up."
        # Verify it actually returns, and auto-recover the known `-update-only` wedge
        # instead of leaving the server silently DOWN for a human to notice.
        if (-not (Wait-ForServerBack)) {
            Write-Host "Game server did NOT come back within 5 min - needs manual attention." -ForegroundColor Red
            Write-Host "On the box: Stop-Process -Name plutonium (clears a wedged updater), then confirm UDP 28960." -ForegroundColor Red
        }
    } else {
        Write-Host "Bootstrapper was NOT running - the game server is DOWN." -ForegroundColor Yellow
        Write-Host "Start it manually (your server start .bat). The restart loop only" -ForegroundColor Yellow
        Write-Host "relaunches after a kill; it cannot start a fully-stopped server." -ForegroundColor Yellow
    }
}

function Restart-Panel {
    # The RCON admin panel (GF-RconPanel scheduled task) runs `node server.js` straight out of the
    # mod folder we just mirrored, so a server.js change is only picked up when its node process is
    # recycled. Do it here so a -Mod deploy always leaves the panel and game on the SAME code - a
    # stale panel (old server.js, no /api/ack) is why command acks 404'd and showed false "timeout"
    # after a deploy. Non-disruptive: touches only the loopback admin tool, never the game/players.
    # No-op if the task isn't installed (e.g. deploying from a dev box); never fatal to the deploy.
    if ($NoRestart -or $DryRun) {
        Write-Host "Skipping RCON panel restart$(if ($DryRun) { ' (dry run)' })."
        return
    }
    $task = Get-ScheduledTask -TaskName "GF-RconPanel" -ErrorAction SilentlyContinue
    if (-not $task) { return }   # panel not installed on this box - nothing to do

    Write-Host "Restarting RCON panel (GF-RconPanel) to load the new server.js..."
    try {
        Stop-ScheduledTask -TaskName "GF-RconPanel" -ErrorAction SilentlyContinue
        # Stop-ScheduledTask only stops task-launched instances; kill any node still holding 3000
        # (e.g. one launched by the AtStartup trigger at boot) so Start relaunches on the new code.
        $c = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
        if ($c) { $c.OwningProcess | Select-Object -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } }
        Start-Sleep -Milliseconds 900
        Start-ScheduledTask -TaskName "GF-RconPanel" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        if (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue) {
            Write-Host "RCON panel restarted (listening on 127.0.0.1:3000)."
        } else {
            Write-Host "RCON panel restart: 3000 not listening yet - check the GF-RconPanel task." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "RCON panel restart failed (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Restart-BoxServices {
    # The box-side helper SERVICES (status_service, conn_logger, join-notify) run their
    # scripts straight out of THIS mod folder we just mirrored - so a -Mod deploy already
    # updates their code on disk. But they are load-once infinite loops (register_services.ps1),
    # so a changed script only takes effect when the process is RECYCLED. Bounce them here so a
    # -Mod deploy always leaves every box service on the SAME code as the mod, exactly like
    # Restart-Panel does for the RCON panel. Without this, box-side service edits deployed but
    # silently kept running the old code until the next reboot or manual restart.
    #   GF-Watchdog is deliberately EXEMPT: it is a short-lived task re-invoked every 3 min
    #   (register_services.ps1), so it re-reads its script on the next run with no restart.
    # Non-fatal and self-skipping: a task not installed on this box (e.g. a dev box) is ignored.
    if ($NoRestart -or $DryRun) {
        Write-Host "Skipping box-service restart$(if ($DryRun) { ' (dry run)' })."
        return
    }
    foreach ($name in @('GF-StatusService', 'GF-ConnLogger', 'GF-JoinNotify')) {
        if (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) { continue }
        try {
            Stop-ScheduledTask  -TaskName $name -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
            Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            Write-Host "Recycled $name (now on the deployed code)."
        } catch {
            Write-Host "$name restart failed (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
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
        (Join-Path $RepoRoot "raw"),
        # Runtime log dir written by the live server (untracked); see console_mp.log* below.
        (Join-Path $ModDest "logs")
    )
    # Gitignored per-box secret stores live IN the mod tree but aren't tracked, so the
    # source (deploy clone) doesn't have them; without /XF, /MIR would DELETE the copies
    # a box operator placed by hand. Exclude them by name so they survive every deploy.
    # (config.example.json / secrets.local.json.example are different names and still ship.)
    # console_mp.log* (+ logs\games_mp.log above) are the running server's own log files -
    # untracked, and held open by the process /MIR just restarted around, so purging them
    # is both wrong (not part of the deploy) and unreliable (ERROR 32, file in use).
    # Box-local RUNTIME state that lives in the mod tree but isn't tracked (the source clone
    # doesn't have it), so without /XF the /MIR would DELETE the live copy every deploy. That
    # churn also re-fired the watchdog's "already alerted" memory each deploy (duplicate pages).
    #   .dvarcache.json          - RCON panel's dvar cache
    #   .geocache.json           - RCON panel's ip-api geo cache. The box's ONE ip-api client, and the
    #                              free tier is 45 req/min - purging it makes every deploy re-fetch the
    #                              whole player set from cold. (Also PII-ish: it maps IPs to locations.)
    #   prefs.local.json         - RCON panel's UI state (the FAVORITES pinboard)
    #   watchdog_state.json      - watchdog's down/last-alert memory
    #   watchdog_maintenance.json- the deploy maintenance marker written just below in Restart-Server
    #   ignore.local.json        - players muted from the activity feed + ntfy (holds GUIDs, so untracked)
    #   security.local.json      - what GF-SecurityWatch TRUSTS (ssh key fingerprints). Deleting it would
    #                              silently drop the box back to trust-on-first-use, which re-adopts
    #                              whatever key is in use as "known" - i.e. a deploy would disarm the
    #                              highest-signal detector on the box without a word.
    #   security_state.json      - its event bookmarks + learned baseline. Purging it replays history and
    #                              re-adopts the current authorized_keys/firewall as the baseline.
    $xf = @("config.json", "secrets.local.json", "prefs.local.json", "ignore.local.json", "console_mp.log*",
            ".dvarcache.json", ".geocache.json", "watchdog_state.json", "watchdog_maintenance.json",
            "security.local.json", "security_state.json")
    Invoke-Robocopy -Source $RepoRoot -Destination $ModDest -ExtraArgs (@("/XD") + $xd + @("/XF") + $xf)
    Write-Host "Mod tree + mod.ff deployed$(if ($DryRun) { ' (dry run - nothing changed)' }) to $ModDest"

    Publish-FastDL

    Restart-Server
    Restart-Panel        # keep the admin panel's node process on the same code as the game
    Restart-BoxServices  # recycle the load-once box services (status/conn/join) onto the new code

    Write-Host ""
    Write-Host "NOTE: clients auto-download mod.ff via FastDL on join (sv_wwwBaseURL)." -ForegroundColor Yellow
    Write-Host "      They must still run the SAME Plutonium build as the server (FastDL" -ForegroundColor Yellow
    Write-Host "      ships the mod, not the engine). The release zip remains the fallback." -ForegroundColor Yellow
}

# --- main -------------------------------------------------------------------

if (!$Mod -and !$Web) {
    Write-Host "Nothing to do. Pass -Mod and/or -Web."
    Write-Host "  .\tools\deploy.ps1 -Web      # publish the website (no restart)"
    Write-Host "  .\tools\deploy.ps1 -Mod      # deploy the mod + restart the server & RCON panel"
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
