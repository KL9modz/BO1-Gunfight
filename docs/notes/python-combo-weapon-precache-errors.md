---
name: ""
metadata: 
  node_type: memory
  originSessionId: c987423e-184e-4957-9b88-adbb55e5a2cf
---

The 4 console errors at "------- Game Initialization -------":
`python_speed_snub_mp`, `python_acog_snub_mp`, `python_acog_speed_mp`, `python_acog_speed_snub_mp`
are **engine-emitted before any mod GSC loads** (they print above `mp_spawn_fix.gsc loaded`), so they are NOT caused by the gunfight mod.

Root cause: a stock Black Ops data gap. `mp/attributesTable.csv` lists python's attachments as `acog dw snub speed`. The engine precaches the dual-/triple-attachment (Warlord) combinations of the non-dw sight attachments {acog, snub, speed}, but python (a revolver) has **no combo weapon files** — only single variants exist (`python_acog_mp`, `python_snub_mp`, `python_speed_mp`, `pythondw_mp`). Every other weapon's combos live in the base fastfiles, so only python errors. Would occur in stock BO1 too whenever those combos get precached.

No GSC fix is possible (precache runs before scripts). Fix applied: created 4 stub weapon files in
`S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\raw\weapons\mp\`
as byte copies of `python_mp` (Plutonium loads loose raw weapon files; a valid file satisfies the precache). They are never equipped — our pool only gives `python_mp`/`pythondw_mp`, and the CAC UI can't put two attachments on a revolver — so the copied content is irrelevant beyond "valid weapon that parses".

Caveats:
- These stub files live in the **game raw folder, outside the mod git repo** — they vanish on a Steam "verify files" / reinstall and must be recreated. They are not gunfight-specific (base-game scope).
- Needs an in-game console check after `map_restart` to confirm Plutonium's loose-rawfile loader picks them up at the pre-GSC weapon precache.

Related: [[special-weapons-precacheitem-and-camo]] (minigun/M202 need PrecacheItem because they're absent from the normal weapon table — a different precache failure class).
