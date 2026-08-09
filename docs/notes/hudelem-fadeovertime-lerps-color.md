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

## The fix

Cancel the pending interpolation with a zero-length fade immediately before the write
(`_gf_rounds.gsc`, `gf_onPlayerDamage`):

```gsc
	eAttacker.hud_damagefeedback fadeOverTime( 0 );
	eAttacker.hud_damagefeedback.color = ( 1, 0.15, 0.15 );
```

⚠ This does **not** disturb stock's fade-out. Stock re-arms `fadeOverTime(1)` itself at `:968`,
immediately before its own `alpha = 0`, so only our write is snapped — the marker still fades out over
a full second exactly as it always did.

## Why the ordering works at all

The mod writes `.color` from `level.onPlayerDamage`, which fires at `_globallogic_player.gsc:741`;
stock does not flash the marker until `:968`. So the colour is always on the element before it is
shown — the rest of that mechanism (why no element is added, why `setShader` does not clear `.color`,
why the white `else` branch is load-bearing) is in CLAUDE.md's **HUD** section.

## Generalisation

Any mod code that recolours a **stock** hudelem inherits whatever fade state stock left on it. Two
rules fall out:

1. **Never assume a `.color` write is instant.** If the element is animated by code you do not own,
   snap it with `fadeOverTime( 0 )` first.
2. **An intermittent wrong-colour bug that depends on RECENCY is this bug.** If the colour is right
   when the element was idle and wrong when it was recently animated, stop looking for a second
   overlapping element — there is only one, and you are watching it crossfade.

⚠ The second rule cost real time here: the reported symptom was "the red overlaps the white and makes
pink", which reads as two elements drawn on top of each other. It is one element mid-lerp. The
diagnostic that would have settled it in one round — set the colour to pure green, which cannot be
confused with a white blend — was never needed once the recency pattern was reported.
