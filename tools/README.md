# Wager Zone Extraction Tools

These tools are for offline research only. Gunfight does not use runtime entity dumps for wager zones.

## Catalogs

- `wager_spawns/` contains `mp_wager_spawn` entities by map.
- `wager_entities/` contains baked wager blocker entities tagged with `script_gameobjectname "gun oic hlnd shrp"`.

## Regenerating

Inflate a map fastfile, then extract either wager spawns or wager-tagged entities:

```powershell
powershell -ExecutionPolicy Bypass -File tools\inflate_fastfile_zlib.ps1 -FastFile "path\to\mp_havoc.ff" -OutFile tools\ff_extract\mp_havoc.bin
powershell -ExecutionPolicy Bypass -File tools\extract_fastfile_entities.ps1 -InflatedFile tools\ff_extract\mp_havoc.bin -OutJson tools\wager_spawns\mp_havoc.json -Classname mp_wager_spawn
powershell -ExecutionPolicy Bypass -File tools\extract_fastfile_entities.ps1 -InflatedFile tools\ff_extract\mp_havoc.bin -OutJson tools\wager_entities\mp_havoc.json -Contains "gun oic hlnd shrp"
```

The generated `tools/ff_extract/` directory is ignored.
