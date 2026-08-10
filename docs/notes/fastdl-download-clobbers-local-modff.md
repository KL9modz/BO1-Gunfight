# FastDL auto-download clobbers your local mod.ff build

**Date:** 2026-08-09 **Status:** structural — cannot be fixed away, only worked around

## The symptom

You edit a compiled asset (`localizedstrings/*.str`, `ui_mp/*.menu`, `mp/gametypesTable.csv`, an
`.efx`), run `tools/build_ff.ps1`, it succeeds — and the game still shows the OLD content. Everything
you check says the change is fine: the source file has it, the linker printed `done.`, the copy
printed the right byte count.

Live case: `"+1 Elimination"` → `"+1 Kill"` in `gf.str`. Built clean at 00:28. Half an hour later the
game was still saying "+1 Elimination", with nothing in the source or the build to explain it.

## The cause

**The mod folder is TWO things at once**, and this is what nobody remembers under pressure:

1. the git repo / build output target (`storage\t5\mods\mp_gunfight\`), and
2. the **Plutonium CLIENT's** FastDL download directory for that same mod.

So when you join the live server to look at your change, the client checks the server's `mod.ff`
checksum, sees it differs from yours (it does — yours is the new one), and **downloads the server's
copy straight over your build.** Your `mod.ff` is gone. You then test against the deployed artifact
and conclude your edit didn't work.

It is the download working exactly as designed ([[t5-clients-must-install-mod-no-autodownload]]) —
the auto-update that makes players' lives easy eats the developer's build, because for this one
machine the two directories are the same directory.

## The tell

Compare the `mod.ff` in the mod folder against what the build actually produced in
`<GameRoot>\zone\english\mod.ff`:

```
zone\english\mod.ff   22,208 B   00:28   <- linker output, has "+1 Kill"
mods\mp_gunfight\..   22,624 B   00:58   <- 30 min NEWER, different size, has "+1 Elimination"
```

A mod folder `mod.ff` **newer than your build** is the whole story. Confirm it by hashing against the
release blob — in the live case they matched exactly:

```powershell
git cat-file blob origin/release:mod.ff > rel.ff   # md5 a89587...  == the clobbered local copy
```

## How to see what is actually INSIDE an ff

Never infer it. `tools/inflate_fastfile_zlib.ps1` already exists for this (zlib stream at offset 12;
localized strings sit near the end as plain text):

```powershell
.\tools\inflate_fastfile_zlib.ps1 -FastFile .\mod.ff -OutFile out.bin
Select-String -Path out.bin -Pattern '\+1 Kill' -Encoding default
```

⚠ Do NOT write a second inflater — one was reinvented in Node during this incident before the
existing tool was noticed.

## What to do

- **Testing a `mod.ff` change locally:** use a LOCAL server. Do not join the live server in between —
  it re-clobbers every time. `map_restart` is also not enough for a zone change; the client must
  reload the fastfile (`loadMod` / reconnect).
- **Getting it live:** rebuild → `package_release.ps1 <ver> -PublishBranch` → `deploy.ps1 -Mod` on the
  box. `mod.ff` reaches the VPS ONLY via the `release` branch ([[modff-drift-vs-gsc-deploy]]) — a
  `main` push carries GSC and nothing else.
- **Recovering your build after a clobber:** copy it back from `<GameRoot>\zone\english\mod.ff`; the
  linker output is untouched by the download.

## Do not conclude

- ...that the edit failed, or that the linker read the wrong source. Check the *artifact* first.
- ...that a stray `raw\english\localizedstrings\*.str` did it. One WAS present and stale here and was
  a red herring — the freshly built ff contained no trace of the old string at all.
- ...that a matching hash across two builds proves anything. `build_ff.ps1` is **not**
  byte-deterministic ([[modff-drift-vs-gsc-deploy]]): the same compiled sources gave **22,208 /
  22,240 / 22,368 bytes on three consecutive runs** during this incident. A hash identifies **one
  artifact**, so it answers "is this file the one I built?" — never
  "are these two builds equivalent?" For that, compare SIZE and expect stale = smaller.

Related: [[build-stage-transitive-menu]], [[fastdl-first-join-black-screen-rebuild]].
