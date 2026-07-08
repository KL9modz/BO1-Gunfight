# register_services.ps1 - register the Gunfight VPS background services (run ON the box)
# ------------------------------------------------------------------------------
# One command sets up every 24/7 helper as a boot-start Scheduled Task, headless,
# auto-restarting if it exits. Run once, ELEVATED (Administrator), on the VPS.
#
#   powershell -ExecutionPolicy Bypass -File register_services.ps1            # install all
#   powershell -ExecutionPolicy Bypass -File register_services.ps1 -List      # show status
#   powershell -ExecutionPolicy Bypass -File register_services.ps1 -Uninstall # remove all
#   powershell -ExecutionPolicy Bypass -File register_services.ps1 -Only GF-StatusService
#
# Services registered:
#   GF-ConnLogger    tools\conn_logger\conn_logger.ps1     private IP connect/leave log
#   GF-JoinNotify    tools\notify\join-notify.ps1          ntfy phone alerts (needs config.json)
#   GF-StatusService tools\status_service\status_service.ps1  public status JSON for the website
#   GF-Watchdog      tools\vps_services\watchdog.ps1        periodic health check + auto-restart
#                                                            + ntfy alert for all of the above
#                                                            (see watchdog.ps1 header)
#
# All run as SYSTEM (no stored password, survive reboot). Each helper resolves its
# own files by paths relative to its script location, so SYSTEM finds them fine.
# GF-JoinNotify is skipped unless tools\notify\config.json exists (it needs a topic).
#
# GF-Watchdog is different in kind from the other three: they are infinite-loop
# processes restarted by Task Scheduler's own RestartOnFailure (999 tries, 1 min
# apart), which EXHAUSTS after ~16.6h of back-to-back failures and then just sits
# dead (State=Ready) until a human notices. GF-Watchdog is instead a short-lived
# script re-invoked on its OWN repeating trigger (every 3 min, forever) - each
# run gets a fresh check, so there's no retry budget to exhaust. It in turn
# restarts any of the other three (or GF-GameServer) that it finds not Running.
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [switch]   $Uninstall,
    [switch]   $List,
    [string[]] $Only
)

$ErrorActionPreference = 'Stop'
$toolsRoot = Split-Path -Parent $PSScriptRoot   # ...\mp_gunfight\tools

$services = @(
    @{ Name = 'GF-ConnLogger'
       Script = Join-Path $toolsRoot 'conn_logger\conn_logger.ps1'
       # Reads status_service's admin.json (no rcon of its own), so it matches that
       # service's 5s cadence instead of the old 15s direct-rcon poll.
       Args = '-IntervalSeconds 5'
       RequiresConfig = '' }
    @{ Name = 'GF-JoinNotify'
       Script = Join-Path $toolsRoot 'notify\join-notify.ps1'
       Args = ''
       RequiresConfig = (Join-Path $toolsRoot 'notify\config.json') }
    @{ Name = 'GF-StatusService'
       Script = Join-Path $toolsRoot 'status_service\status_service.ps1'
       # -AdminOutFile is passed but stays INERT until setup_admin_auth.ps1 creates
       # the .secured marker (fail-safe: no IP data reaches the web root before auth).
       Args = '-IntervalSeconds 5 -AdminOutFile "C:\inetpub\wwwroot\admin\live\admin.json"'
       RequiresConfig = '' }
    @{ Name = 'GF-Watchdog'
       Script = Join-Path $toolsRoot 'vps_services\watchdog.ps1'
       Args = ''
       RequiresConfig = ''
       Periodic = $true }
)

if ($Only) { $services = $services | Where-Object { $Only -contains $_.Name } }

if ($List) {
    foreach ($svc in $services) {
        $t = Get-ScheduledTask -TaskName $svc.Name -ErrorAction SilentlyContinue
        if ($t) {
            $info = Get-ScheduledTaskInfo -TaskName $svc.Name -ErrorAction SilentlyContinue
            Write-Host ('{0,-18} {1,-10} last={2} lastResult={3}' -f `
                $svc.Name, $t.State, $info.LastRunTime, ('0x{0:X}' -f $info.LastTaskResult))
        } else {
            Write-Host ('{0,-18} (not registered)' -f $svc.Name)
        }
    }
    return
}

if ($Uninstall) {
    foreach ($svc in $services) {
        if (Get-ScheduledTask -TaskName $svc.Name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $svc.Name -Confirm:$false
            Write-Host "Removed $($svc.Name)."
        } else {
            Write-Host "$($svc.Name) not registered."
        }
    }
    return
}

# ExecutionTimeLimit 0 = never auto-kill (each helper is an infinite loop);
# restart up to 999 times, 1 min apart, if the process ever exits.
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$trigger = New-ScheduledTaskTrigger -AtStartup

# Periodic tasks (currently just GF-Watchdog) are short-lived scripts re-run on
# their own schedule rather than infinite loops kept alive by RestartOnFailure -
# see the header comment for why that distinction matters.
$periodicSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
# RepetitionDuration must fit the scheduler's XML duration range - 10 years, not
# [TimeSpan]::MaxValue, which Register-ScheduledTask rejects as out of range.
$periodicTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 3) -RepetitionDuration (New-TimeSpan -Days 3650)

foreach ($svc in $services) {
    if (-not (Test-Path $svc.Script)) {
        Write-Warning "Skipping $($svc.Name): script not found ($($svc.Script))."
        continue
    }
    if ($svc.RequiresConfig -and -not (Test-Path $svc.RequiresConfig)) {
        Write-Warning "Skipping $($svc.Name): needs $($svc.RequiresConfig) (not configured yet)."
        continue
    }

    $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $svc.Script
    if ($svc.Args) { $argLine += ' ' + $svc.Args }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine

    if (Get-ScheduledTask -TaskName $svc.Name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $svc.Name -Confirm:$false
    }

    if ($svc.Periodic) {
        Register-ScheduledTask -TaskName $svc.Name `
            -Action $action -Trigger $periodicTrigger -Principal $principal -Settings $periodicSettings `
            -Description ("Gunfight VPS service: {0}" -f $svc.Name) | Out-Null
    } else {
        Register-ScheduledTask -TaskName $svc.Name `
            -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
            -Description ("Gunfight VPS service: {0}" -f $svc.Name) | Out-Null
    }
    Start-ScheduledTask -TaskName $svc.Name
    Write-Host "Registered + started $($svc.Name)."
}

Write-Host ''
Write-Host 'Done. Check status any time with:  register_services.ps1 -List'
