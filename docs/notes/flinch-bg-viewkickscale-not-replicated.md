---
name: flinch-bg-viewkickscale-not-replicated
description: "Flinch appeared broken on the VPS: bg_viewKickScale does NOT replicate to clients — each client scales its own damage view kick from its LOCAL copy, so the server setDvar changed nothing. Fixed 2026-07-11 with a per-client setClientDvar push. Listen hosts masked it (host IS a client)."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8176b57d-55bb-47ac-84c3-d613496c6ee2
---

`scr_gf_flinch` → `bg_viewKickScale` (0.2 × mult) looked like it worked from RCON but players still
flinched on the dedicated VPS. Root cause: **`bg_viewKickScale` is not a replicated dvar.** The damage
view kick is scaled **on the client, from the client's own local copy**. A server-side `setDvar` sets
only the server's copy, which nothing reads.

Proof (2026-07-11, live VPS): `rcon bg_viewKickScale` → `0`, while the in-game client console on the
same server read `0.2`. Setting `bg_viewKickScale 0` by hand in the client console killed the flinch.

**Why it was believed to work:** it does — on a **listen host**, where the host process is both server
and client, so the server-side `setDvar` lands on the only client that matters. Classic listen-vs-
dedicated mask; see [[rcon-dedicated-dvar-push-limits]] for the same trap in the `r_*` family.

**Fix** (`_gf_rounds.gsc`): keep the server-side `setDvar` (so server reads stay truthful) and add a
per-client push.
- `gf_applyFlinch()` loops `level.players` and `setClientDvar`s every human — covers a live RCON change.
  (No-op when called from `onStartGameType`: `level.players` is empty there.)
- `gf_applyFlinchClient()` pushes on spawn — covers new rounds and late joiners. The push is now
  **unconditional** (no skip-at-stock shortcut): a player running `bg_viewKickScale 0` in their own
  autoexec would otherwise take zero flinch while everyone else takes the full kick, so the per-spawn
  push is what keeps the server's value authoritative.

`bg_viewKickScale` is **not** a saved client dvar (absent from `config_mp.cfg`), so the push is
session-only and can't corrupt a player's config the way `r_gamma` would.

**Open question:** whether the dvar is cheat-protected on the client. The push works today, but the VPS
currently runs `sv_cheats 1` (the unstripped dev block — [[package-server-does-not-strip-markers]]). If
that ever gets fixed, re-verify flinch still lands; if it doesn't, the push was riding on sv_cheats.

**General lesson:** before assuming a server-side `setDvar` reaches players, read the dvar from BOTH
sides — `rcon <dvar>` and the in-game client console. A mismatch means it doesn't replicate.
