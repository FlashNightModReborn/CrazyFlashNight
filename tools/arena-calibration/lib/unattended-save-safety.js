"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { sha256OfValue } = require("./arena-calibration-core");

const MAIN_SWF = "CRAZYFLASHER7MercenaryEmpire.swf";

function originSuffixes(swfOrigin) {
  const parsed = path.parse(swfOrigin);
  const relative = swfOrigin.slice(parsed.root.length).split(/[\\/]/).filter(Boolean);
  const variants = [["localhost", ...relative]];
  if (/^[A-Za-z]:/.test(parsed.root)) variants.push(["localhost", parsed.root[0], ...relative]);
  return variants;
}

function assertOrdinaryDirectory(directory) {
  if (fs.lstatSync(directory).isSymbolicLink()) {
    throw new Error(`save origin contains a reparse/symlink directory: ${directory}`);
  }
}

function solOriginDirectories(root, options = {}) {
  const appData = options.appData === undefined ? process.env.APPDATA : options.appData;
  if (!appData) throw new Error("APPDATA is required to verify protected Flash saves");
  const sharedRoot = path.join(path.resolve(appData), "Macromedia", "Flash Player", "#SharedObjects");
  if (!fs.existsSync(sharedRoot)) return [];
  assertOrdinaryDirectory(sharedRoot);
  const canonicalRoot = fs.realpathSync(root);
  const requestedSwf = path.resolve(options.swfOrigin || path.join(canonicalRoot, MAIN_SWF));
  const swfOrigin = fs.existsSync(requestedSwf) ? fs.realpathSync(requestedSwf) : requestedSwf;
  if (path.dirname(swfOrigin).toLowerCase() !== canonicalRoot.toLowerCase()
      || path.basename(swfOrigin).toLowerCase() !== MAIN_SWF.toLowerCase()) {
    throw new Error("SWF origin is not the canonical main SWF under the requested root");
  }
  const variants = originSuffixes(swfOrigin);
  const directories = new Set();
  for (const hashEntry of fs.readdirSync(sharedRoot, { withFileTypes: true })) {
    if (hashEntry.isSymbolicLink()) throw new Error("SharedObjects contains a reparse/symlink hash directory");
    if (!hashEntry.isDirectory()) continue;
    const hashRoot = path.join(sharedRoot, hashEntry.name);
    assertOrdinaryDirectory(hashRoot);
    for (const variant of variants) {
      const origin = path.join(hashRoot, ...variant);
      if (!fs.existsSync(origin)) continue;
      let current = hashRoot;
      for (const part of variant) {
        current = path.join(current, part);
        assertOrdinaryDirectory(current);
      }
      directories.add(origin);
    }
  }
  return [...directories].sort();
}

function listSolFilesForOrigin(root, options = {}) {
  const files = [];
  const slots = new Map();
  for (const origin of solOriginDirectories(root, options)) {
    for (const entry of fs.readdirSync(origin, { withFileTypes: true })) {
      if (!/\.sol$/i.test(entry.name)) continue;
      if (!entry.isFile() || entry.isSymbolicLink()) throw new Error(`unsupported SOL entry: ${entry.name}`);
      const slot = entry.name.slice(0, -4);
      const key = slot.toLowerCase();
      if (slots.has(key)) throw new Error(`ambiguous SOL origin for slot ${slot}: multiple exact origin files`);
      slots.set(key, true);
      files.push({ slot, filePath: path.join(origin, entry.name) });
    }
  }
  return files;
}

function findSolFiles(root, slot, options = {}) {
  if (!/^[A-Za-z0-9_-]+$/.test(slot)) throw new Error("unsafe SOL slot name");
  return listSolFilesForOrigin(root, options)
    .filter((entry) => entry.slot.toLowerCase() === slot.toLowerCase()).map((entry) => entry.filePath);
}

function fileFingerprint(root, filePath, slot, kind) {
  const bytes = fs.readFileSync(filePath);
  const relative = path.relative(root, filePath);
  const pathKey = crypto.createHash("sha256").update(path.resolve(filePath).toLowerCase(), "utf8").digest("hex").slice(0, 16);
  return {
    key: `${kind}:${slot}:${pathKey}`, kind, slot,
    path: relative.startsWith("..") ? `${kind}/${path.basename(filePath)}` : relative.replace(/\\/g, "/"),
    sha256: `sha256:${crypto.createHash("sha256").update(bytes).digest("hex")}`,
    size: bytes.length,
  };
}

function captureProtectedSaveSnapshot(root, targetSlot, options = {}) {
  const savesDir = path.join(root, "saves");
  const files = [];
  // Walk save payloads and backups independently of the live JSON index. This
  // also covers custom slots and SOL-only slots without reading another origin.
  const walk = (directory) => {
    if (!fs.existsSync(directory)) return;
    assertOrdinaryDirectory(directory);
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`unsupported save reparse entry: ${full}`);
      if (entry.isDirectory()) {
        if (entry.name !== targetSlot) walk(full);
      } else if (entry.isFile() && /\.json(?:\..*)?$/i.test(entry.name)
          && !entry.name.startsWith(".") && entry.name !== `${targetSlot}.json`) {
        const slot = entry.name.split(".json")[0];
        files.push(fileFingerprint(root, full, slot, "shadow_json"));
      }
    }
  };
  walk(savesDir);
  for (const entry of listSolFilesForOrigin(root, options)) {
    if (entry.slot.toLowerCase() !== targetSlot.toLowerCase()) {
      files.push(fileFingerprint(root, entry.filePath, entry.slot, "flash_sol"));
    }
  }
  files.sort((a, b) => a.key.localeCompare(b.key));
  return {
    capturedAt: new Date().toISOString(), targetSlot, files,
    snapshotHash: sha256OfValue(files.map(({ key, sha256, size }) => ({ key, sha256, size }))),
  };
}

// The coordinator owns this wider boundary. Workers cannot exempt each other
// by a prefix: every writable SOL is one explicitly listed full origin + slot.
function captureGlobalProtectionSnapshot(options) {
  if (!options || !Array.isArray(options.saveRoots) || !Array.isArray(options.allowedTargets)
      || !path.isAbsolute(options.sharedObjectsRoot || "")) throw new Error("explicit global save protection roots are required");
  const sharedRoot = path.resolve(options.sharedObjectsRoot);
  const allowed = options.allowedTargets.map((target) => {
    if (!target || !path.isAbsolute(target.swfOrigin || "") || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(target.slot || "")) {
      throw new Error("global writable targets require an exact SWF origin and dedicated slot");
    }
    const parent = fs.realpathSync(path.dirname(target.swfOrigin));
    const swfOrigin = path.join(parent, path.basename(target.swfOrigin));
    if (path.basename(swfOrigin).toLowerCase() !== MAIN_SWF.toLowerCase()) throw new Error("invalid allowed SWF origin");
    return { swfOrigin, slot: target.slot,
      jsonPath: path.join(parent, "saves", `${target.slot}.json`).toLowerCase(),
      suffixes: originSuffixes(swfOrigin).map((parts) => [...parts, `${target.slot}.sol`].join("/").toLowerCase()) };
  });
  const files = [];
  const seen = new Set();
  const walk = (directory, kind) => {
    if (!fs.existsSync(directory)) return;
    assertOrdinaryDirectory(directory);
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`global protection found a reparse/symlink entry: ${full}`);
      if (entry.isDirectory()) walk(full, kind);
      else if (entry.isFile()) {
        if (kind === "flash_sol" && !/\.sol$/i.test(entry.name)) continue;
        const relative = path.relative(sharedRoot, full).split(path.sep).slice(1).join("/").toLowerCase();
        if (allowed.some((target) => kind === "flash_sol" ? target.suffixes.includes(relative) : target.jsonPath === full.toLowerCase())) continue;
        const key = full.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        files.push(fileFingerprint(directory, full, path.basename(full), kind));
      }
    }
  };
  options.saveRoots.forEach((root) => {
    if (!path.isAbsolute(root)) throw new Error("global save roots must be absolute");
    walk(path.resolve(root), "shadow_file");
  });
  walk(sharedRoot, "flash_sol");
  files.sort((a, b) => a.key.localeCompare(b.key));
  return { schema: "arena-worker.global-save-snapshot.v1", capturedAt: new Date().toISOString(),
    saveRoots: options.saveRoots.map((root) => path.resolve(root)), sharedObjectsRoot: sharedRoot,
    allowedTargets: allowed.map(({ swfOrigin, slot }) => ({ swfOrigin, slot })), files,
    snapshotHash: sha256OfValue(files.map(({ key, sha256, size }) => ({ key, sha256, size }))) };
}

module.exports = { captureGlobalProtectionSnapshot, captureProtectedSaveSnapshot, findSolFiles,
  listSolFilesForOrigin, solOriginDirectories };
