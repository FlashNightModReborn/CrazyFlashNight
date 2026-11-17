'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const AGENT_SLOT_REGEX = /^cf7_agent_[A-Za-z0-9_-]{1,64}$/;

function isValidAgentSlot(slot) {
  return typeof slot === 'string' && AGENT_SLOT_REGEX.test(slot);
}

function assertAgentSlot(slot, context = 'slot') {
  if (!isValidAgentSlot(slot)) {
    throw new Error(`Invalid agent ${context}: "${slot}". Must match ${AGENT_SLOT_REGEX.toString()}`);
  }
}

function assertSafeSlotReadName(slot) {
  if (typeof slot !== 'string' || !slot.trim() || !/^[A-Za-z0-9._-]+$/.test(slot) || slot.includes('..')) {
    throw new Error(`Unsafe slot name: "${slot}"`);
  }
}

function findFlashSharedObjectDirs() {
  const appData = process.env.APPDATA;
  if (!appData) return [];
  const root = path.join(appData, 'Macromedia', 'Flash Player', '#SharedObjects');
  if (!fs.existsSync(root)) return [];

  const result = [];
  for (const profileEntry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!profileEntry.isDirectory()) continue;
    const profileDir = path.join(root, profileEntry.name);
    for (const host of ['localhost', '127.0.0.1']) {
      const hostDir = path.join(profileDir, host);
      if (fs.existsSync(hostDir) && fs.statSync(hostDir).isDirectory()) {
        result.push(hostDir);
      }
    }
  }
  return result;
}

function hashFile(filePath) {
  const h = crypto.createHash('sha256');
  h.update(fs.readFileSync(filePath));
  return h.digest('hex');
}

function walkProtectedFiles(dir, predicate, out) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkProtectedFiles(full, predicate, out);
    } else if (entry.isFile()) {
      if (predicate(entry.name, full)) {
        const st = fs.statSync(full);
        out[full] = {
          size: st.size,
          mtimeMs: Math.trunc(st.mtimeMs),
          sha256: hashFile(full)
        };
      }
    }
  }
}

/**
 * Captures an exact byte/metadata baseline of every non-`cf7_agent_*` save file in `<projectRoot>/saves`
 * and every non-`cf7_agent_*` `.sol` file in Flash Player `#SharedObjects`.
 */
function snapshotPlayerSaves(projectRoot) {
  const absRoot = path.resolve(projectRoot);
  const files = {};

  const savesDir = path.join(absRoot, 'saves');
  walkProtectedFiles(
    savesDir,
    (name) => !name.startsWith('cf7_agent_'),
    files
  );

  for (const solDir of findFlashSharedObjectDirs()) {
    walkProtectedFiles(
      solDir,
      (name) => !name.startsWith('cf7_agent_'),
      files
    );
  }

  return {
    capturedAtUtc: new Date().toISOString(),
    projectRoot: absRoot,
    fileCount: Object.keys(files).length,
    files
  };
}

function verifyPlayerSavesUnchanged(baseline) {
  if (!baseline || !baseline.files) {
    throw new Error('Invalid baseline passed to verifyPlayerSavesUnchanged');
  }
  const current = snapshotPlayerSaves(baseline.projectRoot);
  const violations = [];

  for (const [filePath, prev] of Object.entries(baseline.files)) {
    const now = current.files[filePath];
    if (!now) {
      violations.push({ type: 'deleted', path: filePath, prev });
      continue;
    }
    if (now.sha256 !== prev.sha256 || now.size !== prev.size) {
      violations.push({ type: 'modified', path: filePath, prev, now });
    }
  }

  for (const [filePath, now] of Object.entries(current.files)) {
    if (!baseline.files[filePath]) {
      violations.push({ type: 'created', path: filePath, now });
    }
  }

  return {
    ok: violations.length === 0,
    checkedFiles: baseline.fileCount,
    violations
  };
}

module.exports = {
  AGENT_SLOT_REGEX,
  isValidAgentSlot,
  assertAgentSlot,
  assertSafeSlotReadName,
  findFlashSharedObjectDirs,
  snapshotPlayerSaves,
  verifyPlayerSavesUnchanged
};
