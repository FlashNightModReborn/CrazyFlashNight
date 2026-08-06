#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  buildRawBundleManifest,
  canonicalJson,
  classifyCatalogDelivery,
  chooseCatalogSelection,
  deepClone,
  redactOpaqueTokens,
  sealEvents,
  sha256Bytes,
  sha256Text,
  PROVIDER_RECEIPT_SCHEMA,
  PROVIDER_EVENT_SCHEMA,
  TOKEN_KEYS,
  tokenRef,
} = require("./common");
const LauncherObservation = require("../lib/launcher-observation");
const ProductionClosure = require("./production-closure");
const { authoritativeIconNamesForLifecycle: verifierIconNames,
  receiptStateForEvidenceMode,
  verifyBundle: verifyBundleStrict } = require("./evidence-verifier");
const { ControlChannel, providerEventSha256, validateAck, validateProviderReceipt,
  validateRequest, writeAck } = require("./control-channel");
const { PANEL_ONE, PANEL_TWO, buildValidBundle } = require("./fixtures/valid-bundle");
const { withWebViewDebugEnvironment } = require("./generic-opener");
const { authoritativeIconNamesForLifecycle: observerIconNames,
  browserInjectionSource } = require("./cdp-passive-observer");
const { createSolidPngForFixture, decodePng } = require("./png-contract");
const ProductionPanelRuntime = require("../../../launcher/web/modules/panel-runtime.js");
const ProductionInventoryRuntime = require("../../../launcher/web/modules/inventory-runtime.js");

let passed = 0;
let browserGateReceipt = null;
const PRODUCTION_ROOT = path.resolve(__dirname, "..", "..", "..");
const ITEMUTIL_RELATIVE = path.join("scripts", "类定义", "org", "flashNight", "arki",
  "item", "ItemUtil.as");
const ARRAY_INVENTORY_RELATIVE = path.join("scripts", "类定义", "org", "flashNight",
  "arki", "item", "itemCollection", "ArrayInventory.as");

function withTemporaryDeliverySources(body) {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-kshop-itemutil-"));
  try {
    [ITEMUTIL_RELATIVE, ARRAY_INVENTORY_RELATIVE].forEach((relativePath) => {
      const target = path.join(temporaryRoot, relativePath);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(path.join(PRODUCTION_ROOT, relativePath), target);
    });
    const itemUtilPath = path.join(temporaryRoot, ITEMUTIL_RELATIVE);
    const arrayInventoryPath = path.join(temporaryRoot, ARRAY_INVENTORY_RELATIVE);
    return body({ temporaryRoot, itemUtilPath, arrayInventoryPath,
      itemUtil: fs.readFileSync(itemUtilPath, "utf8"),
      arrayInventory: fs.readFileSync(arrayInventoryPath, "utf8") });
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

function assertDeliveryAnchorReject(root, acceptedCodes) {
  const codes = acceptedCodes || ["production_itemutil_delivery_semantic_anchor_mismatch"];
  assert.throws(() => ProductionClosure.captureItemUtilDeliverySourceContract(root),
    (error) => error && codes.includes(error.code));
}

function verifyBundle(bundle) {
  return verifyBundleStrict(bundle, { deferModuleJournalRuntime: true });
}

function test(name, body) {
  try {
    body();
    passed += 1;
  } catch (error) {
    error.message = name + ": " + error.message;
    throw error;
  }
}

function assertJavaScriptParses(source) {
  assert.doesNotThrow(() => Function(String(source)));
}

function rawEvents(bundle) {
  return bundle.transcript.events.map((event) => {
    const copy = deepClone(event);
    delete copy.schema;
    delete copy.sequence;
    delete copy.prevHash;
    delete copy.eventHash;
    return copy;
  });
}

function refreshProviderOperationEvents(provider) {
  const events = provider.operationEvents;
  assert.ok(Array.isArray(events), "provider operation events are missing");
  const input = provider.inputObservation;
  const action = events.find((entry) => entry.kind === "action_completed");
  events[0].occurredAt = provider.startedAt;
  events[0].evidence = { kind: "provider_operation_started" };
  if (input) {
    action.occurredAt = input.observedAt;
    action.evidence = { kind: "trusted_dom_input", observerId: input.eventRef.observerId,
      sequence: input.eventRef.sequence, eventSha256: input.eventRef.eventSha256 };
  } else {
    action.evidence = { kind: "provider_tool_result_action", issuer: provider.issuer,
      toolResultSource: provider.toolResultSource, operationId: provider.operationId,
      action: provider.action };
  }
  if (provider.capture) {
    const captureEvent = events.find((entry) => entry.kind === "capture_created");
    captureEvent.occurredAt = provider.capture.capturedAt;
    captureEvent.evidence = { kind: "provider_capture",
      relativePath: provider.capture.relativePath, sha256: provider.capture.sha256,
      bytes: provider.capture.bytes };
  }
  const complete = events.at(-1);
  complete.occurredAt = provider.completedAt;
  complete.evidence = { kind: "provider_operation_completed", result: provider.result };
  events.forEach((entry) => { entry.eventSha256 = providerEventSha256(entry); });
  if (provider.capture) {
    const captureEvent = events.find((entry) => entry.kind === "capture_created");
    provider.capture.eventRef = { eventId: captureEvent.eventId,
      eventSha256: captureEvent.eventSha256 };
  }
}

function reseal(bundle, mutate) {
  const events = rawEvents(bundle);
  mutate(events);
  events.forEach((event) => {
    event.observerId = bundle.transcript.observerId;
    if (!event.message) return;
    if (!event.authorityValueLengths) event.authorityValueLengths = {};
    const used = Object.create(null);
    function restore(value) {
      if (Array.isArray(value)) return value.map(restore);
      if (!value || typeof value !== "object") return value;
      const output = {};
      Object.keys(value).forEach((key) => {
        const publicKey = "field:" + key;
        if (TOKEN_KEYS.has(key) && !event.authorityValueLengths[publicKey]) {
          event.authorityValueLengths[publicKey] = [String(value[key] || "").length];
        }
        if (Object.prototype.hasOwnProperty.call(event.authorityValueLengths, publicKey)) {
          const index = used[publicKey] || 0;
          const length = event.authorityValueLengths[publicKey][index];
          used[publicKey] = index + 1;
          output[key] = "x".repeat(length || 1);
        } else output[key] = restore(value[key]);
      });
      return output;
    }
    const restored = restore(event.message);
    Object.keys(event.authorityValueLengths).forEach((publicKey) => {
      const count = used[publicKey] || 0;
      if (count === 0) delete event.authorityValueLengths[publicKey];
      else event.authorityValueLengths[publicKey]
        = event.authorityValueLengths[publicKey].slice(0, count);
    });
    event.wirePayloadLength = JSON.stringify(restored).length;
  });
  const sealed = sealEvents(events);
  bundle.transcript.events = sealed.events;
  bundle.transcript.eventCount = sealed.eventCount;
  bundle.transcript.chainHead = sealed.chainHead;
  const domEvents = sealed.events.filter((event) => event.kind === "dom_input");
  const domSteps = ["add_selected_item", "open_checkout", "commit_checkout", "close_kshop",
    "restart_readback_close_kshop"];
  domSteps.forEach((step, index) => {
    const event = domEvents[index];
    const provider = bundle.controlProviderReceipts.find((entry) => entry.step === step);
    const request = bundle.controlRequests.find((entry) => entry.step === step);
    const ack = request && bundle.controlAcks.find((entry) => entry.requestId === request.requestId);
    if (!event || !provider || !ack || !event.target) return;
    provider.inputObservation = { eventRef: { observerId: bundle.transcript.observerId,
      sequence: event.sequence, eventSha256: event.eventHash }, observedAt: event.observedAt,
    eventType: event.eventType, isTrusted: event.isTrusted, selector: event.target.selector,
    tagName: event.target.tagName, visible: event.target.visible, enabled: event.target.enabled,
    viewport: deepClone(event.target.viewport), rect: deepClone(event.target.rect),
    clientPoint: deepClone(event.target.clientPoint), hitTargetMatches: event.target.hitTargetMatches,
    key: event.key, button: event.button, repeat: event.repeat };
    refreshProviderOperationEvents(provider);
    delete provider.receiptSha256;
    provider.receiptSha256 = sha256Text(canonicalJson(provider));
    const providerPath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "control", "provider-receipts", request.requestId + ".json");
    const providerBytes = Buffer.from(JSON.stringify(provider, null, 2) + "\n", "utf8");
    fs.writeFileSync(providerPath, providerBytes);
    ack.providerReceiptRef.sha256 = sha256Bytes(providerBytes);
    ack.providerReceiptRef.bytes = providerBytes.length;
    persistAck(bundle, ack);
    const binding = bundle.controlBindings.find((entry) => entry.requestId === request.requestId);
    binding.ackSha256 = sha256Text(canonicalJson(ack));
  });
}

function resealHost(bundle, label, mutate) {
  const lifecycle = bundle.hostLog.lifecycles.find((entry) => entry.label === label);
  assert.ok(lifecycle, "missing Host lifecycle " + label);
  mutate(lifecycle.terminalSnapshot.records);
  const snapshot = lifecycle.terminalSnapshot;
  snapshot.records.forEach((record, index) => { record.lineNumber = index + 1; });
  snapshot.total = snapshot.records.length;
  snapshot.oldestLineNumber = snapshot.records.length ? snapshot.records[0].lineNumber : 1;
  const payload = deepClone(snapshot);
  delete payload.capturedAt;
  delete payload.tailSha256;
  snapshot.tailSha256 = sha256Text(canonicalJson(payload));
}

function hostBody(line) {
  return String(line || "").replace(/^\d{2}:\d{2}:\d{2}\.\d{3} /, "");
}

function timestampLike(record, body) {
  const match = /^(\d{2}:\d{2}:\d{2}\.\d{3} )/.exec(String(record && record.line || ""));
  assert.ok(match, "fixture Host record lacks a timestamp prefix");
  return { line: match[1] + body };
}

function refreshRawManifest(bundle) {
  delete bundle.rawBundleManifest;
  bundle.rawBundleManifest = buildRawBundleManifest(bundle);
}

function refreshEvidenceSha(value, key) {
  delete value[key || "evidenceSha256"];
  value[key || "evidenceSha256"] = sha256Text(canonicalJson(value));
}

function isMessage(event, kind, cmd, panelInstanceId) {
  return event.kind === kind && event.message && event.message.cmd === cmd
    && (!panelInstanceId || event.message.panelInstanceId === panelInstanceId);
}

function expectFailure(name, mutate, expectedCodes, options) {
  test(name, () => {
    const bundle = buildValidBundle();
    let cleanup = null;
    try {
      cleanup = mutate(bundle);
      if (!options || options.refreshManifest !== false) refreshRawManifest(bundle);
      let observed = null;
      try { verifyBundle(bundle); } catch (error) { observed = error; }
      assert.ok(observed, "fixture unexpectedly verified");
      const accepted = Array.isArray(expectedCodes) ? expectedCodes : [expectedCodes];
      assert.ok(accepted.includes(observed.code),
        "expected " + accepted.join("|") + ", observed " + observed.code);
    } finally {
      if (typeof cleanup === "function") cleanup();
    }
  });
}

function findEvent(events, kind, cmd, panelInstanceId) {
  return events.find((event) => isMessage(event, kind, cmd, panelInstanceId));
}

function inventoryResponses(events, panelInstanceId) {
  return events.filter((event) => isMessage(
    event, "webview_message", "snapshot", panelInstanceId));
}

function inventoryPhaseResponses(events, phase) {
  if (phase === "restart") return inventoryResponses(events, PANEL_TWO);
  const first = inventoryResponses(events, PANEL_ONE);
  const commit = findEvent(events, "webview_message", "checkoutCommit", PANEL_ONE);
  assert.ok(commit, "fixture requires the checkoutCommit response boundary");
  const commitIndex = events.indexOf(commit);
  assert.ok(commitIndex >= 0, "fixture checkoutCommit boundary must belong to the raw event list");
  const indexed = first.map((event) => {
    const eventIndex = events.indexOf(event);
    assert.ok(eventIndex >= 0, "fixture Inventory response must belong to the raw event list");
    return {event, eventIndex};
  });
  if (phase === "initial") return indexed.filter((entry) => entry.eventIndex < commitIndex)
    .map((entry) => entry.event);
  if (phase === "post") return indexed.filter((entry) => entry.eventIndex > commitIndex)
    .map((entry) => entry.event);
  throw new Error("unknown fixture Inventory phase: " + phase);
}

function inventoryPhaseSnapshots(events, phase, containerId) {
  return inventoryPhaseResponses(events, phase).flatMap((event) => event.message.snapshots)
    .filter((snapshot) => snapshot.containerId === containerId)
    .sort((left, right) => left.offset - right.offset);
}

function runV83InventoryPhaseRegressionTests() {
  const startingPassed = passed;
  test("raw Inventory events without sequence retain exact initial and post windows", () => {
    const events = rawEvents(buildValidBundle());
    assert.ok(events.every((event) => !Object.prototype.hasOwnProperty.call(event, "sequence")));
    ["initial", "post"].forEach((phase) => {
      const responses = inventoryPhaseResponses(events, phase);
      const windows = responses.flatMap((event) => event.message.snapshots);
      assert.strictEqual(responses.length, 3, phase + " response count");
      assert.strictEqual(windows.length, 4, phase + " window count");
      assert.deepStrictEqual(inventoryPhaseSnapshots(events, phase, "背包")
        .map((snapshot) => snapshot.offset), [0], phase + " backpack windows");
      assert.deepStrictEqual(inventoryPhaseSnapshots(events, phase, "战备箱")
        .map((snapshot) => snapshot.offset), [0, 100, 200], phase + " battlebox windows");
    });
  });

  test("a malformed occupied Inventory slot reaches the verifier and is rejected", () => {
    const bundle = buildValidBundle();
    let mutationHit = false;
    reseal(bundle, (events) => {
      const snapshots = inventoryPhaseSnapshots(events, "initial", "背包");
      assert.strictEqual(snapshots.length, 1, "initial backpack window count");
      const snapshot = snapshots[0];
      assert.strictEqual(snapshot.slots.length, 50, "initial backpack slot count");
      assert.strictEqual(snapshot.slots[0].physicalSlot, 0, "mutation physical slot");
      snapshot.slots[0] = {
        physicalSlot: 0, occupied: true,
        slotLease: snapshot.slots[0].slotLease,
        item: { name: "malformed" }, confirmProjection: {},
      };
      mutationHit = snapshot.slots[0].occupied === true;
    });
    assert.strictEqual(mutationHit, true, "malformed occupied slot mutation was not applied");
    refreshRawManifest(bundle);
    let observed = null;
    try { verifyBundle(bundle); } catch (error) { observed = error; }
    assert.ok(observed, "malformed occupied slot fixture unexpectedly verified");
    assert.strictEqual(observed.code, "inventory_item_invalid");
  });
  return {passed: passed - startingPassed};
}

function inventoryPhaseSlot(events, phase, containerId, physicalSlot) {
  const snapshot = inventoryPhaseSnapshots(events, phase, containerId)
    .find((entry) => physicalSlot >= entry.offset && physicalSlot < entry.offset + entry.limit);
  assert.ok(snapshot, "fixture phase lacks physical slot " + phase + "/" + containerId
    + "/" + physicalSlot);
  const slot = snapshot.slots.find((entry) => entry.physicalSlot === physicalSlot);
  assert.ok(slot, "fixture window lacks physical slot " + physicalSlot);
  return { snapshot, slot };
}

function setPhaseFacetCount(events, phase, containerId, count) {
  const snapshots = inventoryPhaseSnapshots(events, phase, containerId);
  assert.ok(snapshots.length > 0, "fixture phase lacks " + containerId + " snapshots");
  snapshots.forEach((snapshot) => setOccupiedFacetCount(snapshot, count));
}

function setOccupiedFacetCount(snapshot, count) {
  snapshot.filterItemCount = count;
  if (count === 0) {
    snapshot.filterFacets = [];
    return;
  }
  assert.strictEqual(snapshot.filterFacets.length, 1,
    "fixture inventory snapshot must keep one root facet");
  snapshot.filterFacets[0].count = count;
}

function mirrorPostCommitInventoryToRestart(events) {
  ["背包", "战备箱"].forEach((containerId) => {
    const postSnapshots = inventoryPhaseSnapshots(events, "post", containerId);
    const restartSnapshots = inventoryPhaseSnapshots(events, "restart", containerId);
    assert.strictEqual(restartSnapshots.length, postSnapshots.length,
      "restart must expose the same complete window set as post-commit");
    postSnapshots.forEach((postSnapshot, windowIndex) => {
      const restartSnapshot = restartSnapshots[windowIndex];
      assert.strictEqual(restartSnapshot.offset, postSnapshot.offset);
      assert.strictEqual(restartSnapshot.limit, postSnapshot.limit);
      postSnapshot.slots.forEach((postSlot, slotIndex) => {
        const lease = restartSnapshot.slots[slotIndex].slotLease;
        restartSnapshot.slots[slotIndex] = deepClone(postSlot);
        restartSnapshot.slots[slotIndex].slotLease = lease;
      });
      restartSnapshot.filterFacets = deepClone(postSnapshot.filterFacets);
      restartSnapshot.filterItemCount = postSnapshot.filterItemCount;
      restartSnapshot.setFacets = deepClone(postSnapshot.setFacets);
      restartSnapshot.setFilterItemCount = postSnapshot.setFilterItemCount;
    });
  });
}

function restoreFixtureWireMessage(event) {
  const used = Object.create(null);
  function restore(value) {
    if (Array.isArray(value)) return value.map(restore);
    if (!value || typeof value !== "object") return value;
    const output = {};
    Object.keys(value).forEach((key) => {
      if (TOKEN_KEYS.has(key)) {
        const publicKey = "field:" + key;
        const index = used[publicKey] || 0;
        const length = event.authorityValueLengths[publicKey][index];
        used[publicKey] = index + 1;
        output[key] = "x".repeat(length);
      } else output[key] = restore(value[key]);
    });
    return output;
  }
  return restore(event.message);
}

function synchronizeInventorySocketLengths(bundle, lifecycle, panelInstanceId) {
  const responses = inventoryResponses(bundle.transcript.events, panelInstanceId);
  resealHost(bundle, lifecycle, (records) => {
    responses.forEach((event, index) => {
      const raw = restoreFixtureWireMessage(event);
      const business = deepClone(raw);
      ["type", "domain", "panel", "panelInstanceId", "cmd", "callId"]
        .forEach((key) => { delete business[key]; });
      const payload = Object.assign({ task: "inventory_response", callId: index + 1 }, business);
      const prefix = "[XmlSocket:JSON] task=inventory_response cmd=inventorySnapshot callId="
        + (index + 1) + " ";
      const record = records.find((entry) => hostBody(entry.line).startsWith(prefix));
      assert.ok(record, "fixture Host inventory socket summary is missing");
      record.line = record.line.replace(/len=(\d+)/,
        "len=" + JSON.stringify(payload).length);
    });
  });
}

function reindexRawResources(loaded) {
  loaded.rawResourceOccurrences.forEach((entry, index) => {
    entry.occurrence = index + 1;
    entry.resourceOccurrence = index + 1;
  });
}

function appendBoundPageResource(loaded, expected, insertIndex) {
  const page = loaded.rawResourceOccurrences.find((entry) => entry.type === "Document");
  assert.ok(page, "fixture loaded evidence lacks its Overlay document");
  const entry = { occurrence: loaded.rawResourceOccurrences.length + 1,
    frameOccurrence: 1, resourceOccurrence: loaded.rawResourceOccurrences.length + 1,
    frameId: page.frameId, frameUrl: page.frameUrl, frameOrigin: page.frameOrigin,
    url: expected.url, urlOrigin: expected.urlOrigin, type: expected.type,
    resource: { url: expected.url, type: expected.type, mimeType: expected.mimeType || "" },
    sourceMethod: "Page.getResourceContent", sourceSha256: expected.sha256,
    sourceBytes: expected.bytes, sourceError: null };
  const index = Number.isInteger(insertIndex) ? insertIndex : loaded.rawResourceOccurrences.length;
  loaded.rawResourceOccurrences.splice(index, 0, entry);
  reindexRawResources(loaded);
  return entry;
}

function relocateFixtureDelivery(events, containerIndex, physicalSlot) {
  const targetContainer = containerIndex === 0 ? "背包" : "战备箱";
  ["post", "restart"].forEach((phase) => {
    const source = inventoryPhaseSlot(events, phase, "背包", 0);
    const target = inventoryPhaseSlot(events, phase, targetContainer, physicalSlot);
    const delivered = deepClone(source.slot);
    const sourceLease = source.slot.slotLease;
    source.snapshot.slots[source.snapshot.slots.indexOf(source.slot)] = {
      physicalSlot: 0, occupied: false, slotLease: sourceLease,
    };
    delivered.physicalSlot = physicalSlot;
    target.snapshot.slots[target.snapshot.slots.indexOf(target.slot)] = delivered;
    setPhaseFacetCount(events, phase, "背包", targetContainer === "背包" ? 2 : 1);
    setPhaseFacetCount(events, phase, "战备箱", targetContainer === "战备箱" ? 3 : 2);
  });
}

function providerReceiptRecord(bundle, step) {
  const request = bundle.controlRequests.find((entry) => entry.step === step);
  const ack = bundle.controlAcks.find((entry) => entry.requestId === request.requestId);
  const receiptPath = path.resolve(bundle.root,
    bundle.runDir.replace(/\//g, path.sep), ack.providerReceiptRef.relativePath.replace(/\//g, path.sep));
  return { request, ack, receiptPath };
}

function persistAck(bundle, ack) {
  const ackPath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
    "control", "acks", ack.requestId + ".json");
  fs.writeFileSync(ackPath, JSON.stringify(ack, null, 2) + "\n", "utf8");
}

function rewriteControlExchange(bundle, step, mutate) {
  const request = bundle.controlRequests.find((entry) => entry.step === step);
  const ack = bundle.controlAcks.find((entry) => entry.requestId === request.requestId);
  const provider = bundle.controlProviderReceipts.find((entry) =>
    entry.requestId === request.requestId);
  mutate({ request, ack, provider });
  request.expiresAt = new Date(Date.parse(request.issuedAt) + 3600000).toISOString();
  const requestBytes = Buffer.from(JSON.stringify(request, null, 2) + "\n", "utf8");
  provider.requestBindingSha256 = sha256Text(canonicalJson(request));
  provider.requestArtifact = { relativePath: "control/requests/" + request.requestId + ".json",
    sha256: sha256Bytes(requestBytes), bytes: requestBytes.length };
  refreshProviderOperationEvents(provider);
  delete provider.receiptSha256;
  provider.receiptSha256 = sha256Text(canonicalJson(provider));
  const providerPath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
    "control", "provider-receipts", request.requestId + ".json");
  const providerBytes = Buffer.from(JSON.stringify(provider, null, 2) + "\n", "utf8");
  fs.writeFileSync(providerPath, providerBytes);
  ack.requestBindingSha256 = sha256Text(canonicalJson(request));
  ack.completedAt = provider.completedAt;
  ack.providerReceiptRef = { relativePath: "control/provider-receipts/"
      + request.requestId + ".json", sha256: sha256Bytes(providerBytes),
    bytes: providerBytes.length, operationId: provider.operationId };
  const requestPath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
    "control", "requests", request.requestId + ".json");
  fs.writeFileSync(requestPath, requestBytes);
  persistAck(bundle, ack);
  const binding = bundle.controlBindings.find((entry) => entry.requestId === request.requestId);
  binding.requestSha256 = sha256Text(canonicalJson(request));
  binding.ackSha256 = sha256Text(canonicalJson(ack));
  if (bundle.controlRequests.at(-1).requestId === request.requestId) {
    const currentPath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "control", "current-request.json");
    fs.writeFileSync(currentPath, JSON.stringify(request, null, 2) + "\n", "utf8");
  }
}

function hostRecordMoment(bundle, label, predicate) {
  const lifecycle = bundle.hostLog.lifecycles.find((entry) => entry.label === label);
  const matches = lifecycle.terminalSnapshot.records.filter((entry) => predicate(hostBody(entry.line)));
  assert.strictEqual(matches.length, 1, "expected one Host timeline record");
  const match = /^(\d{2}):(\d{2}):(\d{2})\.(\d{3}) /.exec(matches[0].line);
  assert.ok(match, "Host timeline record lacks a formatter timestamp");
  const snapshot = new Date(lifecycle.terminalSnapshot.capturedAt);
  let value = new Date(snapshot.getFullYear(), snapshot.getMonth(), snapshot.getDate(),
    Number(match[1]), Number(match[2]), Number(match[3]), Number(match[4])).getTime();
  if (value > snapshot.getTime() + 1000) value -= 86400000;
  return value;
}

function hostInventoryResponseMoment(bundle, label, webCallId) {
  const lifecycle = bundle.hostLog.lifecycles.find((entry) => entry.label === label);
  const bindingPrefix = "event=authority_flash_call_bound domain=inventory webCallId="
    + webCallId + " ";
  const bindings = lifecycle.terminalSnapshot.records.filter((entry) =>
    hostBody(entry.line).startsWith(bindingPrefix));
  assert.strictEqual(bindings.length, 1, "expected one Host Inventory binding record");
  const flashCallId = / flashCallId=(\d+) /.exec(hostBody(bindings[0].line));
  assert.ok(flashCallId, "Host Inventory binding lacks flashCallId");
  const responsePrefix = "[XmlSocket:JSON] task=inventory_response cmd=inventorySnapshot callId="
    + flashCallId[1] + " ";
  return hostRecordMoment(bundle, label, (body) => body.startsWith(responsePrefix));
}

function rewriteResidueObservedAt(residue, observedAt) {
  residue.observedAt = observedAt;
  refreshEvidenceSha(residue);
}

function rewriteProviderReceipt(bundle, step, mutate) {
  const { request, ack, receiptPath } = providerReceiptRecord(bundle, step);
  const original = fs.readFileSync(receiptPath);
  const receipt = JSON.parse(original.toString("utf8"));
  mutate(receipt, request, ack);
  delete receipt.receiptSha256;
  receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
  const bytes = Buffer.from(JSON.stringify(receipt, null, 2) + "\n", "utf8");
  fs.writeFileSync(receiptPath, bytes);
  ack.providerReceiptRef.sha256 = sha256Bytes(bytes);
  ack.providerReceiptRef.bytes = bytes.length;
  ack.providerReceiptRef.operationId = receipt.operationId;
  const providerIndex = bundle.controlProviderReceipts.findIndex((entry) =>
    entry.requestId === request.requestId);
  bundle.controlProviderReceipts[providerIndex] = deepClone(receipt);
  const ackPath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
    "control", "acks", request.requestId + ".json");
  fs.writeFileSync(ackPath, JSON.stringify(ack, null, 2) + "\n", "utf8");
  const binding = bundle.controlBindings.find((entry) => entry.requestId === request.requestId);
  binding.ackSha256 = sha256Text(canonicalJson(ack));
  return () => fs.writeFileSync(receiptPath, original);
}

function rewriteCandidateManifest(bundle, mutate) {
  const filePath = path.join(bundle.candidateRoot, "runtime", "cf7-runtime-manifest.tsv");
  const original = fs.readFileSync(filePath);
  const lines = original.toString("utf8").replace(/\r/g, "").split("\n");
  mutate(lines);
  fs.writeFileSync(filePath, lines.join("\n"), "utf8");
  return () => fs.writeFileSync(filePath, original);
}

function rebindFirstCandidateEnvelope(bundle) {
  const identity = bundle.runtime.first.identity;
  ["runtimeMode", "processPath", "coreSha256", "buildIdentity", "payloadClosure", "installRoot"]
    .forEach((key) => { bundle.runtime.restart.identity[key] = identity[key]; });
  [bundle.runtime.first.processContract, bundle.runtime.restart.processContract].forEach((contract) => {
    contract.processPath = path.resolve(identity.processPath);
    refreshEvidenceSha(contract, "artifactSha256");
  });
  if (bundle.authorization && bundle.authorization.launcherAgentRuntime) {
    bundle.authorization.launcherAgentRuntime.artifact = deepClone(bundle.runtime.first.processContract);
    bundle.authorization.launcherAgentRuntime.artifactSha256 = sha256Text(canonicalJson(
      bundle.authorization.launcherAgentRuntime.artifact));
  }
  bundle.candidateBeforeClone.identity = { runtimeMode: identity.runtimeMode,
    processPath: path.resolve(identity.processPath), coreSha256: String(identity.coreSha256).toUpperCase(),
    buildIdentity: String(identity.buildIdentity).toUpperCase(),
    payloadClosure: String(identity.payloadClosure).toUpperCase(),
    installRoot: path.resolve(identity.installRoot) };
  bundle.candidateBeforeClone.identitySha256 = sha256Text(canonicalJson(
    bundle.candidateBeforeClone.identity));
  bundle.productionBinding.candidateIdentitySha256 = sha256Text(canonicalJson({
    runtimeMode: identity.runtimeMode, processPath: path.resolve(identity.processPath),
    coreSha256: identity.coreSha256, buildIdentity: identity.buildIdentity,
    payloadClosure: identity.payloadClosure }));
  refreshEvidenceSha(bundle.productionBinding, "bindingSha256");
}

function refreshSafeExitEvidence(bundle) {
  const first = bundle.hostLog.lifecycles.find((entry) => entry.label === "first");
  const capturedAt = bundle.safeExitEvidence.disk.capturedAt;
  const evidence = LauncherObservation.verifyArchiveSaveEvidence({
    root: bundle.root,
    slot: bundle.slot,
    boundary: first.boundary,
    snapshot: first.terminalSnapshot,
    diskEvidence: bundle.safeExitEvidence.disk,
    requiredOrder: ["sv1", "sv2", "archive"],
  });
  evidence.disk.capturedAt = capturedAt;
  delete evidence.evidenceSha256;
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  bundle.safeExitEvidence = evidence;
}

function runAdmissionSmoke() {
  const sent = [];
  const mux = new ProductionPanelRuntime.PanelRequestMux({
    send(message) { sent.push(message); return true; },
    setTimer() { return 1; },
    clearTimer() {},
    timeoutMs: 1000,
    callPrefix: "kshop.audit",
    sessionNonce: "admission",
    createMessage(context) {
      return { type: "panel", panel: "kshop",
        panelInstanceId: context.session.panelInstanceId,
        cmd: context.entry.cmd, callId: context.entry.callId };
    },
  });
  assert.strictEqual(mux.openSession({ ownerPanel: "kshop",
    panelInstanceId: "panel_kshop_admission" }), true);
  mux.request("bulkQuery", {}, { metadata: { channel: "shop" } }, () => {});
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].cmd, "bulkQuery");
  mux.closeSession();
  assert.strictEqual(typeof buildValidBundle, "function");
  return { selfTestLoaded: true, fixtureLoaded: true, productionPanelRuntimeExecuted: true };
}

function runtimePhysicalBatches(accessibleCapacity) {
  const batches = [[
    {containerId: "背包", offset: 0, limit: 50, filterKey: "all"},
    {containerId: "战备箱", offset: 0, limit: 100, filterKey: "all"},
  ]];
  if (accessibleCapacity > 100) batches.push([
    {containerId: "战备箱", offset: 100, limit: 100, filterKey: "all"},
  ]);
  if (accessibleCapacity > 200) batches.push([
    {containerId: "战备箱", offset: 200,
      limit: accessibleCapacity - 200, filterKey: "all"},
  ]);
  return batches;
}

function runtimePhysicalSnapshot(request, accessibleCapacity, snapshotSeq) {
  const bag = request.containerId === "背包";
  const access = bag ? 50 : accessibleCapacity;
  const limit = Math.min(request.limit, Math.max(0, access - request.offset));
  const slots = Array.from({length: limit}, (_unused, index) => ({
    physicalSlot: request.offset + index,
    occupied: false,
    slotLease: "lease_" + (bag ? "bag" : "battle") + "_" + (request.offset + index),
  }));
  return {
    containerId: request.containerId,
    capacity: bag ? 50 : 400,
    accessibleCapacity: access,
    viewCapacity: access,
    filterKey: "all",
    pageSizeHint: bag ? 50 : 40,
    locked: !bag && access === 0,
    snapshotSeq,
    containerEpoch: bag ? 10 : 20,
    containerVersion: 1,
    offset: request.offset,
    limit,
    slots,
    filterFacets: [],
    filterItemCount: 0,
    setFacets: [],
    setFilterItemCount: 0,
  };
}

function exerciseProductionPhysicalSurface(accessibleCapacity, mutateResponse, ownerOptions,
  mutateRequestReturn) {
  const expectedBatches = runtimePhysicalBatches(accessibleCapacity);
  const owner = Object.assign({expectedPanel: "kshop",
    expectedPanelInstanceId: "runtime.surface.owner"}, ownerOptions || {});
  const observedPayloads = [];
  let result = null;
  let callbackCount = 0;
  const started = ProductionInventoryRuntime.readPhysicalInventorySurface(
    (cmd, payload, callback) => {
      const ordinal = observedPayloads.length;
      assert.strictEqual(cmd, "snapshot");
      assert.ok(ordinal < expectedBatches.length, "production helper issued an extra request");
      assert.deepStrictEqual(payload, {v: 1, requests: expectedBatches[ordinal]});
      observedPayloads.push(deepClone(payload));
      const requestCallId = "runtime.surface." + ordinal;
      const response = {
        success: true,
        v: 1,
        sessionNonce: "runtime_surface_session",
        snapshots: payload.requests.map((request, index) => runtimePhysicalSnapshot(
          request, accessibleCapacity, 10 + ordinal * 3 + index)),
        type: "panel_resp",
        domain: "inventory",
        cmd: "snapshot",
        callId: requestCallId,
        panel: owner.expectedPanel || "kshop",
        panelInstanceId: owner.expectedPanelInstanceId || "runtime.surface.owner",
      };
      if (typeof mutateResponse === "function") mutateResponse(response, ordinal);
      callback(response);
      return typeof mutateRequestReturn === "function"
        ? mutateRequestReturn(requestCallId, ordinal) : requestCallId;
    },
    {isActive: () => true, expectedPanel: owner.expectedPanel,
      expectedPanelInstanceId: owner.expectedPanelInstanceId},
    (value) => { callbackCount += 1; result = value; });
  assert.ok(result, "production physical-surface callback was not completed synchronously");
  return {started, result, callbackCount, observedPayloads};
}

const FILTERED_COORDINATOR_REQUESTS = Object.freeze([
  {containerId: "背包", offset: 0, limit: 50, filterKey: "all"},
  {containerId: "战备箱", offset: 40, limit: 40, filterKey: "weapon",
    filterSpec: {branch: "category", major: "weapon", use: "刀"}},
]);

function filteredProjectionSnapshot(request, surface, snapshotSeq) {
  const full = surface.snapshots.find((snapshot) => snapshot.containerId === request.containerId);
  assert.ok(full, "filtered projection lacks its complete physical source");
  const filtered = request.filterSpec != null || request.filterKey !== "all" || request.scope != null;
  const viewCapacity = filtered ? Math.min(80, full.accessibleCapacity) : full.viewCapacity;
  let offset = Number(request.offset);
  if (viewCapacity <= 0) offset = 0;
  else if (offset >= viewCapacity) offset = Math.floor((viewCapacity - 1) / request.limit) * request.limit;
  const limit = Math.min(Number(request.limit), Math.max(0, viewCapacity - offset));
  const snapshot = deepClone(full);
  snapshot.viewCapacity = viewCapacity;
  snapshot.filterKey = String(request.filterKey || "all");
  snapshot.snapshotSeq = snapshotSeq;
  snapshot.offset = offset;
  snapshot.limit = limit;
  snapshot.slots = full.slots.slice(offset, offset + limit).map(deepClone);
  if (request.filterSpec != null) snapshot.filterSpec = deepClone(request.filterSpec);
  else delete snapshot.filterSpec;
  if (request.scope != null) snapshot.scope = request.scope;
  else delete snapshot.scope;
  return snapshot;
}

function exerciseProductionFilteredCoordinator(failFirstProjection) {
  const accessibleCapacity = 240;
  const physicalBatches = runtimePhysicalBatches(accessibleCapacity);
  const observedRequests = [];
  const callbackResults = [];
  let physicalOrdinal = 0;
  let cycle = 0;
  let callOrdinal = 0;
  let projectionOrdinal = 0;
  let currentSurface = null;
  let coordinator = null;
  const projectionOwnerObservations = [];

  function request(cmd, payload, callback) {
    assert.strictEqual(cmd, "snapshot");
    const requests = deepClone(payload.requests);
    const constrained = requests.some((entry) => entry.filterKey !== "all"
      || entry.filterSpec != null || entry.scope != null);
    observedRequests.push(requests);
    const callId = "kshop.filtered." + callOrdinal;
    callOrdinal += 1;
    let response;
    if (constrained) {
      projectionOrdinal += 1;
      assert.ok(currentSurface, "exact visible projection preceded its complete surface");
      assert.deepStrictEqual(requests, FILTERED_COORDINATOR_REQUESTS);
      projectionOwnerObservations.push({
        beforeCallback: coordinator.debugState().busyOwner,
        afterCallback: null,
      });
      response = {
        success: true,
        v: failFirstProjection && projectionOrdinal === 1 ? 2 : 1,
        sessionNonce: currentSurface.sessionNonce,
        snapshots: requests.map((entry, index) => filteredProjectionSnapshot(
          entry, currentSurface, cycle * 100 + 90 + index)),
      };
    } else {
      if (physicalOrdinal === 0) cycle += 1;
      assert.deepStrictEqual(requests, physicalBatches[physicalOrdinal]);
      response = {
        success: true,
        v: 1,
        sessionNonce: "kshop_filtered_surface_" + cycle,
        snapshots: requests.map((entry, index) => runtimePhysicalSnapshot(
          entry, accessibleCapacity, cycle * 100 + 10 + physicalOrdinal * 3 + index)),
      };
      physicalOrdinal += 1;
      if (physicalOrdinal === physicalBatches.length) physicalOrdinal = 0;
    }
    Object.assign(response, {
      type: "panel_resp",
      domain: "inventory",
      cmd: "snapshot",
      callId,
      panel: "kshop",
      panelInstanceId: "kshop.filtered.owner",
    });
    callback(response);
    if (constrained) {
      projectionOwnerObservations[projectionOwnerObservations.length - 1].afterCallback
        = coordinator.debugState().busyOwner;
    }
    return callId;
  }

  coordinator = new ProductionInventoryRuntime.InventoryCoordinator({
    requests: FILTERED_COORDINATOR_REQUESTS,
    request,
    readPhysicalSurface(isActive, callback) {
      return ProductionInventoryRuntime.readPhysicalInventorySurface(request, {
        isActive,
        expectedPanel: "kshop",
        expectedPanelInstanceId: "kshop.filtered.owner",
      }, (result) => {
        if (result && result.success === true) currentSurface = deepClone(result.surface);
        callback(result);
      });
    },
  });
  coordinator.open((result) => callbackResults.push(result));
  return {coordinator, observedRequests, callbackResults, physicalBatches,
    projectionOwnerObservations};
}

function runSelfTests() {
  passed = 0;
  browserGateReceipt = null;
  runAdmissionSmoke();
  test("production KShop Inventory helper probes exact dynamic 50+A surfaces", () => {
    [0, 40, 80, 120, 160, 200, 240].forEach((accessibleCapacity) => {
      const run = exerciseProductionPhysicalSurface(accessibleCapacity);
      assert.strictEqual(run.started, true);
      assert.strictEqual(run.result.success, true);
      assert.strictEqual(run.callbackCount, 1);
      assert.strictEqual(run.result.surface.schema,
        ProductionInventoryRuntime.physicalSurfaceSchema);
      assert.strictEqual(run.result.surface.accessibleCapacity, accessibleCapacity);
      assert.strictEqual(run.result.surface.responseCount,
        runtimePhysicalBatches(accessibleCapacity).length);
      assert.strictEqual(run.result.surface.snapshots[0].slots.length, 50);
      assert.strictEqual(run.result.surface.snapshots[1].slots.length, accessibleCapacity);
      assert.strictEqual(run.result.snapshots[1].slots.length,
        Math.min(40, accessibleCapacity));
      assert.ok(!run.observedPayloads.some((payload) => payload.requests.some((request) =>
        request.containerId === "战备箱" && request.offset > 0 && request.limit === 0)));
    });
  });

  test("production KShop Inventory helper rejects extra or missing callback envelope fields", () => {
    [
      (response, ordinal) => { if (ordinal === 0) response.unexpected = true; },
      (response, ordinal) => { if (ordinal === 0) delete response.panel; },
    ].forEach((mutateResponse) => {
      const run = exerciseProductionPhysicalSurface(240, mutateResponse);
      assert.strictEqual(run.started, true);
      assert.deepStrictEqual(run.result,
        {success: false, error: "inventory_surface_invalid"});
      assert.strictEqual(run.callbackCount, 1);
      assert.strictEqual(run.observedPayloads.length, 1);
    });
  });

  test("production KShop Inventory helper rejects a mismatched callback callId", () => {
    const run = exerciseProductionPhysicalSurface(240, (response, ordinal) => {
      if (ordinal === 0) response.callId = "runtime.surface.wrong";
    });
    assert.strictEqual(run.started, true);
    assert.deepStrictEqual(run.result,
      {success: false, error: "inventory_surface_invalid"});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.observedPayloads.length, 1);
  });

  test("production KShop Inventory helper rejects a repeated matched callId", () => {
    const run = exerciseProductionPhysicalSurface(240, (response, ordinal) => {
      if (ordinal === 1) response.callId = "runtime.surface.0";
    }, null, (requestCallId, ordinal) => ordinal === 1
      ? "runtime.surface.0" : requestCallId);
    assert.strictEqual(run.started, true);
    assert.deepStrictEqual(run.result,
      {success: false, error: "inventory_surface_invalid"});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.observedPayloads.length, 2);
  });

  test("shared physical-surface helper accepts exact KShop and NPC owners", () => {
    [
      {expectedPanel: "kshop", expectedPanelInstanceId: "kshop.owner.1"},
      {expectedPanel: "npcshop", expectedPanelInstanceId: "npcshop.owner.1"},
    ].forEach((owner) => {
      const run = exerciseProductionPhysicalSurface(120, null, owner);
      assert.strictEqual(run.started, true);
      assert.strictEqual(run.result.success, true);
      assert.strictEqual(run.callbackCount, 1);
      assert.strictEqual(run.observedPayloads.length, 2);
    });
  });

  test("shared physical-surface helper rejects wrong panel and cross-batch instance drift", () => {
    const missingOwner = exerciseProductionPhysicalSurface(120, null,
      {expectedPanel: null, expectedPanelInstanceId: null});
    assert.strictEqual(missingOwner.started, false);
    assert.deepStrictEqual(missingOwner.result,
      {success: false, error: "inventory_surface_owner_invalid"});
    assert.strictEqual(missingOwner.callbackCount, 1);
    assert.strictEqual(missingOwner.observedPayloads.length, 0);
    const wrongPanel = exerciseProductionPhysicalSurface(120, (response, ordinal) => {
      if (ordinal === 0) response.panel = "npcshop";
    });
    assert.strictEqual(wrongPanel.started, true);
    assert.deepStrictEqual(wrongPanel.result,
      {success: false, error: "inventory_surface_invalid"});
    assert.strictEqual(wrongPanel.callbackCount, 1);
    const instanceDrift = exerciseProductionPhysicalSurface(120, (response, ordinal) => {
      if (ordinal === 1) response.panelInstanceId = "runtime.surface.other-owner";
    });
    assert.strictEqual(instanceDrift.started, true);
    assert.deepStrictEqual(instanceDrift.result,
      {success: false, error: "inventory_surface_invalid"});
    assert.strictEqual(instanceDrift.callbackCount, 1);
  });

  test("shared physical-surface helper rejects unavailable or invalid initial request returns", () => {
    const results = [];
    const unavailable = ProductionInventoryRuntime.readPhysicalInventorySurface(null,
      {expectedPanel: "kshop"}, (result) => { results.push(result); });
    assert.strictEqual(unavailable, false);
    assert.deepStrictEqual(results,
      [{success: false, error: "inventory_surface_unavailable"}]);
    [
      {name: "null", request: () => null},
      {name: "undefined", request: () => undefined},
      {name: "false", request: () => false},
      {name: "true", request: () => true},
      {name: "object", request: () => ({callId: "runtime.surface.0"})},
      {name: "throw", request: () => { throw new Error("not sent"); }},
    ].forEach((entry) => {
      let callbackCount = 0;
      let result = null;
      let sends = 0;
      const started = ProductionInventoryRuntime.readPhysicalInventorySurface(() => {
        sends += 1;
        return entry.request();
      }, {expectedPanel: "kshop"}, (value) => {
        callbackCount += 1;
        result = value;
      });
      assert.strictEqual(started, false, entry.name);
      assert.strictEqual(sends, 1, entry.name);
      assert.strictEqual(callbackCount, 1, entry.name);
      assert.deepStrictEqual(result,
        {success: false, error: "inventory_surface_request_contract_invalid"}, entry.name);
    });
  });

  test("shared physical-surface helper queues synchronous synthetic failure until callId returns", () => {
    let result = null;
    let callbackCount = 0;
    let sends = 0;
    const mux = new ProductionPanelRuntime.PanelRequestMux({
      send() { sends += 1; return false; },
      setTimer() { return 1; },
      clearTimer() {},
      callPrefix: "kshop.inventory.surface",
      createMessage(context) {
        return {type: "panel", domain: "inventory", panel: "kshop",
          panelInstanceId: context.session.panelInstanceId, cmd: context.entry.cmd,
          callId: context.entry.callId, payload: context.payload};
      },
      createSynthetic(context) {
        return {type: "panel_resp", domain: "inventory", panel: "kshop",
          panelInstanceId: context.session.panelInstanceId, cmd: context.entry.cmd,
          callId: context.entry.callId, success: false, error: context.error,
          clientSynthetic: true};
      },
    });
    assert.strictEqual(mux.openSession({panelInstanceId: "runtime.surface.owner"}), true);
    const started = ProductionInventoryRuntime.readPhysicalInventorySurface(
      (cmd, payload, callback) => mux.request(cmd, payload,
        {sendError: "disconnected"}, callback),
      {expectedPanel: "kshop", expectedPanelInstanceId: "runtime.surface.owner"},
      (value) => { callbackCount += 1; result = value; });
    assert.strictEqual(started, true);
    assert.strictEqual(sends, 1);
    assert.deepStrictEqual(result,
      {success: false, error: "inventory_surface_invalid"});
    assert.strictEqual(callbackCount, 1);
  });

  test("production KShop entry is wired to the complete physical-surface helper", () => {
    const inventorySource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "inventory-runtime.js"), "utf8");
    const kshopSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "kshop.js"), "utf8");
    assert.match(inventorySource,
      /\{containerId:'背包',offset:0,limit:50,filterKey:'all'\}/);
    assert.match(inventorySource,
      /\{containerId:'战备箱',offset:0,limit:100,filterKey:'all'\}/);
    assert.match(inventorySource,
      /offset:100,limit:100,filterKey:'all'/);
    assert.match(inventorySource,
      /offset:200,[\s\S]*limit:accessibleCapacity - 200,filterKey:'all'/);
    assert.match(kshopSource,
      /readPhysicalSurface:function\(isActive, callback\)[\s\S]*InventoryRuntime\.readPhysicalInventorySurface\(requestInventory,[\s\S]*expectedPanel:'kshop',[\s\S]*expectedPanelInstanceId:_panelInstanceId/);
  });

  test("production closure binds KShop and shared Inventory current-tree semantics", () => {
    const consumerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "kshop.js"), "utf8");
    const providerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "inventory-runtime.js"), "utf8");
    const inspected = ProductionClosure.inspectInventorySurfaceSourceContract(
      consumerSource, providerSource);
    assert.strictEqual(inspected.schema,
      "workbench-live-e2e.kshop.production-inventory-source-anchors.v3");
    assert.strictEqual(inspected.anchors.length, 26);
    assert.strictEqual(new Set(inspected.anchors.map((entry) => entry.id)).size, 26);
    assert.strictEqual(inspected.tokenCanonicalization,
      "js-comment-string-regex-excluding-structural-token-stream.v5");
    assert.strictEqual(inspected.structureAssertions.length, 51);
    assert.strictEqual(new Set(inspected.structureAssertions.map((entry) => entry.id)).size, 51);
    assert.deepStrictEqual(inspected.orderAssertions.map((entry) => entry.id), [
      "consumer.coordinator.wiring_order",
      "consumer.checkout.external_write_order",
      "consumer.claim.external_write_order",
    ]);
    const contract = ProductionClosure.captureInventoryPhysicalSurfaceContract(PRODUCTION_ROOT);
    assert.strictEqual(contract.schema,
      "workbench-live-e2e.kshop.production-inventory-surface.v1");
    assert.strictEqual(contract.owner.expectedPanel, "kshop");
    assert.deepStrictEqual(contract.refresh, {
      completePhysicalSurface: {maximumBatchCount: 3,
        order: "bag_50_plus_battle_windows_0_100_200"},
      constrainedProjection: {atMaximumPhysicalSurfaceBatchOrdinal: 4,
        request: "captured_visible_requests_exact_and_not_rewritten",
        ownerRelease: "after_exact_visible_response_or_single_failure"},
      successReceipt: "first_one_to_three_complete_physical_batches_only",
    });
    assert.strictEqual(contract.sourceContract.contractSha256, inspected.contractSha256);
    assert.strictEqual(ProductionClosure.verifyInventoryPhysicalSurfaceContract(
      PRODUCTION_ROOT, contract), contract);
  });

  test("production inventory semantic anchors reject consumer and provider drift", () => {
    const consumerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "kshop.js"), "utf8");
    const providerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "inventory-runtime.js"), "utf8");
    function mutateNth(source, needle, replacement, occurrence) {
      let index = -1;
      let offset = 0;
      const target = occurrence || 0;
      for (let count = 0; count <= target; count += 1) {
        index = source.indexOf(needle, offset);
        assert.ok(index >= 0, "mutation target is absent: " + needle);
        offset = index + needle.length;
      }
      return source.slice(0, index) + replacement + source.slice(index + needle.length);
    }
    const mutations = [
      {id: "consumer.coordinator.assignment", source: "consumer",
        needle: "new InventoryRuntime.InventoryCoordinator({",
        replacement: "new InventoryRuntime.InventoryCoordinatorChanged({"},
      {id: "consumer.coordinator.request", source: "consumer",
        needle: "request: requestInventory",
        replacement: "request: function() { return false; }"},
      {id: "consumer.request.transport", source: "consumer",
        needle: "_inventoryMux.request(cmd, payload || {}, {",
        replacement: "_inventoryMux.requestChanged(cmd, payload || {}, {"},
      {id: "consumer.reader.owner", source: "consumer",
        needle: "expectedPanel:'kshop'", replacement: "expectedPanel:'other'"},
      {id: "consumer.checkout.begin", source: "consumer",
        needle: "beginExternalWrite('shop.checkoutCommit')",
        replacement: "beginExternalWrite('shop.checkoutChanged')"},
      {id: "consumer.checkout.complete", source: "consumer",
        needle: "completeExternalWrite(inventoryWrite, needsInventoryRefresh, function(refreshResult)",
        replacement: "completeExternalWrite(inventoryWrite, false, function(refreshResult)"},
      {id: "consumer.claim.begin", source: "consumer",
        needle: "beginExternalWrite('shop.claim')",
        replacement: "beginExternalWrite('shop.claimChanged')"},
      {id: "consumer.claim.complete", source: "consumer", occurrence: 1,
        needle: "completeExternalWrite(inventoryWrite, needsInventoryRefresh, function(refreshResult)",
        replacement: "completeExternalWrite(inventoryWrite, false, function(refreshResult)"},
      {id: "provider.physical.sync_duplicate", source: "provider",
        needle: "queuedDuplicate = true", replacement: "queuedDuplicate = false"},
      {id: "provider.physical.return_fence", source: "provider",
        needle: "if (!isIdentityText(expectedCallId, 160) || queuedDuplicate)",
        replacement: "if (!isIdentityText(expectedCallId, 160))"},
      {id: "provider.constraint.classifier", source: "provider",
        needle: "normalizeFilterKey(request && request.filterKey) !== 'all'",
        replacement: "normalizeFilterKey(request && request.filterKey) === 'all'"},
      {id: "provider.constraint.classifier", source: "provider",
        needle: "own(request, 'filterSpec')", replacement: "false"},
      {id: "provider.constraint.classifier", source: "provider",
        needle: "normalizeProjectionScope(request && request.scope) !== 'all'",
        replacement: "normalizeProjectionScope(request && request.scope) === 'all'"},
      {id: "provider.local.rejects_constrained", source: "provider",
        needle: "if (requestNeedsAuthorityProjection(request)) return null;",
        replacement: "if (false) return null;"},
      {id: "provider.followup.branch", source: "provider",
        needle: "if (requestsNeedAuthorityProjection(desiredRequests)) {",
        replacement: "if (false) {"},
      {id: "provider.followup.exact_desired", source: "provider",
        needle: "requests:cloneRequests(desiredRequests)", replacement: "requests:[]"},
      {id: "provider.followup.exact_call_id", source: "provider", occurrence: 1,
        needle: "response.callId !== expectedCallId", replacement: "false"},
      {id: "provider.followup.sync_duplicate", source: "provider", occurrence: 1,
        needle: "queuedDuplicate = true", replacement: "queuedDuplicate = false"},
      {id: "provider.followup.throw_fence", source: "provider",
        needle: "catch (_projectionRequestError)", replacement: "catch (_ignoredError)"},
      {id: "provider.followup.return_fence", source: "provider", occurrence: 1,
        needle: "if (!isIdentityText(expectedCallId, 160) || queuedDuplicate)",
        replacement: "if (!isIdentityText(expectedCallId, 160))"},
      {id: "provider.followup.failure_once", source: "provider",
        needle: "function failProjectionRequestContract()",
        replacement: "function failProjectionRequestContractChanged()"},
      {id: "provider.followup.once_fence", source: "provider",
        needle: "function handleProjectionResponse(response)",
        replacement: "function handleProjectionResponseChanged(response)"},
      {id: "provider.coherence.session", source: "provider", occurrence: 1,
        needle: "response.success !== true || response.v !== 1",
        replacement: "response.success !== true || response.v !== 2"},
      {id: "provider.coherence.session", source: "provider", occurrence: 1,
        needle: "!isIdentityText(response.sessionNonce, 128)", replacement: "false"},
      {id: "provider.coherence.session", source: "provider",
        needle: "response.sessionNonce !== surface.sessionNonce", replacement: "false"},
      {id: "provider.coherence.revision", source: "provider",
        needle: "snapshot.capacity !== full.capacity", replacement: "false"},
      {id: "provider.coherence.revision", source: "provider",
        needle: "snapshot.accessibleCapacity !== full.accessibleCapacity", replacement: "false"},
      {id: "provider.coherence.revision", source: "provider",
        needle: "snapshot.pageSizeHint !== full.pageSizeHint", replacement: "false"},
      {id: "provider.coherence.revision", source: "provider",
        needle: "snapshot.locked !== full.locked", replacement: "false"},
      {id: "provider.coherence.revision", source: "provider",
        needle: "snapshot.containerEpoch !== full.containerEpoch", replacement: "false"},
      {id: "provider.coherence.revision", source: "provider",
        needle: "snapshot.containerVersion !== full.containerVersion", replacement: "false"},
      {id: "provider.coherence.sequence", source: "provider",
        needle: "snapshot.snapshotSeq <= maximumSurfaceSequence", replacement: "false"},
      {id: "provider.coherence.facets", source: "provider",
        needle: "sameProjectionValue(snapshot.filterFacets, full.filterFacets)", replacement: "true"},
      {id: "provider.coherence.facets", source: "provider",
        needle: "snapshot.filterItemCount !== full.filterItemCount", replacement: "false"},
      {id: "provider.coherence.facets", source: "provider",
        needle: "sameProjectionValue(snapshot.setFacets, full.setFacets)", replacement: "true"},
      {id: "provider.coherence.facets", source: "provider",
        needle: "snapshot.setFilterItemCount !== full.setFilterItemCount", replacement: "false"},
      {id: "provider.coherence.physical_slot", source: "provider",
        needle: "sameProjectionValue(visibleSlot, full.slots[physicalSlot])",
        replacement: "visibleSlot === full.slots[physicalSlot]"},
      {id: "provider.receipt.retained", source: "provider",
        needle: "finish(valid ? {success:true} : {success:false,error:'inventory_surface_projection_invalid'},\n                            result.surface);",
        replacement: "finish(valid ? {success:true} : {success:false,error:'inventory_surface_projection_invalid'},\n                            null);"},
    ];
    const requiredAnchorIds = ProductionClosure.inspectInventorySurfaceSourceContract(
      consumerSource, providerSource).anchors.map((entry) => entry.id).sort();
    assert.deepStrictEqual(Array.from(new Set(mutations.map((entry) => entry.id))).sort(),
      requiredAnchorIds);
    mutations.forEach((mutation) => {
      let consumer = consumerSource;
      let provider = providerSource;
      if (mutation.source === "consumer") consumer = mutateNth(consumer,
        mutation.needle, mutation.replacement, mutation.occurrence);
      else provider = mutateNth(provider,
        mutation.needle, mutation.replacement, mutation.occurrence);
      assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
        consumer, provider), (error) => error
          && error.code === "production_inventory_surface_source_contract_invalid"
          && error.details && error.details.id === mutation.id, mutation.id);
    });
  });

  test("inventory source markers and wiring cannot be supplied by inert lexical forms", () => {
    const consumerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "kshop.js"), "utf8");
    const providerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "inventory-runtime.js"), "utf8");
    function reject(consumer, provider, expectedId) {
      assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
        consumer, provider), (error) => error
          && error.code === "production_inventory_surface_source_contract_invalid"
          && (!expectedId || error.details && error.details.id === expectedId));
    }

    const requestDecoy = "request: requestInventory,";
    const requestDrift = consumerSource.replace(requestDecoy,
      "request: function() { return " + JSON.stringify(requestDecoy)
        + " && false; }, /* " + requestDecoy + " */");
    assert.notStrictEqual(requestDrift, consumerSource);
    reject(requestDrift, providerSource, "consumer.coordinator.request");
    const requestRegexDrift = consumerSource.replace(requestDecoy,
      "request: function() { var requestRegexDecoy = /request: requestInventory,/; "
        + "return false; },");
    assert.notStrictEqual(requestRegexDrift, consumerSource);
    reject(requestRegexDrift, providerSource, "consumer.coordinator.request");

    const readerDecoy = "readPhysicalSurface: function(isActive, callback) { "
      + "return InventoryRuntime.readPhysicalInventorySurface(requestInventory, "
      + "{isActive:isActive, expectedPanel:'kshop', "
      + "expectedPanelInstanceId:_panelInstanceId}, callback); }";
    const readerStart = "readPhysicalSurface:function(isActive, callback) {";
    const readerDrift = consumerSource.replace(readerStart,
      "readerContractDecoy:" + JSON.stringify(readerDecoy) + ",\n"
        + "        /* " + readerDecoy + " */\n"
        + "        readPhysicalSurfaceChanged:function(isActive, callback) {");
    assert.notStrictEqual(readerDrift, consumerSource);
    reject(readerDrift, providerSource, "consumer.reader.owner");

    const classifierExpression = "normalizeFilterKey(request && request.filterKey) !== 'all' "
      + "|| !!request && own(request, 'filterSpec') "
      + "|| normalizeProjectionScope(request && request.scope) !== 'all'";
    const classifierNeedle = "return " + classifierExpression + ";";
    let classifierDrift = providerSource.replace(
      "normalizeFilterKey(request && request.filterKey) !== 'all'", "false");
    classifierDrift = classifierDrift.replace(
      "function requestNeedsAuthorityProjection(request) {",
      "function requestNeedsAuthorityProjection(request) {\n"
        + "        var classifierContractDecoy = " + JSON.stringify(classifierNeedle) + ";\n"
        + "        /* " + classifierNeedle + " */");
    assert.notStrictEqual(classifierDrift, providerSource);
    reject(consumerSource, classifierDrift, "provider.constraint.classifier");
    let classifierRegexDrift = providerSource.replace(
      "normalizeFilterKey(request && request.filterKey) !== 'all'", "false");
    classifierRegexDrift = classifierRegexDrift.replace(
      "function requestNeedsAuthorityProjection(request) {",
      "function requestNeedsAuthorityProjection(request) {\n"
        + "        var classifierRegexDecoy = /" + classifierNeedle + "/;");
    assert.notStrictEqual(classifierRegexDrift, providerSource);
    reject(consumerSource, classifierRegexDrift, "provider.constraint.classifier");

    const classifierCallable = "function requestNeedsAuthorityProjection(request) { "
      + classifierNeedle + " }";
    let classifierMarkerDrift = providerSource.replace(
      "function requestNeedsAuthorityProjection(request)",
      "function requestNeedsAuthorityProjectionChanged(request)");
    classifierMarkerDrift += "\n/* " + classifierCallable + " */\n"
      + "var classifierCallableDecoy = " + JSON.stringify(classifierCallable) + ";\n";
    assert.notStrictEqual(classifierMarkerDrift, providerSource);
    reject(consumerSource, classifierMarkerDrift);

    let classifierControlRegexDrift = providerSource.replace(
      "function requestNeedsAuthorityProjection(request)",
      "function requestNeedsAuthorityProjectionChanged(request)");
    classifierControlRegexDrift += "\nif (false) /" + classifierCallable + "/;\n";
    assert.notStrictEqual(classifierControlRegexDrift, providerSource);
    assertJavaScriptParses(classifierControlRegexDrift);
    reject(consumerSource, classifierControlRegexDrift);

    const providerModuleMarker = "})(typeof window !== 'undefined' ? window : globalThis, "
      + "function() {";
    let classifierBlockRegexDrift = providerSource.replace(
      "function requestNeedsAuthorityProjection(request)",
      "function requestNeedsAuthorityProjectionChanged(request)");
    classifierBlockRegexDrift = classifierBlockRegexDrift.replace(providerModuleMarker,
      providerModuleMarker + "\n    if (false) {} /{ } " + classifierCallable + "/;");
    assert.notStrictEqual(classifierBlockRegexDrift, providerSource);
    assertJavaScriptParses(classifierBlockRegexDrift);
    reject(consumerSource, classifierBlockRegexDrift);
  });

  test("critical inventory anchors reject dead blocks and unused nested callables", () => {
    const consumerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "kshop.js"), "utf8");
    const providerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "inventory-runtime.js"), "utf8");
    function rejects(consumer, provider, expectedId) {
      assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
        consumer, provider), (error) => error
          && error.code === "production_inventory_surface_source_contract_invalid"
          && error.details && error.details.id === expectedId, expectedId);
    }
    function wrapStatement(source, statement, prefix, suffix, occurrence) {
      let start = -1;
      let offset = 0;
      for (let count = 0; count <= (occurrence || 0); count += 1) {
        start = source.indexOf(statement, offset);
        assert.ok(start >= 0, "dead-code statement is absent: " + statement);
        offset = start + statement.length;
      }
      return source.slice(0, start) + prefix + statement + suffix
        + source.slice(start + statement.length);
    }
    function wrapDelimited(source, startNeedle, endNeedle, prefix, suffix, occurrence) {
      let start = -1;
      let offset = 0;
      for (let count = 0; count <= (occurrence || 0); count += 1) {
        start = source.indexOf(startNeedle, offset);
        assert.ok(start >= 0, "dead-code span start is absent: " + startNeedle);
        offset = start + startNeedle.length;
      }
      const endStart = source.indexOf(endNeedle, start + startNeedle.length);
      assert.ok(endStart >= 0, "dead-code span end is absent: " + endNeedle);
      const end = endStart + endNeedle.length;
      return source.slice(0, start) + prefix + source.slice(start, end) + suffix
        + source.slice(end);
    }

    rejects(wrapDelimited(consumerSource,
      "var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({",
      "\n    });", "if (false) {\n        ", "\n    }", 0), providerSource,
    "consumer.coordinator.assignment");

    const readerStart = "readPhysicalSurface:function(isActive, callback) {";
    const readerStartIndex = consumerSource.indexOf(readerStart);
    const readerEndMarker = "\n        }";
    const readerEndStart = consumerSource.indexOf(readerEndMarker, readerStartIndex);
    assert.ok(readerStartIndex >= 0 && readerEndStart > readerStartIndex);
    const readerEnd = readerEndStart + readerEndMarker.length;
    const readerProperty = consumerSource.slice(readerStartIndex, readerEnd);
    const nestedReader = consumerSource.slice(0, readerStartIndex)
      + "readerDeadCode:{" + readerProperty + "},\n"
      + "        readPhysicalSurfaceChanged:function() { return false; }"
      + consumerSource.slice(readerEnd);
    rejects(nestedReader, providerSource, "consumer.reader.owner");

    const classifierFunctionStart = providerSource.indexOf(
      "function requestNeedsAuthorityProjection(request) {");
    const classifierReturnStart = providerSource.indexOf("return ", classifierFunctionStart);
    const classifierReturnEnd = providerSource.indexOf(";", classifierReturnStart) + 1;
    assert.ok(classifierFunctionStart >= 0 && classifierReturnStart > classifierFunctionStart
      && classifierReturnEnd > classifierReturnStart);
    const classifierReturn = providerSource.slice(classifierReturnStart, classifierReturnEnd);
    rejects(consumerSource, providerSource.replace(classifierReturn,
      "if (false) { " + classifierReturn + " } return false;"),
    "provider.constraint.classifier");
    rejects(consumerSource, providerSource.replace(classifierReturn,
      "function unusedClassifier() { " + classifierReturn + " } return false;"),
    "provider.constraint.classifier");

    const checkoutBegin = "var inventoryWrite = "
      + "_inventoryCoordinator.beginExternalWrite('shop.checkoutCommit');";
    rejects(wrapStatement(consumerSource, checkoutBegin,
      "if (false) { ", " }", 0), providerSource, "consumer.checkout.begin");
    const claimBegin = "var inventoryWrite = "
      + "_inventoryCoordinator.beginExternalWrite('shop.claim');";
    rejects(wrapStatement(consumerSource, claimBegin,
      "function unusedClaimBegin() { ", " }", 0), providerSource, "consumer.claim.begin");

    rejects(wrapDelimited(consumerSource,
      "if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, needsInventoryRefresh, "
        + "function(refreshResult)",
      "\n            })) return;", "function unusedCheckoutComplete() { ", " }", 0),
    providerSource, "consumer.checkout.complete");
    rejects(wrapDelimited(consumerSource,
      "if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, needsInventoryRefresh, "
        + "function(refreshResult)",
      "\n            })) return;", "if (false) { ", " }", 1),
    providerSource, "consumer.claim.complete");

    const completePrefix = "if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, "
      + "needsInventoryRefresh, function(refreshResult)";
    rejects(wrapStatement(consumerSource, completePrefix,
      "return; if (false) {} ", "", 0), providerSource, "consumer.checkout.complete");
    rejects(wrapStatement(consumerSource, completePrefix,
      "return; ", "", 1), providerSource, "consumer.claim.complete");
    rejects(wrapStatement(consumerSource, claimBegin,
      "return; ", "", 0), providerSource, "consumer.claim.begin");
    rejects(wrapStatement(consumerSource,
      "if (!_writeCoordinator.checkout(token, function(resp) {",
      "return; ", "", 0), providerSource, "consumer.checkout.complete");
    rejects(wrapStatement(consumerSource, claimBegin,
      "if (true) { return; } ", "", 0), providerSource, "consumer.claim.begin");
    rejects(wrapStatement(consumerSource, completePrefix,
      "if (true) { return; } ", "", 0), providerSource, "consumer.checkout.complete");
    rejects(wrapStatement(consumerSource, completePrefix,
      "if (true) { return; } 0; ", "", 1), providerSource, "consumer.claim.complete");
  });

  test("external-write call bodies and begin-to-complete order are fail-closed", () => {
    const consumerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "kshop.js"), "utf8");
    const providerSource = fs.readFileSync(path.join(PRODUCTION_ROOT,
      "launcher", "web", "modules", "inventory-runtime.js"), "utf8");
    function nthIndex(source, needle, occurrence) {
      let index = -1;
      let offset = 0;
      for (let count = 0; count <= occurrence; count += 1) {
        index = source.indexOf(needle, offset);
        assert.ok(index >= 0, "swap target is absent: " + needle);
        offset = index + needle.length;
      }
      return index;
    }
    function swapNth(source, leftNeedle, leftOccurrence, rightNeedle, rightOccurrence) {
      const left = nthIndex(source, leftNeedle, leftOccurrence);
      const right = nthIndex(source, rightNeedle, rightOccurrence);
      assert.ok(left < right, "external-write fixture requires begin before complete");
      return source.slice(0, left) + rightNeedle
        + source.slice(left + leftNeedle.length, right) + leftNeedle
        + source.slice(right + rightNeedle.length);
    }
    function replaceNth(source, needle, replacement, occurrence) {
      const start = nthIndex(source, needle, occurrence || 0);
      return source.slice(0, start) + replacement + source.slice(start + needle.length);
    }
    function rejects(consumer, expectedId) {
      assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
        consumer, providerSource), (error) => error
          && error.code === "production_inventory_surface_source_contract_invalid"
          && error.details && error.details.id === expectedId, expectedId);
    }
    function makeWriteRequestInert(source, writerName) {
      const startNeedle = "if (!_writeCoordinator." + writerName;
      const start = source.indexOf(startNeedle);
      assert.ok(start >= 0, "write request start is absent: " + writerName);
      const closeNeedle = "\n        })) {";
      const close = source.indexOf(closeNeedle, start + startNeedle.length);
      assert.ok(close > start, "write request close is absent: " + writerName);
      return source.slice(0, start)
        + source.slice(start, start + 5) + "(false && "
        + source.slice(start + 5, close) + "\n        }))) {"
        + source.slice(close + closeNeedle.length);
    }
    const complete = "if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, "
      + "needsInventoryRefresh, function(refreshResult)";
    rejects(swapNth(consumerSource,
      "var inventoryWrite = _inventoryCoordinator.beginExternalWrite('shop.checkoutCommit');", 0,
      complete, 0), "consumer.checkout.external_write_order");
    rejects(swapNth(consumerSource,
      "var inventoryWrite = _inventoryCoordinator.beginExternalWrite('shop.claim');", 0,
      complete, 1), "consumer.claim.external_write_order");

    rejects(consumerSource.replace(complete,
      "if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, false, "
        + "function(refreshResult)"), "consumer.checkout.complete");
    rejects(consumerSource.replace("beginExternalWrite('shop.claim')",
      "beginExternalWrite('shop.claimChanged')"), "consumer.claim.begin");

    const falseCheckout = makeWriteRequestInert(consumerSource,
      "checkout(token, function(resp) {");
    const falseClaim = makeWriteRequestInert(consumerSource,
      "claim(pidx, function(resp) {");
    assertJavaScriptParses(falseCheckout);
    assertJavaScriptParses(falseClaim);
    rejects(falseCheckout, "consumer.checkout.complete");
    rejects(falseClaim, "consumer.claim.complete");

    const falseRequest = consumerSource.replace("request: requestInventory,",
      "request: requestInventory && function() { return false; },");
    assert.notStrictEqual(falseRequest, consumerSource);
    assertJavaScriptParses(falseRequest);
    rejects(falseRequest, "consumer.coordinator.request");

    const asyncClassifier = providerSource.replace(
      "function requestNeedsAuthorityProjection(request) {",
      "async function requestNeedsAuthorityProjection(request) {");
    assert.notStrictEqual(asyncClassifier, providerSource);
    assertJavaScriptParses(asyncClassifier);
    assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
      consumerSource, asyncClassifier), (error) => error
        && error.code === "production_inventory_surface_source_contract_invalid"
        && error.details && error.details.id === "provider.constraint.classifier");

    const duplicateRequest = consumerSource.replace("request: requestInventory,",
      "request: requestInventory,\n        request: function() { return false; },");
    const computedRequest = consumerSource.replace("request: requestInventory,",
      "request: requestInventory,\n        ['request']: function() { return false; },");
    const duplicateReader = consumerSource.replace(
      /(\r?\n        },\r?\n        onStateChange:)/,
      "\n        },\n        readPhysicalSurface:function() { return false; },\n        onStateChange:");
    [duplicateRequest, computedRequest, duplicateReader].forEach((mutated) => {
      assert.notStrictEqual(mutated, consumerSource);
      assertJavaScriptParses(mutated);
      rejects(mutated, "consumer.coordinator.request");
    });

    function mutateCoordinatorClose(replacement) {
      const start = consumerSource.indexOf(
        "var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({");
      const close = consumerSource.indexOf("\n    });", start);
      assert.ok(start >= 0 && close > start);
      return consumerSource.slice(0, close) + "\n    " + replacement
        + consumerSource.slice(close + "\n    });".length);
    }
    const falseCoordinator = mutateCoordinatorClose("} && false);");
    const projectedCoordinator = mutateCoordinatorClose("}).missingProperty;");
    [falseCoordinator, projectedCoordinator].forEach((mutated) => {
      assertJavaScriptParses(mutated);
      rejects(mutated, "consumer.coordinator.assignment");
    });

    const reboundRequest = consumerSource.replace("function isKShopOpen() {",
      "requestInventory = function() { return false; };\n\n    function isKShopOpen() {");
    assert.notStrictEqual(reboundRequest, consumerSource);
    assertJavaScriptParses(reboundRequest);
    rejects(reboundRequest, "consumer.request.transport");

    const reboundClassifier = providerSource.replace(
      "function requestsNeedAuthorityProjection(requests) {",
      "requestNeedsAuthorityProjection = function() { return false; };\n\n"
        + "    function requestsNeedAuthorityProjection(requests) {");
    assert.notStrictEqual(reboundClassifier, providerSource);
    assertJavaScriptParses(reboundClassifier);
    assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
      consumerSource, reboundClassifier), (error) => error
        && error.code === "production_inventory_surface_source_contract_invalid"
        && error.details && error.details.id === "provider.constraint.classifier");

    const evalClassifier = providerSource.replace(
      /(\r?\n    return \{\r?\n        InventoryCoordinator:)/,
      "\n    eval(\"requestNeedsAuthorityProjection = function(){ return false; }\");$1");
    assert.notStrictEqual(evalClassifier, providerSource);
    assertJavaScriptParses(evalClassifier);
    assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
      consumerSource, evalClassifier), (error) => error
        && error.code === "production_inventory_surface_source_contract_invalid"
        && error.details && error.details.id === "provider.constraint.classifier");

    const refreshAssignmentStart = providerSource.indexOf(
      "InventoryCoordinator.prototype._refreshPhysicalSurfaceWhileOwned = function(");
    assert.ok(refreshAssignmentStart >= 0);
    const refreshAssignmentTail = providerSource.slice(refreshAssignmentStart);
    const refreshAssignmentEnd
      = /\r?\n    };\r?\n\r?\n    InventoryCoordinator\.prototype\._applySnapshots/.exec(
        refreshAssignmentTail);
    assert.ok(refreshAssignmentEnd);
    const refreshAssignmentEndStart = refreshAssignmentStart + refreshAssignmentEnd.index;
    const falseRefreshAssignment = providerSource.slice(0, refreshAssignmentEndStart)
      + "\n    } && false;\n\n    InventoryCoordinator.prototype._applySnapshots"
      + providerSource.slice(refreshAssignmentEndStart + refreshAssignmentEnd[0].length);
    assert.notStrictEqual(falseRefreshAssignment, providerSource);
    assertJavaScriptParses(falseRefreshAssignment);
    assert.throws(() => ProductionClosure.inspectInventorySurfaceSourceContract(
      consumerSource, falseRefreshAssignment), (error) => error
        && error.code === "production_inventory_surface_source_contract_invalid"
        && error.details && error.details.id === "provider.followup.branch");

    rejects(replaceNth(consumerSource, "if (!inventoryWrite) {", "if (true) {", 0),
      "consumer.checkout.complete");
    rejects(consumerSource.replace("if (!canStartShopWrite()) {", "if (true) {"),
      "consumer.claim.complete");
    rejects(replaceNth(consumerSource, "if (!inventoryWrite) {", "if (true) {", 1),
      "consumer.claim.complete");
    rejects(consumerSource.replace("if (resp.success) {",
      "if (resp.success) { return;"), "consumer.checkout.complete");
    const throwingClaimProjection = consumerSource.replace(
      /var needsInventoryRefresh = !!resp\.success\r?\n\s*\|\| \(!!resp\.reconciled && resp\.error !== 'item_not_found' && resp\.error !== 'stale_state'\);/,
      "var needsInventoryRefresh = missingCall() || (false && false && false);");
    assert.notStrictEqual(throwingClaimProjection, consumerSource);
    rejects(throwingClaimProjection, "consumer.claim.complete");
  });

  test("real InventoryCoordinator refreshes filtered page through full then exact authority", () => {
    const run = exerciseProductionFilteredCoordinator(false);
    assert.strictEqual(run.callbackResults.length, 1);
    assert.deepStrictEqual(run.callbackResults[0], {
      success: true,
      refreshed: true,
      surface: run.callbackResults[0].surface,
    });
    assert.deepStrictEqual(run.observedRequests, run.physicalBatches.concat([
      deepClone(FILTERED_COORDINATOR_REQUESTS),
    ]));
    assert.deepStrictEqual(run.projectionOwnerObservations,
      [{beforeCallback: "bootstrap", afterCallback: "bootstrap"}]);
    const state = run.coordinator.debugState();
    assert.strictEqual(state.ready, true);
    assert.strictEqual(state.refreshRequired, false);
    assert.strictEqual(state.busyOwner, null);
    assert.deepStrictEqual(state.requests, FILTERED_COORDINATOR_REQUESTS);
    assert.deepStrictEqual(state.physicalSurface, {
      schema: ProductionInventoryRuntime.physicalSurfaceSchema,
      accessibleCapacity: 240,
      responseCount: 3,
    });
    assert.strictEqual(run.callbackResults[0].surface.responseCount, 3);
    assert.strictEqual(run.callbackResults[0].surface.windows.length, 4);
    assert.strictEqual(run.callbackResults[0].surface.snapshots.length, 2);
    const battle = run.coordinator.getWindow("战备箱");
    assert.strictEqual(battle.offset, 40);
    assert.strictEqual(battle.limit, 40);
    assert.deepStrictEqual(battle.filterSpec,
      {branch: "category", major: "weapon", use: "刀"});
    assert.deepStrictEqual(battle.slots,
      run.callbackResults[0].surface.snapshots[1].slots.slice(40, 80));
  });

  test("filtered physical refresh failure clears receipt and retry repeats the exact route", () => {
    const run = exerciseProductionFilteredCoordinator(true);
    assert.deepStrictEqual(run.callbackResults,
      [{success: false, error: "inventory_surface_projection_invalid"}]);
    assert.deepStrictEqual(run.observedRequests, run.physicalBatches.concat([
      deepClone(FILTERED_COORDINATOR_REQUESTS),
    ]));
    assert.deepStrictEqual(run.projectionOwnerObservations,
      [{beforeCallback: "bootstrap", afterCallback: "bootstrap"}]);
    let state = run.coordinator.debugState();
    assert.strictEqual(state.ready, false);
    assert.strictEqual(state.refreshRequired, true);
    assert.strictEqual(state.busyOwner, null);
    assert.strictEqual(state.physicalSurface, null);
    assert.deepStrictEqual(state.requests, FILTERED_COORDINATOR_REQUESTS);
    assert.strictEqual(run.coordinator.retryRefresh((result) =>
      run.callbackResults.push(result)), true);
    assert.strictEqual(run.callbackResults.length, 2);
    assert.strictEqual(run.callbackResults[1].success, true);
    assert.deepStrictEqual(run.observedRequests,
      run.physicalBatches.concat([deepClone(FILTERED_COORDINATOR_REQUESTS)])
        .concat(run.physicalBatches, [deepClone(FILTERED_COORDINATOR_REQUESTS)]));
    assert.deepStrictEqual(run.projectionOwnerObservations, [
      {beforeCallback: "bootstrap", afterCallback: "bootstrap"},
      {beforeCallback: "refresh.retry", afterCallback: "refresh.retry"},
    ]);
    state = run.coordinator.debugState();
    assert.strictEqual(state.ready, true);
    assert.strictEqual(state.refreshRequired, false);
    assert.deepStrictEqual(state.requests, FILTERED_COORDINATOR_REQUESTS);
    assert.deepStrictEqual(state.physicalSurface, {
      schema: ProductionInventoryRuntime.physicalSurfaceSchema,
      accessibleCapacity: 240,
      responseCount: 3,
    });
  });

  test("canonical check executes filtered browser assertions under a verified child journal", () => {
    const bootstrapPath = path.join(__dirname, "browser-bootstrap.js");
    const bootstrapSource = fs.readFileSync(bootstrapPath, "utf8");
    assert(bootstrapSource.includes(
      "RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest, artifact:journal })"));
    assert(bootstrapSource.includes("verifyServedResourceClosure({"));
    assert(bootstrapSource.includes("browserExecutableReceipt({"));
    assert(bootstrapSource.includes('"external_browser_binary"'));
    const moduleInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
      "browser-module-inventory.v1.json"), "utf8"));
    assert.strictEqual(moduleInventory.schema,
      "workbench-live-e2e.kshop.browser-module-inventory.v1");
    assert.strictEqual(moduleInventory.nodeVersion, process.version);
    assert.strictEqual(moduleInventory.files.length, 280);
    assert.strictEqual(moduleInventory.builtins.length, 23);
    assert(moduleInventory.files.includes("tools/run-kshop-harness.js"));
    assert(!moduleInventory.files.includes("tools/run-npcshop-harness.js"));
    assert.deepStrictEqual(moduleInventory.files, moduleInventory.files.slice().sort());
    assert.deepStrictEqual(moduleInventory.builtins, moduleInventory.builtins.slice().sort());
    const resourceInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
      "browser-resource-inventory.v1.json"), "utf8"));
    assert.strictEqual(resourceInventory.schema,
      "workbench-live-e2e.browser-resource-inventory.v1");
    assert.strictEqual(resourceInventory.files.length, 76);
    assert(resourceInventory.files.includes("modules/kshop/dev/harness.html"));
    assert(resourceInventory.files.includes("modules/kshop.js"));
    assert(resourceInventory.files.includes("css/panels.css"));
    assert.deepStrictEqual(resourceInventory.files, resourceInventory.files.slice().sort());
    const result = childProcess.spawnSync(process.execPath,
      [bootstrapPath], {
        cwd: PRODUCTION_ROOT,
        encoding: "utf8",
        windowsHide: true,
        timeout: 240000,
        maxBuffer: 32 * 1024 * 1024,
      });
    assert.strictEqual(result.error, undefined,
      result.error && result.error.message || "KShop browser harness process error");
    assert.strictEqual(result.status, 0, String(result.stderr || result.stdout));
    assert.strictEqual(result.stderr, "");
    const lines = String(result.stdout || "").split(/\r?\n/).filter(Boolean);
    assert.strictEqual(lines.length, 1, result.stdout);
    const receipt = JSON.parse(lines[0]);
    const receiptDigest = receipt.evidenceSha256;
    delete receipt.evidenceSha256;
    assert.strictEqual(sha256Text(canonicalJson(receipt)), receiptDigest);
    assert.strictEqual(receipt.schema, "workbench-live-e2e.kshop.browser-gate-receipt.v1");
    assert.strictEqual(receipt.status, "OFFLINE_VERIFIED");
    assert.strictEqual(receipt.moduleAdmission, "ADMITTED");
    assert.strictEqual(receipt.journalVerification, "VERIFIED");
    assert.strictEqual(receipt.moduleEntryCount, 363);
    assert.deepStrictEqual({passed:receipt.result.passed, total:receipt.result.total,
      failed:receipt.result.failed}, {passed:150, total:150, failed:0});
    assert.strictEqual(receipt.result.assertionIdsSha256,
      moduleInventory.expectedAssertionIdsSha256);
    assert(/^[a-f0-9]{64}$/.test(receipt.result.resultSha256));
    assert.strictEqual(receipt.result.filteredAssertions.length, 4);
    assert(receipt.result.filteredAssertions.every((entry) => entry.pass === true));
    assert.strictEqual(receipt.servedResourceClosure.schema,
      "workbench-live-e2e.browser-resource-closure-receipt.v1");
    assert.strictEqual(receipt.servedResourceClosure.resourceCount, 76);
    assert(receipt.servedResourceClosure.occurrenceCount >= 76);
    assert.strictEqual(receipt.servedResourceClosure.failureCount, 1);
    ["inventorySha256", "resourcesSha256", "occurrencesSha256", "failuresSha256",
      "evidenceSha256"].forEach((field) =>
      assert(/^[a-f0-9]{64}$/.test(receipt.servedResourceClosure[field]), field));
    const expectedRoute = runtimePhysicalBatches(240).concat([
      deepClone(FILTERED_COORDINATOR_REQUESTS),
    ]);
    ["kshop-filtered-checkout-surface", "kshop-filtered-claim-surface"].forEach((id) => {
      const executed = receipt.result.filteredAssertions.find((entry) => entry.id === id);
      const detail = JSON.parse(executed.detail);
      assert.deepStrictEqual(detail.requests, expectedRoute, id + " request route");
      assert.deepStrictEqual(detail.state.requests, FILTERED_COORDINATOR_REQUESTS,
        id + " visible requests");
      assert.deepStrictEqual(detail.state.physicalSurface, {
        schema: ProductionInventoryRuntime.physicalSurfaceSchema,
        accessibleCapacity: 240,
        responseCount: 3,
      }, id + " physical receipt");
    });
    ["kshop-filtered-checkout-view", "kshop-filtered-claim-view"].forEach((id) => {
      const executed = receipt.result.filteredAssertions.find((entry) => entry.id === id);
      assert.deepStrictEqual(JSON.parse(executed.detail), FILTERED_COORDINATOR_REQUESTS[1],
        id + " exact visible projection");
    });
    assert(/^[a-f0-9]{64}$/.test(receipt.manifestSha256));
    assert(/^[a-f0-9]{64}$/.test(receipt.moduleJournalSha256));
    browserGateReceipt = {
      schema:receipt.schema, evidenceSha256:receiptDigest,
      manifestSha256:receipt.manifestSha256,
      moduleJournalSha256:receipt.moduleJournalSha256,
      moduleEntryCount:receipt.moduleEntryCount,
      browserBinary:receipt.browserBinary,
      resourceClosureEvidenceSha256:receipt.servedResourceClosure.evidenceSha256,
      resourceCount:receipt.servedResourceClosure.resourceCount,
      occurrenceCount:receipt.servedResourceClosure.occurrenceCount,
      assertionIdsSha256:receipt.result.assertionIdsSha256,
      resultSha256:receipt.result.resultSha256,
    };
    assert(receipt.browserBinary && receipt.browserBinary.locator.startsWith("external:")
      && /^[a-f0-9]{64}$/.test(receipt.browserBinary.sha256)
      && Number.isInteger(receipt.browserBinary.bytes) && receipt.browserBinary.bytes > 0);
  });

  test("offline verifier independently admits A=0, A=120, and A=240 surfaces", () => {
    [0, 120, 240].forEach((accessibleCapacity) => {
      const receipt = verifyBundle(buildValidBundle({battleAccessibleCapacity: accessibleCapacity}));
      assert.deepStrictEqual(receipt.inventorySurfaces.map((surface) => ({
        accessibleCapacity: surface.accessibleCapacity,
        calls: surface.callIds.length,
      })), Array.from({length: 3}, () => ({accessibleCapacity,
        calls: runtimePhysicalBatches(accessibleCapacity).length})));
    });
  });

  test("offline fixture verifies without claiming live E2E", () => {
    const receipt = verifyBundle(buildValidBundle());
    assert.strictEqual(receipt.status, "OFFLINE_VERIFIED");
    assert.strictEqual(receipt.liveStatus, "LIVE_BLOCKED");
    assert.strictEqual(receipt.deployment, "NOT_DEPLOYED");
    assert.strictEqual(receipt.total, 1200);
    assert.strictEqual(receipt.panelInstances.length, 2);
    assert.strictEqual(receipt.hostMappings.length, 14);
    assert.strictEqual(receipt.observerContract.issuedCount, 14);
    assert.strictEqual(receipt.boundaries.physicalInputAttestation, false);
    assert.match(receipt.persistence.production.closureSha256, /^[a-f0-9]{64}$/);
    assert.match(receipt.persistence.production.firstLoadedSha256, /^[a-f0-9]{64}$/);
    assert.strictEqual(receipt.closeAcceptance.provenByProductionLog, true);
    assert.strictEqual(receipt.closeAcceptance.receipts.length, 2);
    assert.strictEqual(receipt.boundaries.providerOperationReceiptsVerified, true);
    assert.strictEqual(receipt.boundaries.captureSemanticContentIndependentlyVerified, false);
    assert.deepStrictEqual(receipt.controlEvidence.persisted,
      { requests: 9, acknowledgements: 9, providerReceipts: 9, captures: 2 });
    assert.strictEqual(receipt.controlEvidence.providerOperationIds.length, 9);
    assert.strictEqual(receipt.globalTimeline.schema,
      "workbench-live-e2e.kshop.global-timeline.v2");
    assert.deepStrictEqual(receipt.inventorySurfaces.map((surface) => ({
      phase: surface.phase,
      accessibleCapacity: surface.accessibleCapacity,
      callCount: surface.callIds.length,
    })), [
      {phase: "initial inventory", accessibleCapacity: 240, callCount: 3},
      {phase: "post-commit inventory", accessibleCapacity: 240, callCount: 3},
      {phase: "restart inventory", accessibleCapacity: 240, callCount: 3},
    ]);
    assert.ok(Date.parse(receipt.globalTimeline.first.commitResponseAt)
      < Date.parse(receipt.globalTimeline.first.postCommitReadbackStartedAt));
    assert.ok(Date.parse(receipt.globalTimeline.first.postCommitReadbackStartedAt)
      <= Date.parse(receipt.globalTimeline.first.postCommitReadbackSettledAt));
    assert.ok(Date.parse(receipt.globalTimeline.first.postCommitReadbackSettledAt)
      < Date.parse(receipt.globalTimeline.first.closeRequestAt));
    assert.ok(Date.parse(receipt.globalTimeline.restart.shutdownCompletedAt)
      <= Date.parse(receipt.globalTimeline.restart.cleanResidueAt));
    assert.ok(Date.parse(receipt.globalTimeline.first.safeExitActionAt)
      < Date.parse(receipt.globalTimeline.first.safeExitCaptureAt));
    assert.ok(Date.parse(receipt.globalTimeline.first.exitConfirmActionAt)
      < Date.parse(receipt.globalTimeline.first.exitConfirmCaptureAt));
    assert.strictEqual(new Set([receipt.selection.itemName, receipt.selection.displayName,
      receipt.selection.icon]).size, 3);
    assert.strictEqual(receipt.selection.deliveryContract.classification, "equipment");
    assert.strictEqual(receipt.selection.deliveryContract.destination, "backpack_first_vacancy");
    assert.strictEqual(receipt.catalogDeliveryBaseline.globalLowestPositiveSale.itemName,
      "觉醒晶体");
    assert.strictEqual(receipt.catalogDeliveryBaseline.globalLowestPositiveSale.price, 2);
    assert.strictEqual(receipt.catalogDeliveryBaseline.globalLowestPositiveSale.deliveryContract
      .destinationSurface, "collection.材料");
  });

  test("offline and live evidence modes have separate reachable receipt states", () => {
    assert.deepStrictEqual(receiptStateForEvidenceMode("offline_fixture"),
      { status: "OFFLINE_VERIFIED", liveStatus: "LIVE_BLOCKED" });
    assert.deepStrictEqual(receiptStateForEvidenceMode("live_capture"),
      { status: "e2e_verified", liveStatus: "E2E_VERIFIED" });
    assert.throws(() => receiptStateForEvidenceMode("verified"),
      (error) => error && error.code === "evidence_mode_invalid");
  });

  test("production surface inventory is the frozen 194-file current baseline", () => {
    const roles = Object.create(null);
    ProductionClosure.PRODUCTION_FILES.forEach((entry) => {
      roles[entry.role] = (roles[entry.role] || 0) + 1;
    });
    assert.strictEqual(ProductionClosure.PRODUCTION_FILES.length, 194);
    assert.deepStrictEqual(Object.assign({}, roles), {
      page: 1, overlay_script: 22, lazy_registry: 1, kshop_lazy_web: 17,
      style_entry: 7, style_import: 20, idle_prewarm_image: 15,
      css_conditional_asset: 4, font_pack_manifest: 1, icon_manifest: 1,
      host_composition: 1, host: 13,
      runtime_artifact_source: 1, runtime_input_descriptor: 1,
      runtime_producer_source: 9, runtime_toolchain_lock: 3,
      as2_manifest: 2, as2_source: 2, as2_dependency: 5, as2_swf: 1,
      kshop_data_manifest: 1, kshop_data: 13,
      item_data_manifest: 1, item_data: 52,
    });
    const closure = ProductionClosure.captureProductionClosure(PRODUCTION_ROOT,
      "2026-08-04T00:00:00.000Z");
    assert.strictEqual(closure.schema, "workbench-live-e2e.kshop.production-closure.v7");
    assert.deepStrictEqual(Object.keys(closure.semanticContracts),
      ["inventoryPhysicalSurface"]);
    assert.strictEqual(closure.semanticContracts.inventoryPhysicalSurface.schema,
      ProductionClosure.INVENTORY_SURFACE_CONTRACT_SCHEMA);
    assert.strictEqual(closure.semanticContracts.inventoryPhysicalSurface.sourceContract.schema,
      ProductionClosure.INVENTORY_SURFACE_SOURCE_SCHEMA);
    const delivery = ProductionClosure.verifyCatalogDeliveryContract(
      closure.declarations.catalogDeliveryContract);
    const sourceContract = ProductionClosure.verifyItemUtilDeliverySourceContract(
      delivery.itemUtilDeliverySourceContract);
    assert.deepStrictEqual(sourceContract,
      ProductionClosure.captureItemUtilDeliverySourceContract(PRODUCTION_ROOT));
    assert.strictEqual(sourceContract.schema,
      ProductionClosure.ITEMUTIL_DELIVERY_SOURCE_SCHEMA);
    assert.strictEqual(sourceContract.classifier, "ItemUtil.type-use-precedence.v1");
    assert.strictEqual(sourceContract.equipmentPoststate,
      "ArrayInventory.getVacancies.first-vacancy.v1");
    assert.strictEqual(sourceContract.semanticAnchorVersion,
      "kshop-itemutil-arrayinventory.semantic-anchor.v1");
    assert.strictEqual(sourceContract.tokenCanonicalization,
      "as2-function-lexical-token-stream.v1");
    assert.strictEqual(Object.keys(sourceContract.functionSha256).length, 7);
    assert.deepStrictEqual(Object.keys(sourceContract.functionSpans),
      Object.keys(sourceContract.functionSha256));
    assert.deepStrictEqual(Object.keys(sourceContract.functionTokenCount),
      Object.keys(sourceContract.functionSha256));
    assert.deepStrictEqual(Object.keys(sourceContract.functionTokenSha256),
      Object.keys(sourceContract.functionSha256));
    Object.values(sourceContract.functionSha256).forEach((hash) => {
      assert.match(hash, /^[A-Fa-f0-9]{64}$/);
    });
    Object.values(sourceContract.functionTokenSha256).forEach((hash) => {
      assert.match(hash, /^[A-Fa-f0-9]{64}$/);
    });
    Object.values(sourceContract.functionTokenCount).forEach((count) => {
      assert.ok(Number.isInteger(count) && count > 0);
    });
    assert.strictEqual(delivery.catalogEntryCount, 227);
    assert.deepStrictEqual(Object.assign({}, delivery.classificationCounts),
      { material: 19, mergeable: 32, equipment: 172, information: 4 });
    assert.deepStrictEqual({ index: delivery.globalLowestPositiveSale.catalogIndex,
      name: delivery.globalLowestPositiveSale.itemName,
      price: delivery.globalLowestPositiveSale.price,
      destination: delivery.globalLowestPositiveSale.deliveryContract.destinationSurface },
    { index: 3, name: "觉醒晶体", price: 2, destination: "collection.材料" });
    assert.deepStrictEqual({ index: delivery.lowestProvenPhysicalCandidate.catalogIndex,
      name: delivery.lowestProvenPhysicalCandidate.itemName,
      price: delivery.lowestProvenPhysicalCandidate.price,
      destination: delivery.lowestProvenPhysicalCandidate.deliveryContract.destinationSurface },
    { index: 79, name: "蓝色西式校服", price: 200,
      destination: "inventory.physical.背包" });
    const producer = ProductionClosure.currentProducerInputs(path.resolve(__dirname, "..", "..", ".."));
    assert.deepStrictEqual({ artifactSource: producer.domains.artifactSource.fileCount,
      producerRecipe: producer.domains.producerRecipe.fileCount,
      toolchainLock: producer.domains.toolchainLock.fileCount },
    { artifactSource: 297, producerRecipe: 9, toolchainLock: 3 });
    assert.match(producer.buildIdentityHash, /^[A-F0-9]{64}$/);
  });

  test("AS2 semantic token anchor cannot be supplied by its evidence contract", () => {
    const contract = deepClone(ProductionClosure.captureItemUtilDeliverySourceContract(
      PRODUCTION_ROOT));
    contract.functionTokenSha256.loadItemData = "f".repeat(64);
    delete contract.contractSha256;
    contract.contractSha256 = sha256Text(canonicalJson(contract));
    assert.throws(() => ProductionClosure.verifyItemUtilDeliverySourceContract(contract),
      (error) => error && error.code === "production_itemutil_delivery_source_contract_invalid");
  });

  test("AS2 semantic token anchor rejects string decoys and direct classifier drift", () => {
    withTemporaryDeliverySources(({ temporaryRoot, itemUtilPath, itemUtil }) => {
      const decoyItemUtil = itemUtil.replace(
        'else if(itemData.use === "材料") _materialDict[itemName] = true;',
        'else if(itemData.use === "材料漂移") { var deliveryMarkerDecoy:String = '
          + '\'elseif(itemData.use==="材料")_materialDict[itemName]=true;\'; }');
      assert.notStrictEqual(decoyItemUtil, itemUtil);
      fs.writeFileSync(itemUtilPath, decoyItemUtil, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);

      const driftedItemUtil = itemUtil.replace(
        'else if(itemData.use === "材料")', 'else if(itemData.use === "材料漂移")');
      assert.notStrictEqual(driftedItemUtil, itemUtil);
      fs.writeFileSync(itemUtilPath, driftedItemUtil, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);
    });
  });

  test("AS2 semantic token anchor rejects a correct classifier hidden in if(false)", () => {
    withTemporaryDeliverySources(({ temporaryRoot, itemUtilPath, itemUtil }) => {
      const anchor = '            if(itemData.type === "武器" || itemData.type === "防具") {';
      const driftAnchor
        = '            if(itemData.type === "武器漂移" || itemData.type === "防具漂移") {';
      let mutated = itemUtil.replace(anchor, driftAnchor)
        .replace('            else if(itemData.use === "材料") _materialDict[itemName] = true;',
          '            else if(itemData.use === "材料漂移") _materialDict[itemName] = true;')
        .replace('            else if(itemData.use === "情报") '
          + '_informationMaxValueDict[itemName] = itemData.maxvalue;',
        '            else if(itemData.use === "情报漂移") '
          + '_informationMaxValueDict[itemName] = itemData.maxvalue;');
      const deadBranch = [
        '            if(false) {',
        '                if(itemData.type === "武器" || itemData.type === "防具") {',
        '                    _equipmentDict[itemName] = true;',
        '                }',
        '                else if(itemData.use === "材料") _materialDict[itemName] = true;',
        '                else if(itemData.use === "情报") '
          + '_informationMaxValueDict[itemName] = itemData.maxvalue;',
        '            }',
      ].join("\n") + "\n";
      mutated = mutated.replace(driftAnchor, deadBranch + driftAnchor);
      assert.notStrictEqual(mutated, itemUtil);
      fs.writeFileSync(itemUtilPath, mutated, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);
    });
  });

  test("AS2 semantic token anchor rejects a numeric sort marker hidden in if(false)", () => {
    withTemporaryDeliverySources(({ temporaryRoot, arrayInventoryPath, arrayInventory }) => {
      const mutated = arrayInventory.replace("        indexArr.sort(Array.NUMERIC);",
        "        if(false) indexArr.sort(Array.NUMERIC);\n        indexArr.sort();");
      assert.notStrictEqual(mutated, arrayInventory);
      fs.writeFileSync(arrayInventoryPath, mutated, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);
    });
  });

  test("AS2 semantic token anchor rejects delivery call and comparison-operator drift", () => {
    withTemporaryDeliverySources(({ temporaryRoot, itemUtilPath, arrayInventoryPath,
      itemUtil, arrayInventory }) => {
      const callDrift = itemUtil.replace("背包.getVacancies(nonMergeableList.length)",
        "背包.getIndexes(nonMergeableList.length)");
      assert.notStrictEqual(callDrift, itemUtil);
      fs.writeFileSync(itemUtilPath, callDrift, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);

      fs.writeFileSync(itemUtilPath, itemUtil, "utf8");
      const comparisonDrift = arrayInventory.replace("if (idx <= last) return false;",
        "if (idx < last) return false;");
      assert.notStrictEqual(comparisonDrift, arrayInventory);
      fs.writeFileSync(arrayInventoryPath, comparisonDrift, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);
    });
  });

  test("AS2 token anchor ignores inline comments/spaces but binds line breaks and modifiers", () => {
    const baseline = ProductionClosure.captureItemUtilDeliverySourceContract(PRODUCTION_ROOT);
    withTemporaryDeliverySources(({ temporaryRoot, itemUtilPath, itemUtil }) => {
      const neutral = itemUtil.replace('if(itemData.type === "武器"',
        'if /* semantic-neutral */ (  itemData.type === "武器"');
      assert.notStrictEqual(neutral, itemUtil);
      fs.writeFileSync(itemUtilPath, neutral, "utf8");
      const accepted = ProductionClosure.captureItemUtilDeliverySourceContract(temporaryRoot);
      assert.notStrictEqual(accepted.functionSha256.loadItemData,
        baseline.functionSha256.loadItemData);
      assert.strictEqual(accepted.functionTokenSha256.loadItemData,
        baseline.functionTokenSha256.loadItemData);

      const restrictedLineBreak = itemUtil.replace("if(list == null) return false;",
        "if(list == null) return\n false;");
      assert.notStrictEqual(restrictedLineBreak, itemUtil);
      fs.writeFileSync(itemUtilPath, restrictedLineBreak, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);

      const modifierDrift = itemUtil.replace("public static function loadItemData",
        "private static function loadItemData");
      assert.notStrictEqual(modifierDrift, itemUtil);
      fs.writeFileSync(itemUtilPath, modifierDrift, "utf8");
      assertDeliveryAnchorReject(temporaryRoot);
    });
  });

  test("AS2 structural extraction rejects missing, duplicate, and nested function boundaries", () => {
    withTemporaryDeliverySources(({ temporaryRoot, itemUtilPath, itemUtil }) => {
      const missing = itemUtil.replace("function loadItemData(", "function loadItemDataMissing(");
      assert.notStrictEqual(missing, itemUtil);
      fs.writeFileSync(itemUtilPath, missing, "utf8");
      assertDeliveryAnchorReject(temporaryRoot, ["production_itemutil_delivery_source_invalid"]);

      const declaration = "public static function loadItemData(combinedData):Void{";
      const duplicate = itemUtil.replace(declaration,
        "public static function loadItemData():Void{}\n    " + declaration);
      assert.notStrictEqual(duplicate, itemUtil);
      fs.writeFileSync(itemUtilPath, duplicate, "utf8");
      assertDeliveryAnchorReject(temporaryRoot, ["production_itemutil_delivery_source_invalid"]);

      const requireDeclaration = "public static function require(itemArray:Array):Object {";
      const nested = itemUtil.replace(requireDeclaration,
        requireDeclaration + "\n        function nestedDeliveryBoundary():Void{}");
      assert.notStrictEqual(nested, itemUtil);
      fs.writeFileSync(itemUtilPath, nested, "utf8");
      assertDeliveryAnchorReject(temporaryRoot, ["production_itemutil_delivery_source_invalid"]);
    });
  });

  test("AS2 structural extraction requires the target itself at exact class-member depth", () => {
    withTemporaryDeliverySources(({ temporaryRoot, itemUtilPath, itemUtil }) => {
      const span = ProductionClosure.extractAs2Function(PRODUCTION_ROOT,
        "scripts/类定义/org/flashNight/arki/item/ItemUtil.as", "loadItemData");
      const declaration = itemUtil.slice(span.start, span.end);
      assert.ok(declaration.startsWith("public static function loadItemData"));
      function replaceDeclaration(replacement) {
        return itemUtil.slice(0, span.start) + replacement + itemUtil.slice(span.end);
      }

      const outerFunction = replaceDeclaration(
        "public static function adversarialWrapper():Void {\n" + declaration + "\n}");
      fs.writeFileSync(itemUtilPath, outerFunction, "utf8");
      assertDeliveryAnchorReject(temporaryRoot, ["production_itemutil_delivery_source_invalid"]);

      const conditional = replaceDeclaration("if(false) {\n" + declaration + "\n}");
      fs.writeFileSync(itemUtilPath, conditional, "utf8");
      assertDeliveryAnchorReject(temporaryRoot, ["production_itemutil_delivery_source_invalid"]);

      const extraBlock = replaceDeclaration("{\n" + declaration + "\n}");
      fs.writeFileSync(itemUtilPath, extraBlock, "utf8");
      assertDeliveryAnchorReject(temporaryRoot, ["production_itemutil_delivery_source_invalid"]);

      const classExternal = itemUtil.slice(0, span.start) + itemUtil.slice(span.end)
        + "\n" + declaration + "\n";
      fs.writeFileSync(itemUtilPath, classExternal, "utf8");
      assertDeliveryAnchorReject(temporaryRoot, ["production_itemutil_delivery_source_invalid"]);
    });
  });

  test("production-isomorphic open allows Shop and Inventory sends before either response", () => {
    const bundle = buildValidBundle();
    const records = bundle.hostLog.lifecycles[0].terminalSnapshot.records;
    const shopSend = records.findIndex((entry) => entry.line.includes("[ShopTask] -> Flash:")
      && entry.line.includes("cmd=shopBulkQuery"));
    const inventorySend = records.findIndex((entry) => entry.line.includes("[InventoryTask] -> Flash:")
      && entry.line.includes("cmd=inventorySnapshot"));
    const shopResponse = records.findIndex((entry) => entry.line.includes("task=shop_response")
      && entry.line.includes("cmd=shopBulkQuery"));
    assert.ok(shopSend >= 0 && inventorySend > shopSend && shopResponse > inventorySend);
    assert.strictEqual(verifyBundle(bundle).status, "OFFLINE_VERIFIED");
  });

  test("post-write stack catalog preserves its production technical maximum", () => {
    const bundle = buildValidBundle();
    const events = bundle.transcript.events;
    const initial = findEvent(events, "webview_message", "bulkQuery", PANEL_ONE);
    const commit = findEvent(events, "webview_message", "checkoutCommit", PANEL_ONE);
    assert.strictEqual(initial.message.catalog[0].maxQuantity, 999999);
    assert.strictEqual(commit.message.catalog[0].maxQuantity, 999999);
    assert.strictEqual(verifyBundle(bundle).status, "OFFLINE_VERIFIED");
  });

  test("formatter-equivalent fixture uses real serialized lengths and recursive refs", () => {
    const bundle = buildValidBundle();
    const lines = bundle.hostLog.lifecycles[0].terminalSnapshot.records.map((entry) => entry.line);
    const requestEvent = findEvent(bundle.transcript.events, "bridge_send", "checkoutCommit", PANEL_ONE);
    const request = requestEvent.message;
    const panelLine = lines.find((line) => line.includes("[Panel] HandlePanelMessage:")
      && line.includes("cmd=checkoutCommit"));
    assert.ok(panelLine.includes("len=" + requestEvent.wirePayloadLength));
    assert.ok(lines.some((line) => line.includes("task=inventory_response")
      && /slotLeaseRef(?:s)?=sha256_[a-f0-9]{24}/.test(line)));
  });

  test("direct verifier, runner, and self-test entrypoints are NOT_ADMITTED", () => {
    ["verify-live-journey.js", "run-live-journey.js", "self-test.js"].forEach((name) => {
      const result = childProcess.spawnSync(process.execPath, [path.join(__dirname, name), "--check"],
        { cwd: path.resolve(__dirname, "..", "..", ".."), encoding: "utf8", windowsHide: true });
      assert.strictEqual(result.status, 2, name);
      assert.match(String(result.stderr), /NOT_ADMITTED/);
    });
  });

  test("bootstrap control modes reject mixed live arguments before admission", () => {
    const bootstrap = path.join(__dirname, "bootstrap.js");
    [
      ["--candidate-root", "X", "--check"],
      ["--help", "--candidate-root", "X"],
      ["--verify-bundle", "X", "--check"],
    ].forEach((argv) => {
      const result = childProcess.spawnSync(process.execPath, [bootstrap].concat(argv),
        { cwd: path.resolve(__dirname, "..", "..", ".."), encoding: "utf8", windowsHide: true });
      assert.strictEqual(result.status, 2, argv.join(" "));
      assert.match(String(result.stderr), /exact and cannot be mixed/);
    });
  });

  test("module admission is canonical while saves remain fixture-owned", () => {
    const bundle = buildValidBundle();
    assert.notStrictEqual(bundle.moduleAdmission.manifest.root.toLowerCase(), bundle.root.toLowerCase());
    assert.strictEqual(bundle.moduleAdmission.journal.admissionStatus, "ADMITTED");
    assert.deepStrictEqual(bundle.moduleAdmission.manifest.requiredPhases,
      ["domain_loaded", "audit_executed", "terminal"]);
    const locators = bundle.moduleAdmission.manifest.entries.map((entry) => entry.locator);
    ["root:tools/workbench-live-e2e/kshop/self-test.js",
      "root:tools/workbench-live-e2e/kshop/fixtures/valid-bundle.js",
      "root:launcher/web/modules/panel-runtime.js",
      "external:" + path.resolve(process.execPath).replace(/\\/g, "/")].forEach((locator) => {
      assert.strictEqual(locators.includes(locator), true, locator);
    });
    const nodeEntry = bundle.moduleAdmission.manifest.entries.find((entry) =>
      entry.role === "external_node_binary");
    const nodeBytes = fs.readFileSync(process.execPath);
    assert.deepStrictEqual(nodeEntry && {
      locator:nodeEntry.locator, loadable:nodeEntry.loadable, preexisting:nodeEntry.preexisting,
      bytes:nodeEntry.bytes, sha256:nodeEntry.sha256,
    }, {
      locator:"external:" + path.resolve(process.execPath).replace(/\\/g, "/"),
      loadable:false, preexisting:false, bytes:nodeBytes.length,
      sha256:sha256Bytes(nodeBytes),
    });
    assert.deepStrictEqual(bundle.moduleAdmission.journal.checkpoints.map((entry) => entry.phase),
      ["domain_loaded", "audit_executed"]);
    assert.strictEqual(bundle.moduleAdmission.journal.seal.phase, "terminal");
    assert.ok(bundle.moduleAdmission.journal.checkpoints[1].eventCount
      >= bundle.moduleAdmission.journal.checkpoints[0].eventCount);
  });

  test("complete visible fixture PNG decodes to bounded pixel evidence", () => {
    const decoded = decodePng(createSolidPngForFixture(320, 180, [1, 2, 3, 255]),
      "self_test_png");
    assert.strictEqual(decoded.width, 320);
    assert.strictEqual(decoded.height, 180);
    assert.strictEqual(decoded.decodedBytes, 320 * 180 * 4);
    assert.match(decoded.pixelSha256, /^[a-f0-9]{64}$/);
  });

  test("canonical verifier fully validates fixture admission and emits one JSON document", () => {
    const bundle = buildValidBundle();
    const bundlePath = path.join(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "canonical-verify-input.json");
    const receiptPath = path.join(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "canonical-verify-receipt.json");
    fs.writeFileSync(bundlePath, JSON.stringify(bundle, null, 2) + "\n", "utf8");
    const result = childProcess.spawnSync(process.execPath,
      [path.join(__dirname, "bootstrap.js"), "--verify-bundle", bundlePath,
        "--receipt", receiptPath], {
        cwd: path.resolve(__dirname, "..", "..", ".."), encoding: "utf8",
        windowsHide: true, maxBuffer: 32 * 1024 * 1024,
      });
    assert.strictEqual(result.status, 0, String(result.stderr || result.stdout));
    const parsed = JSON.parse(String(result.stdout || ""));
    assert.strictEqual(parsed.receipt.status, "OFFLINE_VERIFIED");
    assert.strictEqual(parsed.verificationAdmission, "ADMITTED");
    assert.deepStrictEqual(parsed.verificationPhases,
      ["domain_loaded", "verification_executed", "terminal"]);
    assert.strictEqual(String(result.stderr || ""), "");
    assert.strictEqual(fs.existsSync(receiptPath), true);
  });

  test("canonical verifier fails before checkpoint/seal output on an invalid bundle", () => {
    const bundle = buildValidBundle();
    bundle.status = "failed_closed";
    refreshRawManifest(bundle);
    const directory = path.join(bundle.root, bundle.runDir.replace(/\//g, path.sep));
    const bundlePath = path.join(directory, "canonical-invalid-input.json");
    const receiptPath = path.join(directory, "canonical-invalid-receipt.json");
    fs.writeFileSync(bundlePath, JSON.stringify(bundle, null, 2) + "\n", "utf8");
    const result = childProcess.spawnSync(process.execPath,
      [path.join(__dirname, "bootstrap.js"), "--verify-bundle", bundlePath,
        "--receipt", receiptPath], {
        cwd: path.resolve(__dirname, "..", "..", ".."), encoding: "utf8",
        windowsHide: true, maxBuffer: 32 * 1024 * 1024,
      });
    assert.strictEqual(result.status, 1);
    assert.strictEqual(String(result.stdout || ""), "");
    assert.match(String(result.stderr || ""), /bundle status is outside/);
    assert.strictEqual(fs.existsSync(receiptPath), false);
  });

  test("token redaction is idempotent", () => {
    const ref = tokenRef("secret");
    assert.strictEqual(redactOpaqueTokens({ checkoutToken: ref }).checkoutToken, ref);
    assert.strictEqual(redactOpaqueTokens({ checkoutToken: "secret" }).checkoutToken, ref);
    assert.strictEqual(redactOpaqueTokens({ slotLease: "secret" }).slotLease, ref);
  });

  test("control ack is reference-only and capture ownership stays with provider", () => {
    const bundle = buildValidBundle();
    const request = validateRequest(bundle.controlRequests.find((entry) => entry.step === "safe_exit"));
    const ack = bundle.controlAcks.find((entry) => entry.requestId === request.requestId);
    assert.strictEqual(validateAck(ack, request), ack);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(ack, "capture"), false);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(ack, "captureSha256"), false);
    const detached = Object.assign({}, ack);
    delete detached.providerReceiptRef;
    assert.throws(() => validateAck(detached, request),
      (error) => error && error.code === "control_ack_domain_binding_invalid");
  });

  test("offline fixture provider receipt is an independent request-bound operation", () => {
    const bundle = buildValidBundle();
    const { request, ack, receiptPath } = providerReceiptRecord(bundle, "safe_exit");
    const receipt = JSON.parse(fs.readFileSync(receiptPath, "utf8"));
    assert.strictEqual(validateProviderReceipt(receipt, request, "offline_fixture"), receipt);
    assert.notStrictEqual(receipt.operationId, request.requestId);
    assert.strictEqual(receipt.operationId, ack.providerReceiptRef.operationId);
    assert.deepStrictEqual(receipt.operationEvents.map((entry) => entry.kind),
      ["provider_started", "action_completed", "capture_created", "provider_completed"]);
    assert.ok(Date.parse(request.issuedAt) < Date.parse(receipt.operationEvents[0].occurredAt));
    assert.ok(receipt.operationEvents.every((entry, index, events) => index === 0
      || Date.parse(events[index - 1].occurredAt) < Date.parse(entry.occurredAt)));
    assert.deepStrictEqual(receipt.capture.eventRef, {
      eventId: receipt.operationEvents[2].eventId,
      eventSha256: receipt.operationEvents[2].eventSha256,
    });
    assert.strictEqual(receipt.operationEvents.at(-1).occurredAt, ack.completedAt);
    assert.deepStrictEqual(receipt.capture,
      bundle.controlCaptures.find((entry) => entry.relativePath === receipt.capture.relativePath));
    assert.strictEqual(Object.prototype.hasOwnProperty.call(ack, "capture"), false);
  });

  test("ack writer references provider-prewritten bytes and rejects a foreign receipt path", () => {
    const fixture = buildValidBundle();
    const ownedBase = path.join(fixture.root, "tmp", "workbench-live-e2e", "kshop");
    fs.mkdirSync(ownedBase, { recursive: true });
    const runDir = fs.mkdtempSync(path.join(ownedBase, "ack-writer-"));
    const channel = new ControlChannel(fixture.root, runDir);
    function issue(step) {
      return channel.issue(step, { runId: "ack-writer-run",
        allowedTransports: ["codex_computer_use"], timeoutMs: 60000,
        instructions: "fixture", selectors: [], expectedIndependentEvidence: [],
        domainIntent: { action: step, browserSequenceStart: 0, expectedWebCommands: [] } });
    }
    function prewrite(request, operationId) {
      const startedAt = new Date(Date.parse(request.issuedAt) + 10).toISOString();
      const actionAt = new Date(Date.parse(request.issuedAt) + 20).toISOString();
      const completedAt = new Date(Date.parse(request.issuedAt) + 30).toISOString();
      const requestBytes = fs.readFileSync(path.join(channel.requestsDir, request.requestId + ".json"));
      function event(sequence, kind, occurredAt, evidence) {
        const value = { schema: PROVIDER_EVENT_SCHEMA, sequence,
          eventId: operationId + ".event." + sequence, kind, occurredAt,
          operationId, requestId: request.requestId, evidence };
        value.eventSha256 = providerEventSha256(value);
        return value;
      }
      const operationEvents = [
        event(1, "provider_started", startedAt, { kind: "provider_operation_started" }),
        event(2, "action_completed", actionAt, { kind: "provider_tool_result_action",
          issuer: "openai.codex.computer-use",
          toolResultSource: "codex_computer_use.tool_result", operationId,
          action: request.domainIntent.action }),
        event(3, "provider_completed", completedAt,
          { kind: "provider_operation_completed", result: "completed" }),
      ];
      const receipt = { schema: PROVIDER_RECEIPT_SCHEMA, operationId,
        issuer: "openai.codex.computer-use",
        toolResultSource: "codex_computer_use.tool_result",
        transport: "codex_computer_use", requestId: request.requestId,
        runId: request.runId, step: request.step, action: request.domainIntent.action,
        result: "completed", startedAt, completedAt,
        requestBindingSha256: sha256Text(canonicalJson(request)),
        requestArtifact: { relativePath: "control/requests/" + request.requestId + ".json",
          sha256: sha256Bytes(requestBytes), bytes: requestBytes.length },
        inputObservation: null, operationEvents, capture: null };
      receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
      const receiptPath = path.join(channel.providerReceiptsDir, request.requestId + ".json");
      fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2) + "\n", "utf8");
      return receiptPath;
    }
    const first = issue("open_kshop");
    const firstPath = prewrite(first, "provider-prewritten-operation-one");
    const before = sha256Bytes(fs.readFileSync(firstPath));
    const written = writeAck(fixture.root, runDir, first.requestId, {
      transport: "codex_computer_use", result: "completed",
      providerReceiptFile: firstPath, authorizationDecisionId: null,
    });
    assert.strictEqual(sha256Bytes(fs.readFileSync(firstPath)), before);
    assert.strictEqual(written.ack.providerReceiptRef.sha256, before);
    const second = issue("add_selected_item");
    assert.throws(() => writeAck(fixture.root, runDir, second.requestId, {
      transport: "codex_computer_use", result: "completed",
      providerReceiptFile: firstPath, operationId: "inline-self-report",
    }), (error) => error && error.code === "control_ack_input_invalid");
    assert.throws(() => writeAck(fixture.root, runDir, second.requestId, {
      transport: "codex_computer_use", result: "completed",
      providerReceiptFile: firstPath, captureFile: null,
      captureSha256: null, authorizationDecisionId: null,
    }), (error) => error && error.code === "control_ack_input_invalid");
  });

  test("WebView debug environment is launch-scoped", () => {
    const oldArgs = process.env.CF7_WEBVIEW2_ARGS;
    const oldMode = process.env.CF7_WEBVIEW2_DEV_MODE;
    delete process.env.CF7_WEBVIEW2_ARGS;
    delete process.env.CF7_WEBVIEW2_DEV_MODE;
    try {
      withWebViewDebugEnvironment(19333, () => {
        assert.strictEqual(process.env.CF7_WEBVIEW2_ARGS, "--remote-debugging-port=19333");
        assert.strictEqual(process.env.CF7_WEBVIEW2_DEV_MODE, "1");
      });
      assert.strictEqual(process.env.CF7_WEBVIEW2_ARGS, undefined);
      assert.strictEqual(process.env.CF7_WEBVIEW2_DEV_MODE, undefined);
    } finally {
      if (oldArgs === undefined) delete process.env.CF7_WEBVIEW2_ARGS;
      else process.env.CF7_WEBVIEW2_ARGS = oldArgs;
      if (oldMode === undefined) delete process.env.CF7_WEBVIEW2_DEV_MODE;
      else process.env.CF7_WEBVIEW2_DEV_MODE = oldMode;
    }
  });

  test("actual production PanelRequestMux emits onIssued before observed Bridge.send", () => {
    const priorWindow = global.window;
    const priorDocument = global.document;
    const priorLocation = global.location;
    const emitted = [];
    const originalRequest = ProductionPanelRuntime.PanelRequestMux.prototype.request;
    const fakeDocument = {
      getElementById() { return null; },
      addEventListener() {},
      removeEventListener() {},
    };
    const fakeWindow = {
      PanelRuntime: ProductionPanelRuntime,
      Bridge: { send() { return true; } },
      UiData: { dispatch() { return true; } },
      chrome: { webview: { addEventListener() {}, removeEventListener() {} } },
      __fixtureEmit(payload) { emitted.push(JSON.parse(payload)); },
    };
    global.window = fakeWindow;
    global.document = fakeDocument;
    global.location = { href: "https://overlay.local/overlay.html" };
    try {
      const installed = browserInjectionSource()({
        bindingName: "__fixtureEmit",
        markerName: "__fixturePassiveObserver",
      });
      assert.strictEqual(installed.panelRequestMuxWrapped, true);
      const mux = new ProductionPanelRuntime.PanelRequestMux({
        send(message) { return fakeWindow.Bridge.send(message); },
        setTimer() { return 1; },
        clearTimer() {},
        timeoutMs: 1000,
        callPrefix: "wb",
        sessionNonce: "fixture",
        createMessage(context) {
          return { type: "panel", panel: "kshop",
            panelInstanceId: context.session.panelInstanceId,
            cmd: context.entry.cmd, callId: context.entry.callId };
        },
      });
      assert.strictEqual(mux.openSession({ ownerPanel: "kshop",
        panelInstanceId: "panel_fixture_real_mux" }), true);
      mux.request("bulkQuery", {}, { metadata: { channel: "shop" } }, () => {});
      const flow = emitted.filter((event) => ["panel_request_issued", "bridge_send"]
        .includes(event.kind));
      assert.deepStrictEqual(flow.map((event) => event.kind),
        ["panel_request_issued", "bridge_send"]);
      assert.strictEqual(flow[0].callId, flow[1].message.callId);
      assert.strictEqual(flow[0].metadata.channel, "shop");
      fakeWindow.__fixturePassiveObserver.uninstall();
      assert.strictEqual(ProductionPanelRuntime.PanelRequestMux.prototype.request, originalRequest);
    } finally {
      ProductionPanelRuntime.PanelRequestMux.prototype.request = originalRequest;
      if (priorWindow === undefined) delete global.window;
      else global.window = priorWindow;
      if (priorDocument === undefined) delete global.document;
      else global.document = priorDocument;
      if (priorLocation === undefined) delete global.location;
      else global.location = priorLocation;
    }
  });

  expectFailure("raw bundle tamper is rejected first", (bundle) => {
    bundle.selection.total += 1;
  }, "raw_bundle_manifest_mismatch", { refreshManifest: false });

  expectFailure("offline fixture cannot relabel itself live", (bundle) => {
    bundle.evidenceMode = "live_capture";
    bundle.status = "captured_unverified";
  }, "live_capture_root_invalid");

  expectFailure("unknown bundle status is rejected", (bundle) => {
    bundle.status = "verified";
  }, "bundle_status_invalid");

  expectFailure("raw checkout token is rejected", (bundle) => {
    const preview = bundle.transcript.events.find((event) => event.kind === "webview_message"
      && event.message && event.message.cmd === "checkoutPreview");
    preview.message.checkoutToken = "plaintext-capability";
  }, "raw_token_in_public_evidence");

  expectFailure("event-chain tamper is rejected", (bundle) => {
    bundle.transcript.events[3].observedAt = "tampered";
  }, "transcript_chain_invalid");

  expectFailure("Codex fallback requires explicit authorization", (bundle) => {
    bundle.authorization.codexFallbackAllowed = false;
  }, "capability_fallback_invalid");

  expectFailure("capability source cannot be operator asserted", (bundle) => {
    bundle.authorization.launcherAgentRuntime.source = "operator_ack";
  }, "capability_evidence_untrusted");

  expectFailure("capability list is bound to the authenticated session", (bundle) => {
    bundle.authorization.launcherAgentRuntime.observedCapabilities.push("computer.use.kshop");
  }, "capability_contract_invalid");

  expectFailure("acknowledgement cannot carry inline provider-like details", (bundle) => {
    bundle.controlAcks[0].details = { operationId: "self-reported" };
  }, ["control_ack_invalid", "control_ack_domain_binding_invalid"]);

  expectFailure("provider receipt provenance cannot be operator asserted", (bundle) =>
    rewriteProviderReceipt(bundle, "open_kshop", (receipt) => {
      receipt.issuer = "operator";
      receipt.toolResultSource = "manual-note";
      refreshProviderOperationEvents(receipt);
    }), "provider_receipt_provenance_invalid");

  expectFailure("provider receipt must bind the exact request bytes", (bundle) =>
    rewriteProviderReceipt(bundle, "open_kshop", (receipt) => {
      receipt.requestBindingSha256 = "f".repeat(64);
    }), "provider_receipt_invalid");

  expectFailure("provider request artifact digest must bind the exact pretty-printed bytes", (bundle) =>
    rewriteProviderReceipt(bundle, "open_kshop", (receipt) => {
      receipt.requestArtifact.sha256 = "f".repeat(64);
    }), "provider_request_artifact_invalid");

  expectFailure("provider start must be strictly later than request issuance", (bundle) => {
    rewriteControlExchange(bundle, "open_kshop", ({ request, provider }) => {
      provider.startedAt = request.issuedAt;
    });
  }, "provider_receipt_invalid");

  expectFailure("provider operation event set cannot omit the action", (bundle) =>
    rewriteProviderReceipt(bundle, "open_kshop", (receipt) => {
      receipt.operationEvents.splice(1, 1);
    }), "provider_operation_event_set_invalid");

  expectFailure("provider operation event ids cannot be duplicated", (bundle) =>
    rewriteProviderReceipt(bundle, "open_kshop", (receipt) => {
      receipt.operationEvents[1].eventId = receipt.operationEvents[0].eventId;
      receipt.operationEvents[1].eventSha256 = providerEventSha256(receipt.operationEvents[1]);
    }), "provider_operation_event_set_invalid");

  expectFailure("provider operation events cannot be reordered", (bundle) =>
    rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      [receipt.operationEvents[1], receipt.operationEvents[2]]
        = [receipt.operationEvents[2], receipt.operationEvents[1]];
    }), "provider_operation_event_invalid");

  expectFailure("provider DOM tuple must bind the exact passive event hash", (bundle) =>
    rewriteProviderReceipt(bundle, "add_selected_item", (receipt) => {
      receipt.inputObservation.eventRef.eventSha256 = "f".repeat(64);
      refreshProviderOperationEvents(receipt);
    }), "provider_dom_observation_binding_invalid");

  expectFailure("provider DOM facts cannot drift from viewport and hit-tested target", (bundle) =>
    rewriteProviderReceipt(bundle, "open_checkout", (receipt) => {
      receipt.inputObservation.viewport.width += 1;
    }), "provider_dom_observation_binding_invalid");

  expectFailure("one passive close event cannot be reused outside the restart provider timeline", (bundle) => {
    const firstClose = bundle.controlProviderReceipts.find((entry) => entry.step === "close_kshop");
    return rewriteProviderReceipt(bundle, "restart_readback_close_kshop", (receipt) => {
      receipt.inputObservation = deepClone(firstClose.inputObservation);
      refreshProviderOperationEvents(receipt);
    });
  }, "provider_operation_event_timeline_invalid");

  expectFailure("provider completion must encompass its exact DOM observation", (bundle) => {
    rewriteControlExchange(bundle, "add_selected_item", ({ provider }) => {
      provider.completedAt = new Date(Date.parse(provider.inputObservation.observedAt) - 1).toISOString();
    });
  }, "provider_operation_event_timeline_invalid");

  expectFailure("provider operation id cannot be reused across steps", (bundle) => {
    const firstRecord = providerReceiptRecord(bundle, "open_kshop");
    const firstReceipt = JSON.parse(fs.readFileSync(firstRecord.receiptPath, "utf8"));
    return rewriteProviderReceipt(bundle, "add_selected_item", (receipt) => {
      receipt.operationId = firstReceipt.operationId;
      receipt.operationEvents.forEach((event, index) => {
        event.operationId = receipt.operationId;
        event.eventId = receipt.operationId + ".event." + (index + 1);
      });
      refreshProviderOperationEvents(receipt);
    });
  }, "provider_operation_id_reused");

  expectFailure("persisted request bytes must equal the bundle request array", (bundle) => {
    const request = bundle.controlRequests[0];
    const filePath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "control", "requests", request.requestId + ".json");
    const original = fs.readFileSync(filePath);
    fs.writeFileSync(filePath, Buffer.concat([original, Buffer.from(" ")]));
    return () => fs.writeFileSync(filePath, original);
  }, "control_request_bytes_mismatch");

  expectFailure("persisted acknowledgement bytes must equal the bundle ack array", (bundle) => {
    const ack = bundle.controlAcks[0];
    const filePath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "control", "acks", ack.requestId + ".json");
    const original = fs.readFileSync(filePath);
    fs.writeFileSync(filePath, Buffer.concat([original, Buffer.from(" ")]));
    return () => fs.writeFileSync(filePath, original);
  }, "control_ack_bytes_mismatch");

  expectFailure("bundle provider receipt array must equal its persisted receipt", (bundle) => {
    bundle.controlProviderReceipts[0].issuer = "bundle-only-forgery";
  }, "provider_receipt_bundle_mismatch");

  expectFailure("bundle capture array must equal the provider-owned reference", (bundle) => {
    bundle.controlCaptures[0] = deepClone(bundle.controlCaptures[0]);
    bundle.controlCaptures[0].decoded.height += 1;
  }, "provider_capture_bundle_mismatch");

  expectFailure("current request bytes must equal the final persisted request", (bundle) => {
    const filePath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "control", "current-request.json");
    const original = fs.readFileSync(filePath);
    fs.writeFileSync(filePath, JSON.stringify(bundle.controlRequests[0], null, 2) + "\n", "utf8");
    return () => fs.writeFileSync(filePath, original);
  }, "control_current_request_bytes_mismatch");

  expectFailure("provider owns the exact request-named capture path", (bundle) =>
    rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      receipt.capture.relativePath = "control/captures/foreign.png";
      refreshProviderOperationEvents(receipt);
    }), "provider_capture_reference_invalid");

  expectFailure("provider capture decoded dimensions bind the exact PNG bytes", (bundle) =>
    rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      receipt.capture.decoded.width += 1;
    }), "provider_capture_digest_invalid");

  expectFailure("provider capture cannot precede the trusted action", (bundle) =>
    rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      const actionAt = Date.parse(receipt.operationEvents[1].occurredAt);
      receipt.capture.capturedAt = new Date(actionAt - 1).toISOString();
      refreshProviderOperationEvents(receipt);
    }), "provider_operation_event_timeline_invalid");

  expectFailure("provider capture cannot follow provider completion", (bundle) =>
    rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      receipt.capture.capturedAt = new Date(Date.parse(receipt.completedAt) + 1).toISOString();
      refreshProviderOperationEvents(receipt);
    }), "provider_operation_event_timeline_invalid");

  expectFailure("provider capture event reference cannot drift from the sealed event", (bundle) =>
    rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      receipt.capture.eventRef.eventSha256 = "f".repeat(64);
    }), "provider_capture_event_binding_invalid");

  expectFailure("stale PNG file time cannot be relabelled as a fresh provider capture", (bundle) => {
    const provider = bundle.controlProviderReceipts.find((entry) => entry.step === "safe_exit");
    const capturePath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      provider.capture.relativePath.replace(/\//g, path.sep));
    const originalStat = fs.statSync(capturePath);
    const stale = new Date(Date.parse(provider.capture.capturedAt) - 5000);
    fs.utimesSync(capturePath, stale, stale);
    const restoreProvider = rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      receipt.capture.fileModifiedAt = fs.statSync(capturePath).mtime.toISOString();
    });
    return () => {
      restoreProvider();
      fs.utimesSync(capturePath, originalStat.atime, originalStat.mtime);
    };
  }, "provider_capture_digest_invalid");

  expectFailure("control evidence directories reject undeclared persisted artifacts", (bundle) => {
    const filePath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      "control", "acks", "undeclared.json");
    fs.writeFileSync(filePath, "{}\n", "utf8");
    return () => fs.unlinkSync(filePath);
  }, "control_ack_directory_invalid");

  expectFailure("reference-only ack rejects an inline capture shadow", (bundle) => {
    const ack = bundle.controlAcks.find((entry) => entry.step === "safe_exit");
    ack.capture = deepClone(bundle.controlProviderReceipts.find((entry) =>
      entry.step === "safe_exit").capture);
    persistAck(bundle, ack);
  }, "control_ack_domain_binding_invalid");

  test("one-pixel PNG magic bytes cannot satisfy visible capture evidence", () => {
    const bytes = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
      + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
    assert.throws(() => decodePng(bytes, "self_test_png"),
      (error) => error && error.code === "capture_png_geometry_invalid");
  });

  expectFailure("full bundle rejects a one-pixel staged capture after all hash rebinding", (bundle) => {
    const ack = bundle.controlAcks.find((entry) => entry.step === "safe_exit");
    const provider = bundle.controlProviderReceipts.find((entry) => entry.step === "safe_exit");
    const capturePath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
      provider.capture.relativePath.replace(/\//g, path.sep));
    const originalCapture = fs.readFileSync(capturePath);
    const originalStat = fs.statSync(capturePath);
    const bytes = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
      + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
    fs.writeFileSync(capturePath, bytes);
    const captureMoment = new Date(provider.capture.capturedAt);
    fs.utimesSync(capturePath, captureMoment, captureMoment);
    provider.capture.sha256 = sha256Bytes(bytes);
    provider.capture.bytes = bytes.length;
    provider.capture.fileModifiedAt = fs.statSync(capturePath).mtime.toISOString();
    const restoreProvider = rewriteProviderReceipt(bundle, "safe_exit", (receipt) => {
      receipt.capture = deepClone(provider.capture);
      refreshProviderOperationEvents(receipt);
    });
    const captureIndex = bundle.controlCaptures.findIndex((entry) =>
      entry.relativePath === provider.capture.relativePath);
    bundle.controlCaptures[captureIndex] = deepClone(provider.capture);
    return () => {
      fs.writeFileSync(capturePath, originalCapture);
      fs.utimesSync(capturePath, originalStat.atime, originalStat.mtime);
      restoreProvider();
    };
  }, "capture_png_geometry_invalid");

  test("PNG bytes after IEND are rejected", () => {
    const bytes = createSolidPngForFixture(320, 180, [4, 5, 6, 255]);
    assert.throws(() => decodePng(Buffer.concat([bytes, Buffer.from([0])]), "self_test_png"),
      (error) => error && error.code === "capture_png_trailing_bytes");
  });

  test("PNG chunk CRC is verified before pixel admission", () => {
    const bytes = Buffer.from(createSolidPngForFixture(320, 180, [7, 8, 9, 255]));
    bytes[32] ^= 0x01;
    assert.throws(() => decodePng(bytes, "self_test_png"),
      (error) => error && error.code === "capture_png_crc_invalid");
  });

  expectFailure("dynamic selection cannot be replaced by a fixed index", (bundle) => {
    bundle.selection.catalogIndex = 17;
  }, "catalog_selection_mismatch");

  expectFailure("a newly cheaper authoritative item invalidates stale selection", (bundle) => {
    reseal(bundle, (events) => {
      const response = findEvent(events, "webview_message", "bulkQuery", PANEL_ONE);
      response.message.catalog.push({ idx: 1, item: "更低价物品", displayname: "更低价物品",
        icon: "手枪通用弹药", type: "fixture-equipment-shop", majorType: "防具",
        subType: "上装装备", price: 1, level: 1, maxQuantity: 1 });
    });
  }, "catalog_selection_mismatch");

  expectFailure("A3 positive selection cannot collapse internal and display identity", (bundle) => {
    reseal(bundle, (events) => {
      const bulk = findEvent(events, "webview_message", "bulkQuery", PANEL_ONE).message;
      const selected = bulk.catalog.find((entry) => entry.idx === bundle.selection.catalogIndex);
      selected.displayname = selected.item;
      bundle.selection = chooseCatalogSelection(bulk.catalog, bulk.kpoints,
        bulk.playerLevel, bulk.reverseLevel);
    });
  }, "identity_triple_not_distinct");

  expectFailure("level-locked catalog entry cannot be selected", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "bulkQuery", PANEL_ONE)
        .message.catalog.find((entry) => entry.idx === bundle.selection.catalogIndex).level = 999;
    });
  }, "catalog_selection_unavailable");

  expectFailure("business domain injection is rejected", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "bridge_send", "checkoutPreview", PANEL_ONE).message.domain = "inventory";
    });
  }, "shop_domain_invalid");

  expectFailure("owner-mismatched response is rejected", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "bulkQuery", PANEL_ONE)
        .message.panelInstanceId = "panel_foreign";
    });
  }, "response_count_invalid");

  expectFailure("missing production onIssued receipt is rejected", (bundle) => {
    reseal(bundle, (events) => {
      const index = events.findIndex((event) => event.kind === "panel_request_issued"
        && event.cmd === "checkoutPreview");
      events.splice(index, 1);
    });
  }, "panel_request_issue_multiset_invalid");

  expectFailure("onIssued must immediately precede Bridge.send", (bundle) => {
    reseal(bundle, (events) => {
      const index = events.findIndex((event) => event.kind === "panel_request_issued"
        && event.cmd === "checkoutPreview");
      events.splice(index + 1, 0, { kind: "observer_note", value: "gap" });
    });
  }, "panel_request_issue_order_invalid");

  expectFailure("observer may expose no business action methods", (bundle) => {
    reseal(bundle, (events) => {
      events.find((event) => event.kind === "observer_ready")
        .businessActionMethods = ["click"];
    });
  }, "observer_passive_contract_invalid");

  expectFailure("explicit Web-call-to-fid binding is mandatory", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const index = records.findIndex((record) => record.line.includes(
        "event=authority_flash_call_bound domain=shop")
        && record.line.includes("cmd=checkoutCommit"));
      records.splice(index, 1);
    });
  }, "host_flash_binding_count_invalid");

  expectFailure("Host route cannot be duplicated", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const index = records.findIndex((entry) => hostBody(entry.line)
        === "[Panel] Routing cmd=checkoutCommit to ShopTask, _shopTask=ok");
      records.splice(index + 1, 0, deepClone(records[index]));
    });
  }, "host_route_count_invalid");

  expectFailure("Host route closed fields reject trailing data", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const record = records.find((entry) => hostBody(entry.line)
        === "[Panel] Routing cmd=checkoutCommit to ShopTask, _shopTask=ok");
      record.line += " extra=true";
    });
  }, "host_route_invalid");

  expectFailure("binding owner cannot drift", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const record = records.find((entry) => entry.line.includes("cmd=checkoutCommit action="));
      record.line = record.line.replace("panelInstanceId=panel_fixture_kshop_1",
        "panelInstanceId=panel_foreign");
    });
  }, "host_flash_binding_count_invalid");

  expectFailure("explicit dispatch binding cannot be duplicated", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const index = records.findIndex((entry) => entry.line.includes(
        "cmd=checkoutCommit action=shopCheckoutCommit"));
      records.splice(index + 1, 0, deepClone(records[index]));
    });
  }, "host_flash_binding_count_invalid");

  expectFailure("binding closed fields reject trailing data", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const record = records.find((entry) => hostBody(entry.line).startsWith(
        "event=authority_flash_call_bound"));
      record.line += " extra=true";
    });
  }, "host_flash_binding_invalid");

  expectFailure("binding fid must equal the redacted send fid", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const record = records.find((entry) => entry.line.includes("cmd=checkoutCommit action="));
      record.line = record.line.replace("flashCallId=4", "flashCallId=99");
    });
  }, "host_flash_send_missing");

  expectFailure("same-fid Flash response is required", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const record = records.find((entry) => hostBody(entry.line).startsWith("[XmlSocket:JSON]")
        && entry.line.includes("callId=4"));
      record.line = record.line.replace("callId=4", "callId=99");
    });
  }, "host_flash_roundtrip_invalid");

  expectFailure("Flash response command must equal the bound action", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const record = records.find((entry) => hostBody(entry.line).startsWith("[XmlSocket:JSON]")
        && entry.line.includes("callId=4"));
      record.line = record.line.replace("cmd=shopCheckoutCommit", "cmd=shopBulkQuery");
    });
  }, "host_flash_roundtrip_invalid");

  expectFailure("Shop response consumer receipt is required", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const commitResponse = records.findIndex((entry) => hostBody(entry.line).startsWith("[XmlSocket:JSON]")
        && entry.line.includes("callId=4"));
      const receipt = records.findIndex((entry, index) => index > commitResponse
        && hostBody(entry.line) === "[ShopTask] <- Flash response received");
      records.splice(receipt, 1);
    });
  }, "host_shop_response_receipt_invalid");

  expectFailure("untrusted selected-item click is rejected", (bundle) => {
    reseal(bundle, (events) => {
      const click = events.find((event) => event.kind === "dom_input"
        && event.target && event.target.attributes
        && event.target.attributes["data-idx"] === "37");
      click.isTrusted = false;
    });
  }, "trusted_business_input_invalid");

  expectFailure("right-button or hidden-owner business input is rejected", (bundle) => {
    reseal(bundle, (events) => {
      const click = events.find((event) => event.kind === "dom_input"
        && event.target && event.target.attributes
        && event.target.attributes["data-idx"] === "37");
      click.button = 2;
      click.panelState.hidden = true;
    });
  }, "trusted_business_input_invalid");

  expectFailure("trusted click coordinates must land inside the observed target rectangle", (bundle) => {
    reseal(bundle, (events) => {
      const click = events.find((event) => event.kind === "dom_input"
        && event.target && event.target.selector === "#kshop-checkout");
      click.clientX = click.target.rect.right + 1;
    });
  }, "trusted_business_input_invalid");

  expectFailure("hidden or disabled target geometry cannot attest a business click", (bundle) => {
    reseal(bundle, (events) => {
      const click = events.find((event) => event.kind === "dom_input"
        && event.target && event.target.attributes
        && event.target.attributes["data-kshop-settlement-commit"] !== undefined);
      click.target.visible = false;
      click.target.enabled = false;
    });
  }, "trusted_business_input_invalid");

  expectFailure("target rectangle dimensions must close exactly", (bundle) => {
    reseal(bundle, (events) => {
      const click = events.find((event) => event.kind === "dom_input"
        && event.target && event.target.attributes
        && event.target.attributes["data-idx"] === "37");
      click.target.rect.width += 1;
    });
  }, "trusted_business_input_invalid");

  expectFailure("an extra KShop key input is rejected from the exact input set", (bundle) => {
    reseal(bundle, (events) => {
      const commit = events.findIndex((event) => isMessage(
        event, "bridge_send", "checkoutCommit", PANEL_ONE));
      events.splice(commit, 0, { kind: "dom_input", eventType: "keydown", direction: "input",
        isTrusted: true, key: "Enter", repeat: false,
        target: { selector: "#kshop-checkout", tagName: "BUTTON", text: "结算",
          attributes: { id: "kshop-checkout" } },
        panelState: { panel: "kshop", hidden: false } });
    });
  }, "trusted_business_input_multiset_invalid");

  expectFailure("duplicate commit click is rejected", (bundle) => {
    reseal(bundle, (events) => {
      const index = events.findIndex((event) => isMessage(
        event, "bridge_send", "checkoutCommit", PANEL_ONE));
      const click = deepClone(events[index - 2]);
      events.splice(index - 1, 0, click);
    });
  }, "commit_click_count_invalid");

  expectFailure("missing saveCart is rejected", (bundle) => {
    reseal(bundle, (events) => {
      for (let index = events.length - 1; index >= 0; index -= 1) {
        if (events[index].message && events[index].message.cmd === "saveCart") events.splice(index, 1);
      }
    });
  }, ["kshop_command_multiset_invalid", "panel_request_issue_multiset_invalid"]);

  expectFailure("commit preview token mismatch is rejected", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "bridge_send", "checkoutCommit", PANEL_ONE)
        .message.expectedCheckoutToken = tokenRef("wrong-token");
    });
  }, "commit_token_mismatch");

  expectFailure("missing preview checkout token is rejected", (bundle) => {
    reseal(bundle, (events) => {
      delete findEvent(events, "webview_message", "checkoutPreview", PANEL_ONE)
        .message.checkoutToken;
    });
  }, "authority_token_missing");

  expectFailure("missing commit expected checkout token is rejected", (bundle) => {
    reseal(bundle, (events) => {
      delete findEvent(events, "bridge_send", "checkoutCommit", PANEL_ONE)
        .message.expectedCheckoutToken;
      const issued = events.find((event) => event.kind === "panel_request_issued"
        && event.cmd === "checkoutCommit");
      delete issued.message.expectedCheckoutToken;
    });
  }, "authority_token_missing");

  expectFailure("missing initial purchased token is rejected", (bundle) => {
    reseal(bundle, (events) => {
      delete findEvent(events, "webview_message", "bulkQuery", PANEL_ONE)
        .message.purchasedToken;
    });
  }, "authority_token_missing");

  expectFailure("checkout and purchased capabilities cannot collapse", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutPreview", PANEL_ONE)
        .message.checkoutToken = findEvent(events, "webview_message", "bulkQuery", PANEL_ONE)
          .message.purchasedToken;
      findEvent(events, "bridge_send", "checkoutCommit", PANEL_ONE)
        .message.expectedCheckoutToken = findEvent(events, "webview_message", "bulkQuery", PANEL_ONE)
          .message.purchasedToken;
      const issued = events.find((event) => event.kind === "panel_request_issued"
        && event.cmd === "checkoutCommit");
      issued.message.expectedCheckoutToken = findEvent(events, "webview_message", "bulkQuery", PANEL_ONE)
        .message.purchasedToken;
    });
  }, "authority_token_reused");

  expectFailure("zero capacity cannot remain committable", (bundle) => {
    reseal(bundle, (events) => {
      const line = findEvent(events, "webview_message", "checkoutPreview", PANEL_ONE)
        .message.purchaseLines[0];
      line.maxByCapacity = 0;
      line.maxPurchasable = 0;
    });
  }, "purchase_line_mismatch");

  expectFailure("maxAffordable must be recomputed from the whole-order balance", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutPreview", PANEL_ONE)
        .message.purchaseLines[0].maxAffordable = 2;
    });
  }, "purchase_line_mismatch");

  expectFailure("maxPurchasable must equal the minimum authority bound", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutPreview", PANEL_ONE)
        .message.purchaseLines[0].maxPurchasable = 2;
    });
  }, "purchase_line_mismatch");

  expectFailure("post-write dynamic maxQuantity cannot exceed the pre-write bound", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutCommit", PANEL_ONE)
        .message.catalog.find((entry) => entry.idx === bundle.selection.catalogIndex).maxQuantity = 4;
    });
  }, "catalog_identity_mismatch");

  expectFailure("restart dynamic maxQuantity must equal the item-family postcondition", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "bulkQuery", PANEL_TWO)
        .message.catalog.find((entry) => entry.idx === bundle.selection.catalogIndex).maxQuantity = 2;
    });
  }, "catalog_identity_mismatch");

  runV83InventoryPhaseRegressionTests();

  expectFailure("Inventory request cannot truncate the 50-slot backpack surface", (bundle) => {
    reseal(bundle, (events) => {
      const bridge = findEvent(events, "bridge_send", "snapshot", PANEL_ONE);
      const callId = bridge.message.callId;
      events.filter((event) => ["panel_request_issued", "bridge_send"].includes(event.kind)
        && event.message && event.message.callId === callId)
        .forEach((event) => { event.message.payload.requests[0].limit = 49; });
    });
  }, "inventory_surface_order_invalid");

  expectFailure("Inventory response cannot omit backpack physical slot 49", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseSnapshots(events, "initial", "背包")[0].slots.pop();
    });
  }, "inventory_snapshot_invalid");

  expectFailure("Inventory request classification precedes a simultaneously truncated response", (bundle) => {
    reseal(bundle, (events) => {
      const bridge = findEvent(events, "bridge_send", "snapshot", PANEL_ONE);
      const callId = bridge.message.callId;
      events.filter((event) => ["panel_request_issued", "bridge_send"].includes(event.kind)
        && event.message && event.message.callId === callId)
        .forEach((event) => { event.message.payload.requests[0].limit = 49; });
      inventoryPhaseSnapshots(events, "initial", "背包")[0].slots.pop();
    });
  }, "inventory_surface_order_invalid");

  expectFailure("Inventory response cannot hide the declared battlebox tail", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseSnapshots(events, "initial", "战备箱").at(-1).slots.pop();
    });
  }, "inventory_snapshot_invalid");

  expectFailure("Inventory battlebox capacity cannot expand beyond the production tier set", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseSnapshots(events, "initial", "战备箱")[0].accessibleCapacity = 280;
    });
  }, "inventory_battle_access_invalid");

  expectFailure("Inventory callback response rejects a top-level extra field", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseResponses(events, "initial")[0].message.unexpected = true;
    });
  }, "inventory_surface_order_invalid");

  expectFailure("Inventory callback response rejects a missing panel identity", (bundle) => {
    reseal(bundle, (events) => {
      delete inventoryPhaseResponses(events, "initial")[0].message.panel;
    });
  }, "response_count_invalid");

  expectFailure("Inventory callback response rejects a missing non-identity field", (bundle) => {
    reseal(bundle, (events) => {
      delete inventoryPhaseResponses(events, "initial")[0].message.v;
    });
  }, "inventory_surface_order_invalid");

  expectFailure("Inventory callback response rejects a missing snapshots field", (bundle) => {
    reseal(bundle, (events) => {
      delete inventoryPhaseResponses(events, "initial")[0].message.snapshots;
    });
  }, "inventory_surface_order_invalid");

  expectFailure("Inventory callback response rejects a missing battlebox window", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseResponses(events, "initial")[0].message.snapshots.pop();
    });
  }, "inventory_battle_access_invalid");

  expectFailure("Inventory callback response rejects a foreign panel", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseResponses(events, "initial")[0].message.panel = "npcshop";
    });
  }, "response_count_invalid");

  expectFailure("Inventory callback response rejects a duplicate exact response", (bundle) => {
    reseal(bundle, (events) => {
      const response = inventoryPhaseResponses(events, "initial")[0];
      const index = events.indexOf(response);
      assert.ok(index >= 0, "fixture Inventory response must belong to the event list");
      events.splice(index + 1, 0, deepClone(response));
    });
  }, "response_count_invalid");

  expectFailure("Inventory response pairing precedes a simultaneous envelope shape error", (bundle) => {
    reseal(bundle, (events) => {
      const response = inventoryPhaseResponses(events, "initial")[0].message;
      delete response.panel;
      response.unexpected = true;
    });
  }, "response_count_invalid");

  expectFailure("Inventory battlebox A cannot drift between one phase's probe and supplement", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseSnapshots(events, "initial", "战备箱")[1].accessibleCapacity = 200;
    });
  }, "inventory_snapshot_invalid");

  expectFailure("Inventory battlebox supplemental metadata cannot drift", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseSnapshots(events, "post", "战备箱")[1].pageSizeHint = 39;
    });
  }, "inventory_snapshot_invalid");

  expectFailure("Inventory tail item and lease cannot drift across the commit", (bundle) => {
    reseal(bundle, (events) => {
      const tail = inventoryPhaseSlot(events, "post", "战备箱", 239).slot;
      tail.slotLease = "sha256:" + "d".repeat(64);
      tail.item.enhancementLevel += 1;
      tail.confirmProjection.enhancementLevel += 1;
    });
  }, "inventory_physical_delta_invalid");

  expectFailure("Inventory phase rejects an extra complete request-response pair", (bundle) => {
    reseal(bundle, (events) => {
      const sourceResponse = inventoryPhaseResponses(events, "post").at(-1);
      const sourceCallId = sourceResponse.message.callId;
      const sourceEntries = events.filter((event) => event.message
        && event.message.callId === sourceCallId
        && ["panel_request_issued", "bridge_send", "webview_message"].includes(event.kind));
      assert.strictEqual(sourceEntries.length, 3);
      const closeIndex = events.findIndex((event) => isMessage(
        event, "bridge_send", "close", PANEL_ONE));
      const duplicates = sourceEntries.map((event) => {
        const copy = deepClone(event);
        copy.message.callId = sourceCallId + ".extra";
        return copy;
      });
      events.splice(closeIndex, 0, ...duplicates);
    });
  }, "inventory_surface_pair_set_invalid");

  expectFailure("Inventory container profile cannot drift after commit", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseSnapshots(events, "post", "背包")[0].pageSizeHint = 49;
    });
  }, "inventory_snapshot_invalid");

  expectFailure("delivered identity mismatch is rejected", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutCommit", PANEL_ONE)
        .message.delivered[0].displayName = "near-match";
    });
  }, "purchase_line_mismatch");

  expectFailure("money postcondition mismatch is rejected", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutCommit", PANEL_ONE)
        .message.newBalance += 1;
    });
  }, "commit_response_invalid");

  expectFailure("preview balance must equal the initial authoritative balance", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutPreview", PANEL_ONE)
        .message.balance -= 1;
    });
  }, "preview_response_invalid");

  expectFailure("missing post-commit inventory refresh is rejected", (bundle) => {
    reseal(bundle, (events) => {
      const callIds = new Set(inventoryPhaseResponses(events, "post")
        .map((event) => event.message.callId));
      assert.ok(callIds.size > 0, "fixture requires a complete post-commit Inventory phase");
      for (let index = events.length - 1; index >= 0; index -= 1) {
        if (events[index].message && callIds.has(events[index].message.callId)) {
          events.splice(index, 1);
        }
      }
    });
  }, "inventory_surface_pair_set_invalid");

  expectFailure("collateral inventory delta is rejected", (bundle) => {
    reseal(bundle, (events) => {
      const collateral = inventoryPhaseSlot(events, "post", "背包", 20).slot;
      collateral.item.quantity = 10;
      collateral.confirmProjection.quantity = 10;
    });
  }, "inventory_collateral_delta_invalid");

  expectFailure("post-commit collateral slot move is rejected even when identity counts match", (bundle) => {
    reseal(bundle, (events) => {
      const slots = inventoryPhaseSnapshots(events, "post", "背包")[0].slots;
      const moved = slots[20];
      const empty = slots[21];
      slots[20] = Object.assign({}, empty, { physicalSlot: 20 });
      slots[21] = Object.assign({}, moved, { physicalSlot: 21 });
    });
  }, "inventory_physical_delta_invalid");

  expectFailure("post-commit non-target lease drift is rejected", (bundle) => {
    reseal(bundle, (events) => {
      inventoryPhaseSlot(events, "post", "战备箱", 2).slot.slotLease
        = "sha256:" + "e".repeat(64);
    });
  }, "inventory_revision_or_lease_rule_invalid");

  expectFailure("post/restart cannot synchronize delivery into the battlebox", (bundle) => {
    reseal(bundle, (events) => relocateFixtureDelivery(events, 1, 3));
  }, "inventory_delivery_target_invalid");

  expectFailure("post/restart cannot synchronize delivery into the wrong backpack vacancy", (bundle) => {
    reseal(bundle, (events) => relocateFixtureDelivery(events, 0, 1));
  }, "inventory_delivery_target_invalid");

  test("ItemUtil delivery precedence excludes collection material from the physical proof surface", () => {
    const material = classifyCatalogDelivery({ majorType: "收集品", subType: "材料" });
    assert.strictEqual(material.authorityItemKind, "stack");
    assert.strictEqual(material.destinationSurface, "collection.材料");
    assert.strictEqual(material.executableJourneyEligible, false);
    const equipment = classifyCatalogDelivery({ majorType: "防具", subType: "上装装备" });
    assert.strictEqual(equipment.authorityItemKind, "equipment");
    assert.strictEqual(equipment.destination, "backpack_first_vacancy");
    assert.strictEqual(equipment.executableJourneyEligible, true);
    assert.strictEqual(equipment.verifierPoststate,
      "complete_50_slot_backpack_physical_delta");
  });

  test("dynamic selection skips the cheaper collection material and binds the equipment contract", () => {
    const bundle = buildValidBundle();
    const bulk = findEvent(bundle.transcript.events, "webview_message", "bulkQuery", PANEL_ONE).message;
    const selected = chooseCatalogSelection(bulk.catalog, bulk.kpoints,
      bulk.playerLevel, bulk.reverseLevel);
    assert.strictEqual(bulk.catalog[0].price, 2);
    assert.strictEqual(bulk.catalog[0].subType, "材料");
    assert.strictEqual(selected.catalogIndex, 37);
    assert.strictEqual(selected.deliveryContract.authorityItemKind, "equipment");
    assert.strictEqual(selected.deliveryContract.destination, "backpack_first_vacancy");
  });

  expectFailure("purchase line item kind must equal the selected delivery contract", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "checkoutPreview", PANEL_ONE)
        .message.purchaseLines[0].itemKind = "stack";
    });
  }, "purchase_line_mismatch");

  expectFailure("equipment delivery cannot be rewritten as a same-identity stack merge", (bundle) => {
    reseal(bundle, (events) => {
      const initialBag = inventoryPhaseSnapshots(events, "initial", "背包")[0];
      const postBag = inventoryPhaseSnapshots(events, "post", "背包")[0];
      const delivered = deepClone(postBag.slots[0]);
      const prior = deepClone(delivered);
      prior.slotLease = tokenRef("fixture.merge.prior.0");
      prior.confirmProjection.lastUpdate = 0;
      initialBag.slots[0] = deepClone(prior);
      postBag.slots[0] = deepClone(prior);
      delivered.physicalSlot = 2;
      postBag.slots[2] = delivered;
      setOccupiedFacetCount(initialBag, 2);
      setOccupiedFacetCount(postBag, 3);
      mirrorPostCommitInventoryToRestart(events);
    });
  }, "inventory_delivery_target_invalid");

  expectFailure("restart physical slot semantics must equal the post-commit projection", (bundle) => {
    reseal(bundle, (events) => {
      const slots = inventoryPhaseSnapshots(events, "restart", "背包")[0].slots;
      const moved = slots[20];
      const empty = slots[21];
      slots[20] = Object.assign({}, empty, { physicalSlot: 20 });
      slots[21] = Object.assign({}, moved, { physicalSlot: 21 });
    });
  }, "restart_inventory_slot_or_lease_invalid");

  expectFailure("same-instance restart is rejected", (bundle) => {
    reseal(bundle, (events) => {
      events.forEach((event) => {
        if (!event.message) return;
        if (event.message.panelInstanceId === PANEL_TWO) event.message.panelInstanceId = PANEL_ONE;
        if (event.message.initData && event.message.initData.panelInstanceId === PANEL_TWO) {
          event.message.initData.panelInstanceId = PANEL_ONE;
        }
      });
    });
  }, "kshop_instance_inventory_invalid");

  expectFailure("restart readback cannot write", (bundle) => {
    reseal(bundle, (events) => {
      const closeIndex = events.findIndex((event) => isMessage(event, "bridge_send", "close", PANEL_TWO));
      const request = { type: "panel", panel: "kshop", panelInstanceId: PANEL_TWO,
        cmd: "checkoutCommit", callId: "wb.fixture.hidden.commit", v: 1,
        expectedCheckoutToken: tokenRef("hidden") };
      events.splice(closeIndex, 0,
        { kind: "panel_request_issued", direction: "outbound", callId: request.callId,
          cmd: request.cmd, metadata: {}, message: request },
        { kind: "bridge_send", direction: "outbound", message: request });
    });
  }, "kshop_command_multiset_invalid");

  expectFailure("restart balance mismatch is rejected", (bundle) => {
    reseal(bundle, (events) => {
      findEvent(events, "webview_message", "bulkQuery", PANEL_TWO).message.kpoints -= 1;
    });
  }, "restart_bulk_readback_invalid");

  expectFailure("each lifecycle terminal observer detach boundary is mandatory", (bundle) => {
    reseal(bundle, (events) => {
      const index = events.findIndex((event) => event.kind === "observer_detached");
      events.splice(index, 1);
    });
  }, ["loaded_terminal_detach_boundary_invalid", "restart_observer_boundary_missing"]);

  expectFailure("first owner close must be an exact trusted click", (bundle) => {
    reseal(bundle, (events) => {
      const close = events.find((event) => event.kind === "dom_input"
        && event.target && event.target.attributes
        && event.target.attributes["data-header-action"] === "close");
      close.isTrusted = false;
    });
  }, "trusted_business_input_invalid");

  expectFailure("a close rejection in the authenticated Host tail blocks the journey", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const close = records.findIndex((entry) => entry.line.includes("cmd=close"));
      records.splice(close + 1, 0, timestampLike(records[close],
        "[InventoryTask] rejected stale/malformed owner close envelope"));
    });
  }, "host_authority_rejection_observed");

  expectFailure("an extra replay record cannot hide in the relevant Host set", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const index = records.findIndex((entry) => entry.line.includes("cmd=checkoutCommit"));
      records.splice(index + 1, 0, timestampLike(records[index],
        "[ShopTask] duplicate/replayed callId ignored: wb.injected.replay"));
    });
  }, "host_relevant_record_unknown");

  expectFailure("Web payload growth cannot retain a stale Host request length", (bundle) => {
    reseal(bundle, (events) => {
      const bridge = findEvent(events, "bridge_send", "saveCart", PANEL_ONE);
      const issued = events.find((event) => event.kind === "panel_request_issued"
        && event.callId === bridge.message.callId);
      bridge.message.injected = true;
      issued.message.injected = true;
    });
  }, "host_panel_payload_length_mismatch");

  expectFailure("normalized Flash payload length cannot drift", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const send = records.find((entry) => entry.line.includes("[ShopTask] -> Flash:")
        && entry.line.includes("cmd=shopSaveCart"));
      send.line = send.line.replace(/len=(\d+)/, (_match, value) => "len=" + (Number(value) + 1));
    });
  }, "host_flash_payload_length_mismatch");

  expectFailure("socket payload length cannot drift from the sanitized response", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const response = records.find((entry) => entry.line.includes(
        "[XmlSocket:JSON] task=shop_response cmd=shopSaveCart"));
      response.line = response.line.replace(/len=(\d+)/,
        (_match, value) => "len=" + (Number(value) + 1));
    });
  }, "host_socket_payload_length_mismatch");

  expectFailure("bulk socket length cannot use a large lower-bound surrogate", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const response = records.find((entry) => entry.line.includes(
        "[XmlSocket:JSON] task=shop_response cmd=shopBulkQuery"));
      response.line = response.line.replace(/len=(\d+)/,
        (_match, value) => "len=" + (Number(value) + 100000));
    });
  }, "host_socket_payload_length_mismatch");

  expectFailure("commit socket length cannot use a large lower-bound surrogate", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const response = records.find((entry) => entry.line.includes(
        "[XmlSocket:JSON] task=shop_response cmd=shopCheckoutCommit"));
      response.line = response.line.replace(/len=(\d+)/,
        (_match, value) => "len=" + (Number(value) + 100000));
    });
  }, "host_socket_payload_length_mismatch");

  expectFailure("an exact close completion receipt cannot be omitted", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const index = records.findIndex((entry) => hostBody(entry.line).startsWith(
        "event=panel_exact_close_completed"));
      records.splice(index, 1);
    });
  }, "host_exact_close_receipt_multiset_invalid");

  expectFailure("an exact close completion receipt cannot name a foreign owner", (bundle) => {
    resealHost(bundle, "restart", (records) => {
      const receipt = records.find((entry) => hostBody(entry.line).startsWith(
        "event=panel_exact_close_completed"));
      receipt.line = receipt.line.replace(PANEL_TWO, PANEL_ONE);
    });
  }, "host_exact_close_receipt_count_invalid");

  expectFailure("an exact close completion receipt cannot precede PanelHost close", (bundle) => {
    resealHost(bundle, "restart", (records) => {
      const receiptIndex = records.findIndex((entry) => hostBody(entry.line).startsWith(
        "event=panel_exact_close_completed"));
      const receipt = records.splice(receiptIndex, 1)[0];
      const closeIndex = records.findIndex((entry) => hostBody(entry.line)
        === "[PanelHost] closed: kshop");
      records.splice(closeIndex, 0, receipt);
    });
  }, ["host_exact_close_order_invalid", "host_log_clock_regressed"]);

  expectFailure("first lifecycle completion receipt must precede the archive seal", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const receiptIndex = records.findIndex((entry) => hostBody(entry.line).startsWith(
        "event=panel_exact_close_completed"));
      const receipt = records.splice(receiptIndex, 1)[0];
      const archiveIndex = records.findIndex((entry) => hostBody(entry.line).startsWith(
        "[ArchiveTask] Shadow saved:"));
      records.splice(archiveIndex + 1, 0, receipt);
    });
  }, ["host_terminal_tail_invalid", "host_log_clock_regressed"]);

  expectFailure("near-match authority response family is never invisible", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const response = records.findIndex((entry) => entry.line.includes("task=shop_response"));
      records.splice(response + 1, 0, timestampLike(records[response],
        "[XmlSocket:JSON] task=authority_response_family envelope=near_match payload=redacted len=99"));
    });
  }, "host_socket_summary_invalid");

  expectFailure("restart PID reuse is rejected", (bundle) => {
    bundle.runtime.restart.identity.pid = bundle.runtime.first.identity.pid;
  }, "restart_pid_invalid");

  expectFailure("CDP listener ancestry must contain authenticated PID", (bundle) => {
    bundle.runtime.restart.cdpBinding.attestation.ancestorPids = [5200, 9999];
  }, "cdp_runtime_binding_invalid");

  expectFailure("transcript page content hash must equal its runtime binding", (bundle) => {
    reseal(bundle, (events) => {
      events.find((event) => event.kind === "cdp_endpoint_bound").pageContentSha256 = "f".repeat(64);
    });
  }, "cdp_transcript_binding_invalid");

  expectFailure("actually loaded production bytes must match the frozen current tree", (bundle) => {
    bundle.runtime.first.loadedProduction.page.sha256 = "f".repeat(64);
    refreshEvidenceSha(bundle.runtime.first.loadedProduction);
  }, "loaded_production_resource_mismatch");

  expectFailure("raw executable occurrences reject one foreign module", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const extra = deepClone(loaded.rawScriptOccurrences.at(-1));
    extra.occurrence = loaded.rawScriptOccurrences.length + 1;
    extra.scriptId = "fixture-foreign-script";
    extra.url = "https://overlay.local/modules/inventory-workbench.js";
    extra.urlOrigin = "https://overlay.local";
    loaded.rawScriptOccurrences.push(extra);
    refreshEvidenceSha(loaded);
  }, "loaded_production_executable_occurrence_invalid");

  expectFailure("raw executable occurrence order cannot be normalized after capture", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    [loaded.rawScriptOccurrences[0], loaded.rawScriptOccurrences[1]]
      = [loaded.rawScriptOccurrences[1], loaded.rawScriptOccurrences[0]];
    loaded.rawScriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
    refreshEvidenceSha(loaded);
  }, "loaded_production_executable_occurrence_invalid");

  expectFailure("raw executable occurrences reject a duplicate expected URL", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const duplicate = deepClone(loaded.productionScriptOccurrences[0]);
    duplicate.occurrence = loaded.rawScriptOccurrences.length + 1;
    duplicate.scriptId = "fixture-duplicate-production-script";
    loaded.rawScriptOccurrences.push(duplicate);
    refreshEvidenceSha(loaded);
  }, "loaded_production_executable_occurrence_invalid");

  expectFailure("anonymous executable occurrences cannot be filtered away", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const foreign = deepClone(loaded.rawScriptOccurrences.at(-1));
    foreign.occurrence = loaded.rawScriptOccurrences.length + 1;
    foreign.scriptId = "fixture-anonymous-foreign";
    foreign.url = "";
    foreign.urlOrigin = "opaque";
    loaded.rawScriptOccurrences.push(foreign);
    refreshEvidenceSha(loaded);
  }, "loaded_production_executable_occurrence_invalid");

  expectFailure("observer-owned evaluation source hash must equal its raw occurrence", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    loaded.ownedEvaluations[0].sha256 = "f".repeat(64);
    refreshEvidenceSha(loaded);
  }, "loaded_owned_evaluation_mismatch");

  expectFailure("terminal loaded plan cannot omit the observer detach source", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const detached = loaded.ownedEvaluations.pop();
    loaded.rawScriptOccurrences = loaded.rawScriptOccurrences.filter((entry) =>
      entry.url !== detached.url);
    loaded.rawScriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
    refreshEvidenceSha(loaded);
  }, "loaded_terminal_detach_occurrence_invalid");

  expectFailure("terminal loaded plan cannot append a second detach source", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const evaluation = deepClone(loaded.ownedEvaluations.at(-1));
    evaluation.sequence = loaded.ownedEvaluations.length + 1;
    evaluation.url = "cf7-evidence://kshop/0002-observer-detach.js";
    loaded.ownedEvaluations.push(evaluation);
    const occurrence = deepClone(loaded.rawScriptOccurrences.at(-1));
    occurrence.occurrence = loaded.rawScriptOccurrences.length + 1;
    occurrence.scriptId = "fixture-second-detach-source";
    occurrence.url = evaluation.url;
    loaded.rawScriptOccurrences.push(occurrence);
    refreshEvidenceSha(loaded);
  }, "loaded_terminal_detach_occurrence_invalid");

  expectFailure("actual-loaded production script multiset rejects a duplicate", (bundle) => {
    bundle.runtime.first.loadedProduction.scripts.push(
      deepClone(bundle.runtime.first.loadedProduction.scripts[0]));
    refreshEvidenceSha(bundle.runtime.first.loadedProduction);
  }, "loaded_production_multiset_invalid");

  test("actual-loaded evidence retains full context auxData and non-stylesheet resources", () => {
    const loaded = buildValidBundle().runtime.first.loadedProduction;
    assert.strictEqual(loaded.rawExecutionContextOccurrences[0].auxData.type, "default");
    assert.strictEqual(loaded.rawExecutionContextOccurrences[0].auxData.isDefault, true);
    assert.ok(loaded.rawResourceOccurrences.some((entry) => entry.type === "Document"));
    assert.ok(loaded.rawResourceOccurrences.some((entry) => entry.type === "Stylesheet"));
  });

  test("source-derived base-map WebP prewarm resources are admitted exactly", () => {
    const bundle = buildValidBundle();
    const loaded = bundle.runtime.first.loadedProduction;
    const expected = ProductionClosure.expectedStaticResourceSet(bundle.productionClosure);
    assert.strictEqual(expected.filter((entry) => entry.type === "Image").length, 15);
    assert.strictEqual(expected.filter((entry) => entry.type === "Script").length, 40);
    assert.strictEqual(expected.length, 83);
    const fixedUrls = new Set(expected.map((entry) => entry.url));
    assert.deepStrictEqual(loaded.rawResourceOccurrences.filter((entry) => fixedUrls.has(entry.url))
      .map((entry) => ({
      url: entry.url, type: entry.type, urlOrigin: entry.urlOrigin,
    })), expected);
    assert.ok(loaded.iconProjection.resources.length >= 3);
    assert.deepStrictEqual(loaded.rawResourceOccurrences.filter((entry) =>
      loaded.iconProjection.resources.some((icon) => icon.url === entry.url)).map((entry) => ({
      url: entry.url, type: entry.type, sha256: entry.sourceSha256, bytes: entry.sourceBytes,
    })), loaded.iconProjection.resources.map((entry) => ({
      url: entry.url, type: entry.type, sha256: entry.sha256, bytes: entry.bytes,
    })));
    const lxgw = loaded.fontEnvironment.installed.find((entry) =>
      entry.name === "lxgw-wenkai-screen.ttf");
    assert.ok(lxgw);
    assert.ok(loaded.rawResourceOccurrences.some((entry) => entry.url === lxgw.url
      && entry.type === "Font" && entry.sourceSha256 === lxgw.sha256
      && entry.sourceBytes === lxgw.bytes));
    verifyBundle(bundle);
  });

  test("authority-derived icon resources and the installed LXGW font bind exact bytes", () => {
    const bundle = buildValidBundle();
    const loaded = bundle.runtime.restart.loadedProduction;
    assert.deepStrictEqual(loaded.iconProjection.iconNames,
      ["觉醒晶体", "手枪通用弹药", "强化石", "废城防弹军装上装"]);
    assert.ok(loaded.iconProjection.bindings.every((binding) => binding.urls.length >= 1));
    const lxgw = loaded.fontEnvironment.installed.find((entry) =>
      entry.name === "lxgw-wenkai-screen.ttf");
    const font = loaded.rawResourceOccurrences.find((entry) => lxgw && entry.url === lxgw.url);
    assert.ok(lxgw && font && font.type === "Font");
    assert.strictEqual(font.sourceSha256, lxgw.sha256);
    assert.strictEqual(font.sourceBytes, lxgw.bytes);
    verifyBundle(bundle);
  });

  test("one source-declared CSS asset is an allowed same-shape conditional resource", () => {
    const bundle = buildValidBundle();
    const loaded = bundle.runtime.first.loadedProduction;
    const asset = ProductionClosure.cssConditionalResourceSet(bundle.productionClosure)[0];
    assert.ok(asset);
    const dynamicUrls = new Set(loaded.iconProjection.resources.map((entry) => entry.url)
      .concat(loaded.fontEnvironment.installed.map((entry) => entry.url)));
    const dynamicStart = loaded.rawResourceOccurrences.findIndex((entry) => dynamicUrls.has(entry.url));
    appendBoundPageResource(loaded, asset,
      dynamicStart < 0 ? loaded.rawResourceOccurrences.length : dynamicStart);
    refreshEvidenceSha(loaded);
    refreshRawManifest(bundle);
    assert.strictEqual(verifyBundle(bundle).status, "OFFLINE_VERIFIED");
  });

  expectFailure("a source-declared CSS asset cannot forge its loaded bytes", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const asset = ProductionClosure.cssConditionalResourceSet(bundle.productionClosure)[0];
    appendBoundPageResource(loaded, asset).sourceSha256 = "f".repeat(64);
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  expectFailure("an undeclared cfn-fonts resource is rejected", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    appendBoundPageResource(loaded, { url: "https://cfn-fonts.local/unknown-font.ttf",
      urlOrigin: "https://cfn-fonts.local", type: "Font", mimeType: "font/ttf",
      sha256: "f".repeat(64), bytes: 123 });
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  expectFailure("one mandatory authority-projected icon resource cannot be omitted", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const iconUrl = loaded.iconProjection.resources[0].url;
    loaded.rawResourceOccurrences = loaded.rawResourceOccurrences.filter((entry) =>
      entry.url !== iconUrl);
    reindexRawResources(loaded);
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  expectFailure("a valid manifest icon not named by authority is rejected", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const unauthorized = ProductionClosure.iconResourceSetForNames(
      PRODUCTION_ROOT, bundle.productionClosure, ["12号霰弹弹药"]).resources[0];
    assert.ok(unauthorized);
    appendBoundPageResource(loaded, unauthorized);
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  test("a visible historical-purchase icon is part of both authority projections", () => {
    const events = deepClone(buildValidBundle().transcript.events);
    events.filter((event) => event.kind === "webview_message" && event.message
      && event.message.panelInstanceId === PANEL_ONE
      && Array.isArray(event.message.purchased)).forEach((event) => {
      event.message.purchased = [{ purchasedIdx: 0, item: "fixture.pending.item",
        displayname: "待领取夹具物品", icon: "12号霰弹弹药", quantity: 1 }];
    });
    const verifierNames = verifierIconNames(events, "first");
    const observerNames = observerIconNames(events, "first");
    assert.deepStrictEqual(observerNames, verifierNames);
    assert.ok(verifierNames.includes("12号霰弹弹药"));
  });

  test("an authoritative icon name absent from the current manifest is rejected", () => {
    const bundle = buildValidBundle();
    assert.throws(() => ProductionClosure.iconResourceSetForNames(
      PRODUCTION_ROOT, bundle.productionClosure, ["不存在的权威图标名"]),
    (error) => error && error.code === "dynamic_icon_name_unbound");
  });

  expectFailure("full execution-context auxData cannot be projected away", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    delete loaded.rawExecutionContextOccurrences[0].auxData.type;
    loaded.rawScriptOccurrences.forEach((entry) => { delete entry.context.auxData.type; });
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_occurrence_invalid");

  expectFailure("unused raw execution context cannot be appended", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const extra = deepClone(loaded.rawExecutionContextOccurrences[0]);
    extra.occurrence = 2;
    extra.id = 2;
    extra.uniqueId = "fixture-unused-context";
    loaded.rawExecutionContextOccurrences.push(extra);
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_set_invalid");

  expectFailure("raw execution context id cannot be reused", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const duplicate = deepClone(loaded.rawExecutionContextOccurrences[0]);
    duplicate.occurrence = 2;
    duplicate.uniqueId = "fixture-second-context";
    loaded.rawExecutionContextOccurrences.push(duplicate);
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_identity_reused");

  expectFailure("raw execution context uniqueId cannot be reused", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const duplicate = deepClone(loaded.rawExecutionContextOccurrences[0]);
    duplicate.occurrence = 2;
    duplicate.id = 2;
    loaded.rawExecutionContextOccurrences.push(duplicate);
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_identity_reused");

  expectFailure("raw execution context cannot collude on a foreign origin", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    loaded.rawExecutionContextOccurrences[0].origin = "https://foreign.invalid";
    loaded.rawScriptOccurrences.forEach((entry) => {
      entry.context.origin = "https://foreign.invalid";
    });
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_occurrence_invalid");

  expectFailure("raw execution context cannot collude on a foreign frame", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    loaded.rawExecutionContextOccurrences[0].auxData.frameId = "foreign-frame";
    loaded.rawScriptOccurrences.forEach((entry) => {
      entry.context.auxData.frameId = "foreign-frame";
    });
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_occurrence_invalid");

  expectFailure("raw execution context order must equal first script-reference order", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const first = loaded.rawExecutionContextOccurrences[0];
    const second = deepClone(first);
    second.occurrence = 2;
    second.id = 2;
    second.uniqueId = "fixture-second-context";
    const tool = loaded.rawScriptOccurrences.at(-1);
    tool.executionContextId = second.id;
    tool.context = deepClone(second);
    loaded.rawExecutionContextOccurrences = [second, first];
    loaded.rawExecutionContextOccurrences.forEach((entry, index) => {
      entry.occurrence = index + 1;
    });
    loaded.rawScriptOccurrences.forEach((entry) => {
      entry.context.occurrence = entry.executionContextId === first.id ? 2 : 1;
    });
    loaded.productionScriptOccurrences.forEach((entry) => {
      entry.context.occurrence = 2;
    });
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_set_invalid");

  expectFailure("raw execution context cannot be missing from the captured set", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    loaded.rawExecutionContextOccurrences = [];
    refreshEvidenceSha(loaded);
  }, "loaded_execution_context_occurrence_invalid");

  expectFailure("script embedded context must equal its captured context occurrence", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    loaded.rawScriptOccurrences[0].context.name = "mismatched-script-context";
    refreshEvidenceSha(loaded);
  }, "loaded_executable_occurrence_shape_invalid");

  expectFailure("raw resource stream cannot omit the non-stylesheet Overlay document", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    loaded.rawResourceOccurrences = loaded.rawResourceOccurrences.filter((entry) =>
      entry.type !== "Document");
    reindexRawResources(loaded);
    refreshEvidenceSha(loaded);
  }, "loaded_page_resource_occurrence_invalid");

  expectFailure("raw stylesheet occurrence set rejects an omission", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const index = loaded.rawResourceOccurrences.findIndex((entry) => entry.type === "Stylesheet");
    loaded.rawResourceOccurrences.splice(index, 1);
    reindexRawResources(loaded);
    refreshEvidenceSha(loaded);
  }, "loaded_production_stylesheet_set_invalid");

  expectFailure("raw stylesheet occurrences reject a foreign frame origin", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    loaded.rawResourceOccurrences.find((entry) => entry.type === "Stylesheet").frameOrigin
      = "https://foreign.invalid";
    refreshEvidenceSha(loaded);
  }, "loaded_production_stylesheet_set_invalid");

  expectFailure("raw stylesheet occurrences reject a duplicate before projection", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const duplicate = deepClone(loaded.rawResourceOccurrences.find((entry) =>
      entry.type === "Stylesheet"));
    duplicate.occurrence = loaded.rawResourceOccurrences.length + 1;
    duplicate.resourceOccurrence = loaded.rawResourceOccurrences.at(-1).resourceOccurrence + 1;
    loaded.rawResourceOccurrences.push(duplicate);
    refreshEvidenceSha(loaded);
  }, "loaded_production_stylesheet_set_invalid");

  expectFailure("raw stylesheet URL occurrence order cannot be rewritten by projections", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const styles = loaded.rawResourceOccurrences.filter((entry) => entry.type === "Stylesheet");
    const leftUrl = styles[0].url;
    styles[0].url = styles[1].url;
    styles[0].resource.url = styles[0].url;
    styles[1].url = leftUrl;
    styles[1].resource.url = styles[1].url;
    loaded.stylesheets.forEach((entry) => {
      entry.occurrence = styles.find((style) => style.url === entry.url).occurrence;
    });
    refreshEvidenceSha(loaded);
  }, "loaded_production_stylesheet_set_invalid");

  expectFailure("raw Page resources preserve one global cross-layer occurrence order", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const staticUrls = new Set(ProductionClosure.expectedStaticResourceSet(
      bundle.productionClosure).map((entry) => entry.url));
    const iconUrls = new Set(loaded.iconProjection.resources.map((entry) => entry.url));
    const staticIndexes = loaded.rawResourceOccurrences.map((entry, index) =>
      staticUrls.has(entry.url) ? index : -1).filter((index) => index >= 0);
    const iconIndex = loaded.rawResourceOccurrences.findIndex((entry) => iconUrls.has(entry.url));
    const staticIndex = staticIndexes.at(-1);
    assert.ok(Number.isInteger(staticIndex) && staticIndex >= 0 && iconIndex > staticIndex,
      "fixture must place the first icon after the final mandatory static resource");
    [loaded.rawResourceOccurrences[staticIndex], loaded.rawResourceOccurrences[iconIndex]]
      = [loaded.rawResourceOccurrences[iconIndex], loaded.rawResourceOccurrences[staticIndex]];
    reindexRawResources(loaded);
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  expectFailure("raw Page resource set rejects an unregistered image", (bundle) => {
    const loaded = bundle.runtime.first.loadedProduction;
    const extra = deepClone(loaded.rawResourceOccurrences.find((entry) => entry.type === "Image"));
    extra.url = "https://overlay.local/assets/map/unregistered.webp";
    extra.resource.url = extra.url;
    loaded.rawResourceOccurrences.push(extra);
    reindexRawResources(loaded);
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  expectFailure("raw Page resource set rejects a missing idle-prewarm image", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const index = loaded.rawResourceOccurrences.findIndex((entry) => entry.type === "Image");
    loaded.rawResourceOccurrences.splice(index, 1);
    reindexRawResources(loaded);
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  expectFailure("raw Page resource set rejects a missing production Script resource", (bundle) => {
    const loaded = bundle.runtime.restart.loadedProduction;
    const index = loaded.rawResourceOccurrences.findIndex((entry) => entry.type === "Script");
    loaded.rawResourceOccurrences.splice(index, 1);
    reindexRawResources(loaded);
    refreshEvidenceSha(loaded);
  }, "loaded_production_static_resource_set_invalid");

  expectFailure("actual-loaded stylesheet multiset rejects an extra", (bundle) => {
    bundle.runtime.restart.loadedProduction.stylesheets.push({
      role: "style_import",
      locator: "root:launcher/web/css/extra.css",
      url: "https://overlay.local/css/extra.css",
      sourceMethod: "Page.getResourceContent",
      sha256: "f".repeat(64),
      bytes: 1,
    });
    refreshEvidenceSha(bundle.runtime.restart.loadedProduction);
  }, "loaded_production_multiset_invalid");

  expectFailure("candidate producer evidence cannot be rebound away from its exact files", (bundle) => {
    bundle.candidateProducer.builderLabel = "forged-producer";
    refreshEvidenceSha(bundle.candidateProducer);
    bundle.productionBinding.candidateProducerSha256 = bundle.candidateProducer.evidenceSha256;
    refreshEvidenceSha(bundle.productionBinding, "bindingSha256");
  }, "candidate_producer_evidence_mismatch");

  expectFailure("candidate manifest cannot omit every payload file row", (bundle) =>
    rewriteCandidateManifest(bundle, (lines) => {
      for (let index = lines.length - 1; index >= 0; index -= 1) {
        if (lines[index].startsWith("file\t")) lines.splice(index, 1);
      }
    }), "candidate_payload_file_mismatch");

  expectFailure("undeclared candidate payload file is rejected", (bundle) => {
    const filePath = path.join(bundle.candidateRoot, "runtime", "undeclared-fixture.bin");
    fs.writeFileSync(filePath, "undeclared", "utf8");
    return () => fs.unlinkSync(filePath);
  }, "candidate_payload_file_mismatch");

  expectFailure("missing candidate payload file is rejected", (bundle) => {
    const filePath = path.join(bundle.candidateRoot, "runtime",
      "CRAZYFLASHER7MercenaryEmpire.Core.exe");
    const original = fs.readFileSync(filePath);
    fs.unlinkSync(filePath);
    return () => fs.writeFileSync(filePath, original);
  }, "candidate_payload_file_mismatch");

  expectFailure("duplicate candidate payload manifest row is rejected", (bundle) =>
    rewriteCandidateManifest(bundle, (lines) => {
      const row = lines.find((line) => line.startsWith("file\t"));
      lines.splice(lines.length - 1, 0, row);
    }), "candidate_payload_manifest_invalid");

  expectFailure("candidate payload manifest row order is canonical", (bundle) =>
    rewriteCandidateManifest(bundle, (lines) => {
      const indexes = lines.map((line, index) => line.startsWith("file\t") ? index : -1)
        .filter((index) => index >= 0);
      [lines[indexes[0]], lines[indexes[1]]] = [lines[indexes[1]], lines[indexes[0]]];
    }), "candidate_payload_manifest_invalid");

  expectFailure("candidate payload bytes must equal their manifest hash and size", (bundle) => {
    const filePath = path.join(bundle.candidateRoot, "runtime",
      "CRAZYFLASHER7MercenaryEmpire.Core.dll");
    const original = fs.readFileSync(filePath);
    fs.writeFileSync(filePath, Buffer.concat([original, Buffer.from("drift", "utf8")]));
    return () => fs.writeFileSync(filePath, original);
  }, "candidate_payload_file_mismatch");

  expectFailure("candidate Core DLL row must bind runtime core identity", (bundle) => {
    bundle.runtime.first.identity.coreSha256 = "F".repeat(64);
    rebindFirstCandidateEnvelope(bundle);
  }, "candidate_core_identity_mismatch");

  expectFailure("candidate process path must identify one manifest payload row", (bundle) => {
    bundle.runtime.first.identity.processPath = path.join(bundle.candidateRoot,
      "runtime", "not-in-payload.exe");
    rebindFirstCandidateEnvelope(bundle);
  }, "candidate_process_identity_mismatch");

  expectFailure("production closure cannot be relabeled away from the current tree", (bundle) => {
    bundle.productionClosure.files[0].sha256 = "f".repeat(64);
    refreshEvidenceSha(bundle.productionClosure, "closureSha256");
  }, "production_closure_current_tree_mismatch");

  expectFailure("producer recipe identity cannot drift from current runtime inputs", (bundle) => {
    const producer = bundle.productionClosure.producerInputs;
    producer.domains.producerRecipe.hash = "F".repeat(64);
    delete producer.inputsSha256;
    producer.inputsSha256 = sha256Text(canonicalJson(producer));
    refreshEvidenceSha(bundle.productionClosure, "closureSha256");
  }, "production_producer_inputs_current_tree_mismatch");

  expectFailure("candidate identity must remain exact across restart", (bundle) => {
    bundle.runtime.restart.identity.payloadClosure = "D".repeat(64);
  }, "restart_identity_mismatch");

  expectFailure("authorization cannot drift from dynamic selection", (bundle) => {
    bundle.authorization.commitDecision.scope.total += 1;
  }, "authorization_decision_invalid");

  expectFailure("control acknowledgement cannot be omitted", (bundle) => {
    bundle.controlAcks.splice(0, 1);
  }, "control_envelope_count_invalid");

  expectFailure("module manifest cannot omit an admitted module", (bundle) => {
    bundle.moduleAdmission.manifest.entries.pop();
  }, ["runtime_module_journal_invalid", "runtime_module_manifest_invalid",
    "runtime_module_journal_mismatch", "module_manifest_invalid",
    "module_admission_scope_invalid"]);

  expectFailure("restart disk phase must equal SAFEEXIT artifacts", (bundle) => {
    bundle.cloneLifecycle.phases.afterRestart.set.artifacts[0].sha256 = "0".repeat(64);
  }, ["clone_phase_digest_mismatch", "artifact_set_digest_mismatch"]);

  expectFailure("runtime persistence phases require both JSON and SOL", (bundle) => {
    const phase = bundle.cloneLifecycle.phases.afterRestart;
    phase.set.artifacts = phase.set.artifacts.filter((entry) => entry.kind !== "sol");
    const setPayload = { schema: phase.set.schema, slot: phase.set.slot,
      appDataRoot: phase.set.appDataRoot, artifacts: phase.set.artifacts };
    phase.set.setSha256 = sha256Text(canonicalJson(setPayload));
    delete phase.evidenceSha256;
    phase.evidenceSha256 = sha256Text(canonicalJson(phase));
  }, "clone_json_sol_set_incomplete");

  expectFailure("open final residue port is rejected", (bundle) => {
    bundle.residue.final.ports[0].open = true;
    delete bundle.residue.final.evidenceSha256;
    bundle.residue.final.evidenceSha256 = sha256Text(canonicalJson(bundle.residue.final));
  }, ["runtime_residue_invalid", "runtime_residue_not_clean"]);

  expectFailure("restart requires an authenticated supported shutdown receipt", (bundle) => {
    delete bundle.runtime.restart.shutdownEvidence;
  }, "authenticated_shutdown_missing");

  expectFailure("supported shutdown response must be successful", (bundle) => {
    bundle.runtime.restart.shutdownEvidence.response.success = false;
    bundle.runtime.restart.shutdownEvidence.response.ok = false;
    refreshEvidenceSha(bundle.runtime.restart.shutdownEvidence);
  }, ["launcher_response_failed", "authenticated_shutdown_failed", "launcher_task_failed"]);

  expectFailure("archive path must remain the exact clone JSON", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const archive = records.find((entry) => hostBody(entry.line).startsWith(
        "[ArchiveTask] Shadow saved:"));
      archive.line = archive.line.replace("\\saves\\", "\\other\\");
    });
  }, ["archive_save_record_count_invalid", "safe_exit_boundary_invalid"]);

  expectFailure("sv1 and sv2 cannot precede the authoritative commit response", (bundle) => {
    resealHost(bundle, "first", (records) => {
      const markerIndex = records.findIndex((entry) => entry.line.includes("sv:1")
        && entry.line.includes("sv:2"));
      const marker = records.splice(markerIndex, 1)[0];
      const commitResponseIndex = records.findIndex((entry) => entry.line.includes(
        "[XmlSocket:JSON] task=shop_response cmd=shopCheckoutCommit"));
      records.splice(commitResponseIndex, 0, marker);
    });
    refreshSafeExitEvidence(bundle);
  }, ["safe_exit_boundary_invalid", "host_log_clock_regressed"]);

  expectFailure("global timeline rejects a close request before final commit response", (bundle) => {
    const commitAt = hostRecordMoment(bundle, "first", (body) => body.includes(
      "[XmlSocket:JSON] task=shop_response cmd=shopCheckoutCommit"));
    rewriteControlExchange(bundle, "close_kshop", ({ request }) => {
      request.issuedAt = new Date(commitAt - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires complete post-commit Inventory before close request", (bundle) => {
    const commitAt = hostRecordMoment(bundle, "first", (body) => body.includes(
      "[XmlSocket:JSON] task=shop_response cmd=shopCheckoutCommit"));
    const postResponses = inventoryPhaseResponses(bundle.transcript.events, "post");
    assert.ok(postResponses.length > 0, "fixture requires post-commit Inventory responses");
    const postSettledAt = Math.max(...postResponses.map((event) =>
      hostInventoryResponseMoment(bundle, "first", event.message.callId)));
    assert.ok(Number.isFinite(postSettledAt) && commitAt + 1 < postSettledAt,
      "fixture requires a bounded commit-to-post-readback interval");
    rewriteControlExchange(bundle, "close_kshop", ({ request }) => {
      request.issuedAt = new Date(postSettledAt - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires exact close completion before SAFEEXIT request", (bundle) => {
    const closeAt = hostRecordMoment(bundle, "first", (body) => body.startsWith(
      "event=panel_exact_close_completed"));
    rewriteControlExchange(bundle, "safe_exit", ({ request }) => {
      request.issuedAt = new Date(closeAt - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("first close provider completion must follow exact Host close completion", (bundle) => {
    const closeAt = hostRecordMoment(bundle, "first", (body) => body.startsWith(
      "event=panel_exact_close_completed"));
    rewriteControlExchange(bundle, "close_kshop", ({ provider }) => {
      provider.completedAt = new Date(closeAt - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("first close provider completion must precede SAFEEXIT request", (bundle) => {
    const safe = bundle.controlRequests.find((entry) => entry.step === "safe_exit");
    rewriteControlExchange(bundle, "close_kshop", ({ provider }) => {
      provider.completedAt = new Date(Date.parse(safe.issuedAt) + 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires SAFEEXIT provider start before sv1", (bundle) => {
    const sv1At = hostRecordMoment(bundle, "first", (body) => body.includes("sv:1"));
    rewriteControlExchange(bundle, "safe_exit", ({ provider }) => {
      provider.startedAt = new Date(sv1At + 1).toISOString();
      provider.operationEvents.find((entry) => entry.kind === "action_completed").occurredAt
        = new Date(sv1At + 2).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires archive before SAFEEXIT provider completion", (bundle) => {
    const archiveAt = hostRecordMoment(bundle, "first", (body) => body.startsWith(
      "[ArchiveTask] Shadow saved:"));
    let capturePath;
    let originalStat;
    rewriteControlExchange(bundle, "safe_exit", ({ provider }) => {
      capturePath = path.resolve(bundle.root, bundle.runDir.replace(/\//g, path.sep),
        provider.capture.relativePath.replace(/\//g, path.sep));
      originalStat = fs.statSync(capturePath);
      const captureAt = new Date(archiveAt - 2);
      fs.utimesSync(capturePath, captureAt, captureAt);
      provider.capture.capturedAt = captureAt.toISOString();
      provider.capture.fileModifiedAt = fs.statSync(capturePath).mtime.toISOString();
      provider.completedAt = new Date(archiveAt - 1).toISOString();
    });
    const provider = bundle.controlProviderReceipts.find((entry) => entry.step === "safe_exit");
    const captureIndex = bundle.controlCaptures.findIndex((entry) =>
      entry.relativePath === provider.capture.relativePath);
    bundle.controlCaptures[captureIndex] = deepClone(provider.capture);
    return () => fs.utimesSync(capturePath, originalStat.atime, originalStat.mtime);
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires SAFEEXIT completion before EXIT_CONFIRM request", (bundle) => {
    const safe = bundle.controlProviderReceipts.find((entry) => entry.step === "safe_exit");
    rewriteControlExchange(bundle, "exit_confirm", ({ request }) => {
      request.issuedAt = new Date(Date.parse(safe.completedAt) - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires EXIT_CONFIRM completion before clean residue", (bundle) => {
    const exit = bundle.controlProviderReceipts.find((entry) => entry.step === "exit_confirm");
    rewriteResidueObservedAt(bundle.residue.afterSafeExit,
      new Date(Date.parse(exit.completedAt) - 1).toISOString());
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires first clean residue before restart open", (bundle) => {
    const residueAt = Date.parse(bundle.residue.afterSafeExit.observedAt);
    rewriteControlExchange(bundle, "restart_readback_open_kshop", ({ request }) => {
      request.issuedAt = new Date(residueAt - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires restart provider before PanelHost open", (bundle) => {
    const openAt = hostRecordMoment(bundle, "restart", (body) => body.startsWith(
      "[PanelHost] opened: kshop"));
    rewriteControlExchange(bundle, "restart_readback_open_kshop", ({ provider }) => {
      provider.startedAt = new Date(openAt + 1).toISOString();
      provider.operationEvents.find((entry) => entry.kind === "action_completed").occurredAt
        = new Date(openAt + 2).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires restart readback before close request", (bundle) => {
    const bulkAt = hostRecordMoment(bundle, "restart", (body) => body.includes(
      "[XmlSocket:JSON] task=shop_response cmd=shopBulkQuery"));
    const restartResponses = inventoryPhaseResponses(bundle.transcript.events, "restart");
    assert.ok(restartResponses.length > 0, "fixture requires restart Inventory responses");
    const inventoryAt = Math.max(...restartResponses.map((event) =>
      hostInventoryResponseMoment(bundle, "restart", event.message.callId)));
    rewriteControlExchange(bundle, "restart_readback_close_kshop", ({ request }) => {
      request.issuedAt = new Date(Math.max(bulkAt, inventoryAt) - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires restart exact close before supported shutdown", (bundle) => {
    const closeAt = hostRecordMoment(bundle, "restart", (body) => body.startsWith(
      "event=panel_exact_close_completed"));
    bundle.runtime.restart.shutdownEvidence.requestedAt = new Date(closeAt - 1).toISOString();
    refreshEvidenceSha(bundle.runtime.restart.shutdownEvidence);
  }, "global_timeline_order_invalid");

  expectFailure("restart close provider completion must follow exact Host close completion", (bundle) => {
    const closeAt = hostRecordMoment(bundle, "restart", (body) => body.startsWith(
      "event=panel_exact_close_completed"));
    rewriteControlExchange(bundle, "restart_readback_close_kshop", ({ provider }) => {
      provider.completedAt = new Date(closeAt - 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("restart close provider completion must precede supported shutdown", (bundle) => {
    const shutdownAt = Date.parse(bundle.runtime.restart.shutdownEvidence.requestedAt);
    rewriteControlExchange(bundle, "restart_readback_close_kshop", ({ provider }) => {
      provider.completedAt = new Date(shutdownAt + 1).toISOString();
    });
  }, "global_timeline_order_invalid");

  expectFailure("global timeline requires supported shutdown before final residue", (bundle) => {
    const completedAt = Date.parse(bundle.runtime.restart.shutdownEvidence.completedAt);
    rewriteResidueObservedAt(bundle.residue.final, new Date(completedAt - 1).toISOString());
  }, "global_timeline_order_invalid");

  assert(browserGateReceipt);
  return { passed, childReceipts:{ browser:browserGateReceipt } };
}

module.exports = { runAdmissionSmoke, runSelfTests, runV83InventoryPhaseRegressionTests };

if (require.main === module) {
  console.error("self-test.js is NOT_ADMITTED directly; use kshop/bootstrap.js --check");
  process.exit(2);
}
