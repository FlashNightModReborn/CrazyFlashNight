"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const http = require("http");
const net = require("net");
const path = require("path");
const LegacyHttpClient = require("../../lib/legacy-http-client");
const RuntimeIdentity = require("../../lib/runtime-process-identity");
const CloneSaveGuard = require("./clone-save-guard");
const RuntimeGuard = require("./runtime-guard");
const {
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
const SESSION_SCHEMA = "workbench-live-e2e.authenticated-legacy-http-session.v1";
const LOG_SNAPSHOT_SCHEMA = "workbench-live-e2e.launcher-log-tail.v1";
const LOG_BOUNDARY_SCHEMA = "workbench-live-e2e.launcher-terminal-boundary.v1";
const ARCHIVE_SCHEMA = "workbench-live-e2e.archive-save-evidence.v1";
const RESIDUE_SCHEMA = "workbench-live-e2e.runtime-residue.v1";
const AGENT_ENTER_COMMAND = "#func:_root.agentEnterResolvedSave()";
const AGENT_ACTIONS = new Set([
  "status", "start", "revealOk", "cancel", "shutdown", "openArena",
]);
const HANDOFF_MARKER = "[BootstrapAS] event=handoff";
const TITLE_FRAME_MARKER = "[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared";
const WATCHDOG_MARKER = "[LaunchFlow] Flash reveal watchdog fired";

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function defaultHttpRequest(context, method, pathname, body, timeoutMs) {
  return new Promise((resolve, reject) => {
    const payload = body == null ? "" : JSON.stringify(body);
    let headers;
    try {
      headers = Object.assign({ "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(payload) },
      LegacyHttpClient.authorizationHeadersFor(context, pathname));
    } catch (error) { reject(error); return; }
    // HttpApiServer registers an HttpListener prefix for the exact localhost host.
    // Using the numeric loopback address reaches the port but Windows rejects the
    // Host header with HTTP 400 (Invalid Hostname) before our handler/auth runs.
    const request = http.request({ hostname: "localhost", port: context.httpPort,
      method, path: pathname, timeout: timeoutMs || 5000, headers }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => resolve({ statusCode: response.statusCode,
        text: Buffer.concat(chunks).toString("utf8") }));
    });
    request.on("timeout", () => request.destroy(new Error(method + " " + pathname + " timed out")));
    request.on("error", reject);
    request.end(payload);
  });
}

function parseJsonResponse(response, label) {
  if (!response || !Number.isInteger(response.statusCode)
      || response.statusCode < 200 || response.statusCode >= 300) {
    contractFail("legacy_http_status_invalid", "launcher_http",
      label + " returned a non-success HTTP status", { statusCode: response && response.statusCode });
  }
  try { return JSON.parse(String(response.text || "")); }
  catch (error) {
    contractFail("legacy_http_json_invalid", "launcher_http",
      label + " returned invalid JSON", { error: error.message });
  }
}

function responseSucceeded(response) {
  return !!response && (response.success === true || response.ok === true)
    && response.success !== false && response.ok !== false;
}

function assertResponseSucceeded(response, phase, label) {
  if (!responseSucceeded(response)) {
    contractFail("launcher_task_failed", phase || "launcher_http",
      (label || "Launcher task") + " failed", { response });
  }
  return response;
}

function validateAgentFields(action, fields) {
  const value = fields == null ? {} : fields;
  if (!isPlainObject(value) || Object.prototype.hasOwnProperty.call(value, "task")
      || Object.prototype.hasOwnProperty.call(value, "action")) {
    contractFail("agent_control_fields_invalid", "launcher_http", "agent_control fields are malformed");
  }
  const allowed = action === "start"
    ? new Set(["slot", "fresh", "deferReveal", "requireFlashReveal", "rememberSlot"])
    : action === "openArena"
      ? new Set(["expectedSlot", "expectedAttemptId"])
      : new Set();
  const extras = Object.keys(value).filter((key) => !allowed.has(key));
  if (extras.length > 0) {
    contractFail("agent_control_fields_forbidden", "launcher_http",
      "agent_control lifecycle call contains non-lifecycle fields", { action, extras });
  }
  if (action === "start" && (typeof value.slot !== "string"
      || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(value.slot) || value.fresh !== false)) {
    contractFail("agent_control_start_invalid", "launcher_http",
      "agent start requires one dedicated snapshot slot and fresh=false");
  }
  if (action === "openArena" && (typeof value.expectedSlot !== "string"
      || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(value.expectedSlot)
      || typeof value.expectedAttemptId !== "string" || !value.expectedAttemptId)) {
    contractFail("agent_control_arena_open_invalid", "launcher_http",
      "arena open requires the exact dedicated slot and current attempt watermark");
  }
  return value;
}

function publicSessionEvidence(root, context) {
  const ports = readExactRegularFile(context.portsFile, {
    phase: "launcher_http", maximumBytes: 64 * 1024,
  });
  const credential = readExactRegularFile(context.credential.path, {
    phase: "launcher_http", maximumBytes: 64 * 1024,
  });
  const evidence = {
    schema: SESSION_SCHEMA,
    apiVersion: API_VERSION,
    openedAt: new Date().toISOString(),
    pid: context.pid,
    httpPort: context.httpPort,
    socketPort: context.socketPort,
    portsFile: pathInside(root, context.portsFile)
      ? path.relative(root, context.portsFile).replace(/\\/g, "/") : path.resolve(context.portsFile),
    portsFileSha256: ports.sha256,
    portsFileBytes: ports.length,
    credentialFile: path.resolve(context.credential.path),
    credentialFileSha256: credential.sha256,
    credentialFileBytes: credential.length,
    credentialTokenSha256: sha256Text(context.credential.token),
    credentialHeader: context.credential.header,
    processStartUtcTicks: context.credential.processStartUtcTicks,
    lifecycleId: context.credential.lifecycleId,
    capabilities: context.credential.capabilities.slice().sort(),
  };
  evidence.sessionEvidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function verifySessionEvidenceEnvelope(evidence) {
  if (!isPlainObject(evidence) || evidence.schema !== SESSION_SCHEMA
      || evidence.apiVersion !== API_VERSION || !Number.isInteger(evidence.pid) || evidence.pid < 1
      || !Number.isInteger(evidence.httpPort) || evidence.httpPort < 1 || evidence.httpPort > 65535
      || !Number.isInteger(evidence.socketPort) || evidence.socketPort < 1 || evidence.socketPort > 65535
      || evidence.httpPort === evidence.socketPort
      || !Number.isFinite(Date.parse(evidence.openedAt))
      || typeof evidence.portsFile !== "string" || !evidence.portsFile
      || !Number.isInteger(evidence.portsFileBytes) || evidence.portsFileBytes < 1
      || typeof evidence.credentialFile !== "string" || !path.isAbsolute(evidence.credentialFile)
      || !Number.isInteger(evidence.credentialFileBytes) || evidence.credentialFileBytes < 1
      || evidence.credentialHeader !== "X-CF7-Automation-Token"
      || !/^\d{12,20}$/.test(String(evidence.processStartUtcTicks || ""))
      || !/^[A-Za-z0-9_-]{8,160}$/.test(String(evidence.lifecycleId || ""))
      || !Array.isArray(evidence.capabilities)
      || canonicalJson(evidence.capabilities) !== canonicalJson(Array.from(new Set(evidence.capabilities)).sort())
      || ["legacy.console", "legacy.logs", "legacy.status", "legacy.task"]
        .some((entry) => !evidence.capabilities.includes(entry))
      || !/^[a-f0-9]{64}$/.test(String(evidence.portsFileSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(evidence.credentialFileSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(evidence.credentialTokenSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(evidence.sessionEvidenceSha256 || ""))) {
    contractFail("legacy_http_session_evidence_invalid", "launcher_http",
      "authenticated session evidence is malformed");
  }
  const payload = Object.assign({}, evidence);
  delete payload.sessionEvidenceSha256;
  if (sha256Text(canonicalJson(payload)) !== evidence.sessionEvidenceSha256) {
    contractFail("legacy_http_session_evidence_mismatch", "launcher_http",
      "authenticated session evidence digest mismatch");
  }
  return evidence;
}

function openAuthenticatedLegacyHttpSession(options) {
  const root = path.resolve(options.root);
  const reader = options.contextReader || LegacyHttpClient.readExactLauncherHttpContext;
  let context;
  try { context = reader(root, options.contextOptions || {}); }
  catch (error) {
    contractFail("legacy_http_context_unavailable", "launcher_http", error.message);
  }
  const requiredCapabilities = ["legacy.console", "legacy.status", "legacy.task", "legacy.logs"];
  if (!context.credential || !Array.isArray(context.credential.capabilities)
      || requiredCapabilities.some((entry) => !context.credential.capabilities.includes(entry))) {
    contractFail("legacy_http_capability_missing", "launcher_http",
      "credential does not authorize the narrow lifecycle observation surface");
  }
  const evidence = publicSessionEvidence(root, context);
  verifySessionEvidenceEnvelope(evidence);
  const requestImpl = options.requestImpl || defaultHttpRequest;
  async function request(method, pathname, body, timeoutMs) {
    return parseJsonResponse(await requestImpl(context, method, pathname, body, timeoutMs),
      method + " " + pathname);
  }
  async function agentControl(action, fields, timeoutMs) {
    if (!AGENT_ACTIONS.has(action)) {
      contractFail("agent_control_action_forbidden", "launcher_http",
        "shared Launcher session exposes only lifecycle and the fixed arena AS2 opener", { action });
    }
    const safeFields = validateAgentFields(action, fields);
    return request("POST", "/task", Object.assign({ task: "agent_control", action }, safeFields),
      timeoutMs || 20000);
  }
  async function fixedAgentEnter(timeoutMs) {
    return request("POST", "/console", { command: AGENT_ENTER_COMMAND }, timeoutMs || 10000);
  }
  const session = {
    schema: SESSION_SCHEMA,
    evidence,
    getStatus(timeoutMs) { return request("GET", "/status", null, timeoutMs || 5000); },
    agentControl,
    requestFixedAgentEnter: fixedAgentEnter,
    readTerminalLogSnapshot(tailLimit, capturedAt) {
      const limit = Number(tailLimit || 2000);
      if (!Number.isInteger(limit) || limit < 1 || limit > 2000) {
        contractFail("log_tail_limit_invalid", "launcher_log", "tail limit must be 1..2000");
      }
      return request("GET", "/logs?lines=" + limit, null, 5000)
        .then((payload) => normalizeLogSnapshot(payload, limit, capturedAt, evidence));
    },
    verifyRuntimeIdentity(expected) {
      const actual = RuntimeIdentity.verifyRuntimeIdentity(root, evidence.httpPort, expected);
      if (!actual || actual.pid !== evidence.pid || actual.httpPort !== evidence.httpPort) {
        contractFail("legacy_http_runtime_binding_invalid", "launcher_identity",
          "authenticated session and verified runtime identity do not match");
      }
      return RuntimeIdentity.publicRuntimeIdentity(actual);
    },
  };
  return Object.freeze(session);
}

async function waitForAuthenticatedLegacyHttp(options) {
  const deadline = Date.now() + Number(options.timeoutMs || 60000);
  let lastError = null;
  while (Date.now() <= deadline) {
    try {
      const session = openAuthenticatedLegacyHttpSession(options);
      await session.getStatus(3000);
      return session;
    } catch (error) { lastError = error; }
    await sleep(Math.max(100, Number(options.pollMs || 250)));
  }
  contractFail("legacy_http_wait_timeout", "launcher_http",
    "authenticated legacy HTTP session did not become ready", {
      lastError: lastError && lastError.message,
    });
}

function normalizeLogSnapshot(payload, requestedTailLimit, capturedAt, sessionEvidence) {
  const session = verifySessionEvidenceEnvelope(sessionEvidence);
  if (!isPlainObject(payload) || payload.success !== true || !Number.isInteger(payload.total)
      || payload.total < 0 || !Array.isArray(payload.lines)
      || payload.lines.some((line) => typeof line !== "string")
      || payload.lines.length !== Math.min(payload.total, requestedTailLimit)) {
    contractFail("log_tail_incomplete", "launcher_log",
      "Launcher /logs response is not the complete requested terminal tail");
  }
  const oldestLineNumber = payload.lines.length > 0
    ? payload.total - payload.lines.length + 1 : payload.total + 1;
  const records = payload.lines.map((line, index) => ({
    lineNumber: oldestLineNumber + index,
    line,
  }));
  const digestPayload = { schema: LOG_SNAPSHOT_SCHEMA, requestedTailLimit,
    sessionEvidenceSha256: session.sessionEvidenceSha256,
    lifecycleId: session.lifecycleId,
    sessionPid: session.pid,
    sessionProcessStartUtcTicks: session.processStartUtcTicks,
    total: payload.total, oldestLineNumber, records };
  return Object.assign({}, digestPayload, {
    capturedAt: capturedAt || new Date().toISOString(),
    tailSha256: sha256Text(canonicalJson(digestPayload)),
  });
}

function verifyLogSnapshot(snapshot) {
  if (!isPlainObject(snapshot) || snapshot.schema !== LOG_SNAPSHOT_SCHEMA
      || !Number.isInteger(snapshot.requestedTailLimit) || snapshot.requestedTailLimit < 1
      || snapshot.requestedTailLimit > 2000 || !Number.isInteger(snapshot.total)
      || !/^[a-f0-9]{64}$/.test(String(snapshot.sessionEvidenceSha256 || ""))
      || !/^[A-Za-z0-9_-]{8,160}$/.test(String(snapshot.lifecycleId || ""))
      || !Number.isInteger(snapshot.sessionPid) || snapshot.sessionPid < 1
      || !/^\d{12,20}$/.test(String(snapshot.sessionProcessStartUtcTicks || ""))
      || !Number.isInteger(snapshot.oldestLineNumber) || !Array.isArray(snapshot.records)
      || snapshot.records.length !== Math.min(snapshot.total, snapshot.requestedTailLimit)
      || !Number.isFinite(Date.parse(snapshot.capturedAt))) {
    contractFail("log_snapshot_invalid", "launcher_log", "terminal log snapshot is malformed");
  }
  const expectedOldest = snapshot.records.length > 0
    ? snapshot.total - snapshot.records.length + 1 : snapshot.total + 1;
  if (snapshot.oldestLineNumber !== expectedOldest
      || snapshot.records.some((record, index) => !isPlainObject(record)
        || record.lineNumber !== expectedOldest + index || typeof record.line !== "string")) {
    contractFail("log_snapshot_not_contiguous", "launcher_log",
      "terminal tail records are not one complete contiguous suffix");
  }
  const payload = { schema: snapshot.schema, requestedTailLimit: snapshot.requestedTailLimit,
    sessionEvidenceSha256: snapshot.sessionEvidenceSha256,
    lifecycleId: snapshot.lifecycleId, sessionPid: snapshot.sessionPid,
    sessionProcessStartUtcTicks: snapshot.sessionProcessStartUtcTicks,
    total: snapshot.total, oldestLineNumber: snapshot.oldestLineNumber, records: snapshot.records };
  if (sha256Text(canonicalJson(payload)) !== snapshot.tailSha256) {
    contractFail("log_snapshot_digest_mismatch", "launcher_log", "terminal tail digest mismatch");
  }
  return snapshot;
}

function createTerminalLogBoundary(snapshot) {
  verifyLogSnapshot(snapshot);
  return {
    schema: LOG_BOUNDARY_SCHEMA,
    capturedAt: snapshot.capturedAt,
    terminalTotal: snapshot.total,
    terminalTailSha256: snapshot.tailSha256,
    terminalSessionEvidenceSha256: snapshot.sessionEvidenceSha256,
    terminalLifecycleId: snapshot.lifecycleId,
    terminalSessionPid: snapshot.sessionPid,
    terminalSessionProcessStartUtcTicks: snapshot.sessionProcessStartUtcTicks,
    requestedTailLimit: snapshot.requestedTailLimit,
    snapshot,
  };
}

function verifyTerminalLogBoundary(boundary) {
  if (!isPlainObject(boundary) || boundary.schema !== LOG_BOUNDARY_SCHEMA
      || !Number.isInteger(boundary.terminalTotal) || boundary.terminalTotal < 0
      || !/^[a-f0-9]{64}$/.test(String(boundary.terminalTailSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(boundary.terminalSessionEvidenceSha256 || ""))
      || !/^[A-Za-z0-9_-]{8,160}$/.test(String(boundary.terminalLifecycleId || ""))
      || !Number.isInteger(boundary.terminalSessionPid) || boundary.terminalSessionPid < 1
      || !/^\d{12,20}$/.test(String(boundary.terminalSessionProcessStartUtcTicks || ""))
      || !Number.isFinite(Date.parse(boundary.capturedAt))) {
    contractFail("log_terminal_boundary_invalid", "launcher_log",
      "terminal log boundary is malformed");
  }
  verifyLogSnapshot(boundary.snapshot);
  if (boundary.snapshot.total !== boundary.terminalTotal
      || boundary.snapshot.tailSha256 !== boundary.terminalTailSha256
      || boundary.snapshot.sessionEvidenceSha256 !== boundary.terminalSessionEvidenceSha256
      || boundary.snapshot.lifecycleId !== boundary.terminalLifecycleId
      || boundary.snapshot.sessionPid !== boundary.terminalSessionPid
      || boundary.snapshot.sessionProcessStartUtcTicks
        !== boundary.terminalSessionProcessStartUtcTicks
      || boundary.snapshot.requestedTailLimit !== boundary.requestedTailLimit
      || boundary.snapshot.capturedAt !== boundary.capturedAt) {
    contractFail("log_terminal_boundary_mismatch", "launcher_log",
      "terminal boundary is not bound to its complete tail snapshot");
  }
  return boundary;
}

function queryLauncherProcessContract(pid) {
  if (process.platform !== "win32") {
    contractFail("launcher_process_contract_unavailable", "launcher_identity",
      "Launcher process contract observation requires Windows");
  }
  const script = [
    "$ErrorActionPreference='Stop'",
    "[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)",
    "$c=Get-CimInstance Win32_Process -Filter \"ProcessId=" + Number(pid) + "\"",
    "$p=Get-Process -Id " + Number(pid) + " -ErrorAction Stop",
    "[pscustomobject]@{pid=[int]$c.ProcessId;processPath=$c.ExecutablePath;commandLine=$c.CommandLine;processStartUtcTicks=$p.StartTime.ToUniversalTime().Ticks.ToString()} | ConvertTo-Json -Compress",
  ].join("\n");
  const result = childProcess.spawnSync("powershell.exe",
    ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
    { encoding: "utf8", windowsHide: true, timeout: 15000 });
  if (result.status !== 0) {
    contractFail("launcher_process_contract_unavailable", "launcher_identity",
      "could not observe authenticated Launcher process contract", {
        stderr: String(result.stderr || "").slice(-2000),
      });
  }
  try { return JSON.parse(String(result.stdout || "")); }
  catch (error) { contractFail("launcher_process_contract_invalid", "launcher_identity", error.message); }
}

function attestAuthenticatedLauncherProcess(options) {
  const session = options.sessionEvidence;
  const identity = options.runtimeIdentity;
  verifySessionEvidenceEnvelope(session);
  if (!isPlainObject(identity) || session.pid !== identity.pid) {
    contractFail("launcher_process_contract_input_invalid", "launcher_identity",
      "session/runtime identity binding is malformed");
  }
  const observed = (options.observeProcess || queryLauncherProcessContract)(session.pid);
  const commandLine = String(observed && observed.commandLine || "");
  const expectedRoot = path.resolve(options.root);
  const argv = RuntimeGuard.parseWindowsCommandLine(commandLine);
  const normalizedArgs = argv.map((entry) => String(entry).toLowerCase());
  const projectRootIndexes = normalizedArgs.map((entry, index) =>
    entry === "--project-root" ? index : -1).filter((index) => index >= 0);
  const legacyIndexes = normalizedArgs.map((entry, index) =>
    entry === "--legacy-http-automation" ? index : -1).filter((index) => index >= 0);
  const unattendedIndexes = normalizedArgs.map((entry, index) =>
    entry === "--agent-unattended-runner" ? index : -1).filter((index) => index >= 0);
  if (!observed || observed.pid !== session.pid
      || !samePath(observed.processPath || "", identity.processPath || "")
      || String(observed.processStartUtcTicks || "") !== String(session.processStartUtcTicks || "")
      || !samePath(argv[0] || "", identity.processPath || "")
      || projectRootIndexes.length !== 1 || projectRootIndexes[0] + 1 >= argv.length
      || !samePath(argv[projectRootIndexes[0] + 1], expectedRoot)
      || legacyIndexes.length !== 1 || unattendedIndexes.length !== 0) {
    contractFail("launcher_process_contract_mismatch", "launcher_identity",
      "actual process argv does not prove the authenticated legacy lifecycle contract");
  }
  const artifact = { schema: "workbench-live-e2e.launcher-process-contract.v1", apiVersion: API_VERSION,
    observedAt: new Date().toISOString(), pid: session.pid, processPath: path.resolve(observed.processPath),
    processStartUtcTicks: String(observed.processStartUtcTicks),
    commandLineSha256: sha256Text(commandLine), argvSha256: sha256Text(canonicalJson(argv)),
    projectRoot: expectedRoot, projectRootArgumentExact: true,
    legacyHttpAutomationArg: true, agentRuntimeAdmission: false,
    trustedSource: "actual_process_command_line+pid_bound_credential" };
  artifact.artifactSha256 = sha256Text(canonicalJson(artifact));
  return artifact;
}

function recordsAfterTerminalBoundary(boundary, snapshot) {
  verifyTerminalLogBoundary(boundary);
  verifyLogSnapshot(snapshot);
  if (snapshot.total < boundary.terminalTotal) {
    contractFail("log_reset_after_boundary", "launcher_log",
      "Launcher log shrank after the terminal boundary");
  }
  if (snapshot.sessionEvidenceSha256 !== boundary.terminalSessionEvidenceSha256
      || snapshot.lifecycleId !== boundary.terminalLifecycleId
      || snapshot.sessionPid !== boundary.terminalSessionPid
      || snapshot.sessionProcessStartUtcTicks
        !== boundary.terminalSessionProcessStartUtcTicks) {
    contractFail("log_lifecycle_changed_after_boundary", "launcher_log",
      "Launcher log snapshot crossed an authenticated process/session lifecycle");
  }
  if (boundary.terminalTotal < snapshot.oldestLineNumber - 1) {
    contractFail("log_gap_after_boundary", "launcher_log",
      "complete log suffix after terminal boundary fell out of the tail window", {
        terminalTotal: boundary.terminalTotal,
        oldestAvailable: snapshot.oldestLineNumber,
      });
  }
  if (boundary.terminalTotal > 0) {
    const overlapStart = Math.max(boundary.snapshot.oldestLineNumber,
      snapshot.oldestLineNumber);
    const overlapEnd = Math.min(boundary.terminalTotal, snapshot.total);
    if (overlapStart > overlapEnd) {
      contractFail("log_overlap_missing_after_boundary", "launcher_log",
        "Launcher log tail has no visible pre-boundary overlap; reset/catch-up cannot be excluded", {
          terminalTotal: boundary.terminalTotal,
          finalOldestLineNumber: snapshot.oldestLineNumber,
        });
    }
    const boundaryByNumber = new Map(boundary.snapshot.records
      .map((record) => [record.lineNumber, record.line]));
    const finalByNumber = new Map(snapshot.records
      .map((record) => [record.lineNumber, record.line]));
    for (let lineNumber = overlapStart; lineNumber <= overlapEnd; lineNumber += 1) {
      if (!boundaryByNumber.has(lineNumber) || !finalByNumber.has(lineNumber)
          || boundaryByNumber.get(lineNumber) !== finalByNumber.get(lineNumber)) {
        contractFail("log_overlap_changed_after_boundary", "launcher_log",
          "Launcher log overlap changed after the terminal boundary", { lineNumber });
      }
    }
  }
  return snapshot.records.filter((record) => record.lineNumber > boundary.terminalTotal);
}

function lineBody(record) {
  return String(record && record.line || "").replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
}

function parseExactArchiveRecord(record, slot, jsonPath) {
  const match = lineBody(record).match(
    /^\[ArchiveTask\] Shadow saved: ([A-Za-z0-9_-]+) \((\d+) chars\) path=(.+)$/);
  if (!match || match[1] !== slot || !samePath(match[3], jsonPath)) return null;
  const characters = Number(match[2]);
  if (!Number.isSafeInteger(characters) || characters < 1) return null;
  return { lineNumber: record.lineNumber, offset: 0,
    characters, path: path.resolve(match[3]) };
}

function captureDiskSaveEvidence(options) {
  const slot = CloneSaveGuard.assertDedicatedSlot(options.slot);
  const jsonPath = CloneSaveGuard.saveJsonPath(options.root, slot);
  const file = readExactRegularFile(jsonPath, {
    phase: "archive_disk", maximumBytes: 128 * 1024 * 1024,
  });
  const text = file.bytes.toString("utf8");
  try { JSON.parse(text); } catch (error) {
    contractFail("archive_disk_json_invalid", "archive_disk", error.message);
  }
  return { schema: "workbench-live-e2e.disk-save-evidence.v1", slot,
    path: jsonPath, sha256: file.sha256, bytes: file.length, textCharacters: text.length,
    capturedAt: options.capturedAt || new Date().toISOString() };
}

function exactSaveMarkerOccurrences(records, marker) {
  const escaped = String(marker).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp("(^|[\\s|])" + escaped + "(?=$|[\\s|])", "g");
  const occurrences = [];
  records.forEach((record) => {
    const body = lineBody(record);
    let match;
    while ((match = pattern.exec(body)) !== null) {
      occurrences.push({ lineNumber: record.lineNumber, offset: match.index + match[1].length });
    }
  });
  return occurrences;
}

function positionBefore(left, right) {
  return left.lineNumber < right.lineNumber
    || (left.lineNumber === right.lineNumber && left.offset < right.offset);
}

function verifyArchiveSaveEvidence(options) {
  const records = recordsAfterTerminalBoundary(options.boundary, options.snapshot);
  const disk = options.diskEvidence || captureDiskSaveEvidence(options);
  const current = captureDiskSaveEvidence(options);
  if (canonicalJson(Object.assign({}, current, { capturedAt: disk.capturedAt }))
      !== canonicalJson(disk)) {
    contractFail("archive_disk_evidence_mismatch", "archive_disk",
      "disk save bytes no longer match captured evidence");
  }
  const jsonPath = current.path;
  const archiveRecords = records.filter((record) =>
    lineBody(record).startsWith("[ArchiveTask] Shadow saved:"));
  const archives = archiveRecords.map((record) =>
    parseExactArchiveRecord(record, options.slot, jsonPath)).filter(Boolean);
  const sv1 = exactSaveMarkerOccurrences(records, "sv:1");
  const sv2 = exactSaveMarkerOccurrences(records, "sv:2");
  const sv3 = exactSaveMarkerOccurrences(records, "sv:3");
  if (archiveRecords.length !== 1 || archives.length !== 1
      || sv1.length !== 1 || sv2.length !== 1 || sv3.length !== 0) {
    contractFail("archive_save_record_count_invalid", "archive_log",
      "fresh complete tail must contain only one exact target archive, sv:1, and sv:2", {
        archiveRecordCount: archiveRecords.length, archiveCount: archives.length,
        sv1Count: sv1.length, sv2Count: sv2.length, sv3Count: sv3.length,
      });
  }
  if (archives[0].characters !== current.textCharacters) {
    contractFail("archive_character_count_mismatch", "archive_disk",
      "archive receipt character count does not match exact disk text");
  }
  const positions = { archive: { lineNumber: archives[0].lineNumber, offset: archives[0].offset },
    sv1: sv1[0], sv2: sv2[0] };
  const requiredOrder = options.requiredOrder || ["sv1", "sv2", "archive"];
  if (!Array.isArray(requiredOrder) || requiredOrder.length !== 3
      || new Set(requiredOrder).size !== 3
      || requiredOrder.some((entry) => !["archive", "sv1", "sv2"].includes(entry))
      || !positionBefore(positions[requiredOrder[0]], positions[requiredOrder[1]])
      || !positionBefore(positions[requiredOrder[1]], positions[requiredOrder[2]])) {
    contractFail("archive_save_order_invalid", "archive_log",
      "archive/save markers do not satisfy the caller's exact production order", {
        requiredOrder, positions,
      });
  }
  const evidence = { schema: ARCHIVE_SCHEMA, apiVersion: API_VERSION,
    boundary: options.boundary, finalSnapshotSha256: options.snapshot.tailSha256,
    requiredOrder: requiredOrder.slice(), positions, archive: archives[0], disk: current };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function queryLauncherCoreProcesses() {
  if (process.platform !== "win32") return [];
  const script = [
    "$ErrorActionPreference='Stop'",
    "[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)",
    "$records=@(Get-CimInstance Win32_Process -Filter \"Name='CRAZYFLASHER7MercenaryEmpire.Core.exe'\" | ForEach-Object {",
    " [pscustomobject]@{pid=[int]$_.ProcessId;parentPid=[int]$_.ParentProcessId;processPath=$_.ExecutablePath;commandLineSha256=$null}",
    "})",
    "$records | ConvertTo-Json -Compress",
  ].join("\n");
  const result = childProcess.spawnSync("powershell.exe",
    ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
    { encoding: "utf8", windowsHide: true, timeout: 15000 });
  if (result.status !== 0) {
    contractFail("launcher_process_inventory_failed", "launcher_process",
      "could not inventory Launcher Core processes", { stderr: String(result.stderr || "").slice(-2000) });
  }
  let parsed;
  try { parsed = JSON.parse(String(result.stdout || "[]")); }
  catch (error) { contractFail("launcher_process_inventory_invalid", "launcher_process", error.message); }
  const records = Array.isArray(parsed) ? parsed : parsed ? [parsed] : [];
  if (records.some((entry) => !Number.isInteger(entry.pid) || entry.pid < 1)) {
    contractFail("launcher_process_inventory_invalid", "launcher_process", "process inventory is malformed");
  }
  return records;
}

function assertExclusiveLauncherProcess(processes, authenticatedPid) {
  const records = Array.isArray(processes) ? processes : [];
  if (authenticatedPid == null) {
    if (records.length !== 0) {
      contractFail("unverified_launcher_process_present", "launcher_process",
        "Launcher exists without authenticated ownership", { pids: records.map((entry) => entry.pid) });
    }
    return true;
  }
  if (records.length !== 1 || records[0].pid !== authenticatedPid) {
    contractFail("launcher_process_not_exclusive", "launcher_process",
      "authenticated Launcher is not the only Launcher Core process", {
        authenticatedPid, observedPids: records.map((entry) => entry.pid),
      });
  }
  return true;
}

function assertRuntimeReadyStatus(status, expectedSlot, expectedAttemptId) {
  const blockers = status && Array.isArray(status.runtimeReadyBlockedBy)
    ? status.runtimeReadyBlockedBy : [];
  const save = status && status.save;
  const runtime = status && status.saveRuntime;
  if (!responseSucceeded(status) || status.readyForRuntimeAutomation !== true || blockers.length !== 0
      || status.gameEnteredObserved !== true || status.gameEnteredAttemptId !== expectedAttemptId
      || !save || save.decision !== "snapshot" || save.kind !== "Snapshot"
      || save.slot !== expectedSlot || save.attemptId !== expectedAttemptId
      || !runtime || runtime.loaded !== true || runtime.savePath !== expectedSlot
      || runtime.attemptId !== expectedAttemptId || typeof runtime.role !== "string" || !runtime.role
      || runtime.level == null || Number.isNaN(Number(runtime.level))) {
    contractFail("runtime_ready_status_invalid", "runtime_ready",
      "agent_control status does not prove the exact slot/attempt runtime readiness", { status });
  }
  return status;
}

async function waitForAgentControl(session, options) {
  const deadline = Date.now() + Number(options.timeoutMs || 60000);
  let last = null;
  while (Date.now() <= deadline) {
    try {
      last = await session.agentControl("status");
      if (responseSucceeded(last) && last.error !== "task 'agent_control' is not httpCallable") return last;
    } catch (_error) {}
    await sleep(Number(options.pollMs || 250));
  }
  contractFail("agent_control_timeout", "runtime_ready", "agent_control did not become callable", { last });
}

async function waitForRuntimeReady(session, options) {
  const boundary = verifyTerminalLogBoundary(options.startBoundary);
  const deadline = Date.now() + Number(options.timeoutMs || 180000);
  let expectedAttemptId = options.expectedAttemptId || null;
  let handoff = null;
  let title = null;
  let enterCount = 0;
  let lastStatus = options.startResponse || null;
  while (Date.now() <= deadline) {
    lastStatus = await session.agentControl("status");
    assertResponseSucceeded(lastStatus, "runtime_ready", "agent_control status");
    const attempt = lastStatus.save && lastStatus.save.slot === options.slot
      ? lastStatus.save.attemptId : null;
    if (attempt) {
      if (expectedAttemptId && expectedAttemptId !== attempt) {
        contractFail("runtime_attempt_changed", "runtime_ready", "attempt changed while waiting");
      }
      expectedAttemptId = attempt;
    }
    const snapshot = await session.readTerminalLogSnapshot(2000);
    const fresh = recordsAfterTerminalBoundary(boundary, snapshot);
    const handoffs = fresh.filter((record) => record.line.includes(HANDOFF_MARKER));
    const titles = fresh.filter((record) => record.line.includes(TITLE_FRAME_MARKER));
    const watchdogs = fresh.filter((record) => record.line.includes(WATCHDOG_MARKER));
    if (handoffs.length > 1 || titles.length > 1) {
      contractFail("runtime_boot_marker_count_invalid", "runtime_ready",
        "fresh lifecycle must contain one exact handoff and title marker at most");
    }
    handoff = handoff || handoffs[0] || null;
    title = title || titles[0] || null;
    const watchdog = watchdogs[0] || null;
    if (watchdogs.length > 1 || (watchdog && (!title || watchdog.lineNumber < title.lineNumber))) {
      contractFail("runtime_title_frame_missing", "runtime_ready",
        "reveal watchdog fired before title-frame receipt");
    }
    const blockers = Array.isArray(lastStatus.runtimeReadyBlockedBy)
      ? lastStatus.runtimeReadyBlockedBy : [];
    const save = lastStatus.save;
    if (enterCount === 0 && handoff && title && expectedAttemptId
        && lastStatus.launchState === "Ready" && lastStatus.revealPerformed === true
        && lastStatus.socketConnected === true && blockers.includes("runtime_save_not_loaded")
        && save && save.decision === "snapshot" && save.kind === "Snapshot"
        && save.slot === options.slot && save.attemptId === expectedAttemptId) {
      assertResponseSucceeded(await session.requestFixedAgentEnter(), "runtime_ready", "fixed agent enter");
      enterCount += 1;
    }
    if (lastStatus.readyForRuntimeAutomation === true && handoff && title) {
      if (enterCount !== 1 || !expectedAttemptId) {
        contractFail("runtime_ready_enter_count_invalid", "runtime_ready",
          "runtime became ready without one fixed agent-enter request");
      }
      assertRuntimeReadyStatus(lastStatus, options.slot, expectedAttemptId);
      return { status: lastStatus, expectedAttemptId, handoff, title, enterRequestCount: enterCount,
        terminalSnapshot: snapshot };
    }
    await sleep(Number(options.pollMs || 250));
  }
  contractFail("runtime_ready_timeout", "runtime_ready",
    "runtime did not reach exact automation readiness", { expectedAttemptId, lastStatus });
}

function startLauncherCandidate(options) {
  RuntimeGuard.validateCandidateIdentity(options.expectedIdentity, options.candidateRoot);
  const currentIdentity = RuntimeGuard.publicCandidateIdentity(
    RuntimeIdentity.resolveExpectedRuntimeIdentity(options.root, options.candidateRoot));
  const expectedIdentity = RuntimeGuard.publicCandidateIdentity(options.expectedIdentity);
  if (canonicalJson(currentIdentity) !== canonicalJson(expectedIdentity)) {
    contractFail("launcher_candidate_identity_drift", "launcher_start",
      "candidate identity changed between pre-mutation resolution and process start");
  }
  const script = path.join(path.resolve(options.root), "automation", "start.ps1");
  const scriptFile = readExactRegularFile(script, {
    phase: "launcher_start", maximumBytes: 4 * 1024 * 1024,
  });
  const args = RuntimeIdentity.buildLauncherStartArguments(script, expectedIdentity,
    { enableLegacyHttpAutomation: true });
  const spawn = options.spawnSync || childProcess.spawnSync;
  const launch = () => spawn("powershell.exe", args, {
    cwd: path.resolve(options.root), encoding: "utf8", windowsHide: true,
  });
  const result = options.cdpPort
    ? RuntimeGuard.withWebViewDebugEnvironment(options.cdpPort, launch) : launch();
  if (!result || result.status !== 0) {
    contractFail("launcher_start_failed", "launcher_start",
      "candidate Launcher start failed", { status: result && result.status,
        stdoutTail: String(result && result.stdout || "").slice(-2000),
        stderrTail: String(result && result.stderr || "").slice(-2000) });
  }
  const identity = expectedIdentity;
  return { schema: "workbench-live-e2e.launcher-start.v1", apiVersion: API_VERSION,
    startedAt: new Date().toISOString(), candidateIdentity: identity,
    candidateIdentitySha256: sha256Text(canonicalJson(identity)), cdpPort: options.cdpPort || null,
    script: { relativePath: "automation/start.ps1", sha256: scriptFile.sha256,
      bytes: scriptFile.length }, legacyHttpAutomation: true };
}

function probeTcpPort(port, timeoutMs) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host: "127.0.0.1", port });
    let settled = false;
    function finish(open) {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(open);
    }
    socket.setTimeout(timeoutMs || 500);
    socket.once("connect", () => finish(true));
    socket.once("timeout", () => finish(false));
    socket.once("error", () => finish(false));
  });
}

async function observeRuntimeResidue(options) {
  const identity = options.runtimeIdentity;
  const session = options.sessionEvidence;
  const processQuery = options.queryProcesses || queryLauncherCoreProcesses;
  const portProbe = options.probePort || probeTcpPort;
  verifySessionEvidenceEnvelope(session);
  if (!isPlainObject(identity) || identity.pid !== session.pid) {
    contractFail("residue_identity_invalid", "residue", "residue inputs are not identity-bound");
  }
  const cdpPort = options.cdpBinding && options.cdpBinding.port;
  if (!Number.isInteger(cdpPort) || cdpPort < 1 || cdpPort > 65535
      || cdpPort === session.httpPort || cdpPort === session.socketPort) {
    contractFail("residue_cdp_binding_invalid", "residue",
      "residue observation requires the exact distinct runner-owned CDP port");
  }
  const processes = await Promise.resolve(processQuery());
  const expectedPath = path.resolve(identity.processPath);
  const matchingPath = processes.filter((entry) => entry.processPath
    && samePath(entry.processPath, expectedPath));
  const ports = [session.httpPort, session.socketPort, cdpPort];
  const portStates = [];
  for (const port of ports) portStates.push({ port, open: await portProbe(port, 500) });
  const portsFile = path.isAbsolute(session.portsFile)
    ? session.portsFile : path.resolve(options.root, session.portsFile.replace(/\//g, path.sep));
  const evidence = { schema: RESIDUE_SCHEMA, apiVersion: API_VERSION,
    observedAt: new Date().toISOString(),
    expectedPid: identity.pid, expectedProcessPath: expectedPath,
    pidAbsent: !processes.some((entry) => entry.pid === identity.pid),
    candidateProcessAbsent: matchingPath.length === 0,
    observedLauncherPids: processes.map((entry) => entry.pid).sort((a, b) => a - b),
    ports: portStates,
    portsFile, portsFileAbsent: !fs.existsSync(portsFile),
    credentialFile: session.credentialFile,
    credentialFileAbsent: !fs.existsSync(session.credentialFile),
  };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function assertResidueSnapshotClean(evidence) {
  if (!isPlainObject(evidence) || evidence.schema !== RESIDUE_SCHEMA
      || evidence.apiVersion !== API_VERSION || !Number.isFinite(Date.parse(evidence.observedAt))
      || !Number.isInteger(evidence.expectedPid) || evidence.expectedPid < 1
      || typeof evidence.expectedProcessPath !== "string" || !path.isAbsolute(evidence.expectedProcessPath)
      || evidence.pidAbsent !== true || evidence.candidateProcessAbsent !== true
      || !Array.isArray(evidence.observedLauncherPids)
      || evidence.observedLauncherPids.length !== 0
      || evidence.portsFileAbsent !== true || evidence.credentialFileAbsent !== true
      || !Array.isArray(evidence.ports) || evidence.ports.length !== 3
      || new Set(evidence.ports.map((entry) => entry.port)).size !== 3
      || evidence.ports.some((entry) => !Number.isInteger(entry.port)
        || entry.port < 1 || entry.port > 65535 || entry.open !== false)
      || !/^[a-f0-9]{64}$/.test(String(evidence.evidenceSha256 || ""))) {
    contractFail("runtime_residue_not_clean", "residue",
      "PID/ports/rendezvous/credential residue remains", { evidence });
  }
  const payload = Object.assign({}, evidence);
  delete payload.evidenceSha256;
  if (sha256Text(canonicalJson(payload)) !== evidence.evidenceSha256) {
    contractFail("runtime_residue_evidence_mismatch", "residue",
      "runtime residue evidence digest mismatch");
  }
  return evidence;
}

function assertResidueClean(evidence) {
  assertResidueSnapshotClean(evidence);
  if (!Number.isInteger(evidence.stableSamples) || evidence.stableSamples < 2) {
    contractFail("runtime_residue_not_stable", "residue",
      "runtime residue must remain clean for at least two consecutive observations");
  }
  return evidence;
}

async function waitForCleanResidue(options) {
  const deadline = Date.now() + Number(options.timeoutMs || 30000);
  const requiredStable = Number(options.stableSamples || 3);
  if (!Number.isInteger(requiredStable) || requiredStable < 2 || requiredStable > 100) {
    contractFail("runtime_residue_stability_invalid", "residue",
      "stable residue sample count must be an integer in 2..100");
  }
  let stable = 0;
  let last = null;
  while (Date.now() <= deadline) {
    last = await observeRuntimeResidue(options);
    try { assertResidueSnapshotClean(last); stable += 1; }
    catch (_error) { stable = 0; }
    if (stable >= requiredStable) {
      const evidence = Object.assign({}, last, { stableSamples: stable });
      delete evidence.evidenceSha256;
      evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
      return evidence;
    }
    await sleep(Number(options.pollMs || 250));
  }
  contractFail("runtime_residue_timeout", "residue",
    "runtime residue did not remain clean for the required stable samples", { last, stable });
}

function assertFreshAuthenticatedRestart(options) {
  const identity = RuntimeGuard.assertFreshRestartIdentity(options);
  const first = options.firstSession;
  const restart = options.restartSession;
  verifySessionEvidenceEnvelope(first);
  verifySessionEvidenceEnvelope(restart);
  if (first.pid !== options.first.pid || restart.pid !== options.restart.pid
      || first.lifecycleId === restart.lifecycleId
      || first.processStartUtcTicks === restart.processStartUtcTicks
      || first.credentialFileSha256 === restart.credentialFileSha256
      || first.credentialTokenSha256 === restart.credentialTokenSha256) {
    contractFail("restart_session_not_fresh", "restart",
      "restart lacks a fresh authenticated process/credential lifecycle");
  }
  return Object.assign({}, identity, { firstLifecycleId: first.lifecycleId,
    restartLifecycleId: restart.lifecycleId });
}

module.exports = {
  AGENT_ENTER_COMMAND,
  API_VERSION,
  ARCHIVE_SCHEMA,
  LOG_BOUNDARY_SCHEMA,
  LOG_SNAPSHOT_SCHEMA,
  RESIDUE_SCHEMA,
  SESSION_SCHEMA,
  assertExclusiveLauncherProcess,
  assertFreshAuthenticatedRestart,
  assertResidueClean,
  assertResponseSucceeded,
  assertRuntimeReadyStatus,
  attestAuthenticatedLauncherProcess,
  captureDiskSaveEvidence,
  createTerminalLogBoundary,
  normalizeLogSnapshot,
  observeRuntimeResidue,
  openAuthenticatedLegacyHttpSession,
  parseExactArchiveRecord,
  queryLauncherCoreProcesses,
  recordsAfterTerminalBoundary,
  responseSucceeded,
  startLauncherCandidate,
  verifyArchiveSaveEvidence,
  verifyLogSnapshot,
  verifySessionEvidenceEnvelope,
  verifyTerminalLogBoundary,
  waitForAgentControl,
  waitForAuthenticatedLegacyHttp,
  waitForCleanResidue,
  waitForRuntimeReady,
};
