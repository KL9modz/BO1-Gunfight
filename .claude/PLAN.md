# Gunfight v2 — Round Loop (Initial Testable Slice)

## Context
Building v2 from scratch on a clean branch. Goal is a minimal but correct round loop that can be loaded in-game and tested end-to-end before adding HUD, overtime, or advanced features. Everything is based on SD-native round cycling — we override SD callbacks rather than replacing sd.gsc entirely.

Note: The rawfiles in the workspace are IW5 (MW3) source, not T5. All T5 API differences are documented in CLAUDE.md and take precedence.

---

## Files to Create

```
raw/scripts/mp/mp_gunfight.gsc       ← entry point, init, player lifecycle
raw/scripts/mp/_gf_rounds.gsc        ← round loop, timer, bomb suppression, forfeit
raw/scripts/mp/_gf_loadouts.gsc      ← loadout pool, picking, giving
raw/scripts/mp/_gf_hud.gsc           ← stub: timer text only (full HUD deferred)
```

Include chain (each file #includes what it calls directly):
- `mp_gunfight.gsc` → `#include _gf_rounds`
- `_gf_rounds.gsc` → `#include _gf_loadouts`
- `_gf_loadouts.gsc` → `#include _gf_hud`

---

## mp_gunfight.gsc — Entry Point

### `init()`
Called by the engine after sd.gsc's `main()` runs.

```
0. Config — set once here, read everywhere else via level.gf_cfg_*
   level.gf_cfg_roundTime        = 90   // seconds per round
   level.gf_cfg_winLimit         = 6    // rounds needed to win the match
   level.gf_cfg_roundSwitch      = 3    // switch sides every N rounds (scr_sd_roundswitch)
   level.gf_cfg_roundsPerLoadout = 2    // rounds before rotating to next loadout

1. Dvars — derived from config
   setDvar("scr_sd_numlives",    "1")
   setDvar("scr_sd_timelimit",   string(level.gf_cfg_roundTime / 60.0))  // SD expects minutes
   setDvar("scr_sd_roundswitch", string(level.gf_cfg_roundSwitch))
   setDvar("scr_disable_cac",    "1")
   setDvar("compass",            "0")
   level.killstreaksenabled = 0
   level.healthRegenDisabled = true
   level.playerHealth_RegularRegenDelay = 0
   level.roundWinLimit = level.gf_cfg_winLimit

2. State
   level.gf_roundActive      = false
   level.gf_roundNum         = 0
   level.gf_roundEnding      = false
   level.gf_activatingRound  = false

3. Scoreboard
   setscoreboardcolumns("kills", "deaths", "none", "none")

4. Callbacks — override SD's defaults
   level.onDeadEvent  = ::gf_onDeadEvent    // suppress bomb logic, call sd_endGame
   level.onTimeLimit  = ::gf_onTimeLimit    // timer expiry → defenders win
   replacefunc(maps\mp\gametypes\_globallogic_ui::beginClassChoice, ::gf_bypassClassChoice)

5. Threads
   level thread gf_waitForPlayers()   // waittill loop → gf_tryActivateRound + giveLoadout
   level thread gf_bombSuppress()     // 0.5s poll kills bomb interact
   level thread gf_forfeitWatch()     // polls for empty teams post-prematch
```

### `gf_waitForPlayers()`
Waits on `level waittill("spawned_player")` in a loop. On each fire:
- Calls `gf_giveLoadout(player)` on the spawning player
- If `!level.gf_roundActive`: `level thread gf_tryActivateRound()`

### `gf_bypassClassChoice()`
Replacement for `beginClassChoice`:
```
self.pers["class"] = level.defaultClass;
self.class = level.defaultClass;
```

---

## _gf_rounds.gsc — Round Management

### `gf_tryActivateRound()`
Dedup guard + 0.2s grace window before opening a new round:
```
if (level.gf_activatingRound) return;
level.gf_activatingRound = true;
level endon("game_ended");
wait 0.2;
if (level.gf_roundActive) { level.gf_activatingRound = false; return; }
level.gf_roundNum++;
level.gf_roundEnding    = false;   // SD never resets this — must do it ourselves
level.gf_roundActive    = true;
level.gf_activatingRound = false;
pauseTimer();    // pause SD's native clock during 3s pre-round countdown
wait 3;
resumeTimer();   // SD timer runs from here; fires onTimeLimit at expiry
```
No custom `gf_roundTimer()` needed — SD's native timer handles countdown and fires `level.onTimeLimit`.

### `gf_onDeadEvent(team)`
Our override of `level.onDeadEvent`. Suppresses SD's bomb logic entirely:
```
if (level.gf_roundEnding) return;
level.gf_roundEnding = true;
level.gf_roundActive = false;
level notify("gf_round_over");

winner = (team == "all") ? game["defenders"] : maps\mp\_utility::getOtherTeam(team);
maps\mp\gametypes\sd::sd_endGame(winner, "");
```

### `gf_onTimeLimit()`
Timer expired → defenders win:
```
if (level.gf_roundEnding) return;
level.gf_roundEnding = true;
level.gf_roundActive = false;
level notify("gf_round_over");
maps\mp\gametypes\sd::sd_endGame(game["defenders"], "");
```

### `gf_bombSuppress()`
0.5s poll — nullifies bomb plant/defuse by killing the bomb interact trigger:
```
level endon("game_ended");
while (true)
{
    level.bombplanted = 0;
    // disable plant/defuse prompts by zeroing interact triggers if any exist
    wait 0.5;
}
```

### `gf_forfeitWatch()`
Polls every 10s after prematch. Two consecutive all-empty-team checks (20s grace) → `endGame()`:
```
level endon("game_ended");
wait 30;   // prematch grace
while (true)
{
    wait 10;
    if (gf_teamIsEmpty("allies") || gf_teamIsEmpty("axis"))
    {
        wait 10;
        if (gf_teamIsEmpty("allies"))
            maps\mp\gametypes\_globallogic::endGame("axis", "");
        else if (gf_teamIsEmpty("axis"))
            maps\mp\gametypes\_globallogic::endGame("allies", "");
    }
}
```

### `gf_teamIsEmpty(team)` / `gf_getAliveCount(team)`
Use `p.sessionstate == "playing"` check to exclude loading/spectating:
```
gf_getAliveCount(team)
{
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (p.pers["team"] == team && p.sessionstate == "playing" && p.health > 0)
            count++;
    }
    return count;
}
```

---

## _gf_loadouts.gsc — Loadout System

### `gf_initLoadouts()`
Called once in `init()`. Builds the 22-loadout pool and shuffle index in `game[]` so it persists across rounds:
```
if (isDefined(game["gf_init"])) return;
// build game["gf_pool"] = array of loadout structs
// game["gf_idx"] = 0
// game["gf_init"] = 1
```

Loadout pool (22 entries across 5 classes):
- AR ×7, SMG ×6, LMG ×4, Sniper ×2, Shotgun ×2
- Each entry: `load["primary"]`, `load["secondary"]`, `load["lethal"]`, `load["tactical"]`, `load["perks"]` (array of 3), `load["primaryShader"]`, `load["secondaryShader"]`, `load["lethalShader"]`

Perks per class (local vars — no #define in T5):
- AR: specialty_fastreload, specialty_bulletaccuracy, specialty_gpsjammer
- SMG: specialty_movefaster, specialty_fastreload, specialty_quieter
- LMG: specialty_bulletpenetration, specialty_fastreload, specialty_armorvest
- Sniper: specialty_holdbreath, specialty_gpsjammer, specialty_quieter
- Shotgun: specialty_movefaster, specialty_fastreload, specialty_armorvest

### `gf_pickLoadout()`
Shuffle-without-repeat using Fisher-Yates on `game["gf_pool"]`.
Loadout index advances based on `gf_cfg_roundsPerLoadout`:
```
game["gf_idx"] = int(game["roundsplayed"] / level.gf_cfg_roundsPerLoadout) % game["gf_pool"].size;
```
Stores result in `level.gf_currentLoad`. Called at the start of each round activation.

### `gf_giveLoadout(player)`
Called on each player spawn:
```
self takeAllWeapons();
self clearPerks();
self GiveWeapon(level.gf_currentLoad["primary"]);
self GiveWeapon(level.gf_currentLoad["secondary"]);
self GiveWeapon("knife_mp");
self switchToWeapon(level.gf_currentLoad["primary"]);
self giveMaxAmmo(level.gf_currentLoad["primary"]);
self giveMaxAmmo(level.gf_currentLoad["secondary"]);
self GiveOffhandWeapon(level.gf_currentLoad["lethal"]);
self GiveOffhandWeapon(level.gf_currentLoad["tactical"]);
perks = level.gf_currentLoad["perks"];
for (i = 0; i < perks.size; i++)
    self SetPerk(perks[i]);
```

### `gf_addRandomAttachment(baseWeapon, attList)`
Picks one attachment from attList + 2 empty slots (~33% no-attachment chance).
Builds name as: `getSubStr(base, 0, base.size - 3) + "_" + att + "_mp"`

---

## _gf_hud.gsc — Loadout Icon Display

Adapted from Xinerki `t5-gunfight/duel.gsc` → `showWeaponInfo()` / `fadeWeaponInfo()`.
Reference: https://github.com/Xinerki/t5-gunfight/blob/master/maps/mp/gametypes/duel.gsc

### `gf_showLoadoutHUD(player)`
Called from `gf_giveLoadout()` on each spawn. Shows primary, secondary, lethal icons sliding in from the right, holds 5s, slides back out.

**Shader names** — built when pool is created in `gf_initLoadouts()` and stored on each loadout struct:
```
load["primaryShader"]   = "menu_mp_weapons_" + baseName   // strip _mp suffix, handle special cases
load["secondaryShader"] = "menu_mp_weapons_" + baseName   // python→python, m1911→colt, makarov→makarov, cz75→cz75
load["lethalShader"]    = "hud_" + baseName               // frag_grenade→hud_grenadeicon, sticky_grenade→hud_icon_sticky_grenade, hatchet→hud_hatchet
```
All shaders precached in `gf_initLoadouts()` via `PreCacheShader()` at match start.

**Element layout** (3 rows: primary, secondary, lethal):
```
Icon:  64×32 px,  alignX="right", horzAlign="right", vertAlign="middle"
Text:  font="smallfixed", fontScale=1.0, alignX="right", horzAlign="right"
Y positions: primary=-128, secondary=-114, lethal=-100
hidewheninmenu = true
```

**Slide-in animation** (same as Xinerki pattern):
```
icon.x = 400;  text.x = 400;    // start off-screen right
icon moveOverTime(0.3);
text moveOverTime(0.3);
icon.x = -5;   text.x = -72;    // slide to final position
```

**Fade-out** — `gf_fadeLoadoutHUD()` thread:
```
self endon("death");
self endon("disconnect");
wait 5.5;
// slide back to x=400 over 0.3s
// then destroyElem
```

---

## Build Order

1. `_gf_hud.gsc` — no dependencies
2. `_gf_loadouts.gsc` — #includes _gf_hud
3. `_gf_rounds.gsc` — #includes _gf_loadouts
4. `mp_gunfight.gsc` — #includes _gf_rounds

---

## TODO — Future Iterations

- **Multi-gametype support** — currently SD only; add HQ and TDM support
  - HQ: hook `onCapture`/`onDeadEvent` equivalents, suppress hardpoint objective
  - TDM: no round cycling built-in, need manual round loop + respawn block
  - Abstract gametype-specific callbacks behind a shared interface so round logic stays the same

---

## Verification (In-Game Test Checklist)

- [ ] Load mod: `loadMod mp_gunfight` → `map_restart`
- [ ] No class select menu appears on spawn (replacefunc working)
- [ ] All players receive same primary/secondary/equipment
- [ ] SD's native round timer counts down
- [ ] Killing all enemies ends round, scoreboard increments winner
- [ ] No respawns mid-round (numlives=1)
- [ ] No killstreaks available
- [ ] 6 round wins ends the match
- [ ] Forfeit: disconnect all players from one team → other team wins
