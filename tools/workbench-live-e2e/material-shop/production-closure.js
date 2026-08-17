"use strict";

const fs = require("fs");
const path = require("path");
const CraftingSource = require("../crafting/source-contract");
const NpcClosure = require("../npc/production-closure");
const Evidence = require("../lib/evidence-artifact");
const Common = require("./common");
const Scope = require("./scope-manifest");

const CLOSURE_SCHEMA = "workbench-live-e2e.material-shop.production-closure.v1";
const SEMANTIC_SCHEMA = "workbench-live-e2e.material-shop.source-semantics.v1";
const MATERIALIZED_PRODUCER_SCHEMA =
  "workbench-live-e2e.material-shop.materialized-producers.v1";

const SOURCE_ASSERTIONS = Object.freeze([
  {
    relativePath: "launcher/src/Guardian/MaterialShopNavigationCoordinator.cs",
    anchors: [
      ["host_timeout_5000", /MaterialShopNavigationTimeoutMs\s*=\s*5000\s*;/],
      ["host_delivery_margin_1500", /MaterialShopNavigationDeliveryMarginMs\s*=\s*1500\s*;/],
      ["host_forward_command", /"open_npc_shop"/],
      ["host_reverse_command", /"return_crafting_materials"/],
      ["host_exact_replace", /_panelHost\.TryReplacePanelExact\s*\(/],
    ],
  },
  {
    relativePath: "launcher/src/Guardian/PanelHostController.cs",
    anchors: [["host_exact_replace_api", /public\s+bool\s+TryReplacePanelExact\s*\(/]],
  },
  {
    relativePath: "launcher/src/Guardian/PreparedPanelReplace.cs",
    anchors: [
      ["prepared_replace_type", /class\s+PreparedPanelReplace\b/],
      ["prepared_replace_commit", /\bCommitCapabilitiesNoFail\s*\(/],
      ["prepared_replace_abort", /\bAbortPrepared\s*\(/],
    ],
  },
  {
    relativePath: "launcher/src/Tasks/MaterialShopAccessTask.cs",
    anchors: [
      ["access_authority_action", /\?\s*"craftingProcurementShopAuthorize"\s*:\s*"craftingMaterialShopAuthorize"/],
      ["access_indexed_live_match", /"indexed_live_match"/],
    ],
  },
  {
    relativePath: "scripts/类定义/org/flashNight/arki/item/MaterialArchiveProjector.as",
    anchors: [
      ["as2_full_access", /shopAccessMode:fullAccess\s*\?\s*"full"\s*:\s*"unavailable"/],
      ["as2_indexed_live_match", /shopAccessReason:fullAccess\s*\?\s*"indexed_live_match"/],
      ["as2_authority_action", /params\.action\s*===\s*"craftingMaterialShopAuthorize"/],
    ],
  },
  {
    relativePath: "launcher/web/modules/crafting-runtime.js",
    anchors: [
      ["web_watchdog_6500", /NAVIGATION_WATCHDOG_MS\s*=\s*6500\s*;/],
      ["web_forward_command", /cmd:'open_npc_shop'/],
      ["web_forward_source", /source:'crafting_materials'/],
      ["web_forward_snapshot", /materialSnapshotId:String\(input\.materialSnapshotId\)/],
      ["web_forward_index", /catalogIndex:Number\(input\.catalogIndex\)/],
    ],
  },
  {
    relativePath: "launcher/web/modules/npcshop-runtime.js",
    anchors: [
      ["shop_watchdog_6500", /NAVIGATION_WATCHDOG_MS\s*=\s*6500\s*;/],
      ["shop_reverse_command", /cmd:'return_crafting_materials'/],
      ["shop_outer_close_reasons", /CLOSE_REASONS\s*=\s*\{button:true,\s*escape:true,\s*backdrop:true,\s*toggle:true\}/],
    ],
  },
  {
    relativePath: "launcher/web/modules/npcshop-material-navigation.js",
    anchors: [
      ["preferred_index_exact", /Number\(item\.catalogIndex\)\s*===\s*target\.preferredCatalogIndex/],
      ["preferred_name_exact", /String\(item\.itemName\s*\|\|\s*''\)\s*===\s*target\.preferredItemName/],
      ["navigation_focus_marker", /data-navigation-focus/],
      ["navigation_scroll_once_surface", /scrollIntoView\s*\(/],
      ["navigation_focus_surface", /target\.focus\s*\(/],
    ],
    forbids: [
      ["no_click", /\.click\s*\(/],
      ["no_toggle_purchase", /\btogglePurchase\b/],
      ["no_purchase_intents", /\b_purchaseIntents\b/],
      ["no_settlement", /\bopenSettlement\b/],
      ["no_bridge_send", /\bBridge\.send\b/],
      ["no_panels_open", /\bPanels\.open\b/],
    ],
  },
]);

function scopeFile(scope, relativePath) {
  const normalized = Common.normalizeRelative(relativePath);
  const matches = scope.files.filter((entry) =>
    entry.relativePath.toLowerCase() === normalized.toLowerCase());
  if (matches.length !== 1 || matches[0].relativePath !== normalized) {
    Common.fail("material_shop_semantic_file_unbound", "production_closure",
      "semantic assertion file is not uniquely bound by the current-tree scope", { relativePath });
  }
  return matches[0];
}

function readBoundText(root, scope, relativePath) {
  const bound = scopeFile(scope, relativePath);
  const resolved = Common.resolveWithin(root, relativePath, "production_closure");
  const bytes = fs.readFileSync(resolved.absolute);
  if (bytes.length !== bound.bytes || Evidence.sha256Bytes(bytes) !== bound.sha256) {
    Common.fail("material_shop_semantic_file_drift", "production_closure",
      "semantic assertion bytes differ from the bound current-tree scope", { relativePath });
  }
  return { bound, text: bytes.toString("utf8").replace(/^\uFEFF/, "") };
}

function captureSemanticContract(root, scope) {
  const files = SOURCE_ASSERTIONS.map((assertion) => {
    const source = readBoundText(root, scope, assertion.relativePath);
    const anchorIds = [];
    (assertion.anchors || []).forEach(([id, pattern]) => {
      if (!pattern.test(source.text)) {
        Common.fail("material_shop_source_anchor_missing", "production_closure",
          "reviewed A4b source anchor is absent", { relativePath: assertion.relativePath, id });
      }
      anchorIds.push(id);
    });
    const forbidIds = [];
    (assertion.forbids || []).forEach(([id, pattern]) => {
      if (pattern.test(source.text)) {
        Common.fail("material_shop_source_forbidden_surface", "production_closure",
          "navigation-only source exposes a forbidden purchase/business surface",
          { relativePath: assertion.relativePath, id });
      }
      forbidIds.push(id);
    });
    return {
      relativePath: assertion.relativePath,
      sha256: source.bound.sha256,
      anchorIds,
      forbidIds,
    };
  });
  const value = { schema: SEMANTIC_SCHEMA, files };
  value.contractSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function craftingComposition(fingerprint) {
  return {
    schema: fingerprint.schema,
    fingerprintSha256: fingerprint.fingerprintSha256,
    fileCount: fingerprint.files.length,
    producerInputsSchema: fingerprint.producerInputs.schema,
    producerInputsSha256: fingerprint.producerInputs.inputsSha256,
    as2AlgorithmSchema: fingerprint.as2AlgorithmContract.schema,
    as2AlgorithmSha256: Evidence.sha256Text(
      Evidence.canonicalJson(fingerprint.as2AlgorithmContract)),
    sourceFingerprint: fingerprint,
  };
}

function npcComposition(root) {
  const files = NpcClosure.productionFiles(root).map((entry) => ({
    role: entry.role,
    relativePath: Common.normalizeRelative(entry.relativePath),
  }));
  return {
    provider: "tools/workbench-live-e2e/npc/production-closure.js#productionFiles",
    fileCount: files.length,
    inventorySha256: Evidence.sha256Text(Evidence.canonicalJson(files)),
  };
}

function sharedProducerComposition(scope) {
  const files = scope.files.filter((entry) =>
    entry.origins.includes("material_shop_shared_producer")).map((entry) => ({
    roles: entry.roles, relativePath: entry.relativePath,
    bytes: entry.bytes, sha256: entry.sha256,
  }));
  return { provider: "scope-origin:material_shop_shared_producer",
    fileCount: files.length, files,
    filesSha256: Evidence.sha256Text(Evidence.canonicalJson(files)) };
}

function captureMaterializedSharedProducers(resourcesRootValue, closure) {
  verifyProductionClosure(closure, { currentTree: false });
  const resourcesRoot = path.resolve(resourcesRootValue);
  const expected = closure.sharedProducers.files;
  const files = expected.map((entry) => {
    const resolved = Common.resolveWithin(resourcesRoot, entry.relativePath,
      "materialized_producers");
    const file = Evidence.readExactRegularFile(resolved.absolute, {
      phase: "materialized_producers", maximumBytes: Math.max(1, entry.bytes),
    });
    if (file.length !== entry.bytes || file.sha256 !== entry.sha256) {
      Common.fail("material_shop_materialized_producer_drift", "materialized_producers",
        "materialized producer/static input differs from the exact current-tree closure", {
          relativePath: entry.relativePath,
        });
    }
    return { roles: entry.roles, relativePath: entry.relativePath,
      absolutePath: file.path, bytes: file.length, sha256: file.sha256 };
  });
  const value = { schema: MATERIALIZED_PRODUCER_SCHEMA, resourcesRoot,
    closureSha256: closure.closureSha256, files };
  value.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function verifyMaterializedSharedProducers(value, resourcesRoot, closure) {
  Common.exactKeys(value, ["schema", "resourcesRoot", "closureSha256", "files",
    "bindingSha256"], "material_shop_materialized_producers_invalid",
  "materialized_producers");
  const unsigned = Object.assign({}, value);
  delete unsigned.bindingSha256;
  if (value.schema !== MATERIALIZED_PRODUCER_SCHEMA
      || path.resolve(value.resourcesRoot || "") !== path.resolve(resourcesRoot)
      || value.closureSha256 !== closure.closureSha256
      || value.bindingSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_materialized_producers_invalid", "materialized_producers",
      "materialized producer binding is malformed or detached from the closure");
  }
  const current = captureMaterializedSharedProducers(resourcesRoot, closure);
  if (Evidence.canonicalJson(current) !== Evidence.canonicalJson(value)) {
    Common.fail("material_shop_materialized_producer_drift", "materialized_producers",
      "materialized producer/static bytes changed after binding");
  }
  return value;
}

function stableCraftingComposition(value) {
  const projected = JSON.parse(JSON.stringify(value));
  if (projected.sourceFingerprint) {
    delete projected.sourceFingerprint.capturedAt;
    delete projected.sourceFingerprint.fingerprintSha256;
    const stableFingerprintSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(projected.sourceFingerprint));
    projected.sourceFingerprint.fingerprintSha256 = stableFingerprintSha256;
    projected.fingerprintSha256 = stableFingerprintSha256;
  }
  return projected;
}

function stableScope(value) {
  const projected = JSON.parse(JSON.stringify(value));
  delete projected.capturedAt;
  return projected;
}

function stableProjection(value) {
  return {
    schema: value.schema,
    root: value.root,
    head: value.head,
    scope: stableScope(value.scope),
    crafting: stableCraftingComposition(value.crafting),
    npc: value.npc,
    sharedProducers: value.sharedProducers,
    semantics: value.semantics,
    boundaries: value.boundaries,
  };
}

function captureProductionClosure(rootValue, capturedAt) {
  const root = Common.assertCanonicalRoot(rootValue);
  const scope = Scope.captureCurrentTreeScope(root, capturedAt);
  const fingerprint = CraftingSource.captureSourceFingerprint(root, capturedAt);
  if (!CraftingSource.validateSourceFingerprint(fingerprint)) {
    Common.fail("material_shop_crafting_fingerprint_invalid", "production_closure",
      "composed Crafting source fingerprint is invalid");
  }
  const value = {
    schema: CLOSURE_SCHEMA,
    capturedAt: capturedAt || new Date().toISOString(),
    root,
    head: scope.head,
    scope,
    crafting: craftingComposition(fingerprint),
    npc: npcComposition(root),
    sharedProducers: sharedProducerComposition(scope),
    semantics: captureSemanticContract(root, scope),
    boundaries: {
      candidateBuilt: false,
      candidateExecuted: false,
      e2eVerified: false,
      promoted: false,
      standardEntryVerified: false,
    },
  };
  value.closureSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableProjection(value)));
  return value;
}

function verifyProductionClosure(value, options) {
  const settings = options || {};
  Common.exactKeys(value, ["schema", "capturedAt", "root", "head", "scope", "crafting",
    "npc", "sharedProducers", "semantics", "boundaries", "closureSha256"],
  "material_shop_production_closure_invalid", "production_closure");
  if (value.schema !== CLOSURE_SCHEMA || !Number.isFinite(Date.parse(value.capturedAt))
      || value.root !== path.resolve(value.root || "") || value.head !== value.scope.head
      || value.closureSha256 !== Evidence.sha256Text(Evidence.canonicalJson(stableProjection(value)))) {
    Common.fail("material_shop_production_closure_invalid", "production_closure",
      "A5 production closure envelope or digest is invalid");
  }
  Scope.verifyScopeManifest(value.scope, { currentTree: settings.currentTree !== false });
  Common.exactKeys(value.crafting, ["schema", "fingerprintSha256", "fileCount",
    "producerInputsSchema", "producerInputsSha256", "as2AlgorithmSchema",
    "as2AlgorithmSha256", "sourceFingerprint"],
  "material_shop_crafting_composition_invalid", "production_closure");
  Common.exactKeys(value.npc, ["provider", "fileCount", "inventorySha256"],
    "material_shop_npc_composition_invalid", "production_closure");
  Common.exactKeys(value.sharedProducers, ["provider", "fileCount", "files", "filesSha256"],
    "material_shop_shared_producer_composition_invalid", "production_closure");
  Common.exactKeys(value.boundaries, ["candidateBuilt", "candidateExecuted", "e2eVerified",
    "promoted", "standardEntryVerified"], "material_shop_boundary_invalid", "production_closure");
  if (!Common.SHA256_RE.test(String(value.crafting.fingerprintSha256 || ""))
      || !Common.SHA256_RE.test(String(value.crafting.producerInputsSha256 || ""))
      || !Common.SHA256_RE.test(String(value.crafting.as2AlgorithmSha256 || ""))
      || !Number.isInteger(value.crafting.fileCount) || value.crafting.fileCount < 1
      || !CraftingSource.validateSourceFingerprint(value.crafting.sourceFingerprint)
      || value.crafting.sourceFingerprint.fingerprintSha256
        !== value.crafting.fingerprintSha256
      || value.crafting.sourceFingerprint.producerInputs.inputsSha256
        !== value.crafting.producerInputsSha256
      || value.npc.provider !== "tools/workbench-live-e2e/npc/production-closure.js#productionFiles"
      || !Number.isInteger(value.npc.fileCount) || value.npc.fileCount < 1
      || !Common.SHA256_RE.test(String(value.npc.inventorySha256 || ""))
      || value.sharedProducers.provider !== "scope-origin:material_shop_shared_producer"
      || !Number.isInteger(value.sharedProducers.fileCount)
      || value.sharedProducers.fileCount < Scope.SHARED_PRODUCER_ENTRYPOINTS.length
      || !Array.isArray(value.sharedProducers.files)
      || value.sharedProducers.files.length !== value.sharedProducers.fileCount
      || value.sharedProducers.filesSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(value.sharedProducers.files))
      || Evidence.canonicalJson(value.sharedProducers)
        !== Evidence.canonicalJson(sharedProducerComposition(value.scope))
      || Object.values(value.boundaries).some((flag) => flag !== false)) {
    Common.fail("material_shop_production_composition_invalid", "production_closure",
      "A5 production composition or evidence boundary is invalid");
  }
  Common.exactKeys(value.semantics, ["schema", "files", "contractSha256"],
    "material_shop_semantic_contract_invalid", "production_closure");
  if (value.semantics.schema !== SEMANTIC_SCHEMA || !Array.isArray(value.semantics.files)
      || value.semantics.files.length !== SOURCE_ASSERTIONS.length
      || value.semantics.contractSha256 !== Evidence.sha256Text(Evidence.canonicalJson({
        schema: value.semantics.schema, files: value.semantics.files,
      }))) {
    Common.fail("material_shop_semantic_contract_invalid", "production_closure",
      "A5 semantic source contract is malformed or detached");
  }
  if (settings.currentTree !== false) {
    const current = captureProductionClosure(value.root);
    if (Evidence.canonicalJson(stableProjection(current))
        !== Evidence.canonicalJson(stableProjection(value))) {
      Common.fail("material_shop_production_current_tree_drift", "production_closure",
        "A5 production closure changed after capture");
    }
  }
  return value;
}

function captureCandidateBinding(candidateRoot, candidateIdentity, closure) {
  verifyProductionClosure(closure, { currentTree: false });
  return CraftingSource.captureCandidateProducerBinding(
    candidateRoot, candidateIdentity, closure.crafting.sourceFingerprint);
}

function verifyCandidateBinding(candidateRoot, candidateIdentity, closure, binding) {
  verifyProductionClosure(closure, { currentTree: false });
  return CraftingSource.verifyCandidateProducerBinding(
    candidateRoot, candidateIdentity, closure.crafting.sourceFingerprint, binding);
}

module.exports = {
  CLOSURE_SCHEMA,
  MATERIALIZED_PRODUCER_SCHEMA,
  SEMANTIC_SCHEMA,
  SOURCE_ASSERTIONS,
  captureCandidateBinding,
  captureMaterializedSharedProducers,
  captureProductionClosure,
  captureSemanticContract,
  stableCraftingComposition,
  stableScope,
  stableProjection,
  verifyCandidateBinding,
  verifyMaterializedSharedProducers,
  verifyProductionClosure,
};
