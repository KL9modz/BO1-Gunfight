# mp_gunfight

A 2v2 Gunfight mode for **Plutonium T5** (Black Ops 1 Multiplayer).

All four players share the same randomly selected loadout. One life each. Shortest game, highest tension.

## Rules

- **2v2** — one life per player, 60-second round timer
- Round ends when one team is eliminated, or when the timer expires (HP advantage wins; equal HP = draw)
- All players receive the **same shared loadout** for every round (primary weapon with a random attachment, secondary, lethal, tactical)
- Every **2 rounds** teams swap sides and a new loadout is randomly selected
- **First to 6 round wins** takes the match

## Installation

1. Copy the contents of `raw/` into your Plutonium T5 mod folder:
   ```
   %appdata%\Plutonium\storage\t5\raw\
   ```
2. Set the gametype to `sd` in your server config
3. Load the mod in-game:
   ```
   loadMod mp_gunfight
   map_restart
   ```

## Configuration

Set these dvars in your server config or console before the map loads:

| Dvar | Default | Description |
|------|---------|-------------|
| `gf_round_time` | `60` | Seconds per round |
| `gf_rounds_per_loadout` | `2` | Rounds played before the loadout rotates |
| `gf_win_limit` | `6` | Round wins required to win the match |

## Loadout Pool

Loadouts are drawn without replacement until all have been played, then reshuffled. The active loadout is always excluded from the next pick so it never repeats back-to-back.

**Assault Rifles:** FAMAS, Galil, M16, Enfield, AUG, Commando

**SMGs:** AK74u, MP5K, Spectre, Uzi

**Snipers / Shotguns:** L96A1, SPAS-12

Each primary has a pool of attachments; one is chosen at random per round (with a chance of no attachment).

## Project Structure

```
raw/scripts/mp/
  mp_gunfight.gsc   -- entry point, init, state persistence, player lifecycle
  _gf_loadouts.gsc  -- loadout pool, picking, giving, random attachment
  _gf_hud.gsc       -- live HP display, perk pop-in notification
  _gf_rounds.gsc    -- round management, end conditions, audio, bomb suppression
```
