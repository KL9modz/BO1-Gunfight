# watchdog.ps1 - self-healing health check for the Gunfight VPS services (run ON the box)
# ------------------------------------------------------------------------------
# Windows Task Scheduler's own RestartOnFailure (999 tries, 1 min apart - see
# register_services.ps1) gives up after ~16.6 hours of back-to-back failures and
# then just sits there (State=Ready) until a human notices and restarts it by
# hand. That's what happened to GF-ConnLogger 2026-07-05 -> 2026-07-08.
#
# This script is the backstop: instead of relying on one exhaustible in-process
# retry budget, it is invoked FRESH on its own schedule (see the -Register
# trigger below), so each run starts a brand new retry budget. It:
#   1. Checks every GF-* helper task's State; restarts anything not Running.
#   2. Checks admin.json's LastWriteTime as a proxy for "is status_service AND
#      the actual dedicated server (via loopback RCON) still alive" - a hung/
#      crashed game server shows up here even if every task's State still says
#      Running (a wedged process doesn't necessarily exit).
#   2b. Judges the GAME SERVER by the plutonium-bootstrapper-win32 PROCESS + status
#      liveness, NOT by GF-GameServer's task State - because a GSC compile crash
#      (SV_Shutdown) drops the game exe while the task's cmd.exe/bat wrapper lives
#      on, so State stays Running while the server is DOWN. If the bat's own restart
#      loop is also wedged, nothing self-heals; the watchdog then bounces the task
#      (the manual fix that worked live 2026-07-12). See checks 3a/3b/3e.
#   3. Pushes an ntfy alert (reusing tools\notify\config.json's topic) on
#      transition into trouble, and again on recovery. While a problem
#      persists it re-alerts only every $ReAlertMinutes so a long outage
#      doesn't spam.
#
# State (what was already broken last run, so we know a transition happened)
# lives in watchdog_state.json next to this script - gitignored, box-local.
#
#   powershell -ExecutionPolicy Bypass -File watchdog.ps1
#   powershell -ExecutionPolicy Bypass -File watchdog.ps1 -WhatIf   # check only, no restarts/alerts
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string[]] $Tasks            = @('GF-GameServer', 'GF-JoinNotify', 'GF-RconPanel', 'GF-StatusService', 'GF-ConnLogger'),
    # The scheduled task that runs the game-server launch bat. Its process is the cmd.exe/bat
    # WRAPPER, which survives the game exe's death, so its State is a LIE about server health -
    # the process/RCON checks below are the truth. Named separately so it can be bounced directly.
    [string]   $GameServerTask   = 'GF-GameServer',
    [string]   $AdminJsonPath    = 'C:\inetpub\wwwroot\admin\live\admin.json',
    [string]   $HealthJsonPath   = 'C:\inetpub\wwwroot\admin\live\health.json',
    [int]      $AdminStaleSecs  = 90,
    # Beyond this, admin.json staleness escalates from ALERT to ACTIVE RECOVERY (kill the hung
    # server so the launcher loop restarts it). Must be > $AdminStaleSecs.
    [int]      $AdminHardStaleSecs = 300,
    # A plutonium.exe (updater/launcher) with NO bootstrapper child, older than this, is a
    # wedged `-update-only` (the bat is stuck on that step, server DOWN, task still Running).
    # Since 2026-08-11 the bat delegates that step to update_plutonium.ps1, which bounds and kills
    # the updater ITSELF, so this is now a backstop for the paths that script cannot cover (it is
    # missing / it crashed / something else started an updater), not the primary bound.
    [int]      $UpdaterWedgeSecs = 120,
    [int]      $ReAlertMinutes   = 20,
    [string]   $StatePath        = '',
    [string]   $MaintenancePath  = '',   # deploy.ps1 drops a self-expiring marker here to stand the watchdog down during a planned restart
    [string]   $NotifyConfigPath = '',
    [string]   $CfgPath          = '',   # dedicated.cfg (for the rcon password used by map_rotate)
    [int]      $PanelPort        = 3000, # RCON panel loopback port (single rcon pacer)
    [string]   $ModRootPath      = '',   # ...\storage\t5\mods\mp_gunfight (for log hygiene); derived if empty
    [int]      $LogArchiveBudgetMB = 400,# per-base cap on the engine's rolled <log>.NNN archive files (live file untouched)
    [int]      $LiveLogWarnMB    = 800,  # warn if a LIVE log grows past this (a flood dvar likely left on; restart rolls it)
    # Periodic tasks (short-lived, re-triggered) whose health check-1 cannot see: State=Ready is
    # their NORMAL state, so the Running check would false-alarm. Instead check 1b watches their
    # LastTaskResult and LastRunTime age. GF-Watchdog itself is deliberately absent - it cannot
    # judge itself mid-run; security_watch carries the reciprocal check on THIS task.
    [string[]] $PeriodicTasks    = @('GF-SecurityWatch'),
    [int]      $PeriodicMaxAgeMin = 15,  # 5x the 3-min cadence; a trigger that stopped firing shows here
    # RCON panel LIVENESS (check 1c). Task state alone cannot see a hung node process, and the
    # failure is insidious: status_service falls back to direct rcon so admin.json stays fresh
    # and check 2 never fires - meanwhile geo, conn_logger's fallback, and THIS script's own
    # map_rotate remediation are all dead. Probe = one HTTP GET of a static asset (zero rcon).
    [int]      $PanelProbeFailsToAct = 2, # consecutive failed probes before bouncing the task
    # Plutonium update drift (check 5). The launch bat applies updates (bounded) at wrapper
    # start; THIS is the policy for when to restart: new CDN revision + empty server. Endpoint is
    # the one mxve/plutonium-updater defaults to; local truth is the updater's own info.json.
    [string]   $PlutoCdnInfoUrl  = 'https://cdn.plutoniummod.com/updater/prod/info.json',
    # Plutonium install root (holds the updater's info.json). Empty = derived from the t5 storage
    # tree at runtime - which is only correct when running from the DEPLOYED mirror; a repo-clone
    # run derives garbage (the carry.ps1 location trap), so tests pass this explicitly.
    [string]   $PlutoRootPath    = '',
    [int]      $UpdateCheckEveryMin = 30,
    [switch]   $NoRemediate,             # detect + alert only; never kill/rotate (like the old behavior)
    [switch]   $WhatIf
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot '..\common.ps1')   # Resolve-*Root / Get-RconPassword
if (-not $StatePath)        { $StatePath        = Join-Path $scriptRoot 'watchdog_state.json' }
if (-not $MaintenancePath)  { $MaintenancePath  = Join-Path $scriptRoot 'watchdog_maintenance.json' }
if (-not $NotifyConfigPath) { $NotifyConfigPath = Join-Path (Split-Path -Parent $scriptRoot) 'notify\config.json' }
# ...\mp_gunfight (the mod root, where the engine writes console_mp.log and, under logs\,
# games_mp.log) and ...\storage\t5 (dedicated.cfg), both from common.ps1's fixed location.
if (-not $ModRootPath)      { $ModRootPath      = Resolve-ModRoot }
if (-not $CfgPath)          { $CfgPath          = Join-Path (Resolve-T5Root) 'dedicated.cfg' }

function Log($msg) {
    # Write-Host is not lost: run_service.ps1 (the task launcher since 2026-08-02) captures
    # every stream to storage\t5\logs\services\GF-Watchdog.log - before that, this narration
    # went to a hidden window and a restart the watchdog performed left no durable record.
    $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$t] $msg"
}

# Age in seconds of a file that ANOTHER process rewrites continuously, or $null if it isn't there.
# ⚠ Never do `if (Test-Path $p) { (Get-Item $p)... }` on one of these: that is two statements with a
# gap, and status_service replaces its snapshots with `Move-Item -Force`, which on Windows DELETES
# the destination and then moves - so admin.json genuinely blinks out of existence several times a
# minute. Land in that window and Get-Item throws PathNotFound, which under $ErrorActionPreference
# 'Stop' kills the whole run. That is exactly what happened 2026-08-14 02:29:04: check 2 read
# admin.json fine, check 3b missed it in the SAME second, the watchdog exited 1, and GF-SecurityWatch's
# reciprocal dead-man check paged "WATCHDOG down" for what was a self-healing 35s blip. One tolerant
# stat, null-guarded by the caller ([[watchdog-toctou-on-atomically-replaced-json]]).
#
# ⚠ That replace window has TWO failure modes and the fix above only covered one. The second bit
# 2026-08-17 08:38:03: the file EXISTED but its LastWriteTime read as the ZERO FILETIME
# (1601-01-01), so the age came back 13,431,458,283s (425 YEARS), [int] overflowed, and the run
# died exactly as before - GF-SecurityWatch paged "WATCHDOG down" for another self-healing 28s blip.
# ⚠⚠ Do NOT "fix" this by widening to [long]: that is WORSE THAN THE CRASH. A 425-year age is not
# just a big number, it reads as catastrophically stale - and $hardAge feeds check 3b, which KILLS
# THE BOOTSTRAPPER to recover a "hung" server. You would trade 28s of blind monitoring for a real,
# unnecessary game-server restart on a perfectly healthy box.
# An implausible timestamp is not data, it is a FAILED STAT: report it as unknown (same as a missing
# file, same null-guarded callers) and let the next 3-minute run settle it. Small negatives are
# deliberately ALLOWED through - clock granularity can put a just-written file microseconds in the
# future, and the callers read a negative as "fresh", which it is.
function Get-FileAgeSeconds($path) {
    $item = Get-Item $path -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $secs = (New-TimeSpan -Start $item.LastWriteTime -End (Get-Date)).TotalSeconds
    if ($secs -gt 315360000 -or $secs -lt -86400) { return $null }   # >10y stale or >1d future
    return [int]$secs
}

# ---- log hygiene -------------------------------------------------------------
# The engine appends to a single live log (games_mp.log via g_logSync 1; console_mp.log) and rolls
# it to <base>.000, .001, ... when it hits its own size cap. Those rolled files are CLOSED (the
# server has moved on), but NOTHING prunes them, so uptime alone - and much faster, a chatty
# diagnostic dvar - grows the mods folder without bound (we found 1.2 GB of console_mp.log.NNN).
# Prune the closed rolls to a per-base byte budget, newest-first. The LIVE file is NEVER touched
# (the server holds its handle open; only a restart safely rolls it) - we just warn if it gets big.
function Trim-EngineLogArchive($dir, $base, $budgetMB) {
    if (-not (Test-Path $dir)) { return }
    $rolls = Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match ('^' + [regex]::Escape($base) + '\.\d+$') } |
             Sort-Object LastWriteTime -Descending
    if (-not $rolls) { return }
    $budget = [long]$budgetMB * 1MB
    $running = [long]0
    foreach ($f in $rolls) {
        $running += $f.Length
        if ($running -le $budget) { continue }
        $mb = [math]::Round($f.Length / 1MB, 1)
        if ($WhatIf) { Log "would prune log archive $($f.Name) (${mb}MB, over ${budgetMB}MB budget)"; continue }
        try { Remove-Item $f.FullName -Force -ErrorAction Stop; Log "pruned log archive $($f.Name) (${mb}MB)" }
        catch { Log "prune FAILED $($f.Name): $($_.Exception.Message)" }
    }
}

# ---- deploy maintenance window ------------------------------------------------
# deploy.ps1 -Mod restarts the game server (kills the bootstrapper); the launcher
# bat then re-runs `plutonium.exe -update-only`, which routinely takes long enough
# to trip the updater-wedge / staleness checks below and page a FALSE alarm in the
# middle of a planned deploy (observed 2026-07-10). deploy.ps1 drops a short,
# self-expiring marker here so a PLANNED restart stands the watchdog down (no kill,
# no alert) until the window passes; a real outage AFTER expiry is still caught on
# the next 3-min run. Self-expiring by design so a crashed/aborted deploy can never
# leave the watchdog disabled - a stale marker past its `until` is deleted here.
if (Test-Path $MaintenancePath) {
    try {
        $mw = Get-Content $MaintenancePath -Raw | ConvertFrom-Json
        $until = [datetime]$mw.until
        if ((Get-Date) -lt $until) {
            Log ("maintenance window active (reason=$($mw.reason)) until {0:HH:mm:ss} - skipping all checks" -f $until)
            return
        }
        Log 'maintenance window expired - removing marker, resuming normal checks'
        Remove-Item $MaintenancePath -Force -ErrorAction SilentlyContinue
    } catch {
        Log "maintenance marker unreadable ($($_.Exception.Message)) - ignoring it"
    }
}

# ---- ntfy alert (plain HTTP POST, no node dependency) ------------------------
function Send-Alert($title, $message, $priority, $tags) {
    if (-not (Test-Path $NotifyConfigPath)) {
        Log "ALERT (no notify config, not sent): $title - $message"
        return
    }
    try {
        $cfg = Get-Content $NotifyConfigPath -Raw | ConvertFrom-Json
        $topic = $cfg.ntfyTopic
        $server = if ($cfg.ntfyServer) { $cfg.ntfyServer.TrimEnd('/') } else { 'https://ntfy.sh' }
        if (-not $topic) { Log "ALERT (no ntfyTopic configured, not sent): $title - $message"; return }
        $headers = @{ Title = $title; Priority = $priority; Tags = $tags }
        if ($cfg.ntfyToken) { $headers['Authorization'] = 'Bearer ' + $cfg.ntfyToken }
        Invoke-RestMethod -Uri "$server/$topic" -Method Post -Headers $headers `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($message)) -TimeoutSec 10 | Out-Null
        Log "ALERT sent: $title - $message"
    } catch {
        Log "ALERT send FAILED ($($_.Exception.Message)): $title - $message"
    }
}

# ---- issue an rcon command THROUGH the panel (the single box-side rcon pacer) ----
# Never send raw rcon here: the project rule is exactly one process owns the ~1-reply-
# per-0.7s pacing (the panel). map_rotate goes on the panel's priority lane.
function Send-PanelRcon($command) {
    try {
        $pw = Get-RconPassword -CfgPath $CfgPath   # box-local, never logged (env GF_RCON_PW wins)
        if (-not $pw) { Log "Send-PanelRcon: no rcon password in $CfgPath"; return $false }
        # Shared POST (common.ps1's Invoke-GfPanelRcon); this wrapper owns the policy — password
        # resolution, the bool return, and logging a failure instead of throwing.
        $r = Invoke-GfPanelRcon -Pw $pw -Command $command -PanelPort $PanelPort -TimeoutSec 12
        return [bool]$r.ok
    } catch {
        Log "Send-PanelRcon('$command') failed: $($_.Exception.Message)"
        return $false
    }
}

# ---- state persistence -------------------------------------------------------
function Load-State {
    if (Test-Path $StatePath) {
        try { return (Get-Content $StatePath -Raw | ConvertFrom-Json) } catch { }
    }
    return [PSCustomObject]@{ items = @{} }
}
function Save-State($state) {
    $state | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8
}

$state = Load-State
if (-not $state.items) { $state | Add-Member -NotePropertyName items -NotePropertyValue @{} -Force }
$itemsHash = @{}
foreach ($p in $state.items.PSObject.Properties) { $itemsHash[$p.Name] = $p.Value }

function Get-Item-State($key) {
    if ($itemsHash.ContainsKey($key)) { return $itemsHash[$key] }
    return [PSCustomObject]@{ down = $false; lastAlert = $null }
}
function Set-Item-State($key, $down, $lastAlert) {
    $itemsHash[$key] = [PSCustomObject]@{ down = $down; lastAlert = $lastAlert }
}

function Should-Alert($key, $isDown) {
    $prev = Get-Item-State $key
    $now = Get-Date
    if ($isDown) {
        if (-not $prev.down) { return $true }   # just went down: always alert
        if ($prev.lastAlert -and ((New-TimeSpan -Start ([datetime]$prev.lastAlert) -End $now).TotalMinutes -lt $ReAlertMinutes)) {
            return $false                          # still down, too soon to re-alert
        }
        return $true                                # still down, re-alert cadence elapsed
    } else {
        return [bool]$prev.down                     # alert once on recovery
    }
}

$anyProblem = $false

# ---- 1. task state check ------------------------------------------------------
foreach ($taskName in $Tasks) {
    $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $t) {
        Log "$taskName - NOT REGISTERED (skipping)"
        continue
    }
    $isDown = ($t.State -ne 'Running')
    if ($isDown) {
        $anyProblem = $true
        Log "$taskName - DOWN (State=$($t.State))"
        if (-not $WhatIf) {
            try {
                Start-ScheduledTask -TaskName $taskName
                Log "$taskName - restart issued"
            } catch {
                Log "$taskName - restart FAILED: $($_.Exception.Message)"
            }
        }
        if (-not $WhatIf -and (Should-Alert $taskName $true)) {
            Send-Alert -title "Gunfight VPS - $taskName down" `
                -message "$taskName was not running (State=$($t.State)). Restart issued." `
                -priority 'high' -tags 'warning,robot'
            Set-Item-State $taskName $true (Get-Date).ToString('o')
        } elseif (-not $WhatIf) {
            Set-Item-State $taskName $true (Get-Item-State $taskName).lastAlert
        }
    } else {
        Log "$taskName - OK (Running)"
        if (-not $WhatIf -and (Should-Alert $taskName $false)) {
            Send-Alert -title "Gunfight VPS - $taskName recovered" `
                -message "$taskName is running again." -priority 'default' -tags 'white_check_mark'
        }
        if (-not $WhatIf) { Set-Item-State $taskName $false $null }
    }
}

# ---- 1b. periodic-task health (the tasks check 1 is structurally blind to) ----
# A periodic task that starts FAILING (nonzero LastTaskResult) or whose trigger stops firing
# (stale LastRunTime) dies silently: State=Ready is its normal state, so nothing above notices.
# For GF-SecurityWatch that silence means ALL security alerting is gone. 0x41301 (267009) =
# "currently running" and 0x41303 = "has not yet run" are not failures.
foreach ($ptName in $PeriodicTasks) {
    $pt = Get-ScheduledTask -TaskName $ptName -ErrorAction SilentlyContinue
    if (-not $pt) { Log "$ptName - NOT REGISTERED (periodic; skipping)"; continue }
    $pi = Get-ScheduledTaskInfo -TaskName $ptName -ErrorAction SilentlyContinue
    $ageMin = if ($pi.LastRunTime) { [int]((Get-Date) - $pi.LastRunTime).TotalMinutes } else { 9999 }
    $badResult = ($pi.LastTaskResult -ne 0 -and $pi.LastTaskResult -ne 267009 -and $pi.LastTaskResult -ne 267011)
    $isDown = ($ageMin -gt $PeriodicMaxAgeMin) -or $badResult
    $key = "periodic-$ptName"
    if ($isDown) {
        $anyProblem = $true
        $why = if ($badResult) { "LastTaskResult=0x$('{0:X}' -f $pi.LastTaskResult)" } else { "last ran ${ageMin} min ago (cadence 3 min)" }
        Log "$ptName - UNHEALTHY: $why"
        if (-not $WhatIf -and -not $NoRemediate) { try { Start-ScheduledTask -TaskName $ptName; Log "$ptName - start issued" } catch { Log "$ptName - start FAILED: $($_.Exception.Message)" } }
        if (-not $WhatIf -and (Should-Alert $key $true)) {
            Send-Alert -title "Gunfight VPS - $ptName unhealthy" `
                -message "$ptName : $why. $(if(-not $NoRemediate){'Start issued.'}else{'Remediation disabled.'}) If this is SecurityWatch, security alerting was dark for that window." `
                -priority 'high' -tags 'warning,robot'
            Set-Item-State $key $true (Get-Date).ToString('o')
        } elseif (-not $WhatIf) { Set-Item-State $key $true (Get-Item-State $key).lastAlert }
    } else {
        Log "$ptName - OK (last ran ${ageMin} min ago, result 0x$('{0:X}' -f $pi.LastTaskResult))"
        if (-not $WhatIf -and (Should-Alert $key $false)) {
            Send-Alert -title "Gunfight VPS - $ptName healthy again" -message "$ptName is running on schedule again." -priority 'default' -tags 'white_check_mark'
        }
        if (-not $WhatIf) { Set-Item-State $key $false $null }
    }
}

# ---- 1c. RCON panel LIVENESS (an HTTP probe; task state cannot see a hung node) ----
# Insidious failure: a wedged panel leaves admin.json FRESH (status_service falls back to direct
# rcon), so check 2 stays green while geo/flags, conn_logger's fallback and this script's own
# map_rotate remediation are all quietly dead. One GET of a static asset costs zero rcon.
$panelKey = 'panel-liveness'
$panelOk = $false
try {
    $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "http://127.0.0.1:$PanelPort/" `
                              -Headers @{ Host = "127.0.0.1:$PanelPort" }
    $panelOk = ($resp.StatusCode -eq 200)
} catch { $panelOk = $false }
# Consecutive-fail counter lives as a plain int directly on $state (Save-State serializes the
# whole object) - the items store is for down/lastAlert pairs, not counters.
$probeFails = 0
if ($state.PSObject.Properties.Name -contains 'panelProbeFails') { $probeFails = [int]$state.panelProbeFails }
if ($panelOk) {
    if ($probeFails -gt 0) { Log "panel probe OK again (was failing x$probeFails)" } else { Log 'panel probe OK' }
    $state | Add-Member -NotePropertyName panelProbeFails -NotePropertyValue 0 -Force
    if (-not $WhatIf -and (Should-Alert $panelKey $false)) {
        Send-Alert -title 'Gunfight VPS - panel responsive again' -message 'The RCON panel is answering HTTP again.' -priority 'default' -tags 'white_check_mark'
    }
    if (-not $WhatIf) { Set-Item-State $panelKey $false $null }
} else {
    $probeFails++
    $state | Add-Member -NotePropertyName panelProbeFails -NotePropertyValue $probeFails -Force
    $anyProblem = $true
    Log "panel probe FAILED (consecutive: $probeFails/$PanelProbeFailsToAct)"
    if ($probeFails -ge $PanelProbeFailsToAct) {
        if (-not $WhatIf -and -not $NoRemediate) {
            try { Restart-GfScheduledTask -TaskName 'GF-RconPanel'; Log 'bounced GF-RconPanel' }
            catch { Log "GF-RconPanel bounce FAILED: $($_.Exception.Message)" }
        }
        if (-not $WhatIf -and (Should-Alert $panelKey $true)) {
            Send-Alert -title 'Gunfight VPS - panel hung' `
                -message "The RCON panel task is Running but HTTP on :$PanelPort failed $probeFails checks in a row. $(if(-not $NoRemediate){'Bounced the task.'}else{'Remediation disabled.'}) While hung: no geo, no conn_logger fallback, no watchdog map_rotate." `
                -priority 'high' -tags 'warning,robot'
            Set-Item-State $panelKey $true (Get-Date).ToString('o')
        } elseif (-not $WhatIf) { Set-Item-State $panelKey $true (Get-Item-State $panelKey).lastAlert }
    }
}

# ---- 2. admin.json freshness (proxy for "is the live game server responding") ----
$adminKey = 'admin.json-staleness'
$age = Get-FileAgeSeconds $AdminJsonPath
if ($null -ne $age) {
    $isStale = $age -gt $AdminStaleSecs
    if ($isStale) {
        $anyProblem = $true
        Log "admin.json STALE (age=$([int]$age)s > $AdminStaleSecs s) - status_service and/or the live game server may be unresponsive"
        if (-not $WhatIf -and (Should-Alert $adminKey $true)) {
            Send-Alert -title 'Gunfight VPS - server/status unresponsive' `
                -message "admin.json hasn't updated in $([int]$age)s. status_service or the dedicated server (RCON) may be down/hung." `
                -priority 'urgent' -tags 'rotating_light'
            Set-Item-State $adminKey $true (Get-Date).ToString('o')
        } elseif (-not $WhatIf) {
            Set-Item-State $adminKey $true (Get-Item-State $adminKey).lastAlert
        }
    } else {
        Log "admin.json fresh (age=$([int]$age)s)"
        if (-not $WhatIf -and (Should-Alert $adminKey $false)) {
            Send-Alert -title 'Gunfight VPS - server/status recovered' `
                -message 'admin.json is updating again.' -priority 'default' -tags 'white_check_mark'
        }
        if (-not $WhatIf) { Set-Item-State $adminKey $false $null }
    }
} else {
    Log "admin.json not found at $AdminJsonPath (skipping staleness check)"
}

# ---- 3. active remediation (repairs, not just alerts) ------------------------
# The checks above ALERT; these ACT on the failure modes that alerting alone can't fix.
# All destructive actions are gated by (-not $WhatIf -and -not $NoRemediate).
$canAct = (-not $WhatIf -and -not $NoRemediate)

$boot = @(Get-Process -Name 'plutonium-bootstrapper-win32' -ErrorAction SilentlyContinue)
$upd  = @(Get-Process -Name 'plutonium'                    -ErrorAction SilentlyContinue)

# Set when 3a kills a wedged updater this run, so 3e gives the bat one full cycle to relaunch
# from that lighter touch before escalating to a whole-task restart.
$updaterRemediatedThisRun = $false

# (3a) WEDGED UPDATER. If `plutonium.exe -update-only` hangs, the bat is stuck on that step with
# NO game server, yet GF-GameServer stays State=Running (the task can't see it). Signature:
# plutonium.exe present, bootstrapper absent, past a normal update download. Kill it -> bat advances.
# BACKSTOP ONLY since 2026-08-11: the bat's update step is update_plutonium.ps1, which skips the
# updater entirely when the local revision already equals the CDN's, and otherwise waits for the
# revision to LAND and then kills it. A genuinely long update (a first install) stands this whole
# watchdog down behind that script's maintenance marker, so it cannot be reclaimed mid-download.
if ($upd.Count -gt 0 -and $boot.Count -eq 0) {
    $oldest = ($upd | Sort-Object StartTime | Select-Object -First 1)
    $ageSec = [int]((Get-Date) - $oldest.StartTime).TotalSeconds
    if ($ageSec -ge $UpdaterWedgeSecs) {
        $anyProblem = $true
        Log "updater WEDGE: plutonium.exe up ${ageSec}s with no game server"
        if ($canAct) {
            $updaterRemediatedThisRun = $true
            try { $upd | Stop-Process -Force; Log 'killed wedged plutonium.exe (bat loop will relaunch the server)' }
            catch { Log "kill failed: $($_.Exception.Message)" }
        }
        if (-not $WhatIf -and (Should-Alert 'updater-wedge' $true)) {
            Send-Alert -title 'Gunfight VPS - updater wedged' `
                -message "plutonium.exe hung ${ageSec}s with no game server. $(if($canAct){'Killed it so the launcher loop restarts the server.'}else{'Remediation disabled.'})" `
                -priority 'urgent' -tags 'rotating_light,robot'
            Set-Item-State 'updater-wedge' $true (Get-Date).ToString('o')
        } elseif (-not $WhatIf) { Set-Item-State 'updater-wedge' $true (Get-Item-State 'updater-wedge').lastAlert }
    }
} elseif ($boot.Count -gt 0) {
    # Genuine recovery only when the game server is actually back. The old bare `else` also fired
    # here when BOTH processes were absent (server DOWN, not the wedge signature) - a false
    # "recovered". That down-with-no-updater state is now owned by check 3e below.
    if (-not $WhatIf -and (Should-Alert 'updater-wedge' $false)) {
        Send-Alert -title 'Gunfight VPS - updater recovered' -message 'Game server process is up again.' -priority 'default' -tags 'white_check_mark'
    }
    if (-not $WhatIf) { Set-Item-State 'updater-wedge' $false $null }
}

# (3b) HUNG SERVER. admin.json stale past the HARD threshold while the bootstrapper is alive =
# the server is running but not answering RCON/status (a true hang, not a between-launch gap or
# the updater wedge handled above). Kill the bootstrapper so the bat's restart loop starts fresh.
$hardAge = Get-FileAgeSeconds $AdminJsonPath
if ($null -ne $hardAge) {
    if ($hardAge -gt $AdminHardStaleSecs -and $boot.Count -gt 0) {
        $anyProblem = $true
        Log "server HUNG: admin.json ${hardAge}s stale AND bootstrapper alive"
        if ($canAct) {
            try { $boot | Stop-Process -Force; Log 'killed hung bootstrapper (bat loop will relaunch)' }
            catch { Log "kill failed: $($_.Exception.Message)" }
        }
        if (-not $WhatIf -and (Should-Alert 'server-hung' $true)) {
            Send-Alert -title 'Gunfight VPS - server hung' `
                -message "No RCON/status for ${hardAge}s while the process was alive. $(if($canAct){'Killed it so the launcher loop starts a fresh server.'}else{'Remediation disabled.'})" `
                -priority 'urgent' -tags 'rotating_light,robot'
            Set-Item-State 'server-hung' $true (Get-Date).ToString('o')
        } elseif (-not $WhatIf) { Set-Item-State 'server-hung' $true (Get-Item-State 'server-hung').lastAlert }
    } elseif ($hardAge -le $AdminStaleSecs) {
        if (-not $WhatIf -and (Should-Alert 'server-hung' $false)) {
            Send-Alert -title 'Gunfight VPS - server responsive again' -message 'RCON/status is updating again.' -priority 'default' -tags 'white_check_mark'
        }
        if (-not $WhatIf) { Set-Item-State 'server-hung' $false $null }
    }
}

# (3e) DEAD SERVER, TASK STILL "RUNNING" (the compile-crash class - the case task-state check 1
# is blind to by construction). A GSC compile error (or any hard crash) drops the game exe ->
# SV_Shutdown, but GF-GameServer's cmd.exe/bat WRAPPER survives, so its State stays Running while
# the server is DOWN. If the bat's own restart loop is also wedged, nothing relaunches. The only
# truthful signals are the PROCESS (no bootstrapper) and STATUS liveness (admin.json dark). We
# escalate to a full task restart only once the server has been dark past the HARD threshold - a
# full watchdog cycle beyond 3a's lighter "kill the wedged updater and trust the bat" attempt, so
# a bat that can self-heal already had its chance. Deliberately NOT conditioned on plutonium.exe:
# the crash can leave a stray launcher (3a's target) or none, and either way a wedged bat needs
# the task bounced - the manual fix used live 2026-07-12 (Stop/Start the task + clear strays).
$darkAge = Get-FileAgeSeconds $AdminJsonPath
$serverDark = $false
if ($null -eq $darkAge) { $darkAge = 0 }
else { $serverDark = ($darkAge -gt $AdminHardStaleSecs) }
$gsTask = Get-ScheduledTask -TaskName $GameServerTask -ErrorAction SilentlyContinue
if ($boot.Count -eq 0 -and $serverDark -and $gsTask -and $gsTask.State -eq 'Running' -and -not $updaterRemediatedThisRun) {
    $anyProblem = $true
    Log "server DEAD but $GameServerTask still Running: no bootstrapper, status dark ${darkAge}s (compile-crash class) - the bat is not self-recovering"
    if ($canAct) {
        # Clear any stray launcher (re-query fresh; the $upd snapshot may be stale), then bounce the task.
        @(Get-Process -Name 'plutonium' -ErrorAction SilentlyContinue) | Stop-Process -Force -ErrorAction SilentlyContinue
        try {
            Stop-ScheduledTask  -TaskName $GameServerTask -ErrorAction SilentlyContinue
            Start-ScheduledTask -TaskName $GameServerTask
            Log "restarted the $GameServerTask task (fresh bat wrapper)"
        } catch {
            Log "$GameServerTask restart FAILED: $($_.Exception.Message)"
        }
    }
    if (-not $WhatIf -and (Should-Alert 'server-dead' $true)) {
        Send-Alert -title 'Gunfight VPS - server dead (task still Running)' `
            -message "No game-server process and status dark ${darkAge}s while $GameServerTask reported Running (a GSC compile crash looks exactly like this). $(if($canAct){"Bounced the $GameServerTask task to relaunch."}else{'Remediation disabled.'})" `
            -priority 'urgent' -tags 'rotating_light,robot'
        Set-Item-State 'server-dead' $true (Get-Date).ToString('o')
    } elseif (-not $WhatIf) { Set-Item-State 'server-dead' $true (Get-Item-State 'server-dead').lastAlert }
} elseif ($boot.Count -gt 0) {
    # Recovery only when the game server process is genuinely back (Should-Alert gates it to a real
    # prior 'server-dead'); we hold the down-state through transient boot-absent runs (e.g. 3a just
    # acted) so the alert doesn't clear before the bootstrapper actually returns.
    if (-not $WhatIf -and (Should-Alert 'server-dead' $false)) {
        Send-Alert -title 'Gunfight VPS - server process back' -message 'The game server process is running again.' -priority 'default' -tags 'white_check_mark'
    }
    if (-not $WhatIf) { Set-Item-State 'server-dead' $false $null }
}

# (3c) STUCK MATCH. The server answers but the round number is frozen (health.roundStuck).
# The in-GSC watchdog should already have force-ended it (~65s); this is the box backstop.
# Nudge with map_rotate via the panel (fresh onStartGameType). Gated to once per episode /
# every $ReAlertMinutes by Should-Alert so it never rotate-spams.
$health = $null
if (Test-Path $HealthJsonPath) {
    try { $health = Get-Content $HealthJsonPath -Raw | ConvertFrom-Json } catch { }
}
if ($health -and $health.roundStuck) {
    $anyProblem = $true
    Log "match STUCK: round $($health.round) unchanged $([int]$health.secsSinceRoundChange)s (humans=$($health.humans))"
    if (Should-Alert 'match-stuck' $true) {
        $rotated = $false
        if ($canAct) { $rotated = Send-PanelRcon 'map_rotate'; Log ("map_rotate via panel: " + $(if ($rotated) { 'sent' } else { 'FAILED' })) }
        if (-not $WhatIf) {
            Send-Alert -title 'Gunfight VPS - match stuck' `
                -message "Round $($health.round) hasn't advanced in $([int]$health.secsSinceRoundChange)s with $($health.humans) player(s). $(if($canAct){"Issued map_rotate ($(if($rotated){'ok'}else{'failed'}))."}else{'Remediation disabled.'}) The in-game watchdog should also self-heal this." `
                -priority 'high' -tags 'warning,robot'
            Set-Item-State 'match-stuck' $true (Get-Date).ToString('o')
        }
    }
} else {
    if (-not $WhatIf -and (Should-Alert 'match-stuck' $false)) {
        Send-Alert -title 'Gunfight VPS - match cycling again' -message 'Rounds are advancing again.' -priority 'default' -tags 'white_check_mark'
    }
    if (-not $WhatIf) { Set-Item-State 'match-stuck' $false $null }
}

# ---- 5. Plutonium update drift (keep the server current WITHOUT a per-restart updater) ----
# Mechanism grounded 2026-08-10: the official updater maintains {revision} in
# <Plutonium root>\info.json, and the CDN advertises {revision} at $PlutoCdnInfoUrl (the endpoint
# mxve/plutonium-updater defaults to). "Update available" is a two-integer compare over one
# HTTPS GET. The launch bat applies updates (bounded, once per wrapper start), so the POLICY here
# is: drift + EMPTY server -> bounce GF-GameServer under a short maintenance marker (the bat
# updates on the way up); players on -> alert once per revision and wait for empty.
# Rate-limited to every $UpdateCheckEveryMin so we are polite to the CDN. Path note: the watchdog
# runs as SYSTEM, so $env:LOCALAPPDATA is the WRONG profile - derive the Plutonium root from the
# t5 storage tree instead (same location-derivation trap as carry.ps1 documented).
$doUpdateCheck = $true
if ($state.PSObject.Properties.Name -contains 'updateCheckAt' -and $state.updateCheckAt) {
    try { $doUpdateCheck = ((Get-Date) - [datetime]$state.updateCheckAt).TotalMinutes -ge $UpdateCheckEveryMin } catch { }
}
if ($doUpdateCheck) {
    $state | Add-Member -NotePropertyName updateCheckAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
    try {
        $plutoRoot = $PlutoRootPath
        if ([string]::IsNullOrEmpty($plutoRoot)) {
            $t5 = Resolve-T5Root
            if ([string]::IsNullOrEmpty($t5)) { throw 'Resolve-T5Root returned empty (running outside the deployed mirror?) - pass -PlutoRootPath' }
            $plutoRoot = Split-Path -Parent (Split-Path -Parent $t5)   # ...\storage\t5 -> ...\Plutonium
        }
        $localInfo = Join-Path $plutoRoot 'info.json'
        if (Test-Path $localInfo) {
            $localRev = [int](Get-Content $localInfo -Raw | ConvertFrom-Json).revision
            $cdnRev   = [int](Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 -Uri $PlutoCdnInfoUrl).revision
            if ($cdnRev -gt $localRev) {
                $anyProblem = $true
                $humans = if ($health -and $null -ne $health.humans) { [int]$health.humans } else { -1 }
                Log "UPDATE AVAILABLE: local r$localRev -> cdn r$cdnRev (humans=$humans)"
                $alreadyAlerted = ($state.PSObject.Properties.Name -contains 'updateAlertRev' -and [int]$state.updateAlertRev -eq $cdnRev)
                if ($humans -eq 0 -and -not $WhatIf -and -not $NoRemediate) {
                    # Empty server: restart now. The marker mutes the OTHER checks for the planned
                    # window (this run continues; the next runs skip while the bat updates+relaunches).
                    Write-GfMaintenanceMarker -Dir $scriptRoot -Minutes 8 -Reason "plutonium update r$localRev -> r$cdnRev" | Out-Null
                    @(Get-Process -Name 'plutonium' -ErrorAction SilentlyContinue) | Stop-Process -Force -ErrorAction SilentlyContinue
                    try {
                        Stop-ScheduledTask -TaskName $GameServerTask -ErrorAction SilentlyContinue
                        @(Get-Process -Name 'plutonium-bootstrapper-win32' -ErrorAction SilentlyContinue) | Stop-Process -Force -ErrorAction SilentlyContinue
                        Start-ScheduledTask -TaskName $GameServerTask
                        Log "bounced $GameServerTask for the update (bat applies it on the way up)"
                        Send-Alert -title 'Gunfight VPS - updating Plutonium' `
                            -message "New Plutonium revision r$cdnRev (was r$localRev). Server was empty - restarted to apply. Back in ~2 min." `
                            -priority 'default' -tags 'arrows_counterclockwise,robot'
                        $state | Add-Member -NotePropertyName updateAlertRev -NotePropertyValue $cdnRev -Force
                    } catch { Log "update bounce FAILED: $($_.Exception.Message)" }
                } elseif (-not $alreadyAlerted -and -not $WhatIf) {
                    Send-Alert -title 'Gunfight VPS - Plutonium update pending' `
                        -message "New revision r$cdnRev available (running r$localRev). $humans player(s) on - will auto-apply at the next empty check. A stale build can break NEW clients, so don't sit on it for days." `
                        -priority 'default' -tags 'information_source'
                    $state | Add-Member -NotePropertyName updateAlertRev -NotePropertyValue $cdnRev -Force
                }
            } else {
                Log "plutonium current (r$localRev = cdn r$cdnRev)"
            }
        } else { Log "update check skipped: $localInfo not found" }
    } catch { Log "update check failed (non-fatal): $($_.Exception.Message)" }
}

# (4) LOG HYGIENE. Prune the engine's CLOSED rolled log archives to a per-base budget so a
# diagnostic dvar left on (or plain uptime) can't fill the disk; the live handle is untouched.
# This is what makes leaving GF_TEAMTRACE on - and flipping a flood dvar on for an investigation -
# safe. Runs regardless of $anyProblem; it's independent of server health.
$modLogsDir = Join-Path $ModRootPath 'logs'
Trim-EngineLogArchive $modLogsDir  'games_mp.log'   $LogArchiveBudgetMB
Trim-EngineLogArchive $ModRootPath 'console_mp.log' $LogArchiveBudgetMB
foreach ($lp in @((Join-Path $modLogsDir 'games_mp.log'), (Join-Path $ModRootPath 'console_mp.log'))) {
    # Tolerant stat for the same reason as Get-FileAgeSeconds: a server restart rolls the live log
    # to <base>.000 between the test and the read, and a miss here would kill the run.
    $lpItem = Get-Item $lp -ErrorAction SilentlyContinue
    if ($lpItem) {
        $liveMB = [math]::Round($lpItem.Length / 1MB, 0)
        if ($liveMB -ge $LiveLogWarnMB) {
            Log "LIVE log large: $(Split-Path -Leaf $lp) = ${liveMB}MB (only a server restart rolls it - check for a flood dvar left on, e.g. gf_debug_popup)"
        }
    }
}

if (-not $WhatIf) {
    $state.items = $itemsHash
    Save-State $state
}

if (-not $anyProblem) { Log 'all checks OK' }
