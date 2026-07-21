---
name: plutonium-stats-are-namespaced-per-mod
description: "Rank/level does not carry between our server and vanilla because Plutonium keys the player's stats profile to the mod name (fs_game) — not a mod bug, and there is NO server-side opt-out"
metadata: 
  node_type: memory
  type: project
  originSessionId: 3a74d168-843f-4a32-9b88-fb2afc799776
---

**Our server does not share rank progression with other BO1 servers because Plutonium gives every
loaded mod its own player stats profile.** Nothing in `mp_gunfight` causes this and nothing in
`mp_gunfight` can undo it.

The client derives the stats path from **`fs_game`** (the loaded mod name):

```
%localappdata%\Plutonium\storage\t5\players\                      <- base/vanilla profile (config only, locally)
%localappdata%\Plutonium\storage\t5\players\mods\<modname>\
        mpstats  globalstats  mpstatsBasicTraining  config_mp.cfg  <- ONE FULL PROFILE PER MOD NAME
```

Verified on this machine 2026-07-14: separate profiles exist for `mp_gunfight`, `mp_snrservers-t5`,
`mp_CommunityDLC1`, and the old `t5-gunfight-master` folder name. **A mod-folder RENAME therefore
resets everyone's rank on our server** — the profile is keyed to the folder name, not the content.

**The server IS ranked and XP IS saving** — don't chase this as an XP bug. `level.rankedMatch` is true
(`onlinegame 1` + `xblive_privatematch 0` + `xblive_wagermatch 0`), and `players\mods\mp_gunfight\
mpstats` + `globalstats` are written every session. The XP just lands in the mod's own file. Ranked
requires `IsGlobalStatsServer()` on PC (`_globallogic.gsc:21-35`); `fs_game` does **not** flip it.

**No server-side opt-out exists** (no dvar, no launch arg — confirmed against Plutonium staff forum
posts). Plutonium's stated reason is technical: a mod can add custom weapons/unlocks, so it needs its
own stat blob. The only true escape is to ship **no `mod.ff`** (loose GSC in `storage\t5\scripts\mp\`,
`fs_game` never set) — impossible for us: `mod.ff` is what registers the `gf` gametype row, the menu
HUD and the localized strings.

**Player-side workaround (the only one):** copy your vanilla `mpstats`/`globalstats` into
`players\mods\mp_gunfight\` once, before joining. It's a snapshot, not a link.

**Why it barely matters here:** rank is cosmetic in Gunfight — shared forced loadouts, `scr_disable_cac 1`,
no killstreaks, no unlocks. Nothing gated on level. But *"why am I level 1 on your server"* is a
predictable new-player question → worth a line in `docs/GETTING_STARTED.md`.

Related: [[read-the-server-not-the-file]], [[xp-scrxpscale-readonly-and-dead-score-path]],
[[t5-clients-must-install-mod-no-autodownload]].
