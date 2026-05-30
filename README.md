# Gunfight — Plutonium T5 (Black Ops 1)

Custom Gunfight mode for BO1 MP. Work in progress.

## Installation

1. Clone or copy this folder into your Plutonium T5 mods directory:
   ```
   %appdata%\Plutonium\storage\t5\mods\mp_gunfight\
   ```
2. In the Plutonium console:
   ```
   g_gametype gf
   loadMod mp_gunfight
   map_restart
   ```

## Configuration

| Dvar | Default | Description |
|------|---------|-------------|
| `gf_round_time` | `60` | Seconds per round |
| `gf_rounds_per_loadout` | `2` | Rounds before sides swap and loadout rotates |
| `gf_win_limit` | `6` | Round wins to win the match |

## References

- [plutoniummod/t5-scripts](https://github.com/plutoniummod/t5-scripts) — Official T5 source dump
- [Plutonium modding docs](https://plutonium.pw/docs/modding/loading-mods/)
