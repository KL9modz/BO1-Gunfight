# `tools/` — dev & ops tooling

Everything in here is **dev-only**: `package_release.ps1` drops the whole folder from public
outputs, so nothing below ships to players.

**This file is only a map of the folder.** The authoritative how-to for each area lives in
[`docs/DEV.md`](../docs/DEV.md) — build pipeline, branch/release model, the RCON panel and
bridge, bots, debug tools — and in [`docs/VPS_DEPLOY.md`](../docs/VPS_DEPLOY.md) for the box
services. Don't restate their content here; a second copy drifts.

| Area | Entry points | Owned by |
|---|---|---|
| Build | `build_ff.ps1` (**the only way to build `mod.ff`**) | DEV.md → *Building mod.ff* |
| Packaging | `package_release.ps1` (public), `package_server.ps1` (private VPS bundle), `release_common.ps1` (shared drop-list + strip regex) | DEV.md → *Branch & release model* |
| Deploy | `deploy.ps1` (runs **on the VPS**), `push_all.ps1`, `rotate_secrets.ps1`, `vps_setup.ps1`, `vps_services/` | DEV.md → *Deploy pipeline*, VPS_DEPLOY.md |
| Verifiers (pre-commit gates) | `verify_release_strip.ps1`, `verify_locations.ps1`, `verify_loadouts.ps1`, `hooks/` | DEV.md → *Strip markers* |
| Admin panel | `rcon/` (loopback-only Node panel — **never** web-deployed) | DEV.md → *RCON tools* |
| Loadout authoring | `loadout_editor/` | CLAUDE.md → *Per-loadout perks* |
| Box services | `status_service/`, `conn_logger/`, `notify/` (each has its own README) | VPS_DEPLOY.md |
| Shared libs | `common.ps1`, `status_parse.js` + `status_parse.ps1` (the **single-sourced** `status` parser — extend it, never copy the parsing form), `ignore_list.ps1`, `map_names.ps1`, `ntfy.ps1` | — |
| Tests | `tests/` (Pester; `fixtures/status_reply.txt` pins both parser twins) | — |
| Measurement | `ts_sample.ps1` (samples timescale from **outside** the GSC VM — the only wall clock we have) | CLAUDE.md → *Final-killcam slow motion* |
| Wager-zone extraction | see below | this file |

Gitignored, never committed: `dist/`, `ff_extract/`, and the `*.local.json` stores —
`ops.local.json`, `ignore.local.json`, `security.local.json`, `rcon/secrets.local.json`,
`rcon/servers.local.json`, `rcon/prefs.local.json`. Their **`.example` twins are tracked** (the
ignore rules are globs with `!*.example` negations), so a fresh clone gets templates and no values.

---

## Wager-zone extraction (offline research only)

Gunfight does **not** dump entities at runtime — these were used once to author the curated
spawn/blocker data, and the catalogs are checked in so the extraction never has to be repeated.

- `wager_spawns/` — `mp_wager_spawn` entities, by map.
- `wager_entities/` — baked wager blocker entities tagged `script_gameobjectname "gun oic hlnd shrp"`.

Regenerating: inflate a map fastfile, then extract either set.

```powershell
powershell -ExecutionPolicy Bypass -File tools\inflate_fastfile_zlib.ps1 -FastFile "path\to\mp_havoc.ff" -OutFile tools\ff_extract\mp_havoc.bin
powershell -ExecutionPolicy Bypass -File tools\extract_fastfile_entities.ps1 -InflatedFile tools\ff_extract\mp_havoc.bin -OutJson tools\wager_spawns\mp_havoc.json -Classname mp_wager_spawn
powershell -ExecutionPolicy Bypass -File tools\extract_fastfile_entities.ps1 -InflatedFile tools\ff_extract\mp_havoc.bin -OutJson tools\wager_entities\mp_havoc.json -Contains "gun oic hlnd shrp"
```

The same two-layer-zlib trick also recovers a **DLC map's own GSC** (how Hotel's elevator script
was found) — see [[extract-dlc-map-gsc-from-fastfile]] in `docs/notes/`.
