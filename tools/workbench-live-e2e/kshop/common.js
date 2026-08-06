"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const SharedEvidence = require("../lib/evidence-artifact");

const TOOL_SCHEMA = "workbench-live-e2e.kshop.bundle.v2";
const RECEIPT_SCHEMA = "workbench-live-e2e.kshop.receipt.v2";
const EVENT_SCHEMA = "workbench-live-e2e.kshop.passive-event.v2";
const CONTROL_SCHEMA = "workbench-live-e2e.kshop.control.v1";
const ACK_SCHEMA = "workbench-live-e2e.kshop.control-ack.v4";
const PROVIDER_RECEIPT_SCHEMA = "workbench-live-e2e.kshop.provider-operation-receipt.v4";
const PROVIDER_EVENT_SCHEMA = "workbench-live-e2e.kshop.provider-operation-event.v1";
const SLOT_RE = /^cf7_agent_[A-Za-z0-9_-]+$/;
const LIVE_SLOT_RE = /^crazyflasher7_saves\d*$/;
const OPAQUE_ID_RE = /^[A-Za-z0-9._~-]{1,160}$/;
const SHA256_RE = /^[A-Fa-f0-9]{64}$/;
const TOKEN_REF_RE = /^sha256:[a-f0-9]{64}$/;
const SELECTION_SCHEMA = "workbench-live-e2e.kshop.selection.v2";
const DELIVERY_CONTRACT_SCHEMA = "workbench-live-e2e.kshop.item-delivery.v1";
const BUSINESS_COMMANDS = new Set([
  "bulkQuery",
  "saveCart",
  "checkoutPreview",
  "checkoutCommit",
]);
const INVENTORY_COMMANDS = new Set(["snapshot"]);
const TOKEN_KEYS = new Set([
  "expectedTuningToken",
  "tuningToken",
  "checkoutToken",
  "expectedCheckoutToken",
  "expectedPurchasedToken",
  "purchasedToken",
  "expectedCraftToken",
  "craftToken",
  "expectedBatchToken",
  "batchToken",
  "expectedTradeToken",
  "tradeToken",
  "expectedLearnToken",
  "learnToken",
  "expectedLease",
  "slotLease",
  "closeLease",
  "transactionId",
]);

class KShopToolError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "KShopToolError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
  }
}

function fail(code, phase, message, details) {
  throw new KShopToolError(code, phase, message, details);
}

function isPlainObject(value) {
  return SharedEvidence.isPlainObject(value);
}

function deepClone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function stableValue(value) {
  return SharedEvidence.stableValue(value);
}

function canonicalJson(value) {
  return SharedEvidence.canonicalJson(value);
}

function sha256Bytes(value) {
  return SharedEvidence.sha256Bytes(value);
}

function sha256Text(value) {
  return SharedEvidence.sha256Text(value);
}

function sha256File(filePath) {
  return SharedEvidence.sha256File(filePath);
}

function tokenRef(value) {
  return "sha256:" + sha256Text(String(value));
}

function classifyCatalogDelivery(entry) {
  if (!isPlainObject(entry) || typeof entry.majorType !== "string"
      || typeof entry.subType !== "string") {
    fail("catalog_delivery_classification_invalid", "selection",
      "authoritative catalog entry lacks the AS2 type/use projection required by ItemUtil");
  }
  const majorType = entry.majorType;
  const subType = entry.subType;
  // This precedence is the production ItemUtil.require/loadItemData contract:
  // equipment type wins, then material use, then information use, and every
  // remaining mergeable may route to an existing drug slot before the backpack.
  if (majorType === "武器" || majorType === "防具") {
    return {
      schema: DELIVERY_CONTRACT_SCHEMA,
      classifier: "ItemUtil.type-use-precedence.v1",
      classification: "equipment",
      authorityItemKind: "equipment",
      destination: "backpack_first_vacancy",
      destinationSurface: "inventory.physical.背包",
      stateDependent: false,
      verifierPoststate: "complete_50_slot_backpack_physical_delta",
      executableJourneyEligible: true,
    };
  }
  if (subType === "材料") {
    return {
      schema: DELIVERY_CONTRACT_SCHEMA,
      classifier: "ItemUtil.type-use-precedence.v1",
      classification: "material",
      authorityItemKind: "stack",
      destination: "collection_material_add_or_addValue",
      destinationSurface: "collection.材料",
      stateDependent: false,
      verifierPoststate: "not_observed_by_physical_inventory_snapshot",
      executableJourneyEligible: false,
    };
  }
  if (subType === "情报") {
    return {
      schema: DELIVERY_CONTRACT_SCHEMA,
      classifier: "ItemUtil.type-use-precedence.v1",
      classification: "information",
      authorityItemKind: "information",
      destination: "collection_information_add_or_addValue",
      destinationSurface: "collection.情报",
      stateDependent: false,
      verifierPoststate: "not_observed_by_physical_inventory_snapshot",
      executableJourneyEligible: false,
    };
  }
  return {
    schema: DELIVERY_CONTRACT_SCHEMA,
    classifier: "ItemUtil.type-use-precedence.v1",
    classification: "mergeable",
    authorityItemKind: "stack",
    destination: "existing_drug_slot_else_backpack_same_stack_else_first_vacancy",
    destinationSurface: "inventory.药剂栏_or_背包",
    stateDependent: true,
    verifierPoststate: "drug_surface_not_observed_by_physical_inventory_snapshot",
    executableJourneyEligible: false,
  };
}

function catalogSelectionCandidate(entry, balance, playerLevel, reverseLevel) {
  if (!isPlainObject(entry)
      || !Number.isInteger(Number(entry.idx)) || Number(entry.idx) < 0
      || typeof entry.item !== "string" || !entry.item.trim()
      || typeof entry.type !== "string" || !entry.type.trim() || entry.type === "非卖品"
      || typeof entry.displayname !== "string" || !entry.displayname.trim()
      || typeof entry.icon !== "string" || !entry.icon.trim()
      || typeof entry.majorType !== "string" || !entry.majorType.trim()
      || typeof entry.subType !== "string" || !entry.subType.trim()
      || !Number.isInteger(Number(entry.price)) || Number(entry.price) <= 0
      || !Number.isInteger(Number(entry.level)) || Number(entry.level) < 0
      || Number(entry.level) > Number(playerLevel) + Number(reverseLevel)
      || !Number.isInteger(Number(entry.maxQuantity)) || Number(entry.maxQuantity) < 1) {
    return null;
  }
  const deliveryContract = classifyCatalogDelivery(entry);
  if (deliveryContract.executableJourneyEligible !== true) return null;
  const affordable = Math.floor(Number(balance) / Number(entry.price));
  if (!Number.isInteger(affordable) || affordable < 1) return null;
  // A3 deliberately buys one unit.  The value is still derived from and bounded by
  // the authoritative catalog and balance so a stale fixed quantity cannot pass.
  const quantity = Math.min(1, Number(entry.maxQuantity), affordable);
  const selected = {
    schema: SELECTION_SCHEMA,
    strategy: "lowest-price-proven-backpack-equipment-then-catalog-index",
    catalogIndex: Number(entry.idx),
    itemName: entry.item,
    displayName: entry.displayname,
    icon: entry.icon,
    shopType: entry.type,
    catalogMajorType: entry.majorType,
    catalogSubType: entry.subType,
    deliveryContract,
    unitPrice: Number(entry.price),
    quantity,
    maxQuantity: Number(entry.maxQuantity),
    requiredLevel: Number(entry.level),
    playerLevel: Number(playerLevel),
    reverseLevel: Number(reverseLevel),
    balance: Number(balance),
  };
  selected.cart = [{ idx: selected.catalogIndex, qty: selected.quantity }];
  selected.total = selected.unitPrice * selected.quantity;
  selected.catalogEntrySha256 = sha256Text(canonicalJson({
    idx: Number(entry.idx),
    item: entry.item,
    type: entry.type,
    displayname: entry.displayname,
    icon: entry.icon,
    majorType: entry.majorType,
    subType: entry.subType,
    price: Number(entry.price),
    level: Number(entry.level),
    maxQuantity: Number(entry.maxQuantity),
  }));
  return selected;
}

function chooseCatalogSelection(catalog, balance, playerLevel, reverseLevel) {
  if (!Array.isArray(catalog) || !Number.isInteger(Number(balance)) || Number(balance) < 0
      || !Number.isInteger(Number(playerLevel)) || Number(playerLevel) < 0
      || !Number.isInteger(Number(reverseLevel)) || Number(reverseLevel) < 0) {
    fail("catalog_selection_input_invalid", "selection",
      "authoritative catalog/balance is unavailable for dynamic selection");
  }
  const candidates = catalog.map((entry) => catalogSelectionCandidate(
    entry, balance, playerLevel, reverseLevel))
    .filter(Boolean)
    .sort((left, right) => left.unitPrice - right.unitPrice
      || left.catalogIndex - right.catalogIndex
      || left.itemName.localeCompare(right.itemName));
  if (candidates.length < 1) {
    fail("catalog_selection_unavailable", "selection",
      "catalog contains no affordable item with a stateless AS2 backpack destination proven by the 50-slot poststate contract");
  }
  return candidates[0];
}

function verifyCatalogSelection(selection, catalog, balance, playerLevel, reverseLevel) {
  if (!isPlainObject(selection) || selection.schema !== SELECTION_SCHEMA
      || selection.strategy !== "lowest-price-proven-backpack-equipment-then-catalog-index") {
    fail("catalog_selection_invalid", "selection", "dynamic KShop selection is malformed");
  }
  const expected = chooseCatalogSelection(catalog, balance, playerLevel, reverseLevel);
  if (canonicalJson(selection) !== canonicalJson(expected)) {
    fail("catalog_selection_mismatch", "selection",
      "recorded selection is not the deterministic authoritative catalog choice", {
        expected,
        actual: selection,
      });
  }
  return expected;
}

function artifactDigest(kind, locator, value) {
  const bytes = Buffer.from(canonicalJson(value), "utf8");
  return { kind, locator, sha256: sha256Bytes(bytes), bytes: bytes.length };
}

function buildRawBundleManifest(bundle) {
  if (!isPlainObject(bundle) || Object.prototype.hasOwnProperty.call(bundle, "rawBundleManifest")) {
    fail("raw_bundle_input_invalid", "bundle_manifest",
      "raw bundle manifest must be built once before it is attached");
  }
  const embedded = [];
  embedded.push(artifactDigest("transcript", "bundle:transcript", bundle.transcript));
  embedded.push(artifactDigest("host_log", "bundle:hostLog", bundle.hostLog));
  embedded.push(artifactDigest("control", "bundle:control",
    { requests: bundle.controlRequests, acks: bundle.controlAcks,
      providerReceipts: bundle.controlProviderReceipts,
      captures: bundle.controlCaptures, bindings: bundle.controlBindings }));
  embedded.push(artifactDigest("clone_lifecycle", "bundle:cloneLifecycle", bundle.cloneLifecycle));
  embedded.push(artifactDigest("runtime", "bundle:runtime", bundle.runtime));
  embedded.push(artifactDigest("production_closure", "bundle:productionClosure",
    { closure: bundle.productionClosure, binding: bundle.productionBinding }));
  embedded.push(artifactDigest("module_admission", "bundle:moduleAdmission", bundle.moduleAdmission));
  embedded.sort((left, right) => left.locator.localeCompare(right.locator));
  const payloadText = canonicalJson(bundle);
  const manifest = { schema: "workbench-live-e2e.kshop.raw-bundle-manifest.v1",
    createdAt: new Date().toISOString(), bundleSchema: bundle.schema,
    bundlePayloadSha256: sha256Text(payloadText), bundlePayloadBytes: Buffer.byteLength(payloadText, "utf8"),
    embedded };
  manifest.manifestSha256 = sha256Text(canonicalJson(manifest));
  return manifest;
}

function verifyRawBundleManifest(bundle) {
  const manifest = bundle && bundle.rawBundleManifest;
  if (!isPlainObject(manifest)
      || manifest.schema !== "workbench-live-e2e.kshop.raw-bundle-manifest.v1"
      || manifest.bundleSchema !== TOOL_SCHEMA || !Number.isFinite(Date.parse(manifest.createdAt))
      || !SHA256_RE.test(String(manifest.bundlePayloadSha256 || ""))
      || !Number.isInteger(manifest.bundlePayloadBytes) || manifest.bundlePayloadBytes < 1
      || !SHA256_RE.test(String(manifest.manifestSha256 || ""))
      || !Array.isArray(manifest.embedded)) {
    fail("raw_bundle_manifest_invalid", "bundle_manifest", "raw bundle manifest is malformed");
  }
  const payload = Object.assign({}, bundle);
  delete payload.rawBundleManifest;
  const expected = buildRawBundleManifest(payload);
  const comparableExpected = Object.assign({}, expected, { createdAt: manifest.createdAt });
  delete comparableExpected.manifestSha256;
  comparableExpected.manifestSha256 = sha256Text(canonicalJson(comparableExpected));
  if (canonicalJson(comparableExpected) !== canonicalJson(manifest)) {
    fail("raw_bundle_manifest_mismatch", "bundle_manifest",
      "raw bundle manifest does not bind the complete captured payload");
  }
  return manifest;
}

function redactOpaqueTokens(value, keyHint) {
  if (Array.isArray(value)) {
    return value.map((entry) => redactOpaqueTokens(entry, null));
  }
  if (!isPlainObject(value)) {
    if (TOKEN_KEYS.has(String(keyHint || "")) && typeof value === "string") {
      return TOKEN_REF_RE.test(value) ? value : tokenRef(value);
    }
    return value;
  }
  const output = {};
  Object.keys(value).forEach((key) => {
    output[key] = redactOpaqueTokens(value[key], key);
  });
  return output;
}

function redactLogLine(line) {
  return String(line || "").replace(
    /(\"(?:expectedTuningToken|tuningToken|checkoutToken|expectedCheckoutToken|expectedPurchasedToken|purchasedToken|expectedCraftToken|craftToken|expectedBatchToken|batchToken|expectedTradeToken|tradeToken|expectedLearnToken|learnToken|expectedLease|slotLease|closeLease|transactionId)\"\s*:\s*\")([^\"]*)(\")/g,
    (_match, prefix, value, suffix) => prefix + tokenRef(value) + suffix
  );
}

function assertNoRawTokens(value, pathLabel) {
  const label = pathLabel || "$";
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertNoRawTokens(entry, label + "[" + index + "]"));
    return true;
  }
  if (!isPlainObject(value)) {
    if (typeof value === "string") {
      const pattern = /"(?:expectedTuningToken|tuningToken|checkoutToken|expectedCheckoutToken|expectedPurchasedToken|purchasedToken|expectedCraftToken|craftToken|expectedBatchToken|batchToken|expectedTradeToken|tradeToken|expectedLearnToken|learnToken|expectedLease|slotLease|closeLease|transactionId)"\s*:\s*"([^"]*)"/g;
      let match;
      while ((match = pattern.exec(value)) !== null) {
        if (!TOKEN_REF_RE.test(match[1])) {
          fail("raw_token_in_public_evidence", "token_hygiene", label + " embeds a raw token");
        }
      }
    }
    return true;
  }
  Object.keys(value).forEach((key) => {
    const child = value[key];
    const childPath = label + "." + key;
    if (TOKEN_KEYS.has(key) && child !== null && child !== undefined) {
      if (typeof child !== "string" || !TOKEN_REF_RE.test(child)) {
        fail("raw_token_in_public_evidence", "token_hygiene", childPath + " is not a token hash");
      }
    }
    assertNoRawTokens(child, childPath);
  });
  return true;
}

function nextEvent(previousHash, sequence, rawEvent) {
  const event = Object.assign({}, redactOpaqueTokens(rawEvent), {
    schema: EVENT_SCHEMA,
    sequence,
    prevHash: previousHash || "0".repeat(64),
  });
  delete event.eventHash;
  event.eventHash = sha256Text(event.prevHash + "\n" + canonicalJson(event));
  return event;
}

function sealEvents(rawEvents) {
  let previous = "0".repeat(64);
  const events = (rawEvents || []).map((raw, index) => {
    const event = nextEvent(previous, index + 1, raw);
    previous = event.eventHash;
    return event;
  });
  return {
    events,
    chainHead: previous,
    eventCount: events.length,
  };
}

function verifyEventChain(transcript) {
  if (!isPlainObject(transcript) || !Array.isArray(transcript.events)) {
    fail("transcript_missing", "transcript", "passive transcript is missing");
  }
  let previous = "0".repeat(64);
  transcript.events.forEach((observed, index) => {
    if (!isPlainObject(observed)
        || observed.schema !== EVENT_SCHEMA
        || observed.sequence !== index + 1
        || observed.prevHash !== previous
        || !SHA256_RE.test(String(observed.eventHash || ""))) {
      fail("transcript_chain_invalid", "transcript", "event chain metadata is invalid", {
        index,
      });
    }
    const copy = deepClone(observed);
    delete copy.eventHash;
    const expected = sha256Text(previous + "\n" + canonicalJson(copy));
    if (observed.eventHash !== expected) {
      fail("transcript_chain_invalid", "transcript", "event hash does not match", {
        index,
      });
    }
    previous = observed.eventHash;
  });
  if (transcript.eventCount !== transcript.events.length
      || transcript.chainHead !== previous) {
    fail("transcript_chain_invalid", "transcript", "transcript head/count does not match");
  }
  return true;
}

function assertSafeSlot(slot) {
  if (!SLOT_RE.test(String(slot || "")) || LIVE_SLOT_RE.test(String(slot || ""))) {
    fail(
      "unsafe_target_slot",
      "arguments",
      "target slot must be a dedicated cf7_agent_* slot"
    );
  }
  return String(slot);
}

function assertSafeSeed(seedSlot, targetSlot) {
  if (!/^[A-Za-z0-9_-]+$/.test(String(seedSlot || "")) || seedSlot === targetSlot) {
    fail("unsafe_seed_slot", "arguments", "seed slot is missing, malformed, or equals target");
  }
  return String(seedSlot);
}

function pathInside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function assertDirectoryInside(parent, candidate, phase) {
  if (!pathInside(parent, candidate)) {
    fail("path_escape", phase || "filesystem", "path escaped the owned directory", {
      parent,
      candidate,
    });
  }
  return path.resolve(candidate);
}

function atomicWriteJson(filePath, value) {
  const parent = path.dirname(filePath);
  fs.mkdirSync(parent, { recursive: true });
  const temporary = filePath + ".tmp-" + process.pid + "-" + crypto.randomBytes(6).toString("hex");
  let created = false;
  try {
    fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + "\n", {
      encoding: "utf8",
      mode: 0o600,
      flag: "wx",
    });
    created = true;
    if (fs.existsSync(filePath)) {
      const existing = fs.lstatSync(filePath);
      if (!existing.isFile() || existing.isSymbolicLink()) {
        fail("atomic_target_invalid", "filesystem", "atomic JSON target is not a regular file", {
          filePath,
        });
      }
      fs.unlinkSync(filePath);
    }
    fs.renameSync(temporary, filePath);
    created = false;
  } finally {
    if (created) {
      try { fs.unlinkSync(temporary); } catch (_error) { /* owned temporary cleanup */ }
    }
  }
}

function readJson(filePath, label) {
  let stat;
  try { stat = fs.lstatSync(filePath); } catch (error) {
    fail("json_missing", "filesystem", (label || "JSON") + " is missing", {
      filePath,
      error: error.message,
    });
  }
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size <= 0 || stat.size > 32 * 1024 * 1024) {
    fail("json_file_invalid", "filesystem", (label || "JSON") + " is not a safe regular file");
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail("json_invalid", "filesystem", (label || "JSON") + " is invalid: " + error.message);
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function timestampId() {
  return new Date().toISOString().replace(/[-:.]/g, "");
}

module.exports = {
  ACK_SCHEMA,
  BUSINESS_COMMANDS,
  CONTROL_SCHEMA,
  DELIVERY_CONTRACT_SCHEMA,
  EVENT_SCHEMA,
  INVENTORY_COMMANDS,
  KShopToolError,
  LIVE_SLOT_RE,
  OPAQUE_ID_RE,
  PROVIDER_RECEIPT_SCHEMA,
  PROVIDER_EVENT_SCHEMA,
  RECEIPT_SCHEMA,
  SELECTION_SCHEMA,
  SHA256_RE,
  SLOT_RE,
  TOKEN_KEYS,
  TOKEN_REF_RE,
  TOOL_SCHEMA,
  assertDirectoryInside,
  assertNoRawTokens,
  assertSafeSeed,
  assertSafeSlot,
  atomicWriteJson,
  buildRawBundleManifest,
  classifyCatalogDelivery,
  chooseCatalogSelection,
  canonicalJson,
  deepClone,
  fail,
  isPlainObject,
  nextEvent,
  pathInside,
  readJson,
  redactLogLine,
  redactOpaqueTokens,
  sealEvents,
  sha256Bytes,
  sha256File,
  sha256Text,
  sleep,
  stableValue,
  timestampId,
  tokenRef,
  verifyCatalogSelection,
  verifyEventChain,
  verifyRawBundleManifest,
};
