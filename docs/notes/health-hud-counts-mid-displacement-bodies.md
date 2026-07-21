# Health panel showed "3 players / 300 HP" on a 2-human team (counted a mid-displacement body)

**Date:** 2026-07-20, live on the VPS: KL9 connected to Summit (`mp_mountain`); round 1 was
KL9 + a bot vs MrBeanDaddy + Burger6741, but the enemy health row read **3 skulls / 300 HP**.
**Status: FIXED** (`gf_getTeamHealthStats` exclusion).

## Mechanism

`gf_getTeamHealthStats` counted any client with `pers["team"] == team` and this round's
`gf_spawnedRound` stamp. A bot **being displaced** satisfies both for the ~1–2s its sequenced
suicide-park takes to settle (claimed → suicide → death settles → quiet reassign to spectator):
it spawned this round (stamped) and its `pers["team"]` still reads the team until the final
quiet reassign flips it.

At a **match start with humans loading in**, that window is exactly when new panels seed:
KL9's connect displaced a bot on each side, and his `gf_runHealthHUD` seeded while the enemy
side's roster was still Bean + Burger + a settling bot = **3 alive / 300**. (The 0.5s level
recompute + 0.1s per-player push-on-change loop correct the value as soon as the park settles —
the wrongness is transient server-side — but a panel seeded mid-churn shows it, and a player
glancing during the countdown reads a hard "3 v 2".)

## The fix

`gf_getTeamHealthStats` now also skips a body that is **on its way out of the round**:
- `.gf_displacePending` — claimed by the seat-priority displacer (cleared when the park
  settles or by the next boundary's `gf_clearAllMovePending` wipe);
- `pers["gf_parkPending"]` — marked for a deferred park.

Both are reconciler concepts only set in dev builds; in the public build the reads are never
true, so the exclusion is inert there (strip-safe: plain field reads, no calls).

## Rule

Any roster-shaped consumer (HUD stats, future scoreboard/telemetry counts) that keys off
`pers["team"]` must treat the displacement/park marks as "already gone" — the same convention
`gf_teamRosterCount` / `gf_pickDisplaceableBot` already follow. A body's `pers["team"]` lies
for the duration of a sequenced park.
