---
name: cheat-protection-is-client-side-rcon-can-set
description: "PROVEN LIVE: an rcon / dedicated.cfg `set` on a DEDICATED server writes cheat-protected dvars fine (sv_cheats 0 and all). The 'is cheat protected' boot spam comes from a game CLIENT, not a server. Corrects a wrong claim that was baked into _gf_bridge.gsc + CLAUDE.md"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 8820abef-a139-4510-90c7-65471fddf2da
---

**Cheat protection (`DVAR_CHEAT`) is enforced CLIENT-side.** A **dedicated** server's own console — rcon
**and** `dedicated.cfg` — is **not** gated by it. So `jump_height`, `jump_slowdownEnable`, `bg_gravity`,
`g_speed`, `bg_fallDamage*`, `ragdoll_*`, `timescale` are all writable over plain rcon on the VPS with
`sv_cheats 0`.

## The proof (VPS, 2026-07-12, `sv_cheats` 0, `dedicated` = "dedicated internet server")
- `set ragdoll_explode_force 18001` — a dvar on the engine's **own** cheat-protected refusal list — read
  back as **18001**, then restored to 18000. The write **took**.
- Control, same session: `set bg_gravity 0` (domain is "1 or bigger") **echoed** `'0' is not a valid value
  for dvar 'bg_gravity'` and kept 800. So **error echoes DO reach the panel** — which is what makes the
  *silence* on the accepted writes mean "accepted", not "reply swallowed".

## Where the misconception came from (and why it was so convincing)
The famous boot spam — `Error: jump_height is cheat protected`, ditto `bg_fallDamageMinHeight`,
`cg_drawCrosshair`, `ragdoll_explode_force` — is printed by a game **CLIENT** exec'ing the stock
`default_xboxlive.cfg` (it is in the CLIENT's `console_mp.log`, right before `scr_xpscale is read only`).
It is **not** a server refusing an admin. Reading it as one produced a whole wrong theory, a wrong "fix"
(routing the panel's Jump Height + Fall Damage rows through the `svset` bridge to dodge a gate that does
not exist), and a wrong rule written into `CLAUDE.md` — all of it reverted.

The other seed: `_gf_bridge.gsc` claimed rcon `set bg_viewKickScale 0.9` was "verified refused on a
dedicated-equivalent round". That was almost certainly a **listen host**, where the panel's rcon lands on
a console that IS a client's — which is exactly the case where the flag *does* bite.

## The rule that actually holds
The check fires wherever the console belongs to a **client**:
| write path | cheat-gated? |
|---|---|
| rcon → **dedicated** server | **NO** — writes fine |
| `dedicated.cfg` on a dedicated server | **NO** — writes fine |
| GSC `setDvar` | **NO** (stock `_globallogic` uses it: `setDvar("jump_slowdownEnable", 0)` for oldschool) |
| a **player's** console / a client exec'ing a cfg | **YES** |
| `setClientDvar` **arriving** at a client (the `r_*` Visual Tweaks) | **YES** — unrescuable from the server |
| rcon → **listen** host (host's console is a client's) | **YES** |

**What is genuinely unreachable on a dedicated server** — and the ONLY thing worth greying out in the
panel — is a cheat-protected **CLIENT** dvar (`r_*`), plus **archived** client dvars (`cg_fov`,
`bg_viewBobAmplitudeBase`) that Plutonium blocks server writes to. See
[[rcon-dedicated-dvar-push-limits]].

Consistent with [[getdvarint-on-enum-dvar-broke-cheat-guard]], which already concluded cheat protection is
enforced client-side — that memory was right and this one is its live confirmation on the write path.

## Method note (reusable)
To classify a dvar against a **live** server without changing anything, you cannot just write its own
value back — "refused" and "accepted" both leave it unchanged. Either (a) rely on the error echo (a
cheat-protected dvar echoes the refusal *even when the value is identical*), or (b) change it to a
distinct value, read back, restore — using a dvar that cannot affect a live match (`ragdoll_explode_force`
is ideal). **Always include a control** whose answer you already know; mine (`jump_height`) is what
exposed the broken inference instead of shipping it. Per [[read-the-server-not-the-file]].
