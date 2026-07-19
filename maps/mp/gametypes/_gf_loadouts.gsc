// Gunfight v3 — Loadout System
// 53 hand-authored loadouts, shuffled once per match and expanded into a round
// schedule. All players read the same game["roundsplayed"] index so loadout sync
// is guaranteed by construction.
//
// ─── How to custom-build a loadout ──────────────────────────────────────────
// Each pool entry is ONE line:
//
//   pool[n] = gf_load( PRIMARY, SECONDARY, EQUIPMENT, LETHAL, TACTICAL, CAMO, CAMO2, PERKS ); n++;
//
// You type only the weapon TOKENS (e.g. "famas_reflex_mp"); the display name and
// HUD icon are resolved automatically by gf_wdb() from the tables in
// gf_buildWeaponDB() below. Attachment swaps within a known family resolve for
// free (e.g. "famas_reflex_mp" -> "famas_gl_mp" still shows "FAMAS" + the FAMAS
// icon). A brand-new base weapon just needs one gf_reg()/gf_regFamily() row.
//
//   CAMO: 0-15 pins a camo index (see the camo table in .claude/CLAUDE.md), or
//         -1 = roll a fresh random camo each match (the old behavior). Minigun &
//         M202 are auto-forced to stock camo (they reject a real camo).
//
//   PERKS: OPTIONAL. Comma-separated specialty tokens layered on top of the base perk
//         set for this loadout only; a leading '-' REMOVES a base perk. Omit it (or
//         pass "") for the base set alone, which is what most loadouts run.
//           "specialty_holdbreath,specialty_sprintrecovery"  -> Scout + Steady Aim Pro
//           "specialty_quieter,-specialty_movefaster"        -> Ninja, no Lightweight
//         Only THREE reach the overview (it has 3 perk icons): base perks are preferred
//         over Pro abilities, and the same icon is never used twice — a Pro has no art of
//         its own and borrows its parent's, so a perk shown next to its own Pro would
//         render the same icon twice. Extra perks past 3 are silent buffs, by design: the
//         sniper/heavy package is 8 perks and shows Hardened / Steady Aim / Scout.
//         ⚠ An unknown token is a SILENT no-op (SetPerk ignores it) — pick from the
//         table in gf_buildPerkDB(), or use the loadout editor's checkboxes.
//
// Valid tokens are catalogued at the bottom of this file. Slots:
//   Lethal    : frag_grenade_mp | sticky_grenade_mp (Semtex) | hatchet_mp (Tomahawk)
//               (satchel_charge_mp is C4 — equipment slot only, never lethal)
//   Tactical  : flash_grenade_mp | concussion_grenade_mp (Stun) | willy_pete_mp (Smoke)
//               | tabun_gas_mp (Gas) | nightingale_mp (Decoy)
//   Equipment : camera_spike_mp | scrambler_mp (Jammer) | acoustic_sensor_mp
//               (Motion) | claymore_mp | satchel_charge_mp (C4) | "none" (no
//               equipment — the give is skipped and the HUD slot is hidden)
//   Minigun & M202 stay primaries (camo forced 0); true launchers appear only as
//   secondaries. The Finger Gun ("defaultweapon") rides as the Death Machine's
//   secondary — an easter-egg sidearm, not a primary.

#include maps\mp\gametypes\_gf_hud;

// ─── Public API ────────────────────────────────────────────────────────────

gf_initLoadouts()
{
    if ( isDefined( game["gf_init"] ) )
        return;

    gf_buildWeaponDB();   // token -> name/icon resolver tables (level.gf_wpnDB / _wpnFam)
    gf_buildPerkDB();     // specialty token -> display name + icon-parent (level.gf_perkDB)

    pool = [];
    n    = 0;

    // #gf-loadout-editor-begin  tools/loadout_editor rewrites every pool[n]=gf_load line
    //   between these markers. Keep the markers; hand-editing between them is fine too.

    //                        PRIMARY                     SECONDARY                  EQUIPMENT              LETHAL               TACTICAL                  CAMO CAMO2  PERKS (adds, then -removes)
    // ── AR ×8 ──
    pool[n] = gf_load( "famas_dualclip_mp",         "spas_silencer_mp",        "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "m16_elbit_dualclip_mp",     "spas_mp",                 "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "aug_silencer_mp",           "mac11dw_mp",              "claymore_mp",         "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "galil_gl_mp",               "cz75_silencer_mp",        "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "commando_mp",               "crossbow_explosive_mp",   "satchel_charge_mp",   "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "fnfal_acog_mp",             "rpg_mp",                  "camera_spike_mp",     "hatchet_mp",        "flash_grenade_mp",       -1,  -1, "specialty_holdbreath,specialty_fastweaponswitch" ); n++;
    pool[n] = gf_load( "m14_grip_mp",               "china_lake_mp",           "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1, "specialty_holdbreath,specialty_fastweaponswitch" ); n++;
    pool[n] = gf_load( "galil_silencer_mp",         "m72_law_mp",              "claymore_mp",         "sticky_grenade_mp", "willy_pete_mp",          -1,  -1, "specialty_holdbreath,specialty_fastweaponswitch" ); n++;

    // ── SMG ×6 ──
    pool[n] = gf_load( "mp5k_silencer_mp",          "pythondw_mp",             "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "dragunov_acog_mp",          "cz75dw_mp",               "satchel_charge_mp",   "hatchet_mp",        "nightingale_mp",         -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "mp5k_mp",                   "aspdw_mp",                "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "spectre_elbit_grip_mp",     "hs10dw_mp",               "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "uzi_acog_grip_mp",          "ithaca_grip_mp",          "satchel_charge_mp",   "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "pm63_extclip_mp",           "knife_ballistic_mp",      "claymore_mp",         "hatchet_mp",        "nightingale_mp",         -1,  -1 ); n++;

    // ── LMG ×4 ──
    pool[n] = gf_load( "hk21_reflex_mp",            "pm63_rf_mp",              "satchel_charge_mp",   "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "m60_grip_mp",               "python_speed_mp",         "camera_spike_mp",     "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "rpk_elbit_mp",              "m1911_extclip_mp",        "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "stoner63_extclip_mp",       "asp_mp",                  "acoustic_sensor_mp",  "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;

    // ── Sniper ×2 ──
    pool[n] = gf_load( "l96a1_mp",                  "crossbow_explosive_mp",   "camera_spike_mp",     "hatchet_mp",        "concussion_grenade_mp",  -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "wa2000_vzoom_mp",           "m72_law_mp",              "satchel_charge_mp",   "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;

    // ── Shotgun ×2 ──
    pool[n] = gf_load( "spas_silencer_mp",          "china_lake_mp",           "claymore_mp",         "hatchet_mp",        "flash_grenade_mp",       -1,  -1, "specialty_holdbreath,specialty_fastweaponswitch" ); n++;
    pool[n] = gf_load( "ithaca_grip_mp",            "aspdw_mp",                "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;

    // ── AR ×6 (expanded) ──
    pool[n] = gf_load( "ak47_dualclip_mp",          "pythondw_mp",             "acoustic_sensor_mp",  "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "ak47_ft_mp",                "cz75dw_mp",               "claymore_mp",         "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "enfield_mp",                "makarovdw_mp",            "satchel_charge_mp",   "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "g11_mp",                    "kiparisdw_mp",            "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "commando_acog_mp",          "hs10dw_mp",               "scrambler_mp",        "hatchet_mp",        "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "famas_mp",                  "python_snub_mp",          "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;

    // ── SMG ×4 (expanded) ──
    pool[n] = gf_load( "m1911_extclip_mp",          "china_lake_mp",           "acoustic_sensor_mp",  "sticky_grenade_mp", "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "m60_acog_grip_mp",          "rottweil72_mp",           "claymore_mp",         "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "skorpion_extclip_mp",       "pm63dw_mp",               "camera_spike_mp",     "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "ak74u_acog_mp",             "knife_ballistic_mp",      "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;

    // ── Sniper ×2 (expanded) ──
    pool[n] = gf_load( "psg1_ir_mp",                "rpg_mp",                  "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "dragunov_extclip_mp",       "china_lake_mp",           "claymore_mp",         "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;

    // ── Shotgun ×1 (expanded) ──
    pool[n] = gf_load( "rottweil72_mp",             "m72_law_mp",              "satchel_charge_mp",   "sticky_grenade_mp", "nightingale_mp",         -1,  -1, "specialty_fastweaponswitch,specialty_bulletaccuracy" ); n++;

    // ── Dual-wield SMG ×4 ──
    pool[n] = gf_load( "mac11_silencer_mp",         "m1911dw_mp",              "satchel_charge_mp",   "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "ithaca_grip_mp",            "pm63dw_mp",               "acoustic_sensor_mp",  "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "l96a1_mp",                  "rpg_mp",                  "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "aug_elbit_mp",              "python_acog_mp",          "scrambler_mp",        "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;

    // ── SMG/AR/Sniper (expanded ×5) ──
    pool[n] = gf_load( "mpl_acog_grip_mp",          "makarov_silencer_mp",     "satchel_charge_mp",   "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "commando_mk_mp",            "m1911_silencer_mp",       "camera_spike_mp",     "hatchet_mp",        "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "wa2000_acog_mp",            "asp_mp",                  "scrambler_mp",        "frag_grenade_mp",   "willy_pete_mp",          -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "psg1_silencer_mp",          "crossbow_explosive_mp",   "acoustic_sensor_mp",  "sticky_grenade_mp", "tabun_gas_mp",           -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "kiparis_elbit_grip_mp",     "rpg_mp",                  "claymore_mp",         "frag_grenade_mp",   "nightingale_mp",         -1,  -1, "specialty_holdbreath,specialty_fastweaponswitch" ); n++;

    // ── Heavy & mixed ×9 — Minigun/M202 stay primary; launchers are secondaries ──
    pool[n] = gf_load( "m16_ft_mp",                 "hs10_mp",                 "scrambler_mp",        "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "spas_mp",                   "python_acog_mp",          "acoustic_sensor_mp",  "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "ak74u_grip_dualclip_mp",    "makarov_extclip_mp",      "camera_spike_mp",     "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "galil_mp",                  "m1911_extclip_mp",        "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "stoner63_reflex_mp",        "cz75_auto_mp",            "acoustic_sensor_mp",  "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "m202_flash_wager_mp",       "ithaca_grip_mp",          "camera_spike_mp",     "hatchet_mp",        "flash_grenade_mp",       -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads" ); n++;
    pool[n] = gf_load( "minigun_wager_mp",          "defaultweapon",           "claymore_mp",         "hatchet_mp",        "concussion_grenade_mp",  -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_holdbreath,specialty_fastweaponswitch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_fastreload,specialty_fastads" ); n++;
    pool[n] = gf_load( "fnfal_mk_mp",               "skorpiondw_mp",           "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1, "specialty_holdbreath,specialty_fastweaponswitch" ); n++;
    pool[n] = gf_load( "hk21_acog_mp",              "cz75_auto_mp",            "satchel_charge_mp",   "hatchet_mp",        "tabun_gas_mp",           -1,  -1, "specialty_holdbreath,specialty_fastweaponswitch" ); n++;
    // #gf-loadout-editor-end

    // Fisher-Yates shuffle — random order per match, no repeat within one cycle
    for ( i = pool.size - 1; i > 0; i-- )
    {
        j       = randomInt( i + 1 );
        temp    = pool[i];
        pool[i] = pool[j];
        pool[j] = temp;
    }

    game["gf_pool"] = pool;
    game["gf_init"] = 1;

    // Resolver tables were only needed during the build (the pool now holds the
    // resolved names/icons). Drop them so they don't linger on level.
    level.gf_wpnDB  = undefined;
    level.gf_wpnFam = undefined;
    level.gf_perkDB = undefined;
}

// Deterministic loadout selection: index is derived from the persisted round
// counter, so it's idempotent — calling it multiple times per round (e.g. from
// both onStartGameType and gf_endRound) always yields the same loadout.
// Loadout changes every level.gf_cfg_roundsPerLoadout rounds.
gf_pickLoadout()
{
    if ( !isDefined( game["gf_pool"] ) )
        return;

    idx = int( game["roundsplayed"] / level.gf_cfg_roundsPerLoadout ) % game["gf_pool"].size;
    // #strip-begin
    fl = getDvar( "gf_force_loadout" );   // DEV: lock a specific loadout index for testing (-1/unset = off)
    if ( fl != "" && int( fl ) >= 0 && int( fl ) < game["gf_pool"].size )
        idx = int( fl );
    // #strip-end
    level.gf_currentLoad = game["gf_pool"][ idx ];
}

gf_giveCustomLoadout()
{
    // Restart-lobby: skip the ENTIRE loadout build. This is a throwaway frozen spawn about to be moved
    // to the spectator cam and discarded by map_restart(false), so setupBlankRandomPlayer + GiveWeapon
    // x N + CalcWeaponOptions camo packing + perks is pure wasted work per player (the biggest per-spawn
    // cost). Gated on the RESTART hold (not gf_inLobbyHold) so a non-restart Normal-mode hold — where
    // this spawn IS the match spawn and never gets rebuilt — still gets its real weapons.
    if ( isDefined( level.gf_lobbyRestartHold ) && level.gf_lobbyRestartHold )
        return;

    if ( !isDefined( level.gf_currentLoad ) )
        return;
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    load = level.gf_currentLoad;

    self maps\mp\gametypes\_wager::setupBlankRandomPlayer( true, true );

    camoIdx    = load["camo"];
    secCamoIdx = load["camoSecondary"];
    // #strip-begin
    fc = getDvar( "gf_force_camo" );   // DEV: force this camo index (0-15) on BOTH guns every spawn (-1/unset = off)
    if ( fc != "" && int( fc ) >= 0 ) { camoIdx = int( fc ); secCamoIdx = int( fc ); }
    // #strip-end
    camoOpts    = int( self CalcWeaponOptions( camoIdx,    0, 0, 0 ) );
    secCamoOpts = int( self CalcWeaponOptions( secCamoIdx, 0, 0, 0 ) );
    self DisableWeaponCycling();
    self GiveWeapon( load["primary"],   0, camoOpts );
    self GiveWeapon( load["secondary"], 0, secCamoOpts );   // own camo roll; only real-base secondaries (e.g. crossbow) display it, neutral pistols/launchers stay stock
    self GiveWeapon( "knife_mp" );
    self switchToWeapon( load["primary"] );
    // Modest reserve bump (~1 extra magazine, clamped to each weapon's max) — a
    // little more staying power than GiveWeapon's default, without a topped-off
    // (Bandolier) max stockpile.
    self gf_bumpReserveAmmo( load["primary"]   );
    self gf_bumpReserveAmmo( load["secondary"] );
    self GiveWeapon( load["lethal"] );
    lethalCount = 1;                                 // 1 of each lethal on spawn...
    if ( load["lethal"] == "hatchet_mp" )
        lethalCount = 2;                             // ...except Tomahawks, which get 2
    self setWeaponAmmoClip( load["lethal"], lethalCount );
    self SwitchToOffhand( load["lethal"] );
    self GiveWeapon( load["tactical"] );
    self setWeaponAmmoClip( load["tactical"], 1 );   // 1 tactical on spawn
    isBot = isDefined( self.pers["isBot"] ) && self.pers["isBot"];
    // "none" = an equipment-less loadout. GiveWeapon of a token the engine doesn't know
    // hands out the finger gun rather than nothing, so the slot must be skipped outright.
    if ( !isBot && !gf_slotEmpty( load["equip"] ) )
    {
        self GiveWeapon( load["equip"] );
        self SetActionSlot( 1, "weapon", load["equip"] );
    }
    self EnableWeaponCycling();

    // ⚠ Lightweight's SPEED half (specialty_movefaster, +movespeed) is deliberately OFF by default —
    // the base +7% made the tight 42s rounds feel twitchy. perk_speedMultiplier (1.07) is its
    // magnitude gate and now reaches nobody; an admin can still opt it in globally via the RCON Perks
    // tab (gf_perk_on) or a loadout via its 8th field. The Pro half below is KEPT: no-fall-damage is
    // pure QoL for a jump-heavy mode and is independent of the speed boost (à-la-carte — a Pro grants
    // without its base). Removing movefaster here is what makes it off by default in EVERY build; the
    // dev-only gf_perk_off override is no longer the thing holding it off.
    self SetPerk( "specialty_fallheight"        );   // Lightweight Pro — no fall damage (speed boost intentionally not granted)
    self SetPerk( "specialty_longersprint"      );   // Marathon
    // Marathon Pro — the sprint meter never empties. This is the ENGINE's own perk bit (it is in
    // BlackOpsMP.exe's specialty table) and it is consumed by engine movement code: no stock GSC
    // anywhere references it. That makes it strictly better than the scr_gf_sprint_unlimited /
    // player_sprintUnlimited client-dvar push, which exists only because stock's lone push is at
    // connect and is ON-only ([[player-sprintunlimited-one-way-connect-push]]). The two don't fight —
    // they're independent inputs to the same sim — so the dvar path stays until this is proven live;
    // once it is, retire scr_gf_sprint_unlimited and its per-spawn push.
    self SetPerk( "specialty_unlimitedsprint"   );   // Marathon Pro — unlimited sprint
    // ⚠ armorvest is NOT Flak Jacket, and it is NOT any Black Ops perk — it is none of the 15. It's
    // an engine LEFTOVER token (no create-a-class row, no icon) that still carries live damage code:
    // _class::cac_modified_damage does damage * (perk_armorVest * .01), a flat -20% on every
    // NON-HEADSHOT BULLET hit (the dvar defaults to 80). Kept knowingly: it is symmetric, and the
    // softer bullet TTK suits a 42s round. Costs to accept: headshots bypass it entirely, so they are
    // worth proportionally more, and both score (= damage dealt) and the most-remaining-HP round
    // decision tilt toward them.
    self SetPerk( "specialty_armorvest"         );   // Body Armor — -20% bullet damage (NOT Flak Jacket, NOT a BO1 perk)
    self SetPerk( "specialty_flakjacket"        );   // Flak Jacket (base) — reduced explosive damage. Its Pro is specialty_fireproof (fire immunity), not given.
    self SetPerk( "specialty_shades"            );   // Tactical Mask Pro (half) — flash resist; _flashgrenades cuts flash duration to 10%
    self SetPerk( "specialty_stunprotection"    );   // Tactical Mask Pro (half) — stun resist; _weapons cuts concussion time to 10%
    // ⚠ specialty_bulletflinch (Hardened Pro — "reduced reaction and recoil when shot") is NOT in
    // the base set, and must not be put back. It is a SECOND flinch multiplier stacked under
    // scr_gf_flinch: the perk gates the engine's perk_damageKickReduction, whose registered default
    // is 0.2 — and that dvar is the fraction of kick REMAINING, not the fraction removed (stock's
    // own custom-games perk editor maps its "80%" label to the value 0.2 — ui_mp/
    // custom_specialty_editor.menu). So the perk is an 80% cut on top of whatever bg_viewKickScale
    // already is, and Plutonium ships g_fix_damageKickReductionPerk 1, so it genuinely applies.
    // With it in the base set the live VPS ran 0.2 (stock kick) x 0.5 (scr_gf_flinch) x 0.2 (perk)
    // = 10% of stock flinch — "flinch feels like zero" — and scr_gf_flinch could not have restored
    // stock even at its clamp ceiling of 3. ONE reducer, not two: scr_gf_flinch owns flinch for
    // everyone, and the perk survives only in the sniper/heavy package, where flinch resistance is
    // a deliberate class trait ([[hardened-pro-flinch-perk-multiplier]]).
    // Ninja Pro's "enemy movement is louder" HALF, granted WITHOUT specialty_quieter (Ninja): nobody
    // is made quieter, but everyone hears everyone else louder. That asymmetry is the whole point —
    // it's a listener-side perk, so giving it to all makes footsteps globally louder and stays
    // symmetric. Engine-consumed (no stock GSC references it), so it is UNVERIFIED like
    // specialty_unlimitedsprint; if it turns out inert, nothing else changes.
    self SetPerk( "specialty_loudenemies"       );   // Ninja Pro (half) — everyone's footsteps are louder
    // Steady Aim Pro's melee half — "recovery rate after lunging with knife is reduced". The perk is
    // the whole feature: it gates the engine's perk_weapMeleeMultiplier, whose REGISTERED DEFAULT is
    // 0.5 = melee recovery takes half as long. There is no dvar to set — 0.5 IS the perk's effect, and
    // 1.0 would mean NO benefit (the domain is 0.01-1, so "1.0 = stock" is exactly backwards; see
    // [[perk-multiplier-defaults-are-the-effect]]). Drop perk_weapMeleeMultiplier toward 0.01 only if
    // a near-instant knife is wanted. Granted WITHOUT Steady Aim itself (specialty_bulletaccuracy).
    self SetPerk( "specialty_fastmeleerecovery" );   // Steady Aim Pro (half) — faster melee-lunge recovery
    // ⚠ Five Pro tokens above are granted WITHOUT their base perk (fallheight, shades, stunprotection,
    // loudenemies, fastmeleerecovery). That is the à-la-carte model, not an oversight: a perk is just a
    // group of specialty tokens and a Pro is extra tokens in that group, so any half is grantable
    // alone ([[reference_t5_perks_and_pro_specialties]]).
    // specialty_fastweaponswitch (gates perk_weapSwitchMultiplier) is NOT in the base set — stock
    // weapon-swap speed. It rides in the sniper/heavy package, and admins can opt in globally via
    // the RCON Perks tab (adds it to gf_perk_on below), which both grants the perk and makes the
    // "Weapon Switch Speed" slider take effect.

    // Per-loadout perks (the optional 8th gf_load field; parsed once at pool build). Layered on
    // top of the base set so a loadout can DROP a base perk, and applied before the RCON override
    // layer so an admin toggle still beats the loadout. Adds run before removes, so a token listed
    // both ways ends up removed. Both arrays are empty for an unmigrated line -> zero cost, and
    // behavior identical to before the feature existed.
    if ( isDefined( load["perkAdds"] ) )
    {
        for ( i = 0; i < load["perkAdds"].size; i++ )
            self SetPerk( load["perkAdds"][i] );
    }
    if ( isDefined( load["perkRems"] ) )
    {
        for ( i = 0; i < load["perkRems"].size; i++ )
            self UnSetPerk( load["perkRems"][i] );
    }

    // #strip-begin - RCON perk overrides (dev/main only; the public build ships the base perk set only)
    // RCON perk overrides — admin-managed extra/removed perks (rcon Perks tab).
    // Applied AFTER the base set so toggles win. Empty dvars return early, so
    // this is effectively free when no overrides are set.
    // gf_perk_on/gf_perk_off are written ONLY by the bridge, so the public build (no bridge) would
    // always read them empty — stripped so the public source carries no RCON-only dvar reads.
    self gf_applyPerkList( getDvar( "gf_perk_on"  ), true  );
    self gf_applyPerkList( getDvar( "gf_perk_off" ), false );
    // #strip-end

    // Humans only: gf_showWeaponHUD pushes ~21 setClientDvar (8 icons + 8 names + anchor/anim) to
    // build the menu-rendered loadout overview. A bot has no client, so pushing to it is pure waste
    // - and it fires for the whole bot fill in the round-start spawn wave, right at the transition.
    // Also suppressed during the RESTART lobby hold: the overview would slide in on the throwaway
    // frozen spawn then get yanked when the lobby cam moves the player to spectator (the "lobby HUD
    // flash"). The real match re-gives the loadout on the map_restart(false) spawn and shows it then.
    // Gated on the RESTART hold (not gf_inLobbyHold) for the same reason the loadout build above is:
    // a non-restart Normal-mode hold's frozen spawn IS the match spawn and never gets rebuilt, so the
    // broad flag hid the overview for all of round 1 for anyone who loaded in during the gate.
    if ( !isBot && ( !isDefined( level.gf_lobbyRestartHold ) || !level.gf_lobbyRestartHold ) )
        self thread gf_showWeaponHUD( load );
}

// ─── Helpers ───────────────────────────────────────────────────────────────

// Force a comma-separated perk list on/off (rcon Perks tab override layer).
// strTok is a native T5 builtin; an empty string returns immediately so there
// is zero cost on spawn when the admin hasn't set any overrides.
gf_applyPerkList( listStr, enable )
{
    if ( !isDefined( listStr ) || listStr == "" )
        return;

    perks = strTok( listStr, "," );
    for ( i = 0; i < perks.size; i++ )
    {
        if ( perks[i] == "" )
            continue;
        if ( enable )
            self SetPerk( perks[i] );
        else
            self UnSetPerk( perks[i] );
    }
}

// Add ~one magazine of reserve above the weapon's GiveWeapon default, clamped to
// the weapon's max stock. Same native ammo builtins stock uses for the Bandolier
// perk, but adds a fixed magazine instead of topping off to max — so guns feel a
// bit less starved without becoming bottomless. No-op past the weapon's cap.
gf_bumpReserveAmmo( weapon )
{
    if ( !isDefined( weapon ) || weapon == "" )
        return;

    stock   = self GetWeaponAmmoStock( weapon );
    maxAmmo = WeaponMaxAmmo( weapon );
    ammo    = stock + weaponClipSize( weapon );   // +1 magazine
    if ( ammo > maxAmmo )
        ammo = maxAmmo;
    self SetWeaponAmmoStock( weapon, ammo );
}

// Build one loadout from weapon tokens only — name + HUD icon for every slot are
// resolved by gf_wdb() from the tables in gf_buildWeaponDB(). camo: 0-15 pins a
// camo index; -1 = fresh random roll each match (Minigun/M202 forced to stock).
// camoSec: the SECONDARY gun's camo, same rules, independent of camo. Optional 7th
// arg -- if omitted (old 6-arg line) the secondary follows the primary's camo.
//
// perks: OPTIONAL 8th arg — a comma-separated specialty list layered on top of the
// base perk set for THIS loadout only. A leading '-' REMOVES a base perk:
//
//   "specialty_holdbreath,specialty_sprintrecovery"     add Scout + Steady Aim Pro
//   "specialty_quieter,-specialty_movefaster"           add Ninja, drop Lightweight
//
// Omitted / "" == today's behavior exactly (base set only) — that is deliberate: an
// unmigrated pool line must keep granting precisely what it granted before.
// Adds are applied before removes, so "-x" wins if a token appears both ways.
// ⚠ Only real engine tokens work. SetPerk on an unknown name is a SILENT NO-OP (that
// is how a bogus "specialty_blindeye" survived in the RCON panel for months) — the
// valid list is the 52 names in [[reference_t5_perks_and_pro_specialties]].
gf_load( pri, sec, equip, lethal, tactical, camo, camoSec, perks )
{
    load = [];

    p = gf_wdb( pri );
    load["primary"]         = p["w"];   load["primaryName"]     = p["n"];   load["primaryShader"]   = p["s"];

    s = gf_wdb( sec );
    load["secondary"]       = s["w"];   load["secondaryName"]   = s["n"];   load["secondaryShader"] = s["s"];

    e = gf_wdb( equip );
    load["equip"]           = e["w"];   load["equipName"]       = e["n"];   load["equipShader"]     = e["s"];
    // Carried on the loadout so _gf_hud can hide the overview's equipment slot without
    // having to #include this file back (the include graph is one-way: loadouts -> hud).
    load["equipNone"]       = gf_slotEmpty( equip );

    l = gf_wdb( lethal );
    load["lethal"]          = l["w"];   load["lethalName"]      = l["n"];   load["lethalShader"]    = l["s"];

    t = gf_wdb( tactical );
    load["tactical"]        = t["w"];   load["tacticalName"]    = t["n"];   load["tacticalShader"]  = t["s"];

    if ( !isDefined( camoSec ) )   // 6-arg call (pre-migration line): secondary follows primary
        camoSec = camo;
    if ( camo < 0 )
        load["camo"] = randomInt( 16 );            // -1 = fresh per-match roll
    else
        load["camo"] = camo;
    if ( camoSec < 0 )
        load["camoSecondary"] = randomInt( 16 );   // independent secondary roll (only real-base secondaries show it)
    else
        load["camoSecondary"] = camoSec;
    // Special primaries reject a real camo — force stock so GiveWeapon doesn't no-op.
    if ( isSubStr( pri, "minigun" ) || isSubStr( pri, "m202" ) )
        load["camo"] = 0;
    // The Finger Gun (defaultweapon) is an SP weapon def with no camo materials, so a
    // rolled index is meaningless on it. The give works either way (the live server runs
    // it with a random roll), but pin stock in whichever slot it lands.
    if ( pri == "defaultweapon" )
        load["camo"] = 0;
    if ( sec == "defaultweapon" )
        load["camoSecondary"] = 0;

    // Per-loadout perks. Parsed ONCE here at pool build (not per spawn) and cached on the
    // loadout, exactly like the weapon names/shaders — the pool lives in game[] and survives
    // map_restart(true), so every round of the match reuses this work.
    load["perkAdds"] = [];
    load["perkRems"] = [];
    if ( isDefined( perks ) && perks != "" )
    {
        toks = strTok( perks, "," );
        for ( i = 0; i < toks.size; i++ )
        {
            tk = toks[i];
            if ( tk == "" )
                continue;
            if ( getSubStr( tk, 0, 1 ) == "-" )
            {
                tk = getSubStr( tk, 1, tk.size );
                if ( tk != "" )
                    load["perkRems"][ load["perkRems"].size ] = tk;
            }
            else
            {
                load["perkAdds"][ load["perkAdds"].size ] = tk;
            }
        }
    }

    // ── Fixed perk overview — the SAME three tiles for every loadout ──────────────────────────
    // Gunfight's kit is shared, so the overview shows one representative perk per tier color
    // instead of a per-loadout list: Flak Jacket (Tier 1 blue) · Hardened (Tier 2 orange) ·
    // Marathon Pro (Tier 3 green). The three slots (ui_gf_lo_icon5/6/7) share one `visible` flag,
    // so all three are always filled. specialty_armorvest ("Body Armor", -20% non-headshot bullet)
    // is NOT a tile — it's a global rule of the mode, granted to everyone, not a per-loadout perk.
    //
    // gf_getPerkShader() resolves a specialty token to its create-a-class icon (reference_full,
    // stock-precached at _class.gsc:421) — that covers Flak and Hardened. A _pro_256 icon has no
    // token entry, so Marathon Pro is named by material directly and precached in onPrecacheGameType.
    // (Verified on-screen 2026-07: perk_marathon_pro_256 renders; a zombies material —
    // specialty_juggernaut_zombies, the true art for armorvest/Juggernaut — does NOT load in MP,
    // it checkerboards, which is why Body Armor stays a rule and never a tile.)
    load["perkShader0"] = gf_getPerkShader( "specialty_flakjacket" );        load["perkName0"] = "Flak Jacket";
    load["perkShader1"] = gf_getPerkShader( "specialty_bulletpenetration" ); load["perkName1"] = "Hardened";
    load["perkShader2"] = "perk_marathon_pro_256";                           load["perkName2"] = "Marathon Pro";

    return load;
}

// Is token in this list? (GSC has no array search builtin.)
gf_listHas( list, token )
{
    for ( i = 0; i < list.size; i++ )
    {
        if ( list[i] == token )
            return true;
    }
    return false;
}

// Resolve a specialty token -> { n:displayName, p:iconParent }. An unknown token degrades to
// its own name + itself (gf_getPerkShader then falls back to "white"), so a typo shows up as a
// blank icon rather than crashing — but it is still a no-op perk, so prefer the editor's picker.
gf_perkInfo( token )
{
    if ( isDefined( level.gf_perkDB ) && isDefined( level.gf_perkDB[ token ] ) )
        return level.gf_perkDB[ token ];

    info = [];
    info["n"] = token;
    info["p"] = token;
    return info;
}

// One perk row: token -> display name + the perk whose ICON to use. For a base perk the icon
// parent is itself; for a Pro ability it is the parent perk (Pros are not create-a-class items
// and have no art of their own — see gf_load).
gf_pReg( token, name, iconParent )
{
    info = [];
    info["n"] = name;
    info["p"] = iconParent;
    level.gf_perkDB[ token ] = info;
}

// The perk display table. Names match what BO1 shows in create-a-class, so the overview reads
// the way a player expects. Token list + every base->Pro pairing is verified three ways (the
// specialty table in BlackOpsMP.exe, _properks.gsc's stat keys, and shrp.gsc's PERKS_*_PRO
// groups) -> [[reference_t5_perks_and_pro_specialties]].
gf_buildPerkDB()
{
    level.gf_perkDB = [];

    // ── Perk 1 ──
    gf_pReg( "specialty_movefaster",       "Lightweight",       "specialty_movefaster" );
    gf_pReg( "specialty_fallheight",       "Lightweight Pro",   "specialty_movefaster" );
    gf_pReg( "specialty_scavenger",        "Scavenger",         "specialty_scavenger" );
    gf_pReg( "specialty_extraammo",        "Scavenger Pro",     "specialty_scavenger" );
    gf_pReg( "specialty_gpsjammer",        "Ghost",             "specialty_gpsjammer" );
    gf_pReg( "specialty_nottargetedbyai",  "Ghost Pro",         "specialty_gpsjammer" );
    gf_pReg( "specialty_noname",           "Ghost Pro",         "specialty_gpsjammer" );
    gf_pReg( "specialty_killstreak",       "Hardline",          "specialty_killstreak" );
    gf_pReg( "specialty_flakjacket",       "Flak Jacket",       "specialty_flakjacket" );
    gf_pReg( "specialty_fireproof",        "Flak Jacket Pro",   "specialty_flakjacket" );
    gf_pReg( "specialty_pin_back",         "Flak Jacket Pro",   "specialty_flakjacket" );

    // ── Perk 2 ──
    gf_pReg( "specialty_bulletpenetration","Hardened",          "specialty_bulletpenetration" );
    gf_pReg( "specialty_armorpiercing",    "Hardened Pro",      "specialty_bulletpenetration" );
    gf_pReg( "specialty_bulletflinch",     "Hardened Pro",      "specialty_bulletpenetration" );
    gf_pReg( "specialty_holdbreath",       "Scout",             "specialty_holdbreath" );
    gf_pReg( "specialty_fastweaponswitch", "Scout Pro",         "specialty_holdbreath" );
    gf_pReg( "specialty_bulletaccuracy",   "Steady Aim",        "specialty_bulletaccuracy" );
    gf_pReg( "specialty_sprintrecovery",   "Steady Aim Pro",    "specialty_bulletaccuracy" );
    gf_pReg( "specialty_fastmeleerecovery","Steady Aim Pro",    "specialty_bulletaccuracy" );
    gf_pReg( "specialty_fastreload",       "Sleight of Hand",   "specialty_fastreload" );
    gf_pReg( "specialty_fastads",          "Sleight of Hand Pro","specialty_fastreload" );
    gf_pReg( "specialty_twoattach",        "Warlord",           "specialty_twoattach" );
    gf_pReg( "specialty_twogrenades",      "Warlord Pro",       "specialty_twoattach" );

    // ── Perk 3 ──
    gf_pReg( "specialty_gas_mask",         "Tactical Mask",     "specialty_gas_mask" );
    gf_pReg( "specialty_shades",           "Tactical Mask Pro", "specialty_gas_mask" );
    gf_pReg( "specialty_stunprotection",   "Tactical Mask Pro", "specialty_gas_mask" );
    gf_pReg( "specialty_longersprint",     "Marathon",          "specialty_longersprint" );
    gf_pReg( "specialty_unlimitedsprint",  "Marathon Pro",      "specialty_longersprint" );
    gf_pReg( "specialty_quieter",          "Ninja",             "specialty_quieter" );
    gf_pReg( "specialty_loudenemies",      "Ninja Pro",         "specialty_quieter" );
    gf_pReg( "specialty_pistoldeath",      "Second Chance",     "specialty_pistoldeath" );
    gf_pReg( "specialty_finalstand",       "Second Chance Pro", "specialty_pistoldeath" );
    gf_pReg( "specialty_detectexplosive",  "Hacker",            "specialty_detectexplosive" );
    gf_pReg( "specialty_disarmexplosive",  "Hacker Pro",        "specialty_detectexplosive" );
    gf_pReg( "specialty_nomotionsensor",   "Hacker Pro",        "specialty_detectexplosive" );

    // ── Engine leftovers: real, working tokens that are NOT any of Black Ops' 15 perks. No
    //    create-a-class row means no icon of their own, so they borrow a parent's art. Usable.
    gf_pReg( "specialty_armorvest",        "Body Armor",        "specialty_flakjacket" );   // -20% bullet dmg (a GF base perk)
    gf_pReg( "specialty_bulletdamage",     "Stopping Power",    "specialty_bulletdamage" );
    gf_pReg( "specialty_rof",              "Double Tap",        "specialty_rof" );
    gf_pReg( "specialty_twoprimaries",     "Overkill",          "specialty_twoprimaries" );
    gf_pReg( "specialty_grenadepulldeath", "Martyrdom",         "specialty_grenadepulldeath" );
    gf_pReg( "specialty_explosivedamage",  "Explosive Damage",  "specialty_explosivedamage" );
}

// An empty slot — "none" (what the loadout editor writes) or a blank token. Only the
// equipment slot uses it today; the give and the HUD row are both skipped for it.
gf_slotEmpty( token )
{
    return !isDefined( token ) || token == "" || token == "none";
}

// Resolve a weapon token -> { w:token, n:displayName, s:hudShader }.
// 1) exact row (duals / specials / odd-icon pistols), 2) family default keyed on
// the token's first segment (any attachment variant of a known base), 3) a
// best-guess icon + logged warning so a missing row is visible in games_mp.log.
gf_wdb( token )
{
    if ( isDefined( level.gf_wpnDB ) && isDefined( level.gf_wpnDB[ token ] ) )
        return level.gf_wpnDB[ token ];

    parts = strTok( token, "_" );
    base  = parts[0];
    if ( isDefined( level.gf_wpnFam ) && isDefined( level.gf_wpnFam[ base ] ) )
    {
        fam = level.gf_wpnFam[ base ];
        it  = [];
        it["w"] = token;   it["n"] = fam["n"];   it["s"] = fam["s"];
        return it;
    }

    it = [];
    it["w"] = token;
    it["n"] = base;
    it["s"] = "menu_mp_weapons_" + base;
    logPrint( "GF_LOADOUT: unknown weapon token '" + token + "' — add a gf_reg/gf_regFamily row (guessed icon " + it["s"] + ")\n" );
    return it;
}

// Exact token -> name/icon (for duals, specials, and pistols whose icon base
// differs from the token, e.g. m1911 -> colt).
gf_reg( token, name, shader )
{
    it = [];
    it["w"] = token;   it["n"] = name;   it["s"] = shader;
    level.gf_wpnDB[ token ] = it;
}

// Family default keyed on a token's first segment — every attachment variant of
// this base (e.g. famas_reflex_mp / famas_gl_mp / famas_silencer_mp) resolves to
// this name + icon without its own row.
gf_regFamily( base, name, shader )
{
    it = [];
    it["n"] = name;   it["s"] = shader;
    level.gf_wpnFam[ base ] = it;
}

// Token -> name/icon tables used by gf_wdb(). Built once per match at the top of
// gf_initLoadouts(), then dropped. Families cover any attachment variant of a
// base gun; exact rows cover duals, specials, and odd-icon pistols.
gf_buildWeaponDB()
{
    level.gf_wpnDB  = [];
    level.gf_wpnFam = [];

    // ── Primary families (icon = menu_mp_weapons_<seg> unless noted) ──
    gf_regFamily( "famas",      "FAMAS",      "menu_mp_weapons_famas" );
    gf_regFamily( "m16",        "M16",        "menu_mp_weapons_m16" );
    gf_regFamily( "aug",        "AUG",        "menu_mp_weapons_aug" );
    gf_regFamily( "galil",      "Galil",      "menu_mp_weapons_galil" );
    gf_regFamily( "commando",   "Commando",   "menu_mp_weapons_commando" );
    gf_regFamily( "fnfal",      "FN FAL",     "menu_mp_weapons_fnfal" );
    gf_regFamily( "m14",        "M14",        "menu_mp_weapons_m14" );
    gf_regFamily( "ak47",       "AK-47",      "menu_mp_weapons_ak47" );
    gf_regFamily( "enfield",    "Enfield",    "menu_mp_weapons_enfield" );
    gf_regFamily( "g11",        "G11",        "menu_mp_weapons_g11" );
    gf_regFamily( "mp5k",       "MP5K",       "menu_mp_weapons_mp5k" );
    gf_regFamily( "ak74u",      "AK-74u",     "menu_mp_weapons_ak74u" );
    gf_regFamily( "mpl",        "MPL",        "menu_mp_weapons_mpl" );
    gf_regFamily( "spectre",    "Spectre",    "menu_mp_weapons_spectre" );
    gf_regFamily( "uzi",        "Uzi",        "menu_mp_weapons_uzi" );
    gf_regFamily( "pm63",       "PM63",       "menu_mp_weapons_pm63" );
    gf_regFamily( "kiparis",    "Kiparis",    "menu_mp_weapons_kiparis" );
    gf_regFamily( "mac11",      "MAC-11",     "menu_mp_weapons_mac11" );
    gf_regFamily( "skorpion",   "Skorpion",   "menu_mp_weapons_skorpion" );
    gf_regFamily( "hs10",       "HS10",       "menu_mp_weapons_hs10" );
    gf_regFamily( "hk21",       "HK21",       "menu_mp_weapons_hk21" );
    gf_regFamily( "m60",        "M60",        "menu_mp_weapons_m60" );
    gf_regFamily( "rpk",        "RPK",        "menu_mp_weapons_rpk" );
    gf_regFamily( "stoner63",   "Stoner63",   "menu_mp_weapons_stoner63a" );   // icon base has trailing 'a'
    gf_regFamily( "spas",       "SPAS-12",    "menu_mp_weapons_spas" );
    gf_regFamily( "ithaca",     "Stakeout",   "menu_mp_weapons_ithaca" );
    gf_regFamily( "defaultweapon", "Finger Gun", "hud_death_suicide" );   // real weapon (raw\weapons\sp\defaultweapon, precached in gf.gsc) -> engine's finger-gun easter egg. Icon = the skull (same material the health panel uses via ui_gf_skull_mat). (menu_mp_weapons_knife does NOT exist -> was a missing-texture checkerboard.)
    gf_regFamily( "rottweil72", "Olympia",    "menu_mp_weapons_rottweil72" );
    gf_regFamily( "l96a1",      "L96A1",      "menu_mp_weapons_l96a1" );
    gf_regFamily( "wa2000",     "WA2000",     "menu_mp_weapons_wa2000" );
    gf_regFamily( "psg1",       "PSG-1",      "menu_mp_weapons_psg1" );
    gf_regFamily( "dragunov",   "Dragunov",   "menu_mp_weapons_dragunov" );

    // ── Secondary families ──
    gf_regFamily( "python",     "Python",     "menu_mp_weapons_python" );
    gf_regFamily( "makarov",    "Makarov",    "menu_mp_weapons_makarov" );
    gf_regFamily( "cz75",       "CZ75",       "menu_mp_weapons_cz75" );
    gf_regFamily( "m1911",      "M1911",      "menu_mp_weapons_colt" );        // icon base is 'colt'
    gf_regFamily( "asp",        "ASP",        "menu_mp_weapons_asp" );
    gf_regFamily( "crossbow",   "Crossbow",   "menu_mp_weapons_crossbow" );
    gf_regFamily( "china",      "China Lake", "menu_mp_weapons_china_lake" );  // token china_lake_mp -> seg 'china'
    gf_regFamily( "m72",        "M72 LAW",    "menu_mp_weapons_m72_law" );     // token m72_law_mp -> seg 'm72'
    gf_regFamily( "rpg",        "RPG",        "menu_mp_weapons_rpg" );

    // ── Exact rows: dual-wield (icon shares the single-weapon shader) ──
    gf_reg( "pythondw_mp",    "Dual Python",    "menu_mp_weapons_python" );
    gf_reg( "cz75dw_mp",      "Dual CZ75",      "menu_mp_weapons_cz75" );
    gf_reg( "aspdw_mp",       "Dual ASP",       "menu_mp_weapons_asp" );
    gf_reg( "makarovdw_mp",   "Dual Makarov",   "menu_mp_weapons_makarov" );
    gf_reg( "m1911dw_mp",     "Dual M1911",     "menu_mp_weapons_colt" );
    gf_reg( "kiparisdw_mp",   "Dual Kiparis",   "menu_mp_weapons_kiparis" );
    gf_reg( "mac11dw_mp",     "Dual MAC-11",    "menu_mp_weapons_mac11" );
    gf_reg( "pm63dw_mp",      "Dual PM63",      "menu_mp_weapons_pm63" );
    gf_reg( "skorpiondw_mp",  "Dual Skorpion",  "menu_mp_weapons_skorpion" );
    gf_reg( "hs10dw_mp",      "Dual HS10",      "menu_mp_weapons_hs10" );

    // ── Exact rows: specials / odd icons ──
    gf_reg( "knife_ballistic_mp", "Ballistic Knife", "menu_mp_weapons_ballistic_knife" );
    gf_reg( "m202_flash_wager_mp","Grim Reaper",     "hud_m202" );
    gf_reg( "minigun_wager_mp",   "Death Machine",   "menu_mp_weapons_minigun" );

    // ── Equipment ──
    // "none" is a real row so gf_wdb() doesn't log it as an unknown token. The shader is a
    // placeholder — the menu hides that slot (ui_gf_lo_show4 0), so it is never drawn.
    gf_reg( "none",               "None",          "white" );
    gf_reg( "camera_spike_mp",    "Camera Spike",  "hud_deployable_camera" );
    gf_reg( "scrambler_mp",       "Jammer",        "hud_radar_jammer" );
    gf_reg( "acoustic_sensor_mp", "Motion Sensor", "hud_acoustic_sensor" );
    gf_reg( "claymore_mp",        "Claymore",      "hud_icon_claymore" );
    gf_reg( "satchel_charge_mp",  "C4",            "hud_icon_satchelcharge" );

    // ── Lethal ──
    gf_reg( "frag_grenade_mp",    "Frag",     "hud_grenadeicon" );
    gf_reg( "sticky_grenade_mp",  "Semtex",   "hud_icon_sticky_grenade" );
    gf_reg( "hatchet_mp",         "Tomahawk", "hud_hatchet" );

    // ── Tactical ──
    gf_reg( "flash_grenade_mp",      "Flash", "hud_us_flashgrenade" );
    gf_reg( "concussion_grenade_mp", "Stun",  "hud_us_stungrenade" );
    gf_reg( "willy_pete_mp",         "Smoke", "hud_us_smokegrenade" );
    gf_reg( "tabun_gas_mp",          "Gas",   "hud_icon_tabun_gasgrenade" );
    gf_reg( "nightingale_mp",        "Decoy", "hud_nightingale" );
}

// ─── Valid T5 MP Weapon Reference ──────────────────────────────────────────
// All names require _mp suffix.
// KNOWN INVALID: galil_grip_mp, hk21_grip_mp, stoner63_grip_mp, ithaca_mp,
//                pm63_silencer_mp, mpl_extclip_mp, smoke_grenade_mp
//                crossbow_mp (use crossbow_explosive_mp)
//                menu_mp_weapons_m202_flash (no such material; use hud_m202)
// SPECIAL/KS WEAPONS: minigun_mp, m202_flash_mp (and their _wager_ variants) ARE
//   giveable, but only if PrecacheItem'd in gf.gsc::onPrecacheGameType — they are
//   not in the normal weapon table so GiveWeapon silently no-ops without precache.
//                menu_mp_weapons_knife_ballistic (correct: menu_mp_weapons_ballistic_knife)
// Smoke grenade is willy_pete_mp (not smoke_grenade_mp)
//
// AR
//   ak47:      _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer
//   aug:       _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer
//   commando:  _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer
//   enfield:   _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer
//   famas:     _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer
//   fnfal:     _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer
//   g11:       _mp _lps _vzoom
//   galil:     _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer  (NO grip)
//   m14:       _mp _acog _acog_grip _elbit _extclip _ft _gl _grip _ir _ir_grip _mk _reflex _silencer
//   m16:       _mp _acog _dualclip _elbit _extclip _ft _gl _ir _mk _reflex _silencer
//
// SMG
//   ak74u:     _mp _acog _acog_grip _dualclip _elbit _extclip _gl _grip _grip_dualclip _grip_extclip _reflex _rf _silencer
//   kiparis:   _mp _acog _acog_grip _elbit _extclip _grip _grip_extclip _reflex _rf _silencer
//   mac11:     _mp _elbit _extclip _grip _reflex _rf _silencer
//   mp5k:      _mp _acog _elbit _extclip _reflex _rf _silencer
//   mpl:       _mp _acog _acog_grip _dualclip _elbit _grip _reflex _rf _silencer  (NO extclip)
//   pm63:      _mp _extclip _grip _rf  (NO silencer)
//   skorpion:  _mp _extclip _grip _rf _silencer
//   spectre:   _mp _acog _acog_grip _elbit _extclip _grip _reflex _rf _silencer
//   uzi:       _mp _acog _acog_grip _elbit _extclip _grip _reflex _rf _silencer
//
// LMG
//   hk21:      _mp _acog _elbit _extclip _ir _reflex  (NO grip)
//   m60:       _mp _acog _acog_grip _elbit _extclip _grip _ir _ir_grip _reflex
//   rpk:       _mp _acog _dualclip _elbit _extclip _ir _reflex
//   stoner63:  _mp _acog _elbit _extclip _ir _reflex  (NO grip)
//
// Sniper
//   dragunov:  _mp _acog _extclip _ir _silencer _vzoom
//   l96a1:     _mp _acog _extclip _ir _silencer _vzoom
//   psg1:      _mp _acog _extclip _ir _silencer _vzoom
//   wa2000:    _mp _acog _extclip _ir _silencer _vzoom
//
// Shotgun
//   ithaca_grip_mp  (NO plain ithaca_mp)
//   ks23_mp
//   rottweil72_mp
//   spas_mp  spas_silencer_mp
//
// Pistol
//   asp_mp
//   cz75:      _mp _auto _extclip _silencer _upgradesight
//   m1911:     _mp _extclip _silencer _upgradesight
//   makarov:   _mp _extclip _silencer _upgradesight
//   python:    _mp _acog _snub _speed
//
// Launcher / Special
//   china_lake_mp  crossbow_explosive_mp  knife_ballistic_mp
//   m72_law_mp  m202_flash_mp  m202_flash_wager_mp
//   rpg_mp
//
// Equipment (placed — use GiveWeapon + SetActionSlot(1,"weapon",equip))
//   none                 no equipment (give skipped, overview slot hidden)
//   claymore_mp          icon: hud_icon_claymore
//   acoustic_sensor_mp   icon: hud_acoustic_sensor      (Motion Sensor)
//   camera_spike_mp      icon: hud_deployable_camera
//   satchel_charge_mp    icon: hud_icon_satchelcharge    (C4)
//   scrambler_mp         icon: hud_radar_jammer        (Jammer)
//
// Grenades / Lethal (use GiveWeapon only — NO SetActionSlot needed)
//   concussion_grenade_mp  flash_grenade_mp  frag_grenade_mp
//   hatchet_mp  satchel_charge_mp  sticky_grenade_mp  willy_pete_mp
//
// Dual-wield (pass true as 2nd GiveWeapon arg, or use dw/lh variants)
//   aspdw/lh  cz75dw/lh  hs10dw/lh  kiparisdw/lh  m1911dw/lh
//   mac11dw/lh  makarovdw/lh  pm63dw/lh  pythondw/lh  skorpiondw/lh
