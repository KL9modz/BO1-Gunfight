<div align="center">

<!-- Banner image goes here once ready: docs/images/banner.png
![Black Ops Gunfight](docs/images/banner.png) -->

# Black Ops Gunfight

**Round-based, one-life Gunfight for Call of Duty: Black Ops 1 — on Plutonium T5.**

One life per round. A shared random loadout every round. No killstreaks, no health regen, no second chances — just the gunfight.

![Version](https://img.shields.io/badge/version-0.5.2-ff7a1a)
[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?logo=discord&logoColor=white)](https://discord.gg/blackops)
[![Website](https://img.shields.io/badge/web-gunfight.us-2ea44f)](https://gunfight.us)

[Play](#-quick-start) · [How it plays](docs/GAMEPLAY.md) · [Setup guide](docs/SETUP.md) · [Discord](https://discord.gg/blackops) · [Download](https://github.com/KL9modz/BO1-Gunfight/releases)

</div>

---

## About

**Black Ops Gunfight** is a custom multiplayer game mode for **Call of Duty: Black Ops 1**, running on the **Plutonium T5** client. It strips multiplayer down to its core: two teams, **one life each per round**, and the **same randomized loadout** for everyone — so rounds are won by gunskill and positioning, not classes or streaks. First team to **6 rounds** wins.

Made by **KL9**. Come play and talk shop on **[Discord](https://discord.gg/blackops)**.

> **Heads-up for players:** Plutonium has **no automatic mod download**. Everyone — players *and* the server — installs the mod locally and must run the **same version**. It's a one-minute setup → **[Setup guide](docs/SETUP.md)**.

---

## Documentation

| Doc | What's in it |
|---|---|
| **[docs/SETUP.md](docs/SETUP.md)** | Install Black Ops 1 + Plutonium, install the mod, recommended graphics/FOV/ADS settings, and how to connect. |
| **[docs/GAMEPLAY.md](docs/GAMEPLAY.md)** | The rules and everything that *defines* Gunfight — rounds, win conditions, loadouts, overtime, team-size modes. |
| **[docs/REFERENCE.md](docs/REFERENCE.md)** | The full technical reference — every gameplay function, every dvar/variable, and how each system works. |
| **[docs/DEV.md](docs/DEV.md)** | For contributors — building `mod.ff`, the RCON tools, bots, debug tooling, and the branch/release model. |
| Self-hosting | Running your own server: **[VPS_DEPLOY.md](VPS_DEPLOY.md)** + **[VPS_HARDENING.md](VPS_HARDENING.md)**. |

---

## 🎮 Quick start

You need a legitimate copy of **Black Ops 1** and the **Plutonium** launcher.

1. **Install Plutonium** and Black Ops 1 — see the [official guide](https://plutonium.pw/docs/getting-started/).
2. **Download the mod** from [Releases](https://github.com/KL9modz/BO1-Gunfight/releases).
3. **Extract it** so the folder lands at:
   ```
   %LOCALAPPDATA%\Plutonium\storage\t5\mods\mp_gunfight
   ```
   (the folder must stay named `mp_gunfight`).
4. **Load & join:** launch BO1 multiplayer → **Mods** menu → load **mp_gunfight** → **Server Browser** → join **`Gunfight`**.

> T5 has no direct IP connect — find the server in the in-game **browser** by its name. Your installed version must **match the server's**, or the gametype/HUD won't load.

Full walkthrough with graphics and aim tips → **[docs/SETUP.md](docs/SETUP.md)**.

---

## How it plays

- **One life per round** — no respawns. Wipe the enemy team to take the round.
- **Shared random loadout** — both teams get the same primary, secondary, lethal, and tactical each round; the loadout rerolls every couple of rounds.
- **First to 6 rounds** wins the match; sides switch partway through. Draw rounds don't count toward the limit.
- **Beat the clock** — if the round timer expires, the team with more total health wins. A tie triggers **overtime**: a hold-to-capture zone (or HP if no capture) decides it.
- **No killstreaks, no health regen, no weapon drops, no perks shown pre-round.**
- **Auto map scaling** — small lobbies get tight, curated spawns; 4v4+ opens the whole map.

The complete ruleset → **[docs/GAMEPLAY.md](docs/GAMEPLAY.md)**.

---

## Systems at a glance

Black Ops Gunfight is built on the stock T5 Search & Destroy framework with custom systems layered on top. Each is documented in **[docs/REFERENCE.md](docs/REFERENCE.md)**:

- **Round lifecycle & win conditions** — one-life rounds, last-team-standing, timer-expiry-by-HP, 6-round match, side switching, draw handling.
- **Custom round clock** — a mod-owned timer that replaces the stock final-30s sequence with a `timesup` callout + final-10s countdown beeps.
- **Overtime & capture zone** — a pausable overtime clock plus a hold-to-capture zone with team-relative icons and an absolute-color ground FX ring.
- **Team-size mode (large/small)** — auto-selects curated wager-style spawns for small lobbies or the full map for 4v4+, each with its own tunable dvars.
- **Loadout system & camos** — a shared, shuffle-without-repeat loadout pool with randomized weapon camos.
- **Menu-driven HUD** — health panel, loadout overview, self bar, and kill popup, rendered via the menu layer to dodge the engine's per-client hudelem render cap.
- **Curated spawns & wager zones** — per-map spawn/overtime points, and reuse of the stock wager play spaces (kept via the `_gameobjects` allow-list) without enabling the wager framework.

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
