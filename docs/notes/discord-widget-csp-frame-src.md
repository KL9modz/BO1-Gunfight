---
name: discord-widget-csp-frame-src
description: "gunfight.us status.html embeds Discord's official server-widget iframe; it renders BLANK on live until the VPS-owned web.config CSP gains frame-src https://discord.com — deploy.ps1 -Web never touches web.config"
metadata: 
  node_type: memory
  type: project
  originSessionId: 9d7c47dd-470c-447c-bcc5-5e8cf43560ae
---

The Live Status page (`site/wwwroot/status.html`) embeds Discord's official server-widget iframe:
`https://discord.com/widget?id=1130709585284583496&theme=dark` (server "Black Ops Gunfight"; the
canonical invite is **`discord.gg/blackops`** — see [[discord-invite-canonical-blackops]] — used across
index.html + setup.html). Chosen 2026-07-03 over a custom fetch-based widget (user picked the
official iframe). It first went on index.html's Community section, then the user moved it to
status.html; index.html + setup.html are back to pure-static (link fixes only).

**Deploy gotcha — two coupled steps, or the feature ships broken:**
1. `deploy.ps1 -Web` mirrors `wwwroot/` to IIS but **passes `/XF web.config`** — the live CSP is
   VPS-owned and NOT in the repo, so the HTML deploy alone does NOT relax the CSP.
2. The live CSP is `default-src 'none'` with **no `frame-src`**, so the iframe silently renders
   **blank** (no console-visible error banner; `frame-src` falls back to `default-src 'none'`).
   Fix = add `frame-src https://discord.com` to the CSP header in the VPS `web.config` by hand
   (RDP/SSH). The widget is self-contained (its scripts run in Discord's own origin inside the
   frame). Discord's widget page sends no X-Frame-Options and no restrictive CSP, so it permits
   framing; the block is purely our side.

status.html ALSO needs `script-src 'self' 'unsafe-inline'` + `connect-src 'self'` for its own live
readout (inline `<script>` + same-origin `fetch('live/status.json')`) — separate from the Discord
frame-src, and required whenever status.html ships (it's 404 on live now / untracked). So the full
status.html CSP delta = frame-src + script-src + connect-src. The documented reference CSP in
`VPS_HARDENING.md` carries the `frame-src` (source of truth), but the LIVE header must still be
edited on the box.

Related: [[gunfight-us-security-audit]].
