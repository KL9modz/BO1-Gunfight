---
name: vps-deploy-repo-path-and-ssh-invocation
description: "deploy.ps1 lives in C:\\gfdeploy\\BO1-Gunfight (NOT the mods folder), and running it over SSH must go through cmd.exe — PowerShell 5.1 wraps git's stderr into a terminating NativeCommandError and silently aborts the script mid-deploy; and the clone can COMMIT but never PUSH, so a box-side commit hard-fails the next deploy until you fetch it down to the laptop and push from there"
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
Run as **Administrator** — a wrong-account run mirrors to the wrong profile. `$ModDest` defaults to `$env:LOCALAPPDATA\Plutonium\storage\t5\mods\mp_gunfight`, which is what makes the account matter. ⚠ Administrator is the right account because it owns the **profile the server loads from**, NOT because the server runs as it — the process is `SYSTEM` and the task action pins `LOCALAPPDATA` ([[vps-game-server-runs-as-system-localappdata-pinned]]). SSH lands as administrator, so a plain `deploy.ps1 -Mod` over SSH is already correct.

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

## 3. The deploy clone can COMMIT but can never PUSH — and a box-side commit blocks the next deploy

Found 2026-08-17, mid-deploy. `deploy.ps1 -Mod` opens with `git pull --ff-only`, which died on:

```
hint: Diverging branches can't be fast-forwarded, you need to either: ...
fatal: Not possible to fast-forward, aborting.
git pull --ff-only failed (exit 128)
```

The cause was a **real commit made ON the box** (a watchdog fix authored there that morning, already deployed and verified live) that had never reached GitHub. So the clone is not the read-only mirror it looks like — work genuinely originates there, via the `gf-vps` Remote Control session.

⚠ **And it cannot push it back.** Over SSH the push fails before it ever reaches the network:

```
fatal: Unable to persist credentials with the 'wincredman' credential store.
bash: line 1: /dev/tty: No such device or address
fatal: could not read Username for 'https://github.com'
```

Git Credential Manager's `wincredman` store wants an interactive desktop/TTY, and a non-interactive SSH session has neither. **Do not "fix" this by putting a PAT on the box** — that hands a permanent admin agent a push credential on top of everything else it already holds.

**The recovery — pull the box's commits DOWN to the laptop and push from there**, which keeps the SHAs identical so both sides end up genuinely in sync (a cherry-pick would leave the box diverged again on the very next deploy):

```
# on the box: merge, don't rebase — the classifier blocks history rewrites,
# and a merge is the honest record of two lines of work meeting anyway
ssh gf-vps "cd C:\gfdeploy\BO1-Gunfight; git merge origin/main --no-edit"

# on the laptop: fetch the box's own commits over ssh, fast-forward, push
git fetch "gf-vps:C:/gfdeploy/BO1-Gunfight" main
git merge --ff-only FETCH_HEAD
git push origin main
```

`git fetch <ssh-alias>:<windows-path>` **works** against the box despite its PowerShell default shell — worth knowing, because it is the only channel that moves box-side history out intact.

⚠ **Verify the box lands at `## main...origin/main` with no ahead/behind** before calling it done. "Ahead" alone still deploys fine (a fast-forward to an ancestor is a no-op, which is why the deploy could proceed before the sync was finished) — but the moment the laptop pushes anything new it becomes "ahead AND behind", and that is the state that hard-fails `--ff-only`.

⚠ Two related traps this incident also confirmed: SSH lands you in **PowerShell 5.1**, where `&&` is a parse error (use `;`), and `deploy.ps1`'s self-update warning fires when a pull changes `tools/deploy.ps1` or `tools/release_common.ps1` — if the box already had them (as it does after a merge), no warning appears and the run is already on the new code.
