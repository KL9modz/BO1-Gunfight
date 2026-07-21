---
name: plutonium-menu-ads-not-moddable
description: "The cycling ad banner in the Plutonium menu (\"Join our Discord\") is drawn client-side by the Plutonium client from their own backend — unreachable from the mod. sv_motd (intel loadscreen) is the server-owned MOTD."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 060f4a97-617d-4251-a154-d163e30a2ff9
---

**The Plutonium menu ad rotation CANNOT be overridden by the mod.** Investigated 2026-07-11; four
independent lines of evidence, so don't re-derive this:

1. **Not a game asset.** The stock BO1 MOTD info-box in `raw/ui_mp/main.menu` is **commented out**
   (`//#define INFO_TEXT dvarString("motd")` / `//#include "ui_mp/info_box.inc"`), and *nothing* in the
   raw dump renders the engine UI expressions `GetMOTDField` / `IsBlankMOTD` (they exist only as entries
   in `raw/expressions/functions.txt`). So no `.menu` we could override draws it.
2. **Not the Demonware MOTD.** `storage\demonware\18409\pub\motd-english.txt` (the classic COD MOTD
   delivery channel) contains the stale placeholder `Welcome to Plutonium IW5!` — not the ad.
3. **Not baked in any on-disk binary.** The ad text is absent from `Plutonium\games\t5mp.exe` and from
   `plutonium-bootstrapper-win32.exe` (which only carries the launcher's own hardcoded Discord invite). It's
   fetched at runtime by the injected Plutonium client module and drawn by the client.
4. **Structurally decisive:** that screen is **pre-connection**. A player in the Plutonium menu has not
   connected to our server, has not downloaded `mod.ff`, and no GSC of ours is running — `setClientDvar`
   needs a connected client. There is no channel from our server to that screen, whatever draws it.

The only way to change it is patching the Plutonium client — client-side only (nobody else would see
it), and it's the platform's own promo space. Not a route we take.

**What we DO own instead (the real MOTD surfaces):**
- **`sv_motd`** — a real, documented Plutonium dvar: custom message on the **join/intel loadscreen**;
  blank = default intel messages. Already set in `dedicated.cfg`:
  `set sv_motd "^3Welcome to ^1Gunfight^3! Join us at ^5discord.gg/blackops"`. This is the closest
  legitimate analogue and it reaches every joining player. (Related engine dvars `motd` / `g_motd` /
  `cl_motdString` / `scr_motd` exist but are inert here.)
- **In-game HUD** via the menu layer (`ui_mp/hud_gf_health.menu`) — the persistent "gunfight.us"
  watermark on the TODO. Zero hudelem cost, see [[settext-configstring-exhaustion]].
- Join splash (`_hud_message::oldNotifyMessage`) / a `say` line under `sv_sayName "Console"`.
- Server-browser name = the Plutonium **server-key label**, not `sv_hostname`
  ([[plutonium-serverkey-sets-browser-name]]).
- Gametype description ([[gunfight-description-single-source]]).

Invite must stay `discord.gg/blackops` ([[discord-invite-canonical-blackops]]).
