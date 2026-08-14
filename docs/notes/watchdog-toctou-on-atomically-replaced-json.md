# Watchdog TOCTOU on an atomically-replaced JSON snapshot

**Date:** 2026-08-14 **Status:** FIXED (`tools/vps_services/watchdog.ps1`)

## Symptom

An **urgent ntfy page: `Gunfight - WATCHDOG down`**, on a box where everything was actually fine. The
watchdog was healthy again within 40 seconds and the alert never repeated.

## What actually happened

`GF-Watchdog` ran, passed every check, and then **crashed inside the same run**:

```
[02:28:57] ----- run_service start: ...\watchdog.ps1 -----
[02:29:04] admin.json fresh (age=6s)          <- check 2 stats the file successfully
[02:29:04] TERMINATING: Get-Item : Cannot find path
           'C:\inetpub\wwwroot\admin\live\admin.json' because it does not exist.
           At ...\watchdog.ps1:422 char:44
[02:29:04] ----- service DIED (exit 1; Task Scheduler RestartOnFailure takes it from here) -----
[02:29:39] ----- run_service start: ... -----  <- restarted, clean
[02:29:41] all checks OK
```

Check 2 read `admin.json` fine and check 3b could not find it **in the same logged second**. The file
was there, then wasn't.

`GF-SecurityWatch`'s reciprocal dead-man check (its section 10) then read
`LastTaskResult=0x1`, correctly called that "watchdog down", issued `Start-ScheduledTask`, and paged
urgent. **Every part of the alerting chain worked as designed** — the trigger was a self-healing 35s
blip, not an outage.

## Root cause

A textbook TOCTOU. Three sites in `watchdog.ps1` used the two-statement form:

```powershell
if (Test-Path $AdminJsonPath) {
    $age = (New-TimeSpan -Start (Get-Item $AdminJsonPath).LastWriteTime -End (Get-Date)).TotalSeconds
```

`status_service` replaces its snapshots with `Move-Item -Path $tmp -Destination $path -Force`
(`status_service.ps1`). ⚠ **On Windows that is NOT an atomic replace** — PowerShell's `-Force` **deletes
the destination first, then moves**, so `admin.json` genuinely blinks out of existence several times a
minute (the file is rewritten every few seconds; observed ages are 1-6s). `Test-Path` can therefore
succeed and `Get-Item` fail microseconds later.

The kill shot is the service pattern's own `$ErrorActionPreference = 'Stop'`: a missing path becomes a
**terminating** error that takes down the whole run, not a `$null`.

⚠ Note `status_service.ps1` already documents the *other* half of this same Windows behavior — that
`Move-Item -Force` fails outright when another process holds the destination open — and retries 3× with
an in-place-write fallback. The delete-then-move window is the mirror image of that, on the reader's side.

## Fix

One tolerant stat helper, null-guarded by callers, replacing all three `Test-Path`/`Get-Item` pairs:

```powershell
function Get-FileAgeSeconds($path) {
    $item = Get-Item $path -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    return [int]((New-TimeSpan -Start $item.LastWriteTime -End (Get-Date)).TotalSeconds)
}
```

The live-log size check got the same treatment (`Get-Item $lp -ErrorAction SilentlyContinue`): a server
restart rolls `games_mp.log` to `.000` and opens an identical window there.

## The rule

⚠ **Never `Test-Path` then `Get-Item`/`Get-Content` on a file another process rewrites** — that pair is
two statements with a gap, and under `$ErrorActionPreference = 'Stop'` the gap is a crash. Take **one**
tolerant read (`-ErrorAction SilentlyContinue`) and branch on `$null`. This applies to every consumer of
`admin.json` / `status.json` / `health.json` / the engine logs, not just the watchdog.

⚠ Corollary for the alerting design: a **single** `WATCHDOG down` page that clears by itself on the next
cycle is far more likely to be the watchdog *crashing on one run* than a real outage. Read
`storage\t5\logs\services\GF-Watchdog.log` for a `TERMINATING:` line before assuming the box is sick —
that log only exists because of the `run_service.ps1` flight recorder
([[vps-status-log-notify-services]]).

Related: [[vps-status-log-notify-services]], [[gf-admin-connection-history]].
