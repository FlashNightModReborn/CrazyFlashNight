"use strict";

const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const CloneGuard = require("../lib/clone-save-guard");
const NpcProduction = require("../npc/production-closure");
const Common = require("./common");

const APPLICABILITY_SCHEMA = "workbench-live-e2e.material-shop.current-data-applicability.v1";
const FIXTURE_AUTHORITY_BINDING_SCHEMA =
  "workbench-live-e2e.material-shop.fixture-authority-binding.v1";
const MATERIAL_CATALOG = "data/dictionaries/material_catalog.xml";
const PURCHASE_AUTHORITY = "scripts/逻辑系统分区/商店系统_兼容.as";
const HOST_AUTHORITY = "launcher/src/Tasks/NpcShopTask.cs";
const SEED_AUDIT_SLOTS = Object.freeze([
  "cf7_agent_arena_calibration",
  "cf7_agent_character_build_b4",
  "cf7_agent_character_build_final",
  "cf7_agent_equipment_tuning",
]);

function xmlDecode(value) {
  return String(value || "").replace(/&(?:#(\d+)|#x([0-9a-f]+)|amp|lt|gt|quot|apos);/gi,
    (match, decimal, hexadecimal) => {
      if (decimal) return String.fromCodePoint(Number(decimal));
      if (hexadecimal) return String.fromCodePoint(parseInt(hexadecimal, 16));
      return { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&apos;": "'" }[match.toLowerCase()];
    });
}

function exactFile(root, relativePath, maximumBytes) {
  const resolved = Common.resolveWithin(root, relativePath, "applicability");
  const file = Evidence.readExactRegularFile(resolved.absolute, {
    phase: "applicability", maximumBytes: maximumBytes || 64 * 1024 * 1024,
  });
  return { relativePath: resolved.relative, bytes: file.bytes, sha256: file.sha256,
    length: file.length };
}

function parseMaterialNames(bytes) {
  const text = bytes.toString("utf8").replace(/^\uFEFF/, "");
  const names = [];
  const blocks = text.match(/<Material\b[\s\S]*?<\/Material>/g) || [];
  blocks.forEach((block) => {
    const match = /<Name>([\s\S]*?)<\/Name>/.exec(block);
    const name = match && xmlDecode(match[1].trim());
    if (!name || name.length > 128 || /[\u0000-\u001f\u007f]/.test(name)) {
      Common.fail("material_shop_catalog_name_invalid", "applicability",
        "material catalog contains an invalid material name");
    }
    names.push(name);
  });
  if (!names.length || new Set(names).size !== names.length) {
    Common.fail("material_shop_catalog_inventory_invalid", "applicability",
      "material catalog must contain a non-empty unique authored inventory");
  }
  return names;
}

function parseShop(relativePath, bytes) {
  let value;
  try { value = JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_shop_json_invalid", "applicability", error.message,
      { relativePath });
  }
  if (!Evidence.isPlainObject(value) || value.schema !== "npc-shop.v2"
      || typeof value.shopId !== "string" || !value.shopId
      || !Evidence.isPlainObject(value.catalog)) {
    Common.fail("material_shop_shop_contract_invalid", "applicability",
      "NPC shop is not one npc-shop.v2 catalog", { relativePath });
  }
  const entries = [];
  Object.keys(value.catalog).forEach((key) => {
    if (!/^(?:0|[1-9]\d{0,4})$/.test(key)) {
      Common.fail("material_shop_catalog_index_invalid", "applicability",
        "shop catalog index is outside the frozen integer domain", { relativePath, key });
    }
    const catalogIndex = Number(key);
    if (catalogIndex > 10000) {
      Common.fail("material_shop_catalog_index_invalid", "applicability",
        "shop catalog index exceeds ShopCatalogIndex", { relativePath, key });
    }
    const raw = value.catalog[key];
    const itemName = typeof raw === "string" ? raw
      : Evidence.isPlainObject(raw) && typeof raw.name === "string" ? raw.name : "";
    if (!itemName || itemName.length > 128) {
      Common.fail("material_shop_catalog_item_invalid", "applicability",
        "shop catalog entry lacks an exact item name", { relativePath, key });
    }
    entries.push({ shopFile: relativePath, shopId: value.shopId, catalogIndex, itemName,
      requiredInfo: typeof raw === "string" || raw.requiredInfo == null
        ? "" : String(raw.requiredInfo),
      purchaseLimit: typeof raw === "string" || raw.purchaseLimit == null
        ? null : Number(raw.purchaseLimit) });
  });
  return entries.sort((left, right) => left.catalogIndex - right.catalogIndex);
}

function parseItemPrices(relativePath, bytes, prices) {
  const text = bytes.toString("utf8").replace(/^\uFEFF/, "");
  const blocks = text.match(/<item\b[\s\S]*?<\/item>/gi) || [];
  blocks.forEach((block) => {
    const nameMatch = /<name>([\s\S]*?)<\/name>/i.exec(block);
    const priceMatch = /<price>([\s\S]*?)<\/price>/i.exec(block);
    if (!nameMatch || !priceMatch) return;
    const name = xmlDecode(nameMatch[1].trim());
    const priceText = xmlDecode(priceMatch[1].trim());
    const price = Number(priceText);
    if (!name || !Number.isFinite(price)) return;
    if (prices.has(name) && prices.get(name) !== price) {
      Common.fail("material_shop_item_price_conflict", "applicability",
        "duplicate item definitions disagree on base price", { relativePath, name });
    }
    prices.set(name, price);
  });
}

function materialOwnedFromSave(save, itemName) {
  const materials = save && save.collection && save.collection["材料"];
  const raw = materials && Object.prototype.hasOwnProperty.call(materials, itemName)
    ? materials[itemName] : 0;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0 || Math.floor(value) !== value) {
    Common.fail("material_shop_seed_owned_invalid", "applicability",
      "source fixture material quantity is not a non-negative integer", { itemName, raw });
  }
  return value;
}

function captureSourceFixture(root, appData, target) {
  const set = CloneGuard.captureSlotArtifactSet({ root, appData,
    slot: Common.SOURCE_FIXTURE_SLOT, requireJson: true });
  const jsonArtifact = set.artifacts.find((entry) => entry.kind === "json");
  const solArtifacts = set.artifacts.filter((entry) => entry.kind === "sol");
  if (!jsonArtifact || solArtifacts.length < 1) {
    Common.fail("material_shop_source_fixture_incomplete", "applicability",
      "source fixture must bind one JSON and a non-empty complete owned SOL set");
  }
  const jsonFile = exactFile(root, "saves/" + Common.SOURCE_FIXTURE_SLOT + ".json",
    128 * 1024 * 1024);
  let save;
  try { save = JSON.parse(jsonFile.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_source_fixture_json_invalid", "applicability", error.message);
  }
  const money = Number(save && save["0"] && save["0"][2]);
  const owned = materialOwnedFromSave(save, target.itemName);
  if (!Number.isFinite(money) || money < 0 || Math.floor(money) !== money
      || money < target.basePrice || owned !== 0) {
    Common.fail("material_shop_unlocked_target_fixture_invalid", "applicability",
      "source fixture does not prove the frozen quantity-one target", {
        money, owned, basePrice: target.basePrice,
      });
  }
  return {
    sourceFixtureSlot: Common.SOURCE_FIXTURE_SLOT,
    artifactSetSha256: set.setSha256,
    artifacts: set.artifacts.map((entry) => ({ kind: entry.kind, locator: entry.locator,
      sha256: entry.sha256, bytes: entry.bytes })),
    money,
    targetOwned: owned,
  };
}

function captureSeedAudit(root, appData, slot, occurrences, target) {
  if (!SEED_AUDIT_SLOTS.includes(slot)) {
    Common.fail("material_shop_seed_audit_slot_invalid", "applicability",
      "seed audit attempted a foreign fixture slot", { slot });
  }
  const set = CloneGuard.captureSlotArtifactSet({ root, appData, slot, requireJson: true });
  const jsonArtifact = set.artifacts.find((entry) => entry.kind === "json");
  const solArtifacts = set.artifacts.filter((entry) => entry.kind === "sol");
  if (!jsonArtifact || solArtifacts.length < 1) {
    Common.fail("material_shop_seed_audit_incomplete", "applicability",
      "each audited fixture must bind one JSON and a non-empty complete owned SOL set", { slot });
  }
  const jsonFile = exactFile(root, "saves/" + slot + ".json", 128 * 1024 * 1024);
  let save;
  try { save = JSON.parse(jsonFile.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_seed_audit_json_invalid", "applicability", error.message); }
  const money = Number(save && save["0"] && save["0"][2]);
  if (!Number.isInteger(money) || money < 0) {
    Common.fail("material_shop_seed_money_invalid", "applicability",
      "audited seed money is not a non-negative integer", { slot, money });
  }
  const owned = occurrences.map((entry) => materialOwnedFromSave(save, entry.itemName));
  return {
    slot,
    artifactSetSha256: set.setSha256,
    artifacts: set.artifacts.map((entry) => ({ kind: entry.kind, locator: entry.locator,
      sha256: entry.sha256, bytes: entry.bytes })),
    money,
    targetOwned: materialOwnedFromSave(save, target.itemName),
    affordableOccurrenceCount: occurrences.filter((entry) => money >= entry.basePrice).length,
    atDefaultLimitOccurrenceCount: owned.filter((entry) => entry >= 999999).length,
    maxOwned: Math.max(0, ...owned),
  };
}

function assertAuthority(as2File, hostFile) {
  const as2 = as2File.bytes.toString("utf8").replace(/^\uFEFF/, "");
  const host = hostFile.bytes.toString("utf8").replace(/^\uFEFF/, "");
  const anchors = [
    { id: "material_default_limit_999999",
      pattern: /var technicalLimit:Number = equipment \? Math\.floor\(bagCapacity\) : 999999;/ },
    { id: "configured_purchase_limit",
      pattern: /raw\.purchaseLimit != undefined[\s\S]{0,400}technicalLimit = Math\.min\(technicalLimit, configured\);/ },
    { id: "material_capacity_skip",
      pattern: /ItemUtil\.isMaterial\(name\)[\s\S]{0,160}resolvePurchaseDestination\(name\) == "quickslot"\) continue;/ },
  ];
  anchors.forEach((anchor) => {
    if (!anchor.pattern.test(as2)) {
      Common.fail("material_shop_purchase_authority_drift", "applicability",
        "AS2 material purchase-limit authority anchor drifted", { anchorId: anchor.id });
    }
  });
  if (!/MaxPurchaseQuantity\s*=\s*999999/.test(host)) {
    Common.fail("material_shop_host_limit_authority_drift", "applicability",
      "Host ShopCatalogIndex/purchase limit authority anchor drifted");
  }
  return [
    { relativePath: as2File.relativePath, sha256: as2File.sha256,
      anchorIds: anchors.map((entry) => entry.id) },
    { relativePath: hostFile.relativePath, sha256: hostFile.sha256,
      anchorIds: ["host_max_purchase_quantity_999999"] },
  ];
}

function stableApplicability(value) {
  return {
    schema: value.schema,
    materialCatalog: value.materialCatalog,
    counts: value.counts,
    unlocked: value.unlocked,
    locked: value.locked,
    max: value.max,
    occurrences: value.occurrences,
    seedAudit: value.seedAudit,
    sourceFixture: value.sourceFixture,
    selectedUnlockedTarget: value.selectedUnlockedTarget,
    authority: value.authority,
    inputsSha256: value.inputsSha256,
  };
}

function resolveApplicabilityRoots(rootValue, options) {
  const settings = options || {};
  if (settings.fixtureAuthorityRoot == null) {
    const canonicalRoot = Common.assertCanonicalRoot(rootValue);
    return { dataRoot: canonicalRoot, fixtureAuthorityRoot: canonicalRoot };
  }
  const dataRoot = Evidence.assertExactDirectory(path.resolve(rootValue), "applicability");
  const fixtureAuthorityRoot = Common.assertCanonicalRoot(settings.fixtureAuthorityRoot);
  return { dataRoot, fixtureAuthorityRoot };
}

function fixtureAuthorityProjection(applicability) {
  return {
    sourceFixture: {
      slot: applicability.sourceFixture.sourceFixtureSlot,
      artifactSetSha256: applicability.sourceFixture.artifactSetSha256,
      artifacts: applicability.sourceFixture.artifacts.map((entry) => Object.assign({}, entry)),
    },
    seedAudit: applicability.seedAudit.map((entry) => ({
      slot: entry.slot,
      artifactSetSha256: entry.artifactSetSha256,
      artifacts: entry.artifacts.map((artifact) => Object.assign({}, artifact)),
    })),
  };
}

function stableFixtureAuthorityBinding(value) {
  return {
    schema: value.schema,
    boundAt: value.boundAt,
    root: value.root,
    applicabilitySha256: value.applicabilitySha256,
    artifactProjection: value.artifactProjection,
  };
}

function createFixtureAuthorityBinding(rootValue, applicabilityValue, boundAt) {
  const applicability = validateApplicability(applicabilityValue);
  const root = Common.assertCanonicalRoot(rootValue);
  const value = {
    schema: FIXTURE_AUTHORITY_BINDING_SCHEMA,
    boundAt: boundAt || new Date().toISOString(),
    root,
    applicabilitySha256: applicability.applicabilitySha256,
    artifactProjection: fixtureAuthorityProjection(applicability),
  };
  value.bindingSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(stableFixtureAuthorityBinding(value)));
  return validateFixtureAuthorityBinding(value, applicability);
}

function validateFixtureAuthorityBinding(value, applicabilityValue) {
  const applicability = validateApplicability(applicabilityValue);
  Common.exactKeys(value, ["schema", "boundAt", "root", "applicabilitySha256",
    "artifactProjection", "bindingSha256"],
  "material_shop_fixture_authority_binding_invalid", "applicability");
  if (value.schema !== FIXTURE_AUTHORITY_BINDING_SCHEMA
      || !Number.isFinite(Date.parse(value.boundAt))
      || typeof value.root !== "string" || !path.isAbsolute(value.root)
      || value.applicabilitySha256 !== applicability.applicabilitySha256
      || Evidence.canonicalJson(value.artifactProjection)
        !== Evidence.canonicalJson(fixtureAuthorityProjection(applicability))
      || value.bindingSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableFixtureAuthorityBinding(value)))) {
    Common.fail("material_shop_fixture_authority_binding_invalid", "applicability",
      "fixture authority binding is malformed or detached from applicability evidence");
  }
  return value;
}

function replayFixtureAuthorityBinding(value, applicabilityValue, options) {
  const settings = options || {};
  const applicability = validateApplicability(applicabilityValue);
  const binding = validateFixtureAuthorityBinding(value, applicability);
  const resourcesRoot = Evidence.assertExactDirectory(path.resolve(settings.resourcesRoot || ""),
    "applicability");
  const authorityRoot = Evidence.assertExactDirectory(path.resolve(binding.root),
    "applicability");
  if (resourcesRoot.toLowerCase() === authorityRoot.toLowerCase()
      || Evidence.pathInside(resourcesRoot, authorityRoot)) {
    Common.fail("material_shop_fixture_authority_root_invalid", "applicability",
      "fixture authority must be outside the materialized production/mutation root");
  }
  const appData = Evidence.assertExactDirectory(path.resolve(settings.appData || ""),
    "applicability");
  const current = {
    sourceFixture: (() => {
      const set = CloneGuard.captureSlotArtifactSet({ root: authorityRoot, appData,
        slot: applicability.sourceFixture.sourceFixtureSlot, requireJson: true });
      return { slot: applicability.sourceFixture.sourceFixtureSlot,
        artifactSetSha256: set.setSha256,
        artifacts: set.artifacts.map((entry) => ({ kind: entry.kind,
          locator: entry.locator, sha256: entry.sha256, bytes: entry.bytes })) };
    })(),
    seedAudit: applicability.seedAudit.map((entry) => {
      const set = CloneGuard.captureSlotArtifactSet({ root: authorityRoot, appData,
        slot: entry.slot, requireJson: true });
      return { slot: entry.slot, artifactSetSha256: set.setSha256,
        artifacts: set.artifacts.map((artifact) => ({ kind: artifact.kind,
          locator: artifact.locator, sha256: artifact.sha256, bytes: artifact.bytes })) };
    }),
  };
  if (Evidence.canonicalJson(current)
      !== Evidence.canonicalJson(binding.artifactProjection)) {
    Common.fail("material_shop_fixture_authority_drift", "applicability",
      "canonical fixture JSON or owned SOL evidence drifted after outer verification");
  }
  return { root: authorityRoot, binding, artifactProjection: current };
}

function validateApplicability(value) {
  Common.exactKeys(value, ["schema", "capturedAt", "materialCatalog", "counts",
    "unlocked", "locked", "max", "occurrences", "seedAudit", "sourceFixture",
    "selectedUnlockedTarget", "authority", "inputsSha256",
    "applicabilitySha256"], "material_shop_applicability_invalid", "applicability");
  if (value.schema !== APPLICABILITY_SCHEMA || !Number.isFinite(Date.parse(value.capturedAt))
      || !Common.SHA256_RE.test(String(value.inputsSha256 || ""))
      || value.applicabilitySha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableApplicability(value)))) {
    Common.fail("material_shop_applicability_invalid", "applicability",
      "current-data applicability envelope is malformed or byte-detached");
  }
  Common.exactKeys(value.counts, ["materialCount", "shopFileCount",
    "materialOccurrenceCount", "uniqueMaterialItemCount", "requiredInfoOccurrenceCount",
    "purchaseLimitOccurrenceCount", "seedCount", "seedMaterialPairCount",
    "affordableSeedOccurrenceCount", "atDefaultLimitSeedOccurrenceCount"],
  "material_shop_applicability_counts_invalid",
  "applicability");
  Object.values(value.counts).forEach((count) => {
    if (!Number.isInteger(count) || count < 0) {
      Common.fail("material_shop_applicability_counts_invalid", "applicability",
        "applicability counts must be non-negative integers");
    }
  });
  ["unlocked", "locked", "max"].forEach((route) => {
    Common.exactKeys(value[route], ["status", "qualifyingOccurrenceCount"],
      "material_shop_route_applicability_invalid", "applicability");
    const allowed = route === "unlocked"
      ? ["required_candidate_journey"]
      : ["not_applicable_current_data", "requires_seed_probe"];
    if (!allowed.includes(value[route].status)
        || !Number.isInteger(value[route].qualifyingOccurrenceCount)
        || value[route].qualifyingOccurrenceCount < 0
        || (value[route].status === "not_applicable_current_data"
          && value[route].qualifyingOccurrenceCount !== 0)) {
      Common.fail("material_shop_route_applicability_invalid", "applicability",
        "route applicability status/count is inconsistent", { route });
    }
  });
  if (value.unlocked.qualifyingOccurrenceCount < 1
      || value.locked.qualifyingOccurrenceCount !== value.counts.requiredInfoOccurrenceCount
      || value.max.qualifyingOccurrenceCount !== value.counts.purchaseLimitOccurrenceCount) {
    Common.fail("material_shop_route_applicability_invalid", "applicability",
      "route applicability is detached from the current material occurrence inventory");
  }
  Common.exactKeys(value.selectedUnlockedTarget, ["shopId", "catalogIndex", "itemName",
    "basePrice", "owned", "quantity", "saleCount"],
  "material_shop_unlocked_target_invalid", "applicability");
  if (value.selectedUnlockedTarget.shopId !== "厨师"
      || value.selectedUnlockedTarget.catalogIndex !== 24
      || value.selectedUnlockedTarget.itemName !== "食用油"
      || value.selectedUnlockedTarget.basePrice !== 300
      || value.selectedUnlockedTarget.owned !== 0
      || value.selectedUnlockedTarget.quantity !== 1
      || value.selectedUnlockedTarget.saleCount !== 0
      || value.counts.seedCount !== SEED_AUDIT_SLOTS.length
      || value.counts.seedMaterialPairCount
        !== value.counts.seedCount * value.counts.materialOccurrenceCount
      || value.counts.affordableSeedOccurrenceCount !== value.counts.seedMaterialPairCount
      || value.counts.atDefaultLimitSeedOccurrenceCount !== 0) {
    Common.fail("material_shop_unlocked_target_invalid", "applicability",
      "current source fixture does not prove all material routes affordable and the frozen target exact");
  }
  Common.exactKeys(value.sourceFixture, ["sourceFixtureSlot", "artifactSetSha256",
    "artifacts", "money", "targetOwned"],
  "material_shop_source_fixture_invalid", "applicability");
  if (value.sourceFixture.sourceFixtureSlot !== Common.SOURCE_FIXTURE_SLOT
      || !Common.SHA256_RE.test(String(value.sourceFixture.artifactSetSha256 || ""))
      || !Array.isArray(value.sourceFixture.artifacts)
      || value.sourceFixture.artifacts.filter((entry) => entry.kind === "json").length !== 1
      || value.sourceFixture.artifacts.filter((entry) => entry.kind === "sol").length < 1
      || value.sourceFixture.money < value.selectedUnlockedTarget.basePrice
      || value.sourceFixture.targetOwned !== 0) {
    Common.fail("material_shop_source_fixture_invalid", "applicability",
      "source fixture JSON/SOL/money/owned proof is incomplete");
  }
  if (!Array.isArray(value.seedAudit) || value.seedAudit.length !== SEED_AUDIT_SLOTS.length
      || Evidence.canonicalJson(value.seedAudit.map((entry) => entry.slot))
        !== Evidence.canonicalJson(SEED_AUDIT_SLOTS)) {
    Common.fail("material_shop_seed_audit_invalid", "applicability",
      "current applicability lacks the frozen four-seed audit");
  }
  value.seedAudit.forEach((entry) => {
    Common.exactKeys(entry, ["slot", "artifactSetSha256", "artifacts", "money",
      "targetOwned", "affordableOccurrenceCount", "atDefaultLimitOccurrenceCount", "maxOwned"],
    "material_shop_seed_audit_invalid", "applicability");
    if (!Common.SHA256_RE.test(String(entry.artifactSetSha256 || ""))
        || !Array.isArray(entry.artifacts)
        || entry.artifacts.filter((artifact) => artifact.kind === "json").length !== 1
        || entry.artifacts.filter((artifact) => artifact.kind === "sol").length < 1
        || entry.affordableOccurrenceCount !== value.counts.materialOccurrenceCount
        || entry.atDefaultLimitOccurrenceCount !== 0
        || !Number.isInteger(entry.maxOwned) || entry.maxOwned >= 999999) {
      Common.fail("material_shop_seed_audit_invalid", "applicability",
        "audited seed does not prove q1 affordability and no material at default max", {
          slot: entry.slot,
        });
    }
  });
  return value;
}

function captureCurrentDataApplicability(rootValue, options) {
  const settings = typeof options === "string" ? { capturedAt: options } : options || {};
  const roots = resolveApplicabilityRoots(rootValue, settings);
  const dataRoot = roots.dataRoot;
  const fixtureAuthorityRoot = roots.fixtureAuthorityRoot;
  const materialFile = exactFile(dataRoot, MATERIAL_CATALOG);
  const materialNames = parseMaterialNames(materialFile.bytes);
  const materialSet = new Set(materialNames);
  const shopDescriptors = NpcProduction.productionFiles(dataRoot)
    .filter((entry) => entry.role === "shop_data")
    .sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  const inputFiles = [materialFile];
  const prices = new Map();
  NpcProduction.productionFiles(dataRoot).filter((entry) => entry.role === "item_data")
    .sort((left, right) => left.relativePath.localeCompare(right.relativePath))
    .forEach((descriptor) => {
      const file = exactFile(dataRoot, descriptor.relativePath);
      inputFiles.push(file);
      parseItemPrices(file.relativePath, file.bytes, prices);
    });
  const occurrences = [];
  shopDescriptors.forEach((descriptor) => {
    const file = exactFile(dataRoot, descriptor.relativePath);
    inputFiles.push(file);
    parseShop(file.relativePath, file.bytes).forEach((entry) => {
      if (materialSet.has(entry.itemName)) {
        if (!prices.has(entry.itemName) || prices.get(entry.itemName) < 0) {
          Common.fail("material_shop_item_price_missing", "applicability",
            "material shop occurrence lacks an exact ItemData base price", entry);
        }
        entry.basePrice = prices.get(entry.itemName);
        occurrences.push(entry);
      }
    });
  });
  if (!occurrences.length) {
    Common.fail("material_shop_occurrence_inventory_empty", "applicability",
      "current material catalog has no NPC shop source occurrences");
  }
  const as2File = exactFile(dataRoot, PURCHASE_AUTHORITY);
  const hostFile = exactFile(dataRoot, HOST_AUTHORITY);
  inputFiles.push(as2File, hostFile);
  const requiredInfo = occurrences.filter((entry) => entry.requiredInfo !== "");
  const purchaseLimit = occurrences.filter((entry) => Number.isInteger(entry.purchaseLimit)
    && entry.purchaseLimit >= 1);
  const publicOccurrences = occurrences.map((entry) => ({ shopFile: entry.shopFile,
    shopId: entry.shopId, catalogIndex: entry.catalogIndex, itemName: entry.itemName,
    basePrice: entry.basePrice,
    hasRequiredInfo: entry.requiredInfo !== "", hasPurchaseLimit: Number.isInteger(entry.purchaseLimit)
      && entry.purchaseLimit >= 1 }));
  const selectedOccurrence = publicOccurrences.find((entry) => entry.shopId === "厨师"
    && entry.catalogIndex === 24 && entry.itemName === "食用油");
  if (!selectedOccurrence || selectedOccurrence.basePrice !== 300) {
    Common.fail("material_shop_unlocked_target_missing", "applicability",
      "frozen chef catalog target is absent or changed");
  }
  const seedAudit = SEED_AUDIT_SLOTS.map((slot) => captureSeedAudit(
    fixtureAuthorityRoot, settings.appData, slot, occurrences, selectedOccurrence));
  const sourceFixture = captureSourceFixture(fixtureAuthorityRoot, settings.appData,
    selectedOccurrence);
  const inputs = inputFiles.map((file) => ({ relativePath: file.relativePath,
    sha256: file.sha256, bytes: file.length }))
    .sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  const value = {
    schema: APPLICABILITY_SCHEMA,
    capturedAt: settings.capturedAt || new Date().toISOString(),
    materialCatalog: { relativePath: materialFile.relativePath, sha256: materialFile.sha256,
      authoredMaterialCount: materialNames.length },
    counts: { materialCount: materialNames.length, shopFileCount: shopDescriptors.length,
      materialOccurrenceCount: occurrences.length,
      uniqueMaterialItemCount: new Set(occurrences.map((entry) => entry.itemName)).size,
      requiredInfoOccurrenceCount: requiredInfo.length,
      purchaseLimitOccurrenceCount: purchaseLimit.length,
      seedCount: seedAudit.length,
      seedMaterialPairCount: seedAudit.length * occurrences.length,
      affordableSeedOccurrenceCount: seedAudit.reduce((sum, entry) =>
        sum + entry.affordableOccurrenceCount, 0),
      atDefaultLimitSeedOccurrenceCount: seedAudit.reduce((sum, entry) =>
        sum + entry.atDefaultLimitOccurrenceCount, 0) },
    unlocked: { status: "required_candidate_journey",
      qualifyingOccurrenceCount: occurrences.length - requiredInfo.length },
    locked: { status: requiredInfo.length === 0
      ? "not_applicable_current_data" : "requires_seed_probe",
      qualifyingOccurrenceCount: requiredInfo.length },
    max: { status: purchaseLimit.length === 0
      ? "not_applicable_current_data" : "requires_seed_probe",
      qualifyingOccurrenceCount: purchaseLimit.length },
    occurrences: publicOccurrences,
    seedAudit,
    sourceFixture,
    selectedUnlockedTarget: { shopId: selectedOccurrence.shopId,
      catalogIndex: selectedOccurrence.catalogIndex, itemName: selectedOccurrence.itemName,
      basePrice: selectedOccurrence.basePrice, owned: sourceFixture.targetOwned,
      quantity: 1, saleCount: 0 },
    authority: { defaultMaterialPurchaseLimit: 999999, materialCapacitySkipped: true,
      anchors: assertAuthority(as2File, hostFile) },
    inputsSha256: Evidence.sha256Text(Evidence.canonicalJson(inputs)),
  };
  value.applicabilitySha256 = Evidence.sha256Text(
    Evidence.canonicalJson(stableApplicability(value)));
  return validateApplicability(value);
}

function verifyCurrentDataApplicability(root, value, options) {
  validateApplicability(value);
  const current = captureCurrentDataApplicability(root,
    Object.assign({}, options || {}, { capturedAt: value.capturedAt }));
  if (current.applicabilitySha256 !== value.applicabilitySha256) {
    Common.fail("material_shop_applicability_drift", "applicability",
      "current material/shop authority bytes drifted after applicability capture");
  }
  return current;
}

module.exports = {
  APPLICABILITY_SCHEMA,
  FIXTURE_AUTHORITY_BINDING_SCHEMA,
  HOST_AUTHORITY,
  MATERIAL_CATALOG,
  PURCHASE_AUTHORITY,
  SEED_AUDIT_SLOTS,
  captureSeedAudit,
  captureCurrentDataApplicability,
  captureSourceFixture,
  createFixtureAuthorityBinding,
  fixtureAuthorityProjection,
  materialOwnedFromSave,
  parseItemPrices,
  parseMaterialNames,
  parseShop,
  resolveApplicabilityRoots,
  replayFixtureAuthorityBinding,
  stableApplicability,
  stableFixtureAuthorityBinding,
  validateApplicability,
  validateFixtureAuthorityBinding,
  verifyCurrentDataApplicability,
};
