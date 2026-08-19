# GF_TEAMWATCH has fired 243 times, 7 of them UNTRACED — and the reclaim caught all 7

**Date:** 2026-08-18 **Status:** measured on the live VPS log (full history, single file)

## What this corrects

`.claude/CLAUDE.md` stated, in the *Humans stranded in spectator* open bug, that **"`GF_TEAMWATCH` has
fired 0 times ever"**, and used that zero to file the whole strand as *hypothesis only, never observed*.
**That is false.** A count over the live `games_mp.log` (233MB, full history):

| `reason` | firings | what it is |
|---|---|---|
| `user` | 223 | self-chose spectator in the team menu — intentional, working as designed |
| `UNTRACED` | **7** | **the actual signal** |
| `moved` | 7 | sanctioned `gf_seqTeamMove` (incl. the bridge admin force) |
| `maxsize` | 6 | `scr_team_maxsize` capacity overflow |
| **total** | **243** | |

`lock-queue` has never fired. ⚠ **The headline number is meaningless on its own** — 92% of firings are
`reason user`, i.e. people choosing to spectate. A raw `grep -c GF_TEAMWATCH` is not a fault count;
**only `reason UNTRACED` is.** That is probably how the "0 times" claim survived: the interesting
subset really is rare.

## The 7 UNTRACED firings, verbatim

```
439:59  human KL9              round 0, state spectator,    needteam 0, lastWriter none->- gen -1/26397150,  lock 0
106:53  human flko_0           round 7, state spectator,    needteam 0, lastWriter none->- gen -1/6410750,   lock 0
659:40  human shedoesntlovekey round 1, state intermission, needteam 1, lastWriter none->- gen -1/39513350,  lock 0
9360:24 human LiMi7ED          round 6, state intermission, needteam 1, lastWriter none->- gen -1/561608950, lock 0
911:20  human 007cide          round 0, state spectator,    needteam 0, lastWriter none->- gen -1/54677650,  lock 0
2400:12 human patoblack        round 2, state intermission, needteam 1, lastWriter none->- gen -1/143992400, lock 0
11:43   human KL9              round 3, state intermission, needteam 1, lastWriter none->- gen -1/653950,    lock 0
```

## Three things the data settles

**1. The containment has a perfect record: 7 UNTRACED → 7 `GF_RECLAIM`, 1:1.** Every stranded human was
re-seated onto the lighter side at the boundary. `gf_reclaimStrandedHumans` is doing exactly its job, and
`gf_specReasonTag` has never misclassified an intentional spectate as UNTRACED (or the reclaim count
would exceed the UNTRACED count).

**2. Every one is a genuinely stampless write.** All 7 carry `lastWriter none->- gen -1` — not a *stale*
token, **no token at all**, on any of the 10 sanctioned writers, ever, for that player. That is precisely
the signature `gf_teamWatchHumans`' own forensics comment predicts for "truly engine/stock". So this is
**not** the [[untraced-writes-are-unstamped-stock-menu-paths]] family (those were reclassified and are now
stamped `stockauto`/`stockmenu`); a real unstamped writer exists and is still unpinned.

**3. `needteam` splits them 3 / 4, and only one half is the reported bug.** Per the stock model in the
code comment — the team menu (`_globallogic_player.gsc:365`) fires on spectator + needteam-**undefined**,
while a needteam spectator is autoassigned via `level.autoassign` (`:327`) with no menu:

- **`needteam 0` — 3 cases** (KL9 r0, flko_0 r7, 007cide r0): the genuine *"forced to choose a team"*
  strand. All three were `state spectator`.
- **`needteam 1` — 4 cases** (shedoesntlovekey r1, LiMi7ED r6, patoblack r2, KL9 r3): would be
  autoassigned, no menu. All four were `state intermission`.

⚠ **The `state` correlation is perfect across all 7** and is worth chasing: `needteam 0` ⟺ `spectator`,
`needteam 1` ⟺ `intermission`. Two different paths, not one bug with noise.

## The occurrence that prompted this

2026-08-18 22:29:11 PT, `mp_cosmodrome`, round 3 — the owner (KL9) joined and landed stranded; the
reclaim re-seated them to allies at the same boundary. `needteam 1`, so **this instance would have been
autoassigned anyway** and is not the menu case. It surfaced only because the session was already reading
the log for an unrelated client freeze.

## How to re-measure (and the trap)

⚠ **The live `games_mp.log` does not rotate** — the server holds the handle open (`g_logSync 1`), and a
server restart alone did **not** roll it: the single 233MB file spans the whole history. That is what
makes a one-pass count over it authoritative. Don't assume you are only seeing the current uptime.

```powershell
$f='...\mods\mp_gunfight\logs\games_mp.log'
(Select-String -Path $f -Pattern 'GF_TEAMWATCH.*UNTRACED').Count   # the signal
(Select-String -Path $f -Pattern 'GF_RECLAIM').Count               # must match it 1:1
# reason tally: one pass, group in memory (5 separate Select-String passes over 233MB times out)
$l=(Select-String -Path $f -Pattern 'GF_TEAMWATCH').Line; $h=@{}
foreach($x in $l){ if($x -match 'reason (\S+)'){ $h[$Matches[1]] = 1 + $h[$Matches[1]] } }
```

## What is still open

**Which writer.** No stamp, so the tracer's by-difference design has nothing to attribute. The next lever
is the `needteam`/`state` split above: two reproducible shapes to hunt separately rather than one vague
"engine did it". Related: [[quiet-team-move-cleared-class-blocks-respawn]] (the *other* strand-shaped
report, root-caused to a cleared `pers["class"]` and fixed — a different bug),
[[untraced-writes-are-unstamped-stock-menu-paths]] (the stock-menu family, now stamped and excluded).
