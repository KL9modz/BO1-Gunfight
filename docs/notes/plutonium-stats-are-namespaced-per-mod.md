---
name: plutonium-stats-are-namespaced-per-mod
description: "Plutonium keys the player stats profile to fs_game, so a mod is its own level-1 ladder — but there IS a server-side opt-out, the engine dvar modStats (0 = use the BO1 coregame profile). Stats only: config_mp.cfg settings still namespace per mod."
metadata: 
  node_type: memory
  type: project
  originSessionId: 3a74d168-843f-4a32-9b88-fb2afc799776
---

**⚠ CORRECTED 2026-08-17. This note used to say "No server-side opt-out exists (no dvar, no launch
arg — confirmed against Plutonium staff forum posts)." That was WRONG, and it was wrong in the
direction that closed the question for months.** The opt-out is **`modStats`**, a real Plutonium
engine dvar. Gunfight now ships **`modStats 0`**.

## The default, and why it exists

Plutonium gives every loaded mod its own player stats profile, keyed to **`fs_game`**:

```
%localappdata%\Plutonium\storage\t5\players\                      <- base/vanilla (coregame) profile
%localappdata%\Plutonium\storage\t5\players\mods\<modname>\
        mpstats  globalstats  mpstatsBasicTraining  config_mp.cfg  <- ONE FULL PROFILE PER MOD NAME
```

Verified on the dev box: separate profiles exist for `mp_gunfight`, `mp_snife`, `mp_EnCoReV8_3`,
`mp_CommunityDLC1`, `mp_snrservers-t5`, and the old `t5-gunfight-master` folder name. Plutonium's
stated reason is technical — a mod can add custom weapons/unlocks, so it needs its own stat blob.
⚠ **A mod-folder RENAME therefore resets everyone's rank** — the profile is keyed to the folder
name, not the content. (`fs_game` is literally `mods/mp_gunfight`, and the profile path is
`players/` + `fs_game`, which is why the layout looks the way it does.)

## The opt-out: `modStats`

**`modStats 0` = use the BO1 coregame profile. `modStats 1` = per-mod profile (Plutonium default).**

Proof, by this repo's own standard — a **live rcon read** on the dedicated VPS, with the known
placebo included as a control:

```
"modStats"            is: "1" default: "1"   Domain is 0 or 1     <- REAL, engine-registered
"use_localStats"      is: "0" default: "0"   Domain is 0 or 1     <- REAL (unrelated axis, leave it)
"g_fix_viewkick_dupe" is: "1" default: "1"   Domain is any text   <- the known INERT one (control)
```

A typed `0 or 1` domain plus a fixed registered default is the `g_fixBulletDamageDupe` signature;
`Domain is any text` is the `g_fix_viewkick_dupe` placebo signature
([[engine-dvar-defaults-from-log-dump]]). Corroboration:

- **Our cfg never set it** yet the live dedicated dvar dump reads `modStats "1"` next to
  `dedicated "dedicated internet server"` — so Plutonium's T5 module registers it, and a GSC
  seed-if-empty could never fire on it ([[seed-if-empty-dead-on-engine-registered-dvars]]). It is
  **cfg-owned**, same class as the `g_fix_*` family.
- **`plutonium-bootstrapper-win32.exe` carries three per-game description strings** for it —
  WaW, **BO1**, and BO2 wordings of *"Flag whether to use stats of mod (when running a mod) or to
  use stats of the &lt;game&gt; coregame"*. The BO1 one sits in the T5 block beside `mpstats` /
  `globalstats` / `mpstatsBasicTraining` / `use_localStats`. Someone wrote a T5 version.
- **Plutonium changelog:** *"Implemented `modStats` dvar. This lets server owners decide if their
  mod should use normal stats or it's own custom stats."*
- **Community server configs** document the values and the risk:
  `// 0 (Use Vanilla stats when a mod is ran **DANGEROUS**) 1 (Default behavior, mod = new stats)`.

⚠ **Remaining gap, stated honestly:** the changelog entry sits under the **T4 release**, and
registration is not proof the T5 code path honours it. Registered-but-inert is exactly the
`g_fix_viewkick_dupe` trap — though the typed domain argues strongly the other way. **The one live
test that settles it** is below.

## ⚠ It fixes STATS, not SETTINGS — two different layers

| | Layer | Fixed by `modStats 0`? |
|---|---|---|
| Rank / XP / unlocks (`mpstats`, `globalstats`, `mpstatsBasicTraining`) | stats | **Yes** |
| Settings / binds / FOV (`config_mp.cfg`) | filesystem, driven by `fs_game` | **No** |

In the bootstrapper these are two separate string clusters: `modStats` lives in the stats cluster
with the stat blob names, while `config_mp.cfg` lives in the filesystem cluster with `players` /
`mods/` / `usermaps` / `fs_basepath`. Local mtimes agree — `players/config_mp.cfg` is written before
a mod loads and `players/mods/mp_gunfight/config_mp.cfg` after.

And `fs_game` can't be dropped: the client is **forced** to match it (`fs_game mismatch between
server (%s) and client (%s)`), and it is what delivers `mod.ff` — the menu-layer HUD, custom camos,
the main-menu fork, the pause ticker, the `SB_SCORE`→"Damage" string, `net.iwi`. So the settings
half has **no server-side fix**; only player-side ones (copy the vanilla `config_mp.cfg` in once, or
junction `players\mods\mp_gunfight` at `players`).

## Consequences of shipping 0 (all deliberate)

1. **Two-way.** Gunfight registers ~5× stock XP (kill 500 vs 100, plus the 5 / 2.5 / 3.75 match
   scalars), so real BO1 ranks climb ~5× faster here. The site's "4XP Enabled!" promo is now a claim
   about the player's *real* rank.
2. **Not retroactive.** Rank already earned in `players\mods\mp_gunfight\mpstats` stays stranded in
   that file. Everyone's visible level jumps to their real one the first time they connect after the
   switch.
3. **The `_gf_fun` account editors stop being sandboxed.** `funlevel50_`, `funprestige_`,
   `funcodpoints_` and `fununlockpro` now write **real** profiles, permanently, with no undo.
   ⚠ **This is intended, not an oversight** — it is how a player who wants their Gunfight progress
   carried into their real profile gets it restored. It stays behind the panel's Cheat Verbs gate
   and is rare-use by policy. The comments in `_gf_fun.gsc` were updated to say so.
4. **Schema safety is why this is defensible for THIS mod.** The generic danger is a mod writing a
   blob that doesn't fit vanilla's DDL. We ship no weapon files, no `statsTable.csv`, no stats DDL;
   camos ride `weaponOptions.csv` and are applied at give time via `CalcWeaponOptions`, never
   persisted; `scr_disable_cac 1` means no class writes; and we deliberately avoid
   `incPersStat`/`statAdd`. Kill XP flows through stock `giveKillStats`, assists/captures through
   `_rank::giveRankXP`. The blob stays vanilla-shaped.

## The live test that closes the last gap

Local box, not the VPS. Set `modStats 0`, restart, join, get a kill, disconnect, then read mtimes:

- `players/mpstats` **starts** updating and `players/mods/mp_gunfight/mpstats` **stops** → the T5
  path honours the dvar.
- `players/mods/mp_gunfight/config_mp.cfg` **still** updates → confirms the settings half is
  unfixable server-side (expected).

## Where it is set

`dedicated.cfg` (VPS, box-local) + `server/dedicated.cfg.example`, next to `scr_xpscale`. Panel row:
**ADVANCED → ENGINE GAMEPLAY → Player Stats Profile**, badged `RESTART` because whether the engine
latches it is unverified and clients pick their stat set at connect.

Related: [[read-the-server-not-the-file]], [[engine-dvar-defaults-from-log-dump]],
[[seed-if-empty-dead-on-engine-registered-dvars]], [[xp-scrxpscale-readonly-and-dead-score-path]],
[[t5-clients-must-install-mod-no-autodownload]], [[encore-v8-feature-port]].
