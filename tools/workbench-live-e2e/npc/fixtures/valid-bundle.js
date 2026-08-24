"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const LauncherObservation = require("../../lib/launcher-observation");
const ProductionClosure = require("../production-closure");
const { authorityProjection, strictRequestPairsFromEvents } = require("../protocol");
const { domInputEvidence, expectedProviderOperationId } = require("../control-channel");
const {
  BUNDLE_SCHEMA,
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  PRICING_CONSTRAINT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  atomicWriteJson,
  buildArtifactManifest,
  canonicalJson,
  sealEvents,
  sealEvidenceOrigin,
  sealTrustedTimeline,
  sha256Bytes,
  sha256File,
  sha256Text,
  tokenRef,
} = require("../common");

const SHOP_ID = "general";
const RUN_ID = "npc.fixture.20260803";
const SLOT = "cf7_agent_a3_npc_fixture";
const PURCHASE_SLOT = 1;
const INSTANCES = Object.freeze({
  first: "panel.fixture.npc.first",
  restart: "panel.fixture.npc.restart",
});
const PURCHASE = Object.freeze({
  catalogIndex: 17,
  itemName: "训练短刀",
  displayName: "训练短刀",
  icon: "黄鹂短刀",
  basePrice: 100,
  unitPrice: 100,
  buyRatePermille: 1000,
  maxQuantity: 1,
  itemKind: "equipment",
  destinationView: "bag",
  quantity: 1,
});

function iso(second, millis) {
  const wholeSeconds = Math.floor(Number(second));
  const fractionalMillis = Math.round((Number(second) - wholeSeconds) * 1000);
  return new Date(Date.UTC(2026, 7, 3, 0, 0, wholeSeconds,
    Number(millis || 0) + fractionalMillis)).toISOString();
}

function catalog() {
  return [{
    catalogIndex: PURCHASE.catalogIndex,
    itemName: PURCHASE.itemName,
    displayName: PURCHASE.displayName,
    icon: PURCHASE.icon,
    unitPrice: PURCHASE.unitPrice,
    basePrice: PURCHASE.basePrice,
    maxQuantity: PURCHASE.maxQuantity,
    locked: false,
    majorType: "武器",
    use: "",
    actionType: "",
    weaponType: "",
    setId: "",
    setName: "",
    setOrder: 0,
    requiredInfo: "",
  }];
}

function collectionView(containerId, viewId, epoch) {
  return {
    containerId,
    capacity: 20,
    accessibleCapacity: 20,
    viewCapacity: 1,
    offset: 0,
    limit: 1,
    filterKey: "all",
    slots: [{
      physicalSlot: 0,
      collectionKey: viewId === "material" ? "钢材" : "训练情报",
      occupied: true,
      slotLease: "lease." + epoch + "." + viewId,
      item: {
        itemKind: "stack",
        name: viewId === "material" ? "钢材" : "训练情报",
        displayName: viewId === "material" ? "钢材" : "训练情报",
        icon: viewId === "material" ? "金钱" : "经验值",
        majorType: "",
        use: "",
        quantity: 3,
        enhancementLevel: 0,
        rarity: "",
      },
    }],
  };
}

function npcState(balance, epoch) {
  return {
    success: true,
    v: 1,
    shopId: SHOP_ID,
    balance,
    buyRatePermille: 1000,
    catalog: catalog(),
    layout: { title: SHOP_ID, defaultSection: "", sections: [] },
    views: {
      material: collectionView("材料", "material", epoch),
      intelligence: collectionView("情报", "intelligence", epoch),
    },
  };
}

function item(name, quantity, kind) {
  const itemKind = kind || "equipment";
  return {
    itemKind,
    name,
    displayName: name,
    icon: name === "砍刀" ? "砍刀" : name === PURCHASE.itemName ? PURCHASE.icon : name,
    majorType: itemKind === "equipment" ? "武器" : "",
    use: "",
    actionType: "",
    weaponType: "",
    setId: "",
    setName: "",
    setOrder: 0,
    quantity,
    enhancementLevel: itemKind === "stack" ? 0 : 1,
    maxEnhancementLevel: itemKind === "stack" ? 0 : 13,
    isMaxEnhancement: false,
    tierSlotAvailable: false,
    tierSlotUsed: false,
    modSlotCapacity: 0,
    modSlotUsed: 0,
    modSlots: [],
    modMeta: null,
    rarity: "",
  };
}

function confirm(itemValue, _epoch, slot) {
  return { itemKind: itemValue.itemKind, name: itemValue.name,
    displayName: itemValue.displayName, quantity: itemValue.quantity,
    enhancementLevel: itemValue.enhancementLevel, rarity: itemValue.rarity,
    tier: "", modSignature: "", lastUpdate: 1000 + slot };
}

function inventoryState(panelInstanceId, callId, epoch, requests, options) {
  const settings = options || {};
  const accessibleCapacity = Number(settings.battleAccessibleCapacity);
  const occupied = new Map();
  const saleQuantity = settings.saleQuantity == null ? 1 : Number(settings.saleQuantity);
  if (settings.saleSlotPresent !== false && saleQuantity > 0) {
    const value = item("砍刀", saleQuantity, settings.saleItemKind
      || (saleQuantity > 1 ? "stack" : "equipment"));
    occupied.set(0, { physicalSlot: 0, occupied: true, slotLease: "bag." + epoch + ".0",
      item: value, confirmProjection: confirm(value, epoch, 0) });
  }
  const duplicate = item("砍刀", 1);
  occupied.set(9, { physicalSlot: 9, occupied: true, slotLease: "bag." + epoch + ".9",
    item: duplicate, confirmProjection: confirm(duplicate, epoch, 9) });
  if (settings.purchased) {
    const purchased = item(PURCHASE.itemName, 1);
    occupied.set(PURCHASE_SLOT, { physicalSlot: PURCHASE_SLOT, occupied: true,
      slotLease: "bag." + epoch + "." + PURCHASE_SLOT,
      item: purchased, confirmProjection: confirm(purchased, epoch, PURCHASE_SLOT) });
  }
  const battle = new Map();
  if (accessibleCapacity > 0) {
    const tail = item("砍刀", 1);
    battle.set(accessibleCapacity - 1, { physicalSlot: accessibleCapacity - 1,
      occupied: true, slotLease: (epoch === "restart" ? "battle.restart." : "battle.first.")
        + (accessibleCapacity - 1), item: tail,
      confirmProjection: confirm(tail, epoch, accessibleCapacity - 1) });
  }
  const phase = String(epoch);
  const bagVersion = phase === "initial" ? 1 : phase === "purchase-post" ? 2 : 3;
  const restart = phase === "restart";
  function lease(containerId, physicalSlot) {
    if (containerId === "战备箱") {
      return "empty.battle." + (restart ? "restart" : "first") + "." + physicalSlot;
    }
    return "empty." + epoch + "." + containerId.length + "." + physicalSlot;
  }
  function window(request, seq) {
    const containerId = request.containerId;
    const bag = containerId === "背包";
    const values = bag ? occupied : battle;
    const capacity = bag ? 50 : 400;
    const access = bag ? 50 : accessibleCapacity;
    const actualLimit = Math.min(Number(request.limit), Math.max(0, access - Number(request.offset)));
    const slots = Array.from({ length: actualLimit }, (_unused, ordinal) => {
      const physicalSlot = Number(request.offset) + ordinal;
      return values.get(physicalSlot) || { physicalSlot, occupied: false,
        slotLease: lease(containerId, physicalSlot) };
    });
    const count = values.size;
    return { containerId, capacity, accessibleCapacity: access, viewCapacity: access,
      filterKey: "all", pageSizeHint: bag ? 50 : 40, locked: !bag && access === 0,
      snapshotSeq: seq, containerEpoch: bag ? (restart ? 110 : 100) : (restart ? 210 : 200),
      containerVersion: bag ? bagVersion : 1, offset: Number(request.offset), limit: actualLimit,
      slots, filterFacets: count
        ? [{ id: "all", label: "全部", order: 0, count, children: [] }] : [],
      filterItemCount: count, setFacets: [], setFilterItemCount: 0 };
  }
  return {
    type: "panel_resp",
    domain: "inventory",
    panel: "npcshop",
    panelInstanceId,
    cmd: "snapshot",
    callId,
    success: true,
    v: 1,
    sessionNonce: restart ? "inv.restart" : "inv.first",
    snapshots: requests.map((request, index) => window(request,
      10 + String(epoch).length + index)),
  };
}

function envelope(panelInstanceId, cmd, callId, state) {
  return Object.assign({
    type: "panel_resp",
    domain: "npcshop",
    panel: "npcshop",
    panelInstanceId,
    cmd,
    callId,
  }, state);
}

function writeJsonExclusive(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
}

let pngTable;
function crc32(bytes) {
  if (!pngTable) pngTable = Array.from({ length: 256 }, (_unused, index) => {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) value = (value & 1)
      ? (0xedb88320 ^ (value >>> 1)) : (value >>> 1);
    return value >>> 0;
  });
  let crc = 0xffffffff;
  for (const byte of bytes) crc = pngTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([length, name, data, crc]);
}

function fixturePng(index, widthValue, heightValue) {
  const width = widthValue == null ? 320 : Number(widthValue);
  const height = heightValue == null ? 180 : Number(heightValue);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const scanline = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const offset = y * (width * 4 + 1);
    scanline[offset] = 0;
    for (let x = 0; x < width; x += 1) {
      const pixel = offset + 1 + x * 4;
      scanline[pixel] = (index * 17 + x) & 255;
      scanline[pixel + 1] = (index * 31 + y) & 255;
      scanline[pixel + 2] = (x + y + index * 7) & 255;
      scanline[pixel + 3] = 255;
    }
  }
  return Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", ihdr), pngChunk("IDAT", zlib.deflateSync(scanline)),
    pngChunk("IEND", Buffer.alloc(0))]);
}

function diskManifest(slot, jsonSha256, solSha256, sourceSetSha256, capturedAt) {
  const value = { schema: "workbench-live-e2e.npc.disk-artifact-set.v1", slot, capturedAt,
    sourceSetSha256,
    artifacts: [
      { kind: "sol", locator: "appdata:fixture/#SharedObjects/npc/" + slot + ".sol",
        sha256: solSha256, bytes: 4096, regularFile: true, exactRealPath: true },
      { kind: "json", locator: "root:saves/" + slot + ".json",
        sha256: jsonSha256, bytes: 19867, regularFile: true, exactRealPath: true },
    ].sort((left, right) => left.locator.localeCompare(right.locator)) };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function residueSnapshot(runDir, candidate, pid, controlPort, socketPort, cdpPort, observedAt) {
  const value = { schema: LauncherObservation.RESIDUE_SCHEMA,
    apiVersion: LauncherObservation.API_VERSION, observedAt,
    expectedPid: pid, expectedProcessPath: candidate.stableIdentity.processPath,
    pidAbsent: true, candidateProcessAbsent: true, observedLauncherPids: [],
    ports: [controlPort, socketPort, cdpPort].map((port) => ({ port, open: false })),
    portsFile: path.join(runDir, "fixture-runtime", String(pid), "ports.json"),
    portsFileAbsent: true,
    credentialFile: path.join(runDir, "fixture-runtime", String(pid), "credential.json"),
    credentialFileAbsent: true,
    stableSamples: 3 };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function buildFixtureCandidate(runDir, productionClosure) {
  const candidateRoot = path.join(runDir, "fixture-candidate");
  const launcherRelative = "CRAZYFLASHER7MercenaryEmpire.exe";
  const launcherPath = path.join(candidateRoot, launcherRelative);
  const coreRelative = "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe";
  const corePath = path.join(candidateRoot, coreRelative);
  fs.mkdirSync(path.dirname(corePath), { recursive: true });
  const launcherBytes = Buffer.from("NPC A3 offline fixture candidate launcher\n", "utf8");
  const coreBytes = Buffer.from("NPC A3 offline fixture candidate core\n", "utf8");
  fs.writeFileSync(launcherPath, launcherBytes, { flag: "wx" });
  fs.writeFileSync(corePath, coreBytes, { flag: "wx" });
  const payloadFiles = [
    { path: launcherRelative, size: launcherBytes.length,
      sha256: sha256Bytes(launcherBytes).toUpperCase() },
    { path: coreRelative, size: coreBytes.length,
      sha256: sha256Bytes(coreBytes).toUpperCase() },
  ].sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  const runtimeInputs = productionClosure.runtimeInputs.domains;
  const artifactSourceHash = runtimeInputs.artifactSource.sha256;
  const producerRecipeHash = runtimeInputs.producerRecipe.sha256;
  const toolchainLockHash = runtimeInputs.toolchainLock.sha256;
  const buildIdentityHash = ProductionClosure.computeBuildIdentityHash(
    artifactSourceHash, producerRecipeHash, toolchainLockHash);
  const payloadClosureHash = ProductionClosure.canonicalPayloadClosureHash(payloadFiles);
  const metadata = {
    schema: "cf7-runtime-candidate-metadata.v2",
    builderLabel: "npc-a3-offline-fixture",
    artifactSourceHash,
    producerRecipeHash,
    toolchainLockHash,
    buildIdentityHash,
    payloadClosureHash,
    createdAtUtc: iso(0),
  };
  writeJsonExclusive(path.join(candidateRoot, "runtime-build-metadata.v2.json"), metadata);
  const manifest = ["cf7-runtime-manifest-v2",
    "publishMode\tFrameworkDependent",
    "artifactSourceHash\t" + artifactSourceHash,
    "producerRecipeHash\t" + producerRecipeHash,
    "toolchainLockHash\t" + toolchainLockHash,
    "toolchainBaseline\tnpc-a3-offline-fixture",
    "buildIdentityHash\t" + buildIdentityHash,
    "payloadClosureHash\t" + payloadClosureHash,
  ].concat(payloadFiles.map((entry) => "file\t" + entry.path + "\t" + entry.size
    + "\t" + entry.sha256)).join("\n") + "\n";
  fs.writeFileSync(path.join(candidateRoot, "runtime", "cf7-runtime-manifest.tsv"),
    manifest, { encoding: "utf8", flag: "wx" });
  return { candidateRoot, stableIdentity: {
    runtimeMode: "isolated_candidate",
    processPath: corePath,
    coreSha256: payloadFiles.find((entry) => entry.path === coreRelative).sha256,
    buildIdentity: buildIdentityHash,
    payloadClosure: payloadClosureHash,
  } };
}

function buildValidFixture(runDir, options) {
  const settings = Object.assign({ launcherAvailable: false, purchaseOnly: false,
    salePreQuantity: 1, battleAccessibleCapacity: 240 }, options || {});
  if (![0, 40, 80, 120, 160, 200, 240].includes(Number(settings.battleAccessibleCapacity))) {
    throw new Error("fixture battleAccessibleCapacity must be a production 40-slot tier");
  }
  fs.mkdirSync(runDir, { recursive: true });
  const rawEvents = [];
  const hostRecords = { first: [], restart: [] };
  const controlSpecs = [];
  const calls = {};
  let eventSecond = 1;
  let hostLifecycle = "first";
  const hostLine = { first: 1, restart: 1 };
  const hostClockMs = { first: 1000, restart: 52000 };
  let webCall = 0;
  let npcFid = 300;
  let inventoryFid = 600;

  function authorityTail(value) {
    const fields = authorityProjection(value);
    return Object.keys(fields).map((key) => " " + key + "=" + fields[key]).join("");
  }

  function emit(raw) {
    const event = Object.assign({ observedAt: iso(eventSecond) }, raw);
    eventSecond += 0.5;
    rawEvents.push(event);
    return { event, sequence: rawEvents.length };
  }

  function host(body) {
    hostClockMs[hostLifecycle] = Math.max(hostClockMs[hostLifecycle] + 1,
      Math.max(0, eventSecond - 0.5) * 1000 + 100);
    const timestamp = new Date(Date.UTC(2000, 0, 1) + hostClockMs[hostLifecycle])
      .toISOString().slice(11, 23);
    const record = { lineNumber: hostLine[hostLifecycle]++, body,
      line: timestamp + " " + body };
    hostRecords[hostLifecycle].push(record);
    return record;
  }

  function beginControl(step, actionClass, allowedTransports) {
    return {
      step,
      actionClass,
      allowedTransports,
      prefixCount: rawEvents.length,
      events: [],
    };
  }

  function finishControl(spec, boundEntries) {
    spec.events = (boundEntries || []).map((entry) => ({
      sequence: entry.sequence,
      role: entry.role,
    }));
    controlSpecs.push(spec);
  }

  function ingress(source) {
    host("[XmlSocket:JSON] " + JSON.stringify({
      task: "panel_request",
      panel: "npcshop",
      source,
      initData: { shopId: SHOP_ID },
    }));
  }

  function hostMap(request) {
    const inventory = request.domain === "inventory";
    host("[Panel] HandlePanelMessage: task=panel panel=npcshop domain=" + request.domain
      + " cmd=" + request.cmd + " callId=" + request.callId + " payload=redacted len="
      + JSON.stringify(request).length + authorityTail(request));
    host(inventory
      ? "[Panel] Routing domain=inventory cmd=" + request.cmd + " to InventoryTask, _inventoryTask=ok"
      : "[Panel] Routing domain=npcshop cmd=" + request.cmd + " to NpcShopTask, _npcShopTask=ok");
    const fid = inventory ? ++inventoryFid : ++npcFid;
    const action = inventory ? "inventorySnapshot" : ({
      snapshot: "npcShopSnapshot",
      tradePreview: "npcShopTradePreview",
      tradeCommit: "npcShopTradeCommit",
    })[request.cmd];
    host("event=authority_flash_call_bound domain=" + request.domain
      + " webCallId=" + request.callId + " flashCallId=" + fid
      + " panel=npcshop panelInstanceId=" + request.panelInstanceId
      + " cmd=" + request.cmd + " action=" + action);
    host((inventory ? "[InventoryTask] -> Flash:" : "[NpcShopTask] -> Flash:")
      + " task=cmd cmd=" + action + " callId=" + fid + " payload=redacted len="
      + JSON.stringify(Object.assign({ task: "cmd", action, callId: fid }, request.payload)).length
      + authorityTail(request.payload));
    return { fid, action, task: inventory ? "inventory_response" : "npcshop_response" };
  }

  function request(panelInstanceId, domain, cmd, payload, response) {
    const callId = "npc.fixture." + (++webCall);
    const message = { type: "panel", domain, panel: "npcshop", panelInstanceId, cmd, callId, payload };
    const outbound = emit({ kind: "bridge_send", direction: "outbound",
      sendOrder: "after_panel_request_mux_onIssued", message });
    const mapping = hostMap(message);
    const inboundMessage = typeof response === "function" ? response(callId) : response;
    host("[XmlSocket:JSON] task=" + mapping.task + " cmd=" + mapping.action
      + " callId=" + mapping.fid + " success=" + (inboundMessage.success === true ? "true" : "false")
      + " payload=redacted len=" + JSON.stringify(inboundMessage).length
      + authorityTail(inboundMessage));
    const inbound = emit({ kind: "webview_message", direction: "inbound", message: inboundMessage });
    return { callId, outbound, inbound, request: message, response: inboundMessage };
  }

  function inventoryPhase(panelInstanceId, epoch, options) {
    const accessible = Number(settings.battleAccessibleCapacity);
    const batches = [[
      { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
      { containerId: "战备箱", offset: 0, limit: 100, filterKey: "all" },
    ]];
    if (accessible > 100) batches.push([
      { containerId: "战备箱", offset: 100, limit: 100, filterKey: "all" },
    ]);
    if (accessible > 200) batches.push([
      { containerId: "战备箱", offset: 200, limit: accessible - 200, filterKey: "all" },
    ]);
    return batches.map((requests) => request(panelInstanceId, "inventory", "snapshot",
      { v: 1, requests }, (callId) => inventoryState(panelInstanceId, callId, epoch,
        requests, Object.assign({}, options, { battleAccessibleCapacity: accessible }))));
  }

  function open(step, instanceId, source) {
    const selectedTransport = settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use";
    const control = beginControl(step, "business", [selectedTransport]);
    ingress(source);
    host("[PanelHost] opened: npcshop rect=1280x720");
    const opened = emit({
      kind: "webview_message",
      direction: "inbound",
      message: {
        type: "panel_cmd",
        cmd: "open",
        panel: "npcshop",
        panelInstanceId: instanceId,
        initData: { shopId: SHOP_ID, panelInstanceId: instanceId },
      },
    });
    finishControl(control, [{ sequence: opened.sequence, role: "panel_open" }]);
    return opened;
  }

  function dom(selector, tagName, attributes, text, eventType) {
    const type = eventType || "click";
    const pointer = type === "click";
    return emit({
      kind: "dom_input",
      direction: "input",
      eventType: type,
      isTrusted: true,
      button: pointer ? 0 : undefined,
      clientX: pointer ? 190 : null,
      clientY: pointer ? 104 : null,
      target: { selector, tagName, attributes, text, visible: true, enabled: true,
        origin: "https://overlay.local",
        rect: { x: 100, y: 80, width: 180, height: 48 },
        clientPoint: pointer ? { x: 190, y: 104 } : null,
        clientPointSource: pointer ? "event" : "not_applicable",
        hitTest: pointer ? { tagName, matchesTarget: true } : null,
        viewport: { width: 1280, height: 720 } },
      panelState: { panel: "npcshop", hidden: false },
    });
  }

  function close(step, instanceId) {
    const selectedTransport = settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use";
    const control = beginControl(step, "business", [selectedTransport]);
    const input = dom("button[aria-label=\"关闭 NPC 商店\"]", "BUTTON",
      { "aria-label": "关闭 NPC 商店", class: "workbench-close-btn" }, "×");
    const outbound = emit({ kind: "bridge_send", direction: "outbound", message: {
      type: "panel", panel: "npcshop", panelInstanceId: instanceId, cmd: "close",
    } });
    host("[Panel] HandlePanelMessage: task=panel panel=npcshop domain=none cmd=close callId=none payload=redacted len=96");
    host("[PanelHost] closed: npcshop");
    host("event=panel_exact_close_completed panel=npcshop panelInstanceId=" + instanceId);
    finishControl(control, [
      { sequence: input.sequence, role: "panel_close" },
      { sequence: outbound.sequence, role: "panel_close" },
    ]);
    return outbound;
  }

  emit({ kind: "cdp_endpoint_bound", cdpPort: 41001, runtimePid: 1111,
    exclusiveBeforeLaunch: true, pageUrl: "https://overlay.local/overlay.html" });
  emit({ kind: "observer_ready", url: "https://overlay.local/overlay.html",
    bridgeWrapped: true, webviewObserved: true });
  const probe = beginControl("capability_probe", "capability_probe", ["launcher_agent_runtime"]);
  finishControl(probe, []);
  if (!settings.launcherAvailable) {
    const fallback = beginControl("authorize_codex_fallback", "authorization", ["codex_computer_use"]);
    finishControl(fallback, []);
  }

  open("open_first", INSTANCES.first, "world_npc_dialogue");
  const initialInv = inventoryPhase(INSTANCES.first, "initial", {
    purchased: false,
    saleQuantity: settings.salePreQuantity,
  });
  calls.initialInventorySnapshots = initialInv.map((entry) => entry.callId);
  calls.initialInventorySnapshot = calls.initialInventorySnapshots[0];
  const initialNpc = request(INSTANCES.first, "npcshop", "snapshot", { v: 1, shopId: SHOP_ID },
    (callId) => envelope(INSTANCES.first, "snapshot", callId, npcState(1000, "initial")));
  calls.initialNpcSnapshot = initialNpc.callId;

  const purchaseSelectControl = beginControl("select_purchase", "business",
    [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
  const purchaseSelect = dom("article[data-workbench-key=\"" + PURCHASE.catalogIndex + "\"]",
    "ARTICLE", { "data-workbench-key": String(PURCHASE.catalogIndex),
      class: "item-card npcshop-card" }, PURCHASE.displayName);
  finishControl(purchaseSelectControl, [{ sequence: purchaseSelect.sequence, role: "dom_input" }]);

  const purchaseCheckoutControl = beginControl("open_purchase_settlement", "business",
    [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
  const purchaseCheckout = dom("button.npcshop-checkout-btn", "BUTTON",
    { class: "workbench-mode-btn npcshop-checkout-btn", type: "button" }, "结算 (1)");
  const purchaseToken = tokenRef("fixture.purchase.token");
  const purchasePreview = request(INSTANCES.first, "npcshop", "tradePreview", {
    v: 1,
    shopId: SHOP_ID,
    purchases: [{ catalogIndex: PURCHASE.catalogIndex, quantity: 1 }],
    sales: [],
  }, (callId) => envelope(INSTANCES.first, "tradePreview", callId, {
    success: true,
    v: 1,
    shopId: SHOP_ID,
    tradeToken: purchaseToken,
    purchaseLines: [{
      catalogIndex: PURCHASE.catalogIndex,
      itemName: PURCHASE.itemName,
      displayName: PURCHASE.displayName,
      icon: PURCHASE.icon,
      quantity: 1,
      unitPrice: PURCHASE.unitPrice,
      total: PURCHASE.unitPrice,
      maxQuantity: 1,
      purchaseLimit: 1,
      maxAffordable: 1,
      maxByCapacity: 1,
      maxPurchasable: 1,
      limitingReason: "",
      itemKind: "equipment",
      destinationView: "bag",
    }],
    saleLines: [],
    buyTotal: PURCHASE.unitPrice,
    sellTotal: 0,
    netDelta: -PURCHASE.unitPrice,
    projectedBalance: 900,
    requiredSlots: 1,
    availableSlots: 48,
    missingSlots: 0,
    canCommit: true,
    blockingError: "",
  }));
  calls.purchasePreview = purchasePreview.callId;
  finishControl(purchaseCheckoutControl, [
    { sequence: purchaseCheckout.sequence, role: "domain_request" },
    { sequence: purchasePreview.outbound.sequence, role: "domain_request" },
  ]);

  const purchaseCommitControl = beginControl("commit_purchase", "business",
    [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
  const purchaseCommitInput = dom("button[data-trade-commit]", "BUTTON",
    { "data-trade-commit": "", type: "button" }, "确认交易");
  const purchaseCommit = request(INSTANCES.first, "npcshop", "tradeCommit", {
    v: 1,
    shopId: SHOP_ID,
    expectedTradeToken: purchaseToken,
  }, (callId) => envelope(INSTANCES.first, "tradeCommit", callId, Object.assign(
    npcState(900, "purchase-commit"), {
      operation: "tradeCommit",
      trade: { buyTotal: 100, sellTotal: 0, netDelta: -100 },
    })));
  calls.purchaseCommit = purchaseCommit.callId;
  finishControl(purchaseCommitControl, [
    { sequence: purchaseCommitInput.sequence, role: "domain_write" },
    { sequence: purchaseCommit.outbound.sequence, role: "domain_write" },
  ]);
  const purchasePostInv = inventoryPhase(INSTANCES.first, "purchase-post", {
    purchased: true,
    saleQuantity: settings.salePreQuantity,
    saleItemKind: settings.salePreQuantity > 1 ? "stack" : "equipment",
  });
  calls.purchasePostInventories = purchasePostInv.map((entry) => entry.callId);
  calls.purchasePostInventory = calls.purchasePostInventories[0];
  if (!settings.purchaseOnly) {
    const saleSelectControl = beginControl("select_sale", "business",
      [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
    const saleSelect = dom("article[data-workbench-key=\"0\"]", "ARTICLE",
      { "data-workbench-key": "0", class: "inventory-slot-card npcshop-owned-card" }, "砍刀");
    finishControl(saleSelectControl, [{ sequence: saleSelect.sequence, role: "dom_input" }]);
    const saleCheckoutControl = beginControl("open_sale_settlement", "business",
      [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
    const saleCheckout = dom("button.npcshop-checkout-btn", "BUTTON",
      { class: "workbench-mode-btn npcshop-checkout-btn", type: "button" }, "结算 (1)");
    calls.salePreviews = [];
    const preliminaryToken = tokenRef("fixture.sale.preliminary");
    const salePreview = request(INSTANCES.first, "npcshop", "tradePreview", {
      v: 1,
      shopId: SHOP_ID,
      purchases: [],
      sales: [{
        source: { containerId: "背包", slot: 0, expectedLease: "bag.purchase-post.0" },
        quantity: settings.salePreQuantity,
        scope: "slot",
      }],
    }, (callId) => envelope(INSTANCES.first, "tradePreview", callId, {
      success: true,
      v: 1,
      shopId: SHOP_ID,
      tradeToken: preliminaryToken,
      purchaseLines: [],
      saleLines: [{
        itemName: "砍刀", displayName: "砍刀", icon: "砍刀",
        itemKind: settings.salePreQuantity > 1 ? "stack" : "equipment",
        quantity: settings.salePreQuantity, total: 50 * settings.salePreQuantity, sourceIdentity: "bag:0", scope: "slot",
        matchedCount: 1, eligibleCount: 1, protectedCount: 0,
      }],
      buyTotal: 0,
      sellTotal: 50 * settings.salePreQuantity,
      netDelta: 50 * settings.salePreQuantity,
      projectedBalance: 900 + 50 * settings.salePreQuantity,
      requiredSlots: 0,
      availableSlots: 48,
      missingSlots: 0,
      canCommit: true,
      blockingError: "",
    }));
    calls.salePreviews.push(salePreview.callId);
    finishControl(saleCheckoutControl, [
      { sequence: saleCheckout.sequence, role: "domain_request" },
      { sequence: salePreview.outbound.sequence, role: "domain_request" },
    ]);
    let finalSalePreview = salePreview;
    if (settings.salePreQuantity > 1) {
      const quantityControl = beginControl("set_sale_quantity", "business",
        [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
      const quantityInput = dom("input.workbench-quantity-number", "INPUT",
        { class: "workbench-quantity-number", "aria-label": "输入数量", type: "number",
          min: "1", max: String(settings.salePreQuantity), value: "1" }, "", "input");
      const finalToken = tokenRef("fixture.sale.final");
      finalSalePreview = request(INSTANCES.first, "npcshop", "tradePreview", {
        v: 1,
        shopId: SHOP_ID,
        purchases: [],
        sales: [{
          source: { containerId: "背包", slot: 0, expectedLease: "bag.purchase-post.0" },
          quantity: 1,
          scope: "slot",
        }],
      }, (callId) => envelope(INSTANCES.first, "tradePreview", callId, {
        success: true,
        v: 1,
        shopId: SHOP_ID,
        tradeToken: finalToken,
        purchaseLines: [],
        saleLines: [{ itemName: "砍刀", displayName: "砍刀", icon: "砍刀", itemKind: "stack",
          quantity: 1, total: 50, sourceIdentity: "bag:0", scope: "slot",
          matchedCount: 1, eligibleCount: 1, protectedCount: 0 }],
        buyTotal: 0, sellTotal: 50, netDelta: 50, projectedBalance: 950,
        requiredSlots: 0, availableSlots: 47, missingSlots: 0, canCommit: true, blockingError: "",
      }));
      calls.salePreviews.push(finalSalePreview.callId);
      finishControl(quantityControl, [
        { sequence: quantityInput.sequence, role: "domain_request" },
        { sequence: finalSalePreview.outbound.sequence, role: "domain_request" },
      ]);
    }
    const saleCommitControl = beginControl("commit_sale", "business",
      [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
    const saleCommitInput = dom("button[data-trade-commit]", "BUTTON",
      { "data-trade-commit": "", type: "button" }, "确认交易");
    const saleCommit = request(INSTANCES.first, "npcshop", "tradeCommit", {
      v: 1,
      shopId: SHOP_ID,
      expectedTradeToken: finalSalePreview.response.tradeToken,
    }, (callId) => envelope(INSTANCES.first, "tradeCommit", callId, Object.assign(
      npcState(950, "sale-commit"), {
        operation: "tradeCommit",
        trade: { buyTotal: 0, sellTotal: 50, netDelta: 50 },
      })));
    calls.saleCommit = saleCommit.callId;
    finishControl(saleCommitControl, [
      { sequence: saleCommitInput.sequence, role: "domain_write" },
      { sequence: saleCommit.outbound.sequence, role: "domain_write" },
    ]);
    const salePostInv = inventoryPhase(INSTANCES.first, "sale-post",
      { purchased: true, saleQuantity: settings.salePreQuantity - 1,
        saleItemKind: settings.salePreQuantity > 1 ? "stack" : "equipment" });
    calls.salePostInventories = salePostInv.map((entry) => entry.callId);
    calls.salePostInventory = calls.salePostInventories[0];
  } else {
    calls.salePreviews = [];
    calls.salePostInventories = [];
  }
  close("close_before_exit", INSTANCES.first);
  const firstObserverDetached = emit({ kind: "observer_detached",
    pageUrl: "https://overlay.local/overlay.html" });

  const safeExitControl = beginControl("safe_exit", "lifecycle",
    [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
  hostClockMs.first = Math.max(hostClockMs.first, 41000);
  const sv1 = host("sv:1");
  const sv2 = host("sv:2");
  const archivePath = "C:\\fixture\\resources\\saves\\" + SLOT + ".json";
  const archive = host("[ArchiveTask] Shadow saved: " + SLOT + " (19867 chars) path=" + archivePath);
  finishControl(safeExitControl, []);
  const exitConfirmControl = beginControl("exit_confirm", "lifecycle",
    [settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use"]);
  finishControl(exitConfirmControl, []);
  eventSecond = Math.max(eventSecond, 61);
  emit({ kind: "cdp_endpoint_bound", cdpPort: 41002, runtimePid: 2222,
    exclusiveBeforeLaunch: true, pageUrl: "https://overlay.local/overlay.html" });
  emit({ kind: "observer_ready", url: "https://overlay.local/overlay.html",
    bridgeWrapped: true, webviewObserved: true });
  hostLifecycle = "restart";
  open("open_restart_readback", INSTANCES.restart, "tablet_contacts");
  const restartBalance = settings.purchaseOnly ? 900 : 950;
  const restartInv = inventoryPhase(INSTANCES.restart, "restart", {
    purchased: true,
    saleQuantity: settings.purchaseOnly ? settings.salePreQuantity : settings.salePreQuantity - 1,
    saleItemKind: settings.salePreQuantity > 1 ? "stack" : "equipment",
  });
  calls.restartInventorySnapshots = restartInv.map((entry) => entry.callId);
  calls.restartInventorySnapshot = calls.restartInventorySnapshots[0];
  const restartNpc = request(INSTANCES.restart, "npcshop", "snapshot", { v: 1, shopId: SHOP_ID },
    (callId) => envelope(INSTANCES.restart, "snapshot", callId, npcState(restartBalance, "restart")));
  calls.restartNpcSnapshot = restartNpc.callId;
  close("close_restart_readback", INSTANCES.restart);
  emit({ kind: "observer_detached", pageUrl: "https://overlay.local/overlay.html" });

  const transcript = sealEvents(rawEvents);
  const artifacts = [];
  function addArtifact(relativePath, role, bytes) {
    const target = path.join(runDir, relativePath);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, bytes, { flag: "wx" });
    artifacts.push({ path: relativePath.replace(/\\/g, "/"), role, bytes: fs.statSync(target).size, sha256: sha256File(target) });
    return relativePath.replace(/\\/g, "/");
  }
  const transcriptArtifact = addArtifact("evidence/passive-transcript.json", "passive_transcript",
    Buffer.from(JSON.stringify(transcript, null, 2) + "\n", "utf8"));
  function logSnapshot(label, records, pid, ticks, capturedAt) {
    const normalized = records.map((record) => ({ lineNumber: record.lineNumber, line: record.line }));
    const digest = { schema: LauncherObservation.LOG_SNAPSHOT_SCHEMA, requestedTailLimit: 2000,
      sessionEvidenceSha256: sha256Text("fixture-session-" + label),
      lifecycleId: "fixture_" + label + "_lifecycle", sessionPid: pid,
      sessionProcessStartUtcTicks: ticks, total: normalized.length,
      oldestLineNumber: normalized.length ? 1 : 1, records: normalized };
    return Object.assign({}, digest, { capturedAt, tailSha256: sha256Text(canonicalJson(digest)) });
  }
  function hostLifecycleEvidence(label, records, pid, ticks, settledAt, terminalAt, safeExitBoundaryAt) {
    const start = logSnapshot(label, [], pid, ticks, iso(0));
    const completion = "event=panel_exact_close_completed panel=npcshop panelInstanceId="
      + INSTANCES[label];
    const completionIndex = records.findIndex((record) => record.body === completion);
    if (completionIndex < 0) throw new Error("fixture close completion is absent: " + label);
    const settled = logSnapshot(label, records.slice(0, completionIndex + 1),
      pid, ticks, settledAt);
    const boundaries = {};
    if (safeExitBoundaryAt) {
      boundaries.safe_exit_provider_completed = LauncherObservation.createTerminalLogBoundary(
        logSnapshot(label, records.slice(0, completionIndex + 1), pid, ticks, safeExitBoundaryAt));
    }
    return { startBoundary: LauncherObservation.createTerminalLogBoundary(start),
      closeSettledSnapshot: settled,
      terminalSnapshot: logSnapshot(label, records, pid, ticks, terminalAt),
      timelineBoundaries: boundaries };
  }
  const seedDiskManifest = diskManifest("cf7_agent_a3_kshop", "a".repeat(64),
    "b".repeat(64), "c".repeat(64), iso(0));
  const seedManifest = { slot: "cf7_agent_a3_kshop", jsonSha256: "a".repeat(64),
    solSetSha256: sha256Text(canonicalJson(seedDiskManifest.artifacts.filter((entry) =>
      entry.kind === "sol"))),
    solFiles: seedDiskManifest.artifacts.filter((entry) => entry.kind === "sol"),
    artifactSetSha256: "c".repeat(64), manifest: seedDiskManifest };
  const seedBeforeArtifact = addArtifact("evidence/seed-before.json", "seed_manifest",
    Buffer.from(JSON.stringify(seedManifest, null, 2) + "\n", "utf8"));
  const seedAfterArtifact = addArtifact("evidence/seed-after.json", "seed_manifest",
    Buffer.from(JSON.stringify(seedManifest, null, 2) + "\n", "utf8"));

  const selectedTransport = settings.launcherAvailable ? "launcher_agent_runtime" : "codex_computer_use";
  const controls = [];
  const controlTimes = new Map();
  let previousControlCompletedMs = Date.parse(iso(0));
  controlSpecs.forEach((spec, index) => {
    const requestId = "npc-control-" + String(index + 1).padStart(2, "0") + "-" + spec.step;
    const issuedBase = spec.prefixCount === 0 ? Date.parse(iso(0))
      : Date.parse(rawEvents[spec.prefixCount - 1].observedAt);
    let issuedAt = new Date(Math.max(issuedBase + 10,
      previousControlCompletedMs + 10)).toISOString();
    if (spec.step === "exit_confirm") issuedAt = iso(50, 100);
    const expiresAt = new Date(Date.parse(issuedAt) + 120000).toISOString();
    const requestValue = {
      schema: CONTROL_REQUEST_SCHEMA,
      runId: RUN_ID,
      requestId,
      step: spec.step,
      actionClass: spec.actionClass,
      allowedTransports: spec.allowedTransports,
      issuedAt,
      expiresAt,
      ttlMs: 120000,
      nonce: "nonce." + index,
      transcriptPrefix: {
        eventCount: spec.prefixCount,
        chainHead: spec.prefixCount === 0 ? "0".repeat(64) : transcript.events[spec.prefixCount - 1].eventHash,
      },
      instruction: "fixture " + spec.step,
      captureRequired: true,
      expected: spec.step === "select_purchase" ? JSON.parse(JSON.stringify(PURCHASE))
        : spec.step === "select_sale" ? {
          explicitAllowlist: true, containerId: "背包", slot: 0, expectedItem: "砍刀",
          expectedPreQuantity: settings.salePreQuantity,
          expectedLease: "bag.purchase-post.0", quantity: 1,
          requiresQuantityAdjustment: settings.salePreQuantity > 1,
        } : null,
    };
    const requestArtifact = "controls/requests/" + requestId + ".json";
    const requestPath = path.join(runDir, requestArtifact);
    writeJsonExclusive(requestPath, requestValue);
    artifacts.push({ path: requestArtifact, role: "control_request", bytes: fs.statSync(requestPath).size, sha256: sha256File(requestPath) });
    const captureArtifact = "controls/captures/" + requestId + ".png";
    addArtifact(captureArtifact, "control_capture", fixturePng(index + 1));
    let result = "completed";
    let transport = selectedTransport;
    let details = {};
    if (spec.step === "capability_probe") {
      result = settings.launcherAvailable ? "completed" : "unavailable";
      transport = "launcher_agent_runtime";
      details = settings.launcherAvailable ? { capabilities: ["npc_input"] }
        : { reasonCode: "npc_input_not_exposed" };
    } else if (spec.step === "authorize_codex_fallback") {
      transport = "codex_computer_use";
      details = {
        explicitAuthorization: true,
        capabilityRequestId: controls[0].requestId,
        capabilityReasonCode: "npc_input_not_exposed",
      };
    }
    const lastBound = spec.events.reduce((maximum, entry) => Math.max(maximum, entry.sequence), spec.prefixCount);
    const lastBoundObserved = lastBound > 0
      ? Date.parse(rawEvents[lastBound - 1].observedAt) : Date.parse(issuedAt);
    const providerArtifact = "controls/provider-receipts/" + requestId + ".json";
    const capturePath = path.join(runDir, captureArtifact);
    const captureSha256 = sha256File(capturePath);
    const captureBytes = fs.statSync(capturePath).size;
    const boundDom = spec.events.map((entry) => transcript.events[entry.sequence - 1])
      .filter((event) => event && event.kind === "dom_input");
    if (boundDom.length > 1) throw new Error("fixture control owns multiple DOM inputs: " + spec.step);
    const issuedMs = Date.parse(issuedAt);
    const firstBoundObserved = spec.events.length > 0
      ? Date.parse(rawEvents[spec.events[0].sequence - 1].observedAt) : null;
    let startedMs = issuedMs + 10;
    let inputMs = boundDom.length === 1 ? Date.parse(boundDom[0].observedAt)
      : firstBoundObserved == null ? issuedMs + 20
        : Math.max(issuedMs + 20, firstBoundObserved - 10);
    if (!(issuedMs < startedMs && startedMs < inputMs)
        || firstBoundObserved != null && boundDom.length === 0 && inputMs >= firstBoundObserved) {
      throw new Error("fixture control stage window is too narrow: " + spec.step);
    }
    const boundSettlementMs = spec.events.length > 0 ? 200 : 10;
    const terminalStageMs = spec.events.length > 0 ? 100 : 10;
    let captureMs = Math.max(inputMs + 10, lastBoundObserved + boundSettlementMs);
    let providerCompletedMs = captureMs + terminalStageMs;
    let ackCompletedMs = providerCompletedMs + terminalStageMs;
    if (spec.step === "safe_exit") {
      ackCompletedMs = Date.parse(iso(40));
      providerCompletedMs = ackCompletedMs - 100;
      captureMs = providerCompletedMs - 100;
      inputMs = captureMs - 100;
      startedMs = inputMs - 100;
    }
    if (spec.step === "exit_confirm") {
      ackCompletedMs = Date.parse(iso(51));
      providerCompletedMs = ackCompletedMs - 100;
      captureMs = providerCompletedMs - 100;
      inputMs = captureMs - 100;
      startedMs = inputMs - 100;
    }
    const startedAt = new Date(startedMs).toISOString();
    const inputAt = new Date(inputMs).toISOString();
    const captureAt = new Date(captureMs).toISOString();
    const providerCompletedAt = new Date(providerCompletedMs).toISOString();
    const completedAt = new Date(ackCompletedMs).toISOString();
    previousControlCompletedMs = ackCompletedMs;
    controlTimes.set(spec.step, { issuedAt, startedAt, inputAt, captureAt,
      providerCompletedAt, completedAt });
    let inputEvidence;
    if (boundDom.length === 1) {
      inputEvidence = domInputEvidence(transcript.observerId, boundDom[0]);
    } else if (["capability_probe", "authorize_codex_fallback"].includes(spec.step)) {
      inputEvidence = {
        kind: "non_input_operation", observedAt: inputAt,
        eventRef: null, eventType: "provider_operation",
        isTrusted: null, selector: null, tagName: null, origin: null,
        visible: null, enabled: null, viewport: null, rect: null, clientPoint: null,
        hitTargetMatches: null, key: null, button: null, repeat: false,
      };
    } else {
      inputEvidence = {
        kind: "native_input", observedAt: inputAt,
        eventRef: null, eventType: "click", isTrusted: true,
        selector: "native-control[data-step=\"" + spec.step + "\"]", tagName: "BUTTON",
        origin: "launcher://native", visible: true, enabled: true,
        viewport: { width: 1280, height: 720 },
        rect: { x: 96, y: 72, width: 240, height: 56 },
        clientPoint: { x: 216, y: 100 }, hitTargetMatches: true,
        key: null, button: 0, repeat: false,
      };
    }
    const providerValue = {
      schema: PROVIDER_RECEIPT_SCHEMA,
      runId: RUN_ID,
      requestId,
      requestSha256: sha256File(requestPath),
      requestBytes: fs.statSync(requestPath).size,
      step: spec.step,
      transport,
      issuer: transport,
      toolResultSource: transport === "launcher_agent_runtime"
        ? "launcher_agent_runtime_tool_result" : "codex_computer_use_tool_result",
      providerOperationId: "pending",
      action: spec.step,
      result,
      startedAt,
      inputAt,
      captureAt,
      completedAt: providerCompletedAt,
      inputEvidence,
      ownedArtifact: providerArtifact,
      captureArtifact,
      captureSha256,
      captureBytes,
      captureWidth: 320,
      captureHeight: 180,
      details,
    };
    providerValue.providerOperationId = expectedProviderOperationId(providerValue);
    providerValue.receiptSha256 = sha256Text(canonicalJson(providerValue));
    addArtifact(providerArtifact, "provider_receipt",
      Buffer.from(JSON.stringify(providerValue, null, 2) + "\n", "utf8"));
    const ackValue = {
      schema: CONTROL_ACK_SCHEMA,
      runId: RUN_ID,
      requestId,
      requestSha256: sha256File(requestPath),
      step: spec.step,
      transport,
      result,
      completedAt,
      capture: { artifact: captureArtifact, sha256: captureSha256 },
      providerReceipt: { artifact: providerArtifact,
        sha256: sha256File(path.join(runDir, providerArtifact)) },
    };
    const ackArtifact = "controls/acks/" + requestId + ".json";
    const ackPath = path.join(runDir, ackArtifact);
    writeJsonExclusive(ackPath, ackValue);
    artifacts.push({ path: ackArtifact, role: "control_ack", bytes: fs.statSync(ackPath).size, sha256: sha256File(ackPath) });
    controls.push({
      step: spec.step,
      requestId,
      requestArtifact,
      ackArtifact,
      events: spec.events.map((entry) => ({
        sequence: entry.sequence,
        eventHash: transcript.events[entry.sequence - 1].eventHash,
        role: entry.role,
      })),
    });
  });

  const hostLog = { schema: "workbench-live-e2e.npc.host-evidence.v4", utcOffsetMinutes: 0,
    lifecycles: {
    first: hostLifecycleEvidence("first", hostRecords.first, 1111, "638900000000000001",
      new Date(Date.parse(controlTimes.get("close_before_exit").completedAt) + 5).toISOString(),
      iso(50), iso(40, 500)),
    restart: hostLifecycleEvidence("restart", hostRecords.restart, 2222, "638900000000000002",
      new Date(Date.parse(controlTimes.get("close_restart_readback").completedAt) + 5).toISOString(),
      iso(75)),
    } };
  const hostLogArtifact = addArtifact("evidence/host-log.json", "host_log",
    Buffer.from(JSON.stringify(hostLog, null, 2) + "\n", "utf8"));

  const full = !settings.purchaseOnly;
  const repositoryRoot = path.resolve(__dirname, "..", "..", "..", "..");
  const productionClosure = ProductionClosure.captureProductionClosure(repositoryRoot, iso(0));
  const fixtureCandidate = buildFixtureCandidate(runDir, productionClosure);
  const stableIdentity = fixtureCandidate.stableIdentity;
  const candidateProducer = ProductionClosure.captureCandidateProducerBinding(
    fixtureCandidate.candidateRoot, stableIdentity, productionClosure);
  const postRestartProductionClosure = ProductionClosure.captureProductionClosure(repositoryRoot, iso(75, 900));
  const productionBinding = ProductionClosure.bindProductionClosure(
    productionClosure, stableIdentity, RUN_ID, candidateProducer);
  const actualShopBinding = ProductionClosure.bindActualShop(
    repositoryRoot, productionClosure, SHOP_ID);
  function loadedProduction(lifecycle, pid, capturedAt) {
    const expected = ProductionClosure.webFiles(productionClosure);
    const page = expected.find((entry) => entry.role === "page");
    const scripts = expected.filter((entry) => ["overlay_boot_web", "lazy_registry",
      "npc_lazy_web"].includes(entry.role));
    const stylesheets = expected.filter((entry) => entry.role.endsWith("stylesheet"));
    const scriptUrls = scripts.map((entry) => "https://overlay.local/"
      + entry.locator.slice("root:launcher/web/".length));
    const styleUrls = stylesheets.map((entry) => "https://overlay.local/"
      + entry.locator.slice("root:launcher/web/".length));
    const frameId = "fixture-" + lifecycle + "-main-frame";
    const contextId = lifecycle === "first" ? 101 : 202;
    const inlineSource = fs.readFileSync(path.resolve(repositoryRoot,
      "launcher", "web", "overlay.html"), "utf8").match(/<script>([\s\S]*?)<\/script>/i)[1];
    const inlineBytes = Buffer.from(inlineSource, "utf8");
    const rawScripts = [{ url: "https://overlay.local/overlay.html",
      origin: "https://overlay.local", scriptId: "fixture-" + lifecycle + "-inline",
      sourceSha256: sha256Bytes(inlineBytes), sourceBytes: inlineBytes.length }]
      .concat(scripts.map((entry, index) => ({ url: scriptUrls[index],
        origin: "https://overlay.local", scriptId: "fixture-" + lifecycle + "-script-" + index,
        sourceSha256: entry.sha256, sourceBytes: entry.bytes })));
    const toolScriptPlan = ["install_new_document", "install_current_document", "health",
      "panel_state", "detach_hooks"].map((label, index) => {
      const source = "fixture npc tool " + lifecycle + " " + label + " " + index;
      return { sequence: index + 1, label,
        url: "https://cf7-agent.invalid/npc-passive-observer/fixture-" + lifecycle + "/"
          + String(index + 1).padStart(4, "0") + "-" + label + ".js",
        sha256: sha256Text(source), bytes: Buffer.byteLength(source, "utf8") };
    });
    rawScripts.push(...toolScriptPlan.filter((entry) => entry.label !== "install_new_document")
      .map((entry, index) => ({ url: entry.url, origin: "https://cf7-agent.invalid",
        scriptId: "fixture-" + lifecycle + "-tool-" + index,
        sourceSha256: entry.sha256, sourceBytes: entry.bytes })));
    const scriptOccurrences = rawScripts.map((entry, index) => {
      const rawExecutionContextAuxData = { frameId, isDefault: true, type: "default" };
      return Object.assign({
        occurrence: index + 1, executionContextId: contextId,
        contextOrigin: "https://overlay.local", frameId,
        rawExecutionContextAuxData,
        rawParams: { scriptId: entry.scriptId, url: entry.url, executionContextId: contextId,
          executionContextAuxData: JSON.parse(JSON.stringify(rawExecutionContextAuxData)) },
        sourceMethod: "Debugger.getScriptSource",
      }, entry);
    });
    const resourceIconNames = ProductionClosure.authorityIconNames(
      strictRequestPairsFromEvents(transcript.events));
    const resourcePolicy = ProductionClosure.loadedResourcePolicy(repositoryRoot,
      productionClosure, resourceIconNames);
    const resourceRows = resourcePolicy.required.concat(resourcePolicy.conditional.filter((entry) =>
      entry.reason === "conditional_visible_workbench_skin"
        || entry.url === "https://cfn-fonts.local/lxgw-wenkai-screen.ttf"));
    const resourceOccurrences = resourceRows.map((entry, index) => ({ occurrence: index + 1,
      frameId, frameUrl: "https://overlay.local/overlay.html",
      frameOrigin: "https://overlay.local", url: entry.url, origin: entry.origin,
      resourceType: entry.resourceType, mimeType: entry.mimeTypes[0],
      sourceMethod: "Page.getResourceContent", sourceSha256: entry.sha256,
      sourceBytes: entry.bytes }));
    const styleOccurrences = resourceOccurrences.filter((entry) =>
      entry.resourceType === "Stylesheet");
    const value = { schema: ProductionClosure.LOADED_SCHEMA, lifecycle, capturedAt,
      runtimePid: pid, runId: RUN_ID,
      productionClosureSha256: productionClosure.closureSha256,
      productionBindingSha256: productionBinding.bindingSha256,
      page: Object.assign({}, page, { url: "https://overlay.local/overlay.html",
        origin: "https://overlay.local",
        sourceMethod: "Page.getResourceContent" }),
      scriptOccurrences,
      executionContexts: [{ occurrence: 1, id: contextId, origin: "https://overlay.local",
        name: "", uniqueId: "fixture-" + lifecycle + "-context", frameId,
        rawAuxData: { frameId, isDefault: true, type: "default" } }],
      toolScriptPlan,
      inlineScripts: [{ occurrence: 1, scriptId: "fixture-" + lifecycle + "-inline",
        executionContextId: contextId, frameId, contextOrigin: "https://overlay.local",
        sourceMethod: "Debugger.getScriptSource", sha256: sha256Bytes(inlineBytes),
        bytes: inlineBytes.length }],
      resourceIconNames,
      resourceOccurrences,
      styleOccurrences: styleOccurrences.map((entry) => JSON.parse(JSON.stringify(entry))),
      relevantScriptUrls: scriptUrls,
      relevantStyleUrls: styleUrls,
      scripts: scripts.map((entry, index) => ({ occurrence: index + 2, order: index + 1,
        scriptId: "fixture-" + lifecycle + "-script-" + index,
        executionContextId: contextId, frameId, contextOrigin: "https://overlay.local",
        url: scriptUrls[index], origin: "https://overlay.local", declarationRole: entry.role,
        sourceMethod: "Debugger.getScriptSource", sha256: entry.sha256, bytes: entry.bytes })),
      stylesheets: stylesheets.map((entry, index) => ({
        occurrence: styleOccurrences[index].occurrence,
        order: index + 1, frameId, url: styleUrls[index],
        origin: "https://overlay.local", declarationRole: entry.role,
        sourceMethod: "Page.getResourceContent", sha256: entry.sha256, bytes: entry.bytes })) };
    value.evidenceSha256 = sha256Text(canonicalJson(value));
    return value;
  }
  const archiveDiskManifest = diskManifest(SLOT, "2".repeat(64), "4".repeat(64),
    "3".repeat(64), iso(45));
  const restartDiskManifest = diskManifest(SLOT, "2".repeat(64), "4".repeat(64),
    "3".repeat(64), iso(75, 850));
  const afterArchiveArtifact = addArtifact("evidence/clone-after-archive.json", "clone_disk_manifest",
    Buffer.from(JSON.stringify(archiveDiskManifest, null, 2) + "\n", "utf8"));
  const afterRestartArtifact = addArtifact("evidence/clone-after-restart.json", "clone_disk_manifest",
    Buffer.from(JSON.stringify(restartDiskManifest, null, 2) + "\n", "utf8"));
  const firstResidue = residueSnapshot(runDir, fixtureCandidate, 1111, 43111, 44111, 41001,
    iso(55));
  const restartResidue = residueSnapshot(runDir, fixtureCandidate, 2222, 43222, 44222, 41002,
    iso(75, 800));
  const shutdown = { schema: "workbench-live-e2e.npc.supported-shutdown.v1",
    lifecycle: "restart", action: "shutdown", pid: 2222,
    requestedAt: iso(75, 100), completedAt: iso(75, 500),
    responseSha256: "", responseSucceeded: true };
  const shutdownResponse = { success: true, action: "shutdown", state: "completed" };
  shutdown.responseSha256 = sha256Text(canonicalJson(shutdownResponse));
  shutdown.evidenceSha256 = sha256Text(canonicalJson(shutdown));
  const shutdownResponseArtifact = addArtifact("evidence/supported-shutdown-response.json",
    "supported_shutdown_response",
    Buffer.from(JSON.stringify(shutdownResponse, null, 2) + "\n", "utf8"));
  const residue = { schema: "workbench-live-e2e.npc.runtime-residue.v2",
    checkedAfterRestartShutdown: true, checkedAt: restartResidue.observedAt,
    first: firstResidue, restart: restartResidue,
    cloneLockReleased: true, cloneLockReleasedAt: iso(76) };
  residue.evidenceSha256 = sha256Text(canonicalJson(residue));
  function fixtureControlIdentity(step) {
    const binding = controls.find((entry) => entry.step === step);
    const ack = JSON.parse(fs.readFileSync(path.join(runDir, binding.ackArtifact), "utf8"));
    const provider = JSON.parse(fs.readFileSync(path.join(runDir,
      ack.providerReceipt.artifact), "utf8"));
    return { requestId: binding.requestId, providerOperationId: provider.providerOperationId };
  }
  const safeExitIdentity = fixtureControlIdentity("safe_exit");
  const exitConfirmIdentity = fixtureControlIdentity("exit_confirm");
  const inventoryEvents = [
    ["initial", calls.initialInventorySnapshots],
    ["purchase-post", calls.purchasePostInventories],
    ["sale-post", calls.salePostInventories],
    ["restart", calls.restartInventorySnapshots],
  ].flatMap(([phase, callIds]) => callIds.map((callId, pairOrdinal) => {
    const requestEvent = rawEvents.find((event) => event.kind === "bridge_send"
      && event.message && event.message.callId === callId);
    const responseEvent = rawEvents.find((event) => event.kind === "webview_message"
      && event.message && event.message.callId === callId);
    if (!requestEvent || !responseEvent) throw new Error("fixture Inventory timeline pair is absent");
    return { phase, pairOrdinal, callId, requestAt: requestEvent.observedAt,
      responseAt: responseEvent.observedAt };
  }));
  const trustedTimeline = sealTrustedTimeline({
    runId: RUN_ID,
    transcriptSha256: artifacts.find((entry) => entry.path === transcriptArtifact).sha256,
    hostLogSha256: artifacts.find((entry) => entry.path === hostLogArtifact).sha256,
    safeExitRequestId: safeExitIdentity.requestId,
    safeExitProviderOperationId: safeExitIdentity.providerOperationId,
    exitConfirmRequestId: exitConfirmIdentity.requestId,
    exitConfirmProviderOperationId: exitConfirmIdentity.providerOperationId,
    safeExitProviderBoundarySha256: sha256Text(canonicalJson(
      hostLog.lifecycles.first.timelineBoundaries.safe_exit_provider_completed)),
    archiveHostLine: archive.lineNumber,
    shutdownSha256: shutdown.evidenceSha256,
    residueSha256: residue.evidenceSha256,
    inventoryEvents,
  });
  const evidenceOrigin = sealEvidenceOrigin({
    origin: "offline_fixture_generator",
    profile: "offline_fixture_v1",
    evidenceMode: "offline_fixture",
    runId: RUN_ID,
    root: repositoryRoot,
    journeyMode: full ? "purchase_then_explicit_sale" : "purchase_only",
    fullScopeEligible: false,
    requiredPhases: ["domain_loaded", "terminal"],
    sourceGenerator: "tools/workbench-live-e2e/npc/fixtures/valid-bundle.js",
    moduleManifestSha256: null,
    moduleJournalSha256: null,
  });
  const bundle = {
    schema: BUNDLE_SCHEMA,
    evidenceMode: "offline_fixture",
    evidenceOrigin,
    fixtureProvenance: {
      schema: "workbench-live-e2e.npc.offline-fixture-provenance.v1",
      generator: "tools/workbench-live-e2e/npc/fixtures/valid-bundle.js",
      synthetic: true,
      liveEvidence: false,
    },
    runId: RUN_ID,
    root: repositoryRoot,
    runDir,
    candidateRoot: fixtureCandidate.candidateRoot,
    slot: SLOT,
    shopId: SHOP_ID,
    journeyMode: full ? "purchase_then_explicit_sale" : "purchase_only",
    artifactManifest: null,
    transcriptArtifact,
    hostLogArtifact,
    controls,
    instances: INSTANCES,
    calls,
    pricingConstraint: {
      schema: PRICING_CONSTRAINT_SCHEMA,
      expectedBuyRatePermille: PURCHASE.buyRatePermille,
    },
    purchasePolicy: PURCHASE,
    salePolicy: full ? {
      explicitAllowlist: true,
      containerId: "背包",
      slot: 0,
      expectedItem: "砍刀",
      expectedPreQuantity: settings.salePreQuantity,
      expectedLease: "bag.purchase-post.0",
      quantity: 1,
      requiresQuantityAdjustment: settings.salePreQuantity > 1,
    } : null,
    candidate: {
      verifiedBeforeCloneMutation: true,
      verifiedAt: "2026-08-03T00:00:00.000Z",
      stableIdentity,
    },
    clone: {
      slot: SLOT,
      lockExclusive: true,
      lockReleasedAfterResidue: true,
      lockReleasedAt: iso(76),
      mutatedAt: "2026-08-03T00:00:00.500Z",
      seedBeforeArtifact,
      seedAfterArtifact,
      afterArchiveArtifact,
      afterRestartArtifact,
      baselineJsonSha256: "1".repeat(64),
      afterArchiveJsonSha256: "2".repeat(64),
      afterRestartJsonSha256: "2".repeat(64),
      afterArchiveArtifactSetSha256: "3".repeat(64),
      afterRestartArtifactSetSha256: "3".repeat(64),
      afterArchiveSolSetSha256: sha256Text(canonicalJson(
        archiveDiskManifest.artifacts.filter((entry) => entry.kind === "sol"))),
      afterRestartSolSetSha256: sha256Text(canonicalJson(
        restartDiskManifest.artifacts.filter((entry) => entry.kind === "sol"))),
    },
    runtime: {
      first: {
        pid: 1111,
        controlPort: 43111,
        cdpPort: 41001,
        controlBindingPid: 1111,
        cdpBindingPid: 1111,
        cdpExclusiveBeforeLaunch: true,
        startedAt: "2026-08-03T00:00:00.900Z",
        stableIdentity,
        loadedProduction: loadedProduction("first", 1111,
          new Date((Date.parse(firstObserverDetached.event.observedAt)
            + Date.parse(controlTimes.get("safe_exit").issuedAt)) / 2).toISOString()),
      },
      restart: {
        pid: 2222,
        controlPort: 43222,
        cdpPort: 41002,
        controlBindingPid: 2222,
        cdpBindingPid: 2222,
        cdpExclusiveBeforeLaunch: true,
        startedAt: "2026-08-03T00:01:00.000Z",
        stableIdentity,
        loadedProduction: loadedProduction("restart", 2222, iso(74, 800)),
      },
    },
    archive: {
      slot: SLOT,
      hostLine: archive.lineNumber,
      characters: 19867,
      sv1HostLine: sv1.lineNumber,
      sv2HostLine: sv2.lineNumber,
      observedAt: iso(45),
    },
    productionClosure,
    postRestartProductionClosure,
    candidateProducer,
    productionBinding,
    actualShopBinding,
    safeExitUiJourneyVerified: false,
    exitMethod: "offline_fixture_simulation",
    shutdown,
    shutdownResponseArtifact,
    timelineBoundaries: {
      safeExitProviderBoundary: hostLog.lifecycles.first.timelineBoundaries.safe_exit_provider_completed,
    },
    trustedTimeline,
    residue,
  };
  const roleByPath = Object.fromEntries(artifacts.map((entry) => [entry.path, entry.role]));
  roleByPath["fixture-candidate/CRAZYFLASHER7MercenaryEmpire.exe"] = "candidate_payload";
  roleByPath["fixture-candidate/runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe"] = "candidate_payload";
  roleByPath["fixture-candidate/runtime/cf7-runtime-manifest.tsv"] = "candidate_manifest";
  roleByPath["fixture-candidate/runtime-build-metadata.v2.json"] = "candidate_metadata";
  bundle.artifactManifest = buildArtifactManifest(runDir, RUN_ID, roleByPath);
  const bundlePath = path.join(runDir, "evidence-bundle.json");
  atomicWriteJson(bundlePath, bundle);
  atomicWriteJson(path.join(runDir, "artifact-manifest.json"), bundle.artifactManifest);
  return { bundle, bundlePath, runDir };
}

module.exports = {
  INSTANCES,
  PURCHASE,
  PURCHASE_SLOT,
  RUN_ID,
  SHOP_ID,
  SLOT,
  buildValidFixture,
  fixturePng,
  pngChunk,
};
