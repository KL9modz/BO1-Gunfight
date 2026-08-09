# `fadeOverTime` lerps a hudelem's COLOR, not just its alpha

**Found:** 2026-08-06, adding the red killing-blow hitmarker.
**Symptom:** the kill marker rendered **pink** — but *only* when a white marker had appeared shortly
before it. A lone kill marker (no other hit nearby) snapped to a clean red and looked correct.

## The finding

`elem fadeOverTime( t )` arms an interpolation over the hudelem's **whole RGBA**, not just its alpha
channel. So a `.color` write that lands while a previous fade is still in flight does not snap — the
engine **crossfades the old colour into the new one** over the remaining time. White → red passes
through pink for most of that transition, which is exactly what shows on screen.

The stock hitmarker leaves such a fade running after every single hit
(`_damagefeedback.gsc:42-44`):

```gsc
	self.hud_damagefeedback.alpha = 1;
	self.hud_damagefeedback fadeOverTime(1);
	self.hud_damagefeedback.alpha = 0;
```

That is a **1-second** fade-out. Land a body shot and then a kill inside that second — routine, it is
most of a kill — and the mod's `.color` write is interpolated instead of applied.

The intermittency is the tell, and it is what identified the cause: a colour write is only lerped when
there is a fade to lerp *along*. With the element idle at alpha 0, the same write is instant.

## The fix that did NOT work: `fadeOverTime( 0 )`

The obvious cancel — a zero-length fade immediately before the write — was shipped first and is
**wrong**. It cleared the simple case but **rapid-fire kills still rendered washed-out red**.

⚠ **A zero-length fade does not cancel a pending interpolation.** Corroborating evidence: stock passes
`0` to `fadeOverTime` **nowhere** in `raw/maps/mp` — the engine has no zero-fade idiom, so there was
never a reason to expect one to be honoured.

## The fix that works: arm a REAL window, in three parts

The only takeover the engine honours is stock's own idiom — arm a genuine fade window and let the write
complete inside it (`_gf_rounds.gsc`, `gf_onPlayerDamage`):

```gsc
	eAttacker.hud_damagefeedback fadeOverTime( 0.05 );   // one frame - the lerp is invisible
	eAttacker.hud_damagefeedback.color = ( 1, 0.15, 0.15 );
```

That alone still leaves two holes, both closed:

1. **`gf_snapKillMarkerRed()`** — stock's `:968` flash re-arms `fadeOverTime(1)` in the **same frame**
   as our write, and the engine folds a still-in-flight colour lerp into that newest window, so the red
   spends stock's whole second crossfading up from white. One frame later nothing else is writing:
   re-snap the colour on a fresh one-frame window, **then re-arm the flash**
   (`alpha=1; fadeOverTime(1); alpha=0`). ⚠ Re-arming is **mandatory** — the snap re-times the in-flight
   *alpha* fade too, so without it the marker blinks out a frame later instead of fading over its second.
2. **The 1s red-hold (`gf_redMarkerUntil`)** — the killing blow owns the marker's **colour** for the
   length of stock's fade-out. A non-lethal hit inside that window keeps stock's alpha re-flash (hit
   feedback intact) but **skips the white re-stamp**, so spraying on into the next enemy can't wash the
   kill flash out mid-fade. Accepted: any marker inside the window flashes red, friendly fire included.
   This also **subsumes** the old shotgun caveat — a trailing non-lethal pellet in the same frame now
   falls inside the hold.

## Why the ordering works at all

The mod writes `.color` from `level.onPlayerDamage`, which fires at `_globallogic_player.gsc:741`;
stock does not flash the marker until `:968`. So the colour is always on the element before it is
shown — the rest of that mechanism (why no element is added, why `setShader` does not clear `.color`,
why the white `else` branch is load-bearing) is in CLAUDE.md's **HUD** section.

## Generalisation

Any mod code that recolours a **stock** hudelem inherits whatever fade state stock left on it. Two
rules fall out:

1. **Never assume a `.color` write is instant.** If the element is animated by code you do not own,
   give the write its own **short real** fade window (0.05s) — **not** `fadeOverTime( 0 )`, which does
   not cancel a pending interpolation. And check whether the code you don't own re-arms its fade in the
   same frame; if it does, a one-frame-later re-snap (plus re-arming its animation) is what actually
   lands the colour.
2. **An intermittent wrong-colour bug that depends on RECENCY is this bug.** If the colour is right
   when the element was idle and wrong when it was recently animated, stop looking for a second
   overlapping element — there is only one, and you are watching it crossfade.

⚠ The second rule cost real time here: the reported symptom was "the red overlaps the white and makes
pink", which reads as two elements drawn on top of each other. It is one element mid-lerp. The
diagnostic that would have settled it in one round — set the colour to pure green, which cannot be
confused with a white blend — was never needed once the recency pattern was reported.
