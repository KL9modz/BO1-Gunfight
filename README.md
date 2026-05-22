# Gunfight — Plutonium T5 (Black Ops 1)

Custom Gunfight mode for BO1 MP, layered over SD. Work in progress.

## Installation

1. Copy `raw/` into your Plutonium T5 storage folder (`%appdata%\Plutonium\storage\t5\`)
2. Set gametype to `sd`
3. In the Plutonium console: `loadMod mp_gunfight` → `map_restart`

## Configuration

| Dvar | Default | Description |
|------|---------|-------------|
| `gf_round_time` | `60` | Seconds per round |
| `gf_rounds_per_loadout` | `2` | Rounds before sides swap and loadout rotates |
| `gf_win_limit` | `6` | Round wins to win the match |

## References

- [plutoniummod/t5-scripts](https://github.com/plutoniummod/t5-scripts) — Official T5 source dump
- [Plutonium modding docs](https://plutonium.pw/docs/modding/loading-mods/)
- [BO1 weapon strings](https://forum.plutonium.pw/topic/33166/bo1-item-commands)
