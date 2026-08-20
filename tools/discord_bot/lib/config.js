'use strict';
/*
 * Config load + validation. Separated so every module reads the SAME object rather than re-parsing
 * the file, and so the fatal-on-missing behaviour lives in one place.
 */

const fs = require('fs');
const path = require('path');

const CFG_PATH = path.join(__dirname, '..', 'config.local.json');

function load() {
  if (!fs.existsSync(CFG_PATH)) {
    console.error(`FATAL: ${CFG_PATH} not found - copy config.example.json and fill it in.`);
    process.exit(1);
  }
  // ⚠ Strip a BOM before parsing. PowerShell's Set-Content -Encoding UTF8 and Windows Notepad both
  // write UTF-8 WITH a byte-order mark, and JSON.parse rejects it with a syntax error that points at
  // an invisible character - which is exactly how this file first failed to start. Any hand edit on
  // this box can reintroduce it, so the reader forgives it rather than the human remembering.
  const cfg = JSON.parse(fs.readFileSync(CFG_PATH, 'utf8').replace(/^﻿/, ''));
  for (const k of ['token', 'applicationId', 'guildId', 'adminRoleId']) {
    if (!cfg[k]) { console.error(`FATAL: config.local.json is missing "${k}"`); process.exit(1); }
  }
  return cfg;
}

module.exports = { load, CFG_PATH };
