# Spawn Recorder — How To Use

## Setup (one-time)

`gf_debug_spawns 1` must be set before the map loads. It is already set in:
`%localappdata%\Plutonium\storage\t5\gamesettings\gf.cfg`

Remove it from that file when done recording all maps.

Numpad bindings (set once in console, persist in config):
```
bind KP_5 "+actionslot 1"
bind KP_RIGHTARROW "+actionslot 2"
bind KP_HOME "+actionslot 3"
bind KP_UPARROW "+actionslot 4"
```

Disable bots while recording to avoid variable overflow:
```
set bots_manage_fill 0
set bots_manage_add 0
```

---

## Controls

| Key       | Action                                      |
|-----------|---------------------------------------------|
| Numpad 5  | Record point for active team                |
| Numpad 6  | Toggle active team (allies / axis)          |
| Numpad 7  | Save current set + write code to games_mp.log |
| Numpad 8  | Undo last point for active team             |

Status HUD (top-left): `REC[allies]  S:0  A:0  X:0`
- S = saved sets, A = allies points in current set, X = axis points

---

## Recording a set (5 per side example)

1. HUD starts on `REC[allies]`
2. Walk to each allies spawn → **Numpad 5** × 5 — HUD shows `A:5`
3. **Numpad 6** — switches to `REC[axis]`
4. Walk to each axis spawn → **Numpad 5** × 5 — HUD shows `X:5`
5. Walk to map center (overtime flag position)
6. **Numpad 7** — saves set, writes GSC code to `games_mp.log`, screen says "Spawn sets printed to log"

To record a second set (round-rotation variety): repeat steps 1–6 before pressing Numpad 7.
Numpad 7 always saves ALL accumulated sets at once.

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

- **Wrong point** → Numpad 8 undoes last point for active team. Switch teams first (Numpad 6) to undo the other side.
- **Start set over** → Numpad 8 repeatedly until A:0 and X:0.

---

## Maps to record

Priority maps (have both wager spawns and baked blockers):
- mp_array
- mp_cracked
- mp_duga
- mp_hanoi
- mp_havoc
- mp_russianbase

Wager spawns only (no baked blockers):
- mp_cairo
- mp_cosmodrome
- mp_crisis
- mp_mountain
- mp_radiation
- mp_villa
