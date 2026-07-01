# Black Ops Gunfight - Getting Started

Everything a new player needs: install Plutonium and Black Ops 1, dial in the recommended settings, fix the aim-down-sights bug, and join the Gunfight server. *Part of the [Black Ops Gunfight](../README.md) documentation.*

> Platform: **PC only.** Black Ops Gunfight runs on the [Plutonium](https://plutonium.pw/) T5 client for Call of Duty: Black Ops 1. You need a copy of the game (Steam, or from our [Discord](https://discord.gg/blackops)).

## Contents
- [1. Install Plutonium & Black Ops 1](#1-install-plutonium--black-ops-1)
- [2. Recommended settings](#2-recommended-settings)
- [3. Fix aim-down-sights (the sprint bug)](#3-fix-aim-down-sights-the-sprint-bug)
- [4. Find & join Gunfight](#4-find--join-gunfight)
- [5. Troubleshooting](#5-troubleshooting)

---

## 1. Install Plutonium & Black Ops 1

Plutonium is a free community client that runs Black Ops 1 online. Full official walkthrough: **[plutonium.pw/docs/install](https://plutonium.pw/docs/install/#t5-black-ops-1)**.

1. **Download the launcher.** Get `plutonium.exe` from **[plutonium.pw](https://plutonium.pw/)**. You can save it anywhere convenient - your Desktop or the game folder both work.
2. **Run it.** If Windows SmartScreen shows *"Windows protected your PC"*, click **More info -> Run anyway**. The launcher then installs its client files.
3. **Log in.** Sign in with your Plutonium forum account. Don't have one? Create a free account at **[forum.plutonium.pw/register](https://forum.plutonium.pw/register)**, then log in.
4. **Point it at Black Ops.** Select the **Black Ops** tab, click **SETUP**, and choose your Black Ops game folder. A Steam copy is usually at:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops
   ```
   (In Steam: right-click the game -> **Manage -> Browse local files**.) If you got the game from our Discord, select the unzipped Black Ops folder instead.
5. **Launch.** Press **PLAY**. That's it - you're in.

> **Re-selecting the folder later:** use **Game Settings** (next to the **PLAY** button), not SETUP.
>
> **"Invalid Game Path" error?** The folder you picked isn't a valid Black Ops install (wrong folder, or missing/renamed game files). Re-select the correct `Call of Duty Black Ops` folder via **Game Settings**.

<!-- image slot: docs/images/getting-started/01-launcher-setup.png (Plutonium launcher: Black Ops tab -> SETUP -> folder picker) -->

---

## 2. Recommended settings

Black Ops is old, but it hasn't been optimised for modern hardware - so a few tweaks make it look sharp and play fast. Set these from the in-game **Options** menu. Every setting below also has a **console command** (see [How to open the console](#how-to-open-the-console)) if you'd rather paste them.

### Graphics

| Setting | Recommended | Console command |
|---|---|---|
| Video mode (resolution) | Highest your display supports (e.g. `2560x1440` for 1440p) | *(menu - Video Mode)* |
| Aspect ratio | Auto | *(menu)* |
| Screen refresh rate | Highest (e.g. 144 / 240) | *(menu - Refresh Rate)* |
| Fullscreen | Yes | `r_fullscreen 1` |
| No border (borderless) | Yes | *(Plutonium menu / launcher)* |
| Sync every frame (V-Sync) | **No** (unless you have no G-Sync/FreeSync) | `r_vsync 0` |
| Anti-Aliasing | 8x | `r_aasamples 8` |
| Anisotropic filtering | 16 (max) | `r_texFilterAnisoMin 16` |
| Texture filtering | Trilinear | `r_texFilterMipMode "Force Trilinear"` |
| Texture quality | Extra | `r_picmip 0` |
| Shader warming | Yes | `r_shaderWarming 1` |
| Shadows | Yes | `sm_enable 1` |
| Bullet impacts | Yes | `fx_marks 1` |
| Field of view | Wide - raise to taste (~80+) | `cg_fov_default 80` |
| Brightness | Not too high (~1.05) | `r_gamma 1.05` |

> **Field of view - go wide.** Two settings stack: **Field of view** (Graphics) sets the base, and **FOV scale** (Game tab) multiplies it - raise both to taste, higher = more peripheral vision. A base around **78-80** with **FOV scale ~1.05** gives a modern, wide view (the number shown climbs into the high-80s once the scale is applied). Console: `cg_fov_default 80` for the base - some Plutonium builds allow up to ~90; FOV scale is set from the in-game **Game** tab.
>
> **Applying video dvars from console:** resolution, fullscreen, anti-aliasing, aniso, and texture quality need a **`vid_restart`** (or the menu's **Apply** button) to take effect. FOV, brightness, HUD, shadows, and bullet impacts apply live.

![Recommended in-game Graphics settings](images/getting-started/graphics.png)
*In-game Graphics settings - Settings -> Graphics.*

### Game

| Setting | Recommended | Console command |
|---|---|---|
| Draw HUD | Yes | `hud_enable 1` |
| FOV scale | ~1.05 (wider still) | *(Plutonium menu / launcher)* |
| Max FPS | Match or just under your refresh (e.g. 237 for a 240 Hz display), or uncapped | `com_maxfps 237` *(`0` = unlimited)* |
| Reduce engine sleeps | Yes (smoother frametimes) | *(Plutonium menu / launcher)* |

![Recommended in-game Game settings](images/getting-started/game-settings.png)
*Game settings - Settings -> Game.*

### Multiplayer

| Setting | Recommended | Console command |
|---|---|---|
| Allow downloading | Yes *(needed to auto-download the mod)* | `cl_allowdownload 1` |
| Disable emblems | No | *(menu)* |

> **Allow downloading must be on.** It lets Plutonium fetch the Gunfight mod from the server automatically when you join (FastDL) - no manual install. If you ever see a `cl_allowdownload disabled` error, open the console and run `cl_allowdownload 1`.

### Controller

- **Controls -> Gamepad -> Yes** to enable controller support.
- If the game still doesn't see your controller, use **[DS4Windows](https://ds4-windows.com/)** to present it as an Xbox controller.

### How to open the console

Press the **`~`** key (tilde / grave, top-left under **Esc**) to open the Plutonium console. If nothing happens, enable the console in the Plutonium launcher/in-game options first, then press `~` again. Type a command and hit **Enter**.

To make settings stick, you can also paste the console lines into a config file at
`%localappdata%\Plutonium\storage\t5\players\autoexec.cfg`
and run `exec autoexec` in the console once per session (Plutonium does not auto-run it).

---

## 3. Fix aim-down-sights (the sprint bug)

Black Ops 1 has a long-standing quirk: **you can't aim down sights while the Sprint key (Shift) is held.** Normally you have to fully release Shift before you can aim - which loses gunfights. One console command fixes it.

Open the console (**`~`**) and paste:

```
bind MOUSE2 "+speed_throw; -breath_sprint; -sprint"
```

Now you can **ADS without releasing Sprint.** What it does: aiming (`+speed_throw`) also clears the sprint input (`-breath_sprint`) so the engine stops blocking your aim. The trailing `-sprint` is a required no-op - it absorbs the key event so the sprint release actually fires. (Drop it and the two-token version silently fails.)

**Good to know:**
- This forces **Hold-ADS** (not toggle) - hold right-click to aim, regardless of your toggle-ADS menu setting.
- Tapping Shift *while already aiming* will drop you out of ADS. Minor, and a fair trade for being able to aim out of a sprint.
- The game sometimes strips custom `MOUSE2` binds on restart. If ADS goes dead, just **re-paste the line**. Keeping it in `autoexec.cfg` (above) and running `exec autoexec` re-applies it in one step.
- It's a **client-side keybind** - each player sets it on their own machine; it can't be pushed by the server.

---

## 4. Find & join Gunfight

Black Ops 1 has **no direct IP connect** - you join through the in-game **Server Browser** (it uses Plutonium's backend session IDs, not IPs).

1. Launch the game via the Plutonium launcher (**PLAY**) and reach the multiplayer main menu.
2. Open the **Server Browser**.
3. **Reset the filters** and click **Refresh** so every server shows (modded servers are hidden by default filters).
4. On the **Ranked** tab, find **`Gunfight | gunfight.us`** (mode **GF**) and join. The mod **downloads automatically** on connect (FastDL) - no manual install needed.

> Keep your **Plutonium launcher updated** so its build matches the server's - FastDL ships the *mod*, not the engine build. More at **[gunfight.us](https://gunfight.us)** and our **[Discord](https://discord.gg/blackops)**.

![The Server Browser - Gunfight | gunfight.us in the Ranked tab](images/getting-started/server-browser.png)
*The Server Browser - look for `Gunfight | gunfight.us` (mode GF) on the Ranked tab.*

---

## 5. Troubleshooting

| Problem | Fix |
|---|---|
| **Can't aim down sights** while holding Sprint | Paste the ADS bind from [section 3](#3-fix-aim-down-sights-the-sprint-bug). |
| **ADS stopped working** after a restart | Re-paste the `bind MOUSE2 ...` line, or run `exec autoexec`. |
| **"Invalid Game Path"** in the launcher | Re-select the correct `Call of Duty Black Ops` folder via **Game Settings**. |
| **Gunfight isn't in the server list** | Reset all filters, click **Refresh**, and check the **Ranked** tab for `Gunfight | gunfight.us`. |
| **`cl_allowdownload disabled`** on join | Open the console and run `cl_allowdownload 1`, then rejoin. |
| **Joined but no custom HUD / mode looks wrong** | Your Plutonium build is out of date - update the launcher to match the server, then rejoin. |
| **Console won't open** with `~` | Enable the console in the Plutonium launcher/in-game options, then press `~` again. |
| **Controller not detected** | Enable **Controls -> Gamepad -> Yes**; if needed, run **[DS4Windows](https://ds4-windows.com/)**. |

---

*Made by KL9. Questions or bugs? Ping us on [Discord](https://discord.gg/blackops).*
