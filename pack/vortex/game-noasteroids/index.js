'use strict';
// ============================================================
//  Vortex game extension: No Asteroids (v2.0.0)
//
//  - Registers the game so Vortex can manage it (mods deploy
//    into the game root).
//  - The "Mod Menu" mod (v2.x) installs an in-game menu via
//    Patch-ModMenu.ps1 (full asar rebuild). This extension
//    watches deployments:
//      * mod deployed + menu installed  -> OK, nothing to do
//      * mod deployed + menu missing    -> warn: run the
//                                          Install bat once
//      * mod removed  + menu installed  -> restore vanilla
//                                          app.asar from the
//                                          .bak backup
//      * mod removed  + legacy 1.x patch-> restore vanilla
//  - All actions are logged to noasteroids-vortex-log.txt in
//    the game folder. If anything fails, nothing is modified.
// ============================================================
const path = require('path');
const crypto = require('crypto');
const fsp = require('fs').promises;

const GAME_ID = 'noasteroids';
const GAME_NAME = 'No Asteroids';
const EXE = 'No Asteroids.exe';

const PATCH_SCRIPT = 'Patch-ModMenu.ps1';
const MENU_MARKER = 'NoAsteroidsModMenu';
const STATE_FILE = 'modmenu-state.txt';
const LOG_FILE = 'noasteroids-vortex-log.txt';

// ---------- legacy 1.x patch detection (for clean restores) ----------
const SLOT1_VAN = 'wo.lo+(n>>>0)%1e4/1e4*wo.span';
const SLOT2_NEW = 'function Eo(e,t){return So[t]?xee(e,t)-1:0' + '     ' + '}';
const LEGACY_WO_NEW = 'var wo={lo:3.,span:2.4}';
const TO_FN = 'function To(e,t){return Math.round(So[t]*xee(e,t))}';
const TABLE = { 2: ['1.5', '1.2'], 4: ['3.', '2.4'], 6: ['4.5', '3.6'], 8: ['6', '4.8'], 16: ['12', '9.6'] };

function slot1For(m) {
  const t = TABLE[m];
  const pad = Math.max(0, 8 - t[0].length - t[1].length);
  return t[0] + ' '.repeat(pad) + ' + (n>>>0)%1e4/1e4 * ' + t[1];
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

async function appendLog(gamePath, msg) {
  try {
    const line = '[' + new Date().toISOString() + '] ' + msg + '\n';
    await fsp.appendFile(path.join(gamePath, LOG_FILE), line, 'utf8');
  } catch (err) {
    // logging must never break the flow
  }
}

// ---------- asar parsing ----------
function matchEntry(hdr) {
  return hdr.match(new RegExp(
    '"(index-[^"]*\\.js)":\\{"size":(\\d+),"offset":"(\\d+)"' +
    ',"integrity":\\{"algorithm":"[A-Z0-9]+","hash":"([0-9a-f]{64})"' +
    ',"blockSize":(\\d+),"blocks":\\[[^\\]]*\\]'));
}

async function readMeta(filePath) {
  const fh = await fsp.open(filePath, 'r');
  try {
    const b16 = Buffer.alloc(16);
    await fh.read(b16, 0, 16, 0);
    const jsonLen = b16.readUInt32LE(12);
    let D = 16 + jsonLen;
    const probe = Buffer.alloc(1);
    for (;;) {
      const { bytesRead } = await fh.read(probe, 0, 1, D);
      if (bytesRead === 0 || probe[0] !== 0) break;
      D += 1;
    }
    const hdrBuf = Buffer.alloc(jsonLen);
    await fh.read(hdrBuf, 0, jsonLen, 16);
    const hdr = hdrBuf.toString('latin1');
    const m = matchEntry(hdr);
    if (!m) throw new Error('game bundle entry not found in asar header');
    return {
      jsonLen, D, hdr,
      size: parseInt(m[2], 10),
      relOff: parseInt(m[3], 10),
      storedHash: m[4].toLowerCase(),
      S: D + parseInt(m[3], 10),
    };
  } finally {
    await fh.close();
  }
}

async function readSlice(filePath, pos, len) {
  const fh = await fsp.open(filePath, 'r');
  try {
    const buf = Buffer.alloc(len);
    await fh.read(buf, 0, len, pos);
    return buf;
  } finally {
    await fh.close();
  }
}

function countOf(hay, needle) {
  let c = 0, i = 0;
  for (;;) {
    const j = hay.indexOf(needle, i);
    if (j < 0) return c;
    c += 1;
    i = j + needle.length;
  }
}

// ---------- state detection ----------
// vanilla: SLOT1 once, no SLOT2_NEW, no legacy wo
// legacy1x: legacy wo (v1.0) or any slot1For(m) (v1.1)
// menu: MENU_MARKER present
function classify(txt) {
  if (txt.indexOf(MENU_MARKER) >= 0) return { kind: 'menu' };
  const c1v = countOf(txt, SLOT1_VAN);
  const c2n = countOf(txt, SLOT2_NEW);
  const cLegacy = countOf(txt, LEGACY_WO_NEW);
  const toFn = countOf(txt, TO_FN);
  if (cLegacy === 1 && c2n === 1 && c1v === 1) return { kind: 'legacy10', m: 4 };
  for (const k of Object.keys(TABLE)) {
    if (countOf(txt, slot1For(parseInt(k, 10))) === 1 && c2n === 1 && c1v === 0 && cLegacy === 0 && toFn === 1) {
      return { kind: 'legacy11', m: parseInt(k, 10) };
    }
  }
  if (c1v === 1 && c2n === 0 && cLegacy === 0 && toFn === 1) return { kind: 'vanilla' };
  return { kind: 'unknown' };
}

async function detectState(asarPath) {
  const meta = await readMeta(asarPath);
  const slice = await readSlice(asarPath, meta.S, meta.size);
  return { meta, liveHash: sha256(slice), state: classify(slice.toString('latin1')) };
}

// ---------- restore primitive ----------
// Full-file restore from the pristine backup (covers menu and legacy patches).
// The backup's bundle slice is integrity-checked against its header hash first.
async function restoreVanilla(gamePath) {
  const asar = path.join(gamePath, 'resources', 'app.asar');
  const bak = asar + '.bak';
  try { await fsp.access(bak); } catch (err) {
    await appendLog(gamePath, 'ERROR: no vanilla backup (app.asar.bak) found - aborting restore');
    return false;
  }
  const bakMeta = await readMeta(bak);
  const bakSlice = await readSlice(bak, bakMeta.S, bakMeta.size);
  if (sha256(bakSlice) !== bakMeta.storedHash) {
    await appendLog(gamePath, 'ERROR: app.asar.bak failed integrity check - aborting restore');
    return false;
  }
  await fsp.copyFile(bak, asar);
  const after = await readSlice(asar, bakMeta.S, bakMeta.size);
  if (sha256(after) !== bakMeta.storedHash) {
    await appendLog(gamePath, 'ERROR: post-restore verification failed');
    return false;
  }
  try { await fsp.unlink(path.join(gamePath, STATE_FILE)); } catch (err) { /* fine */ }
  await appendLog(gamePath, 'RESTORED (app.asar from backup)');
  return true;
}

// ---------- deployment integration ----------
let capturedGamePath = undefined;
let warnedMissingMenu = false;

async function ensurePatchState(gamePath, notifyFn) {
  try {
    if (!gamePath) return;
    const asar = path.join(gamePath, 'resources', 'app.asar');
    let haveAsar = true;
    try { await fsp.access(asar); } catch (err) { haveAsar = false; }
    if (!haveAsar) {
      await appendLog(gamePath, 'NO-OP (resources\\app.asar not found)');
      return;
    }
    const det = await detectState(asar);
    const st = det.state.kind;

    let modDeployed = false;
    try { await fsp.access(path.join(gamePath, PATCH_SCRIPT)); modDeployed = true; } catch (err) { /* not deployed */ }

    if (modDeployed) {
      if (st === 'menu') {
        warnedMissingMenu = false;
        await appendLog(gamePath, 'OK (mod menu installed)');
      } else {
        await appendLog(gamePath,
          'WARN: mod files deployed but the in-game menu is NOT installed in app.asar (state=' +
          st + '). Double-click Install-Mod-Menu.bat in the game folder once.');
        try {
          if (notifyFn && !warnedMissingMenu) {
            warnedMissingMenu = true;
            notifyFn('No Asteroids: run Install-Mod-Menu.bat',
              'The Mod Menu mod is deployed but the game is not patched yet. ' +
              'Open the game folder and double-click Install-Mod-Menu.bat (game closed).');
          }
        } catch (err2) { /* notification API optional */ }
      }
    } else {
      // no mod files deployed
      if (st === 'menu') {
        await appendLog(gamePath, 'Mod removed - restoring vanilla app.asar');
        await restoreVanilla(gamePath);
      } else if (st === 'legacy10' || st === 'legacy11') {
        await appendLog(gamePath, 'Legacy 1.x patch present, mod removed - restoring vanilla app.asar');
        await restoreVanilla(gamePath);
      } else if (st === 'unknown') {
        await appendLog(gamePath, 'CAUTION: app.asar in an unknown state and no mod deployed - leaving untouched');
      } else {
        await appendLog(gamePath, 'NO-OP (mod not deployed, game vanilla)');
      }
      warnedMissingMenu = false;
    }
  } catch (err) {
    try { await appendLog(gamePath, 'ERROR: ' + err.message); } catch (e2) { /* nothing more we can do */ }
  }
}

function main(context) {
  const notifyFn = (title, message) => {
    if (context.api && typeof context.api.sendNotification === 'function') {
      context.api.sendNotification({ type: 'warning', title, message });
    }
  };

  context.registerGame({
    id: GAME_ID,
    name: GAME_NAME,
    mergeMods: true,
    queryPath: () => Promise.resolve(undefined), // user selects the game folder manually once
    supportedTools: [],
    queryModPath: () => '.',
    executable: () => EXE,
    requiredFiles: [EXE, 'resources/app.asar'],
    setup: (discovery) => {
      capturedGamePath = (discovery !== undefined) ? discovery.path : undefined;
      return Promise.resolve();
    },
    environment: {},
    details: {},
  });

  context.once(() => {
    context.api.events.on('did-deploy', () => {
      ensurePatchState(capturedGamePath, notifyFn);
    });
    context.api.events.on('did-purge', () => {
      ensurePatchState(capturedGamePath, notifyFn);
    });
  });

  return true;
}

module.exports = {
  default: main,
};

// exposed for tests/debugging; Vortex only uses module.default
module.exports.engine = {
  detectState, restoreVanilla, ensurePatchState, classify,
  slot1For, TABLE, LOG_FILE, PATCH_SCRIPT, MENU_MARKER,
};
