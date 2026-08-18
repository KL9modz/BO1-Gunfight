---
name: load-screen-tips-connect-menu-fork
description: "The load-screen tip is dvar `didyouknow`, rendered by ui_mp/connect.menu and re-rolled by the engine at every map load from stringtable mp/didyouknow.csv. Both the pool and the MPTIP_* text sit in zones the client loads BEFORE mod.ff, so neither is overridable — forking the RENDERER is the only route."
metadata:
  node_type: memory
  type: project
---

**Shipped and confirmed in game 2026-08-18** (local listen host): Gunfight's own load-screen tips, via a fork of `ui_mp/connect.menu`.

## How stock does it (4 pieces, only one of them reachable)

1. **Selection** — the engine runs the UI command `selectStringTableEntryInDvar mp/didyouknow.csv 0 didyouknow`, which picks a random row from column 0 and stores it in the **client** dvar `didyouknow`.
2. **Pool** — stringtable **`mp/didyouknow.csv`**, 86 rows of `@MPTIP_*` references, in `zone/Common/code_post_gfx_mp.ff`. Siblings: `didyouknow_wager.csv` (12), `didyouknow_theater.csv` (13).
3. **Text** — the `MPTIP_*` localizedstrings, in `zone/english/en_code_post_gfx_mp.ff`.
4. **Renderer** — an itemDef in **`ui_mp/connect.menu`** bound to `dvar "didyouknow"`, sitting just under the loadbar (the white rule on the load screen IS the loadbar).

⚠ Do not confuse this with `maps/mp/_tutorial.gsc`, which drives the **`MPTIP_TRAINING_*`** set as a top-center HUD element during Combat Training, gated on `xblive_basictraining` + `bot_tips`. Different system, different strings.

## THE LOAD-ORDER RULE (the general finding, and the reason 2 of 3 routes are dead)

From a client's `console_mp.log`, one connect sequence:

```
896  code_post_gfx_mp     <- didyouknow.csv + MPTIP_*  (BEFORE mod)
946  mod                  <- our mod.ff
965  ui_mp                <- connect.menu             (AFTER mod)
999  common_mp / en_common_mp                          (AFTER mod)
```

**First registration wins; a later duplicate is discarded.** So a mod.ff asset can only override a stock asset whose home zone the client loads **after** `mod`:

| Home zone | vs `mod` | Overridable? | Evidence |
|---|---|---|---|
| `code_pre_gfx_mp`, `code_post_gfx_mp`, `patch_mp`, `plutonium_mp` | before | **NO** | `didyouknow.csv`, `MPTIP_*` |
| `patch_ui_mp`, `ui_mp`, `common_mp`, `en_common_mp`, map zones | after | **yes** | `ui_mp/main.menu`, `CGAME_SB_SCORE`, `CGAME_CONNECTIONINTERUPTED` |

⚠ This **qualifies [[stock-engine-string-override-via-modff]]**, which states flatly that a localizedstring in mod.ff beats the shipped-zone copy. That is true only for strings living in a zone loaded after `mod` — which the two we ship happen to be (`en_common_mp`). `MPTIP_*` is the counterexample: same technique, same file shape, silently discarded. **Check the home zone's load position before assuming any override will land.**

⚠ A string appearing in a pre-`mod` zone is **not** proof the asset lives there. `mp/gametypesTable.csv` shows up in `patch_mp` and `ui_mp`, but every one of those is menu `tableLookup` *text*, not the stringtable. The real asset carries its cell data immediately adjacent in the zone (as `didyouknow.csv` does in `code_post_gfx_mp`); a bare name with unrelated neighbours is a reference.

## Why the dvar push is also dead (the cheap route, killed by xref)

`setClientDvar( "didyouknow", ... )` cannot work: **the engine re-rolls the dvar at map load**, i.e. exactly when the load screen draws. The command is a string literal in `BlackOpsMP.exe` at file offset `0x61E0E0` → **VA `0xA1EEE0`**, `PUSH`ed from **4 call sites**, all in map-load/connect code:

| Site (file off) | Neighbouring literals | Path |
|---|---|---|
| `0x10f369` | `CM_LoadMapFromBsp`, `Server changing map %s, gametype %s` | map spawn |
| `0x184f9f` | `Bad specop level name`, `localhost` | level start |
| `0x409d50` | `%s.dm_%d`, `demos`, `timedemo` | demo start |
| `0x4747d0` | `Can't find map "%s"`, `openmenu popup_connectingtodwhandler` | client connect / map cmd |

Corroboration without any tooling: **stock tips visibly differ from one load screen to the next** in a single session. If selection only happened on a host's START MATCH click, they wouldn't. And the dedicated server never has the dvar at all — `didyouknow` appears **0** times in a 9.8 MB actively-written VPS `console_mp.log`, despite the per-`map_restart` dvar dump. It is client-only.

⚠ The menu call sites (`ui_mp.ff` / `patch_ui_mp.ff` / `frontend.ff`) are all **host-side START MATCH buttons**, which is misleading on its own — it was the basis for a wrong guess that the engine does not re-roll on join. The exe's 4 sites are the ones that matter.

## What we ship

- **`ui_mp/connect.menu`** — fork of stock, registered `menufile,ui_mp/connect.menu` in `mod.csv`. The diff vs stock is two hunks: a `#define` block, and the tip itemDef going from `type ITEM_TYPE_BUTTON` + `dvar "didyouknow"` to `type ITEM_TYPE_TEXT` + `exp text ( "@GF_TIP_" + string( GF_TIP_INDEX ) );`.
- **`GF_TIP_INDEX`** = `( int( milliseconds() / GF_TIP_PERIOD ) % GF_TIP_COUNT )`. `milliseconds()` is the **client's UI-realtime clock** ([[menu-milliseconds-client-local-no-per-round-event]]), so the tip **rotates every 4s (`GF_TIP_PERIOD`) while the load screen is up** — something stock cannot do (stock rolls once per load). The server pushes nothing and is not involved.
- **`localizedstrings/gf.str`** — `TIP_0` .. `TIP_16` (17 entries).

⚠ **The references are positional**: the text ref is built at runtime as `"@GF_TIP_" + index`, so they must stay a **gapless 0-based run** and `GF_TIP_COUNT` must equal the entry count. A gap renders a blank line, not an error.

⚠ `string()` of an integral value renders clean (`"3"`, not `"3.00"`) — relied on here, and proven by stock's own `execNow focusItem ( "valid" + string( localVarInt(ui_highlight) - ... ) )`, which would not resolve otherwise. Confirmed live. If it ever regresses, the zero-formatting fallback is N itemDefs each with a static `text` and `visible when( INDEX == n )`.

## Fork safety

`connect.menu` is `loadMenu`-ed by **stock** `ui_mp/code.txt` and by nothing of ours, so the `loadMenu` resolves to whichever copy registered first, i.e. ours. Same shape as the `main.menu` fork (stock `ui_mp/menus.txt` loadMenus that one). ⚠ **Never also `loadMenu` it from one of our own menufiles** — a menu registered in `mod.csv` AND loadMenu-ed by our own menufile double-registers and kills the ENTIRE menu system ([[build-stage-transitive-menu]]). `build_ff.ps1` handles staging over the stock modtools `raw/ui_mp/connect.menu` with its existing backup/restore pass; verify `raw/` came back (it reports `restored N stock file(s)`).

⚠ Reach is **retention, not acquisition** — only clients that already downloaded our `mod.ff` render this. And `mod.ff` is byte-identical between the dev and public builds, so these tips ship publicly too (same as `main.menu`'s gunfight.us block).
