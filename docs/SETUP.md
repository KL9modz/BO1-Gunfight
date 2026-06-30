# Setup & Connect

How to join Black Ops Gunfight on the Plutonium BO1 client (plus the manual-install fallback).

*Part of the [Black Ops Gunfight](../README.md) documentation.*

> **You don't need to install the mod by hand.** Plutonium **downloads the server's mod to you automatically** when you connect (via the server's FastDL). All you need is Black Ops 1, the Plutonium launcher, and an up-to-date launcher build. A manual install is still available as a [fallback](#manual-install-fallback).

## Requirements

- A **legitimate copy of Call of Duty: Black Ops 1** (the game files).
- The **Plutonium launcher**, logged in with a Plutonium account. If you don't have it set up yet, follow the official guide: <https://plutonium.pw/docs/getting-started/>.

Black Ops Gunfight runs on the Plutonium **T5** (Black Ops 1) client. It is free and open source.

## Step 1 - Launch and join

1. Launch **Black Ops 1** through the Plutonium launcher and go to **Multiplayer**.
2. Open the **Server Browser** and join the server named **`Gunfight`**.
3. On connect, Plutonium downloads the mod from the server and loads it for you - there's no Mods-menu step. The **first** join may take a moment while `mod.ff` downloads.

> T5 has **no direct IP connect**. You cannot `connect <ip>:port` to a remote server - you must find and join it through the in-game **Server Browser** by its name.

### Keep your launcher updated

FastDL ships the **mod**, not the Plutonium **engine**. So keep the **Plutonium launcher up to date** - just run the launcher so it pulls the current build. A client engine build that's behind the server's can fail the join handshake even though the mod itself downloads fine.

## Step 2 - Recommended settings

These are optional client tweaks that make BO1 feel a lot better. Open the in-game console with the **`~`** (tilde) key and paste each command in.

### Fix aiming while sprinting

Stock BO1 will not let you aim down sights while the sprint key is held - you have to release sprint first. This one bind clears sprint the instant you ADS so you can aim without letting go:

```
bind MOUSE2 "+speed_throw; -breath_sprint; -sprint"
```

Notes:

- This forces **hold-to-ADS** (not toggle ADS).
- If aiming ever stops working after a restart, reopen the console and run:

  ```
  exec autoexec
  ```

  Plutonium does not auto-run `autoexec`, so you may need to run it again after relaunching.

### Field of view

The default FOV is a cramped `65`. Open it up for better awareness:

```
cg_fov 80
```

Set it once in the console; it sticks across sessions.

### Graphics & visibility

Max out **Options > Graphics** to your taste - texture and model quality cost little on modern hardware. You **don't** need to touch gamma or HDR: the mod sets those each round so everyone gets consistent visibility.

## Manual install (fallback)

Auto-download is the normal path, but you can install the mod by hand if you prefer (or to pre-stage it):

1. Grab the latest `mp_gunfight` package from the [releases page](https://github.com/KL9modz/BO1-Gunfight/releases).
2. Extract the archive so the mod folder lands **exactly** here:

   ```
   %LOCALAPPDATA%\Plutonium\storage\t5\mods\mp_gunfight
   ```

   - The folder **must stay named `mp_gunfight`**. If your zip extracts to something like `mp_gunfight-0.5.2`, rename it to `mp_gunfight`.
   - When you're done, `gf.gsc` should be at `...\storage\t5\mods\mp_gunfight\maps\mp\gametypes\gf.gsc`. If you see a `mp_gunfight\mp_gunfight\` double-nested folder, move the inner one up a level.
3. Launch BO1 multiplayer -> open the **Mods** menu -> load **`mp_gunfight`** (wait for the yellow **"Mod loaded from mods/mp_gunfight"** message) -> **Server Browser** -> join **`Gunfight`**.

A hand-installed `mod.ff` has to be **byte-identical** to the server's. If yours has drifted, the server's copy simply downloads over it on connect - so when in doubt, just let auto-download handle it.

## Troubleshooting

| Problem | Fix |
|---|---|
| Stuck or errored on join while the mod downloads | Make sure your **Plutonium launcher is up to date** (run the launcher to pull the current build), then retry. The engine build must match the server's even though the mod auto-downloads. |
| Can't find the server in the browser | The server name is `Gunfight`. T5 has no direct IP connect - it only appears in the in-game Server Browser. |
| `Invalid download response received from the server` on join | A server-side FastDL issue or an out-of-date launcher. Update the **Plutonium launcher** first; if it persists, the server's download host may be down - report it on [Discord](https://discord.gg/blackops). |
| No HUD, blank menu text, or missing effects after joining | The mod didn't load. Rejoin so it re-downloads, or install `mp_gunfight` manually (see [Manual install](#manual-install-fallback)) and load it from the Mods menu. |
| Can't ADS while sprinting, or aiming stopped after a restart | Apply the sprint/ADS bind above, then run `exec autoexec` in the console. |

## See also

- [Reference](REFERENCE.md) - dvars and tunables.
- [Dev](DEV.md) - building and contributing.
- [VPS deployment](../VPS_DEPLOY.md) and [VPS hardening](../VPS_HARDENING.md) - running your own server.
- Community: [Discord](https://discord.gg/blackops) - find matches and report issues.
