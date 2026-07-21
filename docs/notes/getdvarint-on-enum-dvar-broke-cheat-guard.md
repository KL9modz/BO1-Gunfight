---
name: getdvarint-on-enum-dvar-broke-cheat-guard
description: "getDvarInt(\"dedicated\") returns 0 on EVERY server type (it's an enum whose VALUE is a string) — this silently ran gf.gsc's dev-cheat block on the live VPS for months, forcing sv_cheats 1 + blanking g_password every round. Also: cheat protection is enforced CLIENT-side, not server-side."
metadata: 
  node_type: memory
  type: project
  originSessionId: d4323a1d-c57a-4192-a01d-829edb839a01
---

**`dedicated` is an ENUM dvar whose VALUE is a STRING** — `"listen server"` / `"dedicated LAN server"` /
`"dedicated internet server"`. `getDvarInt( "dedicated" )` cannot parse that, so it returns **0 on every
server type**.

`gf.gsc`'s dev-cheat block was guarded by `if ( getDvarInt( "dedicated" ) == 0 )`, with a comment
asserting "the ENGINE itself blocks this on any dedicated server". It never did. The block ran on the
live public VPS every round, **forcing `sv_cheats 1` and blanking `g_password`**. `sv_disableClientConsole`
was the only thing keeping cheat commands away from players. `g_password` could never be set at all —
the mod wiped it each round, which is why "password protect the server" silently did nothing.

Proof (2026-07-11, live VPS): rcon `set sv_cheats 0` → `fast_restart` → reads `1` again. `dedicated.cfg`
only executes at process start, so only GSC could be the re-setter, and gf.gsc:239 was the only writer
in the tree.

**Fixed** (commit 863374e): compare the string and **fail closed** —
`if ( getDvar( "dedicated" ) == "listen server" )`. Anything else gets no cheats, so a future Plutonium
relabel costs a listen server its dev cheats (annoying) rather than a dedicated server its safety
(catastrophic). Plus `gf_warnIfCheatsOnDedicated()` — a tripwire *outside* the strip markers, because
this guard failed **open and silent** for months. `set sv_cheats "0"` pinned in the VPS cfg.

**Rule: never infer server type with `getDvarInt`.** More generally — don't trust a numeric accessor on
a dvar whose type you haven't verified. Read it over rcon first; the echo shows the real value + domain.

## Cheat protection is enforced CLIENT-side, not server-side

Verified the same night, and it reframes the whole "works on listen, not on VPS" class of bug:

- **Listen server** (`sv_cheats 0`): rcon `set bg_viewKickScale 0.9` → `^1Error: bg_viewKickScale is
  cheat protected`. Refused.
- **Dedicated VPS** (`sv_cheats 0`): the *identical* command **succeeds**.

A dedicated server has no client, so nothing enforces the flag on its own copy — but the write is
**meaningless**, because `bg_viewKickScale` doesn't replicate. To reach a client you must
`setClientDvar`, and then the **client** applies its own cheat check on arrival. Server-side authority
cannot bypass that. This is why the `r_*` Visual Tweaks fail on the VPS *even though `sv_cheats` was 1
there*. See [[rcon-dedicated-dvar-push-limits]] — its 3-class model was built on the false premise that
the VPS had cheats off, and needs re-deriving.

**GSC `setDvar` IS free of the gate** (proven: rcon `set bg_viewKickScale 0.9` refused on listen while
the bridge's `flinch_2` verb wrote that same dvar to 0.4 in the same round). That's why the panel's
cheat-protected **server** dvars now route through the `svset_<dvar>=<value>` bridge verb. It does NOT
rescue cheat-protected **client** dvars — nothing can.

⚠ **Still unproven:** whether a client accepts a `setClientDvar`'d cheat-protected dvar. This decides
whether flinch (`bg_viewKickScale`, pushed per-client since it doesn't replicate) works on a dedicated
server *at all*. Test: dedicated server + real client, read `sv_cheats` and `bg_viewKickScale` in the
client console. If client `sv_cheats` reads 0, it doesn't replicate → the push is refused → flinch is
decorative on the VPS.

Related: [[t5-tweakable-override-dvars-live]], [[package-server-does-not-strip-markers]] (which flagged
the VPS shipping this dev block live — the `dedicated` guard was the supposed mitigation).
