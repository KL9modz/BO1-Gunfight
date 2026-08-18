// gf_ticker.inc -- the gunfight.us ticker bar, ONE definition, included by every menu that shows it.
//
// Included by: ui_mp/main.menu (main menu) and ui_mp/scriptmenus/class.menu (pause screen).
// Both are forks of stock menus; the ticker is the part they genuinely share, and it used to be a
// verbatim ~55-line copy in each under a comment contract to keep them identical BY HAND. A copy
// change (the Discord invite, the domain, a timing tweak) then had to be made twice and needed a
// mod.ff rebuild to even see, so a miss shipped two different addresses on two screens.
// Stock solves the same problem the same way -- ui/scroller.inc is pulled into 13 menus.
//
// WHAT STAYS IN THE INCLUDING MENU: the TK_LINE() calls. That is deliberate -- the copy and its
// colour codes are the one thing the two surfaces are allowed to differ on.
//
// ⚠ BUILD: this file must be STAGED into the game's raw\ for the link, exactly like
// hud_gf_health.menu, because the linker's preprocessor resolves #include from raw\ -- it is NOT a
// mod.csv asset (nothing registers an .inc; it is textual). tools\build_ff.ps1 stages it by name.
// ⚠ NEVER give it a mod.csv menufile row: registering a menu twice kills the entire menu system
// and every gametype vanishes from the UI ([[build-stage-transitive-menu]]).
//
// ⚠ milliseconds() here is the CLIENT's UI-realtime clock, not server time -- which is exactly why
// this animates for free with no server push and no reliable commands
// ([[menu-milliseconds-client-local-no-per-round-event]]).

// Stock geometry. GF_TICKER_X carries stock's own IsInGame() term, which shifts the bar left by 47
// in a match exactly as stock intended -- that is what keeps it aligned on both surfaces.
#define GF_TICKER_X			( -77 - ( IsInGame() * 47 ) )
#define GF_TICKER_Y			-100
#define GF_TICKER_BG_W		455
#define GF_TICKER_BG_H		15
#define GF_TICKER_TEXT_Y	( GF_TICKER_Y + 13 )
#define GF_TICKER_H			12

// Rotation timing. TK_COUNT is the number of TK_LINE slots the including menu declares; each shows
// for TK_SLOT_MS with a TK_FADE_MS fade at both ends.
#define TK_COUNT			2
#define TK_SLOT_MS			5000
#define TK_FADE_MS			500
#define TK_CYCLE_MS			( TK_SLOT_MS * TK_COUNT )
#define TK_T( n )			( ( milliseconds() + TK_CYCLE_MS - ( n * TK_SLOT_MS ) ) % TK_CYCLE_MS )
#define TK_VIS( n )			when( TK_T( n ) < TK_SLOT_MS )
#define TK_ALPHA( n )		( max( 0, min( 1, min( float( TK_T( n ) ) / TK_FADE_MS, float( TK_SLOT_MS - TK_T( n ) ) / TK_FADE_MS ) ) ) )

	// The bar itself (stock bar art, so nothing new has to reach the client).
	itemDef
	{
		style			WINDOW_STYLE_SHADER
		type			ITEM_TYPE_IMAGE
		rect			0 GF_TICKER_Y GF_TICKER_BG_W GF_TICKER_BG_H HORIZONTAL_ALIGN_CENTER VERTICAL_ALIGN_BOTTOM
		exp				rect X( GF_TICKER_X )
		forecolor		0 0 0 0.6
		exp				material( "menu_mp_bar_shadow" )
		visible			1
		decoration
	}

#define TK_LINE( n, txt )																		\
	itemDef																						\
	{																							\
		type			ITEM_TYPE_TEXT															\
		rect			0 GF_TICKER_TEXT_Y 440 GF_TICKER_H HORIZONTAL_ALIGN_CENTER VERTICAL_ALIGN_BOTTOM	\
		exp				rect X( GF_TICKER_X + 5 )												\
		textfont		UI_FONT_SMALL															\
		textscale		0.25																	\
		textalign		ITEM_ALIGN_LEFT															\
		forecolor		0.84313 0.84313 0.84313 1												\
		exp				forecolor a ( TK_ALPHA( n ) );											\
		exp				text( txt );															\
		visible			TK_VIS( n );															\
		decoration																				\
	}
