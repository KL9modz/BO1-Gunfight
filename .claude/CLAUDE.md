# mp_gunfight — Plutonium T5 (Black Ops 1 MP) Gunfight Mod

## T5 Gunfight — Possible Features

Use this as a starting point for a new version. Items marked `[ ]` are built and in the current codebase — needs in-game testing. Unmarked items are not yet implemented.

### Built — ready for in-game testing

**Core Rules**
- [ ] One life per round, no respawns — SD `scr_sd_numlives = 1`
- [ ] No killstreaks, no health regen, no weapon drops — `level.killstreaksenabled = 0`, `level.healthRegenDisabled = true`
- [ ] No `map_restart` between rounds; all state lives in `level`/`game` vars
- [x] 6-round win limit — confirmed working. Requires THREE dvars (all three must be set):
  - `scr_sd_roundwinlimit = "6"` — real win-limit dvar; constructed as `"scr_" + gameType + "_roundwinlimit"` (NOT `scr_sd_winlimit` — that dvar does not exist)
  - `scr_sd_scorelimit = "6"` — must match win limit so SD's score UI has a valid 0–6 scale; setting to 0 breaks the UI (bar/indicator positions calculated as score/scoreLimit)
  - `level.roundWinLimit = 6` — belt-and-suspenders; `hitRoundWinLimit()` reads this level var directly
- [x] Round wins tracked in `game["roundswon"]["allies"/"axis"]`; scoreboard accumulates correctly
- [x] HP comparison on timer expiry — confirmed working: `gf_getTeamHP(team)` sums alive player HP; winner = higher HP team; equal HP = draw (`sd_endgame("tie", "")`)
- [x] Draw rounds don't count toward win limit — `hitRoundWinLimit()` has a second check: `getRoundsWon(team) + game["roundswon"]["tie"] >= limit`, so a tie at 5-x would end the match early. Fix: increment `level.roundWinLimit++` before each `sd_endgame("tie", "")` call. Math holds — a team still needs exactly 6 decisive wins because `realWins + ties >= baseLimit + ties` only triggers when `realWins >= baseLimit`

**Round System**
- [ ] SD-native round cycling — `onDeadEvent` → `sd_endGame(winner, "")` handles scoring, win-limit, intermission, respawn; no manual spawn loop
- [ ] `gf_tryActivateRound()` detects new round from `onPlayerSpawned`; 0.2s dedup grace window; `gf_timerEnd` set before wait so HUD shows immediately on spawn
- [ ] `gf_roundEnding` bug fix — flag cleared inside `gf_tryActivateRound` before opening new round (SD never resets it)
- [ ] SD timer pause/resume — `pauseTimer()` during 3s pre-round countdown, `resumeTimer()` at round start
- [ ] Round state init — `level.gf_roundActive`, `level.gf_roundNum`, `level.gf_timerEnd` initialized in `init()` so never undefined during early connects
- [ ] Bomb suppression loop — 0.5s poll suppresses SD bomb plant/defuse mechanics

**Loadout System**
- [ ] Shared random loadout — all players get same primary/secondary/equipment each round
- [ ] Expanded loadout pool — 22 loadouts across 5 weapon classes (AR×7, SMG×6, LMG×4, Sniper×2, Shotgun×2); shuffle-without-repeat, no back-to-back repeat
- [ ] Perks per loadout class — AR/SMG/LMG/Sniper/Shotgun each have tailored 3-perk sets (local vars at top of `gf_initLoadouts()`; `#define` not supported in T5)
- [ ] Attachment randomizer — `gf_addRandomAttachment(baseWeapon, attList)` picks one random attachment; 2 extra empty slots give ~33% no-attachment chance
- [x] Health regen disabled — `setDvar("scr_player_healthregentime", "0")` is the correct fix. `_healthoverlay::init()` is threaded from `_globallogic::init()` and reads this tweakable dvar to set `level.healthRegenDisabled`; setting the dvar to 0 makes the engine disable regen itself. Setting `level.healthRegenDisabled = true` alone is unreliable because the thread can overwrite it after our `init()` runs
- [ ] All weapon+attachment variants precached at startup via `gf_precacheWeapons()`
- [ ] Attachment strings confirmed: `extclip`, `reflex`, `acog`, `silencer`, `rf`, `vzoom`, `grip`
- [ ] `colt45_mp` does not exist — replaced with `m1911_mp`

**Class & Spawn**
- [x] Class select suppression — `replacefunc` on `beginClassChoice`; `scr_disable_cac=1` as backup (Plutonium ignores the dvar; replacefunc is the real fix)
- [x] Sessionstate fix — `gf_getAliveCount` / `gf_getTeamHP` check `p.sessionstate == "playing"` to exclude loading/spectating players
- [x] Loadout delivery hook — `level.onGiveLoadout` does NOT exist in T5 (confirmed: not in any T5 source file). Correct hook: override `level.playerSpawnedCB = ::gf_playerSpawnedCB`. Fire `level notify("spawned_player")` inside it to preserve SD behavior, then `self thread gf_onSpawned()`. The thread runs after `giveLoadout` completes because `playerSpawnedCB` (line 169 of `_globallogic_spawn.gsc`) and `giveLoadout` (line 189) are in the same synchronous function with no yield between them — any thread queued from `playerSpawnedCB` is scheduled after the whole function finishes
- [x] Draw rounds don't count toward win limit — `hitRoundWinLimit()` adds `game["roundswon"]["tie"]` to both teams; fix: call `sd_endgame("tie","")` then immediately `level thread gf_undoTieMark()`. Two threads (endGame and undoTieMark) race to cancel: whichever order they run in, the net change to the tie counter is zero

**HUD**
- [x] Loadout icon slide-in — `gf_showLoadoutHUD()` confirmed working: 6 rows (3 weapon + 3 perk) slide in from right on spawn, hold 5.5s, slide out. Layout: 28px row spacing, font `"default"` fontScale 1.3, weapon icons 64×32 (primary/secondary) / 32×32 (lethal), perk icons 32×24. Shader names from `level.gf_currentLoad`, precached in `gf_initLoadouts()`. NOTE: `"smallfixed"` font is too small — use `"default"` at 1.3 for readable labels
- [x] HP debug display — `gf_debugHealthHUD()` confirmed working: `self iPrintLn("HP: " + self.health)` every 1s
- [ ] Cold War Gunfight HUD — top-left panel (162×38 px): player icons (9×13), HP bars (68 px), score dots (5×5 px). Updated every 0.1s; persists across rounds. Element refs: `gf_hudBg/Sep`, `gf_hudAlliesIcon[0/1]`, `gf_hudAlliesBarBg/Fg`, `gf_hudAlliesHp`, `gf_hudAllyDot[0..5]`, mirrored for axis
- [ ] Custom round timer — `gf_hudTimer` text element, center-top, MM:SS; driven by `level.gf_timerEnd = gettime() + ms`; `scr_sd_timelimit=0` disables SD's built-in timer
- [ ] Perk display notification — `gf_displayPerks()` in `_gf_hud.gsc`: wager-style icon + name, right side, scale pop-in, 5s fade
- [ ] HUD recreation per spawn — `self notify("gf_hud_restart")` on each spawn; `gf_hud()` ends on that notify, destroys stale elements, creates fresh ones (SD round cycling destroys `newClientHudElem` elements)

**Extra Systems**
- [ ] Overtime — equal HP at timer expiry: reuses `hq_hardpoint` entity as capture zone (hidden at match start via `gf_hideHardpointModels()`); 3s uncontested capture wins; 20s countdown pauses while anyone on zone; HP comparison if time expires; coin flip if still tied; falls back gracefully on maps with no hardpoint
- [ ] Forfeit handling — `gf_forfeitWatch()` polls every 10s post-prematch; two consecutive empty-team checks (20s grace for reconnects) → `endGame()` awards win to other team
- [ ] Death sounds — `level.onPlayerKilled = ::gf_onPlayerKilled` wired; kill-ding sound removed (see TODO — `uin_challenge_repeatable` invalid in T5)
- [ ] Scoreboard columns set to `kills, deaths, none, none`; player score = total damage dealt per round
- [ ] Script split — 4 files under `raw/scripts/mp/`

### TODO — not yet implemented

- Mid-round join grace period (~10s window to allow spawn instead of hard block)
- Prematch control lockout — `self freezeControls(1)` / `self freezeControls(0)` (confirmed in IW5 `_utility.gsc`; T5 should be same method — needs in-game test)
- Minimap disable — `setDvar("compass", "0")` hides the minimap; `setDvar("compassSize", "0")` removes it entirely (from dvarlist.txt); call during `init()` before match starts
- Weapon camos — no direct GSC function exists in T5; engine ties camos to DDL persistent data. Options: (1) check Plutonium modding API/Discord for a native camo setter, (2) test populating `self.custom_class[0]["camo_num"]` before spawn with class set to `CLASS_CUSTOM1`
- Wager match modes (Gun Game, Sharpshooter — reference `gun.gsc` and `shrp.gsc` from plutoniummod/t5-scripts)
- Kill-ding alias — `"uin_challenge_repeatable"` is invalid in T5; causes `DSERR_INVALIDPARAM` DirectSound crash (invalid buffer length). Removed from code. Need a valid alias — try `"mpl_killconfirm_killsound"` or `"mp_level_up"`
- Multi-gametype support — currently SD only; add HQ and TDM support
HQ: hook onCapture/onDeadEvent equivalents, suppress hardpoint objective
TDM: no round cycling built-in, need manual round loop + respawn block
Abstract gametype-specific callbacks behind a shared interface so round logic stays the same

**Needs in-game verification:**
- Round timer: confirm `scr_sd_timelimit=0` hides SD's HUD timer (not "instant expire"), and that `gettime()` returns milliseconds in T5
- Perk icon shaders: `specialty_marathon`, `specialty_hardened`, `specialty_lightweight` etc. — shader names unverified
- Overtime zone: confirm `hq_hardpoint` entities exist on SD maps (BO1 HQ mode shares maps with SD)
- Weapon icon shaders: confirmed from Xinerki T5 duel.gsc (T5 gametype mod) — see asset reference section; perk shaders still unverified

---

## Design Goals

Core features modelled after the community duel mod (`mods\mp_gf`) — use this as the reference bar for what the mode should feel like.

### Core gameplay
- Round-based (last team standing ends the round, then killcam plays)
- 6 rounds to win the match
- One life per round — no respawns
- No killstreaks, no perks shown pre-round, no health regen, no weapon drops

### Random weapon system
- Picks a random primary + secondary + lethal + tactical at round start — same loadout for everyone
- Large primary pool: SMGs, shotguns, ARs, LMGs, snipers, and specials (minigun, crossbow, china lake)
- Secondary pool: Python, M1911, Makarov
- Lethal pool: Frag, Semtex, Tomahawk
- Tactical pool: Flash, Concussion, Smoke
- Perks auto-assigned by weapon class (AR/SMG/LMG/Sniper/Shotgun/Special each have their own 3-perk set)
- Infinite ammo for minigun and china lake specifically
- Primary rotates shuffle-without-repeat; secondary/lethal/tactical are fully random each round

### Loadout HUD (priority visual feature)
- On spawn: weapon icons slide in from the right — primary, secondary, lethal (skipped for specials), then 3 perk icons
- Each row: 32×32 icon + text label (24×24 + smaller text for perks)
- All rows slide in simultaneously via `moveOverTime(0.3)`, hold 5.5s, slide back out
- Implemented in `gf_showLoadoutHUD()` in `_gf_hud.gsc`
- **Needs in-game verification:** `menu_mp_weapons_*` shader names, lethal/tactical icon names

---

## Resources

### T5 Source Code
- **plutoniummod/t5-scripts** — Official Plutonium T5 source dump (MP + ZM gametypes, utility scripts, etc.)
  https://github.com/plutoniummod/t5-scripts
  Key files: `MP/Common/maps/mp/gametypes/shrp.gsc`, `gun.gsc`, `sd.gsc`, `_wager.gsc`, `_globallogic.gsc`, `_class.gsc`, `_hud_util.gsc`, `_rank.gsc`
- **Local T5 source dump** (user's machine): `C:\Users\klaze\OneDrive - sdccd.edu\Desktop\GSC\MP\Common`
- **T9 official Gunfight GSC** (BOCW source reference)
  https://github.com/ate47/bocw-source/blob/main/scripts/mp_common/gametypes/gunfight.gsc

### Community Mods (reference/pattern source)
- **misterbubb/T6-Gunfight-Gamemode** — BO2/T6 Plutonium Gunfight; closest engine to T5, best code reference for overtime + equipment delay
  https://github.com/misterbubb/T6-Gunfight-Gamemode
  https://github.com/misterbubb/T6-Gunfight-Gamemode/blob/main/gunfight_mp/maps/mp/gametypes/sd.gsc
  https://forum.plutonium.pw/topic/43931/release-gunfight-gamemode
- **bblack16/plutonium-waypoints** — IW5/MW3 Gunfight port
  https://github.com/bblack16/plutonium-waypoints
  https://github.com/bblack16/plutonium-waypoints/blob/main/iw5/scripts/gamemode_gunfight.gsc
  https://forum.plutonium.pw/topic/37594/release-custom-game-modes-reinforce-gunfight-and-gun-game
- **iAmThatMichael/gunfight** — BO3/T7 Gunfight recreation; used for game-mode design reference
  https://github.com/iAmThatMichael/gunfight
  https://github.com/iAmThatMichael/gunfight/blob/master/scripts/mp/gametypes/gf.gsc
- **GunMd0wn custom_gunfight.gsc** — community Gunfight mod (runs on HQ/TDM); source of class-select suppression patterns and weapon dvar approach. No GitHub — search Plutonium BO1 forum or megathread.
- **mp_EMv2_Recreation, mp_iMCSx, mp_EnCoReV8** — Community BO1 mods; source of HUD element patterns (`newHudElem`, `newClientHudElem`, `NewScoreHudElem`, `hud.archived`, `fontPulse`)
- **Resxt/Plutonium-T5-Scripts** — Collection of community T5 GSC scripts
  https://github.com/Resxt/Plutonium-T5-Scripts
- **Xinerki/t5-gunfight** — T5 Gunfight/duel gametype mod; source of confirmed weapon icon shader names and T5 player methods
  https://github.com/Xinerki/t5-gunfight

### Weapon & Asset References
- **BO1 MP Weapon list** — verified full dump by primetime43; authoritative for weapon strings and attachment variants
  (local copy shared in project chat; original: https://pastebin.com/ZbKLyVTk)
- **CabConModding BO1 weapons GSC tutorial**
  https://cabconmodding.com/threads/black-ops-1-all-about-weapons-gsc-tutorial.1268/
- **Steam guide — BO1 MP full weapon names**
  https://steamcommunity.com/sharedfiles/filedetails/?id=1425168202
- **TCRF BO1 unused/cut weapons** — Internal asset names
  https://tcrf.net/Call_of_Duty:_Black_Ops_(Windows,_Xbox_360,_PlayStation_3,_Wii)/Unused_%26_Cut_Weapons

### Plutonium Docs & Forums
- **Loading mods into Plutonium**
  https://plutonium.pw/docs/modding/loading-mods/
- **Plutonium new GSC scripting features** (T5/T6 scripting extensions)
  https://www.plutonium.pw/docs/modding/gsc/new-scripting-features/
- **Plutonium BO1 modding releases & resources forum**
  https://forum.plutonium.pw/category/60/bo1-modding-releases-resources
- **BO1 item/weapon give commands thread** (weapon string reference)
  https://forum.plutonium.pw/topic/33166/bo1-item-commands
- **BO1 mods megathread** (organized collection of mods, tutorials, guides)
  https://forum.plutonium.pw/topic/34555/megathread-organized-collection-of-bo1-mods-releases-tutorials-and-guides

### Future Projects (reference)
- **PlutoniumT5 map vote mod** — full mods folder + map vote system
  https://github.com/DoktorSAS/PlutoniumT5Mapvote
- **ProjectDonetsk/T9** — T9 port for Plutonium
  https://github.com/ProjectDonetsk/T9

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

## T5 GSC — Critical API Differences from T6/T7

These are confirmed-broken functions in T5 mod scripts and their correct replacements:

| Broken in T5 mods | Correct T5 replacement |
|---|---|
| `getPlayers()` | `level.players` (engine array, always available) |
| `spawnStruct()` | Associative array: `s = []; s["key"] = val;` |
| `player isAlive()` (method) | `player.health > 0` |
| `isAlive(player)` (standalone) | `player.health > 0` |
| `player.team` | `player.pers["team"]` → returns `"allies"`, `"axis"`, or `"spectator"` |
| `setDvar("scr_player_healthregentime", "0")` | `setDvar("scr_player_healthregentime", "0")` DOES work — set it before `_healthoverlay::init()` threads so the engine reads 0 and disables regen itself |
| `level.onGiveLoadout = ::fn` | Does not exist in T5. Use `level.playerSpawnedCB = ::gf_playerSpawnedCB` instead; fire `level notify("spawned_player")` inside it to keep SD happy, then `self thread gf_onSpawned()` — thread runs after `giveLoadout` with no yield gap |

**Compile error diagnosis:** When T5 throws `unknown function: @ scripts/mp/<file>::<func>`, the broken call is INSIDE the named function — scan every call within it for T5 compatibility.

**Cross-file calls require `#include`:** Each `.gsc` file must `#include` every other mod script whose functions it calls **directly**. T5 does **not** support transitive includes — if A includes B which includes C, A cannot call functions from C. Each file must have its own explicit `#include` for every file it calls into. Missing include → `unknown function` compile error on the calling function. Current include chain: `mp_gunfight.gsc` → `_gf_rounds.gsc` → `_gf_loadouts.gsc` → `_gf_hud.gsc`. `_gf_tests.gsc` includes both `_gf_rounds` and `_gf_loadouts` directly since it calls functions from both.

---

## T5 Engine Reference

### SD callbacks registered in `sd.gsc::main()`
| Level var | Fires when |
|---|---|
| `level.playerSpawnedCB` | Player spawns → fires `level notify("spawned_player")` |
| `level.onPlayerKilled` | Player dies |
| `level.onDeadEvent(team)` | A team is fully eliminated |
| `level.onOneLeftEvent(team)` | Last player alive on a team |
| `level.onTimeLimit` | Round timer expires → defenders win |
| `level.onRoundSwitch` | Halftime / side swap |
| `level.onRoundEndGame` | Returns overall round winner string |

### SD state vars
- `game["attackers"]` / `game["defenders"]` — team role assignment
- `level.aliveCount[team]` — engine-maintained alive count per team
- `game["roundswon"]["allies"]` / `game["roundswon"]["axis"]` — round wins
- `game["roundsplayed"]` — rounds played so far

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
level.onGiveLoadout          // fires at end of giveLoadout — override to swap weapons
level.spawnClient            // queues/delays client spawn; default: _globallogic_spawn::spawnClient
level.spawnPlayer            // puts player into world; default: _globallogic_spawn::spawnPlayer
level._setTeamScore          // set team score directly (default updates game["teamScores"])
level._getTeamScore          // read team score (default returns game["teamScores"][team])
```

### Spawn pipeline (what happens inside `spawnPlayer()`)
Order of operations every time a player spawns:
1. `setSpawnVariables()` — sets player origin, angles, team, sessionstate = "playing"
2. `[[level.onSpawnPlayer]]()` — SD's callback; sets `isBombCarrier = false`, selects spawnpoint, calls `self spawn(...)`
3. `[[level.playerSpawnedCB]]()` — SD fires `level notify("spawned_player")` here ← our waittill
4. `maps\mp\gametypes\_class::setClass(self.class)` — sets perk state
5. `maps\mp\gametypes\_class::giveLoadout(team, class)` — gives default class weapons
6. **Our `gf_roundLoop` thread wakes** from `waittill("spawned_player")` and overwrites weapons with gunfight loadout

Step 6 is correct — our `takeAllWeapons` + custom weapons run *after* the engine's `giveLoadout`, replacing whatever it gave.

### Key game state vars
```gsc
game["state"]                 // "playing" | "postgame"
game["attackers"]             // team string of attacking team in SD
game["defenders"]             // team string of defending team
game["roundswon"]["allies"]   // rounds won by allies
game["roundswon"]["axis"]     // rounds won by axis
game["roundsplayed"]          // total rounds completed
level.gameEnded               // bool — set true when endGame() is called
level.inGracePeriod           // bool — grace period blocks deaths/forfeits
level.inOvertime              // bool — setting true blocks new spawns automatically
level.aliveCount["allies"]    // engine-maintained alive player count (updated by updateTeamStatus)
level.aliveCount["axis"]
level.alivePlayers["allies"]  // array of alive player entities
level.alivePlayers["axis"]
level.playerCount["allies"]   // total connected players per team (alive + dead)
```

### Ending a round / game
```gsc
// SD's wrapper — increments winning team score by 1, then ends round/game:
sd_endGame( winningTeam, endReasonText )

// Core engine function — use for our own endgame calls if not going through SD:
maps\mp\gametypes\_globallogic::endGame( winningTeam, endReasonText )

// Direct team score manipulation:
[[level._setTeamScore]]( "allies", newScore )
[[level._getTeamScore]]( "allies" )
```

### SD round cycling — confirmed working pattern

**`maps\mp\gametypes\sd::sd_endGame( winner, "" )`** — confirmed callable from mod scripts in Plutonium T5.

Calling this from `onDeadEvent` or a custom timer handler:
- Increments `game["roundswon"][winner]` by 1 and updates the scoreboard
- Checks `hitRoundWinLimit()` — ends the match if reached, otherwise cycles the round
- SD handles intermission display, player respawn, and the next prematch automatically
- No manual `pers["lives"]` reset needed — SD handles it
- No manual `[[level.spawnClient]]()` calls needed **between rounds** — SD handles respawning. But `gf_bypassClassChoice` must call it for the initial connect spawn (see class select suppression section).

**Round activation pattern** — since SD doesn't expose a "new round started" event, detect it from `onPlayerSpawned`:
```gsc
// In onPlayerSpawned:
if ( !level.gf_roundActive )
    level thread gf_tryActivateRound();

// gf_tryActivateRound — deduplicated, 0.2s grace window, then opens the round:
gf_tryActivateRound()
{
    if ( level.gf_activatingRound ) return;
    level.gf_activatingRound = true;
    level endon( "game_ended" );
    level.gf_timerEnd = gettime() + level.gf_cfg_roundTime * 1000;
    wait 0.2;
    if ( level.gf_roundActive ) { level.gf_activatingRound = false; return; }
    level.gf_roundNum++;
    level.gf_roundEnding     = false;   // clear from previous round
    level.gf_roundActive     = true;
    level.gf_activatingRound = false;
    level thread gf_roundTimer();
}
```

The 0.2s wait is a brief spawn-protection window (PvP blocked via `!gf_roundActive` in damage handler). `gf_timerEnd` is set before the wait so the HUD countdown shows immediately on spawn. `gf_roundEnding` must be explicitly cleared here — SD never resets it.

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

### Engine callbacks — full list
Registered by `_callbacksetup.gsc`. These engine events call into GSC:
```
CodeCallback_StartGameType()     game init — calls sd.gsc::main()
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
- **`updateTeamStatus()` runs async** (waittillframeend) — `level.aliveCount` may be one frame stale after a kill
- **`level.inGracePeriod = true` blocks forfeit/dead-event checks** — clear it before main gameplay starts
- **`level.inOvertime = true` prevents all new spawns** — useful for overtime zone capture
- **`map_restart(true)`** keeps player positions but resets entities AND `level.*` vars; `false` = full restart. `self.pers[]` and `game[]` are the only things that survive. Do not rely on `level.*` state across a `map_restart`.
- **`self.pers[]` persists across rounds** — player stats, team, class survive `map_restart`
- **`scr_disable_cac = 1`** makes `beginClassChoice` auto-assign `level.defaultClass = "CLASS_ASSAULT"` and auto-spawn
- **SD's `onDeadEvent`** checks `level.bombPlanted` before deciding winner — our override must handle this or replicate the logic

---

## T5 HUD System

All HUD elements created with `newClientHudElem(player)`.

**Coordinate system:**
- `horzAlign="left"`, `vertAlign="top"` → x/y are pixel offsets from screen top-left corner
- `horzAlign="left"`, `vertAlign="middle"` → y is vertical center of element (element straddles y)
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

**To resize a bar:** `e setShader("white", newWidth, height)` — call each update tick.
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
These are wrapper methods on HUD elements — call on an element created with `createIcon` / `createFontString`:
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
`hud.archived = false` — prevents HUD from being hidden during menus or demo playback.

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

All T5 weapon strings use `_mp` suffix. Pass these to `giveWeapon()`.

**Primary weapons**
```
Pistols:      python_speed_mp, makarovdw_mp, asp_mp, cz75_mp
Shotguns:     spas_mp, ithaca_mp, hs10_mp
SMG:          mp5k_mp, skorpiondw_mp, ak74u_mp, mp40_mp, spectre_mp, uzi_mp, pm63_mp
Assault:      m16_mp, famas_mp, aug_mp, galil_mp, commando_mp, fnfal_mp, m14_mp,
              g11_mp, enfield_mp
LMG:          hk21_mp, m60_mp, rpk_mp, stoner63_mp
Sniper:       l96a1_mp, wa2000_mp, dragunov_mp, psg1_mp
Launchers:    m72_law_mp, china_lake_mp, strela_mp, rpg_mp
Special:      crossbow_explosive_mp, knife_ballistic_mp
```

**Additional weapon strings (confirmed from weapons.txt)**
```
g11_mp       G11 (burst-fire AR)
enfield_mp   Enfield (AR)
ks23_mp      KS-23 (shotgun)
pm63_mp      PM-63 (SMG)
hs10_mp      HS-10 (akimbo shotgun)
asp_mp       ASP (pistol)
```

**Equipment / grenades**
```
frag_grenade_mp          flash_grenade_mp
smoke_grenade_mp         concussion_grenade_mp
satchel_charge_mp        mine_bouncing_betty_mp
knife_mp                 (always given, melee slot)
```

**giveWeapon arguments**
`GiveWeapon( weaponName )` — basic form.
`GiveWeapon( weaponName, dualWield )` — `dualWield` is a **boolean**, NOT a camo number.
- `true` gives the akimbo/dualwield variant
- `false` (or omit) gives the single variant
- **T6 uses a 3rd camo-number arg; T5 does not** — passing a number here may crash or be silently ignored

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

**Weapon & lethal icon shaders** — confirmed from Xinerki `t5-gunfight/duel.gsc` (T5 gametype mod).

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
satchel_charge_mp       -> hud_icon_satchel_charge   (confirmed in-game; hud_satchel_charge is wrong — shows satchel bomb, not Semtex)
sticky_grenade          -> hud_icon_sticky_grenade
hatchet                 -> hud_hatchet
Default: "hud_" + baseName
```

Tactical grenade icon shaders — confirmed from IWD `images/*.iwi` listing:
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

**Named shaders (precached by T5 — usable in setShader / createIcon)**
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

`score_bar_allies` / `score_bar_opfor` are particularly useful — native styled team HP/score bars the game uses internally.

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
```
Set via `setDvar( name, value )` in `init()`. `compass "0"` resolves the minimap-disable TODO.

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

## T5 Game Objects — Overtime Zone

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
self GiveWeapon( "frag_grenade_mp" );      // lethal grenade — use GiveWeapon, NOT GiveOffhandWeapon
self GiveWeapon( "flash_grenade_mp" );     // tactical grenade — same

// Perks:
self SetPerk( "specialty_fastreload" );
self SetPerk( "specialty_gpsjammer" );

// Remove a perk:
self UnSetPerk( "specialty_killstreak" );

// Equipment slot (claymore, camera spike etc — NOT grenades):
self GiveWeapon( equipment_weapon );
self SetActionSlot( 1, "weapon", equipment_weapon );
```
**`GiveOffhandWeapon` does NOT exist in T5.** Confirmed from `_class.gsc` in the BO1 install.
Use `GiveWeapon()` for ALL weapon types including grenades and equipment.
`SetActionSlot(1, "weapon", ...)` is only needed for equipment (claymores etc.) so they appear in the correct UI slot — grenades do not need it.

---

## T5 Player Utilities

### Controls & movement
```gsc
self freezeControls( 1 );        // lock movement + shooting (still allows looking)
self freezeControls( 0 );        // re-enable controls
// NOTE: confirmed in IW5 source; T5 should be identical — verify in-game

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
This is the same pattern used by our `gf_addRandomAttachment`.

### Objective markers
Simpler than createUseObject — just places a waypoint:
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

### givePlayerScore — event types
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

## Community Mod Patterns

Aggregated from: GunMd0wn T5 mod, mp_EMv2/iMCSx/EnCoReV8 (community BO1 mods), Xinerki/t5-gunfight, misterbubb/T6-Gunfight-Gamemode, bblack16/plutonium-waypoints IW5.

### Class select suppression (confirmed T5 method)

`allowClassChoice` **does not exist** in the T5 source. Community mod patterns targeting it do nothing.

The real function is `_globallogic_ui::beginClassChoice`. Built-in bypass:
```gsc
if ( level.oldschool || GetDvarInt("scr_disable_cac") == 1 )
{
    self.pers["class"] = level.defaultClass;  // "CLASS_ASSAULT"
    self.class = level.defaultClass;
    return;
}
```

**Current implementation:** `replacefunc( maps\mp\gametypes\_globallogic_ui::beginClassChoice, ::gf_bypassClassChoice )` — confirmed working in Plutonium T5.
`setDvar("scr_disable_cac", "1")` is also set but **does not work in Plutonium** (dvar is parsed but ignored at runtime). The replacefunc is the real fix.

**Critical:** the replacement function must also call `[[level.spawnClient]]()` and `updateTeamStatus()` — the original `beginClassChoice` calls these after assigning the class. Omitting them means players connect and pick a team but never spawn (stuck forever). Confirmed broken without it, confirmed fixed with it.
```gsc
gf_bypassClassChoice()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;
    self.pers["class"] = level.defaultClass;
    self.class         = level.defaultClass;
    if ( self.sessionstate != "playing" )
        self thread [[level.spawnClient]]();
    level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
}
```

### Weapon randomization via dvars (GunMd0wn pattern)
```gsc
setDvar("gunfight_current_game_primary", getRandomWeapon("primary"));
level.gunfight_current_game_primary = getDvar("gunfight_current_game_primary");
```

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

### Overtime countdown — manual decrement, pauses while zone contested
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

### hideHardpointModels — canonical pattern (confirmed misterbubb T6 matches our T5 impl)
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

### T5 player methods confirmed (Xinerki duel.gsc — T5 gametype)
```gsc
maps\mp\gametypes\_wager::setupBlankRandomPlayer( takeAll, chooseBody )
// clears player and optionally assigns a random body model; call before giveWeapon
```

### T6-only patterns — do NOT use in T5 mod scripts

| T6 pattern | T5 replacement |
|---|---|
| `foreach ( p in level.players )` | `for ( i=0; i<level.players.size; i++ )` |
| `isAlive( player )` | `player.health > 0` |
| `player.team` | `player.pers["team"]` |
| `player suicide()` | `player DoDamage( player.health+100, player.origin )` |
| Attachment format `base + "+reflex"` (T6) | T5: `base + "_reflex_mp"` |
| `level setClientField( "key", val )` | No T5 equivalent — use notify/HUD |
| `level.disableclassselection = 1` | T5: `setDvar("scr_disable_cac","1")` + `replacefunc` |
| `spawnStruct()` in mod scripts | `s = []; s["key"] = val;` |

---

## Design Reference (not T5-compatible)

### Official Cold War Gunfight logic (BOCW source reference)

Design reference only — not T5-compatible:
- `level.gunfightroundsperloadout` — how many rounds per loadout
- `game.var_96a8ff4a` — shuffled loadout array; `game.var_b6beb735` — current index
- Win hierarchy: 1) last team standing, 2) overtime zone capture, 3) HP comparison
- Overtime: map entity `gunfight_zone_center` + `gunfight_zone_trigger` required
- Timer pauses while zone is being captured
- `function_c4915ac()` = HP tiebreaker (sum alive players HP per team)
- Loadout given via `takeallweapons` -> `clearperks` -> equip from bundle -> force `specialty_sprint/slide/sprintreload/sprintheal`
- Always-on grace period: 3 seconds per round start

### BO3/T7 Gunfight mod patterns (Michael Akopyan, design reference)
- Weapon classes loaded from `gf_weapons.csv` via `TableLookup`
- Attachments in CSV separated by `+`, parsed with `StrTok(str, "+")`
- HUD pushed server-side via `clientfield::register` + `clientfield::set_to_player`; LUI renders it
- Singleton HUD update: `level notify("tag"); level endon("tag")` prevents spam
- Class select: `self.pers["class"] = level.defaultClass` + `self CloseMenu(MENU_CHANGE_CLASS)` + `globallogic_ui::closeMenus()`
