# Black Ops Gunfight - Gameplay & Design

How a round of Black Ops Gunfight plays, what decides a win, and the settings that shape it.

*Part of the [Black Ops Gunfight](../README.md) documentation.*

Black Ops Gunfight is a standalone round-based gametype (`gf`) for Call of Duty: Black Ops 1 on the Plutonium T5 client. This document covers everything that defines how the mode plays. For setup see [Setup](SETUP.md); for the full dvar/variable list see [Reference](https://github.com/KL9modz/BO1-Gunfight/blob/main/docs/REFERENCE.md); for developer internals see [Dev](https://github.com/KL9modz/BO1-Gunfight/blob/main/docs/DEV.md).

---

## Core concept

Two teams, one life each per round, the same randomly chosen loadout for everyone. Win the round by wiping the other team or holding more total health when the clock runs out. First side to six round wins takes the match.

The design strips the game down to the gunfight itself:

- **One life per round, no respawns.** When you die you are out until the next round. (`scr_gf_numlives` is registered at `1`.)
- **Shared random loadout.** Every player on both teams spawns with the *same* primary, secondary, lethal, tactical, and equipment for that round - the fight is about positioning and aim, not class advantage.
- **No killstreaks.** `level.killstreaksenabled = 0`, and the killstreak-call delay is registered at `0`.
- **No health regeneration.** `scr_player_healthregentime` is forced to `0`, `level.healthRegenDisabled = true`, and the regular-regen delay is pushed to a value that never elapses. Damage you take is permanent for the round.
- **No weapon drops.** `scr_disable_weapondrop` is forced to `1` every round - you keep the loadout you were given and cannot pick up enemy guns.
- **No perks shown pre-round.** The stock perk-on-spawn popup is disabled (`scr_showperksonspawn 0`); the mod's own loadout HUD owns all on-spawn display.
- **Class selection is suppressed.** `scr_disable_cac` is forced to `1`, so there is no create-a-class screen - the engine auto-assigns and auto-spawns players into the gunfight loadout.

These dvars are re-applied every round (on `map_restart`) in `onStartGameType`, because the engine reseeds the stock defaults before the gametype callback runs.

---

## The round

### Prematch (going live)

Each round opens with the engine's native prematch countdown. During prematch, controls (including firing) are frozen, the intro VO plays, the gametype hint is shown, and the round timer is hidden.

- The **first round of the match** uses a longer intro: `scr_gf_match_prematch_seconds` (default `15`).
- **Every later round** uses a shorter one: `scr_gf_prematch_seconds` (default `7`), and the on-screen banner reads "ROUND BEGINS IN" instead of the stock "MATCH STARTING IN".

A per-second beep is layered onto the prematch so the countdown is audible (the native countdown draws the number but plays no sound).

When prematch ends, the round goes live and the custom round clock starts (see below). A short grace period (`level.gracePeriod = 3`) covers the first moments; early-round player-vs-player damage is gated until the round is actually active.

### Winning the round

There are three ways a round ends:

1. **Last team standing.** The instant one team is fully eliminated, the round ends and the other team wins. If both teams are wiped on the same event, the round is a draw ("tie").
2. **Timer expiry decided by health.** If the clock runs out and exactly one team has living players, that team wins. If both teams still have someone alive, the round goes to **overtime** (see below). The health comparison is the **sum of every living player's HP** on each team - the team with more total remaining health wins; equal totals is a draw.
3. **Overtime capture or overtime HP** (covered in the Overtime section).

The native WIN/LOSS/DRAW banner shows a reason subtitle for the outcome: "Team eliminated", "Time expired - health advantage", "Time expired - equal health", "Objective captured", or "Both teams eliminated".

When a team is reduced to its last living player, that player hears a "last man" callout and a last-stand music sting.

### The custom round clock

Black Ops Gunfight runs its **own** round timer rather than the engine's. The stock timer fires a fixed "time running out" sequence (announcer VO, time-out music, and beeps) at hardcoded absolute thresholds - on a 45-second round that would trigger almost immediately and there is no dvar to retune it. So the mod pauses the native timer (which silences that whole sequence) and drives the HUD clock itself.

The mod's warning cues are:

- **A "timesup" announcer callout once at 15 seconds remaining** (generic, to both teams, no music).
- **Countdown beeps in the final 10 seconds only** - one per second, 10 down to 1.

When the clock hits zero, expiry is handed off to the mod's own handler, which routes to overtime or the health decision.

---

## Match structure

- **First to 6 round wins** takes the match (`scr_gf_scorelimit`, default `6`). Round wins are tracked cumulatively in `game["roundswon"]`, and the overall match leader is decided on that cumulative total.
- **Side switching.** Teams swap sides every `scr_gf_roundswitch` rounds (default `2`). At a side switch the attacker/defender sides flip and per-player round outcome is reset.
- **Draw rounds do not count.** A tied round (both teams wiped together, or equal total health at expiry) awards no round win to either side, so it does not advance either team toward the score limit.

The scoreboard shows kills, deaths, assists, and captures. Per-player score in this mode tracks total damage dealt (it does not pop a score-delta on every hit).

---

## Overtime

Overtime triggers when the round clock expires **and both teams still have at least one player alive** - nobody has been eliminated and the timer alone could not decide it.

### The hold-to-capture zone

A capture zone appears at a flag point on the map. Either team can capture it by standing in it; holding it for the capture time wins the round outright for the capturing team. Capture is purely positional - just being in the zone accrues progress, no button press needed.

- **Capture time** is `gf_capture_time` (default `3` seconds) in small mode, `gf_capture_time_large` (default `5` seconds) in large mode.

### The pausable overtime clock

Overtime has its own countdown (`scr_gf_overtimelimit`, default `15` seconds small / `30` seconds large). Its key behavior:

- While a team is actively capturing the zone, the overtime clock **pauses** (and is hidden) so the capture can resolve. If the capture is interrupted (the zone goes uncontested again), the clock **resumes** from where it stopped.
- If both teams are in the zone at once it is **contested** - no capture progresses, and the clock keeps running.
- Overtime also has countdown beeps: one per second from 10s down to 5s, then two per second for the final 5 seconds, driven off the overtime remaining time so the cadence freezes with the clock during a capture pause.

If the overtime clock expires with no capture, the round is decided by the same **total-team-HP tiebreak** as normal expiry (more living HP wins; equal is a draw).

### Zone colors - two independent layers

The zone communicates with two visual layers that carry different information:

| Layer | What it is | What it encodes |
|---|---|---|
| **Minimap icon + 3D flag icon** | Team-routed objective/objpoint elements | **Team-relative**: green when *your* team is capturing, red when the *enemy* is capturing, white when idle or contested |
| **Ground FX ring (apron)** | World-space effect, rendered the same for everyone | **Absolute** activity cue: white idle, gold while a team is capturing, red when contested |

The icons can be team-relative because they are per-team elements (one color shown to allies, another to axis from the same source). The apron cannot - world-space FX renders identically for every player, so it can only be an absolute cue. The two icon layers (2D minimap and 3D world flag) are driven from the same source so their colors always agree.

### Disabling overtime

Setting `scr_gf_overtimelimit` to `0` disables overtime entirely. With it off, a timer expiry where both teams are alive is decided **immediately** by the total-HP tiebreak instead of going to a capture round.

---

## Team-size modes (auto / large / small)

Black Ops Gunfight runs in two spatial modes selected by `scr_gf_teamspawnmode`: `auto` (default), `large`, or `small`. The mode is resolved every round.

| | **Small mode** | **Large mode** |
|---|---|---|
| When (auto) | Below 4v4 | Both teams have 4+ players |
| Spawns | Curated, clustered gunfight spawns; prefers the map's wager-spawn cluster, falls back to TDM spawns | Full-map standard TDM spawn pool |
| Map openness | Baked wager blockers are **kept** to shrink the play space | Wager blockers are **removed** so the whole map opens up |
| Overtime flag | Curated overtime spot for the shrunk zone | Native Domination B (center) flag |
| Wager minimap overlay | Applied | Not applied |

- **`auto`** picks large only when both teams have 4+ players. Because the roster is not fully settled when the round sets up (bots and late joiners connect afterward), the auto decision is captured once the round is active and everyone has spawned, then carried into the next round.
- **`large`** and **`small`** pin the mode regardless of player count - useful for an admin who always wants one or the other.

### Per-mode `_large` dvar variants

Several gameplay tunables have a separate `_large` copy so the two modes can be tuned independently without one clobbering the other:

| Tunable | Small dvar | Large dvar |
|---|---|---|
| Round length | `scr_gf_timelimit` (0.75 min = 45s) | `scr_gf_timelimit_large` (1.5 min = 90s) |
| Overtime length | `scr_gf_overtimelimit` (15s) | `scr_gf_overtimelimit_large` (30s) |
| Capture time | `gf_capture_time` (3s) | `gf_capture_time_large` (5s) |

---

## Loadouts & camos

All players share one randomly selected loadout per round, so every fight is symmetric.

- **Shared pool.** The mod ships a pool of pre-built loadouts (AR, SMG, LMG, sniper, shotgun, dual-wield, and heavy/mixed sets). Each entry is a curated primary + secondary + equipment, with the lethal and tactical layered on for an even spread.
- **Shuffle without repeat.** At the start of each match the pool is Fisher-Yates shuffled once, so no loadout repeats within a cycle and the order differs every match. Every player reads the same round-index into this shuffled pool, so loadout sync is guaranteed - no networking needed.
- **Rotation cadence.** The loadout changes every `scr_gf_roundsperloadout` rounds (default `2`, clamped 1-9). Selection is deterministic from the round counter, so the same round always yields the same loadout for everyone.
- **Lethal balance.** Lethals are spread evenly across the pool: Frag, Semtex (sticky grenade), and Tomahawk. Tomahawks spawn with 2; other lethals spawn with 1. (C4 is a satchel charge and appears only in the equipment slot, never as a lethal.)
- **Tactical balance.** Tacticals are spread evenly: Flash, Stun, Smoke, Gas, and Decoy. One tactical per spawn.
- **Equipment.** Camera Spike, Jammer, Motion Sensor, Claymore, and C4 are distributed across the pool's equipment slots.
- **Secondaries.** A mix of pistols (Python, Makarov, M1911, CZ75, each with a curated attachment), launchers (Crossbow, RPG, China Lake, M72 LAW), and dual pistols.
- **Built-in perks.** Every loadout carries the same fixed base perk set, tuned for mobility and survivability: **Lightweight** + **Lightweight Pro** (faster movement, no fall damage), **Marathon** (longer sprint), and **Flak Jacket** + **Flak Jacket Pro** (explosive resistance + grenade throwback). Perks are never shown on the pre-round screen. Admins can add or remove perks at runtime via the RCON override layer (`gf_perk_on` / `gf_perk_off`).

### Randomized camos

Every loadout rolls two independent random weapon camos at match start - one for the primary and one for the secondary (16 possible camos each, from stock gunmetal through patterns to Gold). The secondary camo only visibly displays on real-base secondaries (e.g. the explosive crossbow); on neutral-base pistols and launchers the roll is a harmless no-op and they render stock.

### Special weapons

Two special primaries are in the rotation:

- **Death Machine** (minigun) and **Grim Reaper** (M202) appear as primaries.
- Both reject real camos, so their camo is forced to stock.
- They are wired to behave as normal swappable primaries (using the wager builds, not the killstreak versions), so picking them does not fire a killstreak announcer or lock you out of switching weapons.

Every player also carries a knife. Weapon swapping speed is left fully stock by default.

---

## Settings that affect gameplay

The player- and admin-relevant gameplay dvars. Set them in the server config or via the console. For the complete list (including HUD, perk-override, and visual dvars) see [Reference](https://github.com/KL9modz/BO1-Gunfight/blob/main/docs/REFERENCE.md).

| Dvar | Default | Meaning |
|---|---|---|
| `scr_gf_timelimit` | 0.75 | Round length in minutes, **small** mode (0.75 = 45s) |
| `scr_gf_timelimit_large` | 1.5 | Round length in minutes, **large** mode (1.5 = 90s) |
| `scr_gf_scorelimit` | 6 | Round wins needed to win the match |
| `scr_gf_roundswitch` | 2 | Rounds between side switches |
| `scr_gf_roundsperloadout` | 2 | Rounds before the shared loadout rotates (clamped 1-9) |
| `scr_gf_overtimelimit` | 15 | Overtime seconds, **small** mode; `0` disables overtime (HP decides immediately) |
| `scr_gf_overtimelimit_large` | 30 | Overtime seconds, **large** mode |
| `gf_capture_time` | 3 | Overtime hold-to-capture seconds, **small** mode |
| `gf_capture_time_large` | 5 | Overtime hold-to-capture seconds, **large** mode |
| `scr_gf_teamspawnmode` | auto | `auto` \| `large` \| `small` (see Team-size modes) |
| `scr_team_maxsize` | 0 | `>0` caps players per team; overflow players are sent to spectator on spawn |

Round length, overtime length, and capture time each read a separate value per team-size mode, so tuning one mode never affects the other.
