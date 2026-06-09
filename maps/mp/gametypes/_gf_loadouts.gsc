// Gunfight v3 — Loadout System
// 22 fully pre-built loadouts, shuffled once per match and expanded into a
// round schedule. All players read the same game["roundsplayed"] index so
// loadout sync is guaranteed by construction.

#include maps\mp\gametypes\_gf_hud;

// ─── Public API ────────────────────────────────────────────────────────────

gf_initLoadouts()
{
    if ( isDefined( game["gf_init"] ) )
        return;

    pool = [];
    n    = 0;

    // ── AR ×8 ────────────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "famas_reflex_mp",        "FAMAS",    "menu_mp_weapons_famas"    ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m16_acog_mp",            "M16",      "menu_mp_weapons_m16"      ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "aug_silencer_mp",        "AUG",      "menu_mp_weapons_aug"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera") ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_extclip_mp",       "Galil",    "menu_mp_weapons_galil"    ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "commando_reflex_mp",     "Commando", "menu_mp_weapons_commando" ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "fnfal_acog_mp",          "FN FAL",   "menu_mp_weapons_fnfal"    ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m14_grip_mp",            "M14",      "menu_mp_weapons_m14"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_silencer_mp",      "Galil",    "menu_mp_weapons_galil"    ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera") ); n++;

    // ── SMG ×6 ───────────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "mp5k_reflex_mp",         "MP5K",     "menu_mp_weapons_mp5k"     ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak74u_silencer_mp",      "AK74u",    "menu_mp_weapons_ak74u"    ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "satchel_charge_mp",      "C4",       "hud_icon_satchelcharge"   ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "mpl_rf_mp",              "MPL",      "menu_mp_weapons_mpl"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spectre_rf_mp",          "Spectre",  "menu_mp_weapons_spectre"  ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "uzi_reflex_mp",          "Uzi",      "menu_mp_weapons_uzi"      ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera") ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "pm63_extclip_mp",        "PM63",     "menu_mp_weapons_pm63"     ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "satchel_charge_mp",      "C4",       "hud_icon_satchelcharge"   ) ); n++;

    // ── LMG ×4 ───────────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "hk21_extclip_mp",        "HK21",     "menu_mp_weapons_hk21"     ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m60_reflex_mp",          "M60",      "menu_mp_weapons_m60"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "rpk_extclip_mp",         "RPK",      "menu_mp_weapons_rpk"      ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "stoner63_extclip_mp",    "Stoner63", "menu_mp_weapons_stoner63a"),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera") ); n++;

    // ── Sniper ×2 ────────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "l96a1_vzoom_mp",         "L96A1",    "menu_mp_weapons_l96a1"    ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "satchel_charge_mp",      "C4",       "hud_icon_satchelcharge"   ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "wa2000_vzoom_mp",        "WA2000",   "menu_mp_weapons_wa2000"   ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    // ── Shotgun ×2 ───────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "spas_mp",                "SPAS-12",  "menu_mp_weapons_spas"     ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ithaca_grip_mp",         "Ithaca",   "menu_mp_weapons_ithaca"   ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor" ) ); n++;

    // ── AR ×6 (expanded) ─────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "ak47_acog_mp",           "AK-47",    "menu_mp_weapons_ak47"     ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera") ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak47_silencer_mp",       "AK-47",    "menu_mp_weapons_ak47"     ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "enfield_acog_mp",        "Enfield",  "menu_mp_weapons_enfield"  ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "g11_lps_mp",             "G11",      "menu_mp_weapons_g11"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "commando_acog_mp",       "Commando", "menu_mp_weapons_commando" ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera") ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m16_reflex_mp",          "M16",      "menu_mp_weapons_m16"      ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    // ── SMG ×4 (expanded) ────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "kiparis_reflex_mp",      "Kiparis",  "menu_mp_weapons_kiparis"  ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "mac11_reflex_mp",        "MAC-11",   "menu_mp_weapons_mac11"    ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "skorpion_rf_mp",         "Skorpion", "menu_mp_weapons_skorpion" ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "willy_pete_mp",          "Smoke",    "hud_us_smokegrenade"      ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera") ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak74u_acog_mp",          "AK74u",    "menu_mp_weapons_ak74u"    ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "satchel_charge_mp",      "C4",       "hud_icon_satchelcharge"   ) ); n++;

    // ── Sniper ×2 (expanded) ─────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "psg1_vzoom_mp",          "PSG-1",    "menu_mp_weapons_psg1"     ),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "dragunov_vzoom_mp",      "Dragunov", "menu_mp_weapons_dragunov" ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",     "hud_us_stungrenade"       ),
        gf_item( "claymore_mp",            "Claymore", "hud_icon_claymore"        ) ); n++;

    // ── Shotgun ×1 (expanded) ────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "rottweil72_mp",          "Rottweil", "menu_mp_weapons_rottweil72"),
        gf_item( "python_mp",              "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",    "hud_us_flashgrenade"      ),
        gf_item( "scrambler_mp",           "Jammer",   "hud_radar_jammer"       ) ); n++;

    // ── Dual-wield ×9 ────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "kiparisdw_mp",           "Dual Kiparis",  "menu_mp_weapons_kiparis"  ),
        gf_item( "python_mp",              "Python",        "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",          "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",         "hud_us_flashgrenade"      ),
        gf_item( "claymore_mp",            "Claymore",      "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "mac11dw_mp",             "Dual MAC-11",   "menu_mp_weapons_mac11"    ),
        gf_item( "m1911_upgradesight_mp",  "M1911",         "menu_mp_weapons_colt"     ),
        gf_item( "satchel_charge_mp",      "Semtex",        "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",          "hud_us_stungrenade"       ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor"      ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "pm63dw_mp",              "Dual PM63",     "menu_mp_weapons_pm63"     ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",          "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",          "hud_grenadeicon"          ),
        gf_item( "willy_pete_mp",          "Smoke",         "hud_us_smokegrenade"      ),
        gf_item( "camera_spike_mp",        "Camera Spike",  "hud_deployable_camera"    ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "skorpiondw_mp",          "Dual Skorpion", "menu_mp_weapons_skorpion" ),
        gf_item( "makarov_upgradesight_mp","Makarov",       "menu_mp_weapons_makarov"  ),
        gf_item( "hatchet_mp",             "Tomahawk",      "hud_hatchet"              ),
        gf_item( "flash_grenade_mp",       "Flash",         "hud_us_flashgrenade"      ),
        gf_item( "satchel_charge_mp",      "C4",            "hud_icon_satchelcharge"   ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "hs10dw_mp",              "Dual HS10",     "menu_mp_weapons_hs10"     ),
        gf_item( "python_mp",              "Python",        "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",          "hud_grenadeicon"          ),
        gf_item( "concussion_grenade_mp",  "Stun",          "hud_us_stungrenade"       ),
        gf_item( "scrambler_mp",           "Jammer",        "hud_radar_jammer"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "pythondw_mp",            "Dual Python",   "menu_mp_weapons_python"   ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",          "menu_mp_weapons_cz75"     ),
        gf_item( "satchel_charge_mp",      "Semtex",        "hud_icon_satchelcharge"   ),
        gf_item( "flash_grenade_mp",       "Flash",         "hud_us_flashgrenade"      ),
        gf_item( "claymore_mp",            "Claymore",      "hud_icon_claymore"        ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "cz75dw_mp",              "Dual CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "makarov_upgradesight_mp","Makarov",       "menu_mp_weapons_makarov"  ),
        gf_item( "sticky_grenade_mp",      "Sticky",        "hud_icon_sticky_grenade"  ),
        gf_item( "flash_grenade_mp",       "Flash",         "hud_us_flashgrenade"      ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor"      ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "aspdw_mp",               "Dual ASP",      "menu_mp_weapons_asp"      ),
        gf_item( "python_mp",              "Python",        "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",          "hud_grenadeicon"          ),
        gf_item( "flash_grenade_mp",       "Flash",         "hud_us_flashgrenade"      ),
        gf_item( "camera_spike_mp",        "Camera Spike",  "hud_deployable_camera"    ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m1911dw_mp",             "Dual M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "makarov_upgradesight_mp","Makarov",       "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",        "hud_icon_satchelcharge"   ),
        gf_item( "concussion_grenade_mp",  "Stun",          "hud_us_stungrenade"       ),
        gf_item( "camera_spike_mp",        "Camera Spike",  "hud_deployable_camera"    ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "makarovdw_mp",           "Dual Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",          "menu_mp_weapons_cz75"     ),
        gf_item( "hatchet_mp",             "Tomahawk",      "hud_hatchet"              ),
        gf_item( "willy_pete_mp",          "Smoke",         "hud_us_smokegrenade"      ),
        gf_item( "scrambler_mp",           "Jammer",        "hud_radar_jammer"       ) ); n++;

    // ── Launcher / Special ×8 — launcher/special is always the secondary ────
    pool[n] = gf_buildLoadout(
        gf_item( "m16_extclip_mp",         "M16",         "menu_mp_weapons_m16"         ),
        gf_item( "china_lake_mp",          "China Lake",  "menu_mp_weapons_china_lake"  ),
        gf_item( "frag_grenade_mp",        "Frag",        "hud_grenadeicon"             ),
        gf_item( "flash_grenade_mp",       "Flash",       "hud_us_flashgrenade"         ),
        gf_item( "claymore_mp",            "Claymore",    "hud_icon_claymore"           ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spas_mp",                "SPAS-12",     "menu_mp_weapons_spas"        ),
        gf_item( "m72_law_mp",             "M72 LAW",     "menu_mp_weapons_m72_law"     ),
        gf_item( "satchel_charge_mp",      "Semtex",      "hud_icon_satchelcharge"      ),
        gf_item( "concussion_grenade_mp",  "Stun",        "hud_us_stungrenade"          ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak74u_grip_mp",          "AK-74u",      "menu_mp_weapons_ak74u"       ),
        gf_item( "crossbow_explosive_mp",  "Crossbow",    "menu_mp_weapons_crossbow"    ),
        gf_item( "frag_grenade_mp",        "Frag",        "hud_grenadeicon"             ),
        gf_item( "flash_grenade_mp",       "Flash",       "hud_us_flashgrenade"         ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera"      ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_mp",               "Galil",       "menu_mp_weapons_galil"       ),
        gf_item( "crossbow_explosive_mp",  "Crossbow",    "menu_mp_weapons_crossbow"    ),
        gf_item( "sticky_grenade_mp",      "Sticky",      "hud_icon_sticky_grenade"     ),
        gf_item( "flash_grenade_mp",       "Flash",       "hud_us_flashgrenade"         ),
        gf_item( "satchel_charge_mp",      "C4",          "hud_icon_satchelcharge"      ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spectre_mp",             "Spectre",     "menu_mp_weapons_spectre"     ),
        gf_item( "rpg_mp",                 "RPG-7",       "menu_mp_weapons_rpg"         ),
        gf_item( "frag_grenade_mp",        "Frag",        "hud_grenadeicon"             ),
        gf_item( "willy_pete_mp",          "Smoke",       "hud_us_smokegrenade"         ),
        gf_item( "scrambler_mp",           "Jammer",      "hud_radar_jammer"            ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "aug_acog_mp",            "AUG ACOG",    "menu_mp_weapons_aug"         ),
        gf_item( "m202_flash_mp",          "M202 FLASH",  "hud_m202"                    ),
        gf_item( "sticky_grenade_mp",      "Sticky",      "hud_icon_sticky_grenade"     ),
        gf_item( "concussion_grenade_mp",  "Stun",        "hud_us_stungrenade"          ),
        gf_item( "claymore_mp",            "Claymore",    "hud_icon_claymore"           ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "fnfal_extclip_mp",       "FN FAL",      "menu_mp_weapons_fnfal"       ),
        gf_item( "strela_mp",              "Strela",      "menu_mp_weapons_strela"      ),
        gf_item( "frag_grenade_mp",        "Frag",        "hud_grenadeicon"             ),
        gf_item( "flash_grenade_mp",       "Flash",       "hud_us_flashgrenade"         ),
        gf_item( "acoustic_sensor_mp",     "Motion Sensor", "hud_acoustic_sensor"       ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "mac11_rf_mp",            "MAC-11",      "menu_mp_weapons_mac11"       ),
        gf_item( "knife_ballistic_mp",     "Ballistic Knife","menu_mp_weapons_ballistic_knife"),
        gf_item( "hatchet_mp",             "Tomahawk",    "hud_hatchet"                 ),
        gf_item( "flash_grenade_mp",       "Flash",       "hud_us_flashgrenade"         ),
        gf_item( "camera_spike_mp",        "Camera Spike", "hud_deployable_camera"      ) ); n++;

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

    camoOpts = int( self CalcWeaponOptions( load["camo"], 0, 0, 0 ) );
    self DisableWeaponCycling();
    self GiveWeapon( load["primary"],   0, camoOpts );
    self GiveWeapon( load["secondary"] );   // no camo — launchers/pistols reject non-zero camoOpts
    self GiveWeapon( "knife_mp" );
    self switchToWeapon( load["primary"] );
    self giveMaxAmmo( load["primary"] );
    self giveMaxAmmo( load["secondary"] );
    self GiveWeapon( load["lethal"] );
    self giveMaxAmmo( load["lethal"] );
    self SwitchToOffhand( load["lethal"] );
    self GiveWeapon( load["tactical"] );
    self giveMaxAmmo( load["tactical"] );
    self GiveWeapon( load["equip"] );
    self SetActionSlot( 1, "weapon", load["equip"] );
    self EnableWeaponCycling();

    self SetPerk( "specialty_movefaster"        );   // Lightweight
    self SetPerk( "specialty_fallheight"        );   // Lightweight Pro — no fall damage
    self SetPerk( "specialty_bulletpenetration" );   // Deep Impact
    self SetPerk( "specialty_bulletdamage"      );   // Deep Impact Pro — extra penetration damage
    self SetPerk( "specialty_longersprint"      );   // Marathon (no pro specialty exists in T5 source)
    self SetPerk( "specialty_armorvest"         );   // Flak Jacket
    self SetPerk( "specialty_flakjacket"        );   // Flak Jacket Pro — throwback grenades
    self SetPerk( "specialty_fireproof"         );   // Flak Jacket Pro — fire immunity

    self thread gf_showWeaponHUD( load );
}

// ─── Helpers ───────────────────────────────────────────────────────────────

gf_buildLoadout( pri, sec, let, tac, equip )
{
    load = [];
    load["primary"]         = pri["w"];   load["primaryName"]     = pri["n"];   load["primaryShader"]   = pri["s"];
    load["secondary"]       = sec["w"];   load["secondaryName"]   = sec["n"];   load["secondaryShader"] = sec["s"];
    load["lethal"]          = let["w"];   load["lethalName"]      = let["n"];   load["lethalShader"]    = let["s"];
    load["tactical"]        = tac["w"];   load["tacticalName"]    = tac["n"];   load["tacticalShader"]  = tac["s"];
    load["equip"]           = equip["w"]; load["equipName"]       = equip["n"]; load["equipShader"]     = equip["s"];
    load["camo"]            = randomInt( 16 );
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
//                crossbow_mp (use crossbow_explosive_mp), minigun_wager_mp (not giveable)
//                menu_mp_weapons_m202_flash (no such material; use hud_m202)
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
//   rpg_mp  strela_mp
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
