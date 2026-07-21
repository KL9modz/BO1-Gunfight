---
name: vps-deploy-repo-path-and-ssh-invocation
description: "deploy.ps1 lives in C:\\gfdeploy\\BO1-Gunfight (NOT the mods folder), and running it over SSH must go through cmd.exe — PowerShell 5.1 wraps git's stderr into a terminating NativeCommandError and silently aborts the script mid-deploy"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 135f1264-98e3-4b8b-bdd1-1d3a5d527b86
---

Two traps that each silently ate a deploy attempt on 2026-07-12. Both cost time because the failure mode is **silence**, not an error.

## 1. The deploy repo is `C:\gfdeploy\BO1-Gunfight` — the mods folder is only the TARGET

`deploy.ps1` mirrors the git tree INTO the Plutonium storage mods folder. That destination copy therefore also contains a `tools\deploy.ps1` — but it has **no `.git`**, so running it there dies instantly:

```
fatal: not a git repository (or any of the parent directories): .git
```

The real clone (the only `.git` on the box) is **`C:\gfdeploy\BO1-Gunfight`**. Always:
```
cd C:\gfdeploy\BO1-Gunfight ; .\tools\deploy.ps1 -Mod
```
Run as **Administrator** (the server's own account) — a wrong-account run mirrors to the wrong profile. `$ModDest` defaults to `$env:LOCALAPPDATA\Plutonium\storage\t5\mods\mp_gunfight`, which is what makes the account matter.

## 2. Over SSH, invoke deploy.ps1 through `cmd.exe` — never let PowerShell redirect git's stderr

`git` writes normal progress to **stderr** ("From https://github.com/…", "* branch release -> FETCH_HEAD") even on a fully successful `exit 0`. In **PowerShell 5.1**, redirecting a native exe's stderr (`2>&1`, `*>&1`) wraps each line in a **NativeCommandError** ErrorRecord and sets `$?` to `$false` *despite exit code 0*. Inside a script with `$ErrorActionPreference = 'Stop'` that becomes **terminating** — so `deploy.ps1` aborts mid-run, printing nothing after the last `Write-Host`.

Symptom: output just stops at `Pulling latest...` or `Fetching mod.ff from 'release' branch...`, no error, no exit code, and the mirror never runs. It reads exactly like a network hang. It is not — `git fetch` completes in **0.4s, exit 0**. (Proved it by timing the fetch directly with `GIT_TERMINAL_PROMPT=0`.)

**Correct invocation** — let CMD do the redirection, so PowerShell never sees the stderr:
```
cmd.exe /c "powershell -NoProfile -ExecutionPolicy Bypass -File C:\gfdeploy\BO1-Gunfight\tools\deploy.ps1 -Mod > C:\gfdeploy\deploy_run.log 2>&1"
```
Then read the log. ⚠ Do **not** wrap the call in `2>&1 | Tee-Object` or `*>&1 | ForEach-Object` — that is what causes the abort.

⚠ `deploy.ps1` also has a legit **self-update trap** (exit 0 with "re-run the SAME command") that fires only when the pull changed `tools/deploy.ps1` itself. Don't confuse it with the stderr abort: the self-update path *prints why it stopped*, the stderr abort prints nothing.

## Bonus: a healthy deploy auto-recovers the wedged updater

A good run logs `Updater appears WEDGED (plutonium.exe flat on CPU AND I/O for 40s). Killing it…` then `Game server is back up (UDP 28960 listening after 57s)`. That is the **fix working**, not a failure — see [[deploy-restart-wedges-on-plutonium-updater]].

## Don't diagnose the box with a bad process filter

The game server process is named **`plutonium-bootstrapper-win32.exe`** — not `plutonium.exe`, not `BlackOpsMP.exe`. A `Get-Process -Name plutonium,BlackOpsMP` returns nothing and reads as "the server is DOWN" when it is perfectly healthy. Twice I called a live server dead on this. Check `Get-NetUDPEndpoint -LocalPort 28960` and the freshness of `C:\inetpub\wwwroot\live\status.json` instead.

⚠ And do **not** hit `/api/tick` yourself to check health — that makes you a THIRD rcon consumer competing with the panel's paced queue (~1 reply/0.7s) and it just times out, which also looks like a dead server. Read `status.json` (written by GF-StatusService) — zero extra rcon. See [[rcon-panel-queue-saturation]], [[read-the-server-not-the-file]].
