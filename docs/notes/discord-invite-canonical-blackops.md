---
name: discord-invite-canonical-blackops
description: Every Discord invite in the repo MUST be https://discord.gg/blackops; the public website drifted to a raw invite code and shipped a dead link. Root cause = URL hardcoded/duplicated with no single source of truth + the site deploys via a separate path. Now guarded by the pre-commit hook.
metadata: 
  node_type: memory
  type: project
  originSessionId: e69af543-09ec-4f96-9760-3cc672e14ae1
---

**Hard rule:** every Discord link anywhere in the repo is the vanity invite
`https://discord.gg/blackops`. Raw/temporary invite codes (e.g. a bare `discord.gg/<code>`)
expire — never use one.

**The incident (2026-07-10):** the live website (`site/wwwroot/index.html` ×2,
`setup.html` ×3) still linked a raw `discord.gg/<code>` invite while README, `docs/`, and the
in-game HUD (`ui_mp/hud_gf_health.menu`) all used `discord.gg/blackops`. The Discord
button on gunfight.us was a dead invite.

**Why it happened:** the invite URL is **hardcoded/duplicated across ~10 spots with no
single source of truth**. When the vanity `blackops` invite was adopted, the docs/HUD
were updated but the 5 website copies were missed — and the **website deploys on its own
path** (`deploy.ps1 -Web` robocopies `site/wwwroot` → IIS), independent of the mod
build/deploy, so the drift was never surfaced by any mod-side check.

**How it can't happen again:** `tools/hooks/pre-commit` now blocks staging any
`discord.gg/<code>` that isn't `discord.gg/blackops` (section 3, alongside the secret
guard). Hook is opt-in per clone: `git config core.hooksPath tools/hooks`.

**Deploy note:** fixing the working tree does NOT fix the live site — the corrected
`site/wwwroot` must be pushed live via `deploy.ps1 -Web` **on the VPS** (see
[[modff-drift-vs-gsc-deploy]] for the analogous "committed ≠ live" trap on the mod side).
The `status.html` Discord *widget* iframe keys off the server ID (1130709585284583496),
not an invite code — unaffected ([[discord-widget-csp-frame-src]]).
