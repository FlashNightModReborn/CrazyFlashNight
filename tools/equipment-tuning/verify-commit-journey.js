#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");
const LegacyHttpClient = require("../lib/legacy-http-client");
const {
  assertRuntimeIdentity,
  publicRuntimeIdentity,
  verifyRuntimeIdentity,
} = require("../lib/runtime-process-identity");
const opener = require("./run-unattended");
const previewGate = require("./verify-journey");

const root = path.resolve(__dirname, "../..");
const GATE = "PG-TUNE-E2E";
const SLOT = opener.DEFAULT_AGENT_SLOT;
const LOG_TAIL_LIMIT = 2000;
const TOKEN = /^[A-Za-z0-9._-]{1,160}$/;
const HASH = /^[A-Fa-f0-9]{64}$/;
const STATE_REF = /^sha256_[a-f0-9]{24}$/;
const BIGINT_DECIMAL = /^(?:0|[1-9]\d{0,39})$/;
const WEB_EVENTS = new Set([
  "candidate_hit",
  "preview_issued",
  "preview_adopted",
  "commit_issued",
  "commit_adopted",
  "inventory_refresh_settled",
  "reconcile_issued",
  "reconcile_adopted",
]);

class GateError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "GateError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
  }
}

function fail(code, phase, message, details) {
  throw new GateError(code, phase, message, details);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isToken(value) {
  return typeof value === "string" && TOKEN.test(value);
}

function bounded(value, maximum) {
  return typeof value === "string"
    && value.length > 0
    && value.length <= maximum
    && !/[\u0000-\u001f\u007f]/.test(value);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function authorityRef(value) {
  return "sha256_" + sha256(String(value)).slice(0, 24);
}

function parseArgs(argv) {
  const args = {
    check: false,
    help: false,
    openReport: null,
    interactionTimeoutMs: 300000,
    saveExitTimeoutMs: 300000,
    restartTimeoutMs: 180000,
    panelTimeoutMs: 120000,
    pollMs: 250,
    settleMs: 1500,
  };
  function next(index, flag) {
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      fail("missing_argument", "arguments", flag + " requires a value");
    }
    return value;
  }
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else if (token === "--open-report") args.openReport = next(index++, token);
    else if (token === "--interaction-timeout-ms") {
      args.interactionTimeoutMs = Number(next(index++, token));
    } else if (token === "--save-exit-timeout-ms") {
      args.saveExitTimeoutMs = Number(next(index++, token));
    } else if (token === "--restart-timeout-ms") {
      args.restartTimeoutMs = Number(next(index++, token));
    } else if (token === "--panel-timeout-ms") {
      args.panelTimeoutMs = Number(next(index++, token));
    } else if (token === "--poll-ms") args.pollMs = Number(next(index++, token));
    else if (token === "--settle-ms") args.settleMs = Number(next(index++, token));
    else fail("unknown_argument", "arguments", "unknown argument: " + token);
  }
  if (args.check) {
    if (argv.length !== 1) {
      fail("check_argument_conflict", "arguments", "--check must be used alone");
    }
    return args;
  }
  if (args.help) return args;
  if (!args.openReport) {
    fail("open_report_required", "arguments", "--open-report is required");
  }
  [
    ["interactionTimeoutMs", 5000, 900000],
    ["saveExitTimeoutMs", 5000, 900000],
    ["restartTimeoutMs", 10000, 600000],
    ["panelTimeoutMs", 5000, 600000],
    ["pollMs", 100, 10000],
    ["settleMs", 1000, 10000],
  ].forEach(([name, minimum, maximum]) => {
    if (!Number.isInteger(args[name])
        || args[name] < minimum || args[name] > maximum) {
      fail(
        "invalid_argument",
        "arguments",
        "--" + name.replace(/[A-Z]/g, (letter) => "-" + letter.toLowerCase())
          + " must be " + minimum + ".." + maximum
      );
    }
  });
  return args;
}

function printHelp() {
  console.log([
    "Equipment Tuning clone-save commit/restart journey verifier",
    "",
    "Usage:",
    "  node tools/equipment-tuning/verify-commit-journey.js --open-report <run-report.json>",
    "",
    "The verifier waits for two real safe-mode UI actions (candidate then Commit),",
    "then a real clone archive persistence receipt and Launcher process exit. It restarts the same",
    "verified runtime without reseeding the clone and waits for the same inventory",
    "slot to expose the committed stateRef. It never sends preview/commit/reconcile",
    "or save commands and it never reads or writes a non-agent save. The operator",
    "should use the current SAFEEXIT UI, but this receipt does not attest its exact UI session.",
    "",
    "Options:",
    "  --interaction-timeout-ms <ms>  Wait for candidate + Commit (default 300000).",
    "  --save-exit-timeout-ms <ms>     Wait for clone archive persistence/exit (default 300000).",
    "  --restart-timeout-ms <ms>       Restart readiness budget (default 180000).",
    "  --panel-timeout-ms <ms>         Reload panel/readback budget (default 120000).",
    "  --poll-ms <ms>                  Poll interval (default 250).",
    "  --settle-ms <ms>                Clean no-reconcile quiet window (default 1500).",
    "  --check                          Run pure offline positive/negative fixtures.",
  ].join("\n"));
}

function readJsonFile(filePath, code, phase) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(code, phase, "cannot read JSON: " + filePath, { message: error.message });
  }
}

function resolveOpenReport(value) {
  return previewGate.resolveOpenReport(value);
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function readCloneSnapshot(targetPath, allowMissing, phase) {
  phase = phase || "clone_baseline";
  let before;
  try {
    before = fs.lstatSync(targetPath, { bigint: true });
  } catch (error) {
    if (allowMissing && error && error.code === "ENOENT") return null;
    fail("clone_shadow_missing", phase, "clone shadow is missing: " + targetPath);
  }
  if (!before.isFile() || before.isSymbolicLink()) {
    fail(
      "clone_shadow_not_regular",
      phase,
      "clone shadow must remain a regular non-reparse file"
    );
  }
  let realPath;
  try {
    realPath = fs.realpathSync.native(targetPath);
  } catch (error) {
    if (allowMissing && error && error.code === "ENOENT") return null;
    fail("clone_shadow_realpath_failed", phase, error.message);
  }
  if (!samePath(realPath, targetPath)) {
    fail("clone_shadow_realpath_mismatch", phase, "clone real path is not exact");
  }
  let raw;
  let opened;
  let afterHandle;
  let afterRealPath;
  let handle = null;
  try {
    handle = fs.openSync(targetPath, "r");
    opened = fs.fstatSync(handle, { bigint: true });
    if (!opened.isFile()
        || before.dev !== opened.dev || before.ino !== opened.ino
        || before.size !== opened.size || before.mtimeNs !== opened.mtimeNs) {
      fail("clone_shadow_changed_before_open", phase, "clone identity changed before open");
    }
    raw = fs.readFileSync(handle);
    afterHandle = fs.fstatSync(handle, { bigint: true });
  } catch (error) {
    if (error && error.code && error.phase) throw error;
    if (allowMissing && error && error.code === "ENOENT") return null;
    fail("clone_shadow_read_failed", phase, error.message);
  } finally {
    if (handle !== null) fs.closeSync(handle);
  }
  let after;
  try {
    after = fs.lstatSync(targetPath, { bigint: true });
    afterRealPath = fs.realpathSync.native(targetPath);
  } catch (error) {
    if (allowMissing && error && error.code === "ENOENT") return null;
    fail("clone_shadow_post_read_failed", phase, error.message);
  }
  if (!after.isFile() || after.isSymbolicLink()
      || !samePath(afterRealPath, targetPath)
      || opened.dev !== afterHandle.dev || opened.ino !== afterHandle.ino
      || opened.size !== afterHandle.size || opened.mtimeNs !== afterHandle.mtimeNs
      || afterHandle.dev !== after.dev || afterHandle.ino !== after.ino
      || afterHandle.size !== after.size || afterHandle.mtimeNs !== after.mtimeNs
      || BigInt(raw.length) !== after.size) {
    fail("clone_shadow_changed_during_read", phase, "clone changed during its bound read");
  }
  return { raw, stat: after, realPath: afterRealPath };
}

function readCloneBytes(targetPath, allowMissing, phase) {
  const snapshot = readCloneSnapshot(targetPath, allowMissing, phase);
  return snapshot ? snapshot.raw : null;
}

function validateClonePreparationContract(report) {
  const prep = report && report.savePreparation;
  const baseline = prep && prep.gateBaseline;
  const expectedRelative = "saves/" + SLOT + ".json";
  const expectedTargetPath = path.resolve(root, expectedRelative);
  const timeline = Array.isArray(report && report.timeline) ? report.timeline : [];
  const snapshotPhases = timeline.filter((entry) => isObject(entry)
    && entry.phase === "snapshot_gate_reached");
  const baselinePhases = timeline.filter((entry) => isObject(entry)
    && entry.phase === "post_snapshot_clone_baseline_bound");
  const finalIdentityPhases = timeline.filter((entry) => isObject(entry)
    && entry.phase === "runtime_identity_reverified_after_clone_baseline");
  const reportSnapshot = report && report.snapshotGate && report.snapshotGate.evidence
    && report.snapshotGate.evidence.tuningSnapshot;
  const baselineSnapshot = baseline && baseline.snapshot;
  const postCapture = baseline && baseline.postCaptureLogWatermark;
  const archive = baseline && baseline.startupArchiveReceipt;
  const stableStartedAt = Date.parse(baseline && baseline.stableStartedAt);
  const capturedAt = Date.parse(baseline && baseline.capturedAt);
  const lastWriteAt = Date.parse(baseline && baseline.lastWriteTimeUtc);
  const postCaptureAt = Date.parse(postCapture && postCapture.capturedAt);
  const snapshotAt = Date.parse(snapshotPhases[0] && snapshotPhases[0].at);
  const finalIdentityAt = Date.parse(finalIdentityPhases[0] && finalIdentityPhases[0].at);
  const finishedAt = Date.parse(report && report.finishedAt);
  const baselinePhase = baselinePhases[0];
  let lastWriteFromNs = null;
  try {
    lastWriteFromNs = new Date(
      Number(BigInt(baseline && baseline.mtimeNs) / 1000000n)
    ).toISOString();
  } catch (_error) {
    lastWriteFromNs = null;
  }
  const startLogTotal = report && report.startLogWatermark
    ? report.startLogWatermark.total : null;
  const handoffLine = report && report.runtime && report.runtime.handoffEvidence
    ? report.runtime.handoffEvidence.lineNumber : null;
  const titleFrameLine = report && report.runtime && report.runtime.titleFrameEvidence
    ? report.runtime.titleFrameEvidence.lineNumber : null;
  const archiveEvidenceFloorLine = Number.isInteger(startLogTotal)
      && Number.isInteger(handoffLine) && Number.isInteger(titleFrameLine)
    ? Math.max(startLogTotal, handoffLine, titleFrameLine) : null;
  const baselineSnapshotLine = baselineSnapshot ? baselineSnapshot.lineNumber : null;
  const changedFromSeed = isObject(baseline)
    && baseline.sha256 !== prep.seededTargetSha256;
  const archiveValid = archive === null || (isObject(archive)
    && Number.isInteger(archive.lineNumber)
    && Number.isInteger(startLogTotal)
    && Number.isInteger(archiveEvidenceFloorLine)
    && Number.isInteger(baselineSnapshotLine)
    && archive.lineNumber > archiveEvidenceFloorLine
    && archive.lineNumber <= baselineSnapshotLine
    && Number.isSafeInteger(archive.archiveChars)
    && archive.archiveChars === baseline.textChars
    && bounded(archive.targetPath, 2048)
    && samePath(archive.targetPath, expectedTargetPath));
  if (!isObject(prep)
      || prep.targetSlot !== SLOT
      || prep.seedSlot !== report.seedSlot
      || prep.wroteSeed !== true
      || String(prep.targetJson || "").replace(/\\/g, "/") !== expectedRelative
      || !HASH.test(prep.seedSha256 || "")
      || !HASH.test(prep.seededTargetSha256 || "")
      || !HASH.test(prep.targetSha256 || "")
      || prep.targetSha256 !== prep.seededTargetSha256
      || prep.semanticContract !== "startup_normalization.v1"
      || !HASH.test(prep.semanticSha256 || "")
      || !isObject(baseline)
      || !HASH.test(baseline.sha256 || "")
      || !Number.isInteger(baseline.utf8Bytes) || baseline.utf8Bytes <= 0
      || baseline.utf8Bytes > 64 * 1024 * 1024
      || !Number.isInteger(baseline.textChars) || baseline.textChars <= 0
      || baseline.textChars > baseline.utf8Bytes
      || !BIGINT_DECIMAL.test(baseline.deviceId || "")
      || !BIGINT_DECIMAL.test(baseline.fileId || "")
      || !BIGINT_DECIMAL.test(baseline.mtimeNs || "")
      || lastWriteFromNs !== baseline.lastWriteTimeUtc
      || baseline.semanticContract !== prep.semanticContract
      || baseline.semanticSha256 !== prep.semanticSha256
      || String(baseline.role) !== String(prep.role)
      || String(baseline.level) !== String(prep.level)
      || !Number.isInteger(baseline.stableWindowMs)
      || baseline.stableWindowMs < 1000 || baseline.stableWindowMs > 10000
      || !Number.isInteger(baseline.stableSampleCount)
      || baseline.stableSampleCount < 2
      || baseline.regularFileVerified !== true
      || baseline.realPathBound !== true
      || !bounded(baseline.lastSaved, 80)
      || !Number.isFinite(stableStartedAt) || !Number.isFinite(capturedAt)
      || !Number.isFinite(lastWriteAt) || !Number.isFinite(postCaptureAt)
      || snapshotPhases.length !== 1 || baselinePhases.length !== 1
      || finalIdentityPhases.length !== 1
      || !Number.isFinite(snapshotAt) || !Number.isFinite(finalIdentityAt)
      || !Number.isFinite(finishedAt)
      || lastWriteAt > stableStartedAt
      || stableStartedAt < snapshotAt
      || capturedAt - stableStartedAt < baseline.stableWindowMs
      || postCaptureAt < capturedAt || finalIdentityAt < postCaptureAt
      || finalIdentityAt > finishedAt
      || !isObject(report.startLogWatermark)
      || !Number.isInteger(report.startLogWatermark.total)
      || !Number.isInteger(archiveEvidenceFloorLine)
      || handoffLine <= startLogTotal || titleFrameLine <= handoffLine
      || baseline.archiveEvidenceFloorLine !== archiveEvidenceFloorLine
      || !isObject(postCapture) || !Number.isInteger(postCapture.total)
      || !isObject(reportSnapshot) || !isObject(baselineSnapshot)
      || postCapture.total < baselineSnapshot.lineNumber
      || baseline.attemptId !== (report.runtime && report.runtime.expectedAttemptId)
      || baselineSnapshot.panelInstanceId !== reportSnapshot.panelInstanceId
      || baselineSnapshot.viewSessionId !== reportSnapshot.viewSessionId
      || baselineSnapshot.callId !== reportSnapshot.callId
      || baselineSnapshot.sourceKey !== reportSnapshot.sourceKey
      || baselineSnapshot.stateRef !== reportSnapshot.stateRef
      || baselineSnapshot.lineNumber !== reportSnapshot.lineNumber
      || !isToken(baselineSnapshot.panelInstanceId)
      || !isToken(baselineSnapshot.viewSessionId)
      || !isToken(baselineSnapshot.callId)
      || !bounded(baselineSnapshot.sourceKey, 1024)
      || !STATE_REF.test(baselineSnapshot.stateRef || "")
      || !Number.isInteger(baselineSnapshot.lineNumber)
      || !archiveValid || (changedFromSeed && !isObject(archive))
      || baseline.changedFromSeed !== changedFromSeed
      || baselinePhase.at !== baseline.capturedAt
      || baselinePhase.sha256 !== baseline.sha256
      || baselinePhase.utf8Bytes !== baseline.utf8Bytes
      || baselinePhase.textChars !== baseline.textChars
      || baselinePhase.deviceId !== baseline.deviceId
      || baselinePhase.fileId !== baseline.fileId
      || baselinePhase.mtimeNs !== baseline.mtimeNs
      || baselinePhase.semanticContract !== baseline.semanticContract
      || baselinePhase.semanticSha256 !== baseline.semanticSha256
      || baselinePhase.stableWindowMs !== baseline.stableWindowMs
      || baselinePhase.stableSampleCount !== baseline.stableSampleCount
      || baselinePhase.changedFromSeed !== changedFromSeed
      || baselinePhase.startupArchiveLine !== (archive ? archive.lineNumber : null)
      || baselinePhase.archiveEvidenceFloorLine !== archiveEvidenceFloorLine
      || baselinePhase.postCaptureLogTotal !== postCapture.total) {
    fail(
      "clone_preparation_invalid",
      "clone_baseline",
      "the opener report does not bind a stable post-snapshot clone baseline"
    );
  }
  return { prep, baseline, expectedRelative };
}

function assertCloneSemanticContract(data, preparation, phase) {
  const player = data && data["0"];
  if (opener.cloneSemanticSha256(data) !== preparation.semanticSha256
      || !Array.isArray(player)
      || String(player[0]) !== String(preparation.role)
      || String(player[3]) !== String(preparation.level)) {
    fail(
      "clone_semantic_mismatch",
      phase,
      "current clone bytes do not satisfy the signed startup normalization contract"
    );
  }
  return true;
}

function validateCloneTarget(report, anchor) {
  if (!isObject(report) || report.slot !== SLOT || report.seedSlot === SLOT) {
    fail(
      "clone_slot_mismatch",
      "clone_baseline",
      "the commit gate only accepts the opener-owned " + SLOT + " clone"
    );
  }
  const contract = validateClonePreparationContract(report);
  const prep = contract.prep;
  const baseline = contract.baseline;
  const expectedRelative = contract.expectedRelative;
  const targetPath = path.resolve(root, prep.targetJson);
  const savesRoot = path.resolve(root, "saves");
  if (!samePath(path.dirname(targetPath), savesRoot)
      || path.basename(targetPath).toLowerCase() !== (SLOT + ".json").toLowerCase()) {
    fail("clone_path_escape", "clone_baseline", "clone path escaped the saves directory");
  }
  opener.assertCanonicalDirectoryChain(root, savesRoot, "clone_baseline");
  const fileSnapshot = readCloneSnapshot(targetPath, false, "clone_baseline");
  const raw = fileSnapshot.raw;
  const actualHash = sha256(raw);
  if (actualHash.toLowerCase() !== String(baseline.sha256).toLowerCase()) {
    fail(
      "clone_changed_before_gate",
      "clone_baseline",
      "the clone changed after the opener; rerun the opener before signing a commit journey",
      { expectedSha256: baseline.sha256, actualSha256: actualHash }
    );
  }
  const stat = fileSnapshot.stat;
  const lastWriteTimeUtc = new Date(Number(stat.mtimeNs / 1000000n)).toISOString();
  if (Number(stat.size) !== baseline.utf8Bytes
      || String(stat.dev) !== baseline.deviceId
      || String(stat.ino) !== baseline.fileId
      || String(stat.mtimeNs) !== baseline.mtimeNs
      || lastWriteTimeUtc !== baseline.lastWriteTimeUtc) {
    fail(
      "clone_changed_before_gate",
      "clone_baseline",
      "the clone metadata changed after the opener; rerun the opener before signing a commit journey",
      {
        expectedLength: baseline.utf8Bytes,
        actualLength: Number(stat.size),
        expectedLastWriteTimeUtc: baseline.lastWriteTimeUtc,
        actualLastWriteTimeUtc: lastWriteTimeUtc,
        expectedDeviceId: baseline.deviceId,
        actualDeviceId: String(stat.dev),
        expectedFileId: baseline.fileId,
        actualFileId: String(stat.ino),
        expectedMtimeNs: baseline.mtimeNs,
        actualMtimeNs: String(stat.mtimeNs),
      }
    );
  }
  let data;
  try {
    data = JSON.parse(raw.toString("utf8"));
  } catch (error) {
    fail("clone_json_invalid", "clone_baseline", error.message);
  }
  if (!isObject(data) || !isObject(data.inventory) || !data.inventory["背包"]) {
    fail("clone_schema_invalid", "clone_baseline", "clone lacks inventory.背包");
  }
  assertCloneSemanticContract(data, prep, "clone_baseline");
  if (String(data.lastSaved || "") !== baseline.lastSaved) {
    fail(
      "clone_changed_before_gate",
      "clone_baseline",
      "the clone lastSaved value changed after the opener"
    );
  }
  return {
    path: targetPath,
    relativePath: expectedRelative,
    sha256: actualHash,
    utf8Bytes: baseline.utf8Bytes,
    deviceId: baseline.deviceId,
    fileId: baseline.fileId,
    mtimeNs: baseline.mtimeNs,
    lastWriteTimeUtc: baseline.lastWriteTimeUtc,
    data,
    lastSaved: data.lastSaved,
    gateBaseline: baseline,
    seedSha256: prep.seedSha256,
    seededTargetSha256: prep.seededTargetSha256,
    openerPid: anchor.pid,
  };
}

function assertCloneMatchesBaseline(baseline, phase) {
  opener.assertCanonicalDirectoryChain(root, path.dirname(baseline.path), phase);
  const snapshot = readCloneSnapshot(baseline.path, false, phase);
  const actualHash = sha256(snapshot.raw);
  const actualLastWrite = new Date(
    Number(snapshot.stat.mtimeNs / 1000000n)
  ).toISOString();
  if (actualHash !== baseline.sha256
      || Number(snapshot.stat.size) !== baseline.utf8Bytes
      || String(snapshot.stat.dev) !== baseline.deviceId
      || String(snapshot.stat.ino) !== baseline.fileId
      || String(snapshot.stat.mtimeNs) !== baseline.mtimeNs
      || actualLastWrite !== baseline.lastWriteTimeUtc) {
    fail(
      "clone_changed_during_gate",
      phase,
      "the clone drifted after its post-snapshot baseline",
      {
        expectedSha256: baseline.sha256,
        actualSha256: actualHash,
        expectedLength: baseline.utf8Bytes,
        actualLength: Number(snapshot.stat.size),
        expectedLastWriteTimeUtc: baseline.lastWriteTimeUtc,
        actualLastWriteTimeUtc: actualLastWrite,
      }
    );
  }
  let data;
  try {
    data = JSON.parse(snapshot.raw.toString("utf8"));
  } catch (error) {
    fail("clone_json_invalid", phase, error.message);
  }
  if (String(data.lastSaved || "") !== String(baseline.lastSaved || "")) {
    fail("clone_changed_during_gate", phase, "clone lastSaved drifted during the gate");
  }
  return true;
}

function validateGateLogHistory(report, anchor, baseline, snapshot) {
  const interactionWatermark = opener.establishInteractionLogWatermark(
    anchor.snapshotLineNumber,
    snapshot
  );
  const gateBaseline = baseline.gateBaseline;
  if (snapshot.total < gateBaseline.postCaptureLogWatermark.total) {
    fail(
      "clone_gate_log_reset",
      "interaction_watermark",
      "Launcher log no longer contains the opener post-capture watermark"
    );
  }
  const records = opener.freshLogRecords(report.startLogWatermark, snapshot);
  const expectedArchive = gateBaseline.startupArchiveReceipt;
  if (expectedArchive) {
    const record = records.find((entry) => entry.lineNumber === expectedArchive.lineNumber);
    const parsed = opener.parseStartupArchiveReceipt(record, SLOT, baseline.path);
    if (!parsed || parsed.archiveChars !== expectedArchive.archiveChars) {
      fail(
        "startup_archive_receipt_mismatch",
        "interaction_watermark",
        "the startup archive receipt no longer matches the signed clone baseline"
      );
    }
  }
  return interactionWatermark;
}

function runtimeExpected(anchor) {
  return {
    runtimeMode: anchor.runtimeIdentity.runtimeMode,
    processPath: anchor.runtimeIdentity.processPath,
    coreSha256: anchor.runtimeIdentity.coreSha256,
    buildIdentity: anchor.runtimeIdentity.buildIdentity,
    payloadClosure: anchor.runtimeIdentity.payloadClosure,
  };
}

function assertIdentityFields(expected, actual, phase) {
  try {
    assertRuntimeIdentity(expected, actual);
  } catch (error) {
    fail(
      "runtime_identity_drift",
      phase,
      "runtime identity drifted: " + error.message,
      error.details || null
    );
  }
  return true;
}

function verifyLiveIdentity(anchor, expectedPid, expectedPort, phase) {
  let context;
  try {
    context = LegacyHttpClient.readExactLauncherHttpContext(root);
  } catch (error) {
    fail("launcher_context_unavailable", phase, error.message);
  }
  if (context.pid !== expectedPid || context.httpPort !== expectedPort) {
    fail(
      "runtime_process_changed",
      phase,
      "Launcher PID/HTTP port changed",
      {
        expectedPid,
        actualPid: context.pid,
        expectedHttpPort: expectedPort,
        actualHttpPort: context.httpPort,
      }
    );
  }
  let actual;
  try {
    actual = verifyRuntimeIdentity(root, expectedPort, runtimeExpected(anchor));
  } catch (error) {
    fail(
      "runtime_identity_drift",
      phase,
      "full runtime identity verification failed: " + error.message,
      error.details || null
    );
  }
  if (actual.pid !== expectedPid || actual.httpPort !== expectedPort) {
    fail("runtime_process_changed", phase, "identity probe observed a different process");
  }
  opener.assertExclusiveLauncherProcess(
    opener.queryLauncherCoreProcesses(),
    actual.pid
  );
  return { context, identity: publicRuntimeIdentity(actual) };
}

function httpRequest(context, method, pathname, timeoutMs) {
  return new Promise((resolve, reject) => {
    let headers;
    try {
      headers = LegacyHttpClient.authorizationHeadersFor(context, pathname);
    } catch (error) {
      reject(error);
      return;
    }
    const request = http.request({
      hostname: "localhost",
      port: context.httpPort,
      method,
      path: pathname,
      headers,
      timeout: timeoutMs,
    }, (response) => {
      let text = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => { text += chunk; });
      response.on("end", () => resolve({ statusCode: response.statusCode, text }));
    });
    request.on("timeout", () => request.destroy(new Error(pathname + " timed out")));
    request.on("error", reject);
    request.end();
  });
}

async function requestLogs(context) {
  const response = await httpRequest(context, "GET", "/logs?lines=2000", 5000);
  let parsed;
  try {
    parsed = JSON.parse(response.text);
  } catch (_error) {
    fail("logs_invalid_json", "logs", "/logs returned invalid JSON");
  }
  if (response.statusCode !== 200 || parsed.success !== true
      || !Number.isInteger(parsed.total) || !Array.isArray(parsed.lines)) {
    fail("logs_unavailable", "logs", "/logs did not return a usable snapshot", parsed);
  }
  return {
    total: parsed.total,
    lines: parsed.lines.map((line) => String(line)),
    capturedAt: new Date().toISOString(),
  };
}

function decodeField(value) {
  if (value === null || value === undefined || value === "-") return "";
  try {
    return decodeURIComponent(String(value));
  } catch (_error) {
    return null;
  }
}

function hostBody(record) {
  if (!record || typeof record.line !== "string" || record.line.includes("[WebDebug]")) {
    return null;
  }
  return record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
}

function booleanLogField(record, name) {
  const value = hostField(record, name);
  if (value === "true") return true;
  if (value === "false") return false;
  return null;
}

function parseRedactedWebDebug(record, text) {
  if (!text.startsWith("scope=equipment_tuning ")) return null;
  const event = decodeField(opener.extractLogField(text, "event"));
  if (!WEB_EVENTS.has(event)) return null;
  const callId = decodeField(opener.extractLogField(text, "callId"));
  const sourceKey = decodeField(
    opener.extractLogField(text, "sourceKeyRef")
      || opener.extractLogField(text, "sourceKey")
  );
  const intentKey = decodeField(
    opener.extractLogField(text, "intentKeyRef")
      || opener.extractLogField(text, "intentKey")
  );
  const tokenPresent = booleanLogField(record, "tokenPresent");
  const transactionIdPresent = booleanLogField(record, "transactionIdPresent");
  const requiresReconcile = booleanLogField(record, "requiresReconcile");
  const callRequired = event !== "candidate_hit";
  const intentRequired = event !== "candidate_hit";
  if (!STATE_REF.test(sourceKey || "")
      || (callRequired && !isToken(callId))
      || (intentRequired && !STATE_REF.test(intentKey || ""))
      || tokenPresent === null
      || (event === "commit_adopted"
        && (transactionIdPresent === null || requiresReconcile === null))) {
    return { invalid: "malformed_" + event, lineNumber: record.lineNumber };
  }
  return {
    kind: "web",
    redactedDiagnostic: true,
    event,
    lineNumber: record.lineNumber,
    sequence: null,
    webCallId: callRequired ? callId : "",
    panelInstanceId: "",
    viewSessionId: "",
    sourceKey,
    candidateKey: "",
    intentKey: intentRequired ? intentKey : "",
    operation: "",
    tokenPresent,
    transactionIdPresent,
    requiresReconcile,
  };
}

function parseWeb(record) {
  if (!record || typeof record.line !== "string") return null;
  const marker = "[WebDebug] ";
  const index = record.line.indexOf(marker);
  if (index < 0) return null;
  const text = record.line.slice(index + marker.length).trim();
  let message;
  try {
    message = JSON.parse(text);
  } catch (_error) {
    const redacted = parseRedactedWebDebug(record, text);
    if (redacted) return redacted;
    if (text.includes("equipment_tuning")) return {
      invalid: "malformed_equipment_tuning_debug",
      lineNumber: record.lineNumber,
    };
    return null;
  }
  if (!isObject(message) || message.scope !== "equipment_tuning"
      || !WEB_EVENTS.has(message.event)) return null;
  const event = String(message.event);
  const callRequired = event !== "candidate_hit";
  const reconcile = event === "reconcile_issued" || event === "reconcile_adopted";
  const candidateRequired = !reconcile && event !== "inventory_refresh_settled"
    || event === "inventory_refresh_settled";
  if (message.type !== "debug"
      || !isToken(message.panelInstanceId)
      || !isToken(message.viewSessionId)
      || (callRequired && !isToken(message.webCallId))
      || (!callRequired && message.webCallId && !isToken(message.webCallId))
      || !bounded(message.sourceKey, 180)
      || !/^[a-z_]{1,40}$/.test(message.operation || "")
      || (candidateRequired && !bounded(message.candidateKey, 180))
      || (!reconcile && event !== "candidate_hit" && !bounded(message.intentKey, 384))
      || !Number.isInteger(message.pendingCount) || message.pendingCount < 0
      || typeof message.tokenPresent !== "boolean"
      || typeof message.commitReady !== "boolean"
      || !/^(safe|fast)$/.test(message.confirmationMode || "")
      || typeof message.autoCommitPending !== "boolean"
      || !/^(idle|read_pending|write_pending|reconcile_required|refresh_pending|refresh_required)$/.test(
        message.writeState || ""
      )
      || typeof message.needsReconcile !== "boolean"
      || (reconcile && !isToken(message.reconcileAfterCallId))) {
    return { invalid: "malformed_" + event, lineNumber: record.lineNumber };
  }
  return {
    kind: "web",
    event,
    lineNumber: record.lineNumber,
    sequence: Number.isInteger(message.sequence) ? message.sequence : null,
    webCallId: message.webCallId || "",
    panelInstanceId: message.panelInstanceId,
    viewSessionId: message.viewSessionId,
    sourceKey: message.sourceKey,
    candidateKey: message.candidateKey || "",
    intentKey: message.intentKey || "",
    operation: message.operation,
    pendingCount: message.pendingCount,
    tokenPresent: message.tokenPresent,
    commitReady: message.commitReady,
    confirmationMode: message.confirmationMode,
    autoCommitPending: message.autoCommitPending,
    writeState: message.writeState,
    needsReconcile: message.needsReconcile,
    success: message.success,
    transactionIdPresent: message.transactionIdPresent,
    requiresReconcile: message.requiresReconcile,
    currentLeasePresent: message.currentLeasePresent,
    reconciled: message.reconciled,
    noOp: message.noOp,
    reconcileAfterCallId: message.reconcileAfterCallId || "",
  };
}

function parseHostPreviewRequest(record) {
  const body = hostBody(record);
  const marker = "[EquipmentTuningTask] -> Flash: ";
  if (!body || !body.startsWith(marker)) return null;
  const text = body.slice(marker.length);
  let message;
  try {
    message = JSON.parse(text);
  } catch (_error) {
    if (text.includes("equipmentTuningPreview")) {
      return { invalid: "malformed_host_preview_request", lineNumber: record.lineNumber };
    }
    return null;
  }
  if (!isObject(message) || message.action !== "equipmentTuningPreview") return null;
  const source = message.source;
  const result = {
    kind: "host_preview_request",
    lineNumber: record.lineNumber,
    flashCallId: Number(message.callId),
    webCallId: message.requestCallId,
    panelInstanceId: message.panelInstanceId,
    viewSessionId: message.viewSessionId,
    operation: message.operation,
    candidateKey: message.candidateKey,
    source: isObject(source) ? {
      sourceKind: source.sourceKind,
      containerId: source.containerId,
      slot: Number(source.slot),
      expectedLeaseRef: source.expectedLeaseRef || "",
    } : null,
  };
  if (!Number.isInteger(result.flashCallId) || result.flashCallId <= 0
      || !isToken(result.webCallId)
      || !isToken(result.panelInstanceId) || !isToken(result.viewSessionId)
      || !/^[a-z_]{1,40}$/.test(result.operation || "")
      || !bounded(result.candidateKey, 180)
      || !result.source || result.source.sourceKind !== "inventory"
      || !bounded(result.source.containerId, 80)
      || !Number.isInteger(result.source.slot) || result.source.slot < 0
      || !STATE_REF.test(result.source.expectedLeaseRef || "")) {
    return { invalid: "malformed_host_preview_request", lineNumber: record.lineNumber };
  }
  return result;
}

function parseHostCommitRequest(record) {
  const body = hostBody(record);
  const marker = "[EquipmentTuningTask] -> Flash: ";
  if (!body || !body.startsWith(marker)) return null;
  const text = body.slice(marker.length);
  let message;
  try {
    message = JSON.parse(text);
  } catch (_error) {
    if (text.includes("equipmentTuningCommit")) {
      return { invalid: "malformed_host_commit_request", lineNumber: record.lineNumber };
    }
    return null;
  }
  if (!isObject(message) || message.action !== "equipmentTuningCommit") return null;
  const result = {
    kind: "host_commit_request",
    lineNumber: record.lineNumber,
    flashCallId: Number(message.callId),
    webCallId: message.requestCallId,
    panelInstanceId: message.panelInstanceId,
    viewSessionId: message.viewSessionId,
    expectedTuningTokenRef: message.expectedTuningTokenRef,
    writeEpoch: Number(message.writeEpoch),
  };
  if (!Number.isInteger(result.flashCallId) || result.flashCallId <= 0
      || !isToken(result.webCallId)
      || !isToken(result.panelInstanceId) || !isToken(result.viewSessionId)
      || !STATE_REF.test(result.expectedTuningTokenRef || "")
      || !Number.isInteger(result.writeEpoch) || result.writeEpoch <= 0) {
    return { invalid: "malformed_host_commit_request", lineNumber: record.lineNumber };
  }
  return result;
}

function parseHostSnapshotRequest(record) {
  const body = hostBody(record);
  const marker = "[EquipmentTuningTask] -> Flash: ";
  if (!body || !body.startsWith(marker)) return null;
  const text = body.slice(marker.length);
  let message;
  try {
    message = JSON.parse(text);
  } catch (_error) {
    if (text.includes("equipmentTuningSnapshot")) {
      return { invalid: "malformed_host_snapshot_request", lineNumber: record.lineNumber };
    }
    return null;
  }
  if (!isObject(message) || message.action !== "equipmentTuningSnapshot") return null;
  const source = message.source;
  const result = {
    kind: "host_snapshot_request",
    lineNumber: record.lineNumber,
    flashCallId: Number(message.callId),
    webCallId: message.requestCallId,
    panelInstanceId: message.panelInstanceId,
    viewSessionId: message.viewSessionId,
    writeEpoch: Number(message.writeEpoch),
    source: isObject(source) ? {
      sourceKind: source.sourceKind,
      containerId: source.containerId,
      slot: Number(source.slot),
      expectedLeaseRef: source.expectedLeaseRef || "",
    } : null,
  };
  if (!Number.isInteger(result.flashCallId) || result.flashCallId <= 0
      || !isToken(result.webCallId)
      || !isToken(result.panelInstanceId) || !isToken(result.viewSessionId)
      || !Number.isInteger(result.writeEpoch) || result.writeEpoch < 0
      || !result.source || result.source.sourceKind !== "inventory"
      || !bounded(result.source.containerId, 80)
      || !Number.isInteger(result.source.slot) || result.source.slot < 0
      || !STATE_REF.test(result.source.expectedLeaseRef || "")) {
    return { invalid: "malformed_host_snapshot_request", lineNumber: record.lineNumber };
  }
  return result;
}

function hostField(record, name) {
  return decodeField(opener.extractLogField(record.line, name));
}

function parseHostPreview(record) {
  const body = hostBody(record);
  if (!body || !body.startsWith("event=equipment_tuning_preview_settled ")) return null;
  const result = {
    kind: "host_preview",
    lineNumber: record.lineNumber,
    webCallId: hostField(record, "webCallId"),
    requestCallId: hostField(record, "requestCallId"),
    flashCallId: Number(hostField(record, "flashCallId")),
    tokenRef: hostField(record, "tokenRef"),
    panelInstanceId: hostField(record, "panelInstanceId"),
    viewSessionId: hostField(record, "viewSessionId"),
    sourceKey: hostField(record, "sourceKey") || hostField(record, "sourceKeyRef"),
    operation: hostField(record, "operation"),
    candidateKey: hostField(record, "candidateKey"),
    intentKey: hostField(record, "intentKey") || hostField(record, "intentKeyRef"),
    outcome: hostField(record, "outcome"),
    remainingPending: Number(hostField(record, "remainingPending")),
  };
  if (!isToken(result.webCallId) || result.requestCallId !== result.webCallId
      || !Number.isInteger(result.flashCallId) || result.flashCallId <= 0
      || !STATE_REF.test(result.tokenRef || "")
      || !isToken(result.panelInstanceId) || !isToken(result.viewSessionId)
      || !bounded(result.sourceKey, 180) || !bounded(result.candidateKey, 180)
      || !/^[a-z_]{1,40}$/.test(result.operation || "")
      || !bounded(result.intentKey, 384) || !bounded(result.outcome, 200)
      || !Number.isInteger(result.remainingPending) || result.remainingPending < 0) {
    return { invalid: "malformed_host_preview_settled", lineNumber: record.lineNumber };
  }
  return result;
}

function parseHostCommit(record) {
  const body = hostBody(record);
  if (!body || !body.startsWith("event=equipment_tuning_commit_settled ")) return null;
  const result = {
    kind: "host_commit",
    lineNumber: record.lineNumber,
    webCallId: hostField(record, "webCallId"),
    requestCallId: hostField(record, "requestCallId"),
    previewWebCallId: hostField(record, "previewWebCallId"),
    flashCallId: Number(hostField(record, "flashCallId")),
    tokenRef: hostField(record, "tokenRef"),
    panelInstanceId: hostField(record, "panelInstanceId"),
    viewSessionId: hostField(record, "viewSessionId"),
    sourceKey: hostField(record, "sourceKey") || hostField(record, "sourceKeyRef"),
    operation: hostField(record, "operation"),
    candidateKey: hostField(record, "candidateKey"),
    intentKey: hostField(record, "intentKey") || hostField(record, "intentKeyRef"),
    outcome: hostField(record, "outcome"),
    writeEpoch: Number(hostField(record, "writeEpoch")),
    writeState: hostField(record, "writeState"),
    remainingPending: Number(hostField(record, "remainingPending")),
    stateRef: hostField(record, "stateRef"),
    snapshotPresent: hostField(record, "snapshotPresent"),
    transactionIdPresent: hostField(record, "transactionIdPresent"),
  };
  const stateRefShapeValid = STATE_REF.test(result.stateRef || "")
    || (result.outcome !== "success" && result.stateRef === "");
  if (!isToken(result.webCallId) || result.requestCallId !== result.webCallId
      || !isToken(result.previewWebCallId)
      || !Number.isInteger(result.flashCallId) || result.flashCallId <= 0
      || !STATE_REF.test(result.tokenRef || "") || !stateRefShapeValid
      || !isToken(result.panelInstanceId) || !isToken(result.viewSessionId)
      || !bounded(result.sourceKey, 180) || !bounded(result.candidateKey, 180)
      || !/^[a-z_]{1,40}$/.test(result.operation || "")
      || !bounded(result.intentKey, 384) || !bounded(result.outcome, 200)
      || !Number.isInteger(result.writeEpoch) || result.writeEpoch <= 0
      || !/^(idle|needs_reconcile)$/.test(result.writeState || "")
      || !Number.isInteger(result.remainingPending) || result.remainingPending < 0
      || !/^(true|false)$/.test(result.snapshotPresent || "")
      || !/^(true|false)$/.test(result.transactionIdPresent || "")) {
    return { invalid: "malformed_host_commit_settled", lineNumber: record.lineNumber };
  }
  return result;
}

function parseHostSnapshot(record) {
  const body = hostBody(record);
  if (!body || !body.startsWith("event=equipment_tuning_snapshot_confirmed ")) return null;
  const result = {
    kind: "host_snapshot",
    lineNumber: record.lineNumber,
    callId: hostField(record, "callId"),
    panelInstanceId: hostField(record, "panelInstanceId"),
    viewSessionId: hostField(record, "viewSessionId"),
    sourceKey: hostField(record, "sourceKey") || hostField(record, "sourceKeyRef"),
    stateRef: hostField(record, "stateRef"),
    writeEpoch: Number(hostField(record, "writeEpoch")),
  };
  if (!isToken(result.callId) || !isToken(result.panelInstanceId)
      || !isToken(result.viewSessionId) || !bounded(result.sourceKey, 180)
      || !STATE_REF.test(result.stateRef || "")
      || !Number.isInteger(result.writeEpoch) || result.writeEpoch < 0) {
    return { invalid: "malformed_host_snapshot_confirmed", lineNumber: record.lineNumber };
  }
  return result;
}

function parseInventorySourceKey(value) {
  const match = String(value || "").match(/^inventory:([^:]{1,80}):(\d{1,6}):(.{1,160})$/);
  if (!match) return null;
  const slot = Number(match[2]);
  if (!Number.isInteger(slot) || slot < 0 || slot > 999999) return null;
  return { sourceKind: "inventory", containerId: match[1], slot, lease: match[3] };
}

function sameStableSource(left, right) {
  const a = parseInventorySourceKey(left);
  const b = parseInventorySourceKey(right);
  return !!a && !!b && a.containerId === b.containerId && a.slot === b.slot;
}

function incomplete(code, observed) {
  return { ok: false, fatal: false, code, observed: observed || null };
}

function fatal(code, observed) {
  return { ok: false, fatal: true, code, observed: observed || null };
}

function verifyRedactedCommitEvidence(events, anchor) {
  function next(predicate, afterLine) {
    return events.find((event) => event.lineNumber > afterLine && predicate(event)) || null;
  }
  const candidate = next((event) => event.kind === "web"
    && event.redactedDiagnostic && event.event === "candidate_hit",
  anchor.snapshotLineNumber);
  if (!candidate) return incomplete("candidate_hit_missing");
  const previewIssued = next((event) => event.kind === "web"
    && event.redactedDiagnostic && event.event === "preview_issued", candidate.lineNumber);
  if (!previewIssued) return incomplete("preview_issued_missing", candidate);
  const previewRequest = next((event) => event.kind === "host_preview_request",
    previewIssued.lineNumber);
  if (!previewRequest) return incomplete("host_preview_request_missing", previewIssued);
  const hostPreview = next((event) => event.kind === "host_preview",
    previewRequest.lineNumber);
  if (!hostPreview) return incomplete("host_preview_settled_missing", previewRequest);
  const previewAdopted = next((event) => event.kind === "web"
    && event.redactedDiagnostic && event.event === "preview_adopted", hostPreview.lineNumber);
  if (!previewAdopted) return incomplete("preview_adopted_missing", hostPreview);
  const commitIssued = next((event) => event.kind === "web"
    && event.redactedDiagnostic && event.event === "commit_issued", previewAdopted.lineNumber);
  if (!commitIssued) return incomplete("commit_issued_missing", previewAdopted);
  const commitRequest = next((event) => event.kind === "host_commit_request",
    commitIssued.lineNumber);
  if (!commitRequest) return incomplete("host_commit_request_missing", commitIssued);
  const hostCommit = next((event) => event.kind === "host_commit", commitRequest.lineNumber);
  if (!hostCommit) return incomplete("host_commit_settled_missing", commitRequest);
  const commitAdopted = next((event) => event.kind === "web"
    && event.redactedDiagnostic && event.event === "commit_adopted", hostCommit.lineNumber);
  if (!commitAdopted) return incomplete("commit_adopted_missing", hostCommit);
  const refresh = next((event) => event.kind === "web"
    && event.redactedDiagnostic && event.event === "inventory_refresh_settled",
  commitAdopted.lineNumber);
  if (!refresh) return incomplete("inventory_refresh_settled_missing", commitAdopted);

  const source = previewRequest.source;
  if (!source || source.containerId !== "背包") {
    return fatal("clone_inventory_source_required", previewRequest);
  }
  const sourceTuple = [candidate, previewIssued, hostPreview, previewAdopted,
    commitIssued, hostCommit, commitAdopted];
  if (sourceTuple.some((event) => event.sourceKey !== candidate.sourceKey)
      || refresh.sourceKey === candidate.sourceKey) {
    return fatal("authority_tuple_mismatch", sourceTuple.concat([refresh]));
  }
  const intent = previewIssued.intentKey;
  const intentTuple = [hostPreview, previewAdopted, commitIssued, hostCommit,
    commitAdopted, refresh];
  if (!intent || intentTuple.some((event) => event.intentKey !== intent)) {
    return fatal("intent_tuple_mismatch", [previewIssued].concat(intentTuple));
  }
  if (previewRequest.webCallId !== previewIssued.webCallId
      || previewRequest.flashCallId !== hostPreview.flashCallId
      || previewRequest.operation !== hostPreview.operation
      || previewRequest.operation !== hostCommit.operation
      || previewRequest.candidateKey !== hostPreview.candidateKey
      || previewRequest.candidateKey !== hostCommit.candidateKey
      || hostPreview.webCallId !== previewIssued.webCallId
      || previewAdopted.webCallId !== previewIssued.webCallId
      || hostPreview.outcome !== "success" || hostPreview.remainingPending !== 0
      || previewIssued.tokenPresent !== false || previewAdopted.tokenPresent !== true) {
    return fatal("preview_contract_mismatch", {
      previewIssued, previewRequest, hostPreview, previewAdopted,
    });
  }
  if (commitIssued.webCallId === previewIssued.webCallId
      || commitRequest.webCallId !== commitIssued.webCallId
      || commitRequest.flashCallId !== hostCommit.flashCallId
      || commitRequest.expectedTuningTokenRef !== hostPreview.tokenRef
      || commitRequest.writeEpoch !== hostCommit.writeEpoch
      || hostCommit.webCallId !== commitIssued.webCallId
      || commitAdopted.webCallId !== commitIssued.webCallId
      || refresh.webCallId !== commitIssued.webCallId
      || hostCommit.previewWebCallId !== previewIssued.webCallId
      || hostCommit.tokenRef !== hostPreview.tokenRef) {
    return fatal("commit_call_chain_mismatch", {
      previewIssued, hostPreview, commitIssued, commitRequest, hostCommit,
      commitAdopted, refresh,
    });
  }
  if (commitIssued.tokenPresent !== true
      || hostCommit.outcome !== "success" || hostCommit.writeState !== "idle"
      || hostCommit.remainingPending !== 0 || hostCommit.snapshotPresent !== "true"
      || hostCommit.transactionIdPresent !== "true"
      || commitAdopted.tokenPresent !== true
      || commitAdopted.transactionIdPresent !== true
      || commitAdopted.requiresReconcile !== false
      || refresh.tokenPresent !== false) {
    return fatal("commit_contract_mismatch", {
      commitIssued, hostCommit, commitAdopted, refresh,
    });
  }
  return {
    ok: true,
    fatal: false,
    source,
    exactTuple: {
      panelInstanceId: anchor.panelInstanceId,
      viewSessionId: anchor.viewSessionId,
      sourceKeyBefore: candidate.sourceKey,
      sourceKeyAfterRefresh: refresh.sourceKey,
      operation: hostPreview.operation,
      candidateKey: hostPreview.candidateKey,
      intentKey: intent,
      previewWebCallId: previewIssued.webCallId,
      commitWebCallId: commitIssued.webCallId,
      tokenRef: hostPreview.tokenRef,
      stateRef: hostCommit.stateRef,
      writeEpoch: hostCommit.writeEpoch,
    },
    evidence: {
      candidateHitLine: candidate.lineNumber,
      previewIssuedLine: previewIssued.lineNumber,
      hostPreviewRequestLine: previewRequest.lineNumber,
      hostPreviewSettledLine: hostPreview.lineNumber,
      previewAdoptedLine: previewAdopted.lineNumber,
      commitIssuedLine: commitIssued.lineNumber,
      hostCommitRequestLine: commitRequest.lineNumber,
      hostCommitSettledLine: hostCommit.lineNumber,
      commitAdoptedLine: commitAdopted.lineNumber,
      inventoryRefreshSettledLine: refresh.lineNumber,
    },
    assertions: {
      twoActionCommitObserved: true,
      redactedDiagnosticProjection: true,
      exactPanelViewSourceCandidateIntent: true,
      previewTokenReferenceLinked: true,
      authoritativeTransactionObserved: true,
      authoritativeSnapshotStateRefObserved: true,
      refreshedSourceReferenceObserved: true,
      reconcileDisposition: "not_required",
      unknownWriteReconcileJourneyVerified: false,
    },
  };
}

function verifyCommitEvidence(records, anchor) {
  const events = [];
  for (const record of records) {
    const parsed = parseWeb(record) || parseHostPreviewRequest(record)
      || parseHostCommitRequest(record) || parseHostPreview(record)
      || parseHostCommit(record);
    if (!parsed) continue;
    if (parsed.invalid) return fatal(parsed.invalid, parsed);
    if (!(parsed.kind === "web" && parsed.redactedDiagnostic)
        && (parsed.panelInstanceId !== anchor.panelInstanceId
          || parsed.viewSessionId !== anchor.viewSessionId)) {
      return fatal("cross_session_tuning_event", parsed);
    }
    events.push(parsed);
  }
  const reconciles = events.filter((event) => event.kind === "web"
    && (event.event === "reconcile_issued" || event.event === "reconcile_adopted"));
  if (reconciles.length > 0) {
    return fatal("unexpected_reconcile_path", reconciles[0]);
  }
  if (events.some((event) => event.kind === "web" && event.redactedDiagnostic)) {
    return verifyRedactedCommitEvidence(events, anchor);
  }
  function next(predicate, afterLine) {
    return events.find((event) => event.lineNumber > afterLine && predicate(event)) || null;
  }
  const candidate = next((event) => event.kind === "web"
    && event.event === "candidate_hit", anchor.snapshotLineNumber);
  if (!candidate) return incomplete("candidate_hit_missing");
  const source = parseInventorySourceKey(candidate.sourceKey);
  if (!source || source.containerId !== "背包") {
    return fatal("clone_inventory_source_required", candidate);
  }
  if (candidate.confirmationMode !== "safe" || candidate.autoCommitPending
      || candidate.pendingCount !== 0 || candidate.needsReconcile
      || candidate.writeState !== "idle") {
    return fatal("candidate_not_safe_and_idle", candidate);
  }
  const previewIssued = next((event) => event.kind === "web"
    && event.event === "preview_issued", candidate.lineNumber);
  if (!previewIssued) return incomplete("preview_issued_missing", candidate);
  const hostPreview = next((event) => event.kind === "host_preview",
    previewIssued.lineNumber);
  if (!hostPreview) return incomplete("host_preview_settled_missing", previewIssued);
  const previewAdopted = next((event) => event.kind === "web"
    && event.event === "preview_adopted", hostPreview.lineNumber);
  if (!previewAdopted) return incomplete("preview_adopted_missing", hostPreview);
  const commitIssued = next((event) => event.kind === "web"
    && event.event === "commit_issued", previewAdopted.lineNumber);
  if (!commitIssued) return incomplete("commit_issued_missing", previewAdopted);
  const hostCommit = next((event) => event.kind === "host_commit",
    commitIssued.lineNumber);
  if (!hostCommit) return incomplete("host_commit_settled_missing", commitIssued);
  const commitAdopted = next((event) => event.kind === "web"
    && event.event === "commit_adopted", hostCommit.lineNumber);
  if (!commitAdopted) return incomplete("commit_adopted_missing", hostCommit);
  if (hostCommit.outcome !== "success") {
    return fatal("commit_outcome_not_success", { hostCommit, commitAdopted });
  }
  if (commitAdopted.success !== true) {
    return fatal("commit_adopted_not_success", { hostCommit, commitAdopted });
  }
  const refresh = next((event) => event.kind === "web"
    && event.event === "inventory_refresh_settled", commitAdopted.lineNumber);
  if (!refresh) return incomplete("inventory_refresh_settled_missing", commitAdopted);

  const webEvents = [candidate, previewIssued, previewAdopted, commitIssued,
    commitAdopted, refresh];
  if (webEvents.some((event) => !Number.isInteger(event.sequence))
      || webEvents.some((event, index) => index > 0
        && event.sequence <= webEvents[index - 1].sequence)) {
    return fatal("web_sequence_not_monotonic", webEvents);
  }
  const tuple = [candidate, previewIssued, hostPreview, previewAdopted,
    commitIssued, hostCommit, commitAdopted];
  if (tuple.some((event) => event.sourceKey !== candidate.sourceKey)
      || tuple.some((event) => event.operation !== candidate.operation)
      || tuple.some((event) => event.candidateKey !== candidate.candidateKey)) {
    return fatal("authority_tuple_mismatch", tuple);
  }
  const intent = previewIssued.intentKey;
  if (!intent || hostPreview.intentKey !== intent || previewAdopted.intentKey !== intent
      || commitIssued.intentKey !== intent || hostCommit.intentKey !== intent
      || commitAdopted.intentKey !== intent || refresh.intentKey !== intent) {
    return fatal("intent_tuple_mismatch", tuple.concat([refresh]));
  }
  if (hostPreview.webCallId !== previewIssued.webCallId
      || previewAdopted.webCallId !== previewIssued.webCallId
      || hostPreview.outcome !== "success" || hostPreview.remainingPending !== 0
      || previewIssued.pendingCount !== 1 || previewIssued.tokenPresent
      || previewIssued.commitReady || previewIssued.writeState !== "read_pending"
      || previewAdopted.pendingCount !== 0 || !previewAdopted.tokenPresent
      || !previewAdopted.commitReady || previewAdopted.writeState !== "idle") {
    return fatal("preview_contract_mismatch", { previewIssued, hostPreview, previewAdopted });
  }
  if (commitIssued.webCallId === previewIssued.webCallId
      || hostCommit.webCallId !== commitIssued.webCallId
      || commitAdopted.webCallId !== commitIssued.webCallId
      || refresh.webCallId !== commitIssued.webCallId
      || hostCommit.previewWebCallId !== previewIssued.webCallId
      || hostCommit.tokenRef !== hostPreview.tokenRef) {
    return fatal("commit_call_chain_mismatch", {
      previewIssued, hostPreview, commitIssued, hostCommit, commitAdopted, refresh,
    });
  }
  if (commitIssued.confirmationMode !== "safe" || commitIssued.autoCommitPending
      || commitIssued.pendingCount !== 1 || !commitIssued.tokenPresent
      || commitIssued.commitReady || commitIssued.writeState !== "write_pending"
      || hostCommit.outcome !== "success" || hostCommit.writeState !== "idle"
      || hostCommit.remainingPending !== 0 || hostCommit.snapshotPresent !== "true"
      || hostCommit.transactionIdPresent !== "true"
      || commitAdopted.confirmationMode !== "safe" || commitAdopted.autoCommitPending
      || commitAdopted.success !== true || commitAdopted.noOp !== false
      || commitAdopted.transactionIdPresent !== true
      || commitAdopted.requiresReconcile !== false || commitAdopted.needsReconcile
      || commitAdopted.pendingCount !== 0 || commitAdopted.writeState !== "write_pending") {
    return fatal("commit_contract_mismatch", { commitIssued, hostCommit, commitAdopted });
  }
  if (!sameStableSource(refresh.sourceKey, candidate.sourceKey)
      || refresh.sourceKey === candidate.sourceKey
      || refresh.success !== true || refresh.currentLeasePresent !== true
      || refresh.needsReconcile || refresh.pendingCount !== 0
      || refresh.writeState !== "idle") {
    return fatal("refresh_contract_mismatch", refresh);
  }
  return {
    ok: true,
    fatal: false,
    source,
    exactTuple: {
      panelInstanceId: anchor.panelInstanceId,
      viewSessionId: anchor.viewSessionId,
      sourceKeyBefore: candidate.sourceKey,
      sourceKeyAfterRefresh: refresh.sourceKey,
      operation: candidate.operation,
      candidateKey: candidate.candidateKey,
      intentKey: intent,
      previewWebCallId: previewIssued.webCallId,
      commitWebCallId: commitIssued.webCallId,
      tokenRef: hostPreview.tokenRef,
      stateRef: hostCommit.stateRef,
      writeEpoch: hostCommit.writeEpoch,
    },
    evidence: {
      candidateHitLine: candidate.lineNumber,
      previewIssuedLine: previewIssued.lineNumber,
      hostPreviewSettledLine: hostPreview.lineNumber,
      previewAdoptedLine: previewAdopted.lineNumber,
      commitIssuedLine: commitIssued.lineNumber,
      hostCommitSettledLine: hostCommit.lineNumber,
      commitAdoptedLine: commitAdopted.lineNumber,
      inventoryRefreshSettledLine: refresh.lineNumber,
    },
    assertions: {
      safeModeTwoActionCommit: true,
      exactPanelViewSourceCandidateIntent: true,
      previewTokenReferenceLinked: true,
      authoritativeTransactionObserved: true,
      authoritativeSnapshotStateRefObserved: true,
      currentLeaseRefreshSettled: true,
      reconcileDisposition: "not_required",
      unknownWriteReconcileJourneyVerified: false,
    },
  };
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForCommit(context, anchor, baseline, timeoutMs, pollMs, settleMs) {
  const deadline = Date.now() + timeoutMs;
  let last = incomplete("fresh_commit_evidence_not_observed");
  let validSince = null;
  let snapshot = null;
  while (Date.now() <= deadline) {
    assertCloneMatchesBaseline(baseline, "commit_journey_clone_guard");
    snapshot = await requestLogs(context);
    const records = opener.freshLogRecords(anchor.watermark, snapshot);
    last = verifyCommitEvidence(records, anchor);
    if (last.fatal) {
      fail(last.code, "commit_journey", "commit journey violated the exact gate", last.observed);
    }
    if (last.ok) {
      if (validSince === null) validSince = Date.now();
      if (Date.now() - validSince >= settleMs) {
        assertCloneMatchesBaseline(baseline, "commit_journey_clone_guard");
        return {
          result: last,
          finalLogTotal: snapshot.total,
          capturedAt: snapshot.capturedAt,
          settleMs,
        };
      }
    } else validSince = null;
    await sleep(pollMs);
  }
  fail("commit_evidence_timeout", "commit_journey", "exact commit journey timed out", {
    last,
    finalLogTotal: snapshot ? snapshot.total : null,
  });
}

function stableJson(value) {
  if (Array.isArray(value)) return value.map(stableJson);
  if (!isObject(value)) return value;
  const result = {};
  Object.keys(value).sort().forEach((key) => { result[key] = stableJson(value[key]); });
  return result;
}

function sourceItem(data, source) {
  const inventory = data && data.inventory;
  const container = inventory && inventory[source.containerId];
  if (!container) return null;
  const record = Array.isArray(container) ? container[source.slot] : container[String(source.slot)];
  if (!isObject(record) || !bounded(String(record.name || ""), 200)
      || !isObject(record.value) || record.lastUpdate == null) return null;
  return record;
}

function verifyPersistedClone(baseline, currentRaw, source, archiveEvidence, processExited) {
  if (!archiveEvidence) return incomplete("archive_shadow_receipt_missing");
  if (processExited !== true) return incomplete("old_launcher_not_exited");
  let current;
  const currentText = Buffer.isBuffer(currentRaw)
    ? currentRaw.toString("utf8") : String(currentRaw);
  if (archiveEvidence.archiveChars !== currentText.length) {
    return fatal("archive_shadow_length_mismatch", {
      archiveChars: archiveEvidence.archiveChars,
      currentTextChars: currentText.length,
    });
  }
  try {
    current = JSON.parse(currentText);
  } catch (error) {
    return fatal("persisted_clone_json_invalid", { message: error.message });
  }
  const rawBuffer = Buffer.isBuffer(currentRaw) ? currentRaw : Buffer.from(String(currentRaw));
  const currentHash = sha256(rawBuffer);
  const before = sourceItem(baseline.data, source);
  const after = sourceItem(current, source);
  if (!before || !after) return fatal("persisted_source_item_missing", { source });
  if (baseline.sha256 === currentHash) return fatal("clone_file_unchanged");
  if (String(current.lastSaved || "") === String(baseline.lastSaved || "")) {
    return fatal("clone_last_saved_unchanged");
  }
  if (String(before.name) !== String(after.name)) {
    return fatal("persisted_source_identity_changed", { before: before.name, after: after.name });
  }
  if (String(before.lastUpdate) === String(after.lastUpdate)) {
    return fatal("persisted_source_timestamp_unchanged");
  }
  if (JSON.stringify(stableJson(before.value)) === JSON.stringify(stableJson(after.value))) {
    return fatal("persisted_source_value_unchanged");
  }
  return {
    ok: true,
    sourceSlot: source.slot,
    itemName: String(after.name),
    beforeSha256: baseline.sha256,
    afterSha256: currentHash,
    beforeLastSaved: baseline.lastSaved,
    afterLastSaved: current.lastSaved,
    beforeItemLastUpdate: before.lastUpdate,
    afterItemLastUpdate: after.lastUpdate,
    archiveLineNumber: archiveEvidence.lineNumber,
    archiveChars: archiveEvidence.archiveChars,
    archivePath: relativeToRoot(archiveEvidence.archivePath),
  };
}

function findArchiveEvidence(records, afterLine, expectedPath) {
  const marker = "[ArchiveTask] Shadow saved: " + SLOT + " (";
  let latest = null;
  for (const record of records) {
    if (record.lineNumber <= afterLine) continue;
    const body = hostBody(record);
    if (!body || !body.startsWith(marker)) continue;
    const match = body.slice(marker.length).match(/^(\d+) chars\) path=(.+)$/);
    if (!match || Number(match[1]) <= 0 || !samePath(match[2], expectedPath)) continue;
    latest = Object.assign({}, record, {
      archiveChars: Number(match[1]),
      archivePath: match[2],
    });
  }
  return latest;
}

function logSnapshotFromText(text) {
  const clean = String(text || "").split("\n").map((line) => (
    line.endsWith("\r") ? line.slice(0, -1) : line
  )).filter((line) => line.length > 0);
  return {
    total: clean.length,
    lines: clean.slice(Math.max(0, clean.length - LOG_TAIL_LIMIT)),
    capturedAt: new Date().toISOString(),
  };
}

function readFinalLogSnapshotFromDisk() {
  const logPath = path.join(root, "logs", "launcher.log");
  opener.assertCanonicalDirectoryChain(root, path.dirname(logPath), "clone_persistence");
  const snapshot = opener.readRegularFileSnapshot(
    logPath,
    true,
    "clone_persistence"
  );
  return snapshot ? logSnapshotFromText(snapshot.raw.toString("utf8")) : null;
}

function processExists(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error && error.code === "EPERM";
  }
}

async function waitForSaveAndExit(context, anchor, baseline, commit, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let archiveEvidence = null;
  let currentRaw = null;
  let lastSnapshot = null;
  while (Date.now() <= deadline) {
    const processAlive = processExists(anchor.pid);
    if (processAlive) {
      try {
        lastSnapshot = await requestLogs(context);
        const records = opener.freshLogRecords(anchor.watermark, lastSnapshot);
        archiveEvidence = findArchiveEvidence(
          records,
          commit.evidence.hostCommitSettledLine,
          baseline.path
        ) || archiveEvidence;
      } catch (_error) {
        // The process may be between archive acknowledgement and final exit.
      }
    }
    const diskSnapshot = !processAlive ? readFinalLogSnapshotFromDisk() : null;
    if (diskSnapshot) {
      lastSnapshot = diskSnapshot;
      const diskRecords = opener.freshLogRecords(anchor.watermark, diskSnapshot);
      const diskArchive = findArchiveEvidence(
        diskRecords,
        commit.evidence.hostCommitSettledLine,
        baseline.path
      );
      if (diskArchive && (!archiveEvidence
          || diskArchive.lineNumber > archiveEvidence.lineNumber)) {
        archiveEvidence = diskArchive;
      }
    }
    currentRaw = readCloneBytes(baseline.path, true, "clone_persistence");
    const exited = !processAlive;
    if (currentRaw) {
      const check = verifyPersistedClone(
        baseline,
        currentRaw,
        commit.source,
        archiveEvidence,
        exited
      );
      if (check.fatal) {
        if (exited) {
          fail(check.code, "clone_persistence", "clone persistence gate failed", check.observed);
        }
      } else if (check.ok) {
        return check;
      }
    }
    if (exited && !archiveEvidence) {
      fail(
        "launcher_exited_without_archive_receipt",
        "clone_persistence",
        "Launcher exited before the exact clone shadow save receipt was observed"
      );
    }
    await sleep(pollMs);
  }
  fail("clone_persistence_timeout", "clone_persistence", "clone archive persistence/exit timed out", {
    archiveObserved: !!archiveEvidence,
    processExited: !processExists(anchor.pid),
    finalLogTotal: lastSnapshot ? lastSnapshot.total : null,
  });
}

function candidateRootFor(anchor) {
  if (anchor.runtimeIdentity.runtimeMode === "formal_runtime") return null;
  return path.dirname(path.dirname(anchor.runtimeIdentity.processPath));
}

function assertSameBuild(anchor, expected) {
  assertIdentityFields(runtimeExpected(anchor), expected, "reload_identity_expected");
  return true;
}

function assertReloadProcessInventory(processes, expectedPid, phase) {
  try {
    opener.assertExclusiveLauncherProcess(processes, expectedPid);
  } catch (error) {
    fail(
      "reload_launcher_process_not_exclusive",
      phase || "reload_identity",
      "reload requires zero Launcher Core processes before start and exactly the new PID afterward",
      error && error.details ? error.details : {
        expectedPid,
        observedPids: Array.isArray(processes)
          ? processes.map((entry) => entry.pid) : [],
      }
    );
  }
  return true;
}

function parseReloadEvidence(records, expected) {
  const parsed = records.map(parseHostSnapshot).filter(Boolean);
  const requests = records.map(parseHostSnapshotRequest).filter(Boolean);
  const invalid = parsed.concat(requests).find((entry) => entry.invalid);
  if (invalid) return fatal(invalid.invalid, invalid);
  const cross = parsed.find((entry) => entry.panelInstanceId !== expected.panelInstanceId
    || entry.viewSessionId !== expected.viewSessionId);
  if (cross) return fatal("reload_cross_session_snapshot", cross);
  const stateMatches = parsed.filter((entry) => entry.stateRef === expected.stateRef);
  const match = stateMatches.map((snapshot) => {
    const request = requests.find((entry) => entry.lineNumber < snapshot.lineNumber
      && entry.webCallId === snapshot.callId
      && entry.panelInstanceId === snapshot.panelInstanceId
      && entry.viewSessionId === snapshot.viewSessionId
      && entry.source.containerId === expected.source.containerId
      && entry.source.slot === expected.source.slot);
    return request ? { snapshot, request } : null;
  }).find(Boolean);
  if (!match) return incomplete("persisted_state_readback_missing", {
    observed: parsed.map((entry) => ({
      lineNumber: entry.lineNumber,
      sourceKey: entry.sourceKey,
      stateRef: entry.stateRef,
      request: requests.find((request) => request.webCallId === entry.callId) || null,
    })),
  });
  return {
    ok: true,
    evidence: Object.assign({}, match.snapshot, {
      requestLineNumber: match.request.lineNumber,
      source: match.request.source,
    }),
    assertions: {
      sameStableInventoryCoordinate: true,
      committedStateRefReadBack: true,
      restartLeaseMayRotate: true,
    },
  };
}

async function waitForReloadReadback(context, watermark, expected, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let last = incomplete("persisted_state_readback_missing");
  while (Date.now() <= deadline) {
    const snapshot = await requestLogs(context);
    const records = opener.freshLogRecords(watermark, snapshot);
    last = parseReloadEvidence(records, expected);
    if (last.fatal) {
      fail(last.code, "reload_readback", "reload readback violated the exact gate", last.observed);
    }
    if (last.ok) return Object.assign({ finalLogTotal: snapshot.total }, last);
    await sleep(pollMs);
  }
  fail(
    "reload_readback_timeout",
    "reload_readback",
    "select the same backpack slot; committed stateRef was not read back before timeout",
    last.observed
  );
}

async function restartAndReadback(anchor, args, commit) {
  const candidateRoot = candidateRootFor(anchor);
  let expected;
  try {
    expected = opener.resolveExpectedRuntimeIdentity(root, candidateRoot);
  } catch (error) {
    fail("reload_identity_expected_failed", "reload_identity", error.message, error.details);
  }
  assertSameBuild(anchor, expected);
  const launcherArgs = {
    startLauncher: true,
    readyTimeoutMs: args.restartTimeoutMs,
    pollMs: args.pollMs,
    slot: SLOT,
  };
  assertReloadProcessInventory(
    opener.queryLauncherCoreProcesses(),
    null,
    "reload_before_start"
  );
  const preexistingPort = await opener.discoverPort(root);
  if (preexistingPort) {
    fail(
      "reload_launcher_already_running",
      "reload_identity",
      "a Launcher appeared after the old PID exited; refusing to adopt an unrelated process"
    );
  }
  opener.startLauncher(root, expected);
  const port = await opener.waitForPort(
    root,
    args.restartTimeoutMs,
    args.pollMs
  );
  let actual;
  try {
    actual = verifyRuntimeIdentity(root, port, expected);
  } catch (error) {
    fail("reload_runtime_identity_failed", "reload_identity", error.message, error.details);
  }
  if (actual.pid === anchor.pid) {
    fail("reload_pid_not_fresh", "reload_identity", "reload reused the pre-save Launcher PID");
  }
  assertReloadProcessInventory(
    opener.queryLauncherCoreProcesses(),
    actual.pid,
    "reload_identity"
  );
  await opener.waitForAgentControl(port, args.restartTimeoutMs, args.pollMs);
  const startSnapshot = await opener.readLogSnapshot(port);
  const startWatermark = {
    total: startSnapshot.total,
    capturedAt: startSnapshot.capturedAt,
  };
  const startResponse = await opener.agent(port, "start", {
    slot: SLOT,
    fresh: false,
    deferReveal: false,
    requireFlashReveal: true,
    rememberSlot: false,
  });
  opener.assertResponseSucceeded(startResponse, "reload_start", "agent_control start");
  const timeline = [];
  const runtime = await opener.waitForRuntimeReady(
    port,
    launcherArgs,
    startWatermark,
    startResponse,
    timeline
  );
  const identityAfterReady = verifyRuntimeIdentity(root, port, expected);
  if (identityAfterReady.pid !== actual.pid) {
    fail("reload_process_changed", "reload_identity", "Launcher changed during reload readiness");
  }
  assertReloadProcessInventory(
    opener.queryLauncherCoreProcesses(),
    actual.pid,
    "reload_ready"
  );
  const openSnapshot = await opener.readLogSnapshot(port);
  const openWatermark = {
    total: openSnapshot.total,
    capturedAt: openSnapshot.capturedAt,
  };
  const openResponse = await opener.agent(port, "openEquipmentTuning", {
    expectedSlot: SLOT,
    expectedAttemptId: runtime.expectedAttemptId,
  });
  opener.assertResponseSucceeded(
    openResponse,
    "reload_open_equipment_tuning",
    "agent_control openEquipmentTuning"
  );
  const panelGate = await opener.waitForWorkbenchSnapshotGate(
    port,
    openWatermark,
    args.panelTimeoutMs,
    args.pollMs
  );
  const panel = panelGate.evidence.activeWorkbench.panelInstanceId;
  const view = panelGate.evidence.tuningSnapshot.viewSessionId;
  process.stderr.write(JSON.stringify({
    state: "waiting_for_reload_source_selection",
    gate: GATE,
    backpackSlot: commit.source.slot,
    itemStateRef: commit.exactTuple.stateRef,
    panelInstanceId: panel,
    viewSessionId: view,
  }) + "\n");
  const context = LegacyHttpClient.readExactLauncherHttpContext(root);
  const readback = await waitForReloadReadback(context, openWatermark, {
    panelInstanceId: panel,
    viewSessionId: view,
    source: {
      containerId: commit.source.containerId,
      slot: commit.source.slot,
    },
    stateRef: commit.exactTuple.stateRef,
  }, args.panelTimeoutMs, args.pollMs);
  const finalIdentity = verifyRuntimeIdentity(root, port, expected);
  if (finalIdentity.pid !== actual.pid) {
    fail("reload_process_changed", "reload_identity", "Launcher changed before readback closed");
  }
  assertReloadProcessInventory(
    opener.queryLauncherCoreProcesses(),
    actual.pid,
    "reload_readback"
  );
  return {
    runtimeIdentity: publicRuntimeIdentity(finalIdentity),
    oldPid: anchor.pid,
    newPid: actual.pid,
    oldHttpPort: anchor.httpPort,
    newHttpPort: port,
    attemptId: runtime.expectedAttemptId,
    handoffEvidence: runtime.handoffEvidence,
    titleFrameEvidence: runtime.titleFrameEvidence,
    enterRequestCount: runtime.enterRequestCount,
    openWatermark,
    panelInstanceId: panel,
    viewSessionId: view,
    readback,
  };
}

function outputDirectory() {
  return path.join(
    root,
    "tmp",
    "equipment-tuning",
    "commit-journeys",
    new Date().toISOString().replace(/[-:.]/g, "") + "-" + String(process.pid)
  );
}

function serializeError(error) {
  return {
    code: error && error.code ? error.code : "unexpected_error",
    phase: error && error.phase ? error.phase : "unexpected",
    message: error && error.message ? error.message : String(error),
    details: error && error.details ? error.details : null,
  };
}

function relativeToRoot(filePath) {
  return path.relative(root, filePath).replace(/\\/g, "/");
}

function formatMarkdown(receipt) {
  return [
    "# Equipment Tuning Commit Journey Receipt",
    "",
    "- Gate: `" + receipt.gate + "`",
    "- Status: `" + receipt.status + "`",
    "- Opener: `" + (receipt.openReport || "") + "`",
    "- Runtime mode: `" + (receipt.opener.runtimeIdentity
      ? receipt.opener.runtimeIdentity.runtimeMode : "") + "`",
    "- Build identity: `" + (receipt.opener.runtimeIdentity
      ? receipt.opener.runtimeIdentity.buildIdentity : "") + "`",
    "- Payload closure: `" + (receipt.opener.runtimeIdentity
      ? receipt.opener.runtimeIdentity.payloadClosure : "") + "`",
    "- Full runtime identity reverified: `" + String(
      receipt.runtimeContinuity.fullIdentityReverified === true
    ) + "`",
    "- Clone: `" + SLOT + "`",
    "- Seed SHA-256: `" + (receipt.opener.seedSha256 || "") + "`",
    "- Seeded target SHA-256: `" + (receipt.opener.seededTargetSha256 || "") + "`",
    "- Post-snapshot clone baseline SHA-256: `"
      + (receipt.opener.cloneBaselineSha256 || "") + "`",
    "- Clone baseline stable window: `"
      + String(receipt.opener.cloneBaselineStableWindowMs || "") + "ms`",
    "- Verifier interaction watermark: `"
      + String(receipt.opener.interactionLogWatermark
        ? receipt.opener.interactionLogWatermark.total : "") + "`",
    "- Commit verified: `" + String(receipt.scope.commitVerified === true) + "`",
    "- Clone persistence verified: `" + String(receipt.scope.clonePersistenceVerified === true) + "`",
    "- Restart readback verified: `" + String(receipt.scope.restartReadbackVerified === true) + "`",
    "- Reconcile disposition: `" + receipt.scope.reconcileDisposition + "`",
    "- SAFEEXIT UI journey verified: `false` (not machine-bound by this gate)",
    "- Unknown-write reconcile journey verified: `false` (reserved for A2 fault injection)",
    "",
    "This receipt is invalid unless status is `e2e_verified`. It proves one real",
    "safe-mode candidate/commit journey, clone-only disk persistence, a fresh",
    "full restart, and exact stateRef readback. It does not authorize or describe",
    "any write to a player save.",
    "",
  ].join("\n");
}

function writeReceipt(receipt, directory) {
  fs.mkdirSync(directory, { recursive: true });
  const jsonPath = path.join(directory, "receipt.json");
  const markdownPath = path.join(directory, "receipt.md");
  receipt.receiptPath = relativeToRoot(jsonPath);
  receipt.receiptMarkdownPath = relativeToRoot(markdownPath);
  fs.writeFileSync(jsonPath, JSON.stringify(receipt, null, 2) + "\n", "utf8");
  fs.writeFileSync(markdownPath, formatMarkdown(receipt), "utf8");
}

async function runJourney(args) {
  const receipt = {
    schema: "equipment-tuning.commit-journey-receipt.v1",
    gate: GATE,
    status: "running",
    startedAt: new Date().toISOString(),
    finishedAt: null,
    openReport: null,
    scope: {
      cloneSlot: SLOT,
      verifierClicksUi: false,
      verifierSendsBusinessCommands: false,
      verifierSendsSaveCommands: false,
      playerSavesReadOrWritten: false,
      commitVerified: false,
      clonePersistenceVerified: false,
      restartReadbackVerified: false,
      reconcileDisposition: "not_evaluated",
      unknownWriteReconcileJourneyVerified: false,
      safeExitUiJourneyVerified: false,
    },
    opener: {},
    runtimeContinuity: {},
    commit: null,
    persistence: null,
    reload: null,
    error: null,
  };
  const directory = outputDirectory();
  let caught = null;
  try {
    const reportPath = resolveOpenReport(args.openReport);
    receipt.openReport = relativeToRoot(reportPath);
    const report = readJsonFile(reportPath, "open_report_json_invalid", "open_report");
    const anchor = previewGate.validateOpenReport(report);
    const openerWatermark = Object.assign({}, anchor.watermark);
    const baseline = validateCloneTarget(report, anchor);
    receipt.opener = {
      runtimeIdentity: anchor.runtimeIdentity,
      httpPort: anchor.httpPort,
      pid: anchor.pid,
      openLogWatermark: openerWatermark,
      interactionLogWatermark: null,
      panelInstanceId: anchor.panelInstanceId,
      viewSessionId: anchor.viewSessionId,
      snapshotLineNumber: anchor.snapshotLineNumber,
      clonePath: baseline.relativePath,
      seedSha256: baseline.seedSha256,
      seededTargetSha256: baseline.seededTargetSha256,
      cloneBaselineSha256: baseline.sha256,
      cloneBaselineCapturedAt: baseline.gateBaseline.capturedAt,
      cloneBaselineStableWindowMs: baseline.gateBaseline.stableWindowMs,
      cloneBaselineStableSampleCount: baseline.gateBaseline.stableSampleCount,
      startupArchiveReceipt: baseline.gateBaseline.startupArchiveReceipt,
      postCaptureLogWatermark: baseline.gateBaseline.postCaptureLogWatermark,
    };
    const before = verifyLiveIdentity(
      anchor,
      anchor.pid,
      anchor.httpPort,
      "runtime_identity_before_commit"
    );
    receipt.runtimeContinuity.beforeCommit = before.identity;
    const interactionSnapshot = await requestLogs(before.context);
    const interactionWatermark = validateGateLogHistory(
      report,
      anchor,
      baseline,
      interactionSnapshot
    );
    assertCloneMatchesBaseline(baseline, "interaction_watermark_clone_guard");
    anchor.watermark = interactionWatermark;
    receipt.opener.interactionLogWatermark = interactionWatermark;
    process.stderr.write(JSON.stringify({
      state: "waiting_for_computer_use_safe_commit",
      gate: GATE,
      instruction: "保持逐次确认：点一个可用候选，等待权威预览，再单独点击提交",
      panelInstanceId: anchor.panelInstanceId,
      viewSessionId: anchor.viewSessionId,
      cloneSlot: SLOT,
      interactionWatermarkTotal: interactionWatermark.total,
    }) + "\n");
    const closed = await waitForCommit(
      before.context,
      anchor,
      baseline,
      args.interactionTimeoutMs,
      args.pollMs,
      args.settleMs
    );
    const afterCommitIdentity = verifyLiveIdentity(
      anchor,
      anchor.pid,
      anchor.httpPort,
      "runtime_identity_after_commit"
    );
    receipt.runtimeContinuity.afterCommit = afterCommitIdentity.identity;
    receipt.runtimeContinuity.fullIdentityReverified = true;
    receipt.commit = Object.assign({}, closed.result, {
      finalLogTotal: closed.finalLogTotal,
      capturedAt: closed.capturedAt,
      cleanNoReconcileQuietWindowMs: closed.settleMs,
    });
    receipt.scope.commitVerified = true;
    receipt.scope.reconcileDisposition = "not_required";
    process.stderr.write(JSON.stringify({
      state: "waiting_for_clone_archive_and_exit",
      gate: GATE,
      instruction: "关闭调制面板；建议走现役 SAFEEXIT 存盘并退出。Gate 只签 clone archive 与旧 PID 退出，不签 SAFEEXIT UI session",
      cloneSlot: SLOT,
      sourceSlot: closed.result.source.slot,
      commitStateRef: closed.result.exactTuple.stateRef,
    }) + "\n");
    receipt.persistence = await waitForSaveAndExit(
      afterCommitIdentity.context,
      anchor,
      baseline,
      closed.result,
      args.saveExitTimeoutMs,
      args.pollMs
    );
    receipt.scope.clonePersistenceVerified = true;
    receipt.reload = await restartAndReadback(anchor, args, closed.result);
    receipt.scope.restartReadbackVerified = true;
    receipt.status = "e2e_verified";
  } catch (error) {
    caught = error;
    receipt.status = "failed";
    receipt.error = serializeError(error);
  } finally {
    receipt.finishedAt = new Date().toISOString();
    writeReceipt(receipt, directory);
  }
  if (caught) {
    caught.receiptPath = receipt.receiptPath;
    throw caught;
  }
  console.log(JSON.stringify({
    ok: true,
    status: receipt.status,
    gate: receipt.gate,
    cloneSlot: SLOT,
    exactTuple: receipt.commit.exactTuple,
    persistence: receipt.persistence,
    reload: {
      oldPid: receipt.reload.oldPid,
      newPid: receipt.reload.newPid,
      panelInstanceId: receipt.reload.panelInstanceId,
      viewSessionId: receipt.reload.viewSessionId,
      stateRef: receipt.reload.readback.evidence.stateRef,
    },
    receipt: receipt.receiptPath,
  }, null, 2));
  return receipt;
}

function fixtureWeb(event, overrides) {
  const base = {
    type: "debug",
    scope: "equipment_tuning",
    sequence: 1,
    event,
    operation: "install_mod",
    webCallId: "",
    panelInstanceId: "panel.1",
    viewSessionId: "view.1",
    sourceKey: "inventory:背包:7:lease.old",
    candidateKey: "mod.1",
    intentKey: "install_mod|mod.1|",
    pendingCount: 0,
    tokenPresent: false,
    commitReady: false,
    confirmationMode: "safe",
    autoCommitPending: false,
    writeState: "idle",
    success: null,
    transactionIdPresent: null,
    requiresReconcile: null,
    currentLeasePresent: null,
    needsReconcile: false,
    reconciled: null,
    noOp: null,
    reconcileAfterCallId: "",
  };
  return Object.assign(base, overrides || {});
}

function fixtureRecords(intentLength) {
  const intent = "install_mod|" + "x".repeat(Math.max(1, (intentLength || 32) - 13)) + "|";
  const messages = [
    fixtureWeb("candidate_hit", { sequence: 1, intentKey: "", candidateKey: "mod.1" }),
    fixtureWeb("preview_issued", {
      sequence: 2, webCallId: "preview.1", intentKey: intent, pendingCount: 1,
      writeState: "read_pending",
    }),
    "event=equipment_tuning_preview_settled webCallId=preview.1 flashCallId=11"
      + " requestCallId=preview.1 tokenRef=sha256_aaaaaaaaaaaaaaaaaaaaaaaa"
      + " panelInstanceId=panel.1 viewSessionId=view.1"
      + " sourceKey=" + encodeURIComponent("inventory:背包:7:lease.old")
      + " operation=install_mod candidateKey=mod.1 intentKey=" + encodeURIComponent(intent)
      + " outcome=success remainingPending=0",
    fixtureWeb("preview_adopted", {
      sequence: 3, webCallId: "preview.1", intentKey: intent,
      tokenPresent: true, commitReady: true,
    }),
    fixtureWeb("commit_issued", {
      sequence: 4, webCallId: "commit.1", intentKey: intent, pendingCount: 1,
      tokenPresent: true, writeState: "write_pending",
    }),
    "event=equipment_tuning_commit_settled webCallId=commit.1 flashCallId=12"
      + " requestCallId=commit.1 previewWebCallId=preview.1"
      + " tokenRef=sha256_aaaaaaaaaaaaaaaaaaaaaaaa"
      + " panelInstanceId=panel.1 viewSessionId=view.1"
      + " sourceKey=" + encodeURIComponent("inventory:背包:7:lease.old")
      + " operation=install_mod candidateKey=mod.1 intentKey=" + encodeURIComponent(intent)
      + " outcome=success writeEpoch=4 writeState=idle remainingPending=0"
      + " stateRef=sha256_bbbbbbbbbbbbbbbbbbbbbbbb"
      + " snapshotPresent=true transactionIdPresent=true",
    fixtureWeb("commit_adopted", {
      sequence: 5, webCallId: "commit.1", intentKey: intent, pendingCount: 0,
      tokenPresent: true, writeState: "write_pending", success: true,
      transactionIdPresent: true, requiresReconcile: false, noOp: false,
    }),
    fixtureWeb("inventory_refresh_settled", {
      sequence: 6, webCallId: "commit.1", intentKey: intent,
      sourceKey: "inventory:背包:7:lease.new", success: true,
      currentLeasePresent: true,
    }),
  ];
  return messages.map((message, index) => ({
    lineNumber: index + 11,
    line: typeof message === "string"
      ? message : "[WebDebug] " + JSON.stringify(message),
  }));
}

function fixtureRedactedRecords() {
  const sourceBefore = authorityRef("inventory:背包:7:lease.old");
  const sourceAfter = authorityRef("inventory:背包:7:lease.new");
  const intent = authorityRef("install_mod|mod.1|");
  function web(event, callId, sourceKey, tokenPresent, extra) {
    return "[WebDebug] scope=equipment_tuning event=" + event
      + " cmd=other callId=" + (callId || "other")
      + " sourceKeyRef=" + sourceKey
      + (event === "candidate_hit" ? " intentKeyPresent=false" : " intentKeyRef=" + intent)
      + " tokenPresent=" + String(tokenPresent)
      + (extra || "")
      + " payload=redacted len=700 authorityFieldCount=4";
  }
  const messages = [
    web("candidate_hit", "", sourceBefore, false),
    web("preview_issued", "preview.1", sourceBefore, false),
    "[EquipmentTuningTask] -> Flash: " + JSON.stringify({
      task: "cmd",
      action: "equipmentTuningPreview",
      callId: 11,
      v: 1,
      viewSessionId: "view.1",
      operation: "install_mod",
      source: {
        sourceKind: "inventory",
        containerId: "背包",
        slot: 7,
        expectedLeaseRef: "sha256_dddddddddddddddddddddddd",
      },
      candidateKey: "mod.1",
      panelInstanceId: "panel.1",
      writeEpoch: 0,
      requestCallId: "preview.1",
    }),
    "event=equipment_tuning_preview_settled webCallId=preview.1 flashCallId=11"
      + " requestCallId=preview.1 tokenRef=sha256_aaaaaaaaaaaaaaaaaaaaaaaa"
      + " panelInstanceId=panel.1 viewSessionId=view.1"
      + " sourceKeyRef=" + sourceBefore
      + " operation=install_mod candidateKey=mod.1 intentKeyRef=" + intent
      + " outcome=success remainingPending=0",
    web("preview_adopted", "preview.1", sourceBefore, true),
    web("commit_issued", "commit.1", sourceBefore, true),
    "[EquipmentTuningTask] -> Flash: " + JSON.stringify({
      task: "cmd",
      action: "equipmentTuningCommit",
      callId: 12,
      v: 1,
      viewSessionId: "view.1",
      expectedTuningTokenRef: "sha256_aaaaaaaaaaaaaaaaaaaaaaaa",
      panelInstanceId: "panel.1",
      writeEpoch: 4,
      requestCallId: "commit.1",
    }),
    "event=equipment_tuning_commit_settled webCallId=commit.1 flashCallId=12"
      + " requestCallId=commit.1 previewWebCallId=preview.1"
      + " tokenRef=sha256_aaaaaaaaaaaaaaaaaaaaaaaa"
      + " panelInstanceId=panel.1 viewSessionId=view.1"
      + " sourceKeyRef=" + sourceBefore
      + " operation=install_mod candidateKey=mod.1 intentKeyRef=" + intent
      + " outcome=success writeEpoch=4 writeState=idle remainingPending=0"
      + " stateRef=sha256_bbbbbbbbbbbbbbbbbbbbbbbb"
      + " snapshotPresent=true transactionIdPresent=true",
    web("commit_adopted", "commit.1", sourceBefore, true,
      " transactionIdPresent=true requiresReconcile=false"),
    web("inventory_refresh_settled", "commit.1", sourceAfter, false),
  ];
  return messages.map((line, index) => ({ lineNumber: index + 11, line }));
}

function fixtureAnchor() {
  return {
    panelInstanceId: "panel.1",
    viewSessionId: "view.1",
    snapshotLineNumber: 10,
  };
}

function deepCopy(value) {
  return JSON.parse(JSON.stringify(value));
}

function expectNegative(name, mutate, expectedCode, counters) {
  const records = fixtureRecords();
  mutate(records);
  const result = verifyCommitEvidence(records, fixtureAnchor());
  if (result.ok || result.code !== expectedCode) {
    throw new Error(name + " expected " + expectedCode + " but got " + JSON.stringify(result));
  }
  counters.negative += 1;
}

function expectRedactedNegative(name, mutate, expectedCode, counters) {
  const records = fixtureRedactedRecords();
  mutate(records);
  const result = verifyCommitEvidence(records, fixtureAnchor());
  if (result.ok || result.code !== expectedCode) {
    throw new Error(name + " expected " + expectedCode + " but got " + JSON.stringify(result));
  }
  counters.negative += 1;
}

function fixtureClonePreparationReport() {
  const snapshotAt = "2026-08-02T00:00:00.000Z";
  const stableStartedAt = "2026-08-02T00:00:00.500Z";
  const capturedAt = "2026-08-02T00:00:01.500Z";
  const seededHash = "1".repeat(64);
  const baselineHash = "2".repeat(64);
  const targetPath = path.resolve(root, "saves", SLOT + ".json");
  return {
    slot: SLOT,
    seedSlot: "crazyflasher7_saves2",
    finishedAt: "2026-08-02T00:00:02.000Z",
    startLogWatermark: {
      total: 80,
      capturedAt: "2026-08-01T23:59:50.000Z",
    },
    runtime: {
      expectedAttemptId: "attempt.fixture.1",
      handoffEvidence: { lineNumber: 85 },
      titleFrameEvidence: { lineNumber: 88 },
    },
    snapshotGate: {
      evidence: {
        tuningSnapshot: {
          panelInstanceId: "panel.fixture.1",
          viewSessionId: "view.fixture.1",
          callId: "snapshot.fixture.1",
          sourceKey: "inventory:背包:7:lease.fixture",
          stateRef: "sha256_aaaaaaaaaaaaaaaaaaaaaaaa",
          lineNumber: 100,
        },
      },
    },
    timeline: [
      { phase: "snapshot_gate_reached", at: snapshotAt },
      {
        phase: "post_snapshot_clone_baseline_bound",
        at: capturedAt,
        sha256: baselineHash,
        utf8Bytes: 4096,
        textChars: 3000,
        deviceId: "123",
        fileId: "20829148277625004",
        mtimeNs: String(
          BigInt(Date.parse("2026-08-01T23:59:59.000Z")) * 1000000n
        ),
        semanticContract: "startup_normalization.v1",
        semanticSha256: "3".repeat(64),
        stableWindowMs: 1000,
        stableSampleCount: 2,
        changedFromSeed: true,
        startupArchiveLine: 90,
        archiveEvidenceFloorLine: 88,
        postCaptureLogTotal: 110,
      },
      {
        phase: "runtime_identity_reverified_after_clone_baseline",
        at: "2026-08-02T00:00:01.700Z",
      },
    ],
    savePreparation: {
      targetSlot: SLOT,
      seedSlot: "crazyflasher7_saves2",
      targetJson: "saves/" + SLOT + ".json",
      wroteSeed: true,
      seedSha256: "0".repeat(64),
      seededTargetSha256: seededHash,
      targetSha256: seededHash,
      semanticContract: "startup_normalization.v1",
      semanticSha256: "3".repeat(64),
      role: "fs",
      level: 99,
      gateBaseline: {
        sha256: baselineHash,
        utf8Bytes: 4096,
        textChars: 3000,
        deviceId: "123",
        fileId: "20829148277625004",
        mtimeNs: String(
          BigInt(Date.parse("2026-08-01T23:59:59.000Z")) * 1000000n
        ),
        semanticContract: "startup_normalization.v1",
        semanticSha256: "3".repeat(64),
        role: "fs",
        level: 99,
        lastWriteTimeUtc: "2026-08-01T23:59:59.000Z",
        lastSaved: "2026-08-02 08:00:01",
        stableStartedAt,
        capturedAt,
        stableWindowMs: 1000,
        stableSampleCount: 2,
        regularFileVerified: true,
        realPathBound: true,
        changedFromSeed: true,
        archiveEvidenceFloorLine: 88,
        attemptId: "attempt.fixture.1",
        snapshot: {
          panelInstanceId: "panel.fixture.1",
          viewSessionId: "view.fixture.1",
          callId: "snapshot.fixture.1",
          sourceKey: "inventory:背包:7:lease.fixture",
          stateRef: "sha256_aaaaaaaaaaaaaaaaaaaaaaaa",
          lineNumber: 100,
        },
        startupArchiveReceipt: {
          lineNumber: 90,
          archiveChars: 3000,
          targetPath,
        },
        postCaptureLogWatermark: {
          total: 110,
          capturedAt: "2026-08-02T00:00:01.600Z",
        },
      },
    },
  };
}

function expectCloneContractNegative(name, mutate, counters) {
  const report = fixtureClonePreparationReport();
  mutate(report);
  let rejected = false;
  try {
    validateClonePreparationContract(report);
  } catch (error) {
    rejected = error && error.code === "clone_preparation_invalid";
  }
  if (!rejected) {
    throw new Error(name + " clone preparation fixture was accepted");
  }
  counters.negative += 1;
}

function runOfflineChecks() {
  const counters = { positive: 0, negative: 0 };
  [fixtureRecords(), fixtureRecords(384)].forEach((records) => {
    const result = verifyCommitEvidence(records, fixtureAnchor());
    if (!result.ok || result.exactTuple.stateRef !== "sha256_bbbbbbbbbbbbbbbbbbbbbbbb") {
      throw new Error("positive commit fixture failed: " + JSON.stringify(result));
    }
    counters.positive += 1;
  });
  const redactedResult = verifyCommitEvidence(
    fixtureRedactedRecords(), fixtureAnchor()
  );
  if (!redactedResult.ok
      || redactedResult.exactTuple.stateRef !== "sha256_bbbbbbbbbbbbbbbbbbbbbbbb"
      || redactedResult.source.slot !== 7
      || redactedResult.assertions.redactedDiagnosticProjection !== true) {
    throw new Error("redacted commit fixture failed: " + JSON.stringify(redactedResult));
  }
  counters.positive += 1;
  expectRedactedNegative("redacted missing preview request", (records) => {
    records.splice(2, 1);
  }, "host_preview_request_missing", counters);
  expectRedactedNegative("redacted source mismatch", (records) => {
    records[7].line = records[7].line.replace(
      /sourceKeyRef=sha256_[a-f0-9]{24}/,
      "sourceKeyRef=sha256_cccccccccccccccccccccccc"
    );
  }, "authority_tuple_mismatch", counters);
  expectRedactedNegative("redacted missing commit request", (records) => {
    records.splice(6, 1);
  }, "host_commit_request_missing", counters);
  expectRedactedNegative("redacted commit token mismatch", (records) => {
    records[6].line = records[6].line.replace(
      "sha256_aaaaaaaaaaaaaaaaaaaaaaaa",
      "sha256_cccccccccccccccccccccccc"
    );
  }, "commit_call_chain_mismatch", counters);
  expectRedactedNegative("redacted refresh did not rotate", (records) => {
    const before = opener.extractLogField(records[0].line, "sourceKeyRef");
    records[9].line = records[9].line.replace(
      /sourceKeyRef=sha256_[a-f0-9]{24}/,
      "sourceKeyRef=" + before
    );
  }, "authority_tuple_mismatch", counters);
  expectRedactedNegative("redacted missing transaction", (records) => {
    records[8].line = records[8].line.replace(
      "transactionIdPresent=true", "transactionIdPresent=false"
    );
  }, "commit_contract_mismatch", counters);
  const web = (records, index) => JSON.parse(records[index].line.slice("[WebDebug] ".length));
  const setWeb = (records, index, value) => {
    records[index].line = "[WebDebug] " + JSON.stringify(value);
  };
  expectNegative("missing candidate", (records) => records.splice(0, 1),
    "candidate_hit_missing", counters);
  expectNegative("cross panel", (records) => {
    const value = web(records, 4); value.panelInstanceId = "panel.other"; setWeb(records, 4, value);
  }, "cross_session_tuning_event", counters);
  expectNegative("cross view", (records) => {
    const value = web(records, 6); value.viewSessionId = "view.other"; setWeb(records, 6, value);
  }, "cross_session_tuning_event", counters);
  expectNegative("loadout source", (records) => {
    const value = web(records, 0); value.sourceKey = "loadout:1:头部:7"; setWeb(records, 0, value);
  }, "clone_inventory_source_required", counters);
  expectNegative("fast mode", (records) => {
    const value = web(records, 4); value.confirmationMode = "fast"; setWeb(records, 4, value);
  }, "commit_contract_mismatch", counters);
  expectNegative("auto commit", (records) => {
    const value = web(records, 4); value.autoCommitPending = true; setWeb(records, 4, value);
  }, "commit_contract_mismatch", counters);
  expectNegative("preview call mismatch", (records) => {
    const value = web(records, 3); value.webCallId = "preview.other"; setWeb(records, 3, value);
  }, "preview_contract_mismatch", counters);
  expectNegative("host preview outcome", (records) => {
    records[2].line = records[2].line.replace("outcome=success", "outcome=error%3Astale_state");
  }, "preview_contract_mismatch", counters);
  expectNegative("token ref mismatch", (records) => {
    records[5].line = records[5].line.replace(
      "sha256_aaaaaaaaaaaaaaaaaaaaaaaa",
      "sha256_cccccccccccccccccccccccc"
    );
  }, "commit_call_chain_mismatch", counters);
  expectNegative("source mismatch", (records) => {
    records[5].line = records[5].line.replace("lease.old", "lease.other");
  }, "authority_tuple_mismatch", counters);
  expectNegative("candidate mismatch", (records) => {
    const value = web(records, 4); value.candidateKey = "mod.2"; setWeb(records, 4, value);
  }, "authority_tuple_mismatch", counters);
  expectNegative("intent mismatch", (records) => {
    const value = web(records, 6); value.intentKey = "install_mod|other|"; setWeb(records, 6, value);
  }, "intent_tuple_mismatch", counters);
  expectNegative("same call", (records) => {
    const value = web(records, 4); value.webCallId = "preview.1"; setWeb(records, 4, value);
  }, "commit_call_chain_mismatch", counters);
  expectNegative("missing transaction", (records) => {
    records[5].line = records[5].line.replace("transactionIdPresent=true", "transactionIdPresent=false");
  }, "commit_contract_mismatch", counters);
  expectNegative("missing snapshot", (records) => {
    records[5].line = records[5].line.replace("snapshotPresent=true", "snapshotPresent=false");
  }, "commit_contract_mismatch", counters);
  expectNegative("missing state ref", (records) => {
    records[5].line = records[5].line.replace(
      "stateRef=sha256_bbbbbbbbbbbbbbbbbbbbbbbb",
      "stateRef=-"
    );
  }, "malformed_host_commit_settled", counters);
  expectNegative("commit failure", (records) => {
    records[5].line = records[5].line
      .replace("outcome=success", "outcome=error%3Atoken_expired")
      .replace("stateRef=sha256_bbbbbbbbbbbbbbbbbbbbbbbb", "stateRef=-")
      .replace("snapshotPresent=true", "snapshotPresent=false");
    const value = web(records, 6); value.success = false; setWeb(records, 6, value);
    records.splice(7, 1);
  }, "commit_outcome_not_success", counters);
  expectNegative("no op", (records) => {
    const value = web(records, 6); value.noOp = true; setWeb(records, 6, value);
  }, "commit_contract_mismatch", counters);
  expectNegative("adopt failure", (records) => {
    const value = web(records, 6); value.success = false; setWeb(records, 6, value);
  }, "commit_adopted_not_success", counters);
  expectNegative("requires reconcile", (records) => {
    const value = web(records, 6); value.requiresReconcile = true; setWeb(records, 6, value);
  }, "commit_contract_mismatch", counters);
  expectNegative("reconcile issued", (records) => {
    records.push({
      lineNumber: 19,
      line: "[WebDebug] " + JSON.stringify(fixtureWeb("reconcile_issued", {
        sequence: 7,
        webCallId: "reconcile.1",
        candidateKey: "",
        intentKey: "",
        pendingCount: 1,
        writeState: "reconcile_required",
        needsReconcile: true,
        reconcileAfterCallId: "commit.1",
      })),
    });
  }, "unexpected_reconcile_path", counters);
  expectNegative("refresh failed", (records) => {
    const value = web(records, 7); value.success = false; setWeb(records, 7, value);
  }, "refresh_contract_mismatch", counters);
  expectNegative("refresh same lease", (records) => {
    const value = web(records, 7); value.sourceKey = "inventory:背包:7:lease.old"; setWeb(records, 7, value);
  }, "refresh_contract_mismatch", counters);
  expectNegative("refresh cross slot", (records) => {
    const value = web(records, 7); value.sourceKey = "inventory:背包:8:lease.new"; setWeb(records, 7, value);
  }, "refresh_contract_mismatch", counters);
  expectNegative("refresh reconcile state", (records) => {
    const value = web(records, 7); value.needsReconcile = true; setWeb(records, 7, value);
  }, "refresh_contract_mismatch", counters);
  expectNegative("nonmonotonic sequence", (records) => {
    const value = web(records, 6); value.sequence = 3; setWeb(records, 6, value);
  }, "web_sequence_not_monotonic", counters);
  expectNegative("malformed debug", (records) => {
    records[1].line = "[WebDebug] {\"scope\":\"equipment_tuning\"";
  }, "malformed_equipment_tuning_debug", counters);
  expectNegative("host text inside web debug", (records) => {
    records[2].line = "[WebDebug] " + JSON.stringify({
      type: "debug",
      scope: "other",
      text: records[2].line,
    });
  }, "host_preview_settled_missing", counters);

  const identity = {
    runtimeMode: "isolated_candidate",
    processPath: path.join("C:\\", "check", "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
    coreSha256: "A".repeat(64),
    buildIdentity: "B".repeat(64),
    payloadClosure: "C".repeat(64),
  };
  assertIdentityFields(identity, deepCopy(identity), "check_identity");
  counters.positive += 1;
  ["runtimeMode", "processPath", "coreSha256", "buildIdentity", "payloadClosure"].forEach((field) => {
    let rejected = false;
    try {
      const changed = deepCopy(identity);
      changed[field] = field === "runtimeMode"
        ? "formal_runtime"
        : field === "processPath"
          ? path.join("C:\\", "other", "Core.exe")
          : "D".repeat(64);
      assertIdentityFields(identity, changed, "check_identity");
    } catch (error) {
      rejected = error.code === "runtime_identity_drift";
    }
    if (!rejected) throw new Error("identity drift fixture failed for " + field);
    counters.negative += 1;
  });
  let playerReportRejected = false;
  try {
    resolveOpenReport(path.join(root, "saves", "crazyflasher7_saves.json"));
  } catch (error) {
    playerReportRejected = error.code === "open_report_outside_opener_directory";
  }
  if (!playerReportRejected) {
    throw new Error("player save path was accepted as an opener report");
  }
  counters.negative += 1;

  const cloneContract = validateClonePreparationContract(
    fixtureClonePreparationReport()
  );
  if (cloneContract.prep.seededTargetSha256 !== "1".repeat(64)
      || cloneContract.baseline.sha256 !== "2".repeat(64)) {
    throw new Error("post-snapshot clone preparation positive fixture failed");
  }
  counters.positive += 1;
  [
    ["missing seed provenance", (report) => {
      delete report.savePreparation.seededTargetSha256;
    }],
    ["seed target hash overwritten", (report) => {
      report.savePreparation.targetSha256 = "2".repeat(64);
    }],
    ["baseline hash mismatch", (report) => {
      report.savePreparation.gateBaseline.sha256 = "3".repeat(64);
    }],
    ["short stability window", (report) => {
      report.savePreparation.gateBaseline.stableWindowMs = 999;
      report.timeline[1].stableWindowMs = 999;
    }],
    ["unverified regular file", (report) => {
      report.savePreparation.gateBaseline.regularFileVerified = false;
    }],
    ["single stable sample", (report) => {
      report.savePreparation.gateBaseline.stableSampleCount = 1;
      report.timeline[1].stableSampleCount = 1;
    }],
    ["file identity mismatch", (report) => {
      report.savePreparation.gateBaseline.fileId = "999";
    }],
    ["missing baseline phase", (report) => {
      report.timeline.splice(1, 1);
    }],
    ["duplicate baseline phase", (report) => {
      report.timeline.push(deepCopy(report.timeline[1]));
    }],
    ["baseline before snapshot", (report) => {
      report.savePreparation.gateBaseline.capturedAt = "2026-08-01T23:59:59.000Z";
      report.timeline[1].at = "2026-08-01T23:59:59.000Z";
    }],
    ["baseline after report finish", (report) => {
      report.finishedAt = "2026-08-02T00:00:01.000Z";
    }],
    ["seed delta mismatch", (report) => {
      report.timeline[1].changedFromSeed = false;
    }],
    ["missing startup archive", (report) => {
      report.savePreparation.gateBaseline.startupArchiveReceipt = null;
      report.timeline[1].startupArchiveLine = null;
    }],
    ["old startup archive", (report) => {
      report.savePreparation.gateBaseline.startupArchiveReceipt.lineNumber = 80;
      report.timeline[1].startupArchiveLine = 80;
    }],
    ["startup archive before title frame", (report) => {
      report.savePreparation.gateBaseline.startupArchiveReceipt.lineNumber = 87;
      report.timeline[1].startupArchiveLine = 87;
    }],
    ["title frame before handoff", (report) => {
      report.runtime.handoffEvidence.lineNumber = 89;
      report.runtime.titleFrameEvidence.lineNumber = 88;
      report.savePreparation.gateBaseline.archiveEvidenceFloorLine = 89;
      report.timeline[1].archiveEvidenceFloorLine = 89;
    }],
    ["wrong startup archive path", (report) => {
      report.savePreparation.gateBaseline.startupArchiveReceipt.targetPath = path.resolve(
        root,
        "saves",
        "crazyflasher7_saves2.json"
      );
    }],
    ["wrong startup archive chars", (report) => {
      report.savePreparation.gateBaseline.startupArchiveReceipt.archiveChars = 2999;
    }],
    ["snapshot tuple mismatch", (report) => {
      report.savePreparation.gateBaseline.snapshot.sourceKey =
        "inventory:背包:8:lease.fixture";
    }],
    ["startup semantic drift", (report) => {
      report.savePreparation.gateBaseline.semanticSha256 = "4".repeat(64);
    }],
    ["startup role drift", (report) => {
      report.savePreparation.gateBaseline.role = "other";
    }],
    ["missing title-frame floor", (report) => {
      delete report.runtime.titleFrameEvidence;
    }],
    ["post-capture watermark before snapshot", (report) => {
      report.savePreparation.gateBaseline.postCaptureLogWatermark.total = 99;
      report.timeline[1].postCaptureLogTotal = 99;
    }],
    ["last write after stable start", (report) => {
      report.savePreparation.gateBaseline.lastWriteTimeUtc =
        "2026-08-02T00:00:00.600Z";
    }],
  ].forEach(([name, mutate]) => {
    expectCloneContractNegative(name, mutate, counters);
  });

  const semanticData = {
    "0": ["fs", null, null, 99],
    inventory: { "背包": {} },
    lastSaved: "2026-08-02 08:00:00",
  };
  const semanticPreparation = {
    semanticSha256: opener.cloneSemanticSha256(semanticData),
    role: "fs",
    level: 99,
  };
  assertCloneSemanticContract(semanticData, semanticPreparation, "check_semantic");
  counters.positive += 1;
  let semanticMutationRejected = false;
  try {
    const changed = deepCopy(semanticData);
    changed["0"][3] = 98;
    assertCloneSemanticContract(changed, semanticPreparation, "check_semantic");
  } catch (error) {
    semanticMutationRejected = error && error.code === "clone_semantic_mismatch";
  }
  if (!semanticMutationRejected) {
    throw new Error("current clone semantic mutation fixture was accepted");
  }
  counters.negative += 1;

  const baselineData = {
    lastSaved: "2026-08-02 10:00:00",
    inventory: {
      "背包": Array.from({ length: 8 }, () => null),
    },
  };
  baselineData.inventory["背包"][7] = {
    name: "测试装备", lastUpdate: 100, value: { level: 1, mods: [] },
  };
  const afterData = deepCopy(baselineData);
  afterData.lastSaved = "2026-08-02 10:00:03";
  afterData.inventory["背包"][7].lastUpdate = 101;
  afterData.inventory["背包"][7].value.mods.push("测试插件");
  const baseline = {
    sha256: sha256(Buffer.from(JSON.stringify(baselineData))),
    data: baselineData,
    lastSaved: baselineData.lastSaved,
  };
  const archive = {
    lineNumber: 90,
    archiveChars: JSON.stringify(afterData).length,
    archivePath: path.join(root, "saves", SLOT + ".json"),
  };
  const diskLogFixture = logSnapshotFromText([
    "old-watermark",
    "event=equipment_tuning_commit_settled webCallId=commit.1",
    "[ArchiveTask] Shadow saved: " + SLOT + " (100 chars) path="
      + path.join(root, "saves", SLOT + ".json"),
    "",
  ].join("\r\n"));
  const diskArchive = findArchiveEvidence(
    opener.freshLogRecords({ total: 1 }, diskLogFixture),
    2,
    path.join(root, "saves", SLOT + ".json")
  );
  if (!diskArchive || diskArchive.lineNumber !== 3) {
    throw new Error("post-exit launcher.log archive fallback fixture failed");
  }
  const truncatedArchive = logSnapshotFromText([
    "old-watermark",
    "event=equipment_tuning_commit_settled webCallId=commit.1",
    "[ArchiveTask] Shadow saved: " + SLOT + " (100 chars) path=",
  ].join("\n"));
  if (findArchiveEvidence(
    opener.freshLogRecords({ total: 1 }, truncatedArchive),
    2,
    path.join(root, "saves", SLOT + ".json")
  )) {
    throw new Error("truncated archive log line was accepted");
  }
  const persisted = verifyPersistedClone(
    baseline,
    Buffer.from(JSON.stringify(afterData)),
    { containerId: "背包", slot: 7 },
    archive,
    true
  );
  if (!persisted.ok) throw new Error("persistence positive fixture failed");
  counters.positive += 1;
  [
    ["archive missing", "missing", true, afterData, "archive_shadow_receipt_missing"],
    ["process alive", "matching", false, afterData, "old_launcher_not_exited"],
    ["wrong final archive chars", "wrong", true, afterData, "archive_shadow_length_mismatch"],
    ["file unchanged", "matching", true, baselineData, "clone_file_unchanged"],
    ["lastSaved unchanged", "matching", true, Object.assign(deepCopy(afterData), {
      lastSaved: baselineData.lastSaved,
    }), "clone_last_saved_unchanged"],
    ["item timestamp unchanged", "matching", true, (() => {
      const value = deepCopy(afterData); value.inventory["背包"][7].lastUpdate = 100; return value;
    })(), "persisted_source_timestamp_unchanged"],
    ["item value unchanged", "matching", true, (() => {
      const value = deepCopy(afterData); value.inventory["背包"][7].value = { level: 1, mods: [] }; return value;
    })(), "persisted_source_value_unchanged"],
  ].forEach(([name, receiptKind, exited, value, code]) => {
    const valueText = JSON.stringify(value);
    const receipt = receiptKind === "missing" ? null : Object.assign({}, archive, {
      archiveChars: valueText.length + (receiptKind === "wrong" ? 1 : 0),
    });
    const check = verifyPersistedClone(
      baseline,
      Buffer.from(valueText),
      { containerId: "背包", slot: 7 },
      receipt,
      exited
    );
    if (check.ok || check.code !== code) {
      throw new Error(name + " expected " + code + " got " + JSON.stringify(check));
    }
    counters.negative += 1;
  });

  const reloadRecords = [{
    lineNumber: 100,
    line: "[EquipmentTuningTask] -> Flash: " + JSON.stringify({
      task: "cmd",
      action: "equipmentTuningSnapshot",
      callId: 1,
      v: 1,
      viewSessionId: "view.reload",
      source: {
        sourceKind: "inventory",
        containerId: "背包",
        slot: 7,
        expectedLeaseRef: "sha256_aaaaaaaaaaaaaaaaaaaaaaaa",
      },
      panelInstanceId: "panel.reload",
      writeEpoch: 0,
      requestCallId: "reload.1",
    }),
  }, {
    lineNumber: 101,
    line: "event=equipment_tuning_snapshot_confirmed callId=reload.1"
      + " panelInstanceId=panel.reload viewSessionId=view.reload"
      + " sourceKeyRef=sha256_cccccccccccccccccccccccc"
      + " stateRef=sha256_bbbbbbbbbbbbbbbbbbbbbbbb writeEpoch=0",
  }];
  const reloadExpected = {
    panelInstanceId: "panel.reload",
    viewSessionId: "view.reload",
    source: { containerId: "背包", slot: 7 },
    stateRef: "sha256_bbbbbbbbbbbbbbbbbbbbbbbb",
  };
  if (!parseReloadEvidence(reloadRecords, reloadExpected).ok) {
    throw new Error("reload positive fixture failed");
  }
  assertReloadProcessInventory([], null, "check_reload_before_start");
  assertReloadProcessInventory([
    { pid: 4321, processPath: "fixture" },
  ], 4321, "check_reload_identity");
  counters.positive += 1;
  [
    ["residual Launcher without port", [
      { pid: 1111, processPath: "fixture-residual" },
    ], null],
    ["second Launcher during reload", [
      { pid: 4321, processPath: "fixture" },
      { pid: 5678, processPath: "fixture-second" },
    ], 4321],
  ].forEach(([name, processes, expectedPid]) => {
    let rejected = false;
    try {
      assertReloadProcessInventory(processes, expectedPid, "check_reload_processes");
    } catch (error) {
      rejected = error && error.code === "reload_launcher_process_not_exclusive";
    }
    if (!rejected) {
      throw new Error(name + " process inventory fixture was accepted");
    }
    counters.negative += 1;
  });
  [
    ["reload source", "slot", '"slot":8', "persisted_state_readback_missing"],
    ["reload state", "stateRef", "sha256_dddddddddddddddddddddddd",
      "persisted_state_readback_missing"],
    ["reload panel", "panelInstanceId", "panel.other", "reload_cross_session_snapshot"],
  ].forEach(([name, field, replacement, code]) => {
    const records = deepCopy(reloadRecords);
    const patterns = {
      slot: /"slot":7/,
      stateRef: /stateRef=\S+/,
      panelInstanceId: /panelInstanceId=\S+/,
    };
    const index = field === "slot" ? 0 : 1;
    records[index].line = records[index].line.replace(
      patterns[field],
      field === "slot" ? replacement : field + "=" + replacement
    );
    const check = parseReloadEvidence(records, reloadExpected);
    if (check.ok || check.code !== code) {
      throw new Error(name + " expected " + code + " got " + JSON.stringify(check));
    }
    counters.negative += 1;
  });

  const missingReloadRequest = parseReloadEvidence([reloadRecords[1]], reloadExpected);
  if (missingReloadRequest.ok
      || missingReloadRequest.code !== "persisted_state_readback_missing") {
    throw new Error("reload snapshot without coordinate request was accepted");
  }
  counters.negative += 1;

  console.log(JSON.stringify({
    ok: true,
    gate: GATE,
    positive: counters.positive,
    negative: counters.negative,
    total: counters.positive + counters.negative,
    scope: "offline_contract_only_no_save_or_runtime_access",
  }, null, 2));
  return counters;
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  if (args.check) return runOfflineChecks();
  return runJourney(args);
}

module.exports = {
  assertCloneMatchesBaseline,
  assertCloneSemanticContract,
  assertIdentityFields,
  assertReloadProcessInventory,
  parseArgs,
  parseHostCommit,
  parseHostSnapshot,
  parseWeb,
  runOfflineChecks,
  validateClonePreparationContract,
  verifyCommitEvidence,
  verifyPersistedClone,
  parseReloadEvidence,
};

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    const code = error && error.code ? error.code : "unexpected_error";
    const receipt = error && error.receiptPath ? " receipt=" + error.receiptPath : "";
    console.error(code + ": " + error.message + receipt);
    process.exit(error && error.phase === "arguments" ? 2 : 1);
  });
}
