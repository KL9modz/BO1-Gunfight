---
name: player-sprintunlimited-one-way-connect-push
description: "player_sprintUnlimited is a CLIENT dvar whose only stock push is at connect and is ON-only — a bare `set` reaches nobody already in the server and can NEVER turn it back off"
metadata: 
  node_type: memory
  type: project
  originSessionId: 64483136-c98d-4fdd-bd43-6b4fb231dc02
---

Reported 2026-07-12 as "unlimited sprint turned off when it switched from small to large mode."
**The mode switch was a red herring** — nothing in the mod links team-size mode to sprint, and at the
time nothing in the mod's GSC read or wrote `player_sprintUnlimited` at all. The RCON panel toggle was
a raw `sdvv('player_sprintUnlimited', …)`, i.e. a bare rcon `set` on the **server's** copy.

**`player_sprintUnlimited` is a CLIENT dvar** — the `player_*` family is client-predicted movement, the
same ownership class as `bg_*` (see [[flinch-bg-viewkickscale-not-replicated]]), **not** the replicated
`jump_*` family (see the jump-fatigue contrast in CLAUDE.md). The server's copy replicates to nobody.

In all of stock MP GSC there is exactly **one** place a client ever receives it —
`_globallogic_player::Callback_PlayerConnect` (raw dump, ~line 103):

```gsc
if ( GetDvarInt( #"player_sprintUnlimited" ) )
    self setClientDvar( "player_sprintUnlimited", 1 );
```

Two consequences, and both bite:
- It fires **at connect only**. (It *does* re-run on `map_restart` — the `!isDefined(self.pers["score"])`
  guards wrapped around the stats blocks above it exist precisely because `pers[]` survives and the
  callback re-enters — so in practice it re-pushes each round. But a mid-match `set` still reaches nobody
  until the next round's restart.)
- It is **one-way**. Stock pushes `1` and never pushes `0`. So the engine can turn unlimited sprint **on**
  and can *never* turn it back **off**: a client handed a `1` keeps it for the rest of its session no
  matter what the server dvar later says. "Off" is only reachable if the mod pushes it.

That one-way, connect-timed push is the whole explanation for a toggle that "randomly stops working" /
applies to some players and not others.

**Fix (shipped):** own it exactly like flinch. `scr_gf_sprint_unlimited` (default 0 = stock) is seeded +
re-applied every round by `gf_applySprintUnlimited()` (`_gf_rounds.gsc`, called from `onStartGameType`),
which sets the **server** copy — the server's own movement sim reads it, and a client predicting unlimited
sprint against a server that limits it rubber-bands — and pushes it to every live human.
`gf_applySprintUnlimitedClient()` pushes it **per human, every spawn**. RCON bridge:
`sprintunlimited_<0|1>`; the panel row is now `data-dvar="scr_gf_sprint_unlimited"` + `bridge(...)`,
mirroring the Jump Fatigue row.

⚠ Unlike `gf_applyFlinchClient`, the per-spawn push has **no skip-at-stock shortcut**. Skipping the push
at 0 would strand any client that had been given a `1` earlier in the session at unlimited sprint forever
— nothing else in the game ever pushes it down.

**The general rule this is the third instance of:** before setting any dvar server-side, read its prefix.
`g_`/`sv_`/`scr_` = server. `bg_`/`cg_`/`player_` = client-owned — a server `set` is decoration unless you
`setClientDvar` it yourself. Prior victims: `bg_viewKickScale` (flinch) and `bg_viewBobAmplitudeBase`.
