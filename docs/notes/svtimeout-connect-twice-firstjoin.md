---
name: svtimeout-connect-twice-firstjoin
description: "\"Must click Connect TWICE on first join — FastDL download window sticks at 100%.\" Cause = client waits for connection-close/EOF; IIS keep-alive withholds it. FIX applied 2026-07-05 = disable keep-alive (Connection: close) for /mods in the VPS web.config. ⚠ The 'sv_timeout is a red herring' verdict below was CORRECT for THIS symptom but is NOT the whole story — see the 2026-07-12 correction at the top"
metadata: 
  node_type: memory
  type: project
  originSessionId: c43d787c-994c-47a4-9143-02534dbc19aa
---

> **CORRECTION 2026-07-12 — "sv_timeout was a red herring" does NOT generalize.** It was the right
> verdict for the stick-at-100% symptom below, but for **two** reasons, and only one was understood:
> (1) the keep-alive bug still blocked the download→load handoff, so attempt 1 never reached the load
> phase and nothing *could* be timing out; and (2) **`sv_timeout` does not govern the connect/load phase
> at all — `sv_connectTimeout` does** (it was sitting at the engine default 80). So raising `sv_timeout`
> was the *wrong dvar* for this symptom regardless. `sv_timeout` governs an **already-in-game** client,
> which was never what was being tested — and at the template's **15** it was separately dropping live
> players (alt-tab out of exclusive fullscreen, and any lag spike, since the client's own `cl_timeout`
> is **40**). Both dvars have now been raised (240 / 200).
> **Do not cite this file as "sv_timeout is fine at 15."** → [[sv-timeout-and-connecttimeout-template-defaults]]

Symptom (user): on a **first** join the FastDL **download window reaches 100% then STICKS** — the
Plutonium client does NOT advance. The 30–60s engine rebuild (black screen,
[[fastdl-first-join-black-screen-rebuild]]) happens only on the **2nd, manual reconnect** (which
finds mod.ff already on disk, skips download, loads, joins). So the download completes but the
download→load handoff never fires on attempt 1.

**sv_timeout was a RED HERRING.** My first theory (sv_timeout dropping them mid-rebuild) was wrong —
the rebuild doesn't even start on attempt 1. I briefly raised `sv_timeout 15→240` then **REVERTED it
in full** (live via panel + cfg-from-backup + tracked example) at the user's request ("no sv_timeout
edit"). It's runtime-settable (not latched); apply via the panel's paced `/api/rcon`, not raw UDP
(raw races the panel poll → rate-limit-dropped).

Ruled out on the box: server advertises exactly 1 file (`found 1 files required for mod download!`,
mod.ff 17KB); mod.ff serves clean (HTTPS 200, correct Content-Length 17344, Accept-Ranges/206, no
gzip/chunk). The local console.log "found 4 files" is a LOCAL listen-server session (KL9 hosting),
NOT a VPS join — no existing client log captures the real hang, and klaze can't easily reproduce
(dev box has the mod cached; only mod-less clients hit it).

**Cause (leading, high-confidence) + FIX APPLIED 2026-07-05:** FastDL is **IIS over HTTPS with
keep-alive** (no `Connection: close`). The client gets all bytes (bar→100%) but treats connection
close / EOF as "download complete"; keep-alive holds the socket open → hangs at 100%. Community +
Plutonium staff flag HTTPS/connection-handling as THE FastDL trouble spot (plain-HTTP HFS is the
known-good server BECAUSE it closes connections). Fix = disable keep-alive for the FastDL path:
added `<location path="mods"><system.webServer><httpProtocol allowKeepAlive="false"/></system.webServer></location>`
to the VPS `C:\inetpub\wwwroot\web.config` (backup `web.config.bak-fastdl`). **Verified at HTTP
layer:** mod.ff now returns `Connection: close` + IIS closes the socket; homepage still 200; scoped
to /mods so site security untouched. IIS applies web.config live — NO restart, NO new port, NO
Contabo change. **PENDING: a fresh mod-less client must confirm one-click download→join.**

If it STILL hangs (cause isn't connection-close): plan B = plain-HTTP HFS on a separate port
(`sv_wwwBaseURL http://gunfight.us:<port>/`, needs restart + Contabo port) OR grab the CLIENT-side
console.log from a stuck attempt to pinpoint it. Revert this fix by restoring web.config.bak-fastdl.

Also done same pass: **cleaned the FastDL web root** — it was serving the whole dev GSC tree
(`gf.gsc`, `_gf_bridge.gsc`, `_bot.gsc`, `bots/`, `_gf_debug.gsc`) + logs + mod.csv at HTTP 200
(`.gsc`/`.csv` are MIME-mapped). Removed all but mod.ff. Exposed gf.gsc rcon_password is a DEV
throwaway ("NOT the VPS password"). See [[package-server-does-not-strip-markers]], [[gunfight-us-security-audit]].
