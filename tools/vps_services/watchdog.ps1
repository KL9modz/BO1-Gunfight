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
    [int]      $AdminStaleSecs  = 90,
    [int]      $ReAlertMinutes   = 20,
    [string]   $StatePath        = '',
    [string]   $NotifyConfigPath = '',
    [switch]   $WhatIf
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $StatePath)        { $StatePath        = Join-Path $scriptRoot 'watchdog_state.json' }
if (-not $NotifyConfigPath) { $NotifyConfigPath = Join-Path (Split-Path -Parent $scriptRoot) 'notify\config.json' }

function Log($msg) {
    $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$t] $msg"
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

if (-not $WhatIf) {
    $state.items = $itemsHash
    Save-State $state
}

if (-not $anyProblem) { Log 'all checks OK' }
