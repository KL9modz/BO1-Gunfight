[<- Black Ops Gunfight](README.md)

# Getting Started

*Install - join - settings*

Black Ops Gunfight runs on [Plutonium](https://plutonium.pw/) for T5 (Call of Duty: Black Ops 1). The open source [CB Servers Launcher](https://cbservers.xyz/launcher/#download) gets you the game for free and Plutonium in one app. You'll need a free [Plutonium account](https://forum.plutonium.pw/register) to play.

## On this page

1. [Install](#1-install)
2. [Find & join Gunfight](#2-find--join-gunfight)
3. [Settings](#3-settings)
4. [Troubleshooting](#4-troubleshooting)

---

## 1. Install

The [CB Servers Launcher](https://cbservers.xyz/launcher/#download) includes everything you need to start playing for free.

1. **Get the launcher.** Download `cb-launcher.exe` from the [CB Servers site](https://cbservers.xyz/launcher/#download).
2. **Run it.** If Windows SmartScreen shows *"Windows protected your PC"*, click **More info -> Run anyway**.
3. **Open the Library tab** and find **Black Ops**, then click **SETUP**. Choose **Download game** and let it finish.
4. **Log in** with your Plutonium account (create one free at [forum.plutonium.pw/register](https://forum.plutonium.pw/register)).
5. **Click PLAY -> Multiplayer -> Server Browser -> [Gunfight](#2-find--join-gunfight)**

> With Black Ops installed, you can open it with either [CB Launcher](https://cbservers.xyz/launcher/#download) or directly through [Plutonium](https://plutonium.pw/docs/install/#plutonium-launcher).

<!-- image slot: docs/images/getting-started/01-launcher-setup.png (CB Servers Launcher: Library -> Black Ops -> SETUP) -->

---

## 2. Find & join Gunfight

Black Ops Gunfight is a ranked server. Join through the in-game **Server Browser**.

1. Launch the game with either [CB Launcher](https://cbservers.xyz/launcher/#download) or directly through [Plutonium](https://plutonium.pw/docs/install/#plutonium-launcher).
2. Click **PLAY** and open the **Server Browser**.
3. On the **Ranked** tab, click **refresh** then find `Gunfight [gunfight.us]` (mode **GF**) and join.

> The screen may go black for a moment as the game does a quick restart before connecting.

![The Server Browser with Gunfight \[gunfight.us\] in the Ranked tab](docs/images/getting-started/server-browser.jpg)
*The Server Browser - look for `Gunfight [gunfight.us]` on the **Ranked** tab.*

> Keep your **Plutonium launcher updated** so its build matches the server's. Questions? Join our [Discord](https://discord.gg/blackops).

---

## 3. Settings

Once connected to the Gunfight Server, press **ESC**, then open **GUNFIGHT -> USER SETTINGS**:

1. On the **GAME** tab, click **APPLY ALL RECOMMENDED**.
2. On the **GRAPHICS** tab, click **SET RECOMMENDED**.
3. Still on **GRAPHICS**, set **Video mode** to your monitor's resolution, then click **APPLY NOW**. The screen goes black for a few seconds while it reloads; you stay in the match.

Done. Your settings save, so you only do this once.

<!-- image slot: docs/images/getting-started/user-settings.jpg (ESC -> GUNFIGHT -> USER SETTINGS, GAME tab) -->

<details>
<summary>What the buttons change</summary>

**APPLY ALL RECOMMENDED**
- Packets per second: **100**
- Reduce engine sleeps: **On**
- Killfeed stays up: **20 seconds**
- Field of view: **65 x 1.3** (see [FOV](#field-of-view-fov))
- Aim fix: **On** (aim down sights while holding Sprint)
- Mute key: **F10**

**SET RECOMMENDED**
- Window: **Borderless**
- V-Sync: **On**
- Texture quality: **Extra**
- Anti-aliasing: **8x**
- Anisotropic filtering: **16x**
- Texture filtering: **Trilinear**
- Shadows and bullet impacts: **On**
- Max FPS: **Unlimited** (V-Sync caps it at your monitor's refresh rate)

</details>

### Refresh rate

A borderless window runs at your Windows refresh rate. In Windows, open **Settings -> System -> Display -> Advanced display** and pick the highest.

### Field of view (FOV)

Your FOV is **Field of view x FOV scale**, both on the **GAME** tab. The recommended **65 x 1.3** works out to about 85.

FOV scale also changes how aiming down sights feels. Three ways to reach **90**:

- `90` x `1`: only hipfire gets wider, so ADS feels slower.
- `40` x `2.25`: ADS matches hipfire, so sensitivity never changes.
- `70` x `1.3`: ADS zooms in a little and feels faster than stock.

### Controller

- Set **Controls -> Gamepad** to **Yes**.
- PlayStation controller? Use [DS4Windows](https://ds4-windows.com/) so the game sees it as an Xbox controller.

---

## 4. Troubleshooting

| Problem | Fix |
|---|---|
| **Controller not detected** | Enable **Controls -> Gamepad -> Yes** (PlayStation controllers need [DS4Windows](https://ds4-windows.com/) or Steam input). |
| **Can't aim down sights** while holding Sprint | Click **APPLY AIM FIX** (ESC -> GUNFIGHT -> USER SETTINGS -> GAME). |
| **FOV or ADS sensitivity feels weird** | See the [Field of view](#field-of-view-fov) section. |
| **Game doesn't feel smooth** | Do the [setup steps](#3-settings), then set Windows to your monitor's [highest refresh rate](#refresh-rate). |
| **Game won't launch / bad install** | In the CB Servers Launcher, open **Black Ops -> SETUP** to re-point or re-download your copy, then click **VERIFY**. |
| **Gunfight isn't in the server list** | Reset all filters, view the **Ranked** tab, and click **Refresh** to find `Gunfight [gunfight.us]`. |
| **Error connecting to the server** | Make sure your Plutonium client is up to date, restart then rejoin. |
| **Settings reset to defaults** after joining Gunfight | Normal on the very first join: your *settings* (FOV, binds, video) are saved **per mod**, not per game. Do the [setup steps](#3-settings) once; they stick from then on. |
| **Does my rank carry over?** | Yes. Gunfight uses your **real Black Ops rank**, the same one you have on any other ranked server, and the XP you earn here counts toward it. Only your settings are separate (row above). |

---

Made by **KL9** - [Discord](https://discord.gg/blackops) - [GitHub](https://github.com/KL9modz/BO1-Gunfight)

*Trademarks used are owned by their respective owners. This mod is not endorsed by or affiliated with the copyright holders of the base game in any form.*
