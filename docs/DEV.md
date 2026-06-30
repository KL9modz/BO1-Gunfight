# Developer Guide

How to build, branch, release, deploy, and use the dev tooling for Black Ops Gunfight.

*Part of the [Black Ops Gunfight](../README.md) documentation.*

This guide covers the contributor side: the repo layout, building `mod.ff`, the branch/release model, the deploy pipeline, and the dev-only tooling (RCON, bots, debug). For per-function and per-dvar detail, see [Reference](REFERENCE.md), and for running a server see the ops runbooks [../VPS_DEPLOY.md](../VPS_DEPLOY.md) and [../VPS_HARDENING.md](../VPS_HARDENING.md).

---

## Dev environment & repo layout

The repo **is** the mod folder. A clone of `main` is dropped directly into the Plutonium T5 storage tree:

```
%localappdata%\Plutonium\storage\t5\mods\mp_gunfight\
```

so that loading and testing the mod is just `loadMod mp_gunfight` + `map_restart` in the Plutonium console.

```
mp_gunfight/                          (GitHub: KL9modz/BO1-Gunfight)
  .claude/CLAUDE.md                   project instructions / engine notes
  mod.csv                             build manifest the linker reads
  mp/gametypesTable.csv               registers the 'gf' gametype row in the UI
  localizedstrings/gf.str             localized UI strings
  ui_mp/
    hud_gf.txt                        menufile loader (loadMenu hud_gf_health.menu)
    hud_gf_health.menu                all mod HUD (health panel, loadout overview, self bar)
  maps/mp/gametypes/
    gf.gsc                            ENTRY POINT: main(), callbacks, precache, spawn pipeline
    _gf_rounds.gsc                    round lifecycle, overtime, damage/score, team-size mode
    _gf_loadouts.gsc                  loadout pool, shuffle, give, camo randomizer
    _gf_hud.gsc                       health panel + loadout overview + score popup
    _gf_locations.gsc                 per-map curated spawns + overtime flag points
    _gf_wager_zones.gsc               wager compass material + map-specific helpers
    _gf_debug.gsc        (dev only)   spawn recorder + entity/HUD-pool debug
    _gf_bridge.gsc       (dev only)   RCON -> GSC command bridge
    _bot.gsc             (dev only)   bot framework integration
  maps/mp/bots/          (dev only)   vendored bot framework (_bot_loadout/_bot_script/_bot_utility)
  raw/fx/misc/*.efx                   custom overtime apron FX source
  tools/                 (dev only)   build/release/deploy scripts + web RCON panel
```

The entry point is `gf.gsc::main()` — there is no `mp_gunfight.gsc`.

### GSC include graph

T5 does **not** support transitive includes: if A includes B and B includes C, A still cannot call C's functions. Every `.gsc` must `#include` every other file whose functions it calls **directly**, or you get an `unknown function` compile error attributed to the calling function.

The current graph (each file includes exactly what it calls):

| File | Includes (mod files) |
|---|---|
| `gf.gsc` | `_gf_locations`, `_gf_rounds`, `_gf_loadouts`, `_gf_wager_zones` (+ `_gf_bridge` dev) |
| `_gf_rounds.gsc` | `_gf_hud` (+ `_gf_debug` dev) |
| `_gf_loadouts.gsc` | `_gf_hud` |
| `_gf_hud.gsc` | stock `_hud_util` only |

Plus the stock engine scripts (`maps\mp\_utility`, `maps\mp\gametypes\_hud_util`, etc.) where used.

### T5 GSC gotchas (most common compile traps)

These are the calls that differ from T6/T7 and bite most often. The full list is in `.claude/CLAUDE.md` under *"T5 GSC — Critical API Differences"*.

| Broken in T5 mods | Correct T5 form |
|---|---|
| `getPlayers()` | `level.players` |
| `spawnStruct()` | associative array `s = []; s["k"] = v;` |
| `player isAlive()` / `isAlive(player)` | `player.health > 0` |
| `player.team` | `player.pers["team"]` (`"allies"` / `"axis"` / `"spectator"`) |
| `level.onGiveLoadout` | does not exist — use `level.giveCustomLoadout` |

When the compiler throws `unknown function: @ scripts/mp/<file>::<func>`, the broken call is **inside** that named function — scan its body for the cases above and for a missing `#include`.

---

## Building mod.ff

`mod.ff` is the compiled zone file. It registers the gametype in the UI (the `gf` row in `gametypesTable.csv`, the `gf.str` strings, the menu files) and compiles binary assets (the custom overtime apron FX). It is a **gitignored build output** — it is not on `main`.

**A rebuild is only needed when a *compiled* asset changes:**

- `mp/gametypesTable.csv`
- `localizedstrings/gf.str`
- `ui_mp/hud_gf.txt` or `ui_mp/hud_gf_health.menu` (menu **structure**)
- any `raw/fx/misc/*.efx`

**Pure GSC changes do NOT need a rebuild.** Plutonium loads the `.gsc` files as loose rawfiles straight from the mod folder. Edit a `.gsc`, then `map_restart` (or restart the server) — done. Likewise, HUD **dvar values / positions** are GSC-tunable at runtime; only the menu *layout* baked into the `.menu` needs a rebuild.

Build with the wrapper script (always — never call the linker by hand):

```powershell
.\tools\build_ff.ps1
```

`build_ff.ps1` reads `mod.csv`, stages each listed asset into the licensed BO1 tree's `raw/`, stages `mod.csv` into the zone-source paths the linker reads, runs `linker_pc.exe` (with cwd = `bin/`), cleans the staged files back out of `raw/`, then copies the built `mod.ff` back into the mod folder. It also explicitly stages `ui_mp/hud_gf_health.menu`, which is loaded transitively via `hud_gf.txt` and is therefore (deliberately) **not** a `mod.csv` `menufile` entry — listing the same `.menu` twice double-registers it and makes all gametypes vanish from the UI.

The linker needs the **licensed Black Ops 1 tree** with its modtools (`bin/linker_pc.exe`, `raw/`, `zone_source/`). The default path is baked into the script's `-GameRoot` parameter; override it if your install differs:

```powershell
.\tools\build_ff.ps1 -GameRoot "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740"
```

GSC rawfile errors from the linker are expected (Plutonium loads those directly). FX "image missing" errors for stock T5 materials are harmless — those images live in the base game fastfiles and resolve at runtime.

---

## Branch & release model

Two public-facing tiers come from one private dev branch.

| Tier | Content | Produced by |
|---|---|---|
| **`main`** | Everything — all gameplay + dev GSC (`_bot`, `bots/`, `_gf_bridge`, `_gf_debug`), `tools/`, `.claude/`, full comments/history. Develop here. | hand commits / `push_all.ps1` |
| **`release` branch** (GitHub default) + **Release zip** | Same minimal public snapshot: `mod.ff` + the gameplay GSC under `maps/` + a generated `README.md`. No dev files, no `tools/`, no `mod.csv`. | `package_release.ps1` |
| **Server bundle** (private) | A complete mirror of `main` **plus** the compiled `mod.ff` and a `dedicated.cfg`. The deliberate inverse of the release zip. | `package_server.ps1` |

> Because `release` is the GitHub **default branch**, a fresh `git clone` lands on the minimal snapshot (no `tools/`, no history). To develop, `git checkout main`. Keep pushing `main` via `push_all.ps1` — it is the only branch that carries history and tooling.

### Strip markers and comment stripping

Dev wiring that lives *inside* otherwise-shipped gameplay files (e.g. the `_gf_bridge` include and bot/RCON init in `gf.gsc`, the `_gf_debug` include and `gf_debug_*` blocks in `_gf_rounds.gsc`) is wrapped in markers:

```gsc
// #strip-begin
... dev wiring (real code on main) ...
// #strip-end
```

On `main` the marker lines are inert `//` comments, so the dev build runs normally. When staging a public output, `package_release.ps1`:

1. **`Strip-Markers`** — removes every `#strip-begin … #strip-end` region (marker lines + body).
2. **`Strip-Comments`** — removes all `//` line and `/* */` block comments from the staged GSC so the public source carries no dev notes. It is a character-scanning state machine (not a regex), so comment markers inside `"string literals"` (e.g. a `"http://"` URL) are preserved.

Order matters: markers are stripped **before** comments, because the marker lines are themselves comments but the wiring between them is real code — stripping comments first would leak the dev body. Pass `-KeepComments` to skip step 2 when debugging a release build. The fully dev-only files (`_bot.gsc`, `maps/mp/bots/*`, `_gf_bridge.gsc`, `_gf_debug.gsc`) are excluded by filename, not by marker.

### package_release.ps1 — public outputs

```powershell
.\tools\package_release.ps1                       # build mod.ff + stage + zip
.\tools\package_release.ps1 0.5.2                 # versioned zip
.\tools\package_release.ps1 0.5.2 -PublishBranch  # zip + force-push the 'release' snapshot
.\tools\package_release.ps1 0.5.2 -Publish        # zip + cut a GitHub Release (gh CLI)
.\tools\package_release.ps1 -SkipBuild            # reuse the existing mod.ff
.\tools\package_release.ps1 -KeepComments         # keep GSC comments in the public copy
```

The zip and the `release` branch carry **byte-identical content**. The branch is force-pushed as a single **orphan commit** (via temp git index + plumbing, working tree untouched) so no binary history accumulates while still including `mod.ff`. Output goes to the gitignored `tools/dist/`.

### package_server.ps1 — private VPS bundle

```powershell
.\tools\package_server.ps1                        # snapshot bundle (config as-is)
.\tools\package_server.ps1 0.5.2                  # versioned bundle
.\tools\package_server.ps1 0.5.2 -RotateRcon      # inject a fresh random rcon_password, print it
.\tools\package_server.ps1 0.5.2 -SanitizeConfig  # blank the rcon_password in the copy
.\tools\package_server.ps1 -IncludeRconTool       # also bundle the web RCON panel at top level
```

The mod folder in the bundle is enumerated via `git ls-files`, so its file set **is** `main` by definition (gitignored junk like `tools/dist`, logs, and the real `dedicated.cfg` are auto-excluded), plus the gitignored `mod.ff` added explicitly. The bundle also carries `dedicated.cfg` and a `DEPLOY.txt`.

**Secret guards:**

- The build **fails** if any staged `.gsc` hardcodes `setDvar("rcon_password", "<nonempty>")` — `dedicated.cfg` must be the sole owner of the password on the VPS.
- `-RotateRcon` rewrites **only the bundled copy** of `dedicated.cfg` with a fresh cryptographically-random alphanumeric password (≤ 23 chars, the Plutonium RCON login limit) and prints it to the console. The source cfg is untouched, so the live password is never the one sitting in git history. `-RotateRcon` takes precedence over `-SanitizeConfig`.

> This bundle is **private** — it contains a live `rcon_password`. Never attach it to a public GitHub Release.

---

## Deploy pipeline

Day-to-day, push from the laptop:

```powershell
.\tools\push_all.ps1                  # stage all changes, commit (auto message), push current branch
.\tools\push_all.ps1 "Tune perks"     # custom commit message
.\tools\push_all.ps1 "WIP" -NoPush    # commit only
```

The VPS uses a **git-pull deploy model**. The full runbook is in [../VPS_DEPLOY.md](../VPS_DEPLOY.md); the script-level summary:

**One-time readiness check** (read-only — changes nothing) run from inside the VPS clone:

```powershell
.\tools\vps_setup.ps1            # verify git, the clone, GitHub reachability, mod folder + IIS paths
.\tools\vps_setup.ps1 -WebDryRun # also preview a no-op web deploy
```

**Apply step** on the VPS — pulls latest and copies into the two live locations:

```powershell
.\tools\deploy.ps1 -Web                # mirror site\wwwroot -> IIS wwwroot (no restart)
.\tools\deploy.ps1 -Mod                # pull GSC + fetch release mod.ff -> Plutonium mods, restart server
.\tools\deploy.ps1 -Mod -Web           # both
.\tools\deploy.ps1 -Web -DryRun        # show what robocopy WOULD do
.\tools\deploy.ps1 -Mod -NoRestart     # copy mod files, leave the server running
```

`deploy.ps1 -Mod` mirrors the tracked tree and pulls `mod.ff` off the `release` branch (it is gitignored on `main`), then restarts the server by killing the bootstrapper (the restart loop relaunches it). Guardrails: it never touches `dedicated.cfg` (which lives in `storage\t5\`, outside the mod folder, and owns `rcon_password`); `-Web` refuses to publish if a secret-looking pattern is found anywhere under `site\wwwroot`; and the private `tools/rcon/` panel is part of the mod tree, never copied to the public site.

> Reminder: with FastDL (`sv_wwwBaseURL`) configured, Plutonium T5 **auto-downloads the server's `mod.ff` to clients on join** — so once the server and its FastDL host carry the new build, players get it automatically (no manual install). `deploy.ps1 -Mod` updates both together. The public package is the manual fallback / offline copy — re-cut it with `package_release.ps1 -Publish`.

---

## RCON tools (dev-only)

Both RCON tools are dev-only and stripped from the public release outputs.

### Web RCON panel — `tools/rcon/`

A zero-dependency Node.js panel (`server.js` uses only built-in modules; `public/index.html` is the UI). The HTTP server **binds to loopback only** (`127.0.0.1:3000`) and validates Host/Origin to resist DNS-rebinding. It speaks the UDP RCON protocol to the game server, parses `status` output (detecting bots and the local player), and reads the `gf_state` telemetry dvar for a live scoreboard. It runs on the same host as the server (or behind an SSH tunnel) — never exposed publicly.

```powershell
node tools\rcon\server.js     # then open http://127.0.0.1:3000
```

### In-game RCON bridge — `_gf_bridge.gsc`

The bridge polls the `gf_cmd` dvar every 0.5s and dispatches dev/admin commands sent over RCON (`set gf_cmd <command>`), and publishes the `gf_state` telemetry dvar every 2s (`alliesWins:axisWins:round:aliveAllies:aliveAxis:gametype`). Notable commands:

- **Match control:** `pause` / `resume`, `endround_allies` / `endround_axis`.
- **Perks:** `allperks_on/off`, `perksync` (re-applies the `gf_perk_on` / `gf_perk_off` override lists to live players without waiting for respawn — the loadout re-applies the same lists each spawn), plus bot difficulty `botdiff_easy/normal/hard/fu`.
- **Cheats/toggles:** `god_on/off`, `infammo_on/off` (native `sv_FullAmmo`), `radar_on/off` (`scr_game_forceradar` + match flags), `headshots_on/off` (sets `level.gf_headshotsOnly`, read by the damage handler), `killstreaks_on/off`, `regen_on/off`.
- **Per-player** (by entity number): `pgod_<n>`, `pfreeze_<n>`, `punfreeze_<n>`, `pperks_<n>`, `pnoclip_<n>`.
- **Visual/fun:** `vision_<set>`, `thirdperson_1/0`, `fps_1/0`, `expbullets_on/off` (`gf_expbullets_radius` slider), `drunk_on/off`, `invis_on/off`, `quake`, `tpall`, `saymsg` (prints the `gf_say` dvar).

See the header of `maps/mp/gametypes/_gf_bridge.gsc` for the complete command list.

---

## Bots (dev / listen-server)

The bot framework is vendored under `maps/mp/bots/` (`_bot_loadout`, `_bot_script`, `_bot_utility`; original author INeedGames) and integrated by `maps/mp/gametypes/_bot.gsc`. `_bot::init()` registers the `bots_*` management dvars and threads the add/fill/team management loops. It is wired in from `gf.gsc` inside a `#strip-begin … #strip-end` block, so it is **stripped from public builds** — bots are a development / listen-server aid only.

Two Gunfight-specific touches matter:

- `teamBots()` skips moving bots between teams while a round is live (`level.gf_roundActive`), because a mid-round team change respawns the bot and would drop it on the wrong side.
- `bot_set_difficulty()` (`easy` / `normal` / `hard` / `fu`) is the dvar set behind the bridge's `botdiff_*` commands.

Dedicated servers cannot spawn bots without an executable patch (documented in the `addBots()` comment); bots are intended for a local listen server.

---

## Debug tools — `_gf_debug.gsc`

Dev-only, gated behind dvars set **before** loading the map. Stripped from public builds (the `_gf_debug` include and `gf_debug_*` blocks in `_gf_rounds.gsc` are marker-wrapped).

| Dvar | Tool |
|---|---|
| `gf_debug_spawns 1` | **Spawn recorder** — record curated spawn points and the overtime flag in-game and print them as paste-ready `_gf_locations.gsc` GSC to the server log. Action-slot keys: `[1]` record point, `[2]` toggle team, `[3]` save set + print all sets, `[4]` undo last. Includes an on-screen legend and a live coords HUD (X/Y/Z + yaw, bottom-left). |
| `gf_debug_hud_pool 1` | **HUD pool overlay** — bottom-left readout of server team-elem and per-player client-hudelem counts (`SV: n/64  DRAWN: n/17`). The `DRAWN` figure tracks the empirical ~17 per-client *render* cap (an engine limit no script probe can read); the overlay turns red at/over budget. |

`_gf_debug.gsc` also has `gf_debugPrintPerks()` for dumping a player's active perks, and a `gf_do_dump` entity scanner referenced by the project notes.

---

## Contributing

- **Develop on `main`.** It carries the full source, history, and tooling. (A fresh clone lands on `release`; `git checkout main` first.)
- **Edit GSC freely** — no rebuild needed; `map_restart` to reload. Only rebuild `mod.ff` (via `.\tools\build_ff.ps1`) when you touch menus, strings, `gametypesTable.csv`, or FX.
- **Test on a listen server** in the Plutonium client (`loadMod mp_gunfight`, `g_gametype gf`, `map mp_havoc`); bots and the dev RCON tools are available there.
- **Push** with `.\tools\push_all.ps1`. Cut public/server artifacts with `package_release.ps1` / `package_server.ps1` only when releasing.
- Keep new dev-only wiring inside `// #strip-begin … // #strip-end` so it never reaches public builds, and never hardcode an `rcon_password` in GSC (the server packager will fail the build).

For per-function and per-dvar behavior, see [Reference](REFERENCE.md) rather than duplicating it here.
