---
name: sv-hostname-is-discord-rich-presence
description: "sv_hostname is the line Plutonium's Discord rich presence publishes for every player on the server. Unset, BO1's engine default makes everyone's Discord read \"BlackOpsPrivate\". Plain text only - colour codes above ^; leak literally."
metadata:
  node_type: memory
  type: reference
---

**Every player on the server publishes `sv_hostname` to Discord.** Traced 2026-08-05 from a report of
Discord showing "BlackOpsGunfight"-era status as **`BlackOpsPrivate`**. The mod has zero Discord code -
this is Plutonium plus a stock Treyarch default.

## The chain

1. **Plutonium publishes the activity.** `plutonium-bootstrapper-win32.exe` ships
   `bin\discord_game_sdk.dll` and carries `plutonium::t5::rich_presence::startup` (alongside t4/t6/iw5).
   The presence payload is built from `cl_ingame`, `mapname`, `g_gametype`, **`sv_hostname`**,
   `sv_maxclients`, plus `"%s on %s"` (gametype on map), `"Main menu"`, `"connect %s"` (join secret) and
   the image key `pluto_t5%s`.
2. **`BlackOpsPrivate` is BO1's own default for `sv_hostname`.** In `t5mp.exe` at VA `0x584BF1` the
   engine registers it with a two-way select - the only two references to either string in the binary,
   7 bytes apart:

   ```asm
   cmp  dword [eax+0x18], 0
   mov  eax, offset "BlackOpsPublic"     ; public / LSG session
   jnz  done
   mov  eax, offset "BlackOpsPrivate"    ; everything else
   done:
   push "" / push 5 / push eax / push "sv_hostname" / call Dvar_RegisterString
   ```

3. **It is server-owned and replicated.** The `InitGame:` serverinfo line carries
   `\sv_hostname\BlackOpsPrivate\` and the client refuses writes with
   `Error: sv_hostname can only be changed by the server`, so a client's copy is whatever the server
   it joined has.

## Rules

- ⚠ **NO COLOUR CODES in `sv_hostname`.** Discord renders `details`/`state` as **plain text** - no
  colour, no markdown, no clickable link - and Plutonium strips codes before publishing anyway. Its
  strip regex is **`\^\d|\^:|\^;`**, i.e. indices **0-11 only**: `^<` (orange) and everything above it
  is **NOT stripped** and would publish literally as `^<YourName.com` to every player. Nothing else
  displays this dvar either, so a `^` code here renders nowhere and only shows up in the logs.
- ⚠ **`sv_hostname` is NOT the server-browser name** - that is the Plutonium server-key label
  ([[plutonium-serverkey-sets-browser-name]]). Different surface, different place to edit.
- The presence detail lines only render on the **profile popout / activity card**; the member list
  shows Plutonium's own Discord application name. Modest reach, but free.
- `dedicated.cfg` is box-owned and **not shipped by `deploy.ps1`** - a change reaches the VPS only via
  the panel (set, then Save) or a hand edit. The tracked `server/dedicated.cfg.example` is
  documentation.

## Ruled out (do not re-derive)

Discord's game-detection database (all 23,888 `applications/detectable` entries fetched - the Black Ops
entry is "Call of Duty: Black Ops", nothing named `BlackOpsPrivate`, and neither
`plutonium-bootstrapper-win32.exe` nor `t5mp.exe` is listed); the window title/class
(`CoDBlackOps` / "Plutonium T5 Multiplayer (rNNNN)"); PE version info on every candidate exe; the
registry; and any named mutex/event/file-mapping.

One gap, stated honestly: the `sv_hostname` *string* has no xref inside the T5 presence function
(its xrefs land in the IW5 one and elsewhere), so T5 fetches the dvar by cached pointer or hardcoded
address rather than by name. The behaviour is settled by observation, not read off the disassembly.

## Bonus: the real colour-code table

Pulled from `t5mp.exe` at `0x6C2CE8` (VA `0xAC3AE8`), 17 entries of vec4 float. The parser is the
19-byte function at file offset `0x14BC70`, and it settles the "is orange real" question outright -
there is **no digit check at all**:

```asm
mov   al, [esp+4]      ; the char after '^'
sub   al, 0x30         ; index = char - '0'
cmp   al, 0x11         ; 17 = table size
movzx eax, al
jb    use_it           ; 0..16 -> real entry
mov   eax, 7           ; else WHITE fallback
ret
```

Its one caller (`0xFC78D`, the only xref to the table) re-checks `cmp eax, 0x11` then
`shl eax, 4` + table base. So codes run past `^9` into ASCII punctuation, `^A`+ falls back to white,
and a char below `'0'` wraps unsigned and also lands on white. **Orange is `^<`** (`'<'` = 0x3C, minus
0x30 = index **12**; `0.97 0.58 0.11` = `#F7941C`). `^0` black, `^1` red (1, .2, .2), `^2` green, `^3` pale yellow, `^4` blue, `^5` cyan,
`^6` pink, **`^7` `^8` `^9` are all plain white** (forum lists claiming grey/brown are wrong for T5),
`^:` dark red, `^;` sea green, `^<` **orange**, `^=` steel blue, `^>` light grey, `^?` purple,
`^@` brown. These render wherever the game draws colour codes (server-key label, `sv_motd`, chat) -
just never in `sv_hostname`.

Related: [[plutonium-menu-ads-not-moddable]] (the other MOTD/ad surfaces we own).
