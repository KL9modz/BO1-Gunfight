# gunfight.us — public website

Source for the public marketing page served by IIS on the VPS. It is a plain
static site (no build step). Claude edits the files in [`wwwroot/`](wwwroot/);
deploying is a git push + a `git pull` on the VPS.

```
site/
  wwwroot/            <- mirrored 1:1 to the VPS IIS wwwroot
    index.html        <- landing page (features, how-to-join)
    setup.html/.js    <- player setup guide (install, settings, ADS fix)
    status.html/.js   <- live "who's on now" + the 7-day public activity feed
    admin/            <- admin.html/.js — behind IIS Basic auth + the `.secured` interlock
    styles.css        <- shared by index + setup ONLY; status/admin carry inline <style>
    script.js         <- tracked placeholder, loaded by NO page (says so in its own header)
    assets/           <- screenshots, logo, favicon, flags/ (self-hosted country SVGs)
  test/               <- node:test suites for the page scripts. OUTSIDE wwwroot on purpose:
                         `deploy.ps1 -Web` /MIRrors wwwroot into IIS, so a test file under it
                         would be published. Run: node --test "site/test/**/*.test.js"
  README.md           <- this file
```

The JSON the status page reads (`status.json`, `activity.json`, and the gated
`admin.json`/`health.json`/`gamestats.json`) is **not** in this folder — `GF-StatusService` writes
it on the box. See `docs/VPS_DEPLOY.md`. `gamestats.json` (the combat leaderboard's source) is
GUID-keyed, so like the other `admin/live/` files it exists only behind the `.secured` gate.

⚠ **IIS long-caches `.css`/`.js` but not `.html`.** After editing an asset, bump the `?v=N` query on
its `<link>`/`<script>` tag, or a deploy ships new HTML against a stale cached asset — this shipped
visibly broken once at `v=4` ([[site-css-js-cache-bust-version-query]]). Current state: `styles.css`
is at `?v=6` (index + setup), `setup.js` at `?v=1`, `admin/admin.js` at `?v=1`, and **`status.js`
carries no `?v=` at all** — so an edit to it relies on the browser revalidating. Add one when you
next touch it. `status.html`/`admin.html` keep their CSS inline, so only their scripts need a bump.

This is **not** the RCON admin panel. That lives in [`../tools/rcon/`](../tools/rcon/),
is loopback-only, and is never deployed to the public site.

## Editing

Edit the files under `wwwroot/`. No framework, no bundler — just HTML/CSS/JS, so
you can open `wwwroot/index.html` straight in a browser to preview.

Never put a secret (RCON password, server keys, anything from `dedicated.cfg`)
in here — the page is world-readable. `tools/deploy.ps1 -Web` secret-scans the
folder and **refuses to publish** if it finds one.

## Deploying

```powershell
# Laptop — push the change
.\tools\push_all.ps1 "web: <what changed>"

# VPS (RDP) — pull and publish (no server restart; static content)
cd C:\gfdeploy\BO1-Gunfight
git pull
.\tools\deploy.ps1 -Web
```

Preview what would change first with `.\tools\deploy.ps1 -Web -DryRun`.
(The leading `.\` is required by Windows PowerShell.)

## web.config ownership

The live `web.config` on the VPS carries the hardened IIS config (HTTP→HTTPS
301 redirect, HSTS, security headers — see `docs/VPS_HARDENING.md`). It is **owned by
the VPS** and is intentionally *not* tracked here.

`deploy.ps1 -Web` detects this: because there is no `wwwroot/web.config` in the
repo, it passes `/XF web.config` to robocopy so the `/MIR` mirror never deletes
or overwrites the live hardened copy.

If you ever want the security config under version control, copy the live
`web.config` into `wwwroot/web.config`, commit it, and from then on it becomes
the source of truth (deploy.ps1 will start mirroring it). Until then, leave it
VPS-owned.
