"use strict";

const {
  TOKEN_REF_RE,
  canonicalJson,
  deepClone,
  deepEqual,
  fail,
  isPlainObject,
  redactAuthorityTokens,
  requireOne,
  sha256Text,
} = require("./common");
const InventoryRuntime = require("../../../launcher/web/modules/inventory-runtime.js");
const LauncherObservation = require("../lib/launcher-observation");

const NPC_ACTIONS = Object.freeze({
  snapshot: "npcShopSnapshot",
  tooltip: "npcShopTooltip",
  batchPreview: "npcShopBatchPreview",
  tradePreview: "npcShopTradePreview",
  buy: "npcShopBuy",
  batchSell: "npcShopBatchSell",
  tradeCommit: "npcShopTradeCommit",
});

const INVENTORY_ACTIONS = Object.freeze({ snapshot: "inventorySnapshot" });
const WRITE_COMMANDS = new Set(["tradeCommit", "buy", "batchSell"]);
const LEGACY_WRITE_COMMANDS = new Set(["buy", "batchSell"]);
const AUTHORITY_KEYS = Object.freeze(["expectedTuningToken", "tuningToken",
  "expectedCheckoutToken", "checkoutToken", "expectedPurchasedToken", "purchasedToken",
  "expectedCraftToken", "craftToken", "expectedBatchToken", "batchToken",
  "expectedTradeToken", "tradeToken", "expectedLearnToken", "learnToken",
  "expectedLease", "slotLease", "closeLease", "transactionId"]);
const AUTHORITY_KEY_MAP = new Map(AUTHORITY_KEYS.map((key) => [key.toLowerCase(), key]));

function parseMaybeJson(value) {
  if (isPlainObject(value)) return value;
  if (typeof value !== "string") return null;
  try {
    const parsed = JSON.parse(value);
    return isPlainObject(parsed) ? parsed : null;
  } catch (_error) { return null; }
}

function eventMessage(event) {
  return parseMaybeJson(event && (event.message != null ? event.message : event.payload));
}

function outboundMessages(events) {
  return events.map((event) => ({ event, message: eventMessage(event) }))
    .filter((entry) => entry.event.kind === "bridge_send" && entry.message);
}

function inboundMessages(events) {
  return events.map((event) => ({ event, message: eventMessage(event) }))
    .filter((entry) => entry.event.kind === "webview_message" && entry.message);
}

function panelRequests(outbound) {
  return outbound.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "npcshop");
}

function panelResponses(inbound) {
  return inbound.filter((entry) => entry.message.type === "panel_resp"
    && entry.message.panel === "npcshop");
}

function openCommands(inbound) {
  return inbound.filter((entry) => entry.message.type === "panel_cmd"
    && entry.message.cmd === "open" && entry.message.panel === "npcshop");
}

function responseMatchesRequest(response, request) {
  const left = response.message;
  const right = request.message;
  return left.panel === right.panel
    && left.panelInstanceId === right.panelInstanceId
    && left.cmd === right.cmd
    && left.callId === right.callId
    && String(left.domain || "") === String(right.domain || "");
}

function responseFor(request, responses, phase) {
  const matches = responses.filter((entry) => entry.event.sequence > request.event.sequence
    && responseMatchesRequest(entry, request));
  return requireOne(matches, "response_count_invalid", phase || "protocol",
    "request must have exactly one later response", {
      cmd: request.message.cmd,
      callId: request.message.callId,
      panelInstanceId: request.message.panelInstanceId,
      domain: request.message.domain || null,
    });
}

function requestPairs(requests, responses) {
  const expectedRequests = requests.filter((entry) => entry.message.cmd !== "close");
  function hasExactIdentity(entry, type) {
    const message = entry && entry.message;
    return isPlainObject(message) && message.type === type && message.panel === "npcshop"
      && [message.panelInstanceId, message.domain, message.cmd, message.callId]
        .every((value) => typeof value === "string" && value.length > 0);
  }
  if (expectedRequests.some((entry) => !hasExactIdentity(entry, "panel"))
      || responses.some((entry) => !hasExactIdentity(entry, "panel_resp"))) {
    fail("response_bijection_invalid", "protocol",
      "NPC request/response pairing requires complete owner, domain, cmd, and callId identity");
  }
  responses.forEach((response) => {
    const matches = expectedRequests.filter((request) =>
      response.event.sequence > request.event.sequence && responseMatchesRequest(response, request));
    if (matches.length !== 1) {
      fail("response_bijection_invalid", "protocol",
        "every NPC panel response must match exactly one earlier request", {
          cmd: response.message.cmd,
          callId: response.message.callId,
          panelInstanceId: response.message.panelInstanceId,
          domain: response.message.domain || null,
          requestMatches: matches.length,
        });
    }
  });
  const pairs = expectedRequests.map((request) => ({
    request,
    response: responseFor(request, responses, "protocol"),
  }));
  if (responses.length !== pairs.length
      || new Set(pairs.map((pair) => pair.response)).size !== pairs.length) {
    fail("response_bijection_invalid", "protocol",
      "NPC panel requests and responses must form one exact bijection", {
        requestCount: expectedRequests.length,
        responseCount: responses.length,
      });
  }
  return pairs;
}

function strictRequestPairsFromEvents(events) {
  const outbound = outboundMessages(events);
  const inbound = inboundMessages(events);
  return requestPairs(panelRequests(outbound), panelResponses(inbound));
}

function requestsFor(requests, panelInstanceId, cmd, domain) {
  return requests.filter((entry) => entry.message.panelInstanceId === panelInstanceId
    && entry.message.cmd === cmd
    && String(entry.message.domain || "") === String(domain || ""));
}

function assertNoNpcOverlap(pairs) {
  const businessPairs = pairs.filter((pair) => pair.request.message.domain === "npcshop")
    .sort((left, right) => left.request.event.sequence - right.request.event.sequence);
  for (let index = 1; index < businessPairs.length; index += 1) {
    const previous = businessPairs[index - 1];
    const current = businessPairs[index];
    if (current.request.event.sequence < previous.response.event.sequence) {
      fail("npc_request_overlap", "protocol", "NPC business requests overlapped instead of preserving unique pending order", {
        previousCallId: previous.request.message.callId,
        currentCallId: current.request.message.callId,
      });
    }
  }
}

function identityTriple(value, internalKey) {
  if (!isPlainObject(value)) return null;
  const itemName = value[internalKey];
  const displayName = value.displayName;
  const icon = value.icon;
  if (![itemName, displayName, icon].every((entry) => typeof entry === "string"
      && entry.trim() && entry.trim().toLowerCase() !== "undefined")) return null;
  return { itemName, displayName, icon };
}

function hasExactKeys(value, required, optional) {
  if (!isPlainObject(value)) return false;
  const allowed = required.concat(optional || []);
  const keys = Object.keys(value);
  return required.every((key) => Object.prototype.hasOwnProperty.call(value, key))
    && keys.every((key) => allowed.includes(key));
}

function safeText(value, maximum, allowEmpty) {
  return typeof value === "string" && value.length <= maximum
    && (allowEmpty || value.length > 0) && !/[\u0000-\u001f\u007f]/.test(value);
}

function integerIn(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

function applyPermilleFloor(amount, quantity, ratePermille, phase) {
  if (!Number.isSafeInteger(amount) || amount < 0
      || !Number.isSafeInteger(quantity) || quantity < 0
      || !Number.isSafeInteger(ratePermille) || ratePermille < 0 || ratePermille > 1000) {
    fail("permille_input_invalid", phase, "NPC fixed-point input is outside the exact integer domain");
  }
  const subtotal = amount * quantity;
  if (!Number.isSafeInteger(subtotal)) {
    fail("permille_subtotal_unsafe", phase, "NPC fixed-point subtotal exceeds the exact integer domain");
  }
  const scaled = subtotal * ratePermille;
  if (!Number.isSafeInteger(scaled)) {
    fail("permille_product_unsafe", phase, "NPC fixed-point product exceeds the exact integer domain");
  }
  return Math.floor(scaled / 1000);
}

function addSafeIntegers(left, right, phase) {
  if (!Number.isSafeInteger(left) || !Number.isSafeInteger(right)) {
    fail("safe_integer_input_invalid", phase, "NPC integer projection input is not exact");
  }
  const result = left + right;
  if (!Number.isSafeInteger(result)) {
    fail("safe_integer_sum_unsafe", phase, "NPC integer projection sum exceeds the exact domain");
  }
  return result;
}

function subtractSafeIntegers(left, right, phase) {
  if (!Number.isSafeInteger(left) || !Number.isSafeInteger(right)) {
    fail("safe_integer_input_invalid", phase, "NPC integer projection input is not exact");
  }
  const result = left - right;
  if (!Number.isSafeInteger(result)) {
    fail("safe_integer_difference_unsafe", phase,
      "NPC integer projection difference exceeds the exact domain");
  }
  return result;
}

function assertCatalog(catalog, phase, buyRatePermille) {
  if (!Array.isArray(catalog)) fail("catalog_missing", phase, "NPC catalog is missing");
  const byIndex = new Map();
  catalog.forEach((entry) => {
    const index = Number(entry && entry.catalogIndex);
    const triple = identityTriple(entry, "itemName");
    const required = ["catalogIndex", "itemName", "displayName", "icon", "majorType", "use",
      "actionType", "weaponType", "setId", "setName", "setOrder", "basePrice", "unitPrice",
      "maxQuantity", "requiredInfo", "locked"];
    if (!hasExactKeys(entry, required, ["balanceSummary"])
        || !Number.isInteger(index) || index < 0 || index > 10000 || byIndex.has(index)
        || !triple || !Number.isSafeInteger(entry.unitPrice) || entry.unitPrice < 0
        || !Number.isSafeInteger(entry.basePrice) || entry.basePrice < 0
        || entry.unitPrice !== applyPermilleFloor(entry.basePrice, 1, buyRatePermille, phase)
        || !integerIn(entry.setOrder, 0, 2147483647)
        || !Number.isInteger(Number(entry.maxQuantity)) || Number(entry.maxQuantity) < 0
        || Number(entry.maxQuantity) > 999999
        || typeof entry.locked !== "boolean"
        || ![entry.majorType, entry.use, entry.actionType, entry.weaponType,
          entry.setId, entry.setName, entry.requiredInfo]
          .every((value) => safeText(value, 256, true))) {
      fail("catalog_entry_invalid", phase, "NPC catalog entry is malformed or duplicated", { index });
    }
    byIndex.set(index, entry);
  });
  return byIndex;
}

function assertNpcState(message, expectedShopId, phase) {
  const envelope = ["type", "domain", "panel", "panelInstanceId", "cmd", "callId"];
  const state = ["success", "v", "shopId", "balance", "buyRatePermille", "catalog", "layout", "views"];
  const commitCommand = message && message.cmd === "tradeCommit";
  const validTrade = !commitCommand || (message.operation === "tradeCommit"
    && isPlainObject(message.trade)
    && Number.isSafeInteger(message.trade.buyTotal) && message.trade.buyTotal >= 0
    && Number.isSafeInteger(message.trade.sellTotal) && message.trade.sellTotal >= 0
    && Number.isSafeInteger(message.trade.netDelta)
    && message.trade.netDelta === subtractSafeIntegers(message.trade.sellTotal,
      message.trade.buyTotal, phase));
  if (!isPlainObject(message) || message.success !== true || message.v !== 1
      || !hasExactKeys(message, envelope.concat(state), commitCommand ? ["operation", "trade"] : [])
      || message.type !== "panel_resp" || message.domain !== "npcshop" || message.panel !== "npcshop"
      || !safeText(message.panelInstanceId, 128, false) || !safeText(message.callId, 160, false)
      || !["snapshot", "tradeCommit"].includes(message.cmd)
      || (commitCommand && (!hasExactKeys(message.trade,
        ["buyTotal", "sellTotal", "netDelta"]) || !validTrade))
      || message.shopId !== expectedShopId || !Number.isSafeInteger(message.balance)
      || message.balance < 0 || !integerIn(message.buyRatePermille, 0, 1000)
      || !isPlainObject(message.views)
      || !hasExactKeys(message.views, ["material", "intelligence"])
      || !hasExactKeys(message.layout, ["title", "defaultSection", "sections"])
      || !safeText(message.layout.title, 256, false)
      || !safeText(message.layout.defaultSection, 128, true)
      || !Array.isArray(message.layout.sections)) {
    fail("npc_state_invalid", phase, "NPC authoritative state is malformed", { expectedShopId });
  }
  const catalog = assertCatalog(message.catalog, phase, message.buyRatePermille);
  ["material", "intelligence"].forEach((viewId) => {
    const view = message.views[viewId];
    if (!hasExactKeys(view, ["containerId", "capacity", "accessibleCapacity", "viewCapacity",
      "offset", "limit", "filterKey", "slots"])
        || view.containerId !== (viewId === "material" ? "材料" : "情报")
        || !integerIn(view.capacity, 0, 100000)
        || !integerIn(view.accessibleCapacity, 0, view.capacity)
        || !integerIn(view.viewCapacity, 0, view.accessibleCapacity)
        || view.offset !== 0 || view.limit !== view.viewCapacity
        || !safeText(view.filterKey, 128, false)
        || !Array.isArray(view.slots) || view.slots.length !== view.viewCapacity) {
      fail("npc_view_invalid", phase, "NPC collection view is missing", { viewId });
    }
    const keys = new Set();
    view.slots.forEach((slot) => {
      const triple = identityTriple(slot && slot.item, "name");
      if (!hasExactKeys(slot, ["physicalSlot", "collectionKey", "occupied", "slotLease", "item"])
          || !integerIn(slot.physicalSlot, 0, 100000)
          || slot.occupied !== true || !triple || typeof slot.collectionKey !== "string"
          || keys.has(slot.collectionKey) || typeof slot.slotLease !== "string" || !slot.slotLease) {
        fail("npc_view_slot_invalid", phase, "NPC collection slot is malformed or duplicated", { viewId });
      }
      if (!hasExactKeys(slot.item, ["itemKind", "name", "displayName", "icon", "majorType",
        "use", "quantity", "enhancementLevel", "rarity"])
          || slot.item.itemKind !== "stack" || slot.item.name !== slot.collectionKey
          || !safeText(slot.item.majorType, 128, true) || !safeText(slot.item.use, 128, true)
          || !Number.isInteger(slot.item.quantity) || slot.item.quantity < 1
          || slot.item.enhancementLevel !== 0 || !safeText(slot.item.rarity, 128, true)) {
        fail("npc_view_item_invalid", phase, "NPC collection item does not match Host exact schema", { viewId });
      }
      keys.add(slot.collectionKey);
    });
  });
  return { message, catalog };
}

const INVENTORY_SURFACE_SCHEMA = "workbench-live-e2e.npc.inventory-surface.v1";
const BAG_PROBE = Object.freeze({ containerId: "背包", offset: 0, limit: 50, filterKey: "all" });
const BATTLE_PROBE = Object.freeze({ containerId: "战备箱", offset: 0, limit: 100, filterKey: "all" });
const BATTLE_ACCESSIBLE_CAPACITIES = new Set([0, 40, 80, 120, 160, 200, 240]);

function assertInventoryResponseEnvelope(message, phase) {
  if (!hasExactKeys(message, ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
    "success", "v", "sessionNonce", "snapshots"])
      || message.type !== "panel_resp" || message.domain !== "inventory"
      || message.panel !== "npcshop" || message.cmd !== "snapshot"
      || message.success !== true || message.v !== 1
      || !safeText(message.panelInstanceId, 128, false)
      || !safeText(message.callId, 160, false)
      || !safeText(message.sessionNonce, 128, false) || !Array.isArray(message.snapshots)) {
    fail("inventory_snapshot_invalid", phase, "inventory response is not authoritative");
  }
  return message;
}

function rawInventoryWindows(message, phase) {
  assertInventoryResponseEnvelope(message, phase);
  const windows = new Map();
  message.snapshots.forEach((snapshot) => {
    if (!InventoryRuntime.isValidSnapshot(snapshot)
        || typeof snapshot.containerId !== "string" || windows.has(snapshot.containerId)) {
      fail("inventory_window_invalid", phase, "inventory window is malformed or duplicated");
    }
    const physicalSlots = new Set();
    snapshot.slots.forEach((slot) => {
      const physical = Number(slot && slot.physicalSlot);
      if (!Number.isInteger(physical) || physical < 0 || physicalSlots.has(physical)
          || typeof slot.occupied !== "boolean") {
        fail("inventory_slot_invalid", phase, "inventory slot identity is malformed or duplicated", {
          containerId: snapshot.containerId,
          physicalSlot: physical,
        });
      }
      physicalSlots.add(physical);
      if (slot.occupied) {
        const triple = identityTriple(slot.item, "name");
        if (!triple || typeof slot.slotLease !== "string" || !slot.slotLease
            || !Number.isInteger(Number(slot.item.quantity)) || Number(slot.item.quantity) < 1) {
          fail("inventory_item_invalid", phase, "occupied inventory slot has an invalid authority projection", {
            containerId: snapshot.containerId,
            physicalSlot: physical,
          });
        }
      }
    });
    windows.set(snapshot.containerId, snapshot);
  });
  if (!windows.has("背包")) fail("bag_window_missing", phase, "authoritative 背包 window is missing");
  return windows;
}

function inventoryWindows(message, phase) {
  if (message && message.schema === INVENTORY_SURFACE_SCHEMA) {
    const windows = new Map();
    message.snapshots.forEach((snapshot) => windows.set(snapshot.containerId, snapshot));
    if (windows.size !== 2 || !windows.has("背包") || !windows.has("战备箱")) {
      fail("inventory_surface_invalid", phase, "validated Inventory surface lost a canonical container");
    }
    return windows;
  }
  return rawInventoryWindows(message, phase);
}

function expectedInventoryRequests(accessibleCapacity) {
  const batches = [[BAG_PROBE, BATTLE_PROBE]];
  if (accessibleCapacity > 100) {
    batches.push([{ containerId: "战备箱", offset: 100, limit: 100, filterKey: "all" }]);
  }
  if (accessibleCapacity > 200) {
    batches.push([{ containerId: "战备箱", offset: 200,
      limit: accessibleCapacity - 200, filterKey: "all" }]);
  }
  return batches;
}

function assertWindowMetadata(snapshot, containerId, accessibleCapacity, phase) {
  const bag = containerId === "背包";
  const expected = bag ? { capacity: 50, accessible: 50, pageSize: 50, locked: false }
    : { capacity: 400, accessible: accessibleCapacity, pageSize: 40,
      locked: accessibleCapacity === 0 };
  if (snapshot.capacity !== expected.capacity
      || snapshot.accessibleCapacity !== expected.accessible
      || snapshot.viewCapacity !== expected.accessible
      || snapshot.pageSizeHint !== expected.pageSize || snapshot.locked !== expected.locked
      || snapshot.filterKey !== "all") {
    fail("inventory_surface_metadata_drift", phase,
      "Inventory capacity/access/view/pageSize/locked metadata differs from the production surface", {
        containerId, expected, actual: {
          capacity: snapshot.capacity, accessibleCapacity: snapshot.accessibleCapacity,
          viewCapacity: snapshot.viewCapacity, pageSizeHint: snapshot.pageSizeHint,
          locked: snapshot.locked,
        },
      });
  }
}

function assertInventorySnapshotSurface(pairs, phase) {
  if (!Array.isArray(pairs) || pairs.length < 1 || pairs.length > 3) {
    fail("inventory_surface_pair_set_invalid", phase,
      "Inventory phase requires one exact ordered probe/supplement pair-set");
  }
  const firstResponse = pairs[0] && pairs[0].response && pairs[0].response.message;
  assertInventoryResponseEnvelope(firstResponse, phase);
  const firstSnapshots = firstResponse && firstResponse.snapshots;
  const firstBattle = Array.isArray(firstSnapshots)
    ? firstSnapshots.find((snapshot) => snapshot.containerId === "战备箱") : null;
  const accessibleCapacity = Number(firstBattle && firstBattle.accessibleCapacity);
  if (!BATTLE_ACCESSIBLE_CAPACITIES.has(accessibleCapacity)) {
    fail("inventory_battle_access_invalid", phase,
      "battle-box accessible capacity must be one exact 40-slot production tier");
  }
  const expectedBatches = expectedInventoryRequests(accessibleCapacity);
  if (pairs.length !== expectedBatches.length) {
    fail("inventory_surface_pair_set_invalid", phase,
      "Inventory supplement count does not cover the full declared battle-box surface", {
        accessibleCapacity, expectedPairs: expectedBatches.length, actualPairs: pairs.length,
      });
  }

  let owner = null;
  let sessionNonce = null;
  let previousResponseSequence = -1;
  let previousResponseAt = -Infinity;
  let battleEpoch = null;
  let battleVersion = null;
  const windows = [];
  const occupiedCoordinates = new Set();
  pairs.forEach((pair, pairOrdinal) => {
    const requestEntry = pair && pair.request;
    const responseEntry = pair && pair.response;
    const request = requestEntry && requestEntry.message;
    const response = responseEntry && responseEntry.message;
    const payload = request && request.payload;
    assertInventoryResponseEnvelope(response, phase);
    const requestAt = Date.parse(requestEntry && requestEntry.event && requestEntry.event.observedAt);
    const responseAt = Date.parse(responseEntry && responseEntry.event && responseEntry.event.observedAt);
    if (!hasExactKeys(payload, ["v", "requests"]) || payload.v !== 1
        || canonicalJson(payload.requests) !== canonicalJson(expectedBatches[pairOrdinal])
        || response.snapshots.length !== expectedBatches[pairOrdinal].length
        || requestEntry.event.sequence <= previousResponseSequence
        || responseEntry.event.sequence <= requestEntry.event.sequence
        || !Number.isFinite(requestAt) || !Number.isFinite(responseAt)
        || requestAt <= previousResponseAt || responseAt <= requestAt) {
      fail("inventory_surface_order_invalid", phase,
        "Inventory probe response must strictly precede the next exact supplement request", {
          pairOrdinal,
        });
    }
    previousResponseSequence = responseEntry.event.sequence;
    previousResponseAt = responseAt;
    const pairOwner = [request.panelInstanceId, request.panel, request.domain, request.cmd].join("|");
    if (owner == null) owner = pairOwner;
    if (pairOwner !== owner || request.domain !== "inventory" || request.cmd !== "snapshot"
        || response.panelInstanceId !== request.panelInstanceId || response.callId !== request.callId
        || response.domain !== "inventory" || response.cmd !== "snapshot") {
      fail("inventory_surface_owner_drift", phase,
        "all Inventory surface pairs must belong to one exact panel owner");
    }
    if (sessionNonce == null) sessionNonce = response.sessionNonce;
    if (!safeText(response.sessionNonce, 128, false) || response.sessionNonce !== sessionNonce) {
      fail("inventory_surface_session_drift", phase,
        "all Inventory surface responses in one phase must share one session nonce");
    }
    expectedBatches[pairOrdinal].forEach((windowRequest, requestOrdinal) => {
      const snapshot = response.snapshots[requestOrdinal];
      const expectedLimit = Math.min(windowRequest.limit,
        Math.max(0, accessibleCapacity - windowRequest.offset));
      const actualExpectedLimit = windowRequest.containerId === "背包" ? 50 : expectedLimit;
      if (!InventoryRuntime.isValidSnapshot(snapshot)
          || snapshot.containerId !== windowRequest.containerId
          || snapshot.offset !== windowRequest.offset || snapshot.limit !== actualExpectedLimit
          || snapshot.slots.length !== actualExpectedLimit) {
        fail("inventory_surface_window_invalid", phase,
          "Inventory response window does not exactly match its ordered request", {
            pairOrdinal, requestOrdinal, request: windowRequest,
          });
      }
      assertWindowMetadata(snapshot, snapshot.containerId, accessibleCapacity, phase);
      if (snapshot.containerId === "战备箱") {
        if (battleEpoch == null) {
          battleEpoch = snapshot.containerEpoch;
          battleVersion = snapshot.containerVersion;
        } else if (snapshot.containerEpoch !== battleEpoch
            || snapshot.containerVersion !== battleVersion) {
          fail("inventory_surface_revision_drift", phase,
            "battle-box epoch/version changed while one phase was being probed");
        }
      }
      snapshot.slots.forEach((slot, slotOrdinal) => {
        const expectedSlot = windowRequest.offset + slotOrdinal;
        const coordinate = snapshot.containerId + ":" + Number(slot.physicalSlot);
        if (Number(slot.physicalSlot) !== expectedSlot || occupiedCoordinates.has(coordinate)) {
          fail("inventory_surface_slot_order_invalid", phase,
            "Inventory full surface contains an overlap, gap, or reordered physical slot", {
              pairOrdinal, containerId: snapshot.containerId, expectedSlot,
              actualSlot: slot.physicalSlot,
            });
        }
        occupiedCoordinates.add(coordinate);
      });
      windows.push({ pairOrdinal, requestOrdinal, callId: request.callId,
        request: deepClone(windowRequest), snapshot: deepClone(snapshot) });
    });
  });

  const merged = ["背包", "战备箱"].map((containerId) => {
    const sourceWindows = windows.filter((window) => window.snapshot.containerId === containerId);
    const first = sourceWindows[0] && sourceWindows[0].snapshot;
    const expectedCount = containerId === "背包" ? 50 : accessibleCapacity;
    const slots = sourceWindows.flatMap((window) => window.snapshot.slots).sort((left, right) =>
      Number(left.physicalSlot) - Number(right.physicalSlot));
    if (!first || slots.length !== expectedCount
        || slots.some((slot, index) => Number(slot.physicalSlot) !== index)) {
      fail("inventory_surface_incomplete", phase,
        "Inventory pair-set does not contain every declared physical slot exactly once", {
          containerId, expectedCount, actualCount: slots.length,
        });
    }
    const snapshot = deepClone(first);
    snapshot.offset = 0;
    snapshot.limit = expectedCount;
    snapshot.slots = deepClone(slots);
    return snapshot;
  });
  return {
    schema: INVENTORY_SURFACE_SCHEMA,
    phase,
    panelInstanceId: pairs[0].request.message.panelInstanceId,
    sessionNonce,
    accessibleCapacity,
    callIds: pairs.map((pair) => pair.request.message.callId),
    pairs,
    windows,
    snapshots: merged,
    firstPair: pairs[0],
    lastPair: pairs[pairs.length - 1],
  };
}

function assertInventorySnapshotPair(pair, phase) {
  return assertInventorySnapshotSurface([pair], phase);
}

function inventoryCounts(message, phase) {
  const counts = new Map();
  inventoryWindows(message, phase).forEach((window) => {
    window.slots.forEach((slot) => {
      if (!slot.occupied || !slot.item) return;
      const name = slot.item.name;
      counts.set(name, Number(counts.get(name) || 0) + Number(slot.item.quantity));
    });
  });
  return counts;
}

function collectionCounts(message, phase) {
  assertNpcState(message, message.shopId, phase);
  const counts = new Map();
  Object.keys(message.views).forEach((viewId) => {
    message.views[viewId].slots.forEach((slot) => {
      counts.set(slot.item.name, Number(counts.get(slot.item.name) || 0) + Number(slot.item.quantity));
    });
  });
  return counts;
}

function bagSlot(message, physicalSlot, phase) {
  const bag = inventoryWindows(message, phase).get("背包");
  return bag.slots.find((slot) => Number(slot.physicalSlot) === Number(physicalSlot)) || null;
}

function canonicalAuthorityProjection(npcMessage, inventoryMessage, selection) {
  assertNpcState(npcMessage, npcMessage && npcMessage.shopId, "authority_projection");
  if (!inventoryMessage || inventoryMessage.schema !== INVENTORY_SURFACE_SCHEMA) {
    fail("inventory_surface_required", "authority_projection",
      "canonical authority projection requires a validated complete Inventory surface");
  }
  const validatedInventory = inventoryWindows(inventoryMessage, "authority_projection");

  const npcViews = {};
  const npcSources = [];
  Object.keys(npcMessage.views).sort().forEach((viewId) => {
    const view = deepClone(npcMessage.views[viewId]);
    view.slots = view.slots.map((slot) => {
      const semanticSlot = deepClone(slot);
      delete semanticSlot.slotLease;
      npcSources.push({ viewId, containerId: view.containerId,
        physicalSlot: slot.physicalSlot, collectionKey: slot.collectionKey,
        occupied: slot.occupied, slotLease: slot.slotLease });
      return semanticSlot;
    });
    npcViews[viewId] = view;
  });

  let selectedCatalog = null;
  if (selection != null) {
    const catalogIndex = Number(selection.catalogIndex);
    selectedCatalog = npcMessage.catalog.find((entry) => Number(entry.catalogIndex) === catalogIndex);
    if (!selectedCatalog || selectedCatalog.itemName !== selection.itemName
        || selectedCatalog.displayName !== selection.displayName
        || selectedCatalog.icon !== selection.icon) {
      fail("authority_selection_invalid", "persistence",
        "fresh authority projection is detached from the frozen catalog selection");
    }
    selectedCatalog = { catalogIndex, entry: deepClone(selectedCatalog) };
  }

  const inventorySources = [];
  const semanticSnapshots = Array.from(validatedInventory.values()).map((snapshot) => {
    const semantic = deepClone(snapshot);
    const source = {
      containerId: snapshot.containerId,
      snapshotSeq: snapshot.snapshotSeq,
      containerEpoch: snapshot.containerEpoch,
      containerVersion: snapshot.containerVersion,
      slots: [],
    };
    delete semantic.snapshotSeq;
    delete semantic.containerEpoch;
    delete semantic.containerVersion;
    semantic.slots = semantic.slots.map((slot) => {
      source.slots.push({ physicalSlot: slot.physicalSlot, occupied: slot.occupied,
        slotLease: slot.slotLease });
      const semanticSlot = deepClone(slot);
      delete semanticSlot.slotLease;
      return semanticSlot;
    });
    inventorySources.push(source);
    return semantic;
  });

  return {
    semantic: {
      npc: {
        success: npcMessage.success,
        v: npcMessage.v,
        shopId: npcMessage.shopId,
        balance: npcMessage.balance,
        buyRatePermille: npcMessage.buyRatePermille,
        catalog: deepClone(npcMessage.catalog),
        selection: selectedCatalog,
        layout: deepClone(npcMessage.layout),
        views: npcViews,
      },
      inventory: {
        success: true,
        v: 1,
        snapshots: semanticSnapshots,
      },
    },
    source: {
      npc: npcSources,
      inventory: {
        sessionNonce: inventoryMessage.sessionNonce,
        snapshots: inventorySources,
        windows: inventoryMessage.schema === INVENTORY_SURFACE_SCHEMA
          ? inventoryMessage.windows.map((window) => ({
            pairOrdinal: window.pairOrdinal,
            requestOrdinal: window.requestOrdinal,
            callId: window.callId,
            containerId: window.snapshot.containerId,
            offset: window.snapshot.offset,
            limit: window.snapshot.limit,
            snapshotSeq: window.snapshot.snapshotSeq,
            containerEpoch: window.snapshot.containerEpoch,
            containerVersion: window.snapshot.containerVersion,
          })) : [],
      },
    },
  };
}

function stateFingerprint(npcMessage, inventoryMessage, selection) {
  return sha256Text(canonicalJson(
    canonicalAuthorityProjection(npcMessage, inventoryMessage, selection).semantic));
}

function authoritySourceFingerprint(npcMessage, inventoryMessage, selection) {
  return sha256Text(canonicalJson(
    canonicalAuthorityProjection(npcMessage, inventoryMessage, selection).source));
}

function sourceLeaseMap(source) {
  const leases = new Map();
  source.npc.forEach((slot) => {
    leases.set("npc:" + slot.viewId + ":" + slot.containerId + ":"
      + slot.physicalSlot + ":" + slot.collectionKey, slot.slotLease);
  });
  source.inventory.snapshots.forEach((snapshot) => snapshot.slots.forEach((slot) => {
    leases.set("inventory:" + snapshot.containerId + ":" + slot.physicalSlot, slot.slotLease);
  }));
  return leases;
}

function assertFreshAuthorityReadback(finalNpc, finalInventory, restartNpc, restartInventory,
  selection) {
  const finalProjection = canonicalAuthorityProjection(finalNpc, finalInventory, selection);
  const restartProjection = canonicalAuthorityProjection(restartNpc, restartInventory, selection);
  const finalFingerprint = sha256Text(canonicalJson(finalProjection.semantic));
  const restartFingerprint = sha256Text(canonicalJson(restartProjection.semantic));
  if (finalFingerprint !== restartFingerprint) {
    fail("restart_semantic_readback_mismatch", "persistence",
      "fresh PID readback differs from the complete canonical authority state");
  }

  const finalSources = sourceLeaseMap(finalProjection.source);
  const restartSources = sourceLeaseMap(restartProjection.source);
  if (canonicalJson(Array.from(finalSources.keys())) !== canonicalJson(Array.from(restartSources.keys()))
      || finalProjection.source.inventory.sessionNonce
        === restartProjection.source.inventory.sessionNonce) {
    fail("restart_source_fingerprint_invalid", "persistence",
      "fresh restart source topology or Inventory session nonce is not exact and fresh");
  }
  finalSources.forEach((lease, key) => {
    if (typeof lease !== "string" || !lease || typeof restartSources.get(key) !== "string"
        || !restartSources.get(key) || lease === restartSources.get(key)) {
      fail("restart_source_fingerprint_invalid", "persistence",
        "every NPC/Inventory authority slot lease must rotate across the fresh owner", { key });
    }
  });
  const finalSourceFingerprint = sha256Text(canonicalJson(finalProjection.source));
  const restartSourceFingerprint = sha256Text(canonicalJson(restartProjection.source));
  if (finalSourceFingerprint === restartSourceFingerprint) {
    fail("restart_source_fingerprint_invalid", "persistence",
      "fresh restart source projection did not change");
  }
  return { finalFingerprint, restartFingerprint,
    finalSourceFingerprint, restartSourceFingerprint };
}

const HOST_TIMESTAMP_PREFIX_RE = /^(\d{2}):(\d{2}):(\d{2})\.(\d{3}) /;
const HOST_RELEVANT_MARKERS = Object.freeze([
  "[XmlSocket:JSON] {",
  "[XmlSocket:JSON] task=npcshop_response ",
  "[XmlSocket:JSON] task=inventory_response ",
  "[XmlSocket:JSON] task=authority_response_family ",
  "[Panel] HandlePanelMessage: ",
  "[Panel] Routing domain=npcshop ",
  "[Panel] Routing domain=inventory ",
  "event=authority_flash_call_bound ",
  "[NpcShopTask] -> Flash:",
  "[InventoryTask] -> Flash:",
  "[PanelHost] opened: npcshop ",
  "[PanelHost] closed: npcshop",
  "event=panel_exact_close_completed ",
  "event=foreign_panel_close_rejected ",
  "[Workbench]",
  "sv:1",
  "sv:2",
  "[ArchiveTask] Shadow saved: ",
]);

function normalizeHostRecord(record, phase) {
  const raw = String(record && record.line || "");
  const timestamp = HOST_TIMESTAMP_PREFIX_RE.exec(raw);
  if (!timestamp) {
    fail("host_timestamp_missing", phase,
      "every authenticated Host record must preserve its production timestamp prefix", {
        lineNumber: record && record.lineNumber,
      });
  }
  const hour = Number(timestamp[1]);
  const minute = Number(timestamp[2]);
  const second = Number(timestamp[3]);
  const millisecond = Number(timestamp[4]);
  if (hour > 23 || minute > 59 || second > 59) {
    fail("host_timestamp_invalid", phase, "Host log timestamp is outside clock bounds", {
      lineNumber: record && record.lineNumber,
    });
  }
  const body = raw.slice(timestamp[0].length);
  const occurrences = [];
  HOST_RELEVANT_MARKERS.forEach((marker) => {
    let offset = body.indexOf(marker);
    while (offset >= 0) {
      occurrences.push({ marker, offset });
      offset = body.indexOf(marker, offset + marker.length);
    }
  });
  if (HOST_TIMESTAMP_PREFIX_RE.test(body)
      || (occurrences.length && (occurrences.length !== 1 || occurrences[0].offset !== 0))) {
    fail("host_relevant_record_invalid", phase,
      "Host record has an extra prefix, embedded relevant marker, or multiple relevant markers", {
        lineNumber: record && record.lineNumber,
      });
  }
  return Object.assign({}, record, { body,
    hostTimeOfDayMs: (((hour * 60 + minute) * 60 + second) * 1000 + millisecond),
    observedAt: null });
}

function resolveHostTimeline(snapshot, utcOffsetMinutes, phase) {
  if (!isPlainObject(snapshot) || !Array.isArray(snapshot.records)
      || !Number.isFinite(Date.parse(snapshot.capturedAt))
      || !Number.isInteger(utcOffsetMinutes)
      || utcOffsetMinutes < -840 || utcOffsetMinutes > 840
      || utcOffsetMinutes % 15 !== 0) {
    fail("host_log_snapshot_invalid", phase,
      "Host snapshot or its explicit UTC offset is malformed");
  }
  const records = snapshot.records.map((record) => normalizeHostRecord(record, phase));
  if (!records.length) return records;
  const capturedMs = Date.parse(snapshot.capturedAt);
  const offsetMs = utcOffsetMinutes * 60000;
  const localCapture = new Date(capturedMs + offsetMs);
  const firstValue = records[0].hostTimeOfDayMs;
  let localDateStart = Date.UTC(localCapture.getUTCFullYear(), localCapture.getUTCMonth(),
    localCapture.getUTCDate());
  let firstObserved = localDateStart + firstValue - offsetMs;
  if (firstObserved > capturedMs) {
    localDateStart -= 24 * 60 * 60 * 1000;
    firstObserved -= 24 * 60 * 60 * 1000;
  }
  let dayOffset = 0;
  let rolloverCount = 0;
  let previousTimeOfDay = firstValue;
  records.forEach((record, index) => {
    const value = record.hostTimeOfDayMs;
    if (index > 0 && value < previousTimeOfDay) {
      const previousHour = Math.floor(previousTimeOfDay / 3600000);
      const currentHour = Math.floor(value / 3600000);
      if (previousHour !== 23 || currentHour !== 0 || rolloverCount !== 0) {
        fail("host_timeline_regression", phase,
          "Host records regress outside one exact 23:xx to 00:xx rollover", {
            previousLineNumber: records[index - 1].lineNumber,
            lineNumber: record.lineNumber, rolloverCount,
          });
      }
      rolloverCount += 1;
      dayOffset += 24 * 60 * 60 * 1000;
    }
    const observed = localDateStart + dayOffset + value - offsetMs;
    if (index > 0 && observed < Date.parse(records[index - 1].observedAt)) {
      fail("host_timestamp_invalid", phase,
        "Host record timeline is non-monotonic after rollover reconstruction", {
          lineNumber: record.lineNumber,
        });
    }
    record.observedAt = new Date(observed).toISOString();
    previousTimeOfDay = value;
  });
  const lastObserved = Date.parse(records[records.length - 1].observedAt);
  if (lastObserved > capturedMs || capturedMs - firstObserved > 36 * 60 * 60 * 1000) {
    fail("host_timestamp_invalid", phase,
      "Host record timeline is future-dated or outside the bounded capture window", {
        firstLineNumber: records[0].lineNumber,
        lastLineNumber: records[records.length - 1].lineNumber,
      });
  }
  return records;
}

function normalizedHostRecords(hostLog) {
  return ["first", "restart"].flatMap((label) => hostLifecycleRecords(hostLog, label));
}

function hostLifecycleRecords(hostLog, label) {
  const lifecycle = hostLog && hostLog.lifecycles && hostLog.lifecycles[label];
  if (!hostLog || hostLog.schema !== "workbench-live-e2e.npc.host-evidence.v4"
      || canonicalJson(Object.keys(hostLog).sort())
        !== canonicalJson(["schema", "utcOffsetMinutes", "lifecycles"].sort())
      || !isPlainObject(lifecycle) || !isPlainObject(lifecycle.closeSettledSnapshot)) {
    fail("host_log_missing", "host_log", "authenticated Host lifecycle evidence is missing", { label });
  }
  let suffix;
  try {
    LauncherObservation.verifyTerminalLogBoundary(lifecycle.startBoundary);
    LauncherObservation.verifyLogSnapshot(lifecycle.closeSettledSnapshot);
    LauncherObservation.verifyLogSnapshot(lifecycle.terminalSnapshot);
    LauncherObservation.recordsAfterTerminalBoundary(
      lifecycle.startBoundary, lifecycle.closeSettledSnapshot);
    LauncherObservation.recordsAfterTerminalBoundary(
      LauncherObservation.createTerminalLogBoundary(lifecycle.closeSettledSnapshot),
      lifecycle.terminalSnapshot);
    suffix = LauncherObservation.recordsAfterTerminalBoundary(
      lifecycle.startBoundary, lifecycle.terminalSnapshot);
  } catch (error) {
    fail(error && error.code || "host_terminal_snapshot_invalid", "host_log",
      "Host evidence is not one authenticated complete terminal suffix", {
        label, message: error && error.message,
      });
  }
  const timeline = resolveHostTimeline(lifecycle.terminalSnapshot,
    hostLog.utcOffsetMinutes, "host_log_" + label);
  const byLine = new Map(timeline.map((record) => [record.lineNumber, record]));
  return suffix.map((record) => {
    const resolved = byLine.get(record.lineNumber);
    if (!resolved || resolved.line !== record.line) {
      fail("host_timeline_binding_invalid", "host_log",
        "terminal suffix is detached from its reconstructed Host clock", {
          label, lineNumber: record.lineNumber,
        });
    }
    return { lifecycle: label, lineNumber: record.lineNumber,
      body: resolved.body, observedAt: resolved.observedAt,
      hostTimeOfDayMs: resolved.hostTimeOfDayMs };
  });
}

function hostCloseSettledRecords(hostLog, label) {
  hostLifecycleRecords(hostLog, label);
  const lifecycle = hostLog.lifecycles[label];
  const suffix = LauncherObservation.recordsAfterTerminalBoundary(
    lifecycle.startBoundary, lifecycle.closeSettledSnapshot);
  const timeline = resolveHostTimeline(lifecycle.closeSettledSnapshot,
    hostLog.utcOffsetMinutes, "host_log_" + label + "_close");
  const byLine = new Map(timeline.map((record) => [record.lineNumber, record]));
  return suffix.map((record) => {
    const resolved = byLine.get(record.lineNumber);
    if (!resolved || resolved.line !== record.line) {
      fail("host_timeline_binding_invalid", "host_log",
        "close-settled suffix is detached from its reconstructed Host clock", {
          label, lineNumber: record.lineNumber,
        });
    }
    return { lifecycle: label, lineNumber: record.lineNumber,
      body: resolved.body, observedAt: resolved.observedAt,
      hostTimeOfDayMs: resolved.hostTimeOfDayMs };
  });
}

function parseLoggedJson(record, prefix) {
  if (!record.body.startsWith(prefix)) return null;
  try { return redactAuthorityTokens(JSON.parse(record.body.slice(prefix.length))); }
  catch (error) {
    fail("host_log_json_invalid", "host_log", "Host JSON record is malformed", {
      lineNumber: record.lineNumber,
      prefix,
      message: error.message,
    });
  }
}

function parseStructured(record, prefix) {
  if (!record.body.startsWith(prefix)) return null;
  const fields = {};
  const orderedKeys = [];
  const body = record.body.slice(prefix.length).trim();
  if (!body) return fields;
  body.split(/\s+/).forEach((part) => {
    const index = part.indexOf("=");
    if (index <= 0 || index === part.length - 1) {
      fail("host_structured_token_invalid", "host_log",
        "Host structured record contains a malformed token", {
          lineNumber: record.lineNumber,
        });
    }
    const key = part.slice(0, index);
    if (Object.prototype.hasOwnProperty.call(fields, key)) {
      fail("host_structured_duplicate_field", "host_log",
        "Host structured record contains a duplicate field", {
          lineNumber: record.lineNumber, key,
        });
    }
    fields[key] = part.slice(index + 1);
    orderedKeys.push(key);
  });
  Object.defineProperty(fields, "__orderedKeys", { value: orderedKeys, enumerable: false });
  return fields;
}

function exactStructured(record, prefix, keys, code) {
  const fields = parseStructured(record, prefix);
  if (!fields) return null;
  if (Object.keys(fields).length !== keys.length
      || canonicalJson(fields.__orderedKeys) !== canonicalJson(keys)) {
    fail(code, "host_log", "Host structured record has missing/extra/duplicate fields", {
      lineNumber: record.lineNumber,
    });
  }
  return fields;
}

function isSensitiveKey(key) {
  const text = String(key || "");
  return AUTHORITY_KEY_MAP.has(text.toLowerCase())
    || /token|lease|transaction|secret|capability/i.test(text);
}

function shortAuthorityRef(value) {
  const text = String(value == null ? "" : value);
  const digest = TOKEN_REF_RE.test(text) ? text.slice("sha256:".length) : sha256Text(text);
  return text ? "sha256_" + digest.slice(0, 24) : null;
}

function authorityProjection(value) {
  const evidence = { fieldCount: 0, unknownFieldCount: 0,
    present: new Set(), refs: new Map(), unknownRefs: new Set() };
  function visit(node) {
    if (Array.isArray(node)) { node.forEach(visit); return; }
    if (!isPlainObject(node)) return;
    Object.keys(node).forEach((key) => {
      const child = node[key];
      if (!isSensitiveKey(key)) { visit(child); return; }
      evidence.fieldCount += 1;
      const canonical = AUTHORITY_KEY_MAP.get(key.toLowerCase()) || null;
      const raw = child == null ? "" : (typeof child === "string" ? child : JSON.stringify(child));
      const reference = shortAuthorityRef(raw);
      if (canonical) {
        evidence.present.add(canonical);
        if (reference) {
          if (!evidence.refs.has(canonical)) evidence.refs.set(canonical, new Set());
          evidence.refs.get(canonical).add(reference);
        }
      } else {
        evidence.unknownFieldCount += 1;
        if (reference) evidence.unknownRefs.add(reference);
      }
    });
  }
  visit(value);
  const fields = {};
  if (evidence.fieldCount === 0) return fields;
  fields.authorityFieldCount = String(evidence.fieldCount);
  AUTHORITY_KEYS.forEach((key) => {
    if (!evidence.present.has(key)) return;
    const refs = Array.from(evidence.refs.get(key) || []).sort();
    if (!refs.length) { fields[key + "Present"] = "true"; return; }
    fields[key + (refs.length === 1 ? "Ref" : "Refs")] = refs.slice(0, 4).join(",");
    if (refs.length > 4) fields[key + "RefCount"] = String(refs.length);
  });
  if (evidence.unknownFieldCount > 0) {
    fields.unknownAuthorityFieldCount = String(evidence.unknownFieldCount);
    const refs = Array.from(evidence.unknownRefs).sort();
    if (refs.length) fields.unknownAuthorityRefs = refs.slice(0, 4).join(",");
    if (refs.length > 4) fields.unknownAuthorityRefCount = String(refs.length);
  }
  return fields;
}

function structuredWithAuthority(record, prefix, baseKeys, expectedAuthority, code) {
  const fields = parseStructured(record, prefix);
  if (!fields) return null;
  const authority = expectedAuthority || {};
  const expectedKeys = baseKeys.concat(Object.keys(authority));
  if (canonicalJson(fields.__orderedKeys) !== canonicalJson(expectedKeys)
      || Object.keys(authority).some((key) => fields[key] !== authority[key])) {
    fail(code, "host_log",
      "Host redacted summary has a missing, extra, or mismatched authority field", {
        lineNumber: record.lineNumber,
      });
  }
  return fields;
}

function assertHostMapping(request, records, responseEntry) {
  const message = request.message;
  const panelEntries = records.map((record) => ({
    record,
    message: parseStructured(record, "[Panel] HandlePanelMessage: "),
  })).filter((entry) => entry.message && entry.message.task === "panel"
    && entry.message.panel === "npcshop" && entry.message.domain === message.domain
    && entry.message.cmd === message.cmd && entry.message.callId === message.callId
    && entry.message.payload === "redacted" && /^\d+$/.test(entry.message.len || ""));
  const panel = requireOne(panelEntries, "host_panel_request_count_invalid", "host_log",
    "exact Web request must occur once in Host log", { callId: message.callId, cmd: message.cmd });
  panel.message = structuredWithAuthority(panel.record, "[Panel] HandlePanelMessage: ",
    ["task", "panel", "domain", "cmd", "callId", "payload", "len"],
    authorityProjection(message), "host_panel_record_invalid");
  const nextPanelLine = records.find((record) => record.lineNumber > panel.record.lineNumber
    && record.body.startsWith("[Panel] HandlePanelMessage: "));
  const beforeNext = (record) => !nextPanelLine || record.lineNumber < nextPanelLine.lineNumber;
  const inventory = message.domain === "inventory";
  const routeBody = inventory
    ? "[Panel] Routing domain=inventory cmd=" + message.cmd + " to InventoryTask, _inventoryTask=ok"
    : "[Panel] Routing domain=npcshop cmd=" + message.cmd + " to NpcShopTask, _npcShopTask=ok";
  const route = records.find((record) => record.lineNumber > panel.record.lineNumber
    && beforeNext(record) && record.body === routeBody);
  if (!route) fail("host_route_missing", "host_log", "exact Host domain route is missing", { routeBody });
  const component = inventory ? "InventoryTask" : "NpcShopTask";
  const prefix = "[" + component + "] -> Flash:";
  const actions = inventory ? INVENTORY_ACTIONS : NPC_ACTIONS;
  const action = actions[message.cmd];
  const receipts = records.map((record) => ({ record,
    message: record.body.startsWith("event=authority_flash_call_bound ")
      ? exactStructured(record, "",
        ["event", "domain", "webCallId", "flashCallId", "panel", "panelInstanceId", "cmd", "action"],
        "host_authority_receipt_invalid") : null }))
    .filter((entry) => entry.message && entry.record.lineNumber > route.lineNumber
      && entry.message.event === "authority_flash_call_bound"
      && entry.message.domain === message.domain
      && entry.message.webCallId === message.callId
      && entry.message.panel === "npcshop"
      && entry.message.panelInstanceId === message.panelInstanceId
      && entry.message.cmd === message.cmd && entry.message.action === action
      && /^\d+$/.test(entry.message.flashCallId || ""));
  const receipt = requireOne(receipts, "host_authority_receipt_count_invalid", "host_log",
    "Host must emit one exact Web callId to Flash fid authority receipt", {
    callId: message.callId,
    cmd: message.cmd,
  });
  const fid = Number(receipt.message.flashCallId);
  const sends = records.map((record) => ({ record, message: parseStructured(record, prefix) }))
    .filter((entry) => entry.message && entry.record.lineNumber > receipt.record.lineNumber
      && entry.message.task === "cmd"
      && entry.message.cmd === action && Number(entry.message.callId) === fid
      && entry.message.payload === "redacted" && /^\d+$/.test(entry.message.len || ""));
  const send = requireOne(sends, "host_flash_send_count_invalid", "host_log",
    "Host must emit one exact redacted AS2 command for the authority receipt");
  send.message = structuredWithAuthority(send.record, prefix,
    ["task", "cmd", "callId", "payload", "len"], authorityProjection(message.payload),
    "host_flash_send_record_invalid");
  const responseTask = inventory ? "inventory_response" : "npcshop_response";
  const responses = records.map((record) => ({
    record,
    message: record.body.startsWith("[XmlSocket:JSON] task=" + responseTask + " ")
      ? parseStructured(record, "[XmlSocket:JSON] ") : null,
  })).filter((entry) => entry.message && entry.record.lineNumber > send.record.lineNumber
    && entry.message.task === responseTask
    && entry.message.cmd === action && Number(entry.message.callId) === fid
    && entry.message.success === "true" && entry.message.payload === "redacted"
    && /^\d+$/.test(entry.message.len || ""));
  const response = requireOne(responses, "host_flash_response_count_invalid", "host_log",
    "same-fid successful Flash response must close the authority receipt");
  response.message = structuredWithAuthority(response.record, "[XmlSocket:JSON] ",
    ["task", "cmd", "callId", "success", "payload", "len"],
    authorityProjection(responseEntry && responseEntry.message),
    "host_flash_response_record_invalid");
  const boundaryTimes = [request.event.observedAt, panel.record.observedAt,
    route.observedAt, receipt.record.observedAt, send.record.observedAt,
    response.record.observedAt, responseEntry && responseEntry.event.observedAt]
    .map(Date.parse);
  if (boundaryTimes.some((value) => !Number.isFinite(value))
      || boundaryTimes.some((value, index) => index > 0 && value < boundaryTimes[index - 1])) {
    fail("host_authority_timeline_invalid", "host_log",
      "Web request, Host route, AS2 call/response, and Web response are not one monotonic chain", {
        callId: message.callId,
        boundaryTimes: [request.event.observedAt, panel.record.observedAt,
          route.observedAt, receipt.record.observedAt, send.record.observedAt,
          response.record.observedAt, responseEntry && responseEntry.event.observedAt],
      });
  }
  return {
    domain: message.domain,
    cmd: message.cmd,
    webCallId: message.callId,
    requestSequence: request.event.sequence,
    panelInstanceId: message.panelInstanceId,
    flashCallId: fid,
    panelLine: panel.record.lineNumber,
    routeLine: route.lineNumber,
    receiptLine: receipt.record.lineNumber,
    flashLine: send.record.lineNumber,
    responseLine: response.record.lineNumber,
    requestObservedAt: request.event.observedAt,
    panelObservedAt: panel.record.observedAt,
    routeObservedAt: route.observedAt,
    receiptObservedAt: receipt.record.observedAt,
    flashObservedAt: send.record.observedAt,
    hostResponseObservedAt: response.record.observedAt,
    webResponseObservedAt: responseEntry.event.observedAt,
  };
}

function isRelevantHostBody(body) {
  return /^\[(?:NpcShopTask|InventoryTask|PanelHost)\]/.test(body)
    || /^(?:event=authority_flash_call_bound|event=panel_exact_close_completed|event=foreign_panel_close_rejected)/.test(body)
    || /^\[XmlSocket:JSON\] (?:\{|task=(?:npcshop_response|inventory_response|authority_response_family))/.test(body)
    || /^\[Panel\] (?:HandlePanelMessage: .*?(?:panel=npcshop\b|domain=npcshop\b)|Routing domain=(?:npcshop|inventory)\b)/.test(body)
    || /^\[Workbench\]/.test(body);
}

function verifyHostLifecycle(hostLog, label, phaseRequests, phaseMappings, panelInstanceId) {
  const records = hostLifecycleRecords(hostLog, label);
  const settledRecords = hostCloseSettledRecords(hostLog, label);
  const closeRequests = phaseRequests.filter((entry) => entry.message.cmd === "close");
  const authorityRequests = phaseRequests.filter((entry) => entry.message.cmd !== "close");
  if (closeRequests.length !== 1 || authorityRequests.length !== phaseMappings.length) {
    fail("host_phase_request_multiset_invalid", "host_log",
      "Host phase request inventory is incomplete", { label });
  }
  const panelRecords = records.filter((record) => record.body.startsWith("[Panel] HandlePanelMessage: "));
  const npcPanelRecords = panelRecords.filter((record) => {
    const fields = parseStructured(record, "[Panel] HandlePanelMessage: ");
    return fields.panel === "npcshop";
  });
  const routeRecords = records.filter((record) => record.body.startsWith("[Panel] Routing domain=npcshop")
    || record.body.startsWith("[Panel] Routing domain=inventory"));
  const bindings = records.filter((record) => record.body.startsWith("event=authority_flash_call_bound "));
  const npcSends = records.filter((record) => record.body.startsWith("[NpcShopTask] -> Flash:"));
  const inventorySends = records.filter((record) => record.body.startsWith("[InventoryTask] -> Flash:"));
  const npcResponses = records.filter((record) => record.body.startsWith("[XmlSocket:JSON] task=npcshop_response "));
  const inventoryResponses = records.filter((record) => record.body.startsWith("[XmlSocket:JSON] task=inventory_response "));
  const closeReceipts = records.filter((record) => record.body.startsWith("event=panel_exact_close_completed "))
    .map((record) => ({ record, fields: exactStructured(record,
      "", ["event", "panel", "panelInstanceId"],
      "host_close_receipt_invalid") }));
  const ingress = records.filter((record) => record.body.startsWith("[XmlSocket:JSON] {")).map((record) => ({ record,
    value: parseLoggedJson(record, "[XmlSocket:JSON] "),
  })).filter((entry) => entry.value && entry.value.task === "panel_request"
    && entry.value.panel === "npcshop");
  const opens = records.filter((record) =>
    /^\[PanelHost\] opened: npcshop rect=[1-9]\d*x[1-9]\d*$/.test(record.body));
  const closed = records.filter((record) => record.body === "[PanelHost] closed: npcshop");
  if (npcSends.some((record) => {
    const fields = parseStructured(record, "[NpcShopTask] -> Flash:");
    return fields && ["npcShopBuy", "npcShopBatchSell"].includes(fields.cmd);
  })) {
    fail("legacy_npc_write_observed", "host_log",
      "legacy NPC AS2 write appeared in authenticated terminal evidence", { label });
  }
  const npcCount = authorityRequests.filter((entry) => entry.message.domain === "npcshop").length;
  const inventoryCount = authorityRequests.filter((entry) => entry.message.domain === "inventory").length;
  if (npcPanelRecords.length !== phaseRequests.length || routeRecords.length !== authorityRequests.length
      || bindings.length !== authorityRequests.length || npcSends.length !== npcCount
      || inventorySends.length !== inventoryCount || npcResponses.length !== npcCount
      || inventoryResponses.length !== inventoryCount || closeReceipts.length !== 1
      || ingress.length !== 1 || opens.length !== 1 || closed.length !== 1
      || closeReceipts[0].fields.event !== "panel_exact_close_completed"
      || closeReceipts[0].fields.panel !== "npcshop"
      || closeReceipts[0].fields.panelInstanceId !== panelInstanceId) {
    fail("host_command_multiset_invalid", "host_log",
      "authenticated terminal suffix contains extra/missing NPC Host records", {
        label, panel: npcPanelRecords.length, routes: routeRecords.length,
        bindings: bindings.length, npcSends: npcSends.length, inventorySends: inventorySends.length,
        npcResponses: npcResponses.length, inventoryResponses: inventoryResponses.length,
        closeReceipts: closeReceipts.length, ingress: ingress.length,
        opens: opens.length, closed: closed.length,
      });
  }
  const closePanel = requireOne(npcPanelRecords.map((record) => ({ record,
    fields: parseStructured(record, "[Panel] HandlePanelMessage: ") }))
    .filter((entry) => entry.fields.domain === "none" && entry.fields.cmd === "close"
      && entry.fields.callId === "none" && entry.fields.payload === "redacted"
      && /^\d+$/.test(entry.fields.len || "")), "host_close_panel_count_invalid", "host_log",
  "Host must observe one exact owner close request", { label });
  structuredWithAuthority(closePanel.record, "[Panel] HandlePanelMessage: ",
    ["task", "panel", "domain", "cmd", "callId", "payload", "len"], {},
    "host_close_panel_invalid");
  if (!(opens[0].lineNumber < npcPanelRecords[0].lineNumber
      && closePanel.record.lineNumber < closed[0].lineNumber
      && closed[0].lineNumber < closeReceipts[0].record.lineNumber)) {
    fail("host_close_receipt_order_invalid", "host_log",
      "PanelHost open and close request→closed→completion order is invalid", { label });
  }
  const closeTimeline = [closeRequests[0].event.observedAt, closePanel.record.observedAt,
    closed[0].observedAt, closeReceipts[0].record.observedAt,
    hostLog.lifecycles[label].closeSettledSnapshot.capturedAt].map(Date.parse);
  if (closeTimeline.some((value) => !Number.isFinite(value))
      || closeTimeline.some((value, index) => index > 0 && value < closeTimeline[index - 1])) {
    fail("host_close_timeline_invalid", "host_log",
      "Web close, Host close, close receipt, and close-settled capture are not one monotonic chain", {
        label,
      });
  }
  const lastMappedResponseLine = Math.max.apply(null,
    phaseMappings.map((mapping) => mapping.responseLine));
  if (!Number.isInteger(lastMappedResponseLine)
      || lastMappedResponseLine >= closePanel.record.lineNumber) {
    fail("host_response_after_close_invalid", "host_log",
      "all authority responses must precede the exact owner close request", { label });
  }
  const chronological = phaseMappings.slice().sort((left, right) => left.requestSequence - right.requestSequence);
  for (let index = 1; index < chronological.length; index += 1) {
    if (chronological[index - 1].receiptLine >= chronological[index].receiptLine) {
      fail("host_request_order_invalid", "host_log",
        "Host call-bound order differs from Web request order", { label });
    }
  }
  const recognized = new Set([
    ...ingress.map((entry) => entry.record.lineNumber), ...opens.map((entry) => entry.lineNumber),
    ...npcPanelRecords.map((entry) => entry.lineNumber), ...routeRecords.map((entry) => entry.lineNumber),
    ...bindings.map((entry) => entry.lineNumber), ...npcSends.map((entry) => entry.lineNumber),
    ...inventorySends.map((entry) => entry.lineNumber), ...npcResponses.map((entry) => entry.lineNumber),
    ...inventoryResponses.map((entry) => entry.lineNumber), ...closed.map((entry) => entry.lineNumber),
    ...closeReceipts.map((entry) => entry.record.lineNumber),
  ]);
  const relevant = records.filter((record) => isRelevantHostBody(record.body));
  const rejection = relevant.filter((record) =>
    /rejected|not queued|superseded|ignored after replacement|expired\/foreign|near_match|malformed/i
      .test(record.body));
  const unknown = relevant.filter((record) => !recognized.has(record.lineNumber));
  if (rejection.length || unknown.length) {
    fail("host_relevant_record_unknown", "host_log",
      "authenticated NPC Host suffix contains a rejection or record outside the exact success multiset", {
        label,
        lines: Array.from(new Set(rejection.concat(unknown).map((entry) => entry.lineNumber))).sort(),
      });
  }
  const lastRelevantLine = Math.max.apply(null, relevant.map((entry) => entry.lineNumber));
  const settledRelevant = settledRecords.filter((record) => isRelevantHostBody(record.body));
  const settledCompletions = settledRecords.filter((record) =>
    record.body === "event=panel_exact_close_completed panel=npcshop panelInstanceId="
      + panelInstanceId);
  const settledLastRelevantLine = Math.max.apply(null,
    settledRelevant.map((entry) => entry.lineNumber));
  if (settledCompletions.length !== 1
      || settledCompletions[0].lineNumber !== closeReceipts[0].record.lineNumber
      || settledLastRelevantLine !== settledCompletions[0].lineNumber
      || settledRecords.some((record) => record.body === "sv:1" || record.body === "sv:2"
        || record.body.startsWith("[ArchiveTask] Shadow saved:"))) {
    fail("host_close_settlement_invalid", "host_log",
      "close-settled snapshot must end at the exact completion before save/shutdown activity", { label });
  }
  if (label === "restart" && lastRelevantLine !== closeReceipts[0].record.lineNumber) {
    fail("host_restart_terminal_record_invalid", "host_log",
      "restart exact-close completion is not the final relevant Host record");
  }
  return { records, closeRequestLine: closePanel.record.lineNumber,
    panelHostClosedLine: closed[0].lineNumber,
    closeReceiptLine: closeReceipts[0].record.lineNumber,
    closeSettledAt: hostLog.lifecycles[label].closeSettledSnapshot.capturedAt,
    relevantRecordCount: relevant.length };
}

function assertUniqueMappings(mappings) {
  const web = new Set();
  const flash = new Set();
  mappings.forEach((mapping) => {
    const webKey = mapping.domain + "|" + mapping.webCallId;
    const flashKey = mapping.domain + "|" + mapping.flashCallId;
    if (web.has(webKey)) fail("web_call_id_reused", "host_log", "Web callId was mapped more than once", { webKey });
    if (flash.has(flashKey)) fail("flash_fid_reused", "host_log", "AS2 fid was reused or concurrent mapping is ambiguous", { flashKey });
    web.add(webKey);
    flash.add(flashKey);
  });
}

function assertNoUnmappedHostWrites(records, mappedWrites, terminalLine) {
  const mappedFids = new Set(mappedWrites.map((entry) => entry.flashCallId));
  const hostPanelWrites = records.map((record) => ({
    record,
    message: parseStructured(record, "[Panel] HandlePanelMessage: "),
  })).filter((entry) => entry.message && entry.message.panel === "npcshop"
    && entry.message.domain === "npcshop" && WRITE_COMMANDS.has(entry.message.cmd));
  if (hostPanelWrites.some((entry) => LEGACY_WRITE_COMMANDS.has(entry.message.cmd))) {
    fail("legacy_npc_write_observed", "host_log", "legacy NPC buy/batchSell write appeared in production journey");
  }
  const sends = records.map((record) => ({
    record,
    message: parseStructured(record, "[NpcShopTask] -> Flash:"),
  })).filter((entry) => entry.message && ["npcShopTradeCommit", "npcShopBuy", "npcShopBatchSell"]
    .includes(entry.message.cmd));
  if (sends.some((entry) => ["npcShopBuy", "npcShopBatchSell"].includes(entry.message.cmd))) {
    fail("legacy_npc_write_observed", "host_log", "legacy NPC AS2 write appeared in production journey");
  }
  const extra = sends.filter((entry) => !mappedFids.has(Number(entry.message.callId)));
  if (extra.length) {
    fail("foreign_host_only_write", "host_log", "Host emitted an unmapped NPC write", {
      flashCallIds: extra.map((entry) => Number(entry.message.callId)),
      manualRecoveryRequired: true,
    });
  }
  const late = sends.filter((entry) => Number.isInteger(terminalLine) && entry.record.lineNumber > terminalLine);
  if (late.length) {
    fail("late_host_write", "host_log", "NPC write appeared after the terminal evidence seal", {
      flashCallIds: late.map((entry) => Number(entry.message.callId)),
      manualRecoveryRequired: true,
    });
  }
  if (hostPanelWrites.length !== mappedWrites.length || sends.length !== mappedWrites.length) {
    fail("host_write_multiset_mismatch", "host_log", "Host/AS2 write multiset differs from mapped Web commits", {
      webWrites: hostPanelWrites.length,
      as2Writes: sends.length,
      mappedWrites: mappedWrites.length,
      manualRecoveryRequired: true,
    });
  }
}

function assertTokenLink(previewResponse, commitRequest, phase) {
  const token = previewResponse.message.tradeToken;
  const expected = commitRequest.message.payload && commitRequest.message.payload.expectedTradeToken;
  if (!TOKEN_REF_RE.test(String(token || "")) || token !== expected) {
    fail("trade_token_link_invalid", phase, "commit does not consume the final authoritative preview token reference");
  }
}

module.exports = {
  INVENTORY_ACTIONS,
  LEGACY_WRITE_COMMANDS,
  NPC_ACTIONS,
  WRITE_COMMANDS,
  authorityProjection,
  authoritySourceFingerprint,
  addSafeIntegers,
  applyPermilleFloor,
  assertFreshAuthorityReadback,
  assertCatalog,
  assertHostMapping,
  assertInventorySnapshotPair,
  assertInventorySnapshotSurface,
  assertNoNpcOverlap,
  assertNoUnmappedHostWrites,
  assertNpcState,
  assertTokenLink,
  assertUniqueMappings,
  bagSlot,
  canonicalAuthorityProjection,
  collectionCounts,
  eventMessage,
  inboundMessages,
  inventoryCounts,
  inventoryWindows,
  normalizedHostRecords,
  normalizeHostRecord,
  hostLifecycleRecords,
  hostCloseSettledRecords,
  openCommands,
  outboundMessages,
  panelRequests,
  panelResponses,
  parseLoggedJson,
  parseStructured,
  requestPairs,
  strictRequestPairsFromEvents,
  requestsFor,
  resolveHostTimeline,
  responseFor,
  stateFingerprint,
  subtractSafeIntegers,
  verifyHostLifecycle,
};
