# mp_gunfight

Gunfight gametype for **Call of Duty: Black Ops 1** (Plutonium T5) - one life per
round, shared random loadouts, six rounds to win the match.

**Version 0.5.1**

## Install (required for every player AND the server)

Plutonium's T5 client cannot download mods from a server, so everyone joining must
install the mod locally. Without it you get no HUD, blank text, and missing effects.

1. Open your Plutonium storage mods folder: `%localappdata%\Plutonium\storage\t5\mods\`
2. Extract so the path is `...\storage\t5\mods\mp_gunfight\mod.ff`
3. In the Plutonium console (or your server config):

       loadMod mp_gunfight
       map_restart

4. Start a match:

       g_gametype gf
       map mp_havoc

## Source

Full source and development are on the
[`main`](https://github.com/KL9modz/BO1-Gunfight/tree/main) branch.