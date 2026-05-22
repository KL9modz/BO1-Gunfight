# mp_gunfight — Plutonium T5 (Black Ops 1 MP) Gunfight Mod

## TODO
- HUD (Cold War Gunfight style — player icons, HP bars, score dots)
  Target layout with `horzAlign="left"`, `vertAlign="top"`:
  ```
  y=126  dark background panel  162×38 px               y=164
  y=137  [icon][icon] [==bar==] HP  . . . . . .  allies row
  y=144  separator line
  y=153  [icon][icon] [==bar==] HP  . . . . . .  axis row
  ```
  - Player icons: 9×13 px squares, blue=allies alive, green=axis alive, gray=dead, hidden=slot empty
  - HP bar: 68 px max (200 HP full), 5 px tall, scales with total team HP
  - HP number: text to right of bar
  - Score dots: 6 per row at x=122+d×7, 5×5 px; ally wins → blue, axis wins → red, unscored → gray

  Planned element refs on each player entity:
  ```
  player.gf_hudBg              background panel
  player.gf_hudSep             separator line
  player.gf_hudAlliesIcon[0/1] player icons
  player.gf_hudAlliesBarBg     bar background
  player.gf_hudAlliesBarFg     bar foreground (resized each tick)
  player.gf_hudAlliesHp        HP number text
  player.gf_hudAllyDot[0..5]   score dots
  player.gf_hudAxisIcon[0/1]
  player.gf_hudAxisBarBg/Fg
  player.gf_hudAxisHp
  player.gf_hudAxisDot[0..5]
  ```
- Overtime mechanic
- Mid-round join grace period (~10s window to allow spawn instead of hard block)
- Prematch control lockout (investigate T5 equivalent of `FreezeControlsAllowLook`)
- Death sounds (wire `level.onPlayerKilled`, test aliases like `"uin_challenge_repeatable"` in-game)
- Minimap disable
- Forfeit handling (if a team drops to 0 connected players, end the match gracefully)
- ~~Verify `colt45_mp`~~ — does not exist; replaced with `m1911_mp` in all loadouts ✅
- More loadout variety (LMGs, Ithaca shotgun, Skorpion/MAC-11)
- Weapon camos — no direct GSC function exists in T5; engine ties camos to DDL persistent data. Options: (1) check Plutonium modding API/Discord for a native camo setter, (2) test populating `self.custom_class[0]["camo_num"]` before spawn with class set to `CLASS_CUSTOM1`
- Wager match modes (Gun Game, Sharpshooter — reference gun.gsc and shrp.gsc from plutoniummod/t5-scripts)
- ~~Verify attachment strings~~ — all confirmed from primetime43 weapon dump ✅: `extclip`, `reflex`, `acog`, `silencer`, `rf` (Rapid Fire, NOT `rapidfire`), `vzoom` (Variable Zoom, NOT `variable`), `grip`. SPAS has no grip variant — `silencer` used instead.
- Remove debug `iprintln` in `gf_giveLoadout` once attachments are confirmed working in-game

## DONE
- ✅ Perks per loadout — Lightweight, Hardened, Marathon given to all loadouts
- ✅ Perk display notification — `gf_displayPerks()` in `_gf_hud.gsc`: wager-style HUD (icon + name, right side, scale pop-in, 5s fade). Icon strings unverified in-game: `specialty_marathon`, `specialty_hardened`, `specialty_lightweight`
- ✅ Attachment fix — `suppressor` → `silencer` (confirmed correct T5 string)
- ✅ Class select suppression — `replacefunc` on `beginClassChoice` (see class select section below)
- ✅ Health regen disabled — `level.healthRegenDisabled = true` + `level.playerHealth_RegularRegenDelay = 0`
- ✅ State persistence — `gf_state_*` dvars survive `map_restart`
- ✅ Bomb suppression — SD bomb hidden and disabled each round
- ✅ Script split — 4 files under `raw/scripts/mp/`

---

## Resources

### T5 Source Code
- **plutoniummod/t5-scripts** — Official Plutonium T5 source dump (MP + ZM gametypes, utility scripts, etc.)
  https://github.com/plutoniummod/t5-scripts
  Key files: `MP/Common/maps/mp/gametypes/shrp.gsc`, `gun.gsc`, `sd.gsc`, `_wager.gsc`, `_globallogic.gsc`, `_class.gsc`, `_hud_util.gsc`, `_rank.gsc`
- **Local T5 source dump** (user's machine): `C:\Users\klaze\OneDrive - sdccd.edu\Desktop\GSC\MP\Common`

### Community BO1 Mods (reference/pattern source)
- **iAmThatMichael/gunfight** — BO3/T7 Gunfight recreation; used for game-mode design reference
  https://github.com/iAmThatMichael/gunfight
- **GunMd0wn custom_gunfight.gsc** — BO1 community Gunfight mod (runs on HQ/TDM); source of class-select suppression patterns and weapon dvar approach
- **mp_EMv2_Recreation, mp_iMCSx, mp_EnCoReV8** — Community BO1 mods; source of HUD element patterns (`newHudElem`, `newClientHudElem`, `NewScoreHudElem`, `hud.archived`, `fontPulse`)
- **Resxt/Plutonium-T5-Scripts** — Collection of community T5 GSC scripts
  https://github.com/Resxt/Plutonium-T5-Scripts

### Weapon & Asset References
- **BO1 MP Weapon list** — verified full dump by primetime43; authoritative for weapon strings and attachment variants
  (local copy shared in project chat; original: https://pastebin.com/ZbKLyVTk)
- **MW2 full weapon list** — Used as naming convention cross-reference for attachment strings (IW4, not T5 — verify before using)
  https://github.com/Gerst20051/Game-Mods/blob/master/Modern%20Warfare%202/Weapons.txt
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

---

## Project overview
Custom Gunfight game mode for Black Ops 1 running on Plutonium T5 MP.
Layered over the SD (Search & Destroy) gametype. Solo offline only.

**Load:** `loadMod mp_gunfight` in the Plutonium console, then `map_restart`.
**Mod folder must be prefixed `mp_`** for it to appear in the in-game mod menu.

**File layout:**
```
raw/scripts/mp/
  mp_gunfight.gsc   -- entry point, init, state persistence, player lifecycle
  _gf_loadouts.gsc  -- loadout pool, picking, giving, random attachment, perk display
  _gf_hud.gsc       -- live HP display, perk pop-in notification
  _gf_rounds.gsc    -- round management, end conditions, audio, bomb suppression
  mp_spawn_fix.gsc  -- spawn fix utility
```

---

## T5 GSC — Critical API differences from T6/T7

These are confirmed-broken functions in T5 mod scripts and their correct replacements:

| Broken in T5 mods | Correct T5 replacement |
|---|---|
| `getPlayers()` | `level.players` (engine array, always available) |
| `spawnStruct()` | Associative array: `s = []; s["key"] = val;` |
| `player isAlive()` (method) | `player.health > 0` |
| `isAlive(player)` (standalone) | `player.health > 0` |
| `player.team` | `player.pers["team"]` → returns `"allies"`, `"axis"`, or `"spectator"` |
| `setDvar("scr_player_healthregentime", "0")` | `level.playerHealth_RegularRegenDelay = 0; level.healthRegenDisabled = true;` |

**Compile error diagnosis:** When T5 throws `unknown function: @ scripts/mp/<file>::<func>`, the broken call is INSIDE the named function — scan every call within it for T5 compatibility.

---

## T5 HUD system

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

---

## Current mod — what's built

### Round flow
- Based on SD: 2v2, one life per player, no respawns
- Round score tracked in `level.gf_alliesWins` / `level.gf_axisWins`
- First to 6 round wins wins the match (configurable via `scr_sd_winlimit`)
- `level.gf_roundNum` tracks current round number

### Loadout
- 12 loadouts, randomly cycled without back-to-back repeats; all 4 players share the same loadout
- Health regen disabled via `level.playerHealth_RegularRegenDelay = 0` + `level.healthRegenDisabled = true`
- Perks given to all loadouts: `specialty_movefaster`, `specialty_bulletpenetration`, `specialty_longersprint`
- Attachment system: `gf_addRandomAttachment(baseWeapon, attList)` picks one random attachment from space-separated list (2 extra empty slots give ~33% no-attachment chance)
- **T5 attachment keyword strings** (used embedded in weapon name: `famas_silencer_mp`) — all confirmed from primetime43 weapon dump:
  - `reflex` — Reflex sight
  - `acog` — ACOG scope
  - `silencer` — Silencer
  - `extclip` — Extended Mags
  - `rf` — Rapid Fire (NOT `rapidfire`)
  - `vzoom` — Variable Zoom sniper scope (NOT `variable`)
  - `grip` — Grip/Foregrip (not available on SPAS)
- All weapon+attachment variants precached at startup via `gf_precacheWeapons()`

### Class select suppression — CONFIRMED T5 method (from source)

`allowClassChoice` **does not exist** in the T5 source. The community mod pattern targeting it is wrong.

The real function is `_globallogic_ui::beginClassChoice`. It has a built-in bypass:
```gsc
if ( level.oldschool || GetDvarInt("scr_disable_cac") == 1 )
{
    self.pers["class"] = level.defaultClass;  // "CLASS_ASSAULT"
    self.class = level.defaultClass;
    // auto-spawns if not already playing
    return;
}
```

**Current implementation:** `replacefunc( maps\mp\gametypes\_globallogic_ui::beginClassChoice, ::gf_bypassClassChoice )` — confirmed working in Plutonium T5.
`setDvar("scr_disable_cac", "1")` is also set but **does not work in Plutonium** (dvar is parsed but ignored at runtime). The replacefunc is the real fix.
`setDvar("scr_sd_selectclass", "0")` kept as extra insurance.

---

## T5 SD source — confirmed facts (from MP/Common source dump)

Source: `C:\Users\klaze\OneDrive - sdccd.edu\Desktop\GSC\MP\Common`

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

### Useful T5 utility functions (maps\mp\_utility)
```gsc
getOtherTeam( team )               // "allies"↔"axis"
getRoundsWon( team )               // game["roundswon"][team]
getRoundsPlayed()                  // game["roundsplayed"]
hitRoundWinLimit()                 // true if any team hit level.roundWinLimit
playSoundOnPlayers( sound, team )  // plays local sound to all players on team
dvarIntValue( name, def, min, max )  // reads scr_sd_<name>, sets default if unset
```

---

## T5 engine internals — core gametype system

### Overridable callbacks (set in `_globallogic.gsc::SetupCallbacks()`)
These are all function-pointer level vars a custom gametype can override:
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

### Critical gotchas
- **`updateTeamStatus()` runs async** (waittillframeend) — `level.aliveCount` may be one frame stale after a kill
- **`level.inGracePeriod = true` blocks forfeit/dead-event checks** — clear it before main gameplay starts
- **`level.inOvertime = true` prevents all new spawns** — useful for overtime zone capture
- **`map_restart(true)`** (called between rounds) keeps player positions but resets entities; `false` = full restart
- **`self.pers[]` persists across rounds** — player stats, team, class survive `map_restart`
- **`scr_disable_cac = 1`** makes `beginClassChoice` auto-assign `level.defaultClass = "CLASS_ASSAULT"` and auto-spawn
- **SD's `onDeadEvent`** checks `level.bombPlanted` before deciding winner — our override must handle this or replicate the logic

---

## Gunfight mode design (from BOCW source reference)

Official CW Gunfight logic (not T5-compatible, reference only):
- `level.gunfightroundsperloadout` — how many rounds per loadout
- `game.var_96a8ff4a` — shuffled loadout array; `game.var_b6beb735` — current index
- Win hierarchy: 1) last team standing, 2) overtime zone capture, 3) HP comparison
- Overtime: map entity `gunfight_zone_center` + `gunfight_zone_trigger` required
- Timer pauses while zone is being captured
- `function_c4915ac()` = HP tiebreaker (sum alive players HP per team)
- Loadout given via `takeallweapons` → `clearperks` → equip from bundle → force `specialty_sprint/slide/sprintreload/sprintheal`
- Always-on grace period: 3 seconds per round start

---

## T5 community Gunfight mod patterns (applicable to this project)

From `custom_gunfight.gsc` by GunMd0wn (runs on BO1 HQ/TDM):

**Class select suppression — NOTE: `allowClassChoice` does not exist in T5 source.**
This `replacefunc` pattern from GunMd0wn's mod targets a ghost function and does nothing.
The correct method (confirmed from T5 source) is `setDvar("scr_disable_cac", "1")` — see the class select section above.

**Weapon randomization via dvars (T5 pattern):**
```gsc
setDvar("gunfight_current_game_primary", getRandomWeapon("primary"));
// re-reads each round, all players get same weapon
level.gunfight_current_game_primary = getDvar("gunfight_current_game_primary");
```

**Team health score display:**
```gsc
maps\mp\gametypes\_gamescore::_setteamscore("allies", getTeamHealth("allies"));
```

**Health regen disable (confirmed T5):**
```gsc
level.healthregendisabled = 1;
```

---

## BO3 community Gunfight mod patterns (design reference)

From `gf.gsc` by Michael Akopyan (BO3/T7):
- Weapon classes loaded from `gf_weapons.csv` via `TableLookup`
- Attachments in CSV separated by `+`, parsed with `StrTok(str, "+")`
- HUD pushed server-side via `clientfield::register` + `clientfield::set_to_player`; LUI renders it
- Singleton HUD update: `level notify("tag"); level endon("tag")` prevents spam
- Class select: `self.pers["class"] = level.defaultClass` + `self CloseMenu(MENU_CHANGE_CLASS)` + `globallogic_ui::closeMenus()`

---

## T5 asset reference — weapons

All T5 weapon strings use `_mp` suffix. Pass these to `giveWeapon()`.

### Primary weapons
```
Pistols:      python_speed_mp, makarovdw_mp
Shotguns:     spas_mp, ithaca_mp
SMG:          mp5k_mp, skorpiondw_mp, ak74u_mp, mp40_mp, spectre_mp, uzi_mp
Assault:      m16_mp, famas_mp, aug_mp, galil_mp, commando_mp, fnfal_mp, m14_mp
LMG:          hk21_mp, m60_mp, rpk_mp, stoner63_mp
Sniper:       l96a1_mp, wa2000_mp, dragunov_mp, psg1_mp
Launchers:    m72_law_mp, china_lake_mp, strela_mp, rpg_mp
Special:      crossbow_explosive_mp, knife_ballistic_mp
```

### Equipment / grenades
```
frag_grenade_mp          flash_grenade_mp
smoke_grenade_mp         concussion_grenade_mp
satchel_charge_mp        mine_bouncing_betty_mp
knife_mp                 (always given, melee slot)
```

### Weapon options struct (for giveWeapon 3rd arg)
```gsc
options = spawnStruct();   // or use [] associative array in T5 mods
options["akimbo"] = true;
options["attachment1"] = "acog_mp";   // attachment suffix strings
```
Common attachments: `acog_mp`, `reflex_mp`, `silencer_mp`, `dualwield_mp`, `grip_mp`, `masterkey_mp`, `flamethrower_mp`

---

## T5 asset reference — perks

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

---

## T5 asset reference — HUD shaders & functions

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

### Named shaders (precached by T5 — usable in setShader / createIcon)
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

**`score_bar_allies` / `score_bar_opfor`** are particularly useful — these are the native styled team HP/score bars the game already uses internally.

---

## T5 asset reference — audio

### leaderDialog (voice callouts)
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

### Music states
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

### Sound playback
```gsc
self playLocalSound( alias )                           // plays to this player only
maps\mp\_utility::playSoundOnPlayers( alias, team )   // plays to whole team (or all if team undefined)
play_sound_in_space( alias, origin )                   // positional 3D sound
```

---

## T5 engine callbacks — full list

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

---

## T5 class & menu constants

### Class name constants
```
CLASS_ASSAULT    CLASS_SMG       CLASS_CQB
CLASS_LMG        CLASS_SNIPER
OFFLINE_CLASS1 … OFFLINE_CLASS10    (offline preset classes)
CLASS_CUSTOM1  … CLASS_CUSTOM5      (online custom classes)
CLASS_CUSTOM6  … CLASS_CUSTOM10     (prestige custom slots)
```
`level.defaultClass = "CLASS_ASSAULT"` (set in _class.gsc init)

### Menu name constants (game["menu_*"])
```
game["menu_team"]                  = "team_marinesopfor"
game["menu_class_allies"]          = "class_marines"
game["menu_class_axis"]            = "class_opfor"
game["menu_changeclass_allies"]    = "changeclass"
game["menu_changeclass_axis"]      = "changeclass"
game["menu_changeclass_custom"]    = "changeclass_custom"
game["menu_changeclass_barebones"] = "changeclass_barebones"
```

---

## T5 spawn system

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

---

## T5 game objects — overtime zone

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

## T5 loadout delivery — correct pattern

```gsc
// Full custom loadout override (call after spawned_player):
self takeAllWeapons();
self GiveWeapon( "famas_mp" );
self GiveWeapon( "python_speed_mp" );
self GiveWeapon( "knife_mp" );
self switchToWeapon( "famas_mp" );
self giveMaxAmmo( "famas_mp" );
self giveMaxAmmo( "python_speed_mp" );
self GiveOffhandWeapon( "frag_grenade_mp" );

// Perks:
self SetPerk( "specialty_fastreload" );
self SetPerk( "specialty_gpsjammer" );

// Remove a perk:
self UnSetPerk( "specialty_killstreak" );

// Equipment slot (flash, smoke, claymore etc):
self SetActionSlot( 1, "weapon", "flash_grenade_mp" );
```
`GiveOffhandWeapon` handles grenades/equipment. `SetActionSlot` maps equipment to UI slots 1-4.

---

## File structure
```
Gunfight/  (GitHub: KL9modz/Gunfight)
  CLAUDE.md                        ← this file
  README.md
  .gitignore
  mp_gunfight.code-workspace
  .vscode/
    settings.json                  ← GSC extension config, runtime folder exclusions, rulers
    extensions.json                ← recommends eyza.aw-gsc
  raw/
    scripts/
      mp/
        mp_gunfight.gsc            ← entry point, init, state persistence, player lifecycle
        _gf_loadouts.gsc           ← loadout pool, picking, giving, attachment randomizer
        _gf_hud.gsc                ← HP HUD, perk pop-in display
        _gf_rounds.gsc             ← round management, end conditions, audio, bomb suppression
        mp_spawn_fix.gsc           ← spawn fix utility
      sp/
        zm_spawn_fix.gsc
```

---

## Community mod findings (from mp_EMv2_Recreation, mp_iMCSx, mp_EnCoReV8)

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

### Spawn point weighting
```gsc
addSphereInfluencer( origin, radius, weight );
// weight > 0 attracts spawns; weight < 0 repels
// call on a spawn point entity or level-level to bias the engine spawn system
```

### Dynamic music
```gsc
actionMusicSet( "state_name" );   // triggers music state (e.g. "round_end_win", "combat")
```

### String utilities (confirmed working in T5)
```gsc
strTok( string, delimiter )        // splits string → array
getSubStr( string, start, end )    // substring; end = string.size to go to end
```

### Visual effects
```gsc
fxid = loadfx( "fx/path/to/effect" );
spawnFx( fxid, origin );
triggerFx( fxid );
```

### Function pointer arrays (dynamic dispatch / menu systems)
```gsc
// Store function pointers in an array for dynamic menus or option tables
menu.functions = [];
menu.functions[0] = ::myFunc;
menu.functions[1] = ::otherFunc;
// Call: self [[ menu.functions[selected] ]]();
```

### notify/waittill as state machine
Use `level notify("state_name")` + `level waittill("state_name")` to drive state transitions instead of polling flags. Cleaner than busy-wait loops for events like round start/end.

### Weapon attachment name pattern (from shrp.gsc line 267)
```gsc
// Strip _mp suffix, append _att_mp
base = getSubStr( weaponName, 0, weaponName.size - 3 );   // removes "_mp"
result = base + "_" + attachmentName + "_mp";
// e.g. "famas_mp" + "reflex" → "famas_reflex_mp"
```
This is the same pattern used by our `gf_addRandomAttachment`.

### Admin / permission pattern
```gsc
// Check if player is host/admin via GUID or dvar list
if ( player.guid == getDvar( "sv_adminGUID" ) ) { ... }
// Or maintain a level.admins[] array populated at connect time
```
