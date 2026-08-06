"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const CloneGuard = require("../../lib/clone-save-guard");
const Evidence = require("../../lib/evidence-artifact");
const LauncherObservation = require("../../lib/launcher-observation");
const IdentityFixture = require("../../../equipment-tuning/fixtures/item-identity-triple.json");
const {
  API_VERSION,
  AUTHORIZATION_SCHEMA,
  BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA,
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  NATIVE_INPUT_EVENT_SCHEMA,
  PROVIDER_CAPTURE_EVENT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  TRANSCRIPT_SCHEMA,
  deriveDiagnosticAuthorityBinding,
  deriveRequestAuthorityBinding,
  nextRecord,
  redactAuthority,
  tokenRef,
} = require("../common");
const { REQUIRED_CONTROL_STEPS, domInputEvidence,
  expectedProviderCaptureEventId, expectedProviderOperationId } = require("../control-channel");
const ProductionClosure = require("../production-closure");

const REPOSITORY_ROOT = path.resolve(__dirname, "../../../..");

const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-equipment-e2e-fixture-"));
const RUN_DIR = path.join(ROOT, "tmp", "workbench-live-e2e", "equipment", "fixture");
const RUN_ID = "fixture-equipment-v2";
const CAPTURE_DIR = path.join(RUN_DIR, "control", "captures");
const REQUEST_DIR = path.join(RUN_DIR, "control", "requests");
const ACK_DIR = path.join(RUN_DIR, "control", "acks");
const PROVIDER_RECEIPT_DIR = path.join(RUN_DIR, "control", "provider-receipts");
const CAPTURE_EVENT_DIR = path.join(RUN_DIR, "control", "capture-events");
const NATIVE_INPUT_EVENT_DIR = path.join(RUN_DIR, "control", "native-input-events");
fs.mkdirSync(CAPTURE_DIR, { recursive: true });
fs.mkdirSync(REQUEST_DIR, { recursive: true });
fs.mkdirSync(ACK_DIR, { recursive: true });
fs.mkdirSync(PROVIDER_RECEIPT_DIR, { recursive: true });
fs.mkdirSync(CAPTURE_EVENT_DIR, { recursive: true });
fs.mkdirSync(NATIVE_INPUT_EVENT_DIR, { recursive: true });
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function pngChunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const output = Buffer.alloc(12 + data.length);
  output.writeUInt32BE(data.length, 0);
  name.copy(output, 4);
  data.copy(output, 8);
  output.writeUInt32BE(crc32(Buffer.concat([name, data])), 8 + data.length);
  return output;
}
function fixturePng(index) {
  const width = 320;
  const height = 180;
  const rows = Buffer.alloc(height * (width * 3 + 1));
  for (let y = 0; y < height; y += 1) {
    const offset = y * (width * 3 + 1);
    rows[offset] = 0;
    for (let x = 0; x < width; x += 1) {
      rows[offset + 1 + x * 3] = (index * 37 + x) & 0xff;
      rows[offset + 2 + x * 3] = (index * 53 + y) & 0xff;
      rows[offset + 3 + x * 3] = (index * 71 + x + y) & 0xff;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", ihdr), pngChunk("IDAT", zlib.deflateSync(rows)),
    pngChunk("IEND", Buffer.alloc(0))]);
}
const CAPTURES = REQUIRED_CONTROL_STEPS.map((step, index) => {
  const name = "fixture-" + step + ".png";
  const bytes = fixturePng(index + 1);
  const file = path.join(CAPTURE_DIR, name);
  fs.writeFileSync(file, bytes, { flag: "wx" });
  return { relativePath: "control/captures/" + name,
    sha256: Evidence.sha256Bytes(bytes), bytes: bytes.length, mediaType: "image/png",
    fixtureBytes: bytes };
});
function resetCaptureFiles() {
  [CAPTURE_DIR, REQUEST_DIR, ACK_DIR, PROVIDER_RECEIPT_DIR, CAPTURE_EVENT_DIR,
    NATIVE_INPUT_EVENT_DIR,
    path.join(RUN_DIR, "evidence")].forEach((directory) => {
    fs.rmSync(directory, { recursive: true, force: true });
    fs.mkdirSync(directory, { recursive: true });
  });
  fs.readdirSync(RUN_DIR, { withFileTypes: true }).forEach((entry) => {
    if (entry.isFile() && (/-passive-transcript\.(?:json|jsonl)$/.test(entry.name)
        || ["journey-bundle.json", "artifact-manifest.json", "verified-receipt.json"]
          .includes(entry.name))) {
      fs.rmSync(path.join(RUN_DIR, entry.name), { force: true });
    }
  });
  CAPTURES.forEach((capture) => {
    fs.writeFileSync(path.join(RUN_DIR, capture.relativePath.replace(/\//g, path.sep)),
      capture.fixtureBytes);
  });
}
process.once("exit", () => {
  try {
    if (path.dirname(ROOT) === path.resolve(os.tmpdir())
        && path.basename(ROOT).startsWith("cf7-equipment-e2e-fixture-")) {
      fs.rmSync(ROOT, { recursive: true, force: true });
    }
  } catch (_error) {}
});

const SEED_SLOT = "cf7_agent_equipment_seed_fixture";
const TARGET_SLOT = "cf7_agent_equipment_target_fixture";
const CANDIDATE_ROOT = path.join(ROOT, "tmp", "runtime-candidates", "v2", "fixture-equipment");
let cachedFixtureProducerInputs = null;
let fixtureLoadedSources = new Map();
const FIXTURE_INLINE_SOURCE = "window.__cf7EquipmentFixtureInline = true;";
const RAW_SOURCE_LEASE_BEFORE = "fixture-source-lease-before-authority";
const RAW_SOURCE_LEASE_AFTER = "fixture-source-lease-after-authority";
const RAW_SOURCE_LEASE_RESTART = "fixture-source-lease-restart-authority";
const SOURCE_BEFORE = Object.freeze({ sourceKind: "inventory", containerId: "背包", slot: 7,
  expectedLease: tokenRef(RAW_SOURCE_LEASE_BEFORE) });
const SOURCE_AFTER = Object.freeze({ sourceKind: "inventory", containerId: "背包", slot: 7,
  expectedLease: tokenRef(RAW_SOURCE_LEASE_AFTER) });
const SOURCE_RESTART = Object.freeze({ sourceKind: "inventory", containerId: "背包", slot: 7,
  expectedLease: tokenRef(RAW_SOURCE_LEASE_RESTART) });
function rawSourceKey(source, rawLease) {
  return "inventory:" + source.containerId + ":" + source.slot + ":" + rawLease;
}
// The frozen fixture candidateKey is a test selector, not a production wire identity.
// Production AS2 assigns mod.<index> keys per snapshot, so the verifier must bind the
// all-distinct identity triple while carrying the wire key returned by that snapshot.
const CANDIDATE_A = Object.freeze(Object.assign({}, IdentityFixture.allDistinct[1],
  { candidateKey: "mod.1" }));
const CANDIDATE_B = Object.freeze(Object.assign({}, IdentityFixture.allDistinct[0],
  { candidateKey: "mod.0" }));
const RAW_TOKEN_A = "fixture-preview-a-authority";
const RAW_TOKEN_B = "fixture-preview-b-authority";
const RAW_TRANSACTION = "fixture-transaction-authority";
const TOKEN_A = tokenRef(RAW_TOKEN_A);
const TOKEN_B = tokenRef(RAW_TOKEN_B);
const TRANSACTION = tokenRef(RAW_TRANSACTION);

function clone(value) { return JSON.parse(JSON.stringify(value)); }
function previewIntentKey(candidateKey) { return "install_mod|" + candidateKey + "|"; }

function equipment(mods, lastUpdate) {
  return {
    name: "fixture_weapon_internal",
    displayName: "验证用武器",
    icon: "fixture_weapon_icon",
    type: "武器",
    use: "长枪",
    level: 13,
    tier: "三阶",
    mods: mods.slice(),
    lastUpdate,
    maxLevel: 25,
    hardMaxLevel: 30,
    modSlotCapacity: 3,
  };
}

function candidate(identity, owned, installed) {
  return Object.assign({}, identity, {
    owned, installed, available: !installed, availabilityCode: installed ? 1 : 0,
    reason: installed ? "已安装" : "可安装", replaceableFrom: [], grade: "A",
    scope: "weapon", role: "utility",
  });
}

function material(identity, count) {
  return { itemName: identity.itemName, displayName: identity.displayName,
    icon: identity.icon, count };
}

function snapshot(after, source, restarted) {
  return {
    gender: "男",
    source: clone(source || (after ? SOURCE_AFTER : SOURCE_BEFORE)),
    equipment: equipment(after ? [CANDIDATE_B.itemName] : [], after ? 200 : 100),
    enhance: { currentLevel: 13, maxLevel: 25, availableMaxLevel: 25, hardMaxLevel: 30 },
    tierCandidates: [],
    modCandidates: [candidate(CANDIDATE_A, 3, false), candidate(CANDIDATE_B, after ? 3 : 4, after)],
    materials: [material(CANDIDATE_A, 3), material(CANDIDATE_B, after ? 3 : 4)],
    materialRevision: restarted ? 1 : after ? 2 : 1,
    inventoryRevision: restarted ? 1 : after ? 2 : 1,
  };
}

function projection(identity, committed) {
  return { source: { source: clone(committed ? SOURCE_AFTER : SOURCE_BEFORE),
    equipment: equipment(identity ? [identity.itemName] : [], committed ? 200 : 100) } };
}

function plan(identity, before) {
  return [{ itemName: identity.itemName, displayName: identity.displayName,
    icon: identity.icon, before, delta: -1, after: before - 1 }];
}

function modSignature(mods) {
  return mods.map((name) => String(name).length + ":" + name + ";").join("");
}

function inventoryMod(identity) {
  return { name: identity.itemName, displayName: identity.displayName, icon: identity.icon,
    grade: "A", gradeLabel: "", gradeColor: "", role: "utility", roleLabel: "",
    symbol: "", scope: "weapon" };
}

function inventoryItem(after) {
  const value = equipment(after ? [CANDIDATE_B.itemName] : [], after ? 200 : 100);
  const modSlots = after ? [inventoryMod(CANDIDATE_B)] : [];
  return { name: value.name, displayName: value.displayName, icon: value.icon,
    majorType: value.type, use: value.use, actionType: "", weaponType: value.use,
    setId: "", setName: "", setOrder: 0, itemKind: "equipment", quantity: 1,
    enhancementLevel: value.level, maxEnhancementLevel: value.hardMaxLevel,
    isMaxEnhancement: value.level >= value.hardMaxLevel,
    tierSlotAvailable: true, tierSlotUsed: value.tier !== "",
    modSlotCapacity: value.modSlotCapacity, modSlotUsed: modSlots.length,
    modSlots, modMeta: null, rarity: "rare" };
}

function inventoryConfirm(item, after) {
  const value = equipment(after ? [CANDIDATE_B.itemName] : [], after ? 200 : 100);
  return { itemKind: item.itemKind, name: item.name, displayName: item.displayName,
    quantity: item.quantity, enhancementLevel: item.enhancementLevel, rarity: item.rarity,
    tier: value.tier, modSignature: modSignature(value.mods), lastUpdate: value.lastUpdate };
}

function occupiedInventorySlot(after, source) {
  const item = inventoryItem(after);
  const authority = source || (after ? SOURCE_AFTER : SOURCE_BEFORE);
  return { physicalSlot: SOURCE_BEFORE.slot, occupied: true,
    slotLease: authority.expectedLease,
    item, confirmProjection: inventoryConfirm(item, after) };
}

function stableNonTargetInventorySlot(leasePhase) {
  const item = { name: "fixture_stable_sidearm", displayName: "稳定性对照副武器",
    icon: "fixture_stable_sidearm_icon", majorType: "武器", use: "手枪", actionType: "",
    weaponType: "手枪", setId: "", setName: "", setOrder: 0, itemKind: "equipment",
    quantity: 1, enhancementLevel: 5, maxEnhancementLevel: 20,
    isMaxEnhancement: false, tierSlotAvailable: false, tierSlotUsed: false,
    modSlotCapacity: 0, modSlotUsed: 0, modSlots: [], modMeta: null, rarity: "common" };
  return { physicalSlot: 20, occupied: true,
    slotLease: tokenRef("fixture-stable-lease-" + leasePhase), item,
    confirmProjection: { itemKind: item.itemKind, name: item.name,
      displayName: item.displayName, quantity: item.quantity,
      enhancementLevel: item.enhancementLevel, rarity: item.rarity, tier: "",
      modSignature: "", lastUpdate: 77 } };
}

function fullBackpackSnapshot(after, snapshotSeq, source, containerVersion, leasePhase) {
  const phase = leasePhase || (after ? "after" : "before");
  const slots = [];
  for (let physicalSlot = 0; physicalSlot < 50; physicalSlot += 1) {
    slots.push(physicalSlot === SOURCE_BEFORE.slot ? occupiedInventorySlot(after, source)
      : physicalSlot === 20 ? stableNonTargetInventorySlot(phase)
      : { physicalSlot, occupied: false,
        slotLease: tokenRef("fixture-empty-lease-" + physicalSlot + "-" + phase) });
  }
  return { containerId: "背包", capacity: 50, accessibleCapacity: 50,
    viewCapacity: 50, filterKey: "all", pageSizeHint: 50, locked: false,
    snapshotSeq: snapshotSeq == null ? (after ? 2 : 1) : snapshotSeq,
    containerEpoch: 1, containerVersion: containerVersion == null ? (after ? 2 : 1)
      : containerVersion, offset: 0, limit: 50, slots,
    filterFacets: [{ id: "weapon", label: "武器", order: 0, count: 2, children: [] }],
    filterItemCount: 2, setFacets: [], setFilterItemCount: 0 };
}

function inventoryResponse(panelInstanceId, callId, after, snapshotSeq, source, containerVersion) {
  return {
    type: "panel_resp", panel: "workbench", domain: "inventory", cmd: "snapshot",
    callId, panelInstanceId, success: true, v: 1,
    sessionNonce: panelInstanceId.includes("restart")
      ? "fixture_inventory_session_restart" : "fixture_inventory_session_first",
    snapshots: [fullBackpackSnapshot(after, snapshotSeq || (after ? 2 : 1), source,
      containerVersion == null ? (after ? 2 : 1) : containerVersion,
      panelInstanceId.includes("restart") ? "restart" : after ? "after" : "before")],
  };
}

function response(request, body) {
  const value = Object.assign({ type: "panel_resp", panel: "workbench", domain: request.domain,
    cmd: request.cmd, callId: request.callId, panelInstanceId: request.panelInstanceId,
    success: true }, body || {});
  if (request.domain === "equipment_tuning") {
    value.v = 1;
    value.viewSessionId = request.payload.viewSessionId;
    if (!Object.prototype.hasOwnProperty.call(value, "writeEpoch")) value.writeEpoch = 0;
  }
  return value;
}

function buildTranscript(phase) {
  const first = phase === "first";
  const panelInstanceId = first ? "panel_equipment_fixture_first" : "panel_equipment_fixture_restart";
  const viewSessionId = first ? "tuning_fixture_first" : "tuning_fixture_restart";
  const readSource = first ? SOURCE_BEFORE : SOURCE_RESTART;
  const readRawLease = first ? RAW_SOURCE_LEASE_BEFORE : RAW_SOURCE_LEASE_RESTART;
  const raw = [];
  let counter = 0;
  let diagnosticSequence = 0;
  function emit(value) { raw.push(value); }
  function createRequest(domain, cmd, payload) {
    const rawMessage = { type: "panel", panel: "workbench", domain, cmd,
      callId: (first ? "first" : "restart") + "." + domain + "." + (++counter),
      panelInstanceId, payload: Object.assign({ v: 1 }, payload || {}) };
    if (domain === "equipment_tuning") rawMessage.payload.viewSessionId = viewSessionId;
    const event = { kind: "bridge_send", message: redactAuthority(rawMessage) };
    const binding = deriveRequestAuthorityBinding(rawMessage);
    if (binding) event.authorityBinding = binding;
    return { rawMessage, event, message: event.message };
  }
  function dispatch(created) { emit(created.event); return created.message; }
  function inbound(requestValue, body) { emit({ kind: "webview_message",
    message: response(requestValue, body) }); }
  let trustedIndex = 0;
  const trustedTimes = first
    ? ["2026-08-03T00:09:11.000Z", "2026-08-03T00:09:21.000Z",
      "2026-08-03T00:09:31.000Z", "2026-08-03T00:09:41.000Z",
      "2026-08-03T00:09:51.000Z", "2026-08-03T00:10:01.000Z"]
    : ["2026-08-03T00:10:41.000Z", "2026-08-03T00:10:51.000Z"];
  function trusted(target) {
    const pageTime = Date.parse(trustedTimes[trustedIndex++]);
    emit({ kind: "dom_input", eventType: "click", isTrusted: true, button: 0,
      pageTime,
      target: Object.assign({ text: "fixture", attributes: {}, mutationCapable: false,
        tagName: "BUTTON", visible: true, enabled: true, hitTargetMatches: true,
        viewport: { width: 1600, height: 900 },
        rect: { left: 10, top: 10, right: 110, bottom: 50, width: 100, height: 40 },
        clientPoint: { x: 50, y: 30 } }, target) });
  }
  function diagnostic(name, callId, candidateKey, options) {
    const settings = options || {};
    const source = settings.source === "after" ? SOURCE_AFTER : SOURCE_BEFORE;
    const rawLease = settings.source === "after"
      ? RAW_SOURCE_LEASE_AFTER : RAW_SOURCE_LEASE_BEFORE;
    const rawMessage = { type: "debug", scope: "equipment_tuning",
      sequence: ++diagnosticSequence, event: name, cmd: "", operation: "install_mod",
      capability: settings.capability || "", phase: "", webCallId: callId || "",
      panelInstanceId, viewSessionId,
      sourceKey: rawSourceKey(source, rawLease), candidateKey: candidateKey || "",
      intentKey: settings.intentKey == null ? "" : settings.intentKey,
      reconcileAfterCallId: "", pendingCount: Number(settings.pendingCount || 0),
      tokenPresent: settings.tokenPresent === true, commitReady: settings.commitReady === true,
      confirmationMode: "safe", autoCommitPending: false,
      writeState: settings.writeState || "idle",
      success: settings.success == null ? null : settings.success === true,
      transactionIdPresent: settings.transactionIdPresent == null
        ? null : settings.transactionIdPresent === true,
      requiresReconcile: settings.requiresReconcile == null
        ? null : settings.requiresReconcile === true,
      currentLeasePresent: settings.currentLeasePresent == null
        ? null : settings.currentLeasePresent === true,
      needsReconcile: false, reconciled: null,
      noOp: settings.noOp == null ? null : settings.noOp === true,
      mismatchFields: [] };
    const event = { kind: "bridge_send", message: redactAuthority(rawMessage) };
    const binding = deriveDiagnosticAuthorityBinding(rawMessage);
    if (binding) event.authorityBinding = binding;
    emit(event);
  }
  emit({ kind: "cdp_endpoint_bound", cdpPort: first ? 19222 : 19223,
    runtimePid: first ? 4100 : 4200 });
  emit({ kind: "observer_ready", url: "https://overlay.local/overlay.html" });
  trusted({ selector: "button[data-physical-slot=\"7\"]",
    attributes: { "data-physical-slot": "7" } });
  const read = dispatch(createRequest("equipment_tuning", "snapshot", {
    source: { sourceKind: "inventory", containerId: "背包", slot: 7,
      expectedLease: readRawLease } }));
  inbound(read, { snapshot: snapshot(!first, readSource, !first) });
  const inv = dispatch(createRequest("inventory", "snapshot", { requests: [
    { containerId: "背包", offset: 0, limit: 50, filterKey: "all", scope: "all" },
  ] }));
  inbound(inv, inventoryResponse(panelInstanceId, inv.callId, !first, 1, readSource, 1));
  if (first) {
    trusted({ selector: "button[data-candidate-key=\"" + CANDIDATE_A.candidateKey + "\"]",
      attributes: { "data-candidate-key": CANDIDATE_A.candidateKey }, mutationCapable: true });
    diagnostic("candidate_hit", "", CANDIDATE_A.candidateKey, {
      capability: "candidate", intentKey: "" });
    const previewACreated = createRequest("equipment_tuning", "preview", { operation: "install_mod",
      source: { sourceKind: "inventory", containerId: "背包", slot: 7,
        expectedLease: RAW_SOURCE_LEASE_BEFORE }, candidateKey: CANDIDATE_A.candidateKey });
    diagnostic("preview_issued", previewACreated.message.callId, CANDIDATE_A.candidateKey, {
      intentKey: previewIntentKey(CANDIDATE_A.candidateKey), pendingCount: 1,
      writeState: "read_pending" });
    const previewA = dispatch(previewACreated);
    inbound(previewA, { operation: "install_mod", tuningToken: TOKEN_A, noOp: false,
      canCommit: true, before: projection(null), after: projection(CANDIDATE_A),
      materials: plan(CANDIDATE_A, 3), removedMods: [], writeEpoch: 0 });
    diagnostic("preview_adopted", previewA.callId, CANDIDATE_A.candidateKey, {
      intentKey: previewIntentKey(CANDIDATE_A.candidateKey), tokenPresent: true,
      commitReady: true });
    trusted({ selector: "button[data-candidate-key=\"" + CANDIDATE_B.candidateKey + "\"]",
      attributes: { "data-candidate-key": CANDIDATE_B.candidateKey }, mutationCapable: true });
    diagnostic("candidate_hit", "", CANDIDATE_B.candidateKey, {
      capability: "candidate", intentKey: previewIntentKey(CANDIDATE_A.candidateKey),
      tokenPresent: true, commitReady: true });
    const previewBCreated = createRequest("equipment_tuning", "preview", { operation: "install_mod",
      source: { sourceKind: "inventory", containerId: "背包", slot: 7,
        expectedLease: RAW_SOURCE_LEASE_BEFORE }, candidateKey: CANDIDATE_B.candidateKey });
    diagnostic("preview_issued", previewBCreated.message.callId, CANDIDATE_B.candidateKey, {
      intentKey: previewIntentKey(CANDIDATE_B.candidateKey), pendingCount: 1,
      writeState: "read_pending" });
    const previewB = dispatch(previewBCreated);
    inbound(previewB, { operation: "install_mod", tuningToken: TOKEN_B, noOp: false,
      canCommit: true, before: projection(null), after: projection(CANDIDATE_B),
      materials: plan(CANDIDATE_B, 4), removedMods: [], writeEpoch: 0 });
    diagnostic("preview_adopted", previewB.callId, CANDIDATE_B.candidateKey, {
      intentKey: previewIntentKey(CANDIDATE_B.candidateKey), tokenPresent: true,
      commitReady: true });
    trusted({ selector: ".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]",
      attributes: { "data-tuning-focus-key": "commit" }, mutationCapable: true });
    const commitCreated = createRequest("equipment_tuning", "commit", {
      expectedTuningToken: RAW_TOKEN_B });
    diagnostic("commit_issued", commitCreated.message.callId, CANDIDATE_B.candidateKey, {
      intentKey: previewIntentKey(CANDIDATE_B.candidateKey), pendingCount: 1,
      tokenPresent: true, writeState: "write_pending" });
    const commit = dispatch(commitCreated);
    inbound(commit, { operation: "install_mod", tuningToken: TOKEN_B,
      transactionId: TRANSACTION, noOp: false, canCommit: false,
      before: projection(null), after: projection(CANDIDATE_B, true),
      materials: plan(CANDIDATE_B, 4), removedMods: [], snapshot: snapshot(true),
      inventorySnapshots: [fullBackpackSnapshot(true, 2, SOURCE_AFTER, 2, "after")],
      writeEpoch: 1 });
    diagnostic("commit_adopted", commit.callId, CANDIDATE_B.candidateKey, {
      intentKey: previewIntentKey(CANDIDATE_B.candidateKey), tokenPresent: true,
      writeState: "write_pending", success: true, transactionIdPresent: true,
      requiresReconcile: false, noOp: false });
    const refresh = dispatch(createRequest("inventory", "snapshot", { requests: [
      { containerId: "背包", offset: 0, limit: 50, filterKey: "all", scope: "all" },
    ] }));
    inbound(refresh, inventoryResponse(panelInstanceId, refresh.callId, true, 3,
      SOURCE_AFTER, 2));
    diagnostic("inventory_refresh_settled", commit.callId, CANDIDATE_B.candidateKey, {
      source: "after", intentKey: previewIntentKey(CANDIDATE_B.candidateKey),
      success: true, currentLeasePresent: true });
    trusted({ selector: "button[data-physical-slot=\"7\"]",
      attributes: { "data-physical-slot": "7" } });
    const fresh = dispatch(createRequest("equipment_tuning", "snapshot", {
      source: { sourceKind: "inventory", containerId: "背包", slot: 7,
        expectedLease: RAW_SOURCE_LEASE_AFTER } }));
    inbound(fresh, { snapshot: snapshot(true), writeEpoch: 1 });
  }
  trusted({ selector: "button[data-header-action=\"close\"]",
    attributes: { "data-header-action": "close" } });
  const detach = dispatch(createRequest("equipment_tuning", "detach", {}));
  inbound(detach, { writeEpoch: first ? 1 : 0 });
  emit({ kind: "observer_detached" });
  let previous = "0".repeat(64);
  let observedClock = Date.parse(first
    ? "2026-08-03T00:09:05.000Z" : "2026-08-03T00:10:35.000Z");
  const events = raw.map((event, index) => {
    if (event.kind === "dom_input" && Number.isFinite(event.pageTime)) {
      observedClock = Math.max(observedClock + 1, event.pageTime);
    } else {
      observedClock += 1;
    }
    const record = nextRecord(previous, index + 1,
      Object.assign({ observedAt: new Date(observedClock).toISOString() }, event));
    previous = record.eventHash;
    return record;
  });
  return { schema: TRANSCRIPT_SCHEMA, observerId: first ? "equipment-first" : "equipment-restart",
    pageUrl: "https://overlay.local/overlay.html", eventCount: events.length,
    chainHead: previous, events };
}

function session(pid, port, ticks, lifecycle, marker) {
  const value = {
    schema: LauncherObservation.SESSION_SCHEMA,
    apiVersion: "FROZEN-v1",
    openedAt: "2026-08-03T00:00:00.000Z",
    pid, httpPort: port, socketPort: port + 100, portsFile: "tmp/ports-" + marker + ".json",
    portsFileSha256: marker.repeat(64).slice(0, 64), portsFileBytes: 64,
    credentialFile: path.join(ROOT, "tmp", "credential-" + marker + ".json"),
    credentialFileSha256: (marker === "a" ? "b" : "c").repeat(64), credentialFileBytes: 128,
    credentialTokenSha256: (marker === "a" ? "d" : "e").repeat(64),
    credentialHeader: "X-CF7-Automation-Token", processStartUtcTicks: ticks,
    lifecycleId: lifecycle,
    capabilities: ["legacy.console", "legacy.logs", "legacy.status", "legacy.task"],
  };
  value.sessionEvidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function identity(pid, httpPort, producer) {
  return { runtimeMode: "isolated_candidate", installRoot: CANDIDATE_ROOT,
    processPath: path.join(CANDIDATE_ROOT, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
    coreSha256: producer.coreSha256, buildIdentity: producer.buildIdentityHash,
    payloadClosure: producer.payloadClosureHash,
    pid, httpPort };
}

function fixtureProducerInputs() {
  if (!cachedFixtureProducerInputs) {
    cachedFixtureProducerInputs = clone(ProductionClosure.currentProducerInputs(REPOSITORY_ROOT));
    cachedFixtureProducerInputs.root = ROOT;
    delete cachedFixtureProducerInputs.inputsSha256;
    cachedFixtureProducerInputs.inputsSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(cachedFixtureProducerInputs));
  }
  return clone(cachedFixtureProducerInputs);
}

function prepareFixtureCandidate(closure) {
  const candidate = path.resolve(CANDIDATE_ROOT);
  if (!candidate.toLowerCase().startsWith((path.resolve(ROOT) + path.sep).toLowerCase())) {
    throw new Error("fixture candidate escaped its temporary root");
  }
  fs.rmSync(candidate, { recursive: true, force: true });
  const runtime = path.join(candidate, "runtime");
  fs.mkdirSync(runtime, { recursive: true });
  const payloadBytes = new Map([
    ["CRAZYFLASHER7MercenaryEmpire.exe", Buffer.from("fixture-bootstrap-v2", "utf8")],
    ["runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", Buffer.from("fixture-core-dll-v2", "utf8")],
    ["runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", Buffer.from("fixture-core-exe-v2", "utf8")],
  ]);
  payloadBytes.forEach((bytes, relativePath) => {
    fs.writeFileSync(path.join(candidate, relativePath.replace(/\//g, path.sep)), bytes);
  });
  const files = Array.from(payloadBytes.entries()).map(([relativePath, bytes]) => ({
    path: relativePath, size: bytes.length,
    sha256: Evidence.sha256Bytes(bytes).toUpperCase(),
  })).sort((left, right) => left.path < right.path ? -1 : (left.path > right.path ? 1 : 0));
  const inputs = closure.producerInputs;
  const buildIdentityHash = inputs.buildIdentityHash;
  const payloadClosureHash = ProductionClosure.canonicalPayloadClosureHash(files);
  const metadata = { schema: "cf7-runtime-candidate-metadata.v2",
    builderLabel: "fixture-offline-producer",
    artifactSourceHash: inputs.domains.artifactSource.hash,
    producerRecipeHash: inputs.domains.producerRecipe.hash,
    toolchainLockHash: inputs.domains.toolchainLock.hash,
    buildIdentityHash, payloadClosureHash, createdAtUtc: "2026-08-03T00:00:00.000Z" };
  fs.writeFileSync(path.join(candidate, "runtime-build-metadata.v2.json"),
    JSON.stringify(metadata) + "\n", "utf8");
  const manifest = [
    "cf7-runtime-manifest-v2",
    "publishMode\tframework-dependent",
    "artifactSourceHash\t" + metadata.artifactSourceHash,
    "producerRecipeHash\t" + metadata.producerRecipeHash,
    "toolchainLockHash\t" + metadata.toolchainLockHash,
    "toolchainBaseline\tfixture-offline",
    "buildIdentityHash\t" + metadata.buildIdentityHash,
    "payloadClosureHash\t" + metadata.payloadClosureHash,
  ].concat(files.map((entry) => "file\t" + entry.path + "\t" + entry.size + "\t"
    + entry.sha256), [""]).join("\n");
  fs.writeFileSync(path.join(runtime, "cf7-runtime-manifest.tsv"), manifest, "utf8");
  return { buildIdentityHash, payloadClosureHash,
    coreSha256: files.find((entry) =>
      entry.path === "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll").sha256 };
}

function processContract(identityValue, sessionValue, marker) {
  const value = { schema: "workbench-live-e2e.launcher-process-contract.v1", apiVersion: "FROZEN-v1",
    observedAt: "2026-08-03T00:00:00.000Z", pid: identityValue.pid,
    processPath: path.resolve(identityValue.processPath),
    processStartUtcTicks: sessionValue.processStartUtcTicks,
    commandLineSha256: marker.repeat(64), argvSha256: (marker === "f" ? "8" : "9").repeat(64),
    projectRoot: ROOT, projectRootArgumentExact: true, legacyHttpAutomationArg: true,
    agentRuntimeAdmission: false,
    trustedSource: "actual_process_command_line+pid_bound_credential" };
  value.artifactSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function cdpBinding(port, pid, listenerPid, marker) {
  const allocatedAt = "2026-08-03T00:00:00.000Z";
  const observedAt = "2026-08-03T00:00:01.000Z";
  const pageIdentity = { url: "https://overlay.local/overlay.html", origin: "https://overlay.local",
    timeOrigin: port, readyState: "complete", userAgent: "fixture-webview2" };
  return { port, allocatedAt, runtimePid: pid, exclusiveBeforeLaunch: true,
    configurationSource: "CF7_WEBVIEW2_ARGS", developerMode: true,
    expectedPageUrl: "https://overlay.local/overlay.html", pageIdentity,
    pageIdentitySha256: Evidence.sha256Text(Evidence.canonicalJson(pageIdentity)),
    pageContentSha256: marker.repeat(64), pageContentBytes: 4096,
    pageContentCapturedAt: "2026-08-03T00:00:02.000Z",
    attestation: { schema: "workbench-live-e2e.cdp-endpoint-attestation.v1", observedAt,
      port, runtimePid: pid, listenerPid, ancestorPids: [listenerPid, pid],
      userDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
      listenerExecutablePath: "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\fixture\\msedgewebview2.exe",
      listenerExecutable: "msedgewebview2.exe", commandLineSha256: "1".repeat(64),
      argvSha256: "2".repeat(64), exactPortArgument: true, exactUserDataRoot: true } };
}

function productionClosure() {
  fixtureLoadedSources = new Map();
  const files = ProductionClosure.productionFiles(REPOSITORY_ROOT).map((descriptor, index) => {
    const locator = "root:" + descriptor.relativePath.replace(/\\/g, "/");
    const loaded = descriptor.role === "page" || descriptor.relativePath.endsWith(".js")
      || descriptor.relativePath.endsWith(".css")
      || ["page_fixed_image", "page_conditional_asset", "icon_manifest", "font_manifest",
        "font_fallback_asset"].includes(descriptor.role);
    let bytes = null;
    if (loaded) {
      let source;
      if (descriptor.role === "page") {
        source = "<!doctype html><html><head></head><body><script>"
          + FIXTURE_INLINE_SOURCE + "</script></body></html>";
      } else if (descriptor.relativePath.endsWith(".css")) {
        source = "/* fixture loaded source " + descriptor.relativePath + " */\n";
      } else if (descriptor.role === "icon_manifest") {
        source = JSON.stringify({
          fixture_weapon_icon: { f1: "fixture_weapon_icon.webp" },
          fixture_stable_sidearm_icon: { f1: "fixture_stable_sidearm_icon.webp" },
          [CANDIDATE_A.icon]: { f1: "7c575e62_1.webp" },
          [CANDIDATE_B.icon]: { f1: "240b496d_1.webp" },
        });
      } else if (descriptor.role === "font_manifest") {
        source = JSON.stringify({ fixture: true, font: "lxgw-wenkai-screen.ttf" });
      } else {
        source = descriptor.relativePath.endsWith(".js")
          ? "\"use strict\";\n// fixture loaded source " + descriptor.relativePath + "\n"
          : "fixture resource bytes " + descriptor.relativePath + "\n";
      }
      bytes = Buffer.from(source, "utf8");
      fixtureLoadedSources.set(locator, bytes);
    }
    return { role: descriptor.role, locator,
      sha256: bytes ? Evidence.sha256Bytes(bytes)
        : (index + 1).toString(16).padStart(2, "0").repeat(32),
      bytes: bytes ? bytes.length : 1000 + index };
  });
  function fileBy(relativePath) {
    return files.find((entry) => entry.locator === "root:" + relativePath);
  }
  function route(relativePath, resourceType, required) {
    const entry = fileBy(relativePath);
    const extension = path.extname(relativePath).toLowerCase();
    const mimeType = extension === ".html" ? "text/html"
      : extension === ".js" ? "text/javascript"
        : extension === ".css" ? "text/css"
          : extension === ".json" ? "application/json"
          : extension === ".webp" ? "image/webp"
            : extension === ".png" ? "image/png"
              : extension === ".jpg" ? "image/jpeg"
                : extension === ".svg" ? "image/svg+xml" : "application/octet-stream";
    return { url: "https://overlay.local/" + relativePath.slice("launcher/web/".length),
      resourceType, mimeType, locator: entry.locator, sha256: entry.sha256,
      bytes: entry.bytes, required: required === true };
  }
  const fixtureIconRoutes = [
    ["fixture_weapon_icon", "fixture_weapon_icon.webp"],
    ["fixture_stable_sidearm_icon", "fixture_stable_sidearm_icon.webp"],
    [CANDIDATE_A.icon, "7c575e62_1.webp"],
    [CANDIDATE_B.icon, "240b496d_1.webp"],
  ].sort((left, right) => left[0] < right[0] ? -1 : (left[0] > right[0] ? 1 : 0))
    .map(([name, fileName]) => {
    const locator = "root:launcher/web/icons/" + fileName;
    const bytes = Buffer.from("fixture icon bytes " + fileName + "\n", "utf8");
    fixtureLoadedSources.set(locator, bytes);
    return { name, resources: [{ url: "https://overlay.local/icons/" + fileName,
      resourceType: "Image", mimeType: "image/webp", locator,
      sha256: Evidence.sha256Bytes(bytes), bytes: bytes.length, required: true }] };
  });
  const fixtureFontBytes = Buffer.from("fixture lxgw routed font bytes\n", "utf8");
  fixtureLoadedSources.set("font-manifest:lxgw-wenkai-screen.ttf", fixtureFontBytes);
  const resourceContract = {
    schema: ProductionClosure.PAGE_RESOURCE_CONTRACT_SCHEMA,
    document: route("launcher/web/overlay.html", "Document", true),
    scripts: ProductionClosure.scriptFiles({ files }).map((entry) =>
      route(entry.locator.slice("root:".length), "Script", true)),
    styles: ProductionClosure.styleFiles({ files }).map((entry) =>
      route(entry.locator.slice("root:".length), "Stylesheet", true)),
    fixedImages: ProductionClosure.BASE_PREWARM_ASSETS.map((relativePath) =>
      route(relativePath, "Image", true)),
    conditionalAssets: ProductionClosure.CONDITIONAL_CSS_ASSETS.map((relativePath) =>
      route(relativePath, "Image", false)),
    fonts: [{ url: "https://cfn-fonts.local/lxgw-wenkai-screen.ttf",
      resourceType: "Font", mimeType: "font/ttf",
      locator: "font-manifest:lxgw-wenkai-screen.ttf",
      sha256: Evidence.sha256Bytes(fixtureFontBytes), bytes: fixtureFontBytes.length,
      required: true }],
    iconManifest: route(ProductionClosure.ICON_MANIFEST, "Fetch", true),
    iconRoutes: fixtureIconRoutes,
  };
  resourceContract.contractSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(resourceContract));
  const value = { schema: ProductionClosure.CLOSURE_SCHEMA,
    capturedAt: "2026-08-03T00:00:00.000Z", root: ROOT, files,
    pageResourceContract: resourceContract, producerInputs: fixtureProducerInputs() };
  value.closureSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function loadedProduction(closure, binding, runtimeIdentity, lifecycle) {
  const expected = ProductionClosure.webFiles(closure);
  const pageExpected = expected.find((entry) => entry.role === "page");
  const scripts = ProductionClosure.scriptFiles(closure);
  const styles = ProductionClosure.styleFiles(closure);
  const scriptUrls = scripts.map((entry) => "https://overlay.local/"
    + entry.locator.slice("root:launcher/web/".length));
  const styleUrls = styles.map((entry) => "https://overlay.local/"
    + entry.locator.slice("root:launcher/web/".length));
  const frameId = lifecycle + "-main-frame";
  const contextId = lifecycle === "first" ? 5101 : 5201;
  const contextAuxData = { frameId, isDefault: true, type: "default" };
  const contextOccurrences = [{ occurrence: 1, id: contextId,
    uniqueId: lifecycle + "-context-unique", name: "", origin: "https://overlay.local",
    auxData: clone(contextAuxData) }];
  const inlineBytes = Buffer.from(FIXTURE_INLINE_SOURCE, "utf8");
  const rawScripts = [{ url: "https://overlay.local/overlay.html",
    origin: "https://overlay.local", scriptId: lifecycle + "-inline", source: inlineBytes }]
    .concat(scripts.map((entry, index) => ({ url: scriptUrls[index],
      origin: "https://overlay.local", scriptId: lifecycle + "-script-" + index,
      source: fixtureLoadedSources.get(entry.locator) })));
  const toolScriptPlan = ["identity", "install_new_document",
    "install_current_document", "health", "detach"].map((label, index) => {
    const url = "cf7-evidence://equipment/" + encodeURIComponent("equipment-" + lifecycle)
      + "/" + String(index + 1).padStart(4, "0") + "-" + label + ".js";
    const deliveryMethod = label === "install_new_document"
      ? "Page.addScriptToEvaluateOnNewDocument" : "Runtime.evaluate";
    const source = Buffer.from("(()=>true)()\n//# sourceURL=" + url, "utf8");
    return { sequence: index + 1, label, url, deliveryMethod,
      sourceBase64: source.toString("base64"), sha256: Evidence.sha256Bytes(source),
      bytes: source.length };
  });
  rawScripts.push(...toolScriptPlan.filter((entry) => entry.label !== "install_new_document")
    .map((entry, index) => ({ url: entry.url, origin: "null",
    scriptId: lifecycle + "-tool-" + index,
    source: Buffer.from(entry.sourceBase64, "base64") })));
  const scriptOccurrences = rawScripts.map((entry, index) => {
    const rawParams = { scriptId: entry.scriptId, url: entry.url, startLine: 0,
      startColumn: 0, endLine: 1, endColumn: 0, executionContextId: contextId,
      hash: Evidence.sha256Bytes(entry.source), executionContextAuxData: clone(contextAuxData),
      isLiveEdit: false, sourceMapURL: "", hasSourceURL: entry.url.startsWith("cf7-evidence://") };
    return { occurrence: index + 1, url: entry.url, origin: entry.origin,
      scriptId: entry.scriptId, executionContextId: contextId, rawParams,
      sourceMethod: "Debugger.getScriptSource", sourceBase64: entry.source.toString("base64"),
      sourceSha256: Evidence.sha256Bytes(entry.source), sourceBytes: entry.source.length };
  });
  const frame = { id: frameId, url: "https://overlay.local/overlay.html",
    securityOrigin: "https://overlay.local", mimeType: "text/html" };
  const pageBytes = fixtureLoadedSources.get(pageExpected.locator);
  const resourceOccurrences = [{ occurrence: 1, resourceKind: "frame_document",
    frameId, frameUrl: frame.url, frameOrigin: "https://overlay.local",
    url: frame.url, origin: "https://overlay.local", resourceType: "Document",
    mimeType: "text/html", rawFrame: clone(frame), rawResource: null,
    sourceMethod: "Page.getResourceContent", sourceBase64: pageBytes.toString("base64"),
    sourceSha256: Evidence.sha256Bytes(pageBytes), sourceBytes: pageBytes.length,
    sourceError: null }];
  const contract = closure.pageResourceContract;
  const routed = contract.scripts.concat(contract.styles, contract.fixedImages,
    [contract.iconManifest],
    contract.iconRoutes.flatMap((entry) => entry.resources),
    contract.fonts.filter((entry) => entry.required));
  routed.forEach((route) => {
    const source = fixtureLoadedSources.get(route.locator);
    const rawResource = { url: route.url, type: route.resourceType, mimeType: route.mimeType };
    resourceOccurrences.push({ occurrence: resourceOccurrences.length + 1,
      resourceKind: "frame_resource", frameId, frameUrl: frame.url,
      frameOrigin: "https://overlay.local", url: route.url,
      origin: route.url.startsWith("https://cfn-fonts.local/")
        ? "https://cfn-fonts.local" : "https://overlay.local",
      resourceType: route.resourceType, mimeType: route.mimeType,
      rawFrame: clone(frame), rawResource,
      sourceMethod: "Page.getResourceContent", sourceBase64: source.toString("base64"),
      sourceSha256: Evidence.sha256Bytes(source), sourceBytes: source.length,
      sourceError: null });
  });
  const value = { schema: ProductionClosure.LOADED_SCHEMA, lifecycle,
    capturedAt: lifecycle === "first"
      ? "2026-08-03T00:10:06.000Z" : "2026-08-03T00:10:55.000Z",
    runtimePid: runtimeIdentity.pid, runId: binding.runId,
    productionClosureSha256: closure.closureSha256,
    productionBindingSha256: binding.bindingSha256,
    contextOccurrences, scriptOccurrences, resourceOccurrences, toolSourcePlan: toolScriptPlan };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function logSnapshot(sessionValue, lines, capturedAt) {
  const records = lines.map((line, index) => ({ lineNumber: index + 1, line }));
  const payload = { schema: LauncherObservation.LOG_SNAPSHOT_SCHEMA, requestedTailLimit: 2000,
    sessionEvidenceSha256: sessionValue.sessionEvidenceSha256, lifecycleId: sessionValue.lifecycleId,
    sessionPid: sessionValue.pid, sessionProcessStartUtcTicks: sessionValue.processStartUtcTicks,
    total: records.length, oldestLineNumber: records.length ? 1 : 1, records };
  return Object.assign({}, payload, { capturedAt,
    tailSha256: Evidence.sha256Text(Evidence.canonicalJson(payload)) });
}

function emptyBoundary(sessionValue) {
  return LauncherObservation.createTerminalLogBoundary(logSnapshot(sessionValue, [],
    "2026-08-03T00:09:00.000Z"));
}

function snapshotStateRef(value) {
  const stable = {
    gender: value.gender,
    equipment: value.equipment,
    enhance: value.enhance,
    tierCandidates: value.tierCandidates,
    modCandidates: value.modCandidates,
    materials: value.materials,
  };
  return tokenRef(Evidence.canonicalJson(stable));
}

const FIXTURE_AUTHORITY_KEYS = ["expectedTuningToken", "tuningToken", "expectedLease",
  "slotLease", "transactionId"];

function sanitizeCommand(value) {
  if (Array.isArray(value)) return value.map(sanitizeCommand);
  if (!value || typeof value !== "object") return clone(value);
  const output = {};
  Object.keys(value).forEach((key) => {
    if (FIXTURE_AUTHORITY_KEYS.includes(key)) output[key + "Ref"] = value[key];
    else output[key] = sanitizeCommand(value[key]);
  });
  return output;
}

function authoritySummary(value) {
  let count = 0;
  const refs = {};
  function visit(current) {
    if (Array.isArray(current)) return current.forEach(visit);
    if (!current || typeof current !== "object") return;
    Object.keys(current).forEach((key) => {
      if (FIXTURE_AUTHORITY_KEYS.includes(key)) {
        count += 1;
        if (!refs[key]) refs[key] = new Set();
        refs[key].add(current[key]);
      } else visit(current[key]);
    });
  }
  visit(value);
  let text = count ? " authorityFieldCount=" + count : "";
  FIXTURE_AUTHORITY_KEYS.forEach((key) => {
    if (!refs[key]) return;
    const values = Array.from(refs[key]).sort();
    text += " " + key + (values.length === 1 ? "Ref=" : "Refs=")
      + values.slice(0, 4).join(",");
    if (values.length > 4) text += " " + key + "RefCount=" + values.length;
  });
  return text;
}

function sourceKeyRefForRequest(request) {
  const source = request.payload && request.payload.source;
  if (source && source.expectedLease === SOURCE_RESTART.expectedLease) {
    return tokenRef(rawSourceKey(SOURCE_RESTART, RAW_SOURCE_LEASE_RESTART));
  }
  const after = source && source.expectedLease === SOURCE_AFTER.expectedLease;
  return tokenRef(rawSourceKey(after ? SOURCE_AFTER : SOURCE_BEFORE,
    after ? RAW_SOURCE_LEASE_AFTER : RAW_SOURCE_LEASE_BEFORE));
}

function hostLines(transcript) {
  const lines = [];
  const firstLifecycle = transcript.observerId === "equipment-first";
  let fid = 0;
  let writeEpoch = 0;
  let acceptedPreview = null;
  const actions = {
    equipment_tuning: {
      snapshot: "equipmentTuningSnapshot",
      preview: "equipmentTuningPreview",
      commit: "equipmentTuningCommit",
      detach: "equipmentTuningDetach",
    },
    inventory: { snapshot: "inventorySnapshot" },
  };
  transcript.events.filter((event) => event.kind === "bridge_send" && event.message
    && ["equipment_tuning", "inventory"].includes(event.message.domain)).forEach((event) => {
    const request = event.message;
    fid += 1;
    if (request.domain === "equipment_tuning" && request.cmd === "commit") writeEpoch += 1;
    const action = actions[request.domain][request.cmd];
    const marker = request.domain === "equipment_tuning"
      ? "[EquipmentTuningTask] -> Flash: " : "[InventoryTask] -> Flash: ";
    lines.push("[Panel] HandlePanelMessage: task=panel panel=workbench domain="
      + request.domain + " cmd=" + request.cmd
      + " callId=" + encodeURIComponent(request.callId)
      + " payload=redacted len=100" + authoritySummary(request));
    lines.push("[Panel] Routing domain=" + request.domain + " cmd=" + request.cmd
      + " to " + (request.domain === "equipment_tuning"
        ? "EquipmentTuningTask, _equipmentTuningTask=ok"
        : "InventoryTask, _inventoryTask=ok"));
    lines.push("event=authority_flash_call_bound"
      + " domain=" + request.domain
      + " webCallId=" + encodeURIComponent(request.callId)
      + " flashCallId=" + fid
      + " panel=workbench"
      + " panelInstanceId=" + encodeURIComponent(request.panelInstanceId)
      + (request.domain === "equipment_tuning"
        ? " viewSessionId=" + encodeURIComponent(request.payload.viewSessionId) : "")
      + " cmd=" + request.cmd
      + " action=" + action);
    if (request.domain === "equipment_tuning") {
      const payload = clone(request.payload);
      payload.panelInstanceId = request.panelInstanceId;
      payload.viewSessionId = request.payload.viewSessionId;
      payload.writeEpoch = writeEpoch;
      payload.requestCallId = request.callId;
      lines.push(marker + JSON.stringify(Object.assign({ task: "cmd", action, callId: fid },
        sanitizeCommand(payload))));
    } else {
      lines.push(marker + "task=cmd cmd=" + action + " callId=" + fid
        + " payload=redacted len=100");
    }
    const responseEvent = transcript.events.find((candidateEvent) => candidateEvent.kind === "webview_message"
      && candidateEvent.message && candidateEvent.message.callId === request.callId);
    let responseSummary = "[XmlSocket:JSON] task=" + (request.domain === "equipment_tuning"
      ? "equipment_tuning_response command=" : "inventory_response cmd=")
      + (request.domain === "equipment_tuning" ? request.cmd : "other")
      + " callId=" + fid + " success=true payload=redacted len=100"
      + authoritySummary(responseEvent.message);
    lines.push(responseSummary);
    if (request.domain === "equipment_tuning" && request.cmd === "snapshot") {
      lines.push("event=equipment_tuning_snapshot_confirmed"
        + " callId=" + encodeURIComponent(request.callId)
        + " panelInstanceId=" + encodeURIComponent(request.panelInstanceId)
        + " viewSessionId=" + encodeURIComponent(request.payload.viewSessionId)
        + " sourceKeyRef=" + sourceKeyRefForRequest(request)
        + " stateRef=" + snapshotStateRef(responseEvent.message.snapshot)
        + " writeEpoch=" + writeEpoch);
    }
    if (request.domain === "equipment_tuning" && request.cmd === "preview") {
      const intentKeyRef = tokenRef(previewIntentKey(request.payload.candidateKey));
      lines.push("event=equipment_tuning_preview_settled"
        + " webCallId=" + encodeURIComponent(request.callId)
        + " flashCallId=" + fid
        + " requestCallId=" + encodeURIComponent(request.callId)
        + " tokenRef=" + responseEvent.message.tuningToken
        + " panelInstanceId=" + encodeURIComponent(request.panelInstanceId)
        + " viewSessionId=" + encodeURIComponent(request.payload.viewSessionId)
        + " sourceKeyRef=" + sourceKeyRefForRequest(request)
        + " operation=" + request.payload.operation
        + " candidateKey=" + encodeURIComponent(request.payload.candidateKey)
        + " intentKeyRef=" + intentKeyRef
        + " outcome=success remainingPending=0");
      acceptedPreview = { request, response: responseEvent.message, intentKeyRef,
        sourceKeyRef: sourceKeyRefForRequest(request) };
    } else if (request.domain === "equipment_tuning" && request.cmd === "commit") {
      lines.push("event=equipment_tuning_commit_settled"
        + " webCallId=" + encodeURIComponent(request.callId)
        + " flashCallId=" + fid
        + " requestCallId=" + encodeURIComponent(request.callId)
        + " previewWebCallId=" + encodeURIComponent(acceptedPreview.request.callId)
        + " tokenRef=" + acceptedPreview.response.tuningToken
        + " panelInstanceId=" + encodeURIComponent(request.panelInstanceId)
        + " viewSessionId=" + encodeURIComponent(request.payload.viewSessionId)
        + " sourceKeyRef=" + acceptedPreview.sourceKeyRef
        + " operation=" + acceptedPreview.request.payload.operation
        + " candidateKey=" + encodeURIComponent(acceptedPreview.request.payload.candidateKey)
        + " intentKeyRef=" + acceptedPreview.intentKeyRef
        + " outcome=success writeEpoch=" + writeEpoch + " writeState=idle remainingPending=0"
        + " stateRef=" + snapshotStateRef(responseEvent.message.snapshot)
        + " snapshotPresent=true transactionIdPresent=true");
    }
  });
  const ownerRequest = transcript.events.find((event) => event.kind === "bridge_send"
    && event.message && event.message.domain === "equipment_tuning");
  lines.push("event=panel_exact_close_completed panel=workbench panelInstanceId="
    + encodeURIComponent(ownerRequest.message.panelInstanceId));
  if (firstLifecycle) {
    lines.push("save sv:1");
    lines.push("save sv:2");
    lines.push("[ArchiveTask] Shadow saved: " + TARGET_SLOT + " (990 chars) path="
      + path.join(ROOT, "fixture-target.json"));
  }
  let normalIndex = 0;
  let detachIndex = 0;
  function stamp(iso, line) {
    const value = new Date(iso);
    const pad = (number, width) => String(number).padStart(width, "0");
    return pad(value.getHours(), 2) + ":" + pad(value.getMinutes(), 2) + ":"
      + pad(value.getSeconds(), 2) + "." + pad(value.getMilliseconds(), 3) + " " + line;
  }
  return lines.map((line) => {
    if (line.includes("sv:1")) return stamp("2026-08-03T00:10:16.000Z", line);
    if (line.includes("sv:2")) return stamp("2026-08-03T00:10:16.200Z", line);
    if (line.startsWith("[ArchiveTask] Shadow saved:")) {
      return stamp("2026-08-03T00:10:16.400Z", line);
    }
    if (line.startsWith("event=panel_exact_close_completed ")) {
      return stamp(firstLifecycle ? "2026-08-03T00:10:01.500Z"
        : "2026-08-03T00:10:51.500Z", line);
    }
    if (/cmd=detach|equipmentTuningDetach|command=detach/.test(line)) {
      const base = Date.parse(firstLifecycle ? "2026-08-03T00:10:01.100Z"
        : "2026-08-03T00:10:51.100Z");
      return stamp(new Date(base + detachIndex++ * 100).toISOString(), line);
    }
    const base = Date.parse(firstLifecycle ? "2026-08-03T00:09:10.000Z"
      : "2026-08-03T00:10:31.000Z");
    return stamp(new Date(base + normalIndex++ * 200).toISOString(), line);
  });
}

function artifactSet(slot, appDataRoot, jsonHash, solHash, capturedAt) {
  const artifacts = [];
  if (solHash) artifacts.push({ kind: "sol", locator: "appdata:Macromedia/Flash Player/#SharedObjects/FIXTURE/localhost/"
    + slot + ".sol", sha256: solHash, bytes: 32, regularFile: true, exactRealPath: true });
  artifacts.push({ kind: "json", locator: "root:saves/" + slot + ".json",
    sha256: jsonHash, bytes: 1024, regularFile: true, exactRealPath: true });
  artifacts.sort((left, right) => left.locator.localeCompare(right.locator));
  const payload = { schema: CloneGuard.ARTIFACT_SET_SCHEMA, slot,
    appDataRoot, artifacts };
  return Object.assign({}, payload, { capturedAt: capturedAt || "2026-08-03T00:00:00.000Z",
    setSha256: Evidence.sha256Text(Evidence.canonicalJson(payload)) });
}

function stableArtifactSet(set, marker) {
  const payload = { schema: "workbench-live-e2e.stable-slot-artifact-set.v1",
    apiVersion: "FROZEN-v1", stableMs: 2000, samples: 3,
    observedAt: "2026-08-03T00:" + marker + ":00.000Z", set: clone(set) };
  return Object.assign({}, payload, {
    evidenceSha256: Evidence.sha256Text(Evidence.canonicalJson(payload)),
  });
}

function disk(equipmentValue, materials, marker) {
  const equipmentProjection = { name: equipmentValue.name, level: equipmentValue.level,
    tier: equipmentValue.tier, mods: equipmentValue.mods.slice(),
    lastUpdate: equipmentValue.lastUpdate };
  const persistedSource = { containerId: SOURCE_BEFORE.containerId, slot: SOURCE_BEFORE.slot,
      name: equipmentValue.name, lastUpdate: equipmentValue.lastUpdate,
      valueSha256: (marker === "3" ? "a" : "b").repeat(64),
      recordSha256: (marker === "3" ? "c" : "d").repeat(64) };
  const semanticProjection = { equipment: equipmentProjection,
    materials: clone(materials), persistedSource };
  return { sha256: marker.repeat(64),
    semanticSha256: Evidence.sha256Text(Evidence.canonicalJson(semanticProjection)),
    bytes: marker === "3" ? 1000 : 1100, textCharacters: marker === "3" ? 900 : 990,
    equipment: equipmentProjection, materials: clone(materials), persistedSource };
}

function residue(identityValue, sessionValue, marker) {
  const value = { schema: LauncherObservation.RESIDUE_SCHEMA, apiVersion: "FROZEN-v1",
    observedAt: marker === "a" ? "2026-08-03T00:10:26.000Z"
      : "2026-08-03T00:10:56.500Z", expectedPid: identityValue.pid,
    expectedProcessPath: path.resolve(identityValue.processPath), pidAbsent: true,
    candidateProcessAbsent: true, observedLauncherPids: [],
    ports: [identityValue.httpPort, identityValue.httpPort + 100, marker === "a" ? 19222 : 19223]
      .map((port) => ({ port, open: false })),
    portsFile: sessionValue.portsFile, portsFileAbsent: true,
    credentialFile: sessionValue.credentialFile, credentialFileAbsent: true,
    stableSamples: 3 };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function buildControl(firstContract, firstTranscript, restartTranscript) {
  const decision = { schema: AUTHORIZATION_SCHEMA, decisionId: "fixture-equipment-commit",
    issuedAt: "2026-08-03T00:00:00.000Z", source: "cli_explicit_flag", oneShot: true,
    allowedStep: "commit_candidate_b", scope: { journey: "equipment-install-mod-v2",
      slot: TARGET_SLOT, candidateKey: CANDIDATE_B.candidateKey, operation: "install_mod",
      candidateRoot: CANDIDATE_ROOT } };
  const decisionSha = Evidence.sha256Text(Evidence.canonicalJson(decision));
  const selectors = {
    open_tuning: ["native HUD equipment tuning entry"],
    select_source: ["button[data-physical-slot=\"7\"]"],
    preview_candidate_a: ["button[data-candidate-key=\"" + CANDIDATE_A.candidateKey + "\"]"],
    preview_candidate_b: ["button[data-candidate-key=\"" + CANDIDATE_B.candidateKey + "\"]"],
    commit_candidate_b: [".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]"],
    reselect_source: ["button[data-physical-slot=\"7\"]"],
    close_first_tuning: ["button[data-header-action=\"close\"]"],
    safe_exit: ["native SAFEEXIT"],
    exit_confirm: ["native EXIT_CONFIRM"],
    restart_open_tuning: ["native HUD equipment tuning entry"],
    restart_select_source: ["button[data-physical-slot=\"7\"]"],
    restart_close_tuning: ["button[data-header-action=\"close\"]"],
  };
  const controlBase = Date.parse("2026-08-03T00:09:00.000Z");
  const requests = REQUIRED_CONTROL_STEPS.map((step, index) => ({
    schema: CONTROL_REQUEST_SCHEMA, runId: RUN_ID, requestId: "fixture-" + step, step,
    issuedAt: new Date(controlBase + index * 10000).toISOString(),
    expiresAt: new Date(controlBase + index * 10000 + 3600000).toISOString(),
    allowedTransports: ["codex_computer_use"],
    requiresCommitAuthorization: step === "commit_candidate_b",
    requiresCaptureSha256: true,
    authorizationRef: step === "commit_candidate_b"
      ? { decisionId: decision.decisionId, decisionSha256: decisionSha } : null,
    instructions: "fixture exact control step " + step,
    selectors: selectors[step], expectedIndependentEvidence: ["independent evidence for " + step],
  }));
  const webBindings = {
    select_source: [firstTranscript, selectors.select_source[0], 0],
    preview_candidate_a: [firstTranscript, selectors.preview_candidate_a[0], 0],
    preview_candidate_b: [firstTranscript, selectors.preview_candidate_b[0], 0],
    commit_candidate_b: [firstTranscript, selectors.commit_candidate_b[0], 0],
    reselect_source: [firstTranscript, selectors.reselect_source[0], 1],
    close_first_tuning: [firstTranscript, selectors.close_first_tuning[0], 0],
    restart_select_source: [restartTranscript, selectors.restart_select_source[0], 0],
    restart_close_tuning: [restartTranscript, selectors.restart_close_tuning[0], 0],
  };
  function nativeInputEvidence(request, index, eventObservedAt, eventReceivedAt) {
    const left = 20 + index * 3;
    const mirrored = { eventType: "click", isTrusted: true,
      selector: request.selectors[0], tagName: "NATIVE", visible: true, enabled: true,
      viewport: { width: 1600, height: 900 },
      rect: { left, top: 20, right: left + 120, bottom: 60, width: 120, height: 40 },
      clientPoint: { x: left + 60, y: 40 }, hitTargetMatches: true,
      key: null, button: 0, repeat: false };
    const eventValue = Object.assign({ schema: NATIVE_INPUT_EVENT_SCHEMA, runId: RUN_ID,
      requestId: request.requestId, step: request.step,
      observedAt: eventObservedAt, receivedAt: eventReceivedAt }, mirrored);
    eventValue.eventSha256 = Evidence.sha256Text(Evidence.canonicalJson(eventValue));
    const relativePath = "control/native-input-events/" + request.requestId + ".json";
    const bytes = Buffer.from(JSON.stringify(eventValue, null, 2) + "\n", "utf8");
    fs.writeFileSync(path.join(RUN_DIR, relativePath.replace(/\//g, path.sep)), bytes);
    return Object.assign({ kind: "native_input", observedAt: eventReceivedAt,
      eventRef: { artifact: relativePath, sha256: Evidence.sha256Bytes(bytes),
        eventSha256: eventValue.eventSha256 } }, mirrored);
  }
  function inputEvidence(request, index, eventObservedAt, eventReceivedAt) {
    const binding = webBindings[request.step];
    if (!binding) return nativeInputEvidence(request, index, eventObservedAt, eventReceivedAt);
    const events = binding[0].events.filter((event) => event.kind === "dom_input"
      && event.target && event.target.selector === binding[1]);
    const event = events[binding[2]];
    return domInputEvidence(binding[0].observerId, event);
  }
  const acks = requests.map((request, index) => {
    const requestBytes = Buffer.from(JSON.stringify(request, null, 2) + "\n", "utf8");
    fs.writeFileSync(path.join(REQUEST_DIR, request.requestId + ".json"), requestBytes);
    const capture = CAPTURES[index];
    const eventObservedAt = new Date(controlBase + index * 10000 + 1000).toISOString();
    const eventReceivedAt = new Date(controlBase + index * 10000 + 2000).toISOString();
    const evidence = inputEvidence(request, index, eventObservedAt, eventReceivedAt);
    const inputAt = Date.parse(evidence.observedAt);
    const startedAt = new Date(Math.max(Date.parse(request.issuedAt) + 1, inputAt - 1000))
      .toISOString();
    const captureDelay = request.step === "safe_exit" ? 5000 : 1000;
    const capturedAt = new Date(inputAt + captureDelay).toISOString();
    const providerCompletedAt = new Date(inputAt + captureDelay + 1000).toISOString();
    const completedAt = new Date(inputAt + captureDelay + 2000).toISOString();
    const capturePath = path.join(RUN_DIR, capture.relativePath.replace(/\//g, path.sep));
    fs.utimesSync(capturePath, new Date(capturedAt), new Date(capturedAt));
    const fileModifiedAt = fs.statSync(capturePath).mtime.toISOString();
    const captureEvent = { schema: PROVIDER_CAPTURE_EVENT_SCHEMA, runId: RUN_ID,
      requestId: request.requestId, step: request.step, transport: "codex_computer_use",
      issuer: "codex_computer_use", toolResultSource: "codex_computer_use_tool_result",
      providerEventId: "pending", requestSha256: Evidence.sha256Bytes(requestBytes),
      captureArtifact: capture.relativePath, capturedAt, fileModifiedAt,
      captureBytes: capture.bytes, captureSha256: capture.sha256,
      captureWidth: 320, captureHeight: 180,
      captureSemanticContentIndependentlyVerified: false };
    captureEvent.providerEventId = expectedProviderCaptureEventId(captureEvent);
    captureEvent.eventSha256 = Evidence.sha256Text(Evidence.canonicalJson(captureEvent));
    const captureEventBytes = Buffer.from(JSON.stringify(captureEvent, null, 2) + "\n", "utf8");
    const captureEventRelative = "control/capture-events/" + request.requestId + ".json";
    fs.writeFileSync(path.join(CAPTURE_EVENT_DIR, request.requestId + ".json"),
      captureEventBytes);
    const captureEventRef = { artifact: captureEventRelative,
      sha256: Evidence.sha256Bytes(captureEventBytes), eventSha256: captureEvent.eventSha256 };
    const providerReceipt = { schema: PROVIDER_RECEIPT_SCHEMA, runId: RUN_ID,
      requestId: request.requestId, step: request.step, transport: "codex_computer_use",
      issuer: "codex_computer_use", toolResultSource: "codex_computer_use_tool_result",
      requestSha256: Evidence.sha256Bytes(requestBytes),
      providerOperationId: "pending", action: request.step, result: "completed", startedAt,
      inputEvidence: evidence, completedAt: providerCompletedAt,
      ownedArtifact: "control/provider-receipts/" + request.requestId + ".json",
      captureEventRef };
    providerReceipt.providerOperationId = expectedProviderOperationId(providerReceipt);
    providerReceipt.receiptSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(providerReceipt));
    const providerBytes = Buffer.from(JSON.stringify(providerReceipt, null, 2) + "\n", "utf8");
    const providerPath = path.join(PROVIDER_RECEIPT_DIR, request.requestId + ".json");
    fs.writeFileSync(providerPath, providerBytes);
    const ack = { schema: CONTROL_ACK_SCHEMA, runId: RUN_ID,
      requestId: request.requestId, step: request.step,
      transport: "codex_computer_use", result: "completed",
      completedAt,
      captureSha256: capture.sha256,
      capture: { relativePath: capture.relativePath, sha256: capture.sha256,
        bytes: capture.bytes, mediaType: capture.mediaType },
      authorizationDecisionId: request.requiresCommitAuthorization ? decision.decisionId : null,
      providerReceipt: { artifact: "control/provider-receipts/" + request.requestId + ".json",
        sha256: Evidence.sha256Bytes(providerBytes) },
      details: {} };
    fs.writeFileSync(path.join(ACK_DIR, request.requestId + ".json"),
      JSON.stringify(ack, null, 2) + "\n", "utf8");
    return ack;
  });
  const capabilityArtifact = { schema: "workbench-live-e2e.equipment.launch-capability.v2",
    processContractSha256: firstContract.artifactSha256, launchMode: "legacy_http_automation",
    agentRuntimeAdmission: false };
  return { selectedTransport: "codex_computer_use", fallbackAllowed: true,
    capability: { schema: CAPABILITY_SCHEMA, available: false,
      source: "authenticated_legacy_http_process_contract", artifact: capabilityArtifact,
      artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(capabilityArtifact)) },
    authorization: decision, authorizationSha256: decisionSha, requests, acks };
}

function buildValidBundle() {
  resetCaptureFiles();
  const firstTranscript = buildTranscript("first");
  const restartTranscript = buildTranscript("restart");
  const closure = productionClosure();
  const producer = prepareFixtureCandidate(closure);
  const firstIdentity = identity(4100, 18080, producer);
  const restartIdentity = identity(4200, 18081, producer);
  const firstSession = session(4100, 18080, "638898000000000001", "lifecycle_fixture_first", "a");
  const restartSession = session(4200, 18081, "638898000000000002", "lifecycle_fixture_restart", "b");
  const firstContract = processContract(firstIdentity, firstSession, "f");
  const restartContract = processContract(restartIdentity, restartSession, "7");
  const candidateProducer = ProductionClosure.captureCandidateProducerBinding(
    CANDIDATE_ROOT, firstIdentity, closure);
  const binding = ProductionClosure.bindProductionClosure(
    closure, firstIdentity, "fixture-equipment-v2", candidateProducer);
  const firstLog = logSnapshot(firstSession, hostLines(firstTranscript),
    "2026-08-03T00:10:18.000Z");
  const restartLog = logSnapshot(restartSession, hostLines(restartTranscript),
    "2026-08-03T00:10:55.100Z");
  const shutdownEvidence = {
    schema: "workbench-live-e2e.equipment.authenticated-shutdown.v1",
    requestedAt: "2026-08-03T00:10:55.500Z",
    completedAt: "2026-08-03T00:10:56.000Z",
    pid: restartIdentity.pid,
    sessionEvidenceSha256: restartSession.sessionEvidenceSha256,
    response: { success: true, ok: true, action: "shutdown" },
  };
  shutdownEvidence.evidenceSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(shutdownEvidence));
  const appData = path.join(ROOT, "fixture-appdata");
  const seed = artifactSet(SEED_SLOT, appData, "1".repeat(64), "2".repeat(64));
  const prepared = artifactSet(TARGET_SLOT, appData, "3".repeat(64), null);
  const committed = artifactSet(TARGET_SLOT, appData, "6".repeat(64), "7".repeat(64),
    "2026-08-03T00:15:00.000Z");
  const beforeEquipment = equipment([], 100);
  const afterEquipment = equipment([CANDIDATE_B.itemName], 200);
  const initialDisk = disk(beforeEquipment,
    { [CANDIDATE_A.itemName]: 3, [CANDIDATE_B.itemName]: 4 }, "3");
  const committedDisk = disk(afterEquipment,
    { [CANDIDATE_A.itemName]: 3, [CANDIDATE_B.itemName]: 3 }, "6");
  const archive = { schema: LauncherObservation.ARCHIVE_SCHEMA, apiVersion: "FROZEN-v1",
    boundary: emptyBoundary(firstSession), finalSnapshotSha256: firstLog.tailSha256,
    requiredOrder: ["sv1", "sv2", "archive"],
    positions: { sv1: { lineNumber: firstLog.total - 2, offset: 5 },
      sv2: { lineNumber: firstLog.total - 1, offset: 5 },
      archive: { lineNumber: firstLog.total, offset: 0 } },
    archive: { lineNumber: firstLog.total, offset: 0, characters: committedDisk.textCharacters,
      path: path.join(ROOT, "fixture-target.json") },
    disk: { schema: "workbench-live-e2e.disk-save-evidence.v1", slot: TARGET_SLOT,
      path: path.join(ROOT, "fixture-target.json"), sha256: committedDisk.sha256,
      bytes: committedDisk.bytes, textCharacters: committedDisk.textCharacters,
      capturedAt: "2026-08-03T00:10:19.500Z" } };
  archive.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(archive));
  const release = { schema: CloneGuard.RELEASE_SCHEMA, apiVersion: "FROZEN-v1",
    releasedAt: "2026-08-03T00:20:00.000Z", seedEnd: clone(seed), targetEnd: clone(committed),
    backupsVerified: true, preparedRecoveryRecordSha256: "8".repeat(64),
    lockRelease: { lockFileAbsent: true, terminalPrivateRelease: true },
    recoveryClear: { recoveryFileAbsent: true } };
  release.releaseSha256 = Evidence.sha256Text(Evidence.canonicalJson(release));
  const expectedIdentity = RuntimePublic(firstIdentity);
  return {
    schema: BUNDLE_SCHEMA, apiVersion: API_VERSION, status: "captured_unverified",
    deployment: "NOT_DEPLOYED", generatedAt: "2026-08-03T00:00:00.000Z",
    evidenceMode: "offline_fixture",
    fixtureProvenance: { schema: "workbench-live-e2e.equipment.fixture-provenance.v1",
      generator: "fixtures/valid-bundle.js", synthetic: true, liveCapture: false },
    safeExitUiJourneyVerified: false, exitMethod: "offline_fixture_simulation",
    runId: RUN_ID, root: ROOT, runDir: RUN_DIR,
    seedSlot: SEED_SLOT, targetSlot: TARGET_SLOT, candidateRoot: CANDIDATE_ROOT,
    allowIsolatedCommit: true, allowCodexCuFallback: true,
    productionClosure: closure, productionBinding: binding, candidateProducer,
    runtime: { expectedIdentity,
      trustedCdpExpectations: { expectedPageUrl: "https://overlay.local/overlay.html",
        expectedPageOrigin: "https://overlay.local",
        expectedUserDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
        expectedListenerExecutableName: "msedgewebview2.exe" },
      first: { identity: firstIdentity, attemptId: "attempt_fixture_first",
        sessionEvidence: firstSession, processContract: firstContract,
        cdpBinding: cdpBinding(19222, 4100, 5100, "a"),
        loadedProduction: loadedProduction(closure, binding, firstIdentity, "first"),
        startBoundary: emptyBoundary(firstSession), finalLogSnapshot: firstLog },
      restart: { identity: restartIdentity, attemptId: "attempt_fixture_restart",
        sessionEvidence: restartSession, processContract: restartContract,
        cdpBinding: cdpBinding(19223, 4200, 5200, "b"),
        loadedProduction: loadedProduction(closure, binding, restartIdentity, "restart"),
        startBoundary: emptyBoundary(restartSession), finalLogSnapshot: restartLog,
        shutdownEvidence } },
    control: buildControl(firstContract, firstTranscript, restartTranscript),
    transcripts: { first: firstTranscript, restart: restartTranscript },
    persistence: { seedBegin: seed, seedEnd: clone(seed), targetPrepared: prepared,
      afterCommit: committed, afterRestart: clone(committed), diskInitial: initialDisk,
      diskAfterCommit: committedDisk, diskAfterRestart: clone(committedDisk),
      archiveEvidence: archive, release,
      stability: { targetPrepared: stableArtifactSet(prepared, "05"),
        afterCommit: stableArtifactSet(committed, "15"),
        afterRestart: stableArtifactSet(committed, "19") } },
    residue: { afterSafeExit: residue(firstIdentity, firstSession, "a"),
      final: residue(restartIdentity, restartSession, "b") },
    moduleJournal: { manifest: null, artifact: null },
  };
}

function RuntimePublic(value) {
  return { runtimeMode: value.runtimeMode, processPath: path.resolve(value.processPath),
    coreSha256: value.coreSha256, buildIdentity: value.buildIdentity,
    payloadClosure: value.payloadClosure, installRoot: path.resolve(value.installRoot) };
}

module.exports = { CANDIDATE_A, CANDIDATE_B, ROOT, RUN_DIR, buildValidBundle, fixturePng };
