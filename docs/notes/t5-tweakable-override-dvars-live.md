---
name: t5-tweakable-override-dvars-live
description: T5 per-gametype tweakable override dvars (scr_<gt>_<cat>_<name>) are polled LIVE every 5s — the only way to change a tweakable mid-match without GSC; fixed the FF dedup this way
metadata: 
  node_type: memory
  type: project
  originSessionId: 06323407-8f87-4645-b5d6-eec95cfcd623
---

T5 stock tweakables (`_tweakables.gsc::registerTweakable(cat,name,dvar,def)`) capture their
dvar's value ONCE at round init — a live `set scr_team_fftype 1` does nothing until the next
`map_restart`. BUT `getTweakableValue(cat,name)` first checks a per-gametype OVERRIDE dvar
`scr_<gametype>_<category>_<name>` (e.g. gf: `scr_gf_team_fftype`) and returns it when
non-empty — and `_serversettings::updateServerSettings()` re-polls friendly fire this way
**every 5 seconds**. So writing base + override together = live-effective tweakable change
with ZERO GSC edits. Caveat: a stale override silently WINS over the base dvar forever —
any writer must always set both (the RCON panel's FF select, Set All, and 💾 Save all do,
via the row's `also:`/`data-also` mechanism).

**Why:** this is how the 2026-07-09 panel redesign fixed the "FF exists in 2 spots and
re-enables itself next round" bug — the old MATCH toggle wrote `scr_gf_ff`/`scr_team_ff`,
which nothing reads at all.

**How to apply:** for any other stock tweakable you want live-tunable from RCON (headshots,
killcam, spectate type... see `_tweakables.gsc` registrations), set `scr_gf_<cat>_<name>`
alongside the base dvar — but check what actually re-polls it: only values read through
`getTweakableValue` in a loop (like `updateServerSettings`'s FF poll) go live; ones read
once at init still need the next round. Related: [[gf-fill-reconciler-and-team-transfer]].
