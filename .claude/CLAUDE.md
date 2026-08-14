# mp_gunfight — Black Ops Gunfight for Plutonium T5 (Black Ops 1 MP)

A standalone **Gunfight** gametype (`gf`) for Call of Duty: Black Ops 1 on Plutonium T5. Two teams,
a **shared loadout that rotates every other round**, one life per round, no killstreaks/regen/drops.
Time expires → most-remaining-health wins the round (or capture the overtime flag). First to **6 round
wins** takes the match.

> This file is the agent operating manual: goal, current architecture, the load-bearing engine
> knowledge, and an organized TODO. It intentionally **summarizes and points** rather than duplicates —
> exhaustive per-function / per-dvar detail lives in `docs/`, and hard-won single-incident findings
> live in `docs/notes/` (one file per finding + a `README.md` index; a `[[slug]]` reference resolves to
> `docs/notes/<slug>.md` — open it for depth). Keep this file present-tense: update behavior in place; do
> not append dated "FIXED …" changelog notes (that history is in `git log` and `docs/notes/`).

---

## TODO

- Migrate to new host
- Map/mode vote
- Website screenshots
- Add more fun mods from other mod menus
- Create alt modes: Team Sharpshooter, Team Gun Game
- **Retail-Steam BO1 port: CLOSED 2026-08-14 — the working server binary is unobtainable, and the
  one person who could ask already did and was refused.** Answered directly by **Classixz**
  (`Classixz/bo1-snife`): ZAM still runs **through GameServers.com**, who were the **SOLE provider**
  of BO1 dedicated servers (renting from them was "essentially the only way") and **stopped selling
  new BO1 servers ~2022**. Decisively: **the files circulating online are the ~2010 leak, while the
  build GameServers actually runs is 2011** — a later, different binary that has **never leaked** —
  and the files cannot be downloaded from them, because when the orders stopped Classixz asked them
  to release the server files and **they declined**. ⚠ **Do not re-run this research and do not
  re-ask Classixz**; the obvious ask has been made and refused. The old framing ("the ONLY open
  question is which `CoDMPServer.exe` build") is therefore answered the unhelpful way: the build that
  works is the one nobody outside GameServers has, and the 2010-vs-2011 gap is also the likeliest
  root of the leak's documented `Exceeded limit of 256 'stringtable' assets` failure (it is a year
  older than the retail assets it is being pointed at — and ours *adds* a stringtable). The surviving
  modded servers are grandfathered GameServers boxes (ZAM's `173.199.76.204` RDAPs to GameServers.com, Toronto), <!-- ip-ok: third-party public game-server address; the RDAP literal IS the evidence for the grandfathered-box finding -->
  which is now explained rather than merely observed: they predate the ~2022 cutoff.
  **What stays true and proven** (keep it — it is real knowledge if the situation ever changes, and
  it cost real work): the whole mod stack runs on retail. Unranked servers auto-deliver `mod.ff` +
  `.iwd` to vanilla clients over the stock HTTP redirect
  (`sv_allowDownload`/`sv_wwwDownload`/`sv_wwwBaseURL`, laid out `<baseURL>/mods/<fs_game>/`;
  Treyarch's own Steam RCON tool, appid 42720, exposes those four dvars in its **unranked** settings
  manifest and **not** the ranked one); custom gametypes register exactly like ours
  (`stringtable,mp/gametypesTable.csv` + `rawfile,maps/mp/gametypes/<gt>.txt` +
  `menufile,ui_mp/hud_<gt>.txt` + a line in `maps/mp/gametypes/_gametypes.txt`); custom `.menu` files
  and custom weapons work; and **GSC stays loose** (snife's `mod.csv` lists no `.gsc` — scripts run
  server-side out of the mod folder, clients never get them). ⚠ **`BlackOpsMP.exe` is client-only —
  tested locally 2026-08-14**: args reach the engine (`r_fullscreen 0` applied) but `dedicated`/
  `net_port`/`logfile` are silently ignored, no log is written, and it comes up as a client on UDP
  3074. The leak's two builds (**`CoDMPServer_s.exe`** secured/ranked, wants `dw_licensefile` +
  `sv_licensenum` and dies on `Dedicated server authentication failure` — the "BO1 needs a Demonware
  licence" everyone repeats — vs plain **`CoDMPServer.exe`**, whose failure is the *asset* one above)
  are both moot now: both are the 2010 leak. **The only remaining retail path is acquiring a
  grandfathered GameServers box from someone winding one down** — untested, probably against their
  ToS, and it buys a rented server on a dead product line. Not worth pursuing. **We stay on
  Plutonium.** The clean-legitimacy alternative remains BO3 (first-party dedicated server tool +
  Workshop delivery) at the cost of a T7 rewrite. ⚠ And note what retail would have *cost* even if it
  had worked, which is the strongest argument this was never the bargain it looked like: no XP
  (unranked grants none, voiding the `registerScoreInfo` tuning) and no `g_fix_*` engine fixes — the
  bullet-damage dupe and the weapon-switch entity leak both bite this mod hard, and both were
  deliberate opt-ins.

### Open bugs
- **RESOLVED — "auto-balanced → forced to choose a class/team, couldn't spawn" (YooDyl `mp_silo`
  2026-07-19, basscar101 `mp_villa` 2026-07-20).** Root-caused off the first `gf_trace_teams 2` live
  capture (`GF_TEAMTRACE: human basscar101 axis -> allies by quietset (at boundary-out, round 8)`) —
  the mover was the mod's own balancer, and the block was **`gf_quietSetTeam` clearing `pers["class"]`**:
  stock's re-begin auto-spawns a team-assigned player only if `isValidClass(pers["class"])`
  (`_globallogic_player.gsc:386`), and its else-branch `showMainMenuForTeam()` (`:392`) — unlike
  `beginClassChoice` — **ignores `scr_disable_cac`** and unconditionally opens the class menu. Fixed:
  quiet moves to a real team now assign `level.defaultClass` (exactly what `beginClassChoice` would do
  under disable-cac) in `gf_quietSetTeam` (the bridge routes through it — its old mirror
  `gf_forceTeamQuiet` was folded in by the tier1 refactor); `gf_botQuietSetTeam`
  deliberately untouched (BotWarfare drives bot class/spawn — demonstrably fine). ⚠ Rule: **any quiet
  team write to a real team must leave `pers["class"]` valid** or its target blocks at the next re-begin.
  `GF_TEAMWATCH`/`GF_RECLAIM` at 0 lines proved the player was never in spectator, killing the old
  spectator-strand theory for these reports. ([[quiet-team-move-cleared-class-blocks-respawn]])
- **Bot mis-seater — reattributed: the "UNTRACED" writes are (mostly) unstamped STOCK menu/autoassign
  paths, not a C-side engine writer.** The every-re-begin `GF_TEAMTRACE: UNTRACED bot <name> spectator ->
  <team> - last stamp NONE …, at pre-spawn` noise is parked bots hitting the re-begin team menu
  (`:365`) and **auto-responding** (test clients answer menus), landing in `gf_menuTeamChoice`'s bot
  passthrough → **stock** handlers, which write `pers["team"]` untokened. The first UNTRACED **human**
  capture (KL9, `mp_hanoi` 2026-07-20) was the same family: Auto Assign → `gf_autoJoinBalance`'s
  balanced-split **stock fallback** (`menuAutoAssign`, untokened). Both are now stamped —
  **`stockmenu`** (bot/demo menu passthrough) and **`stockauto`** (`gf_stockAutoassignStamped`, all 3
  stock-fallback sites) — so a **remaining** UNTRACED line is the real signal that a genuine engine/
  unknown path exists ([[untraced-writes-are-unstamped-stock-menu-paths]]). Either way the maySpawn
  fill-discipline gate (`GF_FILLGUARD`) re-parks any mis-seat the same round — the containment stands,
  and trace+fillguard line pairs per round are expected noise, not a fault.
- **Humans stranded in spectator (`:365` team menu) — hypothesis only, never observed; net stays armed.**
  `GF_TEAMWATCH` has fired **0 times ever**; the reports that seeded this theory are now explained by the
  class-clear bug above. If it DOES exist: the discriminator is **`pers["needteam"]`** (a needteam
  spectator is autoassigned via `:312`→`:327` = `gf_autoJoinBalance`, no menu; a spectator without it
  hits `:365`), stock autobalance is off (`scr_teambalance 0`), every mod spectator-write is stamped,
  and the `_globallogic.gsc` `:587/:663/:692` spectator checks are read-only — so a real occurrence
  would be a stampless engine write, and `gf_teamWatchHumans` now logs `needteam` + the last writer
  stamp to prove it. **`_bot::gf_reclaimStrandedHumans`** (top of every boundary pass, after the watch)
  re-seats any UNTRACED-stranded human onto the lighter side and prints `GF_RECLAIM`; gated by
  **`gf_team_reclaim`** (default 1, bridge `reclaim_<0|1>`); intentional spectates are excluded via the
  breadcrumbs (`gf_menuTeamChoice` → `user`; `gf_seqTeamMove`'s spectator branch → `moved`, covering the
  bridge admin force; `scr_team_maxsize` overflow → `maxsize`; lock queue → `gf_seatQueued`; classified
  by `_bot::gf_specReasonTag`). All diagnostics are `logPrint` → **`mods/mp_gunfight/logs/games_mp.log`**.
- **RESOLVED — the `MAX_PACKET_USERCMDS` killcam spam is a CLIENT-side `cl_maxpackets` limit, self-fixable,
  cosmetic.** Proven live 2026-07-15: a client running `com_maxfps 237` / `cl_maxpackets 30` (stock) spat
  ~37 lines per round-end killcam; setting **`cl_maxpackets 100` on that client killed the spam outright**,
  with `com_maxfps` untouched. So the count is **usercmds-per-outgoing-packet** (driven by the send rate),
  **not** the `com_maxfps × ack-gap` backlog — at 30 packets/sec the client crams enough queued commands
  into each packet to cross 32 during the slow-mo ack stall; at 100 it drains in smaller sends. **Nothing
  server-side is involved and the hard constraint is vindicated** — the fix was never the floor or `sv_fps`
  (both still off-limits; lowering the floor brings the `CG_DrawDisconnect` plug back, raising `sv_fps`
  truncates the killcam archive ring). `cl_maxpackets` is archived (`seta`), so a player sets it once and
  it sticks → this is a **player-facing recommendation** (like `cg_fov`), not an engineering item, and
  `docs/GETTING_STARTED.md` carries it (`seta cl_maxpackets "100"`, solo line + the one-liner block).
  ([[killcam-slowmo-timescale-usercmd-backlog]])
- **Stock weapon-data console warnings — cosmetic, client-side, NOT ours (a whole family).** The mod ships
  **zero** weapon files and no `weaponOptions.csv` (`raw/weapons/` is empty), so every one of these is pure
  Treyarch data that surfaces more here than in vanilla only because the rotating pool hands out
  rarely-equipped attachment combos. **Same class as the `MAX_PACKET_USERCMDS` noise: do not chase any of
  them.** Two seen so far:
  - **`CG_SetWeaponHidePartBits: No such bone tag (…) for weapon (…)`** — e.g. `tag_scope_colt` on
    `python_speed_mp`, `tag_iron_sightlow`/`tag_scope_colt` on `m16_ir_mp`. Each weapon def's `hideTags\…`
    list names model bones to hide when equipped, and some stock files list bones that don't exist on that
    model/attachment combo. Engine can't find the bone → one line, moves on; the tag simply isn't hidden
    (nothing to hide), weapon renders fine.
  - **`Couldn't find weapon parent '' for weapon 'sticky_grenade_mp' in weaponOptions.csv`** (also
    `frag_grenade_mp` etc.). `weaponOptions.csv` is stock's camo-index table, keyed per weapon **parent**;
    grenades have an **empty `parentWeaponName`** (confirmed) because they have no camo. When the options
    system touches a grenade, parent `''` → lookup miss → warning. This is *correct* (no camo to resolve).
    Our own `CalcWeaponOptions` targets only primary/secondary — grenades get a plain 1-arg `GiveWeapon` —
    so it's stock give/validation chatter, not a bad arg from us.
  The ONLY silencer is shipping patched copies of the affected stock files in `raw/…` with the dead
  tags/lookups removed — real cost (one file per variant; `build_ff.ps1` cleans `raw/` because Plutonium
  reads it as a fallback *over* stock, so a stray staged file silently overrides the real game
  [[build-stage-transitive-menu]]). **Leave them** unless the planned custom-weapon-file pass (ADS-FOV /
  move-speed tuning) forks these same files anyway — then the cleanup is a free ride-along.
- **Which client orphans `.killcam` in the round-end deadlock is still unproven.** The deadlock itself is
  now broken by `gf_postRoundWatchdog` (the infinite round can't recur), but the *leaker* was never pinned:
  `finalKillcam`'s only live endon is `self endon("disconnect")`, and a disconnected player leaves
  `level.players` — yet the observed hang persisted after the disconnector left again, so the leaker was a
  client that STAYED. Prime suspect is a fill bot added into the killcam window (`gf_boundaryListener` adds
  at `gf_round_over` +0.5s, and `startLastKillcam` snapshots `level.players` *after* `play_final_killcam`).
  **Next occurrence: read the `GF_ENDWATCH:` log line — it names the client and the flag.**
  ([[infinite-round-orphaned-killcam-flag]])
- **Pregame lobby can end on its own** (should end only via the load/min gate or an admin START) — only
  reachable when `scr_gf_lobby` is Auto/Manual, which is now the **default** (`1` = Auto, changed
  2026-07-29), so it is no longer masked by the shipped config.
- **Prematch/intro countdown runs in slow-motion** — NOT transient and NOT a rendering artifact.
  `GF_HITCH` measures **game-time dilation** (`wait` counts game time, `gettime()` counts real time), so
  `750ms vs 500ms` means the whole simulation ran at ~65% speed for that window. The countdown is simply
  the last clock still driven by a game-time `wait(1.0)`; the mod's own clocks are gettime-anchored and
  immune. **Measured on the VPS (10 days, 2,803 hitches):** 99.3% land in `phase=prematch` — roughly one
  per round, ~700-750ms, and **flat across bot count** (694ms at 0 bots vs 746ms at 6), so it is the
  engine's `map_restart` itself, *not* our bots / HUD pushes / loadout giving. It is not ours to delete →
  **the fix is to make the countdown immune** (gettime-own it; see Ideas). Separately, 226 hitches exceed
  **2s** (map load + the `MatchRecord` stat flush), and **15 landed mid-gameplay** at ~2.8s — those are the
  ones that actually hurt, and the two suspects now have panel toggles: **`demo_enabled`** (match
  recording / the `democlient`; the killcam does **not** depend on it) and **`scr_allowbattlechatter`**
  (whose `CheckDistanceToEvent` the GSC VM has killed 3× with "potential infinite loop", each landing on a
  2.4-2.5s frame hitch). Ceiling: the box is 4 **shared** Contabo vCPUs — steal time produces multi-second
  stalls no config fixes. Instrumented via `gf_hitchMonitor` (`gf_hitch_pct`/`gf_hitch_debug`)
  ([[vps-prematch-slowmo-framehitch]]).
- **Mod may still change some client settings** — the r_* vis-tweak force-push was removed; confirm
  nothing else writes a saved client dvar.
- **Democlient round-cam lag.**
- **Round-1 intro sting may clip if GF's long spawn sting overruns stock's per-player `wait 15` —
  UNTESTED.** Music is **100% stock** (a `level.nextMusicState` + level-wide `prematch_over` underscore
  push was written and **reverted** — driving the bed level-wide clips late joiners). The engine's native
  timing is **per-player self-relative** (`sndStartMusicSystem`, threaded on `self` at each player's own
  first spawn → the underscore starts a fixed 15s after *that* player's sting) and is late-joiner-safe by
  construction; sting + bed are the **same composition**, so the seam is pure timing, not a crossfade.
  **Test by ear:** does an on-time intro get cut before it resolves? If yes, GF's long sting > 15s — fix by
  keeping the **per-player** model and bumping the offset (per-player `wait N` from each spawn), **never**
  going level-wide. ([[intro-sting-killed-by-underscore-shared-channel]])
- **Minimap compass doesn't show wager (zoomed) size on some DLC maps** — inherent to the resident-art
  whitelist excluding First Strike/Escalation maps.
- **SECURITY: rotate the two burned secrets — still OPEN, and it is the ONLY thing that closes them.**
  Run **`tools/rotate_secrets.ps1` on the box** for the RCON password (dry-run by default; enforces the
  ≤23 cap; recycles `GF-StatusService` + `GF-JoinNotify` + **`GF-ConnLogger`** — all three cache the
  password at process start (conn-logger via its admin.json-stale **panel fallback** URL, which is why
  it counts despite owning no rcon poller of its own) — and drops a
  watchdog maintenance window first so the escalation ladder can't bounce the server mid-rotation).
  ⚠ **Run the DEPLOYED copy** (`…\storage\t5\mods\mp_gunfight\tools\rotate_secrets.ps1`), **not the
  deploy clone's** (`C:\gfdeploy\BO1-Gunfight\tools\`): path resolution walks up from `$PSScriptRoot`
  and the clone sits outside the storage tree, so from there it hunts `C:\dedicated.cfg`, misses both
  the cfg and the panel secret store, and pre-flight-fails. Harmless — it refuses to guess and writes
  nothing — but it costs a round trip. From the deployed copy all 9 checks pass (verified 2026-08-09).
  Same trap for any `tools/` script that resolves the T5 root from its own location. The
  **server key is manual-only** at platform.plutonium.pw and needs a **full bat restart** — `set key=`
  runs above `:server`, so a bootstrapper kill relaunches with the old `%key%`. ⚠ Reuse the key's exact
  current label or the server renames itself for every player. The two leaked *passwords* are in git
  history; the *key* never was — see the Secrets section for which route each took and why history is
  deliberately not rewritten.
- **Prevent a duplicate launcher from squatting port 28960 after a reboot** (root cause of the reported
  "FF/settings revert on restart"). Related, root-caused 2026-07-20: **the LAPTOP's dedicated server is
  launcher-started with NO `+exec dedicated.cfg`** — that file (and the panel's 💾 Save, which writes it)
  is decoration locally; only `seta`-archived dvars survive a local restart. The local bot tuning is
  `seta`-contained; the real fix is a local start bat that execs the cfg like the VPS's
  ([[local-launcher-no-exec-dedicated-cfg]]).
> Known design caveat, not a bug: **large/small spawn mode takes effect one round after the HUD readout**
> (next-round snapshot vs live count — see *Team-size mode*).

### Ideas & future
- **Killfeed duration is CLIENT-ONLY — the server cannot force it (SETTLED on the VPS 2026-07-13).**
  The killfeed is the engine's **game-message window 0**, not a hudelem: `con_gameMsgWindow0Filter`
  carries the `"obituary"` type (window 1 = boldgame, window 2 = subtitles), and its on-screen time is
  **`con_gameMsgWindow0MsgTime`** — **seconds**, stock **5** (siblings: `LineCount` 4, `FadeInTime` 0.25,
  `FadeOutTime` 0.5, `ScrollTime` 0.25). A player retimes their own killfeed with
  `/con_gameMsgWindow0MsgTime 20` in their console — works today, no mod change, and it's `seta` so it
  persists. ⚠ **A server push is REFUSED**: the dvar is `con_*` (client-owned) *and* archived, the class
  Plutonium blocks ([[rcon-dedicated-dvar-push-limits]]). Proven on the dedicated VPS with a live human:
  the bridge dispatched (`gf_ack` advanced), `cg_thirdPerson` pushed in the same session **landed**
  (control), and the killfeed dvar **stayed at 5**. Dev verb `killfeed_<sec>` (`_gf_bridge.gsc`) exists
  and is kept only as the reproduction. **Remaining choice if we ever want to own the timing:** document
  the console line for players (cheap), or render our own killfeed in the menu layer (costs reliable
  commands per kill + a `mod.ff` rebuild). ⚠ **Never use an archived dvar as the control** in a push test —
  `cg_drawFPS` is itself `seta`, so `fps_1` fails under BOTH hypotheses and proves nothing (it wasted the
  first run of this experiment). ([[killfeed-duration-client-archived]])
- **Own the prematch/intro countdown with `gettime()`** so a hitch degrades to a 1-frame stutter (the
  planned fully-custom-timers branch). **This is the real fix for the slow-mo countdown** — see the
  frame-hitch bug above: the hitch itself is the engine's `map_restart` and is not ours to delete, but the
  countdown is the last clock still driven by game-time `wait(1.0)`, so owning it makes the symptom vanish.
  ⚠ Do **not** pair this with the once-floated **sv_fps 30** experiment: `GF_HITCH` is *game-time dilation*
  (wall time to advance 0.5s of game time), and the stall is a fixed lump of wall-clock work — more frames
  per second on a CPU-starved box buys more overhead and *more* dilation, not less. VPS runs 20; leave it.
- **Loadout slide-out stays a GSC dvar-animation stream — the "menu-owned free" version is RESOLVED
  UNVIABLE** ([[menu-milliseconds-client-local-no-per-round-event]], settled 2026-07-15 with no rebuild). The
  loadout **outro slides+fades via `gf_slideLoadout`** (the intro snaps): 1 batched command per 0.05s step for
  0.5s = **~13 reliable commands/human/round**, the densest stream the mod emits and the only one a batch can't
  take to zero ([[server-command-overflow-reliable-command-budget]]). ⚠ **It is kept deliberately** — the slide
  reads better than a pop, and it fires ~8s into the round, mid-gameplay, NOT in the `map_restart(false)`
  lobby-START stall where the reliable-command overflow actually bites (that needs a burst AND a frozen client),
  so it is a *purity* cost, not a live-problem cost. **Why the free menu-owned path is dead:** `milliseconds()`
  in a menu `exp` is the **CLIENT's UI-realtime clock, not server `cg.time`** (proof: `raw/ui/main.menu` scrolls
  fog with `milliseconds() % PERIOD` *before any server connection*), so the server **cannot** stamp the start
  marker; stock only ever stamps it **client-side** in a menu's `onOpen` (`game_summary`/AAR `exec
  "setdvartotime"`), and our always-loaded `loadMenu` HUD has **no per-round client event** to stamp one (no
  `onDvarChanged`; the only server→client open trigger, `openMenu`, steals input focus). ⚠ **Do NOT re-open
  this as "unverified" or burn a `mod.ff` rebuild on the `milliseconds()`-vs-`gettime()` probe — `main.menu`
  already answered it.** If the count ever must drop, coarsen the animation (step 0.05→0.1s halves it; shorten
  0.5→0.3s, the fade masks the coarser stepping); snapping the outro (like the intro) is the zero-cost floor.
- **Hybrid custom round-timer HUD:** keep the native engine-driven `MM:SS` for the normal phase, own only
  the final ≤10s (orange `S.T` tenths) via the menu layer, route OT through the same element.
- **Remote RCON access (drive the panel from a phone / any device) — "put it on the website behind a
  login" is the WRONG first move, and the reason is structural.** The panel has **no user
  authentication at all**: `server.js` binds `127.0.0.1` only and allowlists `Host`/`Origin` to
  `127.0.0.1:<PORT>` as its CSRF / DNS-rebinding guard — **loopback IS the auth**. So adding a login
  page is not hardening an app, it is deleting the only control and backfilling in front of four
  unauthenticated power endpoints: `POST /api/rcon` (arbitrary server console — every dvar, the GSC
  bridge, map control), `POST /api/savecfg` (writes `dedicated.cfg` on the box), `GET`/`POST
  /api/secrets` (reads/writes stored **rcon passwords**), and `/api/status` + `/api/geoip` (player
  IPs/GUIDs). Ranked options:
  1. **Tailscale / WireGuard — the recommendation.** Panel reachable at the tailnet IP from phone/
     laptop; no public port, no login code, auth = IdP + device approval. Cost is one config change:
     bind the tailnet interface and **widen the Host/Origin allowlist by ADDING that host — never by
     removing the check** (it is the anti-rebinding guard, and a wildcard means any site you visit can
     POST to the panel). Caveat: everyone on the tailnet is full admin — fine for a single-user tailnet.
  2. **IIS reverse proxy on gunfight.us behind auth** — the literal "secure page with login", and it
     reuses the proven `/admin` pattern (`tools/vps_services/setup_admin_auth.ps1`, Basic auth over
     HTTPS + the `.secured` interlock). Needs ARR, and preserve-host handling or the allowlist rejects
     every proxied request. ⚠ Hardening is **not optional** here: proxy an allowlist of paths (never
     `/`), keep `/api/secrets` + `/api/savecfg` loopback-only, rate-limit, and log every `/api/rcon`
     with the authenticated user. A Windows local account behind IIS Basic auth is thin cover for what
     is effectively a remote console, and that credential is worth more than a panel password.
  3. **Least-privilege command page** — expose a narrow authenticated page with a **whitelist** of
     verbs (pause, end round, restart, kick, map change) consumed by a box-side service; the panel
     itself never faces the internet. Safest public-web shape, at the cost of the live editor.
  4. **Real session auth inside `server.js`** (argon2 + TOTP + CSRF + lockout) — most code, most
     ongoing risk. Only worth it for multiple *named* admins with an audit trail.
  ⚠ Weigh all four against what already exists: the **`gf-vps` Remote Control session** covers
  phone-based ops today, and `ssh -L 3000:127.0.0.1:3000 gf-vps` gives the full panel from any machine
  holding the key. The marginal need may be smaller than it looks.
- RCON: gas/stun/flash intensity sliders; mantle/climb speed control.
- Lobby ready-up / team-picking UI; lobby fly-cam controls.
- Min-players option that also counts bots (`scr_gf_min_players` counts humans only today).
- Spawn/flag pass: widen spawns; adjust flags generally; Hockey mode on Arena (map-specific).
- Ship custom weapon files for ADS-FOV / move-speed tuning; tuning pass (shorter round, capture 3.5s,
  Hardened on sniper classes).
- Persistent "gunfight.us" HUD text; general HUD/visual polish; rename the "democlient" bot label; rename
  the gametype display "GF" → "Gunfight".
- Site/branding: design pass; server ads; credit Plutonium/bots; show per-map feature support; on-brand
  Discord live-count card ([[discord-widget-csp-frame-src]]). Setup guide: recommend `cg_fov 65`,
  `cg_fovScale 1.4`. BO1 server "role" tied to Discord activity.

---

## Goal & design philosophy

**Bring an authentic Gunfight experience to T5 using as much native/core-engine and existing-library
functionality as possible.** The bar for writing custom code is: *does a stock system already express
this?* If yes, use it. We own only the few systems the engine genuinely cannot express, and we own
them for a specific, documented reason.

Principles, in priority order:
1. **Native-first.** Round cycling, scoring, intermission, killcam, prematch, `_gameobjects`, spawn
   selection, friendly-fire, and flinch are all stock. We hook them via `level.on*` callbacks, we do
   not reimplement them.
2. **Own only what stock can't do**, and say why in a comment: the retunable **round clock** (stock
   time-out thresholds are hardcoded absolute seconds, unusable on a 45s round), the **overtime clock**
   (needs pause/resume on a *gameplay condition* + hide-on-capture), and the **HUD** (the per-client
   render cap forces the menu layer).
3. **Strictly avoid poor-performance patterns.** No per-frame busy loops, no redundant polling, no
   piling `setClientDvar` bursts on one frame, no per-client HUD-render-cap abuse. Polling loops are
   bounded (`endon` a lifecycle notify), event-driven where possible, and coalesced.
4. **Lean on `game[]`/`self.pers[]` for anything that must survive `map_restart`** (see the map_restart
   rule below); re-derive everything else each round in `onStartGameType`.

We do **not** reference other community Gunfight mods — they are not a design source here. The only
external references we use are the official engine sources (see **Resources**).

---

## Working in this repo

**The repo IS the mod folder.** A clone of `main` drops into the Plutonium T5 storage tree at
`%localappdata%\Plutonium\storage\t5\mods\mp_gunfight\`, so testing is just `loadMod mp_gunfight` +
`map_restart` in the Plutonium console (`connect 127.0.0.1:28960` for a local dedicated server).

- **GSC is loaded as loose rawfiles** — edit a `.gsc` and `map_restart`; **no rebuild**. Only compiled
  assets need `mod.ff` (see *Building mod.ff*).
- **Local-test cfg quirks:** `party_minplayers 1` for solo testing (`2` for public). If ADS feels wrong
  locally, `exec autoexec`. (The `scr_xpscale is read only` error at boot is our own cfg line being
  rejected — see *XP* below; it is harmless but it is **not** a local-only quirk.)
- **Test panel/bridge/telemetry changes against a DEDICATED server, not a listen host** — a listen
  server masks RCON queue saturation and the "Unknown cmd" dvar-probe spam that only bite on the VPS.

### 🛑 MARKETING COPY IS THE OWNER'S — NEVER "CORRECT" IT AGAINST THE CODE
**`site/wwwroot/*.html` and `README.md`'s feature list are ADVERTISING written by the owner, not
documentation generated from the source.** They are allowed to round, exaggerate, simplify, and
disagree with the code. **A mismatch between site copy and the code is NOT a bug and NOT drift — do
not "fix" it, do not flag it as an inconsistency, and never let a verifier's output override a
sentence a human typed.** If a number there looks wrong to you, you are missing context (a map that
is playable but deliberately uncurated, a promo the owner is running, a claim that is aspirational on
purpose). **Leave it. Ask, or say nothing.**

Owner-authored copy that is **deliberate and must not be rewritten**:
- **"All 26 maps"** — the owner's count and phrasing. `verify_locations.ps1` reports **25 curated**
  spawn sets, and that is the *code* number: `firingrange` is a supported opt-out that still plays
  fine on stock spawns, so 26 is the honest count of *playable* maps. **Both numbers are right about
  different things.** `_gf_locations.gsc`'s 25 belongs in technical prose only (this file's *Spawns*
  section); it never propagates to the site or the README feature list.
- **"4XP Enabled!"** — the owner's promo phrasing. Do **not** replace it with a computed ratio from
  `registerScoreInfo` (kill 500 vs stock 100). The house format is **`<N>XP Enabled!`** and the
  **"All <N> maps"** headline — keep both formats intact even when changing the number.
- **"Tuned game rendering, lighting, and colors"** — kept as written even though the `r_*` push was
  removed and what ships is the `visionSetNaked` pass.

⚠ **This has happened three times and cost real trust.** `eac1a0e` (2026-07-28) rewrote *All 24
maps* → *25 maps* and *2XP Enabled!* → *Boosted XP — rank up ~5× faster!*; the owner restored the
house format in `2a1cdab` (2026-07-30 01:32) as *26 maps* / *4XP Enabled!*; **`36feaeb` (29 minutes
later) reverted both again and also reworded the rendering line — in `README.md` too — citing
"drifted public numbers".** Each pass was a docs/accuracy sweep that treated advertising as if it
were a spec. **A commit whose job is "fix drift" must not touch `site/wwwroot/` or the README
feature list at all.**

✅ **Copy changes there are owner-requested only.** Fix a typo, a broken link, or markup you were
asked to fix; if you believe a *claim* is wrong, raise it and wait. ⚠ Nothing on the site auto-
deploys — `deploy.ps1 -Web` is manual and no scheduled task pulls or publishes (verified 2026-08-09,
all 8 `GF-*` tasks) — so anything live got there because a human ran a deploy over a commit like the
above. That is exactly why the *commit* is the place to stop it.

🚫 **NEVER PUBLISH AN EM DASH.** No `—` and no `&mdash;` in any copy for `site/wwwroot/`, `README.md`,
or anything else player-facing. Use a comma, a semicolon, a colon, or two sentences, whichever the
sentence actually wants. This is a house style rule, not a preference to weigh: an em dash reads as
machine-written copy. **The site + README were fully swept on 2026-08-10** (owner-requested), so
`grep -rn "&mdash;\|—" site/wwwroot README.md` should return **only code comments** — any prose hit is
a regression. Conventions the sweep settled, reuse them: a `<b>Label</b> — text` tile or list row takes
a **colon**; a page `<title>` separator is **`&middot;`** (matching the footer, and unambiguous next to
the `Gunfight [gunfight.us]` server name); an empty data cell is **`n/a`**, never a bare dash glyph.
⚠ **Code comments are deliberately exempt** and were left alone (they are developer-facing, and
rewriting them is pure diff noise). ⚠ **En dashes are NOT covered** — `admin.js`'s `Allies 3 – 2 Axis`
score separator is correct typography; do not "fix" it.

### Diagnostics — where the logs go, and what to read
**There are two log files and only one is ours.** Get this wrong and you will grep an empty file and
conclude a diagnostic never fired:

| GSC call | Lands in | Use for |
|---|---|---|
| `logPrint()` | **`mods/mp_gunfight/logs/games_mp.log`** | **every `GF_*` diagnostic** — this is the one stream |
| `println()` | `mods/mp_gunfight/console_mp.log` | engine console; GSC **compile/runtime errors** surface here |
| `logString()` | **nowhere** | never use ([[xp-scrxpscale-readonly-and-dead-score-path]]) |

⚠ **The two logs live in DIFFERENT folders on the VPS — verified live 2026-07-20** (the running config
has `g_log "logs\games_mp.log"`, so the old "logs/ is a decoy" claim was stale and is retired):
`logPrint`/`GF_*` land in **`mp_gunfight/logs/games_mp.log`** (the mod-root `games_mp.log` does **not**
exist), while `println`/console lands in **`mp_gunfight/console_mp.log`** (mod root). Neither is in
`storage/t5/main/`. ⚠ Grep `logs/games_mp.log` for GF_ lines — grepping the mod root finds nothing.
⚠ **One stream is the rule:** diagnostics split across two files cannot be correlated by timestamp,
which defeats having them. The sole deliberate exception is the `GF_SECURITY` boot alarm, which writes
**both** (red console warning for a human watching the console + a `logPrint` twin so it still greps
with everything else).
⚠ **`games_mp.log`'s LIVE file has no rotation** — the server holds its handle open (`g_logSync 1`), so
only a restart rolls it, and the engine's own `.000`–`.00N` roll then archives it. **`watchdog.ps1` now
prunes those CLOSED `<log>.NNN` archives** to a per-base budget (`$LogArchiveBudgetMB`, default 400) for
both `games_mp.log` and `console_mp.log`, and warns if a LIVE file passes `$LiveLogWarnMB` (800) — so a
flood dvar left on can no longer fill the disk, but it will still bloat the *single live file* until the
next restart. ⚠ **`console_mp.log` trips that warn line by DESIGN, not by fault**: the engine prints a
full 3,078-line dvar dump at every round's `map_restart` (~216MB/day, 92% of the file) — grep the tail
for `END DVAR DUMP` before suspecting a mod flood ([[console-mp-per-round-dvar-dump-flood]], which also
identifies `raw\scripts\mp\mp_spawn_fix.gsc` as Plutonium's own anti-exploit script, not a rogue file). That is why the per-death `GF_POPUP` line stays dvar-gated **OFF** by default (`gf_debug_popup 0`):
the pruning makes a *temporary* investigation safe, not permanent per-hit logging.

**`GF_TEAMTRACE` — the team-write tracer** (`_gf_debug::gf_teamTrace`, dvar `gf_trace_teams`, default
**2 = on, full history**; `1` = untraced moves only, `0` = off). Level 2 also logs the *sanctioned*
balancer's attributed moves — the level-1 blind spot that hid the human "moved to other team → forced
to choose a team/class" case (a transient spectator flash GF_TEAMWATCH can't catch because it only fires
on a strand still present at the NEXT boundary). Built to identify the untraced mis-seater
behind both open team bugs. GSC cannot hook a field write, so it works by **difference**: every
sanctioned writer of `pers["team"]` stamps a **single-use token** naming itself and its target
(`_gf_rounds::gf_stampTeamWriter` — 10 tokens: `seatjoin`, `quietset`, `maxsize`, `botquiet`,
`pteam`, `stockauto`, `stockmenu`, `parkpending`, `movepending`, `fillguard`; there is no `bridge`
token — the bridge's moves land as `pteam`/`quietset`/`movepending` through the shared primitives —
and the tracer's by-difference design makes a drifted token list actively misleading, so verify this
list against the `gf_setTeamFields`/`gf_stampTeamWriter` call sites before using it in an
investigation), and the sampler walks the roster at **three checkpoints**
— `boundary-in`, `boundary-out`, `pre-spawn` — reporting any team change with no matching token as
`GF_TEAMTRACE: UNTRACED …`. ⚠ The token is **consumed on match** deliberately: left in place, a stock
autoassign moving someone back onto a team a sanctioned writer used earlier would be absolved forever.
⚠ `gf_stampTeamWriter` **lives outside every strip region** — the `scr_team_maxsize` writer ships
public, and a kept call into stripped code is an `unknown function` that fails the whole server.
⚠ Keep `GF_TEAMWATCH` too: it catches a player who was *already* wrong before the match's first
checkpoint, which the sampler cannot see.

**Dev-only dvars:** `gf_trace_teams`, `gf_debug_popup` (per-death score share, default 0),
`gf_debug_spawns`, `gf_debug_hud_pool`, `gf_debug_elem_probe`, `gf_debug_spawnyaw`, `gf_debug_loadgap`
(client-readiness gap, `GF_LOADGAP` — see below), `gf_hitch_pct`
(threshold %, code-default 25), `gf_hitch_debug`, `gf_endgap_ms`, `gf_force_loadout`, `gf_force_camo`.

**`GF_LOADGAP` — the client-readiness probe** (`_gf_debug::gf_probeLoadGap`, dvar `gf_debug_loadgap`,
default **0**). On a fresh connect a player spawns on the SERVER before their client is drawing
("round 1, camera isn't loaded yet"), so anything the server times from that spawn can play to a black
screen. ⚠ **The server cannot see "the client is rendering"** — `statusicon`/`"begin"`
(`_globallogic_player.gsc:19-21`) is the deepest signal GSC gets and it fires at cgame init; the first
rendered frame, Plutonium's in-place engine rebuild and the Demonware resync all land after it,
invisibly (stock doesn't even try — T5's `waitForPlayers()` is an empty stub). So the probe measures a
**proxy**: the usercmd stream, which only flows once cgame runs (view divergence / origin delta /
Attack-Jump-Melee). ⚠ It samples from **`prematch_over`, not spawn** — during the countdown the player
is frozen and still, indistinguishable from a client sending nothing, and it is also when
`gf_lockSpawnYaw` releases so nothing of ours is writing angles. The decisive field is **`live2input`**
(ms from go-live to first evidence of presence): `<1000` = the loadout overview's go-live +1s anchor
already covers it; `2000-5000` = an input-gated tail with a ceiling (NOT a bigger fixed number — a panel
over first contact on a 42s one-life round is a real cost); huge/`NO_INPUT` = the gap outlives the round
and the lever is a post-`begin` settle delay on the load gate, which fixes the overview, the welcome
splash, the spawn-yaw hold and the intro sting at once. ⚠ **`NO_INPUT` is ambiguous by design** — a
player who touches nothing logs the same line as one still black-screened; it only ever makes the gap
look worse, the safe direction for a probe that gates spending.

### Companion docs (NOT auto-loaded — open them for depth)
| Doc | Owns |
|---|---|
| `docs/REFERENCE.md` | Authoritative present-tense per-system prose, the full gameplay dvar/var tables, and a per-function reference for the gameplay files. |
| `docs/DEV.md` | Repo layout, GSC include graph, `build_ff.ps1`, branch/release model + strip markers, deploy pipeline, dev tooling (RCON/bots/debug). |
| `docs/VPS_DEPLOY.md` | 11-phase VPS provisioning + deploy runbook (FastDL, git-pull deploy). |
| `docs/MIGRATION.md` | Box-to-box migration runbook — the **delta** VPS_DEPLOY doesn't rebuild: what state is box-local and must be carried, what to rotate, cutover order + acceptance checklist. |
| `docs/VPS_HARDENING.md` | Security runbook (RDP/WinRM/TLS/IIS `web.config`/DNS) with as-applied status. |
| `docs/GETTING_STARTED.md` | Player-facing install / settings / ADS-fix / join guide. |
| `docs/notes/` | Hard-won single-incident deep-dives, one file per finding + `README.md` index. Committed to the repo (so they reach the VPS), NOT auto-loaded — open the one you need. |

`docs/notes/` holds the single-incident deep-dives; a **`[[slug]]`** reference in this file resolves to
**`docs/notes/<slug>.md`** (same slug = same filename). The `docs/notes/README.md` index groups them all.
⚠ These were previously the laptop-only `~/.claude` memory store; they were migrated into the repo so
VPS-Claude sees them too. When you learn a new single-incident finding, add it as a new
`docs/notes/<slug>.md` + one index line, and `[[slug]]`-link it from here — do **not** resurrect the
laptop memory folder as a second copy (it drifts).

### Project map
```
mp_gunfight/  (GitHub: KL9modz/BO1-Gunfight)
  .claude/CLAUDE.md                  <- this file
  mod.csv                            <- build manifest the linker reads
  mp/gametypesTable.csv              <- registers the 'gf' (+ wager gun/oic/hlnd/shrp) UI rows
  localizedstrings/gf.str            <- localized UI strings (assets are named GF_<REFERENCE>)
  localizedstrings/cgame.str         <- OVERRIDES of stock engine strings (see below)
  ui_mp/
    hud_gf.txt                       <- menufile loader (loadMenu hud_team + hud_gf_health)
    hud_gf_health.menu               <- ALL mod HUD (health panel, loadout overview, self bar, lobby)
    mod.txt / mod_ingame.txt         <- empty {} stubs (kill a ~4.6s missing-asset stall on mod load)
  maps/mp/gametypes/
    gf.gsc                           <- ENTRY POINT: main(), callbacks, precache, spawn pipeline
    _gf_rounds.gsc                   <- round lifecycle, clocks, overtime, match-start/lobby, team-size, damage/score
    _gf_loadouts.gsc                 <- shared loadout pool, shuffle, give, camo
    _gf_hud.gsc                      <- menu-driven HUD (health panel, loadout overview, score popup)
    _gf_locations.gsc                <- per-map curated spawns + overtime flag points
    _gf_wager_zones.gsc              <- wager compass material + map-specific zone helpers
    _gf_debug.gsc        (dev only)  <- spawn recorder, HUD-pool probe, frame-hitch monitor
    _gf_bridge.gsc       (dev only)  <- RCON -> GSC command bridge
    _bot.gsc             (dev only)  <- bot integration + dynamic-fill reconciler
  maps/mp/bots/          (dev only)  <- vendored BotWarfare framework (_bot_loadout/_bot_script/_bot_utility)
  raw/fx/misc/*.efx                  <- custom overtime apron FX (white ring; gold/red use stock FX)
  site/wwwroot/                      <- PUBLIC static website (gunfight.us). NOT the RCON panel.
  tools/                 (dev only)  <- build_ff, packagers, deploy, RCON panel, box services, loadout editor
```
> Entry point is `gf.gsc::main()`. `(dev only)` files are excluded from public release outputs by
> `package_release.ps1`. There is no `mp_gunfight.gsc`.

**Cross-file `#include` rule (T5 has no transitive includes):** each file must `#include` every other
file whose functions it calls *directly*; a missing include is an `unknown function` compile error on
the calling function. Current graph: `gf.gsc` → `_gf_locations`/`_gf_rounds`/`_gf_loadouts`/
`_gf_wager_zones` (+ dev `_gf_bridge`/`_gf_debug`) + stock `_utility`/`_hud_util`; `_gf_rounds` →
`_gf_hud` (+ dev `_gf_debug`) + `_hud_util`; `_gf_loadouts` → `_gf_hud`; `_gf_hud` → `_hud_util`.

---

## Core gameplay spec

- **Round-based, one life** — last team standing ends the round; then killcam. `scr_gf_numlives 1`.
- **Match = 6 round wins.** The real threshold is `scr_gf_scorelimit` (6), enforced by stock
  `hitScoreLimit()` on `game["teamScores"]` — each round win adds **1** to the winner's team score in
  `gf_endRound`. (`level.roundWinLimit`/`hitRoundWinLimit` are **inert** here — `RoundWinLimit` is
  registered at 0. To change match length, change `scr_gf_scorelimit`.)
- **Shared random loadout** — every player gets the same primary/secondary/lethal/tactical/equipment
  each round; the pool rotates every `scr_gf_roundsperloadout` (2) rounds.
- **No killstreaks, no health regen, no weapon drops, no class-select** — `level.killstreaksenabled=0`,
  `level.healthRegenDisabled=true`, `scr_disable_weapondrop 1`, `scr_disable_cac 1` (all re-forced each
  round in `onStartGameType`).
- **Round decided by time** → most total remaining HP wins; equal HP is a **draw** (draws add no score).
  If both teams are still alive at expiry, **overtime**: capture the overtime flag, else HP decides.
- **Damage-based scoring** — a player's score is the running total of damage they've dealt.
- **Loadout HUD** — on spawn, a create-a-class-style overview of the round's weapons + perks.

---

## How each system works today

*(Present-tense architecture. File refs are `_gf_rounds.gsc` unless noted. Deep detail →
`docs/REFERENCE.md`; incident depth → `docs/notes/` (a `[[slug]]` = `docs/notes/<slug>.md`).)*

### The `map_restart` rule (read first)
SD round cycling calls `_globallogic::endGame` → **`map_restart(true)` between rounds**, which wipes
**all `level.*`** (and entities) but keeps `game[]` and `self.pers[]`. The pregame lobby uses
**`map_restart(false)`**, which wipes `game[]`/`pers[]`/`level[]` too. Consequences that shape the whole
codebase: `onStartGameType` re-runs every round and must re-establish every `level.*` value; anything
that must survive a restart lives in `game[]`, `pers[]`, or a **dvar** (dvars are the *only* thing
surviving `map_restart(false)`); and **threads survive both restarts** (only `game_ended` tears them
down), so persistent loops are collapsed to one copy via a re-init notify (`bot_reinit`,
`gf_bridge_reinit`) rather than a `game[]` once-guard.

### Round lifecycle & activation
`onStartGameType` stamps `level.gf_roundGen = gettime()` (monotonic across restarts) and resets round
flags. The round runs on the **engine's native prematch** (`level.prematchPeriod`): countdown, freeze,
intro VO, hint, timer-hide are all stock; the only addition is `gf_nativePrematchTicker()` (a 1 Hz beep
the silent stock countdown lacks). Activation is spawn-driven: `gf_onSpawned` threads
`gf_tryActivateRound`, which dedups (0.2s), `waittill("prematch_over")`, then in one **yield-free**
block sets `gf_roundActive`, threads `gf_roundWatchdog(myGen)`, closes grace early
(`gf_closeGraceEarly`, prematch_over+3s floor), captures the team-mode snapshot, and starts the round
clock. Staleness is handled by **capturing `myGen` and bailing if `gf_roundGen` moved** — never by an
`endon` on a lobby-reset notify (that once killed a committing activator and stranded the round;
[[round-freeze-activation-race-and-rails]]).

The round ends by three paths, all → `gf_endRound(winner)` → `_globallogic::endGame`:
elimination (`gf_onDeadEvent`), clock expiry (`gf_onTimeLimit` → HP decision or overtime), or OT
capture. `gf_endRound` adds 1 to the winner's team score (not for "tie"), sets the WIN/LOSS banner
subtitle (`gf_reasonText`), and starts the last killcam. `gf_roundWatchdog` is the only **in-round**
backstop (the mod suppresses every native fallback), gettime()-anchored, 1 Hz: it force-closes a stuck
grace after >65s and force-ends a round when a team has 0 alive out of grace for >3s.

**`gf_postRoundWatchdog` is the round-END half**, threaded from `gf_endRound` *before* `endGame`, because
`gf_roundWatchdog` carries `endon("gf_round_over")` and so retires exactly when the round-end hazard
opens. Stock's end sequence is **synchronous** (`endGame` → `startNextRound` → `displayRoundEnd` →
`executePostRoundEvents` → `map_restart(true)`) and two of its gates are unbounded: `finalKillcamWaiter()`
spins while **any** player merely has `.killcam` *defined*, and `roundEndWait()` spins while any player has
`.doingNotify` true. An orphaned flag on one client therefore blocks `map_restart` **forever** — and the
engine's own force-clear (`endedFinalKillcamCleanup`) waits on `game_ended`, which `endGame` already fired
*before* the final killcam starts, so it is **dead code on this path**. The watchdog is gen-token retired,
clears both flags after 20s, and logs which client/flag leaked (`GF_ENDWATCH:`)
([[infinite-round-orphaned-killcam-flag]]).

⚠ Never re-add an `endon` to the committing activator. ⚠ `gf_roundWatchdog` must stay.
⚠ `gf_postRoundWatchdog` must **not** carry `endon("game_ended")` (endGame fires it within a frame of the
thread starting) and must stay armed on the last round (the same waiter gates the match-end podium).

### Custom round clock & warnings
The live round timer is mod-owned because stock `timeLimitClock` fires its time-out sequence (announcer
VO, `TIME_OUT` music, beeps) at hardcoded absolute seconds — on a 45s round that fires almost
immediately and no dvar retunes it. `gf_startRoundClock` derives length from `level.timeLimit`
(per-mode), sets `level.timeLimitOverride=true` (own expiry), calls `pauseTimer()` (which sets
`level.timerStopped` and gates off the *entire* native warning loop), and drives the HUD via
`setGameEndTime`. `gf_roundClock` ticks 10 Hz off `gettime()` deltas (wall-clock, so sv_fps-immune).
Warning: one `leaderDialog("timesup")` at 15s + a beep each second in the final 10s. Starting the clock
before `prematch_over` would draw over the native countdown — so activation parks on `prematch_over`.
⚠ `pauseTimer()` freezes `getTimePassed()`, which breaks any stock system keyed off it — the grenade-dud
window is disabled (`grenadeLauncherDudTime`/`thrownGrenadeDudTime = -1`) for exactly this reason
([[paused-timer-freezes-gettimepassed]], [[gf-timer-prematch-and-pause-model]]).

### Final-killcam slow motion (`scr_gf_killcam_slowmo` = the timescale FLOOR)
Stock's round-end killcam drops the **whole server** to `SetTimeScale(0.25)` for the money shot
(`raw/_killcam.gsc::waitFinalKillcamSlowdown`, threaded per viewer from `finalKillcam()` — the
round-end cam only, never the per-death one). **Measured on the VPS: 0.27x, held for 8-10 REAL
seconds, every round.** That is what made the "Connection Interrupted" plug flash mid-replay, and it
is **one bug with the `MAX_PACKET_USERCMDS` console spam**, not two:

> The server retires a client's usercmds only when it runs a **game frame**, and
> **`game frames/sec = sv_fps × timescale`**. The game-time quantum is `1000/sv_fps` and a dilation
> does **not** shrink it — it spreads those quanta apart in **wall** time (at `sv_fps 20`, from 50ms
> to **~185ms**). A client makes one usercmd per client frame, so the queue is `com_maxfps × gap`;
> past `MAX_PACKET_USERCMDS` (**32**) it truncates its move packet, and the same backlog makes
> `CG_DrawDisconnect` draw the plug — **it fires when the server stops ACKING your commands, not when
> data stops arriving.** Stock 0.25 → 200ms gap. 0.6 → **~80ms gap, measured live**.

**SHIPPED AND CONFIRMED LIVE (2026-07-13): the plug is GONE and the game feels great in a full lobby.**
Sampler across 4 round-ends: the timescale floors at **0.62** (never below), frame gap **~80ms** — down
from 0.27 / ~185ms.

`gf_killcamSlowmoClamp` (threaded from `gf_endRound`) therefore clamps the slow-mo's **DEPTH, not its
length** — shortening it does nothing, the backlog builds within ~300ms of the drop. It anchors on
stock's `play_final_killcam` notify, mirrors stock's schedule, and re-asserts the floor at 10 Hz using
**stock's own `deathTime` ramp target**, so the cinematic keeps its shape and only its depth changes
(`SetTimeScale` is a plain builtin — the last caller wins). `gf_resetTimeScale()` in `onStartGameType`
is the unconditional net for a leaked dilation.
⚠ It bails unless `level.inFinalKillcam`: stock fires `play_final_killcam` **every** round, killcam or
not, so clamping unguarded would *slow down* a normal round end.
⚠ **`sv_fps` is NOT the lever**, though it is the other term: the killcam rewinds through an archived
snapshot ring sized in **frames, not seconds**, so raising it buys proportionally *less* killcam
history. Tried live at 80 — the replay ended early and the slow-mo never ran at all. **Leave it at 20.**
⚠ **No probe inside the GSC VM can see a dilation** — `SetTimeScale` doesn't mirror into a readable
`timescale` dvar, and `gettime()`/`wait()`/the log timestamps all share the *scaled* clock, so
`GF_HITCH`/`GF_ENDGAP` are blind to it (**their zeros were never an all-clear**). Measure it from
outside the sim with **`tools/ts_sample.ps1`** (RCON is the only wall clock we have).
🛑 **`MAX_PACKET_USERCMDS` STILL PRINTS, AND THAT IS NOT A REGRESSION — DO NOT "FIX" IT BY TOUCHING THE
FLOOR OR `sv_fps`.** An earlier version of this file called "zero `MAX_PACKET_USERCMDS`" the acceptance
test for the fix. **That was wrong** — it conflated two different client limits, and it is a trap: the
spam persists at floor 0.6 while the plug is gone, so a future session that treats the spam as failure
will "fix" a server that is working perfectly and reintroduce the plug. The two limits:
- **`MAX_PACKET_USERCMDS` (32)** — the *per-packet* cap. Exceeding it truncates the move packet, dropping
  the **oldest** queued commands. The server still gets your newest ones and keeps acking, so you lose a
  few ms of stale input nobody can feel. **Cosmetic. Console noise.**
- **`CG_DrawDisconnect`** — a *separate, much looser* backlog threshold. **This** is the plug, and this is
  what the 0.6 floor cleared.

The real acceptance test is the one that shipped: **the plug is gone and the game feels right.**
It remains an open item to make the spam stop too (see TODO) — but it is a **cosmetic-polish** task, and
the constraint is absolute: **do not regress the floor or raise `sv_fps` chasing it.**
([[killcam-slowmo-timescale-usercmd-backlog]])

### Overtime & the two-layer zone color system
`gf_onTimeLimit`: if both teams are alive at expiry → overtime (unless `scr_gf_overtimelimit <= 0`, then
HP decides immediately); else HP decides. Overtime is a custom ms-decrement clock (`gf_beginOvertime`/
`gf_overtimeClock`, gettime()-anchored) because the native timer cannot **pause/resume on a gameplay
condition** (freeze while the zone is being captured, resume if the capture breaks — via a pause-depth
counter), **hide during that pause** (`setGameEndTime(0)`), or tick per-second. The capture zone is
native `_gameobjects::createUseObject` on a **`trigger_radius`**, so standing in it accrues capture (no
button — which is also how bots win OT). A capture wins the round outright.

The color system is two layers with different meaning, dictated by an **engine constraint**:
- **Icons — team-relative** (2D minimap + 3D world), driven from the same native `_gameobjects` path
  (`set2DIcon`/`set3DIcon` + `setOwnerTeam`): **friendly → `defend` (green), enemy → `capture` (red)**,
  neutral/contested → white. (Reversing friendly→capture is the known "my team shows red" bug —
  [[overtime-icon-2d-3d-coincidence]].)
- **Apron ring FX — absolute** (white idle / gold capturing / red contested), the same for everyone,
  because a `spawnFx` entity renders in world space with **no per-team visibility** in T5. The apron
  physically *cannot* encode friendly/enemy — that's why the green/red lives only on the routed icons.

⚠ `loadfx` handles are `level.*`, wiped by `map_restart(true)` — so `gf_loadOvertimeApronFx()` re-loads
them **every OT entry**, not just at precache ([[onprecache-once-per-match-loadfx-wiped]]). ⚠ Native
objective IDs / objpoints accumulate across restarts, so per-round `gf_cleanupOvertimeZone` is mandatory
or the HUD pool exhausts. Deep detail → `docs/REFERENCE.md` "Overtime & capture zone".

### Match-start gate & pregame lobby
**One pre-prematch hold** (`gf_waitForLoadingClients`, called as the LAST statement of
`onStartGameType` — the engine threads the prematch only once that callback returns, so blocking there
= "prematch hasn't started"). It replaced two retired post-prematch gates. Loading clients connect while
still on the loading screen and aren't in `level.players` yet, so `gf_armLoadGate` collects them off the
level `"connecting"` notify (armed early, before the first yield); "loading" is read from `statusicon`.
Bots (`istestclient()`) and demo clients (`isdemoclient()`) are excluded. Three release conditions on
the one hold: **LOAD** (everyone off the loading screen, ceiling `scr_gf_load_wait`, 3s floor),
**MIN-PLAYERS** (`scr_gf_min_players` humans present; ceiling `scr_gf_minplayers_timer`, default 0 =
never auto-start; a 0-human lobby always releases), and **LOBBY MODE**.

**ROSTER EXPECTATION (`scr_gf_load_expect`, default 1 = ON) — a refinement of LOAD, not a fourth gate.**
The tracker can only wait for clients it has *seen*: the gate is already exact for anyone whose connect
packet landed (it releases the instant `stillLoading == 0` — `scr_gf_load_wait` is purely a ceiling),
and there is **no engine read for "clients still connecting"** (`level.players` holds only begun
clients, the `"connecting"` notify is the deepest signal the VM gets, and `raw/maps/mp` has no
connected-count builtin), so the blind 3s arrival floor is all that covers a client who hasn't spoken
yet. The only available *target* number is the previous map's roster: `gf_writeExpectCount` snapshots
the human headcount into **`gf_expectcount`** at every match end (unconditionally — it is a count, not
a seating policy, so unlike the team plan it ignores `gf_team_nextmatch`), and the next match's gate
consumes it. Release then also requires `humans >= expected`, and — the actual win —
**positive roster evidence bypasses the 3s floor**: expected roster present *and* loaded starts the
match immediately, so a 2-player server whose players both reconnect in 400ms starts in 400ms instead
of paying 3s.
⚠ **It needs its own short deadline (`scr_gf_load_expect_wait`, 6s) and that is load-bearing.** A
player who left between matches never sends a connect packet, so there is *no signal at all* — the
expectation can never be reached, and a raw wait would pay the **full 20s load ceiling on the most
routine event there is**, making the common case worse than no feature. After the expect deadline the
gate falls back to today's rule. A genuinely returning player reconnects in ~1-3s (they already hold
the map + `mod.ff`), so the deadline is sized to cover that and nothing more.
⚠ Three guards make a wrong count harmless, and all three are required: the expect deadline is
**clamped to `loadDeadline`** (`scr_gf_load_wait` stays the single ceiling), **`humans == 0` releases
unconditionally** (an empty/bot-only lobby never waits on a snapshot of players who all left — this is
also why the count needs no timestamp), and the dvar is **one-shot consumed** (`gf_consumeExpectCount`),
so an abandoned snapshot dies at the next match start rather than leaking into a later match. Gated on
`loadGateOn`, so `scr_gf_load_wait 0` turns it off too.
⚠ **Gate on the COUNT, not the GUID list.** If one player leaves and another joins, the room is equally
ready; identity matching would refuse the substitute for no benefit. ⚠ A human who connects mid-hold and
then drops is subtracted (`humansGone`) or the gate re-stalls after having been satisfied — and that
subtraction reads a **latched** `level.gf_loadGateHuman[i]` flag, set while the entity is still there to
classify, because a kicked *bot* must never shrink a HUMAN expectation.

`scr_gf_lobby`: **0 = Normal** (in-place hold, no restart), **1 = Auto — THE DEFAULT** (release on
load+min, then fast-restart), **2 = Manual** (hold until an admin's START click, then fast-restart;
`scr_gf_lobby_timer` auto-start backstop, default 600s). The fast-restart is **`map_restart(false)`** —
the fresh reset that re-fires full match-start presentation (gun-rack, spawn music, welcome splash);
`map_restart(true)` deliberately suppresses that. The lobby branch **never returns** (`for(;;) wait 1;`
after the restart) so `startGame()` never threads a stale prematch that would survive and stack a double
countdown. The loop-break flag is the **`gf_matchArmed` dvar** (not `game[]`, which `false` wipes): set
before the restart, consumed after so the real match threads its clocks once. Lobby presentation:
desaturated `mpIntro` vision, bodyless overview cam, a custom `gf_lobby_hud` menuDef ("Waiting for
teams N/M"), forced autoassign. ([[gf-stuck-after-prematch-two-gates]])

**Lobby → match team transfer** survives the `false`-restart via dvars: `gf_writeTeamPlan`/
`gf_applyTeamPlan` carry humans by GUID (`gf_teamplan`); `gf_writeBotPlan`/`gf_applyBotPlan` carry bot
**counts** (`gf_botplan`, inert when `gf_fill_n > 0` — the reconciler owns bots then). `gf_applyTeamPlan`
must **yield before its first roster read** (it runs from the tail of `onStartGameType` where
`level.players` is empty). ⚠ A prematch team switch suicides an alive frozen player without restoring
`pers["lives"]`, so `maySpawn` then denies the respawn → "starts round 1 dead"; **`gf_seqTeamMove`'s
restore-life path** owns the fix (its bounded respawn-recovery tail absorbed the old standalone
`gf_reseatRespawn`, deleted 2026-07-16) ([[stock-teamswitch-suicide-no-life-restore]]).
`scr_gf_load_grace` (non-restart path) keeps round-1 grace open for a still-loading straggler.

**Match → match teams (carry + staging) ride the SAME plan pipeline.** Between matches the map change
wipes `pers[]` and ranked connect re-runs `[[level.autoassign]]` for everyone — and a reconnect wave is
never lopsided, so `gf_autoJoinBalance` falls through to stock `menuAutoAssign`, whose equal-counts
branch is `pickTeamFromScores` → 0-0 fresh map → **`randomInt(2)`: a per-player coin flip**.
`gf_team_nextmatch` (`stock`|`keep`|`shuffle`, default stock) puts it under policy: **keep** snapshots
teams at match end (`gf_writeNextMatchPlan`, called from `gf_onRoundEndGame` — stock invokes that
callback at exactly one site, `_globallogic.gsc:985` **after `startNextRound` declined**, so it fires
only when the match is genuinely over and on EVERY end path, including the bridge END ROUND buttons
whose `sd_endGame` bypasses `gf_endRound`) into `gf_teamplan` + the **`gf_teamcarry`** marker;
**shuffle** writes the same-shape plan but Fisher-Yates deals the seated humans onto a random
**balanced** split (`gf_writeShuffledTeamPlan` — fresh teams every match, off-by-1-even by
construction, odd extra on a random side, deliberate spectators left spectating); **`gf_teamstage`** (same `<guid>:<a|x|s>,…`
format, written by the panel's NEXT MATCH staging as ONE raw `set`, no bridge verb) is one-shot and
**wins over both** at the next match start wherever it comes from (map rotate, lobby release, bridge
`matchrestart`). Consumption is `gf_consumeTeamPlan` on the consuming match's first
`gf_waitForLoadingClients` pass — armed branch passes `requireCarry=false` (its plan was just written),
the plain map-load branch `true` (a marker-less plan is stale residue); all three dvars are cleared
there, so an abandoned stage/carry dies at the very next match start. Seating reuses the connect-time
pre-spawn path (no sequenced suicide/respawn, no prematch flicker), composes with the lobby (carried
seating is what the lobby shows; its release re-snapshots), and bots need no plan (the reconciler
re-pads from `gf_fill_n`). Ties can't end a match and a watchdog `map_rotate` writes nothing — both
degrade to stock.

### Pre-match warmup — `g_pregame_enabled` (100% stock, zero mod GSC)
BO1 ships a **pre-match lobby gametype**: a playable no-XP free-for-all on the map while the server
waits for players, which then hands itself off into the real match. It is fully native and we own
**none** of it — we only expose the switch in the RCON panel.

- **How the engine does it:** `BlackOpsMP.exe` carries the dvar **`g_pregame_enabled`** and the
  hardcoded script path `maps/mp/gametypes/_pregame`. When the dvar is set, the engine loads **that
  stock script instead of `<g_gametype>.gsc`** at level load. `g_gametype` still reads `gf` throughout,
  so `level.gameType`, the server browser and the panel all still say "gf". `_pregame::main()` sets
  `level.pregame = true` → `isPregame()` → stock `_globallogic` turns off XP/rank/AAR/leader-dialog and
  skips the prematch countdown. On release it calls the engine builtin **`pregamestartgame()`** (which
  latches `isPregameGameStarted()`, so a between-round `map_restart` does **not** re-enter the warmup)
  + `SetPreGameTeam`/`SetPregameClass` to carry players, then `map_restart(false)` into `gf`.
  ✅ Verified working on the Plutonium dedicated VPS — `set g_pregame_enabled 1` + `map_restart`.
- ⚠ **Read at LEVEL LOAD** → only ever affects the **next** map (same constraint as `xblive_wagermatch`).
  A `map_restart` is enough to trigger it. The panel badges it `NEXT MAP`. Seeded if-empty in
  `gf.gsc onStartGameType` purely so the panel's connect-sweep doesn't get "Unknown cmd".
- **Gate = `party_minplayers`** (NOT `scr_gf_min_players`). Snapshotted at level load, and it counts any
  non-spectator, so **bots count toward it**.
- ⚠ **`scr_pregame_timelimit` must be 0 — and the mod is what makes it so.** Stock `_pregame::main()`
  registers it via `registerTimeLimitDvar("pregame", 5, …)`, which is **seed-if-empty**, so an
  unregistered dvar lands on **5 minutes**; the warmup's `onTimeLimit` then calls
  `_globallogic::endGame`, and on *that* path it never reaches `pregamestartgame()` — the map
  **rotates** instead of starting the match, so an under-populated server just cycles maps every 5 min.
  `gf.gsc onStartGameType` therefore seeds it to `0` (strip-marked, next to the `g_pregame_enabled`
  seed): dvars outlive a map change, so our 0 is already in the table when the warmup loads and its
  seed-if-empty leaves it alone. `dedicated.cfg.example` sets it too, for the boot-straight-into-a-
  warmup case where that callback has never run.
- Known costs of staying stock (accept, or own with a documented reason): the warmup gives **stock
  classes**, not the Gunfight shared loadout; **no mod GSC runs during it**, so the RCON bridge is dead
  and `gf_state` goes stale (watch for `GF-Watchdog`'s `roundStuck` → `map_rotate` if a warmup with
  humans on it outlives `RoundStuckSecs` = 300s); and the `ui_gf_*` **client** dvars survive the map
  load, so a client that was last in a gf lobby renders the `gf_lobby_hud` menuDef *over* the warmup
  (stale "Waiting for the host to start" and all). That overlay is an accident, not a feature — it only
  appears for clients that saw a lobby earlier.

⚠ **Do NOT ship a mod `maps/mp/gametypes/_pregame.gsc`.** One was written and reverted (2026-07-12): the
native path already does the job, and overriding the stock script also means keeping its whole public
surface or the server won't compile — see the `unknown function` rule in the T5 cheatsheet below.

### Team-size mode (large vs small)
`level.gf_largeMode` (re-derived each round by `gf_resolveTeamMode`) is the single flag driving spawns,
the wager-blocker allow-list, the OT flag choice, and which `_large` dvar variant is read.
`scr_gf_teamspawnmode` = `auto` | `large` | `small`. **auto** triggers on **9+ seated HUMANS** (a 5v4
human split or more, `gf_autoLargeFromHumans`/`gf_countSeatedHumans`): bots **never** trigger it, so a
bot-padded 6v6 keeps the tight curated wager spawns and only a genuinely big human lobby opens the map
up (full-map `mp_tdm_spawn`). Each mode reads its own dvar copy (`_timelimit`/`_overtimelimit`/
`gf_capture_time` + `_large`) so flipping never clobbers the other. The health panel's skulls-vs-
`Alive: N` readout is now a **pure HUD decision** (per-team body count > 4, `_gf_hud` + the menu gate) —
it no longer shares a switch point with the spawn mode.

⚠ **Inherent one-round lag:** the spawn mode is a snapshot (`game["gf_autoLargeMode"]`, captured
post-prematch by `gf_updateAutoTeamMode`, applied *next* round) — the 9th human's join opens the map one
round later. By design (a live count inside `onStartGameType` is unreliable — bots/late joiners connect
after it), not a bug. ⚠ Small mode can now hold up to 6 bodies/side on 5 curated points — the curated
picker returns `undefined` when every point is occupied and the caller falls back to the map's own
**`mp_wager_spawn` pool** (telefrag-aware `getSpawnpoint_NearTeam`, in-bounds of the wager play area
by construction — small mode must **never** spawn anyone past the baked blockers, which the
`mp_tdm_spawn_<team>_start` points on wager maps are; those remain the fallback only on maps with no
wager pool, which also have no blockers, so there is no boundary to escape;
[[small-mode-spawn-fallback-outside-wager-blockers]]). Never spawn ONTO an occupied point — the old
raw-cursor fallback telefragged the occupant. Full detail → `docs/REFERENCE.md`.

### Loadout system
Shared random, **deterministic by round index** — every client reads the same
`int(game["roundsplayed"] / roundsPerLoadout) % poolSize`, so sync is by construction (no per-player
roll at give time). `gf_initLoadouts` builds a **53-entry** hand-authored pool once per match
(`game["gf_init"]` gate), Fisher-Yates shuffles it, stores it in `game["gf_pool"]`. Delivery is the
**`level.giveCustomLoadout = ::gf_giveCustomLoadout` hook** — stock `_class::giveLoadout` calls it during
the spawn's loadout build, so there's no `takeAllWeapons` overwrite race (`level.onGiveLoadout` does not
exist in T5). Base perks: no-fall-damage (Lightweight Pro — the speed half `movefaster` is deliberately
**not** granted, the +7% made 42s rounds twitchy), Marathon, Flak Jacket, flash/stun resist. Fast
weapon switch is **not** in the base set (admins add it via `gf_perk_on`).

Per-slot camo via `CalcWeaponOptions` (primary + independent secondary); rolled once at pool build.
Camo only renders on real-base weapons (the crossbow is the one pool secondary that shows it); pistols/
launchers are neutral-base no-ops. Special weapons need `PrecacheItem` in `onPrecacheGameType` or
`GiveWeapon` silently no-ops: `minigun_wager_mp`/`m202_flash_wager_mp` (the `_wager` builds, NOT the
killstreak names — those fire the "called-in" announcer + holster-lock), the `tabun_gas_mp`/
`nightingale_mp` tacticals, and `defaultweapon` (the Finger-Gun easter-egg, a real SP weapon def; icon =
`hud_death_suicide`). See [[special-weapons-precacheitem-and-camo]], [[invalid-weapon-finger-gun-fallback]],
[[reference_t5_mp_weapons]]. Dev aids: `gf_force_loadout`, `gf_force_camo`.

### Team system: size, balance, lock, switching, late spawn (refactored 2026-07-16)
**One round-boundary TEAM reconciler** (`gf_reconcilerInit` in `_bot.gsc`, dev-only) is the single
authority over next-round team composition; BotWarfare's own managers (`addBots`/`teamBots`/
`doNonDediBots`) are **deleted**. **`gf_fill_n` is the per-team TARGET size** (default **2**, clamp 0-6).
Each `gf_boundaryPass` opens with two log-then-repair diagnostics — `gf_teamWatchHumans` (logs any
human stranded in spectator) then **`gf_reclaimStrandedHumans`** (re-seats an UNTRACED-stranded human
onto the lighter side, `gf_team_reclaim` 1; see the open-bug note) — and then runs three stages:
1. **Seat the lock queue** — spectating humans the team-size lock turned away, seated in **join order**
   (`pers["gf_seatQueued"]` = join seq) whenever a seat opens; quiet reassign (they're spectators).
2. **Even the HUMAN split to off-by-1** (`gf_team_balance` 1, default) — the **most recent joiner**
   (`pers["gf_joinSeq"]`, stamped at connect in `_bot::onPlayerConnect` via `gf_joinSeqOf`) on the
   bigger side moves. How it lands is state-dependent and always race-free: not-"playing" → quiet
   reassign now; prematch-frozen → `gf_seqTeamMove` (sequenced suicide→settle→reassign→respawn, life
   restored); killcam survivor → `pers["gf_movePending"]`, consumed in their next **pre-spawn** window
   (the `maySpawn` hook in gf.gsc — same mechanism as `gf_parkPending`). `gf_team_balance 0` = humans
   never auto-moved (for arranged teams).
3. **Bots pad both sides to `T = max(bigger human side, gf_fill_n)`** — humans define the size, bots
   absorb ALL variance, enough humans = **zero bots** (4 humans, target 2 → 2v2 bot-free; 7 humans →
   4v3 humans + 1 bot = 4v4; 1 human, target 2 → 2v2 with 3 bots). Bots only ever sit on the side with
   fewer humans; default difficulty is the hardest (`bot_difficulty fu`, set by `dedicated.cfg` — it is
   an **engine-registered** dvar, so a seed can't own it; see the dvar table). **`gf_fill_n 0` = no
   bot fill** (stages 1-2 still run; manual per-team bot add/kick/move sticks).

**Team-size lock** (`gf_team_lock`, default 0): `gf_fill_n` becomes a hard **HUMAN** cap per side — a
joiner finding both sides full spectates, **queued in join order**, auto-seated at the next boundary
when a seat opens. Bots never count against the lock (a joining human displaces a bot, never spectates
because of one). Inert at `gf_fill_n 0`.

**Immediate self team-switching** (`gf_team_switch`, default 1): the `level.allies/axis/spectator` menu
handlers are wrapped (`gf_menuAllies`/`gf_menuAxis`/`gf_menuSpectator` in `_gf_rounds.gsc`, installed
each round next to the autoassign override, stock saved into `level.gf_stock*`). Dead/spectating players
re-seat instantly (and may late-spawn); an **ALIVE mid-round switcher dies and sits out the round**
(their life is spent — `maySpawn` gate A enforces the sit-out); during prematch/grace the switch is free
(life restored + respawned). `gf_team_switch 0` = self-switching refused (admin moves still work). Lock
capacity is enforced on self-joins; **admin moves bypass the lock** (admin intent wins).

**Mid-round late spawn** (`scr_gf_latespawn`, default 1): a player/bot may make their **first** spawn
into a LIVE round while their team still has **≥1 alive** — never during overtime (stock `inOvertime`
still blocks), never a respawn (gate A untouched). Implemented in the `maySpawn` hook: it pre-sets
`self.hasSpawned = true` to satisfy stock gate B (`!inGracePeriod && !hasSpawned`), which is the gate
that exists to deny exactly this. Covers joiners, spectators picking a team, and admin force moves.
⚠ **There are exactly two ways in, and both preserve the round's team SIZE** (`gf_lateSpawnAllowed`):
1. **Fill a gap** — the spawn leaves its team no bigger than the enemy's (`mine + 1 <= other`, by
   **roster**, not alive: one life per round means a team that lost players is still "N for this
   round", so treating its dead as a gap would hand it free bodies mid-fight). Open to anyone,
   **bots included** (3v2 → 3v3 after someone leaves).
2. **Take a bot's spot — HUMANS ONLY.** A human never waits a round for a seat a bot is keeping warm:
   the spawn is admitted and that bot is removed (via the fill-discipline gate's seat priority — see
   below — which covers the countdown/grace too), so the size is unchanged. A **bot never displaces
   anyone** to get in. A team full of *humans* has no spot to take → the joiner waits for the
   boundary (a human may take a bot's spot, not another human's).

The gap rule is load-bearing **for bots**: the reconciler's adds are staggered 0.5s apart
(`gf_addFillBots`) and `gf_matchStartPass` waits for a QUIET roster — which a human's join *resets* —
so its pass can fire mid-round and add bots. Stock's gate B used to park all of those in spectator
harmlessly; admitting them unconditionally ran rounds over the target (the "it kept all 4 bots /
rounds starting with an extra bot" regression).

**FILL DISCIPLINE — the spawn-gate half of the size policy (`GF_FILLGUARD` + seat priority).** The
boundary pass only *plans* the composition; the `maySpawn` hook *enforces* it at the one door every
client passes through, size = `max(bigger human side, gf_fill_n)`. Two halves:
- **Bots:** a bot may not spawn when its side already holds the size — it is quiet-parked at its
  spawn attempt and logged (`GF_FILLGUARD: parked bot <name> - <team> already at size N (round R)`),
  so an over-size round is structurally impossible whatever mis-seated it (a stock autoassign
  landing, a menu-response race). Denials cascade correctly (each park flips pers, so the next bot's
  count drops — a side never over-parks).
- **Humans — seat priority, never denied:** a human spawning onto a side already at size that still
  holds a bot **displaces a bot** (`gf_displaceBotForHuman`). This runs on EVERY admitted human
  spawn — **including the prematch countdown and grace**, where stock admits directly and the
  late-spawn path never runs (without it, a countdown join onto a 2-bot side STACKED to 3 bodies —
  live repro 2026-07-16). A dead/unspawned bot is quiet-parked; an alive/frozen one takes the
  **sequenced suicide-park** (`gf_seqTeamMove("spectator")` — stays connected and reusable; the old
  kick threw away a client the reconciler would just re-add). ⚠ The maySpawn trigger is only a cheap
  **pre-filter**; the displacer **recomputes the real over-size at apply time** (`gf_targetRoundSize`,
  the shared formula) and trims **only the genuine excess** — one-bot-per-call was WRONG. During the
  size-bump / fill churn the roster is transiently over-counted (a fill bot momentarily on this side
  before it's steered away), so an unconditional removal killed a REAL bot for a phantom seat and
  dropped a correct 3v3 to 3v2 at random (live repro 2026-07-16). If the team has settled back to
  size, `over <= 0` and it removes nothing. Also safe against denied spawns (re-checks the human
  actually spawned). `.gf_displacePending` claims prevent two same-frame humans picking one bot;
  stale claims are wiped each boundary pass.

`gf_fill_n 0` (manual bot mode) disables the whole gate so a deliberate 3v1 bot setup sticks. Born
from a live 2026-07-16 listen-server repro: a parked displaced bot ended up seated on the enemy side
next round via a path the reconciler provably didn't take (its math planned zero moves for that
state) — watch for the GF_FILLGUARD line to identify it. ⚠ `gf_displaceBotForHuman` **must run after the
human's spawn commits** — removing a team's last alive client mid-round reads as a team wipe
(`onDeadEvent` → the round ends early) — and re-checks state, since `maySpawn` is only a predicate and
the spawn it green-lit may never have happened. It prefers a **not-playing** bot (quiet park — the
free primitive); an **alive/frozen** bot takes the **sequenced suicide-park** (`gf_seqTeamMove` to
spectator — stays connected and reusable; never a kick, never a raw stock switch). Accepted:
replacing a dead bot lifts the team's alive count by one, replacing an alive one is a pure swap —
both keep the roster identical, which is the invariant that matters.

**⚠ The sequenced team move (`gf_seqTeamMove`, `_gf_rounds.gsc`) is the ONLY way to move a "playing"
player.** Stock `menuAllies`/`menuAxis` suicide() asynchronously and drive the respawn in the same
frame; racing that (the old stock-switch + `gf_reseatRespawn` recovery pair — both now deleted) was the
root cause of the rare "**spawned at the enemy spawns / spawned with 1 HP**" bug after team moves. The
primitive sequences suicide → wait for death to settle (bounded ~2s) → quiet reassign (also clears
`pers["savedmodel"]` — a stale one renders the wrong team's skin) → then drives the respawn. The bridge's
`gf_applyTeamMove` (pteam/pteamforce), the lobby plan's `gf_planApplyMove`, the menu wrappers, and the
balancer's prematch moves all route through it. `pteamforce_` on an alive player = **die + late-spawn**
onto the new team (round rules permitting).

**Human-joiner steering at connect** (`level.autoassign = gf_autoJoinBalance`): any human split with a
lighter side → seat it; **only EXACT parity** falls through to the stock pick (players can still squad
up when the choice is free). Lock-aware (both sides full → spectate + queue; one side full → the open
side), and an ALIVE player picking Auto Assign routes through the sequenced move. Still the single
delegate for the lobby→match transfer plan (`gf_autoassignPlanned` fallbacks reach saved *real* stock —
no recursion). Both seating paths share **`gf_seatBalancedJoin`** so they cannot drift.
⚠ **The parity bound is load-bearing, and so is the UNPLANNED-joiner path.** It used to be `diff <= 1`
→ stock, and `gf_autoassignPlanned`'s "fresh joiner not in the plan" branch used to be a **bare** stock
autoassign. Both let a coin flip turn a legal 1-gap into a 2-gap — and because bots pad to
`max(bigger human side, gf_fill_n)`, a 2-gap becomes "N humans vs N-1 humans + a bot" for the **rest of
the match**, which reads to players as "the teams were never balanced" even though the head count is NvN.
⚠ **Steer an unplanned joiner against the PROJECTED split (`gf_planProjectedHumans`), never a live
head-count** — at the match-start re-begin wave clients reconnect one at a time, so an early joiner sees
0/0 and calls it parity no matter how lopsided the plan is. Count the **plan entries** (+ already-seated
humans the plan doesn't name); a stale entry costs at most a 1-gap, which the boundary evens.
([[unplanned-joiner-coinflip-opens-two-gap]])

**Boundary-only remains the rule** — ONE yield-free `gf_boundaryPass` per round, triggered by:
`gf_round_over` +0.5s (inside the killcam), the match-start gate release (pre-spawn; the Auto/Manual
lobby-release instead kicks all bots pre-restart when fill > 0), and one roster-settle pass after init
(these now run **even at fill 0** — balancing/queue are fill-independent). Bot placement is the quiet
`gf_botQuietSetTeam` (⚠ seating on a real team **restores `pers["lives"]`** — a suicide-parked bot
redeployed the same round otherwise sits DEAD all round, maySpawn gate A;
[[prematch-parkpending-defers-a-round-and-lifeless-redeploy]]); surplus alive bots: **prematch-frozen →
immediate sequenced suicide-park** (a `parkPending` there would defer past the whole round AND make the
displacer count the bot as retired — the Berlin Wall 2v3), mid-round survivors defer via
`pers["gf_parkPending"]` → `gf_lobbyMaySpawn`; adds
are staggered + generation-stamped (`level.gf_fillGen`) with `.gf_fillPending` steer marks; displaced
bots park in spectator (reserve capped at live human count; `gf_fill_kick_floor` kicks before
`sv_maxclients`). Counts key off `level.players` + `istestclient()`, never `level.bots`. Every
persistent bot loop carries `endon("bot_reinit")`. Full detail →
[[gf-fill-reconciler-and-team-transfer]], `docs/DEV.md`.

⚠ **`gf_boundaryListener` must NOT carry `endon("game_ended")`** — that notify fires at the end of
**every round**, not at match end (`endGame` runs yield-free to it, and `gf_endRound` threads `endGame`
in the same frame it notifies `gf_round_over`). Paired with the **once-per-match** `_bot::init` gate
(`game["gf_botInit"]`, `gf.gsc`), the endon killed the listener at the first round end and nothing ever
re-threaded it: **the boundary pass never ran at a boundary**, the fill froze at whatever
`gf_matchStartPass` left, and humans joining later were never counted → a side sat at N bots + humans
forever ("bot fill ignores humans"). `bot_reinit` is the only notify allowed to tear these down; the
final round is skipped by `gf_matchIsOver()`. `gf_gateListener` keeps the endon **deliberately** (dying
at round 1's end is what confines it to the match-start gate, since `gf_load_gate_reset` also fires every
round) — read a thread's intended lifetime before touching its endons.
([[game-ended-fires-every-round-end]])

### HUD (menu-layer)
All mod HUD is rendered in the **menu layer** (`ui_mp/hud_gf_health.menu`, in `mod.ff`), NOT client
hudelems, because T5 has an invisible per-client **DRAWN render cap (~17-20 elements)** shared across
*all* hudelem types; the old client-side panel blew past it and silently starved the score popup and OT
flag ([[settext-configstring-exhaustion]]). The server pushes `ui_gf_*` client dvars on-change; menu
itemDefs read them via `exp material(dvarString())`, `exp rect`, `exp forecolor A`, `visible when(...)`.
Materials **must** be dynamic `material(dvarString())` — a static `background "hud_..."` makes the linker
try to bundle the `.iwi` → build error.

- **Health panel:** two rows (row 0 = friendly green, row 1 = enemy red), each an HP number + bar +
  EITHER up to 4 skulls (both teams ≤4) OR an `Alive: N` readout (either team >4). The skull/readout
  mode (`ui_gf_hp_mode`) is shared so both rows switch together — this **is** the small/large coupling
  threshold. Each skull slot is two itemDefs (alive team-colour + dead white) because forecolor RGB
  isn't exp-drivable, only alpha. ⚠ `gf_getTeamHealthStats` counts spawned-this-round pers-team
  members but must SKIP bodies on their way out (`.gf_displacePending` / `gf_parkPending`) — a
  displaced bot's pers lies for the ~2s its suicide-park settles, and a panel seeded mid-churn showed
  "3 players / 300" on a 2-human team ([[health-hud-counts-mid-displacement-bodies]]).
  ⚠ **`Alive: N` reading LOW is almost never a HUD bug — check `scr_team_maxsize` first.** The
  readout is exact at any team size (both stats are plain sums), so a team that "should" be 7 and
  reads 6 usually means the 7th was **benched by the cap** — the tell is `GF_TEAMTRACE: … ->
  spectator by maxsize` plus a `GF_TEAMWATCH … reason maxsize` on the same player each round (live
  2026-08-13, `mp_golfcourse`, cap 6). The second, by-design reason is the `gf_spawnedRound` gate:
  a player team-assigned but not spawned into THIS round is excluded deliberately, so a mid-round
  joiner appears next round. Neither is fixed in `_gf_hud`.
- **Self health bar**, **loadout overview** (icons via `ui_gf_lo_*`; 3 hardcoded perk icons; the
  equipment row's three columns each carry their own gate — `ui_gf_lo_show2`/`3`/`4` — for a `"none"`
  equipment loadout or an admin slot switch, hiding icon+name only so the bracket doesn't reflow), and two
  separate menuDefs — **pregame lobby** (`gf_lobby_hud`) and the admin **pause banner** (`gf_pause_hud`,
  "MATCH PAUSED", gated on `ui_gf_paused`) — both gated `!BIT_IN_KILLCAM` not `BIT_HUD_VISIBLE`
  (the lobby cam clears hud_visible, and a pause can land in a state that has too).
- **Kill/score popup:** renders "+1 Kill"/"+1 Assist" on its own `NewScoreHudElem` (`self.gf_popupElem`,
  a separate pool from the ~17 cap), styled to match the stock yellow popup; the engine's own
  `hud_rankscroreupdate` is parked offscreen each spawn so stock "+N" XP pushes can't race ours.
- **Killing-blow hitmarker (red):** the T5 hitmarker is a **stock GSC hudelem**, not engine-drawn —
  `_damagefeedback::onPlayerConnect` makes one `.hud_damagefeedback` per client and only ever
  re-`setShader`s + fades it. So `gf_onPlayerDamage` just writes `.color`: red on the shot that kills,
  white on everything else. **Adds no element** (nothing against the ~17-20 drawn cap), no reliable
  command, no `mod.ff` rebuild. Three load-bearing facts: `level.onPlayerDamage` fires at
  `_globallogic_player.gsc:741` and stock flashes the marker at `:968` (so our write lands first);
  **`setShader` does not clear `.color`** (stock relies on that in `_hud_util::createPrimaryProgressBar`);
  and `self.health` is still pre-damage there while Body Armor's −20% already came off at `:677`, so
  `iDamage >= health` is an accurate kill test despite the base-set `specialty_armorvest`.
  ⚠ The white `else` branch is **not** cosmetic tidiness — `.color` persists on the element, so every
  marker-drawing hit re-stamps it (a **same-frame co-hit of a killing blow** is the one sanctioned
  exception) or the last kill's red rides along. That is also why the block sits **above** the
  same-team return: stock draws a marker for friendly fire too (`:948` only excludes self-damage).
  ⚠ **Both damage-frame colour writes are deliberately BARE — never arm a fade window in the damage
  frame — and the kill's colour is made to stick by a one-frame-later thread.** `fadeOverTime` arms an
  interpolation over the hudelem's **whole RGBA**, not just alpha, and stock leaves a **1s** fade
  running after *every* hit — so a bare `.color` write CROSSFADES while that fade is in flight (a body
  shot followed by the kill inside the second rendered **pink**), `fadeOverTime( 0 )` does **not**
  cancel the interpolation (tried live; stock passes `0` **nowhere** in `raw/maps/mp`), and ⚠ the
  seemingly-right fix — riding each write on a real `fadeOverTime( 0.05 )` window — **killed the white
  markers outright** (live 2026-08-09): stock's `:968` flash runs two statements later in the SAME
  frame, its `alpha = 1` folds into the still-live window using the marker's CURRENT alpha (0 when
  idle) as the base, and its own `fadeOverTime(1)` + `alpha = 0` then bury the flash — the marker never
  reaches visible alpha. So the damage-frame writes stay best-effort bare (instant on an idle marker),
  and **`gf_snapKillMarkerRed( killAt )`** makes the KILL colour stick: one frame later — a quiet frame,
  where a private `0.05s` window is safe — it re-snaps the red, then the frame after **re-arms stock's
  flash** (`alpha=1; fadeOverTime(1); alpha=0`); the re-arm is mandatory, the snap re-times the
  in-flight **alpha** fade too and the marker would otherwise blink out instead of fading over its
  second. The **kill stamp** (`gf_redMarkerAt`, the kill's `gettime()`) scopes red priority to the
  killing blow's **own frame**: a non-lethal co-hit with equal `gettime()` skips the white re-stamp
  (cures the shotgun caveat — a trailing pellet of the killing blast no longer whitens the marker, in
  either pellet order), while a white in any LATER frame re-stamps immediately **and clears the
  stamp** — fresh feedback on a new target beats the old kill's flash, and a dead victim fires no
  damage events, so only same-frame co-hits can belong to the kill. The stamp doubles as the snap
  thread's **generation token**: cleared or restamped, the mismatch retires the thread so it never
  paints red over a marker that has moved on. ⚠ **Fourteen stock files flash this same element
  WITHOUT passing through `Callback_PlayerDamage`** — reachable in Gunfight: the equipment family
  (`_weaponobjects` claymore/C4, `_cameraspike`, `_scrambler`, `_tacticalinsertion`,
  `_acousticsensor`) — so the hook's white re-stamp never sees those hits, and the persisted `.color`
  made shooting enemy equipment flash red indefinitely after a kill. No hook exists on those paths
  (and overriding 5 stock files is not on), so the coverage is inverted: the snap thread's **step 3
  restores the element's resting colour to white** ~1.15s after the kill (bare write, invisible at
  alpha 0, token-guarded) — red's reign is exactly the kill flash's second, and every untracked
  flash path defaults back to white after it ([[hudelem-fadeovertime-lerps-color]]).

⚠ **Every `setClientDvar` is ONE reliable server command, and the client's ring buffer for them is
FIXED (`MAX_RELIABLE_COMMANDS`).** Blowing it produces **two different client `Com_Error` disconnects —
the same disease, detected at opposite ends**: **`Server command overflow`** (the *server* sees a client
stop acking and its outgoing queue overrun) and **`CL_CGameNeedsServerCommand: a reliable command was
cycled out`** (the *client* received everything but cgame reached for a command already overwritten in
its own ring). ⚠ **Never chase the second as a new bug** — both mean *too many reliable commands in a
window where the client isn't executing them*. That needs a **burst** *and* a **frozen** client, which is
why the one place it bites is the Auto/Manual **lobby START**: `map_restart(false)` stalls every client
while it re-inits, and the push burst lands inside that stall. **The fix is `setClientDvarS` (plural)** —
the stock variadic builtin that carries every name/value pair in a **single** command (stock:
`_globallogic_player.gsc:91`; 9 pairs in one call at `_zombiemode_challenges.gsc:217`). The spawn burst is
batched into groups of ≤8 pairs, taking it from **~45 commands/human to ~12**; `gf_pushHealthRow` pushes
its whole row as one command whenever *any* of its 5 values changes (fewer commands than the old per-dvar
path on **both** the spawn burst and the 0.1 s in-firefight loop — re-sending an unchanged pair inside a
batch is free; it's the command **count** that is scarce).
⚠ **A `grep setClientDvar` audit is NOT enough — hunt the O(n²) call: a loop over players containing a
loop over data.** That is what the first batching pass missed. `gf_lobbyRosterLoop` pushed `pcount` **plus
one command per occupied name slot, per human, per roster change** — the only stream in the mod whose cost
scales with player count, sitting *in the lobby*, the tightest window there is. It compounded with the bot
fill (the reconciler adds on a 0.5s stagger; the loop ticks at 0.5s → ~one roster change **per bot**), so a
12-bot fill cost **~156 reliable commands per human** — over the ring on its own. Now padded to the 12 fixed
slots and pushed as flat batched groups (1 command for a ≤6 lobby, 2 for 7-12).
⚠ **Never expand a batch back into individual pushes**, and never add an unbatched per-player push loop.
`gf_hudRevealStagger` spreads what's left across frames — it is a complement to the batching, **not** a
substitute. ⚠ **Our share is not proven to be the dominant one**: `map_restart(false)` also makes the engine
re-send configstrings (themselves reliable commands) and the bot kick-all fires immediately before it. If
"cycled out" recurs, the next lever is to **stop churning bots across the restart**, not to shave more mod
pushes ([[server-command-overflow-reliable-command-budget]], [[connection-interrupted-mitigations]]).
⚠ **A GSC dvar animation is a reliable-command STREAM** — `gf_slideLoadout` pushes one *batched* command
per 0.05 s step for the whole duration (the 0.5 s loadout outro = **~13** commands/human/round, halved
from 26 by batching the off+alpha pair; the intro snaps; `gf_fadeDvar` is currently dead code). ⚠ **Kept on
purpose:** the slide reads better than a pop, and it fires ~8 s into the round, mid-gameplay — NOT in the
`map_restart(false)` lobby-START stall where the overflow bites (a burst AND a frozen client), so it is a
*purity* cost, not a live-problem cost. Batching is the floor here, not the fix: an animation is a stream by
construction. The zero-cost "menu owns the animation" end-state is **RESOLVED UNVIABLE**
([[menu-milliseconds-client-local-no-per-round-event]]): `milliseconds()` in an `exp` is the **client's
UI-realtime clock, not server `cg.time`** (`raw/ui/main.menu` scrolls fog with it pre-connection), so the
server can't stamp the marker; stock only stamps it client-side in a menu's `onOpen` (`exec "setdvartotime"`),
and our always-loaded `loadMenu` HUD has no per-round client event to do so (no `onDvarChanged`; `openMenu`
steals focus). Don't re-open it or burn a `mod.ff` probe — settled.

Menu **structure** changes need a `mod.ff`
rebuild; dvar values/positions are GSC-tunable. The loadout intro snaps (snap-in); only the loadout outro
animates (`gf_slideLoadout`). Related: [[menu-rendered-loadout-overview]]. Full ui_gf_* map →
`docs/REFERENCE.md`.

### Damage scoring, friendly fire, flinch, vision
- **Score = total damage dealt** (`gf_onPlayerDamage`), capped per hit at the victim's current HP (no
  overkill inflation), pushed silently (bypasses the stock rank-popup so score doesn't flash each hit).
- **Rank XP is ~5× stock and lives ONLY in `registerScoreInfo`** (`gf.gsc onStartGameType`): **kill 500**,
  **headshot 150** (stacks on the kill → 650 on a headshot kill), **assist 200** (the flat tier
  `gf_onPlayerKilled` pays every damager; the `assist_25/50/75` tiers are registered but unreachable),
  **capture 500** (OT flag — wired, see below), and the win/loss/tie **match-bonus
  scalars 5 / 2.5 / 3.75** (stock 1 / 0.5 / 0.75 — these are multipliers on stock's
  `scalar × (timeLimit × SPM) × timePlayedFrac`, not flat XP). XP and score are **fully decoupled**:
  `level.overridePlayerScore = true` makes `_globallogic_score::givePlayerScore` return on its first line, so
  no XP value can ever reach the damage scoreboard, and the stock "+N" popup is killed by `self.enableText =
  false` (per spawn) — **not** by the values, which is why they're safe to be non-zero.
  ⚠ **`scr_xpscale` is READ-ONLY on Plutonium T5 — it is not an XP lever.** rcon *and* `dedicated.cfg` both
  get `Error: scr_xpscale is read only` (proven live; that boot error in `console_mp.log` is our own cfg line
  being rejected), so it is pinned at **1** forever. The only script-side equivalent is assigning
  `level.xpScale` after `_rank::init` — we don't; the `registerScoreInfo` values *are* the knob.
  ⚠ **Kill XP flows from `Callback_PlayerKilled` → `giveKillStats`, NOT from our `level.onPlayerKilled` hook**,
  so it needs no wiring. **Assists do** — `gf_onPlayerKilled` must call `_rank::giveRankXP("assist")`
  **directly**, because stock's assist/capture/defend XP all routes through the dead `givePlayerScore` path.
  The OT flag capture is wired the same way — `gf_awardOvertimeCapture` (`_gf_rounds.gsc`) calls
  `giveRankXP("capture")` directly (500), because stock's capture score path is equally dead under
  `overridePlayerScore`. ⚠ The end-of-match bonus is gated on `game["timepassed"]`, which only accrues while
  `!level.timerStopped` — and our round clock holds `pauseTimer()` all round ([[paused-timer-freezes-gettimepassed]]),
  so it may never fire. **Unverified** (`logString` output does not reach `games_mp.log` on this server, so the
  log can't answer it) — combat XP above is deliberately the load-bearing path.
- **Friendly fire is 100% stock** — the mod GSC sets no FF dvar. It's owned by the RCON panel writing the
  stock tweakables `scr_team_fftype` (base) + `scr_gf_team_fftype` (per-gametype override the engine
  re-polls ~5s). FF damage is applied by the engine but never scored. ([[t5-tweakable-override-dvars-live]])
- **Flinch — ONE lever now: `scr_gf_flinch`, shipped at 0.5 = half stock kick.** It is a straight
  multiplier on `bg_viewKickScale` (stock 0.2), so 1.0 really is stock and 0 really is none.
  ⚠ **The second lever was a PERK, and it was 5× stronger than the dvar.** `specialty_bulletflinch`
  (Hardened Pro) gates the engine's **`perk_damageKickReduction`**, whose registered default `0.2` is the
  fraction of kick **REMAINING** — an **80% cut** — not the fraction removed (stock's own custom-games perk
  editor maps its `"80%"` label to the value `0.2`: `ui_mp/custom_specialty_editor.menu`). Plutonium ships
  `g_fix_damageKickReductionPerk 1`, so it genuinely applies. It was in the **base set**, so the live VPS
  ran `0.2 × 0.5 × 0.2` = **10% of stock flinch** ("flinch feels like zero"), and `scr_gf_flinch` could not
  have restored stock even at its clamp ceiling of 3 (that only reaches 60%). The perk now rides in the
  **sniper/heavy package only** (those 10 loadouts take a further 0.2×), where flinch resistance is a
  deliberate class trait. ⚠ **Never put `specialty_bulletflinch` back in the base set** — it silently
  turns `scr_gf_flinch` into a lie. ⚠ Hardened Pro is **two** tokens (`specialty_armorpiercing` +
  `specialty_bulletflinch`); the package used to carry only the base `specialty_bulletpenetration`, so
  granting "Hardened Pro" means adding the flinch token explicitly
  ([[hardened-pro-flinch-perk-multiplier]]). `gf_applyFlinch` re-applies it every round. ⚠ **`bg_viewKickScale` does NOT replicate** — each client
  scales its own damage view kick from its LOCAL copy, so the server-side `setDvar` alone changes nothing
  for anyone on a dedicated server (it only ever appeared to work on a listen host, where the host *is* a
  client). So the value is **pushed per-client**: to live humans in `gf_applyFlinch`, and per-spawn via
  `gf_applyFlinchClient`, which pushes **unconditionally**. ⚠ **There is deliberately no skip-at-stock
  shortcut**: the old code returned early at `scale == 1`, which only *looks* harmless at a 0.5 default (we
  push anyway) — that is how it survived — and at a 1.0 default it would mean the server never pushes at
  all. `bg_viewKickScale` is a plain client dvar a player can set in their own autoexec, so anyone running
  `bg_viewKickScale 0` would take **zero flinch while everyone else takes the full kick**. The
  unconditional push is what makes the server's value authoritative. Session-only; `bg_viewKickScale` is
  not a saved client dvar. ⚠ The two `gf_cfgFloat` defaults (`gf_applyFlinch` + `gf_applyFlinchClient`)
  must stay in lockstep — the seed is seed-if-empty, so a drift is masked by whichever ran first.
  ([[flinch-bg-viewkickscale-not-replicated]])
- ⚠ **Every `perk_*` dvar is a MAGNITUDE; the matching `specialty_*` perk is its GATE.** The engine (or
  `_class.gsc`) only consults the dvar for a player who **has** the perk — they never "fight", but a
  slider whose gate nobody holds is a **dead control that silently does nothing**. Scopes:
  `perk_sprintMultiplier` (Marathon) and **`perk_weapMeleeMultiplier`** (Steady Aim Pro's
  `fastmeleerecovery`) are **BASE** — live for everyone. `perk_weapSwitchMultiplier` / `_weapReloadMultiplier` /
  `_sprintRecoveryMultiplier` / `_weapSpreadMultiplier` are **SNIPER/HEAVY only** (10 of 53 rounds).
  **`perk_speedMultiplier` is DEAD by default** (gate `movefaster` no longer in the base set — opt back in
  via `gf_perk_on`), **`perk_weapRateMultiplier` is DEAD** (gate `specialty_rof`, granted by nobody), and
  **`perk_weapAdsMultiplier` is DEAD** for the reason below.
- ⚠⚠ **A `perk_*` multiplier's REGISTERED DEFAULT *is* the perk's effect — and `1.0` is NOT "stock", it is
  the WORST value.** Live-read defaults: `weapReload`/`weapAds`/`weapSwitch`/`weapMelee` **0.5**,
  `weapSpread` **0.65**, `weapRate` **0.75**, `sprintRecovery` **0.6** — all with a domain that **CAPS AT 1**.
  So 0.5 = "the action takes half as long", and setting 1.0 **silently disables the perk's benefit**. Two of
  these run the other way: `sprintMultiplier` (default **2**, domain 0-3) and `speedMultiplier` (**1.07**,
  0-5) are *higher = more*. ⚠ The panel shipped `def:'1.0'` + ranges to 2.0 on all eight — its Reset button
  was **disabling** the perks it claimed to tune, and every value >1 it offered was **rejected by the
  server** (which reads as "the dvar is broken"). Fixed. **Never re-guess a default here — read it off the
  running server** ([[perk-multiplier-defaults-are-the-effect]], [[read-the-server-not-the-file]]).
- ⚠ **`specialty_fastads` NEVER STICKS — it is a dead perk.** Proven live with `pperkdump_<num>`: with
  `gf_perk_on` listing 7 perks, **6 land on every player and `fastads` never does**, while 11 other perks
  set in the same loop all do. It is a real engine token (used by stock `shrp.gsc`) and nothing unsets it —
  root cause unknown. Consequences: **Sleight of Hand Pro cannot be granted**, and `perk_weapAdsMultiplier`
  is a dead slider. It still sits in the sniper/heavy package doing nothing; leave it until the cause is
  found (removing it would delete a real effect if `hasPerk` — not `SetPerk` — turns out to be the liar).
- **`g_fix_viewkick_dupe` is INERT on T5 MP — it was never the second flinch multiplier.** (The real one
  was a **perk**: `specialty_bulletflinch` → `perk_damageKickReduction` 0.2×, now out of the base set —
  see Flinch above.) With that perk gone, `scr_gf_flinch` is the only *global* flinch knob and `0.5` →
  `bg_viewKickScale 0.1` is exactly half stock. This file previously claimed
  the dvar doubled felt flinch, on the strength of it *appearing* in the `console_mp.log` dump — which
  proves nothing, because a cfg-created dvar appears there too. A **live RCON read** settles it: the real
  fixes carry a typed domain and a fixed registered default (`g_fixBulletDamageDupe` → `is:"1"
  default:"0" Domain is 0 or 1` — the default stays `0` even though we set `1`), whereas
  `g_fix_viewkick_dupe` → `is:"1" default:"1" **Domain is any text**`, i.e. its "default" merely mirrors
  the value **our own cfg** set. The engine never registered it (Plutonium filed that fix under **SP**).
  Setting it is harmless but does nothing. The panel row is kept, labelled `(INERT)`, so a future
  Plutonium build that *does* register it is easy to spot. ([[engine-dvar-defaults-from-log-dump]])
- **Jump fatigue is OFF** (`scr_gf_jump_fatigue`, default 0 — shipped, public build included). "Jump
  fatigue" is the community name for the engine's **`jump_slowdownEnable`** (stock `1`): every jump drags
  your movement speed, so consecutive hops decay. 42s rounds on wager-sized maps live on short
  repositioning hops, so the stock drag punishes exactly the movement this mode is built on. There is no
  dvar *named* fatigue — the whole engine family is `jump_height` / `jump_slowdownEnable` / `jump_spreadAdd`
  / `jump_stepSize` / `jump_ladderPushVel`. `gf_applyJumpFatigue` (`_gf_rounds.gsc`) re-applies it every
  round; RCON bridge `jumpfatigue_<0|1>`. No per-client push (the `jump_*` family replicates — it must,
  movement is client-predicted), which is what makes it *unlike* flinch.
- **Unlimited sprint is OFF** (`scr_gf_sprint_unlimited`, default 0 — Marathon is already in the base perk
  set). ⚠ **`player_sprintUnlimited` is a CLIENT dvar** — `player_*` is client-predicted movement, the same
  ownership class as `bg_*`, **not** the replicated `jump_*` family. It is owned exactly like flinch:
  `gf_applySprintUnlimited` (every round, from `onStartGameType`) sets the server copy — the server's own
  movement sim reads it, and a client predicting unlimited sprint against a server that limits it
  rubber-bands — and `gf_applySprintUnlimitedClient` pushes it per human **every spawn**. RCON bridge
  `sprintunlimited_<0|1>`. ⚠ **Never `set player_sprintUnlimited` directly** (cfg or rcon): stock's *only*
  client push is `_globallogic_player::Callback_PlayerConnect`'s
  `if (GetDvarInt(#"player_sprintUnlimited")) self setClientDvar(..., 1)` — it fires **at connect only**
  (it does re-run on `map_restart`, so per-round in practice) and it is **one-way**: stock can turn
  unlimited sprint **on** and can *never* turn it back **off**, so a client handed a 1 keeps it for its
  whole session. That one-way connect push is why the old panel toggle looked like it randomly stopped
  working. ⚠ Unlike `gf_applyFlinchClient`, the per-spawn push has **no skip-at-stock shortcut** — skipping
  at 0 would strand a client that was given a 1 earlier in the session.
- ⚠ **CHEAT PROTECTION IS A *CLIENT-SIDE* CHECK — an rcon / `dedicated.cfg` `set` on a dedicated server
  is NOT gated by it.** This is the opposite of what this file and `_gf_bridge.gsc` used to say, and the
  mistake cost a whole wrong "fix": the familiar `Error: jump_height is cheat protected` spam comes from a
  game **CLIENT** exec'ing the stock `default_xboxlive.cfg` at boot — *not* from a server refusing you.
  The `DVAR_CHEAT` flag bites wherever the console belongs to a client: a player's own console, a client
  exec'ing a cfg, and a `setClientDvar` **arriving** at a client. The **dedicated server's own console
  (rcon + `dedicated.cfg`) is not gated**, so `jump_height`, `bg_fallDamage*`, `bg_gravity`, `g_speed`,
  `timescale` etc. are all settable there with a plain `set`, `sv_cheats 0` and all.
  **Proven live on the VPS 2026-07-12** (`sv_cheats 0`, `dedicated` = "dedicated internet server"):
  rcon `set ragdoll_explode_force 18001` — a dvar on the engine's *own* cheat-protected list — read back
  as `18001` (then restored to 18000). Control in the same session: `set bg_gravity 0` (domain starts at
  1) **did** echo its rejection back and kept 800 — so error echoes genuinely reach the panel, and the
  silence on the accepted writes was a real accept, not a swallowed reply.
  ⚠ **What IS unreachable on a dedicated server** (and the only thing the panel is right to grey out) is
  a **cheat-protected CLIENT dvar** — the `r_*` Visual Tweaks — because those ride `setClientDvar` and the
  *client* re-checks on arrival; plus **archived/saved** client dvars (`cg_fov`, `bg_viewBobAmplitudeBase`),
  which Plutonium refuses to let a server write at all.
  ⚠ So **do not route a server dvar through the bridge's `svset_` on the theory that rcon cannot reach
  it** — rcon can. `svset_` survives for two narrower reasons: the **listen/dev host**, where the panel's
  rcon lands on a console that *is* a client's (that is the setup where `set bg_viewKickScale 0.9` was
  once seen refused, which is what seeded the whole misconception), and its `gf_<dvar>` mirror, which
  buys cfg-persistence for free.
- **Reading engine-dvar defaults:** the dvar dump in `console_mp.log` is the cheapest way to prove a dvar
  is engine-registered at all — a `set` on a name the engine never registers creates a user dvar that
  looks real in every dump and is read by nothing. ⚠ **What it prints is NOT reliably the default.** This
  file long claimed "registered defaults, never live values" (`g_inactivity` 190 vs our cfg's 300;
  `sv_maxclients` 4 vs 14) — **the live VPS log on 2026-08-13 says the opposite**: the first dump sits
  *after* `execing dedicated.cfg` and reports the cfg's own values (`g_inactivity "300"`,
  `sv_maxclients "14"`, `sv_timeout "240"`), plus `g_gametype "gf"` and the GSC-seeded
  `scr_gf_flinch "0.5"`, neither of which has a registered default that could read that way. So treat a
  dump value as **live state at that map_restart** (which makes the per-round dumps a free timeline —
  that is how the collision "reset" was dated), and read a true default from a **live rcon read's** typed
  `default:` / `Domain is …` fields. For live values the panel (`/api/dvars?fresh=1`) is still the tool of
  record — the dump is only a fallback when rcon replies are being dropped.
  ([[engine-dvar-defaults-from-log-dump]], [[read-the-server-not-the-file]])
- ⚠ **THE `bg_*` / `cg_*` PREFIX RULE — a server-side `set` on one is INERT on a dedicated server.**
  The prefix *is* the ownership marker: **`g_`/`sv_`/`scr_` = server** (a `set` works), **`bg_` =
  shared/predicted** and **`cg_` = client game** (every client reads its **own local copy**; the server's
  copy replicates to nobody). This has now bitten twice — `bg_viewKickScale` (flinch), which is why the
  mod must **push it per-client** via `setClientDvar` every spawn, and `bg_viewBobAmplitudeBase`, whose
  `dedicated.cfg` line was commented "bg_* replicates to all clients" and **did nothing for years**.
  It only ever *appears* to work on a listen host, where the host **is** a client.
  **Before setting any dvar server-side, read its prefix.** If it is `bg_`/`cg_`, you have exactly three
  options: push it per-client from GSC (the flinch pattern), hand the player the console command (the
  panel's 📋 clipboard button on the Bob slider), or accept that it is decoration. `cg_hudGrenadeIcon-
  ShowFriendly` in `dedicated.cfg.example` is unaudited and likely inert for the same reason.
  ([[flinch-bg-viewkickscale-not-replicated]])
- **Vision — the contrast pop is Gunfight's DEFAULT look, in every build** (`_gf_rounds.gsc`,
  shipped): `gf_initRoundVision` (called from `onStartGameType`) stamps `level.gf_defaultVision` =
  the map's own set and threads `gf_applyRoundVision`, which **waits for `prematch_over`** and then
  `visionSetNaked( "default_night", 3.0 )` — the `"enhance"` key (saturation 1, contrast 1.2).
  ⚠ It **cannot** be applied from `onStartGameType`: the stock prematch stomps vision *afterwards*
  (matchStartTimer forces `mpIntro`, then at T-2s blends back to the map vision over 3s), so we take
  over the tail of that blend — the 3.0s transition is what makes the reveal read as native. Vision is
  `level` state, so `map_restart` wipes it and this re-runs **every round**.
  The RCON `vision_<key>` override layers on top: it persists a key in `gf_vis_vision`, which
  `gf_roundVisionKey()` reads **inside a strip region** — so the public build has no dvar read at all
  and is always the default. ⚠ **Empty `gf_vis_vision` means "the gf default", NOT "the map vision"** —
  the bare map vision is reachable only via the *explicit* `normal` key, which is why `gf_bridgeVision`
  persists the string `"normal"` instead of clearing the dvar, and why `visreset` restores *enhance*.
- **Video (`r_*`) is stock and stays stock.** `gf_vis_*` server dvars map to client `r_*` (ambient/
  gridint/gridcon/hdr/fog), pushed per human spawn only if non-empty — but these are cheat-protected
  and **unreliable on dedicated**, which is exactly why the look lever above is `visionSetNaked` and
  not r_* ([[rcon-dedicated-dvar-push-limits]]). RCON-only, stripped from public builds. `r_gamma` is a
  saved client dvar Plutonium blocks.
- **Round-1 intro music is 100% stock — do NOT own it, and NEVER drive the underscore level-wide.** The
  whole MP music system is a **single shared client channel** (`_music::setMusicState` → one `musicCmd`
  client-system state), so anything set on it *replaces* rather than layers. The round-1 spawn sting
  (`game["music"]["spawn_<team>"]`, a long match-start piece in `mus/mp/spawn/long/`) and its ambient bed
  (`mus_underscore`) are the **same composition** (e.g. `Chopperintro_spawn_long` → `Chopperintro_underscore`,
  matched per map by `loadspec`), so the intro *resolves into its own loop* — there is no alias crossfade
  (`template MUS_NORMAL_2D` has empty `fade_in`/`fade_out`); the seam is pure **timing**. Stock nails that
  timing by being **per-player and self-relative**: `sndStartMusicSystem` is threaded on `self` at each
  player's **own first spawn** (`_globallogic_spawn.gsc:100`) and does `wait 15; self
  set_music_on_player("UNDERSCORE")` — so every player's bed starts a fixed 15s after *their own* sting,
  and a late joiner's is delayed exactly as much as their sting was. It can never land mid-sting for
  anyone. ⚠ **A level-wide push (all players at `prematch_over`, or any global timer) breaks exactly this**
  — it synchronizes the hand-off to one wall-clock moment and guillotines whoever spawned late. A
  `level.nextMusicState` + `prematch_over` "fix" was written and reverted for this reason. The one real
  limitation: stock's `wait 15` is a fixed floor (never earlier than 15s post-spawn, no "sting done"
  callback exists), so it's only perfect when the sting ≈15s — a gap if shorter, a clip if the long sting
  overruns 15s. If a clip ever needs fixing, keep stock's **per-player self-relative** model and bump the
  offset (per-player `wait N` from each spawn); never go level-wide. ([[intro-sting-killed-by-underscore-shared-channel]])
- **Headshots-only** (`level.gf_headshotsOnly`) is a dev-bridge flag, off/undefined in public builds.

### Match stats (persistent per-player K/D/damage/wins)
Recorded the classic CoD-server way: **structured `logPrint` lines on the one diagnostic stream**
(`games_mp.log` — the same file stock writes its `J;` connect lines to), aggregated by a box service.
No RCON, no dvar, no reliable command, no new thread. GSC (`_gf_rounds.gsc`, ships public) emits one
**delta** line per HUMAN per round — `GF_STAT;matchid;round;guid;team;K;D;A;HS;DMG;CAP;RW;name` — and
one `GF_MATCH;matchid;map;guid;W|L|T;name` per seated human at match end. Name rides **LAST**
(end-anchored parsing, names contain anything); bots/democlient never emitted. ⚠ **THE BOT RULE:
nothing involving a bot counts** (bot fill is on by default — anything less is farmable solo):
K/D/A/HS/DMG bump only when BOTH parties are human; a round win / OT capture needs ≥1 HUMAN on the
opposing team that round (`gf_statHumansSpawned`); a match W/L/T is only emitted with a human on both
teams at match end. The in-game **scoreboard still counts bots** deliberately (it shows the round
actually played) — which is why stat damage is its own `pers["gf_stDmg"]` counter, not a mark against
the score's `pers["gf_damage"]`. Deltas mean the
aggregator just **sums every line ever seen** — no dedup, no per-match reconciliation, a crash loses at
most the round in progress. Counters are **mod-owned pers[]** (`gf_stK/D/A/HS/Dmg`, bumped in
`gf_onPlayerKilled`/`gf_onPlayerDamage` under a `gf_roundActive` gate so administrative suicides —
team-switch `gf_seqTeamMove` — never count; captures ride the existing `pers["captures"]` via a
last-flushed mark). ⚠ The flush takes the round number **as an argument** — its two call sites sit on
opposite sides of stock `endGame`'s `roundsplayed++` (`:927` increments, `:985` invokes
`onRoundEndGame`), so the rescue site passes `roundsplayed - 1`. ⚠ **Deliberately NOT stock's `incPersStat`/`statAdd` chain** — that writes the
per-mod Demonware blob the server can never read back ([[plutonium-stats-are-namespaced-per-mod]]), and
parts of it are dead under `overridePlayerScore`. Flush is **double-sited and zero-safe** (counters
zeroed on flush; all-zero lines skipped): `gf_endRound` (pre-notify block, before endGame's
`roundsplayed++` — the round-win predicate reads `pers["gf_spawnedRound"] == roundsplayed`) plus
`gf_onRoundEndGame` as the rescue for end paths that bypass `gf_endRound` (bridge END ROUND's
`sd_endGame`). Box side: `status_service` tails the log **incrementally** (byte offset + file
**creation-time identity** in `storage\t5\logs\gamestats.local.json` — size alone misses a rotation the
fresh log outgrew; archive-tail recovery on rotation), sums day→GUID buckets, and projects
`admin/live/gamestats.json` behind the **`.secured` gate** (GUID-keyed = never the open web root; ingest
runs even while the gate is down). The admin page joins it to the connection history by GUID (Combat
leaderboard + drill-down; windows are **day-granular on the BOX calendar**). Parser regexes are
**line-start anchored** behind the engine's `min:sec` prefix so a hostile player *name* containing
`GF_STAT;…` inside some other line cannot forge stats. Accepted losses: a mid-round leaver's partial
round; a watchdog `map_rotate`'s final round (no endGame → no lines). Tests:
`tools/tests/gamestats.Tests.ps1` + `site/test/admin_combat.test.js`.

### Spawns & wager map zone
Curated hand-placed spawns for **25 maps** (`_gf_locations.gsc`, built once/match, cached in `game[]`;
⚠ this 25 is the *curated-set* count and stays in technical prose — the site and README say **"All 26
maps"** deliberately, counting `firingrange`'s supported opt-out, and that copy is the owner's: see
*Marketing copy is the owner's*);
each map has one set of 5 allies + 5 axis points and one OT flag point. Small mode consumes them via
`onSpawnPlayer`/`onSpawnPlayerUnified`, which **short-circuits all small-mode spawns to the curated
points** so late/async spawns (bot fill, late joiners, 60s forceSpawn) keep fight-facing points instead
of the stock scored pool ([[spawn-wrong-facing-usestartspawns-gate]]). Any map not in the curated set gets no curated data and degrades to `mp_tdm_spawn` + native Dom-B OT flag — omitting a map is the supported opt-out. ⚠ The curated branch must set
`self.lastSpawnTime`/`lastSpawnPoint` (stock `Callback_PlayerDamage` does unguarded arithmetic on them
for grenade spawn-protection) and does a `positionWouldTelefrag` scan (spawning onto an occupied point
kills the occupant).

**Spawn-VIEW angle vs spawn point — a separate carried-input fix.** The curated point sets the right
*facing*, but moving the camera (or holding the look stick) on the round-end **killcam / switching-sides**
screen made the player spawn looking the wrong way next round — a distinct bug from the point-selection one
above. `self spawn()` snaps the view once (a fixangle), but the stale client-side view from that screen
**reverts** the snap ~0.2–1s later (client-authoritative view; `GF_SPAWNYAW d0=0, d1 large`). Fix:
`gf_lockSpawnYaw` (threaded after each `self spawn()` in `onSpawnPlayer`) re-asserts `setPlayerAngles` on
**both** axes, **divergence-gated at 45°** (only a badly-carried view, so a still/adjusting player is never
fought → no camera shake) and **held through the whole prematch**, released at `prematch_over`. Ships public
(stock builtins only). The one edge: actively holding a look input off-target for the whole countdown gets a
gentle pull-back — inherent, not reachable in normal play. Dev probe: `gf_debug_spawnyaw`
([[spawn-yaw-carried-camera-input]]).

**Wager zone without the wager framework:** small mode uses stock `mp_wager_spawn` entities and **keeps
the baked wager blocker entities** (map ents tagged `script_gameobjectname "gun oic hlnd shrp"`) by
adding those four tags to the `_gameobjects::main` allow-list (`["gf","dom"]` + the four in small mode;
large mode omits them so the map opens up; `dom` always kept so the OT B flag survives). A wager compass
material is applied for a 14-map whitelist (the art must be resident — First Strike/Escalation maps keep
their full compass). ⚠ `xblive_wagermatch` is **not** set in `gf.gsc` (the map reads it at level-load,
before the gametype `main()` runs) — it's set to `0` (or `1` for gun/oic/shrp/hlnd) by the RCON map page
before the map loads.

**Hotel's elevators are OFF, and the switch is 100% stock.** `mp_hotel` does **not** use the generic
`maps/mp/_elevator.gsc` (the `elevator_trigger` system) — it ships its **own** `maps/mp/mp_hotel_elevators.gsc`,
which is **not in the `raw/` dump** and had to be pulled out of `zone/Common/mp_hotel.ff`
([[extract-dlc-map-gsc-from-fastfile]]). That script reads **`scr_elevator_failsafe`** (and forces it on
itself when `xblive_wagermatch == 1`, which is why the wager gametypes already ran Hotel with dead lifts —
only `gf` still had them live). Set, it parks both cars at the lower floor, slams the car + floor doors
shut, `DisconnectPaths()` on both levels, retitles the use triggers to "ELEVATOR UNAVAILABLE", and
`return`s **before the trigger loop ever arms** — so the shaft is *sealed*, not left as an open hole — and
short-circuits `elevator_prox_think` so bots stop pathing over to ride. We want it off because a 42s
one-life round has no room for a 3s ride + 3s cooldown lift that can strand a player, and the elevator's
own obstruction handler `DoDamage`s anyone the doors close on (a free kill the map hands out).
⚠ **Read at LEVEL LOAD** — `mp_hotel::main()` → `mp_hotel_elevators::init()` runs *before* the gametype
`main()`, exactly like `xblive_wagermatch`. So the `gf.gsc` seed only lands from the **next** map onward;
`dedicated.cfg` carries it too for the boot-straight-onto-Hotel case, and the panel badges the row
`NEXT MAP`. Same script also exposes `scr_elevator_max_riders` (3), `_cooldown_time` (3), `_move_time` (3)
if a softer nerf is ever wanted.

### RCON bridge + admin panel (dev-only)
Both are stripped from public builds; a public build has no RCON control. **`_gf_bridge.gsc`** is the
GSC side: the panel writes `set gf_cmd <seq>:<cmd>`, `gf_bridgePoll` reads+clears at 20 Hz and writes
`gf_ack`, with high-water seq dedup (`level.gf_ackSeq`) so a dropped-packet retry can't double-fire a
non-idempotent command. ⚠ The mark is **seeded from the `gf_ack` dvar every round, never reset** — a
command that restarts the match itself (`matchrestart`, `lobbystart`) wipes the round that owed it an
ack, so a reset would leave the panel un-acked → it resends the same seq → the wiped mark lets it
**re-run** (one click, N restarts, each re-arming the next). Telemetry (dedicated-only single-token reads): **`gf_state`** (12 colon fields:
`wA:wX:round:aliveA:aliveX:gametype:hold:fillN:pAllies:pAxis:parked:botDiff` — field 12 is the live
bot-difficulty preset, so the panel's Difficulty row stays lit on the current value every tick) and **`gf_roster`**
(`<num>,<team>,<alive>,<pending>,<bot>;…`). Command feedback is private to `gf_admin_guids`
(`gf_bridgeNotify`); only `saymsg` broadcasts.

**Where admin feedback LANDS: the killfeed, by default.** `gf_bridgeNotify( text, bold )` prints with
`iPrintLn` — **game-message window 0**, the same window the obituaries and stock's own
`iPrintLn( &"MP_CONNECTED" )` (`_globallogic_player.gsc:19-29`) share. That is the right home for a
*stream* of feedback: it stacks instead of stomping, sits off to the side, and ages out by itself. The
optional `bold` (an omitted arg is simply undefined in T5 GSC) routes to `iPrintLnBold` = window 1,
center screen, where **each call replaces the previous one** — reserved for the five match-control
banners (pause / resume / start / both restarts). ⚠ Window 0 holds only ~4 lines
(`con_gameMsgWindow0LineCount`) **shared with real obituaries**, so any one notice must be a SINGLE
line or it evicts the kills the admin just made. ⚠ Its dwell is `con_gameMsgWindow0MsgTime` (stock 5s),
**client-owned and archived — the server cannot retime it** ([[killfeed-duration-client-archived]]); an
admin who wants longer types `/con_gameMsgWindow0MsgTime 20` in their own console, and the `killfeed_`
verb is kept **only as the reproduction of that refusal**, never as a working lever.

**`adminmsg` — the box's admin-only channel.** Reads dvar **`gf_adminsay`** and routes it through
`gf_bridgeNotify`, so anything running on the box can put a line in front of the ★ admin and nobody
else. Today's producer is **`GF-ConnLogger`**: on a CONNECT it emits one coloured line — name, city /
country, ISP, plus a `^1[VPN/HOST]` tag when ip-api reports proxy/hosting — so an admin in-game sees
who just joined and from where. Both of its calls go through the **panel** on loopback (`/api/geoip?ip=`
— the *blocking* single-lookup mode, which is what makes the first join from a cold IP carry a location
— then `POST /api/rcon`), so it adds **no rcon poller and no second ip-api client**. The full IP is
**opt-in** (`-AdminNoticeIp`, default off: the line renders on the admin's screen, so a screenshot or
stream would publish a player's address, and the IP is already in the day-file); muted GUIDs
(`ignore.local.json`) raise no notice; `ONLINE` cold-start rows are skipped so a service restart can't
flood the feed. ⚠ **Its own dvar, never `gf_say`** — the panel's broadcast owns that one, and a notice
landing between a Say's two writes would go to the whole server. ⚠ Sent as **one batched, UNSTAMPED**
rcon write (`set gf_adminsay "…";set gf_cmd adminmsg`): two packets race on the paced queue (what the
panel's own Say learned), and seq 0 is never deduped and never touches the panel's high-water mark, so
it cannot collide with a seq the panel is awaiting an ack for — which is also why `gf_bridgeAdminSay`
**clears the dvar on read**. ⚠ The name is stripped of `^` colour codes and of `"`/`;` before it
reaches the dvar: without that, a player could **rename themselves into an rcon command**.

Team moves: `pteam_<num>_<team>` defers to next round
via `pers["gf_pendingTeam"]`, consumed in the target's **pre-spawn** maySpawn window (the
`gf_movePending` mechanism — ⚠ the old `spawned_player` watcher raced the re-begin spawn wave and
resurrected the "enemy spawns / 1 HP" bug; [[pteam-spawnedplayer-apply-races-respawn-1hp]]);
`pteamforce_` applies now via the
**sequenced move** (`_gf_rounds::gf_seqTeamMove` — an alive player **dies + late-spawns** onto the new
team when the round admits it; never the racy stock switch). Team-system toggles: `balance_`/
`teamlock_`/`teamswitch_`/`latespawn_`/`reclaim_<0|1>`. Verbs cover bots, balance-teams,
match-control (`lobbystart`, endround, the two restarts, pause/resume), gameplay toggles, and fun/visual
commands. **`roundrestart`** replays the round with no score/loadout-rotation/side-switch by ending it as
a `"tie"` through `gf_endRound` with `game["roundsplayed"]` pre-decremented (endGame's `++` nets it back)
and `level.roundswitch` zeroed for the cycle. **`matchrestart`** restarts the match (scores 0-0, round 1,
same map + teams) by reusing the lobby's fast-restart plumbing: snapshot the sides into the
`gf_teamplan`/`gf_botplan` dvars + `gf_matchArmed=1`, fire `game_ended`, `map_restart(false)` — so the
post-restart gate skips the lobby hold and re-applies the plan. ⚠ Neither restart may be a raw
`fast_restart` / `map_restart`: those skip `_globallogic::endGame`, so the `game_ended` notify that tears
down every per-round `endon("game_ended")` thread never fires — the old round's loops survive as a second
copy AND the engine's re-`InitGame` stacks a second `prematchPeriod()`/`gameTimer()` (double countdown).
**Pause** delegates the freeze to the mod clock (`gf_pauseMatch` — live clock + controls + bots +
`level.gf_matchPaused`, which drives the `gf_pause_hud` "MATCH PAUSED" menuDef) and keeps the B&W
vision on the bridge side, since only the bridge knows the `gf_vis_vision` key to restore on resume;
a `vision_*`/`visreset` issued mid-pause persists its key but doesn't apply until resume. `gf_bridgeInit` re-threads its loops every round behind a `gf_bridge_reinit`
collapse notify ([[onstartgametype-perround-thread-accumulation]]).

**`tools/rcon/`** is a loopback-only (127.0.0.1) Node admin panel (never web-deployed). Its transport is
the load-bearing part: Plutonium answers ~1 RCON reply per 0.7s and silently drops faster sends, so
**everything goes through one paced (`RCON_MIN_GAP=850ms`), priority, coalescing queue**. The UI runs a
single self-scheduling `pollTick` → `/api/tick` (chains `status;gf_state;gf_roster` into one send).
⚠ **Never add another RCON poller** — box services read through the panel API instead
([[rcon-panel-queue-saturation]]). Panel UI: FAVORITES (landing tab) / DASHBOARD / MAPS (live
`sv_maprotation` editor — [[rcon-map-rotation-editor]]) / ADVANCED / CONSOLE tabs; explicit-flex
`layoutColumns` (not CSS multicolumn); a dead-dvar cache silences "Unknown cmd" probing
([[rcon-connect-sweep-unknown-cmd-spam]]). The sidebar also carries the **NEXT MATCH** staging block
(dedicated-only, humans-only): stage each player Allies/Axis/Spec (or ⬇ prefill from current teams),
Commit writes the whole plan as **one raw `set gf_teamstage "<guid>:<code>,…"`** (no bridge verb, no
per-click writes — one paced rcon slot per commit), restored on connect/↻ Read via `readTeamStage`;
the stock/keep policy row (`gf_team_nextmatch`) lives in ADVANCED → TEAMS (single home — the sidebar
never duplicates a settings control). **FAVORITES** is a pinboard: a ☆ pins either a single
**row** (on any DASHBOARD/ADVANCED settings row) or a **whole block** (on its section title — the only
way the non-row controls reach the pinboard, e.g. BOTS' Add Bot / Kick All / per-team ± / difficulty
buttons, which are not settings rows and have no star of their own). Either way the pin is the **same
DOM node, borrowed** — moved out of its home while the tab is open and put straight back on leaving.
Never render a second copy of a control: reads (`srvApplyValues`) and writes (`sdve`/`sdvv`, Set All,
💾 Save) are keyed by element id / `data-dvar`, so a duplicate id silently drifts out of sync with the
server. ⚠ For the same reason a row inside a **pinned block** is skipped by `favBuild` rather than
borrowed twice. Pins land in one of the five **`FAV_CATS`** categories (MATCH START / GAMEPLAY / BOTS &
PLAYERS / FUN & VISUALS / SERVER), not under their home block — pinning six rows from six blocks used
to make six one-row groups; the home block survives as an `.sgroup` sub-header, an unmapped block falls
through to SERVER, and an empty category doesn't render. A borrowed block renders flush inside its
category (chrome stripped by `#p-fav .block .block` CSS, its own Set All row hidden so the category's
single one governs) and is **excluded from `layoutColumns`' items** — it is content of the category
block, not a column item, and hoisting it would tear it out of its category. Per-gametype rows
(`#srv-gt-body`) are deliberately not pinnable — that block is re-rendered on every dropdown change,
which would destroy a borrowed row's home. ⚠ `_gsClean` / `_blockKey` strip `.fav-star`: a block's
star lives *inside* its `.btitle` and its glyph flips ☆↔★, so an unstripped key would change the
moment you pinned it (breaking both the pin key and the saved fold state). ⚠ **The pinboard is stored SERVER-side** — the panel's
gitignored `tools/rcon/prefs.local.json` via `GET`/`POST /api/prefs`, `localStorage.gf_favs` is only a
first-paint cache — so it follows the **panel process**, not the browser: the VPS panel is one pinboard
whether you reach it by RDP or over the SSH tunnel from the laptop, and a laptop's own local panel keeps
its own. `deploy.ps1` `/XF`-excludes the file so `/MIR` can't delete it. Any settings row also answers a
**right-click** (`showRowCtx`): copy its dvar, pin/unpin, reset to default — the default read from the
DOM's own `defaultValue`/`defaultChecked` (so nothing carries a second copy of it), and pushed back
through the row's **own** apply button / change handler, so a reset can't drift from the row's transport.
Per-profile passwords live in gitignored `secrets.local.json`. ⚠ Status/dvar parsing is **end-anchored**
because names can contain spaces (a bot "MCG Gordon" would otherwise leak in as a human —
[[status-parser-name-spaces-bot-miscount]]), and the address-column **port is signed 16-bit** so a
real client can show `ip:-NNNNN` — every `status` address regex allows a negative port (`-?\d+`), or
~half of real players silently lose their IP + join alert + connection-history row
([[status-address-port-is-signed-16bit-can-be-negative]]). The `status` parser is **single-sourced
per language**: `tools/status_parse.js` (required by the panel and `join-notify.js`) with PS twin
`tools/status_parse.ps1` (dot-sourced by `status_service.ps1` + `join-notify.ps1`, reached only on
their panel-down fallback — the happy path consumes the panel's parsed JSON), both pinned to one
shared fixture (`tools/tests/fixtures/status_reply.txt`) by the two test suites. Extend the shared
module; never copy the parsing form into a new consumer.

---

## Gametype dvars

Set in `dedicated.cfg` or via RCON. The `scr_gf_*` family persists through `map_restart(true)`. Almost
every mod dvar is **seeded in `gf.gsc onStartGameType`** so the panel's connect-sweep never reads an
unregistered dvar (which echoes "Unknown cmd"); clamps live at the read site (`gf_cfgFloat(dvar,def,lo,hi)`).
**Rule: any new panel-read dvar must be seeded there.** Full ranges + `level.*`/`game[]`/`pers[]` var
tables → `docs/REFERENCE.md`.

**Gunfight rules**
| dvar | default | meaning |
|---|---|---|
| `scr_gf_scorelimit` | 6 | Round wins to win the match (the real match-end threshold). |
| `scr_gf_roundswitch` | 2 | Rounds between side switches. |
| `scr_gf_roundsperloadout` | 2 | Rounds before the shared loadout rotates (clamp 1-9). |
| `scr_gf_lethals` / `scr_gf_tacticals` / `scr_gf_equipment` | 1 / 1 / 1 | **Per-slot admin switches** — `0` turns that whole loadout slot off server-wide (nobody gets a lethal / tactical / placed equipment, on any loadout), and `_gf_hud` hides the matching overview column (`ui_gf_lo_show2`/`3`/`4`; the row's bracket still spans all three, so the block never reflows). Read **live at each spawn's loadout build** (`_gf_loadouts::gf_slotOn`, empty = on), so a panel flip lands on the next spawn — the next round for anyone already alive. **No pool rebuild**: the loadout still carries the item, only the give is skipped, so flipping one back on restores exactly what it was giving. Composes with, and never overrides, the two existing narrower skips — a loadout authored with `"none"` equipment (`gf_slotEmpty`) and the bot equipment exclusion. Panel: DASHBOARD → GUNFIGHT → *Loadout Slots*. Plain dvar rows, **no bridge verb** (nothing to apply — the give site is the reader). |
| `scr_gf_timelimit` / `_large` | 0.7 / 1.5 | Round length in minutes, small / large mode (0.7 = 42s). |
| `scr_gf_overtimelimit` / `_large` | 15 / 30 | Overtime seconds, small / large; `0` = OT off (HP decides now). |
| `gf_capture_time` / `_large` | 3.5 / 5 | OT zone hold-to-capture seconds, small / large. |
| `scr_gf_teamspawnmode` | auto | `auto` \| `large` \| `small` (auto goes large when a team hits 5+). |
| `scr_gf_flinch` | 0.5 | Flinch scale (× stock `bg_viewKickScale` 0.2) → **half stock kick**. The **only global flinch reducer**: 1.0 = stock, 0 = none. (The sniper/heavy package's `specialty_bulletflinch` adds a further **0.2×** for those 10 loadouts only — never put it back in the base set.) Pushed **per-client every spawn, unconditionally** — the server dvar alone doesn't replicate, and the push beats a player's own autoexec (clamp 0-3). |
| `scr_gf_headshot_scale` | 0.8 | Multiplier on **FINAL** headshot damage (clamp 0-3): 1 = stock, 0.5 = half, 0 = headshots void; a positive scale never rounds a hit below 1. **0.8 is the shipped default**: every non-headshot bullet takes Body Armor's −20%, so scaling headshots by the same 0.8 cancels that premium and restores the weapon files' stock head:body ratio. ⚠ Not a sniper-one-shot lever — the snipers' 1.5× zone covers neck/upper chest (not headshots), and sniper rounds drop armorvest from everyone. The engine folds the weapon file's baked hit-location multiplier into `iDamage` **before** GSC sees it (`MOD_HEAD_SHOT` set at `_globallogic_player.gsc:731-738`, hook at `:741`, return consumed `:742-743`), so this rescales the result globally — it can't set a per-weapon multiplier to an absolute value (that's the custom-weapon-file pass). Applied at the **top** of `gf_onPlayerDamage` so the scaled value flows through score (= damage dealt), the most-HP time-out decision, and the red kill-marker test; FF headshots scale too (engine applies FF damage, never scored). Read live per hit (`gf_headshotScale`) → an RCON `set` lands on the next shot; registered per round from `gf_roundApplyTuning` for the panel sweep. Plain dvar row (DASHBOARD → GUNFIGHT), **no bridge verb**. |
| `scr_gf_killcam_slowmo` | 0.6 | The round-end killcam's **timescale FLOOR** (clamp 0.25-1.0) — **not a toggle** (it used to be one; 0/1 no longer mean what they did). `0.25` = stock BO1 cinematic **and the bug**; `1.0` = no slow motion. Stock's 0.25 spaces the server's game frames ~200ms apart, overrunning `MAX_PACKET_USERCMDS` (32) on any client above ~160 fps → the "Connection Interrupted" plug. `0.6` → ~83ms, safe to ~385 fps, still a clear slow-mo. Clamp the **depth, not the length**. ⚠ `sv_fps` is not the lever — it truncates the killcam's frame-sized archive ring. |
| `scr_gf_jump_fatigue` | 0 | **0 = OFF (the GF default)** / 1 = stock. Drives the engine's `jump_slowdownEnable` (post-jump movement drag — "jump fatigue"). The mod owns it so OFF ships as a default even with no cfg and no panel (`gf_applyJumpFatigue`, re-applied every round). RCON bridge: `jumpfatigue_<0\|1>`. |
| `scr_gf_sprint_unlimited` | 0 | **0 = stock** / 1 = the sprint meter never empties. Drives the client dvar `player_sprintUnlimited`, **pushed per-client every spawn** — stock's only push is at connect and is ON-only, so a bare `set` on it reaches nobody already in the server and can never turn it back off (`gf_applySprintUnlimited` + `_Client`). RCON bridge: `sprintunlimited_<0\|1>`. |
| `scr_elevator_failsafe` | 1 | **ENGINE/map dvar, read at LEVEL LOAD → next map only.** `1` = **Hotel's elevators are disabled** (the GF default): cars parked at the lower floor, car + floor doors shut, `DisconnectPaths()` both levels, use triggers retitled "ELEVATOR UNAVAILABLE", bot prox-think short-circuited. 100% stock — `mp_hotel` ships its **own** elevator script (`maps/mp/mp_hotel_elevators.gsc`, **not** the generic `maps/mp/_elevator.gsc`) and Treyarch built this switch into it; stock forces it on for `xblive_wagermatch 1`, so the wager gametypes already ran Hotel dead. Seeded if-empty in `gf.gsc onStartGameType` (**outside** the strip regions — it ships in the public build) + set in `dedicated.cfg`, for the boot-straight-onto-Hotel case. No effect on any other map. |
| `g_playerCollision` / `g_playerEjection` | cfg ships **2 / 2** (engine default `everybody`) | **Player collision is OFF by default** — players pass through each other, and nothing shoves overlapping bodies apart. A one-life mode fought out of tight curated 2v2 spawns cannot afford a teammate body-blocking a doorway. **Real Plutonium ENGINE dvars** (registered by the bootstrapper, not Treyarch — absent from `raw/` and from `BlackOpsMP.exe`, which is why an older note wrongly guessed they were T6-only), **cfg-owned** like the `g_fix_*` family: **no GSC writes them**, so `dedicated.cfg` IS the default and a hand edit there is the whole change. ⚠ They are **ENUMs**: written by **index** (`set g_playerCollision "2"`) but they **read back as a NAME** (`nobody`), which blanked the panel's 0/1/2 dropdown on every read and made Set All / 💾 Save skip the row — the "it keeps resetting" report. Fixed panel-side with a name→index `rmap`. ⚠ A live rcon/panel change is **effective immediately and survives `map_restart`**; the ONLY thing that reverts it is a **server restart** re-execing the cfg. Set both — ejection alone still pushes players apart. `g_playerCollisionEjectSpeed` (25) is then moot. ([[player-collision-enum-dvar-panel-blank]]) |
| `g_fix_viewkick_dupe` | 1 | **INERT on T5 MP** — the engine never registered it (live read: `Domain is any text`, `default:` mirrors our own `set`). Harmless, does nothing. Flinch is `scr_gf_flinch` alone. |
| `scr_team_maxsize` | 0 (cfg ships **7**) | `>0` caps players/team; overflow → spectator on spawn. **This is the "bench everyone past the cap" lever**, not `gf_team_lock` (which makes `gf_fill_n` the human cap and would force bots to pad to that size every round). Live-editable — no restart. Shipped 7 (7v7) against `sv_maxclients` 18 = 14 playing + 1 democlient + 3 spectator. ⚠ A cap the client slots can't fund silently benches people: `scr_team_maxsize × 2 + 1 (democlient) ≤ sv_maxclients`. |

**Match start / pregame lobby** (match's first round only)
| dvar | default | meaning |
|---|---|---|
| `scr_gf_match_prematch_seconds` / `scr_gf_prematch_seconds` | 20 / 7 | Native prematch countdown length: first round / later rounds. |
| `scr_gf_min_players` | 1 | Min **humans** to start (1 = off); a release condition on the pre-prematch hold. |
| `scr_gf_minplayers_timer` | 0 | Min-players "start anyway" ceiling (s); **0 = never auto-start**. |
| `scr_gf_load_wait` | 20 | Max s to hold the prematch for still-loading clients — a **ceiling**, not a duration (releases the moment the last loader is off its loading screen). `0` = off. ⚠ Any non-zero value **arms the hold**, and the 3s arrival floor is then unconditional: every match start pays 3s even with nobody loading (the floor exists so a poll running before the engine has delivered the first connect callbacks can't wave the gate through on an empty tracker). |
| `scr_gf_load_expect` | 1 | **1 = the load gate also waits for the HEADCOUNT the last match ended with** (`gf_expectcount`, written unconditionally by `gf_writeExpectCount` at match end, one-shot consumed by the next match's gate), instead of only for whoever connected inside the blind 3s arrival floor. The server cannot see a client that hasn't sent its connect packet, so the previous map's roster is the only available target number. Also lets a **fully-accounted-for room bypass the 3s floor** (start in 400ms, not 3s). ⚠ A player who LEFT between matches gives no signal at all → the count is never reached and the start is held for `scr_gf_load_expect_wait` before falling back; that ceiling is what keeps the common case from costing the full 20s. Requires `scr_gf_load_wait > 0` (this refines that gate and its ceiling always wins); `humans == 0` always releases. Panel: ADVANCED → MATCH START → *Wait for Full Roster*. |
| `scr_gf_load_expect_wait` | 6 | Seconds the roster expectation waits before falling back to "every client we HAVE seen is loaded". **Keep it short** — a returning player reconnects in ~1-3s (already holds the map + `mod.ff`), while a leaver costs the full value every match start. Clamped 0-60, capped by `scr_gf_load_wait`. Inert unless `scr_gf_load_expect 1`. |
| `scr_gf_load_grace` | 20 | s past prematch_over to keep round-1 grace open for a straggler loader (0 = off). |
| `scr_gf_lobby` | **1** | Match Start: **0 Normal** / **1 Auto (default)** / **2 Manual** (Auto/Manual fast-restart via `map_restart(false)`). Auto is the shipped default so every match start re-fires the full presentation (gun-rack, spawn music, welcome splash) — the in-place Normal hold cannot. ⚠ Public builds strip the whole hold, so this only ever applies to a dev/VPS build. |
| `scr_gf_lobby_timer` | 600 | Manual-lobby auto-start ceiling (s); 0 = never auto-start. |
| `g_pregame_enabled` | 0 | **ENGINE** dvar, read at **level load** → **next map only**. `1` = run BO1's stock pre-match warmup lobby (`maps/mp/gametypes/_pregame`) before the match. 100% native; the mod only seeds + exposes it. |
| `party_minplayers` | 2 | Players the **stock warmup** waits for (its only gate). Counts bots. Unrelated to `scr_gf_min_players`. |
| `scr_pregame_timelimit` | 0 | Warmup time limit (min). ⚠ Keep **0** — stock registers it seed-if-empty at 5, and its time-out **rotates the map** instead of starting the match. Seeded to 0 by `gf.gsc` (strip-marked) + `dedicated.cfg.example`. |

**Teams & bots** (dev-only reconciler)
> Bot display names + the orange `^<bot^7` clantag come from **`storage/t5/bots.txt`** (native
> Plutonium, `name,clantag` per line, box-local — above the mod folder, never deployed; carried in
> `docs/MIGRATION.md`). ⚠ **Read at process start** — mid-process bot reconnects keep the internal
> random names; only a bootstrapper restart loads a change
> ([[plutonium-bots-txt-bot-names-clantags]]). `sv_randomizeBotNames` (panel row) picks randomly
> from the list. Does not rename the democlient.

| dvar | default | meaning |
|---|---|---|
| `gf_fill_n` | 2 | **Per-team TARGET size.** Boundary pass evens humans to off-by-1, then pads both sides with bots to `max(bigger human side, gf_fill_n)` — humans define the size, bots absorb variance, enough humans = zero bots. **0 = no bot fill** (balancing/queue still run; manual bot control sticks). Clamp 0-7 (tracks `scr_team_maxsize`). ⚠ The clamp bounds only the admin-set **floor** — `gf_teamSizeTarget` is deliberately unclamped, so humans push the size past it on their own and an odd human split still gets exactly one evening bot at ANY size (7 humans → 4v3 + 1 bot; 7v6 humans → one bot on axis). With `gf_team_lock 1` this is also the hard HUMAN cap per side. |
| `gf_team_balance` | 1 | Even the HUMAN split (off-by-1) at every round boundary, moving the most recent joiner. 0 = humans never auto-moved (arranged teams). Bridge: `balance_<0\|1>`. |
| `gf_team_lock` | 0 | 1 = `gf_fill_n` is a hard human cap per side; overflow joiners spectate, queued in join order, auto-seated when a seat opens. Bots never count against it. Bridge: `teamlock_<0\|1>`. |
| `gf_team_switch` | 1 | Players may switch teams themselves, immediately (alive mid-round = die + sit out the round; prematch/grace = free). 0 = self-switching refused; admin moves still work. Bridge: `teamswitch_<0\|1>`. |
| `scr_gf_latespawn` | 1 | A joiner/mover makes their FIRST spawn into a live round while their team has ≥1 alive — never in OT, never a respawn. Two ways in, both size-preserving: it **fills a gap** (team stays no bigger than the enemy's, by roster — anyone, bots included), or a **HUMAN takes a bot's spot** (that bot is removed; a bot never displaces anyone; a team full of humans makes the joiner wait for the boundary). 0 = always spectate until next round. Bridge: `latespawn_<0\|1>`. |
| `gf_team_reclaim` | 1 | Boundary-time **containment** for the untraced human mis-seat: re-seat a human stranded in spectator with **reason UNTRACED** (not a `user`/`moved`/`maxsize` spectate, not lock-queued) onto the lighter HUMAN side, so the NEXT round starts them ON a team instead of the ranked team/class menu. Runs before the balance/fill stages (bots absorb the size); prints `GF_RECLAIM`. Catches the strand one round late (the menu still shows for that round), so it contains, not cures. 0 = leave stranded humans (diagnostic-only). Bridge: `reclaim_<0\|1>`. |
| `gf_fill_kick_floor` | 2 | Client slots kept free for humans; a parked bot is kicked once total ≥ `sv_maxclients − this`. |
| `bot_difficulty` | normal (engine); cfg ships **fu** | BotWarfare AI difficulty — the **BASELINE preset** under the `gf_sv_*` override layer below. ⚠ A **REAL ENGINE dvar** (BO1 Combat Training), registered at process start: default `normal`, **CLOSED enum domain** easy/normal/hard/fu (live rcon read 2026-07-17) — never empty (a GSC seed-if-empty can never fire; the one gf.gsc carried was dead code, removed; the VPS's old "fu" was a live panel click that a restart silently reverted), and **a fifth name is domain-refused**, so a "custom difficulty" is a baseline + overrides, never a new enum value. The panel labels the four with the game's names (Recruit/Regular/Hardened/Veteran). The GF default fu is owned by `dedicated.cfg` (VPS + example). `_bot::diffBots` re-applies the `sv_bot*` preset from it every 1.5s, so cfg / panel `botdiff_*` changes land within a tick. |
| `gf_bot_difficulty` | seeds `custom` | **The CUSTOM-difficulty selector.** `custom` = Veteran(fu) base + the `gf_sv_*` overrides (the GF shipped tuning; panel CUSTOM button; `botdiff_custom`); `stock` = the four presets run **pure designed values** — `gf_bridgeApplyServerDvars` skips every `sv_bot*` mirror (the stock `botdiff_*` verbs write this sentinel). ⚠ Stock is the explicit string `"stock"`, never `""` — empty is the seed-if-empty state and would flip back to custom each round. Tuning any `sv_bot*` via `svset_` auto-switches to custom (the write is invisible under stock). `gf_state` field 12 reports `custom` when active. |
| `gf_sv_<dvar>` | "" | **Per-dvar overrides = the CUSTOM difficulty's definition (apply only under `gf_bot_difficulty custom`).** `diffBots` rewrites the whole `sv_bot*` family from the preset every 1.5s, then `_gf_bridge::gf_bridgeApplyServerDvars` re-applies every **non-empty** mirror on top **in the same frame** — so an override wins continuously, and empty/absent = preset value. ⚠ A raw `set sv_bot*` (rcon OR cfg) is **NOT cheat-refused** on the dedicated console (proven live 2026-07-20, same-packet set+read) — it is simply clobbered ≤1.5s later; **the mirror is the only write that sticks**. Allowlist = mirror list = `_gf_bridge::gf_bridgeServerDvarList` (13 + `timescale`): FOV, reaction/fire min+max, strafe chance, sprint/melee dist, yaw **hip + ADS** (ADS is the dominant tracking knob — `sv_botMin/MaxAdsTime` is pinned 3000/5000 at every difficulty, 3-5× the engine's 1000), pitch envelope up/down (reads as vertical aim scatter — the easy→fu gradient narrows it), the grenade gate, and **`scr_help_dist`** — the one preset dvar that is **GSC-side**, so its effect is *read* not inferred (`_bot_script.gsc`): `bot_listen_to_steps` compares `dist*dist*8` to a `DistanceSquared`, i.e. bots **hear footsteps** out to **2.83× the value** (fu 512 → ~1448 units) and the same radius decides whether a decoy fools them, while `bot_cry_for_help` is **mostly inert as written** (its teammate loop calls `SetAttacker` on the **victim**, not on the teammate it just found, so it re-targets the victim instead of alerting the squad). ⚠ The custom-vs-stock gate is **`gf_bridgeIsBotTuning`**, not a `sv_bot` prefix test — `scr_help_dist` is preset-owned despite its `scr_` prefix, and a prefix test would leak it onto the stock presets. Clear = set the mirror to `""` (panel ↺ on the row does this — it deliberately does **not** push a "default value", which would pin an override). Shipped tuning: `gf_sv_botYawSpeed 12` + `gf_sv_botYawSpeedAds 10` on the fu baseline (cfg-owned, VPS + example). |

**Perks / RCON-managed / plumbing**
| dvar | default | meaning |
|---|---|---|
| `gf_perk_on` / `gf_perk_off` | "" | Comma-separated perk lists added/removed after the base set. |
| `gf_admin_guids` | "" | GUID allowlist for private bridge command feedback. |
| `gf_team_nextmatch` | stock | **Next-match team policy.** `stock` = the engine's random autoassign between matches (per-player coin flip); `keep` = carry current teams across the map change: `gf_writeNextMatchPlan` (from `gf_onRoundEndGame`, which stock invokes only at true match end — all end paths incl. bridge END ROUND) snapshots humans by GUID into `gf_teamplan` + the `gf_teamcarry` marker; `shuffle` = fresh random **balanced** teams every match (`gf_writeShuffledTeamPlan`: Fisher-Yates deal of the seated humans, off-by-1-even, random odd side; deliberate spectators stay). Either plan is consumed by the next match's first pass (`gf_consumeTeamPlan`) — seated at connect, pre-spawn, no flicker. Panel row: ADVANCED → TEAMS. |
| `gf_teamstage` | "" | **Staged next-match teams** — `<guid>:<a\|x\|s>,…` written by the panel (one raw `set`, no bridge verb). One-shot: wins over any carried/armed `gf_teamplan` at the next match start (rotate, lobby release, `matchrestart` alike), cleared on consume. Empty = no stage. |
| `gf_expectcount` | "" | Roster expectation: humans at the last match end, written unconditionally by `gf_writeExpectCount` and **one-shot consumed** by the next match's load gate (`gf_consumeExpectCount`). Read only when `scr_gf_load_expect 1`; a dvar because a map change wipes `game[]`/`pers[]`. Not a panel row — telemetry the gate owns. |
| `gf_teamplan` / `gf_botplan` / `gf_matchArmed` / `gf_teamcarry` | "" / "" / "" / "" | Lobby→match transfer + loop-break + carry-marker plumbing (dvars because `map_restart(false)` — and a match→match map change — wipe `game[]`). `gf_teamcarry "1"` marks `gf_teamplan` as a carried end-of-match snapshot; a marker-less plan on a plain map load is ignored as stale. |
| `gf_vis_*` (`vision`/`ambient`/`gridint`/`gridcon`/`hdr`/`fog`) | "" | RCON visual tweaks; client-side, unreliable on dedicated. |
| `gf_expbullets_radius` | 200 | RCON explosive-bullets blast radius. |

**Bridge telemetry** (dev-only, dedicated-only): `gf_cmd`, `gf_ack`, `gf_state`, `gf_roster`, `gf_say`,
`gf_adminsay` (the admin-only message slot — see *RCON bridge*; cleared on read).
**HUD** (per-client menu dvars): the `ui_gf_*` family (health panel, self bar, loadout overview,
lobby) — see `docs/REFERENCE.md`. **Dev/debug** (strip-wrapped): `gf_debug_spawns`, `gf_debug_hud_pool`,
`gf_debug_elem_probe`, `gf_hitch_pct`, `gf_hitch_debug`, `gf_force_loadout`, `gf_force_camo`.

**Friendly fire** is set via the **stock** tweakables `scr_team_fftype` + `scr_gf_team_fftype` by the
RCON panel — the mod GSC has **zero** FF references.

**Idle/AFK kicks are stock, not the mod** ([[stock-afk-and-spawn-kick-timers]]) — two independent
sub-5-minute timers, neither with a single `kick()` call in mod GSC. **`g_inactivity`** (input-idle kick,
**spectators included**) is owned by `dedicated.cfg`: the Plutonium `T5ServerConfig` template ships **190**
(kicks a quiet spectator at ~3 min), the VPS + our example now run **300**; the panel's ADVANCED tab edits
it live (cfg is boot-read). **`scr_kick_time`** (stock spawn-or-be-dropped) is *engine-registered at 60* and
armed whenever `level.rankedMatch` is true — which it **is** on our dedicated (`onlinegame 1` +
`xblive_privatematch 0`). It exempts `pers["team"] == "spectator"`, but would kick anyone the mod holds
team-assigned without spawning (a whole Auto/Manual lobby hold; a large-mode late joiner), so `gf.gsc`
pins it to **3600**.

**Connect/timeout drops are a separate axis from AFK — and are TWO dvars, not one**
([[sv-timeout-and-connecttimeout-template-defaults]]). Both measure *packet silence*, never input, and
both are **engine-registered** (no `gf.gsc` seed needed) and **not latched** (the panel's ADVANCED tab
changes them live).
- **`sv_timeout`** — an **already-in-game** client. The `T5ServerConfig` template ships **15**, which is
  hostile two ways: it drops anyone who alt-tabs out of **exclusive fullscreen** (Windows minimizes the
  window, the client stops pumping its main loop and stops sending — borderless/windowed keeps running
  unfocused and never hit it), and it makes the **server ~3× stricter than the client** (`cl_timeout` is
  **40**), so an ordinary lag spike drops a player who is still sitting there waiting. **Never set this
  below `cl_timeout` (40).** VPS + example now run **240** (the engine default). Raising it only costs the
  time a hard-crashed client keeps its player slot.
- **`sv_connectTimeout`** — a client still **connecting/loading**, i.e. the **first-join budget**. Engine
  default **80**, which is thin: a first-timer FastDL-downloads `mod.ff`, then the Plutonium client rebuilds
  its engine *in place* with no loading UI (D3D9 device destroyed + recreated, ~180MB of zones reloaded — a
  30-60s black screen, [[fastdl-first-join-black-screen-rebuild]]) and then runs a Demonware stats/CAC
  re-sync with documented multi-minute stalls. Blowing 80s mid-rebuild is much of why new players report
  having to **connect twice**. VPS + example now run **200** (matching the client's own `cl_connectTimeout`).
  It only ever applies before a client finishes loading, so raising it costs nothing.

**The Plutonium `g_fix_*` family — and why Gunfight ships 3 of 4 against the grain.** These are engine-level
bug fixes Plutonium added, and their **engine defaults split on one line**: a fix with **no gameplay
semantics ships ON**, a fix that **changes felt gameplay ships OFF**, so a stock server stays
vanilla-faithful — bugs and all. Gunfight opts into all of them, because a competitive gametype wants
*correct* damage and flinch, not bug-for-bug BO1 parity. ⚠ **Only 3 of the 4 names below are real dvars** —
`g_fix_viewkick_dupe` is a placebo. Registration and engine defaults come from a **live RCON read** (the
`Domain is …` + `default:` fields), NOT the `console_mp.log` dump: the dump cannot tell a registered dvar
from one our own cfg created ([[engine-dvar-defaults-from-log-dump]]).

| dvar | engine default | GF | what the bug is |
|---|---|---|---|
| `g_fix_damageKickReductionPerk` | **1** (on) | 1 (untouched) | Pure fix, already on. No cfg sets it and it still reports `Domain is 0 or 1`, so the family *exists* in MP. ⚠ That vouches for the family, **not for any individual name** — check each one's own domain. |
| `g_fix_entity_leaks` | **1** (on) | **1** | Engine entity leaks, incl. the `Hunk_AllocAlign failed on 8 bytes` leak from **weapon switching** — this mod's hot path (a fresh shared loadout every round, 24/7). ⚠ The **T5ServerConfig template sets this to 0**, actively *disabling* a fix the engine ships enabled. Restoring it is the one change here that is not a deviation. |
| `g_fix_viewkick_dupe` | **— (unregistered)** | 1 (**inert**) | ⚠ **NOT a real MP dvar.** Live read: `Domain is any text`, and `default:` merely mirrors the value our own cfg `set`. Setting it does nothing — there is no doubled flinch. Kept in cfg/panel only as a tripwire. |
| `g_fixBulletDamageDupe` | **0** (off) | **1** | A bullet through two **intersecting** players deals its damage **twice**. Corrupts three things GF is built on: score **is** cumulative damage dealt, a timed-out round is decided by **most remaining HP**, and rounds are **one life** (a doubled bullet = an unearned instant kill). Bodies overlap constantly in the tight 2v2 spawns. |

⚠ Note the **inconsistent naming** — three are `g_fix_snake_case`, one is `g_fixBulletDamageDupe`
(camelCase, no underscore). A `g_fix_` grep silently misses it. ⚠ All four are set in
`dedicated.cfg`, not seeded by GSC (three are real **engine** dvars; the fourth is inert); the panel
exposes them under ADVANCED → ENGINE GAMEPLAY. The VPS's
`dedicated.cfg` lives on the box and is **not** shipped by `deploy.ps1`, so a change here reaches the VPS
only via the panel (toggle live, then 💾 Save to persist) or a hand edit. ⚠ `g_print_entity_leaks 1` logs
leaks as they happen — the way to actually verify the entity-leak fix rather than assume it.

⚠ **Keep every `dedicated.cfg` comment semicolon-free** — the cfg parser splits on `;` *inside* a `//`
comment and executes each fragment ([[unknown-command-cd-and-cfg-semicolon-parse]]).

**Retired / inert dvars** (no longer read; a stale
cfg value does nothing): `scr_gf_largemode_minplayers`, `scr_gf_roster_wait`, `scr_gf_lobby_hold`/
`_restart`/`_restart_full`, `scr_gf_ff`/`scr_team_ff`, and the `bots_manage_*`/`bots_team_*` family as
Gunfight controls (still seeded for the vendored BotWarfare AI — don't delete the seeds; use `gf_fill_n`).

---

## Building mod.ff

`mod.ff` is a **gitignored build output** (registers the UI rows + strings + menus, compiles the custom
FX). **Pure GSC changes never need a rebuild** — edit + `map_restart`. Rebuild only when a *compiled*
asset changes: `mp/gametypesTable.csv`, `localizedstrings/gf.str`, `localizedstrings/cgame.str`,
`ui_mp/hud_gf.txt` or `ui_mp/hud_gf_health.menu` **structure** (dvar values/positions are
runtime-tunable), or a `raw/fx/misc/*.efx`.

⚠ **A clean build is NOT proof the game is running it — the mod folder is also the CLIENT's FastDL
download directory.** Joining the live server makes the client checksum-compare and **download the
server's `mod.ff` straight over your fresh build**, so the classic "rebuilt it, still shows the old
text" is almost always the artifact being swapped, not a bad edit or a stale source. The tell is a
mod-folder `mod.ff` **newer than** the linker's own output in `<GameRoot>\zone\english\mod.ff`;
recover by copying that back. Test `mod.ff` changes against a LOCAL server, and read what is actually
inside an ff with **`tools/inflate_fastfile_zlib.ps1`** (⚠ it already exists — do not write a second
inflater) rather than inferring it. ⚠ `build_ff.ps1` is not byte-deterministic, so a hash identifies
**one artifact**, never that two builds match ([[modff-drift-vs-gsc-deploy]] — compare SIZE; stale =
smaller). ([[fastdl-download-clobbers-local-modff]])

### Overriding stock engine strings (`localizedstrings/cgame.str`)
A localizedstring baked into **our** `mod.ff` **overrides the game's own shipped-zone copy** — so any
single-purpose engine string can be retitled or blanked. ⚠ **The asset name is `<STR FILENAME>_<REFERENCE>`**,
so an engine `CGAME_*` string MUST be declared in a file literally named `cgame.str` (+ `localize,cgame`
in `mod.csv`); the same reference in `gf.str` compiles to `GF_*`, which nothing reads — a **silent no-op**.
An empty value renders as **nothing** (the engine does not fall back to printing the raw key). Currently
shipped: `SB_SCORE` → **"Damage"** (score in this mod IS cumulative damage dealt) and
`CONNECTIONINTERUPTED` → **""** (blanks the between-rounds banner — note the engine's own typo, one R).

The banner blank is the only lever on the *rendering*: `CG_DrawDisconnect` is client engine code and the
client has **no `cg_drawDisconnect` dvar** (verified against `BlackOpsMP.exe`), so GSC and the menu layer
can't reach it. It **hides** the banner; it does not remove the cause.
⚠ **It was never the "irreducible floor of `map_restart`", and treating it as one cost a lot of time.**
That framing is retired: `GF_ENDTL` measures `dark=0ms` (the server never goes snapshot-silent), and
`map_restart` runs *after* the killcam anyway, so it cannot land mid-replay. The plug people actually saw
was the **final-killcam timescale dilation starving the usercmd ack rate** — a real, fixable server-side
cause, now fixed by the slow-mo floor (see *Final-killcam slow motion*). Keep the blank as cosmetic cover
for genuine lag; do **not** cite it as evidence a symptom is unfixable.
([[killcam-slowmo-timescale-usercmd-backlog]], [[connection-interrupted-mitigations]])
⚠ It also suppresses the
warning for **genuine** lag/packet loss.
⚠ **Only the TEXT is gone — the PLUG ICON still renders, and cannot be removed.** It is material
`net_disconnect` → colorMap image `net` (Q3's inherited phone-jack); no dvar, and its position is hardcoded.
Overriding it would need a new image in `mod.ff`, and **this linker cannot embed one** — it writes an image
*reference* by name and silently drops the pixel data. Both attempts *built clean*: one was a no-op, the
other would have shipped a **missing-texture checkerboard** to every client. Tried and reverted
2026-07-12 → [[modff-cannot-embed-new-images]]. Do not retry without the Asset Manager/`.gdt` pipeline. ⚠ Keep overrides to single-purpose keys: the scoreboard's other
columns are `MPUI_*`, which the combat record / leaderboards / after-action report also use — renaming one
changes it **everywhere**. ⚠ Overrides only reach clients that downloaded `mod.ff`, i.e. players **already
on the server** — a messaging surface, never an ads/acquisition one. Full detail →
[[stock-engine-string-override-via-modff]].

**Always build via `tools/build_ff.ps1`** — it stages `mod.csv` to all five zone-source paths (the
linker reads the **assetlist** copy), stages the transitive `hud_gf_health.menu` explicitly, runs the
linker twice from `cwd=bin/`, cleans staged files back out of `raw/`, and copies `mod.ff` back. Never
call the linker by hand; step-by-step → `docs/DEV.md`. Key gotchas ([[build-stage-transitive-menu]]):
- **menufile double-load kills ALL gametypes.** A `.menu` pulled in by a `loadMenu` (like
  `hud_gf_health.menu` via `hud_gf.txt`) must NOT also be a `menufile` entry in `mod.csv` — double
  registration crashes the menu system and every gametype vanishes from the UI.
- **Empty `ui_mp/mod.txt` + `mod_ingame.txt` stubs** kill a ~4.6s "missing asset" mod-load stall (a
  first-join black-screen contributor — [[fastdl-first-join-black-screen-rebuild]]). Keep both.
- **GSC is deliberately NOT baked into `mod.ff`** — it loads as loose rawfiles; baking the unstripped
  `gf.gsc` once left a dangling dev `#include` that crashed FastDL clients. Never add `rawfile,*.gsc`.
- `build_ff.ps1` cleans `raw/` because Plutonium reads `raw/` as a fallback over IWDs even with no mod
  loaded — a leftover staged file silently overrides the stock game.
- `.efx` files must already live in `<GameRoot>\raw\fx\misc\`; the wrapper does not copy them. Expected
  harmless linker noise: GSC-rawfile errors and stock-FX image-missing errors.

---

## Release, deploy & secrets

**Branch model** ([[repo-release-branch-structure]]): `main` = full dev history + tooling (develop
here). **`release` is the GitHub default branch** — a fresh `git clone` lands there (minimal public
content), so `git checkout main` after cloning and push `main` with `tools/push_all.ps1`. *(The local
`origin/HEAD` may show `main` — that's a stale local ref; the actual GitHub default is `release`.)*

- **`package_release.ps1`** builds the public output (release branch = release zip, byte-identical):
  `mod.ff` + gameplay GSC + README. Dev files excluded by name; `// #strip-begin … #strip-end` regions
  removed, then comments stripped. ⚠ **Strip order is load-bearing** — markers before comments, or the
  dev body leaks (the marker lines are themselves comments; the wiring between them is real code).
  `tools/release_common.ps1` holds the shared drop-list + strip regex (one source of truth for the
  packager AND the verifier below).
- **The public build is a STRIPPED-DOWN Gunfight** — same *gameplay* as the VPS (rounds, shared
  rotating loadouts, overtime + capture zone, auto large/small team mode, curated spawns, damage
  scoring, menu HUD), **none of the dev/ops machinery**. Cut: the whole match-start hold
  (`gf_waitForLoadingClients` and everything it drives — load gate, min-players, Auto/Manual lobby +
  its camera/roster HUD, the team/bot plan transfer), the engine pregame warmup (the
  `g_pregame_enabled` seed is strip-marked — unseeded, the engine defaults it to 0 and BO1's own
  `_pregame` gametype can never come up, so there is **no `_pregame.gsc` to exclude**), bots, the whole
  team system (balancer, lock/queue, the menu-wrapper switch rules, mid-round late spawn — public keeps
  stock autoassign + stock team menus), the RCON
  bridge, debug tooling, admin pause, the `gf_vis_*` r_* push, the RCON perk overrides, and the
  `level.maySpawn` hook (stock guards it with `isDefined`, so the public build installs none and falls
  through to stock grace/lives). The prematch **countdown stays** — pinned at a fixed 20s/7s, with the
  dvar-tunable version strip-marked behind it. A public server owner still gets the core knobs:
  `scr_gf_scorelimit` / `_timelimit(_large)` / `_overtimelimit(_large)` / `_roundswitch` /
  `_roundsperloadout` / `_teamspawnmode` / `gf_capture_time(_large)` / `scr_gf_flinch` /
  `scr_gf_headshot_scale` / `scr_gf_jump_fatigue` / `scr_gf_sprint_unlimited` / `scr_gf_lethals` /
  `scr_gf_tacticals` / `scr_gf_equipment` / `scr_team_maxsize`.
  ⚠ Two functions are deliberately kept OUTSIDE the strip regions because **live-round code still
  calls them**: `gf_anyTrackedClientLoading()` (called by `gf_roundWatchdog` + `gf_closeGraceEarly`;
  already returns false when the tracker never armed, so it degrades to "nobody is loading") and
  `gf_pushPauseBanner()` (called by `gf_runHealthHUD` every spawn; with `gf_matchPaused` never set it
  just clears the banner). The ~8 inert `isDefined( level.gf_inLobbyHold )` guards in
  `gf_playerSpawnedCB` / `_gf_loadouts` are likewise left in place — they degrade correctly and
  excising conditions from live `if` expressions is pure compile risk for zero behavior change.
- **`tools/verify_release_strip.ps1`** — **run after touching ANY strip region.** GSC resolves symbols
  at *compile* time, so a region that removes a function some KEPT code still calls is an `unknown
  function` that fails the **whole server**, and it won't surface until a client connects. The verifier
  applies the strip regions and statically proves: no kept call lands in stripped code, no kept
  `#include` points at a dropped file, and no dev-only dvar leaked. It does **not** prove the GSC
  parses — a real map load is still the final word.
- **`package_server.ps1`** builds the PRIVATE VPS bundle: the **entire `main` tree** + `mod.ff` +
  `dedicated.cfg`. ⚠ It does **not** strip — the VPS runs dev wiring live by design; only a hardcoded
  `rcon_password` in GSC is blocked ([[package-server-does-not-strip-markers]]).
- **`deploy.ps1`** runs **ON the VPS**, from the account owning the **profile the server loads its mod
  from** — `Administrator`, which is what an SSH session lands as, so a plain `deploy.ps1 -Mod` over
  `ssh gf-vps` is already correct (a wrong-account run silently mirrors to the wrong profile).
  ⚠ **The server PROCESS runs as `SYSTEM`, so its process owner is NOT how you find that folder** —
  `GF-GameServer` is a ServiceAccount scheduled task whose action pins `LOCALAPPDATA` to
  Administrator's profile before launching the bat. The old "check the bootstrapper's owner"
  diagnostic (still quoted in some places until 2026-08-14) now answers `SYSTEM` and sends you to a
  `systemprofile` path that does not exist. Read the **task action**, or confirm against the
  continuously-written `…\mods\mp_gunfight\logs\games_mp.log`
  ([[vps-game-server-runs-as-system-localappdata-pinned]]). `-Mod`: pulls `main`, checks `mod.ff` out of `origin/release` (gitignored on
  `main`), mirrors the tree + `mod.ff` into the mods folder, publishes `mod.ff` to the FastDL web root,
  restarts, and recycles the RCON panel + load-once box services. `-Web`: secret-scans + robocopy-mirrors
  `site/wwwroot` into IIS (preserving the box-owned `web.config`). ⚠ The restart auto-recovers a wedged
  `plutonium.exe -update-only` and drops a self-expiring watchdog-maintenance window
  ([[deploy-recycles-box-services]], [[deploy-restart-wedges-on-plutonium-updater]]).
  ⚠ `mod.ff` only reaches the box via `origin/release`, so committed menu/str/csv/FX changes are NOT
  live until rebuilt + republished ([[modff-drift-vs-gsc-deploy]]); verify a deploy via the two logs in
  the storage-path mod folder ([[vps-gsc-deploy-log-verification]]).

**Secrets** — three layers, no secret ever in a tracked file: (1) gitignored stores hold the values
(VPS `rcon_password`/`g_password` in `dedicated.cfg`; panel password in `secrets.local.json`; server key
in launch config); (2) `.gitignore`; (3) the tracked pre-commit hook `tools/hooks/pre-commit` (enable
once per clone: `git config core.hooksPath tools/hooks`). ⚠ `rcon_password` must be **≤23 chars**
(Plutonium truncates on login — [[rcon-tool-vps-connect-23char-cap]]). **Two burned secrets still need
rotating once, and they leaked by DIFFERENT routes** — the layers only prevent future leaks, and
rotation (not history scrubbing) is what closes either one:
- **Two RCON passwords ARE in `main`'s public git history**: a 24-char one in commits
  `43f79da`/`af1707b`/`035c74a`, and a 12-char one in `43f79da`/`79e335e`/`eeca62d`. Both came from the
  same two now-deleted call sites (the panel's hardcoded `<input value=…>` and a
  `setDvar("rcon_password", …)` in `gf.gsc`); neither ever reached `release`. ⚠ **Do not paste either
  literal back into a tracked file to "document" it.** The 24-char one survives at HEAD in exactly one
  place — `tools/deploy.ps1`'s scan denylist — because a detector needs the value it detects; that is
  the *only* justified copy, and the 12-char one needs none. Naming the commits is enough: `git log -S`
  recovers a value when a rotation actually needs it, whereas a literal in this file turns "dig through
  history" into "read one indexed line" for a credential that is still live. ⚠ Note the guards **cannot**
  catch this for you — every password rule keys on adjacency to `rcon_password`/`g_password`, so a bare
  credential in prose commits clean.
- ⚠ **The Plutonium server key was NEVER in git** — every reachable blob was searched; the only
  key-shaped strings are the placeholder and `%key%`. It leaked via a **pasted process command line**
  (`+set key SVrs…`) in a session transcript, 2026-07-02 ([[vps-server-provisioned]]). So git scrubbing
  could not have helped it even in principle. ⚠ Its label **is** the in-game browser name, so a
  replacement key must reuse the **exact** current label ([[plutonium-serverkey-sets-browser-name]]).
⚠ **History is deliberately NOT rewritten — settled, do not re-open.** `main` has been public for
months, so every clone, fork, unreachable-object retention and code-search index already holds the
values; a force-push edits only your branch tips. Rotation makes the leaked thing worthless, which is
the only outcome available. Rewriting would also break the VPS deploy clone's `git pull --ff-only`,
dangle the SHAs cited in `docs/VPS_HARDENING.md`, and delete `deploy.ps1`'s own detector.
Rotation runbook → `tools/rotate_secrets.ps1` (dry-run by default, enforces the ≤23 cap; the server
key is manual-only at platform.plutonium.pw). Security runbook status → `docs/VPS_HARDENING.md`,
[[gunfight-us-security-audit]].

**A fourth class rides those same three layers: ADDRESSES.** `main` is pushed and world-readable, so
an IP in a doc is *published* — and the two worst leaks this repo has had were not passwords at all: a
pasted `status` reply put a **player's** real IP + GUID into `docs/notes/`, and the firewall runbook
printed the **owner's home egress IP**. Neither is a "secret" any password scanner would catch. Three
tiers, by who is hurt:
- **Redacted — placeholder-only in every tracked file:** the **home/admin egress IP**
  (`<admin-home-ip>`, it identifies a house) and the **Contabo VNC console**
  (`<vnc-console-ip>:<vnc-port>`, which bypasses Windows Firewall entirely). Real values live in the
  gitignored **`tools/ops.local.json`** (template `tools/ops.local.json.example`). ⚠ That file is a
  **crib sheet, not config — nothing at runtime reads it**; the panel's runtime host/port list is the
  separate `tools/rcon/servers.local.json`.
- **Published, but declared ONCE:** the box's **own** public IPv4/IPv6. They are already in the
  in-game server browser and one `dig gunfight.us` away, and a runbook step run under pressure must
  stay copy-pasteable — so `docs/VPS_DEPLOY.md`'s *Target box* table is their **single canonical
  declaration**, and only the two runbooks (`VPS_DEPLOY`/`VPS_HARDENING`) spell them out, in facts
  tables and executable steps. ⚠ **Every other file uses the `gf-vps` SSH alias, a pointer to that
  table, or `<vps-ip>`** — never a fresh literal. A restatement in a note buys nothing and is pure
  migration-drift surface.
- **Never in any file, tracked or not:** a **player's** IP or GUID. Doc examples use RFC 5737
  (`203.0.113.x` / `198.51.100.x`) with invented names and GUIDs.

⚠ **The pre-commit hook enforces this, not discipline** — it blocks any staged **public** IPv4/IPv6
literal (loopback/private/CGNAT/RFC-5737/doc ranges excluded) and any pasted `status` roster row
(4 integer columns + a `^N`-coloured name). A deliberate keep needs the token **`ip-ok`** in a comment
on that line — which is why the runbooks' kept literals carry a trailing `<!-- ip-ok -->` — or an entry
in `tools/hooks/ip-allow.txt`. ⚠ **Never allowlist the home IP, the VNC console, or a player address:**
those are precisely the leaks the rule exists to stop, and an allowlist entry is forever.

## VPS & box services

The live server is a Contabo VPS ([[vps-server-provisioned]]); the launch bat + `sv_maxclients` latch
live only in `C:\gameserver\T5\start_mp_server.bat` ([[vps-launch-bat-and-maxclients-latch]]); the
in-game browser name comes from the Plutonium **server key label**, not `sv_hostname`
([[plutonium-serverkey-sets-browser-name]]).

**Remote access: SSH (22) is open to ANY IP; RDP (3389) is pinned to the home IP.** SSH carries the
travel/ops path — rule `SSH-Any-In (travel)`, **additive** (the older `OpenSSH home` /
`OpenSSH (scoped to home IP)` rules are left in place, so it reverts with a single
`Disable-NetFirewallRule`). **RDP is still `RDP-AdminOnly-In` → `<admin-home-ip>` only**, so from a
non-home network the routes are SSH or the **Contabo VNC console `<vnc-console-ip>:<vnc-port>`** (which
bypasses the firewall). ⚠ Both placeholders are deliberate — the real values live in the gitignored
`tools/ops.local.json` (see *Secrets*), never in a tracked file.

⚠ **Public SSH is safe ONLY because sshd is key-only — and that takes TWO directives, not one.**
`PasswordAuthentication no` **and** `KbdInteractiveAuthentication no`. Kbd-interactive offers its **own**
password path on Windows OpenSSH and is **ON by default**, so `PasswordAuthentication no` alone leaves
**Administrator brute-forceable from the internet** (this was the live state until it was fixed).
⚠ Both must sit in the **global** section: `sshd_config` ends with a `Match Group administrators` block,
so a directive appended at the end silently lands **inside** it and does nothing globally.
⚠ **`sshd -T` and the config file are not the same question, and neither is the last word** — verify on
the wire: `ssh -v -o PubkeyAuthentication=no <host>` must answer
`Authentications that can continue: publickey` **and nothing else**. ⚠ For **admin** accounts Windows
OpenSSH ignores `~/.ssh/authorized_keys` and reads only
`C:\ProgramData\ssh\administrators_authorized_keys` (which is why the per-user file is absent yet login
works).

**Claude Code is installed on the box** (`C:\Users\Administrator\.local\bin\claude.exe`, native build, on
the Administrator user PATH — no Node.js on the box and none needed) and authenticated on the Max plan
(`authMethod: claude.ai`, so it draws on the subscription, **not** metered API credits — ⚠ never set
`ANTHROPIC_API_KEY` there, it silently takes precedence). Credentials live in
`%USERPROFILE%\.claude\.credentials.json` and are **per-Windows-user**, so a task running as SYSTEM would
be unauthenticated.

**Ops from any device = the `gf-vps` Remote Control session.** Scheduled task **`GF-ClaudeRC`** runs
`claude rc --name gf-vps` 24/7; open the Claude **mobile app** / `claude.ai/code` → **Code** tab →
`gf-vps` and drive the box: RCON via the panel API on `127.0.0.1:3000` (never a second poller), dvar/cfg
edits, log reads, `deploy.ps1`. **Outbound HTTPS only** — no inbound port, no key on the device.
⚠ **`rc` is a HIDDEN subcommand** (absent from `claude --help`) and is a **server mode** — it needs no TTY
and spawns one child per session. ⚠ The **`--remote-control` FLAG is a different thing** (interactive TUI,
needs a real console, dies headless) — do not substitute it. ⚠ `setup-token` tokens are **rejected** for
Remote Control; it needs full-scope OAuth. ⚠ **Exactly one server may run** (two ⇒ `ambiguous: multiple
remote-control servers match name`); its parent must be `svchost.exe`, and unregistering the task does
**not** kill the process. ⚠ **Security: the Claude account is now equivalent to the SSH key** — a permanent
admin agent on the live server, drivable by whoever holds that account.
⚠ **Claude Code on the WEB cannot reach the box** (HTTP-only sandbox proxy, raw TCP never passes) and the
app's **SSH-host** entry is **desktop-brokered** (invisible to the iPad) — both tested; the full dead-end
table is in `docs/DEV.md` *Working remotely*. Don't re-run that hunt. Box helpers are Scheduled Tasks (`register_services.ps1`):
`GF-RconPanel`, `GF-StatusService` (the single box-side RCON reader → writes the public `status.json` +
`activity.json` plus the `.secured`-gated `admin.json`/`health.json`, all atomically), `GF-ConnLogger`
(zero RCON — diffs `admin.json`), `GF-JoinNotify` (ntfy alerts), `GF-Watchdog` (short-lived, re-invoked
every 3 min so it can't exhaust a retry budget; restarts dead tasks, recovers wedges, `map_rotate`s a
stuck match). Every `register_services.ps1` task runs through the **`run_service.ps1` flight recorder**:
all service output incl. the terminating error that killed it → `storage\t5\logs\services\<Task>.log`
(timestamped, size-capped, outside the mirror; `GF-RconPanel` deliberately not routed — different
registrar). Before 2026-08-02 a dead service left NO evidence ([[vps-status-log-notify-services]]). ⚠ **`GF-Watchdog` judges the GAME server by the `plutonium-bootstrapper-win32` PROCESS +
`admin.json` liveness, never by `GF-GameServer`'s task State** — a GSC **compile crash** (`SV_Shutdown`)
drops the game exe while the task's `cmd.exe`/bat wrapper survives, so State reads `Running` while the
server is DOWN. Escalation ladder in `watchdog.ps1`: **3a** kills a wedged `plutonium.exe` updater
(bootstrapper gone, launcher up >120s) and trusts the bat to relaunch; **3b** kills a *hung* bootstrapper
(process up, status dark >300s) and trusts the bat; **3e** is the compile-crash net — bootstrapper gone +
status dark >300s + `GF-GameServer` still `Running` + 3a didn't act this run → clears strays and
**Stop/Start-restarts the `GF-GameServer` task** (a fresh bat wrapper — the manual fix that worked live
2026-07-12). 3e waits one full cycle past 3a (via `$updaterRemediatedThisRun`) so a self-healing bat gets
first crack before the heavier task bounce ([[deploy-restart-wedges-on-plutonium-updater]]).

**Staying current with Plutonium is automatic, and no longer costs restart time.** The CDN advertises
`{revision}` at `cdn.plutoniummod.com/updater/prod/info.json` and the official updater maintains the
local one in `%LOCALAPPDATA%\Plutonium\info.json`, so "update available" is a **two-integer compare over
one HTTPS GET**. The two halves are split on purpose: **watchdog check 5** owns the POLICY (every 30 min
— drift + **empty** server → bounce `GF-GameServer` under a maintenance marker; players on → alert once
per revision and wait for empty), while the launch bat owns the APPLY via
**`tools/vps_services/update_plutonium.ps1`** — already current → the updater is **never started** (it
does not exit on its no-op path, which used to make every restart pay ~2 min; a restart is now ~16s),
pending → started and cleared the instant the new revision **lands**. ⚠ Two invariants: it sits in the
launch path so it never blocks (always `exit 0`; `$ErrorActionPreference` deliberately **not** `Stop`,
inverting the service pattern), and its run paths stand the watchdog down with a self-expiring,
extend-only marker so 3a cannot reclaim a long first install
([[deploy-restart-wedges-on-plutonium-updater]]).

**Muting a player (the owner's own connects).** `tools/ignore.local.json` (gitignored + `/XF`-excluded,
so it's box-local; shared loader `tools/ignore_list.ps1`, re-read on change with no restart) lists GUIDs
that are **excluded from activity, not from presence**. `GF-StatusService` filters them out of the
`recent` ring and the public `activity.json` **at the projection, never at the source** — `conn_logger`
still writes every connect to the `players_*.log` day-files, so the admin history stays complete and
un-muting restores the feed retroactively — while they stay in `status.json`'s live `players` list, so
the site's "who's on right now" remains truthful. `GF-JoinNotify` applies the same list *harder*: an
ignored player is treated as **not connected at all**, so they can't count toward "N online" or suppress
the high-priority "server now active" push when a real player joins.
⚠ **Panel-first rule: never add another direct RCON poller on the box** — all readers go through the
panel API on `127.0.0.1:3000`. The same rule now covers **geo**: the panel is the box's single ip-api
client (disk-cached `.geocache.json`, paced under the free tier's 45 req/min), and `/api/geoip?ips=`
is the cache-first, non-blocking batch read everything else uses. Player IP/GUID data reaches the web
only behind IIS Basic auth + the `.secured` interlock.

**Public connect history + country flags.** `activity.json` (public web root, **no** `.secured` gate) is
a 7-day connect/leave feed parsed from the same `players_*.log` day-files as the admin history, but
**PII-stripped**: time/name/event/session + a 2-letter country code, never an IP or GUID. status.html
renders it as a searchable feed and puts a flag next to each live player. Flags are **self-hosted SVGs**
(`site/wwwroot/assets/flags/`, vendored circle-flags) — emoji flags are NOT usable, they don't render on
Windows, and self-hosting keeps the CSP's `img-src 'self'` intact. ⚠ The feed inherits conn_logger's
chain (no `.secured` → no `admin.json` → no day-files → empty feed); status.js falls back to the live
in-memory `recent` ring in that case. Full runbook → `docs/VPS_DEPLOY.md`. Admin site + connection history →
[[gf-admin-connection-history]].

---

# T5 Engine Cheatsheet

> The load-bearing "how to write correct T5 GSC on this engine" reference. This is the **only**
> auto-loaded copy (`docs/REFERENCE.md` is scoped to *this mod's* code). Keep it inline.

## T5 GSC — critical API differences (confirmed-broken → correct)
| Broken in T5 mods | Correct T5 replacement |
|---|---|
| `getPlayers()` | `level.players` (engine array, always available) |
| `player isAlive()` (METHOD form) | `isAlive(player)` — the **free-function form IS registered in the MP VM** and runs live in shipped code (`_gf_rounds.gsc` ×4, the vendored bots throughout); `player.health > 0` also works. Same method-vs-bare trap as `visionSetNaked` below. This row used to declare BOTH forms broken — retired 2026-07-28, the shipped call sites are the proof. |
| `player.team` | `player.pers["team"]` → `"allies"`/`"axis"`/`"spectator"` |
| `level.onGiveLoadout = ::fn` | Does not exist. Loadout is delivered via `level.giveCustomLoadout` (called by `_class::giveLoadout`); lifecycle via `level.playerSpawnedCB`. |
| `player visionSetNaked(...)` | `visionSetNaked(...)` — a **bare** builtin in the MP VM (global to all clients); the method form throws unknown-function ([[vector-scale-in-common-scripts-utility]]). |

⚠ **`spawnstruct()` WORKS in T5 MP mod scripts** — this table listed it as broken for months while
shipped code disproved it live (`_gf_hud.gsc::gf_getTeamHealthStats` builds one on the health-stats
hot path every 0.1s; `_bot_utility.gsc:192` too, 24/7 on the VPS). Associative arrays remain a fine
substitute, but do not redesign around "spawnstruct is broken" — it isn't. (Settled 2026-07-28; if
`notifyMessage` genuinely fails, its cause is something else — `oldNotifyMessage` stays preferred on
its own merits: native FX, serialized, zero mod hudelems.)

`setDvar("scr_player_healthregentime","0")` DOES work — set it before `_healthoverlay::init()` threads
and the engine disables regen itself.

**Compile-error diagnosis:** `unknown function: @ scripts/mp/<file>::<func>` means the broken call is
*inside* the named function — scan every call within it for (a) a T5-incompatible builtin, (b) a helper
in an un-`#include`d file, (c) a bare builtin called with a method prefix, or (d) **a function you
deleted from a stock script you override**. Causes (b)/(c) → [[vector-scale-in-common-scripts-utility]].

⚠ **For (a): the raw dump proves a builtin EXISTS, not that it exists in the MP VM — grep
`raw/maps/mp` specifically, never all of `raw/`.** Builtins are registered per-VM, and the dump mixes
SP/ZM/MP freely, so a name with hits only in `maps/_rockclimb.gsc` / `maps/_zombiemode.gsc` /
`maps/_utility.gsc` is SP/ZM evidence and tells you nothing about MP. Cost a real compile error
2026-07-27: **`GetNormalizedMovement()`** (hits: `_rockclimb`, `_horse` — **zero** under `raw/maps/mp`)
failed the whole server with `unknown function @ _gf_debug::gf_probeloadgap`. Proven MP-safe for input
polling: `AttackButtonPressed` / `JumpButtonPressed` / `MeleeButtonPressed` / `UseButtonPressed` /
`FragButtonPressed` (all have `raw/maps/mp` hits). ⚠ Note the button-poll list further down this file
includes **`AdsButtonPressed`**, which has **no** `raw/maps/mp` hits — unverified in MP, so don't reach
for it without testing. When no MP hit exists, prefer a plain **field** read (`self.origin`,
`getPlayerAngles()`) over a builtin: a field carries no registration risk at all.

⚠ **(d) — overriding a stock script means keeping its ENTIRE public surface.** GSC resolves symbols at
**compile** time, so a stock caller links against your file *unconditionally* — even from inside a
runtime guard that would never be true. ⚠ **This mod DOES override one: `maps/mp/gametypes/_bot.gsc`**
(the vendored reconciler shadows stock's) — and `mp_hotel` + `mp_outskirts` call
`_bot::bot_is_idle()` from their idle-bot ambient code, so those two maps failed the **whole server**
with `unknown function` until a stub was added. The base `raw/` dump has **zero** `gametypes\_bot::`
callers, so grepping it proves nothing — DLC map scripts live only inside their `.ff`. And no dvar can
fix it (`scr_elevator_failsafe` gates the call at *runtime*; it is still compiled)
([[dlc-map-scripts-call-stock-bot-is-idle]]). `_globallogic_ui::menuClass` does `if (isPregame()) self
maps\mp\gametypes\_pregame::OnPlayerClassChange(response);`, so shipping a `_pregame.gsc` without that
function fails the WHOLE server with `unknown function @ _globallogic_ui::menuclass` — naming the
caller, not the missing symbol. Before overriding any stock script, grep the raw dump for
`<scriptname>::` and keep every function you find, stubbed if unused.

## T5 engine reference

**Overridable engine/SD callbacks** (most set via `level.*` in `main()`): `playerSpawnedCB` (fires
`spawned_player`), `onSpawnPlayer`/`onSpawnPlayerUnified`, `onPlayerKilled`, `onPlayerDamage`,
`onDeadEvent(team)`, `onOneLeftEvent(team)`, `onTimeLimit`, `onRoundSwitch`, `onRoundEndGame` (returns
the match winner), `giveCustomLoadout`, `_setTeamScore`/`_getTeamScore`. Note `level.maySpawn` is set in
`onStartGameType` and **must be re-set every round** (map_restart wipes it); `spawnClient`/`spawnPlayer`
are engine defaults the mod does not override.

**Spawn pipeline (`spawnPlayer()` order):** (1) `setSpawnVariables` (origin/angles/team,
`sessionstate="playing"`); (2) `[[level.onSpawnPlayer]]()` selects the point and `self spawn(...)`;
(3) `[[level.playerSpawnedCB]]()` fires `spawned_player`; (4) `_class::setClass`; (5)
`_class::giveLoadout` → `[[level.giveCustomLoadout]]()` (our loadout is built here).

**Key state vars:** `game["state"]` (`playing`/`postgame`), `game["roundswon"][team]`,
`game["roundsplayed"]`, `game["switchedsides"]`, `level.gameEnded`, `level.inGracePeriod` (blocks
dead-event/forfeit), `level.inOvertime` (blocks all new spawns), `level.aliveCount[team]` /
`level.alivePlayers[team]` / `level.playerCount[team]`.

**Ending a round/game:** `sd::sd_endGame(winner, "")` (increments the winner's score, checks limits,
cycles the round / ends the match — no manual lives reset or `spawnClient` needed between rounds), or the
core `_globallogic::endGame(winner, reasonText)`. Score: `_setTeamScore(team, n)` / `_getTeamScore(team)`.

**Timer control:** `_globallogic_utils::pauseTimer()` / `resumeTimer()`. Score events (via
`_globallogic_score::givePlayerScore(event, player)`): `kill`, `headshot`, `assist`, `assist_25/50/75`,
`capture`, `defend`, `plant`, `defuse`, `melee_kill`, `hatchet_kill`, `other_kill`.

**Engine callbacks (`_callbacksetup.gsc`):** `CodeCallback_StartGameType`, `PlayerConnect`,
`PlayerDisconnect`, `PlayerDamage`, `PlayerKilled`, `ActorDamage`/`ActorKilled`, `VehicleDamage`,
`HostMigration`, `GlassSmash`.

**Critical gotchas:** `map_restart(true)` keeps `pers[]`/`game[]` and player positions but wipes all
`level.*` + entities; `false` wipes `pers[]`/`game[]` too (only dvars survive); threads survive both.
`updateTeamStatus()` runs `waittillframeend` → `level.aliveCount` can be one frame stale after a kill.
A **demo client is neither a human nor a bot** (`isdemoclient()` true, `istestclient()` **false**, no
`pers["isBot"]`, stock connect parks it teamless at `pers["team"] = ""`), so a bot filter must never be
written as the inverse of a humans-only filter — the real-bot test is `istestclient() && !isdemoclient()`.
`level.inGracePeriod=true` blocks forfeit/dead-event checks; `level.inOvertime=true` blocks new spawns.
`scr_disable_cac 1` auto-assigns `level.defaultClass="CLASS_ASSAULT"` and auto-spawns.

## T5 HUD system

**The per-client DRAWN render cap (the real limit).** T5 has TWO client-HUD limits and only the harmless
one is measurable: the **allocation pool** (`newClientHudElem` succeeds until ~900+ used) is NOT the
constraint; the **per-client DRAWN cap (~17-20)** is — beyond it, the last-created elements silently
don't render even though allocation succeeds and `.alpha`/`.x` read healthy. **No script probe can detect
it** (only the eye). It is **global across ALL hudelem types** (mod HUD + stock ammo/compass + score
popup + OT flag objpoint) and scales with lobby size, so a late-created element vanishes as the lobby
grows. **Mitigation: render mod HUD in the menu layer** (`ui_mp/hud_gf_health.menu`) — a separate system
with no such cap. Server pushes state via `setClientDvar` on change; itemDefs read it via `exp
rect X/Y`, `exp rect W`, `exp forecolor A`, `exp material(dvarString())`, `visible when(...)` (supports
`>`/`<=`/`&&`). Materials must be `material(dvarString())`, never a static `background` (the linker would
try to bundle the `.iwi`). Menu structure needs a `mod.ff` rebuild; dvar values don't. `setText` also
burns configstring slots that survive `map_restart`; use `setValue` for numbers and dvars for per-player
text ([[settext-configstring-exhaustion]]).

**Creation APIs (`_hud_util.gsc`):** `createFontString(font,scale)`, `createIcon(shader,w,h)`,
`createBar(color,w,h)`, `createPrimaryProgressBar()`, and server-side (all players, no per-player pool
slot) `createServerFontString(font,scale,team)`/`createServerIcon(...)`/`createServerBar(...)`. Fonts:
`default`, `bigfixed`, `smallfixed`, `objective`, `extrabig`. **Sizing:** `"default"` at `1.4` is the
reliable small-UI text combo; `fontScale` is a multiplier on the font's native raster, so `"bigfixed"`
at any scale ≤1.0 renders huge/aliased. For a **pulsing** element (score popup) set `baseFontScale`/
`maxFontScale`, not `.fontScale` (`fontPulse` resets to baseFontScale each frame). Server-side text
always renders above client bars regardless of sort.

**Transition helpers (on elements made with `createIcon`/`createBar`):** `transitionSlideIn(dur,dir)`,
`transitionSlideOut`, `hideElem`/`showElem`, `updateBar(frac)`, `setFlashFrac(frac)`.
**Element types:** `newHudElem` (server), `newClientHudElem` (client), `NewScoreHudElem` (score, a
separate pool from the ~17 cap). **Animation:** `fadeOverTime(t)` then set `.alpha`; `moveOverTime(t)`
then set `.x`/`.y`; `.glowColor`/`.glowAlpha`; `fontPulse(player)`. Standard live-element props:
`archived=false`, `hidewheninmenu=true`. Center-screen splashes: `_hud_message::oldNotifyMessage`
(native decode/typewriter FX, serialized, zero mod hudelems — preferred over `notifyMessage` on its
own merits; note `spawnstruct()` itself is NOT broken, see the cheatsheet table).

## T5 asset reference

**GiveWeapon:** `GiveWeapon(name)` or `GiveWeapon(name, dualWield /*bool*/)`. **T5 does NOT take a 3rd
camo arg like T6 in the 2-arg form** — camo goes through `CalcWeaponOptions` (below). Attachments are
baked into the name (`famas_reflex_mp`, `python_speed_mp`). Grenades AND equipment use `GiveWeapon`;
equipment also needs `SetActionSlot(1,"weapon",equip)`.

**Camo** — `camoOpts = int(self CalcWeaponOptions(camoIdx, lensIdx, reticleIdx, reticleColorIdx)); self
GiveWeapon(weapon, 0, camoOpts);`. Camo indices 0-15: 0 Default, 1 Dusty, 2 Ice, 3 Red, 4 OD Green,
5 Desert Nevada, 6 Desert Sahara, 7 Jungle ERDL, 8 Jungle Tiger, 9 Urban German, 10 Urban Warsaw,
11 Winter Siberia, 12 Winter Yukon, 13 Woodland, 14 Woodland Flora, 15 Gold. Pattern camos (5-14) don't
show on neutral-base weapons (python/knife/pistols/launchers). `crossbow_explosive` is the exception
(patterns + gold show). `custom_class["camo_num"]` is a dead end here (only affects the on-back model +
requires a CUSTOM class). Special primaries (minigun/m202/defaultweapon) reject camo — force index 0.

**Perks** (`SetPerk`/`hasPerk`/`UnSetPerk`). **A CAC perk is a `|`-delimited GROUP of `specialty_*`
tokens, and a Pro ability is just EXTRA tokens in that group** (`_class::validatePerkGroup` splits it,
`register_perks()` SetPerks each) — so GSC can grant any perk, any Pro, or a Pro *without* its base, à la
carte. The engine's 52 valid tokens + every base→Pro pairing (verified 3 ways: the token table in
`BlackOpsMP.exe`, `_properks.gsc` stat keys, and `shrp.gsc`'s shared `PERKS_<NAME>_PRO` groups) →
[[reference_t5_perks_and_pro_specialties]]. ⚠ `mp/statsTable.csv` (the real group table) is **not** in
`raw/` and is **not extractable** — its stringtable cells are stored as hashes; don't retry.
⚠ **`specialty_armorvest` is NOT Flak Jacket — and it is NOT any Black Ops perk** (it is none of the 15;
it's an engine **leftover** token with no create-a-class row and no icon, but with **live damage code**).
We call it **"Body Armor"**, named for its effect — do **not** give it a BO1-sounding name, that is how
`specialty_blindeye` survived. It applies a flat **−20% on every non-headshot BULLET hit**
(`_class::cac_modified_damage` → `damage * perk_armorVest * .01`, default 80), live via stock
`Callback_PlayerDamage`. Gunfight grants it to everyone **knowingly** (symmetric; a softer bullet TTK
suits a 42s round) — accept that headshots bypass it, so they are worth proportionally more and both
score (= damage dealt) and the most-HP-wins decision tilt toward them. Real Flak Jacket is
`specialty_flakjacket` (explosives; also granted); its Pro is `specialty_fireproof` (not granted).
**GF's base set (9, every spawn, `gf_giveCustomLoadout`):** `fallheight` (Lightweight Pro — the speed
half `movefaster` is deliberately NOT granted: +7% made the 42s rounds twitchy; `perk_speedMultiplier`
reaches nobody unless an admin opts it back in via `gf_perk_on`),
`longersprint` + `unlimitedsprint` (Marathon + Pro), `armorvest` (Body Armor, above), `flakjacket`
(Flak Jacket), `shades` + `stunprotection` (Tactical Mask Pro's two halves), `loudenemies` (Ninja Pro's
"enemies are louder" half), `fastmeleerecovery` (Steady Aim Pro's melee half — *"recovery rate after
lunging with knife is reduced"*). **Five Pros are granted without their base perk** — that's the
à-la-carte model, not an oversight. ⚠ **`fastmeleerecovery` needs NO dvar**: it gates
`perk_weapMeleeMultiplier`, whose *registered default 0.5 already halves recovery time* — the default **is**
the perk ([[perk-multiplier-defaults-are-the-effect]]). ⚠ **`bulletflinch` (Hardened Pro) is deliberately NOT here** — it is a second
flinch multiplier (0.2×) under `scr_gf_flinch` and belongs to the sniper/heavy package alone (see Flinch). `loudenemies` is the trick for
*globally louder footsteps*: it is **listener-side**, so granting it to everyone (and `quieter` to nobody)
makes everyone hear everyone else louder, symmetrically — there is no footstep-volume dvar in the engine
(`cg_footsteps` is a **client** dvar; `perk_footstepVolume*` does not exist).
⚠ `unlimitedsprint` and `loudenemies` are both **engine-consumed with zero GSC references** — they are the
two base perks whose effect is *unverified in-game*. If `unlimitedsprint` proves live, retire
`scr_gf_sprint_unlimited` / `player_sprintUnlimited` entirely.

**Per-loadout perks** — `gf_load()`'s optional 8th field: a comma-separated specialty list layered on the
base set, `-token` to remove one. Parsed once at pool build, applied after the base set and before the
RCON override layer (so admin toggles still win). **Only 3 reach the HUD** (the overview has 3 perk
icons): base perks are preferred over Pros and **the same icon is never used twice** — a Pro has no art of
its own and borrows its parent's, so a perk beside its own Pro would render one icon twice. Today: 43
loadouts run the base set alone; the 8 snipers + M202 + Minigun carry the **sniper/heavy package** (9
perks: Hardened + **Hardened Pro's flinch half**, Steady Aim + both Pros, Scout + Pro, Sleight of Hand +
Pro), which displays as Hardened / Steady Aim / Scout. `specialty_bulletflinch` rides **here and nowhere
else** — it is the 0.2× `perk_damageKickReduction` gate, so these 10 loadouts take ~½ the flinch everyone
else does (and it costs no HUD slot: its icon parent, Hardened, is already shown). The **8 snipers additionally drop Body Armor** (`-specialty_armorvest`), so
they take **full** non-headshot bullet damage — they out-range you, so they don't also out-tank you. The
**M202 and Minigun keep it** and stay heavy tanks; that asymmetry is deliberate. Edit it all in
`tools/loadout_editor` (checkbox grid + one-click package); its save-time validator rejects any token the
engine doesn't know.
Common: `specialty_movefaster` (Lightweight) + `specialty_fallheight` (its Pro), `specialty_longersprint`
(Marathon) + `specialty_unlimitedsprint` (its Pro), `specialty_fastreload` (SoH) + `specialty_fastads` (its Pro),
`specialty_gpsjammer` (Ghost), `specialty_bulletpenetration` (Hardened) + `specialty_bulletflinch` (its
Pro — reduced flinch when shot), `specialty_quieter` (Ninja), `specialty_gas_mask` (Tactical Mask) +
`specialty_shades`/`specialty_stunprotection` (its Pro — flash/stun resist), `specialty_holdbreath`
(Scout) + `specialty_fastweaponswitch` (its Pro), `specialty_bulletaccuracy` (Steady Aim),
`specialty_scavenger`, `specialty_twoattach` (Warlord) + `specialty_twogrenades` (its Pro).

**HUD shaders** — weapons default to `"menu_mp_weapons_" + base` (base = no `_mp`, no variant suffix).
Special cases: `ithaca_grip→…ithaca`, `stoner63→…stoner63a`, `crossbow_explosive→…crossbow`,
`minigun_wager→…minigun`, `python_speed→…python`, `m1911→…colt`, `makarov→…makarov`, `cz75→…cz75`.
Lethals: `frag_grenade→hud_grenadeicon`, `satchel_charge_mp→hud_icon_satchelcharge`,
`sticky_grenade→hud_icon_sticky_grenade`, `hatchet→hud_hatchet`. Tacticals use a `hud_us_` prefix:
`flash→hud_us_flashgrenade`, `concussion→hud_us_stungrenade`, `smoke→hud_us_smokegrenade`
(Gas→`hud_icon_tabun_gasgrenade`, Decoy→`hud_nightingale`). Precache in the precache phase
(`PreCacheShader`). Named shaders usable directly: `progress_bar_bg/fill/fg`, `score_bar_bg/allies/opfor`,
`waypoint_*` / `compass_waypoint_*` (`capture`/`defend`/`captureneutral`), `white`, `black`,
`hud_death_suicide` (the skull the health panel + Finger-Gun reuse).

**Audio:** `self playLocalSound(alias)`, `_utility::playSoundOnPlayers(alias, team)`,
`play_sound_in_space(alias, origin)`. `_globallogic_audio::leaderDialog(key[, team])` keys:
`gametype`, `last_one`, `halftime`, `round_success`/`round_failure`, `winning`/`losing`, `timesup`,
`challenge` (set the alias via `game["dialog"][key]`). Music:
`_globallogic_audio::set_music_on_team(state, team)` (`MP_LAST_STAND`, `TIME_OUT`, `SILENT`, …);
`actionMusicSet("state")`.

**Classes/menus:** `level.defaultClass="CLASS_ASSAULT"`; classes `CLASS_ASSAULT`/`SMG`/`CQB`/`LMG`/
`SNIPER`, `CLASS_CUSTOM1..10`. Menu names live in `game["menu_*"]`.

**Useful dvars:** `compass 0/1`, `compassSize`, `cg_fov`, `bg_gravity`, `scr_game_prematchperiod`. Full
weapon-name list + attachment variants → [[reference_t5_mp_weapons]]; the "oldschool/reset" dvar set
(jump/mantle/fall-damage/sprint resets) is documented there rather than pasted here.

## T5 spawn system, game objects, loadout delivery, player utilities

**Spawn points:** `_spawnlogic::getSpawnpointArray(classname)`, `getSpawnpoint_Random(points)`,
`getSpawnpoint_NearTeam(points)`, `getRandomIntermissionPoint()`. SD classnames: `mp_sd_spawn_attacker`
(allies) / `mp_sd_spawn_defender` (axis); TDM start: `mp_tdm_spawn_<team>_start`. Bias with
`_spawning::addSpawnInfluencer(origin,radius,weight,type,teamMask)` / `addSphereInfluencer`.

**Game objects (OT zone):** `zone = _gameobjects::createUseObject(ownerTeam, trigger, visuals, offset)`;
then `allowUse("friendly"|"enemy"|"any"|"none")`, `setUseTime(s)`, `setUseText(&"str")`,
`setVisibleTeam("any")`, `set2DIcon`/`set3DIcon`, `setOwnerTeam(team)`. On a `trigger_radius` the engine
runs the **proximity** think (standing accrues capture, no button). `zone.onUse` fires on capture-complete;
`getOwnerTeam()` reads the owner. Simpler waypoint: `objective_add(id,"active",origin)` +
`objective_icon(id,shader)` + `objective_state`/`_setvisibletoplayer`/`_delete`.

**Loadout delivery:** inside `giveCustomLoadout`, `_wager::setupBlankRandomPlayer(takeAll, chooseBody)`
clears the player, then `GiveWeapon`/`switchToWeapon`/`giveMaxAmmo`/`setWeaponAmmoClip`/`SetPerk`/
`SetActionSlot`. Delay grenades a few seconds after spawn to prevent spawn-instant throws.

**Player utilities:** `freezeControls(0/1)`, `DisableWeaponCycling`/`EnableWeaponCycling`,
`setSpawnWeapon`, `closePopupMenu`/`closeIngameMenu`/`closemenus`, `printBoldOnTeam(text, team)`.
Button polls (in a `wait 0.05` loop): `AttackButtonPressed`, `UseButtonPressed`, `MeleeButtonPressed`,
`AdsButtonPressed`, `JumpButtonPressed`, `FragButtonPressed`, `ActionSlotOneButtonPressed`, …
Strings: `strTok(str, delim)`, `getSubStr(str, start, end)`. Arrays: `quickSort(arr)`. Dynamic dispatch:
`self [[ fnArray[i] ]]()`. Prefer `notify`/`waittill` state machines over polling flags. Scoreboard:
`setscoreboardcolumns(...)` (`kills`/`deaths`/`assists`/`captures`/`headshots`/…). FX: `id = loadfx(path)`
then `spawnFx(id, origin)` / `triggerFx(id)` (⚠ handles are `level.*` → re-load after `map_restart`).
`trigger_off()` blocks players only — a hardcoded engine notify passes through it; divert it by repointing
the level var at a dummy `script_origin` ([[trigger-off-vs-script-notify]]).

---

## Resources (engine references only)
- **Plutonium T5 official source dump** — https://github.com/plutoniummod/t5-scripts (MP/ZM gametypes,
  `_globallogic`, `_class`, `_hud_util`, `sd.gsc`, `_wager.gsc`, …).
- **Local `raw/` engine dump** — `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\raw`
  (the definitive stock GSC/menu/weapon source; read it before reimplementing a stock system).
- **JTAG7371/T5-RawFile-Dump** — https://github.com/JTAG7371/T5-RawFile-Dump.
- **Plutonium docs** — modding/loading mods, GSC scripting features, T5 server setup, BO1 modding forum.
- **Client bind note:** the sprint↔ADS compound bind fix is in [[bo1-sprint-ads-compound-bind]].
