#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const CloneGuard = require("./clone-save-guard");
const LauncherObservation = require("./launcher-observation");
const {
  assertExactDirectory,
  canonicalJson,
  contractFail,
  readExactRegularFile,
  sha256Text,
} = require("./evidence-artifact");

const API_VERSION = "FROZEN-v1";
const RECEIPT_SCHEMA = "workbench-live-e2e.offline-clone-recovery-receipt.v1";
const OUTPUT_SCHEMA = "workbench-live-e2e.offline-clone-recovery-output.v1";
const CANONICAL_ROOT = path.resolve(__dirname, "..", "..", "..");
const MODES = new Set([
  "inspect",
  "clear-no-recovery-lock",
  "restore-from-recovery",
  "restore-record-only",
]);
const RECOVERY_STATUSES = new Set([
  "mutation_in_progress",
  "prepared_pending_release",
  "manual_recovery_required",
]);
const VALUE_OPTIONS = new Set([
  "--slot",
  "--expected-lock-sha256",
  "--expected-recovery-sha256",
  "--expected-recovery-status",
]);

function argumentFail(message, details) {
  contractFail("offline_recovery_arguments_invalid", "offline_recovery_cli", message, details);
}

function parseArguments(argv) {
  if (!Array.isArray(argv) || argv.length < 1 || !MODES.has(String(argv[0] || ""))) {
    argumentFail("first argument must be one exact offline recovery mode");
  }
  const mode = argv[0];
  const values = new Map();
  let allowOfflineRecovery = false;
  for (let index = 1; index < argv.length; index += 1) {
    const token = String(argv[index] || "");
    if (token === "--allow-offline-recovery") {
      if (allowOfflineRecovery) argumentFail("authorization flag was duplicated");
      allowOfflineRecovery = true;
      continue;
    }
    if (!VALUE_OPTIONS.has(token) || index + 1 >= argv.length) {
      argumentFail("unknown, missing, or value-less CLI option", { token });
    }
    if (values.has(token)) argumentFail("CLI option was duplicated", { token });
    const value = String(argv[index + 1] || "");
    if (!value || value.startsWith("--")) {
      argumentFail("CLI option requires one non-option value", { token });
    }
    values.set(token, value);
    index += 1;
  }
  const slot = values.get("--slot");
  CloneGuard.assertDedicatedSlot(slot);
  const lockSha256 = values.get("--expected-lock-sha256") || null;
  const recoverySha256 = values.get("--expected-recovery-sha256") || null;
  const recoveryStatus = values.get("--expected-recovery-status") || null;
  const digestValid = (value) => value === null || /^[a-f0-9]{64}$/i.test(value);
  if (!digestValid(lockSha256) || !digestValid(recoverySha256)) {
    argumentFail("expected digests must be exact SHA-256 values");
  }
  if (mode === "inspect") {
    if (allowOfflineRecovery || lockSha256 || recoverySha256 || recoveryStatus
        || values.size !== 1) {
      argumentFail("inspect accepts only --slot");
    }
  } else if (!allowOfflineRecovery) {
    argumentFail("mutation mode requires --allow-offline-recovery");
  } else if (mode === "clear-no-recovery-lock") {
    if (!lockSha256 || recoverySha256 || recoveryStatus || values.size !== 2) {
      argumentFail("pre-mutation lock clearance requires only slot and exact lock digest");
    }
  } else if (mode === "restore-from-recovery") {
    if (!lockSha256 || !recoverySha256
        || !RECOVERY_STATUSES.has(recoveryStatus)
        || values.size !== 4) {
      argumentFail("locked restore requires slot, lock/recovery digests, and exact status");
    }
  } else if (mode === "restore-record-only") {
    if (lockSha256 || !recoverySha256
        || recoveryStatus !== "prepared_pending_release"
        || values.size !== 3) {
      argumentFail("record-only restore requires a prepared record digest and no lock digest");
    }
  }
  return Object.freeze({ mode, slot,
    expectedLockSha256: lockSha256 && lockSha256.toLowerCase(),
    expectedRecoveryRecordSha256: recoverySha256 && recoverySha256.toLowerCase(),
    expectedRecoveryStatus: recoveryStatus,
    allowOfflineRecovery });
}

function createRuntimeObserver(dependencies, observations) {
  return function assertNoRuntime() {
    const processes = dependencies.queryLauncherCoreProcesses();
    dependencies.assertExclusiveLauncherProcess(processes, null);
    observations.push({ observedAt: new Date().toISOString(),
      processCount: processes.length,
      pids: processes.map((entry) => entry.pid).sort((left, right) => left - right) });
    return true;
  };
}

function writeReceipt(root, parsed, result, runtimeObservations) {
  const receiptDirectory = path.join(root, "tmp", "workbench-live-e2e",
    "offline-recovery-receipts");
  fs.mkdirSync(receiptDirectory, { recursive: true });
  assertExactDirectory(receiptDirectory, "offline_recovery_receipt");
  const payload = { schema: RECEIPT_SCHEMA, apiVersion: API_VERSION,
    completedAt: new Date().toISOString(), operation: parsed.mode, slot: parsed.slot,
    authorizationConfirmed: parsed.allowOfflineRecovery,
    expectedLockSha256: parsed.expectedLockSha256,
    expectedRecoveryRecordSha256: parsed.expectedRecoveryRecordSha256,
    expectedRecoveryStatus: parsed.expectedRecoveryStatus,
    runtimeObservations: runtimeObservations.slice(), result };
  const receipt = Object.assign({}, payload, {
    evidenceSha256: sha256Text(canonicalJson(payload)),
  });
  const fileName = receipt.completedAt.replace(/[^0-9]/g, "") + "-" + parsed.mode + "-"
    + parsed.slot + "-" + process.pid + "-" + crypto.randomBytes(6).toString("hex") + ".json";
  const receiptPath = path.join(receiptDirectory, fileName);
  fs.writeFileSync(receiptPath, canonicalJson(receipt), {
    encoding: "utf8", flag: "wx", mode: 0o600,
  });
  const file = readExactRegularFile(receiptPath, {
    phase: "offline_recovery_receipt", maximumBytes: 4 * 1024 * 1024,
  });
  return { relativePath: path.relative(root, receiptPath).replace(/\\/g, "/"),
    sha256: file.sha256, bytes: file.length,
    evidenceSha256: receipt.evidenceSha256 };
}

function executeOfflineRecovery(options) {
  const root = assertExactDirectory(path.resolve(options.root), "offline_recovery_cli");
  const parsed = parseArguments(options.argv);
  const dependencies = Object.assign({
    queryLauncherCoreProcesses: LauncherObservation.queryLauncherCoreProcesses,
    assertExclusiveLauncherProcess: LauncherObservation.assertExclusiveLauncherProcess,
  }, options.dependencies || {});
  if (typeof dependencies.queryLauncherCoreProcesses !== "function"
      || typeof dependencies.assertExclusiveLauncherProcess !== "function") {
    contractFail("offline_recovery_dependencies_invalid", "offline_recovery_cli",
      "offline recovery process observation dependencies are invalid");
  }
  const runtimeObservations = [];
  let result;
  if (parsed.mode === "inspect") {
    const processes = dependencies.queryLauncherCoreProcesses();
    runtimeObservations.push({ observedAt: new Date().toISOString(),
      processCount: processes.length,
      pids: processes.map((entry) => entry.pid).sort((left, right) => left - right) });
    result = CloneGuard.inspectCloneLock({ root, slot: parsed.slot });
  } else {
    const assertNoRuntime = createRuntimeObserver(dependencies, runtimeObservations);
    if (parsed.mode === "clear-no-recovery-lock") {
      result = CloneGuard.clearAbandonedNoRecoveryCloneLock({ root, slot: parsed.slot,
        expectedLockSha256: parsed.expectedLockSha256, assertNoRuntime });
    } else {
      result = CloneGuard.restoreAbandonedCloneFromRecovery({ root, slot: parsed.slot,
        appData: options.appData == null ? process.env.APPDATA : options.appData,
        expectedLockSha256: parsed.expectedLockSha256,
        expectedRecoveryRecordSha256: parsed.expectedRecoveryRecordSha256,
        expectedRecoveryStatus: parsed.expectedRecoveryStatus,
        recordOnly: parsed.mode === "restore-record-only", assertNoRuntime });
    }
  }
  const receipt = writeReceipt(root, parsed, result, runtimeObservations);
  return { schema: OUTPUT_SCHEMA, apiVersion: API_VERSION, ok: true,
    operation: parsed.mode, slot: parsed.slot, result, receipt };
}

function publicError(error) {
  return { schema: OUTPUT_SCHEMA, apiVersion: API_VERSION, ok: false,
    error: { name: String(error && error.name || "Error"),
      code: String(error && error.code || "offline_recovery_failed"),
      phase: String(error && error.phase || "offline_recovery_cli"),
      message: String(error && error.message || "offline recovery failed"),
      details: error && error.details || null } };
}

module.exports = { API_VERSION, CANONICAL_ROOT, OUTPUT_SCHEMA, RECEIPT_SCHEMA,
  executeOfflineRecovery, parseArguments, publicError };

if (require.main === module) {
  try {
    process.stdout.write(JSON.stringify(executeOfflineRecovery({ root: CANONICAL_ROOT,
      argv: process.argv.slice(2) })) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify(publicError(error)) + "\n");
    process.exitCode = 1;
  }
}
