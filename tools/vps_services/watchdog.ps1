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
    [string]   $AdminJsonPath    = 'C:\inetpub\wwwroot\admin\live\admin.json',
    [string]   $HealthJsonPath   = 'C:\inetpub\wwwroot\admin\live\health.json',
    [int]      $AdminStaleSecs  = 90,
    # Beyond this, admin.json staleness escalates from ALERT to ACTIVE RECOVERY (kill the hung
    # server so the launcher loop restarts it). Must be > $AdminStaleSecs.
    [int]      $AdminHardStaleSecs = 300,
    # A plutonium.exe (updater/launcher) with NO bootstrapper child, older than this, is a
    # wedged `-update-only` (the bat loop is stuck on that line, server DOWN, task still Running).
    [int]      $UpdaterWedgeSecs = 120,
    [int]      $ReAlertMinutes   = 20,
    [string]   $StatePath        = '',
    [string]   $MaintenancePath  = '',   # deploy.ps1 drops a self-expiring marker here to stand the watchdog down during a planned restart
    [string]   $NotifyConfigPath = '',
    [string]   $CfgPath          = '',   # dedicated.cfg (for the rcon password used by map_rotate)
    [int]      $PanelPort        = 3000, # RCON panel loopback port (single rcon pacer)
    [switch]   $NoRemediate,             # detect + alert only; never kill/rotate (like the old behavior)
    [switch]   $WhatIf
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $StatePath)        { $StatePath        = Join-Path $scriptRoot 'watchdog_state.json' }
if (-not $MaintenancePath)  { $MaintenancePath  = Join-Path $scriptRoot 'watchdog_maintenance.json' }
if (-not $NotifyConfigPath) { $NotifyConfigPath = Join-Path (Split-Path -Parent $scriptRoot) 'notify\config.json' }
if (-not $CfgPath) {
    # ...\storage\t5\mods\mp_gunfight\tools\vps_services -> four parents up = ...\storage\t5
    $st5 = $scriptRoot
    for ($i = 0; $i -lt 4; $i++) { $st5 = Split-Path -Parent $st5 }
    $CfgPath = Join-Path $st5 'dedicated.cfg'
}

function Log($msg) {
    $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$t] $msg"
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

# ---- rcon password (read from dedicated.cfg, box-local, never logged) --------
function Get-RconPw {
    if ($env:GF_RCON_PW) { return $env:GF_RCON_PW }
    if (Test-Path $CfgPath) {
        $m = Select-String -Path $CfgPath -Pattern 'set\s+rcon_password\s+"([^"]*)"' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return ''
}

# ---- issue an rcon command THROUGH the panel (the single box-side rcon pacer) ----
# Never send raw rcon here: the project rule is exactly one process owns the ~1-reply-
# per-0.7s pacing (the panel). map_rotate goes on the panel's priority lane.
function Send-PanelRcon($command) {
    try {
        $pw = Get-RconPw
        if (-not $pw) { Log "Send-PanelRcon: no rcon password in $CfgPath"; return $false }
        $body = @{ host = '127.0.0.1'; port = '28960'; password = $pw; command = $command; priority = $true } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$PanelPort/api/rcon" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 12
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

# ---- 2. admin.json freshness (proxy for "is the live game server responding") ----
$adminKey = 'admin.json-staleness'
if (Test-Path $AdminJsonPath) {
    $age = (New-TimeSpan -Start (Get-Item $AdminJsonPath).LastWriteTime -End (Get-Date)).TotalSeconds
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

# (3a) WEDGED UPDATER. The launch bat runs `plutonium.exe -update-only` before each
# (re)launch; if it hangs, the loop is stuck there with NO game server, yet GF-GameServer
# stays State=Running (the task can't see it). Signature: plutonium.exe present, bootstrapper
# absent, and it's been that way past a normal update download. Kill it -> the bat advances.
if ($upd.Count -gt 0 -and $boot.Count -eq 0) {
    $oldest = ($upd | Sort-Object StartTime | Select-Object -First 1)
    $ageSec = [int]((Get-Date) - $oldest.StartTime).TotalSeconds
    if ($ageSec -ge $UpdaterWedgeSecs) {
        $anyProblem = $true
        Log "updater WEDGE: plutonium.exe up ${ageSec}s with no game server"
        if ($canAct) {
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
} else {
    if (-not $WhatIf -and (Should-Alert 'updater-wedge' $false)) {
        Send-Alert -title 'Gunfight VPS - updater recovered' -message 'Game server process is up again.' -priority 'default' -tags 'white_check_mark'
    }
    if (-not $WhatIf) { Set-Item-State 'updater-wedge' $false $null }
}

# (3b) HUNG SERVER. admin.json stale past the HARD threshold while the bootstrapper is alive =
# the server is running but not answering RCON/status (a true hang, not a between-launch gap or
# the updater wedge handled above). Kill the bootstrapper so the bat's restart loop starts fresh.
if (Test-Path $AdminJsonPath) {
    $hardAge = [int]((New-TimeSpan -Start (Get-Item $AdminJsonPath).LastWriteTime -End (Get-Date)).TotalSeconds)
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

if (-not $WhatIf) {
    $state.items = $itemsHash
    Save-State $state
}

if (-not $anyProblem) { Log 'all checks OK' }
