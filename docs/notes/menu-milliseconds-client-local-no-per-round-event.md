---
name: menu-milliseconds-client-local-no-per-round-event
description: "menu milliseconds() is the CLIENT's UI-realtime clock (not server cg.time) → the server cannot stamp a menu animation marker; and an always-loaded loadMenu HUD has no per-round client-side event to stamp one locally → the \"free\" menu-owned loadout slide animation is NOT viable"
metadata: 
  node_type: memory
  type: project
  originSessionId: f989054e-7946-4a16-9216-83dfce41fde1
---

Settles the long-open CLAUDE.md question "is the menu clock server-synced `cg.time` so the server can
stamp the loadout slide-out marker?" — investigated 2026-07-15 **without a `mod.ff` rebuild** (the probe
the file proposed is unnecessary; the raw dump proves it).

**Three findings, in order:**

1. **`milliseconds()` in a menu `exp` is the CLIENT's local UI-realtime clock, NOT server `cg.time`.**
   Proof: `raw/ui/main.menu:256` scrolls a fog background with `milliseconds() % FOG_SCROLL_TIME` — and the
   **main menu renders before any server connection exists**. A server-synced clock could not drive that.
   → The server has no handle on the client's UI clock, so it **cannot** push an animation start-marker in
   any base the menu reads. The CLAUDE.md's hoped-for "good branch" (server stamps marker in its `gettime()`
   base → trivial) is **dead**.

2. **The stock marker is ALWAYS stamped client-side, from a menu-open event.** `raw/ui_mp/game_summary.menu`
   (`popup_summary` menuDef) and `after_action_report.menu` fire `exec "setdvartotime ui_time_marker"` inside
   `onOpen`, then itemDefs read `(milliseconds() - dvarInt(ui_time_marker)) / SPEED` as the animation fraction.
   Marker and read share the one client clock — that IS the mechanism. `setdvartotime` is a client UI exec.

3. **Our loadout overview has NO per-round client-side event.** It lives in an always-loaded `loadMenu`'d HUD
   menu (`ui_mp/hud_gf_health.menu`), so its `onOpen` fires once at HUD load, not per round. The menu event
   vocabulary has no `onDvarChanged` / "on item shown" hook (`raw/ui/menudefinition.h`), and the only
   server→client menu-open trigger is `openMenu` — which is **interactive and steals input focus** (every
   stock `openMenu` in `raw/maps/mp` is a change-class / team-select / endgame / wager-side-bet menu at a
   spawn/dead/menu moment). Firing it every round to stamp a marker would grab the cursor mid-firefight.

**Conclusion:** the "free" (zero reliable-command) menu-owned loadout slide is **not achievable** without
disrupting gameplay. The GSC dvar-animation stream (`gf_slideLoadout`, ~13 reliable cmds/human/round) stays —
and that's fine: it fires ~8s into the round, mid-gameplay, NOT in the `map_restart(false)` lobby-START stall
where the reliable-command overflow actually bites (needs a burst AND a frozen client), so it is a *purity*
cost, not a live-problem cost. If the count ever must drop, the cheap lever is to coarsen the animation
(step 0.05→0.1s halves it; shorten 0.5→0.3s) — the fade masks the coarser stepping — not to chase the menu.

⚠ Do NOT re-open this as "unverified" and burn a `mod.ff` rebuild on the `milliseconds()`-vs-`gettime()`
probe — `main.menu` already answered it. See [[server-command-overflow-reliable-command-budget]],
[[menu-rendered-loadout-overview]].
