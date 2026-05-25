// Gunfight v2 — Loadout System
// 22-entry pool (AR×7, SMG×6, LMG×4, Sniper×2, Shotgun×2)
// Persisted in game[] so it survives SD round cycling

#include scripts\mp\_gf_hud;

// ─── Public API ────────────────────────────────────────────────────────────

gf_initLoadouts()
{
    if ( isDefined( game["gf_init"] ) )
        return;

    // perk sets per class (no #define in T5)
    arPerks      = [];
    arPerks[0]   = "specialty_fastreload";
    arPerks[1]   = "specialty_bulletaccuracy";
    arPerks[2]   = "specialty_gpsjammer";

    smgPerks     = [];
    smgPerks[0]  = "specialty_movefaster";
    smgPerks[1]  = "specialty_fastreload";
    smgPerks[2]  = "specialty_quieter";

    lmgPerks     = [];
    lmgPerks[0]  = "specialty_bulletpenetration";
    lmgPerks[1]  = "specialty_fastreload";
    lmgPerks[2]  = "specialty_armorvest";

    snpPerks     = [];
    snpPerks[0]  = "specialty_holdbreath";
    snpPerks[1]  = "specialty_gpsjammer";
    snpPerks[2]  = "specialty_quieter";

    sgPerks      = [];
    sgPerks[0]   = "specialty_movefaster";
    sgPerks[1]   = "specialty_fastreload";
    sgPerks[2]   = "specialty_armorvest";

    // AR attachments
    arAtts       = [];
    arAtts[0]    = "reflex";
    arAtts[1]    = "acog";
    arAtts[2]    = "silencer";
    arAtts[3]    = "grip";

    // SMG attachments
    smgAtts      = [];
    smgAtts[0]   = "reflex";
    smgAtts[1]   = "silencer";
    smgAtts[2]   = "extclip";
    smgAtts[3]   = "rf";

    // LMG attachments
    lmgAtts      = [];
    lmgAtts[0]   = "grip";
    lmgAtts[1]   = "reflex";
    lmgAtts[2]   = "extclip";

    // Sniper attachments
    snpAtts      = [];
    snpAtts[0]   = "vzoom";

    pool = [];
    n    = 0;

    // ── AR ×7 ────────────────────────────────────────────────────────
    pool[n] = gf_buildSlot( "famas_mp",    "FAMAS",    "menu_mp_weapons_famas",    arAtts, arPerks ); n++;
    pool[n] = gf_buildSlot( "m16_mp",      "M16",      "menu_mp_weapons_m16",      arAtts, arPerks ); n++;
    pool[n] = gf_buildSlot( "aug_mp",      "AUG",      "menu_mp_weapons_aug",      arAtts, arPerks ); n++;
    pool[n] = gf_buildSlot( "galil_mp",    "Galil",    "menu_mp_weapons_galil",    arAtts, arPerks ); n++;
    pool[n] = gf_buildSlot( "commando_mp", "Commando", "menu_mp_weapons_commando", arAtts, arPerks ); n++;
    pool[n] = gf_buildSlot( "fnfal_mp",    "FN FAL",   "menu_mp_weapons_fnfal",    arAtts, arPerks ); n++;
    pool[n] = gf_buildSlot( "m14_mp",      "M14",      "menu_mp_weapons_m14",      arAtts, arPerks ); n++;

    // ── SMG ×6 ───────────────────────────────────────────────────────
    pool[n] = gf_buildSlot( "mp5k_mp",    "MP5K",    "menu_mp_weapons_mp5k",    smgAtts, smgPerks ); n++;
    pool[n] = gf_buildSlot( "ak74u_mp",   "AK74u",   "menu_mp_weapons_ak74u",   smgAtts, smgPerks ); n++;
    pool[n] = gf_buildSlot( "mp40_mp",    "MP40",    "menu_mp_weapons_mp40",    smgAtts, smgPerks ); n++;
    pool[n] = gf_buildSlot( "spectre_mp", "Spectre", "menu_mp_weapons_spectre", smgAtts, smgPerks ); n++;
    pool[n] = gf_buildSlot( "uzi_mp",     "Uzi",     "menu_mp_weapons_uzi",     smgAtts, smgPerks ); n++;
    pool[n] = gf_buildSlot( "pm63_mp",    "PM63",    "menu_mp_weapons_pm63",    smgAtts, smgPerks ); n++;

    // ── LMG ×4 ───────────────────────────────────────────────────────
    pool[n] = gf_buildSlot( "hk21_mp",    "HK21",    "menu_mp_weapons_hk21",    lmgAtts, lmgPerks ); n++;
    pool[n] = gf_buildSlot( "m60_mp",     "M60",     "menu_mp_weapons_m60",     lmgAtts, lmgPerks ); n++;
    pool[n] = gf_buildSlot( "rpk_mp",     "RPK",     "menu_mp_weapons_rpk",     lmgAtts, lmgPerks ); n++;
    pool[n] = gf_buildSlot( "stoner63_mp","Stoner63","menu_mp_weapons_stoner63a",lmgAtts,lmgPerks ); n++;

    // ── Sniper ×2 ────────────────────────────────────────────────────
    pool[n] = gf_buildSlot( "l96a1_mp",  "L96A1",  "menu_mp_weapons_l96a1",  snpAtts, snpPerks ); n++;
    pool[n] = gf_buildSlot( "wa2000_mp", "WA2000", "menu_mp_weapons_wa2000", snpAtts, snpPerks ); n++;

    // ── Shotgun ×2 ───────────────────────────────────────────────────
    noAtts = [];
    pool[n] = gf_buildSlot( "spas_mp",   "SPAS-12", "menu_mp_weapons_spas",        noAtts, sgPerks ); n++;
    pool[n] = gf_buildSlot( "ithaca_mp", "Ithaca",  "menu_mp_weapons_ithaca",       noAtts, sgPerks ); n++;

    // Fisher-Yates shuffle
    for ( i = pool.size - 1; i > 0; i-- )
    {
        j       = randomInt( i + 1 );
        temp    = pool[i];
        pool[i] = pool[j];
        pool[j] = temp;
    }

    // precache all primary shaders
    for ( i = 0; i < pool.size; i++ )
        PreCacheShader( pool[i]["primaryShader"] );

    // precache secondary shaders
    PreCacheShader( "menu_mp_weapons_python" );
    PreCacheShader( "menu_mp_weapons_colt" );
    PreCacheShader( "menu_mp_weapons_makarov" );
    PreCacheShader( "menu_mp_weapons_cz75" );

    // precache lethal shaders
    PreCacheShader( "hud_grenadeicon" );
    PreCacheShader( "hud_satchel_charge" );
    PreCacheShader( "hud_hatchet" );

    game["gf_pool"] = pool;
    game["gf_idx"]  = -1;
    game["gf_init"] = 1;
}

gf_pickLoadout()
{
    if ( !isDefined( game["gf_pool"] ) )
        return;

    idx = int( game["roundsplayed"] / level.gf_cfg_roundsPerLoadout ) % game["gf_pool"].size;

    if ( idx == game["gf_idx"] && isDefined( level.gf_currentLoad ) )
        return;

    game["gf_idx"] = idx;
    slot = game["gf_pool"][idx];

    // random lethal
    lethals         = [];
    lethals[0]      = [];
    lethals[0]["w"] = "frag_grenade_mp";
    lethals[0]["s"] = "hud_grenadeicon";
    lethals[0]["n"] = "Frag";
    lethals[1]      = [];
    lethals[1]["w"] = "satchel_charge_mp";
    lethals[1]["s"] = "hud_satchel_charge";
    lethals[1]["n"] = "Semtex";
    lethals[2]      = [];
    lethals[2]["w"] = "hatchet_mp";
    lethals[2]["s"] = "hud_hatchet";
    lethals[2]["n"] = "Tomahawk";
    lethal = lethals[ randomInt( lethals.size ) ];

    // random tactical
    tacticals    = [];
    tacticals[0] = "flash_grenade_mp";
    tacticals[1] = "concussion_grenade_mp";
    tacticals[2] = "smoke_grenade_mp";
    tactical = tacticals[ randomInt( tacticals.size ) ];

    // random secondary
    secondaries      = [];
    secondaries[0]   = [];
    secondaries[0]["w"] = "python_speed_mp";
    secondaries[0]["s"] = "menu_mp_weapons_python";
    secondaries[0]["n"] = "Python";
    secondaries[1]   = [];
    secondaries[1]["w"] = "m1911_upgradesight_mp";
    secondaries[1]["s"] = "menu_mp_weapons_colt";
    secondaries[1]["n"] = "M1911";
    secondaries[2]   = [];
    secondaries[2]["w"] = "makarov_upgradesight_mp";
    secondaries[2]["s"] = "menu_mp_weapons_makarov";
    secondaries[2]["n"] = "Makarov";
    secondaries[3]   = [];
    secondaries[3]["w"] = "cz75_upgradesight_mp";
    secondaries[3]["s"] = "menu_mp_weapons_cz75";
    secondaries[3]["n"] = "CZ75";
    sec = secondaries[ randomInt( secondaries.size ) ];

    load = [];
    load["primary"]         = gf_addRandomAttachment( slot["primaryBase"], slot["primaryAtts"] );
    load["primaryShader"]   = slot["primaryShader"];
    load["primaryName"]     = slot["primaryName"];
    load["secondary"]       = sec["w"];
    load["secondaryShader"] = sec["s"];
    load["secondaryName"]   = sec["n"];
    load["lethal"]          = lethal["w"];
    load["lethalShader"]    = lethal["s"];
    load["lethalName"]      = lethal["n"];
    load["tactical"]        = tactical;
    load["perks"]           = slot["perks"];

    level.gf_currentLoad = load;
}

gf_giveLoadout()
{
    // self = player; called from level.onGiveLoadout after engine gives class weapons
    if ( !isDefined( level.gf_currentLoad ) )
        return;

    load = level.gf_currentLoad;

    self takeAllWeapons();
    self clearperks();

    self GiveWeapon( load["primary"] );
    self GiveWeapon( load["secondary"] );
    self GiveWeapon( "knife_mp" );
    self switchToWeapon( load["primary"] );
    self giveMaxAmmo( load["primary"] );
    self giveMaxAmmo( load["secondary"] );
    self GiveOffhandWeapon( load["lethal"] );
    self GiveOffhandWeapon( load["tactical"] );

    perks = load["perks"];
    for ( i = 0; i < perks.size; i++ )
        self SetPerk( perks[i] );

    self thread gf_showLoadoutHUD();
}

// ─── Helpers ───────────────────────────────────────────────────────────────

gf_buildSlot( base, name, shader, atts, perks )
{
    s = [];
    s["primaryBase"]   = base;
    s["primaryName"]   = name;
    s["primaryShader"] = shader;
    s["primaryAtts"]   = atts;
    s["perks"]         = perks;
    return s;
}

gf_addRandomAttachment( base, atts )
{
    // 2 empty slots give ~33% no-attachment chance
    total = atts.size + 2;
    roll  = randomInt( total );

    if ( roll >= atts.size )
        return base;

    att  = atts[roll];
    stem = getSubStr( base, 0, base.size - 3 );   // strips "_mp"
    return stem + "_" + att + "_mp";
}
