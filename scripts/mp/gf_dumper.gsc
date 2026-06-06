// Auto-loading entity scanner — works under any gametype when the mod is loaded.
//
// Usage for wager barrier research:
//   1. Set xblive_wagermatch 1 in gf.cfg (so barriers appear at map load)
//   2. Set gametype to gun (or any wager gametype)
//   3. loadMod mp_gunfight  →  map_restart
//   4. Once in-game: set gf_do_dump 2  → full entity census in ~ console
//
// set gf_debug_ents 1  must be set before the map loads to activate this script.

#include maps\mp\gametypes\_gf_debug;

init()
{
    if ( getDvarInt( "gf_debug_ents" ) != 1 )
        return;

    level thread gf_dumperLoop();
}

gf_dumperLoop()
{
    level endon( "game_ended" );

    wait 2;   // let map finish initializing
    PrintLn( "[gf_dumper] ready  set gf_do_dump 2=census  1=nearby(needs player)" );

    while ( true )
    {
        wait 0.5;

        mode = getDvarInt( "gf_do_dump" );
        if ( mode == 2 )
        {
            setDvar( "gf_do_dump", 0 );
            gf_censusEnts();
        }
    }
}
