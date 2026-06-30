<div align="center">

<!-- Banner image goes here once ready: docs/images/banner.png
![Black Ops Gunfight](docs/images/banner.png) -->

# Black Ops Gunfight

**Black Ops Gunfight** brings the authentic **Gunfight** game mode to **Call of Duty: Black Ops 1** on **Plutonium T5** for PC. Two teams face off using a **shared loadout** that **rotates every other round**. **No health regeneration, no custom loadouts, no killstreaks.** If time expires, capture the **overtime flag** to secure the round. Otherwise, the team with the **most remaining health** wins the round. The first team to win **6 rounds** wins the match.

Made by **KL9**. Join us on **[Discord](https://discord.gg/blackops)**.

![Version](https://img.shields.io/badge/version-0.5.2-ff7a1a)
[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?logo=discord&logoColor=white)](https://discord.gg/blackops)
[![Website](https://img.shields.io/badge/web-gunfight.us-2ea44f)](https://gunfight.us)

[Play](#-quick-start) · [Features](#features) · [Setup guide](docs/SETUP.md) · [Discord](https://discord.gg/blackops) · [Download](https://github.com/KL9modz/BO1-Gunfight/releases)

</div>

---

## Features

- **Fully custom HUD** — a built-from-scratch heads-up display showing live health for both teams, plus a full loadout preview at the start of every round.
- **Custom overtime flag** — a hold-to-capture objective that spawns in the center of the map at the end of a round for either team to take.
- **Health-based round logic** — if both teams survive and neither captures the overtime flag, the round is decided on time expiry by **total remaining health**. Equal health is a draw.
- **Per-map spawn & overtime points** — hand-placed spawn and overtime-flag locations for each map.
- **Map-size scaling** — smaller wager-style map sizes for **3v3 and under**, larger full-map sizes for **4v4 and up**.
- **Loadout system & camos** — a shared, shuffle-without-repeat loadout pool with randomized weapon camos.
- **Damage-based scoring** — each player's score value is the total damage they've dealt.
- **Full bot support** — bots are fully supported.

**Adjustable (server-side):**
- Loadout rotation and side switching — every **2 rounds** by default.
- Round timer, overtime timer, and capture time.

Full reference for every system and tunable → **[docs/REFERENCE.md](docs/REFERENCE.md)**.

---

## Documentation

| Doc | What's in it |
|---|---|
| **[docs/SETUP.md](docs/SETUP.md)** | Install Black Ops 1 + Plutonium, join the server (the mod auto-downloads), recommended graphics/FOV/ADS settings, and the manual-install fallback. |
| **[docs/REFERENCE.md](docs/REFERENCE.md)** | The full technical reference — every gameplay function, every dvar/variable, and how each system works. |
| **[docs/DEV.md](docs/DEV.md)** | For contributors — building `mod.ff`, the RCON tools, bots, debug tooling, and the branch/release model. |
| Self-hosting | Running your own server: **[VPS_DEPLOY.md](VPS_DEPLOY.md)** + **[VPS_HARDENING.md](VPS_HARDENING.md)**. |

---

## 🎮 Quick start

You need a legitimate copy of **Black Ops 1** and the **Plutonium** launcher — that's it. The mod **downloads automatically** when you connect.

1. **Install Plutonium** and Black Ops 1 — see the [official guide](https://plutonium.pw/docs/getting-started/).
2. **Launch & join:** start BO1 multiplayer through Plutonium → open the **Server Browser** → join **`Gunfight`**. Plutonium pulls the mod from the server (FastDL) on connect — no manual install.

> T5 has no direct IP connect — find the server in the in-game **browser** by its name. Keep your **Plutonium launcher updated** so its build matches the server's (FastDL ships the mod, not the engine). Prefer a manual install? The [Setup guide](docs/SETUP.md) covers the fallback.

Full walkthrough with graphics and aim tips → **[docs/SETUP.md](docs/SETUP.md)**.

---

## For developers

The repo root **is** the mod folder — it lives at `%LOCALAPPDATA%\Plutonium\storage\t5\mods\mp_gunfight\`.

```
mp_gunfight/  (GitHub: KL9modz/BO1-Gunfight)
  maps/mp/gametypes/
    gf.gsc              entry point: main(), callbacks, precache, spawn pipeline
    _gf_rounds.gsc      round lifecycle, overtime, damage/score, team-size mode
    _gf_loadouts.gsc    loadout pool, shuffle, give, camo randomizer
    _gf_hud.gsc         health panel + loadout overview + score popup (menu-driven)
    _gf_locations.gsc   per-map curated spawns + overtime flag points
    _gf_wager_zones.gsc wager compass material + map-specific zone helpers
    _gf_debug/_gf_bridge/_bot.gsc   (dev-only; stripped from public release)
  ui_mp/                menu-layer HUD (hud_gf.txt + hud_gf_health.menu)
  localizedstrings/     localized UI strings (gf.str)
  mp/gametypesTable.csv registers the 'gf' gametype in the UI
  site/wwwroot/         public website source (gunfight.us)
  tools/                build + packaging + deploy + RCON tooling
  docs/                 this documentation set
```

- **Build `mod.ff`:** `.\tools\build_ff.ps1` (see [docs/DEV.md](docs/DEV.md) for the full pipeline).
- **Load in-game:** `loadMod mp_gunfight` in the Plutonium console, then `map_restart`. The folder **must** be prefixed `mp_` to appear in the in-game Mods menu.
- **Full technical reference:** [docs/REFERENCE.md](docs/REFERENCE.md) · **contributor guide:** [docs/DEV.md](docs/DEV.md).

> A fresh `git clone` lands on the **`release`** branch (the minimal public snapshot). Run `git checkout main` for the full source + tooling.

---

## Self-hosting

Want to run your own Black Ops Gunfight server? The full runbook is in **[VPS_DEPLOY.md](VPS_DEPLOY.md)** (setup, launch, firewall, distribution) and **[VPS_HARDENING.md](VPS_HARDENING.md)** (security). Note that, because clients must install the mod manually, a public server also needs to hand players the matching mod package.

---

## Links

- 💬 **Discord:** https://discord.gg/blackops
- 🌐 **Website:** https://gunfight.us
- 📦 **Releases:** https://github.com/KL9modz/BO1-Gunfight/releases
- 🛠 **Source:** https://github.com/KL9modz/BO1-Gunfight

<sub>Black Ops Gunfight is a fan-made, non-commercial game mode. Not affiliated with or endorsed by Activision or Treyarch. Requires a legitimate copy of Call of Duty: Black Ops and the Plutonium client.</sub>
