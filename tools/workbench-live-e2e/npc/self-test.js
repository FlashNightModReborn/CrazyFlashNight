#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const LauncherObservation = require("../lib/launcher-observation");
const { CANONICAL_TIMELINE_ORDER, CONTROL_ACK_SCHEMA, PROVIDER_RECEIPT_SCHEMA,
  NpcJourneyError, atomicWriteJson,
  canonicalJson, decodePng, deepClone, sealEvents, sealEvidenceOrigin, sealTrustedTimeline,
  sha256File, sha256Text } = require("./common");
const AckControl = require("./ack-control");
const { ControlChannel, captureRelativePath, domInputEvidence, expectedProviderOperationId,
  providerReceiptRelativePath } = require("./control-channel");
const { PURCHASE_SLOT, buildValidFixture, fixturePng, pngChunk }
  = require("./fixtures/valid-bundle");
const ProductionClosure = require("./production-closure");
const Protocol = require("./protocol");
const { createScriptContextLedger } = require("./passive-recorder");
const { loadSharedAdapter } = require("./shared-adapter");
const { controlRequestOutputRecord, parseArgs, selectPurchaseTarget, selectSaleTarget,
  validateArgs } = require("./run-live-journey");
const { assertInventoryPhaseAccessConsistency, assertStableRevisionLeases,
  verifyEvidenceFile } = require("./verify-evidence");
const InventoryRuntime = require("../../../launcher/web/modules/inventory-runtime.js");

const tests = [];
let browserGateReceipt = null;
function test(name, body) { tests.push({ name, body }); }
function withFixture(options, body) {
  const runDir = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-npc-v2-"));
  try { return body(buildValidFixture(runDir, options || {})); }
  finally { fs.rmSync(runDir, { recursive: true, force: true }); }
}
function load(fixture) { return JSON.parse(fs.readFileSync(fixture.bundlePath, "utf8")); }
function inventorySurface(fixture, bundle, callIds, phase) {
  const transcript = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
    bundle.transcriptArtifact), "utf8"));
  const allPairs = Protocol.strictRequestPairsFromEvents(transcript.events);
  const byCallId = new Map(allPairs.map((pair) => [pair.request.message.callId, pair]));
  return Protocol.assertInventorySnapshotSurface(callIds.map((callId) => byCallId.get(callId)),
    phase || "self_test_surface");
}
function save(fixture, bundle) {
  const manifest = bundle.artifactManifest;
  if (manifest) {
    delete manifest.manifestSha256;
    manifest.manifestSha256 = sha256Text(canonicalJson(manifest));
    atomicWriteJson(path.join(fixture.runDir, "artifact-manifest.json"), manifest);
  }
  atomicWriteJson(fixture.bundlePath, bundle);
  fixture.bundle = bundle;
}
function sealDigest(value) {
  delete value.evidenceSha256;
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}
function entry(bundle, relativePath) {
  return bundle.artifactManifest.artifacts.find((value) => value.path === relativePath);
}
function refreshArtifactEntry(fixture, bundle, filePath) {
  const relativePath = path.relative(fixture.runDir, filePath).replace(/\\/g, "/");
  const artifact = entry(bundle, relativePath);
  assert(artifact, "fixture artifact entry is missing: " + relativePath);
  artifact.bytes = fs.statSync(filePath).size;
  artifact.sha256 = sha256File(filePath);
  return artifact;
}
function refreshTrustedTimeline(fixture, bundle) {
  if (!bundle.trustedTimeline) return;
  const hostLog = JSON.parse(fs.readFileSync(path.join(fixture.runDir, bundle.hostLogArtifact), "utf8"));
  function controlIdentity(step) {
    const binding = bundle.controls.find((value) => value.step === step);
    const ack = JSON.parse(fs.readFileSync(path.join(fixture.runDir, binding.ackArtifact), "utf8"));
    const provider = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
      ack.providerReceipt.artifact), "utf8"));
    return { requestId: binding.requestId, providerOperationId: provider.providerOperationId };
  }
  const safeExit = controlIdentity("safe_exit");
  const exitConfirm = controlIdentity("exit_confirm");
  const transcript = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
    bundle.transcriptArtifact), "utf8"));
  const inventoryEvents = [
    ["initial", bundle.calls.initialInventorySnapshots],
    ["purchase-post", bundle.calls.purchasePostInventories],
    ["sale-post", bundle.calls.salePostInventories],
    ["restart", bundle.calls.restartInventorySnapshots],
  ].flatMap(([phase, callIds]) => callIds.map((callId, pairOrdinal) => {
    const request = transcript.events.find((event) => event.kind === "bridge_send"
      && event.message && event.message.callId === callId);
    const response = transcript.events.find((event) => event.kind === "webview_message"
      && event.message && event.message.callId === callId);
    const prior = bundle.trustedTimeline && bundle.trustedTimeline.inventoryEvents
      && bundle.trustedTimeline.inventoryEvents.find((entry) => entry.callId === callId);
    return { phase, pairOrdinal, callId,
      requestAt: request ? request.observedAt : prior.requestAt,
      responseAt: response ? response.observedAt : prior.responseAt };
  }));
  bundle.trustedTimeline = sealTrustedTimeline({
    runId: bundle.runId,
    transcriptSha256: entry(bundle, bundle.transcriptArtifact).sha256,
    hostLogSha256: entry(bundle, bundle.hostLogArtifact).sha256,
    safeExitRequestId: safeExit.requestId,
    safeExitProviderOperationId: safeExit.providerOperationId,
    exitConfirmRequestId: exitConfirm.requestId,
    exitConfirmProviderOperationId: exitConfirm.providerOperationId,
    safeExitProviderBoundarySha256: sha256Text(canonicalJson(
      hostLog.lifecycles.first.timelineBoundaries.safe_exit_provider_completed)),
    archiveHostLine: bundle.archive.hostLine,
    shutdownSha256: bundle.shutdown.evidenceSha256,
    residueSha256: bundle.residue.evidenceSha256,
    inventoryEvents,
  });
}
function rewrite(fixture, relativePath, mutate) {
  const bundle = load(fixture);
  const target = path.join(fixture.runDir, relativePath);
  const value = JSON.parse(fs.readFileSync(target, "utf8"));
  mutate(value, bundle);
  fs.writeFileSync(target, JSON.stringify(value, null, 2) + "\n", "utf8");
  const artifact = entry(bundle, relativePath);
  artifact.bytes = fs.statSync(target).size;
  artifact.sha256 = sha256File(target);
  if (relativePath === bundle.hostLogArtifact) refreshTrustedTimeline(fixture, bundle);
  save(fixture, bundle);
}
function reseal(fixture, mutate) {
  const bundle = load(fixture);
  const target = path.join(fixture.runDir, bundle.transcriptArtifact);
  const transcript = JSON.parse(fs.readFileSync(target, "utf8"));
  const raw = transcript.events.map((event) => {
    const copy = deepClone(event);
    delete copy.schema; delete copy.sequence; delete copy.previousHash; delete copy.eventHash;
    return copy;
  });
  mutate(raw);
  const sealed = sealEvents(raw, transcript.observerId);
  sealed.pageUrl = transcript.pageUrl;
  fs.writeFileSync(target, JSON.stringify(sealed, null, 2) + "\n", "utf8");
  const transcriptEntry = entry(bundle, bundle.transcriptArtifact);
  transcriptEntry.bytes = fs.statSync(target).size;
  transcriptEntry.sha256 = sha256File(target);
  bundle.controls.forEach((binding) => {
    binding.events.forEach((bound) => { bound.eventHash = sealed.events[bound.sequence - 1].eventHash; });
    const requestPath = path.join(fixture.runDir, binding.requestArtifact);
    const request = JSON.parse(fs.readFileSync(requestPath, "utf8"));
    const count = request.transcriptPrefix.eventCount;
    request.transcriptPrefix.chainHead = count ? sealed.events[count - 1].eventHash : "0".repeat(64);
    fs.writeFileSync(requestPath, JSON.stringify(request, null, 2) + "\n", "utf8");
    const requestEntry = entry(bundle, binding.requestArtifact);
    requestEntry.bytes = fs.statSync(requestPath).size;
    requestEntry.sha256 = sha256File(requestPath);
    const ackPath = path.join(fixture.runDir, binding.ackArtifact);
    const ack = JSON.parse(fs.readFileSync(ackPath, "utf8"));
    ack.requestSha256 = requestEntry.sha256;
    const providerPath = path.join(fixture.runDir, ack.providerReceipt.artifact);
    const provider = JSON.parse(fs.readFileSync(providerPath, "utf8"));
    provider.requestSha256 = requestEntry.sha256;
    provider.requestBytes = requestEntry.bytes;
    const domEvents = binding.events.map((bound) => sealed.events[bound.sequence - 1])
      .filter((event) => event && event.kind === "dom_input");
    if (domEvents.length === 1) {
      provider.inputEvidence = domInputEvidence(sealed.observerId, domEvents[0]);
    }
    provider.providerOperationId = expectedProviderOperationId(provider);
    delete provider.receiptSha256;
    provider.receiptSha256 = sha256Text(canonicalJson(provider));
    fs.writeFileSync(providerPath, JSON.stringify(provider, null, 2) + "\n", "utf8");
    const providerEntry = entry(bundle, ack.providerReceipt.artifact);
    providerEntry.bytes = fs.statSync(providerPath).size;
    providerEntry.sha256 = sha256File(providerPath);
    ack.providerReceipt.sha256 = providerEntry.sha256;
    fs.writeFileSync(ackPath, JSON.stringify(ack, null, 2) + "\n", "utf8");
    const ackEntry = entry(bundle, binding.ackArtifact);
    ackEntry.bytes = fs.statSync(ackPath).size;
    ackEntry.sha256 = sha256File(ackPath);
  });
  refreshTrustedTimeline(fixture, bundle);
  save(fixture, bundle);
}
function rewriteHost(fixture, label, mutate) {
  const relativePath = load(fixture).hostLogArtifact;
  rewrite(fixture, relativePath, (log, bundle) => {
    const snapshot = log.lifecycles[label].terminalSnapshot;
    const timestampPattern = /^(\d{2}:\d{2}:\d{2}\.\d{3}) (.*)$/;
    const working = snapshot.records.map((record) => {
      const match = timestampPattern.exec(record.line);
      if (!match) throw new Error("fixture Host record lost timestamp before mutation");
      return { lineNumber: record.lineNumber, line: match[2], __timestamp: match[1] };
    });
    mutate(working, bundle);
    let lastClock = 0;
    snapshot.records = working.map((record) => {
      let timestamp = record.__timestamp;
      if (!timestamp) {
        lastClock += 1;
        timestamp = new Date(Date.UTC(2000, 0, 1) + lastClock).toISOString().slice(11, 23);
      } else {
        const parts = timestamp.split(/[:.]/).map(Number);
        lastClock = (((parts[0] * 60 + parts[1]) * 60 + parts[2]) * 1000 + parts[3]);
      }
      return { lineNumber: record.lineNumber, line: timestamp + " " + record.line };
    });
    function resealSnapshot(value) {
      value.records.forEach((record, index) => { record.lineNumber = index + 1; });
      value.total = value.records.length;
      value.oldestLineNumber = value.records.length ? 1 : value.total + 1;
      const payload = { schema: value.schema, requestedTailLimit: value.requestedTailLimit,
        sessionEvidenceSha256: value.sessionEvidenceSha256, lifecycleId: value.lifecycleId,
        sessionPid: value.sessionPid,
        sessionProcessStartUtcTicks: value.sessionProcessStartUtcTicks,
        total: value.total, oldestLineNumber: value.oldestLineNumber, records: value.records };
      value.tailSha256 = sha256Text(canonicalJson(payload));
    }
    resealSnapshot(snapshot);
    const settled = log.lifecycles[label].closeSettledSnapshot;
    const panelInstanceId = bundle.instances[label];
    const completion = "event=panel_exact_close_completed panel=npcshop panelInstanceId="
      + panelInstanceId;
    const completionIndex = snapshot.records.findIndex((record) => record.line.endsWith(" " + completion));
    const prefixLength = completionIndex >= 0 ? completionIndex + 1
      : Math.min(settled.records.length, snapshot.records.length);
    settled.records = snapshot.records.slice(0, prefixLength).map((record) => Object.assign({}, record));
    resealSnapshot(settled);
  });
}
function rewriteProvider(fixture, step, mutate, options) {
  const bundle = load(fixture);
  const binding = bundle.controls.find((value) => value.step === step);
  const ackPath = path.join(fixture.runDir, binding.ackArtifact);
  const ack = JSON.parse(fs.readFileSync(ackPath, "utf8"));
  const providerPath = path.join(fixture.runDir, ack.providerReceipt.artifact);
  const provider = JSON.parse(fs.readFileSync(providerPath, "utf8"));
  mutate(provider, ack, bundle);
  if (!(options && options.preserveOperationId)) {
    provider.providerOperationId = expectedProviderOperationId(provider);
  }
  delete provider.receiptSha256;
  provider.receiptSha256 = sha256Text(canonicalJson(provider));
  fs.writeFileSync(providerPath, JSON.stringify(provider, null, 2) + "\n", "utf8");
  const providerEntry = entry(bundle, ack.providerReceipt.artifact);
  providerEntry.bytes = fs.statSync(providerPath).size;
  providerEntry.sha256 = sha256File(providerPath);
  ack.providerReceipt.sha256 = providerEntry.sha256;
  fs.writeFileSync(ackPath, JSON.stringify(ack, null, 2) + "\n", "utf8");
  const ackEntry = entry(bundle, binding.ackArtifact);
  ackEntry.bytes = fs.statSync(ackPath).size;
  ackEntry.sha256 = sha256File(ackPath);
  refreshTrustedTimeline(fixture, bundle);
  save(fixture, bundle);
}
function rewriteControlRequest(fixture, step, mutate) {
  const bundle = load(fixture);
  const binding = bundle.controls.find((value) => value.step === step);
  assert(binding, "fixture control binding is missing: " + step);
  const requestPath = path.join(fixture.runDir, binding.requestArtifact);
  const request = JSON.parse(fs.readFileSync(requestPath, "utf8"));
  mutate(request, bundle);
  fs.writeFileSync(requestPath, JSON.stringify(request, null, 2) + "\n", "utf8");
  const requestEntry = refreshArtifactEntry(fixture, bundle, requestPath);
  const ackPath = path.join(fixture.runDir, binding.ackArtifact);
  const ack = JSON.parse(fs.readFileSync(ackPath, "utf8"));
  ack.requestSha256 = requestEntry.sha256;
  const providerPath = path.join(fixture.runDir, ack.providerReceipt.artifact);
  const provider = JSON.parse(fs.readFileSync(providerPath, "utf8"));
  provider.requestSha256 = requestEntry.sha256;
  provider.requestBytes = requestEntry.bytes;
  provider.providerOperationId = expectedProviderOperationId(provider);
  delete provider.receiptSha256;
  provider.receiptSha256 = sha256Text(canonicalJson(provider));
  fs.writeFileSync(providerPath, JSON.stringify(provider, null, 2) + "\n", "utf8");
  const providerEntry = refreshArtifactEntry(fixture, bundle, providerPath);
  ack.providerReceipt.sha256 = providerEntry.sha256;
  fs.writeFileSync(ackPath, JSON.stringify(ack, null, 2) + "\n", "utf8");
  refreshArtifactEntry(fixture, bundle, ackPath);
  refreshTrustedTimeline(fixture, bundle);
  save(fixture, bundle);
}
function rewriteLoaded(fixture, lifecycle, mutate) {
  const bundle = load(fixture);
  const loaded = bundle.runtime[lifecycle].loadedProduction;
  mutate(loaded, bundle);
  const unsigned = Object.assign({}, loaded); delete unsigned.evidenceSha256;
  loaded.evidenceSha256 = sha256Text(canonicalJson(unsigned));
  save(fixture, bundle);
}
function rewriteOrigin(fixture, mutate) {
  const bundle = load(fixture);
  const fields = deepClone(bundle.evidenceOrigin);
  delete fields.schema;
  delete fields.evidenceSha256;
  mutate(fields, bundle);
  bundle.evidenceOrigin = sealEvidenceOrigin(fields);
  save(fixture, bundle);
}
function rewriteSealedRuntime(fixture, field, mutate) {
  const bundle = load(fixture);
  mutate(bundle[field], bundle);
  sealDigest(bundle[field]);
  refreshTrustedTimeline(fixture, bundle);
  save(fixture, bundle);
}
function negative(name, mutate, codes, options) {
  test(name, () => withFixture(options || {}, (fixture) => {
    mutate(fixture);
    let caught = null;
    try { verifyEvidenceFile(fixture.bundlePath); } catch (error) { caught = error; }
    assert(caught instanceof NpcJourneyError, "expected NpcJourneyError");
    assert([].concat(codes).includes(caught.code), "unexpected " + caught.code);
  }));
}

function expectFixtureRejected(options, mutate, codes) {
  return withFixture(options || {}, (fixture) => {
    mutate(fixture);
    let caught = null;
    try { verifyEvidenceFile(fixture.bundlePath); } catch (error) { caught = error; }
    assert(caught instanceof NpcJourneyError, "expected NpcJourneyError");
    assert([].concat(codes).includes(caught.code), "unexpected " + caught.code);
  });
}

function replacePngIdat(png, transform) {
  const output = [png.subarray(0, 8)];
  let offset = 8;
  let count = 0;
  while (offset < png.length) {
    const length = png.readUInt32BE(offset);
    const type = png.subarray(offset + 4, offset + 8).toString("ascii");
    const data = png.subarray(offset + 8, offset + 8 + length);
    output.push(type === "IDAT" ? pngChunk(type, transform(Buffer.from(data), count++))
      : pngChunk(type, Buffer.from(data)));
    offset += 12 + length;
  }
  assert.strictEqual(count, 1);
  return Buffer.concat(output);
}

function indexedFixturePng(bitDepth, paletteIndex) {
  const width = 320;
  const height = 180;
  const rowBytes = Math.ceil(width * bitDepth / 8);
  const raw = Buffer.alloc(height * (rowBytes + 1));
  const index = Number(paletteIndex || 0);
  if (index !== 0) raw[1] = index << (8 - bitDepth);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = bitDepth;
  ihdr[9] = 3;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", ihdr),
    pngChunk("PLTE", Buffer.from([0x22, 0x44, 0x66])),
    pngChunk("IDAT", zlib.deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

test("full same-owner purchase and sale verifies", () => withFixture({}, (fixture) => {
  const receipt = verifyEvidenceFile(fixture.bundlePath);
  assert.strictEqual(receipt.status, "OFFLINE_VERIFIED");
  assert.strictEqual(receipt.liveStatus, "LIVE_BLOCKED");
  assert.strictEqual(receipt.deployment, "NOT_DEPLOYED");
  assert.strictEqual(receipt.a3NpcClosable, false);
  assert.strictEqual(receipt.writeCount, 2);
  assert.deepStrictEqual(receipt.purchase.destination,
    { containerId: "背包", physicalSlot: PURCHASE_SLOT, key: "背包:" + PURCHASE_SLOT });
  assert.deepStrictEqual(receipt.ownerInstances,
    ["panel.fixture.npc.first", "panel.fixture.npc.restart"]);
  assert.strictEqual(receipt.webHostAs2Proof.contract,
    "structured_web_call_to_same_fid_success_response.v2");
}));
test("request and response sets form an exact bidirectional mapping", () => {
  const request = { event: { sequence: 1 }, message: { type: "panel", panel: "npcshop",
    panelInstanceId: "panel.fixture", domain: "inventory", cmd: "snapshot", callId: "call.1" } };
  const response = { event: { sequence: 2 }, message: { type: "panel_resp", panel: "npcshop",
    panelInstanceId: "panel.fixture", domain: "inventory", cmd: "snapshot", callId: "call.1",
    success: true } };
  assert.strictEqual(Protocol.requestPairs([request], [response]).length, 1);
  [
    ["panelInstanceId", "foreign.panel"],
    ["panelInstanceId", null],
    ["domain", "npcshop"],
    ["cmd", "tradePreview"],
    ["callId", "foreign.call"],
  ].forEach(([field, value]) => {
    const drift = deepClone(response);
    drift.message[field] = value;
    assert.throws(() => Protocol.requestPairs([request], [drift]),
      (error) => error instanceof NpcJourneyError && error.code === "response_bijection_invalid");
  });
  assert.throws(() => Protocol.requestPairs([request], [response, deepClone(response)]),
    (error) => error instanceof NpcJourneyError && error.code === "response_count_invalid");
});
test("v9 dynamic Inventory surface rejects envelope, boundary, pair-set, time, tail, and metadata drift", () =>
  withFixture({}, (fixture) => {
    const bundle = load(fixture);
    const transcript = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
      bundle.transcriptArtifact), "utf8"));
    const allPairs = Protocol.strictRequestPairsFromEvents(transcript.events);
    const byCallId = new Map(allPairs.map((pair) => [pair.request.message.callId, pair]));
    const pairs = bundle.calls.purchasePostInventories.map((callId) => byCallId.get(callId));
    const valid = Protocol.assertInventorySnapshotSurface(pairs, "v8_valid_surface");
    assert.strictEqual(valid.accessibleCapacity, 240);
    assert.deepStrictEqual(valid.callIds, bundle.calls.purchasePostInventories);
    assert.strictEqual(Protocol.inventoryWindows(valid, "v8_valid_surface")
      .get("战备箱").slots.length, 240);
    function rejected(mutator, codes) {
      const drift = deepClone(pairs);
      mutator(drift);
      assert.throws(() => Protocol.assertInventorySnapshotSurface(drift, "v8_negative"),
        (error) => error instanceof NpcJourneyError && [].concat(codes).includes(error.code));
    }
    rejected((drift) => { drift[0].response.message.snapshots[1].capacity = 401; },
      "inventory_surface_metadata_drift");
    rejected((drift) => { drift[0].response.message.untrustedExtra = true; },
      "inventory_snapshot_invalid");
    rejected((drift) => { delete drift[0].response.message.sessionNonce; },
      "inventory_snapshot_invalid");
    rejected((drift) => { drift[0].response.message.v = 2; },
      "inventory_snapshot_invalid");
    rejected((drift) => { drift[0].response.message.success = false; },
      "inventory_snapshot_invalid");
    rejected((drift) => { drift.push(deepClone(drift[2])); },
      "inventory_surface_pair_set_invalid");
    rejected((drift) => {
      drift[0].response.message.snapshots[1].accessibleCapacity = 100;
      drift[0].response.message.snapshots[1].viewCapacity = 100;
    }, "inventory_battle_access_invalid");
    rejected((drift) => { drift.pop(); }, "inventory_surface_pair_set_invalid");
    rejected((drift) => { drift[1].request.message.payload.requests[0].offset = 99; },
      "inventory_surface_order_invalid");
    rejected((drift) => {
      drift[1].response.message.snapshots[0].slots[0].physicalSlot = 99;
    }, "inventory_surface_window_invalid");
    rejected((drift) => { [drift[1], drift[2]] = [drift[2], drift[1]]; },
      "inventory_surface_order_invalid");
    rejected((drift) => {
      drift[1].request.event.observedAt = drift[0].response.event.observedAt;
    }, "inventory_surface_order_invalid");
    rejected((drift) => {
      drift[1].response.event.observedAt = drift[1].request.event.observedAt;
    }, "inventory_surface_order_invalid");
    rejected((drift) => { drift[1].response.message.callId = "npc.fixture.foreign.response"; },
      "inventory_surface_owner_drift");
    [
      ["accessibleCapacity", 200], ["viewCapacity", 200],
      ["pageSizeHint", 50], ["locked", true],
    ].forEach(([field, value]) => rejected((drift) => {
      drift[1].response.message.snapshots[0][field] = value;
    }, ["inventory_surface_metadata_drift", "inventory_surface_window_invalid"]));

    const initial = inventorySurface(fixture, bundle, bundle.calls.initialInventorySnapshots,
      "v8_initial");
    assert.doesNotThrow(() => assertStableRevisionLeases(initial, valid, "v8_stable"));
    const phaseDrift = deepClone(valid);
    phaseDrift.accessibleCapacity = 200;
    assert.throws(() => assertInventoryPhaseAccessConsistency([initial, phaseDrift], "v8_phase"),
      (error) => error instanceof NpcJourneyError && error.code === "inventory_phase_access_drift");
    const tailItemDrift = deepClone(valid);
    tailItemDrift.snapshots.find((snapshot) => snapshot.containerId === "战备箱")
      .slots.at(-1).item.displayName = "forged-tail";
    assert.throws(() => assertStableRevisionLeases(initial, tailItemDrift, "v8_tail_item"),
      (error) => error instanceof NpcJourneyError && error.code === "inventory_stable_revision_drift");
    const tailLeaseDrift = deepClone(valid);
    tailLeaseDrift.snapshots.find((snapshot) => snapshot.containerId === "战备箱")
      .slots.at(-1).slotLease = "forged-tail-lease";
    assert.throws(() => assertStableRevisionLeases(initial, tailLeaseDrift, "v8_tail_lease"),
      (error) => error instanceof NpcJourneyError && error.code === "inventory_stable_revision_drift");
  }));
test("v8 locked A=0 returns an empty first battle window and never supplements", () =>
  withFixture({ battleAccessibleCapacity: 0 }, (fixture) => {
    const bundle = load(fixture);
    assert.strictEqual(verifyEvidenceFile(fixture.bundlePath).status, "OFFLINE_VERIFIED");
    assert.strictEqual(bundle.calls.initialInventorySnapshots.length, 1);
    const surface = inventorySurface(fixture, bundle, bundle.calls.initialInventorySnapshots,
      "v8_locked_surface");
    const battle = Protocol.inventoryWindows(surface, "v8_locked_surface").get("战备箱");
    assert.deepStrictEqual([battle.capacity, battle.accessibleCapacity, battle.viewCapacity,
      battle.pageSizeHint, battle.locked, battle.limit, battle.slots.length],
    [400, 0, 0, 40, true, 0, 0]);
  }));
test("v8 A=200 stops after the exact offset100 supplement", () =>
  withFixture({ battleAccessibleCapacity: 200 }, (fixture) => {
    const bundle = load(fixture);
    assert.strictEqual(verifyEvidenceFile(fixture.bundlePath).status, "OFFLINE_VERIFIED");
    assert.strictEqual(bundle.calls.restartInventorySnapshots.length, 2);
    const surface = inventorySurface(fixture, bundle, bundle.calls.restartInventorySnapshots,
      "v8_a200_surface");
    assert.deepStrictEqual(surface.windows.filter((window) =>
      window.snapshot.containerId === "战备箱").map((window) =>
      [window.request.offset, window.request.limit, window.snapshot.limit]),
    [[0, 100, 100], [100, 100, 100]]);
  }));
test("v10 production physical reader executes every allowed battle-access boundary", () => {
  const capacities = [0, 40, 80, 120, 160, 200, 240];
  function expectedBatches(accessibleCapacity) {
    const batches = [[
      { containerId:"背包", offset:0, limit:50, filterKey:"all" },
      { containerId:"战备箱", offset:0, limit:100, filterKey:"all" },
    ]];
    if (accessibleCapacity > 100) batches.push([
      { containerId:"战备箱", offset:100, limit:100, filterKey:"all" },
    ]);
    if (accessibleCapacity > 200) batches.push([
      { containerId:"战备箱", offset:200, limit:accessibleCapacity - 200, filterKey:"all" },
    ]);
    return batches;
  }
  function snapshot(request, accessibleCapacity, sequence) {
    const bag = request.containerId === "背包";
    const access = bag ? 50 : accessibleCapacity;
    const limit = Math.min(request.limit, Math.max(0, access - request.offset));
    return {
      containerId:request.containerId, capacity:bag ? 50 : 400,
      accessibleCapacity:access, viewCapacity:access, filterKey:"all",
      pageSizeHint:bag ? 50 : 40, locked:!bag && access === 0,
      snapshotSeq:sequence, containerEpoch:bag ? 10 : 20, containerVersion:1,
      offset:request.offset, limit,
      slots:Array.from({ length:limit }, (_unused, index) => ({
        physicalSlot:request.offset + index, occupied:false,
        slotLease:"npc.boundary." + (bag ? "bag." : "battle.") + (request.offset + index),
      })),
      filterFacets:[], filterItemCount:0, setFacets:[], setFilterItemCount:0,
    };
  }
  capacities.forEach((accessibleCapacity) => {
    const batches = expectedBatches(accessibleCapacity);
    const calls = [];
    let completion = null;
    let completionCount = 0;
    const started = InventoryRuntime.readPhysicalInventorySurface(
      (cmd, payload, callback) => {
        const ordinal = calls.length;
        const callId = "npc.boundary." + accessibleCapacity + "." + ordinal;
        calls.push({ cmd, requests:deepClone(payload.requests) });
        callback({
          success:true, v:1, sessionNonce:"npc.boundary.session." + accessibleCapacity,
          snapshots:payload.requests.map((request, index) =>
            snapshot(request, accessibleCapacity, 10 + ordinal * 3 + index)),
          type:"panel_resp", domain:"inventory", cmd:"snapshot", callId,
          panel:"npcshop", panelInstanceId:"npc.boundary.owner",
        });
        return callId;
      },
      { isActive:() => true, expectedPanel:"npcshop",
        expectedPanelInstanceId:"npc.boundary.owner" },
      (result) => { completionCount += 1; completion = result; });
    assert.strictEqual(started, true, "A=" + accessibleCapacity + " start");
    assert.strictEqual(completionCount, 1, "A=" + accessibleCapacity + " completion");
    assert.strictEqual(completion && completion.success, true,
      "A=" + accessibleCapacity + " result " + JSON.stringify(completion));
    assert.deepStrictEqual(calls.map((call) => call.requests), batches,
      "A=" + accessibleCapacity + " request batches");
    assert.strictEqual(completion.surface.responseCount, batches.length,
      "A=" + accessibleCapacity + " response count");
    assert.strictEqual(completion.surface.windows.length, batches.length + 1,
      "A=" + accessibleCapacity + " raw windows");
    assert.strictEqual(completion.surface.snapshots.length, 2,
      "A=" + accessibleCapacity + " merged snapshots");
    const bag = completion.surface.snapshots[0];
    const battle = completion.surface.snapshots[1];
    assert.deepStrictEqual([bag.containerId, bag.slots.length, battle.containerId,
      battle.offset, battle.limit, battle.slots.length, battle.accessibleCapacity,
      battle.pageSizeHint, battle.locked],
    ["背包", 50, "战备箱", 0, accessibleCapacity, accessibleCapacity,
      accessibleCapacity, 40, accessibleCapacity === 0], "A=" + accessibleCapacity + " merge");
    assert.strictEqual(completion.snapshots[1].limit, Math.min(40, accessibleCapacity),
      "A=" + accessibleCapacity + " visible limit");
    assert.strictEqual(completion.snapshots[1].slots.length, Math.min(40, accessibleCapacity),
      "A=" + accessibleCapacity + " visible slots");
    if (accessibleCapacity === 0) {
      assert.strictEqual(calls.length, 1, "A=0 no supplement");
      assert.strictEqual(calls[0].requests[1].limit, 100, "A=0 exact first probe");
      assert.strictEqual(completion.surface.windows[1].limit, 0, "A=0 authority empty limit");
    }
  });
});
negative("full bundle rejects an extra successful response without a request", (fixture) =>
  reseal(fixture, (events) => {
    const source = events.find((event) => event.kind === "webview_message" && event.message
      && event.message.callId === fixture.bundle.calls.purchasePostInventory);
    const orphan = deepClone(source);
    orphan.message.callId = "npc.fixture.orphan.response";
    const detachIndex = events.map((event) => event.kind).lastIndexOf("observer_detached");
    assert(detachIndex > 0, "fixture final observer_detached is missing");
    const before = Date.parse(events[detachIndex - 1].observedAt);
    const after = Date.parse(events[detachIndex].observedAt);
    orphan.observedAt = new Date(Math.floor((before + after) / 2)).toISOString();
    events.splice(detachIndex, 0, orphan);
  }), "response_bijection_invalid");
test("canonical authority projection retains complete state and separates all sources", () =>
  withFixture({}, (fixture) => {
    const bundle = load(fixture);
    const transcript = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
      bundle.transcriptArtifact), "utf8"));
    function response(callId) {
      return transcript.events.find((event) => event.kind === "webview_message"
        && event.message && event.message.callId === callId).message;
    }
    const projection = Protocol.canonicalAuthorityProjection(response(bundle.calls.saleCommit),
      inventorySurface(fixture, bundle, bundle.calls.salePostInventories,
        "canonical_projection"), bundle.purchasePolicy);
    assert.strictEqual(projection.semantic.inventory.snapshots
      .reduce((total, snapshot) => total + snapshot.slots.length, 0), 290);
    assert.strictEqual(projection.source.inventory.snapshots
      .reduce((total, snapshot) => total + snapshot.slots.length, 0), 290);
    const purchased = projection.semantic.inventory.snapshots
      .find((snapshot) => snapshot.containerId === "背包").slots
      .find((slot) => slot.physicalSlot === PURCHASE_SLOT);
    assert.strictEqual(purchased.item.rarity, purchased.confirmProjection.rarity);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(purchased, "slotLease"), false);
    assert.strictEqual(projection.semantic.npc.selection.catalogIndex,
      bundle.purchasePolicy.catalogIndex);
  }));
test("Launcher Agent preferred path verifies", () => withFixture({ launcherAvailable: true }, (fixture) => {
  assert.strictEqual(verifyEvidenceFile(fixture.bundlePath).transport, "launcher_agent_runtime");
}));
test("stack sale narrows to one unit", () => withFixture({ salePreQuantity: 25 }, (fixture) => {
  const receipt = verifyEvidenceFile(fixture.bundlePath);
  assert.strictEqual(receipt.sale.previewCount, 2);
  assert.strictEqual(receipt.sale.quantity, 1);
}));
test("purchase-only remains non-closable", () => withFixture({ purchaseOnly: true }, (fixture) => {
  const receipt = verifyEvidenceFile(fixture.bundlePath);
  assert.strictEqual(receipt.writeCount, 1);
  assert.strictEqual(receipt.scopeComplete, false);
  assert.strictEqual(receipt.liveStatus, "LIVE_BLOCKED");
  assert.strictEqual(receipt.a3NpcClosable, false);
}));
test("runner requires explicit bounded-write flags", () => {
  const base = ["--candidate-root", path.resolve("fixture-candidate"),
    "--allow-isolated-commit", "--allow-codex-cu-fallback"];
  assert.doesNotThrow(() => validateArgs(parseArgs(base)));
  assert.throws(() => validateArgs(parseArgs(base.slice(0, -1))), /fallback/);
});
test("purchase selection is affordable deterministic and differs from sale", () => {
  const selected = selectPurchaseTarget({ balance: 50, buyMultiplier: 1, catalog: [
    { catalogIndex: 4, itemName: "砍刀", displayName: "砍刀", icon: "a", majorType: "武器",
      basePrice: 1, unitPrice: 1, maxQuantity: 1, locked: false },
    { catalogIndex: 2, itemName: "乙", displayName: "乙", icon: "b", majorType: "武器",
      basePrice: 20, unitPrice: 20, maxQuantity: 1, locked: false },
  ] }, { purchaseOnly: false, expectedSaleItem: "砍刀" });
  assert.strictEqual(selected.catalogIndex, 2);
});
test("sale selector prefers exact slot-zero machete", () => withFixture({}, (fixture) => {
  const bundle = load(fixture);
  const transcript = JSON.parse(fs.readFileSync(path.join(fixture.runDir, bundle.transcriptArtifact), "utf8"));
  const selected = selectSaleTarget(inventorySurface(fixture, bundle,
    bundle.calls.purchasePostInventories, "sale_selector"), bundle.purchasePolicy, {});
  assert.deepStrictEqual([selected.slot, selected.expectedItem, selected.quantity], [0, "砍刀", 1]);
}));
test("shared adapter is a frozen callable surface", () => {
  const adapter = loadSharedAdapter(path.resolve(__dirname, "..", "..", ".."));
  assert.strictEqual(typeof adapter.prepare, "function");
  const source = fs.readFileSync(path.join(__dirname, "shared-adapter.js"), "utf8");
  assert(source.includes("async awaitExactClose("));
  assert.strictEqual(source.includes("readTerminalLogSnapshot(4000)"), false);
});
test("passive observer uses mature ws and no business action", () => {
  const source = fs.readFileSync(path.join(__dirname, "passive-recorder.js"), "utf8");
  assert(source.includes('playwright-core/lib/utilsBundle.js").ws'));
  ["page.click(", "Bridge.send(", "Panels.open(", "mouse.click(", "keyboard.press("].forEach((needle) =>
    assert.strictEqual(source.includes(needle), false));
});
test("v12 production Inventory facade, adapter, provider, and executable bindings remain jointly closed", () => {
  const root = path.resolve(__dirname, "../../..");
  const consumer = fs.readFileSync(path.join(root,
    "launcher/web/modules/npcshop.js"), "utf8");
  const adapter = fs.readFileSync(path.join(root,
    "launcher/web/modules/npcshop-runtime.js"), "utf8");
  const provider = fs.readFileSync(path.join(root,
    "launcher/web/modules/inventory-runtime.js"), "utf8");
  const current = ProductionClosure.inspectInventorySurfaceSourceContract(
    consumer, adapter, provider);
  assert.strictEqual(current.valid, true, JSON.stringify(current));
  function replaceWhitespaceInsensitiveOnce(source, from, to, label) {
    const needle = String(from).replace(/\s+/g, "");
    let compact = "";
    const offsets = [];
    for (let index = 0; index < source.length; index += 1) {
      if (/\s/.test(source[index])) continue;
      compact += source[index];
      offsets.push(index);
    }
    const found = compact.indexOf(needle);
    assert(found >= 0, label + " mutation anchor");
    assert.strictEqual(compact.indexOf(needle, found + needle.length), -1,
      label + " mutation anchor must be unique");
    return source.slice(0, offsets[found]) + to
      + source.slice(offsets[found + needle.length - 1] + 1);
  }
  function rejected(label, sourceName, from, to, expectedGroup, expectedId) {
    const sources = { consumer, adapter, provider };
    sources[sourceName] = replaceWhitespaceInsensitiveOnce(
      sources[sourceName], from, to, label);
    const report = ProductionClosure.inspectInventorySurfaceSourceContract(
      sources.consumer, sources.adapter, sources.provider);
    assert.strictEqual(report.valid, false, label);
    assert(report[expectedGroup].includes(expectedId), label + " report " + JSON.stringify(report));
  }
  function rejectedSyntaxValid(label, sourceName, from, to, expectedGroup, expectedId) {
    const sources = { consumer, adapter, provider };
    sources[sourceName] = replaceWhitespaceInsensitiveOnce(
      sources[sourceName], from, to, label);
    assert.doesNotThrow(() => Function(sources[sourceName]), label + " syntax");
    const report = ProductionClosure.inspectInventorySurfaceSourceContract(
      sources.consumer, sources.adapter, sources.provider);
    assert.strictEqual(report.valid, false, label);
    assert(report[expectedGroup].includes(expectedId), label + " report " + JSON.stringify(report));
  }
  function acceptedSyntaxValid(label, sourceName, from, to) {
    const sources = { consumer, adapter, provider };
    sources[sourceName] = replaceWhitespaceInsensitiveOnce(
      sources[sourceName], from, to, label);
    assert.doesNotThrow(() => Function(sources[sourceName]), label + " syntax");
    const report = ProductionClosure.inspectInventorySurfaceSourceContract(
      sources.consumer, sources.adapter, sources.provider);
    assert.strictEqual(report.valid, true, label + " report " + JSON.stringify(report));
  }
  function rejectedByClosedSource(label, sourceName, from, to) {
    rejectedSyntaxValid(label, sourceName, from, to, "forbidden",
      sourceName + ":closed_source_bytes_changed");
  }
  rejected("facade must delegate to the physical adapter", "consumer",
    "NpcShopRuntime.createPhysicalInventoryAdapter({", "NpcShopRuntime.createDetachedAdapter({",
    "missing", "consumer:npc_adapter_delegation");
  rejected("session reset must remain before owner open", "consumer",
    "if(!_inventoryAdapter.resetSession())returnfalse;if(!_owner.open(initData.panelInstanceId))returnfalse;",
    "if(!_owner.open(initData.panelInstanceId))returnfalse;if(!_inventoryAdapter.resetSession())returnfalse;",
    "outOfOrder", "consumer_session_open:npc_owner_open");
  rejected("facade must reset the inventory session", "consumer",
    "if(!_inventoryAdapter.resetSession())returnfalse;", "",
    "missing", "consumer:npc_on_open_session_reset");
  rejected("inventory retry state must fence write interaction", "consumer",
    "functioninventoryWriteUnavailable(){return!_inventoryState.ready"
      + "||!!_inventoryState.busyOwner||!!_inventoryState.refreshRequired;}",
    "functioninventoryWriteUnavailable(){returnfalse;}",
    "missing", "consumer:npc_inventory_write_fence");
  rejected("retry control must invoke a fresh snapshot", "consumer",
    "_retryButton.addEventListener('click',refreshSnapshot);",
    "_retryButton.addEventListener('click',function(){});",
    "missing", "consumer:npc_retry_listener");
  rejected("settlement entry must remain inventory-fenced", "consumer",
    "if(!selectionCount()||_busy||_owner.needsReconcile||inventoryWriteUnavailable())return;",
    "if(!selectionCount()||_busy||_owner.needsReconcile)return;",
    "missing", "consumer:npc_open_settlement_write_fence");
  rejected("preview dispatch must remain inventory-fenced", "consumer",
    "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
      + "||!_settlementPresenter||!_settlementPresenter.isActive())return;",
    "if(_busy||_owner.needsReconcile||!_settlementPresenter"
      + "||!_settlementPresenter.isActive())return;",
    "missing", "consumer:npc_preview_write_fence");
  rejected("commit dispatch must remain inventory-fenced", "consumer",
    "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
      + "||!_settlement||!_settlement.canCommit||_previewBusy)return;",
    "if(_busy||_owner.needsReconcile||!_settlement"
      + "||!_settlement.canCommit||_previewBusy)return;",
    "missing", "consumer:npc_commit_write_fence");
  rejected("generic write dispatch must remain inventory-fenced", "consumer",
    "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()){",
    "if(_busy||_owner.needsReconcile){",
    "missing", "consumer:npc_write_dispatch_fence");
  rejected("adapter must bind the exact NPC owner", "adapter",
    "expectedPanel:'npcshop'", "expectedPanel:'kshop'",
    "missing", "adapter:adapter_exact_owner");
  rejected("adapter must retain the canonical initial visible windows", "adapter",
    "{containerId:'战备箱',offset:0,limit:40,filterKey:'all'}",
    "{containerId:'战备箱',offset:0,limit:80,filterKey:'all'}",
    "missing", "adapter:adapter_initial_windows");
  rejected("reset must remain closed-only", "adapter",
    "if(coordinator.debugState().opened)returnfalse;", "if(false)returnfalse;",
    "missing", "adapter:adapter_reset_closed_only");
  rejected("reset must preserve backpack offset", "adapter",
    "offset:backpack.offset,limit:50", "offset:0,limit:50",
    "missing", "adapter:adapter_reset_atomic_configure");
  rejected("reset must preserve battlebox offset", "adapter",
    "offset:battlebox.offset,limit:40", "offset:0,limit:40",
    "missing", "adapter:adapter_reset_atomic_configure");
  rejected("reset must retain fixed limits", "adapter",
    "offset:backpack.offset,limit:50", "offset:backpack.offset,limit:51",
    "missing", "adapter:adapter_reset_atomic_configure");
  rejected("reset must clear structured filters", "adapter",
    "offset:backpack.offset,limit:50,filterKey:'all'},",
    "offset:backpack.offset,limit:50,filterKey:'all',filterSpec:{}},",
    "missing", "adapter:adapter_reset_atomic_configure");
  rejected("reset must be one atomic configure", "adapter",
    "returncoordinator.configureRequests([", "coordinator.resetWindow('背包',0,50,'all');"
      + "returncoordinator.configureRequests([",
    "forbidden", "adapter:reset_uses_sequential_window_mutation");
  rejected("refresh must not reset the caller visible page", "adapter",
    "varself=this,coordinator=this.coordinator;coordinator.open(function(result){",
    "varself=this,coordinator=this.coordinator;"
      + "coordinator.resetWindow('战备箱',0,40,'all');coordinator.open(function(result){",
    "forbidden", "adapter:refresh_calls_reset_window");
  [
    ["reset the session", "coordinator.resetSession();", "adapter:refresh_calls_reset_session"],
    ["configure requests", "coordinator.configureRequests([]);",
      "adapter:refresh_calls_configure_requests"],
    ["close the coordinator", "coordinator.close();", "adapter:refresh_closes_coordinator"],
  ].forEach((entry) => rejected("refresh must not " + entry[0], "adapter",
    "varself=this,coordinator=this.coordinator;coordinator.open(function(result){",
    "varself=this,coordinator=this.coordinator;" + entry[1] + "coordinator.open(function(result){",
    "forbidden", entry[2]));
  rejected("adapter must preserve a detached complete-surface receipt", "adapter",
    "?JSON.parse(JSON.stringify(result.surface)):null;", "?result.surface:null;",
    "missing", "adapter:adapter_receipt_copy");
  const requestReturn = "expectedCallId=request('snapshot',{v:1,requests:expectedRequests},function(response){";
  const bareRequest = "request('snapshot',{v:1,requests:expectedRequests},function(response){";
  rejected("missing request-return callId", "provider", requestReturn, bareRequest,
    "missing", "provider:request_returns_expected_call_id");
  rejected("boolean request return", "provider", requestReturn, "expectedCallId=true;" + bareRequest,
    "forbidden", "provider:boolean_request_return");
  rejected("object request return", "provider", requestReturn,
    "expectedCallId={callId:'forged'};" + bareRequest,
    "forbidden", "provider:object_request_return");
  rejected("missing response callId equality", "provider",
    "||!isIdentityText(response.callId,160)||response.callId!==expectedCallId"
      + "||!isIdentityText(response.panel,64)",
    "||!isIdentityText(response.callId,160)||!isIdentityText(response.panel,64)",
    "missing", "provider:response_call_id_equals_expected");
  const ownerFailClosed = "if(!isIdentityText(expectedPanel,64)||(expectedPanelInstanceId!=null"
    + "&&!isIdentityText(expectedPanelInstanceId,128))){"
    + "reject('inventory_surface_owner_invalid',true);returnfalse;}";
  const legacyOwnerReject = "if(!isIdentityText(expectedPanel,64)||(expectedPanelInstanceId!=null"
    + "&&!isIdentityText(expectedPanelInstanceId,128))){"
    + "returnreject('inventory_surface_owner_invalid');}";
  rejected("legacy return reject", "provider", ownerFailClosed, legacyOwnerReject,
    "forbidden", "provider:legacy_owner_return_reject");
  const exceptionFailClosed = "}catch(_error){returned=true;if(ordinal===0)"
    + "reject('inventory_surface_request_contract_invalid',true);"
    + "elsereject('inventory_surface_request_contract_invalid');returnfalse;}";
  rejected("request exception must fail closed", "provider", exceptionFailClosed,
    "}catch(_error){returnfalse;}", "missing", "provider:request_exception_fail_closed");
  const invalidReturnFailClosed = "if(!isIdentityText(expectedCallId,160)){if(ordinal===0)"
    + "reject('inventory_surface_request_contract_invalid',true);"
    + "elsereject('inventory_surface_request_contract_invalid');returnfalse;}";
  const currentInvalidReturnFence = invalidReturnFailClosed.replace(
    "if(!isIdentityText(expectedCallId,160))", "if(!isIdentityText(expectedCallId,160)||queuedDuplicate)");
  rejected("invalid request return must reject once", "provider", currentInvalidReturnFence,
    "if(!isIdentityText(expectedCallId,160)||queuedDuplicate){returnfalse;}",
    "missing", "provider:invalid_request_return_fail_closed");
  const physicalSyncFence = "if(!returned){if(queued)queuedDuplicate=true;"
    + "else{queued=true;queuedResponse=response;}return;}handleResponse(response);";
  rejected("physical batches must reject synchronous duplicates", "provider",
    physicalSyncFence, physicalSyncFence.replace("if(queued)queuedDuplicate=true;", "if(queued)return;"),
    "missing", "provider:physical_sync_duplicate_fence");
  [
    ["filter key", "normalizeFilterKey(request&&request.filterKey)!=='all'"],
    ["structured filter", "||!!request&&own(request,'filterSpec')"],
    ["projection scope", "||normalizeProjectionScope(request&&request.scope)!=='all'"],
  ].forEach((entry) => rejected("projection classifier must retain " + entry[0], "provider",
    entry[1], "", "missing", "provider:projection_constraint_classifier"));
  rejected("constrained requests must use an exact authority follow-up", "provider",
    "if(requestsNeedAuthorityProjection(desiredRequests)){", "if(false){",
    "forbidden", "provider:constrained_projection_bypassed");
  rejected("local projection must reject constrained requests", "provider",
    "if(requestNeedsAuthorityProjection(request))returnnull;", "",
    "missing", "provider:local_projection_rejects_constrained");
  rejected("authority follow-up must use the exact visible request set", "provider",
    "expectedCallId=self._request('snapshot',{v:1,requests:cloneRequests(desiredRequests)},"
      + "function(response){",
    "expectedCallId=self._request('snapshot',{v:1,requests:[]},function(response){",
    "missing", "provider:projection_exact_desired_request");
  rejected("authority follow-up must bind response callId", "provider",
    "if(!response||response.callId!==expectedCallId){", "if(!response){",
    "missing", "provider:projection_exact_call_id");
  const projectionSyncFence = "if(!returned){if(queued)queuedDuplicate=true;"
    + "else{queued=true;queuedResponse=response;}return;}handleProjectionResponse(response);";
  rejected("authority follow-up must reject synchronous duplicates", "provider",
    projectionSyncFence, projectionSyncFence.replace("if(queued)queuedDuplicate=true;", "if(queued)return;"),
    "missing", "provider:projection_sync_duplicate_fence");
  rejected("authority follow-up exceptions must complete once", "provider",
    "}catch(_projectionRequestError){returned=true;failProjectionRequestContract();return;}",
    "}catch(_projectionRequestError){return;}",
    "missing", "provider:projection_exception_fence");
  rejected("authority follow-up invalid returns must complete once", "provider",
    "if(!isIdentityText(expectedCallId,160)||queuedDuplicate){"
      + "failProjectionRequestContract();return;}",
    "if(!isIdentityText(expectedCallId,160)||queuedDuplicate){return;}",
    "missing", "provider:projection_invalid_return_fence");
  rejected("authority response completion must be single-shot", "provider",
    "functionhandleProjectionResponse(response){"
      + "if(projectionDone||!self._isActiveOperation(operation))return;projectionDone=true;",
    "functionhandleProjectionResponse(response){projectionDone=true;",
    "missing", "provider:projection_response_single_completion");
  rejected("authority failure completion must be single-shot", "provider",
    "functionfailProjectionRequestContract(){"
      + "if(projectionDone||!self._isActiveOperation(operation))return;projectionDone=true;finish(",
    "functionfailProjectionRequestContract(){finish(",
    "missing", "provider:projection_failure_single_completion");
  rejected("authority response must retain v1", "provider",
    "||!Array.isArray(surface.windows)||!Array.isArray(surface.snapshots)"
      + "||!response||response.success!==true||response.v!==1"
      + "||!isIdentityText(response.sessionNonce,128)",
    "||!Array.isArray(surface.windows)||!Array.isArray(surface.snapshots)"
      + "||!response||response.success!==true||!isIdentityText(response.sessionNonce,128)",
    "missing", "provider:projection_response_v1");
  const coherence = [
    ["session", "||response.sessionNonce!==surface.sessionNonce)returnfalse;",
      "||false)returnfalse;", "projection_same_session"],
    ["capacity", "snapshot.capacity!==full.capacity", "false", "projection_same_capacity"],
    ["accessible capacity", "snapshot.accessibleCapacity!==full.accessibleCapacity",
      "false", "projection_same_accessibility"],
    ["page size", "snapshot.pageSizeHint!==full.pageSizeHint", "false", "projection_same_page_size"],
    ["lock state", "snapshot.locked!==full.locked", "false", "projection_same_lock_state"],
    ["epoch", "snapshot.containerEpoch!==full.containerEpoch", "false", "projection_same_epoch"],
    ["version", "snapshot.containerVersion!==full.containerVersion", "false", "projection_same_version"],
    ["later sequence", "snapshot.snapshotSeq<=maximumSurfaceSequence", "false",
      "projection_later_sequence"],
    ["filter facets", "!sameProjectionValue(snapshot.filterFacets,full.filterFacets)",
      "false", "projection_same_filter_facets"],
    ["filter count", "snapshot.filterItemCount!==full.filterItemCount",
      "false", "projection_same_filter_count"],
    ["set facets", "!sameProjectionValue(snapshot.setFacets,full.setFacets)",
      "false", "projection_same_set_facets"],
    ["set count", "snapshot.setFilterItemCount!==full.setFilterItemCount",
      "false", "projection_same_set_count"],
    ["physical slot", "!sameProjectionValue(visibleSlot,full.slots[physicalSlot])",
      "false", "projection_exact_physical_slots"],
  ];
  coherence.forEach((entry) => rejected("paired " + entry[0] + " must remain equal", "provider",
    entry[1], entry[2], "missing", "provider:" + entry[3]));
  const retainedReceipt = "varvalid=authorityProjectionMatchesPhysicalSurface(response,result.surface,"
    + "desiredRequests,self._windows)&&self._applySnapshots(response.snapshots,desiredRequests);"
    + "finish(valid?{success:true}:{success:false,error:'inventory_surface_projection_invalid'},"
    + "result.surface);";
  rejected("authority visible response must retain the physical receipt", "provider",
    retainedReceipt, retainedReceipt.replace(",result.surface);", ",null);"),
    "missing", "provider:projection_retains_physical_receipt");
  rejected("comment copy cannot restore reset-before-open ordering", "consumer",
    "if(!_inventoryAdapter.resetSession())returnfalse;if(!_owner.open(initData.panelInstanceId))returnfalse;",
    "if(!_owner.open(initData.panelInstanceId))returnfalse;"
      + "if(!_inventoryAdapter.resetSession())returnfalse;"
      + "/*if(!_inventoryAdapter.resetSession())returnfalse;"
      + "if(!_owner.open(initData.panelInstanceId))returnfalse;*/",
    "outOfOrder", "consumer_session_open:npc_owner_open");
  rejected("comment copy cannot restore the closed-only reset gate", "adapter",
    "if(coordinator.debugState().opened)returnfalse;",
    "if(false)returnfalse;/*if(coordinator.debugState().opened)returnfalse;*/",
    "missing", "adapter:adapter_reset_closed_only");
  rejected("comment copy cannot restore revision coherence", "provider",
    "snapshot.containerVersion!==full.containerVersion",
    "false/*snapshot.containerVersion!==full.containerVersion*/",
    "missing", "provider:projection_same_version");
  rejected("string copy cannot restore the retry listener", "consumer",
    "_retryButton.addEventListener('click',refreshSnapshot);",
    "_retryButton.onclick=null;var retryDecoy=\"_retryButton.addEventListener('click',refreshSnapshot);\";",
    "missing", "consumer:npc_retry_listener");
  const retryBlock = "_retryButton=document.createElement('button');"
    + "_retryButton.type='button';"
    + "_retryButton.className='workbench-mode-btn warning npcshop-retry-btn';"
    + "_retryButton.textContent='重新同步';"
    + "_retryButton.addEventListener('click',refreshSnapshot);"
    + "_shell.addHeaderAction(_retryButton);";
  const versionBlock = "if(!full||snapshot.capacity!==full.capacity"
    + "||snapshot.accessibleCapacity!==full.accessibleCapacity"
    + "||snapshot.pageSizeHint!==full.pageSizeHint"
    + "||snapshot.locked!==full.locked"
    + "||snapshot.containerEpoch!==full.containerEpoch"
    + "||snapshot.containerVersion!==full.containerVersion"
    + "||snapshot.snapshotSeq<=maximumSurfaceSequence)returnfalse;";
  const checkoutBlock = "if(_checkoutButton){"
    + "_checkoutButton.textContent=count?'结算 ('+count+')':'结算';"
    + "_checkoutButton.disabled=!count||_busy||_owner.needsReconcile"
    + "||inventoryWriteUnavailable();}";
  [
    ["retry listener", "consumer", retryBlock, "if(false){" + retryBlock + "}",
      "consumer:npc_retry_listener"],
    ["closed-only reset", "adapter", "if(coordinator.debugState().opened)returnfalse;",
      "if(false){if(coordinator.debugState().opened)returnfalse;}",
      "adapter:adapter_reset_closed_only"],
    ["revision coherence", "provider", versionBlock, "if(false){" + versionBlock + "}",
      "provider:projection_same_version"],
    ["settlement entry fence", "consumer",
      "if(!selectionCount()||_busy||_owner.needsReconcile||inventoryWriteUnavailable())return;",
      "if(false){if(!selectionCount()||_busy||_owner.needsReconcile"
        + "||inventoryWriteUnavailable())return;}",
      "consumer:npc_open_settlement_write_fence"],
    ["preview fence", "consumer",
      "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
        + "||!_settlementPresenter||!_settlementPresenter.isActive())return;",
      "if(false){if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
        + "||!_settlementPresenter||!_settlementPresenter.isActive())return;}",
      "consumer:npc_preview_write_fence"],
    ["commit fence", "consumer",
      "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
        + "||!_settlement||!_settlement.canCommit||_previewBusy)return;",
      "if(false){if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
        + "||!_settlement||!_settlement.canCommit||_previewBusy)return;}",
      "consumer:npc_commit_write_fence"],
    ["write dispatch fence", "consumer",
      "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()){"
        + "toast(_owner.needsReconcile||_inventoryState.refreshRequired||!_inventoryState.ready"
        + "?'请先重新同步商店状态。':'正在处理上一项交易。');returnfalse;}",
      "if(false){if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()){"
        + "toast(_owner.needsReconcile||_inventoryState.refreshRequired||!_inventoryState.ready"
        + "?'请先重新同步商店状态。':'正在处理上一项交易。');returnfalse;}}",
      "consumer:npc_write_dispatch_fence"],
    ["checkout disable fence", "consumer", checkoutBlock, "if(false){" + checkoutBlock + "}",
      "consumer:npc_checkout_write_fence"],
  ].forEach((entry) => rejected("dead branch cannot restore " + entry[0], entry[1],
    entry[2], entry[3], "misplaced", entry[4]));
  rejected("unused nested function cannot restore the retry listener", "consumer",
    "_retryButton.addEventListener('click',refreshSnapshot);",
    "_retryButton.onclick=null;function inactiveRetry(){"
      + "_retryButton.addEventListener('click',refreshSnapshot);}",
    "missing", "consumer:npc_retry_listener");
  rejected("unbraced constant branch cannot restore the retry listener", "consumer",
    "_retryButton.addEventListener('click',refreshSnapshot);",
    "_retryButton.onclick=null;if(false)_retryButton.addEventListener('click',refreshSnapshot);",
    "missing", "consumer:npc_retry_listener");
  rejected("constant short circuit cannot restore the retry listener", "consumer",
    "_retryButton.addEventListener('click',refreshSnapshot);",
    "_retryButton.onclick=null;false&&_retryButton.addEventListener('click',refreshSnapshot);",
    "missing", "consumer:npc_retry_listener");
  rejected("same-depth insertion cannot preserve the retry active-position proof", "consumer",
    retryBlock, "if(false);" + retryBlock,
    "misplaced", "consumer:npc_retry_listener");
  const adapterRefreshTail = "if(typeofcallback==='function')callback(result);});returntrue;};";
  rejectedSyntaxValid("assignment operator tail cannot neutralize the adapter refresh binding", "adapter",
    adapterRefreshTail,
    "if(typeofcallback==='function')callback(result);});returntrue;}&&false;",
    "forbidden",
    "adapter:binding_definition_incomplete_PhysicalInventoryAdapter_prototype_refresh");
  rejectedSyntaxValid("a later direct assignment cannot replace the settlement entry binding", "consumer",
    "functioncloseSettlement(){",
    "openSettlement = function() { return; }; function closeSettlement() {",
    "forbidden", "consumer:binding_rewrite_openSettlement");
  rejectedSyntaxValid("a later compound assignment cannot replace the settlement entry binding", "consumer",
    "functioncloseSettlement(){",
    "openSettlement ||= function() { return; }; function closeSettlement() {",
    "forbidden", "consumer:binding_rewrite_openSettlement");
  rejectedSyntaxValid("a later direct assignment cannot replace the provider prototype binding", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "InventoryCoordinator.prototype._refreshPhysicalSurfaceWhileOwned=function(){returnfalse;};"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "forbidden",
    "provider:binding_rewrite_InventoryCoordinator_prototype__refreshPhysicalSurfaceWhileOwned");
  rejectedSyntaxValid("a bracket assignment cannot replace an audited provider prototype binding", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "InventoryCoordinator.prototype['_refreshPhysicalSurfaceWhileOwned']=function(){returnfalse;};"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "forbidden",
    "provider:binding_rewrite_InventoryCoordinator_prototype__refreshPhysicalSurfaceWhileOwned");
  rejectedSyntaxValid("defineProperty cannot replace an audited provider prototype binding", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "Object.defineProperty(InventoryCoordinator.prototype,'_refreshPhysicalSurfaceWhileOwned',"
      + "{value:function(){returnfalse;}});"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "forbidden",
    "provider:binding_rewrite_InventoryCoordinator_prototype__refreshPhysicalSurfaceWhileOwned");
  rejectedSyntaxValid("an alias cannot replace an audited provider prototype binding", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "var providerPrototype = InventoryCoordinator.prototype;"
      + "providerPrototype._refreshPhysicalSurfaceWhileOwned = function() { return false; };"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "forbidden",
    "provider:binding_rewrite_InventoryCoordinator_prototype__refreshPhysicalSurfaceWhileOwned");
  rejectedSyntaxValid("computed prototype access cannot replace an audited provider binding", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "InventoryCoordinator['prototype']._refreshPhysicalSurfaceWhileOwned = function() { return false; };"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "forbidden",
    "provider:binding_rewrite_InventoryCoordinator_prototype__refreshPhysicalSurfaceWhileOwned");
  rejectedSyntaxValid("destructured prototype access cannot replace an audited provider binding", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "var {prototype: providerPrototype} = InventoryCoordinator;"
      + "providerPrototype._refreshPhysicalSurfaceWhileOwned = function() { return false; };"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "forbidden",
    "provider:binding_rewrite_InventoryCoordinator_prototype__refreshPhysicalSurfaceWhileOwned");
  rejectedSyntaxValid("the audited provider prototype carrier cannot be replaced", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "InventoryCoordinator.prototype={};"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "forbidden",
    "provider:binding_rewrite_InventoryCoordinator_prototype__refreshPhysicalSurfaceWhileOwned");
  rejectedSyntaxValid("direct eval is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "eval('openSettlement=function(){return;}'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_eval");
  rejectedSyntaxValid("indirect eval is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "(0,eval)('openSettlement=function(){return;}'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_eval");
  rejectedSyntaxValid("member eval is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "window.eval('openSettlement=function(){return;}'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_eval");
  rejectedSyntaxValid("Function constructor is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "var generated = Function('return false;'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_function_constructor");
  rejectedSyntaxValid("new Function is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "var generated = new Function('return false;'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_function_constructor");
  rejectedSyntaxValid("computed eval is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "globalThis['eval']('openSettlement=function(){return;}'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_eval");
  rejectedSyntaxValid("constant-folded computed eval is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "globalThis['ev' + 'al']('openSettlement=function(){return;}'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_eval");
  rejectedSyntaxValid("computed Function is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "var generated = globalThis['Function']('return false;'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_function_constructor");
  rejectedSyntaxValid("constant-folded computed Function is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "var generated = globalThis['Fun' + 'ction']('return false;'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_function_constructor");
  rejectedSyntaxValid("constructor-chain dynamic code is forbidden in an audited source", "consumer",
    "functioncloseSettlement(){",
    "var generated = (function() {}).constructor('return false;'); function closeSettlement() {",
    "forbidden", "consumer:dynamic_function_constructor");
  rejectedByClosedSource("even inert comment and string edits require an explicit source-pin review", "consumer",
    "functioncloseSettlement(){",
    "var dynamicDecoy = \"globalThis['eval']; globalThis['Function']; value['constructor']\";"
      + "/* eval('x'); new Function('x'); value.constructor('x'); */"
      + "function closeSettlement() {");
  rejectedByClosedSource("nested object destructuring cannot rebind a closed declaration", "consumer",
    "functioncloseSettlement(){",
    "var nestedSource={entry:{openSettlement:function(){return;}}};"
      + "({entry:{openSettlement:openSettlement}}=nestedSource);function closeSettlement(){");
  rejectedByClosedSource("nested array destructuring cannot rebind a closed declaration", "consumer",
    "functioncloseSettlement(){",
    "var nestedSource=[[function(){return;}]];"
      + "([[openSettlement]]=nestedSource);function closeSettlement(){");
  rejectedByClosedSource("destructuring for-of cannot rebind a closed declaration", "consumer",
    "functioncloseSettlement(){",
    "for({openSettlement:openSettlement}of[{openSettlement:function(){return;}}]){}"
      + "function closeSettlement(){");
  rejectedByClosedSource("Unicode escaped eval cannot enter a closed source", "consumer",
    "functioncloseSettlement(){",
    "\\u0065val('openSettlement=function(){return;}');function closeSettlement(){");
  rejectedByClosedSource("Unicode escaped Function cannot enter a closed source", "consumer",
    "functioncloseSettlement(){",
    "var generated=Funct\\u0069on('return false;');function closeSettlement(){");
  rejectedByClosedSource("parenthesized constant computed eval cannot enter a closed source", "consumer",
    "functioncloseSettlement(){",
    "globalThis[(('ev'+'al'))]('openSettlement=function(){return;}');"
      + "function closeSettlement(){");
  rejectedByClosedSource("concat-computed Function cannot enter a closed source", "consumer",
    "functioncloseSettlement(){",
    "var generated=globalThis['Fun'.concat('ction')]('return false;');"
      + "function closeSettlement(){");
  rejectedByClosedSource("template interpolation cannot execute inside a closed source", "consumer",
    "functioncloseSettlement(){",
    "var generated=`${eval('openSettlement=function(){return;}')}`;"
      + "function closeSettlement(){");
  rejectedByClosedSource("constructor alias dynamic code cannot enter a closed source", "consumer",
    "functioncloseSettlement(){",
    "var Generated=(function(){}).constructor;Generated('return false;')();"
      + "function closeSettlement(){");
  rejectedByClosedSource("parenthesized constructor carrier cannot replace the audited prototype", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "(InventoryCoordinator).prototype._refreshPhysicalSurfaceWhileOwned=function(){return false;};"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){");
  rejectedByClosedSource("constructor alias cannot replace the audited prototype", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "var InventoryAlias=InventoryCoordinator;"
      + "InventoryAlias.prototype._refreshPhysicalSurfaceWhileOwned=function(){return false;};"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){");
  rejectedByClosedSource("parenthesized reflective mutation cannot replace the audited prototype", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "Object.defineProperty((InventoryCoordinator).prototype,"
      + "'_refreshPhysicalSurfaceWhileOwned',{value:function(){return false;}});"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){");
  rejectedByClosedSource("the audited provider constructor carrier cannot be replaced", "provider",
    "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){",
    "InventoryCoordinator=function(){};"
      + "InventoryCoordinator.prototype._applySnapshots=function(snapshots,expectedRequests){");
  rejectedByClosedSource("a canonical assignment can still not be followed by an equivalent replacement", "adapter",
    "PhysicalInventoryAdapter.prototype.resetSession=function(){",
    "(PhysicalInventoryAdapter).prototype.refresh=function(){return false;};"
      + "PhysicalInventoryAdapter.prototype.resetSession=function(){");
  rejected("nested callable with the canonical marker cannot restore settlement fencing", "consumer",
    "functionopenSettlement(){"
      + "if(!selectionCount()||_busy||_owner.needsReconcile||inventoryWriteUnavailable())return;",
    "functionremovedOpenSettlement(){functionopenSettlement(){"
      + "if(!selectionCount()||_busy||_owner.needsReconcile||inventoryWriteUnavailable())return;}}",
    "missing", "consumer:npc_open_settlement_write_fence");
});
test("NPC browser journeys execute under an independently verified child module journal", () => {
  const root = path.resolve(__dirname, "../../..");
  const harnessPath = path.join(root, "launcher/web/modules/npcshop/dev/harness.html");
  const harnessSource = fs.readFileSync(harnessPath, "utf8");
  ["filtered visible projection failure exposes an actionable retry and blocks the next trade write",
    "visible retry redoes 3 physical + exact filtered projection and restores the preserved filter/page/receipt",
    "generic write dispatch rechecks Inventory immediately before sending after an intervening synchronous failure",
    "filtered authority projection rejects containerVersion drift from its paired physical receipt",
    "preview dispatch independently refuses an Inventory-invalid settlement mutation",
    "commit dispatch independently refuses an Inventory-invalid settlement",
    "settlement entry independently refuses an Inventory-invalid selection"]
    .forEach((label) => assert.strictEqual(harnessSource.split(label).length - 1, 1, label));
  const bootstrapPath = path.join(__dirname, "browser-bootstrap.js");
  const bootstrapSource = fs.readFileSync(bootstrapPath, "utf8");
  assert(bootstrapSource.includes("RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest, artifact:journal })"));
  assert(bootstrapSource.includes("verifyServedResourceClosure({"));
  assert(bootstrapSource.includes("browserExecutableReceipt({"));
  assert(bootstrapSource.includes('"external_browser_binary"'));
  const moduleInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
    "browser-module-inventory.v1.json"), "utf8"));
  assert.strictEqual(moduleInventory.schema,
    "workbench-live-e2e.npc.browser-module-inventory.v1");
  assert.strictEqual(moduleInventory.nodeVersion, process.version);
  assert.strictEqual(moduleInventory.files.length, 280);
  assert.strictEqual(moduleInventory.builtins.length, 23);
  const resourceInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
    "browser-resource-inventory.v1.json"), "utf8"));
  assert.strictEqual(resourceInventory.schema,
    "workbench-live-e2e.browser-resource-inventory.v1");
  assert.strictEqual(resourceInventory.files.length, 37);
  assert(resourceInventory.files.includes("modules/npcshop/dev/harness.html"));
  assert(resourceInventory.files.includes("modules/npcshop.js"));
  assert(resourceInventory.files.includes("modules/npcshop-runtime.js"));
  assert.deepStrictEqual(resourceInventory.files, resourceInventory.files.slice().sort());
  const result = childProcess.spawnSync(process.execPath,
    [bootstrapPath], {
      cwd: root, encoding: "utf8", windowsHide: true, timeout: 120000,
    });
  assert.strictEqual(result.error, undefined, result.error && result.error.message);
  assert.strictEqual(result.status, 0, String(result.stderr || result.stdout));
  assert.strictEqual(result.stderr, "");
  const lines = result.stdout.split(/\r?\n/).filter(Boolean);
  assert.strictEqual(lines.length, 1, result.stdout);
  const receipt = JSON.parse(lines[0]);
  const receiptDigest = receipt.evidenceSha256;
  delete receipt.evidenceSha256;
  assert.strictEqual(sha256Text(canonicalJson(receipt)), receiptDigest);
  assert.strictEqual(receipt.schema, "workbench-live-e2e.npc.browser-gate-receipt.v1");
  assert.strictEqual(receipt.status, "OFFLINE_VERIFIED");
  assert.strictEqual(receipt.moduleAdmission, "ADMITTED");
  assert.strictEqual(receipt.journalVerification, "VERIFIED");
  assert.strictEqual(receipt.moduleEntryCount, 324);
  assert.deepStrictEqual({passed:receipt.result.passed, total:receipt.result.total,
    reducedPassed:receipt.result.reducedPassed, reducedTotal:receipt.result.reducedTotal,
    contractQuantity:receipt.result.contractQuantity},
  {passed:128, total:128, reducedPassed:2, reducedTotal:2, contractQuantity:4549});
  assert.strictEqual(receipt.result.checkNamesSha256,
    moduleInventory.expectedCheckNamesSha256);
  assert(/^[a-f0-9]{64}$/.test(receipt.result.resultSha256));
  assert.strictEqual(receipt.result.criticalChecks.length, 7);
  assert(receipt.result.criticalChecks.every((entry) => entry.ok === true));
  assert.deepStrictEqual(receipt.result.criticalChecks.map((entry) => entry.name), [
    "filtered visible projection failure exposes an actionable retry and blocks the next trade write",
    "visible retry redoes 3 physical + exact filtered projection and restores the preserved filter/page/receipt",
    "generic write dispatch rechecks Inventory immediately before sending after an intervening synchronous failure",
    "filtered authority projection rejects containerVersion drift from its paired physical receipt",
    "preview dispatch independently refuses an Inventory-invalid settlement mutation",
    "commit dispatch independently refuses an Inventory-invalid settlement",
    "settlement entry independently refuses an Inventory-invalid selection",
  ]);
  assert.strictEqual(receipt.servedResourceClosure.schema,
    "workbench-live-e2e.browser-resource-closure-receipt.v1");
  assert.strictEqual(receipt.servedResourceClosure.resourceCount, 37);
  assert(receipt.servedResourceClosure.occurrenceCount >= 37);
  assert.strictEqual(receipt.servedResourceClosure.failureCount, 1);
  ["inventorySha256", "resourcesSha256", "occurrencesSha256", "failuresSha256",
    "evidenceSha256"].forEach((field) =>
    assert(/^[a-f0-9]{64}$/.test(receipt.servedResourceClosure[field]), field));
  assert(/^[a-f0-9]{64}$/.test(receipt.manifestSha256));
  assert(/^[a-f0-9]{64}$/.test(receipt.moduleJournalSha256));
  assert(receipt.browserBinary && receipt.browserBinary.locator.startsWith("external:")
    && /^[a-f0-9]{64}$/.test(receipt.browserBinary.sha256)
    && Number.isInteger(receipt.browserBinary.bytes) && receipt.browserBinary.bytes > 0);
  browserGateReceipt = {
    schema:receipt.schema, evidenceSha256:receiptDigest,
    manifestSha256:receipt.manifestSha256,
    moduleJournalSha256:receipt.moduleJournalSha256,
    moduleEntryCount:receipt.moduleEntryCount,
    browserBinary:receipt.browserBinary,
    resourceClosureEvidenceSha256:receipt.servedResourceClosure.evidenceSha256,
    resourceCount:receipt.servedResourceClosure.resourceCount,
    occurrenceCount:receipt.servedResourceClosure.occurrenceCount,
    checkNamesSha256:receipt.result.checkNamesSha256,
    resultSha256:receipt.result.resultSha256,
  };
});
test("NPC session reset is atomic, closed-only, and refresh preserves current requests", () => {
  const NpcShopRuntime = require(path.resolve(__dirname,
    "../../../launcher/web/modules/npcshop-runtime.js"));
  function FakeCoordinator(options) {
    this.requests = JSON.parse(JSON.stringify(options.requests));
    this.opened = false; this.configureCalls = []; this.openCalls = 0; this.closeCalls = 0;
  }
  FakeCoordinator.prototype.debugState = function() { return { opened:this.opened }; };
  FakeCoordinator.prototype.getRequest = function(containerId) {
    return this.requests.find((request) => request.containerId === containerId) || null;
  };
  FakeCoordinator.prototype.configureRequests = function(requests) {
    this.configureCalls.push(JSON.parse(JSON.stringify(requests)));
    this.requests = JSON.parse(JSON.stringify(requests)); return true;
  };
  FakeCoordinator.prototype.open = function(callback) {
    this.openCalls++; this.opened = true;
    callback({ success:false, error:"fixture_refresh" }); return true;
  };
  FakeCoordinator.prototype.close = function() { this.closeCalls++; this.opened = false; };
  const adapter = NpcShopRuntime.createPhysicalInventoryAdapter({
    inventoryRuntime: { InventoryCoordinator:FakeCoordinator,
      readPhysicalInventorySurface:function() {} },
    request:function() { return "fixture.call"; },
    owner:{ panelInstanceId:"npc.fixture" },
  });
  adapter.coordinator.requests = [
    { containerId:"背包", offset:17, limit:7, filterKey:"category",
      filterSpec:{ branch:"category", major:"weapon" }, scope:"filtered" },
    { containerId:"战备箱", offset:80, limit:20, filterKey:"category",
      filterSpec:{ branch:"category", major:"weapon", use:"刀" }, scope:"filtered" },
  ];
  adapter._surfaceReceipt = { stale:true };
  assert.strictEqual(adapter.resetSession(), true);
  assert.strictEqual(adapter.coordinator.configureCalls.length, 1);
  assert.deepStrictEqual(adapter.coordinator.requests, [
    { containerId:"背包", offset:17, limit:50, filterKey:"all" },
    { containerId:"战备箱", offset:80, limit:40, filterKey:"all" },
  ]);
  adapter.coordinator.requests.forEach((request) => {
    assert.strictEqual(Object.prototype.hasOwnProperty.call(request, "filterSpec"), false);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(request, "scope"), false);
  });
  assert.strictEqual(adapter.getReceipt(), null);
  adapter.coordinator.opened = true;
  assert.strictEqual(adapter.resetSession(), false);
  assert.strictEqual(adapter.coordinator.configureCalls.length, 1);
  adapter.coordinator.opened = false;
  let refreshResult = null;
  assert.strictEqual(adapter.refresh((result) => { refreshResult = result; }), true);
  assert.strictEqual(adapter.coordinator.openCalls, 1);
  assert.strictEqual(adapter.coordinator.configureCalls.length, 1);
  assert.strictEqual(adapter.coordinator.closeCalls, 0);
  assert.strictEqual(refreshResult.error, "fixture_refresh");
});
test("NPC bootstrap explicitly admits production adapter behavior dependencies", () => {
  const bootstrap = path.join(__dirname, "bootstrap.js");
  const source = fs.readFileSync(bootstrap, "utf8");
  ["launcher/web/modules/panel-runtime.js", "launcher/web/modules/inventory-runtime.js",
    "launcher/web/modules/npcshop-runtime.js"].forEach((relativePath) => {
    const needle = "repo(\"" + relativePath + "\"), \"production_schema_validator\"";
    assert.strictEqual(source.split(needle).length - 1, 1, relativePath);
  });
  assert(source.includes('if (mode !== "help") entryRows.push('));
  const help = childProcess.spawnSync(process.execPath, [bootstrap, "--help"], {
    encoding: "utf8", windowsHide: true, timeout: 30000,
  });
  assert.strictEqual(help.error, undefined, help.error && help.error.message);
  assert.strictEqual(help.status, 0, help.stderr);
  const payload = JSON.parse(help.stdout);
  assert.strictEqual(payload.moduleAdmission, "ADMITTED");
  assert.strictEqual(payload.moduleEntryCount, 4);
});
test("production closure covers exact close Host and AS2 artifact", () => withFixture({}, (fixture) => {
  const bundle = load(fixture);
  const locators = new Set(bundle.productionClosure.files.map((entry) => entry.locator));
  ["root:launcher/src/Guardian/AuthorityLogFormatter.cs",
    "root:launcher/src/Guardian/PanelHostController.cs",
    "root:launcher/src/Tasks/PanelBridge.cs",
    "root:launcher/src/Tasks/PanelPendingCallTracker.cs",
    "root:launcher/src/Guardian/PanelRequestOwnerLifecycle.cs",
    "root:launcher/src/Bus/XmlSocketServer.cs",
    "root:scripts/asLoader.swf",
    "root:launcher/web/modules/npcshop.js",
    "root:launcher/web/modules/npcshop-runtime.js",
    "root:launcher/web/css/panels.css",
    "root:launcher/web/css/workbench/core.css"].forEach((locator) => assert(locators.has(locator), locator));
  assert.strictEqual(bundle.productionClosure.declarations.bootWeb.length, 23);
  assert.strictEqual(bundle.productionClosure.declarations.npcLazyWeb.length, 13);
  assert.strictEqual(bundle.productionClosure.declarations.styleWeb.length, 29);
  const physicalSurface = bundle.productionClosure.semanticContracts.inventoryPhysicalSurface;
  assert.strictEqual(physicalSurface.schema,
    "workbench-live-e2e.npc.production-inventory-surface.v10");
  assert.strictEqual(physicalSurface.consumer.locator, "root:launcher/web/modules/npcshop.js");
  assert.strictEqual(physicalSurface.adapter.locator,
    "root:launcher/web/modules/npcshop-runtime.js");
  assert.strictEqual(physicalSurface.provider.locator,
    "root:launcher/web/modules/inventory-runtime.js");
  assert.deepStrictEqual(physicalSurface.owner, {
    expectedPanel: "npcshop",
    expectedPanelInstanceId: "current_exact_owner",
    supplements: "same_exact_owner",
  });
  assert.deepStrictEqual(physicalSurface.requestCallId, {
    requestReturn: "bounded_expected_call_id",
    synchronousCallback: "single_callback_queued_until_request_return",
    responseEcho: "exact_expected_call_id",
    invalidReturn: "fail_closed_once",
  });
  assert.deepStrictEqual(physicalSurface.sessionReset, {
    order: "before_owner_open",
    availability: "closed_only",
    mutation: "single_atomic_configure",
    offsets: "preserved",
    limits: { backpack:50, battlebox:40 },
    projection: "filterKey_all_without_filterSpec_or_scope",
    refresh: "open_current_requests_without_reconfiguration",
  });
  assert.strictEqual(physicalSurface.projection.constrainedRequests,
    "physical_then_exact_authority_visible");
  assert.strictEqual(physicalSurface.projection.ownerRelease,
    "after_exact_visible_response");
  assert.strictEqual(physicalSurface.projection.receipt,
    "one_to_three_batch_physical_surface");
  assert(physicalSurface.projection.pairedCoherence.includes("exactPhysicalSlot"));
  assert(physicalSurface.projection.failureFence.includes("synchronousDuplicate"));
  assert.strictEqual(physicalSurface.sourceContract.schema,
    "workbench-live-e2e.npc.production-inventory-source-anchors.v8");
  assert.strictEqual(physicalSurface.sourceContract.tokenCanonicalization,
    "exact-source-byte-pin-plus-js-binding-depth-active-prefix-rewrite-fence.v5");
  assert.strictEqual(physicalSurface.sourceContract.bindingGuards.length, 20);
  assert.deepStrictEqual(physicalSurface.sourceContract.closedSourceBytes, {
    policy:"exact_utf8_bytes_governance_pin",
    expected:{
      consumer:"aac86d778cd3773dc7b3fbe63d37d5464397e9b88ecb053d2c5f9e7537bdeec0",
      adapter:"2abc6d198607eb45185111ebf5269e946fb81dc5d0286a9ac0d465efdf9e9267",
      provider:"b2c6b06baadb3677d7434334cc06e2795d30a407c9499e5caec93df34c4a95dc",
    },
    actual:{
      consumer:"aac86d778cd3773dc7b3fbe63d37d5464397e9b88ecb053d2c5f9e7537bdeec0",
      adapter:"2abc6d198607eb45185111ebf5269e946fb81dc5d0286a9ac0d465efdf9e9267",
      provider:"b2c6b06baadb3677d7434334cc06e2795d30a407c9499e5caec93df34c4a95dc",
    },
  });
  assert.deepStrictEqual(physicalSurface.sourceContract.dynamicCode,
    {eval:"forbidden_file_wide", Function:"forbidden_file_wide"});
  assert.strictEqual(physicalSurface.sourceContract.structuralAnchors.length, 8);
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "consumer:npc_adapter_delegation"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "adapter:adapter_exact_owner"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "provider:request_returns_expected_call_id"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "provider:response_call_id_equals_expected"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "consumer:npc_on_open_session_reset"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "consumer:npc_retry_listener"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "consumer:npc_open_settlement_write_fence"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "consumer:npc_preview_write_fence"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "consumer:npc_commit_write_fence"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "consumer:npc_write_dispatch_fence"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "adapter:adapter_reset_atomic_configure"));
  assert(physicalSurface.sourceContract.requiredAnchors.includes(
    "provider:projection_exact_desired_request"));
  assert(physicalSurface.sourceContract.forbiddenAnchors.includes(
    "provider:legacy_owner_return_reject"));
  assert(physicalSurface.sourceContract.forbiddenAnchors.includes(
    "adapter:refresh_calls_reset_window"));
  assert.deepStrictEqual(physicalSurface.firstBatch.map((request) =>
    [request.containerId, request.offset, request.limit]),
  [["背包", 0, 50], ["战备箱", 0, 100]]);
  assert.deepStrictEqual(physicalSurface.battleAccessibleCapacities,
    [0, 40, 80, 120, 160, 200, 240]);
  assert.strictEqual(physicalSurface.authorityVisibleFollowup.responseCount, 1);
  assert.strictEqual(bundle.candidateProducer.artifactSourceHash,
    bundle.productionClosure.artifactSource.artifactSourceHash);
  assert.strictEqual(bundle.productionClosure.treeSha256,
    bundle.postRestartProductionClosure.treeSha256);
}));

negative("missing business control fails", (fixture) => {
  const bundle = load(fixture); bundle.controls = bundle.controls.filter((value) => value.step !== "commit_sale"); save(fixture, bundle);
}, "artifact_role_set_invalid");
negative("wrong owner fails", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "bridge_send" && event.message
    && event.message.callId === fixture.bundle.calls.saleCommit).message.panelInstanceId = "foreign.owner";
}), ["phase_request_count_invalid", "response_count_invalid", "response_bijection_invalid"]);
negative("commit before preview response fails", (fixture) => reseal(fixture, (events) => {
  const previewIndex = events.findIndex((event) => event.kind === "webview_message"
    && event.message && event.message.callId === fixture.bundle.calls.purchasePreview);
  const [preview] = events.splice(previewIndex, 1);
  const commitIndex = events.findIndex((event) => event.kind === "bridge_send"
    && event.message && event.message.callId === fixture.bundle.calls.purchaseCommit);
  events.splice(commitIndex + 1, 0, preview);
}), "transcript_timeline_invalid");
negative("wrong send-order marker fails", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "bridge_send" && event.message
    && event.message.callId === fixture.bundle.calls.purchaseCommit).sendOrder = "before_onIssued";
}), "web_send_order_invalid");
negative("missing authority receipt fails", (fixture) => {
  rewriteHost(fixture, "first", (records, bundle) => {
    const record = records.find((entry) => entry.line.startsWith("event=authority_flash_call_bound ")
      && entry.line.includes("webCallId=" + bundle.calls.purchaseCommit));
    record.line = "fixture authority receipt removed";
  });
}, "host_authority_receipt_count_invalid");
negative("missing same-fid response fails", (fixture) => {
  rewriteHost(fixture, "first", (records, bundle) => {
    const receipt = records.find((record) => record.line.startsWith("event=authority_flash_call_bound ")
      && record.line.includes("webCallId=" + bundle.calls.saleCommit));
    const fid = receipt.line.match(/flashCallId=(\d+)/)[1];
    records.find((record) => record.line.startsWith("[XmlSocket:JSON] task=npcshop_response ")
      && record.line.includes("callId=" + fid + " ")).line = "fixture response removed";
  });
}, "host_flash_response_count_invalid");
negative("raw JSON Host authority log fails closed", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    const record = records.find((value) => value.line.startsWith("[NpcShopTask] -> Flash:"));
    record.line = '[NpcShopTask] -> Flash: {"task":"cmd"}';
  });
}, "host_structured_token_invalid");
negative("legacy buy command fails", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    records.push({ lineNumber: records.length + 1,
      line: "[NpcShopTask] -> Flash: task=cmd cmd=npcShopBuy callId=999 payload=redacted len=20" });
  });
}, "legacy_npc_write_observed");
negative("candidate drift fails", (fixture) => {
  const bundle = load(fixture); bundle.runtime.restart.stableIdentity.coreSha256 = "9".repeat(64); save(fixture, bundle);
}, "runtime_stable_identity_mismatch");
negative("restart PID reuse fails", (fixture) => {
  const bundle = load(fixture); bundle.runtime.restart.pid = bundle.runtime.first.pid;
  bundle.runtime.restart.controlBindingPid = bundle.runtime.first.pid;
  bundle.runtime.restart.cdpBindingPid = bundle.runtime.first.pid; save(fixture, bundle);
}, "runtime_freshness_invalid");
negative("seed drift fails", (fixture) => {
  const bundle = load(fixture); rewrite(fixture, bundle.clone.seedAfterArtifact,
    (seed) => { seed.solSetSha256 = "7".repeat(64); });
}, "seed_invariant_failed");
negative("protected sale fails", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.salePreviews.at(-1)).message.saleLines[0].protectedCount = 1;
}), "sale_preview_projection_mismatch");
negative("lease mismatch fails", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "bridge_send" && event.message
    && event.message.callId === fixture.bundle.calls.salePreviews[0]).message.payload.sales[0].source.expectedLease = "foreign";
}), "sale_preview_source_mismatch");
negative("token mismatch fails", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "bridge_send" && event.message
    && event.message.callId === fixture.bundle.calls.saleCommit).message.payload.expectedTradeToken = "sha256:" + "8".repeat(64);
}), "trade_token_link_invalid");
negative("preview token reuse across writes fails", (fixture) => reseal(fixture, (events) => {
  const purchase = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.purchasePreview).message.tradeToken;
  events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.salePreviews.at(-1)).message.tradeToken = purchase;
  events.find((event) => event.kind === "bridge_send" && event.message
    && event.message.callId === fixture.bundle.calls.saleCommit).message.payload.expectedTradeToken = purchase;
}), "trade_token_reused");
negative("purchase price is recomputed from base price and multiplier", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.purchasePreview).message;
  response.purchaseLines[0].unitPrice += 1;
  response.purchaseLines[0].total += 1;
  response.buyTotal += 1;
  response.netDelta -= 1;
  response.projectedBalance -= 1;
}), "purchase_preview_projection_mismatch");
negative("purchase dynamic capacity maximum is exact", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.purchasePreview).message;
  response.purchaseLines[0].maxByCapacity = 2;
}), "purchase_preview_projection_mismatch");
negative("purchase preview line is a closed schema", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.purchasePreview).message;
  response.purchaseLines[0].derivedByFixture = true;
}), "purchase_preview_projection_mismatch");
negative("purchase poststate cannot mutate a non-target inventory slot", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.purchasePostInventory).message;
  response.snapshots.find((window) => window.containerId === "背包")
    .slots.find((slot) => slot.physicalSlot === 9).item.icon = "foreign-icon";
}), "purchase_inventory_delta_invalid");
negative("purchase poststate target identity is exact", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.purchasePostInventory).message;
  const slot = response.snapshots.find((window) => window.containerId === "背包")
    .slots.find((value) => value.physicalSlot === PURCHASE_SLOT);
  slot.item.name = "foreign-target";
  slot.item.displayName = "foreign-target";
  slot.item.icon = "foreign-target-icon";
  slot.confirmProjection.name = "foreign-target";
  slot.confirmProjection.displayName = "foreign-target";
}), "purchase_inventory_target_invalid");
negative("equipment purchase must use ItemUtil.acquire's unique first vacancy", (fixture) =>
  reseal(fixture, (events) => {
    const response = events.find((event) => event.kind === "webview_message" && event.message
      && event.message.callId === fixture.bundle.calls.purchasePostInventory).message;
    const slots = response.snapshots.find((window) => window.containerId === "背包").slots;
    const legal = slots.find((slot) => slot.physicalSlot === PURCHASE_SLOT);
    const wrong = slots.find((slot) => slot.physicalSlot === 20);
    wrong.occupied = true;
    wrong.slotLease = "bag.purchase-post.20";
    wrong.item = deepClone(legal.item);
    wrong.confirmProjection = deepClone(legal.confirmProjection);
    legal.occupied = false;
    legal.slotLease = "empty.purchase-post.2." + PURCHASE_SLOT;
    delete legal.item;
    delete legal.confirmProjection;
  }), "purchase_inventory_destination_invalid");
negative("purchase delivery category must match the authoritative catalog", (fixture) =>
  reseal(fixture, (events) => {
    const response = events.find((event) => event.kind === "webview_message" && event.message
      && event.message.callId === fixture.bundle.calls.purchasePostInventory).message;
    const slot = response.snapshots.find((window) => window.containerId === "背包")
      .slots.find((value) => value.physicalSlot === PURCHASE_SLOT);
    slot.item.majorType = "防具";
  }), "purchase_inventory_target_invalid");
negative("inventory first batch is exact ordered bag50 and battle100", (fixture) => reseal(fixture, (events) => {
  const request = events.find((event) => event.kind === "bridge_send" && event.message
    && event.message.callId === fixture.bundle.calls.purchasePostInventory).message;
  request.payload.requests[0].limit = 49;
}), "inventory_surface_order_invalid");
negative("stack sale unit-price formula is stable across previews", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.salePreviews[0]).message;
  response.saleLines[0].total += 1;
  response.sellTotal += 1;
  response.netDelta += 1;
  response.projectedBalance += 1;
}), "sale_price_formula_invalid", { salePreQuantity: 25 });
negative("sale poststate cannot mutate a non-target inventory slot", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.salePostInventory).message;
  const slot = response.snapshots.find((window) => window.containerId === "背包")
    .slots.find((value) => value.physicalSlot === 9);
  slot.item.displayName = "foreign-name";
  slot.confirmProjection.displayName = "foreign-name";
}), "sale_inventory_delta_invalid");
negative("fresh restart rejects full item and confirm rarity drift", (fixture) =>
  reseal(fixture, (events) => {
    const response = events.find((event) => event.kind === "webview_message" && event.message
      && event.message.callId === fixture.bundle.calls.restartInventorySnapshot).message;
    const slot = response.snapshots.find((window) => window.containerId === "背包")
      .slots.find((value) => value.physicalSlot === PURCHASE_SLOT);
    slot.item.rarity = "FORGED_RESTART_RARITY";
    slot.confirmProjection.rarity = "FORGED_RESTART_RARITY";
  }), "restart_semantic_readback_mismatch");
negative("fresh restart rejects any catalog field drift", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.restartNpcSnapshot).message;
  response.catalog[0].requiredInfo = "forged-but-schema-valid";
}), "restart_semantic_readback_mismatch");
negative("fresh restart requires every one of the full-surface slot leases to rotate", (fixture) =>
  reseal(fixture, (events) => {
    const finalResponse = events.find((event) => event.kind === "webview_message" && event.message
      && event.message.callId === fixture.bundle.calls.salePostInventory).message;
    const restartResponse = events.find((event) => event.kind === "webview_message" && event.message
      && event.message.callId === fixture.bundle.calls.restartInventorySnapshot).message;
    const finalSlot = finalResponse.snapshots.find((window) => window.containerId === "背包")
      .slots.find((slot) => slot.physicalSlot === 9);
    const restartSlot = restartResponse.snapshots.find((window) => window.containerId === "背包")
      .slots.find((slot) => slot.physicalSlot === 9);
    restartSlot.slotLease = finalSlot.slotLease;
  }), "restart_source_fingerprint_invalid");
negative("archive order fails", (fixture) => {
  const bundle = load(fixture); [bundle.archive.sv1HostLine, bundle.archive.sv2HostLine]
    = [bundle.archive.sv2HostLine, bundle.archive.sv1HostLine]; save(fixture, bundle);
}, "archive_order_invalid");
negative("runtime residue fails", (fixture) => {
  const bundle = load(fixture); bundle.residue.coreProcessCount = 1; save(fixture, bundle);
}, "runtime_residue_present");
negative("first lifecycle residue binds all three ports", (fixture) => {
  rewriteSealedRuntime(fixture, "residue", (residue) => {
    residue.first.ports.pop();
    sealDigest(residue.first);
  });
}, ["runtime_residue_present", "runtime_residue_identity_mismatch"]);
negative("supported restart shutdown must succeed before residue", (fixture) => {
  rewriteSealedRuntime(fixture, "shutdown", (shutdown) => {
    shutdown.responseSucceeded = false;
  });
}, "supported_shutdown_timeline_invalid");
negative("supported shutdown binds its exact response artifact", (fixture) => {
  const bundle = load(fixture);
  rewrite(fixture, bundle.shutdownResponseArtifact, (response) => { response.state = "foreign"; });
}, "supported_shutdown_timeline_invalid");
negative("archive disk manifest requires the full JSON and SOL set", (fixture) => {
  const bundle = load(fixture);
  rewrite(fixture, bundle.clone.afterArchiveArtifact, (manifest) => {
    manifest.artifacts = manifest.artifacts.filter((artifact) => artifact.kind !== "sol");
    sealDigest(manifest);
  });
}, "disk_artifact_manifest_invalid");
negative("SAFEEXIT Host boundary must match the Host-owned snapshot", (fixture) => {
  const bundle = load(fixture);
  bundle.timelineBoundaries.safeExitProviderBoundary.terminalTotal -= 1;
  save(fixture, bundle);
}, "safe_exit_host_boundary_invalid");
negative("trusted timeline binds the exact archive Host line", (fixture) => {
  const bundle = load(fixture);
  bundle.trustedTimeline.archiveHostLine += 1;
  save(fixture, bundle);
}, "trusted_timeline_binding_invalid");
negative("trusted timeline binds every Inventory supplement callId", (fixture) => {
  const bundle = load(fixture);
  bundle.trustedTimeline.inventoryEvents[1].callId = "npc.fixture.forged-supplement";
  sealDigest(bundle.trustedTimeline);
  save(fixture, bundle);
}, "trusted_timeline_binding_invalid");
test("seventh-round trusted timeline uses the canonical close-detach-exit order", () =>
  withFixture({}, (fixture) => {
    const bundle = load(fixture);
    assert.deepStrictEqual(bundle.trustedTimeline.orderedEvents,
      CANONICAL_TIMELINE_ORDER.slice());
    const order = bundle.trustedTimeline.orderedEvents;
    assert(order.indexOf("first_close_settled") < order.indexOf("first_observer_detached"));
    assert(order.indexOf("first_observer_detached") < order.indexOf("first_loaded_production"));
    assert(order.indexOf("first_loaded_production") < order.indexOf("safe_exit_issued"));
    assert(order.indexOf("safe_exit_ack") < order.indexOf("exit_confirm_issued"));
  }));
negative("legacy timeline that places first detach after EXIT_CONFIRM is rejected", (fixture) => {
  const bundle = load(fixture);
  const legacy = CANONICAL_TIMELINE_ORDER.filter((label) =>
    !["first_observer_detached", "first_loaded_production"].includes(label));
  legacy.splice(legacy.indexOf("exit_confirm_provider") + 1, 0,
    "first_observer_detached", "first_loaded_production");
  bundle.trustedTimeline.orderedEvents = legacy;
  sealDigest(bundle.trustedTimeline);
  save(fixture, bundle);
}, "trusted_timeline_binding_invalid");
negative("offline fixture cannot claim a live native SAFEEXIT journey", (fixture) => {
  const bundle = load(fixture);
  bundle.safeExitUiJourneyVerified = true;
  bundle.exitMethod = "native_safe_exit";
  save(fixture, bundle);
}, "offline_live_claim_forbidden");
negative("offline fixture exit method is exact", (fixture) => {
  const bundle = load(fixture); bundle.exitMethod = "supported_shutdown"; save(fixture, bundle);
}, "offline_live_claim_forbidden");
negative("first open request order must be Inventory then NPC", (fixture) => reseal(fixture, (events) => {
  const observedAt = events.map((event) => event.observedAt);
  const calls = fixture.bundle.calls;
  const inv = events.findIndex((event) => event.kind === "bridge_send"
    && event.message && event.message.callId === calls.initialInventorySnapshot);
  const npc = events.findIndex((event) => event.kind === "bridge_send"
    && event.message && event.message.callId === calls.initialNpcSnapshot);
  const pair = events.splice(npc, 2);
  events.splice(inv, 0, ...pair);
  events.forEach((event, index) => { event.observedAt = observedAt[index]; });
}), "initial_request_order_invalid");
negative("restart request order must be Inventory then NPC", (fixture) => reseal(fixture, (events) => {
  const observedAt = events.map((event) => event.observedAt);
  const calls = fixture.bundle.calls;
  const inv = events.findIndex((event) => event.kind === "bridge_send"
    && event.message && event.message.callId === calls.restartInventorySnapshot);
  const npc = events.findIndex((event) => event.kind === "bridge_send"
    && event.message && event.message.callId === calls.restartNpcSnapshot);
  const pair = events.splice(npc, 2);
  events.splice(inv, 0, ...pair);
  events.forEach((event, index) => { event.observedAt = observedAt[index]; });
}), "restart_request_order_invalid");
negative("catalog must match production exact schema", (fixture) => reseal(fixture, (events) => {
  const response = events.find((event) => event.kind === "webview_message" && event.message
    && event.message.callId === fixture.bundle.calls.initialNpcSnapshot);
  delete response.message.catalog[0].use;
}), "catalog_entry_invalid");
negative("fake PNG magic header is rejected", (fixture) => {
  const bundle = load(fixture);
  const binding = bundle.controls.find((entry) => entry.step === "select_purchase");
  const ackPath = path.join(fixture.runDir, binding.ackArtifact);
  const ack = JSON.parse(fs.readFileSync(ackPath, "utf8"));
  const capturePath = path.join(fixture.runDir, ack.capture.artifact);
  fs.writeFileSync(capturePath, Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"),
    Buffer.alloc(48, 0x41)]));
  const captureEntry = entry(bundle, ack.capture.artifact);
  captureEntry.bytes = fs.statSync(capturePath).size;
  captureEntry.sha256 = sha256File(capturePath);
  ack.capture.sha256 = captureEntry.sha256;
  fs.writeFileSync(ackPath, JSON.stringify(ack, null, 2) + "\n", "utf8");
  const ackEntry = entry(bundle, binding.ackArtifact);
  ackEntry.bytes = fs.statSync(ackPath).size;
  ackEntry.sha256 = sha256File(ackPath);
  save(fixture, bundle);
}, "control_capture_media_invalid");
negative("provider observation cannot be omitted", (fixture) => {
  const bundle = load(fixture);
  const binding = bundle.controls.find((value) => value.step === "safe_exit");
  rewrite(fixture, binding.ackArtifact, (ack) => { delete ack.providerReceipt; });
}, ["provider_receipt_missing", "control_ack_invalid"]);
negative("extra relevant Host read before terminal seal fails", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    records.push({ lineNumber: records.length + 1,
      line: "[Panel] HandlePanelMessage: task=panel panel=npcshop domain=npcshop cmd=snapshot callId=foreign.read payload=redacted len=96" });
  });
}, "host_command_multiset_invalid");
negative("extra Host authority field fails exact projection", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    const record = records.find((value) => value.line.startsWith("event=authority_flash_call_bound "));
    record.line += " unexpected=field";
  });
}, "host_authority_receipt_invalid");
negative("duplicate Host authority field fails exact projection", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    const record = records.find((value) => value.line.startsWith("event=authority_flash_call_bound "));
    record.line += " domain=npcshop";
  });
}, "host_structured_duplicate_field");
negative("first exact close completion is mandatory", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    const receipt = records.find((record) => record.line.startsWith("event=panel_exact_close_completed "));
    receipt.line = "fixture close completion removed";
  });
}, "host_command_multiset_invalid");
negative("restart exact close completion is mandatory", (fixture) => {
  rewriteHost(fixture, "restart", (records) => {
    const receipt = records.find((record) => record.line.startsWith("event=panel_exact_close_completed "));
    receipt.line = "fixture close completion removed";
  });
}, "host_command_multiset_invalid");
negative("final Host commit response must precede sv1", (fixture) => {
  const bundle = load(fixture); bundle.archive.sv1HostLine = 1; save(fixture, bundle);
}, ["archive_order_invalid", "host_close_before_archive_invalid"]);
negative("loaded production script multiset cannot shrink", (fixture) => {
  const bundle = load(fixture);
  const loaded = bundle.runtime.restart.loadedProduction;
  loaded.scripts.pop();
  const unsigned = Object.assign({}, loaded); delete unsigned.evidenceSha256;
  loaded.evidenceSha256 = sha256Text(canonicalJson(unsigned));
  save(fixture, bundle);
}, "loaded_production_multiset_invalid");
negative("post-restart production tree cannot drift", (fixture) => {
  const bundle = load(fixture);
  bundle.postRestartProductionClosure.files[0].sha256 = "0".repeat(64);
  bundle.postRestartProductionClosure.treeSha256 = sha256Text(canonicalJson(
    bundle.postRestartProductionClosure.files));
  const unsigned = Object.assign({}, bundle.postRestartProductionClosure);
  delete unsigned.closureSha256;
  bundle.postRestartProductionClosure.closureSha256 = sha256Text(canonicalJson(unsigned));
  save(fixture, bundle);
}, ["production_closure_current_tree_mismatch", "production_closure_restart_drift"]);

negative("legacy offlineFixture mode field is rejected", (fixture) => {
  const bundle = load(fixture); bundle.offlineFixture = true; save(fixture, bundle);
}, "legacy_evidence_mode_field_forbidden");
negative("unknown evidence mode is rejected", (fixture) => {
  const bundle = load(fixture); bundle.evidenceMode = "fixture"; save(fixture, bundle);
}, "evidence_mode_invalid");
negative("offline fixture cannot carry a live module journal", (fixture) => {
  const bundle = load(fixture); bundle.moduleJournal = {}; save(fixture, bundle);
}, "offline_fixture_identity_invalid");
negative("offline bundle cannot be relabeled live without a sealed live origin", (fixture) => {
  const bundle = load(fixture); bundle.evidenceMode = "live_capture"; save(fixture, bundle);
}, "live_run_directory_invalid");
negative("offline origin cannot claim full-scope eligibility", (fixture) => {
  rewriteOrigin(fixture, (origin) => { origin.fullScopeEligible = true; });
}, "offline_evidence_origin_invalid");
negative("offline origin cannot claim live capture phases", (fixture) => {
  rewriteOrigin(fixture, (origin) => {
    origin.requiredPhases = ["domain_loaded", "clone_prepared", "first_captured",
      "restart_captured", "terminal"];
  });
}, "offline_evidence_origin_invalid");
negative("evidence root is the exact canonical checkout", (fixture) => {
  rewriteOrigin(fixture, (origin, bundle) => {
    origin.root = path.resolve(bundle.root, "foreign-root");
    bundle.root = origin.root;
  });
}, "evidence_origin_invalid");

negative("candidate producer metadata bytes are rebound", (fixture) => {
  const bundle = load(fixture);
  const file = path.join(bundle.candidateRoot, "runtime-build-metadata.v2.json");
  const value = JSON.parse(fs.readFileSync(file, "utf8"));
  value.builderLabel = "detached-producer";
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", "utf8");
  refreshArtifactEntry(fixture, bundle, file);
  save(fixture, bundle);
}, "candidate_producer_evidence_mismatch");
negative("candidate payload bytes are rebound", (fixture) => {
  const bundle = load(fixture);
  fs.appendFileSync(bundle.candidate.stableIdentity.processPath, "drift", "utf8");
  refreshArtifactEntry(fixture, bundle, bundle.candidate.stableIdentity.processPath);
  save(fixture, bundle);
}, "candidate_payload_file_mismatch");
negative("candidate manifest rejects extra metadata", (fixture) => {
  const bundle = load(fixture);
  const file = path.join(bundle.candidateRoot, "runtime", "cf7-runtime-manifest.tsv");
  const text = fs.readFileSync(file, "utf8").replace("publishMode\t", "extra\tvalue\npublishMode\t");
  fs.writeFileSync(file, text, "utf8");
  refreshArtifactEntry(fixture, bundle, file);
  save(fixture, bundle);
}, "candidate_producer_manifest_invalid");
negative("candidate producer recipe is bound to current canonical inputs", (fixture) => {
  const bundle = load(fixture);
  bundle.candidateProducer.producerRecipeHash = "0".repeat(64);
  sealDigest(bundle.candidateProducer);
  save(fixture, bundle);
}, "candidate_producer_evidence_mismatch");
negative("candidate toolchain input count is frozen", (fixture) => {
  const bundle = load(fixture);
  bundle.candidateProducer.runtimeInputCounts.toolchainLock = 4;
  sealDigest(bundle.candidateProducer);
  save(fixture, bundle);
}, "candidate_producer_evidence_mismatch");
negative("production binding requires candidate producer digest", (fixture) => {
  const bundle = load(fixture); delete bundle.productionBinding.candidateProducerSha256;
  const unsigned = Object.assign({}, bundle.productionBinding); delete unsigned.bindingSha256;
  bundle.productionBinding.bindingSha256 = sha256Text(canonicalJson(unsigned)); save(fixture, bundle);
}, "production_binding_invalid");
negative("production binding includes exact toolchain and build identity", (fixture) => {
  const bundle = load(fixture);
  bundle.productionBinding.toolchainLockHash = "0".repeat(64);
  bundle.productionBinding.buildIdentityHash = "1".repeat(64);
  const unsigned = Object.assign({}, bundle.productionBinding);
  delete unsigned.bindingSha256;
  bundle.productionBinding.bindingSha256 = sha256Text(canonicalJson(unsigned));
  save(fixture, bundle);
}, "production_binding_invalid");

negative("loaded production stylesheet multiset cannot shrink", (fixture) => {
  rewriteLoaded(fixture, "restart", (loaded) => { loaded.stylesheets.pop(); });
}, "loaded_production_multiset_invalid");
negative("loaded production rejects an extra stylesheet", (fixture) => {
  rewriteLoaded(fixture, "first", (loaded) => { loaded.stylesheets.push({ occurrence: 999,
    url: "https://overlay.local/css/workbench/npc-extra.css",
    sourceMethod: "Page.getResourceContent", sha256: "a".repeat(64), bytes: 1 }); });
}, "loaded_production_multiset_invalid");
negative("loaded production stylesheet digest is exact", (fixture) => {
  rewriteLoaded(fixture, "first", (loaded) => { loaded.stylesheets[0].sha256 = "a".repeat(64); });
}, "loaded_production_resource_mismatch");
negative("loaded production rejects an extra registry script", (fixture) => {
  rewriteLoaded(fixture, "restart", (loaded) => { loaded.scripts.push({ occurrence: 999,
    scriptId: "fixture-script-extra", url: "https://overlay.local/modules/npcshop-extra.js",
    sourceMethod: "Debugger.getScriptSource", sha256: "b".repeat(64), bytes: 1 }); });
}, "loaded_production_multiset_invalid");
negative("loaded production rejects duplicate script occurrences", (fixture) => {
  rewriteLoaded(fixture, "first", (loaded) => { const copy = deepClone(loaded.scripts[0]);
    copy.occurrence = 999; copy.scriptId = "fixture-script-duplicate"; loaded.scripts.push(copy); });
}, "loaded_production_multiset_invalid");
negative("loaded production preserves raw script occurrence order", (fixture) => {
  rewriteLoaded(fixture, "first", (loaded) => {
    [loaded.scripts[0], loaded.scripts[1]] = [loaded.scripts[1], loaded.scripts[0]];
  });
}, "loaded_production_script_occurrence_invalid");
negative("loaded production script origin is exact", (fixture) => {
  rewriteLoaded(fixture, "restart", (loaded) => {
    loaded.scripts[0].origin = "https://foreign.invalid";
  });
}, "loaded_production_resource_mismatch");
negative("loaded production stylesheet declaration order is exact", (fixture) => {
  rewriteLoaded(fixture, "first", (loaded) => { loaded.stylesheets[0].order = 2; });
}, "loaded_production_resource_mismatch");

negative("provider receipt binds request digest", (fixture) => {
  rewriteProvider(fixture, "select_purchase", (provider) => {
    provider.requestSha256 = "f".repeat(64);
  });
}, "provider_receipt_invalid");
negative("provider receipt binds its owned artifact", (fixture) => {
  rewriteProvider(fixture, "select_purchase", (provider) => {
    provider.ownedArtifact = "controls/provider-receipts/other.json";
  });
}, "provider_receipt_invalid");
negative("provider receipt binds exact tool-result source", (fixture) => {
  rewriteProvider(fixture, "select_purchase", (provider) => {
    provider.toolResultSource = "helper_generated";
  });
}, "provider_receipt_invalid");
negative("provider operation ids cannot be reused", (fixture) => {
  const bundle = load(fixture);
  const first = bundle.controls.find((value) => value.step === "select_purchase");
  const firstAck = JSON.parse(fs.readFileSync(path.join(fixture.runDir, first.ackArtifact), "utf8"));
  const firstProvider = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
    firstAck.providerReceipt.artifact), "utf8"));
  rewriteProvider(fixture, "open_purchase_settlement", (provider) => {
    provider.providerOperationId = firstProvider.providerOperationId;
  }, { preserveOperationId: true });
}, "provider_receipt_invalid");
negative("provider receipt rejects extra fields", (fixture) => {
  rewriteProvider(fixture, "select_purchase", (provider) => { provider.helperClaim = true; });
}, "provider_receipt_invalid");
negative("ACK cannot carry provider-owned semantic details", (fixture) => {
  const bundle = load(fixture);
  const binding = bundle.controls.find((value) => value.step === "select_purchase");
  rewrite(fixture, binding.ackArtifact, (ack) => { ack.details = { resultSource: "helper" }; });
}, "control_ack_invalid");
negative("capability reason lives in the provider receipt", (fixture) => {
  rewriteProvider(fixture, "capability_probe", (provider) => { provider.details = {}; });
}, "capability_unavailable_reason_missing");
negative("fallback authorization binds provider-owned capability reason", (fixture) => {
  rewriteProvider(fixture, "authorize_codex_fallback", (provider) => {
    provider.details.capabilityReasonCode = "different_reason";
  });
}, "fallback_authorization_invalid");
negative("valid one-pixel captures are still insufficient", (fixture) => {
  const bundle = load(fixture);
  const binding = bundle.controls.find((value) => value.step === "select_purchase");
  const ackPath = path.join(fixture.runDir, binding.ackArtifact);
  const ack = JSON.parse(fs.readFileSync(ackPath, "utf8"));
  const capturePath = path.join(fixture.runDir, ack.capture.artifact);
  fs.writeFileSync(capturePath, fixturePng(55, 1, 1));
  const captureEntry = entry(bundle, ack.capture.artifact);
  captureEntry.bytes = fs.statSync(capturePath).size;
  captureEntry.sha256 = sha256File(capturePath);
  save(fixture, bundle);
  rewriteProvider(fixture, "select_purchase", (provider, targetAck) => {
    provider.captureSha256 = captureEntry.sha256;
    provider.captureWidth = 1; provider.captureHeight = 1;
    targetAck.capture.sha256 = captureEntry.sha256;
  });
}, "control_capture_media_invalid");
test("ack helper executes and emits a pure provider reference", () => {
  const source = fs.readFileSync(path.join(__dirname, "control-channel.js"), "utf8");
  const writeAckSource = source.slice(source.indexOf("function writeAck("));
  assert(writeAckSource.includes("providerReceiptArtifact"));
  assert.strictEqual(writeAckSource.includes("copyFileSync"), false);
  assert.strictEqual(writeAckSource.includes("renameSync"), false);
  assert.strictEqual(writeAckSource.includes("captureArtifact"), false);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-npc-ack-root-"));
  const runDir = path.join(root, "tmp", "workbench-live-e2e", "npc", "ack-helper");
  fs.mkdirSync(runDir, { recursive: true });
  try {
    const channel = new ControlChannel(root, runDir, "npc.ack.helper");
    const request = channel.issue("open_first", {
      actionClass: "business",
      allowedTransports: ["codex_computer_use"],
      ttlMs: 120000,
      transcriptPrefix: { eventCount: 0, chainHead: "0".repeat(64) },
      instruction: "offline acknowledgement helper contract test",
      expected: null,
    });
    const captureRelative = captureRelativePath(request.requestId);
    const capturePath = path.join(runDir, captureRelative);
    fs.mkdirSync(path.dirname(capturePath), { recursive: true });
    fs.writeFileSync(capturePath, fixturePng(88));
    const providerRelative = providerReceiptRelativePath(request.requestId);
    const providerPath = path.join(runDir, providerRelative);
    const provider = {
      schema: PROVIDER_RECEIPT_SCHEMA,
      runId: request.runId,
      requestId: request.requestId,
      requestSha256: request.requestSha256,
      requestBytes: fs.statSync(request.requestPath).size,
      step: request.step,
      transport: "codex_computer_use",
      issuer: "codex_computer_use",
      toolResultSource: "codex_computer_use_tool_result",
      providerOperationId: "pending",
      action: request.step,
      result: "completed",
      startedAt: new Date(Date.parse(request.issuedAt) + 1).toISOString(),
      inputAt: new Date(Date.parse(request.issuedAt) + 2).toISOString(),
      captureAt: new Date(Date.parse(request.issuedAt) + 3).toISOString(),
      completedAt: new Date(Date.parse(request.issuedAt) + 4).toISOString(),
      inputEvidence: {
        kind: "native_input",
        observedAt: new Date(Date.parse(request.issuedAt) + 2).toISOString(),
        eventRef: null, eventType: "click", isTrusted: true,
        selector: "native-control[data-step=\"open_first\"]", tagName: "BUTTON",
        origin: "launcher://native", visible: true, enabled: true,
        viewport: { width: 1280, height: 720 },
        rect: { x: 96, y: 72, width: 240, height: 56 },
        clientPoint: { x: 216, y: 100 }, hitTargetMatches: true,
        key: null, button: 0, repeat: false,
      },
      ownedArtifact: providerRelative,
      captureArtifact: captureRelative,
      captureSha256: sha256File(capturePath),
      captureBytes: fs.statSync(capturePath).size,
      captureWidth: 320,
      captureHeight: 180,
      details: {},
    };
    provider.providerOperationId = expectedProviderOperationId(provider);
    provider.receiptSha256 = sha256Text(canonicalJson(provider));
    atomicWriteJson(providerPath, provider);
    while (Date.now() <= Date.parse(provider.completedAt)) {}
    const output = AckControl.main(["--run-dir", runDir, "--request-id", request.requestId,
      "--transport", "codex_computer_use", "--result", "completed",
      "--provider-receipt", providerRelative], { root, quiet: true });
    const ack = JSON.parse(fs.readFileSync(output.ackPath, "utf8"));
    assert.strictEqual(ack.schema, CONTROL_ACK_SCHEMA);
    assert.deepStrictEqual(Object.keys(ack).sort(), ["schema", "runId", "requestId",
      "requestSha256", "step", "transport", "result", "completedAt", "capture",
      "providerReceipt"].sort());
    assert.strictEqual(Object.prototype.hasOwnProperty.call(ack, "details"), false);
    assert.throws(() => AckControl.parse(["--reason-code", "invented"]), /invalid argument/);
    assert.throws(() => AckControl.parse(["--result", "completed", "--result", "failed"]),
      /duplicate argument/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

negative("DOM evidence must be trusted", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input").isTrusted = false;
}), "dom_input_evidence_invalid");
negative("DOM evidence target must be visibly hit-testable", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input").target.visible = false;
}), "dom_input_evidence_invalid");
negative("DOM checkout selector cannot be invented", (fixture) => reseal(fixture, (events) => {
  const event = events.find((value) => value.kind === "dom_input"
    && value.target.selector === "button.npcshop-checkout-btn");
  event.target.selector = "[data-npcshop-action=checkout]";
}), "provider_input_target_mismatch");
negative("DOM commit tag must match production", (fixture) => reseal(fixture, (events) => {
  const event = events.find((value) => value.kind === "dom_input"
    && value.target.selector === "button[data-trade-commit]");
  event.target.tagName = "DIV";
}), "provider_input_target_mismatch");
negative("DOM coordinates must be finite", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input").target.clientPoint.x = null;
}), "dom_input_evidence_invalid");
negative("DOM click must use the primary button", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input" && event.eventType === "click").button = 1;
}), "dom_input_evidence_invalid");
negative("DOM target must be enabled", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input").target.enabled = false;
}), "dom_input_evidence_invalid");
negative("DOM point must come from the real input event", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input" && event.eventType === "click")
    .target.clientPointSource = "rect_center";
}), "dom_input_evidence_invalid");
negative("DOM click point must be inside the exact target rectangle", (fixture) => reseal(fixture, (events) => {
  const event = events.find((value) => value.kind === "dom_input" && value.eventType === "click");
  event.target.clientPoint.x = event.target.rect.x - 1;
}), "dom_input_evidence_invalid");
negative("DOM elementFromPoint must resolve the target", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input" && event.eventType === "click")
    .target.hitTest.matchesTarget = false;
}), "dom_input_evidence_invalid");
negative("DOM target origin must be the Overlay origin", (fixture) => reseal(fixture, (events) => {
  events.find((event) => event.kind === "dom_input").target.origin = "https://foreign.invalid";
}), "dom_input_evidence_invalid");
negative("keyboard evidence accepts only frozen keys", (fixture) => reseal(fixture, (events) => {
  const event = events.find((value) => value.kind === "dom_input" && value.eventType === "input"
    && value.target.selector === "input.workbench-quantity-number");
  event.eventType = "keydown";
  event.key = "Escape";
  event.repeat = false;
}), "dom_input_evidence_invalid", { salePreQuantity: 25 });

negative("Host panel authority tail is mandatory", (fixture) => {
  rewriteHost(fixture, "first", (records, bundle) => {
    const record = records.find((entry) => entry.line.includes("callId=" + bundle.calls.purchaseCommit)
      && entry.line.startsWith("[Panel] HandlePanelMessage:"));
    record.line = record.line.replace(/ authorityFieldCount=.*$/, "");
  });
}, "host_panel_record_invalid");
negative("Host authority field count must match", (fixture) => {
  rewriteHost(fixture, "first", (records, bundle) => {
    const record = records.find((entry) => entry.line.includes("callId=" + bundle.calls.purchaseCommit)
      && entry.line.startsWith("[Panel] HandlePanelMessage:"));
    record.line = record.line.replace(/authorityFieldCount=\d+/, "authorityFieldCount=9");
  });
}, "host_panel_record_invalid");
negative("Host socket authority reference must match", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    const record = records.find((entry) => entry.line.startsWith("[XmlSocket:JSON] task=npcshop_response ")
      && entry.line.includes(" tradeTokenRef="));
    record.line = record.line.replace(/tradeTokenRef=sha256_[a-f0-9]{24}/,
      "tradeTokenRef=sha256_000000000000000000000000");
  });
}, "host_flash_response_record_invalid");
negative("Host formatter field order is exact", (fixture) => {
  rewriteHost(fixture, "first", (records, bundle) => {
    const record = records.find((entry) => entry.line.includes("callId=" + bundle.calls.purchaseCommit)
      && entry.line.startsWith("[Panel] HandlePanelMessage:"));
    record.line = record.line.replace("task=panel panel=npcshop",
      "panel=npcshop task=panel");
  });
}, "host_panel_record_invalid");
negative("PanelHost close completion requires a closed record", (fixture) => {
  rewriteHost(fixture, "first", (records) => {
    records.find((record) => record.line === "[PanelHost] closed: npcshop").line = "fixture closed removed";
  });
}, "host_command_multiset_invalid");
negative("PanelHost close ordering is exact", (fixture) => {
  rewriteHost(fixture, "restart", (records) => {
    const closed = records.find((record) => record.line === "[PanelHost] closed: npcshop");
    const completed = records.find((record) => record.line.startsWith("event=panel_exact_close_completed "));
    [closed.line, completed.line] = [completed.line, closed.line];
  });
}, "host_close_receipt_order_invalid");
negative("all Host authority responses precede the close request", (fixture) => {
  rewriteHost(fixture, "first", (records, bundle) => {
    const receipt = records.find((record) => record.line.startsWith("event=authority_flash_call_bound ")
      && record.line.includes("webCallId=" + bundle.calls.saleCommit));
    const fid = receipt.line.match(/flashCallId=(\d+)/)[1];
    const responseIndex = records.findIndex((record) =>
      record.line.startsWith("[XmlSocket:JSON] task=npcshop_response ")
      && record.line.includes("callId=" + fid + " "));
    const response = records.splice(responseIndex, 1)[0];
    const completionIndex = records.findIndex((record) =>
      record.line.startsWith("event=panel_exact_close_completed "));
    records.splice(completionIndex + 1, 0, response);
  });
}, "host_timeline_regression");
negative("first close settlement precedes the SAFEEXIT request", (fixture) => {
  const bundle = load(fixture);
  const binding = bundle.controls.find((value) => value.step === "safe_exit");
  const request = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
    binding.requestArtifact), "utf8"));
  rewrite(fixture, bundle.hostLogArtifact, (log) => {
    log.lifecycles.first.closeSettledSnapshot.capturedAt =
      new Date(Date.parse(request.issuedAt) + 1).toISOString();
  });
}, "native_exit_order_invalid");
negative("Host rejection records cannot coexist with success", (fixture) => {
  rewriteHost(fixture, "first", (records) => { records.push({ lineNumber: 0,
    line: "event=foreign_panel_close_rejected panel=npcshop rejected=true" }); });
}, "host_relevant_record_unknown");
negative("restart completion must be the last relevant Host record", (fixture) => {
  rewriteHost(fixture, "restart", (records) => { records.push({ lineNumber: 0,
    line: "[Workbench] npcshop late relevant record" }); });
}, "host_relevant_record_unknown");
negative("first close completion must precede save markers", (fixture) => {
  rewriteHost(fixture, "first", (records, bundle) => {
    const index = records.findIndex((record) => record.line.startsWith("event=panel_exact_close_completed "));
    const completed = records.splice(index, 1)[0]; records.push(completed);
    bundle.archive.sv1HostLine = records.findIndex((record) => record.line === "sv:1") + 1;
    bundle.archive.sv2HostLine = records.findIndex((record) => record.line === "sv:2") + 1;
    bundle.archive.hostLine = records.findIndex((record) => record.line.startsWith("[ArchiveTask] Shadow saved:")) + 1;
  });
}, "host_timeline_regression");

test("fourth-round file, candidate, and raw CDP inventories fail closed", () => {
  expectFixtureRejected({}, (fixture) => {
    fs.writeFileSync(path.join(fixture.runDir, "unexpected-artifact.bin"), "unexpected", "utf8");
  }, "artifact_set_mismatch");
  expectFixtureRejected({}, (fixture) => {
    const bundle = load(fixture);
    [bundle.artifactManifest.artifacts[0], bundle.artifactManifest.artifacts[1]]
      = [bundle.artifactManifest.artifacts[1], bundle.artifactManifest.artifacts[0]];
    save(fixture, bundle);
  }, "artifact_entry_invalid");
  expectFixtureRejected({}, (fixture) => {
    const bundle = load(fixture);
    bundle.artifactManifest.artifacts[0].role = "foreign_role";
    save(fixture, bundle);
  }, "artifact_role_set_invalid");
  withFixture({}, (fixture) => {
    const bundle = load(fixture);
    fs.writeFileSync(path.join(bundle.candidateRoot, "runtime", "foreign.dll"), "foreign", "utf8");
    assert.throws(() => ProductionClosure.verifyCandidateProducerBinding(bundle.candidateRoot,
      bundle.candidate.stableIdentity, bundle.productionClosure, bundle.candidateProducer),
    (error) => error instanceof NpcJourneyError && error.code === "candidate_payload_file_mismatch");
  });
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded) => {
      const duplicate = deepClone(loaded.executionContexts[0]);
      duplicate.occurrence = 2;
      loaded.executionContexts.push(duplicate);
    });
  }, "loaded_production_context_set_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded) => {
      const anonymous = deepClone(loaded.scriptOccurrences.at(-1));
      anonymous.occurrence = loaded.scriptOccurrences.length + 1;
      anonymous.scriptId += "-anonymous";
      anonymous.url = "";
      anonymous.origin = "opaque";
      loaded.scriptOccurrences.push(anonymous);
    });
  }, "loaded_production_script_occurrence_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "restart", (loaded) => {
      const foreign = deepClone(loaded.resourceOccurrences.at(-1));
      foreign.occurrence = loaded.resourceOccurrences.length + 1;
      foreign.url = "https://foreign.invalid/extra.css";
      foreign.origin = "https://foreign.invalid";
      loaded.resourceOccurrences.push(foreign);
      loaded.styleOccurrences.push(deepClone(foreign));
    });
  }, "loaded_production_resource_set_invalid");
});

test("fourth-round Host clock, PID, and lifecycle boundaries fail closed", () => {
  function clockSnapshot(capturedAt, lines) {
    return { capturedAt, records: lines.map((line, index) => ({ lineNumber: index + 1,
      line: line + " fixture" })) };
  }
  const rollover = Protocol.resolveHostTimeline(clockSnapshot("2026-08-04T00:00:02.000Z",
    ["23:59:59.900", "00:00:00.050", "00:00:01.000"]), 0, "rollover_fixture");
  assert.strictEqual(rollover.length, 3);
  assert(Date.parse(rollover[0].observedAt) < Date.parse(rollover[1].observedAt));
  assert.throws(() => Protocol.resolveHostTimeline(clockSnapshot("2026-08-04T12:00:02.000Z",
    ["12:00:01.000", "11:59:59.000"]), 0, "rollback_fixture"),
  (error) => error instanceof NpcJourneyError && error.code === "host_timeline_regression");
  assert.throws(() => Protocol.resolveHostTimeline(clockSnapshot("2026-08-06T00:00:02.000Z",
    ["23:59:59.000", "00:00:00.000", "23:59:59.500", "00:00:01.000"]),
  0, "second_rollover_fixture"),
  (error) => error instanceof NpcJourneyError && error.code === "host_timeline_regression");
  expectFixtureRejected({}, (fixture) => {
    const bundle = load(fixture);
    rewrite(fixture, bundle.hostLogArtifact, (log) => {
      const lifecycle = log.lifecycles.first;
      function snapshotPid(snapshot) {
        snapshot.sessionPid = 9999;
        const payload = { schema: snapshot.schema,
          requestedTailLimit: snapshot.requestedTailLimit,
          sessionEvidenceSha256: snapshot.sessionEvidenceSha256,
          lifecycleId: snapshot.lifecycleId, sessionPid: snapshot.sessionPid,
          sessionProcessStartUtcTicks: snapshot.sessionProcessStartUtcTicks,
          total: snapshot.total, oldestLineNumber: snapshot.oldestLineNumber,
          records: snapshot.records };
        snapshot.tailSha256 = sha256Text(canonicalJson(payload));
        return snapshot;
      }
      lifecycle.startBoundary = LauncherObservation.createTerminalLogBoundary(
        snapshotPid(lifecycle.startBoundary.snapshot));
      snapshotPid(lifecycle.closeSettledSnapshot);
      snapshotPid(lifecycle.terminalSnapshot);
      lifecycle.timelineBoundaries.safe_exit_provider_completed
        = LauncherObservation.createTerminalLogBoundary(snapshotPid(
          lifecycle.timelineBoundaries.safe_exit_provider_completed.snapshot));
    });
  }, "host_runtime_pid_mismatch");
  expectFixtureRejected({}, (fixture) => {
    const bundle = load(fixture);
    bundle.postRestartProductionClosure.capturedAt = "2026-08-03T00:00:10.000Z";
    const unsigned = deepClone(bundle.postRestartProductionClosure);
    delete unsigned.closureSha256;
    bundle.postRestartProductionClosure.closureSha256 = sha256Text(canonicalJson(unsigned));
    save(fixture, bundle);
  }, ["production_closure_restart_drift", "strict_lifecycle_timeline_invalid"]);
});

test("fourth-round provider, DOM, PNG, argv, and pre-seal contracts fail closed", () => {
  expectFixtureRejected({}, (fixture) => reseal(fixture, (events) => {
    const event = events.find((value) => value.kind === "dom_input" && value.eventType === "click");
    event.clientX += 1;
  }), "dom_input_evidence_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteProvider(fixture, "select_purchase", (provider) => {
      provider.inputEvidence.eventRef.sequence += 1;
      provider.providerOperationId = expectedProviderOperationId(provider);
    });
  }, "provider_dom_binding_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteProvider(fixture, "select_purchase", (provider) => {
      provider.requestBytes += 1;
      provider.providerOperationId = expectedProviderOperationId(provider);
    });
  }, "provider_receipt_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteProvider(fixture, "select_purchase", (provider) => {
      provider.captureBytes += 1;
      provider.providerOperationId = expectedProviderOperationId(provider);
    });
  }, "provider_capture_binding_invalid");
  assert.throws(() => decodePng(fixturePng(3, 64, 64)),
    (error) => error instanceof NpcJourneyError && error.code === "control_capture_media_invalid");
  const valid = fixturePng(4);
  assert.throws(() => decodePng(replacePngIdat(valid,
    (compressed) => Buffer.concat([compressed, Buffer.from([0])]))),
  (error) => error instanceof NpcJourneyError && error.code === "control_capture_media_invalid");
  assert.throws(() => decodePng(replacePngIdat(valid,
    (compressed) => compressed.subarray(0, compressed.length - 1))),
  (error) => error instanceof NpcJourneyError && error.code === "control_capture_media_invalid");
  assert.throws(() => decodePng(replacePngIdat(valid, (compressed) => {
    const raw = zlib.inflateSync(compressed); raw[0] = 5; return zlib.deflateSync(raw);
  })), (error) => error instanceof NpcJourneyError
    && error.code === "control_capture_media_invalid");
  const bootstrap = path.join(__dirname, "bootstrap.js");
  [[[], "one exact bootstrap mode"], [["--check", "--help"], "cannot be mixed"]]
    .forEach(([args, message]) => {
      const result = childProcess.spawnSync(process.execPath, [bootstrap].concat(args), {
        encoding: "utf8", windowsHide: true,
      });
      assert.strictEqual(result.status, 2);
      assert.strictEqual(result.stdout, "");
      assert(result.stderr.includes(message));
    });
  const verifierSource = fs.readFileSync(path.join(__dirname, "verify-evidence.js"), "utf8");
  const finalizer = verifierSource.slice(verifierSource.indexOf("function finalizePreSealVerification("),
    verifierSource.indexOf("function verifyEvidenceFile("));
  assert.strictEqual(finalizer.includes("verifyBundle("), false);
  const runnerSource = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
  assert(runnerSource.indexOf("verifyBundlePreSeal(bundle, runDir)")
    < runnerSource.indexOf("finalizePreSealVerification(bundle, runDir, preSealVerification)"));
  assert(runnerSource.indexOf("finalizePreSealVerification(bundle, runDir, preSealVerification)")
    < runnerSource.indexOf("const receiptPath = path.join(runDir, \"receipt.json\")"));
});

test("fifth-round indexed PNG palette bounds cover every admitted bit depth", () => {
  [1, 2, 4, 8].forEach((bitDepth) => {
    const decoded = decodePng(indexedFixturePng(bitDepth, 0));
    assert.strictEqual(decoded.width, 320);
    assert.strictEqual(decoded.height, 180);
    assert.throws(() => decodePng(indexedFixturePng(bitDepth, 1)),
      (error) => error instanceof NpcJourneyError
        && error.code === "control_capture_media_invalid");
  });
});

test("fifth-round bootstrap classifies raw argv before loading live modules", () => {
  const bootstrap = path.join(__dirname, "bootstrap.js");
  const candidate = path.resolve(__dirname, "fixture-candidate");
  const rejected = [
    ["--purchase-only"],
    ["--candidate-root", candidate],
    ["--check", "--candidate-root", candidate],
    ["--candidate-root", candidate, "--seed-slot", "cf7_agent_seed", "--slot",
      "cf7_agent_target", "--allow-isolated-commit", "--allow-codex-cu-fallback", "--bogus"],
    ["--candidate-root", candidate, "--candidate-root", candidate, "--seed-slot",
      "cf7_agent_seed", "--slot", "cf7_agent_target", "--allow-isolated-commit",
      "--allow-codex-cu-fallback"],
    ["--candidate-root", candidate, "--seed-slot", "foreign-live-save", "--slot",
      "cf7_agent_target", "--allow-read-only-live-seed", "--allow-isolated-commit",
      "--allow-codex-cu-fallback"],
    ["--verify-bundle", "relative-evidence-bundle.json"],
  ];
  rejected.forEach((args) => {
    const result = childProcess.spawnSync(process.execPath, [bootstrap].concat(args), {
      encoding: "utf8", windowsHide: true,
    });
    assert.strictEqual(result.status, 2, args.join(" "));
    assert.strictEqual(result.stdout, "", args.join(" "));
    assert.strictEqual(result.stderr.includes("Cannot find module"), false, args.join(" "));
  });
  const source = fs.readFileSync(bootstrap, "utf8");
  const classification = source.indexOf("mode = classifyArgs(argv)");
  const liveRequire = source.indexOf("require(\"./run-live-journey\")");
  assert(classification > 0 && liveRequire > classification);
  const prefix = source.slice(0, classification);
  assert.deepStrictEqual(Array.from(prefix.matchAll(/require\(([^)]+)\)/g),
    (match) => match[1]), ["\"../lib/runtime-module-journal\""]);
});

test("fifth-round raw resources and final detach source are an exact closure", () => {
  withFixture({}, (fixture) => {
    const bundle = load(fixture);
    const loaded = bundle.runtime.first.loadedProduction;
    const policy = ProductionClosure.loadedResourcePolicy(bundle.root,
      bundle.productionClosure, loaded.resourceIconNames);
    const idle = policy.required.filter((entry) => entry.reason === "idle_prewarm_base");
    const fonts = policy.conditional.filter((entry) =>
      entry.reason === "conditional_font_manifest");
    const skins = policy.conditional.filter((entry) =>
      entry.reason === "conditional_visible_workbench_skin");
    const icons = policy.required.filter((entry) =>
      entry.reason.startsWith("authority_projected_icon:"));
    assert.strictEqual(idle.length, 15);
    assert.strictEqual(fonts.length, 13);
    assert.strictEqual(skins.length, 2);
    assert(icons.length > 0);
    assert(loaded.resourceOccurrences.some((entry) =>
      entry.url === "https://cfn-fonts.local/lxgw-wenkai-screen.ttf"));
    idle.concat(icons).forEach((expected) => assert(loaded.resourceOccurrences.some((entry) =>
      entry.resourceType === expected.resourceType && entry.url === expected.url
      && entry.sourceSha256 === expected.sha256 && entry.sourceBytes === expected.bytes)));
    const labels = loaded.toolScriptPlan.map((entry) => entry.label);
    assert.strictEqual(labels.at(-1), "detach_hooks");
    assert.strictEqual(labels.filter((label) => label === "detach_hooks").length, 1);
    const runner = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
    const firstSeal = runner.indexOf("await state.observer.sealPageHooksForFinalCapture();");
    const safeExit = runner.indexOf("const safeExitControl = await controlStep(state, \"safe_exit\"");
    const exitConfirm = runner.indexOf("await controlStep(state, \"exit_confirm\"");
    assert(firstSeal > 0 && safeExit > firstSeal && exitConfirm > safeExit);
    assert(runner.slice(safeExit, exitConfirm).includes("skipObserverHealth: true"));
    assert(runner.slice(exitConfirm, runner.indexOf("await session.awaitExit", exitConfirm))
      .includes("skipObserverHealth: true"));
    verifyEvidenceFile(fixture.bundlePath);
  });
  assert.throws(() => withFixture({}, (fixture) => {
    const bundle = load(fixture);
    ProductionClosure.loadedResourcePolicy(bundle.root, bundle.productionClosure,
      ["不存在的权威图标"]);
  }), (error) => error instanceof NpcJourneyError
    && error.code === "production_icon_projection_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded) => {
      const font = loaded.resourceOccurrences.find((entry) => entry.resourceType === "Font");
      const extra = deepClone(font);
      extra.occurrence = loaded.resourceOccurrences.length + 1;
      extra.url = "https://cfn-fonts.local/unmapped-fixture.ttf";
      loaded.resourceOccurrences.push(extra);
    });
  }, "loaded_production_resource_set_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded, bundle) => {
      const policy = ProductionClosure.loadedResourcePolicy(bundle.root,
        bundle.productionClosure, loaded.resourceIconNames);
      const target = policy.required.find((entry) => entry.reason === "idle_prewarm_base");
      const index = loaded.resourceOccurrences.findIndex((entry) =>
        entry.resourceType === target.resourceType && entry.url === target.url);
      assert(index >= 0);
      loaded.resourceOccurrences.splice(index, 1);
      loaded.resourceOccurrences.forEach((entry, occurrence) => {
        entry.occurrence = occurrence + 1;
      });
    });
  }, "loaded_production_resource_set_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "restart", (loaded) => {
      loaded.resourceOccurrences[0].frameId = "fixture-child-frame";
    });
  }, "loaded_production_resource_set_invalid");
  expectFixtureRejected({}, (fixture) => {
    const bundle = load(fixture);
    const safe = bundle.controls.find((entry) => entry.step === "safe_exit");
    const request = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
      safe.requestArtifact), "utf8"));
    rewriteLoaded(fixture, "first", (loaded) => {
      loaded.capturedAt = new Date(Date.parse(request.issuedAt) + 1).toISOString();
    });
  }, "strict_lifecycle_timeline_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded) => {
      const plan = loaded.toolScriptPlan.find((entry) => entry.label === "detach_hooks");
      loaded.toolScriptPlan = loaded.toolScriptPlan.filter((entry) => entry !== plan);
      loaded.scriptOccurrences = loaded.scriptOccurrences.filter((entry) => entry.url !== plan.url);
      loaded.scriptOccurrences.forEach((entry, occurrence) => {
        entry.occurrence = occurrence + 1;
      });
    });
  }, "loaded_production_tool_script_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "restart", (loaded) => {
      const priorPlan = loaded.toolScriptPlan.at(-1);
      const plan = deepClone(priorPlan);
      plan.sequence = loaded.toolScriptPlan.length + 1;
      plan.url = priorPlan.url.replace(/\d{4}-detach_hooks\.js$/,
        String(plan.sequence).padStart(4, "0") + "-detach_hooks.js");
      plan.sha256 = sha256Text("extra terminal detach source");
      plan.bytes = Buffer.byteLength("extra terminal detach source", "utf8");
      loaded.toolScriptPlan.push(plan);
      const occurrence = deepClone(loaded.scriptOccurrences.find((entry) =>
        entry.url === priorPlan.url));
      occurrence.occurrence = loaded.scriptOccurrences.length + 1;
      occurrence.url = plan.url;
      occurrence.scriptId += "-extra-detach";
      occurrence.sourceSha256 = plan.sha256;
      occurrence.sourceBytes = plan.bytes;
      loaded.scriptOccurrences.push(occurrence);
    });
  }, "loaded_production_tool_script_invalid");
});

test("seventh-round recorder keeps scriptParsed raw params immutable across later context arrival", () => {
  const ledger = createScriptContextLedger();
  const rawParams = { scriptId: "script.1", url: "https://overlay.local/example.js",
    executionContextId: 7,
    executionContextAuxData: { frameId: "script-frame", isDefault: true, type: "default" } };
  ledger.record({ method: "Debugger.scriptParsed", params: rawParams });
  rawParams.executionContextAuxData.frameId = "mutated-after-record";
  ledger.record({ method: "Runtime.executionContextCreated", params: { context: {
    id: 7, origin: "https://overlay.local", name: "", uniqueId: "context.7",
    auxData: { frameId: "context-frame", isDefault: true, type: "default" },
  } } });
  const script = ledger.parsedScriptOrder[0];
  assert.strictEqual(script.rawExecutionContextAuxData.frameId, "script-frame");
  assert.strictEqual(script.rawParams.executionContextAuxData.frameId, "script-frame");
  assert.strictEqual(script.frameId, "script-frame");
  assert.strictEqual(script.contextOrigin, "https://overlay.local");
  assert.strictEqual(ledger.executionContextOrder[0].rawAuxData.frameId, "context-frame");
  assert(Object.isFrozen(script.rawParams));
  assert(Object.isFrozen(script.rawExecutionContextAuxData));
});

test("seventh-round execution contexts and both raw auxData sources fail closed", () => {
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded) => {
      loaded.executionContexts[0].rawAuxData.foreignMarker = true;
    });
  }, "loaded_production_context_set_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "restart", (loaded) => {
      loaded.executionContexts[0].rawAuxData.isDefault = false;
    });
  }, "loaded_production_context_set_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded) => {
      loaded.scriptOccurrences[0].rawExecutionContextAuxData.type = "isolated";
      loaded.scriptOccurrences[0].rawParams.executionContextAuxData.type = "isolated";
    });
  }, "loaded_production_script_occurrence_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "restart", (loaded) => {
      delete loaded.scriptOccurrences[0].rawExecutionContextAuxData;
    });
  }, "loaded_production_script_occurrence_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "restart", (loaded) => {
      const context = deepClone(loaded.executionContexts[0]);
      context.occurrence = 2;
      context.id += 1000;
      loaded.executionContexts.push(context);
      const script = deepClone(loaded.scriptOccurrences.at(-1));
      script.occurrence = loaded.scriptOccurrences.length + 1;
      script.scriptId += "-duplicate-context";
      script.executionContextId = context.id;
      script.rawParams.scriptId = script.scriptId;
      script.rawParams.executionContextId = context.id;
      loaded.scriptOccurrences.push(script);
    });
  }, "loaded_production_context_set_invalid");
});

test("fifth-round provider stages, targets, and serial order fail closed", () => {
  withFixture({}, (fixture) => {
    const bundle = load(fixture);
    bundle.controls.forEach((binding) => {
      const ack = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
        binding.ackArtifact), "utf8"));
      const provider = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
        ack.providerReceipt.artifact), "utf8"));
      assert.strictEqual(provider.schema, PROVIDER_RECEIPT_SCHEMA);
      assert(Date.parse(provider.startedAt) < Date.parse(provider.inputAt));
      assert(Date.parse(provider.inputAt) < Date.parse(provider.captureAt));
      assert(Date.parse(provider.captureAt) < Date.parse(provider.completedAt));
      assert(Date.parse(provider.completedAt) < Date.parse(ack.completedAt));
      assert.strictEqual(provider.inputEvidence.observedAt, provider.inputAt);
    });
  });
  expectFixtureRejected({}, (fixture) => {
    rewriteProvider(fixture, "safe_exit", (provider) => {
      provider.inputEvidence.selector = "native-control[data-step=\"exit_confirm\"]";
    });
  }, "provider_input_target_mismatch");
  expectFixtureRejected({}, (fixture) => {
    rewriteProvider(fixture, "select_purchase", (provider) => {
      provider.inputAt = provider.startedAt;
      provider.inputEvidence.observedAt = provider.inputAt;
    });
  }, "provider_receipt_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteProvider(fixture, "commit_purchase", (provider) => {
      provider.inputEvidence.observedAt = provider.startedAt;
    });
  }, "provider_receipt_invalid");
  expectFixtureRejected({}, (fixture) => {
    const bundle = load(fixture);
    const previous = bundle.controls.find((entry) => entry.step === "select_purchase");
    const previousAck = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
      previous.ackArtifact), "utf8"));
    rewriteControlRequest(fixture, "open_purchase_settlement", (request) => {
      request.issuedAt = previousAck.completedAt;
      request.expiresAt = new Date(Date.parse(request.issuedAt) + request.ttlMs).toISOString();
    });
  }, "control_operation_order_invalid");
  expectFixtureRejected({}, (fixture) => {
    const bundle = load(fixture);
    const left = bundle.controls.findIndex((entry) => entry.step === "select_purchase");
    const right = bundle.controls.findIndex((entry) => entry.step === "open_purchase_settlement");
    [bundle.controls[left], bundle.controls[right]] = [bundle.controls[right], bundle.controls[left]];
    save(fixture, bundle);
  }, "control_operation_order_invalid");
});

test("sixth-round icon projection trusts only authoritative NPC and Inventory state", () =>
  withFixture({}, (fixture) => {
    const bundle = load(fixture);
    const transcript = JSON.parse(fs.readFileSync(path.join(fixture.runDir,
      bundle.transcriptArtifact), "utf8"));
    const expected = ["砍刀", "黄鹂短刀", "经验值", "金钱"];
    const pairs = Protocol.strictRequestPairsFromEvents(transcript.events);
    assert.deepStrictEqual(ProductionClosure.authorityIconNames(pairs), expected);
    assert.throws(() => ProductionClosure.authorityIconNames(transcript.events),
      (error) => error instanceof NpcJourneyError
        && error.code === "authority_icon_pair_set_invalid");
    const polluted = [
      { kind: "bridge_send", direction: "outbound", message: { icon: "技能点" } },
      { kind: "webview_message", direction: "inbound",
        message: { type: "panel_cmd", cmd: "open", panel: "npcshop", icon: "技能点" } },
    ].concat(transcript.events);
    assert.deepStrictEqual(ProductionClosure.authorityIconNames(
      Protocol.strictRequestPairsFromEvents(polluted)), expected);
    const previewPollutedPairs = deepClone(pairs);
    previewPollutedPairs.find((pair) => pair.response.message.cmd === "tradePreview")
      .response.message.icon = "技能点";
    assert.deepStrictEqual(ProductionClosure.authorityIconNames(previewPollutedPairs), expected);
  }));

negative("NPC panel-open envelope rejects ordinary icon-field pollution", (fixture) =>
  reseal(fixture, (events) => {
    const open = events.find((event) => event.kind === "webview_message" && event.message
      && event.message.type === "panel_cmd" && event.message.cmd === "open");
    open.message.icon = "技能点";
  }), "panel_open_contract_invalid");

test("sixth-round unprojected icon names and Page resources fail closed", () => {
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded) => {
      loaded.resourceIconNames.push("技能点");
    });
  }, "loaded_production_multiset_invalid");
  expectFixtureRejected({}, (fixture) => {
    rewriteLoaded(fixture, "first", (loaded, bundle) => {
      const target = ProductionClosure.loadedResourcePolicy(bundle.root,
        bundle.productionClosure, ["技能点"]).required.find((entry) =>
        entry.reason === "authority_projected_icon:技能点");
      assert(target);
      loaded.resourceOccurrences.push({
        occurrence: loaded.resourceOccurrences.length + 1,
        frameId: loaded.resourceOccurrences[0].frameId,
        frameUrl: "https://overlay.local/overlay.html",
        frameOrigin: "https://overlay.local",
        url: target.url,
        origin: target.origin,
        resourceType: target.resourceType,
        mimeType: target.mimeTypes[0],
        sourceMethod: "Page.getResourceContent",
        sourceSha256: target.sha256,
        sourceBytes: target.bytes,
      });
    });
  }, "loaded_production_resource_set_invalid");
});

test("sixth-round machine output separates single JSON control modes from live NDJSON", () =>
  withFixture({}, (fixture) => {
    function assertSingleJson(result, label) {
      assert.strictEqual(result.status, 0, label + " status\n" + result.stderr);
      assert.strictEqual(result.stderr, "", label + " stderr");
      const lines = String(result.stdout).split(/\r?\n/).filter(Boolean);
      assert.strictEqual(lines.length, 1, label + " stdout line count");
      return JSON.parse(lines[0]);
    }
    const bootstrap = path.join(__dirname, "bootstrap.js");
    const help = assertSingleJson(childProcess.spawnSync(process.execPath,
      [bootstrap, "--help"], { encoding: "utf8", windowsHide: true }), "help");
    assert.strictEqual(typeof help.help, "string");
    const verified = assertSingleJson(childProcess.spawnSync(process.execPath,
      [bootstrap, "--verify-bundle", fixture.bundlePath],
      { encoding: "utf8", windowsHide: true }), "verify");
    assert.strictEqual(verified.receipt.status, "OFFLINE_VERIFIED");

    const request = controlRequestOutputRecord("select_purchase", {
      requestId: "request.fixture.1",
      requestPath: "C:/fixture/control/request.json",
      expiresAt: "2026-08-04T12:00:00.000Z",
    });
    assert.deepStrictEqual(request, {
      type: "control_request",
      step: "select_purchase",
      requestId: "request.fixture.1",
      requestPath: "C:/fixture/control/request.json",
      expiresAt: "2026-08-04T12:00:00.000Z",
    });
    const source = fs.readFileSync(bootstrap, "utf8");
    const dispatchStart = source.indexOf("async function dispatch()");
    const checkStart = source.indexOf('if (mode === "check")', dispatchStart);
    const liveBoundary = source.slice(checkStart).search(
      /\r?\n\r?\n  controller\.checkpoint\("domain_loaded"\);/);
    assert(liveBoundary >= 0);
    const liveStart = checkStart + liveBoundary;
    const checkBranch = source.slice(checkStart, liveStart);
    assert.strictEqual((checkBranch.match(/process\.stdout\.write/g) || []).length, 1);
    assert(source.includes('type: "final_status"'));
  }));

async function run(options) {
  const settings = options || {};
  browserGateReceipt = null;
  const fullRun = typeof settings.filter !== "function";
  const selectedTests = fullRun ? tests : tests.filter(settings.filter);
  let passed = 0;
  const failures = [];
  for (const current of selectedTests) {
    try {
      await current.body();
      passed += 1;
      if (!settings.quiet) process.stdout.write("PASS " + current.name + "\n");
    }
    catch (error) {
      failures.push({ name: current.name, error });
      if (!settings.quiet) {
        process.stderr.write("FAIL " + current.name + "\n" + (error.stack || String(error)) + "\n");
      }
    }
  }
  if (!settings.quiet) process.stdout.write("NPC A3 OFFLINE " + passed + "/" + selectedTests.length + " PASS\n");
  if (failures.length) {
    const error = new Error("NPC offline Gate failed " + failures.length + " test(s): "
      + failures.map((entry) => entry.name).join(", "));
    error.code = "npc_offline_gate_failed";
    error.failures = failures;
    throw error;
  }
  if (fullRun) assert(browserGateReceipt);
  const result = { passed, total: selectedTests.length };
  if (fullRun) result.childReceipts = { browser:browserGateReceipt };
  return result;
}

module.exports = { run };
if (require.main === module) {
  process.stderr.write("self-test.js is NOT_ADMITTED directly; use npc/bootstrap.js --check\n");
  process.exitCode = 2;
}
