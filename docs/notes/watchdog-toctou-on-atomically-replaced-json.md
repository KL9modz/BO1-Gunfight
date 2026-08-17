# Watchdog TOCTOU on an atomically-replaced JSON snapshot

**Date:** 2026-08-14, **recurred with a second symptom 2026-08-17**
**Status:** FIXED both halves (`tools/vps_services/watchdog.ps1`), regression-tested
(`tools/tests/service_functions.Tests.ps1`)

> ⚠ **The replace window has TWO failure modes and the 08-14 fix only closed one.** Missing file
> (below) *and* **present file with a blank timestamp** (2026-08-17, see the section at the end).
> Same file, same race, same self-healing ~30s blip, same false `WATCHDOG down` page.

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

---

## Recurrence 2026-08-17 08:38:03 — the OTHER half: a present file with a 1601 timestamp

Identical outward symptom (one urgent `WATCHDOG down`, self-cleared, game server never affected —
28s of blind monitoring), completely different crash:

```
[08:38:03] panel probe OK
[08:38:03] TERMINATING: watchdog.ps1 : Cannot convert value "13431458283.0755" to type
           "System.Int32". Error: "Value was either too large or too small for an Int32."
[08:38:03] ----- service DIED (exit 1) -----
[08:38:30] ALERT [urgent] Gunfight - WATCHDOG down :: GF-Watchdog : LastTaskResult=0x1
[08:38:31] ----- run_service start -----   <- restarted, clean; 08:41:33 "watchdog OK"
```

**13,431,458,283 seconds is 425 years** — `Now` minus it lands on **1601-01-01, the zero Windows
FILETIME**. So `Get-Item` *succeeded* (the 08-14 null-guard passed) and handed back a file whose
`LastWriteTime` had not been populated yet, mid-`Move-Item`-replace. `[int]` of 13.4 billion
overflows Int32 (max 2,147,483,647) → terminating under `$ErrorActionPreference = 'Stop'`.

Corroboration that the file really does blink this way: `GF-ConnLogger` independently logged
`admin.json unusable this tick - roster read from the panel instead` at 08:28:43 and 09:35:26 the
same morning. Every consumer of these snapshots is exposed, not just the watchdog.

### ⚠ The trap in the obvious fix

**Widening `[int]` to `[long]` is WORSE THAN THE CRASH.** A 425-year age does not merely fit in a
long — it reads as *catastrophically stale*, and `$hardAge` feeds **check 3b, which kills the
bootstrapper** to recover a "hung" server. You would trade 28 seconds of blind monitoring for a
real, unnecessary game-server restart on a perfectly healthy box.

### Fix

An implausible timestamp is not data, it is a **failed stat** — report it as unknown, exactly like
a missing file, and let the next 3-minute run settle it:

```powershell
$secs = (New-TimeSpan -Start $item.LastWriteTime -End (Get-Date)).TotalSeconds
if ($secs -gt 315360000 -or $secs -lt -86400) { return $null }   # >10y stale or >1d future
return [int]$secs
```

Small negatives pass through deliberately: clock granularity can put a just-written file
microseconds in the future, and the callers read a negative as "fresh", which it is.

### The rule, extended

⚠ **A tolerant read is not enough — the VALUE it returns must be sanity-checked too.** The 08-14
rule ("one tolerant stat, branch on `$null`") is necessary but not sufficient: a racing writer can
hand back a *successful* read of garbage. Any derived number that feeds a remediation decision
needs a plausibility gate, and the failure direction must be chosen deliberately — here, "unknown"
is safe and "very stale" triggers a kill.

⚠ Diagnosing the next one: the flight-recorder log **wraps long error text onto continuation
lines**, so a `Where-Object`/grep on the timestamp pattern shows only `... : Cannot ` and hides the
actual cause. Read the raw lines around the `TERMINATING:` index, not a filtered view.

**Deeper option, not taken:** make `status_service` use a genuinely atomic `File.Replace` /
`MoveFileEx` instead of PowerShell's delete-then-move. That would close the window at the source,
but readers should be tolerant regardless (ConnLogger hits the same window), so the reader fix
ships first.

Related: [[vps-status-log-notify-services]], [[gf-admin-connection-history]].
