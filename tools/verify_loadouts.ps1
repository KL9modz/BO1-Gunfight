param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

# Statically validate the hand-authored loadout pool in _gf_loadouts.gsc.
#
# Why this exists: every failure mode in the pool is SILENT at runtime.
#   - An unknown WEAPON token is a GiveWeapon no-op: a primary falls back to the engine's
#     finger gun, an offhand simply never appears — for every player, every rotation of
#     that loadout, all match long.
#   - An unknown PERK token is a SetPerk no-op (the loadout editor validates perks at save
#     time, but a hand edit between the markers bypasses it entirely — which this file's
#     own header explicitly invites: "hand-editing between them is fine too").
#   - An empty pool would make gf_currentLoadoutIndex modulo-by-zero every round.
# None of that surfaces as an error anywhere; it surfaces as "this gun never showed up",
# weeks later, on the VPS. This closes the gap the same way verify_release_strip.ps1 does
# for the strip regions: prove the data at commit time.
#
# Sources of truth (deliberately not new lists — both already exist):
#   - Weapon tokens : tools/weapon_tokens_mp.txt, generated from the engine dump's
#     <GameRoot>\raw\weapons\mp\ filenames (the file NAME is the GiveWeapon token).
#     One committed copy so clones without the game installed can still validate.
#   - Perk tokens   : the PERKS catalog in tools/loadout_editor/server.js — the same
#     engine-token table the editor's save-time validator uses, parsed from the source
#     so the two consumers cannot drift.
#
# Usage:  tools\verify_loadouts.ps1

$GscPath    = Join-Path $WorkspaceRoot "maps\mp\gametypes\_gf_loadouts.gsc"
$TokensPath = Join-Path $PSScriptRoot "weapon_tokens_mp.txt"
$EditorPath = Join-Path $PSScriptRoot "loadout_editor\server.js"

foreach ($p in @($GscPath, $TokensPath, $EditorPath)) {
    if (!(Test-Path -LiteralPath $p)) { Write-Host "FAILED -- missing input: $p" -ForegroundColor Red; exit 1 }
}

# -- Weapon whitelist -------------------------------------------------------------
$WeaponTokens = @{}
foreach ($line in (Get-Content -LiteralPath $TokensPath)) {
    $t = $line.Trim()
    if ($t.Length -eq 0 -or $t.StartsWith("#")) { continue }
    $WeaponTokens[$t] = $true
}
# The Finger Gun is the one deliberate off-list token: a real SP weapon def
# (raw\weapons\sp\defaultweapon, no _mp suffix), precached by gf.gsc and given as the
# Death Machine's easter-egg secondary. The MP dump list carries defaultweapon_mp,
# which is a DIFFERENT def — keep this exception explicit rather than widening the list.
$WeaponTokens["defaultweapon"] = $true

# ⚠ The raw dump is INCOMPLETE for two-attachment (Warlord) combos — it carries some
# (spectre_acog_grip_mp, kiparis_grip_extclip_mp) but not all (no *_elbit_dualclip_mp at
# all), while mp/attachmentTable.csv proves those pairings valid (elbit's compatible list
# includes dualclip and grip) and the engine ships their defs inside fastfiles. So an
# unknown token of the shape base_a1_a2_mp is accepted iff BOTH single-attachment
# variants base_a1_mp AND base_a2_mp exist in the dump — a typo in the base or either
# attachment still fails, which is the error class this check exists for. Accepted
# limitation: an incompatible-but-both-real pairing (e.g. two top-slot optics) would
# pass; the editor UI can't author one and hand-authoring one has never happened.
function Test-WeaponToken {
    param([string]$Tok)
    if ($WeaponTokens.ContainsKey($Tok)) { return $true }
    $m = [regex]::Match($Tok, '^(.+)_([a-z0-9]+)_([a-z0-9]+)_mp$')
    if (-not $m.Success) { return $false }
    $base = $m.Groups[1].Value; $a1 = $m.Groups[2].Value; $a2 = $m.Groups[3].Value
    if ($a1 -eq $a2) { return $false }
    return ($WeaponTokens.ContainsKey("${base}_${a1}_mp") -and $WeaponTokens.ContainsKey("${base}_${a2}_mp"))
}

# -- Perk whitelist: parse the editor's PERKS catalog rows ({ t: "specialty_..." }) ----
$PerkTokens = @{}
$editorText = [System.IO.File]::ReadAllText($EditorPath)
foreach ($m in [regex]::Matches($editorText, '\{\s*t:\s*"(specialty_[a-z0-9_]+)"')) {
    $PerkTokens[$m.Groups[1].Value] = $true
}
if ($PerkTokens.Count -lt 30) {
    # The engine knows ~52 specialty tokens; a catalog parse this small means the editor's
    # source format changed and the regex above silently stopped matching — fail loudly
    # rather than validate against a near-empty set (which would flag every real perk).
    Write-Host ("FAILED -- only {0} perk tokens parsed from {1}; the PERKS catalog format has changed" -f $PerkTokens.Count, $EditorPath) -ForegroundColor Red
    exit 1
}

# -- Extract the pool region ------------------------------------------------------
$gscLines = [System.IO.File]::ReadAllText($GscPath) -split "`n"
$begin = -1; $end = -1
for ($i = 0; $i -lt $gscLines.Count; $i++) {
    if ($gscLines[$i] -match '#gf-loadout-editor-begin') { $begin = $i }
    elseif ($gscLines[$i] -match '#gf-loadout-editor-end') { $end = $i; break }
}
if ($begin -lt 0 -or $end -le $begin) {
    Write-Host "FAILED -- #gf-loadout-editor-begin/end markers not found (or out of order) in _gf_loadouts.gsc" -ForegroundColor Red
    exit 1
}

# gf_load( "pri", "sec", "equip", "lethal", "tactical", camo, camoSec [, "perks"] )
# Strings first, then the two ints, then the optional quoted perk list. Parsed with one
# anchored regex (no comma-splitting — the perks string contains commas).
$LoadRe = '(?x) pool\[n\]\s*=\s*gf_load\(\s*
    "([^"]*)"\s*,\s*   # 1 primary
    "([^"]*)"\s*,\s*   # 2 secondary
    "([^"]*)"\s*,\s*   # 3 equipment
    "([^"]*)"\s*,\s*   # 4 lethal
    "([^"]*)"\s*,\s*   # 5 tactical
    (-?\d+)\s*,\s*     # 6 camo
    (-?\d+)\s*         # 7 camoSec
    (?:,\s*"([^"]*)"\s*)?   # 8 perks (optional)
    \)\s*;\s*n\+\+\s*;'

$errors = @()
$count  = 0
$slotNames = @("primary", "secondary", "equipment", "lethal", "tactical")

for ($i = $begin + 1; $i -lt $end; $i++) {
    $line = $gscLines[$i]
    if ($line -notmatch 'gf_load\s*\(') { continue }
    $lineNo = $i + 1

    $m = [regex]::Match($line, $LoadRe)
    if (-not $m.Success) {
        # A line that mentions gf_load but doesn't parse is an ERROR, not a skip — a
        # malformed hand edit is exactly the input this validator exists to catch.
        $errors += "MALFORMED LINE  :{0}  gf_load call does not match the expected shape" -f $lineNo
        continue
    }
    $count++

    for ($s = 0; $s -lt 5; $s++) {
        $tok = $m.Groups[$s + 1].Value
        if ($tok -eq "none") {
            # "none" is the empty-slot token; ONLY equipment may be empty (the give is
            # skipped and the HUD column hidden). Anywhere else the engine hands out the
            # finger-gun fallback instead of nothing.
            if ($s -ne 2) { $errors += "BAD 'none'      :{0}  {1} cannot be 'none' -- only equipment may be empty" -f $lineNo, $slotNames[$s] }
            continue
        }
        if (-not (Test-WeaponToken $tok)) {
            $errors += "UNKNOWN WEAPON  :{0}  {1} '{2}' is not a weapon this engine knows -- GiveWeapon would silently no-op" -f $lineNo, $slotNames[$s], $tok
        }
    }

    foreach ($g in @(6, 7)) {
        $c = [int]$m.Groups[$g].Value
        if ($c -lt -1 -or $c -gt 15) {
            $errors += "BAD CAMO        :{0}  camo index {1} out of range -1..15" -f $lineNo, $c
        }
    }

    if ($m.Groups[8].Success -and $m.Groups[8].Value.Trim().Length -gt 0) {
        $seen = @{}
        foreach ($raw in ($m.Groups[8].Value -split ",")) {
            $tok = $raw.Trim()
            if ($tok.Length -eq 0) { continue }
            $bare = $tok.TrimStart("-")
            if (-not $PerkTokens.ContainsKey($bare)) {
                $errors += "UNKNOWN PERK    :{0}  '{1}' is not a specialty this engine knows -- SetPerk would silently do nothing" -f $lineNo, $tok
            }
            if ($seen.ContainsKey($bare)) {
                $errors += "DUPLICATE PERK  :{0}  '{1}' listed twice" -f $lineNo, $bare
            }
            $seen[$bare] = $true
        }
    }
}

if ($count -eq 0) {
    $errors += "EMPTY POOL      no gf_load lines found between the markers -- gf_currentLoadoutIndex would modulo-by-zero every round"
}

# -- Report -----------------------------------------------------------------------
Write-Host "Verifying the loadout pool"
Write-Host ("  {0} loadout(s), {1} weapon token(s) known, {2} perk token(s) known" -f $count, $WeaponTokens.Count, $PerkTokens.Count)
Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "FAILED -- the pool would misbehave silently at runtime:" -ForegroundColor Red
    Write-Host ""
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
    Write-Host ""
    Write-Host ("{0} problem(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}
Write-Host "OK -- every weapon and perk token resolves, camos in range, 'none' only in equipment." -ForegroundColor Green
exit 0
