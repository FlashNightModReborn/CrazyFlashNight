#!/usr/bin/env node
"use strict";

// Prepare a disposable, full-backpack save for the map-loot target_full path.
// It intentionally works only on cf7_agent_* shadows; live saves are read-only seeds.

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");
const LegacyHttpClient = require("./lib/legacy-http-client");

const DEFAULT_SEED_SLOT = "crazyflasher7_saves";
const DEFAULT_TARGET_SLOT = "cf7_agent_loot_target_full_v1";
const AGENT_SLOT_RE = /^cf7_agent_[A-Za-z0-9_-]+$/;
const SAFE_SLOT_RE = /^[A-Za-z0-9_-]+$/;
const LIVE_SLOT_RE = /^crazyflasher7_saves\d*$/;
const SLOT_COUNT = 50;

class PrepareError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "PrepareError";
    this.code = code;
    this.details = details || null;
    this.isUsageError = ["unknown_argument", "missing_argument_value", "conflicting_verification_modes"].includes(code);
  }
}

function fail(code, message, details) {
  throw new PrepareError(code, message, details);
}

function projectRoot() {
  return path.resolve(__dirname, "..");
}

function parseArgs(argv) {
  const args = {
    seedSlot: DEFAULT_SEED_SLOT,
    slot: DEFAULT_TARGET_SLOT,
    verifyOnly: false,
    verifyContentOnly: false,
    root: projectRoot(),
    help: false,
  };
  function valueAfter(index, option) {
    if (index + 1 >= argv.length || String(argv[index + 1]).startsWith("--")) {
      fail("missing_argument_value", option + " requires a value");
    }
    return argv[index + 1];
  }
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--seed-slot") args.seedSlot = valueAfter(index++, token);
    else if (token === "--slot") args.slot = valueAfter(index++, token);
    else if (token === "--root") args.root = valueAfter(index++, token);
    else if (token === "--verify-only") args.verifyOnly = true;
    else if (token === "--verify-content-only") args.verifyContentOnly = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail("unknown_argument", "unknown argument: " + token);
  }
  if (args.verifyOnly && args.verifyContentOnly) {
    fail("conflicting_verification_modes", "--verify-only and --verify-content-only are mutually exclusive");
  }
  args.root = path.resolve(args.root);
  return args;
}

function printHelp() {
  console.log([
    "Usage: node tools/prepare-loot-target-full-save.js [options]",
    "",
    "Clones a valid shadow into a dedicated cf7_agent_* slot and fills its 0..49 backpack slots.",
    "The seed is never changed. A running Launcher/Flash must prove the target slot is not active.",
    "",
    "Options:",
    "  --seed-slot <slot>  Read-only source shadow. Default: " + DEFAULT_SEED_SLOT,
    "  --slot <slot>       Dedicated target. Default: " + DEFAULT_TARGET_SLOT,
    "  --verify-only       Strict pre-launch gate: verifies content and requires no target SOL; never writes.",
    "  --verify-content-only  Post-launch diagnostic: verifies shadow JSON content but does not inspect or reject a target SOL; never writes.",
    "  --root <path>       Project root (mainly useful for isolated tests).",
  ].join("\n"));
}

function assertSafeArgs(args) {
  if (!AGENT_SLOT_RE.test(String(args.slot || "")) || LIVE_SLOT_RE.test(String(args.slot || ""))) {
    fail("unsafe_target_slot", "target slot must be a dedicated cf7_agent_* slot and can never be a live save slot");
  }
  if (!SAFE_SLOT_RE.test(String(args.seedSlot || "")) || String(args.seedSlot).includes("..")) {
    fail("unsafe_seed_slot", "seed slot must contain only letters, digits, underscore, or hyphen");
  }
  if (args.seedSlot === args.slot) {
    fail("seed_equals_target", "seed slot must differ from the dedicated target slot");
  }
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function isValidSaveData(data) {
  if (!isPlainObject(data) || data.version !== "3.0" || typeof data.lastSaved !== "string" || !data.lastSaved) return false;
  if (!Array.isArray(data["0"]) || data["0"].length < 14 || data["0"][0] == null || Number.isNaN(Number(data["0"][3]))) return false;
  if (!Array.isArray(data["1"]) || data["1"].length < 28 || !Array.isArray(data["4"]) || data["4"].length < 2 || !Array.isArray(data["5"]) || !Array.isArray(data["7"]) || data["7"].length < 5) return false;
  if (!isPlainObject(data.inventory) || !isPlainObject(data.inventory["背包"]) || !isPlainObject(data.collection) || !isPlainObject(data.infrastructure)) return false;
  if (!isPlainObject(data.tasks) || !Array.isArray(data.tasks.tasks_to_do) || !isPlainObject(data.tasks.tasks_finished) || !isPlainObject(data.tasks.task_chains_progress)) return false;
  if (!isPlainObject(data.pets) || !Array.isArray(data.pets["宠物信息"]) || data.pets["宠物信息"].length < 5 || data.pets["宠物领养限制"] == null) return false;
  return isPlainObject(data.shop) && Array.isArray(data.shop["商城已购买物品"]) && Array.isArray(data.shop["商城购物车"]);
}

function isLegalInventoryEntry(value) {
  return isPlainObject(value)
    && typeof value.name === "string" && value.name.trim() !== ""
    && Object.prototype.hasOwnProperty.call(value, "value");
}

function exactScenarioAssertions(data) {
  const inspected = inspectBackpack(data);
  return {
    numericAntibioticStackPresent: inspected.donors.some((entry) => (
      entry.name === "抗生素"
      && typeof entry.value === "number"
      && Number.isFinite(entry.value)
      && entry.value > 0
    )),
    darkGuitarAbsent: !inspected.donors.some((entry) => entry.name === "黑暗吉他"),
  };
}

function assertExactScenario(data) {
  const assertions = exactScenarioAssertions(data);
  if (!assertions.numericAntibioticStackPresent) {
    fail("antibiotic_stack_missing", "exact target_full requires an existing positive numeric 抗生素 stack");
  }
  if (!assertions.darkGuitarAbsent) {
    fail("dark_guitar_already_present", "exact target_full requires 黑暗吉他 to be absent before map loot");
  }
  return assertions;
}

function sha256Buffer(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function sha256File(filePath) {
  return fs.existsSync(filePath) ? sha256Buffer(fs.readFileSync(filePath)) : null;
}

function saveJsonPath(root, slot) {
  return path.join(root, "saves", String(slot) + ".json");
}

function tombstonePath(root, slot) {
  return path.join(root, "saves", String(slot) + ".tombstone");
}

function readValidSave(filePath, code) {
  let raw;
  let data;
  try {
    raw = fs.readFileSync(filePath, "utf8");
    data = JSON.parse(raw);
  } catch (error) {
    fail(code, "could not read valid shadow JSON: " + filePath, { cause: error.message });
  }
  if (!isValidSaveData(data)) fail(code, "shadow JSON has an unsupported or invalid save schema: " + filePath);
  return { raw, data, sha256: sha256Buffer(Buffer.from(raw, "utf8")) };
}

function localTimestamp(date) {
  const value = date || new Date();
  const pad = (number) => String(number).padStart(2, "0");
  return value.getFullYear() + "-" + pad(value.getMonth() + 1) + "-" + pad(value.getDate())
    + " " + pad(value.getHours()) + ":" + pad(value.getMinutes()) + ":" + pad(value.getSeconds());
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function inspectBackpack(data) {
  const bag = data.inventory && data.inventory["背包"];
  if (!isPlainObject(bag)) fail("invalid_backpack", "save inventory.背包 must be an object");
  const occupied = [];
  const donors = [];
  Object.keys(bag).forEach((key) => {
    if (!/^(0|[1-9]\d*)$/.test(key)) fail("invalid_backpack_slot", "backpack contains a non-numeric slot key: " + key);
    const slot = Number(key);
    if (!Number.isInteger(slot) || slot < 0 || slot >= SLOT_COUNT) {
      fail("invalid_backpack_slot", "backpack contains an out-of-range slot: " + key);
    }
    if (!isLegalInventoryEntry(bag[key])) fail("invalid_inventory_entry", "backpack slot " + key + " is not a legal inventory entry");
    occupied.push(slot);
    donors.push(bag[key]);
  });
  occupied.sort((a, b) => a - b);
  return { bag, occupied, donors };
}

function fillBackpack(data, nowMs) {
  const before = inspectBackpack(data);
  const empty = [];
  for (let slot = 0; slot < SLOT_COUNT; slot += 1) {
    if (!Object.prototype.hasOwnProperty.call(before.bag, String(slot))) empty.push(slot);
  }
  if (empty.length && !before.donors.length) {
    fail("no_legal_donor", "cannot fill an empty backpack without an existing legal inventory entry");
  }
  const base = Number.isFinite(nowMs) ? Math.floor(nowMs) : Date.now();
  const inserted = [];
  empty.forEach((slot, index) => {
    const clone = deepClone(before.donors[index % before.donors.length]);
    clone.lastUpdate = base + index + 1;
    before.bag[String(slot)] = clone;
    inserted.push(slot);
  });
  const after = inspectBackpack(data);
  const uniqueInsertedUpdates = new Set(inserted.map((slot) => after.bag[String(slot)].lastUpdate)).size === inserted.length;
  return {
    beforeOccupied: before.occupied,
    insertedSlots: inserted,
    afterOccupied: after.occupied,
    assertions: {
      sourceEntriesLegal: before.donors.every(isLegalInventoryEntry),
      filledOnlyPreviouslyEmptySlots: inserted.every((slot) => !before.occupied.includes(slot)),
      insertedLastUpdatesIndependent: uniqueInsertedUpdates,
      slots0To49Full: after.occupied.length === SLOT_COUNT && after.occupied.every((slot, index) => slot === index),
    },
  };
}

function solOwnershipSuffix(root, slot) {
  const absoluteRoot = path.resolve(root);
  const localRoot = path.relative(path.parse(absoluteRoot).root, absoluteRoot);
  return path.join("localhost", localRoot, "CRAZYFLASHER7MercenaryEmpire.swf", String(slot) + ".sol");
}

function isOwnedSolPath(root, slot, candidatePath) {
  return path.resolve(candidatePath).toLowerCase().endsWith((path.sep + solOwnershipSuffix(root, slot)).toLowerCase());
}

function findSolFiles(root, slot, sharedObjectsRoot) {
  const sharedRoot = sharedObjectsRoot || (process.env.APPDATA && path.join(process.env.APPDATA, "Macromedia", "Flash Player", "#SharedObjects"));
  if (!sharedRoot || !fs.existsSync(sharedRoot)) return [];
  const expected = String(slot) + ".sol";
  const found = [];
  const stack = [sharedRoot];
  while (stack.length) {
    const directory = stack.pop();
    let entries;
    try { entries = fs.readdirSync(directory, { withFileTypes: true }); } catch (_error) { continue; }
    entries.forEach((entry) => {
      const candidate = path.join(directory, entry.name);
      if (entry.isDirectory()) stack.push(candidate);
      else if (entry.isFile() && entry.name === expected && isOwnedSolPath(root, slot, candidate)) found.push(candidate);
    });
  }
  return found.sort();
}

function backupFile(filePath, backupDir, label) {
  if (!fs.existsSync(filePath)) return null;
  fs.mkdirSync(backupDir, { recursive: true });
  const destination = path.join(backupDir, label + "-" + path.basename(filePath));
  fs.copyFileSync(filePath, destination);
  return destination;
}

function relativeOrAbsolute(root, filePath) {
  const relative = path.relative(root, filePath);
  return !relative.startsWith("..") && !path.isAbsolute(relative) ? relative.replace(/\\/g, "/") : filePath;
}

function statusSlots(status) {
  let value = status;
  if (value && isPlainObject(value.result)) value = value.result;
  else if (value && isPlainObject(value.status)) value = value.status;
  else if (value && isPlainObject(value.data)) value = value.data;
  if (!isPlainObject(value)) fail("runtime_status_incomplete", "running Launcher returned no usable agent-control status");
  const candidates = [
    value.save && value.save.slot,
    value.saveRuntime && value.saveRuntime.savePath,
    value.slot,
    value.currentSlot,
  ].filter((entry) => entry != null).map(String);
  if (!candidates.length) {
    fail("runtime_status_incomplete", "running Launcher status did not expose an active or selected save slot", value);
  }
  return candidates;
}

function slotReferenceKeys(value, root) {
  const text = String(value).trim();
  const pathLike = path.isAbsolute(text) || /[\\/]/.test(text) || /\.json$/i.test(text);
  const slotName = pathLike ? path.basename(text, path.extname(text)) : text;
  const keys = new Set(["slot:" + slotName.toLowerCase()]);
  if (root) {
    const absolute = pathLike ? path.resolve(root, text) : saveJsonPath(root, text);
    keys.add("path:" + path.resolve(absolute).replace(/\//g, "\\").toLowerCase());
  }
  return keys;
}

function assertTargetSlotNotInUse(status, targetSlot, root) {
  const slots = statusSlots(status);
  const targetKeys = slotReferenceKeys(targetSlot, root);
  const targetInUse = slots.some((slot) => {
    for (const key of slotReferenceKeys(slot, root)) {
      if (targetKeys.has(key)) return true;
    }
    return false;
  });
  if (targetInUse) {
    fail("target_slot_in_use", "dedicated target slot is already selected by a running Launcher or Flash instance", { slots, targetSlot });
  }
  return slots;
}

function requestJson(port, method, pathname, body, timeoutMs, legacyHttpContext) {
  return new Promise((resolve, reject) => {
    const payload = body == null ? "" : JSON.stringify(body);
    let authorizationHeaders;
    try {
      authorizationHeaders = LegacyHttpClient.authorizationHeadersFor(
        legacyHttpContext,
        pathname
      );
    } catch (error) {
      reject(error);
      return;
    }
    const request = http.request({
      hostname: "localhost", port, method, path: pathname, timeout: timeoutMs || 1500,
      headers: Object.assign(
        body == null
          ? {}
          : {
              "Content-Type": "application/json",
              "Content-Length": Buffer.byteLength(payload)
            },
        authorizationHeaders
      ),
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        let json = null;
        try { json = JSON.parse(text); } catch (_error) { /* caller decides whether this is a safe status */ }
        resolve({ statusCode: response.statusCode, text, json });
      });
    });
    request.on("timeout", () => request.destroy(new Error("request timed out")));
    request.on("error", reject);
    request.end(payload);
  });
}

function isConnectionAbsent(error) {
  return error && ["ECONNREFUSED", "ENETUNREACH", "EHOSTUNREACH"].includes(error.code);
}

async function queryAgentStatus(legacyHttpContext) {
  const port = legacyHttpContext.httpPort;
  let identity;
  try {
    identity = await requestJson(
      port, "POST", "/testConnection", null, null, legacyHttpContext);
  } catch (error) {
    if (isConnectionAbsent(error)) return { reachable: false, status: null, socketPort: null };
    fail("runtime_status_unavailable", "unknown listener on localhost:" + port + " could not be identified as Launcher HTTP", { cause: error.message });
  }
  const identityStatus = new URLSearchParams(identity.text.trim()).get("status");
  if (identity.statusCode < 200 || identity.statusCode >= 300 || identityStatus !== "success") {
    fail("runtime_status_unavailable", "unknown HTTP listener on localhost:" + port + " did not provide the Launcher identity endpoint", { response: identity.text.slice(0, 300) });
  }
  let socketInfo;
  try {
    socketInfo = await requestJson(
      port, "GET", "/getSocketPort", null, null, legacyHttpContext);
  } catch (error) {
    fail("runtime_status_unavailable", "Launcher HTTP on localhost:" + port + " did not declare its paired socket port", { cause: error.message });
  }
  const socketText = new URLSearchParams(socketInfo.text.trim()).get("socketPort");
  const socketPort = /^\d+$/.test(socketText || "") ? Number(socketText) : NaN;
  if (socketInfo.statusCode < 200 || socketInfo.statusCode >= 300
      || !Number.isInteger(socketPort) || socketPort < 1 || socketPort > 65535 || socketPort === port) {
    fail("runtime_status_unavailable", "Launcher HTTP on localhost:" + port + " returned an invalid paired socket port", { response: socketInfo.text.slice(0, 300) });
  }
  let task;
  try {
    task = await requestJson(
      port,
      "POST",
      "/task",
      { task: "agent_control", action: "status" },
      null,
      legacyHttpContext);
  } catch (error) {
    fail("runtime_status_unavailable", "reachable localhost:" + port + " did not provide a safe agent-control status", { cause: error.message });
  }
  if (task.statusCode >= 200 && task.statusCode < 300 && isPlainObject(task.json) && (task.json.success === true || task.json.ok === true)) {
    return { reachable: true, status: task.json, socketPort };
  }
  fail("runtime_status_unavailable", "reachable localhost:" + port + " did not provide a successful agent-control status", { task: task.text.slice(0, 300) });
}

async function assertTargetNotRunning(root, targetSlot, options) {
  const opts = options || {};
  const injectedPorts = Array.isArray(opts.ports) ? opts.ports.slice() : null;
  let exactContext = null;
  let ports = injectedPorts;
  if (ports === null) {
    const portsFile = path.join(root, "launcher_ports.json");
    if (!fs.existsSync(portsFile)) ports = [];
    else {
      exactContext = LegacyHttpClient.readExactLauncherHttpContext(
        root,
        opts.legacyHttpOptions || {});
      ports = [exactContext.httpPort];
    }
  }
  const statusQuery = typeof opts.queryAgentStatus === "function"
    ? opts.queryAgentStatus
    : (port) => {
        if (!exactContext || port !== exactContext.httpPort) {
          fail(
            "runtime_status_unavailable",
            "authenticated exact launcher_ports.json context is required",
            {port});
        }
        return queryAgentStatus(exactContext);
      };
  const instances = [];
  const pairedSocketPorts = new Set();
  const skippedSocketPorts = new Set();
  for (const port of ports) {
    if (pairedSocketPorts.has(port)) {
      skippedSocketPorts.add(port);
      continue;
    }
    const result = await statusQuery(port);
    if (!isPlainObject(result) || typeof result.reachable !== "boolean") {
      fail("runtime_status_unavailable", "Launcher status probe returned an invalid result for localhost:" + port);
    }
    if (!result.reachable) continue;
    if (Number.isInteger(result.socketPort)) pairedSocketPorts.add(result.socketPort);
    instances.push({
      port,
      socketPort: Number.isInteger(result.socketPort) ? result.socketPort : null,
      slots: assertTargetSlotNotInUse(result.status, targetSlot, root),
    });
  }
  return {
    port: instances.length ? instances[0].port : null,
    slots: Array.from(new Set(instances.reduce((all, instance) => all.concat(instance.slots), []))),
    instances,
    skippedSocketPorts: Array.from(skippedSocketPorts),
  };
}

function defaultBackupDir(root, slot) {
  const stamp = new Date().toISOString().replace(/[-:.]/g, "");
  return path.join(root, "tmp", "loot-target-full-save", stamp + "-" + process.pid + "-" + slot, "backups");
}

function writeMinifiedJsonAtomic(targetPath, data) {
  const payload = Buffer.from(JSON.stringify(data), "utf8");
  const temporary = targetPath + ".tmp-" + process.pid + "-" + Date.now();
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(temporary, payload);
  try { fs.renameSync(temporary, targetPath); } catch (error) {
    try { fs.unlinkSync(temporary); } catch (_ignored) { /* best-effort cleanup */ }
    throw error;
  }
  return sha256Buffer(payload);
}

function verifyPreparedTarget(root, slot, sharedObjectsRoot, options) {
  const opts = options || {};
  const requireTargetSolAbsent = opts.requireTargetSolAbsent !== false;
  const targetPath = saveJsonPath(root, slot);
  const tombstone = tombstonePath(root, slot);
  const solFiles = findSolFiles(root, slot, sharedObjectsRoot).map((filePath) => relativeOrAbsolute(root, filePath));
  const targetSolAbsent = solFiles.length === 0;
  const report = {
    verificationScope: requireTargetSolAbsent ? "pre-launch-ready" : "shadow-content-only",
    runtimeSolContentInspected: false,
    targetPath: relativeOrAbsolute(root, targetPath),
    before: { sha256: sha256File(targetPath) },
    after: { sha256: sha256File(targetPath) },
    occupied: { before: [], after: [] },
    assertions: {},
    observations: { targetSolAbsent },
    solFiles,
  };
  if (fs.existsSync(tombstone)) fail("target_tombstoned", "target has a tombstone and is not loadable: " + tombstone);
  const target = readValidSave(targetPath, "invalid_target_shadow");
  const inspected = inspectBackpack(target.data);
  report.occupied.before = inspected.occupied;
  report.occupied.after = inspected.occupied;
  report.assertions = {
    targetValidShadow: true,
    targetTombstoneAbsent: true,
    slots0To49Full: inspected.occupied.length === SLOT_COUNT && inspected.occupied.every((slotNumber, index) => slotNumber === index),
    allEntriesLegal: inspected.donors.every(isLegalInventoryEntry),
  };
  if (requireTargetSolAbsent) report.assertions.targetSolAbsent = targetSolAbsent;
  Object.assign(report.assertions, exactScenarioAssertions(target.data));
  if (!Object.values(report.assertions).every(Boolean)) fail("target_verification_failed", "target does not satisfy target_full save assertions", report);
  return report;
}

function verifyPreparedContent(root, slot, sharedObjectsRoot) {
  return verifyPreparedTarget(root, slot, sharedObjectsRoot, { requireTargetSolAbsent: false });
}

function prepareTarget(root, args, options) {
  const opts = options || {};
  const seedPath = saveJsonPath(root, args.seedSlot);
  const targetPath = saveJsonPath(root, args.slot);
  const targetTombstone = tombstonePath(root, args.slot);
  const seed = readValidSave(seedPath, "invalid_seed_shadow");
  const beforeSha = sha256File(targetPath);
  const backupDir = opts.backupDir || defaultBackupDir(root, args.slot);
  const solFiles = findSolFiles(root, args.slot, opts.sharedObjectsRoot);
  const clone = deepClone(seed.data);
  const fill = fillBackpack(clone, opts.nowMs);
  const exactAssertions = assertExactScenario(clone);
  clone.lastSaved = localTimestamp(opts.now || new Date());
  const backups = [];
  const backupTargets = [
    [targetPath, "target-json"],
    [targetTombstone, "target-tombstone"],
  ].concat(solFiles.map((filePath, index) => [filePath, "target-sol-" + String(index + 1)]));
  backupTargets.forEach(([filePath, label]) => {
    const backup = backupFile(filePath, backupDir, label);
    if (backup) backups.push(relativeOrAbsolute(root, backup));
  });

  // A stale target SOL or tombstone must not win over the newly prepared shadow.
  // Files are never parsed or edited: target-only artifacts are first copied verbatim.
  solFiles.forEach((filePath) => fs.unlinkSync(filePath));
  if (fs.existsSync(targetTombstone)) fs.unlinkSync(targetTombstone);
  const afterSha = writeMinifiedJsonAtomic(targetPath, clone);
  const verification = verifyPreparedTarget(root, args.slot, opts.sharedObjectsRoot);
  return {
    targetPath: relativeOrAbsolute(root, targetPath),
    seedPath: relativeOrAbsolute(root, seedPath),
    before: { sha256: beforeSha, occupied: fill.beforeOccupied },
    after: { sha256: afterSha, occupied: fill.afterOccupied },
    insertedSlots: fill.insertedSlots,
    backups,
    removedTargetSolFiles: solFiles.map((filePath) => relativeOrAbsolute(root, filePath)),
    removedTargetTombstone: backupTargets.some(([filePath]) => filePath === targetTombstone && fs.existsSync(path.join(backupDir, "target-tombstone-" + path.basename(targetTombstone)))),
    assertions: Object.assign({
      seedUnchanged: sha256File(seedPath) === seed.sha256,
      targetJsonMinifiedUtf8: fs.readFileSync(targetPath, "utf8") === JSON.stringify(JSON.parse(fs.readFileSync(targetPath, "utf8"))),
    }, fill.assertions, exactAssertions, verification.assertions),
    verification,
  };
}

async function run(args) {
  assertSafeArgs(args);
  if (args.verifyOnly) {
    const verification = verifyPreparedTarget(args.root, args.slot);
    return { ok: true, mode: "verify-only", targetSlot: args.slot, seedSlot: args.seedSlot, runtimeGuard: null, ...verification };
  }
  if (args.verifyContentOnly) {
    const verification = verifyPreparedContent(args.root, args.slot);
    return { ok: true, mode: "verify-content-only", targetSlot: args.slot, seedSlot: args.seedSlot, runtimeGuard: null, ...verification };
  }
  const runtimeGuard = await assertTargetNotRunning(args.root, args.slot);
  const prepared = prepareTarget(args.root, args);
  const report = { ok: true, mode: "prepare", targetSlot: args.slot, seedSlot: args.seedSlot, runtimeGuard, ...prepared };
  if (!Object.values(report.assertions).every(Boolean)) fail("post_write_assertion_failed", "prepared target failed a required assertion", report);
  return report;
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  console.log(JSON.stringify(await run(args)));
}

module.exports = {
  DEFAULT_SEED_SLOT,
  DEFAULT_TARGET_SLOT,
  PrepareError,
  assertSafeArgs,
  assertExactScenario,
  assertTargetNotRunning,
  assertTargetSlotNotInUse,
  fillBackpack,
  exactScenarioAssertions,
  findSolFiles,
  isLegalInventoryEntry,
  isOwnedSolPath,
  isValidSaveData,
  parseArgs,
  prepareTarget,
  solOwnershipSuffix,
  verifyPreparedContent,
  verifyPreparedTarget,
};

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(JSON.stringify({ ok: false, code: error.code || "unhandled_error", message: error.message, details: error.details || null }));
    process.exit(error.isUsageError ? 2 : 1);
  });
}
