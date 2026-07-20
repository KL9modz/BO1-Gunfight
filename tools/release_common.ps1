# Shared definition of "what the PUBLIC build is". Dot-sourced by:
#   package_release.ps1      - stages + zips the public build
#   verify_release_strip.ps1 - statically proves the staged GSC still resolves
#
# One source of truth on purpose. The dev-file list and the strip regex used to be
# private to the packager, so a checker would have had to re-declare them -- and a
# drifted copy of "what gets dropped" is worse than no checker at all.

# GSC excluded from the public mod outright (forward-slash, repo-relative).
#
# NOTE the pre-match warmup is NOT here: it carries no mod GSC at all. It is the ENGINE's
# own pregame (BlackOpsMP.exe reads g_pregame_enabled at level load and runs BO1's stock
# maps/mp/gametypes/_pregame instead of the gametype). The public build simply never seeds
# that dvar -- the seed in gf.gsc is strip-marked -- so the warmup can't come up, and there
# is no file to drop.
$script:DevFiles = @(
    "maps/mp/gametypes/_bot.gsc",
    "maps/mp/bots/_bot_loadout.gsc",
    "maps/mp/bots/_bot_script.gsc",
    "maps/mp/bots/_bot_utility.gsc",
    "maps/mp/gametypes/_gf_bridge.gsc",
    "maps/mp/gametypes/_gf_debug.gsc"
)

# Dvars that must NOT survive into the public build. Every one is read only by dev
# wiring (RCON bridge / bot reconciler / debug) or by the match-start hold machinery,
# all of which is strip-marked. A surviving READ means a strip region has a hole in it.
# (A surviving mention inside a *string literal* is fine -- the checker only looks at
# getDvar/setDvar call sites.)
$script:StrippedDvars = @(
    # match-start hold / pregame lobby
    "scr_gf_lobby", "scr_gf_lobby_timer", "scr_gf_min_players", "scr_gf_minplayers_timer",
    "scr_gf_load_wait", "scr_gf_load_grace", "g_pregame_enabled", "scr_pregame_timelimit",
    "scr_gf_match_prematch_seconds", "scr_gf_prematch_seconds",
    "gf_matchArmed", "gf_teamplan", "gf_botplan",
    # bots
    "gf_fill_n", "gf_fill_kick_floor", "bot_difficulty", "bots_manage_add", "bots_play_move",
    # RCON bridge
    "gf_cmd", "gf_ack", "gf_state", "gf_roster", "gf_say", "gf_admin_guids",
    "gf_perk_on", "gf_perk_off", "gf_expbullets_radius",
    "gf_vis_vision", "gf_vis_ambient", "gf_vis_gridint", "gf_vis_gridcon", "gf_vis_hdr", "gf_vis_fog",
    # debug
    "gf_debug_spawns", "gf_debug_hud_pool", "gf_debug_elem_probe",
    "gf_hitch_pct", "gf_hitch_debug", "gf_force_loadout", "gf_force_camo",
    # Team-write tracer. Its seed is inside gf.gsc's stripped debug block and its only reader is
    # _gf_debug.gsc (a wholly dropped file), so it must not appear in the public build.
    # NOTE: gf_debug_popup is deliberately NOT listed — its reader (the GF_POPUP gate in
    # _gf_rounds.gsc) ships PUBLIC, sitting on the score path. Unseeded there, getDvarInt returns 0
    # and the logging stays off, which is the intended public behavior.
    "gf_trace_teams",
    # Previously unguarded: only readers are in dropped files today, so nothing leaked, but the
    # checker was not actually covering them.
    "gf_debug_spawnyaw", "gf_endgap_ms", "gf_endprobe_t0", "gf_endprobe_last"
)

# Remove every "// #strip-begin ... // #strip-end" region (dev wiring) inclusive.
#
# Non-greedy per region, so multiple regions in one file each match independently.
# MUST run BEFORE any comment stripping: the marker lines are themselves // comments,
# but the wiring BETWEEN them is real code -- strip comments first and the markers
# vanish while the dev body leaks into the public build.
function Strip-Markers {
    param([string]$Content)
    return [regex]::Replace($Content, "(?ms)^[^\r\n]*#strip-begin\b.*?#strip-end[^\r\n]*\r?\n?", "")
}

# Every .gsc under maps/ that the public build actually ships, as repo-relative
# forward-slash paths.
function Get-ShippedGsc {
    param([string]$ModRoot)
    $out = @()
    foreach ($file in (Get-ChildItem -Recurse -File -LiteralPath (Join-Path $ModRoot "maps") -Filter *.gsc)) {
        $rel = $file.FullName.Substring($ModRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if ($script:DevFiles -contains $rel) { continue }
        $out += $rel
    }
    return $out
}
