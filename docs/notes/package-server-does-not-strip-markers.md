---
name: package-server-does-not-strip-markers
description: "package_server.ps1 (VPS bundle) does NOT run Strip-Markers — the gf.gsc dev cheat/secret block ships live to the dedicated server, contradicting the in-code \"block is gone on VPS\" comment"
metadata: 
  node_type: memory
  type: project
  originSessionId: ac394956-0b16-45d9-8127-e9c89468a139
---

`tools/package_server.ps1` builds the private VPS bundle by copying every `git ls-files`
path from `main` **verbatim** plus `mod.ff`. It has **no `Strip-Markers` / `Strip-Comments`
pass** — only `tools/package_release.ps1` strips `// #strip-begin ... // #strip-end` regions.

Consequence: whatever dev wiring lives between the strip markers in `gf.gsc` ships and runs
on the live dedicated VPS — that is **by design** (the VPS is meant to run the dev machinery;
only the public *release* build strips it). The alarming secret-leak specifics are now
resolved: `gf.gsc` **no longer hardcodes an `rcon_password`** (it says "NO password is set
here" behind a fail-closed `sv_cheats` guard), and `package_server.ps1` now carries a **secret
guard that throws** on any staged GSC hardcoding an `rcon_password`, so a throwaway password
can no longer become the effective live RCON credential. The RCON password is owned solely by
the gitignored `t5/dedicated.cfg`.

The one thing package_server still deliberately does NOT do is run `Strip-Markers` /
`Strip-Comments` — the VPS bundle ships the dev block live on purpose. Relates to
[[repo-release-branch-structure]] and [[gf-timer-prematch-and-pause-model]].
