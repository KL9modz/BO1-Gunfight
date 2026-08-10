# mp_gunfight - Box Migration Runbook

Moving the live server from one box to another (the Contabo -> LA move, or any future rehome).

**`docs/VPS_DEPLOY.md` builds a box from nothing. This file is the DELTA** - the state that a fresh
build does *not* reconstruct. Follow VPS_DEPLOY for the build; follow this for what has to travel.

## The core principle

`git clone` + `deploy.ps1` rebuilds the **mod** and the **website**. That is all it rebuilds.

Everything else - credentials, the server identity, connect history, IIS/TLS config, firewall
posture, scheduled tasks, the panel's pinboard - is **deliberately gitignored and box-local**.
`.gitignore` is the closest thing this repo has to a machine-readable inventory of it: every entry
in that file is, by definition, something a new box will not have.

> ⚠ **The old box must stay alive until the new one is verified.** It serves the ISO URL during
> install, it is the only copy of the connect-history day-files, and it is the rollback. Plan a
> multi-day overlap and do not cancel on cutover day.

---

## Phase 0 - Before you buy

Do these on the OLD box, ahead of any purchase. None of them depend on owning the new box.

1. **Drop the DNS TTL to 300s** on `gunfight.us` (A + AAAA). This is the only step with a
   mandatory lead time - at a 3600s or 86400s TTL the cutover drags for hours. Do it first.
2. **Verify each carry-list item below actually exists** and note its path — this is now
   scripted: **`.\tools\carry.ps1 -Check`** reports every item (exists / missing / optional) and
   exits non-zero on a missing REQUIRED one. Finding out that `tools/notify/config.json` was
   never created is a five-minute problem now and a confusing silent-no-alerts problem later.
3. **Take a provider snapshot.** It is the rollback for everything that follows.
4. **Decide rotate-vs-carry for each secret** (table in Phase 2). A migration is the cheapest
   moment to rotate, because you are rewriting the files that hold them anyway.
5. **Pre-sales questions to the new provider**, since either answer can change what you buy:
   - CPU model and clock of the node (the spec that decides whether this beats the old box for a
     single-threaded game server).
   - Any size cap on custom-ISO uploads, if you are going the BYOL route.

---

## Phase 1 - The carry list

Everything below is box-local. Group by group, with how it moves.

> **This phase is scripted: `.\tools\carry.ps1 -Zip`** collects every file item below (plus the
> two scheduled-task XMLs register_services.ps1 does not recreate, the firewall posture, and a
> GF_HITCH baseline extracted from games_mp.log) into one bundle with a MANIFEST that carries
> per-item restore notes and the not-a-file checklist. ⚠ The bundle holds live secrets and player
> PII — scp only, delete from both boxes once verified. The table stays authoritative for WHAT
> moves and WHY; the script is the executable form.

### 1. Game server & settings

| Item | Where | How it moves |
|---|---|---|
| `dedicated.cfg` | `%LOCALAPPDATA%\Plutonium\storage\t5\dedicated.cfg` | **Copy + review.** Never deployed by `deploy.ps1` and gitignored, so this file exists only on the box. Sole owner of `rcon_password` / `g_password`. |
| Plutonium **server key** | `set key=` in the start bat | **Carry the key AND its exact label.** ⚠ The label *is* the in-game browser name - a new key with a different label renames the server for every player. |
| Start bat | `C:\gameserver\T5\start_mp_server.bat` | **Copy + edit.** Carries the server key and the `sv_maxclients` latch (latched at launch - not settable later). |
| `bots.txt` | `%LOCALAPPDATA%\Plutonium\storage\t5\bots.txt` | **Copy.** Custom bot names + orange `^<BOT` clantags. Never deployed by `deploy.ps1` (lives above the mod folder). Read at process start - needs a server restart to load ([[plutonium-bots-txt-bot-names-clantags]]). |
| Game files | `C:\gameserver\T5` | **Re-download** (VPS_DEPLOY Phase 2). Faster than moving ~11 GB. Re-apply the `main\` slim-down after it runs clean. |
| Plutonium runtime | `%LOCALAPPDATA%\Plutonium\bin\` | **Re-created** by running the launcher once and logging in. |
| Mod tree | `...\storage\t5\mods\mp_gunfight\` | **From git** - `deploy.ps1 -Mod`. Nothing to carry. |

⚠ `dedicated.cfg` is the single largest carry risk, because it is where all the *tuned deviations*
live and none of them are in git: `bot_difficulty fu`, the `gf_sv_botYawSpeed` / `...Ads` overrides,
the four `g_fix_*` values, `sv_timeout 240`, `sv_connectTimeout 200`, `g_inactivity 300`,
`scr_pregame_timelimit 0`, `scr_elevator_failsafe 1`, `scr_team_maxsize 6`, `party_minplayers`,
`sv_hostname`, the 28-map `sv_maprotation`, `g_log`/`g_logSync`, and `sv_wwwBaseURL`. Diff it
against `dedicated.cfg.example` before you trust it, and keep the "cfg = deviations only" rule -
a line restating an engine default silently pins that default.

⚠ `sv_wwwBaseURL` **latches at startup**. It must be in the cfg before launch; setting it over RCON
does nothing, and an empty value is what produces the client-side "Invalid download response".

### 2. RCON panel

| Item | Where | How it moves |
|---|---|---|
| `secrets.local.json` | `tools/rcon/` | **Recreate** - `setup_rcon_vps.ps1` writes it by reading the password out of `dedicated.cfg`. |
| `servers.local.json` | `tools/rcon/` | **Recreate** (same script). Holds the loopback profile. ⚠ Joined to the password store **by profile name** - a rename in one file leaves the panel able to see the server but not authenticate. |
| `prefs.local.json` | `tools/rcon/` | **Copy** to keep the FAVORITES pinboard. Stored server-side, so it follows the panel process, not the browser. Regenerable, but only by re-pinning everything by hand. |
| `.geocache.json` | `tools/rcon/` | **Copy** (optional). Player IP -> country cache. Regenerates, but re-warming costs ip-api calls against the free tier's 45/min. ⚠ PII - never leaves the box. |
| `.dvarcache.json` | `tools/rcon/` | **Skip.** Learned per-server dead-dvar cache; regenerates on the next connect sweep. |
| Node LTS | system | **Reinstalled** by `setup_rcon_vps.ps1` if absent. |
| `GF-RconPanel` task | Scheduled Tasks | **Re-registered** by `setup_rcon_vps.ps1`. |

⚠ **Panel-first rule survives the move:** every box-side reader goes through the panel API on
`127.0.0.1:3000`. Do not stand up a second direct RCON poller on the new box - Plutonium answers
roughly one reply per 0.7s and silently drops faster sends.

### 3. Website, FastDL & TLS

| Item | Where | How it moves |
|---|---|---|
| Site content | `C:\inetpub\wwwroot` | **From git** - `deploy.ps1 -Web`. |
| `web.config` | `C:\inetpub\wwwroot\web.config` | **Copy.** Box-owned and deliberately excluded from the `-Web` mirror. Carries the HTTPS redirect, HSTS, and GET/HEAD-only rules. |
| `.ff` MIME type | IIS static content | **Re-apply** (VPS_DEPLOY Phase 8). Without it IIS 404s `mod.ff` and FastDL silently fails. |
| TLS certificate | IIS / Let's Encrypt | **Re-issue** on the new box. Do it *after* DNS cuts over, or the HTTP-01 challenge cannot validate. Preserve the `.well-known` challenge dir. |
| FastDL `mod.ff` | `wwwroot\mods\mp_gunfight\mod.ff` | **Republished** by `deploy.ps1 -Mod`. ⚠ Must stay byte-identical to the server's copy or clients get a blocking `invalid file` and cannot join. |
| Admin site + `.secured` | `wwwroot\admin\` | **Re-run `setup_admin_auth.ps1`.** The `.secured` marker is a fail-safe interlock: until it exists, `GF-StatusService` writes no `admin.json`, so no IP data can reach the web root ahead of auth. Recreate the Basic auth users. |
| IIS bindings | IIS | **Recreate** - site bindings, HTTP->HTTPS, hostnames. |

### 4. Scheduled tasks

| Task | Registered by | Notes |
|---|---|---|
| `GF-ConnLogger` | `register_services.ps1` | Zero RCON - diffs `admin.json`. |
| `GF-JoinNotify` | `register_services.ps1` | ⚠ **Skipped silently** unless `tools/notify/config.json` exists. |
| `GF-StatusService` | `register_services.ps1` | The single box-side RCON reader. |
| `GF-Watchdog` | `register_services.ps1` | Periodic (3 min), so no retry budget to exhaust. |
| `GF-SecurityWatch` | `register_services.ps1` | ⚠ Also needs `notify/config.json` or it detects into the void. |
| `GF-RconPanel` | `setup_rcon_vps.ps1` | Loopback-bound. |
| `GF-GameServer` | manual / VPS_DEPLOY Phase 6 | Wraps the start bat. |
| `GF-ClaudeRC` | manual | `claude rc --name gf-vps`. ⚠ Exactly one server may run, or you get `ambiguous: multiple remote-control servers match name` - **make sure the OLD box's is stopped before starting the new one.** |

**All of these are scripted** - that is the good news of this section. Run `register_services.ps1`
then `setup_rcon_vps.ps1` and the task layer rebuilds itself. Verify with `register_services.ps1 -List`.

⚠ **Auto-logon is a prerequisite, not a task.** The bootstrapper needs an interactive session, so
the new box needs auto-logon re-established (Sysinternals **Autologon.exe** - the encrypted LSA
secret, never the cleartext Winlogon `DefaultPassword` registry method) plus the start-bat shortcut
in `shell:startup`, plus the logon lock task. Without it the game server does not come back from a
reboot.

### 5. Networking & DNS

| Item | How it moves |
|---|---|
| `gunfight.us` A + AAAA | **Repoint** to the new box. TTL already dropped in Phase 0. |
| UDP 28960 | **Re-open** - `New-NetFirewallRule ... -Protocol UDP -LocalPort 28960`. |
| Default-deny inbound | **Re-apply** - `Set-NetFirewallProfile -DefaultInboundAction Block`. |
| Provider-level firewall | **Re-apply** if the new provider has one (Contabo's Cloud Firewall has no direct equivalent everywhere). |
| Out-of-band console | **New address.** The VNC console details in `tools/ops.local.json` are Contabo-specific and must be replaced with the new provider's console. |

⚠ **T5 has no remote `connect <ip>:port`.** Players find the server through the in-game browser by
its `sv_hostname` + server key label, so the IP change is invisible to them **provided the key label
is unchanged**. The DNS change matters for the website and FastDL, not for joining.

### 6. Security & access

| Item | Where | How it moves |
|---|---|---|
| RDP scoping | Firewall `RDP-AdminOnly-In` | **Recreate**, scoped to the home IP (real value in `tools/ops.local.json`). ⚠ Do this **before** exposing the box, or a spammer on world-open 3389 can lock out your own account. |
| SSH rule | Firewall `SSH-Any-In (travel)` | **Recreate.** Additive to the home-scoped rules so it reverts with one `Disable-NetFirewallRule`. |
| sshd key-only | `C:\ProgramData\ssh\sshd_config` | **Re-apply BOTH** `PasswordAuthentication no` **and** `KbdInteractiveAuthentication no`. ⚠ Kbd-interactive is ON by default and offers its own password path - the first directive alone leaves Administrator brute-forceable from the internet. ⚠ Both must sit in the **global** section: the file ends with `Match Group administrators`, so a directive appended at the end silently lands inside it and does nothing globally. |
| SSH public keys | `C:\ProgramData\ssh\administrators_authorized_keys` | **Copy.** ⚠ For admin accounts Windows OpenSSH ignores `~/.ssh/authorized_keys` entirely and reads only this file. |
| `~/.ssh/config` (laptop) | laptop | **Update the `gf-vps` alias** to the new address. Every doc and script refers to the alias, so this one edit repoints all of them. |
| NLA + lockout | registry / `net accounts` | **Re-apply.** |
| Claude Code | `%USERPROFILE%\.claude\.credentials.json` | **Re-authenticate** on the new box (per-Windows-user; a SYSTEM task would be unauthenticated). ⚠ Never set `ANTHROPIC_API_KEY` - it silently takes precedence over the Max-plan login. |
| `security.local.json` | `tools/` | **Recreate** - trusted SSH fingerprints/users for the security watcher. |
| `security_state.json` | `tools/vps_services/` | **Do not copy.** Deleting it is correct: the watcher re-runs trust-on-first-use and baselines the *new* box. Copying it would carry the old box's baseline and produce false alarms forever. |
| Defender / SMBv1 / patching | system | **Re-apply** (VPS_DEPLOY Phase 10 #6). |
| Provider panel | provider | **2FA on the new account**, and treat its console password as a primary secret - the panel can rebuild the box. |

### 7. Data & history

| Item | Where | How it moves |
|---|---|---|
| `players_*.log` day-files | `%LOCALAPPDATA%\Plutonium\storage\t5\logs\players_YYYY-MM-DD.log` | **COPY - irreplaceable.** The admin connection history *and* the public 7-day activity feed both derive from these. Nothing regenerates them. ⚠ Note the path: the **storage tree**, not `tools/`. |
| `.connstate.json` | same `logs\` dir | **Skip** - the logger's own bookmark; regenerates. |
| `tools/notify/config.json` | `tools/notify/` | **Copy.** Holds the secret ntfy topic (functions as a password). Two tasks skip silently without it. |
| `tools/ignore.local.json` | `tools/` | **Copy.** Muted player GUIDs. Re-read on change, no restart. |
| `tools/ops.local.json` | `tools/` | **Copy + edit** - home IP stays, the VNC console entry is replaced with the new provider's. ⚠ Crib sheet only; nothing at runtime reads it. |
| `watchdog_state.json` | `tools/vps_services/` | **Skip** - transient alert state, regenerates. |
| `watchdog_maintenance.json` | `tools/vps_services/` | **Skip** - self-expiring marker. |
| Game logs | `mods/mp_gunfight/logs/`, `console_mp.log` | **Copy only if you want the `GF_HITCH` baseline** for the before/after comparison. Otherwise skip. |

⚠ **Keep the old box's `GF_HITCH` numbers before you wipe it.** They are the acceptance test for
whether the move actually worked: the current baseline is ~2,803 hitches / 10 days, 99.3% in
prematch at ~700-750ms, 226 over 2s, and 15 mid-gameplay at ~2.8s. Without the old numbers the new
box's numbers mean nothing.

---

## Phase 2 - Rotate, don't copy

A migration rewrites every file that holds a secret, so rotation is nearly free here. Two of these
are long-standing open items that this move can finally close.

| Secret | Action | Why |
|---|---|---|
| `rcon_password` | **ROTATE** | Two values are in `main`'s public git history. Rotation is the only thing that closes them. You are authoring a fresh `dedicated.cfg` anyway. ⚠ **<= 23 chars** - Plutonium truncates on login. |
| Plutonium server key | **CARRY** (label + all) | The label is the browser name. Rotate only if you must, and reuse the exact label. |
| Panel password | **Regenerated** | `setup_rcon_vps.ps1` reads it from the rotated `dedicated.cfg`. |
| ntfy topic | Carry, or rotate | Acts as a password; rotating means updating the phone subscription. |
| Windows admin password | **NEW** | New box, new credential. |
| Provider console password | **NEW** + 2FA | |

`tools/rotate_secrets.ps1` handles the RCON side (dry-run by default, enforces the <=23 cap, recycles
the services that cache the password at process start). On the new box the services are being
registered fresh anyway, so the simpler path is: put the new password straight into the new
`dedicated.cfg` before first launch, then let `setup_rcon_vps.ps1` derive the panel's copy from it.

---

## Phase 3 - Repo edits the move requires

Small, easy to forget, and things break subtly without them.

1. **`docs/VPS_DEPLOY.md` "Target box" table** - the single canonical declaration of the box's own
   addresses. This is a **one-row edit** by design; every other file points here or uses the
   `gf-vps` alias. Update plan, IPv4, IPv6, location, OS, console.
2. **`docs/VPS_HARDENING.md`** - the only other file allowed to spell out literals.
3. **`<!-- ip-ok -->` markers** - the pre-commit hook blocks any staged public IP literal. New
   addresses need the marker on their line, or an entry in `tools/hooks/ip-allow.txt`.
   ⚠ **Never allowlist the home IP, the provider console, or a player address.**
4. **Re-enable the hook in the new deploy clone**: `git config core.hooksPath tools/hooks`. It is
   per-clone and does not travel with the repo.
5. **`tools/ops.local.json`** on the box - new console details.
6. **`~/.ssh/config`** on the laptop - repoint the `gf-vps` alias.

---

## Phase 4 - Cutover order

1. Build the new box through **VPS_DEPLOY Phases 1-8** (game files, Plutonium, mod, firewall,
   auto-logon, IIS, FastDL).
2. Apply the carry list (Phase 1 above).
3. Run `register_services.ps1` then `setup_rcon_vps.ps1`; verify with `register_services.ps1 -List`.
4. Run `setup_admin_auth.ps1` to create the `.secured` interlock and Basic auth users.
5. **Smoke-test with DNS still pointing at the old box** - `connect 127.0.0.1:28960` on the new box,
   RCON `status` through the panel, confirm a map loads and a round completes.
6. **Stop `GF-ClaudeRC` on the old box** before starting it on the new one.
7. **Repoint DNS.** Wait out the 300s TTL.
8. **Issue the TLS certificate** (needs DNS to have moved).
9. Verify FastDL externally: `https://gunfight.us/mods/mp_gunfight/mod.ff` must download the binary,
   not a 404 or an HTML page.
10. Announce, and watch the first live round.

---

## Phase 5 - Acceptance checklist

Do not decommission the old box until every line passes.

- [ ] Server appears in the in-game browser under the **same name** (key label intact)
- [ ] A player can join from the browser and download `mod.ff` on join (FastDL working)
- [ ] A full round completes: loadout rotation, overtime flag, killcam, score
- [ ] `gunfight.us` serves over **HTTPS** with a valid cert; HTTP redirects
- [ ] `status.json` / `activity.json` are updating; live player list is correct
- [ ] Admin site prompts for Basic auth and `admin.json` is present (`.secured` in place)
- [ ] Country flags render (geo path working through the panel)
- [ ] Connect history shows **pre-migration** entries (day-files carried successfully)
- [ ] ntfy join alert fires on a real join
- [ ] `register_services.ps1 -List` shows all tasks `Running`
- [ ] Panel reachable over the SSH tunnel; FAVORITES pinboard intact
- [ ] `ssh -v -o PubkeyAuthentication=no gf-vps` answers `publickey` **and nothing else**
- [ ] RDP refused from anywhere but the home IP
- [ ] Box survives a **full reboot** unattended (auto-logon + startup shortcut + tasks)
- [ ] **`GF_HITCH` compared against the old baseline** - the >2s tail and the mid-gameplay hitches
      are the numbers that justify the move

---

## Phase 6 - Decommission

Only after the checklist passes and a few days of live play.

1. Pull a **final copy** of the `players_*.log` day-files (in case any accumulated during overlap).
2. Remove the staged Windows ISO from the old web root.
3. Archive the old `dedicated.cfg` and start bat somewhere durable - they are the record of the
   tuned configuration.
4. Take a final snapshot.
5. Cancel.

⚠ **Do not skip step 1.** The connect history is the one dataset on the box that nothing else
reproduces, and the public activity feed on the site depends on it.
