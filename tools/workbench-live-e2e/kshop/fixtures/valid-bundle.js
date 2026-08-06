"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const CloneSaveGuard = require("../../lib/clone-save-guard");
const Evidence = require("../../lib/evidence-artifact");
const LauncherObservation = require("../../lib/launcher-observation");
const {
  ACK_SCHEMA,
  CONTROL_SCHEMA,
  PROVIDER_EVENT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  TOOL_SCHEMA,
  buildRawBundleManifest,
  canonicalJson,
  chooseCatalogSelection,
  sealEvents,
  sha256Bytes,
  sha256Text,
  tokenRef,
} = require("../common");
const { createSolidPngForFixture, decodePng } = require("../png-contract");
const { REQUIRED_CONTROL_STEPS, SHOP_ACTIONS } = require("../evidence-verifier");
const { providerEventSha256 } = require("../control-channel");
const { captureSaveUniverse } = require("../generic-opener");
const ProductionClosure = require("../production-closure");

const PRODUCTION_ROOT = path.resolve(__dirname, "..", "..", "..", "..");
const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-kshop-fixture-"));
const RUN_DIR = path.join(ROOT, "tmp", "workbench-live-e2e", "kshop", "fixture");
const APP_DATA = path.join(ROOT, "fixture-appdata");
const SLOT = "cf7_agent_fixture_kshop";
const SEED_SLOT = "cf7_agent_fixture_seed";
const COLLATERAL_SLOT = "cf7_agent_fixture_collateral";
const RUN_ID = "fixture-kshop-a3-v2";
const OBSERVER_ID = "fixture-kshop-observer-v2";
const CANDIDATE_ROOT = path.join(ROOT, "tmp", "runtime-candidates", "v2", "fixture-candidate");
const PANEL_ONE = "panel_fixture_kshop_1";
const PANEL_TWO = "panel_fixture_kshop_2";
const PURCHASED_TOKEN = "fixture-purchased-token";
const CHECKOUT_TOKEN = "fixture-checkout-token";
const FIXED_TIME = "2026-08-03T00:00:00.000Z";

const FIXTURE_MATERIAL = Object.freeze({ catalogIndex: 3,
  itemName: "fixture.internal.material-crystal", displayName: "夹具材料晶体",
  icon: "觉醒晶体", shopType: "fixture-material-shop", majorType: "收集品",
  subType: "材料", unitPrice: 2, maxQuantity: 999999 });
const FIXTURE_ITEM = Object.freeze({ catalogIndex: 37, itemName: "fixture.internal.armor",
  displayName: "夹具测试护甲", icon: "手枪通用弹药", shopType: "fixture-equipment-shop",
  majorType: "防具", subType: "上装装备", unitPrice: 1200, maxQuantity: 1 });
const FIXTURE_CATALOG_ITEMS = Object.freeze([FIXTURE_MATERIAL, FIXTURE_ITEM]);

function clone(value) { return JSON.parse(JSON.stringify(value)); }

function safeRemoveFixture() {
  const expectedParent = path.resolve(os.tmpdir());
  if (path.dirname(ROOT) !== expectedParent || !path.basename(ROOT).startsWith("cf7-kshop-fixture-")) {
    return;
  }
  try { fs.rmSync(ROOT, { recursive: true, force: true }); } catch (_error) {}
}
process.once("exit", safeRemoveFixture);

function produceModuleAdmission() {
  const bootstrap = path.join(PRODUCTION_ROOT, "tools", "workbench-live-e2e", "kshop", "bootstrap.js");
  const result = childProcess.spawnSync(process.execPath,
    [bootstrap, "--emit-offline-admission-fixture"], {
      cwd: PRODUCTION_ROOT,
      encoding: "utf8",
      windowsHide: true,
      maxBuffer: 32 * 1024 * 1024,
      env: Object.assign({}, process.env),
    });
  if (result.status !== 0) {
    throw new Error("fixture module admission failed: " + String(result.stderr || result.stdout));
  }
  return JSON.parse(String(result.stdout || ""));
}

fs.mkdirSync(RUN_DIR, { recursive: true });
fs.mkdirSync(path.join(ROOT, "saves"), { recursive: true });
fs.mkdirSync(APP_DATA, { recursive: true });
let moduleAdmissionCache = null;

function moduleAdmission() {
  if (!moduleAdmissionCache) moduleAdmissionCache = produceModuleAdmission();
  return clone(moduleAdmissionCache);
}

const CAPTURE_DIR = path.join(RUN_DIR, "control", "captures");
fs.mkdirSync(CAPTURE_DIR, { recursive: true });
const CAPTURES = ["fixture-safe_exit.png", "fixture-exit_confirm.png"].map((name, index) => {
  const bytes = createSolidPngForFixture(320, 180,
    index === 0 ? [12, 45, 88, 255] : [88, 45, 12, 255]);
  const filePath = path.join(CAPTURE_DIR, name);
  fs.writeFileSync(filePath, bytes, { flag: "wx" });
  return { relativePath: "control/captures/" + name, sha256: sha256Bytes(bytes),
    bytes: bytes.length, mediaType: "image/png", decoded: decodePng(bytes, "fixture_capture") };
});

function ownedSolPath(slot) {
  return path.join(APP_DATA, "Macromedia", "Flash Player", "#SharedObjects", "FIXTURE",
    CloneSaveGuard.solOwnershipSuffix(ROOT, slot));
}

function writeOwnedSol(slot, bytes) {
  const filePath = ownedSolPath(slot);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, bytes);
  return filePath;
}

const seedJsonBytes = Buffer.from(JSON.stringify({ version: "3.0", slot: SEED_SLOT,
  inventory: { seed: true } }), "utf8");
fs.writeFileSync(path.join(ROOT, "saves", SEED_SLOT + ".json"), seedJsonBytes);
writeOwnedSol(SEED_SLOT, Buffer.from("fixture-seed-sol-v1", "utf8"));
fs.writeFileSync(path.join(ROOT, "saves", COLLATERAL_SLOT + ".json"),
  JSON.stringify({ version: "3.0", slot: COLLATERAL_SLOT, untouched: true }));
writeOwnedSol(COLLATERAL_SLOT, Buffer.from("fixture-collateral-sol-v1", "utf8"));

const finalSaveText = JSON.stringify({ version: "3.0", lastSaved: "2026-08-03 00:15:00",
  slot: SLOT, kpoints: 48800, inventory: [
    { name: FIXTURE_ITEM.itemName, displayName: FIXTURE_ITEM.displayName,
      icon: FIXTURE_ITEM.icon, quantity: 1 },
  ] });
fs.writeFileSync(path.join(ROOT, "saves", SLOT + ".json"), finalSaveText, "utf8");
writeOwnedSol(SLOT, Buffer.from("fixture-target-safe-sol-v2", "utf8"));

function catalog(maxQuantity) {
  return FIXTURE_CATALOG_ITEMS.map((item) => ({ idx: item.catalogIndex, id: "fixture." + item.catalogIndex,
    item: item.itemName, type: item.shopType, price: item.unitPrice, displayname: item.displayName,
    majorType: item.majorType, subType: item.subType, actionType: "", weaponType: "", setId: "",
    setName: "", setOrder: 0, level: 1, icon: item.icon,
    maxQuantity: maxQuantity == null || item !== FIXTURE_ITEM ? item.maxQuantity : maxQuantity }));
}

function purchaseLines(selection) {
  const maxAffordable = Math.min(selection.maxQuantity,
    Math.floor(selection.balance / selection.unitPrice));
  return [{ catalogIndex: selection.catalogIndex,
    itemName: selection.itemName, displayName: selection.displayName, icon: selection.icon,
    quantity: selection.quantity,
    unitPrice: selection.unitPrice, total: selection.total, maxQuantity: selection.maxQuantity,
    maxAffordable, maxByCapacity: selection.maxQuantity,
    maxPurchasable: maxAffordable,
    itemKind: selection.deliveryContract.authorityItemKind }];
}

function inventoryItem(itemKind, name, displayName, icon, quantity, enhancementLevel) {
  const equipment = itemKind === "equipment";
  return { name, displayName, icon, majorType: equipment ? "装备" : "材料", use: "",
    actionType: "", weaponType: "", setId: "", setName: "", setOrder: 0, itemKind,
    quantity, enhancementLevel, maxEnhancementLevel: equipment ? 10 : 0,
    isMaxEnhancement: false, tierSlotAvailable: false, tierSlotUsed: false,
    modSlotCapacity: 0, modSlotUsed: 0, modSlots: [], modMeta: null, rarity: "普通" };
}

function occupiedSlot(physicalSlot, lease, item) {
  return { physicalSlot, occupied: true, slotLease: lease, item,
    confirmProjection: { itemKind: item.itemKind, name: item.name,
      displayName: item.displayName, quantity: item.quantity,
      enhancementLevel: item.enhancementLevel, rarity: item.rarity,
      tier: "", modSignature: "", lastUpdate: 1 } };
}

function inventoryBatches(accessibleCapacity) {
  const batches = [[
    { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
    { containerId: "战备箱", offset: 0, limit: 100, filterKey: "all" },
  ]];
  if (accessibleCapacity > 100) batches.push([
    { containerId: "战备箱", offset: 100, limit: 100, filterKey: "all" },
  ]);
  if (accessibleCapacity > 200) batches.push([
    { containerId: "战备箱", offset: 200,
      limit: accessibleCapacity - 200, filterKey: "all" },
  ]);
  return batches;
}

function inventorySnapshot(request, occupied, phase, accessibleCapacity, snapshotSeq) {
  const containerId = request.containerId;
  const bag = containerId === "背包";
  const capacity = bag ? 50 : 400;
  const access = bag ? 50 : accessibleCapacity;
  const actualLimit = Math.min(request.limit, Math.max(0, access - request.offset));
  const slots = [];
  const restart = phase === "restart";
  for (let ordinal = 0; ordinal < actualLimit; ordinal += 1) {
    const index = request.offset + ordinal;
    slots.push(occupied[index] || { physicalSlot: index, occupied: false,
      slotLease: "fixture.empty." + (restart ? "restart" : "first")
        + "." + containerId + "." + index });
  }
  const occupiedCount = Object.keys(occupied).length;
  return { containerId, capacity, accessibleCapacity: access, viewCapacity: access,
    filterKey: "all", pageSizeHint: bag ? 50 : 40, locked: !bag && access === 0,
    snapshotSeq, containerEpoch: bag ? (restart ? 110 : 100) : (restart ? 210 : 200),
    containerVersion: bag ? (phase === "initial" ? 1 : phase === "post" ? 2 : 1) : 1,
    offset: request.offset, limit: actualLimit, slots,
    filterFacets: occupiedCount > 0
      ? [{ id: "all", label: "全部", order: 0, count: occupiedCount, children: [] }] : [],
    filterItemCount: occupiedCount, setFacets: [], setFilterItemCount: 0 };
}

function inventoryResponse(panelInstanceId, callId, phase, selection, requests,
  accessibleCapacity, pairOrdinal) {
  const delivered = phase !== "initial";
  const restart = phase === "restart";
  const bag = {
    20: occupiedSlot(20, restart ? "fixture.collateral.restart.material"
      : "fixture.collateral.first.material",
      inventoryItem("stack", "强化石", "强化石显示名", "强化石", 9, 0)),
  };
  if (delivered) {
    bag[0] = occupiedSlot(0, restart ? "fixture.selected.restart.0" : "fixture.selected.post.0",
      inventoryItem("equipment", selection.itemName, selection.displayName,
        selection.icon, selection.quantity, 0));
  }
  const battle = {};
  if (accessibleCapacity > 0) {
    battle[2] = occupiedSlot(2, restart ? "fixture.battle.restart.2" : "fixture.battle.first.2",
      inventoryItem("equipment", "旧护具", "旧护具显示名", "废城防弹军装上装", 1, 3));
    const tail = accessibleCapacity - 1;
    battle[tail] = occupiedSlot(tail,
      (restart ? "fixture.battle.restart.tail." : "fixture.battle.first.tail.") + tail,
      inventoryItem("equipment", "尾部旧护具", "尾部旧护具显示名", "废城防弹军装上装", 1, 2));
  }
  return { type: "panel_resp", domain: "inventory", panel: "kshop", panelInstanceId,
    cmd: "snapshot", callId, success: true, v: 1,
    sessionNonce: restart ? "inv.fixture.restart" : "inv.fixture.first",
    snapshots: requests.map((request, index) => inventorySnapshot(request,
      request.containerId === "背包" ? bag : battle, phase, accessibleCapacity,
      10 + pairOrdinal * 3 + index)) };
}

function authorityReference(value) {
  const publicValue = /^sha256:[a-f0-9]{64}$/.test(String(value || ""))
    ? String(value) : tokenRef(value);
  const match = /^sha256:([a-f0-9]{64})$/.exec(publicValue);
  return match ? "sha256_" + match[1].slice(0, 24) : null;
}

const AUTHORITY_KEYS = ["expectedTuningToken", "tuningToken", "expectedCheckoutToken",
  "checkoutToken", "expectedPurchasedToken", "purchasedToken", "expectedCraftToken",
  "craftToken", "expectedBatchToken", "batchToken", "expectedTradeToken", "tradeToken",
  "expectedLearnToken", "learnToken", "expectedLease", "slotLease", "closeLease",
  "transactionId"];
function authorityTail(message) {
  const refs = new Map(AUTHORITY_KEYS.map((key) => [key, new Set()]));
  let fieldCount = 0;
  function visit(value) {
    if (Array.isArray(value)) return value.forEach(visit);
    if (!value || typeof value !== "object") return;
    Object.keys(value).forEach((key) => {
      if (refs.has(key)) {
        fieldCount += 1;
        const reference = authorityReference(value[key]);
        if (!reference) throw new Error("fixture authority value is not redacted: " + key);
        refs.get(key).add(reference);
      } else visit(value[key]);
    });
  }
  visit(message);
  if (fieldCount === 0) return "";
  let tail = " authorityFieldCount=" + fieldCount;
  AUTHORITY_KEYS.forEach((key) => {
    const values = Array.from(refs.get(key)).sort();
    if (values.length === 1) tail += " " + key + "Ref=" + values[0];
    else if (values.length > 1) tail += " " + key + "Refs=" + values.slice(0, 4).join(",");
    if (values.length > 4) tail += " " + key + "RefCount=" + values.length;
  });
  return tail;
}

function messageWireFacts(message) {
  const authorityValueLengths = {};
  function visit(value) {
    if (Array.isArray(value)) return value.forEach(visit);
    if (!value || typeof value !== "object") return;
    Object.keys(value).forEach((key) => {
      if (AUTHORITY_KEYS.includes(key) && typeof value[key] === "string") {
        const publicKey = "field:" + key;
        if (!authorityValueLengths[publicKey]) authorityValueLengths[publicKey] = [];
        authorityValueLengths[publicKey].push(value[key].length);
      } else visit(value[key]);
    });
  }
  visit(message);
  return { wirePayloadLength: JSON.stringify(message).length, authorityValueLengths };
}

function panelSummary(request) {
  return "[Panel] HandlePanelMessage: task=panel panel=kshop domain="
    + (request.domain === "inventory" ? "inventory" : "other")
    + " cmd=" + request.cmd + " callId=" + (request.callId || "other")
    + " payload=redacted len=" + JSON.stringify(request).length + authorityTail(request);
}

function flashSummary(component, action, fid, message) {
  let normalized;
  if (message.domain === "inventory") normalized = clone(message.payload);
  else {
    normalized = clone(message);
    ["type", "panel", "panelInstanceId", "cmd", "callId", "domain", "action", "task"]
      .forEach((key) => { delete normalized[key]; });
  }
  const payload = Object.assign({ task: "cmd", action, callId: fid }, normalized);
  return "[" + component + "] -> Flash: task=cmd cmd=" + action + " callId=" + fid
    + " payload=redacted len=" + JSON.stringify(payload).length + authorityTail(payload);
}

function socketSummary(task, action, fid, payload) {
  return "[XmlSocket:JSON] task=" + task + " cmd=" + action + " callId=" + fid
    + " success=true payload=redacted len=" + JSON.stringify(payload).length + authorityTail(payload);
}

function dispatchBindingSummary(request, domain, action, fid) {
  return "event=authority_flash_call_bound domain=" + domain
    + " webCallId=" + request.callId + " flashCallId=" + fid
    + " panel=kshop panelInstanceId=" + request.panelInstanceId
    + " cmd=" + request.cmd + " action=" + action;
}

function session(pid, port, ticks, lifecycle, marker) {
  const value = { schema: LauncherObservation.SESSION_SCHEMA, apiVersion: "FROZEN-v1",
    openedAt: FIXED_TIME, pid, httpPort: port, socketPort: port + 100,
    portsFile: "tmp/ports-" + marker + ".json",
    portsFileSha256: marker.repeat(64).slice(0, 64), portsFileBytes: 64,
    credentialFile: path.join(ROOT, "tmp", "credential-" + marker + ".json"),
    credentialFileSha256: (marker === "a" ? "b" : "c").repeat(64), credentialFileBytes: 128,
    credentialTokenSha256: (marker === "a" ? "d" : "e").repeat(64),
    credentialHeader: "X-CF7-Automation-Token", processStartUtcTicks: ticks,
    lifecycleId: lifecycle,
    capabilities: ["legacy.console", "legacy.logs", "legacy.status", "legacy.task"] };
  value.sessionEvidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function identity(pid, httpPort, producer) {
  return { runtimeMode: "isolated_candidate", installRoot: CANDIDATE_ROOT,
    processPath: path.join(CANDIDATE_ROOT, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
    coreSha256: producer.coreSha256, buildIdentity: producer.buildIdentityHash,
    payloadClosure: producer.payloadClosureHash, pid, httpPort };
}

function prepareFixtureCandidate(closure) {
  const artifactSourceHash = closure.producerInputs.domains.artifactSource.hash;
  const producerRecipeHash = closure.producerInputs.domains.producerRecipe.hash;
  const toolchainLockHash = closure.producerInputs.domains.toolchainLock.hash;
  const buildIdentityHash = closure.producerInputs.buildIdentityHash;
  const runtimeDirectory = path.join(CANDIDATE_ROOT, "runtime");
  fs.mkdirSync(runtimeDirectory, { recursive: true });
  const payloadSources = [
    { path: "CRAZYFLASHER7MercenaryEmpire.exe",
      bytes: Buffer.from("fixture-kshop-bootstrap-exe-v1", "utf8") },
    { path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll",
      bytes: Buffer.from("fixture-kshop-core-dll-v1", "utf8") },
    { path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe",
      bytes: Buffer.from("fixture-kshop-core-exe-v1", "utf8") },
  ];
  const payloadFiles = payloadSources.map((entry) => {
    const filePath = path.join(CANDIDATE_ROOT, entry.path.replace(/\//g, path.sep));
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, entry.bytes);
    return { path: entry.path, size: entry.bytes.length,
      sha256: sha256Bytes(entry.bytes).toUpperCase() };
  }).sort((left, right) => left.path.localeCompare(right.path));
  const payloadClosureHash = sha256Text(payloadFiles.map((entry) => entry.path + "\t"
    + entry.size + "\t" + entry.sha256).join("\n") + "\n").toUpperCase();
  const metadata = { schema: "cf7-runtime-candidate-metadata.v2",
    builderLabel: "fixture-offline-producer", artifactSourceHash, producerRecipeHash,
    toolchainLockHash, buildIdentityHash, payloadClosureHash, createdAtUtc: FIXED_TIME };
  fs.writeFileSync(path.join(CANDIDATE_ROOT, "runtime-build-metadata.v2.json"),
    JSON.stringify(metadata) + "\n", "utf8");
  fs.writeFileSync(path.join(runtimeDirectory, "cf7-runtime-manifest.tsv"), [
    "cf7-runtime-manifest-v2",
    "publishMode\tframework-dependent",
    "artifactSourceHash\t" + artifactSourceHash,
    "producerRecipeHash\t" + producerRecipeHash,
    "toolchainLockHash\t" + toolchainLockHash,
    "toolchainBaseline\tfixture-offline",
    "buildIdentityHash\t" + buildIdentityHash,
    "payloadClosureHash\t" + payloadClosureHash,
    ...payloadFiles.map((entry) => "file\t" + entry.path + "\t" + entry.size + "\t" + entry.sha256),
    "",
  ].join("\n"), "utf8");
  return Object.assign({}, metadata, { coreSha256: payloadFiles.find((entry) =>
    entry.path === "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll").sha256 });
}

function processContract(identityValue, sessionValue, marker) {
  const value = { schema: "workbench-live-e2e.launcher-process-contract.v1",
    apiVersion: "FROZEN-v1", observedAt: FIXED_TIME, pid: identityValue.pid,
    processPath: path.resolve(identityValue.processPath),
    processStartUtcTicks: sessionValue.processStartUtcTicks,
    commandLineSha256: marker.repeat(64), argvSha256: (marker === "f" ? "8" : "9").repeat(64),
    projectRoot: ROOT, projectRootArgumentExact: true, legacyHttpAutomationArg: true,
    agentRuntimeAdmission: false,
    trustedSource: "actual_process_command_line+pid_bound_credential" };
  value.artifactSha256 = sha256Text(canonicalJson(value));
  return value;
}

function cdpBinding(port, pid, listenerPid, marker) {
  const pageIdentity = { url: "https://overlay.local/overlay.html", origin: "https://overlay.local",
    timeOrigin: port, readyState: "complete", userAgent: "fixture-webview2" };
  return { port, allocatedAt: "2026-08-03T00:00:00.000Z", runtimePid: pid,
    exclusiveBeforeLaunch: true, configurationSource: "CF7_WEBVIEW2_ARGS", developerMode: true,
    expectedPageUrl: "https://overlay.local/overlay.html", pageIdentity,
    pageIdentitySha256: sha256Text(canonicalJson(pageIdentity)),
    pageContentSha256: marker.repeat(64), pageContentBytes: 4096,
    pageContentCapturedAt: "2026-08-03T00:00:02.000Z",
    attestation: { schema: "workbench-live-e2e.cdp-endpoint-attestation.v1",
      observedAt: "2026-08-03T00:00:01.000Z", port, runtimePid: pid, listenerPid,
      ancestorPids: [listenerPid, pid],
      userDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
      listenerExecutablePath: "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\fixture\\msedgewebview2.exe",
      listenerExecutable: "msedgewebview2.exe", commandLineSha256: "1".repeat(64),
      argvSha256: "2".repeat(64), exactPortArgument: true, exactUserDataRoot: true } };
}

function loadedProduction(closure, binding, runtimeIdentity, lifecycle, accessibleCapacity) {
  const web = ProductionClosure.webFiles(closure);
  const page = web.find((entry) => entry.role === "page");
  const scripts = ProductionClosure.scriptFiles(closure);
  const stylesheets = ProductionClosure.styleFiles(closure);
  const executable = ProductionClosure.expectedExecutableOccurrences(closure);
  const context = { occurrence: 1, id: 1, uniqueId: "fixture-overlay-context-" + lifecycle,
    origin: "https://overlay.local", name: "fixture-overlay",
    auxData: { frameId: "fixture-overlay-frame", isDefault: true, type: "default" } };
  const productionScriptOccurrences = executable.map((entry, index) => ({
    occurrence: index + 1, scriptId: "fixture-production-" + lifecycle + "-" + (index + 1),
    url: entry.url, executionContextId: context.id,
    startLine: 0, startColumn: 0, endLine: 1, endColumn: entry.bytes,
    sourceMapUrl: "", urlOrigin: "https://overlay.local", context: clone(context),
    sourceMethod: "Debugger.getScriptSource", sha256: entry.sha256, bytes: entry.bytes,
  }));
  const toolSource = Buffer.from("({fixture:true})\n//# sourceURL=cf7-evidence://kshop/0001-observer-detach.js", "utf8");
  const ownedEvaluations = [{ sequence: 1, label: "observer detach",
    url: "cf7-evidence://kshop/0001-observer-detach.js",
    sha256: sha256Bytes(toolSource), bytes: toolSource.length }];
  const toolOccurrence = { occurrence: productionScriptOccurrences.length + 1,
    scriptId: "fixture-tool-" + lifecycle + "-1", url: ownedEvaluations[0].url,
    executionContextId: context.id, startLine: 0, startColumn: 0, endLine: 1,
    endColumn: toolSource.length, sourceMapUrl: "", urlOrigin: "null", context: clone(context),
    sourceMethod: "Debugger.getScriptSource", sha256: ownedEvaluations[0].sha256,
    bytes: ownedEvaluations[0].bytes };
  const rawScriptOccurrences = productionScriptOccurrences.concat([toolOccurrence]);
  const iconProjection = ProductionClosure.iconResourceSetForNames(PRODUCTION_ROOT, closure,
    FIXTURE_CATALOG_ITEMS.map((entry) => entry.icon)
      .concat(accessibleCapacity > 0
        ? ["强化石", "废城防弹军装上装"] : ["强化石"]));
  const fontEnvironment = ProductionClosure.captureFontEnvironment(
    PRODUCTION_ROOT, closure, process.env);
  const lxgw = fontEnvironment.installed.find((entry) => entry.name === "lxgw-wenkai-screen.ttf");
  const staticResources = ProductionClosure.expectedStaticResourceSet(closure)
    .map((entry) => Object.assign({}, entry, {
      mimeType: entry.type === "Document" ? "text/html"
        : entry.type === "Stylesheet" ? "text/css"
          : entry.type === "Script" ? "text/javascript" : "image/webp",
      sourceMethod: null, sourceSha256: null, sourceBytes: null, sourceError: null,
    }));
  const boundResources = iconProjection.resources.map((entry) => Object.assign({}, entry, {
    sourceMethod: "Page.getResourceContent", sourceSha256: entry.sha256,
    sourceBytes: entry.bytes, sourceError: null,
  }));
  if (lxgw) boundResources.push({ url: lxgw.url, type: "Font",
    urlOrigin: "https://cfn-fonts.local", mimeType: "font/ttf",
    sourceMethod: "Page.getResourceContent", sourceSha256: lxgw.sha256,
    sourceBytes: lxgw.bytes, sourceError: null });
  const rawResourceOccurrences = staticResources.concat(boundResources)
    .map((entry, index) => {
      const resource = { url: entry.url, type: entry.type, mimeType: entry.mimeType };
      return { occurrence: index + 1, frameOccurrence: 1, resourceOccurrence: index + 1,
        frameId: context.auxData.frameId,
        frameUrl: "https://overlay.local/overlay.html",
        frameOrigin: "https://overlay.local", url: entry.url,
        urlOrigin: entry.urlOrigin, type: entry.type, resource,
        sourceMethod: entry.sourceMethod, sourceSha256: entry.sourceSha256,
        sourceBytes: entry.sourceBytes, sourceError: entry.sourceError };
    });
  const stylesheetOccurrences = rawResourceOccurrences.filter((entry) => entry.type === "Stylesheet");
  const value = { schema: ProductionClosure.LOADED_SCHEMA, lifecycle,
    capturePhase: "post_observer_detach",
    runtimePid: runtimeIdentity.pid, runId: binding.runId,
    productionClosureSha256: closure.closureSha256,
    productionBindingSha256: binding.bindingSha256,
    page: Object.assign({}, page, { url: "https://overlay.local/overlay.html",
      sourceMethod: "Page.getResourceContent" }),
    rawScriptOccurrences,
    rawExecutionContextOccurrences: [clone(context)],
    productionScriptOccurrences,
    ownedEvaluations,
    rawResourceOccurrences,
    fontEnvironment,
    iconProjection,
    scripts: scripts.map((entry) => Object.assign({}, entry, {
      url: "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length),
      sourceMethod: "Debugger.getScriptSource",
      occurrence: productionScriptOccurrences.find((occurrence) => occurrence.url
        === "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length)).occurrence,
    })),
    stylesheets: stylesheets.map((entry) => Object.assign({}, entry, {
      url: "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length),
      sourceMethod: "Page.getResourceContent",
      occurrence: stylesheetOccurrences.find((occurrence) => occurrence.url
        === "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length)).occurrence,
    })) };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function logSnapshot(sessionValue, lines, capturedAt) {
  const records = lines.map((line, index) => ({ lineNumber: index + 1, line }));
  const payload = { schema: LauncherObservation.LOG_SNAPSHOT_SCHEMA, requestedTailLimit: 2000,
    sessionEvidenceSha256: sessionValue.sessionEvidenceSha256,
    lifecycleId: sessionValue.lifecycleId, sessionPid: sessionValue.pid,
    sessionProcessStartUtcTicks: sessionValue.processStartUtcTicks,
    total: records.length, oldestLineNumber: records.length ? 1 : 1, records };
  return Object.assign({}, payload, { capturedAt: capturedAt || FIXED_TIME,
    tailSha256: sha256Text(canonicalJson(payload)) });
}

function stablePhase(set, observedAt) {
  const value = { schema: "workbench-live-e2e.stable-slot-artifact-set.v1",
    apiVersion: "FROZEN-v1", stableMs: 10, samples: 3, observedAt, set: clone(set) };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function artifactSet(slot, artifacts, capturedAt) {
  const ordered = artifacts.slice().sort((left, right) => left.locator.localeCompare(right.locator));
  const payload = { schema: CloneSaveGuard.ARTIFACT_SET_SCHEMA, slot,
    appDataRoot: APP_DATA, artifacts: ordered };
  return Object.assign({}, payload, { capturedAt: capturedAt || FIXED_TIME,
    setSha256: sha256Text(canonicalJson(payload)) });
}

function artifact(kind, locator, bytes) {
  return { kind, locator, sha256: sha256Bytes(bytes), bytes: bytes.length,
    regularFile: true, exactRealPath: true };
}

function cloneLifecycleEvidence() {
  const seedBegin = CloneSaveGuard.captureSlotArtifactSet({ root: ROOT, appData: APP_DATA,
    slot: SEED_SLOT, requireJson: true, capturedAt: FIXED_TIME });
  const targetSafe = CloneSaveGuard.captureSlotArtifactSet({ root: ROOT, appData: APP_DATA,
    slot: SLOT, requireJson: true, capturedAt: "2026-08-03T00:15:00.000Z" });
  const oldJson = Buffer.from('{"version":"3.0","oldTarget":true}', "utf8");
  const oldSol = Buffer.from("fixture-old-target-sol", "utf8");
  const targetBefore = artifactSet(SLOT, [
    artifact("json", "root:saves/" + SLOT + ".json", oldJson),
    artifact("sol", "appdata:" + path.relative(APP_DATA, ownedSolPath(SLOT)).replace(/\\/g, "/"), oldSol),
  ], FIXED_TIME);
  const backupDir = path.join(RUN_DIR, "backups", SLOT);
  fs.mkdirSync(backupDir, { recursive: true });
  const backupBytes = [oldJson, oldSol];
  const backups = targetBefore.artifacts.map((source, index) => {
    const extension = source.kind === "json" ? ".json" : ".sol";
    const relative = "backups/" + SLOT + "/" + String(index + 1).padStart(3, "0")
      + "-" + source.kind + extension;
    const bytes = source.kind === "json" ? oldJson : oldSol;
    fs.writeFileSync(path.join(RUN_DIR, relative.replace(/\//g, path.sep)), bytes, { flag: "w" });
    return { source: clone(source), backupRelativePath: relative,
      sha256: source.sha256, bytes: source.bytes };
  });
  void backupBytes;
  const preparedJson = Buffer.from('{"version":"3.0","prepared":true}', "utf8");
  const targetPrepared = artifactSet(SLOT,
    [artifact("json", "root:saves/" + SLOT + ".json", preparedJson)],
    "2026-08-03T00:01:00.000Z");
  const baselineSol = Buffer.from("fixture-runtime-baseline-sol", "utf8");
  const runtimeBaseline = artifactSet(SLOT, [
    artifact("json", "root:saves/" + SLOT + ".json", preparedJson),
    artifact("sol", "appdata:" + path.relative(APP_DATA, ownedSolPath(SLOT)).replace(/\\/g, "/"), baselineSol),
  ], "2026-08-03T00:02:00.000Z");
  const preparationContextSha256 = sha256Text(canonicalJson({ root: ROOT, runDir: RUN_DIR,
    seedSlot: SEED_SLOT, targetSlot: SLOT, transformId: "kshop-clone-lastSaved-v1",
    seedBegin, seedAfterPrepare: seedBegin, targetBefore, targetPrepared, backups }));
  const preparation = { schema: CloneSaveGuard.PREPARATION_SCHEMA, apiVersion: "FROZEN-v1",
    preparedAt: "2026-08-03T00:01:00.000Z", root: ROOT, runDir: RUN_DIR,
    seedSlot: SEED_SLOT, targetSlot: SLOT, transformId: "kshop-clone-lastSaved-v1",
    lock: { schema: CloneSaveGuard.LOCK_SCHEMA, slot: SLOT, ownerPid: 12345,
      ownerProcessStartUtcTicks: "638898000000000000", recoveryMode: false,
      recoveryRecordSha256: null, recordSha256: "1".repeat(64) },
    seedBegin, seedAfterPrepare: clone(seedBegin), targetBefore, targetPrepared, backups,
    preparationContextSha256,
    mutationJournal: { beganRecordSha256: "2".repeat(64), activeRecordSha256: "3".repeat(64),
      activeStatus: "prepared_pending_release", recoveryFilePresent: true } };
  preparation.preparationSha256 = sha256Text(canonicalJson(preparation));
  const release = { schema: CloneSaveGuard.RELEASE_SCHEMA, apiVersion: "FROZEN-v1",
    releasedAt: "2026-08-03T00:20:00.000Z", seedEnd: clone(seedBegin),
    targetEnd: clone(targetSafe), backupsVerified: true,
    preparedRecoveryRecordSha256: "3".repeat(64),
    lockRelease: { lockFileAbsent: true, terminalPrivateRelease: true },
    recoveryClear: { recoveryFileAbsent: true } };
  release.releaseSha256 = sha256Text(canonicalJson(release));
  const collateralBefore = captureSaveUniverse(ROOT, APP_DATA, SLOT,
    "2026-08-03T00:00:00.000Z");
  const collateralEnd = captureSaveUniverse(ROOT, APP_DATA, SLOT,
    "2026-08-03T00:20:00.000Z");
  return { preparation,
    phases: { runtimeBaseline: stablePhase(runtimeBaseline, "2026-08-03T00:02:10.000Z"),
      afterCommit: stablePhase(targetSafe, "2026-08-03T00:10:00.000Z"),
      afterSafeExit: stablePhase(targetSafe, "2026-08-03T00:15:00.000Z"),
      afterRestart: stablePhase(targetSafe, "2026-08-03T00:18:00.000Z") },
    collateralBefore, collateralEnd,
    collateral: { setSha256: collateralEnd.setSha256,
      artifactCount: collateralEnd.artifacts.length }, release };
}

function residue(identityValue, sessionValue, cdpPort, method, observedAt) {
  const value = { schema: LauncherObservation.RESIDUE_SCHEMA, apiVersion: "FROZEN-v1",
    observedAt, expectedPid: identityValue.pid,
    expectedProcessPath: path.resolve(identityValue.processPath), pidAbsent: true,
    candidateProcessAbsent: true, observedLauncherPids: [],
    ports: [identityValue.httpPort, sessionValue.socketPort, cdpPort]
      .map((port) => ({ port, open: false })),
    portsFile: sessionValue.portsFile, portsFileAbsent: true,
    credentialFile: sessionValue.credentialFile, credentialFileAbsent: true,
    stableSamples: 3, method };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function buildValidBundle(options) {
  const settings = Object.assign({ battleAccessibleCapacity: 240 }, options || {});
  if (![0, 40, 80, 120, 160, 200, 240].includes(settings.battleAccessibleCapacity)) {
    throw new Error("fixture battleAccessibleCapacity must be one production tier");
  }
  const productionClosure = ProductionClosure.captureProductionClosure(PRODUCTION_ROOT, FIXED_TIME);
  const producer = prepareFixtureCandidate(productionClosure);
  const firstIdentity = identity(4100, 18080, producer);
  const restartIdentity = identity(4200, 18081, producer);
  const firstSession = session(4100, 18080, "638898000000000001",
    "lifecycle_fixture_first", "a");
  const restartSession = session(4200, 18081, "638898000000000002",
    "lifecycle_fixture_restart", "c");
  const firstContract = processContract(firstIdentity, firstSession, "f");
  const restartContract = processContract(restartIdentity, restartSession, "7");
  const firstCdp = cdpBinding(19222, 4100, 5100, "a");
  const restartCdp = cdpBinding(19223, 4200, 5200, "b");
  const candidateProducer = ProductionClosure.captureCandidateProducerBinding(
    CANDIDATE_ROOT, firstIdentity, productionClosure);
  const productionBinding = ProductionClosure.bindProductionClosure(
    productionClosure, firstIdentity, RUN_ID, candidateProducer);
  const trustedCdpExpectations = { expectedPageUrl: "https://overlay.local/overlay.html",
    expectedPageOrigin: "https://overlay.local",
    expectedUserDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
    expectedListenerExecutableName: "msedgewebview2.exe" };
  const rawEvents = [];
  const hostFirst = [];
  const hostRestart = [];
  const ranges = Object.create(null);
  let currentHost = hostFirst;
  let webIndex = 0;
  let shopFid = 0;
  let inventoryFid = 0;
  let clockMs = Date.parse("2026-08-03T00:03:00.000Z");

  function advance(milliseconds) {
    clockMs += Number(milliseconds || 25);
    return new Date(clockMs).toISOString();
  }

  function hostTimestamp(iso) {
    const value = new Date(iso);
    return [value.getHours(), value.getMinutes(), value.getSeconds()]
      .map((entry) => String(entry).padStart(2, "0")).join(":")
      + "." + String(value.getMilliseconds()).padStart(3, "0");
  }

  function emit(event) {
    const facts = event && event.message ? messageWireFacts(event.message) : {};
    rawEvents.push(Object.assign({ observedAt: advance(25) }, event, facts));
  }
  function host(line) {
    const observedAt = advance(25);
    currentHost.push(hostTimestamp(observedAt) + " " + line);
  }
  function begin(step) {
    ranges[step] = { start: rawEvents.length, end: null,
      issuedAt: advance(25), providerStartedAt: advance(25),
      providerActionAt: advance(25), captureAt: null, providerCompletedAt: null };
  }
  function end(step) {
    ranges[step].end = rawEvents.length;
    if (["safe_exit", "exit_confirm"].includes(step)) ranges[step].captureAt = advance(25);
    ranges[step].providerCompletedAt = advance(25);
  }
  function webCallId(prefix) { webIndex += 1; return "wb.fixture." + prefix + "." + webIndex; }
  function hostMap(request) {
    host(panelSummary(request));
    const inventory = request.domain === "inventory";
    if (inventory) host("[Panel] Routing domain=inventory cmd=" + request.cmd
      + " to InventoryTask, _inventoryTask=ok");
    else {
      host("[Panel] Routing cmd=" + request.cmd + " to ShopTask, _shopTask=ok");
      host("[ShopTask] HandleWebRequest: cmd=" + request.cmd);
    }
    const fid = inventory ? ++inventoryFid : ++shopFid;
    const action = inventory ? "inventorySnapshot" : SHOP_ACTIONS[request.cmd];
    host(dispatchBindingSummary(request, inventory ? "inventory" : "shop", action, fid));
    host(flashSummary(inventory ? "InventoryTask" : "ShopTask", action, fid, request));
    return { inventory, fid, action };
  }
  function hostResponse(mapping, response) {
    const business = clone(response);
    ["type", "domain", "panel", "panelInstanceId", "cmd", "callId"]
      .forEach((key) => { delete business[key]; });
    if (!mapping.inventory && ["shopBulkQuery", "shopCheckoutCommit"].includes(mapping.action)) {
      const purchasedView = business.purchased;
      business.purchased = clone(legacyPurchased);
      business.purchasedView = clone(purchasedView);
    }
    const flashResponse = Object.assign({ task: mapping.inventory
      ? "inventory_response" : "shop_response", callId: mapping.fid }, business);
    host(socketSummary(mapping.inventory ? "inventory_response" : "shop_response",
      mapping.action, mapping.fid, flashResponse));
    if (!mapping.inventory) host("[ShopTask] <- Flash response received");
  }
  function beginBusiness(panelInstanceId, cmd, payload, response) {
    const request = Object.assign({}, payload || {}, { type: "panel", panel: "kshop",
      panelInstanceId, cmd, callId: webCallId(cmd) });
    emit({ kind: "panel_request_issued", direction: "outbound", callId: request.callId,
      cmd: request.cmd, metadata: { channel: "shop" }, message: request });
    emit({ kind: "bridge_send", direction: "outbound", message: request });
    const mapping = hostMap(request);
    const reply = Object.assign({}, response, { type: "panel_resp", panel: "kshop",
      panelInstanceId, cmd, callId: request.callId });
    return { request, response: reply, mapping };
  }
  function finishBusiness(call) {
    const { request, response: reply, mapping } = call;
    hostResponse(mapping, reply);
    emit({ kind: "webview_message", direction: "inbound", message: reply });
    return { request, response: reply };
  }
  function business(panelInstanceId, cmd, payload, response) {
    return finishBusiness(beginBusiness(panelInstanceId, cmd, payload, response));
  }
  function beginInventory(panelInstanceId, phase, requests, pairOrdinal) {
    const request = { type: "panel", panel: "kshop", panelInstanceId, domain: "inventory",
      cmd: "snapshot", callId: webCallId("inventory"),
      payload: { v: 1, requests: clone(requests) } };
    emit({ kind: "panel_request_issued", direction: "outbound", callId: request.callId,
      cmd: request.cmd, metadata: { channel: "inventory" }, message: request });
    emit({ kind: "bridge_send", direction: "outbound", message: request });
    const mapping = hostMap(request);
    const reply = inventoryResponse(panelInstanceId, request.callId, phase, selection,
      requests, settings.battleAccessibleCapacity, pairOrdinal);
    return { request, response: reply, mapping };
  }
  function finishInventory(call) {
    const { request, response: reply, mapping } = call;
    hostResponse(mapping, reply);
    emit({ kind: "webview_message", direction: "inbound", message: reply });
    return { request, response: reply };
  }
  function inventorySurface(panelInstanceId, phase, firstCall) {
    const batches = inventoryBatches(settings.battleAccessibleCapacity);
    const pairs = [];
    if (firstCall) pairs.push(finishInventory(firstCall));
    else pairs.push(finishInventory(beginInventory(panelInstanceId, phase, batches[0], 0)));
    for (let pairOrdinal = 1; pairOrdinal < batches.length; pairOrdinal += 1) {
      pairs.push(finishInventory(beginInventory(panelInstanceId, phase,
        batches[pairOrdinal], pairOrdinal)));
    }
    return pairs;
  }
  function open(panelInstanceId) {
    host("[PanelHost] opened: kshop rect=1280x720");
    emit({ kind: "webview_message", direction: "inbound", message: { type: "panel_cmd",
      cmd: "open", panel: "kshop", panelInstanceId, initData: { panelInstanceId } } });
  }
  function close(panelInstanceId) {
    emit({ kind: "dom_input", eventType: "click", direction: "input", isTrusted: true,
      button: 0, key: null, repeat: false, clientX: 1200, clientY: 40,
      target: { selector: "[data-header-action=\"close\"]", tagName: "BUTTON", text: "关闭", attributes: {
        class: "kshop-close-btn workbench-close-btn", "data-header-action": "close" },
        visible: true, enabled: true,
        viewport: { width: 1280, height: 720, devicePixelRatio: 1, scrollX: 0, scrollY: 0 },
        rect: { left: 1180, top: 20, right: 1240, bottom: 60, width: 60, height: 40 },
        clientPoint: { x: 1200, y: 40 }, hitTargetMatches: true },
      panelState: { panel: "kshop", hidden: false } });
    const request = { type: "panel", panel: "kshop", panelInstanceId, cmd: "close" };
    emit({ kind: "bridge_send", direction: "outbound", message: request });
    host(panelSummary(request));
    host("[PanelHost] closed: kshop");
    host("event=panel_exact_close_completed panel=kshop panelInstanceId=" + panelInstanceId);
  }

  const purchased = [];
  const legacyPurchased = [];
  const bulkBefore = { success: true, catalog: catalog(), playerLevel: 30, reverseLevel: 0,
    kpoints: 50000, cart: [], cartAdjusted: false, purchased, purchasedToken: PURCHASED_TOKEN };
  const selection = chooseCatalogSelection(bulkBefore.catalog, bulkBefore.kpoints,
    bulkBefore.playerLevel, bulkBefore.reverseLevel);
  const finalBalance = selection.balance - selection.total;
  const bulkAfter = Object.assign({}, bulkBefore, { kpoints: finalBalance, cart: [],
    catalog: catalog() });

  emit({ kind: "cdp_endpoint_bound", cdpPort: firstCdp.port, runtimePid: firstCdp.runtimePid,
    exclusiveBeforeLaunch: true, configurationSource: "CF7_WEBVIEW2_ARGS",
    pageUrl: "https://overlay.local/overlay.html", endpointAttestation: firstCdp.attestation,
    pageIdentity: firstCdp.pageIdentity, pageIdentitySha256: firstCdp.pageIdentitySha256,
    pageContentSha256: firstCdp.pageContentSha256, pageContentBytes: firstCdp.pageContentBytes,
    pageContentCapturedAt: firstCdp.pageContentCapturedAt });
  emit({ kind: "observer_ready", url: "https://overlay.local/overlay.html",
    bridgeWrapped: true, uiDataWrapped: true, panelRequestMuxWrapped: true,
    webviewObserved: true, observationOnly: true, businessActionMethods: [] });

  begin("open_kshop");
  open(PANEL_ONE);
  const initialBulkCall = beginBusiness(PANEL_ONE, "bulkQuery", {}, bulkBefore);
  const surfaceBatches = inventoryBatches(settings.battleAccessibleCapacity);
  const initialInventoryCall = beginInventory(PANEL_ONE, "initial", surfaceBatches[0], 0);
  finishBusiness(initialBulkCall);
  inventorySurface(PANEL_ONE, "initial", initialInventoryCall);
  end("open_kshop");

  begin("add_selected_item");
  emit({ kind: "dom_input", eventType: "click", direction: "input", isTrusted: true,
    button: 0, key: null, repeat: false, clientX: 900, clientY: 300,
    target: { selector: "button[data-idx=\"37\"]", tagName: "BUTTON", text: "加入",
      attributes: { class: "kshop-add-btn", "data-idx": "37" }, visible: true, enabled: true,
      viewport: { width: 1280, height: 720, devicePixelRatio: 1, scrollX: 0, scrollY: 0 },
      rect: { left: 880, top: 280, right: 940, bottom: 320, width: 60, height: 40 },
      clientPoint: { x: 900, y: 300 }, hitTargetMatches: true },
    panelState: { panel: "kshop", hidden: false } });
  business(PANEL_ONE, "saveCart", { cart: selection.cart },
    { success: true, v: 1, cart: selection.cart, adjusted: false });
  end("add_selected_item");

  begin("open_checkout");
  emit({ kind: "dom_input", eventType: "click", direction: "input", isTrusted: true,
    button: 0, key: null, repeat: false, clientX: 1000, clientY: 680,
    target: { selector: "#kshop-checkout", tagName: "BUTTON", text: "结算",
      attributes: { id: "kshop-checkout" }, visible: true, enabled: true,
      viewport: { width: 1280, height: 720, devicePixelRatio: 1, scrollX: 0, scrollY: 0 },
      rect: { left: 960, top: 650, right: 1040, bottom: 710, width: 80, height: 60 },
      clientPoint: { x: 1000, y: 680 }, hitTargetMatches: true },
    panelState: { panel: "kshop", hidden: false } });
  const preview = { success: true, v: 1, checkoutToken: CHECKOUT_TOKEN,
    purchaseLines: purchaseLines(selection), total: selection.total, balance: 50000,
    projectedBalance: finalBalance, canCommit: true, blockingError: "" };
  business(PANEL_ONE, "checkoutPreview", { v: 1, cart: selection.cart }, preview);
  end("open_checkout");

  begin("commit_checkout");
  emit({ kind: "dom_input", eventType: "click", direction: "input", isTrusted: true,
    button: 0, key: null, repeat: false, clientX: 900, clientY: 650,
    target: { selector: "[data-kshop-settlement-commit]", tagName: "BUTTON", text: "确认购买",
      attributes: { "data-kshop-settlement-commit": "" }, visible: true, enabled: true,
      viewport: { width: 1280, height: 720, devicePixelRatio: 1, scrollX: 0, scrollY: 0 },
      rect: { left: 860, top: 620, right: 940, bottom: 680, width: 80, height: 60 },
      clientPoint: { x: 900, y: 650 }, hitTargetMatches: true },
    panelState: { panel: "kshop", hidden: false } });
  business(PANEL_ONE, "checkoutCommit", { v: 1, expectedCheckoutToken: CHECKOUT_TOKEN },
    { success: true, v: 1, newBalance: finalBalance,
      delivered: purchaseLines(selection), cart: [],
      purchased, purchasedToken: PURCHASED_TOKEN, catalog: catalog() });
  inventorySurface(PANEL_ONE, "post");
  end("commit_checkout");

  begin("close_kshop"); close(PANEL_ONE); end("close_kshop");
  begin("safe_exit");
  host("[Frame:UI] sample q:1|sv:1|q:1|sv:2|q:1");
  const diskEvidence = LauncherObservation.captureDiskSaveEvidence({ root: ROOT, slot: SLOT });
  host("[ArchiveTask] Shadow saved: " + SLOT + " (" + diskEvidence.textCharacters
    + " chars) path=" + diskEvidence.path);
  end("safe_exit");
  emit({ kind: "observer_detached" });
  const firstSnapshotCapturedAt = advance(50);
  begin("exit_confirm"); end("exit_confirm");
  const afterSafeExitResidueAt = advance(50);

  currentHost = hostRestart;
  shopFid = 0;
  inventoryFid = 0;
  emit({ kind: "cdp_endpoint_bound", cdpPort: restartCdp.port, runtimePid: restartCdp.runtimePid,
    exclusiveBeforeLaunch: true, configurationSource: "CF7_WEBVIEW2_ARGS",
    pageUrl: "https://overlay.local/overlay.html", endpointAttestation: restartCdp.attestation,
    pageIdentity: restartCdp.pageIdentity, pageIdentitySha256: restartCdp.pageIdentitySha256,
    pageContentSha256: restartCdp.pageContentSha256, pageContentBytes: restartCdp.pageContentBytes,
    pageContentCapturedAt: restartCdp.pageContentCapturedAt });
  emit({ kind: "observer_ready", url: "https://overlay.local/overlay.html",
    bridgeWrapped: true, uiDataWrapped: true, panelRequestMuxWrapped: true,
    webviewObserved: true, observationOnly: true, businessActionMethods: [] });
  begin("restart_readback_open_kshop"); open(PANEL_TWO);
  const restartBulkCall = beginBusiness(PANEL_TWO, "bulkQuery", {}, bulkAfter);
  const restartInventoryCall = beginInventory(PANEL_TWO, "restart", surfaceBatches[0], 0);
  finishBusiness(restartBulkCall);
  inventorySurface(PANEL_TWO, "restart", restartInventoryCall);
  end("restart_readback_open_kshop");
  begin("restart_readback_close_kshop"); close(PANEL_TWO);
  end("restart_readback_close_kshop");
  emit({ kind: "observer_detached" });
  const restartSnapshotCapturedAt = advance(50);
  const shutdownRequestedAt = advance(50);
  const shutdownCompletedAt = advance(50);
  const finalResidueAt = advance(50);

  const transcript = Object.assign({ schema: "workbench-live-e2e.kshop.transcript.v2",
    observerId: OBSERVER_ID, pageUrl: "https://overlay.local/overlay.html" },
  sealEvents(rawEvents.map((event) => Object.assign({ observerId: OBSERVER_ID }, event))));
  const firstBoundary = LauncherObservation.createTerminalLogBoundary(logSnapshot(firstSession, []));
  const restartBoundary = LauncherObservation.createTerminalLogBoundary(logSnapshot(restartSession, []));
  const firstSnapshot = logSnapshot(firstSession, hostFirst, firstSnapshotCapturedAt);
  const restartSnapshot = logSnapshot(restartSession, hostRestart, restartSnapshotCapturedAt);
  const safeExitEvidence = LauncherObservation.verifyArchiveSaveEvidence({ root: ROOT, slot: SLOT,
    boundary: firstBoundary, snapshot: firstSnapshot, diskEvidence,
    requiredOrder: ["sv1", "sv2", "archive"] });

  const controlActions = {
    open_kshop: ["open_kshop", ["bulkQuery", "snapshot"]],
    add_selected_item: ["add_selected_item", ["saveCart"]],
    open_checkout: ["open_checkout", ["checkoutPreview"]],
    commit_checkout: ["commit_checkout", ["checkoutCommit", "snapshot"]],
    close_kshop: ["close_kshop", ["close"]],
    safe_exit: ["safe_exit", []],
    exit_confirm: ["exit_confirm", []],
    restart_readback_open_kshop: ["open_kshop", ["bulkQuery", "snapshot"]],
    restart_readback_close_kshop: ["close_kshop", ["close"]],
  };
  const controlSelectors = {
    add_selected_item: ["button[data-idx=\"37\"]"],
    open_checkout: ["#kshop-checkout"],
    commit_checkout: ["[data-kshop-settlement-commit]"],
    close_kshop: ["[data-header-action=\"close\"]"],
    restart_readback_close_kshop: ["[data-header-action=\"close\"]"],
  };
  function inputObservation(step, timing) {
    if (!Object.prototype.hasOwnProperty.call(controlSelectors, step)) return null;
    const event = transcript.events.find((entry) => entry.sequence > timing.start
      && entry.sequence <= timing.end && entry.kind === "dom_input" && entry.isTrusted === true);
    if (!event) throw new Error("fixture DOM observation missing: " + step);
    return { eventRef: { observerId: transcript.observerId, sequence: event.sequence,
      eventSha256: event.eventHash }, observedAt: event.observedAt, eventType: event.eventType,
    isTrusted: event.isTrusted, selector: event.target.selector, tagName: event.target.tagName,
    visible: event.target.visible, enabled: event.target.enabled, viewport: clone(event.target.viewport),
    rect: clone(event.target.rect), clientPoint: clone(event.target.clientPoint),
    hitTargetMatches: event.target.hitTargetMatches, key: event.key, button: event.button,
    repeat: event.repeat };
  }
  const commitRequestId = "fixture-commit_checkout";
  const commitDecision = { schema: "workbench-live-e2e.authorization-decision.v1",
    decisionId: "fixture-kshop-purchase", issuedAt: FIXED_TIME,
    expiresAt: "2026-08-03T01:00:00.000Z", source: "cli_explicit_flag", oneShot: true,
    allowedStep: "commit_checkout", scope: { journey: "kshop-dynamic-single-item-purchase.v1",
      runId: RUN_ID, exactRequestId: commitRequestId, slot: SLOT,
      candidateRoot: CANDIDATE_ROOT, selection, cart: selection.cart,
      total: selection.total } };
  const decisionSha = sha256Text(canonicalJson(commitDecision));
  const controlRequests = [];
  const controlAcks = [];
  const controlProviderReceipts = [];
  const controlCaptures = [];
  const controlBindings = [];
  const requestDirectory = path.join(RUN_DIR, "control", "requests");
  const ackDirectory = path.join(RUN_DIR, "control", "acks");
  const providerReceiptDirectory = path.join(RUN_DIR, "control", "provider-receipts");
  fs.mkdirSync(requestDirectory, { recursive: true });
  fs.mkdirSync(ackDirectory, { recursive: true });
  fs.mkdirSync(providerReceiptDirectory, { recursive: true });
  REQUIRED_CONTROL_STEPS.forEach((step, index) => {
    const timing = ranges[step];
    const request = { schema: CONTROL_SCHEMA,
      requestId: step === "commit_checkout" ? commitRequestId : "fixture-" + step,
      step, runId: RUN_ID, issuedAt: timing.issuedAt,
      expiresAt: new Date(Date.parse(timing.issuedAt) + 3600000).toISOString(),
      allowedTransports: ["codex_computer_use"],
      requiresCommitAuthorization: step === "commit_checkout",
      requiresCaptureSha256: ["safe_exit", "exit_confirm"].includes(step),
      authorizationRef: step === "commit_checkout"
        ? { decisionId: commitDecision.decisionId, decisionSha256: decisionSha } : null,
      instructions: "fixture", selectors: controlSelectors[step] || [], expectedIndependentEvidence: [],
      domainIntent: { action: controlActions[step][0], browserSequenceStart: ranges[step].start,
        expectedWebCommands: controlActions[step][1] } };
    const requestBytes = Buffer.from(JSON.stringify(request, null, 2) + "\n", "utf8");
    const requestRelative = "control/requests/" + request.requestId + ".json";
    fs.writeFileSync(path.join(RUN_DIR, requestRelative.replace(/\//g, path.sep)), requestBytes);
    const captureIndex = step === "safe_exit" ? 0 : step === "exit_confirm" ? 1 : -1;
    const operationId = "fixture-provider-operation-" + String(index + 1).padStart(2, "0");
    const observation = inputObservation(step, timing);
    let capture = null;
    if (captureIndex >= 0) {
      const base = clone(CAPTURES[captureIndex]);
      const capturePath = path.join(RUN_DIR, base.relativePath.replace(/\//g, path.sep));
      fs.utimesSync(capturePath, new Date(timing.captureAt), new Date(timing.captureAt));
      const captureStat = fs.statSync(capturePath);
      capture = Object.assign(base, { capturedAt: timing.captureAt,
        fileModifiedAt: new Date(captureStat.mtimeMs).toISOString(), eventRef: null });
    }
    function operationEvent(sequence, kind, occurredAt, evidence) {
      const value = { schema: PROVIDER_EVENT_SCHEMA, sequence,
        eventId: operationId + ".event." + sequence, kind, occurredAt,
        operationId, requestId: request.requestId, evidence };
      value.eventSha256 = providerEventSha256(value);
      return value;
    }
    const operationEvents = [operationEvent(1, "provider_started", timing.providerStartedAt,
      { kind: "provider_operation_started" })];
    const actionEvidence = observation
      ? { kind: "trusted_dom_input", observerId: observation.eventRef.observerId,
        sequence: observation.eventRef.sequence, eventSha256: observation.eventRef.eventSha256 }
      : { kind: "provider_tool_result_action", issuer: "offline.fixture",
        toolResultSource: "fixture.contract", operationId, action: request.domainIntent.action };
    operationEvents.push(operationEvent(2, "action_completed",
      observation ? observation.observedAt : timing.providerActionAt, actionEvidence));
    if (capture) {
      const captureEvent = operationEvent(3, "capture_created", capture.capturedAt,
        { kind: "provider_capture", relativePath: capture.relativePath,
          sha256: capture.sha256, bytes: capture.bytes });
      capture.eventRef = { eventId: captureEvent.eventId,
        eventSha256: captureEvent.eventSha256 };
      operationEvents.push(captureEvent);
    }
    operationEvents.push(operationEvent(operationEvents.length + 1, "provider_completed",
      timing.providerCompletedAt, { kind: "provider_operation_completed", result: "completed" }));
    const providerReceipt = { schema: PROVIDER_RECEIPT_SCHEMA, operationId,
      issuer: "offline.fixture", toolResultSource: "fixture.contract",
      transport: "codex_computer_use", requestId: request.requestId, runId: RUN_ID,
      step, action: request.domainIntent.action, result: "completed",
      startedAt: timing.providerStartedAt,
      completedAt: timing.providerCompletedAt,
      requestBindingSha256: sha256Text(canonicalJson(request)),
      requestArtifact: { relativePath: requestRelative, sha256: sha256Bytes(requestBytes),
        bytes: requestBytes.length },
      inputObservation: observation,
      operationEvents,
      capture };
    providerReceipt.receiptSha256 = sha256Text(canonicalJson(providerReceipt));
    const providerBytes = Buffer.from(JSON.stringify(providerReceipt, null, 2) + "\n", "utf8");
    const providerRelative = "control/provider-receipts/" + request.requestId + ".json";
    fs.writeFileSync(path.join(RUN_DIR, providerRelative.replace(/\//g, path.sep)), providerBytes);
    const ack = { schema: ACK_SCHEMA, requestId: request.requestId, runId: RUN_ID, step,
      action: request.domainIntent.action,
      requestBindingSha256: sha256Text(canonicalJson(request)),
      transport: "codex_computer_use", result: "completed",
      completedAt: providerReceipt.completedAt,
      authorizationDecisionId: step === "commit_checkout" ? commitDecision.decisionId : null,
      providerReceiptRef: { relativePath: providerRelative, sha256: sha256Bytes(providerBytes),
        bytes: providerBytes.length, operationId } };
    controlRequests.push(request);
    controlAcks.push(ack);
    controlProviderReceipts.push(providerReceipt);
    if (capture) controlCaptures.push(capture);
    controlBindings.push({ requestId: request.requestId, step, runId: RUN_ID,
      action: request.domainIntent.action, browserSequenceStart: ranges[step].start,
      browserSequenceEnd: ranges[step].end,
      requestSha256: sha256Text(canonicalJson(request)), ackSha256: sha256Text(canonicalJson(ack)) });
    fs.writeFileSync(path.join(ackDirectory, request.requestId + ".json"),
      JSON.stringify(ack, null, 2) + "\n");
  });
  fs.writeFileSync(path.join(RUN_DIR, "control", "current-request.json"),
    JSON.stringify(controlRequests.at(-1), null, 2) + "\n");

  const cloneLifecycle = cloneLifecycleEvidence();
  const candidateIdentity = { runtimeMode: firstIdentity.runtimeMode,
    processPath: path.resolve(firstIdentity.processPath), coreSha256: firstIdentity.coreSha256,
    buildIdentity: firstIdentity.buildIdentity, payloadClosure: firstIdentity.payloadClosure,
    installRoot: path.resolve(firstIdentity.installRoot) };
  const candidateBeforeClone = { schema: "workbench-live-e2e.candidate-before-clone.v1",
    apiVersion: "FROZEN-v1", resolvedAt: FIXED_TIME, identity: candidateIdentity,
    candidateEvidence: { source: "fixture_exact_module_clone" } };
  candidateBeforeClone.identitySha256 = sha256Text(canonicalJson(candidateIdentity));

  const bundle = { schema: TOOL_SCHEMA, status: "offline_fixture",
    evidenceMode: "offline_fixture", generatedAt: FIXED_TIME,
    fixture: { schema: "workbench-live-e2e.kshop.offline-fixture.v1",
      productionEffects: false, purpose: "contract-self-test" },
    completedAt: "2026-08-03T00:20:00.000Z", runId: RUN_ID, root: ROOT,
    runDir: path.relative(ROOT, RUN_DIR).replace(/\\/g, "/"), slot: SLOT,
    seedSlot: SEED_SLOT, candidateRoot: CANDIDATE_ROOT,
    productionClosure, productionBinding, candidateProducer,
    selection,
    authorization: { isolatedPurchaseAllowed: true, codexFallbackAllowed: true,
      selectedTransport: "codex_computer_use",
      launcherAgentRuntime: { available: false, source: "authenticated_process_contract",
        preferredTransport: "launcher_agent_runtime",
        requiredCapabilities: ["computer.use.kshop", "native.safe_exit"],
        observedCapabilities: firstSession.capabilities.slice().sort(),
        reasonCode: "authenticated_process_lacks_kshop_computer_use",
        reason: "fixture authenticated legacy HTTP process excludes Agent Runtime",
        artifact: firstContract, artifactSha256: sha256Text(canonicalJson(firstContract)) },
      commitDecision, commitDecisionSha256: decisionSha },
    controlRequests, controlAcks, controlProviderReceipts, controlCaptures, controlBindings,
    candidateBeforeClone,
    runtime: { first: { identity: firstIdentity, identityVerified: true,
      ready: { expectedAttemptId: "attempt_fixture_first" }, cdpBinding: firstCdp,
      trustedCdpExpectations, sessionEvidence: firstSession, processContract: firstContract,
      loadedProduction: loadedProduction(productionClosure, productionBinding, firstIdentity,
        "first", settings.battleAccessibleCapacity) },
    restart: { identity: restartIdentity, identityVerified: true,
      ready: { expectedAttemptId: "attempt_fixture_restart" }, cdpBinding: restartCdp,
      trustedCdpExpectations, sessionEvidence: restartSession, processContract: restartContract,
      loadedProduction: loadedProduction(productionClosure, productionBinding, restartIdentity,
        "restart", settings.battleAccessibleCapacity),
      shutdownEvidence: null } },
    cloneLifecycle, safeExitEvidence,
    residue: { afterSafeExit: residue(firstIdentity, firstSession, firstCdp.port,
      "SAFEEXIT_UI", afterSafeExitResidueAt),
      final: residue(restartIdentity, restartSession, restartCdp.port,
        "agent_control.shutdown", finalResidueAt) },
    transcript,
    hostLog: { schema: "workbench-live-e2e.kshop.host-lifecycles.v1",
      lifecycles: [{ label: "first", sessionEvidence: firstSession,
        boundary: firstBoundary, terminalSnapshot: firstSnapshot },
      { label: "restart", sessionEvidence: restartSession,
        boundary: restartBoundary, terminalSnapshot: restartSnapshot }] },
    moduleAdmission: moduleAdmission() };
  bundle.runtime.restart.shutdownEvidence = {
    schema: "workbench-live-e2e.kshop.authenticated-shutdown.v1",
    requestedAt: shutdownRequestedAt, completedAt: shutdownCompletedAt,
    pid: restartIdentity.pid,
    sessionEvidenceSha256: restartSession.sessionEvidenceSha256,
    response: { success: true, ok: true },
  };
  bundle.runtime.restart.shutdownEvidence.evidenceSha256 = sha256Text(canonicalJson(
    bundle.runtime.restart.shutdownEvidence));
  bundle.rawBundleManifest = buildRawBundleManifest(bundle);
  return bundle;
}

module.exports = {
  CHECKOUT_TOKEN,
  PANEL_ONE,
  PANEL_TWO,
  ROOT,
  RUN_DIR,
  SLOT,
  buildValidBundle,
};
