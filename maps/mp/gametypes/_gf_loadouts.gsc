// Gunfight v3 — Loadout System
// 54 hand-authored loadouts, shuffled once per match and expanded into a round
// schedule. All players read the same game["roundsplayed"] index so loadout sync
// is guaranteed by construction.
//
// ─── How to custom-build a loadout ──────────────────────────────────────────
// Each pool entry is ONE line:
//
//   pool[n] = gf_load( PRIMARY, SECONDARY, EQUIPMENT, LETHAL, TACTICAL, CAMO ); n++;
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
// Valid tokens are catalogued at the bottom of this file. Slots:
//   Lethal    : frag_grenade_mp | sticky_grenade_mp (Semtex) | hatchet_mp (Tomahawk)
//               (satchel_charge_mp is C4 — equipment slot only, never lethal)
//   Tactical  : flash_grenade_mp | concussion_grenade_mp (Stun) | willy_pete_mp (Smoke)
//               | tabun_gas_mp (Gas) | nightingale_mp (Decoy)
//   Equipment : camera_spike_mp | scrambler_mp (Jammer) | acoustic_sensor_mp
//               (Motion) | claymore_mp | satchel_charge_mp (C4)
//   Minigun & M202 stay primaries (camo forced 0); true launchers appear only as
//   secondaries.

#include maps\mp\gametypes\_gf_hud;

// ─── Public API ────────────────────────────────────────────────────────────

gf_initLoadouts()
{
    if ( isDefined( game["gf_init"] ) )
        return;

    gf_buildWeaponDB();   // token -> name/icon resolver tables (level.gf_wpnDB / _wpnFam)

    pool = [];
    n    = 0;

    // #gf-loadout-editor-begin  tools/loadout_editor rewrites every pool[n]=gf_load line
    //   between these markers. Keep the markers; hand-editing between them is fine too.

    //                        PRIMARY                     SECONDARY                  EQUIPMENT              LETHAL               TACTICAL                  CAMO
    // ── AR ×8 ──
    pool[n] = gf_load( "famas_dualclip_mp",         "spas_silencer_mp",        "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "m16_acog_mp",               "spas_mp",                 "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "aug_silencer_mp",           "mac11dw_mp",              "acoustic_sensor_mp",  "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "galil_gl_mp",               "cz75_silencer_mp",        "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "commando_mp",               "crossbow_explosive_mp",   "satchel_charge_mp",   "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "fnfal_acog_mp",             "rpg_mp",                  "camera_spike_mp",     "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "m14_reflex_grip_mp",        "china_lake_mp",           "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "galil_silencer_mp",         "m72_law_mp",              "claymore_mp",         "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;

    // ── SMG ×6 ──
    pool[n] = gf_load( "mp5k_silencer_mp",          "pythondw_mp",             "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "dragunov_acog_mp",          "cz75dw_mp",               "satchel_charge_mp",   "hatchet_mp",        "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "mp5k_mp",                   "aspdw_mp",                "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "spectre_grip_extclip_mp",   "hs10dw_mp",               "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "uzi_acog_grip_mp",          "ithaca_grip_mp",          "satchel_charge_mp",   "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "pm63_extclip_mp",           "knife_ballistic_mp",      "claymore_mp",         "hatchet_mp",        "nightingale_mp",         -1,  -1 ); n++;

    // ── LMG ×4 ──
    pool[n] = gf_load( "hk21_ir_mp",                "pm63_rf_mp",              "satchel_charge_mp",   "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "m60_acog_mp",               "python_speed_mp",         "camera_spike_mp",     "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "rpk_reflex_mp",             "m1911_extclip_mp",        "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "stoner63_extclip_mp",       "asp_mp",                  "acoustic_sensor_mp",  "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;

    // ── Sniper ×2 ──
    pool[n] = gf_load( "l96a1_mp",                  "crossbow_explosive_mp",   "camera_spike_mp",     "hatchet_mp",        "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "wa2000_ir_silencer_mp",     "m72_law_mp",              "satchel_charge_mp",   "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1 ); n++;

    // ── Shotgun ×2 ──
    pool[n] = gf_load( "spas_silencer_mp",          "china_lake_mp",           "claymore_mp",         "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
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
    pool[n] = gf_load( "m60_grip_mp",               "rottweil72_mp",           "claymore_mp",         "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "skorpion_extclip_mp",       "pm63dw_mp",               "camera_spike_mp",     "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "ak74u_acog_mp",             "knife_ballistic_mp",      "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;

    // ── Sniper ×2 (expanded) ──
    pool[n] = gf_load( "psg1_ir_mp",                "rpg_mp",                  "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "dragunov_vzoom_mp",         "china_lake_mp",           "claymore_mp",         "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1 ); n++;

    // ── Shotgun ×1 (expanded) ──
    pool[n] = gf_load( "rottweil72_mp",             "m72_law_mp",              "satchel_charge_mp",   "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;

    // ── Dual-wield SMG ×5 ──
    pool[n] = gf_load( "mac11_grip_silencer_mp",    "m1911dw_mp",              "satchel_charge_mp",   "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "defaultweapon",             "knife_ballistic_mp",      "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "ithaca_grip_mp",            "pm63dw_mp",               "acoustic_sensor_mp",  "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "l96a1_mp",                  "rpg_mp",                  "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "aug_elbit_dualclip_mp",     "python_acog_mp",          "scrambler_mp",        "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;

    // ── SMG/AR/Sniper (expanded ×5) ──
    pool[n] = gf_load( "mpl_acog_grip_mp",          "makarov_silencer_mp",     "acoustic_sensor_mp",  "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "commando_mk_mp",            "m1911_silencer_mp",       "camera_spike_mp",     "hatchet_mp",        "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "wa2000_acog_mp",            "asp_mp",                  "scrambler_mp",        "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "psg1_silencer_mp",          "crossbow_explosive_mp",   "acoustic_sensor_mp",  "sticky_grenade_mp", "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "kiparis_elbit_grip_mp",     "rpg_mp",                  "claymore_mp",         "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;

    // ── Heavy & mixed ×9 — Minigun/M202 stay primary; launchers are secondaries ──
    pool[n] = gf_load( "m16_ir_extclip_mp",         "hs10_mp",                 "scrambler_mp",        "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "spas_mp",                   "python_acog_mp",          "acoustic_sensor_mp",  "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "ak74u_grip_dualclip_mp",    "makarov_extclip_mp",      "camera_spike_mp",     "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "galil_mp",                  "m1911_extclip_mp",        "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "stoner63_reflex_mp",        "cz75_auto_mp",            "acoustic_sensor_mp",  "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "m202_flash_wager_mp",       "ithaca_grip_mp",          "camera_spike_mp",     "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "minigun_wager_mp",          "knife_ballistic_mp",      "claymore_mp",         "hatchet_mp",        "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "fnfal_mk_mp",               "skorpiondw_mp",           "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "hk21_acog_mp",              "cz75_auto_mp",            "satchel_charge_mp",   "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
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
    if ( !isBot )
    {
        self GiveWeapon( load["equip"] );
        self SetActionSlot( 1, "weapon", load["equip"] );
    }
    self EnableWeaponCycling();

    self SetPerk( "specialty_movefaster"        );   // Lightweight
    self SetPerk( "specialty_fallheight"        );   // Lightweight Pro — no fall damage
    self SetPerk( "specialty_longersprint"      );   // Marathon (no pro specialty exists in T5 source)
    self SetPerk( "specialty_armorvest"         );   // Flak Jacket
    self SetPerk( "specialty_flakjacket"        );   // Flak Jacket Pro — throwback grenades
    self SetPerk( "specialty_shades"            );   // flashbang resist — _flashgrenades cuts flash duration to 10%
    self SetPerk( "specialty_stunprotection"    );   // concussion/stun resist — _weapons cuts concussion time to 10%
    // specialty_fastweaponswitch (gates perk_weapSwitchMultiplier) is OFF by default now — stock
    // weapon-swap speed. Admins opt in via the RCON Perks tab (adds it to gf_perk_on below), which
    // both grants the perk and makes the "Weapon Switch Speed" slider take effect.

    // RCON perk overrides — admin-managed extra/removed perks (rcon Perks tab).
    // Applied AFTER the base set so toggles win. Empty dvars return early, so
    // this is effectively free when no overrides are set.
    self gf_applyPerkList( getDvar( "gf_perk_on"  ), true  );
    self gf_applyPerkList( getDvar( "gf_perk_off" ), false );

    // Humans only: gf_showWeaponHUD pushes ~21 setClientDvar (8 icons + 8 names + anchor/anim) to
    // build the menu-rendered loadout overview. A bot has no client, so pushing to it is pure waste
    // - and it fires for the whole bot fill in the round-start spawn wave, right at the transition.
    // Also suppressed during the pregame lobby hold: the overview would slide in on the frozen
    // prematch spawn then get yanked when the lobby cam moves the player to spectator (the "lobby HUD
    // flash"). The real match re-gives the loadout on the map_restart(false) spawn and shows it then.
    if ( !isBot
        && ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold )
        && getDvarInt( "gf_diag_cd_no_loadout_hud" ) != 1 )
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
gf_load( pri, sec, equip, lethal, tactical, camo, camoSec )
{
    load = [];

    p = gf_wdb( pri );
    load["primary"]         = p["w"];   load["primaryName"]     = p["n"];   load["primaryShader"]   = p["s"];

    s = gf_wdb( sec );
    load["secondary"]       = s["w"];   load["secondaryName"]   = s["n"];   load["secondaryShader"] = s["s"];

    e = gf_wdb( equip );
    load["equip"]           = e["w"];   load["equipName"]       = e["n"];   load["equipShader"]     = e["s"];

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
    // Special primaries reject a real camo — force stock so they don't error.
    if ( isSubStr( pri, "minigun" ) || isSubStr( pri, "m202" ) )
        load["camo"] = 0;

    return load;
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
    gf_regFamily( "defaultweapon", "Finger Gun", "menu_mp_weapons_knife" );   // real weapon (raw\weapons\sp\defaultweapon, precached in gf.gsc) -> engine's finger-gun easter egg
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
