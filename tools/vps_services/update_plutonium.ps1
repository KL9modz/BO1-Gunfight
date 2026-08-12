# Revision-aware Plutonium update step for the launch bat (C:\gameserver\T5\start_mp_server.bat).
#
# WHY THIS EXISTS
#   `plutonium.exe -update-only` NEVER EXITS on its no-op path. Proven live 2026-08-10 with local
#   and CDN both at r5344: it sat the full 120s with NOTHING to download. The bat could only bound
#   it with a blind timer, so every deliberate restart paid ~2 minutes of dead server.
#
#   The fix is a POSITIVE completion signal instead of a blind timer. The updater maintains
#   {"revision":N} in <PlutoRoot>\info.json and the CDN advertises the target at $CdnInfoUrl:
#     local == cdn  -> nothing to do; skip the updater entirely (restart drops to seconds)
#     local <  cdn  -> run it, wait for the local revision to REACH the cdn one, then clear it
#   so an update finishes in the ~20s it actually takes instead of always paying the cap.
#   (Same signal CBServers/cb-launcher uses; their comment on the hang is our bug verbatim:
#   "Their window stays up after finishing, so the revision landing is the completion signal.")
#   $CdnInfoUrl is the URL that cdn.plutonium.pw/updater/prod.json's manifests[0] resolves to -
#   that file is the indirection layer to re-resolve through if this endpoint ever moves.
#
# CONTRACT WITH THE BAT: NEVER BLOCK THE SERVER LAUNCH. Every failure path (CDN unreachable, no
# updater exe, an unexpected throw) degrades to "run it bounded" or "skip it", and the script
# ALWAYS exits 0. That is why $ErrorActionPreference is deliberately NOT 'Stop' here, unlike the
# long-running services: this runs in the launch path, where one non-terminating error becoming
# fatal is the difference between a slow start and a dead server.
#
# WATCHDOG INTERLOCK: a real update can legitimately outrun watchdog check 3a's 120s wedge
# threshold (a first install on a fresh box downloads everything), and 3a would kill it mid-write.
# So the RUN paths drop a self-expiring maintenance marker sized to their own cap, extend-only so
# a deploy's longer marker is never shortened, and never delete it (an expiring marker cannot
# leave the watchdog disabled). The SKIP path writes nothing - there is no window to protect.
#
# UPDATE POLICY (when to restart the server for a new revision) is NOT here: it lives in
# watchdog.ps1 check 5, which owns the "drift + empty server -> bounce" decision. This script only
# owns "apply whatever is pending, as fast as it can be verified" during a launch that is already
# happening.

param(
    # Plutonium install root - holds info.json and the storage tree. Empty = this user's
    # %LOCALAPPDATA%\Plutonium (correct for the bat, which runs as the interactive server account;
    # it would be the WRONG profile under SYSTEM, hence the explicit parameter).
    [string]$PlutoRoot    = '',
    # The updater binary. The bat passes its own folder's copy (C:\gameserver\T5\plutonium.exe);
    # falls back to one inside PlutoRoot.
    [string]$UpdaterExe   = '',
    [string]$CdnInfoUrl   = 'https://cdn.plutoniummod.com/updater/prod/info.json',
    [int]$CdnTimeoutSec   = 15,
    # Caps, not durations - the revision landing ends the wait long before these.
    [int]$UpdateWaitSecs  = 180,   # a normal revision bump (~20s in practice)
    [int]$InstallWaitSecs = 900,   # first install on a fresh box: the whole client comes down
    [int]$PollMs          = 1000,
    # Report only, change nothing. Exit 0 = current, 10 = update available, 2 = undetermined.
    [switch]$Check
)

$ErrorActionPreference = 'Continue'   # deliberate - see CONTRACT above

# ---- logging ------------------------------------------------------------------------------
# Own file under the flight recorder's folder: GF-GameServer is registered separately and is NOT
# routed through run_service.ps1, so without this the bat's console output dies with its window.
$script:LogFile = $null
try {
    . (Join-Path $PSScriptRoot '..\common.ps1')
    # Resolve-T5Root is derived from common.ps1's own LOCATION, so it is only correct inside the
    # deployed storage tree - from a repo clone it walks up to something like C:\ and we would
    # create a junk C:\logs\services (the same location trap carry.ps1 hit). Verify the resolved
    # root actually looks like the t5 tree before writing anything into it.
    $t5 = Resolve-T5Root
    if (-not (Test-Path -LiteralPath (Join-Path $t5 'mods'))) { throw "resolved '$t5' is not a t5 storage tree (running from a clone?)" }
    $logDir = Join-Path $t5 'logs\services'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $script:LogFile = Join-Path $logDir 'update_plutonium.log'
    if ((Test-Path -LiteralPath $script:LogFile) -and (Get-Item -LiteralPath $script:LogFile).Length -gt 256KB) {
        $keep = Get-Content -LiteralPath $script:LogFile -Tail 200
        Set-Content -LiteralPath $script:LogFile -Value $keep -Encoding UTF8
    }
} catch {
    Write-Host "update_plutonium: file logging unavailable ($($_.Exception.Message)); console only"
}

function Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    }
}

# ---- primitives ---------------------------------------------------------------------------
function Get-LocalRevision {
    param([string]$Root)
    $p = Join-Path $Root 'info.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $j = Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $j.revision) { return $null }
        return [int]$j.revision
    } catch { return $null }   # mid-write / malformed: treat as unknown, never throw
}

function Get-CdnRevision {
    param([string]$Url, [int]$TimeoutSec)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($null -eq $r.revision) { return $null }
        return [int]$r.revision
    } catch { return $null }
}

# Kills the UPDATER only. 'plutonium' is an exact base-name match, so the game server's
# 'plutonium-bootstrapper-win32' is never a target (same name the watchdog matches on).
function Stop-Updater {
    $procs = @(Get-Process -Name 'plutonium' -ErrorAction SilentlyContinue)
    foreach ($p in $procs) { try { $p | Stop-Process -Force -ErrorAction SilentlyContinue } catch { } }
    return $procs.Count
}

# Extend-only maintenance marker. A deploy (or check 5) may already hold a LONGER window and
# shortening it would expose the very restart it is protecting, so an existing later marker wins.
# Never deleted on completion: self-expiry is what guarantees an aborted run cannot leave the
# watchdog switched off.
function Set-MarkerAtLeast {
    param([int]$Minutes, [string]$Reason)
    if (-not (Get-Command Write-GfMaintenanceMarker -ErrorAction SilentlyContinue)) {
        Log "no maintenance marker (common.ps1 unavailable) - watchdog check 3a may reclaim a long update"
        return
    }
    try {
        $existing = Join-Path $PSScriptRoot 'watchdog_maintenance.json'
        if (Test-Path -LiteralPath $existing) {
            $until = (Get-Content -LiteralPath $existing -Raw | ConvertFrom-Json).until
            if ($until -and ([datetime]$until) -gt (Get-Date).AddMinutes($Minutes)) {
                Log "existing maintenance marker runs longer (until $until) - left as is"
                return
            }
        }
        Write-GfMaintenanceMarker -Dir $PSScriptRoot -Minutes $Minutes -Reason $Reason | Out-Null
        Log "maintenance marker set for ${Minutes}m ($Reason)"
    } catch { Log "marker write failed (non-fatal): $($_.Exception.Message)" }
}

# Run the updater and wait for a POSITIVE signal.
#   $TargetRev > 0 : done when the local revision reaches it.
#   $TargetRev = 0 : blind mode (CDN unreachable) - done when the local revision CHANGES, or when
#                    the process exits by itself. Best effort, still bounded.
# Returns $true when the revision landed.
function Invoke-BoundedUpdate {
    param([string]$Exe, [string]$Root, [int]$TargetRev, [int]$CapSecs, [string]$Mode)

    $startRev = Get-LocalRevision $Root
    $killed = Stop-Updater
    if ($killed -gt 0) { Log "cleared $killed stale updater process(es) before starting" }

    Set-MarkerAtLeast -Minutes ([math]::Ceiling($CapSecs / 60) + 3) -Reason "plutonium $Mode (cap ${CapSecs}s)"

    Log "starting updater: $Exe -install-dir `"$Root`" -update-only   [$Mode, cap ${CapSecs}s]"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = $null
    try {
        # Same invocation the bat used inline - no -no-self-update: letting the updater refresh
        # itself is wanted here (cb-launcher passes it only to protect its own bundled copy).
        $proc = Start-Process -FilePath $Exe -ArgumentList @('-install-dir', $Root, '-update-only') `
                              -WindowStyle Minimized -PassThru -ErrorAction Stop
    } catch {
        Log "FAILED to start the updater: $($_.Exception.Message) - launching the server anyway"
        return $false
    }

    $landed = $false
    $exited = $false
    while ($sw.Elapsed.TotalSeconds -lt $CapSecs) {
        Start-Sleep -Milliseconds $PollMs
        $now = Get-LocalRevision $Root
        if ($TargetRev -gt 0) { $landed = ($null -ne $now -and $now -ge $TargetRev) }
        else                  { $landed = ($null -ne $now -and $now -ne $startRev) }
        if ($landed) { break }
        try { $exited = $proc.HasExited } catch { $exited = $false }
        if ($exited) { break }   # it finished (or died) - stop waiting on a process that is gone
    }
    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    $left = Stop-Updater
    $final = Get-LocalRevision $Root
    if ($landed) {
        Log "revision landed at r$final after ${elapsed}s (cleared $left lingering updater process(es))"
    } elseif ($exited) {
        Log "updater exited on its own after ${elapsed}s WITHOUT the revision landing (local r$final) - continuing to launch"
    } else {
        Log "TIMEOUT: revision did not land within ${CapSecs}s (local r$final) - killed $left updater process(es) and continuing to launch"
    }
    return $landed
}

# ---- main ---------------------------------------------------------------------------------
try {
    if ([string]::IsNullOrWhiteSpace($PlutoRoot)) { $PlutoRoot = Join-Path $env:LOCALAPPDATA 'Plutonium' }
    if ([string]::IsNullOrWhiteSpace($UpdaterExe)) { $UpdaterExe = Join-Path $PlutoRoot 'plutonium.exe' }

    $localRev = Get-LocalRevision $PlutoRoot
    $cdnRev   = Get-CdnRevision -Url $CdnInfoUrl -TimeoutSec $CdnTimeoutSec

    $localTxt = if ($null -eq $localRev) { 'none (first install)' } else { "r$localRev" }
    $cdnTxt   = if ($null -eq $cdnRev)   { 'unreachable' }          else { "r$cdnRev" }

    if ($Check) {
        Log "check: local $localTxt, cdn $cdnTxt   [root $PlutoRoot]"
        if ($null -eq $cdnRev -or $null -eq $localRev) { exit 2 }
        if ($cdnRev -gt $localRev) { Log "UPDATE AVAILABLE"; exit 10 }
        Log "current"
        exit 0
    }

    # Revision comparison FIRST: "already current" is the common case and the informative log line,
    # and it does not care whether the updater binary is even present.
    if ($null -ne $localRev -and $null -ne $cdnRev -and $localRev -ge $cdnRev) {
        # THE FAST PATH, and the whole point of this script: nothing to download, so the updater
        # would only hang. Anything already running provably has no work either - clear it.
        $killed = Stop-Updater
        $extra = if ($killed -gt 0) { " (cleared $killed idle updater process(es))" } else { '' }
        Log "plutonium current (local $localTxt = cdn $cdnTxt) - updater SKIPPED$extra"
        exit 0
    }

    if (-not (Test-Path -LiteralPath $UpdaterExe)) {
        Log "WANTED an update (local $localTxt, cdn $cdnTxt) but no updater at $UpdaterExe - launching the server unpatched"
        exit 0
    }

    if ($null -eq $cdnRev) {
        Log "cdn unreachable ($CdnInfoUrl) - running the updater blind, bounded at ${UpdateWaitSecs}s"
        Invoke-BoundedUpdate -Exe $UpdaterExe -Root $PlutoRoot -TargetRev 0 -CapSecs $UpdateWaitSecs -Mode 'blind update' | Out-Null
    } elseif ($null -eq $localRev) {
        Log "no local info.json - FIRST INSTALL to $cdnTxt, bounded at ${InstallWaitSecs}s"
        Invoke-BoundedUpdate -Exe $UpdaterExe -Root $PlutoRoot -TargetRev $cdnRev -CapSecs $InstallWaitSecs -Mode 'first install' | Out-Null
    } else {
        Log "update pending: local $localTxt -> cdn $cdnTxt"
        Invoke-BoundedUpdate -Exe $UpdaterExe -Root $PlutoRoot -TargetRev $cdnRev -CapSecs $UpdateWaitSecs -Mode 'update' | Out-Null
    }
} catch {
    # Belt and braces: an unexpected throw here must still let the server start.
    Log "UNEXPECTED ERROR (continuing to launch): $($_.Exception.Message)"
}

exit 0
