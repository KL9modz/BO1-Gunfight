---
name: plutonium-serverkey-sets-browser-name
description: "T5 server-browser display name comes from the Plutonium platform serverkey registration (platform.plutonium.pw/serverkeys), NOT sv_hostname in dedicated.cfg"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6e5be926-fdc3-457c-84d2-a847483066cd
---

The name shown for the server in the Plutonium T5 in-game **server browser** is the
label attached to the **server key** at **https://platform.plutonium.pw/serverkeys**, NOT
the `sv_hostname` dvar in `dedicated.cfg`.

Observed 2026-06-30: the browser kept showing "KL9 | Gunfight" no matter what
`sv_hostname` was set to (cfg edit or RCON). The fix was renaming the server on the
serverkeys platform page. `sv_hostname` still exists in `dedicated.cfg` (and is read by
some external master lists / IW4MAdmin), but it does **not** drive the Plutonium browser
name.

**How to change the live browser name:** log in to platform.plutonium.pw/serverkeys, edit
the key's server name there. (Changing `sv_hostname` in the cfg or over RCON will not do it.)

Related: [[vps-server-provisioned]] (the live key lives in the VPS start bat as `+set key %key%`).
