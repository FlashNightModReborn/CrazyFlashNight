"use strict";

const fs = require("fs");
const path = require("path");
const SharedControl = require("../lib/control-contract");
const CloneSaveGuard = require("../lib/clone-save-guard");
const SharedEvidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const SharedRuntime = require("../lib/runtime-guard");
const RuntimeModuleJournal = require("../lib/runtime-module-journal");
const ProductionClosure = require("./production-closure");
const {
  ACK_SCHEMA,
  CONTROL_SCHEMA,
  RECEIPT_SCHEMA,
  SHA256_RE,
  TOKEN_KEYS,
  TOOL_SCHEMA,
  assertNoRawTokens,
  assertSafeSlot,
  canonicalJson,
  fail,
  isPlainObject,
  pathInside,
  sha256Bytes,
  sha256Text,
  verifyCatalogSelection,
  verifyEventChain,
  verifyRawBundleManifest,
} = require("./common");
const { DOM_CONTROL_STEPS, validateAck, validateRequest, verifyAckCaptureFile,
  verifyProviderReceiptFile } = require("./control-channel");
const { assertSaveUniverseInvariant, verifySaveUniverse } = require("./generic-opener");

const CANONICAL_ROOT = path.resolve(__dirname, "..", "..", "..");

const SHOP_ACTIONS = Object.freeze({
  bulkQuery: "shopBulkQuery",
  saveCart: "shopSaveCart",
  checkoutPreview: "shopCheckoutPreview",
  checkoutCommit: "shopCheckoutCommit",
  tooltip: "shopTooltip",
});
const REQUIRED_CONTROL_STEPS = Object.freeze([
  "open_kshop",
  "add_selected_item",
  "open_checkout",
  "commit_checkout",
  "close_kshop",
  "safe_exit",
  "exit_confirm",
  "restart_readback_open_kshop",
  "restart_readback_close_kshop",
]);
const INVENTORY_BAG_PROBE = Object.freeze({
  containerId: "背包", offset: 0, limit: 50, filterKey: "all",
});
const INVENTORY_BATTLE_PROBE = Object.freeze({
  containerId: "战备箱", offset: 0, limit: 100, filterKey: "all",
});
const INVENTORY_BATTLE_ACCESS = new Set([0, 40, 80, 120, 160, 200, 240]);
const INVENTORY_SURFACE_SCHEMA = "workbench-live-e2e.kshop.inventory-surface.v1";
const EXPECTED_RUNTIME_MODULE_LOCATORS = Object.freeze([
  "external:" + path.resolve(process.execPath).replace(/\\/g, "/"),
  "root:launcher/perf/node_modules/playwright-core/lib/utilsBundle.js",
  "root:launcher/perf/node_modules/playwright-core/lib/utilsBundleImpl/index.js",
  "root:tools/lib/legacy-http-auth.js",
  "root:tools/lib/legacy-http-client.js",
  "root:tools/lib/runtime-process-identity.js",
  "root:tools/workbench-live-e2e/kshop/bootstrap.js",
  "root:tools/workbench-live-e2e/kshop/cdp-client.js",
  "root:tools/workbench-live-e2e/kshop/cdp-passive-observer.js",
  "root:tools/workbench-live-e2e/kshop/common.js",
  "root:tools/workbench-live-e2e/kshop/control-channel.js",
  "root:tools/workbench-live-e2e/kshop/evidence-verifier.js",
  "root:tools/workbench-live-e2e/kshop/generic-opener.js",
  "root:tools/workbench-live-e2e/kshop/production-closure.js",
  "root:tools/workbench-live-e2e/kshop/png-contract.js",
  "root:tools/workbench-live-e2e/kshop/run-live-journey.js",
  "root:tools/workbench-live-e2e/kshop/verify-live-journey.js",
  "root:tools/workbench-live-e2e/lib/clone-save-guard.js",
  "root:tools/workbench-live-e2e/lib/control-contract.js",
  "root:tools/workbench-live-e2e/lib/evidence-artifact.js",
  "root:tools/workbench-live-e2e/lib/launcher-observation.js",
  "root:tools/workbench-live-e2e/lib/runtime-guard.js",
  "root:tools/workbench-live-e2e/lib/runtime-module-journal.js",
].sort());
const EXPECTED_AUDIT_MODULE_LOCATORS = Object.freeze(EXPECTED_RUNTIME_MODULE_LOCATORS.concat([
  "root:launcher/web/modules/inventory-runtime.js",
  "root:launcher/web/modules/panel-runtime.js",
  "root:tools/workbench-live-e2e/kshop/fixtures/valid-bundle.js",
  "root:tools/workbench-live-e2e/kshop/self-test.js",
]).sort());
const EXPECTED_MODULE_BUILTINS = Object.freeze([
  "assert", "buffer", "child_process", "constants", "crypto", "dns", "events", "fs",
  "http", "https", "net", "os", "path", "process", "stream", "tls", "tty", "url",
  "util", "zlib",
]);

function own(value, key) {
  return Object.prototype.hasOwnProperty.call(value || {}, key);
}

function requireObject(value, code, message) {
  if (!isPlainObject(value)) fail(code, "verify", message);
  return value;
}

function requireOne(values, code, message) {
  if (!Array.isArray(values) || values.length !== 1) {
    fail(code, "verify", message, { count: Array.isArray(values) ? values.length : null });
  }
  return values[0];
}

function receiptStateForEvidenceMode(evidenceMode) {
  if (evidenceMode === "offline_fixture") {
    return { status: "OFFLINE_VERIFIED", liveStatus: "LIVE_BLOCKED" };
  }
  if (evidenceMode === "live_capture") {
    return { status: "e2e_verified", liveStatus: "E2E_VERIFIED" };
  }
  fail("evidence_mode_invalid", "bundle",
    "receipt state requires one closed evidence mode", { evidenceMode });
}

function deepEqual(left, right) {
  return canonicalJson(left) === canonicalJson(right);
}

function authoritativeIconNamesForLifecycle(events, lifecycle) {
  const opens = (events || []).filter((event) => event && event.kind === "webview_message"
    && event.direction === "inbound" && event.message && event.message.type === "panel_cmd"
    && event.message.panel === "kshop" && event.message.cmd === "open"
    && typeof event.message.panelInstanceId === "string" && event.message.panelInstanceId);
  const lifecycleIndex = lifecycle === "first" ? 0 : lifecycle === "restart" ? 1 : -1;
  const open = lifecycleIndex >= 0 ? opens[lifecycleIndex] : null;
  if (!open) {
    fail("dynamic_icon_lifecycle_open_missing", "production_closure",
      "loaded icon projection lacks its exact transcript lifecycle owner", { lifecycle });
  }
  const nextOpen = opens[lifecycleIndex + 1] || null;
  const names = [];
  function add(value) {
    const name = String(value || "").trim();
    if (name && !names.includes(name)) names.push(name);
  }
  (events || []).filter((event) => event && event.sequence > open.sequence
    && (!nextOpen || event.sequence < nextOpen.sequence)
    && event.kind === "webview_message" && event.direction === "inbound"
    && event.message && event.message.type === "panel_resp"
    && event.message.panel === "kshop"
    && event.message.panelInstanceId === open.message.panelInstanceId
    && event.message.success === true).forEach((event) => {
    const message = event.message;
    (Array.isArray(message.catalog) ? message.catalog : []).forEach((item) => add(item && item.icon));
    (Array.isArray(message.purchased) ? message.purchased : []).forEach((item) => add(item && item.icon));
    (Array.isArray(message.snapshots) ? message.snapshots : []).forEach((snapshot) => {
      (snapshot && Array.isArray(snapshot.slots) ? snapshot.slots : []).forEach((slot) => {
        if (slot && slot.occupied === true && slot.item) add(slot.item.icon);
      });
    });
  });
  if (!names.length) {
    fail("dynamic_icon_authority_empty", "production_closure",
      "authoritative catalog/inventory responses expose no icon names", { lifecycle });
  }
  return names;
}

function verifyProductionEvidence(bundle, first, restart, firstIdentity) {
  const closure = ProductionClosure.verifyProductionClosure(CANONICAL_ROOT,
    bundle.productionClosure);
  const candidateProducer = ProductionClosure.verifyCandidateProducerBinding(
    path.resolve(bundle.candidateRoot || ""), firstIdentity, closure, bundle.candidateProducer);
  const binding = requireObject(bundle.productionBinding,
    "production_binding_missing", "production closure is not bound to candidate/run identity");
  const identity = { runtimeMode: firstIdentity.runtimeMode,
    processPath: path.resolve(firstIdentity.processPath || ""),
    coreSha256: firstIdentity.coreSha256, buildIdentity: firstIdentity.buildIdentity,
    payloadClosure: firstIdentity.payloadClosure };
  const unsignedBinding = Object.assign({}, binding);
  delete unsignedBinding.bindingSha256;
  if (binding.schema !== ProductionClosure.BINDING_SCHEMA || binding.runId !== bundle.runId
      || binding.productionClosureSha256 !== closure.closureSha256
      || binding.candidateIdentitySha256 !== sha256Text(canonicalJson(identity))
      || binding.candidateProducerSha256 !== candidateProducer.evidenceSha256
      || binding.bindingSha256 !== sha256Text(canonicalJson(unsignedBinding))) {
    fail("production_binding_invalid", "production_closure",
      "production closure is detached from the exact candidate/run identity");
  }
  const expectedWeb = ProductionClosure.webFiles(closure);
  const transcriptEvents = bundle.transcript && Array.isArray(bundle.transcript.events)
    ? bundle.transcript.events : [];
  const lifecycleOpens = transcriptEvents.filter((event) => event && event.kind === "webview_message"
    && event.message && event.message.type === "panel_cmd" && event.message.panel === "kshop"
    && event.message.cmd === "open");
  const terminalDetaches = transcriptEvents.filter((event) => event
    && event.kind === "observer_detached");
  if (lifecycleOpens.length !== 2 || terminalDetaches.length !== 2
      || transcriptEvents.some((event) => event && event.kind === "observer_detach_transport_lost")
      || terminalDetaches[0].sequence <= lifecycleOpens[0].sequence
      || terminalDetaches[0].sequence >= lifecycleOpens[1].sequence
      || terminalDetaches[1].sequence <= lifecycleOpens[1].sequence) {
    fail("loaded_terminal_detach_boundary_invalid", "production_closure",
      "both loaded lifecycles require one successful terminal observer detach boundary");
  }
  function verifyLoaded(runtime, lifecycle) {
    const loaded = requireObject(runtime.loadedProduction, "loaded_production_missing",
      lifecycle + " runtime lacks actually loaded production bytes");
    const unsigned = Object.assign({}, loaded);
    delete unsigned.evidenceSha256;
    if (loaded.schema !== ProductionClosure.LOADED_SCHEMA || loaded.lifecycle !== lifecycle
        || loaded.capturePhase !== "post_observer_detach"
        || loaded.runtimePid !== runtime.identity.pid || loaded.runId !== bundle.runId
        || loaded.productionClosureSha256 !== closure.closureSha256
        || loaded.productionBindingSha256 !== binding.bindingSha256
        || loaded.evidenceSha256 !== sha256Text(canonicalJson(unsigned))) {
      fail("loaded_production_binding_invalid", "production_closure",
        lifecycle + " loaded-resource evidence is detached");
    }
    const observed = [loaded.page]
      .concat(Array.isArray(loaded.scripts) ? loaded.scripts : [])
      .concat(Array.isArray(loaded.stylesheets) ? loaded.stylesheets : []);
    if (observed.length !== expectedWeb.length
        || new Set(observed.map((entry) => entry && entry.locator)).size !== observed.length
        || !deepEqual(observed.map((entry) => entry && entry.locator),
          expectedWeb.map((entry) => entry.locator))) {
      fail("loaded_production_multiset_invalid", "production_closure",
        lifecycle + " loaded-resource multiset has gaps, duplicates, or extras");
    }
    const expectedExecutables = ProductionClosure.expectedExecutableOccurrences(closure);
    const rawScripts = Array.isArray(loaded.rawScriptOccurrences)
      ? loaded.rawScriptOccurrences : [];
    const productionScripts = Array.isArray(loaded.productionScriptOccurrences)
      ? loaded.productionScriptOccurrences : [];
    const ownedEvaluations = Array.isArray(loaded.ownedEvaluations)
      ? loaded.ownedEvaluations : [];
    const rawContexts = Array.isArray(loaded.rawExecutionContextOccurrences)
      ? loaded.rawExecutionContextOccurrences : [];
    const rawResources = Array.isArray(loaded.rawResourceOccurrences)
      ? loaded.rawResourceOccurrences : [];
    const pageResources = rawResources.filter((entry) => entry && entry.type === "Document"
      && entry.url === "https://overlay.local/overlay.html");
    const mainFrameId = pageResources.length === 1
      && typeof pageResources[0].frameId === "string" && pageResources[0].frameId
      ? pageResources[0].frameId : null;
    const expectedProductionUrls = expectedExecutables.map((entry) => entry.url);
    const expectedProductionUrlSet = new Set(expectedProductionUrls);
    const expectedToolUrls = ownedEvaluations.map((entry) => entry && entry.url);
    const expectedToolUrlSet = new Set(expectedToolUrls);
    const rawProduction = rawScripts.filter((entry) => entry
      && expectedProductionUrlSet.has(entry.url));
    const rawTool = rawScripts.filter((entry) => entry && expectedToolUrlSet.has(entry.url));
    const rawForeign = rawScripts.filter((entry) => !entry
      || (!expectedProductionUrlSet.has(entry.url) && !expectedToolUrlSet.has(entry.url)));
    if (!rawScripts.length || rawForeign.length > 0
        || new Set(rawScripts.map((entry) => entry && entry.scriptId)).size !== rawScripts.length
        || !deepEqual(rawScripts.map((entry) => entry && entry.occurrence),
          rawScripts.map((_entry, index) => index + 1))
        || !deepEqual(rawProduction, productionScripts)
        || !deepEqual(productionScripts.map((entry) => entry.url), expectedProductionUrls)
        || expectedToolUrlSet.size !== expectedToolUrls.length
        || !deepEqual(rawTool.map((entry) => entry.url), expectedToolUrls)) {
      fail("loaded_production_executable_occurrence_invalid", "production_closure",
        lifecycle + " raw executable occurrence/order has an extra, duplicate, omission, or foreign source");
    }
    if (rawContexts.length < 1 || rawContexts.some((entry, index) => !exactKeys(entry,
      ["occurrence", "id", "uniqueId", "origin", "name", "auxData"])
        || entry.occurrence !== index + 1 || !Number.isInteger(entry.id) || entry.id < 1
        || typeof entry.uniqueId !== "string" || !entry.uniqueId
        || entry.origin !== "https://overlay.local"
        || typeof entry.name !== "string" || !isPlainObject(entry.auxData)
        || typeof entry.auxData.frameId !== "string" || !entry.auxData.frameId
        || mainFrameId !== null && entry.auxData.frameId !== mainFrameId
        || entry.auxData.isDefault !== true
        || typeof entry.auxData.type !== "string" || !entry.auxData.type)) {
      fail("loaded_execution_context_occurrence_invalid", "production_closure",
        lifecycle + " raw execution-context occurrence/order/full auxData is malformed");
    }
    if (new Set(rawContexts.map((entry) => entry.id)).size !== rawContexts.length
        || new Set(rawContexts.map((entry) => entry.uniqueId)).size !== rawContexts.length) {
      fail("loaded_execution_context_identity_reused", "production_closure",
        lifecycle + " raw execution-context ids and uniqueIds must each be unique");
    }
    const referencedContexts = [];
    const referencedContextIds = new Set();
    rawScripts.forEach((entry) => {
      if (!exactKeys(entry, ["occurrence", "scriptId", "url", "executionContextId",
        "startLine", "startColumn", "endLine", "endColumn", "sourceMapUrl", "urlOrigin",
        "context", "sourceMethod", "sha256", "bytes"])
          || !Number.isInteger(entry.occurrence) || !entry.scriptId
          || !Number.isInteger(entry.executionContextId) || entry.executionContextId < 1
          || !isPlainObject(entry.context)
          || !exactKeys(entry.context,
            ["occurrence", "id", "uniqueId", "origin", "name", "auxData"])
          || entry.context.id !== entry.executionContextId
          || entry.context.origin !== "https://overlay.local"
          || !isPlainObject(entry.context.auxData)
          || entry.context.auxData.isDefault !== true
          || typeof entry.context.auxData.frameId !== "string"
          || !entry.context.auxData.frameId
          || !rawContexts.some((context) => deepEqual(context, entry.context))
          || entry.sourceMethod !== "Debugger.getScriptSource"
          || !SHA256_RE.test(String(entry.sha256 || ""))
          || !Number.isInteger(entry.bytes) || entry.bytes < 1) {
        fail("loaded_executable_occurrence_shape_invalid", "production_closure",
          lifecycle + " raw executable occurrence lacks exact order/origin/source facts");
      }
      if (!referencedContextIds.has(entry.executionContextId)) {
        referencedContextIds.add(entry.executionContextId);
        referencedContexts.push(entry.context);
      }
    });
    if (!deepEqual(referencedContexts, rawContexts)) {
      fail("loaded_execution_context_set_invalid", "production_closure",
        lifecycle + " raw execution contexts are not the exact ordered unique script reference set");
    }
    productionScripts.forEach((actual, index) => {
      const expected = expectedExecutables[index];
      if (!expected || actual.url !== expected.url || actual.sha256 !== expected.sha256
          || actual.bytes !== expected.bytes || actual.urlOrigin !== "https://overlay.local") {
        fail("loaded_production_executable_source_mismatch", "production_closure",
          lifecycle + " production executable bytes/order differ from current tree");
      }
    });
    ownedEvaluations.forEach((expected, index) => {
      const actual = rawTool[index];
      if (!exactKeys(expected, ["sequence", "label", "url", "sha256", "bytes"])
          || expected.sequence !== index + 1 || !/^cf7-evidence:\/\/kshop\/[A-Za-z0-9._-]+\.js$/.test(
            String(expected.url || "")) || !actual || actual.url !== expected.url
          || actual.sha256 !== expected.sha256 || actual.bytes !== expected.bytes
          || actual.urlOrigin !== "null") {
        fail("loaded_owned_evaluation_mismatch", "production_closure",
          lifecycle + " observer-owned runtime evaluation evidence is malformed or detached");
      }
    });
    const terminalEvaluation = ownedEvaluations.at(-1);
    if (!terminalEvaluation
        || ownedEvaluations.filter((entry) => entry.label === "observer detach").length !== 1
        || terminalEvaluation.label !== "observer detach"
        || !rawTool.length || rawTool.at(-1).url !== terminalEvaluation.url
        || rawScripts.at(-1).url !== terminalEvaluation.url) {
      fail("loaded_terminal_detach_occurrence_invalid", "production_closure",
        lifecycle + " loaded executable plan does not terminate at the exact observer detach source");
    }
    const expectedStylesheetUrls = ProductionClosure.styleFiles(closure)
      .map((entry) => "https://overlay.local/"
        + entry.locator.slice("root:launcher/web/".length));
    if (rawResources.length < 1 || rawResources.some((entry, index) => !exactKeys(entry,
      ["occurrence", "frameOccurrence", "resourceOccurrence", "frameId", "frameUrl",
        "frameOrigin", "url", "urlOrigin", "type", "resource", "sourceMethod",
        "sourceSha256", "sourceBytes", "sourceError"])
        || entry.occurrence !== index + 1 || !Number.isInteger(entry.frameOccurrence)
        || entry.frameOccurrence < 1 || !Number.isInteger(entry.resourceOccurrence)
        || entry.resourceOccurrence < 1 || typeof entry.frameId !== "string" || !entry.frameId
        || typeof entry.frameUrl !== "string" || typeof entry.frameOrigin !== "string"
        || typeof entry.url !== "string" || !entry.url || typeof entry.urlOrigin !== "string"
        || typeof entry.type !== "string" || !isPlainObject(entry.resource)
        || String(entry.resource.url || "") !== entry.url
        || String(entry.resource.type || "") !== entry.type)) {
      fail("loaded_raw_resource_occurrence_invalid", "production_closure",
        lifecycle + " full raw Page resource occurrence/order is malformed");
    }
    const rawStyles = rawResources.filter((entry) => entry.type === "Stylesheet"
      || /\.css(?:$|[?#])/.test(entry.url));
    if (pageResources.length !== 1 || pageResources[0].urlOrigin !== "https://overlay.local"
        || pageResources[0].frameOrigin !== "https://overlay.local") {
      fail("loaded_page_resource_occurrence_invalid", "production_closure",
        lifecycle + " raw resource stream omitted or duplicated the actual Overlay document");
    }
    if (!deepEqual(rawStyles.map((entry) => entry.url), expectedStylesheetUrls)
        || rawStyles.some((entry) => entry.type !== "Stylesheet"
          || entry.urlOrigin !== "https://overlay.local"
          || entry.frameOrigin !== "https://overlay.local")
        || !deepEqual((loaded.stylesheets || []).map((entry) => entry.occurrence),
          rawStyles.map((entry) => entry.occurrence))) {
      fail("loaded_production_stylesheet_set_invalid", "production_closure",
        lifecycle + " raw stylesheet occurrence/order has an extra, duplicate, omission, or foreign origin");
    }
    const expectedStaticResources = ProductionClosure.expectedStaticResourceSet(closure);
    const expectedIconProjection = ProductionClosure.iconResourceSetForNames(CANONICAL_ROOT, closure,
      authoritativeIconNamesForLifecycle(bundle.transcript.events, lifecycle));
    if (!loaded.iconProjection || !deepEqual(loaded.iconProjection, expectedIconProjection)) {
      fail("loaded_dynamic_icon_projection_invalid", "production_closure",
        lifecycle + " icon resources are not bound to authoritative catalog/inventory icon names");
    }
    const fontEnvironment = ProductionClosure.verifyFontEnvironment(
      CANONICAL_ROOT, closure, loaded.fontEnvironment, process.env);
    const expectedCssResources = ProductionClosure.cssConditionalResourceSet(closure);
    const expectedStaticProjection = expectedStaticResources.map((entry) => ({
      url: entry.url, type: entry.type, urlOrigin: entry.urlOrigin,
    }));
    const expectedIconProjectionSet = expectedIconProjection.resources.map((entry) => ({
      url: entry.url, type: entry.type, urlOrigin: entry.urlOrigin,
    }));
    const staticByUrl = new Map(expectedStaticResources.map((entry) => [entry.url, entry]));
    const iconByUrl = new Map(expectedIconProjection.resources.map((entry) => [entry.url, entry]));
    const cssByUrl = new Map(expectedCssResources.map((entry) => [entry.url, entry]));
    const fontByUrl = new Map(fontEnvironment.installed.map((entry) => [entry.url, Object.assign({
      type: "Font", urlOrigin: "https://cfn-fonts.local",
    }, entry)]));
    const expectedLayerUrlCount = staticByUrl.size + iconByUrl.size + cssByUrl.size + fontByUrl.size;
    if (new Set(Array.from(staticByUrl.keys()).concat(Array.from(iconByUrl.keys()),
      Array.from(cssByUrl.keys()), Array.from(fontByUrl.keys()))).size !== expectedLayerUrlCount) {
      fail("loaded_resource_layer_collision", "production_closure",
        "fixed, icon, CSS, and font resource layers overlap");
    }
    const actualStaticProjection = [];
    const actualIconProjection = [];
    let layeredResourceInvalid = false;
    const fixedMimeTypeValid = (entry) => {
      const mimeType = String(entry && entry.resource && entry.resource.mimeType || "");
      if (entry.type === "Document") return mimeType === "text/html";
      if (entry.type === "Stylesheet") return mimeType === "text/css";
      if (entry.type === "Script") {
        return ["text/javascript", "application/javascript"].includes(mimeType);
      }
      if (entry.type === "Image") return mimeType === "image/webp";
      return false;
    };
    function boundSourceValid(entry, expected) {
      return entry.sourceMethod === "Page.getResourceContent"
        && entry.sourceSha256 === expected.sha256 && entry.sourceBytes === expected.bytes
        && entry.sourceError === null;
    }
    rawResources.forEach((entry, index) => {
      const commonValid = entry.frameOccurrence === 1
        && entry.resourceOccurrence === index + 1
        && entry.frameId === mainFrameId
        && entry.frameUrl === "https://overlay.local/overlay.html"
        && entry.frameOrigin === "https://overlay.local";
      const projection = { url: entry.url, type: entry.type, urlOrigin: entry.urlOrigin };
      const fixed = staticByUrl.get(entry.url);
      const icon = iconByUrl.get(entry.url);
      const css = cssByUrl.get(entry.url);
      const font = fontByUrl.get(entry.url);
      if (fixed) {
        actualStaticProjection.push(projection);
        if (!commonValid || entry.sourceMethod !== null || entry.sourceSha256 !== null
            || entry.sourceBytes !== null || entry.sourceError !== null
            || entry.type !== fixed.type || entry.urlOrigin !== fixed.urlOrigin
            || !fixedMimeTypeValid(entry)) layeredResourceInvalid = true;
        return;
      }
      if (icon) {
        actualIconProjection.push(projection);
        if (!commonValid || entry.type !== icon.type || entry.urlOrigin !== icon.urlOrigin
            || String(entry.resource.mimeType || "") !== icon.mimeType
            || !boundSourceValid(entry, icon)) layeredResourceInvalid = true;
        return;
      }
      if (css) {
        if (!commonValid || entry.type !== css.type || entry.urlOrigin !== css.urlOrigin
            || String(entry.resource.mimeType || "") !== css.mimeType
            || !boundSourceValid(entry, css)) layeredResourceInvalid = true;
        return;
      }
      if (font) {
        if (!commonValid || entry.type !== "Font"
            || entry.urlOrigin !== "https://cfn-fonts.local"
            || !boundSourceValid(entry, font)) layeredResourceInvalid = true;
        return;
      }
      layeredResourceInvalid = true;
    });
    const actualUrlSet = new Set(rawResources.map((entry) => entry && entry.url));
    const projectionOf = (entry) => ({ url: entry.url, type: entry.type,
      urlOrigin: entry.urlOrigin });
    // The Page stream is one global occurrence sequence.  Fixed resources are
    // mandatory; CSS/font routes are optional current-environment subsets; all
    // authoritative icon routes are mandatory.  Filtering optional routes by
    // observed presence is the only permitted projection—no grouping/sorting.
    const expectedGlobalProjection = expectedStaticResources.map(projectionOf)
      .concat(expectedCssResources.filter((entry) => actualUrlSet.has(entry.url)).map(projectionOf))
      .concat(expectedIconProjection.resources.map(projectionOf))
      .concat(fontEnvironment.installed.filter((entry) => actualUrlSet.has(entry.url))
        .map((entry) => ({ url: entry.url, type: "Font",
          urlOrigin: "https://cfn-fonts.local" })));
    const actualGlobalProjection = rawResources.map(projectionOf);
    if (!deepEqual(actualStaticProjection, expectedStaticProjection)
        || !deepEqual(actualIconProjection, expectedIconProjectionSet)
        || !deepEqual(actualGlobalProjection, expectedGlobalProjection)
        || new Set(rawResources.map((entry) => entry && entry.url)).size !== rawResources.length
        || layeredResourceInvalid) {
      fail("loaded_production_static_resource_set_invalid", "production_closure",
        lifecycle + " raw Page resources differ from the exact global fixed/CSS/icon/font occurrence contract", {
          expectedStatic: expectedStaticProjection, actualStatic: actualStaticProjection,
          expectedIcons: expectedIconProjectionSet, actualIcons: actualIconProjection,
          expectedGlobal: expectedGlobalProjection, actualGlobal: actualGlobalProjection,
        });
    }
    expectedWeb.forEach((expected) => {
      const actual = requireOne(observed.filter((entry) => entry
        && entry.locator === expected.locator), "loaded_production_resource_missing",
      lifecycle + " lacks one exact production resource");
      const suffix = expected.locator.slice("root:launcher/web/".length);
      const expectedUrl = expected.role === "page" ? "https://overlay.local/overlay.html"
        : "https://overlay.local/" + suffix;
      const expectedMethod = ["overlay_script", "lazy_registry", "kshop_lazy_web"].includes(expected.role)
        ? "Debugger.getScriptSource" : "Page.getResourceContent";
      if (actual.role !== expected.role || actual.url !== expectedUrl
          || actual.sourceMethod !== expectedMethod || actual.sha256 !== expected.sha256
          || actual.bytes !== expected.bytes
          || (expected.role !== "page"
            && (!Number.isInteger(actual.occurrence) || actual.occurrence < 1))) {
        fail("loaded_production_resource_mismatch", "production_closure",
          lifecycle + " loaded bytes/source differ from current-tree closure", {
            locator: expected.locator,
          });
      }
    });
    return loaded;
  }
  return { closure, binding, candidateProducer, first: verifyLoaded(first, "first"),
    restart: verifyLoaded(restart, "restart") };
}

function parseMaybeJson(value) {
  if (isPlainObject(value)) return value;
  if (typeof value !== "string") return null;
  try {
    const parsed = JSON.parse(value);
    return isPlainObject(parsed) ? parsed : null;
  } catch (_error) {
    return null;
  }
}

function eventMessage(event) {
  if (!event || (event.kind !== "bridge_send" && event.kind !== "webview_message")) return null;
  return parseMaybeJson(event.message);
}

function restoreWireMessage(event, message, label) {
  if (!isPlainObject(message) || !isPlainObject(event)
      || !Number.isInteger(event.wirePayloadLength) || event.wirePayloadLength < 2
      || !isPlainObject(event.authorityValueLengths)) {
    fail("wire_payload_facts_missing", "payload_causality",
      label + " lacks pre-redaction serialized length evidence");
  }
  const lengths = event.authorityValueLengths;
  const used = Object.create(null);
  Object.keys(lengths).forEach((publicKey) => {
    const key = publicKey.startsWith("field:") ? publicKey.slice("field:".length) : "";
    if (!TOKEN_KEYS.has(key) || !Array.isArray(lengths[publicKey])
        || lengths[publicKey].some((value) => !Number.isInteger(value) || value < 1 || value > 160)) {
      fail("wire_authority_lengths_invalid", "payload_causality",
        label + " contains malformed authority-value lengths", { key });
    }
    used[key] = 0;
  });
  function visit(value) {
    if (Array.isArray(value)) return value.map(visit);
    if (!isPlainObject(value)) return value;
    const output = {};
    Object.keys(value).forEach((key) => {
      if (TOKEN_KEYS.has(key)) {
        if (!/^sha256:[a-f0-9]{64}$/.test(String(value[key] || ""))) {
          fail("wire_authority_reference_invalid", "payload_causality",
            label + " authority field is not publicly redacted", { key });
        }
        const index = used[key] || 0;
        const publicKey = "field:" + key;
        const length = lengths[publicKey] && lengths[publicKey][index];
        if (!Number.isInteger(length)) {
          fail("wire_authority_lengths_missing", "payload_causality",
            label + " lacks one pre-redaction authority length", { key, index });
        }
        used[key] = index + 1;
        output[key] = "x".repeat(length);
      } else output[key] = visit(value[key]);
    });
    return output;
  }
  const restored = visit(message);
  Object.keys(lengths).forEach((publicKey) => {
    const key = publicKey.slice("field:".length);
    if (used[key] !== lengths[publicKey].length) {
      fail("wire_authority_lengths_extra", "payload_causality",
        label + " contains detached authority-value lengths", { key });
    }
  });
  const restoredLength = JSON.stringify(restored).length;
  if (restoredLength !== event.wirePayloadLength) {
    fail("wire_payload_length_mismatch", "payload_causality",
      label + " pre-redaction length is detached from its exact public envelope", {
        expected: restoredLength, actual: event.wirePayloadLength,
      });
  }
  return restored;
}

function verifyWirePayloadFacts(events) {
  const relevant = events.filter((event) => event && event.message
    && ["bridge_send", "webview_message", "panel_request_issued"].includes(event.kind));
  relevant.forEach((event) => restoreWireMessage(event, parseMaybeJson(event.message),
    event.kind + "#" + event.sequence));
  return { eventCount: relevant.length,
    totalWireCharacters: relevant.reduce((sum, event) => sum + event.wirePayloadLength, 0) };
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
    && entry.message.panel === "kshop" && typeof entry.message.cmd === "string");
}

function panelResponses(inbound) {
  return inbound.filter((entry) => entry.message.type === "panel_resp"
    && entry.message.panel === "kshop" && typeof entry.message.cmd === "string");
}

function verifyPanelRequestIssueOrder(events, requests) {
  const issued = events.filter((event) => event.kind === "panel_request_issued"
    && event.message && event.message.type === "panel" && event.message.panel === "kshop");
  const expectedRequests = requests.filter((entry) => entry.message.cmd !== "close");
  if (issued.length !== expectedRequests.length) {
    fail("panel_request_issue_multiset_invalid", "observer",
      "PanelRequestMux onIssued events do not exactly cover non-close KShop sends", {
        issued: issued.length,
        expected: expectedRequests.length,
      });
  }
  expectedRequests.forEach((request) => {
    const matches = issued.filter((event) => event.callId === request.message.callId
      && event.cmd === request.message.cmd
      && deepEqual(event.message, request.message));
    const exact = requireOne(matches, "panel_request_issue_count_invalid",
      "KShop bridge send lacks one exact production onIssued receipt");
    const expectedChannel = request.message.domain === "inventory" ? "inventory" : "shop";
    if (!isPlainObject(exact.metadata) || exact.metadata.channel !== expectedChannel
        || Object.keys(exact.metadata).length !== 1) {
      fail("panel_request_issue_metadata_invalid", "observer",
        "PanelRequestMux onIssued metadata does not match the KShop request channel", {
          callId: request.message.callId,
          expectedChannel,
        });
    }
    if (exact.sequence + 1 !== request.event.sequence) {
      fail("panel_request_issue_order_invalid", "observer",
        "PanelRequestMux onIssued must be observed immediately before Bridge.send", {
          callId: request.message.callId,
          issuedSequence: exact.sequence,
          sendSequence: request.event.sequence,
        });
    }
    if (exact.wirePayloadLength !== request.event.wirePayloadLength
        || !deepEqual(exact.authorityValueLengths, request.event.authorityValueLengths)) {
      fail("panel_request_wire_facts_mismatch", "payload_causality",
        "PanelRequestMux and Bridge.send disagree on the exact pre-redaction request bytes", {
          callId: request.message.callId,
        });
    }
  });
  const ready = events.filter((event) => event.kind === "observer_ready");
  if (ready.length !== 2 || ready.some((event) => event.observationOnly !== true
      || event.panelRequestMuxWrapped !== true
      || !Array.isArray(event.businessActionMethods)
      || event.businessActionMethods.length !== 0)) {
    fail("observer_passive_contract_invalid", "observer",
      "each lifecycle needs a passive-only observer bound to PanelRequestMux");
  }
  return { issuedCount: issued.length, observerReadyCount: ready.length };
}

function responseFor(request, responses) {
  const matches = responses.filter((entry) => entry.event.sequence > request.event.sequence
    && entry.message.callId === request.message.callId
    && entry.message.cmd === request.message.cmd
    && entry.message.panelInstanceId === request.message.panelInstanceId
    && (own(request.message, "domain")
      ? entry.message.domain === request.message.domain
      : !own(entry.message, "domain")));
  return requireOne(matches, "response_count_invalid",
    "request does not have exactly one owner/domain-bound Web response");
}

function requestsForInstance(requests, panelInstanceId, cmd, domainMode) {
  return requests.filter((entry) => entry.message.panelInstanceId === panelInstanceId
    && entry.message.cmd === cmd
    && (domainMode === "inventory"
      ? entry.message.domain === "inventory"
      : !own(entry.message, "domain")));
}

function exactTargetCart(cart, selection) {
  const targetCart = selection && selection.cart;
  if (!Array.isArray(cart) || !Array.isArray(targetCart)
      || cart.length !== targetCart.length) return false;
  const clean = cart.map((entry) => ({ idx: Number(entry.idx), qty: Number(entry.qty) }))
    .sort((left, right) => left.idx - right.idx);
  const expected = targetCart.map((entry) => ({ idx: Number(entry.idx), qty: Number(entry.qty) }))
    .sort((left, right) => left.idx - right.idx);
  return deepEqual(clean, expected);
}

function catalogItem(catalog, index) {
  return Array.isArray(catalog)
    ? catalog.find((entry) => entry && Number(entry.idx) === Number(index)) || null
    : null;
}

function assertSelectedCatalog(catalog, selection, phase, expectedDynamicLimit) {
  const actual = catalogItem(catalog, selection.catalogIndex);
  if (!actual || actual.item !== selection.itemName
      || actual.displayname !== selection.displayName
      || actual.icon !== selection.icon
      || actual.type !== selection.shopType
      || actual.majorType !== selection.catalogMajorType
      || actual.subType !== selection.catalogSubType
      || Number(actual.price) !== selection.unitPrice
      || (expectedDynamicLimit === undefined
        ? Number(actual.maxQuantity) !== selection.maxQuantity
        : Number(actual.maxQuantity) !== expectedDynamicLimit)) {
    fail("catalog_identity_mismatch", phase,
      "selected catalog stable identity/price or phase-appropriate dynamic limit is invalid", {
      selection,
      actual,
    });
  }
  return true;
}

function assertPurchaseLines(lines, balance, selection) {
  if (!Array.isArray(lines) || lines.length !== 1) {
    fail("preview_lines_invalid", "preview", "preview/commit must contain one selected line");
  }
  const line = lines[0];
  const exactKeys = ["catalogIndex", "itemName", "displayName", "icon", "quantity",
    "unitPrice", "total", "maxQuantity", "maxAffordable", "maxByCapacity",
    "maxPurchasable", "itemKind"].sort();
  const expectedTotal = selection.unitPrice * selection.quantity;
  const maximum = Number(line && line.maxQuantity);
  const affordable = Number(line && line.maxAffordable);
  const byCapacity = Number(line && line.maxByCapacity);
  const purchasable = Number(line && line.maxPurchasable);
  const expectedAffordable = selection.unitPrice <= 0 ? maximum
    : Math.max(0, Math.min(maximum, Math.floor(Number(balance) / selection.unitPrice)));
  if (!line || !deepEqual(Object.keys(line).sort(), exactKeys)
      || Number(line.catalogIndex) !== selection.catalogIndex
      || line.itemName !== selection.itemName || line.displayName !== selection.displayName
      || line.icon !== selection.icon || Number(line.quantity) !== selection.quantity
      || Number(line.unitPrice) !== selection.unitPrice
      || Number(line.total) !== expectedTotal
      || !Number.isInteger(maximum) || maximum < 1
      || !Number.isInteger(affordable) || affordable < 0
      || !Number.isInteger(byCapacity) || byCapacity < 0
      || !Number.isInteger(purchasable) || purchasable < 0
      || affordable !== expectedAffordable
      || purchasable !== Math.min(maximum, affordable, byCapacity)
      || selection.quantity > purchasable
      || !isPlainObject(selection.deliveryContract)
      || selection.deliveryContract.executableJourneyEligible !== true
      || selection.deliveryContract.classification !== "equipment"
      || selection.deliveryContract.destination !== "backpack_first_vacancy"
      || selection.deliveryContract.verifierPoststate
        !== "complete_50_slot_backpack_physical_delta"
      || line.itemKind !== selection.deliveryContract.authorityItemKind) {
    fail("purchase_line_mismatch", "preview", "authority line is not the exact selected identity", {
      selection,
      actual: line,
    });
  }
  if ((line.itemKind === "equipment" && maximum !== 1)
      || (line.itemKind === "information" && byCapacity !== maximum)
      || (line.itemKind === "stack" && maximum !== 999999)) {
    fail("purchase_capacity_authority_invalid", "preview",
      "item-family capacity/maxQuantity authority differs from production rules", {
        itemKind: line.itemKind, maximum, byCapacity,
      });
  }
  const total = Number(line.total);
  if (total !== expectedTotal || !Number.isFinite(Number(balance)) || Number(balance) < total) {
    fail("purchase_total_invalid", "preview", "selected total or balance is invalid", {
      total,
      expectedTotal,
      balance,
    });
  }
  return total;
}

function requireTokenReference(message, key, phase) {
  const value = message && message[key];
  if (!own(message, key) || !/^sha256:[a-f0-9]{64}$/.test(String(value || ""))) {
    fail("authority_token_missing", phase, key + " must be one required token reference", { key });
  }
  return value;
}

function inputEvents(events, start, end) {
  return events.filter((event) => event.kind === "dom_input"
    && event.eventType === "click" && event.sequence > start && event.sequence < end);
}

function targetAttribute(event, name) {
  return event && event.target && event.target.attributes
    ? event.target.attributes[name]
    : undefined;
}

function assertTrustedVisibleButton(event, label) {
  const target = event && event.target;
  const rect = target && target.rect;
  const viewport = target && target.viewport;
  const point = target && target.clientPoint;
  const targetKeys = ["selector", "tagName", "text", "attributes", "visible", "enabled",
    "viewport", "rect", "clientPoint", "hitTargetMatches"];
  const rectKeys = ["left", "top", "right", "bottom", "width", "height"];
  const viewportKeys = ["width", "height", "devicePixelRatio", "scrollX", "scrollY"];
  if (!event || event.isTrusted !== true || event.button !== 0
      || event.key !== null || event.repeat !== false
      || !Number.isFinite(event.clientX) || !Number.isFinite(event.clientY)
      || !exactKeys(target, targetKeys) || target.tagName !== "BUTTON"
      || typeof target.selector !== "string" || !target.selector
      || !isPlainObject(target.attributes) || target.visible !== true || target.enabled !== true
      || !exactKeys(rect, rectKeys) || rectKeys.some((key) => !Number.isFinite(rect[key]))
      || rect.width <= 0 || rect.height <= 0 || rect.right !== rect.left + rect.width
      || rect.bottom !== rect.top + rect.height
      || !exactKeys(viewport, viewportKeys) || !Object.values(viewport).every(Number.isFinite)
      || viewport.width < 320 || viewport.height < 180 || viewport.devicePixelRatio <= 0
      || !exactKeys(point, ["x", "y"]) || !Number.isFinite(point.x) || !Number.isFinite(point.y)
      || point.x !== event.clientX || point.y !== event.clientY
      || event.clientX < rect.left || event.clientX > rect.right
      || event.clientY < rect.top || event.clientY > rect.bottom
      || event.clientX < 0 || event.clientX > viewport.width
      || event.clientY < 0 || event.clientY > viewport.height
      || target.hitTargetMatches !== true
      || !event.panelState || event.panelState.panel !== "kshop"
      || event.panelState.hidden !== false) {
    fail("trusted_business_input_invalid", "input",
      label + " is not one exact trusted left-button input on the visible KShop owner");
  }
  return event;
}

function providerObservationFromEvent(observerId, event) {
  const target = event.target;
  return { eventRef: { observerId, sequence: event.sequence, eventSha256: event.eventHash },
    observedAt: event.observedAt, eventType: event.eventType, isTrusted: event.isTrusted,
    selector: target.selector, tagName: target.tagName, visible: target.visible,
    enabled: target.enabled, viewport: target.viewport, rect: target.rect,
    clientPoint: target.clientPoint, hitTargetMatches: target.hitTargetMatches,
    key: event.key, button: event.button, repeat: event.repeat };
}

function assertTrustedFirstJourneyInputs(events, firstOpen, commitRequest, selection) {
  const clicks = inputEvents(events, firstOpen.event.sequence, commitRequest.event.sequence + 1);
  const addEvidence = [];
  selection.cart.forEach((target) => {
    const matches = clicks.filter((event) => String(targetAttribute(event, "data-idx"))
      === String(target.idx)
      && String(targetAttribute(event, "class") || "").split(/\s+/).includes("kshop-add-btn"));
    const exact = requireOne(matches, "target_click_count_invalid",
      "target add control was not clicked exactly once");
    assertTrustedVisibleButton(exact, "target add control");
    if (exact.target.selector !== "button[data-idx=\"" + target.idx + "\"]") {
      fail("trusted_business_selector_invalid", "input",
        "target add input selector differs from the selected catalog identity");
    }
    addEvidence.push({ catalogIndex: target.idx, sequence: exact.sequence });
  });
  const checkout = requireOne(clicks.filter((event) => event.target
    && event.target.selector === "#kshop-checkout"), "checkout_click_count_invalid",
  "checkout control was not clicked exactly once");
  assertTrustedVisibleButton(checkout, "checkout control");
  const commit = requireOne(clicks.filter((event) => targetAttribute(
    event, "data-kshop-settlement-commit") !== undefined), "commit_click_count_invalid",
  "settlement commit control was not clicked exactly once");
  assertTrustedVisibleButton(commit, "settlement commit control");
  if (commit.target.selector !== "[data-kshop-settlement-commit]") {
    fail("trusted_business_selector_invalid", "input",
      "settlement commit selector differs from the exact production control");
  }
  if (!(addEvidence.every((entry) => entry.sequence < checkout.sequence)
      && checkout.sequence < commit.sequence && commit.sequence < commitRequest.event.sequence)) {
    fail("trusted_input_order_invalid", "input", "trusted input order does not precede authority requests");
  }
  return { addEvidence, checkoutSequence: checkout.sequence, commitSequence: commit.sequence };
}

function assertTrustedCloseInputs(events, opens, closes) {
  return closes.map((close, index) => {
    const candidates = inputEvents(events, opens[index].event.sequence, close.event.sequence + 1)
      .filter((event) => targetAttribute(event, "data-header-action") === "close"
        || String(targetAttribute(event, "class") || "").split(/\s+/)
          .includes("kshop-close-btn"));
    const exact = requireOne(candidates, "close_click_count_invalid",
      "each KShop owner close requires one exact header-close click");
    const classes = String(targetAttribute(exact, "class") || "").split(/\s+/);
    assertTrustedVisibleButton(exact, "KShop close control");
    if (targetAttribute(exact, "data-header-action") !== "close"
        || !classes.includes("kshop-close-btn") || !classes.includes("workbench-close-btn")
        || exact.target.selector !== "[data-header-action=\"close\"]") {
      fail("trusted_close_input_invalid", "input",
        "owner close was not one exact trusted visible KShop header click", { index });
    }
    return { panelInstanceId: close.message.panelInstanceId, sequence: exact.sequence };
  });
}

function assertExactBusinessInputSet(events, opens, closes, inputs, closeInputs) {
  const expected = new Set(inputs.addEvidence.map((entry) => entry.sequence)
    .concat([inputs.checkoutSequence, inputs.commitSequence])
    .concat(closeInputs.map((entry) => entry.sequence)));
  const start = opens[0].event.sequence;
  const end = closes[1].event.sequence;
  const observed = events.filter((event) => event.kind === "dom_input"
    && event.sequence > start && event.sequence < end + 1);
  const extras = observed.filter((event) => !expected.has(event.sequence));
  if (observed.length !== expected.size || extras.length > 0
      || observed.some((event) => event.eventType !== "click")) {
    fail("trusted_business_input_multiset_invalid", "input",
      "KShop Web journey contains an extra, missing, or non-click business input", {
        observed: observed.map((entry) => entry.sequence), extras: extras.map((entry) => entry.sequence),
      });
  }
  return { trustedInputCount: observed.length };
}

function validateFacetList(values, maximum, depth, setMode, label) {
  if (!Array.isArray(values) || values.length > 64 || depth > 2) {
    fail("inventory_facets_invalid", "inventory", label + " facet list is malformed");
  }
  const ids = new Set();
  let total = 0;
  values.forEach((value) => {
    if (!exactKeys(value, ["id", "label", "order", "count", "children"])
        || typeof value.id !== "string" || !value.id || typeof value.label !== "string"
        || !value.label || !Number.isInteger(value.order) || !Number.isInteger(value.count)
        || value.count < 0 || value.count > maximum || ids.has(value.id)) {
      fail("inventory_facets_invalid", "inventory", label + " facet node is malformed");
    }
    ids.add(value.id);
    if (setMode && (!Array.isArray(value.children) || value.children.length !== 0)) {
      fail("inventory_facets_invalid", "inventory", label + " set facet must be a leaf");
    }
    if (!setMode) {
      const childTotal = validateFacetList(value.children, maximum, depth + 1, false, label);
      if (childTotal > value.count) fail("inventory_facets_invalid", "inventory",
        label + " child facet total exceeds its parent");
    }
    total += value.count;
    if (total > maximum) fail("inventory_facets_invalid", "inventory",
      label + " facet total exceeds accessible capacity");
  });
  return total;
}

function validateInventoryMod(value, label) {
  const keys = ["name", "displayName", "icon", "grade", "gradeLabel", "gradeColor",
    "role", "roleLabel", "symbol", "scope"];
  if (!exactKeys(value, keys) || keys.some((key) => typeof value[key] !== "string")
      || !value.name || !value.displayName || !value.icon) {
    fail("inventory_mod_invalid", "inventory", label + " mod projection is malformed");
  }
}

function validateInventoryItem(item, label) {
  const required = ["name", "displayName", "icon", "majorType", "use", "actionType",
    "weaponType", "setId", "setName", "setOrder", "itemKind", "quantity",
    "enhancementLevel", "maxEnhancementLevel", "isMaxEnhancement", "tierSlotAvailable",
    "tierSlotUsed", "modSlotCapacity", "modSlotUsed", "modSlots", "modMeta", "rarity"];
  const allowed = required.concat(["balanceSummary"]);
  if (!isPlainObject(item) || required.some((key) => !own(item, key))
      || Object.keys(item).some((key) => !allowed.includes(key))
      || ["name", "displayName", "icon"].some((key) => typeof item[key] !== "string" || !item[key])
      || ["majorType", "use", "actionType", "weaponType", "setId", "setName", "rarity"]
        .some((key) => typeof item[key] !== "string")
      || !["equipment", "stack"].includes(item.itemKind)
      || !Number.isSafeInteger(item.quantity) || !Number.isInteger(item.setOrder)
      || !Number.isInteger(item.enhancementLevel) || !Number.isInteger(item.maxEnhancementLevel)
      || !Number.isInteger(item.modSlotCapacity) || !Number.isInteger(item.modSlotUsed)
      || [item.enhancementLevel, item.maxEnhancementLevel, item.modSlotCapacity, item.modSlotUsed]
        .some((value) => value < 0)
      || typeof item.isMaxEnhancement !== "boolean"
      || typeof item.tierSlotAvailable !== "boolean" || typeof item.tierSlotUsed !== "boolean"
      || item.tierSlotUsed && !item.tierSlotAvailable
      || item.isMaxEnhancement !== (item.itemKind === "equipment"
        && item.enhancementLevel >= item.maxEnhancementLevel)
      || (item.itemKind === "equipment" && item.quantity !== 1)
      || (item.itemKind === "stack" && (item.quantity <= 0 || item.enhancementLevel !== 0
        || item.isMaxEnhancement || item.tierSlotAvailable || item.tierSlotUsed
        || item.modSlotCapacity !== 0 || item.modSlotUsed !== 0))) {
    fail("inventory_item_invalid", "inventory", label + " item projection is malformed");
  }
  if (!Array.isArray(item.modSlots) || item.modSlots.length > 3
      || item.modSlots.length > item.modSlotUsed) {
    fail("inventory_item_invalid", "inventory", label + " mod slot projection is malformed");
  }
  item.modSlots.forEach((value, index) => validateInventoryMod(value, label + ".modSlots[" + index + "]"));
  if (item.modMeta !== null) validateInventoryMod(item.modMeta, label + ".modMeta");
  if (own(item, "balanceSummary")
      && (!exactKeys(item.balanceSummary, ["state", "weightLayers", "formula", "level"])
        || item.balanceSummary.state !== "confirmed"
        || !Number.isInteger(item.balanceSummary.weightLayers)
        || item.balanceSummary.formula !== 1 || !Number.isInteger(item.balanceSummary.level)
        || item.balanceSummary.level < 0)) {
    fail("inventory_balance_summary_invalid", "inventory",
      label + " balance summary is malformed");
  }
  return item;
}

function validateConfirmProjection(confirm, item, label) {
  const keys = ["itemKind", "name", "displayName", "quantity", "enhancementLevel",
    "rarity", "tier", "modSignature", "lastUpdate"];
  if (!exactKeys(confirm, keys) || confirm.itemKind !== item.itemKind
      || confirm.name !== item.name || confirm.displayName !== item.displayName
      || confirm.quantity !== item.quantity || confirm.enhancementLevel !== item.enhancementLevel
      || confirm.rarity !== item.rarity
      || ["tier", "modSignature"].some((key) => typeof confirm[key] !== "string")
      || !Number.isSafeInteger(confirm.lastUpdate) || confirm.lastUpdate < 0) {
    fail("inventory_confirm_projection_invalid", "inventory",
      label + " confirmation projection is detached from its item");
  }
}

function expectedInventoryBatches(accessibleCapacity) {
  const batches = [[INVENTORY_BAG_PROBE, INVENTORY_BATTLE_PROBE]];
  if (accessibleCapacity > 100) batches.push([
    { containerId: "战备箱", offset: 100, limit: 100, filterKey: "all" },
  ]);
  if (accessibleCapacity > 200) batches.push([
    { containerId: "战备箱", offset: 200,
      limit: accessibleCapacity - 200, filterKey: "all" },
  ]);
  return batches;
}

function validateInventorySnapshot(snapshot, requested, accessibleCapacity, label, location) {
  const bag = requested.containerId === "背包";
  const physicalCapacity = bag ? 50 : 400;
  const access = bag ? 50 : accessibleCapacity;
  const expectedLimit = bag ? 50
    : Math.min(requested.limit, Math.max(0, accessibleCapacity - requested.offset));
  const keys = ["containerId", "capacity", "accessibleCapacity", "viewCapacity", "filterKey",
    "pageSizeHint", "locked", "snapshotSeq", "containerEpoch", "containerVersion",
    "offset", "limit", "slots", "filterFacets", "filterItemCount", "setFacets",
    "setFilterItemCount"];
  if (!exactKeys(snapshot, keys) || snapshot.containerId !== requested.containerId
      || requested.filterKey !== "all" || snapshot.filterKey !== "all"
      || snapshot.capacity !== physicalCapacity || snapshot.accessibleCapacity !== access
      || snapshot.viewCapacity !== access || snapshot.pageSizeHint !== (bag ? 50 : 40)
      || snapshot.locked !== (!bag && accessibleCapacity === 0)
      || !Number.isInteger(snapshot.snapshotSeq) || snapshot.snapshotSeq < 1
      || !Number.isInteger(snapshot.containerEpoch) || snapshot.containerEpoch < 1
      || !Number.isInteger(snapshot.containerVersion) || snapshot.containerVersion < 0
      || snapshot.offset !== requested.offset || snapshot.limit !== expectedLimit
      || !Array.isArray(snapshot.slots) || snapshot.slots.length !== expectedLimit
      || !Number.isInteger(snapshot.filterItemCount) || snapshot.filterItemCount < 0
      || !Number.isInteger(snapshot.setFilterItemCount) || snapshot.setFilterItemCount < 0
      || snapshot.setFilterItemCount > snapshot.filterItemCount) {
    fail("inventory_snapshot_invalid", "inventory", label + " snapshot projection is malformed", {
      location,
    });
  }
  const counts = Object.create(null);
  snapshot.slots.forEach((slot, index) => {
    if (!isPlainObject(slot) || slot.physicalSlot !== snapshot.offset + index
        || typeof slot.occupied !== "boolean"
        || !/^sha256:[a-f0-9]{64}$/.test(String(slot.slotLease || ""))) {
      fail("inventory_slot_invalid", "inventory", label + " slot projection is malformed", {
        location, index,
      });
    }
    if (!slot.occupied) {
      if (!exactKeys(slot, ["physicalSlot", "occupied", "slotLease"])) {
        fail("inventory_empty_slot_invalid", "inventory",
          label + " empty slot carries an extra projection");
      }
      return;
    }
    if (!exactKeys(slot, ["physicalSlot", "occupied", "slotLease", "item", "confirmProjection"])) {
      fail("inventory_occupied_slot_invalid", "inventory",
        label + " occupied slot lacks the exact item/confirm projection");
    }
    const item = validateInventoryItem(slot.item, label + "." + location + ".slots[" + index + "]");
    validateConfirmProjection(slot.confirmProjection, item,
      label + "." + location + ".slots[" + index + "]");
    const identity = { name: item.name, displayName: item.displayName, icon: item.icon };
    const key = canonicalJson(identity);
    counts[key] = (counts[key] || 0) + item.quantity;
  });
  const facetTotal = validateFacetList(snapshot.filterFacets,
    snapshot.accessibleCapacity, 0, false, label + "." + location + ".filterFacets");
  const setFacetTotal = validateFacetList(snapshot.setFacets,
    snapshot.accessibleCapacity, 0, true, label + "." + location + ".setFacets");
  if (facetTotal !== snapshot.filterItemCount || setFacetTotal !== snapshot.setFilterItemCount) {
    fail("inventory_facet_total_invalid", "inventory",
      label + " facet totals differ from the authenticated snapshot counts");
  }
  return counts;
}

function validateInventorySurface(pairs, label) {
  if (!Array.isArray(pairs) || pairs.length < 1 || pairs.length > 3) {
    fail("inventory_surface_pair_set_invalid", "inventory",
      label + " requires one exact ordered probe/supplement pair-set");
  }
  const responseKeys = ["type", "domain", "panel", "panelInstanceId", "cmd", "callId",
    "success", "v", "sessionNonce", "snapshots"];
  pairs.forEach((pair, pairOrdinal) => {
    const request = pair && pair.request && pair.request.message;
    const response = pair && pair.response && pair.response.message;
    if (!request || !response || !exactKeys(response, responseKeys)
        || response.type !== "panel_resp" || response.domain !== "inventory"
        || response.panel !== "kshop" || response.cmd !== "snapshot"
        || response.success !== true || response.v !== 1
        || response.callId !== request.callId
        || response.panelInstanceId !== request.panelInstanceId
        || !Array.isArray(response.snapshots)) {
      fail("inventory_surface_order_invalid", "inventory",
        label + " pair-set has an incomplete or malformed callback response", {
          pairOrdinal,
        });
    }
  });
  const firstSnapshots = pairs[0] && pairs[0].response && pairs[0].response.message
    && pairs[0].response.message.snapshots;
  const firstBattle = Array.isArray(firstSnapshots) ? firstSnapshots[1] : null;
  const accessibleCapacity = Number(firstBattle && firstBattle.accessibleCapacity);
  if (!INVENTORY_BATTLE_ACCESS.has(accessibleCapacity)) {
    fail("inventory_battle_access_invalid", "inventory",
      label + " battle-box access is not one production 40-slot tier");
  }
  const expectedBatches = expectedInventoryBatches(accessibleCapacity);
  if (pairs.length !== expectedBatches.length) {
    fail("inventory_surface_pair_set_invalid", "inventory",
      label + " pair-set does not cover the declared battle-box tail", {
        accessibleCapacity, expected: expectedBatches.length, actual: pairs.length,
      });
  }
  let owner = null;
  let sessionNonce = null;
  let previousResponseSequence = -1;
  let battleAnchor = null;
  let lastBattleSnapshotSeq = -1;
  const callIds = new Set();
  const windows = [];
  const counts = Object.create(null);
  const timeline = [];
  pairs.forEach((pair, pairOrdinal) => {
    const requestEntry = pair && pair.request;
    const responseEntry = pair && pair.response;
    const request = requestEntry && requestEntry.message;
    const response = responseEntry && responseEntry.message;
    const expected = expectedBatches[pairOrdinal];
    if (!requestEntry || !responseEntry || !request || !response
        || !exactKeys(request.payload, ["v", "requests"]) || request.payload.v !== 1
        || !deepEqual(request.payload.requests, expected)
        || !exactKeys(response, responseKeys) || response.type !== "panel_resp"
        || response.domain !== "inventory" || response.panel !== "kshop"
        || response.cmd !== "snapshot" || response.success !== true || response.v !== 1
        || typeof request.callId !== "string" || !request.callId || callIds.has(request.callId)
        || response.callId !== request.callId
        || response.panelInstanceId !== request.panelInstanceId
        || !Array.isArray(response.snapshots) || response.snapshots.length !== expected.length
        || requestEntry.event.sequence <= previousResponseSequence
        || responseEntry.event.sequence <= requestEntry.event.sequence) {
      fail("inventory_surface_order_invalid", "inventory",
        label + " pair-set has an extra field, wrong request, owner drift, or reordered call", {
          pairOrdinal,
        });
    }
    callIds.add(request.callId);
    previousResponseSequence = responseEntry.event.sequence;
    const pairOwner = [request.panel, request.panelInstanceId, request.domain, request.cmd].join("|");
    if (owner == null) owner = pairOwner;
    if (pairOwner !== owner || request.panel !== "kshop" || request.domain !== "inventory"
        || request.cmd !== "snapshot") {
      fail("inventory_surface_owner_drift", "inventory",
        label + " Inventory pairs do not share one exact owner");
    }
    if (sessionNonce == null) sessionNonce = response.sessionNonce;
    if (typeof response.sessionNonce !== "string" || !response.sessionNonce
        || response.sessionNonce !== sessionNonce) {
      fail("inventory_surface_session_drift", "inventory",
        label + " Inventory pairs do not share one exact session nonce");
    }
    timeline.push({ pairOrdinal, callId: request.callId,
      requestSequence: requestEntry.event.sequence, responseSequence: responseEntry.event.sequence,
      requestAt: requestEntry.event.observedAt, responseAt: responseEntry.event.observedAt });
    expected.forEach((requested, requestOrdinal) => {
      const snapshot = response.snapshots[requestOrdinal];
      const windowCounts = validateInventorySnapshot(snapshot, requested, accessibleCapacity,
        label, "pairs[" + pairOrdinal + "].snapshots[" + requestOrdinal + "]");
      Object.keys(windowCounts).forEach((key) => {
        counts[key] = (counts[key] || 0) + windowCounts[key];
      });
      if (snapshot.containerId === "战备箱") {
        const durable = { capacity: snapshot.capacity,
          accessibleCapacity: snapshot.accessibleCapacity, viewCapacity: snapshot.viewCapacity,
          pageSizeHint: snapshot.pageSizeHint, locked: snapshot.locked,
          filterKey: snapshot.filterKey, containerEpoch: snapshot.containerEpoch,
          containerVersion: snapshot.containerVersion, filterFacets: snapshot.filterFacets,
          filterItemCount: snapshot.filterItemCount, setFacets: snapshot.setFacets,
          setFilterItemCount: snapshot.setFilterItemCount };
        if (battleAnchor == null) battleAnchor = durable;
        else if (!deepEqual(battleAnchor, durable)) {
          fail("inventory_surface_revision_drift", "inventory",
            label + " battle-box metadata/epoch/version drifted during one phase");
        }
        if (snapshot.snapshotSeq <= lastBattleSnapshotSeq) {
          fail("inventory_surface_sequence_drift", "inventory",
            label + " battle-box snapshot sequence did not advance across supplements");
        }
        lastBattleSnapshotSeq = snapshot.snapshotSeq;
      }
      windows.push({ pairOrdinal, requestOrdinal, callId: request.callId,
        request: JSON.parse(JSON.stringify(requested)), snapshot: JSON.parse(JSON.stringify(snapshot)) });
    });
  });
  const physicalSlots = ["背包", "战备箱"].map((containerId) => {
    const source = windows.filter((entry) => entry.snapshot.containerId === containerId);
    const slots = source.flatMap((entry) => entry.snapshot.slots);
    const expectedCount = containerId === "背包" ? 50 : accessibleCapacity;
    if (slots.length !== expectedCount
        || slots.some((slot, index) => slot.physicalSlot !== index)) {
      fail("inventory_surface_incomplete", "inventory",
        label + " has a hidden tail, gap, overlap, or reordered physical slot", {
          containerId, expectedCount, actualCount: slots.length,
        });
    }
    return { containerId, slots: JSON.parse(JSON.stringify(slots)) };
  });
  const bagWindow = windows.find((entry) => entry.snapshot.containerId === "背包").snapshot;
  const battleWindow = windows.find((entry) => entry.snapshot.containerId === "战备箱").snapshot;
  return { schema: INVENTORY_SURFACE_SCHEMA, label,
    panelInstanceId: pairs[0].request.message.panelInstanceId,
    sessionNonce, accessibleCapacity, callIds: pairs.map((pair) => pair.request.message.callId),
    pairs, timeline, windows, firstPair: pairs[0], lastPair: pairs[pairs.length - 1], counts,
    profiles: [bagWindow, battleWindow].map((snapshot) => ({
      containerId: snapshot.containerId, capacity: snapshot.capacity,
      accessibleCapacity: snapshot.accessibleCapacity, viewCapacity: snapshot.viewCapacity,
      filterKey: snapshot.filterKey, pageSizeHint: snapshot.pageSizeHint,
      locked: snapshot.locked, offset: 0,
      limit: snapshot.containerId === "背包" ? 50 : accessibleCapacity,
    })),
    revisions: { bag: { containerEpoch: bagWindow.containerEpoch,
      containerVersion: bagWindow.containerVersion },
    battle: { containerEpoch: battleWindow.containerEpoch,
      containerVersion: battleWindow.containerVersion } },
    physicalSlots };
}

function validateInventoryResponse(response, request, label) {
  const event = { sequence: 1, observedAt: "1970-01-01T00:00:00.000Z" };
  const responseEvent = { sequence: 2, observedAt: "1970-01-01T00:00:00.001Z" };
  return validateInventorySurface([{ request: { message: request, event },
    response: { message: response, event: responseEvent } }], label);
}

function inventoryCounts(response, request) {
  return validateInventoryResponse(response, request, "inventory").counts;
}

function targetInventoryKey(selection) {
  return canonicalJson({ name: selection.itemName,
    displayName: selection.displayName, icon: selection.icon });
}

function assertInventoryDelta(before, after, selection) {
  const expectedDelta = new Map([[targetInventoryKey(selection), selection.quantity]]);
  const keys = new Set(Object.keys(before).concat(Object.keys(after)));
  keys.forEach((key) => {
    const delta = Number(after[key] || 0) - Number(before[key] || 0);
    const expected = expectedDelta.get(key) || 0;
    if (delta !== expected) {
      fail("inventory_collateral_delta_invalid", "inventory",
        "inventory multiset changed outside the selected identity triple", { key, delta, expected });
    }
  });
  const key = targetInventoryKey(selection);
  const oldCount = Number(before[key] || 0);
  const newCount = Number(after[key] || 0);
  if (newCount !== oldCount + selection.quantity) {
    fail("inventory_delivery_delta_invalid", "inventory",
      "selected inventory count did not increase by the authorized quantity", {
        itemName: selection.itemName,
        before: oldCount,
        after: newCount,
      });
  }
}

function matchesDeliveryIdentity(item, selection) {
  return item && item.name === selection.itemName
    && item.displayName === selection.displayName && item.icon === selection.icon;
}

function exactAllowedDeliveryTargets(before, selection, itemKind) {
  const backpacks = before.filter((entry) => entry && entry.containerId === "背包");
  if (backpacks.length !== 1 || !Array.isArray(backpacks[0].slots)) {
    fail("inventory_delivery_surface_invalid", "inventory",
      "the initial physical projection lacks one exact backpack destination");
  }
  if (itemKind !== "equipment" || !selection.deliveryContract
      || selection.deliveryContract.authorityItemKind !== itemKind
      || selection.deliveryContract.destination !== "backpack_first_vacancy"
      || selection.deliveryContract.destinationSurface !== "inventory.physical.背包"
      || selection.deliveryContract.stateDependent !== false
      || selection.deliveryContract.executableJourneyEligible !== true) {
    fail("inventory_delivery_destination_unsupported", "inventory",
      "the selected item family is not the stateless AS2 equipment→backpack contract", {
        itemKind, deliveryContract: selection.deliveryContract,
      });
  }
  const slots = backpacks[0].slots;
  const target = slots.find((slot) => slot && slot.occupied === false) || null;
  if (!target) {
    fail("inventory_delivery_target_unavailable", "inventory",
      "the initial backpack has no production-legal merge slot or first vacancy");
  }
  return [{ containerId: "背包", physicalSlot: target.physicalSlot,
    placement: "first_vacancy" }];
}

function inventorySlotSemantics(slot) {
  const value = JSON.parse(JSON.stringify(slot));
  delete value.slotLease;
  return value;
}

function assertPhysicalInventoryDelta(beforeSurface, afterSurface, selection, itemKind) {
  const before = beforeSurface && beforeSurface.physicalSlots;
  const after = afterSurface && afterSurface.physicalSlots;
  if (!Array.isArray(before) || !Array.isArray(after) || before.length !== after.length
      || before.some((entry, index) => !entry || !after[index]
        || entry.containerId !== after[index].containerId
        || !Array.isArray(entry.slots) || !Array.isArray(after[index].slots)
        || entry.slots.length !== after[index].slots.length)) {
    fail("inventory_physical_projection_invalid", "inventory",
      "physical container/slot projections are not comparable");
  }
  const changed = [];
  before.forEach((container, containerIndex) => {
    container.slots.forEach((slot, slotIndex) => {
      const next = after[containerIndex].slots[slotIndex];
      if (!deepEqual(inventorySlotSemantics(slot), inventorySlotSemantics(next))) {
        changed.push({ containerId: container.containerId,
        physicalSlot: slot.physicalSlot, before: slot, after: next });
      }
    });
  });
  if (changed.length !== 1) {
    fail("inventory_physical_delta_invalid", "inventory",
      "commit must change exactly one physical target slot and no collateral slot", {
        changed: changed.map((entry) => entry.containerId + ":" + entry.physicalSlot),
      });
  }
  const delta = changed[0];
  const allowedTargets = exactAllowedDeliveryTargets(before, selection, itemKind);
  const allowed = allowedTargets.find((target) => target.containerId === delta.containerId
    && target.physicalSlot === delta.physicalSlot);
  if (!allowed) {
    fail("inventory_delivery_target_invalid", "inventory",
      "the unique physical delta is outside the exact production delivery target set", {
        actual: delta.containerId + ":" + delta.physicalSlot,
        allowed: allowedTargets.map((target) => target.containerId + ":" + target.physicalSlot),
      });
  }
  const prior = delta.before;
  const next = delta.after;
  if (!next.occupied || !matchesDeliveryIdentity(next.item, selection)
      || next.item.itemKind !== itemKind || next.slotLease === prior.slotLease) {
    fail("inventory_target_slot_invalid", "inventory",
      "changed physical slot lacks the exact selected family/identity or a fresh target lease");
  }
  const priorQuantity = prior.occupied ? Number(prior.item && prior.item.quantity) : 0;
  if (prior.occupied && (!matchesDeliveryIdentity(prior.item, selection)
      || prior.item.itemKind !== "stack" || itemKind !== "stack")
      || Number(next.item.quantity) - priorQuantity !== Number(selection.quantity)) {
    fail("inventory_target_slot_invalid", "inventory",
      "target physical slot quantity delta differs from the authorized delivery");
  }
  if (prior.occupied) {
    const normalizedNext = JSON.parse(JSON.stringify(next));
    normalizedNext.slotLease = prior.slotLease;
    normalizedNext.item.quantity = prior.item.quantity;
    normalizedNext.confirmProjection.quantity = prior.confirmProjection.quantity;
    normalizedNext.confirmProjection.lastUpdate = prior.confirmProjection.lastUpdate;
    if (next.confirmProjection.lastUpdate < prior.confirmProjection.lastUpdate) {
      fail("inventory_target_slot_drift", "inventory",
        "merged target lastUpdate regressed across the authorized delivery");
    }
    if (!deepEqual(normalizedNext, prior)) fail("inventory_target_slot_drift", "inventory",
      "existing target stack changed fields outside quantity, lease, and lastUpdate");
  }
  const beforeBattle = before.find((entry) => entry.containerId === "战备箱");
  const afterBattle = after.find((entry) => entry.containerId === "战备箱");
  if (beforeSurface.sessionNonce !== afterSurface.sessionNonce
      || beforeSurface.accessibleCapacity !== afterSurface.accessibleCapacity
      || !deepEqual(beforeSurface.revisions.battle, afterSurface.revisions.battle)
      || !deepEqual(beforeBattle, afterBattle)
      || beforeSurface.revisions.bag.containerEpoch
        !== afterSurface.revisions.bag.containerEpoch
      || afterSurface.revisions.bag.containerVersion
        <= beforeSurface.revisions.bag.containerVersion) {
    fail("inventory_revision_or_lease_rule_invalid", "inventory",
      "post-commit surface violated same-session bag/battle revision and lease rules");
  }
  return { containerId: delta.containerId, physicalSlot: delta.physicalSlot,
    quantityBefore: priorQuantity, quantityAfter: next.item.quantity,
    quantityDelta: Number(selection.quantity), placement: allowed.placement };
}

function assertRestartInventory(afterSurface, restartSurface) {
  if (!deepEqual(afterSurface.profiles, restartSurface.profiles)
      || afterSurface.accessibleCapacity !== restartSurface.accessibleCapacity
      || afterSurface.sessionNonce === restartSurface.sessionNonce) {
    fail("restart_inventory_profile_invalid", "inventory",
      "restart must re-probe the same surface under one fresh Inventory session");
  }
  const after = afterSurface.physicalSlots;
  const restart = restartSurface.physicalSlots;
  if (!Array.isArray(after) || !Array.isArray(restart) || after.length !== restart.length) {
    fail("restart_inventory_physical_invalid", "inventory",
      "restart physical surface is not comparable with post-commit authority");
  }
  after.forEach((container, containerIndex) => {
    const nextContainer = restart[containerIndex];
    if (!nextContainer || nextContainer.containerId !== container.containerId
        || nextContainer.slots.length !== container.slots.length) {
      fail("restart_inventory_physical_invalid", "inventory",
        "restart container order or declared surface changed");
    }
    container.slots.forEach((slot, slotIndex) => {
      const next = nextContainer.slots[slotIndex];
      if (!deepEqual(inventorySlotSemantics(slot), inventorySlotSemantics(next))
          || slot.slotLease === next.slotLease) {
        fail("restart_inventory_slot_or_lease_invalid", "inventory",
          "restart must preserve every slot semantic and rotate every session-bound lease", {
            containerId: container.containerId, physicalSlot: slot.physicalSlot,
          });
      }
    });
  });
}

function assertCountsEqual(left, right, code) {
  if (canonicalJson(left) !== canonicalJson(right)) {
    fail(code, "inventory", "fresh inventory readback changed the complete identity multiset");
  }
}

function parseTimestampedHostLine(line, sourceLineNumber, lifecycle) {
  const match = /^(\d{2}):(\d{2}):(\d{2})\.(\d{3}) ([^\r\n]+)$/.exec(String(line || ""));
  const hour = match && Number(match[1]);
  const minute = match && Number(match[2]);
  const second = match && Number(match[3]);
  if (!match || hour > 23 || minute > 59 || second > 59) {
    fail("host_log_formatter_invalid", "host_log",
      "Host log record is not one exact timestamped LogManager line", {
        sourceLineNumber, lifecycle,
      });
  }
  return { body: match[5], timestamp: match[1] + ":" + match[2] + ":" + match[3]
      + "." + match[4],
    timeOfDayMs: ((hour * 60 + minute) * 60 + second) * 1000 + Number(match[4]) };
}

function hostMoment(snapshotCapturedAt, timeOfDayMs) {
  const snapshot = new Date(snapshotCapturedAt);
  if (!Number.isFinite(snapshot.getTime()) || !Number.isInteger(timeOfDayMs)
      || timeOfDayMs < 0 || timeOfDayMs >= 86400000) {
    fail("host_timeline_time_invalid", "timeline",
      "Host formatter time cannot be placed on the authenticated snapshot date");
  }
  let moment = new Date(snapshot.getFullYear(), snapshot.getMonth(), snapshot.getDate(),
    0, 0, 0, timeOfDayMs).getTime();
  if (moment > snapshot.getTime() + 1000) moment -= 86400000;
  if (snapshot.getTime() - moment > 86400000) {
    fail("host_timeline_time_invalid", "timeline",
      "Host formatter time falls outside the authenticated snapshot window");
  }
  return moment;
}

function hostRecords(bundle) {
  const hostLog = bundle.hostLog;
  if (!isPlainObject(hostLog) || hostLog.schema !== "workbench-live-e2e.kshop.host-lifecycles.v1"
      || !Array.isArray(hostLog.lifecycles) || hostLog.lifecycles.length !== 2
      || canonicalJson(hostLog.lifecycles.map((entry) => entry && entry.label))
        !== canonicalJson(["first", "restart"])) {
    fail("host_log_missing", "host_log", "two exact authenticated Host lifecycle tails are required");
  }
  const records = [];
  hostLog.lifecycles.forEach((lifecycle, lifecycleIndex) => {
    LauncherObservation.verifySessionEvidenceEnvelope(lifecycle.sessionEvidence);
    LauncherObservation.verifyTerminalLogBoundary(lifecycle.boundary);
    LauncherObservation.verifyLogSnapshot(lifecycle.terminalSnapshot);
    if (lifecycle.sessionEvidence.sessionEvidenceSha256
          !== lifecycle.boundary.terminalSessionEvidenceSha256
        || lifecycle.sessionEvidence.sessionEvidenceSha256
          !== lifecycle.terminalSnapshot.sessionEvidenceSha256) {
      fail("host_log_session_mismatch", "host_log",
        "Host boundary/tail is not bound to its exact authenticated lifecycle", { label: lifecycle.label });
    }
    let previousHostEpochMs = null;
    LauncherObservation.recordsAfterTerminalBoundary(lifecycle.boundary,
      lifecycle.terminalSnapshot).forEach((record) => {
      const parsed = parseTimestampedHostLine(record.line, record.lineNumber, lifecycle.label);
      const hostEpochMs = hostMoment(lifecycle.terminalSnapshot.capturedAt, parsed.timeOfDayMs);
      if (previousHostEpochMs != null && hostEpochMs < previousHostEpochMs) {
        fail("host_log_clock_regressed", "host_log",
          "timestamped Host records regress within one authenticated lifecycle", {
            lifecycle: lifecycle.label, sourceLineNumber: record.lineNumber,
          });
      }
      previousHostEpochMs = hostEpochMs;
      records.push({ lineNumber: records.length + 1, sourceLineNumber: record.lineNumber,
        lifecycle: lifecycle.label, lifecycleIndex, body: parsed.body,
        timestamp: parsed.timestamp, timeOfDayMs: parsed.timeOfDayMs,
        hostEpochMs, hostObservedAt: new Date(hostEpochMs).toISOString() });
    });
  });
  if (records.length < 1) fail("host_log_empty", "host_log", "authenticated Host tails are empty");
  return records;
}

const AUTHORITY_KEYS = Object.freeze([
  "expectedTuningToken", "tuningToken", "expectedCheckoutToken", "checkoutToken",
  "expectedPurchasedToken", "purchasedToken", "expectedCraftToken", "craftToken",
  "expectedBatchToken", "batchToken", "expectedTradeToken", "tradeToken",
  "expectedLearnToken", "learnToken", "expectedLease", "slotLease", "closeLease",
  "transactionId",
]);
const SHOP_FLASH_ACTIONS = new Set(Object.values(SHOP_ACTIONS));
const INVENTORY_FLASH_ACTIONS = new Set(["inventorySnapshot", "inventoryTooltip"]);

function parseAuthorityTail(tail, record) {
  const fields = Object.create(null);
  const text = String(tail || "");
  if (!text) return fields;
  if (!/^ (?:[A-Za-z][A-Za-z0-9]*=[^\s]+)(?: [A-Za-z][A-Za-z0-9]*=[^\s]+)*$/.test(text)) {
    fail("host_authority_summary_invalid", "host_log",
      "authority summary tail is not one exact key/value sequence", { lineNumber: record.lineNumber });
  }
  text.trim().split(/\s+/).forEach((entry) => {
    const separator = entry.indexOf("=");
    const key = entry.slice(0, separator);
    const value = entry.slice(separator + 1);
    const authorityBase = AUTHORITY_KEYS.find((candidate) => key.startsWith(candidate)) || null;
    const suffix = authorityBase ? key.slice(authorityBase.length) : "";
    const numeric = ["authorityFieldCount", "unknownAuthorityFieldCount",
      "unknownAuthorityRefCount"].includes(key) || suffix === "RefCount";
    const reference = suffix === "Ref" || suffix === "Refs" || key === "unknownAuthorityRefs";
    const present = suffix === "Present";
    if (Object.prototype.hasOwnProperty.call(fields, key)
        || (!numeric && !reference && !present)
        || (numeric && !/^(?:0|[1-9]\d*)$/.test(value))
        || (reference && !/^sha256_[a-f0-9]{24}(?:,sha256_[a-f0-9]{24}){0,3}$/.test(value))
        || (present && value !== "true")) {
      fail("host_authority_summary_invalid", "host_log",
        "authority summary contains an unknown, duplicate, or malformed field", {
          lineNumber: record.lineNumber, key,
        });
    }
    fields[key] = value;
  });
  return fields;
}

function parsePanelSummary(record) {
  const prefix = "[Panel] HandlePanelMessage: ";
  if (!record.body.startsWith(prefix)) return null;
  const match = /^task=panel panel=(kshop|workbench|crafting|npcshop|skills|loot|other) domain=(inventory|npcshop|crafting|equipment_tuning|tuning|loadout|skills|other) cmd=([A-Za-z][A-Za-z0-9]*|other) callId=([A-Za-z0-9._:-]{1,96}|other)( envelope=near_match)? payload=redacted len=(\d+)(.*)$/
    .exec(record.body.slice(prefix.length));
  if (!match || match[5]) fail("host_panel_summary_invalid", "host_log",
    "KShop Host panel log is not one exact redacted envelope", { lineNumber: record.lineNumber });
  return { panel: match[1], domain: match[2], cmd: match[3], callId: match[4],
    payloadLength: Number(match[6]), authority: parseAuthorityTail(match[7], record) };
}

function parseFlashSend(record, component) {
  const prefix = "[" + component + "] -> Flash: ";
  if (!record.body.startsWith(prefix)) return null;
  const match = /^task=cmd cmd=([A-Za-z][A-Za-z0-9]*|other) callId=(\d+|other) payload=redacted len=(\d+)(.*)$/
    .exec(record.body.slice(prefix.length));
  if (!match || match[2] === "other") fail("host_flash_summary_invalid", "host_log",
    "Host→Flash log is not one exact redacted command", { lineNumber: record.lineNumber, component });
  const action = match[1];
  const allowed = component === "ShopTask" ? SHOP_FLASH_ACTIONS : INVENTORY_FLASH_ACTIONS;
  if (!allowed.has(action)) fail("host_flash_summary_invalid", "host_log",
    "Host→Flash summary action is outside the exact KShop allowlist", {
      lineNumber: record.lineNumber, component, action,
    });
  return { task: "cmd", action, callId: Number(match[2]), payloadLength: Number(match[3]),
    authority: parseAuthorityTail(match[4], record) };
}

function parsePanelRoute(record) {
  const prefix = "[Panel] Routing ";
  if (!record.body.startsWith(prefix)) return null;
  let match = /^domain=inventory cmd=([A-Za-z][A-Za-z0-9]*) to InventoryTask, _inventoryTask=ok$/
    .exec(record.body.slice(prefix.length));
  if (match) return { domain: "inventory", cmd: match[1], component: "InventoryTask" };
  match = /^cmd=([A-Za-z][A-Za-z0-9]*) to ShopTask, _shopTask=ok$/
    .exec(record.body.slice(prefix.length));
  if (match) return { domain: "shop", cmd: match[1], component: "ShopTask" };
  fail("host_route_invalid", "host_log",
    "KShop Host route is not one exact closed-field route", { lineNumber: record.lineNumber });
}

function parseSocketResponse(record) {
  const prefix = "[XmlSocket:JSON] ";
  if (!record.body.startsWith(prefix)) return null;
  const text = record.body.slice(prefix.length);
  if (/^[{[]/.test(text)) fail("host_socket_unredacted_forbidden", "host_log",
    "authority socket evidence must be the centralized redacted top-level summary", {
      lineNumber: record.lineNumber,
    });
  const match = /^task=(shop_response|inventory_response) cmd=([A-Za-z][A-Za-z0-9]*|other) callId=(\d+|other) success=(true|false|unknown) payload=redacted len=(\d+)(.*)$/.exec(text);
  if (!match) {
    if (/^task=(?:shop_response|inventory_response|authority_response_family)\b/.test(text)
        || /\benvelope=near_match\b/.test(text)) {
      fail("host_socket_summary_invalid", "host_log",
        "authority socket response is not one exact closed-field summary", {
          lineNumber: record.lineNumber,
        });
    }
    return null;
  }
  if (match[3] === "other") fail("host_socket_summary_invalid", "host_log",
    "authority socket response lacks a top-level integer callId", { lineNumber: record.lineNumber });
  return { task: match[1], cmd: match[2], callId: Number(match[3]), success: match[4],
    payloadLength: Number(match[5]), authority: parseAuthorityTail(match[6], record) };
}

function assertNoHostAuthorityAnomalies(records) {
  const rejection = records.filter((record) =>
    /^(?:\[ShopTask\]|\[InventoryTask\]|event=foreign_panel_close_rejected)/.test(record.body)
    && /(?:rejected|not queued|superseded|ignored after replacement|expired\/foreign)/i
      .test(record.body));
  if (rejection.length > 0) {
    fail("host_authority_rejection_observed", "host_log",
      "authenticated KShop lifecycle contains a rejection/supersession record", {
        lines: rejection.map((entry) => entry.lineNumber),
      });
  }
  records.forEach((record) => { parsePanelSummary(record); parseSocketResponse(record); });
}

function parseShopHandle(record) {
  const prefix = "[ShopTask] HandleWebRequest: cmd=";
  if (!record.body.startsWith(prefix)) return null;
  const cmd = record.body.slice(prefix.length);
  if (!Object.prototype.hasOwnProperty.call(SHOP_ACTIONS, cmd)) {
    fail("host_shop_handle_invalid", "host_log",
      "ShopTask consumer record is outside the exact KShop command set", {
        lineNumber: record.lineNumber, cmd,
      });
  }
  return { cmd };
}

function assertGlobalRelevantHostSet(records, mappings) {
  const handles = [];
  const opens = [];
  const closed = [];
  const unknown = [];
  records.forEach((record) => {
    const body = record.body;
    let recognized = false;
    if (body.startsWith("[ShopTask]")) {
      const handle = parseShopHandle(record);
      const send = parseFlashSend(record, "ShopTask");
      recognized = !!handle || !!send || body === "[ShopTask] <- Flash response received";
      if (handle) handles.push({ lifecycle: record.lifecycle, cmd: handle.cmd });
    } else if (body.startsWith("[InventoryTask]")) {
      recognized = !!parseFlashSend(record, "InventoryTask");
    } else if (body.startsWith("event=authority_flash_call_bound")) {
      recognized = !!parseAuthorityFlashBinding(record);
    } else if (body.startsWith("event=panel_exact_close_completed")) {
      recognized = !!parsePanelExactCloseCompleted(record);
    } else if (body.startsWith("[XmlSocket:JSON] ")) {
      recognized = !!parseSocketResponse(record);
    } else if (body.startsWith("[Panel] HandlePanelMessage: ")) {
      const summary = parsePanelSummary(record);
      recognized = !!summary && summary.panel === "kshop";
    } else if (body.startsWith("[Panel] Routing ")) {
      recognized = !!parsePanelRoute(record);
    } else if (/^\[PanelHost\] opened: kshop rect=[1-9]\d*x[1-9]\d*$/.test(body)) {
      recognized = true;
      opens.push({ lifecycle: record.lifecycle, lineNumber: record.lineNumber });
    } else if (body === "[PanelHost] closed: kshop") {
      recognized = true;
      closed.push({ lifecycle: record.lifecycle, lineNumber: record.lineNumber });
    }
    const relevant = /^\[(?:ShopTask|InventoryTask)\]/.test(body)
      || /^(?:event=authority_flash_call_bound|event=panel_exact_close_completed|event=foreign_panel_close_rejected)/.test(body)
      || /^\[XmlSocket:JSON\] task=(?:shop_response|inventory_response|authority_response_family)\b/.test(body)
      || /^\[Panel\] (?:HandlePanelMessage: .*panel=kshop\b|Routing .*?(?:ShopTask|InventoryTask))/.test(body)
      || /^\[PanelHost\].*(?:kshop|exact close)/i.test(body)
      || /^\[Workbench\]/.test(body);
    if (relevant && !recognized) unknown.push(record);
  });
  if (unknown.length > 0) {
    fail("host_relevant_record_unknown", "host_log",
      "authenticated tails contain a KShop-relevant record outside the exact success set", {
        lines: unknown.map((entry) => entry.lineNumber),
      });
  }
  const expectedHandles = mappings.filter((entry) => entry.domain == null)
    .map((entry) => ({ lifecycle: entry.lifecycle, cmd: entry.cmd }))
    .sort((left, right) => canonicalJson(left).localeCompare(canonicalJson(right)));
  handles.sort((left, right) => canonicalJson(left).localeCompare(canonicalJson(right)));
  if (!deepEqual(handles, expectedHandles)) {
    fail("host_shop_handle_multiset_invalid", "host_log",
      "ShopTask HandleWebRequest records do not exactly cover routed KShop calls");
  }
  [opens, closed].forEach((entries) => {
    if (entries.length !== 2 || entries[0].lifecycle !== "first"
        || entries[1].lifecycle !== "restart") {
      fail("host_panel_lifecycle_multiset_invalid", "host_log",
        "each authenticated lifecycle requires one exact KShop PanelHost open and close");
    }
  });
  return { relevantRecordCount: records.filter((record) => {
    const body = record.body;
    return /^\[(?:ShopTask|InventoryTask|PanelHost)\]/.test(body)
      || /^(?:event=authority_flash_call_bound|event=panel_exact_close_completed)/.test(body)
      || /^\[XmlSocket:JSON\] task=(?:shop_response|inventory_response)\b/.test(body)
      || /^\[Panel\] (?:HandlePanelMessage: .*panel=kshop\b|Routing )/.test(body);
  }).length, shopHandleCount: handles.length, panelHostOpenCount: opens.length,
  panelHostCloseCount: closed.length };
}

function parseAuthorityFlashBinding(record) {
  const prefix = "event=authority_flash_call_bound";
  if (!record.body.startsWith(prefix)) return null;
  const match = /^event=authority_flash_call_bound domain=(shop|inventory) webCallId=([A-Za-z0-9._:-]{1,96}) flashCallId=(\d+) panel=kshop panelInstanceId=([A-Za-z0-9._~-]{1,128}) cmd=([A-Za-z][A-Za-z0-9]*) action=([A-Za-z][A-Za-z0-9]*)$/
    .exec(record.body);
  if (!match || Number(match[3]) < 1) {
    fail("host_flash_binding_invalid", "host_log",
      "authority_flash_call_bound is not the exact closed KShop dispatch receipt", {
        lineNumber: record.lineNumber,
      });
  }
  const allowed = match[1] === "inventory" ? INVENTORY_FLASH_ACTIONS : SHOP_FLASH_ACTIONS;
  if (!allowed.has(match[6])) {
    fail("host_flash_binding_invalid", "host_log",
      "authority_flash_call_bound action is outside the KShop allowlist", {
        lineNumber: record.lineNumber,
        action: match[6],
      });
  }
  return { domain: match[1], webCallId: match[2], flashCallId: Number(match[3]),
    panel: "kshop", panelInstanceId: match[4], cmd: match[5], action: match[6] };
}

function parsePanelExactCloseCompleted(record) {
  if (!record.body.startsWith("event=panel_exact_close_completed")) return null;
  const match = /^event=panel_exact_close_completed panel=kshop panelInstanceId=([A-Za-z0-9._~-]{1,128})$/
    .exec(record.body);
  if (!match) {
    fail("host_exact_close_receipt_invalid", "host_log",
      "exact-close completion is not one closed KShop owner receipt", {
        lineNumber: record.lineNumber,
      });
  }
  return { panel: "kshop", panelInstanceId: match[1] };
}

function assertExactCloseReceipts(records, closes) {
  const receipts = records.map((record) => ({ record,
    receipt: parsePanelExactCloseCompleted(record) })).filter((entry) => entry.receipt);
  if (receipts.length !== closes.length) {
    fail("host_exact_close_receipt_multiset_invalid", "host_log",
      "two owner closes require exactly two production completion receipts", {
        expected: closes.length, actual: receipts.length,
      });
  }
  return closes.map((close, index) => {
    const lifecycle = index === 0 ? "first" : "restart";
    const panelEntries = records.map((record) => ({ record, summary: parsePanelSummary(record) }))
      .filter((entry) => entry.record.lifecycle === lifecycle
        && panelSummaryMatchesRequest(entry.summary, close.message));
    const panel = requireOne(panelEntries, "host_exact_close_panel_count_invalid",
      "exact owner close lacks one authenticated Host request summary");
    const matchingReceipts = receipts.filter((entry) => entry.record.lifecycle === lifecycle
      && entry.receipt.panelInstanceId === close.message.panelInstanceId);
    const receipt = requireOne(matchingReceipts, "host_exact_close_receipt_count_invalid",
      "owner close lacks one same-instance production completion receipt");
    const closed = records.filter((record) => record.lifecycle === lifecycle
      && record.lineNumber > panel.record.lineNumber
      && record.lineNumber < receipt.record.lineNumber
      && record.body === "[PanelHost] closed: kshop");
    if (closed.length !== 1 || receipt.record.lineNumber <= panel.record.lineNumber) {
      fail("host_exact_close_order_invalid", "host_log",
        "completion receipt must follow one exact PanelHost close in the same owner lifecycle", {
          lifecycle, panelInstanceId: close.message.panelInstanceId,
        });
    }
    return { lifecycle, panelInstanceId: close.message.panelInstanceId,
      panelLine: panel.record.lineNumber, panelHostClosedLine: closed[0].lineNumber,
      completionLine: receipt.record.lineNumber,
      panelObservedAt: panel.record.hostObservedAt,
      panelHostClosedAt: closed[0].hostObservedAt,
      completionObservedAt: receipt.record.hostObservedAt };
  });
}

function authorityReference(tokenValue) {
  const match = /^sha256:([a-f0-9]{64})$/.exec(String(tokenValue || ""));
  return match ? "sha256_" + match[1].slice(0, 24) : null;
}

function messageAuthorityProjection(message) {
  const refs = new Map(AUTHORITY_KEYS.map((key) => [key, new Set()]));
  let fieldCount = 0;
  function visit(value) {
    if (Array.isArray(value)) return value.forEach(visit);
    if (!isPlainObject(value)) return;
    Object.keys(value).forEach((key) => {
      if (refs.has(key)) {
        fieldCount += 1;
        const reference = authorityReference(value[key]);
        if (!reference) fail("authority_value_not_redacted", "host_log",
          "public authority field is not one token reference", { key });
        refs.get(key).add(reference);
        return;
      }
      if (/(?:token|lease|transaction|secret|capability)/i.test(key)) {
        fail("unknown_authority_field", "host_log",
          "public evidence contains an unknown authority-bearing field", { key });
      }
      visit(value[key]);
    });
  }
  visit(message);
  const projection = Object.create(null);
  if (fieldCount === 0) return projection;
  projection.authorityFieldCount = String(fieldCount);
  AUTHORITY_KEYS.forEach((key) => {
    const values = Array.from(refs.get(key)).sort();
    if (values.length === 1) projection[key + "Ref"] = values[0];
    else if (values.length > 1) projection[key + "Refs"] = values.slice(0, 4).join(",");
    if (values.length > 4) projection[key + "RefCount"] = String(values.length);
  });
  return projection;
}

function assertMessageAuthorityRefs(message, authority, _keys, code) {
  const expected = messageAuthorityProjection(message);
  if (!deepEqual(authority || {}, expected)) {
    fail(code, "host_log", "Host authority references are not the exact Web-envelope projection", {
      expected, actual: authority || {},
    });
  }
}

function panelSummaryMatchesRequest(summary, request) {
  const expectedDomain = request.domain === "inventory" ? "inventory" : "other";
  const expectedCallId = request.cmd === "close" ? "other" : String(request.callId);
  return !!summary && summary.panel === "kshop" && summary.domain === expectedDomain
    && summary.cmd === request.cmd && summary.callId === expectedCallId;
}

function exactKeys(value, keys) {
  return isPlainObject(value)
    && deepEqual(Object.keys(value).sort(), keys.slice().sort());
}

function normalizedFlashRequest(request, flashCallId, action) {
  const raw = restoreWireMessage(request.event, request.message,
    "KShop request " + request.message.callId);
  const common = ["type", "panel", "panelInstanceId", "cmd", "callId"];
  let normalized;
  if (raw.domain === "inventory") {
    if (!exactKeys(raw, common.concat(["domain", "payload"]))
        || !exactKeys(raw.payload, ["v", "requests"]) || raw.payload.v !== 1
        || !Array.isArray(raw.payload.requests) || raw.payload.requests.length < 1
        || raw.payload.requests.length > 2
        || raw.payload.requests.some((entry) => !exactKeys(entry,
          ["containerId", "offset", "limit", "filterKey"]))) {
      fail("flash_normalized_request_invalid", "payload_causality",
        "inventory snapshot request differs from the exact Host normalization input");
    }
    normalized = { v: 1, requests: raw.payload.requests.map((entry) => ({
      containerId: entry.containerId, offset: entry.offset,
      limit: entry.limit, filterKey: entry.filterKey,
    })) };
  } else if (raw.cmd === "bulkQuery") {
    if (!exactKeys(raw, common)) fail("flash_normalized_request_invalid", "payload_causality",
      "bulkQuery carries a field outside the exact Host request contract");
    normalized = {};
  } else if (raw.cmd === "saveCart") {
    if (!exactKeys(raw, common.concat(["cart"])) || !Array.isArray(raw.cart)
        || raw.cart.some((entry) => !exactKeys(entry, ["idx", "qty"]))) {
      fail("flash_normalized_request_invalid", "payload_causality",
        "saveCart carries a field outside the exact Host request contract");
    }
    normalized = { cart: raw.cart };
  } else if (raw.cmd === "checkoutPreview") {
    if (!exactKeys(raw, common.concat(["v", "cart"])) || raw.v !== 1
        || !Array.isArray(raw.cart)
        || raw.cart.some((entry) => !exactKeys(entry, ["idx", "qty"]))) {
      fail("flash_normalized_request_invalid", "payload_causality",
        "checkoutPreview carries a field outside the exact Host request contract");
    }
    normalized = { v: 1, cart: raw.cart };
  } else if (raw.cmd === "checkoutCommit") {
    if (!exactKeys(raw, common.concat(["v", "expectedCheckoutToken"])) || raw.v !== 1
        || !/^[A-Za-z0-9._-]{1,160}$/.test(raw.expectedCheckoutToken)) {
      fail("flash_normalized_request_invalid", "payload_causality",
        "checkoutCommit carries a field outside the exact Host request contract");
    }
    normalized = { v: 1, expectedCheckoutToken: raw.expectedCheckoutToken };
  } else {
    fail("flash_normalized_request_invalid", "payload_causality",
      "journey contains a command outside the normalized KShop request set", { cmd: raw.cmd });
  }
  return Object.assign({ task: "cmd", action, callId: flashCallId }, normalized);
}

function socketPayloadExpectation(webResponse, flashCallId, action, isInventory) {
  const rawWeb = restoreWireMessage(webResponse.event, webResponse.message,
    "KShop response " + webResponse.message.callId);
  const business = Object.assign({}, rawWeb);
  ["type", "domain", "panel", "panelInstanceId", "cmd", "callId"]
    .forEach((key) => { delete business[key]; });
  const raw = Object.assign({ task: isInventory ? "inventory_response" : "shop_response",
    callId: flashCallId }, business);
  if (!isInventory && ["shopBulkQuery", "shopCheckoutCommit"].includes(action)) {
    const purchasedView = raw.purchased;
    if (!Array.isArray(purchasedView) || purchasedView.length !== 0) {
      fail("socket_payload_projection_not_exact", "payload_causality",
        "A3 exact-length journey requires an empty legacy purchased projection");
    }
    raw.purchased = [];
    raw.purchasedView = purchasedView;
  }
  return { mode: "exact", characters: JSON.stringify(raw).length };
}

function assertHostMapping(request, records, webResponse) {
  const panelEntries = records.map((record) => ({
    record,
    summary: parsePanelSummary(record),
  })).filter((entry) => panelSummaryMatchesRequest(entry.summary, request.message));
  if (panelEntries.length !== 1) {
    fail("host_panel_request_count_invalid", "host_log",
      "exact Web request is not present once in host log", {
        count: panelEntries.length,
        callId: request.message.callId,
        cmd: request.message.cmd,
        domain: request.message.domain || null,
      });
  }
  const panel = panelEntries[0];
  if (panel.summary.payloadLength !== request.event.wirePayloadLength) {
    fail("host_panel_payload_length_mismatch", "payload_causality",
      "Host panel summary length differs from the observed pre-redaction Web request", {
        callId: request.message.callId,
      });
  }
  assertMessageAuthorityRefs(request.message, panel.summary.authority,
    ["expectedCheckoutToken", "expectedPurchasedToken"], "host_panel_authority_ref_mismatch");
  const isInventory = request.message.domain === "inventory";
  const expectedDomain = isInventory ? "inventory" : "shop";
  const action = isInventory
    ? (request.message.cmd === "tooltip" ? "inventoryTooltip" : "inventorySnapshot")
    : SHOP_ACTIONS[request.message.cmd];
  if (!action) fail("host_action_unknown", "host_log", "mapped Web command lacks an exact Flash action", {
    cmd: request.message.cmd, domain: request.message.domain || null,
  });
  const bindings = records.map((record) => ({ record,
    binding: parseAuthorityFlashBinding(record) }))
    .filter((entry) => entry.binding && entry.record.lifecycle === panel.record.lifecycle
      && entry.record.lineNumber > panel.record.lineNumber
      && entry.binding.domain === expectedDomain
      && entry.binding.webCallId === request.message.callId
      && entry.binding.panelInstanceId === request.message.panelInstanceId
      && entry.binding.cmd === request.message.cmd
      && entry.binding.action === action);
  if (bindings.length !== 1) {
    fail("host_flash_binding_count_invalid", "host_log",
      "Web callId does not have exactly one explicit authority_flash_call_bound receipt", {
        count: bindings.length, webCallId: request.message.callId,
        panelInstanceId: request.message.panelInstanceId, cmd: request.message.cmd,
      });
  }
  const binding = bindings[0];
  const routeEntries = records.map((record) => ({ record, route: parsePanelRoute(record) }))
    .filter((entry) => entry.route && entry.record.lineNumber > panel.record.lineNumber
      && entry.record.lineNumber < binding.record.lineNumber
      && entry.record.lifecycle === panel.record.lifecycle
      && entry.route.domain === (isInventory ? "inventory" : "shop")
      && entry.route.cmd === request.message.cmd);
  if (routeEntries.length !== 1) {
    fail("host_route_count_invalid", "host_log",
      "exact Host route is missing or duplicated", {
        count: routeEntries.length,
        cmd: request.message.cmd,
        domain: isInventory ? "inventory" : "shop",
      });
  }
  const route = routeEntries[0].record;
  let handleLine = null;
  if (!isInventory) {
    const handles = records.filter((record) => record.lifecycle === panel.record.lifecycle
      && record.lineNumber > route.lineNumber && record.lineNumber < binding.record.lineNumber
      && record.body === "[ShopTask] HandleWebRequest: cmd=" + request.message.cmd);
    const handle = requireOne(handles, "host_shop_handle_count_invalid",
      "Shop route lacks one exact HandleWebRequest consumer record");
    handleLine = handle.lineNumber;
  }
  const component = isInventory ? "InventoryTask" : "ShopTask";
  const sends = records.map((record) => ({ record, message: parseFlashSend(record, component) }))
    .filter((entry) => entry.message && entry.record.lineNumber > binding.record.lineNumber
      && entry.record.lifecycle === binding.record.lifecycle && entry.message.action === action
      && entry.message.callId === binding.binding.flashCallId);
  if (sends.length < 1) fail("host_flash_send_missing", "host_log", "Host→Flash send is missing");
  if (sends.length !== 1) fail("host_flash_send_count_invalid", "host_log",
    "one Web request interval contains multiple matching Host→Flash sends");
  const send = sends[0];
  const expectedFlash = normalizedFlashRequest(request, binding.binding.flashCallId, action);
  const expectedFlashLength = JSON.stringify(expectedFlash).length;
  if (send.message.payloadLength !== expectedFlashLength) {
    fail("host_flash_payload_length_mismatch", "payload_causality",
      "Host Flash summary length differs from the exact normalized request", {
        callId: request.message.callId, expected: expectedFlashLength,
        actual: send.message.payloadLength,
      });
  }
  if (request.message.expectedCheckoutToken) {
    const expectedRef = authorityReference(request.message.expectedCheckoutToken);
    if (!expectedRef || send.message.authority.expectedCheckoutTokenRef !== expectedRef) {
      fail("host_flash_authority_ref_mismatch", "host_log",
        "checkout authority reference is detached from the redacted Web request");
    }
  }
  const responseTask = isInventory ? "inventory_response" : "shop_response";
  const socketResponses = records.map((record) => ({ record, response: parseSocketResponse(record) }))
    .filter((entry) => entry.response && entry.record.lineNumber > send.record.lineNumber
       && entry.record.lifecycle === send.record.lifecycle && entry.response.task === responseTask
       && entry.response.callId === binding.binding.flashCallId
       && entry.response.cmd === action);
  if (socketResponses.length !== 1
      || socketResponses[0].response.callId !== binding.binding.flashCallId
      || socketResponses[0].response.success !== "true") {
    fail("host_flash_roundtrip_invalid", "host_log",
      "Host send is not followed by exactly one same-domain/fid/action Flash response", {
        expectedFid: send.message.callId,
        observed: socketResponses.map((entry) => entry.response.callId),
        domain: isInventory ? "inventory" : "shop",
      });
  }
  if (webResponse && webResponse.message) {
    assertMessageAuthorityRefs(webResponse.message, socketResponses[0].response.authority,
      ["checkoutToken", "purchasedToken"], "host_socket_authority_ref_mismatch");
  }
  const socketExpectation = socketPayloadExpectation(webResponse,
    binding.binding.flashCallId, action, isInventory);
  const observedSocketLength = socketResponses[0].response.payloadLength;
  if (observedSocketLength > 8 * 1024 * 1024
      || socketExpectation.mode !== "exact"
      || observedSocketLength !== socketExpectation.characters) {
    fail("host_socket_payload_length_mismatch", "payload_causality",
        "Host socket summary length differs from the exact formatter character count", {
        callId: request.message.callId, expectation: socketExpectation,
        actual: observedSocketLength,
      });
  }
  if (!isInventory) {
    const nextShopResponse = records.find((record) => record.lifecycle === send.record.lifecycle
      && record.lineNumber > socketResponses[0].record.lineNumber
      && (() => { const parsed = parseSocketResponse(record);
        return parsed && parsed.task === "shop_response"; })());
    const receipt = records.filter((record) => record.lineNumber > socketResponses[0].record.lineNumber
      && record.lifecycle === send.record.lifecycle
      && (!nextShopResponse || record.lineNumber < nextShopResponse.lineNumber)
      && record.body === "[ShopTask] <- Flash response received");
    if (receipt.length !== 1) {
      fail("host_shop_response_receipt_invalid", "host_log", "ShopTask did not consume the exact Flash response once");
    }
  }
  return {
    webSequence: request.event.sequence,
    webCallId: request.message.callId,
    flashCallId: binding.binding.flashCallId,
    panelInstanceId: request.message.panelInstanceId,
    cmd: request.message.cmd,
    domain: isInventory ? "inventory" : null,
    panelLine: panel.record.lineNumber,
    routeLine: route.lineNumber,
    handleLine,
    bindingLine: binding.record.lineNumber,
    flashLine: send.record.lineNumber,
    flashResponseLine: socketResponses[0].record.lineNumber,
    flashSourceLine: send.record.sourceLineNumber,
    flashResponseSourceLine: socketResponses[0].record.sourceLineNumber,
    flashResponseObservedAt: socketResponses[0].record.hostObservedAt,
    flashResponseHostEpochMs: socketResponses[0].record.hostEpochMs,
    payloadCausality: { webRequestCharacters: request.event.wirePayloadLength,
      normalizedFlashCharacters: expectedFlashLength,
      socketResponseCharacters: observedSocketLength,
      socketExpectationMode: socketExpectation.mode,
      sanitizedWebResponseCharacters: webResponse.event.wirePayloadLength },
    lifecycle: send.record.lifecycle,
  };
}

function exactPersistedBytes(value) {
  return Buffer.from(JSON.stringify(value, null, 2) + "\n", "utf8");
}

function verifyPersistedArtifact(runDir, relativePath, expectedBytes, code) {
  const normalized = String(relativePath || "").replace(/\\/g, "/");
  const filePath = path.resolve(runDir, normalized.replace(/\//g, path.sep));
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (error) { fail(code, "control", error.message, { relativePath: normalized }); }
  if (!pathInside(runDir, filePath) || !stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || stat.size !== expectedBytes.length) {
    fail(code, "control", "persisted control artifact is not one exact owned regular file", {
      relativePath: normalized,
    });
  }
  const actual = fs.readFileSync(filePath);
  if (!actual.equals(expectedBytes)) {
    fail(code, "control", "persisted control artifact differs byte-for-byte from the bundle", {
      relativePath: normalized,
    });
  }
  return actual;
}

function verifyExactDirectoryEntries(runDir, relativeDirectory, expectedNames, code) {
  const directory = path.resolve(runDir, relativeDirectory.replace(/\//g, path.sep));
  let stat;
  let real;
  try { stat = fs.lstatSync(directory); real = fs.realpathSync.native(directory); }
  catch (error) { fail(code, "control", error.message, { relativeDirectory }); }
  if (!pathInside(runDir, directory) || !stat.isDirectory() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== directory.toLowerCase()) {
    fail(code, "control", "control evidence directory is not one exact owned directory", {
      relativeDirectory,
    });
  }
  const actual = fs.readdirSync(directory).sort();
  const expected = expectedNames.slice().sort();
  if (!deepEqual(actual, expected)) {
    fail(code, "control", "persisted control directory has an extra, duplicate, or omission", {
      relativeDirectory, actual, expected,
    });
  }
}

function verifyControl(bundle, events, mappings, webRequests) {
  const requests = Array.isArray(bundle.controlRequests) ? bundle.controlRequests : [];
  const acks = Array.isArray(bundle.controlAcks) ? bundle.controlAcks : [];
  const providerReceipts = Array.isArray(bundle.controlProviderReceipts)
    ? bundle.controlProviderReceipts : [];
  const captures = Array.isArray(bundle.controlCaptures) ? bundle.controlCaptures : [];
  if (requests.length !== REQUIRED_CONTROL_STEPS.length || acks.length !== requests.length
      || providerReceipts.length !== requests.length || captures.length !== 2
      || !deepEqual(requests.map((entry) => entry && entry.step), REQUIRED_CONTROL_STEPS)
      || !deepEqual(acks.map((entry) => entry && entry.requestId),
        requests.map((entry) => entry && entry.requestId))
      || !deepEqual(providerReceipts.map((entry) => entry && entry.requestId),
        requests.map((entry) => entry && entry.requestId))) {
    fail("control_envelope_count_invalid", "control", "control evidence must contain only the exact required steps");
  }
  if (new Set(requests.map((entry) => entry.requestId)).size !== requests.length
      || new Set(acks.map((entry) => entry.requestId)).size !== acks.length) {
    fail("control_id_reused", "control", "control request/ack ids must be unique");
  }
  const byStep = new Map();
  const runDir = path.resolve(bundle.root, bundle.runDir || "");
  verifyExactDirectoryEntries(runDir, "control",
    ["requests", "acks", "provider-receipts", "captures", "current-request.json"],
    "control_root_directory_invalid");
  verifyExactDirectoryEntries(runDir, "control/requests",
    requests.map((entry) => entry.requestId + ".json"), "control_request_directory_invalid");
  verifyExactDirectoryEntries(runDir, "control/acks",
    requests.map((entry) => entry.requestId + ".json"), "control_ack_directory_invalid");
  verifyExactDirectoryEntries(runDir, "control/provider-receipts",
    requests.map((entry) => entry.requestId + ".json"), "provider_receipt_directory_invalid");
  verifyExactDirectoryEntries(runDir, "control/captures",
    captures.map((entry) => path.posix.basename(String(entry.relativePath || ""))),
    "provider_capture_directory_invalid");
  REQUIRED_CONTROL_STEPS.forEach((step) => {
    const request = requireOne(requests.filter((entry) => entry.step === step),
      "control_step_request_invalid", "required control step request is missing or duplicated");
    const ack = requireOne(acks.filter((entry) => entry.requestId === request.requestId),
      "control_step_ack_invalid", "required control step acknowledgement is missing or duplicated");
    validateRequest(request);
    validateAck(ack, request);
    verifyPersistedArtifact(runDir, "control/requests/" + request.requestId + ".json",
      exactPersistedBytes(request), "control_request_bytes_mismatch");
    verifyPersistedArtifact(runDir, "control/acks/" + request.requestId + ".json",
      exactPersistedBytes(ack), "control_ack_bytes_mismatch");
    if (request.schema !== CONTROL_SCHEMA || ack.schema !== ACK_SCHEMA
        || !Array.isArray(request.allowedTransports)
        || !request.allowedTransports.includes(ack.transport)
        || typeof request.requiresCommitAuthorization !== "boolean"
        || typeof request.requiresCaptureSha256 !== "boolean"
        || !Number.isFinite(Date.parse(request.issuedAt))
        || !Number.isFinite(Date.parse(request.expiresAt))
        || !Number.isFinite(Date.parse(ack.completedAt))
        || Date.parse(ack.completedAt) < Date.parse(request.issuedAt)
        || Date.parse(ack.completedAt) > Date.parse(request.expiresAt)) {
      fail("control_envelope_invalid", "control", "control request/ack envelope is invalid", { step });
    }
    if (ack.result !== "completed") {
      fail("control_step_not_completed", "control", "operator step did not complete", { step, result: ack.result });
    }
    const providerReceipt = verifyProviderReceiptFile(bundle.root, runDir,
      ack, request, bundle.evidenceMode);
    const embeddedProvider = requireOne(providerReceipts.filter((entry) => entry
      && entry.requestId === request.requestId), "provider_receipt_bundle_invalid",
    "bundle provider receipt is missing or duplicated");
    if (!deepEqual(providerReceipt, embeddedProvider)) {
      fail("provider_receipt_bundle_mismatch", "control",
        "persisted provider receipt differs byte-for-byte from the bundle array", { step });
    }
    verifyPersistedArtifact(runDir, ack.providerReceiptRef.relativePath,
      exactPersistedBytes(embeddedProvider), "provider_receipt_bundle_bytes_mismatch");
    const captureResult = verifyAckCaptureFile(bundle.root, runDir, ack, request, providerReceipt);
    if (request.requiresCaptureSha256) {
      const embeddedCapture = requireOne(captures.filter((entry) => entry
        && entry.relativePath === providerReceipt.capture.relativePath),
      "provider_capture_bundle_invalid", "bundle provider capture is missing or duplicated");
      if (!deepEqual(embeddedCapture, providerReceipt.capture)) {
        fail("provider_capture_bundle_mismatch", "control",
          "provider and bundle capture references differ", { step });
      }
      verifyPersistedArtifact(runDir, embeddedCapture.relativePath,
        fs.readFileSync(captureResult.path), "provider_capture_bundle_bytes_mismatch");
    }
    byStep.set(step, { request, ack, providerReceipt, capture: captureResult
      ? captureResult.capture : null });
  });
  verifyPersistedArtifact(runDir, "control/current-request.json",
    exactPersistedBytes(requests.at(-1)), "control_current_request_bytes_mismatch");
  const providerOperationIds = Array.from(byStep.values())
    .map((entry) => entry.providerReceipt.operationId);
  if (new Set(providerOperationIds).size !== REQUIRED_CONTROL_STEPS.length) {
    fail("provider_operation_id_reused", "control",
      "every control step requires one independent provider operation id");
  }
  const capability = bundle.authorization && bundle.authorization.launcherAgentRuntime;
  const selected = bundle.authorization && bundle.authorization.selectedTransport;
  SharedControl.verifyCapabilityDecision({
    capability,
    trustedSources: ["authenticated_process_contract"],
    selectedTransport: selected,
    preferredTransport: "launcher_agent_runtime",
    fallbackTransport: "codex_computer_use",
    fallbackAllowed: !!(bundle.authorization && bundle.authorization.codexFallbackAllowed),
  });
  const startArtifact = capability.artifact;
  const firstIdentity = bundle.runtime && bundle.runtime.first && bundle.runtime.first.identity;
  const processPayload = Object.assign({}, startArtifact);
  delete processPayload.artifactSha256;
  if (startArtifact.schema !== "workbench-live-e2e.launcher-process-contract.v1"
      || startArtifact.agentRuntimeAdmission !== false
      || startArtifact.legacyHttpAutomationArg !== true
      || startArtifact.projectRootArgumentExact !== true
      || startArtifact.trustedSource !== "actual_process_command_line+pid_bound_credential"
      || !firstIdentity || startArtifact.pid !== firstIdentity.pid
      || path.resolve(startArtifact.processPath || "").toLowerCase()
        !== path.resolve(firstIdentity.processPath || "").toLowerCase()
      || path.resolve(startArtifact.projectRoot || "").toLowerCase()
        !== path.resolve(bundle.root).toLowerCase()
      || startArtifact.artifactSha256 !== sha256Text(canonicalJson(processPayload))) {
    fail("capability_start_contract_invalid", "control",
      "capability decision is not bound to actual authenticated process argv");
  }
  if (capability.preferredTransport !== "launcher_agent_runtime"
      || !Array.isArray(capability.requiredCapabilities)
      || !capability.requiredCapabilities.includes("computer.use.kshop")
      || !capability.requiredCapabilities.includes("native.safe_exit")
      || !Array.isArray(capability.observedCapabilities)
      || !deepEqual(capability.observedCapabilities,
        (bundle.runtime.first.sessionEvidence.capabilities || []).slice().sort())
      || (capability.available === false
        && capability.reasonCode !== "authenticated_process_lacks_kshop_computer_use")) {
    fail("capability_contract_invalid", "control",
      "preferred Agent Runtime capability evidence is not an honest current-process decision");
  }
  const authorization = SharedControl.verifyOneShotAuthorization({
    decision: bundle.authorization.commitDecision,
    decisionSha256: bundle.authorization.commitDecisionSha256,
    decisionSchema: "workbench-live-e2e.authorization-decision.v1",
    trustedSources: ["cli_explicit_flag"],
    requests,
    acks,
    expectedStep: "commit_checkout",
  });
  const decision = bundle.authorization.commitDecision;
  if (decision.allowedStep !== "commit_checkout" || !decision.scope
      || decision.scope.journey !== "kshop-dynamic-single-item-purchase.v1"
      || decision.scope.runId !== bundle.runId
      || decision.scope.exactRequestId !== authorization.requestId
      || decision.scope.slot !== bundle.slot
      || path.resolve(decision.scope.candidateRoot || "").toLowerCase()
        !== path.resolve(bundle.candidateRoot || "").toLowerCase()
      || !deepEqual(decision.scope.selection, bundle.selection)
      || !deepEqual(decision.scope.cart, bundle.selection.cart)
      || Number(decision.scope.total) !== bundle.selection.total
      || !Number.isFinite(Date.parse(decision.expiresAt))
      || Date.parse(decision.expiresAt) <= Date.parse(decision.issuedAt)) {
    fail("purchase_authorization_scope_invalid", "control",
      "one-shot authorization scope does not match the exact KShop mutation");
  }
  REQUIRED_CONTROL_STEPS.forEach((step) => {
    if (byStep.get(step).ack.transport !== selected) {
      fail("control_transport_mismatch", "control", "operator step used the wrong transport", { step });
    }
  });
  if (!bundle.authorization || bundle.authorization.isolatedPurchaseAllowed !== true
      || byStep.get("commit_checkout").request.requiresCommitAuthorization !== true
      || authorization.requestId !== byStep.get("commit_checkout").request.requestId) {
    fail("purchase_not_authorized", "control", "isolated purchase authorization is absent");
  }
  const commitPair = byStep.get("commit_checkout");
  if (Date.parse(commitPair.request.issuedAt) < Date.parse(decision.issuedAt)
      || Date.parse(commitPair.request.issuedAt) > Date.parse(decision.expiresAt)
      || Date.parse(commitPair.ack.completedAt) > Date.parse(decision.expiresAt)) {
    fail("purchase_authorization_expired", "control",
      "one-shot purchase authorization did not cover the exact request/ack window");
  }
  const bindings = Array.isArray(bundle.controlBindings) ? bundle.controlBindings : [];
  if (bindings.length !== requests.length || new Set(bindings.map((entry) => entry.requestId)).size
      !== requests.length) {
    fail("control_binding_set_invalid", "control",
      "every acknowledgement needs one exact action/browser binding");
  }
  const orderedRequests = requests.slice().sort((left, right) =>
    left.domainIntent.browserSequenceStart - right.domainIntent.browserSequenceStart);
  const providerDomRefs = new Set();
  orderedRequests.forEach((request, index) => {
    const ack = acks.find((entry) => entry.requestId === request.requestId);
    const binding = requireOne(bindings.filter((entry) => entry.requestId === request.requestId),
      "control_binding_invalid", "control binding is missing or duplicated");
    const nextStart = index + 1 < orderedRequests.length
      ? orderedRequests[index + 1].domainIntent.browserSequenceStart : bundle.transcript.eventCount + 1;
    if (binding.runId !== bundle.runId || binding.step !== request.step
        || binding.action !== request.domainIntent.action
        || binding.browserSequenceStart !== request.domainIntent.browserSequenceStart
        || !Number.isInteger(binding.browserSequenceEnd)
        || binding.browserSequenceEnd < binding.browserSequenceStart
        || binding.browserSequenceEnd > nextStart
        || binding.requestSha256 !== sha256Text(canonicalJson(request))
        || binding.ackSha256 !== sha256Text(canonicalJson(ack))) {
      fail("control_binding_invalid", "control",
        "ack/action/browser window binding is malformed", { step: request.step });
    }
    const within = events.filter((event) => event.sequence > binding.browserSequenceStart
      && event.sequence <= binding.browserSequenceEnd);
    const mapped = mappings.filter((entry) => entry.webSequence > binding.browserSequenceStart
      && entry.webSequence <= binding.browserSequenceEnd);
    const actualCommands = new Set(mapped.map((entry) => entry.cmd));
    request.domainIntent.expectedWebCommands.forEach((cmd) => {
      if (cmd === "close") {
        const closes = webRequests.filter((entry) => entry.message.cmd === "close"
          && entry.event.sequence > binding.browserSequenceStart
          && entry.event.sequence <= binding.browserSequenceEnd);
        if (closes.length !== 1) fail("control_web_close_binding_missing", "control",
          "close action lacks one exact Host-bound Web close request", { step: request.step,
            count: closes.length });
      } else if (!actualCommands.has(cmd)) fail("control_web_binding_missing", "control",
        "control action lacks its expected Web callId→Flash fid mapping", { step: request.step, cmd });
    });
    const pair = byStep.get(request.step);
    if (DOM_CONTROL_STEPS.has(request.step)) {
      const trusted = within.filter((event) => event.kind === "dom_input" && event.isTrusted === true);
      const observed = requireOne(trusted, "control_browser_input_binding_missing",
        "browser action window lacks one exact trusted input event");
      const expectedObservation = providerObservationFromEvent(bundle.transcript.observerId, observed);
      const referenceKey = expectedObservation.eventRef.observerId + ":"
        + expectedObservation.eventRef.sequence + ":" + expectedObservation.eventRef.eventSha256;
      if (!deepEqual(pair.providerReceipt.inputObservation, expectedObservation)
          || observed.observerId !== bundle.transcript.observerId
          || providerDomRefs.has(referenceKey)
          || Date.parse(observed.observedAt) < Date.parse(pair.providerReceipt.startedAt)
          || Date.parse(observed.observedAt) > Date.parse(pair.providerReceipt.completedAt)) {
        fail("provider_dom_observation_binding_invalid", "control",
          "request/provider/DOM/capture evidence is not one temporally exact bijection", {
            step: request.step, referenceKey,
          });
      }
      providerDomRefs.add(referenceKey);
    } else if (pair.providerReceipt.inputObservation !== null) {
      fail("provider_native_observation_binding_invalid", "control",
        "native control step claimed a passive DOM input", { step: request.step });
    }
  });
  if (providerDomRefs.size !== DOM_CONTROL_STEPS.size) {
    fail("provider_dom_observation_binding_invalid", "control",
      "provider DOM observation references contain a gap, extra, or reuse");
  }
  const captureDigests = new Set();
  const capturePaths = new Set();
  ["safe_exit", "exit_confirm"].forEach((step) => {
    const pair = byStep.get(step);
    const capture = pair.providerReceipt.capture;
    if (pair.request.requiresCaptureSha256 !== true || !isPlainObject(capture)
        || !SHA256_RE.test(String(capture.sha256 || ""))) {
      fail("safe_exit_capture_missing", "control", "native SAFEEXIT step lacks a capture digest", { step });
    }
    const capturePath = path.resolve(runDir, String(capture.relativePath || "").replace(/\//g, path.sep));
    let stat;
    let real;
    try {
      stat = fs.lstatSync(capturePath);
      real = fs.realpathSync.native(capturePath);
    } catch (error) {
      fail("safe_exit_capture_file_missing", "control", error.message, { step });
    }
    if (!pathInside(runDir, capturePath) || !stat.isFile() || stat.isSymbolicLink()
        || path.resolve(real).toLowerCase() !== capturePath.toLowerCase()
        || stat.size !== capture.bytes || stat.size < 1 || stat.size > 64 * 1024 * 1024) {
      fail("safe_exit_capture_file_invalid", "control", "native capture is not an exact owned regular file", { step });
    }
    const bytes = fs.readFileSync(capturePath);
    const digest = sha256Bytes(bytes);
    if (digest !== capture.sha256 || capture.mediaType !== "image/png") {
      fail("safe_exit_capture_digest_mismatch", "control", "native capture bytes do not match the acknowledgement", { step });
    }
    captureDigests.add(digest);
    capturePaths.add(capturePath.toLowerCase());
  });
  if (captureDigests.size !== 2 || capturePaths.size !== 2) {
    fail("safe_exit_capture_reused", "control", "SAFEEXIT and EXIT_CONFIRM require two distinct captures");
  }
  return { selectedTransport: selected, launcherReachable: capability.available,
    steps: REQUIRED_CONTROL_STEPS.slice(), providerOperationIds, exchanges: byStep,
    persisted: { requests: requests.length, acknowledgements: acks.length,
      providerReceipts: providerReceipts.length, captures: captures.length } };
}

function verifyStableArtifactPhase(phase, slot) {
  if (!isPlainObject(phase) || phase.schema !== "workbench-live-e2e.stable-slot-artifact-set.v1"
      || phase.apiVersion !== "FROZEN-v1" || !Number.isInteger(phase.stableMs) || phase.stableMs < 1
      || !Number.isInteger(phase.samples) || phase.samples < 2
      || !Number.isFinite(Date.parse(phase.observedAt))
      || !SHA256_RE.test(String(phase.evidenceSha256 || ""))) {
    fail("clone_phase_invalid", "persistence", "stable clone phase is malformed");
  }
  const payload = Object.assign({}, phase);
  delete payload.evidenceSha256;
  if (sha256Text(canonicalJson(payload)) !== phase.evidenceSha256) {
    fail("clone_phase_digest_mismatch", "persistence", "stable clone phase digest changed");
  }
  CloneSaveGuard.verifyArtifactSet(phase.set);
  if (phase.set.slot !== slot) fail("clone_phase_slot_mismatch", "persistence",
    "stable clone phase belongs to another slot");
  return phase;
}

function jsonArtifact(set) {
  return set.artifacts.find((entry) => entry.kind === "json") || null;
}

function assertCompleteJsonSolSet(set, label) {
  const jsonCount = set.artifacts.filter((entry) => entry.kind === "json").length;
  const solCount = set.artifacts.filter((entry) => entry.kind === "sol").length;
  if (jsonCount !== 1 || solCount < 1) {
    fail("clone_json_sol_set_incomplete", "persistence",
      label + " must bind one save JSON and the complete non-empty owned SOL set", {
        jsonCount,
        solCount,
      });
  }
}

function verifyCloneLifecycle(bundle) {
  const lifecycle = requireObject(bundle.cloneLifecycle, "clone_lifecycle_missing",
    "full clone lifecycle evidence is missing");
  const preparation = requireObject(lifecycle.preparation, "clone_preparation_missing",
    "clone preparation evidence is missing");
  const preparationPayload = Object.assign({}, preparation);
  delete preparationPayload.preparationSha256;
  if (preparation.schema !== CloneSaveGuard.PREPARATION_SCHEMA
      || preparation.apiVersion !== "FROZEN-v1" || preparation.targetSlot !== bundle.slot
      || preparation.seedSlot !== bundle.seedSlot
      || preparation.root.toLowerCase() !== path.resolve(bundle.root).toLowerCase()
      || !SHA256_RE.test(String(preparation.preparationSha256 || ""))
      || sha256Text(canonicalJson(preparationPayload)) !== preparation.preparationSha256) {
    fail("clone_preparation_invalid", "persistence", "clone preparation is malformed or detached");
  }
  [preparation.seedBegin, preparation.seedAfterPrepare, preparation.targetBefore,
    preparation.targetPrepared].forEach(CloneSaveGuard.verifyArtifactSet);
  CloneSaveGuard.assertArtifactSetInvariant(preparation.seedBegin, preparation.seedAfterPrepare,
    "seed_changed_during_prepare");
  CloneSaveGuard.verifyBackupManifest({ runDir: preparation.runDir,
    backups: preparation.backups, set: preparation.targetBefore });
  const phases = requireObject(lifecycle.phases, "clone_phases_missing",
    "clone phase evidence is missing");
  const baseline = verifyStableArtifactPhase(phases.runtimeBaseline, bundle.slot);
  const afterCommit = verifyStableArtifactPhase(phases.afterCommit, bundle.slot);
  const afterSafeExit = verifyStableArtifactPhase(phases.afterSafeExit, bundle.slot);
  const afterRestart = verifyStableArtifactPhase(phases.afterRestart, bundle.slot);
  assertCompleteJsonSolSet(baseline.set, "runtime baseline");
  assertCompleteJsonSolSet(afterCommit.set, "post-commit phase");
  assertCompleteJsonSolSet(afterSafeExit.set, "SAFEEXIT phase");
  assertCompleteJsonSolSet(afterRestart.set, "restart phase");
  if (baseline.set.setSha256 === afterCommit.set.setSha256) {
    fail("clone_not_mutated", "persistence", "commit did not change the complete target artifact set");
  }
  const safeJson = jsonArtifact(afterSafeExit.set);
  const restartJson = jsonArtifact(afterRestart.set);
  if (!safeJson || !restartJson || safeJson.sha256 !== restartJson.sha256
      || safeJson.bytes !== restartJson.bytes
      || afterSafeExit.set.setSha256 !== afterRestart.set.setSha256
      || canonicalJson(afterSafeExit.set.artifacts) !== canonicalJson(afterRestart.set.artifacts)) {
    fail("restart_disk_readback_mismatch", "persistence",
      "restart target JSON/SOL set differs from exact SAFEEXIT artifacts");
  }
  verifySaveUniverse(lifecycle.collateralBefore);
  verifySaveUniverse(lifecycle.collateralEnd);
  assertSaveUniverseInvariant(lifecycle.collateralBefore, lifecycle.collateralEnd);
  const release = requireObject(lifecycle.release, "clone_release_missing",
    "terminal clone release evidence is missing");
  const releasePayload = Object.assign({}, release);
  delete releasePayload.releaseSha256;
  if (release.schema !== CloneSaveGuard.RELEASE_SCHEMA || release.apiVersion !== "FROZEN-v1"
      || release.backupsVerified !== true || !SHA256_RE.test(String(release.releaseSha256 || ""))
      || sha256Text(canonicalJson(releasePayload)) !== release.releaseSha256) {
    fail("clone_release_invalid", "persistence", "terminal clone release evidence is malformed");
  }
  CloneSaveGuard.verifyArtifactSet(release.seedEnd);
  CloneSaveGuard.verifyArtifactSet(release.targetEnd);
  assertCompleteJsonSolSet(release.targetEnd, "terminal released target");
  CloneSaveGuard.assertArtifactSetInvariant(preparation.seedBegin, release.seedEnd,
    "seed_artifact_set_changed");
  const finalJson = jsonArtifact(release.targetEnd);
  if (!finalJson || finalJson.sha256 !== safeJson.sha256 || finalJson.bytes !== safeJson.bytes
      || release.targetEnd.setSha256 !== afterSafeExit.set.setSha256
      || canonicalJson(release.targetEnd.artifacts) !== canonicalJson(afterSafeExit.set.artifacts)
      || !release.lockRelease || release.lockRelease.lockFileAbsent !== true
      || !release.recoveryClear || release.recoveryClear.recoveryFileAbsent !== true) {
    fail("clone_terminal_state_invalid", "persistence",
      "final JSON/lock/recovery state is not exact after release");
  }
  return { preparationSha256: preparation.preparationSha256,
    seedSetSha256: preparation.seedBegin.setSha256,
    baselineSetSha256: baseline.set.setSha256, afterCommitSetSha256: afterCommit.set.setSha256,
    safeExitSetSha256: afterSafeExit.set.setSha256,
    restartSetSha256: afterRestart.set.setSha256,
    finalSetSha256: release.targetEnd.setSha256, finalJsonSha256: finalJson.sha256,
    collateralSetSha256: lifecycle.collateralEnd.setSha256,
    releaseSha256: release.releaseSha256 };
}

function verifyModuleAdmission(bundle, options) {
  const admission = requireObject(bundle.moduleAdmission, "module_admission_missing",
    "runtime module admission evidence is missing");
  const preSeal = options && options.preSeal === true;
  if (preSeal) {
    RuntimeModuleJournal.verifyExplicitModuleManifest({ root: admission.manifest.root,
      manifest: admission.manifest });
    if (admission.journal !== null) {
      fail("module_admission_preseal_invalid", "module_admission",
        "live semantic verification must execute before the current journal is sealed");
    }
  } else if (options && options.deferModuleJournalRuntime === true) {
    RuntimeModuleJournal.verifyExplicitModuleManifest({ root: admission.manifest.root,
      manifest: admission.manifest });
    if (!isPlainObject(admission.journal)
        || admission.journal.schema !== RuntimeModuleJournal.JOURNAL_SCHEMA
        || admission.journal.admissionStatus !== RuntimeModuleJournal.ADMISSION_STATUS
        || !SHA256_RE.test(String(admission.journal.evidenceSha256 || ""))) {
      fail("module_admission_deferred_invalid", "module_admission",
        "pre-seal audit received a malformed sealed module journal");
    }
  } else {
    RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: admission.manifest.root,
      manifest: admission.manifest, artifact: admission.journal });
  }
  const manifestLocators = admission.manifest.entries.map((entry) => entry.locator).sort();
  const manifestBuiltins = admission.manifest.builtins.map((entry) => entry.name).sort();
  const offline = bundle.evidenceMode === "offline_fixture";
  const expectedLocators = offline ? EXPECTED_AUDIT_MODULE_LOCATORS : EXPECTED_RUNTIME_MODULE_LOCATORS;
  const expectedPhases = offline ? ["domain_loaded", "audit_executed", "terminal"]
    : ["domain_loaded", "clone_prepared", "first_captured", "restart_captured",
      "verification_executed", "terminal"];
  if (path.resolve(admission.manifest.root).toLowerCase() !== CANONICAL_ROOT.toLowerCase()
      || canonicalJson(manifestLocators) !== canonicalJson(expectedLocators)
      || canonicalJson(manifestBuiltins) !== canonicalJson(EXPECTED_MODULE_BUILTINS)
      || !deepEqual(admission.manifest.requiredPhases, expectedPhases)
      || (offline && (!isPlainObject(admission.smoke)
        || admission.smoke.selfTestLoaded !== true || admission.smoke.fixtureLoaded !== true
        || admission.smoke.productionPanelRuntimeExecuted !== true))) {
    fail("module_admission_scope_invalid", "module_admission",
      "module admission does not cover the exact KShop runner/WebSocket closure");
  }
  return { manifestSha256: admission.manifest.manifestSha256,
    journalSha256: preSeal ? null : admission.journal.evidenceSha256,
    admissionStatus: preSeal ? "PRESEAL_VALIDATION_ACTIVE" : admission.journal.admissionStatus };
}

function verifyRuntimeAndPersistence(bundle, records, commitMapping) {
  const runtime = requireObject(bundle.runtime, "runtime_missing", "runtime evidence is missing");
  const first = requireObject(runtime.first, "runtime_first_missing", "first runtime evidence is missing");
  const restart = requireObject(runtime.restart, "runtime_restart_missing", "restart runtime evidence is missing");
  const firstIdentity = requireObject(first.identity, "runtime_identity_missing", "first identity is missing");
  const restartIdentity = requireObject(restart.identity, "runtime_identity_missing", "restart identity is missing");
  if (first.identityVerified !== true || restart.identityVerified !== true
      || firstIdentity.runtimeMode !== "isolated_candidate"
      || restartIdentity.runtimeMode !== "isolated_candidate") {
    fail("runtime_identity_not_verified", "runtime", "both runs must attest an isolated verified identity");
  }
  const candidateRoot = path.resolve(bundle.candidateRoot || "");
  const firstInstallRoot = path.dirname(path.dirname(path.resolve(firstIdentity.processPath || "")));
  const restartInstallRoot = path.dirname(path.dirname(path.resolve(restartIdentity.processPath || "")));
  if (candidateRoot.toLowerCase() !== firstInstallRoot.toLowerCase()
      || candidateRoot.toLowerCase() !== restartInstallRoot.toLowerCase()
      || !SHA256_RE.test(String(firstIdentity.coreSha256 || ""))
      || !SHA256_RE.test(String(firstIdentity.buildIdentity || ""))
      || !SHA256_RE.test(String(firstIdentity.payloadClosure || ""))) {
    fail("runtime_candidate_binding_invalid", "runtime", "runtime process is not bound to the exact candidate identity");
  }
  const beforeClone = requireObject(bundle.candidateBeforeClone,
    "candidate_before_clone_missing", "candidate identity was not resolved before clone mutation");
  const expectedCandidate = { runtimeMode: firstIdentity.runtimeMode,
    processPath: path.resolve(firstIdentity.processPath),
    coreSha256: String(firstIdentity.coreSha256).toUpperCase(),
    buildIdentity: String(firstIdentity.buildIdentity).toUpperCase(),
    payloadClosure: String(firstIdentity.payloadClosure).toUpperCase(),
    installRoot: path.resolve(firstIdentity.installRoot || firstInstallRoot) };
  if (beforeClone.schema !== "workbench-live-e2e.candidate-before-clone.v1"
      || beforeClone.identitySha256 !== sha256Text(canonicalJson(beforeClone.identity))
      || !deepEqual(beforeClone.identity, expectedCandidate)) {
    fail("candidate_before_clone_mismatch", "runtime",
      "runtime identity differs from the exact pre-mutation candidate triple");
  }
  if (!bundle.productionClosure || !Number.isFinite(Date.parse(bundle.productionClosure.capturedAt))
      || !Number.isFinite(Date.parse(beforeClone.resolvedAt))
      || Date.parse(bundle.productionClosure.capturedAt) > Date.parse(beforeClone.resolvedAt)) {
    fail("production_closure_not_pre_mutation", "production_closure",
      "current-tree production closure was not frozen before candidate/clone resolution");
  }
  if (!Number.isInteger(firstIdentity.pid) || !Number.isInteger(restartIdentity.pid)
      || firstIdentity.pid === restartIdentity.pid) {
    fail("restart_pid_invalid", "restart", "restart must use a new authenticated PID");
  }
  const firstCdp = requireObject(first.cdpBinding, "cdp_binding_missing", "first CDP binding is missing");
  const restartCdp = requireObject(restart.cdpBinding, "cdp_binding_missing", "restart CDP binding is missing");
  SharedRuntime.assertRuntimeCdpBinding(firstCdp, firstIdentity, first.trustedCdpExpectations);
  SharedRuntime.assertRuntimeCdpBinding(restartCdp, restartIdentity, restart.trustedCdpExpectations);
  if (firstCdp.port === restartCdp.port) {
    fail("cdp_restart_port_reused", "restart", "restart must allocate a fresh exclusive CDP endpoint");
  }
  const cdpEvents = bundle.transcript.events.filter((event) => event.kind === "cdp_endpoint_bound");
  if (cdpEvents.length !== 2
      || cdpEvents[0].cdpPort !== firstCdp.port || cdpEvents[0].runtimePid !== firstIdentity.pid
      || cdpEvents[1].cdpPort !== restartCdp.port || cdpEvents[1].runtimePid !== restartIdentity.pid
      || cdpEvents.some((event) => event.exclusiveBeforeLaunch !== true
        || event.configurationSource !== "CF7_WEBVIEW2_ARGS")
      || !deepEqual(cdpEvents[0].endpointAttestation, firstCdp.attestation)
      || !deepEqual(cdpEvents[1].endpointAttestation, restartCdp.attestation)
      || cdpEvents[0].pageIdentitySha256 !== firstCdp.pageIdentitySha256
      || cdpEvents[1].pageIdentitySha256 !== restartCdp.pageIdentitySha256
      || cdpEvents[0].pageContentSha256 !== firstCdp.pageContentSha256
      || cdpEvents[1].pageContentSha256 !== restartCdp.pageContentSha256
      || cdpEvents[0].pageContentBytes !== firstCdp.pageContentBytes
      || cdpEvents[1].pageContentBytes !== restartCdp.pageContentBytes) {
    fail("cdp_transcript_binding_invalid", "runtime", "transcript does not attest the two exact CDP bindings");
  }
  ["runtimeMode", "processPath", "coreSha256", "buildIdentity", "payloadClosure"].forEach((field) => {
    if (!firstIdentity[field] || firstIdentity[field] !== restartIdentity[field]) {
      fail("restart_identity_mismatch", "restart", "restart identity differs at " + field);
    }
  });
  if (!first.ready || !restart.ready || !first.ready.expectedAttemptId
      || !restart.ready.expectedAttemptId
      || first.ready.expectedAttemptId === restart.ready.expectedAttemptId) {
    fail("restart_attempt_invalid", "restart", "restart attempt id is missing or reused");
  }
  LauncherObservation.verifySessionEvidenceEnvelope(first.sessionEvidence);
  LauncherObservation.verifySessionEvidenceEnvelope(restart.sessionEvidence);
  [first, restart].forEach((entry) => {
    const contract = entry.processContract;
    const payload = Object.assign({}, contract);
    delete payload.artifactSha256;
    if (!isPlainObject(contract) || contract.pid !== entry.identity.pid
        || contract.agentRuntimeAdmission !== false || contract.legacyHttpAutomationArg !== true
        || contract.artifactSha256 !== sha256Text(canonicalJson(payload))) {
      fail("runtime_process_contract_invalid", "runtime",
        "actual process argv contract is missing or detached from runtime identity");
    }
  });
  LauncherObservation.assertFreshAuthenticatedRestart({ first: firstIdentity, restart: restartIdentity,
    firstAttemptId: first.ready.expectedAttemptId, restartAttemptId: restart.ready.expectedAttemptId,
    firstSession: first.sessionEvidence, restartSession: restart.sessionEvidence });
  const shutdownEvidence = requireObject(restart.shutdownEvidence,
    "authenticated_shutdown_missing", "restart authenticated shutdown evidence is missing");
  const shutdownPayload = Object.assign({}, shutdownEvidence);
  delete shutdownPayload.evidenceSha256;
  if (!exactKeys(shutdownEvidence, ["schema", "requestedAt", "completedAt", "pid",
    "sessionEvidenceSha256", "response", "evidenceSha256"])
      || shutdownEvidence.schema !== "workbench-live-e2e.kshop.authenticated-shutdown.v1"
      || shutdownEvidence.pid !== restartIdentity.pid
      || shutdownEvidence.sessionEvidenceSha256 !== restart.sessionEvidence.sessionEvidenceSha256
      || !Number.isFinite(Date.parse(shutdownEvidence.requestedAt))
      || !Number.isFinite(Date.parse(shutdownEvidence.completedAt))
      || Date.parse(shutdownEvidence.completedAt) < Date.parse(shutdownEvidence.requestedAt)
      || shutdownEvidence.evidenceSha256 !== sha256Text(canonicalJson(shutdownPayload))) {
    fail("authenticated_shutdown_invalid", "runtime",
      "restart shutdown evidence is malformed or detached from the authenticated lifecycle");
  }
  LauncherObservation.assertResponseSucceeded(shutdownEvidence.response,
    "authenticated_shutdown", "agent_control shutdown");
  const production = verifyProductionEvidence(bundle, first, restart, firstIdentity);
  const clone = verifyCloneLifecycle(bundle);
  const firstHost = bundle.hostLog.lifecycles[0];
  const safeEvidence = LauncherObservation.verifyArchiveSaveEvidence({ root: bundle.root,
    slot: bundle.slot, boundary: firstHost.boundary, snapshot: firstHost.terminalSnapshot,
    diskEvidence: bundle.safeExitEvidence.disk, requiredOrder: ["sv1", "sv2", "archive"] });
  const normalizedSafeEvidence = JSON.parse(JSON.stringify(safeEvidence));
  normalizedSafeEvidence.disk.capturedAt = bundle.safeExitEvidence.disk.capturedAt;
  delete normalizedSafeEvidence.evidenceSha256;
  normalizedSafeEvidence.evidenceSha256 = sha256Text(canonicalJson(normalizedSafeEvidence));
  const hostClock = { lifecycle: "first",
    commitResponse: { lineNumber: commitMapping.flashResponseSourceLine, offset: 0 },
    sv1: safeEvidence.positions.sv1,
    sv2: safeEvidence.positions.sv2,
    archive: safeEvidence.positions.archive };
  function positionBefore(left, right) {
    return left.lineNumber < right.lineNumber
      || (left.lineNumber === right.lineNumber && left.offset < right.offset);
  }
  if (!deepEqual(normalizedSafeEvidence, bundle.safeExitEvidence)
      || commitMapping.lifecycle !== "first"
      || !positionBefore(hostClock.commitResponse, hostClock.sv1)
      || !positionBefore(hostClock.sv1, hostClock.sv2)
      || !positionBefore(hostClock.sv2, hostClock.archive)) {
    fail("safe_exit_boundary_invalid", "persistence",
      "SAFEEXIT evidence is detached from the commit and authenticated first lifecycle");
  }
  const residue = requireObject(bundle.residue, "residue_missing", "process/port residue evidence is missing");
  if (!residue.afterSafeExit || residue.afterSafeExit.method !== "SAFEEXIT_UI"
      || !residue.final || residue.final.method !== "agent_control.shutdown") {
    fail("runtime_residue_invalid", "residue", "exit/restart residue contract is incomplete");
  }
  LauncherObservation.assertResidueClean(residue.afterSafeExit);
  LauncherObservation.assertResidueClean(residue.final);
  return {
    firstPid: firstIdentity.pid,
    restartPid: restartIdentity.pid,
    firstAttemptId: first.ready.expectedAttemptId,
    restartAttemptId: restart.ready.expectedAttemptId,
    archiveLine: safeEvidence.archive.lineNumber,
    archivePath: safeEvidence.archive.path,
    hostClock,
    shutdown: { requestedAt: shutdownEvidence.requestedAt,
      completedAt: shutdownEvidence.completedAt,
      evidenceSha256: shutdownEvidence.evidenceSha256 },
    production: { closureSha256: production.closure.closureSha256,
      bindingSha256: production.binding.bindingSha256,
      candidateProducerSha256: production.candidateProducer.evidenceSha256,
      artifactSourceHash: production.candidateProducer.artifactSourceHash,
      firstLoadedSha256: production.first.evidenceSha256,
      restartLoadedSha256: production.restart.evidenceSha256 },
    clone,
  };
}

function recordForSourcePosition(records, lifecycle, position, label) {
  const matches = records.filter((record) => record.lifecycle === lifecycle
    && record.sourceLineNumber === position.lineNumber);
  if (matches.length !== 1) {
    fail("global_timeline_marker_invalid", "timeline",
      "save/archive marker does not resolve to one authenticated Host record", {
        label, lifecycle, lineNumber: position.lineNumber, count: matches.length,
      });
  }
  return matches[0];
}

function verifyGlobalTimeline(bundle, records, mappings, exactCloseReceipts, control, persistence,
  inventorySurfaces) {
  const firstClose = exactCloseReceipts.find((entry) => entry.lifecycle === "first");
  const restartClose = exactCloseReceipts.find((entry) => entry.lifecycle === "restart");
  const commit = mappings.find((entry) => entry.lifecycle === "first"
    && entry.cmd === "checkoutCommit" && entry.domain == null);
  const safe = control.exchanges.get("safe_exit");
  const exit = control.exchanges.get("exit_confirm");
  const firstCloseControl = control.exchanges.get("close_kshop");
  const restartOpenControl = control.exchanges.get("restart_readback_open_kshop");
  const restartCloseControl = control.exchanges.get("restart_readback_close_kshop");
  if (!firstClose || !restartClose || !commit || !safe || !exit || !firstCloseControl
      || !restartOpenControl || !restartCloseControl) {
    fail("global_timeline_evidence_missing", "timeline",
      "global KShop timeline lacks a required Host/control boundary");
  }
  const firstHost = bundle.hostLog.lifecycles[0];
  const positions = bundle.safeExitEvidence.positions;
  const sv1Record = recordForSourcePosition(records, "first", positions.sv1, "sv1");
  const sv2Record = recordForSourcePosition(records, "first", positions.sv2, "sv2");
  const archiveRecord = recordForSourcePosition(records, "first", positions.archive, "archive");
  const positionBefore = (left, right) => left.lineNumber < right.lineNumber
    || (left.lineNumber === right.lineNumber && left.offset < right.offset);
  if (!positionBefore(positions.sv1, positions.sv2)
      || !positionBefore(positions.sv2, positions.archive)
      || positions.archive.lineNumber > firstHost.terminalSnapshot.total) {
    fail("global_timeline_save_order_invalid", "timeline",
      "sv1, sv2, and archive do not form one exact authenticated Host order");
  }
  const restartOpenRecords = records.filter((record) => record.lifecycle === "restart"
    && /^\[PanelHost\] opened: kshop rect=[1-9]\d*x[1-9]\d*$/.test(record.body));
  const restartOpenRecord = requireOne(restartOpenRecords,
    "global_timeline_restart_open_invalid", "restart has no exact PanelHost open boundary");
  const postSurface = inventorySurfaces && inventorySurfaces.find((entry) => entry.label
    === "post-commit inventory");
  const expectedPostCallIds = postSurface ? postSurface.callIds.slice().sort() : [];
  const postReadbacks = postSurface ? mappings.filter((entry) => entry.lifecycle === "first"
    && entry.cmd === "snapshot" && entry.domain === "inventory"
    && postSurface.callIds.includes(entry.webCallId)) : [];
  const actualPostCallIds = postReadbacks.map((entry) => entry.webCallId).sort();
  if (!postSurface || postReadbacks.length !== postSurface.callIds.length
      || !deepEqual(actualPostCallIds, expectedPostCallIds)) {
    fail("global_timeline_post_readback_invalid", "timeline",
      "first lifecycle lacks the exact complete post-commit Inventory pair-set");
  }
  const postReadbackTimes = postReadbacks.map((entry) => entry.flashResponseHostEpochMs);
  const restartSurface = inventorySurfaces && inventorySurfaces.find((entry) => entry.label
    === "restart inventory");
  const restartReadbacks = mappings.filter((entry) => entry.lifecycle === "restart"
    && ((entry.cmd === "bulkQuery" && entry.domain == null)
      || (entry.cmd === "snapshot" && entry.domain === "inventory")));
  const expectedRestartCallIds = restartSurface ? restartSurface.callIds.slice().sort() : [];
  const actualRestartCallIds = restartReadbacks.filter((entry) => entry.domain === "inventory")
    .map((entry) => entry.webCallId).sort();
  if (!restartSurface || restartReadbacks.length !== 1 + restartSurface.callIds.length
      || !deepEqual(actualRestartCallIds, expectedRestartCallIds)) {
    fail("global_timeline_restart_readback_invalid", "timeline",
      "restart timeline lacks the exact bulk plus complete Inventory pair-set");
  }
  const readbackTimes = restartReadbacks.map((entry) => entry.flashResponseHostEpochMs);
  const time = {
    commitResponse: commit.flashResponseHostEpochMs,
    postReadbackFirst: Math.min(...postReadbackTimes),
    postReadbackLast: Math.max(...postReadbackTimes),
    firstCloseRequest: Date.parse(firstCloseControl.request.issuedAt),
    firstCloseProviderStarted: Date.parse(firstCloseControl.providerReceipt.startedAt),
    firstClosePanel: Date.parse(firstClose.panelObservedAt),
    firstPanelHostClosed: Date.parse(firstClose.panelHostClosedAt),
    firstCloseCompleted: Date.parse(firstClose.completionObservedAt),
    firstCloseProviderCompleted: Date.parse(firstCloseControl.providerReceipt.completedAt),
    safeRequest: Date.parse(safe.request.issuedAt),
    safeProviderStarted: Date.parse(safe.providerReceipt.startedAt),
    safeAction: Date.parse(safe.providerReceipt.operationEvents[1].occurredAt),
    sv1: sv1Record.hostEpochMs,
    sv2: sv2Record.hostEpochMs,
    archive: archiveRecord.hostEpochMs,
    safeCapture: Date.parse(safe.providerReceipt.capture.capturedAt),
    safeProviderCompleted: Date.parse(safe.providerReceipt.completedAt),
    exitRequest: Date.parse(exit.request.issuedAt),
    exitProviderStarted: Date.parse(exit.providerReceipt.startedAt),
    exitAction: Date.parse(exit.providerReceipt.operationEvents[1].occurredAt),
    exitCapture: Date.parse(exit.providerReceipt.capture.capturedAt),
    exitProviderCompleted: Date.parse(exit.providerReceipt.completedAt),
    afterSafeExitResidue: Date.parse(bundle.residue.afterSafeExit.observedAt),
    restartOpenRequest: Date.parse(restartOpenControl.request.issuedAt),
    restartOpenProviderStarted: Date.parse(restartOpenControl.providerReceipt.startedAt),
    restartPanelHostOpened: restartOpenRecord.hostEpochMs,
    restartReadbackFirst: Math.min(...readbackTimes),
    restartReadbackLast: Math.max(...readbackTimes),
    restartCloseRequest: Date.parse(restartCloseControl.request.issuedAt),
    restartCloseProviderStarted: Date.parse(restartCloseControl.providerReceipt.startedAt),
    restartClosePanel: Date.parse(restartClose.panelObservedAt),
    restartPanelHostClosed: Date.parse(restartClose.panelHostClosedAt),
    restartCloseCompleted: Date.parse(restartClose.completionObservedAt),
    restartCloseProviderCompleted: Date.parse(restartCloseControl.providerReceipt.completedAt),
    shutdownRequested: Date.parse(bundle.runtime.restart.shutdownEvidence.requestedAt),
    shutdownCompleted: Date.parse(bundle.runtime.restart.shutdownEvidence.completedAt),
    finalResidue: Date.parse(bundle.residue.final.observedAt),
  };
  if (Object.values(time).some((value) => !Number.isFinite(value))) {
    fail("global_timeline_time_invalid", "timeline",
      "global KShop timeline contains a non-finite timestamp");
  }
  const chain = [
    ["commitResponse", "postReadbackFirst"],
    ["postReadbackLast", "firstCloseRequest"],
    ["firstCloseRequest", "firstCloseProviderStarted"],
    ["firstCloseProviderStarted", "firstClosePanel"],
    ["firstClosePanel", "firstPanelHostClosed"],
    ["firstPanelHostClosed", "firstCloseCompleted"],
    ["firstCloseCompleted", "firstCloseProviderCompleted"],
    ["firstCloseProviderCompleted", "safeRequest"],
    ["safeRequest", "safeProviderStarted"],
    ["safeProviderStarted", "safeAction"],
    ["safeAction", "sv1"],
    ["archive", "safeCapture"],
    ["safeCapture", "safeProviderCompleted"],
    ["safeProviderCompleted", "exitRequest"],
    ["exitRequest", "exitProviderStarted"],
    ["exitProviderStarted", "exitAction"],
    ["exitAction", "exitCapture"],
    ["exitCapture", "exitProviderCompleted"],
    ["exitProviderCompleted", "afterSafeExitResidue"],
    ["afterSafeExitResidue", "restartOpenRequest"],
    ["restartOpenRequest", "restartOpenProviderStarted"],
    ["restartOpenProviderStarted", "restartPanelHostOpened"],
    ["restartPanelHostOpened", "restartReadbackFirst"],
    ["restartReadbackLast", "restartCloseRequest"],
    ["restartCloseRequest", "restartCloseProviderStarted"],
    ["restartCloseProviderStarted", "restartClosePanel"],
    ["restartClosePanel", "restartPanelHostClosed"],
    ["restartPanelHostClosed", "restartCloseCompleted"],
    ["restartCloseCompleted", "restartCloseProviderCompleted"],
    ["restartCloseProviderCompleted", "shutdownRequested"],
  ];
  const violation = chain.find(([left, right]) => !(time[left] < time[right]));
  if (violation || !(time.sv1 <= time.sv2 && time.sv2 <= time.archive)
      || !(time.shutdownRequested <= time.shutdownCompleted
        && time.shutdownCompleted < time.finalResidue)
      || safe.ack.completedAt !== safe.providerReceipt.completedAt
      || exit.ack.completedAt !== exit.providerReceipt.completedAt
      || firstCloseControl.ack.completedAt !== firstCloseControl.providerReceipt.completedAt
      || restartOpenControl.ack.completedAt !== restartOpenControl.providerReceipt.completedAt
      || restartCloseControl.ack.completedAt !== restartCloseControl.providerReceipt.completedAt
      || Date.parse(restartOpenControl.ack.completedAt) >= time.restartCloseRequest
      || persistence.hostClock.archive.lineNumber !== positions.archive.lineNumber) {
    fail("global_timeline_order_invalid", "timeline",
      "one trusted timeline does not prove commit, close, SAFEEXIT, save/archive, EXIT_CONFIRM, restart readback/close, supported shutdown, and residue order", {
        violation: violation || null,
      });
  }
  return {
    schema: "workbench-live-e2e.kshop.global-timeline.v2",
    inventory: inventorySurfaces.map((surface) => ({
      phase: surface.label, panelInstanceId: surface.panelInstanceId,
      accessibleCapacity: surface.accessibleCapacity,
      sessionNonceSha256: sha256Text(surface.sessionNonce),
      callIds: surface.callIds.slice(), timeline: JSON.parse(JSON.stringify(surface.timeline)),
    })),
    first: {
      commitResponseAt: new Date(time.commitResponse).toISOString(),
      postCommitReadbackStartedAt: new Date(time.postReadbackFirst).toISOString(),
      postCommitReadbackSettledAt: new Date(time.postReadbackLast).toISOString(),
      closeRequestAt: firstCloseControl.request.issuedAt,
      closeProviderStartedAt: firstCloseControl.providerReceipt.startedAt,
      panelHostClosedAt: firstClose.panelHostClosedAt,
      exactCloseCompletedAt: firstClose.completionObservedAt,
      closeProviderCompletedAt: firstCloseControl.providerReceipt.completedAt,
      safeExitRequestAt: safe.request.issuedAt,
      safeExitProviderStartedAt: safe.providerReceipt.startedAt,
      safeExitActionAt: safe.providerReceipt.operationEvents[1].occurredAt,
      sv1: positions.sv1, sv2: positions.sv2, archive: positions.archive,
      safeExitCaptureAt: safe.providerReceipt.capture.capturedAt,
      safeExitProviderCompletedAt: safe.providerReceipt.completedAt,
      exitConfirmRequestAt: exit.request.issuedAt,
      exitConfirmActionAt: exit.providerReceipt.operationEvents[1].occurredAt,
      exitConfirmCaptureAt: exit.providerReceipt.capture.capturedAt,
      exitConfirmProviderCompletedAt: exit.providerReceipt.completedAt,
      cleanResidueAt: bundle.residue.afterSafeExit.observedAt,
    },
    restart: {
      openRequestAt: restartOpenControl.request.issuedAt,
      panelHostOpenedAt: restartOpenRecord.hostObservedAt,
      readbackSettledAt: new Date(time.restartReadbackLast).toISOString(),
      closeRequestAt: restartCloseControl.request.issuedAt,
      panelHostClosedAt: restartClose.panelHostClosedAt,
      exactCloseCompletedAt: restartClose.completionObservedAt,
      closeProviderCompletedAt: restartCloseControl.providerReceipt.completedAt,
      shutdownRequestedAt: bundle.runtime.restart.shutdownEvidence.requestedAt,
      shutdownCompletedAt: bundle.runtime.restart.shutdownEvidence.completedAt,
      cleanResidueAt: bundle.residue.final.observedAt,
    },
  };
}

function verifyBundle(bundle, options) {
  const settings = options || {};
  const preSeal = settings.preSeal === true;
  requireObject(bundle, "bundle_invalid", "bundle must be an object");
  if (bundle.schema !== TOOL_SCHEMA || !bundle.root || !bundle.slot) {
    fail("bundle_contract_invalid", "bundle", "bundle schema/root/slot is invalid");
  }
  if (!["live_capture", "offline_fixture"].includes(bundle.evidenceMode)) {
    fail("evidence_mode_invalid", "bundle",
      "bundle must distinguish a real live capture from an offline contract fixture");
  }
  const expectedBundleStatus = bundle.evidenceMode === "offline_fixture"
    ? "offline_fixture" : "captured_unverified";
  if (bundle.status !== expectedBundleStatus) {
    fail("bundle_status_invalid", "bundle",
      "bundle status is outside the exact evidence-mode state machine", {
        evidenceMode: bundle.evidenceMode, expected: expectedBundleStatus, actual: bundle.status,
      });
  }
  if (bundle.evidenceMode === "live_capture"
      && path.resolve(bundle.root).toLowerCase() !== CANONICAL_ROOT.toLowerCase()) {
    fail("live_capture_root_invalid", "bundle",
      "live evidence must be captured by the canonical workspace runner");
  }
  if (bundle.evidenceMode === "offline_fixture"
      && (!isPlainObject(bundle.fixture)
        || bundle.fixture.schema !== "workbench-live-e2e.kshop.offline-fixture.v1"
        || bundle.fixture.productionEffects !== false
        || path.resolve(bundle.root).toLowerCase() === CANONICAL_ROOT.toLowerCase())) {
    fail("offline_fixture_provenance_invalid", "bundle",
      "offline verification requires an explicit non-production fixture provenance");
  }
  if (preSeal && (bundle.evidenceMode !== "live_capture"
      || own(bundle, "rawBundleManifest")
      || !bundle.moduleAdmission || bundle.moduleAdmission.journal !== null)) {
    fail("preseal_bundle_state_invalid", "bundle",
      "pre-seal validation accepts only an unsealed live bundle without a raw manifest");
  }
  assertSafeSlot(bundle.slot);
  const rawBundle = preSeal ? null : verifyRawBundleManifest(bundle);
  const moduleAdmission = verifyModuleAdmission(bundle, settings);
  assertNoRawTokens(bundle);
  verifyEventChain(bundle.transcript);
  if (bundle.transcript.schema !== "workbench-live-e2e.kshop.transcript.v2"
      || !/^[A-Za-z0-9._~-]{1,160}$/.test(String(bundle.transcript.observerId || ""))
      || bundle.transcript.events.some((event) => event.observerId !== bundle.transcript.observerId)) {
    fail("transcript_observer_identity_invalid", "transcript",
      "passive transcript and every event must share one exact observer identity");
  }
  const events = bundle.transcript.events;
  const wirePayloadFacts = verifyWirePayloadFacts(events);
  const outbound = outboundMessages(events);
  const inbound = inboundMessages(events);
  const requests = panelRequests(outbound);
  const responses = panelResponses(inbound);
  const opens = inbound.filter((entry) => entry.message.type === "panel_cmd"
    && entry.message.cmd === "open" && entry.message.panel === "kshop"
    && entry.message.panelInstanceId
    && entry.message.initData
    && entry.message.initData.panelInstanceId === entry.message.panelInstanceId);
  if (opens.length !== 2 || new Set(opens.map((entry) => entry.message.panelInstanceId)).size !== 2) {
    fail("kshop_instance_inventory_invalid", "panel", "journey must contain exactly two fresh KShop instances");
  }
  const [firstOpen, secondOpen] = opens;
  const firstId = firstOpen.message.panelInstanceId;
  const secondId = secondOpen.message.panelInstanceId;
  const knownInstances = new Set([firstId, secondId]);
  const shopCommands = new Set(["bulkQuery", "saveCart", "checkoutPreview",
    "checkoutCommit", "checkout", "claim"]);
  requests.forEach((entry) => {
    if (!knownInstances.has(entry.message.panelInstanceId)) {
      fail("foreign_kshop_owner_observed", "panel", "KShop request used an unbound panel owner");
    }
    if (entry.message.cmd === "close") {
      if (own(entry.message, "domain")) fail("close_domain_invalid", "panel", "close must be domain-less");
      return;
    }
    if (shopCommands.has(entry.message.cmd)) {
      if (own(entry.message, "domain")) {
        fail("shop_domain_invalid", "panel", "KShop business request must be domain-less", {
          cmd: entry.message.cmd,
        });
      }
      return;
    }
    if (entry.message.cmd === "tooltip"
        && (!own(entry.message, "domain") || entry.message.domain === "inventory")) return;
    if (entry.message.cmd === "snapshot" && entry.message.domain === "inventory") return;
    fail("unexpected_kshop_request", "panel", "unexpected KShop command/domain was observed", {
      cmd: entry.message.cmd,
      domain: entry.message.domain || null,
    });
  });
  const closeRequests = requests.filter((entry) => entry.message.cmd === "close");
  const closes = [firstId, secondId].map((panelInstanceId) =>
    requireOne(closeRequests.filter((entry) => entry.message.panelInstanceId === panelInstanceId),
      "kshop_close_count_invalid", "each KShop instance must close exactly once"));
  if (!(firstOpen.event.sequence < closes[0].event.sequence
      && closes[0].event.sequence < secondOpen.event.sequence
      && secondOpen.event.sequence < closes[1].event.sequence)) {
    fail("kshop_instance_order_invalid", "panel", "KShop instances are out of order");
  }
  const trustedCloseInputs = assertTrustedCloseInputs(events, [firstOpen, secondOpen], closes);
  const bounds = new Map([
    [firstId, [firstOpen.event.sequence, closes[0].event.sequence]],
    [secondId, [secondOpen.event.sequence, closes[1].event.sequence]],
  ]);
  requests.filter((entry) => entry.message.cmd !== "close").forEach((entry) => {
    const bound = bounds.get(entry.message.panelInstanceId);
    if (!bound || entry.event.sequence <= bound[0] || entry.event.sequence >= bound[1]) {
      fail("kshop_request_outside_instance", "panel", "KShop request escaped its instance lifetime");
    }
  });
  const commandKey = (panelInstanceId, domain, cmd) =>
    panelInstanceId + "|" + domain + "|" + cmd;
  const observedCommandMultiset = requests.filter((entry) => entry.message.domain !== "inventory")
    .map((entry) => commandKey(
    entry.message.panelInstanceId,
    "shop",
    entry.message.cmd)).sort();
  const expectedCommandMultiset = [
    commandKey(firstId, "shop", "bulkQuery"),
    commandKey(firstId, "shop", "saveCart"),
    commandKey(firstId, "shop", "checkoutPreview"),
    commandKey(firstId, "shop", "checkoutCommit"),
    commandKey(firstId, "shop", "close"),
    commandKey(secondId, "shop", "bulkQuery"),
    commandKey(secondId, "shop", "close"),
  ].sort();
  if (!deepEqual(observedCommandMultiset, expectedCommandMultiset)
      || requests.some((entry) => entry.message.domain === "inventory"
        && entry.message.cmd !== "snapshot")) {
    fail("kshop_command_multiset_invalid", "panel",
      "KShop journey command multiset contains a missing, duplicate, or extra command", {
        observedCommandMultiset,
        expectedCommandMultiset,
      });
  }
  requests.forEach((entry) => {
    if (["checkout", "claim"].includes(entry.message.cmd)) {
      fail("legacy_shop_write_observed", "commit", "legacy checkout/claim was invoked");
    }
    if (entry.message.panelInstanceId !== secondId) return;
    const readOnly = entry.message.cmd === "bulkQuery"
      || entry.message.cmd === "snapshot"
      || entry.message.cmd === "tooltip"
      || entry.message.cmd === "close";
    if (!readOnly) {
      fail("readback_instance_write_observed", "readback",
        "restart readback instance must be read-only", {
          panelInstanceId: entry.message.panelInstanceId,
          cmd: entry.message.cmd,
        });
    }
  });
  const restartDetach = events.find((event) => event.sequence > closes[0].event.sequence
    && event.sequence < secondOpen.event.sequence
    && ["observer_detached", "observer_detach_transport_lost"].includes(event.kind));
  const restartObserverReady = events.find((event) => event.sequence > (restartDetach
    ? restartDetach.sequence : closes[0].event.sequence)
    && event.sequence < secondOpen.event.sequence && event.kind === "observer_ready");
  if (!restartDetach || !restartObserverReady) {
    fail("restart_observer_boundary_missing", "restart", "readback instance lacks a fresh observer/process boundary");
  }

  const firstBulkRequest = requireOne(requestsForInstance(requests, firstId, "bulkQuery", "shop"),
    "first_bulk_count_invalid", "first KShop instance needs one bulkQuery");
  const firstBulk = responseFor(firstBulkRequest, responses);
  if (firstBulk.message.success !== true || !Array.isArray(firstBulk.message.catalog)
      || !Array.isArray(firstBulk.message.cart) || firstBulk.message.cart.length !== 0
      || !Array.isArray(firstBulk.message.purchased)) {
    fail("first_bulk_invalid", "business", "first bulkQuery was not authoritative");
  }
  const selection = verifyCatalogSelection(bundle.selection, firstBulk.message.catalog,
    Number(firstBulk.message.kpoints), Number(firstBulk.message.playerLevel),
    Number(firstBulk.message.reverseLevel));
  const catalogDeliveryBaseline = ProductionClosure.verifyCatalogDeliveryContract(
    bundle.productionClosure && bundle.productionClosure.declarations
      && bundle.productionClosure.declarations.catalogDeliveryContract);
  assertSelectedCatalog(firstBulk.message.catalog, selection, "first_bulk");
  if (new Set([selection.itemName, selection.displayName, selection.icon]).size !== 3) {
    fail("identity_triple_not_distinct", "business",
      "A3 positive journey must select one production item with all three identity fields distinct");
  }
  const purchasedToken = requireTokenReference(firstBulk.message, "purchasedToken", "first_bulk");
  const previews = requestsForInstance(requests, firstId, "checkoutPreview", "shop");
  const previewRequest = requireOne(previews, "preview_request_count_invalid", "checkoutPreview must occur exactly once");
  if (previewRequest.message.v !== 1 || !exactTargetCart(previewRequest.message.cart, selection)) {
    fail("preview_request_cart_invalid", "preview", "checkoutPreview target cart is not exact");
  }
  const preview = responseFor(previewRequest, responses);
  const checkoutToken = requireTokenReference(preview.message, "checkoutToken", "preview");
  if (checkoutToken === purchasedToken) {
    fail("authority_token_reused", "preview", "checkout and purchased tokens must be distinct capabilities");
  }
  const total = assertPurchaseLines(preview.message.purchaseLines, preview.message.balance, selection);
  const selectedLine = preview.message.purchaseLines[0];
  const expectedPostMaxQuantity = selectedLine.itemKind === "information"
    ? selection.maxQuantity - selection.quantity : selection.maxQuantity;
  if (!Number.isInteger(expectedPostMaxQuantity) || expectedPostMaxQuantity < 0) {
    fail("post_catalog_dynamic_limit_invalid", "business",
      "selected item family cannot derive one exact post-purchase maxQuantity");
  }
  if (preview.message.success !== true || preview.message.v !== 1
      || preview.message.canCommit !== true || preview.message.blockingError !== ""
      || Number(preview.message.balance) !== Number(firstBulk.message.kpoints)
      || Number(preview.message.total) !== total
      || Number(preview.message.projectedBalance) !== Number(preview.message.balance) - total) {
    fail("preview_response_invalid", "preview", "authoritative preview is not committable/exact");
  }
  const commits = requestsForInstance(requests, firstId, "checkoutCommit", "shop");
  const commitRequest = requireOne(commits, "commit_request_count_invalid", "checkoutCommit must occur exactly once");
  const expectedCheckoutToken = requireTokenReference(commitRequest.message,
    "expectedCheckoutToken", "commit");
  if (commitRequest.message.v !== 1
      || expectedCheckoutToken !== checkoutToken) {
    fail("commit_token_mismatch", "commit", "commit did not echo exact preview token hash");
  }
  const inputs = assertTrustedFirstJourneyInputs(events, firstOpen, commitRequest, selection);
  const exactInputSet = assertExactBusinessInputSet(events, [firstOpen, secondOpen],
    closes, inputs, trustedCloseInputs);
  const firstAddSequence = Math.min(...inputs.addEvidence.map((entry) => entry.sequence));
  if (!(firstBulk.event.sequence < firstAddSequence
      && inputs.checkoutSequence < previewRequest.event.sequence
      && preview.event.sequence < inputs.commitSequence)) {
    fail("authority_input_order_invalid", "input",
      "bulk/add/checkout/preview/commit authority order is invalid");
  }
  const allSaveCartPairs = requestsForInstance(requests, firstId, "saveCart", "shop")
    .map((request) => ({ request, response: responseFor(request, responses) }));
  if (allSaveCartPairs.length < 1
      || allSaveCartPairs.some((pair) => pair.request.event.sequence >= commitRequest.event.sequence
        || pair.response.message.success !== true || pair.response.message.v !== 1)) {
    fail("save_cart_sequence_invalid", "commit", "every saveCart must settle successfully before commit");
  }
  const foreignSaveCart = requests.filter((entry) => entry.message.cmd === "saveCart"
    && entry.message.panelInstanceId !== firstId);
  if (foreignSaveCart.length > 0) {
    fail("save_cart_outside_first_instance", "commit", "fresh readback instance wrote the cart");
  }
  const saveCartPairs = allSaveCartPairs
    .filter((pair) => pair.response.event.sequence < commitRequest.event.sequence
      && pair.response.message.success === true && pair.response.message.v === 1
      && exactTargetCart(pair.response.message.cart, selection));
  if (saveCartPairs.length < 1) {
    fail("authoritative_save_cart_missing", "commit", "exact target cart was not saved before commit");
  }
  const commit = responseFor(commitRequest, responses);
  requireTokenReference(commit.message, "purchasedToken", "commit");
  assertPurchaseLines(commit.message.delivered, preview.message.balance, selection);
  assertSelectedCatalog(commit.message.catalog, selection, "commit", expectedPostMaxQuantity);
  if (commit.message.success !== true || commit.message.v !== 1
      || Number(commit.message.newBalance) !== Number(preview.message.projectedBalance)
      || !Array.isArray(commit.message.cart) || commit.message.cart.length !== 0
      || !deepEqual(commit.message.delivered, preview.message.purchaseLines)
      || !deepEqual(commit.message.purchased, firstBulk.message.purchased)
      || commit.message.purchasedToken !== purchasedToken) {
    fail("commit_response_invalid", "commit", "commit postcondition differs from the preview/initial authority");
  }
  const firstInventoryPairs = requestsForInstance(requests, firstId, "snapshot", "inventory")
    .map((request) => ({ request, response: responseFor(request, responses) }));
  const initialInventoryPairs = firstInventoryPairs.filter((pair) =>
    pair.response.event.sequence < firstAddSequence);
  const postCommitInventoryPairs = firstInventoryPairs.filter((pair) =>
    pair.request.event.sequence > commit.event.sequence
      && pair.response.event.sequence < closes[0].event.sequence);
  const restartInventoryPairs = requestsForInstance(requests, secondId, "snapshot", "inventory")
    .map((request) => ({ request, response: responseFor(request, responses) }))
    .filter((pair) => pair.request.event.sequence > secondOpen.event.sequence
      && pair.response.event.sequence < closes[1].event.sequence);
  if (firstInventoryPairs.length !== initialInventoryPairs.length + postCommitInventoryPairs.length
      || requestsForInstance(requests, secondId, "snapshot", "inventory").length
        !== restartInventoryPairs.length) {
    fail("inventory_surface_extra_call", "inventory",
      "an Inventory call escaped the exact initial/post-commit/restart phase partition");
  }
  const beforeInventory = validateInventorySurface(initialInventoryPairs, "initial inventory");
  const afterInventory = validateInventorySurface(postCommitInventoryPairs, "post-commit inventory");
  const restartInventory = validateInventorySurface(restartInventoryPairs, "restart inventory");
  [beforeInventory, afterInventory, restartInventory].forEach((surface) => {
    const writes = requests.filter((entry) => entry.event.sequence > surface.firstPair.request.event.sequence
      && entry.event.sequence < surface.lastPair.response.event.sequence
      && ["saveCart", "checkoutCommit", "checkout", "claim"].includes(entry.message.cmd));
    if (writes.length > 0) {
      fail("inventory_surface_write_interleaving", "inventory",
        surface.label + " contains an interleaved write request", {
          commands: writes.map((entry) => entry.message.cmd),
        });
    }
  });
  if (beforeInventory.accessibleCapacity !== afterInventory.accessibleCapacity
      || afterInventory.accessibleCapacity !== restartInventory.accessibleCapacity) {
    fail("inventory_phase_access_drift", "inventory",
      "all three phases must independently derive one equal declared battle-box tier", {
        accessibleCapacities: [beforeInventory.accessibleCapacity,
          afterInventory.accessibleCapacity, restartInventory.accessibleCapacity],
      });
  }
  const beforeCounts = beforeInventory.counts;
  const afterCounts = afterInventory.counts;
  if (!deepEqual(beforeInventory.profiles, afterInventory.profiles)) {
    fail("inventory_container_profile_drift", "inventory",
      "container capacity/view/filter profile changed across the one-item commit");
  }
  assertInventoryDelta(beforeCounts, afterCounts, selection);
  const physicalInventoryDelta = assertPhysicalInventoryDelta(beforeInventory,
    afterInventory, selection, selectedLine.itemKind);
  assertCountsEqual(afterCounts, restartInventory.counts, "restart_inventory_mismatch");
  assertRestartInventory(afterInventory, restartInventory);

  function verifyFreshPanel(openEntry, id, label, inventorySurface) {
    const bulkRequest = requireOne(requestsForInstance(requests, id, "bulkQuery", "shop"),
      label + "_bulk_count_invalid", label + " KShop instance needs one fresh bulkQuery");
    const bulk = responseFor(bulkRequest, responses);
    if (bulk.event.sequence <= openEntry.event.sequence || bulk.message.success !== true
        || Number(bulk.message.kpoints) !== Number(commit.message.newBalance)
        || !Array.isArray(bulk.message.cart) || bulk.message.cart.length !== 0
        || !deepEqual(bulk.message.purchased, firstBulk.message.purchased)
        || requireTokenReference(bulk.message, "purchasedToken", label) !== commit.message.purchasedToken) {
      fail(label + "_bulk_readback_invalid", "readback", label + " bulk readback is stale/different");
    }
    assertSelectedCatalog(bulk.message.catalog, selection, label, expectedPostMaxQuantity);
    if (!inventorySurface || inventorySurface.firstPair.request.event.sequence <= openEntry.event.sequence) {
      fail(label + "_inventory_missing", "readback", label + " inventory readback is missing");
    }
    const counts = inventorySurface.counts;
    assertCountsEqual(afterCounts, counts, label + "_inventory_mismatch");
    if (!deepEqual(afterInventory.profiles, inventorySurface.profiles)) {
      fail(label + "_inventory_profile_mismatch", "inventory",
        label + " inventory container profile differs after restart");
    }
    return { bulkRequest, bulk, inventorySurface, counts, profiles: inventorySurface.profiles,
      physicalSlots: inventorySurface.physicalSlots };
  }
  const second = verifyFreshPanel(secondOpen, secondId, "restart", restartInventory);

  const checkoutTokenOccurrences = events.reduce((count, event) => {
    const message = eventMessage(event);
    if (!message) return count;
    return count + (message.checkoutToken === checkoutToken ? 1 : 0)
      + (message.expectedCheckoutToken === checkoutToken ? 1 : 0);
  }, 0);
  if (checkoutTokenOccurrences !== 2) {
    fail("checkout_token_consumption_invalid", "commit",
      "checkout token must be issued once and consumed once", { checkoutTokenOccurrences });
  }
  const purchasedTokenValues = events.map(eventMessage).filter(Boolean)
    .filter((message) => own(message, "purchasedToken"))
    .map((message) => requireTokenReference(message, "purchasedToken", "business"));
  if (purchasedTokenValues.length !== 3
      || purchasedTokenValues.some((value) => value !== purchasedToken)) {
    fail("purchased_token_authority_invalid", "business",
      "one required purchased-token value must bind initial, commit, and restart authority", {
        count: purchasedTokenValues.length,
        unique: new Set(purchasedTokenValues).size,
      });
  }

  const observerContract = verifyPanelRequestIssueOrder(events, requests);

  const records = hostRecords(bundle);
  assertNoHostAuthorityAnomalies(records);
  const mappedRequests = requests.filter((request) => request.message.cmd !== "close");
  const responseKeys = responses.map((response) => [response.message.domain || "shop",
    response.message.panelInstanceId, response.message.cmd, response.message.callId].join("|"));
  const expectedResponseKeys = mappedRequests.map((request) => [request.message.domain || "shop",
    request.message.panelInstanceId, request.message.cmd, request.message.callId].join("|"));
  if (canonicalJson(responseKeys.slice().sort()) !== canonicalJson(expectedResponseKeys.slice().sort())) {
    fail("web_response_multiset_mismatch", "host_log",
      "Web responses do not exactly cover every Flash-bound KShop request");
  }
  const loggedPanels = records.map((record) => ({ record, summary: parsePanelSummary(record) }))
    .filter((entry) => entry.summary && entry.summary.panel === "kshop");
  const webRequestMultiset = requests.map((entry) => canonicalJson({ panel: "kshop",
    domain: entry.message.domain === "inventory" ? "inventory" : "other",
    cmd: entry.message.cmd, callId: entry.message.cmd === "close" ? "other" : entry.message.callId })).sort();
  const hostPanelMultiset = loggedPanels.map((entry) => canonicalJson({ panel: entry.summary.panel,
    domain: entry.summary.domain, cmd: entry.summary.cmd, callId: entry.summary.callId })).sort();
  if (canonicalJson(webRequestMultiset) !== canonicalJson(hostPanelMultiset)) {
    fail("host_panel_multiset_mismatch", "host_log",
      "authenticated Host tails do not exactly cover every KShop Web request");
  }
  const uniqueMapped = [];
  const seenCallIds = new Set();
  mappedRequests.forEach((request) => {
    const key = request.message.domain + "|" + request.message.callId;
    if (seenCallIds.has(key)) {
      fail("web_call_id_reused", "host_log", "relevant Web callId was reused in one domain", {
        callId: request.message.callId,
        domain: request.message.domain || null,
      });
    }
    seenCallIds.add(key);
    uniqueMapped.push(request);
  });
  const mappings = uniqueMapped.map((request) => assertHostMapping(request, records,
    responseFor(request, responses)));
  const dispatchBindings = records.map((record) => ({ record,
    binding: parseAuthorityFlashBinding(record) })).filter((entry) => entry.binding);
  if (dispatchBindings.length !== mappings.length) {
    fail("host_flash_binding_multiset_mismatch", "host_log",
      "explicit authority_flash_call_bound receipts contain gaps or extras", {
        bindings: dispatchBindings.length,
        mappings: mappings.length,
      });
  }
  const bindingKeys = dispatchBindings.map((entry) => canonicalJson(entry.binding)).sort();
  const mappingBindingKeys = mappings.map((entry) => canonicalJson({
    domain: entry.domain || "shop",
    webCallId: entry.webCallId,
    flashCallId: entry.flashCallId,
    panel: "kshop",
    panelInstanceId: entry.panelInstanceId,
    cmd: entry.cmd,
    action: (entry.domain === "inventory"
      ? (entry.cmd === "tooltip" ? "inventoryTooltip" : "inventorySnapshot")
      : SHOP_ACTIONS[entry.cmd]),
  })).sort();
  if (!deepEqual(bindingKeys, mappingBindingKeys)) {
    fail("host_flash_binding_multiset_mismatch", "host_log",
      "dispatch receipts do not exactly bind Web owner/callId to Flash fid/action");
  }
  const shopMapped = mappings.filter((entry) => entry.domain == null);
  const inventoryMapped = mappings.filter((entry) => entry.domain === "inventory");
  const shopSends = records.map((record) => ({ record,
    message: parseFlashSend(record, "ShopTask") }))
    .filter((entry) => entry.message && entry.message.task === "cmd");
  const inventorySends = records.map((record) => ({ record,
    message: parseFlashSend(record, "InventoryTask") }))
    .filter((entry) => entry.message && entry.message.task === "cmd");
  const socketResponses = records.map((record) => ({ record, response: parseSocketResponse(record) }))
    .filter((entry) => entry.response);
  const shopReceipts = records.filter((record) =>
    record.body === "[ShopTask] <- Flash response received");
  const routes = records.map((record) => ({ record, route: parsePanelRoute(record) }))
    .filter((entry) => entry.route);
  if (routes.length !== mappings.length
      || shopSends.length !== shopMapped.length || inventorySends.length !== inventoryMapped.length
      || socketResponses.filter((entry) => entry.response.task === "shop_response").length
        !== shopMapped.length
      || socketResponses.filter((entry) => entry.response.task === "inventory_response").length
        !== inventoryMapped.length
      || shopReceipts.length !== shopMapped.length) {
    fail("host_flash_multiset_mismatch", "host_log",
      "Host routes, sends, top-level Flash responses, and consumer receipts contain gaps or extras");
  }
  const mappingKeys = mappings.map((entry) => entry.lifecycle + ":"
    + (entry.domain || "shop") + ":" + entry.flashCallId);
  if (new Set(mappingKeys).size !== mappingKeys.length) {
    fail("flash_call_id_reused", "host_log", "mapped Flash callId was reused within one task domain");
  }
  const commitMapping = mappings.find((entry) => entry.webCallId === commitRequest.message.callId
    && entry.cmd === "checkoutCommit");
  if (!commitMapping) fail("commit_host_mapping_missing", "host_log", "commit mapping is absent");
  const exactCloseReceipts = assertExactCloseReceipts(records, closes);
  const globalHostSet = assertGlobalRelevantHostSet(records, mappings);
  const firstLifecycleRecords = records.filter((record) => record.lifecycle === "first");
  const restartLifecycleRecords = records.filter((record) => record.lifecycle === "restart");
  const firstRelevant = firstLifecycleRecords.filter((record) => /^\[(?:Panel|PanelHost|ShopTask|InventoryTask|XmlSocket:JSON|ArchiveTask)\]/.test(record.body)
    || record.body.startsWith("event=panel_exact_close_completed")
    || /(?:^|[\s|])sv:[12](?=$|[\s|])/.test(record.body));
  const restartRelevant = restartLifecycleRecords.filter((record) =>
    /^\[(?:Panel|PanelHost|ShopTask|InventoryTask|XmlSocket:JSON|ArchiveTask)\]/.test(record.body)
      || record.body.startsWith("event=panel_exact_close_completed"));
  if (firstRelevant.length < 1 || !firstRelevant.at(-1).body.startsWith("[ArchiveTask] Shadow saved:")
      || exactCloseReceipts[0].completionLine >= firstRelevant.at(-1).lineNumber
      || restartRelevant.length < 1
      || !restartRelevant.at(-1).body.startsWith("event=panel_exact_close_completed")
      || parsePanelExactCloseCompleted(restartRelevant.at(-1)).panelInstanceId !== secondId) {
    fail("host_terminal_tail_invalid", "host_log",
      "complete authenticated lifecycle tails do not terminate at archive/restart close");
  }
  const control = verifyControl(bundle, events, mappings, requests);
  const persistence = verifyRuntimeAndPersistence(bundle, records, commitMapping);
  const inventorySurfaces = [beforeInventory, afterInventory, restartInventory];
  const globalTimeline = verifyGlobalTimeline(bundle, records, mappings,
    exactCloseReceipts, control, persistence, inventorySurfaces);
  const receiptState = receiptStateForEvidenceMode(bundle.evidenceMode);
  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: receiptState.status,
    liveStatus: receiptState.liveStatus,
    evidenceMode: bundle.evidenceMode,
    deployment: "NOT_DEPLOYED",
    verifiedAt: new Date().toISOString(),
    slot: bundle.slot,
    selectedTransport: control.selectedTransport,
    controlEvidence: { steps: control.steps, providerOperationIds: control.providerOperationIds,
      persisted: control.persisted },
    selection,
    catalogDeliveryBaseline,
    targetCart: selection.cart,
    targetIdentityTriples: [{ catalogIndex: selection.catalogIndex,
      itemName: selection.itemName, displayName: selection.displayName, icon: selection.icon,
      unitPrice: selection.unitPrice, quantity: selection.quantity }],
    total,
    expectedPostMaxQuantity,
    firstBalance: Number(preview.message.balance),
    finalBalance: Number(commit.message.newBalance),
    panelInstances: [firstId, secondId],
    browserEventIsTrusted: inputs,
    exactInputSet,
    trustedCloseInputs,
    closeAcceptance: { provenByProductionLog: true, receipts: exactCloseReceipts },
    observerContract,
    wirePayloadFacts,
    hostMappings: mappings,
    globalHostSet,
    inventoryCounts: { before: beforeCounts, after: afterCounts, restart: second.counts },
    inventoryProfiles: { before: beforeInventory.profiles,
      after: afterInventory.profiles, restart: second.profiles },
    inventoryPhysicalSlots: { before: beforeInventory.physicalSlots,
      after: afterInventory.physicalSlots, restart: second.physicalSlots,
      delivery: physicalInventoryDelta },
    inventorySurfaces: inventorySurfaces.map((surface) => ({
      schema: surface.schema, phase: surface.label,
      panelInstanceId: surface.panelInstanceId,
      accessibleCapacity: surface.accessibleCapacity,
      sessionNonceSha256: sha256Text(surface.sessionNonce),
      callIds: surface.callIds.slice(), revisions: surface.revisions,
      timeline: JSON.parse(JSON.stringify(surface.timeline)),
    })),
    persistence,
    globalTimeline,
    moduleAdmission,
    rawBundle: preSeal ? null : { manifestSha256: rawBundle.manifestSha256,
      bundlePayloadSha256: rawBundle.bundlePayloadSha256,
      embedded: rawBundle.embedded },
    transcript: {
      eventCount: bundle.transcript.eventCount,
      chainHead: bundle.transcript.chainHead,
    },
    hostLogTailSha256: bundle.hostLog.lifecycles.map((entry) => entry.terminalSnapshot.tailSha256),
    boundaries: {
      physicalDualScreen: false,
      deployment: false,
      operatorAcknowledgementIsBusinessProof: false,
      physicalInputAttestation: false,
      operatorAckTimestampsAreSelfReported: false,
      providerOperationReceiptsVerified: true,
      captureSemanticContentIndependentlyVerified: false,
      browserEventIsTrustedNotPhysicalProof: true,
      productionAcceptedCloseReceiptAvailable: true,
      tokenMaterialPublished: false,
    },
  };
  assertNoRawTokens(receipt);
  receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
  return receipt;
}

function preSealProjection(bundle) {
  const projection = JSON.parse(JSON.stringify(bundle));
  delete projection.rawBundleManifest;
  if (projection.moduleAdmission) projection.moduleAdmission.journal = null;
  return projection;
}

function verifyBundlePreSeal(bundle) {
  const provisionalReceipt = verifyBundle(bundle, { preSeal: true });
  const evidence = {
    schema: "workbench-live-e2e.kshop.preseal-verification.v1",
    bundleProjectionSha256: sha256Text(canonicalJson(preSealProjection(bundle))),
    provisionalReceipt,
    provisionalReceiptSha256: sha256Text(canonicalJson(provisionalReceipt)),
  };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function finalizePreSealVerification(bundle, evidence) {
  const payload = Object.assign({}, evidence);
  delete payload.evidenceSha256;
  if (!exactKeys(evidence, ["schema", "bundleProjectionSha256", "provisionalReceipt",
    "provisionalReceiptSha256", "evidenceSha256"])
      || evidence.schema !== "workbench-live-e2e.kshop.preseal-verification.v1"
      || !SHA256_RE.test(String(evidence.bundleProjectionSha256 || ""))
      || evidence.bundleProjectionSha256
        !== sha256Text(canonicalJson(preSealProjection(bundle)))
      || evidence.provisionalReceiptSha256
        !== sha256Text(canonicalJson(evidence.provisionalReceipt))
      || evidence.evidenceSha256 !== sha256Text(canonicalJson(payload))) {
    fail("preseal_verification_binding_invalid", "module_admission",
      "sealed finalization is detached from the exact pre-seal semantic validation");
  }
  const moduleAdmission = verifyModuleAdmission(bundle, {});
  const rawBundle = verifyRawBundleManifest(bundle);
  assertNoRawTokens(bundle);
  const receipt = JSON.parse(JSON.stringify(evidence.provisionalReceipt));
  delete receipt.receiptSha256;
  receipt.moduleAdmission = moduleAdmission;
  receipt.rawBundle = { manifestSha256: rawBundle.manifestSha256,
    bundlePayloadSha256: rawBundle.bundlePayloadSha256, embedded: rawBundle.embedded };
  receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
  return receipt;
}

function prepareDeferredBundleVerification(bundle) {
  const provisionalReceipt = verifyBundle(bundle, { deferModuleJournalRuntime: true });
  const evidence = {
    schema: "workbench-live-e2e.kshop.deferred-module-verification.v1",
    bundleSha256: sha256Text(canonicalJson(bundle)),
    provisionalReceipt,
    provisionalReceiptSha256: sha256Text(canonicalJson(provisionalReceipt)),
  };
  evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
  return evidence;
}

function finalizeDeferredBundleVerification(bundle, evidence) {
  const payload = Object.assign({}, evidence);
  delete payload.evidenceSha256;
  if (!exactKeys(evidence, ["schema", "bundleSha256", "provisionalReceipt",
    "provisionalReceiptSha256", "evidenceSha256"])
      || evidence.schema !== "workbench-live-e2e.kshop.deferred-module-verification.v1"
      || evidence.bundleSha256 !== sha256Text(canonicalJson(bundle))
      || evidence.provisionalReceiptSha256
        !== sha256Text(canonicalJson(evidence.provisionalReceipt))
      || evidence.evidenceSha256 !== sha256Text(canonicalJson(payload))) {
    fail("deferred_verification_binding_invalid", "module_admission",
      "post-seal module finalization is detached from pre-seal bundle validation");
  }
  const moduleAdmission = verifyModuleAdmission(bundle, {});
  const receipt = JSON.parse(JSON.stringify(evidence.provisionalReceipt));
  delete receipt.receiptSha256;
  receipt.moduleAdmission = moduleAdmission;
  receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
  return receipt;
}

module.exports = {
  REQUIRED_CONTROL_STEPS,
  SHOP_ACTIONS,
  authoritativeIconNamesForLifecycle,
  assertHostMapping,
  exactTargetCart,
  finalizeDeferredBundleVerification,
  inventoryCounts,
  validateInventorySurface,
  prepareDeferredBundleVerification,
  receiptStateForEvidenceMode,
  finalizePreSealVerification,
  verifyBundle,
  verifyBundlePreSeal,
};
