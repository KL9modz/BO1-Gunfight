# Gunfight - Plutonium T5 (Black Ops 1)

Custom Gunfight mode for BO1 MP. Work in progress.

## Project Layout

This repository is intended to live at:

```
%localappdata%\Plutonium\storage\t5\mods\mp_gunfight\
```

Edit source files in this folder, especially:

```
maps\mp\gametypes\
scripts\mp\
ui_mp\
localizedstrings\
```

Generated files such as `mod.ff` and runtime logs are intentionally ignored.

## Build

From this folder:

```
powershell -ExecutionPolicy Bypass -File tools\build_ff.ps1
```

The build script stages files from `mod.csv`, runs the BO1 linker, and writes the finished package to:

```
%localappdata%\Plutonium\storage\t5\mods\mp_gunfight\mod.ff
```

After loading the mod in-game, use `map_restart` to reload script changes during testing.

## Configuration

| Dvar | Default | Description |
|------|---------|-------------|
| `scr_gf_timelimit` | `1` | Minutes per round |
| `scr_gf_overtimelimit` | `15` | Seconds of overtime after round time expires; `0` disables overtime |
| `scr_gf_scorelimit` | `6` | Round wins to win the match |
| `scr_gf_roundswitch` | `2` | Rounds between side switches |
| `scr_gf_roundsperloadout` | `2` | Rounds before the shared loadout rotates |
| `scr_gf_wagerzones` | `1` | Optional kill switch; stock wager-map zones are on by default |

Note: `scr_gf_wagerzones` and the offline wager extraction catalogs/tools are temporary safety/proof artifacts. Once wager-zone behavior is fully validated across the map pool, remove the dvar, delete any unneeded extraction artifacts, and hardwire wager zones on for simplicity.

## Overtime

When the round timer expires with both teams still alive, Gunfight starts overtime instead of ending the round immediately. `scr_gf_overtimelimit` controls the overtime duration in seconds; setting it to `0` skips overtime and resolves the round by living HP immediately.

Overtime creates a neutral hold-to-capture zone at the map's Domination B flag when that entity exists. Capturing the zone wins the round immediately. The overtime clock legitimately pauses while the zone is actively being captured, then resumes if the capture is interrupted. The overtime timer ticks with the stock countdown sound from 15 seconds down. If overtime expires without a capture, the round is awarded to the team with higher living HP; equal HP is a tie. If a team is wiped during overtime, the same overtime resolver ends the round immediately.

The B flag is available because `gf.gsc` keeps Domination gameobjects in the `_gameobjects` allow-list. Maps without a B flag fall back to HP-only overtime.

## Wager Zones

Gunfight uses the stock wager-map play spaces automatically. No console setup is required.

The key discovery: wager blockers are already baked into the map entity lump. They are tagged with:

```
script_gameobjectname "gun oic hlnd shrp"
```

Stock `_gameobjects::main( allowed )` removes map entities whose `script_gameobjectname` does not match the active gametype allow-list. Gunfight keeps those blockers by adding the stock wager gametype names to the allow-list. The default-on `scr_gf_wagerzones` dvar only exists as an opt-out switch.

What the implementation does:

- Uses `mp_wager_spawn` entities for team spawns when the current map has them.
- Preserves baked wager blockers by allowing `gun`, `oic`, `hlnd`, and `shrp` gameobject tags.
- Applies the smaller wager compass material through `_gf_wager_zones.gsc`.
- Never enables the wager-match framework; do not set `xblive_wagermatch` to `1` for Gunfight.
- Adds only the extra script-spawned Cosmodrome wager collision helpers.

Verified offline catalogs:

- `tools/wager_spawns/` lists maps with `mp_wager_spawn` entities.
- `tools/wager_entities/` lists baked wager blockers tagged for `gun oic hlnd shrp`.
- Confirmed blocker maps: `mp_array`, `mp_cracked`, `mp_duga`, `mp_hanoi`, `mp_havoc`, `mp_russianbase`.

Normal test:

```
set g_gametype gf
map mp_havoc
```

Optional fallback test for the full map:

```
set scr_gf_wagerzones 0
map_restart
```

Do not use runtime entity dumps or local overrides of stock `gun.gsc` / `oic.gsc` for this feature. The proven path is the `_gameobjects` allow-list.

## References

- [plutoniummod/t5-scripts](https://github.com/plutoniummod/t5-scripts) - Official T5 source dump
- [Plutonium modding docs](https://plutonium.pw/docs/modding/loading-mods/)
