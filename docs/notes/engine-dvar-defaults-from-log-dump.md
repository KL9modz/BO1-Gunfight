---
name: engine-dvar-defaults-from-log-dump
description: "How to read an engine dvar's TRUE default and tell a real engine dvar from a cfg-created ghost — the dvar dump in console_mp.log (REGISTERED DEFAULTS, not live values), and the \"Domain is ...\" field"
metadata: 
  node_type: memory
  type: reference
  originSessionId: efc84dea-3422-4233-a328-595e97be17f7
---

Two cheap tests that settle "is this dvar real, and what is its actual default?" — the questions that
otherwise get answered by guessing.

## 1. The dvar dump in `console_mp.log` prints REGISTERED DEFAULTS, not live values

**Every value in that dump is the engine-registered default**, never the configured value. Proven by the
divergences: dump `g_inactivity 190` vs cfg 300, dump `sv_maxclients 4` vs cfg 14, dump
`sv_connectTimeout 80` (engine default) while no cfg sets it, dump `g_fix_entity_leaks 1` vs cfg 0.

⚠ It is **not** simply "a boot dump that runs before the cfg" — that was the first guess and it is wrong.
The dump is re-emitted at **every map load**, and still prints the default on load #5 of a long-running
server, where any cfg value has obviously been in force for hours. So it is dumping reset-values.
Practical upshot either way: **read defaults from it, never live values.** For live values use the panel's
`/api/dvars?fresh=1` or a direct RCON query, per [[read-the-server-not-the-file]].

This makes it the ground truth for **engine** dvar defaults, and the way to prove a dvar is genuinely
registered by the engine rather than conjured by a cfg `set` line. A dvar present in the *pre-cfg* dump
is registered by the binary. Corollary: a dvar that is registered in the MP dump **is an MP dvar**, no
matter what the changelog says — `g_fix_viewkick_dupe` is documented by Plutonium as an SP addition but
is plainly in the MP table (as is its neighbour `g_fix_damageKickReductionPerk`, which reads `1` and
which **no cfg on the box sets** — nothing but the engine could have put it there).

## 2. The `Domain is ...` field discriminates code-registered from script/cfg-created

Query a dvar over RCON and read the tail:

| Reported domain | Means |
|---|---|
| `Domain is any number from 0 to 10` / `Domain is 0 or 1` | **Code-registered** — real type + range, and `default:` is the true registered default |
| `Domain is any text` | **Script/cfg-created** (a GSC `setDvar` or a cfg `set` on a name the engine never registered) — it is a STRING, and its `default:` is meaningless |

⚠ For a script-created dvar the `default:` field **just mirrors the last value set**. That is why
`scr_gf_flinch` reported `is: "1.2" default: "1.2"` — nothing had "defaulted" to 1.2, someone had *set*
it to 1.2 and the default followed. Never read a mod dvar's intended default off the server; read it
from the `gf_cfgFloat( name, def, lo, hi )` call site in GSC.

Together these tell you whether a dvar you are about to set will do anything at all. A cfg `set` on a
name the engine does not register happily creates a user dvar that looks legitimate in every dump and is
read by nothing — a silent placebo.

Extends [[read-the-server-not-the-file]] (a cfg is an INTENTION, the process is REALITY) with: *and the
pre-cfg dump is the third thing — the engine's own opinion, before either of them.* The complementary
trap where a dvar IS real but does not replicate to clients is [[flinch-bg-viewkickscale-not-replicated]]
(`bg_*` = shared/predicted → client-side; `g_*` = server game module).
