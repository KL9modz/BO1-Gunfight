#include maps\mp\gametypes\_gf_hud;

gf_initLoadouts()
{
    if ( isDefined( game["gf_init"] ) )
        return;

    pool = [];
    n    = 0;

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

    pool[n] = gf_buildLoadout(
        gf_item( "l96a1_vzoom_mp",             "L96A1",          "menu_mp_weapons_l96a1" ),
        gf_item( "crossbow_explosive_mp",      "Crossbow",       "menu_mp_weapons_crossbow" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "wa2000_vzoom_mp",            "WA2000",         "menu_mp_weapons_wa2000" ),
        gf_item( "rpg_mp",                     "RPG",            "menu_mp_weapons_rpg" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "spas_mp",                    "SPAS-12",        "menu_mp_weapons_spas" ),
        gf_item( "china_lake_mp",              "China Lake",     "menu_mp_weapons_china_lake" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "ithaca_grip_mp",             "Stakeout",       "menu_mp_weapons_ithaca" ),
        gf_item( "m72_law_mp",                 "M72 LAW",        "menu_mp_weapons_m72_law" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) ); n++;

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

    pool[n] = gf_buildLoadout(
        gf_item( "psg1_vzoom_mp",              "PSG-1",          "menu_mp_weapons_psg1" ),
        gf_item( "rpg_mp",                     "RPG",            "menu_mp_weapons_rpg" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "dragunov_vzoom_mp",          "Dragunov",       "menu_mp_weapons_dragunov" ),
        gf_item( "china_lake_mp",              "China Lake",     "menu_mp_weapons_china_lake" ),
        gf_item( "claymore_mp",                "Claymore",       "hud_icon_claymore" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "rottweil72_mp",              "Olympia",        "menu_mp_weapons_rottweil72" ),
        gf_item( "m72_law_mp",                 "M72 LAW",        "menu_mp_weapons_m72_law" ),
        gf_item( "satchel_charge_mp",          "C4",             "hud_icon_satchelcharge" ) ); n++;

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
    pool[n]["camo"] = 0; n++;

    pool[n] = gf_buildLoadout(
        gf_item( "minigun_wager_mp",           "Death Machine",  "menu_mp_weapons_minigun" ),
        gf_item( "knife_ballistic_mp",         "Ballistic Knife","menu_mp_weapons_ballistic_knife" ),
        gf_item( "scrambler_mp",               "Jammer",         "hud_radar_jammer" ) );
    pool[n]["camo"] = 0; n++;

    pool[n] = gf_buildLoadout(
        gf_item( "fnfal_mk_mp",                "FN FAL",         "menu_mp_weapons_fnfal" ),
        gf_item( "m1911_upgradesight_mp",      "M1911",          "menu_mp_weapons_colt" ),
        gf_item( "acoustic_sensor_mp",         "Motion Sensor",  "hud_acoustic_sensor" ) ); n++;

    pool[n] = gf_buildLoadout(
        gf_item( "hk21_reflex_mp",             "HK21",           "menu_mp_weapons_hk21" ),
        gf_item( "cz75_silencer_mp",           "CZ75",           "menu_mp_weapons_cz75" ),
        gf_item( "camera_spike_mp",            "Camera Spike",   "hud_deployable_camera" ) ); n++;

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
    if ( !isBot )
    {
        self GiveWeapon( load["equip"] );
        self SetActionSlot( 1, "weapon", load["equip"] );
    }
    self EnableWeaponCycling();

    self SetPerk( "specialty_movefaster"        );
    self SetPerk( "specialty_fallheight"        );
    self SetPerk( "specialty_longersprint"      );
    self SetPerk( "specialty_armorvest"         );
    self SetPerk( "specialty_flakjacket"        );
    self SetPerk( "specialty_shades"            );
    self SetPerk( "specialty_stunprotection"    );

    self gf_applyPerkList( getDvar( "gf_perk_on"  ), true  );
    self gf_applyPerkList( getDvar( "gf_perk_off" ), false );

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

gf_buildLoadout( pri, sec, equip )
{
    load = [];
    load["primary"]         = pri["w"];   load["primaryName"]     = pri["n"];   load["primaryShader"]   = pri["s"];
    load["secondary"]       = sec["w"];   load["secondaryName"]   = sec["n"];   load["secondaryShader"] = sec["s"];
    load["equip"]           = equip["w"]; load["equipName"]       = equip["n"]; load["equipShader"]     = equip["s"];
    load["camo"]            = randomInt( 16 );
    load["camoSecondary"]   = randomInt( 16 );
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
