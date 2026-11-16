'use strict';

const fs = require('fs');
const path = require('path');
const {
  assertAgentSlot,
  assertSafeSlotReadName,
  findFlashSharedObjectDirs,
  isValidAgentSlot
} = require('./player-save-guard');

function getSavesDir(projectRoot) {
  return path.join(path.resolve(projectRoot), 'saves');
}

function summarizeSaveObject(slot, obj, filePath, stat) {
  const arr0 = Array.isArray(obj['0']) ? obj['0'] : [];
  const inv = obj.inventory && typeof obj.inventory === 'object' ? obj.inventory : {};
  const countItems = (bucket) => (bucket && typeof bucket === 'object' ? Object.keys(bucket).length : 0);
  return {
    slot,
    isAgentSlot: isValidAgentSlot(slot),
    roleName: typeof arr0[0] === 'string' ? arr0[0] : '',
    gender: typeof arr0[1] === 'string' ? arr0[1] : '',
    gold: Number(arr0[2]) || 0,
    level: Number(arr0[3]) || 0,
    exp: Number(arr0[4]) || 0,
    kpoints: Number(arr0[9]) || 0,
    mainProgress: obj['3'] !== undefined ? Number(obj['3']) : null,
    lastSaved: obj.lastSaved || null,
    version: obj.version || null,
    inventoryCounts: {
      backpack: countItems(inv['背包']),
      equipped: countItems(inv['装备栏']),
      drugs: countItems(inv['药剂栏']),
      warehouse: countItems(inv['仓库']),
      warReserve: countItems(inv['战备箱'])
    },
    sizeBytes: stat ? stat.size : undefined,
    mtimeUtc: stat ? new Date(stat.mtimeMs).toISOString() : undefined,
    filePath
  };
}

function listSaves({ projectRoot, includeBookruns = false }) {
  const savesDir = getSavesDir(projectRoot);
  if (!fs.existsSync(savesDir)) {
    return { savesDir, slots: [] };
  }
  const slots = [];
  for (const name of fs.readdirSync(savesDir)) {
    if (!name.endsWith('.json')) continue;
    if (name.startsWith('.')) continue;
    if (name === 'slot_catalog.json') continue;
    const slot = name.slice(0, -5);
    if (!includeBookruns && slot.startsWith('bookrun_')) continue;

    const full = path.join(savesDir, name);
    const stat = fs.statSync(full);
    if (!stat.isFile()) continue;
    try {
      const obj = JSON.parse(fs.readFileSync(full, 'utf8'));
      slots.push(summarizeSaveObject(slot, obj, full, stat));
    } catch (err) {
      slots.push({
        slot,
        isAgentSlot: isValidAgentSlot(slot),
        corrupt: true,
        error: err.message,
        filePath: full
      });
    }
  }
  slots.sort((a, b) => a.slot.localeCompare(b.slot));
  return { savesDir, slots };
}

function removeSolForAgentSlot(slot) {
  assertAgentSlot(slot);
  const removed = [];
  for (const dir of findFlashSharedObjectDirs()) {
    const solPath = path.join(dir, slot + '.sol');
    if (fs.existsSync(solPath)) {
      fs.unlinkSync(solPath);
      removed.push(solPath);
    }
  }
  return removed;
}

function cloneSave({ projectRoot, fromSlot, toSlot, patches }) {
  assertSafeSlotReadName(fromSlot);
  assertAgentSlot(toSlot, 'toSlot');

  const savesDir = getSavesDir(projectRoot);
  const srcPath = path.join(savesDir, fromSlot + '.json');
  if (!fs.existsSync(srcPath)) {
    throw new Error(`Source save not found: ${srcPath}`);
  }

  const data = JSON.parse(fs.readFileSync(srcPath, 'utf8'));
  if (!Array.isArray(data['0'])) {
    throw new Error(`Source save "${fromSlot}" does not contain valid mydata[0] array`);
  }

  if (patches && typeof patches === 'object') {
    if (patches.roleName !== undefined) data['0'][0] = String(patches.roleName);
    if (patches.gold !== undefined) data['0'][2] = Number(patches.gold);
    if (patches.money !== undefined) data['0'][2] = Number(patches.money);
    if (patches.level !== undefined) {
      const lvl = Number(patches.level);
      data['0'][3] = lvl;
      data['0'][8] = 1000 * lvl;
    }
    if (patches.skillPoints !== undefined) data['0'][6] = Number(patches.skillPoints);
    if (patches.kpoints !== undefined) data['0'][9] = Number(patches.kpoints);
    if (patches.mainProgress !== undefined) data['3'] = Number(patches.mainProgress);

    if (Array.isArray(patches.addItems) && patches.addItems.length > 0) {
      if (!data.inventory || typeof data.inventory !== 'object') data.inventory = {};
      const nowMs = Date.now();
      for (const spec of patches.addItems) {
        if (!spec || !spec.name) continue;
        const container = String(spec.container || '背包');
        if (!data.inventory[container] || typeof data.inventory[container] !== 'object') {
          data.inventory[container] = {};
        }
        const bucket = data.inventory[container];
        let nextIdx = 0;
        while (Object.prototype.hasOwnProperty.call(bucket, String(nextIdx)) && nextIdx < 200) {
          nextIdx++;
        }
        bucket[String(nextIdx)] = {
          name: String(spec.name),
          value: spec.value !== undefined ? spec.value : 1,
          lastUpdate: nowMs
        };
      }
    }
  }

  fs.mkdirSync(savesDir, { recursive: true });
  const dstPath = path.join(savesDir, toSlot + '.json');
  const tmpPath = dstPath + '.tmp';
  fs.writeFileSync(tmpPath, JSON.stringify(data), 'utf8');
  fs.renameSync(tmpPath, dstPath);

  for (const stale of [dstPath + '.deleted', path.join(savesDir, toSlot + '.tombstone')]) {
    if (fs.existsSync(stale)) fs.unlinkSync(stale);
  }
  const removedSol = removeSolForAgentSlot(toSlot);

  const stat = fs.statSync(dstPath);
  return {
    ok: true,
    fromSlot,
    toSlot,
    removedSolCount: removedSol.length,
    summary: summarizeSaveObject(toSlot, data, dstPath, stat)
  };
}

function inspectSave({ projectRoot, slot }) {
  assertSafeSlotReadName(slot);
  const savesDir = getSavesDir(projectRoot);
  const filePath = path.join(savesDir, slot + '.json');
  if (!fs.existsSync(filePath)) {
    throw new Error(`Save file not found: ${filePath}`);
  }
  const stat = fs.statSync(filePath);
  const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const inv = data.inventory || {};
  const listBucket = (name) => {
    const b = inv[name];
    if (!b || typeof b !== 'object') return [];
    return Object.entries(b).map(([key, item]) => ({
      slotKey: key,
      name: item && item.name ? item.name : null,
      value: item && item.value !== undefined ? item.value : null
    }));
  };

  return {
    ok: true,
    summary: summarizeSaveObject(slot, data, filePath, stat),
    backpack: listBucket('背包'),
    equipped: listBucket('装备栏'),
    drugs: listBucket('药剂栏'),
    shop: data.shop || null,
    collection: data.collection || null,
    settings: data.others ? data.others['设置'] : null
  };
}

function deleteAgentSave({ projectRoot, slot }) {
  assertAgentSlot(slot);
  const savesDir = getSavesDir(projectRoot);
  const removed = [];
  if (fs.existsSync(savesDir)) {
    for (const name of fs.readdirSync(savesDir)) {
      if (
        name === slot + '.json'
        || name === slot + '.json.deleted'
        || name === slot + '.tombstone'
        || name.startsWith(slot + '.json.previous-')
      ) {
        const full = path.join(savesDir, name);
        fs.unlinkSync(full);
        removed.push(full);
      }
    }
  }
  for (const sol of removeSolForAgentSlot(slot)) {
    removed.push(sol);
  }
  return { ok: true, slot, removed };
}

module.exports = {
  listSaves,
  cloneSave,
  inspectSave,
  deleteAgentSave
};
