# Notes — single-incident deep-dives

Hard-won findings, one file per incident. These were migrated out of the laptop-only `~/.claude` memory
store into the repo so they travel with a clone (and reach the VPS). **Not auto-loaded** — open the one
you need. A **`[[slug]]`** reference in `.claude/CLAUDE.md` (or in another note) resolves to
**`docs/notes/<slug>.md>`** — same slug, same filename.

Adding a finding: write `docs/notes/<slug>.md` (frontmatter + the fact; link related notes as
`[[slug]]`), then add one line below. Keep it to one line per note. Don't resurrect the `~/.claude`
memory folder as a second copy — it drifts ([[site-css-js-cache-bust-version-query]] is the analogous
"two sources diverge" trap).

## Working rules (read first)
- [read-the-server-not-the-file](read-the-server-not-the-file.md) — a cfg on disk is an INTENTION; the running process is REALITY. Seeds are if-empty and cfg execs FIRST, so a cfg line restating a default silently PINS it. cfg = deviations only.
- [cheat-protection-is-client-side-rcon-can-set](cheat-protection-is-client-side-rcon-can-set.md) — the "is cheat protected" boot spam is a CLIENT exec'ing default_xboxlive.cfg, not a server refusing you. Only cheat-protected CLIENT dvars (r_*) and archived ones (cg_fov) are truly unreachable.
- [engine-dvar-defaults-from-log-dump](engine-dvar-defaults-from-log-dump.md) — the console_mp.log dvar dump prints REGISTERED DEFAULTS, never live values. `Domain is any text` = a cfg-CREATED dvar → a `set` on a name the engine never registered is a silent PLACEBO.
- [perk-multiplier-defaults-are-the-effect](perk-multiplier-defaults-are-the-effect.md) — 0.5 = half time, and that default IS the perk. `1.0` is NOT stock, it's the WORST value. Domains CAP AT 1 → a slider offering >1 pushes values the server REJECTS. READ THE DOMAIN before calling a dvar inert.
- [seed-if-empty-dead-on-engine-registered-dvars](seed-if-empty-dead-on-engine-registered-dvars.md) — a seed never fires on an engine-registered dvar (never empty): bot_difficulty silently reverted from fu every restart. Such defaults are cfg-owned; query the name (typed Domain = registered) before writing any seed.

## Round lifecycle / freezes
- [killcam-slowmo-timescale-usercmd-backlog](killcam-slowmo-timescale-usercmd-backlog.md) — game frames/sec = `sv_fps x timescale`; stock's 0.25x killcam starves the ack rate. FIXED by clamping the slow-mo DEPTH (floor 0.6). MAX_PACKET_USERCMDS spam is a cosmetic per-packet cap, NOT the plug (client-side `cl_maxpackets 100` kills it). No in-VM probe sees a dilation — use `tools/ts_sample.ps1`.
- [infinite-round-orphaned-killcam-flag](infinite-round-orphaned-killcam-flag.md) — `finalKillcamWaiter()` spins while ANY player merely has `.killcam` DEFINED → map_restart never runs. Fixed by `gf_postRoundWatchdog`; WHICH client leaks is unproven — read `GF_ENDWATCH:`.
- [round-freeze-activation-race-and-rails](round-freeze-activation-race-and-rails.md) — gf_tryActivateRound killed mid-commit by an endon → grace stuck true. Fix = gen token + gf_roundWatchdog.
- [gf-timer-prematch-and-pause-model](gf-timer-prematch-and-pause-model.md) — CUSTOM round clock (timeLimitOverride kills the native 30s VO on 45s rounds); must start at prematch_over.
- [paused-timer-freezes-gettimepassed](paused-timer-freezes-gettimepassed.md) — pauseTimer() freezes getTimePassed() at ~0 all round; broke the grenade dud window. Audit any stock system reading it.
- [gf-stuck-after-prematch-two-gates](gf-stuck-after-prematch-two-gates.md) — ONE pre-prematch hold. `scr_gf_lobby` 0/1/2; Auto/Manual fast-restart via `map_restart(FALSE)`; loop-break flag = `gf_matchArmed` DVAR (game[] is wiped).
- [onstartgametype-perround-thread-accumulation](onstartgametype-perround-thread-accumulation.md) — it re-runs every round but threads survive map_restart → loops stack one copy/round.
- [stock-teamswitch-suicide-no-life-restore](stock-teamswitch-suicide-no-life-restore.md) — "starts round 1 dead": menuAllies/menuAxis suicide()s a frozen player without restoring pers["lives"]. Fix: gf_seqTeamMove (sequenced move).
- [quiet-team-move-cleared-class-blocks-respawn](quiet-team-move-cleared-class-blocks-respawn.md) — "autobalanced → forced to choose a class": quiet move cleared pers["class"]; stock re-begin auto-spawn is gated on isValidClass, and its fallback showMainMenuForTeam IGNORES scr_disable_cac. Fix: quiet moves to a real team assign level.defaultClass. Also: TEAMWATCH 0-lines killed the spectator-strand hypothesis; the bot mis-seater is the engine re-seating parked test clients at re-begin (routine, FILLGUARD contains).
- [stock-afk-and-spawn-kick-timers](stock-afk-and-spawn-kick-timers.md) — zero kick() calls in the mod. `g_inactivity` + `scr_kick_time` would kick a whole lobby hold; gf.gsc pins 3600.
- [sv-timeout-and-connecttimeout-template-defaults](sv-timeout-and-connecttimeout-template-defaults.md) — TWO dvars: in-game vs FIRST-JOIN budget. Template's 15 drops fullscreen alt-tabbers. Now 240/200.

## Bots / fill
- [gf-fill-reconciler-and-team-transfer](gf-fill-reconciler-and-team-transfer.md) — acts ONLY at round boundaries via race-free primitives. 3 stages: lock queue → even HUMANS off-by-1 → bots pad to max(humans, gf_fill_n); fill 0 = no bots. gf_seqTeamMove replaced every raw stock switch. Traps: threads SURVIVE map_restart(false); level.players EMPTY during onStartGameType.
- [prematch-parkpending-defers-a-round-and-lifeless-redeploy](prematch-parkpending-defers-a-round-and-lifeless-redeploy.md) — Berlin Wall 2v3 + dead teammate bot at match start: parkPending on a PREMATCH bot defers past the whole round (and masks the displacer's count) → prematch surplus now suicide-parks immediately; a redeploy of a suicide-parked bot must restore pers["lives"] or gate A strands it dead.

## Engine / GSC gotchas
- [xp-scrxpscale-readonly-and-dead-score-path](xp-scrxpscale-readonly-and-dead-score-path.md) — Pluto T5 rejects `set scr_xpscale` from rcon AND cfg. `level.overridePlayerScore` makes `givePlayerScore` return on line 1 → knobs = `registerScoreInfo` + a DIRECT `giveRankXP` call. TRAP: `logString` never reaches `games_mp.log`.
- [plutonium-stats-are-namespaced-per-mod](plutonium-stats-are-namespaced-per-mod.md) — the stats profile is keyed to `fs_game`, so `players\mods\mp_gunfight\mpstats` is its own level-1 ladder. NOT our bug, NO server-side opt-out; a mod-folder RENAME resets everyone.
- [game-ended-fires-every-round-end](game-ended-fires-every-round-end.md) — `endon("game_ended")` means "die at the next round end". With a once-per-MATCH thread gate it is lethal and SILENT. Has bitten twice.
- [gsc-notify-kills-the-notifying-thread](gsc-notify-kills-the-notifying-thread.md) — `notify("X")` terminates every thread with `endon("X")` INCLUDING the caller. Fix: `level thread` the call sites.
- [vector-scale-in-common-scripts-utility](vector-scale-in-common-scripts-utility.md) — three causes of T5 "unknown function": un-included helper; bare builtin with a method prefix; a function DELETED from a stock script you OVERRIDE. All blame the enclosing func. Grep the raw dump CASE-INSENSITIVELY.
- [getdvarint-on-enum-dvar-broke-cheat-guard](getdvarint-on-enum-dvar-broke-cheat-guard.md) — `dedicated` is an ENUM whose VALUE is a STRING → getDvarInt returns 0 on EVERY server.
- [flinch-bg-viewkickscale-not-replicated](flinch-bg-viewkickscale-not-replicated.md) — the client scales view kick from its LOCAL copy (worked on a listen host because the host IS a client). Fix = per-client push, unconditional.
- [hardened-pro-flinch-perk-multiplier](hardened-pro-flinch-perk-multiplier.md) — `perk_damageKickReduction` 0.2 = the kick REMAINING (80% cut), and it MULTIPLIES with scr_gf_flinch → 10% of stock flinch. A `perk_*` dvar is a magnitude its `specialty_*` perk silently arms.
- [player-sprintunlimited-one-way-connect-push](player-sprintunlimited-one-way-connect-push.md) — `player_*` is a CLIENT dvar family; stock's ONLY push is at connect and pushes 1 but NEVER 0. Now owned per-spawn like flinch.
- [t5-tweakable-override-dvars-live](t5-tweakable-override-dvars-live.md) — `scr_<gt>_<cat>_<name>` beats the base tweakable and re-polls ~5s; writers must set base+override together.
- [onprecache-once-per-match-loadfx-wiped](onprecache-once-per-match-loadfx-wiped.md) — precached level.* FX handles work round 1 only; re-loadfx each round.
- [trigger-off-vs-script-notify](trigger-off-vs-script-notify.md) — trigger_off blocks players only; divert a hardcoded engine notify via a dummy script_origin.

## Audio / music
- [intro-sting-killed-by-underscore-shared-channel](intro-sting-killed-by-underscore-shared-channel.md) — MP music is ONE shared client channel; stock's sting→bed hand-off is per-player self-relative (`wait 15` from each player's OWN spawn) and late-joiner-safe. NEVER drive the underscore level-wide.

## HUD
- [killfeed-duration-client-archived](killfeed-duration-client-archived.md) — duration = `con_gameMsgWindow0MsgTime` (seconds, stock 5). A SERVER push is REFUSED. Never use an archived dvar as the control in a push test.
- [server-command-overflow-reliable-command-budget](server-command-overflow-reliable-command-budget.md) — every `setClientDvar` is ONE reliable command; the ring is FIXED. `Server command overflow` and `CL_CGameNeedsServerCommand ... CYCLED OUT` are the SAME budget. Fix = `setClientDvarS` (batched). Watch the O(n²) per-player loop pushing a per-item LIST.
- [stock-engine-string-override-via-modff](stock-engine-string-override-via-modff.md) — asset name = `<STR FILENAME>_<REFERENCE>`, so CGAME_* MUST go in cgame.str (gf.str = silent no-op). Empty renders BLANK.
- [settext-configstring-exhaustion](settext-configstring-exhaustion.md) — setText burns slots that survive map_restart. Also: invisible per-client RENDER cap ~17-20 DRAWN/player → move static chrome to the menu layer.
- [menu-rendered-loadout-overview](menu-rendered-loadout-overview.md) — fully menu-rendered (icons via material(dvarString)); layout GSC-tunable, sizes baked in the menu.
- [menu-milliseconds-client-local-no-per-round-event](menu-milliseconds-client-local-no-per-round-event.md) — `milliseconds()` = CLIENT UI-realtime (main.menu scrolls fog with it pre-connection), NOT server cg.time → server CAN'T stamp the marker. The "free" menu loadout slide is NOT viable. Settled — don't re-run the mod.ff probe.
- [overtime-icon-2d-3d-coincidence](overtime-icon-2d-3d-coincidence.md) — minimap + flag agree only when driven from the same native _gameobjects path; friendly→defend(green), enemy→capture(red).
- [ot-icon-team-hudelem-delivery-bug](ot-icon-team-hudelem-delivery-bug.md) — engine bug: newTeamHudElem not delivered when another client connects mid-round.
- [health_hud_menu_numbers](health_hud_menu_numbers.md) — (older experiment note, now SHIPPED) why team HP numbers moved off script HUD font elems into the menu layer, and the `ui_gf_health_*` dvars that drive them.

## Weapons / loadouts / spawns
- [reference_t5_mp_weapons](reference_t5_mp_weapons.md) — verified GiveWeapon() strings + invalid names + attachment variants.
- [reference_t5_perks_and_pro_specialties](reference_t5_perks_and_pro_specialties.md) — a CAC perk is a GROUP of tokens; a Pro is just EXTRA tokens → any perk/Pro is individually grantable via SetPerk. `specialty_armorvest` is "Body Armor" (an engine leftover, −20% bullet dmg) — NOT a BO1 perk. `specialty_fastads` NEVER STICKS.
- [special-weapons-precacheitem-and-camo](special-weapons-precacheitem-and-camo.md) — minigun/M202 show the icon but GiveWeapon no-ops unless PrecacheItem'd; they reject non-zero camo.
- [invalid-weapon-finger-gun-fallback](invalid-weapon-finger-gun-fallback.md) — an invalid token silently gives the engine's default "finger gun", not an error.
- [python-combo-weapon-precache-errors](python-combo-weapon-precache-errors.md) — stock data gap; fixed with stub combo files in raw/weapons/mp.
- [spawn-wrong-facing-usestartspawns-gate](spawn-wrong-facing-usestartspawns-gate.md) — small mode short-circuits to curated points. Curated branch MUST set lastSpawnTime/lastSpawnPoint.
- [firingrange-intentional-bigmap-default](firingrange-intentional-bigmap-default.md) — omitting a map from _gf_locations IS the opt-out. Don't "fix" it.
- [spawn_recorder](spawn_recorder.md) — how to use the `gf_debug_spawns` spawn-recorder dev tool (ActionSlot binds, per-map capture flow).

## Map scripts (stock)
- [extract-dlc-map-gsc-from-fastfile](extract-dlc-map-gsc-from-fastfile.md) — DLC map scripts are NOT in raw/ but ARE shipped as rawfile SOURCE in zone/Common/mp_*.ff. TWO layers of zlib.
- [silo-background-missiles-are-client-side](silo-background-missiles-are-client-side.md) — mp_silo.csc `rocket_manager`; NO server dvar/entity reaches it. Launch (mp_cosmodrome) is the opposite — `scr_rocket_event_off`.

## Build / release / deploy
- [modff-cannot-embed-new-images](modff-cannot-embed-new-images.md) — the linker writes an image REFERENCE and never embeds .iwi pixel data. Both attempts BUILT CLEAN; one would have shipped a CHECKERBOARD to every client.
- [build-stage-transitive-menu](build-stage-transitive-menu.md) — ALWAYS build via tools/build_ff.ps1. A leftover staged .menu double-registers → ALL gametypes vanish.
- [modff-drift-vs-gsc-deploy](modff-drift-vs-gsc-deploy.md) — deploy ships GSC from main but mod.ff ONLY from `release`. The HASH compare is a FALSE POSITIVE (build_ff not byte-deterministic) — compare SIZE. Stale = SMALLER.
- [vps-deploy-repo-path-and-ssh-invocation](vps-deploy-repo-path-and-ssh-invocation.md) — deploy.ps1 lives in `C:\gfdeploy\BO1-Gunfight`. Over SSH it MUST go through cmd.exe (PS 5.1 turns git's stderr into a terminating error). Game process = `plutonium-bootstrapper-win32.exe`.
- [repo-release-branch-structure](repo-release-branch-structure.md) — GitHub default branch = 'release' (NOT main). main = full dev source. 3 tiers via strip markers.
- [package-server-does-not-strip-markers](package-server-does-not-strip-markers.md) — SECURITY: the VPS bundle ships the dev block LIVE by design; only package_release.ps1 strips.
- [vps-gsc-deploy-log-verification](vps-gsc-deploy-log-verification.md) — verify via TWO logs in the storage-path mod folder: console_mp.log + logs\games_mp.log.
- [deploy-recycles-box-services](deploy-recycles-box-services.md) — bounces the load-once box services + drops a self-expiring watchdog_maintenance.json.
- [deploy-restart-wedges-on-plutonium-updater](deploy-restart-wedges-on-plutonium-updater.md) — `plutonium.exe -update-only` can hang forever. Manual fix = `Stop-Process -Name plutonium`.

## VPS / infra
- [vps-server-provisioned](vps-server-provisioned.md) — Contabo VPS (94.72.121.4, Win Server 2019). `ssh -i ~/.ssh/gf_vps Administrator@94.72.121.4`.
- [vps-launch-bat-and-maxclients-latch](vps-launch-bat-and-maxclients-latch.md) — live launcher = C:\gameserver\T5\start_mp_server.bat; sv_maxclients lives ONLY there, needs a full bat restart.
- [vps-prematch-slowmo-framehitch](vps-prematch-slowmo-framehitch.md) — GF_HITCH is game-time dilation; 99.3% prematch, FLAT across bot count → it's the ENGINE's map_restart, not our bots/HUD. Do NOT raise sv_fps.
- [what-the-democlient-is-for](what-the-democlient-is-for.md) — match recording (Theater), gated by `demo_enabled`. The KILLCAM does NOT depend on it.
- [gunfight-us-security-audit](gunfight-us-security-audit.md) — technical hardening status; leaked RCON pw rotation still open.
- [plutonium-serverkey-sets-browser-name](plutonium-serverkey-sets-browser-name.md) — the browser name = the server-key label, NOT sv_hostname.
- [connection-interrupted-mitigations](connection-interrupted-mitigations.md) — operational cfg facts (sv_maxRate 25000 in the VPS dedicated.cfg; live-vs-decoy cfg paths; HUD stagger). The round-end plug ROOT CAUSE was the killcam timescale dilation — see [[killcam-slowmo-timescale-usercmd-backlog]].
- [vps-status-log-notify-services](vps-status-log-notify-services.md) — the 3 boot-start box tasks and how status.json / admin.json / ntfy wire together.

## RCON panel / tooling
- [rcon-wrong-password-is-silent-not-an-error](rcon-wrong-password-is-silent-not-an-error.md) — Pluto drops a wrong password with no reply; looks exactly like a blocked port. `getstatus` is NOT a reachability probe. Compare password LENGTHS first — free, leaks nothing.
- [rcon-panel-queue-saturation](rcon-panel-queue-saturation.md) — Plutonium answers ~1 reply/0.7s. ONE self-scheduled /api/tick. RULES: no new direct rcon pollers; test vs DEDICATED.
- [rcon-tool-vps-connect-23char-cap](rcon-tool-vps-connect-23char-cap.md) — rcon_password CAPPED at 23 chars. "Reverts on restart" was a duplicate server squatting the port.
- [rcon-dedicated-dvar-push-limits](rcon-dedicated-dvar-push-limits.md) — 3 dvar classes (archived-blocked / cheat-protected / plain-ok). visionSetNaked is the VPS-safe look lever.
- [rcon-connect-sweep-unknown-cmd-spam](rcon-connect-sweep-unknown-cmd-spam.md) — unregistered dvars echo the error. RULE: seed any new panel dvar in gf.gsc.
- [rcon-map-rotation-editor](rcon-map-rotation-editor.md) — Pluto T5 honors rcon writes to sv_maprotation AND sv_maprotationcurrent (head = next map).
- [status-parser-name-spaces-bot-miscount](status-parser-name-spaces-bot-miscount.md) — a spaced name shifts columns. RULE: read name/addr END-anchored.
- [kick-all-bots-kicked-real-players](kick-all-bots-kicked-real-players.md) — the bot flag was fail-open and a STILL-CONNECTING client looks like a bot in `status`. A classifier's DEFAULT must never be the destructive class; identity for a kick comes from the SERVER (istestclient), never parsed text.
- [server_reference](server_reference.md) — older Gunfight dvar cheat-sheet. ⚠ Some defaults are STALE (e.g. scr_gf_timelimit shown as 1) — trust docs/REFERENCE.md + CLAUDE.md's dvar tables over this.

## Site / web / players
- [site-css-js-cache-bust-version-query](site-css-js-cache-bust-version-query.md) — IIS long-caches .css/.js but not .html, so a deploy ships new HTML + STALE cached stylesheet. Edit styles.css/setup.js → bump ?v=N in index.html + setup.html or it looks broken. Bit us live at v=4.
- [public-activity-feed-and-country-flags](public-activity-feed-and-country-flags.md) — activity.json is PII-stripped. Emoji flags DON'T RENDER ON WINDOWS (self-host SVGs); the panel is the box's SINGLE ip-api client.
- [gf-admin-connection-history](gf-admin-connection-history.md) — conn_logger diffs status_service's admin.json (0 rcon). Deployed via scp, NOT committed.
- [discord-invite-canonical-blackops](discord-invite-canonical-blackops.md) — a raw invite code → dead button. Canonical = discord.gg/blackops. Blocked by the pre-commit hook.
- [discord-widget-csp-frame-src](discord-widget-csp-frame-src.md) — the iframe is BLANK until web.config CSP gains `frame-src https://discord.com`.
- [getting-started-cb-servers-install-path](getting-started-cb-servers-install-path.md) — CB Servers = one app; free Plutonium account still needed.
- [gunfight-description-single-source](gunfight-description-single-source.md) — both in-game descriptions read ONE string GF_GAMETYPE_DESC.
- [plutonium-menu-ads-not-moddable](plutonium-menu-ads-not-moddable.md) — drawn client-side pre-connection. Our MOTD surface = `sv_motd`.
- [plutonium-client-menus-vs-raw-dump](plutonium-client-menus-vs-raw-dump.md) — the live Pluto UI ≠ the raw/ui dump. Verify from a screenshot.

## FastDL / client install
- [t5-clients-must-install-mod-no-autodownload](t5-clients-must-install-mod-no-autodownload.md) — T5 DOES auto-download the mod via sv_wwwBaseURL. The engine build must still version-match.
- [fastdl-first-join-black-screen-rebuild](fastdl-first-join-black-screen-rebuild.md) — post-download the client rebuilds the engine with NO UI. Empty ui_mp/mod.txt stub kills a 4.6s stall. Unstick: vid_restart.
- [svtimeout-connect-twice-firstjoin](svtimeout-connect-twice-firstjoin.md) — the client waits for an EOF IIS keep-alive withholds. Fix = allowKeepAlive=false for /mods.
- [fastdl-mod-download-count-counts-local-ff](fastdl-mod-download-count-counts-local-ff.md) — a count of the LOCAL mod folder, NOT the server manifest. Don't chase it.

## Client-side
- [bo1-sprint-ads-compound-bind](bo1-sprint-ads-compound-bind.md) — needs a trailing inert keynum-absorber token; HOLD ads only; Pluto reads the storage-path config_mp.cfg.
- [unknown-command-cd-and-cfg-semicolon-parse](unknown-command-cd-and-cfg-semicolon-parse.md) — client "unknown cmd cd" = stale Plutonium build; a string absent from all mod source → suspect the engine build. Also: keep `dedicated.cfg` comments semicolon-free.
