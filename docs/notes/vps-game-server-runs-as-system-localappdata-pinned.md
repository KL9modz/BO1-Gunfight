# The game server runs as SYSTEM — its profile is pinned, so the process owner lies

**Date:** 2026-08-14 **Status:** settled — the documented diagnostic was retired, deploy behaviour unchanged

## The claim that went stale

From 2026-07-02 until this note, `tools/deploy.ps1`, `docs/VPS_DEPLOY.md` and two notes all said:

> On the current VPS the server runs as **ADMINISTRATOR** (confirmed via the bootstrapper process
> owner). Find the real account any time:
> `Get-CimInstance Win32_Process | ? Name -match bootstrapper`   # check the owner

The *conclusion* (deploy from an Administrator session) is still right. The *reason* and the
*diagnostic* are both wrong, and the diagnostic now actively misleads.

## What is actually true

```
plutonium-bootstrapper-win32.exe | pid 808 | owner NT AUTHORITY\SYSTEM
(Get-ScheduledTask GF-GameServer).Principal -> UserId: SYSTEM, LogonType: ServiceAccount
```

The process runs as **SYSTEM**. The storage tree is Administrator's anyway, because the task action
pins the profile before the bat ever runs:

```
cmd.exe /c "set LOCALAPPDATA=C:\Users\Administrator\AppData\Local&&C:\gameserver\T5\start_mp_server.bat"
```

`start_mp_server.bat` then does everything off `%LOCALAPPDATA%` — `cd /D %LOCALAPPDATA%\Plutonium`, the
`update_plutonium.ps1` path, `-install-dir` — so **process identity and storage profile are decoupled**.
There is no machine-level `LOCALAPPDATA` override; the pin lives only in that task action.

## Why the old diagnostic is worse than no diagnostic

Following it reads `SYSTEM` and points you at
`C:\Windows\System32\config\systemprofile\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight` —
**which does not exist on the box**. A conscientious session that "corrects" the deploy by passing
`-ModDest` at that path produces exactly the silent wrong-profile deploy the comment was written to
prevent: robocopy happily creates the tree, prints a healthy summary, and the server keeps loading the
old files. The failure mode is a **successful-looking deploy**, which is the expensive kind
([[vps-deploy-repo-path-and-ssh-invocation]] is the same shape of trap).

## What to read instead

Two reads, in order of directness:

```powershell
# 1. Authoritative: the task action carries the pin
(Get-ScheduledTask GF-GameServer).Actions | % { $_.Execute + ' ' + $_.Arguments }

# 2. Confirm against reality - the live log is written continuously (g_logSync 1)
'<profile>\Plutonium\storage\t5\mods\mp_gunfight\logs\games_mp.log'   # age should be ~0s
```

The second is the one that settles any argument: whichever profile holds a `games_mp.log` whose
`LastWriteTime` is seconds old is the live one, no matter who owns the process. That is
[[read-the-server-not-the-file]] applied to a filesystem path rather than a dvar.

## Practical consequence: none, if you use SSH

`ssh gf-vps` lands as `administrator`, whose `$env:LOCALAPPDATA` is exactly the pinned profile, so a
plain `cd C:\gfdeploy\BO1-Gunfight ; .\tools\deploy.ps1 -Mod -Web` is already correct and needs no
`-ModDest`. Verified end to end on 2026-08-14: mod tree + `mod.ff` mirrored, server back on UDP 28960
in 11s, no GSC compile errors, all six JSON projections refreshing.

⚠ If the task is ever re-registered, **the pin is the thing to preserve** — it is a single `set` inside
a `cmd.exe /c` string in the action, easy to drop when converting the task to run the bat directly. Lose
it and a SYSTEM-run server silently starts building a fresh, empty storage tree under `systemprofile`.

Related: [[vps-server-provisioned]] (provisioning record, corrected),
[[vps-launch-bat-and-maxclients-latch]] (the bat's other latched state).
