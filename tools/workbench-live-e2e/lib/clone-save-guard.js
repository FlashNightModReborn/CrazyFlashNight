"use strict";

const crypto = require("crypto");
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  assertExactDirectory,
  assertOwnedRunDirectory,
  canonicalJson,
  contractFail,
  isPlainObject,
  pathInside,
  readExactRegularFile,
  samePath,
  sha256Bytes,
  sha256Text,
} = require("./evidence-artifact");

const API_VERSION = "FROZEN-v1";
const ARTIFACT_SET_SCHEMA = "workbench-live-e2e.slot-artifact-set.v1";
const LOCK_SCHEMA = "workbench-live-e2e.clone-lock.v1";
const PREPARATION_SCHEMA = "workbench-live-e2e.clone-preparation.v1";
const RELEASE_SCHEMA = "workbench-live-e2e.clone-release.v1";
const OFFLINE_LOCK_CLEAR_SCHEMA = "workbench-live-e2e.clone-offline-lock-clear.v1";
const OFFLINE_RESTORE_SCHEMA = "workbench-live-e2e.clone-offline-restore.v1";
const SAFE_SLOT_RE = /^[A-Za-z0-9_-]{1,80}$/;
const DEDICATED_SLOT_RE = /^cf7_agent_[A-Za-z0-9_-]{1,70}$/;
const RECOVERY_STATUSES = new Set([
  "mutation_in_progress",
  "prepared_pending_release",
  "manual_recovery_required",
]);
const lockRuntimeStates = new WeakMap();
let cachedCurrentProcessStartUtcTicks = null;

function queryProcessStartUtcTicks(pid, allowMissing) {
  if (!Number.isInteger(pid) || pid < 1 || process.platform !== "win32") {
    contractFail("clone_lock_process_observation_invalid", "clone_lock",
      "clone lock process identity observation requires one Windows PID", { pid });
  }
  const script = [
    "$ErrorActionPreference='Stop'",
    "$p=Get-Process -Id " + pid + " -ErrorAction SilentlyContinue",
    "if ($null -eq $p) { [Console]::Out.Write('ABSENT'); exit 0 }",
    "[Console]::Out.Write($p.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture))",
  ].join("\n");
  const result = childProcess.spawnSync("powershell.exe",
    ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
    { encoding: "utf8", windowsHide: true, timeout: 15000 });
  if (!result || result.status !== 0) {
    contractFail("clone_lock_process_observation_failed", "clone_lock",
      "could not establish clone lock owner process identity", {
        pid, status: result && result.status,
        stderr: String(result && result.stderr || "").slice(-1000),
      });
  }
  const value = String(result.stdout || "").trim();
  if (value === "ABSENT" && allowMissing === true) return null;
  if (!/^\d{16,20}$/.test(value)) {
    contractFail("clone_lock_process_observation_failed", "clone_lock",
      "clone lock owner process start identity is unavailable", { pid, value });
  }
  return value;
}

function currentProcessStartUtcTicks() {
  if (!cachedCurrentProcessStartUtcTicks) {
    cachedCurrentProcessStartUtcTicks = queryProcessStartUtcTicks(process.pid, false);
  }
  return cachedCurrentProcessStartUtcTicks;
}

function assertSourceSlot(slot) {
  const value = String(slot || "");
  if (!SAFE_SLOT_RE.test(value) || value === "." || value === ".." || value.includes("..")) {
    contractFail("source_slot_invalid", "clone", "source slot is not one exact save name", { slot: value });
  }
  return value;
}

function assertDedicatedSlot(slot) {
  const value = String(slot || "");
  if (!DEDICATED_SLOT_RE.test(value) || /^crazyflasher7_saves/i.test(value)) {
    contractFail("target_slot_not_dedicated", "clone",
      "target slot must be a dedicated cf7_agent_* name", { slot: value });
  }
  return value;
}

function exactRoot(root, phase) {
  return assertExactDirectory(path.resolve(root), phase || "clone");
}

function saveJsonPath(root, slot) {
  return path.join(path.resolve(root), "saves", assertSourceSlot(slot) + ".json");
}

function solOwnershipSuffix(root, slot) {
  const absoluteRoot = path.resolve(root);
  const volumeRoot = path.parse(absoluteRoot).root;
  const localRoot = path.relative(volumeRoot, absoluteRoot);
  return path.join("localhost", localRoot, "CRAZYFLASHER7MercenaryEmpire.swf",
    assertSourceSlot(slot) + ".sol");
}

function isOwnedSolPath(root, slot, candidatePath) {
  const candidate = path.resolve(candidatePath).toLowerCase();
  const suffix = solOwnershipSuffix(root, slot).toLowerCase();
  return candidate === suffix || candidate.endsWith(path.sep + suffix);
}

function exactOptionalFile(filePath, phase) {
  try {
    fs.lstatSync(filePath);
  } catch (error) {
    if (error && error.code === "ENOENT") return null;
    contractFail("artifact_lstat_failed", phase, error.message, { filePath });
  }
  return readExactRegularFile(filePath, { phase, maximumBytes: 128 * 1024 * 1024 });
}

function exactAppData(options) {
  const raw = options && options.appData != null ? options.appData : process.env.APPDATA;
  if (!raw) {
    contractFail("appdata_root_missing", "clone_sol",
      "exact APPDATA root is required to prove the complete owned SOL set");
  }
  const resolved = path.resolve(raw);
  return assertExactDirectory(resolved, "clone_sol");
}

function findOwnedSolFiles(options) {
  const root = exactRoot(options.root, "clone_sol");
  const slot = assertSourceSlot(options.slot);
  const appData = exactAppData(options);
  const sharedRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  if (!fs.existsSync(sharedRoot)) return [];
  assertExactDirectory(sharedRoot, "clone_sol");
  const results = [];
  const stack = [sharedRoot];
  let visited = 0;
  while (stack.length > 0) {
    const directory = stack.pop();
    const entries = fs.readdirSync(directory, { withFileTypes: true });
    for (const entry of entries) {
      visited += 1;
      if (visited > 100000) {
        contractFail("sol_inventory_unbounded", "clone_sol", "SOL inventory exceeded its bound");
      }
      const fullPath = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) {
        contractFail("sol_inventory_reparse", "clone_sol",
          "SOL inventory contains a reparse entry and cannot prove completeness", { fullPath });
      }
      if (entry.isDirectory()) stack.push(fullPath);
      else if (entry.isFile() && entry.name.toLowerCase() === (slot + ".sol").toLowerCase()
          && isOwnedSolPath(root, slot, fullPath)) results.push(path.resolve(fullPath));
    }
  }
  return results.sort((left, right) => left.localeCompare(right));
}

function artifactEnvelope(kind, locator, file) {
  return { kind, locator, sha256: file.sha256, bytes: file.length,
    regularFile: true, exactRealPath: true };
}

function captureSlotArtifactSet(options) {
  const root = exactRoot(options.root, "clone_snapshot");
  const slot = assertSourceSlot(options.slot);
  const appData = exactAppData(options);
  const savesRoot = assertExactDirectory(path.join(root, "saves"), "clone_snapshot");
  const jsonPath = saveJsonPath(root, slot);
  if (!samePath(path.dirname(jsonPath), savesRoot)) {
    contractFail("save_path_escape", "clone_snapshot", "save JSON escaped the exact saves directory");
  }
  const artifacts = [];
  const json = exactOptionalFile(jsonPath, "clone_snapshot");
  if (!json && options.requireJson !== false) {
    contractFail("save_json_missing", "clone_snapshot", "required save JSON is missing", { slot });
  }
  if (json) artifacts.push(artifactEnvelope("json", "root:saves/" + slot + ".json", json));
  findOwnedSolFiles({ root, slot, appData }).forEach((solPath) => {
    if (!appData || !pathInside(appData, solPath)) {
      contractFail("sol_path_escape", "clone_snapshot", "owned SOL escaped APPDATA", { solPath });
    }
    const file = readExactRegularFile(solPath, {
      phase: "clone_snapshot", maximumBytes: 128 * 1024 * 1024,
    });
    artifacts.push(artifactEnvelope("sol",
      "appdata:" + path.relative(appData, solPath).replace(/\\/g, "/"), file));
  });
  artifacts.sort((left, right) => left.locator.localeCompare(right.locator));
  const digestPayload = { schema: ARTIFACT_SET_SCHEMA, slot, appDataRoot: appData, artifacts };
  return Object.assign({}, digestPayload, {
    capturedAt: options.capturedAt || new Date().toISOString(),
    setSha256: sha256Text(canonicalJson(digestPayload)),
  });
}

function verifyArtifactSet(set) {
  if (!isPlainObject(set) || set.schema !== ARTIFACT_SET_SCHEMA
      || !SAFE_SLOT_RE.test(String(set.slot || "")) || !Array.isArray(set.artifacts)
      || typeof set.appDataRoot !== "string" || !path.isAbsolute(set.appDataRoot)
      || !Number.isFinite(Date.parse(set.capturedAt))
      || !/^[a-f0-9]{64}$/.test(String(set.setSha256 || ""))) {
    contractFail("artifact_set_invalid", "clone_snapshot", "slot artifact set is malformed");
  }
  const sorted = set.artifacts.slice().sort((left, right) =>
    String(left && left.locator).localeCompare(String(right && right.locator)));
  const jsonLocator = "root:saves/" + set.slot + ".json";
  const jsonArtifacts = set.artifacts.filter((entry) => entry && entry.kind === "json");
  if (canonicalJson(sorted) !== canonicalJson(set.artifacts)
      || new Set(set.artifacts.map((entry) => entry.locator)).size !== set.artifacts.length
      || jsonArtifacts.length > 1
      || set.artifacts.some((entry) => !isPlainObject(entry)
        || !["json", "sol"].includes(entry.kind)
        || !/^(?:root|appdata):/.test(String(entry.locator || ""))
        || (entry.kind === "json" && entry.locator !== jsonLocator)
        || (entry.kind === "sol" && (!entry.locator.startsWith("appdata:")
          || !entry.locator.toLowerCase().endsWith("/" + set.slot.toLowerCase() + ".sol")))
        || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || entry.regularFile !== true || entry.exactRealPath !== true)) {
    contractFail("artifact_set_invalid", "clone_snapshot", "artifact entries are malformed");
  }
  const payload = { schema: set.schema, slot: set.slot,
    appDataRoot: path.resolve(set.appDataRoot), artifacts: set.artifacts };
  if (sha256Text(canonicalJson(payload)) !== set.setSha256) {
    contractFail("artifact_set_digest_mismatch", "clone_snapshot", "artifact set digest does not match");
  }
  return set;
}

function verifyCurrentSlotArtifactSet(options) {
  const declared = verifyArtifactSet(options.set);
  const current = captureSlotArtifactSet({ root: options.root, appData: options.appData,
    slot: declared.slot, requireJson: declared.artifacts.some((entry) => entry.kind === "json"),
    capturedAt: declared.capturedAt });
  if (canonicalJson(current) !== canonicalJson(declared)) {
    contractFail("artifact_set_current_mismatch", "clone_snapshot",
      "declared slot artifact set does not match current exact bytes");
  }
  return declared;
}

function assertArtifactSetInvariant(begin, end, code) {
  verifyArtifactSet(begin);
  verifyArtifactSet(end);
  if (begin.slot !== end.slot || !samePath(begin.appDataRoot, end.appDataRoot)
      || begin.setSha256 !== end.setSha256
      || canonicalJson(begin.artifacts) !== canonicalJson(end.artifacts)) {
    contractFail(code || "seed_artifact_set_changed", "clone_invariant",
      "read-only slot JSON/SOL artifact set changed", {
        slot: begin.slot,
        beginSetSha256: begin.setSha256,
        endSetSha256: end.setSha256,
      });
  }
  return { slot: begin.slot, setSha256: begin.setSha256 };
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function captureStableSlotArtifactSet(options) {
  const timeoutMs = Number(options.timeoutMs || 10000);
  const stableMs = Number(options.stableMs || 1000);
  const pollMs = Number(options.pollMs || 100);
  if (!Number.isInteger(timeoutMs) || timeoutMs < stableMs || !Number.isInteger(stableMs)
      || stableMs < 1 || !Number.isInteger(pollMs) || pollMs < 1) {
    contractFail("stable_artifact_options_invalid", "clone_snapshot",
      "stable artifact capture timing is invalid");
  }
  const deadline = Date.now() + timeoutMs;
  let current = null;
  let stableSince = 0;
  let samples = 0;
  while (Date.now() <= deadline) {
    const observed = captureSlotArtifactSet(options);
    samples += 1;
    if (!current || observed.setSha256 !== current.setSha256
        || canonicalJson(observed.artifacts) !== canonicalJson(current.artifacts)) {
      current = observed;
      stableSince = Date.now();
    } else if (Date.now() - stableSince >= stableMs) {
      const evidence = { schema: "workbench-live-e2e.stable-slot-artifact-set.v1",
        apiVersion: API_VERSION, stableMs, samples, observedAt: new Date().toISOString(), set: observed };
      evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
      return evidence;
    }
    await delay(pollMs);
  }
  contractFail("stable_artifact_timeout", "clone_snapshot",
    "slot artifact set did not remain stable within the timeout", {
      slot: options.slot, samples, lastSetSha256: current && current.setSha256,
    });
}

function cloneLockDirectory(root) {
  const resolvedRoot = exactRoot(root, "clone_lock");
  const directory = path.join(resolvedRoot, "tmp", "workbench-live-e2e", "locks");
  fs.mkdirSync(directory, { recursive: true });
  return assertExactDirectory(directory, "clone_lock");
}

function cloneRecoveryDirectory(root) {
  const resolvedRoot = exactRoot(root, "clone_recovery");
  const directory = path.join(resolvedRoot, "tmp", "workbench-live-e2e", "manual-recovery");
  fs.mkdirSync(directory, { recursive: true });
  return assertExactDirectory(directory, "clone_recovery");
}

function cloneRecoveryPath(root, slot, noCreate) {
  const directory = noCreate === true
    ? path.join(exactRoot(root, "clone_recovery"), "tmp", "workbench-live-e2e", "manual-recovery")
    : cloneRecoveryDirectory(root);
  return path.join(directory, assertDedicatedSlot(slot) + ".json");
}

function readCloneRecovery(root, slot, allowMissing, noCreate) {
  const recoveryPath = cloneRecoveryPath(root, slot, noCreate);
  const file = exactOptionalFile(recoveryPath, "clone_recovery");
  if (!file) {
    if (allowMissing) return null;
    contractFail("clone_recovery_missing", "clone_recovery", "manual recovery record is missing");
  }
  let record;
  try { record = JSON.parse(file.bytes.toString("utf8")); }
  catch (error) { contractFail("clone_recovery_invalid", "clone_recovery", error.message); }
  const digest = record && record.recordSha256;
  const payload = Object.assign({}, record);
  delete payload.recordSha256;
  if (!isPlainObject(record) || record.schema !== "workbench-live-e2e.clone-manual-recovery.v1"
      || record.apiVersion !== API_VERSION
      || !RECOVERY_STATUSES.has(record.status)
      || !Number.isFinite(Date.parse(record.recordedAt))
      || record.slot !== slot || record.slot !== assertDedicatedSlot(record.slot)
      || record.seedSlot !== assertSourceSlot(record.seedSlot)
      || typeof record.runDir !== "string" || path.isAbsolute(record.runDir)
      || record.runDir.split(/[\\/]/).includes("..")
      || !record.runDir.replace(/\\/g, "/").startsWith("tmp/workbench-live-e2e/")
      || !Array.isArray(record.backups) || !Array.isArray(record.mutationProgress)
      || !/^[a-f0-9]{64}$/.test(String(digest || ""))
      || sha256Text(canonicalJson(payload)) !== digest || file.sha256 !== sha256Text(canonicalJson(record))) {
    contractFail("clone_recovery_invalid", "clone_recovery", "manual recovery record is malformed");
  }
  verifyArtifactSet(record.seedBegin);
  verifyArtifactSet(record.targetBefore);
  if (record.seedBegin.slot !== record.seedSlot || record.targetBefore.slot !== record.slot) {
    contractFail("clone_recovery_invalid", "clone_recovery",
      "manual recovery seed/target-before sets do not match their slots");
  }
  if (record.targetPrepared !== null) {
    verifyArtifactSet(record.targetPrepared);
    if (record.targetPrepared.slot !== record.slot) {
      contractFail("clone_recovery_invalid", "clone_recovery",
        "manual recovery prepared target set does not match its slot");
    }
  }
  if ((record.status === "mutation_in_progress"
        && (record.targetPrepared !== null || record.preparationContextSha256 !== null
          || record.failure !== null))
      || (record.status === "prepared_pending_release"
        && (!isPlainObject(record.targetPrepared)
          || !/^[a-f0-9]{64}$/.test(String(record.preparationContextSha256 || ""))
          || record.failure !== null))
      || (record.status === "manual_recovery_required"
        && (!isPlainObject(record.failure) || typeof record.failure.code !== "string"
          || typeof record.failure.message !== "string"))) {
    contractFail("clone_recovery_invalid", "clone_recovery",
      "manual recovery status payload is inconsistent");
  }
  return record;
}

function writeCloneRecovery(options) {
  const recoveryPath = cloneRecoveryPath(options.root, options.slot);
  const payload = {
    schema: "workbench-live-e2e.clone-manual-recovery.v1",
    apiVersion: API_VERSION,
    status: options.status || "manual_recovery_required",
    recordedAt: new Date().toISOString(),
    slot: options.slot,
    seedSlot: options.seedSlot,
    runDir: path.relative(options.root, options.runDir).replace(/\\/g, "/"),
    seedBegin: options.seedBegin,
    targetBefore: options.targetBefore,
    backups: options.backups,
    mutationProgress: options.mutationProgress.slice(),
    targetPrepared: options.targetPrepared || null,
    preparationContextSha256: options.preparationContextSha256 || null,
    failure: options.error ? { code: options.error.code || "clone_prepare_failed",
      message: String(options.error.message || "clone preparation failed") } : null,
  };
  const record = Object.assign({}, payload, { recordSha256: sha256Text(canonicalJson(payload)) });
  const raw = canonicalJson(record);
  try {
    if (options.replace === true) {
      const current = readCloneRecovery(options.root, options.slot, false);
      if (!/^[a-f0-9]{64}$/.test(String(options.expectedRecordSha256 || ""))
          || current.recordSha256 !== options.expectedRecordSha256) {
        contractFail("clone_recovery_record_changed", "clone_recovery",
          "manual recovery transition lost its exact prior record", {
            expectedRecordSha256: options.expectedRecordSha256,
            actualRecordSha256: current.recordSha256,
          });
      }
      const temporary = recoveryPath + "." + process.pid + "."
        + crypto.randomBytes(8).toString("hex") + ".tmp";
      fs.writeFileSync(temporary, raw, { encoding: "utf8", flag: "wx", mode: 0o600 });
      try { fs.renameSync(temporary, recoveryPath); }
      finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    } else {
      fs.writeFileSync(recoveryPath, raw, { encoding: "utf8", flag: "wx", mode: 0o600 });
    }
  }
  catch (error) {
    contractFail("clone_recovery_record_failed", "clone_recovery",
      "target mutation failed and a manual recovery record could not be created", {
        recoveryPath, originalError: payload.failure, recordError: error.message,
      });
  }
  return readCloneRecovery(options.root, options.slot, false);
}

function clearExactCloneRecoveryRecord(root, slot, expectedRecordSha256, expectedStatus) {
  const record = readCloneRecovery(root, slot, false);
  if (record.status !== expectedStatus || record.recordSha256 !== expectedRecordSha256) {
    contractFail("clone_recovery_record_changed", "clone_recovery",
      "clone recovery clearance lost its exact state transition", {
        expectedStatus,
        actualStatus: record.status,
        expectedRecordSha256,
        actualRecordSha256: record.recordSha256,
      });
  }
  const recoveryPath = cloneRecoveryPath(root, slot);
  fs.unlinkSync(recoveryPath);
  if (fs.existsSync(recoveryPath)) {
    contractFail("clone_recovery_clear_failed", "clone_recovery",
      "exact clone recovery record remained");
  }
  return { recoveryRecordSha256: record.recordSha256, recoveryFileAbsent: true };
}

function readCloneLockRecord(root, slot, lockPath, allowMissing) {
  const file = exactOptionalFile(lockPath, "clone_lock");
  if (!file) {
    if (allowMissing === true) return null;
    contractFail("clone_lock_missing", "clone_lock", "clone lock file is missing", { slot });
  }
  let record;
  try { record = JSON.parse(file.bytes.toString("utf8")); }
  catch (error) { contractFail("clone_lock_tampered", "clone_lock", error.message); }
  if (!isPlainObject(record) || record.schema !== LOCK_SCHEMA || record.apiVersion !== API_VERSION
      || record.slot !== slot || record.slot !== assertDedicatedSlot(record.slot)
      || !Number.isInteger(record.pid) || record.pid < 1
      || !/^\d{16,20}$/.test(String(record.ownerProcessStartUtcTicks || ""))
      || !Number.isFinite(Date.parse(record.acquiredAt))
      || typeof record.runDir !== "string" || path.isAbsolute(record.runDir)
      || record.runDir.split(/[\\/]/).includes("..")
      || !record.runDir.replace(/\\/g, "/").startsWith("tmp/workbench-live-e2e/")
      || !/^[a-f0-9]{48}$/.test(String(record.ownerNonce || ""))
      || typeof record.recoveryMode !== "boolean"
      || (record.recoveryMode === true
        ? !/^[a-f0-9]{64}$/.test(String(record.recoveryRecordSha256 || ""))
        : record.recoveryRecordSha256 !== null)
      || !samePath(lockPath, path.join(cloneLockDirectory(root), slot + ".clone.lock"))) {
    contractFail("clone_lock_tampered", "clone_lock", "clone lock record is malformed", { slot });
  }
  return { file, record };
}

function inspectCloneLock(options) {
  const root = exactRoot(options.root, "clone_lock_inspection");
  const slot = assertDedicatedSlot(options.slot);
  const lockPath = path.join(root, "tmp", "workbench-live-e2e", "locks",
    slot + ".clone.lock");
  const observed = readCloneLockRecord(root, slot, lockPath, true);
  const recovery = readCloneRecovery(root, slot, true, true);
  if (!observed) {
    const absent = { schema: "workbench-live-e2e.clone-lock-inspection.v1",
      apiVersion: API_VERSION, observedAt: new Date().toISOString(), slot,
      lockPath, lockPresent: false, recordSha256: null, ownerPid: null,
      ownerProcessStartUtcTicks: null, observedProcessStartUtcTicks: null,
      ownerState: "absent", recoveryPresent: recovery !== null,
      recoveryStatus: recovery ? recovery.status : null,
      recoveryRecordSha256: recovery ? recovery.recordSha256 : null };
    absent.evidenceSha256 = sha256Text(canonicalJson(absent));
    return absent;
  }
  const observedProcessStartUtcTicks = queryProcessStartUtcTicks(observed.record.pid, true);
  const evidence = { schema: "workbench-live-e2e.clone-lock-inspection.v1",
    apiVersion: API_VERSION, observedAt: new Date().toISOString(), slot,
    lockPath, lockPresent: true, recordSha256: observed.file.sha256,
    ownerPid: observed.record.pid,
    ownerProcessStartUtcTicks: observed.record.ownerProcessStartUtcTicks,
    observedProcessStartUtcTicks,
    ownerState: observedProcessStartUtcTicks === null ? "owner_absent"
      : observedProcessStartUtcTicks === observed.record.ownerProcessStartUtcTicks
        ? "owner_active" : "pid_reused",
    recoveryPresent: recovery !== null,
    recoveryStatus: recovery ? recovery.status : null,
    recoveryRecordSha256: recovery ? recovery.recordSha256 : null };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function assertExpectedSha256(value, label) {
  const digest = String(value || "").toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(digest)) {
    contractFail("clone_offline_expected_digest_invalid", "clone_recovery_offline",
      label + " must be one exact SHA-256 digest");
  }
  return digest;
}

function assertOfflineRuntimeExcluded(options) {
  if (typeof options.assertNoRuntime !== "function"
      || options.assertNoRuntime() !== true) {
    contractFail("clone_offline_runtime_not_excluded", "clone_recovery_offline",
      "offline clone recovery requires an exact no-live-runtime observation");
  }
  return true;
}

function observeExpectedAbandonedLock(options) {
  const root = exactRoot(options.root, "clone_recovery_offline");
  const slot = assertDedicatedSlot(options.slot);
  const expectedLockSha256 = assertExpectedSha256(options.expectedLockSha256,
    "expected clone lock digest");
  const lockPath = path.join(cloneLockDirectory(root), slot + ".clone.lock");
  const observed = readCloneLockRecord(root, slot, lockPath, false);
  if (observed.file.sha256 !== expectedLockSha256) {
    contractFail("clone_offline_lock_changed", "clone_recovery_offline",
      "offline clone recovery lost its exact lock binding", {
        expectedLockSha256,
        actualLockSha256: observed.file.sha256,
      });
  }
  const observedProcessStartUtcTicks = queryProcessStartUtcTicks(observed.record.pid, true);
  if (observedProcessStartUtcTicks !== null) {
    contractFail("clone_offline_lock_owner_not_absent", "clone_recovery_offline",
      "offline clone recovery requires the exact lock owner PID to be absent", {
        ownerPid: observed.record.pid,
        ownerProcessStartUtcTicks: observed.record.ownerProcessStartUtcTicks,
        observedProcessStartUtcTicks,
        ownerState: observedProcessStartUtcTicks === observed.record.ownerProcessStartUtcTicks
          ? "owner_active" : "pid_reused",
      });
  }
  return { root, slot, lockPath, file: observed.file, record: observed.record,
    ownerState: "owner_absent" };
}

function unlinkExpectedAbandonedLock(options) {
  const observed = observeExpectedAbandonedLock(options);
  if (options.expectedRecoveryRecordSha256 === null) {
    if (observed.record.recoveryMode !== false
        || observed.record.recoveryRecordSha256 !== null) {
      contractFail("clone_offline_lock_recovery_binding_invalid", "clone_recovery_offline",
        "a recovery-bound lock cannot be cleared as an empty pre-mutation lock");
    }
  } else {
    const expectedRecoveryRecordSha256 = assertExpectedSha256(
      options.expectedRecoveryRecordSha256, "expected clone recovery digest");
    if (observed.record.recoveryMode === true
        && observed.record.recoveryRecordSha256 !== expectedRecoveryRecordSha256) {
      contractFail("clone_offline_lock_recovery_binding_invalid", "clone_recovery_offline",
        "recovery-mode lock is not bound to the exact recovery record", {
          lockRecoveryRecordSha256: observed.record.recoveryRecordSha256,
          expectedRecoveryRecordSha256,
        });
    }
  }
  assertOfflineRuntimeExcluded(options);
  const finalObservation = observeExpectedAbandonedLock(options);
  fs.unlinkSync(finalObservation.lockPath);
  if (exactOptionalFile(finalObservation.lockPath, "clone_recovery_offline") !== null) {
    contractFail("clone_offline_lock_clear_failed", "clone_recovery_offline",
      "exact abandoned clone lock remained after offline clearance");
  }
  return { lockPath: finalObservation.lockPath,
    lockRecordSha256: finalObservation.file.sha256,
    ownerPid: finalObservation.record.pid,
    ownerProcessStartUtcTicks: finalObservation.record.ownerProcessStartUtcTicks,
    ownerState: finalObservation.ownerState,
    lockFileAbsent: true };
}

function clearAbandonedNoRecoveryCloneLock(options) {
  const root = exactRoot(options.root, "clone_recovery_offline");
  const slot = assertDedicatedSlot(options.slot);
  assertOfflineRuntimeExcluded(options);
  const recovery = readCloneRecovery(root, slot, true, true);
  if (recovery !== null) {
    contractFail("clone_offline_recovery_present", "clone_recovery_offline",
      "a lock with a durable recovery record requires exact offline restore", {
        recoveryStatus: recovery.status,
        recoveryRecordSha256: recovery.recordSha256,
      });
  }
  const clearance = unlinkExpectedAbandonedLock({ root, slot,
    expectedLockSha256: options.expectedLockSha256,
    expectedRecoveryRecordSha256: null,
    assertNoRuntime: options.assertNoRuntime });
  assertOfflineRuntimeExcluded(options);
  const evidence = { schema: OFFLINE_LOCK_CLEAR_SCHEMA, apiVersion: API_VERSION,
    clearedAt: new Date().toISOString(), slot, noRuntimeConfirmed: true,
    recoveryFileAbsent: readCloneRecovery(root, slot, true, true) === null,
    lockRecordSha256: clearance.lockRecordSha256,
    ownerPid: clearance.ownerPid,
    ownerProcessStartUtcTicks: clearance.ownerProcessStartUtcTicks,
    ownerState: clearance.ownerState,
    lockFileAbsent: clearance.lockFileAbsent };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function acquireCloneLock(options) {
  const root = exactRoot(options.root, "clone_lock");
  const slot = assertDedicatedSlot(options.slot);
  const runDir = assertOwnedRunDirectory(root, options.runDir,
    options.ownedBaseRelative || path.join("tmp", "workbench-live-e2e"), "clone_lock");
  const recovery = readCloneRecovery(root, slot, true);
  if (recovery && options.recoveryMode !== true) {
    contractFail("clone_manual_recovery_required", "clone_lock",
      "dedicated target has an unresolved manual recovery record", {
        slot, recordSha256: recovery.recordSha256, runDir: recovery.runDir,
      });
  }
  if (recovery && recovery.status === "prepared_pending_release"
      && options.recoveryMode === true) {
    contractFail("clone_prepared_release_offline_recovery_required", "clone_lock",
      "a prepared/live-interrupted clone requires explicit offline restore and clearance", {
        slot, recordSha256: recovery.recordSha256, runDir: recovery.runDir,
      });
  }
  if (!recovery && options.recoveryMode === true) {
    contractFail("clone_recovery_missing", "clone_lock",
      "recovery-mode lock requires an existing manual recovery record");
  }
  const lockPath = path.join(cloneLockDirectory(root), slot + ".clone.lock");
  const existingLock = readCloneLockRecord(root, slot, lockPath, true);
  if (existingLock) {
    contractFail("clone_lock_unavailable", "clone_lock",
      "clone acquisition never takes over an existing lock; use explicit offline recovery", {
        slot, ownerPid: existingLock.record.pid,
        ownerProcessStartUtcTicks: existingLock.record.ownerProcessStartUtcTicks,
        recordSha256: existingLock.file.sha256,
      });
  }
  const ownerNonce = crypto.randomBytes(24).toString("hex");
  const record = {
    schema: LOCK_SCHEMA,
    apiVersion: API_VERSION,
    slot,
    pid: process.pid,
    ownerProcessStartUtcTicks: currentProcessStartUtcTicks(),
    acquiredAt: new Date().toISOString(),
    runDir: path.relative(root, runDir).replace(/\\/g, "/"),
    ownerNonce,
    recoveryMode: options.recoveryMode === true,
    recoveryRecordSha256: recovery ? recovery.recordSha256 : null,
  };
  const raw = Buffer.from(canonicalJson(record), "utf8");
  try { fs.writeFileSync(lockPath, raw, { flag: "wx", mode: 0o600 }); }
  catch (error) {
    contractFail("clone_lock_unavailable", "clone_lock",
      "dedicated target already has an exclusive lock", { slot, error: error.message });
  }
  const lock = {
    schema: LOCK_SCHEMA,
    root,
    slot,
    path: lockPath,
    ownerNonce,
    ownerProcessStartUtcTicks: record.ownerProcessStartUtcTicks,
    recordSha256: sha256Bytes(raw),
    acquiredAt: record.acquiredAt,
    recoveryMode: record.recoveryMode,
    recoveryRecordSha256: record.recoveryRecordSha256,
    manualRecoveryRequired: false,
    mutationBegan: false,
    preparationSha256: null,
    released: false,
  };
  lockRuntimeStates.set(lock, {
    manualRecoveryRequired: false,
    mutationBegan: false,
    preparationSha256: null,
    activeRecoveryRecordSha256: recovery ? recovery.recordSha256 : null,
    recoveryCleared: false,
  });
  return lock;
}

function assertCloneLockOwned(lock, expectedSlot) {
  const runtimeState = isPlainObject(lock) ? lockRuntimeStates.get(lock) : null;
  if (!runtimeState || !isPlainObject(lock) || lock.schema !== LOCK_SCHEMA || lock.released === true
      || lock.slot !== assertDedicatedSlot(expectedSlot || lock.slot)
      || !/^[a-f0-9]{48}$/.test(String(lock.ownerNonce || ""))
      || !/^\d{16,20}$/.test(String(lock.ownerProcessStartUtcTicks || ""))
      || lock.ownerProcessStartUtcTicks !== currentProcessStartUtcTicks()
      || typeof lock.recoveryMode !== "boolean"
      || (lock.recoveryMode === true
        ? !/^[a-f0-9]{64}$/.test(String(lock.recoveryRecordSha256 || ""))
        : lock.recoveryRecordSha256 !== null)
      || lock.manualRecoveryRequired !== runtimeState.manualRecoveryRequired
      || lock.mutationBegan !== runtimeState.mutationBegan
      || lock.preparationSha256 !== runtimeState.preparationSha256) {
    contractFail("clone_lock_invalid", "clone_lock", "clone lock handle is malformed or released");
  }
  const observed = readCloneLockRecord(lock.root, lock.slot, lock.path, false);
  const file = observed.file;
  const record = observed.record;
  if (file.sha256 !== lock.recordSha256 || record.schema !== LOCK_SCHEMA
      || record.slot !== lock.slot || record.ownerNonce !== lock.ownerNonce
      || record.pid !== process.pid
      || record.ownerProcessStartUtcTicks !== lock.ownerProcessStartUtcTicks
      || record.recoveryMode !== lock.recoveryMode
      || record.recoveryRecordSha256 !== lock.recoveryRecordSha256
      || !samePath(path.dirname(lock.path), cloneLockDirectory(lock.root))) {
    contractFail("clone_lock_tampered", "clone_lock", "clone lock ownership changed");
  }
  return lock;
}

function publicLockEvidence(lock) {
  assertCloneLockOwned(lock, lock.slot);
  return { schema: LOCK_SCHEMA, slot: lock.slot, acquiredAt: lock.acquiredAt,
    ownerPid: process.pid, ownerProcessStartUtcTicks: lock.ownerProcessStartUtcTicks,
    recoveryMode: lock.recoveryMode, recoveryRecordSha256: lock.recoveryRecordSha256,
    recordSha256: lock.recordSha256 };
}

function releaseCloneLock(lock) {
  assertCloneLockOwned(lock, lock.slot);
  const runtimeState = lockRuntimeStates.get(lock);
  const recovery = readCloneRecovery(lock.root, lock.slot, true);
  if (recovery || runtimeState.manualRecoveryRequired || runtimeState.mutationBegan
      || runtimeState.preparationSha256 !== null
      || (lock.recoveryMode === true && runtimeState.recoveryCleared !== true)) {
    contractFail("clone_lock_release_blocked", "clone_lock",
      "public lock release is allowed only before mutation or after exact recovery clearance", {
        slot: lock.slot,
        recoveryRecordSha256: recovery && recovery.recordSha256 || null,
        mutationBegan: runtimeState.mutationBegan,
        manualRecoveryRequired: runtimeState.manualRecoveryRequired,
      });
  }
  fs.unlinkSync(lock.path);
  if (fs.existsSync(lock.path)) {
    contractFail("clone_lock_release_failed", "clone_lock", "clone lock remained after release");
  }
  lock.released = true;
  lockRuntimeStates.delete(lock);
  return { schema: LOCK_SCHEMA, slot: lock.slot, releasedAt: new Date().toISOString(),
    ownerPid: process.pid, ownerProcessStartUtcTicks: lock.ownerProcessStartUtcTicks,
    recoveryMode: lock.recoveryMode, recoveryRecordSha256: lock.recoveryRecordSha256,
    recordSha256: lock.recordSha256, lockFileAbsent: true };
}

function beginCloneMutation(lock) {
  assertCloneLockOwned(lock, lock.slot);
  const runtimeState = lockRuntimeStates.get(lock);
  if (lock.recoveryMode || runtimeState.mutationBegan
      || runtimeState.activeRecoveryRecordSha256 !== null
      || readCloneRecovery(lock.root, lock.slot, true) !== null) {
    contractFail("clone_mutation_state_invalid", "clone_prepare",
      "clone mutation requires one clean ordinary lock");
  }
  runtimeState.mutationBegan = true;
  lock.mutationBegan = true;
}

function bindCloneRecoveryState(lock, recovery, options) {
  const runtimeState = lockRuntimeStates.get(lock);
  if (!runtimeState || !isPlainObject(recovery)
      || !/^[a-f0-9]{64}$/.test(String(recovery.recordSha256 || ""))) {
    contractFail("clone_mutation_state_invalid", "clone_recovery",
      "clone lock cannot bind a malformed recovery state");
  }
  runtimeState.activeRecoveryRecordSha256 = recovery.recordSha256;
  if (options && options.manualRecoveryRequired === true) {
    runtimeState.manualRecoveryRequired = true;
    lock.manualRecoveryRequired = true;
  }
  if (options && options.preparationSha256) {
    runtimeState.preparationSha256 = options.preparationSha256;
    lock.preparationSha256 = options.preparationSha256;
  }
}

function unlinkPreparedCloneLock(lock, preparationSha256, recoveryRecordSha256) {
  assertCloneLockOwned(lock, lock.slot);
  const runtimeState = lockRuntimeStates.get(lock);
  const recovery = readCloneRecovery(lock.root, lock.slot, false);
  if (!runtimeState.mutationBegan || runtimeState.manualRecoveryRequired
      || runtimeState.preparationSha256 !== preparationSha256
      || runtimeState.activeRecoveryRecordSha256 !== recoveryRecordSha256
      || recovery.status !== "prepared_pending_release"
      || recovery.recordSha256 !== recoveryRecordSha256) {
    contractFail("clone_private_release_state_invalid", "clone_release",
      "terminal clone release lost its exact prepared lock/recovery state");
  }
  fs.unlinkSync(lock.path);
  if (fs.existsSync(lock.path)) {
    contractFail("clone_lock_release_failed", "clone_release",
      "terminal clone lock remained after private release");
  }
  lock.released = true;
  lockRuntimeStates.delete(lock);
  return { schema: LOCK_SCHEMA, slot: lock.slot, releasedAt: new Date().toISOString(),
    ownerPid: process.pid, ownerProcessStartUtcTicks: lock.ownerProcessStartUtcTicks,
    recoveryMode: false, recoveryRecordSha256, recordSha256: lock.recordSha256,
    lockFileAbsent: true, terminalPrivateRelease: true };
}

function artifactAbsolutePath(root, appData, artifact) {
  if (artifact.locator.startsWith("root:")) {
    const value = path.resolve(root, artifact.locator.slice(5).replace(/\//g, path.sep));
    if (!pathInside(root, value)) contractFail("artifact_path_escape", "clone", "root artifact escaped");
    return value;
  }
  if (artifact.locator.startsWith("appdata:") && appData) {
    const value = path.resolve(appData, artifact.locator.slice(8).replace(/\//g, path.sep));
    if (!pathInside(appData, value)) contractFail("artifact_path_escape", "clone", "SOL escaped APPDATA");
    return value;
  }
  contractFail("artifact_locator_invalid", "clone", "artifact locator cannot be resolved");
}

function ensureNewBackupDirectory(runDir, slot) {
  const base = path.join(runDir, "save-backups");
  fs.mkdirSync(base, { recursive: true });
  assertExactDirectory(base, "clone_backup");
  const directory = path.join(base, slot);
  try { fs.mkdirSync(directory); }
  catch (error) {
    contractFail("clone_backup_exists", "clone_backup",
      "backup directory already exists; refusing overwrite", { directory, error: error.message });
  }
  return assertExactDirectory(directory, "clone_backup");
}

function backupArtifactSet(options) {
  const set = verifyArtifactSet(options.set);
  const backupDir = ensureNewBackupDirectory(options.runDir, set.slot);
  return set.artifacts.map((artifact, index) => {
    const sourcePath = artifactAbsolutePath(options.root, options.appData, artifact);
    const source = readExactRegularFile(sourcePath, {
      phase: "clone_backup", maximumBytes: 128 * 1024 * 1024,
    });
    if (source.sha256 !== artifact.sha256 || source.length !== artifact.bytes) {
      contractFail("clone_backup_source_changed", "clone_backup",
        "target artifact changed before backup", { locator: artifact.locator });
    }
    const extension = artifact.kind === "json" ? ".json" : ".sol";
    const destination = path.join(backupDir,
      String(index + 1).padStart(3, "0") + "-" + artifact.kind + extension);
    fs.copyFileSync(source.path, destination, fs.constants.COPYFILE_EXCL);
    const copied = readExactRegularFile(destination, {
      phase: "clone_backup", maximumBytes: 128 * 1024 * 1024,
    });
    if (copied.sha256 !== source.sha256 || copied.length !== source.length) {
      contractFail("clone_backup_digest_mismatch", "clone_backup", "backup bytes changed");
    }
    return { source: artifact, backupRelativePath:
      path.relative(options.runDir, destination).replace(/\\/g, "/"),
    sha256: copied.sha256, bytes: copied.length };
  });
}

function verifyBackupManifest(options) {
  if (!Array.isArray(options.backups)) {
    contractFail("clone_backup_manifest_invalid", "clone_backup", "backup manifest is missing");
  }
  if (new Set(options.backups.map((backup) => backup && backup.backupRelativePath)).size
      !== options.backups.length) {
    contractFail("clone_backup_manifest_invalid", "clone_backup", "backup paths are duplicated");
  }
  options.backups.forEach((backup) => {
    if (!isPlainObject(backup) || !isPlainObject(backup.source)
        || typeof backup.backupRelativePath !== "string") {
      contractFail("clone_backup_manifest_invalid", "clone_backup", "backup entry is malformed");
    }
    const backupPath = path.resolve(options.runDir,
      backup.backupRelativePath.replace(/\//g, path.sep));
    if (!pathInside(options.runDir, backupPath)) {
      contractFail("clone_backup_path_escape", "clone_backup", "backup escaped run directory");
    }
    const file = readExactRegularFile(backupPath, {
      phase: "clone_backup", maximumBytes: 128 * 1024 * 1024,
    });
    if (file.sha256 !== backup.sha256 || file.length !== backup.bytes
        || backup.sha256 !== backup.source.sha256 || backup.bytes !== backup.source.bytes) {
      contractFail("clone_backup_digest_mismatch", "clone_backup", "backup manifest bytes mismatch");
    }
  });
  if (options.set) {
    const set = verifyArtifactSet(options.set);
    const sources = options.backups.map((backup) => backup.source);
    if (canonicalJson(sources) !== canonicalJson(set.artifacts)) {
      contractFail("clone_backup_manifest_scope_invalid", "clone_backup",
        "backup manifest does not cover the exact target-before artifact set");
    }
  }
  return options.backups;
}

function atomicWriteExact(root, targetPath, bytes, expectedExistingJson) {
  const parent = assertExactDirectory(path.dirname(targetPath), "clone_prepare");
  if (!pathInside(root, targetPath) || !samePath(parent, path.join(root, "saves"))) {
    contractFail("clone_target_path_escape", "clone_prepare", "target JSON escaped saves root");
  }
  const existing = exactOptionalFile(targetPath, "clone_prepare");
  if (existing && !samePath(existing.path, targetPath)) {
    contractFail("clone_target_reparse", "clone_prepare", "target JSON path is not exact");
  }
  if (expectedExistingJson === null) {
    if (existing) {
      contractFail("clone_target_created_before_replace", "clone_prepare",
        "target JSON appeared after target-before capture; refusing unbacked overwrite");
    }
  } else if (!isPlainObject(expectedExistingJson) || expectedExistingJson.kind !== "json"
      || !existing || existing.sha256 !== expectedExistingJson.sha256
      || existing.length !== expectedExistingJson.bytes
      || !samePath(existing.path, targetPath)) {
    contractFail("clone_target_changed_before_replace", "clone_prepare",
      "target JSON changed after backup; refusing unbacked overwrite");
  }
  const temporary = path.join(parent, "." + path.basename(targetPath) + "."
    + process.pid + "." + crypto.randomBytes(8).toString("hex") + ".tmp");
  let created = false;
  try {
    fs.writeFileSync(temporary, bytes, { flag: "wx", mode: 0o600 });
    created = true;
    fs.renameSync(temporary, targetPath);
    created = false;
  } finally {
    if (created) { try { fs.unlinkSync(temporary); } catch (_error) {} }
  }
  const written = readExactRegularFile(targetPath, {
    phase: "clone_prepare", maximumBytes: 128 * 1024 * 1024,
  });
  if (written.sha256 !== sha256Bytes(bytes) || written.length !== bytes.length) {
    contractFail("clone_target_write_mismatch", "clone_prepare", "target JSON bytes changed after write");
  }
  return written;
}

function ensureOfflineRestoreParent(root, appData, artifact, targetPath) {
  const parent = path.dirname(targetPath);
  if (artifact.kind === "json") {
    const savesRoot = assertExactDirectory(path.join(root, "saves"),
      "clone_recovery_offline");
    if (!samePath(parent, savesRoot)) {
      contractFail("clone_offline_restore_path_invalid", "clone_recovery_offline",
        "offline JSON restore escaped the exact saves directory");
    }
    return savesRoot;
  }
  if (artifact.kind !== "sol" || !pathInside(appData, targetPath)) {
    contractFail("clone_offline_restore_path_invalid", "clone_recovery_offline",
      "offline SOL restore escaped the exact APPDATA directory");
  }
  fs.mkdirSync(parent, { recursive: true });
  return assertExactDirectory(parent, "clone_recovery_offline");
}

function atomicRestoreBackupArtifact(options) {
  const artifact = options.backup.source;
  const targetPath = artifactAbsolutePath(options.root, options.appData, artifact);
  const parent = ensureOfflineRestoreParent(options.root, options.appData, artifact, targetPath);
  const current = exactOptionalFile(targetPath, "clone_recovery_offline");
  const expectedCurrent = options.expectedCurrent || null;
  if (expectedCurrent === null) {
    if (current !== null) {
      contractFail("clone_offline_target_changed", "clone_recovery_offline",
        "offline restore target appeared after its stable snapshot", {
          locator: artifact.locator,
        });
    }
  } else if (!current || current.sha256 !== expectedCurrent.sha256
      || current.length !== expectedCurrent.bytes) {
    contractFail("clone_offline_target_changed", "clone_recovery_offline",
      "offline restore target changed after its stable snapshot", {
        locator: artifact.locator,
        expectedSha256: expectedCurrent.sha256,
        actualSha256: current && current.sha256 || null,
      });
  }
  const backupPath = path.resolve(options.runDir,
    options.backup.backupRelativePath.replace(/\//g, path.sep));
  const backup = readExactRegularFile(backupPath, {
    phase: "clone_recovery_offline", maximumBytes: 128 * 1024 * 1024,
  });
  if (backup.sha256 !== artifact.sha256 || backup.length !== artifact.bytes) {
    contractFail("clone_backup_digest_mismatch", "clone_recovery_offline",
      "offline restore backup bytes changed", { locator: artifact.locator });
  }
  if (current && current.sha256 === backup.sha256 && current.length === backup.length) {
    return { operation: "already_exact", locator: artifact.locator,
      sha256: backup.sha256, bytes: backup.length };
  }
  const temporary = path.join(parent, "." + path.basename(targetPath) + ".offline-restore."
    + process.pid + "." + crypto.randomBytes(8).toString("hex") + ".tmp");
  let temporaryPresent = false;
  try {
    fs.writeFileSync(temporary, backup.bytes, { flag: "wx", mode: 0o600 });
    temporaryPresent = true;
    const staged = readExactRegularFile(temporary, {
      phase: "clone_recovery_offline", maximumBytes: 128 * 1024 * 1024,
    });
    if (staged.sha256 !== backup.sha256 || staged.length !== backup.length) {
      contractFail("clone_offline_restore_stage_mismatch", "clone_recovery_offline",
        "offline restore staging bytes changed", { locator: artifact.locator });
    }
    fs.renameSync(temporary, targetPath);
    temporaryPresent = false;
  } finally {
    if (temporaryPresent) {
      try { fs.unlinkSync(temporary); } catch (_error) {}
    }
  }
  const restored = readExactRegularFile(targetPath, {
    phase: "clone_recovery_offline", maximumBytes: 128 * 1024 * 1024,
  });
  if (restored.sha256 !== backup.sha256 || restored.length !== backup.length) {
    contractFail("clone_offline_restore_write_mismatch", "clone_recovery_offline",
      "offline restored artifact bytes changed", { locator: artifact.locator });
  }
  return { operation: "restored", locator: artifact.locator,
    sha256: restored.sha256, bytes: restored.length };
}

function removeOfflineRestoreExtra(options) {
  const targetPath = artifactAbsolutePath(options.root, options.appData, options.artifact);
  const current = exactOptionalFile(targetPath, "clone_recovery_offline");
  if (!current || current.sha256 !== options.artifact.sha256
      || current.length !== options.artifact.bytes) {
    contractFail("clone_offline_target_changed", "clone_recovery_offline",
      "offline restore extra artifact changed after its stable snapshot", {
        locator: options.artifact.locator,
      });
  }
  fs.unlinkSync(targetPath);
  if (exactOptionalFile(targetPath, "clone_recovery_offline") !== null) {
    contractFail("clone_offline_restore_remove_failed", "clone_recovery_offline",
      "offline restore extra artifact remained", { locator: options.artifact.locator });
  }
  return { operation: "removed", locator: options.artifact.locator,
    sha256: options.artifact.sha256, bytes: options.artifact.bytes };
}

function readExactOfflineRecovery(options) {
  const record = readCloneRecovery(options.root, options.slot, false, true);
  const expectedRecordSha256 = assertExpectedSha256(options.expectedRecoveryRecordSha256,
    "expected clone recovery digest");
  const expectedStatus = String(options.expectedRecoveryStatus || "");
  if (!RECOVERY_STATUSES.has(expectedStatus)
      || record.status !== expectedStatus
      || record.recordSha256 !== expectedRecordSha256) {
    contractFail("clone_offline_recovery_changed", "clone_recovery_offline",
      "offline clone restore lost its exact recovery record/status binding", {
        expectedStatus,
        actualStatus: record.status,
        expectedRecoveryRecordSha256: expectedRecordSha256,
        actualRecoveryRecordSha256: record.recordSha256,
      });
  }
  return record;
}

function restoreAbandonedCloneFromRecovery(options) {
  const root = exactRoot(options.root, "clone_recovery_offline");
  const slot = assertDedicatedSlot(options.slot);
  const appData = exactAppData(options);
  const recordOnly = options.recordOnly === true;
  assertOfflineRuntimeExcluded(options);
  let record = readExactOfflineRecovery({ root, slot,
    expectedRecoveryRecordSha256: options.expectedRecoveryRecordSha256,
    expectedRecoveryStatus: options.expectedRecoveryStatus });
  if (!samePath(appData, record.seedBegin.appDataRoot)
      || !samePath(appData, record.targetBefore.appDataRoot)) {
    contractFail("clone_offline_appdata_mismatch", "clone_recovery_offline",
      "offline clone restore APPDATA root differs from the durable artifact sets");
  }
  const runDir = assertOwnedRunDirectory(root,
    path.resolve(root, record.runDir.replace(/\//g, path.sep)),
    path.join("tmp", "workbench-live-e2e"), "clone_recovery_offline");
  const inspection = inspectCloneLock({ root, slot });
  let abandonedLock = null;
  if (inspection.lockPresent) {
    if (recordOnly) {
      contractFail("clone_offline_record_only_lock_present", "clone_recovery_offline",
        "record-only recovery requires the exact clone lock to be absent");
    }
    abandonedLock = observeExpectedAbandonedLock({ root, slot,
      expectedLockSha256: options.expectedLockSha256 });
    if (abandonedLock.record.recoveryMode === true
        && abandonedLock.record.recoveryRecordSha256 !== record.recordSha256) {
      contractFail("clone_offline_lock_recovery_binding_invalid", "clone_recovery_offline",
        "recovery-mode lock is not bound to the exact recovery record");
    }
  } else {
    if (!recordOnly || record.status !== "prepared_pending_release"
        || options.expectedLockSha256 != null) {
      contractFail("clone_offline_record_only_invalid", "clone_recovery_offline",
        "lock-absent recovery is allowed only for an explicit prepared record-only state");
    }
  }
  verifyBackupManifest({ runDir, backups: record.backups, set: record.targetBefore });
  const seedInitial = captureSlotArtifactSet({ root, slot: record.seedSlot,
    appData, requireJson: true });
  assertArtifactSetInvariant(record.seedBegin, seedInitial,
    "clone_recovery_seed_not_restored");
  const targetInitial = captureSlotArtifactSet({ root, slot, appData, requireJson: false });

  assertOfflineRuntimeExcluded(options);
  record = readExactOfflineRecovery({ root, slot,
    expectedRecoveryRecordSha256: options.expectedRecoveryRecordSha256,
    expectedRecoveryStatus: options.expectedRecoveryStatus });
  if (abandonedLock) {
    abandonedLock = observeExpectedAbandonedLock({ root, slot,
      expectedLockSha256: options.expectedLockSha256 });
  } else if (inspectCloneLock({ root, slot }).lockPresent) {
    contractFail("clone_offline_record_only_lock_present", "clone_recovery_offline",
      "clone lock appeared during record-only recovery");
  }
  verifyBackupManifest({ runDir, backups: record.backups, set: record.targetBefore });
  const seedBeforeMutation = captureSlotArtifactSet({ root, slot: record.seedSlot,
    appData, requireJson: true });
  assertArtifactSetInvariant(record.seedBegin, seedBeforeMutation,
    "clone_recovery_seed_not_restored");
  const targetBeforeMutation = captureSlotArtifactSet({ root, slot, appData,
    requireJson: false });
  assertArtifactSetInvariant(targetInitial, targetBeforeMutation,
    "clone_offline_target_changed");
  const currentByLocator = new Map(targetBeforeMutation.artifacts
    .map((artifact) => [artifact.locator, artifact]));
  const desiredLocators = new Set(record.targetBefore.artifacts
    .map((artifact) => artifact.locator));
  const operations = [];
  record.backups.forEach((backup) => {
    operations.push(atomicRestoreBackupArtifact({ root, appData, runDir, backup,
      expectedCurrent: currentByLocator.get(backup.source.locator) || null }));
  });
  targetBeforeMutation.artifacts
    .filter((artifact) => !desiredLocators.has(artifact.locator))
    .forEach((artifact) => operations.push(removeOfflineRestoreExtra({ root, appData,
      artifact })));

  const targetRestored = captureSlotArtifactSet({ root, slot, appData,
    requireJson: record.targetBefore.artifacts.some((entry) => entry.kind === "json") });
  assertArtifactSetInvariant(record.targetBefore, targetRestored,
    "clone_recovery_not_restored");
  const seedRestored = captureSlotArtifactSet({ root, slot: record.seedSlot,
    appData, requireJson: true });
  assertArtifactSetInvariant(record.seedBegin, seedRestored,
    "clone_recovery_seed_not_restored");

  assertOfflineRuntimeExcluded(options);
  readExactOfflineRecovery({ root, slot,
    expectedRecoveryRecordSha256: options.expectedRecoveryRecordSha256,
    expectedRecoveryStatus: options.expectedRecoveryStatus });
  if (abandonedLock) {
    observeExpectedAbandonedLock({ root, slot,
      expectedLockSha256: options.expectedLockSha256 });
  }
  const recoveryClear = clearExactCloneRecoveryRecord(root, slot,
    record.recordSha256, record.status);
  let lockClear = null;
  if (abandonedLock) {
    lockClear = unlinkExpectedAbandonedLock({ root, slot,
      expectedLockSha256: options.expectedLockSha256,
      expectedRecoveryRecordSha256: record.recordSha256,
      assertNoRuntime: options.assertNoRuntime });
  }
  assertOfflineRuntimeExcluded(options);
  const finalInspection = inspectCloneLock({ root, slot });
  if (finalInspection.lockPresent || finalInspection.recoveryPresent) {
    contractFail("clone_offline_restore_clearance_incomplete", "clone_recovery_offline",
      "offline clone restore left a lock or recovery record", {
        lockPresent: finalInspection.lockPresent,
        recoveryPresent: finalInspection.recoveryPresent,
      });
  }
  const evidence = { schema: OFFLINE_RESTORE_SCHEMA, apiVersion: API_VERSION,
    restoredAt: new Date().toISOString(), slot, recoveryStatus: record.status,
    recoveryRecordSha256: record.recordSha256,
    lockRecordSha256: lockClear ? lockClear.lockRecordSha256 : null,
    recordOnly, noRuntimeConfirmed: true, backupsVerified: true,
    seedSetSha256: seedRestored.setSha256,
    targetBeforeSetSha256: record.targetBefore.setSha256,
    restoredTargetSetSha256: targetRestored.setSha256,
    operations, recoveryFileAbsent: recoveryClear.recoveryFileAbsent,
    lockFileAbsent: true };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function prepareDedicatedClone(options) {
  const root = exactRoot(options.root, "clone_prepare");
  const seedSlot = assertSourceSlot(options.seedSlot);
  const targetSlot = assertDedicatedSlot(options.targetSlot);
  if (seedSlot === targetSlot) {
    contractFail("clone_seed_equals_target", "clone_prepare", "seed and target must differ");
  }
  const runDir = assertOwnedRunDirectory(root, options.runDir,
    options.ownedBaseRelative || path.join("tmp", "workbench-live-e2e"), "clone_prepare");
  assertCloneLockOwned(options.lock, targetSlot);
  if (options.lock.recoveryMode === true) {
    contractFail("clone_prepare_recovery_lock_forbidden", "clone_prepare",
      "a recovery-mode lock can restore targetBefore only; it cannot prepare a new clone");
  }
  const appData = exactAppData(options);
  const seedBegin = captureSlotArtifactSet({ root, slot: seedSlot, appData, requireJson: true });
  const seedJsonArtifact = seedBegin.artifacts.find((entry) => entry.kind === "json");
  const seedJsonPath = artifactAbsolutePath(root, appData, seedJsonArtifact);
  const seedFile = readExactRegularFile(seedJsonPath, {
    phase: "clone_prepare", maximumBytes: 128 * 1024 * 1024,
  });
  let seedData;
  try { seedData = JSON.parse(seedFile.bytes.toString("utf8")); }
  catch (error) { contractFail("clone_seed_json_invalid", "clone_prepare", error.message); }
  if (typeof options.validateSeed === "function" && options.validateSeed(seedData) !== true) {
    contractFail("clone_seed_contract_invalid", "clone_prepare", "caller seed contract rejected the JSON");
  }
  let targetBytes = seedFile.bytes;
  let transformId = "exact-byte-copy";
  if (typeof options.transformJson === "function") {
    transformId = String(options.transformId || "");
    if (!/^[A-Za-z0-9._~-]{1,120}$/.test(transformId)) {
      contractFail("clone_transform_id_invalid", "clone_prepare", "transformed clone needs an exact id");
    }
    const transformed = options.transformJson(JSON.parse(JSON.stringify(seedData)));
    if (Buffer.isBuffer(transformed)) targetBytes = transformed;
    else if (typeof transformed === "string") targetBytes = Buffer.from(transformed, "utf8");
    else if (isPlainObject(transformed) || Array.isArray(transformed)) {
      targetBytes = Buffer.from(JSON.stringify(transformed), "utf8");
    } else {
      contractFail("clone_transform_output_invalid", "clone_prepare", "clone transform output is invalid");
    }
  }
  let targetData;
  try { targetData = JSON.parse(targetBytes.toString("utf8")); }
  catch (error) { contractFail("clone_target_json_invalid", "clone_prepare", error.message); }
  if (typeof options.validateTarget === "function" && options.validateTarget(targetData) !== true) {
    contractFail("clone_target_contract_invalid", "clone_prepare", "caller target contract rejected the JSON");
  }
  const targetBefore = captureSlotArtifactSet({
    root, slot: targetSlot, appData, requireJson: false,
  });
  const backups = backupArtifactSet({ root, appData, runDir, set: targetBefore });
  const targetPath = saveJsonPath(root, targetSlot);
  const mutationProgress = [];
  beginCloneMutation(options.lock);
  const beganRecovery = writeCloneRecovery({ root, slot: targetSlot, seedSlot, runDir,
    seedBegin, targetBefore, backups, mutationProgress, status: "mutation_in_progress",
    targetPrepared: null, preparationContextSha256: null, error: null });
  bindCloneRecoveryState(options.lock, beganRecovery);
  let activeRecovery = beganRecovery;
  let targetPrepared;
  let seedEnd;
  try {
    targetBefore.artifacts.filter((entry) => entry.kind === "sol").forEach((artifact) => {
      const solPath = artifactAbsolutePath(root, appData, artifact);
      const before = readExactRegularFile(solPath, {
        phase: "clone_prepare", maximumBytes: 128 * 1024 * 1024,
      });
      if (before.sha256 !== artifact.sha256) {
        contractFail("clone_target_changed_before_remove", "clone_prepare", "target SOL changed");
      }
      fs.unlinkSync(solPath);
      mutationProgress.push({ operation: "sol_removed", locator: artifact.locator,
        sha256: artifact.sha256 });
    });
    if (typeof options.beforeJsonReplace === "function") options.beforeJsonReplace();
    const targetBeforeJson = targetBefore.artifacts.find((entry) => entry.kind === "json") || null;
    atomicWriteExact(root, targetPath, targetBytes, targetBeforeJson);
    mutationProgress.push({ operation: "json_replaced", locator: "root:saves/" + targetSlot + ".json",
      sha256: sha256Bytes(targetBytes), bytes: targetBytes.length });
    targetPrepared = captureSlotArtifactSet({
      root, slot: targetSlot, appData, requireJson: true,
    });
    if (targetPrepared.artifacts.some((entry) => entry.kind === "sol")) {
      contractFail("clone_target_sol_remained", "clone_prepare", "target SOL remained after preparation");
    }
    seedEnd = captureSlotArtifactSet({ root, slot: seedSlot, appData, requireJson: true });
    assertArtifactSetInvariant(seedBegin, seedEnd);
    verifyBackupManifest({ runDir, backups, set: targetBefore });
    const preparationContextSha256 = sha256Text(canonicalJson({ root, runDir, seedSlot,
      targetSlot, transformId, seedBegin, seedAfterPrepare: seedEnd,
      targetBefore, targetPrepared, backups }));
    activeRecovery = writeCloneRecovery({ root, slot: targetSlot, seedSlot, runDir,
      seedBegin, targetBefore, backups, mutationProgress, status: "prepared_pending_release",
      targetPrepared, preparationContextSha256, error: null, replace: true,
      expectedRecordSha256: activeRecovery.recordSha256 });
    bindCloneRecoveryState(options.lock, activeRecovery);
    const preparation = {
      schema: PREPARATION_SCHEMA,
      apiVersion: API_VERSION,
      preparedAt: new Date().toISOString(),
      root,
      runDir,
      seedSlot,
      targetSlot,
      transformId,
      lock: publicLockEvidence(options.lock),
      seedBegin,
      seedAfterPrepare: seedEnd,
      targetBefore,
      targetPrepared,
      backups,
      preparationContextSha256,
      mutationJournal: { beganRecordSha256: beganRecovery.recordSha256,
        activeRecordSha256: activeRecovery.recordSha256,
        activeStatus: activeRecovery.status, recoveryFilePresent: true },
    };
    preparation.preparationSha256 = sha256Text(canonicalJson(preparation));
    bindCloneRecoveryState(options.lock, activeRecovery, {
      preparationSha256: preparation.preparationSha256,
    });
    return preparation;
  } catch (error) {
    const recovery = writeCloneRecovery({ root, slot: targetSlot, seedSlot, runDir,
      seedBegin, targetBefore, backups, mutationProgress, status: "manual_recovery_required",
      targetPrepared: targetPrepared || null, preparationContextSha256: null,
      error, replace: true, expectedRecordSha256: activeRecovery.recordSha256 });
    bindCloneRecoveryState(options.lock, recovery, { manualRecoveryRequired: true });
    contractFail("clone_prepare_manual_recovery_required", "clone_prepare",
      "target mutation failed after preparation began; manual recovery is required", {
        recoveryRecordSha256: recovery.recordSha256,
        mutationProgress,
        originalCode: error && error.code || null,
      });
  }
}

function verifyClonePreparation(options) {
  const preparation = options.preparation;
  if (!isPlainObject(preparation) || preparation.schema !== PREPARATION_SCHEMA
      || preparation.apiVersion !== API_VERSION
      || typeof preparation.root !== "string" || !path.isAbsolute(preparation.root)
      || typeof preparation.runDir !== "string" || !path.isAbsolute(preparation.runDir)
      || preparation.seedSlot !== assertSourceSlot(preparation.seedSlot)
      || preparation.targetSlot !== assertDedicatedSlot(preparation.targetSlot)
      || !isPlainObject(preparation.lock)
      || preparation.lock.schema !== LOCK_SCHEMA
      || preparation.lock.slot !== preparation.targetSlot
      || !Number.isInteger(preparation.lock.ownerPid) || preparation.lock.ownerPid < 1
      || !/^\d{16,20}$/.test(String(preparation.lock.ownerProcessStartUtcTicks || ""))
      || preparation.lock.recoveryMode !== false
      || preparation.lock.recoveryRecordSha256 !== null
      || !/^[a-f0-9]{64}$/.test(String(preparation.lock.recordSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(preparation.preparationContextSha256 || ""))
      || !isPlainObject(preparation.mutationJournal)
      || !/^[a-f0-9]{64}$/.test(String(preparation.mutationJournal.beganRecordSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(preparation.mutationJournal.activeRecordSha256 || ""))
      || preparation.mutationJournal.activeStatus !== "prepared_pending_release"
      || preparation.mutationJournal.recoveryFilePresent !== true
      || !/^[a-f0-9]{64}$/.test(String(preparation.preparationSha256 || ""))) {
    contractFail("clone_preparation_invalid", "clone_prepare", "clone preparation is malformed");
  }
  const payload = Object.assign({}, preparation);
  delete payload.preparationSha256;
  if (sha256Text(canonicalJson(payload)) !== preparation.preparationSha256) {
    contractFail("clone_preparation_digest_mismatch", "clone_prepare",
      "clone preparation artifact was modified");
  }
  [preparation.seedBegin, preparation.seedAfterPrepare,
    preparation.targetBefore, preparation.targetPrepared].forEach(verifyArtifactSet);
  if (preparation.seedBegin.slot !== preparation.seedSlot
      || preparation.seedAfterPrepare.slot !== preparation.seedSlot
      || preparation.targetBefore.slot !== preparation.targetSlot
      || preparation.targetPrepared.slot !== preparation.targetSlot
      || preparation.targetPrepared.artifacts.filter((entry) => entry.kind === "json").length !== 1
      || preparation.targetPrepared.artifacts.some((entry) => entry.kind === "sol")) {
    contractFail("clone_preparation_scope_invalid", "clone_prepare",
      "clone preparation artifact sets do not match their exact seed/target roles");
  }
  assertArtifactSetInvariant(preparation.seedBegin, preparation.seedAfterPrepare);
  const preparationContextSha256 = sha256Text(canonicalJson({ root: preparation.root,
    runDir: preparation.runDir, seedSlot: preparation.seedSlot,
    targetSlot: preparation.targetSlot, transformId: preparation.transformId,
    seedBegin: preparation.seedBegin, seedAfterPrepare: preparation.seedAfterPrepare,
    targetBefore: preparation.targetBefore, targetPrepared: preparation.targetPrepared,
    backups: preparation.backups }));
  if (preparationContextSha256 !== preparation.preparationContextSha256) {
    contractFail("clone_preparation_context_mismatch", "clone_prepare",
      "clone preparation context no longer binds its exact artifact sets");
  }
  verifyBackupManifest({ runDir: preparation.runDir, backups: preparation.backups,
    set: preparation.targetBefore });
  const recovery = readCloneRecovery(preparation.root, preparation.targetSlot, false);
  if (recovery.status !== "prepared_pending_release"
      || recovery.recordSha256 !== preparation.mutationJournal.activeRecordSha256
      || recovery.preparationContextSha256 !== preparation.preparationContextSha256
      || canonicalJson(recovery.seedBegin) !== canonicalJson(preparation.seedBegin)
      || canonicalJson(recovery.targetBefore) !== canonicalJson(preparation.targetBefore)
      || canonicalJson(recovery.targetPrepared) !== canonicalJson(preparation.targetPrepared)
      || canonicalJson(recovery.backups) !== canonicalJson(preparation.backups)) {
    contractFail("clone_preparation_recovery_mismatch", "clone_prepare",
      "clone preparation lost its exact durable prepared recovery record");
  }
  if (options.verifyCurrentSeed === true) {
    verifyCurrentSlotArtifactSet({ root: preparation.root, appData: options.appData,
      set: preparation.seedBegin });
  }
  return preparation;
}

function clearCloneRecoveryAfterRestore(options) {
  const root = exactRoot(options.root, "clone_recovery");
  const slot = assertDedicatedSlot(options.slot);
  assertCloneLockOwned(options.lock, slot);
  if (options.lock.recoveryMode !== true) {
    contractFail("clone_recovery_lock_required", "clone_recovery",
      "manual recovery clearance requires a recovery-mode exclusive lock");
  }
  const record = readCloneRecovery(root, slot, false);
  if (options.lock.recoveryRecordSha256 !== record.recordSha256) {
    contractFail("clone_recovery_record_changed", "clone_recovery",
      "manual recovery record changed after the recovery lock was acquired");
  }
  if (!["mutation_in_progress", "manual_recovery_required"].includes(record.status)) {
    contractFail("clone_recovery_offline_clear_required", "clone_recovery",
      "prepared clone recovery cannot be cleared through the live recovery-lock path");
  }
  const runDir = path.resolve(root, record.runDir.replace(/\//g, path.sep));
  verifyBackupManifest({ runDir, backups: record.backups, set: record.targetBefore });
  const seedCurrent = captureSlotArtifactSet({ root, slot: record.seedSlot,
    appData: options.appData, requireJson: true });
  assertArtifactSetInvariant(record.seedBegin, seedCurrent, "clone_recovery_seed_not_restored");
  const current = captureSlotArtifactSet({ root, slot,
    appData: options.appData, requireJson: record.targetBefore.artifacts.some((entry) => entry.kind === "json") });
  assertArtifactSetInvariant(record.targetBefore, current, "clone_recovery_not_restored");
  const clearance = clearExactCloneRecoveryRecord(root, slot, record.recordSha256, record.status);
  const runtimeState = lockRuntimeStates.get(options.lock);
  runtimeState.activeRecoveryRecordSha256 = null;
  runtimeState.recoveryCleared = true;
  return { schema: "workbench-live-e2e.clone-manual-recovery-clear.v1",
    slot, clearedAt: new Date().toISOString(), restoredSetSha256: current.setSha256,
    restoredSeedSetSha256: seedCurrent.setSha256,
    recoveryRecordSha256: record.recordSha256,
    recoveryFileAbsent: clearance.recoveryFileAbsent };
}

function clearPreparedCloneRecoveryAfterOfflineRestore(options) {
  const root = exactRoot(options.root, "clone_recovery_offline");
  const slot = assertDedicatedSlot(options.slot);
  if (typeof options.assertNoRuntime !== "function" || options.assertNoRuntime() !== true) {
    contractFail("clone_recovery_offline_runtime_not_excluded", "clone_recovery_offline",
      "offline prepared recovery clearance requires an exact no-live-runtime assertion");
  }
  const lockPath = path.join(cloneLockDirectory(root), slot + ".clone.lock");
  if (readCloneLockRecord(root, slot, lockPath, true) !== null) {
    contractFail("clone_recovery_offline_lock_present", "clone_recovery_offline",
      "offline prepared recovery clearance requires the exact clone lock to be absent");
  }
  const record = readCloneRecovery(root, slot, false);
  if (record.status !== "prepared_pending_release"
      || !/^[a-f0-9]{64}$/.test(String(options.expectedRecordSha256 || ""))
      || record.recordSha256 !== options.expectedRecordSha256) {
    contractFail("clone_recovery_record_changed", "clone_recovery_offline",
      "offline prepared recovery clearance lost its exact record binding");
  }
  const runDir = path.resolve(root, record.runDir.replace(/\//g, path.sep));
  verifyBackupManifest({ runDir, backups: record.backups, set: record.targetBefore });
  const seedCurrent = captureSlotArtifactSet({ root, slot: record.seedSlot,
    appData: options.appData, requireJson: true });
  assertArtifactSetInvariant(record.seedBegin, seedCurrent, "clone_recovery_seed_not_restored");
  const targetCurrent = captureSlotArtifactSet({ root, slot,
    appData: options.appData,
    requireJson: record.targetBefore.artifacts.some((entry) => entry.kind === "json") });
  assertArtifactSetInvariant(record.targetBefore, targetCurrent, "clone_recovery_not_restored");
  const clearance = clearExactCloneRecoveryRecord(root, slot,
    record.recordSha256, "prepared_pending_release");
  return { schema: "workbench-live-e2e.clone-prepared-offline-recovery-clear.v1",
    apiVersion: API_VERSION, slot, clearedAt: new Date().toISOString(),
    noRuntimeConfirmed: true, lockFileAbsent: true,
    restoredSeedSetSha256: seedCurrent.setSha256,
    restoredTargetSetSha256: targetCurrent.setSha256,
    recoveryRecordSha256: record.recordSha256,
    recoveryFileAbsent: clearance.recoveryFileAbsent };
}

function releaseDedicatedClone(options) {
  const preparation = options.preparation;
  assertCloneLockOwned(options.lock, options.lock.slot);
  const runtimeState = lockRuntimeStates.get(options.lock);
  const recovery = readCloneRecovery(options.lock.root, options.lock.slot, false);
  if (!preparation || runtimeState.preparationSha256 !== preparation.preparationSha256
      || runtimeState.activeRecoveryRecordSha256 !== recovery.recordSha256
      || recovery.status !== "prepared_pending_release") {
    contractFail("clone_release_state_mismatch", "clone_release",
      "clone release is not bound to the active prepared lock/recovery state");
  }
  let evidence;
  try {
    verifyClonePreparation({ preparation, appData: options.appData, verifyCurrentSeed: true });
    if (preparation.lock.recordSha256 !== options.lock.recordSha256
        || preparation.lock.ownerPid !== process.pid
        || preparation.lock.ownerProcessStartUtcTicks !== options.lock.ownerProcessStartUtcTicks
        || preparation.lock.recoveryMode !== options.lock.recoveryMode
        || preparation.lock.recoveryRecordSha256 !== options.lock.recoveryRecordSha256) {
      contractFail("clone_release_lock_mismatch", "clone_release",
        "clone release lock is not the exact lock recorded by preparation");
    }
    const appData = exactAppData(options);
    const seedEnd = captureSlotArtifactSet({ root: preparation.root,
      slot: preparation.seedSlot, appData, requireJson: true });
    assertArtifactSetInvariant(preparation.seedBegin, seedEnd);
    const targetEnd = captureSlotArtifactSet({ root: preparation.root,
      slot: preparation.targetSlot, appData, requireJson: true });
    verifyBackupManifest({ runDir: preparation.runDir, backups: preparation.backups,
      set: preparation.targetBefore });
    evidence = { schema: RELEASE_SCHEMA, apiVersion: API_VERSION,
      releasedAt: new Date().toISOString(), seedEnd, targetEnd,
      backupsVerified: true,
      preparedRecoveryRecordSha256: recovery.recordSha256 };
  } catch (error) {
    const failedRecovery = writeCloneRecovery({ root: options.lock.root,
      slot: recovery.slot, seedSlot: recovery.seedSlot,
      runDir: path.resolve(options.lock.root, recovery.runDir.replace(/\//g, path.sep)),
      seedBegin: recovery.seedBegin, targetBefore: recovery.targetBefore,
      backups: recovery.backups, mutationProgress: recovery.mutationProgress,
      status: "manual_recovery_required", targetPrepared: recovery.targetPrepared,
      preparationContextSha256: recovery.preparationContextSha256,
      error, replace: true, expectedRecordSha256: recovery.recordSha256 });
    bindCloneRecoveryState(options.lock, failedRecovery, { manualRecoveryRequired: true });
    contractFail("clone_release_manual_recovery_required", "clone_release",
      "clone terminal verification failed; exact offline recovery is required", {
        recoveryRecordSha256: failedRecovery.recordSha256,
        originalCode: error && error.code || null,
      });
  }
  const lockRelease = unlinkPreparedCloneLock(options.lock,
    preparation.preparationSha256, recovery.recordSha256);
  const recoveryClear = clearExactCloneRecoveryRecord(preparation.root,
    preparation.targetSlot, recovery.recordSha256, "prepared_pending_release");
  evidence.lockRelease = lockRelease;
  evidence.recoveryClear = recoveryClear;
  evidence.releaseSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

async function withCloneLock(options, callback) {
  const lock = acquireCloneLock(options);
  try { return await callback(lock); }
  finally {
    const runtimeState = lockRuntimeStates.get(lock);
    if (!lock.released && runtimeState && !runtimeState.mutationBegan
        && !runtimeState.manualRecoveryRequired
        && (lock.recoveryMode !== true || runtimeState.recoveryCleared === true)) {
      releaseCloneLock(lock);
    }
  }
}

module.exports = {
  API_VERSION,
  ARTIFACT_SET_SCHEMA,
  LOCK_SCHEMA,
  OFFLINE_LOCK_CLEAR_SCHEMA,
  OFFLINE_RESTORE_SCHEMA,
  PREPARATION_SCHEMA,
  RELEASE_SCHEMA,
  acquireCloneLock,
  assertArtifactSetInvariant,
  assertCloneLockOwned,
  assertDedicatedSlot,
  assertSourceSlot,
  captureSlotArtifactSet,
  captureStableSlotArtifactSet,
  clearAbandonedNoRecoveryCloneLock,
  clearCloneRecoveryAfterRestore,
  clearPreparedCloneRecoveryAfterOfflineRestore,
  findOwnedSolFiles,
  inspectCloneLock,
  isOwnedSolPath,
  prepareDedicatedClone,
  publicLockEvidence,
  releaseCloneLock,
  releaseDedicatedClone,
  readCloneRecovery,
  restoreAbandonedCloneFromRecovery,
  saveJsonPath,
  solOwnershipSuffix,
  verifyArtifactSet,
  verifyBackupManifest,
  verifyClonePreparation,
  verifyCurrentSlotArtifactSet,
  withCloneLock,
};
