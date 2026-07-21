---
name: public-activity-feed-and-country-flags
description: "gunfight.us status page gained a 7-day public connect feed (activity.json, PII-stripped) + country flags; the RCON panel is now the box's SINGLE ip-api geo client, and emoji flags are unusable because Windows won't render them"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6fb1c266-9624-42ae-9543-aadcd07b75a9
---

Built 2026-07-11. The public status page (`site/wwwroot/status.html`) previously showed only a
15-event **in-memory** "recent activity" ring that died on every GF-StatusService restart. It now
renders a persistent, searchable **7-day** feed plus a **country flag** per player (live roster and
history).

**Data path:** `conn_logger` → `players_*.log` day-files → `status_service` parses them (the SAME
`Build-ConnHistory` that already fed the admin page) → two projections:
- `live/activity.json` — **PUBLIC**, no `.secured` gate: `date/time/event/name/session/cc` only.
  The IP is dropped on the box; **only the 2-letter country code is ever published.**
- `live/admin/admin_history.json` — private, full IP + GUID, `.secured` gate (unchanged, now also `cc`).

**Why:** see [[gf-admin-connection-history]] for the admin-side original.

## The three non-obvious things

1. **Emoji flags (🇺🇸) DO NOT RENDER ON WINDOWS.** Chrome/Edge/Firefox on Windows fall back to the
   bare letter pair ("US") — no regional-indicator glyphs in the system fonts. That's most of the
   player base, so emoji were never an option. Flags are **self-hosted SVGs** vendored from
   `HatScripts/circle-flags` (MIT) into `site/wwwroot/assets/flags/` — 246 files, ~235 KB total
   (avg 700 B). `flag-icons` was rejected: 2 MB with a pathological tail (Serbia 180 KB, Spain 89 KB).
   Self-hosting also keeps the live CSP's `img-src 'self' data:` intact — **no `web.config` edit**,
   which matters because `deploy.ps1 -Web` excludes web.config (it must be hand-edited on the box).
   `xx.svg` is the neutral placeholder; an unresolved country renders an empty same-width span so the
   name column still lines up.

2. **The panel is the box's ONE geo client** — the panel-first rule now covers geo, not just RCON.
   ip-api.com free is **45 req/min per SOURCE IP** and hard-limits, so N independent clients on the box
   burn one shared budget re-resolving the same IPs. `tools/rcon/server.js` owns it: disk-cached
   (`.geocache.json`, gitignored — it maps real player IPs to locations, so it never enters git or a
   web root), paced at `GEO_MIN_GAP` 1.5s, in-flight deduped, 30-day TTL for hits but only **30 min for
   failures** (a transient rate-limit must not blank a flag for a month). Two modes:
   - `?ip=` **blocking** — the panel UI's "Locate" (an admin is watching a spinner).
   - `?ips=a,b,c` **NON-blocking** — status_service. Returns only what's cached and warms the rest in
     the background. **This must never block:** blocking would stall the public status snapshot behind
     a rate-paced queue. A cold IP just means "no flag for a poll or two".

   `tools/notify/join-notify.{js,ps1}` still has its own independent ip-api client (process-lifetime
   cache, no `countryCode`). Harmless today (it caches), but it's the one remaining second client —
   fold it into the panel endpoint if geo ever gets rate-limited.

3. **The public feed inherits conn_logger's dependency chain.** No `.secured` marker → no `admin.json`
   → conn_logger writes no day-files → `activity.json` is empty. `status.js` falls back to the live
   in-memory `recent` ring so the page degrades instead of going blank.

## Deploy

Needs **both** `deploy.ps1 -Mod` (ships `tools/` = new `server.js` + `status_service.ps1`, and restarts
the panel + box services) **and** `deploy.ps1 -Web` (ships `site/wwwroot` = status page + 246 flags).
The panel must actually restart to pick up the geo code — a running panel serving the OLD code answers
`?ips=` with `{"ok":false,"error":"Bad IP"}` (it falls through to the single-IP branch). That's the
tell if flags stay blank after a deploy.

Front-end gotcha: the activity feed lives in its own `#activity` container, NOT `#content` — the 5s
status refresh wipes `#content`, which would clear the search box and steal focus mid-type (the same
reason the admin page splits its history out).
