'use strict';
/*
 * Buffered attachments, so a DELETED message can still show what was attached to it.
 *
 * ── WHY THE BYTES HAVE TO BE HELD ──────────────────────────────────────────────────────────────
 * ⚠ There is no way to fetch a deleted message's attachment afterwards. Discord's CDN links are
 * signed and expiring (`?ex=&is=&hm=`), refreshing a signature requires the message to still exist,
 * and once it is gone the link is unreliable at best. So an attachment can only be logged if it was
 * downloaded WHILE the message was alive. Every media-logging bot works this way; the honest cost
 * is that the box briefly holds a copy of anything anyone uploads.
 *
 * ── WHICH MAKES THE CAPS THE DESIGN ────────────────────────────────────────────────────────────
 * This runs on the machine that runs the game server, and the input is arbitrary user uploads. The
 * limits below are not tuning, they are the safety model:
 *
 *   MAX_FILE   a single file bigger than this is never downloaded. Its metadata is still logged,
 *              so the card says a 40MB video was deleted rather than silently omitting it.
 *   MAX_TOTAL  a hard ceiling across everything held. Oldest go first.
 *   TTL        nothing is kept longer than this. The window only has to cover "posted, then
 *              deleted", which is minutes, not hours.
 *
 * ⚠ MEMORY, NOT DISK, and that is deliberate twice over: nothing survives a restart (so a crash
 * cannot leave a pile of other people's files on the box), and the ceiling is enforced by one
 * counter rather than by trusting a cleanup job.
 *
 * ⚠ Nothing here ever EXECUTES or inspects a file. It is bytes in, bytes back out to Discord.
 */

const MAX_FILE  = 8 * 1024 * 1024;    // per attachment. Discord's own default upload cap is 10MB.
const MAX_TOTAL = 64 * 1024 * 1024;   // across the whole cache
const TTL_MS    = 15 * 60 * 1000;
// A delete can land while the download is still in flight. Waiting briefly turns a race into a
// slightly slower card; waiting indefinitely would hang the log on a slow CDN.
const RACE_WAIT_MS = 3000;

module.exports = function makeAttachments(log) {
  const held = new Map();   // messageId -> { at, bytes, promise }
  let total = 0;

  const evictOldest = () => {
    const k = held.keys().next().value;
    if (k === undefined) return false;
    drop(k);
    return true;
  };

  function drop(id) {
    const e = held.get(id);
    if (!e) return;
    total -= e.bytes;
    held.delete(id);
  }

  function sweep() {
    const cutoff = Date.now() - TTL_MS;
    for (const [id, e] of held) {
      if (e.at >= cutoff) break;        // insertion order: the first fresh row ends the sweep
      drop(id);
    }
  }

  async function download(a) {
    const res = await fetch(a.url);
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const buf = Buffer.from(await res.arrayBuffer());
    // ⚠ Re-checked AFTER the download: `size` is what the uploader's client claimed, and the only
    // number we can trust is the one we actually received.
    if (buf.length > MAX_FILE) throw new Error('larger than declared');
    return { filename: a.filename, contentType: a.contentType || null, buf };
  }

  return {
    MAX_FILE, MAX_TOTAL, TTL_MS,

    /*
     * Called on MESSAGE_CREATE. Fire and forget: the gateway handler must not wait on a CDN, and a
     * failed download is a card that says so rather than a crash.
     */
    remember(messageId, attachments) {
      if (!attachments || !attachments.length) return;
      const wanted = attachments.filter((a) => a.size <= MAX_FILE);
      if (!wanted.length) return;

      sweep();
      const entry = { at: Date.now(), bytes: 0, promise: null };
      held.set(messageId, entry);

      entry.promise = Promise.all(wanted.map((a) => download(a).catch((e) => {
        log(`attachment: ${a.filename} not buffered - ${e.message}`);
        return null;
      }))).then((files) => {
        const got = files.filter(Boolean);
        entry.bytes = got.reduce((n, f) => n + f.buf.length, 0);
        total += entry.bytes;
        // ⚠ Evict AFTER accounting, and never the row we just added - a single upload larger than
        // whatever is left would otherwise loop evicting itself.
        while (total > MAX_TOTAL && held.size > 1) { if (!evictOldest()) break; }
        return got;
      });
      entry.promise.catch(() => {});    // the awaiter handles it; this only stops an unhandled rejection
    },

    /*
     * Called on MESSAGE_DELETE. Returns [{filename, contentType, buf}] and forgets them - a logged
     * attachment has done its job, and holding it longer is only risk.
     */
    async take(messageId) {
      const e = held.get(messageId);
      if (!e) return [];
      let files = [];
      try {
        files = await Promise.race([
          e.promise,
          new Promise((r) => setTimeout(() => r(null), RACE_WAIT_MS)),
        ]) || [];
      } catch { files = []; }
      drop(messageId);
      return files;
    },

    forget: drop,
    stats: () => ({ messages: held.size, bytes: total }),
  };
};
