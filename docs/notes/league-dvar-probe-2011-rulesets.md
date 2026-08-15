---
name: league-dvar-probe-2011-rulesets
description: "Live-probed (2026-08-14, panel rcon) the stock dvars BOCL's rulesets.gsc set from the 2011 ESL/CEVO/ClanBase configs. Two classes: 7 engine-registered (typed domains - the voice family, sv_zombietime, g_redCrosshairs, g_allow_teamchange, sv_disableClientConsole) and 11 string-typed tweakables (the scr_team_fftype class). All at engine defaults except sv_disableClientConsole 1 = our own deliberate console block - which also means player console advice only works from the MAIN MENU, and menus are the only in-game client-exec channel on our server."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0206234e-9e40-5448-9815-c6fbd96d8e2d
---

`Classixz/bo1-competitiveleaguemod`'s `rulesets.gsc` transcribes the **actual 2011 ESL /
CEVO / ClanBase configs** (source URLs cited in its header) — a catalog of stock
competitive dvars this repo had never touched. All of them live-probed on the VPS
2026-08-14 through the panel (the [[read-the-server-not-the-file]] rule; a raw dump line
proves nothing — [[engine-dvar-defaults-from-log-dump]]).

## Engine-registered (typed domain = real registration)

| dvar | live | default | domain | disposition |
|---|---|---|---|---|
| `sv_disableClientConsole` | **1** | 0 | 0/1 | **Ours, deliberate** — see below |
| `sv_voice` | 1 | 1 | 0/1 | Voice master is ON server-side |
| `voice_global` | 0 | 0 | 0/1 | cfg sets 0 |
| `voice_deadChat` | 0 | 0 | 0/1 | Panel candidate (dead-talk toggle) |
| `g_voiceChatTalkingDuration` | 500 | 500 | 0-10000 | catalog only |
| `sv_zombietime` | 2 | 2 | 0-1800 | disconnected-slot linger; catalog only |
| `g_redCrosshairs` | 1 | 1 | 0/1 | Panel candidate (enemy-red crosshair) |
| `g_allow_teamchange` | 1 | 1 | 0/1 | ⚠ leave alone — our team system wraps the menu handlers itself; a 0 here would fight `gf_team_switch` at a layer we don't control |

## String-typed tweakables (`Domain is any text`, default == value)

`scr_game_perks` (1), `scr_game_killstreaks` (1), `scr_game_hardpoints` (1),
`scr_disable_attachments` (0), `scr_game_spectatetype` (1), `scr_game_allowkillcam` (1),
`scr_player_sprinttime` (4), `scr_player_forcerespawn` (1), `scr_weapon_allowrpgs` (1),
`scr_weapon_allowc4` (1), `scr_team_kickteamkillers` (0).

These read exactly like **`scr_team_fftype`** — the proven-live tweakable class
([[t5-tweakable-override-dvars-live]]): string-typed, registered by the stock tweakables
system, consumed engine/stock-GSC-side (BOCL's stock-derived fork shows only *setters*;
the consumers are in files it didn't fork). ⚠ The string type means the probe cannot
distinguish "live tweakable" from "inert" per-dvar — the FF precedent argues live, but
each one needs a behavior test before the panel exposes it. Dispositions:

- **`scr_player_sprinttime`** — the interesting one: base sprint seconds (stock 4), the
  *duration* lever next to our `scr_gf_sprint_unlimited` on/off. Panel candidate after a
  live test.
- **`scr_game_perks`** ⚠ HAZARD, never set 0: our whole loadout identity is SetPerk-driven
  (9 base perks + packages). If the engine gates perks on it, 0 silently deletes the mod's
  perk layer. There is no upside — we already control perks per-spawn.
- `scr_game_killstreaks` — redundant belt to our `level.killstreaksenabled = 0`; harmless,
  not worth a row.
- `scr_disable_attachments` — likely CAC-layer only (our gives bake attachments into
  weapon names); irrelevant to gf, maybe relevant to a future stock-CAC alt mode.
- `scr_game_spectatetype`, `scr_game_allowkillcam`, `scr_weapon_allow*`,
  `scr_team_kickteamkillers`, `scr_player_forcerespawn` — catalog only; our own systems
  already own these behaviors (killcam, one-life, loadout-controlled equipment, FF policy).

## The one non-default: our own console block, and what it implies

`sv_disableClientConsole 1` is set by `dedicated.cfg:31` **on purpose** (panel row
"Block Player Console", [[getdvarint-on-enum-dvar-broke-cheat-guard]] — it is the line
between players and cheat-protected commands on a public lobby). Two consequences this
probe surfaced that were never written down:

1. **Every "player types X in their console" remedy is MAIN-MENU-ONLY on our server** —
   the killfeed retiming (`con_gameMsgWindow0MsgTime`), `cg_fov`, `cl_maxpackets`. All are
   `seta`-archived so main-menu-set values persist into the session, and
   `docs/GETTING_STARTED.md` already frames setup as back-out-to-menu — consistent, but
   the killfeed advice in CLAUDE.md said "in their console" unqualified.
2. **Menus become the ONLY in-game client-exec channel on our server** — which raises the
   value of the menu-`execNow` experiment ([[bocl-readyup-timeout-execmenu-designs]]):
   `sv_disableClientConsole` blocks the player *typing*, not a menu *executing*.
