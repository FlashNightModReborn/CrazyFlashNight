"use strict";

const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const ControlContract = require("../lib/control-contract");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const ModuleJournal = require("../lib/runtime-module-journal");
const RuntimeGuard = require("../lib/runtime-guard");
const {
  API_VERSION,
  AUTHORIZATION_SCHEMA,
  BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA,
  OWNED_BASE_RELATIVE,
  RECEIPT_SCHEMA,
  SHA256_RE,
  assertNoRawAuthority,
  atomicWriteJson,
  deepClone,
  fail,
  readJsonFile,
  verifyArtifactManifest,
} = require("./common");
const {
  REQUIRED_CONTROL_STEPS,
  TRANSPORTS,
  RESULTS,
  domInputEvidence,
  validateAck,
  validateRequest,
  verifyAckCapture,
  verifyProviderReceiptReference,
} = require("./control-channel");
const Protocol = require("./protocol");
const ProductionClosure = require("./production-closure");
const REPOSITORY_ROOT = path.resolve(__dirname, "..", "..", "..");

const TRUSTED_CAPABILITY_SOURCES = new Set([
  "authenticated_legacy_http_process_contract",
]);
const TRUSTED_AUTHORIZATION_SOURCES = new Set(["cli_explicit_flag"]);

function same(left, right) {
  return Evidence.canonicalJson(left) === Evidence.canonicalJson(right);
}

function requireObject(value, code, phase, message) {
  if (!Evidence.isPlainObject(value)) fail(code, phase, message);
  return value;
}

function verifyDigestObject(value, digestField, code, phase) {
  requireObject(value, code, phase, "digest-bound artifact is missing");
  const digest = String(value[digestField] || "");
  const payload = Object.assign({}, value);
  delete payload[digestField];
  if (!/^[a-f0-9]{64}$/.test(digest)
      || Evidence.sha256Text(Evidence.canonicalJson(payload)) !== digest) {
    fail(code, phase, "digest-bound artifact was modified");
  }
  return value;
}

function validateEnvelope(bundle, options) {
  const settings = options || {};
  requireObject(bundle, "bundle_invalid", "bundle", "journey bundle is missing");
  const live = bundle.evidenceMode === "live_capture";
  const offline = bundle.evidenceMode === "offline_fixture";
  if (bundle.schema !== BUNDLE_SCHEMA || bundle.apiVersion !== API_VERSION
      || bundle.status !== "captured_unverified" || bundle.deployment !== "NOT_DEPLOYED"
      || typeof bundle.root !== "string" || !path.isAbsolute(bundle.root)
      || typeof bundle.runDir !== "string" || !path.isAbsolute(bundle.runDir)
      || !/^[A-Za-z0-9._~-]{1,160}$/.test(String(bundle.runId || ""))
      || bundle.seedSlot === bundle.targetSlot
      || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(String(bundle.targetSlot || ""))
      || bundle.allowIsolatedCommit !== true || bundle.allowCodexCuFallback !== true
      || (!live && !offline)
      || live && (bundle.fixtureProvenance !== null
        || bundle.safeExitUiJourneyVerified !== true
        || bundle.exitMethod !== "native_safe_exit_then_exit_confirm")
      || offline && (!Evidence.isPlainObject(bundle.fixtureProvenance)
        || !same(Object.keys(bundle.fixtureProvenance).sort(),
          ["generator", "liveCapture", "schema", "synthetic"])
        || bundle.fixtureProvenance.schema
          !== "workbench-live-e2e.equipment.fixture-provenance.v1"
        || bundle.fixtureProvenance.generator !== "fixtures/valid-bundle.js"
        || bundle.fixtureProvenance.synthetic !== true
        || bundle.fixtureProvenance.liveCapture !== false
        || bundle.safeExitUiJourneyVerified !== false
        || bundle.exitMethod !== "offline_fixture_simulation")) {
    fail("bundle_invalid", "bundle", "Equipment journey envelope/scope is malformed");
  }
  CloneGuard.assertSourceSlot(bundle.seedSlot);
  CloneGuard.assertDedicatedSlot(bundle.targetSlot);
  if (settings.testOnlyAllowInjectedEvidence !== true) {
    if (!live) {
      fail("offline_fixture_not_live_admissible", "bundle",
        "offline fixture evidence cannot enter the live verification path");
    }
    if (path.resolve(bundle.root).toLowerCase() !== REPOSITORY_ROOT.toLowerCase()) {
      fail("bundle_root_mismatch", "bundle",
        "journey bundle is not bound to the verifier's current repository root");
    }
    const exactRunDir = Evidence.assertOwnedRunDirectory(REPOSITORY_ROOT, bundle.runDir,
      OWNED_BASE_RELATIVE, "bundle");
    if (path.basename(exactRunDir) !== bundle.runId) {
      fail("bundle_run_identity_mismatch", "bundle",
        "owned run directory basename does not equal the immutable runId");
    }
  }
  assertNoRawAuthority(bundle, "bundle");
  return bundle;
}

function verifyProcessContract(artifact, session, identity, root) {
  verifyDigestObject(artifact, "artifactSha256", "launcher_process_contract_invalid", "runtime");
  if (artifact.schema !== "workbench-live-e2e.launcher-process-contract.v1"
      || artifact.apiVersion !== "FROZEN-v1" || artifact.pid !== identity.pid
      || artifact.pid !== session.pid || artifact.processPath !== path.resolve(identity.processPath)
      || String(artifact.processStartUtcTicks) !== String(session.processStartUtcTicks)
      || artifact.projectRootArgumentExact !== true || artifact.legacyHttpAutomationArg !== true
      || artifact.agentRuntimeAdmission !== false
      || path.resolve(artifact.projectRoot || "") !== path.resolve(root)
      || artifact.trustedSource !== "actual_process_command_line+pid_bound_credential") {
    fail("launcher_process_contract_invalid", "runtime",
      "authenticated process contract does not prove legacy-only candidate lifecycle");
  }
  return artifact;
}

function verifiedAuthorityIconNames(firstSemantic, restartSemantic) {
  const names = new Set();
  const phases = [firstSemantic, restartSemantic];
  phases.forEach((phase, phaseIndex) => {
    const pairs = phase && phase.pairs && phase.pairs.all;
    if (!Array.isArray(pairs) || !pairs.length) {
      fail("authority_icon_source_invalid", "production_closure",
        "verified Equipment/Inventory authority pairs are missing", { phaseIndex });
    }
    pairs.forEach((pair, pairIndex) => {
      const request = pair && pair.request;
      const response = pair && pair.response;
      if (!Evidence.isPlainObject(request) || !Evidence.isPlainObject(response)
          || request.type !== "panel" || request.panel !== "workbench"
          || !["equipment_tuning", "inventory"].includes(request.domain)
          || response.type !== "panel_resp" || response.panel !== "workbench"
          || response.domain !== request.domain || response.cmd !== request.cmd
          || response.callId !== request.callId
          || response.panelInstanceId !== request.panelInstanceId
          || response.success !== true) {
        fail("authority_icon_source_invalid", "production_closure",
          "icon authority is not one completed strict Equipment/Inventory request-response pair",
          { phaseIndex, pairIndex });
      }
      (function collectValidatedAuthorityIcons(value) {
        if (Array.isArray(value)) {
          value.forEach(collectValidatedAuthorityIcons);
          return;
        }
        if (!Evidence.isPlainObject(value)) return;
        Object.keys(value).forEach((key) => {
          if (key === "icon" && typeof value[key] === "string" && value[key]) {
            names.add(value[key]);
          } else {
            collectValidatedAuthorityIcons(value[key]);
          }
        });
      }(response));
    });
  });
  return names;
}

function verifyProduction(bundle, first, restart, firstSemantic, restartSemantic, options) {
  const suppliedClosure = requireObject(bundle.productionClosure, "production_closure_missing",
    "production_closure", "current-tree production closure is missing");
  let closure;
  if (options && options.testOnlyAllowInjectedEvidence === true
      && options.skipFileClosure === true) {
    const unsignedClosure = Object.assign({}, suppliedClosure);
    delete unsignedClosure.closureSha256;
    if (suppliedClosure.schema !== ProductionClosure.CLOSURE_SCHEMA
        || path.resolve(suppliedClosure.root || "").toLowerCase()
          !== path.resolve(bundle.root).toLowerCase()
        || !Number.isFinite(Date.parse(suppliedClosure.capturedAt))
        || !Array.isArray(suppliedClosure.files) || !suppliedClosure.files.length
        || new Set(suppliedClosure.files.map((entry) => entry && entry.locator)).size
          !== suppliedClosure.files.length
        || suppliedClosure.files.some((entry) => !Evidence.isPlainObject(entry)
          || !/^[a-z0-9_]+$/.test(String(entry.role || ""))
          || !/^root:[^\\]+$/.test(String(entry.locator || ""))
          || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
          || !Number.isInteger(entry.bytes) || entry.bytes < 1)
        || suppliedClosure.closureSha256 !== Evidence.sha256Text(
          Evidence.canonicalJson(unsignedClosure))) {
      fail("production_closure_invalid", "production_closure",
        "test fixture production closure is malformed");
    }
    ProductionClosure.validateProducerInputsEnvelope(suppliedClosure.producerInputs,
      suppliedClosure.root);
    ProductionClosure.validatePageResourceContract(suppliedClosure.pageResourceContract,
      suppliedClosure.files);
    closure = suppliedClosure;
  } else {
    closure = ProductionClosure.verifyProductionClosure(bundle.root, suppliedClosure);
  }
  const candidateProducer = ProductionClosure.verifyCandidateProducerBinding(
    path.resolve(bundle.candidateRoot || ""), first.identity, closure,
    bundle.candidateProducer);
  const binding = requireObject(bundle.productionBinding, "production_binding_missing",
    "production_closure", "candidate/run production binding is missing");
  const unsignedBinding = Object.assign({}, binding);
  delete unsignedBinding.bindingSha256;
  const publicIdentity = ProductionClosure.publicCandidateIdentity(first.identity);
  if (binding.schema !== ProductionClosure.BINDING_SCHEMA || binding.runId !== bundle.runId
      || binding.productionClosureSha256 !== closure.closureSha256
      || binding.producerInputsSha256 !== closure.producerInputs.inputsSha256
      || binding.candidateIdentitySha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(publicIdentity))
      || binding.candidateProducerSha256 !== candidateProducer.evidenceSha256
      || binding.bindingSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(unsignedBinding))) {
    fail("production_binding_invalid", "production_closure",
      "production closure is detached from the exact candidate/run identity");
  }
  if (!same(ProductionClosure.publicCandidateIdentity(restart.identity), publicIdentity)) {
    fail("production_binding_restart_invalid", "production_closure",
      "restart candidate identity differs from the production binding");
  }
  const expectedWeb = ProductionClosure.webFiles(closure);
  const expectedScripts = ProductionClosure.scriptFiles(closure);
  const expectedStyles = ProductionClosure.styleFiles(closure);
  const expectedScriptUrls = expectedScripts.map((entry) => "https://overlay.local/"
    + entry.locator.slice("root:launcher/web/".length));
  const expectedStyleUrls = expectedStyles.map((entry) => "https://overlay.local/"
    + entry.locator.slice("root:launcher/web/".length));
  // Only protocol-validated, strictly paired successful Equipment/Inventory
  // responses may authorize dynamic icon routes. Arbitrary transcript metadata,
  // requests, diagnostics, or other bundle fields are deliberately excluded.
  const relevantIconNames = verifiedAuthorityIconNames(firstSemantic, restartSemantic);
  function verifyLoaded(runtime, lifecycle) {
    const loaded = requireObject(runtime.loadedProduction, "loaded_production_missing",
      "production_closure", lifecycle + " runtime lacks actually loaded production bytes");
    const unsigned = Object.assign({}, loaded);
    delete unsigned.evidenceSha256;
    const loadedKeys = ["capturedAt", "contextOccurrences", "evidenceSha256", "lifecycle",
      "productionBindingSha256", "productionClosureSha256", "resourceOccurrences", "runId",
      "runtimePid", "schema", "scriptOccurrences", "toolSourcePlan"].sort();
    if (Evidence.canonicalJson(Object.keys(loaded).sort()) !== Evidence.canonicalJson(loadedKeys)
        || loaded.schema !== ProductionClosure.LOADED_SCHEMA || loaded.lifecycle !== lifecycle
        || loaded.runtimePid !== runtime.identity.pid || loaded.runId !== bundle.runId
        || !Number.isFinite(Date.parse(loaded.capturedAt))
        || loaded.productionClosureSha256 !== closure.closureSha256
        || loaded.productionBindingSha256 !== binding.bindingSha256
        || loaded.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
      fail("loaded_production_binding_invalid", "production_closure",
        lifecycle + " loaded-resource evidence is detached");
    }
    if (!Array.isArray(loaded.contextOccurrences)
        || !Array.isArray(loaded.scriptOccurrences)
        || !Array.isArray(loaded.resourceOccurrences)
        || !Array.isArray(loaded.toolSourcePlan)) {
      fail("loaded_production_raw_stream_invalid", "production_closure",
        lifecycle + " raw CDP context/script/resource streams are incomplete");
    }
    function sourceBytes(entry, code) {
      if (typeof entry.sourceBase64 !== "string" || !entry.sourceBase64
          || !/^[A-Za-z0-9+/]+={0,2}$/.test(entry.sourceBase64)) {
        fail(code, "production_closure", lifecycle + " raw source bytes are not canonical base64");
      }
      const bytes = Buffer.from(entry.sourceBase64, "base64");
      if (bytes.toString("base64") !== entry.sourceBase64
          || entry.sourceMethod === "Debugger.getScriptSource"
            && typeof entry.sourceBase64 !== "string"
          || entry.sourceBytes !== bytes.length
          || entry.sourceSha256 !== Evidence.sha256Bytes(bytes)) {
        fail(code, "production_closure",
          lifecycle + " raw source bytes/hash/count are detached");
      }
      return bytes;
    }
    function sourceOrigin(url) {
      try { return new URL(url).origin; } catch (_error) { return "opaque"; }
    }
    const contextKeys = ["auxData", "id", "name", "occurrence", "origin", "uniqueId"];
    // Bind the default execution context to the frame represented by the raw
    // Page stream without pre-classifying its first occurrence as Document.
    // Document cardinality/order belongs to the resource verifier below.
    const rawObservedFrameId = loaded.resourceOccurrences[0]
      ? loaded.resourceOccurrences[0].frameId : null;
    if (loaded.contextOccurrences.length !== 1
        || new Set(loaded.contextOccurrences.map((entry) => entry && entry.id)).size
          !== loaded.contextOccurrences.length
        || new Set(loaded.contextOccurrences.map((entry) => entry && entry.uniqueId)).size
          !== loaded.contextOccurrences.length
        || loaded.contextOccurrences.some((entry, index) => !Evidence.isPlainObject(entry)
          || !same(Object.keys(entry).sort(), contextKeys)
          || entry.occurrence !== index + 1 || !Number.isInteger(entry.id) || entry.id < 1
          || typeof entry.uniqueId !== "string" || !entry.uniqueId
          || typeof entry.name !== "string" || entry.origin !== "https://overlay.local"
          || !Evidence.isPlainObject(entry.auxData)
          || entry.auxData.isDefault !== true || entry.auxData.type !== "default"
          || typeof entry.auxData.frameId !== "string" || !entry.auxData.frameId
          || entry.auxData.frameId !== rawObservedFrameId)) {
      fail("loaded_production_context_occurrence_invalid", "production_closure",
        lifecycle + " raw Runtime.executionContextCreated occurrence stream drifted");
    }
    const mainContext = loaded.contextOccurrences[0];
    const mainFrameId = mainContext.auxData.frameId;
    const pageScriptUrl = "https://overlay.local/overlay.html";
    const scriptOccurrenceKeys = ["executionContextId", "occurrence", "origin", "rawParams",
      "scriptId", "sourceBase64", "sourceBytes", "sourceMethod", "sourceSha256", "url"];
    const scriptIds = new Set();
    loaded.scriptOccurrences.forEach((entry, index) => {
      const raw = entry && entry.rawParams;
      if (!Evidence.isPlainObject(entry) || !same(Object.keys(entry).sort(), scriptOccurrenceKeys)
          || entry.occurrence !== index + 1 || typeof entry.url !== "string"
          || entry.origin !== sourceOrigin(entry.url) || typeof entry.scriptId !== "string"
          || !entry.scriptId || scriptIds.has(entry.scriptId)
          || entry.executionContextId !== mainContext.id || entry.sourceMethod !== "Debugger.getScriptSource"
          || !Evidence.isPlainObject(raw) || String(raw.scriptId || "") !== entry.scriptId
          || String(raw.url || "") !== entry.url
          || Number(raw.executionContextId) !== entry.executionContextId
          || !Object.prototype.hasOwnProperty.call(raw, "executionContextAuxData")
          || !Evidence.isPlainObject(raw.executionContextAuxData)
          || !same(raw.executionContextAuxData, mainContext.auxData)) {
        fail("loaded_production_script_occurrence_invalid", "production_closure",
          lifecycle + " raw Debugger.scriptParsed occurrence/order/context stream drifted");
      }
      sourceBytes(entry, "loaded_production_script_occurrence_invalid");
      scriptIds.add(entry.scriptId);
    });
    const referencedContextIds = [];
    loaded.scriptOccurrences.forEach((entry) => {
      if (!referencedContextIds.includes(entry.executionContextId)) {
        referencedContextIds.push(entry.executionContextId);
      }
    });
    if (!same(referencedContextIds, loaded.contextOccurrences.map((entry) => entry.id))) {
      fail("loaded_production_context_reference_set_invalid", "production_closure",
        lifecycle + " script stream does not reference the exact ordered context occurrence set");
    }
    const toolPlanKeys = ["bytes", "deliveryMethod", "label", "sequence", "sha256",
      "sourceBase64", "url"];
    const executableOccurrences = loaded.scriptOccurrences.filter((entry) =>
      entry && expectedScriptUrls.includes(entry.url));
    const pageOccurrences = loaded.scriptOccurrences.filter((entry) =>
      entry && entry.url === pageScriptUrl);
    const toolOccurrences = loaded.scriptOccurrences.filter((entry) => entry
      && String(entry.url || "").startsWith("cf7-evidence://equipment/"));
    const foreignScripts = loaded.scriptOccurrences.filter((entry) => !entry
      || !entry.url || (!expectedScriptUrls.includes(entry.url) && entry.url !== pageScriptUrl
        && !entry.url.startsWith("cf7-evidence://equipment/")));
    const toolByUrl = new Map();
    loaded.toolSourcePlan.forEach((entry, index) => {
      if (!Evidence.isPlainObject(entry) || !same(Object.keys(entry).sort(), toolPlanKeys)
          || entry.sequence !== index + 1
          || !["identity", "install_new_document", "install_current_document", "health",
            "panel_state", "detach"].includes(entry.label)
          || typeof entry.url !== "string"
          || !entry.url.startsWith("cf7-evidence://equipment/")
          || !["Runtime.evaluate", "Page.addScriptToEvaluateOnNewDocument"]
            .includes(entry.deliveryMethod)
          || entry.label === "install_new_document"
            && entry.deliveryMethod !== "Page.addScriptToEvaluateOnNewDocument"
          || entry.label !== "install_new_document" && entry.deliveryMethod !== "Runtime.evaluate"
          || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
          || !Number.isInteger(entry.bytes) || entry.bytes < 1 || toolByUrl.has(entry.url)) {
        fail("loaded_production_tool_script_invalid", "production_closure",
          lifecycle + " tool-owned script plan is malformed, duplicated, or unordered");
      }
      const bytes = sourceBytes({ sourceBase64: entry.sourceBase64,
        sourceBytes: entry.bytes, sourceSha256: entry.sha256,
        sourceMethod: entry.deliveryMethod }, "loaded_production_tool_script_invalid");
      if (!bytes.toString("utf8").endsWith("//# sourceURL=" + entry.url)) {
        fail("loaded_production_tool_script_invalid", "production_closure",
          lifecycle + " tool sourceURL is absent or differs from its unique plan URL");
      }
      toolByUrl.set(entry.url, entry);
    });
    const expectedToolOccurrences = loaded.toolSourcePlan.filter((entry) =>
      entry.deliveryMethod === "Runtime.evaluate");
    const observedToolUrls = new Set();
    toolOccurrences.forEach((entry, index) => {
      const plan = expectedToolOccurrences[index];
      if (!plan || plan.url !== entry.url || observedToolUrls.has(entry.url)
          || entry.sourceSha256 !== plan.sha256 || entry.sourceBytes !== plan.bytes) {
        fail("loaded_production_tool_script_invalid", "production_closure",
          lifecycle + " raw tool occurrence is absent, reordered, reused, or byte-detached");
      }
      observedToolUrls.add(entry.url);
    });
    const toolLabels = loaded.toolSourcePlan.map((entry) => entry.label);
    if (loaded.toolSourcePlan.filter((entry) => entry.label === "install_new_document").length !== 1
        || loaded.toolSourcePlan.filter((entry) => entry.label === "detach").length !== 1
        || !same(toolLabels.slice(0, 3),
          ["identity", "install_new_document", "install_current_document"])
        || toolLabels[toolLabels.length - 1] !== "detach"
        || toolOccurrences.length !== expectedToolOccurrences.length
        || !same(toolOccurrences.map((entry) => ({ url: entry.url,
          sha256: entry.sourceSha256, bytes: entry.sourceBytes })),
        expectedToolOccurrences.map((entry) => ({ url: entry.url,
          sha256: entry.sha256, bytes: entry.bytes })))
        || loaded.toolSourcePlan.some((entry) => entry.label !== "install_new_document"
          && !observedToolUrls.has(entry.url))
        || toolOccurrences[toolOccurrences.length - 1].url
          !== loaded.toolSourcePlan[loaded.toolSourcePlan.length - 1].url) {
      fail("loaded_production_tool_script_invalid", "production_closure",
        lifecycle + " terminal detach is not the unique final raw tool/script occurrence");
    }
    if (foreignScripts.length !== 0 || pageOccurrences.length !== 1
        || !same(executableOccurrences.map((entry) => entry.url), expectedScriptUrls)
        || toolOccurrences.some((entry) => entry.origin !== "null")) {
      fail("loaded_production_script_occurrence_invalid", "production_closure",
          lifecycle + " raw CDP script occurrence/order/origin stream is not exact");
    }
    if (loaded.scriptOccurrences[loaded.scriptOccurrences.length - 1].url
        !== loaded.toolSourcePlan[loaded.toolSourcePlan.length - 1].url) {
      fail("loaded_production_tool_script_invalid", "production_closure",
        lifecycle + " terminal detach is not the final raw script occurrence");
    }
    const resourceOccurrenceKeys = ["frameId", "frameOrigin", "frameUrl", "mimeType",
      "occurrence", "origin", "rawFrame", "rawResource", "resourceKind", "resourceType",
      "sourceBase64", "sourceBytes", "sourceError", "sourceMethod", "sourceSha256", "url"];
    loaded.resourceOccurrences.forEach((entry, index) => {
      const document = entry && entry.resourceKind === "frame_document";
      if (!Evidence.isPlainObject(entry) || !same(Object.keys(entry).sort(), resourceOccurrenceKeys)
          || entry.occurrence !== index + 1 || !["frame_document", "frame_resource"]
            .includes(entry.resourceKind)
          || entry.frameId !== mainFrameId || entry.frameUrl !== pageScriptUrl
          || entry.frameOrigin !== "https://overlay.local" || !entry.url
          || entry.origin !== sourceOrigin(entry.url) || !Evidence.isPlainObject(entry.rawFrame)
          || String(entry.rawFrame.id || "") !== entry.frameId
          || String(entry.rawFrame.url || "") !== entry.frameUrl
          || document && entry.rawResource !== null
          || !document && (!Evidence.isPlainObject(entry.rawResource)
            || String(entry.rawResource.url || "") !== entry.url
            || String(entry.rawResource.type || "") !== entry.resourceType
            || String(entry.rawResource.mimeType || "") !== entry.mimeType)
          || entry.sourceMethod !== "Page.getResourceContent" || entry.sourceError !== null) {
        fail("loaded_production_resource_occurrence_invalid", "production_closure",
          lifecycle + " raw Page resource occurrence/order/frame stream drifted");
      }
      sourceBytes(entry, "loaded_production_resource_occurrence_invalid");
    });
    const pageResources = loaded.resourceOccurrences.filter((entry) =>
      entry.resourceKind === "frame_document");
    const resourceContract = closure.pageResourceContract;
    const iconRouteByName = new Map(resourceContract.iconRoutes.map((entry) => [entry.name, entry]));
    const missingIconNames = Array.from(relevantIconNames)
      .filter((name) => !iconRouteByName.has(name));
    if (missingIconNames.length !== 0) {
      fail("page_resource_contract_invalid", "production_closure",
        lifecycle + " rendered item icon names are absent from the canonical icon manifest", {
          missingIconNames,
        });
    }
    const dynamicIconRoutes = resourceContract.iconRoutes
      .filter((entry) => relevantIconNames.has(entry.name));
    const coreRoutes = [resourceContract.document, resourceContract.iconManifest]
      .concat(resourceContract.scripts,
      resourceContract.styles, resourceContract.fixedImages,
      resourceContract.conditionalAssets, resourceContract.fonts);
    const permittedRoutes = coreRoutes.concat(
      dynamicIconRoutes.flatMap((entry) => entry.resources));
    const routeByUrl = new Map();
    permittedRoutes.forEach((route) => {
      const previous = routeByUrl.get(route.url);
      if (previous && !same(previous, route)) {
        fail("page_resource_contract_invalid", "production_closure",
          lifecycle + " permitted resource URL has conflicting exact-byte routes", {
            url: route.url,
          });
      }
      routeByUrl.set(route.url, route);
    });
    const requiredUrls = new Set(coreRoutes.filter((entry) => entry.required)
      .concat(dynamicIconRoutes.flatMap((entry) =>
        entry.resources.filter((resource) => resource.required)))
      .map((entry) => entry.url));
    const actualByUrl = new Map();
    loaded.resourceOccurrences.forEach((entry) => {
      const route = routeByUrl.get(entry.url);
      if (!route || actualByUrl.has(entry.url)
          || entry.resourceType !== route.resourceType || entry.mimeType !== route.mimeType
          || entry.origin !== sourceOrigin(route.url)
          || (route.resourceType === "Document"
            ? entry.resourceKind !== "frame_document" : entry.resourceKind !== "frame_resource")) {
        fail("loaded_production_resource_occurrence_invalid", "production_closure",
          lifecycle + " Page resource is unknown, duplicated, or mistyped", {
            url: entry && entry.url, resourceType: entry && entry.resourceType,
          });
      }
      if (entry.sourceSha256 !== route.sha256 || entry.sourceBytes !== route.bytes) {
        fail("loaded_production_resource_mismatch", "production_closure",
          lifecycle + " Page resource differs from its exact current-tree/manifest bytes", {
            url: entry.url, locator: route.locator,
          });
      }
      actualByUrl.set(entry.url, entry);
    });
    const missingRequired = Array.from(requiredUrls).filter((url) => !actualByUrl.has(url));
    const styleOccurrences = loaded.resourceOccurrences.filter((entry) =>
      entry.resourceType === "Stylesheet");
    const resourceScriptOccurrences = loaded.resourceOccurrences.filter((entry) =>
      entry.resourceType === "Script");
    const fixedImageUrls = new Set(resourceContract.fixedImages.map((entry) => entry.url));
    const fixedImageOccurrences = loaded.resourceOccurrences.filter((entry) =>
      fixedImageUrls.has(entry.url));
    const actualUrlSet = new Set(loaded.resourceOccurrences.map((entry) => entry.url));
    const expectedGlobalRoutes = [resourceContract.document]
      .concat(resourceContract.scripts, resourceContract.styles,
        resourceContract.fixedImages,
        resourceContract.conditionalAssets.filter((entry) => actualUrlSet.has(entry.url)),
        [resourceContract.iconManifest],
        dynamicIconRoutes.flatMap((entry) => entry.resources
          .filter((resource) => resource.required || actualUrlSet.has(resource.url))),
        resourceContract.fonts.filter((entry) => entry.required || actualUrlSet.has(entry.url)));
    function expectedResourceProjection(route) {
      return {
        resourceKind: route.resourceType === "Document" ? "frame_document" : "frame_resource",
        frameId: mainFrameId,
        frameUrl: pageScriptUrl,
        frameOrigin: "https://overlay.local",
        url: route.url,
        origin: sourceOrigin(route.url),
        resourceType: route.resourceType,
        mimeType: route.mimeType,
        sourceMethod: "Page.getResourceContent",
        sourceSha256: route.sha256,
        sourceBytes: route.bytes,
      };
    }
    function actualResourceProjection(entry) {
      return {
        resourceKind: entry.resourceKind,
        frameId: entry.frameId,
        frameUrl: entry.frameUrl,
        frameOrigin: entry.frameOrigin,
        url: entry.url,
        origin: entry.origin,
        resourceType: entry.resourceType,
        mimeType: entry.mimeType,
        sourceMethod: entry.sourceMethod,
        sourceSha256: entry.sourceSha256,
        sourceBytes: entry.sourceBytes,
      };
    }
    const expectedGlobalProjection = expectedGlobalRoutes.map(expectedResourceProjection);
    const actualGlobalProjection = loaded.resourceOccurrences.map(actualResourceProjection);
    if (pageResources.length !== 1 || pageResources[0].occurrence !== 1
        || pageResources[0].url !== pageScriptUrl || missingRequired.length !== 0
        || !same(actualGlobalProjection, expectedGlobalProjection)
        || !same(resourceScriptOccurrences.map((entry) => entry.url),
          resourceContract.scripts.map((entry) => entry.url))
        || !same(styleOccurrences.map((entry) => entry.url), expectedStyleUrls)
        || !same(fixedImageOccurrences.map((entry) => entry.url),
          resourceContract.fixedImages.map((entry) => entry.url))
        || styleOccurrences.some((entry) => entry.origin !== "https://overlay.local"
          || entry.resourceKind !== "frame_resource" || entry.resourceType !== "Stylesheet")) {
      fail("loaded_production_resource_occurrence_invalid", "production_closure",
          lifecycle + " raw Page resource stream differs from the one canonical global occurrence sequence", {
            missingRequired,
          });
    }
    const pageExpected = expectedWeb.find((entry) => entry.role === "page");
    if (pageResources[0].sourceSha256 !== pageExpected.sha256
        || pageResources[0].sourceBytes !== pageExpected.bytes) {
      fail("loaded_production_resource_mismatch", "production_closure",
        lifecycle + " loaded page bytes differ from the current production closure");
    }
    executableOccurrences.forEach((occurrence, index) => {
      const expected = expectedScripts[index];
      if (occurrence.sourceSha256 !== expected.sha256 || occurrence.sourceBytes !== expected.bytes) {
        fail("loaded_production_script_source_binding_invalid", "production_closure",
          lifecycle + " production script bytes differ from the current production closure", {
            locator: expected.locator,
          });
      }
    });
    resourceScriptOccurrences.forEach((occurrence, index) => {
      const expected = resourceContract.scripts[index];
      if (occurrence.sourceSha256 !== expected.sha256 || occurrence.sourceBytes !== expected.bytes) {
        fail("loaded_production_resource_mismatch", "production_closure",
          lifecycle + " Page Script resource differs from its exact current-tree bytes", {
            locator: expected.locator,
          });
      }
    });
    styleOccurrences.forEach((occurrence, index) => {
      const expected = expectedStyles[index];
      if (occurrence.sourceSha256 !== expected.sha256 || occurrence.sourceBytes !== expected.bytes) {
        fail("loaded_production_style_source_binding_invalid", "production_closure",
          lifecycle + " stylesheet bytes differ from the current production closure", {
            locator: expected.locator,
          });
      }
    });
    const pageBytes = sourceBytes(pageResources[0], "loaded_production_inline_script_invalid");
    const inlineBytes = sourceBytes(pageOccurrences[0], "loaded_production_inline_script_invalid");
    if (pageBytes.indexOf(inlineBytes) < 0) {
      fail("loaded_production_inline_script_invalid", "production_closure",
        lifecycle + " inline Debugger source is absent from the exact page bytes");
    }
    if (!(options && options.testOnlyAllowInjectedEvidence === true
        && options.skipFileClosure === true)) {
      const pageFile = Evidence.readExactRegularFile(
        path.join(bundle.root, "launcher", "web", "overlay.html"), {
          phase: "production_closure", maximumBytes: 16 * 1024 * 1024,
        });
      const html = pageFile.bytes.toString("utf8");
      const inlineSources = [];
      const scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
      let match;
      while ((match = scriptPattern.exec(html)) !== null) {
        if (!/\bsrc\s*=/.test(match[1])) inlineSources.push(match[2]);
      }
      const expectedInlineBytes = inlineSources.length === 1
        ? Buffer.from(inlineSources[0], "utf8") : null;
      if (!expectedInlineBytes || !inlineBytes.equals(expectedInlineBytes)) {
        fail("loaded_production_inline_script_invalid", "production_closure",
          lifecycle + " inline CDP source bytes differ from the current loaded page source");
      }
    }
    return loaded;
  }
  return { closure, binding, candidateProducer, first: verifyLoaded(first, "first"),
    restart: verifyLoaded(restart, "restart") };
}

function verifyRuntime(bundle, firstSemantic, restartSemantic, options) {
  const runtime = requireObject(bundle.runtime, "runtime_invalid", "runtime", "runtime evidence is missing");
  const first = requireObject(runtime.first, "runtime_first_invalid", "runtime", "first lifecycle is missing");
  const restart = requireObject(runtime.restart, "runtime_restart_invalid", "runtime", "restart lifecycle is missing");
  RuntimeGuard.validateCandidateIdentity(first.identity, bundle.candidateRoot);
  RuntimeGuard.validateCandidateIdentity(restart.identity, bundle.candidateRoot);
  if (!same(RuntimeGuard.publicCandidateIdentity(first.identity), runtime.expectedIdentity)
      || !same(RuntimeGuard.publicCandidateIdentity(restart.identity), runtime.expectedIdentity)) {
    fail("candidate_identity_drift", "runtime", "resolved candidate identity changed across lifecycles");
  }
  const firstSession = LauncherObservation.verifySessionEvidenceEnvelope(first.sessionEvidence);
  const restartSession = LauncherObservation.verifySessionEvidenceEnvelope(restart.sessionEvidence);
  if (firstSession.pid !== first.identity.pid || restartSession.pid !== restart.identity.pid) {
    fail("session_pid_binding_invalid", "runtime", "authenticated sessions crossed runtime PID");
  }
  const firstProcessContract = verifyProcessContract(first.processContract, firstSession,
    first.identity, bundle.root);
  const restartProcessContract = verifyProcessContract(restart.processContract, restartSession,
    restart.identity, bundle.root);
  const production = verifyProduction(bundle, first, restart,
    firstSemantic, restartSemantic, options);
  const trusted = requireObject(runtime.trustedCdpExpectations,
    "cdp_trusted_expectations_missing", "runtime", "independent CDP expectations are missing");
  RuntimeGuard.assertRuntimeCdpBinding(first.cdpBinding, first.identity, trusted);
  RuntimeGuard.assertRuntimeCdpBinding(restart.cdpBinding, restart.identity, trusted);
  const freshIdentity = RuntimeGuard.assertFreshRestartIdentity({
    first: first.identity,
    restart: restart.identity,
    firstAttemptId: first.attemptId,
    restartAttemptId: restart.attemptId,
  });
  LauncherObservation.assertFreshAuthenticatedRestart({
    first: first.identity,
    restart: restart.identity,
    firstAttemptId: first.attemptId,
    restartAttemptId: restart.attemptId,
    firstSession,
    restartSession,
  });
  if (first.cdpBinding.port === restart.cdpBinding.port
      || first.cdpBinding.pageIdentity.timeOrigin === restart.cdpBinding.pageIdentity.timeOrigin) {
    fail("restart_cdp_not_fresh", "runtime", "restart reused CDP port/page lifetime");
  }
  const shutdownEvidence = requireObject(restart.shutdownEvidence,
    "authenticated_shutdown_missing", "runtime",
    "restart authenticated shutdown evidence is missing");
  const shutdownPayload = Object.assign({}, shutdownEvidence);
  delete shutdownPayload.evidenceSha256;
  const shutdownKeys = ["completedAt", "evidenceSha256", "pid", "requestedAt",
    "response", "schema", "sessionEvidenceSha256"].sort();
  if (!same(Object.keys(shutdownEvidence).sort(), shutdownKeys)
      || shutdownEvidence.schema
        !== "workbench-live-e2e.equipment.authenticated-shutdown.v1"
      || shutdownEvidence.pid !== restart.identity.pid
      || shutdownEvidence.sessionEvidenceSha256 !== restartSession.sessionEvidenceSha256
      || !Number.isFinite(Date.parse(shutdownEvidence.requestedAt))
      || !Number.isFinite(Date.parse(shutdownEvidence.completedAt))
      || Date.parse(shutdownEvidence.completedAt) < Date.parse(shutdownEvidence.requestedAt)
      || shutdownEvidence.evidenceSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(shutdownPayload))) {
    fail("authenticated_shutdown_invalid", "runtime",
      "restart shutdown evidence is malformed or detached from the authenticated lifecycle");
  }
  LauncherObservation.assertResponseSucceeded(shutdownEvidence.response,
    "authenticated_shutdown", "agent_control shutdown");
  return { first, restart, firstSession, restartSession, firstProcessContract,
    restartProcessContract, freshIdentity, production, shutdownEvidence };
}

function recordsForPhase(lifecycle) {
  LauncherObservation.verifyTerminalLogBoundary(lifecycle.startBoundary);
  LauncherObservation.verifyLogSnapshot(lifecycle.finalLogSnapshot);
  if (lifecycle.startBoundary.terminalSessionEvidenceSha256
      !== lifecycle.sessionEvidence.sessionEvidenceSha256
      || lifecycle.finalLogSnapshot.sessionEvidenceSha256
        !== lifecycle.sessionEvidence.sessionEvidenceSha256) {
    fail("host_log_session_mismatch", "host_log", "log boundary crossed authenticated lifecycle");
  }
  return { records: LauncherObservation.recordsAfterTerminalBoundary(
    lifecycle.startBoundary, lifecycle.finalLogSnapshot),
  capturedAt: lifecycle.finalLogSnapshot.capturedAt };
}

function verifyLifecycleTranscript(transcript, phase) {
  const ready = transcript.events.filter((event) => event.kind === "observer_ready");
  const bound = transcript.events.filter((event) => event.kind === "cdp_endpoint_bound");
  const detached = transcript.events.filter((event) => ["observer_detached",
    "observer_detach_transport_lost"].includes(event.kind));
  if (ready.length !== 1 || bound.length !== 1 || detached.length !== 1
      || !(bound[0].sequence < ready[0].sequence && ready[0].sequence < detached[0].sequence)) {
    fail("observer_lifecycle_invalid", phase, "observer attach/detach lifecycle is not exact");
  }
}

function verifyHost(bundle, runtimeResult, firstResult, restartResult) {
  const firstRecords = recordsForPhase(runtimeResult.first);
  const restartRecords = recordsForPhase(runtimeResult.restart);
  const firstMappings = Protocol.verifyHostMappings(firstRecords, firstResult.pairs, "first");
  const restartMappings = Protocol.verifyHostMappings(restartRecords, restartResult.pairs, "restart");
  const firstTimeline = Protocol.resolveHostTimeline(firstRecords, "first");
  const restartTimeline = Protocol.resolveHostTimeline(restartRecords, "restart");
  const all = firstMappings.concat(restartMappings);
  if (new Set(all.map((entry) => entry.webCallId)).size !== all.length) {
    fail("cross_lifecycle_web_call_id_reused", "host_log", "Web callId was reused across restart");
  }
  return { firstRecords, restartRecords, firstTimeline, restartTimeline,
    firstMappings, restartMappings };
}

function findTrustedInputs(transcript, predicate) {
  return transcript.events.filter((event) => event.kind === "dom_input"
    && event.isTrusted === true && predicate(event));
}

function exactOne(values, code, message) {
  if (values.length !== 1) fail(code, "control", message, { count: values.length });
  return values[0];
}

function verifyControl(bundle, firstResult, restartResult) {
  const control = requireObject(bundle.control, "control_invalid", "control", "control evidence is missing");
  if (control.capability.schema !== CAPABILITY_SCHEMA
      || control.selectedTransport !== "codex_computer_use"
      || control.fallbackAllowed !== true) {
    fail("control_capability_invalid", "control", "legacy lifecycle must explicitly select Codex CU fallback");
  }
  const capability = ControlContract.verifyCapabilityDecision({
    capability: control.capability,
    trustedSources: TRUSTED_CAPABILITY_SOURCES,
    selectedTransport: control.selectedTransport,
    preferredTransport: "launcher_agent_runtime",
    fallbackTransport: "codex_computer_use",
    fallbackAllowed: bundle.allowCodexCuFallback,
  });
  if (control.capability.available !== false
      || control.capability.artifact.agentRuntimeAdmission !== false
      || control.capability.artifact.processContractSha256
        !== bundle.runtime.first.processContract.artifactSha256) {
    fail("capability_process_contract_mismatch", "control",
      "fallback decision is not bound to authenticated legacy-only launch artifact");
  }
  if (!Array.isArray(control.requests) || !Array.isArray(control.acks)) {
    fail("control_set_count_invalid", "control",
      "control evidence must contain exact request and acknowledgement arrays");
  }
  const exchanges = ControlContract.assertExactControlSet({
    root: bundle.root,
    runDir: bundle.runDir,
    ownedBaseRelative: OWNED_BASE_RELATIVE,
    requests: control.requests,
    acks: control.acks,
    requiredSteps: REQUIRED_CONTROL_STEPS,
    requestSchema: require("./common").CONTROL_REQUEST_SCHEMA,
    ackSchema: require("./common").CONTROL_ACK_SCHEMA,
    allowedTransports: TRANSPORTS,
    allowedResults: RESULTS,
    maximumTtlMs: 3600000,
  });
  control.requests.forEach((request) => {
    validateRequest(request);
    if (request.runId !== bundle.runId) {
      fail("control_request_invalid", "control", "control request crossed run identity");
    }
  });
  control.acks.forEach((ack) => {
    const matches = control.requests.filter((request) => request.requestId === ack.requestId);
    if (matches.length !== 1) {
      fail("control_step_ack_invalid", "control",
        "control acknowledgement lacks one exact request", { requestId: ack.requestId });
    }
    validateAck(ack, matches[0]);
  });
  exchanges.forEach((exchange, step) => {
    if (exchange.ack.result !== "completed" || exchange.ack.transport !== control.selectedTransport) {
      fail("control_exchange_incomplete", "control", "control step was not completed by selected transport", { step });
    }
    verifyAckCapture(bundle.root, bundle.runDir, exchange.request, exchange.ack);
  });
  REQUIRED_CONTROL_STEPS.forEach((step, index) => {
    const exchange = exchanges.get(step);
    if (exchange.request.requiresCaptureSha256 !== true
        || !exchange.capture || !exchange.ack.capture
        || exchange.ack.captureSha256 !== exchange.capture.sha256) {
      fail("control_capture_policy_invalid", "control",
        "every one-shot provider result must bind one exact provider-owned capture", { step });
    }
    if (index > 0) {
      const previous = exchanges.get(REQUIRED_CONTROL_STEPS[index - 1]);
      if (Date.parse(previous.request.issuedAt) >= Date.parse(exchange.request.issuedAt)
          || Date.parse(previous.ack.completedAt) >= Date.parse(exchange.ack.completedAt)
          || Date.parse(previous.ack.completedAt) > Date.parse(exchange.request.issuedAt)) {
        fail("control_partial_order_invalid", "control",
          "control issue/ack chronology does not follow the frozen one-shot journey", {
            previous: REQUIRED_CONTROL_STEPS[index - 1], step,
          });
      }
    }
  });
  const slotSelector = "button[data-physical-slot=\"" + firstResult.initial.source.slot + "\"]";
  const expectedSelectors = {
    open_tuning: ["native HUD equipment tuning entry"],
    select_source: [slotSelector],
    preview_candidate_a: ["button[data-candidate-key=\"" + firstResult.candidateA.candidateKey + "\"]"],
    preview_candidate_b: ["button[data-candidate-key=\"" + firstResult.candidateB.candidateKey + "\"]"],
    commit_candidate_b: [".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]"],
    reselect_source: [slotSelector],
    close_first_tuning: ["button[data-header-action=\"close\"]"],
    safe_exit: ["native SAFEEXIT"],
    exit_confirm: ["native EXIT_CONFIRM"],
    restart_open_tuning: ["native HUD equipment tuning entry"],
    restart_select_source: [slotSelector],
    restart_close_tuning: ["button[data-header-action=\"close\"]"],
  };
  exchanges.forEach((exchange, step) => {
    if (!same(exchange.request.selectors, expectedSelectors[step])
        || typeof exchange.request.instructions !== "string"
        || !exchange.request.instructions.trim()
        || !Array.isArray(exchange.request.expectedIndependentEvidence)
        || exchange.request.expectedIndependentEvidence.length < 1) {
      fail("control_request_scope_invalid", "control",
        "control request does not describe the exact frozen UI step", { step });
    }
  });
  if (control.authorization.schema !== AUTHORIZATION_SCHEMA
      || control.authorization.allowedStep !== "commit_candidate_b"
      || control.authorization.scope.slot !== bundle.targetSlot
      || control.authorization.scope.candidateKey !== firstResult.candidateB.candidateKey
      || control.authorization.scope.operation !== "install_mod") {
    fail("authorization_scope_invalid", "control", "one-shot commit scope is not exact");
  }
  const authorization = ControlContract.verifyOneShotAuthorization({
    decision: control.authorization,
    decisionSha256: control.authorizationSha256,
    decisionSchema: AUTHORIZATION_SCHEMA,
    trustedSources: TRUSTED_AUTHORIZATION_SOURCES,
    requests: control.requests,
    acks: control.acks,
    expectedStep: "commit_candidate_b",
  });

  const firstEvents = bundle.transcripts.first.events;
  const sourceInputs = findTrustedInputs(bundle.transcripts.first, (event) => event.target
    && event.target.selector === slotSelector);
  if (sourceInputs.length !== 2) {
    fail("source_input_count_invalid", "control", "source must be selected and reselected exactly twice");
  }
  const candidateAInput = exactOne(findTrustedInputs(bundle.transcripts.first, (event) => event.target
    && event.target.selector === expectedSelectors.preview_candidate_a[0]),
  "candidate_a_input_invalid", "candidate A was not selected by one trusted input");
  const candidateBInput = exactOne(findTrustedInputs(bundle.transcripts.first, (event) => event.target
    && event.target.selector === expectedSelectors.preview_candidate_b[0]),
  "candidate_b_input_invalid", "candidate B was not selected by one trusted input");
  const commitInput = exactOne(findTrustedInputs(bundle.transcripts.first, (event) => event.target
    && event.target.selector === expectedSelectors.commit_candidate_b[0]),
  "commit_input_invalid", "commit was not triggered by one trusted production control");
  const previewARequest = firstResult.pairs.tuning[1].requestEvent;
  const previewBRequest = firstResult.pairs.tuning[2].requestEvent;
  const commitRequest = firstResult.pairs.tuning[3].requestEvent;
  const freshRequest = firstResult.pairs.tuning[4].requestEvent;
  if (!(sourceInputs[0].sequence < firstResult.pairs.tuning[0].requestEvent.sequence
      && candidateAInput.sequence < previewARequest.sequence
      && previewARequest.sequence < candidateBInput.sequence
      && candidateBInput.sequence < previewBRequest.sequence
      && previewBRequest.sequence < commitInput.sequence
      && commitInput.sequence < commitRequest.sequence
      && commitRequest.sequence < sourceInputs[1].sequence
      && sourceInputs[1].sequence < freshRequest.sequence)) {
    fail("trusted_input_order_invalid", "control", "trusted Equipment input/authority order is invalid");
  }
  const restartSource = exactOne(findTrustedInputs(bundle.transcripts.restart, (event) => event.target
    && event.target.selector === slotSelector),
  "restart_source_input_invalid", "restart source was not selected exactly once");
  if (restartSource.sequence >= restartResult.pairs.tuning[0].requestEvent.sequence) {
    fail("restart_source_input_order_invalid", "control", "restart source input did not precede readback");
  }
  if (firstEvents.some((event) => event.kind === "dom_input" && event.isTrusted !== true
      && event.target && event.target.mutationCapable === true)) {
    fail("untrusted_mutation_input_observed", "control", "untrusted mutation-capable DOM input was observed");
  }
  const firstCloseInput = exactOne(findTrustedInputs(bundle.transcripts.first, (event) => event.target
    && event.target.selector === expectedSelectors.close_first_tuning[0]),
  "first_close_input_invalid", "first close was not one trusted exact button input");
  const restartCloseInput = exactOne(findTrustedInputs(bundle.transcripts.restart,
    (event) => event.target
      && event.target.selector === expectedSelectors.restart_close_tuning[0]),
  "restart_close_input_invalid", "restart close was not one trusted exact button input");
  const providerOperationIds = new Set();
  const providerCapturePaths = new Set();
  const providerCaptureDigests = new Set();
  const providerCaptureEventIds = new Set();
  const providerCaptureEventRefs = new Set();
  const providerEventRefs = new Set();
  const expectedDomEvents = new Map([
    ["select_source", [bundle.transcripts.first, sourceInputs[0]]],
    ["preview_candidate_a", [bundle.transcripts.first, candidateAInput]],
    ["preview_candidate_b", [bundle.transcripts.first, candidateBInput]],
    ["commit_candidate_b", [bundle.transcripts.first, commitInput]],
    ["reselect_source", [bundle.transcripts.first, sourceInputs[1]]],
    ["close_first_tuning", [bundle.transcripts.first, firstCloseInput]],
    ["restart_select_source", [bundle.transcripts.restart, restartSource]],
    ["restart_close_tuning", [bundle.transcripts.restart, restartCloseInput]],
  ]);
  exchanges.forEach((exchange, step) => {
    const provider = verifyProviderReceiptReference(bundle.root, bundle.runDir,
      exchange.request, exchange.ack);
    const operationId = provider.receipt.providerOperationId;
    if (providerOperationIds.has(operationId)) {
      fail("provider_operation_id_reused", "control",
        "provider operation id must be unique across the 12 one-shot controls", { step });
    }
    providerOperationIds.add(operationId);
    if (providerCapturePaths.has(provider.capture.relativePath)
        || providerCaptureDigests.has(provider.capture.sha256)) {
      fail("provider_capture_reused", "control",
        "provider capture path and bytes must be unique across one-shot controls", { step });
    }
    providerCapturePaths.add(provider.capture.relativePath);
    providerCaptureDigests.add(provider.capture.sha256);
    const captureEvent = provider.captureEvent.value;
    const captureEventReferenceKey = provider.captureEvent.relativePath + ":"
      + provider.captureEvent.file.sha256 + ":" + captureEvent.eventSha256;
    if (providerCaptureEventIds.has(captureEvent.providerEventId)
        || providerCaptureEventRefs.has(captureEventReferenceKey)) {
      fail("provider_capture_event_reused", "control",
        "trusted provider capture event identity/reference must be unique across controls", { step });
    }
    providerCaptureEventIds.add(captureEvent.providerEventId);
    providerCaptureEventRefs.add(captureEventReferenceKey);
    const domBinding = expectedDomEvents.get(step);
    let eventTime;
    let referenceKey;
    if (domBinding) {
      const expectedInput = domInputEvidence(domBinding[0].observerId, domBinding[1]);
      referenceKey = "web:" + expectedInput.eventRef.observerId + ":" + expectedInput.eventRef.sequence
        + ":" + expectedInput.eventRef.eventSha256;
      if (!same(provider.receipt.inputEvidence, expectedInput)
          || providerEventRefs.has(referenceKey)) {
        fail("provider_dom_event_binding_invalid", "control",
          "provider operation is not in one strict request-to-DOM-event-to-capture bijection", {
            step, referenceKey,
          });
      }
      eventTime = domBinding[1].observedAt;
    } else if (provider.receipt.inputEvidence.kind !== "native_input"
        || provider.receipt.inputEvidence.tagName !== "NATIVE"
        || !provider.nativeInputEvent) {
      fail("provider_native_input_binding_invalid", "control",
        "native provider operation lacks one exact provider-owned target contract", { step });
    } else {
      const reference = provider.receipt.inputEvidence.eventRef;
      referenceKey = "native:" + reference.artifact + ":" + reference.sha256 + ":"
        + reference.eventSha256;
      if (providerEventRefs.has(referenceKey)) {
        fail("provider_native_input_binding_invalid", "control",
          "native input event reference was reused across one-shot controls", { step });
      }
      eventTime = provider.nativeInputEvent.eventTime;
    }
    const requestAt = Date.parse(exchange.request.issuedAt);
    const startedAt = Date.parse(provider.receipt.startedAt);
    const inputAt = Date.parse(provider.receipt.inputEvidence.observedAt);
    const captureAt = Date.parse(captureEvent.capturedAt);
    const fileModifiedAt = Date.parse(captureEvent.fileModifiedAt);
    const providerAt = Date.parse(provider.receipt.completedAt);
    const ackAt = Date.parse(exchange.ack.completedAt);
    if (!Number.isFinite(Date.parse(eventTime)) || Date.parse(eventTime) !== inputAt
        || !(requestAt < startedAt && startedAt <= inputAt && inputAt < captureAt
          && captureAt <= fileModifiedAt && fileModifiedAt < providerAt && providerAt < ackAt)) {
      fail("provider_input_time_binding_invalid", "control",
        "control timing is not request < start <= input < capture < completion < acknowledgement", {
          step, request: exchange.request.issuedAt, started: provider.receipt.startedAt,
          input: provider.receipt.inputEvidence.observedAt,
          capture: captureEvent.capturedAt, fileModified: captureEvent.fileModifiedAt,
          completed: provider.receipt.completedAt, acknowledgement: exchange.ack.completedAt,
        });
    }
    providerEventRefs.add(referenceKey);
    exchange.inputEventTime = eventTime;
    exchange.providerReceipt = provider.receipt;
    exchange.providerCaptureEvent = captureEvent;
  });
  if (providerEventRefs.size !== REQUIRED_CONTROL_STEPS.length
      || providerCaptureEventIds.size !== REQUIRED_CONTROL_STEPS.length
      || providerCaptureEventRefs.size !== REQUIRED_CONTROL_STEPS.length) {
    fail("provider_input_event_binding_invalid", "control",
      "provider input/capture event binding set has gaps, extras, or reuse");
  }
  return { capability, exchanges, authorization,
    browserTrustedInput: { candidateA: candidateAInput.sequence,
      candidateB: candidateBInput.sequence, commit: commitInput.sequence,
      firstClose: firstCloseInput, restartClose: restartCloseInput },
  };
}

function verifyDiskRecord(record, expectedEquipment, expectedMaterials, expectedSource, phase) {
  requireObject(record, "disk_record_invalid", phase, "disk semantic record is missing");
  const persisted = record.persistedSource;
  const expectedProjection = {
    name: String(expectedEquipment.name || expectedEquipment.itemName || ""),
    level: Number(expectedEquipment.level != null
      ? expectedEquipment.level : expectedEquipment.enhancementLevel),
    tier: expectedEquipment.tier == null ? "" : String(expectedEquipment.tier),
    mods: Array.isArray(expectedEquipment.mods) ? expectedEquipment.mods.slice() : [],
    lastUpdate: Number(expectedEquipment.lastUpdate),
  };
  if (!/^[a-f0-9]{64}$/.test(String(record.sha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(record.semanticSha256 || ""))
      || !Number.isInteger(record.bytes) || record.bytes < 1
      || !Number.isInteger(record.textCharacters) || record.textCharacters < 1
      || !same(record.equipment, expectedProjection)
      || !same(record.materials, expectedMaterials)
      || !Evidence.isPlainObject(persisted)
      || persisted.containerId !== expectedSource.containerId
      || persisted.slot !== expectedSource.slot
      || persisted.name !== (expectedEquipment.itemName || expectedEquipment.name)
      || Number(persisted.lastUpdate) !== Number(expectedEquipment.lastUpdate)
      || !/^[a-f0-9]{64}$/.test(String(persisted.valueSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(persisted.recordSha256 || ""))) {
    fail("disk_record_invalid", phase, "disk semantic record does not match authority state");
  }
  const semanticProjection = { equipment: record.equipment,
    materials: record.materials, persistedSource: record.persistedSource };
  if (record.semanticSha256 !== Evidence.sha256Text(
    Evidence.canonicalJson(semanticProjection))) {
    fail("disk_semantic_digest_invalid", phase,
      "disk semantic digest does not bind its published projection");
  }
  return record;
}

function materialTotals(snapshot) {
  const output = {};
  snapshot.materials.forEach((entry) => { output[entry.itemName] = entry.count; });
  return output;
}

function verifyRelease(release, persistence) {
  verifyDigestObject(release, "releaseSha256", "clone_release_invalid", "persistence");
  if (release.schema !== CloneGuard.RELEASE_SCHEMA || release.apiVersion !== "FROZEN-v1"
      || release.backupsVerified !== true || release.lockRelease.lockFileAbsent !== true
      || release.lockRelease.terminalPrivateRelease !== true
      || release.recoveryClear.recoveryFileAbsent !== true) {
    fail("clone_release_invalid", "persistence", "clone lock/recovery release is incomplete");
  }
  CloneGuard.verifyArtifactSet(release.seedEnd);
  CloneGuard.verifyArtifactSet(release.targetEnd);
  CloneGuard.assertArtifactSetInvariant(persistence.seedBegin, release.seedEnd,
    "seed_artifact_set_changed");
  if (!same(release.targetEnd, persistence.afterRestart)) {
    fail("target_release_set_mismatch", "persistence", "released target set differs from restart readback set");
  }
  return release;
}

function verifyStableArtifactPhase(phase, expectedSet, phaseName) {
  requireObject(phase, "clone_phase_invalid", phaseName, "stable clone phase is missing");
  const payload = Object.assign({}, phase);
  delete payload.evidenceSha256;
  if (phase.schema !== "workbench-live-e2e.stable-slot-artifact-set.v1"
      || phase.apiVersion !== "FROZEN-v1" || !Number.isInteger(phase.stableMs)
      || phase.stableMs < 1 || !Number.isInteger(phase.samples) || phase.samples < 2
      || !Number.isFinite(Date.parse(phase.observedAt))
      || !/^[a-f0-9]{64}$/.test(String(phase.evidenceSha256 || ""))
      || Evidence.sha256Text(Evidence.canonicalJson(payload)) !== phase.evidenceSha256) {
    fail("clone_phase_invalid", phaseName, "stable clone phase is malformed or changed");
  }
  CloneGuard.verifyArtifactSet(phase.set);
  if (!same(phase.set, expectedSet)) {
    fail("clone_phase_set_mismatch", phaseName,
      "stable clone phase does not bind the persistence artifact set");
  }
  return phase;
}

function verifyPersistence(bundle, firstResult, restartResult) {
  const value = requireObject(bundle.persistence, "persistence_invalid", "persistence",
    "clone/disk persistence evidence is missing");
  [value.seedBegin, value.seedEnd, value.targetPrepared, value.afterCommit,
    value.afterRestart].forEach(CloneGuard.verifyArtifactSet);
  const stability = requireObject(value.stability, "clone_stability_missing", "persistence",
    "stable artifact evidence is missing");
  verifyStableArtifactPhase(stability.targetPrepared, value.targetPrepared,
    "persistence.target_prepared");
  verifyStableArtifactPhase(stability.afterCommit, value.afterCommit,
    "persistence.after_commit");
  verifyStableArtifactPhase(stability.afterRestart, value.afterRestart,
    "persistence.after_restart");
  CloneGuard.assertArtifactSetInvariant(value.seedBegin, value.seedEnd, "seed_artifact_set_changed");
  CloneGuard.assertArtifactSetInvariant(value.afterCommit, value.afterRestart,
    "restart_artifact_set_changed");
  if (value.targetPrepared.slot !== bundle.targetSlot || value.afterCommit.slot !== bundle.targetSlot
      || value.seedBegin.slot !== bundle.seedSlot || value.seedEnd.slot !== bundle.seedSlot
      || value.targetPrepared.setSha256 === value.afterCommit.setSha256) {
    fail("persistence_artifact_scope_invalid", "persistence", "clone artifact set roles are invalid");
  }
  const beforeMaterials = materialTotals(firstResult.initial);
  const afterMaterials = materialTotals(firstResult.fresh);
  const initialDisk = verifyDiskRecord(value.diskInitial,
    firstResult.previewB.before.equipment.raw, beforeMaterials, firstResult.initial.source,
    "persistence.initial");
  const commitDisk = verifyDiskRecord(value.diskAfterCommit,
    firstResult.commit.after.equipment.raw, afterMaterials, firstResult.initial.source,
    "persistence.commit");
  const restartDisk = verifyDiskRecord(value.diskAfterRestart,
    restartResult.readback.equipment.raw, afterMaterials, restartResult.readback.source,
    "persistence.restart");
  if (initialDisk.sha256 === commitDisk.sha256 || initialDisk.semanticSha256 === commitDisk.semanticSha256
      || commitDisk.sha256 !== restartDisk.sha256
      || commitDisk.semanticSha256 !== restartDisk.semanticSha256
      || commitDisk.bytes !== restartDisk.bytes
      || commitDisk.textCharacters !== restartDisk.textCharacters) {
    fail("disk_persistence_invalid", "persistence", "disk before/commit/restart identity is not exact");
  }
  if (initialDisk.persistedSource.recordSha256 === commitDisk.persistedSource.recordSha256
      || !same(commitDisk.persistedSource, restartDisk.persistedSource)) {
    fail("disk_source_record_persistence_invalid", "persistence",
      "persisted source record did not change once and remain exact across restart");
  }
  const archive = verifyDigestObject(value.archiveEvidence, "evidenceSha256",
    "archive_evidence_invalid", "persistence");
  if (archive.schema !== LauncherObservation.ARCHIVE_SCHEMA
      || archive.apiVersion !== "FROZEN-v1"
      || !same(archive.requiredOrder, ["sv1", "sv2", "archive"])
      || archive.disk.slot !== bundle.targetSlot
      || archive.disk.sha256 !== commitDisk.sha256
      || archive.disk.bytes !== commitDisk.bytes
      || archive.disk.textCharacters !== commitDisk.textCharacters) {
    fail("archive_evidence_invalid", "persistence", "SAFEEXIT archive does not bind committed disk bytes");
  }
  const release = verifyRelease(value.release, value);
  return { initialDisk, commitDisk, restartDisk, archive, release };
}

function verifyResidue(bundle) {
  LauncherObservation.assertResidueClean(bundle.residue.afterSafeExit);
  LauncherObservation.assertResidueClean(bundle.residue.final);
  if (bundle.residue.afterSafeExit.expectedPid !== bundle.runtime.first.identity.pid
      || bundle.residue.final.expectedPid !== bundle.runtime.restart.identity.pid) {
    fail("residue_pid_mismatch", "residue", "residue proof crossed runtime PID");
  }
  return bundle.residue;
}

const STRICT_GLOBAL_BOUNDARY_LABELS = Object.freeze([
  "final_commit_response", "close_request", "close_operation_started", "close_dom_input",
  "panel_host_closed", "close_capture", "close_provider_completed", "close_ack",
  "first_loaded", "safeexit_request", "safeexit_operation_started", "safeexit_native_input",
  "sv1", "sv2", "archive", "safeexit_capture", "safeexit_provider_completed",
  "safeexit_ack", "archive_disk", "exit_confirm_request", "exit_confirm_operation_started",
  "exit_confirm_native_input", "exit_confirm_capture", "exit_confirm_provider_completed",
  "exit_confirm_ack", "first_shutdown_residue", "restart_open_request",
  "restart_open_operation_started", "restart_open_native_input", "restart_open_capture",
  "restart_open_provider_completed", "restart_open_ack", "restart_close_request",
  "restart_close_operation_started", "restart_close_dom_input", "restart_panel_host_closed",
  "restart_close_capture", "restart_close_provider_completed", "restart_close_ack",
  "restart_loaded", "restart_shutdown_request", "restart_shutdown_completion",
  "restart_shutdown_residue",
]);

function assertStrictBoundaryChain(boundaries) {
  if (!Array.isArray(boundaries)
      || !same(boundaries.map((entry) => entry && entry[0]), STRICT_GLOBAL_BOUNDARY_LABELS)
      || boundaries.some((entry) => !Array.isArray(entry) || entry.length !== 2
        || !Number.isFinite(Date.parse(entry[1])))) {
    fail("global_partial_order_invalid", "order",
      "global timeline boundary set is missing, extra, reordered, or not comparable");
  }
  for (let index = 1; index < boundaries.length; index += 1) {
    if (Date.parse(boundaries[index - 1][1]) >= Date.parse(boundaries[index][1])) {
      fail("global_partial_order_invalid", "order",
        "commit, close, SAFEEXIT, archive, EXIT_CONFIRM, restart close, and residue are not one strict comparable timeline",
        { badPair: [boundaries[index - 1][0], boundaries[index][0]] });
    }
  }
  return boundaries;
}

function verifyGlobalPartialOrder(runtime, host, control, persistence, residue) {
  const firstDetach = host.firstMappings.find((entry) => entry.ownerCloseReceipt);
  const restartDetach = host.restartMappings.find((entry) => entry.ownerCloseReceipt);
  const commitMapping = host.firstMappings.find((entry) => entry.commitReceipt);
  const safeExit = control.exchanges.get("safe_exit");
  const exitConfirm = control.exchanges.get("exit_confirm");
  const firstClose = control.exchanges.get("close_first_tuning");
  const restartOpen = control.exchanges.get("restart_open_tuning");
  const restartClose = control.exchanges.get("restart_close_tuning");
  if (!commitMapping || !firstDetach || !restartDetach || !firstClose
      || !safeExit || !exitConfirm || !restartOpen || !restartClose) {
    fail("global_partial_order_invalid", "order",
      "global close/control/persistence order lacks one required boundary");
  }
  const archivePositions = persistence.archive.positions;
  function atLine(records, position, label) {
    const matches = records.filter((record) => record.lineNumber === position.lineNumber);
    if (matches.length !== 1 || !matches[0].observedAt) {
      fail("global_timeline_record_missing", "order",
        "global timeline position lacks one timestamped Host record", { label });
    }
    return matches[0];
  }
  if (!archivePositions || !archivePositions.sv1 || !archivePositions.sv2
      || !archivePositions.archive) {
    fail("global_partial_order_invalid", "order", "archive marker positions are incomplete");
  }
  const sv1Record = atLine(host.firstTimeline, archivePositions.sv1, "sv1");
  const sv2Record = atLine(host.firstTimeline, archivePositions.sv2, "sv2");
  const archiveRecord = atLine(host.firstTimeline, archivePositions.archive, "archive");
  if (!/(?:^|\s)sv:1(?:$|\s)/.test(sv1Record.line)
      || !/(?:^|\s)sv:2(?:$|\s)/.test(sv2Record.line)
      || !archiveRecord.line.startsWith("[ArchiveTask] Shadow saved:")) {
    fail("global_timeline_record_invalid", "order",
      "archive positions do not point to the exact sv1/sv2/archive Host records");
  }
  const boundaries = [
    ["final_commit_response", commitMapping.commitReceipt.observedAt],
    ["close_request", firstClose.request.issuedAt],
    ["close_operation_started", firstClose.providerReceipt.startedAt],
    ["close_dom_input", firstClose.providerReceipt.inputEvidence.observedAt],
    ["panel_host_closed", firstDetach.ownerCloseReceipt.observedAt],
    ["close_capture", firstClose.providerCaptureEvent.capturedAt],
    ["close_provider_completed", firstClose.providerReceipt.completedAt],
    ["close_ack", firstClose.ack.completedAt],
    ["first_loaded", runtime.production.first.capturedAt],
    ["safeexit_request", safeExit.request.issuedAt],
    ["safeexit_operation_started", safeExit.providerReceipt.startedAt],
    ["safeexit_native_input", safeExit.providerReceipt.inputEvidence.observedAt],
    ["sv1", sv1Record.observedAt],
    ["sv2", sv2Record.observedAt],
    ["archive", archiveRecord.observedAt],
    ["safeexit_capture", safeExit.providerCaptureEvent.capturedAt],
    ["safeexit_provider_completed", safeExit.providerReceipt.completedAt],
    ["safeexit_ack", safeExit.ack.completedAt],
    ["archive_disk", persistence.archive.disk.capturedAt],
    ["exit_confirm_request", exitConfirm.request.issuedAt],
    ["exit_confirm_operation_started", exitConfirm.providerReceipt.startedAt],
    ["exit_confirm_native_input", exitConfirm.providerReceipt.inputEvidence.observedAt],
    ["exit_confirm_capture", exitConfirm.providerCaptureEvent.capturedAt],
    ["exit_confirm_provider_completed", exitConfirm.providerReceipt.completedAt],
    ["exit_confirm_ack", exitConfirm.ack.completedAt],
    ["first_shutdown_residue", residue.afterSafeExit.observedAt],
    ["restart_open_request", restartOpen.request.issuedAt],
    ["restart_open_operation_started", restartOpen.providerReceipt.startedAt],
    ["restart_open_native_input", restartOpen.providerReceipt.inputEvidence.observedAt],
    ["restart_open_capture", restartOpen.providerCaptureEvent.capturedAt],
    ["restart_open_provider_completed", restartOpen.providerReceipt.completedAt],
    ["restart_open_ack", restartOpen.ack.completedAt],
    ["restart_close_request", restartClose.request.issuedAt],
    ["restart_close_operation_started", restartClose.providerReceipt.startedAt],
    ["restart_close_dom_input", restartClose.providerReceipt.inputEvidence.observedAt],
    ["restart_panel_host_closed", restartDetach.ownerCloseReceipt.observedAt],
    ["restart_close_capture", restartClose.providerCaptureEvent.capturedAt],
    ["restart_close_provider_completed", restartClose.providerReceipt.completedAt],
    ["restart_close_ack", restartClose.ack.completedAt],
    ["restart_loaded", runtime.production.restart.capturedAt],
    ["restart_shutdown_request", runtime.shutdownEvidence.requestedAt],
    ["restart_shutdown_completion", runtime.shutdownEvidence.completedAt],
    ["restart_shutdown_residue", residue.final.observedAt],
  ];
  assertStrictBoundaryChain(boundaries);
  return { clock: "utc_iso8601_from_provider_cdp_and_host_prefix",
    boundaries: Object.fromEntries(boundaries),
    firstCloseLineNumber: firstDetach.ownerCloseReceipt.lineNumber,
    restartCloseLineNumber: restartDetach.ownerCloseReceipt.lineNumber };
}

function verifySemanticBundle(bundle, options) {
  const settings = options || {};
  validateEnvelope(bundle, settings);
  verifyLifecycleTranscript(bundle.transcripts.first, "first");
  verifyLifecycleTranscript(bundle.transcripts.restart, "restart");
  const first = Protocol.verifyFirstTranscript(bundle.transcripts.first);
  const restart = Protocol.verifyRestartTranscript(bundle.transcripts.restart, first);
  const inventory = Protocol.verifyInventory(bundle.transcripts.first,
    bundle.transcripts.restart, first, restart);
  const runtime = verifyRuntime(bundle, first, restart, settings);
  const host = verifyHost(bundle, runtime, first, restart);
  const control = verifyControl(bundle, first, restart);
  const persistence = verifyPersistence(bundle, first, restart);
  const residue = verifyResidue(bundle);
  const partialOrder = verifyGlobalPartialOrder(runtime, host, control, persistence, residue);
  if (settings.skipFileClosure === true && settings.testOnlyAllowInjectedEvidence !== true) {
    fail("test_only_bypass_forbidden", "bundle", "file-closure bypass is test-only");
  }
  return { runtime, first, restart, inventory, host, control, persistence, residue,
    partialOrder };
}

const PRESEAL_FREEZE_SCHEMA = "workbench-live-e2e.equipment.preseal-artifact-freeze.v1";
const NATIVE_PRESEAL_CONTROL_STEPS = new Set([
  "open_tuning", "safe_exit", "exit_confirm", "restart_open_tuning",
]);
const PRESEAL_SIDECARS = Object.freeze([
  { relativePath: "evidence/host-first-final-log.json", role: "host_log_snapshot",
    valueOf: (bundle) => bundle.runtime.first.finalLogSnapshot },
  { relativePath: "evidence/host-restart-final-log.json", role: "host_log_snapshot",
    valueOf: (bundle) => bundle.runtime.restart.finalLogSnapshot },
  { relativePath: "evidence/persistence.json", role: "persistence_evidence",
    valueOf: (bundle) => bundle.persistence },
]);

function persistPreSealSidecars(bundle) {
  PRESEAL_SIDECARS.forEach((entry) => {
    atomicWriteJson(path.join(bundle.runDir, entry.relativePath.replace(/\//g, path.sep)),
      entry.valueOf(bundle));
  });
  return PRESEAL_SIDECARS.map((entry) => entry.relativePath);
}

function expectedPreSealArtifactContracts(bundle) {
  const contracts = [];
  ["first", "restart"].forEach((phase) => {
    const prefix = "equipment-" + phase + "-passive-transcript";
    contracts.push({ relativePath: prefix + ".json", role: "raw_transcript",
      expectedJson: bundle.transcripts[phase] });
    contracts.push({ relativePath: prefix + ".jsonl", role: "raw_transcript",
      expectedEvents: bundle.transcripts[phase].events });
  });
  bundle.control.requests.forEach((request) => {
    contracts.push({ relativePath: "control/requests/" + request.requestId + ".json",
      role: "control_request", expectedJson: request });
  });
  bundle.control.acks.forEach((ack) => {
    contracts.push({ relativePath: ack.providerReceipt.artifact, role: "provider_receipt",
      expectedSha256: ack.providerReceipt.sha256 });
    contracts.push({ relativePath: "control/capture-events/" + ack.requestId + ".json",
      role: "provider_capture_event" });
    contracts.push({ relativePath: "control/acks/" + ack.requestId + ".json",
      role: "control_ack", expectedJson: ack });
    contracts.push({ relativePath: ack.capture.relativePath, role: "provider_capture",
      expectedSha256: ack.capture.sha256, expectedBytes: ack.capture.bytes });
    if (NATIVE_PRESEAL_CONTROL_STEPS.has(ack.step)) {
      contracts.push({ relativePath: "control/native-input-events/" + ack.requestId + ".json",
        role: "native_input_event" });
    }
  });
  PRESEAL_SIDECARS.forEach((entry) => contracts.push({ relativePath: entry.relativePath,
    role: entry.role, expectedJson: entry.valueOf(bundle) }));
  contracts.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  if (new Set(contracts.map((entry) => entry.relativePath.toLowerCase())).size
      !== contracts.length) {
    fail("preseal_artifact_set_invalid", "preseal_artifacts",
      "pre-seal artifact contract contains a duplicate or aliased path");
  }
  return contracts;
}

function verifyExactPreSealFileSets(bundle, contracts) {
  function exactDirectory(relativeDir) {
    const expected = contracts.filter((entry) => path.posix.dirname(entry.relativePath)
      === relativeDir).map((entry) => entry.relativePath).sort();
    const absolute = path.join(bundle.runDir, relativeDir.replace(/\//g, path.sep));
    let entries;
    try { entries = fs.readdirSync(absolute, { withFileTypes: true }); }
    catch (_error) {
      fail("preseal_artifact_set_invalid", "preseal_artifacts",
        "required pre-seal artifact directory is missing", { relativeDir });
    }
    if (entries.some((entry) => !entry.isFile() || entry.isSymbolicLink())) {
      fail("preseal_artifact_set_invalid", "preseal_artifacts",
        "pre-seal artifact directory contains a non-regular entry", { relativeDir });
    }
    const actual = entries.map((entry) => relativeDir + "/" + entry.name).sort();
    if (!same(actual, expected)) {
      fail("preseal_artifact_set_invalid", "preseal_artifacts",
        "pre-seal artifact directory has an extra, missing, or renamed file", {
          relativeDir, actual, expected,
        });
    }
  }
  ["control/requests", "control/provider-receipts", "control/capture-events", "control/acks",
    "control/captures", "control/native-input-events", "evidence"].forEach(exactDirectory);
  const transcriptExpected = contracts.filter((entry) => entry.role === "raw_transcript")
    .map((entry) => entry.relativePath).sort();
  const transcriptActual = fs.readdirSync(bundle.runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && /-passive-transcript\.(?:json|jsonl)$/.test(entry.name))
    .map((entry) => entry.name).sort();
  if (!same(transcriptActual, transcriptExpected)) {
    fail("preseal_artifact_set_invalid", "preseal_artifacts",
      "pre-seal transcript file set has extras, omissions, or renamed entries");
  }
}

function verifyPreSealContractContent(contract, file) {
  if (contract.expectedSha256 && file.sha256 !== contract.expectedSha256
      || Number.isInteger(contract.expectedBytes) && file.length !== contract.expectedBytes) {
    fail("preseal_artifact_reference_mismatch", "preseal_artifacts",
      "pre-seal artifact bytes differ from their ACK/provider reference", {
        relativePath: contract.relativePath,
      });
  }
  if (Object.prototype.hasOwnProperty.call(contract, "expectedJson")) {
    let value;
    try { value = JSON.parse(file.bytes.toString("utf8")); }
    catch (error) {
      fail("preseal_artifact_content_invalid", "preseal_artifacts",
        "pre-seal JSON artifact is malformed", {
          relativePath: contract.relativePath, message: error.message,
        });
    }
    if (!same(value, contract.expectedJson)) {
      fail("preseal_artifact_content_invalid", "preseal_artifacts",
        "pre-seal JSON artifact differs from its verified bundle projection", {
          relativePath: contract.relativePath,
        });
    }
  }
  if (Object.prototype.hasOwnProperty.call(contract, "expectedEvents")) {
    const text = file.bytes.toString("utf8");
    let values;
    try {
      values = text.endsWith("\n") && text.length > 1
        ? text.slice(0, -1).split("\n").map((line) => JSON.parse(line)) : null;
    } catch (_error) { values = null; }
    if (!values || !same(values, contract.expectedEvents)) {
      fail("preseal_artifact_content_invalid", "preseal_artifacts",
        "pre-seal transcript JSONL differs from its verified event stream", {
          relativePath: contract.relativePath,
        });
    }
  }
}

function capturePreSealArtifactFreeze(bundle) {
  const contracts = expectedPreSealArtifactContracts(bundle);
  verifyExactPreSealFileSets(bundle, contracts);
  const entries = contracts.map((contract) => {
    const absolutePath = path.resolve(bundle.runDir,
      contract.relativePath.replace(/\//g, path.sep));
    const file = Evidence.readExactRegularFile(absolutePath, {
      phase: "preseal_artifacts", maximumBytes: 128 * 1024 * 1024,
    });
    verifyPreSealContractContent(contract, file);
    return { relativePath: contract.relativePath, role: contract.role,
      bytes: file.length, sha256: file.sha256, rawBase64: file.bytes.toString("base64") };
  });
  const freeze = { schema: PRESEAL_FREEZE_SCHEMA, entries };
  freeze.freezeSha256 = Evidence.sha256Text(Evidence.canonicalJson(freeze));
  return freeze;
}

function verifyPreSealArtifactFreeze(bundle, freeze, artifactManifest) {
  const payload = Object.assign({}, freeze);
  delete payload.freezeSha256;
  const contracts = expectedPreSealArtifactContracts(bundle);
  const entryKeys = ["bytes", "rawBase64", "relativePath", "role", "sha256"];
  if (!Evidence.isPlainObject(freeze) || freeze.schema !== PRESEAL_FREEZE_SCHEMA
      || !Array.isArray(freeze.entries)
      || freeze.freezeSha256 !== Evidence.sha256Text(Evidence.canonicalJson(payload))
      || !same(freeze.entries.map((entry) => [entry.relativePath, entry.role]),
        contracts.map((entry) => [entry.relativePath, entry.role]))) {
    fail("preseal_artifact_freeze_invalid", "preseal_artifacts",
      "pre-seal artifact freeze is missing, reordered, role-drifted, or detached");
  }
  verifyExactPreSealFileSets(bundle, contracts);
  freeze.entries.forEach((entry, index) => {
    const contract = contracts[index];
    if (!Evidence.isPlainObject(entry) || !same(Object.keys(entry).sort(), entryKeys)
        || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
        || typeof entry.rawBase64 !== "string") {
      fail("preseal_artifact_freeze_invalid", "preseal_artifacts",
        "pre-seal artifact freeze entry is malformed", { index });
    }
    const frozenBytes = Buffer.from(entry.rawBase64, "base64");
    if (frozenBytes.toString("base64") !== entry.rawBase64
        || frozenBytes.length !== entry.bytes
        || Evidence.sha256Bytes(frozenBytes) !== entry.sha256) {
      fail("preseal_artifact_freeze_invalid", "preseal_artifacts",
        "pre-seal raw bytes are not canonically frozen", { relativePath: entry.relativePath });
    }
    const current = Evidence.readExactRegularFile(path.join(bundle.runDir,
      entry.relativePath.replace(/\//g, path.sep)), {
      phase: "preseal_artifacts", maximumBytes: 128 * 1024 * 1024,
    });
    verifyPreSealContractContent(contract, current);
    if (current.length !== entry.bytes || current.sha256 !== entry.sha256
        || !current.bytes.equals(frozenBytes)) {
      fail("preseal_artifact_bytes_changed", "preseal_artifacts",
        "post-seal artifact bytes differ from the exact pre-seal freeze", {
          relativePath: entry.relativePath,
        });
    }
    if (artifactManifest) {
      const manifestEntry = artifactManifest.get(entry.relativePath);
      if (!manifestEntry || manifestEntry.role !== entry.role
          || manifestEntry.bytes !== entry.bytes || manifestEntry.sha256 !== entry.sha256) {
        fail("preseal_artifact_manifest_mismatch", "preseal_artifacts",
          "artifact manifest path/role/bytes/hash differs from the pre-seal freeze", {
            relativePath: entry.relativePath,
          });
      }
    }
  });
  return true;
}

function verifyTranscriptArtifacts(bundle, artifactManifest) {
  ["first", "restart"].forEach((phase) => {
    const prefix = "equipment-" + phase + "-passive-transcript";
    const summaryRelative = prefix + ".json";
    const jsonlRelative = prefix + ".jsonl";
    const summaryEntry = artifactManifest.get(summaryRelative);
    const jsonlEntry = artifactManifest.get(jsonlRelative);
    if (!summaryEntry || summaryEntry.role !== "raw_transcript"
        || !jsonlEntry || jsonlEntry.role !== "raw_transcript") {
      fail("transcript_artifact_role_invalid", "artifact_manifest",
        "transcript artifacts are absent or have the wrong manifest role", { phase });
    }
    const summary = readJsonFile(summaryEntry.absolutePath,
      "transcript_artifact", 128 * 1024 * 1024).value;
    if (!same(summary, bundle.transcripts[phase])) {
      fail("transcript_summary_bundle_mismatch", "transcript_artifact",
        "persisted transcript summary differs from the verified bundle", { phase });
    }
    const jsonlFile = Evidence.readExactRegularFile(jsonlEntry.absolutePath, {
      phase: "transcript_artifact", maximumBytes: 128 * 1024 * 1024,
    });
    const text = jsonlFile.bytes.toString("utf8");
    if (!text.endsWith("\n")) {
      fail("transcript_jsonl_invalid", "transcript_artifact",
        "transcript JSONL lacks a closed terminal newline", { phase });
    }
    let records;
    try { records = text.slice(0, -1).split("\n").map((line) => JSON.parse(line)); }
    catch (error) {
      fail("transcript_jsonl_invalid", "transcript_artifact", error.message, { phase });
    }
    if (!same(records, bundle.transcripts[phase].events)) {
      fail("transcript_jsonl_bundle_mismatch", "transcript_artifact",
        "persisted transcript event stream differs from the verified bundle", { phase });
    }
    assertNoRawAuthority(summary, "transcript_artifact");
    assertNoRawAuthority(records, "transcript_artifact");
  });
  PRESEAL_SIDECARS.forEach((contract) => {
    const entry = artifactManifest.get(contract.relativePath);
    if (!entry || entry.role !== contract.role) {
      fail("preseal_sidecar_artifact_role_invalid", "artifact_manifest",
        "Host/persistence sidecar is absent or has the wrong role", {
          relativePath: contract.relativePath,
        });
    }
    const value = readJsonFile(entry.absolutePath, contract.role,
      128 * 1024 * 1024).value;
    if (!same(value, contract.valueOf(bundle))) {
      fail("preseal_sidecar_bundle_mismatch", "artifact_manifest",
        "Host/persistence sidecar differs from the verified bundle", {
          relativePath: contract.relativePath,
        });
    }
  });
  const sidecarRolePaths = Array.from(artifactManifest.entries())
    .filter((entry) => PRESEAL_SIDECARS.some((contract) => contract.role === entry[1].role))
    .map((entry) => entry[0]).sort();
  if (!same(sidecarRolePaths, PRESEAL_SIDECARS.map((entry) => entry.relativePath).sort())) {
    fail("preseal_sidecar_artifact_set_invalid", "artifact_manifest",
      "Host/persistence sidecar roles contain extras or omissions");
  }
  const bundleEntry = artifactManifest.get("journey-bundle.json");
  if (!bundleEntry || bundleEntry.role !== "verified_input") {
    fail("bundle_artifact_role_invalid", "artifact_manifest",
      "journey bundle is absent or has the wrong manifest role");
  }
  const persistedBundle = readJsonFile(bundleEntry.absolutePath,
    "bundle_artifact", 128 * 1024 * 1024).value;
  if (!same(persistedBundle, bundle)) {
    fail("bundle_artifact_mismatch", "bundle_artifact",
      "persisted journey bundle differs from verifier input");
  }
  const providerPaths = bundle.control && Array.isArray(bundle.control.acks)
    ? bundle.control.acks.map((ack) => ack && ack.providerReceipt
      && ack.providerReceipt.artifact) : [];
  if (providerPaths.length !== REQUIRED_CONTROL_STEPS.length
      || providerPaths.some((entry) => typeof entry !== "string")
      || new Set(providerPaths).size !== providerPaths.length) {
    fail("provider_receipt_artifact_set_invalid", "artifact_manifest",
      "provider receipt artifact set is missing, duplicated, or malformed");
  }
  const nativeInputPaths = [];
  const providerCaptureEventPaths = [];
  providerPaths.forEach((relativePath) => {
    const entry = artifactManifest.get(relativePath);
    if (!entry || entry.role !== "provider_receipt") {
      fail("provider_receipt_artifact_role_invalid", "artifact_manifest",
        "provider receipt is absent or has the wrong manifest role", { relativePath });
    }
    const provider = readJsonFile(entry.absolutePath, "provider_receipt", 64 * 1024).value;
    if (!provider.captureEventRef || typeof provider.captureEventRef.artifact !== "string") {
      fail("provider_capture_event_artifact_set_invalid", "artifact_manifest",
        "provider receipt lacks its trusted capture event reference", { relativePath });
    }
    providerCaptureEventPaths.push(provider.captureEventRef.artifact);
    if (provider.inputEvidence && provider.inputEvidence.kind === "native_input"
        && provider.inputEvidence.eventRef) {
      nativeInputPaths.push(provider.inputEvidence.eventRef.artifact);
    }
  });
  const rolePaths = Array.from(artifactManifest.entries())
    .filter((entry) => entry[1] && entry[1].role === "provider_receipt")
    .map((entry) => entry[0]).sort();
  if (!same(rolePaths, providerPaths.slice().sort())) {
    fail("provider_receipt_artifact_set_invalid", "artifact_manifest",
      "provider receipt manifest role contains extras or omissions");
  }
  if (providerCaptureEventPaths.length !== REQUIRED_CONTROL_STEPS.length
      || new Set(providerCaptureEventPaths).size !== providerCaptureEventPaths.length) {
    fail("provider_capture_event_artifact_set_invalid", "artifact_manifest",
      "provider capture event artifact set is missing, duplicated, or malformed");
  }
  providerCaptureEventPaths.forEach((relativePath) => {
    const entry = artifactManifest.get(relativePath);
    if (!entry || entry.role !== "provider_capture_event") {
      fail("provider_capture_event_artifact_role_invalid", "artifact_manifest",
        "provider capture event is absent or has the wrong role", { relativePath });
    }
  });
  const captureEventRolePaths = Array.from(artifactManifest.entries())
    .filter((entry) => entry[1] && entry[1].role === "provider_capture_event")
    .map((entry) => entry[0]).sort();
  if (!same(captureEventRolePaths, providerCaptureEventPaths.slice().sort())) {
    fail("provider_capture_event_artifact_set_invalid", "artifact_manifest",
      "provider capture event manifest role contains extras or omissions");
  }
  if (nativeInputPaths.length !== 4 || new Set(nativeInputPaths).size !== nativeInputPaths.length) {
    fail("native_input_event_artifact_set_invalid", "artifact_manifest",
      "native input event artifact set is missing, duplicated, or malformed");
  }
  nativeInputPaths.forEach((relativePath) => {
    const entry = artifactManifest.get(relativePath);
    if (!entry || entry.role !== "native_input_event") {
      fail("native_input_event_artifact_role_invalid", "artifact_manifest",
        "native input event artifact is absent or has the wrong role", { relativePath });
    }
  });
  const nativeRolePaths = Array.from(artifactManifest.entries())
    .filter((entry) => entry[1] && entry[1].role === "native_input_event")
    .map((entry) => entry[0]).sort();
  if (!same(nativeRolePaths, nativeInputPaths.slice().sort())) {
    fail("native_input_event_artifact_set_invalid", "artifact_manifest",
      "native input event artifact role contains extras or omissions");
  }
  const artifactContracts = [
    { role: "control_request", values: bundle.control.requests,
      pathOf: (value) => "control/requests/" + value.requestId + ".json" },
    { role: "control_ack", values: bundle.control.acks,
      pathOf: (value) => "control/acks/" + value.requestId + ".json" },
  ];
  artifactContracts.forEach((contract) => {
    const expectedPaths = contract.values.map(contract.pathOf);
    expectedPaths.forEach((relativePath, index) => {
      const entry = artifactManifest.get(relativePath);
      if (!entry || entry.role !== contract.role) {
        fail("control_artifact_role_invalid", "artifact_manifest",
          "persisted control request/ack artifact role is missing or wrong", { relativePath });
      }
      const persisted = readJsonFile(entry.absolutePath, contract.role, 2 * 1024 * 1024).value;
      if (!same(persisted, contract.values[index])) {
        fail("control_artifact_bundle_mismatch", "artifact_manifest",
          "persisted control request/ack bytes differ from the bundle", { relativePath });
      }
    });
    const actualPaths = Array.from(artifactManifest.entries())
      .filter((entry) => entry[1] && entry[1].role === contract.role)
      .map((entry) => entry[0]).sort();
    if (!same(actualPaths, expectedPaths.slice().sort())) {
      fail("control_artifact_set_invalid", "artifact_manifest",
        "control artifact role contains extras or omissions", { role: contract.role });
    }
  });
  const capturePaths = bundle.control.acks.map((ack) => ack.capture.relativePath);
  capturePaths.forEach((relativePath, index) => {
    const entry = artifactManifest.get(relativePath);
    const ack = bundle.control.acks[index];
    if (!entry || entry.role !== "provider_capture" || entry.sha256 !== ack.capture.sha256
        || entry.bytes !== ack.capture.bytes) {
      fail("provider_capture_artifact_invalid", "artifact_manifest",
        "provider-owned capture artifact is missing or byte-detached", { relativePath });
    }
  });
  const roleCapturePaths = Array.from(artifactManifest.entries())
    .filter((entry) => entry[1] && entry[1].role === "provider_capture")
    .map((entry) => entry[0]).sort();
  if (!same(roleCapturePaths, capturePaths.slice().sort())) {
    fail("provider_capture_artifact_set_invalid", "artifact_manifest",
      "provider capture manifest role contains extras or omissions");
  }
  return true;
}

function verifyModuleJournalEnvelope(bundle, preSeal) {
  const expectedPhases = bundle.evidenceMode === "live_capture"
    ? ["domain_loaded", "clone_prepared", "first_captured", "restart_captured",
      "verification_executed", "terminal"]
    : ["domain_loaded", "audit_executed", "terminal"];
  if (!Evidence.isPlainObject(bundle.moduleJournal)
      || !Evidence.isPlainObject(bundle.moduleJournal.manifest)
      || !same(bundle.moduleJournal.manifest.requiredPhases, expectedPhases)
      || preSeal && bundle.moduleJournal.artifact !== null
      || !preSeal && !Evidence.isPlainObject(bundle.moduleJournal.artifact)) {
    fail("module_journal_profile_invalid", "module_journal",
      "module journal does not match the exact live/offline phase profile");
  }
  ModuleJournal.verifyExplicitModuleManifest({ root: bundle.root,
    manifest: bundle.moduleJournal.manifest });
}

function preSealProjection(bundle) {
  const projection = JSON.parse(JSON.stringify(bundle));
  delete projection.rawBundleManifest;
  if (projection.moduleJournal) projection.moduleJournal.artifact = null;
  return projection;
}

function semanticDigest(bundle) {
  return Evidence.sha256Text(Evidence.canonicalJson(preSealProjection(bundle)));
}

function buildReceipt(bundle, result, semanticSha256, artifactCount, moduleJournalSha256) {
  const receipt = {
    schema: RECEIPT_SCHEMA,
    apiVersion: API_VERSION,
    status: bundle.evidenceMode === "live_capture" ? "e2e_verified" : "OFFLINE_VERIFIED",
    liveStatus: bundle.evidenceMode === "live_capture" ? "LIVE_VERIFIED" : "LIVE_BLOCKED",
    evidenceMode: bundle.evidenceMode,
    deployment: "NOT_DEPLOYED",
    verifiedAt: new Date().toISOString(),
    runId: bundle.runId,
    targetSlot: bundle.targetSlot,
    candidateIdentity: bundle.runtime.expectedIdentity,
    productionClosureSha256: result.runtime.production.closure.closureSha256,
    productionBindingSha256: result.runtime.production.binding.bindingSha256,
    candidateProducerSha256: result.runtime.production.candidateProducer.evidenceSha256,
    firstLoadedProductionSha256: result.runtime.production.first.evidenceSha256,
    restartLoadedProductionSha256: result.runtime.production.restart.evidenceSha256,
    selectedTransport: result.control.capability.selectedTransport,
    source: result.first.initial.source,
    installedCandidate: result.first.candidateB,
    firstPanelInstanceId: result.first.pairs.panelInstanceId,
    restartPanelInstanceId: result.restart.pairs.panelInstanceId,
    firstViewSessionId: result.first.pairs.viewSessionId,
    restartViewSessionId: result.restart.pairs.viewSessionId,
    firstHostMappings: result.host.firstMappings,
    restartHostMappings: result.host.restartMappings,
    partialOrder: result.partialOrder,
    persistence: {
      initialSha256: result.persistence.initialDisk.sha256,
      committedSha256: result.persistence.commitDisk.sha256,
      restartSha256: result.persistence.restartDisk.sha256,
      archiveEvidenceSha256: result.persistence.archive.evidenceSha256,
      releaseSha256: result.persistence.release.releaseSha256,
    },
    transcript: {
      first: { eventCount: bundle.transcripts.first.eventCount,
        chainHead: bundle.transcripts.first.chainHead },
      restart: { eventCount: bundle.transcripts.restart.eventCount,
        chainHead: bundle.transcripts.restart.chainHead },
    },
    artifactCount,
    moduleJournalSha256,
    semanticSha256,
    boundaries: {
      deployment: false,
      physicalDualScreen: false,
      operatorAcknowledgementIsBusinessProof: false,
      operatorAckTimestampsAreSelfReported: true,
      captureSemanticContentIndependentlyVerified: false,
      browserEventIsTrustedNotPhysicalProof: true,
      physicalInputAttestation: false,
      safeExitUiJourneyVerified: bundle.safeExitUiJourneyVerified === true,
      rawAuthorityMaterialPublished: false,
    },
  };
  assertNoRawAuthority(receipt, "receipt");
  receipt.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
  return receipt;
}

function verifyBundleBusinessPreSeal(bundle, semanticOptions) {
  const result = verifySemanticBundle(bundle, semanticOptions);
  verifyModuleJournalEnvelope(bundle, true);
  const semanticSha256 = semanticDigest(bundle);
  return { result, semanticSha256 };
}

function verifyBundlePreSeal(bundle, semanticOptions) {
  const verified = verifyBundleBusinessPreSeal(bundle, semanticOptions);
  const artifactFreeze = capturePreSealArtifactFreeze(bundle);
  const provisionalReceipt = buildReceipt(bundle, verified.result,
    verified.semanticSha256, null, null);
  const evidence = {
    schema: "workbench-live-e2e.equipment.preseal-verification.v3",
    bundleProjectionSha256: verified.semanticSha256,
    artifactFreeze,
    provisionalReceipt,
    provisionalReceiptSha256: Evidence.sha256Text(Evidence.canonicalJson(provisionalReceipt)),
  };
  evidence.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(evidence));
  return evidence;
}

function verifyBundle(bundle, options) {
  const settings = options || {};
  if (settings.preSeal === true) {
    const evidence = verifyBundlePreSeal(bundle, settings.semanticOptions);
    return { schema: evidence.schema, status: "PRESEAL_VERIFIED",
      liveStatus: "LIVE_PENDING_SEAL", deployment: "NOT_DEPLOYED", runId: bundle.runId,
      manifestSha256: bundle.moduleJournal.manifest.manifestSha256,
      semanticSha256: evidence.bundleProjectionSha256,
      evidenceSha256: evidence.evidenceSha256 };
  }
  const result = verifySemanticBundle(bundle, settings.semanticOptions);
  verifyModuleJournalEnvelope(bundle, false);
  const semanticSha256 = semanticDigest(bundle);
  const artifactManifestValue = readJsonFile(path.join(bundle.runDir, "artifact-manifest.json"),
    "artifact_manifest", 16 * 1024 * 1024).value;
  const artifactManifest = verifyArtifactManifest({
    root: bundle.root, runDir: bundle.runDir, manifest: artifactManifestValue,
    ownedBaseRelative: OWNED_BASE_RELATIVE,
  });
  verifyTranscriptArtifacts(bundle, artifactManifest);
  ModuleJournal.verifyRuntimeModuleJournal({
    root: bundle.root,
    manifest: bundle.moduleJournal.manifest,
    artifact: bundle.moduleJournal.artifact,
  });
  return buildReceipt(bundle, result, semanticSha256, artifactManifest.size,
    bundle.moduleJournal.artifact.evidenceSha256);
}

function exactEvidenceEnvelope(evidence, schema, digestField, digestValue, code) {
  const expectedKeys = ["schema", digestField, "provisionalReceipt",
    "provisionalReceiptSha256", "evidenceSha256"];
  if (schema === "workbench-live-e2e.equipment.preseal-verification.v3") {
    expectedKeys.push("artifactFreeze");
  }
  const payload = Object.assign({}, evidence);
  delete payload.evidenceSha256;
  if (!Evidence.isPlainObject(evidence) || evidence.schema !== schema
      || !Protocol.exactKeys(evidence, expectedKeys)
      || !SHA256_RE.test(String(evidence[digestField] || ""))
      || !SHA256_RE.test(String(evidence.provisionalReceiptSha256 || ""))
      || !SHA256_RE.test(String(evidence.evidenceSha256 || ""))
      || evidence[digestField] !== digestValue
      || evidence.provisionalReceiptSha256
        !== Evidence.sha256Text(Evidence.canonicalJson(evidence.provisionalReceipt))
      || evidence.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(payload))) {
    fail(code, "module_journal",
      "post-seal finalization is detached from the exact pre-seal verification");
  }
}

function finalizePreSealVerification(bundle, evidence) {
  exactEvidenceEnvelope(evidence,
    "workbench-live-e2e.equipment.preseal-verification.v3",
    "bundleProjectionSha256", semanticDigest(bundle), "preseal_verification_binding_invalid");
  verifyModuleJournalEnvelope(bundle, false);
  ModuleJournal.verifyRuntimeModuleJournal({ root: bundle.root,
    manifest: bundle.moduleJournal.manifest, artifact: bundle.moduleJournal.artifact });
  const artifactManifestValue = readJsonFile(path.join(bundle.runDir, "artifact-manifest.json"),
    "artifact_manifest", 16 * 1024 * 1024).value;
  const artifactManifest = verifyArtifactManifest({ root: bundle.root, runDir: bundle.runDir,
    manifest: artifactManifestValue, ownedBaseRelative: OWNED_BASE_RELATIVE });
  verifyPreSealArtifactFreeze(bundle, evidence.artifactFreeze, artifactManifest);
  verifyTranscriptArtifacts(bundle, artifactManifest);
  assertNoRawAuthority(bundle, "bundle");
  const receipt = JSON.parse(JSON.stringify(evidence.provisionalReceipt));
  delete receipt.receiptSha256;
  receipt.artifactCount = artifactManifest.size;
  receipt.moduleJournalSha256 = bundle.moduleJournal.artifact.evidenceSha256;
  receipt.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
  return receipt;
}

function prepareDeferredBundleVerification(bundle) {
  const provisionalReceipt = verifyBundle(bundle);
  const evidence = {
    schema: "workbench-live-e2e.equipment.deferred-verification.v1",
    bundleSha256: Evidence.sha256Text(Evidence.canonicalJson(bundle)),
    provisionalReceipt,
    provisionalReceiptSha256: Evidence.sha256Text(Evidence.canonicalJson(provisionalReceipt)),
  };
  evidence.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(evidence));
  return evidence;
}

function finalizeDeferredBundleVerification(bundle, evidence, admission) {
  exactEvidenceEnvelope(evidence,
    "workbench-live-e2e.equipment.deferred-verification.v1", "bundleSha256",
    Evidence.sha256Text(Evidence.canonicalJson(bundle)), "deferred_verification_binding_invalid");
  if (!Evidence.isPlainObject(admission) || !Evidence.isPlainObject(admission.manifest)
      || !Evidence.isPlainObject(admission.journal)
      || !same(admission.manifest.requiredPhases,
        ["domain_loaded", "verification_executed", "terminal"])) {
    fail("verification_admission_invalid", "module_journal",
      "external verification did not complete the exact current journal profile");
  }
  ModuleJournal.verifyRuntimeModuleJournal({ root: admission.manifest.root,
    manifest: admission.manifest, artifact: admission.journal });
  return evidence.provisionalReceipt;
}

module.exports = {
  STRICT_GLOBAL_BOUNDARY_LABELS,
  TRUSTED_AUTHORIZATION_SOURCES,
  TRUSTED_CAPABILITY_SOURCES,
  assertStrictBoundaryChain,
  capturePreSealArtifactFreeze,
  finalizeDeferredBundleVerification,
  finalizePreSealVerification,
  persistPreSealSidecars,
  prepareDeferredBundleVerification,
  preSealProjection,
  semanticDigest,
  verifyBundle,
  verifyBundlePreSeal,
  verifyPreSealArtifactFreeze,
  verifySemanticBundle,
  verifyTranscriptArtifacts,
};
