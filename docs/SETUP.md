# Setup & Connect

How to install Black Ops Gunfight, load it on the Plutonium BO1 client, and join the server.

*Part of the [Black Ops Gunfight](../README.md) documentation.*

> **Read this first.** Plutonium has **no automatic mod download**. Every player installs the mod locally, and your installed version must be the **same version as the server** (currently `0.5.2`). A mismatched or missing mod gives an `Invalid download response received from the server` error on join.

## Requirements

- A **legitimate copy of Call of Duty: Black Ops 1** (the game files).
- The **Plutonium launcher**, logged in with a Plutonium account. If you don't have it set up yet, follow the official guide: <https://plutonium.pw/docs/getting-started/>.

Black Ops Gunfight runs on the Plutonium **T5** (Black Ops 1) client. It is free and open source.

## Step 1 - Download Black Ops Gunfight

Grab the latest `mp_gunfight` package from the GitHub releases page:

<https://github.com/KL9modz/BO1-Gunfight/releases>

Download the release archive (the zip) for version `0.5.2`.

## Step 2 - Install it in your mods folder

Extract the archive so the mod folder lands **exactly** here:

```
%LOCALAPPDATA%\Plutonium\storage\t5\mods\mp_gunfight
```

Tips:

- Paste `%LOCALAPPDATA%\Plutonium\storage\t5\mods\` into the Windows Explorer address bar to jump straight to the `mods` folder, then extract the zip into it.
- The folder **must stay named `mp_gunfight`**. If your zip extracts to something like `mp_gunfight-0.5.2`, rename it to `mp_gunfight`.
- When you're done, `gf.gsc` should be at `...\storage\t5\mods\mp_gunfight\maps\mp\gametypes\gf.gsc`. If you see a `mp_gunfight\mp_gunfight\` double-nested folder, move the inner one up a level.

### Version matching (important)

T5's client cannot download mods from the server, so installing once is not "set and forget":

- Your installed mod version must **match the server's**. If the server updates, download the matching release and replace your `mp_gunfight` folder.
- Keep the **Plutonium launcher up to date** as well - just run the launcher so it pulls the current build. A stale client against a freshly-installed server can fail the mod handshake.

If either is out of date you'll get `Invalid download response received from the server` when you try to join.

## Step 3 - Load the mod and join

1. Launch **Black Ops 1** through the Plutonium launcher and go to **Multiplayer**.
2. From the main menu, open the **Mods** menu and load **`mp_gunfight`**.
3. Wait for the yellow confirmation message **"Mod loaded from mods/mp_gunfight"**. Merely having the folder present is not enough - the mod must actually be loaded.
4. Go to the **Server Browser** and join the server named **`Gunfight`**.

> T5 has **no direct IP connect**. You cannot `connect <ip>:port` to a remote server - you must find and join it through the in-game **Server Browser** by its name.

## Step 4 - Recommended settings

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

## Troubleshooting

| Problem | Fix |
|---|---|
| Mod won't load / no **"Mod loaded from mods/mp_gunfight"** message | Confirm the folder is exactly `%LOCALAPPDATA%\Plutonium\storage\t5\mods\mp_gunfight` (named `mp_gunfight`, not double-nested). Re-extract the release if files are missing. |
| Can't find the server in the browser | Make sure you **loaded** the mod first (Step 3), not just installed it. The server name is `Gunfight`. T5 has no direct IP connect - it only appears in the in-game Server Browser. |
| `Invalid download response received from the server` on join | Version mismatch or missing mod. Install the **same release version as the server** (`0.5.2`) and update the **Plutonium launcher** to the current build, then reload the mod. |
| No HUD, blank menu text, or missing effects after joining | The mod isn't installed/loaded on your client. Plutonium does not send mods to clients - install and load `mp_gunfight` locally (Steps 1-3). |
| Can't ADS while sprinting, or aiming stopped after a restart | Apply the sprint/ADS bind above, then run `exec autoexec` in the console. |

## See also

- [Reference](REFERENCE.md) - dvars and tunables.
- [Dev](DEV.md) - building and contributing.
- [VPS deployment](../VPS_DEPLOY.md) and [VPS hardening](../VPS_HARDENING.md) - running your own server.
- Community: [Discord](https://discord.gg/blackops) - find matches and report issues.
