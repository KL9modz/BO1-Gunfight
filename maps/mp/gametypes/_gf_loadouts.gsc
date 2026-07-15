#include maps\mp\gametypes\_gf_hud;

gf_initLoadouts()
{
    if ( isDefined( game["gf_init"] ) )
        return;

    gf_buildWeaponDB();
    gf_buildPerkDB();

    pool = [];
    n    = 0;

    pool[n] = gf_load( "famas_dualclip_mp",         "spas_silencer_mp",        "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "m16_acog_mp",               "spas_mp",                 "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "aug_silencer_mp",           "mac11dw_mp",              "claymore_mp",         "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "galil_gl_mp",               "cz75_silencer_mp",        "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "commando_mp",               "crossbow_explosive_mp",   "satchel_charge_mp",   "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "fnfal_acog_mp",             "rpg_mp",                  "camera_spike_mp",     "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "m14_acog_grip_mp",          "china_lake_mp",           "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "galil_silencer_mp",         "m72_law_mp",              "claymore_mp",         "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;

    pool[n] = gf_load( "mp5k_silencer_mp",          "pythondw_mp",             "claymore_mp",         "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "dragunov_acog_mp",          "cz75dw_mp",               "satchel_charge_mp",   "hatchet_mp",        "nightingale_mp",         -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "mp5k_mp",                   "aspdw_mp",                "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "spectre_acog_grip_mp",      "hs10dw_mp",               "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "uzi_acog_grip_mp",          "ithaca_grip_mp",          "satchel_charge_mp",   "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "pm63_extclip_mp",           "knife_ballistic_mp",      "claymore_mp",         "hatchet_mp",        "nightingale_mp",         -1,  -1 ); n++;

    pool[n] = gf_load( "hk21_ir_mp",                "pm63_rf_mp",              "satchel_charge_mp",   "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "m60_acog_mp",               "python_speed_mp",         "camera_spike_mp",     "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "rpk_reflex_mp",             "m1911_extclip_mp",        "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "stoner63_extclip_mp",       "asp_mp",                  "acoustic_sensor_mp",  "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;

    pool[n] = gf_load( "l96a1_mp",                  "crossbow_explosive_mp",   "camera_spike_mp",     "hatchet_mp",        "concussion_grenade_mp",  -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "wa2000_vzoom_mp",           "m72_law_mp",              "satchel_charge_mp",   "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;

    pool[n] = gf_load( "spas_silencer_mp",          "china_lake_mp",           "claymore_mp",         "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "ithaca_grip_mp",            "aspdw_mp",                "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;

    pool[n] = gf_load( "ak47_dualclip_mp",          "pythondw_mp",             "acoustic_sensor_mp",  "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "ak47_ft_mp",                "cz75dw_mp",               "claymore_mp",         "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "enfield_mp",                "makarovdw_mp",            "satchel_charge_mp",   "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "g11_mp",                    "kiparisdw_mp",            "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "commando_acog_mp",          "hs10dw_mp",               "scrambler_mp",        "hatchet_mp",        "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "famas_mp",                  "python_snub_mp",          "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;

    pool[n] = gf_load( "m1911_extclip_mp",          "china_lake_mp",           "acoustic_sensor_mp",  "sticky_grenade_mp", "tabun_gas_mp",           -1,  -1 ); n++;
    pool[n] = gf_load( "m60_grip_mp",               "rottweil72_mp",           "claymore_mp",         "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "skorpion_extclip_mp",       "pm63dw_mp",               "camera_spike_mp",     "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "ak74u_acog_mp",             "knife_ballistic_mp",      "scrambler_mp",        "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;

    pool[n] = gf_load( "psg1_ir_mp",                "rpg_mp",                  "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "dragunov_extclip_mp",       "china_lake_mp",           "claymore_mp",         "frag_grenade_mp",   "tabun_gas_mp",           -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;

    pool[n] = gf_load( "rottweil72_mp",             "m72_law_mp",              "satchel_charge_mp",   "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;

    pool[n] = gf_load( "mac11_silencer_mp",         "m1911dw_mp",              "satchel_charge_mp",   "hatchet_mp",        "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "ithaca_grip_mp",            "pm63dw_mp",               "acoustic_sensor_mp",  "sticky_grenade_mp", "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "l96a1_mp",                  "rpg_mp",                  "camera_spike_mp",     "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "aug_elbit_mp",              "python_acog_mp",          "scrambler_mp",        "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;

    pool[n] = gf_load( "mpl_acog_grip_mp",          "makarov_silencer_mp",     "satchel_charge_mp",   "sticky_grenade_mp", "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "commando_mk_mp",            "m1911_silencer_mp",       "camera_spike_mp",     "hatchet_mp",        "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "wa2000_acog_mp",            "asp_mp",                  "scrambler_mp",        "frag_grenade_mp",   "willy_pete_mp",          -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "psg1_silencer_mp",          "crossbow_explosive_mp",   "acoustic_sensor_mp",  "sticky_grenade_mp", "tabun_gas_mp",           -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads,-specialty_armorvest" ); n++;
    pool[n] = gf_load( "kiparis_acog_grip_mp",      "rpg_mp",                  "claymore_mp",         "frag_grenade_mp",   "nightingale_mp",         -1,  -1 ); n++;

    pool[n] = gf_load( "m16_ir_mp",                 "hs10_mp",                 "scrambler_mp",        "frag_grenade_mp",   "flash_grenade_mp",       -1,  -1 ); n++;
    pool[n] = gf_load( "spas_mp",                   "python_acog_mp",          "acoustic_sensor_mp",  "sticky_grenade_mp", "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "ak74u_grip_dualclip_mp",    "makarov_extclip_mp",      "camera_spike_mp",     "hatchet_mp",        "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "galil_mp",                  "m1911_extclip_mp",        "scrambler_mp",        "frag_grenade_mp",   "concussion_grenade_mp",  -1,  -1 ); n++;
    pool[n] = gf_load( "stoner63_reflex_mp",        "cz75_auto_mp",            "acoustic_sensor_mp",  "sticky_grenade_mp", "nightingale_mp",         -1,  -1 ); n++;
    pool[n] = gf_load( "m202_flash_wager_mp",       "ithaca_grip_mp",          "camera_spike_mp",     "hatchet_mp",        "flash_grenade_mp",       -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads" ); n++;
    pool[n] = gf_load( "minigun_wager_mp",          "defaultweapon",           "claymore_mp",         "hatchet_mp",        "concussion_grenade_mp",  -1,  -1, "specialty_bulletpenetration,specialty_bulletflinch,specialty_bulletaccuracy,specialty_sprintrecovery,specialty_holdbreath,specialty_fastweaponswitch,specialty_fastreload,specialty_fastads" ); n++;
    pool[n] = gf_load( "fnfal_mk_mp",               "skorpiondw_mp",           "acoustic_sensor_mp",  "frag_grenade_mp",   "willy_pete_mp",          -1,  -1 ); n++;
    pool[n] = gf_load( "hk21_acog_mp",              "cz75_auto_mp",            "satchel_charge_mp",   "hatchet_mp",        "tabun_gas_mp",           -1,  -1 ); n++;

    for ( i = pool.size - 1; i > 0; i-- )
    {
        j       = randomInt( i + 1 );
        temp    = pool[i];
        pool[i] = pool[j];
        pool[j] = temp;
    }

    game["gf_pool"] = pool;
    game["gf_init"] = 1;

    level.gf_wpnDB  = undefined;
    level.gf_wpnFam = undefined;
    level.gf_perkDB = undefined;
}

gf_pickLoadout()
{
    if ( !isDefined( game["gf_pool"] ) )
        return;

    idx = int( game["roundsplayed"] / level.gf_cfg_roundsPerLoadout ) % game["gf_pool"].size;
    level.gf_currentLoad = game["gf_pool"][ idx ];
}

gf_giveCustomLoadout()
{
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
    camoOpts    = int( self CalcWeaponOptions( camoIdx,    0, 0, 0 ) );
    secCamoOpts = int( self CalcWeaponOptions( secCamoIdx, 0, 0, 0 ) );
    self DisableWeaponCycling();
    self GiveWeapon( load["primary"],   0, camoOpts );
    self GiveWeapon( load["secondary"], 0, secCamoOpts );
    self GiveWeapon( "knife_mp" );
    self switchToWeapon( load["primary"] );
    self gf_bumpReserveAmmo( load["primary"]   );
    self gf_bumpReserveAmmo( load["secondary"] );
    self GiveWeapon( load["lethal"] );
    lethalCount = 1;
    if ( load["lethal"] == "hatchet_mp" )
        lethalCount = 2;
    self setWeaponAmmoClip( load["lethal"], lethalCount );
    self SwitchToOffhand( load["lethal"] );
    self GiveWeapon( load["tactical"] );
    self setWeaponAmmoClip( load["tactical"], 1 );
    isBot = isDefined( self.pers["isBot"] ) && self.pers["isBot"];
    if ( !isBot && !gf_slotEmpty( load["equip"] ) )
    {
        self GiveWeapon( load["equip"] );
        self SetActionSlot( 1, "weapon", load["equip"] );
    }
    self EnableWeaponCycling();

    self SetPerk( "specialty_fallheight"        );
    self SetPerk( "specialty_longersprint"      );
    self SetPerk( "specialty_unlimitedsprint"   );
    self SetPerk( "specialty_armorvest"         );
    self SetPerk( "specialty_flakjacket"        );
    self SetPerk( "specialty_shades"            );
    self SetPerk( "specialty_stunprotection"    );
    self SetPerk( "specialty_loudenemies"       );
    self SetPerk( "specialty_fastmeleerecovery" );

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

    if ( !isBot && ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold ) )
        self thread gf_showWeaponHUD( load );
}

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

gf_bumpReserveAmmo( weapon )
{
    if ( !isDefined( weapon ) || weapon == "" )
        return;

    stock   = self GetWeaponAmmoStock( weapon );
    maxAmmo = WeaponMaxAmmo( weapon );
    ammo    = stock + weaponClipSize( weapon );
    if ( ammo > maxAmmo )
        ammo = maxAmmo;
    self SetWeaponAmmoStock( weapon, ammo );
}

gf_load( pri, sec, equip, lethal, tactical, camo, camoSec, perks )
{
    load = [];

    p = gf_wdb( pri );
    load["primary"]         = p["w"];   load["primaryName"]     = p["n"];   load["primaryShader"]   = p["s"];

    s = gf_wdb( sec );
    load["secondary"]       = s["w"];   load["secondaryName"]   = s["n"];   load["secondaryShader"] = s["s"];

    e = gf_wdb( equip );
    load["equip"]           = e["w"];   load["equipName"]       = e["n"];   load["equipShader"]     = e["s"];
    load["equipNone"]       = gf_slotEmpty( equip );

    l = gf_wdb( lethal );
    load["lethal"]          = l["w"];   load["lethalName"]      = l["n"];   load["lethalShader"]    = l["s"];

    t = gf_wdb( tactical );
    load["tactical"]        = t["w"];   load["tacticalName"]    = t["n"];   load["tacticalShader"]  = t["s"];

    if ( !isDefined( camoSec ) )
        camoSec = camo;
    if ( camo < 0 )
        load["camo"] = randomInt( 16 );
    else
        load["camo"] = camo;
    if ( camoSec < 0 )
        load["camoSecondary"] = randomInt( 16 );
    else
        load["camoSecondary"] = camoSec;
    if ( isSubStr( pri, "minigun" ) || isSubStr( pri, "m202" ) )
        load["camo"] = 0;
    if ( pri == "defaultweapon" )
        load["camo"] = 0;
    if ( sec == "defaultweapon" )
        load["camoSecondary"] = 0;

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

    load["perkShader0"] = gf_getPerkShader( "specialty_flakjacket" );        load["perkName0"] = "Flak Jacket";
    load["perkShader1"] = gf_getPerkShader( "specialty_bulletpenetration" ); load["perkName1"] = "Hardened";
    load["perkShader2"] = "perk_marathon_pro_256";                           load["perkName2"] = "Marathon Pro";

    return load;
}

gf_listHas( list, token )
{
    for ( i = 0; i < list.size; i++ )
    {
        if ( list[i] == token )
            return true;
    }
    return false;
}

gf_perkInfo( token )
{
    if ( isDefined( level.gf_perkDB ) && isDefined( level.gf_perkDB[ token ] ) )
        return level.gf_perkDB[ token ];

    info = [];
    info["n"] = token;
    info["p"] = token;
    return info;
}

gf_pReg( token, name, iconParent )
{
    info = [];
    info["n"] = name;
    info["p"] = iconParent;
    level.gf_perkDB[ token ] = info;
}

gf_buildPerkDB()
{
    level.gf_perkDB = [];

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

    gf_pReg( "specialty_armorvest",        "Body Armor",        "specialty_flakjacket" );
    gf_pReg( "specialty_bulletdamage",     "Stopping Power",    "specialty_bulletdamage" );
    gf_pReg( "specialty_rof",              "Double Tap",        "specialty_rof" );
    gf_pReg( "specialty_twoprimaries",     "Overkill",          "specialty_twoprimaries" );
    gf_pReg( "specialty_grenadepulldeath", "Martyrdom",         "specialty_grenadepulldeath" );
    gf_pReg( "specialty_explosivedamage",  "Explosive Damage",  "specialty_explosivedamage" );
}

gf_slotEmpty( token )
{
    return !isDefined( token ) || token == "" || token == "none";
}

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

gf_reg( token, name, shader )
{
    it = [];
    it["w"] = token;   it["n"] = name;   it["s"] = shader;
    level.gf_wpnDB[ token ] = it;
}

gf_regFamily( base, name, shader )
{
    it = [];
    it["n"] = name;   it["s"] = shader;
    level.gf_wpnFam[ base ] = it;
}

gf_buildWeaponDB()
{
    level.gf_wpnDB  = [];
    level.gf_wpnFam = [];

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
    gf_regFamily( "stoner63",   "Stoner63",   "menu_mp_weapons_stoner63a" );
    gf_regFamily( "spas",       "SPAS-12",    "menu_mp_weapons_spas" );
    gf_regFamily( "ithaca",     "Stakeout",   "menu_mp_weapons_ithaca" );
    gf_regFamily( "defaultweapon", "Finger Gun", "hud_death_suicide" );
    gf_regFamily( "rottweil72", "Olympia",    "menu_mp_weapons_rottweil72" );
    gf_regFamily( "l96a1",      "L96A1",      "menu_mp_weapons_l96a1" );
    gf_regFamily( "wa2000",     "WA2000",     "menu_mp_weapons_wa2000" );
    gf_regFamily( "psg1",       "PSG-1",      "menu_mp_weapons_psg1" );
    gf_regFamily( "dragunov",   "Dragunov",   "menu_mp_weapons_dragunov" );

    gf_regFamily( "python",     "Python",     "menu_mp_weapons_python" );
    gf_regFamily( "makarov",    "Makarov",    "menu_mp_weapons_makarov" );
    gf_regFamily( "cz75",       "CZ75",       "menu_mp_weapons_cz75" );
    gf_regFamily( "m1911",      "M1911",      "menu_mp_weapons_colt" );
    gf_regFamily( "asp",        "ASP",        "menu_mp_weapons_asp" );
    gf_regFamily( "crossbow",   "Crossbow",   "menu_mp_weapons_crossbow" );
    gf_regFamily( "china",      "China Lake", "menu_mp_weapons_china_lake" );
    gf_regFamily( "m72",        "M72 LAW",    "menu_mp_weapons_m72_law" );
    gf_regFamily( "rpg",        "RPG",        "menu_mp_weapons_rpg" );

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

    gf_reg( "knife_ballistic_mp", "Ballistic Knife", "menu_mp_weapons_ballistic_knife" );
    gf_reg( "m202_flash_wager_mp","Grim Reaper",     "hud_m202" );
    gf_reg( "minigun_wager_mp",   "Death Machine",   "menu_mp_weapons_minigun" );

    gf_reg( "none",               "None",          "white" );
    gf_reg( "camera_spike_mp",    "Camera Spike",  "hud_deployable_camera" );
    gf_reg( "scrambler_mp",       "Jammer",        "hud_radar_jammer" );
    gf_reg( "acoustic_sensor_mp", "Motion Sensor", "hud_acoustic_sensor" );
    gf_reg( "claymore_mp",        "Claymore",      "hud_icon_claymore" );
    gf_reg( "satchel_charge_mp",  "C4",            "hud_icon_satchelcharge" );

    gf_reg( "frag_grenade_mp",    "Frag",     "hud_grenadeicon" );
    gf_reg( "sticky_grenade_mp",  "Semtex",   "hud_icon_sticky_grenade" );
    gf_reg( "hatchet_mp",         "Tomahawk", "hud_hatchet" );

    gf_reg( "flash_grenade_mp",      "Flash", "hud_us_flashgrenade" );
    gf_reg( "concussion_grenade_mp", "Stun",  "hud_us_stungrenade" );
    gf_reg( "willy_pete_mp",         "Smoke", "hud_us_smokegrenade" );
    gf_reg( "tabun_gas_mp",          "Gas",   "hud_icon_tabun_gasgrenade" );
    gf_reg( "nightingale_mp",        "Decoy", "hud_nightingale" );
}
