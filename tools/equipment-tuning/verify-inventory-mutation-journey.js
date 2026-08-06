#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

const {
  assertRuntimeIdentity,
  publicRuntimeIdentity,
  resolveExpectedRuntimeIdentity,
} = require("../lib/runtime-process-identity");
const opener = require("./run-unattended");
const previewGate = require("./verify-journey");
const commitGate = require("./verify-commit-journey");

const ROOT = path.resolve(__dirname, "../..");
const SLOT = opener.DEFAULT_AGENT_SLOT;
const GATE = "A2-INVENTORY-NORMAL-MUTATION-E2E";
const DEFAULT_REPORT = path.join(
  ROOT,
  "tmp",
  "equipment-tuning",
  "unattended",
  "20260802T130205Z-cf7_agent_equipment_tuning",
  "run-report.json"
);
const SOURCE = Object.freeze({ containerId: "背包", slot: 0 });
const DESTINATION = Object.freeze({ containerId: "战备箱", slot: 9 });
const ITEM = Object.freeze({ name: "手枪通用弹药", quantity: 87 });
const EXPECTED = Object.freeze({
  reportRelative: "tmp/equipment-tuning/unattended/20260802T130205Z-cf7_agent_equipment_tuning/run-report.json",
  candidateDirectory: "c-acb7d341bf25-08846e81b3-20260802t112923788z-0de05d30",
  buildIdentity: "ACB7D341BF2524AD9FA4B2FBBBF48DC3B48020FEE799899C70FAA0FD7DA4C090",
  payloadClosure: "DE073A8934696B62DF95741779EA2B99AE27F5E1C294C74687AAA53D4711EFA3",
  coreDllSha256: "639944974F1A6F9A521540DF4F7907FEBEB22F9FF3ECF28BC7AE0485D3BFF09D",
  coreExeSha256: "86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD",
  seedSha256: "E7C8B3307C3A31FDF4951676911E61227982DE1605B9862C05CD38BDD3E3A3DC",
  seededTargetSha256: "3E2FDCBE03796B3E4C7A60F428B1CFB5725B5811D02E4A5C77874BE6D42F9777",
  semanticSha256: "BA8B5391FBE047C90ECD591B0991A19B9305E02DE37E2E6D56DC5A0F7B20C71C",
  gateBaselineSha256: "137698294042B6C8FD367F4A383F8CC7E2310D132E9092236890F405B62E08D3",
  finalCloneSha256: "2D0CD5B49EDD25C4AD7D8FD771473A2C61E625FFA4FBAE69A8C511451FD5B9CE",
  finalLastSaved: "2026-08-02 21:18:49",
  firstPid: 23656,
  firstAttemptId: "e0d21b8811754700b9461fe59d74c09d",
  firstPanelInstanceId: "panel__w8CLEyXPO9k7a_frRRPJADl",
  firstViewSessionId: "tuning.msbt9uxr.7147xh",
  firstInventorySessionNonce: "inv21983.1",
  mutationWebCallId: "inventory-workbench.inventory-workbench.msbt9uuc.hf7ryh.1.3",
  mutationFlashCallId: 3,
  secondPid: 15520,
  secondAttemptId: "0661b1effbc644ac9d9e01f4bb694232",
  secondPanelInstanceId: "panel_UHJliwb_Fpbv4y2dT8LynB1C",
  secondViewSessionId: "tuning.msbttj5k.loe0ws",
  secondInventorySessionNonce: "inv22903.1",
});

class VerificationError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "VerificationError";
    this.code = code;
    this.details = details || null;
  }
}

function fail(code, message, details) {
  throw new VerificationError(code, message, details);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function relativeTo(root, filePath) {
  return path.relative(root, filePath).replace(/\\/g, "/");
}

function readRegularFile(filePath, label) {
  let stat;
  try {
    stat = fs.lstatSync(filePath);
  } catch (error) {
    fail("artifact_missing", label + " is missing", { filePath, message: error.message });
  }
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("artifact_not_regular", label + " must be a regular non-reparse file", { filePath });
  }
  const realPath = fs.realpathSync.native(filePath);
  if (!samePath(realPath, filePath)) {
    fail("artifact_realpath_mismatch", label + " real path changed", { filePath, realPath });
  }
  return fs.readFileSync(filePath);
}

function readJson(filePath, label) {
  const raw = readRegularFile(filePath, label);
  try {
    return { raw, data: JSON.parse(raw.toString("utf8")) };
  } catch (error) {
    fail("artifact_json_invalid", label + " is not valid JSON", {
      filePath,
      message: error.message,
    });
  }
}

function parseArgs(argv) {
  const args = { check: false, help: false, openReport: DEFAULT_REPORT };
  function next(index, flag) {
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail("missing_argument", flag + " requires a value");
    return value;
  }
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else if (token === "--open-report") args.openReport = next(index++, token);
    else fail("unknown_argument", "unknown argument: " + token);
  }
  if (args.check && argv.length !== 1) {
    fail("check_argument_conflict", "--check must be used alone");
  }
  return args;
}

function printHelp() {
  console.log([
    "Read-only A2 Inventory mutation/restart evidence verifier",
    "",
    "Usage:",
    "  node tools/equipment-tuning/verify-inventory-mutation-journey.js",
    "  node tools/equipment-tuning/verify-inventory-mutation-journey.js --check",
    "",
    "The default gate reads only the frozen 20260802T130205 opener report,",
    "launcher.log, the exact seed/clone JSON, and exact candidate metadata/runtime bytes.",
    "It does not connect to CDP, start or stop Launcher, mutate a save, or attest physical input.",
  ].join("\n"));
}

function recordAt(data, containerId, slot) {
  const inventory = data && data.inventory;
  const container = inventory && inventory[containerId];
  if (!container) return null;
  const value = Array.isArray(container) ? container[slot] : container[String(slot)];
  return isObject(value) ? value : null;
}

function assertExactItem(record, label) {
  if (!record || record.name !== ITEM.name || Number(record.value) !== ITEM.quantity) {
    fail("item_coordinate_mismatch", label + " does not contain the exact item/quantity", {
      expected: ITEM,
      actual: record,
    });
  }
  return true;
}

function firstEmptySlot(data, containerId, limit) {
  for (let slot = 0; slot < limit; slot += 1) {
    if (!recordAt(data, containerId, slot)) return slot;
  }
  return null;
}

function validateSeedAndFinal(seedData, finalData) {
  const seedSource = recordAt(seedData, SOURCE.containerId, SOURCE.slot);
  const seedDestination = recordAt(seedData, DESTINATION.containerId, DESTINATION.slot);
  assertExactItem(seedSource, "seed source 背包:0");
  if (seedDestination) {
    fail("seed_destination_not_empty", "seed destination 战备箱:9 was not empty", seedDestination);
  }
  const matchingBattlebox = [];
  for (let slot = 0; slot < 40; slot += 1) {
    const record = recordAt(seedData, "战备箱", slot);
    if (record && record.name === ITEM.name) matchingBattlebox.push(slot);
  }
  if (matchingBattlebox.length !== 0) {
    fail("seed_merge_target_present", "mergeThenEmpty had an earlier merge target", {
      slots: matchingBattlebox,
    });
  }
  const firstEmpty = firstEmptySlot(seedData, "战备箱", 40);
  if (firstEmpty !== DESTINATION.slot) {
    fail("seed_first_empty_mismatch", "authority-selected first empty slot was not 战备箱:9", {
      firstEmpty,
    });
  }
  if (recordAt(finalData, SOURCE.containerId, SOURCE.slot)) {
    fail("final_source_not_empty", "final clone still contains an item at 背包:0");
  }
  const finalDestination = recordAt(finalData, DESTINATION.containerId, DESTINATION.slot);
  assertExactItem(finalDestination, "final destination 战备箱:9");
  if (String(finalDestination.lastUpdate) !== String(seedSource.lastUpdate)) {
    fail("moved_item_timestamp_changed", "final item is not the same persisted inventory record", {
      before: seedSource.lastUpdate,
      after: finalDestination.lastUpdate,
    });
  }
  return {
    sourceBefore: seedSource,
    destinationBefore: null,
    sourceAfter: null,
    destinationAfter: finalDestination,
    authorityFirstEmptySlot: firstEmpty,
    mergeCandidateCount: matchingBattlebox.length,
  };
}

function stripTimestamp(line) {
  return String(line || "").replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
}

function readLogRecords(filePath) {
  const raw = readRegularFile(filePath, "launcher.log").toString("utf8");
  return raw.split(/\r?\n/).map((line, index) => ({
    line,
    body: stripTimestamp(line),
    lineNumber: index + 1,
  }));
}

function parsePanelMessage(record) {
  const marker = "[Panel] HandlePanelMessage: ";
  if (!record.body.startsWith(marker)) return null;
  try {
    return { record, message: JSON.parse(record.body.slice(marker.length)) };
  } catch (error) {
    fail("panel_log_json_invalid", "Panel message log is malformed", {
      lineNumber: record.lineNumber,
      message: error.message,
    });
  }
}

function parseTaskSend(record) {
  const marker = "[InventoryTask] -> Flash: ";
  if (!record.body.startsWith(marker)) return null;
  try {
    return { record, message: JSON.parse(record.body.slice(marker.length)) };
  } catch (error) {
    fail("inventory_send_log_json_invalid", "InventoryTask send log is malformed", {
      lineNumber: record.lineNumber,
      message: error.message,
    });
  }
}

function parseInventoryResponse(record) {
  const marker = "[XmlSocket:JSON] ";
  if (!record.body.startsWith(marker) || !record.body.includes('"task":"inventory_response"')) {
    return null;
  }
  const callId = record.body.match(/\{"callId":(\d+),"task":"inventory_response"/);
  const sessionNonce = record.body.match(/"sessionNonce":"([A-Za-z0-9._-]+)"/);
  const operation = record.body.match(/"operation":"([A-Za-z]+)"/);
  const policy = record.body.match(/"policy":"([A-Za-z]+)"/);
  return {
    record,
    callId: callId ? Number(callId[1]) : null,
    success: record.body.includes('"success":true'),
    versionOne: record.body.includes('"v":1'),
    sessionNonce: sessionNonce ? sessionNonce[1] : null,
    operation: operation ? operation[1] : null,
    policy: policy ? policy[1] : null,
    hasSnapshots: record.body.includes('"snapshots":['),
    destinationTruncated: record.body.includes('"destination":...'),
  };
}

function exactWindows(value, equipmentScope) {
  if (!Array.isArray(value) || value.length !== 2) return false;
  const expected = [
    Object.assign({ containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
      equipmentScope ? { scope: "equipment" } : {}),
    { containerId: "战备箱", offset: 0, limit: 40, filterKey: "all" },
  ];
  return JSON.stringify(value) === JSON.stringify(expected);
}

function requireOne(values, code, message) {
  if (values.length !== 1) fail(code, message, { count: values.length });
  return values[0];
}

function findAfter(records, afterLine, predicate) {
  return records.filter((record) => record.lineNumber > afterLine && predicate(record));
}

function validateMutationLog(records, report, expected) {
  const panelEntries = records.map(parsePanelMessage).filter(Boolean).filter((entry) => (
    entry.message.domain === "inventory" && entry.message.cmd === "autoTransfer"
  ));
  const panel = requireOne(
    panelEntries,
    "mutation_panel_request_count",
    "expected exactly one inventory autoTransfer Web request"
  );
  const message = panel.message;
  const payload = message.payload || {};
  if (message.type !== "panel" || message.panel !== "workbench"
      || message.panelInstanceId !== expected.firstPanelInstanceId
      || message.callId !== expected.mutationWebCallId
      || payload.v !== 1
      || !isObject(payload.source)
      || payload.source.containerId !== SOURCE.containerId
      || payload.source.slot !== SOURCE.slot
      || typeof payload.source.expectedLease !== "string"
      || !payload.source.expectedLease.startsWith(expected.firstInventorySessionNonce + ".")
      || payload.targetContainerId !== DESTINATION.containerId
      || payload.policy !== "mergeThenEmpty"
      || !exactWindows(payload.windows, false)) {
    fail("mutation_panel_tuple_mismatch", "autoTransfer Web tuple is not exact", message);
  }
  const route = requireOne(
    records.filter((record) => record.body
      === "[Panel] Routing domain=inventory cmd=autoTransfer to InventoryTask, _inventoryTask=ok"),
    "mutation_route_count",
    "expected exactly one successful inventory autoTransfer route"
  );
  const sends = records.map(parseTaskSend).filter(Boolean).filter((entry) => (
    entry.message.action === "inventoryAutoTransfer"
  ));
  const send = requireOne(sends, "mutation_send_count", "expected exactly one InventoryTask mutation send");
  const sent = send.message;
  if (sent.task !== "cmd" || sent.callId !== expected.mutationFlashCallId || sent.v !== 1
      || JSON.stringify(sent.source) !== JSON.stringify(payload.source)
      || sent.targetContainerId !== payload.targetContainerId
      || sent.policy !== payload.policy || !exactWindows(sent.windows, false)) {
    fail("mutation_send_tuple_mismatch", "InventoryTask send did not preserve the Web tuple", sent);
  }
  const firstShutdownFence = records.find((record) => record.lineNumber > send.record.lineNumber
    && record.body === "event=character_build_shutdown_fence result=pass reason=no_binding");
  if (!firstShutdownFence) {
    fail("mutation_run_boundary_missing", "first mutation run has no shutdown boundary");
  }
  const response = requireOne(
    records.map(parseInventoryResponse).filter(Boolean)
      .filter((entry) => entry.callId === expected.mutationFlashCallId
        && entry.record.lineNumber > send.record.lineNumber
        && entry.record.lineNumber < firstShutdownFence.lineNumber),
    "mutation_response_count",
    "expected exactly one response for InventoryTask callId 3 in the opener-bound run"
  );
  if (!response.success || !response.versionOne || response.operation !== "move"
      || response.policy !== "mergeThenEmpty" || !response.destinationTruncated) {
    fail("mutation_response_mismatch", "Inventory response was not a successful move", response);
  }
  if (!(panel.record.lineNumber < route.lineNumber
      && route.lineNumber < send.record.lineNumber
      && send.record.lineNumber < response.record.lineNumber)) {
    fail("mutation_log_order_invalid", "Web → Host → AS2 → response order is invalid");
  }
  if (report.snapshotGate.evidence.activeWorkbench.panelInstanceId !== message.panelInstanceId) {
    fail("mutation_cross_panel", "mutation panel does not match the opener-bound panel");
  }
  return {
    webCallId: message.callId,
    flashCallId: sent.callId,
    expectedLease: sent.source.expectedLease,
    panelInstanceId: message.panelInstanceId,
    requestLine: panel.record.lineNumber,
    routeLine: route.lineNumber,
    sendLine: send.record.lineNumber,
    responseLine: response.record.lineNumber,
    operation: response.operation,
    policy: response.policy,
    responseDestinationFieldTruncatedByHostLog: true,
  };
}

function parseArchive(record, expectedPath) {
  const match = record.body.match(
    /^\[ArchiveTask\] Shadow saved: ([A-Za-z0-9_-]+) \((\d+) chars\) path=(.+)$/
  );
  if (!match || match[1] !== SLOT || !samePath(match[3], expectedPath)) return null;
  return {
    lineNumber: record.lineNumber,
    textChars: Number(match[2]),
    path: match[3],
  };
}

function validateSafeSaveAndFirstShutdown(records, mutation, clonePath) {
  const archives = findAfter(records, mutation.responseLine, (record) => !!parseArchive(record, clonePath))
    .map((record) => parseArchive(record, clonePath));
  if (archives.length < 1) fail("post_mutation_archive_missing", "no clone archive followed the mutation");
  const safeArchive = archives.find((archive) => {
    const preceding = records.filter((record) => record.lineNumber < archive.lineNumber
      && record.lineNumber >= archive.lineNumber - 3);
    return preceding.some((record) => record.body.startsWith("[Frame:UI]")
      && record.body.includes("sv:1") && record.body.includes("sv:2"));
  });
  if (!safeArchive) {
    fail("safe_save_telemetry_missing", "no post-mutation archive is adjacent to sv:1/sv:2 telemetry");
  }
  const shadowTransport = records.find((record) => record.lineNumber > mutation.responseLine
    && record.lineNumber < safeArchive.lineNumber
    && record.body.includes('[XmlSocket:JSON] (len=')
    && record.body.includes('"payload":{"op":"shadow","slot":"' + SLOT + '"')
    && record.line.endsWith("..."));
  if (!shadowTransport) {
    fail("truncated_shadow_transport_missing",
      "post-mutation save has no logger-truncated shadow transport evidence");
  }
  const shutdownFence = findAfter(records, safeArchive.lineNumber, (record) => (
    record.body === "event=character_build_shutdown_fence result=pass reason=no_binding"
  ))[0];
  const shuttingDown = shutdownFence && findAfter(records, shutdownFence.lineNumber, (record) => (
    record.body === "[Guardian] Shutting down..."
  ))[0];
  const httpStopped = shuttingDown && findAfter(records, shuttingDown.lineNumber, (record) => (
    record.body === "[HTTP] Stopped"
  ))[0];
  if (!shutdownFence || !shuttingDown || !httpStopped) {
    fail("first_supported_shutdown_missing", "first run lacks the supported shutdown fence/stop chain");
  }
  return {
    shadowTransportLine: shadowTransport.lineNumber,
    shadowTransportLoggerLineChars: shadowTransport.line.length,
    shadowPayloadTruncatedByLogger: true,
    shadowPayloadParsed: false,
    firstSafeArchive: safeArchive,
    postMutationArchiveCount: archives.filter((entry) => entry.lineNumber < shutdownFence.lineNumber).length,
    shutdownFenceLine: shutdownFence.lineNumber,
    shuttingDownLine: shuttingDown.lineNumber,
    httpStoppedLine: httpStopped.lineNumber,
  };
}

function panelSnapshots(records, afterLine) {
  return records.map(parsePanelMessage).filter(Boolean).filter((entry) => (
    entry.record.lineNumber > afterLine
      && entry.message.domain === "inventory"
      && entry.message.cmd === "snapshot"
  ));
}

function taskSnapshots(records, afterLine) {
  return records.map(parseTaskSend).filter(Boolean).filter((entry) => (
    entry.record.lineNumber > afterLine && entry.message.action === "inventorySnapshot"
  ));
}

function validateFreshRestart(records, report, mutation, firstShutdown, clonePath, finalTextLength,
  expected) {
  const separators = findAfter(records, firstShutdown.httpStoppedLine, (record) => (
    /^═+ 2026-08-02 21:18:12 ═+$/.test(record.body)
  ));
  const restart = requireOne(separators, "fresh_restart_boundary_count", "fresh restart boundary missing");
  const postRestart = records.filter((record) => record.lineNumber > restart.lineNumber);
  const secondStopBoundary = postRestart.find((record) => record.body === "[HTTP] Stopped");
  if (!secondStopBoundary) {
    fail("fresh_run_boundary_missing", "fresh restart has no HTTP stop boundary");
  }
  const secondRecords = postRestart.filter((record) => (
    record.lineNumber <= secondStopBoundary.lineNumber
  ));
  const expectedProcessPath = report.runtimeIdentity.processPath;
  const pathEvidence = secondRecords.find((record) => record.body.startsWith("[DPI] Compatibility override:")
    && record.body.includes("path=" + expectedProcessPath + " "));
  if (!pathEvidence) fail("fresh_candidate_path_missing", "fresh restart did not log the exact candidate path");
  const solHit = secondRecords.find((record) => record.body.startsWith("[SolFileLocator] hit ")
    && record.body.includes("\\" + SLOT + ".sol"));
  const sameCloneSeed = secondRecords.find((record) => record.body
    === "[ArchiveTask] seed shadow saved: slot=" + SLOT + " path=" + clonePath);
  const resolver = secondRecords.find((record) => record.body
    === "[SolResolver] snapshot source=sol slot=" + SLOT
      + " seedAuthority=True target=" + clonePath);
  if (!solHit || !sameCloneSeed || !resolver
      || !(solHit.lineNumber < sameCloneSeed.lineNumber
        && sameCloneSeed.lineNumber <= resolver.lineNumber)) {
    fail("fresh_clone_sol_rehydration_missing", "fresh restart did not rehydrate the same clone SOL");
  }
  const attempts = secondRecords.map((record) => {
    const match = record.body.match(/^\[Prewarm\] triggered attemptId=([a-f0-9]{32})$/);
    return match ? { record, attemptId: match[1] } : null;
  }).filter(Boolean);
  const attempt = requireOne(attempts, "fresh_attempt_count", "fresh attempt evidence missing");
  if (attempt.attemptId !== expected.secondAttemptId
      || attempt.attemptId === expected.firstAttemptId) {
    fail("fresh_attempt_mismatch", "fresh attemptId is not exact/new", attempt);
  }
  const status = secondRecords.find((record) => record.body.includes('"task":"agent_runtime_status"')
    && record.body.includes('"loaded":true')
    && record.body.includes('"savePath":"' + SLOT + '"')
    && record.body.includes('"attemptId":"' + expected.secondAttemptId + '"')
    && record.body.includes('"source":"launcher_snapshot:sol"'));
  if (!status) fail("fresh_runtime_status_missing", "fresh AS2 runtime did not bind the clone SOL");
  const titlePid = secondRecords.map((record) => {
    const match = record.body.match(/pid=(\d+)[^"]*title="CF7:FlashNight [^"]+"/);
    return match ? Number(match[1]) : null;
  }).find((pid) => pid === expected.secondPid);
  if (titlePid !== expected.secondPid || titlePid === expected.firstPid) {
    fail("fresh_pid_mismatch", "fresh candidate PID evidence is missing or reused");
  }
  const snapshots = panelSnapshots(records, restart.lineNumber);
  const scopedPanel = requireOne(snapshots.filter((entry) => exactWindows(
    entry.message.payload && entry.message.payload.requests, true
  )), "fresh_scoped_snapshot_count", "fresh equipment-scope snapshot request missing");
  const fullPanel = requireOne(snapshots.filter((entry) => exactWindows(
    entry.message.payload && entry.message.payload.requests, false
  )), "fresh_full_snapshot_count", "fresh full snapshot request missing");
  for (const entry of [scopedPanel, fullPanel]) {
    if (entry.message.panelInstanceId !== expected.secondPanelInstanceId
        || entry.message.panelInstanceId === expected.firstPanelInstanceId) {
      fail("fresh_panel_mismatch", "fresh snapshot did not use the exact new panel", entry.message);
    }
  }
  const sends = taskSnapshots(records, restart.lineNumber);
  const scopedSend = requireOne(sends.filter((entry) => entry.message.callId === 1
    && exactWindows(entry.message.requests, true)), "fresh_call1_count", "fresh callId 1 missing");
  const fullSend = requireOne(sends.filter((entry) => entry.message.callId === 2
    && exactWindows(entry.message.requests, false)), "fresh_call2_count", "fresh callId 2 missing");
  const responses = records.map(parseInventoryResponse).filter(Boolean)
    .filter((entry) => entry.record.lineNumber > restart.lineNumber);
  const response1 = requireOne(responses.filter((entry) => entry.callId === 1),
    "fresh_response1_count", "fresh callId 1 response missing");
  const response2 = requireOne(responses.filter((entry) => entry.callId === 2),
    "fresh_response2_count", "fresh callId 2 response missing");
  for (const response of [response1, response2]) {
    if (!response.success || !response.versionOne || !response.hasSnapshots
        || response.sessionNonce !== expected.secondInventorySessionNonce
        || response.sessionNonce === expected.firstInventorySessionNonce) {
      fail("fresh_response_mismatch", "fresh inventory snapshot response is not authoritative/new", response);
    }
  }
  const tuningEntry = requireOne(secondRecords.map(parsePanelMessage).filter(Boolean).filter((entry) => (
    entry.message.domain === "equipment_tuning" && entry.message.cmd === "snapshot"
  )), "fresh_tuning_snapshot_count", "fresh tuning snapshot request missing");
  const tuningPayload = tuningEntry.message.payload || {};
  if (tuningEntry.message.panel !== "workbench"
      || tuningEntry.message.panelInstanceId !== expected.secondPanelInstanceId
      || tuningEntry.message.panelInstanceId === expected.firstPanelInstanceId
      || tuningPayload.v !== 1
      || tuningPayload.viewSessionId !== expected.secondViewSessionId
      || tuningPayload.viewSessionId === expected.firstViewSessionId
      || !isObject(tuningPayload.source)
      || !String(tuningPayload.source.expectedLease || "")
        .startsWith(expected.secondInventorySessionNonce + ".")) {
    fail("fresh_tuning_tuple_mismatch", "fresh panel/view/session tuple is not exact/new", {
      message: tuningEntry.message,
    });
  }
  const tuningConfirmed = requireOne(secondRecords.filter((record) => (
    record.body.startsWith("event=equipment_tuning_snapshot_confirmed ")
      && record.body.includes("panelInstanceId=" + expected.secondPanelInstanceId)
      && record.body.includes("viewSessionId=" + expected.secondViewSessionId)
  )), "fresh_tuning_confirmation_count", "fresh tuning confirmation missing");
  if (!(scopedPanel.record.lineNumber < scopedSend.record.lineNumber
      && scopedSend.record.lineNumber < response1.record.lineNumber
      && response1.record.lineNumber < tuningEntry.record.lineNumber
      && tuningEntry.record.lineNumber < tuningConfirmed.lineNumber
      && tuningConfirmed.lineNumber < fullPanel.record.lineNumber
      && fullPanel.record.lineNumber < fullSend.record.lineNumber
      && fullSend.record.lineNumber < response2.record.lineNumber)) {
    fail("fresh_snapshot_order_invalid", "fresh snapshot request/send/response order is invalid");
  }
  const secondAutoTransfers = secondRecords.map(parsePanelMessage).filter(Boolean).filter((entry) => (
    entry.message.domain === "inventory" && entry.message.cmd === "autoTransfer"
  ));
  if (secondAutoTransfers.length !== 0) {
    fail("fresh_restart_replayed_mutation", "fresh restart contains another autoTransfer");
  }
  const freshArchive = secondRecords.map((record) => parseArchive(record, clonePath))
    .filter(Boolean).find((archive) => archive.textChars === finalTextLength);
  if (!freshArchive || freshArchive.lineNumber >= scopedPanel.record.lineNumber) {
    fail("fresh_disk_archive_missing",
      "fresh restart startup archive path/length does not correlate with the final clone");
  }
  const shutdownFence = secondRecords.find((record) => record.body
    === "event=character_build_shutdown_fence result=pass reason=no_binding");
  const shutdownPanel = secondRecords.find((record) => record.body.includes("panel=shutdown"));
  const shuttingDown = secondRecords.find((record) => record.body === "[Guardian] Shutting down...");
  const stopped = secondRecords.find((record) => record.body === "[HTTP] Stopped");
  if (!shutdownFence || !shutdownPanel || !shuttingDown || !stopped
      || !(response2.record.lineNumber < shutdownFence.lineNumber
        && shutdownFence.lineNumber < shuttingDown.lineNumber
        && shuttingDown.lineNumber < stopped.lineNumber)) {
    fail("fresh_supported_shutdown_missing", "fresh run lacks supported shutdown/stop evidence");
  }
  return {
    restartBoundaryLine: restart.lineNumber,
    candidatePathLine: pathEvidence.lineNumber,
    sameCloneSolHitLine: solHit.lineNumber,
    solDerivedShadowWriteLine: sameCloneSeed.lineNumber,
    shadowPayloadParsed: false,
    resolverLine: resolver.lineNumber,
    resolverSource: "sol",
    playerSeedReplayDetected: false,
    pid: expected.secondPid,
    attemptId: attempt.attemptId,
    panelInstanceId: expected.secondPanelInstanceId,
    viewSessionId: expected.secondViewSessionId,
    tuningSnapshotRequestLine: tuningEntry.record.lineNumber,
    tuningSnapshotConfirmedLine: tuningConfirmed.lineNumber,
    inventorySessionNonce: expected.secondInventorySessionNonce,
    scopedSnapshot: {
      webCallId: scopedPanel.message.callId,
      flashCallId: scopedSend.message.callId,
      requestLine: scopedPanel.record.lineNumber,
      responseLine: response1.record.lineNumber,
    },
    fullSnapshot: {
      webCallId: fullPanel.message.callId,
      flashCallId: fullSend.message.callId,
      requestLine: fullPanel.record.lineNumber,
      responseLine: response2.record.lineNumber,
    },
    freshArchive,
    freshArchivePathAndLengthCorrelated: true,
    freshArchiveBytesParsedFromLog: false,
    shutdownFenceLine: shutdownFence.lineNumber,
    shuttingDownLine: shuttingDown.lineNumber,
    httpStoppedLine: stopped.lineNumber,
  };
}

function validateReport(report, expected) {
  const identity = report && report.runtimeIdentity;
  const preparation = report && report.savePreparation;
  const baseline = preparation && preparation.gateBaseline;
  const snapshot = report && report.snapshotGate && report.snapshotGate.evidence
    && report.snapshotGate.evidence.tuningSnapshot;
  if (!isObject(report) || report.schema !== "equipment-tuning.unattended-run.v1"
      || report.status !== "snapshot_gate_reached" || report.slot !== SLOT
      || report.seedSlot !== "crazyflasher7_saves2"
      || !isObject(identity) || identity.verified !== true
      || identity.runtimeMode !== "isolated_candidate"
      || identity.pid !== expected.firstPid
      || String(identity.buildIdentity).toUpperCase() !== expected.buildIdentity
      || String(identity.payloadClosure).toUpperCase() !== expected.payloadClosure
      || String(identity.coreSha256).toUpperCase() !== expected.coreDllSha256
      || !isObject(preparation)
      || preparation.targetSlot !== SLOT
      || preparation.seedSlot !== "crazyflasher7_saves2"
      || preparation.seedSource !== "saves/crazyflasher7_saves2.json"
      || preparation.targetJson !== "saves/" + SLOT + ".json"
      || preparation.wroteSeed !== true
      || String(preparation.seedSha256).toUpperCase() !== expected.seedSha256
      || String(preparation.seededTargetSha256).toUpperCase() !== expected.seededTargetSha256
      || String(preparation.targetSha256).toUpperCase() !== expected.seededTargetSha256
      || preparation.semanticContract !== "startup_normalization.v1"
      || String(preparation.semanticSha256).toUpperCase() !== expected.semanticSha256
      || !isObject(baseline)
      || String(baseline.sha256).toUpperCase() !== expected.gateBaselineSha256
      || baseline.semanticContract !== preparation.semanticContract
      || String(baseline.semanticSha256).toUpperCase() !== expected.semanticSha256
      || baseline.changedFromSeed !== true
      || baseline.regularFileVerified !== true
      || baseline.realPathBound !== true
      || baseline.attemptId !== expected.firstAttemptId
      || !isObject(snapshot)
      || snapshot.panelInstanceId !== expected.firstPanelInstanceId
      || snapshot.viewSessionId !== expected.firstViewSessionId) {
    fail("opener_report_tuple_mismatch", "opener report does not bind the frozen A2 tuple");
  }
  return { identity, preparation, baseline, snapshot };
}

function verifyRuntime(root, report, expected) {
  const candidateRoot = path.dirname(path.dirname(report.runtimeIdentity.processPath));
  const candidateBase = path.join(root, "tmp", "runtime-candidates", "v2");
  if (!samePath(path.dirname(candidateRoot), candidateBase)
      || path.basename(candidateRoot) !== expected.candidateDirectory) {
    fail("candidate_root_mismatch", "report process path is not the exact isolated candidate", {
      candidateRoot,
    });
  }
  let current;
  let formal;
  try {
    current = resolveExpectedRuntimeIdentity(root, candidateRoot);
    formal = resolveExpectedRuntimeIdentity(root, null);
    assertRuntimeIdentity({
      runtimeMode: "isolated_candidate",
      processPath: report.runtimeIdentity.processPath,
      coreSha256: expected.coreDllSha256,
      buildIdentity: expected.buildIdentity,
      payloadClosure: expected.payloadClosure,
    }, current);
  } catch (error) {
    fail("candidate_identity_mismatch", "candidate metadata/runtime bytes do not match", {
      message: error.message,
      code: error.code || null,
      details: error.details || null,
    });
  }
  const exeSha = sha256(readRegularFile(current.processPath, "candidate Core EXE"));
  if (exeSha !== expected.coreExeSha256) {
    fail("candidate_core_exe_mismatch", "candidate Core EXE SHA-256 changed", {
      expected: expected.coreExeSha256,
      actual: exeSha,
    });
  }
  if (formal.buildIdentity === current.buildIdentity
      && formal.payloadClosure === current.payloadClosure
      && samePath(formal.processPath, current.processPath)) {
    fail("candidate_not_isolated", "candidate path was confused with formal runtime");
  }
  return {
    runtimeMode: current.runtimeMode,
    candidateRoot: relativeTo(root, candidateRoot),
    processPath: relativeTo(root, current.processPath),
    coreDllSha256: current.coreSha256,
    coreExeSha256: exeSha,
    buildIdentity: current.buildIdentity,
    payloadClosure: current.payloadClosure,
    formalRuntimeIdentity: publicRuntimeIdentity(formal),
    notDeployed: true,
  };
}

function resolveArtifactPaths(root, reportPath, report) {
  const logPath = path.join(root, "logs", "launcher.log");
  const seedPath = path.resolve(root, report.savePreparation.seedSource);
  const clonePath = path.resolve(root, report.savePreparation.targetJson);
  if (!samePath(logPath, path.join(root, "logs", "launcher.log"))
      || !samePath(seedPath, path.join(root, "saves", "crazyflasher7_saves2.json"))
      || !samePath(clonePath, path.join(root, "saves", SLOT + ".json"))) {
    fail("artifact_path_mismatch", "report seed/clone paths are not canonical");
  }
  return { reportPath, logPath, seedPath, clonePath };
}

function verifyBundle(config) {
  const root = config.root;
  const expected = config.expected;
  const reportRead = readJson(config.reportPath, "opener report");
  const report = reportRead.data;
  if (config.strictOpener) {
    previewGate.validateOpenReport(report);
    commitGate.validateClonePreparationContract(report);
  }
  const reportTuple = validateReport(report, expected);
  const paths = resolveArtifactPaths(root, config.reportPath, report);
  const runtime = verifyRuntime(root, report, expected);
  const seedRead = readJson(paths.seedPath, "frozen player seed");
  const cloneRead = readJson(paths.clonePath, "final agent clone");
  const seedHash = sha256(seedRead.raw);
  const cloneHash = sha256(cloneRead.raw);
  if (seedHash !== expected.seedSha256
      || seedHash !== String(report.savePreparation.seedSha256).toUpperCase()) {
    fail("seed_sha_mismatch", "current seed no longer matches the opener-frozen seed", {
      expected: expected.seedSha256,
      actual: seedHash,
    });
  }
  if (cloneHash !== expected.finalCloneSha256
      || String(cloneRead.data.lastSaved || "") !== expected.finalLastSaved) {
    fail("final_clone_identity_mismatch", "final clone bytes/lastSaved changed", {
      expectedSha256: expected.finalCloneSha256,
      actualSha256: cloneHash,
      expectedLastSaved: expected.finalLastSaved,
      actualLastSaved: cloneRead.data.lastSaved,
    });
  }
  const inventoryDelta = validateSeedAndFinal(seedRead.data, cloneRead.data);
  const records = readLogRecords(paths.logPath);
  const mutation = validateMutationLog(records, report, expected);
  const persistence = validateSafeSaveAndFirstShutdown(records, mutation, paths.clonePath);
  const restart = validateFreshRestart(
    records,
    report,
    mutation,
    persistence,
    paths.clonePath,
    cloneRead.raw.toString("utf8").length,
    expected
  );
  return {
    schema: "equipment-tuning.inventory-mutation-readonly-receipt.v1",
    gate: GATE,
    status: "e2e_verified",
    verifiedAt: new Date().toISOString(),
    evidenceMode: "post_hoc_read_only_artifact_verification",
    artifacts: {
      report: relativeTo(root, paths.reportPath),
      launcherLog: relativeTo(root, paths.logPath),
      seed: { path: relativeTo(root, paths.seedPath), sha256: seedHash },
      clone: {
        path: relativeTo(root, paths.clonePath),
        sha256: cloneHash,
        textChars: cloneRead.raw.toString("utf8").length,
        lastSaved: cloneRead.data.lastSaved,
      },
    },
    opener: {
      pid: expected.firstPid,
      attemptId: expected.firstAttemptId,
      panelInstanceId: reportTuple.snapshot.panelInstanceId,
      viewSessionId: reportTuple.snapshot.viewSessionId,
      gateBaselineSha256: reportTuple.baseline.sha256,
    },
    preMutationAuthority: {
      seedSource: reportTuple.preparation.seedSource,
      seedSha256: seedHash,
      seedFileReadAndInventoryCoordinatesVerified: true,
      seededTargetSha256: reportTuple.preparation.seededTargetSha256,
      semanticContract: reportTuple.preparation.semanticContract,
      semanticSha256: reportTuple.preparation.semanticSha256,
      gateBaselineSha256: reportTuple.baseline.sha256,
      gateBaselineSemanticSha256: reportTuple.baseline.semanticSha256,
      startupNormalizationPreservedSemanticState: true,
      shadowPayloadParsedFromLauncherLog: false,
      note: "初始物品坐标来自报告绑定的种子文件及其独立 SHA/内容复算；截断的 Shadow 日志只证明保存动作，不证明 payload 内容。",
    },
    runtime,
    mutation: Object.assign({}, mutation, {
      source: SOURCE,
      destination: DESTINATION,
      item: ITEM,
      inventoryDelta,
      destinationProof:
        "mergeThenEmpty + no merge candidate + seed first empty=9 + final same record at 战备箱:9",
      destinationSlotMachineInferredFromPolicySeedAndDiskDelta: true,
      destinationSlotParsedFromTruncatedHostResponse: false,
    }),
    persistence,
    restart,
    shutdown: {
      safeSaveTelemetryVerified: true,
      safeExitUiJourneyVerified: false,
      processExitMechanism: "supported agent_control shutdown",
      shutdownControlResponseArtifactMachineVerified: false,
      shutdownFenceAndStoppedLogsVerified: true,
      note: "UI 退出游戏只触发安全存档/回地图；进程退出由 supported agent_control shutdown 完成。",
    },
    scope: {
      cloneOnlyMutationVerified: true,
      playerSeedReadOnly: true,
      playerSaveWritten: false,
      syntheticDomActivationDeclared: true,
      syntheticDomEventIsTrusted: false,
      syntheticDomTranscriptArtifactMachineVerified: false,
      productionDomActivationMachineVerified: false,
      productionWebMessageToInventoryTaskToAs2MutationVerified: true,
      freshAuthoritativeInventorySnapshotVerified: true,
      freshSnapshotPayloadItemsParsedFromTruncatedLog: false,
      freshDiskReadbackVerified: true,
      physicalPointerKeyboardHitTestingVerified: false,
      agentRuntimeInputVerified: false,
      a4A5InteractionCoverageVerified: false,
      safeExitUiJourneyVerified: false,
      promotionVerified: false,
      runtimeMode: "isolated_candidate",
      deploymentStatus: "NOT_DEPLOYED",
    },
  };
}

function writeRuntimeFixture(root, candidateDirectory, identity, closure, dllBytes, exeBytes) {
  const candidateRoot = path.join(root, "tmp", "runtime-candidates", "v2", candidateDirectory);
  const runtime = path.join(candidateRoot, "runtime");
  fs.mkdirSync(runtime, { recursive: true });
  const dllName = "CRAZYFLASHER7MercenaryEmpire.Core.dll";
  const exeName = "CRAZYFLASHER7MercenaryEmpire.Core.exe";
  fs.writeFileSync(path.join(runtime, dllName), dllBytes);
  fs.writeFileSync(path.join(runtime, exeName), exeBytes);
  fs.writeFileSync(path.join(runtime, "cf7-runtime-manifest.tsv"), [
    "cf7-runtime-manifest-v2",
    "buildIdentityHash\t" + identity,
    "payloadClosureHash\t" + closure,
    "file\truntime/" + dllName + "\t" + dllBytes.length + "\t" + sha256(dllBytes),
    "",
  ].join("\n"));
  fs.writeFileSync(path.join(candidateRoot, "runtime-build-metadata.v2.json"), JSON.stringify({
    schema: "cf7-runtime-candidate-metadata.v2",
    buildIdentityHash: identity,
    payloadClosureHash: closure,
  }));
  return { candidateRoot, processPath: path.join(runtime, exeName) };
}

function writeFormalFixture(root) {
  const runtime = path.join(root, "runtime");
  fs.mkdirSync(runtime, { recursive: true });
  const dll = Buffer.from("formal-dll");
  const exe = Buffer.from("formal-exe");
  const identity = "A".repeat(64);
  const closure = "B".repeat(64);
  const dllName = "CRAZYFLASHER7MercenaryEmpire.Core.dll";
  const exeName = "CRAZYFLASHER7MercenaryEmpire.Core.exe";
  fs.writeFileSync(path.join(runtime, dllName), dll);
  fs.writeFileSync(path.join(runtime, exeName), exe);
  fs.writeFileSync(path.join(runtime, "cf7-runtime-manifest.tsv"), [
    "cf7-runtime-manifest-v2",
    "buildIdentityHash\t" + identity,
    "payloadClosureHash\t" + closure,
    "file\truntime/" + dllName + "\t" + dll.length + "\t" + sha256(dll),
    "",
  ].join("\n"));
}

function fixtureReport(expected, processPath, seedSha, baselineSha) {
  return {
    schema: "equipment-tuning.unattended-run.v1",
    status: "snapshot_gate_reached",
    slot: SLOT,
    seedSlot: "crazyflasher7_saves2",
    runtimeIdentity: {
      verified: true,
      runtimeMode: "isolated_candidate",
      processPath,
      coreSha256: expected.coreDllSha256,
      buildIdentity: expected.buildIdentity,
      payloadClosure: expected.payloadClosure,
      pid: expected.firstPid,
    },
    savePreparation: {
      targetSlot: SLOT,
      seedSlot: "crazyflasher7_saves2",
      seedSource: "saves/crazyflasher7_saves2.json",
      targetJson: "saves/" + SLOT + ".json",
      seedSha256: seedSha,
      wroteSeed: true,
      seededTargetSha256: expected.seededTargetSha256,
      targetSha256: expected.seededTargetSha256,
      semanticContract: "startup_normalization.v1",
      semanticSha256: expected.semanticSha256,
      gateBaseline: {
        sha256: baselineSha,
        semanticContract: "startup_normalization.v1",
        semanticSha256: expected.semanticSha256,
        changedFromSeed: true,
        regularFileVerified: true,
        realPathBound: true,
        attemptId: expected.firstAttemptId,
      },
    },
    snapshotGate: { evidence: {
      activeWorkbench: { panelInstanceId: expected.firstPanelInstanceId },
      tuningSnapshot: {
        panelInstanceId: expected.firstPanelInstanceId,
        viewSessionId: expected.firstViewSessionId,
      },
    } },
  };
}

function fixtureLog(expected, processPath, clonePath, finalChars) {
  function panel(message) { return "[Panel] HandlePanelMessage: " + JSON.stringify(message); }
  const scoped = [
    { containerId: "背包", offset: 0, limit: 50, filterKey: "all", scope: "equipment" },
    { containerId: "战备箱", offset: 0, limit: 40, filterKey: "all" },
  ];
  const full = [
    { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
    { containerId: "战备箱", offset: 0, limit: 40, filterKey: "all" },
  ];
  const source = { containerId: "背包", slot: 0,
    expectedLease: expected.firstInventorySessionNonce + ".67" };
  return [
    panel({ type: "panel", domain: "inventory", panel: "workbench",
      panelInstanceId: expected.firstPanelInstanceId, cmd: "autoTransfer",
      callId: expected.mutationWebCallId,
      payload: { v: 1, source, targetContainerId: "战备箱",
        policy: "mergeThenEmpty", windows: full } }),
    "[Panel] Routing domain=inventory cmd=autoTransfer to InventoryTask, _inventoryTask=ok",
    "[InventoryTask] -> Flash: " + JSON.stringify({ task: "cmd",
      action: "inventoryAutoTransfer", callId: 3, v: 1, source,
      targetContainerId: "战备箱", policy: "mergeThenEmpty", windows: full }),
    '[XmlSocket:JSON] (len=60000) {"callId":3,"task":"inventory_response","success":true,"v":1,"operation":"move","policy":"mergeThenEmpty","destination":...',
    '[XmlSocket:JSON] (len=23410) {"callId":4,"payload":{"op":"shadow","slot":"'
      + SLOT + '","data":"{...',
    "[Frame:UI] sample count=1 sv:1|sv:2",
    "[ArchiveTask] Shadow saved: " + SLOT + " (100 chars) path=" + clonePath,
    "event=character_build_shutdown_fence result=pass reason=no_binding",
    "[Guardian] Shutting down...",
    "[HTTP] Stopped",
    "════════ 2026-08-02 21:18:12 ════════",
    "[DPI] Compatibility override: source=none path=" + processPath + " appOverride=False",
    "[SolFileLocator] hit x: C:\\fixture\\" + SLOT + ".sol",
    "[ArchiveTask] seed shadow saved: slot=" + SLOT + " path=" + clonePath,
    "[SolResolver] snapshot source=sol slot=" + SLOT + " seedAuthority=True target=" + clonePath,
    "[Prewarm] triggered attemptId=" + expected.secondAttemptId,
    '[XmlSocket:JSON] {"payload":{"loaded":true,"savePath":"' + SLOT
      + '","attemptId":"' + expected.secondAttemptId
      + '","source":"launcher_snapshot:sol"},"task":"agent_runtime_status"}',
    "[FocusRestore] pid=" + expected.secondPid
      + ' class=x title="CF7:FlashNight — 隔离候选 / 未部署"',
    "[ArchiveTask] Shadow saved: " + SLOT + " (" + finalChars + " chars) path=" + clonePath,
    panel({ type: "panel", domain: "inventory", panel: "workbench",
      panelInstanceId: expected.secondPanelInstanceId, cmd: "snapshot", callId: "fresh.1",
      payload: { v: 1, requests: scoped } }),
    "[InventoryTask] -> Flash: " + JSON.stringify({ task: "cmd", action: "inventorySnapshot",
      callId: 1, v: 1, requests: scoped }),
    '[XmlSocket:JSON] (len=10) {"callId":1,"task":"inventory_response","success":true,"v":1,"sessionNonce":"'
      + expected.secondInventorySessionNonce + '","snapshots":[...',
    panel({ type: "panel", domain: "equipment_tuning", panel: "workbench",
      panelInstanceId: expected.secondPanelInstanceId, cmd: "snapshot", callId: "fresh.tune",
      payload: { v: 1, viewSessionId: expected.secondViewSessionId,
        source: { sourceKind: "inventory", containerId: "背包", slot: 21,
          expectedLease: expected.secondInventorySessionNonce + ".1" } } }),
    "event=equipment_tuning_snapshot_confirmed callId=fresh.tune panelInstanceId="
      + expected.secondPanelInstanceId + " viewSessionId=" + expected.secondViewSessionId,
    panel({ type: "panel", domain: "inventory", panel: "workbench",
      panelInstanceId: expected.secondPanelInstanceId, cmd: "snapshot", callId: "fresh.2",
      payload: { v: 1, requests: full } }),
    "[InventoryTask] -> Flash: " + JSON.stringify({ task: "cmd", action: "inventorySnapshot",
      callId: 2, v: 1, requests: full }),
    '[XmlSocket:JSON] (len=10) {"callId":2,"task":"inventory_response","success":true,"v":1,"sessionNonce":"'
      + expected.secondInventorySessionNonce + '","snapshots":[...',
    "event=character_build_shutdown_fence result=pass reason=no_binding",
    "[IdleProbe] done mode=full panel=shutdown total=1ms",
    "[Guardian] Shutting down...",
    "[HTTP] Stopped",
    "",
  ].join("\n");
}

function expectFailure(label, callback, expectedCode, counters) {
  let caught = null;
  try { callback(); } catch (error) { caught = error; }
  if (!caught || caught.code !== expectedCode) {
    throw new Error(label + " expected " + expectedCode + ", got "
      + (caught ? caught.code + ": " + caught.message : "success"));
  }
  counters.negative += 1;
}

function runOfflineChecks() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-inventory-mutation-check-"));
  const counters = { positive: 0, negative: 0 };
  try {
    writeFormalFixture(tempRoot);
    const dll = Buffer.from("candidate-dll");
    const exe = Buffer.from("candidate-exe");
    const fixtureExpected = Object.assign({}, EXPECTED, {
      candidateDirectory: "c-fixture",
      buildIdentity: "C".repeat(64),
      payloadClosure: "D".repeat(64),
      coreDllSha256: sha256(dll),
      coreExeSha256: sha256(exe),
      seedSha256: "",
      seededTargetSha256: "F".repeat(64),
      semanticSha256: "9".repeat(64),
      gateBaselineSha256: "E".repeat(64),
      finalCloneSha256: "",
      finalLastSaved: "2026-08-02 21:18:49",
    });
    const runtime = writeRuntimeFixture(tempRoot, fixtureExpected.candidateDirectory,
      fixtureExpected.buildIdentity, fixtureExpected.payloadClosure, dll, exe);
    const saves = path.join(tempRoot, "saves");
    const logs = path.join(tempRoot, "logs");
    const reports = path.join(tempRoot, "tmp", "equipment-tuning", "unattended", "fixture");
    fs.mkdirSync(saves, { recursive: true });
    fs.mkdirSync(logs, { recursive: true });
    fs.mkdirSync(reports, { recursive: true });
    const seed = { inventory: { 背包: { "0": { name: ITEM.name, value: ITEM.quantity,
      lastUpdate: 123 } }, 战备箱: {} }, lastSaved: "before" };
    for (let slot = 0; slot < 9; slot += 1) {
      seed.inventory.战备箱[String(slot)] = { name: "fixture-" + slot, value: 1,
        lastUpdate: slot };
    }
    const final = JSON.parse(JSON.stringify(seed));
    delete final.inventory.背包["0"];
    final.inventory.战备箱["9"] = { name: ITEM.name, value: ITEM.quantity, lastUpdate: 123 };
    final.lastSaved = fixtureExpected.finalLastSaved;
    const seedText = JSON.stringify(seed);
    const finalText = JSON.stringify(final);
    fixtureExpected.seedSha256 = sha256(Buffer.from(seedText));
    fixtureExpected.finalCloneSha256 = sha256(Buffer.from(finalText));
    const seedPath = path.join(saves, "crazyflasher7_saves2.json");
    const clonePath = path.join(saves, SLOT + ".json");
    const reportPath = path.join(reports, "run-report.json");
    const logPath = path.join(logs, "launcher.log");
    fs.writeFileSync(seedPath, seedText);
    fs.writeFileSync(clonePath, finalText);
    fs.writeFileSync(reportPath, JSON.stringify(fixtureReport(fixtureExpected,
      runtime.processPath, fixtureExpected.seedSha256, fixtureExpected.gateBaselineSha256)));
    const goodLog = fixtureLog(fixtureExpected, runtime.processPath, clonePath, finalText.length);
    fs.writeFileSync(logPath, goodLog);
    const config = { root: tempRoot, reportPath, expected: fixtureExpected, strictOpener: false };
    const receipt = verifyBundle(config);
    if (receipt.status !== "e2e_verified" || receipt.scope.physicalPointerKeyboardHitTestingVerified
        || receipt.runtime.notDeployed !== true) {
      throw new Error("positive fixture returned an invalid receipt");
    }
    counters.positive += 1;

    const mutations = [
      ["cross panel", /panelInstanceId":"[^"]+"/, 'panelInstanceId":"panel_attacker"',
        "mutation_panel_tuple_mismatch"],
      ["wrong source", /"slot":0/, '"slot":7', "mutation_panel_tuple_mismatch"],
      ["missing move success", '"operation":"move"', '"operation":"merge"',
        "mutation_response_mismatch"],
      ["replayed mutation", "[Frame:UI] sample count=1", goodLog.split("\n")[0]
        + "\n[Frame:UI] sample count=1", "mutation_panel_request_count"],
      ["same session restart", fixtureExpected.secondInventorySessionNonce,
        fixtureExpected.firstInventorySessionNonce, "fresh_response_mismatch"],
      ["fresh replay", "event=character_build_shutdown_fence result=pass reason=no_binding\n[IdleProbe]",
        goodLog.split("\n")[0] + "\nevent=character_build_shutdown_fence result=pass reason=no_binding\n[IdleProbe]",
        "mutation_panel_request_count"],
      ["missing safe telemetry", "[Frame:UI] sample count=1 sv:1|sv:2",
        "[Frame:UI] sample count=1", "safe_save_telemetry_missing"],
      ["wrong candidate path", runtime.processPath, path.join(tempRoot, "attacker.exe"),
        "fresh_candidate_path_missing"],
    ];
    for (const [label, needle, replacement, code] of mutations) {
      const changed = needle instanceof RegExp
        ? goodLog.replace(needle, replacement) : goodLog.replace(needle, replacement);
      fs.writeFileSync(logPath, changed);
      expectFailure(label, () => verifyBundle(config), code, counters);
    }
    fs.writeFileSync(logPath, goodLog);
    const wrongFinal = JSON.parse(finalText);
    wrongFinal.inventory.战备箱["9"].value = 86;
    fs.writeFileSync(clonePath, JSON.stringify(wrongFinal));
    expectFailure("wrong final clone", () => verifyBundle(config),
      "final_clone_identity_mismatch", counters);
    fs.writeFileSync(clonePath, finalText);
    const wrongReport = fixtureReport(fixtureExpected, runtime.processPath,
      fixtureExpected.seedSha256, fixtureExpected.gateBaselineSha256);
    wrongReport.runtimeIdentity.coreSha256 = "0".repeat(64);
    fs.writeFileSync(reportPath, JSON.stringify(wrongReport));
    expectFailure("wrong report DLL hash", () => verifyBundle(config),
      "opener_report_tuple_mismatch", counters);
    counters.positive += 1;
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
  console.log(JSON.stringify({
    ok: true,
    gate: GATE,
    positive: counters.positive,
    negative: counters.negative,
    total: counters.positive + counters.negative,
    scope: "temporary_offline_fixtures_only_no_workspace_save_or_runtime_access",
  }, null, 2));
  return counters;
}

function resolveProductionReport(value) {
  const filePath = previewGate.resolveOpenReport(value);
  if (!samePath(filePath, DEFAULT_REPORT)) {
    fail("report_not_frozen_a2_artifact", "only the frozen 20260802T130205 report is accepted", {
      filePath,
    });
  }
  return filePath;
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  if (args.check) return runOfflineChecks();
  const reportPath = resolveProductionReport(args.openReport);
  const receipt = verifyBundle({
    root: ROOT,
    reportPath,
    expected: EXPECTED,
    strictOpener: true,
  });
  console.log(JSON.stringify(receipt, null, 2));
  return receipt;
}

module.exports = {
  EXPECTED,
  GATE,
  parseArgs,
  parseInventoryResponse,
  runOfflineChecks,
  validateMutationLog,
  validateSeedAndFinal,
  verifyBundle,
};

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    const code = error && error.code ? error.code : "unexpected_error";
    console.error(code + ": " + error.message);
    if (error && error.details) console.error(JSON.stringify(error.details));
    process.exit(error && /argument/.test(code) ? 2 : 1);
  }
}
