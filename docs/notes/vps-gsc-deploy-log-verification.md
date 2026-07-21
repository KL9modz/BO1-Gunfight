---
name: vps-gsc-deploy-log-verification
description: How to verify a GSC deploy actually landed + compiled + ran on the VPS via the two server logs (console_mp.log vs games_mp.log)
metadata: 
  node_type: memory
  type: reference
  originSessionId: c905da21-6ae3-4ada-9b8d-ae5ddf701a0b
---

After `deploy.ps1 -Mod` (SSH in: `ssh -i ~/.ssh/gf_vps Administrator@94.72.121.4`, PowerShell shell), the live mod loads from `C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight` (Administrator's LOCALAPPDATA storage — the authoritative path). The console line "Searching for files required to download mod" also lists `C:\gameserver\T5\mods\mp_gunfight`, but that folder DOES NOT EXIST — it's just a fallback search root, not a second live copy. Confirm the deploy landed by checking a changed `.gsc` for a new marker + LastWrite in the storage path.

Two logs, DIFFERENT jobs (checked one, missed the other, more than once):
- `...\mods\mp_gunfight\console_mp.log` — engine console. **GSC compile/runtime errors show HERE** ("script error", "unknown function", "****"). Clean tail (only benign dvar-domain warnings like `bg_shock_viewKick*`) = compiled OK. Note the boot dumps ~2994 dvars, so grep for real error phrases, not dvar *names* containing "error"/"round".
- `...\mods\mp_gunfight\logs\games_mp.log` — the g_log. **GSC `logPrint()` output goes HERE, NOT console_mp.log**, plus per-round `InitGame:` lines. Repeated `InitGame` = rounds cycling cleanly.

Handy runtime proof for our mod: `gf_validateCustomLocations` logPrints "Gunfight custom spawn sets loaded for <map>: sets=N allies=N axis=N" (+ "custom overtime flag loaded"). Since the [[repo-release-branch-structure]] location cache, that line appears **once per match** (round 1 build) and NOT on later rounds' InitGames — that one-shot pattern is itself the proof the `game[]` location cache is working (pre-cache it logged every round).

Both logs are held open by the running server, so robocopy /MIR can't purge them (harmless EXTRA errors in deploy output; FAILED count stays 0). See [[vps-server-provisioned]].
