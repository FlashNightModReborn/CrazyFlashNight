#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const Evidence = require("../lib/evidence-artifact");
const {
  PROVIDER_RECEIPT_SCHEMA,
  PROVIDER_CAPTURE_EVENT_SCHEMA,
  NATIVE_INPUT_EVENT_SCHEMA,
  decodePng,
  nextRecord,
  redactAuthority,
  tokenRef,
} = require("./common");
const { STRICT_GLOBAL_BOUNDARY_LABELS, assertStrictBoundaryChain,
  capturePreSealArtifactFreeze, semanticDigest,
  persistPreSealSidecars, verifyPreSealArtifactFreeze,
  verifySemanticBundle, verifyTranscriptArtifacts } = require("./evidence-verifier");
const { ControlChannel, domInputEvidence, expectedProviderOperationId,
  expectedProviderCaptureEventId, writeAck } = require("./control-channel");
const Protocol = require("./protocol");
const ProductionClosure = require("./production-closure");
const AckControl = require("./ack-control");
const Fixture = require("./fixtures/valid-bundle");
const IdentityFixture = require("../../equipment-tuning/fixtures/item-identity-triple.json");
const REPOSITORY_ROOT = path.resolve(__dirname, "../../..");

function clone(value) { return JSON.parse(JSON.stringify(value)); }

const pngCrcTable = (() => {
  const table = [];
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table.push(value >>> 0);
  }
  return table;
})();

function pngCrc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = pngCrcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
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

function rewritePng(bytes, rewrite) {
  const chunks = [];
  let offset = 8;
  while (offset < bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const type = bytes.subarray(offset + 4, offset + 8).toString("ascii");
    chunks.push({ type, data: Buffer.from(bytes.subarray(offset + 8, offset + 8 + length)) });
    offset += 12 + length;
  }
  rewrite(chunks);
  return Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"),
    ...chunks.map((entry) => pngChunk(entry.type, entry.data))]);
}

function indexedPng(bitDepth, paletteEntries, paletteIndex) {
  assert.ok([1, 2, 4, 8].includes(bitDepth));
  assert.ok(Number.isInteger(paletteEntries) && paletteEntries >= 1
    && paletteEntries <= 2 ** bitDepth);
  assert.ok(Number.isInteger(paletteIndex) && paletteIndex >= 0
    && paletteIndex < 2 ** bitDepth);
  const width = 320;
  const height = 180;
  const rowBytes = Math.ceil(width * bitDepth / 8);
  const rows = Buffer.alloc(height * (rowBytes + 1));
  const mask = (1 << bitDepth) - 1;
  for (let row = 0; row < height; row += 1) {
    const rowOffset = row * (rowBytes + 1);
    rows[rowOffset] = 0;
    for (let column = 0; column < width; column += 1) {
      const bitOffset = column * bitDepth;
      const byteOffset = rowOffset + 1 + Math.floor(bitOffset / 8);
      const shift = 8 - bitDepth - (bitOffset % 8);
      rows[byteOffset] |= (paletteIndex & mask) << shift;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = bitDepth;
  ihdr[9] = 3;
  const palette = Buffer.alloc(paletteEntries * 3);
  for (let index = 0; index < paletteEntries; index += 1) {
    palette[index * 3] = index;
    palette[index * 3 + 1] = 255 - index;
    palette[index * 3 + 2] = index ^ 0x55;
  }
  return Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", ihdr), pngChunk("PLTE", palette),
    pngChunk("IDAT", zlib.deflateSync(rows)), pngChunk("IEND", Buffer.alloc(0))]);
}

function hostTimelineSnapshot(capturedAt, values) {
  return { capturedAt, records: values.map((value, index) => ({
    lineNumber: index + 1, line: value + " fixture_event=" + (index + 1),
  })) };
}

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

function messages(bundle, phase, kind, domain, cmd) {
  return bundle.transcripts[phase].events.filter((event) => event.kind === kind
    && event.message && (!domain || event.message.domain === domain)
    && (!cmd || event.message.cmd === cmd));
}

function request(bundle, phase, domain, cmd, occurrence) {
  return messages(bundle, phase, "bridge_send", domain, cmd)[occurrence || 0];
}

function response(bundle, phase, domain, cmd, occurrence) {
  return messages(bundle, phase, "webview_message", domain, cmd)[occurrence || 0];
}

function diagnostic(bundle, eventName, occurrence) {
  return bundle.transcripts.first.events.filter((event) => event.message
    && event.message.type === "debug" && event.message.event === eventName)[occurrence || 0];
}

function placeBefore(items, moving, anchor) {
  const next = items.filter((entry) => entry !== moving);
  const index = next.indexOf(anchor);
  assert.ok(index >= 0, "anchor must remain in the collection");
  next.splice(index, 0, moving);
  items.splice(0, items.length, ...next);
}

function placeAfter(items, moving, anchor) {
  const next = items.filter((entry) => entry !== moving);
  const index = next.indexOf(anchor);
  assert.ok(index >= 0, "anchor must remain in the collection");
  next.splice(index + 1, 0, moving);
  items.splice(0, items.length, ...next);
}

function hostRecord(bundle, phase, fragment, occurrence) {
  return bundle.runtime[phase].finalLogSnapshot.records
    .filter((record) => String(record.line || "").includes(fragment))[occurrence || 0];
}

function pushTimestampedHostRecord(bundle, phase, line) {
  const records = bundle.runtime[phase].finalLogSnapshot.records;
  const prefix = records.slice(-1)[0].line.slice(0, 13);
  records.push({ lineNumber: 0, line: prefix + line });
}

function setHostRecordTime(record, iso) {
  const value = new Date(iso);
  const pad = (number, width) => String(number).padStart(width, "0");
  const prefix = pad(value.getHours(), 2) + ":" + pad(value.getMinutes(), 2) + ":"
    + pad(value.getSeconds(), 2) + "." + pad(value.getMilliseconds(), 3) + " ";
  record.line = prefix + record.line.slice(13);
}

function resealProductionClosure(closure) {
  const payload = Object.assign({}, closure);
  delete payload.closureSha256;
  closure.closureSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function resealPageResourceContract(contract) {
  const payload = Object.assign({}, contract);
  delete payload.contractSha256;
  contract.contractSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function resealProducerInputs(inputs) {
  delete inputs.inputsSha256;
  inputs.inputsSha256 = Evidence.sha256Text(Evidence.canonicalJson(inputs));
}

function resealLoadedProduction(loaded) {
  const payload = Object.assign({}, loaded);
  delete payload.evidenceSha256;
  loaded.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function replaceRawSource(entry, value) {
  const bytes = Buffer.from(value, "utf8");
  entry.sourceBase64 = bytes.toString("base64");
  entry.sourceBytes = bytes.length;
  entry.sourceSha256 = Evidence.sha256Bytes(bytes);
}

function resealProductionBinding(binding) {
  const payload = Object.assign({}, binding);
  delete payload.bindingSha256;
  binding.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function resealLog(snapshot) {
  snapshot.records.forEach((record, index) => { record.lineNumber = index + 1; });
  snapshot.total = snapshot.records.length;
  snapshot.oldestLineNumber = snapshot.records.length ? 1 : 1;
  const payload = { schema: snapshot.schema, requestedTailLimit: snapshot.requestedTailLimit,
    sessionEvidenceSha256: snapshot.sessionEvidenceSha256, lifecycleId: snapshot.lifecycleId,
    sessionPid: snapshot.sessionPid,
    sessionProcessStartUtcTicks: snapshot.sessionProcessStartUtcTicks,
    total: snapshot.total, oldestLineNumber: snapshot.oldestLineNumber, records: snapshot.records };
  snapshot.tailSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function resealSession(session) {
  delete session.sessionEvidenceSha256;
  session.sessionEvidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(session));
}

function resealArtifactSet(set) {
  const payload = { schema: set.schema, slot: set.slot, appDataRoot: set.appDataRoot,
    artifacts: set.artifacts };
  set.setSha256 = Evidence.sha256Text(Evidence.canonicalJson(payload));
}

function resealDigest(value, field) {
  delete value[field];
  value[field] = Evidence.sha256Text(Evidence.canonicalJson(value));
}

function providerReceiptEntry(bundle, step) {
  const requestValue = bundle.control.requests.find((entry) => entry.step === step);
  const ack = bundle.control.acks.find((entry) => entry.requestId === requestValue.requestId);
  const filePath = path.join(bundle.runDir,
    ack.providerReceipt.artifact.replace(/\//g, path.sep));
  return { request: requestValue, ack, filePath,
    value: JSON.parse(fs.readFileSync(filePath, "utf8")) };
}

function providerCaptureEventEntry(bundle, step) {
  const provider = providerReceiptEntry(bundle, step);
  const reference = provider.value.captureEventRef;
  const filePath = path.join(bundle.runDir, reference.artifact.replace(/\//g, path.sep));
  return { provider, reference, filePath,
    value: JSON.parse(fs.readFileSync(filePath, "utf8")) };
}

function mutateProviderCaptureEvent(bundle, step, mutate, reseal) {
  const entry = providerCaptureEventEntry(bundle, step);
  mutate(entry.value, entry);
  if (reseal !== false) {
    entry.value.providerEventId = expectedProviderCaptureEventId(entry.value);
    resealDigest(entry.value, "eventSha256");
  }
  const bytes = Buffer.from(JSON.stringify(entry.value, null, 2) + "\n", "utf8");
  fs.writeFileSync(entry.filePath, bytes);
  entry.provider.value.captureEventRef = { artifact: entry.reference.artifact,
    sha256: Evidence.sha256Bytes(bytes), eventSha256: entry.value.eventSha256 };
  entry.provider.value.providerOperationId = expectedProviderOperationId(entry.provider.value);
  resealDigest(entry.provider.value, "receiptSha256");
  const providerBytes = Buffer.from(JSON.stringify(entry.provider.value, null, 2) + "\n", "utf8");
  fs.writeFileSync(entry.provider.filePath, providerBytes);
  entry.provider.ack.providerReceipt.sha256 = Evidence.sha256Bytes(providerBytes);
  return entry;
}

function mutateProviderReceipt(bundle, step, mutate, reseal) {
  const entry = providerReceiptEntry(bundle, step);
  mutate(entry.value, entry);
  if (reseal !== false) resealDigest(entry.value, "receiptSha256");
  const bytes = Buffer.from(JSON.stringify(entry.value, null, 2) + "\n", "utf8");
  fs.writeFileSync(entry.filePath, bytes);
  entry.ack.providerReceipt.sha256 = Evidence.sha256Bytes(bytes);
  return entry;
}

function mutateNativeInputEvent(bundle, step, mutate) {
  const provider = providerReceiptEntry(bundle, step);
  assert.strictEqual(provider.value.inputEvidence.kind, "native_input");
  const reference = provider.value.inputEvidence.eventRef;
  const eventPath = path.join(bundle.runDir, reference.artifact.replace(/\//g, path.sep));
  const eventValue = JSON.parse(fs.readFileSync(eventPath, "utf8"));
  mutate(eventValue, provider);
  resealDigest(eventValue, "eventSha256");
  const eventBytes = Buffer.from(JSON.stringify(eventValue, null, 2) + "\n", "utf8");
  fs.writeFileSync(eventPath, eventBytes);
  provider.value.inputEvidence.eventRef = {
    artifact: reference.artifact,
    sha256: Evidence.sha256Bytes(eventBytes),
    eventSha256: eventValue.eventSha256,
  };
  provider.value.providerOperationId = expectedProviderOperationId(provider.value);
  resealDigest(provider.value, "receiptSha256");
  const providerBytes = Buffer.from(JSON.stringify(provider.value, null, 2) + "\n", "utf8");
  fs.writeFileSync(provider.filePath, providerBytes);
  provider.ack.providerReceipt.sha256 = Evidence.sha256Bytes(providerBytes);
  return { provider, eventPath, eventValue };
}

function rebindProviderDomEvidence(bundle) {
  const bindings = {
    select_source: [bundle.transcripts.first, "button[data-physical-slot=\"7\"]", 0],
    preview_candidate_a: [bundle.transcripts.first,
      "button[data-candidate-key=\"" + Fixture.CANDIDATE_A.candidateKey + "\"]", 0],
    preview_candidate_b: [bundle.transcripts.first,
      "button[data-candidate-key=\"" + Fixture.CANDIDATE_B.candidateKey + "\"]", 0],
    commit_candidate_b: [bundle.transcripts.first,
      ".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]", 0],
    reselect_source: [bundle.transcripts.first, "button[data-physical-slot=\"7\"]", 1],
    close_first_tuning: [bundle.transcripts.first,
      "button[data-header-action=\"close\"]", 0],
    restart_select_source: [bundle.transcripts.restart,
      "button[data-physical-slot=\"7\"]", 0],
    restart_close_tuning: [bundle.transcripts.restart,
      "button[data-header-action=\"close\"]", 0],
  };
  Object.keys(bindings).forEach((step) => {
    const binding = bindings[step];
    const events = binding[0].events.filter((event) => event.kind === "dom_input"
      && event.target && event.target.selector === binding[1]);
    mutateProviderReceipt(bundle, step, (receipt) => {
      receipt.inputEvidence = domInputEvidence(binding[0].observerId, events[binding[2]]);
      receipt.providerOperationId = expectedProviderOperationId(receipt);
    });
  });
}

function mutateControlCapture(bundle, step, bytes) {
  const requestValue = bundle.control.requests.find((entry) => entry.step === step);
  const ack = bundle.control.acks.find((entry) => entry.requestId === requestValue.requestId);
  const filePath = path.join(bundle.runDir, ack.capture.relativePath.replace(/\//g, path.sep));
  fs.writeFileSync(filePath, bytes);
  const digest = Evidence.sha256Bytes(bytes);
  ack.capture.sha256 = digest;
  ack.capture.bytes = bytes.length;
  ack.captureSha256 = digest;
}

function mutateCandidateManifest(bundle, mutate) {
  const filePath = path.join(bundle.candidateRoot, "runtime", "cf7-runtime-manifest.tsv");
  const text = fs.readFileSync(filePath, "utf8").replace(/\r/g, "");
  assert.ok(text.endsWith("\n"));
  const lines = text.slice(0, -1).split("\n");
  mutate(lines);
  fs.writeFileSync(filePath, lines.join("\n") + "\n", "utf8");
}

function writeTranscriptArtifactFixture(bundle) {
  const manifest = new Map();
  persistPreSealSidecars(bundle);
  ["first", "restart"].forEach((phase) => {
    const prefix = "equipment-" + phase + "-passive-transcript";
    const summary = path.join(bundle.runDir, prefix + ".json");
    const jsonl = path.join(bundle.runDir, prefix + ".jsonl");
    fs.writeFileSync(summary, JSON.stringify(bundle.transcripts[phase], null, 2) + "\n", "utf8");
    fs.writeFileSync(jsonl, bundle.transcripts[phase].events
      .map((event) => JSON.stringify(event)).join("\n") + "\n", "utf8");
    manifest.set(prefix + ".json", { absolutePath: summary, role: "raw_transcript" });
    manifest.set(prefix + ".jsonl", { absolutePath: jsonl, role: "raw_transcript" });
  });
  const bundlePath = path.join(bundle.runDir, "journey-bundle.json");
  fs.writeFileSync(bundlePath, JSON.stringify(bundle, null, 2) + "\n", "utf8");
  manifest.set("journey-bundle.json", { absolutePath: bundlePath, role: "verified_input" });
  bundle.control.requests.forEach((requestValue) => {
    const relativePath = "control/requests/" + requestValue.requestId + ".json";
    manifest.set(relativePath, { absolutePath: path.join(bundle.runDir,
      relativePath.replace(/\//g, path.sep)), role: "control_request" });
  });
  bundle.control.acks.forEach((ack) => {
    const ackRelative = "control/acks/" + ack.requestId + ".json";
    manifest.set(ackRelative, { absolutePath: path.join(bundle.runDir,
      ackRelative.replace(/\//g, path.sep)), role: "control_ack" });
    manifest.set(ack.capture.relativePath, { absolutePath: path.join(bundle.runDir,
      ack.capture.relativePath.replace(/\//g, path.sep)), role: "provider_capture",
    sha256: ack.capture.sha256, bytes: ack.capture.bytes });
    manifest.set(ack.providerReceipt.artifact, {
      absolutePath: path.join(bundle.runDir,
        ack.providerReceipt.artifact.replace(/\//g, path.sep)),
      role: "provider_receipt",
    });
    const provider = JSON.parse(fs.readFileSync(path.join(bundle.runDir,
      ack.providerReceipt.artifact.replace(/\//g, path.sep)), "utf8"));
    manifest.set(provider.captureEventRef.artifact, { absolutePath: path.join(bundle.runDir,
      provider.captureEventRef.artifact.replace(/\//g, path.sep)),
    role: "provider_capture_event" });
    if (provider.inputEvidence && provider.inputEvidence.kind === "native_input") {
      const relativePath = provider.inputEvidence.eventRef.artifact;
      manifest.set(relativePath, { absolutePath: path.join(bundle.runDir,
        relativePath.replace(/\//g, path.sep)), role: "native_input_event" });
    }
  });
  [
    ["evidence/host-first-final-log.json", "host_log_snapshot"],
    ["evidence/host-restart-final-log.json", "host_log_snapshot"],
    ["evidence/persistence.json", "persistence_evidence"],
  ].forEach(([relativePath, role]) => {
    manifest.set(relativePath, { absolutePath: path.join(bundle.runDir,
      relativePath.replace(/\//g, path.sep)), role });
  });
  manifest.forEach((entry) => {
    const bytes = fs.readFileSync(entry.absolutePath);
    entry.bytes = bytes.length;
    entry.sha256 = Evidence.sha256Bytes(bytes);
  });
  return manifest;
}

function runSelfTests() {
  const positives = [];
  const negatives = [];
  let browserGateReceipt = null;
  function positive(name, body) {
    body();
    positives.push(name);
  }
  function negative(name, expectedCode, mutate) {
    const bundle = Fixture.buildValidBundle();
    mutate(bundle);
    assert.throws(() => verifySemanticBundle(bundle, {
      testOnlyAllowInjectedEvidence: true, skipFileClosure: true,
    }), (error) => {
      if (!error || error.code !== expectedCode) {
        throw new Error(name + " expected " + expectedCode + " but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push(name);
  }
  function negativeArtifact(name, expectedCode, mutate) {
    const bundle = Fixture.buildValidBundle();
    const manifest = writeTranscriptArtifactFixture(bundle);
    mutate(bundle, manifest);
    assert.throws(() => verifyTranscriptArtifacts(bundle, manifest), (error) => {
      if (!error || error.code !== expectedCode) {
        throw new Error(name + " expected " + expectedCode + " but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push(name);
  }
  function negativePreSeal(name, expectedCode, mutate) {
    const bundle = Fixture.buildValidBundle();
    const manifest = writeTranscriptArtifactFixture(bundle);
    const freeze = capturePreSealArtifactFreeze(bundle);
    mutate(bundle, freeze, manifest);
    assert.throws(() => verifyPreSealArtifactFreeze(bundle, freeze, manifest), (error) => {
      if (!error || error.code !== expectedCode) {
        throw new Error(name + " expected " + expectedCode + " but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push(name);
  }
  function negativeUsage(name, body) {
    assert.throws(body, (error) => error && error.isUsageError === true);
    negatives.push(name);
  }
  function negativeContract(name, expectedCode, body) {
    assert.throws(body, (error) => error && error.code === expectedCode);
    negatives.push(name);
  }
  function negativeProductionClosure(name, expectedCode, mutate) {
    const closure = ProductionClosure.captureProductionClosure(REPOSITORY_ROOT,
      "2026-08-04T00:00:00.000Z");
    mutate(closure);
    assert.throws(() => ProductionClosure.verifyProductionClosure(
      REPOSITORY_ROOT, closure), (error) => {
      if (!error || error.code !== expectedCode) {
        throw new Error(name + " expected " + expectedCode + " but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push(name);
  }
  function negativeCandidateProducer(name, expectedCode, mutate) {
    const bundle = Fixture.buildValidBundle();
    const identity = bundle.runtime.first.identity;
    mutate(bundle, identity);
    assert.throws(() => ProductionClosure.captureCandidateProducerBinding(
      bundle.candidateRoot, identity, bundle.productionClosure), (error) => {
      if (!error || error.code !== expectedCode) {
        throw new Error(name + " expected " + expectedCode + " but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push(name);
  }

  positive("valid two-process install-mod journey is admitted semantically", () => {
    const result = verifySemanticBundle(Fixture.buildValidBundle(), {
      testOnlyAllowInjectedEvidence: true, skipFileClosure: true,
    });
    assert.strictEqual(result.first.candidateB.candidateKey, Fixture.CANDIDATE_B.candidateKey);
    assert.notStrictEqual(result.first.candidateB.candidateKey,
      IdentityFixture.allDistinct[0].candidateKey,
      "canonical fixture selectors must not be mistaken for production wire candidate keys");
  });
  positive("canonical executes the production Equipment browser matrix under a child closure", () => {
    const browserBootstrap = path.join(__dirname, "browser-bootstrap.js");
    const browserSource = fs.readFileSync(browserBootstrap, "utf8");
    assert(browserSource.includes(
      "RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest, artifact:journal })"));
    assert(browserSource.includes("verifyServedResourceClosure({"));
    assert(browserSource.includes("browserExecutableReceipt({"));
    const moduleInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
      "browser-module-inventory.v1.json"), "utf8"));
    assert.strictEqual(moduleInventory.schema,
      "workbench-live-e2e.equipment.browser-module-inventory.v1");
    assert.strictEqual(moduleInventory.nodeVersion, process.version);
    assert.strictEqual(moduleInventory.files.length, 280);
    assert.strictEqual(moduleInventory.builtins.length, 23);
    assert(moduleInventory.files.includes("tools/run-equipment-tuning-harness.js"));
    const resourceInventory = JSON.parse(fs.readFileSync(path.join(__dirname,
      "browser-resource-inventory.v1.json"), "utf8"));
    assert.strictEqual(resourceInventory.schema,
      "workbench-live-e2e.browser-resource-inventory.v1");
    assert.strictEqual(resourceInventory.files.length, 39);
    assert.strictEqual(resourceInventory.optionalFiles, undefined);
    assert(resourceInventory.files.includes("modules/equipment-tuning/dev/harness.html"));
    assert(resourceInventory.files.includes("modules/equipment-tuning-view.js"));
    assert(resourceInventory.files.includes("modules/equipment-tuning-loadout-lifecycle.js"));
    assert.deepStrictEqual(resourceInventory.files, resourceInventory.files.slice().sort());
    const child = childProcess.spawnSync(process.execPath, [browserBootstrap], {
      cwd:REPOSITORY_ROOT, encoding:"utf8", windowsHide:true,
      timeout:180000, maxBuffer:32 * 1024 * 1024,
    });
    assert.strictEqual(child.error, undefined, child.error && child.error.message);
    assert.strictEqual(child.signal, null);
    assert.strictEqual(child.status, 0, String(child.stderr || child.stdout));
    assert.strictEqual(child.stderr, "");
    const lines = child.stdout.split(/\r?\n/).filter(Boolean);
    assert.strictEqual(lines.length, 1, child.stdout);
    const receipt = JSON.parse(lines[0]);
    const receiptDigest = receipt.evidenceSha256;
    delete receipt.evidenceSha256;
    assert.strictEqual(Evidence.sha256Text(Evidence.canonicalJson(receipt)), receiptDigest);
    assert.strictEqual(receipt.schema,
      "workbench-live-e2e.equipment.browser-gate-receipt.v1");
    assert.strictEqual(receipt.status, "OFFLINE_VERIFIED");
    assert.strictEqual(receipt.moduleAdmission, "ADMITTED");
    assert.strictEqual(receipt.journalVerification, "VERIFIED");
    assert.strictEqual(receipt.moduleEntryCount, 325);
    assert.deepStrictEqual(receipt.result.viewports, [
      {width:1024,height:576}, {width:1366,height:768}, {width:1920,height:1080},
    ]);
    assert.strictEqual(receipt.result.checkCount, 129);
    assert.strictEqual(receipt.result.checkNamesSha256.length, 3);
    assert.strictEqual(new Set(receipt.result.checkNamesSha256).size, 1);
    receipt.result.checkNamesSha256.forEach((digest) =>
      assert.strictEqual(digest, moduleInventory.expectedCheckNamesSha256));
    assert.deepStrictEqual(receipt.result.criticalChecks.map((entry) => entry.name), [
      "isolated candidate projection preserves visible bag request and window",
      "right-pane convert target click previews immediately with exact inventory authority",
      "three all-distinct identity fixtures preserve display and icon roles",
      "tooltip-first response interleave preserves candidate activation and adopts the preview token",
      "commit holds the same inventory write capability through refresh",
      "blocked candidate remains keyboard-readable and activation only explains its reason",
      "definitive stale lease refreshes inventory before rebinding snapshot",
      "pending tuning write blocks close/rebind",
      "ambiguous commit is not replayed",
      "layout stays inside host",
    ]);
    assert(receipt.result.criticalChecks.every((entry) => entry.ok === true));
    assert.strictEqual(receipt.result.motionProof.pass, true);
    assert.strictEqual(receipt.servedResourceClosure.requiredResourceCount, 38);
    assert.strictEqual(receipt.servedResourceClosure.allowedResourceCount, 38);
    assert.strictEqual(receipt.servedResourceClosure.resourceCount, 38);
    assert.strictEqual(receipt.servedResourceClosure.occurrenceCount, 115);
    assert.strictEqual(receipt.servedResourceClosure.failureCount, 1);
    assert(receipt.browserBinary && receipt.browserBinary.locator.startsWith("external:")
      && /^[a-f0-9]{64}$/.test(receipt.browserBinary.sha256)
      && Number.isInteger(receipt.browserBinary.bytes) && receipt.browserBinary.bytes > 0);
    assert(/^[a-f0-9]{64}$/.test(receipt.result.resultSha256));
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
  positive("raw Web diagnostic keys become whole-key named digest references", () => {
    const sourceKey = "inventory:背包:7:opaque-lease";
    const intentKey = "install_mod|candidate|";
    const clean = redactAuthority({ sourceKey, intentKey });
    assert.deepStrictEqual(clean, {
      sourceKeyRef: tokenRef(sourceKey), intentKeyRef: tokenRef(intentKey),
    });
    const refShapedRaw = "sha256_0123456789abcdef01234567";
    const refShapedClean = redactAuthority({ tuningToken: refShapedRaw });
    assert.strictEqual(refShapedClean.tuningToken,
      "sha256_" + Evidence.sha256Text(refShapedRaw).slice(0, 24));
    assert.notStrictEqual(refShapedClean.tuningToken, refShapedRaw,
      "raw authority must be hashed even when its spelling already resembles a reference");
    const malformedClean = redactAuthority({ transactionId: { nested: "secret" },
      expectedLease: 7, sourceKey: { nested: "source-secret" } });
    assert.ok(Object.values(malformedClean).every((value) =>
      /^sha256_[a-f0-9]{24}$/.test(value)));
    assert.ok(!JSON.stringify(malformedClean).includes("secret"));
  });
  positive("persisted transcript JSON and JSONL are exactly bundle-bound", () => {
    const bundle = Fixture.buildValidBundle();
    assert.strictEqual(verifyTranscriptArtifacts(bundle,
      writeTranscriptArtifactFixture(bundle)), true);
  });
  positive("production Web Host AS2 data and SWF bytes form one exact current-tree closure", () => {
    const closure = ProductionClosure.captureProductionClosure(REPOSITORY_ROOT,
      "2026-08-04T00:00:00.000Z");
    const descriptors = ProductionClosure.productionFiles(REPOSITORY_ROOT);
    assert.deepStrictEqual(closure.files.map((entry) => entry.locator),
      descriptors.map((entry) => "root:" + entry.relativePath));
    assert.strictEqual(ProductionClosure.verifyProductionClosure(REPOSITORY_ROOT, closure), closure);
  });
  positive("production closure exactly covers current Workbench and tuning lazy declarations", () => {
    const lazyRegistry = fs.readFileSync(path.join(REPOSITORY_ROOT,
      "launcher/web/modules/panels-lazy-registry.js"), "utf8");
    const workbenchStart = lazyRegistry.indexOf("Panels.registerLazy('workbench'");
    const workbenchEnd = lazyRegistry.indexOf("noop);", workbenchStart);
    assert.ok(workbenchStart >= 0 && workbenchEnd > workbenchStart);
    const declaredWorkbench = Array.from(lazyRegistry.slice(workbenchStart, workbenchEnd)
      .matchAll(/['"](modules\/[^'"]+\.js)['"]/g))
      .map((match) => "launcher/web/" + match[1]);
    const featureLoader = fs.readFileSync(path.join(REPOSITORY_ROOT,
      "launcher/web/modules/inventory-workbench-feature-loader.js"), "utf8");
    const tuningStart = featureLoader.indexOf("var TUNING_DEPS = [");
    const tuningEnd = featureLoader.indexOf("];", tuningStart);
    assert.ok(tuningStart >= 0 && tuningEnd > tuningStart);
    const declaredTuning = Array.from(featureLoader.slice(tuningStart, tuningEnd)
      .matchAll(/['"](modules\/[^'"]+\.js)['"]/g))
      .map((match) => "launcher/web/" + match[1]);
    assert.deepStrictEqual(declaredWorkbench, ProductionClosure.WORKBENCH_LAZY_WEB);
    assert.deepStrictEqual(declaredTuning, ProductionClosure.TUNING_LAZY_WEB);
    ["launcher/src/Guardian/PanelHostController.cs",
      "launcher/src/Guardian/PanelRequestOwnerLifecycle.cs",
      "launcher/src/Tasks/PanelBridge.cs",
      "launcher/src/Guardian/LogManager.cs",
      "launcher/src/Bus/XmlSocketServer.cs"].forEach((relativePath) => {
      assert.ok(ProductionClosure.HOST_FILES.includes(relativePath));
    });
    const styles = ProductionClosure.verifyOverlayStyleInventory(REPOSITORY_ROOT);
    assert.deepStrictEqual(styles.overlayStyles, ProductionClosure.OVERLAY_STYLE_WEB);
    assert.deepStrictEqual(styles.panelStyles, ProductionClosure.PANELS_IMPORT_STYLE_WEB);
    const closure = ProductionClosure.captureProductionClosure(REPOSITORY_ROOT,
      "2026-08-04T00:00:00.000Z");
    assert.strictEqual(closure.files.length, 159);
    assert.strictEqual(ProductionClosure.scriptFiles(closure).length, 55);
    assert.strictEqual(ProductionClosure.styleFiles(closure).length, 27);
    assert.strictEqual(closure.pageResourceContract.fixedImages.length, 15);
    assert.strictEqual(closure.pageResourceContract.conditionalAssets.length, 4);
    assert.strictEqual(closure.pageResourceContract.fonts.length, 13);
    assert.strictEqual(closure.pageResourceContract.iconRoutes.length, 1575);
    assert.strictEqual(closure.producerInputs.domains.artifactSource.files.some((entry) =>
      entry.relativePath === "launcher/src/Tasks/EquipmentTuningTask.cs"), true);
    assert.strictEqual(closure.producerInputs.domains.producerRecipe.files.some((entry) =>
      entry.relativePath === "launcher/build-runtime-candidate.ps1"), true);
    assert.strictEqual(closure.producerInputs.domains.toolchainLock.files.some((entry) =>
      entry.relativePath === "config/build/runtime-toolchain.lock.json"), true);
  });
  positive("candidate producer binds authenticated process and Core as distinct exact payload rows",
    () => {
      const bundle = Fixture.buildValidBundle();
      const binding = bundle.candidateProducer.runtimeFileBinding;
      assert.strictEqual(binding.processPath, path.resolve(bundle.runtime.first.identity.processPath));
      assert.strictEqual(binding.process.path,
        "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe");
      assert.strictEqual(binding.core.path,
        "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll");
      assert.notStrictEqual(binding.process.sha256, binding.core.sha256);
      assert.strictEqual(bundle.candidateProducer.runtimeFileBindingSha256,
        Evidence.sha256Text(Evidence.canonicalJson(binding)));
    });
  positive("preview adoption may be observed before the raw inbound response", () => {
    const bundle = Fixture.buildValidBundle();
    const events = bundle.transcripts.first.events;
    placeBefore(events, diagnostic(bundle, "preview_adopted", 0),
      response(bundle, "first", "equipment_tuning", "preview", 0));
    resealTranscript(bundle.transcripts.first);
    rebindProviderDomEvidence(bundle);
    verifySemanticBundle(bundle, {
      testOnlyAllowInjectedEvidence: true, skipFileClosure: true,
    });
  });
  positive("commit adoption may be observed before the raw inbound response", () => {
    const bundle = Fixture.buildValidBundle();
    const events = bundle.transcripts.first.events;
    placeBefore(events, diagnostic(bundle, "commit_adopted", 0),
      response(bundle, "first", "equipment_tuning", "commit", 0));
    resealTranscript(bundle.transcripts.first);
    rebindProviderDomEvidence(bundle);
    verifySemanticBundle(bundle, {
      testOnlyAllowInjectedEvidence: true, skipFileClosure: true,
    });
  });
  positive("provider timing uses observer receipt time rather than pageTime", () => {
    const bundle = Fixture.buildValidBundle();
    bundle.transcripts.first.events.filter((event) => event.kind === "dom_input")
      .forEach((event, index) => { event.pageTime = index + 1; });
    bundle.transcripts.restart.events.filter((event) => event.kind === "dom_input")
      .forEach((event, index) => { event.pageTime = index + 1; });
    resealTranscript(bundle.transcripts.first);
    resealTranscript(bundle.transcripts.restart);
    rebindProviderDomEvidence(bundle);
    verifySemanticBundle(bundle, {
      testOnlyAllowInjectedEvidence: true, skipFileClosure: true,
    });
  });
  positive("pre-exit checkpoints admit an open observer without weakening final closure", () => {
    const bundle = Fixture.buildValidBundle();
    bundle.transcripts.first.events = bundle.transcripts.first.events.filter((event) =>
      !["observer_detached", "observer_detach_transport_lost"].includes(event.kind));
    bundle.transcripts.restart.events = bundle.transcripts.restart.events.filter((event) =>
      !["observer_detached", "observer_detach_transport_lost"].includes(event.kind));
    resealTranscript(bundle.transcripts.first);
    resealTranscript(bundle.transcripts.restart);
    const first = Protocol.verifyFirstTranscript(bundle.transcripts.first, {
      requireObserverDetached: false,
    });
    const restart = Protocol.verifyRestartTranscript(bundle.transcripts.restart, first, {
      requireObserverDetached: false,
    });
    assert.strictEqual(restart.readback.equipment.raw.mods[0], Fixture.CANDIDATE_B.itemName);
  });
  positive("one exact production Host timestamp prefix is required and accepted", () => {
    verifySemanticBundle(Fixture.buildValidBundle(), {
      testOnlyAllowInjectedEvidence: true, skipFileClosure: true,
    });
  });
  positive("non-authority transcript metadata cannot authorize or poison icon routes", () => {
    const bundle = Fixture.buildValidBundle();
    bundle.transcripts.first.icon = "fixture_icon_absent_from_manifest";
    verifySemanticBundle(bundle, {
      testOnlyAllowInjectedEvidence: true, skipFileClosure: true,
    });
  });
  positive("one exact Host midnight rollover is reconstructed monotonically", () => {
    const snapshotValue = hostTimelineSnapshot("2026-08-04T00:00:02.000+08:00",
      ["23:59:59.900", "00:00:00.050", "00:00:01.000"]);
    const timeline = Protocol.resolveHostTimeline(snapshotValue, "midnight_fixture");
    assert.ok(Date.parse(timeline[0].observedAt) < Date.parse(timeline[1].observedAt));
    assert.ok(Date.parse(timeline[1].observedAt) < Date.parse(timeline[2].observedAt));
  });
  positive("pre-seal projection digest binds business fields and provider evidence", () => {
    const business = Fixture.buildValidBundle();
    const businessDigest = semanticDigest(business);
    business.persistence.diskInitial.equipment.level += 1;
    assert.notStrictEqual(semanticDigest(business), businessDigest);
    const provider = Fixture.buildValidBundle();
    const providerDigest = semanticDigest(provider);
    mutateProviderCaptureEvent(provider, "select_source", (event) => {
      event.capturedAt = "2026-08-03T00:10:03.500Z";
    });
    assert.notStrictEqual(semanticDigest(provider), providerDigest);
  });
  positive("pre-seal freeze binds every exact raw artifact and final manifest row", () => {
    const bundle = Fixture.buildValidBundle();
    const manifest = writeTranscriptArtifactFixture(bundle);
    const freeze = capturePreSealArtifactFreeze(bundle);
    assert.strictEqual(verifyPreSealArtifactFreeze(bundle, freeze, manifest), true);
    assert.strictEqual(freeze.entries.filter((entry) => entry.role === "control_request").length,
      12);
    assert.strictEqual(freeze.entries.filter((entry) => entry.role === "provider_receipt").length,
      12);
    assert.strictEqual(freeze.entries.filter((entry) => entry.role === "control_ack").length, 12);
    assert.strictEqual(freeze.entries.filter((entry) => entry.role === "provider_capture").length,
      12);
    assert.strictEqual(freeze.entries.filter((entry) => entry.role === "provider_capture_event")
      .length, 12);
    assert.strictEqual(freeze.entries.filter((entry) => entry.role === "native_input_event").length,
      4);
  });
  positive("strict PNG decoder reconstructs the full canonical capture", () => {
    const decoded = decodePng(Fixture.fixturePng(101));
    assert.deepStrictEqual([decoded.width, decoded.height], [320, 180]);
    assert.strictEqual(decoded.pixelBytes, 320 * 180 * 3);
    assert.match(decoded.pixelSha256, /^[a-f0-9]{64}$/);
  });
  positive("indexed PNG decoder unpacks palette samples at 1 2 4 and 8 bits", () => {
    [1, 2, 4, 8].forEach((bitDepth) => {
      const paletteEntries = 2 ** bitDepth;
      const decoded = decodePng(indexedPng(bitDepth, paletteEntries, paletteEntries - 1));
      assert.deepStrictEqual([decoded.width, decoded.height], [320, 180]);
      assert.strictEqual(decoded.pixelBytes, Math.ceil(320 * bitDepth / 8) * 180);
      assert.strictEqual(decoded.paletteEntries, paletteEntries);
      assert.strictEqual(decoded.maximumPaletteIndex, paletteEntries - 1);
    });
  });
  positive("ack helper help is one bounded non-business mode", () => {
    assert.strictEqual(AckControl.parseArgs(["--help"]).help, true);
  });
  positive("ack writer only references one provider-prewritten tool result", () => {
    const runDir = path.join(Fixture.ROOT, "tmp", "workbench-live-e2e", "equipment",
      "ack-writer-fixture");
    fs.mkdirSync(runDir);
    const channel = new ControlChannel(Fixture.ROOT, runDir);
    const requestValue = channel.issue("open_tuning", {
      timeoutMs: 60000,
      allowedTransports: ["codex_computer_use"],
      instructions: "fixture open tuning",
      selectors: ["native HUD equipment tuning entry"],
      expectedIndependentEvidence: ["fixture provider tool result"],
    });
    const receipt = { schema: PROVIDER_RECEIPT_SCHEMA, runId: channel.runId,
      requestId: requestValue.requestId, step: requestValue.step,
      transport: "codex_computer_use", issuer: "codex_computer_use",
      toolResultSource: "codex_computer_use_tool_result",
      requestSha256: Evidence.sha256File(channel.requestPath(requestValue.requestId)),
      providerOperationId: "pending", action: requestValue.step,
      result: "completed",
      startedAt: new Date(Date.parse(requestValue.issuedAt) + 1).toISOString(),
      inputEvidence: { kind: "native_input", eventRef: null, eventType: "click",
        isTrusted: true, selector: requestValue.selectors[0], tagName: "NATIVE",
        visible: true, enabled: true, viewport: { width: 1600, height: 900 },
        rect: { left: 20, top: 20, right: 140, bottom: 60, width: 120, height: 40 },
        clientPoint: { x: 80, y: 40 }, hitTargetMatches: true,
        key: null, button: 0, repeat: false,
        observedAt: new Date(Date.parse(requestValue.issuedAt) + 2).toISOString() },
      completedAt: new Date(Date.parse(requestValue.issuedAt) + 4).toISOString(),
      ownedArtifact: "control/provider-receipts/" + requestValue.requestId + ".json",
      captureEventRef: null };
    const eventValue = Object.assign({ schema: NATIVE_INPUT_EVENT_SCHEMA,
      runId: channel.runId, requestId: requestValue.requestId, step: requestValue.step,
      observedAt: requestValue.issuedAt, receivedAt: receipt.inputEvidence.observedAt },
    Object.fromEntries(["eventType", "isTrusted", "selector", "tagName", "visible", "enabled",
      "viewport", "rect", "clientPoint", "hitTargetMatches", "key", "button", "repeat"]
      .map((field) => [field, receipt.inputEvidence[field]])));
    eventValue.eventSha256 = Evidence.sha256Text(Evidence.canonicalJson(eventValue));
    const eventPath = path.join(channel.nativeInputEventsDir, requestValue.requestId + ".json");
    const eventBytes = Buffer.from(JSON.stringify(eventValue, null, 2) + "\n", "utf8");
    fs.writeFileSync(eventPath, eventBytes);
    receipt.inputEvidence.eventRef = {
      artifact: "control/native-input-events/" + requestValue.requestId + ".json",
      sha256: Evidence.sha256Bytes(eventBytes), eventSha256: eventValue.eventSha256,
    };
    const captureBytes = Fixture.fixturePng(99);
    const capturePath = path.join(channel.capturesDir, requestValue.requestId + ".png");
    fs.writeFileSync(capturePath, captureBytes);
    const capturedAt = new Date(Date.parse(requestValue.issuedAt) + 3).toISOString();
    fs.utimesSync(capturePath, new Date(capturedAt), new Date(capturedAt));
    const captureEvent = { schema: PROVIDER_CAPTURE_EVENT_SCHEMA, runId: channel.runId,
      requestId: requestValue.requestId, step: requestValue.step,
      transport: "codex_computer_use", issuer: "codex_computer_use",
      toolResultSource: "codex_computer_use_tool_result", providerEventId: "pending",
      requestSha256: receipt.requestSha256,
      captureArtifact: "control/captures/" + requestValue.requestId + ".png",
      capturedAt, fileModifiedAt: fs.statSync(capturePath).mtime.toISOString(),
      captureBytes: captureBytes.length, captureSha256: Evidence.sha256Bytes(captureBytes),
      captureWidth: 320, captureHeight: 180,
      captureSemanticContentIndependentlyVerified: false };
    captureEvent.providerEventId = expectedProviderCaptureEventId(captureEvent);
    captureEvent.eventSha256 = Evidence.sha256Text(Evidence.canonicalJson(captureEvent));
    const captureEventBytes = Buffer.from(JSON.stringify(captureEvent, null, 2) + "\n", "utf8");
    fs.writeFileSync(path.join(channel.captureEventsDir, requestValue.requestId + ".json"),
      captureEventBytes);
    receipt.captureEventRef = {
      artifact: "control/capture-events/" + requestValue.requestId + ".json",
      sha256: Evidence.sha256Bytes(captureEventBytes), eventSha256: captureEvent.eventSha256,
    };
    receipt.providerOperationId = expectedProviderOperationId(receipt);
    receipt.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
    const receiptPath = path.join(channel.providerReceiptsDir, requestValue.requestId + ".json");
    fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2) + "\n", "utf8");
    const before = Evidence.sha256File(receiptPath);
    const written = writeAck(Fixture.ROOT, runDir, requestValue.requestId, {
      transport: "codex_computer_use", result: "completed",
      providerReceiptArtifact: receiptPath, authorizationDecisionId: null,
    });
    assert.strictEqual(Evidence.sha256File(receiptPath), before);
    assert.deepStrictEqual(written.ack.providerReceipt, {
      artifact: "control/provider-receipts/" + requestValue.requestId + ".json",
      sha256: before,
    });
  });
  negativeUsage("ack helper help cannot mix with business arguments", () => {
    AckControl.parseArgs(["--help", "--run-dir", "owned"]);
  });
  negativeContract("Host ordinary time-of-day regression is rejected",
    "host_timeline_regression", () => {
      Protocol.resolveHostTimeline(hostTimelineSnapshot("2026-08-04T12:00:02.000+08:00",
        ["12:00:01.000", "11:59:59.000"]), "ordinary_regression_fixture");
    });
  negativeContract("Host second midnight rollover is rejected",
    "host_timeline_regression", () => {
      Protocol.resolveHostTimeline(hostTimelineSnapshot("2026-08-06T00:00:02.000+08:00",
        ["23:59:59.000", "00:00:00.000", "23:59:59.500", "00:00:01.000"]),
      "second_rollover_fixture");
    });
  negativeContract("PNG rejects compressed-stream trailing junk",
    "control_capture_media_invalid", () => {
      decodePng(rewritePng(Fixture.fixturePng(102), (chunks) => {
        const idat = chunks.find((entry) => entry.type === "IDAT");
        idat.data = Buffer.concat([idat.data, Buffer.from([0xde, 0xad, 0xbe, 0xef])]);
      }));
    });
  negativeContract("PNG rejects a truncated compressed stream",
    "control_capture_media_invalid", () => {
      decodePng(rewritePng(Fixture.fixturePng(103), (chunks) => {
        const idat = chunks.find((entry) => entry.type === "IDAT");
        idat.data = idat.data.subarray(0, idat.data.length - 1);
      }));
    });
  negativeContract("PNG rejects an invalid reconstructed row filter",
    "control_capture_media_invalid", () => {
      decodePng(rewritePng(Fixture.fixturePng(104), (chunks) => {
        const idat = chunks.find((entry) => entry.type === "IDAT");
        const rows = zlib.inflateSync(idat.data);
        rows[0] = 5;
        idat.data = zlib.deflateSync(rows);
      }));
    });
  negativeContract("indexed PNG rejects a 1-bit palette index outside PLTE",
    "control_capture_media_invalid", () => {
      decodePng(indexedPng(1, 1, 1));
    });
  negativeContract("indexed PNG rejects a 2-bit palette index outside PLTE",
    "control_capture_media_invalid", () => {
      decodePng(indexedPng(2, 2, 2));
    });
  negativeContract("indexed PNG rejects a 4-bit palette index outside PLTE",
    "control_capture_media_invalid", () => {
      decodePng(indexedPng(4, 3, 3));
    });
  negativeContract("indexed PNG rejects an 8-bit palette index outside PLTE",
    "control_capture_media_invalid", () => {
      decodePng(indexedPng(8, 4, 4));
    });
  negativeContract("valid 16x16 PNG remains below capture dimensions",
    "control_capture_media_invalid", () => {
      decodePng(rewritePng(Fixture.fixturePng(105), (chunks) => {
        const ihdr = chunks.find((entry) => entry.type === "IHDR");
        ihdr.data.writeUInt32BE(16, 0);
        ihdr.data.writeUInt32BE(16, 4);
      }));
    });
  STRICT_GLOBAL_BOUNDARY_LABELS.slice(1).forEach((label, index) => {
    const previousLabel = STRICT_GLOBAL_BOUNDARY_LABELS[index];
    negativeContract("strict global boundary rejects " + previousLabel + " >= " + label,
      "global_partial_order_invalid", () => {
        const boundaries = STRICT_GLOBAL_BOUNDARY_LABELS.map((name, boundaryIndex) => [name,
          new Date(Date.UTC(2026, 7, 4, 0, 0, boundaryIndex)).toISOString()]);
        boundaries[index + 1][1] = boundaries[index][1];
        assertStrictBoundaryChain(boundaries);
      });
  });

  negativeUsage("ack helper rejects duplicate arguments", () => {
    AckControl.parseArgs(["--result", "completed", "--result", "completed"]);
  });
  negativeUsage("ack helper requires one provider-prewritten receipt", () => {
    AckControl.main(["--run-dir", "owned", "--request-id", "request",
      "--transport", "codex_computer_use", "--result", "completed"]);
  });
  negativeContract("ack writer rejects inline provider-like input",
    "control_ack_input_invalid", () => {
      writeAck(Fixture.ROOT, Fixture.RUN_DIR, "fixture-open_tuning", {
        transport: "codex_computer_use", result: "completed",
        providerReceiptArtifact: "control/provider-receipts/fixture-open_tuning.json",
        providerOperationId: "forbidden-inline-result",
      });
    });
  {
    const bundle = Fixture.buildValidBundle();
    bundle.evidenceMode = "live_capture";
    bundle.fixtureProvenance = null;
    bundle.safeExitUiJourneyVerified = true;
    bundle.exitMethod = "native_safe_exit_then_exit_confirm";
    assert.throws(() => verifySemanticBundle(bundle), (error) => {
      if (!error || error.code !== "bundle_root_mismatch") {
        throw new Error("foreign verifier root expected bundle_root_mismatch but received "
          + (error && error.code) + ": " + (error && error.message));
      }
      return true;
    });
    negatives.push("full verification rejects a foreign repository root");
  }

  negativeProductionClosure("production closure path set is closed",
    "production_closure_invalid", (closure) => {
      closure.files.pop();
      resealProductionClosure(closure);
    });
  negativeProductionClosure("production closure aggregate digest is exact",
    "production_closure_digest_invalid", (closure) => {
      closure.closureSha256 = "0".repeat(64);
    });
  negativeProductionClosure("production closure hash is bound to current tree",
    "production_closure_current_tree_mismatch", (closure) => {
      closure.files[0].sha256 = "0".repeat(64);
      resealProductionClosure(closure);
    });
  negativeProductionClosure("production closure byte count is bound to current tree",
    "production_closure_current_tree_mismatch", (closure) => {
      closure.files[0].bytes += 1;
      resealProductionClosure(closure);
    });
  negativeProductionClosure("production closure cannot omit one Overlay stylesheet",
    "production_closure_invalid", (closure) => {
      const index = closure.files.findIndex((entry) =>
        entry.locator === "root:launcher/web/css/workbench/equipment-tuning.css");
      assert.ok(index >= 0);
      closure.files.splice(index, 1);
      resealProductionClosure(closure);
    });
  negativeProductionClosure("current Host source byte replacement is rejected",
    "production_closure_current_tree_mismatch", (closure) => {
      const entry = closure.files.find((file) =>
        file.locator === "root:launcher/src/Tasks/EquipmentTuningTask.cs");
      assert.ok(entry);
      entry.sha256 = "0".repeat(64);
      resealProductionClosure(closure);
    });
  negativeProductionClosure("runtime producer input evidence is bound to current source bytes",
    "production_producer_inputs_current_tree_mismatch", (closure) => {
      const domain = closure.producerInputs.domains.artifactSource;
      const source = domain.files.find((entry) =>
        entry.relativePath === "launcher/src/Tasks/EquipmentTuningTask.cs");
      assert.ok(source);
      source.sha256 = "0".repeat(64);
      domain.fingerprintSha256 = Evidence.sha256Text(Evidence.canonicalJson(domain.files));
      resealProducerInputs(closure.producerInputs);
      resealProductionClosure(closure);
    });
  negativeProductionClosure("Page resource routes are recomputed from the current tree",
    "page_resource_contract_current_tree_mismatch", (closure) => {
      closure.pageResourceContract.fixedImages[0].sha256 = "0".repeat(64);
      resealPageResourceContract(closure.pageResourceContract);
      resealProductionClosure(closure);
    });
  negative("first loaded page bytes must match the production closure",
    "loaded_production_resource_mismatch", (b) => {
      replaceRawSource(b.runtime.first.loadedProduction.resourceOccurrences[0],
        "<!doctype html><title>changed</title>");
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("restart loaded script multiset is exact",
    "loaded_production_script_occurrence_invalid", (b) => {
      b.runtime.restart.loadedProduction.scriptOccurrences.splice(1, 1);
      resealLoadedProduction(b.runtime.restart.loadedProduction);
    });
  negative("loaded script digest is exact", "loaded_production_script_source_binding_invalid", (b) => {
    replaceRawSource(b.runtime.first.loadedProduction.scriptOccurrences[1], "changed script");
    resealLoadedProduction(b.runtime.first.loadedProduction);
  });
  negative("loaded script order is exact", "loaded_production_script_occurrence_invalid", (b) => {
    const scripts = b.runtime.first.loadedProduction.scriptOccurrences;
    [scripts[1], scripts[2]] = [scripts[2], scripts[1]];
    scripts.forEach((entry, index) => { entry.occurrence = index + 1; });
    resealLoadedProduction(b.runtime.first.loadedProduction);
  });
  negative("actual-loaded script URL inventory rejects an extra producer",
    "loaded_production_script_occurrence_invalid", (b) => {
      const values = b.runtime.first.loadedProduction.scriptOccurrences;
      const extra = clone(values[1]);
      extra.occurrence = values.length + 1;
      extra.url = "https://overlay.local/modules/foreign-equipment-producer.js";
      extra.origin = "https://overlay.local";
      extra.scriptId = "foreign-extra-script";
      extra.rawParams.scriptId = extra.scriptId;
      extra.rawParams.url = extra.url;
      values.push(extra);
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("loaded stylesheet multiset cannot omit one import",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const index = loaded.resourceOccurrences.findIndex((entry) =>
        entry.resourceType === "Stylesheet");
      loaded.resourceOccurrences.splice(index, 1);
      loaded.resourceOccurrences.forEach((entry, position) => { entry.occurrence = position + 1; });
      resealLoadedProduction(loaded);
    });
  negative("loaded stylesheet multiset rejects an extra resource",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const values = b.runtime.first.loadedProduction.resourceOccurrences;
      const extra = clone(values.find((entry) => entry.resourceType === "Stylesheet"));
      extra.occurrence = values.length + 1;
      extra.url = "https://overlay.local/css/foreign.css";
      extra.rawResource.url = extra.url;
      values.push(extra);
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("loaded stylesheet declaration order is exact",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const resources = b.runtime.first.loadedProduction.resourceOccurrences;
      const indexes = resources.map((entry, index) => [entry, index])
        .filter(([entry]) => entry.resourceType === "Stylesheet").map((entry) => entry[1]);
      [resources[indexes[0]], resources[indexes[1]]] =
        [resources[indexes[1]], resources[indexes[0]]];
      resources.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("loaded stylesheet digest is exact",
    "loaded_production_resource_mismatch", (b) => {
      const style = b.runtime.first.loadedProduction.resourceOccurrences.find((entry) =>
        entry.resourceType === "Stylesheet");
      replaceRawSource(style, "changed style");
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("loaded resource objects reject extra evidence fields",
    "loaded_production_resource_occurrence_invalid", (b) => {
      b.runtime.first.loadedProduction.resourceOccurrences[1].providerClaim = "not-independent";
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("actual-loaded stylesheet URL inventory rejects an extra producer",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const entry = b.runtime.first.loadedProduction.resourceOccurrences.find((resource) =>
        resource.resourceType === "Stylesheet");
      entry.url = "https://foreign.invalid/foreign.css";
      entry.origin = "https://foreign.invalid";
      entry.rawResource.url = entry.url;
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("production binding cannot cross run identity",
    "production_binding_invalid", (b) => {
      b.productionBinding.runId = "other-run";
      resealProductionBinding(b.productionBinding);
    });
  negative("production binding cannot cross candidate identity",
    "production_binding_invalid", (b) => {
      b.productionBinding.candidateIdentitySha256 = "0".repeat(64);
      resealProductionBinding(b.productionBinding);
    });
  negative("current source identity cannot be rebound to a candidate from older inputs",
    "candidate_producer_identity_mismatch", (b) => {
      const domain = b.productionClosure.producerInputs.domains.artifactSource;
      const source = domain.files.find((entry) =>
        entry.relativePath === "launcher/src/Tasks/EquipmentTuningTask.cs");
      assert.ok(source);
      source.sha256 = "0".repeat(64);
      domain.fingerprintSha256 = Evidence.sha256Text(Evidence.canonicalJson(domain.files));
      domain.hash = "F".repeat(64);
      b.productionClosure.producerInputs.buildIdentityHash =
        ProductionClosure.computeBuildIdentityHash(domain.hash,
          b.productionClosure.producerInputs.domains.producerRecipe.hash,
          b.productionClosure.producerInputs.domains.toolchainLock.hash);
      resealProducerInputs(b.productionClosure.producerInputs);
      const host = b.productionClosure.files.find((entry) =>
        entry.locator === "root:launcher/src/Tasks/EquipmentTuningTask.cs");
      host.sha256 = "0".repeat(64);
      resealProductionClosure(b.productionClosure);
    });
  negative("candidate metadata cannot replace build identity",
    "candidate_producer_identity_mismatch", (b) => {
      const file = path.join(b.candidateRoot, "runtime-build-metadata.v2.json");
      const value = JSON.parse(fs.readFileSync(file, "utf8"));
      value.buildIdentityHash = "F".repeat(64);
      fs.writeFileSync(file, JSON.stringify(value) + "\n", "utf8");
    });
  negative("candidate metadata cannot replace payload closure",
    "candidate_producer_identity_mismatch", (b) => {
      const file = path.join(b.candidateRoot, "runtime-build-metadata.v2.json");
      const value = JSON.parse(fs.readFileSync(file, "utf8"));
      value.payloadClosureHash = "F".repeat(64);
      fs.writeFileSync(file, JSON.stringify(value) + "\n", "utf8");
    });
  negative("candidate manifest payload closure is recomputed from exact rows",
    "candidate_payload_closure_mismatch", (b) => {
      const file = path.join(b.candidateRoot, "runtime", "cf7-runtime-manifest.tsv");
      const text = fs.readFileSync(file, "utf8").replace(
        /payloadClosureHash\t[A-F0-9]{64}/, "payloadClosureHash\t" + "F".repeat(64));
      fs.writeFileSync(file, text, "utf8");
    });
  negative("candidate payload bytes are bound to the producer manifest",
    "candidate_payload_file_mismatch", (b) => {
      fs.appendFileSync(path.join(b.candidateRoot, "runtime",
        "CRAZYFLASHER7MercenaryEmpire.Core.dll"), "changed", "utf8");
    });
  negativeCandidateProducer("candidate manifest cannot omit the authenticated process row",
    "candidate_payload_file_mismatch", (b) => {
      mutateCandidateManifest(b, (lines) => {
        const index = lines.findIndex((line) => line.startsWith(
          "file\truntime/CRAZYFLASHER7MercenaryEmpire.Core.exe\t"));
        assert.ok(index >= 0);
        lines.splice(index, 1);
      });
    });
  negativeCandidateProducer("candidate manifest cannot duplicate the authenticated process row",
    "candidate_payload_file_mismatch", (b) => {
      mutateCandidateManifest(b, (lines) => {
        const index = lines.findIndex((line) => line.startsWith(
          "file\truntime/CRAZYFLASHER7MercenaryEmpire.Core.exe\t"));
        assert.ok(index >= 0);
        lines.splice(index, 0, lines[index]);
      });
    });
  negativeCandidateProducer("candidate manifest cannot add a second process-like payload row",
    "candidate_payload_file_mismatch", (b) => {
      mutateCandidateManifest(b, (lines) => {
        const index = lines.findIndex((line) => line.startsWith(
          "file\truntime/CRAZYFLASHER7MercenaryEmpire.Core.exe\t"));
        assert.ok(index >= 0);
        lines.splice(index + 1, 0, lines[index].replace(".Core.exe", ".Other.exe"));
      });
    });
  negativeCandidateProducer("candidate manifest process hash must match actual bytes",
    "candidate_payload_file_mismatch", (b) => {
      mutateCandidateManifest(b, (lines) => {
        const index = lines.findIndex((line) => line.startsWith(
          "file\truntime/CRAZYFLASHER7MercenaryEmpire.Core.exe\t"));
        assert.ok(index >= 0);
        const fields = lines[index].split("\t");
        fields[3] = "F".repeat(64);
        lines[index] = fields.join("\t");
      });
    });
  negativeCandidateProducer("authenticated process path cannot name a missing payload row",
    "candidate_process_identity_mismatch", (b, identity) => {
      identity.processPath = path.join(b.candidateRoot, "runtime", "Missing.exe");
    });
  negativeCandidateProducer("authenticated process path cannot escape the candidate root",
    "candidate_process_path_invalid", (b, identity) => {
      identity.processPath = path.join(path.dirname(b.candidateRoot), "foreign.exe");
    });
  negativeCandidateProducer("authenticated process cannot be confused with the Core DLL",
    "candidate_process_identity_mismatch", (b, identity) => {
      identity.processPath = path.join(b.candidateRoot, "runtime",
        "CRAZYFLASHER7MercenaryEmpire.Core.dll");
    });
  negative("candidate producer evidence cannot claim a foreign root",
    "candidate_producer_evidence_mismatch", (b) => {
      b.candidateProducer.candidateRoot = path.join(Fixture.ROOT, "foreign-candidate");
      resealDigest(b.candidateProducer, "evidenceSha256");
      b.productionBinding.candidateProducerSha256 = b.candidateProducer.evidenceSha256;
      resealProductionBinding(b.productionBinding);
    });
  negative("loaded production capture must have a finite timestamp",
    "loaded_production_binding_invalid", (b) => {
      b.runtime.first.loadedProduction.capturedAt = "not-a-time";
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });

  negativeArtifact("persisted transcript summary drift", "transcript_summary_bundle_mismatch",
    (_bundle, manifest) => {
      const entry = manifest.get("equipment-first-passive-transcript.json");
      const value = JSON.parse(fs.readFileSync(entry.absolutePath, "utf8"));
      value.observerId = "forged-observer";
      fs.writeFileSync(entry.absolutePath, JSON.stringify(value) + "\n", "utf8");
    });
  negativeArtifact("persisted transcript JSONL drift", "transcript_jsonl_bundle_mismatch",
    (_bundle, manifest) => {
      const entry = manifest.get("equipment-first-passive-transcript.jsonl");
      const lines = fs.readFileSync(entry.absolutePath, "utf8").trimEnd().split("\n");
      lines.pop();
      fs.writeFileSync(entry.absolutePath, lines.join("\n") + "\n", "utf8");
    });
  negativeArtifact("persisted transcript role drift", "transcript_artifact_role_invalid",
    (_bundle, manifest) => {
      manifest.get("equipment-first-passive-transcript.json").role = "other";
    });
  negativeArtifact("persisted bundle drift", "bundle_artifact_mismatch", (_bundle, manifest) => {
    const entry = manifest.get("journey-bundle.json");
    const value = JSON.parse(fs.readFileSync(entry.absolutePath, "utf8"));
    value.generatedAt = "2026-08-03T01:00:00.000Z";
    fs.writeFileSync(entry.absolutePath, JSON.stringify(value) + "\n", "utf8");
  });
  negativeArtifact("provider receipt manifest role is exact",
    "provider_receipt_artifact_role_invalid", (bundle, manifest) => {
      manifest.get(bundle.control.acks[0].providerReceipt.artifact).role = "raw_evidence";
    });
  negativeArtifact("provider receipt manifest role admits no extras",
    "provider_receipt_artifact_set_invalid", (bundle, manifest) => {
      manifest.set("control/provider-receipts/extra.json", {
        absolutePath: path.join(bundle.runDir, "control", "provider-receipts", "extra.json"),
        role: "provider_receipt",
      });
    });
  negativeContract("pre-seal provider bytes must match the exact ACK reference",
    "preseal_artifact_reference_mismatch", () => {
      const bundle = Fixture.buildValidBundle();
      writeTranscriptArtifactFixture(bundle);
      const ack = bundle.control.acks[0];
      ack.providerReceipt.sha256 = "0".repeat(64);
      fs.writeFileSync(path.join(bundle.runDir, "control", "acks", ack.requestId + ".json"),
        JSON.stringify(ack, null, 2) + "\n", "utf8");
      capturePreSealArtifactFreeze(bundle);
    });
  negativePreSeal("post-seal provider replacement with an empty object is rejected",
    "preseal_artifact_reference_mismatch", (bundle) => {
      const relativePath = bundle.control.acks[0].providerReceipt.artifact;
      fs.writeFileSync(path.join(bundle.runDir, relativePath.replace(/\//g, path.sep)),
        "{}\n", "utf8");
    });
  negativePreSeal("post-seal request semantic content drift is rejected",
    "preseal_artifact_content_invalid", (bundle) => {
      const requestValue = bundle.control.requests[0];
      const filePath = path.join(bundle.runDir, "control", "requests",
        requestValue.requestId + ".json");
      const value = JSON.parse(fs.readFileSync(filePath, "utf8"));
      value.instructions += " postseal";
      fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", "utf8");
    });
  negativePreSeal("post-seal capture raw-byte drift is rejected",
    "preseal_artifact_reference_mismatch", (bundle) => {
      const ack = bundle.control.acks[0];
      const filePath = path.join(bundle.runDir,
        ack.capture.relativePath.replace(/\//g, path.sep));
      fs.appendFileSync(filePath, Buffer.from([0]));
    });
  negativePreSeal("post-seal Host sidecar spelling drift is rejected byte-for-byte",
    "preseal_artifact_bytes_changed", (bundle) => {
      fs.appendFileSync(path.join(bundle.runDir, "evidence", "host-first-final-log.json"),
        " \n", "utf8");
    });
  negativePreSeal("post-seal persistence sidecar content drift is rejected",
    "preseal_artifact_content_invalid", (bundle) => {
      fs.writeFileSync(path.join(bundle.runDir, "evidence", "persistence.json"),
        "{}\n", "utf8");
    });
  negativePreSeal("post-seal artifact set cannot gain an extra provider file",
    "preseal_artifact_set_invalid", (bundle) => {
      fs.writeFileSync(path.join(bundle.runDir, "control", "provider-receipts", "extra.json"),
        "{}\n", "utf8");
    });
  negativePreSeal("post-seal artifact set cannot omit a request file",
    "preseal_artifact_set_invalid", (bundle) => {
      const requestValue = bundle.control.requests[0];
      fs.unlinkSync(path.join(bundle.runDir, "control", "requests",
        requestValue.requestId + ".json"));
    });
  negativePreSeal("pre-seal freeze entries cannot be reordered and resealed",
    "preseal_artifact_freeze_invalid", (_bundle, freeze) => {
      [freeze.entries[0], freeze.entries[1]] = [freeze.entries[1], freeze.entries[0]];
      resealDigest(freeze, "freezeSha256");
    });
  negativePreSeal("pre-seal freeze role cannot drift after digest reseal",
    "preseal_artifact_freeze_invalid", (_bundle, freeze) => {
      freeze.entries[0].role = "other";
      resealDigest(freeze, "freezeSha256");
    });
  negativePreSeal("post-seal artifact manifest role must match the frozen role",
    "preseal_artifact_manifest_mismatch", (_bundle, freeze, manifest) => {
      manifest.get(freeze.entries[0].relativePath).role = "other";
    });
  negativePreSeal("post-seal artifact manifest hash must match the frozen bytes",
    "preseal_artifact_manifest_mismatch", (_bundle, freeze, manifest) => {
      manifest.get(freeze.entries[0].relativePath).sha256 = "0".repeat(64);
    });

  negative("bundle schema drift", "bundle_invalid", (b) => { b.schema = "other"; });
  negative("bundle API drift", "bundle_invalid", (b) => { b.apiVersion = "equipment-v1"; });
  negative("bundle status overclaim", "bundle_invalid", (b) => { b.status = "e2e_verified"; });
  negative("bundle deployment overclaim", "bundle_invalid", (b) => { b.deployment = "DEPLOYED"; });
  negative("bundle relative root", "bundle_invalid", (b) => { b.root = "."; });
  negative("bundle relative run directory", "bundle_invalid", (b) => { b.runDir = "."; });
  negative("bundle malformed run id", "bundle_invalid", (b) => { b.runId = "bad id"; });
  negative("bundle seed target alias", "bundle_invalid", (b) => { b.seedSlot = b.targetSlot; });
  negative("bundle non-dedicated target", "bundle_invalid", (b) => { b.targetSlot = "player1"; });
  negative("bundle commit consent absent", "bundle_invalid", (b) => { b.allowIsolatedCommit = false; });
  negative("bundle fallback consent absent", "bundle_invalid", (b) => { b.allowCodexCuFallback = false; });
  negative("raw tuning token persistence", "raw_authority_token_present", (b) => {
    response(b, "first", "equipment_tuning", "preview", 0).message.tuningToken = "raw-token";
  });
  negative("non-string authority persistence", "raw_authority_token_present", (b) => {
    response(b, "first", "equipment_tuning", "preview", 0).message.tuningToken = 7;
  });
  negative("raw source lease persistence", "raw_authority_token_present", (b) => {
    request(b, "first", "equipment_tuning", "snapshot", 0).message.payload.source.expectedLease = "raw-lease";
  });

  negative("first candidate root mismatch", "candidate_identity_invalid", (b) => {
    b.runtime.first.identity.installRoot += "-other";
  });
  negative("restart candidate hash mismatch", "candidate_identity_drift", (b) => {
    b.runtime.restart.identity.coreSha256 = "D".repeat(64);
  });
  negative("expected identity mismatch", "candidate_identity_drift", (b) => {
    b.runtime.expectedIdentity.payloadClosure = "D".repeat(64);
  });
  negative("first session PID mismatch", "session_pid_binding_invalid", (b) => {
    b.runtime.first.sessionEvidence.pid += 1;
    resealSession(b.runtime.first.sessionEvidence);
  });
  negative("process contract admission overclaim", "launcher_process_contract_invalid", (b) => {
    b.runtime.first.processContract.agentRuntimeAdmission = true;
    resealDigest(b.runtime.first.processContract, "artifactSha256");
  });
  negative("process contract PID mismatch", "launcher_process_contract_invalid", (b) => {
    b.runtime.first.processContract.pid += 1;
    resealDigest(b.runtime.first.processContract, "artifactSha256");
  });
  negative("CDP page origin mismatch", "cdp_runtime_binding_invalid", (b) => {
    b.runtime.first.cdpBinding.pageIdentity.origin = "https://evil.local";
    b.runtime.first.cdpBinding.pageIdentitySha256 = Evidence.sha256Text(
      Evidence.canonicalJson(b.runtime.first.cdpBinding.pageIdentity));
  });
  negative("CDP user data root mismatch", "cdp_runtime_binding_invalid", (b) => {
    b.runtime.first.cdpBinding.attestation.userDataRoot += "-other";
  });
  negative("CDP listener ancestry missing", "cdp_runtime_binding_invalid", (b) => {
    b.runtime.first.cdpBinding.attestation.ancestorPids = [5100];
  });
  negative("CDP page identity digest mismatch", "cdp_runtime_binding_invalid", (b) => {
    b.runtime.first.cdpBinding.pageIdentitySha256 = "0".repeat(64);
  });
  negative("restart attempt reused", "restart_identity_not_fresh", (b) => {
    b.runtime.restart.attemptId = b.runtime.first.attemptId;
  });
  negative("restart PID reused", "session_pid_binding_invalid", (b) => {
    b.runtime.restart.identity.pid = b.runtime.first.identity.pid;
  });
  negative("restart CDP port reused", "restart_cdp_not_fresh", (b) => {
    b.runtime.restart.cdpBinding.port = b.runtime.first.cdpBinding.port;
    b.runtime.restart.cdpBinding.attestation.port = b.runtime.first.cdpBinding.port;
  });
  negative("restart page lifetime reused", "restart_cdp_not_fresh", (b) => {
    b.runtime.restart.cdpBinding.pageIdentity.timeOrigin = b.runtime.first.cdpBinding.pageIdentity.timeOrigin;
    b.runtime.restart.cdpBinding.pageIdentitySha256 = Evidence.sha256Text(
      Evidence.canonicalJson(b.runtime.restart.cdpBinding.pageIdentity));
  });

  negative("transcript event payload tamper", "transcript_chain_invalid", (b) => {
    b.transcripts.first.events[2].kind = "tampered";
  });
  negative("transcript event sequence tamper", "transcript_chain_invalid", (b) => {
    b.transcripts.first.events[2].sequence = 99;
  });
  negative("transcript terminal count tamper", "transcript_terminal_invalid", (b) => {
    b.transcripts.first.eventCount += 1;
  });
  negative("observer ready missing", "observer_lifecycle_invalid", (b) => {
    b.transcripts.first.events = b.transcripts.first.events.filter((e) => e.kind !== "observer_ready");
    resealTranscript(b.transcripts.first);
  });
  negative("observer duplicate detach", "observer_lifecycle_invalid", (b) => {
    b.transcripts.first.events.push({ kind: "observer_detached" });
    resealTranscript(b.transcripts.first);
  });
  negative("strict final observer detach missing", "observer_lifecycle_invalid", (b) => {
    b.transcripts.first.events = b.transcripts.first.events.filter((event) =>
      !["observer_detached", "observer_detach_transport_lost"].includes(event.kind));
    resealTranscript(b.transcripts.first);
  });
  negative("preview issued after production request", "journey_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    placeAfter(events, diagnostic(b, "preview_issued", 0),
      request(b, "first", "equipment_tuning", "preview", 0));
    resealTranscript(b.transcripts.first);
  });
  negative("preview adopted before production request", "journey_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    placeBefore(events, diagnostic(b, "preview_adopted", 0),
      request(b, "first", "equipment_tuning", "preview", 0));
    resealTranscript(b.transcripts.first);
  });
  negative("preview A response crosses candidate B response", "journey_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    placeAfter(events, response(b, "first", "equipment_tuning", "preview", 0),
      response(b, "first", "equipment_tuning", "preview", 1));
    resealTranscript(b.transcripts.first);
  });
  negative("postcommit Inventory pair occurs before commit input", "cross_domain_request_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    const inventoryRequest = request(b, "first", "inventory", "snapshot", 1);
    const inventoryResponse = response(b, "first", "inventory", "snapshot", 1);
    const commitInput = events.find((event) => event.kind === "dom_input"
      && event.target && event.target.attributes["data-tuning-focus-key"] === "commit");
    placeBefore(events, inventoryRequest, commitInput);
    placeAfter(events, inventoryResponse, inventoryRequest);
    resealTranscript(b.transcripts.first);
  });
  negative("initial Inventory request cannot precede tuning authority",
    "cross_domain_request_order_invalid", (b) => {
      const events = b.transcripts.first.events;
      placeBefore(events, request(b, "first", "inventory", "snapshot", 0),
        request(b, "first", "equipment_tuning", "snapshot", 0));
      resealTranscript(b.transcripts.first);
    });
  negative("restart Inventory request cannot precede tuning authority",
    "cross_domain_request_order_invalid", (b) => {
      const events = b.transcripts.restart.events;
      placeBefore(events, request(b, "restart", "inventory", "snapshot", 0),
        request(b, "restart", "equipment_tuning", "snapshot", 0));
      resealTranscript(b.transcripts.restart);
    });
  negative("commit response crosses fresh tuning response", "journey_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    placeAfter(events, response(b, "first", "equipment_tuning", "commit", 0),
      response(b, "first", "equipment_tuning", "snapshot", 1));
    resealTranscript(b.transcripts.first);
  });
  negative("refresh settled before commit request", "diagnostic_multiset_invalid", (b) => {
    const events = b.transcripts.first.events;
    placeBefore(events, diagnostic(b, "inventory_refresh_settled", 0),
      request(b, "first", "equipment_tuning", "commit", 0));
    resealTranscript(b.transcripts.first);
  });
  negative("fresh tuning response occurs after detach", "journey_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    placeAfter(events, response(b, "first", "equipment_tuning", "snapshot", 1),
      response(b, "first", "equipment_tuning", "detach", 0));
    resealTranscript(b.transcripts.first);
  });
  negative("preview A adoption missing", "diagnostic_multiset_invalid", (b) => {
    const target = diagnostic(b, "preview_adopted", 0);
    b.transcripts.first.events = b.transcripts.first.events.filter((event) => event !== target);
    resealTranscript(b.transcripts.first);
  });
  negative("preview adoption lacks Web call id", "authority_diagnostic_not_exact", (b) => {
    diagnostic(b, "preview_adopted", 0).message.webCallId = "";
    resealTranscript(b.transcripts.first);
  });
  negative("commit adoption duplicated", "diagnostic_multiset_invalid", (b) => {
    b.transcripts.first.events.splice(-1, 0, clone(diagnostic(b, "commit_adopted", 0)));
    resealTranscript(b.transcripts.first);
  });
  negative("initial Inventory response occurs after candidate A input", "journey_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    const candidateAInput = events.find((event) => event.kind === "dom_input"
      && event.target && event.target.attributes["data-candidate-key"] === Fixture.CANDIDATE_A.candidateKey);
    placeAfter(events, response(b, "first", "inventory", "snapshot", 0), candidateAInput);
    resealTranscript(b.transcripts.first);
  });
  negative("candidate B input occurs before preview A response", "journey_order_invalid", (b) => {
    const events = b.transcripts.first.events;
    const candidateBInput = events.find((event) => event.kind === "dom_input"
      && event.target && event.target.attributes["data-candidate-key"] === Fixture.CANDIDATE_B.candidateKey);
    placeBefore(events, candidateBInput,
      response(b, "first", "equipment_tuning", "preview", 0));
    resealTranscript(b.transcripts.first);
  });
  negative("tuning command missing", "command_sequence_invalid", (b) => {
    const target = request(b, "first", "equipment_tuning", "preview", 0);
    b.transcripts.first.events = b.transcripts.first.events.filter((e) => e !== target);
    resealTranscript(b.transcripts.first);
  });
  negative("tuning command extra", "command_sequence_invalid", (b) => {
    b.transcripts.first.events.splice(-1, 0, clone(request(b, "first", "equipment_tuning", "snapshot", 0)));
    resealTranscript(b.transcripts.first);
  });
  negative("inventory command missing", "command_sequence_invalid", (b) => {
    const target = request(b, "first", "inventory", "snapshot", 1);
    b.transcripts.first.events = b.transcripts.first.events.filter((e) => e !== target);
    resealTranscript(b.transcripts.first);
  });
  negative("Web call id reuse", "request_call_id_duplicate", (b) => {
    request(b, "first", "equipment_tuning", "preview", 1).message.callId =
      request(b, "first", "equipment_tuning", "preview", 0).message.callId;
    resealTranscript(b.transcripts.first);
  });
  negative("authority response missing", "request_response_pair_invalid", (b) => {
    const target = response(b, "first", "equipment_tuning", "preview", 0);
    b.transcripts.first.events = b.transcripts.first.events.filter((e) => e !== target);
    resealTranscript(b.transcripts.first);
  });
  negative("authority response duplicated", "request_response_pair_invalid", (b) => {
    b.transcripts.first.events.splice(-1, 0, clone(response(b, "first", "equipment_tuning", "preview", 0)));
    resealTranscript(b.transcripts.first);
  });
  negative("Equipment response version missing", "response_fields_invalid", (b) => {
    delete response(b, "first", "equipment_tuning", "snapshot", 0).message.v;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory response session nonce missing", "response_fields_invalid", (b) => {
    delete response(b, "first", "inventory", "snapshot", 0).message.sessionNonce;
    resealTranscript(b.transcripts.first);
  });
  negative("successful Web response field set is closed", "response_fields_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 0)
      .message.requiresReconcile = false;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory request payload field set is closed", "request_payload_invalid", (b) => {
    request(b, "first", "inventory", "snapshot", 0).message.payload.extra = true;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory snapshot request cannot use an empty window set", "request_payload_invalid", (b) => {
    request(b, "first", "inventory", "snapshot", 0).message.payload.requests = [];
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory snapshot request must cover the source physical slot", "inventory_request_scope_invalid", (b) => {
    request(b, "first", "inventory", "snapshot", 0).message.payload.requests[0].offset = 8;
    resealTranscript(b.transcripts.first);
  });
  negative("Equipment inventory source cannot cross into another container",
    "inventory_source_required", (b) => {
      request(b, "first", "equipment_tuning", "snapshot", 0)
        .message.payload.source.containerId = "仓库";
      resealTranscript(b.transcripts.first);
    });
  negative("Equipment inventory source slot is bounded by the production backpack",
    "inventory_source_required", (b) => {
      request(b, "first", "equipment_tuning", "snapshot", 0).message.payload.source.slot = 50;
      resealTranscript(b.transcripts.first);
    });
  negative("panel owner drift", "panel_owner_not_exact", (b) => {
    request(b, "first", "inventory", "snapshot", 0).message.panelInstanceId = "foreign_panel";
    response(b, "first", "inventory", "snapshot", 0).message.panelInstanceId = "foreign_panel";
    resealTranscript(b.transcripts.first);
  });
  negative("view session drift", "view_session_not_exact", (b) => {
    request(b, "first", "equipment_tuning", "preview", 0).message.payload.viewSessionId = "foreign_view";
    response(b, "first", "equipment_tuning", "preview", 0).message.viewSessionId = "foreign_view";
    resealTranscript(b.transcripts.first);
  });
  negative("source coordinate drift", "source_authority_drift", (b) => {
    request(b, "first", "equipment_tuning", "preview", 0).message.payload.source.slot = 8;
    resealTranscript(b.transcripts.first);
  });
  negative("preview candidate reused", "preview_replacement_not_proven", (b) => {
    const a = request(b, "first", "equipment_tuning", "preview", 0).message.payload.candidateKey;
    request(b, "first", "equipment_tuning", "preview", 1).message.payload.candidateKey = a;
    resealTranscript(b.transcripts.first);
  });
  negative("preview token reused", "preview_replacement_not_proven", (b) => {
    response(b, "first", "equipment_tuning", "preview", 1).message.tuningToken =
      response(b, "first", "equipment_tuning", "preview", 0).message.tuningToken;
    resealTranscript(b.transcripts.first);
  });
  negative("selected candidate unavailable", "selected_candidate_not_authoritative", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0).message.snapshot.modCandidates[1].available = false;
    resealTranscript(b.transcripts.first);
  });
  negative("selected candidate unowned", "selected_candidate_not_authoritative", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0).message.snapshot.modCandidates[1].owned = 0;
    resealTranscript(b.transcripts.first);
  });
  negative("selected identity not all distinct", "final_candidate_not_all_distinct", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0).message.snapshot.modCandidates[1].displayName =
      Fixture.CANDIDATE_B.itemName;
    resealTranscript(b.transcripts.first);
  });
  negative("selected identity outside frozen fixture", "final_candidate_not_canonical_fixture", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0).message.snapshot.modCandidates[1].displayName += "x";
    resealTranscript(b.transcripts.first);
  });
  negative("candidate material identity mismatch", "candidate_material_identity_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "preview", 1).message.materials[0].icon =
      Fixture.CANDIDATE_A.icon;
    resealTranscript(b.transcripts.first);
  });
  negative("equipment projection rejects an extra field", "equipment_leaf_invalid", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0)
      .message.snapshot.equipment.legacyLevel = 13;
    resealTranscript(b.transcripts.first);
  });
  negative("equipment projection requires max-level authority", "equipment_leaf_invalid", (b) => {
    delete response(b, "first", "equipment_tuning", "snapshot", 0)
      .message.snapshot.equipment.maxLevel;
    resealTranscript(b.transcripts.first);
  });
  negative("enhance projection must bind the equipment level", "tuning_snapshot_invalid", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0)
      .message.snapshot.enhance.currentLevel = 12;
    resealTranscript(b.transcripts.first);
  });
  negative("mod candidate rejects a legacy display alias", "mod_candidate_invalid", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0)
      .message.snapshot.modCandidates[0].displayname = "旧别名";
    resealTranscript(b.transcripts.first);
  });
  negative("mod candidate replaceable keys must be unique opaque values",
    "mod_candidate_invalid", (b) => {
      response(b, "first", "equipment_tuning", "snapshot", 0)
        .message.snapshot.modCandidates[0].replaceableFrom = ["same", "same"];
      resealTranscript(b.transcripts.first);
    });
  negative("snapshot material identities must be unique", "snapshot_material_invalid", (b) => {
    const materials = response(b, "first", "equipment_tuning", "snapshot", 0)
      .message.snapshot.materials;
    materials[1].itemName = materials[0].itemName;
    resealTranscript(b.transcripts.first);
  });
  negative("material plan rejects extra projection fields", "material_plan_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 1)
      .message.materials[0].legacyName = "旧字段";
    resealTranscript(b.transcripts.first);
  });
  negative("preview removed-mod set must be unique", "preview_response_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 1)
      .message.removedMods = ["重复插件", "重复插件"];
    resealTranscript(b.transcripts.first);
  });
  negative("commit removed-mod set must equal accepted preview",
    "commit_removed_mods_mismatch", (b) => {
      response(b, "first", "equipment_tuning", "commit", 0)
        .message.removedMods = ["其他插件"];
      resealTranscript(b.transcripts.first);
    });
  negative("material arithmetic invalid", "material_plan_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 1).message.materials[0].after = 1;
    resealTranscript(b.transcripts.first);
  });
  negative("preview projection carries an impossible target", "projection_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 0).message.after.target = {};
    resealTranscript(b.transcripts.first);
  });
  negative("inventory source carries loadout-only aliases", "source_ref_invalid", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 0)
      .message.snapshot.source.sessionGeneration = 1;
    resealTranscript(b.transcripts.first);
  });
  negative("selected preview candidate is already installed",
    "selected_candidate_not_authoritative", (b) => {
      const snapshot = response(b, "first", "equipment_tuning", "snapshot", 0)
        .message.snapshot;
      snapshot.modCandidates[0].installed = true;
      snapshot.equipment.mods = [snapshot.modCandidates[0].itemName];
      resealTranscript(b.transcripts.first);
    });
  negative("preview before drift", "initial_preview_before_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "preview", 0).message.before.source.equipment.lastUpdate = 99;
    resealTranscript(b.transcripts.first);
  });
  negative("commit before mismatch", "commit_before_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0).message.before.source.equipment.lastUpdate = 99;
    resealTranscript(b.transcripts.first);
  });
  negative("commit after mismatch", "commit_after_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0).message.after.source.equipment.level = 14;
    resealTranscript(b.transcripts.first);
  });
  negative("commit after timestamp does not advance", "commit_after_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0)
      .message.after.source.equipment.lastUpdate = 100;
    resealTranscript(b.transcripts.first);
  });
  negative("commit material mismatch", "commit_materials_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0).message.materials[0].before = 5;
    response(b, "first", "equipment_tuning", "commit", 0).message.materials[0].after = 4;
    resealTranscript(b.transcripts.first);
  });
  negative("commit token mismatch", "commit_token_binding_invalid", (b) => {
    request(b, "first", "equipment_tuning", "commit", 0).message.payload.expectedTuningToken = tokenRef("other");
    resealTranscript(b.transcripts.first);
  });
  negative("commit snapshot mismatch", "commit_snapshot_after_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0).message.snapshot.equipment.lastUpdate = 201;
    resealTranscript(b.transcripts.first);
  });
  negative("fresh tuning snapshot mismatch", "fresh_snapshot_after_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 1).message.snapshot.equipment.lastUpdate = 201;
    resealTranscript(b.transcripts.first);
  });
  negative("fresh material total mismatch", "fresh_material_postcondition_invalid", (b) => {
    response(b, "first", "equipment_tuning", "snapshot", 1).message.snapshot.materials[1].count = 4;
    resealTranscript(b.transcripts.first);
  });
  negative("commit and fresh revisions must advance once",
    "fresh_revision_postcondition_invalid", (b) => {
      const committed = response(b, "first", "equipment_tuning", "commit", 0).message.snapshot;
      const fresh = response(b, "first", "equipment_tuning", "snapshot", 1).message.snapshot;
      committed.materialRevision = 1;
      committed.inventoryRevision = 1;
      fresh.materialRevision = 1;
      fresh.inventoryRevision = 1;
      resealTranscript(b.transcripts.first);
    });
  negative("installed mod missing", "tuning_snapshot_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 1).message.after.source.equipment.mods = [];
    const commit = response(b, "first", "equipment_tuning", "commit", 0).message;
    commit.after.source.equipment.mods = [];
    commit.snapshot.equipment.mods = [];
    response(b, "first", "equipment_tuning", "snapshot", 1).message.snapshot.equipment.mods = [];
    resealTranscript(b.transcripts.first);
  });
  negative("preview A projected after state is absent", "install_mod_postcondition_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 0).message.after.source.equipment.mods = [];
    resealTranscript(b.transcripts.first);
  });
  negative("preview A changes an unrelated equipment field",
    "install_mod_postcondition_invalid", (b) => {
      response(b, "first", "equipment_tuning", "preview", 0)
        .message.after.source.equipment.level = 14;
      resealTranscript(b.transcripts.first);
    });
  negative("preview A advances timestamp before commit",
    "install_mod_postcondition_invalid", (b) => {
      response(b, "first", "equipment_tuning", "preview", 0)
        .message.after.source.equipment.lastUpdate = 101;
      resealTranscript(b.transcripts.first);
    });
  negative("preview B carries a second material debit",
    "install_mod_postcondition_invalid", (b) => {
      response(b, "first", "equipment_tuning", "preview", 1).message.materials.push({
        itemName: Fixture.CANDIDATE_A.itemName,
        displayName: Fixture.CANDIDATE_A.displayName,
        icon: Fixture.CANDIDATE_A.icon,
        before: 3,
        delta: -1,
        after: 2,
      });
      resealTranscript(b.transcripts.first);
    });
  negative("preview B invents a removed mod", "install_mod_postcondition_invalid", (b) => {
    response(b, "first", "equipment_tuning", "preview", 1)
      .message.removedMods = [Fixture.CANDIDATE_A.itemName];
    resealTranscript(b.transcripts.first);
  });
  negative("trusted business input missing", "trusted_input_contract_invalid", (b) => {
    b.transcripts.first.events.forEach((e) => { if (e.kind === "dom_input") e.isTrusted = false; });
    resealTranscript(b.transcripts.first);
  });
  negative("diagnostic chain incomplete", "diagnostic_multiset_invalid", (b) => {
    b.transcripts.first.events = b.transcripts.first.events.filter((e) => !(e.message
      && e.message.type === "debug" && e.message.event === "commit_adopted"));
    resealTranscript(b.transcripts.first);
  });
  negative("preview adopted lacks token readiness", "authority_diagnostic_status_invalid", (b) => {
    const message = diagnostic(b, "preview_adopted", 0).message;
    message.tokenPresent = false;
    message.commitReady = false;
    message.pendingCount = 9;
    resealTranscript(b.transcripts.first);
  });
  negative("commit adopted reports failed unsettled reconciliation", "authority_diagnostic_status_invalid", (b) => {
    const message = diagnostic(b, "commit_adopted", 0).message;
    message.success = false;
    message.transactionIdPresent = false;
    message.requiresReconcile = true;
    message.pendingCount = 9;
    resealTranscript(b.transcripts.first);
  });
  negative("Inventory refresh diagnostic reports failure without lease", "authority_diagnostic_not_exact", (b) => {
    const message = diagnostic(b, "inventory_refresh_settled", 0).message;
    message.success = false;
    message.currentLeasePresent = false;
    message.needsReconcile = true;
    resealTranscript(b.transcripts.first);
  });
  negative("unexpected reconcile diagnostic is rejected", "diagnostic_multiset_invalid", (b) => {
    const event = clone(diagnostic(b, "commit_adopted", 0));
    event.message.event = "reconcile_issued";
    b.transcripts.first.events.splice(-1, 0, event);
    resealTranscript(b.transcripts.first);
  });
  negative("unexpected response tuple diagnostic is rejected", "diagnostic_multiset_invalid", (b) => {
    const event = clone(diagnostic(b, "commit_adopted", 0));
    event.message.event = "response_tuple_mismatch";
    b.transcripts.first.events.splice(-1, 0, event);
    resealTranscript(b.transcripts.first);
  });
  negative("first detach response invents a detached field", "response_fields_invalid", (b) => {
    response(b, "first", "equipment_tuning", "detach", 0).message.detached = false;
    resealTranscript(b.transcripts.first);
  });
  negative("first detach response is unsuccessful", "response_envelope_invalid", (b) => {
    response(b, "first", "equipment_tuning", "detach", 0).message.success = false;
    resealTranscript(b.transcripts.first);
  });

  negative("restart panel reused", "restart_instance_not_fresh", (b) => {
    const firstPanel = request(b, "first", "equipment_tuning", "snapshot", 0).message.panelInstanceId;
    b.transcripts.restart.events.forEach((e) => {
      if (e.message && e.message.panelInstanceId) e.message.panelInstanceId = firstPanel;
    });
    resealTranscript(b.transcripts.restart);
  });
  negative("restart view reused", "restart_instance_not_fresh", (b) => {
    const firstView = request(b, "first", "equipment_tuning", "snapshot", 0).message.payload.viewSessionId;
    b.transcripts.restart.events.forEach((e) => {
      if (e.message && e.message.domain === "equipment_tuning") {
        if (e.kind === "bridge_send") e.message.payload.viewSessionId = firstView;
        else e.message.viewSessionId = firstView;
      }
    });
    resealTranscript(b.transcripts.restart);
  });
  negative("restart equipment drift", "restart_equipment_readback_mismatch", (b) => {
    response(b, "restart", "equipment_tuning", "snapshot", 0).message.snapshot.equipment.lastUpdate = 999;
    resealTranscript(b.transcripts.restart);
  });
  negative("restart material drift", "restart_material_readback_mismatch", (b) => {
    response(b, "restart", "equipment_tuning", "snapshot", 0).message.snapshot.materials[1].count = 2;
    resealTranscript(b.transcripts.restart);
  });
  negative("restart detach response invents a detached field", "response_fields_invalid", (b) => {
    response(b, "restart", "equipment_tuning", "detach", 0).message.detached = false;
    resealTranscript(b.transcripts.restart);
  });
  negative("restart mutation input observed", "restart_write_input_observed", (b) => {
    b.transcripts.restart.events.splice(-1, 0, { kind: "dom_input", isTrusted: true,
      eventType: "click", target: { mutationCapable: true, attributes: {} } });
    resealTranscript(b.transcripts.restart);
  });
  negative("inventory container missing", "inventory_snapshot_shape_invalid", (b) => {
    response(b, "first", "inventory", "snapshot", 0).message.snapshots[0].containerId = "other";
    resealTranscript(b.transcripts.first);
  });
  negative("inventory snapshot omits one required production field",
    "inventory_snapshot_shape_invalid", (b) => {
      delete response(b, "first", "inventory", "snapshot", 0)
        .message.snapshots[0].viewCapacity;
      resealTranscript(b.transcripts.first);
    });
  negative("inventory response carries an explicit all scope alias",
    "inventory_snapshot_shape_invalid", (b) => {
      response(b, "first", "inventory", "snapshot", 0).message.snapshots[0].scope = "all";
      resealTranscript(b.transcripts.first);
    });
  negative("inventory response carries a null filterSpec alias",
    "inventory_snapshot_shape_invalid", (b) => {
      response(b, "first", "inventory", "snapshot", 0).message.snapshots[0].filterSpec = null;
      resealTranscript(b.transcripts.first);
    });
  negative("inventory request adds a second window", "inventory_request_scope_invalid", (b) => {
    request(b, "first", "inventory", "snapshot", 0).message.payload.requests.push({
      containerId: "仓库", offset: 0, limit: 50, filterKey: "all", scope: "all",
    });
    resealTranscript(b.transcripts.first);
  });
  negative("inventory request drifts from the frozen scope=all 50-slot window",
    "inventory_request_scope_invalid", (b) => {
      request(b, "first", "inventory", "snapshot", 0)
        .message.payload.requests[0].scope = "equipment";
      resealTranscript(b.transcripts.first);
    });
  negative("inventory source slot missing", "inventory_source_slot_invalid", (b) => {
    const slots = response(b, "first", "inventory", "snapshot", 0).message.snapshots[0].slots;
    const source = slots[7];
    slots[7] = { physicalSlot: 7, occupied: false,
      slotLease: tokenRef("fixture-source-slot-missing") };
    source.physicalSlot = 8;
    slots[8] = source;
    resealTranscript(b.transcripts.first);
  });
  negative("inventory occupied slot omits confirmation projection",
    "inventory_slot_invalid", (b) => {
      delete response(b, "first", "inventory", "snapshot", 0)
        .message.snapshots[0].slots[7].confirmProjection;
      resealTranscript(b.transcripts.first);
    });
  negative("inventory item uses a legacy tuning type field", "inventory_item_invalid", (b) => {
    response(b, "first", "inventory", "snapshot", 0)
      .message.snapshots[0].slots[7].item.type = "武器";
    resealTranscript(b.transcripts.first);
  });
  negative("inventory identity drift", "inventory_initial_before_mismatch", (b) => {
    response(b, "first", "inventory", "snapshot", 0).message.snapshots[0].slots[7].item.icon =
      Fixture.CANDIDATE_A.icon;
    resealTranscript(b.transcripts.first);
  });
  negative("inventory confirmation mod signature drift",
    "inventory_initial_before_mismatch", (b) => {
      response(b, "first", "inventory", "snapshot", 0)
        .message.snapshots[0].slots[7].confirmProjection.modSignature = "6:forged;";
      resealTranscript(b.transcripts.first);
    });
  negative("inventory refresh drift", "inventory_refresh_after_mismatch", (b) => {
    response(b, "first", "inventory", "snapshot", 1)
      .message.snapshots[0].slots[7].confirmProjection.lastUpdate = 999;
    resealTranscript(b.transcripts.first);
  });
  negative("inventory restart drift", "inventory_restart_after_mismatch", (b) => {
    response(b, "restart", "inventory", "snapshot", 0)
      .message.snapshots[0].slots[7].confirmProjection.lastUpdate = 999;
    resealTranscript(b.transcripts.restart);
  });
  negative("commit embedded Inventory snapshot missing", "inventory_full_backpack_invalid", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0).message.inventorySnapshots = [];
    resealTranscript(b.transcripts.first);
  });
  negative("commit embedded Inventory snapshot is sparse",
    "inventory_snapshot_shape_invalid", (b) => {
      response(b, "first", "equipment_tuning", "commit", 0)
        .message.inventorySnapshots[0].slots.length = 1;
      resealTranscript(b.transcripts.first);
    });
  negative("commit embedded Inventory lease drift", "inventory_source_lease_mismatch", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0)
      .message.inventorySnapshots[0].slots[7].slotLease = tokenRef("forged-embedded-lease");
    resealTranscript(b.transcripts.first);
  });
  negative("commit embedded Inventory equipment drift", "inventory_commit_after_mismatch", (b) => {
    const slot = response(b, "first", "equipment_tuning", "commit", 0)
      .message.inventorySnapshots[0].slots[7];
    slot.item.modSlots = [];
    slot.item.modSlotUsed = 0;
    slot.confirmProjection.modSignature = "";
    resealTranscript(b.transcripts.first);
  });
  negative("initial Inventory lease disagrees with tuning source", "inventory_source_lease_mismatch", (b) => {
    response(b, "first", "inventory", "snapshot", 0)
      .message.snapshots[0].slots[7].slotLease = tokenRef("forged-initial-lease");
    resealTranscript(b.transcripts.first);
  });
  negative("refreshed Inventory lease disagrees with commit source", "inventory_source_lease_mismatch", (b) => {
    response(b, "first", "inventory", "snapshot", 1)
      .message.snapshots[0].slots[7].slotLease = tokenRef("forged-refresh-lease");
    resealTranscript(b.transcripts.first);
  });
  negative("restart Inventory lease disagrees with fresh source", "inventory_source_lease_mismatch", (b) => {
    response(b, "restart", "inventory", "snapshot", 0)
      .message.snapshots[0].slots[7].slotLease = tokenRef("forged-restart-lease");
    resealTranscript(b.transcripts.restart);
  });
  negative("Inventory session nonce is reused across process restart",
    "inventory_session_nonce_invalid", (b) => {
      response(b, "restart", "inventory", "snapshot", 0).message.sessionNonce =
        response(b, "first", "inventory", "snapshot", 0).message.sessionNonce;
      resealTranscript(b.transcripts.restart);
    });
  negative("one occupied non-target slot cannot change during the target commit",
    "inventory_non_target_drift", (b) => {
      const slot = response(b, "first", "equipment_tuning", "commit", 0)
        .message.inventorySnapshots[0].slots[20];
      slot.item.enhancementLevel += 1;
      slot.confirmProjection.enhancementLevel += 1;
      resealTranscript(b.transcripts.first);
    });
  negative("an unrelated occupied slot cannot be added with internally consistent facets",
    "inventory_non_target_drift", (b) => {
      const snapshot = response(b, "first", "equipment_tuning", "commit", 0)
        .message.inventorySnapshots[0];
      const lease = snapshot.slots[21].slotLease;
      snapshot.slots[21] = clone(snapshot.slots[20]);
      snapshot.slots[21].physicalSlot = 21;
      snapshot.slots[21].slotLease = lease;
      snapshot.filterFacets[0].count += 1;
      snapshot.filterItemCount += 1;
      resealTranscript(b.transcripts.first);
    });
  negative("every non-target lease must rotate on the target mutation",
    "inventory_slot_lease_lifecycle_invalid", (b) => {
      const initial = response(b, "first", "inventory", "snapshot", 0)
        .message.snapshots[0].slots[20];
      response(b, "first", "equipment_tuning", "commit", 0)
        .message.inventorySnapshots[0].slots[20].slotLease = initial.slotLease;
      resealTranscript(b.transcripts.first);
    });
  negative("a settled non-target lease cannot rotate again on refresh",
    "inventory_slot_lease_lifecycle_invalid", (b) => {
      response(b, "first", "inventory", "snapshot", 1)
        .message.snapshots[0].slots[20].slotLease = tokenRef("forged-refresh-side-lease");
      resealTranscript(b.transcripts.first);
    });
  negative("a non-target lease cannot be reused across process restart",
    "inventory_slot_lease_lifecycle_invalid", (b) => {
      const refreshed = response(b, "first", "inventory", "snapshot", 1)
        .message.snapshots[0].slots[20];
      response(b, "restart", "inventory", "snapshot", 0)
        .message.snapshots[0].slots[20].slotLease = refreshed.slotLease;
      resealTranscript(b.transcripts.restart);
    });
  negative("Inventory container version does not advance on commit",
    "inventory_container_version_invalid", (b) => {
      response(b, "first", "equipment_tuning", "commit", 0)
        .message.inventorySnapshots[0].containerVersion = 1;
      response(b, "first", "inventory", "snapshot", 1)
        .message.snapshots[0].containerVersion = 1;
      resealTranscript(b.transcripts.first);
    });
  negative("Inventory embedded snapshot sequence is not between read and refresh",
    "inventory_snapshot_sequence_invalid", (b) => {
      response(b, "first", "equipment_tuning", "commit", 0)
        .message.inventorySnapshots[0].snapshotSeq = 1;
      resealTranscript(b.transcripts.first);
    });
  negative("Inventory container epoch changes during single-slot tuning",
    "inventory_container_epoch_invalid", (b) => {
      response(b, "first", "equipment_tuning", "commit", 0)
        .message.inventorySnapshots[0].containerEpoch = 2;
      response(b, "first", "inventory", "snapshot", 1)
        .message.snapshots[0].containerEpoch = 2;
      resealTranscript(b.transcripts.first);
    });
  negative("restart Inventory version disagrees with tuning revision",
    "inventory_revision_binding_invalid", (b) => {
      response(b, "restart", "inventory", "snapshot", 0)
        .message.snapshots[0].containerVersion = 2;
      resealTranscript(b.transcripts.restart);
    });
  negative("preview projected source crosses lease generation", "source_authority_drift", (b) => {
    response(b, "first", "equipment_tuning", "preview", 0)
      .message.after.source.source.expectedLease = tokenRef("forged-preview-lease");
    resealTranscript(b.transcripts.first);
  });
  negative("commit after projection keeps the pre-write lease", "source_authority_drift", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0)
      .message.after.source.source.expectedLease =
        response(b, "first", "equipment_tuning", "preview", 1)
          .message.after.source.source.expectedLease;
    resealTranscript(b.transcripts.first);
  });
  negative("commit snapshot source crosses lease generation", "source_authority_drift", (b) => {
    response(b, "first", "equipment_tuning", "commit", 0)
      .message.snapshot.source.slot = 8;
    resealTranscript(b.transcripts.first);
  });

  negative("first Host command missing", "host_flash_command_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const index = records.findIndex((entry) =>
      entry.line.includes("[EquipmentTuningTask] -> Flash:")
        && entry.line.includes("equipmentTuningSnapshot"));
    records.splice(index, 1);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("first structured call-bound receipt missing", "host_call_bound_receipt_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const index = records.findIndex((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=equipment_tuning")
        && entry.line.includes(" cmd=snapshot "));
    records.splice(index, 1);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("structured call-bound Web call id drift", "host_call_bound_receipt_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=equipment_tuning")
        && entry.line.includes(" cmd=snapshot "));
    record.line = record.line.replace("webCallId=first.equipment_tuning.1",
      "webCallId=forged.call");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("structured call-bound action drift", "host_call_bound_receipt_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=inventory"));
    record.line = record.line.replace("action=inventorySnapshot", "action=inventoryTooltip");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("structured call-bound panel owner drift", "host_call_bound_receipt_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=inventory"));
    record.line = record.line.replace("panel=workbench", "panel=other");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("structured call-bound field set is open", "host_call_bound_receipt_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=inventory"));
    record.line += " payload=forbidden";
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("structured call-bound receipt occurs after Flash command", "host_timeline_regression", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const dispatchIndex = records.findIndex((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=inventory"));
    const dispatch = records.splice(dispatchIndex, 1)[0];
    const responseIndex = records.findIndex((entry) =>
      entry.line.includes("task=inventory_response"));
    records.splice(responseIndex + 1, 0, dispatch);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("AS2 response occurs before Flash command", "host_timeline_regression", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const responseIndex = records.findIndex((entry) =>
      entry.line.includes("task=inventory_response"));
    const response = records.splice(responseIndex, 1)[0];
    const callBoundIndex = records.findIndex((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=inventory"));
    records.splice(callBoundIndex + 1, 0, response);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("first AS2 response missing", "as2_response_mapping_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const index = records.findIndex((entry) =>
      entry.line.includes("task=equipment_tuning_response command=snapshot"));
    records.splice(index, 1);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("AS2 preview token ref forged", "as2_response_mapping_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("task=equipment_tuning_response command=preview"));
    record.line = record.line.replace(/tuningTokenRef=sha256_[a-f0-9]{24}/,
      "tuningTokenRef=" + tokenRef("forged-as2-preview-token"));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("AS2 commit transaction ref forged", "as2_response_mapping_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("task=equipment_tuning_response command=commit"));
    record.line = record.line.replace(/transactionIdRef=sha256_[a-f0-9]{24}/,
      "transactionIdRef=" + tokenRef("forged-as2-transaction"));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Inventory response command receipt drift", "as2_response_mapping_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("task=inventory_response cmd=other"));
    record.line = record.line.replace("cmd=other", "cmd=snapshot");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("AS2 call id reused", "as2_call_id_reused", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const inventoryCommand = records.find((entry) =>
      entry.line.includes("[InventoryTask] -> Flash:") && entry.line.includes("cmd=inventorySnapshot"));
    const inventoryDispatch = records.find((entry) =>
      entry.line.includes("event=authority_flash_call_bound domain=inventory"));
    const inventoryResponse = records.find((entry) =>
      entry.line.includes("task=inventory_response"));
    inventoryCommand.line = inventoryCommand.line.replace(/callId=\d+/, "callId=1");
    inventoryDispatch.line = inventoryDispatch.line.replace(/flashCallId=\d+/, "flashCallId=1");
    inventoryResponse.line = inventoryResponse.line.replace(/callId=\d+/, "callId=1");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host command multiset extra", "host_command_multiset_invalid", (b) => {
    const prefix = b.runtime.first.finalLogSnapshot.records.slice(-1)[0].line.slice(0, 13);
    b.runtime.first.finalLogSnapshot.records.push({ lineNumber: 0,
      line: prefix + '[EquipmentTuningTask] -> Flash: {"task":"cmd","action":"snapshot","callId":999,"requestCallId":"unrelated"}' });
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host call-bound multiset extra", "host_command_multiset_invalid", (b) => {
    const prefix = b.runtime.first.finalLogSnapshot.records.slice(-1)[0].line.slice(0, 13);
    b.runtime.first.finalLogSnapshot.records.push({ lineNumber: 0,
      line: prefix + "event=authority_flash_call_bound domain=inventory webCallId=unrelated flashCallId=999"
        + " panel=workbench panelInstanceId=panel_equipment_fixture_first"
        + " cmd=snapshot action=inventorySnapshot" });
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("AS2 response duplicate success field is rejected", "as2_response_mapping_invalid", (b) => {
    const record = hostRecord(b, "first", "task=equipment_tuning_response command=preview", 0);
    record.line += " success=false";
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("AS2 response duplicate tuning token field is rejected", "as2_response_mapping_invalid", (b) => {
    const record = hostRecord(b, "first", "task=equipment_tuning_response command=preview", 0);
    const value = /tuningTokenRef=(sha256_[a-f0-9]{24})/.exec(record.line)[1];
    record.line += " tuningTokenRef=" + value;
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Inventory command duplicate cmd field is rejected", "host_flash_command_invalid", (b) => {
    const record = hostRecord(b, "first", "[InventoryTask] -> Flash:", 0);
    record.line += " cmd=inventorySnapshot";
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("unused extra AS2 response is rejected", "host_command_multiset_invalid", (b) => {
    const prefix = b.runtime.first.finalLogSnapshot.records.slice(-1)[0].line.slice(0, 13);
    b.runtime.first.finalLogSnapshot.records.push({ lineNumber: 0,
      line: prefix + "[XmlSocket:JSON] task=inventory_response cmd=other callId=999 success=true"
        + " payload=redacted len=100" });
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("preview settled receipt duplicate token field is rejected", "host_preview_receipt_invalid", (b) => {
    const record = hostRecord(b, "first", "event=equipment_tuning_preview_settled", 0);
    const value = /tokenRef=(sha256_[a-f0-9]{24})/.exec(record.line)[1];
    record.line += " tokenRef=" + value;
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("preview settled receipt duplicate Web call field is rejected", "host_preview_receipt_invalid", (b) => {
    const record = hostRecord(b, "first", "event=equipment_tuning_preview_settled", 0);
    record.line += " webCallId=duplicate";
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("preview settled receipt unknown field is rejected", "host_preview_receipt_invalid", (b) => {
    const record = hostRecord(b, "first", "event=equipment_tuning_preview_settled", 0);
    record.line += " unknown=forbidden";
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("preview settled receipt occurs before AS2 response", "host_timeline_regression", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    placeBefore(records, hostRecord(b, "first", "event=equipment_tuning_preview_settled", 0),
      hostRecord(b, "first", "task=equipment_tuning_response command=preview", 0));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("commit settled receipt occurs before AS2 response", "host_timeline_regression", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    placeBefore(records, hostRecord(b, "first", "event=equipment_tuning_commit_settled", 0),
      hostRecord(b, "first", "task=equipment_tuning_response command=commit", 0));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("extra unrelated preview settled receipt is rejected", "host_command_multiset_invalid", (b) => {
    const extra = clone(hostRecord(b, "first", "event=equipment_tuning_preview_settled", 0));
    const prefix = b.runtime.first.finalLogSnapshot.records.slice(-1)[0].line.slice(0, 13);
    extra.line = prefix + extra.line.slice(13).replace(/webCallId=\S+/, "webCallId=unrelated")
      .replace(/requestCallId=\S+/, "requestCallId=unrelated");
    b.runtime.first.finalLogSnapshot.records.push(extra);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host preview B call-bound crosses preview A", "host_timeline_regression", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    placeBefore(records,
      hostRecord(b, "first", "webCallId=first.equipment_tuning.4", 0),
      hostRecord(b, "first", "webCallId=first.equipment_tuning.3", 0));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host fresh snapshot call-bound crosses commit", "host_timeline_regression", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    placeBefore(records,
      hostRecord(b, "first", "event=authority_flash_call_bound domain=equipment_tuning webCallId=first.equipment_tuning.7", 0),
      hostRecord(b, "first", "event=authority_flash_call_bound domain=equipment_tuning webCallId=first.equipment_tuning.5", 0));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("snapshot confirmation missing", "host_snapshot_receipt_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const record = hostRecord(b, "first", "event=equipment_tuning_snapshot_confirmed", 0);
    records.splice(records.indexOf(record), 1);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("snapshot confirmation duplicated", "host_snapshot_receipt_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const duplicate = clone(hostRecord(b, "first", "event=equipment_tuning_snapshot_confirmed", 0));
    duplicate.line = records.slice(-1)[0].line.slice(0, 13) + duplicate.line.slice(13);
    records.push(duplicate);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("snapshot confirmation state reference drift", "host_snapshot_receipt_invalid", (b) => {
    const record = hostRecord(b, "first", "event=equipment_tuning_snapshot_confirmed", 0);
    record.line = record.line.replace(/stateRef=sha256_[a-f0-9]{24}/,
      "stateRef=" + tokenRef("forged-snapshot-state"));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("snapshot confirmation source reference drift", "host_snapshot_receipt_invalid", (b) => {
    const record = hostRecord(b, "first", "event=equipment_tuning_snapshot_confirmed", 0);
    record.line = record.line.replace(/sourceKeyRef=sha256_[a-f0-9]{24}/,
      "sourceKeyRef=" + tokenRef("forged-snapshot-source"));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("snapshot confirmation epoch drift", "host_snapshot_receipt_invalid", (b) => {
    const record = hostRecord(b, "first", "event=equipment_tuning_snapshot_confirmed", 0);
    record.line = record.line.replace("writeEpoch=0", "writeEpoch=9");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Equipment command requestCallId drift", "host_flash_command_invalid", (b) => {
    const record = hostRecord(b, "first", "[EquipmentTuningTask] -> Flash:", 0);
    record.line = record.line.replace('"requestCallId":"first.equipment_tuning.1"',
      '"requestCallId":"forged"');
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Equipment command panel owner drift", "host_flash_command_invalid", (b) => {
    const record = hostRecord(b, "first", "[EquipmentTuningTask] -> Flash:", 0);
    record.line = record.line.replace('"panelInstanceId":"panel_equipment_fixture_first"',
      '"panelInstanceId":"forged"');
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Equipment command view owner drift", "host_flash_command_invalid", (b) => {
    const record = hostRecord(b, "first", "[EquipmentTuningTask] -> Flash:", 0);
    record.line = record.line.replace('"viewSessionId":"tuning_fixture_first"',
      '"viewSessionId":"forged"');
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Equipment command write epoch drift", "host_flash_command_invalid", (b) => {
    const record = hostRecord(b, "first", "[EquipmentTuningTask] -> Flash:", 0);
    record.line = record.line.replace('"writeEpoch":0', '"writeEpoch":9');
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Equipment command duplicate JSON field is rejected", "host_flash_command_invalid", (b) => {
    const record = hostRecord(b, "first", "[EquipmentTuningTask] -> Flash:", 0);
    record.line = record.line.replace('{"task":"cmd",', '{"task":"cmd","task":"cmd",');
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("request-derived source ref forged", "preview_authority_binding_mismatch", (b) => {
    request(b, "first", "equipment_tuning", "preview", 0)
      .authorityBinding.sourceKeyRef = tokenRef("forged-request-source");
    resealTranscript(b.transcripts.first);
  });
  negative("request-derived intent ref forged", "authority_diagnostic_not_exact", (b) => {
    request(b, "first", "equipment_tuning", "preview", 0)
      .authorityBinding.intentKeyRef = tokenRef("forged-request-intent");
    resealTranscript(b.transcripts.first);
  });
  negative("Web diagnostic source ref forged", "authority_diagnostic_not_exact", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.message
      && entry.message.event === "preview_issued");
    event.message.sourceKeyRef = tokenRef("forged-debug-source");
    resealTranscript(b.transcripts.first);
  });
  negative("Web diagnostic binding forged consistently", "authority_diagnostic_not_exact", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.message
      && entry.message.event === "preview_issued");
    event.message.sourceKeyRef = tokenRef("forged-debug-source");
    event.authorityBinding.sourceKeyRef = event.message.sourceKeyRef;
    resealTranscript(b.transcripts.first);
  });
  negative("Host source ref forged consistently", "host_preview_receipt_invalid", (b) => {
    const forged = tokenRef("forged-host-source");
    b.runtime.first.finalLogSnapshot.records.forEach((record) => {
      record.line = record.line.replace(/sourceKeyRef=sha256_[a-f0-9]{24}/g,
        "sourceKeyRef=" + forged);
    });
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host intent ref forged consistently", "host_preview_receipt_invalid", (b) => {
    const forged = tokenRef("forged-host-intent");
    b.runtime.first.finalLogSnapshot.records.forEach((record) => {
      record.line = record.line.replace(/intentKeyRef=sha256_[a-f0-9]{24}/g,
        "intentKeyRef=" + forged);
    });
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host preview pending count is not settled", "host_preview_receipt_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("event=equipment_tuning_preview_settled"));
    record.line = record.line.replace("remainingPending=0", "remainingPending=1");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host commit state reference forged", "host_commit_receipt_invalid", (b) => {
    const record = b.runtime.first.finalLogSnapshot.records.find((entry) =>
      entry.line.includes("event=equipment_tuning_commit_settled"));
    record.line = record.line.replace(/stateRef=sha256_[a-f0-9]{24}/,
      "stateRef=" + tokenRef("forged-state"));
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host raw source key field persisted", "host_raw_authority_field_present", (b) => {
    const prefix = b.runtime.first.finalLogSnapshot.records.slice(-1)[0].line.slice(0, 13);
    b.runtime.first.finalLogSnapshot.records.push({ lineNumber: 0,
      line: prefix + "event=bad sourceKey=inventory:%E8%83%8C%E5%8C%85:7:raw-lease" });
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host raw tuning token field persisted", "host_raw_authority_field_present", (b) => {
    const prefix = b.runtime.first.finalLogSnapshot.records.slice(-1)[0].line.slice(0, 13);
    b.runtime.first.finalLogSnapshot.records.push({ lineNumber: 0,
      line: prefix + "event=bad tuningToken=raw-authority-token" });
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("transcript raw intent key field persisted", "raw_authority_key_present", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.message
      && entry.message.event === "preview_issued");
    event.message.intentKey = "install_mod|raw|";
    resealTranscript(b.transcripts.first);
  });
  negative("Host log snapshot digest drift", "log_snapshot_digest_mismatch", (b) => {
    b.runtime.first.finalLogSnapshot.tailSha256 = "0".repeat(64);
  });
  negative("first Host exact close completion is required", "host_close_receipt_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const close = hostRecord(b, "first", "event=panel_exact_close_completed", 0);
    records.splice(records.indexOf(close), 1);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host exact close completion cannot be duplicated", "host_close_receipt_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const duplicate = clone(hostRecord(b, "first", "event=panel_exact_close_completed", 0));
    duplicate.line = records.slice(-1)[0].line.slice(0, 13) + duplicate.line.slice(13);
    records.push(duplicate);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host exact close completion cannot cross panel owner",
    "host_close_receipt_invalid", (b) => {
      const close = hostRecord(b, "first", "event=panel_exact_close_completed", 0);
      close.line = close.line.replace("panel_equipment_fixture_first", "foreign-owner");
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("Host exact close completion must follow detach response",
    "host_close_receipt_invalid", (b) => {
      const records = b.runtime.first.finalLogSnapshot.records;
      placeBefore(records, hostRecord(b, "first", "event=panel_exact_close_completed", 0),
        hostRecord(b, "first", "task=equipment_tuning_response command=detach", 0));
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("Host exact close receipt field set is closed", "host_close_receipt_invalid", (b) => {
    hostRecord(b, "first", "event=panel_exact_close_completed", 0).line += " outcome=success";
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host near-match response family is rejected", "host_relevant_record_invalid", (b) => {
    pushTimestampedHostRecord(b, "first",
      "event=equipment_tuning_response_family envelope=near_match rejected=true");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host malformed response family is rejected", "host_relevant_record_invalid", (b) => {
    pushTimestampedHostRecord(b, "first",
      "[XmlSocket:JSON] task=equipment_tuning_response envelope=malformed");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host rejected close record is not ignorable", "host_relevant_record_invalid", (b) => {
    pushTimestampedHostRecord(b, "first",
      "event=panel_exact_close_rejected panel=workbench rejected=true");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host deferred close record is not ignorable", "host_relevant_record_invalid", (b) => {
    pushTimestampedHostRecord(b, "first", "[Workbench] close deferred panel=workbench");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host replacement race record is not ignorable", "host_relevant_record_invalid", (b) => {
    pushTimestampedHostRecord(b, "first",
      "[Workbench] equipment_tuning ignored after replacement");
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host extra panel request summary is rejected", "host_command_multiset_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const extra = clone(hostRecord(b, "first", "[Panel] HandlePanelMessage:", 0));
    extra.line = extra.line.replace(/callId=[^ ]+/, "callId=unrelated");
    extra.line = records.slice(-1)[0].line.slice(0, 13) + extra.line.slice(13);
    records.push(extra);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host extra route record is rejected", "host_command_multiset_invalid", (b) => {
    const records = b.runtime.first.finalLogSnapshot.records;
    const duplicate = clone(hostRecord(b, "first", "[Panel] Routing ", 0));
    duplicate.line = records.slice(-1)[0].line.slice(0, 13) + duplicate.line.slice(13);
    records.push(duplicate);
    resealLog(b.runtime.first.finalLogSnapshot);
  });
  negative("Host relevant marker cannot follow an arbitrary prefix",
    "host_relevant_record_invalid", (b) => {
      const record = hostRecord(b, "first", "[Panel] HandlePanelMessage:", 0);
      record.line = "diagnostic-prefix " + record.line;
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("Host relevant marker cannot follow two production timestamp prefixes",
    "host_relevant_record_invalid", (b) => {
      const record = hostRecord(b, "first", "[Panel] Routing ", 0);
      record.line = "12:34:56.789 12:34:56.790 " + record.line;
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("Host production timestamp prefix spelling is exact",
    "host_relevant_record_invalid", (b) => {
      const record = hostRecord(b, "first", "[XmlSocket:JSON] task=inventory_response", 0);
      record.line = "12:34:56.789  " + record.line;
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("Host relevant line cannot carry multiple recognized markers",
    "host_relevant_record_invalid", (b) => {
      const record = hostRecord(b, "first", "event=panel_exact_close_completed", 0);
      record.line += " [Panel] Routing domain=inventory cmd=snapshot"
        + " to InventoryTask, _inventoryTask=ok";
      resealLog(b.runtime.first.finalLogSnapshot);
    });

  negative("capability preferred availability contradiction", "capability_preference_violated", (b) => {
    b.control.capability.available = true;
  });
  negative("capability untrusted source", "capability_evidence_untrusted", (b) => {
    b.control.capability.source = "operator_claim";
  });
  negative("capability artifact digest drift", "capability_evidence_untrusted", (b) => {
    b.control.capability.artifactSha256 = "0".repeat(64);
  });
  negative("control request missing", "control_set_count_invalid", (b) => { b.control.requests.pop(); });
  negative("control ack missing", "control_set_count_invalid", (b) => { b.control.acks.pop(); });
  negative("control request field set is closed", "control_request_invalid", (b) => {
    b.control.requests[0].providerOperationId = "forbidden-provider-field";
  });
  negative("control acknowledgement field set is closed", "control_ack_invalid", (b) => {
    b.control.acks[0].providerOperationId = "forbidden-provider-field";
  });
  negative("control request run identity is exact", "control_request_invalid", (b) => {
    b.control.requests[0].runId = "other-run";
  });
  negative("control acknowledgement run identity is exact", "control_ack_invalid", (b) => {
    b.control.acks[0].runId = "other-run";
  });
  negative("provider reference field set is closed", "control_ack_invalid", (b) => {
    b.control.acks[0].providerReceipt.source = "forbidden-inline-provider-result";
  });
  negative("control wrong transport", "control_ack_invalid", (b) => {
    b.control.acks[0].transport = "launcher_agent_runtime";
  });
  negative("control non-completed result", "control_exchange_incomplete", (b) => {
    b.control.acks[0].result = "failed";
  });
  negative("control capture digest drift", "control_ack_capture_invalid", (b) => {
    const ack = b.control.acks.find((entry) => entry.capture);
    ack.captureSha256 = "0".repeat(64);
  });
  negative("control acknowledgement completion order cannot invert",
    "control_partial_order_invalid", (b) => {
      b.control.acks[0].completedAt = "2026-08-03T00:09:16.000Z";
    });
  negative("SAFEEXIT capture requirement cannot be disabled",
    "control_capture_policy_invalid", (b) => {
      const requestValue = b.control.requests.find((entry) => entry.step === "safe_exit");
      const ack = b.control.acks.find((entry) => entry.requestId === requestValue.requestId);
      requestValue.requiresCaptureSha256 = false;
      ack.captureSha256 = null;
      ack.capture = null;
    });
  negative("EXIT_CONFIRM capture byte count is bound", "capture_digest_mismatch", (b) => {
    const requestValue = b.control.requests.find((entry) => entry.step === "exit_confirm");
    const ack = b.control.acks.find((entry) => entry.requestId === requestValue.requestId);
    ack.capture.bytes += 1;
  });
  negative("one control cannot borrow another provider capture",
    "provider_capture_reference_invalid", (b) => {
      const source = b.control.acks[1];
      b.control.acks[0].capture = clone(source.capture);
      b.control.acks[0].captureSha256 = source.captureSha256;
  });
  negative("eight-byte PNG signature remains invalid after envelope reseal",
    "control_capture_media_invalid", (b) => {
      mutateControlCapture(b, "safe_exit", Buffer.from("89504e470d0a1a0a", "hex"));
    });
  negative("PNG trailing bytes remain invalid after envelope reseal",
    "control_capture_media_invalid", (b) => {
      const entry = b.control.acks.find((ack) => ack.step === "exit_confirm");
      const filePath = path.join(b.runDir, entry.capture.relativePath.replace(/\//g, path.sep));
      mutateControlCapture(b, "exit_confirm",
        Buffer.concat([fs.readFileSync(filePath), Buffer.from([0])]));
    });
  negative("PNG CRC corruption remains invalid after envelope reseal",
    "control_capture_media_invalid", (b) => {
      const entry = b.control.acks.find((ack) => ack.step === "safe_exit");
      const filePath = path.join(b.runDir, entry.capture.relativePath.replace(/\//g, path.sep));
      const bytes = Buffer.from(fs.readFileSync(filePath));
      bytes[29] ^= 1;
      mutateControlCapture(b, "safe_exit", bytes);
    });
  negative("provider capture rejects an out-of-range indexed palette sample after full reseal",
    "control_capture_media_invalid", (b) => {
      const bytes = indexedPng(4, 3, 3);
      mutateControlCapture(b, "safe_exit", bytes);
    });
  negative("provider receipt reference path is exact",
    "provider_receipt_reference_invalid", (b) => {
      b.control.acks[0].providerReceipt.artifact = "control/provider-receipts/other.json";
    });
  negative("provider receipt file hash is exact", "provider_receipt_hash_mismatch", (b) => {
    b.control.acks[0].providerReceipt.sha256 = "0".repeat(64);
  });
  negative("provider capture event reference path is exact",
    "provider_capture_event_reference_invalid", (b) => {
      mutateProviderReceipt(b, "open_tuning", (receipt) => {
        receipt.captureEventRef.artifact = "control/capture-events/other.json";
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider capture event file hash is exact",
    "provider_capture_event_hash_mismatch", (b) => {
      mutateProviderReceipt(b, "select_source", (receipt) => {
        receipt.captureEventRef.sha256 = "0".repeat(64);
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider capture event self-digest cannot drift",
    "provider_capture_event_invalid", (b) => {
      mutateProviderCaptureEvent(b, "preview_candidate_a", (event) => {
        event.eventSha256 = "0".repeat(64);
      }, false);
    });
  negative("provider capture event cannot cross request identity",
    "provider_capture_event_invalid", (b) => {
      mutateProviderCaptureEvent(b, "preview_candidate_b", (event) => {
        event.requestId = "fixture-other-request";
      });
    });
  negative("provider capture event cannot claim independent business semantics",
    "provider_capture_event_invalid", (b) => {
      mutateProviderCaptureEvent(b, "commit_candidate_b", (event) => {
        event.captureSemanticContentIndependentlyVerified = true;
      });
    });
  negative("provider capture event rejects a stale PNG mtime",
    "provider_capture_event_invalid", (b) => {
      const entry = providerCaptureEventEntry(b, "reselect_source");
      const capturePath = path.join(b.runDir,
        entry.value.captureArtifact.replace(/\//g, path.sep));
      fs.utimesSync(capturePath, new Date("2020-01-01T00:00:00.000Z"),
        new Date("2020-01-01T00:00:00.000Z"));
    });
  negative("provider capture event rejects pre-request capturedAt",
    "provider_capture_event_invalid", (b) => {
      const requestValue = b.control.requests.find((entry) => entry.step === "close_first_tuning");
      mutateProviderCaptureEvent(b, "close_first_tuning", (event) => {
        event.capturedAt = new Date(Date.parse(requestValue.issuedAt) - 1).toISOString();
      });
    });
  negative("provider capture event binds the current PNG bytes",
    "provider_capture_event_invalid", (b) => {
      mutateControlCapture(b, "restart_open_tuning", Fixture.fixturePng(777));
    });
  negative("provider receipt self-digest cannot drift",
    "provider_receipt_digest_invalid", (b) => {
      mutateProviderReceipt(b, "open_tuning", (receipt) => {
        receipt.receiptSha256 = "0".repeat(64);
      }, false);
    });
  negative("legacy provider receipt v4 fails closed",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "open_tuning", (receipt) => {
        receipt.schema = "workbench-live-e2e.equipment.provider-receipt.v4";
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider receipt field set is closed after evidence reseal",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "select_source", (receipt) => {
        receipt.providerLikeExtra = "forbidden";
      });
    });
  negative("provider receipt source remains tool-result bound after evidence reseal",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "preview_candidate_a", (receipt) => {
        receipt.source = "operator_claim";
      });
    });
  negative("provider receipt request identity remains bound after evidence reseal",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "preview_candidate_b", (receipt) => {
        receipt.requestId = "fixture-other-request";
      });
    });
  negative("provider receipt step remains bound after evidence reseal",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "commit_candidate_b", (receipt) => {
        receipt.step = "preview_candidate_b";
        receipt.action = "preview_candidate_b";
      });
    });
  negative("provider receipt result remains bound after evidence reseal",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "reselect_source", (receipt) => {
        receipt.result = "failed";
      });
    });
  negative("provider receipt completion remains close to acknowledgement",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "close_first_tuning", (receipt) => {
        receipt.completedAt = "2026-08-03T00:10:01.000Z";
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider receipt start time spelling is canonical UTC",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "restart_open_tuning", (receipt) => {
        receipt.startedAt = "2026-08-03 00:10:35Z";
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  ["startedAt", "completedAt"].forEach((field) => {
    negative("provider receipt cannot omit stage " + field,
      "provider_receipt_invalid", (b) => {
        mutateProviderReceipt(b, "preview_candidate_a", (receipt) => {
          delete receipt[field];
        });
      });
  });
  negative("provider capture cannot precede provider input",
    "provider_receipt_invalid", (b) => {
      const receipt = providerReceiptEntry(b, "preview_candidate_b").value;
      mutateProviderCaptureEvent(b, "preview_candidate_b", (event) => {
        event.capturedAt = receipt.startedAt;
      });
    });
  negative("provider completion cannot precede provider capture",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "commit_candidate_b", (receipt) => {
        receipt.completedAt = providerCaptureEventEntry(b,
          "commit_candidate_b").value.fileModifiedAt;
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider operation id is closed after evidence reseal",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "restart_select_source", (receipt) => {
        receipt.providerOperationId = "bad id";
      });
    });
  negative("provider operation id cannot be reused across request bindings",
    "provider_receipt_invalid", (b) => {
      const firstOperationId = providerReceiptEntry(b, "open_tuning").value.providerOperationId;
      mutateProviderReceipt(b, "select_source", (receipt) => {
        receipt.providerOperationId = firstOperationId;
      });
    });
  negative("provider operation ids cannot be swapped and resealed",
    "provider_receipt_invalid", (b) => {
      const firstId = providerReceiptEntry(b, "select_source").value.providerOperationId;
      const secondId = providerReceiptEntry(b, "preview_candidate_a").value.providerOperationId;
      mutateProviderReceipt(b, "select_source", (receipt) => {
        receipt.providerOperationId = secondId;
      });
      mutateProviderReceipt(b, "preview_candidate_a", (receipt) => {
        receipt.providerOperationId = firstId;
      });
    });
  negative("one DOM event cannot be reused by two provider operations",
    "provider_dom_event_binding_invalid", (b) => {
      const firstReference = providerReceiptEntry(b, "select_source").value.inputEvidence.eventRef;
      mutateProviderReceipt(b, "reselect_source", (receipt) => {
        receipt.inputEvidence.eventRef = clone(firstReference);
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("native provider input cannot omit its provider-owned event reference",
    "provider_input_evidence_invalid", (b) => {
      mutateProviderReceipt(b, "open_tuning", (receipt) => {
        receipt.inputEvidence.eventRef = null;
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("native provider event bytes cannot drift from their exact reference",
    "provider_native_input_binding_invalid", (b) => {
      const entry = providerReceiptEntry(b, "safe_exit");
      const eventPath = path.join(b.runDir,
        entry.value.inputEvidence.eventRef.artifact.replace(/\//g, path.sep));
      fs.appendFileSync(eventPath, " \n", "utf8");
    });
  negative("native provider event target cannot differ from mirrored receipt evidence",
    "provider_native_input_binding_invalid", (b) => {
      mutateNativeInputEvent(b, "exit_confirm", (eventValue) => {
        eventValue.selector = "native OTHER";
      });
    });
  negative("native provider event cannot precede its control request",
    "provider_receipt_invalid", (b) => {
      const requestValue = b.control.requests.find((entry) => entry.step === "open_tuning");
      const before = new Date(Date.parse(requestValue.issuedAt) - 1).toISOString();
      mutateNativeInputEvent(b, "open_tuning", (eventValue) => {
        eventValue.observedAt = before;
        eventValue.receivedAt = before;
      }).provider.value.inputEvidence.observedAt = before;
      mutateProviderReceipt(b, "open_tuning", (receipt) => {
        receipt.inputEvidence.observedAt = before;
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("native observer receipt cannot follow provider completion",
    "provider_receipt_invalid", (b) => {
      const provider = providerReceiptEntry(b, "restart_open_tuning");
      const afterProvider = new Date(Date.parse(provider.value.completedAt) + 1).toISOString();
      mutateNativeInputEvent(b, "restart_open_tuning", (eventValue) => {
        eventValue.observedAt = afterProvider;
        eventValue.receivedAt = afterProvider;
      });
      mutateProviderReceipt(b, "restart_open_tuning", (receipt) => {
        receipt.inputEvidence.observedAt = afterProvider;
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("native event observed time cannot follow its provider receipt time",
    "provider_native_input_binding_invalid", (b) => {
      mutateNativeInputEvent(b, "safe_exit", (eventValue) => {
        eventValue.observedAt = new Date(Date.parse(eventValue.receivedAt) + 1).toISOString();
      });
    });
  negative("provider completion cannot follow acknowledgement completion",
    "provider_receipt_invalid", (b) => {
      const ack = b.control.acks.find((entry) => entry.step === "exit_confirm");
      mutateProviderReceipt(b, "exit_confirm", (receipt) => {
        receipt.completedAt = new Date(Date.parse(ack.completedAt) + 1).toISOString();
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider input selector is request-bound",
    "provider_input_evidence_invalid", (b) => {
      mutateProviderReceipt(b, "preview_candidate_a", (receipt) => {
        receipt.inputEvidence.selector = "button[data-candidate-key=\"wrong\"]";
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider input point must remain inside its captured rect",
    "provider_input_evidence_invalid", (b) => {
      mutateProviderReceipt(b, "preview_candidate_b", (receipt) => {
        receipt.inputEvidence.clientPoint.x = receipt.inputEvidence.rect.right + 1;
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider click cannot carry a keyboard key",
    "provider_input_evidence_invalid", (b) => {
      mutateProviderReceipt(b, "commit_candidate_b", (receipt) => {
        receipt.inputEvidence.key = "Enter";
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("provider DOM reference cannot point at another ordered event",
    "provider_dom_event_binding_invalid", (b) => {
      const wrongReference = providerReceiptEntry(b, "select_source").value.inputEvidence.eventRef;
      mutateProviderReceipt(b, "preview_candidate_a", (receipt) => {
        receipt.inputEvidence.eventRef = clone(wrongReference);
        receipt.providerOperationId = expectedProviderOperationId(receipt);
      });
    });
  negative("authorization candidate scope drift", "authorization_scope_invalid", (b) => {
    b.control.authorization.scope.candidateKey = "other";
    resealDigest(b.control.authorization, "unused");
  });
  negative("authorization digest drift", "authorization_decision_invalid", (b) => {
    b.control.authorizationSha256 = "0".repeat(64);
    const requestValue = b.control.requests.find((entry) => entry.requiresCommitAuthorization);
    requestValue.authorizationRef.decisionSha256 = "0".repeat(64);
  });
  negative("commit input untrusted", "trusted_input_contract_invalid", (b) => {
    const event = b.transcripts.first.events.find((e) => e.kind === "dom_input"
      && e.target && e.target.selector
        === ".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]");
    event.isTrusted = false;
    resealTranscript(b.transcripts.first);
  });
  negative("source trusted click physical slot drift", "trusted_input_target_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input"
      && entry.target && entry.target.attributes["data-physical-slot"]);
    event.target.attributes["data-physical-slot"] = "8";
    resealTranscript(b.transcripts.first);
  });
  negative("first close trusted input missing", "trusted_input_multiset_invalid", (b) => {
    b.transcripts.first.events = b.transcripts.first.events.filter((entry) => !(entry.kind === "dom_input"
      && entry.target && entry.target.attributes["data-header-action"] === "close"));
    resealTranscript(b.transcripts.first);
  });
  negative("first close trusted input targets wrong action", "trusted_input_target_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input"
      && entry.target && entry.target.attributes["data-header-action"] === "close");
    event.target.attributes["data-header-action"] = "other";
    resealTranscript(b.transcripts.first);
  });
  negative("restart close trusted input missing", "restart_input_multiset_invalid", (b) => {
    b.transcripts.restart.events = b.transcripts.restart.events.filter((entry) => !(entry.kind === "dom_input"
      && entry.target && entry.target.attributes["data-header-action"] === "close"));
    resealTranscript(b.transcripts.restart);
  });
  negative("source input count extra", "trusted_input_multiset_invalid", (b) => {
    const event = clone(b.transcripts.first.events.find((e) => e.kind === "dom_input"
      && e.target && e.target.attributes["data-physical-slot"]));
    b.transcripts.first.events.splice(-1, 0, event);
    resealTranscript(b.transcripts.first);
  });
  negative("restart source input untrusted", "trusted_input_contract_invalid", (b) => {
    b.transcripts.restart.events.find((e) => e.kind === "dom_input").isTrusted = false;
    resealTranscript(b.transcripts.restart);
  });

  negative("seed artifact changed", "seed_artifact_set_changed", (b) => {
    b.persistence.seedEnd.artifacts[0].sha256 = "9".repeat(64);
    resealArtifactSet(b.persistence.seedEnd);
  });
  negative("restart artifact set changed", "restart_artifact_set_changed", (b) => {
    b.persistence.afterRestart.artifacts[0].sha256 = "9".repeat(64);
    resealArtifactSet(b.persistence.afterRestart);
    b.persistence.stability.afterRestart.set = clone(b.persistence.afterRestart);
    resealDigest(b.persistence.stability.afterRestart, "evidenceSha256");
  });
  negative("prepared set aliases commit", "persistence_artifact_scope_invalid", (b) => {
    b.persistence.targetPrepared = clone(b.persistence.afterCommit);
    b.persistence.stability.targetPrepared.set = clone(b.persistence.targetPrepared);
    resealDigest(b.persistence.stability.targetPrepared, "evidenceSha256");
  });
  negative("stable clone phase digest drift", "clone_phase_invalid", (b) => {
    b.persistence.stability.afterCommit.evidenceSha256 = "0".repeat(64);
  });
  negative("stable clone phase set drift", "clone_phase_set_mismatch", (b) => {
    b.persistence.stability.afterCommit.set = clone(b.persistence.targetPrepared);
    resealDigest(b.persistence.stability.afterCommit, "evidenceSha256");
  });
  negative("initial disk equipment drift", "disk_record_invalid", (b) => {
    b.persistence.diskInitial.equipment.lastUpdate = 999;
  });
  negative("initial disk level/mod projection drift", "disk_record_invalid", (b) => {
    b.persistence.diskInitial.equipment.mods = [Fixture.CANDIDATE_A.itemName];
  });
  negative("disk semantic projection digest drift", "disk_semantic_digest_invalid", (b) => {
    b.persistence.diskInitial.semanticSha256 = "0".repeat(64);
  });
  negative("commit disk materials drift", "disk_record_invalid", (b) => {
    b.persistence.diskAfterCommit.materials[Fixture.CANDIDATE_B.itemName] = 4;
  });
  negative("restart disk hash drift", "disk_persistence_invalid", (b) => {
    b.persistence.diskAfterRestart.sha256 = "9".repeat(64);
  });
  negative("archive order drift", "archive_evidence_invalid", (b) => {
    b.persistence.archiveEvidence.requiredOrder = ["archive", "sv1", "sv2"];
    resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
  });
  negative("archive disk hash drift", "archive_evidence_invalid", (b) => {
    b.persistence.archiveEvidence.disk.sha256 = "9".repeat(64);
    resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
  });
  negative("archive evidence digest drift", "archive_evidence_invalid", (b) => {
    b.persistence.archiveEvidence.evidenceSha256 = "0".repeat(64);
  });
  negative("final commit response must precede close request",
    "host_timeline_regression", (b) => {
      setHostRecordTime(hostRecord(b, "first", "event=equipment_tuning_commit_settled", 0),
        "2026-08-03T00:10:00.500Z");
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("SAFEEXIT completion must precede archive capture",
    "global_partial_order_invalid", (b) => {
      b.persistence.archiveEvidence.disk.capturedAt = "2026-08-03T00:10:14.000Z";
      resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
    });
  negative("archive capture must precede EXIT_CONFIRM issuance",
    "global_partial_order_invalid", (b) => {
      b.persistence.archiveEvidence.disk.capturedAt = "2026-08-03T00:10:21.000Z";
      resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
    });
  negative("exact close completion must precede save control records",
    "global_timeline_record_invalid", (b) => {
      b.persistence.archiveEvidence.positions.sv1.lineNumber =
        hostRecord(b, "first", "event=panel_exact_close_completed", 0).lineNumber;
      resealDigest(b.persistence.archiveEvidence, "evidenceSha256");
    });
  negative("restart loaded closure must precede restart close",
    "global_partial_order_invalid", (b) => {
      b.runtime.restart.loadedProduction.capturedAt = "2026-08-03T00:10:51.000Z";
      resealLoadedProduction(b.runtime.restart.loadedProduction);
    });
  negative("restart close must precede final shutdown residue",
    "global_partial_order_invalid", (b) => {
      b.residue.final.observedAt = "2026-08-03T00:10:54.000Z";
      resealDigest(b.residue.final, "evidenceSha256");
    });
  negative("authenticated restart shutdown evidence cannot disappear",
    "authenticated_shutdown_missing", (b) => {
      delete b.runtime.restart.shutdownEvidence;
    });
  negative("authenticated restart shutdown must bind the restart session",
    "authenticated_shutdown_invalid", (b) => {
      b.runtime.restart.shutdownEvidence.sessionEvidenceSha256 = "0".repeat(64);
      resealDigest(b.runtime.restart.shutdownEvidence, "evidenceSha256");
    });
  negative("authenticated restart shutdown response must succeed",
    "launcher_task_failed", (b) => {
      b.runtime.restart.shutdownEvidence.response.success = false;
      b.runtime.restart.shutdownEvidence.response.ok = false;
      resealDigest(b.runtime.restart.shutdownEvidence, "evidenceSha256");
    });
  negative("restart close must precede authenticated shutdown request",
    "global_partial_order_invalid", (b) => {
      b.runtime.restart.shutdownEvidence.requestedAt = "2026-08-03T00:10:54.000Z";
      b.runtime.restart.shutdownEvidence.completedAt = "2026-08-03T00:10:54.500Z";
      resealDigest(b.runtime.restart.shutdownEvidence, "evidenceSha256");
    });
  negative("release lock remains", "clone_release_invalid", (b) => {
    b.persistence.release.lockRelease.lockFileAbsent = false;
    resealDigest(b.persistence.release, "releaseSha256");
  });
  negative("release recovery remains", "clone_release_invalid", (b) => {
    b.persistence.release.recoveryClear.recoveryFileAbsent = false;
    resealDigest(b.persistence.release, "releaseSha256");
  });
  negative("release digest drift", "clone_release_invalid", (b) => {
    b.persistence.release.releaseSha256 = "0".repeat(64);
  });
  negative("first residue process remains", "runtime_residue_not_clean", (b) => {
    b.residue.afterSafeExit.pidAbsent = false;
    resealDigest(b.residue.afterSafeExit, "evidenceSha256");
  });
  negative("final residue port remains", "runtime_residue_not_clean", (b) => {
    b.residue.final.ports[0].open = true;
    resealDigest(b.residue.final, "evidenceSha256");
  });
  negative("residue digest drift", "runtime_residue_evidence_mismatch", (b) => {
    b.residue.final.evidenceSha256 = "0".repeat(64);
  });

  negative("bundle evidence mode is closed", "bundle_invalid", (b) => {
    b.evidenceMode = "synthetic_live";
  });
  negative("offline fixture cannot claim a real SAFEEXIT journey", "bundle_invalid", (b) => {
    b.safeExitUiJourneyVerified = true;
  });
  negative("offline fixture provenance is mandatory", "bundle_invalid", (b) => {
    b.fixtureProvenance = null;
  });
  negative("live capture cannot carry fixture provenance", "bundle_invalid", (b) => {
    b.evidenceMode = "live_capture";
    b.safeExitUiJourneyVerified = true;
    b.exitMethod = "native_safe_exit_then_exit_confirm";
  });

  negative("raw CDP script occurrence order cannot be statically rewritten",
    "loaded_production_tool_script_invalid", (b) => {
      const values = b.runtime.first.loadedProduction.scriptOccurrences;
      const page = values.shift();
      values.reverse();
      values.unshift(page);
      values.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("raw CDP script occurrences reject a foreign executable",
    "loaded_production_script_occurrence_invalid", (b) => {
      const values = b.runtime.first.loadedProduction.scriptOccurrences;
      const foreign = clone(values[1]);
      foreign.occurrence = values.length + 1;
      foreign.url = "https://foreign.invalid/producer.js";
      foreign.origin = "https://foreign.invalid";
      foreign.scriptId = "foreign-script";
      foreign.rawParams.url = foreign.url;
      foreign.rawParams.scriptId = foreign.scriptId;
      values.push(foreign);
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("raw CDP script occurrences reject a duplicate executable",
    "loaded_production_script_occurrence_invalid", (b) => {
      const values = b.runtime.first.loadedProduction.scriptOccurrences;
      const duplicate = clone(values[1]);
      duplicate.occurrence = values.length + 1;
      duplicate.scriptId = "duplicate-script-id";
      duplicate.rawParams.scriptId = duplicate.scriptId;
      values.push(duplicate);
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("raw CDP script occurrences reject anonymous executable source",
    "loaded_production_script_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const anonymous = clone(loaded.scriptOccurrences[0]);
      anonymous.occurrence = loaded.scriptOccurrences.length + 1;
      anonymous.url = "";
      anonymous.origin = "opaque";
      anonymous.scriptId = "anonymous-script-id";
      anonymous.rawParams.url = "";
      anonymous.rawParams.scriptId = anonymous.scriptId;
      loaded.scriptOccurrences.push(anonymous);
      resealLoadedProduction(loaded);
    });
  negative("raw CDP execution context cannot detach from its frame",
    "loaded_production_context_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.contextOccurrences[0].auxData.frameId = "foreign-frame";
      resealLoadedProduction(loaded);
    });
  negative("raw CDP context occurrence stream rejects an unexpected second context",
    "loaded_production_context_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const extra = clone(loaded.contextOccurrences[0]);
      extra.occurrence = 2;
      extra.id += 1;
      extra.uniqueId += "-isolated";
      extra.name = "unexpected-isolated-world";
      loaded.contextOccurrences.push(extra);
      resealLoadedProduction(loaded);
    });
  negative("raw CDP context ids cannot be duplicated and resealed",
    "loaded_production_context_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const extra = clone(loaded.contextOccurrences[0]);
      extra.occurrence = 2;
      loaded.contextOccurrences.push(extra);
      resealLoadedProduction(loaded);
    });
  negative("raw CDP context auxData remains an exact unclassified occurrence",
    "loaded_production_context_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.contextOccurrences[0].auxData.isDefault = false;
      resealLoadedProduction(loaded);
    });
  negative("raw script occurrence cannot omit executionContextAuxData",
    "loaded_production_script_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      delete loaded.scriptOccurrences[1].rawParams.executionContextAuxData;
      resealLoadedProduction(loaded);
    });
  negative("raw script executionContextAuxData must equal its referenced context",
    "loaded_production_script_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.scriptOccurrences[1].rawParams.executionContextAuxData.isDefault = false;
      resealLoadedProduction(loaded);
    });
  negative("production script source bytes bind its raw CDP occurrence",
    "loaded_production_script_source_binding_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      replaceRawSource(loaded.scriptOccurrences[1], "changed production source");
      resealLoadedProduction(loaded);
    });
  negative("tool-owned script source bytes bind its source plan",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const tool = loaded.scriptOccurrences.find((entry) =>
        entry.url.startsWith("cf7-evidence://equipment/"));
      replaceRawSource(tool, "(()=>false)()\n//# sourceURL=" + tool.url);
      resealLoadedProduction(loaded);
    });
  negative("terminal observer detach must remain in the captured tool plan",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const detach = loaded.toolSourcePlan.find((entry) => entry.label === "detach");
      loaded.toolSourcePlan = loaded.toolSourcePlan.filter((entry) => entry !== detach);
      loaded.scriptOccurrences = loaded.scriptOccurrences.filter((entry) => entry.url !== detach.url);
      loaded.scriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(loaded);
    });
  negative("terminal observer detach cannot move before the final capture tool",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const detachIndex = loaded.toolSourcePlan.findIndex((entry) => entry.label === "detach");
      const detach = loaded.toolSourcePlan.splice(detachIndex, 1)[0];
      loaded.toolSourcePlan.splice(3, 0, detach);
      resealLoadedProduction(loaded);
    });
  negative("terminal observer detach must occur in the raw script stream",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const detach = loaded.toolSourcePlan.find((entry) => entry.label === "detach");
      loaded.scriptOccurrences = loaded.scriptOccurrences.filter((entry) => entry.url !== detach.url);
      loaded.scriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(loaded);
    });
  negative("raw tool occurrence order must exactly project the tool source plan",
    "loaded_production_tool_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const detach = loaded.scriptOccurrences.find((entry) => loaded.toolSourcePlan
        .some((plan) => plan.label === "detach" && plan.url === entry.url));
      const health = loaded.scriptOccurrences.find((entry) => loaded.toolSourcePlan
        .some((plan) => plan.label === "health" && plan.url === entry.url));
      placeAfter(loaded.scriptOccurrences, health, detach);
      loaded.scriptOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(loaded);
    });
  negative("raw resource stream cannot omit its non-CSS Document occurrence",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      loaded.resourceOccurrences.shift();
      loaded.resourceOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(loaded);
    });
  negative("inline source evidence cannot detach from the page occurrence",
    "loaded_production_inline_script_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      replaceRawSource(loaded.scriptOccurrences[0], "window.__detachedInline = true;");
      resealLoadedProduction(loaded);
    });
  negative("raw stylesheet occurrence order cannot be statically rewritten",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const values = b.runtime.first.loadedProduction.resourceOccurrences;
      const styleIndexes = values.map((entry, index) =>
        entry.resourceType === "Stylesheet" ? index : -1).filter((index) => index >= 0);
      const styles = styleIndexes.map((index) => values[index]).reverse();
      styleIndexes.forEach((index, position) => { values[index] = styles[position]; });
      values.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  negative("raw stylesheet occurrences reject foreign origin",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const entry = b.runtime.first.loadedProduction.resourceOccurrences.find((resource) =>
        resource.resourceType === "Stylesheet");
      entry.origin = "https://foreign.invalid";
      entry.url = "https://foreign.invalid/foreign.css";
      entry.rawResource.url = entry.url;
      resealLoadedProduction(b.runtime.first.loadedProduction);
    });
  [
    ["Fetch and terminal Font", (b) => [
      b.productionClosure.pageResourceContract.iconManifest.url,
      b.productionClosure.pageResourceContract.fonts.find((entry) => entry.required).url]],
    ["fixed and authority icon", (b) => [
      b.productionClosure.pageResourceContract.fixedImages[0].url,
      b.productionClosure.pageResourceContract.iconRoutes[0].resources[0].url]],
  ].forEach(([label, urls]) => negative("global Page order rejects cross-group swap: " + label,
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const pair = urls(b).map((url) => loaded.resourceOccurrences.findIndex((entry) =>
        entry.url === url));
      assert.ok(pair.every((index) => index >= 0));
      [loaded.resourceOccurrences[pair[0]], loaded.resourceOccurrences[pair[1]]]
        = [loaded.resourceOccurrences[pair[1]], loaded.resourceOccurrences[pair[0]]];
      loaded.resourceOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(loaded);
    }));
  [
    ["one production Script resource", (b) => b.productionClosure.pageResourceContract.scripts[0].url],
    ["the icon manifest Fetch resource", (b) =>
      b.productionClosure.pageResourceContract.iconManifest.url],
    ["one fixed Image resource", (b) => b.productionClosure.pageResourceContract.fixedImages[0].url],
    ["one relevant dynamic icon resource", (b) =>
      b.productionClosure.pageResourceContract.iconRoutes[0].resources[0].url],
    ["the required LXGW Font resource", () =>
      "https://cfn-fonts.local/lxgw-wenkai-screen.ttf"],
  ].forEach(([label, resourceUrl]) => negative("raw Page stream cannot omit " + label,
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const url = resourceUrl(b);
      loaded.resourceOccurrences = loaded.resourceOccurrences.filter((entry) => entry.url !== url);
      loaded.resourceOccurrences.forEach((entry, index) => { entry.occurrence = index + 1; });
      resealLoadedProduction(loaded);
    }));
  negative("raw Page stream rejects an unknown resource URL",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const foreign = clone(loaded.resourceOccurrences.find((entry) =>
        entry.resourceType === "Image"));
      foreign.url = "https://overlay.local/assets/unknown-resource.png";
      foreign.origin = "https://overlay.local";
      foreign.rawResource.url = foreign.url;
      foreign.occurrence = loaded.resourceOccurrences.length + 1;
      loaded.resourceOccurrences.push(foreign);
      resealLoadedProduction(loaded);
    });
  negative("raw Page resource type is exact",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const entry = loaded.resourceOccurrences.find((resource) => resource.resourceType === "Image");
      entry.resourceType = "Media";
      entry.rawResource.type = "Media";
      resealLoadedProduction(loaded);
    });
  negative("raw Page resource MIME type is exact",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const entry = loaded.resourceOccurrences.find((resource) => resource.resourceType === "Image");
      entry.mimeType = "application/octet-stream";
      entry.rawResource.mimeType = entry.mimeType;
      resealLoadedProduction(loaded);
    });
  negative("raw Page resource frame binding is exact",
    "loaded_production_resource_occurrence_invalid", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const entry = loaded.resourceOccurrences.find((resource) => resource.resourceType === "Image");
      entry.frameId = "foreign-frame";
      resealLoadedProduction(loaded);
    });
  negative("raw Page resource bytes remain current-tree exact",
    "loaded_production_resource_mismatch", (b) => {
      const loaded = b.runtime.first.loadedProduction;
      const entry = loaded.resourceOccurrences.find((resource) => resource.resourceType === "Image");
      replaceRawSource(entry, "changed Page image bytes");
      resealLoadedProduction(loaded);
    });
  negative("every rendered item icon name must exist in the canonical icon manifest",
    "page_resource_contract_invalid", (b) => {
      const unknown = "fixture_icon_absent_from_manifest";
      [response(b, "first", "inventory", "snapshot", 0).message.snapshots[0],
        response(b, "first", "inventory", "snapshot", 1).message.snapshots[0],
        response(b, "first", "equipment_tuning", "commit", 0)
          .message.inventorySnapshots[0],
        response(b, "restart", "inventory", "snapshot", 0).message.snapshots[0]]
        .forEach((snapshot) => { snapshot.slots[20].item.icon = unknown; });
      resealTranscript(b.transcripts.first);
      resealTranscript(b.transcripts.restart);
    });
  negative("Page resource contract field set is closed",
    "page_resource_contract_invalid", (b) => {
      b.productionClosure.pageResourceContract.forbidden = true;
      resealPageResourceContract(b.productionClosure.pageResourceContract);
      resealProductionClosure(b.productionClosure);
    });

  [
    ["trusted DOM target must be visible", (target) => { target.visible = false; }],
    ["trusted DOM target must be enabled", (target) => { target.enabled = false; }],
    ["trusted DOM target must be a BUTTON", (target) => { target.tagName = "DIV"; }],
    ["trusted DOM target selector is exact", (target) => { target.selector = "button"; }],
    ["trusted DOM rect must have area", (target) => {
      target.rect.right = target.rect.left; target.rect.width = 0;
    }],
    ["trusted DOM client point must hit the rect", (target) => { target.clientPoint.x = 999; }],
    ["trusted DOM hit test must resolve to the button", (target) => {
      target.hitTargetMatches = false;
    }],
    ["trusted DOM viewport must be finite and positive", (target) => {
      target.viewport.width = 0;
    }],
    ["trusted DOM point cannot use the exclusive viewport edge", (target) => {
      target.viewport.width = target.clientPoint.x;
    }],
  ].forEach(([name, mutate]) => negative(name, "trusted_input_contract_invalid", (b) => {
    const event = b.transcripts.first.events.find((entry) => entry.kind === "dom_input");
    mutate(event.target);
    resealTranscript(b.transcripts.first);
  }));

  negative("valid 1x1 PNG remains below the minimum capture dimensions",
    "control_capture_media_invalid", (b) => {
      mutateControlCapture(b, "safe_exit", Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
        "base64"));
    });
  negative("provider issuer is independently bound", "provider_receipt_invalid", (b) => {
    mutateProviderReceipt(b, "open_tuning", (receipt) => { receipt.issuer = "self_reported"; });
  });
  negative("provider tool-result source is independently bound",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "open_tuning", (receipt) => {
        receipt.toolResultSource = "operator_note";
      });
    });
  negative("provider receipt binds exact persisted request bytes",
    "provider_receipt_invalid", (b) => {
      mutateProviderReceipt(b, "open_tuning", (receipt) => {
        receipt.requestSha256 = "0".repeat(64);
      });
    });
  negative("provider capture event binds decoded capture dimensions",
    "provider_capture_event_invalid", (b) => {
      mutateProviderCaptureEvent(b, "open_tuning", (event) => { event.captureWidth = 321; });
    });
  negative("provider captures cannot reuse bytes across operations",
    "provider_capture_reused", (b) => {
      const first = b.control.acks[0];
      const second = b.control.acks[1];
      const firstBytes = fs.readFileSync(path.join(b.runDir,
        first.capture.relativePath.replace(/\//g, path.sep)));
      const secondPath = path.join(b.runDir,
        second.capture.relativePath.replace(/\//g, path.sep));
      const secondEvent = providerCaptureEventEntry(b, second.step).value;
      fs.writeFileSync(secondPath, firstBytes);
      fs.utimesSync(secondPath, new Date(secondEvent.fileModifiedAt),
        new Date(secondEvent.fileModifiedAt));
      second.capture.sha256 = first.capture.sha256;
      second.capture.bytes = first.capture.bytes;
      second.captureSha256 = first.captureSha256;
      mutateProviderCaptureEvent(b, second.step, (event) => {
        event.captureSha256 = first.capture.sha256;
        event.captureBytes = first.capture.bytes;
      });
    });

  negativeArtifact("persisted control request bytes are bundle-closed",
    "control_artifact_bundle_mismatch", (_bundle, manifest) => {
      const entry = Array.from(manifest.values()).find((value) => value.role === "control_request");
      const value = JSON.parse(fs.readFileSync(entry.absolutePath, "utf8"));
      value.instructions += " forged";
      fs.writeFileSync(entry.absolutePath, JSON.stringify(value) + "\n", "utf8");
    });
  negativeArtifact("persisted control ack bytes are bundle-closed",
    "control_artifact_bundle_mismatch", (_bundle, manifest) => {
      const entry = Array.from(manifest.values()).find((value) => value.role === "control_ack");
      const value = JSON.parse(fs.readFileSync(entry.absolutePath, "utf8"));
      value.completedAt = "2026-08-03T00:00:00.000Z";
      fs.writeFileSync(entry.absolutePath, JSON.stringify(value) + "\n", "utf8");
    });
  negativeArtifact("provider capture manifest role admits no extras",
    "provider_capture_artifact_set_invalid", (bundle, manifest) => {
      manifest.set("control/captures/extra.png", { absolutePath: path.join(bundle.runDir,
        "control", "captures", "extra.png"), role: "provider_capture",
      sha256: "0".repeat(64), bytes: 1 });
    });
  negativeArtifact("provider capture event manifest role admits no extras",
    "provider_capture_event_artifact_set_invalid", (bundle, manifest) => {
      manifest.set("control/capture-events/extra.json", { absolutePath: path.join(bundle.runDir,
        "control", "capture-events", "extra.json"), role: "provider_capture_event",
      sha256: "0".repeat(64), bytes: 1 });
    });
  negativeArtifact("provider capture event manifest role is exact",
    "provider_capture_event_artifact_role_invalid", (_bundle, manifest) => {
      const entry = Array.from(manifest.values()).find((value) =>
        value.role === "provider_capture_event");
      entry.role = "forged_capture_event";
    });

  negative("PanelHost close timestamp must follow the actual DOM hit",
    "host_timeline_regression", (b) => {
      setHostRecordTime(hostRecord(b, "first", "event=panel_exact_close_completed", 0),
        "2026-08-03T00:10:00.500Z");
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("SAFEEXIT provider input must precede sv1",
    "global_partial_order_invalid", (b) => {
      setHostRecordTime(hostRecord(b, "first", "sv:1", 0),
        "2026-08-03T00:10:11.000Z");
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("sv1 must strictly precede sv2 on the comparable clock",
    "host_timeline_regression", (b) => {
      setHostRecordTime(hostRecord(b, "first", "sv:2", 0),
        "2026-08-03T00:10:15.900Z");
      resealLog(b.runtime.first.finalLogSnapshot);
    });
  negative("restart PanelHost close must follow restart DOM hit",
    "host_timeline_regression", (b) => {
      setHostRecordTime(hostRecord(b, "restart", "event=panel_exact_close_completed", 0),
        "2026-08-03T00:10:50.500Z");
      resealLog(b.runtime.restart.finalLogSnapshot);
    });
  negative("Host timeline records cannot omit their production time prefix",
    "host_timestamp_missing", (b) => {
      const record = b.runtime.first.finalLogSnapshot.records[0];
      record.line = record.line.slice(13);
      resealLog(b.runtime.first.finalLogSnapshot);
    });

  assert(browserGateReceipt);
  return { passed: positives.length + negatives.length, positives: positives.length,
    negatives: negatives.length, names: positives.concat(negatives),
    childReceipts:{ browser:browserGateReceipt } };
}

module.exports = { runSelfTests };

if (require.main === module) {
  console.error("self-test.js is NOT_ADMITTED directly; use equipment/bootstrap.js --check");
  process.exitCode = 2;
}
