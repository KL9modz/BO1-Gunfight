# mp_gunfight â€” Plutonium T5 (Black Ops 1 MP) Gunfight Mod

---

## Dedicated Server Setup

**Launch script:** `C:\Users\klaze\AppData\Local\Plutonium\storage\t5\T5ServerConfig-master\!start_mp_server.bat`
**Config:** `C:\Users\klaze\AppData\Local\Plutonium\storage\t5\dedicated.cfg`
**Game files:** `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops\`
**Mod files:** `C:\Users\klaze\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight\`

**To start:** run `!start_mp_server.bat` (auto-restarts on crash).
**To connect locally:** `connect 127.0.0.1:28960` in the Plutonium client console.

**Deviation from official docs** â€” The [Plutonium T5 server docs](https://plutonium.pw/docs/server/t5/setting-up-a-server/) say to place the bat files inside the game folder so that `set gamepath=%cd%` resolves correctly. Our bat lives in `T5ServerConfig-master` instead; we work around this by hardcoding `set gamepath=S:\SteamLibrary\steamapps\common\Call of Duty Black Ops` in the bat. The server works as-is â€” this note exists so the deviation is understood if the bat is ever moved or reset.

**Known cfg quirks:**
- `set scr_xpscale "1"` in `dedicated.cfg` is read-only on a dedicated server â€” harmless error, ignore it.
- `party_minplayers` must be `"1"` for solo testing; set back to `"2"` for a public server.

---

**Core Rules**
- One life per round, no respawns 
- No killstreaks, no health regen, no weapon drops â€” `level.killstreaksenabled = 0`, `level.healthRegenDisabled = true`
- 6-round win limit.
  - `level.roundWinLimit = 6` â€” belt-and-suspenders; `hitRoundWinLimit()` reads this level var directly
- Round wins tracked in `game["roundswon"]["allies"/"axis"]`; scoreboard accumulates correctly
- HP comparison on timer expiry 
- Draw rounds don't count toward win limit 

**Round System**
- SD-style round cycling, intermission, spawns

**Loadout System**
- Shared random loadout â€” all players get same primary/secondary/equipment each round
- Expanded loadout pool; shuffle-without-repeat, no back-to-back repeat
- Class select suppression â€” `scr_disable_cac=1`

**HUD**
- Loadout icon slide-in
- Perk display notification 
- HUD recreation per spawn 

### TODO 
- Kill-ding alias â€” `"mpl_killconfirm_killsound"` or `"mp_level_up"`
- **Mapvote** â€” removed; maps currently cycle via `sv_maprotation`. Needs a clean implementation. Key files preserved in repo (`scripts/mp/mapvote.gsc`, `scripts/mp/utils.gsc`, `ui_mp/scriptmenus/mapvote.menu`) but removed from `mod.csv` so they don't load. The DoktorSAS mapvote was working but is entangled with wager-match logic (`_wager::finalizeWagerRound/Game` calls in `mapvoteEndGame`). A replacement should use a simpler `replaceFunc` on `_globallogic::endGame` without the wager calls, and source its map list from a dvar or cfg rather than a hardcoded default.

---

## Wager Map Zone

### Proven approach

Gunfight uses the stock wager-map play spaces automatically without enabling the wager-match framework. No console setup is required.

The important discovery is that many wager blockers are already baked into the map entity lump. They are normal map entities tagged with:

```gsc
script_gameobjectname "gun oic hlnd shrp"
```

Stock `_gameobjects::main( allowed )` deletes entities whose `script_gameobjectname` does not match the gametype allow-list. Gunfight keeps the wager blockers by adding the stock wager gametype tags to `allowed`. The default-on `scr_gf_wagerzones` dvar only exists as an opt-out switch.

### Implementation

- `maps/mp/gametypes/gf.gsc` uses `mp_wager_spawn` for both teams when wager spawns exist.
- `maps/mp/gametypes/gf.gsc` keeps `gf` and `dom` gameobjects, then adds `gun`, `oic`, `hlnd`, and `shrp` before calling `_gameobjects::main( allowed )`.
- `maps/mp/gametypes/_gf_wager_zones.gsc` applies the wager minimap material and the extra Cosmodrome small-map collision helpers.
- `scr_gf_wagerzones` defaults to `1`; it does not need to be set during normal play.
- Set `scr_gf_wagerzones` to `0` only when intentionally testing full-map fallback behavior.
- Do not set `xblive_wagermatch` to `1`; enabling it brings back wager UI/lives/prematch side effects.

### Verified catalogs

Offline fastfile/entity extraction found the stock wager data without needing a runtime dump:

- `tools/wager_spawns/` lists maps with `mp_wager_spawn` entities.
- `tools/wager_entities/` lists baked blocker entities tagged with `script_gameobjectname "gun oic hlnd shrp"`.
- Maps with baked blocker catalogs: `mp_array`, `mp_cracked`, `mp_duga`, `mp_hanoi`, `mp_havoc`, `mp_russianbase`.
- Maps with wager spawns: `mp_array`, `mp_cairo`, `mp_cosmodrome`, `mp_cracked`, `mp_crisis`, `mp_duga`, `mp_hanoi`, `mp_havoc`, `mp_mountain`, `mp_radiation`, `mp_russianbase`, `mp_villa`.

### Normal test

```cfg
set g_gametype gf
map mp_havoc
```

Expected result: Gunfight loads normally, uses wager spawns/minimap, and preserves the stock visible blockers such as rocks, gates, fencing, sandbags, debris, and brushmodels.

Optional full-map fallback test:

```cfg
set scr_gf_wagerzones 0
map_restart
```

### Cleanup notes

Removed failed research paths from the project:

- No local overrides of stock `gun.gsc` or `oic.gsc`.
- No `gf_dumper.gsc` auto-loader script.
- No `xblive_wagermatch` dvar toggle — setting it was never necessary and activates the full wager framework.
- No plugin/DLL dvar timing workaround for this feature.

`_gf_debug.gsc` remains in the project as a general dev tool (spawn recorder + `gf_do_dump` entity scanner), but it has no connection to how wager barriers are enabled.

---
## Design Goals

> Focus on minimizing custom systems in favor of leveraging native engine functionality wherever possible. 
> Thoroughly review all relevant source files S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\raw\maps\mp\gametypesand dual.gsc.
> Identify redundant logic, inefficient patterns, and unnecessary custom implementations.
> Highlight areas where built-in or stock game engine systems can replace custom code.
> Investigate making the project more lightweight and maintainable.
> Reduce script complexity, execution overhead, and duplication.
> Ensure better integration with existing game framework features.
> Propose specific refactors to improve structure, readability, and modularity.
> Suggest simplifications that preserve functionality while reducing code size and complexity.
> Identify CPU-heavy logic, repeated calls, or inefficient loops.
> Suggest improvements that align with a more â€œOEM/stockâ€ feel.

### Core gameplay
- Round-based (last team standing ends the round, then killcam plays)
- 6 rounds to win the match
- One life per round â€” no respawns
- No killstreaks, no perks shown pre-round, no health regen, no weapon drops


### Loadout HUD (priority visual feature)
- On spawn: weapon icons slide in from the right â€” primary, secondary, lethal, tactical, then 3 perk icons
- All rows slide in simultaneously via `moveOverTime(0.5)`, hold 5.5s, slide back out


---

## Resources

### T5 Source Code
- **plutoniummod/t5-scripts** â€” Official Plutonium T5 source dump (MP + ZM gametypes, utility scripts, etc.)
  https://github.com/plutoniummod/t5-scripts
  Key files: `MP/Common/maps/mp/gametypes/shrp.gsc`, `gun.gsc`, `sd.gsc`, `_wager.gsc`, `_globallogic.gsc`, `_class.gsc`, `_hud_util.gsc`, `_rank.gsc`
- **Local T5 source dump** (user's machine): `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\raw`
- https://github.com/JTAG7371/T5-RawFile-Dump

### Community Mods (reference/pattern source)
- **Xinerki/t5-gunfight** â€” T5 Gunfight/duel gametype mod; source of confirmed weapon icon shader names and T5 player methods
  https://github.com/Xinerki/t5-gunfight
- **misterbubb/T6-Gunfight-Gamemode** â€” BO2/T6 Plutonium Gunfight; closest engine to T5, best code reference for overtime + equipment delay
  https://github.com/misterbubb/T6-Gunfight-Gamemode
  https://github.com/misterbubb/T6-Gunfight-Gamemode/blob/main/gunfight_mp/maps/mp/gametypes/sd.gsc
  https://forum.plutonium.pw/topic/43931/release-gunfight-gamemode
- **bblack16/plutonium-waypoints** â€” IW5/MW3 Gunfight port
  https://github.com/bblack16/plutonium-waypoints
  https://github.com/bblack16/plutonium-waypoints/blob/main/iw5/scripts/gamemode_gunfight.gsc
  https://forum.plutonium.pw/topic/37594/release-custom-game-modes-reinforce-gunfight-and-gun-game
- **iAmThatMichael/gunfight** â€” BO3/T7 Gunfight recreation; used for game-mode design reference
  https://github.com/iAmThatMichael/gunfight
  https://github.com/iAmThatMichael/gunfight/blob/master/scripts/mp/gametypes/gf.gsc
- **GunMd0wn custom_gunfight.gsc** â€” community Gunfight mod (runs on HQ/TDM); source of class-select suppression patterns and weapon dvar approach. No GitHub â€” search Plutonium BO1 forum or megathread.
- **mp_EMv2_Recreation, mp_iMCSx, mp_EnCoReV8** â€” Community BO1 mods; source of HUD element patterns (`newHudElem`, `newClientHudElem`, `NewScoreHudElem`, `hud.archived`, `fontPulse`)
- **Resxt/Plutonium-T5-Scripts** â€” Collection of community T5 GSC scripts
  https://github.com/Resxt/Plutonium-T5-Scripts
- **CabConModding BO1 weapons GSC tutorial**
  https://cabconmodding.com/threads/black-ops-1-all-about-weapons-gsc-tutorial.1268/


### Plutonium Docs & Forums
- **Loading mods into Plutonium**
  https://plutonium.pw/docs/modding/loading-mods/
- **Plutonium new GSC scripting features** (T5/T6 scripting extensions)
  https://www.plutonium.pw/docs/modding/gsc/new-scripting-features/
- **Plutonium BO1 modding releases & resources forum**
  https://forum.plutonium.pw/category/60/bo1-modding-releases-resources
- **BO1 mods megathread** (organized collection of mods, tutorials, guides)
  https://forum.plutonium.pw/topic/34555/megathread-organized-collection-of-bo1-mods-releases-tutorials-and-guides

### Future Projects (reference)
- **PlutoniumT5 map vote mod** â€” full mods folder + map vote system
  https://github.com/DoktorSAS/PlutoniumT5Mapvote
- **ProjectDonetsk/T9** â€” T9 port for Plutonium
  https://github.com/ProjectDonetsk/T9

---

## Building mod.ff

`mod.ff` is the compiled zone file that registers the gametype in the UI (strings, gametype table, mapvote menu). Rebuild it whenever `gametypesTable.csv`, `gf.str`, or `mapvote.menu` changes.

**Tools:** `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\bin\linker_pc.exe`

**Step 1 â€” stage source files to mod tools `raw/`:**
```
mod folder                              â†’ mod tools raw/
mp/gametypesTable.csv                   â†’ raw/mp/gametypesTable.csv
localizedstrings/gf.str                 â†’ raw/english/localizedstrings/gf.str
maps/mp/gametypes/_gametypes.txt        â†’ raw/maps/mp/gametypes/_gametypes.txt
maps/mp/gametypes/gf.txt               â†’ raw/maps/mp/gametypes/gf.txt
ui_mp/scriptmenus/mapvote.menu          â†’ raw/ui_mp/scriptmenus/mapvote.menu
mod.csv                                 â†’ zone_source/mods/mp_gunfight.csv
mod.csv                                 â†’ zone_source/english/assetinfo/mods/mp_gunfight.csv
```

**Step 2 â€” run linker from `bin/`:**
```
cd "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\bin"
linker_pc.exe -language english mods/mp_gunfight
```
GSC rawfile errors are expected â€” Plutonium loads those directly, they don't need to be in the zone.

**Step 3 â€” copy output back:**
```
zone/english/mods/mp_gunfight.ff  â†’  mods/mp_gunfight/mod.ff  (Plutonium storage)
```

**Gametype UI icon** â€” controlled by the 4th column of the `gf` row in `mp/gametypesTable.csv`.
Available values: `playlist_tdm`, `playlist_ffa`, `playlist_search_destroy`, `playlist_domination`, `playlist_headquarters`, `playlist_demolition`, `playlist_ctf`, `playlist_sabotage`.
Currently set to `playlist_tdm`. Change and rebuild mod.ff to update.

---

## Project Overview

Custom Gunfight game mode for Black Ops 1 running on Plutonium T5 MP.

**Load:** `loadMod mp_gunfight` in the Plutonium console, then `map_restart`.
**Mod folder must be prefixed `mp_`** for it to appear in the in-game mod menu.

```
Gunfight/  (GitHub: KL9modz/Gunfight)
  CLAUDE.md                        <- this file
  README.md
  .gitignore
  mp_gunfight.code-workspace
  .vscode/
    settings.json                  <- GSC extension config, runtime folder exclusions, rulers
    extensions.json                <- recommends eyza.aw-gsc
  raw/
    scripts/
      mp/
        mp_gunfight.gsc            <- entry point, init, state persistence, player lifecycle
        _gf_loadouts.gsc           <- loadout pool, picking, giving, attachment randomizer
        _gf_hud.gsc                <- HP HUD, perk pop-in display
        _gf_rounds.gsc             <- round management, end conditions, audio, bomb suppression
        mp_spawn_fix.gsc           <- spawn fix utility
      sp/
        zm_spawn_fix.gsc
```

---

## T5 GSC â€” Critical API Differences from T6/T7

These are confirmed-broken functions in T5 mod scripts and their correct replacements:

| Broken in T5 mods | Correct T5 replacement |
|---|---|
| `getPlayers()` | `level.players` (engine array, always available) |
| `spawnStruct()` | Associative array: `s = []; s["key"] = val;` |
| `player isAlive()` (method) | `player.health > 0` |
| `isAlive(player)` (standalone) | `player.health > 0` |
| `player.team` | `player.pers["team"]` â†’ returns `"allies"`, `"axis"`, or `"spectator"` |
| `setDvar("scr_player_healthregentime", "0")` | `setDvar("scr_player_healthregentime", "0")` DOES work â€” set it before `_healthoverlay::init()` threads so the engine reads 0 and disables regen itself |
| `level.onGiveLoadout = ::fn` | Does not exist in T5. Use `level.playerSpawnedCB = ::gf_playerSpawnedCB` instead; fire `level notify("spawned_player")` inside it to keep SD happy, then `self thread gf_onSpawned()` â€” thread runs after `giveLoadout` with no yield gap |

**Compile error diagnosis:** When T5 throws `unknown function: @ scripts/mp/<file>::<func>`, the broken call is INSIDE the named function â€” scan every call within it for T5 compatibility.

**Cross-file calls require `#include`:** Each `.gsc` file must `#include` every other mod script whose functions it calls **directly**. T5 does **not** support transitive includes â€” if A includes B which includes C, A cannot call functions from C. Each file must have its own explicit `#include` for every file it calls into. Missing include â†’ `unknown function` compile error on the calling function. Current include chain: `mp_gunfight.gsc` â†’ `_gf_rounds.gsc` â†’ `_gf_loadouts.gsc` â†’ `_gf_hud.gsc`. `_gf_tests.gsc` includes both `_gf_rounds` and `_gf_loadouts` directly since it calls functions from both.

---

## T5 Engine Reference

### SD callbacks registered in `sd.gsc::main()`
| Level var | Fires when |
|---|---|
| `level.playerSpawnedCB` | Player spawns â†’ fires `level notify("spawned_player")` |
| `level.onPlayerKilled` | Player dies |
| `level.onDeadEvent(team)` | A team is fully eliminated |
| `level.onOneLeftEvent(team)` | Last player alive on a team |
| `level.onTimeLimit` | Round timer expires â†’ defenders win |
| `level.onRoundSwitch` | Halftime / side swap |
| `level.onRoundEndGame` | Returns overall round winner string |

### SD state vars
- `game["attackers"]` / `game["defenders"]` â€” team role assignment
- `level.aliveCount[team]` â€” engine-maintained alive count per team
- `game["roundswon"]["allies"]` / `game["roundswon"]["axis"]` â€” round wins
- `game["roundsplayed"]` â€” rounds played so far

### Overridable callbacks (set in `_globallogic.gsc::SetupCallbacks()`)
```
level.onSpawnPlayer          // fires after player spawns into world
level.playerSpawnedCB        // fires after spawn (SD sets this to notify "spawned_player")
level.onPlayerKilled         // fires on kill
level.onDeadEvent(team)      // fires when a whole team is eliminated
level.onOneLeftEvent(team)   // fires when last player on team is alive
level.onTimeLimit            // fires when round clock hits 0
level.onRoundSwitch          // fires at halftime / side swap
level.onRoundEndGame         // should return winner string "allies"/"axis"/"tie"
level.onGiveLoadout          // fires at end of giveLoadout â€” override to swap weapons
level.spawnClient            // queues/delays client spawn; default: _globallogic_spawn::spawnClient
level.spawnPlayer            // puts player into world; default: _globallogic_spawn::spawnPlayer
level._setTeamScore          // set team score directly (default updates game["teamScores"])
level._getTeamScore          // read team score (default returns game["teamScores"][team])
```

### Spawn pipeline (what happens inside `spawnPlayer()`)
Order of operations every time a player spawns:
1. `setSpawnVariables()` â€” sets player origin, angles, team, sessionstate = "playing"
2. `[[level.onSpawnPlayer]]()` â€” SD's callback; sets `isBombCarrier = false`, selects spawnpoint, calls `self spawn(...)`
3. `[[level.playerSpawnedCB]]()` â€” SD fires `level notify("spawned_player")` here â† our waittill
4. `maps\mp\gametypes\_class::setClass(self.class)` â€” sets perk state
5. `maps\mp\gametypes\_class::giveLoadout(team, class)` â€” gives default class weapons
6. **Our `gf_roundLoop` thread wakes** from `waittill("spawned_player")` and overwrites weapons with gunfight loadout

Step 6 is correct â€” our `takeAllWeapons` + custom weapons run *after* the engine's `giveLoadout`, replacing whatever it gave.

### Key game state vars
```gsc
game["state"]                 // "playing" | "postgame"
game["attackers"]             // team string of attacking team in SD
game["defenders"]             // team string of defending team
game["roundswon"]["allies"]   // rounds won by allies
game["roundswon"]["axis"]     // rounds won by axis
game["roundsplayed"]          // total rounds completed
level.gameEnded               // bool â€” set true when endGame() is called
level.inGracePeriod           // bool â€” grace period blocks deaths/forfeits
level.inOvertime              // bool â€” setting true blocks new spawns automatically
level.aliveCount["allies"]    // engine-maintained alive player count (updated by updateTeamStatus)
level.aliveCount["axis"]
level.alivePlayers["allies"]  // array of alive player entities
level.alivePlayers["axis"]
level.playerCount["allies"]   // total connected players per team (alive + dead)
```

### Ending a round / game
```gsc
// SD's wrapper â€” increments winning team score by 1, then ends round/game:
sd_endGame( winningTeam, endReasonText )

// Core engine function â€” use for our own endgame calls if not going through SD:
maps\mp\gametypes\_globallogic::endGame( winningTeam, endReasonText )

// Direct team score manipulation:
[[level._setTeamScore]]( "allies", newScore )
[[level._getTeamScore]]( "allies" )
```

### SD round cycling â€” confirmed working pattern

**`maps\mp\gametypes\sd::sd_endGame( winner, "" )`** â€” confirmed callable from mod scripts in Plutonium T5.

Calling this from `onDeadEvent` or a custom timer handler:
- Increments `game["roundswon"][winner]` by 1 and updates the scoreboard
- Checks `hitRoundWinLimit()` â€” ends the match if reached, otherwise cycles the round
- SD handles intermission display, player respawn, and the next prematch automatically
- No manual `pers["lives"]` reset needed â€” SD handles it
- No manual `[[level.spawnClient]]()` calls needed **between rounds** â€” SD handles respawning. But `gf_bypassClassChoice` must call it for the initial connect spawn (see class select suppression section).

The 0.2s wait is a brief spawn-protection window (PvP blocked via `!gf_roundActive` in damage handler). `gf_timerEnd` is set before the wait so the HUD countdown shows immediately on spawn. `gf_roundEnding` must be explicitly cleared here â€” SD never resets it.

### Timer control
```gsc
maps\mp\gametypes\_globallogic_utils::pauseTimer()   // stops round clock
maps\mp\gametypes\_globallogic_utils::resumeTimer()  // resumes round clock
// Useful for overtime: pause clock, wait for zone capture, then end round
```

### Score events
```gsc
maps\mp\gametypes\_globallogic_score::givePlayerScore( "kill", player )
// Recognized events: "kill", "headshot", "assist", "assist_25/50/75",
//                    "plant", "defuse", "win", "loss", "tie"
```

### Useful T5 utility functions (maps\mp\_utility)
```gsc
getOtherTeam( team )               // "allies"<->"axis"
getRoundsWon( team )               // game["roundswon"][team]
getRoundsPlayed()                  // game["roundsplayed"]
hitRoundWinLimit()                 // true if any team hit level.roundWinLimit
playSoundOnPlayers( sound, team )  // plays local sound to all players on team
dvarIntValue( name, def, min, max )  // reads scr_sd_<name>, sets default if unset
```

### Engine callbacks â€” full list
Registered by `_callbacksetup.gsc`. These engine events call into GSC:
```
CodeCallback_StartGameType()     game init â€” calls sd.gsc::main()
CodeCallback_PlayerConnect()     player joins server
CodeCallback_PlayerDisconnect()  player leaves
CodeCallback_PlayerDamage()      damage event (before health change)
CodeCallback_PlayerKilled()      death event
CodeCallback_ActorDamage()       NPC damage
CodeCallback_ActorKilled()       NPC death
CodeCallback_VehicleDamage()     vehicle hit
CodeCallback_HostMigration()     host migration
CodeCallback_GlassSmash()        glass break FX
```

### Critical gotchas
- **`updateTeamStatus()` runs async** (waittillframeend) â€” `level.aliveCount` may be one frame stale after a kill
- **`level.inGracePeriod = true` blocks forfeit/dead-event checks** â€” clear it before main gameplay starts
- **`level.inOvertime = true` prevents all new spawns** â€” useful for overtime zone capture
- **`map_restart(true)`** keeps player positions but resets entities AND `level.*` vars; `false` = full restart. `self.pers[]` and `game[]` are the only things that survive. Do not rely on `level.*` state across a `map_restart`.
- **`self.pers[]` persists across rounds** â€” player stats, team, class survive `map_restart`
- **`scr_disable_cac = 1`** makes `beginClassChoice` auto-assign `level.defaultClass = "CLASS_ASSAULT"` and auto-spawn
- **SD's `onDeadEvent`** checks `level.bombPlanted` before deciding winner â€” our override must handle this or replicate the logic

---

## T5 HUD System

All HUD elements created with `newClientHudElem(player)`.

**Coordinate system:**
- `horzAlign="left"`, `vertAlign="top"` â†’ x/y are pixel offsets from screen top-left corner
- `horzAlign="left"`, `vertAlign="middle"` â†’ y is vertical center of element (element straddles y)
- `alignX` / `alignY` control which edge/center of the element the x/y coordinate refers to

**Colored rectangles (health bars, backgrounds):**
```gsc
e = newClientHudElem(player);
e.horzAlign = "left";
e.vertAlign = "top";
e.alignX    = "left";
e.alignY    = "middle";
e.x         = 10;
e.y         = 145;   // vertical center of the rect
e.color     = (0.3, 0.55, 1);
e.alpha     = 0.9;
e.sort      = 2;     // draw order (higher = on top)
e setShader("white", 68, 5);  // width=68px, height=5px
```

**To resize a bar:** `e setShader("white", newWidth, height)` â€” call each update tick.
Use `"progress_bar_fill"` / `"progress_bar_bg"` instead of `"white"` for native-styled bars.

**Text elements:** set `e.font = "smallfixed"` and `e.fontScale = 1.0`, then `e setText("string")`.

**Timer:** `e setTimerUp(0)` starts counting up from 0. Engine-driven, no script polling needed.

**Persistent HUD pattern:** Create elements once after first `spawned_player`, update every 0.2s in a loop, never destroy/rebuild mid-session. Destroy on `disconnect`.

### Better HUD creation functions (_hud_util.gsc)
These are cleaner than raw `newClientHudElem` + `setShader`:
```gsc
createFontString( font, fontScale )              // text element
createIcon( shader, width, height )              // icon element
createBar( color, width, height )                // colored bar (wraps setShader)
createPrimaryProgressBar()                       // game-styled primary progress bar
createSecondaryProgressBar()                     // game-styled secondary progress bar
createServerFontString( font, fontScale, team )  // server-side (all players see same)
createServerIcon( shader, width, height, team )
createServerBar( color, width, height, flashFrac, team )
```
Font strings: `"default"`, `"bigfixed"`, `"smallfixed"`, `"objective"`, `"extrabig"`

### HUD transition helpers (from IW5/T5 `_hud_util.gsc`)
These are wrapper methods on HUD elements â€” call on an element created with `createIcon` / `createFontString`:
```gsc
e transitionSlideIn( duration, direction );   // direction: "left", "right", "up", "down"
e transitionSlideOut( duration, direction );
e hideElem();        // sets alpha=0, non-interactive
e showElem();        // restores alpha
e updateBar( fraction );     // resizes bar to fraction [0.0 - 1.0] of its max width
e setFlashFrac( fraction );  // sets flash threshold on a progress bar (flashes below fraction)
```
These assume elements were created with `createBar`/`createIcon` which store `.baseWidth` etc. as properties on the element. Raw `newClientHudElem` elements won't have those properties; use `createBar` / `createIcon` instead.

### HUD element types
```gsc
hud = newHudElem( player );          // server-side, general purpose
hud = newClientHudElem( player );    // client-side only
hud = NewScoreHudElem( player );     // score-specific HUD element
```
`hud.archived = false` â€” prevents HUD from being hidden during menus or demo playback.

### HUD animations
```gsc
hud fadeOverTime( 0.3 );       // fade alpha over time
hud moveOverTime( 0.2 );       // smooth position transition (set .x/.y after)
hud.alpha = 0;                 // set target alpha after fadeOverTime
hud.x = 100; hud.y = 50;      // set target pos after moveOverTime

// Font glow
hud.glowAlpha = 1;
hud.glowColor = ( r/255, g/255, b/255 );

// Pulse (score pop)
hud fontPulse( player );       // brief scale-up pop effect
```

### Standard properties for live-round HUD elements
```gsc
e.archived       = false;   // don't hide during menus / demo playback
e.hidewheninmenu = true;    // hide during pause menu
e.glowColor      = ( 1, 0.3, 0 );
e.glowAlpha      = 0.5;
```

---

## T5 Asset Reference

### Weapons

**giveWeapon arguments**
`GiveWeapon( weaponName )` â€” basic form.
`GiveWeapon( weaponName, dualWield )` â€” `dualWield` is a **boolean**, NOT a camo number.
- `true` gives the akimbo/dualwield variant
- `false` (or omit) gives the single variant
- **T6 uses a 3rd camo-number arg; T5 does not** â€” passing a number here may crash or be silently ignored

To give a weapon with an embedded attachment, use the `_attachment_` naming pattern:
```gsc
self GiveWeapon( "famas_reflex_mp" );   // attachment baked into weapon name
self GiveWeapon( "python_speed_mp" );   // _speed_ is speed-draw holster variant
```
Common attachments: `acog_mp`, `reflex_mp`, `silencer_mp`, `dualwield_mp`, `grip_mp`, `masterkey_mp`, `flamethrower_mp`

### Perks

Pass these strings to `self SetPerk(name)` / check with `self hasPerk(name)`.

```
specialty_bulletaccuracy     Steady Aim
specialty_movefaster         Lightweight
specialty_holdbreath         Scout
specialty_fastreload         Sleight of Hand
specialty_gpsjammer          Ghost
specialty_detectexplosive    Hacker
specialty_bulletpenetration  Deep Impact
specialty_quieter            Ninja
specialty_pistoldeath        Second Chance
specialty_gas_mask           Tactical Mask
specialty_twoattach          Warlord / Professional
specialty_extraammo          Extra Ammo
specialty_killstreak         Hardline
specialty_longersprint       Marathon
specialty_scavenger          Scavenger
specialty_armorvest          Flak Jacket
specialty_blindeye           Cold Blooded
specialty_sprintrecovery     Extreme Conditioning
```

Additional perks confirmed from T5 source (weapons.txt):
```
specialty_twogrenades        Two grenades (extra grenade slot)
specialty_twoprimaries       Two primary weapons (warlord tier)
specialty_rof                Increased rate of fire
specialty_stunprotection     Reduced stun effect duration
specialty_nomotionsensor     Not visible on motion sensor
specialty_loudenemies        Hear enemies more clearly
specialty_showenemyequipment Show enemy equipment on minimap
specialty_showonradar        Show player on enemy radar (negative perk use)
specialty_shellshock         Shellshock effect on nearby explosions
specialty_nottargetedbyai    Not targeted by AI turrets/dogs
specialty_noname             Unnamed perk slot (test before using)
```

### HUD Shaders

**Weapon & lethal icon shaders** â€” confirmed from Xinerki `t5-gunfight/duel.gsc` (T5 gametype mod).

Default rule: `"menu_mp_weapons_" + baseName` where baseName has no `_mp` and no variant suffix.

Special cases (base name doesn't match shader):
```
Weapon base name          Shader
ithaca_grip             -> menu_mp_weapons_ithaca
stoner63                -> menu_mp_weapons_stoner63a
crossbow_explosive      -> menu_mp_weapons_crossbow
minigun_wager           -> menu_mp_weapons_minigun
python_speed            -> menu_mp_weapons_python
m1911_upgradesight      -> menu_mp_weapons_colt
makarov_upgradesight    -> menu_mp_weapons_makarov
cz75_upgradesight       -> menu_mp_weapons_cz75
Default secondary: "menu_mp_weapons_" + base (strip suffix like _speed, _upgradesight)
```

Lethal icon shaders:
```
frag_grenade            -> hud_grenadeicon
satchel_charge_mp       -> hud_icon_satchelcharge   (confirmed from weapon def file hudIcon field; NOT in loose IWDs â€” compiled into .ff zone; hud_sticky_grenade / hud_satchelcharge both wrong)
sticky_grenade          -> hud_icon_sticky_grenade
hatchet                 -> hud_hatchet
Default: "hud_" + baseName
```

Tactical grenade icon shaders â€” confirmed from IWD `images/*.iwi` listing:
```
flash_grenade_mp       -> hud_us_flashgrenade
concussion_grenade_mp  -> hud_us_stungrenade
smoke_grenade_mp       -> hud_us_smokegrenade
```
Pattern: `hud_us_` prefix (NOT `hud_` directly).

Precaching before use:
```gsc
PreCacheShader( "menu_mp_weapons_famas" );   // call at match start before HUD creation
e setShader( "menu_mp_weapons_famas", 64, 32 );
```

**Named shaders (precached by T5 â€” usable in setShader / createIcon)**
```
Progress bars:    progress_bar_bg, progress_bar_fill, progress_bar_fg
Score bars:       score_bar_bg, score_bar_allies, score_bar_opfor
Waypoints:        waypoint_bomb, waypoint_kill, waypoint_capture, waypoint_defend
                  waypoint_defuse, waypoint_target, waypoint_second_chance
Compass:          compass_waypoint_bomb, compass_waypoint_capture, compass_waypoint_defend
HUD:              hud_suitcase_bomb, hud_momentum, hud_scavenger_pickup
Factions:         faction_128_marines, faction_128_nva, faction_128_spetsnaz
Emblems:          composite_emblem_team_allies, composite_emblem_team_axis
Generic:          white, black
```

`score_bar_allies` / `score_bar_opfor` are particularly useful â€” native styled team HP/score bars the game uses internally.

### Audio

**Sound playback**
```gsc
self playLocalSound( alias )                           // plays to this player only
maps\mp\_utility::playSoundOnPlayers( alias, team )   // plays to whole team (or all if team undefined)
play_sound_in_space( alias, origin )                   // positional 3D sound
```

**leaderDialog (voice callouts)**
```gsc
maps\mp\gametypes\_globallogic_audio::leaderDialog( dialogKey )
maps\mp\gametypes\_globallogic_audio::leaderDialog( dialogKey, team )
```
Available dialog keys (set via `game["dialog"][key]`):
```
"gametype"       mode intro VO
"last_one"       last player alive warning
"halftime"       halftime VO
"round_success"  encourage_win
"round_failure"  encourage_lost
"winning"        winning
"losing"         losing
"timesup"        timesup
"challenge"      challengecomplete
```

**Music states**
```gsc
maps\mp\gametypes\_globallogic_audio::set_music_on_team( state, team )
```
```
"MP_LAST_STAND"          last-alive suspense
"TIME_OUT"               bomb countdown
"CTF_WE_TAKE"            friendly picks up object
"CTF_THEY_TAKE"          enemy picks up object
"SILENT"                 mute music
```

**Dynamic music**
```gsc
actionMusicSet( "state_name" );   // triggers music state (e.g. "round_end_win", "combat")
```

### Classes & Menus

**Class name constants**
```
CLASS_ASSAULT    CLASS_SMG       CLASS_CQB
CLASS_LMG        CLASS_SNIPER
OFFLINE_CLASS1 ... OFFLINE_CLASS10    (offline preset classes)
CLASS_CUSTOM1  ... CLASS_CUSTOM5      (online custom classes)
CLASS_CUSTOM6  ... CLASS_CUSTOM10     (prestige custom slots)
```
`level.defaultClass = "CLASS_ASSAULT"` (set in _class.gsc init)

**Menu name constants (game["menu_*"])**
```
game["menu_team"]                  = "team_marinesopfor"
game["menu_class_allies"]          = "class_marines"
game["menu_class_axis"]            = "class_opfor"
game["menu_changeclass_allies"]    = "changeclass"
game["menu_changeclass_axis"]      = "changeclass"
game["menu_changeclass_custom"]    = "changeclass_custom"
game["menu_changeclass_barebones"] = "changeclass_barebones"
```

### DVARs

Useful dvars for Gunfight (from dvarlist.txt):
```
compass         "0" / "1"       show/hide the minimap compass
compassSize     integer         minimap size in pixels (0 = hidden)
cg_drawHealth   "0" / "1"       show/hide default health bar HUD element
cg_fov          float           field of view (default 65)
bg_gravity      float           gravity (default 800)
set scr_game_prematchperiod	15
```
Set via `setDvar( name, value )` in `init()`. `compass "0"` resolves the minimap-disable TODO.
reset bg_ladder_yawcap
reset bg_maxGrenadeIndicatorSpeed
reset bg_prone_yawcap
reset mantle_check_range
reset jump_spreadAdd
reset player_adsExitDelay
reset player_runbkThreshhold
reset player_sprintCameraBob
reset player_sprintStrafeSpeedScale 
reset player_sprintThreshhold
reset bg_fallDamageMaxHeight
reset bg_fallDamageMinHeight
reset bg_viewBobMax
reset com_timescale
reset friction
reset g_synchronousClients
reset jump_height
reset jump_ladderPushVel
reset jump_slowdownEnable
reset mantle_check_radius
reset mantle_check_angle
reset mantle_enable
reset player_backSpeedScale
reset player_breath_fire_delay
reset player_breath_gasp_lerp
reset player_breath_gasp_scale
reset player_breath_gasp_time
reset player_breath_hold_lerp
reset player_breath_hold_time
reset player_dmgtimer_minScale
reset player_footstepsThreshhold
reset player_scopeExitOnDamage
reset player_sprintForwardMinimum
reset player_sprintMinTime
reset player_sprintRechargePause
reset player_sprintSpeedScale
reset player_sprintTime
reset player_sprintUnlimited
reset player_strafeSpeedScale
reset player_view_pitch_down
reset player_view_pitch_up
reset sv_clientSideBullets
reset timescale
set scr_disable_cac 0
set scr_disable_weapondrop 0
set actionslotshide 0
set ammoCounterHide 0
set player_sprintUnlimited 0
if ( dvarInt( ui_multiplayer ) == 1 ) exec "reset_bindings.cfg"
set ui_selectlobby 0

// oldschool dvars set in script
reset ragdoll_explode_force
reset ragdoll_explode_upbias

reset jump_height
reset jump_slowdownEnable
reset bg_fallDamageMinHeight
reset bg_fallDamageMaxHeight
// end oldschool dvars set in script

// wager-zone blockers are preserved via _gameobjects allow-list, not wager dvars
---

## T5 Spawn System

### Getting spawn points
```gsc
maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_attacker" )
maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_defender" )
maps\mp\gametypes\_spawnlogic::getSpawnpoint_Random( spawnPoints )
maps\mp\gametypes\_spawnlogic::getRandomIntermissionPoint()
```
SD uses `mp_sd_spawn_attacker` (allies) and `mp_sd_spawn_defender` (axis) classnames.

### Spawn influencer types (for custom spawn bias)
```gsc
// Push enemies away from a position (e.g. stop spawning behind a zone):
maps\mp\gametypes\_spawning::addSpawnInfluencer( origin, radius, weight, influencerType, teamMask )
```
Influencer types: `eINFLUENCER_TYPE_NORMAL`(0), `eINFLUENCER_TYPE_PLAYER`(1), `eINFLUENCER_TYPE_GAME_MODE`(6)
Team masks: `iSPAWN_TEAMMASK_ALLIES`(4), `iSPAWN_TEAMMASK_AXIS`(2)

Spawn point weighting (from community mods):
```gsc
addSphereInfluencer( origin, radius, weight );
// weight > 0 attracts spawns; weight < 0 repels
```

---

## T5 Game Objects â€” Overtime Zone

For implementing an overtime capture zone (`_gameobjects.gsc`):
```gsc
// Create a zone players must stand in (like a koth hill or overtime zone):
zone = maps\mp\gametypes\_gameobjects::createUseObject( ownerTeam, trigger, visuals, offset );
zone maps\mp\gametypes\_gameobjects::allowUse( "enemy" );    // "friendly", "enemy", "any", "none"
zone maps\mp\gametypes\_gameobjects::setUseTime( seconds );  // how long to capture
zone maps\mp\gametypes\_gameobjects::setUseText( &"string" );
zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "any" );
zone maps\mp\gametypes\_gameobjects::set2DIcon( "any", "compass_waypoint_capture" );
zone maps\mp\gametypes\_gameobjects::set3DIcon( "any", "waypoint_capture" );
zone.onBeginUse = ::myOnBeginUse;   // player starts capturing
zone.onEndUse   = ::myOnEndUse;     // player stops / finishes
zone.onUse      = ::myOnCapture;    // capture complete

// Get which team owns the zone:
winningTeam = zone maps\mp\gametypes\_gameobjects::getOwnerTeam();
```

---

## T5 Loadout Delivery

```gsc
// Full custom loadout override (call after spawned_player):
self takeAllWeapons();
self GiveWeapon( "famas_mp" );
self GiveWeapon( "python_speed_mp" );
self GiveWeapon( "knife_mp" );
self switchToWeapon( "famas_mp" );
self giveMaxAmmo( "famas_mp" );
self giveMaxAmmo( "python_speed_mp" );
self GiveWeapon( "frag_grenade_mp" );      // lethal grenade â€” use GiveWeapon, NOT GiveOffhandWeapon
self GiveWeapon( "flash_grenade_mp" );     // tactical grenade â€” same

// Perks:
self SetPerk( "specialty_fastreload" );
self SetPerk( "specialty_gpsjammer" );

// Remove a perk:
self UnSetPerk( "specialty_killstreak" );

// Equipment slot (claymore, camera spike etc â€” NOT grenades):
self GiveWeapon( equipment_weapon );
self SetActionSlot( 1, "weapon", equipment_weapon );
```
Use `GiveWeapon()` for ALL weapon types including grenades and equipment.
`SetActionSlot(1, "weapon", ...)` is only needed for equipment (claymores etc.) so they appear in the correct UI slot â€” grenades do not need it.

### Weapon camos â€” `CalcWeaponOptions` + `GiveWeapon` 3rd arg

Camo is applied via the 3rd parameter of `GiveWeapon`, which is a packed integer produced by the native `CalcWeaponOptions`:
```gsc
camoOpts = int( self CalcWeaponOptions( camoIndex, lensIndex, reticleIndex, reticleColorIndex ) );
self GiveWeapon( weapon, 0, camoOpts );
// Minimal form â€” camo only, stock lens/reticle:
camoOpts = int( self CalcWeaponOptions( 7, 0, 0, 0 ) );   // Jungle ERDL
self GiveWeapon( "galil_extclip_mp", 0, camoOpts );
```

**Camo indices** (from `mp/weaponOptions.csv`):
```
0   Default (weapon-specific gunmetal / wood / plastic)
1   Dusty          2   Ice            3   Red
4   OD Green       5   Desert Nevada  6   Desert Sahara
7   Jungle ERDL    8   Jungle Tiger   9   Urban German
10  Urban Warsaw   11  Winter Siberia 12  Winter Yukon
13  Woodland       14  Woodland Flora 15  Gold
```

**Lens indices** (0â€“5): white, red, blue, green, orange, yellow. Pass `0` for stock.
**Reticle indices** (0â€“39): various dot/cross/shape patterns. Pass `0` for stock red-dot.
**Reticle color indices** (0â€“6): red, green, blue, purple, cyan, yellow, orange.

**Weapons where pattern camos (5â€“14) won't show** â€” they use `weapon_camo_neutral` as their base and are unaffected by patterns. Solid colors (1â€“4) and Gold (15) behavior may vary:
`python`, `knife`, `m1911`, `cz75`, `makarov`, `asp`, `crossbow_explosive`, `rpg`, `strela`, `m72_law`, `china_lake`

**Why `custom_class["camo_num"]` does NOT work for this mod:**
`camo_num` is only read in `_weapons.gsc::stow_on_back()` â€” it affects only the weapon model rendered on the player's *back* (not in-hand). It also requires `isSubStr(self.curclass, "CUSTOM")`, which is false for `CLASS_ASSAULT` (our class when `scr_disable_cac=1`). Dead end.

**Current mod implementation** (`_gf_loadouts.gsc`):
- Each loadout gets `load["camo"] = randomInt(16)` at pool-build time (match start)
- `gf_giveCustomLoadout` calls `CalcWeaponOptions(load["camo"], 0, 0, 0)` and passes the result to both primary and secondary `GiveWeapon` calls
- When adding curated loadouts later, pass camo as a 5th arg to `gf_buildLoadout` and assign it directly instead of using `randomInt(16)`

---

## T5 Player Utilities

### Controls & movement
```gsc
self freezeControls( 1 );        // lock movement + shooting (still allows looking)
self freezeControls( 0 );        // re-enable controls
// NOTE: confirmed in IW5 source; T5 should be identical â€” verify in-game

self DisableWeaponCycling()      // lock player to current weapon, no scrolling
self EnableWeaponCycling()       // re-enable
self setSpawnWeapon( "famas_mp" ) // sets weapon held on spawn
```

### Team messaging & menus
```gsc
printBoldOnTeam( text, team );   // send bold center-screen message to entire team
                                  // team = "allies" | "axis" | undefined (all)

self closePopupMenu();           // close any open popup
self closeIngameMenu();          // close in-game menu (pause/settings overlay)
closemenus();                    // calls both
```

### Array utilities
```gsc
quickSort( array );              // in-place sort, returns sorted array
// Usage: sorted = quickSort( myArray );
```

### Button detection (self = player, call in loop with wait 0.05)
```gsc
self AttackButtonPressed()
self UseButtonPressed()
self MeleeButtonPressed()
self AdsButtonPressed()
self JumpButtonPressed()
self FragButtonPressed()
self SecondaryOffHandButtonPressed()
self ActionSlotOneButtonPressed()    // through ActionSlotFourButtonPressed()
```

### String utilities (confirmed working in T5)
```gsc
strTok( string, delimiter )        // splits string -> array
getSubStr( string, start, end )    // substring; end = string.size to go to end
```

### Weapon attachment name pattern (from shrp.gsc line 267)
```gsc
// Strip _mp suffix, append _att_mp
base = getSubStr( weaponName, 0, weaponName.size - 3 );   // removes "_mp"
result = base + "_" + attachmentName + "_mp";
// e.g. "famas_mp" + "reflex" -> "famas_reflex_mp"
```

### Objective markers
Simpler than createUseObject â€” just places a waypoint:
```gsc
objId = 150;    // arbitrary ID 0-255
objective_add( objId, "active", origin );
objective_icon( objId, "waypoint_defend" );    // waypoint_capture, waypoint_target, etc.
objective_state( objId, "active" );            // "active", "invisible", "done", "failed"
objective_setvisibletoplayer( objId, player ); // call per player to show
objective_delete( objId );                      // cleanup
```

3D always-on world waypoint via HUD element:
```gsc
wp = newClientHudElem( player );
wp.x = origin[0];
wp.y = origin[1];
wp.z = origin[2] + 40;
wp setShader( "waypoint_defend", 12, 12 );
wp setwaypoint( true, true );   // arg1: always show off-screen; arg2: onscreen indicator
wp.color = ( 1, 1, 0 );
wp.hidewheninmenu = true;
```

### Visual effects
```gsc
fxid = loadfx( "fx/path/to/effect" );
spawnFx( fxid, origin );
triggerFx( fxid );
```

### Function pointer arrays (dynamic dispatch / menu systems)
```gsc
menu.functions = [];
menu.functions[0] = ::myFunc;
menu.functions[1] = ::otherFunc;
// Call: self [[ menu.functions[selected] ]]();
```

### notify/waittill as state machine
Use `level notify("state_name")` + `level waittill("state_name")` to drive state transitions instead of polling flags. Cleaner than busy-wait loops for events like round start/end.

### Scoreboard column names (valid values for setscoreboardcolumns)
```
kills  deaths  assists  captures  defends  returns  plants  defuses
stabs  humiliated  tomahawks  kdratio  x2score  survived  headshots  none
```

### givePlayerScore â€” event types
```gsc
givePlayerScore( "kill",        player );
givePlayerScore( "headshot",    player );
givePlayerScore( "assist",      player );
givePlayerScore( "capture",     player );
givePlayerScore( "defend",      player );
givePlayerScore( "plant",       player );
givePlayerScore( "defuse",      player );
givePlayerScore( "assault",     player );
givePlayerScore( "melee_kill",  player );
givePlayerScore( "hatchet_kill",player );
givePlayerScore( "other_kill",  player );
```

---

### Team health score display (GunMd0wn pattern)
```gsc
maps\mp\gametypes\_gamescore::_setteamscore("allies", getTeamHealth("allies"));
```

### game[] persistence for loadouts
`game[]` persists across rounds (SD round cycling doesn't reset it). Use it to pre-generate all loadouts at match start:
```gsc
if ( !isDefined( game["gf_init"] ) )
{
    game["gf_pool"]  = [];
    game["gf_loads"] = [];
    for ( i = 0; i < 6; i++ )
        game["gf_loads"][i] = gf_buildLoadout();
    game["gf_idx"]  = 0;
    game["gf_init"] = 1;
}
level.gf_currentLoad = game["gf_loads"][ game["gf_idx"] ];
// Advance: game["gf_idx"] = int( game["gf_rounds_done"] / 2 ); in onDeadEvent
```

### Loadout as associative array (confirmed T5)
```gsc
load = [];
load["primary"]   = "famas_reflex_mp";
load["secondary"] = "python_speed_mp";
load["lethal"]    = "frag_grenade_mp";
load["tactical"]  = "flash_grenade_mp";
```

### Singleton HUD kill pattern
Prevents stale HUD instances when recreating after round cycling:
```gsc
level notify( "kill_healthhud" );
level endon( "kill_healthhud" );
// ... create HUD elements below ...
```

### Overtime countdown â€” manual decrement, pauses while zone contested
```gsc
gf_overtimeCountdown()
{
    level endon( "game_ended" );
    timeLeft = 20.0;
    while ( timeLeft > 0 )
    {
        if ( !level.gf_overtimeCaptureActive )
            timeLeft -= 0.1;
        wait 0.1;
    }
    level notify( "gf_overtime_expired" );
}
```

### Delayed grenade delivery (prevents spawn-instant-throw)
```gsc
gf_giveDelayedGrenade( lethal )
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );
    wait 3;
    if ( self.health > 0 )
    {
        self GiveWeapon( lethal );   // T5: GiveWeapon for grenades, not GiveOffhandWeapon
        self setWeaponAmmoClip( lethal, 1 );   // one grenade only
    }
}
```

### hideHardpointModels â€” canonical pattern (confirmed misterbubb T6 matches our T5 impl)
```gsc
hardpoints = getentarray( "hq_hardpoint", "targetname" );
for ( i = 0; i < hardpoints.size; i++ )
{
    hp = hardpoints[i];
    hp.original_origin = hp.origin;
    if ( isDefined( hp.target ) )
    {
        visuals = getentarray( hp.target, "targetname" );
        for ( j = 0; j < visuals.size; j++ )
            if ( isDefined( visuals[j] ) )
            {
                visuals[j].origin = visuals[j].origin + ( 0, 0, -10000 );
                visuals[j] hide();
            }
    }
    if ( isDefined( hp.model ) ) hp hide();
}
```
`hp.original_origin` is read in `gf_overtime()` to place the capture zone at the correct world position.

### Admin / permission pattern
```gsc
if ( player.guid == getDvar( "sv_adminGUID" ) ) { ... }
// Or maintain a level.admins[] array populated at connect time
```

### T5 player methods confirmed (Xinerki duel.gsc â€” T5 gametype)
```gsc
maps\mp\gametypes\_wager::setupBlankRandomPlayer( takeAll, chooseBody )
// clears player and optionally assigns a random body model; call before giveWeapon
```

---

