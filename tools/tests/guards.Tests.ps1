# Pester regression net for the shared publish guards + strip machinery in
# tools/release_common.ps1 — the PS half of the twin-guard system (the sh half lives in
# tools/hooks/pre-commit; release_common.ps1's own header documents the lockstep contract).
#
#   Invoke-Pester tools/tests
#
# Every case below encodes either a PAST INCIDENT (sentence-final period hiding an address,
# the '.?' leading-slot drift between the twins, secrets.local.json.bak passing all three
# layers) or a DOCUMENTED-ON-PURPOSE behaviour whose silent change would break the guard's
# contract (the version-string concession, pii-ok vs ip-ok asymmetry).
#
# ⚠ Assertions are plain `if (...) { throw }` — NOT `Should Be` / `Should -Be` — on purpose:
# the inbox Windows Pester is 3.4 (space syntax) and Pester 5 removed that syntax entirely,
# so either dialect fails on the other box. An `It` block failing on a thrown exception is
# the one contract every Pester version honours.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $here) "release_common.ps1")

function Assert-True($cond, $msg)  { if (-not $cond) { throw "ASSERT: $msg" } }
function Assert-False($cond, $msg) { if ($cond)      { throw "ASSERT: $msg" } }
function Assert-Eq($actual, $expected, $msg) {
    if ("$actual" -ne "$expected") { throw "ASSERT: $msg -- expected [$expected], got [$actual]" }
}

Describe "Strip-Markers" {
    It "removes a marked region inclusive of both marker lines" {
        $in = "keep1`n// #strip-begin x`ndev1`ndev2`n// #strip-end`nkeep2`n"
        Assert-Eq (Strip-Markers $in) "keep1`nkeep2`n" "region + markers removed"
    }
    It "removes multiple regions independently (non-greedy)" {
        $in = "a`n// #strip-begin`nd1`n// #strip-end`nb`n// #strip-begin`nd2`n// #strip-end`nc`n"
        Assert-Eq (Strip-Markers $in) "a`nb`nc`n" "both regions removed, kept code between survives"
    }
    It "an UNMATCHED begin leaves the whole region in place (why verify_release_strip checks balance)" {
        # This is the documented worst failure direction: the regex simply never matches, so
        # the dev body SHIPS. The behaviour itself is unfixable at the regex layer — the
        # verifier's marker-balance check (added 2026-07-28) is the guard. If this ever starts
        # passing, the regex changed shape and that verifier logic must be revisited.
        $in = "keep`n// #strip-begin never closed`ndev`n"
        Assert-Eq (Strip-Markers $in) $in "unmatched begin strips nothing"
    }
    It "handles CRLF content" {
        $in = "keep`r`n// #strip-begin`r`ndev`r`n// #strip-end`r`nkeep2`r`n"
        Assert-Eq (Strip-Markers $in) "keep`r`nkeep2`r`n" "CRLF region removed"
    }
}

Describe "Test-PublicIPv4Literal" {
    It "flags a public address" {
        Assert-True (Test-PublicIPv4Literal "51.68.200.10") "public quad flagged"
    }
    It "excludes every reserved/documentation range on the ladder" {
        foreach ($q in @("127.0.0.1", "10.1.2.3", "192.168.1.5", "172.16.0.9", "172.31.255.1",
                         "169.254.1.1", "100.64.0.1", "100.127.9.9", "198.18.0.1",
                         "192.0.2.44", "198.51.100.7", "203.0.113.200", "224.0.0.1", "255.255.255.255", "0.4.0.4")) {
            Assert-False (Test-PublicIPv4Literal $q) "$q must be excluded"
        }
    }
    It "concedes the version-string shape (all octets <= 20) -- deliberate, documented hole" {
        Assert-False (Test-PublicIPv4Literal "1.2.3.4") "version-string shape conceded"
        Assert-False (Test-PublicIPv4Literal "8.8.8.8") "the known cost of the concession"
        Assert-True  (Test-PublicIPv4Literal "1.2.3.21") "one octet over 20 is an address again"
    }
    It "rejects non-quads" {
        Assert-False (Test-PublicIPv4Literal "300.1.1.1") "octet > 255"
        Assert-False (Test-PublicIPv4Literal "1.2.3")     "3 groups"
    }
}

Describe "Get-LeakIpLiterals" {
    It "catches a SENTENCE-FINAL address (the trailing-dot incident)" {
        $hits = @(Get-LeakIpLiterals "the server answered from 51.68.200.10.")
        Assert-Eq $hits.Count 1 "sentence-final quad found"
        Assert-Eq $hits[0] "51.68.200.10" "trailing period stripped"
    }
    It "sees BOTH addresses on one line" {
        $hits = @(Get-LeakIpLiterals "from 51.68.200.10 to 51.68.200.11")
        Assert-Eq $hits.Count 2 "both quads found"
    }
    It "ignores 5-group tokens, build numbers and regex literals" {
        Assert-Eq @(Get-LeakIpLiterals "1.2.3.4.5 and 10.0.19045.123 and \d{1,3}(\.\d{1,3}){3}").Count 0 "no false positives"
    }
    It "still excludes a reserved address even sentence-final" {
        Assert-Eq @(Get-LeakIpLiterals "listening on 127.0.0.1.").Count 0 "exclusion ladder still applies after dot strip"
    }
    It "catches a global-unicast IPv6 literal but not times, dates or gf telemetry" {
        Assert-Eq @(Get-LeakIpLiterals "addr 2607:5300:60:80::1 up").Count 1 "global unicast found"
        Assert-Eq @(Get-LeakIpLiterals "at 14:22:07 on 2026:07:25 state 3:2:5:2:1:gf:0:3:3:3:1:fu").Count 0 "colon noise excluded"
        Assert-Eq @(Get-LeakIpLiterals "see 2001:db8::1 in docs").Count 0 "RFC 3849 documentation range excluded"
    }
}

Describe "StatusRosterRe (raw-file twin of the hook's section 5)" {
    It "matches a sanitized roster row, including one nested in leading whitespace" {
        Assert-True ("  2   857    0 1234567 ^1SomeBot         0 unknown  42  5000" -match $script:StatusRosterRe) "leading-space row matched"
        Assert-True ("2 857 0 1234567 ^1Name" -match $script:StatusRosterRe) "bare row matched"
    }
    It "requires the colour code -- a plain table of integers is not a roster row" {
        Assert-False ("12 857 0 1234567 PlainName" -match $script:StatusRosterRe) "no ^N = no match"
    }
    It "documents the shared residual: a bullet/pipe/quote-prefixed row is out of scope for BOTH twins" {
        # Deliberate: the leading slot means "whitespace or a digit". The hook (which governs
        # entry into git) has the same residual, and release_common.ps1's header explains why
        # the two must stay SEMANTICALLY equal. If this starts matching, the twin drifted.
        Assert-False ("- 2 857 0 1234567 ^1Name" -match $script:StatusRosterRe) "bullet row out of scope (both sides)"
        Assert-False ("| 2 857 0 1234567 ^1Name" -match $script:StatusRosterRe) "pipe row out of scope (both sides)"
    }
    It "allows the negative score column (signed 16-bit lesson applied here too)" {
        Assert-True ("2 -857 0 1234567 ^1Name" -match $script:StatusRosterRe) "negative score matched"
    }
}

Describe "Test-LocalOnlyPath (rule A)" {
    It "matches the exact store names and the near-miss backup that once passed all three layers" {
        Assert-True (Test-LocalOnlyPath "secrets.local.json")     "exact store"
        Assert-True (Test-LocalOnlyPath "secrets.local.json.bak") "editor backup (the incident)"
        Assert-True (Test-LocalOnlyPath "tools\ops.local.md")     "ops crib sheet, any extension"
        Assert-True (Test-LocalOnlyPath "prefs.local.json")       "pinboard"
    }
    It "lets the committable templates through" {
        Assert-False (Test-LocalOnlyPath "ops.local.json.example")     "template ships"
        Assert-False (Test-LocalOnlyPath "secrets.local.json.example") "template ships"
    }
    It "does not match unrelated names" {
        Assert-False (Test-LocalOnlyPath "server.js") "ordinary file"
        Assert-False (Test-LocalOnlyPath "config.json.md") "not a store leaf"
    }
}

Describe "Find-LeakHits (rule B end-to-end over a temp tree)" {
    $tmp = Join-Path $env:TEMP ("gf-guardtest-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Set-Content -Path (Join-Path $tmp "doc.md") -Encoding Ascii -Value @(
        "clean line",
        "leaky address 51.68.200.10 here",
        "intended address 51.68.200.11 here <!-- ip-ok -->",
        "  2   857    0 1234567 ^1SomeBot 0 unknown 42 5000",
        "  3   857    0 1234567 ^1Marked 0 unknown 42 5000 <!-- pii-ok -->"
    )
    Set-Content -Path (Join-Path $tmp "binary.bin") -Encoding Ascii -Value "51.68.200.12"  # extension not scanned

    $hits = @(Find-LeakHits -Root $tmp)

    It "flags the bare public address" {
        Assert-True (($hits -join "`n") -match "51\.68\.200\.10") "bare address reported"
    }
    It "honours ip-ok for the whole line" {
        Assert-False (($hits -join "`n") -match "51\.68\.200\.11") "ip-ok line skipped"
    }
    It "flags the unmarked roster row and honours pii-ok on the marked one" {
        $roster = @($hits | Where-Object { $_ -match "roster row" })
        Assert-Eq $roster.Count 1 "exactly the unmarked row"
        Assert-True ($roster[0] -match ": 4 :") "and it is line 4"
    }
    It "skips extensions outside the text list" {
        Assert-False (($hits -join "`n") -match "51\.68\.200\.12") "binary extension not scanned"
    }

    Remove-Item -Recurse -Force $tmp
}
