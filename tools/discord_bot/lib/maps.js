'use strict';
/*
 * The BO1 map table: what players call a map, and what the engine calls it.
 *
 * ⚠ In lib/, not in a feature, because more than one thing needs it - /map today, and the
 * tournament map picker next. A second hand-typed copy of 26 map ids is how the two drift.
 *
 * The DISPLAY names are the ones the website and the alerts use, so a map reads the same in the
 * server browser, on gunfight.us and in Discord.
 */

// label (what a human types) -> engine id
const MAPS = {
  array: 'mp_array', cracked: 'mp_cracked', crisis: 'mp_crisis', firingrange: 'mp_firingrange',
  grid: 'mp_duga', hanoi: 'mp_hanoi', havana: 'mp_cairo', jungle: 'mp_havoc', launch: 'mp_cosmodrome',
  nuketown: 'mp_nuked', radiation: 'mp_radiation', summit: 'mp_mountain', villa: 'mp_villa',
  wmd: 'mp_russianbase', berlinwall: 'mp_berlinwall2', discovery: 'mp_discovery', kowloon: 'mp_kowloon',
  stadium: 'mp_stadium', convoy: 'mp_gridlock', hotel: 'mp_hotel', stockpile: 'mp_outskirts',
  zoo: 'mp_zoo', drivein: 'mp_drivein', hangar18: 'mp_area51', hazard: 'mp_golfcourse', silo: 'mp_silo',
};

const DISPLAY = {
  array: 'Array', cracked: 'Cracked', crisis: 'Crisis', firingrange: 'Firing Range',
  grid: 'Grid', hanoi: 'Hanoi', havana: 'Havana', jungle: 'Jungle', launch: 'Launch', nuketown: 'Nuketown',
  radiation: 'Radiation', summit: 'Summit', villa: 'Villa', wmd: 'WMD', berlinwall: 'Berlin Wall',
  discovery: 'Discovery', kowloon: 'Kowloon', stadium: 'Stadium', convoy: 'Convoy', hotel: 'Hotel',
  stockpile: 'Stockpile', zoo: 'Zoo', drivein: 'Drive-In', hangar18: 'Hangar 18', hazard: 'Hazard', silo: 'Silo',
};

// Reverse lookup, built once: the game reports mp_mountain, players know it as Summit.
const BY_ID = Object.fromEntries(Object.entries(MAPS).map(([label, id]) => [id, DISPLAY[label]]));

// ⚠ Falls through to the raw mp_* rather than to "unknown": an id we do not know is still more
// useful on screen than a shrug, and it names the map to add to this table.
const mapName = (id) => BY_ID[id] || id || 'unknown map';

const labels = () => Object.keys(MAPS);
const idOf = (label) => MAPS[String(label || '').toLowerCase().replace(/[^a-z0-9]/g, '')] || null;

module.exports = { MAPS, DISPLAY, BY_ID, mapName, labels, idOf };
