---
name: xp-scrxpscale-readonly-and-dead-score-path
description: "scr_xpscale is READ-ONLY on Plutonium T5 (rcon + cfg both rejected) so it can never be an XP lever; and in Gunfight level.overridePlayerScore kills the whole givePlayerScore XP path (assists/captures), leaving registerScoreInfo + a direct giveRankXP call as the only knobs"
metadata: 
  node_type: memory
  type: project
  originSessionId: e567b5ad-0ade-42a5-b856-3a58ff19adbc
---

**"Can we set `scr_xpscale 2` for a 2XP weekend?" — No. It is DVAR_ROM on Plutonium T5.**
Proven live on the VPS (2026-07-12): rcon `set scr_xpscale 2` → `^1Error: scr_xpscale is read only`,
value stayed `1`. The **same error appears at boot** in `console_mp.log` — that is our own
`dedicated.cfg` line `set scr_xpscale "1"` being rejected, not a local-testing quirk (CLAUDE.md said
that for years; fixed). Presumably Plutonium locks it so servers can't farm ranked XP.
The only script-side equivalent is assigning `level.xpScale` after `_rank::init` runs.

**Where XP actually comes from in this mod** (all verified against the raw dump):

- **Kills/headshots: `Callback_PlayerKilled` → `_globallogic_score::giveKillStats` → `giveRankXP("kill")`
  (+`"headshot"`, which STACKS).** This does **not** go through `level.onPlayerKilled`, so our hook is
  irrelevant to it — restoring a non-zero `registerScoreInfo("kill", …)` is the whole fix.
- **Assists, captures, defends: DEAD.** They route through `_globallogic_score::givePlayerScore`, whose
  first line is `if ( level.overridePlayerScore ) return;` — and `gf.gsc` sets that true. So
  `givePlayerScore("assist", damager)` in `gf_onPlayerKilled` awarded **nothing** for the mod's whole life.
  Assist XP must call `_rank::giveRankXP( "assist" )` **directly**. The OT flag capture still pays no XP
  for the same reason (stock `capture` = 300 is unreachable).
- **Match bonus** (`win`/`loss`/`tie`) is a **scalar**, not flat XP:
  `scalar × (level.timeLimit×60 ÷ 60 × SPM) × timePlayedFrac`, where SPM = `(3 + (rank+1)×0.5) × 10`.
  ⚠ It is gated on `game["timepassed"]`, which `_globallogic_utils::gameTimer` only accrues while
  `!level.timerStopped` — and our round clock holds `pauseTimer()` all round
  ([[paused-timer-freezes-gettimepassed]]). So it may never fire. **Still unverified.**

**Two traps that cost time here:**
1. `logString()` output does **not** reach `games_mp.log` on this server (stock's own
   `logString("game ended")` has 0 hits in 36 MB / 19k games, while `logPrint` lines like `GF_POPUP`
   number 27k). So "no `xp <type>: N` lines in the log" proves **nothing** — don't use it as evidence.
   See [[read-the-server-not-the-file]].
2. XP values are **safe to be non-zero** even though score = damage: `overridePlayerScore` keeps them off
   the scoreboard, and the stock "+N" popup is suppressed by `self.enableText = false` per spawn, **not**
   by zeroed score info (the old comment in `_gf_rounds.gsc` claimed otherwise).

Current economy (2026-07-13, hardcoded in `gf.gsc onStartGameType`, 5× stock): kill **500**,
headshot **+500**, assist **100**, win/loss/tie **5 / 2.5 / 3.75**.
