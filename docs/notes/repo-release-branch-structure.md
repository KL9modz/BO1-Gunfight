---
name: repo-release-branch-structure
description: "GitHub default branch is 'release' (clean orphan snapshot), NOT main; main is the full dev source. Three content tiers + packaging scripts."
metadata: 
  node_type: memory
  type: project
  originSessionId: 4742057e-0b4d-4982-8749-a8735ac3d7de
---

GitHub repo **KL9modz/BO1-Gunfight** uses a deliberate non-standard branch layout (set up 2026-06-15):

- **`main`** = full dev source (everything: `_bot`/`bots`, `_gf_debug`, `_gf_bridge`/RCON, `tools/`, `.claude/`; `mod.ff` is gitignored here). The real history. Develop on `main`; push with `tools/push_all.ps1`. **Keep pushing main** — it's the only branch with history/tooling.
- **`release`** = the **GitHub default branch** (what a fresh clone gets). A *generated orphan snapshot*, force-pushed as a single commit by `package_release.ps1 -PublishBranch` (no history → no binary bloat). `git checkout main` after cloning to develop.
- **`release` branch and the Release zip carry the SAME minimal content** (branch = browsable/clonable, zip = download): `mod.ff` + gameplay GSC + generated README + GETTING_STARTED. Dropped: the dev files in `$DevFiles` (`_bot`, `bots/_bot_*`, `_gf_bridge`, `_gf_debug`) by filename, AND every `// #strip-begin … // #strip-end` region (ONE strip style now — NOT categorized features/debug). Staged GSC is also comment-stripped unless `-KeepComments`. Markers are inert `//` on main. GitHub Releases are tag-based, independent of the default branch.

**Scripts** (all in `tools/`, ASCII-only for PS 5.1): `build_ff.ps1` (build mod.ff), `package_release.ps1 [ver] -PublishBranch -Publish` (zip + force-push release branch + GH Release), `package_server.ps1` (PRIVATE VPS bundle = full main mirror + mod.ff + dedicated.cfg — carries rcon_password, never public), `push_all.ps1` (stage/commit/push), `deploy.ps1` (VPS-side git-pull applier). `tools/dist/` gitignored.

**Release-ordering gotcha (learned 2026-07-03):** GitHub marks "Latest" by the tag's CREATED-DATE, not semver — so cutting a LOWER version number LATER makes it "Latest" AND (since `-Publish` tags `--target release` and `-PublishBranch` force-pushes the branch) drags the `release` branch backward to it. This exact bug happened: `0.5.3` was cut, then `0.5.2` was cut after → `0.5.2` became Latest and owned the branch. Always bump monotonically; to repair, cut a clearly-higher version and `gh release delete <bad> --cleanup-tag --yes`. Current release after cleanup: **0.5.4** (release branch tip `f184a7a`); published line is now monotonic 0.4.8 → 0.5.1 → 0.5.3 → 0.5.4.

**Deploy direction:** `deploy.ps1` runs ON the VPS clone (`C:\gfdeploy\BO1-Gunfight`) as Administrator — the INVERSE of the packagers. `-Mod` = pull main + check `mod.ff` out of `release` + mirror to the live mods folder + FastDL copy to IIS + restart (bootstrapper taskkill → restart-loop relaunch, which re-execs `dedicated.cfg`). `-Web` = mirror `site/wwwroot` to IIS (secret-scanned, web.config preserved). See [[vps-launch-bat-and-maxclients-latch]], [[build-stage-transitive-menu]], [[t5-clients-must-install-mod-no-autodownload]].
