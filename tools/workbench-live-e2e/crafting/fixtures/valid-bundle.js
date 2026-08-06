"use strict";

if (require.main === module) {
  console.error("Offline fixture is admitted only by the canonical Crafting bootstrap check");
  process.exit(2);
}

const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const CloneGuard = require("../../lib/clone-save-guard");
const Evidence = require("../../lib/evidence-artifact");
const LauncherObservation = require("../../lib/launcher-observation");
const RuntimeGuard = require("../../lib/runtime-guard");
const {
  API_VERSION,
  AUTHORIZATION_SCHEMA,
  BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA,
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  PROVIDER_CAPTURE_EVENT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  TRANSCRIPT_SCHEMA,
  nextRecord,
  tokenRef,
} = require("../common");
const { REQUIRED_CONTROL_STEPS, domInputEvidence, expectedControlIntent,
  expectedProviderCaptureEventId, expectedProviderOperationId } = require("../control-channel");
const Protocol = require("../protocol");
const SourceContract = require("../source-contract");

const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-crafting-e2e-fixture-"));
const PROJECT_ROOT = path.resolve(__dirname, "..", "..", "..", "..");
const PROJECT_SOURCE_FINGERPRINT = SourceContract.captureSourceFingerprint(PROJECT_ROOT);
const RUN_DIR = path.join(ROOT, "tmp", "workbench-live-e2e", "crafting", "fixture");
const REQUEST_DIR = path.join(RUN_DIR, "control", "requests");
const ACK_DIR = path.join(RUN_DIR, "control", "acks");
const CAPTURE_DIR = path.join(RUN_DIR, "control", "captures");
const PROVIDER_RECEIPT_DIR = path.join(RUN_DIR, "control", "provider-receipts");
const CAPTURE_EVENT_DIR = path.join(RUN_DIR, "control", "capture-events");
fs.mkdirSync(REQUEST_DIR, { recursive: true });
fs.mkdirSync(ACK_DIR, { recursive: true });
fs.mkdirSync(CAPTURE_DIR, { recursive: true });
fs.mkdirSync(PROVIDER_RECEIPT_DIR, { recursive: true });
fs.mkdirSync(CAPTURE_EVENT_DIR, { recursive: true });
function crc32(bytes) {
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
  output.writeUInt32BE(crc32(Buffer.concat([name, data])), 8 + data.length);
  return output;
}
function visiblePng(width, height, seed) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const stride = width * 4 + 1;
  const raw = Buffer.alloc(stride * height, 0);
  for (let row = 0; row < height; row += 1) {
    for (let column = 0; column < width; column += 1) {
      const offset = row * stride + 1 + column * 4;
      raw[offset] = (column + seed * 17) % 256;
      raw[offset + 1] = (row + seed * 31) % 256;
      raw[offset + 2] = (column + row + seed * 47) % 256;
      raw[offset + 3] = 255;
    }
  }
  return Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", ihdr), pngChunk("IDAT", zlib.deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0))]);
}
const CAPTURE_BYTES = REQUIRED_CONTROL_STEPS.map((_step, index) =>
  visiblePng(320, 180, index + 1));
const CAPTURES = REQUIRED_CONTROL_STEPS.map((step, index) => {
  const name = "fixture-" + step + ".png";
  const bytes = CAPTURE_BYTES[index];
  const file = path.join(CAPTURE_DIR, name);
  fs.writeFileSync(file, bytes, { flag: "wx" });
  return { relativePath: "control/captures/" + name,
    sha256: Evidence.sha256Bytes(bytes), bytes: bytes.length, mediaType: "image/png" };
});
process.once("exit", () => {
  try {
    if (path.dirname(ROOT) === path.resolve(os.tmpdir())
        && path.basename(ROOT).startsWith("cf7-crafting-e2e-fixture-")) {
      fs.rmSync(ROOT, { recursive: true, force: true });
    }
  } catch (_error) {}
});

const CATEGORY = "武器合成";
const RECIPE_INDEX = 7;
const CRAFT_COUNT = 1;
const SEED_SLOT = "cf7_agent_crafting_seed_fixture";
const TARGET_SLOT = "cf7_agent_crafting_target_fixture";
const CANDIDATE_ROOT = path.join(ROOT, "tmp", "runtime-candidates", "v2", "fixture-crafting");
const OUTPUT = Object.freeze({
  name: "fixture.output.internal",
  displayName: "验证产物",
  icon: "强化石",
  itemKind: "stack",
  value: 1,
  quantity: 1,
  enhancementLevel: 0,
  majorType: "consumable",
  use: "",
  actionType: "",
  weaponType: "",
  setId: "",
  setName: "",
  setOrder: 0,
  requiredLevel: 0,
});
const MATERIAL = Object.freeze({
  name: "fixture.material.internal",
  displayName: "验证材料",
  icon: "废城防弹军装上装",
  itemKind: "stack",
  required: 2,
  consumed: true,
  isQuantity: true,
});
const UNRELATED = Object.freeze({
  name: "fixture.unrelated.internal", displayName: "稳定无关物品", icon: "金钱",
  itemKind: "stack", majorType: "consumable", use: "", actionType: "",
  weaponType: "", setId: "", setName: "", setOrder: 0,
});
const PROJECT_FONT_ENVIRONMENT = SourceContract.captureFontEnvironment(
  PROJECT_ROOT, PROJECT_SOURCE_FINGERPRINT, process.env);
const PROJECT_ICON_PROJECTION = SourceContract.iconResourceSetForNames(
  PROJECT_ROOT, PROJECT_SOURCE_FINGERPRINT, [OUTPUT.icon, MATERIAL.icon, UNRELATED.icon]);
const TOKENS = Object.freeze({
  auto: tokenRef("fixture-auto-preview"),
  selected: tokenRef("fixture-selected-preview"),
  accepted: tokenRef("fixture-accepted-preview"),
  fresh: tokenRef("fixture-fresh-preview"),
  final: tokenRef("fixture-final-preview"),
  restartAuto: tokenRef("fixture-restart-auto"),
  restartSelected: tokenRef("fixture-restart-selected"),
  restartFinal: tokenRef("fixture-restart-final"),
});

function clone(value) { return JSON.parse(JSON.stringify(value)); }
function recipeOutput() {
  const value = clone(OUTPUT);
  delete value.requiredLevel;
  return value;
}
function panelState() {
  return { panel: "crafting", hidden: false, craftingVisible: true, view: "recipes" };
}
function request(owner, callId, cmd, payload) {
  return { type: "panel", domain: "crafting", panel: "crafting",
    panelInstanceId: owner, cmd, callId, payload };
}
function recipe() {
  return { recipeIndex: RECIPE_INDEX, title: "验证配方", output: recipeOutput(),
    baseCost: { money: 10, kpoints: 0 }, materialCount: 1,
    batchEligible: true, canCraftOne: true, availability: "ready" };
}
function snapshot(owner, callId, balance) {
  return { type: "panel_resp", domain: "crafting", panel: "crafting",
    panelInstanceId: owner, cmd: "snapshot", callId, success: true, v: 1,
    category: CATEGORY, gender: "男", recipes: [recipe()],
    balance: clone(balance), skills: {
      reverseLevel: 0, smithEnabled: false, smithLevel: 0,
    }, note: "fixture" };
}
function material(owned) {
  return Object.assign({}, clone(MATERIAL), { owned, maxEnhancement: 0,
    tier: "", enough: owned >= MATERIAL.required, storageKind: "bag" });
}
function outputDelivery() {
  return { available: true, storageKind: "bag", mode: "merge",
    physicalSlot: 0, quantity: OUTPUT.quantity };
}
function outputPrototype() {
  const item = inventoryItem(OUTPUT, OUTPUT.quantity);
  return { item, confirmProjection: {
    itemKind: item.itemKind, name: item.name, displayName: item.displayName,
    quantity: item.quantity, enhancementLevel: item.enhancementLevel,
    rarity: item.rarity, tier: "", modSignature: "",
  } };
}
function outputReceipt() {
  const item = inventoryItem(OUTPUT, 3);
  return { item, confirmProjection: {
    itemKind: item.itemKind, name: item.name, displayName: item.displayName,
    quantity: item.quantity, enhancementLevel: item.enhancementLevel,
    rarity: item.rarity, tier: "", modSignature: "", lastUpdate: 2000,
  } };
}
function acceptedPlan(owned) {
  return { category: CATEGORY, recipeIndex: RECIPE_INDEX, craftCount: CRAFT_COUNT,
    output: clone(OUTPUT), materials: [material(owned)], outputDelivery: outputDelivery(),
    outputPrototype: outputPrototype(), cost: { money: 10, kpoints: 0 } };
}
function preview(owner, callId, balance, owned, token) {
  return { type: "panel_resp", domain: "crafting", panel: "crafting",
    panelInstanceId: owner, cmd: "preview", callId, success: true, v: 1,
    category: CATEGORY, recipeIndex: RECIPE_INDEX, craftCount: CRAFT_COUNT,
    batchEligible: true, maxCraftCount: 9, output: clone(OUTPUT),
    materials: [material(owned)], cost: { money: 10, kpoints: 0 },
    balance: clone(balance), skills: {
      reverseLevel: 0, smithEnabled: false, smithLevel: 0,
    }, levelAllowed: true, enoughMaterials: true, enoughMoney: true,
    enoughKpoints: true, enoughSpace: true, canCommit: true,
    blockingError: "", outputDelivery: outputDelivery(), craftTokenRef: token,
    acceptedPlan: acceptedPlan(owned) };
}
function commit(owner, callId) {
  return { type: "panel_resp", domain: "crafting", panel: "crafting",
    panelInstanceId: owner, cmd: "commit", callId, success: true, v: 1,
    operation: "commit", category: CATEGORY, recipeIndex: RECIPE_INDEX,
    craftCount: CRAFT_COUNT, crafted: clone(OUTPUT),
    acceptedPlan: acceptedPlan(5), outputReceipt: outputReceipt(),
    balance: { money: 90, kpoints: 5 } };
}
function input(target) {
  const rect = { left: 100, top: 100, right: 220, bottom: 140,
    width: 120, height: 40 };
  return { kind: "dom_input", eventType: "click", isTrusted: true, button: 0,
    target: Object.assign({ tagName: "BUTTON", text: "fixture",
      selector: "button", attributes: {}, mutationCapable: false,
      visible: true, enabled: true,
      viewport: { width: 1280, height: 720, scrollX: 0, scrollY: 0 },
      clientPoint: { x: 160, y: 120 }, hitTargetMatches: true, rect }, target),
    coordinates: { x: 160, y: 120 },
    panelState: panelState(), pageTime: 1000 };
}
function message(kind, value) {
  return { kind, message: value, panelState: panelState(), pageTime: 1000 };
}
function inventoryRequest(owner, callId) {
  return { type: "panel", domain: "inventory", panel: "crafting",
    panelInstanceId: owner, cmd: "snapshot", callId, payload: { v: 1, requests: [
      { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
      { containerId: "战备箱", offset: 0, limit: 40, filterKey: "all" },
    ] } };
}
function inventoryItem(source, quantity) {
  return {
    name: source.name, displayName: source.displayName, icon: source.icon,
    majorType: source.majorType || "consumable", use: source.use || "",
    actionType: source.actionType || "", weaponType: source.weaponType || "",
    setId: source.setId || "", setName: source.setName || "",
    setOrder: source.setOrder || 0, itemKind: source.itemKind, quantity,
    enhancementLevel: 0, maxEnhancementLevel: 0, isMaxEnhancement: false,
    tierSlotAvailable: false, tierSlotUsed: false,
    modSlotCapacity: 0, modSlotUsed: 0, modSlots: [], modMeta: null, rarity: "",
  };
}

function inventorySlot(index, source, quantity, phase, container, lastUpdate) {
  const base = { physicalSlot: index, occupied: !!source && quantity > 0,
    slotLeaseRef: tokenRef("lease." + phase + "." + container + "." + index) };
  if (!source || quantity <= 0) return base;
  const item = inventoryItem(source, quantity);
  return Object.assign(base, { item, confirmProjection: {
    itemKind: item.itemKind, name: item.name, displayName: item.displayName,
    quantity: item.quantity, enhancementLevel: item.enhancementLevel,
    rarity: item.rarity, tier: "", modSignature: "", lastUpdate,
  } });
}

function inventorySnapshot(containerId, capacity, quantity, phase, ordinal) {
  const tag = containerId === "背包" ? "bag" : "storage";
  const bag = containerId === "背包";
  const slots = [];
  const visibleCapacity = bag ? 50 : 40;
  const postCommit = phase === "restart" || ordinal > 1;
  for (let index = 0; index < visibleCapacity; index += 1) {
    let source = null;
    let itemQuantity = 0;
    let lastUpdate = 0;
    if (bag && index === 0) {
      source = OUTPUT; itemQuantity = quantity; lastUpdate = postCommit ? 2000 : 1000;
    } else if (bag && index === 1) {
      source = MATERIAL; itemQuantity = postCommit ? 3 : 5; lastUpdate = 1100;
    } else if (bag && index === 2) {
      source = UNRELATED; itemQuantity = 7; lastUpdate = 1200;
    }
    slots.push(inventorySlot(index, source, itemQuantity, phase + "." + ordinal,
      tag, lastUpdate));
  }
  const occupied = slots.filter((slot) => slot.occupied).length;
  const filterFacets = occupied > 0
    ? [{ id: "all", label: "全部", order: 0, count: occupied, children: [] }] : [];
  return {
    containerId, capacity, accessibleCapacity: bag ? 50 : 40,
    viewCapacity: bag ? 50 : 40,
    filterKey: "all", pageSizeHint: visibleCapacity, locked: false,
    snapshotSeq: ordinal, containerEpoch: phase === "restart" ? 2 : 1,
    containerVersion: bag ? (postCommit ? 12 : 10) : 5,
    offset: 0, limit: visibleCapacity, slots,
    filterFacets, filterItemCount: occupied,
    setFacets: [], setFilterItemCount: 0,
  };
}

function inventoryResponse(owner, callId, quantity, phase, ordinal) {
  return { type: "panel_resp", domain: "inventory", panel: "crafting",
    panelInstanceId: owner, cmd: "snapshot", callId, success: true, v: 1,
    sessionNonce: "fixture-session-" + phase, snapshots: [
      inventorySnapshot("背包", 50, quantity, phase, ordinal),
      inventorySnapshot("战备箱", 400, 0, phase, ordinal),
    ] };
}
function buildTranscript(phase) {
  const first = phase === "first";
  const owner = first ? "crafting_owner_first" : "crafting_owner_restart";
  let call = 0;
  let inventoryOrdinal = 0;
  const raw = [];
  const inputMinutes = first ? [2, 3, 4, 5, 6, 7, 8] : [19, 20, 21, 22];
  function emit(value) { raw.push(value); }
  function emitInput(target) {
    const minute = inputMinutes.shift();
    const observedAt = "2026-08-03T00:" + String(minute).padStart(2, "0") + ":10.000Z";
    const event = input(target);
    event.observedAt = observedAt;
    event.pageTime = Date.parse(observedAt);
    emit(event);
  }
  function pair(cmd, payload, response) {
    const callId = "craft." + phase + "." + (++call);
    const req = request(owner, callId, cmd, payload);
    emit(message("bridge_send", req));
    emit(message("webview_message", response(callId)));
  }
  function inventoryPair(quantity) {
    const callId = "inventory." + phase + "." + (++call);
    inventoryOrdinal += 1;
    emit(message("bridge_send", inventoryRequest(owner, callId)));
    emit(message("webview_message", inventoryResponse(owner, callId, quantity, phase,
      inventoryOrdinal)));
  }
  emit({ kind: "cdp_endpoint_bound", cdpPort: first ? 19222 : 19223,
    runtimePid: first ? 4100 : 4200 });
  emit({ kind: "observer_ready", url: "https://overlay.local/overlay.html",
    bridgeWrapped: true, uiDataWrapped: true, webviewObserved: true,
    panelState: { panel: "", hidden: true, craftingVisible: false, view: "" } });
  emit(message("webview_message", {
    type: "panel_cmd", cmd: "open", panel: "crafting", panelInstanceId: owner,
    initData: { mode: "runtime", category: CATEGORY, source: "world_crafting_entry",
      debug: false, panelInstanceId: owner },
  }));
  pair("snapshot", { category: CATEGORY, v: 1 },
    (callId) => snapshot(owner, callId, first
      ? { money: 100, kpoints: 5 } : { money: 90, kpoints: 5 }));
  pair("preview", { category: CATEGORY, recipeIndex: RECIPE_INDEX,
    craftCount: CRAFT_COUNT, v: 1 }, (callId) => preview(owner, callId,
    first ? { money: 100, kpoints: 5 } : { money: 90, kpoints: 5 },
    first ? 5 : 3, first ? TOKENS.auto : TOKENS.restartAuto));
  emitInput({ selector: "button[data-workbench-key=\"7\"]",
    attributes: { class: "crafting-recipe-card craftable",
      "data-workbench-key": String(RECIPE_INDEX) }, mutationCapable: true });
  pair("preview", { category: CATEGORY, recipeIndex: RECIPE_INDEX,
    craftCount: CRAFT_COUNT, v: 1 }, (callId) => preview(owner, callId,
    first ? { money: 100, kpoints: 5 } : { money: 90, kpoints: 5 },
    first ? 5 : 3, first ? TOKENS.selected : TOKENS.restartSelected));
  emitInput({ selector: "button.crafting-organizer-btn",
    attributes: { class: "workbench-mode-btn crafting-organizer-btn" } });
  pair("snapshot", { category: CATEGORY, v: 1 },
    (callId) => snapshot(owner, callId, first
      ? { money: 100, kpoints: 5 } : { money: 90, kpoints: 5 }));
  inventoryPair(first ? 2 : 3);
  emitInput({ selector: "button.inventory-return-crafting-btn",
    attributes: { class: "workbench-mode-btn inventory-return-crafting-btn" } });
  pair("snapshot", { category: CATEGORY, v: 1 },
    (callId) => snapshot(owner, callId, first
      ? { money: 100, kpoints: 5 } : { money: 90, kpoints: 5 }));
  pair("preview", { category: CATEGORY, recipeIndex: RECIPE_INDEX,
    craftCount: CRAFT_COUNT, v: 1 }, (callId) => preview(owner, callId,
    first ? { money: 100, kpoints: 5 } : { money: 90, kpoints: 5 },
    first ? 5 : 3, first ? TOKENS.accepted : TOKENS.restartFinal));
  if (first) {
    emitInput({ selector: "button[data-commit-primary]",
      attributes: { class: "crafting-commit-btn", "data-commit-primary": "" },
      mutationCapable: true });
    pair("commit", { category: CATEGORY, expectedCraftTokenRef: TOKENS.accepted, v: 1 },
      (callId) => commit(owner, callId));
    pair("snapshot", { category: CATEGORY, v: 1 },
      (callId) => snapshot(owner, callId, { money: 90, kpoints: 5 }));
    pair("preview", { category: CATEGORY, recipeIndex: RECIPE_INDEX,
      craftCount: CRAFT_COUNT, v: 1 }, (callId) => preview(owner, callId,
      { money: 90, kpoints: 5 }, 3, TOKENS.fresh));
    emitInput({ selector: "button.crafting-organizer-btn",
      attributes: { class: "workbench-mode-btn crafting-organizer-btn" } });
    pair("snapshot", { category: CATEGORY, v: 1 },
      (callId) => snapshot(owner, callId, { money: 90, kpoints: 5 }));
    inventoryPair(3);
    emitInput({ selector: "button.inventory-return-crafting-btn",
      attributes: { class: "workbench-mode-btn inventory-return-crafting-btn" } });
    pair("snapshot", { category: CATEGORY, v: 1 },
      (callId) => snapshot(owner, callId, { money: 90, kpoints: 5 }));
    pair("preview", { category: CATEGORY, recipeIndex: RECIPE_INDEX,
      craftCount: CRAFT_COUNT, v: 1 }, (callId) => preview(owner, callId,
      { money: 90, kpoints: 5 }, 3, TOKENS.final));
  }
  emitInput({ selector: "button[data-header-action=\"close\"]",
    attributes: { "data-header-action": "close" }, mutationCapable: false });
  emit(message("bridge_send", { type: "panel", cmd: "close", panel: "crafting",
    panelInstanceId: owner }));
  emit({ kind: "panel_state_sample", label: "after_close", panelState: {
    panel: "", hidden: true, craftingVisible: false, view: "",
  } });
  emit({ kind: "observer_detached", panelState: {
    panel: "", hidden: true, craftingVisible: false, view: "",
  } });
  let previous = "0".repeat(64);
  const events = raw.map((event, index) => {
    const sealed = nextRecord(previous, index + 1,
      Object.assign({ observedAt: "2026-08-03T00:00:00.000Z" }, event));
    previous = sealed.eventHash;
    return sealed;
  });
  return { schema: TRANSCRIPT_SCHEMA,
    observerId: first ? "crafting-first" : "crafting-restart",
    pageUrl: "https://overlay.local/overlay.html",
    eventCount: events.length, chainHead: previous, events };
}

function session(pid, port, ticks, lifecycle, marker) {
  const value = {
    schema: LauncherObservation.SESSION_SCHEMA,
    apiVersion: LauncherObservation.API_VERSION,
    openedAt: "2026-08-03T00:00:00.000Z",
    pid, httpPort: port, socketPort: port + 100,
    portsFile: "tmp/ports-" + marker + ".json",
    portsFileSha256: marker.repeat(64), portsFileBytes: 64,
    credentialFile: path.join(ROOT, "tmp", "credential-" + marker + ".json"),
    credentialFileSha256: (marker === "a" ? "b" : "c").repeat(64),
    credentialFileBytes: 128,
    credentialTokenSha256: (marker === "a" ? "d" : "e").repeat(64),
    credentialHeader: "X-CF7-Automation-Token",
    processStartUtcTicks: ticks, lifecycleId: lifecycle,
    capabilities: ["legacy.console", "legacy.diagnostic", "legacy.logs", "legacy.save_push",
      "legacy.shutdown", "legacy.status", "legacy.task"],
  };
  value.sessionEvidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function identity(pid, httpPort) {
  return { runtimeMode: "isolated_candidate", installRoot: CANDIDATE_ROOT,
    processPath: path.join(CANDIDATE_ROOT, "runtime",
      "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
    coreSha256: "A".repeat(64),
    buildIdentity: PROJECT_SOURCE_FINGERPRINT.producerInputs.buildIdentityHash,
    payloadClosure: "C".repeat(64), pid, httpPort };
}

function processContract(identityValue, sessionValue, marker) {
  const value = {
    schema: "workbench-live-e2e.launcher-process-contract.v1",
    apiVersion: LauncherObservation.API_VERSION,
    observedAt: "2026-08-03T00:00:00.000Z",
    pid: identityValue.pid, processPath: path.resolve(identityValue.processPath),
    processStartUtcTicks: sessionValue.processStartUtcTicks,
    commandLineSha256: marker.repeat(64),
    argvSha256: (marker === "f" ? "8" : "9").repeat(64),
    projectRoot: ROOT, projectRootArgumentExact: true,
    legacyHttpAutomationArg: true, agentRuntimeAdmission: false,
    trustedSource: "actual_process_command_line+pid_bound_credential",
  };
  value.artifactSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function cdpBinding(port, pid, listenerPid, marker) {
  const pageIdentity = {
    url: "https://overlay.local/overlay.html",
    origin: "https://overlay.local",
    timeOrigin: port, readyState: "complete", userAgent: "fixture-webview2",
  };
  return {
    port, allocatedAt: "2026-08-03T00:00:00.000Z",
    runtimePid: pid, exclusiveBeforeLaunch: true,
    configurationSource: "CF7_WEBVIEW2_ARGS", developerMode: true,
    expectedPageUrl: "https://overlay.local/overlay.html",
    pageIdentity,
    pageIdentitySha256: Evidence.sha256Text(Evidence.canonicalJson(pageIdentity)),
    pageContentSha256: marker.repeat(64), pageContentBytes: 4096,
    pageContentCapturedAt: "2026-08-03T00:00:02.000Z",
    attestation: {
      schema: "workbench-live-e2e.cdp-endpoint-attestation.v1",
      observedAt: "2026-08-03T00:00:01.000Z",
      port, runtimePid: pid, listenerPid, ancestorPids: [listenerPid, pid],
      userDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
      listenerExecutablePath: "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\fixture\\msedgewebview2.exe",
      listenerExecutable: "msedgewebview2.exe",
      commandLineSha256: "1".repeat(64), argvSha256: "2".repeat(64),
      exactPortArgument: true, exactUserDataRoot: true,
    },
  };
}

function emptyBoundary(sessionValue) {
  return LauncherObservation.createTerminalLogBoundary(logSnapshot(sessionValue, []));
}

function logSnapshot(sessionValue, lines, capturedAt) {
  const records = lines.map((line, index) => ({ lineNumber: index + 1, line }));
  const payload = {
    schema: LauncherObservation.LOG_SNAPSHOT_SCHEMA,
    requestedTailLimit: 2000,
    sessionEvidenceSha256: sessionValue.sessionEvidenceSha256,
    lifecycleId: sessionValue.lifecycleId,
    sessionPid: sessionValue.pid,
    sessionProcessStartUtcTicks: sessionValue.processStartUtcTicks,
    total: records.length, oldestLineNumber: 1, records,
  };
  return Object.assign({}, payload, {
    capturedAt: capturedAt || "2026-08-03T00:00:00.000Z",
    tailSha256: Evidence.sha256Text(Evidence.canonicalJson(payload)),
  });
}

function hostLines(transcript, startMinute) {
  const lines = ['[XmlSocket:JSON] {"task":"panel_request","panel":"crafting","source":"world_crafting_entry","category":"'
    + CATEGORY + '"}'];
  let fid = 0;
  transcript.events.filter((event) => event.kind === "bridge_send"
    && event.message && ["crafting", "inventory"].includes(event.message.domain)).forEach((event) => {
    const req = event.message;
    const response = transcript.events.find((candidate) =>
      candidate.kind === "webview_message" && candidate.message
        && candidate.message.type === "panel_resp"
        && candidate.message.callId === req.callId).message;
    fid += 1;
    const authority = req.domain === "crafting" && req.cmd === "commit"
      ? " authorityFieldCount=1 expectedCraftTokenRef="
        + req.payload.expectedCraftTokenRef : "";
    lines.push("[Panel] HandlePanelMessage: task=panel panel=crafting domain=" + req.domain + " cmd="
      + req.cmd + " callId=" + req.callId + " payload=redacted len=100" + authority);
    const taskName = req.domain === "crafting" ? "CraftingTask" : "InventoryTask";
    const routeField = req.domain === "crafting" ? "_craftingTask" : "_inventoryTask";
    lines.push("[Panel] Routing domain=" + req.domain + " cmd=" + req.cmd
      + " to " + taskName + ", " + routeField + "=ok");
    const action = req.domain === "inventory" ? "inventorySnapshot"
      : ({ snapshot: "craftingSnapshot", preview: "craftingPreview",
        commit: "craftingCommit" })[req.cmd];
    lines.push("event=authority_flash_call_bound domain=" + req.domain + " webCallId=" + req.callId
      + " flashCallId=" + fid + " panel=crafting"
      + " panelInstanceId=" + req.panelInstanceId
      + " cmd=" + req.cmd + " action=" + action);
    lines.push("[" + taskName + "] -> Flash: task=cmd cmd=" + action
      + " callId=" + fid + " payload=redacted len=100" + authority);
    const responseAuthority = req.domain === "crafting" && req.cmd === "preview"
      ? " authorityFieldCount=1 craftTokenRef=" + response.craftTokenRef : "";
    lines.push("[XmlSocket:JSON] task=" + (req.domain === "crafting"
      ? "crafting_response" : "inventory_response") + " cmd=" + req.cmd + " callId=" + fid
      + " success=true payload=redacted len=100" + responseAuthority);
  });
  lines.push("[Panel] HandlePanelMessage: task=panel panel=crafting domain=other"
    + " cmd=close callId=other payload=redacted len=100");
  const close = transcript.events.find((event) => event.kind === "bridge_send"
    && event.message && event.message.cmd === "close");
  lines.push("event=panel_exact_close_completed panel=crafting panelInstanceId="
    + close.message.panelInstanceId);
  return lines.map((line, index) => {
    if (line.startsWith("event=panel_exact_close_completed")) {
      return (Number(startMinute) < 10 ? "08:09:30.000 " : "08:22:35.000 ") + line;
    }
    const seconds = Number(startMinute) * 60 + index * 7;
    const minute = Math.floor(seconds / 60);
    const second = seconds % 60;
    return "08:" + String(minute).padStart(2, "0") + ":"
      + String(second).padStart(2, "0") + ".000 " + line;
  });
}

function artifactSet(slot, appDataRoot, jsonHash, solHash, capturedAt) {
  const artifacts = [];
  if (solHash) artifacts.push({
    kind: "sol",
    locator: "appdata:Macromedia/Flash Player/#SharedObjects/FIXTURE/localhost/"
      + slot + ".sol",
    sha256: solHash, bytes: 32, regularFile: true, exactRealPath: true,
  });
  artifacts.push({ kind: "json", locator: "root:saves/" + slot + ".json",
    sha256: jsonHash, bytes: 1024, regularFile: true, exactRealPath: true });
  artifacts.sort((left, right) => left.locator.localeCompare(right.locator));
  const payload = { schema: CloneGuard.ARTIFACT_SET_SCHEMA,
    slot, appDataRoot, artifacts };
  return Object.assign({}, payload, {
    capturedAt: capturedAt || "2026-08-03T00:00:00.000Z",
    setSha256: Evidence.sha256Text(Evidence.canonicalJson(payload)),
  });
}

function stableArtifactSet(set, marker) {
  const payload = {
    schema: "workbench-live-e2e.stable-slot-artifact-set.v1",
    apiVersion: CloneGuard.API_VERSION,
    stableMs: 2000, samples: 3,
    observedAt: "2026-08-03T00:" + marker + ":00.000Z",
    set: clone(set),
  };
  return Object.assign({}, payload, {
    evidenceSha256: Evidence.sha256Text(Evidence.canonicalJson(payload)),
  });
}

function disk(marker) {
  return { schema: "workbench-live-e2e.disk-save-evidence.v1",
    slot: TARGET_SLOT, path: path.join(ROOT, "saves", TARGET_SLOT + ".json"),
    sha256: marker.repeat(64), bytes: 1024, textCharacters: 990,
    capturedAt: "2026-08-03T00:15:00.000Z" };
}

function sourceClosure() {
  const fingerprint = clone(PROJECT_SOURCE_FINGERPRINT);
  fingerprint.root = ROOT;
  fingerprint.producerInputs.root = ROOT;
  delete fingerprint.producerInputs.inputsSha256;
  fingerprint.producerInputs.inputsSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(fingerprint.producerInputs));
  fingerprint.capturedAt = "2026-08-03T00:00:00.000Z";
  const unsigned = { schema: fingerprint.schema, capturedAt: fingerprint.capturedAt,
    root: fingerprint.root, head: fingerprint.head, files: fingerprint.files,
    producerInputs: fingerprint.producerInputs,
    as2AlgorithmContract: fingerprint.as2AlgorithmContract };
  fingerprint.fingerprintSha256 = Evidence.sha256Text(Evidence.canonicalJson(unsigned));
  const records = SourceContract.REQUIRED_SOURCE_PHASES.map((phase, index) => ({
    phase,
    observedAt: "2026-08-03T00:" + String(index).padStart(2, "0") + ":00.000Z",
    fingerprint: clone(fingerprint),
  }));
  return SourceContract.sealSourceClosure(records);
}

function loadedProduction(closure, binding, identityValue, lifecycle) {
  const expected = SourceContract.webFiles(closure);
  const scriptRecords = SourceContract.scriptFiles(closure);
  const styleRecords = SourceContract.styleFiles(closure);
  const scriptUrls = scriptRecords.map((entry) => "https://overlay.local/"
    + entry.locator.slice("root:launcher/web/".length));
  const styleUrls = styleRecords.map((entry) => "https://overlay.local/"
    + entry.locator.slice("root:launcher/web/".length));
  const frameId = "fixture-main-frame";
  const contextId = lifecycle === "first" ? 5101 : 5201;
  const inlineHash = (lifecycle === "first" ? "e" : "f").repeat(64);
  const rawScripts = [{ url: "https://overlay.local/overlay.html",
    origin: "https://overlay.local", scriptId: lifecycle + "-inline",
    sourceSha256: inlineHash, sourceBytes: 256 }]
    .concat(scriptRecords.map((entry, index) => ({ url: scriptUrls[index],
      origin: "https://overlay.local", scriptId: lifecycle + "-script-" + index,
      sourceSha256: entry.sha256, sourceBytes: entry.bytes })));
  const toolScriptPlan = ["identity", "install_new_document",
    "install_current_document", "health", "detach"].map((label, index) => {
    const url = "cf7-evidence://crafting/" + encodeURIComponent("crafting-" + lifecycle)
      + "/" + String(index + 1).padStart(4, "0") + "-" + label + ".js";
    return { sequence: index + 1, label, url,
      sha256: (lifecycle === "first" ? (index + 10).toString(16)
        : (index + 20).toString(16)).padStart(2, "0").repeat(32), bytes: 300 + index };
  });
  rawScripts.push(...toolScriptPlan.filter((entry) => entry.label !== "install_new_document")
    .map((entry, index) => ({ url: entry.url, origin: "null",
      scriptId: lifecycle + "-tool-" + index,
      sourceSha256: entry.sha256, sourceBytes: entry.bytes })));
  const contextAuxData = { frameId, isDefault: true, type: "default" };
  const rawContext = { id: contextId, origin: "https://overlay.local", name: "",
    uniqueId: lifecycle + "-context", auxData: clone(contextAuxData) };
  const scriptOccurrences = rawScripts.map((entry, index) => Object.assign({
    occurrence: index + 1, executionContextId: contextId,
    startLine: 0, startColumn: 0, endLine: 1, endColumn: 0, sourceMapUrl: "",
    contextOrigin: "https://overlay.local", frameId,
    rawExecutionContextAuxData: clone(contextAuxData),
    rawParams: { scriptId: entry.scriptId, url: entry.url, executionContextId: contextId,
      startLine: 0, startColumn: 0, endLine: 1, endColumn: 0, sourceMapURL: "",
      executionContextAuxData: clone(contextAuxData) },
    sourceMethod: "Debugger.getScriptSource",
  }, entry));
  const executionContextOccurrences = [{ occurrence: 1, executionContextId: contextId,
    origin: "https://overlay.local", name: "", uniqueId: lifecycle + "-context",
    frameId, rawAuxData: clone(contextAuxData), rawContext: clone(rawContext) }];
  const staticResources = SourceContract.expectedStaticResourceSet(closure);
  const conditionalResources = SourceContract.cssConditionalResourceSet(closure);
  const fontEnvironment = clone(PROJECT_FONT_ENVIRONMENT);
  const fontResources = fontEnvironment.installed.map((entry) => {
    const extension = path.posix.extname(new URL(entry.url).pathname).toLowerCase();
    return { url: entry.url, resourceType: "Font", origin: "https://cfn-fonts.local",
      mimeType: extension === ".woff2" ? "font/woff2"
        : extension === ".woff" ? "font/woff" : "font/ttf",
      sha256: entry.sha256, bytes: entry.bytes };
  });
  const iconProjection = clone(PROJECT_ICON_PROJECTION);
  const resourceOccurrences = staticResources.concat(conditionalResources, fontResources,
    iconProjection.resources).map((entry, index) => {
    const byteBound = Object.prototype.hasOwnProperty.call(entry, "sha256");
    return { occurrence: index + 1, frameOccurrence: 1,
      resourceOccurrence: index + 1, frameId,
      frameUrl: "https://overlay.local/overlay.html", frameOrigin: "https://overlay.local",
      url: entry.url, origin: entry.origin, resourceType: entry.resourceType,
      mimeType: entry.mimeType,
      resource: { url: entry.url, type: entry.resourceType, mimeType: entry.mimeType },
      sourceMethod: byteBound ? "Page.getResourceContent" : null,
      sourceSha256: byteBound ? entry.sha256 : null,
      sourceBytes: byteBound ? entry.bytes : null, sourceError: null };
  });
  const styleOccurrences = resourceOccurrences.filter((entry) =>
    entry.resourceType === "Stylesheet").map((entry) => clone(entry));
  const pageExpected = expected.find((entry) => entry.role === "page");
  const value = { schema: SourceContract.LOADED_SCHEMA, lifecycle,
    capturePhase: "post_observer_detach",
    capturedAt: lifecycle === "first" ? "2026-08-03T00:15:30.000Z"
      : "2026-08-03T00:22:57.000Z",
    runtimePid: identityValue.pid, runId: "fixture-crafting-v4",
    mainFrameId: frameId,
    sourceFingerprintSha256: closure.records[0].fingerprint.fingerprintSha256,
    sourceBindingSha256: binding.bindingSha256,
    page: { role: pageExpected.role, locator: pageExpected.locator,
      url: "https://overlay.local/overlay.html", sourceMethod: "Page.getResourceContent",
      sha256: pageExpected.sha256, bytes: pageExpected.bytes },
    scripts: scriptRecords.map((entry, index) => ({ role: entry.role, locator: entry.locator,
      url: scriptUrls[index], occurrence: index + 2,
      scriptId: lifecycle + "-script-" + index, executionContextId: contextId,
      frameId, contextOrigin: "https://overlay.local", sourceMethod: "Debugger.getScriptSource",
      sha256: entry.sha256, bytes: entry.bytes })),
    styles: styleRecords.map((entry, index) => ({ role: entry.role, locator: entry.locator,
      url: styleUrls[index], resourceOccurrence: styleOccurrences[index].occurrence, frameId,
      sourceMethod: "Page.getResourceContent", sha256: entry.sha256, bytes: entry.bytes })),
    scriptOccurrences, executionContextOccurrences, toolScriptPlan,
    inlineScripts: [{ occurrence: 1, scriptId: lifecycle + "-inline",
      executionContextId: contextId, frameId, contextOrigin: "https://overlay.local",
      sourceMethod: "Debugger.getScriptSource", sha256: inlineHash, bytes: 256 }],
    resourceOccurrences, fontEnvironment, iconProjection,
    styleOccurrences,
    relevantScriptUrls: scriptUrls, relevantStyleUrls: styleUrls };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function residue(identityValue, sessionValue, marker) {
  const value = {
    schema: LauncherObservation.RESIDUE_SCHEMA,
    apiVersion: LauncherObservation.API_VERSION,
    observedAt: marker === "a" ? "2026-08-03T00:17:30.000Z"
      : "2026-08-03T00:23:10.000Z",
    expectedPid: identityValue.pid,
    expectedProcessPath: path.resolve(identityValue.processPath),
    pidAbsent: true, candidateProcessAbsent: true, observedLauncherPids: [],
    ports: [identityValue.httpPort, identityValue.httpPort + 100,
      marker === "a" ? 19222 : 19223].map((port) => ({ port, open: false })),
    portsFile: sessionValue.portsFile, portsFileAbsent: true,
    credentialFile: sessionValue.credentialFile, credentialFileAbsent: true,
    stableSamples: 3,
  };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function buildControl(firstContract, firstTranscript, restartTranscript) {
  CAPTURE_BYTES.forEach((bytes, index) => {
    fs.writeFileSync(path.join(CAPTURE_DIR,
      "fixture-" + REQUIRED_CONTROL_STEPS[index] + ".png"), bytes);
  });
  const decision = {
    schema: AUTHORIZATION_SCHEMA,
    decisionId: "fixture-crafting-commit",
    issuedAt: "2026-08-03T00:00:00.000Z",
    source: "cli_explicit_flag", oneShot: true,
    allowedStep: "commit_recipe",
    scope: { journey: "crafting-commit-v4", slot: TARGET_SLOT,
      category: CATEGORY, recipeIndex: RECIPE_INDEX, craftCount: CRAFT_COUNT,
      operation: "craft", candidateRoot: CANDIDATE_ROOT },
  };
  const decisionSha = Evidence.sha256Text(Evidence.canonicalJson(decision));
  const minuteByStep = [1, 2, 3, 4, 5, 6, 7, 8, 10, 16, 18, 19, 20, 21, 22];
  const requests = REQUIRED_CONTROL_STEPS.map((step, index) => Object.assign({
    schema: CONTROL_REQUEST_SCHEMA, runId: "fixture-crafting-v4",
    requestId: "fixture-" + step, step,
    issuedAt: "2026-08-03T00:" + String(minuteByStep[index]).padStart(2, "0") + ":00.000Z",
    expiresAt: "2026-08-03T01:00:00.000Z",
    allowedTransports: ["codex_computer_use"],
    requiresCommitAuthorization: step === "commit_recipe",
    requiresCaptureSha256: true,
    authorizationRef: step === "commit_recipe"
      ? { decisionId: decision.decisionId, decisionSha256: decisionSha } : null,
  }, expectedControlIntent(step, { recipeIndex: RECIPE_INDEX })));
  const firstInputs = firstTranscript.events.filter((entry) => entry.kind === "dom_input");
  const restartInputs = restartTranscript.events.filter((entry) => entry.kind === "dom_input");
  const domByStep = new Map([
    ["select_recipe", [firstTranscript, firstInputs[0]]],
    ["capture_inventory_before", [firstTranscript, firstInputs[1]]],
    ["return_from_inventory_before", [firstTranscript, firstInputs[2]]],
    ["commit_recipe", [firstTranscript, firstInputs[3]]],
    ["capture_inventory_after", [firstTranscript, firstInputs[4]]],
    ["return_from_inventory_after", [firstTranscript, firstInputs[5]]],
    ["close_first_crafting", [firstTranscript, firstInputs[6]]],
    ["restart_select_recipe", [restartTranscript, restartInputs[0]]],
    ["restart_capture_inventory", [restartTranscript, restartInputs[1]]],
    ["restart_return_from_inventory", [restartTranscript, restartInputs[2]]],
    ["restart_close_crafting", [restartTranscript, restartInputs[3]]],
  ]);
  function nativeInputEvidence(request, minute) {
    return { kind: "native_input", eventRef: null, eventType: "click", isTrusted: true,
      selector: request.selectors[0], tagName: "NATIVE", visible: true, enabled: true,
      viewport: { width: 1280, height: 720, scrollX: 0, scrollY: 0 },
      rect: { left: 0, top: 0, right: 1280, bottom: 720, width: 1280, height: 720 },
      clientPoint: { x: 640, y: 360 }, hitTargetMatches: true,
      key: null, button: 0, repeat: false,
      observedAt: "2026-08-03T00:" + String(minute).padStart(2, "0") + ":10.000Z" };
  }
  const acks = requests.map((request, index) => {
    const requestBytes = Buffer.from(JSON.stringify(request, null, 2) + "\n", "utf8");
    fs.writeFileSync(path.join(REQUEST_DIR, request.requestId + ".json"), requestBytes);
    const capture = CAPTURES[index];
    const providerRelative = "control/provider-receipts/" + request.requestId + ".json";
    const domBinding = domByStep.get(request.step);
    const inputEvidence = domBinding
      ? domInputEvidence(domBinding[0].observerId, domBinding[1])
      : nativeInputEvidence(request, minuteByStep[index]);
    const minute = String(minuteByStep[index]).padStart(2, "0");
    let captureObservedAt = "2026-08-03T00:" + minute + ":20.000Z";
    let providerCompletedAt = "2026-08-03T00:" + minute + ":29.000Z";
    let ackCompletedAt = "2026-08-03T00:" + minute + ":30.000Z";
    if (request.step === "close_first_crafting") {
      captureObservedAt = "2026-08-03T00:09:40.000Z";
      providerCompletedAt = "2026-08-03T00:09:54.000Z";
      ackCompletedAt = "2026-08-03T00:09:55.000Z";
    } else if (request.step === "safe_exit") {
      captureObservedAt = "2026-08-03T00:13:10.000Z";
      providerCompletedAt = "2026-08-03T00:13:29.000Z";
      ackCompletedAt = "2026-08-03T00:13:30.000Z";
    } else if (request.step === "restart_close_crafting") {
      captureObservedAt = "2026-08-03T00:22:40.000Z";
      providerCompletedAt = "2026-08-03T00:22:54.000Z";
      ackCompletedAt = "2026-08-03T00:22:55.000Z";
    }
    const captureFileModifiedAt = new Date(Date.parse(captureObservedAt) + 1000).toISOString();
    const capturePath = path.join(RUN_DIR, capture.relativePath.replace(/\//g, path.sep));
    const modifiedSeconds = Date.parse(captureFileModifiedAt) / 1000;
    fs.utimesSync(capturePath, modifiedSeconds, modifiedSeconds);
    const captureEventRelative = "control/capture-events/" + request.requestId + ".json";
    const captureEvent = { schema: PROVIDER_CAPTURE_EVENT_SCHEMA,
      runId: request.runId, requestId: request.requestId, step: request.step,
      transport: "codex_computer_use", issuer: "codex_computer_use",
      toolResultSource: "codex_computer_use_tool_result", providerEventId: null,
      requestSha256: Evidence.sha256Bytes(requestBytes), captureArtifact: capture.relativePath,
      capturedAt: captureObservedAt, fileModifiedAt: captureFileModifiedAt,
      captureBytes: capture.bytes, captureSha256: capture.sha256,
      captureWidth: 320, captureHeight: 180,
      captureSemanticContentIndependentlyVerified: false };
    captureEvent.providerEventId = expectedProviderCaptureEventId(captureEvent);
    captureEvent.eventSha256 = Evidence.sha256Text(Evidence.canonicalJson(captureEvent));
    const captureEventBytes = Buffer.from(JSON.stringify(captureEvent, null, 2) + "\n", "utf8");
    fs.writeFileSync(path.join(CAPTURE_EVENT_DIR, request.requestId + ".json"), captureEventBytes);
    const providerReceipt = { schema: PROVIDER_RECEIPT_SCHEMA,
      runId: request.runId, requestId: request.requestId, step: request.step,
      transport: "codex_computer_use", issuer: "codex_computer_use",
      toolResultSource: "codex_computer_use_tool_result",
      requestSha256: Evidence.sha256Bytes(requestBytes),
      providerOperationId: null,
      action: request.step, result: "completed",
      startedAt: "2026-08-03T00:" + minute + ":05.000Z",
      inputEvidence, completedAt: providerCompletedAt,
      ownedArtifact: providerRelative,
      captureEventRef: { artifact: captureEventRelative,
        sha256: Evidence.sha256Bytes(captureEventBytes),
        eventSha256: captureEvent.eventSha256 } };
    providerReceipt.providerOperationId = expectedProviderOperationId(providerReceipt);
    providerReceipt.receiptSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(providerReceipt));
    const providerBytes = Buffer.from(JSON.stringify(providerReceipt, null, 2) + "\n", "utf8");
    fs.writeFileSync(path.join(PROVIDER_RECEIPT_DIR, request.requestId + ".json"), providerBytes);
    const ack = { schema: CONTROL_ACK_SCHEMA, runId: request.runId,
      requestId: request.requestId, step: request.step,
      transport: "codex_computer_use", result: "completed",
      completedAt: ackCompletedAt,
      captureSha256: capture.sha256,
      capture: clone(capture),
      authorizationDecisionId: request.requiresCommitAuthorization
        ? decision.decisionId : null,
      providerReceipt: { artifact: "control/provider-receipts/" + request.requestId + ".json",
        sha256: Evidence.sha256Bytes(providerBytes) },
      details: {} };
    fs.writeFileSync(path.join(ACK_DIR, request.requestId + ".json"),
      JSON.stringify(ack, null, 2) + "\n");
    return ack;
  });
  const artifact = {
    schema: "workbench-live-e2e.crafting.launch-capability.v3",
    processContractSha256: firstContract.artifactSha256,
    commandLineSha256: firstContract.commandLineSha256,
    argvSha256: firstContract.argvSha256,
    launchMode: "legacy_http_automation", agentRuntimeAdmission: false,
    legacyHttpAutomationArg: true,
    credentialCapabilitiesSha256: Evidence.sha256Text(
      Evidence.canonicalJson([
        "legacy.console", "legacy.diagnostic", "legacy.logs", "legacy.save_push",
        "legacy.shutdown", "legacy.status", "legacy.task",
      ])),
  };
  const commitInputIndex = firstTranscript.events.findIndex((event) => event.kind === "dom_input"
    && event.target && event.target.attributes
    && Object.prototype.hasOwnProperty.call(event.target.attributes, "data-commit-primary"));
  const preCommitEvents = firstTranscript.events.slice(0, commitInputIndex).map(clone);
  const preCommitTranscript = Object.assign({}, firstTranscript, {
    events: preCommitEvents, eventCount: preCommitEvents.length,
    chainHead: preCommitEvents[preCommitEvents.length - 1].eventHash,
  });
  const admission = Protocol.verifyPreCommitAuthority(preCommitTranscript,
    { category: CATEGORY, recipeIndex: RECIPE_INDEX, craftCount: CRAFT_COUNT });
  return {
    selectedTransport: "codex_computer_use", fallbackAllowed: true,
    capability: { schema: CAPABILITY_SCHEMA, available: false,
      source: "authenticated_process_contract", artifact,
      artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(artifact)) },
    authorization: decision, authorizationSha256: decisionSha,
    preCommitAdmission: { status: "admitted", selector: admission.selector,
      acceptedCraftTokenRef: admission.acceptedPreview.craftTokenRef,
      inventoryCallId: admission.inventoryPair.request.callId,
      delivery: admission.plan.delivery },
    requests, acks,
  };
}

function publicIdentity(value) {
  return RuntimeGuard.publicCandidateIdentity(value);
}

function candidateProducerEvidence(fingerprint, identityValue) {
  const value = {
    schema: SourceContract.CANDIDATE_PRODUCER_SCHEMA,
    candidateRoot: CANDIDATE_ROOT,
    metadata: { locator: "candidate:runtime-build-metadata.v2.json",
      sha256: "D".repeat(64), bytes: 1024 },
    manifest: { locator: "candidate:runtime/cf7-runtime-manifest.tsv",
      sha256: "E".repeat(64), bytes: 2048 },
    builderLabel: "fixture-offline-producer",
    createdAtUtc: "2026-08-03T00:00:00.000Z",
    producerInputsSha256: fingerprint.producerInputs.inputsSha256,
    artifactSourceHash: fingerprint.producerInputs.domains.artifactSource.hash,
    producerRecipeHash: fingerprint.producerInputs.domains.producerRecipe.hash,
    toolchainLockHash: fingerprint.producerInputs.domains.toolchainLock.hash,
    buildIdentityHash: identityValue.buildIdentity,
    payloadClosureHash: identityValue.payloadClosure,
    payloadFileCount: 2,
    processImage: { locator: "candidate:runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe",
      sha256: "F".repeat(64), bytes: 4096 },
    coreLibrary: { locator: "candidate:runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll",
      sha256: identityValue.coreSha256, bytes: 8192 },
  };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function buildValidBundle() {
  const firstTranscript = buildTranscript("first");
  const restartTranscript = buildTranscript("restart");
  const firstIdentity = identity(4100, 18080);
  const restartIdentity = identity(4200, 18081);
  const firstSession = session(4100, 18080, "638898000000000001",
    "lifecycle_fixture_first", "a");
  const restartSession = session(4200, 18081, "638898000000000002",
    "lifecycle_fixture_restart", "b");
  const firstContract = processContract(firstIdentity, firstSession, "f");
  const restartContract = processContract(restartIdentity, restartSession, "7");
  const closure = sourceClosure();
  const candidateProducer = candidateProducerEvidence(
    closure.records[0].fingerprint, firstIdentity);
  const binding = SourceContract.bindSourceClosure(closure.records[0].fingerprint,
    firstIdentity, "fixture-crafting-v4", CANDIDATE_ROOT, candidateProducer);
  const firstBoundary = emptyBoundary(firstSession);
  const restartBoundary = emptyBoundary(restartSession);
  const firstLines = hostLines(firstTranscript, 1);
  firstLines.push("08:11:00.000 [Save] sv:1", "08:12:00.000 [Save] sv:2",
    "08:13:00.000 [Save] archive");
  const firstLog = logSnapshot(firstSession, firstLines,
    "2026-08-03T00:14:00.000Z");
  const restartLog = logSnapshot(restartSession, hostLines(restartTranscript, 18),
    "2026-08-03T00:22:40.000Z");
  const appData = path.join(ROOT, "fixture-appdata");
  const seed = artifactSet(SEED_SLOT, appData, "1".repeat(64), "2".repeat(64));
  const targetBefore = artifactSet(TARGET_SLOT, appData, "9".repeat(64), "a".repeat(64));
  const prepared = artifactSet(TARGET_SLOT, appData, "3".repeat(64), null);
  const committed = artifactSet(TARGET_SLOT, appData, "6".repeat(64), "7".repeat(64),
    "2026-08-03T00:15:00.000Z");
  const preparationBase = {
    schema: CloneGuard.PREPARATION_SCHEMA, apiVersion: CloneGuard.API_VERSION,
    root: ROOT, runDir: RUN_DIR, seedSlot: SEED_SLOT, targetSlot: TARGET_SLOT,
    transformId: "crafting-clone-lastSaved-v3",
    seedBegin: seed, seedAfterPrepare: clone(seed),
    targetBefore, targetPrepared: prepared, backups: [],
  };
  const preparation = Object.assign({}, preparationBase, {
    preparationSha256: Evidence.sha256Text(Evidence.canonicalJson(preparationBase)),
  });
  const committedDisk = disk("6");
  const archive = {
    schema: LauncherObservation.ARCHIVE_SCHEMA,
    apiVersion: LauncherObservation.API_VERSION,
    boundary: firstBoundary, finalSnapshotSha256: firstLog.tailSha256,
    requiredOrder: ["sv1", "sv2", "archive"],
    positions: { sv1: { lineNumber: firstLog.total - 2, offset: 0 },
      sv2: { lineNumber: firstLog.total - 1, offset: 0 },
      archive: { lineNumber: firstLog.total, offset: 0 } },
    archive: { lineNumber: firstLog.total, offset: 0,
      characters: committedDisk.textCharacters, path: committedDisk.path },
    disk: clone(committedDisk),
  };
  archive.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(archive));
  const release = {
    schema: CloneGuard.RELEASE_SCHEMA, apiVersion: CloneGuard.API_VERSION,
    releasedAt: "2026-08-03T00:20:00.000Z",
    seedEnd: clone(seed), targetEnd: clone(committed),
    backupsVerified: true, preparedRecoveryRecordSha256: "8".repeat(64),
    lockRelease: { lockFileAbsent: true, terminalPrivateRelease: true },
    recoveryClear: { recoveryFileAbsent: true },
  };
  release.releaseSha256 = Evidence.sha256Text(Evidence.canonicalJson(release));
  const runtime = {
    expectedIdentity: publicIdentity(firstIdentity),
    trustedCdpExpectations: {
      expectedPageUrl: "https://overlay.local/overlay.html",
      expectedPageOrigin: "https://overlay.local",
      expectedUserDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
      expectedListenerExecutableName: "msedgewebview2.exe",
    },
    first: { identity: firstIdentity, attemptId: "attempt_fixture_first",
      sessionEvidence: firstSession, processContract: firstContract,
      cdpBinding: cdpBinding(19222, 4100, 5100, "a"),
      startBoundary: firstBoundary, finalLogSnapshot: firstLog,
      loadedProduction: loadedProduction(closure, binding, firstIdentity, "first") },
    restart: { identity: restartIdentity, attemptId: "attempt_fixture_restart",
      sessionEvidence: restartSession, processContract: restartContract,
      cdpBinding: cdpBinding(19223, 4200, 5200, "b"),
      startBoundary: restartBoundary, finalLogSnapshot: restartLog,
      loadedProduction: loadedProduction(closure, binding, restartIdentity, "restart"),
      shutdownEvidence: null },
  };
  runtime.restart.shutdownEvidence = {
    schema: "workbench-live-e2e.crafting.authenticated-shutdown.v1",
    requestedAt: "2026-08-03T00:23:00.000Z",
    completedAt: "2026-08-03T00:23:01.000Z", pid: restartIdentity.pid,
    sessionEvidenceSha256: restartSession.sessionEvidenceSha256,
    response: { success: true, ok: true, action: "shutdown" },
  };
  runtime.restart.shutdownEvidence.evidenceSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(runtime.restart.shutdownEvidence));
  const persistence = {
    preparation,
    stability: { targetPrepared: stableArtifactSet(prepared, "05"),
      afterCommit: stableArtifactSet(committed, "15"),
      afterRestart: stableArtifactSet(committed, "19") },
    afterCommit: committed, afterRestart: clone(committed), seedEnd: clone(seed),
    diskAfterCommit: committedDisk, diskAfterRestart: clone(committedDisk),
    archiveEvidence: archive, release,
  };
  const firstHost = { schema: "workbench-live-e2e.crafting.host-as2-tail.v3",
    label: "first", sessionEvidence: firstSession, startBoundary: firstBoundary,
    finalLogSnapshot: firstLog,
    records: LauncherObservation.recordsAfterTerminalBoundary(firstBoundary, firstLog) };
  const restartHost = { schema: "workbench-live-e2e.crafting.host-as2-tail.v3",
    label: "restart", sessionEvidence: restartSession, startBoundary: restartBoundary,
    finalLogSnapshot: restartLog,
    records: LauncherObservation.recordsAfterTerminalBoundary(restartBoundary, restartLog) };
  return {
    schema: BUNDLE_SCHEMA, apiVersion: API_VERSION,
    status: "captured_unverified", deployment: "NOT_DEPLOYED",
    evidenceClass: "offline_fixture",
    evidenceMode: "offline_fixture",
    fixtureProvenance: { schema: "workbench-live-e2e.crafting.fixture-provenance.v1",
      generator: "fixtures/valid-bundle.js", synthetic: true, liveCapture: false },
    safeExitUiJourneyVerified: false, exitMethod: "offline_fixture_simulation",
    generatedAt: "2026-08-03T00:00:00.000Z",
    runId: "fixture-crafting-v4", root: ROOT, runDir: RUN_DIR,
    seedSlot: SEED_SLOT, targetSlot: TARGET_SLOT, candidateRoot: CANDIDATE_ROOT,
    allowIsolatedCommit: true, allowCodexCuFallback: true,
    runtime, control: buildControl(firstContract, firstTranscript, restartTranscript),
    transcripts: { first: firstTranscript, restart: restartTranscript },
    hostArtifacts: { first: firstHost, restart: restartHost },
    sourceClosure: closure, sourceBinding: binding, candidateProducer,
    persistence,
    residue: { afterSafeExit: residue(firstIdentity, firstSession, "a"),
      final: residue(restartIdentity, restartSession, "b") },
    moduleJournal: { manifest: null, artifact: null },
  };
}

module.exports = {
  CATEGORY, CRAFT_COUNT, OUTPUT, RECIPE_INDEX, ROOT, RUN_DIR,
  SEED_SLOT, TARGET_SLOT, TOKENS, buildTranscript, buildValidBundle,
  visiblePng,
};
