#!/usr/bin/env node
"use strict";

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

const root = path.resolve(__dirname, "../..");
const LOG_TAIL_LIMIT = 2000;
const TOKEN = /^[A-Za-z0-9._-]{1,160}$/;
const HASH = /^[A-Fa-f0-9]{64}$/;
const WEB_EVENTS = new Set([
  "candidate_hit",
  "preview_issued",
  "preview_adopted",
]);
const FORBIDDEN_WRITE_EVENTS = new Set([
  "commit_issued",
  "commit_adopted",
  "inventory_refresh_settled",
  "reconcile_issued",
  "reconcile_adopted",
]);

class JourneyError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "JourneyError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
  }
}

function fail(code, phase, message, details) {
  throw new JourneyError(code, phase, message, details);
}

function parseArgs(argv) {
  const args = {
    check: false,
    help: false,
    openReport: null,
    timeoutMs: 180000,
    pollMs: 250,
    settleMs: 1000,
  };
  function valueAfter(index, flag) {
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
    else if (token === "--open-report") args.openReport = valueAfter(index++, token);
    else if (token === "--timeout-ms") args.timeoutMs = Number(valueAfter(index++, token));
    else if (token === "--poll-ms") args.pollMs = Number(valueAfter(index++, token));
    else if (token === "--settle-ms") args.settleMs = Number(valueAfter(index++, token));
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
  if (!Number.isInteger(args.timeoutMs)
      || args.timeoutMs < 1000 || args.timeoutMs > 600000) {
    fail("invalid_timeout", "arguments", "--timeout-ms must be 1000..600000");
  }
  if (!Number.isInteger(args.pollMs)
      || args.pollMs < 100 || args.pollMs > 10000) {
    fail("invalid_poll", "arguments", "--poll-ms must be 100..10000");
  }
  if (!Number.isInteger(args.settleMs)
      || args.settleMs < 1000 || args.settleMs > 5000) {
    fail("invalid_settle", "arguments", "--settle-ms must be 1000..5000");
  }
  return args;
}

function printHelp() {
  console.log([
    "Equipment Tuning preview journey verifier",
    "",
    "Usage:",
    "  node tools/equipment-tuning/verify-journey.js --open-report <run-report.json>",
    "",
    "Options:",
    "  --timeout-ms <ms>  Wait for a real computer-use click (default 180000).",
    "  --poll-ms <ms>     Host log polling interval (default 250).",
    "  --settle-ms <ms>   Reject auto-commit during this quiet window (default 1000).",
    "  --check            Run positive and negative offline fixtures.",
    "",
    "This gate verifies preview only. It never clicks UI and never sends business commands.",
  ].join("\n"));
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isToken(value) {
  return typeof value === "string" && TOKEN.test(value);
}

function isNonEmptyBounded(value, limit) {
  return typeof value === "string"
    && value.length > 0
    && value.length <= limit
    && !/[\u0000-\u001f\u007f]/.test(value);
}

function readJsonFile(filePath, code) {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(code, "open_report", "cannot read JSON: " + filePath, {
      message: error.message,
    });
  }
  return parsed;
}

function pathWithin(basePath, targetPath) {
  const relative = path.relative(basePath, targetPath);
  return !!relative
    && !relative.startsWith(".." + path.sep)
    && relative !== ".."
    && !path.isAbsolute(relative);
}

function resolveOpenReport(value) {
  const filePath = path.isAbsolute(value) ? value : path.resolve(root, value);
  const allowedRoot = path.join(root, "tmp", "equipment-tuning", "unattended");
  const relative = path.relative(allowedRoot, filePath);
  const parts = relative.split(path.sep).filter(Boolean);
  if (!pathWithin(allowedRoot, filePath)
      || parts.length !== 2
      || parts[1].toLowerCase() !== "run-report.json") {
    fail(
      "open_report_outside_opener_directory",
      "open_report",
      "open report must be the canonical opener run-report.json under tmp/equipment-tuning/unattended"
    );
  }
  try {
    const runDirectory = path.dirname(filePath);
    [
      path.join(root, "tmp"),
      path.join(root, "tmp", "equipment-tuning"),
      allowedRoot,
      runDirectory,
    ].forEach((directory) => {
      const stat = fs.lstatSync(directory);
      if (!stat.isDirectory() || stat.isSymbolicLink()) {
        fail(
          "open_report_reparse_or_not_regular",
          "open_report",
          "opener report path must contain only regular directories and a regular file"
        );
      }
    });
    const reportStat = fs.lstatSync(filePath);
    if (!reportStat.isFile() || reportStat.isSymbolicLink()) {
      fail(
        "open_report_reparse_or_not_regular",
        "open_report",
        "opener report path must contain only regular directories and a regular file"
      );
    }
    const realRoot = fs.realpathSync.native(root);
    const realAllowed = fs.realpathSync.native(allowedRoot);
    const realReport = fs.realpathSync.native(filePath);
    if (!pathWithin(realRoot, realAllowed) || !pathWithin(realAllowed, realReport)) {
      fail(
        "open_report_realpath_escape",
        "open_report",
        "opener report real path escaped the canonical opener directory"
      );
    }
  } catch (error) {
    if (error && error.code && error.phase) throw error;
    fail("open_report_not_found", "open_report", "open report not found: " + filePath);
  }
  return filePath;
}

function validateOpenReport(report) {
  if (!isObject(report)
      || report.schema !== "equipment-tuning.unattended-run.v1"
      || report.status !== "snapshot_gate_reached") {
    fail(
      "open_report_not_snapshot_gate",
      "open_report",
      "the opener report did not reach the production snapshot gate"
    );
  }
  const scope = report.scope;
  if (!isObject(scope)
      || scope.productionOpenerOnly !== true
      || scope.uiBusinessClicks !== false
      || scope.businessWritesAttempted !== false
      || scope.stopAfterSnapshot !== true
      || scope.gate !== "active_workbench_and_first_tuning_snapshot") {
    fail(
      "open_report_scope_mismatch",
      "open_report",
      "the source report is not the zero-business-click production opener"
    );
  }
  if (report.shutdownResponse) {
    fail(
      "opener_already_shutdown",
      "open_report",
      "the opener used --shutdown; rerun it without --shutdown before preview verification"
    );
  }
  const timeline = Array.isArray(report.timeline) ? report.timeline : [];
  const finalIdentityPhases = timeline.filter((entry) => isObject(entry)
    && entry.phase === "runtime_identity_reverified_after_clone_baseline");
  if (finalIdentityPhases.length !== 1
      || !Number.isFinite(Date.parse(finalIdentityPhases[0].at))
      || !Number.isFinite(Date.parse(report.finishedAt))
      || Date.parse(finalIdentityPhases[0].at) > Date.parse(report.finishedAt)) {
    fail(
      "opener_final_identity_missing",
      "open_report",
      "the opener did not reverify runtime identity after closing its clone baseline"
    );
  }
  const identity = report.runtimeIdentity;
  if (!isObject(identity)
      || identity.verified !== true
      || !/^(formal_runtime|isolated_candidate)$/.test(identity.runtimeMode || "")
      || !isNonEmptyBounded(identity.processPath, 1024)
      || !HASH.test(identity.coreSha256 || "")
      || !HASH.test(identity.buildIdentity || "")
      || !HASH.test(identity.payloadClosure || "")
      || !Number.isInteger(identity.pid) || identity.pid <= 0) {
    fail(
      "runtime_identity_unverified",
      "open_report",
      "the opener report lacks a verified formal/isolated runtime identity"
    );
  }
  if (finalIdentityPhases[0].pid !== identity.pid
      || String(finalIdentityPhases[0].coreSha256 || "").toUpperCase()
        !== String(identity.coreSha256).toUpperCase()) {
    fail(
      "opener_final_identity_mismatch",
      "open_report",
      "the final post-baseline identity receipt does not match the opener runtime"
    );
  }
  const expectedIdentity = identity.expected;
  if (!isObject(expectedIdentity)
      || expectedIdentity.runtimeMode !== identity.runtimeMode
      || expectedIdentity.processPath !== identity.processPath
      || String(expectedIdentity.coreSha256 || "").toUpperCase()
        !== String(identity.coreSha256).toUpperCase()
      || String(expectedIdentity.buildIdentity || "").toUpperCase()
        !== String(identity.buildIdentity).toUpperCase()
      || String(expectedIdentity.payloadClosure || "").toUpperCase()
        !== String(identity.payloadClosure).toUpperCase()) {
    fail(
      "runtime_identity_expected_actual_mismatch",
      "open_report",
      "the opener runtime identity does not match its expected identity"
    );
  }
  if (!Number.isInteger(report.httpPort)
      || report.httpPort < 1 || report.httpPort > 65535
      || identity.httpPort !== report.httpPort) {
    fail("runtime_http_port_mismatch", "open_report", "runtime HTTP port is not exact");
  }
  const watermark = report.openLogWatermark;
  if (!isObject(watermark)
      || !Number.isInteger(watermark.total) || watermark.total < 0
      || !isNonEmptyBounded(watermark.capturedAt, 80)
      || !Number.isFinite(Date.parse(watermark.capturedAt))) {
    fail("open_watermark_invalid", "open_report", "open log watermark is malformed");
  }
  const evidence = report.snapshotGate && report.snapshotGate.evidence;
  const active = evidence && evidence.activeWorkbench;
  const snapshot = evidence && evidence.tuningSnapshot;
  if (!isObject(active) || !isObject(snapshot)
      || !isToken(active.panelInstanceId)
      || active.panelInstanceId !== snapshot.panelInstanceId
      || !isToken(snapshot.viewSessionId)
      || !isNonEmptyBounded(snapshot.sourceKey, 1024)
      || !/^sha256_[a-f0-9]{24}$/.test(snapshot.stateRef || "")
      || !Number.isInteger(active.lineNumber)
      || !Number.isInteger(snapshot.lineNumber)
      || active.lineNumber <= watermark.total
      || snapshot.lineNumber <= active.lineNumber) {
    fail(
      "snapshot_tuple_invalid",
      "open_report",
      "panel/view snapshot evidence is not fresh and exactly correlated"
    );
  }
  return {
    httpPort: report.httpPort,
    pid: identity.pid,
    runtimeIdentity: {
      runtimeMode: identity.runtimeMode,
      processPath: identity.processPath,
      coreSha256: identity.coreSha256.toUpperCase(),
      buildIdentity: identity.buildIdentity.toUpperCase(),
      payloadClosure: identity.payloadClosure.toUpperCase(),
      pid: identity.pid,
      httpPort: identity.httpPort,
      verified: true,
    },
    watermark: {
      total: watermark.total,
      capturedAt: watermark.capturedAt,
    },
    panelInstanceId: active.panelInstanceId,
    viewSessionId: snapshot.viewSessionId,
    sourceKey: snapshot.sourceKey,
    stateRef: snapshot.stateRef,
    snapshotLineNumber: snapshot.lineNumber,
  };
}

function decodeLogField(value) {
  if (value === null || value === undefined || value === "-") return "";
  try {
    return decodeURIComponent(String(value));
  } catch (_error) {
    return null;
  }
}

function hostLogBody(record) {
  if (!record || typeof record.line !== "string"
      || record.line.includes("[WebDebug]")) return null;
  return record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
}

function parseWebDebug(record) {
  if (!record || typeof record.line !== "string") return null;
  const marker = "[WebDebug] ";
  const markerIndex = record.line.indexOf(marker);
  if (markerIndex < 0) return null;
  const text = record.line.slice(markerIndex + marker.length).trim();
  let message;
  try {
    message = JSON.parse(text);
  } catch (_error) {
    if (text.includes("equipment_tuning")) {
      return { invalid: "malformed_equipment_tuning_web_debug", lineNumber: record.lineNumber };
    }
    return null;
  }
  if (!isObject(message) || message.scope !== "equipment_tuning") return null;
  if (FORBIDDEN_WRITE_EVENTS.has(message.event)) {
    if (message.type !== "debug"
        || !isToken(message.panelInstanceId)
        || !isToken(message.viewSessionId)) {
      return {
        invalid: "malformed_forbidden_write_event",
        lineNumber: record.lineNumber,
      };
    }
    return {
      kind: "forbidden_write",
      event: message.event,
      lineNumber: record.lineNumber,
      panelInstanceId: message.panelInstanceId,
      viewSessionId: message.viewSessionId,
      webCallId: isToken(message.webCallId) ? message.webCallId : "",
    };
  }
  if (!WEB_EVENTS.has(message.event)) return null;
  const requiredBooleans = typeof message.tokenPresent === "boolean"
    && typeof message.commitReady === "boolean";
  if (message.type !== "debug"
      || !isToken(message.panelInstanceId)
      || !isToken(message.viewSessionId)
      || !isNonEmptyBounded(message.sourceKey, 180)
      || !isNonEmptyBounded(message.candidateKey, 180)
      || !/^[a-z_]{1,40}$/.test(message.operation || "")
      || !Number.isInteger(message.pendingCount) || message.pendingCount < 0
      || !requiredBooleans) {
    return { invalid: "malformed_" + message.event, lineNumber: record.lineNumber };
  }
  const callRequired = message.event !== "candidate_hit";
  const intentRequired = message.event !== "candidate_hit";
  if ((callRequired && !isToken(message.webCallId))
      || (!callRequired && message.webCallId && !isToken(message.webCallId))
      || (intentRequired && !isNonEmptyBounded(message.intentKey, 384))
      || (!intentRequired && message.intentKey
        && !isNonEmptyBounded(message.intentKey, 384))
      || !/^(safe|fast)$/.test(message.confirmationMode || "")
      || typeof message.autoCommitPending !== "boolean"
      || !/^(idle|read_pending|write_pending|reconcile_required|refresh_pending|refresh_required)$/.test(
        message.writeState || ""
      )
      || typeof message.needsReconcile !== "boolean") {
    return { invalid: "malformed_" + message.event, lineNumber: record.lineNumber };
  }
  return {
    kind: "web_debug",
    event: message.event,
    lineNumber: record.lineNumber,
    sequence: Number.isInteger(message.sequence) ? message.sequence : null,
    webCallId: message.webCallId || "",
    panelInstanceId: message.panelInstanceId,
    viewSessionId: message.viewSessionId,
    sourceKey: message.sourceKey,
    candidateKey: message.candidateKey,
    operation: message.operation,
    intentKey: message.intentKey || "",
    pendingCount: message.pendingCount,
    tokenPresent: message.tokenPresent,
    commitReady: message.commitReady,
    confirmationMode: message.confirmationMode,
    autoCommitPending: message.autoCommitPending,
    writeState: message.writeState,
    needsReconcile: message.needsReconcile,
  };
}

function parseHostSettled(record) {
  const body = hostLogBody(record);
  if (!body || !body.startsWith("event=equipment_tuning_preview_settled ")) return null;
  function field(name) {
    return decodeLogField(opener.extractLogField(record.line, name));
  }
  const flashCallId = Number(field("flashCallId"));
  const remainingPending = Number(field("remainingPending"));
  const result = {
    kind: "host_settled",
    event: "equipment_tuning_preview_settled",
    lineNumber: record.lineNumber,
    webCallId: field("webCallId"),
    requestCallId: field("requestCallId"),
    flashCallId,
    tokenRef: field("tokenRef"),
    panelInstanceId: field("panelInstanceId"),
    viewSessionId: field("viewSessionId"),
    sourceKey: field("sourceKey"),
    candidateKey: field("candidateKey"),
    operation: field("operation"),
    intentKey: field("intentKey"),
    outcome: field("outcome"),
    remainingPending,
  };
  if (!isToken(result.webCallId)
      || result.requestCallId !== result.webCallId
      || !Number.isInteger(flashCallId) || flashCallId <= 0
      || !/^sha256_[a-f0-9]{24}$/.test(result.tokenRef || "")
      || !isToken(result.panelInstanceId)
      || !isToken(result.viewSessionId)
      || !isNonEmptyBounded(result.sourceKey, 180)
      || !isNonEmptyBounded(result.candidateKey, 180)
      || !/^[a-z_]{1,40}$/.test(result.operation || "")
      || !isNonEmptyBounded(result.intentKey, 384)
      || !isNonEmptyBounded(result.outcome, 200)
      || !Number.isInteger(remainingPending) || remainingPending < 0) {
    return { invalid: "malformed_host_preview_settled", lineNumber: record.lineNumber };
  }
  return result;
}

function parseHostForbiddenWrite(record) {
  const body = hostLogBody(record);
  if (!body || !body.startsWith("event=equipment_tuning_commit_settled ")) return null;
  function field(name) {
    return decodeLogField(opener.extractLogField(body, name));
  }
  const result = {
    kind: "forbidden_write",
    event: "equipment_tuning_commit_settled",
    lineNumber: record.lineNumber,
    panelInstanceId: field("panelInstanceId"),
    viewSessionId: field("viewSessionId"),
    webCallId: field("webCallId"),
    previewWebCallId: field("previewWebCallId"),
    tokenRef: field("tokenRef"),
  };
  if (!isToken(result.panelInstanceId)
      || !isToken(result.viewSessionId)
      || !isToken(result.webCallId)) {
    return { invalid: "malformed_host_commit_settled", lineNumber: record.lineNumber };
  }
  return result;
}

function sameCoreTuple(left, right, includeIntent) {
  return left.panelInstanceId === right.panelInstanceId
    && left.viewSessionId === right.viewSessionId
    && left.sourceKey === right.sourceKey
    && left.candidateKey === right.candidateKey
    && left.operation === right.operation
    && (!includeIntent || left.intentKey === right.intentKey);
}

function failedCheck(code, observed) {
  return { ok: false, code, observed: observed || {} };
}

function verifyPreviewEvidence(records, anchor) {
  const evidenceFloor = Math.max(
    anchor.watermark.total,
    Number.isInteger(anchor.snapshotLineNumber)
      ? anchor.snapshotLineNumber : anchor.watermark.total
  );
  const fresh = (records || []).filter((record) => (
    record && Number.isInteger(record.lineNumber)
      && record.lineNumber > evidenceFloor
  ));
  const parsed = [];
  fresh.forEach((record) => {
    const web = parseWebDebug(record);
    if (web) parsed.push(web);
    const host = parseHostSettled(record);
    if (host) parsed.push(host);
    const hostWrite = parseHostForbiddenWrite(record);
    if (hostWrite) parsed.push(hostWrite);
  });
  const invalid = parsed.find((event) => event.invalid);
  if (invalid) {
    return Object.assign(
      failedCheck(invalid.invalid, { lineNumber: invalid.lineNumber }),
      { fatal: true }
    );
  }

  const forbiddenWrite = parsed.find((event) => (
    event.kind === "forbidden_write"
      && event.panelInstanceId === anchor.panelInstanceId
      && event.viewSessionId === anchor.viewSessionId
  ));
  if (forbiddenWrite) {
    return Object.assign(failedCheck("business_write_observed", {
      event: forbiddenWrite.event,
      lineNumber: forbiddenWrite.lineNumber,
      webCallId: forbiddenWrite.webCallId,
    }), { fatal: true });
  }

  const webEvents = parsed.filter((event) => event.kind === "web_debug");
  const hostEvents = parsed.filter((event) => event.kind === "host_settled");
  const unsafeMode = webEvents.find((event) => (
    event.panelInstanceId === anchor.panelInstanceId
      && event.viewSessionId === anchor.viewSessionId
      && (event.confirmationMode !== "safe" || event.autoCommitPending !== false)
  ));
  if (unsafeMode) {
    return Object.assign(failedCheck("unsafe_confirmation_mode_observed", {
      event: unsafeMode.event,
      lineNumber: unsafeMode.lineNumber,
      confirmationMode: unsafeMode.confirmationMode,
      autoCommitPending: unsafeMode.autoCommitPending,
    }), { fatal: true });
  }
  const hits = webEvents.filter((event) => (
    event.event === "candidate_hit"
      && event.panelInstanceId === anchor.panelInstanceId
      && event.viewSessionId === anchor.viewSessionId
  ));
  if (hits.length === 0) {
    return failedCheck("candidate_hit_missing_after_watermark", {
      freshRecords: fresh.length,
    });
  }

  for (const hit of hits) {
    const issuedEvents = webEvents.filter((event) => (
      event.event === "preview_issued"
        && event.lineNumber > hit.lineNumber
        && sameCoreTuple(hit, event, false)
        && (!hit.webCallId || hit.webCallId === event.webCallId)
        && (!hit.intentKey || hit.intentKey === event.intentKey)
        && event.pendingCount >= 1
    ));
    for (const issued of issuedEvents) {
      const adopted = webEvents.find((event) => (
        event.event === "preview_adopted"
          && event.lineNumber > issued.lineNumber
          && event.webCallId === issued.webCallId
          && sameCoreTuple(issued, event, true)
          && event.pendingCount === 0
          && event.tokenPresent === true
          && event.commitReady === true
          && event.confirmationMode === "safe"
          && event.autoCommitPending === false
          && event.writeState === "idle"
          && event.needsReconcile === false
      ));
      const settled = hostEvents.find((event) => (
        event.lineNumber > issued.lineNumber
          && event.webCallId === issued.webCallId
          && sameCoreTuple(issued, event, true)
          && event.outcome === "success"
      ));
      if (adopted && settled) {
        return {
          ok: true,
          exactTuple: {
            webCallId: issued.webCallId,
            flashCallId: settled.flashCallId,
            panelInstanceId: issued.panelInstanceId,
            viewSessionId: issued.viewSessionId,
            sourceKey: issued.sourceKey,
            candidateKey: issued.candidateKey,
            operation: issued.operation,
            intentKey: issued.intentKey,
          },
          evidence: {
            candidateHit: hit,
            previewIssued: issued,
            hostSettled: settled,
            previewAdopted: adopted,
          },
          assertions: {
            eventsAfterOpenWatermark: true,
            eventsAfterInitialSnapshot: true,
            exactPanelAndView: true,
            exactSourceCandidateOperationIntent: true,
            exactWebCallIdAcrossWebAndHost: true,
            hostOutcomeSuccess: true,
            adoptedPendingCountZero: true,
            adoptedTokenPresent: true,
            adoptedCommitReady: true,
            confirmationModeSafe: true,
            autoCommitPendingFalse: true,
            adoptedWriteStateIdle: true,
            adoptedNeedsReconcileFalse: true,
          },
        };
      }
    }
  }

  const anchorIssued = webEvents.filter((event) => (
    event.event === "preview_issued"
      && event.panelInstanceId === anchor.panelInstanceId
      && event.viewSessionId === anchor.viewSessionId
  ));
  if (anchorIssued.length === 0) {
    return failedCheck("preview_issued_missing_or_tuple_mismatch", {
      candidateHits: hits.length,
    });
  }
  const anchorAdopted = webEvents.filter((event) => (
    event.event === "preview_adopted"
      && event.panelInstanceId === anchor.panelInstanceId
      && event.viewSessionId === anchor.viewSessionId
  ));
  if (anchorAdopted.length === 0) {
    return failedCheck("preview_adopted_missing_or_tuple_mismatch", {
      previewIssued: anchorIssued.length,
    });
  }
  if (hostEvents.length === 0) {
    return failedCheck("host_preview_settled_missing", {
      previewIssued: anchorIssued.length,
      previewAdopted: anchorAdopted.length,
    });
  }
  return failedCheck("preview_exact_tuple_not_closed", {
    candidateHits: hits.length,
    previewIssued: anchorIssued.length,
    previewAdopted: anchorAdopted.length,
    hostSettled: hostEvents.length,
  });
}

function requestLogs(context) {
  const pathname = "/logs?lines=" + LOG_TAIL_LIMIT;
  const headers = LegacyHttpClient.authorizationHeadersFor(context, pathname);
  return new Promise((resolve, reject) => {
    const request = http.request({
      hostname: "localhost",
      port: context.httpPort,
      path: pathname,
      method: "GET",
      timeout: 5000,
      headers,
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        let parsed;
        try {
          parsed = JSON.parse(text);
        } catch (_error) {
          reject(new JourneyError(
            "logs_non_json",
            "logs",
            "/logs returned non-JSON HTTP " + response.statusCode
          ));
          return;
        }
        if (response.statusCode !== 200
            || parsed.success !== true
            || !Number.isInteger(parsed.total)
            || !Array.isArray(parsed.lines)) {
          reject(new JourneyError(
            "logs_unavailable",
            "logs",
            "/logs did not return a usable snapshot",
            { statusCode: response.statusCode }
          ));
          return;
        }
        resolve({
          total: parsed.total,
          lines: parsed.lines.map((line) => String(line)),
          capturedAt: new Date().toISOString(),
        });
      });
    });
    request.on("timeout", () => request.destroy(new Error("/logs timed out")));
    request.on("error", reject);
    request.end();
  });
}

function assertContextMatchesAnchor(context, anchor) {
  if (context.pid !== anchor.pid || context.httpPort !== anchor.httpPort) {
    fail(
      "runtime_process_changed",
      "runtime_continuity",
      "Launcher PID/HTTP port changed after the verified opener",
      {
        expectedPid: anchor.pid,
        actualPid: context.pid,
        expectedHttpPort: anchor.httpPort,
        actualHttpPort: context.httpPort,
      }
    );
  }
  return true;
}

function expectedRuntimeIdentity(anchor) {
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

function exactLiveContext(anchor) {
  let context;
  try {
    context = LegacyHttpClient.readExactLauncherHttpContext(root);
  } catch (error) {
    fail("launcher_context_unavailable", "runtime_continuity", error.message);
  }
  assertContextMatchesAnchor(context, anchor);
  return context;
}

function exactLiveRuntime(anchor, phase) {
  const context = exactLiveContext(anchor);
  let actual;
  try {
    actual = verifyRuntimeIdentity(
      root,
      anchor.httpPort,
      expectedRuntimeIdentity(anchor)
    );
  } catch (error) {
    fail(
      "runtime_identity_drift",
      phase,
      "full runtime identity verification failed: " + error.message,
      error.details || null
    );
  }
  if (actual.pid !== anchor.pid || actual.httpPort !== anchor.httpPort) {
    fail(
      "runtime_process_changed",
      phase,
      "identity probe observed a different Launcher PID/HTTP port"
    );
  }
  opener.assertExclusiveLauncherProcess(
    opener.queryLauncherCoreProcesses(),
    actual.pid
  );
  return { context, identity: publicRuntimeIdentity(actual) };
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForPreview(context, anchor, timeoutMs, pollMs, settleMs) {
  const deadline = Date.now() + timeoutMs;
  let lastCheck = failedCheck("fresh_evidence_not_observed");
  let lastSnapshot = null;
  let validSince = null;
  while (Date.now() <= deadline) {
    lastSnapshot = await requestLogs(context);
    const records = opener.freshLogRecords(anchor.watermark, lastSnapshot);
    lastCheck = verifyPreviewEvidence(records, anchor);
    if (lastCheck.fatal) {
      fail(lastCheck.code, "preview", "preview-only boundary was violated", lastCheck.observed);
    }
    if (lastCheck.ok) {
      if (validSince === null) validSince = Date.now();
      if (Date.now() - validSince >= settleMs) {
        return {
          result: lastCheck,
          finalLogTotal: lastSnapshot.total,
          capturedAt: lastSnapshot.capturedAt,
          settleMs,
        };
      }
    } else {
      validSince = null;
    }
    await sleep(pollMs);
  }
  fail(
    "preview_evidence_timeout",
    "preview",
    "no exact preview journey closed before timeout",
    {
      lastCheck,
      finalLogTotal: lastSnapshot ? lastSnapshot.total : null,
    }
  );
}

function outputDirectory() {
  const stamp = new Date().toISOString().replace(/[-:.]/g, "").replace("Z", "Z");
  return path.join(
    root,
    "tmp",
    "equipment-tuning",
    "journeys",
    stamp + "-" + String(process.pid)
  );
}

function relativeToRoot(filePath) {
  return path.relative(root, filePath).replace(/\\/g, "/");
}

function serializeError(error) {
  return {
    code: error && error.code ? error.code : "unexpected_error",
    phase: error && error.phase ? error.phase : "unexpected",
    message: error && error.message ? error.message : String(error),
    details: error && error.details ? error.details : null,
  };
}

function formatMarkdown(receipt) {
  const lines = [
    "# Equipment Tuning preview journey receipt",
    "",
    "- Gate: `PG-TUNE-PREVIEW`",
    "- Status: `" + receipt.status + "`",
    "- Coverage: `preview_only`",
    "- Open report: `" + (receipt.openReport || "") + "`",
    "- Runtime mode: `" + (receipt.opener.runtimeIdentity
      ? receipt.opener.runtimeIdentity.runtimeMode : "") + "`",
    "- Runtime identity verified by opener: `" + String(
      !!(receipt.opener.runtimeIdentity && receipt.opener.runtimeIdentity.verified)
    ) + "`",
    "- Build identity: `" + (receipt.opener.runtimeIdentity
      ? receipt.opener.runtimeIdentity.buildIdentity : "") + "`",
    "- Payload closure: `" + (receipt.opener.runtimeIdentity
      ? receipt.opener.runtimeIdentity.payloadClosure : "") + "`",
    "- Launcher process continuity: `" + String(
      receipt.runtimeContinuity.verified === true
    ) + "`",
    "- Full runtime identity reverified before/after preview: `" + String(
      receipt.runtimeContinuity.fullIdentityReverified === true
    ) + "`",
    "- Panel instance: `" + (receipt.opener.panelInstanceId || "") + "`",
    "- View session: `" + (receipt.opener.viewSessionId || "") + "`",
    "- Open watermark: `" + (receipt.opener.openLogWatermark
      ? receipt.opener.openLogWatermark.total : "") + "`",
    "",
  ];
  if (receipt.exactTuple) {
    lines.push("## Exact preview tuple", "");
    Object.keys(receipt.exactTuple).forEach((key) => {
      lines.push("- " + key + ": `" + String(receipt.exactTuple[key]) + "`");
    });
    lines.push("");
  }
  if (receipt.evidence) {
    lines.push("## Fresh evidence lines", "");
    lines.push("- candidate_hit: `" + receipt.evidence.candidateHit.lineNumber + "`");
    lines.push("- preview_issued: `" + receipt.evidence.previewIssued.lineNumber + "`");
    lines.push("- Host preview_settled: `" + receipt.evidence.hostSettled.lineNumber + "`");
    lines.push("- preview_adopted: `" + receipt.evidence.previewAdopted.lineNumber + "`", "");
  }
  if (receipt.error) {
    lines.push("## Failure", "", "- Code: `" + receipt.error.code + "`");
    lines.push("- Phase: `" + receipt.error.phase + "`");
    lines.push("- Message: " + receipt.error.message, "");
  }
  lines.push(
    "## Coverage boundary",
    "",
    "This receipt proves only a fresh, exact preview journey after the opener watermark. "
      + "It does not prove commit, inventory reconciliation, persistence, or save integrity.",
    "",
    "A separate clone-save commit receipt is required before any commit/reconcile E2E claim.",
    ""
  );
  return lines.join("\n");
}

function writeReceipt(receipt, directory) {
  fs.mkdirSync(directory, { recursive: true });
  const jsonPath = path.join(directory, "journey-receipt.json");
  const markdownPath = path.join(directory, "journey-receipt.md");
  receipt.receiptPath = relativeToRoot(jsonPath);
  receipt.receiptMarkdownPath = relativeToRoot(markdownPath);
  fs.writeFileSync(jsonPath, JSON.stringify(receipt, null, 2) + "\n", "utf8");
  fs.writeFileSync(markdownPath, formatMarkdown(receipt), "utf8");
  return { jsonPath, markdownPath };
}

function fixtureWeb(lineNumber, event, overrides) {
  const base = {
    type: "debug",
    scope: "equipment_tuning",
    sequence: lineNumber,
    event,
    operation: "install_mod",
    webCallId: event === "candidate_hit" ? "" : "tune.fixture.1",
    panelInstanceId: "panel.fixture.1",
    viewSessionId: "view.fixture.1",
    sourceKey: "inventory:背包:24:lease.fixture",
    candidateKey: "mod.25",
    intentKey: event === "candidate_hit" ? "" : "install_mod|mod.25|",
    pendingCount: event === "preview_issued" ? 1 : 0,
    tokenPresent: event === "preview_adopted",
    commitReady: event === "preview_adopted",
    confirmationMode: "safe",
    autoCommitPending: false,
    writeState: event === "preview_issued" ? "read_pending" : "idle",
    needsReconcile: false,
  };
  return {
    lineNumber,
    line: "12:00:00.000 [WebDebug] " + JSON.stringify(Object.assign(base, overrides || {})),
  };
}

function encodedField(value) {
  return encodeURIComponent(String(value));
}

function fixtureHost(lineNumber, overrides) {
  const fields = Object.assign({
    webCallId: "tune.fixture.1",
    flashCallId: 17,
    requestCallId: "tune.fixture.1",
    tokenRef: "sha256_0123456789abcdef01234567",
    panelInstanceId: "panel.fixture.1",
    viewSessionId: "view.fixture.1",
    sourceKey: "inventory:背包:24:lease.fixture",
    operation: "install_mod",
    candidateKey: "mod.25",
    intentKey: "install_mod|mod.25|",
    outcome: "success",
    remainingPending: 0,
  }, overrides || {});
  return {
    lineNumber,
    line: "12:00:00.010 event=equipment_tuning_preview_settled"
      + " webCallId=" + encodedField(fields.webCallId)
      + " flashCallId=" + String(fields.flashCallId)
      + " requestCallId=" + encodedField(fields.requestCallId)
      + " tokenRef=" + encodedField(fields.tokenRef)
      + " panelInstanceId=" + encodedField(fields.panelInstanceId)
      + " viewSessionId=" + encodedField(fields.viewSessionId)
      + " sourceKey=" + encodedField(fields.sourceKey)
      + " operation=" + encodedField(fields.operation)
      + " candidateKey=" + encodedField(fields.candidateKey)
      + " intentKey=" + encodedField(fields.intentKey)
      + " outcome=" + encodedField(fields.outcome)
      + " remainingPending=" + String(fields.remainingPending),
  };
}

function fixtureHostCommit(lineNumber) {
  return {
    lineNumber,
    line: "12:00:00.020 event=equipment_tuning_commit_settled"
      + " webCallId=tune.fixture.commit.1"
      + " panelInstanceId=panel.fixture.1"
      + " viewSessionId=view.fixture.1",
  };
}

function fixtureAnchor() {
  return {
    watermark: { total: 100, capturedAt: "2026-08-02T00:00:00.000Z" },
    snapshotLineNumber: 100,
    panelInstanceId: "panel.fixture.1",
    viewSessionId: "view.fixture.1",
    pid: 1234,
    httpPort: 1192,
    runtimeIdentity: {
      runtimeMode: "isolated_candidate",
      processPath: path.join("C:\\", "check", "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
      coreSha256: "A".repeat(64),
      buildIdentity: "B".repeat(64),
      payloadClosure: "C".repeat(64),
    },
  };
}

function validFixture() {
  return [
    fixtureWeb(101, "candidate_hit"),
    fixtureWeb(102, "preview_issued"),
    fixtureHost(103),
    fixtureWeb(104, "preview_adopted"),
  ];
}

function expectFixtureRejected(name, records) {
  const result = verifyPreviewEvidence(records, fixtureAnchor());
  if (result.ok) throw new Error(name + " fixture was accepted");
  return result.code;
}

function expectCallRejected(name, callback, expectedCode) {
  let error = null;
  try {
    callback();
  } catch (caught) {
    error = caught;
  }
  if (!error) throw new Error(name + " contract was accepted");
  if (expectedCode && error.code !== expectedCode) {
    throw new Error(name + " returned " + error.code + ", expected " + expectedCode);
  }
  return error.code;
}

function runOfflineChecks() {
  const identity = fixtureAnchor().runtimeIdentity;
  assertIdentityFields(identity, JSON.parse(JSON.stringify(identity)), "check_identity");
  const valid = verifyPreviewEvidence(validFixture(), fixtureAnchor());
  if (!valid.ok
      || valid.exactTuple.webCallId !== "tune.fixture.1"
      || valid.exactTuple.flashCallId !== 17) {
    throw new Error("positive exact-tuple fixture failed");
  }
  const maxIntent = "i".repeat(384);
  const maxIntentFixture = [
    fixtureWeb(101, "candidate_hit"),
    fixtureWeb(102, "preview_issued", { intentKey: maxIntent }),
    fixtureHost(103, { intentKey: maxIntent }),
    fixtureWeb(104, "preview_adopted", { intentKey: maxIntent }),
  ];
  if (!verifyPreviewEvidence(maxIntentFixture, fixtureAnchor()).ok) {
    throw new Error("384-character intent fixture failed");
  }
  const cleanInteractionWatermark = opener.establishInteractionLogWatermark(100, {
    total: 101,
    lines: ["12:00:00.000 event=equipment_tuning_snapshot_confirmed"],
    capturedAt: "2026-08-02T00:00:01.000Z",
  });
  if (cleanInteractionWatermark.total !== 101) {
    throw new Error("clean verifier interaction watermark fixture failed");
  }
  const crossSession = validFixture();
  crossSession[3] = fixtureWeb(104, "preview_adopted", {
    viewSessionId: "view.fixture.other",
  });
  const crossCandidate = validFixture();
  crossCandidate[3] = fixtureWeb(104, "preview_adopted", {
    candidateKey: "mod.other",
  });
  const crossCallId = validFixture();
  crossCallId[2] = fixtureHost(103, {
    webCallId: "tune.fixture.other",
    requestCallId: "tune.fixture.other",
  });
  const missingEvent = validFixture().filter((record) => record.lineNumber !== 103);
  const oldEvents = validFixture().map((record, index) => Object.assign({}, record, {
    lineNumber: 96 + index,
  }));
  const autoCommit = validFixture().concat([
    fixtureWeb(105, "commit_issued", { webCallId: "tune.fixture.commit.1" }),
  ]);
  const hostAutoCommit = validFixture().concat([fixtureHostCommit(105)]);
  const fastMode = [
    fixtureWeb(101, "candidate_hit", { confirmationMode: "fast" }),
    fixtureWeb(102, "preview_issued", {
      confirmationMode: "fast",
      autoCommitPending: true,
    }),
    fixtureHost(103),
    fixtureWeb(104, "preview_adopted", {
      confirmationMode: "fast",
      autoCommitPending: true,
    }),
  ];
  const failedOutcome = validFixture();
  failedOutcome[2] = fixtureHost(103, { outcome: "error:invalid_candidate" });
  const badTerminal = validFixture();
  badTerminal[3] = fixtureWeb(104, "preview_adopted", {
    pendingCount: 1,
    tokenPresent: false,
    commitReady: false,
  });
  const wrongOrder = [
    fixtureWeb(101, "preview_issued"),
    fixtureWeb(102, "candidate_hit"),
    fixtureHost(103),
    fixtureWeb(104, "preview_adopted"),
  ];
  const fakeHostSubstring = validFixture().filter((record) => record.lineNumber !== 103);
  fakeHostSubstring.splice(2, 0, {
    lineNumber: 103,
    line: "12:00:00.010 [WebDebug] " + JSON.stringify({
      type: "debug",
      scope: "other_scope",
      note: "event=equipment_tuning_preview_settled webCallId=tune.fixture.1",
    }),
  });
  const overlongIntent = [
    fixtureWeb(101, "candidate_hit"),
    fixtureWeb(102, "preview_issued", { intentKey: "i".repeat(385) }),
    fixtureHost(103, { intentKey: "i".repeat(385) }),
    fixtureWeb(104, "preview_adopted", { intentKey: "i".repeat(385) }),
  ];
  const rejected = {
    crossSession: expectFixtureRejected("cross-session", crossSession),
    crossCandidate: expectFixtureRejected("cross-candidate", crossCandidate),
    crossCallId: expectFixtureRejected("cross-callId", crossCallId),
    missingEvent: expectFixtureRejected("missing-event", missingEvent),
    oldEvents: expectFixtureRejected("old-event", oldEvents),
    autoCommit: expectFixtureRejected("auto-commit", autoCommit),
    hostAutoCommit: expectFixtureRejected("host-auto-commit", hostAutoCommit),
    fastMode: expectFixtureRejected("fast-mode", fastMode),
    failedOutcome: expectFixtureRejected("failed-outcome", failedOutcome),
    badTerminal: expectFixtureRejected("bad-terminal", badTerminal),
    wrongOrder: expectFixtureRejected("wrong-order", wrongOrder),
    fakeHostSubstring: expectFixtureRejected("fake-host-substring", fakeHostSubstring),
    overlongIntent: expectFixtureRejected("overlong-intent", overlongIntent),
    shortQuietWindow: expectCallRejected("short-quiet-window", () => parseArgs([
      "--open-report", "fixture.json", "--settle-ms", "999",
    ]), "invalid_settle"),
    logReset: expectCallRejected("log-reset", () => opener.freshLogRecords(
      fixtureAnchor().watermark,
      { total: 99, lines: [] }
    ), "log_reset_after_watermark"),
    logGap: expectCallRejected("log-gap", () => opener.freshLogRecords(
      fixtureAnchor().watermark,
      { total: 2101, lines: new Array(2000).fill("line") }
    ), "log_gap_after_watermark"),
    processChanged: expectCallRejected("process-changed", () => (
      assertContextMatchesAnchor({ pid: 9999, httpPort: 1192 }, fixtureAnchor())
    ), "runtime_process_changed"),
    portChanged: expectCallRejected("port-changed", () => (
      assertContextMatchesAnchor({ pid: 1234, httpPort: 2291 }, fixtureAnchor())
    ), "runtime_process_changed"),
    coreIdentityChanged: expectCallRejected("core-identity-changed", () => {
      const changed = JSON.parse(JSON.stringify(identity));
      changed.coreSha256 = "D".repeat(64);
      assertIdentityFields(identity, changed, "check_identity");
    }, "runtime_identity_drift"),
    buildIdentityChanged: expectCallRejected("build-identity-changed", () => {
      const changed = JSON.parse(JSON.stringify(identity));
      changed.buildIdentity = "D".repeat(64);
      assertIdentityFields(identity, changed, "check_identity");
    }, "runtime_identity_drift"),
    payloadClosureChanged: expectCallRejected("payload-closure-changed", () => {
      const changed = JSON.parse(JSON.stringify(identity));
      changed.payloadClosure = "D".repeat(64);
      assertIdentityFields(identity, changed, "check_identity");
    }, "runtime_identity_drift"),
    runtimeModeChanged: expectCallRejected("runtime-mode-changed", () => {
      const changed = JSON.parse(JSON.stringify(identity));
      changed.runtimeMode = "formal_runtime";
      assertIdentityFields(identity, changed, "check_identity");
    }, "runtime_identity_drift"),
    processPathChanged: expectCallRejected("process-path-changed", () => {
      const changed = JSON.parse(JSON.stringify(identity));
      changed.processPath = path.join("C:\\", "other", "Core.exe");
      assertIdentityFields(identity, changed, "check_identity");
    }, "runtime_identity_drift"),
    playerSaveAsReport: expectCallRejected("player-save-as-report", () => (
      resolveOpenReport(path.join(root, "saves", "crazyflasher7_saves.json"))
    ), "open_report_outside_opener_directory"),
    beforePromptReplay: expectCallRejected("before-prompt-replay", () => (
      opener.establishInteractionLogWatermark(100, {
        total: 101,
        lines: ["12:00:00.000 [WebDebug] " + JSON.stringify({
          scope: "equipment_tuning",
          event: "candidate_hit",
        })],
        capturedAt: "2026-08-02T00:00:01.000Z",
      })
    ), "business_action_before_verifier"),
  };
  const report = {
    ok: true,
    gate: "PG-TUNE-PREVIEW",
    scope: "preview_only",
    fixtures: {
      positive: 3,
      negative: Object.keys(rejected).length,
      rejected,
    },
  };
  console.log(JSON.stringify(report, null, 2));
  return report;
}

async function runJourney(args) {
  const startedAt = new Date().toISOString();
  const directory = outputDirectory();
  const receipt = {
    schema: "equipment-tuning.preview-journey-receipt.v1",
    gate: "PG-TUNE-PREVIEW",
    status: "running",
    startedAt,
    finishedAt: null,
    openReport: null,
    scope: {
      coverage: "preview_only",
      verifierClicksUi: false,
      verifierSendsBusinessCommands: false,
      verifierBusinessWritesAttempted: false,
      journeyBusinessWritesObserved: null,
      commitVerified: false,
      reconcileVerified: false,
    },
    opener: {
      runtimeIdentity: null,
      httpPort: null,
      openLogWatermark: null,
      interactionLogWatermark: null,
      panelInstanceId: null,
      viewSessionId: null,
    },
    runtimeContinuity: { verified: false },
    freshness: null,
    exactTuple: null,
    evidence: null,
    assertions: null,
    commit: {
      status: "not_verified",
      cloneSaveReceiptRequired: true,
    },
    error: null,
  };
  let caught = null;
  try {
    const openReportPath = resolveOpenReport(args.openReport);
    receipt.openReport = relativeToRoot(openReportPath);
    const source = readJsonFile(openReportPath, "open_report_json_invalid");
    const anchor = validateOpenReport(source);
    const openerWatermark = Object.assign({}, anchor.watermark);
    receipt.opener = {
      runtimeIdentity: anchor.runtimeIdentity,
      httpPort: anchor.httpPort,
      openLogWatermark: openerWatermark,
      interactionLogWatermark: null,
      panelInstanceId: anchor.panelInstanceId,
      viewSessionId: anchor.viewSessionId,
      snapshotLineNumber: anchor.snapshotLineNumber,
    };
    const beforePreview = exactLiveRuntime(anchor, "runtime_identity_before_preview");
    receipt.runtimeContinuity = {
      verified: true,
      expectedPid: anchor.pid,
      observedPid: beforePreview.context.pid,
      expectedHttpPort: anchor.httpPort,
      observedHttpPort: beforePreview.context.httpPort,
      beforePreview: beforePreview.identity,
      afterPreview: null,
      fullIdentityReverified: false,
    };
    const interactionSnapshot = await requestLogs(beforePreview.context);
    const interactionWatermark = opener.establishInteractionLogWatermark(
      anchor.snapshotLineNumber,
      interactionSnapshot
    );
    anchor.watermark = interactionWatermark;
    receipt.opener.interactionLogWatermark = interactionWatermark;
    process.stderr.write(JSON.stringify({
      state: "waiting_for_computer_use_preview",
      gate: "PG-TUNE-PREVIEW",
      panelInstanceId: anchor.panelInstanceId,
      viewSessionId: anchor.viewSessionId,
      openWatermarkTotal: openerWatermark.total,
      interactionWatermarkTotal: interactionWatermark.total,
      coverage: "preview_only",
    }) + "\n");
    const closed = await waitForPreview(
      beforePreview.context,
      anchor,
      args.timeoutMs,
      args.pollMs,
      args.settleMs
    );
    const afterPreview = exactLiveRuntime(anchor, "runtime_identity_after_preview");
    receipt.runtimeContinuity.afterPreview = afterPreview.identity;
    receipt.runtimeContinuity.fullIdentityReverified = true;
    receipt.freshness = {
      eventsAfterOpenWatermark: true,
      openWatermarkTotal: openerWatermark.total,
      interactionWatermarkTotal: interactionWatermark.total,
      finalLogTotal: closed.finalLogTotal,
      capturedAt: closed.capturedAt,
      noWriteQuietWindowMs: closed.settleMs,
    };
    receipt.exactTuple = closed.result.exactTuple;
    receipt.evidence = closed.result.evidence;
    receipt.assertions = Object.assign({
      openerRuntimeIdentityVerified: true,
      formalOrIsolatedRuntimeMode: true,
      launcherPidAndPortContinuous: true,
      fullRuntimeIdentityReverified: true,
      noCommitRefreshOrReconcileObserved: true,
    }, closed.result.assertions);
    receipt.scope.journeyBusinessWritesObserved = false;
    receipt.status = "preview_verified";
  } catch (error) {
    caught = error;
    receipt.status = "failed";
    receipt.error = serializeError(error);
    if (receipt.error.code === "business_write_observed") {
      receipt.scope.journeyBusinessWritesObserved = true;
    }
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
    coverage: receipt.scope.coverage,
    exactTuple: receipt.exactTuple,
    commitVerified: false,
    receipt: receipt.receiptPath,
  }, null, 2));
  return receipt;
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }
  if (args.check) {
    runOfflineChecks();
    return;
  }
  await runJourney(args);
}

module.exports = {
  assertIdentityFields,
  parseArgs,
  parseHostSettled,
  parseWebDebug,
  runOfflineChecks,
  resolveOpenReport,
  validateOpenReport,
  verifyPreviewEvidence,
};

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    const code = error && error.code ? error.code : "unexpected_error";
    const receipt = error && error.receiptPath ? " receipt=" + error.receiptPath : "";
    console.error(code + ": " + error.message + receipt);
    process.exit(error && error.code && error.phase === "arguments" ? 2 : 1);
  });
}
