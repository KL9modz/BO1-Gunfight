---
name: trigger-off-vs-script-notify
description: "T5 trigger_off only blocks player touches (moves origin -10000); script notifies pass through — divert them by reassigning the level var the notifier reads, timed via the init-frame ordering below"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6ce8413b-bbd4-4439-9ac7-f19a0fdb0040
---

T5 engine facts proven during the mp_radiation blast-door fix:

- `common_scripts\utility::trigger_off()` just stashes `self.realOrigin` and moves the trigger to origin −10000 (`trigger_off_proc`). It blocks **player/bot interaction only** — a script-side `ent notify("trigger")` still wakes every `waittill` armed on that entity.
- To suppress a stock script's hardcoded `level.someEnt notify("...")`, don't try to kill the listener (stock map threads usually have no endon) — **reassign the level var to a dummy `spawn("script_origin", (0,0,0))` before the notifier reads it**. Notifiers read the level var at fire time; already-parked `waittill_any_ents` listeners captured the real ent refs and are unaffected.
- Waking a parked `waittill_any_ents` with a manual notify *runs* the wait's body — it is never a "kill" mechanism.
- Init-frame ordering: map script `main()` runs before `Callback_StartGameType`, so a map's `waittillframeend` registers before anything the gametype threads — FIFO resume means a `waittillframeend` thread started from `onStartGameType` resumes **after** the map's deferred init (its `level.*` ent vars are already assigned). Stock per-thread timers keyed to `level waittill("prematch_over")` are deterministic offsets — you can slot between them (radiation: lights re-read vars at +0.1s, auto-open notify at +0.3s → swap at +0.2s).

Applied in `_gf_wager_zones.gsc::gf_disableRadiationDoors`. See also [[onprecache-once-per-match-loadfx-wiped]] (map_restart re-runs all of this every round, which is why the hook lives in onStartGameType).
