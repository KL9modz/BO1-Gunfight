# A bot's own presence is TEXT ONLY - buttons and images are ignored

**Settled 2026-08-20 by live test. Do not re-run this.**

## The question

The Developer Portal has a **Rich Presence -> Art Assets** page (300 slots), and the activity object
in a presence update (gateway op 3) has `assets` (large_image / small_image) and `buttons` fields.
So: can **our bot's own** presence carry a map thumbnail and a "Play now" button on its profile?

The gateway docs do not say. They document `name` and `type` on the Update Presence example and
state outright that *"undocumented fields are not supported for apps"*.

## The answer: no

Buttons were the cheap half of the test, because unlike assets they need **no Portal upload** - they
are pure payload. The bot sent exactly this on op 3:

```json
{ "since": null, "afk": false, "status": "online",
  "activities": [ { "name": "Launch", "type": 3,
    "buttons": [ { "label": "Play now",     "url": "https://gunfight.us" },
                 { "label": "Join Discord", "url": "https://discord.gg/blackops" } ] } ] }
```

The profile card rendered:

```
Watching
Launch
```

No buttons. The payload was well-formed and accepted (the gateway did not close, and the text half
updated normally), so this is Discord **ignoring** the field for a bot, not rejecting the message.

⚠ **By implication, `assets` will not render either.** Buttons are the more permissive of the two
rich fields, and both belong to the same Rich Presence family that is published by a GAME over the
local IPC socket. Nobody should spend a day sourcing 26 map images for a profile widget on the hope
that the image half behaves differently from the button half.

## `assets` - the inference above, now PROVEN (2026-08-21)

The image half was tested directly once the art became free (`tools/fetch_map_art.ps1`), which is
what removed the reason not to. `tools/discord_bot/probe_presence_art.js` held one presence at a
time on a live profile:

| variant | payload | rendered |
|---|---|---|
| 1 CONTROL | plain text, no `assets`, no `application_id` | **card: "Playing / 1 - control (no art)"** |
| 2 | `assets.large_image` as an `mp:app-assets/…` proxy path, no app id | **same card, NO picture** |
| 4 | `assets.large_image: "mp_nuked"` + `application_id` = Plutonium's app, which really does own an asset by that name | **same card, NO picture** |

So `assets` is **accepted and silently dropped**, exactly like `buttons`. It does *not* break the
activity - the text half renders identically with the field present or absent - and a foreign
`application_id` does not break it either. Two reference forms, same outcome.

⚠ **THE ACTIVITY IS A CARD; THE CUSTOM STATUS IS A BUBBLE. They are different places on the profile,
and conflating them wasted three probe runs.** The custom status renders in a speech bubble beside
the AVATAR. The activity renders as a titled card **between About Me and Roles**. Watching the
bubble for an activity shows a stale custom status and reads as "nothing rendered at all".

### What is still untested, and it is the only thing left

**Our OWN application id + an asset WE own.** Every shape above pointed at somebody else's app or at
no app, so if Discord refuses to resolve art for an application the bot does not own, that would look
identical to "the field is ignored". It is a real possibility and it is the one route we cannot take
ourselves: **a bot token is 403 on BOTH upload endpoints** -
`POST /oauth2/applications/{id}/assets` ("Bots cannot use this endpoint", 20001) and
`POST /applications/{id}/external-assets`. It needs a human in the Developer Portal.

Cost to settle: upload ONE image named `mp_nuked` (Portal -> Rich Presence -> Art Assets), set
`"presenceMapArt": true`, restart the bot, look while Nuketown is up. `features/presence.js` is
already wired for it end to end - `buildPresence` builds `assets.large_image` straight from
`status.json`'s map field, so nothing needs writing.

### Probe design lessons, because they cost three runs

1. **Run the control FIRST.** Run 1 put it last, where it was contaminated - so "no activity at all"
   could not be told apart from "this probe never rendered anything". A probe whose control goes
   unobserved answers nothing.
2. **HOLD one state, do not cycle on a timer.** Asking a human to catch a 45-second slot on a profile
   popout means a missed slot is indistinguishable from a dropped field.
3. **Stand the watchdog down before stopping any GF-* service.** `GF-Watchdog` saw `GF-DiscordBot`
   as DOWN 2m45s into run 1, restarted it, PAGED the owner with a false alarm, and its custom status
   then won the profile for the rest of the run. Use the same self-expiring marker `deploy.ps1` uses
   (`Write-GfMaintenanceMarker`, `watchdog.ps1:180` skips *all* checks while it is live).

## And only ONE activity renders, custom status winning

Tested twice on 2026-08-20 with a live look each time:

| sent | rendered |
|---|---|
| custom status first, then the activity | the custom status only |
| the ACTIVITY first, then the custom status | **still** the custom status only |

⚠ **Order makes no difference.** Sending both does not get you both - it silently discards the
activity, and a custom status beats every other type regardless of position. A user profile shows a
custom status *and* a game; a bot does not.

So the presence uses **one surface at a time, chosen by state**: the custom status while nobody is
playing, the activity the moment somebody is. That sidesteps the limit rather than fighting it, and
it is what `features/presence.js` does.

## What this closes

- **The Rich Presence tab is dead weight for this project.** Art Assets, the Visualizer and the
  invite image all serve a game client implementing the Discord SDK. We do not have one, and
  BO1/Plutonium does not speak that protocol either ([[plutonium-serverkey-sets-browser-name]] is
  unrelated; the relevant point is simply that no server can set a *player's* presence).
- **Map thumbnails on the bot profile: not possible.** Map art in an EMBED still works fine - that
  takes any public https URL and is a completely different mechanism. **Shipped there instead,
  2026-08-21:** the join card carries the map picture as its embed thumbnail (`Get-GfMapThumb` in
  `tools/map_names.ps1` -> `Send-GfDiscord -Thumbnail`), and it coexists with the link button on the
  same card. Verified live by reading the posted message back: Discord returned a `proxy_url` and
  `256 x 256`, i.e. it fetched and cached the image rather than merely storing the URL.
  ⚠ The pictures come from **Plutonium's own rich-presence Art Assets** (app `924614901975117834`,
  keyed by engine map id), rehosted on gunfight.us by `tools/fetch_map_art.ps1` - so the same art
  this note proves we cannot put on the profile is exactly what the embed now shows. The asset
  *page* was never the problem; the *presence* was.
- The `presenceMapArt` and `presenceButtons` config keys are kept, defaulted OFF, and marked with
  this finding. They cost nothing, and if Discord ever honours these for bots the switch is there.

## What still works on a bot profile

Avatar, **banner** (bots can have one), accent colour, the app description shown as About Me, tags,
the automatic badges, and the activity line itself (`type` + one line of text). The genuinely
interactive surface is **Linked Roles** (`/applications/{id}/role-connections/metadata`, confirmed
reachable - returns `200 []` for our app), which needs an OAuth callback endpoint.

## The one caveat worth stating

This is one client's rendering (Discord desktop, 2026-08-20). It is the practical answer for our
users. If a future Discord release starts showing bot activity buttons, the flags above are already
wired and the test is one config change.
