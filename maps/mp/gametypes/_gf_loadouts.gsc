// Gunfight v3 — Loadout System
// 54 fully pre-built loadouts, shuffled once per match and expanded into a
// round schedule. All players read the same game["roundsplayed"] index so
// loadout sync is guaranteed by construction.
//
// Slot balance (static order is gameplay-irrelevant — the pool is Fisher-Yates
// shuffled below). Primaries are kept in their original category order.
//   Lethal    : auto-balanced 18 Frag / 18 Semtex / 18 Tomahawk — assigned in
//               gf_initLoadouts (not per-row); Semtex = sticky_grenade_mp,
//               satchel_charge_mp is C4 and lives ONLY in the equipment slot
//   Tactical  : auto-balanced 11 Flash / 11 Stun / 11 Smoke / 11 Gas / 10 Decoy
//               — assigned in gf_initLoadouts (Gas = tabun_gas_mp,
//               Decoy = nightingale_mp; both work natively via stock _decoy)
//   Equipment : 14 Camera / 13 Jammer / 13 Motion / 7 Claymore / 7 C4
//   Secondary : pistols 6 each (Python/Makarov/M1911/CZ75), each with a
//               hardcoded, curated attachment (like the primaries); even mix of
//               launchers (Crossbow/RPG/China Lake/M72) and dual pistols
//   Minigun & M202 stay primaries (camo forced 0 — they reject a real camo);
//   true launchers appear only as secondaries.

#include maps\mp\gametypes\_gf_hud;

// ─── Public API ────────────────────────────────────────────────────────────

gf_initLoadouts()
{
    if ( isDefined( game["gf_init"] ) )
        return;

    pool = [];
    n    = 0;

    // ── AR ×8 ──
    pool[n] = gf_buildLoadout(
        gf_item( "famas_reflex_mp",            "FAMAS",          "menu_mp_weapons_famas" ),
        gf_item( "python_speed_mp",            "Python",         "menu_mp_weapons_python" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m16_acog_mp",                "M16",            "menu_mp_weapons_m16" ),
        gf_item( "makarov_silencer_mp",        "Makarov",        "menu_mp_weapons_makarov" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "aug_silencer_mp",            "AUG",            "menu_mp_weapons_aug" ),
        gf_item( "m1911_silencer_mp",          "M1911",          "menu_mp_weapons_colt" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_gl_mp",                "Galil",          "menu_mp_weapons_galil" ),
        gf_item( "cz75_silencer_mp",           "CZ75",           "menu_mp_weapons_cz75" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "commando_mp",                "Commando",       "menu_mp_weapons_commando" ),
        gf_item( "crossbow_explosive_mp",      "Crossbow",       "menu_mp_weapons_crossbow" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "fnfal_acog_mp",              "FN FAL",         "menu_mp_weapons_fnfal" ),
        gf_item( "rpg_mp",                     "RPG",            "menu_mp_weapons_rpg" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m14_acog_grip_mp",           "M14",            "menu_mp_weapons_m14" ),
        gf_item( "china_lake_mp",              "China Lake",     "menu_mp_weapons_china_lake" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_silencer_mp",          "Galil",          "menu_mp_weapons_galil" ),
        gf_item( "m72_law_mp",                 "M72 LAW",        "menu_mp_weapons_m72_law" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    // ── SMG ×6 ──
    pool[n] = gf_buildLoadout(
        gf_item( "mp5k_mp",                    "MP5K",           "menu_mp_weapons_mp5k" ),
        gf_item( "pythondw_mp",                "Dual Python",    "menu_mp_weapons_python" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak74u_silencer_mp",          "AK-74u",         "menu_mp_weapons_ak74u" ),
        gf_item( "cz75dw_mp",                  "Dual CZ75",      "menu_mp_weapons_cz75" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "mpl_rf_mp",                  "MPL",            "menu_mp_weapons_mpl" ),
        gf_item( "aspdw_mp",                   "Dual ASP",       "menu_mp_weapons_asp" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spectre_rf_mp",              "Spectre",        "menu_mp_weapons_spectre" ),
        gf_item( "makarovdw_mp",               "Dual Makarov",   "menu_mp_weapons_makarov" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "uzi_reflex_mp",              "Uzi",            "menu_mp_weapons_uzi" ),
        gf_item( "m1911dw_mp",                 "Dual M1911",     "menu_mp_weapons_colt" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "pm63_extclip_mp",            "PM63",           "menu_mp_weapons_pm63" ),
        gf_item( "knife_ballistic_mp",         "Ballistic Knife","menu_mp_weapons_ballistic_knife" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    // ── LMG ×4 ──
    pool[n] = gf_buildLoadout(
        gf_item( "hk21_extclip_mp",            "HK21",           "menu_mp_weapons_hk21" ),
        gf_item( "python_acog_mp",             "Python",         "menu_mp_weapons_python" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m60_reflex_mp",              "M60",            "menu_mp_weapons_m60" ),
        gf_item( "makarov_extclip_mp",         "Makarov",        "menu_mp_weapons_makarov" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "rpk_extclip_mp",             "RPK",            "menu_mp_weapons_rpk" ),
        gf_item( "m1911_extclip_mp",           "M1911",          "menu_mp_weapons_colt" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "stoner63_extclip_mp",        "Stoner63",       "menu_mp_weapons_stoner63a" ),
        gf_item( "cz75_auto_mp",               "CZ75",           "menu_mp_weapons_cz75" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    // ── Sniper ×2 ──
    pool[n] = gf_buildLoadout(
        gf_item( "l96a1_vzoom_mp",             "L96A1",          "menu_mp_weapons_l96a1" ),
        gf_item( "crossbow_explosive_mp",      "Crossbow",       "menu_mp_weapons_crossbow" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "wa2000_vzoom_mp",            "WA2000",         "menu_mp_weapons_wa2000" ),
        gf_item( "rpg_mp",                     "RPG",            "menu_mp_weapons_rpg" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    // ── Shotgun ×2 ──
    pool[n] = gf_buildLoadout(
        gf_item( "spas_mp",                    "SPAS-12",        "menu_mp_weapons_spas" ),
        gf_item( "china_lake_mp",              "China Lake",     "menu_mp_weapons_china_lake" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ithaca_grip_mp",             "Stakeout",       "menu_mp_weapons_ithaca" ),
        gf_item( "m72_law_mp",                 "M72 LAW",        "menu_mp_weapons_m72_law" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    // ── AR ×6 (expanded) ──
    pool[n] = gf_buildLoadout(
        gf_item( "ak47_acog_mp",               "AK-47",          "menu_mp_weapons_ak47" ),
        gf_item( "pythondw_mp",                "Dual Python",    "menu_mp_weapons_python" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak47_ft_mp",                 "AK-47",          "menu_mp_weapons_ak47" ),
        gf_item( "cz75dw_mp",                  "Dual CZ75",      "menu_mp_weapons_cz75" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "enfield_mp",                 "Enfield",        "menu_mp_weapons_enfield" ),
        gf_item( "aspdw_mp",                   "Dual ASP",       "menu_mp_weapons_asp" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "g11_lps_mp",                 "G11",            "menu_mp_weapons_g11" ),
        gf_item( "makarovdw_mp",               "Dual Makarov",   "menu_mp_weapons_makarov" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "commando_acog_mp",           "Commando",       "menu_mp_weapons_commando" ),
        gf_item( "m1911dw_mp",                 "Dual M1911",     "menu_mp_weapons_colt" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m16_reflex_mp",              "M16",            "menu_mp_weapons_m16" ),
        gf_item( "python_snub_mp",             "Python",         "menu_mp_weapons_python" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    // ── SMG ×4 (expanded) ──
    pool[n] = gf_buildLoadout(
        gf_item( "kiparis_grip_extclip_mp",    "Kiparis",        "menu_mp_weapons_kiparis" ),
        gf_item( "makarov_upgradesight_mp",    "Makarov",        "menu_mp_weapons_makarov" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m60_acog_mp",                "M60",            "menu_mp_weapons_m60" ),
        gf_item( "m1911_upgradesight_mp",      "M1911",          "menu_mp_weapons_colt" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "skorpion_rf_mp",             "Skorpion",       "menu_mp_weapons_skorpion" ),
        gf_item( "cz75_extclip_mp",            "CZ75",           "menu_mp_weapons_cz75" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak74u_acog_mp",              "AK-74u",         "menu_mp_weapons_ak74u" ),
        gf_item( "crossbow_explosive_mp",      "Crossbow",       "menu_mp_weapons_crossbow" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    // ── Sniper ×2 (expanded) ──
    pool[n] = gf_buildLoadout(
        gf_item( "psg1_vzoom_mp",              "PSG-1",          "menu_mp_weapons_psg1" ),
        gf_item( "rpg_mp",                     "RPG",            "menu_mp_weapons_rpg" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "dragunov_vzoom_mp",          "Dragunov",       "menu_mp_weapons_dragunov" ),
        gf_item( "china_lake_mp",              "China Lake",     "menu_mp_weapons_china_lake" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    // ── Shotgun ×1 (expanded) ──
    pool[n] = gf_buildLoadout(
        gf_item( "rottweil72_mp",              "Olympia",        "menu_mp_weapons_rottweil72" ),
        gf_item( "m72_law_mp",                 "M72 LAW",        "menu_mp_weapons_m72_law" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    // ── Dual-wield SMG ×5 ──
    pool[n] = gf_buildLoadout(
        gf_item( "kiparisdw_mp",               "Dual Kiparis",   "menu_mp_weapons_kiparis" ),
        gf_item( "pythondw_mp",                "Dual Python",    "menu_mp_weapons_python" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "mac11dw_mp",                 "Dual MAC-11",    "menu_mp_weapons_mac11" ),
        gf_item( "cz75dw_mp",                  "Dual CZ75",      "menu_mp_weapons_cz75" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "pm63dw_mp",                  "Dual PM63",      "menu_mp_weapons_pm63" ),
        gf_item( "aspdw_mp",                   "Dual ASP",       "menu_mp_weapons_asp" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "skorpiondw_mp",              "Dual Skorpion",  "menu_mp_weapons_skorpion" ),
        gf_item( "makarovdw_mp",               "Dual Makarov",   "menu_mp_weapons_makarov" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "hs10dw_mp",                  "Dual HS10",      "menu_mp_weapons_hs10" ),
        gf_item( "python_speed_mp",            "Python",         "menu_mp_weapons_python" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    // ── SMG/AR/Sniper (expanded ×5) ──
    pool[n] = gf_buildLoadout(
        gf_item( "mpl_rf_mp",                  "MPL",            "menu_mp_weapons_mpl" ),
        gf_item( "makarov_silencer_mp",        "Makarov",        "menu_mp_weapons_makarov" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "fnfal_acog_mp",              "FN FAL",         "menu_mp_weapons_fnfal" ),
        gf_item( "m1911_silencer_mp",          "M1911",          "menu_mp_weapons_colt" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spas_silencer_mp",           "SPAS-12",        "menu_mp_weapons_spas" ),
        gf_item( "cz75_upgradesight_mp",       "CZ75",           "menu_mp_weapons_cz75" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "psg1_silencer_mp",           "PSG-1",          "menu_mp_weapons_psg1" ),
        gf_item( "crossbow_explosive_mp",      "Crossbow",       "menu_mp_weapons_crossbow" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "kiparis_silencer_mp",        "Kiparis",        "menu_mp_weapons_kiparis" ),
        gf_item( "rpg_mp",                     "RPG",            "menu_mp_weapons_rpg" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    // ── Heavy & mixed ×9 — Minigun/M202 stay primary; launchers are secondaries ──
    pool[n] = gf_buildLoadout(
        gf_item( "m16_extclip_mp",             "M16",            "menu_mp_weapons_m16" ),
        gf_item( "china_lake_mp",              "China Lake",     "menu_mp_weapons_china_lake" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spas_mp",                    "SPAS-12",        "menu_mp_weapons_spas" ),
        gf_item( "python_acog_mp",             "Python",         "menu_mp_weapons_python" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak74u_grip_extclip_mp",      "AK-74u",         "menu_mp_weapons_ak74u" ),
        gf_item( "makarov_extclip_mp",         "Makarov",        "menu_mp_weapons_makarov" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_mp",                   "Galil",          "menu_mp_weapons_galil" ),
        gf_item( "m1911_extclip_mp",           "M1911",          "menu_mp_weapons_colt" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "stoner63_reflex_mp",         "Stoner63",       "menu_mp_weapons_stoner63a" ),
        gf_item( "cz75_auto_mp",               "CZ75",           "menu_mp_weapons_cz75" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m202_flash_wager_mp",        "Grim Reaper",    "hud_m202" ),
        gf_item( "python_snub_mp",             "Python",         "menu_mp_weapons_python" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) );
    pool[n]["camo"] = 0; n++;   // M202: launcher primary rejects camo — force stock

    pool[n] = gf_buildLoadout(
        gf_item( "minigun_wager_mp",           "Death Machine",  "menu_mp_weapons_minigun" ),
        gf_item( "knife_ballistic_mp",         "Ballistic Knife","menu_mp_weapons_ballistic_knife" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) );
    pool[n]["camo"] = 0; n++;   // Minigun: special primary rejects camo — force stock

    pool[n] = gf_buildLoadout(
        gf_item( "fnfal_mk_mp",                "FN FAL",         "menu_mp_weapons_fnfal" ),
        gf_item( "m1911_upgradesight_mp",      "M1911",          "menu_mp_weapons_colt" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "hk21_reflex_mp",             "HK21",           "menu_mp_weapons_hk21" ),
        gf_item( "cz75_silencer_mp",           "CZ75",           "menu_mp_weapons_cz75" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    // ── Even lethal + tactical distribution ──────────────────────────────────
    // Both offhand slots are assigned here, not per-loadout, so every match
    // spreads them as evenly as the pool size allows; the shuffle below
    // decorrelates them from weapon class. Built once per match (gf_init guard),
    // so all players read identical slots — sync holds by construction.
    //   Lethal   (3): 18 Frag / 18 Semtex / 18 Tomahawk
    //   Tactical (5): 11 Flash / 11 Stun / 11 Smoke / 11 Gas / 10 Decoy
    lethals = [];
    lethals[0] = gf_item( "frag_grenade_mp",   "Frag",     "hud_grenadeicon" );
    lethals[1] = gf_item( "sticky_grenade_mp", "Semtex",   "hud_icon_sticky_grenade" );
    lethals[2] = gf_item( "hatchet_mp",        "Tomahawk", "hud_hatchet" );

    tacticals = [];
    tacticals[0] = gf_item( "flash_grenade_mp",      "Flash", "hud_us_flashgrenade" );
    tacticals[1] = gf_item( "concussion_grenade_mp", "Stun",  "hud_us_stungrenade" );
    tacticals[2] = gf_item( "willy_pete_mp",         "Smoke", "hud_us_smokegrenade" );
    tacticals[3] = gf_item( "tabun_gas_mp",          "Gas",   "hud_icon_tabun_gasgrenade" );
    tacticals[4] = gf_item( "nightingale_mp",        "Decoy", "hud_nightingale" );

    for ( i = 0; i < pool.size; i++ )
    {
        l = lethals[ i % lethals.size ];
        pool[i]["lethal"]         = l["w"];
        pool[i]["lethalName"]     = l["n"];
        pool[i]["lethalShader"]   = l["s"];

        t = tacticals[ i % tacticals.size ];
        pool[i]["tactical"]       = t["w"];
        pool[i]["tacticalName"]   = t["n"];
        pool[i]["tacticalShader"] = t["s"];
    }

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
    level.gf_currentLoad = game["gf_pool"][ idx ];
}

gf_giveCustomLoadout()
{
    if ( !isDefined( level.gf_currentLoad ) )
        return;
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    load = level.gf_currentLoad;

    self maps\mp\gametypes\_wager::setupBlankRandomPlayer( true, true );

    camoOpts    = int( self CalcWeaponOptions( load["camo"],          0, 0, 0 ) );
    secCamoOpts = int( self CalcWeaponOptions( load["camoSecondary"], 0, 0, 0 ) );
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

// Lethal + tactical are NOT passed here — they're assigned in even rotation by
// the balancer in gf_initLoadouts so their match-wide counts stay balanced.
gf_buildLoadout( pri, sec, equip )
{
    load = [];
    load["primary"]         = pri["w"];   load["primaryName"]     = pri["n"];   load["primaryShader"]   = pri["s"];
    load["secondary"]       = sec["w"];   load["secondaryName"]   = sec["n"];   load["secondaryShader"] = sec["s"];
    load["equip"]           = equip["w"]; load["equipName"]       = equip["n"]; load["equipShader"]     = equip["s"];
    load["camo"]            = randomInt( 16 );   // primary camo
    load["camoSecondary"]   = randomInt( 16 );   // independent roll — only shows on real-base secondaries (e.g. crossbow); no-op on neutral-base pistols/launchers
    return load;
}

gf_item( w, n, s )
{
    it = [];
    it["w"] = w;
    it["n"] = n;
    it["s"] = s;
    return it;
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
