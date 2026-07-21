---
name: seed-if-empty-dead-on-engine-registered-dvars
description: "A GSC seed-if-empty can NEVER fire on an engine-registered dvar (it is never empty) — bot_difficulty (engine default \"normal\") silently reverted from fu on every server restart; such defaults must be cfg-owned"
metadata: 
  node_type: memory
  type: project
  originSessionId: a6871413-0e01-4867-86a6-cdd3cbb14d2b
---

**Incident (2026-07-17):** after a routine VPS deploy/restart, `bot_difficulty` read `normal` although
the documented GF default was `fu` "seeded if-empty in gf.gsc". A bare rcon query settled it:
`bot_difficulty` is a **REAL ENGINE dvar** (BO1 Combat Training) registered at process start —
`default: "normal"`, enum `Domain: easy/normal/hard/fu`. An engine-registered dvar is **never empty**,
so the `if (getDvar(...) == "") setDvar(...)` seed was dead code that had never fired once. Every
"fu" ever observed was a live panel `botdiff_fu` click surviving in-process — and every server restart
silently reverted the box to `normal`.

**Why:** seed-if-empty only works on mod-invented dvar names (unregistered until the seed creates
them). Engine registration happens before any cfg or GSC runs, so the read always returns the engine
default, never `""`. GSC also cannot force-set instead: an engine-registered `normal` is
indistinguishable from an admin's deliberately chosen `normal`, so a forced set would stomp cfg intent.

**Fix applied:** the default moved to `dedicated.cfg` (`set bot_difficulty "fu"`, VPS + example) — a
genuine deviation from an engine default, which is exactly what cfg is for per [[read-the-server-not-the-file]]
(cfg = deviations only). The dead seed in gf.gsc was removed and replaced with a comment. Verified
across a cold boot: post-restart live read = `fu`.

**How to apply:** before adding any seed-if-empty, prove the name is NOT engine-registered — bare rcon
query: a typed `Domain is ...` + a default that doesn't mirror your own set = registered (seed is dead;
cfg owns the default); `Domain is any text` = user-created (seed works). Same live-read discipline as
[[engine-dvar-defaults-from-log-dump]] and [[perk-multiplier-defaults-are-the-effect]].
