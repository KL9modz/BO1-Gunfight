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

## Fix that did NOT work #1: `fadeOverTime( 0 )`

The obvious cancel — a zero-length fade immediately before the write — was shipped first and is
**wrong**. It cleared the simple case but **rapid-fire kills still rendered washed-out red**.

⚠ **A zero-length fade does not cancel a pending interpolation.** Corroborating evidence: stock passes
`0` to `fadeOverTime` **nowhere** in `raw/maps/mp` — the engine has no zero-fade idiom, so there was
never a reason to expect one to be honoured.

## Fix that did NOT work #2: arming a REAL window at write time — it killed the WHITE markers

The next obvious move — ride each `.color` write on a genuine one-frame window
(`fadeOverTime( 0.05 )` then write) — is **worse**: live 2026-08-09, **white hitmarkers stopped
rendering entirely** (kills still flashed red). Mechanism: stock's `:968` flash runs **two statements
later in the same frame** — `alpha = 1; fadeOverTime(1); alpha = 0`. Its `alpha = 1` folds into our
still-live 0.05 window with the marker's **current** alpha as the interpolation base — **0 on an idle
marker** — and stock's own `fadeOverTime(1)` + `alpha = 0` then bury the pending flash: the element
lerps 0 → … → 0 and **never reaches visible alpha**. Kills survived only because the snap thread
(below) re-flashes `alpha = 1` two frames later, when every window has expired — which is itself the
live proof of both the fold mechanism and the thread's necessity.

⚠ The general law both failures point at: **whoever arms a window last owns every write still in
flight, and a window armed just before code you do not own writes the element hands your window to
their writes.** You cannot safely arm a fade in a frame where stock is about to flash.

## The fix that works: bare writes in the damage frame + a one-frame-later snap thread

In the damage frame the writes are **bare** (`_gf_rounds.gsc`, `gf_onPlayerDamage`) — instant on an
idle marker, briefly crossfaded on a recently-flashed one, and never in stock's way:

```gsc
	eAttacker.hud_damagefeedback.color = ( 1, 0.15, 0.15 );   // no fadeOverTime here - EVER
```

Correctness for the kill colour comes from two pieces:

1. **`gf_snapKillMarkerRed( killAt )`** — one frame after the kill nothing else is writing, so a
   private one-frame window is safe there: re-snap the colour (`fadeOverTime(0.05)` + red), then the
   frame after **re-arm the flash** (`alpha=1; fadeOverTime(1); alpha=0`). ⚠ Re-arming is
   **mandatory** — the snap re-times the in-flight *alpha* fade too, so without it the marker blinks
   out a frame later instead of fading over its second.
2. **The kill stamp (`gf_redMarkerAt` = the kill's `gettime()`)** — red priority is scoped to the
   killing blow's **own frame**. A non-lethal co-hit with equal `gettime()` skips the white re-stamp,
   which is what cures the shotgun caveat (a trailing pellet of the killing blast whitening the marker;
   either pellet order ends red — white-then-red is last-write-wins inside the frame). A white in any
   **later** frame re-stamps immediately and **clears the stamp**: fresh feedback on a new target beats
   the old kill's flash, and a dead victim fires no damage events, so same-frame co-hits are the only
   post-kill hits that can belong to the kill itself. The stamp doubles as the snap thread's
   **generation token** — cleared or restamped, the mismatch retires a mid-flight
   `gf_snapKillMarkerRed`, so it never paints red over a marker that has moved on.
3. **The resting-colour reset (snap thread step 3)** — `.color` persists, and **fourteen stock
   files flash the same element without passing through `Callback_PlayerDamage`** (grep
   `raw/maps/mp` for `updateDamageFeedback` callers; in Gunfight the reachable ones are the
   equipment family: `_weaponobjects` claymore/C4, `_cameraspike`, `_scrambler`,
   `_tacticalinsertion`, `_acousticsensor`). The hook's white re-stamp never sees those hits, so
   after any kill, shooting enemy equipment flashed **red indefinitely** (live 2026-08-09). There
   is no hookable callback on those paths, so the fix inverts the coverage: ~1.15s after the kill
   — once stock's 1s fade has fully played out and its window expired — the snap thread bare-writes
   the resting colour back to **white** (invisible at alpha 0, token-guarded). Red's reign is
   exactly the kill flash's second; every untracked flash path defaults to white after it.

## Why the ordering works at all

The mod writes `.color` from `level.onPlayerDamage`, which fires at `_globallogic_player.gsc:741`;
stock does not flash the marker until `:968`. So the colour is always on the element before it is
shown — the rest of that mechanism (why no element is added, why `setShader` does not clear `.color`,
why the white `else` branch is load-bearing) is in CLAUDE.md's **HUD** section.

## Generalisation

Any mod code that recolours a **stock** hudelem inherits whatever fade state stock left on it. Two
rules fall out:

1. **Never assume a `.color` write is instant — and never arm a window in a frame the owner is about
   to write.** `fadeOverTime( 0 )` does not cancel a pending interpolation, and a real window armed
   just before the owner's own writes hands the window to THEM (that is how the white markers died).
   The only reliable takeover is a **deferred** one: write bare at event time as best-effort, then
   one frame later — when the element is quiet — arm a private one-frame window, re-write the colour,
   and re-arm the owner's animation.
2. **An intermittent wrong-colour bug that depends on RECENCY is this bug.** If the colour is right
   when the element was idle and wrong when it was recently animated, stop looking for a second
   overlapping element — there is only one, and you are watching it crossfade.

⚠ The second rule cost real time here: the reported symptom was "the red overlaps the white and makes
pink", which reads as two elements drawn on top of each other. It is one element mid-lerp. The
diagnostic that would have settled it in one round — set the colour to pure green, which cannot be
confused with a white blend — was never needed once the recency pattern was reported.
