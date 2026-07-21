---
name: getting-started-cb-servers-install-path
description: Getting Started now routes ALL game install through the CB Servers Launcher (one app = game + Plutonium client); dropped the Steam+Plutonium manual steps and the Discord-zip download. Why + the unverified server-browser caveat.
metadata: 
  node_type: memory
  type: project
  originSessionId: a15b90d7-6225-4d70-93d6-ddc5b125d392
---

As of 2026-07-10 the player-facing install flow recommends the **CB Servers Launcher**
([docs.cbservers.xyz/games/t5](https://docs.cbservers.xyz/games/t5); open-source `cb-launcher.exe` at
github.com/CBServers/cb-launcher) as the **single** way to get set up: one app downloads Black Ops 1
*and* runs it on the Plutonium client, so there is no separate `plutonium.exe` step. A free Plutonium
account (forum.plutonium.pw/register) is still required — CB can't do that part.

**Why:** the old flow offered "get the game from Steam or our Discord (zip)" plus a manual plutonium.exe
setup. The Discord-zip download was sketchy and the two-step install was friction. The user chose to
**lead with CB Servers**, then — once confirmed CB bundles Plutonium — to **scratch the Steam+Plutonium
manual blurbs entirely**. CB is now the only documented path. Steam owners are still served silently:
CB's SETUP has an "existing install → VERIFY" option (no ~large re-download).

**How to apply:** touched `docs/GETTING_STARTED.md`, `site/wwwroot/setup.html`, `site/wwwroot/index.html`,
`README.md`. Discord stays ONLY as a community/support link, never a download source (keep it
discord.gg/blackops per [[discord-invite-canonical-blackops]]). If a manual Plutonium path is ever
re-added, put it back as a *secondary* subsection — don't demote CB as the lead.

**⚠ Unverified caveat:** CB's docs never explicitly confirm the launcher's in-game server browser is the
*full* Plutonium master list (vs. CB-only). It almost certainly is — CB's T5 IS the Plutonium client
(their manual method is literally plain `plutonium.exe`) and Plutonium T5 has one master server list, so
gunfight.us shows. The docs were written so the join flow does NOT *depend* on the CB launcher (players
end up on Plutonium either way). If a player ever reports not seeing gunfight.us via CB, verify this first.

**Not live until deployed:** site changes reach gunfight.us only via `deploy.ps1 -Web` on the VPS (same
gotcha as [[discord-invite-canonical-blackops]]); docs/README are just in-repo.
