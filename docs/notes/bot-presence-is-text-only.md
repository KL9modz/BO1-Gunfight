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

## What this closes

- **The Rich Presence tab is dead weight for this project.** Art Assets, the Visualizer and the
  invite image all serve a game client implementing the Discord SDK. We do not have one, and
  BO1/Plutonium does not speak that protocol either ([[plutonium-serverkey-sets-browser-name]] is
  unrelated; the relevant point is simply that no server can set a *player's* presence).
- **Map thumbnails on the bot profile: not possible.** Map art in an EMBED still works fine - that
  takes any public https URL and is a completely different mechanism.
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
