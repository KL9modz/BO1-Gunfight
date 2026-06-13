# Spawn Recorder — How To Use

## Setup (one-time)

`gf_debug_spawns 1` must be set before the map loads. It is already set in:
`%localappdata%\Plutonium\storage\t5\gamesettings\gf.cfg`

Remove it from that file when done recording all maps.

Disable bots while recording to avoid variable overflow:
```
set bots_manage_fill 0
set bots_manage_add 0
```

---

## Controls

These are the ActionSlot bindings saved in `config_mp.cfg` — they persist across sessions.

| Key | Action                                        |
|-----|-----------------------------------------------|
| `X` | Record point for active team                  |
| `7` | Toggle active team (allies / axis)            |
| `5` | Save current set + write code to games_mp.log |
| `6` | Undo last point for active team               |

Status HUD (top-left): `REC[allies]  S:0  A:0  X:0`
- S = saved sets, A = allies points in current set, X = axis points

---

## Recording a set (5 per side example)

1. HUD starts on `REC[allies]`
2. Walk to each allies spawn → **X** × 5 — HUD shows `A:5`
3. **7** — switches to `REC[axis]`
4. Walk to each axis spawn → **X** × 5 — HUD shows `X:5`
5. Walk to map center (overtime flag position)
6. **5** — saves set, writes GSC code to `games_mp.log`, screen says "Spawn sets printed to log"

To record a second set (round-rotation variety): repeat steps 1–6 before pressing **5**.
**5** always saves ALL accumulated sets at once.

---

## Output

Open `games_mp.log` (mod folder) after pressing Numpad 7. Look for lines like:

```
// === mp_villa - 1 spawn sets ===
    if ( mapname == "mp_villa" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (x, y, z), yaw );
        ...
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

// === mp_villa overtime flag at current position ===
    if ( mapname == "mp_villa" )
        return gf_ot( (x, y, z), yaw );
```

---

## Pasting into code

**Spawn block** → paste inside `gf_getCustomSpawnLocations()` in `_gf_locations.gsc`

**Overtime line** → paste inside `gf_getCustomOvertimeLocation()` in `_gf_locations.gsc`

After pasting, `map_restart` and confirm console prints:
```
Gunfight custom spawn sets loaded for mp_villa: sets=1 allies=5 axis=5
Gunfight custom overtime flag loaded for mp_villa
```

---

## Mistakes

- **Wrong point** → **6** undoes last point for active team. Switch teams first (**7**) to undo the other side.
- **Start set over** → **6** repeatedly until A:0 and X:0.

---

## Maps to record

Done:
- ~~mp_villa~~
- ~~mp_cosmodrome~~
- ~~mp_duga~~
- ~~mp_cairo~~
- ~~mp_russianbase~~
- ~~mp_crisis~~
- ~~mp_hanoi~~
- ~~mp_radiation~~
- ~~mp_mountain~~
- ~~mp_array~~
- ~~mp_nuked~~
- ~~mp_silo~~

Remaining — base game:
- mp_cracked
- mp_firingrange
- mp_havoc

Remaining — First Strike DLC 1:
- mp_berlinwall2
- mp_discovery
- mp_kowloon
- mp_stadium

Remaining — Escalation DLC 2:
- mp_gridlock
- mp_hotel
- mp_outskirts
- mp_zoo

Remaining — Annihilation DLC 3:
- mp_drivein
- mp_area51
- mp_golfcourse
