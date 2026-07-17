# Developer Guide

How to build, branch, release, deploy, and use the dev tooling for Black Ops Gunfight.

*Part of the [Black Ops Gunfight](../README.md) documentation.*

This guide covers the contributor side: the repo layout, building `mod.ff`, the branch/release model, the deploy pipeline, and the dev-only tooling (RCON, bots, debug). For per-function and per-dvar detail, see [Reference](REFERENCE.md), and for running a server see the ops runbooks [VPS_DEPLOY.md](VPS_DEPLOY.md) and [VPS_HARDENING.md](VPS_HARDENING.md).

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
- `localizedstrings/cgame.str` (**overrides of stock engine strings** — a localizedstring in our `mod.ff` beats the game's own shipped-zone copy. The asset name is `<STR FILENAME>_<REFERENCE>`, so an engine `CGAME_*` string only takes effect from a file literally named `cgame.str`; the same entry in `gf.str` would compile to `GF_*` and be read by nothing.)
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

The VPS uses a **git-pull deploy model**. The full runbook is in [VPS_DEPLOY.md](VPS_DEPLOY.md); the script-level summary:

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

- **Match control:** `pause` / `resume`, `endround_allies` / `endround_axis`, plus the two restarts:
  - `roundrestart` — replays the current round: ends it as a `"tie"` through `gf_endRound` (no score), with `game["roundsplayed"]` pre-decremented (endGame's `++` nets it back, so the loadout doesn't rotate) and `level.roundswitch` zeroed for that cycle (so the sides don't switch).
  - `matchrestart` — restarts the whole match: scores 0-0, round 1, same map + teams. Snapshots the sides into `gf_teamplan`/`gf_botplan` and sets `gf_matchArmed=1` (dvars — they have to survive the wipe), fires `game_ended`, then `map_restart(false)` (fast, no map reload, re-fires the full match-start presentation). The post-restart `gf_waitForLoadingClients` pass consumes `gf_matchArmed`, skips the lobby hold and re-applies the plan.
  - ⚠ Neither is a raw `fast_restart` / `map_restart` console command, and a running match must never be restarted with one: GSC threads survive a `map_restart`, and the **only** thing that retires them is the `game_ended` notify `_globallogic::endGame` fires at each round end. Restart without it and the engine's re-`InitGame` threads a second `startGame()` → `prematchPeriod()`/`gameTimer()` on top of the survivors (double countdown), plus a second copy of every HUD/gate loop.
- **Perks:** `allperks_on/off`, `perksync` (re-applies the `gf_perk_on` / `gf_perk_off` override lists to live players without waiting for respawn — the loadout re-applies the same lists each spawn), plus bot difficulty `botdiff_easy/normal/hard/fu`.
- **Cheats/toggles:** `god_on/off`, `infammo_on/off` (native `sv_FullAmmo`), `radar_on/off` (`scr_game_forceradar` + match flags), `headshots_on/off` (sets `level.gf_headshotsOnly`, read by the damage handler), `killstreaks_on/off`, `regen_on/off`.
- **Per-player** (by entity number): `pgod_<n>`, `pfreeze_<n>`, `punfreeze_<n>`, `pperks_<n>`, `pnoclip_<n>`.
- **Visual/fun:** `vision_<set>`, `thirdperson_1/0`, `fps_1/0`, `expbullets_on/off` (`gf_expbullets_radius` slider), `drunk_on/off`, `invis_on/off`, `quake`, `tpall`, `saymsg` (prints the `gf_say` dvar).

See the header of `maps/mp/gametypes/_gf_bridge.gsc` for the complete command list.

---

## Bots (dev / listen-server)

The bot framework is vendored under `maps/mp/bots/` (`_bot_loadout`, `_bot_script`, `_bot_utility`; original author INeedGames) and integrated by `maps/mp/gametypes/_bot.gsc`. `_bot::init()` registers the `bots_*` dvars (kept for the vendored AI) and threads `diffBots` (difficulty) plus the Gunfight **round-boundary TEAM reconciler** — the single authority over next-round team composition (see the big header block in `_bot.gsc`). Each boundary pass: (1) seats the team-size-lock queue (spectating humans, join order); (2) evens the **human** split to off-by-1 (`gf_team_balance`, most recent joiner moves via `pers["gf_joinSeq"]`); (3) pads both sides with bots to `max(bigger human side, gf_fill_n)` — `gf_fill_n` is the per-team target (default 2), 0 = no bot fill (stages 1-2 still run). BotWarfare's own managers (`addBots` / `teamBots` / `doNonDediBots`) are **deleted**. It is wired in from `gf.gsc` inside a `#strip-begin … #strip-end` block, so it is **stripped from public builds** — bots and the team system are a development / server-side aid only.

Gunfight-specific behavior that matters:

- The reconciler acts **only at round boundaries** — round end (inside the killcam), the match-start gate release, and one roster-settle pass after init — and only through race-free primitives: a quiet pers reassign (`gf_botQuietSetTeam` / `_gf_rounds::gf_quietSetTeam`) for un-"playing" clients, the deferred `pers["gf_parkPending"]` / `pers["gf_movePending"]` marks (consumed pre-spawn by `gf_lobbyMaySpawn`) for alive ones, the sequenced prematch move (`_gf_rounds::gf_seqTeamMove` — suicide → death settles → reassign → respawn), kicks, and 0.5s-staggered generation-stamped adds. It never moves a client mid-round and never raw stock-switches one (the stock team switch's async suicide racing the respawn was both the historical "bots suicide at spawn" bug and the rare "spawned on the wrong team / at 1 HP" bug).
- `bot_set_difficulty()` (`easy` / `normal` / `hard` / `fu`) is the dvar set behind the bridge's `botdiff_*` commands. It rewrites the whole `sv_bot*` preset from whatever `bot_difficulty` holds, and `diffBots` re-runs it every 1.5s — so `bot_difficulty` always reflects the live difficulty (the panel reads it on connect to highlight the right button). The default is **`fu`**, seeded if-empty in `gf.gsc`'s bot block; a `dedicated.cfg` value or a live `botdiff_*` still wins, since the preset writes the dvar back and the seed only fires when it's empty (first round after a server boot).

Bots run on both a local listen server and the dedicated VPS. The current Plutonium T5 build spawns test clients on a dedicated server without any executable patch (confirmed live 2026-07-04).

⚠ **`gf_fill_n` is seeded if-empty (2), so a `dedicated.cfg` line SILENTLY PINS the team size and the code default never applies.** The seed is `if ( getDvar( "gf_fill_n" ) == "" )` in `gf.gsc`, and `dedicated.cfg` is exec'd at boot **before** the gametype callback runs — so any cfg value wins, by design (a server owner must beat a code default). This bit us live 2026-07-16: the VPS cfg carried `set gf_fill_n "3"`, written back when the default was **0** (fill off) purely so a reboot wouldn't come back bot-free. Once the default became 2 that line was both redundant *and* the reason the VPS ran 3v3 after a deploy. The line is now **removed** — the cfg should carry only **deviations** from the defaults, never a restatement of one, or the same trap re-arms at the next default change. (This paragraph previously claimed `gf_fill_n` "never appears in `dedicated.cfg`" — it did, for months. Read the box, not the doc: `deploy.ps1` does not ship `dedicated.cfg`, so the live file is whatever the box has.)

---

## Debug tools — `_gf_debug.gsc`

Dev-only, gated behind dvars set **before** loading the map. Stripped from public builds (the `_gf_debug` include and `gf_debug_*` blocks in `_gf_rounds.gsc` are marker-wrapped).

| Dvar | Tool |
|---|---|
| `gf_debug_spawns 1` | **Spawn recorder** — record curated spawn points and the overtime flag in-game and print them as paste-ready `_gf_locations.gsc` GSC to the server log. Action-slot keys: `[1]` record point, `[2]` toggle team, `[3]` save set + print all sets, `[4]` undo last. Includes an on-screen legend and a live coords HUD (X/Y/Z + yaw, bottom-left). |
| `gf_debug_hud_pool 1` | **HUD pool overlay** — bottom-left readout of server team-elem and per-player client-hudelem counts (`SV: n/64  DRAWN: n/17`). The `DRAWN` figure tracks the empirical ~17 per-client *render* cap (an engine limit no script probe can read); the overlay turns red at/over budget. |

`_gf_debug.gsc` also has `gf_debugPrintPerks()` for dumping a player's active perks, and a `gf_do_dump` entity scanner referenced by the project notes.

---

## Working remotely (iPad / travel)

**Ops from any device → `gf-vps`.** A **Remote Control server** runs 24/7 on the VPS. Open the Claude **mobile app** (or `claude.ai/code`) → **Code** tab → session **`gf-vps`** (computer icon, green "Connected") → tell it to do ops: RCON via the panel API on `127.0.0.1:3000` (never a second poller), dvar/`dedicated.cfg` edits, log reads, `deploy.ps1`. **Outbound HTTPS only — no inbound port, no key on the device.** This is the answer to "drive the server from an iPad".

**How it's wired.** Scheduled task **`GF-ClaudeRC`** runs `claude rc --name gf-vps` (cwd `C:\gfdeploy\BO1-Gunfight`).

- ⚠ **`rc` is a HIDDEN subcommand** — `.command("remote-control",{hidden:true}).alias("rc")`, so it does **not** appear in `claude --help`. It is a **server mode**: it idles and spawns one child per session (`--print --sdk-url …/code/sessions/cse_…`). That is why it needs **no TTY** and works headless.
- ⚠ **Do NOT use the `--remote-control` FLAG instead.** That form starts an interactive TUI with RC bolted on, needs a real console, and under a scheduled task it registered nothing and **died on its own**. The flag and the subcommand are different features. This cost an evening.
- ⚠ **Registered from raw XML**, because PowerShell **cannot express an indefinite repetition**: `-RepetitionDuration ([TimeSpan]::MaxValue)` → `P99999999DT23H59M59S` and `([TimeSpan]::Zero)` → `PT0S` are **both rejected** by Task Scheduler. In XML, **omitting `<Duration>`** inside `<Repetition>` *is* "indefinitely".
- **Triggers: at-logon** (the box AutoAdminLogons as Administrator) **+ a 5-minute repetition**. With `MultipleInstancesPolicy=IgnoreNew` that repetition is a **self-heal poll** — a live server is left alone, a dead one restarts within 5 min. Needed because **a network outage >~10 min kills the session by design**.
- ⚠ **Exactly one `rc --name gf-vps` server may run** — two give `ambiguous: multiple remote-control servers match name`. Unregistering a task does **not** kill its running process, so after re-registering, kill any untracked server first or the task sits at `Ready` while an orphan keeps serving. **Ownership check: the server's parent must be `svchost.exe`** (Task Scheduler); a `powershell.exe` parent means it's an orphan.
- **Auth: full-scope OAuth** (`claude auth login`). ⚠ A `claude setup-token` token is **inference-only and is rejected** for Remote Control.
- ⚠ **If `gf-vps` dies while you are away, only SSH can restart it** — that is why port 22 is open to any IP (`SSH-Any-In (travel)`) and why **Blink Shell → `ssh Administrator@94.72.121.4` → `claude`** stays the break-glass path.

⚠ **Security:** this is a permanent agent with admin on the live game server, drivable by anyone holding the Claude account. **The Claude account is now equivalent to the SSH key** — 2FA on it carries the same weight.

**Authoring → Claude Code on the web.** Cloud sessions (Anthropic-managed Ubuntu VM on the GitHub repo) suit authoring: GSC loads as loose rawfiles, so it needs no build and no game install, and it keeps dev work off the box's **4 shared vCPUs** (which already log multi-second `GF_HITCH` stalls from steal time alone). ⚠ **Every cloud session's first move is `git checkout main`** — the GitHub default branch is `release`, so a fresh clone lands on the stripped public tree with neither the real source nor `.claude/CLAUDE.md`. ⚠ A cloud session only sees what is **pushed**.

**What nothing remote can do:** build `mod.ff`. It needs Windows plus the BO1 linker and `zone_source` tree on the dev box's `S:\` drive — ⚠ **`mod.ff` is a desktop-only artifact**, so menu/`.str`/`.csv`/FX work waits until you are home. Nor can anything test in-game.

### Dead ends — all four were tested live. Do not re-run this hunt.

| Path | Why it fails |
|---|---|
| **Cloud session → SSH to the VPS** | The sandbox egresses through an **HTTP/HTTPS-only proxy**; its allowlist takes **domains, not `IP:port`**, and **raw TCP never passes**. Architectural — **no firewall change or network-access setting fixes it** (opening 22 to any IP did nothing for this). ⚠ The published `160.79.104.0/21` looks like the answer and is not: it is documented for the **API service's** outbound calls, never for sandboxes, and a **shared** egress range is not an identity — allowlisting it would admit everything else exiting there. There is also **no secrets store** (env vars/setup scripts are plaintext, visible to anyone who can edit the environment, ~7-day cache), so a VPS key cannot live there. |
| **"SSH host" in the app's environment picker** | A real feature (config keys `sshHost` / `sshPort` / `sshIdentityFile` / `startDirectory`) and it **does** run the session on the VPS — but it is **brokered by the desktop app**, so the host **does not exist for the iPad** ("no sessions found"). Fine at the desk, useless for travel. |
| **`--remote-control` flag under a scheduled task** | Needs a real TTY. Registered nothing; process exited unprompted. Use the **`rc` subcommand** (above) instead. |
| **Remote Control on a laptop** | Dies when the laptop sleeps. The 24/7 VPS is what makes Remote Control viable at all — that reframing is the whole trick. |

> ⚠ There is no Anthropic product called "Claude Code Remote". The two real things are **Claude Code on the web** (cloud VM) and **Remote Control** (`claude rc`, a process on *your* machine steered from claude.ai / the mobile app).

> ⚠ **Not** the same thing: **Remote Control** (`claude remote-control`) exposes a *local* session on your laptop to the iPad. It dies when the laptop sleeps, so it is useless for travel. There is no Anthropic product called "Claude Code Remote".

---

## Contributing

- **Develop on `main`.** It carries the full source, history, and tooling. (A fresh clone lands on `release`; `git checkout main` first.)
- **Edit GSC freely** — no rebuild needed; `map_restart` to reload. Only rebuild `mod.ff` (via `.\tools\build_ff.ps1`) when you touch menus, strings, `gametypesTable.csv`, or FX.
- **Test on a listen server** in the Plutonium client (`loadMod mp_gunfight`, `g_gametype gf`, `map mp_havoc`); bots and the dev RCON tools are available there.
- **Push** with `.\tools\push_all.ps1`. Cut public/server artifacts with `package_release.ps1` / `package_server.ps1` only when releasing.
- Keep new dev-only wiring inside `// #strip-begin … // #strip-end` so it never reaches public builds, and never hardcode an `rcon_password` in GSC (the server packager will fail the build).

For per-function and per-dvar behavior, see [Reference](REFERENCE.md) rather than duplicating it here.
