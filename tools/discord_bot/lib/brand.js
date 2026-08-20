'use strict';
/*
 * The house style. ONE place decides what a Black Ops Bot card looks like, so a feature written
 * six months from now matches the ones written today without its author having to know the rules.
 *
 * ⚠ This is the edit surface for branding. Changing a colour here restyles every card the bot has
 * ever posted from that moment on; a feature that hardcodes its own hex is the bug this file
 * exists to prevent.
 *
 * Colours are taken from the SITE, not invented: --accent #ff7a1a ("gunfight orange") and
 * --accent-2 #ffb066 in site/wwwroot's stylesheet. Keeping them equal is what makes Discord and
 * gunfight.us look like one product.
 */

// Semantic, never literal. A feature asks for DANGER, not for red, so the day the palette changes
// nothing has to be re-reasoned about.
const FOOTER = 'gunfight.us';

const COLOR = {
  BRAND:      0xff7a1a,   // site --accent, "gunfight orange"
  BRAND_SOFT: 0xffb066,   // site --accent-2, links / hover
  OK:         0x57f287,
  INFO:       0x5865f2,
  WARN:       0xfee75c,
  DANGER:     0xed4245,
  MUTED:      0x99aab5,
};

// ── the card format ────────────────────────────────────────────────────────────────────────────
// ⚠ DETAIL GOES IN A FIELD, NEVER IN THE DESCRIPTION, and that is a NOTIFICATION decision rather
// than a styling one. Proven on a real device: a mobile push shows `content` verbatim when it is
// present, and otherwise flattens the embed TITLE + DESCRIPTION - so anything in a description
// lands on a lock screen, raw markdown and all. A field renders identically in the channel and
// never reaches the push. Hence the house shape: a one-line title, and the detail under __Details__.
//
// The underscores underline the label (field NAMES render markdown; the bold is the default).
const DETAILS = '__Details__';

// Discord's hard caps. Over either one the whole message is rejected, so a hostile display name or
// a long map list gets clamped rather than trusted.
const TITLE_MAX = 256, FIELD_MAX = 1024, DESC_MAX = 4096, NAME_MAX = 128;

const clamp = (t, n) => {
  const s = String(t == null ? '' : t);
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
};

// Label/value lines for a __Details__ block. Every feature's detail block is built through this, so
// they all bold the label and separate identically.
const detailLines = (pairs) => pairs
  .filter(([, v]) => v !== null && v !== undefined && v !== '')
  .map(([k, v]) => `**${k}:** ${v}`)
  .join('\n');

/*
 * Build a card. Everything is optional except a title.
 *
 *   card({ title, color, details: [['User', tag], ['Channel', chip]], footer: true })
 *
 * `details` is the label/value list; pass `fields` instead when a feature genuinely needs several
 * blocks side by side (Discord lays out up to three inline fields per row).
 *
 * ⚠ `footer` is OPT-IN. A footer on a card that arrives ten at a time - the voice log - is noise,
 * while a footer on a standalone announcement is branding. The default is therefore off, and the
 * feature decides.
 */
function card(o) {
  const e = { title: clamp(o.title, TITLE_MAX), color: o.color === undefined ? COLOR.BRAND : o.color };
  if (o.url) e.url = o.url;
  if (o.description) e.description = clamp(o.description, DESC_MAX);

  const fields = [];
  if (o.details && o.details.length) {
    const v = detailLines(o.details);
    if (v) fields.push({ name: o.detailsLabel || DETAILS, value: clamp(v, FIELD_MAX) });
  }
  for (const f of (o.fields || [])) {
    fields.push({ name: clamp(f.name, TITLE_MAX), value: clamp(f.value, FIELD_MAX), inline: Boolean(f.inline) });
  }
  if (fields.length) e.fields = fields;

  if (o.thumbnail) e.thumbnail = { url: o.thumbnail };
  if (o.image) e.image = { url: o.image };
  if (o.footer) e.footer = { text: typeof o.footer === 'string' ? o.footer : FOOTER };
  // Discord renders its own relative timestamp from this, which is better than us formatting one:
  // it is correct in every reader's own zone.
  if (o.timestamp !== false) e.timestamp = new Date(o.timestamp || Date.now()).toISOString();
  return e;
}

// Chips. <@id> and <#id> render as clickable pills and CANNOT ping as long as the message also
// sets allowed_mentions parse:[] - which lib/rest.js does on every write, so a feature cannot
// forget it.
const userTag  = (id) => `<@${id}>`;
const roleTag  = (id) => `<@&${id}>`;
const chanChip = (id) => `<#${id}>`;
// ⚠ An embed TITLE is plain text - it renders no chip and would print the raw <#123> token. Titles
// take names, fields take chips. Every card in this bot follows that split.

const plural = (n, one, many) => `${n} ${n === 1 ? one : (many || one + 's')}`;

module.exports = { COLOR, DETAILS, FOOTER, TITLE_MAX, FIELD_MAX, DESC_MAX, NAME_MAX,
                   clamp, detailLines, card, userTag, roleTag, chanChip, plural };
