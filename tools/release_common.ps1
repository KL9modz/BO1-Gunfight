# Shared definition of "what the PUBLIC build is" AND of "what must never leave this
# repo". Dot-sourced by:
#   package_release.ps1      - stages + zips the public build
#   package_server.ps1       - private VPS bundle (uses the local-store drop-list only)
#   verify_release_strip.ps1 - statically proves the staged GSC still resolves
#   deploy.ps1               - the -Web publish guard (leak scan)
#
# One source of truth on purpose. The dev-file list and the strip regex used to be
# private to the packager, so a checker would have had to re-declare them -- and a
# drifted copy of "what gets dropped" is worse than no checker at all. The same
# reasoning now governs the PUBLISH GUARDS at the bottom of this file: four callers,
# one definition.

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
    "maps/mp/gametypes/_gf_debug.gsc",
    # Ported mod-menu features (EnCoRe V8.3 + guest patches). Dropped WHOLESALE rather than
    # strip-marked: it is reached only from _gf_bridge.gsc (also dropped), so the public build loses
    # the whole feature set with no marker to get wrong and no hole for the verifier to miss.
    "maps/mp/gametypes/_gf_fun.gsc"
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
    "gf_debug_spawnyaw", "gf_endgap_ms", "gf_endprobe_t0", "gf_endprobe_last",
    # Team system (balancer / lock+queue / self-switch / late spawn / reclaim) — all readers live
    # in _bot.gsc (dropped) or strip regions of _gf_rounds.gsc/gf.gsc; the public build keeps stock
    # autoassign + stock team menus. Backfilled 2026-07-28: none of these were covered, so a strip
    # hole around any of them would have passed the verifier silently.
    "gf_team_balance", "gf_team_lock", "gf_team_switch", "scr_gf_latespawn", "gf_team_reclaim",
    "gf_gap_repair",
    # Match-to-match team carry/staging + the roster-expectation load gate — plan plumbing dvars
    # written/consumed only by the match-start hold machinery (strip-marked).
    "gf_team_nextmatch", "gf_teamcarry", "gf_teamstage", "gf_expectcount",
    "scr_gf_load_expect", "scr_gf_load_expect_wait",
    # Debug probes / bot-difficulty selector added after the original list was written.
    "gf_debug_loadgap", "gf_bot_difficulty",
    # Ported fun/mod-menu features. Readers live only in _gf_fun.gsc + _gf_bridge.gsc (both dropped),
    # so a surviving read is by definition a leak. The whole family (including the gf_fun_prev_*
    # engine-dvar snapshots, which are named per dvar) is covered by the "gf_fun_" PREFIX below —
    # these exact names are kept only so the common ones report by name.
    "gf_fun_cheats", "gf_fun_bullet", "gf_fun_nade", "gf_fun_antiquit", "gf_fun_text"
)

# Dev-only dvar PREFIXES. The gf_sv_* bot-tuning mirrors are one per engine dvar (13+ names,
# growing with _gf_bridge::gf_bridgeServerDvarList) and mostly reach the scanner as computed
# strings anyway — but any LITERAL "gf_sv_..." read surviving into a shipped file is a strip
# hole by definition, so the verifier matches the family by prefix rather than chasing an
# exact-name list that would drift the day the allowlist grows.
$script:StrippedDvarPrefixes = @(
    "gf_sv_",
    # Same argument for the fun/mod-menu family: it grows a name per feature (and gf_fun_prev_*
    # grows one per ENGINE dvar the text verbs snapshot), and every reader lives in a dropped
    # file, so the family is covered by prefix rather than by an exact-name list that would drift
    # the day someone adds gf_fun_<next>.
    "gf_fun_"
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

# ===========================================================================
# PUBLISH GUARDS
# ===========================================================================
# Shared by deploy.ps1 (-Web), package_release.ps1 and package_server.ps1. Two
# INDEPENDENT rules live here, because the existing password denylist can see
# neither of them:
#
#   A. LOCAL-ONLY STORES - gitignored per-box files that must never enter any
#      packaged output. They hold live credentials (secrets.local.json), player
#      GUIDs (ignore.local.json), or the ops crib sheet of real infrastructure
#      IPs (servers.local.json / ops.local.json).
#   B. LEAK SCAN         - public IP literals + pasted `status` roster rows.
#      The two worst leaks this repo has had were a third party's real IP in a
#      pasted status dump and the owner's home egress IP in a firewall runbook.
#      Neither is a "secret", so no password scanner would ever have caught them.
#
# ****************************************************************************
# * RULE B IS THE INTENTIONAL TWIN OF tools/hooks/pre-commit SECTIONS 4 + 5. *
# * RULE A IS THE TWIN OF ITS SECTION 1 `case` (and of .gitignore).          *
# * CHANGE BOTH OR NEITHER, IN THE SAME COMMIT.                              *
# ****************************************************************************
# The hook stops a leak ENTERING git; this stops one LEAVING via a publish or a
# bundle. They deliberately share all four opt-out semantics so a developer can
# never satisfy one guard and then be blocked by the other:
#   1. the excluded-range ladder in Test-PublicIPv4Literal below (RFC 5737 /
#      RFC 3849 / private / loopback / link-local / CGNAT / RFC 2544 / multicast,
#      plus the all-octets-<=-20 version-string concession),
#   2. the per-LINE opt-out token  ip-ok  (whitelists the WHOLE line),
#   3. the repo-wide allowlist file tools/hooks/ip-allow.txt - the SAME file the
#      hook reads, deliberately, so there is one list and not two,
#   4. the per-LINE opt-out token  pii-ok  for the roster half (hook section 5),
#      a separate token from ip-ok so marking a sanitized roster row does not
#      also blind the address rule on that line.
# Widen one side and you must widen the other. A rule that exists on only one
# side produces the worst outcome available: an address the hook waves through
# that deploy then refuses at 2am, or a page that publishes what git blocked.
#
# ** "The same spelling" is NOT the test -- the same BEHAVIOUR is. ** The two run over
#    different input: the hook reads DIFF lines (always '+'-prefixed), this reads RAW
#    file lines. A regex copied across verbatim therefore means something different on
#    each side, which is how $StatusRosterRe's leading-character slot drifted while
#    looking byte-identical (see the note on it below). Where the input differs, spell
#    them differently ON PURPOSE and say so in a comment on BOTH sides.
#
# ** The hook's section 2 (rcon/g_password values, long key tokens) and section 3
#    (non-canonical Discord invite) have NO twin here, deliberately. ** Rule B is the
#    twin of sections 4 + 5 only. That is why the hook's  pw-ok  opt-out is hook-only
#    and there is nothing to mirror: it exempts a line from the password and key
#    patterns, which do not exist in this file. If a password rule is ever added here,
#    it must honour pw-ok on the same terms, or the split this header warns about
#    reappears on a third rule.
# ** This has already cost a changeset once: the roster rule shipped without an
#    opt-out and made its own sanitized documentation uncommittable except with
#    --no-verify, which also disarms the password, key, store and Discord rules. **
#
# Known and accepted: the leak scan is a TEXT scan. It cannot see inside mod.ff,
# an image, or a zip. That is fine -- neither has ever been a leak vector here,
# and the guard's job is the human-authored text that has been.

# The gitignored per-box stores, by LEAF NAME (robocopy /XF and the packagers all
# match on the name, and the same file can legitimately live at more than one
# path). Keep this in lockstep with deploy.ps1's $xf robocopy exclusions and with
# .gitignore -- a name missing from any one of the three ships the real values
# straight back out.
#
# ** AND with the hook's section 1 `case` ladder, which is the fourth copy. ** Nine of
#    the names below were once absent from it -- including the `ops.local.*` glob, the
#    crib sheet ip-allow.txt's own header names as the sole home of the home egress IP
#    and the VNC console address -- so `git add -f` committed them clean while this
#    file would have refused to publish them. The ladder now spells the exact names
#    `*/NAME|NAME` to reproduce this list's LEAF-name semantics on a repo-relative
#    path. Where the two still differ the hook is the stricter side, which is the safe
#    direction: nothing it blocks was ever going to be publishable anyway.
#
# ** ONE INTENTIONAL ASYMMETRY, DO NOT "FIX" IT: `dedicated.cfg` is absent from this
#    list on purpose. ** The hook blocks it (it must never enter git -- it carries the
#    live rcon password), but package_server.ps1 deliberately SHIPS it inside the
#    private VPS bundle, which is the whole point of that bundle and what -RotateRcon
#    rewrites. Adding it here would break the private bundle to solve a problem the
#    hook already solves. The rule is "never into git", not "never into an output".
$script:LocalOnlyFiles = @(
    "secrets.local.json",     # RCON panel: per-profile rcon passwords (live credentials)
    "servers.local.json",     # RCON panel: profile host/port - the real VPS IP
    "prefs.local.json",       # RCON panel: FAVORITES pinboard (box-local UI state)
    "ignore.local.json",      # muted players - holds GUIDs
    "security.local.json",    # GF-SecurityWatch trust store (ssh key fingerprints)
    "security_state.json",    # its event bookmarks + learned baseline
    "config.json",            # tools/notify: ntfy topic + optional rcon password
    ".dvarcache.json",        # panel dvar cache (box-local)
    ".geocache.json",         # panel ip-api geo cache - maps player IPs to locations
    "watchdog_state.json",
    "watchdog_maintenance.json"
)

# Leaf-name GLOBS, for a store whose extension is not fixed. .gitignore ships the ops
# crib sheet as the glob `tools/ops.local.*` (it may land as .json, .md or .txt), so an
# exact-name list here would be defeated by whichever spelling the operator picked --
# and that file is the one holding the home egress IP and the VNC console address.
# ** A committable `*.example` template is deliberately NOT matched ** (.gitignore
# carries the same `!tools/ops.local.*.example` negation), or the templates that
# document these files could never ship.
#
# ** The two RCON-panel stores are globbed for the same reason, and it is not
#    theoretical. ** They were exact names in all three layers, and the near miss
#    `secrets.local.json.bak` therefore passed every one of them at once: the hook's
#    `*secrets.local.json` case wanted the path to END there, .gitignore listed the
#    exact path, and Test-LocalOnlyPath returned $false -- so `package_server.ps1
#    -IncludeRconTool` would have bundled live rcon passwords onto another box. A
#    routine editor backup is enough to create that name. Keep these in lockstep with
#    .gitignore (`tools/rcon/secrets.local.*`, `tools/rcon/servers.local.*`) and with
#    the hook's `case` -- the exact names below in $LocalOnlyFiles are now redundant
#    with these globs and are kept only because that list is also deploy.ps1's
#    robocopy /XF lockstep list.
$script:LocalOnlyGlobs = @(
    "ops.local.*",            # ops crib sheet: home egress IP, VNC console address
    "secrets.local.*",        # RCON panel: per-profile rcon passwords (live credentials)
    "servers.local.*"         # RCON panel: profile host/port - the real VPS IP
)

# tools/hooks/ip-allow.txt, resolved from a repo root. Returns the path whether or
# not it exists; an ABSENT file means an empty allowlist, exactly as in the hook
# (`[ -f "$ip_allow" ]`) -- never an error, so a clone that predates the file still
# deploys.
function Get-IpAllowFile {
    param([string]$RepoRoot)
    if ([string]::IsNullOrEmpty($RepoRoot)) { return "" }
    return (Join-Path $RepoRoot "tools\hooks\ip-allow.txt")
}

function Get-IpAllowList {
    param([string]$AllowFile)
    $out = @()
    if ([string]::IsNullOrEmpty($AllowFile)) { return $out }
    if (!(Test-Path -LiteralPath $AllowFile)) { return $out }
    foreach ($raw in (Get-Content -LiteralPath $AllowFile)) {
        $t = ($raw -replace '#.*$', '').Trim()
        if ($t.Length -gt 0) { $out += $t }
    }
    return $out
}

# Is this dotted quad a PUBLIC address worth flagging?
#
# ** Every `return $false` below is a line of the hook's `case` ladder. Keep them
#    ordered and worded the same so a diff of the two is readable. **
#
# The all-octets-<=-20 concession is the one deliberate hole: "1.2.3.4", "6.4.0.1"
# and a build number are indistinguishable from an address without context, and
# this repo is full of version strings. Cost of the concession is real but tiny --
# 8.8.8.8 and 1.1.1.1 walk through -- and no player, home or VPS address this repo
# has ever leaked had that shape; version strings constantly do.
#
# ** Do NOT "prove" that last sentence by listing the octets of the addresses it is
#    about. ** A comment in the guard module is still tracked text: an earlier draft
#    of this one carried the first two octets of the home egress IP, both third-party
#    player IPs and the VNC console, and neither guard could catch it -- both match
#    WHOLE dotted quads, so a two-octet prefix walks straight through the very rule
#    it is documenting. The twin at tools/hooks/pre-commit makes the identical point
#    with no octet list; keep it that way on both sides.
function Test-PublicIPv4Literal {
    param([string]$Quad)
    $parts = $Quad.Split('.')
    if ($parts.Count -ne 4) { return $false }
    $o = New-Object 'int[]' 4
    for ($i = 0; $i -lt 4; $i++) {
        if ($parts[$i] -notmatch '^[0-9]{1,3}$') { return $false }
        $o[$i] = [int]$parts[$i]
        if ($o[$i] -gt 255) { return $false }                                    # not a dotted quad at all
    }
    if ($o[0] -le 20 -and $o[1] -le 20 -and $o[2] -le 20 -and $o[3] -le 20) { return $false }  # version-string shape
    if ($o[0] -eq 0 -or $o[0] -eq 10 -or $o[0] -eq 127)          { return $false }  # this-network / private / loopback
    if ($o[0] -eq 169 -and $o[1] -eq 254)                        { return $false }  # link-local
    if ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31)       { return $false }  # private 172.16/12
    if ($o[0] -eq 192 -and $o[1] -eq 168)                        { return $false }  # private
    if ($o[0] -eq 100 -and $o[1] -ge 64 -and $o[1] -le 127)      { return $false }  # CGNAT / Tailscale
    if ($o[0] -eq 198 -and ($o[1] -eq 18 -or $o[1] -eq 19))      { return $false }  # RFC 2544 benchmarking
    if ($o[0] -eq 192 -and $o[1] -eq 0 -and $o[2] -eq 2)         { return $false }  # RFC 5737 TEST-NET-1
    if ($o[0] -eq 198 -and $o[1] -eq 51 -and $o[2] -eq 100)      { return $false }  # RFC 5737 TEST-NET-2
    if ($o[0] -eq 203 -and $o[1] -eq 0 -and $o[2] -eq 113)       { return $false }  # RFC 5737 TEST-NET-3
    if ($o[0] -ge 224)                                           { return $false }  # multicast / reserved / broadcast
    return $true
}

# IPv6: only a GLOBAL-UNICAST literal (a full 4-hex-digit first group starting 2 or
# 3) that also carries a '::' or a 4th group. That anchor alone excludes ::1, ::,
# fe80::, fc00::/fd00::, ff02::, clock times (14:22:07), dates (2026:07:25) and the
# mod's own colon-packed gf_state telemetry strings ("3:2:5:2:1:gf:0:3:3:3:1:fu").
function Test-PublicIPv6Literal {
    param([string]$Token)
    if ($Token -notmatch '^[23][0-9A-Fa-f]{3}(:[0-9A-Fa-f]{0,4}){2,7}$')  { return $false }
    if ($Token -notmatch '::' -and $Token -notmatch '^([0-9A-Fa-f]*:){3}') { return $false }
    if ($Token -match '(?i)^2001:0*db8:')                                  { return $false }  # RFC 3849 documentation
    return $true
}

# Reduce a line to bare digit/dot (then hex/colon) TOKENS and match each one whole.
# This is the PowerShell spelling of the hook's `tr -c '0-9.' '\n'` and it is doing
# real work, not cosmetics: whole-token matching is what makes "1.2.3.4.5",
# "10.0.19045.123" and a literal '\d{1,3}(\.\d{1,3}){3}' regex (this repo carries
# six of those) all fail to match, while still seeing BOTH addresses when two sit
# adjacent on one line -- which a `-match` with boundary guards silently would not.
#
# ** The trailing-dot strip is load-bearing, and it is the twin of the `sed 's/\.*$//'`
#    in the hook's bad_ip4 pipeline -- change both or neither. **
# '.' is INSIDE the split character class (it has to be, it is the quad separator), so a
# SENTENCE-ENDING period is absorbed into the token: "answered from <addr>." came out as
# a 5-group token, failed the whole-quad test, and BOTH guards reported nothing -- while
# the same address followed by any word was caught. This rule's whole stated purpose is
# human-authored prose, and end-of-sentence is the single most common prose position for
# an address, so that was the biggest hole in it. Strips ALL trailing dots, not one, so a
# trailing ellipsis is covered too; the hook's sed does the same. It cannot manufacture a
# false positive: removing dots can only REDUCE the group count, and every survivor still
# has to pass Test-PublicIPv4Literal's 4-group test and full exclusion ladder (so
# "...on 127.0.0.1." is still skipped).
function Get-LeakIpLiterals {
    param([string]$Line)
    $out = @()
    foreach ($t in [regex]::Split($Line, '[^0-9.]+')) {
        $t = $t -replace '\.*$', ''                       # sentence-final period / ellipsis
        if ($t.Length -lt 7) { continue }                 # a flaggable quad is never shorter than this
        if (Test-PublicIPv4Literal $t) { $out += $t }
    }
    if ($Line.Contains(':')) {
        foreach ($t in [regex]::Split($Line, '[^0-9A-Fa-f:]+')) {
            if ($t.Length -lt 6) { continue }
            if (Test-PublicIPv6Literal $t) { $out += $t }
        }
    }
    return ($out | Select-Object -Unique)
}

# A pasted `status` reply is exactly how the player PII got in. Its address column
# is already covered above; this catches a row whose IP was scrubbed but whose guid
# + gamertag were not. Signature = the 4 leading integer columns (num score ping
# guid) followed by a name carrying a Treyarch '^N' colour code. Narrow on purpose:
# a bare Plutonium GUID is a 7-digit integer with no distinguishing shape, so a
# GUID rule cannot be written without flagging every timestamp and byte count in
# the tree.
#
# MEASURED: exactly one false positive across the tracked tree, and it is a known,
# permanent one -- docs/notes/status-address-port-is-signed-16bit-can-be-negative.md
# holds two fully sanitized rows (RFC 5737 addresses, invented names and guids) whose
# column SHAPE is the subject of the note and so cannot be reflowed away. That row
# carries the `pii-ok` marker below. Any OTHER hit is a real finding.
#
# The leading `\s*` is load-bearing: without it a single leading space (a row nested
# inside a markdown list) walks through the whole rule.
#
# ** THE LEADING-CHARACTER SLOT IS THE ONE PLACE THIS REGEX AND ITS TWIN ARE
#    DELIBERATELY NOT SPELLED THE SAME, because they are fed different input. **
#    THIS side matches RAW file lines, which carry no prefix -- hence a bare `^\s*`.
#    The hook's matches DIFF lines, which always carry a '+' -- hence `^\+?[[:space:]]*`.
#    Both therefore mean the identical thing: *the row's own first character must be
#    whitespace or a digit*.
#    Both used to be written `.?` "so the two spellings stay diffable". Identical text
#    over different input is not identical behaviour: here that `.?` was free to eat one
#    ARBITRARY character, so a roster row opening with a markdown bullet ('- '), a table
#    pipe ('| ') or a blockquote ('> ') was PASSED by the commit hook and REFUSED by
#    Find-LeakHits -- exactly the "an address the hook waves through that deploy then
#    refuses at 2am" split the header above says must never exist.
#    Keep the two SEMANTICALLY equal, not textually equal. The residual is shared and
#    known: a roster row whose first character is '-', '|' or '>' is now out of scope
#    for BOTH guards. That was already true of the hook, which is the guard that decides
#    what enters git, so nothing regressed by aligning to it -- and such a row still
#    trips the IP rule above unless its address was scrubbed as well.
$script:StatusRosterRe = '^\s*[0-9]+ +-?[0-9]+ +[0-9]+ +[0-9]+ +[^ ]*\^[0-9]'

# Per-line opt-outs. The `[^A-Za-z0-9_-]` guards are why "zip-ok" does NOT count as
# a marker -- same as the hook's grep.
#
# Two tokens, not one, because the rules answer different questions: `ip-ok` says
# "this ADDRESS is meant to be public", `pii-ok` says "this ROW is already sanitized
# but must keep its column shape". A single token would mean marking the roster note
# also blinded the IP rule on those lines. ** Deliberately NOT an exemption for rows
# whose address sits in an RFC 5737 range ** -- that would blind the rule to the one
# case it exists for, a row whose IP was scrubbed while the gamertag and guid were not.
$script:IpOptOutRe  = '(^|[^A-Za-z0-9_-])ip-ok([^A-Za-z0-9_-]|$)'
$script:PiiOptOutRe = '(^|[^A-Za-z0-9_-])pii-ok([^A-Za-z0-9_-]|$)'

# Text extensions the leak scan reads. A superset of deploy.ps1's password-scan
# list (which is web-only) because this one also runs over staged GSC and tooling.
# Anything not listed -- mod.ff, images, zips -- is skipped, deliberately.
$script:LeakScanExtensions = @(
    ".html", ".htm", ".css", ".js", ".mjs", ".json", ".txt", ".xml", ".svg",
    ".config", ".md", ".yml", ".yaml", ".ini", ".cfg", ".conf", ".env", ".webmanifest",
    ".gsc", ".menu", ".csv", ".str", ".ps1", ".psm1", ".bat", ".cmd", ".sh"
)

# Scan a staged/publish root for rule B. Returns pre-formatted "  rel : line : what"
# strings, empty when clean. Never throws on an unreadable file -- a guard that dies
# on a locked log would just get switched off.
function Find-LeakHits {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$AllowFile,
        [string[]]$TextExtensions = $script:LeakScanExtensions
    )
    $hits = @()
    if (!(Test-Path -LiteralPath $Root)) { return $hits }
    $allow = Get-IpAllowList $AllowFile
    $rootLen = $Root.TrimEnd('\', '/').Length

    # The allowlist itself is a list OF addresses, so scanning it would flag every entry.
    # The hook excludes it the same way (':(exclude)tools/hooks/ip-allow.txt') - without
    # that, adding an entry blocks the very commit that adds it.
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $TextExtensions -contains $_.Extension.ToLowerInvariant() } |
        Where-Object { $_.Name -ne "ip-allow.txt" }

    foreach ($file in $files) {
        $rel = $file.FullName.Substring($rootLen).TrimStart('\', '/')
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
            $lineNo++
            if ($line -notmatch '[0-9]') { continue }              # cheap pre-filter
            # ip-ok skips the WHOLE line, so it exempts the roster check below too --
            # while pii-ok exempts only the roster check. That one-way asymmetry is
            # deliberate and is mirrored in the hook (its status_src derives from
            # ip_src); change it on one side only and the two guards start disagreeing
            # about the same line.
            if ($line -match $script:IpOptOutRe) { continue }      # author opted this LINE out
            foreach ($ip in @(Get-LeakIpLiterals $line)) {
                if ($allow -contains $ip) { continue }
                $hits += ("  {0} : {1} : public IP literal '{2}'" -f $rel, $lineNo, $ip)
            }
            if ($line -match $script:StatusRosterRe -and $line -notmatch $script:PiiOptOutRe) {
                $hits += ("  {0} : {1} : pasted 'status' roster row (gamertag + guid = player PII)" -f $rel, $lineNo)
            }
        }
    }
    return $hits
}

# Rule A. Leaf-name test + a whole-tree sweep, so both the "should I copy this file"
# question and the "did anything slip into the stage" assertion read off one list.
function Test-LocalOnlyPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $leaf = Split-Path -Leaf $Path
    if ($leaf -like "*.example") { return $false }        # templates are meant to ship
    if ($script:LocalOnlyFiles -contains $leaf) { return $true }
    foreach ($g in $script:LocalOnlyGlobs) {
        if ($leaf -like $g) { return $true }
    }
    return $false
}

function Find-LocalOnlyFiles {
    param([Parameter(Mandatory = $true)][string]$Root)
    $hits = @()
    if (!(Test-Path -LiteralPath $Root)) { return $hits }
    $rootLen = $Root.TrimEnd('\', '/').Length
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue)) {
        if (Test-LocalOnlyPath $f.Name) {
            $hits += ("  " + $f.FullName.Substring($rootLen).TrimStart('\', '/'))
        }
    }
    return $hits
}
