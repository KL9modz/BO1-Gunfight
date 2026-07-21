---
name: stock-engine-string-override-via-modff
description: "A localizedstring baked into mod.ff OVERRIDES the game's own shipped-zone copy — the lever that killed the 'Connection Interrupted' banner (no cg_drawDisconnect dvar exists). Asset name = <STR FILENAME>_<REFERENCE>."
metadata: 
  node_type: memory
  type: project
  originSessionId: c744c337-8003-4081-9056-ab50fbe151a1
---

**A localizedstring in our `mod.ff` beats the stock copy in the game's shipped zone.** Verified in-game 2026-07-12 (probe: overrode `CGAME_SB_PING`, the scoreboard Ping header, and watched it change). This turns *any* single-purpose engine string into something we can retitle or blank — a capability we did not know we had.

**THE FILENAME PREFIX RULE (the trap).** A localized asset is named `<STR FILENAME>_<REFERENCE>`. Our `gf.str` declares `REFERENCE GAMETYPE_DESC` and the game reads `GF_GAMETYPE_DESC` — the `GF_` comes from the *filename*. So overriding the engine's `CGAME_CONNECTIONINTERUPTED` requires a **new `localizedstrings/cgame.str`** with `REFERENCE CONNECTIONINTERUPTED`, plus `localize,cgame` in `mod.csv`. Putting that reference in `gf.str` compiles to `GF_CONNECTIONINTERUPTED`, which **nothing reads** — it fails silently. Each string is its own asset, so a one-reference `cgame.str` shadows exactly that string, not the rest of the stock `CGAME_*` family.

**An EMPTY value renders as nothing** — the engine does NOT fall back to printing the raw key. (Tested explicitly, because a fallback would have put `CGAME_SB_PING` on screen — strictly worse than the thing we were hiding.)

**Shipped in `localizedstrings/cgame.str`:**
- `SB_SCORE` -> `"Damage"` — score in this mod IS cumulative damage dealt, so the stock "Score" header misled.
- `CONNECTIONINTERUPTED` -> `""` — blanks the between-rounds banner. Note the engine's own typo: **one R** in INTERUPTED.

**Why blanking was the ONLY option:** `CG_DrawDisconnect` is client engine code. Confirmed by dumping every `cg_draw*` dvar from `BlackOpsMP.exe` — there is `cg_drawFPS`, `cg_drawShellshock`, `cg_drawpaused`, ~25 others, but **no `cg_drawDisconnect`**. No dvar, and GSC/the menu layer can't reach it. See [[connection-interrupted-mitigations]] — this HIDES the banner, it does not remove the cause. ⚠ It was **never** "the irreducible floor of stock `map_restart(true)` round cycling" — GF_ENDTL measured `dark=0ms` (the server never goes snapshot-silent) and `map_restart` runs *after* the killcam, so it can't land mid-replay; the plug people actually saw was the final-killcam **timescale dilation** starving the usercmd ack rate, a real server-side cause now fixed by the slow-mo floor ([[killcam-slowmo-timescale-usercmd-backlog]]). Keep the blank as cosmetic cover for genuine lag only. **TRADE-OFF: it also suppresses the warning for genuine lag/packet loss.**

**Scope limits, before reaching for this again:**
- Overrides only reach clients that downloaded our `mod.ff` (FastDL) — i.e. people **already on our server**. It is a messaging/retention surface, **never** an acquisition/ads one. Attracting players = the serverkey browser label + `sv_motd` + the site.
- **Keep to single-purpose keys.** The scoreboard's other columns come from `MPUI_KILLS`/`DEATHS`/`ASSISTS`/`CAPTURES`/`DEFENDS`/`HEADSHOTS`/`ALIVE`, which are ALSO used by the combat record, leaderboards and after-action report — renaming one changes it **everywhere in the client UI**. `CGAME_SB_*` is scoreboard-scoped, which is why the Damage rename is contained.
- For our own persistent HUD text (e.g. a "gunfight.us" tag), use the **menu layer we already own**, not string hijacking.

**How to find a key:** the strings are NOT in the mod-tools `raw/` dump (they live in compiled stock zones). Dump them straight out of the client binary instead: `grep -a -o -E "CGAME_[A-Z_]+" BlackOpsMP.exe | sort -u`.

⚠ This is a `mod.ff` change: **not live on the VPS until rebuilt AND published via `origin/release`** ([[modff-drift-vs-gsc-deploy]]), and every republish forces all clients to re-download on next join ([[fastdl-first-join-black-screen-rebuild]]).
