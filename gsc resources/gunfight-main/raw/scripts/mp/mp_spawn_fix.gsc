#include maps\mp\_utility;
#include common_scripts\utility;

main()
{
	if ( GetDvarInt( "scr_disablePlutoniumFixes" ) )
	{
		return;
	}

	if ( isDedicated() )
	{
		replaceFunc( getFunction( "maps/mp/gametypes/_class", "getLoadoutItemFromDDLStats" ), ::getLoadoutItemFromDDLStats_hook, -1 );
	}
}

getLoadoutItemFromDDLStats_hook( customClassNum, loadoutSlot )
{
	func = getFunction( "maps/mp/gametypes/_class", "getLoadoutItemFromDDLStats" );
	disableDetourOnce( func );
	answer = self [[func]]( customClassNum, loadoutSlot );
	
	switch ( loadoutSlot )
	{
		case "primarygrenade":
			switch ( answer )
			{
				case 63: // frag
				case 64: // semtex
				case 65: // axe
					break;
					
				default:
					answer = 63;
					break;
			}
			
			break;
			
		case "specialty1":
			switch ( answer )
			{
				case 150: // light
				case 151: // light pro
				case 152: // scav
				case 153: // scav pro
				case 154: // ghost
				case 155: // ghost pro
				case 156: // flak
				case 157: // flak pro
				case 158: // hard
				case 159: // hard pro
					break;
					
				default:
					answer = 150;
					break;
			}
			
			break;
			
		case "specialty2":
			switch ( answer )
			{
				case 164: // hardened
				case 165: // hardened pro
				case 162: // scout
				case 163: // scout pro
				case 160: // steady
				case 161: // steady pro
				case 166: // slight
				case 167: // slight pro
				case 168: // war
				case 169: // war pro
					break;
					
				default:
					answer = 164;
					break;
			}
			
			break;
			
		case "specialty3":
			switch ( answer )
			{
				case 178: // tact
				case 179: // tact pro
				case 170: // mara
				case 171: // mara pro
				case 172: // ninja
				case 173: // ninja pro
				case 174: // second
				case 175: // second pro
				case 176: // hacker
				case 177: // hacker pro
					break;
					
				default:
					answer = 178;
					break;
			}
			
			break;
			
		case "specialgrenade":
			switch ( answer )
			{
				case 67: // smoke
				case 68: // gas
				case 69: // flash
				case 70: // con
				case 71: // decoy
					break;
					
				default:
					answer = 67;
					break;
			}
			
			break;
			
		case "equipment":
			switch ( answer )
			{
				case 77: // camera
				case 74: // c4
				case 76: // tact
				case 75: // jam
				case 78: // motion
				case 73: // clay
				case 0: // none
					break;
					
				default:
					answer = 0;
					break;
			}
			
			break;
			
		case "primary":
			switch ( answer )
			{
				case 12: // ak74u
				case 13: // kiparis
				case 14: // mac
				case 15: // mp5k
				case 16: // mpl
				case 17: // pm63
				case 18: // skorp
				case 19: // spectre
				case 20: // uzi
				case 26: // ak47
				case 27: // aug
				case 28: // commando
				case 29: // enfield
				case 30: // famas
				case 31: // fal
				case 32: // g11
				case 33: // galil
				case 34: // m14
				case 35: // m16
				case 37: // hk
				case 38: // m60
				case 39: // rpk
				case 40: // stoner
				case 42: // drag
				case 43: // l96
				case 44: // psg
				case 45: // wa
				case 47: // hs
				case 48: // stake
				case 49: // olyp
				case 50: // spas
					break;
					
				default:
					answer = 15;
					break;
			}
			
			break;
			
		case "secondary":
			switch ( answer )
			{
				case 1: // asp
				case 2: // cz
				case 3: // m1911
				case 4: // mak
				case 5: // python
				case 53: // law
				case 54: // rpg
				case 55: // strella
				case 57: // china
				case 56: // cross
				case 62: // knife
					break;
					
				default:
					answer = 1;
					break;
			}
			
			break;
			
		case "body":
			switch ( answer )
			{
				// case 97:
				case 98:
				case 99:
				case 100:
				case 101:
				case 102:
					break;
					
				default:
					answer = 98;
					break;
			}
			
			break;
			
		case "head":
			switch ( answer )
			{
				case 88:
				case 89:
				case 90:
				case 91:
				case 92:
				case 93:
				case 94:
				case 95:
				case 96:
				case 106:
				case 107:
				case 108:
				case 109:
				case 110:
				case 111:
				case 112:
				case 113:
				case 114:
				case 115:
				case 116:
				case 117:
				case 118:
				case 119:
				case 120:
				case 121:
				case 122:
				case 123:
				case 124:
				case 125:
				case 126:
				case 127:
				case 128:
				case 129:
				case 130:
					break;
					
				default:
					answer = 106;
					break;
			}
			
			break;
			
		case "classbonus":
			answer = 0;
			break;
	}
	
	return answer;
}

init()
{
	if ( GetDvarInt( "scr_disablePlutoniumFixes" ) )
	{
		return;
	}
	
	level thread on_player_connect();
}

on_player_connect()
{
	for ( ;; )
	{
		level waittill( "connected", player );
		player thread player_connected();
	}
}

player_connected()
{
	self endon( "disconnect" );
	
	if ( isDedicated() )
	{
		if ( !self istestclient() && !self isdemoclient() )
		{
			self thread fix_godmode_class_exploit();
		}
	}
}

fix_godmode_class_exploit()
{
	self endon( "disconnect" );
	
	this_class = "";
	
	for ( ;; )
	{
		wait 0.05;
		
		if ( !isDefined( self.class ) || !isdefined( self.cac_initialized ) || !self.cac_initialized )
		{
			continue;
		}
		
		if ( this_class == self.class )
		{
			continue;
		}
		
		this_class = self.class;
		
		needle = "CLASS_CUSTOM";
		
		if ( getsubstr( self.class, 0, needle.size ) != needle )
		{
			continue;
		}
		
		class_num = int( getsubstr( self.class, needle.size, self.class.size ) ) - 1;
		
		if ( !isDefined( level.cac_functions["set_body_model"][self.custom_class[class_num]["body"]] ) )
		{
			kick( self getentitynumber(), "PATCH_BAD_STATS" );
		}
		
		has_warlord = false;
		
		for ( i = 0; i < self.custom_class[class_num]["specialties"].size; i++ )
		{
			if ( self.custom_class[class_num]["specialties"][i].name == "specialty_twoattach" )
			{
				has_warlord = true;
				break;
			}
		}
		
		priattachments = [[ getFunction( "maps/mp/gametypes/_class", "listWeaponAttachments" ) ]]( self.custom_class[class_num]["primary"], self );
		secattachments = [[ getFunction( "maps/mp/gametypes/_class", "listWeaponAttachments" ) ]]( self.custom_class[class_num]["secondary"], self );
		
		// dw and rf+extclip do not have weapon files, so no need to check for that
		is_exclusive_attachment = false;
		
		for ( i = 0; i < priattachments.size; i++ )
		{
			if ( priattachments[i]["name"] == "gl" || priattachments[i]["name"] == "ft" || priattachments[i]["name"] == "mk" )
			{
				is_exclusive_attachment = true;
			}
		}
		
		if ( priattachments.size > 2 || secattachments.size > 1 || ( ( !has_warlord || is_exclusive_attachment ) && priattachments.size > 1 ) )
		{
			kick( self getentitynumber(), "PATCH_BAD_STATS" );
		}
	}
}
