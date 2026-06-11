# Gunfight Server Reference

All dvars can be set live in the server console or permanently in `dedicated.cfg` / `gamesettings/gf.cfg`. Changes to `dedicated.cfg` need a server restart; changes to `gf.cfg` take effect on the next `map_restart`.

---

## Gunfight Mod Dvars

set gf_debug_hud_pool 1

These are specific to the `gf` gametype. Set them in `gamesettings/gf.cfg` or the console.

| Dvar | Default | Range | What it does |
|---|---|---|---|
| `scr_gf_timelimit` | `1` | 0–1440 | Round time limit in **minutes** (0 = no limit). Set to `2` for a 2-minute round. |
| `scr_gf_scorelimit` | `6` | 0–10 | **Rounds needed to win the match.** This is the primary win condition. |
| `scr_gf_roundsperloadout` | `2` | 1–9 | How many rounds before the loadout rotates to the next one. |
| `scr_gf_overtimelimit` | `15` | 0–120 | Overtime flag-capture countdown in **seconds**. `0` disables overtime. |
| `gf_debug_spawns` | `0` | 0–1 | Enable spawn recorder tool (set before map loads, see `notes/spawn_recorder.md`). |

---

## Bot Control (Bot Warfare)

### Quick setup

```
// Fill the server to 4 total players (e.g. 1 real + 3 bots):
set bots_manage_fill 4

// Add 2 bots right now (one-shot, doesn't maintain count):
set bots_manage_add 2

// Remove all bots:
set bots_manage_fill 0
set bots_manage_fill_kick true
```

### Bot count dvars

| Dvar | Default | What it does |
|---|---|---|
| `bots_manage_fill` | `0` | Maintain this many total players; bots are added/removed to reach the target. `0` = no auto-fill. |
| `bots_manage_fill_kick` | `false` | If `true`, kicks bots when the total exceeds `bots_manage_fill`. |
| `bots_manage_fill_mode` | `0` | `0` = count everyone, `1` = count only bots, `2` = map-based target, `3` = map target + bots only. |
| `bots_manage_add` | `0` | Spawn this many bots immediately (consumed once, resets to 0). |
| `bots_manage_fill_spec` | `true` | Count spectators toward the fill target. |

### Bot team assignment

| Dvar | Default | What it does |
|---|---|---|
| `bots_team` | `autoassign` | Which team bots join: `autoassign`, `allies`, `axis`, or `custom`. |
| `bots_team_amount` | `0` | When `bots_team custom`: number of bots on axis. Remaining go allies. |
| `bots_team_force` | `false` | Force bots to stay on the assigned team. |
| `bots_team_mode` | `0` | `0` = count all players for balance, `1` = count only bots. |

### Bot behavior

| Dvar | Default | What it does |
|---|---|---|
| `bots_play_move` | `true` | Bots move around. |
| `bots_play_fire` | `true` | Bots shoot. |
| `bots_play_knife` | `true` | Bots melee. |
| `bots_play_nade` | `true` | Bots throw grenades. |
| `bots_play_camp` | `true` | Bots camp and follow teammates. |
| `bots_loadout_rank` | `-1` | Bot skill rank. `-1` = match players, `0` = random. |
| `bots_loadout_reasonable` | `false` | Filter out bad weapons/perks for bots. |
| `bots_loadout_allow_op` | `true` | Allow bots to use Juggernaut, Martyrdom, Last Stand. |

### Kick bots / players

```
kick all                  // kick everyone (bots and players)
kick botname              // kick a specific bot by name
```

During spawn recording, disable bots to avoid variable overflow:
```
set bots_manage_fill 0
set bots_manage_add 0
```

---

## Match Settings

Set in `dedicated.cfg` (requires server restart) or console (live).

| Dvar | Default | What it does |
|---|---|---|
| `party_minplayers` | `1` | Minimum players to start the pre-match countdown. Use `1` for solo testing, `2` for public. |
| `scr_game_prematchperiod` | `15` | Pre-match lobby countdown in seconds. |
| `scr_game_graceperiod` | `15` | Grace period at start of each round (no damage). |
| `scr_game_spectatetype` | `1` | `0` = disabled, `1` = own team, `2` = all players, `3` = all + free roam. |
| `scr_game_allowkillcam` | `1` | Show killcam after death. |
| `scr_game_allowfinalkillcam` | `1` | Show final killcam at round end. |
| `sv_maxclients` | `24` | Max player slots. |

---

## Map Rotation

Set in `dedicated.cfg`. Syntax: `gametype <gt> map <mapname>` pairs, space-separated.

```
set sv_maprotation "gametype gf map mp_villa gametype gf map mp_duga gametype gf map mp_cairo"
```

**Map name reference:**

| Display name | Map name |
|---|---|
| Array | mp_array |
| Cracked | mp_cracked |
| Crisis | mp_crisis |
| Firing Range | mp_firingrange |
| Grid (Duga) | mp_duga |
| Hanoi | mp_hanoi |
| Havana (Cairo) | mp_cairo |
| Jungle (Havoc) | mp_havoc |
| Launch (Cosmodrome) | mp_cosmodrome |
| Nuketown | mp_nuked |
| Radiation | mp_radiation |
| Summit (Mountain) | mp_mountain |
| Villa | mp_villa |
| WMD (Russian Base) | mp_russianbase |
| Berlin Wall | mp_berlinwall2 |
| Discovery | mp_discovery |
| Kowloon | mp_kowloon |
| Stadium | mp_stadium |

---

## Useful Console Commands

```
map mp_villa              // load a specific map
map_restart               // restart current map (reloads gf.cfg)
fast_restart              // restart without reloading assets (faster)
g_gametype gf             // set gametype (takes effect on next map)

kick all                  // kick all players
kick KL9                  // kick player by name
status                    // list connected players and their IDs
clientkick 1              // kick player by slot ID

set scr_gf_timelimit 2    // change round time live
set bots_manage_fill 4    // add bots to fill to 4 players live
```

---

## Files Quick Reference

| File | Purpose |
|---|---|
| `dedicated.cfg` | Server settings, map rotation, player limits |
| `gamesettings/gf.cfg` | Gunfight dvars, exec'd before each map |
| `maps/mp/gametypes/_gf_locations.gsc` | Custom spawn points and overtime flag locations |
| `notes/spawn_recorder.md` | How to record spawn points for new maps |
