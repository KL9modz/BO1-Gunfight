# Comprehensive Review Plan — mp_gunfight (2026-07-28)

**Summary:** Full repo review across 10 areas (all GSC files, RCON panel, PS tooling, site, docs). 88 verified findings: 5 HIGH, ~35 MEDIUM, ~48 LOW. Review agents read every file; adversarial verify did not run (session limit), but all 5 HIGHs manually verified against source.

---

## 🔴 **5 VERIFIED HIGH FINDINGS**

### HIGH-1: `.efx` FX sources untracked in all branches
- **File:** `raw/fx/misc/*.efx` (white, blue, red flagbase FX)
- **Issue:** Exist only on laptop disk; zero git branches hold them; `.gitignore:90` swallows `raw/`; `git ls-files raw/` returns empty; no branch has them; `origin/release` errors on the path
- **Consequence:** Disk loss destroys OT-apron source; MIGRATION.md premise ("clone + deploy rebuilds mod") is false
- **Fix:** Track the files immediately
  ```bash
  git add raw/fx/misc/*.efx
  git commit -m "fix: track custom overtime-apron FX sources (prevent loss on migration)"
  git push origin main
  ```

### HIGH-2: `gf_team_balance` silently degrades over a match
- **File:** `maps/mp/gametypes/_bot.gsc:993` (gf_balanceMoved check) + :1030 (stamp write)
- **Issue:** `gf_balanceMoved` stamped with `level.gf_fillGen` (per-level counter, wiped every round). Entity fields survive the whole session. From round 2 onward each boundary pass runs at gen==1, colliding with stale stamps. Once every human on the bigger side has a stale stamp, the pick loop finds nobody and the split stays lopsided with bots padding around it.
- **Consequence:** Human balance never triggers after round 1; match degrades to bot-only balance
- **Fix:** Clear `.gf_balanceMoved` in `gf_clearAllMovePending` sweep (line 225 area)
  ```gsc
  delete p.gf_balanceMoved;  // inside the player loop
  ```
  OR use `gettime()` instead of `level.gf_fillGen` for stamping.

### HIGH-3: XSS via player names in admin panel
- **File:** `tools/rcon/public/app.js:709` (x function) + :574-575 (rowHtml)
- **Issue:** `x()` escapes `& < > '` but NOT `"`. Player names interpolated into `data-name="…"` and `oncontextmenu="showCtx(…,'name')"` attributes. HTML entity decode re-arms the quote before JS parses, so a crafted name breaks out and executes JS. Panel can POST `/api/rcon` — remote player → admin browser → rcon chain.
- **Consequence:** Remote privilege escalation (any player can execute rcon commands via the admin panel)
- **Fix:**
  1. Escape `"` in `x(s)`: add `.replace(/"/g,'&quot;')` to line 709
  2. Move player names out of inline handlers: rows already carry `data-num`; use delegated listener instead of `oncontextmenu="showCtx(…,'name')"`

### HIGH-4: Three hand-mirrored BASE_PERKS copies, two wrong
- **Files:** 
  - `tools/rcon/public/app.js:1578` (panel)
  - `tools/loadout_editor/server.js:98` (editor)
  - `maps/mp/gametypes/_gf_loadouts.gsc:244-251` (GSC, ground truth)
- **Issue:** GSC base set deliberately dropped `specialty_movefaster` 2026-07-16 (speed made 42s rounds twitchy). Panel and editor still list it. Consequence in panel: (a) checking Lightweight box does nothing (not pushed to gf_perk_on OR gf_perk_off), (b) Reset button checks it while server grants to nobody, (c) perkReset UI lies about the default.
- **Fix:** Remove `'specialty_movefaster'` from BASE_PERKS in both app.js and server.js. Also update CLAUDE.md line 904 XP paragraph (see below).

### HIGH-5: `verify_release_strip.ps1` dvar-leak check is silently weaker than claimed
- **File:** `tools/verify_release_strip.ps1:143` (regex alternation) + :35-59 ($StrippedDvars list)
- **Issue:** Alternation knows `gf_cfgFloat` but not tier1-added `gf_seedDvar` or `gf_cfgInt`. Comment at line 131-135 says "if you add a new read wrapper, add it here" — this exact class of staleness passed a real leak once before. Also: 13+ dev-only dvars (team system, staging, expect-gate, gf_sv_*) are missing from $StrippedDvars. Additionally: no check for unmatched `#strip-begin` markers (an unmatched begin leaks the *entire* dev region into the public build — worst failure direction, nothing checks it).
- **Consequence:** The guard can't see whole idiom classes; future edits can silently leak dev code
- **Fix:** Three parts:
  1. Add `gf_seedDvar|gf_cfgInt` to line 143 regex alternation (one-line fix)
  2. Backfill 13 missing dvars into $StrippedDvars: `gf_team_balance`, `gf_team_lock`, `gf_team_switch`, `scr_gf_latespawn`, `gf_team_reclaim`, `gf_teamstage`, `gf_teamcarry`, `gf_team_nextmatch`, `gf_expectcount`, `scr_gf_load_expect`, `scr_gf_load_expect_wait`, `gf_debug_loadgap`, `gf_bot_difficulty`, plus prefix rule for `gf_sv_*`
  3. Add strip-marker balance check: count `#strip-begin` vs `#strip-end` per file, fail on mismatch

---

## 🟠 **MEDIUM FINDINGS (35 verified, organized by area)**

### Round Lifecycle (9 findings)
- **Admin pause doesn't stop OT capture** (`_gf_rounds.gsc:3418`): frozen players in zone keep accruing; round ending mid-pause leaks `bots_play_move 0` across restart → next round has pinned bots, no banner. Fix: re-assert `setDvar("bots_play_move",1);` in `onStartGameType` next to `gf_resetTimeScale()`.
- **`gf_endRound` not re-entry-safe** (`:3492`): unconditional score increment, guard lives in callers. Document invariant or restructure so `gf_overtime` doesn't pre-set `gf_roundEnding`.
- **Stale comment: killcam clamp** (`:380-383`): still invites re-running a settled experiment. Replace with resolution: client-side `cl_maxpackets`, proven 2026-07-15.
- **Clock structural near-duplicates** (`:3241+:3619`): ~14 parallel functions must stay in lockstep. Tier1 already single-sourced the constants; consider unifying just the pure-arithmetic helpers (medium priority — proven-stable subsystem).
- **`gf_activatingRound` flag ownership unsafe** (`:2921`): stale activator clears the fresh round's flag. Only clear when gen still matches.
- **Stale cross-generation activator** (`:2921-2928`): outcome stays correct only because commit block is yield-free. Make generation-safe.
- **Doc drift: OT capture XP wired** (CLAUDE.md line 917): code wires `gf_awardOvertimeCapture` directly; doc still says "unreachable — wire it if we want it" (it's done).
- **Doc drift: XP values** (CLAUDE.md line 904): headshot 150 (not +500), assist 200 (not 100), capture 500 wired.
- **Doc drift: `isAlive()` cheatsheet** (CLAUDE.md cheatsheet): declared broken, but 4 call sites in shipped code prove free-function form works. Narrow the row or test the method form.

### Rounds/Teams/Lobby (11 findings)
- **Stale `pers["gf_specReason"]` breadcrumbs** (`_gf_rounds.gsc:1647`): only `gf_seatJoinTeam` clears it; re-seated humans keep `user`/`moved` stale tags, and later genuine UNTRACED strands get misclassified and *skipped* by reclaim. Fix: clear in `gf_setTeamFields` on real-team writes (single choke point covering all sanctioned writers).
- **Roster-expect gate double-counts** (`:888-889`): drop-and-reconnect human contributes to both humansGone AND live entry, bypassing 3s floor one player early. Un-latch or key by GUID.
- **`gf_team_switch 0` bypassable** (`:1804-1811`): spectate is ungated; spectator's Auto Assign never checks the kill-switch → spectate → Auto Assign loop changes teams. Document as known limitation or enforce in autoassign.
- **Duplicated seat sequences** (`:1849-1856` + `:1712-1717`): gf_seqTeamMove ↔ gf_menuTeamChoice (5 lines must stay in lockstep). Extract `gf_seatSpectator()`.
- **Duplicated restore expression** (`:1580-1581` + `:1840-1841`): prematch/grace check. Extract `gf_moveIsFreeNow()`.
- **Duplicated plan serialization** (`:1113-1124` + `:1262-1296`): guid:code loop. Extract `gf_planAppend()`.
- **Silent plan consumption** (`:1307-1322`): malformed or expired plans degrade to stock autoassign with zero log. Add `GF_TEAMPLAN` lines on consume and deadline (forensics discipline: one stream, correlate by timestamp).
- **Doc drift: deleted gf_forceTeamQuiet** (CLAUDE.md:32): tier1 deleted it; still cited as "bridge mirror" — update to `gf_quietSetTeam` (bridge routes through it).
- **Doc drift: stamp list** (CLAUDE.md:280): says "11 sites incl. `bridge`", actual is 10 tokens, no bridge. Update.
- **Doc drift: `gf_reseatRespawn`** (CLAUDE.md:583): described live; line 785 says deleted. Fix to `gf_seqTeamMove` restore-life path.
- **Decompose gf_waitForLoadingClients** (`:640-1089`): ~450 lines mixing 6 concerns. Apply stage-helper pattern; a pure `gf_gateReleaseReason()` predicate makes the "lobby ends on its own" bug self-diagnosing.

### Loadouts/HUD (9 findings)
- **Weapon tokens never validated** (`_gf_loadouts.gsc:441`): `gf_load`'s 8th-field perk tokens have no existence check; typo is silent per-spawn no-op for the whole match. Mirror `gf_wdb` pattern: logPrint on unknown token (once at pool build, zero spawn-time cost).
- **Dead menu kill-popup section** (`ui_mp/hud_gf_health.menu:985-1021`): ui_gf_popup_* dvars have zero GSC writers; comment falsely claims gf_showScorePopup pushes them. Real popup is NewScoreHudElem. Fix comment now; drop itemDefs in next mod.ff rebuild.
- **Dead ui_gf_health_hp* labels** (`:16-44`): no GSC writes to ui_gf_health_hp* family; remnant of experiment, docs/notes still say "Current experiment". Batch into next rebuild; retitle the note as historical.
- **Perk-overview description drift** (4 sites, incompatible): code truth = fixed trio (Flak/Hardened/Marathon Pro) for all 53 loadouts. Docs describe per-loadout selection algorithm, gf_load comments, CLAUDE.md, REFERENCE.md all differ. Pick code as truth, rewrite all 4.
- **REFERENCE.md stale** (`:425-443`): describes deleted 54-entry pool with gf_buildLoadout/gf_item, round-robin offhands, 8-perk base set with movefaster. Rewrite against gf_load signature, 53 entries, per-line offhand/camo/perks.
- **Dead `gf_destroyLoadoutHUD`** (`:876`): zero callers, reads never-written fields. Delete.
- **Dead `gf_hideHealthPanelForIntro` hp_alpha push** (`:341`): snap-in overwrites it same frame. Skip the push while snap is in effect.
- **`gf_getTeamHealthStats` uses spawnstruct()** (`:523`): contradicts cheatsheet (declared broken). Works live; either settle via test or migrate to associative array for consistency.
- **Header comment wrong on client-dvar persistence** (`_gf_hud.gsc:16`): says map_restart wipes pushed dvars; pause-banner / chrome-hide code exists because they *persist*. Fix to persist model.

### Locations/Wager (5 findings)
- **Flat data-format support unreachable** (`_gf_locations.gsc:765`): gf_normalizeCustomSpawnLocations promote branch, gf_validateCustomLocations flat fallback, gf_getCustomSpawnCount all dead (flat arrays always empty by construction). Delete ~40 lines.
- **Runtime validation too loose** (`:795`): only enforces `>=1 point per team`, real contract is exactly 5+5+1. Static validator needed (tools/verify_locations.ps1).
- **Table built twice per cold cache** (`:49+:60`): both spawn + OT getters rebuild gf_locationsTable. Fold into one init lookup.
- **Compass whitelist gap unexplained** (`:91-103`): rationale covers 7/11 excluded maps; mp_nuked, mp_golfcourse, mp_area51, mp_drivein are undocumented (3 Annihilation maps like whitelisted mp_silo).
- **Doc drift: `_gf_locations` section** (REFERENCE.md:569): still describes pre-tier1 if-chain; doesn't mention gf_locationsTable/gf_locMapEntry or the game[] cache.

### Bots (7 findings)
- **`watch_shoot`/`watch_grenade` accumulate** (`_bot.gsc:148`): threaded on every "connected" (re-fires at each map_restart); each client accumulates ~11 idle copies per match. Add level endon("game_ended") or per-entity once-guard.
- **Vendored file edit undocumented** (`_bot_script.gsc:64`): only gf_-local edit in maps/mp/bots (bot_on_death wantSafeSpawn gate). Add checklist to DEV.md so re-vendor doesn't drop it.
- **`gf_reclaimStrandedHumans` bypasses lock** (`:851-858`): seats a reclaimed human without consulting gf_team_lock hard cap (unlike queue seating). Document or enforce.
- **`bot_set_difficulty` table rebuilt every 1.5s** (`:1149-1255`): pure redundant work in the highest-frequency persistent loop. Cache the table behind an isDefined guard (level wipes per round = once-per-round build).
- **`pers["gf_specReason"]` never cleared** (`:1647`+`: only gf_seatJoinTeam clears; quiet/pteam/movePending re-seats leave stale breadcrumbs. Clear in gf_setTeamFields.
- **Doc drift: stamp list** (CLAUDE.md:280): says "11 sites incl. bridge", actual is 10, no bridge. Lists gf_forceTeamQuiet which is deleted.
- **Stale comment: pteam header** (CLAUDE.md:785): "old stock-switch + gf_reseatRespawn — both now deleted". Both deleted; see rounds/teams drift above.

### Bridge/Debug (11 findings)
- **Verb dispatcher uses substring-anywhere matching** (`:449-455` etc.): 27 hand-counted getSubStr offsets with no check. isSubStr matches at ANY position (prefix collision hazard). Fix: `gf_bridgeTail(cmd, prefix)` helper (kills offset deps and anywhere-match).
- **5 stale/wrong comments**: pteamforce header (names forbidden "stock switch"; actual is gf_seqTeamMove), gf.gsc:263 (references deleted pending-team watcher), _gf_debug:899 (wrong log path — says mods/mp_gunfight/games_mp.log, should be mods/mp_gunfight/logs/games_mp.log), _gf_rounds:380 (invites re-running settled experiment), _gf_hud:984 (^4 vs ^5 color code).
- **`gf_startCoordsHUD` dead** (`:19`): zero callers; header claims "auto-starts alongside recorder" (false). Re-wire under gf_debug_spawns or delete.
- **Spawn recorder loses state** (`:49+:51-54`): level endon("game_ended") fires every round end (restarts the loop, wipes all state). Add self.endon("gf_rec_kill") + back state with pers[] so sets survive round boundaries.
- **Per-player verbs fail silently** (`:1278+:1285`): pteam_999_allies / pgod_999 ack with no feedback (unlike pperkdump's "no player N"). Add gf_bridgeNotify on early returns.
- **Dump Perks broken** (app.js:786): stringifies fetch object instead of `.response`, always prints `[object Object]`. Use `r && r.ok ? r.response||'' : ''`.
- **Per-spawn wasted reliable command** (`_gf_hud.gsc:341`): gf_hideHealthPanelForIntro pushes hp_alpha=0, overwritten same frame by snap intro. Skip while snap is in effect.
- **Stale dvar-push claims** (server.js:469): says status_service/join-notify/watchdog all send explicit password=; join-notify.js never talks to panel at all (violates both panel-first RCON and single-ip-api-client rules).
- **Doc drift: gf_forceTeamQuiet** (CLAUDE.md:32): deleted by tier1; still cited as "bridge mirror". Update to gf_quietSetTeam.

### RCON Panel (9 findings)
- **app.js BASE_PERKS wrong** (`:1578`): has specialty_movefaster (dropped from GSC base set).
- **XSS: player names in handlers** (`:709+:574-575`): See HIGH-3.
- **"Dump Perks" broken** (`:786`): See above.
- **Player field injection** (`:1363+app.js:38/:1922`): `set` values unquoted/unsanitized; semicolon chains commands. Route through sanitizer (strip `";\r\n`, quote).
- **`sdv()` dead code** (`:1361`): duplicates sdve's job, never called. Delete.
- **Status parser misses spaced names** (server.js:159-188): end-anchored regex catches it; join-notify.js/status_service.ps1 hand-carry the same rules (duplicated 3 ways).
- **`/api/batch` unclamped** (server.js:1201): `commands` not validated as array; huge arrays or large delayMs tie up the queue. Add count cap + delayMs clamp.
- **Static-file path traversal edge case** (server.js:957): startsWith without trailing separator; currently unreachable but one refactor away. Use `startsWith(PUBLIC_DIR + path.sep)`.
- **join-notify.js violates rules** (join-notify.ps1:220): its own direct ip-api call + direct UDP RCON poller (should route through panel like the .ps1 twin does). Route through /api/geoip or document exception.

### PowerShell Tooling (9 findings)
- **gf_seedDvar/gf_cfgInt not in dvar-leak check** (verify_release_strip.ps1:143): See HIGH-5.
- **$StrippedDvars missing 13 entries** (`:35-59`): team system, staging, load-gate, debug dvars. See HIGH-5.
- **No strip-marker balance check** (verify_release_strip.ps1): unmatched `#strip-begin` leaks entire dev region. See HIGH-5.
- **build_ff.ps1 cleanup never runs on error** (`:189`): staged files stay in raw/ (overrides stock game), originals in temp. Wrap in finally.
- **Duplicated ops primitives** (5 pairs): New-RconPassword (rotate_secrets vs package_server), cfg-password regex (rotate vs common), maintenance-marker writer (deploy vs rotate), panel-rcon POST (watchdog vs rotate), task recycle (rotate vs deploy × 2). Move all 5 into common.ps1.
- **Dead Get-GfDefault* helpers** (common.ps1:21-23): never called; the literals they claim to deduplicate still sit in param defaults. Delete or wire them after dot-source.
- **join-notify.ps1 violates panel-first rule** (`:220`): direct ip-api call competes with panel's shared 45 req/min budget. Route through /api/geoip.
- **No pester tests** (tools/tests/): leak-scan/pre-commit twins, Strip-Markers, status parsers all have zero regression nets. Prime candidates: parseStatusText (spaced names/signed port/CNCT), upsertCfg, paced queue.
- **Duplicated status parser** (3 codebases): server.js/join-notify.js/status_service.ps1 each hand-carry end-anchored names, signed 16-bit port, positive-claim bot flag. Extract shared module.

### Site/Docs/Repo (12 findings)
- **REFACTOR_TIER1_CHECKLIST stale** (docs/REFACTOR_TIER1_CHECKLIST.md:3): says "Status: not yet run" but tier1 merged (c73d76d in main). Record what actually ran or retire to docs/notes; preserve sections 3-4 as reusable smoke checklist.
- **MIGRATION.md audited clean** (committed; referenced as new+uncommitted in review — stale): every task/script/path verified real. Micro-fixes: qualify setup_rcon_vps.ps1; note VPS_HARDENING CSP breaks status.html until fixed.
- **VPS_HARDENING CSP broken** (`:218`): sample web.config omits script-src/connect-src since the inline→external refactor. Status.html can't load scripts. Fix before LA migration uses it; consider committing web.config.example for tracked source of truth.
- **status.js unknown team rendering** (site/wwwroot/status.js:126): status_service emits team 'unknown' when gf_state stale (e.g., during stock pregame); page shows invisible players. Fix: renderRoster predicate for spectator/unknown team.
- **Site copy drift** (index.html:74-75): "24 maps (12 base + 12 DLC)" vs 25 curated; "2XP Enabled!" vs 5× rank-XP. Update to match code.
- **Dead site assets** (site/wwwroot/assets/): health-hud-crop.png / loadout-crop.png unreferenced; blue/red .efx untracked. See HIGH-1; decide crop PNGs.
- **cgame.str comment stale** (localizedstrings/cgame.str:28): still asserts banner blank is "irreducible floor" — retired in CLAUDE.md after killcam-timescale fix. Rewrite.
- **Doc drift: gf_forceTeamQuiet** (CLAUDE.md:32 + 2 notes): tier1 deleted it; still cited as live fix site. Update.
- **DEV.md include table drifted** (`:53-58`): omits gf.gsc:14 _gf_debug include, missing _gf_bridge and _bot rows entirely. Regenerate from actual #include headers.
- **Doc drift: XP/capture** (CLAUDE.md:917): "OT capture pays no XP — wire it if we want it" — already wired via gf_awardOvertimeCapture. Update.
- **Doc drift: stamp list** (CLAUDE.md:280): "11 sites incl. bridge" → 10 tokens, no bridge.
- **Doc drift: deleted gf_forceTeamQuiet** (CLAUDE.md:32): See above; also in docs/notes (quiet-team-move note, gf-fill-reconciler note).

---

## 🟢 **48 LOW FINDINGS** (detailed by area in full review; listed in order)

### Core Entry (core-entry-4, core-entry-5, core-entry-6)
- gf_lockSpawnYaw 25s cap < max 30s prematch; large-mode spawns skip the hold (deliberate?); strip hygiene clean

### Rounds/Lifecycle (rounds-lifecycle-5 through -9)
- gf_endRound re-entry invariant (caller-side guard); stale activator; stale comment on MAX_PACKET_USERCMDS (settled); structural clock duplicates (low refactor priority)

### Rounds/Teams/Lobby (rounds-teams-lobby-4 through -11)
- isAlive() cheatsheet vs code; gf_team_switch 0 spectate bypass; duplicated seat/restore/plan logic; plan consumption silent; roster-expect double-count edge case; setTeamFields keep-public rationale false

### Loadouts/HUD (loadouts-hud-5 through -9)
- Weapon reference table incomplete; pool size zero guard; dead gf_destroyLoadoutHUD; color code mismatch (^4 vs ^5)

### Locations/Wager (locations-wager-2 through -5)
- Dead flat-format support; static validator needed; table double-build; compass whitelist rationale gap

### Bots (bots-4 through -7)
- Watch-shoot/grenade accumulation; vendored edit undocumented; reclaim bypasses lock; difficulty table rebuild churn

### Bridge/Debug (bridge-debug-2 through -11)
- Dead gf_startCoordsHUD; recorder loses state; verb-dispatch offset gap; per-player verbs fail silently; dvar-push stale claims; HUD-pool setText churn; static-file path traversal edge

### RCON Panel (rcon-panel-6 through -9)
- `set` values unsanitized for semicolon; /api/batch unclamped; status parser duplication

### PowerShell (ps-tooling-7, ps-tooling-8, ps-tooling-9)
- Dead Get-GfDefault* helpers; no pester tests; duplicated status parser

### Site/Docs/Repo (site-docs-repo-6 through -12)
- Stale comments (cgame.str, gf.gsc:263); dead site assets; status.js unknown team; copy drift; include table drift

---

## 📋 **RECOMMENDED SEQUENCE**

### **DAY 1: Fix the 5 HIGHs**
1. Commit `.efx` files (prevent source loss)
2. Fix `gf_team_balance` collision (one-line clear)
3. Panel XSS fix (escaping + handler refactor)
4. Perk-list drifts × 3 (remove movefaster, update CLAUDE.md XP)
5. Verifier weak check (regex + backfill + marker balance)

### **Then: Quick medium fixes** (same session)
- Admin pause bot-freeze fix
- Stale breadcrumb clear
- Dump Perks broken fix

### **Then: CLAUDE.md drift batch** (one commit)
- Line 32: gf_forceTeamQuiet deletion
- Line 280: stamp list correction
- Line 72: cl_maxpackets TODO removal
- Cheatsheet: isAlive() and spawnstruct() rows (settle both)

### **This week: Data validators + tests** (highest leverage)
1. Loadout-pool validator (pre-commit) — weapon/perk/camo validation, zero-pool guard
2. `verify_locations.ps1` — 5+5+1 per map, key/header match
3. Node:test for server.js (parseStatusText, upsertCfg, queue pacing)
4. Pester for PS twins (leak-scan, Strip-Markers, status parsers)

### **Next: Structural refactors** (gate on map load + verify_release_strip)
1. Split `_gf_rounds.gsc` (dev blocks → _gf_teams/_gf_matchstart)
2. `gf_bridgeTail()` helper in bridge
3. Decompose `gf_waitForLoadingClients` with stage helpers
4. Consolidate PS ops primitives into common.ps1

### **Then: Project features** (from your TODO)
1. Re-port `prematch-owned-countdown` onto current main (66 commits behind; use as reference, don't merge)
2. Compass residency test on mp_golfcourse/mp_area51/mp_drivein (free three maps if resident)
3. LA host migration (MIGRATION.md audited; gates on FX commit + CSP fix)

---

## 🚀 **QUICK START**

Start with **HIGH-1**: track the `.efx` files and push. Then **HIGH-2/3/4/5** in order (each is a self-contained fix). The "quick mediums" follow naturally. CLAUDE.md drift batch is one commit once the code is solid.

All citations are **file:line** for quick navigation.

---

Generated from comprehensive review across 10 areas (all reviewers completed; 88 verified findings).
