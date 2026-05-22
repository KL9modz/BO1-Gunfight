#include maps\mp\_utility;
#include common_scripts\utility;

// Defines every available shared loadout.
// All players receive the same randomly selected loadout for gf_rounds_per_loadout rounds.
gf_initLoadouts()
{
	level.gf_loadouts = [];
	n = 0;

	// ---- Assault Rifles ----
	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "FAMAS / Python";
	level.gf_loadouts[n]["primary"]       = "famas_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Galil / M1911";
	level.gf_loadouts[n]["primary"]       = "galil_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "m1911_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "M16 / Python";
	level.gf_loadouts[n]["primary"]       = "m16_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Enfield / Makarov";
	level.gf_loadouts[n]["primary"]       = "enfield_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "makarovdw_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "AUG / M1911";
	level.gf_loadouts[n]["primary"]       = "aug_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "m1911_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Commando / Python";
	level.gf_loadouts[n]["primary"]       = "commando_mp";
	level.gf_loadouts[n]["primary_atts"]  = "silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	// ---- Submachine Guns ----
	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "AK74u / M1911";
	level.gf_loadouts[n]["primary"]       = "ak74u_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "m1911_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "MP5K / Makarov";
	level.gf_loadouts[n]["primary"]       = "mp5k_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex silencer extclip rf";
	level.gf_loadouts[n]["second"]        = "makarovdw_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Spectre / Python";
	level.gf_loadouts[n]["primary"]       = "spectre_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Uzi / M1911";
	level.gf_loadouts[n]["primary"]       = "uzi_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex silencer extclip";
	level.gf_loadouts[n]["second"]        = "m1911_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	// ---- Snipers / Shotguns ----
	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "L96A1 / Python";
	level.gf_loadouts[n]["primary"]       = "l96a1_mp";
	level.gf_loadouts[n]["primary_atts"]  = "silencer extclip vzoom";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "SPAS / Makarov";
	level.gf_loadouts[n]["primary"]       = "spas_mp";
	level.gf_loadouts[n]["primary_atts"]  = "silencer";
	level.gf_loadouts[n]["second"]        = "makarovdw_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadoutCount   = n;
	level.gf_usedLoadouts   = [];
	level.gf_currentLoadout = undefined;
}

// Picks a random loadout from the unused pool, never repeating until all
// loadouts have been played, then resets. Current loadout is always excluded
// from the next pick so the same one never plays back-to-back.
gf_pickLoadout()
{
	if ( level.gf_loadoutCount <= 0 )
		return;

	if ( level.gf_loadoutCount == 1 )
	{
		level.gf_loadoutIdx     = 0;
		level.gf_currentLoadout = level.gf_loadouts[0];
		return;
	}

	pool = [];
	for ( i = 0; i < level.gf_loadoutCount; i++ )
	{
		if ( i == level.gf_loadoutIdx ) continue;
		if ( isDefined( level.gf_usedLoadouts[i] ) && level.gf_usedLoadouts[i] ) continue;
		pool[pool.size] = i;
	}

	if ( pool.size == 0 )
	{
		level.gf_usedLoadouts = [];
		for ( i = 0; i < level.gf_loadoutCount; i++ )
		{
			if ( i != level.gf_loadoutIdx )
				pool[pool.size] = i;
		}
		iprintln( "^3[Gunfight] All loadouts played -- reshuffling." );
	}

	newIdx = pool[ randomInt( pool.size ) ];
	level.gf_usedLoadouts[newIdx] = true;
	level.gf_loadoutIdx     = newIdx;
	level.gf_currentLoadout = level.gf_loadouts[newIdx];
}

// Precaches all weapon variants (base + each attachment combo) used by the loadout pool.
gf_precacheWeapons()
{
	for ( i = 0; i < level.gf_loadoutCount; i++ )
	{
		lo = level.gf_loadouts[i];
		precacheItem( lo["primary"]  );
		precacheItem( lo["second"]   );
		precacheItem( lo["lethal"]   );
		precacheItem( lo["tactical"] );

		if ( !isDefined( lo["primary_atts"] ) || lo["primary_atts"] == "" )
			continue;

		atts = strTok( lo["primary_atts"], " " );
		base = getSubStr( lo["primary"], 0, lo["primary"].size - 3 );
		for ( j = 0; j < atts.size; j++ )
			precacheItem( base + "_" + atts[j] + "_mp" );
	}
}

gf_announceLoadout()
{
	if ( !isDefined( level.gf_currentLoadout ) )
		return;
	iprintlnbold( "^3Loadout: ^7" + level.gf_currentLoadout["name"] );
}

// Gives the active shared loadout to self.
gf_giveLoadout()
{
	if ( !isDefined( level.gf_currentLoadout ) )
		return;

	lo = level.gf_currentLoadout;

	self takeAllWeapons();
	wait 0.05;

	primary = gf_addRandomAttachment( lo["primary"], lo["primary_atts"] );
	iprintln( "^3[GF] giving: ^7" + primary + " / " + lo["second"] );
	self giveWeapon( primary         );
	self giveWeapon( lo["second"]    );
	self giveWeapon( lo["lethal"]    );
	self giveWeapon( lo["tactical"]  );

	self switchToWeapon( primary );
	self giveMaxAmmo( primary        );
	self giveMaxAmmo( lo["second"]   );

	self SetPerk( "specialty_movefaster"       );
	self SetPerk( "specialty_bulletpenetration" );
	self SetPerk( "specialty_longersprint"     );

	self thread gf_displayPerks();
}

// Returns baseWeapon with a randomly chosen attachment appended, or the base
// weapon unchanged if attList is empty or the "no attachment" slot wins.
// Two empty slots are added so ~2/(N+2) of picks give no attachment.
gf_addRandomAttachment( baseWeapon, attList )
{
	if ( !isDefined( attList ) || attList == "" )
		return baseWeapon;

	atts = strTok( attList, " " );
	if ( atts.size <= 0 )
		return baseWeapon;

	atts[atts.size] = "";
	atts[atts.size] = "";

	att = atts[ randomInt( atts.size ) ];
	if ( att == "" )
		return baseWeapon;

	// Strip "_mp", insert attachment, re-add "_mp"
	// e.g. "famas_mp" + "reflex" -> "famas_reflex_mp"
	base = getSubStr( baseWeapon, 0, baseWeapon.size - 3 );
	return base + "_" + att + "_mp";
}
