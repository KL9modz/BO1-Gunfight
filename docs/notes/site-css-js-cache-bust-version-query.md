---
name: site-css-js-cache-bust-version-query
description: Editing site styles.css/setup.js requires bumping its ?v=N query in the HTML or browsers keep the stale cached copy
metadata: 
  node_type: memory
  type: project
  originSessionId: 99e4770a-1c43-4150-a560-f497b0516c47
  modified: 2026-07-20T23:40:48.890Z
---

The public site (`site/wwwroot`) cache-busts its static assets with a **`?v=N` query
string** on the `<link>`/`<script>` tag, because IIS serves `.css`/`.js` with a long
cache lifetime but `.html` with a short one. So after a `deploy.ps1 -Web`, a returning
visitor gets the **new HTML but the OLD cached stylesheet/script** unless the version
number changes — the URL is the only cache key the browser has.

**Rule: any edit to `styles.css` or `setup.js` MUST bump its `?v=` number in the same
change, in every HTML file that references it.** Forgetting this is silent — the deploy
succeeds, the asset is live on the server (verify with `WebFetch https://gunfight.us/styles.css`),
and it *still* looks broken in the browser because the browser never refetches.

Symptom that fingerprints this exactly: **new HTML elements appear but their new CSS
doesn't apply** (unstyled/overflowing layout). Fix = bump `?v=` and redeploy; a user can
work around it once with Ctrl+F5 (empty-cache hard reload).

- `styles.css` is referenced only by `index.html` + `setup.html` (status/admin have their
  own styling). Bump both together.
- Bit us live 2026-07-20: `styles.css` was edited (added `pre.oneline`/`.copybox`) but left
  at `?v=4`, so the Setup page's new copy-button box rendered unstyled and off-screen even
  though the server had the correct CSS. Bumped to `v=5`.

Related: [[modff-drift-vs-gsc-deploy]] (the analogous "the artifact shipped but the change
didn't propagate" trap on the mod.ff side), [[deploy-recycles-box-services]].
