# The local test box: the collision is the PORT, and a dedicated server needs a real server KEY

**Date:** 2026-08-18 · **Status:** both root-caused live on the laptop (KL9-UFO)

Two findings from building `tools/local/` (the local dedicated test box). They are independent, and
each one wasted time by looking like the other.

## 1. A dedicated server and the game client coexist fine. The PORT is the only collision.

**Symptom:** starting a local dedicated server "prevented the game from launching" on the same PC,
which reads like a single-instance lock.

**It is not.** Proven live: the game client (PID 32532, launched with `-token`) ran **simultaneously**
with **two** dedicated servers (28970 + 28971) out of the *same* Plutonium install, three
`plutonium-bootstrapper-win32.exe` processes at once, both servers bound and listening. There is no
exclusive mutex. (`t5mp.exe` does contain a `CreateMutex` string, which is what makes the wrong
theory so easy to believe. It is not an exclusive game-instance lock.)

The real conflict is **UDP 28960** — the port the client's own server wants. Bind it from a test
server and the client has nowhere to go. **So the fix is a non-default port, and nothing more.**
`start_local_server.bat` therefore defaults to **28965**.

⚠ Do not "fix" a coexistence problem by serializing the two, and do not conclude from a failed
side-by-side launch that Plutonium is single-instance. Check the port first.

## 2. A dedicated server needs a REAL server key, or it never loads a map.

**Symptom:** the server starts, binds its port, loads `mod.ff`, overrides the `gf` rawfiles — and then
sits forever printing:

```
Error: Unable to fetch file online_tu14_mp_english.wad.
Early out of maprotate, waiting for WAD!
```

**Root cause:** `DW_AUTHORIZING TIMED OUT`. A **dedicated server** authenticates to Demonware with the
**server key** (`+set key`); a **game client** authenticates with its account **`-token`** instead —
which is why the client on the same machine, on the same network, is perfectly fine. Without
authorization the engine cannot fetch the TU WAD, and `map_rotate` early-outs every cycle. The process
stays up, so it looks like a hang rather than an auth failure.

**The key must be VALID, not merely present** — tested with a syntactically plausible fake key and it
failed identically. The WAD file existing in `storage/demonware/*/pub/` is likewise a red herring: the
fetch goes through the DW layer, not the local path.

**Confirmed with a real key (2026-08-18).** The whole chain unblocks at once:
`DW_AUTHORIZED (233 msecs)` → `DW_LOBBY_CONNECTING` → `DW_LOGON_COMPLETE` →
`Read 24616 bytes of file online_tu14_mp_english.wad` → `------ Server Initialization ------` →
`Loading fastfile 'mp_array'`, with the `gf` rotation and `GF_LOADGATE`/`GF_LOBBY`/`GF_ENDMARK`
diagnostics flowing. So the key is the single blocker, and nothing else about a keyless launch is
wrong: it binds its port and loads `mod.ff` normally, which is exactly why it reads as a hang.

⚠ **The key's LABEL overwrites `sv_hostname`.** With a key labelled "Local Test", a live rcon read of
`sv_hostname` returns `Local Test`, not the value `local_test.cfg` set. So the cfg's hostname line is
belt-and-braces and the KEY LABEL is the real control over what the box calls itself
([[plutonium-serverkey-sets-browser-name]]) — name a test box's key accordingly.

⚠ **Give the test box its OWN key, never the live server's.** The key's **label is the name players
see in the browser** ([[plutonium-serverkey-sets-browser-name]]), so a second server on the live key
renames or shadows the real one. Keys: https://platform.plutonium.pw/serverkeys

⚠ The key goes in **gitignored `tools/local/local.env.bat`**, never a tracked file. The server key is
the one secret this repo's git history never held, and it leaked once by being pasted where it did not
belong ([[vps-server-provisioned]]).

## 3. Two smaller traps found while building it

- **The bootstrapper resolves the game executable relative to the WORKING DIRECTORY**, not to its own
  path and not to `%LOCALAPPDATA%`. Launching from anywhere else dies with
  `executable "<cwd>\games\t5mp.exe" not found!`. This is exactly why the VPS bat does
  `cd /D %LOCALAPPDATA%\Plutonium` before its launch line — that `cd` is load-bearing, not tidiness.
- **`setlocal enabledelayedexpansion` eats `!` in echoed text**, which silently ate the `!` in the
  "waiting for WAD!" warning. The launcher uses plain `setlocal` — nothing there needs `!var!`.

## Isolation, and why LOCALAPPDATA is the lever
`setup_test_box.ps1` builds a separate storage tree (default `C:\gftest`) and the launcher pins
`LOCALAPPDATA` to it for that process only — the same mechanism the VPS's `GF-GameServer` task uses to
pin its profile. Everything large and read-only (`bin`, `games`, `launcher`, `zone`, `raw`,
`plutonium`, the `demonware` cache) is a **directory junction** back to the real install; the mod
folder is a junction to the repo, so the server loads the files you are editing with no copy step.
Private to the test box: `dedicated.cfg`, `local_test.cfg`, `players/`, `logs/`.

`players/` is the one that matters: the shared cfg ships **`modStats 0`**, so the server reads and
writes the player's **real** Black Ops profile ([[plutonium-stats-are-namespaced-per-mod]]) — a test
box running 5x XP, bot farming and the `_gf_fun` account editors has no business near it. Verified
live: every write to the real profile predated the test server's start, and the test tree's `players/`
stayed empty.

⚠ `-Remove` deletes junctions **individually first**, then the tree. A recursive delete over a
junction can follow it into the target, which here would be the real install and this repo.

## Related
[[local-launcher-no-exec-dedicated-cfg]] (the gap this closes: the local server now execs the cfg, so
it is authoritative and the panel's save button means something) ·
[[plutonium-serverkey-sets-browser-name]] · [[vps-launch-bat-and-maxclients-latch]] ·
[[plutonium-stats-are-namespaced-per-mod]] · [[read-the-server-not-the-file]]
