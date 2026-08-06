"use strict";

const fs = require("fs");
const path = require("path");
const RuntimeModuleJournal = require("../lib/runtime-module-journal");
const LauncherObservation = require("../lib/launcher-observation");
const ProductionClosure = require("./production-closure");
const {
  BUNDLE_SCHEMA,
  EVIDENCE_ORIGIN_SCHEMA,
  RECEIPT_SCHEMA,
  SHA256_RE,
  TOKEN_REF_RE,
  assertNoRawAuthorityTokens,
  assertOpaqueId,
  assertSafeSlot,
  canonicalJson,
  canonicalTimelineEntries,
  deepClone,
  deepEqual,
  fail,
  isPlainObject,
  readJson,
  readManifestJson,
  requireOne,
  sha256File,
  sha256Text,
  sealTrustedTimeline,
  verifyArtifactManifest,
  verifyEventChain,
} = require("./common");
const { verifyControls } = require("./control-contract");
const { captureRelativePath, providerReceiptRelativePath } = require("./control-channel");
const {
  assertHostMapping,
  assertFreshAuthorityReadback,
  assertInventorySnapshotSurface,
  assertNoNpcOverlap,
  assertNoUnmappedHostWrites,
  assertNpcState,
  assertTokenLink,
  assertUniqueMappings,
  bagSlot,
  inboundMessages,
  inventoryWindows,
  normalizedHostRecords,
  hostLifecycleRecords,
  openCommands,
  outboundMessages,
  panelRequests,
  panelResponses,
  requestPairs,
  requestsFor,
  responseFor,
  verifyHostLifecycle,
} = require("./protocol");

const REAL_NPC_SOURCES = new Set(["world_npc", "world_npc_dialogue", "tablet_contacts"]);
const FULL_MODE = "purchase_then_explicit_sale";
const PURCHASE_ONLY_MODE = "purchase_only";
const RUNTIME_HASH_RE = /^[A-Fa-f0-9]{64}$/;
const CANONICAL_ROOT = path.resolve(__dirname, "..", "..", "..");
const LIVE_PHASES = Object.freeze(["domain_loaded", "clone_prepared", "first_captured",
  "restart_captured", "verification_executed", "terminal"]);
const OFFLINE_PHASES = Object.freeze(["domain_loaded", "terminal"]);

function own(value, key) {
  return Object.prototype.hasOwnProperty.call(value || {}, key);
}

function hasExactKeys(value, keys) {
  return isPlainObject(value)
    && canonicalJson(Object.keys(value).sort()) === canonicalJson(keys.slice().sort());
}

function assertStrictTimeline(entries, code, phase) {
  const parsed = entries.map((entry) => ({ label: entry[0], value: Date.parse(entry[1]) }));
  const invalid = parsed.find((entry) => !Number.isFinite(entry.value));
  if (invalid) {
    fail(code, phase, "strict boundary chain contains a missing or malformed timestamp", {
      label: invalid.label,
    });
  }
  for (let index = 1; index < parsed.length; index += 1) {
    if (parsed[index].value <= parsed[index - 1].value) {
      fail(code, phase, "strict boundary chain regressed or collapsed", {
        previous: parsed[index - 1].label,
        current: parsed[index].label,
      });
    }
  }
  return parsed;
}

function verifyEvidenceOrigin(bundle, options) {
  const settings = options || {};
  const origin = bundle.evidenceOrigin;
  const keys = ["schema", "origin", "profile", "evidenceMode", "runId", "root", "journeyMode",
    "fullScopeEligible", "requiredPhases", "sourceGenerator", "moduleManifestSha256",
    "moduleJournalSha256", "evidenceSha256"];
  const unsigned = Object.assign({}, origin || {});
  delete unsigned.evidenceSha256;
  if (!isPlainObject(origin)
      || canonicalJson(Object.keys(origin).sort()) !== canonicalJson(keys.slice().sort())
      || origin.schema !== EVIDENCE_ORIGIN_SCHEMA
      || origin.evidenceMode !== bundle.evidenceMode || origin.runId !== bundle.runId
      || origin.root !== CANONICAL_ROOT || bundle.root !== CANONICAL_ROOT
      || origin.journeyMode !== bundle.journeyMode
      || origin.evidenceSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("evidence_origin_invalid", "evidence_origin",
      "sealed evidence origin is detached from the canonical NPC journey");
  }
  if (bundle.evidenceMode === "offline_fixture") {
    if (origin.origin !== "offline_fixture_generator" || origin.profile !== "offline_fixture_v1"
        || origin.fullScopeEligible !== false
        || canonicalJson(origin.requiredPhases) !== canonicalJson(OFFLINE_PHASES)
        || origin.sourceGenerator !== "tools/workbench-live-e2e/npc/fixtures/valid-bundle.js"
        || origin.moduleManifestSha256 !== null || origin.moduleJournalSha256 !== null) {
      fail("offline_evidence_origin_invalid", "evidence_origin",
        "offline fixture origin cannot acquire live phases, profile, or eligibility");
    }
    return origin;
  }
  const full = bundle.journeyMode === FULL_MODE;
  if (origin.origin !== "bootstrap_live_capture"
      || origin.profile !== (full ? "npc_a3_full_live_v1" : "npc_a3_purchase_diagnostic_v1")
      || origin.fullScopeEligible !== full
      || canonicalJson(origin.requiredPhases) !== canonicalJson(LIVE_PHASES)
      || origin.sourceGenerator !== "tools/workbench-live-e2e/npc/bootstrap.js"
      || !isPlainObject(bundle.moduleJournal)
      || origin.moduleManifestSha256 !== bundle.moduleJournal.manifest.manifestSha256
      || (settings.preSeal === true
        ? origin.moduleJournalSha256 !== null || bundle.moduleJournal.artifact !== null
        : !isPlainObject(bundle.moduleJournal.artifact)
          || origin.moduleJournalSha256 !== bundle.moduleJournal.artifact.evidenceSha256)) {
    fail("live_evidence_origin_invalid", "evidence_origin",
      "live evidence lacks the exact bootstrap profile, phase set, or sealed module binding");
  }
  return origin;
}

function number(value, code, phase, label, options) {
  const settings = options || {};
  const candidate = Number(value);
  if (!Number.isFinite(candidate)
      || (settings.integer && !Number.isInteger(candidate))
      || (settings.min != null && candidate < settings.min)
      || (settings.max != null && candidate > settings.max)) {
    fail(code, phase, label + " is outside its contract", { value });
  }
  return candidate;
}

function phasePair(requests, responses, panelInstanceId, cmd, domain, callId, phase) {
  const matches = requestsFor(requests, panelInstanceId, cmd, domain)
    .filter((entry) => callId == null || entry.message.callId === callId);
  const request = requireOne(matches, "phase_request_count_invalid", phase,
    "phase request is absent or duplicated", { panelInstanceId, cmd, domain, callId });
  return { request, response: responseFor(request, responses, phase) };
}

function phaseInventorySurface(requests, responses, panelInstanceId, callIds, legacyHead, phase) {
  if (!Array.isArray(callIds) || callIds.length < 1 || callIds.length > 3
      || new Set(callIds).size !== callIds.length || legacyHead !== callIds[0]) {
    fail("inventory_surface_call_ids_invalid", phase,
      "sealed Inventory surface callIds must be one exact unique ordered pair-set");
  }
  const pairs = callIds.map((callId) => phasePair(requests, responses, panelInstanceId,
    "snapshot", "inventory", callId, phase));
  return assertInventorySnapshotSurface(pairs, phase);
}

function assertSuccess(pair, phase) {
  if (!pair.response.message || pair.response.message.success !== true) {
    fail("authority_response_failed", phase, "authoritative response did not succeed", {
      cmd: pair.request.message.cmd,
      callId: pair.request.message.callId,
      error: pair.response.message && pair.response.message.error,
    });
  }
  return pair.response.message;
}

function assertOpen(open, expectedInstanceId, expectedShopId, phase) {
  const message = open && open.message;
  if (!hasExactKeys(message, ["type", "cmd", "panel", "panelInstanceId", "initData"])
      || message.type !== "panel_cmd" || message.cmd !== "open" || message.panel !== "npcshop"
      || message.panelInstanceId !== expectedInstanceId
      || !hasExactKeys(message.initData, ["shopId", "panelInstanceId"])
      || message.initData.panelInstanceId !== expectedInstanceId
      || message.initData.shopId !== expectedShopId) {
    fail("panel_open_contract_invalid", phase, "NPC panel open is not bound to the expected owner and shop", {
      expectedInstanceId,
      expectedShopId,
    });
  }
}

function assertFreshInstances(opens, bundle) {
  const expectedNames = ["first", "restart"];
  if (!isPlainObject(bundle.instances) || opens.length !== expectedNames.length) {
    fail("panel_open_multiset_invalid", "instances", "NPC owner-open multiset does not match journey mode", {
      expected: expectedNames.length,
      actual: opens.length,
    });
  }
  const ids = [];
  expectedNames.forEach((name, index) => {
    const id = bundle.instances[name];
    assertOpaqueId(id, "panel_instance_invalid", "instances", name + " panelInstanceId");
    assertOpen(opens[index], id, bundle.shopId, "open_" + name);
    ids.push(id);
    if (index > 0 && opens[index].event.sequence <= opens[index - 1].event.sequence) {
      fail("panel_open_order_invalid", "instances", "fresh NPC owners are out of order");
    }
  });
  if (new Set(ids).size !== ids.length) {
    fail("panel_instance_reused", "instances", "NPC panelInstanceId was reused across the fresh restart");
  }
  return expectedNames.map((name, index) => ({ name, id: ids[index], open: opens[index] }));
}

function parseIngressRecords(records) {
  return records.map((record) => {
    const prefix = "[XmlSocket:JSON] ";
    if (!record.body.startsWith(prefix)) return null;
    try {
      const envelope = JSON.parse(record.body.slice(prefix.length));
      const request = isPlainObject(envelope.payload) ? envelope.payload : envelope;
      return { record, envelope, request };
    } catch (_error) { return null; }
  }).filter((entry) => entry && entry.envelope.task === "panel_request"
    && entry.request.panel === "npcshop");
}

function assertRealIngress(records, expectedCount, shopId) {
  const ingress = parseIngressRecords(records);
  if (ingress.length !== expectedCount) {
    fail("npc_real_ingress_count_invalid", "ingress", "each NPC reopen must have one real Flash panel_request", {
      expectedCount,
      actualCount: ingress.length,
    });
  }
  ingress.forEach((entry) => {
    if (!REAL_NPC_SOURCES.has(entry.request.source)
        || !isPlainObject(entry.request.initData)
        || entry.request.initData.shopId !== shopId) {
      fail("npc_real_ingress_invalid", "ingress", "NPC panel did not come from an allowed real production ingress", {
        source: entry.request.source,
      });
    }
  });
  return ingress;
}

function assertClose(requests, instanceId, phase) {
  const close = requireOne(requests.filter((entry) => entry.message.panelInstanceId === instanceId
    && entry.message.cmd === "close" && !own(entry.message, "domain") && !own(entry.message, "callId")),
  "panel_close_count_invalid", phase, "NPC owner must close exactly once before a fresh reopen");
  return close;
}

function assertRequestShape(pair, expectedPayload, phase) {
  if (!deepEqual(pair.request.message.payload, expectedPayload)) {
    fail("request_payload_mismatch", phase, "Web request payload differs from the expected authority intent", {
      expectedPayload,
      actualPayload: pair.request.message.payload,
    });
  }
}

function assertCatalogTarget(snapshot, policy, phase) {
  if (!hasExactKeys(policy, ["catalogIndex", "itemName", "displayName", "icon", "basePrice",
    "unitPrice", "buyMultiplier", "maxQuantity", "itemKind", "destinationView", "quantity"])) {
    fail("purchase_policy_invalid", phase, "purchase policy is not the exact sealed catalog contract");
  }
  const state = assertNpcState(snapshot, snapshot.shopId, phase);
  const catalog = state.catalog;
  const entry = catalog.get(Number(policy.catalogIndex));
  if (!entry || entry.itemName !== policy.itemName || entry.displayName !== policy.displayName
      || entry.icon !== policy.icon || entry.locked !== false || Number(entry.maxQuantity) < 1
      || Number(entry.basePrice) !== Number(policy.basePrice)
      || Number(entry.unitPrice) !== Number(policy.unitPrice)
      || Number(entry.maxQuantity) !== Number(policy.maxQuantity)
      || Number(snapshot.buyMultiplier) !== Number(policy.buyMultiplier)
      || Number(entry.unitPrice) !== Math.floor(Number(entry.basePrice) * Number(snapshot.buyMultiplier))
      || policy.itemKind !== "equipment" || policy.destinationView !== "bag"
      || !["武器", "防具"].includes(entry.majorType) || Number(policy.quantity) !== 1) {
    fail("purchase_target_mismatch", phase, "purchase target does not match the authoritative catalog identity", {
      policy,
    });
  }
  return entry;
}

function emptyBagSlots(message, phase) {
  const bag = inventoryWindowsForVerification(message, phase).get("背包");
  return bag.slots.filter((slot) => !slot.occupied).length;
}

function inventoryWindowsForVerification(message, phase) {
  const windows = inventoryWindows(message, phase);
  if (!windows.has("背包") || !windows.has("战备箱")) {
    fail("inventory_windows_invalid", phase, "exact bag and battle-box windows are required");
  }
  return windows;
}

function inventoryContentProjection(message, phase) {
  const projection = new Map();
  inventoryWindowsForVerification(message, phase).forEach((window, containerId) => {
    window.slots.forEach((slot) => {
      projection.set(containerId + ":" + Number(slot.physicalSlot), {
        occupied: slot.occupied === true,
        item: slot.occupied ? JSON.parse(JSON.stringify(slot.item)) : null,
        confirmProjection: slot.occupied
          ? JSON.parse(JSON.stringify(slot.confirmProjection)) : null,
      });
    });
  });
  return projection;
}

function assertPurchasePreview(message, policy, beforeBalance, inventoryBefore, phase) {
  const responseKeys = ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
    "success", "v", "shopId", "tradeToken", "purchaseLines", "saleLines", "buyTotal",
    "sellTotal", "netDelta", "projectedBalance", "requiredSlots", "availableSlots",
    "missingSlots", "canCommit", "blockingError"];
  if (!hasExactKeys(message, responseKeys) || message.success !== true || message.shopId == null
      || !Array.isArray(message.purchaseLines) || message.purchaseLines.length !== 1
      || !Array.isArray(message.saleLines) || message.saleLines.length !== 0
      || message.canCommit !== true || message.blockingError !== "") {
    fail("purchase_preview_invalid", phase, "purchase preview is not a one-line committable purchase");
  }
  const line = message.purchaseLines[0];
  const lineKeys = ["catalogIndex", "itemName", "displayName", "icon", "quantity", "unitPrice",
    "total", "maxQuantity", "purchaseLimit", "maxAffordable", "maxByCapacity",
    "maxPurchasable", "limitingReason", "itemKind", "destinationView"];
  const limit = Number(policy.maxQuantity);
  const affordable = Math.min(limit, Math.floor(Number(beforeBalance) / Number(policy.unitPrice)));
  const available = emptyBagSlots(inventoryBefore, phase + "_capacity");
  const capacity = Math.min(limit, available);
  const maximum = Math.min(limit, affordable, capacity);
  const limitingReason = maximum < limit
    ? (capacity <= affordable ? "inventory_full" : "insufficient_money") : "";
  const expectedTotal = Math.floor(Number(policy.basePrice) * Number(policy.quantity)
    * Number(policy.buyMultiplier));
  if (!hasExactKeys(line, lineKeys) || Number(line.catalogIndex) !== Number(policy.catalogIndex)
      || line.itemName !== policy.itemName || line.displayName !== policy.displayName
      || line.icon !== policy.icon || Number(line.quantity) !== 1
      || Number(line.unitPrice) !== Number(policy.unitPrice)
      || Number(line.total) !== expectedTotal
      || Number(line.maxQuantity) !== limit || Number(line.purchaseLimit) !== limit
      || Number(line.maxAffordable) !== affordable || Number(line.maxByCapacity) !== capacity
      || Number(line.maxPurchasable) !== maximum || line.limitingReason !== limitingReason
      || line.itemKind !== policy.itemKind || line.destinationView !== policy.destinationView
      || Number(message.buyTotal) !== expectedTotal || Number(message.sellTotal) !== 0
      || Number(message.netDelta) !== -expectedTotal
      || Number(message.projectedBalance) !== Number(beforeBalance) - expectedTotal
      || Number(message.requiredSlots) !== 1 || Number(message.availableSlots) !== available
      || Number(message.missingSlots) !== 0 || maximum < 1) {
    fail("purchase_preview_projection_mismatch", phase,
      "purchase preview identity, quantity, price, capacity, or balance is inconsistent");
  }
  return line;
}

function assertCommitState(message, preview, operation, phase) {
  if (!message || message.success !== true || message.operation !== "tradeCommit"
      || !isPlainObject(message.trade)
      || Number(message.trade.buyTotal) !== Number(preview.buyTotal)
      || Number(message.trade.sellTotal) !== Number(preview.sellTotal)
      || Number(message.trade.netDelta) !== Number(preview.netDelta)
      || Number(message.balance) !== Number(preview.projectedBalance)) {
    fail("trade_commit_state_invalid", phase, operation + " commit response is not the preview's authoritative state");
  }
  assertNpcState(message, preview.shopId, phase);
}

function firstLegalEquipmentDestination(beforeMessage, policy) {
  if (!policy || policy.itemKind !== "equipment" || policy.destinationView !== "bag"
      || Number(policy.quantity) !== 1) {
    fail("purchase_inventory_policy_invalid", "purchase",
      "purchase delivery requires one exact non-mergeable equipment item for the bag");
  }
  const bag = inventoryWindowsForVerification(beforeMessage, "purchase_inventory_destination")
    .get("背包");
  const legal = bag.slots.find((slot) => slot.occupied === false);
  if (!legal) {
    fail("purchase_inventory_destination_missing", "purchase",
      "purchase preview admitted equipment without one legal first vacant bag slot");
  }
  return { containerId: "背包", physicalSlot: Number(legal.physicalSlot),
    key: "背包:" + Number(legal.physicalSlot) };
}

function assertPurchaseInventoryDelta(beforeMessage, afterMessage, policy, catalogEntry) {
  const before = inventoryContentProjection(beforeMessage, "purchase_inventory_before");
  const after = inventoryContentProjection(afterMessage, "purchase_inventory_after");
  if (canonicalJson(Array.from(before.keys())) !== canonicalJson(Array.from(after.keys()))) {
    fail("purchase_inventory_surface_changed", "purchase", "inventory slot surface changed across purchase");
  }
  const changed = Array.from(before.keys()).filter((key) =>
    canonicalJson(before.get(key)) !== canonicalJson(after.get(key)));
  if (changed.length !== 1) {
    fail("purchase_inventory_delta_invalid", "purchase",
      "purchase must change exactly one previously empty bag slot and no non-target slot");
  }
  const destination = firstLegalEquipmentDestination(beforeMessage, policy);
  if (changed[0] !== destination.key) {
    fail("purchase_inventory_destination_invalid", "purchase",
      "equipment purchase did not use ItemUtil.acquire's unique first vacant bag slot", {
        expectedContainerId: destination.containerId,
        expectedPhysicalSlot: destination.physicalSlot,
        actual: changed[0],
      });
  }
  if (before.get(destination.key).occupied !== false
      || after.get(destination.key).occupied !== true) {
    fail("purchase_inventory_delta_invalid", "purchase",
      "purchase destination did not transition from empty to occupied");
  }
  const beforeLease = bagSlot(beforeMessage, destination.physicalSlot,
    "purchase_inventory_lease_before").slotLease;
  const afterLease = bagSlot(afterMessage, destination.physicalSlot,
    "purchase_inventory_lease_after").slotLease;
  if (beforeLease === afterLease) {
    fail("purchase_target_lease_not_invalidated", "purchase",
      "purchase target mutation must invalidate its pre-write slot lease");
  }
  const item = after.get(destination.key).item;
  if (!item || item.name !== policy.itemName || item.displayName !== policy.displayName
      || item.icon !== policy.icon || item.itemKind !== policy.itemKind
      || Number(item.quantity) !== 1 || !catalogEntry
      || item.majorType !== catalogEntry.majorType || item.use !== catalogEntry.use
      || item.actionType !== catalogEntry.actionType || item.weaponType !== catalogEntry.weaponType
      || item.setId !== catalogEntry.setId || item.setName !== catalogEntry.setName
      || Number(item.setOrder) !== Number(catalogEntry.setOrder)) {
    fail("purchase_inventory_target_invalid", "purchase",
      "the legal delivery slot is not the exact authoritative catalog equipment");
  }
  return destination;
}

function assertSalePolicy(snapshotMessage, policy) {
  if (!hasExactKeys(policy, ["explicitAllowlist", "containerId", "slot", "expectedItem",
    "expectedPreQuantity", "expectedLease", "quantity", "requiresQuantityAdjustment",
    "forbiddenPurchasedItem"])
      || policy.explicitAllowlist !== true || policy.containerId !== "背包"
      || !Number.isInteger(Number(policy.slot)) || Number(policy.slot) < 0 || Number(policy.slot) > 49
      || typeof policy.expectedItem !== "string" || !policy.expectedItem
      || typeof policy.expectedLease !== "string" || !policy.expectedLease
      || Number(policy.quantity) !== 1) {
    fail("sale_policy_invalid", "sale", "sale requires an explicit exact-slot one-unit allowlist");
  }
  const slot = bagSlot(snapshotMessage, policy.slot, "sale_policy");
  if (!slot || !slot.occupied || slot.item.name !== policy.expectedItem
      || Number(slot.item.quantity) < 1 || policy.expectedItem === policy.forbiddenPurchasedItem
      || typeof slot.slotLease !== "string" || !slot.slotLease
      || slot.slotLease !== policy.expectedLease
      || (Number(slot.item.quantity) > 1) !== (policy.requiresQuantityAdjustment === true)) {
    fail("sale_source_mismatch", "sale", "explicit sale slot does not match the authoritative inventory source", {
      slot: policy.slot,
      expectedItem: policy.expectedItem,
    });
  }
  if (slot.item.itemKind === "equipment"
      && (Number(slot.item.enhancementLevel || 0) > 1 || slot.item.tierSlotUsed === true
        || Number(slot.item.modSlotUsed || 0) > 0)) {
    fail("sale_source_not_plain", "sale", "explicit equipment sale source is not a plain unmodified item");
  }
  if (policy.expectedPreQuantity != null
      && Number(slot.item.quantity) !== Number(policy.expectedPreQuantity)) {
    fail("sale_source_quantity_mismatch", "sale", "sale source quantity changed from the allowlist expectation");
  }
  return slot;
}

function assertSalePreview(pair, sourceSlot, policy, balance, inventoryBefore, final, phase) {
  const request = pair.request.message.payload;
  const response = pair.response.message;
  if (!hasExactKeys(request, ["v", "shopId", "purchases", "sales"])
      || !Array.isArray(request.purchases) || request.purchases.length !== 0
      || !Array.isArray(request.sales) || request.sales.length !== 1) {
    fail("sale_preview_request_invalid", phase, "sale preview must contain one exact sale and no purchase");
  }
  const sale = request.sales[0];
  const expectedQuantity = final ? 1 : Number(sourceSlot.item.quantity);
  if (!hasExactKeys(sale, ["source", "quantity", "scope"])
      || !hasExactKeys(sale.source, ["containerId", "slot", "expectedLease"])
      || sale.source.containerId !== "背包"
      || Number(sale.source.slot) !== Number(policy.slot)
      || sale.source.expectedLease !== sourceSlot.slotLease
      || sale.scope !== "slot" || Number(sale.quantity) !== expectedQuantity) {
    fail("sale_preview_source_mismatch", phase, "sale preview does not preserve exact slot/lease/quantity authority");
  }
  const responseKeys = ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
    "success", "v", "shopId", "tradeToken", "purchaseLines", "saleLines", "buyTotal",
    "sellTotal", "netDelta", "projectedBalance", "requiredSlots", "availableSlots",
    "missingSlots", "canCommit", "blockingError"];
  if (!hasExactKeys(response, responseKeys) || response.success !== true || !Array.isArray(response.purchaseLines)
      || response.purchaseLines.length !== 0 || !Array.isArray(response.saleLines)
      || response.saleLines.length !== 1) {
    fail("sale_preview_invalid", phase, "sale preview response is not an exact one-line sale");
  }
  const line = response.saleLines[0];
  const lineKeys = ["itemName", "displayName", "icon", "itemKind", "quantity", "total",
    "sourceIdentity", "scope", "matchedCount", "eligibleCount", "protectedCount"];
  const availableBefore = emptyBagSlots(inventoryBefore, phase + "_capacity");
  const availableAfterPlannedSale = availableBefore
    + (expectedQuantity >= Number(sourceSlot.item.quantity) ? 1 : 0);
  if (!hasExactKeys(line, lineKeys)
      || line.sourceIdentity !== "bag:" + policy.slot || line.scope !== "slot"
      || line.itemName !== policy.expectedItem || Number(line.quantity) !== expectedQuantity
      || line.displayName !== sourceSlot.item.displayName || line.icon !== sourceSlot.item.icon
      || line.itemKind !== sourceSlot.item.itemKind
      || Number(line.matchedCount) !== 1 || Number(line.eligibleCount) !== 1
      || Number(line.protectedCount) !== 0 || Number(line.total) < 0
      || Number(response.buyTotal) !== 0 || Number(response.sellTotal) !== Number(line.total)
      || Number(response.netDelta) !== Number(line.total)
      || Number(response.projectedBalance) !== Number(balance) + Number(line.total)
      || Number(response.requiredSlots) !== 0
      || Number(response.availableSlots) !== availableAfterPlannedSale
      || Number(response.missingSlots) !== 0) {
    fail("sale_preview_projection_mismatch", phase,
      "sale preview did not prove exact eligible/protected counts, price, and projected balance");
  }
  if (final && (response.canCommit !== true || response.blockingError !== "")) {
    fail("sale_preview_not_committable", phase, "final one-unit sale preview is not committable");
  }
  return line;
}

function assertSaleInventoryDelta(beforeMessage, afterMessage, policy) {
  const before = inventoryContentProjection(beforeMessage, "sale_inventory_before");
  const after = inventoryContentProjection(afterMessage, "sale_inventory_after");
  if (canonicalJson(Array.from(before.keys())) !== canonicalJson(Array.from(after.keys()))) {
    fail("sale_inventory_surface_changed", "sale", "inventory slot surface changed across sale");
  }
  const changed = Array.from(before.keys()).filter((key) =>
    canonicalJson(before.get(key)) !== canonicalJson(after.get(key)));
  const targetKey = "背包:" + Number(policy.slot);
  if (changed.length !== 1 || changed[0] !== targetKey) {
    fail("sale_inventory_delta_invalid", "sale",
      "sale must change exactly its explicit source slot and no non-target slot");
  }
  const oldValue = before.get(targetKey);
  const newValue = after.get(targetKey);
  const oldLease = bagSlot(beforeMessage, policy.slot, "sale_inventory_lease_before").slotLease;
  const newLease = bagSlot(afterMessage, policy.slot, "sale_inventory_lease_after").slotLease;
  if (oldLease === newLease) {
    fail("sale_target_lease_not_invalidated", "sale",
      "sale target mutation must invalidate its pre-write slot lease");
  }
  if (!oldValue.occupied || !oldValue.item || oldValue.item.name !== policy.expectedItem) {
    fail("sale_inventory_source_invalid", "sale", "sealed sale source is absent from prestate");
  }
  const remaining = Number(oldValue.item.quantity) - 1;
  if (remaining === 0) {
    if (newValue.occupied) fail("sale_exact_slot_not_removed", "sale", "sold one-unit slot remained occupied");
  } else {
    const expectedItem = JSON.parse(JSON.stringify(oldValue.item));
    expectedItem.quantity = remaining;
    if (!newValue.occupied || canonicalJson(newValue.item) !== canonicalJson(expectedItem)) {
      fail("sale_exact_slot_quantity_invalid", "sale",
        "partial exact-slot sale changed fields other than quantity");
    }
  }
}

function assertStableRevisionLeases(before, after, phase) {
  const beforeWindows = inventoryWindowsForVerification(before, phase + "_before");
  const afterWindows = inventoryWindowsForVerification(after, phase + "_after");
  beforeWindows.forEach((beforeWindow, containerId) => {
    const afterWindow = afterWindows.get(containerId);
    if (!afterWindow || beforeWindow.containerEpoch !== afterWindow.containerEpoch
        || beforeWindow.containerVersion !== afterWindow.containerVersion) return;
    beforeWindow.slots.forEach((beforeSlot, index) => {
      const afterSlot = afterWindow.slots[index];
      if (!afterSlot || Number(beforeSlot.physicalSlot) !== Number(afterSlot.physicalSlot)
          || canonicalJson({ occupied: beforeSlot.occupied, item: beforeSlot.item || null,
            confirmProjection: beforeSlot.confirmProjection || null })
            !== canonicalJson({ occupied: afterSlot.occupied, item: afterSlot.item || null,
              confirmProjection: afterSlot.confirmProjection || null })
          || beforeSlot.slotLease !== afterSlot.slotLease) {
        fail("inventory_stable_revision_drift", phase,
          "pure reads of one container revision must keep every item and lease stable", {
            containerId, physicalSlot: beforeSlot.physicalSlot,
          });
      }
    });
  });
}

function assertNoSurfaceWriteInterleaving(surface, requests, phase) {
  const start = surface.firstPair.request.event.sequence;
  const end = surface.lastPair.response.event.sequence;
  const writes = requests.filter((entry) => entry.event.sequence > start
    && entry.event.sequence < end && ["tradeCommit", "buy", "batchSell"].includes(entry.message.cmd));
  if (writes.length) {
    fail("inventory_surface_write_interleaving", phase,
      "a write interleaved one phase's ordered Inventory probe/supplement pair-set", {
        callIds: writes.map((entry) => entry.message.callId),
      });
  }
}

function assertInventoryPhaseAccessConsistency(surfaces, phase) {
  if (!Array.isArray(surfaces) || surfaces.length < 2
      || surfaces.some((surface) => !surface
        || ![0, 40, 80, 120, 160, 200, 240].includes(surface.accessibleCapacity))
      || new Set(surfaces.map((surface) => surface.accessibleCapacity)).size !== 1) {
    fail("inventory_phase_access_drift", phase || "persistence",
      "every lifecycle phase must independently re-probe the same declared battle-box surface", {
        accessibleCapacities: Array.isArray(surfaces)
          ? surfaces.map((surface) => surface && surface.accessibleCapacity) : null,
      });
  }
}

function controlByStep(control, step) {
  return requireOne(control.loaded.filter((entry) => entry.request.step === step),
    "control_step_missing", "control_binding", "control step is absent or duplicated", { step });
}

function assertControlIncludes(control, step, eventEntries, role) {
  const entry = controlByStep(control, step);
  eventEntries.forEach((eventEntry) => {
    if (!entry.events.some((bound) => bound.sequence === eventEntry.event.sequence
        && (!role || bound.role === role))) {
      fail("control_semantic_binding_missing", "control_binding",
        "control acknowledgement does not bind the exact production event", {
          step,
          sequence: eventEntry.event.sequence,
          role,
        });
    }
  });
}

function domInputs(events, start, end) {
  return events.filter((event) => event.kind === "dom_input"
    && event.sequence > start && event.sequence < end);
}

function targetAttribute(event, name) {
  return event && event.target && event.target.attributes
    ? event.target.attributes[name]
    : undefined;
}

function requireDomInput(events, predicate, code, phase, message) {
  const entry = requireOne(events.filter(predicate).map((event) => ({ event })), code, phase, message);
  const event = entry.event;
  const target = event.target;
  const rect = target && target.rect;
  const point = target && target.clientPoint;
  const hitTest = target && target.hitTest;
  const viewport = target && target.viewport;
  const finite = (value) => typeof value === "number" && Number.isFinite(value);
  if (event.isTrusted !== true || !isPlainObject(target) || target.visible !== true
      || target.enabled !== true || target.origin !== "https://overlay.local"
      || canonicalJson(Object.keys(target).sort()) !== canonicalJson([
        "selector", "tagName", "text", "attributes", "visible", "enabled", "origin", "rect",
        "clientPoint", "clientPointSource", "hitTest", "viewport"].sort())
      || !isPlainObject(target.attributes) || typeof target.selector !== "string"
      || !target.selector || typeof target.tagName !== "string" || !target.tagName
      || own(target.attributes, "disabled")
      || String(target.attributes["aria-disabled"] || "").toLowerCase() === "true"
      || !isPlainObject(rect) || !isPlainObject(viewport)
      || canonicalJson(Object.keys(rect).sort()) !== canonicalJson(["x", "y", "width", "height"].sort())
      || canonicalJson(Object.keys(viewport).sort()) !== canonicalJson(["width", "height"].sort())
      || ![rect.x, rect.y, rect.width, rect.height, viewport.width, viewport.height].every(finite)
      || rect.width <= 0 || rect.height <= 0 || viewport.width <= 0 || viewport.height <= 0
      || (event.eventType === "click" && (!isPlainObject(point)
        || canonicalJson(Object.keys(point).sort()) !== canonicalJson(["x", "y"].sort())
        || ![point.x, point.y].every(finite) || target.clientPointSource !== "event"
        || !finite(event.clientX) || !finite(event.clientY)
        || event.clientX !== point.x || event.clientY !== point.y
        || point.x < rect.x || point.x > rect.x + rect.width
        || point.y < rect.y || point.y > rect.y + rect.height
        || point.x < 0 || point.x > viewport.width || point.y < 0 || point.y > viewport.height
        || event.button !== 0 || !isPlainObject(hitTest)
        || canonicalJson(Object.keys(hitTest).sort()) !== canonicalJson(["tagName", "matchesTarget"].sort())
        || typeof hitTest.tagName !== "string" || !hitTest.tagName
        || hitTest.matchesTarget !== true))
      || (event.eventType !== "click" && (point !== null
        || event.clientX !== null || event.clientY !== null
        || target.clientPointSource !== "not_applicable" || hitTest !== null))
      || (event.eventType === "keydown" && (!["Enter", " ", "ArrowLeft", "ArrowRight",
        "Home", "End"].includes(event.key) || event.repeat !== false))) {
    fail("dom_input_evidence_invalid", phase,
      "bound DOM input is not one trusted visible finite hit target", {
        sequence: event.sequence,
      });
  }
  return entry;
}

function assertPurchaseControls(control, events, initialOpen, previewPair, commitPair, policy) {
  assertControlIncludes(control, "open_first", [initialOpen], "panel_open");
  const windowEvents = domInputs(events, initialOpen.event.sequence, commitPair.request.event.sequence + 1);
  const select = requireDomInput(windowEvents, (event) => event.eventType === "click"
    && String(targetAttribute(event, "data-workbench-key")) === String(policy.catalogIndex)
    && event.target && event.target.tagName === "ARTICLE"
    && event.target.selector === "article[data-workbench-key=\"" + policy.catalogIndex + "\"]"
    && String(event.target && event.target.text || "").includes(policy.displayName),
  "purchase_input_missing", "purchase", "purchase card input is absent or ambiguous");
  const checkout = requireDomInput(windowEvents, (event) => event.eventType === "click"
    && event.target && event.target.tagName === "BUTTON"
    && event.target.selector === "button.npcshop-checkout-btn",
  "purchase_checkout_input_missing", "purchase", "purchase checkout input is absent");
  const commit = requireDomInput(windowEvents, (event) => event.eventType === "click"
    && event.target && event.target.tagName === "BUTTON"
    && event.target.selector === "button[data-trade-commit]"
    && own(event.target && event.target.attributes, "data-trade-commit"),
  "purchase_commit_input_missing", "purchase", "purchase commit input is absent");
  assertControlIncludes(control, "select_purchase", [select], "dom_input");
  assertControlIncludes(control, "open_purchase_settlement", [checkout, previewPair.request], "domain_request");
  assertControlIncludes(control, "commit_purchase", [commit, commitPair.request], "domain_write");
}

function assertSaleControls(control, events, open, previewPairs, commitPair, close, policy) {
  const windowEvents = domInputs(events, open.event.sequence, commitPair.request.event.sequence + 1);
  const select = requireDomInput(windowEvents, (event) => event.eventType === "click"
    && String(targetAttribute(event, "data-workbench-key")) === String(policy.slot)
    && event.target && event.target.tagName === "ARTICLE"
    && event.target.selector === "article[data-workbench-key=\"" + policy.slot + "\"]"
    && String(event.target && event.target.text || "").includes(policy.expectedItem),
  "sale_input_missing", "sale", "exact sale-slot input is absent or ambiguous");
  const saleWindow = windowEvents.filter((event) => event.sequence > select.event.sequence);
  const checkout = requireDomInput(saleWindow, (event) => event.eventType === "click"
    && event.target && event.target.tagName === "BUTTON"
    && event.target.selector === "button.npcshop-checkout-btn",
  "sale_checkout_input_missing", "sale", "sale checkout input is absent");
  const commit = requireDomInput(saleWindow, (event) => event.eventType === "click"
    && event.target && event.target.tagName === "BUTTON"
    && event.target.selector === "button[data-trade-commit]"
    && own(event.target && event.target.attributes, "data-trade-commit"),
  "sale_commit_input_missing", "sale", "sale commit input is absent");
  assertControlIncludes(control, "select_sale", [select], "dom_input");
  assertControlIncludes(control, "open_sale_settlement", [checkout, previewPairs[0].request], "domain_request");
  if (policy.requiresQuantityAdjustment) {
    const quantity = requireDomInput(saleWindow, (event) => ["input", "change", "keydown"]
      .includes(event.eventType) && event.target && event.target.tagName === "INPUT"
      && ["input.workbench-quantity-number", "input.workbench-quantity-range"]
        .includes(event.target.selector)
      && String(targetAttribute(event, "aria-label") || "").includes("数量"),
    "sale_quantity_input_missing", "sale", "sale quantity adjustment input is absent");
    assertControlIncludes(control, "set_sale_quantity", [quantity, previewPairs.at(-1).request], "domain_request");
  }
  assertControlIncludes(control, "commit_sale", [commit, commitPair.request], "domain_write");
  const closeInput = requireDomInput(events, (event) => event.sequence < close.event.sequence
    && event.sequence > commitPair.response.event.sequence && event.eventType === "click"
    && event.target && event.target.tagName === "BUTTON"
    && event.target.selector === "button[aria-label=\"关闭 NPC 商店\"]"
    && targetAttribute(event, "aria-label") === "关闭 NPC 商店",
  "sale_close_input_missing", "sale", "sale owner close input is absent");
  assertControlIncludes(control, "close_before_exit", [closeInput, close], "panel_close");
}

function verifyProduction(bundle, verifiedPairs) {
  const closure = ProductionClosure.verifyProductionClosure(bundle.root, bundle.productionClosure);
  const post = ProductionClosure.verifyProductionClosure(bundle.root, bundle.postRestartProductionClosure);
  ProductionClosure.sameProductionTree(closure, post);
  const candidateProducer = ProductionClosure.verifyCandidateProducerBinding(
    bundle.candidateRoot, bundle.candidate.stableIdentity, closure, bundle.candidateProducer);
  const binding = bundle.productionBinding;
  const unsignedBinding = Object.assign({}, binding || {});
  delete unsignedBinding.bindingSha256;
  const identity = ProductionClosure.publicCandidateIdentity(bundle.candidate.stableIdentity);
  if (!isPlainObject(binding) || binding.schema !== ProductionClosure.BINDING_SCHEMA
      || binding.runId !== bundle.runId || binding.productionTreeSha256 !== closure.treeSha256
      || binding.productionClosureSha256 !== closure.closureSha256
      || binding.artifactSourceHash !== closure.runtimeInputs.domains.artifactSource.sha256
      || binding.producerRecipeHash !== closure.runtimeInputs.domains.producerRecipe.sha256
      || binding.toolchainLockHash !== closure.runtimeInputs.domains.toolchainLock.sha256
      || binding.buildIdentityHash !== closure.runtimeInputs.buildIdentityHash
      || binding.runtimeInputsSha256 !== closure.runtimeInputs.evidenceSha256
      || binding.candidateIdentitySha256 !== require("./common").sha256Text(canonicalJson(identity))
      || binding.candidateProducerSha256 !== candidateProducer.evidenceSha256
      || binding.bindingSha256 !== require("./common").sha256Text(canonicalJson(unsignedBinding))) {
    fail("production_binding_invalid", "production_closure",
      "production tree is detached from the candidate/run identity");
  }
  const shop = bundle.actualShopBinding;
  const unsignedShop = Object.assign({}, shop || {});
  delete unsignedShop.bindingSha256;
  const canonicalShop = ProductionClosure.bindActualShop(bundle.root, closure, bundle.shopId);
  const expectedShop = closure.files.filter((entry) => entry.locator === (shop && shop.locator));
  if (!isPlainObject(shop) || shop.schema !== ProductionClosure.SHOP_BINDING_SCHEMA
      || shop.shopId !== bundle.shopId || expectedShop.length !== 1
      || expectedShop[0].role !== "shop_data" || expectedShop[0].sha256 !== shop.sha256
      || expectedShop[0].bytes !== shop.bytes || shop.productionTreeSha256 !== closure.treeSha256
      || shop.bindingSha256 !== require("./common").sha256Text(canonicalJson(unsignedShop))
      || canonicalJson(shop) !== canonicalJson(canonicalShop)) {
    fail("actual_shop_binding_invalid", "production_closure",
      "actual shopId is detached from canonical shop data");
  }
  const expectedWeb = ProductionClosure.webFiles(closure);
  const expectedResourceIconNames = ProductionClosure.authorityIconNames(verifiedPairs);
  function loaded(runtime, lifecycle) {
    const value = runtime.loadedProduction;
    const unsigned = Object.assign({}, value || {});
    delete unsigned.evidenceSha256;
    const loadedKeys = ["capturedAt", "evidenceSha256", "inlineScripts", "lifecycle", "page",
      "executionContexts", "productionBindingSha256", "productionClosureSha256", "relevantScriptUrls",
      "relevantStyleUrls", "resourceIconNames", "resourceOccurrences", "runId", "runtimePid", "schema",
      "scriptOccurrences", "scripts", "styleOccurrences", "stylesheets", "toolScriptPlan"];
    if (!isPlainObject(value) || value.schema !== ProductionClosure.LOADED_SCHEMA
        || canonicalJson(Object.keys(value).sort()) !== canonicalJson(loadedKeys.sort())
        || value.lifecycle !== lifecycle || value.runtimePid !== runtime.pid
        || value.runId !== bundle.runId || !Number.isFinite(Date.parse(value.capturedAt))
        || value.productionClosureSha256 !== closure.closureSha256
        || value.productionBindingSha256 !== binding.bindingSha256
        || value.evidenceSha256 !== require("./common").sha256Text(canonicalJson(unsigned))) {
      fail("loaded_production_binding_invalid", "production_closure",
        lifecycle + " loaded production evidence is detached");
    }
    const pageExpected = requireOne(expectedWeb.filter((entry) => entry.role === "page"),
      "loaded_production_page_invalid", "production_closure",
      "production closure must contain one Overlay page");
    const pageKeys = ["role", "locator", "url", "origin", "sourceMethod", "sha256", "bytes"];
    if (!isPlainObject(value.page)
        || canonicalJson(Object.keys(value.page).sort()) !== canonicalJson(pageKeys.sort())
        || value.page.role !== pageExpected.role || value.page.locator !== pageExpected.locator
        || value.page.url !== "https://overlay.local/overlay.html"
        || value.page.origin !== "https://overlay.local"
        || value.page.sourceMethod !== "Page.getResourceContent"
        || value.page.sha256 !== pageExpected.sha256 || value.page.bytes !== pageExpected.bytes) {
      fail("loaded_production_page_invalid", "production_closure",
        lifecycle + " loaded Overlay page differs from the current-tree closure");
    }
    const expectedScripts = expectedWeb.filter((entry) => ["overlay_boot_web", "lazy_registry",
      "npc_lazy_web"].includes(entry.role));
    const expectedStyles = expectedWeb.filter((entry) => entry.role.endsWith("stylesheet"));
    function expectedUrl(entry) {
      return "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length);
    }
    const expectedScriptUrls = expectedScripts.map(expectedUrl);
    const expectedStyleUrls = expectedStyles.map(expectedUrl);
    const pageScriptUrl = "https://overlay.local/overlay.html";
    const scripts = Array.isArray(value.scripts) ? value.scripts : [];
    const styles = Array.isArray(value.stylesheets) ? value.stylesheets : [];
    if (!Array.isArray(value.scriptOccurrences) || !Array.isArray(value.executionContexts)
        || !Array.isArray(value.toolScriptPlan)
        || !Array.isArray(value.inlineScripts) || !Array.isArray(value.resourceIconNames)
        || canonicalJson(value.resourceIconNames) !== canonicalJson(expectedResourceIconNames)
        || !Array.isArray(value.resourceOccurrences)
        || !Array.isArray(value.styleOccurrences) || !Array.isArray(value.relevantScriptUrls)
        || !Array.isArray(value.relevantStyleUrls)
        || canonicalJson(value.relevantScriptUrls) !== canonicalJson(expectedScriptUrls)
        || canonicalJson(value.relevantStyleUrls) !== canonicalJson(expectedStyleUrls)
        || scripts.length !== expectedScripts.length || styles.length !== expectedStyles.length
        || new Set(scripts.map((entry) => entry && entry.url)).size !== scripts.length
        || new Set(scripts.map((entry) => entry && entry.scriptId)).size !== scripts.length
        || new Set(styles.map((entry) => entry && entry.url)).size !== styles.length) {
      fail("loaded_production_multiset_invalid", "production_closure",
        lifecycle + " raw relevant script/stylesheet multiset is missing, duplicated, or extra");
    }
    const toolPrefix = "https://cf7-agent.invalid/npc-passive-observer/";
    const scriptOccurrenceKeys = ["contextOrigin", "executionContextId", "frameId",
      "occurrence", "origin", "rawExecutionContextAuxData", "rawParams", "scriptId",
      "sourceBytes", "sourceMethod", "sourceSha256", "url"];
    const resourceOccurrenceKeys = ["frameId", "frameOrigin", "frameUrl", "mimeType",
      "occurrence", "origin", "resourceType", "sourceBytes", "sourceMethod",
      "sourceSha256", "url"];
    const toolPlanKeys = ["bytes", "label", "sequence", "sha256", "url"];
    const contextKeys = ["frameId", "id", "name", "occurrence", "origin", "rawAuxData", "uniqueId"];
    const contextIds = [];
    value.scriptOccurrences.forEach((entry) => {
      if (entry && !contextIds.includes(entry.executionContextId)) {
        contextIds.push(entry.executionContextId);
      }
    });
    const contextAuxKeys = ["frameId", "isDefault", "type"];
    if (canonicalJson(value.executionContexts.map((entry) => entry && entry.id))
          !== canonicalJson(contextIds)
        || value.executionContexts.some((entry, index) => !isPlainObject(entry)
          || canonicalJson(Object.keys(entry).sort()) !== canonicalJson(contextKeys.sort())
          || entry.occurrence !== index + 1 || !Number.isInteger(entry.id) || entry.id < 1
          || entry.origin !== "https://overlay.local" || typeof entry.name !== "string"
          || typeof entry.uniqueId !== "string" || !entry.uniqueId
          || typeof entry.frameId !== "string" || !entry.frameId
          || !isPlainObject(entry.rawAuxData)
          || canonicalJson(Object.keys(entry.rawAuxData).sort()) !== canonicalJson(contextAuxKeys)
          || String(entry.rawAuxData.frameId || "") !== entry.frameId
          || entry.rawAuxData.isDefault !== true || entry.rawAuxData.type !== "default")
        || new Set(value.executionContexts.map((entry) => entry && entry.id)).size
          !== value.executionContexts.length
        || new Set(value.executionContexts.map((entry) => entry && entry.uniqueId)).size
          !== value.executionContexts.length) {
      fail("loaded_production_context_set_invalid", "production_closure",
        lifecycle + " raw execution-context stream is missing, duplicated, reordered, or foreign");
    }
    const contextById = new Map(value.executionContexts.map((entry) => [entry.id, entry]));
    const executableOccurrences = value.scriptOccurrences.filter((entry) =>
      entry && expectedScriptUrls.includes(entry.url));
    const pageOccurrences = value.scriptOccurrences.filter((entry) =>
      entry && entry.url === pageScriptUrl);
    const toolOccurrences = value.scriptOccurrences.filter((entry) => entry
      && String(entry.url || "").startsWith(toolPrefix));
    const foreignScripts = value.scriptOccurrences.filter((entry) =>
      !entry || (!expectedScriptUrls.includes(entry.url) && entry.url !== pageScriptUrl
        && !String(entry.url || "").startsWith(toolPrefix)));
    const toolByUrl = new Map();
    value.toolScriptPlan.forEach((entry, index) => {
      if (!isPlainObject(entry)
          || canonicalJson(Object.keys(entry).sort()) !== canonicalJson(toolPlanKeys.sort())
          || entry.sequence !== index + 1
          || !["install_new_document", "install_current_document", "health", "panel_state",
            "detach_hooks"].includes(entry.label)
          || typeof entry.url !== "string" || !entry.url.startsWith(toolPrefix)
          || !SHA256_RE.test(String(entry.sha256 || ""))
          || !Number.isInteger(entry.bytes) || entry.bytes < 1 || toolByUrl.has(entry.url)) {
        fail("loaded_production_tool_script_invalid", "production_closure",
          lifecycle + " tool-owned source plan is malformed, duplicated, or unordered");
      }
      toolByUrl.set(entry.url, entry);
    });
    const observedToolUrls = new Set();
    toolOccurrences.forEach((entry) => {
      const plan = toolByUrl.get(entry.url);
      if (!plan || observedToolUrls.has(entry.url)
          || entry.sourceSha256 !== plan.sha256 || entry.sourceBytes !== plan.bytes) {
        fail("loaded_production_tool_script_invalid", "production_closure",
          lifecycle + " tool-owned source is absent, reused, or byte-detached");
      }
      observedToolUrls.add(entry.url);
    });
    const plannedLabels = value.toolScriptPlan.map((entry) => entry.label);
    const executedToolPlan = value.toolScriptPlan.filter((entry) =>
      entry.label !== "install_new_document");
    if (plannedLabels.filter((label) => label === "install_new_document").length !== 1
        || plannedLabels.filter((label) => label === "install_current_document").length !== 1
        || plannedLabels.filter((label) => label === "detach_hooks").length !== 1
        || plannedLabels.at(-1) !== "detach_hooks"
        || canonicalJson(toolOccurrences.map((entry) => entry.url))
          !== canonicalJson(executedToolPlan.map((entry) => entry.url))
        || executedToolPlan.some((entry) => !observedToolUrls.has(entry.url))) {
      fail("loaded_production_tool_script_invalid", "production_closure",
        lifecycle + " final detach source or exact executed tool sequence is not closed");
    }
    if (foreignScripts.length !== 0 || pageOccurrences.length !== 1
        || canonicalJson(executableOccurrences.map((entry) => entry.url))
          !== canonicalJson(expectedScriptUrls)
        || canonicalJson(executableOccurrences.map((entry) => entry.url))
          !== canonicalJson(value.relevantScriptUrls)
        || canonicalJson(scripts.map((entry) => entry.url)) !== canonicalJson(value.relevantScriptUrls)
        || new Set(value.scriptOccurrences.map((entry) => entry && entry.scriptId)).size
          !== value.scriptOccurrences.length
        || value.scriptOccurrences.some((entry, index) => !isPlainObject(entry)
          || canonicalJson(Object.keys(entry).sort()) !== canonicalJson(scriptOccurrenceKeys.sort())
          || entry.occurrence !== index + 1 || !entry.url
          || expectedScriptUrls.concat([pageScriptUrl]).includes(entry.url)
            && entry.origin !== "https://overlay.local"
          || entry.url.startsWith(toolPrefix) && entry.origin !== "https://cf7-agent.invalid"
          || typeof entry.scriptId !== "string" || !entry.scriptId
          || !Number.isInteger(entry.executionContextId) || entry.executionContextId < 1
          || typeof entry.frameId !== "string" || !entry.frameId
          || entry.contextOrigin !== "https://overlay.local"
          || !isPlainObject(entry.rawParams)
          || String(entry.rawParams.url || "") !== entry.url
          || String(entry.rawParams.scriptId || "") !== entry.scriptId
          || Number(entry.rawParams.executionContextId) !== entry.executionContextId
          || !isPlainObject(entry.rawExecutionContextAuxData)
          || canonicalJson(Object.keys(entry.rawExecutionContextAuxData).sort())
            !== canonicalJson(contextAuxKeys)
          || canonicalJson(entry.rawParams.executionContextAuxData)
            !== canonicalJson(entry.rawExecutionContextAuxData)
          || String(entry.rawExecutionContextAuxData.frameId || "") !== entry.frameId
          || entry.rawExecutionContextAuxData.isDefault !== true
          || entry.rawExecutionContextAuxData.type !== "default"
          || !contextById.has(entry.executionContextId)
          || canonicalJson(entry.rawExecutionContextAuxData)
            !== canonicalJson(contextById.get(entry.executionContextId).rawAuxData)
          || entry.sourceMethod !== "Debugger.getScriptSource"
          || !SHA256_RE.test(String(entry.sourceSha256 || ""))
          || !Number.isInteger(entry.sourceBytes) || entry.sourceBytes < 0)) {
      fail("loaded_production_script_occurrence_invalid", "production_closure",
        lifecycle + " raw scriptParsed occurrence/order/origin/source stream is not exact");
    }
    const derivedStyles = value.resourceOccurrences.filter((entry) => entry
      && (entry.resourceType === "Stylesheet" || /\.css(?:$|[?#])/.test(entry.url)));
    const mainFrameId = value.resourceOccurrences[0] && value.resourceOccurrences[0].frameId;
    ProductionClosure.validateLoadedResourceContract(CANONICAL_ROOT, closure,
      value.resourceOccurrences, mainFrameId, value.resourceIconNames);
    if (canonicalJson(value.styleOccurrences) !== canonicalJson(derivedStyles)
        || canonicalJson(value.styleOccurrences.map((entry) => entry && entry.url))
          !== canonicalJson(expectedStyleUrls)
        || canonicalJson(styles.map((entry) => entry.url)) !== canonicalJson(expectedStyleUrls)
        || value.resourceOccurrences.some((entry, index) => !isPlainObject(entry)
          || canonicalJson(Object.keys(entry).sort()) !== canonicalJson(resourceOccurrenceKeys.sort())
          || entry.occurrence !== index + 1 || typeof entry.frameId !== "string" || !entry.frameId
          || entry.frameId !== mainFrameId || entry.frameUrl !== pageScriptUrl
          || entry.frameOrigin !== "https://overlay.local"
          || typeof entry.url !== "string" || typeof entry.origin !== "string"
          || typeof entry.resourceType !== "string" || typeof entry.mimeType !== "string"
          || !entry.resourceType || !entry.mimeType
          || entry.sourceMethod !== "Page.getResourceContent"
          || !SHA256_RE.test(String(entry.sourceSha256 || ""))
          || !Number.isInteger(entry.sourceBytes) || entry.sourceBytes < 1)
        || value.styleOccurrences.some((entry) => !isPlainObject(entry)
          || entry.origin !== "https://overlay.local" || entry.frameOrigin !== "https://overlay.local"
          || entry.resourceType !== "Stylesheet" || typeof entry.mimeType !== "string")) {
      fail("loaded_production_style_occurrence_invalid", "production_closure",
        lifecycle + " raw resource/CSS occurrence stream is filtered, reordered, foreign, or incomplete");
    }
    const scriptKeys = ["occurrence", "order", "scriptId", "executionContextId", "frameId",
      "contextOrigin", "url", "origin", "declarationRole", "sourceMethod", "sha256", "bytes"];
    expectedScripts.forEach((expected, index) => {
      const url = expectedUrl(expected);
      const actual = scripts[index];
      const raw = executableOccurrences[index];
      if (!isPlainObject(actual)
          || canonicalJson(Object.keys(actual).sort()) !== canonicalJson(scriptKeys.sort())
          || !Number.isInteger(actual.occurrence) || actual.occurrence < 1
          || (index > 0 && actual.occurrence <= scripts[index - 1].occurrence)
          || actual.order !== index + 1 || actual.url !== url
          || !raw || actual.occurrence !== raw.occurrence || actual.scriptId !== raw.scriptId
          || actual.executionContextId !== raw.executionContextId || actual.frameId !== raw.frameId
          || actual.contextOrigin !== raw.contextOrigin || actual.sha256 !== raw.sourceSha256
          || actual.bytes !== raw.sourceBytes
          || typeof actual.scriptId !== "string" || !actual.scriptId
          || !Number.isInteger(actual.executionContextId) || actual.executionContextId < 1
          || typeof actual.frameId !== "string" || !actual.frameId
          || actual.contextOrigin !== "https://overlay.local"
          || actual.origin !== "https://overlay.local" || actual.declarationRole !== expected.role
          || actual.sourceMethod !== "Debugger.getScriptSource" || actual.sha256 !== expected.sha256
          || actual.bytes !== expected.bytes) {
        fail("loaded_production_resource_mismatch", "production_closure",
          lifecycle + " loaded bytes differ from current-tree closure", { locator: expected.locator });
      }
    });
    const styleKeys = ["occurrence", "order", "url", "frameId", "origin", "declarationRole",
      "sourceMethod", "sha256", "bytes"];
    expectedStyles.forEach((expected, index) => {
      const url = expectedUrl(expected);
      const actual = styles[index];
      const raw = value.styleOccurrences[index];
      if (!isPlainObject(actual)
          || canonicalJson(Object.keys(actual).sort()) !== canonicalJson(styleKeys.sort())
          || !Number.isInteger(actual.occurrence) || actual.occurrence < 1
          || !raw || actual.occurrence !== raw.occurrence
          || actual.order !== index + 1 || actual.url !== url
          || actual.frameId !== raw.frameId
          || actual.origin !== "https://overlay.local" || actual.declarationRole !== expected.role
          || actual.sourceMethod !== "Page.getResourceContent"
          || actual.sha256 !== expected.sha256 || actual.bytes !== expected.bytes) {
        fail("loaded_production_resource_mismatch", "production_closure",
          lifecycle + " loaded stylesheet differs from current-tree closure", {
            locator: expected.locator,
          });
      }
    });
    const inlineKeys = ["bytes", "contextOrigin", "executionContextId", "frameId",
      "occurrence", "scriptId", "sha256", "sourceMethod"];
    if (value.inlineScripts.length !== 1
        || value.inlineScripts.some((entry) => !isPlainObject(entry)
          || canonicalJson(Object.keys(entry).sort()) !== canonicalJson(inlineKeys.sort()))
        || !deepEqual(value.inlineScripts[0], {
          occurrence: pageOccurrences[0].occurrence,
          scriptId: pageOccurrences[0].scriptId,
          executionContextId: pageOccurrences[0].executionContextId,
          frameId: pageOccurrences[0].frameId,
          contextOrigin: pageOccurrences[0].contextOrigin,
          sourceMethod: pageOccurrences[0].sourceMethod,
          sha256: pageOccurrences[0].sourceSha256,
          bytes: pageOccurrences[0].sourceBytes,
        })) {
      fail("loaded_production_inline_script_invalid", "production_closure",
        lifecycle + " inline script projection is detached from its raw page occurrence");
    }
    return value;
  }
  const firstLoaded = loaded(bundle.runtime.first, "first");
  const restartLoaded = loaded(bundle.runtime.restart, "restart");
  return { treeSha256: closure.treeSha256, fileCount: closure.files.length,
    artifactSourceHash: closure.artifactSource.artifactSourceHash,
    artifactSourceFileCount: closure.artifactSource.fileCount,
    producerRecipeHash: closure.runtimeInputs.domains.producerRecipe.sha256,
    producerRecipeFileCount: closure.runtimeInputs.domains.producerRecipe.fileCount,
    toolchainLockHash: closure.runtimeInputs.domains.toolchainLock.sha256,
    toolchainLockFileCount: closure.runtimeInputs.domains.toolchainLock.fileCount,
    buildIdentityHash: candidateProducer.buildIdentityHash,
    payloadClosureHash: candidateProducer.payloadClosureHash,
    loadedScriptCount: firstLoaded.scripts.length,
    loadedStylesheetCount: firstLoaded.stylesheets.length,
    first: firstLoaded, restart: restartLoaded, shop };
}

function verifyRuntime(bundle, verifiedPairs) {
  if (!isPlainObject(bundle.candidate) || bundle.candidate.verifiedBeforeCloneMutation !== true
      || !isPlainObject(bundle.candidate.stableIdentity)
      || !isPlainObject(bundle.runtime) || !isPlainObject(bundle.runtime.first)
      || !isPlainObject(bundle.runtime.restart)) {
    fail("runtime_evidence_invalid", "runtime", "candidate/runtime identity evidence is incomplete");
  }
  const first = bundle.runtime.first;
  const restart = bundle.runtime.restart;
  const stable = bundle.candidate.stableIdentity;
  const candidateRoot = path.resolve(bundle.candidateRoot);
  const processPath = path.resolve(String(stable.processPath || ""));
  const installRoot = path.dirname(path.dirname(processPath));
  if (stable.runtimeMode !== "isolated_candidate"
      || candidateRoot.toLowerCase() !== installRoot.toLowerCase()
      || path.basename(processPath).toLowerCase() !== "crazyflasher7mercenaryempire.core.exe"
      || !RUNTIME_HASH_RE.test(String(stable.coreSha256 || ""))
      || !RUNTIME_HASH_RE.test(String(stable.buildIdentity || ""))
      || !RUNTIME_HASH_RE.test(String(stable.payloadClosure || ""))) {
    fail("runtime_candidate_binding_invalid", "runtime",
      "stable runtime identity is not bound to the exact isolated candidate executable");
  }
  if (!deepEqual(first.stableIdentity, bundle.candidate.stableIdentity)
      || !deepEqual(restart.stableIdentity, bundle.candidate.stableIdentity)) {
    fail("runtime_stable_identity_mismatch", "runtime", "restart does not use the frozen candidate identity");
  }
  const firstPid = number(first.pid, "runtime_pid_invalid", "runtime", "first pid", { integer: true, min: 1 });
  const restartPid = number(restart.pid, "runtime_pid_invalid", "runtime", "restart pid", { integer: true, min: 1 });
  const firstCdp = number(first.cdpPort, "runtime_port_invalid", "runtime", "first CDP port", { integer: true, min: 1024, max: 65535 });
  const restartCdp = number(restart.cdpPort, "runtime_port_invalid", "runtime", "restart CDP port", { integer: true, min: 1024, max: 65535 });
  number(first.controlPort, "runtime_port_invalid", "runtime", "first control port", { integer: true, min: 1024, max: 65535 });
  number(restart.controlPort, "runtime_port_invalid", "runtime", "restart control port", { integer: true, min: 1024, max: 65535 });
  if (firstPid === restartPid || firstCdp === restartCdp
      || first.controlBindingPid !== firstPid || restart.controlBindingPid !== restartPid
      || first.cdpBindingPid !== firstPid || restart.cdpBindingPid !== restartPid
      || first.cdpExclusiveBeforeLaunch !== true || restart.cdpExclusiveBeforeLaunch !== true) {
    fail("runtime_freshness_invalid", "runtime", "restart PID/CDP endpoint is not fresh and separately rebound");
  }
  const verified = Date.parse(bundle.candidate.verifiedAt);
  const mutated = Date.parse(bundle.clone.mutatedAt);
  const firstStarted = Date.parse(first.startedAt);
  const restartStarted = Date.parse(restart.startedAt);
  if (![verified, mutated, firstStarted, restartStarted].every(Number.isFinite)
      || verified > mutated || mutated > firstStarted || firstStarted >= restartStarted) {
    fail("runtime_timeline_invalid", "runtime", "candidate verification, clone mutation, and restart ordering is invalid");
  }
  return { firstPid, restartPid, firstCdp, restartCdp,
    production: verifyProduction(bundle, verifiedPairs) };
}

function verifyDiskManifest(value, slot, phase) {
  const unsigned = Object.assign({}, value || {});
  delete unsigned.evidenceSha256;
  if (!hasExactKeys(value, ["schema", "slot", "capturedAt", "sourceSetSha256", "artifacts",
    "evidenceSha256"])
      || value.schema !== "workbench-live-e2e.npc.disk-artifact-set.v1"
      || value.slot !== slot || !Number.isFinite(Date.parse(value.capturedAt))
      || !SHA256_RE.test(String(value.sourceSetSha256 || ""))
      || !Array.isArray(value.artifacts) || value.artifacts.length < 1
      || canonicalJson(value.artifacts) !== canonicalJson(value.artifacts.slice().sort((left, right) =>
        String(left.locator).localeCompare(String(right.locator))))
      || new Set(value.artifacts.map((entry) => entry && entry.locator)).size !== value.artifacts.length
      || value.artifacts.filter((entry) => entry && entry.kind === "json").length !== 1
      || value.artifacts.filter((entry) => entry && entry.kind === "sol").length < 1
      || value.artifacts.some((entry) => !hasExactKeys(entry,
        ["kind", "locator", "sha256", "bytes", "regularFile", "exactRealPath"])
        || !["json", "sol"].includes(entry.kind)
        || !/^(?:root|appdata):/.test(String(entry.locator || ""))
        || !SHA256_RE.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || entry.regularFile !== true || entry.exactRealPath !== true)
      || value.evidenceSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("disk_artifact_manifest_invalid", phase,
      "JSON/SOL artifact manifest is malformed, incomplete, or detached");
  }
  const json = value.artifacts.find((entry) => entry.kind === "json");
  if (json.locator !== "root:saves/" + slot + ".json"
      || value.artifacts.filter((entry) => entry.kind === "sol")
        .some((entry) => !entry.locator.startsWith("appdata:")
          || !entry.locator.toLowerCase().endsWith("/" + slot.toLowerCase() + ".sol"))) {
    fail("disk_artifact_locator_invalid", phase,
      "JSON/SOL manifest does not identify the exact clone slot");
  }
  return value;
}

function verifyPersistence(bundle, artifacts, firstRecords, finalFingerprint, restartFingerprint,
  finalSourceFingerprint, restartSourceFingerprint, finalCommitResponseLine) {
  if (!isPlainObject(bundle.clone) || bundle.clone.lockExclusive !== true
      || bundle.clone.slot !== bundle.slot || bundle.clone.lockReleasedAfterResidue !== true
      || !Number.isFinite(Date.parse(bundle.clone.lockReleasedAt))) {
    fail("clone_lock_invalid", "persistence", "dedicated clone lock/lifecycle evidence is invalid");
  }
  const seedBefore = readManifestJson(artifacts, bundle.clone.seedBeforeArtifact, "seed_manifest", "persistence");
  const seedAfter = readManifestJson(artifacts, bundle.clone.seedAfterArtifact, "seed_manifest", "persistence");
  const seedBeforeManifest = verifyDiskManifest(seedBefore && seedBefore.manifest,
    seedBefore && seedBefore.slot, "persistence");
  const seedAfterManifest = verifyDiskManifest(seedAfter && seedAfter.manifest,
    seedAfter && seedAfter.slot, "persistence");
  const seedSols = seedBeforeManifest.artifacts.filter((entry) => entry.kind === "sol");
  if (!deepEqual(seedBefore, seedAfter)
      || !hasExactKeys(seedBefore, ["slot", "jsonSha256", "solSetSha256", "solFiles",
        "artifactSetSha256", "manifest"])
      || !SHA256_RE.test(String(seedBefore.jsonSha256 || ""))
      || !SHA256_RE.test(String(seedBefore.solSetSha256 || ""))
      || !SHA256_RE.test(String(seedBefore.artifactSetSha256 || ""))
      || seedBefore.jsonSha256 !== seedBeforeManifest.artifacts.find((entry) => entry.kind === "json").sha256
      || seedBefore.solSetSha256 !== sha256Text(canonicalJson(seedSols))
      || canonicalJson(seedBefore.solFiles) !== canonicalJson(seedSols)
      || seedBefore.artifactSetSha256 !== seedBeforeManifest.sourceSetSha256
      || canonicalJson(seedBeforeManifest) !== canonicalJson(seedAfterManifest)) {
    fail("seed_invariant_failed", "persistence", "seed JSON/SOL set changed during the live journey");
  }
  const archiveDisk = verifyDiskManifest(readManifestJson(artifacts,
    bundle.clone.afterArchiveArtifact, "clone_disk_manifest", "persistence"),
  bundle.slot, "persistence");
  const restartDisk = verifyDiskManifest(readManifestJson(artifacts,
    bundle.clone.afterRestartArtifact, "clone_disk_manifest", "persistence"),
  bundle.slot, "persistence");
  const archiveJson = archiveDisk.artifacts.find((entry) => entry.kind === "json");
  const restartJson = restartDisk.artifacts.find((entry) => entry.kind === "json");
  if (bundle.clone.baselineJsonSha256 === bundle.clone.afterArchiveJsonSha256
      || !SHA256_RE.test(String(bundle.clone.baselineJsonSha256 || ""))
      || !SHA256_RE.test(String(bundle.clone.afterArchiveJsonSha256 || ""))
      || bundle.clone.afterRestartJsonSha256 !== bundle.clone.afterArchiveJsonSha256
      || !SHA256_RE.test(String(bundle.clone.afterArchiveArtifactSetSha256 || ""))
      || bundle.clone.afterRestartArtifactSetSha256 !== bundle.clone.afterArchiveArtifactSetSha256
      || !SHA256_RE.test(String(bundle.clone.afterArchiveSolSetSha256 || ""))
      || bundle.clone.afterRestartSolSetSha256 !== bundle.clone.afterArchiveSolSetSha256
      || archiveDisk.sourceSetSha256 !== bundle.clone.afterArchiveArtifactSetSha256
      || restartDisk.sourceSetSha256 !== bundle.clone.afterRestartArtifactSetSha256
      || sha256Text(canonicalJson(archiveDisk.artifacts.filter((entry) => entry.kind === "sol")))
        !== bundle.clone.afterArchiveSolSetSha256
      || sha256Text(canonicalJson(restartDisk.artifacts.filter((entry) => entry.kind === "sol")))
        !== bundle.clone.afterRestartSolSetSha256
      || archiveJson.sha256 !== bundle.clone.afterArchiveJsonSha256
      || restartJson.sha256 !== bundle.clone.afterRestartJsonSha256
      || canonicalJson(archiveDisk.artifacts) !== canonicalJson(restartDisk.artifacts)) {
    fail("clone_archive_not_changed", "persistence", "dedicated clone did not receive an archived mutation");
  }
  if (!isPlainObject(bundle.archive) || bundle.archive.slot !== bundle.slot
      || !Number.isInteger(bundle.archive.hostLine) || bundle.archive.hostLine < 1
      || !Number.isInteger(bundle.archive.characters) || bundle.archive.characters < 1
      || !Number.isFinite(Date.parse(bundle.archive.observedAt))) {
    fail("archive_evidence_invalid", "persistence", "archive receipt is missing or ordered before final commit");
  }
  const expectedSuffix = path.join("saves", bundle.slot + ".json").toLowerCase();
  const archive = requireOne(firstRecords.filter((record) => record.lineNumber === bundle.archive.hostLine
    && record.body.startsWith("[ArchiveTask] Shadow saved: " + bundle.slot + " (" + bundle.archive.characters
      + " chars) path=") && record.body.toLowerCase().endsWith(expectedSuffix)),
  "archive_host_record_invalid", "persistence", "exact archive Host receipt is absent");
  if (!archive || !Number.isInteger(finalCommitResponseLine)
      || finalCommitResponseLine >= bundle.archive.sv1HostLine
      || bundle.archive.sv1HostLine >= bundle.archive.hostLine
      || bundle.archive.sv2HostLine >= bundle.archive.hostLine
      || bundle.archive.sv1HostLine >= bundle.archive.sv2HostLine) {
    fail("archive_order_invalid", "persistence", "sv:1→sv:2→archive ordering is invalid");
  }
  const sv1 = firstRecords.find((record) => record.lineNumber === bundle.archive.sv1HostLine);
  const sv2 = firstRecords.find((record) => record.lineNumber === bundle.archive.sv2HostLine);
  if (!sv1 || !sv2 || sv1.body !== "sv:1" || sv2.body !== "sv:2") {
    fail("archive_save_markers_invalid", "persistence", "archive ordering lines are not the required sv:1/sv:2 markers");
  }
  const finalHostResponse = firstRecords.find((record) =>
    record.lineNumber === finalCommitResponseLine);
  const saveTimeline = [finalHostResponse && finalHostResponse.observedAt,
    sv1.observedAt, sv2.observedAt, archive.observedAt, bundle.archive.observedAt,
    archiveDisk.capturedAt].map(Date.parse);
  if (saveTimeline.some((value) => !Number.isFinite(value))
      || saveTimeline.some((value, index) => index > 0 && value < saveTimeline[index - 1])) {
    fail("archive_timeline_invalid", "persistence",
      "final Host response, sv:1, sv:2, archive receipt, and disk capture are not one monotonic chain");
  }
  if (finalFingerprint !== restartFingerprint) {
    fail("restart_semantic_readback_mismatch", "persistence", "fresh PID readback differs from final committed authority state");
  }
  if (!SHA256_RE.test(finalSourceFingerprint) || !SHA256_RE.test(restartSourceFingerprint)
      || finalSourceFingerprint === restartSourceFingerprint) {
    // Leases must rotate across fresh owners; equal source fingerprints would indicate stale replay.
    fail("restart_source_fingerprint_invalid", "persistence",
      "fresh restart did not produce distinct authoritative source leases/fingerprint");
  }
  const receipt = {
    archiveHostLine: bundle.archive.hostLine,
    finalCommitResponseHostLine: finalCommitResponseLine,
    finalFingerprint,
    restartFingerprint,
    finalSourceFingerprint,
    restartSourceFingerprint,
  };
  return receipt;
}

function verifyResidue(bundle, control, hostLog, restartHost, artifacts) {
  const residue = bundle.residue;
  const residueKeys = ["schema", "checkedAfterRestartShutdown", "checkedAt", "first", "restart",
    "cloneLockReleased", "cloneLockReleasedAt", "evidenceSha256"];
  const unsigned = Object.assign({}, residue || {}); delete unsigned.evidenceSha256;
  if (!isPlainObject(residue)
      || canonicalJson(Object.keys(residue).sort()) !== canonicalJson(residueKeys.slice().sort())
      || residue.schema !== "workbench-live-e2e.npc.runtime-residue.v2"
      || residue.checkedAfterRestartShutdown !== true || residue.cloneLockReleased !== true
      || !Number.isFinite(Date.parse(residue.checkedAt))
      || !Number.isFinite(Date.parse(residue.cloneLockReleasedAt))
      || residue.cloneLockReleasedAt !== bundle.clone.lockReleasedAt
      || residue.evidenceSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("runtime_residue_present", "residue",
      "complete first/restart residue envelope is missing or detached");
  }
  function clean(value, runtime, label) {
    try { LauncherObservation.assertResidueClean(value); }
    catch (error) {
      fail("runtime_residue_present", "residue", "shared residue receipt is not clean", {
        label, code: error && error.code,
      });
    }
    const ports = value.ports.map((entry) => entry.port);
    if (value.expectedPid !== runtime.pid
        || path.resolve(value.expectedProcessPath).toLowerCase()
          !== path.resolve(runtime.stableIdentity.processPath).toLowerCase()
        || !ports.includes(runtime.controlPort) || !ports.includes(runtime.cdpPort)
        || new Set(ports).size !== 3 || value.observedLauncherPids.length !== 0
        || value.pidAbsent !== true || value.candidateProcessAbsent !== true
        || value.portsFileAbsent !== true || value.credentialFileAbsent !== true
        || value.stableSamples < 2) {
      fail("runtime_residue_identity_mismatch", "residue",
        "residue is not bound to the exact lifecycle PID/path/three ports/credential files", { label });
    }
  }
  clean(residue.first, bundle.runtime.first, "first");
  clean(residue.restart, bundle.runtime.restart, "restart");
  const shutdown = bundle.shutdown;
  const shutdownResponse = readManifestJson(artifacts, bundle.shutdownResponseArtifact,
    "supported_shutdown_response", "residue");
  const shutdownUnsigned = Object.assign({}, shutdown || {}); delete shutdownUnsigned.evidenceSha256;
  const requestedAt = Date.parse(shutdown && shutdown.requestedAt);
  const completedAt = Date.parse(shutdown && shutdown.completedAt);
  const restartTerminalAt = Date.parse(hostLog.lifecycles.restart.terminalSnapshot.capturedAt);
  const exitConfirm = controlByStep(control, "exit_confirm");
  if (!isPlainObject(shutdown) || shutdown.schema !== "workbench-live-e2e.npc.supported-shutdown.v1"
      || shutdown.lifecycle !== "restart" || shutdown.action !== "shutdown"
      || shutdown.pid !== bundle.runtime.restart.pid || shutdown.responseSucceeded !== true
      || !SHA256_RE.test(String(shutdown.responseSha256 || ""))
      || !isPlainObject(shutdownResponse)
      || shutdown.responseSha256 !== sha256Text(canonicalJson(shutdownResponse))
      || shutdown.evidenceSha256 !== sha256Text(canonicalJson(shutdownUnsigned))
      || !Number.isFinite(requestedAt) || !Number.isFinite(completedAt) || requestedAt > completedAt
      || Date.parse(restartHost.closeSettledAt) > requestedAt || restartTerminalAt > requestedAt
      || completedAt > Date.parse(residue.restart.observedAt)
      || Date.parse(exitConfirm.providerReceipt.completedAt) > Date.parse(residue.first.observedAt)
      || residue.checkedAt !== residue.restart.observedAt
      || Date.parse(residue.cloneLockReleasedAt) < Date.parse(residue.checkedAt)) {
    fail("supported_shutdown_timeline_invalid", "residue",
      "supported shutdown and complete residue are not causally ordered");
  }
  try { LauncherObservation.assertResponseSucceeded(shutdownResponse, "residue", "supported shutdown"); }
  catch (error) {
    fail("supported_shutdown_response_invalid", "residue",
      "supported shutdown response artifact is not a successful Launcher receipt", {
        code: error && error.code,
      });
  }
  return residue;
}

const FINAL_ARTIFACT_PATHS = Object.freeze([
  "artifact-manifest.json", "evidence-bundle.json", "receipt.json", "status.json",
]);

function artifactRolesForBundle(bundle) {
  const roles = Object.create(null);
  roles[bundle.transcriptArtifact] = "passive_transcript";
  roles[bundle.hostLogArtifact] = "host_log";
  roles[bundle.clone.seedBeforeArtifact] = "seed_manifest";
  roles[bundle.clone.seedAfterArtifact] = "seed_manifest";
  roles[bundle.clone.afterArchiveArtifact] = "clone_disk_manifest";
  roles[bundle.clone.afterRestartArtifact] = "clone_disk_manifest";
  roles[bundle.shutdownResponseArtifact] = "supported_shutdown_response";
  if (bundle.evidenceMode === "live_capture") {
    roles["passive-transcript.jsonl"] = "passive_transcript_stream";
  } else {
    [
      ["fixture-candidate/CRAZYFLASHER7MercenaryEmpire.exe", "candidate_payload"],
      ["fixture-candidate/runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", "candidate_payload"],
      ["fixture-candidate/runtime/cf7-runtime-manifest.tsv", "candidate_manifest"],
      ["fixture-candidate/runtime-build-metadata.v2.json", "candidate_metadata"],
    ].forEach(([relativePath, role]) => { roles[relativePath] = role; });
  }
  if (!Array.isArray(bundle.controls)) {
    fail("controls_missing", "control", "control bindings are missing");
  }
  bundle.controls.forEach((binding) => {
    if (!isPlainObject(binding) || typeof binding.requestArtifact !== "string"
        || typeof binding.ackArtifact !== "string") {
      fail("control_binding_invalid", "control", "control binding is malformed");
    }
    assertOpaqueId(binding.requestId, "control_binding_invalid", "control", "control requestId");
    roles[binding.requestArtifact] = "control_request";
    roles[binding.ackArtifact] = "control_ack";
    // The artifact inventory is derived from the immutable binding identity, not
    // from an unvalidated ACK.  A malformed/missing ACK reference must therefore
    // reach validateAck() as a fail-closed NpcJourneyError instead of throwing a
    // raw TypeError while the inventory is being projected.
    roles[captureRelativePath(binding.requestId)] = "control_capture";
    roles[providerReceiptRelativePath(binding.requestId)] = "provider_receipt";
  });
  return roles;
}

function verifyArtifactClosure(bundle, runDir, options) {
  const settings = options || {};
  const roles = artifactRolesForBundle(bundle);
  if (settings.preSeal === true) {
    ["artifact-manifest.json", "evidence-bundle.json", "receipt.json"].forEach((name) => {
      if (fs.existsSync(path.join(runDir, name))) {
        fail("preseal_artifact_state_invalid", "artifacts",
          "final artifact exists before journal admission", { name });
      }
    });
  } else {
    const persisted = readJson(path.join(runDir, "artifact-manifest.json"), "artifact_manifest");
    if (!deepEqual(persisted, bundle.artifactManifest)) {
      fail("artifact_manifest_bundle_mismatch", "artifacts",
        "persisted artifact manifest differs from the bundle projection");
    }
  }
  const artifacts = verifyArtifactManifest(runDir, bundle.artifactManifest, {
    runId: bundle.runId,
    roleByPath: roles,
    excludedPaths: FINAL_ARTIFACT_PATHS,
  });
  if (bundle.evidenceMode === "live_capture") {
    const jsonl = artifacts.get("passive-transcript.jsonl");
    if (!jsonl) fail("transcript_stream_missing", "transcript",
      "live capture lacks the append-only passive transcript stream");
    const text = fs.readFileSync(jsonl.absolutePath, "utf8");
    if (!text.endsWith("\n")) {
      fail("transcript_stream_invalid", "transcript", "passive transcript stream lacks final newline");
    }
    let rows;
    try { rows = text.slice(0, -1).split("\n").filter(Boolean).map((line) => JSON.parse(line)); }
    catch (error) {
      fail("transcript_stream_invalid", "transcript", "passive transcript stream is invalid JSONL", {
        message: error.message,
      });
    }
    const summary = readManifestJson(artifacts, bundle.transcriptArtifact,
      "passive_transcript", "transcript");
    if (!deepEqual(rows, summary.events)) {
      fail("transcript_stream_mismatch", "transcript",
        "passive transcript stream differs from its summary");
    }
  }
  return artifacts;
}

function verifyBundle(bundle, runDir, options) {
  const settings = options || {};
  const preSeal = settings.preSeal === true;
  if (!isPlainObject(bundle) || bundle.schema !== BUNDLE_SCHEMA) {
    fail("bundle_contract_invalid", "bundle", "NPC live evidence bundle schema is invalid");
  }
  assertOpaqueId(bundle.runId, "run_id_invalid", "bundle", "runId");
  assertSafeSlot(bundle.slot);
  if (![FULL_MODE, PURCHASE_ONLY_MODE].includes(bundle.journeyMode)) {
    fail("journey_mode_invalid", "bundle", "NPC journey mode is invalid");
  }
  if (typeof bundle.shopId !== "string" || !bundle.shopId || !path.isAbsolute(bundle.root)
      || !path.isAbsolute(bundle.candidateRoot) || !path.isAbsolute(bundle.runDir)
      || path.resolve(bundle.runDir).toLowerCase() !== path.resolve(runDir).toLowerCase()) {
    fail("bundle_identity_invalid", "bundle", "root/candidate/shop identity is incomplete");
  }
  if (!["offline_fixture", "live_capture"].includes(bundle.evidenceMode)) {
    fail("evidence_mode_invalid", "bundle",
      "NPC bundle must declare one exact offline_fixture or live_capture mode");
  }
  if (bundle.evidenceMode === "live_capture") {
    const ownedBase = path.join(CANONICAL_ROOT, "tmp", "workbench-live-e2e", "npc");
    const relativeRun = path.relative(ownedBase, path.resolve(runDir));
    if (!relativeRun || relativeRun.startsWith(".." + path.sep) || path.isAbsolute(relativeRun)) {
      fail("live_run_directory_invalid", "bundle",
        "live evidence run directory is outside the fixed NPC-owned base");
    }
  }
  verifyEvidenceOrigin(bundle, { preSeal });
  if (Object.prototype.hasOwnProperty.call(bundle, "offlineFixture")) {
    fail("legacy_evidence_mode_field_forbidden", "bundle",
      "legacy offlineFixture ambiguity is not part of the closed evidence-mode contract");
  }
  if (bundle.evidenceMode === "offline_fixture") {
    const provenance = bundle.fixtureProvenance;
    if (bundle.runId !== "npc.fixture.20260803"
        || bundle.root !== CANONICAL_ROOT
        || !isPlainObject(provenance)
        || canonicalJson(Object.keys(provenance).sort()) !== canonicalJson([
          "schema", "generator", "synthetic", "liveEvidence"].sort())
        || provenance.schema !== "workbench-live-e2e.npc.offline-fixture-provenance.v1"
        || provenance.generator !== "tools/workbench-live-e2e/npc/fixtures/valid-bundle.js"
        || provenance.synthetic !== true || provenance.liveEvidence !== false
        || Object.prototype.hasOwnProperty.call(bundle, "moduleJournal")) {
      fail("offline_fixture_identity_invalid", "bundle",
        "offline fixture exemption is not bound to the closed synthetic identity");
    }
  } else {
    if (Object.prototype.hasOwnProperty.call(bundle, "fixtureProvenance")) {
      fail("live_fixture_field_forbidden", "bundle",
        "live capture cannot contain offline fixture provenance");
    }
    if (!isPlainObject(bundle.moduleJournal) || !isPlainObject(bundle.moduleJournal.manifest)
        || (preSeal ? bundle.moduleJournal.artifact !== null
          : !isPlainObject(bundle.moduleJournal.artifact))) {
      fail("module_journal_missing", "bundle", "production bundle lacks sealed module admission");
    }
    try {
      if (canonicalJson(bundle.moduleJournal.manifest.requiredPhases) !== canonicalJson(LIVE_PHASES)) {
        fail("live_module_phase_profile_invalid", "bundle",
          "production module journal does not carry the exact live-only phase profile");
      }
      if (preSeal) RuntimeModuleJournal.verifyExplicitModuleManifest({ root: CANONICAL_ROOT,
        manifest: bundle.moduleJournal.manifest });
      else RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: CANONICAL_ROOT,
        manifest: bundle.moduleJournal.manifest, artifact: bundle.moduleJournal.artifact });
    } catch (error) {
      fail(error && error.code || "module_journal_invalid", "bundle",
        "production bundle module admission is invalid", { message: error && error.message });
    }
  }
  const artifacts = verifyArtifactClosure(bundle, runDir, { preSeal });
  const transcript = readManifestJson(artifacts, bundle.transcriptArtifact, "passive_transcript", "transcript");
  const events = verifyEventChain(transcript);
  events.filter((event) => event.kind === "dom_input").forEach((event) => {
    requireDomInput([event], () => true, "dom_input_evidence_invalid", "transcript",
      "raw DOM input is not one exact trusted interaction record");
  });
  const hostLog = readManifestJson(artifacts, bundle.hostLogArtifact, "host_log", "host_log");
  const records = normalizedHostRecords(hostLog);
  const control = verifyControls(bundle, artifacts, transcript);
  const outbound = outboundMessages(events);
  const inbound = inboundMessages(events);
  const requests = panelRequests(outbound);
  const responses = panelResponses(inbound);
  const pairs = requestPairs(requests, responses);
  if (pairs.some((pair) => pair.request.event.sendOrder !== "after_panel_request_mux_onIssued")) {
    fail("web_send_order_invalid", "protocol",
      "Bridge.send observation is not bound after PanelRequestMux onIssued");
  }
  assertNoNpcOverlap(pairs);
  const opens = openCommands(inbound);
  const phases = assertFreshInstances(opens, bundle);
  assertRealIngress(records, phases.length, bundle.shopId);

  const byName = Object.fromEntries(phases.map((phase) => [phase.name, phase]));
  const initialNpc = phasePair(requests, responses, byName.first.id, "snapshot", "npcshop",
    bundle.calls.initialNpcSnapshot, "purchase_initial_snapshot");
  const initialInventoryState = phaseInventorySurface(requests, responses, byName.first.id,
    bundle.calls.initialInventorySnapshots, bundle.calls.initialInventorySnapshot,
    "purchase_initial_inventory");
  assertNoSurfaceWriteInterleaving(initialInventoryState, requests, "purchase_initial_inventory");
  const initialState = assertSuccess(initialNpc, "purchase_initial_snapshot");
  if (initialInventoryState.firstPair.request.event.sequence >= initialNpc.request.event.sequence) {
    fail("initial_request_order_invalid", "purchase",
      "Inventory snapshot request must precede NPC snapshot request on first open");
  }
  const policy = bundle.purchasePolicy;
  if (!isPlainObject(policy) || Number(policy.quantity) !== 1) {
    fail("purchase_policy_invalid", "purchase", "purchase policy must identify one exact catalog item");
  }
  const purchaseCatalogEntry = assertCatalogTarget(initialState, policy, "purchase");
  const purchasePreview = phasePair(requests, responses, byName.first.id, "tradePreview", "npcshop",
    bundle.calls.purchasePreview, "purchase_preview");
  assertRequestShape(purchasePreview, {
    v: 1,
    shopId: bundle.shopId,
    purchases: [{ catalogIndex: Number(policy.catalogIndex), quantity: 1 }],
    sales: [],
  }, "purchase_preview");
  const purchasePreviewMessage = assertSuccess(purchasePreview, "purchase_preview");
  assertPurchasePreview(purchasePreviewMessage, policy, initialState.balance,
    initialInventoryState, "purchase_preview");
  const purchaseCommit = phasePair(requests, responses, byName.first.id, "tradeCommit", "npcshop",
    bundle.calls.purchaseCommit, "purchase_commit");
  assertTokenLink(purchasePreview.response, purchaseCommit.request, "purchase_commit");
  const purchaseCommitMessage = assertSuccess(purchaseCommit, "purchase_commit");
  assertCommitState(purchaseCommitMessage, purchasePreviewMessage, "purchase", "purchase_commit");
  if (!(purchasePreview.response.event.sequence < purchaseCommit.request.event.sequence
      && purchaseCommit.request.event.sequence < purchaseCommit.response.event.sequence)) {
    fail("purchase_order_invalid", "purchase", "purchase preview/token/commit order is invalid");
  }
  const purchasePostInventoryState = phaseInventorySurface(requests, responses, byName.first.id,
    bundle.calls.purchasePostInventories, bundle.calls.purchasePostInventory,
    "purchase_post_inventory");
  assertNoSurfaceWriteInterleaving(purchasePostInventoryState, requests, "purchase_post_inventory");
  if (purchasePostInventoryState.firstPair.request.event.sequence
      < purchaseCommit.response.event.sequence) {
    fail("purchase_refresh_order_invalid", "purchase", "post-purchase inventory refresh preceded commit response");
  }
  const purchaseDestination = assertPurchaseInventoryDelta(initialInventoryState,
    purchasePostInventoryState, policy, purchaseCatalogEntry);
  assertStableRevisionLeases(initialInventoryState, purchasePostInventoryState,
    "purchase_inventory_revision");
  const postPurchaseState = purchaseCommitMessage;
  const postPurchaseInventoryState = purchasePostInventoryState;
  assertPurchaseControls(control, events, byName.first.open, purchasePreview, purchaseCommit, policy);

  let finalNpcState = postPurchaseState;
  let finalInventoryState = postPurchaseInventoryState;
  let lastCommit = purchaseCommit;
  const commitPairs = [purchaseCommit];
  const previewTokenRefs = [purchasePreviewMessage.tradeToken];
  let saleSummary = null;
  let firstClose = null;

  if (bundle.journeyMode === FULL_MODE) {
    const salePolicy = Object.assign({}, bundle.salePolicy, { forbiddenPurchasedItem: policy.itemName });
    const sourceSlot = assertSalePolicy(postPurchaseInventoryState, salePolicy);
    const previewRequests = requestsFor(requests, byName.first.id, "tradePreview", "npcshop")
      .filter((entry) => entry.event.sequence > purchaseCommit.response.event.sequence);
    if (previewRequests.length < 1 || previewRequests.length > 2
        || (salePolicy.requiresQuantityAdjustment ? previewRequests.length !== 2 : previewRequests.length !== 1)) {
      fail("sale_preview_multiset_invalid", "sale", "sale preview count does not match exact UI quantity flow", {
        actual: previewRequests.length,
        requiresQuantityAdjustment: !!salePolicy.requiresQuantityAdjustment,
      });
    }
    const salePreviewPairs = previewRequests.map((request, index) => {
      if (request.message.callId !== bundle.calls.salePreviews[index]) {
        fail("sale_preview_call_order_invalid", "sale", "sale preview callId/order differs from sealed evidence");
      }
      return { request, response: responseFor(request, responses, "sale_preview") };
    });
    const salePreviewLines = [];
    salePreviewPairs.forEach((pair, index) => {
      assertSuccess(pair, "sale_preview");
      previewTokenRefs.push(pair.response.message.tradeToken);
      salePreviewLines.push(assertSalePreview(pair, sourceSlot, salePolicy, postPurchaseState.balance,
        postPurchaseInventoryState, index === salePreviewPairs.length - 1,
        "sale_preview_" + (index + 1)));
      if (index > 0 && pair.request.event.sequence < salePreviewPairs[index - 1].response.event.sequence) {
        fail("sale_preview_overlap", "sale", "sale preview replacement overlapped an unfinished preview");
      }
    });
    if (salePreviewLines.length === 2
        && Number(salePreviewLines[0].total) !== Number(salePreviewLines[1].total)
          * Number(salePreviewLines[0].quantity)) {
      fail("sale_price_formula_invalid", "sale",
        "full-stack and one-unit authoritative sale previews do not preserve one exact unit price");
    }
    const finalSalePreview = salePreviewPairs.at(-1);
    const saleCommit = phasePair(requests, responses, byName.first.id, "tradeCommit", "npcshop",
      bundle.calls.saleCommit, "sale_commit");
    assertTokenLink(finalSalePreview.response, saleCommit.request, "sale_commit");
    const saleCommitMessage = assertSuccess(saleCommit, "sale_commit");
    assertCommitState(saleCommitMessage, finalSalePreview.response.message, "sale", "sale_commit");
    if (saleCommit.request.event.sequence < finalSalePreview.response.event.sequence) {
      fail("sale_commit_order_invalid", "sale", "sale commit preceded final one-unit preview response");
    }
    const salePostInventoryState = phaseInventorySurface(requests, responses, byName.first.id,
      bundle.calls.salePostInventories, bundle.calls.salePostInventory, "sale_post_inventory");
    assertNoSurfaceWriteInterleaving(salePostInventoryState, requests, "sale_post_inventory");
    if (salePostInventoryState.firstPair.request.event.sequence < saleCommit.response.event.sequence) {
      fail("sale_refresh_order_invalid", "sale", "post-sale inventory refresh preceded commit response");
    }
    assertSaleInventoryDelta(postPurchaseInventoryState, salePostInventoryState, salePolicy);
    assertStableRevisionLeases(postPurchaseInventoryState, salePostInventoryState,
      "sale_inventory_revision");
    firstClose = assertClose(requests, byName.first.id, "first_close");
    if (firstClose.event.sequence < salePostInventoryState.lastPair.response.event.sequence) {
      fail("sale_close_order_invalid", "sale", "first owner closed before fresh sale postcondition");
    }
    assertSaleControls(control, events, byName.first.open, salePreviewPairs, saleCommit, firstClose, salePolicy);
    finalNpcState = saleCommitMessage;
    finalInventoryState = salePostInventoryState;
    lastCommit = saleCommit;
    commitPairs.push(saleCommit);
    saleSummary = {
      slot: salePolicy.slot,
      itemName: salePolicy.expectedItem,
      quantity: 1,
      previewCount: salePreviewPairs.length,
      finalPreviewCallId: finalSalePreview.request.message.callId,
      commitCallId: saleCommit.request.message.callId,
      eligibleCount: finalSalePreview.response.message.saleLines[0].eligibleCount,
      protectedCount: finalSalePreview.response.message.saleLines[0].protectedCount,
    };
  } else {
    firstClose = assertClose(requests, byName.first.id, "first_close");
    const closeInput = requireDomInput(events, (event) =>
      event.sequence > purchasePostInventoryState.lastPair.response.event.sequence
      && event.sequence < firstClose.event.sequence && event.eventType === "click"
      && event.target && event.target.tagName === "BUTTON"
      && event.target.selector === "button[aria-label=\"关闭 NPC 商店\"]"
      && targetAttribute(event, "aria-label") === "关闭 NPC 商店",
    "purchase_close_input_missing", "purchase", "first owner close input is absent");
    assertControlIncludes(control, "close_before_exit", [closeInput, firstClose], "panel_close");
  }

  if (previewTokenRefs.some((value) => !TOKEN_REF_RE.test(String(value || "")))
      || new Set(previewTokenRefs).size !== previewTokenRefs.length) {
    fail("trade_token_reused", "protocol",
      "every authoritative preview token must be fresh and single-use across the journey");
  }

  const restartNpc = phasePair(requests, responses, byName.restart.id, "snapshot", "npcshop",
    bundle.calls.restartNpcSnapshot, "restart_snapshot");
  const restartInventoryState = phaseInventorySurface(requests, responses, byName.restart.id,
    bundle.calls.restartInventorySnapshots, bundle.calls.restartInventorySnapshot,
    "restart_inventory");
  assertNoSurfaceWriteInterleaving(restartInventoryState, requests, "restart_inventory");
  const restartNpcState = assertSuccess(restartNpc, "restart_snapshot");
  if (restartInventoryState.firstPair.request.event.sequence >= restartNpc.request.event.sequence) {
    fail("restart_request_order_invalid", "restart",
      "Inventory snapshot request must precede NPC snapshot request after restart");
  }
  const surfaceAccess = [initialInventoryState, purchasePostInventoryState,
    finalInventoryState, restartInventoryState];
  assertInventoryPhaseAccessConsistency(surfaceAccess, "persistence");
  const inventoryTimelineEvents = [
    ["initial", initialInventoryState],
    ["purchase-post", purchasePostInventoryState],
  ].concat(bundle.journeyMode === FULL_MODE ? [["sale-post", finalInventoryState]] : [], [
    ["restart", restartInventoryState],
  ]).flatMap(([phase, surface]) => surface.pairs.map((pair, pairOrdinal) => ({
    phase,
    pairOrdinal,
    callId: pair.request.message.callId,
    requestAt: pair.request.event.observedAt,
    responseAt: pair.response.event.observedAt,
  })));
  const closeRestart = assertClose(requests, byName.restart.id, "restart_close");
  if (closeRestart.event.sequence < restartInventoryState.lastPair.response.event.sequence) {
    fail("restart_close_order_invalid", "restart",
      "restart owner closed before its full Inventory surface was re-probed");
  }
  const restartCloseInput = requireDomInput(events, (event) =>
    event.sequence > restartNpc.response.event.sequence
    && event.sequence < closeRestart.event.sequence && event.eventType === "click"
    && event.target && event.target.tagName === "BUTTON"
    && event.target.selector === "button[aria-label=\"关闭 NPC 商店\"]"
    && targetAttribute(event, "aria-label") === "关闭 NPC 商店",
  "restart_close_input_missing", "restart", "restart owner close input is absent");
  assertControlIncludes(control, "open_restart_readback", [byName.restart.open], "panel_open");
  assertControlIncludes(control, "close_restart_readback", [restartCloseInput, closeRestart], "panel_close");

  const expectedNpcRequests = 1 + 1 + commitPairs.length
    + 1 + (bundle.journeyMode === FULL_MODE
      ? bundle.calls.salePreviews.length : 0); // snapshots + commits + purchase preview + sale previews
  const npcRequests = requests.filter((entry) => entry.message.domain === "npcshop");
  const inventoryCallIds = bundle.calls.initialInventorySnapshots
    .concat(bundle.calls.purchasePostInventories, bundle.calls.salePostInventories,
      bundle.calls.restartInventorySnapshots);
  const expectedInventoryRequests = inventoryCallIds.length;
  const inventoryRequests = requests.filter((entry) => entry.message.domain === "inventory");
  if (npcRequests.length !== expectedNpcRequests || inventoryRequests.length !== expectedInventoryRequests
      || canonicalJson(inventoryRequests.map((entry) => entry.message.callId))
        !== canonicalJson(inventoryCallIds)
      || requests.some((entry) => !["", "npcshop", "inventory"].includes(String(entry.message.domain || "")))) {
    fail("domain_request_multiset_invalid", "protocol", "NPC/inventory request multiset contains missing or extra operations", {
      npc: npcRequests.length,
      expectedNpcRequests,
      inventory: inventoryRequests.length,
      expectedInventoryRequests,
    });
  }
  const closeRequests = requests.filter((entry) => entry.message.cmd === "close");
  if (closeRequests.length !== phases.length) {
    fail("close_request_multiset_invalid", "protocol", "every owner must have exactly one close request");
  }

  const firstRecords = hostLifecycleRecords(hostLog, "first");
  const restartRecords = hostLifecycleRecords(hostLog, "restart");
  const mapped = pairs.map((pair) => assertHostMapping(pair.request,
    pair.request.message.panelInstanceId === byName.first.id ? firstRecords : restartRecords,
    pair.response));
  assertUniqueMappings(mapped);
  const firstRequests = requests.filter((entry) => entry.message.panelInstanceId === byName.first.id);
  const restartRequests = requests.filter((entry) => entry.message.panelInstanceId === byName.restart.id);
  const firstMapped = mapped.filter((entry) => entry.panelInstanceId === byName.first.id);
  const restartMapped = mapped.filter((entry) => entry.panelInstanceId === byName.restart.id);
  const firstHost = verifyHostLifecycle(hostLog, "first", firstRequests, firstMapped, byName.first.id);
  const restartHost = verifyHostLifecycle(hostLog, "restart", restartRequests, restartMapped, byName.restart.id);
  if (!isPlainObject(bundle.archive)
      || firstHost.closeReceiptLine >= bundle.archive.sv1HostLine) {
    fail("host_close_before_archive_invalid", "host_log",
      "first exact-close completion must precede SAFEEXIT save markers and archive");
  }
  const commitMappings = commitPairs.map((pair) => requireOne(mapped.filter((mapping) =>
    mapping.domain === "npcshop" && mapping.webCallId === pair.request.message.callId),
  "commit_mapping_missing", "host_log", "tradeCommit lacks a unique Host→AS2 fid mapping"));
  assertNoUnmappedHostWrites(records, commitMappings, null);

  const runtime = verifyRuntime(bundle, pairs);
  [["first", runtime.firstPid], ["restart", runtime.restartPid]].forEach(([label, pid]) => {
    const lifecycle = hostLog.lifecycles[label];
    const snapshots = [lifecycle.startBoundary && lifecycle.startBoundary.snapshot,
      lifecycle.closeSettledSnapshot, lifecycle.terminalSnapshot]
      .concat(Object.values(lifecycle.timelineBoundaries || {}).map((boundary) =>
        boundary && boundary.snapshot));
    if (snapshots.some((snapshot) => !snapshot || snapshot.sessionPid !== pid)) {
      fail("host_runtime_pid_mismatch", "host_log",
        "every Host snapshot/boundary must bind the exact authenticated runtime PID", {
          label, expectedPid: pid,
        });
    }
  });
  const endpoints = events.filter((event) => event.kind === "cdp_endpoint_bound");
  const observerReady = events.filter((event) => event.kind === "observer_ready");
  const observerDetached = events.filter((event) => event.kind === "observer_detached");
  if (endpoints.length !== 2 || observerReady.length !== 2 || observerDetached.length !== 2
      || endpoints[0].runtimePid !== runtime.firstPid
      || endpoints[1].runtimePid !== runtime.restartPid
      || endpoints[0].cdpPort !== runtime.firstCdp
      || endpoints[1].cdpPort !== runtime.restartCdp
      || endpoints.some((event) => event.exclusiveBeforeLaunch !== true
        || event.pageUrl !== "https://overlay.local/overlay.html")
      || !(endpoints[0].sequence < observerReady[0].sequence
        && observerReady[0].sequence < byName.first.open.event.sequence
        && byName.first.open.event.sequence < observerDetached[0].sequence
        && observerDetached[0].sequence < endpoints[1].sequence
        && endpoints[1].sequence < observerReady[1].sequence
        && observerReady[1].sequence < byName.restart.open.event.sequence
        && byName.restart.open.event.sequence < observerDetached[1].sequence)) {
    fail("runtime_observer_lifecycle_invalid", "runtime",
      "fresh runtime PID/CDP/observer attach-detach boundaries are missing, duplicated, or reordered");
  }
  const readback = assertFreshAuthorityReadback(finalNpcState, finalInventoryState,
    restartNpcState, restartInventoryState, policy);
  const { finalFingerprint, restartFingerprint,
    finalSourceFingerprint, restartSourceFingerprint } = readback;
  const finalCommitMapping = requireOne(commitMappings.filter((entry) =>
    entry.webCallId === lastCommit.request.message.callId), "final_commit_mapping_missing",
  "persistence", "final commit lacks an exact Host response mapping");
  const persistence = verifyPersistence(bundle, artifacts, firstRecords, finalFingerprint,
    restartFingerprint, finalSourceFingerprint, restartSourceFingerprint,
    finalCommitMapping.responseLine);
  const residue = verifyResidue(bundle, control, hostLog, restartHost, artifacts);
  const firstCloseControl = controlByStep(control, "close_before_exit");
  const safeExitControl = controlByStep(control, "safe_exit");
  const exitConfirmControl = controlByStep(control, "exit_confirm");
  const firstCloseSettledAt = Date.parse(firstHost.closeSettledAt);
  const firstCloseCompletedAt = Date.parse(firstCloseControl.ack.completedAt);
  const safeExitIssuedAt = Date.parse(safeExitControl.request.issuedAt);
  const safeExitProviderCompletedAt = Date.parse(safeExitControl.providerReceipt.completedAt);
  const safeExitBoundary = bundle.timelineBoundaries
    && bundle.timelineBoundaries.safeExitProviderBoundary;
  const hostSafeExitBoundary = hostLog.lifecycles.first.timelineBoundaries
    && hostLog.lifecycles.first.timelineBoundaries.safe_exit_provider_completed;
  try { LauncherObservation.verifyTerminalLogBoundary(safeExitBoundary); }
  catch (error) {
    fail("safe_exit_host_boundary_invalid", "persistence",
      "SAFEEXIT provider completion lacks an exact Host boundary", { code: error && error.code });
  }
  if (canonicalJson(safeExitBoundary) !== canonicalJson(hostSafeExitBoundary)
      || safeExitBoundary.terminalTotal >= bundle.archive.sv1HostLine) {
    fail("safe_exit_host_boundary_invalid", "persistence",
      "SAFEEXIT provider boundary already contains save markers or differs from Host evidence");
  }
  const safeExitBoundaryAt = Date.parse(safeExitBoundary.capturedAt);
  const archiveObservedAt = Date.parse(bundle.archive.observedAt);
  const firstSealAt = Date.parse(hostLog.lifecycles.first.terminalSnapshot.capturedAt);
  const exitConfirmIssuedAt = Date.parse(exitConfirmControl.request.issuedAt);
  const exitConfirmProviderCompletedAt = Date.parse(exitConfirmControl.providerReceipt.completedAt);
  const finalResponseAt = Date.parse(lastCommit.response.event.observedAt);
  const firstCloseRequestAt = Date.parse(firstClose.event.observedAt);
  const expectedTimeline = sealTrustedTimeline({
    runId: bundle.runId,
    transcriptSha256: artifacts.get(bundle.transcriptArtifact).sha256,
    hostLogSha256: artifacts.get(bundle.hostLogArtifact).sha256,
    safeExitRequestId: safeExitControl.request.requestId,
    safeExitProviderOperationId: safeExitControl.providerReceipt.providerOperationId,
    exitConfirmRequestId: exitConfirmControl.request.requestId,
    exitConfirmProviderOperationId: exitConfirmControl.providerReceipt.providerOperationId,
    safeExitProviderBoundarySha256: sha256Text(canonicalJson(safeExitBoundary)),
    archiveHostLine: bundle.archive.hostLine,
    shutdownSha256: bundle.shutdown.evidenceSha256,
    residueSha256: residue.evidenceSha256,
    inventoryEvents: inventoryTimelineEvents,
  });
  if (canonicalJson(bundle.trustedTimeline) !== canonicalJson(expectedTimeline)) {
    fail("trusted_timeline_binding_invalid", "persistence",
      "trusted timeline is detached from transcript, Host, provider, archive, shutdown, or residue evidence");
  }
  if (safeExitControl.events.length !== 0 || exitConfirmControl.events.length !== 0
      || !(finalResponseAt < firstCloseRequestAt
        && firstCloseRequestAt < firstCloseCompletedAt
        && firstCloseCompletedAt < firstCloseSettledAt
        && firstCloseSettledAt < safeExitIssuedAt
        && safeExitIssuedAt < safeExitProviderCompletedAt
        && safeExitProviderCompletedAt < safeExitBoundaryAt
        && safeExitBoundaryAt < archiveObservedAt
        && archiveObservedAt < firstSealAt
        && firstSealAt < exitConfirmIssuedAt
        && exitConfirmIssuedAt < exitConfirmProviderCompletedAt
        && exitConfirmProviderCompletedAt < Date.parse(residue.first.observedAt))) {
    fail("native_exit_order_invalid", "persistence",
      "close settlement, provider SAFEEXIT, Host archive seal, EXIT_CONFIRM, and residue are out of order");
  }
  const firstCloseReceipt = firstRecords.find((record) =>
    record.lineNumber === firstHost.closeReceiptLine);
  const sv1Record = firstRecords.find((record) =>
    record.lineNumber === bundle.archive.sv1HostLine);
  const sv2Record = firstRecords.find((record) =>
    record.lineNumber === bundle.archive.sv2HostLine);
  const archiveHostRecord = firstRecords.find((record) =>
    record.lineNumber === bundle.archive.hostLine);
  const restartCloseControl = controlByStep(control, "close_restart_readback");
  const restartCloseReceipt = restartRecords.find((record) =>
    record.lineNumber === restartHost.closeReceiptLine);
  const restartDisk = readManifestJson(artifacts, bundle.clone.afterRestartArtifact,
    "clone_disk_manifest", "timeline");
  const providerStageTimeline = [];
  control.loaded.forEach((entry) => {
    const prefix = "control." + entry.request.step + ".";
    providerStageTimeline.push(
      [prefix + "request", entry.request.issuedAt],
      [prefix + "operation", entry.providerReceipt.startedAt],
      [prefix + "input", entry.providerReceipt.inputAt],
      [prefix + "capture", entry.providerReceipt.captureAt],
      [prefix + "provider_complete", entry.providerReceipt.completedAt],
      [prefix + "ack", entry.ack.completedAt]);
  });
  assertStrictTimeline(providerStageTimeline,
    "strict_global_control_timeline_invalid", "timeline");
  assertStrictTimeline(canonicalTimelineEntries({
    first_runtime_started: bundle.runtime.first.startedAt,
    first_cdp_bound: endpoints[0].observedAt,
    first_observer_ready: observerReady[0].observedAt,
    final_authority_response: lastCommit.response.event.observedAt,
    first_close_control_request: firstCloseControl.request.issuedAt,
    first_close_operation: firstCloseControl.providerReceipt.startedAt,
    first_close_input: firstCloseControl.providerReceipt.inputAt,
    first_close_request: firstClose.event.observedAt,
    first_host_close_receipt: firstCloseReceipt && firstCloseReceipt.observedAt,
    first_close_capture: firstCloseControl.providerReceipt.captureAt,
    first_close_provider: firstCloseControl.providerReceipt.completedAt,
    first_close_ack: firstCloseControl.ack.completedAt,
    first_close_settled: firstHost.closeSettledAt,
    first_observer_detached: observerDetached[0].observedAt,
    first_loaded_production: bundle.runtime.first.loadedProduction.capturedAt,
    safe_exit_issued: safeExitControl.request.issuedAt,
    safe_exit_operation: safeExitControl.providerReceipt.startedAt,
    safe_exit_input: safeExitControl.providerReceipt.inputAt,
    safe_exit_capture: safeExitControl.providerReceipt.captureAt,
    safe_exit_provider: safeExitControl.providerReceipt.completedAt,
    safe_exit_ack: safeExitControl.ack.completedAt,
    safe_exit_host_boundary: safeExitBoundary.capturedAt,
    sv1: sv1Record && sv1Record.observedAt,
    sv2: sv2Record && sv2Record.observedAt,
    archive_host_receipt: archiveHostRecord && archiveHostRecord.observedAt,
    archive_capture: bundle.archive.observedAt,
    first_host_terminal: hostLog.lifecycles.first.terminalSnapshot.capturedAt,
    exit_confirm_issued: exitConfirmControl.request.issuedAt,
    exit_confirm_operation: exitConfirmControl.providerReceipt.startedAt,
    exit_confirm_input: exitConfirmControl.providerReceipt.inputAt,
    exit_confirm_capture: exitConfirmControl.providerReceipt.captureAt,
    exit_confirm_provider: exitConfirmControl.providerReceipt.completedAt,
    exit_confirm_ack: exitConfirmControl.ack.completedAt,
    first_residue: residue.first.observedAt,
    restart_runtime_started: bundle.runtime.restart.startedAt,
    restart_cdp_bound: endpoints[1].observedAt,
    restart_observer_ready: observerReady[1].observedAt,
    restart_open_control_request: controlByStep(control, "open_restart_readback").request.issuedAt,
    restart_open_operation: controlByStep(control, "open_restart_readback").providerReceipt.startedAt,
    restart_open_input: controlByStep(control, "open_restart_readback").providerReceipt.inputAt,
    restart_open: byName.restart.open.event.observedAt,
    restart_open_capture: controlByStep(control, "open_restart_readback").providerReceipt.captureAt,
    restart_open_provider: controlByStep(control, "open_restart_readback").providerReceipt.completedAt,
    restart_open_ack: controlByStep(control, "open_restart_readback").ack.completedAt,
    restart_close_control_request: restartCloseControl.request.issuedAt,
    restart_close_operation: restartCloseControl.providerReceipt.startedAt,
    restart_close_input: restartCloseControl.providerReceipt.inputAt,
    restart_close_request: closeRestart.event.observedAt,
    restart_host_close_receipt: restartCloseReceipt && restartCloseReceipt.observedAt,
    restart_close_capture: restartCloseControl.providerReceipt.captureAt,
    restart_close_provider: restartCloseControl.providerReceipt.completedAt,
    restart_close_ack: restartCloseControl.ack.completedAt,
    restart_close_settled: restartHost.closeSettledAt,
    restart_observer_detached: observerDetached[1].observedAt,
    restart_loaded_production: bundle.runtime.restart.loadedProduction.capturedAt,
    restart_host_terminal: hostLog.lifecycles.restart.terminalSnapshot.capturedAt,
    shutdown_requested: bundle.shutdown.requestedAt,
    shutdown_completed: bundle.shutdown.completedAt,
    restart_residue: residue.restart.observedAt,
    restart_disk_capture: restartDisk.capturedAt,
    post_restart_production_capture: bundle.postRestartProductionClosure.capturedAt,
    clone_lock_release: residue.cloneLockReleasedAt,
  }, inventoryTimelineEvents, "strict_lifecycle_timeline_invalid"),
  "strict_lifecycle_timeline_invalid", "timeline");
  if (bundle.evidenceMode === "offline_fixture") {
    if (bundle.safeExitUiJourneyVerified !== false || bundle.exitMethod !== "offline_fixture_simulation") {
      fail("offline_live_claim_forbidden", "persistence",
        "offline fixtures must not carry a live SAFEEXIT UI claim or native exit method");
    }
  } else if (bundle.safeExitUiJourneyVerified !== true || bundle.exitMethod !== "native_safe_exit") {
    fail("live_safe_exit_claim_required", "persistence",
      "live capture requires an exact native SAFEEXIT UI claim before e2e verification");
  }
  assertNoRawAuthorityTokens(bundle, "bundle");

  const scopeComplete = bundle.journeyMode === FULL_MODE && saleSummary !== null
    && bundle.evidenceOrigin.fullScopeEligible === true;
  const liveVerified = bundle.evidenceMode === "live_capture" && scopeComplete;
  const diagnosticOnly = bundle.evidenceMode === "live_capture" && !scopeComplete;
  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: liveVerified ? "e2e_verified"
      : (diagnosticOnly ? "DIAGNOSTIC_VERIFIED" : "OFFLINE_VERIFIED"),
    liveStatus: liveVerified ? "LIVE_CAPTURE_VERIFIED" : "LIVE_BLOCKED",
    deployment: "NOT_DEPLOYED",
    evidenceMode: bundle.evidenceMode,
    runId: bundle.runId,
    journeyMode: bundle.journeyMode,
    scopeComplete,
    a3NpcClosable: liveVerified,
    candidateRoot: bundle.candidateRoot,
    candidateStableIdentity: bundle.candidate.stableIdentity,
    slot: bundle.slot,
    shopId: bundle.shopId,
    transport: control.selectedTransport,
    capabilityProbe: control.capability,
    ownerInstances: phases.map((phase) => phase.id),
    inventorySurfaces: {
      bag: { physicalCapacity: 50, accessibleCapacity: 50, pageSize: 50 },
      battlebox: { physicalCapacity: 400,
        accessibleCapacity: initialInventoryState.accessibleCapacity, pageSize: 40 },
      phases: inventoryTimelineEvents.reduce((result, entry) => {
        let phase = result.find((value) => value.phase === entry.phase);
        if (!phase) { phase = { phase: entry.phase, callIds: [] }; result.push(phase); }
        phase.callIds.push(entry.callId);
        return result;
      }, []),
    },
    purchase: {
      catalogIndex: policy.catalogIndex,
      itemName: policy.itemName,
      quantity: 1,
      destination: purchaseDestination,
      previewCallId: purchasePreview.request.message.callId,
      commitCallId: purchaseCommit.request.message.callId,
      flashCallId: commitMappings[0].flashCallId,
    },
    sale: saleSummary && Object.assign({}, saleSummary, {
      flashCallId: commitMappings[1].flashCallId,
    }),
    writeCount: commitPairs.length,
    webHostAs2Proof: {
      contract: "structured_web_call_to_same_fid_success_response.v2",
      rawAs2ResponseFidObserved: false,
      mappedRequestCount: mapped.length,
      uniqueFlashFids: new Set(mapped.map((entry) => entry.domain + ":" + entry.flashCallId)).size,
      noForeignLegacyLateWrites: true,
      firstTerminalCloseReceiptLine: firstHost.closeReceiptLine,
      restartTerminalCloseReceiptLine: restartHost.closeReceiptLine,
    },
    persistence,
    runtime,
    residue,
    safeExitUiJourneyVerified: bundle.safeExitUiJourneyVerified,
    exitMethod: bundle.exitMethod,
    artifactCount: bundle.artifactManifest.artifacts.length,
    moduleJournalSha256: preSeal || bundle.evidenceMode === "offline_fixture"
      ? null : bundle.moduleJournal.artifact.evidenceSha256,
    bundleCanonicalSha256: sha256Text(canonicalJson(preSeal ? preSealProjection(bundle) : bundle)),
  };
  receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
  return receipt;
}

function preSealProjection(bundle) {
  const projection = deepClone(bundle);
  if (projection.moduleJournal) projection.moduleJournal.artifact = null;
  if (projection.evidenceOrigin && projection.evidenceMode === "live_capture") {
    const fields = deepClone(projection.evidenceOrigin);
    delete fields.schema;
    delete fields.evidenceSha256;
    fields.moduleJournalSha256 = null;
    projection.evidenceOrigin = require("./common").sealEvidenceOrigin(fields);
  }
  return projection;
}

function verifyBundlePreSeal(bundle, runDir) {
  const provisionalReceipt = verifyBundle(bundle, runDir, { preSeal: true });
  const evidence = {
    schema: "workbench-live-e2e.npc.preseal-verification.v1",
    bundleProjectionSha256: sha256Text(canonicalJson(preSealProjection(bundle))),
    provisionalReceipt,
    provisionalReceiptSha256: sha256Text(canonicalJson(provisionalReceipt)),
    artifacts: bundle.artifactManifest.artifacts.map((entry) => deepClone(entry)),
  };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function finalizePreSealVerification(bundle, runDir, evidence) {
  const unsigned = deepClone(evidence);
  delete unsigned.evidenceSha256;
  if (!hasExactKeys(evidence, ["schema", "bundleProjectionSha256", "provisionalReceipt",
    "provisionalReceiptSha256", "artifacts", "evidenceSha256"])
      || evidence.schema !== "workbench-live-e2e.npc.preseal-verification.v1"
      || evidence.bundleProjectionSha256 !== sha256Text(canonicalJson(preSealProjection(bundle)))
      || evidence.provisionalReceiptSha256 !== sha256Text(canonicalJson(evidence.provisionalReceipt))
      || evidence.evidenceSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("preseal_verification_binding_invalid", "module_journal",
      "sealed finalization is detached from the exact pre-seal semantic verification");
  }
  verifyEvidenceOrigin(bundle, { preSeal: false });
  try {
    if (!isPlainObject(bundle.moduleJournal)
        || canonicalJson(bundle.moduleJournal.manifest.requiredPhases) !== canonicalJson(LIVE_PHASES)) {
      fail("live_module_phase_profile_invalid", "module_journal",
        "sealed module journal lacks the exact live verification phase profile");
    }
    RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: CANONICAL_ROOT,
      manifest: bundle.moduleJournal.manifest, artifact: bundle.moduleJournal.artifact });
  } catch (error) {
    fail(error && error.code || "module_journal_invalid", "module_journal",
      "sealed module admission is invalid", { message: error && error.message });
  }
  const artifacts = verifyArtifactClosure(bundle, runDir, { preSeal: false });
  if (!deepEqual(evidence.artifacts, bundle.artifactManifest.artifacts)) {
    fail("preseal_artifact_binding_invalid", "artifacts",
      "raw artifact projection changed after pre-seal verification");
  }
  const receipt = deepClone(evidence.provisionalReceipt);
  delete receipt.receiptSha256;
  receipt.artifactCount = artifacts.size;
  receipt.moduleJournalSha256 = bundle.moduleJournal.artifact.evidenceSha256;
  receipt.bundleCanonicalSha256 = sha256Text(canonicalJson(bundle));
  receipt.bundleFileSha256 = sha256File(path.join(runDir, "evidence-bundle.json"));
  receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
  return receipt;
}

function verifyEvidenceFile(bundlePath) {
  const resolved = path.resolve(bundlePath);
  const runDir = path.dirname(resolved);
  if (path.basename(resolved) !== "evidence-bundle.json") {
    fail("bundle_path_invalid", "bundle", "bundle must use the canonical evidence-bundle.json path");
  }
  const bundle = readJson(resolved, "bundle");
  const receipt = verifyBundle(bundle, runDir);
  delete receipt.receiptSha256;
  receipt.bundleFileSha256 = sha256File(resolved);
  receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
  return receipt;
}

module.exports = {
  FULL_MODE,
  PURCHASE_ONLY_MODE,
  artifactRolesForBundle,
  assertInventoryPhaseAccessConsistency,
  assertStableRevisionLeases,
  finalizePreSealVerification,
  preSealProjection,
  verifyBundle,
  verifyBundlePreSeal,
  verifyEvidenceFile,
};
