init()
{
	precacheShader("damage_feedback");
	precacheShader("damage_feedback_j");
	level thread onPlayerConnect();
}
onPlayerConnect()
{
	for(;;)
	{
		level waittill("connecting", player);
		player.hud_damagefeedback = newClientHudElem(player);
		player.hud_damagefeedback.horzAlign = "center";
		player.hud_damagefeedback.vertAlign = "middle";
		player.hud_damagefeedback.x = -12;
		player.hud_damagefeedback.y = -12;
		player.hud_damagefeedback.alpha = 0;
		player.hud_damagefeedback.archived = true;
		player.hud_damagefeedback setShader("damage_feedback", 24, 48);
		player.hitSoundTracker = true;
	}
}
updateDamageFeedback( hitBodyArmor, mod )
{
	if ( !isPlayer( self ) )
		return;

	if ( hitBodyArmor )
	{

		self playlocalsound("mpl_hit_alert");
	}
	else
	{
		self.hud_damagefeedback setShader("damage_feedback", 24, 48);
		if ( isdefined( mod ) && mod != "MOD_CRUSH" && mod != "MOD_GRENADE_SPLASH" && mod != "MOD_HIT_BY_OBJECT" )
		{
			self thread playHitSound (mod);
		}
	}

	if ( isDefined( self.gf_markerColor ) && isDefined( self.gf_markerFrame ) && self.gf_markerFrame == gettime() )
	{
		self.hud_damagefeedback.color = self.gf_markerColor;
		self.gf_markerRedAt  = gettime();
		self.gf_markerSnapAt = gettime();
		self thread gf_markerSnap( self.gf_markerSnapAt, self.gf_markerColor );
	}
	else
	{
		self.hud_damagefeedback.color = ( 1, 1, 1 );
		self.gf_markerColor = undefined;
		self.gf_markerFrame = undefined;

		if ( isDefined( self.gf_markerRedAt ) && gettime() - self.gf_markerRedAt < 1200 )
		{
			self.gf_markerSnapAt = gettime();
			self thread gf_markerSnap( self.gf_markerSnapAt, ( 1, 1, 1 ) );
		}
		else
			self.gf_markerRedAt = undefined;
	}

	self.hud_damagefeedback.alpha = 1;
	self.hud_damagefeedback fadeOverTime(1);
	self.hud_damagefeedback.alpha = 0;
}
playHitSound (mod)
{
self endon ("disconnect");
	if (self.hitSoundTracker)
	{
		self.hitSoundTracker = false;
		self playlocalsound("mpl_hit_alert");

		wait .05;
		self.hitSoundTracker = true;
	}
}
updateSpecialDamageFeedback( hitEnt )
{
	if ( !isPlayer( self ) )
		return;

	if ( !isdefined(hitEnt) )
		return;

	if ( !isPlayer( hitEnt ) )
		return;
	wait (0.05);
	if ( !isdefined( self.directionalHitArray ) )
	{
		self.directionalHitArray = [];
		hitEntNum = hitEnt getEntityNumber();
		self.directionalHitArray[hitEntNum] = 1;
		self thread sendHitSpecialEventAtFrameEnd(hitEnt);
	}
	else
	{
		hitEntNum = hitEnt getEntityNumber();
		self.directionalHitArray[hitEntNum] = 1;
	}
}
sendHitSpecialEventAtFrameEnd(hitEnt)
{
	self endon ("disconnect");
	waittillframeend;
	enemysHit = 0;
	value = 1;

	entBitArray0 = 0;
	for ( i = 0; i < 32; i++ )
	{
		if (isdefined (self.directionalHitArray[i]) && self.directionalHitArray[i] != 0 )
		{
			entBitArray0 += value;
			enemysHit++;
		}
		value *= 2;
	}
	entBitArray1 = 0;
	for (  i = 33; i < 64; i++ )
	{
		if (isdefined (self.directionalHitArray[i]) && self.directionalHitArray[i] != 0 )
		{
			entBitArray1 += value;
			enemysHit++;
		}
		value *= 2;
	}

	if ( enemysHit )
	{
		self directionalHitIndicator( entBitArray0, entBitArray1 );
	}
	self.directionalHitArray = undefined;
	entBitArray0 = 0;
	entBitArray1 = 0;
}

gf_markerSnap( frame, col )
{
	self endon( "disconnect" );

	wait 0.05;
	if ( !isDefined( self.hud_damagefeedback ) || !isDefined( self.gf_markerSnapAt ) || self.gf_markerSnapAt != frame )
		return;
	self.hud_damagefeedback fadeOverTime( 0.05 );
	self.hud_damagefeedback.color = col;

	wait 0.05;
	if ( !isDefined( self.hud_damagefeedback ) || !isDefined( self.gf_markerSnapAt ) || self.gf_markerSnapAt != frame )
		return;
	self.hud_damagefeedback.alpha = 1;
	self.hud_damagefeedback fadeOverTime( 1 );
	self.hud_damagefeedback.alpha = 0;
}
