# EnCoRe V8.3 feature port — the full 725 → ~120 accounting

**Source:** `%localappdata%\Plutonium\storage\t5\mods\mp_EnCoReV8_3` — CabCon's *EnCoRe Patch V8*
(v1.30, 2015), a console-era GSC mod-menu pack. 65 `.gsc` files, no `mod.csv`, no `mod.ff`, no assets.
It boots by **overriding stock `_rank.gsc`** (which threads `fyea::BuildMenu()` per player), opens on
`[{+smoke}]`, and switches between its 7 bundled guest patches by setting a dvar
(`v1`/`v2`/`v4`/`v5`/`v6`/`v7`/`L`) and calling `map_restart(false)`.

**Nothing in it is usable as-is here.** It overrides stock scripts we depend on, its status model is
`isHost()` (no host player on a dedicated server), several guest menus reference **Black Ops 2**
assets, and its whole delivery mechanism is an in-game menu we deliberately do not have. The port
re-expresses each *mechanic* as a bridge verb + an RCON panel control.

## Why 725 becomes ~120

The option count is mostly repetition, not distinct behaviour: 15 prestiges, 22 FOV values, 63 gun
X/Y/Z offsets (3 axes × 21 steps), 30 colour swatches, 35 raw vision names, ~40 weapon gives, ~50
canned chat lines, and 24 player models × 3 delivery modes (wear / rain / spawn). Each collapses to
one parameterised verb.

## Implementation status — PRUNED 2026-08-15 (owner review)

The first pass shipped ~29 verb families and a separate MODS tab. The owner reviewed each feature
and pruned for **performance and code size** (precache weight, load times, loops); the MODS tab was
deleted and the keepers merged into DASHBOARD/ADVANCED. What ships now:

| Panel home | Contents |
|---|---|
| DASHBOARD → FUN & VISION | The Vision Set dropdown now carries **two optgroups**: the 9 persistent keyed sets (`vision_`) and ~30 raw EnCoRe visions (`funvision_`, transient — the round-start re-apply overwrites them; SP names may be absent from some maps' zones, harmless no-op) |
| DASHBOARD → MOD TOOLS | Reset All Mods · give weapon (36) + take all · bullet mode (**11 modes**: 4 launchers, care packages, teleport, and **5 EnCoRe FX bullets** — lazy `loadfx` per round, impact entities tracked + deleted after 4s because `spawnFx` entities outlive their visual) · ride your grenade · positions (teleport / save / load / clone) · **Gersh Device** (a frag that teleports the thrower to where it lands) · 11 sounds · **per-team names** (`g_TeamName_Allies` / `_Axis` are separate server dvars) · splash message · **loading tip** (`didyouknow`; whether Plutonium's loading UI renders it is UNVERIFIED) |
| ADVANCED → CHAOS & ACCOUNT *(all gated on `gf_fun_cheats`)* | aimbot snap/silent per player · per-team god · **Adventure Time** (sphere-ride 2000u up, then the drop — can spend a life, hence gated) · **anti-quit** (2 Hz menu-close, deliberately NOT EnCoRe's 20 Hz — that is a reliable-command stream; menu-only, Alt-F4 still quits) · **prestige set** (EnCoRe's exact `setDStat plevel` + `setRank` pair) · **instant level 50** (its exact `statSet rankxp 1262500`) · CoD points · unlock pro perks (= EnCoRe's "Unlock All" — same call) |
| ADVANCED → CLIENT-ONLY MODS *(greyed on dedicated)* | the infections (aim assist / melee-damage / compass) · wallhack/names · tracers · sun & fog colour · **name / clantag / class-name editors** (archived dvars: `name`, `clanName`, `customclassN`) · dev overlays — each a 📋 console line; main-menu-only, host-only on a listen server |

**Pruned on owner review** (existed in the first pass, deleted): speed/jump/gravity/fall sliders,
fly, double jump, model swap, killstreak gives, music player, world builders + trampoline,
per-player kill/bring/goto, `funxp_`, and the `gf_funSetDvar` snapshot machinery only they needed.

**Deliberately not implemented, with reasons** (not oversights):
- **Health bar & crosshair picker** — per-client hudelems against the ~17-20 drawn cap plus colour
  busy-loops, and EnCoRe's crosshair is per-player `setText`
  ([[settext-configstring-exhaustion]]). We already ship a menu-layer health HUD. Owner concurred.
- **Trickshot slow-mo** — would fight `gf_killcamSlowmoClamp`; the timescale floor is load-bearing.
- **Long killcams** — `scr_killcam_time` is not registered in the raw MP dump; not shipping a placebo.
- **Controls Infection** — `cl_modcontroller*` is console-era controller anti-cheat machinery,
  meaningless on PC Plutonium.
- **"Spawn Hackenkreuz"** — builds a swastika. Nothing technical about that call.
- **Magician** — the menu entry references a function that does not exist anywhere in the pack.
- **Prestige note:** the first pass refused prestige-set as risky; the owner overrode, and it ships
  as EnCoRe's exact battle-tested sequence. ⚠ **The "blast radius is our own ladder" reasoning that
  justified it EXPIRED on 2026-08-17**: the server now ships `modStats 0`, so every account write
  here lands on the player's **real** Black Ops profile
  ([[plutonium-stats-are-namespaced-per-mod]]). Still shipped, still gated, now rare-use by policy
  and repurposed as the rank-restoration tool.

### What was verified statically, and what is still open

Done: strip verifier green after every tier (public build unchanged at **198 functions**); panel suite
34/34; `node --check` on `app.js`; GSC braces/parens balanced; **every call in `_gf_fun.gsc` resolved**
(all 125 called identifiers are either locally defined, a language keyword, a builtin confirmed present
in **`raw/maps/mp`**, or a fully-qualified stock function confirmed to exist — `incRankXP`,
`syncXPStat`, `setCodPointsStat`, `unlockItemFromChallenge`, `set_music_on_team`, `oldNotifyMessage`,
`gf_isHuman`, `gf_bridgeFindPlayer`, `gf_bridgeNotify`, plus post-prune: `clonePlayer`,
`SetWeaponAmmoClip`, `MoveTo`, `closeInGameMenu`, `setDStat`, `setRank`, `statSet`); every panel
verb cross-checked against the bridge dispatch; the new block titles (`MOD TOOLS`,
`CHAOS & ACCOUNT`, `CLIENT-ONLY MODS`) matched against `FAV_CATS` so every row pins.

⚠ **Still open: a real compile.** None of the above parses GSC. A syntax error or a builtin that is
registered in another VM but not MP surfaces only on a map load, and it fails the WHOLE server.
Acceptance is `loadMod mp_gunfight` + `map_restart` against a **LOCAL DEDICATED** server, then grep
`console_mp.log` for `unknown function` — a listen host would mask the client-dvar refusals half this
port is about.

## Verdict key

| Key | Meaning |
|---|---|
| **HAVE** | Already in `_gf_bridge.gsc` before this port. Do not re-implement. |
| **T1-T4** | Ported, by tier (see the plan). All new code lands in the dev-only `_gf_fun.gsc`. |
| **DEAD** | Structurally impossible on a dedicated server. Ships as a greyed `ded-lockable` row + 📋 clipboard line (Tier 5). |
| **N/A** | Meaningless in our setup (console-era, BO2 assets, or a stock system we already own better). Not ported, reason recorded. |

⚠ **DEAD means dedicated.** On a **listen host the same features work for the HOST only** — that
console *is* a client console, so a cheat-protected or archived dvar set there applies and sticks.
Remote clients on that listen host still refuse the push exactly as on dedicated. This is the same
asymmetry as [[flinch-bg-viewkickscale-not-replicated]] and
[[cheat-protection-is-client-side-rcon-can-set]]; the panel already models it with `.ded-lockable`.

---

## Main Mods / Fun

| EnCoRe option | Verdict | Note |
|---|---|---|
| God Mode | HAVE | `god_on/off`, `pgod_<num>` |
| Unlimited Ammo | HAVE | `infammo_on/off` |
| Give All Perks / Clear Perks | HAVE / T1 | `allperks_*`; clear is new |
| Invisible | HAVE | `invis_on/off` |
| Freeze Player | HAVE | `pfreeze_`/`punfreeze_` |
| Third Person | HAVE | `thirdperson_<0\|1>` |
| Toggle Vision | HAVE | `vision_<key>`, 9 sets |
| UFO Mode / Noclip | T1 | GSC flight (origin drive). The engine `noclip` command is listen-only and stays that way. |
| Suicide (self) | T1 | |
| Teleport to crosshair | T1 | Trace + `setOrigin` |
| Save / Load position | T1 | Per-player `pers[]` slot |
| Clone Self | T1 | `CloneSelf()` builtin |
| Double Jump / Jet Boots | T1 | GSC velocity |
| Toggle NoSpread | T1 | Partial: `perk_weapSpreadMultiplier` needs its `specialty_*` gate ([[perk-multiplier-defaults-are-the-effect]]) |
| Nade Training | T1 | Ported as **Ride Your Grenade**. Core is server-side (`LinkTo` + freeze + hide + invulnerable); only EnCoRe's `cg_fov 100` dressing is refused, so it rides at normal FOV. ⚠ Bounded at 6s — an unbounded ride strands the player frozen for the rest of a one-life round. |
| Matrix / Tracer Bullets | DEAD | ⚠ Looks server-side, is not: `DoTracers()` is four `cg_tracer*` client-dvar pushes (`fyea.gsc:2763`). Read the implementation, not the menu label. |
| Show FPS | DEAD | `cg_drawFPS` is archived (`seta`) — the existing `fps_` verb is kept only as the reproduction |
| Field of View toggle + changer | DEAD | `cg_fov` archived; Plutonium blocks server writes |
| Toggle Compass Size / map side | T1 | `compassSize` etc. are server-readable; verify each live before shipping the row |
| Big Overhead Names | DEAD | `cg_overheadNames*` are client `cg_` |

## Weapons / Bullets

| EnCoRe option | Verdict | Note |
|---|---|---|
| Give <weapon> (~40) | T1 | One `giveweapon_<name>` verb + a panel picker. ⚠ Our loadout system re-gives on every spawn, so a gift lasts the current life only — by design. |
| Give All / Take All | T1 | |
| Modded weapons (minigun, supplydrop, briefcase, camera, syrette…) | T1 | Same verb; the `_wager` builds need `PrecacheItem` ([[special-weapons-precacheitem-and-camo]]) |
| Explosive Bullets + radius | HAVE | `expbullets_on/off`, `gf_expbullets_radius` |
| RPG / LAW / China Lake / Minigun bullets | T1 | `MagicBullet` on `weapon_fired` |
| Care Package Bullets | T1 | |
| Teleport Bullets | T1 | |
| FX Bullets (5 effects) | T1 | `loadfx` handles are `level.*` → reload per round ([[onprecache-once-per-match-loadfx-wiped]]) |
| Melee/knife range | HAVE | `longknife_<n>` (`aim_automelee_range`) |
| Gun X / Y / Z position (63 options) | DEAD | `cg_gun_x/y/z` are cheat-protected client dvars |
| Weapon FOV (22 options) | DEAD | `cg_fov` — as above |

## Killstreaks / Bots / Game settings

| EnCoRe option | Verdict | Note |
|---|---|---|
| Give killstreak (10) | T1 | `givestreak_<name>`. ⚠ `level.killstreaksenabled` is 0 in GF; the give still works for the holder. |
| Blackbird always on | HAVE | `radar_on/off` |
| Spawn 1/3/5/10/18 bots, kick all, difficulty | HAVE | Our reconciler is strictly better — `gf_fill_n`, `botadd_*`, `botdiff_*`. Do **not** port EnCoRe's. |
| Super Speed / Jump / Gravity | T1 | `g_speed`, `jump_height`, `bg_gravity` — server dvars, rcon-settable ([[cheat-protection-is-client-side-rcon-can-set]]) |
| Timescale | HAVE | Already in `gf_bridgeServerDvarList` |
| Fast / Unlimited Sprint | HAVE | `sprintunlimited_<0\|1>` |
| Restart Match / End Match | HAVE | `matchrestart`, `endround_*`, `roundrestart` |
| Infinite Match | T1 | |
| Slow motion | T1 | ⚠ Must not collide with `gf_killcamSlowmoClamp` — check `level.inFinalKillcam` |
| Anti-Quit / Force Host | N/A | Console-era lobby-host concepts; no host player on dedicated |
| Hardcore Mode | N/A | We own the damage model (`scr_gf_headshot_scale`, Body Armor) |
| Developer toggles (killcam data, entity count, lagometer, bandwidth) | DEAD | All client `draw*` dvars |

## Outside effects

| EnCoRe option | Verdict | Note |
|---|---|---|
| 11 custom vision toggles + 14 named + 35 raw | T1 | Extend the existing `vision_` key map rather than adding a second path |
| Fog colour (11) | DEAD | `r_fog*` is the cheat-protected `r_*` family. The existing `visfog_` row already lives in a `ded-lockable` block for exactly this reason — it is not a working colour control on dedicated. |
| Sun colour (7) | DEAD | `r_lightTweakSunColor` etc. are cheat-protected `r_*` ([[rcon-dedicated-dvar-push-limits]]) |
| Sound player (17 aliases) | T1 | `playSoundOnPlayers` |
| Music player (7 states) | T1 | ⚠ **Never level-wide during round 1** — it guillotines a late joiner's intro sting ([[intro-sting-killed-by-underscore-shared-channel]]) |
| Sky colour (Waterfall) | T1 | |

## Admin / Host / Messages

| EnCoRe option | Verdict | Note |
|---|---|---|
| Teleport all to you | HAVE | `tpall` |
| Broadcast / Say | HAVE | `saymsg`, `adminmsg` |
| Typewriter message / MOTD | T1 | |
| Modded team names | T1 | `g_TeamName_Allies/Axis` (server dvars) |
| Drunken mode | HAVE | `drunk_on/off` |
| Earthquake / Quake | HAVE | `quake` |
| Health bar / crosshair text / kill text / heart text | T1 | ⚠ hudelems, and we are near the ~17-20 drawn cap ([[settext-configstring-exhaustion]]) — prefer `iPrintLn`, and never leave one allocated after `funreset` |
| Magician / Taliban / Adventure Time / Gersh / bleeding / centipede | T1 | Cosmetic model+FX toys |
| Decapitate | T2 | |
| Long killcams | T1 | Server-side killcam time |
| Camera bob toggle | DEAD | `bg_viewBobAmplitudeBase` — archived, and `bg_` does not replicate |
| Name wallhack / see-through-walls | DEAD | `cg_drawThroughWalls`, `cg_enemyNameFade*` |
| Menu design (colours, position, bar) | N/A | EnCoRe is styling its own in-game menu; we have none |

## Aimbot / player-affecting (Tier 2, gated behind `gf_fun_cheats`, default 0)

Normal aimbot · Unfair aimbot · Real-unfair · Real-head · Real-head-no-aim · Trickshot slow-motion ·
Give aimbot to a player · Give god to a player (**HAVE**: `pgod_`) · Teleport to me / to him ·
Force suicide · Clone player · Per-team godmode.

All are server-side (`setPlayerAngles`, `MagicBullet`), so they genuinely work on dedicated. They are
gated and auto-cleared at `gf_round_over` so a stray click cannot ride through a live public match.

## World builders (Tier 3)

Forge mode + ramp / wall / grids / teleporter / lift · Skybase (build + goto + spawn) · Bridge ·
Bunker · Prison · Skytext · Trampoline · Landmines · Drivable car · Torch · Mexican wave · Model
swapper (24 models × wear/rain/spawn) · Delete all entities.

⚠ **The entity budget is the whole risk.** EnCoRe's `WP()` helper stacks *hundreds* of models per
click (see `system_spawn.gsc` — the Prison call passes ~250 coordinate pairs per layer, 4 layers).
Mandatory: a `gf_fun_ents[]` registry, a hard cap, auto-cleanup on `gf_round_over`, and a
delete-all verb. Test with `g_print_entity_leaks 1`.

## Account / rank editors (Tier 4)

Instant level 50 · Prestige 1-16 (+999) · Unlock All · Unlock Pro Perks · CoD Points · XP lobby
(8 presets) · Class names · Clantag · Player name.

⚠ **Most of this cannot work the way the menu implies, and the rows must say so rather than lie:**
- Plutonium stats are **namespaced per mod** by default — but ⚠ **we opted out**: the server ships
  `modStats 0`, so account edits touch the player's **real BO1 profile**, not a private ladder
  ([[plutonium-stats-are-namespaced-per-mod]]). Any row implying otherwise is now a lie.
- **`scr_xpscale` is READ-ONLY** on Plutonium T5 from both rcon and cfg
  ([[xp-scrxpscale-readonly-and-dead-score-path]]). The XP-lobby presets cannot be implemented as
  EnCoRe implements them. The only working lever is assigning `level.xpScale` after `_rank::init`.
- `_persistence::unlockItemFromChallenge` (EnCoRe's `Account.gsc::UnlockPro`) **is** a real path and
  is the one piece here worth porting straight.

## Guest-patch extras (unique mechanics only)

| Patch | Unique | Verdict |
|---|---|---|
| Waterfall (Exelo) | Drivable car, landmines, jetpack, auto-dropshot, sky colour, news bars, kamikaze bomber, pickup players | T1/T3 |
| Waterfall | BO2 weapons (`mp7_mp`, `ballista_mp`…), BO2 killstreaks (VSAT, Lodestar, AGR…), BO2 map list | **N/A — wrong game.** These are the reason Waterfall's menu looks bigger than it is. |
| iMCS | Walking AC130, flyable jet, B52 kamikaze, derank/fire/money-all, get-everyone-drunk | T2/T3 (drunk: HAVE) |
| SwA / Derektrotter | Zip line, laser, stoned mode, flashing text | T1/T3 |
| RaZzA (McCoy5856) | Pro-mod editor, knockback dvar, show locations, crosshair presets | T1 |
| ElitePatch | Kick / verify / VIP / admin a player, grenade training | Partly HAVE (panel kick + `gf_admin_guids`); grenade training T1 |
| NaTo / EnCoReV5 | Nothing unique (subsets of the main menu) | N/A |
| All patches | Menu switching via `map_restart(false)` + per-patch `_rank.gsc` | **N/A** — that IS the delivery model we replaced with the bridge |

## Porting traps found while doing this (both cost real time — do not rediscover)

1. **`CloneSelf()` DOES NOT EXIST in T5.** EnCoRe calls it for "Clone Self" / "Clone Player" and it
   appears nowhere in the raw dump. The real builtin is **`clonePlayer( deathAnimDuration )`**, which
   stock MP uses for death corpses (`_globallogic_player.gsc:1691`). This is the general shape of the
   hazard: EnCoRe is console-era and several of its builtins are T6/other-VM names. ⚠ Verify every
   builtin a port reaches for against **`raw/maps/mp`** specifically, never all of `raw/`
   ([[vector-scale-in-common-scripts-utility]]). Verified MP-registered while porting: `MagicBullet`
   (`_copter.gsc:477`), `bulletTrace`, `playSoundOnPlayers`, `GetEye`, `GetVelocity`/`SetVelocity`
   (`mp_radiation.gsc:669/675`), `IsOnGround`, `SetOrigin`, `AnglesToForward`, `vector_scale`
   (needs `#include common_scripts\utility`).
2. **A per-player "already adopted" mark must be GENERATION-STAMPED, not a boolean.** Every fun loop
   carries `endon("game_ended")`, which fires at the end of **every round**
   ([[game-ended-fires-every-round-end]]) — so the threads die each boundary and are re-threaded by
   `gf_funInit`. But the mark lives on the player entity, which `map_restart(true)` preserves. With a
   boolean, the manager sees a stale mark, declines to re-thread, and the feature **silently stops
   working after round 1 while the panel still shows it ON**. `_gf_fun.gsc` stamps
   `level.gf_funGen = gettime()` per round and compares against it (`gf_funAdopted`).
3. **`PrecacheItem` is a phase, not a call.** Anything a fun feature gives or fires (`rpg_mp`,
   `m72_law_mp`, `china_lake_mp`, the 10 killstreak weapons) has to be precached in
   `gf.gsc::onPrecacheGameType` — inside a strip region, since the feature file itself is dropped.
   Without it both `GiveWeapon` and `MagicBullet` are **silent no-ops**, which reads as "the button
   does nothing" rather than as an error.

## Things deliberately NOT ported

- **The whole infection block** (`system_infection.gsc`): ~120 `setClientDvar` writes to `aim_*`,
  `player_*`, `cg_*`, `sv_cheats`, `sv_God`. Every one is a cheat-protected or archived **client**
  dvar → refused on arrival on dedicated. A handful (`aim_automelee_range`) already work and are
  already exposed; the rest is Tier 5 clipboard material.
- **`_rank.gsc` / `_globallogic.gsc` overrides.** Overriding a stock script means keeping its entire
  public surface ([[dlc-map-scripts-call-stock-bot-is-idle]]); we override `_bot.gsc` only, and
  reluctantly.
- **The in-game menu itself.** Our control surface is the panel; an in-game menu would need a
  `mod.ff` rebuild, hudelems against the drawn cap, and a per-round client event we do not have
  ([[menu-milliseconds-client-local-no-per-round-event]]).
