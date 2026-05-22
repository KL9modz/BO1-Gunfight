#include maps\mp\_utility;
#include common_scripts\utility;

// Live HP readout centered on screen with a horizontal divider line.
gf_hud()
{
	self endon( "disconnect" );
	self endon( "death" );

	hp = newClientHudElem( self );
	hp.horzAlign         = "center";
	hp.vertAlign         = "middle";
	hp.alignX            = "center";
	hp.alignY            = "middle";
	hp.x                 = 0;
	hp.y                 = 0;
	hp.font              = "default";
	hp.fontScale         = 2;
	hp.color             = ( 1, 1, 1 );
	hp.alpha             = 1;
	hp.foreground        = true;
	hp.hidewhendead      = false;
	hp.hidewheninmenu    = false;
	hp.hidewheninkillcam = false;
	hp.archived          = false;

	dot = newClientHudElem( self );
	dot.horzAlign         = "center";
	dot.vertAlign         = "middle";
	dot.alignX            = "center";
	dot.alignY            = "middle";
	dot.x                 = 0;
	dot.y                 = -20;
	dot.color             = ( 1, 0.3, 0.3 );
	dot.alpha             = 0.9;
	dot.foreground        = true;
	dot.hidewhendead      = false;
	dot.hidewheninmenu    = false;
	dot.hidewheninkillcam = false;
	dot.archived          = false;
	dot setShader( "white", 40, 4 );

	for ( ;; )
	{
		wait 0.05;
		hp setText( "HP " + self.health );
	}
}

// Shows the 3 active perks on the right side of the HUD after spawn,
// styled after Sharpshooter's perk-unlock notification (icon + name,
// scaling pop-in, 5s display, fade out).
gf_displayPerks()
{
	self endon( "disconnect" );
	self endon( "death" );

	wait 1.5;

	iconSize    = 32;
	bigIconSize = 40;
	startY      = 280;
	spacing     = 40;

	perkNames    = [];
	perkNames[0] = "Lightweight";
	perkNames[1] = "Hardened";
	perkNames[2] = "Marathon";

	perkIcons    = [];
	perkIcons[0] = "specialty_marathon";
	perkIcons[1] = "specialty_hardened";
	perkIcons[2] = "specialty_lightweight";

	hudText = [];
	hudIcon = [];

	for ( i = 0; i < 3; i++ )
	{
		y = startY - spacing * i;

		hudText[i] = newClientHudElem( self );
		hudText[i].fontScale         = 1.5;
		hudText[i].x                 = -125;
		hudText[i].y                 = y;
		hudText[i].alignX            = "left";
		hudText[i].alignY            = "middle";
		hudText[i].horzAlign         = "user_right";
		hudText[i].vertAlign         = "user_top";
		hudText[i].color             = ( 1, 1, 1 );
		hudText[i].foreground        = true;
		hudText[i].hidewhendead      = false;
		hudText[i].hidewheninmenu    = true;
		hudText[i].hidewheninkillcam = true;
		hudText[i].archived          = false;
		hudText[i].alpha             = 0;
		hudText[i] setText( perkNames[i] );

		hudIcon[i] = newClientHudElem( self );
		hudIcon[i].x                 = -125 - 5 - bigIconSize;
		hudIcon[i].y                 = y - bigIconSize / 2;
		hudIcon[i].alignX            = "left";
		hudIcon[i].alignY            = "top";
		hudIcon[i].horzAlign         = "user_right";
		hudIcon[i].vertAlign         = "user_top";
		hudIcon[i].color             = ( 1, 1, 1 );
		hudIcon[i].foreground        = true;
		hudIcon[i].hidewhendead      = false;
		hudIcon[i].hidewheninmenu    = true;
		hudIcon[i].hidewheninkillcam = true;
		hudIcon[i].archived          = false;
		hudIcon[i].alpha             = 0;
		hudIcon[i] setShader( perkIcons[i], bigIconSize, bigIconSize );

		hudText[i] fadeOverTime( 0.5 );
		hudText[i].alpha = 1.0;
		hudIcon[i] fadeOverTime( 0.5 );
		hudIcon[i].alpha = 1.0;
		hudIcon[i] scaleOverTime( 0.5, iconSize, iconSize );
		hudIcon[i].x = -125 - 5 - iconSize;
		hudIcon[i].y = y - iconSize / 2;

		wait 0.5;
	}

	wait 4.0;

	for ( i = 0; i < 3; i++ )
	{
		hudText[i] fadeOverTime( 0.5 );
		hudText[i].alpha = 0;
		hudIcon[i] fadeOverTime( 0.5 );
		hudIcon[i].alpha = 0;
	}

	wait 0.5;

	for ( i = 0; i < 3; i++ )
	{
		hudText[i] destroy();
		hudIcon[i] destroy();
	}
}
