#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");
const { performance } = require("perf_hooks");
const LegacyHttpClient = require("../lib/legacy-http-client");
const {
  buildLauncherStartArguments,
  checkRuntimeIdentityContract,
  createRuntimeIdentityReport,
  recordObservedRuntimeIdentity,
  recordVerifiedRuntimeIdentity,
  resolveExpectedRuntimeIdentity,
  verifyRuntimeIdentity,
} = require("../lib/runtime-process-identity");
const { checkAgentEntryContract } = require("../test-agent-entry-contract");

const DEFAULT_AGENT_SLOT = "cf7_agent_equipment_tuning";
const AGENT_SLOT_RE = /^cf7_agent_[A-Za-z0-9_-]+$/;
const SAFE_SLOT_RE = /^[A-Za-z0-9_-]+$/;
const LIVE_SLOT_RE = /^crazyflasher7_saves\d*$/;
const HANDOFF_MARKER = "[BootstrapAS] event=handoff";
const TITLE_FRAME_MARKER = "[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared";
const REVEAL_WATCHDOG_MARKER = "[LaunchFlow] Flash reveal watchdog fired";
const AGENT_ENTER_COMMAND = "#func:_root.agentEnterResolvedSave()";
const LOG_TAIL_LIMIT = 2000;
const CLONE_BASELINE_STABLE_MS = 1000;
const CLONE_BASELINE_TIMEOUT_MS = 10000;
let activeLegacyHttpContext = null;

class RunnerError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "RunnerError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
    this.isUsageError = phase === "arguments";
  }
}

function fail(code, phase, message, details) {
  throw new RunnerError(code, phase, message, details);
}

function parseArgs(argv) {
  const args = {
    slot: DEFAULT_AGENT_SLOT,
    seedSlot: null,
    startLauncher: true,
    fresh: false,
    shutdown: false,
    readyTimeoutMs: 180000,
    panelTimeoutMs: 60000,
    pollMs: 500,
    report: null,
    reportMd: null,
    candidateRoot: null,
    check: false,
    help: false,
  };

  function valueAfter(index, option) {
    if (index + 1 >= argv.length || String(argv[index + 1]).startsWith("--")) {
      fail("missing_argument_value", "arguments", option + " requires a value");
    }
    return argv[index + 1];
  }

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--slot") args.slot = valueAfter(index++, token);
    else if (token === "--seed-slot") args.seedSlot = valueAfter(index++, token);
    else if (token === "--no-start-launcher") args.startLauncher = false;
    else if (token === "--fresh") args.fresh = true;
    else if (token === "--shutdown") args.shutdown = true;
    else if (token === "--ready-timeout-ms") args.readyTimeoutMs = Number(valueAfter(index++, token));
    else if (token === "--panel-timeout-ms") args.panelTimeoutMs = Number(valueAfter(index++, token));
    else if (token === "--poll-ms") args.pollMs = Number(valueAfter(index++, token));
    else if (token === "--report") args.report = valueAfter(index++, token);
    else if (token === "--report-md") args.reportMd = valueAfter(index++, token);
    else if (token === "--candidate-root") args.candidateRoot = valueAfter(index++, token);
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail("unknown_argument", "arguments", "unknown argument: " + token);
  }
  return args;
}

function printHelp() {
  console.log([
    "Usage: node tools/equipment-tuning/run-unattended.js --seed-slot <slot> [options]",
    "",
    "Opens the production equipment-tuning workbench on an isolated save clone,",
    "waits for the active workbench instance and its first authoritative tuning",
    "snapshot, then stops. It never clicks business controls or sends preview/commit.",
    "",
    "Options:",
    "  --slot <slot>              Dedicated target slot. Default: " + DEFAULT_AGENT_SLOT,
    "  --seed-slot <slot>         Required source shadow. Read-only; cloned before launch.",
    "  --no-start-launcher        Require an already running launcher.",
    "  --ready-timeout-ms <n>     Runtime readiness timeout. Default: 180000.",
    "  --panel-timeout-ms <n>     Workbench/snapshot evidence timeout. Default: 60000.",
    "  --poll-ms <n>              Status/log polling interval. Default: 500.",
    "  --report <file>            Diagnostic/open-only JSON path; live receipt gates require the default.",
    "  --report-md <file>         Diagnostic/open-only Markdown path; live receipt gates require the default.",
    "  --candidate-root <dir>     Run and bind to one immutable local runtime candidate.",
    "  --shutdown                 Ask launcher to shut down after reporting.",
    "  --fresh                    Always rejected; fresh save automation is forbidden.",
    "  --check                    Offline self-check; does not launch or touch saves.",
    "",
    "Safety:",
    "  The target must match cf7_agent_* and can never be crazyflasher7_saves*.",
    "  --seed-slot may name a live shadow because it is only read and cloned.",
    "  Without --candidate-root, runtimeMode=formal_runtime; with it, isolated_candidate.",
  ].join("\n"));
}

function assertSafeArgs(args) {
  if (args.fresh) {
    fail(
      "fresh_forbidden",
      "arguments",
      "--fresh is forbidden for unattended equipment tuning; use an explicit seeded clone"
    );
  }
  if (!AGENT_SLOT_RE.test(String(args.slot || "")) || LIVE_SLOT_RE.test(String(args.slot || ""))) {
    fail(
      "unsafe_target_slot",
      "arguments",
      "target slot must be a dedicated cf7_agent_* slot and can never be a live save slot"
    );
  }
  if (!args.seedSlot) {
    fail(
      "seed_slot_required",
      "arguments",
      "--seed-slot is required; implicit newest-save selection is not allowed"
    );
  }
  if (!isSafeSlotName(args.seedSlot)) {
    fail(
      "unsafe_seed_slot",
      "arguments",
      "--seed-slot must contain only letters, digits, underscore, or hyphen"
    );
  }
  if (args.seedSlot === args.slot) {
    fail(
      "seed_equals_target",
      "arguments",
      "--seed-slot must differ from the dedicated target slot"
    );
  }
  assertPositiveInteger(args.readyTimeoutMs, "--ready-timeout-ms", 1000);
  assertPositiveInteger(args.panelTimeoutMs, "--panel-timeout-ms", 1000);
  assertPositiveInteger(args.pollMs, "--poll-ms", 50);
}

function assertPositiveInteger(value, option, minimum) {
  if (!Number.isInteger(value) || value < minimum) {
    fail(
      "invalid_timeout",
      "arguments",
      option + " must be an integer greater than or equal to " + minimum
    );
  }
}

function isSafeSlotName(slot) {
  const text = String(slot || "");
  return SAFE_SLOT_RE.test(text) && text !== "." && text !== ".." && !text.includes("..");
}

function projectRoot() {
  return path.resolve(__dirname, "../..");
}

function timestampId(date) {
  const value = date || new Date();
  return value.toISOString().replace(/[-:]/g, "").replace(/\..+$/, "Z");
}

function toProjectRelative(root, filePath) {
  const relative = path.relative(root, filePath);
  if (!relative.startsWith("..") && !path.isAbsolute(relative)) {
    return relative.replace(/\\/g, "/");
  }
  return filePath;
}

function resolveOutputPath(root, filePath) {
  return path.isAbsolute(filePath) ? filePath : path.resolve(root, filePath);
}

function formatLocalSaveTimestamp(date) {
  const value = date || new Date();
  const pad = (number) => String(number).padStart(2, "0");
  return value.getFullYear() + "-" + pad(value.getMonth() + 1) + "-" + pad(value.getDate())
    + " " + pad(value.getHours()) + ":" + pad(value.getMinutes()) + ":" + pad(value.getSeconds());
}

const ORDER_INSENSITIVE_SOURCE_CACHE_KEYS = new Set([
  "completedChallengeQuests",
  "discoveredEnemies",
  "discoveredQuests",
  "discoveredStages",
]);

function canonicalizeCloneSemantic(value, trail) {
  const pathTrail = trail || [];
  const last = pathTrail.length > 0 ? pathTrail[pathTrail.length - 1] : "";
  if (Array.isArray(value)) {
    const projected = value.map((entry, index) => (
      canonicalizeCloneSemantic(entry, pathTrail.concat(String(index)))
    ));
    if (pathTrail.length === 3
        && pathTrail[0] === "others"
        && pathTrail[1] === "物品来源缓存"
        && ORDER_INSENSITIVE_SOURCE_CACHE_KEYS.has(last)) {
      projected.sort((left, right) => {
        const a = JSON.stringify(left);
        const b = JSON.stringify(right);
        return a < b ? -1 : a > b ? 1 : 0;
      });
    }
    return projected;
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value);
    if (last === "mods" && keys.length === 0) return [];
    const projected = {};
    keys.sort().forEach((key) => {
      if (pathTrail.length === 0 && key === "lastSaved") return;
      projected[key] = canonicalizeCloneSemantic(value[key], pathTrail.concat(key));
    });
    return projected;
  }
  return value;
}

function cloneSemanticSha256(data) {
  return crypto.createHash("sha256")
    .update(JSON.stringify(canonicalizeCloneSemantic(data, [])), "utf8")
    .digest("hex");
}

function isValidSaveData(data) {
  if (!data || data.version !== "3.0" || !data.lastSaved) return false;
  const player = data["0"];
  if (!Array.isArray(player) || player.length < 14) return false;
  if (player[0] == null || player[0] === "") return false;
  if (player[3] == null || Number.isNaN(Number(player[3]))) return false;
  if (!Array.isArray(data["1"]) || data["1"].length < 28) return false;
  if (!Array.isArray(data["4"]) || data["4"].length < 2) return false;
  if (!Array.isArray(data["5"])) return false;
  if (!Array.isArray(data["7"]) || data["7"].length < 5) return false;
  if (!data.inventory || !data.collection || !data.infrastructure) return false;
  if (!data.tasks || !Array.isArray(data.tasks.tasks_to_do)
      || !data.tasks.tasks_finished || !data.tasks.task_chains_progress) return false;
  if (!data.pets || !Array.isArray(data.pets["宠物信息"])
      || data.pets["宠物信息"].length < 5 || data.pets["宠物领养限制"] == null) return false;
  if (!data.shop || !Array.isArray(data.shop["商城已购买物品"])
      || !Array.isArray(data.shop["商城购物车"])) return false;
  return true;
}

function tryReadValidSave(filePath) {
  const snapshot = readRegularFileSnapshot(filePath, true, "save_seed");
  if (!snapshot) return null;
  try {
    const raw = snapshot.raw.toString("utf8");
    const data = JSON.parse(raw);
    if (!isValidSaveData(data)) return null;
    return { filePath, data, raw };
  } catch (_error) {
    return null;
  }
}

function saveJsonPath(root, slot) {
  return path.join(root, "saves", String(slot) + ".json");
}

function backupFile(source, backupDir, label) {
  const snapshot = readRegularFileSnapshot(source, true, "save_backup");
  if (!snapshot) return null;
  fs.mkdirSync(backupDir, { recursive: true });
  const destination = path.join(backupDir, label + "-" + path.basename(source));
  fs.writeFileSync(destination, snapshot.raw, { flag: "wx" });
  return destination;
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function sameBoundFileIdentity(left, right) {
  return !!left && !!right
    && left.dev === right.dev
    && left.ino === right.ino
    && left.size === right.size
    && left.mtimeNs === right.mtimeNs;
}

function assertRegularFileLstat(stat, filePath, phase) {
  if (!stat || !stat.isFile() || stat.isSymbolicLink()) {
    fail("regular_file_reparse", phase, "file must be regular and non-reparse", {
      path: filePath,
    });
  }
  return stat;
}

function assertCanonicalDirectoryChain(root, directory, phase) {
  const expectedRoot = path.resolve(root);
  const expectedDirectory = path.resolve(directory);
  const relative = path.relative(expectedRoot, expectedDirectory);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("directory_path_escape", phase, "directory escaped the exact project root");
  }
  const volumeRoot = path.parse(expectedDirectory).root;
  const segments = path.relative(volumeRoot, expectedDirectory).split(path.sep).filter(Boolean);
  let current = volumeRoot;
  for (const segment of segments) {
    current = path.join(current, segment);
    let stat;
    let realPath;
    try {
      stat = fs.lstatSync(current);
      realPath = fs.realpathSync.native(current);
    } catch (error) {
      fail("directory_chain_unavailable", phase, error.message, { path: current });
    }
    if (!stat.isDirectory() || stat.isSymbolicLink() || !samePath(realPath, current)) {
      fail(
        "directory_chain_reparse",
        phase,
        "directory chain must contain only exact non-reparse directories",
        { path: current, realPath }
      );
    }
  }
  return expectedDirectory;
}

function readRegularFileSnapshot(filePath, allowMissing, phase) {
  let before;
  try {
    before = fs.lstatSync(filePath, { bigint: true });
  } catch (error) {
    if (allowMissing && error && error.code === "ENOENT") return null;
    fail("regular_file_unavailable", phase, error.message, { path: filePath });
  }
  assertRegularFileLstat(before, filePath, phase);
  let realPath;
  try {
    realPath = fs.realpathSync.native(filePath);
  } catch (error) {
    fail("regular_file_realpath_failed", phase, error.message, { path: filePath });
  }
  if (!samePath(realPath, filePath)) {
    fail("regular_file_realpath_mismatch", phase, "file real path is not exact", {
      path: filePath,
      realPath,
    });
  }
  let raw;
  let opened;
  let afterHandle;
  let handle = null;
  try {
    handle = fs.openSync(filePath, "r");
    opened = fs.fstatSync(handle, { bigint: true });
    if (!opened.isFile() || !sameBoundFileIdentity(before, opened)) {
      fail("regular_file_changed_before_open", phase, "file identity changed before open", {
        path: filePath,
      });
    }
    raw = fs.readFileSync(handle);
    afterHandle = fs.fstatSync(handle, { bigint: true });
  } catch (error) {
    if (error && error.code && error.phase) throw error;
    fail("regular_file_read_failed", phase, error.message, { path: filePath });
  } finally {
    if (handle !== null) fs.closeSync(handle);
  }
  let after;
  let afterRealPath;
  try {
    after = fs.lstatSync(filePath, { bigint: true });
    afterRealPath = fs.realpathSync.native(filePath);
  } catch (error) {
    fail("regular_file_post_read_failed", phase, error.message, { path: filePath });
  }
  if (!after.isFile() || after.isSymbolicLink()
      || !samePath(afterRealPath, filePath)
      || !sameBoundFileIdentity(opened, afterHandle)
      || !sameBoundFileIdentity(afterHandle, after)
      || BigInt(raw.length) !== after.size) {
    fail("regular_file_changed_during_read", phase, "file changed during the bound read", {
      path: filePath,
    });
  }
  return { raw, stat: after, realPath: afterRealPath };
}

function writeAtomicRegularFile(root, targetPath, content, phase) {
  const parent = path.dirname(targetPath);
  assertCanonicalDirectoryChain(root, parent, phase);
  const tempPath = path.join(
    parent,
    "." + path.basename(targetPath) + "." + process.pid + "."
      + crypto.randomBytes(8).toString("hex") + ".tmp"
  );
  let created = false;
  try {
    const handle = fs.openSync(tempPath, "wx", 0o600);
    created = true;
    try {
      fs.writeFileSync(handle, content, "utf8");
      fs.fsyncSync(handle);
    } finally {
      fs.closeSync(handle);
    }
    assertCanonicalDirectoryChain(root, parent, phase);
    const existing = readRegularFileSnapshot(targetPath, true, phase);
    if (existing && !samePath(existing.realPath, targetPath)) {
      fail("target_realpath_mismatch", phase, "target path changed before replace");
    }
    fs.renameSync(tempPath, targetPath);
    created = false;
    assertCanonicalDirectoryChain(root, parent, phase);
    return readRegularFileSnapshot(targetPath, false, phase);
  } finally {
    if (created) {
      try { fs.unlinkSync(tempPath); } catch (_error) { /* owned temp cleanup */ }
    }
  }
}

function assertExactSeededTargetBytes(expected, observed) {
  if (!Buffer.isBuffer(expected) || !Buffer.isBuffer(observed)
      || !observed.equals(expected)) {
    fail(
      "seed_target_post_write_mismatch",
      "save_seed",
      "the dedicated clone no longer matches the exact intended seed bytes"
    );
  }
  return true;
}

function solOwnershipSuffix(root, slot) {
  const absoluteRoot = path.resolve(root);
  const volumeRoot = path.parse(absoluteRoot).root;
  const localRoot = path.relative(volumeRoot, absoluteRoot);
  return path.join(
    "localhost",
    localRoot,
    "CRAZYFLASHER7MercenaryEmpire.swf",
    String(slot) + ".sol"
  );
}

function isOwnedSolPath(root, slot, candidatePath) {
  const normalizedCandidate = path.resolve(candidatePath).toLowerCase();
  const normalizedSuffix = solOwnershipSuffix(root, slot).toLowerCase();
  return normalizedCandidate.endsWith(path.sep + normalizedSuffix);
}

function findSolFiles(root, slot) {
  const appData = process.env.APPDATA;
  if (!appData) return [];
  const sharedRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  if (!fs.existsSync(sharedRoot)) return [];

  const fileName = String(slot) + ".sol";
  const results = [];
  const stack = [sharedRoot];
  while (stack.length > 0) {
    const directory = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch (_error) {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile() && entry.name === fileName) {
        if (isOwnedSolPath(root, slot, full)) {
          results.push(full);
        }
      }
    }
  }
  return results.sort();
}

function assertTargetSlotNotInUse(status, targetSlot) {
  const launcherSlot = status && status.save && status.save.slot != null
    ? String(status.save.slot) : "";
  const runtimeSlot = status && status.saveRuntime && status.saveRuntime.savePath != null
    ? String(status.saveRuntime.savePath) : "";
  if (launcherSlot === targetSlot || runtimeSlot === targetSlot) {
    fail(
      "target_slot_in_use",
      "save_seed",
      "dedicated target slot is already selected by the running Launcher/Flash instance"
    );
  }
  return { launcherSlot, runtimeSlot };
}

function prepareDedicatedSave(root, args, runDir) {
  const savesRoot = assertCanonicalDirectoryChain(
    root,
    path.join(root, "saves"),
    "save_seed"
  );
  const seedPath = saveJsonPath(root, args.seedSlot);
  if (!samePath(path.dirname(seedPath), savesRoot)) {
    fail("seed_path_escape", "save_seed", "seed path escaped the exact saves directory");
  }
  const seed = tryReadValidSave(seedPath);
  if (!seed) {
    fail(
      "invalid_seed_shadow",
      "save_seed",
      "--seed-slot " + args.seedSlot + " is missing or is not a valid save shadow"
    );
  }

  const targetPath = saveJsonPath(root, args.slot);
  if (!samePath(path.dirname(targetPath), savesRoot)) {
    fail("target_path_escape", "save_seed", "target path escaped the exact saves directory");
  }
  const backupDir = path.join(runDir, "save-backups");
  const preparation = {
    targetSlot: args.slot,
    seedSlot: args.seedSlot,
    seedSource: toProjectRelative(root, seedPath),
    targetJson: toProjectRelative(root, targetPath),
    seedSha256: crypto.createHash("sha256").update(seed.raw, "utf8").digest("hex"),
    semanticContract: "startup_normalization.v1",
    semanticSha256: cloneSemanticSha256(seed.data),
    role: seed.data["0"][0],
    level: seed.data["0"][3],
    backups: [],
    removedSolFiles: [],
    wroteSeed: false,
  };

  const targetBackup = backupFile(targetPath, backupDir, "target-json");
  if (targetBackup) preparation.backups.push(toProjectRelative(root, targetBackup));

  const solFiles = findSolFiles(root, args.slot);
  solFiles.forEach((solPath, index) => {
    const backup = backupFile(solPath, backupDir, "target-sol-" + String(index + 1));
    if (backup) preparation.backups.push(toProjectRelative(root, backup));
    fs.unlinkSync(solPath);
    preparation.removedSolFiles.push(solPath);
  });

  const clone = JSON.parse(JSON.stringify(seed.data));
  clone.lastSaved = formatLocalSaveTimestamp();
  const cloneText = JSON.stringify(clone);
  const expectedCloneBytes = Buffer.from(cloneText, "utf8");
  const expectedSeededTargetSha256 = crypto
    .createHash("sha256")
    .update(expectedCloneBytes)
    .digest("hex");
  const written = writeAtomicRegularFile(
    root,
    targetPath,
    cloneText,
    "save_seed"
  );
  assertExactSeededTargetBytes(expectedCloneBytes, written.raw);
  preparation.wroteSeed = true;
  preparation.seededTargetSha256 = expectedSeededTargetSha256;
  preparation.targetSha256 = preparation.seededTargetSha256;
  return preparation;
}

function cloneBaselineTarget(root, preparation) {
  const expectedRelative = "saves/" + String(preparation.targetSlot) + ".json";
  if (String(preparation.targetJson || "").replace(/\\/g, "/") !== expectedRelative) {
    fail(
      "clone_baseline_path_mismatch",
      "clone_baseline",
      "the clone baseline path no longer matches the dedicated target slot"
    );
  }
  const targetPath = path.resolve(root, preparation.targetJson);
  const savesRoot = assertCanonicalDirectoryChain(
    root,
    path.resolve(root, "saves"),
    "clone_baseline"
  );
  if (!samePath(path.dirname(targetPath), savesRoot)
      || path.basename(targetPath).toLowerCase()
        !== (String(preparation.targetSlot) + ".json").toLowerCase()) {
    fail(
      "clone_baseline_path_escape",
      "clone_baseline",
      "the clone baseline path escaped the saves directory"
    );
  }
  return targetPath;
}

function readCloneBaselineSample(root, preparation) {
  const targetPath = cloneBaselineTarget(root, preparation);
  let before;
  try {
    before = fs.lstatSync(targetPath, { bigint: true });
  } catch (error) {
    if (error && ["ENOENT", "EPERM", "EBUSY"].includes(error.code)) return null;
    fail("clone_baseline_missing", "clone_baseline", error.message);
  }
  if (!before.isFile() || before.isSymbolicLink()) {
    fail(
      "clone_baseline_not_regular",
      "clone_baseline",
      "the clone baseline must be a regular non-reparse file"
    );
  }
  let realPath;
  try {
    realPath = fs.realpathSync.native(targetPath);
  } catch (error) {
    if (error && ["ENOENT", "EPERM", "EBUSY"].includes(error.code)) return null;
    fail("clone_baseline_realpath_failed", "clone_baseline", error.message);
  }
  if (!samePath(realPath, targetPath)) {
    fail(
      "clone_baseline_realpath_mismatch",
      "clone_baseline",
      "the clone baseline resolved outside its exact target path"
    );
  }

  let raw;
  let opened;
  let afterHandle;
  let handle = null;
  try {
    handle = fs.openSync(targetPath, "r");
    opened = fs.fstatSync(handle, { bigint: true });
    if (!opened.isFile() || !sameBoundFileIdentity(before, opened)) return null;
    raw = fs.readFileSync(handle);
    afterHandle = fs.fstatSync(handle, { bigint: true });
  } catch (error) {
    if (error && ["ENOENT", "EPERM", "EBUSY"].includes(error.code)) return null;
    return null;
  } finally {
    if (handle !== null) fs.closeSync(handle);
  }
  let after;
  try {
    after = fs.lstatSync(targetPath, { bigint: true });
  } catch (error) {
    if (error && ["ENOENT", "EPERM", "EBUSY"].includes(error.code)) return null;
    return null;
  }
  if (!after.isFile() || after.isSymbolicLink()
      || !sameBoundFileIdentity(opened, afterHandle)
      || !sameBoundFileIdentity(afterHandle, after)
      || BigInt(raw.length) !== after.size) {
    return null;
  }
  let afterRealPath;
  try {
    afterRealPath = fs.realpathSync.native(targetPath);
  } catch (error) {
    if (error && ["ENOENT", "EPERM", "EBUSY"].includes(error.code)) return null;
    fail("clone_baseline_realpath_failed", "clone_baseline", error.message);
  }
  if (!samePath(afterRealPath, targetPath)) {
    fail(
      "clone_baseline_realpath_mismatch",
      "clone_baseline",
      "the clone baseline changed real path during sampling"
    );
  }
  let data;
  const text = raw.toString("utf8");
  try {
    data = JSON.parse(text);
  } catch (_error) {
    return null;
  }
  if (!isValidSaveData(data)) return null;
  const digest = crypto.createHash("sha256").update(raw).digest("hex");
  return {
    sha256: digest,
    utf8Bytes: raw.length,
    textChars: text.length,
    deviceId: String(after.dev),
    fileId: String(after.ino),
    mtimeNs: String(after.mtimeNs),
    lastWriteTimeUtc: new Date(Number(after.mtimeNs / 1000000n)).toISOString(),
    lastSaved: data.lastSaved == null ? "" : String(data.lastSaved),
    semanticSha256: cloneSemanticSha256(data),
    role: data["0"][0],
    level: data["0"][3],
    fingerprint: [
      digest,
      String(raw.length),
      String(text.length),
      String(after.mtimeNs),
      String(after.dev),
      String(after.ino),
    ].join(":"),
  };
}

async function captureStableCloneBaseline(root, preparation, dependencies) {
  const options = dependencies || {};
  const stableMs = options.stableMs || CLONE_BASELINE_STABLE_MS;
  const timeoutMs = options.timeoutMs || CLONE_BASELINE_TIMEOUT_MS;
  const monotonicNow = options.monotonicNow || (() => performance.now());
  const readSample = options.readSample
    || (() => readCloneBaselineSample(root, preparation));
  const wait = options.wait || sleep;
  const deadline = monotonicNow() + timeoutMs;
  let stableSince = null;
  let stableStartedAt = null;
  let previousFingerprint = null;
  let stableSampleCount = 0;
  while (monotonicNow() <= deadline) {
    const sample = readSample();
    if (!sample) {
      stableSince = null;
      stableStartedAt = null;
      previousFingerprint = null;
      stableSampleCount = 0;
    } else if (sample.fingerprint !== previousFingerprint) {
      stableSince = monotonicNow();
      stableStartedAt = new Date().toISOString();
      previousFingerprint = sample.fingerprint;
      stableSampleCount = 1;
    } else {
      stableSampleCount += 1;
    }
    if (sample && stableSampleCount >= 2
        && monotonicNow() - stableSince >= stableMs) {
      return {
        sha256: sample.sha256,
        utf8Bytes: sample.utf8Bytes,
        textChars: sample.textChars,
        deviceId: sample.deviceId,
        fileId: sample.fileId,
        mtimeNs: sample.mtimeNs,
        lastWriteTimeUtc: sample.lastWriteTimeUtc,
        lastSaved: sample.lastSaved,
        semanticSha256: sample.semanticSha256,
        role: sample.role,
        level: sample.level,
        stableStartedAt,
        capturedAt: new Date().toISOString(),
        stableWindowMs: stableMs,
        stableSampleCount,
        regularFileVerified: true,
        realPathBound: true,
      };
    }
    await wait(100);
  }
  fail(
    "clone_baseline_unstable",
    "clone_baseline",
    "the dedicated clone did not remain stable long enough to bind the post-open baseline"
  );
}

function bindCloneGateBaseline(preparation, baseline) {
  preparation.gateBaseline = baseline;
  return preparation;
}

function httpRequest(port, method, pathname, body, timeoutMs) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined || body === null ? "" : JSON.stringify(body);
    let authorizationHeaders;
    try {
      authorizationHeaders = LegacyHttpClient.authorizationHeadersFor(
        activeLegacyHttpContext,
        pathname
      );
    } catch (error) {
      reject(error);
      return;
    }
    const req = http.request(
      {
        hostname: "localhost",
        port,
        path: pathname,
        method,
        timeout: timeoutMs || 5000,
        headers: Object.assign({
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload),
        }, authorizationHeaders),
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          resolve({
            statusCode: res.statusCode,
            text: Buffer.concat(chunks).toString("utf8"),
          });
        });
      }
    );
    req.on("timeout", () => {
      req.destroy(new Error("HTTP " + method + " " + pathname + " timed out"));
    });
    req.on("error", reject);
    req.end(payload);
  });
}

function parseJsonResponse(response, context) {
  try {
    return JSON.parse(response.text);
  } catch (_error) {
    fail(
      "non_json_response",
      "http",
      context + " returned non-JSON HTTP " + response.statusCode + ": "
        + response.text.slice(0, 300)
    );
  }
}

async function testPort(port) {
  try {
    const response = await httpRequest(port, "POST", "/testConnection", null, 1000);
    return response.statusCode === 200;
  } catch (_error) {
    return false;
  }
}

function queryLauncherCoreProcesses() {
  if (process.platform !== "win32") return [];
  const script = [
    "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)",
    "$records = @(Get-Process -Name 'CRAZYFLASHER7MercenaryEmpire.Core' -ErrorAction SilentlyContinue | ForEach-Object {",
    "  $processPath = $null",
    "  try { $processPath = $_.Path } catch {}",
    "  [pscustomobject]@{ pid = $_.Id; processPath = $processPath }",
    "})",
    "ConvertTo-Json -InputObject $records -Compress",
  ].join("\n");
  const result = childProcess.spawnSync(
    "powershell.exe",
    ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
    { encoding: "utf8", windowsHide: true }
  );
  if (result.status !== 0) {
    fail(
      "launcher_process_inventory_failed",
      "save_seed",
      "could not prove exclusive Launcher ownership before mutating the clone",
      { stderr: tailText(result.stderr || "") }
    );
  }
  let parsed;
  try {
    parsed = JSON.parse(String(result.stdout || "[]"));
  } catch (error) {
    fail("launcher_process_inventory_invalid", "save_seed", error.message);
  }
  if (!Array.isArray(parsed)
      || parsed.some((entry) => !entry || !Number.isInteger(entry.pid) || entry.pid <= 0)) {
    fail(
      "launcher_process_inventory_invalid",
      "save_seed",
      "Launcher process inventory was malformed"
    );
  }
  return parsed;
}

function assertExclusiveLauncherProcess(processes, authenticatedPid) {
  const records = Array.isArray(processes) ? processes : [];
  if (authenticatedPid == null) {
    if (records.length !== 0) {
      fail(
        "unverified_launcher_process_present",
        "save_seed",
        "a Launcher Core process exists without an authenticated automation context",
        { pids: records.map((entry) => entry.pid) }
      );
    }
    return true;
  }
  const others = records.filter((entry) => entry.pid !== authenticatedPid);
  const authenticated = records.filter((entry) => entry.pid === authenticatedPid);
  if (authenticated.length !== 1 || others.length !== 0) {
    fail(
      "launcher_process_not_exclusive",
      "save_seed",
      "the authenticated Launcher is not the only Launcher Core process",
      {
        authenticatedPid,
        observedPids: records.map((entry) => entry.pid),
      }
    );
  }
  return true;
}

async function discoverPort(root) {
  const portsFile = path.join(root, "launcher_ports.json");
  activeLegacyHttpContext = null;
  if (!fs.existsSync(portsFile)) return null;

  const ports = LegacyHttpClient.readExactLauncherPorts(root);
  if (!await testPort(ports.httpPort)) return null;
  activeLegacyHttpContext =
    LegacyHttpClient.readExactLauncherHttpContext(root);
  return activeLegacyHttpContext.httpPort;
}

function startLauncher(root, expectedIdentity) {
  const script = path.join(root, "automation", "start.ps1");
  const launchArgs = buildLauncherStartArguments(
    script,
    expectedIdentity,
    { enableLegacyHttpAutomation: true },
  );
  const result = childProcess.spawnSync(
    "powershell.exe",
    launchArgs,
    { cwd: root, encoding: "utf8" }
  );
  if (result.status !== 0) {
    fail(
      "launcher_start_failed",
      "launcher",
      "automation/start.ps1 failed with exit code " + result.status,
      {
        stdout: tailText(result.stdout || ""),
        stderr: tailText(result.stderr || ""),
        signal: result.signal || null,
      }
    );
  }
  if (result.stdout) process.stdout.write(result.stdout);
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForPort(root, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const port = await discoverPort(root);
    if (port) return port;
    await sleep(Math.max(250, pollMs));
  }
  fail(
    "launcher_http_timeout",
    "launcher",
    "launcher HTTP bus was not ready within " + timeoutMs + "ms"
  );
}

async function ensureLauncherPort(root, args, expectedIdentity) {
  let port = await discoverPort(root);
  if (!port && args.startLauncher) {
    startLauncher(root, expectedIdentity);
    port = await waitForPort(root, args.readyTimeoutMs, args.pollMs);
  }
  if (!port) {
    fail(
      "launcher_not_running",
      "launcher",
      "launcher is not running; remove --no-start-launcher or start it first"
    );
  }
  return port;
}

async function callTask(port, message, timeoutMs) {
  const response = await httpRequest(port, "POST", "/task", message, timeoutMs || 20000);
  return parseJsonResponse(response, "/task " + String(message.task || ""));
}

async function agent(port, action, fields) {
  return callTask(port, Object.assign(
    { task: "agent_control", action },
    fields || {}
  ));
}

async function consoleCommand(port, command) {
  const response = await httpRequest(
    port,
    "POST",
    "/console",
    { command },
    10000
  );
  return parseJsonResponse(response, "/console");
}

function responseSucceeded(response) {
  return !!response && (response.success === true || response.ok === true);
}

function assertResponseSucceeded(response, phase, label) {
  if (responseSucceeded(response)) return;
  fail(
    "task_failed",
    phase,
    label + " failed: " + JSON.stringify(response),
    response
  );
}

async function waitForAgentControl(port, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    try {
      last = await agent(port, "status");
      if (responseSucceeded(last)
          && last.error !== "task 'agent_control' is not httpCallable") {
        return last;
      }
    } catch (_error) {
      // Launcher may expose HTTP a moment before TaskRegistry is fully ready.
    }
    await sleep(pollMs);
  }
  fail(
    "agent_control_timeout",
    "launcher",
    "agent_control was not available within " + timeoutMs + "ms",
    last
  );
}

async function readLogSnapshot(port) {
  const response = await httpRequest(
    port,
    "GET",
    "/logs?lines=" + LOG_TAIL_LIMIT,
    null,
    5000
  );
  const parsed = parseJsonResponse(response, "/logs");
  if (parsed.success !== true || !Number.isInteger(parsed.total) || !Array.isArray(parsed.lines)) {
    fail(
      "logs_unavailable",
      "logs",
      "/logs did not return a usable watermark: " + JSON.stringify(parsed),
      parsed
    );
  }
  return {
    total: parsed.total,
    lines: parsed.lines.map((line) => String(line)),
    capturedAt: new Date().toISOString(),
  };
}

function logWatermark(snapshot) {
  return {
    total: snapshot.total,
    capturedAt: snapshot.capturedAt || new Date().toISOString(),
  };
}

function freshLogRecords(watermark, snapshot) {
  if (!watermark || !Number.isInteger(watermark.total)) {
    fail("invalid_log_watermark", "logs", "log watermark is missing or malformed");
  }
  if (!snapshot || !Number.isInteger(snapshot.total) || !Array.isArray(snapshot.lines)) {
    fail("invalid_log_snapshot", "logs", "log snapshot is missing or malformed");
  }
  if (snapshot.total < watermark.total) {
    fail(
      "log_reset_after_watermark",
      "logs",
      "launcher.log shrank after the watermark; freshness cannot be proven",
      { watermarkTotal: watermark.total, currentTotal: snapshot.total }
    );
  }

  const oldestZeroBased = snapshot.total - snapshot.lines.length;
  if (watermark.total < oldestZeroBased) {
    fail(
      "log_gap_after_watermark",
      "logs",
      "more than " + LOG_TAIL_LIMIT
        + " launcher log lines arrived after the watermark; freshness evidence was lost",
      { watermarkTotal: watermark.total, oldestAvailable: oldestZeroBased }
    );
  }

  const start = Math.max(0, watermark.total - oldestZeroBased);
  return snapshot.lines.slice(start).map((line, offset) => ({
    line,
    lineNumber: oldestZeroBased + start + offset + 1,
  }));
}

function findFreshHandoff(records) {
  return records.find((record) => record.line.includes(HANDOFF_MARKER)) || null;
}

function findFreshTitleFrame(records) {
  return records.find((record) => record.line.includes(TITLE_FRAME_MARKER)) || null;
}

function findFreshRevealWatchdog(records) {
  return records.find((record) => record.line.includes(REVEAL_WATCHDOG_MARKER)) || null;
}

function assertRuntimeEvidenceOrder(startWatermark, handoff, titleFrame) {
  if (!startWatermark || !Number.isInteger(startWatermark.total)
      || !handoff || !Number.isInteger(handoff.lineNumber)
      || !titleFrame || !Number.isInteger(titleFrame.lineNumber)
      || handoff.lineNumber <= startWatermark.total
      || titleFrame.lineNumber <= handoff.lineNumber) {
    fail(
      "runtime_marker_order_invalid",
      "runtime_ready",
      "runtime evidence must satisfy start watermark < handoff < title frame"
    );
  }
  return true;
}

function extractLogField(line, name) {
  const escaped = name.replace(/[.*+?^{}$()|[\]\\]/g, "\\$&");
  const match = String(line).match(new RegExp("(?:^|\\s)" + escaped + "=([^\\s]+)"));
  return match ? match[1] : null;
}

function decodeLogValue(value) {
  if (value == null || value === "-") return "";
  try {
    return decodeURIComponent(String(value));
  } catch (_error) {
    return "";
  }
}

function parseStartupArchiveReceipt(record, slot, targetPath) {
  if (!record || typeof record.line !== "string") return null;
  const body = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
  const match = body.match(
    /^\[ArchiveTask\] Shadow saved: ([A-Za-z0-9_-]+) \((\d+) chars\) path=(.+)$/
  );
  if (!match || match[1] !== slot || !samePath(match[3], targetPath)) return null;
  const archiveChars = Number(match[2]);
  if (!Number.isSafeInteger(archiveChars) || archiveChars <= 0) return null;
  return {
    lineNumber: record.lineNumber,
    archiveChars,
    targetPath: path.resolve(match[3]),
  };
}

function isEquipmentTuningBusinessRecord(record) {
  const line = record && typeof record.line === "string" ? record.line : "";
  if (/event=equipment_tuning_(?:preview|commit|reconcile)_settled(?:\s|$)/.test(line)) {
    return true;
  }
  const marker = "[WebDebug] ";
  const index = line.indexOf(marker);
  if (index < 0) return false;
  let message;
  try {
    message = JSON.parse(line.slice(index + marker.length).trim());
  } catch (_error) {
    return line.includes("equipment_tuning");
  }
  return message && message.scope === "equipment_tuning"
    && /^(?:candidate_hit|preview_|commit_|inventory_refresh_|reconcile_)/.test(
      String(message.event || "")
    );
}

function establishInteractionLogWatermark(snapshotLineNumber, snapshot) {
  const records = freshLogRecords({ total: snapshotLineNumber }, snapshot);
  const premature = records.find(isEquipmentTuningBusinessRecord);
  if (premature) {
    fail(
      "business_action_before_verifier",
      "interaction_watermark",
      "equipment-tuning business input occurred before the verifier interaction watermark",
      { lineNumber: premature.lineNumber }
    );
  }
  return logWatermark(snapshot);
}

function completeCloneGateBaseline(root, report, baseline, snapshot) {
  const tuningSnapshot = report && report.snapshotGate
    && report.snapshotGate.evidence
    && report.snapshotGate.evidence.tuningSnapshot;
  if (!tuningSnapshot || !report.startLogWatermark || !report.runtime) {
    fail("clone_baseline_evidence_missing", "clone_baseline", "snapshot evidence is missing");
  }
  const handoffLine = report.runtime.handoffEvidence
    && report.runtime.handoffEvidence.lineNumber;
  const titleFrameLine = report.runtime.titleFrameEvidence
    && report.runtime.titleFrameEvidence.lineNumber;
  if (!Number.isInteger(handoffLine) || !Number.isInteger(titleFrameLine)) {
    fail(
      "clone_baseline_runtime_floor_missing",
      "clone_baseline",
      "fresh handoff/title-frame evidence is required before binding startup archive provenance"
    );
  }
  assertRuntimeEvidenceOrder(
    report.startLogWatermark,
    report.runtime.handoffEvidence,
    report.runtime.titleFrameEvidence
  );
  const archiveEvidenceFloorLine = Math.max(
    report.startLogWatermark.total,
    handoffLine,
    titleFrameLine
  );
  if (baseline.semanticSha256 !== report.savePreparation.semanticSha256
      || String(baseline.role) !== String(report.savePreparation.role)
      || String(baseline.level) !== String(report.savePreparation.level)) {
    fail(
      "startup_normalization_semantic_drift",
      "clone_baseline",
      "startup archive changed data outside the narrow normalization contract"
    );
  }
  const records = freshLogRecords(report.startLogWatermark, snapshot);
  const postSnapshotBusiness = records.find((record) => (
    record.lineNumber > tuningSnapshot.lineNumber
      && isEquipmentTuningBusinessRecord(record)
  ));
  if (postSnapshotBusiness) {
    fail(
      "business_action_before_clone_baseline",
      "clone_baseline",
      "equipment-tuning business input occurred before the opener baseline closed",
      { lineNumber: postSnapshotBusiness.lineNumber }
    );
  }
  const targetPath = cloneBaselineTarget(root, report.savePreparation);
  const archiveReceipt = records
    .filter((record) => record.lineNumber > archiveEvidenceFloorLine
      && record.lineNumber <= tuningSnapshot.lineNumber)
    .map((record) => parseStartupArchiveReceipt(
      record,
      report.savePreparation.targetSlot,
      targetPath
    ))
    .filter((receipt) => receipt && receipt.archiveChars === baseline.textChars)
    .pop() || null;
  const changedFromSeed = baseline.sha256
    !== report.savePreparation.seededTargetSha256;
  if (changedFromSeed && !archiveReceipt) {
    fail(
      "startup_archive_receipt_missing",
      "clone_baseline",
      "post-start clone normalization changed bytes without an exact startup archive receipt"
    );
  }
  baseline.changedFromSeed = changedFromSeed;
  baseline.semanticContract = report.savePreparation.semanticContract;
  baseline.archiveEvidenceFloorLine = archiveEvidenceFloorLine;
  baseline.attemptId = report.runtime.expectedAttemptId;
  baseline.snapshot = {
    panelInstanceId: tuningSnapshot.panelInstanceId,
    viewSessionId: tuningSnapshot.viewSessionId,
    callId: tuningSnapshot.callId,
    sourceKey: tuningSnapshot.sourceKey,
    stateRef: tuningSnapshot.stateRef,
    lineNumber: tuningSnapshot.lineNumber,
  };
  baseline.startupArchiveReceipt = archiveReceipt;
  baseline.postCaptureLogWatermark = logWatermark(snapshot);
  return baseline;
}

function parsePanelBoundEvidence(record) {
  if (!record || !record.line.includes("event=equipment_tuning_panel_bound")) return null;
  const panelInstanceId = extractLogField(record.line, "panelInstanceId");
  if (!panelInstanceId) return null;
  return {
    kind: "active_workbench",
    marker: "equipment_tuning_panel_bound",
    panelInstanceId,
    lineNumber: record.lineNumber,
    line: record.line,
  };
}

function parseSnapshotEvidence(record) {
  if (!record || !record.line.includes("event=equipment_tuning_snapshot_confirmed")) return null;
  const callId = extractLogField(record.line, "callId");
  const panelInstanceId = extractLogField(record.line, "panelInstanceId");
  const viewSessionId = extractLogField(record.line, "viewSessionId");
  const legacySourceKey = decodeLogValue(extractLogField(record.line, "sourceKey"));
  const sourceKeyRef = decodeLogValue(extractLogField(record.line, "sourceKeyRef"));
  const sourceKey = legacySourceKey || sourceKeyRef;
  const stateRef = decodeLogValue(extractLogField(record.line, "stateRef"));
  const writeEpochText = extractLogField(record.line, "writeEpoch");
  const writeEpoch = writeEpochText == null ? NaN : Number(writeEpochText);
  if (!callId || !panelInstanceId || !viewSessionId || !sourceKey
      || (sourceKeyRef && !/^sha256_[a-f0-9]{24}$/.test(sourceKeyRef))
      || !/^sha256_[a-f0-9]{24}$/.test(stateRef)
      || !Number.isInteger(writeEpoch) || writeEpoch < 0) return null;
  return {
    kind: "tuning_snapshot",
    marker: "equipment_tuning_snapshot_confirmed",
    callId,
    panelInstanceId,
    viewSessionId,
    sourceKey,
    sourceKeyRef: sourceKeyRef || null,
    stateRef,
    writeEpoch,
    lineNumber: record.lineNumber,
    line: record.line,
  };
}

function selectWorkbenchSnapshotGate(records) {
  const bounds = records.map(parsePanelBoundEvidence).filter(Boolean);
  const snapshots = records.map(parseSnapshotEvidence).filter(Boolean);
  for (const bound of bounds) {
    for (const snapshot of snapshots) {
      if (snapshot.lineNumber <= bound.lineNumber) continue;
      if (snapshot.panelInstanceId !== bound.panelInstanceId) continue;
      return { activeWorkbench: bound, tuningSnapshot: snapshot };
    }
  }
  return null;
}

function readyBlockers(status) {
  return status && Array.isArray(status.runtimeReadyBlockedBy)
    ? status.runtimeReadyBlockedBy
    : [];
}

function isSafeSnapshotStatus(save) {
  return !!save
    && save.decision === "snapshot"
    && save.kind === "Snapshot";
}

function statusAttemptForSlot(status, slot) {
  const save = status && status.save;
  if (!save || save.slot !== slot) return null;
  return typeof save.attemptId === "string" && save.attemptId
    ? save.attemptId
    : null;
}

function shouldRequestAgentEnter(status, state) {
  if (!status || !state || state.enterRequested) return false;
  if (!state.handoffEvidence || !state.titleFrameEvidence || !state.expectedAttemptId) return false;
  if (status.launchState !== "Ready"
      || status.revealPerformed !== true
      || status.socketConnected !== true) return false;
  if (!readyBlockers(status).includes("runtime_save_not_loaded")) return false;
  if (!isSafeSnapshotStatus(status.save)) return false;
  return status.save.slot === state.expectedSlot
    && status.save.attemptId === state.expectedAttemptId;
}

function assertRuntimeReadyStatus(status, expectedSlot, expectedAttemptId) {
  if (!status || status.readyForRuntimeAutomation !== true
      || readyBlockers(status).length !== 0) {
    fail(
      "runtime_not_ready",
      "runtime_ready",
      "readyForRuntimeAutomation was not satisfied",
      status
    );
  }
  if (status.gameEnteredObserved !== true) {
    fail(
      "game_enter_not_observed",
      "runtime_ready",
      "Host did not observe the AS2 s:1 game-enter UI state",
      status
    );
  }
  if (status.gameEnteredAttemptId !== expectedAttemptId) {
    fail(
      "game_enter_attempt_mismatch",
      "runtime_ready",
      "Host game-enter receipt does not match the current launch attempt",
      {
        expectedAttemptId,
        gameEnteredAttemptId: status.gameEnteredAttemptId,
      }
    );
  }
  if (!isSafeSnapshotStatus(status.save)
      || status.save.slot !== expectedSlot
      || status.save.attemptId !== expectedAttemptId) {
    fail(
      "launcher_save_watermark_mismatch",
      "runtime_ready",
      "launcher save watermark does not match the dedicated slot/attempt",
      status.save
    );
  }
  const runtime = status.saveRuntime;
  if (!runtime || runtime.loaded !== true
      || runtime.savePath !== expectedSlot
      || runtime.attemptId !== expectedAttemptId
      || typeof runtime.role !== "string" || !runtime.role
      || runtime.level == null || Number.isNaN(Number(runtime.level))) {
    fail(
      "runtime_save_watermark_mismatch",
      "runtime_ready",
      "AS2 runtime acknowledgement does not match the dedicated slot/attempt",
      runtime
    );
  }
}

async function waitForRuntimeReady(port, args, startWatermark, startResponse, timeline) {
  const deadline = Date.now() + args.readyTimeoutMs;
  let status = startResponse;
  // A launcher created by this run can prewarm the requested slot before the explicit
  // Start action is consumed, so Start legitimately reuses that same attempt id. A truly
  // pre-existing target attempt was already rejected by assertTargetSlotNotInUse; freshness
  // here comes from the post-watermark SWF handoff before the one-shot agent enter request.
  let expectedAttemptId = statusAttemptForSlot(status, args.slot);
  const state = {
    expectedSlot: args.slot,
    expectedAttemptId,
    handoffEvidence: null,
    titleFrameEvidence: null,
    revealWatchdogEvidence: null,
    enterRequested: false,
    enterRequestCount: 0,
    enterResponse: null,
  };
  let lastLogSnapshot = null;

  while (Date.now() <= deadline) {
    status = await agent(port, "status");
    assertResponseSucceeded(status, "runtime_ready", "agent_control status");

    const candidateAttempt = statusAttemptForSlot(status, args.slot);
    if (candidateAttempt) {
      if (state.expectedAttemptId && state.expectedAttemptId !== candidateAttempt) {
        fail(
          "attempt_changed",
          "runtime_ready",
          "launcher attempt changed while waiting for runtime readiness",
          { expected: state.expectedAttemptId, actual: candidateAttempt }
        );
      }
      state.expectedAttemptId = candidateAttempt;
    }

    lastLogSnapshot = await readLogSnapshot(port);
    const freshRecords = freshLogRecords(startWatermark, lastLogSnapshot);
    if (!state.handoffEvidence && state.expectedAttemptId) {
      state.handoffEvidence = findFreshHandoff(freshRecords);
      if (state.handoffEvidence) {
        timeline.push({
          phase: "fresh_handoff_observed",
          at: new Date().toISOString(),
          lineNumber: state.handoffEvidence.lineNumber,
        });
      }
    }
    if (!state.titleFrameEvidence && state.expectedAttemptId) {
      state.titleFrameEvidence = findFreshTitleFrame(freshRecords);
      if (state.titleFrameEvidence) {
        timeline.push({
          phase: "title_frame_observed",
          at: new Date().toISOString(),
          lineNumber: state.titleFrameEvidence.lineNumber,
        });
      }
    }
    if (!state.revealWatchdogEvidence) {
      state.revealWatchdogEvidence = findFreshRevealWatchdog(freshRecords);
    }
    if (state.handoffEvidence && state.titleFrameEvidence) {
      assertRuntimeEvidenceOrder(
        startWatermark,
        state.handoffEvidence,
        state.titleFrameEvidence
      );
    }
    if (state.revealWatchdogEvidence && !state.titleFrameEvidence) {
      fail(
        "title_frame_not_observed",
        "agent_enter",
        "Flash reveal watchdog fired before the real title-frame receipt; refusing to skip root frames 52..81",
        { watchdog: state.revealWatchdogEvidence }
      );
    }

    if (status.launchState === "Error") {
      fail(
        "launcher_error",
        "runtime_ready",
        "launcher entered Error state while waiting for runtime readiness",
        status
      );
    }

    if (state.handoffEvidence
        && status.launchState === "Ready"
        && status.revealPerformed === true
        && readyBlockers(status).includes("save_decision_unsafe")) {
      fail(
        "save_decision_unsafe",
        "runtime_ready",
        "launcher rejected the dedicated clone as an authoritative snapshot",
        status.save
      );
    }

    if (status.readyForRuntimeAutomation === true) {
      if (!state.handoffEvidence || !state.titleFrameEvidence) {
        await sleep(args.pollMs);
        continue;
      }
      if (state.enterRequestCount !== 1) {
        fail(
          "runtime_ready_without_single_enter",
          "runtime_ready",
          "runtime became ready without exactly one agentEnterResolvedSave request",
          { enterRequestCount: state.enterRequestCount }
        );
      }
      if (!state.expectedAttemptId) {
        fail(
          "attempt_missing",
          "runtime_ready",
          "runtime became ready without a fresh launcher attempt id"
        );
      }
      assertRuntimeReadyStatus(status, args.slot, state.expectedAttemptId);
      return {
        status,
        expectedAttemptId: state.expectedAttemptId,
        handoffEvidence: state.handoffEvidence,
        titleFrameEvidence: state.titleFrameEvidence,
        enterRequestCount: state.enterRequestCount,
        enterResponse: state.enterResponse,
        gameEnteredObserved: status.gameEnteredObserved,
        gameEnteredAttemptId: status.gameEnteredAttemptId,
        lastLogTotal: lastLogSnapshot.total,
      };
    }

    if (shouldRequestAgentEnter(status, state)) {
      state.enterRequested = true;
      state.enterRequestCount += 1;
      state.enterResponse = await consoleCommand(port, AGENT_ENTER_COMMAND);
      assertResponseSucceeded(
        state.enterResponse,
        "agent_enter",
        "agentEnterResolvedSave"
      );
      timeline.push({
        phase: "agent_enter_requested",
        at: new Date().toISOString(),
        attemptId: state.expectedAttemptId,
        count: state.enterRequestCount,
      });
    }
    await sleep(args.pollMs);
  }

  if (!state.titleFrameEvidence) {
    fail(
      "title_frame_not_observed",
      "agent_enter",
      "the real bootstrap_reveal_ready title-frame receipt was not observed before timeout",
      {
        handoffEvidence: state.handoffEvidence,
        revealWatchdogEvidence: state.revealWatchdogEvidence,
      }
    );
  }

  fail(
    "runtime_ready_timeout",
    "runtime_ready",
    "game did not reach readyForRuntimeAutomation within "
      + args.readyTimeoutMs + "ms",
    {
      status,
      expectedAttemptId: state.expectedAttemptId,
      handoffEvidence: state.handoffEvidence,
      titleFrameEvidence: state.titleFrameEvidence,
      revealWatchdogEvidence: state.revealWatchdogEvidence,
      enterRequestCount: state.enterRequestCount,
      logTotal: lastLogSnapshot ? lastLogSnapshot.total : null,
    }
  );
}

async function waitForWorkbenchSnapshotGate(port, watermark, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let lastSnapshot = null;
  while (Date.now() <= deadline) {
    lastSnapshot = await readLogSnapshot(port);
    const records = freshLogRecords(watermark, lastSnapshot);
    const evidence = selectWorkbenchSnapshotGate(records);
    if (evidence) {
      return {
        evidence,
        lastLogTotal: lastSnapshot.total,
      };
    }
    await sleep(pollMs);
  }
  fail(
    "snapshot_gate_timeout",
    "snapshot_gate",
    "active workbench and first equipment-tuning snapshot were not both confirmed within "
      + timeoutMs + "ms",
    {
      watermarkTotal: watermark.total,
      lastLogTotal: lastSnapshot ? lastSnapshot.total : null,
      requiredMarkers: [
        "event=equipment_tuning_panel_bound",
        "event=equipment_tuning_snapshot_confirmed",
      ],
    }
  );
}

async function shutdownLauncher(port) {
  try {
    return await agent(port, "shutdown");
  } catch (error) {
    return {
      success: false,
      error: "shutdown_failed",
      message: error.message,
    };
  }
}

function tailText(text, limit) {
  const max = limit || 6000;
  const value = String(text || "");
  return value.length <= max ? value : value.slice(value.length - max);
}

function defaultOutputPaths(root, args) {
  const runDir = path.join(
    root,
    "tmp",
    "equipment-tuning",
    "unattended",
    timestampId() + "-" + args.slot
  );
  return {
    runDir,
    report: args.report
      ? resolveOutputPath(root, args.report)
      : path.join(runDir, "run-report.json"),
    reportMd: args.reportMd
      ? resolveOutputPath(root, args.reportMd)
      : path.join(runDir, "run-report.md"),
  };
}

function serializeError(error) {
  return {
    code: error.code || "unhandled_error",
    phase: error.phase || "unknown",
    message: error.message,
    details: error.details || null,
  };
}

function formatReportMarkdown(report) {
  const lines = [
    "# Equipment tuning unattended run",
    "",
    "- Status: " + report.status,
    "- Slot: " + report.slot,
    "- Seed slot: " + report.seedSlot,
    "- Started: " + report.startedAt,
    "- Finished: " + (report.finishedAt || ""),
    "- Gate: " + report.scope.gate,
    "- UI business clicks: " + String(report.scope.uiBusinessClicks),
    "- Business writes attempted: " + String(report.scope.businessWritesAttempted),
    "",
  ];
  if (report.runtimeIdentity) {
    const identity = report.runtimeIdentity;
    lines.push("## Runtime binary identity", "");
    lines.push("- Verified: " + String(identity.verified));
    lines.push("- Runtime mode: " + String(identity.runtimeMode || "not observed"));
    lines.push("- Process path: " + String(identity.processPath || "not observed"));
    lines.push("- Core SHA-256: " + String(identity.coreSha256 || "not observed"));
    lines.push("- Build identity: " + String(identity.buildIdentity || "not observed"));
    lines.push("- Payload closure: " + String(identity.payloadClosure || "not observed"));
    lines.push("");
  }
  if (report.runtime && report.runtime.expectedAttemptId) {
    lines.push("## Runtime watermark", "");
    lines.push("- Attempt: " + report.runtime.expectedAttemptId);
    lines.push("- Fresh handoff line: "
      + String(report.runtime.handoffEvidence
        ? report.runtime.handoffEvidence.lineNumber
        : "not observed"));
    lines.push("- Real title-frame receipt line: "
      + String(report.runtime.titleFrameEvidence
        ? report.runtime.titleFrameEvidence.lineNumber
        : "not observed"));
    lines.push("- agentEnterResolvedSave calls: "
      + String(report.runtime.enterRequestCount));
    lines.push("- Host observed AS2 s:1: "
      + String(report.runtime.gameEnteredObserved === true));
    lines.push("- Host s:1 attempt: "
      + String(report.runtime.gameEnteredAttemptId || "not observed"));
    lines.push("");
  }
  if (report.snapshotGate && report.snapshotGate.evidence) {
    const evidence = report.snapshotGate.evidence;
    lines.push("## Snapshot gate", "");
    lines.push("- Active workbench instance: "
      + evidence.activeWorkbench.panelInstanceId);
    lines.push("- Tuning view session: "
      + evidence.tuningSnapshot.viewSessionId);
    lines.push("- Snapshot call: " + evidence.tuningSnapshot.callId);
    lines.push("- Write epoch: " + String(evidence.tuningSnapshot.writeEpoch));
    lines.push("");
  }
  if (report.savePreparation && report.savePreparation.gateBaseline) {
    const preparation = report.savePreparation;
    const baseline = preparation.gateBaseline;
    lines.push("## Clone gate baseline", "");
    lines.push("- Seed source SHA-256: " + preparation.seedSha256);
    lines.push("- Seeded target SHA-256: " + preparation.seededTargetSha256);
    lines.push("- Post-snapshot baseline SHA-256: " + baseline.sha256);
    lines.push("- Changed by same-attempt startup archive: "
      + String(baseline.changedFromSeed));
    lines.push("- Stable samples/window: " + String(baseline.stableSampleCount)
      + " / " + String(baseline.stableWindowMs) + "ms");
    lines.push("- Startup archive line: " + String(
      baseline.startupArchiveReceipt
        ? baseline.startupArchiveReceipt.lineNumber : "not required"
    ));
    lines.push("- Post-capture log watermark: "
      + String(baseline.postCaptureLogWatermark.total));
    lines.push("");
  }
  if (report.error) {
    lines.push("## Failure", "");
    lines.push("- Code: " + report.error.code);
    lines.push("- Phase: " + report.error.phase);
    lines.push("- Message: " + report.error.message);
    lines.push("");
  }
  lines.push("## Boundary", "");
  lines.push(
    "This run stops after the production AS2 opener, active workbench binding, "
      + "and the first authoritative equipment-tuning snapshot. It does not "
      + "click operation controls or send preview/commit."
  );
  lines.push("");
  return lines.join("\n");
}

function writeJsonFile(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", "utf8");
}

function writeReport(report, outputs) {
  writeJsonFile(outputs.report, report);
  fs.mkdirSync(path.dirname(outputs.reportMd), { recursive: true });
  fs.writeFileSync(outputs.reportMd, formatReportMarkdown(report), "utf8");
}

function expectRejected(label, callback, expectedCode) {
  let error = null;
  try {
    callback();
  } catch (caught) {
    error = caught;
  }
  if (!error) throw new Error(label + " was not rejected");
  if (expectedCode && error.code !== expectedCode) {
    throw new Error(label + " returned " + error.code + ", expected " + expectedCode);
  }
}

async function runCheck() {
  const agentEntryContract = checkAgentEntryContract();
  const parsed = parseArgs(["--seed-slot", "crazyflasher7_saves2"]);
  assertSafeArgs(parsed);
  if (parsed.slot !== DEFAULT_AGENT_SLOT) {
    throw new Error("default dedicated equipment-tuning slot changed");
  }
  const candidateParsed = parseArgs([
    "--seed-slot", "crazyflasher7_saves2",
    "--candidate-root", "tmp/runtime-candidates/v2/check",
  ]);
  if (candidateParsed.candidateRoot !== "tmp/runtime-candidates/v2/check") {
    throw new Error("--candidate-root parsing failed");
  }
  const identityContract = checkRuntimeIdentityContract();

  expectRejected(
    "live target",
    () => assertSafeArgs(Object.assign({}, parsed, { slot: "crazyflasher7_saves2" })),
    "unsafe_target_slot"
  );
  expectRejected(
    "fresh flow",
    () => assertSafeArgs(Object.assign({}, parsed, { fresh: true })),
    "fresh_forbidden"
  );
  expectRejected(
    "implicit seed",
    () => assertSafeArgs(Object.assign({}, parsed, { seedSlot: null })),
    "seed_slot_required"
  );
  expectRejected(
    "target as seed",
    () => assertSafeArgs(Object.assign({}, parsed, { seedSlot: parsed.slot })),
    "seed_equals_target"
  );

  const ownershipRoot = path.join("C:\\", "Games", "CF7-A", "resources");
  const ownedSol = path.join(
    process.env.APPDATA || path.join("C:\\", "Users", "check", "AppData", "Roaming"),
    "Macromedia", "Flash Player", "#SharedObjects", "HASH1234",
    solOwnershipSuffix(ownershipRoot, parsed.slot)
  );
  const foreignSol = path.join(
    process.env.APPDATA || path.join("C:\\", "Users", "check", "AppData", "Roaming"),
    "Macromedia", "Flash Player", "#SharedObjects", "HASH1234", "localhost",
    "Games", "CF7-B", "resources", "CRAZYFLASHER7MercenaryEmpire.swf",
    parsed.slot + ".sol"
  );
  if (!isOwnedSolPath(ownershipRoot, parsed.slot, ownedSol)
      || isOwnedSolPath(ownershipRoot, parsed.slot, foreignSol)) {
    throw new Error("SOL ownership path was not bound to the exact local game root");
  }

  expectRejected(
    "running launcher target slot",
    () => assertTargetSlotNotInUse({
      save: { slot: parsed.slot },
      saveRuntime: { savePath: "different_agent_slot" },
    }, parsed.slot),
    "target_slot_in_use"
  );
  expectRejected(
    "running Flash target slot",
    () => assertTargetSlotNotInUse({
      save: { slot: "different_agent_slot" },
      saveRuntime: { savePath: parsed.slot },
    }, parsed.slot),
    "target_slot_in_use"
  );
  assertTargetSlotNotInUse({
    save: { slot: "different_launcher_slot" },
    saveRuntime: { savePath: "different_runtime_slot" },
  }, parsed.slot);

  const baselinePreparation = {
    seededTargetSha256: "1".repeat(64),
    targetSha256: "1".repeat(64),
  };
  bindCloneGateBaseline(baselinePreparation, {
    sha256: "2".repeat(64),
    utf8Bytes: 123,
    textChars: 100,
    lastWriteTimeUtc: "2026-08-02T00:00:00.000Z",
    lastSaved: "2026-08-02 08:00:00",
    capturedAt: "2026-08-02T00:00:01.000Z",
    stableWindowMs: CLONE_BASELINE_STABLE_MS,
    regularFileVerified: true,
    realPathBound: true,
  });
  if (baselinePreparation.seededTargetSha256 !== "1".repeat(64)
      || baselinePreparation.targetSha256 !== "1".repeat(64)
      || baselinePreparation.gateBaseline.sha256 !== "2".repeat(64)) {
    throw new Error("post-snapshot clone baseline binding lost seed provenance");
  }

  let fakeNow = 0;
  let sampleIndex = 0;
  const sampleA = {
    sha256: "a".repeat(64),
    utf8Bytes: 100,
    textChars: 90,
    lastWriteTimeUtc: "2026-08-02T00:00:00.000Z",
    lastSaved: "2026-08-02 08:00:00",
    fingerprint: "sample-a",
  };
  const sampleB = Object.assign({}, sampleA, {
    sha256: "b".repeat(64),
    fingerprint: "sample-b",
  });
  const samples = [null, sampleA, sampleA, sampleB, sampleB, sampleB];
  const stableFixture = await captureStableCloneBaseline(null, null, {
    stableMs: 200,
    timeoutMs: 1000,
    monotonicNow: () => fakeNow,
    readSample: () => samples[Math.min(sampleIndex++, samples.length - 1)],
    wait: async (milliseconds) => { fakeNow += milliseconds; },
  });
  if (stableFixture.sha256 !== sampleB.sha256
      || stableFixture.stableSampleCount < 2
      || stableFixture.stableWindowMs !== 200) {
    throw new Error("stable clone sampler did not reset across missing/changed samples");
  }
  let unstableRejected = false;
  fakeNow = 0;
  sampleIndex = 0;
  try {
    await captureStableCloneBaseline(null, null, {
      stableMs: 200,
      timeoutMs: 450,
      monotonicNow: () => fakeNow,
      readSample: () => (sampleIndex++ % 2 === 0 ? sampleA : sampleB),
      wait: async (milliseconds) => { fakeNow += milliseconds; },
    });
  } catch (error) {
    unstableRejected = error && error.code === "clone_baseline_unstable";
  }
  if (!unstableRejected) {
    throw new Error("unstable clone sampler fixture was accepted");
  }

  const semanticA = {
    lastSaved: "old",
    inventory: { slot: { value: { mods: {} } } },
    others: {
      "物品来源缓存": {
        discoveredStages: ["B", "A"],
        discoveredEnemies: ["Y", "X"],
        discoveredQuests: ["2", "1"],
        completedChallengeQuests: ["20", "10"],
      },
    },
  };
  const semanticB = JSON.parse(JSON.stringify(semanticA));
  semanticB.lastSaved = "new";
  semanticB.inventory.slot.value.mods = [];
  Object.keys(semanticB.others["物品来源缓存"]).forEach((key) => {
    semanticB.others["物品来源缓存"][key].reverse();
  });
  if (cloneSemanticSha256(semanticA) !== cloneSemanticSha256(semanticB)) {
    throw new Error("narrow startup normalization semantic fixture changed hash");
  }
  semanticB.inventory.slot.value.level = 2;
  if (cloneSemanticSha256(semanticA) === cloneSemanticSha256(semanticB)) {
    throw new Error("out-of-contract startup semantic mutation was accepted");
  }
  assertExactSeededTargetBytes(Buffer.from("seed"), Buffer.from("seed"));
  let replacedSeedRejected = false;
  try {
    assertExactSeededTargetBytes(Buffer.from("seed"), Buffer.from("other"));
  } catch (error) {
    replacedSeedRejected = error && error.code === "seed_target_post_write_mismatch";
  }
  if (!replacedSeedRejected) {
    throw new Error("post-write seed replacement fixture was accepted");
  }

  const watermark = { total: 2, capturedAt: "2026-07-16T00:00:00.000Z" };
  const snapshot = {
    total: 6,
    lines: [
      "old-1",
      "old-2",
      "[BootstrapAS] event=handoff",
      "[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared",
      "event=equipment_tuning_panel_bound panelInstanceId=panel.workbench.7",
      "event=equipment_tuning_snapshot_confirmed callId=tune.check.1 "
        + "panelInstanceId=panel.workbench.7 viewSessionId=view.check.1 "
        + "sourceKeyRef=sha256_cccccccccccccccccccccccc "
        + "stateRef=sha256_aaaaaaaaaaaaaaaaaaaaaaaa writeEpoch=3",
    ],
  };
  const records = freshLogRecords(watermark, snapshot);
  const handoff = findFreshHandoff(records);
  if (!handoff || handoff.lineNumber !== 3) {
    throw new Error("fresh handoff watermark check failed");
  }
  const titleFrame = findFreshTitleFrame(records);
  if (!titleFrame || titleFrame.lineNumber !== 4) {
    throw new Error("fresh title-frame watermark check failed");
  }
  assertRuntimeEvidenceOrder(watermark, handoff, titleFrame);
  expectRejected(
    "title frame before handoff",
    () => assertRuntimeEvidenceOrder(
      watermark,
      { lineNumber: 4 },
      { lineNumber: 3 }
    ),
    "runtime_marker_order_invalid"
  );
  if (findFreshRevealWatchdog(records)) {
    throw new Error("clean title-frame evidence unexpectedly contained a reveal watchdog");
  }
  const gate = selectWorkbenchSnapshotGate(records);
  if (!gate
      || gate.activeWorkbench.panelInstanceId !== gate.tuningSnapshot.panelInstanceId
      || gate.tuningSnapshot.writeEpoch !== 3
      || gate.tuningSnapshot.sourceKey !== "sha256_cccccccccccccccccccccccc"
      || gate.tuningSnapshot.sourceKeyRef !== "sha256_cccccccccccccccccccccccc") {
    throw new Error("correlated workbench/snapshot evidence check failed");
  }

  const mismatched = selectWorkbenchSnapshotGate([
    {
      lineNumber: 3,
      line: "event=equipment_tuning_panel_bound panelInstanceId=panel.workbench.A",
    },
    {
      lineNumber: 4,
      line: "event=equipment_tuning_snapshot_confirmed callId=tune.bad.1 "
        + "panelInstanceId=panel.workbench.B viewSessionId=view.bad.1 "
        + "sourceKey=inventory%3A%E8%83%8C%E5%8C%85%3A7%3Alease.bad "
        + "stateRef=sha256_bbbbbbbbbbbbbbbbbbbbbbbb writeEpoch=0",
    },
  ]);
  if (mismatched) throw new Error("cross-instance snapshot evidence was accepted");

  const beforeHandoff = {
    launchState: "Ready",
    revealPerformed: true,
    socketConnected: true,
    runtimeReadyBlockedBy: ["runtime_save_not_loaded"],
    save: {
      decision: "snapshot",
      kind: "Snapshot",
      slot: DEFAULT_AGENT_SLOT,
      attemptId: "attempt-check",
    },
  };
  const enterState = {
    expectedSlot: DEFAULT_AGENT_SLOT,
    expectedAttemptId: "attempt-check",
    handoffEvidence: null,
    titleFrameEvidence: null,
    enterRequested: false,
  };
  if (shouldRequestAgentEnter(beforeHandoff, enterState)) {
    throw new Error("agent enter was allowed before fresh handoff");
  }
  enterState.handoffEvidence = handoff;
  if (shouldRequestAgentEnter(beforeHandoff, enterState)) {
    throw new Error("agent enter was allowed before the real title-frame receipt");
  }
  enterState.titleFrameEvidence = titleFrame;
  if (!shouldRequestAgentEnter(beforeHandoff, enterState)) {
    throw new Error("agent enter was not allowed after all narrow gates");
  }
  enterState.enterRequested = true;
  if (shouldRequestAgentEnter(beforeHandoff, enterState)) {
    throw new Error("agent enter was not single-shot");
  }

  const ready = JSON.parse(JSON.stringify(beforeHandoff));
  ready.runtimeReadyBlockedBy = [];
  ready.readyForRuntimeAutomation = true;
  ready.gameEnteredObserved = true;
  ready.gameEnteredAttemptId = "attempt-check";
  ready.saveRuntime = {
    loaded: true,
    savePath: DEFAULT_AGENT_SLOT,
    attemptId: "attempt-check",
    role: "check-role",
    level: 10,
  };
  assertRuntimeReadyStatus(ready, DEFAULT_AGENT_SLOT, "attempt-check");
  expectRejected(
    "missing game-enter receipt",
    () => {
      const missingGameEnter = JSON.parse(JSON.stringify(ready));
      missingGameEnter.gameEnteredObserved = false;
      assertRuntimeReadyStatus(missingGameEnter, DEFAULT_AGENT_SLOT, "attempt-check");
    },
    "game_enter_not_observed"
  );
  expectRejected(
    "stale runtime attempt",
    () => {
      const stale = JSON.parse(JSON.stringify(ready));
      stale.saveRuntime.attemptId = "attempt-stale";
      assertRuntimeReadyStatus(stale, DEFAULT_AGENT_SLOT, "attempt-check");
    },
    "runtime_save_watermark_mismatch"
  );

  const checkIdentity = {
    runtimeMode: "isolated_candidate",
    processPath: path.join("C:\\", "check", "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
    coreSha256: "C".repeat(64),
    buildIdentity: "A".repeat(64),
    payloadClosure: "B".repeat(64),
    pid: 123,
    httpPort: 1192,
  };
  const identityReport = createRuntimeIdentityReport(checkIdentity);
  recordVerifiedRuntimeIdentity(identityReport, checkIdentity);
  const markdown = formatReportMarkdown({
    status: "snapshot_gate_reached",
    slot: DEFAULT_AGENT_SLOT,
    seedSlot: "crazyflasher7_saves2",
    startedAt: "2026-07-16T00:00:00.000Z",
    finishedAt: "2026-07-16T00:00:01.000Z",
    scope: {
      gate: "active_workbench_and_first_tuning_snapshot",
      uiBusinessClicks: false,
      businessWritesAttempted: false,
    },
    runtime: {
      expectedAttemptId: "attempt-check",
      handoffEvidence: handoff,
      titleFrameEvidence: titleFrame,
      enterRequestCount: 1,
      gameEnteredObserved: true,
      gameEnteredAttemptId: "attempt-check",
    },
    runtimeIdentity: identityReport,
    snapshotGate: { evidence: gate },
    error: null,
  });
  if (!markdown.includes("does not click operation controls")
      || !markdown.includes("panel.workbench.7")
      || !markdown.includes("Real title-frame receipt line: 4")
      || !markdown.includes("Host observed AS2 s:1: true")
      || !markdown.includes("Host s:1 attempt: attempt-check")
      || !markdown.includes("isolated_candidate")
      || !markdown.includes("C".repeat(64))) {
    throw new Error("report boundary/evidence check failed");
  }

  console.log(JSON.stringify({
    ok: true,
    slot: DEFAULT_AGENT_SLOT,
    checks: 31 + identityContract.checks,
    agentEntryContract: agentEntryContract.uiState,
    scope: "open_snapshot_gate_only",
  }, null, 2));
}

async function runUnattended(args) {
  assertSafeArgs(args);
  const root = projectRoot();
  const outputs = defaultOutputPaths(root, args);
  fs.mkdirSync(outputs.runDir, { recursive: true });

  const report = {
    schema: "equipment-tuning.unattended-run.v1",
    status: "running",
    slot: args.slot,
    seedSlot: args.seedSlot,
    startedAt: new Date().toISOString(),
    finishedAt: null,
    reportPath: toProjectRelative(root, outputs.report),
    reportMarkdownPath: toProjectRelative(root, outputs.reportMd),
    scope: {
      gate: "active_workbench_and_first_tuning_snapshot",
      productionOpenerOnly: true,
      uiBusinessClicks: false,
      businessWritesAttempted: false,
      businessCommandsSent: [],
      stopAfterSnapshot: true,
    },
    timeline: [],
    savePreparation: null,
    preparationGuard: null,
    httpPort: null,
    runtimeIdentity: createRuntimeIdentityReport(null),
    startLogWatermark: null,
    startResponse: null,
    runtime: null,
    openLogWatermark: null,
    openResponse: null,
    snapshotGate: null,
    shutdownResponse: null,
    error: null,
  };

  let port = null;
  let caught = null;
  try {
    const expectedIdentity = resolveExpectedRuntimeIdentity(root, args.candidateRoot);
    report.runtimeIdentity = createRuntimeIdentityReport(expectedIdentity);
    report.timeline.push({
      phase: "runtime_identity_expected",
      at: new Date().toISOString(),
      runtimeMode: expectedIdentity.runtimeMode,
      processPath: expectedIdentity.processPath,
      coreSha256: expectedIdentity.coreSha256,
      buildIdentity: expectedIdentity.buildIdentity,
      payloadClosure: expectedIdentity.payloadClosure,
    });

    let priorStatus = null;
    port = await discoverPort(root);
    if (port) {
      const actualIdentity = verifyRuntimeIdentity(
        root,
        port,
        expectedIdentity,
        (observed) => recordObservedRuntimeIdentity(report.runtimeIdentity, observed)
      );
      recordVerifiedRuntimeIdentity(report.runtimeIdentity, actualIdentity);
      assertExclusiveLauncherProcess(queryLauncherCoreProcesses(), actualIdentity.pid);
      report.httpPort = port;
      report.timeline.push({
        phase: "existing_launcher_runtime_identity_verified",
        at: new Date().toISOString(),
        runtimeMode: actualIdentity.runtimeMode,
        pid: actualIdentity.pid,
        coreSha256: actualIdentity.coreSha256,
      });
      priorStatus = await waitForAgentControl(
        port,
        args.readyTimeoutMs,
        args.pollMs
      );
      report.preparationGuard = assertTargetSlotNotInUse(priorStatus, args.slot);
      report.timeline.push({
        phase: "existing_launcher_target_slot_guard_passed",
        at: new Date().toISOString(),
        launcherSlot: report.preparationGuard.launcherSlot,
        runtimeSlot: report.preparationGuard.runtimeSlot,
      });
    } else {
      assertExclusiveLauncherProcess(queryLauncherCoreProcesses(), null);
      if (!args.startLauncher) {
        fail(
          "launcher_not_running",
          "launcher",
          "launcher is not running; remove --no-start-launcher or start it first"
        );
      }
      report.preparationGuard = { launcherSlot: "", runtimeSlot: "" };
      report.timeline.push({
        phase: "no_existing_launcher_before_save_seed",
        at: new Date().toISOString(),
      });
    }

    report.savePreparation = prepareDedicatedSave(root, args, outputs.runDir);
    report.timeline.push({
      phase: "dedicated_save_seeded",
      at: new Date().toISOString(),
      targetSlot: args.slot,
      seedSlot: args.seedSlot,
    });

    if (!port) {
      port = await ensureLauncherPort(root, args, expectedIdentity);
      const actualIdentity = verifyRuntimeIdentity(
        root,
        port,
        expectedIdentity,
        (observed) => recordObservedRuntimeIdentity(report.runtimeIdentity, observed)
      );
      recordVerifiedRuntimeIdentity(report.runtimeIdentity, actualIdentity);
      assertExclusiveLauncherProcess(queryLauncherCoreProcesses(), actualIdentity.pid);
      report.timeline.push({
        phase: "started_launcher_runtime_identity_verified",
        at: new Date().toISOString(),
        runtimeMode: actualIdentity.runtimeMode,
        pid: actualIdentity.pid,
        coreSha256: actualIdentity.coreSha256,
      });
    }
    report.httpPort = port;
    assertExclusiveLauncherProcess(
      queryLauncherCoreProcesses(),
      report.runtimeIdentity.pid
    );
    report.timeline.push({
      phase: "launcher_process_exclusivity_reverified_after_seed",
      at: new Date().toISOString(),
      pid: report.runtimeIdentity.pid,
    });
    if (!priorStatus) {
      priorStatus = await waitForAgentControl(
        port,
        args.readyTimeoutMs,
        args.pollMs
      );
    }

    const startLog = await readLogSnapshot(port);
    report.startLogWatermark = logWatermark(startLog);
    report.timeline.push({
      phase: "pre_start_log_watermark",
      at: new Date().toISOString(),
      total: report.startLogWatermark.total,
    });

    report.startResponse = await agent(port, "start", {
      slot: args.slot,
      fresh: false,
      deferReveal: false,
      requireFlashReveal: true,
      rememberSlot: false,
    });
    assertResponseSucceeded(report.startResponse, "start", "agent_control start");
    report.timeline.push({
      phase: "start_requested",
      at: new Date().toISOString(),
      slot: args.slot,
      fresh: false,
    });

    report.runtime = await waitForRuntimeReady(
      port,
      args,
      report.startLogWatermark,
      report.startResponse,
      report.timeline
    );
    report.timeline.push({
      phase: "runtime_ready",
      at: new Date().toISOString(),
      attemptId: report.runtime.expectedAttemptId,
    });

    const openLog = await readLogSnapshot(port);
    report.openLogWatermark = logWatermark(openLog);
    report.timeline.push({
      phase: "pre_open_log_watermark",
      at: new Date().toISOString(),
      total: report.openLogWatermark.total,
    });

    report.openResponse = await agent(port, "openEquipmentTuning", {
      expectedSlot: args.slot,
      expectedAttemptId: report.runtime.expectedAttemptId,
    });
    assertResponseSucceeded(
      report.openResponse,
      "open_equipment_tuning",
      "agent_control openEquipmentTuning"
    );
    report.timeline.push({
      phase: "equipment_tuning_open_requested",
      at: new Date().toISOString(),
      attemptId: report.runtime.expectedAttemptId,
    });

    report.snapshotGate = await waitForWorkbenchSnapshotGate(
      port,
      report.openLogWatermark,
      args.panelTimeoutMs,
      args.pollMs
    );
    report.timeline.push({
      phase: "snapshot_gate_reached",
      at: new Date().toISOString(),
      panelInstanceId: report.snapshotGate.evidence.activeWorkbench.panelInstanceId,
      viewSessionId: report.snapshotGate.evidence.tuningSnapshot.viewSessionId,
    });
    const snapshotIdentity = verifyRuntimeIdentity(
      root,
      port,
      expectedIdentity,
      (observed) => recordObservedRuntimeIdentity(report.runtimeIdentity, observed)
    );
    recordVerifiedRuntimeIdentity(report.runtimeIdentity, snapshotIdentity);
    report.timeline.push({
      phase: "runtime_identity_reverified_after_snapshot",
      at: new Date().toISOString(),
      pid: snapshotIdentity.pid,
      coreSha256: snapshotIdentity.coreSha256,
    });
    let cloneBaseline = await captureStableCloneBaseline(
      root,
      report.savePreparation
    );
    const baselineLogSnapshot = await readLogSnapshot(port);
    cloneBaseline = completeCloneGateBaseline(
      root,
      report,
      cloneBaseline,
      baselineLogSnapshot
    );
    bindCloneGateBaseline(report.savePreparation, cloneBaseline);
    report.timeline.push({
      phase: "post_snapshot_clone_baseline_bound",
      at: cloneBaseline.capturedAt,
      sha256: cloneBaseline.sha256,
      utf8Bytes: cloneBaseline.utf8Bytes,
      textChars: cloneBaseline.textChars,
      deviceId: cloneBaseline.deviceId,
      fileId: cloneBaseline.fileId,
      mtimeNs: cloneBaseline.mtimeNs,
      semanticContract: cloneBaseline.semanticContract,
      semanticSha256: cloneBaseline.semanticSha256,
      stableWindowMs: cloneBaseline.stableWindowMs,
      stableSampleCount: cloneBaseline.stableSampleCount,
      changedFromSeed: cloneBaseline.changedFromSeed,
      startupArchiveLine: cloneBaseline.startupArchiveReceipt
        ? cloneBaseline.startupArchiveReceipt.lineNumber : null,
      archiveEvidenceFloorLine: cloneBaseline.archiveEvidenceFloorLine,
      postCaptureLogTotal: cloneBaseline.postCaptureLogWatermark.total,
    });
    const finalIdentity = verifyRuntimeIdentity(
      root,
      port,
      expectedIdentity,
      (observed) => recordObservedRuntimeIdentity(report.runtimeIdentity, observed)
    );
    recordVerifiedRuntimeIdentity(report.runtimeIdentity, finalIdentity);
    assertExclusiveLauncherProcess(queryLauncherCoreProcesses(), finalIdentity.pid);
    report.timeline.push({
      phase: "runtime_identity_reverified_after_clone_baseline",
      at: new Date().toISOString(),
      pid: finalIdentity.pid,
      coreSha256: finalIdentity.coreSha256,
    });
    report.status = "snapshot_gate_reached";
  } catch (error) {
    caught = error;
    report.status = "failed";
    report.error = serializeError(error);
  } finally {
    if (args.shutdown && port && report.runtimeIdentity.verified
        && (!caught || caught.phase !== "runtime_identity")) {
      report.shutdownResponse = await shutdownLauncher(port);
    }
    report.finishedAt = new Date().toISOString();
    writeReport(report, outputs);
  }

  if (caught) throw caught;
  console.log(JSON.stringify({
    ok: true,
    status: report.status,
    slot: report.slot,
    attemptId: report.runtime.expectedAttemptId,
    gameEnteredObserved: report.runtime.gameEnteredObserved === true,
    panelInstanceId: report.snapshotGate.evidence.activeWorkbench.panelInstanceId,
    viewSessionId: report.snapshotGate.evidence.tuningSnapshot.viewSessionId,
    runtimeMode: report.runtimeIdentity.runtimeMode,
    processPath: report.runtimeIdentity.processPath,
    coreSha256: report.runtimeIdentity.coreSha256,
    buildIdentity: report.runtimeIdentity.buildIdentity,
    payloadClosure: report.runtimeIdentity.payloadClosure,
    scope: "open_snapshot_gate_only",
    report: report.reportPath,
  }, null, 2));
  return report;
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }
  if (args.check) {
    await runCheck();
    return;
  }
  await runUnattended(args);
}

module.exports = {
  AGENT_ENTER_COMMAND,
  DEFAULT_AGENT_SLOT,
  HANDOFF_MARKER,
  REVEAL_WATCHDOG_MARKER,
  TITLE_FRAME_MARKER,
  agent,
  assertCanonicalDirectoryChain,
  assertExactSeededTargetBytes,
  assertExclusiveLauncherProcess,
  assertRegularFileLstat,
  assertResponseSucceeded,
  assertRuntimeEvidenceOrder,
  assertRuntimeReadyStatus,
  assertSafeArgs,
  assertTargetSlotNotInUse,
  captureStableCloneBaseline,
  cloneSemanticSha256,
  discoverPort,
  ensureLauncherPort,
  extractLogField,
  establishInteractionLogWatermark,
  findFreshHandoff,
  findFreshRevealWatchdog,
  findFreshTitleFrame,
  formatReportMarkdown,
  freshLogRecords,
  isValidSaveData,
  isOwnedSolPath,
  logWatermark,
  parseArgs,
  parsePanelBoundEvidence,
  parseSnapshotEvidence,
  parseStartupArchiveReceipt,
  queryLauncherCoreProcesses,
  readCloneBaselineSample,
  readLogSnapshot,
  readRegularFileSnapshot,
  resolveExpectedRuntimeIdentity,
  runCheck,
  selectWorkbenchSnapshotGate,
  sameBoundFileIdentity,
  shutdownLauncher,
  shouldRequestAgentEnter,
  solOwnershipSuffix,
  startLauncher,
  statusAttemptForSlot,
  waitForAgentControl,
  waitForPort,
  waitForRuntimeReady,
  waitForWorkbenchSnapshotGate,
  writeAtomicRegularFile,
};

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exit(error.isUsageError ? 2 : 1);
  });
}
