---
name: modff-drift-vs-gsc-deploy
description: "mod.ff (menu/str/csv/FX) reaches the VPS ONLY via package_release -PublishBranch, while GSC deploys straight from main — so committed menu/str/csv changes are silently NOT live until a rebuild+republish"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c905da21-6ae3-4ada-9b8d-ae5ddf701a0b
---

The deploy pipeline handles GSC and mod.ff by DIFFERENT paths, and they can drift:
- **GSC** (`maps/mp/gametypes/*.gsc`): `deploy.ps1 -Mod` mirrors the tracked `main` tree, so a plain `git push origin main` + deploy makes GSC changes live immediately. No rebuild.
- **mod.ff** (compiled zone = `hud_gf_health.menu` + `hud_gf.txt` + `gf.str` + `gametypesTable.csv` + `_gametypes.txt` + `gf.txt` + the `fx/misc/*.efx`): `deploy.ps1 -Mod` fetches mod.ff ONLY from the `release` branch (`git checkout FETCH_HEAD -- mod.ff`). The release branch's mod.ff updates ONLY when you run `tools\package_release.ps1 <ver> -PublishBranch` (which calls `build_ff.ps1`).

CONSEQUENCE (bit us 2026-07-03): committing a menu/str/csv change to `main` does NOT put it on the server. The release-branch mod.ff had been built at the **0.5.4 tag** and was never rebuilt while `main` gained the whole 6v6 health-HUD menu rework (`c539bb7`, `ace0c9f`) — so the VPS ran a stale mod.ff (pre-6v6 menu itemDefs) for weeks even though the 6v6 GSC was live. FastDL clients auto-downloaded that stale mod.ff too. A compressed-size delta between the old and freshly-built mod.ff (18240 -> 17312 bytes) is the tell that the release mod.ff had drifted from main's UI source, NOT a dropped asset (verify FX by confirming `raw/fx/misc/fx_ui_flagbase_gf_white.efx` exists; mod.ff is compressed so you canNOT grep asset-name strings in it).

RULE: any change under `ui_mp/`, `localizedstrings/`, `mp/gametypesTable.csv`, `maps/mp/gametypes/*.txt`, or `raw/fx/` needs `build_ff.ps1` + `package_release.ps1 <ver> -PublishBranch` + `deploy.ps1 -Mod` to go live — a bare main push only ships GSC. See [[repo-release-branch-structure]], [[build-stage-transitive-menu]], [[vps-gsc-deploy-log-verification]].

## ⚠ "Does MY diff touch a compiled asset?" is the WRONG check (bit us AGAIN 2026-07-12)

Asking whether the diff *you are about to deploy* changes a compiled asset is necessary but **not sufficient** — the release mod.ff can ALREADY be stale from an **earlier** commit. That is exactly what happened: a 6-commit deploy touched no compiled asset (correctly → "no rebuild needed"), but `d2d265c` had edited `ui_mp/hud_gf_health.menu` ("tidy the lobby HUD rules line") **without** rebuilding, so the live zone still shipped the deleted lobby text. The user spotted it in-game; the deploy check did not.

**The check is a property of the BRANCH, not a diff scan.** Compare a fresh local build against what deploy will actually ship:
```
git hash-object mod.ff              # a fresh local build_ff.ps1 output
git rev-parse origin/release:mod.ff # what deploy.ps1 will actually ship
git cat-file -s origin/release:mod.ff   # ... and its SIZE (the real signal — see below)
```
Do this before EVERY `deploy.ps1 -Mod`, not just when you edited a menu.

### ⚠ The HASH compare gives a FALSE POSITIVE every time — compare the SIZE (proven 2026-07-13)

**`build_ff.ps1` output is NOT byte-deterministic.** Two consecutive builds of *identical, untouched* sources produce the **same byte size but a different SHA** (measured: both 20288 bytes, hashes `949c58e0…` vs `c944a5a7…`). The linker's compressed output carries some run-varying bytes. So a bare `git hash-object` compare reports "DRIFT!" on **every** deploy even when the zone is perfectly fresh — and acting on it means pushing a pointless new `release` commit each time.

**Use the compressed SIZE as the drift signal**, exactly as the 0.5.4 incident originally did:
- **Sizes differ → real drift.** Content genuinely changed. The stale zone is consistently the **smaller** one (18240→17312, 20224→19552, and 19360→20288 on 2026-07-13 — the same shrink signature three times, because the stale build predates added menu/str content).
- **Sizes match → treat as fresh.** Don't chase the hash.

(2026-07-13: the `Release 0.6.5 (clean snapshot)` publish shipped a **19360-byte** mod.ff while a fresh build of the very same sources was **20288** — so `package_release.ps1` had published a stale zone, most likely via `-SkipBuild` reusing an old local `mod.ff`. ⚠ **`-SkipBuild` is how a stale zone gets *into* a release.** Republished the fresh zone alone onto `release` by the worktree route below.)

## You can publish mod.ff ALONE — a full release is not required

`package_release.ps1 -PublishBranch` is not the only route, and it is often the wrong one: `release` is GitHub's **public default branch**, so publishing it cuts a public release (it was 278 commits behind main — a huge, outward-facing action just to fix a zone). To fix ONLY the drift, commit the rebuilt mod.ff onto `release` by itself, from a detached worktree so `main` is never touched:
```
git worktree add --detach <tmp> origin/release
cp mod.ff <tmp>/mod.ff && cd <tmp> && git add -f mod.ff   # -f: gitignored on main, tracked on release
git commit -m "mod.ff: rebuild" && git push origin HEAD:release
git worktree remove --force <tmp>
```
This is SAFE for the VPS and its players: a connecting client only ever downloads **mod.ff** (GSC runs server-side as loose rawfiles), so `main`'s GSC + a fresh zone is a consistent pair. It leaves the public GSC snapshot at the old release tag — fine, and it keeps future deploys correct. ⚠ Do NOT instead scp mod.ff onto the box: the next `deploy.ps1 -Mod` re-fetches from `release` and silently REGRESSES it. See [[vps-deploy-repo-path-and-ssh-invocation]].
