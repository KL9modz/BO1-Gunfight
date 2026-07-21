---
name: intro-sting-killed-by-underscore-shared-channel
description: The round-1 intro spawn sting -> ambient underscore hand-off is 100% stock and PER-PLAYER self-relative. Never drive the underscore level-wide (it clips late joiners). The wait is a fixed 15s floor.
metadata: 
  node_type: memory
  type: project
  originSessionId: 3985e91d-3ec4-4dd8-8894-48487f4d2d4a
---

**The engine handles the round-1 intro music itself, and correctly — leave it stock.** Do NOT "own" it.

**Mechanism (why native timing is perfect):**
1. The whole BO1 MP music system is **ONE shared client channel** (`maps/mp/_music.gsc::setMusicState`
   → a single `musicCmd` client-system state per player). Anything set on it **replaces** the current
   music; it does not layer.
2. The round-1 spawn sting (`game["music"]["spawn_<team>"]`, a long match-start piece in
   `mus/mp/spawn/long/`, e.g. `Chopperintro_spawn_long_a.wav`) and its ambient bed (`mus_underscore`,
   e.g. `Chopperintro_underscore_a.wav`, matched per map by the alias `loadspec`) are the **same
   composition** — the intro *resolves into its own loop*. There is **no alias crossfade** (`template
   MUS_NORMAL_2D` has empty `fade_in`/`fade_out`; it's a single-stream `music=yes` bus). The seam is
   **pure timing**, not a fade.
3. Stock nails the timing by being **PER-PLAYER and SELF-RELATIVE**: `sndStartMusicSystem` is threaded on
   `self` at each player's **own first spawn** (`_globallogic_spawn.gsc:100`, gated `!self.hasSpawned`)
   and does `wait 15; self set_music_on_player("UNDERSCORE")`. So every player's bed starts a fixed 15s
   after *their own* sting, and a **late joiner's is delayed exactly as much as their sting was** — it
   can never land mid-sting for anyone.

**The trap (a "fix" that was written and REVERTED):** neutering stock's switch with `level.nextMusicState`
and starting the underscore **level-wide** (all players at `prematch_over`, or any global timer) converts
the per-player self-relative offset into a **synchronized wall-clock cut** — on-time players segue fine,
but anyone whose sting is still playing gets **guillotined**. ⚠ **Never drive this channel level-wide.**
If it must be touched at all, keep stock's per-player self-relative model (`self thread ... wait N`).

**Rounds 2+ are SILENT by design (stock).** Every round END the engine calls a level-wide
`_music::setmusicstate("SILENT")` (`_globallogic.gsc:967`, in the round-end freeze), and nothing
re-triggers music after round 1: the sting is latched off (`pers["music"].spawn`=true, survives
map_restart) and `sndStartMusicSystem` is **connect-gated** (`hasSpawned` resets only in
`Callback_PlayerConnect`, not per round). So music is a MATCH-START event, not per-round — "only the first
round has music" is correct and intended. Quirk: because it's connect-gated, a brand-new player who
connects **mid-match** (any round) gets a fresh `pers["music"]` + `hasSpawned`=false and hears the full
sting on their first spawn — another reason the per-player self-relative model is the right one (it
anchors any joiner in any round; a level-wide push has no anchor for them).

**The one real limitation:** stock's `wait 15` is a **fixed floor** — the engine has no "music finished"
callback, so it just assumes the sting ≈15s. Perfect when the sting is ~15s; a silence **gap** if the
sting is shorter; a **clip** if the long sting overruns 15s. GF pulls the *long* stings, so whether stock
is perfect for GF is **UNTESTED** — verify by ear (does an on-time intro get cut before it resolves?). If
it clips, the fix is a **bigger per-player offset** (per-player `wait N` from each spawn), still
self-relative, **never** level-wide.

Net today: no runtime code change — GF music is back to pure stock; the value was understanding the
mechanism. Related: [[gf-timer-prematch-and-pause-model]].
