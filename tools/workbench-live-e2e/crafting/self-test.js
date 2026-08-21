#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const Evidence = require("../lib/evidence-artifact");
const ModuleJournal = require("../lib/runtime-module-journal");
const Common = require("./common");
const { nextRecord } = Common;
const Verifier = require("./evidence-verifier");
const Fixture = require("./fixtures/valid-bundle");
const Observer = require("./cdp-passive-observer");
const Protocol = require("./protocol");
const SourceContract = require("./source-contract");
const As2AnchorTest = require("./as2-anchor-test");
const { domInputEvidence, expectedProviderCaptureEventId,
  expectedProviderOperationId } = require("./control-channel");

function resealTranscript(transcript) {
  let previous = "0".repeat(64);
  transcript.events = transcript.events.map((event, index) => {
    const raw = Object.assign({}, event);
    delete raw.sequence;
    delete raw.previousHash;
    delete raw.eventHash;
    const sealed = nextRecord(previous, index + 1, raw);
    previous = sealed.eventHash;
    return sealed;
  });
  transcript.eventCount = transcript.events.length;
  transcript.chainHead = previous;
}

function resealLog(snapshot) {
  snapshot.records.forEach((record, index) => { record.lineNumber = index + 1; });
  snapshot.total = snapshot.records.length;
  snapshot.oldestLineNumber = 1;
  const payload = { schema: snapshot.schema, requestedTailLimit: snapshot.requestedTailLimit,
    sessionEvidenceSha256: snapshot.sessionEvidenceSha256, lifecycleId: snapshot.lifecycleId,
    sessionPid: snapshot.sessionPid,
    sessionProcessStartUtcTicks: snapshot.sessionProcessStartUtcTicks,
    total: snapshot.total, oldestLineNumber: snapshot.oldestLineNumber, records: snapshot.records };
  snapshot.tailSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function resealDigest(value, field) {
  const payload = Object.assign({}, value);
  delete payload[field];
  value[field] = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function preCommitPrefix(transcript) {
  const commitIndex = transcript.events.findIndex((event) => event.kind === "dom_input"
    && event.target && event.target.attributes
    && Object.prototype.hasOwnProperty.call(event.target.attributes, "data-commit-primary"));
  assert(commitIndex > 0, "fixture must expose one commit boundary");
  const events = transcript.events.slice(0, commitIndex).map((event) => Common.deepClone(event));
  return Object.assign({}, transcript, { events, eventCount: events.length,
    chainHead: events[events.length - 1].eventHash });
}

function resealSourceClosure(closure) {
  closure.records.forEach((record) => {
    const fingerprint = record.fingerprint;
    const payload = { schema: fingerprint.schema, capturedAt: fingerprint.capturedAt,
      root: fingerprint.root, head: fingerprint.head, files: fingerprint.files,
      producerInputs: fingerprint.producerInputs,
      as2AlgorithmContract: fingerprint.as2AlgorithmContract };
    fingerprint.fingerprintSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
  });
  resealDigest(closure, "closureSha256");
}

function pngCrc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value >>> 1) ^ (value & 1 ? 0xedb88320 : 0);
    }
  }
  return (value ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const output = Buffer.alloc(12 + data.length);
  output.writeUInt32BE(data.length, 0);
  name.copy(output, 4);
  data.copy(output, 8);
  output.writeUInt32BE(pngCrc32(Buffer.concat([name, data])), 8 + data.length);
  return output;
}

function testPng(width, height, bitDepth, colorType, inflated, options) {
  const settings = options || {};
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = bitDepth;
  ihdr[9] = colorType;
  const compressed = settings.compressed || zlib.deflateSync(inflated);
  const chunks = [pngChunk("IHDR", ihdr)];
  if (settings.palette) chunks.push(pngChunk("PLTE", settings.palette));
  chunks.push(pngChunk("IDAT", compressed), pngChunk("IEND", Buffer.alloc(0)));
  return Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex")].concat(chunks));
}

function rebindFixtureProviderDomInputs(bundle) {
  const first = bundle.transcripts.first.events.filter((entry) => entry.kind === "dom_input");
  const restart = bundle.transcripts.restart.events.filter((entry) => entry.kind === "dom_input");
  const bindings = new Map([
    ["select_recipe", [bundle.transcripts.first, first[0]]],
    ["capture_inventory_before", [bundle.transcripts.first, first[1]]],
    ["return_from_inventory_before", [bundle.transcripts.first, first[2]]],
    ["commit_recipe", [bundle.transcripts.first, first[3]]],
    ["capture_inventory_after", [bundle.transcripts.first, first[4]]],
    ["return_from_inventory_after", [bundle.transcripts.first, first[5]]],
    ["close_first_crafting", [bundle.transcripts.first, first[6]]],
    ["restart_select_recipe", [bundle.transcripts.restart, restart[0]]],
    ["restart_capture_inventory", [bundle.transcripts.restart, restart[1]]],
    ["restart_return_from_inventory", [bundle.transcripts.restart, restart[2]]],
    ["restart_close_crafting", [bundle.transcripts.restart, restart[3]]],
  ]);
  bindings.forEach((binding, step) => {
    const request = bundle.control.requests.find((entry) => entry.step === step);
    const ack = bundle.control.acks.find((entry) => entry.requestId === request.requestId);
    const file = path.join(bundle.runDir, ack.providerReceipt.artifact.replace(/\//g, path.sep));
    const receipt = JSON.parse(fs.readFileSync(file, "utf8"));
    receipt.inputEvidence = domInputEvidence(binding[0].observerId, binding[1]);
    receipt.providerOperationId = expectedProviderOperationId(receipt);
    resealDigest(receipt, "receiptSha256");
    const bytes = Buffer.from(JSON.stringify(receipt, null, 2) + "\n", "utf8");
    fs.writeFileSync(file, bytes);
    ack.providerReceipt.sha256 = Evidence.sha256Bytes(bytes);
  });
}

function inventoryResponses(transcript) {
  return transcript.events.filter((event) => event.kind === "webview_message"
    && event.message && event.message.domain === "inventory");
}

function setInventoryQuantity(response, quantity) {
  const slot = response.message.snapshots[0].slots[0];
  slot.item.quantity = quantity;
  slot.confirmProjection.quantity = quantity;
}

function equipmentInsertContract() {
  const output = {
    name: "fixture.equipment.internal", displayName: "验证装备产物", icon: "强化石",
    itemKind: "equipment", value: 5, quantity: 1, enhancementLevel: 5,
    majorType: "武器", use: "长枪", actionType: "", weaponType: "突击步枪",
    setId: "", setName: "", setOrder: 0, requiredLevel: 1,
  };
  const item = {
    name: output.name, displayName: output.displayName, icon: output.icon,
    majorType: output.majorType, use: output.use, actionType: output.actionType,
    weaponType: output.weaponType, setId: "", setName: "", setOrder: 0,
    itemKind: "equipment", quantity: 1, enhancementLevel: 5,
    maxEnhancementLevel: 13, isMaxEnhancement: false,
    tierSlotAvailable: false, tierSlotUsed: false,
    modSlotCapacity: 3, modSlotUsed: 0, modSlots: [], modMeta: null, rarity: "rare",
    balanceSummary: { state: "confirmed", weightLayers: 0, formula: 1, level: 1 },
  };
  const stableConfirm = {
    itemKind: item.itemKind, name: item.name, displayName: item.displayName,
    quantity: 1, enhancementLevel: 5, rarity: "rare", tier: "", modSignature: "",
  };
  return {
    output,
    delivery: { available: true, storageKind: "bag", mode: "insert",
      physicalSlot: 3, quantity: 1 },
    prototype: { item: Common.deepClone(item), confirmProjection: stableConfirm },
    receipt: { item: Common.deepClone(item), confirmProjection: Object.assign(
      { lastUpdate: 2000 }, stableConfirm) },
  };
}

function convertFirstTranscriptToEquipmentInsert(bundle) {
  const contract = equipmentInsertContract();
  bundle.transcripts.first.events.forEach((event) => {
    const message = event.message;
    if (!message || message.domain !== "crafting" || message.type !== "panel_resp") return;
    if (message.cmd === "snapshot") {
      const recipeOutput = Common.deepClone(contract.output);
      delete recipeOutput.requiredLevel;
      message.recipes[0].output = recipeOutput;
      return;
    }
    if (message.cmd === "preview") {
      message.output = Common.deepClone(contract.output);
      message.outputDelivery = Common.deepClone(contract.delivery);
      message.acceptedPlan.output = Common.deepClone(contract.output);
      message.acceptedPlan.outputDelivery = Common.deepClone(contract.delivery);
      message.acceptedPlan.outputPrototype = Common.deepClone(contract.prototype);
      return;
    }
    if (message.cmd === "commit") {
      message.crafted = Common.deepClone(contract.output);
      message.acceptedPlan.output = Common.deepClone(contract.output);
      message.acceptedPlan.outputDelivery = Common.deepClone(contract.delivery);
      message.acceptedPlan.outputPrototype = Common.deepClone(contract.prototype);
      message.outputReceipt = Common.deepClone(contract.receipt);
    }
  });
  const inventory = inventoryResponses(bundle.transcripts.first);
  const before = inventory[0].message.snapshots[0];
  const after = inventory[1].message.snapshots[0];
  const priorOutputLease = after.slots[0].slotLeaseRef;
  after.slots[0] = Common.deepClone(before.slots[0]);
  after.slots[0].slotLeaseRef = priorOutputLease;
  const target = after.slots[3];
  after.slots[3] = {
    physicalSlot: 3, occupied: true, slotLeaseRef: target.slotLeaseRef,
    item: Common.deepClone(contract.receipt.item),
    confirmProjection: Common.deepClone(contract.receipt.confirmProjection),
  };
  after.filterItemCount += 1;
  after.filterFacets[0].count += 1;
  resealTranscript(bundle.transcripts.first);
  return contract;
}

function commitResponse(bundle) {
  return bundle.transcripts.first.events.find((event) => event.kind === "webview_message"
    && event.message && event.message.domain === "crafting"
    && event.message.cmd === "commit").message;
}

function mutateReceiptAndReadback(bundle, mutate) {
  const commit = commitResponse(bundle);
  const afterSlot = inventoryResponses(bundle.transcripts.first)[1].message.snapshots[0].slots[0];
  mutate(commit.outputReceipt, afterSlot);
  resealTranscript(bundle.transcripts.first);
}

function semantic(bundle) {
  return Verifier.verifySemanticBundle(bundle, {
    testOnlyAllowInjectedEvidence: true,
    skipFileClosure: true,
  });
}

function writeArtifactFixture(bundle) {
  const roles = {
    "journey-bundle.json": "verified_input",
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
  fs.mkdirSync(bundle.runDir, { recursive: true });
  function write(relative, value, jsonl) {
    const target = path.join(bundle.runDir, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const text = jsonl ? value.events.map((entry) => JSON.stringify(entry)).join("\n") + "\n"
      : JSON.stringify(value, null, 2) + "\n";
    fs.writeFileSync(target, text, "utf8");
  }
  write("journey-bundle.json", bundle);
  ["first", "restart"].forEach((phase) => {
    write("crafting-" + phase + "-passive-transcript.json", bundle.transcripts[phase]);
    write("crafting-" + phase + "-passive-transcript.jsonl", bundle.transcripts[phase], true);
  });
  write("first-host-as2-tail.json", bundle.hostArtifacts.first);
  write("restart-host-as2-tail.json", bundle.hostArtifacts.restart);
  write("persistence-phases.json", bundle.persistence);
  write("runtime-lifecycles.json", bundle.runtime);
  write("source-closure.json", bundle.sourceClosure);
  write("source-binding.json", bundle.sourceBinding);
  write("candidate-producer.json", bundle.candidateProducer);
  bundle.control.requests.forEach((request, index) => {
    const ack = bundle.control.acks[index];
    const requestPath = "control/requests/" + request.requestId + ".json";
    const ackPath = "control/acks/" + request.requestId + ".json";
    write(requestPath, request);
    write(ackPath, ack);
    roles[requestPath] = "control_request";
    roles[ackPath] = "control_ack";
    roles[ack.providerReceipt.artifact] = "provider_receipt";
    const providerReceipt = JSON.parse(fs.readFileSync(
      path.join(bundle.runDir, ack.providerReceipt.artifact), "utf8"));
    roles[providerReceipt.captureEventRef.artifact] = "provider_capture_event";
    if (ack.capture) roles[ack.capture.relativePath] = "provider_capture";
  });
  const manifest = new Map(Object.keys(roles).map((relative) => {
    const absolutePath = path.join(bundle.runDir, relative);
    const bytes = fs.readFileSync(absolutePath);
    return [relative, { absolutePath, role: roles[relative], bytes: bytes.length,
      sha256: Evidence.sha256Bytes(bytes) }];
  }));
  return { manifest, roles };
}

const AS2_ANCHOR_MODULE_LOCATOR =
  "root:tools/workbench-live-e2e/crafting/as2-anchor-test.js";
const SELF_TEST_MODULE_LOCATOR = "root:tools/workbench-live-e2e/crafting/self-test.js";
const ISOLATED_MODULE_MANIFEST_FIXTURE_SCHEMA =
  "workbench-live-e2e.crafting.module-manifest-fixture.v1";
const ISOLATED_MODULE_MANIFEST_RESULT_SCHEMA =
  "workbench-live-e2e.crafting.module-manifest-isolated-test.v1";
const ISOLATED_MODULE_MANIFEST_RECEIPT_SCHEMA =
  "workbench-live-e2e.crafting.module-manifest-child-receipt.v2";
const MODULE_CONTRACT_CHILD_TIMEOUT_MS = 120000;
const ISOLATED_MODULE_MANIFEST_FAILURES = Object.freeze([
  { caseId: "missing_registration",
    errorCode: "runtime_module_journal_coverage_mismatch" },
  { caseId: "extra_loadable",
    errorCode: "runtime_module_journal_coverage_mismatch" },
  { caseId: "locator_only_drift", errorCode: "module_manifest_file_changed" },
  { caseId: "bytes_only_drift", errorCode: "module_manifest_file_changed" },
  { caseId: "hash_only_drift", errorCode: "module_manifest_file_changed" },
]);

function resealModuleManifest(manifest) {
  manifest.entries.sort((left, right) => left.locator.localeCompare(right.locator));
  const payload = Object.assign({}, manifest);
  delete payload.manifestSha256;
  manifest.manifestSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function resealModuleJournalArtifact(artifact, manifest) {
  artifact.manifestSha256 = manifest.manifestSha256;
  const payload = Object.assign({}, artifact);
  delete payload.evidenceSha256;
  artifact.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function captureModuleContractFailure(body, expected) {
  let errorCode = null;
  try {
    body();
  } catch (error) {
    errorCode = error && error.code || null;
  }
  assert.strictEqual(errorCode, expected.errorCode, expected.caseId);
  return { caseId: expected.caseId, errorCode };
}

function runIsolatedModuleManifestContractTests(fixtureInput) {
  const raw = JSON.stringify(fixtureInput);
  assert.ok(raw.length > 0 && raw.length <= 8 * 1024 * 1024,
    "module manifest fixture has invalid size");
  const fixture = JSON.parse(raw);
  assert.ok(fixture && typeof fixture === "object" && !Array.isArray(fixture));
  assert.deepStrictEqual(Object.keys(fixture).sort(), ["artifact", "manifest", "schema"]);
  assert.strictEqual(fixture.schema, ISOLATED_MODULE_MANIFEST_FIXTURE_SCHEMA);
  const productionRoot = path.resolve(__dirname, "..", "..", "..");
  ModuleJournal.verifyRuntimeModuleJournal({
    root: productionRoot, manifest: fixture.manifest, artifact: fixture.artifact,
  });

  function clonedFixture() {
    return JSON.parse(JSON.stringify({ manifest: fixture.manifest, artifact: fixture.artifact }));
  }
  const cases = [];

  const missing = clonedFixture();
  missing.manifest.entries = missing.manifest.entries.filter((entry) =>
    entry.locator !== AS2_ANCHOR_MODULE_LOCATOR);
  resealModuleManifest(missing.manifest);
  resealModuleJournalArtifact(missing.artifact, missing.manifest);
  cases.push(captureModuleContractFailure(() => ModuleJournal.verifyRuntimeModuleJournal({
    root: productionRoot, manifest: missing.manifest, artifact: missing.artifact,
  }), ISOLATED_MODULE_MANIFEST_FAILURES[0]));

  const extra = clonedFixture();
  const extraPath = path.resolve(__dirname, "run-checks.js");
  const extraBytes = fs.readFileSync(extraPath);
  extra.manifest.entries.push({
    locator: "root:tools/workbench-live-e2e/crafting/run-checks.js",
    scope: "repo", role: "offline_unloaded_tombstone", loadable: true,
    preexisting: false, sha256: Evidence.sha256Bytes(extraBytes), bytes: extraBytes.length,
  });
  resealModuleManifest(extra.manifest);
  resealModuleJournalArtifact(extra.artifact, extra.manifest);
  cases.push(captureModuleContractFailure(() => ModuleJournal.verifyRuntimeModuleJournal({
    root: productionRoot, manifest: extra.manifest, artifact: extra.artifact,
  }), ISOLATED_MODULE_MANIFEST_FAILURES[1]));

  const locatorDrift = clonedFixture();
  locatorDrift.manifest.entries.find((entry) => entry.locator === AS2_ANCHOR_MODULE_LOCATOR)
    .locator = "root:tools/workbench-live-e2e/crafting/run-checks.js";
  resealModuleManifest(locatorDrift.manifest);
  cases.push(captureModuleContractFailure(() => ModuleJournal.verifyExplicitModuleManifest({
    root: productionRoot, manifest: locatorDrift.manifest,
  }), ISOLATED_MODULE_MANIFEST_FAILURES[2]));

  const bytesDrift = clonedFixture();
  bytesDrift.manifest.entries.find((entry) => entry.locator === AS2_ANCHOR_MODULE_LOCATOR)
    .bytes += 1;
  resealModuleManifest(bytesDrift.manifest);
  cases.push(captureModuleContractFailure(() => ModuleJournal.verifyExplicitModuleManifest({
    root: productionRoot, manifest: bytesDrift.manifest,
  }), ISOLATED_MODULE_MANIFEST_FAILURES[3]));

  const hashDrift = clonedFixture();
  const hashEntry = hashDrift.manifest.entries.find((entry) =>
    entry.locator === AS2_ANCHOR_MODULE_LOCATOR);
  hashEntry.sha256 = hashEntry.sha256 === "0".repeat(64) ? "1".repeat(64) : "0".repeat(64);
  resealModuleManifest(hashDrift.manifest);
  cases.push(captureModuleContractFailure(() => ModuleJournal.verifyExplicitModuleManifest({
    root: productionRoot, manifest: hashDrift.manifest,
  }), ISOLATED_MODULE_MANIFEST_FAILURES[4]));

  return { schema: ISOLATED_MODULE_MANIFEST_RESULT_SCHEMA,
    total: cases.length, passed: cases.length, failed: 0, cases };
}

function runModuleManifestContractTests() {
  const result = childProcess.spawnSync(process.execPath, [
    require.resolve("./bootstrap"), "--emit-offline-admission-fixture",
  ], { encoding: "utf8", windowsHide: true,
    timeout: MODULE_CONTRACT_CHILD_TIMEOUT_MS, maxBuffer: 4 * 1024 * 1024 });
  assert.strictEqual(result.error, undefined);
  assert.strictEqual(result.signal, null);
  assert.strictEqual(result.status, 0, result.stderr);
  assert.strictEqual(result.stderr, "");
  const emitted = JSON.parse(result.stdout);
  const productionRoot = path.resolve(__dirname, "..", "..", "..");
  assert.strictEqual(emitted.artifact.admissionStatus, ModuleJournal.ADMISSION_STATUS);
  assert.strictEqual(emitted.artifact.manifestSha256, emitted.manifest.manifestSha256);
  assert.deepStrictEqual(emitted.manifest.requiredPhases, ["domain_loaded", "terminal"]);
  assert.ok(/^[a-f0-9]{64}$/.test(emitted.artifact.evidenceSha256));
  assert.strictEqual(emitted.manifest.entries.length, 28);
  assert.strictEqual(emitted.artifact.loadedFiles.length, 27);
  assert.strictEqual(emitted.artifact.cacheAtRestore.length, 27);
  const nodeBytes = fs.readFileSync(process.execPath);
  assert.deepStrictEqual(emitted.processExecutable, {
    locator:"external:" + path.resolve(process.execPath).replace(/\\/g, "/"),
    scope:"external", role:"external_node_binary", loadable:false, preexisting:false,
    sha256:Evidence.sha256Bytes(nodeBytes), bytes:nodeBytes.length,
  });
  const anchorBytes = fs.readFileSync(require.resolve("./as2-anchor-test"));
  const anchorIndex = emitted.manifest.entries.findIndex((entry) =>
    entry.locator === AS2_ANCHOR_MODULE_LOCATOR);
  assert.strictEqual(anchorIndex, 9);
  const anchorEntry = emitted.manifest.entries[anchorIndex];
  assert.deepStrictEqual(anchorEntry, {
    locator: AS2_ANCHOR_MODULE_LOCATOR,
    scope: "repo",
    role: "offline_gate_dependency",
    loadable: true,
    preexisting: false,
    sha256: Evidence.sha256Bytes(anchorBytes),
    bytes: anchorBytes.length,
  });
  const loadedAnchorIndex = emitted.artifact.loadedFiles.findIndex((entry) =>
    entry.locator === AS2_ANCHOR_MODULE_LOCATOR);
  assert.strictEqual(loadedAnchorIndex, 8);
  assert.deepStrictEqual(emitted.artifact.loadedFiles[loadedAnchorIndex], {
    locator: anchorEntry.locator, sha256: anchorEntry.sha256, bytes: anchorEntry.bytes,
  });
  const anchorEvents = emitted.artifact.events.filter((event) =>
    event.kind === "file" && event.resolved === AS2_ANCHOR_MODULE_LOCATOR);
  assert.strictEqual(anchorEvents.length, 1);
  assert.strictEqual(anchorEvents[0].request, "./as2-anchor-test");
  assert.strictEqual(anchorEvents[0].parent, SELF_TEST_MODULE_LOCATOR);
  assert.strictEqual(anchorEvents[0].beforeSha256, anchorEntry.sha256);
  assert.strictEqual(anchorEvents[0].afterSha256, anchorEntry.sha256);
  assert.strictEqual(anchorEvents[0].beforeBytes, anchorEntry.bytes);
  assert.strictEqual(anchorEvents[0].afterBytes, anchorEntry.bytes);

  const isolatedInput = JSON.stringify({
    schema: ISOLATED_MODULE_MANIFEST_FIXTURE_SCHEMA,
    manifest: emitted.manifest, artifact: emitted.artifact,
  });
  const isolatedChild = childProcess.spawnSync(process.execPath, [
    require.resolve("./isolated-module-contract-bootstrap"),
  ], { input: isolatedInput, encoding: "utf8", windowsHide: true,
    timeout: MODULE_CONTRACT_CHILD_TIMEOUT_MS, maxBuffer: 16 * 1024 * 1024 });
  assert.strictEqual(isolatedChild.error, undefined);
  assert.strictEqual(isolatedChild.signal, null);
  assert.strictEqual(isolatedChild.status, 0, isolatedChild.stderr);
  assert.strictEqual(isolatedChild.stderr, "");
  assert.strictEqual(isolatedChild.stdout.trim().split(/\r?\n/).length, 1);
  const isolatedReceipt = JSON.parse(isolatedChild.stdout);
  assert.strictEqual(isolatedReceipt.schema, ISOLATED_MODULE_MANIFEST_RECEIPT_SCHEMA);
  assert.strictEqual(isolatedReceipt.status, "OFFLINE_VERIFIED");
  assert.strictEqual(isolatedReceipt.inputSha256,
    Evidence.sha256Text(isolatedInput));
  assert.strictEqual(isolatedReceipt.moduleAdmission, ModuleJournal.ADMISSION_STATUS);
  assert.ok(/^[a-f0-9]{64}$/.test(isolatedReceipt.manifestSha256));
  assert.ok(/^[a-f0-9]{64}$/.test(isolatedReceipt.moduleJournalSha256));
  assert.strictEqual(isolatedReceipt.moduleEntryCount, 26);
  assert.ok(/^[a-f0-9]{64}$/.test(isolatedReceipt.preAdmissionManifestSha256));
  assert.ok(/^[a-f0-9]{64}$/.test(isolatedReceipt.preAdmissionModuleJournalSha256));
  assert.strictEqual(isolatedReceipt.preAdmissionModuleEntryCount, 26);
  assert.strictEqual(isolatedReceipt.testedModulesLoadedBeforeAdmission, false);
  const isolatedNodeBytes = fs.readFileSync(process.execPath);
  assert.deepStrictEqual(isolatedReceipt.processExecutable, {
    locator:"external:" + path.resolve(process.execPath).replace(/\\/g, "/"),
    scope:"external", role:"external_node_binary", loadable:false, preexisting:false,
    sha256:Evidence.sha256Bytes(isolatedNodeBytes), bytes:isolatedNodeBytes.length,
  });
  const isolatedReceiptPayload = Object.assign({}, isolatedReceipt);
  delete isolatedReceiptPayload.evidenceSha256;
  assert.strictEqual(isolatedReceipt.evidenceSha256,
    Evidence.sha256Text(Evidence.canonicalJson(isolatedReceiptPayload)));
  const isolated = isolatedReceipt.result;
  assert.strictEqual(isolatedReceipt.resultSha256,
    Evidence.sha256Text(Evidence.canonicalJson(isolated)));
  assert.deepStrictEqual(Object.keys(isolated),
    ["schema", "total", "passed", "failed", "cases"]);
  assert.strictEqual(isolated.schema, ISOLATED_MODULE_MANIFEST_RESULT_SCHEMA);
  assert.strictEqual(isolated.total, 5);
  assert.strictEqual(isolated.passed, 5);
  assert.strictEqual(isolated.failed, 0);
  isolated.cases.forEach((entry) => assert.deepStrictEqual(Object.keys(entry),
    ["caseId", "errorCode"]));
  assert.deepStrictEqual(isolated.cases, ISOLATED_MODULE_MANIFEST_FAILURES);

  return { schema: "workbench-live-e2e.crafting.module-manifest-test.v1",
    total: 6, passed: 6, failed: 0, manifestEntries: 28,
    anchorIndex, anchorLocator: AS2_ANCHOR_MODULE_LOCATOR,
    childReceipt:{
      schema:isolatedReceipt.schema,
      evidenceSha256:isolatedReceipt.evidenceSha256,
      inputSha256:isolatedReceipt.inputSha256,
      manifestSha256:isolatedReceipt.manifestSha256,
      moduleJournalSha256:isolatedReceipt.moduleJournalSha256,
      moduleEntryCount:isolatedReceipt.moduleEntryCount,
      preAdmissionManifestSha256:isolatedReceipt.preAdmissionManifestSha256,
      preAdmissionModuleJournalSha256:isolatedReceipt.preAdmissionModuleJournalSha256,
      preAdmissionModuleEntryCount:isolatedReceipt.preAdmissionModuleEntryCount,
      testedModulesLoadedBeforeAdmission:false,
      processExecutable:isolatedReceipt.processExecutable,
      resultSha256:isolatedReceipt.resultSha256,
    } };
}

function runSelfTests() {
  const positives = [];
  const negatives = [];
  let browserGateReceipt = null;
  let isolatedModuleGateReceipt = null;
  function positive(name, body) { body(); positives.push(name); }
  function negative(name, expectedCode, mutate) {
    const bundle = Fixture.buildValidBundle();
    mutate(bundle);
    assert.throws(() => semantic(bundle), (error) => {
      if (!error || expectedCode && error.code !== expectedCode) {
        throw new Error(name + " expected " + expectedCode + " but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push(name);
  }
  function negativeDirect(name, expectedCode, body) {
    assert.throws(body, (error) => {
      if (!error || expectedCode && error.code !== expectedCode) {
        throw new Error(name + " expected " + expectedCode + " but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push(name);
  }
  function mutateProvider(bundle, step, mutate, reseal) {
    const request = bundle.control.requests.find((entry) => entry.step === step);
    const ack = bundle.control.acks.find((entry) => entry.requestId === request.requestId);
    const file = path.join(bundle.runDir, ack.providerReceipt.artifact.replace(/\//g, path.sep));
    const receipt = JSON.parse(fs.readFileSync(file, "utf8"));
    mutate(receipt);
    if (reseal !== false) resealDigest(receipt, "receiptSha256");
    const bytes = Buffer.from(JSON.stringify(receipt, null, 2) + "\n", "utf8");
    fs.writeFileSync(file, bytes);
    ack.providerReceipt.sha256 = Evidence.sha256Bytes(bytes);
  }
  function mutateBoundProvider(bundle, step, mutate) {
    mutateProvider(bundle, step, (receipt) => {
      mutate(receipt);
      receipt.providerOperationId = expectedProviderOperationId(receipt);
    });
  }
  function mutateCaptureEvent(bundle, step, mutate, options) {
    const settings = options || {};
    const request = bundle.control.requests.find((entry) => entry.step === step);
    const ack = bundle.control.acks.find((entry) => entry.requestId === request.requestId);
    const receiptFile = path.join(bundle.runDir,
      ack.providerReceipt.artifact.replace(/\//g, path.sep));
    const receipt = JSON.parse(fs.readFileSync(receiptFile, "utf8"));
    const eventFile = path.join(bundle.runDir,
      receipt.captureEventRef.artifact.replace(/\//g, path.sep));
    const event = JSON.parse(fs.readFileSync(eventFile, "utf8"));
    mutate(event, { request, ack, receipt, eventFile });
    if (settings.resealEvent !== false) {
      event.providerEventId = expectedProviderCaptureEventId(event);
      resealDigest(event, "eventSha256");
    }
    const eventBytes = Buffer.from(JSON.stringify(event, null, 2) + "\n", "utf8");
    fs.writeFileSync(eventFile, eventBytes);
    receipt.captureEventRef.sha256 = Evidence.sha256Bytes(eventBytes);
    receipt.captureEventRef.eventSha256 = event.eventSha256;
    receipt.providerOperationId = expectedProviderOperationId(receipt);
    resealDigest(receipt, "receiptSha256");
    const receiptBytes = Buffer.from(JSON.stringify(receipt, null, 2) + "\n", "utf8");
    fs.writeFileSync(receiptFile, receiptBytes);
    ack.providerReceipt.sha256 = Evidence.sha256Bytes(receiptBytes);
  }
  function overwriteCapture(bundle, step, bytes) {
    const request = bundle.control.requests.find((entry) => entry.step === step);
    const ack = bundle.control.acks.find((entry) => entry.requestId === request.requestId);
    const file = path.join(bundle.runDir, ack.capture.relativePath.replace(/\//g, path.sep));
    fs.writeFileSync(file, bytes);
    ack.capture.sha256 = Evidence.sha256Bytes(bytes);
    ack.capture.bytes = bytes.length;
    ack.captureSha256 = ack.capture.sha256;
  }

  positive("real-order Crafting+Inventory two-process fixture is admitted", () => {
    const result = semantic(Fixture.buildValidBundle());
    assert.strictEqual(result.first.inventory.afterCount - result.first.inventory.beforeCount, 1);
    assert.strictEqual(result.restart.inventory.count, result.first.inventory.afterCount);
    assert.strictEqual(result.host.firstMappings.length, 14);
  });
  positive("fixed bootstrap admits one explicit offline module closure", () => {
    const moduleResult = runModuleManifestContractTests();
    isolatedModuleGateReceipt = moduleResult.childReceipt;
    delete moduleResult.childReceipt;
    assert.deepStrictEqual(moduleResult, {
      schema: "workbench-live-e2e.crafting.module-manifest-test.v1",
      total: 6, passed: 6, failed: 0, manifestEntries: 28,
      anchorIndex: 9, anchorLocator: AS2_ANCHOR_MODULE_LOCATOR,
    });
  });
  positive("bootstrap verifies before checkpoint/seal and only then persists receipts", () => {
    const source = fs.readFileSync(require.resolve("./bootstrap"), "utf8");
    const checkVerify = source.indexOf("const checks = selfTest.runSelfTests();");
    const checkPoint = source.indexOf('controller.checkpoint("verification_executed");', checkVerify);
    const checkSeal = source.indexOf("const artifact = sealAdmission();", checkPoint);
    const verifyPrepare = source.indexOf("const prepared = verifier.prepare(verifyArgs);");
    const verifyPoint = source.indexOf('controller.checkpoint("verification_executed");', verifyPrepare);
    const verifySeal = source.indexOf("const artifact = sealAdmission();", verifyPoint);
    const verifyFinalize = source.indexOf("const verification = verifier.finalize(prepared);", verifySeal);
    const livePrepare = source.lastIndexOf("const prepared = output.prepare(manifest);");
    const livePoint = source.indexOf('controller.checkpoint("verification_executed");', livePrepare);
    const liveSeal = source.indexOf("const artifact = sealAdmission();", livePoint);
    const liveFinalize = source.indexOf("const result = prepared.complete(artifact);", liveSeal);
    assert.ok(checkVerify < checkPoint && checkPoint < checkSeal);
    assert.ok(verifyPrepare < verifyPoint && verifyPoint < verifySeal && verifySeal < verifyFinalize);
    assert.ok(livePrepare < livePoint && livePoint < liveSeal && liveSeal < liveFinalize);
  });
  positive("help success is one JSON document with empty stderr", () => {
    const result = childProcess.spawnSync(process.execPath,
      [require.resolve("./bootstrap"), "--help"], { encoding: "utf8", windowsHide: true });
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(result.stderr, "");
    const parsed = JSON.parse(result.stdout);
    assert.ok(parsed.help && typeof parsed.help.usage === "string");
    assert.strictEqual(result.stdout.trim().split(/\r?\n/).length, 1);
  });
  positive("canonical executes the production Crafting browser matrix under a child closure", () => {
    const browserBootstrap = path.join(__dirname, "browser-bootstrap.js");
    const browserSource = fs.readFileSync(browserBootstrap, "utf8");
    assert(browserSource.includes(
      "RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest, artifact:journal })"));
    assert(browserSource.includes("verifyServedResourceClosure({"));
    assert(browserSource.includes("browserExecutableReceipt({"));
    const moduleInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
      "browser-module-inventory.v1.json"), "utf8"));
    assert.strictEqual(moduleInventory.schema,
      "workbench-live-e2e.crafting.browser-module-inventory.v1");
    assert.strictEqual(moduleInventory.nodeVersion, process.version);
    assert.strictEqual(moduleInventory.files.length, 280);
    assert.strictEqual(moduleInventory.builtins.length, 23);
    const resourceInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
      "browser-resource-inventory.v1.json"), "utf8"));
    assert.strictEqual(resourceInventory.schema,
      "workbench-live-e2e.browser-resource-inventory.v1");
    assert.strictEqual(resourceInventory.files.length, 59);
    assert.strictEqual(resourceInventory.optionalFiles.length, 30);
    assert(resourceInventory.files.includes("modules/crafting/dev/harness.html"));
    assert(resourceInventory.files.includes("modules/crafting.js"));
    assert(resourceInventory.optionalFiles.every((relative) =>
      /^assets\/dressup\/skins\/c50514b6_\d+\.png$/.test(relative)));
    const child = childProcess.spawnSync(process.execPath, [browserBootstrap], {
      cwd:path.resolve(__dirname, "..", "..", ".."), encoding:"utf8",
      windowsHide:true, timeout:300000, maxBuffer:32 * 1024 * 1024,
    });
    assert.strictEqual(child.error, undefined, child.error && child.error.message);
    assert.strictEqual(child.status, 0, String(child.stderr || child.stdout));
    assert.strictEqual(child.stderr, "");
    const lines = child.stdout.split(/\r?\n/).filter(Boolean);
    assert.strictEqual(lines.length, 1, child.stdout);
    const receipt = JSON.parse(lines[0]);
    const receiptDigest = receipt.evidenceSha256;
    delete receipt.evidenceSha256;
    assert.strictEqual(Evidence.sha256Text(Evidence.canonicalJson(receipt)), receiptDigest);
    assert.strictEqual(receipt.schema,
      "workbench-live-e2e.crafting.browser-gate-receipt.v1");
    assert.strictEqual(receipt.status, "OFFLINE_VERIFIED");
    assert.strictEqual(receipt.moduleAdmission, "ADMITTED");
    assert.strictEqual(receipt.journalVerification, "VERIFIED");
    assert.strictEqual(receipt.moduleEntryCount, 376);
    assert.deepStrictEqual(receipt.result.viewports, [
      {width:1024,height:576}, {width:1366,height:768}, {width:1920,height:1080},
    ]);
    assert.deepStrictEqual(receipt.result.scenarioCounts,
      {baseline:150,coverage:15,fault:8,identity:10,legacy:6,sessionLock:9,
        recipeJump:26,materialShop:12,infrastructure:9,procurement:17});
    assert.strictEqual(receipt.result.faultChecks.length, 8);
    assert(receipt.result.faultChecks.every((entry) => entry.ok === true));
    assert.strictEqual(receipt.result.procurementChecks.length, 17);
    assert(receipt.result.procurementChecks.every((entry) => entry.ok === true));
    Object.values(receipt.result.scenarioNamesSha256).forEach((digest) =>
      assert(/^[a-f0-9]{64}$/.test(digest)));
    assert.deepStrictEqual(receipt.result.scenarioNamesSha256,
      moduleInventory.expectedScenarioNamesSha256);
    assert(/^[a-f0-9]{64}$/.test(receipt.result.resultSha256));
    assert.strictEqual(receipt.servedResourceClosure.requiredResourceCount, 59);
    assert.strictEqual(receipt.servedResourceClosure.allowedResourceCount, 89);
    assert(receipt.servedResourceClosure.resourceCount >= 59
      && receipt.servedResourceClosure.resourceCount <= 89);
    assert.strictEqual(receipt.servedResourceClosure.failureCount, 4);
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
      scenarioNamesSha256:receipt.result.scenarioNamesSha256,
      resultSha256:receipt.result.resultSha256,
    };
  });
  positive("raw transcript/Host/persistence artifacts are exactly bundle-bound", () => {
    const bundle = Fixture.buildValidBundle();
    const written = writeArtifactFixture(bundle);
    const canonicalRoles = Verifier.artifactRolesForBundle(bundle, true);
    assert.deepStrictEqual(written.roles, canonicalRoles);
    assert.strictEqual(Verifier.verifyTranscriptArtifacts(bundle, written.manifest), true);
    const manifest = Common.buildArtifactManifest({ root: bundle.root, runDir: bundle.runDir,
      runId: bundle.runId, roleByPath: written.roles });
    fs.writeFileSync(path.join(bundle.runDir, "artifact-manifest.json"),
      JSON.stringify(manifest, null, 2) + "\n", "utf8");
    const verified = Common.verifyArtifactManifest({ root: bundle.root, runDir: bundle.runDir,
      manifest });
    assert.ok(verified.size >= written.manifest.size);
    assert.strictEqual(Array.from(verified.values()).filter((entry) =>
      entry.role === "control_request").length, 15);
    assert.strictEqual(Array.from(verified.values()).filter((entry) =>
      entry.role === "control_ack").length, 15);
    assert.strictEqual(Array.from(verified.values()).filter((entry) =>
      entry.role === "provider_receipt").length, 15);
    assert.strictEqual(Array.from(verified.values()).filter((entry) =>
      entry.role === "provider_capture_event").length, 15);
    assert.strictEqual(Array.from(verified.values()).filter((entry) =>
      entry.role === "provider_capture").length, 15);
  });
  positive("current production Web/Host/AS2/data/SWF closure is complete and hashable", () => {
    const fingerprint = SourceContract.captureSourceFingerprint(
      path.resolve(__dirname, "..", "..", ".."));
    assert.strictEqual(SourceContract.validateSourceFingerprint(fingerprint), true);
    const roles = fingerprint.files.reduce((result, entry) => {
      result[entry.role] = (result[entry.role] || 0) + 1;
      return result;
    }, {});
    assert.strictEqual(fingerprint.files.length, 257);
    assert.deepStrictEqual(roles, { page: 1, overlay_startup_web: 18,
      overlay_startup_crafting_web: 1, lazy_registry: 1,
      crafting_lazy_web: 19, organizer_lazy_web: 6,
      overlay_stylesheet: 8, panels_import_stylesheet: 25,
      font_declaration_stylesheet: 1,
      idle_prewarm_image: 15, css_conditional_asset: 6,
      font_pack_manifest: 1, font_catalog_xml: 1,
      font_runtime_projection: 1, permanent_font_asset: 2, icon_manifest: 1,
      host_source: 18, runtime_artifact_source: 1, runtime_input_descriptor: 1,
      runtime_producer_source: 10, runtime_toolchain_lock: 3,
      as2_source: 22, crafting_data: 13, item_projection_data: 79,
      production_swf: 3 });
    const records = SourceContract.REQUIRED_SOURCE_PHASES.map((phase, index) => ({
      phase, observedAt: new Date(Date.parse(fingerprint.capturedAt) + index).toISOString(),
      fingerprint: JSON.parse(JSON.stringify(fingerprint)),
    }));
    assert.ok(SourceContract.assertCurrentSourceClosure(
      path.resolve(__dirname, "..", "..", ".."), SourceContract.sealSourceClosure(records)));
  });
  positive("all 24 AS2 anchors bind exact class/member/modifier/signature/return/body depth", () => {
    assert.deepStrictEqual(As2AnchorTest.run(path.resolve(__dirname, "..", "..", "..")), {
      anchors: 24, baselineAccepted: 24, neutralAccepted: 24,
      variantsPerAnchor: 14, rejected: 336, totalAssertions: 384,
    });
  });
  positive("source closure includes grenade-aware acquisition and all authoritative algorithm owners", () => {
    const fingerprint = SourceContract.captureSourceFingerprint(
      path.resolve(__dirname, "..", "..", ".."));
    const locators = new Set(fingerprint.files.map((entry) => entry.locator));
    assert(locators.has("root:scripts/类定义/org/flashNight/arki/item/ItemUtil.as"));
    assert(locators.has(
      "root:scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as"));
    assert(locators.has("root:scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as"));
    assert(locators.has("root:scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as"));
    assert(locators.has("root:scripts/类定义/org/flashNight/arki/item/BaseItem.as"));
    assert(locators.has("root:scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as"));
    assert(locators.has(
      "root:scripts/类定义/org/flashNight/arki/item/equipment/TierSystem.as"));
    assert(locators.has(
      "root:scripts/类定义/org/flashNight/arki/item/equipment/EquipmentConfigManager.as"));
    assert.strictEqual(fingerprint.as2AlgorithmContract.functions.length,
      SourceContract.AS2_ALGORITHM_EXPECTATIONS.length);
    assert.strictEqual(fingerprint.as2AlgorithmContract.schema,
      "workbench-live-e2e.crafting.as2-algorithm-contract.v4");
    const itemRequire = fingerprint.as2AlgorithmContract.functions.find((entry) =>
      entry.className === "org.flashNight.arki.item.ItemUtil"
        && entry.functionName === "require");
    const itemAcquire = fingerprint.as2AlgorithmContract.functions.find((entry) =>
      entry.className === "org.flashNight.arki.item.ItemUtil"
        && entry.functionName === "acquire");
    assert.deepStrictEqual({
      bodyTokenCount: itemRequire && itemRequire.bodyTokenCount,
      bodyTokenSha256: itemRequire && itemRequire.bodyTokenSha256,
      tokenCount: itemRequire && itemRequire.tokenCount,
      normalizedTokenSha256: itemRequire && itemRequire.normalizedTokenSha256,
    }, {
      bodyTokenCount: 1055,
      bodyTokenSha256: "9b3fba89be011711c8a80481cf1daf45b27d778f53b48487cf15734148f0313a",
      tokenCount: 1066,
      normalizedTokenSha256: "be49a9398ce96a0910e69a88de4b8e552d1d068571e94ee84b31ded0133f87f4",
    });
    assert.deepStrictEqual({
      bodyTokenCount: itemAcquire && itemAcquire.bodyTokenCount,
      bodyTokenSha256: itemAcquire && itemAcquire.bodyTokenSha256,
      tokenCount: itemAcquire && itemAcquire.tokenCount,
      normalizedTokenSha256: itemAcquire && itemAcquire.normalizedTokenSha256,
    }, {
      bodyTokenCount: 830,
      bodyTokenSha256: "2ddfd3de815af09e1c2b4262ef9e9ffab05db90f2726fa7b33c7b5023fd71e21",
      tokenCount: 841,
      normalizedTokenSha256: "400fd377f6a8545ef346c94d4e3e1bdf921ecfa50e3cc87e33ed0339276e2bbe",
    });
  });
  positive("late observer listener permits child send before parent response without inventing order", () => {
    const bundle = Fixture.buildValidBundle();
    const events = bundle.transcripts.first.events;
    const organizer = events.find((event) => event.kind === "dom_input"
      && event.target && /crafting-organizer-btn/.test(String(
        event.target.attributes && event.target.attributes.class || "")));
    const parentRequest = events.find((event) => event.sequence > organizer.sequence
      && event.kind === "bridge_send" && event.message
      && event.message.domain === "crafting" && event.message.cmd === "snapshot");
    const parentResponseIndex = events.findIndex((event) => event.kind === "webview_message"
      && event.message && event.message.callId === parentRequest.message.callId);
    const childRequestIndex = events.findIndex((event) => event.sequence > parentRequest.sequence
      && event.kind === "bridge_send" && event.message
      && event.message.domain === "inventory");
    const parentResponse = events.splice(parentResponseIndex, 1)[0];
    const adjustedChildIndex = events.indexOf(events.find((event) => event.kind === "bridge_send"
      && event.message && event.message.callId === parentRequest.message.callId)) < childRequestIndex
      ? childRequestIndex - 1 : childRequestIndex;
    events.splice(adjustedChildIndex + 1, 0, parentResponse);
    resealTranscript(bundle.transcripts.first);
    rebindFixtureProviderDomInputs(bundle);
    const result = semantic(bundle);
    assert.strictEqual(result.first.inventory.afterCount - result.first.inventory.beforeCount, 1);
  });
  positive("precommit gate proves the same 90-slot plan before commit control is reachable", () => {
    const bundle = Fixture.buildValidBundle();
    const prefix = preCommitPrefix(bundle.transcripts.first);
    const selector = { category: Fixture.CATEGORY, recipeIndex: Fixture.RECIPE_INDEX,
      craftCount: Fixture.CRAFT_COUNT };
    const admission = Protocol.verifyPreCommitAuthority(prefix, selector);
    assert.deepStrictEqual(admission.plan.delivery,
      { containerId: "背包", storageKind: "bag", available: true,
        physicalSlot: 0, mode: "merge", quantity: 1 });
    assert.strictEqual(prefix.events.some((event) => event.kind === "bridge_send"
      && event.message && event.message.cmd === "commit"), false);
    assert.strictEqual(prefix.events.some((event) => event.kind === "dom_input"
      && event.target && event.target.mutationCapable === true
      && event.target.attributes && Object.prototype.hasOwnProperty.call(
        event.target.attributes, "data-commit-primary")), false);
    const runner = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
    const gateAt = runner.indexOf("Protocol.verifyPreCommitAuthority(preCommitTranscript, selected)");
    const authorizationAt = runner.indexOf("authorization(args, selected)", gateAt);
    const riskAt = runner.indexOf("commitMayHaveReachedAuthority = true", gateAt);
    const controlAt = runner.indexOf("controlStep(state, \"commit_recipe\"", gateAt);
    assert(gateAt >= 0 && gateAt < authorizationAt && authorizationAt < riskAt && riskAt < controlAt);
  });
  positive("equipment output is inserted from a frozen full prototype and exact commit receipt", () => {
    const bundle = Fixture.buildValidBundle();
    const contract = convertFirstTranscriptToEquipmentInsert(bundle);
    const result = Protocol.verifyFirstTranscript(bundle.transcripts.first);
    assert.deepStrictEqual(result.inventory.delivery,
      { containerId: "背包", physicalSlot: 3, mode: "insert", quantity: 1 });
    assert.deepStrictEqual(result.commit.acceptedPlan.outputPrototype, contract.prototype);
    assert.deepStrictEqual(result.commit.outputReceipt, contract.receipt);
    assert.strictEqual(result.inventory.beforeCount, 0);
    assert.strictEqual(result.inventory.afterCount, 1);
  });
  negativeDirect("unobserved material route fails closed before commit input or control",
    "inventory_material_route_unobserved", () => {
      const bundle = Fixture.buildValidBundle();
      const prefix = preCommitPrefix(bundle.transcripts.first);
      const previews = prefix.events.filter((event) => event.kind === "webview_message"
        && event.message && event.message.domain === "crafting" && event.message.cmd === "preview");
      const accepted = previews[previews.length - 1].message;
      accepted.materials[0].storageKind = "material_collection";
      accepted.acceptedPlan.materials[0].storageKind = "material_collection";
      resealTranscript(prefix);
      const issuedControls = [];
      try {
        Protocol.verifyPreCommitAuthority(prefix, {
          category: Fixture.CATEGORY, recipeIndex: Fixture.RECIPE_INDEX,
          craftCount: Fixture.CRAFT_COUNT,
        });
        issuedControls.push("commit_recipe");
      } finally {
        assert.deepStrictEqual(issuedControls, []);
        assert.strictEqual(prefix.events.some((event) => event.message
          && event.message.cmd === "commit"), false);
      }
    });

  negative("production category set rejects invented category", "production_open_invalid", (b) => {
    const open = b.transcripts.first.events.find((e) => e.kind === "webview_message"
      && e.message && e.message.type === "panel_cmd");
    open.message.initData.category = "防具合成";
    resealTranscript(b.transcripts.first);
  });
  negative("response extra field is rejected", "preview_response_keys_invalid", (b) => {
    const response = b.transcripts.first.events.find((e) => e.kind === "webview_message"
      && e.message && e.message.domain === "crafting" && e.message.cmd === "preview");
    response.message.extra = true;
    resealTranscript(b.transcripts.first);
  });
  negative("material route is required in the authoritative projection",
    "material_projection_keys_invalid", (b) => {
      const response = b.transcripts.first.events.find((e) => e.kind === "webview_message"
        && e.message && e.message.domain === "crafting" && e.message.cmd === "preview");
      delete response.message.materials[0].storageKind;
      resealTranscript(b.transcripts.first);
    });
  negative("output delivery is required before commit", "preview_response_keys_invalid", (b) => {
    const response = b.transcripts.first.events.find((e) => e.kind === "webview_message"
      && e.message && e.message.domain === "crafting" && e.message.cmd === "preview");
    delete response.message.outputDelivery;
    resealTranscript(b.transcripts.first);
  });
  negative("accepted plan cannot differ from projected material routes",
    "accepted_plan_projection_mismatch", (b) => {
      const response = b.transcripts.first.events.find((e) => e.kind === "webview_message"
        && e.message && e.message.domain === "crafting" && e.message.cmd === "preview");
      response.message.acceptedPlan.materials[0].storageKind = "material_collection";
      resealTranscript(b.transcripts.first);
    });
  negative("commit must echo the exact accepted plan", "commit_accepted_plan_mismatch", (b) => {
    const response = b.transcripts.first.events.find((e) => e.kind === "webview_message"
      && e.message && e.message.domain === "crafting" && e.message.cmd === "commit");
    response.message.acceptedPlan.cost.money += 1;
    resealTranscript(b.transcripts.first);
  });
  negative("commit receipt rarity cannot drift behind matching Inventory readback",
    "output_receipt_projection_mismatch", (b) => {
      mutateReceiptAndReadback(b, (receipt, slot) => {
        receipt.item.rarity = "drifted";
        receipt.confirmProjection.rarity = "drifted";
        slot.item.rarity = "drifted";
        slot.confirmProjection.rarity = "drifted";
      });
    });
  negative("commit receipt enhancement ceiling cannot drift behind matching Inventory readback",
    "output_receipt_projection_mismatch", (b) => {
      mutateReceiptAndReadback(b, (receipt, slot) => {
        receipt.item.maxEnhancementLevel = 1;
        slot.item.maxEnhancementLevel = 1;
      });
    });
  negative("commit receipt loose-plugin metadata cannot appear behind matching Inventory readback",
    "output_receipt_projection_mismatch", (b) => {
      const modMeta = { name: "fixture.mod.internal", displayName: "验证插件",
        icon: "强化石", grade: "basic", gradeLabel: "基础", gradeColor: "#ffffff",
        role: "utility", roleLabel: "通用", symbol: "◇", scope: "all" };
      mutateReceiptAndReadback(b, (receipt, slot) => {
        receipt.item.modMeta = Common.deepClone(modMeta);
        slot.item.modMeta = Common.deepClone(modMeta);
      });
    });
  negative("commit receipt modifier signature cannot drift behind matching Inventory readback",
    "output_receipt_projection_mismatch", (b) => {
      mutateReceiptAndReadback(b, (receipt, slot) => {
        receipt.confirmProjection.modSignature = "12:fixture.mod;";
        slot.confirmProjection.modSignature = "12:fixture.mod;";
      });
    });
  negative("commit receipt cannot add an optional balance projection absent from preview",
    "output_receipt_projection_mismatch", (b) => {
      const balance = { state: "confirmed", weightLayers: 1, formula: 1, level: 1 };
      mutateReceiptAndReadback(b, (receipt, slot) => {
        receipt.item.balanceSummary = Common.deepClone(balance);
        slot.item.balanceSummary = Common.deepClone(balance);
      });
    });
  negative("commit receipt balance values must equal the frozen optional preview projection",
    "output_receipt_projection_mismatch", (b) => {
      const previewBalance = { state: "confirmed", weightLayers: 1, formula: 1, level: 1 };
      b.transcripts.first.events.forEach((event) => {
        const message = event.message;
        if (!message || message.domain !== "crafting" || message.type !== "panel_resp") return;
        if ((message.cmd === "preview" || message.cmd === "commit")
            && message.acceptedPlan) {
          message.acceptedPlan.outputPrototype.item.balanceSummary =
            Common.deepClone(previewBalance);
        }
      });
      mutateReceiptAndReadback(b, (receipt, slot) => {
        const drift = { state: "confirmed", weightLayers: 2, formula: 1, level: 1 };
        receipt.item.balanceSummary = Common.deepClone(drift);
        slot.item.balanceSummary = Common.deepClone(drift);
      });
    });
  negative("transaction field overclaim is rejected", "commit_response_keys_invalid", (b) => {
    const response = b.transcripts.first.events.find((e) => e.kind === "webview_message"
      && e.message && e.message.domain === "crafting" && e.message.cmd === "commit");
    response.message.transactionIdRef = "sha256_0123456789abcdef01234567";
    resealTranscript(b.transcripts.first);
  });
  negative("observer cannot self-report PanelRequestMux ordering", "observer_order_claim_forbidden", (b) => {
    const request = b.transcripts.first.events.find((e) => e.kind === "bridge_send");
    request.sendOrder = "after_panel_request_mux_onIssued";
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory pre-read cannot disappear", "inventory_command_order_invalid", (b) => {
    const index = b.transcripts.first.events.findIndex((e) => e.kind === "bridge_send"
      && e.message && e.message.domain === "inventory");
    const callId = b.transcripts.first.events[index].message.callId;
    b.transcripts.first.events = b.transcripts.first.events.filter((e) =>
      !(e.message && e.message.callId === callId));
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory request exact field set rejects extras", "inventory_window_keys_invalid", (b) => {
    const request = b.transcripts.first.events.find((e) => e.kind === "bridge_send"
      && e.message && e.message.domain === "inventory");
    request.message.payload.requests[0].extra = true;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory request preserves bag then battlebox order", "inventory_window_invalid", (b) => {
    const request = b.transcripts.first.events.find((e) => e.kind === "bridge_send"
      && e.message && e.message.domain === "inventory");
    request.message.payload.requests.reverse();
    resealTranscript(b.transcripts.first);
  });
  negative("battlebox exposes production capacity rather than a 40-slot fake container",
    "inventory_snapshot_invalid", (b) => {
      inventoryResponses(b.transcripts.first)[0].message.snapshots[1].capacity = 40;
      resealTranscript(b.transcripts.first);
    });
  negative("Inventory output delta must equal crafted quantity", "inventory_output_delta_mismatch", (b) => {
    const responses = inventoryResponses(b.transcripts.first);
    setInventoryQuantity(responses[1], 4);
    resealTranscript(b.transcripts.first);
  });
  negative("restart Inventory readback must match poststate", "inventory_restart_count_mismatch", (b) => {
    const response = inventoryResponses(b.transcripts.restart)[0];
    setInventoryQuantity(response, 4);
    resealTranscript(b.transcripts.restart);
  });
  negative("after and restart cannot consistently add one unrelated bag item",
    "inventory_slot_delta_mismatch", (b) => {
      [inventoryResponses(b.transcripts.first)[1], inventoryResponses(b.transcripts.restart)[0]]
        .forEach((response) => {
          const bag = response.message.snapshots[0];
          const source = Common.deepClone(bag.slots[2]);
          const targetLease = bag.slots[3].slotLeaseRef;
          source.physicalSlot = 3;
          source.slotLeaseRef = targetLease;
          bag.slots[3] = source;
          bag.filterItemCount = 4;
          bag.filterFacets[0].count = 4;
        });
      resealTranscript(b.transcripts.first);
      resealTranscript(b.transcripts.restart);
    });
  negative("Crafting cannot mutate any observed battlebox slot",
    "inventory_battlebox_mutation_forbidden", (b) => {
      const response = inventoryResponses(b.transcripts.first)[1];
      const bagSource = Common.deepClone(response.message.snapshots[0].slots[2]);
      const battle = response.message.snapshots[1];
      bagSource.physicalSlot = 0;
      bagSource.slotLeaseRef = battle.slots[0].slotLeaseRef;
      battle.slots[0] = bagSource;
      battle.filterItemCount = 1;
      battle.filterFacets = [{ id: "all", label: "全部", order: 0, count: 1, children: [] }];
      resealTranscript(b.transcripts.first);
    });
  negative("physical stack material is consumed from the lowest matching slot",
    "inventory_slot_delta_mismatch", (b) => {
      const responses = inventoryResponses(b.transcripts.first);
      const before = responses[0].message.snapshots[0];
      const after = responses[1].message.snapshots[0];
      const beforeExtra = Common.deepClone(before.slots[1]);
      before.slots[1].item.quantity = 3;
      before.slots[1].confirmProjection.quantity = 3;
      beforeExtra.physicalSlot = 3;
      beforeExtra.slotLeaseRef = before.slots[3].slotLeaseRef;
      beforeExtra.item.quantity = 2;
      beforeExtra.confirmProjection.quantity = 2;
      before.slots[3] = beforeExtra;
      before.filterItemCount = 4;
      before.filterFacets[0].count = 4;
      after.slots[1].item.quantity = 3;
      after.slots[1].confirmProjection.quantity = 3;
      resealTranscript(b.transcripts.first);
    });
  negative("crafted stack merges into the lowest same-name bag slot",
    "inventory_output_delivery_invalid", (b) => {
      const responses = inventoryResponses(b.transcripts.first);
      const before = responses[0].message.snapshots[0];
      const after = responses[1].message.snapshots[0];
      const beforeExtra = Common.deepClone(before.slots[0]);
      beforeExtra.physicalSlot = 3;
      beforeExtra.slotLeaseRef = before.slots[3].slotLeaseRef;
      beforeExtra.item.quantity = 4;
      beforeExtra.confirmProjection.quantity = 4;
      beforeExtra.confirmProjection.lastUpdate = 900;
      before.slots[3] = beforeExtra;
      before.filterItemCount = 4;
      before.filterFacets[0].count = 4;
      after.slots[0].item.quantity = 2;
      after.slots[0].confirmProjection.quantity = 2;
      after.slots[0].confirmProjection.lastUpdate = 1000;
      const afterExtra = Common.deepClone(beforeExtra);
      afterExtra.slotLeaseRef = after.slots[3].slotLeaseRef;
      afterExtra.item.quantity = 5;
      afterExtra.confirmProjection.quantity = 5;
      afterExtra.confirmProjection.lastUpdate = 2000;
      after.slots[3] = afterExtra;
      after.filterItemCount = 4;
      after.filterFacets[0].count = 4;
      resealTranscript(b.transcripts.first);
    });
  negative("accepted preview token cannot drift", "craft_token_lifecycle_invalid", (b) => {
    const commit = b.transcripts.first.events.find((e) => e.kind === "bridge_send"
      && e.message && e.message.domain === "crafting" && e.message.cmd === "commit");
    commit.message.payload.expectedCraftTokenRef = "sha256_0123456789abcdef01234567";
    resealTranscript(b.transcripts.first);
  });
  negative("commit click must remain trusted", "trusted_input_set_invalid", (b) => {
    const click = b.transcripts.first.events.find((e) => e.kind === "dom_input"
      && e.target && e.target.mutationCapable === true
      && e.target.attributes && Object.prototype.hasOwnProperty.call(
        e.target.attributes, "data-commit-primary"));
    click.isTrusted = false;
    resealTranscript(b.transcripts.first);
  });
  negative("Host call-bound receipt cannot disappear", "host_dispatch_receipt_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const index = log.records.findIndex((r) => r.line.includes(
      "event=authority_flash_call_bound domain=crafting"));
    log.records.splice(index, 1);
    resealLog(log);
  });
  negative("Host authority field set rejects transaction extras", "host_authority_field_set_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const record = log.records.find((r) => r.line.includes("task=crafting_response")
      && r.line.includes("craftTokenRef="));
    record.line += " transactionIdRef=sha256_0123456789abcdef01234567";
    resealLog(log);
  });
  negative("Host Inventory same-fid response cannot drift", "host_flash_roundtrip_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const record = log.records.find((r) => r.line.includes("task=inventory_response"));
    record.line = record.line.replace(/callId=\d+/, "callId=999");
    resealLog(log);
  });
  negative("control exchange set cannot omit Inventory step", "control_set_count_invalid", (b) => {
    const request = b.control.requests.find((entry) => entry.step === "capture_inventory_after");
    b.control.requests = b.control.requests.filter((entry) => entry !== request);
    b.control.acks = b.control.acks.filter((entry) => entry.requestId !== request.requestId);
  });
  negative("stored precommit admission cannot drift from the same 90-slot planner",
    "precommit_admission_evidence_invalid", (b) => {
      b.control.preCommitAdmission.delivery.physicalSlot += 1;
    });
  negative("restart lifecycle cannot reinterpret snapshot as commit", "commit_token_reference_invalid", (b) => {
    const event = b.transcripts.restart.events.find((e) => e.kind === "bridge_send"
      && e.message && e.message.domain === "crafting" && e.message.cmd === "snapshot");
    event.message.cmd = "commit";
    resealTranscript(b.transcripts.restart);
  });

  negative("current-tree source phase cannot drift", "source_closure_invalid", (b) => {
    b.sourceClosure.records[b.sourceClosure.records.length - 1]
      .fingerprint.files[0].sha256 = "e".repeat(64);
    resealSourceClosure(b.sourceClosure);
  });
  negative("fixed AS2 algorithm digest cannot be replaced by runtime-derived evidence",
    "source_closure_invalid", (b) => {
      b.sourceClosure.records.forEach((record) => {
        record.fingerprint.as2AlgorithmContract.functions[0].normalizedTokenSha256 = "0".repeat(64);
      });
      resealSourceClosure(b.sourceClosure);
    });
  {
    const name = "sealed source closure must still equal current production bytes";
    const bundle = Fixture.buildValidBundle();
    bundle.sourceClosure.records.forEach((record) => {
      record.fingerprint.files[0].sha256 = "e".repeat(64);
    });
    resealSourceClosure(bundle.sourceClosure);
    assert.throws(() => SourceContract.assertCurrentSourceClosure(
      path.resolve(__dirname, "..", "..", ".."), bundle.sourceClosure),
    (error) => error && ["source_fingerprint_drift", "source_closure_invalid"].includes(error.code));
    negatives.push(name);
  }
  negative("Crafting nested projected output rejects extras", "projected_item_keys_invalid", (b) => {
    const response = b.transcripts.first.events.find((event) => event.kind === "webview_message"
      && event.message && event.message.domain === "crafting" && event.message.cmd === "preview");
    response.message.output.forged = true;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory nested snapshot rejects extras", "inventory_snapshot_invalid", (b) => {
    inventoryResponses(b.transcripts.first)[0].message.snapshots[0].forgedSnapshot = true;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory nested slot rejects extras", "inventory_snapshot_invalid", (b) => {
    inventoryResponses(b.transcripts.first)[0].message.snapshots[0].slots[0].forgedSlot = true;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory nested item rejects extras", "inventory_snapshot_invalid", (b) => {
    inventoryResponses(b.transcripts.first)[0].message.snapshots[0].slots[0].item.forgedItem = true;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory nonce cannot drift within first process", "inventory_session_nonce_drift", (b) => {
    inventoryResponses(b.transcripts.first)[1].message.sessionNonce = "fixture-session-drift";
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory nonce must be fresh after restart", "inventory_restart_nonce_reused", (b) => {
    inventoryResponses(b.transcripts.restart)[0].message.sessionNonce =
      inventoryResponses(b.transcripts.first)[0].message.sessionNonce;
    resealTranscript(b.transcripts.restart);
  });
  negative("close Bridge.send cannot be omitted", "close_send_count_invalid", (b) => {
    b.transcripts.first.events = b.transcripts.first.events.filter((event) =>
      !(event.kind === "bridge_send" && event.message
        && event.message.type === "panel" && event.message.cmd === "close"));
    resealTranscript(b.transcripts.first);
  });
  negative("close Bridge.send cannot be duplicated", "close_send_count_invalid", (b) => {
    const events = b.transcripts.first.events;
    const close = events.find((event) => event.kind === "bridge_send"
      && event.message && event.message.type === "panel" && event.message.cmd === "close");
    events.splice(events.indexOf(close), 0, JSON.parse(JSON.stringify(close)));
    resealTranscript(b.transcripts.first);
  });
  negative("page-authored issued diagnostic cannot replace observation", "observer_issued_diagnostic_forbidden", (b) => {
    const closeIndex = b.transcripts.first.events.findIndex((event) => event.kind === "bridge_send"
      && event.message && event.message.cmd === "close");
    b.transcripts.first.events.splice(closeIndex, 0, {
      kind: "bridge_send", message: { type: "debug", scope: "crafting",
        event: "preview_issued", webCallId: "forged" }, panelState: {
        panel: "crafting", hidden: false, craftingVisible: true, view: "recipes",
      }, pageTime: 1000,
    });
    resealTranscript(b.transcripts.first);
  });
  negative("extra trusted click is outside the exact input grammar", "trusted_input_set_invalid", (b) => {
    const events = b.transcripts.first.events;
    const recipe = events.find((event) => event.kind === "dom_input"
      && event.target && event.target.attributes
      && event.target.attributes["data-workbench-key"] === String(Fixture.RECIPE_INDEX));
    const closeIndex = events.findIndex((event) => event.kind === "dom_input"
      && event.target && event.target.attributes
      && event.target.attributes["data-header-action"] === "close");
    events.splice(closeIndex, 0, JSON.parse(JSON.stringify(recipe)));
    resealTranscript(b.transcripts.first);
  });
  negative("extra trusted keydown is outside the exact input grammar", "trusted_input_set_invalid", (b) => {
    const events = b.transcripts.first.events;
    const recipe = JSON.parse(JSON.stringify(events.find((event) => event.kind === "dom_input"
      && event.target && event.target.attributes
      && event.target.attributes["data-workbench-key"] === String(Fixture.RECIPE_INDEX))));
    recipe.eventType = "keydown";
    recipe.key = "Enter";
    recipe.repeat = false;
    delete recipe.button;
    const closeIndex = events.findIndex((event) => event.kind === "dom_input"
      && event.target && event.target.attributes
      && event.target.attributes["data-header-action"] === "close");
    events.splice(closeIndex, 0, recipe);
    resealTranscript(b.transcripts.first);
  });
  negative("trusted input without a target cannot evade the exact grammar", "trusted_input_set_invalid", (b) => {
    const events = b.transcripts.first.events;
    const event = {
      kind: "dom_input", eventType: "click", isTrusted: true, button: 0,
      panelState: { panel: "crafting", hidden: false, craftingVisible: true, view: "recipes" },
      pageTime: 1000,
    };
    const closeIndex = events.findIndex((entry) => entry.kind === "dom_input"
      && entry.target && entry.target.attributes
      && entry.target.attributes["data-header-action"] === "close");
    events.splice(closeIndex, 0, event);
    resealTranscript(b.transcripts.first);
  });
  negative("organizer input must cause the pre-organizer request boundary", "trusted_input_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    const organizer = events.find((event) => event.kind === "dom_input"
      && event.target && /crafting-organizer-btn/.test(String(
        event.target.attributes && event.target.attributes.class || "")));
    events.splice(events.indexOf(organizer), 1);
    const inventoryResponse = events.find((event) => event.kind === "webview_message"
      && event.message && event.message.domain === "inventory");
    events.splice(events.indexOf(inventoryResponse) + 1, 0, organizer);
    resealTranscript(b.transcripts.first);
  });
  negative("close send must follow the trusted close input", "trusted_input_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    const send = events.find((event) => event.kind === "bridge_send"
      && event.message && event.message.cmd === "close");
    const click = events.find((event) => event.kind === "dom_input"
      && event.target && event.target.attributes
      && event.target.attributes["data-header-action"] === "close");
    events.splice(events.indexOf(send), 1);
    events.splice(events.indexOf(click), 0, send);
    resealTranscript(b.transcripts.first);
  });
  negative("post-close hidden sample cannot disappear", "close_hidden_state_invalid", (b) => {
    b.transcripts.first.events = b.transcripts.first.events.filter((event) =>
      event.kind !== "panel_state_sample");
    resealTranscript(b.transcripts.first);
  });
  negative("post-close sample must prove the panel is hidden", "close_hidden_state_invalid", (b) => {
    const sample = b.transcripts.first.events.find((event) => event.kind === "panel_state_sample");
    sample.panelState = { panel: "crafting", hidden: false, craftingVisible: true, view: "recipes" };
    resealTranscript(b.transcripts.first);
  });
  negative("Host response-family near-match is relevant and fatal", "host_socket_near_match_forbidden", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    log.records.push({ lineNumber: log.records.length + 1,
      line: "08:13:30.000 [XmlSocket:JSON] task=authority_response_family envelope=near_match payload=redacted len=91" });
    resealLog(log);
  });
  negative("Host close record cannot disappear", "host_close_count_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    log.records = log.records.filter((record) => !record.line.includes(
      "panel=crafting domain=other cmd=close callId=other"));
    resealLog(log);
  });
  negative("Host close record cannot be duplicated", "host_close_count_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const close = log.records.find((record) => record.line.includes(
      "panel=crafting domain=other cmd=close callId=other"));
    log.records.push({ lineNumber: log.records.length + 1,
      line: close.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:13:30.000") });
    resealLog(log);
  });
  negative("disk/archive bytes must equal artifact JSON bytes", "persistence_disk_artifact_mismatch", (b) => {
    [b.persistence.diskAfterCommit, b.persistence.diskAfterRestart,
      b.persistence.archiveEvidence.disk].forEach((disk) => {
      disk.sha256 = "d".repeat(64);
      disk.bytes = 2222;
    });
    resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
  });

  negative("Crafting cannot manually flip Agent Runtime capability positive",
    "launcher_process_contract_invalid", (b) => {
      b.runtime.first.processContract.agentRuntimeAdmission = true;
      b.runtime.first.processContract.legacyHttpAutomationArg = false;
      resealDigest(b.runtime.first.processContract, "artifactSha256");
    });
  positive("canonical bootstrap rejects mixed and incomplete control modes with exit 2", () => {
    [["--check", "--candidate-root", "C:\\foreign"], ["--verify-bundle"],
      ["--check", "--help"], ["--unknown"], []].forEach((args) => {
      const result = childProcess.spawnSync(process.execPath,
        [require.resolve("./bootstrap")].concat(args), { encoding: "utf8", windowsHide: true });
      assert.strictEqual(result.status, 2, result.stderr || result.stdout);
      assert.strictEqual(result.stdout, "", "rejected arguments must not run or print the suite");
      assert.doesNotMatch(result.stderr, /OFFLINE_VERIFIED|positives|negatives/);
    });
  });

  negative("source closure root cannot be foreign", "source_closure_invalid", (b) => {
    b.sourceClosure.root = "C:\\foreign-root";
    b.sourceClosure.records.forEach((record) => {
      record.fingerprint.root = "C:\\foreign-root";
    });
    resealSourceClosure(b.sourceClosure);
  });
  negative("source binding cannot cross run id", "source_binding_invalid", (b) => {
    b.sourceBinding.runId = "foreign-run";
    resealDigest(b.sourceBinding, "bindingSha256");
  });
  negative("source binding cannot cross candidate root", "source_binding_invalid", (b) => {
    b.sourceBinding.candidateRoot = "C:\\foreign-candidate";
    resealDigest(b.sourceBinding, "bindingSha256");
  });
  negative("first lifecycle must provide actual loaded Web bytes", "loaded_production_invalid", (b) => {
    delete b.runtime.first.loadedProduction;
  });
  negative("loaded Web multiset cannot omit a lazy module", "loaded_production_url_multiset_invalid", (b) => {
    b.runtime.first.loadedProduction.scripts.pop();
    resealDigest(b.runtime.first.loadedProduction, "evidenceSha256");
  });
  negative("loaded Web multiset cannot duplicate a module", "loaded_production_url_multiset_invalid", (b) => {
    b.runtime.first.loadedProduction.scripts.push(
      JSON.parse(JSON.stringify(b.runtime.first.loadedProduction.scripts[0])));
    resealDigest(b.runtime.first.loadedProduction, "evidenceSha256");
  });
  negative("loaded Web bytes must equal current source", "loaded_production_resource_invalid", (b) => {
    b.runtime.restart.loadedProduction.scripts[0].sha256 = "e".repeat(64);
    resealDigest(b.runtime.restart.loadedProduction, "evidenceSha256");
  });
  negative("loaded Web source method must be exact", "loaded_production_resource_invalid", (b) => {
    b.runtime.first.loadedProduction.scripts[0].sourceMethod = "Page.getResourceContent";
    resealDigest(b.runtime.first.loadedProduction, "evidenceSha256");
  });

  negative("Host exact close completion cannot disappear", "host_close_order_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    log.records = log.records.filter((record) =>
      !record.line.includes("event=panel_exact_close_completed"));
    resealLog(log);
  });
  negative("Host exact close completion cannot duplicate", "host_close_order_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const record = log.records.find((entry) => entry.line.includes("event=panel_exact_close_completed"));
    log.records.push({ lineNumber: log.records.length + 1,
      line: record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:13:30.000") });
    resealLog(log);
  });
  negative("Host exact close completion owner must match", "host_close_order_invalid", (b) => {
    const log = b.runtime.restart.finalLogSnapshot;
    const record = log.records.find((entry) => entry.line.includes("event=panel_exact_close_completed"));
    record.line = record.line.replace(/panelInstanceId=\S+/, "panelInstanceId=foreign-owner");
    resealLog(log);
  });
  negative("Host close completion must follow incoming close", "host_close_order_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const index = log.records.findIndex((entry) => entry.line.includes("event=panel_exact_close_completed"));
    const completion = log.records.splice(index, 1)[0];
    completion.line = completion.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:09:16.000");
    const incoming = log.records.findIndex((entry) => entry.line.includes("cmd=close callId=other"));
    log.records.splice(incoming, 0, completion);
    resealLog(log);
  });
  negative("extra relevant Host route is rejected", "host_command_multiset_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const route = log.records.find((entry) => entry.line.includes("[Panel] Routing domain=crafting"));
    log.records.push({
      lineNumber: log.records.length + 1,
      line: route.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:13:30.000"),
    });
    resealLog(log);
  });
  negative("rejected race Host record is not ignorable", "host_relevant_record_unclassified", (b) => {
    const log = b.runtime.restart.finalLogSnapshot;
    log.records.push({ lineNumber: log.records.length + 1,
      line: "08:22:36.000 [CraftingTask] rejected expired foreign owner race" });
    resealLog(log);
  });
  negative("deferred Host record is not ignorable", "host_relevant_record_unclassified", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    log.records.push({ lineNumber: log.records.length + 1,
      line: "08:13:30.000 [InventoryTask] deferred request race" });
    resealLog(log);
  });
  negative("near-match Host route is rejected", "host_route_summary_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    log.records.push({ lineNumber: log.records.length + 1,
      line: "08:13:30.000 [Panel] Routing domain=crafting cmd=preview to CraftingTask, _craftingTask=deferred" });
    resealLog(log);
  });

  negative("legacy Crafting argv cannot claim Agent Runtime availability", "launcher_process_contract_invalid", (b) => {
    b.runtime.first.processContract.agentRuntimeAdmission = true;
    b.runtime.first.processContract.legacyHttpAutomationArg = false;
    resealDigest(b.runtime.first.processContract, "artifactSha256");
  });
  negative("control request array order is closed", "control_partial_order_invalid", (b) => {
    b.control.requests.reverse();
    b.control.acks.reverse();
  });
  negative("control ack chronology is closed", "control_partial_order_invalid", (b) => {
    b.control.acks[0].completedAt = "2026-08-03T00:02:15.000Z";
  });
  negative("control selector is exact", "control_request_scope_invalid", (b) => {
    b.control.requests[1].selectors = [".forged-selector"];
  });
  negative("control instruction is exact", "control_request_scope_invalid", (b) => {
    b.control.requests[1].instructions += " retry";
  });
  negative("control independent evidence is exact", "control_request_scope_invalid", (b) => {
    b.control.requests[1].expectedIndependentEvidence.push("operator says pass");
  });
  negative("PNG magic bytes alone are not a decodable capture", "control_capture_media_invalid", (b) => {
    const bytes = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    overwriteCapture(b, "safe_exit", bytes);
  });
  negative("PNG trailing bytes are rejected", "control_capture_media_invalid", (b) => {
    const request = b.control.requests.find((entry) => entry.step === "safe_exit");
    const ack = b.control.acks.find((entry) => entry.requestId === request.requestId);
    const original = fs.readFileSync(path.join(b.runDir,
      ack.capture.relativePath.replace(/\//g, path.sep)));
    const bytes = Buffer.concat([original, Buffer.from([0])]);
    overwriteCapture(b, "safe_exit", bytes);
  });

  negative("exact close must precede sv1 on the same Host line axis", "global_partial_order_invalid", (b) => {
    const closeLine = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("event=panel_exact_close_completed")).lineNumber;
    b.persistence.archiveEvidence.positions.sv1.lineNumber = closeLine;
    resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
  });
  negative("terminal first loaded production bytes must follow archive disk capture",
    "global_partial_order_invalid", (b) => {
      b.runtime.first.loadedProduction.capturedAt = "2026-08-03T00:14:40.000Z";
      resealDigest(b.runtime.first.loadedProduction, "evidenceSha256");
  });
  negative("exact close completion must precede SAFEEXIT provider action",
    "global_partial_order_invalid", (b) => {
      const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
        entry.line.includes("event=panel_exact_close_completed"));
      record.line = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:10:30.000");
      resealLog(b.runtime.first.finalLogSnapshot);
      b.persistence.archiveEvidence.finalSnapshotSha256 = b.runtime.first.finalLogSnapshot.tailSha256;
      resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
    });
  negative("SAFEEXIT native input must strictly precede sv1",
    "global_partial_order_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("[Save] sv:1"));
    record.line = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:10:10.000");
    resealLog(b.runtime.first.finalLogSnapshot);
    b.persistence.archiveEvidence.finalSnapshotSha256 = b.runtime.first.finalLogSnapshot.tailSha256;
    resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
  });
  negative("archive capture must precede EXIT_CONFIRM", "global_partial_order_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("[Save] archive"));
    record.line = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:16:45.000");
    b.runtime.first.finalLogSnapshot.capturedAt = "2026-08-03T00:17:00.000Z";
    resealLog(b.runtime.first.finalLogSnapshot);
    b.persistence.archiveEvidence.finalSnapshotSha256 = b.runtime.first.finalLogSnapshot.tailSha256;
    resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
  });
  negative("sv1 and sv2 Host timestamps must be strictly ordered", "global_partial_order_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("[Save] sv:2"));
    record.line = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, "08:11:00.000");
    resealLog(b.runtime.first.finalLogSnapshot);
    b.persistence.archiveEvidence.finalSnapshotSha256 = b.runtime.first.finalLogSnapshot.tailSha256;
    resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
  });
  negative("terminal restart loaded bytes must follow restart close ack",
    "global_partial_order_invalid", (b) => {
    b.runtime.restart.loadedProduction.capturedAt = "2026-08-03T00:22:40.000Z";
    resealDigest(b.runtime.restart.loadedProduction, "evidenceSha256");
  });
  negative("restart close must precede authenticated final residue", "global_partial_order_invalid", (b) => {
    b.residue.final.observedAt = "2026-08-03T00:22:00.000Z";
    resealDigest(b.residue.final, "evidenceSha256");
  });
  negative("authenticated restart shutdown evidence cannot disappear", "authenticated_shutdown_invalid", (b) => {
    delete b.runtime.restart.shutdownEvidence;
  });
  negative("authenticated restart shutdown must succeed", "launcher_task_failed", (b) => {
    b.runtime.restart.shutdownEvidence.response.success = false;
    b.runtime.restart.shutdownEvidence.response.ok = false;
    resealDigest(b.runtime.restart.shutdownEvidence, "evidenceSha256");
  });
  negative("restart close must precede authenticated shutdown response", "global_partial_order_invalid", (b) => {
    b.runtime.restart.shutdownEvidence.requestedAt = "2026-08-03T00:22:00.000Z";
    resealDigest(b.runtime.restart.shutdownEvidence, "evidenceSha256");
  });
  negative("shutdown request cannot follow shutdown completion",
    "global_partial_order_invalid", (b) => {
    b.runtime.restart.shutdownEvidence.requestedAt = "2026-08-03T00:22:50.000Z";
    resealDigest(b.runtime.restart.shutdownEvidence, "evidenceSha256");
  });
  negative("shutdown completion must precede final residue", "global_partial_order_invalid", (b) => {
    b.runtime.restart.shutdownEvidence.completedAt = "2026-08-03T00:23:30.000Z";
    resealDigest(b.runtime.restart.shutdownEvidence, "evidenceSha256");
  });
  const strictBoundaryFixture = Verifier.STRICT_GLOBAL_BOUNDARY_LABELS.map((label, index) =>
    [label, new Date(Date.parse("2026-08-03T00:00:00.000Z") + index * 1000).toISOString()]);
  positive("global boundary inventory admits one complete strict adjacent chain", () => {
    assert.deepStrictEqual(Verifier.assertStrictBoundaryChain(
      Common.deepClone(strictBoundaryFixture)), strictBoundaryFixture);
  });
  Verifier.STRICT_GLOBAL_BOUNDARY_LABELS.slice(1).forEach((label, index) => {
    const previous = Verifier.STRICT_GLOBAL_BOUNDARY_LABELS[index];
    negativeDirect("global boundary rejects non-strict pair " + previous + " -> " + label,
      "global_partial_order_invalid", () => {
        const boundaries = Common.deepClone(strictBoundaryFixture);
        boundaries[index + 1][1] = boundaries[index][1];
        Verifier.assertStrictBoundaryChain(boundaries);
      });
  });
  negativeDirect("global boundary inventory rejects an omitted boundary",
    "global_partial_order_invalid", () => {
      Verifier.assertStrictBoundaryChain(Common.deepClone(strictBoundaryFixture).slice(1));
    });
  negativeDirect("global boundary inventory rejects reordered labels",
    "global_partial_order_invalid", () => {
      const boundaries = Common.deepClone(strictBoundaryFixture);
      [boundaries[1], boundaries[2]] = [boundaries[2], boundaries[1]];
      Verifier.assertStrictBoundaryChain(boundaries);
    });

  positive("offline fixture cannot receive a live verdict", () => {
    assert.throws(() => Verifier.verifySemanticBundle(Fixture.buildValidBundle()),
      (error) => error && error.code === "offline_fixture_verdict_forbidden");
  });
  negative("offline fixture provenance cannot claim a live capture", "bundle_invalid", (b) => {
    b.fixtureProvenance.liveCapture = true;
  });
  negative("offline fixture cannot claim the real SAFEEXIT journey", "bundle_invalid", (b) => {
    b.safeExitUiJourneyVerified = true;
  });
  negative("evidence mode cannot diverge from evidence class", "bundle_invalid", (b) => {
    b.evidenceMode = "live_capture";
  });
  positive("non-canonical direct entries reject with exit 2", () => {
    ["self-test.js", "run-checks.js", "fixtures/valid-bundle.js", "run-live-journey.js",
      "verify-live-journey.js"].forEach((relative) => {
      const result = childProcess.spawnSync(process.execPath,
        [path.join(__dirname, relative)], { encoding: "utf8", windowsHide: true });
      assert.strictEqual(result.status, 2, relative + "\n" + result.stderr);
    });
  });

  negative("trusted target must be visible", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.target.visible = false; resealTranscript(b.transcripts.first);
  });
  negative("trusted target must be enabled", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.target.enabled = false; resealTranscript(b.transcripts.first);
  });
  negative("trusted target tag is exact", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.target.tagName = "SPAN"; resealTranscript(b.transcripts.first);
  });
  negative("trusted target selector is exact", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.target.selector = "button"; resealTranscript(b.transcripts.first);
  });
  negative("trusted click coordinates remain inside rect", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.coordinates.x = 9999; resealTranscript(b.transcripts.first);
  });
  negative("trusted target rect must have visible dimensions", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.target.rect.width = 0; event.target.rect.right = event.target.rect.left;
    resealTranscript(b.transcripts.first);
  });
  negative("trusted click client point must equal the captured event coordinates",
    "trusted_input_set_invalid", (b) => {
      const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
      event.target.clientPoint.x += 1; resealTranscript(b.transcripts.first);
    });
  negative("trusted click must hit the exact target", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.target.hitTargetMatches = false; resealTranscript(b.transcripts.first);
  });
  negative("trusted click viewport must be visible and bounded", "trusted_input_set_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    event.target.viewport.width = 0; resealTranscript(b.transcripts.first);
  });
  negative("raw parsed-script URL multiset cannot omit a producer",
    "loaded_production_url_multiset_invalid", (b) => {
      b.runtime.first.loadedProduction.relevantScriptUrls.pop();
      resealDigest(b.runtime.first.loadedProduction, "evidenceSha256");
    });
  negative("raw stylesheet URL multiset cannot duplicate a producer",
    "loaded_production_url_multiset_invalid", (b) => {
      b.runtime.restart.loadedProduction.relevantStyleUrls.push(
        b.runtime.restart.loadedProduction.relevantStyleUrls[0]);
      b.runtime.restart.loadedProduction.relevantStyleUrls.sort();
      resealDigest(b.runtime.restart.loadedProduction, "evidenceSha256");
    });
  negative("raw script occurrence stream rejects foreign executable URLs",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.scriptOccurrences.push({ occurrence: loaded.scriptOccurrences.length + 1,
        url: "https://foreign.invalid/injected.js", origin: "https://foreign.invalid",
        scriptId: "foreign-script", executionContextId: 1,
        source: "Debugger.scriptParsed" });
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw script occurrence stream rejects duplicate execution",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const duplicate = Common.deepClone(loaded.scriptOccurrences[1]);
      duplicate.occurrence = loaded.scriptOccurrences.length + 1;
      duplicate.scriptId = "duplicate-script";
      loaded.scriptOccurrences.push(duplicate);
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw script occurrence stream preserves execution order",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      [loaded.scriptOccurrences[1], loaded.scriptOccurrences[2]]
        = [loaded.scriptOccurrences[2], loaded.scriptOccurrences[1]];
      loaded.scriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw script occurrence binds execution context",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      loaded.scriptOccurrences[1].executionContextId = 0;
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw script occurrence binds CDP source",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      loaded.scriptOccurrences[1].source = "fixture_projection";
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw stylesheet occurrence binds main frame",
    "loaded_production_style_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.styleOccurrences[0].frameId = "foreign-frame";
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw stylesheet occurrence binds overlay origin",
    "loaded_production_style_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.styleOccurrences[0].origin = "https://foreign.invalid";
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw stylesheet occurrence stream preserves resource order",
    "loaded_production_style_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      [loaded.styleOccurrences[0], loaded.styleOccurrences[1]]
        = [loaded.styleOccurrences[1], loaded.styleOccurrences[0]];
      loaded.styleOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealDigest(loaded, "evidenceSha256");
    });
  negative("anonymous scriptParsed occurrence is retained and rejected",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const extra = Common.deepClone(loaded.scriptOccurrences.at(-1));
      extra.occurrence = loaded.scriptOccurrences.length + 1;
      extra.scriptId = "anonymous-script";
      extra.url = "";
      extra.origin = "opaque";
      extra.rawParams.scriptId = extra.scriptId;
      extra.rawParams.url = "";
      loaded.scriptOccurrences.push(extra);
      resealDigest(loaded, "evidenceSha256");
    });
  negative("unknown tool-owned sourceURL is rejected from the raw stream",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const extra = Common.deepClone(loaded.scriptOccurrences.at(-1));
      extra.occurrence = loaded.scriptOccurrences.length + 1;
      extra.scriptId = "unknown-tool-script";
      extra.url = "cf7-evidence://crafting/crafting-restart/9999-unknown.js";
      extra.rawParams.scriptId = extra.scriptId;
      extra.rawParams.url = extra.url;
      loaded.scriptOccurrences.push(extra);
      resealDigest(loaded, "evidenceSha256");
    });
  negative("tool sourceURL is the stable observer sequence projection",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const plan = loaded.toolScriptPlan.find((entry) => entry.label === "health");
      const occurrence = loaded.scriptOccurrences.find((entry) => entry.url === plan.url);
      plan.url = "cf7-evidence://crafting/crafting-first/9999-health.js";
      occurrence.url = plan.url;
      occurrence.rawParams.url = plan.url;
      resealDigest(loaded, "evidenceSha256");
    });
  negative("tool source hash binds its exact raw script occurrence",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.toolScriptPlan.find((entry) => entry.label === "health").sha256 = "0".repeat(64);
      resealDigest(loaded, "evidenceSha256");
    });
  negative("every executed tool plan entry remains in the raw script stream",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const plan = loaded.toolScriptPlan.find((entry) => entry.label === "health");
      loaded.scriptOccurrences = loaded.scriptOccurrences.filter((entry) => entry.url !== plan.url);
      loaded.scriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealDigest(loaded, "evidenceSha256");
    });
  positive("script raw params stay immutable when a later execution context arrives", () => {
    const ledger = Observer.createScriptContextLedger();
    const scriptParams = { scriptId: "script-a", url: "https://overlay.local/a.js",
      executionContextId: 41, startLine: 0, startColumn: 0, endLine: 1, endColumn: 0,
      sourceMapURL: "", executionContextAuxData: {
        frameId: "script-frame", isDefault: true, type: "default",
      } };
    ledger.record({ method: "Debugger.scriptParsed", params: scriptParams });
    scriptParams.url = "https://foreign.invalid/forged.js";
    scriptParams.executionContextAuxData.frameId = "mutated-input-frame";
    const entry = ledger.parsedScriptOrder[0];
    assert.strictEqual(entry.url, "https://overlay.local/a.js");
    assert.strictEqual(entry.frameId, "script-frame");
    assert.strictEqual(entry.rawParams.executionContextAuxData.frameId, "script-frame");
    assert(Object.isFrozen(entry.rawParams));
    assert(Object.isFrozen(entry.rawExecutionContextAuxData));
    const context = { id: 41, origin: "https://overlay.local", name: "", uniqueId: "ctx-a",
      auxData: { frameId: "later-context-frame", isDefault: true, type: "default" } };
    ledger.record({ method: "Runtime.executionContextCreated", params: { context } });
    context.origin = "https://foreign.invalid";
    context.auxData.frameId = "mutated-context-input";
    assert.strictEqual(entry.contextOrigin, "https://overlay.local");
    assert.strictEqual(entry.frameId, "script-frame");
    assert.strictEqual(entry.rawExecutionContextAuxData.frameId, "script-frame");
    assert.strictEqual(ledger.executionContexts.get(41).auxData.frameId, "later-context-frame");
    assert(Object.isFrozen(ledger.executionContexts.get(41)));
  });
  negative("execution context preserves the full raw auxData occurrence",
    "loaded_production_context_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.executionContextOccurrences[0].rawContext.auxData.type = "isolated";
      resealDigest(loaded, "evidenceSha256");
    });
  negative("execution context occurrence stream cannot disappear",
    "loaded_production_context_occurrence_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      loaded.executionContextOccurrences = [];
      resealDigest(loaded, "evidenceSha256");
    });
  negative("execution context stream rejects an unused valid-shaped context",
    "loaded_production_context_projection_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const extra = Common.deepClone(loaded.executionContextOccurrences[0]);
      extra.occurrence = 2;
      extra.executionContextId += 1000;
      extra.uniqueId = "unused-context";
      extra.rawContext.id = extra.executionContextId;
      extra.rawContext.uniqueId = extra.uniqueId;
      loaded.executionContextOccurrences.push(extra);
      resealDigest(loaded, "evidenceSha256");
    });
  negative("production script auxData is exact with its referenced context",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const occurrence = loaded.scriptOccurrences.find((entry) =>
        loaded.relevantScriptUrls.includes(entry.url));
      occurrence.rawExecutionContextAuxData.type = "isolated";
      resealDigest(loaded, "evidenceSha256");
    });
  negative("production script raw auxData cannot disappear",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const occurrence = loaded.scriptOccurrences.find((entry) =>
        loaded.relevantScriptUrls.includes(entry.url));
      delete occurrence.rawExecutionContextAuxData;
      resealDigest(loaded, "evidenceSha256");
    });
  negative("script raw params and dedicated script auxData must be deep-equal",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const occurrence = loaded.scriptOccurrences.find((entry) =>
        loaded.relevantScriptUrls.includes(entry.url));
      occurrence.rawParams.executionContextAuxData.frameId = "foreign-frame";
      resealDigest(loaded, "evidenceSha256");
    });
  negative("scriptParsed start/end fields bind the full raw params",
    "loaded_production_url_multiset_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.scriptOccurrences[1].rawParams.endLine += 1;
      resealDigest(loaded, "evidenceSha256");
    });
  negative("production source bytes cannot drift in raw and derived projections",
    "loaded_production_resource_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const occurrence = loaded.scriptOccurrences.find((entry) =>
        entry.url === loaded.scripts[0].url);
      occurrence.sourceSha256 = "0".repeat(64);
      loaded.scripts[0].sha256 = occurrence.sourceSha256;
      resealDigest(loaded, "evidenceSha256");
    });
  negative("foreign stylesheet remains visible in the raw resource stream",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const extra = Common.deepClone(loaded.styleOccurrences.at(-1));
      extra.occurrence = loaded.resourceOccurrences.length + 1;
      extra.resourceOccurrence += 1;
      extra.url = "https://foreign.invalid/injected.css";
      extra.origin = "https://foreign.invalid";
      extra.resource.url = extra.url;
      loaded.resourceOccurrences.push(extra);
      loaded.styleOccurrences.push(Common.deepClone(extra));
      resealDigest(loaded, "evidenceSha256");
    });
  negative("unregistered non-CSS resource occurrence is rejected",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const extra = Common.deepClone(loaded.resourceOccurrences.at(-1));
      extra.occurrence = loaded.resourceOccurrences.length + 1;
      extra.resourceOccurrence = extra.occurrence;
      extra.url = "https://overlay.local/assets/unregistered.png";
      extra.resource.url = extra.url;
      loaded.resourceOccurrences.push(extra);
      resealDigest(loaded, "evidenceSha256");
    });
  negative("Page tree cannot omit an external production Script occurrence",
    "loaded_production_resource_projection_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const index = loaded.resourceOccurrences.findIndex((entry) =>
        entry.resourceType === "Script");
      loaded.resourceOccurrences.splice(index, 1);
      loaded.resourceOccurrences.forEach((entry, occurrence) => {
        entry.occurrence = occurrence + 1;
        entry.resourceOccurrence = occurrence + 1;
      });
      loaded.styleOccurrences = loaded.resourceOccurrences.filter((entry) =>
        entry.resourceType === "Stylesheet").map((entry) => Common.deepClone(entry));
      resealDigest(loaded, "evidenceSha256");
    });
  negative("Page tree cannot omit a base-map prewarm Image occurrence",
    "loaded_production_resource_projection_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const prewarm = SourceContract.idlePrewarmFiles(b.sourceClosure)[0];
      const url = "https://overlay.local/"
        + prewarm.locator.slice("root:launcher/web/".length);
      loaded.resourceOccurrences = loaded.resourceOccurrences.filter((entry) => entry.url !== url);
      loaded.resourceOccurrences.forEach((entry, occurrence) => {
        entry.occurrence = occurrence + 1;
        entry.resourceOccurrence = occurrence + 1;
      });
      loaded.styleOccurrences = loaded.resourceOccurrences.filter((entry) =>
        entry.resourceType === "Stylesheet").map((entry) => Common.deepClone(entry));
      resealDigest(loaded, "evidenceSha256");
    });
  negative("conditional CSS resources preserve source inventory order",
    "loaded_production_resource_projection_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const urls = SourceContract.cssConditionalResourceSet(b.sourceClosure)
        .slice(0, 2).map((entry) => entry.url);
      const indexes = urls.map((url) => loaded.resourceOccurrences.findIndex((entry) =>
        entry.url === url));
      [loaded.resourceOccurrences[indexes[0]], loaded.resourceOccurrences[indexes[1]]]
        = [loaded.resourceOccurrences[indexes[1]], loaded.resourceOccurrences[indexes[0]]];
      loaded.resourceOccurrences.forEach((entry, occurrence) => {
        entry.occurrence = occurrence + 1;
        entry.resourceOccurrence = occurrence + 1;
      });
      loaded.styleOccurrences = loaded.resourceOccurrences.filter((entry) =>
        entry.resourceType === "Stylesheet").map((entry) => Common.deepClone(entry));
      resealDigest(loaded, "evidenceSha256");
    });
  negative("successful Font occurrence binds its mapped manifest bytes",
    "loaded_production_resource_source_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const font = loaded.fontEnvironment.installed[0];
      assert.ok(font, "fixture must exercise at least one successful Font route");
      loaded.resourceOccurrences.find((entry) => entry.url === font.url).sourceBytes += 1;
      resealDigest(loaded, "evidenceSha256");
    });
  negative("authoritative icon bytes bind the current manifest asset",
    "loaded_production_resource_source_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const iconUrl = loaded.iconProjection.resources[0].url;
      loaded.resourceOccurrences.find((entry) => entry.url === iconUrl).sourceSha256
        = "0".repeat(64);
      resealDigest(loaded, "evidenceSha256");
    });
  negative("raw resource preserves its complete CDP resource fields",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      loaded.resourceOccurrences[0].resource.url = "https://overlay.local/assets/other.png";
      resealDigest(loaded, "evidenceSha256");
    });
  negative("CSS order is derived from the unfiltered raw resource stream",
    "loaded_production_resource_projection_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      [loaded.resourceOccurrences[1], loaded.resourceOccurrences[2]]
        = [loaded.resourceOccurrences[2], loaded.resourceOccurrences[1]];
      loaded.resourceOccurrences.forEach((entry, index) => {
        entry.occurrence = index + 1;
        entry.resourceOccurrence = index + 1;
      });
      loaded.styleOccurrences = loaded.resourceOccurrences.filter((entry) =>
        entry.resourceType === "Stylesheet").map((entry) => Common.deepClone(entry));
      resealDigest(loaded, "evidenceSha256");
    });
  negative("detach sourceURL is the terminal raw script occurrence",
    "loaded_production_not_terminal", (b) => {
      const loaded = b.runtime.restart.loadedProduction;
      const detachUrl = loaded.toolScriptPlan.at(-1).url;
      const detachIndex = loaded.scriptOccurrences.findIndex((entry) => entry.url === detachUrl);
      [loaded.scriptOccurrences[detachIndex - 1], loaded.scriptOccurrences[detachIndex]]
        = [loaded.scriptOccurrences[detachIndex], loaded.scriptOccurrences[detachIndex - 1]];
      loaded.scriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealDigest(loaded, "evidenceSha256");
    });
  negative("same-fid response cmd must bind the request operation",
    "host_flash_roundtrip_invalid", (b) => {
      const log = b.runtime.first.finalLogSnapshot;
      const record = log.records.find((entry) =>
        entry.line.includes("task=crafting_response cmd=snapshot"));
      record.line = record.line.replace("cmd=snapshot", "cmd=other");
      resealLog(log);
    });
  negative("non-ready production rejection is a relevant Host record",
    "host_non_ready_rejection_present", (b) => {
      const log = b.runtime.first.finalLogSnapshot;
      log.records.push({ lineNumber: log.records.length + 1,
        line: "08:13:40.000 [Panel] rejected message from a non-ready Web document cmd=commit" });
      resealLog(log);
    });
  negative("Host records require the current formatter timestamp",
    "host_log_formatter_invalid", (b) => {
      const log = b.runtime.first.finalLogSnapshot;
      log.records[0].line = log.records[0].line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3} /, "");
      resealLog(log);
    });
  negative("Host rejects an ordinary non-midnight clock regression",
    "host_timeline_regression", (b) => {
      const log = b.runtime.first.finalLogSnapshot;
      log.records[1].line = log.records[1].line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/,
        "08:00:59.000");
      resealLog(log);
    });
  positive("Host reconstructs one legal 23-to-00 rollover statefully", () => {
    const bundle = Fixture.buildValidBundle();
    const lifecycle = bundle.runtime.first;
    const start = 23 * 3600 + 59 * 60 + 50;
    lifecycle.finalLogSnapshot.records.forEach((record, index) => {
      const seconds = (start + index * 2) % (24 * 3600);
      const stamp = String(Math.floor(seconds / 3600)).padStart(2, "0") + ":"
        + String(Math.floor(seconds / 60) % 60).padStart(2, "0") + ":"
        + String(seconds % 60).padStart(2, "0") + ".000";
      record.line = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/, stamp);
    });
    lifecycle.finalLogSnapshot.capturedAt = new Date(2026, 7, 4, 1, 0, 0).toISOString();
    resealLog(lifecycle.finalLogSnapshot);
    const records = Verifier.recordsForLifecycle(lifecycle, "legal_rollover");
    assert.strictEqual(records.length, lifecycle.finalLogSnapshot.records.length);
    assert(/^23:/.test(records[0].timestamp));
    assert(/^00:/.test(records.at(-1).timestamp));
    assert(Date.parse(records[0].observedAt) < Date.parse(records.at(-1).observedAt));
    assert.strictEqual(Date.parse(records.at(-1).observedAt)
      - Date.parse(records[0].observedAt), (records.length - 1) * 2000);
  });
  negativeDirect("Host rejects a second 23-to-00 rollover in one lifecycle",
    "host_timeline_regression", () => {
      const bundle = Fixture.buildValidBundle();
      const lifecycle = bundle.runtime.first;
      const forced = ["23:59:58.000", "00:00:00.000", "23:59:59.000", "00:00:01.000"];
      lifecycle.finalLogSnapshot.records.forEach((record, index) => {
        const fallback = "00:00:" + String(Math.min(59, index)).padStart(2, "0") + ".000";
        record.line = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}/,
          forced[index] || fallback);
      });
      lifecycle.finalLogSnapshot.capturedAt = new Date(2026, 7, 5, 0, 2, 0).toISOString();
      resealLog(lifecycle.finalLogSnapshot);
      Verifier.recordsForLifecycle(lifecycle, "second_rollover");
    });
  negative("Host summary rejects trailing fields", "host_authority_summary_invalid", (b) => {
    const log = b.runtime.first.finalLogSnapshot;
    const record = log.records.find((entry) => entry.line.includes("HandlePanelMessage"));
    record.line += " trailing"; resealLog(log);
  });
  negative("provider source must be the selected tool result", "provider_receipt_invalid", (b) => {
    mutateProvider(b, "open_crafting", (receipt) => {
      receipt.toolResultSource = "launcher_agent_runtime_tool_result";
    });
  });
  negative("provider issuer must match the selected transport", "provider_receipt_invalid", (b) => {
    mutateProvider(b, "open_crafting", (receipt) => {
      receipt.issuer = "launcher_agent_runtime";
    });
  });
  negative("provider receipt binds exact persisted request bytes", "provider_receipt_invalid", (b) => {
    mutateProvider(b, "select_recipe", (receipt) => {
      receipt.requestSha256 = "1".repeat(64);
    });
  });
  negative("persisted request cannot drift from the bundle", "control_request_artifact_mismatch", (b) => {
    const request = b.control.requests[2];
    const file = path.join(b.runDir, "control", "requests", request.requestId + ".json");
    const persisted = JSON.parse(fs.readFileSync(file, "utf8"));
    persisted.instructions += " forged";
    fs.writeFileSync(file, JSON.stringify(persisted, null, 2) + "\n");
  });
  negative("provider receipt binds its exact owned path", "provider_receipt_invalid", (b) => {
    mutateProvider(b, "capture_inventory_before", (receipt) => {
      receipt.ownedArtifact = "control/provider-receipts/foreign.json";
    });
  });
  negative("provider capture event binds its exact owned PNG path",
    "provider_capture_event_invalid", (b) => {
      mutateCaptureEvent(b, "return_from_inventory_before", (event) => {
        event.captureArtifact = "control/captures/foreign.png";
      });
    });
  negative("provider capture event binds current PNG byte count",
    "provider_capture_event_invalid", (b) => {
      mutateCaptureEvent(b, "commit_recipe", (event) => { event.captureBytes += 1; });
    });
  negative("provider capture event binds current PNG dimensions",
    "provider_capture_event_invalid", (b) => {
      mutateCaptureEvent(b, "capture_inventory_after", (event) => {
        event.captureWidth = 319;
      });
    });
  negative("provider capture event cannot claim semantic screenshot verification",
    "provider_capture_event_invalid", (b) => {
      mutateCaptureEvent(b, "capture_inventory_after", (event) => {
        event.captureSemanticContentIndependentlyVerified = true;
      });
    });
  negative("provider receipt cannot redirect to another capture event",
    "provider_capture_event_reference_invalid", (b) => {
      mutateProvider(b, "return_from_inventory_before", (receipt) => {
        receipt.captureEventRef.artifact = "control/capture-events/foreign.json";
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("ack cannot redirect to another provider capture", "provider_capture_reference_invalid", (b) => {
    const first = b.control.acks[0].capture;
    const ack = b.control.acks[1];
    ack.capture = Common.deepClone(first); ack.captureSha256 = first.sha256;
  });
  negative("provider captures cannot reuse the same image bytes", "provider_evidence_reused", (b) => {
    const firstAck = b.control.acks[0];
    const secondRequest = b.control.requests[1];
    const secondAck = b.control.acks[1];
    const bytes = fs.readFileSync(path.join(b.runDir,
      firstAck.capture.relativePath.replace(/\//g, path.sep)));
    const secondCapturePath = path.join(b.runDir,
      secondAck.capture.relativePath.replace(/\//g, path.sep));
    const secondRequestAck = b.control.acks.find((entry) =>
      entry.requestId === secondRequest.requestId);
    const secondReceipt = JSON.parse(fs.readFileSync(path.join(b.runDir,
      secondRequestAck.providerReceipt.artifact.replace(/\//g, path.sep)), "utf8"));
    const originalEvent = JSON.parse(fs.readFileSync(path.join(b.runDir,
      secondReceipt.captureEventRef.artifact.replace(/\//g, path.sep)), "utf8"));
    overwriteCapture(b, secondRequest.step, bytes);
    const modifiedSeconds = Date.parse(originalEvent.fileModifiedAt) / 1000;
    fs.utimesSync(secondCapturePath, modifiedSeconds, modifiedSeconds);
    mutateCaptureEvent(b, secondRequest.step, (event) => {
      event.captureSha256 = secondAck.capture.sha256;
      event.captureBytes = secondAck.capture.bytes;
    });
  });
  negative("provider capture event self-digest is closed", "provider_capture_event_invalid", (b) => {
    mutateCaptureEvent(b, "select_recipe", (event) => {
      event.eventSha256 = "0".repeat(64);
    }, { resealEvent: false });
  });
  negative("provider receipt self-digest is closed", "provider_receipt_digest_invalid", (b) => {
    mutateProvider(b, "select_recipe", (receipt) => {
      receipt.receiptSha256 = "0".repeat(64);
    }, false);
  });
  negative("deterministic provider operation ids reject reuse", "provider_receipt_invalid", (b) => {
    const first = b.control.requests.find((entry) => entry.step === "open_crafting");
    const firstAck = b.control.acks.find((entry) => entry.requestId === first.requestId);
    const firstReceipt = JSON.parse(fs.readFileSync(path.join(b.runDir,
      firstAck.providerReceipt.artifact.replace(/\//g, path.sep)), "utf8"));
    mutateProvider(b, "select_recipe", (receipt) => {
      receipt.providerOperationId = firstReceipt.providerOperationId;
    });
  });
  negative("provider DOM event hash binds the exact transcript occurrence",
    "provider_dom_event_binding_invalid", (b) => {
      mutateBoundProvider(b, "select_recipe", (receipt) => {
        receipt.inputEvidence.eventRef.eventSha256 = "0".repeat(64);
      });
    });
  negative("one trusted DOM occurrence cannot satisfy two provider operations",
    "provider_dom_event_binding_invalid", (b) => {
      const firstRequest = b.control.requests.find((entry) =>
        entry.step === "capture_inventory_before");
      const firstAck = b.control.acks.find((entry) => entry.requestId === firstRequest.requestId);
      const firstReceipt = JSON.parse(fs.readFileSync(path.join(b.runDir,
        firstAck.providerReceipt.artifact.replace(/\//g, path.sep)), "utf8"));
      mutateBoundProvider(b, "capture_inventory_after", (receipt) => {
        receipt.inputEvidence.eventRef = Common.deepClone(firstReceipt.inputEvidence.eventRef);
      });
    });
  negative("provider DOM tag fact is transcript-bound",
    "provider_dom_event_binding_invalid", (b) => {
      mutateBoundProvider(b, "commit_recipe", (receipt) => {
        receipt.inputEvidence.tagName = "DIV";
      });
    });
  negative("provider DOM client point is transcript-bound",
    "provider_dom_event_binding_invalid", (b) => {
      mutateBoundProvider(b, "return_from_inventory_before", (receipt) => {
        receipt.inputEvidence.clientPoint.x += 1;
      });
    });
  negative("provider selector must equal the exact request selector",
    "provider_input_evidence_invalid", (b) => {
      mutateBoundProvider(b, "select_recipe", (receipt) => {
        receipt.inputEvidence.selector = "button";
      });
    });
  negative("provider click cannot claim a keyboard key",
    "provider_input_evidence_invalid", (b) => {
      mutateBoundProvider(b, "select_recipe", (receipt) => {
        receipt.inputEvidence.key = "Enter";
      });
    });
  negative("native provider input cannot claim a passive DOM eventRef",
    "provider_input_evidence_invalid", (b) => {
      mutateBoundProvider(b, "safe_exit", (receipt) => {
        receipt.inputEvidence.eventRef = { observerId: "crafting-first", sequence: 1,
          eventSha256: "1".repeat(64) };
      });
    });
  negative("provider operation must start strictly after request issue",
    "provider_receipt_invalid", (b) => {
      const request = b.control.requests.find((entry) => entry.step === "select_recipe");
      mutateBoundProvider(b, "select_recipe", (receipt) => {
        receipt.startedAt = request.issuedAt;
      });
    });
  negative("trusted DOM input cannot precede provider operation start",
    "provider_receipt_invalid", (b) => {
      mutateBoundProvider(b, "select_recipe", (receipt) => {
        receipt.startedAt = "2026-08-03T00:02:11.000Z";
      });
    });
  negative("trusted DOM input must occur strictly after provider operation start",
    "provider_receipt_invalid", (b) => {
      mutateBoundProvider(b, "select_recipe", (receipt) => {
        receipt.startedAt = receipt.inputEvidence.observedAt;
      });
    });
  negative("provider capture must follow the exact input occurrence",
    "provider_receipt_invalid", (b) => {
      mutateCaptureEvent(b, "select_recipe", (event, state) => {
        event.capturedAt = state.receipt.inputEvidence.observedAt;
      });
    });
  negative("provider capture must strictly precede its filesystem mtime",
    "provider_capture_event_invalid", (b) => {
      mutateCaptureEvent(b, "select_recipe", (event) => {
        event.capturedAt = event.fileModifiedAt;
      });
    });
  negative("provider completion must follow its owned capture",
    "provider_receipt_invalid", (b) => {
      mutateBoundProvider(b, "select_recipe", (receipt) => {
        const eventFile = path.join(b.runDir,
          receipt.captureEventRef.artifact.replace(/\//g, path.sep));
        const event = JSON.parse(fs.readFileSync(eventFile, "utf8"));
        receipt.completedAt = event.fileModifiedAt;
      });
    });
  negative("capture file mtime cannot drift behind a valid event digest",
    "provider_capture_event_invalid", (b) => {
      const request = b.control.requests.find((entry) => entry.step === "select_recipe");
      const ack = b.control.acks.find((entry) => entry.requestId === request.requestId);
      const capturePath = path.join(b.runDir,
        ack.capture.relativePath.replace(/\//g, path.sep));
      const drift = Date.parse("2026-08-03T00:02:22.000Z") / 1000;
      fs.utimesSync(capturePath, drift, drift);
    });
  negative("capture event identity cannot bind a stale request hash",
    "provider_capture_event_invalid", (b) => {
      mutateCaptureEvent(b, "select_recipe", (event) => {
        event.requestSha256 = "0".repeat(64);
      });
    });
  negative("control request run identity is exact", "control_request_invalid", (b) => {
    b.control.requests[0].runId = "foreign-run";
  });
  negative("control ack step identity is exact", "control_ack_invalid", (b) => {
    b.control.acks[0].step = "select_recipe";
  });
  negative("candidate producer evidence cannot disappear",
    "candidate_producer_evidence_invalid", (b) => { delete b.candidateProducer; });
  negative("candidate producer binds the authenticated Core EXE locator",
    "candidate_producer_evidence_invalid", (b) => {
      b.candidateProducer.processImage.locator = "candidate:runtime/Other.exe";
      resealDigest(b.candidateProducer, "evidenceSha256");
    });
  negative("candidate producer binds independent Core EXE bytes",
    "source_binding_invalid", (b) => {
      b.candidateProducer.processImage.sha256 = "0".repeat(64).toUpperCase();
      resealDigest(b.candidateProducer, "evidenceSha256");
    });
  negative("candidate producer rejects an empty Core EXE byte record",
    "candidate_producer_evidence_invalid", (b) => {
      b.candidateProducer.processImage.bytes = 0;
      resealDigest(b.candidateProducer, "evidenceSha256");
    });
  negative("candidate producer exposes the exact Core DLL identity row",
    "candidate_producer_evidence_invalid", (b) => {
      b.candidateProducer.coreLibrary.sha256 = "1".repeat(64);
      resealDigest(b.candidateProducer, "evidenceSha256");
    });
  negative("source binding includes candidate producer digest", "source_binding_invalid", (b) => {
    b.sourceBinding.candidateProducerSha256 = "d".repeat(64);
    resealDigest(b.sourceBinding, "bindingSha256");
  });
  negative("runtime producer three-domain envelope is mandatory", "source_closure_invalid", (b) => {
    b.sourceClosure.records.forEach((record) => {
      delete record.fingerprint.producerInputs.domains.toolchainLock;
    });
    resealSourceClosure(b.sourceClosure);
  });
  negative("legacy credential capability allowlist is exact",
    "legacy_credential_allowlist_invalid", (b) => {
      b.runtime.first.sessionEvidence.capabilities.push("legacy.unadmitted_extra");
      b.runtime.first.sessionEvidence.capabilities.sort();
      resealDigest(b.runtime.first.sessionEvidence, "sessionEvidenceSha256");
    });
  negative("process contract field set is exact", "launcher_process_contract_invalid", (b) => {
    b.runtime.first.processContract.operatorNote = "not authoritative";
    resealDigest(b.runtime.first.processContract, "artifactSha256");
  });
  negative("capability envelope field set is exact", "control_capability_invalid", (b) => {
    b.control.capability.operatorNote = "not authoritative";
  });
  negative("capability artifact field set is exact", "control_capability_invalid", (b) => {
    b.control.capability.artifact.operatorNote = "not authoritative";
    b.control.capability.artifactSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(b.control.capability.artifact));
  });
  negative("one-pixel PNG is not visible evidence", "control_capture_media_invalid", (b) => {
    const bytes = Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
      "base64");
    overwriteCapture(b, "safe_exit", bytes);
  });
  negative("sixteen-pixel PNG is not usable interaction evidence", "control_capture_media_invalid", (b) => {
    overwriteCapture(b, "safe_exit", Fixture.visiblePng(16, 16, 71));
  });
  negativeDirect("PNG rejects a second concatenated zlib stream",
    "control_capture_media_invalid", () => {
      const raw = Buffer.alloc((320 * 4 + 1) * 180);
      const stream = zlib.deflateSync(raw);
      Common.decodePng(testPng(320, 180, 8, 6, raw, {
        compressed: Buffer.concat([stream, stream]),
      }));
    });
  negativeDirect("PNG rejects arbitrary bytes after the zlib stream",
    "control_capture_media_invalid", () => {
      const raw = Buffer.alloc((320 * 4 + 1) * 180);
      Common.decodePng(testPng(320, 180, 8, 6, raw, {
        compressed: Buffer.concat([zlib.deflateSync(raw), Buffer.from([0xde, 0xad])]),
      }));
    });
  negativeDirect("PNG rejects a truncated compressed stream",
    "control_capture_media_invalid", () => {
      const raw = Buffer.alloc((320 * 4 + 1) * 180);
      const compressed = zlib.deflateSync(raw);
      Common.decodePng(testPng(320, 180, 8, 6, raw, {
        compressed: compressed.subarray(0, compressed.length - 2),
      }));
    });
  negativeDirect("PNG rejects an undefined scanline filter",
    "control_capture_media_invalid", () => {
      const raw = Buffer.alloc((320 * 4 + 1) * 180);
      raw[0] = 5;
      Common.decodePng(testPng(320, 180, 8, 6, raw));
    });
  negativeDirect("indexed PNG rejects pixels outside the declared palette",
    "control_capture_media_invalid", () => {
      const raw = Buffer.alloc((320 + 1) * 180);
      for (let row = 0; row < 180; row += 1) raw.fill(1, row * 321 + 1, (row + 1) * 321);
      Common.decodePng(testPng(320, 180, 8, 3, raw, {
        palette: Buffer.from([0, 0, 0]),
      }));
    });
  positive("PNG unfilters all five legal scanline filter types", () => {
    const stride = 320 * 4 + 1;
    const raw = Buffer.alloc(stride * 180);
    for (let row = 0; row < 180; row += 1) raw[row * stride] = row % 5;
    const decoded = Common.decodePng(testPng(320, 180, 8, 6, raw));
    assert.strictEqual(decoded.width, 320);
    assert.strictEqual(decoded.height, 180);
    assert.strictEqual(decoded.pixelBytes, 320 * 180 * 4);
    assert.match(decoded.pixelSha256, /^[a-f0-9]{64}$/);
  });
  negative("valid PNG replacement cannot change behind a trusted capture event",
    "provider_capture_event_invalid", (b) => {
    overwriteCapture(b, "safe_exit", Fixture.visiblePng(320, 180, 99));
  });

  positive("all 15 controls have unique provider-bound request and capture evidence", () => {
    const result = semantic(Fixture.buildValidBundle());
    const exchanges = Array.from(result.control.exchanges.values());
    assert.strictEqual(exchanges.length, 15);
    assert.strictEqual(new Set(exchanges.map((entry) =>
      entry.providerReceipt.providerOperationId)).size, 15);
    assert.strictEqual(new Set(exchanges.map((entry) =>
      entry.providerReceipt.requestSha256)).size, 15);
    assert.strictEqual(new Set(exchanges.map((entry) =>
      entry.providerCaptureEvent.captureSha256)).size, 15);
    assert.strictEqual(new Set(exchanges.map((entry) =>
      entry.providerCaptureEvent.providerEventId)).size, 15);
  });
  positive("ack helper rejects caller-supplied capture files before filesystem work", () => {
    const result = childProcess.spawnSync(process.execPath, [require.resolve("./ack-control"),
      "--run-dir", "C:\\absent", "--request-id", "fixture-request",
      "--transport", "codex_computer_use", "--result", "completed",
      "--provider-receipt", "C:\\absent\\provider.json",
      "--capture-file", "C:\\external.png"], { encoding: "utf8", windowsHide: true });
    assert.strictEqual(result.status, 2);
    assert.strictEqual(result.stdout, "");
    assert.match(result.stderr, /unknown argument: --capture-file/);
  });

  assert(browserGateReceipt);
  assert(isolatedModuleGateReceipt);
  return { ok: true, schema: "workbench-live-e2e.crafting.self-test.v5",
    status: "OFFLINE_VERIFIED", live: "LIVE_BLOCKED", deployment: "NOT_DEPLOYED",
    positives: positives.length, negatives: negatives.length,
    total: positives.length + negatives.length,
    childReceipts:{ browser:browserGateReceipt, isolatedModule:isolatedModuleGateReceipt } };
}

function main() {
  const result = runSelfTests();
  console.log(JSON.stringify(result, null, 2));
  return result;
}

module.exports = { main, resealLog, resealTranscript,
  runIsolatedModuleManifestContractTests, runModuleManifestContractTests, runSelfTests };

if (require.main === module) {
  console.error("Use canonical entry: node tools/workbench-live-e2e/crafting/bootstrap.js --check");
  process.exitCode = 2;
}
