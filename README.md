# Gunfight — Plutonium T5 (Black Ops 1)

A faithful recreation of Cold War's Gunfight mode for **Black Ops 1** running on [Plutonium T5](https://plutonium.pw).

2v2. One life. Shared loadout. First to 6.

---

## Rules

- **2v2** — one life per player per round, no respawns
- **Shared loadout** — all four players use the same randomly selected primary, secondary, lethal, and tactical
- **60-second round timer** — if time expires, the team with higher total HP wins; equal HP is a draw
- **Loadout rotates every 2 rounds** alongside a side swap
- **First to 6 round wins** takes the match

---

## Installation

1. Copy the `raw/` folder contents into your Plutonium T5 storage:
   ```
   %appdata%\Plutonium\storage\t5\raw\
   ```
2. In Plutonium, set the gametype to `sd`
3. Load the mod:
   ```
   loadMod mp_gunfight
   map_restart
   ```

> The mod folder is named `mp_gunfight` so it appears in the in-game Mods menu.

---

## Configuration

Set these in your server config or the Plutonium console **before** the map loads:

| Dvar | Default | Description |
|------|---------|-------------|
| `gf_round_time` | `60` | Seconds per round |
| `gf_rounds_per_loadout` | `2` | Rounds before sides swap and loadout rotates |
| `gf_win_limit` | `6` | Round wins required to win the match |

---

## Loadout Pool

All 12 loadouts are drawn without replacement — every loadout plays before any repeats. The active loadout is always excluded from the next pick so it never plays back-to-back.

Each primary has a pool of attachments; one is randomly selected per round (with a ~33% chance of no attachment).

All loadouts give: **Lightweight**, **Hardened (Deep Impact)**, **Marathon**

| # | Name | Primary | Attachments | Secondary | Lethal | Tactical |
|---|------|---------|-------------|-----------|--------|----------|
| 1 | FAMAS / Python | FAMAS | Reflex, ACOG, Silencer, Extended Mags | Python | Frag | Concussion |
| 2 | Galil / Colt 45 | Galil | Reflex, ACOG, Silencer, Extended Mags | Colt 45 | Semtex | Flash |
| 3 | M16 / Python | M16 | Reflex, ACOG, Silencer, Extended Mags | Python | Frag | Flash |
| 4 | Enfield / Makarov | Enfield | Reflex, ACOG, Silencer, Extended Mags | Makarov | Semtex | Concussion |
| 5 | AUG / Colt 45 | AUG | Reflex, ACOG, Silencer, Extended Mags | Colt 45 | Frag | Flash |
| 6 | Commando / Python | Commando | Silencer, Extended Mags | Python | Semtex | Concussion |
| 7 | AK74u / Colt 45 | AK74u | Reflex, ACOG, Silencer, Extended Mags | Colt 45 | Semtex | Flash |
| 8 | MP5K / Makarov | MP5K | Reflex, Silencer, Extended Mags, Rapid Fire | Makarov | Frag | Concussion |
| 9 | Spectre / Python | Spectre | Reflex, Silencer, Extended Mags | Python | Frag | Flash |
| 10 | Uzi / Colt 45 | Uzi | Reflex, Silencer, Extended Mags | Colt 45 | Semtex | Concussion |
| 11 | L96A1 / Python | L96A1 | Silencer, Extended Mags, Variable Zoom | Python | Frag | Concussion |
| 12 | SPAS / Makarov | SPAS-12 | Grip | Makarov | Semtex | Flash |

---

## What's Built

- Round flow: elimination detection, HP tiebreaker on timer expiry, draw handling
- Loadout rotation: 12 loadouts, no-repeat random cycling, shared across all players
- Random attachment per round with configurable pool per loadout
- State persistence across `map_restart` via `gf_state_*` dvars
- Side swap every N rounds (configurable)
- Scoreboard: damage dealt tracked per player
- Perks: Lightweight, Hardened, Marathon on every loadout
- Perk pop-in notification on spawn (icon + name, right side, scale animation, 5s fade)
- HP readout HUD
- Bomb and objective fully suppressed (invisible, unusable)
- Audio: leader dialog callouts, last-alive music sting

## Roadmap

- Cold War style HUD (left side — player icons, HP bars, score dots)
- Overtime zone capture mechanic
- Mid-round join grace period
- Prematch control lockout
- Death sounds
- Minimap disable
- Forfeit handling (team drops to 0 players)
- More loadout variety (LMGs, Ithaca, Skorpion/MAC-11)

---

## Project Structure

```
raw/scripts/mp/
  mp_gunfight.gsc    entry point, init, state persistence, player lifecycle
  _gf_loadouts.gsc   loadout pool, picking, giving, attachment randomizer
  _gf_hud.gsc        HP display, perk pop-in notification
  _gf_rounds.gsc     round management, end conditions, audio, bomb suppression
```

---

## References

- [plutoniummod/t5-scripts](https://github.com/plutoniummod/t5-scripts) — Official T5 source dump
- [Resxt/Plutonium-T5-Scripts](https://github.com/Resxt/Plutonium-T5-Scripts) — Community T5 scripts
- [Plutonium modding docs](https://plutonium.pw/docs/modding/loading-mods/)
- [BO1 weapon strings reference](https://forum.plutonium.pw/topic/33166/bo1-item-commands)
