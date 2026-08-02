---
name: console-mp-per-round-dvar-dump-flood
description: "console_mp.log grows ~216MB/day because the engine prints a FULL 3,078-line DVAR DUMP at every round's map_restart (92% of volume) — engine-inherent, not a mod flood; and raw\\scripts\\mp\\mp_spawn_fix.gsc is Plutonium's OWN anti-exploit script, not a rogue file"
metadata:
  type: project
---

Diagnosed 2026-08-02, minutes after the service flight recorder went live: the watchdog's
previously-invisible narration surfaced `LIVE log large: console_mp.log = 1116MB` on its first
recorded cycle ([[vps-status-log-notify-services]]).

**The flood is the ENGINE's own per-restart dvar dump, not a mod diagnostic left on.**
`console_mp.log` grows ~216 MB/day (measured live: 118,000 bytes / 45s, at 0 humans + 4 bots).
In a 200k-line window: 60 `END DVAR DUMP` markers = 60 `Executing 'main' for
scripts/mp/mp_spawn_fix.gsc` lines — i.e. **exactly one full 3,078-line dvar dump per
`map_restart`**, and SD round cycling map_restarts every round, 24/7, bots included. The dumps
are **92% of total log volume**. No command echo precedes the dump (it sits inside the engine's
own init spew after the `checksum2:` lines), so it is not something a cfg or the panel triggers.
The rate is not new — 423MB on 07-30 over ~2 days since the 07-28 restart is the same ~210MB/day.

**Bounding, not fixing:** the live file only rolls when the SERVER restarts (engine keeps the
handle; the roll produces `console_mp.log.NNN` archives, which `watchdog.ps1` already prunes to
the `$LogArchiveBudgetMB` budget — verified: ~269MB of archives, under the 400MB cap). Disk is
not urgent (99GB free = months of headroom). Options, in preference order: (a) **accept** — every
deploy restart rolls it, and the watchdog's 800MB warn line is the tripwire, now visible in
`GF-Watchdog.log`; (b) a **scheduled low-traffic restart** (with a 0-humans guard off
`status.json`) if the box ever runs weeks without a deploy; (c) hunt a Plutonium dump-suppress
switch (none known — research before believing one exists). ⚠ Do NOT chase the dump as a mod bug,
and do not read the watchdog's size warning as a `gf_debug_popup`-style flood dvar being on —
grep the tail for `END DVAR DUMP` first; that is the 92% answer.

**`raw\scripts\mp\mp_spawn_fix.gsc` is Plutonium's OWN shipped fix script — do not delete it,
do not re-investigate it.** Despite the name it has nothing to do with spawn points: it (1)
detours `_class::getLoadoutItemFromDDLStats` on dedicated to clamp hacked create-a-class stat
indices to legal values, and (2) watches real humans for the god-mode class exploit / illegal
attachment combos and kicks `PATCH_BAD_STATS`. Gated on `scr_disablePlutoniumFixes`, uses
Plutonium's `replaceFunc`/`getFunction` detour API, and was materialized into
`storage\t5\raw\scripts\mp\` by the Plutonium client itself (file created 2026-06-29 02:00, a
client-update timestamp — the repo has never shipped any `scripts/` file). Under gf it is
near-inert: loadout delivery is `giveCustomLoadout` and `scr_disable_cac 1` keeps everyone off
CLASS_CUSTOM, so the exploit watcher's kick path is unreachable in normal play. Its
`Executing/Finished 'main'/'init'` console pair per round is normal. The
`'0' is not a valid value for dvar 'bg_shock_viewKickPeriod'/'FadeTime'` pairs each round are
NOT from this script (it sets no dvars) — engine/stock-cfg init noise, 4 lines/round, cosmetic,
same do-not-chase family as the weapon-data warnings in CLAUDE.md.
