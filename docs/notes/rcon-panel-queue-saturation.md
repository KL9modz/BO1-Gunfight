---
name: rcon-panel-queue-saturation
description: Why RCON panel commands took MINUTES on the VPS (2026-07-03) — panel tick oversubscription + 4 competing box-side rcon senders; fixed with /api/tick + coalescing + panel-first services; rules to not regress
metadata: 
  node_type: memory
  type: project
  originSessionId: b8c631f8-3308-42af-95de-d994dacab8a2
---

**Symptom (2026-07-03):** connected to the VPS, panel commands took minutes; right-click player
moves timed out; map restart / bots / map switch delayed or seemingly dropped. Game server itself
was HEALTHY (direct UDP probe: ~60ms replies, 5/5) — the delay was entirely client/queue-side.

**Root cause 1 — panel self-saturation (the "minutes"):** each background rcon read holds the
panel's serialized send lane ~1.25s (850ms `RCON_MIN_GAP` + ~350ms reply collect). Old UI enqueued
3 reads per cycle (status @3s + gf_state + gf_roster @2.5s) ≈ 1.4× drain capacity → unbounded queue
growth on a dedicated server. `setInterval` async tickers STACK (they fire regardless of whether the
previous fetch resolved). Hanging fetches then exhausted the browser's **6-per-origin connection
pool**, so even server-side PRIORITY-lane clicks waited minutes in the *browser* — the priority
scheduler can't reorder what never reaches it. A **listen server masked everything** (scoreTick
early-returned on `_listenServer`; gf_* telemetry reads only reply on dedicated), so local testing
looked fine.

**Root cause 2 — competing senders:** the VPS box also ran status_service (2 raw rcon sends / 5s),
join-notify (TWICE — a duplicate "GF Join Notifier" task shadowed the canonical GF-JoinNotify;
removed), and conn_logger (1 / 15s). Plutonium answers ~1 rcon reply per 0.7s and SILENTLY DROPS
faster arrivals — unsynchronized senders eat each other's replies; each eaten panel reply = a 3s
timeout stall of the whole lane.

**Fix (deployed live via scp + task restarts 2026-07-03; user confirmed working; committed
c12a816 and shipped in release 0.6.0 on 2026-07-04):**
- server.js: `/api/tick` = `status;gf_state;gf_roster` chained into ONE rcon send; `_rconEnqueue`
  gained a coalesce `key` (identical queued reads share one send; keys on tick/status/gfstate/
  gfroster/ack).
- index.html: ONE self-scheduling `pollTick` loop (next cycle armed only after the previous
  resolves — can never stack) replaces the autoTick/scoreTick setIntervals. Steady state ≈ 35% of
  lane capacity.
- status_service / join-notify / conn_logger: **panel-first** — read via the panel's
  `/api/tick`//`/api/status` on 127.0.0.1:3000 (sharing/coalescing with the panel's own queue),
  direct rcon only as fallback when the panel is down.

**UPDATE 2026-07-05 — conn_logger no longer rcon-polls at all** (further reduced box-side rcon by
one reader). It now diffs `status_service`'s `admin.json` FILE (the auth-gated admin snapshot, which
carries per-player IP + GUID), so status_service is the SINGLE box-side rcon reader for both the
public/admin snapshot AND the persistent IP connect log. conn_logger inherits the 5s cadence (was
15s). Missing/stale(>30s)/offline admin.json → conn_logger skips that tick (never a mass-LEFT). See
[[gf-admin-connection-history]] for the full data flow + the ip:port human-filter added the same day.

**Rules to not regress:** (1) never add another direct rcon poller on the box — go through the
panel API so ONE process owns pacing; (2) never poll from a browser with a bare `setInterval(fetch)`
— self-schedule after resolve; (3) each browser-side poll cycle = at most ONE rcon send (chain
commands with `;`, parse the combined reply); (4) test panel changes against a DEDICATED server —
listen hides the whole failure class. Panel debug: `GF_RCON_DEBUG=1` env logs read timings.

Related: [[rcon-tool-vps-connect-23char-cap]] (the other silent-rcon failure mode + an earlier
duplicate-process incident on this box — duplicates recur here, check scheduled tasks),
[[rcon-dedicated-dvar-push-limits]].
