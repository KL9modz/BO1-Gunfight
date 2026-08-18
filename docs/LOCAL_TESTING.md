# Local Test Box

An isolated local dedicated server for exercising a change **before** it is deployed to the live VPS,
on the same PC you play on.

Everything here lives in [`tools/local/`](../tools/local/). It is dev tooling: nothing in it ships in a
public build or reaches the VPS.

---

## Why it exists

Two gaps it closes:

1. **The local server never exec'd `dedicated.cfg`.** It was started straight from the Plutonium
   launcher with no cfg exec at all, so that file, and the RCON panel's 💾 Save which writes it, were
   decoration locally: only `seta`-archived dvars survived a restart
   ([[local-launcher-no-exec-dedicated-cfg]]). The launcher here passes `+exec`, so the cfg is
   authoritative exactly as it is on the VPS.
2. **A deploy was the first place a mistake showed up.** `preflight.ps1` runs everything provable
   without a running game as one command.

The rule the repo already had still stands: **test panel, bridge and telemetry changes against a
DEDICATED server, not a listen host** — a listen server masks RCON queue saturation and the dvar-probe
spam that only bite on the VPS. This gives you a real dedicated server locally.

---

## One-time setup

```powershell
.\tools\local\setup_test_box.ps1
```

Builds an isolated Plutonium storage tree at `C:\gftest` (override with `-TestRoot D:\somewhere`).

| Path | What it is |
|---|---|
| `bin`, `games`, `launcher` | **junction** to the real install (large, read-only) |
| `storage\demonware` | **junction** (the TU WAD cache) |
| `storage\t5\{zone,raw,plutonium}` | **junction** |
| `storage\t5\mods\mp_gunfight` | **junction to this repo** — the server loads the files you edit, no copy step |
| `storage\t5\dedicated.cfg` | private copy, seeded from your real one |
| `storage\t5\local_test.cfg` | private copy of the override layer |
| `storage\t5\{players,logs,demos}` | private, empty |

⚠ **The game logs are NOT isolated, by design.** `g_log` is relative to `fs_game`, and the mod folder
is a junction to the repo, so `games_mp.log` (all `GF_*` diagnostics) and `console_mp.log` land in the
**repo's** `logs/` and root exactly as they do today. `C:\gftest\...\mods\mp_gunfight\console_mp.log`
and the repo path are the same file through the junction. The private `storage\t5\logs` is a different
thing (Plutonium's own service logs).

`players/` is the one that matters. The shared cfg ships **`modStats 0`**, so a server reads and
writes your **real** Black Ops profile — and a test box runs 5× XP, bot farming, and the `_gf_fun`
account editors, which are permanent and have no undo. The isolated tree keeps all of that off it,
and `local_test.cfg` additionally pins `modStats 1`.

Then get a **server key** and put it in `tools/local/local.env.bat` (copy `local.env.bat.example`):

```bat
set KEY=<your test box's key>
```

⚠ **Use a SEPARATE key from the live server.** The key's *label* is the name players see in the
browser, so a second server on the live key renames or shadows the real one. Keys are issued at
<https://platform.plutonium.pw/serverkeys>. The file is gitignored: the key never enters a tracked
file.

⚠ **Without a valid key the server will not load a map.** It starts, binds its port, loads `mod.ff`,
then sits forever on `Early out of maprotate, waiting for WAD!` because Demonware authorization never
completes. A dedicated server authenticates with the key; a game *client* uses its account `-token`,
which is why your client is fine on the same machine. An invalid key fails identically to none
([[local-test-box-port-collision-and-server-key]]).

---

## Daily loop

```powershell
.\tools\local\preflight.ps1          # static checks (see below)
.\tools\local\start_local_server.bat # start the test box
```

Then join from your own client: `connect 127.0.0.1:28965`, and drive it from the panel
(`tools\rcon\rcon_start.bat`, ad-hoc profile on port 28965).

**GSC is loose rawfiles: edit a `.gsc` and `map_restart`. No rebuild, no server restart.** Only a
*compiled* asset (menus, strings, `gametypesTable.csv`, `weaponOptions.csv`, `mod.csv`, `.efx`) needs
`tools\build_ff.ps1`, and a new or edited `.iwi` needs `tools\make_iwd.ps1` as well. `preflight.ps1`
catches both when they go stale.

### You can play while it runs — via two measures, not by luck
**Two** things have to be handled, and each was found the hard way:

1. **Port.** Your client's own server wants **28960**, so the test box defaults to **28965**.
2. **Process name.** Plutonium **refuses to start a game client while a process named
   `plutonium-bootstrapper-win32.exe` is running** — and a dedicated server *is* that executable. So
   the server runs from a renamed copy, `bintest\gfserver.exe`, built by `setup_test_box.ps1`.

⚠ **The guard is one-directional, which makes it very easy to misdiagnose.** A client that is
*already running* tolerates a server started afterwards — so testing in that order shows no problem at
all and invites the conclusion "there is no single-instance lock". Start the server first and the
launcher dies instantly: exit 11, a **0-byte `console.log`**, no message. The A/B, same command and
same token: server running → exit 11 immediately; no server → still running at 25s. Verified both
ways round, including that restoring the stock exe name re-broke the launcher on the very next
attempt.

⚠ **Never "simplify" the launcher back to `bin\plutonium-bootstrapper-win32.exe`.** It would start a
server that works perfectly and silently locks you out of your own game. The bat treats the renamed
copy as a hard requirement and fails loudly rather than falling back.

⚠ A **leftover** bootstrapper trips the same guard — a zombie from a previous session, or a server
someone started by hand. If the game will not launch, look for a stray process before anything else.

### The launcher does not auto-restart
Deliberate. The VPS bat loops because a live server must come back up unattended; a dev box wants the
opposite, since a GSC compile error takes the server down (`SV_Shutdown`) and a restart loop would
scroll the error away. Here it stops with the failure on screen. Read the tail of
`C:\gftest\Plutonium\storage\t5\mods\mp_gunfight\console_mp.log` for `unknown function`.

⚠ Diagnostics split across two files: `logPrint`/`GF_*` land in **`logs\games_mp.log`**, while
`println` and compile errors land in **`console_mp.log`** at the mod root.

---

## `preflight.ps1` — the pre-deploy gate

```powershell
.\tools\local\preflight.ps1            # everything
.\tools\local\preflight.ps1 -Quick     # verifiers + artifacts, no test suites
.\tools\local\preflight.ps1 -NoTests
```

Exit 0 = safe to deploy, 1 = at least one **FAIL**. **WARN** never fails the run: warnings are things
legitimate in some workflows (an unpushed WIP commit) but wrong if you are deploying right now.

| Group | Checks |
|---|---|
| **Static verifiers** | `verify_release_strip` (a strip region that drops a function kept code calls takes down the *whole* server on the next map load), `verify_loadouts`, `verify_locations` |
| **Test suites** | Pester (`tools\tests`), node (`site\test`) |
| **Build artifacts** | `mod.ff` older than any compiled source → FAIL; `mp_gunfight.iwd` older than any `images\*.iwi` → FAIL; a leftover `mp_gunfight.iwd.new` → FAIL (the last build could not overwrite the live `.iwd` because a running game held it open, so it silently did not land) |
| **Deploy readiness** | on `main`, clean tree, pushed, and whether `origin/release:mod.ff` matches the local build by size |

That last one matters because `mod.ff` is gitignored on `main` and reaches the box only via
`origin/release` — a committed menu or string change is **not** live until it is rebuilt *and*
published there.

**It is the static half only.** The other half is loading the mod on the test box and walking the
**smoke checklist** in [DEV.md](DEV.md#post-restructure-smoke-checklist). The verifiers prove symbols
and data; only a real map load proves the GSC parses.

---

## `local_test.cfg` — the override layer

The launcher execs **`dedicated.cfg` first, then `local_test.cfg`**, so every line in the override
file deliberately beats the base. That split keeps the base cfg a faithful VPS mirror (and keeps it
the file the panel's Save writes) while the knobs that must differ on a dev box cannot be clobbered by
copying a cfg down from the VPS.

Shipped overrides, all with a reason:

| Setting | Why |
|---|---|
| `sv_hostname "^3GF ^7LOCAL TEST"` | never let a dev box look like the live one. ⚠ Mostly belt-and-braces: the **server key's label** is what actually shows in the browser and it overrides this ([[plutonium-serverkey-sets-browser-name]]) — so name the test box's key something obviously non-live, and this line only covers surfaces that read the dvar |
| `modStats 1` | keep test XP and the account editors off your real BO1 profile |
| `sv_wwwBaseURL ""`, `sv_wwwDownload 0`, `sv_allowDownload 0` | **load-bearing.** FastDL points a joining client at the server's `mod.ff` and the client overwrites its own with it. A local server aimed at gunfight.us would download the **live** artifact over the build you are testing, which reads as "I rebuilt it and nothing changed" ([[fastdl-download-clobbers-local-modff]]) |
| `party_minplayers 1` | solo testing (2 is the public value) |
| `g_password ""` | a dev box binds all interfaces, so set one if this machine is reachable from your LAN |

⚠ **No semicolons in cfg comments.** The parser splits on that character *inside* a `//` comment and
executes each fragment ([[unknown-command-cd-and-cfg-semicolon-parse]]).

---

## Files

| File | Tracked | What |
|---|---|---|
| `tools/local/setup_test_box.ps1` | yes | builds/relinks/removes the isolated tree (`-Force`, `-Remove`) |
| `tools/local/start_local_server.bat` | yes | the launcher |
| `tools/local/preflight.ps1` | yes | the pre-deploy gate |
| `tools/local/local_test.cfg.example` | yes | template for the override layer |
| `tools/local/local.env.bat.example` | yes | template for machine-local settings |
| `tools/local/local.env.bat` | **no** | your server key, paths, port |

---

## Teardown

```powershell
.\tools\local\setup_test_box.ps1 -Remove
```

Removes junctions individually before deleting the tree. ⚠ Never `rmdir /s` the test root by hand: a
recursive delete over a junction can follow it into the target, which here is the real Plutonium
install and this repo.
