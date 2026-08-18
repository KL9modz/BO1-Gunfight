# A Claude RC restart orphans every open session ("Environment deleted")

**Date:** 2026-08-18 **Status:** understood; watched by `watchdog.ps1` check 1d since this incident.

## Symptom

The `gf-vps` session in the Claude app would not open. The card showed **`Environment deleted`** with the
last message still readable, and a *second* `gf-vps` card underneath it read `Connected`. Nothing was
wrong with the box: the game server, the panel and every `GF-*` service were healthy throughout.

## What actually happened

`GF-ClaudeRC` runs **`claude rc --name gf-vps`**, a server process. **Each session is a CHILD PROCESS of
that server** (`claude.exe --print --sdk-url …/code/sessions/cse_… --resume=…`) and exists only inside
it. There is no server-side snapshot to reattach to, so when the parent dies the session cannot be
resumed by anyone — the app has nothing to offer but the history and that badge.

Timeline, reconstructed from process start times and the transcript:

| Evidence | Reading |
|---|---|
| `0206234e-….jsonl` last write 11:43 | when the session went IDLE, not when it died |
| RC server pid 7360 `CreationDate` 12:10:00, parent `svchost.exe` (pid 1844, `-k netsvcs … Schedule`) | the task's own repetition relaunched it here, so the old server died shortly before |
| `LastTaskResult 0x800710E0` at 12:25 | **normal, not an error**: `MultipleInstances = IgnoreNew` refusing to start a second instance because one is already running |

⚠ **Do not read `LastRunTime` as "when it restarted".** With a repeating trigger and `IgnoreNew`, the task
fires on cadence forever and *most of those firings are refused*. The restart is the **process creation
time**, and only that.

⚠ **Do not read a transcript's last-write time as the death time** either. It marks the last turn, not the
process. The two are unrelated, and conflating them makes the outage look ~25 min longer than it was.

## Why it was invisible

The recovery is automatic and silent: the task's repetition relaunches the server, so the box self-heals
and **the only evidence a user ever sees is a session that will not open** — at which point the cause
(a process restarted minutes ago) is indistinguishable from an app bug, an auth problem, or a network
fault. Nothing logged it, because `GF-ClaudeRC` is the one service NOT routed through the
`run_service.ps1` flight recorder.

## Why it can never BE routed through the flight recorder

The obvious fix — wrap it like every other service so its death lands in
`storage\t5\logs\services\` — is **wrong and would break Remote Control**: that wrapper makes its target a
child of `powershell.exe`, and **the RC server's parent must be `svchost.exe`** (Task Scheduler). The
flight recorder would destroy the thing it was added to watch. `watchdog.ps1` **check 1d** is the
substitute, which is why the check lives in the watchdog rather than in a new always-on service.

## What check 1d does

Alerts (ntfy + Discord, the standard path) on the three states task-state checking is blind to:

1. **restart** — the orphaning event, detected by a persisted `pid|CreationDate` signature in
   `watchdog_state.json`. Reported even though nothing is "down": the server is healthy, the SESSIONS
   are what was lost, and only this transition reveals it.
2. **two servers** — Claude refuses an ambiguous name, so a duplicate is a total ops outage while both
   processes look perfectly healthy. Deliberately **not** auto-killed: one of them may hold a live
   session.
3. **non-`svchost` parent** — hand-started, so it dies with that console.

A genuinely absent server is Stop/Start-restarted, bounding an outage at the 3-min watchdog cadence
instead of the RC task's own 5-min poll.

⚠ **The load-bearing rule: never act on absent EVIDENCE.** Remediation here Stop/Starts `GF-ClaudeRC`,
which ends **every live session on the box, including the operator's own**. So a failed process query, or
`claude.exe` processes whose command lines cannot be read (a privilege drop blanks them and they match
nothing), degrade to *no judgement* — never to "the server is gone". A missed check costs one quiet 3-min
tick; a false positive costs exactly what the check exists to protect. Pinned by a Pester guard in
`tools/tests/service_functions.Tests.ps1` that asserts the query-failed branch comes FIRST in the chain.

Related: [[vps-status-log-notify-services]] (the flight recorder this one cannot use),
[[vps-game-server-runs-as-system-localappdata-pinned]] (the other "the task's State is not the truth"
case).
