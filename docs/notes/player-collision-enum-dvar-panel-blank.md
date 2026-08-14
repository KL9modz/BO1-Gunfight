---
name: player-collision-enum-dvar-panel-blank
description: "Player collision (g_playerCollision/g_playerEjection) is a real Plutonium ENUM dvar — written by index, read back as a NAME — so the RCON panel's 0/1/2 dropdown goes blank on every read and Set All / Save silently skip the row, which reads as \"the server keeps resetting it\". The live write actually sticks; only a server restart (cfg re-exec) reverts it."
metadata:
  type: project
---

**Symptom (2026-08-13):** "player collision — I want it off by default, I'm not sure if it works from
the RCON or if it's just resetting."

**Three separate facts, and only the last one is a real reset:**

### 1. The dvars are REAL on Plutonium T5 (an old note guessed they weren't)
`rcon-connect-sweep-unknown-cmd-spam.md` listed the whole GAMEPLAY panel section
(`g_playerCollision` / `g_playerEjection` / `g_patchRocketJumps` / …) as "looks T6/BO2-derived and
likely doesn't exist on T5". **It does exist** — it is a *Plutonium* runtime registration, not a
Treyarch one, which is why it is absent from the `raw/` dump and from `BlackOpsMP.exe`. The strings
live in `plutonium-bootstrapper-win32.exe`:

```
everybody . enemies . nobody
Who player collision applies to . g_playerCollision
Who player ejection applies to  . g_playerEjection
Speed at which to push intersecting players away from each other . g_playerCollisionEjectSpeed
```

Corroborating: neither name is in the panel's dead-dvar cache (`tools/rcon/.dvarcache.json`) for
either profile, i.e. both answered the connect sweep with a value instead of `Unknown cmd`.

### 2. It is an ENUM: written by INDEX, read back as a NAME — this is the "resetting" illusion
`set g_playerCollision "2"` works (an index is accepted — the cfg's `"0"` provably lands as
`everybody`), but a read returns the **string** `nobody`. The panel row is
`type:'sel'` with option values `0`/`1`/`2`, and `srvApplyValues` does a bare `el.value = val`:

- `select.value = "nobody"` matches no `<option>` → **`selectedIndex` becomes -1 → the row renders
  BLANK**, so every ↻ Read / connect sweep wipes the visible setting.
- `_rowVal` then returns `null` for that empty select, and both `setAllInBlock` and
  `collectBlockDvars` guard on `v !== null` → **Set All and 💾 Save silently SKIP the row**, so it
  never persists to `dedicated.cfg` either.

The write itself was always fine. **Fix:** an optional `rmap` (name → option value) on the var def,
applied in `srvApplyValues` before the control is written. Unknown strings fall through unchanged.

### 3. The only genuine reset is a SERVER RESTART re-execing dedicated.cfg
Proven from one continuous `console_mp.log` on the live VPS (the log rolls at restart, so head =
this process's boot; the per-round dvar dump gives a free timeline):

| where | `g_playerCollision` |
|---|---|
| head, first dump after `execing dedicated.cfg` | `"everybody"` (the cfg's `set … "0"`) |
| tail, ~2 days and hundreds of rounds later | `"nobody"` |

So a live panel/rcon write landed, took effect, and **survived every `map_restart` since**. Nothing
in mod GSC writes either dvar (`grep` is clean) — there is no in-game writer to fight. The cfg is the
whole story: it re-applies at every boot, which is what silently undid earlier experiments.

**Resolution:** `dedicated.cfg` (box) + `server/dedicated.cfg.example` now ship
`g_playerCollision "2"` **and** `g_playerEjection "2"` — ejection is the other half, or overlapping
players still get shoved apart. Cfg-owned on purpose (same class as the `g_fix_*` family: a
Plutonium engine dvar with no GSC writer). A GSC-owned `scr_gf_*` version — re-applied per round like
`gf_applyJumpFatigue` — is the alternative if the public build should also default to collision off.

⚠ **Panel `def:` stays `'0'`** (the engine's own default), so right-click → *Reset to default* still
means "engine default", consistent with every other row. The GF default lives in the cfg.

## Side finding: the per-round dvar dump prints LIVE values, not registered defaults
[[engine-dvar-defaults-from-log-dump]] states the `console_mp.log` dump is "registered defaults,
never live values". **On the live VPS today it is the opposite** — the first dump sits *after*
`execing dedicated.cfg` and reports the cfg's values: `g_inactivity "300"` (engine default 190),
`sv_maxclients "14"` (4), `sv_timeout "240"`, `sv_connectTimeout "200"`, `bot_difficulty "fu"`, and
decisively `g_gametype "gf"` and the GSC-seeded `scr_gf_flinch "0.5"` — neither of which has any
registered default that could read that way. The old note's practical use survives (**the dump proves
a name is registered at all**), but do not read a dump value as a default: for that, use a live rcon
read's typed `Domain is …` / `default:` fields.
