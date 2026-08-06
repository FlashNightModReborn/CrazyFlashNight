#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const net = require("net");
const path = require("path");

const opener = require("../../equipment-tuning/run-unattended");
const RuntimeIdentity = require("../../lib/runtime-process-identity");
const LegacyHttpClient = require("../../lib/legacy-http-client");
const LegacyHttpAuth = require("../../lib/legacy-http-auth");
const Recorder = require("./passive-recorder");
const Verifier = require("./verify-receipt");
const SessionVerifier = require("./verify-session-evidence");
const { SOURCE_ASSETS, validateSourceFingerprint } = require("./source-contract");

const ROOT = path.resolve(__dirname, "../../..");
const TARGET_SLOT = "cf7_agent_a3_crafting";
const CONTROL_INTEGRATION_READY = false;
const AGENT_SLOT_RE = /^cf7_agent_[A-Za-z0-9_-]+$/;
const SAFE_SLOT_RE = /^[A-Za-z0-9_-]+$/;
const LIVE_SLOT_RE = /^crazyflasher7_saves\d*$/;
const DEFAULT_CDP_PORT = 9234;
class RunnerError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "RunnerError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
  }
}

function fail(code, phase, message, details) {
  throw new RunnerError(code, phase, message, details);
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function timestampId(date) {
  return (date || new Date()).toISOString().replace(/[-:]/g, "").replace(/\..+$/, "Z");
}

function toRelative(filePath) {
  const relative = path.relative(ROOT, filePath);
  return !relative.startsWith("..") && !path.isAbsolute(relative)
    ? relative.replace(/\\/g, "/") : filePath;
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function processExists(pid) {
  try { process.kill(pid, 0); return true; }
  catch (error) { return !!(error && error.code === "EPERM"); }
}

function parseArgs(argv) {
  const args = {
    seedSlot: null,
    candidateRoot: null,
    inputProvider: null,
    cdpPort: DEFAULT_CDP_PORT,
    readyTimeoutMs: 180000,
    ingressTimeoutMs: 900000,
    interactionTimeoutMs: 900000,
    saveTimeoutMs: 900000,
    readbackTimeoutMs: 900000,
    shutdownTimeoutMs: 60000,
    pollMs: 500,
    quietMs: 1200,
    check: false,
    help: false
  };
  function next(index, option) {
    if (index + 1 >= argv.length || String(argv[index + 1]).startsWith("--")) {
      fail("missing_argument", "arguments", option + " requires a value");
    }
    return argv[index + 1];
  }
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--seed-slot") args.seedSlot = next(index++, token);
    else if (token === "--candidate-root") args.candidateRoot = next(index++, token);
    else if (token === "--input-provider") args.inputProvider = next(index++, token);
    else if (token === "--cdp-port") args.cdpPort = Number(next(index++, token));
    else if (token === "--ready-timeout-ms") args.readyTimeoutMs = Number(next(index++, token));
    else if (token === "--ingress-timeout-ms") args.ingressTimeoutMs = Number(next(index++, token));
    else if (token === "--interaction-timeout-ms") args.interactionTimeoutMs = Number(next(index++, token));
    else if (token === "--save-timeout-ms") args.saveTimeoutMs = Number(next(index++, token));
    else if (token === "--readback-timeout-ms") args.readbackTimeoutMs = Number(next(index++, token));
    else if (token === "--shutdown-timeout-ms") args.shutdownTimeoutMs = Number(next(index++, token));
    else if (token === "--poll-ms") args.pollMs = Number(next(index++, token));
    else if (token === "--quiet-ms") args.quietMs = Number(next(index++, token));
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail("unknown_argument", "arguments", "unknown argument: " + token);
  }
  return args;
}

function printHelp() {
  console.log([
    "Usage: node tools/workbench-live-e2e/crafting/run-crafting.js --seed-slot <slot>",
    "  --candidate-root <exact candidate> --input-provider <launcher_agent|codex_computer_use>",
    "",
    "Starts a dedicated clone and waits for external computer-use to perform the real",
    "Map -> Armory -> Flash crafting entry, trusted recipe/commit clicks, safe save,",
    "and the same production readback route after restart. The runner never sends a",
    "crafting business command and never clicks a business control.",
    "",
    "Fixed target: " + TARGET_SLOT,
    "Default CDP port: " + DEFAULT_CDP_PORT,
    "--check runs offline self-checks only."
  ].join("\n"));
}

function assertArgs(args) {
  if (!args.seedSlot || !SAFE_SLOT_RE.test(args.seedSlot) || args.seedSlot.includes("..")) {
    fail("seed_slot_invalid", "arguments", "--seed-slot must be an explicit safe slot name");
  }
  if (AGENT_SLOT_RE.test(args.seedSlot) || args.seedSlot === TARGET_SLOT) {
    fail("agent_seed_forbidden", "arguments", "an A3 clone may not be seeded from another agent clone");
  }
  if (!LIVE_SLOT_RE.test(args.seedSlot)) {
    fail("shadow_seed_required", "arguments",
      "seed must be an explicit crazyflasher7_saves* shadow; it is read only");
  }
  if (!args.candidateRoot) {
    fail("candidate_root_required", "arguments", "A3 requires one explicit isolated candidate");
  }
  if (args.inputProvider !== "launcher_agent" && args.inputProvider !== "codex_computer_use") {
    fail("input_provider_required", "arguments",
      "--input-provider must record launcher_agent or codex_computer_use");
  }
  if (!Number.isInteger(args.cdpPort) || args.cdpPort < 1024 || args.cdpPort > 65535) {
    fail("cdp_port_invalid", "arguments", "--cdp-port must be an integer from 1024 to 65535");
  }
  ["readyTimeoutMs", "ingressTimeoutMs", "interactionTimeoutMs", "saveTimeoutMs",
    "readbackTimeoutMs", "shutdownTimeoutMs", "pollMs", "quietMs"].forEach((name) => {
    if (!Number.isInteger(args[name]) || args[name] < (name === "pollMs" ? 100 : 500)) {
      fail("timeout_invalid", "arguments", name + " is outside the supported range");
    }
  });
}

function formatLocalSaveTimestamp(date) {
  const value = date || new Date();
  const pad = (number) => String(number).padStart(2, "0");
  return value.getFullYear() + "-" + pad(value.getMonth() + 1) + "-" + pad(value.getDate())
    + " " + pad(value.getHours()) + ":" + pad(value.getMinutes()) + ":" + pad(value.getSeconds());
}

function savePath(slot) {
  return path.join(ROOT, "saves", slot + ".json");
}

function cloneLockPath() {
  return path.join(ROOT, "saves", TARGET_SLOT + ".live-e2e.lock");
}

function acquireCloneLock(runId) {
  const savesRoot = opener.assertCanonicalDirectoryChain(
    ROOT, path.join(ROOT, "saves"), "clone_lock");
  const lockPath = cloneLockPath();
  if (path.dirname(lockPath).toLowerCase() !== savesRoot.toLowerCase()) {
    fail("clone_lock_path_invalid", "clone_lock", "clone lock escaped saves directory");
  }
  let descriptor = null;
  try {
    descriptor = fs.openSync(lockPath, "wx");
    const body = Buffer.from(JSON.stringify({
      schema: "crafting.clone-lock.v1",
      runId,
      targetSlot: TARGET_SLOT,
      pid: process.pid,
      acquiredAt: new Date().toISOString()
    }) + "\n", "utf8");
    fs.writeFileSync(descriptor, body);
    fs.fsyncSync(descriptor);
  } catch (error) {
    if (descriptor != null) {
      try { fs.closeSync(descriptor); } catch (_closeError) { /* preserve original */ }
    }
    fail(error && error.code === "EEXIST" ? "clone_lock_held" : "clone_lock_acquire_failed",
      "clone_lock", "exclusive Crafting clone lock could not be acquired", {
        path: toRelative(lockPath),
        error: error && error.message
      });
  }
  let contentionRejected = false;
  try {
    const probe = fs.openSync(lockPath, "wx");
    fs.closeSync(probe);
  } catch (error) {
    contentionRejected = !!(error && error.code === "EEXIST");
  }
  if (!contentionRejected) {
    try { fs.closeSync(descriptor); } catch (_closeError) { /* handled below */ }
    try { fs.unlinkSync(lockPath); } catch (_unlinkError) { /* handled by failure evidence */ }
    fail("clone_lock_not_exclusive", "clone_lock",
      "second create-new probe did not reject the held clone lock");
  }
  return {
    descriptor,
    path: lockPath,
    evidence: {
      targetSlot: TARGET_SLOT,
      ownerRunId: runId,
      path: lockPath,
      exclusive: true,
      acquired: true,
      acquireMode: "create_new",
      contentionProbeRejected: true,
      released: false,
      heldThroughFinalShutdown: false
    }
  };
}

function releaseCloneLock(lock, heldThroughFinalShutdown) {
  if (!lock || lock.released) return lock && lock.evidence;
  const expected = path.resolve(cloneLockPath());
  if (path.resolve(lock.path) !== expected) {
    fail("clone_lock_release_path_invalid", "clone_lock",
      "refusing to release a non-canonical clone lock", { path: lock.path });
  }
  fs.closeSync(lock.descriptor);
  fs.unlinkSync(expected);
  lock.released = true;
  lock.evidence.released = true;
  lock.evidence.heldThroughFinalShutdown = heldThroughFinalShutdown === true;
  lock.evidence.releasedAt = new Date().toISOString();
  return lock.evidence;
}

function backupRegularFile(source, backupDir, label) {
  const snapshot = opener.readRegularFileSnapshot(source, true, "clone_backup");
  if (!snapshot) return null;
  fs.mkdirSync(backupDir, { recursive: true });
  opener.assertCanonicalDirectoryChain(ROOT, backupDir, "clone_backup");
  const destination = path.join(backupDir, label + "-" + path.basename(source));
  fs.writeFileSync(destination, snapshot.raw, { flag: "wx" });
  return destination;
}

function findOwnedSolFiles(slot) {
  const appData = process.env.APPDATA;
  if (!appData) return [];
  const sharedRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  if (!fs.existsSync(sharedRoot)) return [];
  const results = [];
  const stack = [sharedRoot];
  while (stack.length > 0) {
    const directory = stack.pop();
    let entries;
    try { entries = fs.readdirSync(directory, { withFileTypes: true }); }
    catch (_error) { continue; }
    for (const entry of entries) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) stack.push(full);
      else if (entry.isFile() && entry.name === slot + ".sol"
          && opener.isOwnedSolPath(ROOT, slot, full)) results.push(full);
    }
  }
  return results.sort();
}

function captureSeedFileSet(slot) {
  const jsonPath = savePath(slot);
  const candidates = [{ kind: "json", path: jsonPath }]
    .concat(findOwnedSolFiles(slot).map((filePath) => ({ kind: "sol", path: filePath })));
  const files = candidates.map((candidate) => {
    const snapshot = opener.readRegularFileSnapshot(candidate.path, false, "seed_invariant");
    const relative = path.relative(ROOT, candidate.path);
    return {
      kind: candidate.kind,
      path: (!relative.startsWith("..") && !path.isAbsolute(relative)
        ? relative : path.resolve(candidate.path)).replace(/\\/g, "/"),
      bytes: snapshot.raw.length,
      sha256: sha256(snapshot.raw)
    };
  }).sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  return {
    slot,
    files,
    setSha256: sha256(Buffer.from(JSON.stringify(files), "utf8"))
  };
}

function assertSeedFileSetUnchanged(before) {
  const after = captureSeedFileSet(before.slot);
  if (!Verifier.deepEqual(before, after)) {
    fail("seed_source_changed", "seed_invariant",
      "read-only seed JSON/SOL file set changed during Crafting E2E", { before, after });
  }
  return after;
}

function prepareClone(runDir, seedSlot) {
  const savesRoot = opener.assertCanonicalDirectoryChain(ROOT, path.join(ROOT, "saves"), "clone_seed");
  const seedFile = savePath(seedSlot);
  const targetFile = savePath(TARGET_SLOT);
  if (path.dirname(seedFile).toLowerCase() !== savesRoot.toLowerCase()
      || path.dirname(targetFile).toLowerCase() !== savesRoot.toLowerCase()) {
    fail("save_path_escape", "clone_seed", "save path escaped the exact saves directory");
  }
  const seed = opener.readRegularFileSnapshot(seedFile, false, "clone_seed");
  let data;
  try { data = JSON.parse(seed.raw.toString("utf8")); }
  catch (error) { fail("seed_json_invalid", "clone_seed", error.message); }
  if (!opener.isValidSaveData(data)) {
    fail("seed_contract_invalid", "clone_seed", "seed shadow is not a valid v3 save");
  }
  const preparation = {
    seedSlot,
    targetSlot: TARGET_SLOT,
    seedSource: toRelative(seedFile),
    targetJson: toRelative(targetFile),
    seedSha256: sha256(seed.raw),
    semanticContract: "startup_normalization.v1",
    semanticSha256: opener.cloneSemanticSha256(data),
    role: data["0"][0],
    level: data["0"][3],
    backups: [],
    removedSolFiles: []
  };
  const backupDir = path.join(runDir, "save-backups");
  const oldTarget = backupRegularFile(targetFile, backupDir, "target-json");
  if (oldTarget) preparation.backups.push(toRelative(oldTarget));
  findOwnedSolFiles(TARGET_SLOT).forEach((solFile, index) => {
    const backup = backupRegularFile(solFile, backupDir, "target-sol-" + (index + 1));
    if (backup) preparation.backups.push(toRelative(backup));
    const before = opener.readRegularFileSnapshot(solFile, false, "clone_seed");
    if (!before || !opener.isOwnedSolPath(ROOT, TARGET_SLOT, solFile)) {
      fail("sol_ownership_lost", "clone_seed", "target SOL ownership changed before removal");
    }
    fs.unlinkSync(solFile);
    preparation.removedSolFiles.push(solFile);
  });
  const clone = JSON.parse(JSON.stringify(data));
  clone.lastSaved = formatLocalSaveTimestamp();
  const bytes = Buffer.from(JSON.stringify(clone), "utf8");
  const written = opener.writeAtomicRegularFile(ROOT, targetFile, bytes, "clone_seed");
  opener.assertExactSeededTargetBytes(bytes, written.raw);
  preparation.seededTargetSha256 = sha256(bytes);
  preparation.targetSha256 = preparation.seededTargetSha256;
  preparation.wroteSeed = true;
  return preparation;
}

function gitBuffer(args) {
  const result = childProcess.spawnSync("git", args, {
    cwd: ROOT,
    encoding: null,
    windowsHide: true,
    maxBuffer: 128 * 1024 * 1024
  });
  if (result.status !== 0) {
    fail("git_fingerprint_failed", "source_identity", "git command failed", {
      args,
      stderr: Buffer.from(result.stderr || []).toString("utf8").slice(-2000)
    });
  }
  return Buffer.from(result.stdout || []);
}

function hashFile(relativePath) {
  const absolute = path.resolve(ROOT, relativePath);
  const snapshot = opener.readRegularFileSnapshot(absolute, false, "source_identity");
  return { path: relativePath.replace(/\\/g, "/"), bytes: snapshot.raw.length, sha256: sha256(snapshot.raw) };
}

function captureSourceFingerprint() {
  const head = gitBuffer(["rev-parse", "HEAD"]).toString("utf8").trim();
  const status = gitBuffer(["status", "--porcelain=v1", "-z", "--untracked-files=all"]);
  const diff = gitBuffer(["diff", "HEAD", "--binary", "--no-ext-diff", "--"]);
  const untracked = gitBuffer(["ls-files", "--others", "--exclude-standard", "-z"])
    .toString("utf8").split("\0").filter(Boolean)
    .filter((name) => !/^(?:tmp|saves|logs)\//.test(name.replace(/\\/g, "/")));
  const untrackedHash = crypto.createHash("sha256");
  const untrackedFiles = [];
  untracked.sort().forEach((name) => {
    const absolute = path.resolve(ROOT, name);
    const relative = path.relative(ROOT, absolute);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      fail("untracked_path_escape", "source_identity", "untracked file escaped repository", { name });
    }
    const snapshot = opener.readRegularFileSnapshot(absolute, false, "source_identity");
    untrackedHash.update(Buffer.from(name, "utf8"));
    untrackedHash.update(Buffer.from([0]));
    untrackedHash.update(snapshot.raw);
    untrackedHash.update(Buffer.from([0]));
    untrackedFiles.push({ path: name.replace(/\\/g, "/"), bytes: snapshot.raw.length,
      sha256: sha256(snapshot.raw) });
  });
  const fingerprint = {
    head,
    statusSha256: sha256(status),
    diffSha256: sha256(diff),
    untrackedSha256: untrackedHash.digest("hex").toUpperCase(),
    statusEntries: status.toString("utf8").split("\0").filter(Boolean),
    untrackedFiles,
    assets: SOURCE_ASSETS.map(hashFile)
  };
  if (!validateSourceFingerprint(fingerprint)) {
    fail("source_fingerprint_shape_invalid", "source_identity",
      "captured Crafting source closure does not match its canonical asset inventory");
  }
  return fingerprint;
}

function assertFingerprint(expected, phase) {
  const actual = captureSourceFingerprint();
  if (!Verifier.deepEqual(expected, actual)) {
    fail("source_fingerprint_drift", phase, "current tree/assets changed during the A3 journey", {
      expected,
      actual
    });
  }
  return actual;
}

function recordSourceFingerprint(records, expected, phase) {
  const fingerprint = phase === "initial" ? expected : assertFingerprint(expected, phase);
  records.push({ phase, fingerprint });
  return fingerprint;
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  opener.assertCanonicalDirectoryChain(ROOT, path.dirname(filePath), "artifact_write");
  opener.writeAtomicRegularFile(ROOT, filePath, JSON.stringify(value, null, 2) + "\n", "artifact_write");
}

function emitStatus(paths, receipt, state, detail) {
  const payload = Object.assign({
    schema: "crafting-live-e2e.status.v1",
    runId: receipt.runId,
    state,
    at: new Date().toISOString(),
    cloneSlot: TARGET_SLOT,
    inputProvider: receipt.inputTrust.provider
  }, detail || {});
  writeJson(paths.status, payload);
  receipt.timeline.push(payload);
  process.stderr.write(JSON.stringify(payload) + "\n");
}

function assertPortAvailable(port) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.once("error", (error) => reject(new RunnerError(
      "cdp_port_in_use", "launcher", "CDP port is already in use", { port, message: error.message }
    )));
    server.listen({ host: "127.0.0.1", port, exclusive: true }, () => {
      server.close(() => resolve(true));
    });
  });
}

function withWebViewDebugEnvironment(cdpPort, callback) {
  const oldArgs = process.env.CF7_WEBVIEW2_ARGS;
  const oldMode = process.env.CF7_WEBVIEW2_DEV_MODE;
  if (oldArgs && oldArgs.trim()) {
    fail("webview_args_preexisting", "launcher",
      "CF7_WEBVIEW2_ARGS is already set; refusing to silently replace it", { value: oldArgs });
  }
  process.env.CF7_WEBVIEW2_ARGS = "--remote-debugging-port=" + cdpPort;
  process.env.CF7_WEBVIEW2_DEV_MODE = "1";
  try { return callback(); }
  finally {
    if (oldArgs === undefined) delete process.env.CF7_WEBVIEW2_ARGS;
    else process.env.CF7_WEBVIEW2_ARGS = oldArgs;
    if (oldMode === undefined) delete process.env.CF7_WEBVIEW2_DEV_MODE;
    else process.env.CF7_WEBVIEW2_DEV_MODE = oldMode;
  }
}

async function waitForCdp(cdpPort, recorderId, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() <= deadline) {
    try { return await Recorder.connectRecorder(cdpPort, recorderId); }
    catch (error) { lastError = error; }
    await sleep(pollMs);
  }
  fail("cdp_attach_timeout", "recorder", "could not attach passive recorder", {
    cdpPort,
    lastError: lastError ? lastError.message : null
  });
}

async function waitForProductionOverlay(connection, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() <= deadline) {
    try {
      const record = await Recorder.findProductionOverlayPage(connection);
      if (record) return record;
    } catch (error) { lastError = error; }
    await sleep(pollMs);
  }
  fail("production_overlay_timeout", "recorder",
    "fixed https://overlay.local/overlay.html surface was not observed", {
      lastError: lastError && lastError.message
    });
}

async function establishIngressFloor(connection, runtimeSession, label, args) {
  const record = await waitForProductionOverlay(
    connection, args.readyTimeoutMs, args.pollMs);
  const logSnapshot = await opener.readLogSnapshot(runtimeSession.port);
  const logWatermark = opener.logWatermark(logSnapshot);
  const sequence = await Recorder.checkpoint(record.page, label, {
    logFloor: logWatermark.total
  });
  if (!Number.isInteger(sequence) || sequence <= 0) {
    fail("ingress_floor_checkpoint_failed", "journey",
      "production overlay did not accept ingress floor checkpoint", { label });
  }
  return {
    page: record.page,
    sequence,
    logWatermark,
    preFloorRecords: opener.freshLogRecords(runtimeSession.startWatermark, logSnapshot)
  };
}

async function sealTerminalTail(page, runtimeSession, ingressFloor, label, args) {
  const deadline = Date.now() + args.readyTimeoutMs;
  let stableTotal = null;
  let stableSince = null;
  let stableSnapshot = null;
  while (Date.now() <= deadline) {
    const snapshot = await opener.readLogSnapshot(runtimeSession.port);
    if (snapshot.total !== stableTotal) {
      stableTotal = snapshot.total;
      stableSince = Date.now();
      stableSnapshot = snapshot;
    } else if (Date.now() - stableSince >= args.quietMs) {
      const sequence = await Recorder.checkpoint(page, label, { logEnd: stableTotal });
      const transcript = await Recorder.pageTranscript(page);
      const after = await opener.readLogSnapshot(runtimeSession.port);
      if (!Number.isInteger(sequence) || !transcript || transcript.sequence !== sequence
          || after.total !== stableTotal) {
        fail("terminal_tail_seal_raced", "tail",
          "Web/Host tail changed while terminal seal was captured", {
            label, sequence, transcriptSequence: transcript && transcript.sequence,
            expectedLogEnd: stableTotal, actualLogEnd: after.total
          });
      }
      return {
        transcript,
        records: opener.freshLogRecords(ingressFloor.logWatermark, stableSnapshot),
        tailSequence: sequence,
        tailLogEnd: stableTotal
      };
    }
    await sleep(args.pollMs);
  }
  fail("terminal_tail_seal_timeout", "tail",
    "Host log did not reach a quiet terminal seal", { label, stableTotal });
}

function parseInventoryHostLine(record) {
  const marker = "[InventoryTask] -> Flash: ";
  const index = record && typeof record.line === "string" ? record.line.indexOf(marker) : -1;
  if (index < 0) return null;
  try { return JSON.parse(record.line.slice(index + marker.length).trim()); }
  catch (_error) { return { malformed: true }; }
}

function assertTerminalWriteCounts(transcript, logRecords, expectedCount, phase) {
  const webWrites = (transcript.events || []).map((event) =>
    event.kind === "bridge_send" ? event.detail.message : null).filter((message) => {
    if (!message || message.type !== "panel") return false;
    if (message.domain === "crafting") return message.cmd === "commit";
    return message.domain === "inventory"
      && message.cmd !== "snapshot" && message.cmd !== "tooltip";
  });
  const hostWrites = [];
  for (const record of logRecords || []) {
    const crafting = Verifier.parseHostFlash(record);
    if (crafting && crafting.message && crafting.message.action === "craftingCommit") {
      hostWrites.push({ domain: "crafting", record, message: crafting.message });
    }
    const inventory = parseInventoryHostLine(record);
    if (inventory && inventory.action !== "inventorySnapshot"
        && inventory.action !== "inventoryTooltip") {
      hostWrites.push({ domain: "inventory", record, message: inventory });
    }
  }
  if (webWrites.length !== expectedCount || hostWrites.length !== expectedCount) {
    fail("tail_write_detected", phase,
      "terminal seal contains a missing, extra, or Host-only business write", {
        expectedCount,
        webWrites,
        hostWrites
      });
  }
  return { webWrites: webWrites.length, hostWrites: hostWrites.length };
}

function bindTranscriptEnvelope(transcript, runId, pid) {
  return Object.assign({}, transcript, {
    runId,
    cloneSlot: TARGET_SLOT,
    processPid: pid
  });
}

function runtimePublic(actual) {
  return RuntimeIdentity.publicRuntimeIdentity(actual);
}

async function launchRuntime(args, expectedIdentity, sourceFingerprint, phase) {
  assertFingerprint(sourceFingerprint, phase + "_source_before_start");
  if (await opener.discoverPort(ROOT)) {
    fail("launcher_already_running", phase, "an authenticated Launcher already exists");
  }
  opener.assertExclusiveLauncherProcess(opener.queryLauncherCoreProcesses(), null);
  await assertPortAvailable(args.cdpPort);
  withWebViewDebugEnvironment(args.cdpPort, () => opener.startLauncher(ROOT, expectedIdentity));
  const port = await opener.waitForPort(ROOT, args.readyTimeoutMs, args.pollMs);
  const actual = RuntimeIdentity.verifyRuntimeIdentity(ROOT, port, expectedIdentity);
  opener.assertExclusiveLauncherProcess(opener.queryLauncherCoreProcesses(), actual.pid);
  const context = LegacyHttpClient.readExactLauncherHttpContext(ROOT);
  const startSnapshot = await opener.readLogSnapshot(port);
  const startWatermark = opener.logWatermark(startSnapshot);
  const startResponse = await opener.agent(port, "start", {
    slot: TARGET_SLOT,
    fresh: false,
    deferReveal: false,
    requireFlashReveal: true,
    rememberSlot: false
  });
  opener.assertResponseSucceeded(startResponse, phase, "agent_control start");
  const timeline = [];
  const runtime = await opener.waitForRuntimeReady(port, {
    slot: TARGET_SLOT,
    readyTimeoutMs: args.readyTimeoutMs,
    pollMs: args.pollMs
  }, startWatermark, startResponse, timeline);
  const readyIdentity = RuntimeIdentity.verifyRuntimeIdentity(ROOT, port, expectedIdentity);
  if (readyIdentity.pid !== actual.pid) {
    fail("runtime_pid_changed", phase, "Launcher PID changed during runtime readiness");
  }
  opener.assertExclusiveLauncherProcess(opener.queryLauncherCoreProcesses(), actual.pid);
  return {
    port,
    httpPort: port,
    cdpPort: args.cdpPort,
    pid: actual.pid,
    credentialPath: context.credential.path,
    identity: runtimePublic(readyIdentity),
    startWatermark,
    startResponse,
    runtime,
    timeline,
    portEvidence: {
      launcherPortsBound: true,
      authenticatedHttpEndpoint: true,
      cdpEndpointObserved: false,
      httpPort: port,
      cdpPort: args.cdpPort
    }
  };
}

async function closeStartupBaseline(preparation, runtimeSession, reference) {
  const expected = reference || {
    sha256: preparation.seededTargetSha256,
    semanticSha256: preparation.semanticSha256,
    role: preparation.role,
    level: preparation.level
  };
  let baseline = await opener.captureStableCloneBaseline(ROOT, preparation);
  const logSnapshot = await opener.readLogSnapshot(runtimeSession.port);
  const records = opener.freshLogRecords(runtimeSession.startWatermark, logSnapshot);
  const premature = records.find((record) => record.line.includes("[CraftingTask] -> Flash:")
    || (record.line.includes("[XmlSocket:JSON]") && record.line.includes('"panel":"crafting"')));
  if (premature) {
    fail("crafting_before_baseline", "startup_baseline",
      "crafting traffic occurred before startup clone baseline closed", premature);
  }
  if (baseline.semanticSha256 !== expected.semanticSha256
      || String(baseline.role) !== String(expected.role)
      || String(baseline.level) !== String(expected.level)) {
    fail("startup_semantic_drift", "startup_baseline",
      "startup normalization changed semantic save data", baseline);
  }
  const floor = Math.max(
    runtimeSession.startWatermark.total,
    runtimeSession.runtime.handoffEvidence.lineNumber,
    runtimeSession.runtime.titleFrameEvidence.lineNumber
  );
  const target = path.resolve(ROOT, preparation.targetJson);
  const archive = records.filter((record) => record.lineNumber > floor)
    .map((record) => opener.parseStartupArchiveReceipt(record, TARGET_SLOT, target))
    .filter(Boolean).pop() || null;
  baseline.changedFromReference = baseline.sha256 !== expected.sha256;
  if (baseline.changedFromReference && (!archive || archive.archiveChars !== baseline.textChars)) {
    fail("startup_archive_missing", "startup_baseline",
      "startup byte normalization lacks an exact archive receipt", { baseline, archive });
  }
  baseline.startupArchiveReceipt = archive;
  baseline.postCaptureLogWatermark = opener.logWatermark(logSnapshot);
  preparation.gateBaseline = baseline;
  return baseline;
}

function pendingCraftingCalls(transcript, afterSequence) {
  const requests = new Set();
  const responses = new Set();
  for (const event of transcript.events || []) {
    if (event.sequence <= afterSequence) continue;
    const outbound = event.kind === "bridge_send" ? event.detail.message : null;
    const inbound = event.kind === "host_message" ? event.detail.message : null;
    if (outbound && outbound.type === "panel" && outbound.domain === "crafting") {
      requests.add(outbound.callId);
    }
    if (inbound && inbound.type === "panel_resp" && inbound.domain === "crafting") {
      responses.add(inbound.callId);
    }
  }
  return Array.from(requests).filter((callId) => !responses.has(callId));
}

function pendingAuthorityCalls(transcript, afterSequence) {
  const requests = new Map();
  const responses = new Set();
  for (const event of transcript.events || []) {
    if (event.sequence <= afterSequence) continue;
    const outbound = event.kind === "bridge_send" ? event.detail.message : null;
    const inbound = event.kind === "host_message" ? event.detail.message : null;
    if (outbound && outbound.type === "panel"
        && (outbound.domain === "crafting" || outbound.domain === "inventory")) {
      requests.set(outbound.domain + ":" + outbound.callId, outbound);
    }
    if (inbound && inbound.type === "panel_resp"
        && (inbound.domain === "crafting" || inbound.domain === "inventory")) {
      responses.add(inbound.domain + ":" + inbound.callId);
    }
  }
  return Array.from(requests.keys()).filter((key) => !responses.has(key));
}

function hasSuccessfulResponseAfter(transcript, floor, cmd, predicate) {
  return (transcript.events || []).some((event) => {
    if (event.sequence <= floor || event.kind !== "host_message") return false;
    const message = event.detail.message;
    return message && message.type === "panel_resp" && message.domain === "crafting"
      && message.cmd === cmd && message.success === true && (!predicate || predicate(message));
  });
}

function successfulAuthorityResponseAfter(transcript, floor, domain, cmd, predicate) {
  return (transcript.events || []).find((event) => {
    if (event.sequence <= floor || event.kind !== "host_message") return false;
    const message = event.detail.message;
    return message && message.type === "panel_resp" && message.domain === domain
      && message.cmd === cmd && message.success === true && (!predicate || predicate(message));
  }) || null;
}

async function waitForInventoryAuthorityAndReturn(page, afterSequence, args, phase) {
  const deadline = Date.now() + args.interactionTimeoutMs;
  let stableSequence = null;
  let stableSince = null;
  let last = null;
  while (Date.now() <= deadline) {
    const transcript = await Recorder.pageTranscript(page);
    if (!transcript) fail("recorder_lost", phase, "production recorder disappeared");
    const inventory = successfulAuthorityResponseAfter(
      transcript, afterSequence, "inventory", "snapshot");
    const pending = pendingAuthorityCalls(transcript, afterSequence);
    const returned = await page.evaluate(() => {
      const organizer = document.querySelector('[data-workbench-owner-context="crafting-organizer"]');
      const recipe = document.querySelector(".crafting-catalog-grid .crafting-recipe-card");
      return !organizer && !!recipe;
    });
    if (inventory && pending.length === 0 && returned) {
      if (stableSequence !== transcript.sequence) {
        stableSequence = transcript.sequence;
        stableSince = Date.now();
      } else if (Date.now() - stableSince >= args.quietMs) {
        return {
          transcript,
          inventoryResponse: inventory.detail.message,
          inventoryResponseSequence: inventory.sequence
        };
      }
    } else {
      stableSequence = null;
      stableSince = null;
    }
    last = { sequence: transcript.sequence, inventory: !!inventory, pending, returned };
    await sleep(args.pollMs);
  }
  fail("inventory_authority_timeout", phase,
    "Inventory authority snapshot and normal return did not settle", last);
}

async function establishInteractionFloor(page, runtimeSession, label, candidate, ingress) {
  const log = await opener.readLogSnapshot(runtimeSession.port);
  const logWatermark = opener.logWatermark(log);
  const sequence = await Recorder.checkpoint(page, label, {
    logFloor: logWatermark.total,
    candidate,
    ingress
  });
  if (!Number.isInteger(sequence) || sequence <= 0) {
    fail("interaction_floor_checkpoint_failed", "journey",
      "production overlay did not accept interaction floor checkpoint", { label });
  }
  return { sequence, logWatermark };
}

async function assertRecipeCandidateStable(page, candidate) {
  const refreshed = await Recorder.inspectRecipe(page, candidate.recipeIndex);
  const expected = candidate && candidate.output;
  const actual = refreshed && refreshed.output;
  if (!refreshed || refreshed.visible !== true || refreshed.disabled === true
      || refreshed.canCraftOne !== true || !expected || !actual
      || expected.name !== actual.name || expected.displayName !== actual.displayName
      || expected.icon !== actual.icon) {
    fail("recipe_candidate_drift", "initial_inventory",
      "read-only Inventory inspection changed the selected ready recipe", {
        expected: candidate,
        actual: refreshed
      });
  }
  return refreshed;
}

async function waitForPanelReady(connection, runtimeSession, args, options) {
  const deadline = Date.now() + options.timeoutMs;
  let stableSequence = null;
  let stableSince = null;
  let lastObserved = null;
  while (Date.now() <= deadline) {
    const record = await Recorder.findCraftingPage(connection);
    if (record) {
      const snapshot = await opener.readLogSnapshot(runtimeSession.port);
      const ingressRecords = opener.freshLogRecords(options.ingressFloor.logWatermark, snapshot);
      let ingress;
      try {
        ingress = Verifier.validateIngress(record.transcript, ingressRecords, {
          entryFloorSequence: options.ingressFloor.sequence,
          expectedCategory: options.expectedCategory || null
        });
      } catch (error) {
        const waitingForFirstEvidence = error instanceof Verifier.GateError
          && (error.code === "production_open_count_invalid"
            || error.code === "as2_panel_request_count_invalid")
          && error.details && error.details.count === 0;
        if (!waitingForFirstEvidence) throw error;
      }
      if (ingress) {
        const pending = pendingCraftingCalls(record.transcript, ingress.openSequence);
        const hasSnapshot = hasSuccessfulResponseAfter(
          record.transcript, ingress.openSequence, "snapshot"
        );
        let candidate = null;
        if (options.expectedRecipeIndex == null) {
          const ready = await Recorder.inspectReadyRecipes(record.page);
          candidate = ready.sort((left, right) => left.recipeIndex - right.recipeIndex)[0] || null;
        } else {
          candidate = await Recorder.inspectRecipe(record.page, options.expectedRecipeIndex);
        }
        const usable = candidate && candidate.visible && !candidate.disabled
          && (options.expectedRecipeIndex != null || candidate.canCraftOne === true);
        if (pending.length === 0 && hasSnapshot && usable) {
          if (stableSequence !== record.transcript.sequence) {
            stableSequence = record.transcript.sequence;
            stableSince = Date.now();
          } else if (Date.now() - stableSince >= args.quietMs) {
            if (options.deferInteractionFloor === true) {
              const transcript = await Recorder.pageTranscript(record.page);
              return {
                page: record.page,
                transcript,
                ingress,
                candidate,
                ingressFloorSequence: options.ingressFloor.sequence,
                ingressLogWatermark: options.ingressFloor.logWatermark,
                interactionFloorSequence: null,
                interactionLogWatermark: null,
                ingressRecords
              };
            }
            const interactionLog = await opener.readLogSnapshot(runtimeSession.port);
            const interactionLogWatermark = opener.logWatermark(interactionLog);
            const interactionFloorSequence = await Recorder.checkpoint(
              record.page,
              options.checkpointLabel,
              { logFloor: interactionLogWatermark.total, candidate, ingress }
            );
            const transcript = await Recorder.pageTranscript(record.page);
            return {
              page: record.page,
              transcript,
              ingress,
              candidate,
              ingressFloorSequence: options.ingressFloor.sequence,
              ingressLogWatermark: options.ingressFloor.logWatermark,
              interactionFloorSequence,
              interactionLogWatermark,
              ingressRecords
            };
          }
        } else {
          stableSequence = null;
          stableSince = null;
        }
        lastObserved = { ingress, pending, hasSnapshot, candidate };
      }
    }
    await sleep(args.pollMs);
  }
  fail("production_ingress_timeout", options.phase,
    "production Crafting panel did not reach a settled attach point", lastObserved);
}

async function waitForCommitEvidence(page, runtimeSession, gate, args) {
  const deadline = Date.now() + args.interactionTimeoutMs;
  let stableSequence = null;
  let stableSince = null;
  let last = null;
  while (Date.now() <= deadline) {
    const transcript = await Recorder.pageTranscript(page);
    if (!transcript) fail("recorder_lost", "commit", "crafting recorder disappeared");
    const floor = gate.interactionFloorSequence;
    const events = transcript.events || [];
    const commitResponse = events.find((event) => event.sequence > floor
      && event.kind === "host_message" && event.detail.message
      && event.detail.message.type === "panel_resp"
      && event.detail.message.domain === "crafting"
      && event.detail.message.cmd === "commit"
      && event.detail.message.success === true);
    const freshSnapshot = commitResponse && events.find((event) => event.sequence > commitResponse.sequence
      && event.kind === "host_message" && event.detail.message
      && event.detail.message.type === "panel_resp"
      && event.detail.message.domain === "crafting"
      && event.detail.message.cmd === "snapshot"
      && event.detail.message.success === true);
    const freshPreview = freshSnapshot && events.find((event) => event.sequence > freshSnapshot.sequence
      && event.kind === "host_message" && event.detail.message
      && event.detail.message.type === "panel_resp"
      && event.detail.message.domain === "crafting"
      && event.detail.message.cmd === "preview"
      && event.detail.message.success === true);
    const pending = pendingCraftingCalls(transcript, floor);
    if (commitResponse && freshSnapshot && freshPreview && pending.length === 0) {
      if (stableSequence !== transcript.sequence) {
        stableSequence = transcript.sequence;
        stableSince = Date.now();
      } else if (Date.now() - stableSince >= args.quietMs) {
        const logSnapshot = await opener.readLogSnapshot(runtimeSession.port);
        const records = opener.freshLogRecords(gate.interactionLogWatermark, logSnapshot);
        return {
          transcript,
          logSnapshot,
          logRecords: records,
          verified: Verifier.verifyCommitJourney({
            transcript,
            logRecords: records,
            interactionFloorSequence: floor,
            ingress: gate.ingress
          })
        };
      }
    } else {
      stableSequence = null;
      stableSince = null;
    }
    last = {
      sequence: transcript.sequence,
      commitResponse: !!commitResponse,
      freshSnapshot: !!freshSnapshot,
      freshPreview: !!freshPreview,
      pending
    };
    await sleep(args.pollMs);
  }
  fail("commit_evidence_timeout", "commit", "trusted commit/fresh authority chain timed out", last);
}

async function waitForSelectedPreview(page, gate, args) {
  const deadline = Date.now() + args.interactionTimeoutMs;
  let stableSequence = null;
  let stableSince = null;
  let last = null;
  while (Date.now() <= deadline) {
    const transcript = await Recorder.pageTranscript(page);
    if (!transcript) fail("recorder_lost", "recipe_select", "crafting recorder disappeared");
    const events = transcript.events || [];
    const prematureCommit = events.find((event) => event.sequence > gate.interactionFloorSequence
      && event.kind === "bridge_send" && event.detail.message
      && event.detail.message.type === "panel" && event.detail.message.domain === "crafting"
      && event.detail.message.cmd === "commit");
    if (prematureCommit) {
      fail("commit_before_authorization", "recipe_select",
        "commit was issued before its one-shot control request", prematureCommit);
    }
    const preview = events.find((event) => event.sequence > gate.interactionFloorSequence
      && event.kind === "host_message" && event.detail.message
      && event.detail.message.type === "panel_resp"
      && event.detail.message.domain === "crafting" && event.detail.message.cmd === "preview"
      && event.detail.message.success === true
      && event.detail.message.recipeIndex === gate.candidate.recipeIndex
      && event.detail.message.canCommit === true);
    const trustedClick = events.find((event) => event.sequence > gate.interactionFloorSequence
      && event.sequence < (preview ? preview.sequence : Number.MAX_SAFE_INTEGER)
      && event.kind === "capture_click" && event.detail.browserEventIsTrusted === true
      && String(event.detail.selector || "").includes("crafting-recipe-card")
      && String(event.detail.workbenchKey) === String(gate.candidate.recipeIndex));
    const pending = pendingCraftingCalls(transcript, gate.interactionFloorSequence);
    if (preview && trustedClick && pending.length === 0) {
      if (stableSequence !== transcript.sequence) {
        stableSequence = transcript.sequence;
        stableSince = Date.now();
      } else if (Date.now() - stableSince >= args.quietMs) {
        return {
          transcript,
          preview: preview.detail.message,
          previewSequence: preview.sequence,
          clickSequence: trustedClick.sequence
        };
      }
    } else {
      stableSequence = null;
      stableSince = null;
    }
    last = { sequence: transcript.sequence, preview: !!preview,
      trustedClick: !!trustedClick, pending };
    await sleep(args.pollMs);
  }
  fail("selected_preview_timeout", "recipe_select",
    "trusted recipe click and selected authority preview timed out", last);
}

async function waitForReadbackEvidence(page, runtimeSession, gate, expected, args) {
  const deadline = Date.now() + args.readbackTimeoutMs;
  let stableSequence = null;
  let stableSince = null;
  let last = null;
  while (Date.now() <= deadline) {
    const transcript = await Recorder.pageTranscript(page);
    if (!transcript) fail("readback_recorder_lost", "readback", "readback recorder disappeared");
    const floor = gate.interactionFloorSequence;
    const matched = hasSuccessfulResponseAfter(transcript, floor, "preview", (message) =>
      message.recipeIndex === expected.recipeIndex && message.craftCount === expected.craftCount);
    const pending = pendingCraftingCalls(transcript, floor);
    if (matched && pending.length === 0) {
      if (stableSequence !== transcript.sequence) {
        stableSequence = transcript.sequence;
        stableSince = Date.now();
      } else if (Date.now() - stableSince >= args.quietMs) {
        const logSnapshot = await opener.readLogSnapshot(runtimeSession.port);
        const records = opener.freshLogRecords(gate.interactionLogWatermark, logSnapshot);
        return {
          transcript,
          logSnapshot,
          logRecords: records,
          verified: Verifier.verifyReadbackJourney({
            transcript,
            logRecords: records,
            interactionFloorSequence: floor,
            ingress: gate.ingress,
            expectedPoststate: expected
          })
        };
      }
    } else {
      stableSequence = null;
      stableSince = null;
    }
    last = { sequence: transcript.sequence, matched, pending };
    await sleep(args.pollMs);
  }
  fail("readback_evidence_timeout", "readback", "trusted restart readback timed out", last);
}

async function waitForArchive(runtimeSession, commit, baseline, args) {
  const deadline = Date.now() + args.saveTimeoutMs;
  const target = savePath(TARGET_SLOT);
  const commitLine = commit.hostCorrelation.find((entry) => entry.cmd === "commit").hostLogLine;
  let last = null;
  while (Date.now() <= deadline) {
    const snapshot = await opener.readLogSnapshot(runtimeSession.port);
    const records = opener.freshLogRecords(runtimeSession.startWatermark, snapshot);
    const archive = records.filter((record) => record.lineNumber > commitLine)
      .map((record) => opener.parseStartupArchiveReceipt(record, TARGET_SLOT, target))
      .filter(Boolean).pop() || null;
    if (archive) {
      const persisted = await opener.captureStableCloneBaseline(ROOT, {
        targetSlot: TARGET_SLOT,
        targetJson: toRelative(target)
      });
      if (archive.archiveChars !== persisted.textChars) {
        fail("archive_char_count_mismatch", "persistence",
          "archive receipt does not match persisted clone length", { archive, persisted });
      }
      if (persisted.semanticSha256 === baseline.semanticSha256) {
        fail("clone_semantic_unchanged", "persistence",
          "commit produced no semantic clone change", { baseline, persisted });
      }
      return { archive, persisted, finalLogTotal: snapshot.total };
    }
    last = { finalLogTotal: snapshot.total, commitLine };
    await sleep(args.pollMs);
  }
  fail("archive_timeout", "persistence", "safe save did not emit exact clone archive receipt", last);
}

function cdpOpen(port) {
  return new Promise((resolve) => {
    const request = http.get({ hostname: "127.0.0.1", port, path: "/json/version", timeout: 800 },
      (response) => { response.resume(); resolve(true); });
    request.on("timeout", () => { request.destroy(); resolve(false); });
    request.on("error", () => resolve(false));
  });
}

function psQuote(value) {
  return "'" + String(value).replace(/'/g, "''") + "'";
}

function queryProjectProcesses() {
  if (process.platform !== "win32") return [];
  const root = path.resolve(ROOT).toLowerCase();
  const script = [
    "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)",
    "$root = " + psQuote(root),
    "$records = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('CRAZYFLASHER7MercenaryEmpire.Core.exe','CRAZYFLASHER7MercenaryEmpire.exe','Adobe Flash Player 20.exe','msedgewebview2.exe') } | ForEach-Object {",
    "  $exe = if ($_.ExecutablePath) { [string]$_.ExecutablePath } else { '' }",
    "  $cmd = if ($_.CommandLine) { [string]$_.CommandLine } else { '' }",
    "  $match = ($exe.ToLowerInvariant().StartsWith($root)) -or (($cmd.ToLowerInvariant().Contains($root)) -and ($cmd -like '*webview2*'))",
    "  if ($match) { [pscustomobject]@{ pid=[int]$_.ProcessId; parentPid=[int]$_.ParentProcessId; name=[string]$_.Name; executablePath=$exe } }",
    "})",
    "ConvertTo-Json -InputObject $records -Compress"
  ].join("\n");
  const result = childProcess.spawnSync("powershell.exe",
    ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
    { encoding: "utf8", windowsHide: true, timeout: 10000 });
  if (result.status !== 0) {
    fail("residue_process_query_failed", "shutdown", "could not query project processes", {
      stderr: String(result.stderr || "").slice(-2000)
    });
  }
  try {
    const parsed = JSON.parse(String(result.stdout || "[]"));
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    fail("residue_process_json_invalid", "shutdown", error.message);
  }
}

async function supportedShutdownAndResidue(runtimeSession, args, phase) {
  const before = RuntimeIdentity.verifyRuntimeIdentity(ROOT, runtimeSession.port,
    RuntimeIdentity.resolveExpectedRuntimeIdentity(ROOT, args.candidateRoot));
  if (before.pid !== runtimeSession.pid) {
    fail("shutdown_identity_mismatch", phase, "refusing to shut down a different Launcher");
  }
  const response = await opener.shutdownLauncher(runtimeSession.port);
  if (!response || (response.success !== true && response.ok !== true)) {
    fail("supported_shutdown_failed", phase, "agent_control shutdown failed", response);
  }
  const deadline = Date.now() + args.shutdownTimeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    const processes = queryProjectProcesses();
    const portsExists = fs.existsSync(path.join(ROOT, "launcher_ports.json"));
    const credentialExists = fs.existsSync(runtimeSession.credentialPath);
    const debugOpen = await cdpOpen(args.cdpPort);
    if (!processExists(runtimeSession.pid) && processes.length === 0
        && !portsExists && !credentialExists && !debugOpen) {
      return {
        supportedShutdown: true,
        oldPid: runtimeSession.pid,
        processExited: true,
        projectProcesses: [],
        launcherPortsFileAbsent: true,
        credentialAbsent: true,
        cdpPortClosed: true,
        checkedAt: new Date().toISOString()
      };
    }
    last = { processes, portsExists, credentialExists, debugOpen,
      pidAlive: processExists(runtimeSession.pid) };
    await sleep(args.pollMs);
  }
  fail("shutdown_residue_timeout", phase, "supported shutdown left project residue", last);
}

function artifactPaths(runId) {
  const runDir = path.join(ROOT, "tmp", "workbench-live-e2e", "crafting", runId);
  fs.mkdirSync(runDir, { recursive: true });
  opener.assertCanonicalDirectoryChain(ROOT, runDir, "artifact_init");
  return {
    runDir,
    status: path.join(runDir, "status.json"),
    receipt: path.join(runDir, "receipt.json"),
    firstTranscript: path.join(runDir, "commit-transcript.json"),
    firstLogs: path.join(runDir, "commit-log-records.json"),
    firstBundle: path.join(runDir, "commit-verification-input.json"),
    readbackTranscript: path.join(runDir, "readback-transcript.json"),
    readbackLogs: path.join(runDir, "readback-log-records.json"),
    readbackBundle: path.join(runDir, "readback-verification-input.json"),
    sessionBundle: path.join(runDir, "session-verification-input.json"),
    sessionEvidence: path.join(runDir, "session-evidence.json"),
    sessionVerification: path.join(runDir, "session-verification.json"),
    firstTranscriptV2: path.join(runDir, "first-transcript.json"),
    firstLogsV2: path.join(runDir, "first-logs.json"),
    restartTranscriptV2: path.join(runDir, "restart-transcript.json"),
    restartLogsV2: path.join(runDir, "restart-logs.json"),
    runtimeEvidence: path.join(runDir, "runtime.json"),
    persistenceEvidence: path.join(runDir, "persistence.json"),
    sourceFingerprints: path.join(runDir, "source-fingerprints.json"),
    seedInvariant: path.join(runDir, "seed-invariant.json"),
    controlEvidence: path.join(runDir, "control.json")
  };
}

function rawArtifactPaths(paths) {
  return {
    firstTranscript: paths.firstTranscriptV2,
    firstLogs: paths.firstLogsV2,
    restartTranscript: paths.restartTranscriptV2,
    restartLogs: paths.restartLogsV2,
    runtime: paths.runtimeEvidence,
    persistence: paths.persistenceEvidence,
    sourceFingerprints: paths.sourceFingerprints,
    seedInvariant: paths.seedInvariant,
    control: paths.controlEvidence
  };
}

function buildArtifactManifest(paths) {
  const mapping = rawArtifactPaths(paths);
  return SessionVerifier.RAW_ROLES.map((role) => {
    const filePath = mapping[role];
    const relative = path.relative(paths.runDir, filePath);
    if (!filePath || relative.startsWith("..") || path.isAbsolute(relative)) {
      fail("artifact_manifest_path_invalid", "artifacts",
        "raw artifact escaped the owned session directory", { role, filePath });
    }
    const snapshot = opener.readRegularFileSnapshot(filePath, false, "artifacts");
    return {
      role,
      path: relative.replace(/\\/g, "/"),
      bytes: snapshot.raw.length,
      sha256: sha256(snapshot.raw)
    };
  });
}

function stableRuntimeIdentity(identity) {
  return {
    runtimeMode: identity.runtimeMode,
    processPath: identity.processPath,
    coreSha256: identity.coreSha256,
    buildIdentity: identity.buildIdentity,
    payloadClosure: identity.payloadClosure
  };
}

function runtimeSessionEvidence(runtimeSession) {
  return {
    pid: runtimeSession.pid,
    httpPort: runtimeSession.httpPort,
    cdpPort: runtimeSession.cdpPort,
    startLogFloor: runtimeSession.startWatermark.total,
    identity: runtimeSession.identity,
    portEvidence: runtimeSession.portEvidence
  };
}

function buildRuntimeEvidence(runId, expectedIdentity, firstRuntime, restartRuntime) {
  return {
    runId,
    cloneSlot: TARGET_SLOT,
    expectedStable: stableRuntimeIdentity(expectedIdentity),
    first: runtimeSessionEvidence(firstRuntime),
    restart: runtimeSessionEvidence(restartRuntime)
  };
}

function buildPersistenceEvidence(receipt, firstLogs) {
  const archive = receipt.persistence && receipt.persistence.archive;
  const archiveRecord = archive && firstLogs.records.find((record) =>
    record.lineNumber === archive.lineNumber);
  const seedJson = receipt.seedInvariant.before.files.find((file) => file.kind === "json");
  if (!archive || !archiveRecord || !seedJson || !receipt.persistence.restartBaseline) {
    fail("persistence_artifact_incomplete", "artifacts",
      "persistence evidence cannot be projected from the closed journey");
  }
  return {
    runId: receipt.runId,
    cloneSlot: TARGET_SLOT,
    lock: receipt.cloneLock,
    clonePreparation: {
      seedSlot: receipt.seedSlot,
      targetSlot: TARGET_SLOT,
      seedSetSha256: receipt.seedInvariant.before.setSha256,
      seedJsonSha256: seedJson.sha256,
      seedSemanticSha256: receipt.clonePreparation.semanticSha256,
      seededTargetSha256: receipt.clonePreparation.seededTargetSha256
    },
    initialBaseline: receipt.clonePreparation.gateBaseline,
    archive: {
      slot: TARGET_SLOT,
      status: "archived",
      lineNumber: archive.lineNumber,
      targetPath: archive.targetPath,
      archiveChars: archive.archiveChars,
      lineSha256: sha256(Buffer.from(archiveRecord.line, "utf8"))
    },
    persisted: receipt.persistence.persisted,
    restartBaseline: receipt.persistence.restartBaseline,
    firstShutdown: receipt.firstShutdown,
    finalShutdown: receipt.finalShutdown
  };
}

function serializeError(error) {
  return {
    name: error && error.name || "Error",
    code: error && error.code || "unexpected_error",
    phase: error && error.phase || "main",
    message: error && error.message || String(error),
    details: error && error.details || null,
    stack: error && error.stack || null
  };
}

async function run(args) {
  assertArgs(args);
  if (!CONTROL_INTEGRATION_READY) {
    fail("shared_control_not_frozen", "preflight",
      "Crafting live mutation is disabled until the shared control/capture contract is frozen");
  }
  const runId = timestampId() + "-" + process.pid;
  const paths = artifactPaths(runId);
  const receipt = {
    schema: "crafting.production-write-receipt.v1",
    gate: "A3_CRAFTING_PRODUCTION_WRITE",
    runId,
    status: "running",
    startedAt: new Date().toISOString(),
    finishedAt: null,
    runtimeMode: "isolated_candidate",
    deploymentStatus: "NOT_DEPLOYED",
    cloneSlot: TARGET_SLOT,
    seedSlot: args.seedSlot,
    inputTrust: {
      provider: args.inputProvider,
      webBusinessClicksRequireIsTrusted: true,
      flashIngressEvidence: "external computer-use trace + exact world_crafting_entry AS2 request",
      flashIngressTrustedByRunner: false,
      syntheticCdpBusinessInputAllowed: false
    },
    scope: {
      runnerClicksBusinessControls: false,
      runnerSendsCraftingBusinessCommands: false,
      runnerSendsSaveCommands: false,
      playerSaveReadOnlySeed: true,
      playerSaveWritten: false,
      dedicatedCloneOnly: true,
      exactlyOneWriteRequired: true,
      safeExitUiJourneyVerified: false,
      outputInventoryCountReadbackVerified: false
    },
    sourceFingerprint: null,
    sourceFingerprints: { runId, cloneSlot: TARGET_SLOT, records: [] },
    seedInvariant: { runId, cloneSlot: TARGET_SLOT, before: null, after: null },
    cloneLock: null,
    runtimeIdentity: null,
    clonePreparation: null,
    firstRuntime: null,
    firstIngress: null,
    commit: null,
    persistence: null,
    firstShutdown: null,
    restartRuntime: null,
    readbackIngress: null,
    readback: null,
    independentSessionVerification: null,
    finalShutdown: null,
    artifacts: {
      status: toRelative(paths.status),
      receipt: toRelative(paths.receipt),
      commitTranscript: toRelative(paths.firstTranscript),
      commitLogs: toRelative(paths.firstLogs),
      commitVerificationInput: toRelative(paths.firstBundle),
      readbackTranscript: toRelative(paths.readbackTranscript),
      readbackLogs: toRelative(paths.readbackLogs),
      readbackVerificationInput: toRelative(paths.readbackBundle),
      sessionVerificationInput: toRelative(paths.sessionBundle)
    },
    timeline: [],
    error: null
  };
  let firstRuntime = null;
  let restartRuntime = null;
  let firstConnection = null;
  let restartConnection = null;
  let writeObserved = false;
  let commitVerificationInput = null;
  let caught = null;
  let cloneLock = null;
  let expectedIdentity = null;
  let firstTailEvidence = null;
  let restartTailEvidence = null;
  let firstLogsV2 = null;
  let restartLogsV2 = null;
  try {
    receipt.sourceFingerprint = captureSourceFingerprint();
    recordSourceFingerprint(
      receipt.sourceFingerprints.records, receipt.sourceFingerprint, "initial");
    expectedIdentity = RuntimeIdentity.resolveExpectedRuntimeIdentity(ROOT, args.candidateRoot);
    if (expectedIdentity.runtimeMode !== "isolated_candidate") {
      fail("isolated_candidate_required", "runtime_identity", "A3 cannot run against formal runtime");
    }
    receipt.runtimeIdentity = RuntimeIdentity.createRuntimeIdentityReport(expectedIdentity);
    if (await opener.discoverPort(ROOT)) {
      fail("launcher_present_before_clone", "clone_seed", "stop the existing Launcher before A3");
    }
    opener.assertExclusiveLauncherProcess(opener.queryLauncherCoreProcesses(), null);
    receipt.seedInvariant.before = captureSeedFileSet(args.seedSlot);
    cloneLock = acquireCloneLock(runId);
    receipt.cloneLock = cloneLock.evidence;
    receipt.clonePreparation = prepareClone(paths.runDir, args.seedSlot);
    recordSourceFingerprint(receipt.sourceFingerprints.records,
      receipt.sourceFingerprint, "after_clone_seed");

    firstRuntime = await launchRuntime(args, expectedIdentity, receipt.sourceFingerprint, "first_runtime");
    receipt.firstRuntime = firstRuntime;
    RuntimeIdentity.recordObservedRuntimeIdentity(receipt.runtimeIdentity, firstRuntime.identity);
    RuntimeIdentity.recordVerifiedRuntimeIdentity(receipt.runtimeIdentity, firstRuntime.identity);
    const startupBaseline = await closeStartupBaseline(receipt.clonePreparation, firstRuntime);
    receipt.clonePreparation.gateBaseline = startupBaseline;
    firstConnection = await waitForCdp(args.cdpPort,
      "crafting-" + runId + "-initial", args.readyTimeoutMs, args.pollMs);
    firstRuntime.portEvidence.cdpEndpointObserved = true;
    const firstIngressFloor = await establishIngressFloor(
      firstConnection, firstRuntime, "first_ingress_floor", args);

    emitStatus(paths, receipt, "awaiting_production_ingress", {
      instruction: [
        "Use visible computer-use only.",
        "Click Native HUD 地图, select 地下一层 if needed, then click 武器库.",
        "Inside the real Flash 武器库 click one real 合成 button.",
        "Do not call Panels/openCraftingWorkbench/Bridge.send or /console business functions."
      ],
      ingress: { source: "world_crafting_entry", panel: "crafting" }
    });
    const firstGate = await waitForPanelReady(firstConnection, firstRuntime, args, {
      phase: "first_ingress",
      timeoutMs: args.ingressTimeoutMs,
      ingressFloor: firstIngressFloor,
      deferInteractionFloor: true
    });
    emitStatus(paths, receipt, "awaiting_initial_inventory_authority", {
      instruction: [
        "Click the visible 背包 / 战备箱 button with computer-use.",
        "Wait for both containers to load, then click 返回合成.",
        "Do not move, split, equip, or otherwise mutate Inventory."
      ],
      inventoryWindows: [
        { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
        { containerId: "战备箱", offset: 0, limit: 40, filterKey: "all" }
      ]
    });
    const initialInventory = await waitForInventoryAuthorityAndReturn(
      firstGate.page, firstGate.transcript.sequence, args, "initial_inventory");
    firstGate.candidate = await assertRecipeCandidateStable(
      firstGate.page, firstGate.candidate);
    const firstInteractionFloor = await establishInteractionFloor(
      firstGate.page, firstRuntime, "first_interaction_floor",
      firstGate.candidate, firstGate.ingress);
    firstGate.interactionFloorSequence = firstInteractionFloor.sequence;
    firstGate.interactionLogWatermark = firstInteractionFloor.logWatermark;
    receipt.firstIngress = {
      ...firstGate.ingress,
      ingressFloorSequence: firstGate.ingressFloorSequence,
      ingressLogWatermark: firstGate.ingressLogWatermark,
      interactionFloorSequence: firstGate.interactionFloorSequence,
      interactionLogWatermark: firstGate.interactionLogWatermark,
      candidate: firstGate.candidate,
      initialInventory: {
        callId: initialInventory.inventoryResponse.callId,
        responseSequence: initialInventory.inventoryResponseSequence
      }
    };
    emitStatus(paths, receipt, "awaiting_trusted_recipe", {
      instruction: [
        "Click the exact visible recipe card below with computer-use.",
        "Wait until the authoritative preview is ready and the commit button is enabled.",
        "Do not click commit until the next one-shot request."
      ],
      recipeSelector: firstGate.candidate.selector,
      recipeIndex: firstGate.candidate.recipeIndex,
      identity: firstGate.candidate.output
    });
    const selectedPreview = await waitForSelectedPreview(firstGate.page, firstGate, args);
    receipt.firstIngress.selectedPreview = {
      callId: selectedPreview.preview.callId,
      responseSequence: selectedPreview.previewSequence,
      clickSequence: selectedPreview.clickSequence,
      craftToken: selectedPreview.preview.craftToken
    };
    emitStatus(paths, receipt, "awaiting_one_shot_commit", {
      instruction: [
        "The selected authority preview is now frozen for this one-shot action.",
        "Click the enabled commit button exactly once with computer-use.",
        "Do not use CDP/DOM synthetic click and do not click any other recipe."
      ],
      commitSelector: ".crafting-commit-btn:not(:disabled)",
      expectedCraftToken: selectedPreview.preview.craftToken,
      recipeIndex: selectedPreview.preview.recipeIndex,
      craftCount: selectedPreview.preview.craftCount
    });
    const commitEvidence = await waitForCommitEvidence(firstGate.page, firstRuntime, firstGate, args);
    writeObserved = true;
    receipt.commit = commitEvidence.verified;
    writeJson(paths.firstTranscript, commitEvidence.transcript);
    writeJson(paths.firstLogs, commitEvidence.logRecords);
    commitVerificationInput = {
      schema: "crafting-verification-input.v1",
      mode: "commit",
      transcript: commitEvidence.transcript,
      ingressRecords: firstGate.ingressRecords,
      logRecords: commitEvidence.logRecords,
      interactionFloorSequence: firstGate.interactionFloorSequence
    };
    writeJson(paths.firstBundle, commitVerificationInput);
    assertFingerprint(receipt.sourceFingerprint, "after_commit");
    const afterCommitIdentity = RuntimeIdentity.verifyRuntimeIdentity(ROOT, firstRuntime.port, expectedIdentity);
    if (afterCommitIdentity.pid !== firstRuntime.pid) {
      fail("runtime_changed_after_commit", "commit", "runtime changed after commit");
    }

    emitStatus(paths, receipt, "awaiting_post_commit_inventory_authority", {
      instruction: [
        "Click the visible 背包 / 战备箱 button with computer-use.",
        "Wait for both containers to load, then click 返回合成.",
        "Do not mutate Inventory; this snapshot proves the crafted output quantity."
      ],
      expectedOutput: receipt.commit.identityTriple
    });
    const postCommitInventory = await waitForInventoryAuthorityAndReturn(
      firstGate.page, commitEvidence.transcript.sequence, args, "post_commit_inventory");
    receipt.commit.postCommitInventory = {
      callId: postCommitInventory.inventoryResponse.callId,
      responseSequence: postCommitInventory.inventoryResponseSequence
    };

    emitStatus(paths, receipt, "awaiting_safe_save", {
      instruction: [
        "Close the Crafting panel through the normal UI.",
        "Use the visible SAFEEXIT/save flow so the dedicated clone is archived and returns to the map.",
        "Do not terminate the Launcher; the runner will use supported agent_control shutdown after archive."
      ],
      cloneSlot: TARGET_SLOT,
      safeExitUiJourneyVerified: false
    });
    receipt.persistence = await waitForArchive(
      firstRuntime, receipt.commit, startupBaseline, args
    );
    assertFingerprint(receipt.sourceFingerprint, "after_archive");
    firstTailEvidence = await sealTerminalTail(
      firstGate.page, firstRuntime, firstIngressFloor, "first_tail_seal", args);
    assertTerminalWriteCounts(
      firstTailEvidence.transcript, firstTailEvidence.records, 1, "first_tail");
    const firstTranscriptV2 = bindTranscriptEnvelope(
      firstTailEvidence.transcript, runId, firstRuntime.pid);
    firstLogsV2 = {
      runId,
      cloneSlot: TARGET_SLOT,
      processPid: firstRuntime.pid,
      floors: {
        startLogFloor: firstRuntime.startWatermark.total,
        ingressSequence: firstIngressFloor.sequence,
        interactionSequence: firstGate.interactionFloorSequence,
        tailSequence: firstTailEvidence.tailSequence,
        ingressLogFloor: firstIngressFloor.logWatermark.total,
        interactionLogFloor: firstGate.interactionLogWatermark.total,
        tailLogEnd: firstTailEvidence.tailLogEnd
      },
      preFloorRecords: firstIngressFloor.preFloorRecords,
      records: firstTailEvidence.records
    };
    writeJson(paths.firstTranscriptV2, firstTranscriptV2);
    writeJson(paths.firstLogsV2, firstLogsV2);
    recordSourceFingerprint(receipt.sourceFingerprints.records,
      receipt.sourceFingerprint, "before_first_shutdown");
    receipt.firstShutdown = await supportedShutdownAndResidue(
      firstRuntime, args, "first_shutdown"
    );
    firstConnection = null;

    emitStatus(paths, receipt, "restarting_same_clone", {
      instruction: "The runner is restarting the same clone without reseeding."
    });
    recordSourceFingerprint(receipt.sourceFingerprints.records,
      receipt.sourceFingerprint, "before_restart");
    restartRuntime = await launchRuntime(args, expectedIdentity, receipt.sourceFingerprint, "restart_runtime");
    if (restartRuntime.pid === firstRuntime.pid) {
      fail("restart_pid_not_fresh", "restart_runtime", "restart reused the old Launcher PID");
    }
    if (!SessionVerifier.sameStableIdentity(restartRuntime.identity, firstRuntime.identity)) {
      fail("restart_identity_mismatch", "restart_runtime", "candidate identity changed across restart", {
        first: firstRuntime.identity,
        restart: restartRuntime.identity
      });
    }
    receipt.restartRuntime = restartRuntime;
    const restartBaseline = await closeStartupBaseline(
      receipt.clonePreparation,
      restartRuntime,
      {
        sha256: receipt.persistence.persisted.sha256,
        semanticSha256: receipt.persistence.persisted.semanticSha256,
        role: receipt.persistence.persisted.role,
        level: receipt.persistence.persisted.level
      }
    );
    if (restartBaseline.semanticSha256 !== receipt.persistence.persisted.semanticSha256) {
      fail("restart_clone_semantic_mismatch", "restart_runtime",
        "same clone was not read back after restart", { restartBaseline, persisted: receipt.persistence.persisted });
    }
    receipt.persistence.restartBaseline = restartBaseline;
    restartConnection = await waitForCdp(args.cdpPort,
      "crafting-" + runId + "-readback", args.readyTimeoutMs, args.pollMs);
    restartRuntime.portEvidence.cdpEndpointObserved = true;
    const restartIngressFloor = await establishIngressFloor(
      restartConnection, restartRuntime, "restart_ingress_floor", args);
    emitStatus(paths, receipt, "awaiting_readback_production_ingress", {
      instruction: [
        "Repeat the same visible Native HUD 地图 -> 武器库 -> Flash 合成入口.",
        "Choose the same category: " + receipt.commit.category + ".",
        "Do not commit anything during readback."
      ],
      expectedCategory: receipt.commit.category,
      recipeIndex: receipt.commit.recipeIndex
    });
    const readbackGate = await waitForPanelReady(restartConnection, restartRuntime, args, {
      phase: "readback_ingress",
      timeoutMs: args.readbackTimeoutMs,
      ingressFloor: restartIngressFloor,
      expectedCategory: receipt.commit.category,
      expectedRecipeIndex: receipt.commit.recipeIndex,
      deferInteractionFloor: true
    });
    const restartInteractionFloor = await establishInteractionFloor(
      readbackGate.page, restartRuntime, "restart_interaction_floor",
      readbackGate.candidate, readbackGate.ingress);
    readbackGate.interactionFloorSequence = restartInteractionFloor.sequence;
    readbackGate.interactionLogWatermark = restartInteractionFloor.logWatermark;
    receipt.readbackIngress = {
      ...readbackGate.ingress,
      ingressFloorSequence: readbackGate.ingressFloorSequence,
      ingressLogWatermark: readbackGate.ingressLogWatermark,
      interactionFloorSequence: readbackGate.interactionFloorSequence,
      interactionLogWatermark: readbackGate.interactionLogWatermark,
      candidate: readbackGate.candidate
    };
    emitStatus(paths, receipt, "awaiting_trusted_readback_click", {
      instruction: [
        "Click the exact same recipe card once with visible computer-use.",
        "Wait for its authoritative preview. Do not click commit."
      ],
      recipeSelector: readbackGate.candidate.selector,
      recipeIndex: receipt.commit.recipeIndex
    });
    const readbackEvidence = await waitForReadbackEvidence(
      readbackGate.page,
      restartRuntime,
      readbackGate,
      {
        recipeIndex: receipt.commit.recipeIndex,
        craftCount: receipt.commit.craftCount,
        snapshot: receipt.commit.freshPoststate.snapshot,
        preview: receipt.commit.freshPoststate.preview
      },
      args
    );
    receipt.readback = readbackEvidence.verified;
    emitStatus(paths, receipt, "awaiting_restart_inventory_authority", {
      instruction: [
        "Click the visible 背包 / 战备箱 button with computer-use.",
        "Wait for both containers to load, then click 返回合成.",
        "Do not mutate Inventory or click commit."
      ],
      expectedOutput: receipt.commit.identityTriple
    });
    const restartInventory = await waitForInventoryAuthorityAndReturn(
      readbackGate.page, readbackEvidence.transcript.sequence, args, "restart_inventory");
    receipt.readback.restartInventory = {
      callId: restartInventory.inventoryResponse.callId,
      responseSequence: restartInventory.inventoryResponseSequence
    };
    writeJson(paths.readbackTranscript, readbackEvidence.transcript);
    writeJson(paths.readbackLogs, readbackEvidence.logRecords);
    const readbackVerificationInput = {
      schema: "crafting-verification-input.v1",
      mode: "readback",
      transcript: readbackEvidence.transcript,
      ingressRecords: readbackGate.ingressRecords,
      logRecords: readbackEvidence.logRecords,
      interactionFloorSequence: readbackGate.interactionFloorSequence,
      expectedPoststate: {
        recipeIndex: receipt.commit.recipeIndex,
        craftCount: receipt.commit.craftCount,
        snapshot: receipt.commit.freshPoststate.snapshot,
        preview: receipt.commit.freshPoststate.preview
      }
    };
    writeJson(paths.readbackBundle, readbackVerificationInput);
    const sessionVerificationInput = {
      schema: "crafting-session-verification-input.v1",
      mode: "session",
      commit: commitVerificationInput,
      readback: readbackVerificationInput
    };
    const independentSessionResult = Verifier.verifyBundle(sessionVerificationInput);
    if (!independentSessionResult.crossRestartPoststateBound) {
      fail("independent_session_verification_failed", "readback",
        "combined commit/readback bundle did not verify");
    }
    writeJson(paths.sessionBundle, sessionVerificationInput);
    receipt.independentSessionVerification = {
      crossRestartPoststateBound: true,
      commitCallId: independentSessionResult.commit.commitCallId,
      readbackCallId: independentSessionResult.readback.previewCallId
    };
    assertFingerprint(receipt.sourceFingerprint, "after_readback");
    restartTailEvidence = await sealTerminalTail(
      readbackGate.page, restartRuntime, restartIngressFloor, "restart_tail_seal", args);
    assertTerminalWriteCounts(
      restartTailEvidence.transcript, restartTailEvidence.records, 0, "restart_tail");
    const restartTranscriptV2 = bindTranscriptEnvelope(
      restartTailEvidence.transcript, runId, restartRuntime.pid);
    restartLogsV2 = {
      runId,
      cloneSlot: TARGET_SLOT,
      processPid: restartRuntime.pid,
      floors: {
        startLogFloor: restartRuntime.startWatermark.total,
        ingressSequence: restartIngressFloor.sequence,
        interactionSequence: readbackGate.interactionFloorSequence,
        tailSequence: restartTailEvidence.tailSequence,
        ingressLogFloor: restartIngressFloor.logWatermark.total,
        interactionLogFloor: readbackGate.interactionLogWatermark.total,
        tailLogEnd: restartTailEvidence.tailLogEnd
      },
      preFloorRecords: restartIngressFloor.preFloorRecords,
      records: restartTailEvidence.records
    };
    writeJson(paths.restartTranscriptV2, restartTranscriptV2);
    writeJson(paths.restartLogsV2, restartLogsV2);
    recordSourceFingerprint(receipt.sourceFingerprints.records,
      receipt.sourceFingerprint, "before_final_shutdown");
    receipt.finalShutdown = await supportedShutdownAndResidue(
      restartRuntime, args, "final_shutdown"
    );
    restartConnection = null;
    recordSourceFingerprint(receipt.sourceFingerprints.records,
      receipt.sourceFingerprint, "final");
    receipt.seedInvariant.after = assertSeedFileSetUnchanged(receipt.seedInvariant.before);
    releaseCloneLock(cloneLock, true);
    writeJson(paths.runtimeEvidence,
      buildRuntimeEvidence(runId, expectedIdentity, firstRuntime, restartRuntime));
    writeJson(paths.persistenceEvidence,
      buildPersistenceEvidence(receipt, firstLogsV2));
    writeJson(paths.sourceFingerprints, receipt.sourceFingerprints);
    writeJson(paths.seedInvariant, receipt.seedInvariant);
    receipt.status = "e2e_verified";
    receipt.scope.commitVerified = true;
    receipt.scope.clonePersistenceVerified = true;
    receipt.scope.restartReadbackVerified = true;
    receipt.scope.zeroResidueVerified = true;
    receipt.inputTrust.trustedWebBusinessClicksVerified = true;
    emitStatus(paths, receipt, "complete", {
      result: "e2e_verified / NOT_DEPLOYED",
      receipt: toRelative(paths.receipt)
    });
  } catch (error) {
    caught = error;
    receipt.status = "failed";
    receipt.error = serializeError(error);
    try {
      const connection = restartConnection || firstConnection;
      if (connection) {
        const transcripts = await Recorder.allTranscripts(connection);
        writeObserved = writeObserved || transcripts.some((record) =>
          (record.transcript.events || []).some((event) => {
            const message = event.kind === "bridge_send" ? event.detail.message : null;
            if (!message || message.type !== "panel") return false;
            if (message.domain === "crafting") return message.cmd === "commit";
            return message.domain === "inventory"
              && message.cmd !== "snapshot" && message.cmd !== "tooltip";
          }));
      }
    } catch (_error) { /* retain the original failure */ }
    try {
      const activeRuntime = restartRuntime && processExists(restartRuntime.pid)
        ? restartRuntime : firstRuntime;
      if (activeRuntime && processExists(activeRuntime.pid)) {
        const logSnapshot = await opener.readLogSnapshot(activeRuntime.port);
        const logRecords = opener.freshLogRecords(activeRuntime.startWatermark, logSnapshot);
        writeObserved = writeObserved || logRecords.some((record) => {
          const parsed = Verifier.parseHostFlash(record);
          if (parsed && parsed.message && parsed.message.task === "cmd"
              && parsed.message.action === "craftingCommit") return true;
          const inventory = parseInventoryHostLine(record);
          return inventory && inventory.task === "cmd"
            && inventory.action !== "inventorySnapshot"
            && inventory.action !== "inventoryTooltip";
        });
      }
    } catch (_error) { /* transcript evidence remains authoritative when log read is unavailable */ }
    if (writeObserved) {
      emitStatus(paths, receipt, "manual_recovery_required", {
        instruction: "A commit may have reached authority. Preserve the process, use visible SAFEEXIT/save, then perform supported shutdown; do not rerun or reseed.",
        error: receipt.error
      });
    } else {
      const runtime = restartRuntime || firstRuntime;
      if (runtime && processExists(runtime.pid)) {
        try { receipt.failureCleanup = await supportedShutdownAndResidue(runtime, args, "failure_cleanup"); }
        catch (cleanupError) { receipt.failureCleanup = { error: serializeError(cleanupError) }; }
      }
      if (receipt.seedInvariant.before) {
        try { receipt.seedInvariant.after = assertSeedFileSetUnchanged(receipt.seedInvariant.before); }
        catch (seedError) { receipt.seedInvariant.error = serializeError(seedError); }
      }
      if (cloneLock && !cloneLock.released) {
        try { releaseCloneLock(cloneLock, false); }
        catch (lockError) { receipt.cloneLock.releaseError = serializeError(lockError); }
      }
      emitStatus(paths, receipt, "failed_before_write", { error: receipt.error });
    }
  } finally {
    receipt.finishedAt = new Date().toISOString();
    writeJson(paths.receipt, receipt);
  }
  if (caught) {
    caught.receiptPath = toRelative(paths.receipt);
    throw caught;
  }
  console.log(JSON.stringify({
    ok: true,
    status: receipt.status,
    gate: receipt.gate,
    cloneSlot: TARGET_SLOT,
    receipt: toRelative(paths.receipt),
    commit: {
      panelInstanceId: receipt.commit.panelInstanceId,
      webCallId: receipt.commit.commitCallId,
      identityTriple: receipt.commit.identityTriple
    },
    residue: receipt.finalShutdown
  }, null, 2));
  return receipt;
}

function runCheck() {
  const parsed = parseArgs([
    "--seed-slot", "crazyflasher7_saves",
    "--candidate-root", "tmp/runtime-candidates/v2/check",
    "--input-provider", "launcher_agent",
    "--cdp-port", "9234"
  ]);
  assertArgs(parsed);
  let rejected = false;
  try {
    assertArgs(Object.assign({}, parsed, { seedSlot: TARGET_SLOT }));
  } catch (error) { rejected = error && error.code === "agent_seed_forbidden"; }
  if (!rejected) throw new Error("agent-clone seed was accepted");
  if (!SOURCE_ASSETS.includes("scripts/asLoader.swf")
      || !SOURCE_ASSETS.includes("launcher/web/modules/crafting.js")
      || !SOURCE_ASSETS.includes("launcher/web/modules/inventory-storage-workbench.js")) {
    throw new Error("source asset closure is incomplete");
  }
  return { checks: 3, verifier: Verifier.runCheck() };
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.help) { printHelp(); return; }
  if (args.check) {
    console.log(JSON.stringify({ ok: true, schema: "crafting-live-runner.check.v1", ...runCheck() }));
    return;
  }
  await run(args);
}

function supersededEntry() {
  const error = new Error("SUPERSEDED / NOT_ADMITTED: use crafting/bootstrap.js only");
  error.code = "superseded_not_admitted";
  throw error;
}

module.exports = {
  SOURCE_ASSETS,
  TARGET_SLOT,
  assertArgs,
  captureSourceFingerprint,
  parseArgs,
  prepareClone,
  run: supersededEntry,
  runCheck: supersededEntry,
};

if (require.main === module) {
  process.stderr.write("SUPERSEDED / NOT_ADMITTED: use crafting/bootstrap.js only.\n");
  process.exitCode = 2;
}
