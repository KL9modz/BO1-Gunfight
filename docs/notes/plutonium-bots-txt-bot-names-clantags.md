# Custom bot names + colored clantags: Plutonium's native `bots.txt` (read at process start)

**Finding (2026-08-09):** Plutonium T5 has a built-in mechanism for custom bot names AND per-bot
clantags — no GSC, no BotWarfare change, no mod.ff. A file named **`bots.txt`** in the **storage
root** (`%LOCALAPPDATA%\Plutonium\storage\t5\bots.txt` — one level ABOVE `mods\`, so it is outside
the repo and never touched by `deploy.ps1`), one bot per line:

```
Mason,^<BOT
Woods,^<BOT
```

- Format is **`name[,clantag]`** — comma-separated, clantag optional per line.
- Proven from the engine binary itself: the T5 bot connect userinfo string is
  `...\name\%s\protocol\%d\clanAbbrev\%s\qport\%d`, sitting next to the help text
  *"Custom bot names inside of bots.txt will be randomized"* — so the clantag is baked into the
  bot's userinfo at connect exactly like a real player's, and **`sv_randomizeBotNames`** (already a
  panel row, shipped `1`) only controls pick order from the list.
- **Color codes work in both fields** — standard `^N` carets; orange is **`^<`** (`#F7941C`), per
  the extended-color table in [[sv-hostname-is-discord-rich-presence]]. Clantags cap at
  **7 characters** (Plutonium changelog), so `^<BOT` (5 chars) fits; names cap ~15.
- Deployed 2026-08-09: 24 surname-style entries, every one tagged `^<BOT`, on the VPS + the laptop.

## ⚠ The file is read at PROCESS START — a live server will not pick it up

Observed live: the file was placed while the VPS server was running; a full match end + reconciler
re-add cycled all 4 bots through fresh connects, and they still came back with Plutonium's
internal random names (`PBabar`, `JMattis`, …). So the engine caches the name list at boot (the
file didn't exist then → internal fallback), and **new bot connects within the same process do NOT
re-read it**. A `map_restart` / `matchrestart` is not enough — it takes a **bootstrapper restart**
(same procedure as `deploy.ps1`'s `Restart-Server`: maintenance marker → kill
`plutonium-bootstrapper-win32` → the bat relaunches).

Bots already connected keep their old name until they reconnect, but on any restart that's moot —
the map change drops all test clients and the reconciler re-adds them.

## Ops notes

- **Box-local state**: carried by hand on migration (listed in `docs/MIGRATION.md` §1) — it lives
  above the mod folder, so no deploy path ships it.
- The panel/status parsers don't care: bot identity is `istestclient()`, never name-matched, and
  the `status` parser is end-anchored (names with spaces already handled).
- This does **not** rename the democlient — that label is a separate TODO.
- File encoding: plain ASCII, no BOM (a BOM would corrupt the first name); CRLF used defensively.
