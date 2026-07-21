---
name: connection-interrupted-mitigations
description: "Root cause + the levers applied for the between-rounds \"Connection Interrupted\" flash; note sv_maxRate lives ONLY in the VPS dedicated.cfg (untracked)"
metadata: 
  node_type: memory
  type: project
  originSessionId: c905da21-6ae3-4ada-9b8d-ae5ddf701a0b
---

Players saw the engine "Connection Interrupted" overlay flash the second a round ends/starts. It is the SOFT `CG_DrawDisconnect` (client draws it when the server stops acking its commands, at com_maxfps ~85-237), NOT a real drop. ⚠ **ROOT CAUSE — SUPERSEDED:** this was attributed to the server going snapshot-silent during stock `map_restart(true)` round cycling (an "unavoidable floor"). That is **wrong** — `GF_ENDTL` measured `dark=0ms` (the server never goes snapshot-silent) and `map_restart` runs *after* the killcam, so it can't land mid-replay. The real cause was the **final-killcam timescale dilation** (stock 0.25x) starving the usercmd ack rate, which is a real, fixable server-side problem — fixed by clamping the slow-mo floor to 0.6 ([[killcam-slowmo-timescale-usercmd-backlog]]). The levers below still helped the transition burst and remain valid operationally.

Levers applied 2026-07-03 (all attack the SAME transition burst from different angles):
- **sv_maxRate 5000 -> 25000** in the VPS `dedicated.cfg` (line ~490; backup `dedicated.cfg.bak-conninterrupt`). 5000 was the Plutonium/engine DEFAULT (not previously in the cfg) = only ~250 B/snapshot at sv_fps 20, throttling the round-transition data+HUD burst. **THIS LIVES ONLY ON THE VPS** — dedicated.cfg is gitignored/VPS-local, so it is NOT in the repo and will be lost if the cfg is ever regenerated. Re-add `set sv_maxRate "25000"` after any cfg rebuild. **Why:** biggest single-line win; drains the burst ~5x faster.
- **HUD push stagger** (git: `gf_hudRevealStagger` in _gf_hud.gsc) — offsets each human's ~40 round-start setClientDvar by client slot (getEntityNumber % 6 -> 0-0.25s) so ~2 players/frame instead of the whole lobby at once. Humans only (bot-guarded).
- **bridge once-per-match guard** + **bot-guard gf_showWeaponHUD** + **gf_initCustomLocations game[] cache** (earlier commits) shrank/spread the burst and killed the grows-over-match component.

**WHICH dedicated.cfg (verified 2026-07-12):** there are TWO on the box and only one is live.
- LIVE: `C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\dedicated.cfg` — the launch bat does `cd /D %LOCALAPPDATA%\Plutonium` + `+exec dedicated.cfg`, so this is the one the server loads. `set sv_maxRate "25000"` is on line ~491; confirmed live via the panel (`/api/dvars?fresh=1`).
- DECOY: `C:\gameserver\T5\T5ServerConfig-master\localappdata\Plutonium\storage\t5\dedicated.cfg` — a stale template copy. No `sv_maxRate`, and its `rcon_password` is EMPTY. Nothing reads it. A recursive `dir /s dedicated.cfg` under `C:\gameserver` finds ONLY this one, which is how it fools you. ⚠ "Restoring" the cfg from this template silently drops both sv_maxRate and the RCON password.

**How to verify live (not just on disk):** a cfg value only counts if it was exec'd at boot, so read the running server through the panel, not the file: `/api/dvars?fresh=1&names=sv_maxRate&password=<pw>` on `127.0.0.1:3000` (panel-first rule — no new direct RCON reader). As of 2026-07-12: sv_maxRate 25000, sv_fps 20, sv_maxclients 14, g_inactivity 300.

**The round-end killcam flash had a real fix, not just a floor:** the plug that flashed *on the killcam* was the final-killcam timescale dilation (see [[killcam-slowmo-timescale-usercmd-backlog]]), cleared by the slow-mo floor 0.6 — not an unavoidable `map_restart` artifact. If any flash recurs after that fix, confirm the live dvar above (`sv_maxRate`) before re-chasing a mitigation, and check the slow-mo floor.

**SSH gotcha:** the VPS `ssh` lands in PowerShell, so `&&`/`&` chaining fails, and `powershell -Command -` over stdin executes ~line-by-line — multi-line `foreach`/`if` blocks silently produce NO output. Use one-liners.

**How to apply next time:** raising sv_maxRate is the cheap high-leverage move for any transition-burst netcode symptom; animating the HUD slide-in does NOT help (it ADDS per-frame ui_gf_lo_off/alpha pushes — the flash is netcode, not HUD-render). sv_fps is 20 (NOT the 30 experiment), so tick jitter is not a factor here. See [[modff-drift-vs-gsc-deploy]], [[vps-gsc-deploy-log-verification]], [[paused-timer-freezes-gettimepassed]].
