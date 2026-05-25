# Gunfight v2 — Round Loop (Initial Testable Slice)

## Context
Building v2 from scratch on a clean branch. Goal is a minimal but correct round loop that can
be loaded in-game and tested end-to-end before adding full HUD, overtime, or advanced features.
Everything is based on SD-native round cycling — we override SD callbacks rather than replacing
sd.gsc entirely.

Note: The rawfiles in the workspace are IW5 (MW3) source, not T5. All T5 API differences are
documented in CLAUDE.md and take precedence.

---

## Files Created

```
raw/scripts/mp/mp_gunfight.gsc       ← entry point, init, player lifecycle
raw/scripts/mp/_gf_rounds.gsc        ← round loop, bomb suppression, forfeit
raw/scripts/mp/_gf_loadouts.gsc      ← loadout pool, picking, giving
raw/scripts/mp/_gf_hud.gsc           ← loadout icon slide-in display
```

Include chain:
- `mp_gunfight.gsc`   → `#include scripts\mp\_gf_rounds`
- `_gf_rounds.gsc`    → `#include scripts\mp\_gf_loadouts`
- `_gf_loadouts.gsc`  → `#include scripts\mp\_gf_hud`

---

## Config (top of mp_gunfight.gsc::init)

| Var | Default | Meaning |
|---|---|---|
| `level.gf_cfg_roundTime` | 90 | seconds per round (→ scr_sd_timelimit in minutes) |
| `level.gf_cfg_winLimit` | 6 | rounds needed to win the match |
| `level.gf_cfg_roundSwitch` | 3 | switch sides every N rounds |
| `level.gf_cfg_roundsPerLoadout` | 2 | rounds before rotating to next loadout |

---

## Key Design Notes

- **SD-native round cycling**: `sd_endGame(winner, "")` handles score, win-limit, intermission, respawn
- **Round activation**: detected from `level.onGiveLoadout` (fires per-player after engine gives weapons); `gf_tryActivateRound` has 0.2s dedup guard
- **Timer**: SD's native timer (`scr_sd_timelimit`); paused 3s pre-round via `pauseTimer()`/`resumeTimer()`; `onTimeLimit` → defenders win
- **Loadout**: 22-entry pool (AR×7, SMG×6, LMG×4, Sniper×2, Shotgun×2); pre-shuffled at match start; index = `int(roundsplayed / roundsPerLoadout) % poolSize`; random attachment applied at pick time; random lethal/tactical each round
- **HUD**: weapon icon slide-in adapted from Xinerki t5-gunfight/duel.gsc; 3 rows (primary/secondary/lethal), slides in from right, holds 5.5s, slides back out

---

## TODO — Future Iterations

- [ ] Multi-gametype support: HQ and TDM
- [ ] Overtime zone (reuse hq_hardpoint entity)
- [ ] Full HP bar / score dot HUD
- [ ] Perk pop-in display
- [ ] Kill-ding sound alias (valid T5 alias needed)
- [ ] Mid-round join grace period

---

## Verification Checklist

- [ ] `loadMod mp_gunfight` → `map_restart` — no script errors
- [ ] No class select menu on spawn (replacefunc working)
- [ ] All players get same primary/secondary/equipment each round
- [ ] Loadout icons slide in on spawn, hold, slide out
- [ ] SD timer counts down
- [ ] Killing all enemies ends round, scoreboard increments winner
- [ ] No respawns mid-round
- [ ] No killstreaks
- [ ] 6 round wins ends match
- [ ] Forfeit: empty team → other team wins after 20s grace
