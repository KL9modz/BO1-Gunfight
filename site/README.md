# gunfight.us — public website

Source for the public marketing page served by IIS on the VPS. It is a plain
static site (no build step). Claude edits the files in [`wwwroot/`](wwwroot/);
deploying is a git push + a `git pull` on the VPS.

```
site/
  wwwroot/          <- mirrored 1:1 to the VPS IIS wwwroot
    index.html
    styles.css
    script.js
    assets/         <- screenshots / images / favicon
  README.md         <- this file
```

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
301 redirect, HSTS, security headers — see `VPS_HARDENING.md`). It is **owned by
the VPS** and is intentionally *not* tracked here.

`deploy.ps1 -Web` detects this: because there is no `wwwroot/web.config` in the
repo, it passes `/XF web.config` to robocopy so the `/MIR` mirror never deletes
or overwrites the live hardened copy.

If you ever want the security config under version control, copy the live
`web.config` into `wwwroot/web.config`, commit it, and from then on it becomes
the source of truth (deploy.ps1 will start mirroring it). Until then, leave it
VPS-owned.
