"use strict";

const Evidence = require("../lib/evidence-artifact");
const PanelRuntime = require("../../../launcher/web/modules/panel-runtime.js");
const InventoryRuntime = require("../../../launcher/web/modules/inventory-runtime.js");
const {
  TOKEN_REF_RE,
  deepClone,
  fail,
  verifyRecordChain,
} = require("./common");

if (!PanelRuntime || typeof PanelRuntime.PanelRequestMux !== "function"
    || typeof PanelRuntime.PanelResponseRouter !== "function"
    || !InventoryRuntime || typeof InventoryRuntime.InventoryCoordinator !== "function") {
  fail("production_runtime_contract_missing", "bootstrap",
    "actual PanelRuntime and InventoryRuntime contracts are not executable");
}

const CATEGORY_SET = new Set([
  "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
  "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备",
]);
const FIRST_COMMANDS = Object.freeze([
  "snapshot", "preview", "preview",
  "snapshot", "snapshot", "preview",
  "commit", "snapshot", "preview",
  "snapshot", "snapshot", "preview",
]);
const RESTART_COMMANDS = Object.freeze([
  "snapshot", "preview", "preview", "snapshot", "snapshot", "preview",
]);
const INVENTORY_FIRST = Object.freeze(["snapshot", "snapshot"]);
const INVENTORY_RESTART = Object.freeze(["snapshot"]);
const BAG_CONTAINER = "背包";
const BATTLEBOX_CONTAINER = "战备箱";
const CALL_ID_RE = /^[A-Za-z0-9._:-]{1,96}$/;
const OWNER_RE = /^[A-Za-z0-9._~-]{1,160}$/;
const AVAILABILITY_CODES = new Set([
  "ready", "level_locked", "material_missing", "insufficient_money",
  "insufficient_kpoint", "inventory_full", "output_projection_failed",
]);
const PROJECTED_ITEM_KEYS = Object.freeze([
  "name", "displayName", "icon", "itemKind", "value", "quantity",
  "enhancementLevel", "majorType", "use", "actionType", "weaponType",
  "setId", "setName", "setOrder",
]);
const STORAGE_KINDS = new Set([
  "bag", "drug", "bag_and_drug", "material_collection",
  "information_collection", "unavailable",
]);

function canonical(value) { return Evidence.canonicalJson(value); }
function same(left, right) { return canonical(left) === canonical(right); }
function own(value, key) { return Object.prototype.hasOwnProperty.call(value || {}, key); }

function exactKeys(value, required, optional, code, phase) {
  if (!Evidence.isPlainObject(value)) fail(code, phase, "expected one exact object");
  const actual = Object.keys(value).sort();
  const allowed = new Set((required || []).concat(optional || []));
  if ((required || []).some((key) => !own(value, key))
      || actual.some((key) => !allowed.has(key))) {
    fail(code, phase, "object keys do not match the closed contract", {
      actual, required, optional,
    });
  }
  return value;
}

function parseMessage(event) {
  if (!event || !own(event, "message")) return null;
  if (Evidence.isPlainObject(event.message)) return event.message;
  try { return JSON.parse(String(event.message)); } catch (_error) { return null; }
}

function identityTriple(value, phase) {
  if (!Evidence.isPlainObject(value)
      || !boundedText(value.name, 128, false)
      || !boundedText(value.displayName, 256, false)
      || !boundedText(value.icon, 256, false)) {
    fail("identity_triple_invalid", phase, "item identity triple is malformed");
  }
  return { name: value.name, displayName: value.displayName, icon: value.icon };
}

function sameTriple(left, right) {
  return canonical(identityTriple(left, "identity"))
    === canonical(identityTriple(right, "identity"));
}

function finiteNonNegative(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function boundedText(value, maximum, allowEmpty) {
  return typeof value === "string" && value.length <= maximum
    && (allowEmpty || value.length > 0) && !/[\u0000-\u001f\u007f]/.test(value);
}

function integerIn(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

function requireBalance(value, phase) {
  exactKeys(value, ["money", "kpoints"], [], "balance_keys_invalid", phase);
  if (!finiteNonNegative(value.money)
      || !finiteNonNegative(value.kpoints)) {
    fail("balance_invalid", phase, "balance projection is malformed");
  }
  return { money: value.money, kpoints: value.kpoints };
}

function requireCost(value, phase) {
  exactKeys(value, ["money", "kpoints"], [], "cost_keys_invalid", phase);
  if (!finiteNonNegative(value.money)
      || !finiteNonNegative(value.kpoints)) {
    fail("cost_invalid", phase, "cost projection is malformed");
  }
  return { money: value.money, kpoints: value.kpoints };
}

function requireSkills(value, phase) {
  exactKeys(value, ["reverseLevel", "smithEnabled", "smithLevel"], [],
    "skills_keys_invalid", phase);
  if (!finiteNonNegative(value.reverseLevel) || typeof value.smithEnabled !== "boolean"
      || !finiteNonNegative(value.smithLevel)) {
    fail("skills_invalid", phase, "skills projection is malformed");
  }
  return value;
}

function validateProjectedItem(value, withRequiredLevel, phase) {
  const keys = PROJECTED_ITEM_KEYS.concat(withRequiredLevel ? ["requiredLevel"] : []);
  exactKeys(value, keys, [], "projected_item_keys_invalid", phase);
  identityTriple(value, phase);
  if (!["equipment", "stack"].includes(value.itemKind)
      || !finiteNonNegative(value.value) || !finiteNonNegative(value.quantity)
      || !finiteNonNegative(value.enhancementLevel)
      || !Number.isInteger(value.value) || value.value < 1
      || !Number.isInteger(value.quantity) || value.quantity < 1
      || !Number.isInteger(value.enhancementLevel)
      || !boundedText(value.majorType, 128, true)
      || !boundedText(value.use, 128, true)
      || !boundedText(value.actionType, 128, true)
      || !boundedText(value.weaponType, 128, true)
      || !boundedText(value.setId, 128, true)
      || !boundedText(value.setName, 256, true)
      || !integerIn(value.setOrder, 0, 100000)
      || withRequiredLevel && !finiteNonNegative(value.requiredLevel)
      || value.itemKind === "equipment"
        && (value.quantity !== 1 || value.enhancementLevel !== value.value)
      || value.itemKind === "stack"
        && (value.enhancementLevel !== 0 || value.quantity !== value.value)) {
    fail("projected_item_invalid", phase, "Crafting projected item is malformed");
  }
  return value;
}

function exactOpen(transcript, phase) {
  const opens = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
    .filter((entry) => entry.event.kind === "webview_message" && entry.message
      && entry.message.type === "panel_cmd" && entry.message.cmd === "open"
      && entry.message.panel === "crafting");
  if (opens.length !== 1) {
    fail("production_open_count_invalid", phase,
      "one exact production Crafting open envelope is required", { count: opens.length });
  }
  const open = opens[0];
  const message = open.message;
  const init = message.initData;
  if (!OWNER_RE.test(String(message.panelInstanceId || ""))
      || !Evidence.isPlainObject(init) || init.mode !== "runtime"
      || init.source !== "world_crafting_entry" || init.debug !== false
      || init.panelInstanceId !== message.panelInstanceId || !CATEGORY_SET.has(init.category)) {
    fail("production_open_invalid", phase,
      "Crafting open is not the world-entry runtime owner contract");
  }
  return { event: open.event, message, owner: message.panelInstanceId, category: init.category };
}

function validateRequest(message, owner, category, phase) {
  exactKeys(message, ["type", "domain", "panel", "panelInstanceId", "cmd", "callId", "payload"],
    [], "crafting_request_keys_invalid", phase);
  if (!Evidence.isPlainObject(message) || message.type !== "panel"
      || message.domain !== "crafting" || message.panel !== "crafting"
      || message.panelInstanceId !== owner || !CALL_ID_RE.test(String(message.callId || ""))
      || !FIRST_COMMANDS.includes(message.cmd) || !Evidence.isPlainObject(message.payload)
      || message.payload.v !== 1 || message.payload.category !== category) {
    fail("crafting_request_invalid", phase, "Crafting request envelope is malformed", { message });
  }
  const payload = message.payload;
  if (message.cmd === "snapshot") {
    if (canonical(Object.keys(payload).sort()) !== canonical(["category", "v"])) {
      fail("snapshot_selector_invalid", phase, "snapshot selector is not exact");
    }
  } else if (message.cmd === "preview") {
    if (canonical(Object.keys(payload).sort())
        !== canonical(["category", "craftCount", "recipeIndex", "v"])
        || !Number.isInteger(payload.recipeIndex) || payload.recipeIndex < 0 || payload.recipeIndex > 999
        || !Number.isInteger(payload.craftCount) || payload.craftCount < 1 || payload.craftCount > 99) {
      fail("preview_selector_invalid", phase, "preview selector is not exact");
    }
  } else if (message.cmd === "commit") {
    if (canonical(Object.keys(payload).sort())
        !== canonical(["category", "expectedCraftTokenRef", "v"])
        || !TOKEN_REF_RE.test(String(payload.expectedCraftTokenRef || ""))) {
      fail("commit_token_reference_invalid", phase,
        "commit must carry only one opaque preview-token reference");
    }
  }
  return message;
}

function validateRecipe(value, phase) {
  exactKeys(value, ["recipeIndex", "title", "output", "baseCost", "materialCount",
    "batchEligible", "canCraftOne", "availability"], [],
  "recipe_projection_keys_invalid", phase);
  if (!integerIn(value.recipeIndex, 0, 999)
      || !boundedText(value.title, 256, false)
      || !integerIn(value.materialCount, 0, 999)
      || typeof value.batchEligible !== "boolean" || typeof value.canCraftOne !== "boolean") {
    fail("recipe_projection_invalid", phase, "recipe projection is malformed");
  }
  if (!AVAILABILITY_CODES.has(value.availability)
      || value.canCraftOne !== (value.availability === "ready")) {
    fail("recipe_availability_invalid", phase, "recipe availability is not authoritative");
  }
  validateProjectedItem(value.output, false, phase);
  requireCost(value.baseCost, phase);
  return value;
}

function validateMaterial(value, phase) {
  exactKeys(value, ["name", "displayName", "icon", "itemKind", "required", "owned",
    "maxEnhancement", "isQuantity", "tier", "consumed", "enough", "storageKind"], [],
  "material_projection_keys_invalid", phase);
  if (!finiteNonNegative(value.required)
      || !finiteNonNegative(value.owned) || typeof value.consumed !== "boolean"
      || typeof value.isQuantity !== "boolean" || typeof value.enough !== "boolean"
      || !["equipment", "stack"].includes(value.itemKind)
      || !finiteNonNegative(value.maxEnhancement) || !boundedText(value.tier, 128, true)
      || !STORAGE_KINDS.has(value.storageKind)) {
    fail("material_projection_invalid", phase, "material projection is malformed");
  }
  identityTriple(value, phase);
  return value;
}

function validateOutputDelivery(value, output, phase) {
  exactKeys(value, ["available", "storageKind", "mode", "physicalSlot", "quantity"], [],
    "output_delivery_keys_invalid", phase);
  if (typeof value.available !== "boolean" || !STORAGE_KINDS.has(value.storageKind)
      || !Number.isInteger(value.physicalSlot) || !finiteNonNegative(value.quantity)
      || value.quantity !== output.quantity) {
    fail("output_delivery_invalid", phase, "output delivery capability is malformed");
  }
  if (!value.available) {
    if (value.storageKind !== "unavailable" || value.mode !== "none"
        || value.physicalSlot !== -1) {
      fail("output_delivery_invalid", phase, "unavailable output route is not closed");
    }
  } else if (value.storageKind === "bag") {
    if (!(value.mode === "insert" || value.mode === "merge" && output.itemKind === "stack")
        || !integerIn(value.physicalSlot, 0, 49)) {
      fail("output_delivery_invalid", phase, "bag output route is not one exact physical slot");
    }
  } else if (value.storageKind === "drug") {
    if (output.itemKind !== "stack" || value.mode !== "merge" || value.physicalSlot < 0) {
      fail("output_delivery_invalid", phase, "drug output route is not one existing stack");
    }
  } else if (["material_collection", "information_collection"].includes(value.storageKind)) {
    if (output.itemKind !== "stack" || value.mode !== "increment" || value.physicalSlot !== -1) {
      fail("output_delivery_invalid", phase, "collection output route is malformed");
    }
  } else {
    fail("output_delivery_invalid", phase, "available output route uses an unsupported storage kind");
  }
  return value;
}

function validateOutputPrototype(value, output, delivery, phase) {
  const physical = delivery && delivery.available === true
    && ["bag", "drug"].includes(delivery.storageKind);
  if (!physical) {
    if (value !== null || !delivery
        || !["material_collection", "information_collection"].includes(delivery.storageKind)) {
      fail("output_prototype_route_invalid", phase,
        "non-physical output route must carry one explicit null prototype");
    }
    return value;
  }
  exactKeys(value, ["item", "confirmProjection"], [],
    "output_prototype_keys_invalid", phase);
  if (!InventoryRuntime.isValidItemProjection(value.item)
      || !InventoryRuntime.isValidStableConfirmProjection(
        value.confirmProjection, value.item)) {
    fail("output_prototype_invalid", phase,
      "output prototype is not the production Inventory projection contract");
  }
  if (!sameTriple(value.item, output) || value.item.itemKind !== output.itemKind
      || value.item.quantity !== output.quantity
      || value.item.enhancementLevel !== output.enhancementLevel
      || value.item.quantity !== delivery.quantity) {
    fail("output_prototype_projection_mismatch", phase,
      "output prototype is detached from the Crafting output and delivery");
  }
  return value;
}

function validateOutputReceipt(value, acceptedPlan, crafted, phase) {
  const delivery = acceptedPlan && acceptedPlan.outputDelivery;
  const physical = delivery && delivery.available === true
    && ["bag", "drug"].includes(delivery.storageKind);
  if (!physical) {
    if (value !== null || !delivery
        || !["material_collection", "information_collection"].includes(delivery.storageKind)) {
      fail("output_receipt_route_invalid", phase,
        "non-physical output route must carry one explicit null receipt");
    }
    return value;
  }
  exactKeys(value, ["item", "confirmProjection"], [],
    "output_receipt_keys_invalid", phase);
  if (!InventoryRuntime.isValidItemProjection(value.item)
      || !InventoryRuntime.isValidConfirmProjection(value.confirmProjection, value.item)) {
    fail("output_receipt_invalid", phase,
      "output receipt is not the production Inventory projection contract");
  }
  const prototype = acceptedPlan.outputPrototype;
  const postQuantity = Number(value.item.quantity);
  if (!prototype || !Number.isInteger(postQuantity) || postQuantity < 1
      || delivery.mode === "insert" && postQuantity !== crafted.quantity
      || delivery.mode === "merge" && postQuantity < crafted.quantity) {
    fail("output_receipt_quantity_invalid", phase,
      "output receipt quantity is inconsistent with its frozen delivery mode");
  }
  const normalizedItem = deepClone(value.item);
  normalizedItem.quantity = prototype.item.quantity;
  const normalizedConfirm = deepClone(value.confirmProjection);
  delete normalizedConfirm.lastUpdate;
  normalizedConfirm.quantity = prototype.confirmProjection.quantity;
  if (!same(normalizedItem, prototype.item)
      || !same(normalizedConfirm, prototype.confirmProjection)) {
    fail("output_receipt_projection_mismatch", phase,
      "output receipt stable fields differ from the frozen prototype");
  }
  return value;
}

function validateAcceptedPlan(value, response, outputField, phase) {
  exactKeys(value, ["category", "recipeIndex", "craftCount", "output", "materials",
    "outputDelivery", "outputPrototype", "cost"], [], "accepted_plan_keys_invalid", phase);
  if (value.category !== response.category || value.recipeIndex !== response.recipeIndex
      || value.craftCount !== response.craftCount || !same(value.output, response[outputField])) {
    fail("accepted_plan_selector_invalid", phase,
      "accepted plan does not exactly bind selector and output");
  }
  validateProjectedItem(value.output, true, phase);
  if (!Array.isArray(value.materials)) {
    fail("accepted_plan_materials_invalid", phase, "accepted plan materials are not an array");
  }
  value.materials.forEach((entry) => validateMaterial(entry, phase));
  validateOutputDelivery(value.outputDelivery, value.output, phase);
  validateOutputPrototype(value.outputPrototype, value.output, value.outputDelivery, phase);
  requireCost(value.cost, phase);
  return value;
}

function validateResponse(message, request, phase) {
  if (!Evidence.isPlainObject(message) || message.type !== "panel_resp"
      || message.domain !== "crafting" || message.panel !== "crafting"
      || message.panelInstanceId !== request.panelInstanceId || message.cmd !== request.cmd
      || message.callId !== request.callId || message.success !== true || message.v !== 1) {
    fail("crafting_response_invalid", phase,
      "Crafting response does not exactly correlate to its Web request", { message });
  }
  if (request.cmd === "snapshot") {
    exactKeys(message, ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
      "success", "v", "category", "gender", "recipes", "balance", "skills", "note"],
    [], "snapshot_response_keys_invalid", phase);
    if (message.category !== request.payload.category || !Array.isArray(message.recipes)
        || message.recipes.length < 1 || new Set(message.recipes.map((entry) => entry.recipeIndex)).size
          !== message.recipes.length || !["男", "女"].includes(message.gender)
        || !boundedText(message.note, 2000, true)) {
      fail("snapshot_response_invalid", phase, "snapshot response is malformed");
    }
    message.recipes.forEach((entry) => validateRecipe(entry, phase));
    requireBalance(message.balance, phase);
    requireSkills(message.skills, phase);
  } else if (request.cmd === "preview") {
    exactKeys(message, ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
      "success", "v", "category", "recipeIndex", "craftCount", "batchEligible",
      "maxCraftCount", "output", "materials", "cost", "balance", "skills",
      "levelAllowed", "enoughMaterials", "enoughMoney", "enoughKpoints", "enoughSpace",
      "canCommit", "blockingError", "outputDelivery", "craftTokenRef", "acceptedPlan"], [],
    "preview_response_keys_invalid", phase);
    if (message.category !== request.payload.category
        || message.recipeIndex !== request.payload.recipeIndex
        || message.craftCount !== request.payload.craftCount
        || message.canCommit !== true || !TOKEN_REF_RE.test(String(message.craftTokenRef || ""))
        || own(message, "craftToken") || !Array.isArray(message.materials)
        || typeof message.batchEligible !== "boolean"
        || !integerIn(message.maxCraftCount, 0, 99)
        || message.maxCraftCount < message.craftCount
        || !["levelAllowed", "enoughMaterials", "enoughMoney", "enoughKpoints",
          "enoughSpace", "canCommit"].every((key) => typeof message[key] === "boolean")
        || message.canCommit !== (message.levelAllowed && message.enoughMaterials
          && message.enoughMoney && message.enoughKpoints && message.enoughSpace)
        || message.blockingError !== ""
        || !message.batchEligible && (message.craftCount !== 1 || message.maxCraftCount > 1)) {
      fail("preview_response_invalid", phase,
        "preview response selector/authority contract is malformed");
    }
    validateProjectedItem(message.output, true, phase);
    message.materials.forEach((entry) => validateMaterial(entry, phase));
    validateOutputDelivery(message.outputDelivery, message.output, phase);
    validateAcceptedPlan(message.acceptedPlan, message, "output", phase);
    if (!same(message.acceptedPlan.materials, message.materials)
        || !same(message.acceptedPlan.outputDelivery, message.outputDelivery)
        || !same(message.acceptedPlan.cost, message.cost)) {
      fail("accepted_plan_projection_mismatch", phase,
        "accepted plan is not the exact authoritative preview projection");
    }
    requireBalance(message.balance, phase);
    requireCost(message.cost, phase);
    requireSkills(message.skills, phase);
  } else if (request.cmd === "commit") {
    exactKeys(message, ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
      "success", "v", "operation", "category", "recipeIndex", "craftCount", "crafted",
      "acceptedPlan", "outputReceipt", "balance"], [], "commit_response_keys_invalid", phase);
    if (message.operation !== "commit" || message.category !== request.payload.category
        || !integerIn(message.recipeIndex, 0, 999) || !integerIn(message.craftCount, 1, 99)) {
      fail("commit_response_invalid", phase, "commit response postcondition is malformed");
    }
    validateProjectedItem(message.crafted, true, phase);
    validateAcceptedPlan(message.acceptedPlan, message, "crafted", phase);
    validateOutputReceipt(message.outputReceipt, message.acceptedPlan, message.crafted, phase);
    if (message.crafted.itemKind === "equipment"
        ? message.craftCount !== 1 || message.crafted.quantity !== 1
        : message.crafted.quantity < message.craftCount) {
      fail("commit_response_invalid", phase,
        "crafted output quantity is inconsistent with the authoritative craft count");
    }
    requireBalance(message.balance, phase);
  }
  return message;
}

function validateInventoryRequest(message, owner, phase) {
  exactKeys(message, ["type", "domain", "panel", "panelInstanceId", "cmd", "callId", "payload"],
    [], "inventory_request_keys_invalid", phase);
  if (message.type !== "panel" || message.domain !== "inventory" || message.panel !== "crafting"
      || message.panelInstanceId !== owner || message.cmd !== "snapshot"
      || !CALL_ID_RE.test(String(message.callId || ""))) {
    fail("inventory_request_invalid", phase, "Inventory request is outside the Crafting owner");
  }
  exactKeys(message.payload, ["v", "requests"], [], "inventory_payload_keys_invalid", phase);
  if (message.payload.v !== 1 || !Array.isArray(message.payload.requests)
      || message.payload.requests.length !== 2) {
    fail("inventory_payload_invalid", phase, "Inventory must request exactly two full containers");
  }
  const expected = [{ containerId: BAG_CONTAINER, limit: 50 },
    { containerId: BATTLEBOX_CONTAINER, limit: 40 }];
  message.payload.requests.forEach((entry, index) => {
    exactKeys(entry, ["containerId", "offset", "limit", "filterKey"], ["filterSpec", "scope"],
      "inventory_window_keys_invalid", phase);
    if (entry.containerId !== expected[index].containerId
        || entry.offset !== 0 || entry.limit !== expected[index].limit
        || entry.filterKey !== "all" || own(entry, "filterSpec") || own(entry, "scope")) {
      fail("inventory_window_invalid", phase,
        "Inventory window is not the exact ordered 50+40 physical read scope");
    }
  });
  return message;
}

function validateRedactedInventorySnapshot(snapshot, phase) {
  if (!Evidence.isPlainObject(snapshot) || !Array.isArray(snapshot.slots)) {
    fail("inventory_snapshot_invalid", phase, "Inventory snapshot is not an object with slots");
  }
  const restored = deepClone(snapshot);
  restored.slots.forEach((slot, index) => {
    if (!Evidence.isPlainObject(slot) || !TOKEN_REF_RE.test(String(slot.slotLeaseRef || ""))
        || own(slot, "slotLease")) {
      fail("inventory_slot_lease_reference_invalid", phase,
        "persisted Inventory slot lacks one redacted production lease reference", { index });
    }
    slot.slotLease = "lease_ref_" + slot.slotLeaseRef.slice("sha256_".length);
    delete slot.slotLeaseRef;
  });
  if (!InventoryRuntime.isValidSnapshot(restored)) {
    fail("inventory_snapshot_invalid", phase,
      "Inventory snapshot does not match the production nested validator");
  }
  return restored;
}

function validateInventoryResponse(message, request, phase) {
  exactKeys(message, ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
    "success", "v", "sessionNonce", "snapshots"], [],
  "inventory_response_keys_invalid", phase);
  if (message.type !== "panel_resp" || message.domain !== "inventory"
      || message.panel !== "crafting" || message.panelInstanceId !== request.panelInstanceId
      || message.cmd !== "snapshot" || message.callId !== request.callId
      || message.success !== true || message.v !== 1
      || !boundedText(message.sessionNonce, 256, false)
      || !Array.isArray(message.snapshots) || message.snapshots.length !== 2) {
    fail("inventory_response_invalid", phase, "Inventory response envelope is malformed");
  }
  message.snapshots.forEach((snapshot, index) => {
    const requested = request.payload.requests[index];
    const restored = validateRedactedInventorySnapshot(snapshot, phase);
    const bagShape = index === 0 && restored.containerId === BAG_CONTAINER
      && restored.capacity === 50 && restored.accessibleCapacity === 50
      && restored.viewCapacity === 50;
    const battleboxShape = index === 1 && restored.containerId === BATTLEBOX_CONTAINER
      && restored.capacity === 400 && restored.accessibleCapacity >= 40
      && restored.accessibleCapacity <= 400 && restored.accessibleCapacity % 40 === 0
      && restored.viewCapacity === restored.accessibleCapacity;
    if (restored.containerId !== requested.containerId || restored.offset !== 0
        || restored.limit !== requested.limit || restored.viewCapacity < requested.limit
        || !(bagShape || battleboxShape)
        || restored.filterKey !== "all" || own(restored, "filterSpec") || own(restored, "scope")) {
      fail("inventory_snapshot_invalid", phase,
        "Inventory snapshot is not the production-shaped exact full window", { index });
    }
  });
  return message;
}

function durableSlot(slot) {
  const value = deepClone(slot);
  delete value.slotLeaseRef;
  return value;
}

function durableSnapshot(snapshot, restartProjection) {
  const value = deepClone(snapshot);
  value.slots = value.slots.map(durableSlot);
  delete value.snapshotSeq;
  if (restartProjection === true) {
    delete value.containerEpoch;
    delete value.containerVersion;
  }
  return value;
}

function exactContainer(response, index, containerId, phase) {
  const snapshot = response && response.snapshots && response.snapshots[index];
  if (!snapshot || snapshot.containerId !== containerId) {
    fail("inventory_container_projection_invalid", phase,
      "ordered Inventory response lacks one exact container", { index, containerId });
  }
  return snapshot;
}

function sameStablePrototypeItem(item, prototype) {
  if (!item || !prototype) return false;
  const normalized = deepClone(item);
  normalized.quantity = prototype.quantity;
  return same(normalized, prototype);
}

function assertSlotMaterialIdentity(slot, material, phase) {
  if (!slot || slot.occupied !== true || !slot.item
      || !sameTriple(slot.item, material) || slot.item.itemKind !== material.itemKind) {
    fail("inventory_material_identity_ambiguous", phase,
      "same-name physical requirement is detached from its preview identity");
  }
}

function emptyDurableSlot(physicalSlot) {
  return { physicalSlot, occupied: false };
}

function consumePhysicalMaterials(shadow, materials, output, phase) {
  const materialNames = new Set();
  materials.forEach((material, materialIndex) => {
    if (materialNames.has(material.name) || material.name === output.name) {
      fail("inventory_material_plan_ambiguous", phase,
        "duplicate requirement names and output self-reference are not admitted", { materialIndex });
    }
    materialNames.add(material.name);
    if (material.storageKind !== "bag") {
      fail("inventory_material_route_unobserved", phase,
        "precommit admits only deductions projected to the full 50-slot bag", {
          materialIndex, storageKind: material.storageKind,
        });
    }
    if (material.consumed === false) return;
    if (!Number.isInteger(material.required) || material.required < 1) {
      fail("inventory_material_quantity_invalid", phase,
        "physical requirement is not one positive integer", { materialIndex });
    }
    const matches = shadow.filter((slot) => slot.occupied === true
      && slot.item && slot.item.name === material.name);
    matches.forEach((slot) => assertSlotMaterialIdentity(slot, material, phase));
    if (material.itemKind === "equipment") {
      const selected = material.isQuantity === true
        ? matches.slice(0, material.required)
        : matches.filter((slot) => slot.item.enhancementLevel >= material.required).slice(0, 1);
      const needed = material.isQuantity === true ? material.required : 1;
      if (selected.length !== needed) {
        fail("inventory_material_not_physically_observable", phase,
          "equipment requirement cannot be fully proven in the ordered bag window", {
            materialIndex,
          });
      }
      selected.forEach((slot) => { shadow[slot.physicalSlot] = emptyDurableSlot(slot.physicalSlot); });
      return;
    }
    let remaining = material.required;
    matches.forEach((slot) => {
      if (remaining <= 0) return;
      const quantity = Number(slot.item.quantity);
      if (!Number.isInteger(quantity) || quantity < 1) {
        fail("inventory_material_quantity_invalid", phase,
          "physical stack requirement has an invalid quantity", { materialIndex });
      }
      const consumed = Math.min(quantity, remaining);
      if (consumed === quantity) {
        shadow[slot.physicalSlot] = emptyDurableSlot(slot.physicalSlot);
      } else {
        slot.item.quantity -= consumed;
        slot.confirmProjection.quantity -= consumed;
      }
      remaining -= consumed;
    });
    if (remaining !== 0) {
      fail("inventory_material_not_physically_observable", phase,
        "stack requirement spills into an unobserved collection or drug slot", { materialIndex });
    }
  });
}

function resolveBagOutput(shadow, output, outputPrototype, phase) {
  const quantity = Number(output.quantity);
  if (!Number.isInteger(quantity) || quantity < 1) {
    fail("inventory_output_quantity_invalid", phase, "crafted output quantity is not integral");
  }
  let target = -1;
  let mode = "insert";
  if (output.itemKind === "stack") {
    const sameName = shadow.filter((slot) => slot.occupied === true
      && slot.item && slot.item.name === output.name);
    sameName.forEach((slot) => {
      if (!outputPrototype || !sameStablePrototypeItem(slot.item, outputPrototype.item)) {
        fail("inventory_output_identity_ambiguous", phase,
          "same-name output stack differs from the frozen full prototype");
      }
    });
    if (sameName.length) { target = sameName[0].physicalSlot; mode = "merge"; }
  }
  if (target < 0) {
    const vacancy = shadow.find((slot) => slot.occupied === false);
    if (!vacancy) fail("inventory_output_delivery_unobservable", phase,
      "crafted output has no deterministic bag destination");
    target = vacancy.physicalSlot;
  }
  return { containerId: BAG_CONTAINER, storageKind: "bag", available: true,
    physicalSlot: target, mode, quantity };
}

function requireProjectedBagDelivery(projected, resolved, phase) {
  if (!projected || projected.available !== true || projected.storageKind !== "bag"
      || projected.physicalSlot !== resolved.physicalSlot || projected.mode !== resolved.mode
      || projected.quantity !== resolved.quantity) {
    fail("inventory_output_route_mismatch", phase,
      "AS2 outputDelivery does not match the deterministic full-bag planner", {
        projected, resolved,
      });
  }
}

function applyBagOutput(shadow, actualAfter, output, outputPrototype, outputReceipt,
  projectedDelivery, phase) {
  const resolved = resolveBagOutput(shadow, output, outputPrototype, phase);
  requireProjectedBagDelivery(projectedDelivery, resolved, phase);
  const { physicalSlot: target, mode, quantity } = resolved;
  const afterSlot = actualAfter[target];
  const expectedQuantity = mode === "merge"
    ? shadow[target].item.quantity + quantity : quantity;
  const expectedSlot = outputReceipt && {
    physicalSlot: target, occupied: true,
    item: deepClone(outputReceipt.item),
    confirmProjection: deepClone(outputReceipt.confirmProjection),
  };
  if (!outputReceipt || outputReceipt.item.quantity !== expectedQuantity
      || outputReceipt.confirmProjection.quantity !== expectedQuantity
      || !same(afterSlot, expectedSlot)) {
    fail("inventory_output_delivery_invalid", phase,
      "full Inventory readback differs from the commit-side output receipt", {
        target, mode,
      });
  }
  if (mode === "merge") {
    if (outputReceipt.confirmProjection.lastUpdate
        < shadow[target].confirmProjection.lastUpdate) {
      fail("inventory_output_update_time_invalid", phase,
        "merged output lastUpdate moved backwards");
    }
  }
  // Expected state comes only from preview prototype + commit receipt. Never clone after into itself.
  shadow[target] = expectedSlot;
  return { containerId: BAG_CONTAINER, physicalSlot: target, mode, quantity };
}

function planInventoryTransition(beforeResponse, preview, phase) {
  const beforeBag = exactContainer(beforeResponse, 0, BAG_CONTAINER, phase);
  exactContainer(beforeResponse, 1, BATTLEBOX_CONTAINER, phase);
  const shadow = beforeBag.slots.map(durableSlot);
  consumePhysicalMaterials(shadow, preview.materials, preview.output, phase);
  const delivery = resolveBagOutput(shadow, preview.output,
    preview.acceptedPlan.outputPrototype, phase);
  requireProjectedBagDelivery(preview.outputDelivery, delivery, phase);
  if (!same(preview.acceptedPlan.output, preview.output)
      || !same(preview.acceptedPlan.materials, preview.materials)
      || !same(preview.acceptedPlan.outputDelivery, preview.outputDelivery)) {
    fail("precommit_accepted_plan_mismatch", phase,
      "precommit authority differs from its accepted plan");
  }
  return { delivery, beforeDurable: beforeResponse.snapshots.map(
    (snapshot) => durableSnapshot(snapshot, true)) };
}

function verifyInventoryTransition(beforeResponse, afterResponse, preview, commit) {
  const beforeBag = exactContainer(beforeResponse, 0, BAG_CONTAINER, "inventory.before");
  const afterBag = exactContainer(afterResponse, 0, BAG_CONTAINER, "inventory.after");
  const beforeBattlebox = exactContainer(beforeResponse, 1, BATTLEBOX_CONTAINER,
    "inventory.before");
  const afterBattlebox = exactContainer(afterResponse, 1, BATTLEBOX_CONTAINER,
    "inventory.after");
  if (!same(durableSnapshot(beforeBattlebox, false),
    durableSnapshot(afterBattlebox, false))) {
    fail("inventory_battlebox_mutation_forbidden", "postcondition",
      "Crafting changed the 40-slot battlebox page or its durable metadata");
  }
  if (beforeBag.containerEpoch !== afterBag.containerEpoch
      || afterBag.containerVersion <= beforeBag.containerVersion) {
    fail("inventory_bag_version_invalid", "postcondition",
      "bag mutation did not advance one same-epoch authority version");
  }
  const bagShell = (snapshot) => {
    const value = durableSnapshot(snapshot, false);
    delete value.slots; delete value.snapshotSeq; delete value.containerVersion;
    delete value.filterFacets; delete value.filterItemCount;
    delete value.setFacets; delete value.setFilterItemCount;
    return value;
  };
  if (!same(bagShell(beforeBag), bagShell(afterBag))) {
    fail("inventory_bag_window_drift", "postcondition",
      "bag capacity/window contract changed around commit");
  }
  const beforeSlots = beforeBag.slots.map(durableSlot);
  const afterSlots = afterBag.slots.map(durableSlot);
  const shadow = deepClone(beforeSlots);
  consumePhysicalMaterials(shadow, preview.materials, commit.crafted, "postcondition");
  const delivery = applyBagOutput(shadow, afterSlots, commit.crafted,
    preview.acceptedPlan.outputPrototype, commit.outputReceipt,
    preview.outputDelivery, "postcondition");
  if (!same(shadow, afterSlots)) {
    fail("inventory_slot_delta_mismatch", "postcondition",
      "bag slots differ from exact AS2 submit-then-acquire simulation");
  }
  const occupiedAfter = afterSlots.filter((slot) => slot.occupied === true).length;
  if (afterBag.filterItemCount !== occupiedAfter) {
    fail("inventory_facet_count_mismatch", "postcondition",
      "full bag facet count differs from occupied physical slots");
  }
  return { delivery,
    afterDurable: afterResponse.snapshots.map((snapshot) => durableSnapshot(snapshot, true)) };
}

function verifyRestartInventory(response, firstInventory) {
  const durable = response.snapshots.map((snapshot) => durableSnapshot(snapshot, true));
  if (!same(durable, firstInventory.afterDurable)) {
    fail("inventory_restart_projection_mismatch", "restart",
      "restart changed the durable 90-slot post-commit projection or facets");
  }
  return durable;
}

function inventoryOutputCount(response, identity, phase) {
  let count = 0;
  response.snapshots.forEach((snapshot) => snapshot.slots.forEach((slot) => {
    if (!Evidence.isPlainObject(slot) || slot.occupied !== true || !Evidence.isPlainObject(slot.item)) return;
    const item = slot.item;
    if (item.name === identity.name && item.displayName === identity.displayName
        && item.icon === identity.icon) {
      const quantity = Number(item.quantity);
      if (!Number.isFinite(quantity) || quantity < 1) {
        fail("inventory_output_quantity_invalid", phase, "matched output has invalid quantity");
      }
      count += quantity;
    }
  }));
  return count;
}

function collectPairs(transcript, phase) {
  verifyRecordChain(transcript);
  const open = exactOpen(transcript, phase);
  const observedSends = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
    .filter((entry) => entry.event.kind === "bridge_send" && entry.message);
  if (observedSends.some((entry) => own(entry.event, "sendOrder"))) {
    fail("observer_order_claim_forbidden", phase,
      "Bridge observer must not self-report an internal mux-issued order");
  }
  if (observedSends.some((entry) => entry.message.type === "debug"
      && entry.message.scope === "crafting"
      && /^(?:preview|commit)_issued$/.test(String(entry.message.event || "")))) {
    fail("observer_issued_diagnostic_forbidden", phase,
      "page-authored issued diagnostics are not authority evidence");
  }
  const requests = observedSends.filter((entry) => entry.message.domain === "crafting");
  const callIds = new Set();
  const pairs = requests.map((request) => {
    validateRequest(request.message, open.owner, open.category, phase);
    if (callIds.has(request.message.callId)) {
      fail("web_call_id_reused", phase, "Web callId is not one-shot", { callId: request.message.callId });
    }
    callIds.add(request.message.callId);
    const matches = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
      .filter((entry) => entry.event.kind === "webview_message" && entry.message
        && entry.message.type === "panel_resp" && entry.message.domain === "crafting"
        && entry.message.callId === request.message.callId);
    if (matches.length !== 1 || matches[0].event.sequence <= request.event.sequence) {
      fail("web_response_count_invalid", phase,
        "Crafting request lacks one later exact response", { callId: request.message.callId });
    }
    validateResponse(matches[0].message, request.message, phase);
    if (!request.event.panelState || request.event.panelState.panel !== "crafting"
        || request.event.panelState.craftingVisible !== true
        || !matches[0].event.panelState || matches[0].event.panelState.panel !== "crafting") {
      fail("panel_view_binding_invalid", phase,
        "business traffic is outside the exact visible Crafting view");
    }
    return { requestEvent: request.event, request: request.message,
      responseEvent: matches[0].event, response: matches[0].message };
  });
  const inventoryRequests = observedSends.filter((entry) => entry.message.domain === "inventory");
  const expectedInventory = phase === "first" ? INVENTORY_FIRST : INVENTORY_RESTART;
  if (canonical(inventoryRequests.map((entry) => entry.message.cmd)) !== canonical(expectedInventory)) {
    fail("inventory_command_order_invalid", phase, "Inventory readback command set is not exact");
  }
  const inventoryPairs = inventoryRequests.map((request) => {
    validateInventoryRequest(request.message, open.owner, phase);
    if (callIds.has(request.message.callId)) {
      fail("web_call_id_reused", phase, "Web callId is reused across Crafting and Inventory");
    }
    callIds.add(request.message.callId);
    const matches = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
      .filter((entry) => entry.event.kind === "webview_message" && entry.message
        && entry.message.type === "panel_resp" && entry.message.domain === "inventory"
        && entry.message.callId === request.message.callId);
    if (matches.length !== 1 || matches[0].event.sequence <= request.event.sequence) {
      fail("inventory_response_count_invalid", phase,
        "Inventory request lacks one later exact response", { callId: request.message.callId });
    }
    validateInventoryResponse(matches[0].message, request.message, phase);
    return { requestEvent: request.event, request: request.message,
      responseEvent: matches[0].event, response: matches[0].message };
  });
  const allResponses = transcript.events.filter((event) => event.kind === "webview_message"
    && parseMessage(event) && ["crafting", "inventory"].includes(parseMessage(event).domain)
    && parseMessage(event).type === "panel_resp");
  if (allResponses.length !== pairs.length + inventoryPairs.length) {
    fail("response_set_not_exact", phase, "extra or duplicate authority responses were observed");
  }
  const closeRequests = observedSends.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "crafting" && entry.message.cmd === "close");
  if (closeRequests.length !== 1) {
    fail("close_send_count_invalid", phase,
      "each lifecycle requires one exact production close Bridge.send", { count: closeRequests.length });
  }
  const close = closeRequests[0];
  exactKeys(close.message, ["type", "cmd", "panel", "panelInstanceId"], [],
    "close_send_keys_invalid", phase);
  if (close.message.panelInstanceId !== open.owner || own(close.message, "domain")
      || !close.event.panelState || close.event.panelState.panel !== "crafting"
      || close.event.panelState.craftingVisible !== true) {
    fail("close_send_invalid", phase,
      "close send is detached from the exact visible Crafting owner");
  }
  const closedStates = transcript.events.filter((event) => event.kind === "panel_state_sample"
    && event.label === "after_close");
  if (closedStates.length !== 1 || closedStates[0].sequence <= close.event.sequence
      || !closedStates[0].panelState || closedStates[0].panelState.hidden !== true
      || closedStates[0].panelState.craftingVisible !== false
      || closedStates[0].panelState.panel !== "") {
    fail("close_hidden_state_invalid", phase,
      "one post-close sample must prove the Crafting panel is hidden", {
        count: closedStates.length,
      });
  }
  return { open, pairs, inventoryPairs, close, closedState: closedStates[0] };
}

function verifyPreCommitAuthority(transcript, expectedSelector) {
  const phase = "precommit";
  verifyRecordChain(transcript);
  const open = exactOpen(transcript, phase);
  const observedSends = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
    .filter((entry) => entry.event.kind === "bridge_send" && entry.message);
  const requests = observedSends.filter((entry) => entry.message.domain === "crafting");
  if (!same(requests.map((entry) => entry.message.cmd), FIRST_COMMANDS.slice(0, 6))
      || requests.some((entry) => entry.message.cmd === "commit")) {
    fail("precommit_command_set_invalid", phase,
      "precommit boundary must contain six read-only Crafting requests and zero commit requests");
  }
  const callIds = new Set();
  const pairs = requests.map((request) => {
    validateRequest(request.message, open.owner, open.category, phase);
    if (callIds.has(request.message.callId)) {
      fail("web_call_id_reused", phase, "precommit Web callId is not one-shot");
    }
    callIds.add(request.message.callId);
    const matches = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
      .filter((entry) => entry.event.kind === "webview_message" && entry.message
        && entry.message.type === "panel_resp" && entry.message.domain === "crafting"
        && entry.message.callId === request.message.callId);
    if (matches.length !== 1 || matches[0].event.sequence <= request.event.sequence) {
      fail("web_response_count_invalid", phase,
        "precommit Crafting request lacks one later exact response");
    }
    validateResponse(matches[0].message, request.message, phase);
    return { requestEvent: request.event, request: request.message,
      responseEvent: matches[0].event, response: matches[0].message };
  });
  const inventoryRequests = observedSends.filter((entry) => entry.message.domain === "inventory");
  if (inventoryRequests.length !== 1 || inventoryRequests[0].message.cmd !== "snapshot") {
    fail("precommit_inventory_count_invalid", phase,
      "precommit requires exactly one authoritative 90-slot Inventory read");
  }
  const inventoryRequest = inventoryRequests[0];
  validateInventoryRequest(inventoryRequest.message, open.owner, phase);
  if (callIds.has(inventoryRequest.message.callId)) {
    fail("web_call_id_reused", phase, "Inventory callId is reused at precommit");
  }
  const inventoryMatches = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
    .filter((entry) => entry.event.kind === "webview_message" && entry.message
      && entry.message.type === "panel_resp" && entry.message.domain === "inventory"
      && entry.message.callId === inventoryRequest.message.callId);
  if (inventoryMatches.length !== 1
      || inventoryMatches[0].event.sequence <= inventoryRequest.event.sequence) {
    fail("inventory_response_count_invalid", phase,
      "precommit Inventory request lacks one later exact response");
  }
  validateInventoryResponse(inventoryMatches[0].message, inventoryRequest.message, phase);
  const inventoryPair = { requestEvent: inventoryRequest.event,
    request: inventoryRequest.message, responseEvent: inventoryMatches[0].event,
    response: inventoryMatches[0].message };
  const allPairs = orderedPairs(pairs, [inventoryPair]);
  const expectedOrder = [
    "crafting:snapshot", "crafting:preview", "crafting:preview",
    "crafting:snapshot", "inventory:snapshot", "crafting:snapshot", "crafting:preview",
  ];
  if (!same(requestSignatures(allPairs), expectedOrder)) {
    fail("precommit_request_order_invalid", phase,
      "read-only authority and Inventory boundary order is not exact");
  }
  const allAuthorityResponses = transcript.events.filter((event) => event.kind === "webview_message"
    && parseMessage(event) && ["crafting", "inventory"].includes(parseMessage(event).domain)
    && parseMessage(event).type === "panel_resp");
  if (allAuthorityResponses.length !== pairs.length + 1) {
    fail("precommit_response_set_not_exact", phase,
      "precommit contains extra or duplicate authority responses");
  }
  const acceptedPreview = pairs[5].response;
  const selector = { category: acceptedPreview.category,
    recipeIndex: acceptedPreview.recipeIndex, craftCount: acceptedPreview.craftCount };
  if (!same(selector, expectedSelector)) {
    fail("precommit_selector_drift", phase,
      "precommit authoritative preview differs from the selected candidate", {
        expectedSelector, selector,
      });
  }
  const inputs = exactTrustedInputGrammar(transcript, selector.recipeIndex,
    ["recipe", "organizer", "return"], phase);
  if (trustedInputs(transcript).some((event) => classifyTrustedInput(event,
    selector.recipeIndex) === "commit")) {
    fail("precommit_input_already_issued", phase, "commit input exists before admission");
  }
  const plan = planInventoryTransition(inventoryPair.response, acceptedPreview, phase);
  return { owner: open.owner, selector, acceptedPreview, inventoryPair,
    plan, trustedInputs: inputs };
}

function commands(pairs) { return pairs.map((entry) => entry.request.cmd); }
function orderedPairs(left, right) {
  return left.concat(right).sort((a, b) => a.requestEvent.sequence - b.requestEvent.sequence);
}

function requestSignatures(pairs) {
  return pairs.map((entry) => entry.request.domain + ":" + entry.request.cmd);
}

function trustedInputs(transcript) {
  return transcript.events.filter((event) => event.kind === "dom_input"
    && ["click", "keydown"].includes(event.eventType)
    && event.isTrusted === true);
}

function classifyTrustedInput(event, recipeIndex) {
  if (event.eventType !== "click" || event.button !== 0 || !event.target
      || !event.panelState || event.panelState.panel !== "crafting"
      || event.panelState.craftingVisible !== true) return null;
  const targetKeys = ["attributes", "clientPoint", "enabled", "hitTargetMatches",
    "mutationCapable", "rect", "selector", "tagName", "text", "viewport", "visible"];
  const rectKeys = ["bottom", "height", "left", "right", "top", "width"];
  const viewportKeys = ["height", "scrollX", "scrollY", "width"];
  if (canonical(Object.keys(event.target).sort()) !== canonical(targetKeys.slice().sort())
      || canonical(Object.keys(event.target.rect || {}).sort()) !== canonical(rectKeys.slice().sort())
      || canonical(Object.keys(event.target.viewport || {}).sort())
        !== canonical(viewportKeys.slice().sort())
      || canonical(Object.keys(event.target.clientPoint || {}).sort()) !== canonical(["x", "y"])
      || canonical(Object.keys(event.coordinates || {}).sort()) !== canonical(["x", "y"])
      || event.target.tagName !== "BUTTON" || event.target.visible !== true
      || event.target.enabled !== true || event.target.hitTargetMatches !== true
      || !Number.isFinite(event.target.rect.left) || !Number.isFinite(event.target.rect.top)
      || !Number.isFinite(event.target.rect.right) || !Number.isFinite(event.target.rect.bottom)
      || !Number.isFinite(event.target.rect.width) || !Number.isFinite(event.target.rect.height)
      || event.target.rect.width <= 0 || event.target.rect.height <= 0
      || event.target.rect.right !== event.target.rect.left + event.target.rect.width
      || event.target.rect.bottom !== event.target.rect.top + event.target.rect.height
      || !Number.isFinite(event.coordinates.x) || !Number.isFinite(event.coordinates.y)
      || event.coordinates.x !== event.target.clientPoint.x
      || event.coordinates.y !== event.target.clientPoint.y
      || !Number.isFinite(event.target.viewport.width)
      || !Number.isFinite(event.target.viewport.height)
      || !Number.isFinite(event.target.viewport.scrollX)
      || !Number.isFinite(event.target.viewport.scrollY)
      || event.target.viewport.width <= 0 || event.target.viewport.height <= 0
      || event.coordinates.x < 0 || event.coordinates.x > event.target.viewport.width
      || event.coordinates.y < 0 || event.coordinates.y > event.target.viewport.height
      || event.coordinates.x < event.target.rect.left
      || event.coordinates.x > event.target.rect.right
      || event.coordinates.y < event.target.rect.top
      || event.coordinates.y > event.target.rect.bottom) return null;
  const attributes = event.target.attributes || {};
  const classes = String(attributes.class || "");
  let role = null;
  if (String(attributes["data-workbench-key"]) === String(recipeIndex)) role = "recipe";
  if (own(attributes, "data-commit-primary") || /(?:^|\s)crafting-commit-btn(?:\s|$)/.test(classes)) {
    role = "commit";
  }
  if (/(?:^|\s)crafting-organizer-btn(?:\s|$)/.test(classes)) role = "organizer";
  if (/(?:^|\s)inventory-return-crafting-btn(?:\s|$)/.test(classes)) role = "return";
  if (attributes["data-header-action"] === "close") role = "close";
  const expectedSelectors = {
    recipe: "button[data-workbench-key=\"" + recipeIndex + "\"]",
    commit: "button[data-commit-primary]",
    organizer: "button.crafting-organizer-btn",
    return: "button.inventory-return-crafting-btn",
    close: "button[data-header-action=\"close\"]",
  };
  const expectedMutation = role === "recipe" || role === "commit";
  return role && event.target.selector === expectedSelectors[role]
    && event.target.mutationCapable === expectedMutation ? role : null;
}

function exactTrustedInputGrammar(transcript, recipeIndex, expected, phase) {
  const inputs = trustedInputs(transcript);
  const classified = inputs.map((event) => ({ event, role: classifyTrustedInput(event, recipeIndex) }));
  if (classified.some((entry) => !entry.role)
      || canonical(classified.map((entry) => entry.role)) !== canonical(expected)) {
    fail("trusted_input_set_invalid", phase,
      "trusted click/keydown set or order is not the exact production journey", {
        expected, actual: classified.map((entry) => ({ role: entry.role,
          eventType: entry.event.eventType, key: entry.event.key || null })),
      });
  }
  const byRole = Object.create(null);
  classified.forEach((entry) => {
    if (!byRole[entry.role]) byRole[entry.role] = [];
    byRole[entry.role].push(entry.event);
  });
  return byRole;
}

function recipeFromSnapshot(snapshot, index, phase) {
  const matches = snapshot.recipes.filter((entry) => entry.recipeIndex === index);
  if (matches.length !== 1) fail("snapshot_recipe_not_exact", phase,
    "snapshot lacks one exact selected recipe", { index });
  return matches[0];
}

function materialDelta(before, after, craftCount) {
  if (before.length !== after.length) {
    fail("material_projection_count_mismatch", "postcondition",
      "fresh preview changed material projection cardinality");
  }
  return before.map((left, index) => {
    const right = after[index];
    if (!right || !sameTriple(left, right) || left.required !== right.required
        || left.consumed !== right.consumed || left.isQuantity !== right.isQuantity
        || left.itemKind !== right.itemKind) {
      fail("material_projection_drift", "postcondition",
        "fresh material projection changed identity or semantics", { index });
    }
    const expected = left.consumed === false ? left.owned
      : left.itemKind === "stack" || left.isQuantity === true
        ? left.owned - left.required : left.owned - 1;
    if (right.owned !== expected) {
      fail(left.itemKind === "stack" || left.isQuantity === true
        ? "stack_material_delta_mismatch" : "equipment_material_refresh_invalid",
      "postcondition", "fresh material owned delta is not exact", { index, expected, actual: right.owned });
    }
    return { identity: identityTriple(left, "postcondition"),
      beforeOwned: left.owned, afterOwned: right.owned };
  });
}

function verifyFirstTranscript(transcript) {
  const result = collectPairs(transcript, "first");
  if (canonical(commands(result.pairs)) !== canonical(FIRST_COMMANDS)) {
    fail("first_command_order_invalid", "first",
      "first lifecycle must include selected preview, pre/post Inventory reads, one commit, and fresh Crafting reads",
    { actual: commands(result.pairs) });
  }
  const allPairs = orderedPairs(result.pairs, result.inventoryPairs);
  const expectedRequestOrder = [
    "crafting:snapshot", "crafting:preview", "crafting:preview",
    "crafting:snapshot", "inventory:snapshot",
    "crafting:snapshot", "crafting:preview", "crafting:commit",
    "crafting:snapshot", "crafting:preview",
    "crafting:snapshot", "inventory:snapshot",
    "crafting:snapshot", "crafting:preview",
  ];
  if (canonical(requestSignatures(allPairs)) !== canonical(expectedRequestOrder)) {
    fail("cross_domain_request_order_invalid", "first",
      "Crafting/Inventory request boundary order is not exact", {
        actual: requestSignatures(allPairs), expected: expectedRequestOrder,
      });
  }
  const inventoryNonces = new Set(result.inventoryPairs.map((entry) => entry.response.sessionNonce));
  if (inventoryNonces.size !== 1) {
    fail("inventory_session_nonce_drift", "first",
      "Inventory sessionNonce changed within one authenticated process");
  }
  const initialSnapshot = result.pairs[0].response;
  const autoPreview = result.pairs[1].response;
  const selectedPreview = result.pairs[2].response;
  const acceptedPreview = result.pairs[5].response;
  const commit = result.pairs[6].response;
  const freshSnapshot = result.pairs[7].response;
  const freshPreview = result.pairs[8].response;
  const finalSnapshot = result.pairs[10].response;
  const finalPreview = result.pairs[11].response;
  const selector = { category: selectedPreview.category, recipeIndex: selectedPreview.recipeIndex,
    craftCount: selectedPreview.craftCount };
  [autoPreview, acceptedPreview, freshPreview, finalPreview].forEach((preview) => {
    if (preview.category !== selector.category || preview.recipeIndex !== selector.recipeIndex
        || preview.craftCount !== selector.craftCount) {
      fail("selector_drift", "first", "same candidate selector drifted across the journey");
    }
  });
  if (commit.category !== selector.category || commit.recipeIndex !== selector.recipeIndex
      || commit.craftCount !== selector.craftCount) {
    fail("commit_selector_drift", "first", "commit selector differs from selected preview");
  }
  if (!same(commit.acceptedPlan, acceptedPreview.acceptedPlan)) {
    fail("commit_accepted_plan_mismatch", "first",
      "commit did not exactly echo the one preview plan accepted by Host");
  }
  const recipe = recipeFromSnapshot(initialSnapshot, selector.recipeIndex, "first");
  const freshRecipe = recipeFromSnapshot(freshSnapshot, selector.recipeIndex, "first");
  if (!sameTriple(recipe.output, selectedPreview.output)
      || !sameTriple(selectedPreview.output, acceptedPreview.output)
      || !sameTriple(acceptedPreview.output, commit.crafted)
      || !sameTriple(commit.crafted, freshRecipe.output)
      || !sameTriple(freshRecipe.output, freshPreview.output)
      || !sameTriple(freshPreview.output, finalPreview.output)
      || !sameTriple(finalPreview.output,
        recipeFromSnapshot(finalSnapshot, selector.recipeIndex, "first").output)) {
    fail("crafted_identity_drift", "first",
      "canonical output identity triple drifted across snapshot/preview/commit/fresh snapshot");
  }
  const consumed = acceptedPreview.craftTokenRef;
  if (result.pairs[6].request.payload.expectedCraftTokenRef !== consumed
      || selectedPreview.craftTokenRef === consumed || freshPreview.craftTokenRef === consumed
      || finalPreview.craftTokenRef === consumed || autoPreview.craftTokenRef === consumed) {
    fail("craft_token_lifecycle_invalid", "first",
      "commit did not consume exactly the selected opaque preview token");
  }
  ["money", "kpoints"].forEach((field) => {
    const expected = acceptedPreview.balance[field] - acceptedPreview.cost[field];
    if (commit.balance[field] !== expected || freshSnapshot.balance[field] !== expected
        || freshPreview.balance[field] !== expected || finalSnapshot.balance[field] !== expected
        || finalPreview.balance[field] !== expected) {
      fail("balance_poststate_mismatch", "postcondition",
        "commit/fresh balance does not equal preview balance minus authoritative cost", { field });
    }
  });
  const inputSet = exactTrustedInputGrammar(transcript, selector.recipeIndex,
    ["recipe", "organizer", "return", "commit", "organizer", "return", "close"], "first");
  const recipeClick = inputSet.recipe[0];
  const commitClick = inputSet.commit[0];
  const closeClick = inputSet.close[0];
  const organizerClicks = inputSet.organizer;
  const returnClicks = inputSet.return;
  const detached = transcript.events.find((event) => event.kind === "observer_detached");
  if (!(result.pairs[1].responseEvent.sequence < recipeClick.sequence
      && recipeClick.sequence < result.pairs[2].requestEvent.sequence
      && result.pairs[2].responseEvent.sequence < organizerClicks[0].sequence
      && organizerClicks[0].sequence < result.pairs[3].requestEvent.sequence
      && result.pairs[3].requestEvent.sequence < result.inventoryPairs[0].requestEvent.sequence
      && result.inventoryPairs[0].responseEvent.sequence < returnClicks[0].sequence
      && returnClicks[0].sequence < result.pairs[4].requestEvent.sequence
      && result.pairs[5].responseEvent.sequence < commitClick.sequence
      && commitClick.sequence < result.pairs[6].requestEvent.sequence
      && result.pairs[8].responseEvent.sequence < organizerClicks[1].sequence
      && organizerClicks[1].sequence < result.pairs[9].requestEvent.sequence
      && result.pairs[9].requestEvent.sequence < result.inventoryPairs[1].requestEvent.sequence
      && result.inventoryPairs[1].responseEvent.sequence < returnClicks[1].sequence
      && returnClicks[1].sequence < result.pairs[10].requestEvent.sequence
      && result.pairs[11].responseEvent.sequence < closeClick.sequence
      && closeClick.sequence < result.close.event.sequence
      && result.close.event.sequence < result.closedState.sequence
      && detached && result.closedState.sequence < detached.sequence)) {
    fail("trusted_input_order_invalid", "control",
      "trusted recipe/commit/close inputs do not bracket the authority chain");
  }
  const beforeInventoryCount = inventoryOutputCount(result.inventoryPairs[0].response,
    identityTriple(commit.crafted, "inventory.before"), "inventory.before");
  const afterInventoryCount = inventoryOutputCount(result.inventoryPairs[1].response,
    identityTriple(commit.crafted, "inventory.after"), "inventory.after");
  const expectedOutputDelta = Number(commit.crafted.quantity);
  if (!Number.isFinite(expectedOutputDelta) || expectedOutputDelta < 1
      || afterInventoryCount - beforeInventoryCount !== expectedOutputDelta) {
    fail("inventory_output_delta_mismatch", "postcondition",
      "full Inventory readback does not prove the exact crafted output quantity", {
        beforeInventoryCount, afterInventoryCount, expectedOutputDelta,
      });
  }
  const inventoryTransition = verifyInventoryTransition(
    result.inventoryPairs[0].response, result.inventoryPairs[1].response,
    acceptedPreview, commit);
  return { owner: result.open.owner, category: result.open.category, selector,
    identity: identityTriple(selectedPreview.output, "first"), initialSnapshot,
    selectedPreview: acceptedPreview, commit, freshSnapshot: finalSnapshot,
    freshPreview: finalPreview,
    inventory: { beforeCount: beforeInventoryCount, afterCount: afterInventoryCount,
      expectedOutputDelta, sessionNonce: result.inventoryPairs[0].response.sessionNonce,
      delivery: inventoryTransition.delivery,
      afterDurable: inventoryTransition.afterDurable, pairs: result.inventoryPairs },
    materialDelta: materialDelta(acceptedPreview.materials, finalPreview.materials,
      selector.craftCount), pairs: result.pairs,
    allPairs, close: result.close,
    trustedInputs: { recipe: recipeClick, organizer: organizerClicks,
      return: returnClicks, commit: commitClick, close: closeClick } };
}

function verifyRestartTranscript(transcript, first) {
  const result = collectPairs(transcript, "restart");
  if (canonical(commands(result.pairs)) !== canonical(RESTART_COMMANDS)
      || result.pairs.some((entry) => entry.request.cmd === "commit")) {
    fail("restart_command_order_invalid", "restart",
      "restart must be snapshot, auto preview, selected preview with no write");
  }
  const allPairs = orderedPairs(result.pairs, result.inventoryPairs);
  const expectedRequestOrder = [
    "crafting:snapshot", "crafting:preview", "crafting:preview",
    "crafting:snapshot", "inventory:snapshot",
    "crafting:snapshot", "crafting:preview",
  ];
  if (canonical(requestSignatures(allPairs)) !== canonical(expectedRequestOrder)) {
    fail("cross_domain_request_order_invalid", "restart",
      "restart Crafting/Inventory request boundary order is not exact", {
        actual: requestSignatures(allPairs), expected: expectedRequestOrder,
      });
  }
  const restartNonce = result.inventoryPairs[0].response.sessionNonce;
  if (restartNonce === first.inventory.sessionNonce) {
    fail("inventory_restart_nonce_reused", "restart",
      "fresh authenticated restart reused the first Inventory sessionNonce");
  }
  if (result.open.owner === first.owner) {
    fail("restart_owner_reused", "restart", "fresh process reused the first panel owner");
  }
  const snapshot = result.pairs[0].response;
  const selected = result.pairs[5].response;
  if (selected.category !== first.selector.category
      || selected.recipeIndex !== first.selector.recipeIndex
      || selected.craftCount !== first.selector.craftCount
      || !sameTriple(selected.output, first.identity)
      || !sameTriple(recipeFromSnapshot(snapshot, selected.recipeIndex, "restart").output, first.identity)
      || canonical(selected.balance) !== canonical(first.freshPreview.balance)
      || canonical(selected.materials.map((entry) => ({
        identity: identityTriple(entry, "restart"), required: entry.required, owned: entry.owned,
        consumed: entry.consumed, isQuantity: entry.isQuantity, itemKind: entry.itemKind,
      }))) !== canonical(first.freshPreview.materials.map((entry) => ({
        identity: identityTriple(entry, "restart"), required: entry.required, owned: entry.owned,
        consumed: entry.consumed, isQuantity: entry.isQuantity, itemKind: entry.itemKind,
      })))) {
    fail("restart_readback_mismatch", "restart",
      "same clone fresh readback differs from the verified post-commit projection");
  }
  const inputSet = exactTrustedInputGrammar(transcript, first.selector.recipeIndex,
    ["recipe", "organizer", "return", "close"], "restart");
  const recipeClick = inputSet.recipe[0];
  const closeClick = inputSet.close[0];
  const organizerClick = inputSet.organizer[0];
  const returnClick = inputSet.return[0];
  const detached = transcript.events.find((event) => event.kind === "observer_detached");
  if (!(result.pairs[1].responseEvent.sequence < recipeClick.sequence
      && recipeClick.sequence < result.pairs[2].requestEvent.sequence
      && result.pairs[2].responseEvent.sequence < organizerClick.sequence
      && organizerClick.sequence < result.pairs[3].requestEvent.sequence
      && result.pairs[3].requestEvent.sequence < result.inventoryPairs[0].requestEvent.sequence
      && result.inventoryPairs[0].responseEvent.sequence < returnClick.sequence
      && returnClick.sequence < result.pairs[4].requestEvent.sequence
      && result.pairs[5].responseEvent.sequence < closeClick.sequence
      && closeClick.sequence < result.close.event.sequence
      && result.close.event.sequence < result.closedState.sequence
      && detached && result.closedState.sequence < detached.sequence)) {
    fail("restart_input_order_invalid", "control",
      "restart readback input order is not exact");
  }
  const restartCount = inventoryOutputCount(result.inventoryPairs[0].response,
    first.identity, "inventory.restart");
  if (restartCount !== first.inventory.afterCount) {
    fail("inventory_restart_count_mismatch", "restart",
      "same-clone restart Inventory count differs from committed poststate");
  }
  const restartDurable = verifyRestartInventory(result.inventoryPairs[0].response,
    first.inventory);
  return { owner: result.open.owner, category: result.open.category,
    snapshot, selectedPreview: selected, inventory: { count: restartCount,
      sessionNonce: restartNonce,
      durable: restartDurable, pairs: result.inventoryPairs }, pairs: result.pairs,
    allPairs, close: result.close,
    trustedInputs: { recipe: recipeClick, organizer: [organizerClick],
      return: [returnClick], close: closeClick } };
}

module.exports = {
  CATEGORY_SET, FIRST_COMMANDS, INVENTORY_FIRST, INVENTORY_RESTART, RESTART_COMMANDS,
  collectPairs, exactKeys, identityTriple, inventoryOutputCount,
  parseMessage, planInventoryTransition, sameTriple, verifyFirstTranscript,
  verifyPreCommitAuthority, verifyRestartTranscript,
};
