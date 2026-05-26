// Gunfight v2 — Loadout System
// 22 fully pre-built loadouts, shuffled once per match and expanded into a
// round schedule. All players read the same game["roundsplayed"] index so
// loadout sync is guaranteed by construction.

#include scripts\mp\_gf_hud;

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
        gf_item( "python_speed_mp",        "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m16_acog_mp",            "M16",      "menu_mp_weapons_m16"      ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_satchel_charge"       ),
        "concussion_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "aug_silencer_mp",        "AUG",      "menu_mp_weapons_aug"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        "smoke_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_grip_mp",          "Galil",    "menu_mp_weapons_galil"    ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "commando_reflex_mp",     "Commando", "menu_mp_weapons_commando" ),
        gf_item( "python_speed_mp",        "Python",   "menu_mp_weapons_python"   ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_satchel_charge"       ),
        "concussion_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "fnfal_acog_mp",          "FN FAL",   "menu_mp_weapons_fnfal"    ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m14_grip_mp",            "M14",      "menu_mp_weapons_m14"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "smoke_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "galil_silencer_mp",      "Galil",    "menu_mp_weapons_galil"    ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        "flash_grenade_mp" ); n++;

    // ── SMG ×6 ───────────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "mp5k_reflex_mp",         "MP5K",     "menu_mp_weapons_mp5k"     ),
        gf_item( "python_speed_mp",        "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ak74u_silencer_mp",      "AK74u",    "menu_mp_weapons_ak74u"    ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        "concussion_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "mp40_extclip_mp",        "MP40",     "menu_mp_weapons_mp40"     ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_satchel_charge"       ),
        "smoke_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spectre_rf_mp",          "Spectre",  "menu_mp_weapons_spectre"  ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "uzi_reflex_mp",          "Uzi",      "menu_mp_weapons_uzi"      ),
        gf_item( "python_speed_mp",        "Python",   "menu_mp_weapons_python"   ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_satchel_charge"       ),
        "concussion_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "pm63_silencer_mp",       "PM63",     "menu_mp_weapons_pm63"     ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        "smoke_grenade_mp" ); n++;

    // ── LMG ×4 ───────────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "hk21_grip_mp",           "HK21",     "menu_mp_weapons_hk21"     ),
        gf_item( "python_speed_mp",        "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "concussion_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "m60_reflex_mp",          "M60",      "menu_mp_weapons_m60"      ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_satchel_charge"       ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "rpk_extclip_mp",         "RPK",      "menu_mp_weapons_rpk"      ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        "smoke_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "stoner63_grip_mp",       "Stoner63", "menu_mp_weapons_stoner63a"),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "concussion_grenade_mp" ); n++;

    // ── Sniper ×2 ────────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "l96a1_vzoom_mp",         "L96A1",    "menu_mp_weapons_l96a1"    ),
        gf_item( "python_speed_mp",        "Python",   "menu_mp_weapons_python"   ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "wa2000_vzoom_mp",        "WA2000",   "menu_mp_weapons_wa2000"   ),
        gf_item( "makarov_upgradesight_mp","Makarov",  "menu_mp_weapons_makarov"  ),
        gf_item( "satchel_charge_mp",      "Semtex",   "hud_satchel_charge"       ),
        "concussion_grenade_mp" ); n++;

    // ── Shotgun ×2 ───────────────────────────────────────────────────
    pool[n] = gf_buildLoadout(
        gf_item( "spas_mp",                "SPAS-12",  "menu_mp_weapons_spas"     ),
        gf_item( "m1911_upgradesight_mp",  "M1911",    "menu_mp_weapons_colt"     ),
        gf_item( "hatchet_mp",             "Tomahawk", "hud_hatchet"              ),
        "flash_grenade_mp" ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ithaca_mp",              "Ithaca",   "menu_mp_weapons_ithaca"   ),
        gf_item( "cz75_upgradesight_mp",   "CZ75",     "menu_mp_weapons_cz75"     ),
        gf_item( "frag_grenade_mp",        "Frag",     "hud_grenadeicon"          ),
        "smoke_grenade_mp" ); n++;

    // Fisher-Yates shuffle — random order per match, no repeat within one cycle
    for ( i = pool.size - 1; i > 0; i-- )
    {
        j       = randomInt( i + 1 );
        temp    = pool[i];
        pool[i] = pool[j];
        pool[j] = temp;
    }

    // expand pool into a flat round schedule: each entry repeated roundsPerLoadout times
    schedule = [];
    j = 0;
    for ( i = 0; i < pool.size; i++ )
        for ( r = 0; r < level.gf_cfg_roundsPerLoadout; r++ )
        {
            schedule[j] = pool[i];
            j++;
        }

    // precache shaders (loop pool not schedule to avoid redundant calls)
    for ( i = 0; i < pool.size; i++ )
    {
        PreCacheShader( pool[i]["primaryShader"]   );
        PreCacheShader( pool[i]["secondaryShader"] );
        PreCacheShader( pool[i]["lethalShader"]    );
    }

    // perk shaders — names unverified in T5; blank icon if wrong, no crash
    PreCacheShader( "specialty_lightweight" );
    PreCacheShader( "specialty_hardened"    );
    PreCacheShader( "specialty_marathon"    );

    game["gf_pool"]     = pool;
    game["gf_schedule"] = schedule;
    game["gf_schedIdx"] = -1;
    game["gf_init"]     = 1;
}

gf_pickLoadout()
{
    if ( !isDefined( game["gf_schedule"] ) )
        return;

    game["gf_schedIdx"]  = ( game["gf_schedIdx"] + 1 ) % game["gf_schedule"].size;
    level.gf_currentLoad = game["gf_schedule"][ game["gf_schedIdx"] ];
}

gf_giveLoadout()
{
    if ( !isDefined( level.gf_currentLoad ) )
        return;

    load = level.gf_currentLoad;

    self takeAllWeapons();

    self GiveWeapon( load["primary"] );
    self GiveWeapon( load["secondary"] );
    self GiveWeapon( "knife_mp" );
    self switchToWeapon( load["primary"] );
    self giveMaxAmmo( load["primary"] );
    self giveMaxAmmo( load["secondary"] );
    self GiveWeapon( load["lethal"] );
    self GiveWeapon( load["tactical"] );

    self SetPerk( "specialty_movefaster"        );   // Lightweight
    self SetPerk( "specialty_bulletpenetration"  );   // Hardened
    self SetPerk( "specialty_longersprint"      );   // Marathon

    self thread gf_showLoadoutHUD( load );
    self thread gf_debugHealthHUD();
}

// ─── Helpers ───────────────────────────────────────────────────────────────

gf_buildLoadout( pri, sec, let, tac )
{
    load = [];
    load["primary"]         = pri["w"];   load["primaryName"]     = pri["n"];   load["primaryShader"]   = pri["s"];
    load["secondary"]       = sec["w"];   load["secondaryName"]   = sec["n"];   load["secondaryShader"] = sec["s"];
    load["lethal"]          = let["w"];   load["lethalName"]      = let["n"];   load["lethalShader"]    = let["s"];
    load["tactical"]        = tac;
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
