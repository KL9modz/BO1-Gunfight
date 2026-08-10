---
name: deploy-restart-wedges-on-plutonium-updater
description: "FIXED 2026-08-10: `plutonium.exe -update-only` hangs on its NO-OP path (fails to exit when already current), which wedged EVERY restart. The bat now runs it once BEFORE the :server loop, cmd-bounded at 120s + taskkill; crash relaunches skip it (3s recovery). Freshness moved to watchdog check 5 (CDN revision drift, restart-when-empty). deploy.ps1 + watchdog 3a heals remain as nets."
metadata: 
  node_type: memory
  type: project
  originSessionId: 6390c4a6-e66f-463b-8f1c-c6947c553ea8
---

`tools/deploy.ps1 -Mod` kills the bootstrapper and relies on the `:server` loop in
`C:\gameserver\T5\start_mp_server.bat` (run by the **GF-GameServer scheduled task**, whose `cmd.exe`
is the bootstrapper's parent) to relaunch it. That loop's FIRST statement is

```bat
"%~dp0plutonium.exe" -install-dir "%LOCALAPPDATA%\Plutonium" -update-only
```

which cmd runs **synchronously**. Observed 2026-07-09: after a deploy restart, `plutonium.exe` did its
work (wrote `info.json` ~20s in) and then **never exited** — 0 CPU, no established TCP connections, no
files written, `MainWindowTitle` empty. `cmd` blocked on it, so the bootstrapper line was never reached
and **the live server stayed down ~11.5 minutes** until the updater was killed by hand.

It was NOT downloading: `info.json` already said `revision 5334` and the server came back as `r5334`, so
there was nothing to apply. It is a GUI launcher that can hang with no desktop (the task runs
non-interactive). So this can recur on **any** restart, not only when an update exists.

**Recover (server down after a deploy):**
```powershell
Get-Process plutonium -EA SilentlyContinue | Stop-Process -Force   # NOT plutonium-bootstrapper-win32
# the :server loop then falls through and relaunches; UDP 28960 binds ~30s later
```
Confirm with: bootstrapper process alive AND `Get-NetUDPEndpoint -LocalPort 28960`.

**GF-Watchdog NOW auto-heals this (fixed 2026-07-10, pending deploy).** `watchdog.ps1` gained an active
`(3a)` remediation step: if `plutonium.exe` is up with **no** `plutonium-bootstrapper-win32` child for
>`$UpdaterWedgeSecs` (120s), it `Stop-Process`es the wedged updater so the `:server` loop falls through
and relaunches. Plus `(3b)`: admin.json hard-stale >`$AdminHardStaleSecs` (300s) while the bootstrapper is
alive = a hung server → kill the bootstrapper (loop relaunches). Run `-NoRemediate` for the OLD
alert-only behavior. (Before this, the para below was true: `GF-GameServer.State` stays `Running` while
the game is down, and staleness only alerted.) See [[round-freeze-activation-race-and-rails]].

**`deploy.ps1 -Mod` NOW auto-recovers this itself** (fixed 2026-07-10, commit 6106286; recovery
**sped up in commit 1ec94b1**, both live on the box's deploy clone). This is the key complement to the
watchdog heal above: the deploy's own `Set-Maintenance` drops a watchdog-maintenance marker that
**suppresses GF-Watchdog for the whole restart window** — i.e. the watchdog is stood down during exactly
the span the wedge happens in, so it can't heal a deploy-triggered wedge. So `Restart-Server` owns
recovery: after killing the bootstrapper it calls `Wait-ForServerBack` — polls `Get-NetUDPEndpoint
-LocalPort 28960`, and kills the wedged `plutonium.exe` once it is provably stalled so the `:server`
loop falls through; 300s ceiling then reports failure. Maintenance window is 7 min to cover the poll.

**Detection is now DUAL-SIGNAL (commit 1ec94b1) — heals in ~45-60s, was ~170s.** The old check keyed on
**CPU-flat alone**, so it needed a blanket 150s grace (a network-bound download sits at ~0 CPU and would
otherwise look wedged). A real wedge is flat on **CPU AND disk I/O**, while a live update grows one or the
other, so `Get-UpdaterActivity` now samples both `plutonium.exe` CPU-seconds AND
`Win32_Process` ReadTransferCount+WriteTransferCount; it kills only after a **sustained flat streak**
(`FlatKillSeconds` 40s) past a short **45s warmup** (`MinGraceSeconds`). Dual-signal + streak means it
can never abort a working update, so the warmup is short. Manual `Stop-Process -Name plutonium` is now
automated in BOTH the watchdog (non-deploy restarts) and deploy.ps1 (deploy restarts).

**Two operational gotchas that still bit on 2026-07-10:** (1) NOTE the one-run lag — PowerShell loads the
whole script at invocation, so a `-Mod` run executes the deploy.ps1 already on disk; its own mid-run `git
pull` updates the file but not the running instance, so the clone must be pulled BEFORE the deploy that
should use the new code (`git -C C:\gfdeploy\BO1-Gunfight pull`). (2) **Don't sever the SSH session early**
— the deploy's recovery poll can run up to 5 min, so an SSH client `ConnectTimeout`/command timeout under
~90s kills the remote deploy *before* `Wait-ForServerBack` fires and leaves the server down (exactly what
forced the manual kill on 2026-07-10, when the client timed out at 120s < the old 150s grace). Run the
remote deploy detached or with a generous timeout.

**DURABLE FIX IMPLEMENTED 2026-08-10** (in `start_mp_server.bat`, box-local, NOT in the repo —
`tools/carry.ps1` carries it to the next box). Two structural changes, live-tested the same day:
1. **The updater moved OUT of the `:server` loop** — it now runs once, before the label, so a crash
   relaunch skips it entirely and recovers in 3s instead of gambling on the hang.
2. **It is bounded in cmd itself**: launched detached (`start "" /min`), polled with
   `tasklist|find` in a `for /L` loop (24 x 5s), then `taskkill`'d unconditionally at 120s. The
   watchdog-3a lesson baked into the launch path — no watcher needed for the deploy-window case
   where the watchdog is deliberately stood down.

The live test also settled the root-cause question this note left open, and CONFIRMS the 2026-07-09
observation was the general case: with CDN and local both at r5344 (**nothing to apply**), the
updater still sat the full 120s and had to be killed. `-update-only` **fails to exit when there is
no update** — the hang is the no-op path, not a slow download, which is why every restart wedged.

**The old "keep it in the loop for freshness" concern is now owned by watchdog check (5)** —
update DRIFT policy: the CDN advertises `{revision}` at
`https://cdn.plutoniummod.com/updater/prod/info.json` (the endpoint mxve/plutonium-updater
defaults to) and the official updater maintains `%LOCALAPPDATA%\Plutonium\info.json` locally, so
"update available" is a two-integer compare over one HTTPS GET. New revision + empty server ->
the watchdog bounces GF-GameServer (the bat updates on the way up); players on -> alert once per
revision and wait. A stale build can therefore no longer accumulate across restarts
([[unknown-command-cd-and-cfg-semicolon-parse]] stays covered) — and no restart can hang on the
updater again. Watchdog 3a remains as the belt-and-suspenders net.

Also note `.claude/CLAUDE.md` claims GF-GameServer was disabled 2026-07-04 in favor of a manual desktop
shortcut — **that is stale**: the task is registered and Running, and it owns the restart loop.
See [[vps-server-provisioned]], [[vps-launch-bat-and-maxclients-latch]].
