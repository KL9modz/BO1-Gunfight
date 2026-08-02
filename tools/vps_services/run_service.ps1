# run_service.ps1 - flight recorder for the GF-* box services (run BY Task Scheduler, not by hand)
# ------------------------------------------------------------------------------
# The five helper tasks used to run "-WindowStyle Hidden" with stdout/stderr attached to a
# window nobody sees, so a service that DIED left no evidence: GF-ConnLogger crashed
# 2026-08-02 13:45 and the only trace was a 6-minute hole in the day-file - the terminating
# error, the watchdog's own "DOWN -> restart issued" narration, everything went to /dev/null.
# register_services.ps1 now routes every service through this launcher, which:
#
#   1. Runs the real service script IN-PROCESS and streams ALL its output (stdout, Write-Host/
#      information, warnings, non-terminating errors) into one per-service log, each line
#      timestamped. Probe-verified on the box: `*>&1` in Windows PowerShell 5.1 carries every
#      stream including information/Write-Host.
#   2. Catches a TERMINATING error - the thing that actually kills a service under the
#      $ErrorActionPreference='Stop' these scripts all set - logs it with full position info,
#      and exits 1 so Task Scheduler's RestartOnFailure still fires exactly as before.
#   3. Size-caps the log at start (rollover to <log>.old, one generation kept), so the
#      recorder can never become the disk problem it exists to diagnose. Logs live under
#      storage\t5\logs\services\ - OUTSIDE the mods mirror, so deploy.ps1's /MIR can never
#      delete them (same reasoning as the players_*.log day-files).
#
# The log write itself is try/catch-swallowed: the recorder must never be able to kill the
# service it records. A terminating error in the SERVICE still propagates to the catch below.
#
# Parameter names are Gf-prefixed so they can never prefix-collide with a service's own
# pass-through arguments (everything unrecognized lands in -GfServiceArgs). ⚠ Those arrive as
# a STRING ARRAY, and array-splatting strings at a .ps1 binds them POSITIONALLY - '-Name'
# tokens are NOT re-parsed as parameter names (probe-proven 2026-08-02: the toy service's
# first positional param received the literal string '-IntervalSeconds'). So the launcher
# parses the array into a named hashtable and splats THAT. Supported shape: `-Name value`
# pairs and bare `-Switch` flags - which is everything register_services.ps1 emits; a value
# that itself starts with `-<letter>` would misparse, so never pass one.
# Windows PowerShell 5.1 compatible. ASCII-only source.
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $GfScript,   # absolute path to the service script
    [Parameter(Mandatory = $true)] [string] $GfLog,      # absolute path to this service's log
    [int] $GfMaxLogKB = 4096,                            # rollover threshold (start-time check)
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $GfServiceArgs = @()
)

function Write-SvcLog([string]$text) {
    # Swallow, always: a locked/unwritable log must cost a line, never the service.
    try {
        Add-Content -Path $GfLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $text) -Encoding UTF8
    } catch { }
}

# --- log dir + start-time rollover -------------------------------------------
try {
    $dir = Split-Path -Parent $GfLog
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-Path $GfLog) {
        if ((Get-Item $GfLog).Length -gt ($GfMaxLogKB * 1KB)) {
            Move-Item -Path $GfLog -Destination ($GfLog + '.old') -Force
        }
    }
} catch { }

Write-SvcLog ("----- run_service start: {0}  args=[{1}] -----" -f $GfScript, ($GfServiceArgs -join ' '))

if (-not (Test-Path $GfScript)) {
    Write-SvcLog ("FATAL: service script not found: {0}" -f $GfScript)
    exit 1
}

# --- parse pass-through args into a NAMED splat (see header for why) ---------
$svcSplat = @{}
for ($i = 0; $i -lt $GfServiceArgs.Count; $i++) {
    $tok = $GfServiceArgs[$i]
    if ($tok -match '^-([A-Za-z]\w*)$') {
        $name   = $Matches[1]
        $hasVal = ($i + 1 -lt $GfServiceArgs.Count) -and ($GfServiceArgs[$i + 1] -notmatch '^-[A-Za-z]')
        if ($hasVal) { $svcSplat[$name] = $GfServiceArgs[++$i] } else { $svcSplat[$name] = $true }
    } else {
        Write-SvcLog ("FATAL: unparseable service arg '{0}' (expected -Name value pairs); refusing to guess" -f $tok)
        exit 1
    }
}

# --- run the service, recording every stream ---------------------------------
try {
    & $GfScript @svcSplat *>&1 | ForEach-Object {
        $prefix = ''
        if     ($_ -is [System.Management.Automation.WarningRecord]) { $prefix = 'WARNING: ' }
        elseif ($_ -is [System.Management.Automation.ErrorRecord])   { $prefix = 'ERROR: ' }
        elseif ($_ -is [System.Management.Automation.VerboseRecord]) { $prefix = 'VERBOSE: ' }
        $txt = ($_ | Out-String).TrimEnd()
        if ($txt -ne '') { Write-SvcLog ($prefix + $txt) }
    }
    # The 24/7 services are infinite loops - reaching here is itself a finding. The periodic
    # ones (watchdog, security watch) land here every scheduled run; that is their heartbeat.
    Write-SvcLog "----- service exited normally -----"
} catch {
    Write-SvcLog ("TERMINATING: " + (($_ | Out-String).TrimEnd()))
    Write-SvcLog "----- service DIED (exit 1; Task Scheduler RestartOnFailure takes it from here) -----"
    exit 1
}
