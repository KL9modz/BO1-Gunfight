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
#   GF-SecurityWatch tools\vps_services\security_watch.ps1  periodic SECURITY watch: unknown ssh
#                                                            key, authorized_keys change, RDP
#                                                            login, account/group management,
#                                                            firewall posture (see its header)
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
. (Join-Path $toolsRoot 'common.ps1')           # Resolve-T5Root (service-log home below)

# Every service runs THROUGH the flight-recorder launcher (run_service.ps1): all of a
# service's output - including the terminating error that kills it - lands timestamped in
# storage\t5\logs\services\<TaskName>.log. Before this, "-WindowStyle Hidden" sent
# everything to a window nobody sees, so a dead service left no evidence (GF-ConnLogger,
# 2026-08-02: a 6-minute day-file hole was the entire forensic record). The logs live
# OUTSIDE the mods mirror so deploy.ps1's /MIR can never delete them.
$launcher  = Join-Path $PSScriptRoot 'run_service.ps1'
$svcLogDir = Join-Path (Resolve-T5Root) 'logs\services'

$services = @(
    @{ Name = 'GF-ConnLogger'
       Script = Join-Path $toolsRoot 'conn_logger\conn_logger.ps1'
       # Reads status_service's admin.json, so it matches that service's 5s cadence
       # instead of the old 15s direct-rcon poll. NOTE it is no longer "no rcon at all":
       # when admin.json is stale/missing it falls back to the PANEL API (never a direct
       # rcon socket -- the panel-first rule holds), and that fallback URL carries the
       # password, cached at process start. So this task must be recycled by
       # tools\rotate_secrets.ps1 alongside GF-StatusService / GF-JoinNotify.
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
    @{ Name = 'GF-SecurityWatch'
       Script = Join-Path $toolsRoot 'vps_services\security_watch.ps1'
       # Periodic for the same reason as the watchdog: short-lived, fresh each run, bookmarked
       # by event RecordId so a missed run loses nothing (it just reads further back next time).
       # Needs the notify config for its topic, same as GF-JoinNotify - with no topic it would
       # detect into the void.
       Args = ''
       RequiresConfig = (Join-Path $toolsRoot 'notify\config.json')
       Periodic = $true }
    @{ Name = 'GF-DiscordStatus'
       Script = Join-Path $toolsRoot 'notify\discord_status.ps1'
       # Rewrites ONE Discord message with live status (it never posts a second one). Reads only
       # status.json / health.json, so its tick costs zero rcon.
       # DELIBERATELY NOT in the watchdog $PeriodicTasks health list: a stale status card is
       # cosmetic, and paging about it would be pure noise.
       Args = ''
       RequiresConfig = (Join-Path $toolsRoot 'notify\config.json')
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

# The Task Scheduler operational event log is OFF by default on Server 2019, which is one of
# the three reasons the 2026-08-02 GF-ConnLogger death was unexplainable (no start/stop/exit
# events existed). Enable it whenever services are (re)registered - idempotent, cheap, and it
# rides register_services.ps1 so a migration rebuild gets it automatically.
try {
    & wevtutil.exe sl 'Microsoft-Windows-TaskScheduler/Operational' /e:true 2>$null
    Write-Host 'Task Scheduler operational event log: enabled.'
} catch { Write-Warning "could not enable the Task Scheduler operational log: $($_.Exception.Message)" }

foreach ($svc in $services) {
    if (-not (Test-Path $svc.Script)) {
        Write-Warning "Skipping $($svc.Name): script not found ($($svc.Script))."
        continue
    }
    if ($svc.RequiresConfig -and -not (Test-Path $svc.RequiresConfig)) {
        Write-Warning "Skipping $($svc.Name): needs $($svc.RequiresConfig) (not configured yet)."
        continue
    }
    if (-not (Test-Path $launcher)) {
        Write-Warning "Skipping $($svc.Name): launcher not found ($launcher)."
        continue
    }

    # Route through the flight recorder; the service's own args ride behind the Gf* params
    # and land in run_service.ps1's -GfServiceArgs (ValueFromRemainingArguments) verbatim.
    $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -GfScript "{1}" -GfLog "{2}"' -f `
               $launcher, $svc.Script, (Join-Path $svcLogDir ($svc.Name + '.log'))
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
Write-Host ('Per-service output logs: {0}\<TaskName>.log' -f $svcLogDir)
