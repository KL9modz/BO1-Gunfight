# `-Publish` and `-PublishBranch` are INDEPENDENT — one cuts the release, the other ships the build

**Date:** 2026-08-21, cutting 0.8.5. **Status: caught before deploy, no harm done.** Cost: a released
tag that pointed at the wrong snapshot for ~10 minutes, and a deploy that would have shipped a
three-day-old `mod.ff`.

## What happened

`package_release.ps1 0.8.5 -Publish` ran clean and printed `Published.` with a release URL. It looked
like a complete release. It was not:

- **`-Publish`** cuts the **GitHub Release** (`gh release create <ver> <zip> --target release`).
- **`-PublishBranch`** force-pushes the **`release` branch** as a fresh orphan commit carrying
  `mod.ff` + `mp_gunfight.iwd`.

Neither implies the other — they are two separate `if` blocks (`package_release.ps1` :295 and :328).
So `-Publish` alone uploads a correct, freshly-built **zip asset** while leaving the branch untouched.

## Why that is dangerous rather than cosmetic

⚠ **`deploy.ps1 -Mod` gets `mod.ff` from `origin/release`, not from your working tree.** `mod.ff` is
gitignored on `main`, so the branch is its only delivery path to the box. A `-Publish`-only release
therefore leaves the branch — and every subsequent deploy — on **whatever build was last
`-PublishBranch`ed**, which can be arbitrarily old. Here that was an **2026-08-18** build, so the
deploy would have shipped a `mod.ff` with none of the new camo table, none of the renumbered indices,
and the old `main.menu`: every custom camo would have rendered **white** on a client that trusted the
matching `.iwd`.

Second, `gh release create --target release` creates the tag **at the branch's current tip**. Publish
before the branch is updated and the tag names the *previous* snapshot, so the release page's source
links disagree with its own zip.

## The tell, and the fix

The branch's commit message is the tell — it is written by the packager and carries the version it was
built for. Ours read **`Release 0.8.6 (clean snapshot)`** while the newest tag was `0.8.4`: a version
that was never tagged and never released, i.e. someone had run `-PublishBranch 0.8.6` days earlier.
A branch whose version does not match the release you are cutting is the warning.

```
git log --oneline -1 origin/release                      # says which build the box will actually get
git cat-file -s $(git rev-parse origin/release:mod.ff)   # compare against your fresh mod.ff size
```

`preflight.ps1`'s **`origin/release mod.ff matches local size`** check exists for exactly this and is
the automated version of the same question — but note it compares **size**, and `build_ff.ps1` is not
byte-deterministic, so it catches a *stale* build (reliably a different size) and cannot prove two
builds are identical (see [modff-drift-vs-gsc-deploy](modff-drift-vs-gsc-deploy.md)).

**Pass BOTH flags for a real release:**

```powershell
.\tools\package_release.ps1 0.8.5 -PublishBranch -Publish
```

Order inside the script is already correct — the branch is force-pushed (:295) before the GitHub
Release is cut (:328) — so a single invocation tags the right snapshot. Recovering after the fact
means re-running with `-PublishBranch -SkipBuild`, then `git tag -f <ver> origin/release` and
`git push origin -f refs/tags/<ver>`.
