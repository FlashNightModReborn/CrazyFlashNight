"use strict";

const path = require("path");
const fs = require("fs");
const CloneGuard = require("../lib/clone-save-guard");
const ControlContract = require("../lib/control-contract");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const ModuleJournal = require("../lib/runtime-module-journal");
const RuntimeGuard = require("../lib/runtime-guard");
const {
  API_VERSION,
  AUTHORIZATION_SCHEMA,
  BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA,
  OWNED_BASE_RELATIVE,
  RECEIPT_SCHEMA,
  TOKEN_REF_RE,
  assertNoRawAuthority,
  buildArtifactManifest,
  decodePng,
  deepClone,
  fail,
  own,
  readJsonFile,
  verifyArtifactManifest,
} = require("./common");
const { REQUIRED_CONTROL_STEPS, RESULTS, TRANSPORTS,
  domInputEvidence, expectedControlIntent, validateAck, validateRequest, verifyAckCapture,
  verifyProviderReceiptReference } = require("./control-channel");
const Protocol = require("./protocol");
const SourceContract = require("./source-contract");

const TRUSTED_CAPABILITY_SOURCES = new Set([
  "authenticated_process_contract",
]);
const TRUSTED_AUTHORIZATION_SOURCES = new Set(["cli_explicit_flag"]);
const CRAFT_ACTIONS = Object.freeze({
  snapshot: "craftingSnapshot",
  preview: "craftingPreview",
  commit: "craftingCommit",
});
const INVENTORY_ACTIONS = Object.freeze({ snapshot: "inventorySnapshot" });
const LEGACY_CAPABILITY_ALLOWLIST = Object.freeze([
  "legacy.console", "legacy.diagnostic", "legacy.logs", "legacy.save_push",
  "legacy.shutdown", "legacy.status", "legacy.task",
]);
const PROCESS_CONTRACT_KEYS = Object.freeze([
  "agentRuntimeAdmission", "apiVersion", "argvSha256", "artifactSha256",
  "commandLineSha256", "legacyHttpAutomationArg", "observedAt", "pid",
  "processPath", "processStartUtcTicks", "projectRoot", "projectRootArgumentExact",
  "schema", "trustedSource",
]);
const CAPABILITY_KEYS = Object.freeze([
  "artifact", "artifactSha256", "available", "schema", "source",
]);
const CAPABILITY_ARTIFACT_KEYS = Object.freeze([
  "agentRuntimeAdmission", "argvSha256", "commandLineSha256",
  "credentialCapabilitiesSha256", "launchMode", "legacyHttpAutomationArg",
  "processContractSha256", "schema",
]);
const TEST_SOURCE_EVIDENCE_CACHE = new Map();

function same(left, right) {
  return Evidence.canonicalJson(left) === Evidence.canonicalJson(right);
}

function samePath(left, right) {
  const normalize = (value) => path.resolve(String(value || "")).replace(/\\/g, "/").toLowerCase();
  return normalize(left) === normalize(right);
}

function authoritativeIconNames(events, lifecycle) {
  const opens = (events || []).filter((event) => event && event.kind === "webview_message"
    && event.message && event.message.type === "panel_cmd" && event.message.panel === "crafting"
    && event.message.cmd === "open" && typeof event.message.panelInstanceId === "string"
    && event.message.panelInstanceId);
  if (opens.length !== 1) {
    fail("dynamic_icon_lifecycle_open_invalid", "source_identity",
      lifecycle + " transcript does not expose one exact Crafting owner");
  }
  const owner = opens[0].message.panelInstanceId;
  const names = [];
  function add(value) {
    const name = String(value || "").trim();
    if (name && !names.includes(name)) names.push(name);
  }
  function addItem(item) {
    if (!Evidence.isPlainObject(item)) return;
    add(item.icon);
    (Array.isArray(item.modSlots) ? item.modSlots : []).forEach((mod) => add(mod && mod.icon));
  }
  (events || []).filter((event) => event && event.kind === "webview_message"
    && event.message && event.message.type === "panel_resp"
    && event.message.panel === "crafting" && event.message.panelInstanceId === owner
    && event.message.success === true).forEach((event) => {
    const message = event.message;
    (Array.isArray(message.recipes) ? message.recipes : []).forEach((recipe) =>
      addItem(recipe && recipe.output));
    addItem(message.output);
    addItem(message.crafted);
    (Array.isArray(message.materials) ? message.materials : []).forEach(addItem);
    (Array.isArray(message.snapshots) ? message.snapshots : []).forEach((snapshot) => {
      (snapshot && Array.isArray(snapshot.slots) ? snapshot.slots : []).forEach((slot) => {
        if (slot && slot.occupied === true) addItem(slot.item);
      });
    });
  });
  if (!names.length) {
    fail("dynamic_icon_authority_empty", "source_identity",
      lifecycle + " authoritative responses expose no icon names");
  }
  return names;
}

function orderedSubset(actual, expected) {
  let cursor = 0;
  for (const value of actual) {
    while (cursor < expected.length && expected[cursor] !== value) cursor += 1;
    if (cursor >= expected.length) return false;
    cursor += 1;
  }
  return true;
}

function assertDecodablePng(filePath, phase) {
  let bytes;
  try { bytes = fs.readFileSync(filePath); }
  catch (_error) {
    fail("control_capture_decode_invalid", phase, "PNG capture file is unreadable");
  }
  decodePng(bytes);
  return true;
}
function requireObject(value, code, phase, message) {
  if (!Evidence.isPlainObject(value)) fail(code, phase, message);
  return value;
}

function verifyDigestObject(value, field, code, phase) {
  requireObject(value, code, phase, "digest-bound artifact is missing");
  const digest = String(value[field] || "");
  const payload = Object.assign({}, value);
  delete payload[field];
  if (!/^[a-f0-9]{64}$/.test(digest)
      || Evidence.sha256Text(Evidence.canonicalJson(payload)) !== digest) {
    fail(code, phase, "digest-bound artifact changed");
  }
  return value;
}

function validateEnvelope(bundle, options) {
  requireObject(bundle, "bundle_invalid", "bundle", "journey bundle is missing");
  if (bundle.schema !== BUNDLE_SCHEMA || bundle.apiVersion !== API_VERSION
      || bundle.status !== "captured_unverified" || bundle.deployment !== "NOT_DEPLOYED"
      || typeof bundle.root !== "string" || !path.isAbsolute(bundle.root)
      || typeof bundle.runDir !== "string" || !path.isAbsolute(bundle.runDir)
      || !/^[A-Za-z0-9._~-]{1,160}$/.test(String(bundle.runId || ""))
      || typeof bundle.candidateRoot !== "string" || !path.isAbsolute(bundle.candidateRoot)
      || bundle.seedSlot === bundle.targetSlot
      || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(String(bundle.targetSlot || ""))
      || bundle.allowIsolatedCommit !== true || bundle.allowCodexCuFallback !== true
      || !["production_capture", "offline_fixture"].includes(bundle.evidenceClass)
      || !["live_capture", "offline_fixture"].includes(bundle.evidenceMode)
      || (bundle.evidenceClass === "production_capture") !== (bundle.evidenceMode === "live_capture")
      || (bundle.evidenceMode === "live_capture"
        ? bundle.fixtureProvenance !== null || bundle.safeExitUiJourneyVerified !== true
          || bundle.exitMethod !== "safeexit_ui"
        : !Evidence.isPlainObject(bundle.fixtureProvenance)
          || bundle.fixtureProvenance.schema
            !== "workbench-live-e2e.crafting.fixture-provenance.v1"
          || bundle.fixtureProvenance.generator !== "fixtures/valid-bundle.js"
          || bundle.fixtureProvenance.synthetic !== true
          || bundle.fixtureProvenance.liveCapture !== false
          || bundle.safeExitUiJourneyVerified !== false
          || bundle.exitMethod !== "offline_fixture_simulation")) {
    fail("bundle_invalid", "bundle", "Crafting journey envelope/scope is malformed");
  }
  if (bundle.evidenceClass !== "production_capture"
      && !(options && options.testOnlyAllowInjectedEvidence === true
        && bundle.evidenceClass === "offline_fixture")) {
    fail("offline_fixture_verdict_forbidden", "bundle",
      "offline fixture evidence cannot receive a live verification verdict");
  }
  CloneGuard.assertSourceSlot(bundle.seedSlot);
  CloneGuard.assertDedicatedSlot(bundle.targetSlot);
  assertNoRawAuthority(bundle, "bundle");
  return bundle;
}

function verifyProcessContract(artifact, session, identity, root) {
  verifyDigestObject(artifact, "artifactSha256",
    "launcher_process_contract_invalid", "runtime");
  if (!same(Object.keys(artifact).sort(), PROCESS_CONTRACT_KEYS.slice().sort())
      || artifact.schema !== "workbench-live-e2e.launcher-process-contract.v1"
      || artifact.apiVersion !== LauncherObservation.API_VERSION
      || artifact.pid !== identity.pid || artifact.pid !== session.pid
      || path.resolve(artifact.processPath || "") !== path.resolve(identity.processPath)
      || String(artifact.processStartUtcTicks) !== String(session.processStartUtcTicks)
      || !/^[a-f0-9]{64}$/.test(String(artifact.commandLineSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(artifact.argvSha256 || ""))
      || artifact.projectRootArgumentExact !== true
      || artifact.agentRuntimeAdmission !== false
      || artifact.legacyHttpAutomationArg !== true
      || !samePath(artifact.projectRoot, root)
      || artifact.trustedSource !== "actual_process_command_line+pid_bound_credential") {
    fail("launcher_process_contract_invalid", "runtime",
      "actual argv does not prove the authenticated legacy-only candidate lifecycle");
  }
  return artifact;
}

function verifyRuntime(bundle) {
  const runtime = requireObject(bundle.runtime, "runtime_invalid", "runtime",
    "runtime evidence is missing");
  const first = requireObject(runtime.first, "runtime_first_invalid", "runtime",
    "first lifecycle is missing");
  const restart = requireObject(runtime.restart, "runtime_restart_invalid", "runtime",
    "restart lifecycle is missing");
  RuntimeGuard.validateCandidateIdentity(first.identity, bundle.candidateRoot);
  RuntimeGuard.validateCandidateIdentity(restart.identity, bundle.candidateRoot);
  if (!same(RuntimeGuard.publicCandidateIdentity(first.identity), runtime.expectedIdentity)
      || !same(RuntimeGuard.publicCandidateIdentity(restart.identity), runtime.expectedIdentity)) {
    fail("candidate_identity_drift", "runtime",
      "candidate identity changed across the same-clone restart");
  }
  const firstSession = LauncherObservation.verifySessionEvidenceEnvelope(first.sessionEvidence);
  const restartSession = LauncherObservation.verifySessionEvidenceEnvelope(restart.sessionEvidence);
  if (!same(firstSession.capabilities, LEGACY_CAPABILITY_ALLOWLIST)
      || !same(restartSession.capabilities, LEGACY_CAPABILITY_ALLOWLIST)) {
    fail("legacy_credential_allowlist_invalid", "runtime",
      "authenticated credential capabilities differ from the current exact legacy allowlist");
  }
  if (firstSession.pid !== first.identity.pid || restartSession.pid !== restart.identity.pid) {
    fail("session_pid_binding_invalid", "runtime", "authenticated session crossed runtime PID");
  }
  const firstProcessContract = verifyProcessContract(
    first.processContract, firstSession, first.identity, bundle.root);
  const restartProcessContract = verifyProcessContract(
    restart.processContract, restartSession, restart.identity, bundle.root);
  const trusted = requireObject(runtime.trustedCdpExpectations,
    "cdp_trusted_expectations_missing", "runtime", "independent CDP expectations are missing");
  RuntimeGuard.assertRuntimeCdpBinding(first.cdpBinding, first.identity, trusted);
  RuntimeGuard.assertRuntimeCdpBinding(restart.cdpBinding, restart.identity, trusted);
  LauncherObservation.assertFreshAuthenticatedRestart({
    first: first.identity, restart: restart.identity,
    firstAttemptId: first.attemptId, restartAttemptId: restart.attemptId,
    firstSession, restartSession,
  });
  if (first.cdpBinding.port === restart.cdpBinding.port
      || first.cdpBinding.pageIdentity.timeOrigin === restart.cdpBinding.pageIdentity.timeOrigin) {
    fail("restart_cdp_not_fresh", "runtime", "restart reused CDP port/page lifetime");
  }
  const shutdownEvidence = verifyDigestObject(restart.shutdownEvidence,
    "evidenceSha256", "authenticated_shutdown_invalid", "runtime");
  const shutdownKeys = ["completedAt", "evidenceSha256", "pid", "requestedAt",
    "response", "schema", "sessionEvidenceSha256"];
  if (!same(Object.keys(shutdownEvidence).sort(), shutdownKeys.slice().sort())
      || shutdownEvidence.schema !== "workbench-live-e2e.crafting.authenticated-shutdown.v1"
      || shutdownEvidence.pid !== restart.identity.pid
      || shutdownEvidence.sessionEvidenceSha256 !== restartSession.sessionEvidenceSha256
      || !Number.isFinite(Date.parse(shutdownEvidence.requestedAt))
      || !Number.isFinite(Date.parse(shutdownEvidence.completedAt))
      || Date.parse(shutdownEvidence.completedAt) < Date.parse(shutdownEvidence.requestedAt)) {
    fail("authenticated_shutdown_invalid", "runtime",
      "restart shutdown evidence is detached from the authenticated lifecycle");
  }
  LauncherObservation.assertResponseSucceeded(shutdownEvidence.response,
    "runtime", "authenticated restart shutdown");
  return { first, restart, firstSession, restartSession,
    firstProcessContract, restartProcessContract, shutdownEvidence };
}

function verifyLifecycleTranscript(transcript, phase) {
  const ready = transcript.events.filter((event) => event.kind === "observer_ready");
  const bound = transcript.events.filter((event) => event.kind === "cdp_endpoint_bound");
  const detached = transcript.events.filter((event) =>
    ["observer_detached", "observer_detach_transport_lost"].includes(event.kind));
  if (ready.length !== 1 || bound.length !== 1 || detached.length !== 1
      || !(bound[0].sequence < ready[0].sequence
        && ready[0].sequence < detached[0].sequence)) {
    fail("observer_lifecycle_invalid", phase,
      "passive observer attach/detach lifecycle is not exact");
  }
}

function parseTimestampedHostLine(line, sourceLineNumber, lifecycle) {
  const match = /^(\d{2}):(\d{2}):(\d{2})\.(\d{3}) ([^\r\n]+)$/.exec(String(line || ""));
  const hour = match && Number(match[1]);
  const minute = match && Number(match[2]);
  const second = match && Number(match[3]);
  if (!match || hour > 23 || minute > 59 || second > 59) {
    fail("host_log_formatter_invalid", "host_log",
      "Host log record is not one exact current LogManager line", { sourceLineNumber, lifecycle });
  }
  return { body: match[5], timestamp: match[1] + ":" + match[2] + ":" + match[3]
      + "." + match[4],
    timeOfDayMs: ((hour * 60 + minute) * 60 + second) * 1000 + Number(match[4]) };
}

function recordsForLifecycle(lifecycle, label) {
  LauncherObservation.verifyTerminalLogBoundary(lifecycle.startBoundary);
  LauncherObservation.verifyLogSnapshot(lifecycle.finalLogSnapshot);
  if (lifecycle.startBoundary.terminalSessionEvidenceSha256
      !== lifecycle.sessionEvidence.sessionEvidenceSha256
      || lifecycle.finalLogSnapshot.sessionEvidenceSha256
        !== lifecycle.sessionEvidence.sessionEvidenceSha256) {
    fail("host_log_session_mismatch", "host_log",
      "terminal boundary/tail crossed the authenticated lifecycle", { label });
  }
  const records = LauncherObservation.recordsAfterTerminalBoundary(
    lifecycle.startBoundary, lifecycle.finalLogSnapshot).map((record, index) => {
      const parsed = parseTimestampedHostLine(record.line, record.lineNumber, label);
      return { lineNumber: index + 1, sourceLineNumber: record.lineNumber,
        lifecycle: label, body: parsed.body, timestamp: parsed.timestamp,
        timeOfDayMs: parsed.timeOfDayMs, observedAt: null };
    });
  if (!records.length) return records;
  const capturedAt = new Date(lifecycle.finalLogSnapshot.capturedAt);
  if (!Number.isFinite(capturedAt.getTime())) {
    fail("host_log_snapshot_invalid", "host_log",
      "authenticated Host snapshot capture time is invalid", { label });
  }
  const firstValue = records[0].timeOfDayMs;
  let currentDate = new Date(capturedAt.getFullYear(), capturedAt.getMonth(), capturedAt.getDate(),
    Math.floor(firstValue / 3600000), Math.floor(firstValue / 60000) % 60,
    Math.floor(firstValue / 1000) % 60, firstValue % 1000);
  if (currentDate.getTime() > capturedAt.getTime()) currentDate.setDate(currentDate.getDate() - 1);
  let previousTimeOfDay = firstValue;
  let rolloverCount = 0;
  records.forEach((record, index) => {
    const value = record.timeOfDayMs;
    if (index > 0 && value < previousTimeOfDay) {
      const previousHour = Math.floor(previousTimeOfDay / 3600000);
      const currentHour = Math.floor(value / 3600000);
      if (previousHour !== 23 || currentHour !== 0 || rolloverCount !== 0) {
        fail("host_timeline_regression", "host_log",
          "Host records regress outside one exact 23:xx to 00:xx rollover", {
            label, previousLineNumber: records[index - 1].sourceLineNumber,
            lineNumber: record.sourceLineNumber, previousTimeOfDay,
            currentTimeOfDay: value, rolloverCount,
          });
      }
      rolloverCount += 1;
      currentDate.setDate(currentDate.getDate() + 1);
    }
    const candidate = new Date(currentDate.getFullYear(), currentDate.getMonth(),
      currentDate.getDate(), Math.floor(value / 3600000), Math.floor(value / 60000) % 60,
      Math.floor(value / 1000) % 60, value % 1000);
    const previousObserved = index > 0 ? Date.parse(records[index - 1].observedAt) : null;
    if (previousObserved !== null && candidate.getTime() < previousObserved) {
      fail("host_timeline_regression", "host_log",
        "Host timeline is non-monotonic after calendar reconstruction", {
          label, lineNumber: record.sourceLineNumber, rolloverCount,
        });
    }
    record.observedAt = candidate.toISOString();
    previousTimeOfDay = value;
  });
  const firstObserved = Date.parse(records[0].observedAt);
  const lastObserved = Date.parse(records[records.length - 1].observedAt);
  if (lastObserved > capturedAt.getTime()
      || capturedAt.getTime() - firstObserved > 36 * 60 * 60 * 1000) {
    fail("host_timeline_time_invalid", "host_log",
      "Host record timeline is future-dated or outside the bounded snapshot window", {
        label, rolloverCount,
      });
  }
  return records;
}

const AUTHORITY_KEYS = Object.freeze([
  "expectedCraftToken", "craftToken", "expectedLease", "slotLease", "transactionId",
]);

function parseAuthorityTail(tail, record) {
  const fields = Object.create(null);
  const text = String(tail || "");
  if (!text) return fields;
  if (!/^ (?:[A-Za-z][A-Za-z0-9]*=[^\s]+)(?: [A-Za-z][A-Za-z0-9]*=[^\s]+)*$/.test(text)) {
    fail("host_authority_summary_invalid", "host_log",
      "authority summary tail is not an exact key/value sequence", { line: record.sourceLineNumber });
  }
  text.trim().split(/\s+/).forEach((entry) => {
    const split = entry.indexOf("=");
    const key = entry.slice(0, split);
    const value = entry.slice(split + 1);
    const base = AUTHORITY_KEYS.find((candidate) => key.startsWith(candidate));
    const suffix = base ? key.slice(base.length) : "";
    const numeric = ["authorityFieldCount", "unknownAuthorityFieldCount",
      "unknownAuthorityRefCount"].includes(key) || suffix === "RefCount";
    const reference = suffix === "Ref" || suffix === "Refs" || key === "unknownAuthorityRefs";
    const present = suffix === "Present";
    if (Object.prototype.hasOwnProperty.call(fields, key)
        || (!numeric && !reference && !present)
        || (numeric && !/^(?:0|[1-9]\d*)$/.test(value))
        || (reference && !/^sha256_[a-f0-9]{24}(?:,sha256_[a-f0-9]{24}){0,3}$/.test(value))
        || (present && value !== "true")) {
      fail("host_authority_summary_invalid", "host_log",
        "authority summary has an unknown/duplicate/malformed field", { key });
    }
    fields[key] = value;
  });
  return fields;
}

function requireAuthorityKeys(value, expected, phase, locator) {
  const actual = Object.keys(value || {}).sort();
  const wanted = expected.slice().sort();
  if (!same(actual, wanted)) {
    fail("host_authority_field_set_invalid", phase,
      "authority log field set has extras, omissions, or a transaction-field overclaim", {
        locator, actual, expected: wanted,
      });
  }
  if (own(value, "authorityFieldCount")
      && Number(value.authorityFieldCount) !== wanted.filter((key) => key.endsWith("Ref")).length) {
    fail("host_authority_field_count_invalid", phase,
      "authorityFieldCount does not match the exact reference field set", { locator });
  }
}

function parsePanel(record) {
  const prefix = "[Panel] HandlePanelMessage: ";
  if (!record.body.startsWith(prefix)) return null;
  const match = /^task=panel panel=(crafting|other) domain=(crafting|inventory|other) cmd=([A-Za-z][A-Za-z0-9]*|other) callId=([A-Za-z0-9._:-]{1,96}|other)( envelope=near_match)? payload=redacted len=(\d+)(.*)$/
    .exec(record.body.slice(prefix.length));
  if (!match || match[5]) {
    fail("host_panel_summary_invalid", "host_log",
      "Crafting panel log is not one exact redacted envelope");
  }
  return { panel: match[1], domain: match[2], cmd: match[3], callId: match[4],
    payloadLength: Number(match[6]), authority: parseAuthorityTail(match[7], record) };
}

function parseFlash(record) {
  const craftingPrefix = "[CraftingTask] -> Flash: ";
  const inventoryPrefix = "[InventoryTask] -> Flash: ";
  const domain = record.body.startsWith(craftingPrefix) ? "crafting"
    : record.body.startsWith(inventoryPrefix) ? "inventory" : null;
  if (!domain) return null;
  const prefix = domain === "crafting" ? craftingPrefix : inventoryPrefix;
  const match = /^task=cmd cmd=(craftingSnapshot|craftingPreview|craftingCommit|inventorySnapshot|other) callId=(\d+|other) payload=redacted len=(\d+)(.*)$/
    .exec(record.body.slice(prefix.length));
  if (!match || match[1] === "other" || match[2] === "other") {
    fail("host_flash_summary_invalid", "host_log",
      "Crafting Host-to-Flash log is not one exact redacted command");
  }
  return { domain, action: match[1], callId: Number(match[2]), payloadLength: Number(match[3]),
    authority: parseAuthorityTail(match[4], record) };
}

function parseSocket(record) {
  const prefix = "[XmlSocket:JSON] ";
  if (!record.body.startsWith(prefix)) return null;
  const text = record.body.slice(prefix.length);
  if (/^[{[]/.test(text)) {
    let parsed;
    try { parsed = JSON.parse(text); } catch (_error) {
      fail("host_socket_json_invalid", "host_log",
        "XmlSocket JSON log is malformed inside the isolated journey");
    }
    if (parsed.task === "crafting_response" || parsed.task === "inventory_response") {
      fail("host_socket_unredacted_forbidden", "host_log",
        "raw Crafting authority response appeared in persistent logs");
    }
    const family = String(parsed.task || "").toLowerCase().replace(/[^a-z]/g, "");
    if (family.startsWith("craftingresponse") || family.startsWith("inventoryresponse")
        || family === "authorityresponsefamily") {
      fail("host_socket_near_match_forbidden", "host_log",
        "raw Crafting/Inventory response-family near-match appeared in persistent logs");
    }
    return { raw: parsed };
  }
  const match = /^task=(crafting_response|inventory_response) cmd=([A-Za-z][A-Za-z0-9]*|other) callId=(\d+|other) success=(true|false|unknown) payload=redacted len=(\d+)(.*)$/
    .exec(text);
  if (!match) {
    if (/^task=(?:authority_response_family|crafting_response|inventory_response)\b/i.test(text)) {
      fail("host_socket_near_match_forbidden", "host_log",
        "Crafting/Inventory response-family near-match or malformed summary is forbidden", {
          line: record.sourceLineNumber,
        });
    }
    return null;
  }
  if (match[3] === "other") {
    fail("host_socket_summary_invalid", "host_log",
      "Crafting response summary lacks a numeric fid");
  }
  return { task: match[1], cmd: match[2], callId: Number(match[3]), success: match[4],
    payloadLength: Number(match[5]), authority: parseAuthorityTail(match[6], record) };
}

function parseDispatch(record) {
  const match = /^event=authority_flash_call_bound domain=(crafting|inventory) webCallId=([A-Za-z0-9._-]{1,96}) flashCallId=([1-9]\d*) panel=(crafting) panelInstanceId=([A-Za-z0-9._~-]{1,160}) cmd=(snapshot|preview|commit) action=(craftingSnapshot|craftingPreview|craftingCommit|inventorySnapshot)$/
    .exec(record.body);
  if (!match) {
    if (record.body.startsWith("event=authority_flash_call_bound")) {
      fail("host_dispatch_summary_invalid", "host_log",
        "authority call-bound record is malformed or outside the exact Crafting/Inventory set", {
          line: record.sourceLineNumber,
        });
    }
    return null;
  }
  return { domain: match[1], webCallId: match[2], flashCallId: Number(match[3]),
    panel: match[4], panelInstanceId: match[5], cmd: match[6], action: match[7] };
}

function parseRoute(record) {
  const match = /^\[Panel\] Routing domain=(crafting|inventory) cmd=(snapshot|preview|commit) to (CraftingTask|InventoryTask), (_craftingTask|_inventoryTask)=ok$/
    .exec(record.body);
  if (!match) {
    if (record.body.startsWith("[Panel] Routing domain=crafting")
        || record.body.startsWith("[Panel] Routing domain=inventory")) {
      fail("host_route_summary_invalid", "host_log",
        "Crafting/Inventory route is malformed or outside the exact family", {
          line: record.sourceLineNumber,
        });
    }
    return null;
  }
  const expectedTask = match[1] === "crafting" ? "CraftingTask" : "InventoryTask";
  const expectedField = match[1] === "crafting" ? "_craftingTask" : "_inventoryTask";
  if (match[3] !== expectedTask || match[4] !== expectedField
      || match[1] === "inventory" && match[2] !== "snapshot") {
    fail("host_route_summary_invalid", "host_log",
      "Crafting/Inventory route target does not match its domain");
  }
  return { domain: match[1], cmd: match[2], task: match[3] };
}

function parseCloseCompletion(record) {
  const prefix = "event=panel_exact_close_completed";
  if (!record.body.startsWith(prefix)) return null;
  const match = /^event=panel_exact_close_completed panel=crafting panelInstanceId=([A-Za-z0-9._~-]{1,160})$/
    .exec(record.body);
  if (!match) {
    fail("host_close_completion_invalid", "host_log",
      "exact close completion receipt is malformed or for another panel", {
        line: record.sourceLineNumber,
      });
  }
  return { panel: "crafting", panelInstanceId: match[1] };
}

function classifyRelevantHostRecord(record) {
  if (/^\[Panel\] rejected message from a non-ready Web document cmd=/.test(record.body)) {
    fail("host_non_ready_rejection_present", "host_log",
      "production non-ready rejection is relevant and forbids Crafting admission", {
        line: record.sourceLineNumber, body: record.body,
      });
  }
  const panel = parsePanel(record);
  if (panel) return panel.domain === "other" ? "incoming_close" : "panel";
  const route = parseRoute(record);
  if (route) return "route";
  if (parseDispatch(record)) return "dispatch";
  if (parseFlash(record)) return "flash";
  const socket = parseSocket(record);
  if (socket && socket.raw && socket.raw.task === "panel_request"
      && (socket.raw.panel === "crafting"
        || socket.raw.payload && socket.raw.payload.panel === "crafting")) return "ingress";
  if (socket && ["crafting_response", "inventory_response"].includes(socket.task)) return "response";
  if (parseCloseCompletion(record)) return "close_completion";
  if (/(?:\[CraftingTask\]|\[InventoryTask\]|panel=crafting|domain=(?:crafting|inventory)|panel_exact_close_completed)/i
      .test(record.body)) {
    fail("host_relevant_record_unclassified", "host_log",
      "Crafting relevant Host record is rejected/deferred/racy/near-match or otherwise unclassified", {
        line: record.sourceLineNumber, body: record.body,
      });
  }
  return null;
}

function verifyHostClose(close, records, phase, lastPanelLine) {
  const matches = records.map((record) => ({ record, value: parsePanel(record) }))
    .filter((entry) => entry.value && entry.value.panel === "crafting"
      && entry.value.domain === "other" && entry.value.cmd === "close"
      && entry.value.callId === "other");
  if (matches.length !== 1) {
    fail("host_close_count_invalid", "host_log",
      "one exact domain-less Crafting close must reach Host", { phase, count: matches.length });
  }
  requireAuthorityKeys(matches[0].value.authority, [], "host_log", "close");
  const completions = records.map((record) => ({ record, value: parseCloseCompletion(record) }))
    .filter((entry) => entry.value);
  if (!close || close.message.panelInstanceId == null
      || matches[0].record.sourceLineNumber <= lastPanelLine
      || completions.length !== 1
      || completions[0].value.panelInstanceId !== close.message.panelInstanceId
      || completions[0].record.sourceLineNumber <= matches[0].record.sourceLineNumber) {
    fail("host_close_order_invalid", "host_log",
      "incoming close and unique exact owner close completion are detached or out of order", {
        phase, completionCount: completions.length,
      });
  }
  return { phase, owner: close.message.panelInstanceId,
    panelLine: matches[0].record.sourceLineNumber,
    completionLine: completions[0].record.sourceLineNumber,
    completionTimeOfDayMs: completions[0].record.timeOfDayMs,
    completionObservedAt: completions[0].record.observedAt };
}

function verifyIngress(records, open, phase) {
  const matches = records.map((record) => ({ record, socket: parseSocket(record) }))
    .filter((entry) => entry.socket && entry.socket.raw
      && entry.socket.raw.task === "panel_request"
      && (entry.socket.raw.panel === "crafting"
        || entry.socket.raw.payload && entry.socket.raw.payload.panel === "crafting"));
  if (matches.length !== 1) {
    fail("production_ingress_invalid", "host_log",
      "one exact AS2 panel_request ingress is required", { phase, count: matches.length });
  }
  const value = matches[0].socket.raw;
  const payload = Evidence.isPlainObject(value.payload) ? value.payload : value;
  const init = Evidence.isPlainObject(payload.initData) ? payload.initData : payload;
  if (payload.source !== "world_crafting_entry" && value.source !== "world_crafting_entry"
      || String(init.category || payload.category || "") !== open.category) {
    fail("production_ingress_invalid", "host_log",
      "AS2 ingress is not bound to the world Crafting entry/category");
  }
  assertNoRawAuthority(value, "host_ingress");
  return matches[0].record.sourceLineNumber;
}

function verifyHostPair(pair, records, phase) {
  const panels = records.map((record) => ({ record, value: parsePanel(record) }))
    .filter((entry) => entry.value && entry.value.panel === "crafting"
      && entry.value.domain === pair.request.domain && entry.value.cmd === pair.request.cmd
      && entry.value.callId === pair.request.callId);
  if (panels.length !== 1) {
    fail("host_panel_request_count_invalid", "host_log",
      "Web request does not appear exactly once in Host log", {
        phase, cmd: pair.request.cmd, callId: pair.request.callId, count: panels.length,
      });
  }
  const panel = panels[0];
  const commitAuthorityKeys = pair.request.domain === "crafting" && pair.request.cmd === "commit"
    ? ["authorityFieldCount", "expectedCraftTokenRef"] : [];
  requireAuthorityKeys(panel.value.authority, commitAuthorityKeys, "host_log", "panel");
  if (pair.request.cmd === "commit"
      && panel.value.authority.expectedCraftTokenRef
        !== pair.request.payload.expectedCraftTokenRef) {
    fail("host_panel_authority_ref_mismatch", "host_log",
      "redacted Host panel token reference is detached from Web commit");
  }
  const nextPanel = records.find((record) => record.lineNumber > panel.record.lineNumber
    && record.body.startsWith("[Panel] HandlePanelMessage: "));
  const within = (record) => !nextPanel || record.lineNumber < nextPanel.lineNumber;
  const taskName = pair.request.domain === "crafting" ? "CraftingTask" : "InventoryTask";
  const routeField = pair.request.domain === "crafting" ? "_craftingTask" : "_inventoryTask";
  const actions = pair.request.domain === "crafting" ? CRAFT_ACTIONS : INVENTORY_ACTIONS;
  const routeText = "[Panel] Routing domain=" + pair.request.domain + " cmd=" + pair.request.cmd
    + " to " + taskName + ", " + routeField + "=ok";
  const routes = records.filter((record) => record.lineNumber > panel.record.lineNumber
    && within(record) && record.body === routeText);
  if (routes.length !== 1) fail("host_route_missing", "host_log",
    "exact Crafting Host route is missing", { routeText });
  const dispatches = records.map((record) => ({ record, value: parseDispatch(record) }))
    .filter((entry) => entry.value && entry.record.lineNumber > routes[0].lineNumber
      && within(entry.record) && entry.value.webCallId === pair.request.callId
      && entry.value.cmd === pair.request.cmd
      && entry.value.action === actions[pair.request.cmd]
      && entry.value.panel === pair.request.panel
      && entry.value.domain === pair.request.domain
      && entry.value.panelInstanceId === pair.request.panelInstanceId);
  if (dispatches.length !== 1) {
    fail("host_dispatch_receipt_invalid", "host_log",
      "exact Web callId-to-AS2 fid binding lacks one trusted receipt", {
        phase, webCallId: pair.request.callId, count: dispatches.length,
      });
  }
  const dispatch = dispatches[0];
  const sends = records.map((record) => ({ record, value: parseFlash(record) }))
    .filter((entry) => entry.value
      && entry.record.lineNumber > dispatch.record.lineNumber
      && within(entry.record)
      && entry.value.domain === pair.request.domain
      && entry.value.action === dispatch.value.action
      && entry.value.callId === dispatch.value.flashCallId);
  if (sends.length !== 1) {
    fail("host_flash_send_count_invalid", "host_log",
      "one binding interval lacks one exact same-fid Crafting Flash command");
  }
  const send = sends[0];
  requireAuthorityKeys(send.value.authority, commitAuthorityKeys, "host_log", "flash");
  if (pair.request.cmd === "commit"
      && send.value.authority.expectedCraftTokenRef
        !== pair.request.payload.expectedCraftTokenRef) {
    fail("host_flash_authority_ref_mismatch", "host_log",
      "redacted Host-to-Flash token reference is detached from Web commit");
  }
  const nextSend = records.find((record) => record.lineNumber > send.record.lineNumber
    && record.body.startsWith("[" + taskName + "] -> Flash: "));
  const beforeNextSend = (record) => !nextSend || record.lineNumber < nextSend.lineNumber;
  const responses = records.map((record) => ({ record, value: parseSocket(record) }))
    .filter((entry) => entry.value && entry.value.task === (pair.request.domain === "crafting"
      ? "crafting_response" : "inventory_response")
      && entry.record.lineNumber > send.record.lineNumber && beforeNextSend(entry.record));
  if (responses.length !== 1 || responses[0].value.callId !== send.value.callId
      || responses[0].value.cmd !== pair.request.cmd
      || responses[0].value.success !== "true") {
    fail("host_flash_roundtrip_invalid", "host_log",
      "Host send is not followed by one same-fid successful AS2 response", {
        phase, expectedFid: send.value.callId,
      });
  }
  const responseAuthorityKeys = pair.request.domain === "crafting" && pair.request.cmd === "preview"
    ? ["authorityFieldCount", "craftTokenRef"] : [];
  requireAuthorityKeys(responses[0].value.authority, responseAuthorityKeys,
    "host_log", "response");
  if (pair.request.cmd === "preview"
      && responses[0].value.authority.craftTokenRef !== pair.response.craftTokenRef) {
    fail("host_socket_authority_ref_mismatch", "host_log",
      "AS2 preview token reference is detached from Web response");
  }
  return { phase, webCallId: pair.request.callId, as2Fid: send.value.callId,
    owner: pair.request.panelInstanceId, panel: pair.request.panel,
    domain: pair.request.domain, cmd: pair.request.cmd,
    panelLine: panel.record.sourceLineNumber, routeLine: routes[0].sourceLineNumber,
    flashLine: send.record.sourceLineNumber,
    dispatchLine: dispatch.record.sourceLineNumber,
    as2ResponseLine: responses[0].record.sourceLineNumber,
    as2ResponseTimeOfDayMs: responses[0].record.timeOfDayMs,
    as2ResponseObservedAt: responses[0].record.observedAt };
}

function verifyHost(bundle, runtime, first, restart) {
  const firstRecords = recordsForLifecycle(runtime.first, "first");
  const restartRecords = recordsForLifecycle(runtime.restart, "restart");
  const ingress = {
    first: verifyIngress(firstRecords, { category: first.category }, "first"),
    restart: verifyIngress(restartRecords, { category: restart.category }, "restart"),
  };
  const firstMappings = first.allPairs.map((pair) => verifyHostPair(pair, firstRecords, "first"));
  const restartMappings = restart.allPairs.map((pair) =>
    verifyHostPair(pair, restartRecords, "restart"));
  const firstClose = verifyHostClose(first.close, firstRecords, "first",
    firstMappings[firstMappings.length - 1].panelLine);
  const restartClose = verifyHostClose(restart.close, restartRecords, "restart",
    restartMappings[restartMappings.length - 1].panelLine);
  const all = firstMappings.concat(restartMappings);
  if (ingress.first >= firstMappings[0].panelLine
      || ingress.restart >= restartMappings[0].panelLine) {
    fail("business_before_ingress", "host_log",
      "business traffic preceded the authenticated AS2 production ingress");
  }
  if (new Set(all.map((entry) => entry.webCallId)).size !== all.length
      || new Set(all.map((entry) => entry.phase + ":" + entry.as2Fid)).size !== all.length) {
    fail("cross_lifecycle_call_mapping_reused", "host_log",
      "Web callId/fid mapping is not exact across lifecycle boundaries");
  }
  [firstMappings, restartMappings].forEach((mappings, phaseIndex) => {
    mappings.forEach((entry, index) => {
      if (index > 0 && entry.panelLine <= mappings[index - 1].panelLine) {
        fail("host_request_order_invalid", "host_log",
          "Host authority order differs from the passive Web request order", {
            phase: phaseIndex === 0 ? "first" : "restart", index,
          });
      }
    });
  });
  [[firstRecords, firstMappings, "first"], [restartRecords, restartMappings, "restart"]]
    .forEach(([records, mappings, phase]) => {
      const families = records.map(classifyRelevantHostRecord).filter(Boolean);
      const count = (name) => families.filter((entry) => entry === name).length;
      if (count("ingress") !== 1 || count("panel") !== mappings.length
          || count("route") !== mappings.length || count("dispatch") !== mappings.length
          || count("flash") !== mappings.length || count("response") !== mappings.length
          || count("incoming_close") !== 1 || count("close_completion") !== 1
          || families.length !== 2 + mappings.length * 5 + 1) {
        fail("host_command_multiset_invalid", "host_log",
          "terminal boundary has extra/missing relevant Host families", {
            phase, families,
          });
      }
    });
  return { firstRecords, restartRecords, firstMappings, restartMappings,
    firstClose, restartClose, ingress };
}

function verifyControl(bundle, first, restart) {
  const control = requireObject(bundle.control, "control_invalid", "control",
    "control evidence is missing");
  if (!same(Object.keys(control).sort(), ["acks", "authorization", "authorizationSha256",
    "capability", "fallbackAllowed", "preCommitAdmission", "requests",
    "selectedTransport"].sort())) {
    fail("control_invalid", "control", "control evidence field set is not exact");
  }
  const capabilityEvidence = requireObject(control.capability,
    "control_capability_invalid", "control", "control capability evidence is missing");
  const capabilityArtifact = requireObject(capabilityEvidence.artifact,
    "control_capability_invalid", "control", "control capability artifact is missing");
  if (!same(Object.keys(capabilityEvidence).sort(), CAPABILITY_KEYS.slice().sort())
      || !same(Object.keys(capabilityArtifact).sort(), CAPABILITY_ARTIFACT_KEYS.slice().sort())
      || capabilityEvidence.schema !== CAPABILITY_SCHEMA
      || control.selectedTransport !== "codex_computer_use"
      || control.fallbackAllowed !== true || bundle.allowCodexCuFallback !== true
      || capabilityEvidence.available !== false
      || capabilityArtifact.agentRuntimeAdmission !== false
      || capabilityArtifact.legacyHttpAutomationArg !== true
      || capabilityArtifact.credentialCapabilitiesSha256
        !== Evidence.sha256Text(Evidence.canonicalJson(
          bundle.runtime.first.sessionEvidence.capabilities))
      || capabilityArtifact.launchMode !== "legacy_http_automation"
      || capabilityArtifact.processContractSha256
        !== bundle.runtime.first.processContract.artifactSha256) {
    fail("control_capability_invalid", "control",
      "authenticated legacy-only argv requires the explicit Codex CU fallback");
  }
  const capability = ControlContract.verifyCapabilityDecision({
    capability: control.capability, trustedSources: TRUSTED_CAPABILITY_SOURCES,
    selectedTransport: control.selectedTransport,
    preferredTransport: "launcher_agent_runtime", fallbackTransport: "codex_computer_use",
    fallbackAllowed: bundle.allowCodexCuFallback,
  });
  const commitInput = first.trustedInputs && first.trustedInputs.commit;
  const preCommitEvents = bundle.transcripts.first.events.filter((event) =>
    commitInput && event.sequence < commitInput.sequence).map(deepClone);
  const preCommitTranscript = Object.assign({}, bundle.transcripts.first, {
    events: preCommitEvents, eventCount: preCommitEvents.length,
    chainHead: preCommitEvents.length ? preCommitEvents[preCommitEvents.length - 1].eventHash : null,
  });
  const recomputedAdmission = Protocol.verifyPreCommitAuthority(
    preCommitTranscript, first.selector);
  const expectedPreCommitAdmission = { status: "admitted",
    selector: recomputedAdmission.selector,
    acceptedCraftTokenRef: recomputedAdmission.acceptedPreview.craftTokenRef,
    inventoryCallId: recomputedAdmission.inventoryPair.request.callId,
    delivery: recomputedAdmission.plan.delivery };
  if (!same(control.preCommitAdmission, expectedPreCommitAdmission)) {
    fail("precommit_admission_evidence_invalid", "control",
      "stored precommit admission differs from the independently recomputed 90-slot plan");
  }
  const exchanges = ControlContract.assertExactControlSet({
    root: bundle.root, runDir: bundle.runDir, ownedBaseRelative: OWNED_BASE_RELATIVE,
    requests: control.requests, acks: control.acks, requiredSteps: REQUIRED_CONTROL_STEPS,
    requestSchema: require("./common").CONTROL_REQUEST_SCHEMA,
    ackSchema: require("./common").CONTROL_ACK_SCHEMA,
    allowedTransports: TRANSPORTS, allowedResults: RESULTS, maximumTtlMs: 3600000,
  });
  control.requests.forEach((request) => {
    validateRequest(request);
    if (request.runId !== bundle.runId) {
      fail("control_request_invalid", "control", "control request crossed run identity");
    }
  });
  control.acks.forEach((ack) => {
    const matches = control.requests.filter((request) => request.requestId === ack.requestId);
    if (matches.length !== 1) {
      fail("control_step_ack_invalid", "control",
        "control acknowledgement lacks one exact request", { requestId: ack.requestId });
    }
    validateAck(ack, matches[0]);
  });
  if (!same(control.requests.map((entry) => entry.step), REQUIRED_CONTROL_STEPS)
      || !same(control.acks.map((entry) => entry.requestId),
        control.requests.map((entry) => entry.requestId))) {
    fail("control_partial_order_invalid", "control",
      "control request/ack arrays do not preserve the exact journey order");
  }
  exchanges.forEach((exchange, step) => {
    if (exchange.ack.result !== "completed"
        || exchange.ack.transport !== control.selectedTransport) {
      fail("control_exchange_incomplete", "control",
        "control step was not completed by the selected transport", { step });
    }
    verifyAckCapture(bundle.root, bundle.runDir, exchange.request, exchange.ack);
  });
  REQUIRED_CONTROL_STEPS.forEach((step, index) => {
    const exchange = exchanges.get(step);
    const intent = expectedControlIntent(step, { recipeIndex: first.selector.recipeIndex });
    if (!same(exchange.request.selectors, intent.selectors)
        || exchange.request.instructions !== intent.instructions
        || !same(exchange.request.expectedIndependentEvidence,
          intent.expectedIndependentEvidence)) {
      fail("control_request_scope_invalid", "control",
        "control request differs from the exact Crafting selector/instruction/evidence contract", { step });
    }
    if (exchange.request.requiresCaptureSha256 !== true
        || !exchange.capture || !exchange.ack.capture
        || exchange.ack.captureSha256 !== exchange.capture.sha256) {
      fail("control_capture_policy_invalid", "control",
        "every one-shot Crafting control requires one provider-owned capture", { step });
    }
    assertDecodablePng(path.join(bundle.runDir,
      exchange.capture.relativePath.replace(/\//g, path.sep)), "control");
    if (index > 0) {
      const previous = exchanges.get(REQUIRED_CONTROL_STEPS[index - 1]);
      if (!(Date.parse(previous.request.issuedAt) < Date.parse(previous.ack.completedAt)
          && Date.parse(previous.ack.completedAt) <= Date.parse(exchange.request.issuedAt)
          && Date.parse(exchange.request.issuedAt) < Date.parse(exchange.ack.completedAt))) {
        fail("control_partial_order_invalid", "control",
          "control request/ack chronology violates the exact serial journey", {
            previous: REQUIRED_CONTROL_STEPS[index - 1], step,
          });
      }
    }
  });
  const providerOperationIds = new Set();
  const providerCaptureEventIds = new Set();
  const providerCaptureDigests = new Set();
  const providerRequestDigests = new Set();
  const providerInputDigests = new Set();
  const providerDomEventRefs = new Set();
  const expectedDomEvents = new Map([
    ["select_recipe", [bundle.transcripts.first, first.trustedInputs.recipe]],
    ["capture_inventory_before", [bundle.transcripts.first, first.trustedInputs.organizer[0]]],
    ["return_from_inventory_before", [bundle.transcripts.first, first.trustedInputs.return[0]]],
    ["commit_recipe", [bundle.transcripts.first, first.trustedInputs.commit]],
    ["capture_inventory_after", [bundle.transcripts.first, first.trustedInputs.organizer[1]]],
    ["return_from_inventory_after", [bundle.transcripts.first, first.trustedInputs.return[1]]],
    ["close_first_crafting", [bundle.transcripts.first, first.trustedInputs.close]],
    ["restart_select_recipe", [bundle.transcripts.restart, restart.trustedInputs.recipe]],
    ["restart_capture_inventory", [bundle.transcripts.restart, restart.trustedInputs.organizer[0]]],
    ["restart_return_from_inventory", [bundle.transcripts.restart, restart.trustedInputs.return[0]]],
    ["restart_close_crafting", [bundle.transcripts.restart, restart.trustedInputs.close]],
  ]);
  exchanges.forEach((exchange, step) => {
    const provider = verifyProviderReceiptReference(bundle.root, bundle.runDir,
      exchange.request, exchange.ack);
    if (providerOperationIds.has(provider.receipt.providerOperationId)) {
      fail("provider_operation_id_reused", "control",
        "provider operation id must be unique across the 15 one-shot controls", { step });
    }
    if (providerCaptureEventIds.has(provider.captureEvent.value.providerEventId)
        || providerCaptureDigests.has(provider.capture.sha256)
        || providerRequestDigests.has(provider.receipt.requestSha256)) {
      fail("provider_evidence_reused", "control",
        "provider request bytes and captures must be unique across all 15 one-shot controls", {
          step,
        });
    }
    providerOperationIds.add(provider.receipt.providerOperationId);
    providerCaptureEventIds.add(provider.captureEvent.value.providerEventId);
    providerCaptureDigests.add(provider.capture.sha256);
    providerRequestDigests.add(provider.receipt.requestSha256);
    const inputDigest = Evidence.sha256Text(Evidence.canonicalJson(provider.receipt.inputEvidence));
    if (providerInputDigests.has(inputDigest)) {
      fail("provider_input_evidence_reused", "control",
        "provider input evidence must be unique across the 15 one-shot controls", { step });
    }
    providerInputDigests.add(inputDigest);
    const requestAt = Date.parse(exchange.request.issuedAt);
    const operationAt = Date.parse(provider.receipt.startedAt);
    const inputAt = Date.parse(provider.receipt.inputEvidence.observedAt);
    const captureAt = Date.parse(provider.captureEvent.value.capturedAt);
    const fileModifiedAt = Date.parse(provider.captureEvent.value.fileModifiedAt);
    const providerAt = Date.parse(provider.receipt.completedAt);
    const ackAt = Date.parse(exchange.ack.completedAt);
    if (!(requestAt < operationAt && operationAt < inputAt && inputAt < captureAt
        && captureAt < fileModifiedAt && fileModifiedAt < providerAt && providerAt < ackAt)) {
      fail("provider_input_timeline_invalid", "control",
        "provider control must preserve request < operation < input < capture < mtime < completion < ack",
        { step });
    }
    const domBinding = expectedDomEvents.get(step);
    if (domBinding) {
      const expectedInput = domInputEvidence(domBinding[0].observerId, domBinding[1]);
      const referenceKey = expectedInput.eventRef.observerId + ":" + expectedInput.eventRef.sequence
        + ":" + expectedInput.eventRef.eventSha256;
      if (!same(provider.receipt.inputEvidence, expectedInput)
          || providerDomEventRefs.has(referenceKey)) {
        fail("provider_dom_event_binding_invalid", "control",
          "provider operation is not in one strict request-to-DOM-event-to-capture bijection", {
            step, referenceKey,
          });
      }
      providerDomEventRefs.add(referenceKey);
    } else if (provider.receipt.inputEvidence.kind !== "native_input"
        || provider.receipt.inputEvidence.eventRef !== null
        || provider.receipt.inputEvidence.tagName !== "NATIVE") {
      fail("provider_native_input_binding_invalid", "control",
        "native provider operation lacks one exact provider-owned target contract", { step });
    }
    exchange.providerReceipt = provider.receipt;
    exchange.providerCaptureEvent = provider.captureEvent.value;
  });
  if (providerDomEventRefs.size !== expectedDomEvents.size) {
    fail("provider_dom_event_binding_invalid", "control",
      "provider DOM event binding set has gaps, extras, or reuse");
  }
  const auth = control.authorization;
  if (!Evidence.isPlainObject(auth) || auth.schema !== AUTHORIZATION_SCHEMA
      || auth.allowedStep !== "commit_recipe" || auth.scope.slot !== bundle.targetSlot
      || auth.scope.category !== first.selector.category
      || auth.scope.recipeIndex !== first.selector.recipeIndex
      || auth.scope.craftCount !== first.selector.craftCount
      || auth.scope.operation !== "craft") {
    fail("authorization_scope_invalid", "control",
      "one-shot manual commit authorization scope is not exact");
  }
  const authorization = ControlContract.verifyOneShotAuthorization({
    decision: auth, decisionSha256: control.authorizationSha256,
    decisionSchema: AUTHORIZATION_SCHEMA, trustedSources: TRUSTED_AUTHORIZATION_SOURCES,
    requests: control.requests, acks: control.acks, expectedStep: "commit_recipe",
  });
  return { capability, exchanges, authorization };
}

function verifyStablePhase(phase, expectedSet, label) {
  requireObject(phase, "clone_phase_invalid", label, "stable artifact phase is missing");
  verifyDigestObject(phase, "evidenceSha256", "clone_phase_invalid", label);
  if (phase.schema !== "workbench-live-e2e.stable-slot-artifact-set.v1"
      || phase.apiVersion !== CloneGuard.API_VERSION || !Number.isInteger(phase.samples)
      || phase.samples < 2 || !Number.isInteger(phase.stableMs) || phase.stableMs < 1
      || !same(phase.set, expectedSet)) {
    fail("clone_phase_invalid", label, "stable artifact phase is malformed or detached");
  }
  CloneGuard.verifyArtifactSet(phase.set);
}

function verifyPreparation(preparation, bundle, settings) {
  verifyDigestObject(preparation, "preparationSha256",
    "clone_preparation_invalid", "persistence");
  if (preparation.schema !== CloneGuard.PREPARATION_SCHEMA
      || preparation.apiVersion !== CloneGuard.API_VERSION
      || path.resolve(preparation.root || "") !== path.resolve(bundle.root)
      || path.resolve(preparation.runDir || "") !== path.resolve(bundle.runDir)
      || preparation.seedSlot !== bundle.seedSlot || preparation.targetSlot !== bundle.targetSlot
      || !Array.isArray(preparation.backups)) {
    fail("clone_preparation_invalid", "persistence",
      "clone preparation envelope/scope is malformed");
  }
  [preparation.seedBegin, preparation.seedAfterPrepare,
    preparation.targetBefore, preparation.targetPrepared].forEach(CloneGuard.verifyArtifactSet);
  CloneGuard.assertArtifactSetInvariant(preparation.seedBegin, preparation.seedAfterPrepare);
  if (settings.skipFileClosure !== true) {
    CloneGuard.verifyBackupManifest({ runDir: bundle.runDir,
      backups: preparation.backups, set: preparation.targetBefore });
  }
  return preparation;
}

function verifyRelease(release, persistence) {
  verifyDigestObject(release, "releaseSha256", "clone_release_invalid", "persistence");
  if (release.schema !== CloneGuard.RELEASE_SCHEMA || release.apiVersion !== CloneGuard.API_VERSION
      || release.backupsVerified !== true || release.lockRelease.lockFileAbsent !== true
      || release.lockRelease.terminalPrivateRelease !== true
      || release.recoveryClear.recoveryFileAbsent !== true) {
    fail("clone_release_invalid", "persistence",
      "clone lock/recovery release is incomplete");
  }
  CloneGuard.verifyArtifactSet(release.seedEnd);
  CloneGuard.verifyArtifactSet(release.targetEnd);
  CloneGuard.assertArtifactSetInvariant(persistence.preparation.seedBegin, release.seedEnd,
    "seed_artifact_set_changed");
  CloneGuard.assertArtifactSetInvariant(persistence.afterRestart, release.targetEnd,
    "target_release_set_mismatch");
  return release;
}

function verifyDiskEvidence(value, slot, root, phase) {
  const expectedPath = path.join(root, "saves", slot + ".json");
  if (!Evidence.isPlainObject(value)
      || value.schema !== "workbench-live-e2e.disk-save-evidence.v1"
      || value.slot !== slot || typeof value.path !== "string" || !path.isAbsolute(value.path)
      || !samePath(value.path, expectedPath)
      || !/^[a-f0-9]{64}$/.test(String(value.sha256 || ""))
      || !Number.isInteger(value.bytes) || value.bytes < 1
      || !Number.isInteger(value.textCharacters) || value.textCharacters < 1
      || !Number.isFinite(Date.parse(value.capturedAt))) {
    fail("disk_evidence_invalid", phase, "disk save evidence is malformed");
  }
  return value;
}

function exactJsonArtifact(set, root, slot, phase) {
  CloneGuard.verifyArtifactSet(set);
  const expectedLocator = "root:saves/" + slot + ".json";
  const matches = set.artifacts.filter((entry) => entry.kind === "json"
    && String(entry.locator || "").replace(/\\/g, "/") === expectedLocator);
  if (matches.length !== 1 || matches[0].regularFile !== true
      || matches[0].exactRealPath !== true
      || !samePath(path.join(root, "saves", slot + ".json"),
        path.resolve(root, matches[0].locator.slice("root:".length)))) {
    fail("persistence_json_artifact_invalid", phase,
      "artifact set lacks one exact owned JSON save", { expectedLocator, count: matches.length });
  }
  return matches[0];
}

function requireDiskArtifactIdentity(disk, artifact, phase) {
  if (disk.sha256 !== artifact.sha256 || disk.bytes !== artifact.bytes) {
    fail("persistence_disk_artifact_mismatch", phase,
      "disk save evidence differs from the clone artifact JSON bytes");
  }
}

function verifyPersistence(bundle, settings) {
  const value = requireObject(bundle.persistence, "persistence_invalid", "persistence",
    "clone/save persistence evidence is missing");
  const preparation = verifyPreparation(value.preparation, bundle, settings);
  [value.afterCommit, value.afterRestart, value.seedEnd].forEach(CloneGuard.verifyArtifactSet);
  verifyStablePhase(value.stability.targetPrepared,
    preparation.targetPrepared, "persistence.target_prepared");
  verifyStablePhase(value.stability.afterCommit, value.afterCommit, "persistence.after_commit");
  verifyStablePhase(value.stability.afterRestart, value.afterRestart, "persistence.after_restart");
  CloneGuard.assertArtifactSetInvariant(preparation.seedBegin, value.seedEnd,
    "seed_artifact_set_changed");
  CloneGuard.assertArtifactSetInvariant(value.afterCommit, value.afterRestart,
    "restart_artifact_set_changed");
  if (preparation.targetPrepared.setSha256 === value.afterCommit.setSha256
      || value.afterCommit.slot !== bundle.targetSlot
      || value.afterCommit.artifacts.filter((entry) => entry.kind === "json").length !== 1) {
    fail("persistence_artifact_scope_invalid", "persistence",
      "commit did not change the dedicated clone JSON/SOL closure");
  }
  const committedDisk = verifyDiskEvidence(value.diskAfterCommit,
    bundle.targetSlot, bundle.root, "persistence.commit");
  const restartDisk = verifyDiskEvidence(value.diskAfterRestart,
    bundle.targetSlot, bundle.root, "persistence.restart");
  const committedJson = exactJsonArtifact(value.afterCommit,
    bundle.root, bundle.targetSlot, "persistence.commit");
  const restartJson = exactJsonArtifact(value.afterRestart,
    bundle.root, bundle.targetSlot, "persistence.restart");
  requireDiskArtifactIdentity(committedDisk, committedJson, "persistence.commit");
  requireDiskArtifactIdentity(restartDisk, restartJson, "persistence.restart");
  if (committedDisk.sha256 !== restartDisk.sha256 || committedDisk.bytes !== restartDisk.bytes
      || committedDisk.textCharacters !== restartDisk.textCharacters) {
    fail("restart_disk_readback_mismatch", "persistence",
      "restart readback changed committed disk bytes");
  }
  const archive = verifyDigestObject(value.archiveEvidence, "evidenceSha256",
    "archive_evidence_invalid", "persistence");
  if (archive.schema !== LauncherObservation.ARCHIVE_SCHEMA
      || archive.apiVersion !== LauncherObservation.API_VERSION
      || !same(archive.requiredOrder, ["sv1", "sv2", "archive"])
      || archive.disk.slot !== bundle.targetSlot
      || !samePath(archive.disk.path, committedDisk.path)
      || archive.disk.sha256 !== committedDisk.sha256
      || archive.disk.bytes !== committedDisk.bytes
      || archive.disk.textCharacters !== committedDisk.textCharacters
      || !archive.archive || !samePath(archive.archive.path, committedDisk.path)
      || archive.archive.characters !== committedDisk.textCharacters) {
    fail("archive_evidence_invalid", "persistence",
      "SAFEEXIT sv1/sv2/archive closure is detached from committed disk bytes");
  }
  const release = verifyRelease(value.release, value);
  const releaseJson = exactJsonArtifact(release.targetEnd,
    bundle.root, bundle.targetSlot, "persistence.release");
  requireDiskArtifactIdentity(restartDisk, releaseJson, "persistence.release");
  return { preparation, committedDisk, restartDisk, committedJson, restartJson,
    releaseJson, archive, release };
}

function verifyResidue(bundle) {
  LauncherObservation.assertResidueClean(bundle.residue.afterSafeExit);
  LauncherObservation.assertResidueClean(bundle.residue.final);
  if (bundle.residue.afterSafeExit.expectedPid !== bundle.runtime.first.identity.pid
      || bundle.residue.final.expectedPid !== bundle.runtime.restart.identity.pid) {
    fail("residue_pid_mismatch", "residue",
      "process/port/rendezvous/credential residue proof crossed runtime PID");
  }
  return bundle.residue;
}

function verifySourceClosure(bundle, runtime, options) {
  if (!SourceContract.validateSourceClosure(bundle.sourceClosure)) {
    fail("source_closure_invalid", "source_identity",
      "production Web/Host/AS2/data/SWF phase closure is malformed or drifting");
  }
  if (!(options && options.testOnlyAllowInjectedEvidence === true
      && options.skipFileClosure === true)) {
    SourceContract.assertCurrentSourceClosure(bundle.root, bundle.sourceClosure);
  } else if (!samePath(bundle.sourceClosure.root, bundle.root)) {
    fail("source_closure_root_invalid", "source_identity",
      "test source closure is detached from the bundle root");
  }
  const binding = verifyDigestObject(bundle.sourceBinding, "bindingSha256",
    "source_binding_invalid", "source_identity");
  const baseline = bundle.sourceClosure.records[0].fingerprint;
  const expectedIdentity = SourceContract.publicCandidateIdentity(runtime.first.identity);
  let candidateProducer = bundle.candidateProducer;
  if (!(options && options.testOnlyAllowInjectedEvidence === true
      && options.skipFileClosure === true)) {
    candidateProducer = SourceContract.verifyCandidateProducerBinding(bundle.candidateRoot,
      runtime.first.identity, baseline, bundle.candidateProducer);
  } else {
    const producerKeys = ["artifactSourceHash", "buildIdentityHash", "builderLabel",
      "candidateRoot", "coreLibrary", "createdAtUtc", "evidenceSha256", "manifest",
      "metadata", "payloadClosureHash", "payloadFileCount", "processImage",
      "producerInputsSha256", "producerRecipeHash", "schema", "toolchainLockHash"];
    const fileKeys = ["bytes", "locator", "sha256"];
    const processRelative = path.relative(path.resolve(bundle.candidateRoot),
      path.resolve(runtime.first.identity.processPath)).replace(/\\/g, "/");
    const unsignedCandidate = Object.assign({}, Evidence.isPlainObject(candidateProducer)
      ? candidateProducer : {});
    delete unsignedCandidate.evidenceSha256;
    if (!Evidence.isPlainObject(candidateProducer)
        || candidateProducer.schema !== SourceContract.CANDIDATE_PRODUCER_SCHEMA
        || !same(Object.keys(candidateProducer).sort(), producerKeys.slice().sort())
        || !samePath(candidateProducer.candidateRoot, bundle.candidateRoot)
        || !Number.isFinite(Date.parse(candidateProducer.createdAtUtc))
        || typeof candidateProducer.builderLabel !== "string"
        || !candidateProducer.builderLabel.trim()
        || !Number.isInteger(candidateProducer.payloadFileCount)
        || candidateProducer.payloadFileCount < 2
        || !Evidence.isPlainObject(candidateProducer.metadata)
        || !Evidence.isPlainObject(candidateProducer.manifest)
        || !Evidence.isPlainObject(candidateProducer.processImage)
        || !Evidence.isPlainObject(candidateProducer.coreLibrary)
        || [candidateProducer.metadata, candidateProducer.manifest,
          candidateProducer.processImage, candidateProducer.coreLibrary]
          .some((entry) => !same(Object.keys(entry).sort(), fileKeys.slice().sort())
            || !/^[A-F0-9]{64}$/.test(String(entry.sha256 || ""))
            || !Number.isInteger(entry.bytes) || entry.bytes < 1)
        || candidateProducer.metadata.locator
          !== "candidate:runtime-build-metadata.v2.json"
        || candidateProducer.manifest.locator
          !== "candidate:runtime/cf7-runtime-manifest.tsv"
        || String(candidateProducer.processImage.locator || "").toLowerCase()
          !== ("candidate:" + processRelative).toLowerCase()
        || String(candidateProducer.coreLibrary.locator || "").toLowerCase()
          !== "candidate:runtime/crazyflasher7mercenaryempire.core.dll"
        || candidateProducer.coreLibrary.sha256
          !== String(runtime.first.identity.coreSha256 || "").toUpperCase()
        || candidateProducer.producerInputsSha256 !== baseline.producerInputs.inputsSha256
        || candidateProducer.artifactSourceHash
          !== baseline.producerInputs.domains.artifactSource.hash
        || candidateProducer.producerRecipeHash
          !== baseline.producerInputs.domains.producerRecipe.hash
        || candidateProducer.toolchainLockHash
          !== baseline.producerInputs.domains.toolchainLock.hash
        || candidateProducer.buildIdentityHash !== baseline.producerInputs.buildIdentityHash
        || candidateProducer.buildIdentityHash !== runtime.first.identity.buildIdentity
        || candidateProducer.payloadClosureHash !== runtime.first.identity.payloadClosure
        || !/^[a-f0-9]{64}$/.test(String(candidateProducer.evidenceSha256 || ""))
        || candidateProducer.evidenceSha256 !== Evidence.sha256Text(
          Evidence.canonicalJson(unsignedCandidate))) {
      fail("candidate_producer_evidence_invalid", "source_identity",
        "test candidate producer evidence is malformed, detached, or not digest-bound");
    }
  }
  if (binding.schema !== SourceContract.SOURCE_BINDING_SCHEMA
      || binding.runId !== bundle.runId || !samePath(binding.sourceRoot, bundle.root)
      || !samePath(binding.candidateRoot, bundle.candidateRoot)
      || binding.sourceFingerprintSha256 !== baseline.fingerprintSha256
      || binding.producerInputsSha256 !== baseline.producerInputs.inputsSha256
      || binding.candidateProducerSha256 !== candidateProducer.evidenceSha256
      || binding.candidateIdentitySha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(expectedIdentity))
      || !same(SourceContract.publicCandidateIdentity(runtime.restart.identity), expectedIdentity)) {
    fail("source_binding_invalid", "source_identity",
      "production source closure is detached from current root/candidate/run");
  }
  const expectedWeb = SourceContract.webFiles(bundle.sourceClosure);
  const sourceReadRoot = options && options.testOnlyAllowInjectedEvidence === true
      && options.skipFileClosure === true
    ? path.resolve(__dirname, "..", "..", "..") : bundle.root;
  function verifyLoaded(lifecycleRuntime, lifecycle) {
    const loaded = verifyDigestObject(lifecycleRuntime.loadedProduction,
      "evidenceSha256", "loaded_production_invalid", "source_identity");
    if (loaded.schema !== SourceContract.LOADED_SCHEMA || loaded.lifecycle !== lifecycle
        || loaded.runtimePid !== lifecycleRuntime.identity.pid || loaded.runId !== bundle.runId
        || !Number.isFinite(Date.parse(loaded.capturedAt))
        || loaded.sourceFingerprintSha256 !== baseline.fingerprintSha256
        || loaded.sourceBindingSha256 !== binding.bindingSha256) {
      fail("loaded_production_binding_invalid", "source_identity",
        lifecycle + " actual loaded bytes are detached from source/candidate/run");
    }
    const loadedKeys = ["capturePhase", "capturedAt", "evidenceSha256",
      "executionContextOccurrences", "fontEnvironment", "iconProjection",
      "inlineScripts", "lifecycle", "mainFrameId", "page", "relevantScriptUrls",
      "relevantStyleUrls", "resourceOccurrences", "runId", "runtimePid", "schema",
      "scriptOccurrences", "scripts", "sourceBindingSha256", "sourceFingerprintSha256",
      "styleOccurrences", "styles", "toolScriptPlan"];
    if (!same(Object.keys(loaded).sort(), loadedKeys.slice().sort())
        || !Array.isArray(loaded.relevantScriptUrls)
        || !Array.isArray(loaded.relevantStyleUrls)
        || !Array.isArray(loaded.scriptOccurrences)
        || !Array.isArray(loaded.executionContextOccurrences)
        || !Array.isArray(loaded.toolScriptPlan)
        || !Array.isArray(loaded.inlineScripts)
        || !Array.isArray(loaded.resourceOccurrences)
        || !Array.isArray(loaded.styleOccurrences)
        || !Array.isArray(loaded.scripts) || !Array.isArray(loaded.styles)
        || loaded.capturePhase !== "post_observer_detach"
        || !Evidence.isPlainObject(loaded.fontEnvironment)
        || !Evidence.isPlainObject(loaded.iconProjection)) {
      fail("loaded_production_multiset_invalid", "source_identity",
        lifecycle + " raw loaded occurrence streams are absent or open-ended");
    }
    const expectedScriptRecords = SourceContract.scriptFiles(bundle.sourceClosure);
    const expectedStyleRecords = SourceContract.styleFiles(bundle.sourceClosure);
    const expectedStaticResources = SourceContract.expectedStaticResourceSet(bundle.sourceClosure);
    const expectedConditionalResources = SourceContract.cssConditionalResourceSet(bundle.sourceClosure);
    const iconNames = authoritativeIconNames(bundle.transcripts[lifecycle].events, lifecycle);
    const injected = options && options.testOnlyAllowInjectedEvidence === true
      && options.skipFileClosure === true;
    const cacheKey = baseline.fingerprintSha256 + "\u0000" + sourceReadRoot;
    let cached = TEST_SOURCE_EVIDENCE_CACHE.get(cacheKey);
    if (injected && !cached) {
      cached = { fontEnvironment: SourceContract.captureFontEnvironment(sourceReadRoot,
        bundle.sourceClosure, process.env), icons: new Map() };
      TEST_SOURCE_EVIDENCE_CACHE.set(cacheKey, cached);
    }
    const verifiedFontEnvironment = injected ? cached.fontEnvironment
      : SourceContract.verifyFontEnvironment(sourceReadRoot,
        bundle.sourceClosure, loaded.fontEnvironment, process.env);
    if (injected && !same(verifiedFontEnvironment, loaded.fontEnvironment)) {
      fail("font_environment_mismatch", "source_identity",
        lifecycle + " loaded font environment differs from current manifest bytes");
    }
    const iconKey = Evidence.canonicalJson(iconNames);
    let expectedIconProjection = injected && cached.icons.get(iconKey);
    if (!expectedIconProjection) {
      expectedIconProjection = SourceContract.iconResourceSetForNames(sourceReadRoot,
        bundle.sourceClosure, iconNames);
      if (injected) cached.icons.set(iconKey, expectedIconProjection);
    }
    if (!same(loaded.iconProjection, expectedIconProjection)) {
      fail("dynamic_icon_projection_invalid", "source_identity",
        lifecycle + " icon projection is detached from authoritative response names and manifest bytes");
    }
    const expectedScripts = expectedScriptRecords.map((entry) =>
      "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length));
    const expectedStyles = expectedStyleRecords.map((entry) =>
      "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length));
    if (!same(loaded.relevantScriptUrls, expectedScripts)
        || !same(loaded.relevantStyleUrls, expectedStyles)
        || !same(loaded.scripts.map((entry) => entry && entry.url), expectedScripts)
        || !same(loaded.styles.map((entry) => entry && entry.url), expectedStyles)) {
      fail("loaded_production_url_multiset_invalid", "source_identity",
        lifecycle + " loaded production URL projection has gaps, duplicates, extras, or reordering");
    }
    const pageScriptUrl = "https://overlay.local/overlay.html";
    const toolPrefix = "cf7-evidence://crafting/";
    const executableOccurrences = loaded.scriptOccurrences.filter((entry) =>
      entry && expectedScripts.includes(entry.url));
    const pageOccurrences = loaded.scriptOccurrences.filter((entry) =>
      entry && entry.url === pageScriptUrl);
    const toolOccurrences = loaded.scriptOccurrences.filter((entry) => entry
      && String(entry.url || "").startsWith(toolPrefix));
    const foreignScripts = loaded.scriptOccurrences.filter((entry) =>
      !entry || (!expectedScripts.includes(entry.url) && entry.url !== pageScriptUrl
        && !String(entry.url || "").startsWith(toolPrefix)));
    const scriptOccurrenceKeys = ["contextOrigin", "endColumn", "endLine",
      "executionContextId", "frameId", "occurrence", "origin",
      "rawExecutionContextAuxData", "rawParams",
      "scriptId", "sourceBytes", "sourceMapUrl", "sourceMethod", "sourceSha256",
      "startColumn", "startLine", "url"];
    const contextOccurrenceKeys = ["executionContextId", "frameId", "name", "occurrence",
      "origin", "rawAuxData", "rawContext", "uniqueId"];
    const contextAuxKeys = ["frameId", "isDefault", "type"];
    const resourceOccurrenceKeys = ["frameId", "frameOccurrence", "frameOrigin", "frameUrl",
      "mimeType", "occurrence", "origin", "resource", "resourceOccurrence",
      "resourceType", "sourceBytes", "sourceError", "sourceMethod", "sourceSha256", "url"];
    const toolPlanKeys = ["bytes", "label", "sequence", "sha256", "url"];
    const contexts = new Map();
    if (loaded.executionContextOccurrences.some((entry, index) => {
      if (!Evidence.isPlainObject(entry)
          || !same(Object.keys(entry).sort(), contextOccurrenceKeys)
          || entry.occurrence !== index + 1
          || !Number.isInteger(entry.executionContextId) || entry.executionContextId < 1
          || contexts.has(entry.executionContextId)
          || entry.origin !== "https://overlay.local"
          || typeof entry.name !== "string" || typeof entry.uniqueId !== "string"
          || !Evidence.isPlainObject(entry.rawAuxData)
          || !same(Object.keys(entry.rawAuxData).sort(), contextAuxKeys)
          || String(entry.rawAuxData.frameId || "") !== loaded.mainFrameId
          || entry.rawAuxData.isDefault !== true || entry.rawAuxData.type !== "default"
          || entry.frameId !== loaded.mainFrameId
          || !Evidence.isPlainObject(entry.rawContext)
          || Number(entry.rawContext.id) !== entry.executionContextId
          || String(entry.rawContext.origin || "") !== entry.origin
          || String(entry.rawContext.name || "") !== entry.name
          || String(entry.rawContext.uniqueId || "") !== entry.uniqueId
          || !same(entry.rawContext.auxData || {}, entry.rawAuxData)) return true;
      contexts.set(entry.executionContextId, entry);
      return false;
    }) || contexts.size < 1) {
      fail("loaded_production_context_occurrence_invalid", "source_identity",
        lifecycle + " raw execution-context occurrence stream is malformed or foreign");
    }
    const toolByUrl = new Map();
    const toolLabelCounts = new Map();
    loaded.toolScriptPlan.forEach((entry, index) => {
      const observerId = bundle.transcripts[lifecycle].observerId;
      const expectedToolUrl = toolPrefix + encodeURIComponent(observerId) + "/"
        + String(index + 1).padStart(4, "0") + "-"
        + String(entry && entry.label || "") + ".js";
      if (!Evidence.isPlainObject(entry) || !same(Object.keys(entry).sort(), toolPlanKeys)
          || entry.sequence !== index + 1
          || !["identity", "install_new_document", "install_current_document", "health",
            "panel_state", "record_panel_state", "detach"].includes(entry.label)
          || entry.url !== expectedToolUrl
          || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
          || !Number.isInteger(entry.bytes) || entry.bytes < 1 || toolByUrl.has(entry.url)) {
        fail("loaded_production_tool_script_invalid", "source_identity",
          lifecycle + " tool-owned script plan is malformed, duplicated, or unordered");
      }
      toolByUrl.set(entry.url, entry);
      toolLabelCounts.set(entry.label, (toolLabelCounts.get(entry.label) || 0) + 1);
    });
    if (toolLabelCounts.get("identity") !== 1
        || toolLabelCounts.get("install_new_document") !== 1
        || toolLabelCounts.get("install_current_document") !== 1
        || toolLabelCounts.get("detach") !== 1
        || !loaded.toolScriptPlan.length
        || loaded.toolScriptPlan[loaded.toolScriptPlan.length - 1].label !== "detach") {
      fail("loaded_production_tool_script_invalid", "source_identity",
        lifecycle + " tool-owned plan lacks its exact bootstrap or terminal detach source");
    }
    const observedToolUrls = new Set();
    toolOccurrences.forEach((entry) => {
      const plan = toolByUrl.get(entry.url);
      if (!plan || observedToolUrls.has(entry.url)
          || entry.sourceSha256 !== plan.sha256 || entry.sourceBytes !== plan.bytes) {
        fail("loaded_production_tool_script_invalid", "source_identity",
          lifecycle + " tool-owned script occurrence is absent, reused, or byte-detached");
      }
      observedToolUrls.add(entry.url);
    });
    if (loaded.toolScriptPlan.some((entry) => entry.label !== "install_new_document"
      && !observedToolUrls.has(entry.url))) {
      fail("loaded_production_tool_script_invalid", "source_identity",
        lifecycle + " an executed tool source is missing from the raw script stream");
    }
    if (!same(executableOccurrences.map((entry) => entry.url), expectedScripts)
        || foreignScripts.length !== 0 || pageOccurrences.length !== 1
        || !String(loaded.mainFrameId || "")
        || new Set(loaded.scriptOccurrences.map((entry) => entry && entry.scriptId)).size
          !== loaded.scriptOccurrences.length
        || loaded.scriptOccurrences.some((entry, index) => !Evidence.isPlainObject(entry)
          || !same(Object.keys(entry).sort(), scriptOccurrenceKeys.slice().sort())
          || entry.occurrence !== index + 1 || !entry.url
          || expectedScripts.concat([pageScriptUrl]).includes(entry.url)
            && entry.origin !== "https://overlay.local"
          || entry.url.startsWith(toolPrefix) && !["null", "opaque"].includes(entry.origin)
          || !String(entry.scriptId || "")
          || !Number.isInteger(entry.executionContextId) || entry.executionContextId < 1
          || !contexts.has(entry.executionContextId)
          || entry.frameId !== loaded.mainFrameId
          || entry.contextOrigin !== contexts.get(entry.executionContextId).origin
          || entry.contextOrigin !== "https://overlay.local"
          || !Evidence.isPlainObject(entry.rawExecutionContextAuxData)
          || !same(Object.keys(entry.rawExecutionContextAuxData).sort(), contextAuxKeys)
          || !same(entry.rawExecutionContextAuxData,
            contexts.get(entry.executionContextId).rawAuxData)
          || String(entry.rawExecutionContextAuxData.frameId || "") !== entry.frameId
          || entry.rawExecutionContextAuxData.isDefault !== true
          || entry.rawExecutionContextAuxData.type !== "default"
          || !Evidence.isPlainObject(entry.rawParams)
          || String(entry.rawParams.scriptId || "") !== entry.scriptId
          || String(entry.rawParams.url || "") !== entry.url
          || Number(entry.rawParams.executionContextId) !== entry.executionContextId
          || ![entry.startLine, entry.startColumn, entry.endLine, entry.endColumn]
            .every((value) => Number.isInteger(value) && value >= 0)
          || Number(entry.rawParams.startLine) !== entry.startLine
          || Number(entry.rawParams.startColumn) !== entry.startColumn
          || Number(entry.rawParams.endLine) !== entry.endLine
          || Number(entry.rawParams.endColumn) !== entry.endColumn
          || String(entry.rawParams.sourceMapURL || "") !== entry.sourceMapUrl
          || !own(entry.rawParams, "executionContextAuxData")
          || !same(entry.rawParams.executionContextAuxData,
            entry.rawExecutionContextAuxData)
          || entry.sourceMethod !== "Debugger.getScriptSource"
          || !/^[a-f0-9]{64}$/.test(String(entry.sourceSha256 || ""))
          || !Number.isInteger(entry.sourceBytes) || entry.sourceBytes < 1)) {
      fail("loaded_production_url_multiset_invalid", "source_identity",
        lifecycle + " raw CDP script occurrence/order/origin/context/source stream is not exact");
    }
    const referencedContextIds = [];
    loaded.scriptOccurrences.forEach((entry) => {
      if (!referencedContextIds.includes(entry.executionContextId)) {
        referencedContextIds.push(entry.executionContextId);
      }
    });
    if (!same(loaded.executionContextOccurrences.map((entry) => entry.executionContextId),
      referencedContextIds)) {
      fail("loaded_production_context_projection_invalid", "source_identity",
        lifecycle + " context stream is not the exact first-reference projection of scripts");
    }
    const detachPlan = loaded.toolScriptPlan[loaded.toolScriptPlan.length - 1];
    const terminalScript = loaded.scriptOccurrences[loaded.scriptOccurrences.length - 1];
    if (!terminalScript || terminalScript.url !== detachPlan.url) {
      fail("loaded_production_not_terminal", "source_identity",
        lifecycle + " loadedProduction was captured before the final observer detach source");
    }
    const fontResources = verifiedFontEnvironment.installed.map((entry) => {
      const extension = path.posix.extname(new URL(entry.url).pathname).toLowerCase();
      return { url: entry.url, resourceType: "Font", origin: "https://cfn-fonts.local",
        mimeType: extension === ".woff2" ? "font/woff2"
          : extension === ".woff" ? "font/woff" : "font/ttf",
        sha256: entry.sha256, bytes: entry.bytes };
    });
    const layers = [
      ["fixed", expectedStaticResources],
      ["conditional", expectedConditionalResources],
      ["font", fontResources],
      ["icon", expectedIconProjection.resources],
    ];
    const expectedByKey = new Map();
    layers.forEach(([layer, records]) => records.forEach((record) => {
      const key = record.url + "\u0000" + record.resourceType;
      if (expectedByKey.has(key)) {
        fail("loaded_production_resource_collision", "source_identity",
          lifecycle + " registered Page resource layers overlap", { key });
      }
      expectedByKey.set(key, { layer, record });
    }));
    const actualByLayer = { fixed: [], conditional: [], font: [], icon: [] };
    const actualFixedKeys = [];
    const rawKeys = [];
    loaded.resourceOccurrences.forEach((entry, index) => {
      const key = entry && entry.url + "\u0000" + entry.resourceType;
      const expected = expectedByKey.get(key);
      const scriptMimeAllowed = expected && expected.record.resourceType === "Script"
        && ["text/javascript", "application/javascript"].includes(entry.mimeType);
      if (!Evidence.isPlainObject(entry)
          || !same(Object.keys(entry).sort(), resourceOccurrenceKeys.slice().sort())
          || entry.occurrence !== index + 1 || entry.frameOccurrence !== 1
          || entry.resourceOccurrence !== index + 1
          || entry.frameId !== loaded.mainFrameId
          || entry.frameUrl !== "https://overlay.local/overlay.html"
          || entry.frameOrigin !== "https://overlay.local"
          || !expected || entry.origin !== expected.record.origin
          || (!scriptMimeAllowed && entry.mimeType !== expected.record.mimeType)
          || !Evidence.isPlainObject(entry.resource)
          || String(entry.resource.url || "") !== entry.url
          || String(entry.resource.type || "") !== entry.resourceType
          || String(entry.resource.mimeType || "") !== entry.mimeType) {
        fail("loaded_production_resource_occurrence_invalid", "source_identity",
          lifecycle + " Page tree contains a malformed, foreign, or unregistered occurrence", {
            occurrence: index + 1, url: entry && entry.url,
          });
      }
      if (expected.layer === "fixed") {
        if (entry.sourceMethod !== null || entry.sourceSha256 !== null
            || entry.sourceBytes !== null || entry.sourceError !== null) {
          fail("loaded_production_resource_source_invalid", "source_identity",
            lifecycle + " fixed Page resource incorrectly claims a conditional byte read");
        }
      } else if (entry.sourceMethod !== "Page.getResourceContent"
          || entry.sourceSha256 !== expected.record.sha256
          || entry.sourceBytes !== expected.record.bytes || entry.sourceError !== null) {
        fail("loaded_production_resource_source_invalid", "source_identity",
          lifecycle + " conditional/font/icon bytes are absent or detached from their source");
      }
      actualByLayer[expected.layer].push(entry.url);
      if (expected.layer === "fixed") actualFixedKeys.push(key);
      rawKeys.push(key);
    });
    const expectedFixedKeys = expectedStaticResources.map((entry) =>
      entry.url + "\u0000" + entry.resourceType);
    const expectedConditionalUrls = expectedConditionalResources.map((entry) => entry.url);
    const expectedFontUrls = fontResources.map((entry) => entry.url);
    const expectedIconUrls = expectedIconProjection.resources.map((entry) => entry.url);
    if (!same(actualFixedKeys, expectedFixedKeys)
        || new Set(actualByLayer.conditional).size !== actualByLayer.conditional.length
        || !orderedSubset(actualByLayer.conditional, expectedConditionalUrls)
        || new Set(actualByLayer.font).size !== actualByLayer.font.length
        || !orderedSubset(actualByLayer.font, expectedFontUrls)
        || !same(actualByLayer.icon, expectedIconUrls)) {
      fail("loaded_production_resource_projection_invalid", "source_identity",
        lifecycle + " Page resource layer has omissions, extras, duplicates, or reordering");
    }
    const allowedRawOrder = expectedFixedKeys
      .concat(actualByLayer.conditional.map((url) => url + "\u0000Image"))
      .concat(actualByLayer.font.map((url) => url + "\u0000Font"))
      .concat(expectedIconProjection.resources.map((entry) =>
        entry.url + "\u0000" + entry.resourceType));
    if (!same(rawKeys, allowedRawOrder)) {
      fail("loaded_production_resource_order_invalid", "source_identity",
        lifecycle + " Page resource occurrences crossed the canonical layer order");
    }
    const derivedStyles = loaded.resourceOccurrences.filter((entry) =>
      entry.resourceType === "Stylesheet");
    if (!same(loaded.styleOccurrences, derivedStyles)
        || !same(loaded.styleOccurrences.map((entry) => entry.url), expectedStyles)
        || !same(loaded.styleOccurrences.map((entry) => entry.url), loaded.relevantStyleUrls)) {
      fail("loaded_production_style_occurrence_invalid", "source_identity",
        lifecycle + " external stylesheet occurrence stream is not exact");
    }
    const observed = [loaded.page]
      .concat(Array.isArray(loaded.scripts) ? loaded.scripts : [])
      .concat(Array.isArray(loaded.styles) ? loaded.styles : []);
    if (observed.length !== expectedWeb.length
        || new Set(observed.map((entry) => entry && entry.locator)).size !== observed.length) {
      fail("loaded_production_multiset_invalid", "source_identity",
        lifecycle + " loaded Web byte multiset has gaps, duplicates, or extras");
    }
    if (!same(observed.map((entry) => entry && entry.locator),
      expectedWeb.map((entry) => entry.locator))) {
      fail("loaded_production_order_invalid", "source_identity",
        lifecycle + " loaded byte projection differs from raw occurrence order");
    }
    if (!same(loaded.scripts.map((entry) => entry && entry.locator),
      expectedScriptRecords.map((entry) => entry.locator))
        || !same(loaded.styles.map((entry) => entry && entry.locator),
          expectedStyleRecords.map((entry) => entry.locator))) {
      fail("loaded_production_type_partition_invalid", "source_identity",
        lifecycle + " loaded resources crossed the script/stylesheet partition");
    }
    expectedWeb.forEach((expected) => {
      const matches = observed.filter((entry) => entry && entry.locator === expected.locator);
      const expectedMethod = expected.role === "page" || !expected.locator.endsWith(".js")
        ? "Page.getResourceContent" : "Debugger.getScriptSource";
      const actual = matches[0];
      const resourceKeys = expected.locator.endsWith(".css")
        ? ["bytes", "frameId", "locator", "resourceOccurrence", "role", "sha256",
          "sourceMethod", "url"]
        : expected.role === "page"
          ? ["bytes", "locator", "role", "sha256", "sourceMethod", "url"]
          : ["bytes", "contextOrigin", "executionContextId", "frameId", "locator",
            "occurrence", "role", "scriptId", "sha256", "sourceMethod", "url"];
      if (matches.length !== 1 || !Evidence.isPlainObject(actual)
          || !same(Object.keys(actual).sort(), resourceKeys)
          || actual.role !== expected.role || actual.sha256 !== expected.sha256
          || actual.bytes !== expected.bytes || actual.sourceMethod !== expectedMethod
          || actual.url !== "https://overlay.local/"
            + expected.locator.slice("root:launcher/web/".length)) {
        fail("loaded_production_resource_invalid", "source_identity",
          lifecycle + " actual loaded Web byte differs from current source", {
            locator: expected.locator, count: matches.length,
          });
      }
    });
    const inlineKeys = ["bytes", "contextOrigin", "executionContextId", "frameId",
      "occurrence", "scriptId", "sha256", "sourceMethod"];
    if (loaded.inlineScripts.length !== 1
        || loaded.inlineScripts.some((entry) => !Evidence.isPlainObject(entry)
          || !same(Object.keys(entry).sort(), inlineKeys))
        || !same(loaded.inlineScripts[0], {
          occurrence: pageOccurrences[0].occurrence,
          scriptId: pageOccurrences[0].scriptId,
          executionContextId: pageOccurrences[0].executionContextId,
          frameId: pageOccurrences[0].frameId,
          contextOrigin: pageOccurrences[0].contextOrigin,
          sourceMethod: pageOccurrences[0].sourceMethod,
          sha256: pageOccurrences[0].sourceSha256,
          bytes: pageOccurrences[0].sourceBytes,
        })) {
      fail("loaded_production_inline_script_invalid", "source_identity",
        lifecycle + " inline script source is detached from its raw page occurrence");
    }
    if (!(options && options.testOnlyAllowInjectedEvidence === true
        && options.skipFileClosure === true)) {
      const pageFile = Evidence.readExactRegularFile(
        path.join(bundle.root, "launcher", "web", "overlay.html"), {
          phase: "source_identity", maximumBytes: 16 * 1024 * 1024,
        });
      const html = pageFile.bytes.toString("utf8");
      const inlineSources = [];
      const scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
      let match;
      while ((match = scriptPattern.exec(html)) !== null) {
        if (!/\bsrc\s*=/.test(match[1])) inlineSources.push(match[2]);
      }
      const inlineBytes = inlineSources.length === 1
        ? Buffer.from(inlineSources[0], "utf8") : null;
      if (!inlineBytes || loaded.inlineScripts[0].sha256 !== Evidence.sha256Bytes(inlineBytes)
          || loaded.inlineScripts[0].bytes !== inlineBytes.length) {
        fail("loaded_production_inline_script_invalid", "source_identity",
          lifecycle + " inline CDP source bytes differ from current page source");
      }
    }
    executableOccurrences.forEach((occurrence, index) => {
      const resource = loaded.scripts[index];
      if (!resource || resource.occurrence !== occurrence.occurrence
          || resource.scriptId !== occurrence.scriptId
          || resource.executionContextId !== occurrence.executionContextId
          || resource.frameId !== occurrence.frameId
          || resource.contextOrigin !== occurrence.contextOrigin
          || resource.sha256 !== occurrence.sourceSha256
          || resource.bytes !== occurrence.sourceBytes) {
        fail("loaded_production_script_source_binding_invalid", "source_identity",
          lifecycle + " production script bytes are detached from the raw occurrence");
      }
    });
    loaded.styles.forEach((resource, index) => {
      const occurrence = loaded.styleOccurrences[index];
      if (!occurrence || resource.resourceOccurrence !== occurrence.occurrence
          || resource.frameId !== occurrence.frameId) {
        fail("loaded_production_style_source_binding_invalid", "source_identity",
          lifecycle + " production stylesheet bytes are detached from the raw occurrence");
      }
    });
    return loaded;
  }
  return { closure: bundle.sourceClosure, binding, candidateProducer,
    firstLoaded: verifyLoaded(runtime.first, "first"),
    restartLoaded: verifyLoaded(runtime.restart, "restart") };
}

function recordMoment(records, position, label) {
  const matches = records.filter((record) => record.sourceLineNumber === position.lineNumber);
  if (matches.length !== 1 || !Number.isFinite(Date.parse(matches[0].observedAt))) {
    fail("host_timeline_marker_invalid", "partial_order",
      "save/archive marker is not one exact Host record", { label, count: matches.length });
  }
  return matches[0].observedAt;
}

const STRICT_GLOBAL_BOUNDARY_LABELS = Object.freeze([
  "commit_response", "close_request", "close_operation_started",
  "close_dom_input", "close_exact_completion", "close_capture", "close_capture_mtime",
  "close_provider_completed", "close_ack", "safeexit_request",
  "safeexit_operation_started", "safeexit_native_input", "sv1", "sv2", "archive",
  "safeexit_capture", "safeexit_capture_mtime", "safeexit_provider_completed", "safeexit_ack", "archive_disk",
  "first_loaded",
  "exit_confirm_request", "exit_confirm_operation_started", "exit_confirm_native_input",
  "exit_confirm_capture", "exit_confirm_capture_mtime", "exit_confirm_provider_completed", "exit_confirm_ack",
  "first_clean_residue", "restart_open_request", "restart_open_operation_started",
  "restart_open_native_input", "restart_open_capture", "restart_open_capture_mtime",
  "restart_open_provider_completed",
  "restart_open_ack", "restart_close_request",
  "restart_close_operation_started", "restart_close_dom_input",
  "restart_close_exact_completion", "restart_close_capture", "restart_close_capture_mtime",
  "restart_close_provider_completed", "restart_close_ack", "restart_loaded",
  "restart_shutdown_request",
  "restart_shutdown_completion", "final_clean_residue",
]);

function assertStrictBoundaryChain(boundaries) {
  if (!Array.isArray(boundaries)
      || !same(boundaries.map((entry) => entry && entry[0]), STRICT_GLOBAL_BOUNDARY_LABELS)
      || boundaries.some((entry) => !Array.isArray(entry) || entry.length !== 2
        || !Number.isFinite(Date.parse(entry[1])))) {
    fail("global_partial_order_invalid", "partial_order",
      "global timeline boundary set is missing, extra, reordered, or not comparable");
  }
  for (let index = 1; index < boundaries.length; index += 1) {
    if (Date.parse(boundaries[index - 1][1]) >= Date.parse(boundaries[index][1])) {
      fail("global_partial_order_invalid", "partial_order",
        "Crafting controls, Host, save, restart, shutdown, and residue do not form one strict timeline", {
          badPair: [boundaries[index - 1][0], boundaries[index][0]],
        });
    }
  }
  return boundaries;
}

function verifyGlobalPartialOrder(bundle, runtime, first, host, control,
  persistence, residue, source) {
  const commit = host.firstMappings.find((entry) =>
    entry.domain === "crafting" && entry.cmd === "commit");
  const safe = control.exchanges.get("safe_exit");
  const exit = control.exchanges.get("exit_confirm");
  const firstCloseControl = control.exchanges.get("close_first_crafting");
  const restartOpenControl = control.exchanges.get("restart_open_crafting");
  const restartCloseControl = control.exchanges.get("restart_close_crafting");
  const positions = persistence.archive.positions;
  const sv1At = recordMoment(host.firstRecords, positions.sv1, "sv1");
  const sv2At = recordMoment(host.firstRecords, positions.sv2, "sv2");
  const archiveAt = recordMoment(host.firstRecords, positions.archive, "archive");
  if (!commit || commit.as2ResponseLine >= host.firstClose.completionLine
      || positions.archive.lineNumber > runtime.first.finalLogSnapshot.total
      || persistence.archive.finalSnapshotSha256
        !== runtime.first.finalLogSnapshot.tailSha256
      || host.restartClose.completionLine > runtime.restart.finalLogSnapshot.total
      || !firstCloseControl || !restartOpenControl || !restartCloseControl
      || !safe || !exit) {
    fail("global_partial_order_invalid", "partial_order",
      "one trusted timeline lacks a required Crafting control, Host, save, or restart boundary");
  }
  const boundaries = [
    ["commit_response", commit.as2ResponseObservedAt],
    ["close_request", firstCloseControl.request.issuedAt],
    ["close_operation_started", firstCloseControl.providerReceipt.startedAt],
    ["close_dom_input", firstCloseControl.providerReceipt.inputEvidence.observedAt],
    ["close_exact_completion", host.firstClose.completionObservedAt],
    ["close_capture", firstCloseControl.providerCaptureEvent.capturedAt],
    ["close_capture_mtime", firstCloseControl.providerCaptureEvent.fileModifiedAt],
    ["close_provider_completed", firstCloseControl.providerReceipt.completedAt],
    ["close_ack", firstCloseControl.ack.completedAt],
    ["safeexit_request", safe.request.issuedAt],
    ["safeexit_operation_started", safe.providerReceipt.startedAt],
    ["safeexit_native_input", safe.providerReceipt.inputEvidence.observedAt],
    ["sv1", sv1At], ["sv2", sv2At], ["archive", archiveAt],
    ["safeexit_capture", safe.providerCaptureEvent.capturedAt],
    ["safeexit_capture_mtime", safe.providerCaptureEvent.fileModifiedAt],
    ["safeexit_provider_completed", safe.providerReceipt.completedAt],
    ["safeexit_ack", safe.ack.completedAt],
    ["archive_disk", persistence.archive.disk.capturedAt],
    ["first_loaded", source.firstLoaded.capturedAt],
    ["exit_confirm_request", exit.request.issuedAt],
    ["exit_confirm_operation_started", exit.providerReceipt.startedAt],
    ["exit_confirm_native_input", exit.providerReceipt.inputEvidence.observedAt],
    ["exit_confirm_capture", exit.providerCaptureEvent.capturedAt],
    ["exit_confirm_capture_mtime", exit.providerCaptureEvent.fileModifiedAt],
    ["exit_confirm_provider_completed", exit.providerReceipt.completedAt],
    ["exit_confirm_ack", exit.ack.completedAt],
    ["first_clean_residue", residue.afterSafeExit.observedAt],
    ["restart_open_request", restartOpenControl.request.issuedAt],
    ["restart_open_operation_started", restartOpenControl.providerReceipt.startedAt],
    ["restart_open_native_input", restartOpenControl.providerReceipt.inputEvidence.observedAt],
    ["restart_open_capture", restartOpenControl.providerCaptureEvent.capturedAt],
    ["restart_open_capture_mtime", restartOpenControl.providerCaptureEvent.fileModifiedAt],
    ["restart_open_provider_completed", restartOpenControl.providerReceipt.completedAt],
    ["restart_open_ack", restartOpenControl.ack.completedAt],
    ["restart_close_request", restartCloseControl.request.issuedAt],
    ["restart_close_operation_started", restartCloseControl.providerReceipt.startedAt],
    ["restart_close_dom_input", restartCloseControl.providerReceipt.inputEvidence.observedAt],
    ["restart_close_exact_completion", host.restartClose.completionObservedAt],
    ["restart_close_capture", restartCloseControl.providerCaptureEvent.capturedAt],
    ["restart_close_capture_mtime", restartCloseControl.providerCaptureEvent.fileModifiedAt],
    ["restart_close_provider_completed", restartCloseControl.providerReceipt.completedAt],
    ["restart_close_ack", restartCloseControl.ack.completedAt],
    ["restart_loaded", source.restartLoaded.capturedAt],
    ["restart_shutdown_request", runtime.shutdownEvidence.requestedAt],
    ["restart_shutdown_completion", runtime.shutdownEvidence.completedAt],
    ["final_clean_residue", residue.final.observedAt],
  ];
  assertStrictBoundaryChain(boundaries);
  return { clock: "utc_iso8601_from_provider_cdp_and_stateful_host_prefix",
    boundaries: Object.fromEntries(boundaries),
    firstCloseLine: host.firstClose.completionLine,
    restartCloseLine: host.restartClose.completionLine };
}

function verifySemanticBundle(bundle, options) {
  const settings = options || {};
  validateEnvelope(bundle, settings);
  const runtime = verifyRuntime(bundle);
  verifyLifecycleTranscript(bundle.transcripts.first, "first");
  verifyLifecycleTranscript(bundle.transcripts.restart, "restart");
  const first = Protocol.verifyFirstTranscript(bundle.transcripts.first);
  const restart = Protocol.verifyRestartTranscript(bundle.transcripts.restart, first);
  const host = verifyHost(bundle, runtime, first, restart);
  const control = verifyControl(bundle, first, restart);
  const persistence = verifyPersistence(bundle, settings);
  const residue = verifyResidue(bundle);
  const sourceClosure = verifySourceClosure(bundle, runtime, settings);
  const partialOrder = verifyGlobalPartialOrder(bundle, runtime, first, host,
    control, persistence, residue, sourceClosure);
  if (settings.skipFileClosure === true && settings.testOnlyAllowInjectedEvidence !== true) {
    fail("test_only_bypass_forbidden", "bundle", "file closure bypass is test-only");
  }
  return { runtime, first, restart, host, control, persistence, residue,
    sourceClosure, partialOrder };
}

function verifyJsonArtifact(bundle, manifest, relative, role, expected) {
  const entry = manifest.get(relative);
  if (!entry || entry.role !== role) {
    fail("artifact_role_invalid", "artifact_manifest",
      "required raw artifact is absent or has the wrong role", { relative, role });
  }
  const value = readJsonFile(entry.absolutePath || path.join(bundle.runDir, relative),
    "artifact", 128 * 1024 * 1024).value;
  if (!same(value, expected)) {
    fail("artifact_bundle_mismatch", "artifact",
      "persisted raw artifact differs from the verified bundle", { relative });
  }
}

function artifactRolesForBundle(bundle, includeBundle) {
  const roles = {
    "crafting-first-passive-transcript.json": "raw_transcript",
    "crafting-first-passive-transcript.jsonl": "raw_transcript",
    "crafting-restart-passive-transcript.json": "raw_transcript",
    "crafting-restart-passive-transcript.jsonl": "raw_transcript",
    "first-host-as2-tail.json": "raw_host_as2",
    "restart-host-as2-tail.json": "raw_host_as2",
    "persistence-phases.json": "raw_persistence",
    "runtime-lifecycles.json": "raw_lifecycle",
    "source-closure.json": "production_source_closure",
    "source-binding.json": "production_source_binding",
    "candidate-producer.json": "candidate_producer_binding",
  };
  if (includeBundle) roles["journey-bundle.json"] = "verified_input";
  bundle.control.requests.forEach((request, index) => {
    const ack = bundle.control.acks[index];
    roles["control/requests/" + request.requestId + ".json"] = "control_request";
    roles["control/acks/" + request.requestId + ".json"] = "control_ack";
    roles["control/provider-receipts/" + request.requestId + ".json"] = "provider_receipt";
    roles["control/capture-events/" + request.requestId + ".json"] = "provider_capture_event";
    roles[ack.capture.relativePath] = "provider_capture";
  });
  return roles;
}

function assertManifestRoleSet(manifest, roles) {
  const expectedPaths = Object.keys(roles).sort();
  if (manifest.size !== expectedPaths.length
      || !same(Array.from(manifest.keys()), expectedPaths)
      || expectedPaths.some((relative) => manifest.get(relative).role !== roles[relative])) {
    fail("artifact_manifest_role_set_invalid", "artifact_manifest",
      "artifact manifest contains an extra, omission, reorder, or role drift", {
        expectedPaths, actualPaths: Array.from(manifest.keys()),
      });
  }
}

function verifyTranscriptArtifacts(bundle, manifest, options) {
  const settings = options || {};
  ["first", "restart"].forEach((phase) => {
    const prefix = "crafting-" + phase + "-passive-transcript";
    verifyJsonArtifact(bundle, manifest, prefix + ".json", "raw_transcript",
      bundle.transcripts[phase]);
    const entry = manifest.get(prefix + ".jsonl");
    if (!entry || entry.role !== "raw_transcript") {
      fail("transcript_artifact_role_invalid", "artifact_manifest",
        "raw transcript JSONL is absent", { phase });
    }
    const file = Evidence.readExactRegularFile(
      entry.absolutePath || path.join(bundle.runDir, prefix + ".jsonl"), {
        phase: "transcript_artifact", maximumBytes: 128 * 1024 * 1024,
      });
    const text = file.bytes.toString("utf8");
    if (!text.endsWith("\n")) fail("transcript_jsonl_invalid", "transcript_artifact",
      "transcript JSONL lacks a terminal newline");
    let events;
    try { events = text.slice(0, -1).split("\n").map((line) => JSON.parse(line)); }
    catch (error) { fail("transcript_jsonl_invalid", "transcript_artifact", error.message); }
    if (!same(events, bundle.transcripts[phase].events)) {
      fail("transcript_jsonl_bundle_mismatch", "transcript_artifact",
        "raw transcript stream differs from bundle");
    }
  });
  if (settings.skipBundle !== true) {
    verifyJsonArtifact(bundle, manifest, "journey-bundle.json", "verified_input", bundle);
  }
  verifyJsonArtifact(bundle, manifest, "first-host-as2-tail.json", "raw_host_as2",
    bundle.hostArtifacts.first);
  verifyJsonArtifact(bundle, manifest, "restart-host-as2-tail.json", "raw_host_as2",
    bundle.hostArtifacts.restart);
  verifyJsonArtifact(bundle, manifest, "persistence-phases.json", "raw_persistence",
    bundle.persistence);
  verifyJsonArtifact(bundle, manifest, "runtime-lifecycles.json", "raw_lifecycle",
    bundle.runtime);
  verifyJsonArtifact(bundle, manifest, "source-closure.json", "production_source_closure",
    bundle.sourceClosure);
  verifyJsonArtifact(bundle, manifest, "source-binding.json", "production_source_binding",
    bundle.sourceBinding);
  verifyJsonArtifact(bundle, manifest, "candidate-producer.json", "candidate_producer_binding",
    bundle.candidateProducer);
  bundle.control.requests.forEach((request, index) => {
    const ack = bundle.control.acks[index];
    verifyJsonArtifact(bundle, manifest, "control/requests/" + request.requestId + ".json",
      "control_request", request);
    verifyJsonArtifact(bundle, manifest, "control/acks/" + request.requestId + ".json",
      "control_ack", ack);
    const provider = verifyProviderReceiptReference(bundle.root, bundle.runDir, request, ack);
    verifyJsonArtifact(bundle, manifest, provider.relativePath, "provider_receipt",
      provider.receipt);
    verifyJsonArtifact(bundle, manifest, provider.captureEvent.relativePath,
      "provider_capture_event", provider.captureEvent.value);
    const captureEntry = manifest.get(ack.capture.relativePath);
    if (!captureEntry || captureEntry.role !== "provider_capture"
        || captureEntry.sha256 !== provider.capture.sha256
        || captureEntry.bytes !== provider.capture.bytes
        || ack.capture.relativePath !== provider.capture.relativePath) {
      fail("control_capture_artifact_role_invalid", "artifact_manifest",
        "provider-owned capture is absent, changed, or has the wrong role", {
          step: request.step,
        });
    }
  });
  return true;
}

function verifyPostSealClosure(bundle, preSealArtifacts) {
  const manifestValue = readJsonFile(path.join(bundle.runDir, "artifact-manifest.json"),
    "artifact_manifest", 16 * 1024 * 1024).value;
  const manifest = verifyArtifactManifest({
    root: bundle.root, runDir: bundle.runDir, manifest: manifestValue,
    ownedBaseRelative: OWNED_BASE_RELATIVE,
  });
  // Attach absolute paths only after the manifest itself has been verified.
  manifest.forEach((entry, relative) => {
    entry.absolutePath = path.join(bundle.runDir, relative.replace(/\//g, path.sep));
  });
  assertManifestRoleSet(manifest, artifactRolesForBundle(bundle, true));
  if (Array.isArray(preSealArtifacts)) {
    const finalProjection = Array.from(manifest.values()).filter((entry) =>
      entry.relativePath !== "journey-bundle.json").map((entry) => ({
        relativePath: entry.relativePath, role: entry.role,
        bytes: entry.bytes, sha256: entry.sha256,
      }));
    if (!same(finalProjection, preSealArtifacts)) {
      fail("preseal_artifact_binding_invalid", "artifact_manifest",
        "raw artifact bytes changed after pre-seal verification");
    }
    verifyJsonArtifact(bundle, manifest, "journey-bundle.json", "verified_input", bundle);
  } else {
    verifyTranscriptArtifacts(bundle, manifest);
    SourceContract.assertCurrentSourceClosure(path.resolve(__dirname, "..", "..", ".."),
      bundle.sourceClosure);
  }
  ModuleJournal.verifyRuntimeModuleJournal({
    root: bundle.root, manifest: bundle.moduleJournal.manifest,
    artifact: bundle.moduleJournal.artifact,
  });
  return manifest;
}

function verifyPreSealArtifacts(bundle) {
  ["journey-bundle.json", "artifact-manifest.json", "verified-receipt.json"].forEach((name) => {
    if (fs.existsSync(path.join(bundle.runDir, name))) {
      fail("preseal_artifact_state_invalid", "artifact_manifest",
        "final bundle, manifest, or receipt existed before module admission", { name });
    }
  });
  const roles = artifactRolesForBundle(bundle, false);
  const provisional = buildArtifactManifest({
    root: bundle.root, runDir: bundle.runDir, runId: bundle.runId,
    ownedBaseRelative: OWNED_BASE_RELATIVE, roleByPath: roles,
  });
  const manifest = new Map(provisional.entries.map((entry) => [entry.relativePath,
    Object.assign({ absolutePath: path.join(bundle.runDir,
      entry.relativePath.replace(/\//g, path.sep)) }, entry)]));
  assertManifestRoleSet(manifest, roles);
  verifyTranscriptArtifacts(bundle, manifest, { skipBundle: true });
  return provisional.entries.map((entry) => ({ relativePath: entry.relativePath,
    role: entry.role, bytes: entry.bytes, sha256: entry.sha256 }));
}

function verifyPreSealModuleManifest(bundle) {
  if (!Evidence.isPlainObject(bundle.moduleJournal)
      || !Evidence.isPlainObject(bundle.moduleJournal.manifest)
      || bundle.moduleJournal.artifact !== null) {
    fail("module_journal_preseal_invalid", "module_journal",
      "pre-seal verification requires the exact active manifest and no sealed artifact");
  }
  ModuleJournal.verifyExplicitModuleManifest({
    root: bundle.root, manifest: bundle.moduleJournal.manifest,
  });
  const phases = ["domain_loaded", "clone_prepared", "first_captured", "restart_captured",
    "verification_executed", "terminal"];
  if (!same(bundle.moduleJournal.manifest.requiredPhases, phases)) {
    fail("module_journal_phase_invalid", "module_journal",
      "live Crafting manifest lacks the verification_executed checkpoint");
  }
  return bundle.moduleJournal.manifest;
}

function verifyBundle(bundle, options) {
  const settings = options || {};
  const preSeal = settings.preSeal === true;
  if (preSeal && bundle.evidenceMode !== "live_capture") {
    fail("preseal_evidence_mode_invalid", "bundle",
      "only an unsealed live capture may enter pre-seal verification");
  }
  const result = verifySemanticBundle(bundle, settings);
  const manifest = preSeal ? null : verifyPostSealClosure(bundle);
  if (preSeal) verifyPreSealModuleManifest(bundle);
  const receipt = {
    schema: RECEIPT_SCHEMA, apiVersion: API_VERSION, status: "e2e_verified",
    deployment: "NOT_DEPLOYED", verifiedAt: new Date().toISOString(),
    runId: bundle.runId, targetSlot: bundle.targetSlot,
    candidateIdentity: bundle.runtime.expectedIdentity,
    selectedTransport: result.control.capability.selectedTransport,
    category: result.first.category, recipeIndex: result.first.selector.recipeIndex,
    craftCount: result.first.selector.craftCount, outputIdentity: result.first.identity,
    authorityContract: {
      previewAuthorityConsumed: true,
      transactionRefCount: 0,
      authorityModel: "Crafting v1 commit has no transactionId field",
      postconditionFreshCrafting: true,
      postconditionInventoryDelta: result.first.inventory.expectedOutputDelta,
      postconditionInventoryCount: result.first.inventory.afterCount,
      restartInventoryCount: result.restart.inventory.count,
      inventoryNonceContinuousWithinProcess: true,
      inventoryNonceFreshAfterRestart: true,
      exactOwnerBoundClosePerLifecycle: true,
      hostRelevantMultisetExact: true,
    },
    firstOwner: result.first.owner, restartOwner: result.restart.owner,
    firstHostMappings: result.host.firstMappings,
    restartHostMappings: result.host.restartMappings,
    hostClose: { first: result.host.firstClose, restart: result.host.restartClose },
    persistence: {
      committedSha256: result.persistence.committedDisk.sha256,
      restartSha256: result.persistence.restartDisk.sha256,
      archiveEvidenceSha256: result.persistence.archive.evidenceSha256,
      releaseSha256: result.persistence.release.releaseSha256,
    },
    artifactCount: preSeal ? null : manifest.size,
    moduleJournalSha256: preSeal ? null : bundle.moduleJournal.artifact.evidenceSha256,
    sourceClosureSha256: result.sourceClosure.closure.closureSha256,
    sourceBindingSha256: result.sourceClosure.binding.bindingSha256,
    runtimeProducerInputsSha256:
      result.sourceClosure.closure.records[0].fingerprint.producerInputs.inputsSha256,
    candidateProducerSha256: result.sourceClosure.candidateProducer.evidenceSha256,
    firstLoadedProductionSha256: result.sourceClosure.firstLoaded.evidenceSha256,
    restartLoadedProductionSha256: result.sourceClosure.restartLoaded.evidenceSha256,
    partialOrder: result.partialOrder,
    boundaries: {
      deployment: false, operatorAcknowledgementIsBusinessProof: false,
      operatorAckTimestampsAreSelfReported: true,
      providerToolResultReceiptsBound: true,
      browserEventIsTrustedNotPhysicalProof: true,
      physicalInputAttestation: false, rawAuthorityMaterialPublished: false,
      responseToDownstreamTotalOrderClaimed: false,
      observationOrder: "trusted_input_and_bridge_send_partial_order",
    },
  };
  assertNoRawAuthority(receipt, "receipt");
  receipt.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
  return receipt;
}

function preSealProjection(bundle) {
  const projection = JSON.parse(JSON.stringify(bundle));
  if (projection.moduleJournal) projection.moduleJournal.artifact = null;
  return projection;
}

function verifyBundlePreSeal(bundle) {
  const provisionalReceipt = verifyBundle(bundle, { preSeal: true });
  const artifacts = verifyPreSealArtifacts(bundle);
  const evidence = {
    schema: "workbench-live-e2e.crafting.preseal-verification.v1",
    bundleProjectionSha256: Evidence.sha256Text(
      Evidence.canonicalJson(preSealProjection(bundle))),
    provisionalReceipt,
    provisionalReceiptSha256: Evidence.sha256Text(
      Evidence.canonicalJson(provisionalReceipt)),
    artifacts,
  };
  evidence.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(evidence));
  return evidence;
}

function finalizePreSealVerification(bundle, evidence) {
  const payload = Object.assign({}, evidence);
  delete payload.evidenceSha256;
  if (!Evidence.isPlainObject(evidence)
      || !same(Object.keys(evidence).sort(), ["artifacts", "bundleProjectionSha256",
        "evidenceSha256", "provisionalReceipt", "provisionalReceiptSha256", "schema"].sort())
      || evidence.schema !== "workbench-live-e2e.crafting.preseal-verification.v1"
      || evidence.bundleProjectionSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(preSealProjection(bundle)))
      || evidence.provisionalReceiptSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(evidence.provisionalReceipt))
      || evidence.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(payload))) {
    fail("preseal_verification_binding_invalid", "module_journal",
      "sealed finalization is detached from the exact pre-seal semantic verification");
  }
  const manifest = verifyPostSealClosure(bundle, evidence.artifacts);
  const receipt = JSON.parse(JSON.stringify(evidence.provisionalReceipt));
  delete receipt.receiptSha256;
  receipt.artifactCount = manifest.size;
  receipt.moduleJournalSha256 = bundle.moduleJournal.artifact.evidenceSha256;
  receipt.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
  return receipt;
}

module.exports = {
  STRICT_GLOBAL_BOUNDARY_LABELS,
  TRUSTED_AUTHORIZATION_SOURCES,
  TRUSTED_CAPABILITY_SOURCES,
  assertStrictBoundaryChain,
  artifactRolesForBundle,
  parseFlash,
  parseDispatch,
  parsePanel,
  parseSocket,
  recordsForLifecycle,
  finalizePreSealVerification,
  verifyBundle,
  verifyBundlePreSeal,
  verifyHostPair,
  verifySemanticBundle,
  verifyTranscriptArtifacts,
};
