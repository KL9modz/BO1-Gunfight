---
name: gunfight-description-single-source
description: "Both in-game Gunfight description displays (gametype-select card + match-intro hint splash) now read ONE string, GF_GAMETYPE_DESC"
metadata: 
  node_type: memory
  type: project
  originSessionId: a32b2fd6-bba4-466d-a6e8-48e8f14ca8c6
---

The in-game Gunfight description shows in TWO places and both now resolve to the
single localized string `GF_GAMETYPE_DESC` (declared as `REFERENCE GAMETYPE_DESC`
in `localizedstrings/gf.str` — the `GF_` prefix is the `.str` filename auto-prepended
to every reference):

1. **Gametype-select card** (the big diamond icon screen): wired via the description
   column of the `gf` row in `mp/gametypesTable.csv` (`GF_GAMETYPE_DESC`).
2. **Match-intro splash** (the "MAP GAMETYPE / one-line desc" overlay at round start):
   this is the client dvar `cg_objectiveText`, pushed by
   `_globallogic_ui::updateObjectiveText()`. Because gunfight `scorelimit` is 6 (`> 0`), it
   uses the **SCORE** text (`getObjectiveScoreText`, passing `level.scorelimit` as the `&&1`),
   NOT the hint and NOT the plain objective. So the splash = `setObjectiveScoreText`.
   They were stock `OBJECTIVES_TDM` / `_SCORE` / `_HINT` ("Gain points by eliminating enemy
   players. First team to &&1 wins."). Repointing only the HINT (first attempt) did NOT
   change the splash — that was lesson #1.

   GOTCHA (lesson #2): the score path is `setclientdvar("cg_objectiveText", <str>, level.scorelimit)`.
   COD does NOT silently ignore an unused substitution param — if `<str>` has **no** `&&1`
   token, the number is **appended** to the end (we saw "...No health regen.6"). So the score
   string MUST contain a `&&1`. Therefore the splash needs its OWN string:
   `GF_GAMETYPE_DESC_SCORE` = same text but with `&&1` in place of the literal "6"
   ("...\n&&1 rounds to win. ..."). The engine substitutes scorelimit → "6" in the right spot.
   The menu card can't substitute (no param passed → would show literal "&&1"), so it keeps
   the hardcoded-"6" `GF_GAMETYPE_DESC`. Net wiring in gf.gsc:
   - setObjectiveText / setObjectiveHintText (both teams) → `&"GF_GAMETYPE_DESC"` (literal 6)
   - setObjectiveScoreText (both teams) → `&"GF_GAMETYPE_DESC_SCORE"` (`&&1`)  <- this is the splash
   (Splitscreen would show literal "&&1" since line 315 omits the param, but Pluto MP isn't splitscreen.)

Line breaks in the `.str` value use the literal `\n` escape (valid in BO1 .str, e.g.
stock `hideandseek.str`). Editing the description = edit `GAMETYPE_DESC` in `gf.str` then
rebuild `mod.ff` (it's compiled in) via `tools/build_ff.ps1`; the `gf.gsc` repoint only
needs `map_restart`.

NOT covered by this single source: a third **dev-tool mirror** — a hardcoded copy in
`tools/rcon/public/index.html` (`desc:` for the `gf` gametype) — must be updated by hand.
The plain objective / score strings (`OBJECTIVES_TDM` / `OBJECTIVES_TDM_SCORE`,
gf.gsc L296-299) are still stock TDM; they don't appear in those two displays.
