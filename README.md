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
| `scr_gf_scorelimit` | `6` | Round wins to win the match |
| `scr_gf_roundswitch` | `2` | Rounds between side switches |
| `scr_gf_roundsperloadout` | `2` | Rounds before the shared loadout rotates |

## References

- [plutoniummod/t5-scripts](https://github.com/plutoniummod/t5-scripts) - Official T5 source dump
- [Plutonium modding docs](https://plutonium.pw/docs/modding/loading-mods/)
