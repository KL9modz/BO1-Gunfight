# "Prestige changes, then resets back later in the same match" — a DStat write aimed at a node stock never reads

**Date:** 2026-08-20 (owner report: *"it was working the other day but now i cant set anyones
prestige"*, then *"sometimes it changes but then they get reset back later in the same match"*).
**Status: root-caused and FIXED** in `_gf_fun::gf_funPrestige`.

⚠ Two *different* faults were reported as one symptom. The total failure was the cheat gate
re-locking on a server restart ([[cheat-gate-relocks-on-every-server-restart]]). This note is the
second one: the revert.

## Symptom

The prestige visibly changes on the target's rank badge and the bridge prints its green
`^2Prestige N: <name>` success line. A round or two later it is back to the old value, without
anyone touching anything. Sometimes described as "it takes, then it resets mid-match".

## The bug

`gf_funPrestige` wrote a **four-arg** DStat:

```gsc
target setDStat( "playerstatslist", "plevel", "StatValue", p );   // WRONG
```

That addresses the CHILD node `PlayerStatsList/plevel/StatValue`. Stock never reads it. From `raw/`:

| direction | call chain | arity |
|---|---|---|
| read | `_rank::getPrestigeLevel()` → `_persistence::statGet("plevel")` → `getdstat( "PlayerStatsList", "plevel" )` | **2 args** |
| write | `_persistence::statSet` → `statSetInternal` → `setPlayerStat` → `setdstat( baseName, dataName, value )` | **3 args** |

⚠ A **case-sensitive** grep for the literal `"StatValue"` across the whole stock script dump returns
**zero hits**. The lowercase `statValue` that does exist is a local variable and a DDL field inside
the **weapon / group challenge** sub-trees only — `getDStat( baseName, item, "stats", statName,
statType )` — never under `PlayerStatsList/<stat>`. So the write went to a node nothing on the read
side has ever looked at.

## Why it looked like it worked, which is the expensive part

The line *after* the write is `target setRank( rank, p )`. **`setRank` is live and
NON-PERSISTENT**: it updates the badge immediately, which is why the change is real on screen and
the success notify is honest as far as it goes. Nothing reports that the persistent half missed.

Then stock puts it back. `Callback_PlayerConnect` (`_globallogic_player.gsc:15-22`) does
`self waittill("begin"); waittillframeend; level notify("connected", self)` — and **it re-runs on
every `map_restart`**, i.e. at every round boundary in this mod. `_rank::onPlayerConnect` is parked
on that notify and does:

```gsc
player.pers["plevel"] = player _persistence::statGet( "PLEVEL" );
prestige = player getPrestigeLevel();
player setRank( rankId, prestige );
player.pers["prestige"] = prestige;
```

It re-reads the **untouched** stat and re-applies `setRank` from it. Hence: reverts one round after
the click, in the same match, with no trigger a player would recognise.

## The fix

Route through stock's own writer, the exact inverse of stock's reader:

```gsc
target maps\mp\gametypes\_persistence::statSet( "plevel", p, false );
target.pers["plevel"]   = p;
target.pers["prestige"] = p;
```

`includeGameType` is **false**: prestige is a global stat, there is no `PlayerStatsByGameMode/plevel`,
and stock's own connect-time read is the global one. Both `pers` fields are stamped because stock
stamps both at connect — `pers["plevel"]` is what `shouldKickByRank()` reads, `pers["prestige"]` is
what the rest of the rank code reads, and setting only one left them disagreeing until the next
re-begin.

## The rule this generalises to

⚠ **An account write must go through the same `_persistence` entry point that stock's reader is the
inverse of.** Never hand-roll a `setdstat` next to a stock `statGet`. The other three editors were
already correct and are the model: `funlevel50_` uses `statSet("rankxp", …)`, `funcodpoints_` uses
`_rank::setCodPointsStat` (→ `setPlayerStat("PlayerStatsList","CODPOINTS",…)`), `fununlockpro` uses
stock `unlockItemFromChallenge`. Prestige was the only one improvising, and it was the only one that
broke.

⚠ **A DStat key-path error is SILENT IN BOTH DIRECTIONS.** `setdstat` does not validate the path and
`getdstat` returns 0 for a node that was never written, so there is no error line, no log entry and
no failed return to check. The only observable is a value that quietly fails to survive the next
re-begin. If a stat write "doesn't stick", compare arity with stock's reader **first**.

## Why the comment mattered as much as the code

The header called this "EnCoRe's exact battle-tested sequence", and the panel tooltip repeated it.
That framing is what let a wrong call sit unexamined: a borrowed line from another mod is not
evidence, especially a console-era menu whose own stats layer we do not share. Both comments were
rewritten to say so. See also [[read-the-server-not-the-file]] — same failure mode, different layer.

## Blast radius note

Because Gunfight ships **`modStats 0`** ([[plutonium-stats-are-namespaced-per-mod]]), a *working*
prestige write lands on the player's **real** Black Ops profile, permanently. The panel's Account
Editor copy still claimed the sandboxed "writes THIS MOD's own ladder / nobody's real rank is
touched" wording — `3fd02ea` corrected the GSC comments and missed the panel. Fixed here too.
