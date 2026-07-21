---
name: rcon-wrong-password-is-silent-not-an-error
description: A wrong rcon_password makes Plutonium DROP the packet with no reply — identical to a firewall block. And getstatus is NOT a reachability probe (Pluto T5 never answers it).
metadata: 
  node_type: memory
  type: project
  originSessionId: 782af5bf-007b-4e40-a664-97394d96f6a4
---

Plutonium T5 answers a **wrong rcon password with total silence** — no "Invalid password",
no packet at all. On the panel that renders exactly like a dead network path, so
"rcon won't connect" is **a password hypothesis before it is a network one**.

⚠ **`getstatus` is useless as a reachability probe here** — Pluto T5 does not answer it
*even over loopback on a healthy server*. A `getstatus` timeout proves nothing; it does
NOT mean the port is blocked. Only an rcon packet **with a known-correct password** can
distinguish "unreachable" from "wrong password".

**Why:** every failure mode collapses to the same observable (no UDP reply): wrong
password, blocked port, dead server. They must be told apart by *changing one variable at
a time against ground truth*, never by the symptom.

**How to apply — the ladder that worked (2026-07-17, laptop panel → VPS):**
1. `Test-NetConnection <ip> -Port 22` + ping — is the box alive at all?
2. SSH in: is `plutonium-bootstrapper-win32` up and is UDP 28960 bound to `0.0.0.0`?
3. **Read the live `console_mp.log` tail** — the real up/down verdict. It lives in the
   **mod folder** (`...\storage\t5\mods\mp_gunfight\console_mp.log`), NOT `storage\t5\`.
   A live tail + client stat flushes = the server is healthy, so the fault is the *probe*.
4. Read `rcon_password` out of the **live** `dedicated.cfg` and rcon over **loopback**.
   A reply here = the server is fine and the problem is entirely client-side.
5. Only then rcon from the laptop **with that same password**. A reply = pure password
   staleness; still nothing = the network.

**The actual bug:** the VPS password had been rotated (cfg edited 01:10, server restarted
01:38) and `tools/rcon/secrets.local.json`'s `VPS` entry still held the old 20-char one
(live = 22 chars). Comparing **lengths** alone exposed it without ever printing a secret —
do that first, it's free.

⚠ **Two traps that cost time here:**
- **Extracting the password with a sloppy regex** grabs the trailing `// comment` too
  (read back as `len=264`), producing a *wrong-password silent drop* that masquerades as a
  dead server. Anchor on the quotes: `set\s+rcon_password\s+"([^"]*)"`.
- **`GET /api/tick` with no query params always reports `Server not responding (timeout)`**
  — the panel takes host/port/password *from the UI*, so a bare curl is not evidence the
  panel is broken.

Related: [[read-the-server-not-the-file]] (the cfg on disk was right; the panel's cached
copy was the lie), [[rcon-tool-vps-connect-23char-cap]] (≤23 chars — the live 22 fits),
[[rcon-panel-queue-saturation]], [[vps-launch-bat-and-maxclients-latch]].
