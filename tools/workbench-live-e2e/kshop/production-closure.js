"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  canonicalJson,
  classifyCatalogDelivery,
  fail,
  sha256Bytes,
  sha256Text,
} = require("./common");

const CLOSURE_SCHEMA = "workbench-live-e2e.kshop.production-closure.v8";
const LOADED_SCHEMA = "workbench-live-e2e.kshop.loaded-production.v7";
const BINDING_SCHEMA = "workbench-live-e2e.kshop.production-binding.v1";
const CANDIDATE_PRODUCER_SCHEMA = "workbench-live-e2e.kshop.candidate-producer-binding.v1";
const PRODUCER_INPUTS_SCHEMA = "workbench-live-e2e.kshop.runtime-producer-inputs.v1";
const FONT_ENVIRONMENT_SCHEMA = "workbench-live-e2e.kshop.font-environment.v2";
const FONT_CATALOG_XML = "fonts/fonts.xml";
const FONT_RUNTIME_PROJECTION = "launcher/web/generated/font-catalog.json";
const PERMANENT_FONT_FILES = Object.freeze([
  "fonts/permanent/runtime/jetbrains-mono.woff2",
  "fonts/permanent/runtime/source-han-serif-cn-regular.otf",
]);
const ICON_PROJECTION_SCHEMA = "workbench-live-e2e.kshop.icon-resource-projection.v1";
const CATALOG_DELIVERY_SCHEMA = "workbench-live-e2e.kshop.catalog-delivery-contract.v2";
const INVENTORY_SURFACE_CONTRACT_SCHEMA
  = "workbench-live-e2e.kshop.production-inventory-surface.v1";
const INVENTORY_SURFACE_SOURCE_SCHEMA
  = "workbench-live-e2e.kshop.production-inventory-source-anchors.v3";
const INVENTORY_SURFACE_ANCHOR_VERSION
  = "kshop-inventory-physical-authority.semantic-anchor.v3";
const KSHOP_SOURCE_PATH = "launcher/web/modules/kshop.js";
const INVENTORY_RUNTIME_PATH = "launcher/web/modules/inventory-runtime.js";
const ITEMUTIL_DELIVERY_SOURCE_SCHEMA
  = "workbench-live-e2e.kshop.itemutil-delivery-source-contract.v3";
const ITEMUTIL_DELIVERY_ANCHOR_VERSION = "kshop-itemutil-arrayinventory.semantic-anchor.v2";
const AS2_TOKEN_CANONICALIZATION = "as2-function-lexical-token-stream.v1";
const ITEMUTIL_PATH = "scripts/类定义/org/flashNight/arki/item/ItemUtil.as";
const ARRAY_INVENTORY_PATH
  = "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as";
const AS2_TARGET_CLASSES = Object.freeze({
  [ITEMUTIL_PATH]: "org.flashNight.arki.item.ItemUtil",
  [ARRAY_INVENTORY_PATH]: "org.flashNight.arki.item.itemCollection.ArrayInventory",
});
const SHA256_RE = /^[A-Fa-f0-9]{64}$/;
const producerInputsCache = new Map();
const fontEnvironmentCache = new Map();
const CANONICAL_ROOT = path.resolve(__dirname, "..", "..", "..");

const REQUIRED_KSHOP_LAZY_WEB = Object.freeze([
  "launcher/web/modules/panel-runtime.js",
  "launcher/web/modules/workbench-lifecycle.js",
  "launcher/web/modules/workbench-focus.js",
  "launcher/web/modules/workbench-primitives.js",
  "launcher/web/modules/workbench-profile.js",
  "launcher/web/modules/workbench.js",
  "launcher/web/modules/workbench-components.js",
  "launcher/web/modules/item-filter.js",
  "launcher/web/modules/kshop-runtime.js",
  "launcher/web/modules/inventory-runtime.js",
  "launcher/web/modules/inventory-ui.js",
  "launcher/web/modules/kshop-views.js",
  "launcher/web/modules/kshop-cart-controller.js",
  "launcher/web/modules/kshop-catalog-presenter.js",
  "launcher/web/modules/kshop-owned-inventory-presenter.js",
  "launcher/web/modules/kshop-tooltip-presenter.js",
  "launcher/web/modules/kshop-procurement-navigation.js",
  "launcher/web/modules/kshop.js",
]);

const HOST_FILES = Object.freeze([
  "launcher/src/Program.cs",
  { role: "host", relativePath: "launcher/src/Tasks/ShopTask.cs" },
  { role: "host", relativePath: "launcher/src/Tasks/InventoryTask.cs" },
  { role: "host", relativePath: "launcher/src/Tasks/FontPackTask.cs" },
  { role: "host", relativePath: "launcher/src/Guardian/AuthorityLogFormatter.cs" },
  { role: "host", relativePath: "launcher/src/Guardian/LogManager.cs" },
  { role: "host", relativePath: "launcher/src/Guardian/PanelHostController.cs" },
  { role: "host", relativePath: "launcher/src/Guardian/PanelRequestOwnerLifecycle.cs" },
  { role: "host", relativePath: "launcher/src/Guardian/WebOverlayForm.cs" },
  { role: "host", relativePath: "launcher/src/Guardian/LauncherCommandRouter.cs" },
  { role: "host", relativePath: "launcher/src/Tasks/PanelBridge.cs" },
  { role: "host", relativePath: "launcher/src/Bus/MessageRouter.cs" },
  { role: "host", relativePath: "launcher/src/Bus/TaskRegistry.cs" },
  { role: "host", relativePath: "launcher/src/Bus/XmlSocketServer.cs" },
].map((entry) => typeof entry === "string" ? { role: "host_composition", relativePath: entry } : entry));

const BUILD_FILES = Object.freeze([
  { role: "runtime_artifact_source", relativePath: "launcher/CRAZYFLASHER7MercenaryEmpire.csproj" },
  { role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json" },
  { role: "runtime_producer_source", relativePath: ".gitattributes" },
  { role: "runtime_producer_source", relativePath: "launcher/build-runtime-candidate.ps1" },
  { role: "runtime_producer_source", relativePath: "launcher/native/assert-pinned-tools.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/build-audio-v2.ps1" },
  { role: "runtime_producer_source", relativePath: "launcher/native/build.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/bootstrap/build.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/sol_parser/.cargo/config.toml" },
  { role: "runtime_producer_source", relativePath: "launcher/native/sol_parser/build.bat" },
  { role: "runtime_producer_source", relativePath: "tools/check-runtime-build-env.ps1" },
  { role: "runtime_producer_source", relativePath: "tools/runtime-build-v2-common.ps1" },
  { role: "runtime_toolchain_lock", relativePath: "config/build/runtime-toolchain.lock.json" },
  { role: "runtime_toolchain_lock", relativePath: "global.json" },
  { role: "runtime_toolchain_lock", relativePath: "launcher/native/sol_parser/rust-toolchain.toml" },
]);

const AS2_FILES = Object.freeze([
  { role: "as2_manifest", relativePath: "scripts/asLoaderManifest/frame10.as" },
  { role: "as2_manifest", relativePath: "scripts/asLoaderManifest/frame41.as" },
  { role: "as2_source", relativePath: "scripts/逻辑系统分区/商城系统_兼容.as" },
  { role: "as2_source", relativePath: "scripts/逻辑系统分区/商城系统_WebView.as" },
  { role: "as2_dependency", relativePath: "scripts/类定义/LiteJSON.as" },
  { role: "as2_dependency", relativePath: "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as" },
  { role: "as2_dependency", relativePath: "scripts/类定义/org/flashNight/arki/item/ItemUtil.as" },
  { role: "as2_dependency", relativePath: "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as" },
  { role: "as2_dependency", relativePath: "scripts/类定义/org/flashNight/arki/pause/PauseManager.as" },
  { role: "as2_swf", relativePath: "scripts/asLoader.swf" },
]);

function exactFile(root, descriptor) {
  const filePath = path.resolve(root, descriptor.relativePath);
  const expectedRoot = path.resolve(root) + path.sep;
  if (!filePath.toLowerCase().startsWith(expectedRoot.toLowerCase())) {
    fail("production_closure_path_invalid", "production_closure",
      "production closure path escaped the canonical root", descriptor);
  }
  let stat;
  let real;
  try {
    stat = fs.lstatSync(filePath);
    real = fs.realpathSync.native(filePath);
  } catch (error) {
    fail("production_closure_file_missing", "production_closure",
      "required KShop production file is missing", { relativePath: descriptor.relativePath });
  }
  if (!stat.isFile() || stat.isSymbolicLink() || path.resolve(real) !== filePath) {
    fail("production_closure_file_invalid", "production_closure",
      "required KShop production file is not one exact regular file", {
        relativePath: descriptor.relativePath,
      });
  }
  const bytes = fs.readFileSync(filePath);
  return { role: descriptor.role, locator: "root:" + descriptor.relativePath.replace(/\\/g, "/"),
    sha256: sha256Bytes(bytes), bytes: bytes.length };
}

function readExactText(root, relativePath) {
  const entry = exactFile(root, { role: "validation", relativePath });
  return { entry, text: fs.readFileSync(path.resolve(root, relativePath), "utf8") };
}

const INVENTORY_SURFACE_INVARIANTS = Object.freeze([
  "kshop_reader_binds_exact_panel_owner",
  "kshop_request_binding_is_unique_exact_mux_transport",
  "checkout_and_claim_hold_inventory_owner_through_refresh",
  "filter_key_filter_spec_or_scope_requires_authority_projection",
  "local_projection_rejects_constrained_requests",
  "constrained_refresh_requests_exact_desired_projection",
  "physical_surface_request_rejects_synchronous_duplicate_callback",
  "projection_request_requires_exact_call_id_and_single_sync_callback",
  "projection_request_throw_or_invalid_return_fails_closed",
  "projection_success_and_failure_have_independent_single_completion_fences",
  "projection_response_requires_same_v_and_session",
  "projection_response_requires_same_container_revision",
  "projection_response_sequence_follows_complete_surface",
  "unscoped_facets_and_counts_match_complete_surface",
  "every_visible_slot_deep_equals_its_complete_physical_slot",
  "successful_projection_retains_complete_surface_receipt",
]);

const REVIEWED_INVENTORY_CALLABLE_TOKEN_SHA256 = Object.freeze({
  "consumer.inventoryCoordinator": "1f3b3cc5b1e524ad7b8152828835bfde4e1c11ec707631649ac921b07c55f6ff",
  "consumer.commitCheckout": "83d04d78297e4a73d9a3cfd845d2d6bed5c3509aedd4edd01a8fecc5c01545df",
  "consumer.onClaim": "86126993e20852cac351cce458e48bdcb5d141e3102f283f8b43182beaea8513",
});

const INVENTORY_SURFACE_SOURCE_ANCHORS = Object.freeze([
  { id: "consumer.coordinator.assignment", source: "consumer", scope: "inventoryCoordinator",
    needle: "var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({" },
  { id: "consumer.coordinator.request", source: "consumer", scope: "inventoryCoordinator",
    needle: "request: requestInventory," },
  { id: "consumer.request.transport", source: "consumer", scope: "requestInventory",
    needle: "return _inventoryMux.request(cmd, payload || {}, {sendError:'disconnected'}, callback);" },
  { id: "consumer.reader.owner", source: "consumer", scope: "inventoryCoordinator",
    needle: "readPhysicalSurface: function(isActive, callback) { return InventoryRuntime.readPhysicalInventorySurface(requestInventory, {isActive:isActive, expectedPanel:'kshop', expectedPanelInstanceId:_panelInstanceId}, callback); }," },
  { id: "consumer.checkout.begin", source: "consumer", scope: "commitCheckout",
    needle: "var inventoryWrite = _inventoryCoordinator.beginExternalWrite('shop.checkoutCommit');" },
  { id: "consumer.checkout.complete", source: "consumer", scope: "commitCheckout",
    needle: "if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, needsInventoryRefresh, function(refreshResult)" },
  { id: "consumer.claim.begin", source: "consumer", scope: "onClaim",
    needle: "var inventoryWrite = _inventoryCoordinator.beginExternalWrite('shop.claim');" },
  { id: "consumer.claim.complete", source: "consumer", scope: "onClaim",
    needle: "if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, needsInventoryRefresh, function(refreshResult)" },
  { id: "provider.physical.sync_duplicate", source: "provider", scope: "readPhysicalSurface",
    needle: "if (!returned) { if (queued) queuedDuplicate = true; else { queued = true; queuedResponse = response; } return; } handleResponse(response);" },
  { id: "provider.physical.return_fence", source: "provider", scope: "readPhysicalSurface",
    needle: "if (!isIdentityText(expectedCallId, 160) || queuedDuplicate) { if (ordinal === 0) reject('inventory_surface_request_contract_invalid', true); else reject('inventory_surface_request_contract_invalid'); return false; }" },
  { id: "provider.constraint.classifier", source: "provider",
    scope: "requestNeedsAuthorityProjection",
    needle: "return normalizeFilterKey(request && request.filterKey) !== 'all' || !!request && own(request, 'filterSpec') || normalizeProjectionScope(request && request.scope) !== 'all';" },
  { id: "provider.local.rejects_constrained", source: "provider",
    scope: "projectPhysicalSurfaceToVisibleRequests",
    needle: "if (requestNeedsAuthorityProjection(request)) return null;" },
  { id: "provider.followup.branch", source: "provider", scope: "refreshPhysicalSurface",
    needle: "if (requestsNeedAuthorityProjection(desiredRequests)) {" },
  { id: "provider.followup.exact_desired", source: "provider", scope: "refreshPhysicalSurface",
    needle: "self._request('snapshot', {v:1, requests:cloneRequests(desiredRequests)}, function(response)" },
  { id: "provider.followup.exact_call_id", source: "provider", scope: "refreshPhysicalSurface",
    needle: "if (!response || response.callId !== expectedCallId)" },
  { id: "provider.followup.sync_duplicate", source: "provider", scope: "refreshPhysicalSurface",
    needle: "if (!returned) { if (queued) queuedDuplicate = true; else { queued = true; queuedResponse = response; } return; } handleProjectionResponse(response);" },
  { id: "provider.followup.throw_fence", source: "provider", scope: "refreshPhysicalSurface",
    needle: "catch (_projectionRequestError) { returned = true; failProjectionRequestContract(); return; }" },
  { id: "provider.followup.return_fence", source: "provider", scope: "refreshPhysicalSurface",
    needle: "if (!isIdentityText(expectedCallId, 160) || queuedDuplicate) { failProjectionRequestContract(); return; }" },
  { id: "provider.followup.failure_once", source: "provider", scope: "refreshPhysicalSurface",
    needle: "function failProjectionRequestContract() { if (projectionDone || !self._isActiveOperation(operation)) return; projectionDone = true; finish({success:false, error:'inventory_surface_projection_request_contract_invalid'}, null); }" },
  { id: "provider.followup.once_fence", source: "provider", scope: "refreshPhysicalSurface",
    needle: "function handleProjectionResponse(response) { if (projectionDone || !self._isActiveOperation(operation)) return; projectionDone = true;" },
  { id: "provider.coherence.session", source: "provider",
    scope: "authorityProjectionMatchesPhysicalSurface",
    needle: "!response || response.success !== true || response.v !== 1 || !isIdentityText(response.sessionNonce, 128) || response.sessionNonce !== surface.sessionNonce" },
  { id: "provider.coherence.revision", source: "provider",
    scope: "authorityProjectionMatchesPhysicalSurface",
    needle: "snapshot.capacity !== full.capacity || snapshot.accessibleCapacity !== full.accessibleCapacity || snapshot.pageSizeHint !== full.pageSizeHint || snapshot.locked !== full.locked || snapshot.containerEpoch !== full.containerEpoch || snapshot.containerVersion !== full.containerVersion" },
  { id: "provider.coherence.sequence", source: "provider",
    scope: "authorityProjectionMatchesPhysicalSurface",
    needle: "snapshot.snapshotSeq <= maximumSurfaceSequence" },
  { id: "provider.coherence.facets", source: "provider",
    scope: "authorityProjectionMatchesPhysicalSurface",
    needle: "!sameProjectionValue(snapshot.filterFacets, full.filterFacets) || snapshot.filterItemCount !== full.filterItemCount || !sameProjectionValue(snapshot.setFacets, full.setFacets) || snapshot.setFilterItemCount !== full.setFilterItemCount" },
  { id: "provider.coherence.physical_slot", source: "provider",
    scope: "authorityProjectionMatchesPhysicalSurface",
    needle: "!sameProjectionValue(visibleSlot, full.slots[physicalSlot])" },
  { id: "provider.receipt.retained", source: "provider", scope: "refreshPhysicalSurface",
    needle: "&& self._applySnapshots(response.snapshots, desiredRequests); finish(valid ? {success:true} : {success:false,error:'inventory_surface_projection_invalid'}, result.surface);" },
]);

const INVENTORY_SURFACE_SOURCE_ORDER_GROUPS = Object.freeze([
  { id: "consumer.coordinator.wiring_order", source: "consumer",
    scope: "inventoryCoordinator", anchorIds: ["consumer.coordinator.assignment",
      "consumer.coordinator.request", "consumer.reader.owner"] },
  { id: "consumer.checkout.external_write_order", source: "consumer", scope: "commitCheckout",
    anchorIds: ["consumer.checkout.begin", "consumer.checkout.complete"] },
  { id: "consumer.claim.external_write_order", source: "consumer", scope: "onClaim",
    anchorIds: ["consumer.claim.begin", "consumer.claim.complete"] },
]);

const INVENTORY_JS_WORD_START_RE = /^[\p{L}\p{Nl}_$]$/u;
const INVENTORY_JS_WORD_PART_RE = /^[\p{L}\p{Nl}\p{Nd}\p{Mn}\p{Mc}\p{Pc}_$]$/u;
const INVENTORY_JS_MULTI_SYMBOLS = Object.freeze([
  ">>>=", "&&=", "||=", "??=", "**=", "===", "!==", ">>>", "<<=", ">>=", "=>",
  "==", "!=", "<=", ">=",
  "++", "--", "&&", "||", "??", "+=", "-=", "*=", "/=", "%=", "<<", ">>", "&=",
  "|=", "^=", "**", "?.", "...",
].sort((left, right) => right.length - left.length));

function inventorySourceFail(message, details) {
  fail("production_inventory_surface_source_contract_invalid", "production_closure",
    message, details || {});
}

const INVENTORY_REGEX_PREFIX_SYMBOLS = new Set([
  "(", "{", "}", "[", ",", ";", ":", "=", "==", "===", "!=", "!==", "!", "&&",
  "||", "??", "?", "+", "-", "*", "%", "&", "|", "^", "~", "<", ">", "<=",
  ">=", "=>",
]);
const INVENTORY_REGEX_PREFIX_WORDS = new Set([
  "return", "throw", "case", "delete", "void", "typeof", "instanceof", "in", "of",
  "new", "else", "do", "yield", "await",
]);
const INVENTORY_REGEX_CONTROL_HEADER_WORDS = new Set([
  "if", "while", "for", "with", "switch", "catch",
]);

function inventoryFollowsControlHeader(tokens) {
  if (tokens.length === 0 || tokens[tokens.length - 1].value !== ")") return false;
  let depth = 0;
  for (let index = tokens.length - 1; index >= 0; index -= 1) {
    if (tokens[index].value === ")") depth += 1;
    else if (tokens[index].value === "(") {
      depth -= 1;
      if (depth === 0) {
        const header = tokens[index - 1];
        return !!header && header.kind === "word"
          && INVENTORY_REGEX_CONTROL_HEADER_WORDS.has(header.value);
      }
    }
  }
  return false;
}

function inventoryRegexCanStart(tokens) {
  if (tokens.length === 0) return true;
  const previous = tokens[tokens.length - 1];
  return INVENTORY_REGEX_PREFIX_SYMBOLS.has(previous.value)
    || previous.kind === "word" && INVENTORY_REGEX_PREFIX_WORDS.has(previous.value)
    || inventoryFollowsControlHeader(tokens);
}

function tokenizeInventoryJs(sourceValue, label) {
  const source = String(sourceValue || "");
  const tokens = [];
  let index = 0;
  function emit(kind, value, start, end) { tokens.push({ kind, value, start, end }); }
  while (index < source.length) {
    const current = source[index];
    const next = source[index + 1];
    if (current === "\uFEFF" || /\s/.test(current)) { index += 1; continue; }
    if (current === "/" && next === "/") {
      index += 2;
      while (index < source.length && source[index] !== "\r" && source[index] !== "\n") index += 1;
      continue;
    }
    if (current === "/" && next === "*") {
      const start = index;
      index += 2;
      while (index < source.length && !(source[index] === "*" && source[index + 1] === "/")) {
        index += 1;
      }
      if (index >= source.length) inventorySourceFail(
        "inventory JavaScript source contains an unterminated block comment", { label, start });
      index += 2;
      continue;
    }
    if (current === "/" && next !== "=" && inventoryRegexCanStart(tokens)) {
      const start = index;
      index += 1;
      let escaped = false;
      let inClass = false;
      let closed = false;
      while (index < source.length) {
        const value = source[index];
        if (value === "\r" || value === "\n") break;
        if (escaped) { escaped = false; index += 1; continue; }
        if (value === "\\") { escaped = true; index += 1; continue; }
        if (value === "[") { inClass = true; index += 1; continue; }
        if (value === "]" && inClass) { inClass = false; index += 1; continue; }
        if (value === "/" && !inClass) { index += 1; closed = true; break; }
        index += 1;
      }
      if (!closed) inventorySourceFail(
        "inventory JavaScript source contains an unterminated regular expression",
        { label, start });
      while (index < source.length && /[A-Za-z]/.test(source[index])) index += 1;
      emit("regex", source.slice(start, index), start, index);
      continue;
    }
    if (current === "'" || current === "\"" || current === "`") {
      const start = index;
      const quote = current;
      index += 1;
      let closed = false;
      while (index < source.length) {
        if (source[index] === "\\") {
          if (index + 1 >= source.length) break;
          index += 2;
          continue;
        }
        if (source[index] === quote) { index += 1; closed = true; break; }
        if (quote !== "`" && (source[index] === "\r" || source[index] === "\n")) break;
        index += 1;
      }
      if (!closed) inventorySourceFail(
        "inventory JavaScript source contains an unterminated string", { label, start });
      emit("string", source.slice(start, index), start, index);
      continue;
    }
    if (INVENTORY_JS_WORD_START_RE.test(current)) {
      const start = index;
      index += 1;
      while (index < source.length && INVENTORY_JS_WORD_PART_RE.test(source[index])) index += 1;
      emit("word", source.slice(start, index), start, index);
      continue;
    }
    const number = /^(?:0[xX][0-9A-Fa-f]+|0[bB][01]+|0[oO][0-7]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)/
      .exec(source.slice(index));
    if (number) {
      const start = index;
      index += number[0].length;
      emit("number", number[0], start, index);
      continue;
    }
    const symbol = INVENTORY_JS_MULTI_SYMBOLS.find((candidate) => source.startsWith(candidate, index))
      || current;
    emit("symbol", symbol, index, index + symbol.length);
    index += symbol.length;
  }
  return { source, tokens };
}

function sameInventoryToken(left, right) {
  return !!left && !!right && left.kind === right.kind && left.value === right.value;
}

function findInventoryTokenSequences(tokens, needleTokens) {
  const starts = [];
  if (!needleTokens.length || needleTokens.length > tokens.length) return starts;
  for (let start = 0; start <= tokens.length - needleTokens.length; start += 1) {
    let matches = true;
    for (let offset = 0; offset < needleTokens.length; offset += 1) {
      if (!sameInventoryToken(tokens[start + offset], needleTokens[offset])) {
        matches = false;
        break;
      }
    }
    if (matches) starts.push(start);
  }
  return starts;
}

function inventoryNeedleTokens(value, label) {
  const tokens = tokenizeInventoryJs(value, label).tokens;
  if (!tokens.length) inventorySourceFail("inventory semantic marker is empty", { label });
  return tokens;
}

function uniqueInventorySequence(tokens, needleValue, label, details) {
  const needleTokens = inventoryNeedleTokens(needleValue, label + ".needle");
  const starts = findInventoryTokenSequences(tokens, needleTokens);
  if (starts.length !== 1) inventorySourceFail(
    "inventory semantic marker is missing or ambiguous",
    Object.assign({ label, occurrenceCount: starts.length }, details || {}));
  return { start: starts[0], tokens: needleTokens };
}

function matchingInventoryToken(tokens, openIndex, openValue, closeValue, label) {
  if (!tokens[openIndex] || tokens[openIndex].value !== openValue) inventorySourceFail(
    "inventory semantic span lacks its structural opening token", { label, openValue });
  let depth = 0;
  for (let index = openIndex; index < tokens.length; index += 1) {
    if (tokens[index].value === openValue) depth += 1;
    else if (tokens[index].value === closeValue) {
      depth -= 1;
      if (depth === 0) return index;
      if (depth < 0) break;
    }
  }
  inventorySourceFail("inventory semantic span has an unclosed structural boundary",
    { label, openValue, closeValue });
}

function inventoryTokenScope(tokenSource, startToken, endToken, label, structure) {
  if (!tokenSource.tokens[startToken] || !tokenSource.tokens[endToken] || endToken < startToken) {
    inventorySourceFail("inventory semantic span is invalid", { label, startToken, endToken });
  }
  const tokens = tokenSource.tokens.slice(startToken, endToken + 1);
  return Object.assign({ label, tokens, globalTokenStart: startToken,
    globalTokenEnd: endToken,
    sourceStart: tokens[0].start, sourceEnd: tokens[tokens.length - 1].end },
  structure || {});
}

function namedInventoryCallableScope(tokenSource, functionName, parameters, label, details) {
  const match = uniqueInventorySequence(tokenSource.tokens,
    "function " + functionName + "(" + parameters + ") {", label, details);
  const bodyOpen = match.start + match.tokens.length - 1;
  const bodyClose = matchingInventoryToken(tokenSource.tokens, bodyOpen, "{", "}", label);
  return inventoryTokenScope(tokenSource, match.start, bodyClose, label,
    { kind: "named_callable", bodyOpenGlobal: bodyOpen, bodyCloseGlobal: bodyClose });
}

function assignedInventoryCallableScope(tokenSource, marker, parameters, label) {
  const match = uniqueInventorySequence(tokenSource.tokens,
    marker + " function(" + parameters + ") {", label);
  const bodyOpen = match.start + match.tokens.length - 1;
  const bodyClose = matchingInventoryToken(tokenSource.tokens, bodyOpen, "{", "}", label);
  if (!tokenSource.tokens[bodyClose + 1] || tokenSource.tokens[bodyClose + 1].value !== ";") {
    inventorySourceFail("inventory assigned callable does not end at its reviewed boundary",
      { id: "provider.followup.branch", label, bodyClose });
  }
  return inventoryTokenScope(tokenSource, match.start, bodyClose + 1, label,
    { kind: "assigned_callable", bodyOpenGlobal: bodyOpen, bodyCloseGlobal: bodyClose });
}

function assignedInventoryObjectScope(tokenSource, label) {
  const assignment = uniqueInventorySequence(tokenSource.tokens,
    "_inventoryCoordinator =", label + ".unique_assignment",
    { id: "consumer.coordinator.assignment" });
  const marker = uniqueInventorySequence(tokenSource.tokens,
    "var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({", label,
    { id: "consumer.coordinator.assignment" });
  if (assignment.start !== marker.start + 1) inventorySourceFail(
    "inventory coordinator constructor does not own the unique assignment",
    { label, id: "consumer.coordinator.assignment" });
  const objectOpen = marker.start + marker.tokens.length - 1;
  const objectClose = matchingInventoryToken(tokenSource.tokens, objectOpen, "{", "}", label);
  if (!tokenSource.tokens[objectClose + 1] || tokenSource.tokens[objectClose + 1].value !== ")"
      || !tokenSource.tokens[objectClose + 2]
      || tokenSource.tokens[objectClose + 2].value !== ";") inventorySourceFail(
    "inventory coordinator constructor assignment does not end at the reviewed object boundary",
    { id: "consumer.coordinator.assignment", label, objectClose });
  return inventoryTokenScope(tokenSource, marker.start, objectClose + 2, label,
    { kind: "assigned_object", bodyOpenGlobal: objectOpen, bodyCloseGlobal: objectClose });
}

function inventoryModuleScope(tokenSource, markerValue, label) {
  const marker = uniqueInventorySequence(tokenSource.tokens, markerValue, label);
  const bodyOpen = marker.start + marker.tokens.length - 1;
  const bodyClose = matchingInventoryToken(tokenSource.tokens, bodyOpen, "{", "}", label);
  return inventoryTokenScope(tokenSource, marker.start, bodyClose, label,
    { kind: "module_callable", bodyOpenGlobal: bodyOpen, bodyCloseGlobal: bodyClose });
}

function inventorySequenceWithinScope(scope, needleValue, label, details) {
  const match = uniqueInventorySequence(scope.tokens, needleValue, label, details);
  return { start: scope.globalTokenStart + match.start, tokens: match.tokens };
}

function objectFunctionInventoryScope(tokenSource, objectScope, markerValue, parameters,
  label, details) {
  const match = inventorySequenceWithinScope(objectScope,
    markerValue + " function(" + parameters + ") {", label, details);
  const bodyOpen = match.start + match.tokens.length - 1;
  const bodyClose = matchingInventoryToken(tokenSource.tokens, bodyOpen, "{", "}", label);
  return inventoryTokenScope(tokenSource, match.start, bodyClose, label,
    { kind: "object_function", bodyOpenGlobal: bodyOpen, bodyCloseGlobal: bodyClose });
}

function callbackInventoryScope(tokenSource, callableScope, markerValue, label, details) {
  const match = inventorySequenceWithinScope(callableScope, markerValue, label, details);
  const bodyOpen = match.start + match.tokens.length - 1;
  const bodyClose = matchingInventoryToken(tokenSource.tokens, bodyOpen, "{", "}", label);
  return inventoryTokenScope(tokenSource, match.start, bodyClose, label,
    { kind: "callback", bodyOpenGlobal: bodyOpen, bodyCloseGlobal: bodyClose });
}

function indexInventoryBraceParents(tokenSource, label) {
  const tokens = tokenSource.tokens;
  const parentOpenByToken = new Array(tokens.length).fill(null);
  const closeByOpen = new Map();
  const stack = [];
  tokens.forEach((token, index) => {
    parentOpenByToken[index] = stack.length > 0 ? stack[stack.length - 1] : null;
    if (token.value === "{") {
      stack.push(index);
      return;
    }
    if (token.value !== "}") return;
    if (stack.length === 0) inventorySourceFail(
      "inventory JavaScript source contains an unmatched closing brace", { label, start: token.start });
    closeByOpen.set(stack.pop(), index);
  });
  if (stack.length > 0) inventorySourceFail(
    "inventory JavaScript source contains an unclosed brace",
    { label, start: tokens[stack[stack.length - 1]].start });
  return { parentOpenByToken, closeByOpen };
}

function inventorySourceScopes(consumerSource, providerSource) {
  const sources = {
    consumer: tokenizeInventoryJs(consumerSource, "consumer"),
    provider: tokenizeInventoryJs(providerSource, "provider"),
  };
  const braceIndexes = {
    consumer: indexInventoryBraceParents(sources.consumer, "consumer"),
    provider: indexInventoryBraceParents(sources.provider, "provider"),
  };
  const moduleScopes = {
    consumer: inventoryModuleScope(sources.consumer, "var KShop = (function() {",
      "consumer.module"),
    provider: inventoryModuleScope(sources.provider,
      "})(typeof window !== 'undefined' ? window : globalThis, function() {",
      "provider.module"),
  };
  const scopes = {
    consumer: {
      inventoryCoordinator: assignedInventoryObjectScope(sources.consumer,
        "consumer.inventoryCoordinator"),
      requestInventory: namedInventoryCallableScope(sources.consumer, "requestInventory",
        "cmd, payload, callback", "consumer.requestInventory",
        { id: "consumer.request.transport" }),
      commitCheckout: namedInventoryCallableScope(sources.consumer, "commitCheckout", "token",
        "consumer.commitCheckout", { id: "consumer.checkout.begin" }),
      onClaim: namedInventoryCallableScope(sources.consumer, "onClaim", "e", "consumer.onClaim",
        { id: "consumer.claim.begin" }),
    },
    provider: {
      readPhysicalSurface: namedInventoryCallableScope(sources.provider,
        "readPhysicalInventorySurface", "request, options, callback",
        "provider.readPhysicalInventorySurface", { id: "provider.physical.sync_duplicate" }),
      requestNeedsAuthorityProjection: namedInventoryCallableScope(sources.provider,
        "requestNeedsAuthorityProjection", "request",
        "provider.requestNeedsAuthorityProjection", { id: "provider.constraint.classifier" }),
      projectPhysicalSurfaceToVisibleRequests: namedInventoryCallableScope(sources.provider,
        "projectPhysicalSurfaceToVisibleRequests", "surface, desiredRequests",
        "provider.projectPhysicalSurfaceToVisibleRequests",
        { id: "provider.local.rejects_constrained" }),
      authorityProjectionMatchesPhysicalSurface: namedInventoryCallableScope(sources.provider,
        "authorityProjectionMatchesPhysicalSurface",
        "response, surface, desiredRequests, currentWindows",
        "provider.authorityProjectionMatchesPhysicalSurface",
        { id: "provider.coherence.session" }),
      refreshPhysicalSurface: assignedInventoryCallableScope(sources.provider,
        "InventoryCoordinator.prototype._refreshPhysicalSurfaceWhileOwned =",
        "callback, operation",
        "provider.refreshPhysicalSurface"),
    },
  };
  const auxiliaryScopes = {
    inventoryReader: objectFunctionInventoryScope(sources.consumer,
      scopes.consumer.inventoryCoordinator, "readPhysicalSurface:", "isActive, callback",
      "consumer.inventoryReader", { id: "consumer.reader.owner" }),
    checkoutCallback: callbackInventoryScope(sources.consumer,
      scopes.consumer.commitCheckout, "if (!_writeCoordinator.checkout(token, function(resp) {",
      "consumer.checkoutCallback", { id: "consumer.checkout.complete" }),
    claimCallback: callbackInventoryScope(sources.consumer,
      scopes.consumer.onClaim, "if (!_writeCoordinator.claim(pidx, function(resp) {",
      "consumer.claimCallback", { id: "consumer.claim.complete" }),
  };
  return { sources, braceIndexes, moduleScopes, scopes, auxiliaryScopes,
  };
}

function inspectInventorySourceStructure(indexed, anchorsById) {
  const assertions = [];
  function requireParent(source, tokenIndex, expectedParent, id, subject) {
    const actualParent = indexed.braceIndexes[source].parentOpenByToken[tokenIndex];
    if (actualParent !== expectedParent) inventorySourceFail(
      "inventory semantic element is not at its required direct structural depth",
      { id, subject, source, tokenIndex, expectedParent, actualParent });
    assertions.push({ id: "structure." + subject, source, subject,
      tokenIndex, parentOpenToken: actualParent });
  }
  function requireFirstBodyToken(source, tokenIndex, bodyOpen, id, subject) {
    if (tokenIndex !== bodyOpen + 1) inventorySourceFail(
      "inventory semantic statement is not the callable's direct first statement",
      { id, subject, source, tokenIndex, expectedTokenIndex: bodyOpen + 1 });
    assertions.push({ id: "execution." + subject + ".first_statement", source, subject,
      tokenIndex, bodyOpenToken: bodyOpen });
  }
  function requirePrecedingToken(source, tokenIndex, expectedValue, id, subject) {
    const previous = indexed.sources[source].tokens[tokenIndex - 1];
    if (!previous || previous.value !== expectedValue) inventorySourceFail(
      "inventory semantic statement is outside its reviewed direct execution position",
      { id, subject, source, tokenIndex, expectedPreviousToken: expectedValue,
        actualPreviousToken: previous && previous.value });
    assertions.push({ id: "execution." + subject + ".predecessor", source, subject,
      tokenIndex, previousToken: expectedValue });
  }
  function requireDirectTokenCounts(source, parentOpen, startToken, endToken,
    expectedCounts, id, subject) {
    const counts = {};
    Object.keys(expectedCounts).forEach((value) => { counts[value] = 0; });
    const tokens = indexed.sources[source].tokens;
    for (let tokenIndex = startToken; tokenIndex < endToken; tokenIndex += 1) {
      if (indexed.braceIndexes[source].parentOpenByToken[tokenIndex] !== parentOpen) continue;
      if (Object.prototype.hasOwnProperty.call(counts, tokens[tokenIndex].value)) {
        counts[tokens[tokenIndex].value] += 1;
      }
    }
    if (canonicalJson(counts) !== canonicalJson(expectedCounts)) inventorySourceFail(
      "inventory semantic path contains unexpected direct control flow",
      { id, subject, source, startToken, endToken, expectedCounts, actualCounts: counts });
    assertions.push({ id: "execution." + subject + ".direct_token_counts", source, subject,
      parentOpenToken: parentOpen, startToken, endToken, tokenCounts: counts });
  }
  function anchor(id) {
    const value = anchorsById.get(id);
    if (!value) inventorySourceFail("inventory structural assertion lacks its semantic anchor",
      { id });
    return value;
  }
  function directSequence(source, scope, needleValue, id, subject) {
    const needleTokens = inventoryNeedleTokens(needleValue, subject);
    const starts = findInventoryTokenSequences(scope.tokens, needleTokens)
      .map((start) => scope.globalTokenStart + start)
      .filter((start) => indexed.braceIndexes[source].parentOpenByToken[start]
        === scope.bodyOpenGlobal);
    if (starts.length !== 1) inventorySourceFail(
      "inventory semantic direct statement is missing or ambiguous",
      { id, subject, source, occurrenceCount: starts.length });
    return starts[0];
  }
  function requireReviewedCallableTokens(source, scope, expectedSha256, id, subject) {
    const actualSha256 = sha256Text(canonicalJson(scope.tokens.map((token) =>
      [token.kind, token.value])));
    if (actualSha256 !== expectedSha256) inventorySourceFail(
      "inventory reviewed callable token body has drifted",
      { id, subject, source, expectedSha256, actualSha256 });
    assertions.push({ id: "execution." + subject + ".reviewed_token_sha256",
      source, subject, tokenCount: scope.tokens.length, tokenSha256: actualSha256 });
  }
  function requireUniqueNamedBinding(source, scope, identifier, expectedOccurrenceCount,
    id, subject) {
    const tokens = indexed.sources[source].tokens;
    const declarationToken = scope.globalTokenStart + 1;
    const declarations = [];
    const writes = [];
    let occurrences = 0;
    const assignmentOperators = new Set([
      "=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", ">>>=", "&=", "|=", "^=",
      "**=", "&&=", "||=", "??=",
    ]);
    for (let index = 0; index < tokens.length; index += 1) {
      if (tokens[index].value !== identifier) continue;
      occurrences += 1;
      const previous = tokens[index - 1];
      const next = tokens[index + 1];
      if (previous && previous.value === "function") declarations.push(index);
      if (previous && (previous.value === "var" || previous.value === "let"
          || previous.value === "const" || previous.value === "class"
          || previous.value === "++" || previous.value === "--")
          || next && (assignmentOperators.has(next.value)
            || next.value === "++" || next.value === "--")) writes.push(index);
    }
    if (declarations.length !== 1 || declarations[0] !== declarationToken
        || writes.length !== 0 || occurrences !== expectedOccurrenceCount) inventorySourceFail(
      "inventory callable binding is declared, written, or referenced outside its reviewed set",
      { id, subject, source, identifier, declarationToken,
        declarationTokens: declarations, writeTokens: writes,
        expectedOccurrenceCount, actualOccurrenceCount: occurrences });
    assertions.push({ id: "execution." + subject + ".unique_binding",
      source, subject, identifier, declarationToken, occurrenceCount: occurrences });
  }
  function requireNoDynamicCode(source, id, subject) {
    const forbidden = indexed.sources[source].tokens.filter((token) =>
      token.kind === "word" && (token.value === "eval" || token.value === "Function"));
    if (forbidden.length !== 0) inventorySourceFail(
      "inventory authority source contains dynamic code construction",
      { id, subject, source, forbidden: forbidden.map((token) =>
        ({ value: token.value, start: token.start })) });
    assertions.push({ id: "execution." + subject + ".no_dynamic_code",
      source, subject, forbiddenTokenCount: 0 });
  }

  requireParent("consumer", indexed.moduleScopes.consumer.bodyOpenGlobal, null,
    "consumer.coordinator.assignment", "consumer.module_body");
  requireParent("provider", indexed.moduleScopes.provider.bodyOpenGlobal, null,
    "provider.constraint.classifier", "provider.module_body");
  requireNoDynamicCode("consumer", "consumer.coordinator.request", "consumer.module");
  requireNoDynamicCode("provider", "provider.constraint.classifier", "provider.module");

  [
    ["consumer", indexed.scopes.consumer.inventoryCoordinator,
      indexed.moduleScopes.consumer.bodyOpenGlobal, "consumer.coordinator.assignment",
      "consumer.inventoryCoordinator"],
    ["consumer", indexed.scopes.consumer.requestInventory,
      indexed.moduleScopes.consumer.bodyOpenGlobal, "consumer.request.transport",
      "consumer.requestInventory"],
    ["consumer", indexed.scopes.consumer.commitCheckout,
      indexed.moduleScopes.consumer.bodyOpenGlobal, "consumer.checkout.begin",
      "consumer.commitCheckout"],
    ["consumer", indexed.scopes.consumer.onClaim,
      indexed.moduleScopes.consumer.bodyOpenGlobal, "consumer.claim.begin", "consumer.onClaim"],
    ["provider", indexed.scopes.provider.readPhysicalSurface,
      indexed.moduleScopes.provider.bodyOpenGlobal, "provider.physical.sync_duplicate",
      "provider.readPhysicalSurface"],
    ["provider", indexed.scopes.provider.requestNeedsAuthorityProjection,
      indexed.moduleScopes.provider.bodyOpenGlobal, "provider.constraint.classifier",
      "provider.requestNeedsAuthorityProjection"],
    ["provider", indexed.scopes.provider.projectPhysicalSurfaceToVisibleRequests,
      indexed.moduleScopes.provider.bodyOpenGlobal, "provider.local.rejects_constrained",
      "provider.projectPhysicalSurfaceToVisibleRequests"],
    ["provider", indexed.scopes.provider.authorityProjectionMatchesPhysicalSurface,
      indexed.moduleScopes.provider.bodyOpenGlobal, "provider.coherence.session",
      "provider.authorityProjectionMatchesPhysicalSurface"],
    ["provider", indexed.scopes.provider.refreshPhysicalSurface,
      indexed.moduleScopes.provider.bodyOpenGlobal, "provider.followup.branch",
      "provider.refreshPhysicalSurface"],
  ].forEach((rule) => requireParent(rule[0], rule[1].globalTokenStart,
    rule[2], rule[3], rule[4]));

  [
    ["consumer", indexed.scopes.consumer.commitCheckout,
      "consumer.checkout.begin", "consumer.commitCheckout.declaration"],
    ["consumer", indexed.scopes.consumer.requestInventory,
      "consumer.request.transport", "consumer.requestInventory.declaration"],
    ["consumer", indexed.scopes.consumer.onClaim,
      "consumer.claim.begin", "consumer.onClaim.declaration"],
    ["provider", indexed.scopes.provider.readPhysicalSurface,
      "provider.physical.sync_duplicate", "provider.readPhysicalSurface.declaration"],
    ["provider", indexed.scopes.provider.requestNeedsAuthorityProjection,
      "provider.constraint.classifier", "provider.requestNeedsAuthorityProjection.declaration"],
    ["provider", indexed.scopes.provider.projectPhysicalSurfaceToVisibleRequests,
      "provider.local.rejects_constrained",
      "provider.projectPhysicalSurfaceToVisibleRequests.declaration"],
    ["provider", indexed.scopes.provider.authorityProjectionMatchesPhysicalSurface,
      "provider.coherence.session",
      "provider.authorityProjectionMatchesPhysicalSurface.declaration"],
  ].forEach((rule) => requirePrecedingToken(rule[0], rule[1].globalTokenStart,
    "}", rule[2], rule[3]));

  requireUniqueNamedBinding("consumer", indexed.scopes.consumer.requestInventory,
    "requestInventory", 5, "consumer.request.transport", "consumer.requestInventory");
  requireUniqueNamedBinding("provider", indexed.scopes.provider.requestNeedsAuthorityProjection,
    "requestNeedsAuthorityProjection", 4, "provider.constraint.classifier",
    "provider.requestNeedsAuthorityProjection");

  requireParent("consumer", indexed.auxiliaryScopes.inventoryReader.globalTokenStart,
    indexed.scopes.consumer.inventoryCoordinator.bodyOpenGlobal,
    "consumer.reader.owner", "consumer.inventoryReader");
  requireParent("consumer", indexed.auxiliaryScopes.checkoutCallback.globalTokenStart,
    indexed.scopes.consumer.commitCheckout.bodyOpenGlobal,
    "consumer.checkout.complete", "consumer.checkoutCallback");
  requireParent("consumer", indexed.auxiliaryScopes.claimCallback.globalTokenStart,
    indexed.scopes.consumer.onClaim.bodyOpenGlobal,
    "consumer.claim.complete", "consumer.claimCallback");

  const directParents = [
    ["consumer.coordinator.assignment", indexed.moduleScopes.consumer.bodyOpenGlobal,
      "consumer.coordinator.assignment"],
    ["consumer.coordinator.request", indexed.scopes.consumer.inventoryCoordinator.bodyOpenGlobal,
      "consumer.coordinator.request"],
    ["consumer.request.transport", indexed.scopes.consumer.requestInventory.bodyOpenGlobal,
      "consumer.request.transport"],
    ["consumer.reader.owner", indexed.scopes.consumer.inventoryCoordinator.bodyOpenGlobal,
      "consumer.reader.owner"],
    ["consumer.checkout.begin", indexed.scopes.consumer.commitCheckout.bodyOpenGlobal,
      "consumer.checkout.begin"],
    ["consumer.checkout.complete", indexed.auxiliaryScopes.checkoutCallback.bodyOpenGlobal,
      "consumer.checkout.complete"],
    ["consumer.claim.begin", indexed.scopes.consumer.onClaim.bodyOpenGlobal,
      "consumer.claim.begin"],
    ["consumer.claim.complete", indexed.auxiliaryScopes.claimCallback.bodyOpenGlobal,
      "consumer.claim.complete"],
    ["provider.constraint.classifier",
      indexed.scopes.provider.requestNeedsAuthorityProjection.bodyOpenGlobal,
      "provider.constraint.classifier"],
  ];
  directParents.forEach((rule) => requireParent(anchorsById.get(rule[0]).source,
    anchor(rule[0]).sourceTokenStart, rule[1], rule[2], "anchor." + rule[0]));

  requireFirstBodyToken("consumer", anchor("consumer.checkout.begin").sourceTokenStart,
    indexed.scopes.consumer.commitCheckout.bodyOpenGlobal,
    "consumer.checkout.begin", "consumer.checkout.begin");
  requireFirstBodyToken("consumer", anchor("consumer.request.transport").sourceTokenStart,
    indexed.scopes.consumer.requestInventory.bodyOpenGlobal,
    "consumer.request.transport", "consumer.request.transport");
  requireFirstBodyToken("provider", anchor("provider.constraint.classifier").sourceTokenStart,
    indexed.scopes.provider.requestNeedsAuthorityProjection.bodyOpenGlobal,
    "provider.constraint.classifier", "provider.constraint.classifier");

  const readerReturn = inventorySequenceWithinScope(indexed.auxiliaryScopes.inventoryReader,
    "return InventoryRuntime.readPhysicalInventorySurface(requestInventory, "
      + "{isActive:isActive, expectedPanel:'kshop', expectedPanelInstanceId:_panelInstanceId}, "
      + "callback);",
    "consumer.inventoryReader.return", { id: "consumer.reader.owner" });
  requireParent("consumer", readerReturn.start,
    indexed.auxiliaryScopes.inventoryReader.bodyOpenGlobal,
    "consumer.reader.owner", "consumer.inventoryReader.return");
  requireFirstBodyToken("consumer", readerReturn.start,
    indexed.auxiliaryScopes.inventoryReader.bodyOpenGlobal,
    "consumer.reader.owner", "consumer.inventoryReader.return");

  requirePrecedingToken("consumer", anchor("consumer.checkout.complete").sourceTokenStart,
    "}", "consumer.checkout.complete", "consumer.checkout.complete");
  requirePrecedingToken("consumer", anchor("consumer.claim.complete").sourceTokenStart,
    ";", "consumer.claim.complete", "consumer.claim.complete");

  const checkoutGuard = directSequence("consumer", indexed.auxiliaryScopes.checkoutCallback,
    "if (!isKShopOpen()) return;", "consumer.checkout.complete",
    "consumer.checkoutCallback.guard");
  const claimGuard = directSequence("consumer", indexed.auxiliaryScopes.claimCallback,
    "if (!isKShopOpen()) return;", "consumer.claim.complete",
    "consumer.claimCallback.guard");
  requireFirstBodyToken("consumer", checkoutGuard,
    indexed.auxiliaryScopes.checkoutCallback.bodyOpenGlobal,
    "consumer.checkout.complete", "consumer.checkoutCallback.guard");
  requireFirstBodyToken("consumer", claimGuard,
    indexed.auxiliaryScopes.claimCallback.bodyOpenGlobal,
    "consumer.claim.complete", "consumer.claimCallback.guard");

  const claimBeforeBeginCounts = {
    return: 0, throw: 0, break: 0, continue: 0,
    while: 0, for: 0, do: 0, switch: 0, if: 1, try: 0, with: 0,
    function: 0, "?": 0, "&&": 0, "||": 0, "??": 0,
  };
  const beforeRequestCounts = {
    return: 0, throw: 0, break: 0, continue: 0,
    while: 0, for: 0, do: 0, switch: 0, if: 1, try: 0, with: 0,
    function: 0, "?": 0, "&&": 0, "||": 0, "??": 0,
  };
  requireDirectTokenCounts("consumer", indexed.scopes.consumer.onClaim.bodyOpenGlobal,
    indexed.scopes.consumer.onClaim.bodyOpenGlobal + 1,
    anchor("consumer.claim.begin").sourceTokenStart,
    claimBeforeBeginCounts, "consumer.claim.begin", "consumer.claim.before_begin");
  requireDirectTokenCounts("consumer", indexed.scopes.consumer.commitCheckout.bodyOpenGlobal,
    anchor("consumer.checkout.begin").sourceTokenStart
      + anchor("consumer.checkout.begin").tokenCount,
    indexed.auxiliaryScopes.checkoutCallback.globalTokenStart,
    beforeRequestCounts, "consumer.checkout.complete", "consumer.checkout.before_request");
  requireDirectTokenCounts("consumer", indexed.scopes.consumer.onClaim.bodyOpenGlobal,
    anchor("consumer.claim.begin").sourceTokenStart + anchor("consumer.claim.begin").tokenCount,
    indexed.auxiliaryScopes.claimCallback.globalTokenStart,
    beforeRequestCounts, "consumer.claim.complete", "consumer.claim.before_request");
  const checkoutCallbackPathCounts = {
    return: 1, throw: 0, break: 0, continue: 0,
    while: 0, for: 0, do: 0, switch: 0, if: 2, try: 0, with: 0,
    function: 0, "?": 0, "&&": 0, "||": 1, "??": 0,
  };
  const claimCallbackPathCounts = {
    return: 1, throw: 0, break: 0, continue: 0,
    while: 0, for: 0, do: 0, switch: 0, if: 1, try: 0, with: 0,
    function: 0, "?": 0, "&&": 2, "||": 1, "??": 0,
  };
  requireDirectTokenCounts("consumer", indexed.auxiliaryScopes.checkoutCallback.bodyOpenGlobal,
    indexed.auxiliaryScopes.checkoutCallback.bodyOpenGlobal + 1,
    anchor("consumer.checkout.complete").sourceTokenStart,
    checkoutCallbackPathCounts,
    "consumer.checkout.complete", "consumer.checkout.before_complete");
  requireDirectTokenCounts("consumer", indexed.auxiliaryScopes.claimCallback.bodyOpenGlobal,
    indexed.auxiliaryScopes.claimCallback.bodyOpenGlobal + 1,
    anchor("consumer.claim.complete").sourceTokenStart,
    claimCallbackPathCounts,
    "consumer.claim.complete", "consumer.claim.before_complete");
  requireReviewedCallableTokens("consumer", indexed.scopes.consumer.inventoryCoordinator,
    REVIEWED_INVENTORY_CALLABLE_TOKEN_SHA256["consumer.inventoryCoordinator"],
    "consumer.coordinator.request", "consumer.inventoryCoordinator");
  requireReviewedCallableTokens("consumer", indexed.scopes.consumer.commitCheckout,
    REVIEWED_INVENTORY_CALLABLE_TOKEN_SHA256["consumer.commitCheckout"],
    "consumer.checkout.complete", "consumer.commitCheckout");
  requireReviewedCallableTokens("consumer", indexed.scopes.consumer.onClaim,
    REVIEWED_INVENTORY_CALLABLE_TOKEN_SHA256["consumer.onClaim"],
    "consumer.claim.complete", "consumer.onClaim");
  return assertions;
}

function inspectInventorySurfaceSourceContract(consumerSource, providerSource) {
  const rawSources = { consumer: String(consumerSource || ""), provider: String(providerSource || "") };
  const indexed = inventorySourceScopes(rawSources.consumer, rawSources.provider);
  const anchors = INVENTORY_SURFACE_SOURCE_ANCHORS.map((anchor) => {
    const scope = indexed.scopes[anchor.source][anchor.scope];
    const needleTokens = inventoryNeedleTokens(anchor.needle, anchor.id);
    const starts = findInventoryTokenSequences(scope.tokens, needleTokens);
    if (starts.length !== 1) inventorySourceFail(
      "inventory semantic anchor is missing or ambiguous", { id: anchor.id,
        source: anchor.source, scope: anchor.scope, occurrenceCount: starts.length });
    const tokenStart = starts[0];
    const first = scope.tokens[tokenStart];
    const last = scope.tokens[tokenStart + needleTokens.length - 1];
    return { id: anchor.id, source: anchor.source, scope: anchor.scope,
      scopeTokenStart: tokenStart,
      sourceTokenStart: scope.globalTokenStart + tokenStart,
      sourceStart: first.start, sourceEnd: last.end,
      tokenCount: needleTokens.length,
      anchorSha256: sha256Text(canonicalJson(needleTokens.map((token) =>
        [token.kind, token.value]))) };
  });
  const anchorsById = new Map(anchors.map((anchor) => [anchor.id, anchor]));
  const orderAssertions = INVENTORY_SURFACE_SOURCE_ORDER_GROUPS.map((group) => {
    const ordered = group.anchorIds.map((id) => anchorsById.get(id));
    if (ordered.some((anchor) => !anchor
        || anchor.source !== group.source || anchor.scope !== group.scope)) inventorySourceFail(
      "inventory semantic order group does not bind one exact scope", { id: group.id,
        anchorIds: group.anchorIds });
    for (let index = 1; index < ordered.length; index += 1) {
      if (ordered[index - 1].scopeTokenStart >= ordered[index].scopeTokenStart) inventorySourceFail(
        "inventory semantic calls are outside the required order", { id: group.id,
          anchorIds: group.anchorIds });
    }
    return { id: group.id, source: group.source, scope: group.scope,
      anchorIds: group.anchorIds.slice(),
      sourceTokenStarts: ordered.map((anchor) => anchor.sourceTokenStart) };
  });
  const structureAssertions = inspectInventorySourceStructure(indexed, anchorsById);
  const scopeSpans = [];
  ["consumer", "provider"].forEach((source) => {
    Object.keys(indexed.scopes[source]).sort().forEach((scopeName) => {
      const scope = indexed.scopes[source][scopeName];
      scopeSpans.push({ source, scope: scopeName, sourceStart: scope.sourceStart,
        sourceEnd: scope.sourceEnd, tokenCount: scope.tokens.length,
        bodyOpenToken: scope.bodyOpenGlobal, bodyCloseToken: scope.bodyCloseGlobal,
        tokenSha256: sha256Text(canonicalJson(scope.tokens.map((token) =>
          [token.kind, token.value]))) });
    });
  });
  const value = {
    schema: INVENTORY_SURFACE_SOURCE_SCHEMA,
    semanticAnchorVersion: INVENTORY_SURFACE_ANCHOR_VERSION,
    tokenCanonicalization: "js-comment-string-regex-excluding-structural-token-stream.v5",
    sources: [
      { role: "consumer", relativePath: KSHOP_SOURCE_PATH,
        bytes: Buffer.byteLength(rawSources.consumer, "utf8"),
        sha256: sha256Text(rawSources.consumer) },
      { role: "provider", relativePath: INVENTORY_RUNTIME_PATH,
        bytes: Buffer.byteLength(rawSources.provider, "utf8"),
        sha256: sha256Text(rawSources.provider) },
    ],
    scopeSpans,
    anchors,
    structureAssertions,
    orderAssertions,
    invariants: INVENTORY_SURFACE_INVARIANTS.slice(),
  };
  value.contractSha256 = sha256Text(canonicalJson(value));
  return value;
}

function captureInventoryPhysicalSurfaceContract(root) {
  const consumer = readExactText(root, KSHOP_SOURCE_PATH);
  const provider = readExactText(root, INVENTORY_RUNTIME_PATH);
  const value = {
    schema: INVENTORY_SURFACE_CONTRACT_SCHEMA,
    owner: { expectedPanel: "kshop", expectedPanelInstanceId: "current_panel_instance" },
    refresh: {
      completePhysicalSurface: { maximumBatchCount: 3,
        order: "bag_50_plus_battle_windows_0_100_200" },
      constrainedProjection: { atMaximumPhysicalSurfaceBatchOrdinal: 4,
        request: "captured_visible_requests_exact_and_not_rewritten",
        ownerRelease: "after_exact_visible_response_or_single_failure" },
      successReceipt: "first_one_to_three_complete_physical_batches_only",
    },
    consumer: consumer.entry,
    provider: provider.entry,
    sourceContract: inspectInventorySurfaceSourceContract(consumer.text, provider.text),
  };
  value.contractSha256 = sha256Text(canonicalJson(value));
  return value;
}

function verifyInventoryPhysicalSurfaceContract(root, contract) {
  const unsigned = Object.assign({}, contract);
  delete unsigned.contractSha256;
  if (!contract || contract.schema !== INVENTORY_SURFACE_CONTRACT_SCHEMA
      || !contract.sourceContract
      || contract.sourceContract.schema !== INVENTORY_SURFACE_SOURCE_SCHEMA
      || contract.contractSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("production_inventory_surface_contract_invalid", "production_closure",
      "KShop inventory semantic contract is malformed or detached");
  }
  const current = captureInventoryPhysicalSurfaceContract(root);
  if (canonicalJson(current) !== canonicalJson(contract)) {
    fail("production_inventory_surface_current_tree_mismatch", "production_closure",
      "KShop inventory semantic contract differs from the current canonical tree");
  }
  return contract;
}

const AS2_WORD_START_RE = /^[\p{L}\p{Nl}_$]$/u;
const AS2_WORD_PART_RE = /^[\p{L}\p{Nl}\p{Nd}\p{Mn}\p{Mc}\p{Pc}_$]$/u;
const AS2_MULTI_SYMBOLS = Object.freeze([
  ">>>=", "===", "!==", ">>>", "<<=", ">>=", "==", "!=", "<=", ">=", "++", "--",
  "&&", "||", "+=", "-=", "*=", "/=", "%=", "<<", ">>", "&=", "|=", "^=", "::", "..",
]);
const AS2_MEMBER_MODIFIERS = new Set([
  "public", "private", "protected", "internal", "static", "final", "override", "native",
]);

function as2LexicalFail(relativePath, message, details) {
  fail("production_itemutil_delivery_source_invalid", "production_closure", message,
    Object.assign({ relativePath }, details || {}));
}

function tokenizeAs2(sourceValue, relativePath) {
  const source = String(sourceValue);
  const tokens = [];
  let index = 0;
  let lineBreakBefore = false;
  function emit(kind, value, start, end) {
    tokens.push({ kind, value, lineBreakBefore, start, end });
    lineBreakBefore = false;
  }
  while (index < source.length) {
    const current = source[index];
    const next = source[index + 1];
    if (/\s/.test(current)) {
      if (current === "\r" || current === "\n") lineBreakBefore = true;
      index += 1;
      continue;
    }
    if (current === "/" && next === "/") {
      index += 2;
      while (index < source.length && source[index] !== "\r" && source[index] !== "\n") index += 1;
      continue;
    }
    if (current === "/" && next === "*") {
      const commentStart = index;
      index += 2;
      while (index < source.length && !(source[index] === "*" && source[index + 1] === "/")) {
        if (source[index] === "\r" || source[index] === "\n") lineBreakBefore = true;
        index += 1;
      }
      if (index >= source.length) as2LexicalFail(relativePath,
        "AS2 delivery source contains an unterminated block comment", { start: commentStart });
      index += 2;
      continue;
    }
    if (current === "\"" || current === "'") {
      const start = index;
      const quote = current;
      index += 1;
      let closed = false;
      while (index < source.length) {
        if (source[index] === "\\") {
          if (index + 1 >= source.length) break;
          index += 2;
          continue;
        }
        if (source[index] === quote) { index += 1; closed = true; break; }
        if (source[index] === "\r" || source[index] === "\n") break;
        index += 1;
      }
      if (!closed) as2LexicalFail(relativePath,
        "AS2 delivery source contains an unterminated string", { start });
      emit("string", source.slice(start, index), start, index);
      continue;
    }
    if (AS2_WORD_START_RE.test(current)) {
      const start = index;
      index += 1;
      while (index < source.length && AS2_WORD_PART_RE.test(source[index])) index += 1;
      emit("word", source.slice(start, index), start, index);
      continue;
    }
    const number = /^(?:0[xX][0-9A-Fa-f]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)/
      .exec(source.slice(index));
    if (number) {
      const start = index;
      index += number[0].length;
      emit("number", number[0], start, index);
      continue;
    }
    const symbol = AS2_MULTI_SYMBOLS.find((candidate) => source.startsWith(candidate, index))
      || current;
    emit("symbol", symbol, index, index + symbol.length);
    index += symbol.length;
  }
  return tokens;
}

function matchingAs2Token(tokens, openIndex, openValue, closeValue, relativePath, functionName) {
  if (!tokens[openIndex] || tokens[openIndex].value !== openValue) as2LexicalFail(relativePath,
    "AS2 delivery function lacks its structural opening token", { functionName, openValue });
  let depth = 0;
  for (let index = openIndex; index < tokens.length; index += 1) {
    if (tokens[index].value === openValue) depth += 1;
    else if (tokens[index].value === closeValue) {
      depth -= 1;
      if (depth === 0) return index;
      if (depth < 0) break;
    }
  }
  as2LexicalFail(relativePath, "AS2 delivery function has an unclosed structural boundary", {
    functionName, openValue, closeValue,
  });
}

function loadAs2TokenSource(root, relativePath, cache) {
  if (cache.has(relativePath)) return cache.get(relativePath);
  const exact = readExactText(root, relativePath);
  const value = { source: exact.text, tokens: tokenizeAs2(exact.text, relativePath) };
  cache.set(relativePath, value);
  return value;
}

function indexAs2BraceParents(tokens, relativePath) {
  const parentOpenByToken = new Array(tokens.length).fill(null);
  const closeByOpen = new Map();
  const stack = [];
  tokens.forEach((token, index) => {
    parentOpenByToken[index] = stack.length > 0 ? stack[stack.length - 1] : null;
    if (token.value === "{") {
      stack.push(index);
      return;
    }
    if (token.value !== "}") return;
    if (stack.length === 0) as2LexicalFail(relativePath,
      "AS2 delivery source contains an unmatched closing brace", { start: token.start });
    closeByOpen.set(stack.pop(), index);
  });
  if (stack.length > 0) as2LexicalFail(relativePath,
    "AS2 delivery source contains an unclosed brace", {
      start: tokens[stack[stack.length - 1]].start,
    });
  return { parentOpenByToken, closeByOpen };
}

function as2QualifiedClassName(tokens, classIndex) {
  let cursor = classIndex + 1;
  if (!tokens[cursor] || tokens[cursor].kind !== "word") return null;
  let name = tokens[cursor].value;
  cursor += 1;
  while (tokens[cursor] && tokens[cursor].value === "."
      && tokens[cursor + 1] && tokens[cursor + 1].kind === "word") {
    name += "." + tokens[cursor + 1].value;
    cursor += 2;
  }
  return { name, signatureEnd: cursor };
}

function targetAs2ClassBody(tokens, relativePath, braceIndex) {
  const expectedClassName = AS2_TARGET_CLASSES[relativePath];
  if (!expectedClassName) as2LexicalFail(relativePath,
    "AS2 delivery source has no exact target class contract");
  const declarations = [];
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index].kind !== "word" || tokens[index].value !== "class") continue;
    const qualified = as2QualifiedClassName(tokens, index);
    if (!qualified || qualified.name !== expectedClassName) continue;
    let bodyOpen = qualified.signatureEnd;
    while (bodyOpen < tokens.length && tokens[bodyOpen].value !== "{") {
      if ([";", "}", "function", "class"].includes(tokens[bodyOpen].value)) {
        as2LexicalFail(relativePath, "AS2 target class declaration escaped its boundary", {
          expectedClassName, token: tokens[bodyOpen].value,
        });
      }
      bodyOpen += 1;
    }
    if (bodyOpen >= tokens.length || !braceIndex.closeByOpen.has(bodyOpen)) {
      as2LexicalFail(relativePath, "AS2 target class lacks one structural body", {
        expectedClassName,
      });
    }
    declarations.push({ classIndex: index, bodyOpen,
      bodyClose: braceIndex.closeByOpen.get(bodyOpen) });
  }
  if (declarations.length !== 1) as2LexicalFail(relativePath,
    "AS2 delivery source lacks one exact target class declaration", {
      expectedClassName, count: declarations.length,
    });
  const declaration = declarations[0];
  if (braceIndex.parentOpenByToken[declaration.classIndex] !== null
      || braceIndex.parentOpenByToken[declaration.bodyOpen] !== null) {
    as2LexicalFail(relativePath, "AS2 target class is not a file-level declaration", {
      expectedClassName, start: tokens[declaration.classIndex].start,
    });
  }
  return declaration;
}

function extractAs2FunctionFromCache(root, relativePath, functionName, cache) {
  const loaded = loadAs2TokenSource(root, relativePath, cache);
  const { source, tokens } = loaded;
  const braceIndex = indexAs2BraceParents(tokens, relativePath);
  const targetClass = targetAs2ClassBody(tokens, relativePath, braceIndex);
  const declarations = [];
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index].kind !== "word" || tokens[index].value !== "function"
        || !tokens[index + 1] || tokens[index + 1].value !== functionName) continue;
    if (tokens[index + 1].kind !== "word" || !tokens[index + 2]
        || tokens[index + 2].value !== "(") {
      as2LexicalFail(relativePath, "AS2 delivery function declaration is malformed", {
        functionName, start: tokens[index].start,
      });
    }
    declarations.push(index);
  }
  if (declarations.length !== 1) as2LexicalFail(relativePath,
    "AS2 delivery source lacks one exact structural function declaration", {
      functionName, count: declarations.length,
    });
  const functionIndex = declarations[0];
  const parameterOpen = functionIndex + 2;
  const parameterClose = matchingAs2Token(tokens, parameterOpen, "(", ")",
    relativePath, functionName);
  let bodyOpen = parameterClose + 1;
  while (bodyOpen < tokens.length && tokens[bodyOpen].value !== "{") {
    if ([";", "}", "function"].includes(tokens[bodyOpen].value)) as2LexicalFail(relativePath,
      "AS2 delivery function return declaration escaped its structural boundary", {
        functionName, token: tokens[bodyOpen].value,
      });
    bodyOpen += 1;
  }
  if (bodyOpen >= tokens.length) as2LexicalFail(relativePath,
    "AS2 delivery function lacks one structural body", { functionName });
  const bodyClose = matchingAs2Token(tokens, bodyOpen, "{", "}", relativePath, functionName);
  const nested = tokens.slice(bodyOpen + 1, bodyClose).find((token) =>
    token.kind === "word" && token.value === "function");
  if (nested) as2LexicalFail(relativePath,
    "AS2 delivery function contains a nested function boundary", {
      functionName, nestedAt: nested.start,
    });
  let memberStart = functionIndex;
  while (memberStart > 0 && tokens[memberStart - 1].kind === "word"
      && AS2_MEMBER_MODIFIERS.has(tokens[memberStart - 1].value)) memberStart -= 1;
  [memberStart, functionIndex, parameterOpen, bodyOpen].forEach((tokenIndex) => {
    if (tokenIndex <= targetClass.bodyOpen || tokenIndex >= targetClass.bodyClose
        || braceIndex.parentOpenByToken[tokenIndex] !== targetClass.bodyOpen) {
      as2LexicalFail(relativePath,
        "AS2 delivery function is not a direct member of its exact target class", {
          functionName, expectedClassName: AS2_TARGET_CLASSES[relativePath],
          start: tokens[tokenIndex].start,
        });
    }
  });
  const functionTokens = tokens.slice(memberStart, bodyClose + 1);
  const normalized = canonicalJson(functionTokens.map((token, index) =>
    [token.kind, token.value, index === 0 ? false : token.lineBreakBefore]));
  const start = tokens[memberStart].start;
  const end = tokens[bodyClose].end;
  const sourceSpan = source.slice(start, end);
  return {
    relativePath,
    functionName,
    start,
    end,
    codeUnits: end - start,
    bytes: Buffer.byteLength(sourceSpan, "utf8"),
    sourceSha256: sha256Text(sourceSpan),
    tokenCount: functionTokens.length,
    tokenSha256: sha256Text(normalized),
  };
}

function extractAs2Function(root, relativePath, functionName) {
  return extractAs2FunctionFromCache(root, relativePath, functionName, new Map());
}

// These reviewed digests are intentionally literal and versioned.  They are not
// derived from a bundle, evidence object, or the current source during capture.
const ITEMUTIL_DELIVERY_FUNCTION_ANCHORS = Object.freeze({
  loadItemData: Object.freeze({ relativePath: ITEMUTIL_PATH, tokenCount: 713,
    tokenSha256: "bc1249da9109710f1093bfab5cb0576241f9ee92404a331576ce26d58794a0b4" }),
  require: Object.freeze({ relativePath: ITEMUTIL_PATH, tokenCount: 1066,
    tokenSha256: "9e466247690dd1ac307c6bdafcf5ea5e2ce09ace91efba1011bac5ebed6bae2a" }),
  acquire: Object.freeze({ relativePath: ITEMUTIL_PATH, tokenCount: 841,
    tokenSha256: "c844529eb07709fb5f712163ac52fdb6d8f0758b77db822d0583d51b3bffec37" }),
  getVacancies: Object.freeze({ relativePath: ARRAY_INVENTORY_PATH, tokenCount: 195,
    tokenSha256: "d8f2f71327c28b20bfc5e20a40574000a70e2ea7ee272041958eebd37ab3aca2" }),
  rebuildIndexesFromItems: Object.freeze({ relativePath: ARRAY_INVENTORY_PATH, tokenCount: 204,
    tokenSha256: "a61a68823b1574dad0758d691818d7292840b892f074bbc921649e1e13969179" }),
  getValidatedIndexes: Object.freeze({ relativePath: ARRAY_INVENTORY_PATH, tokenCount: 76,
    tokenSha256: "baddde811d98a268e28680d0290a40f2f5db2f298d04e942afb9dae6cc2b74a9" }),
  isIndexArrayValid: Object.freeze({ relativePath: ARRAY_INVENTORY_PATH, tokenCount: 139,
    tokenSha256: "55a119a8b38e93cfff98d737a1f4f74d4669d31d223063c9c12a39d01b2fa9eb" }),
});

function assertItemUtilSemanticAnchor(functionName, extracted) {
  const anchor = ITEMUTIL_DELIVERY_FUNCTION_ANCHORS[functionName];
  if (!anchor || extracted.relativePath !== anchor.relativePath
      || extracted.tokenCount !== anchor.tokenCount
      || extracted.tokenSha256 !== anchor.tokenSha256) {
    fail("production_itemutil_delivery_semantic_anchor_mismatch", "production_closure",
      "AS2 delivery function differs from the fixed reviewed semantic token anchor", {
        functionName,
        expected: anchor || null,
        actual: { relativePath: extracted.relativePath, tokenCount: extracted.tokenCount,
          tokenSha256: extracted.tokenSha256 },
      });
  }
}

function captureItemUtilDeliverySourceContract(root) {
  const cache = new Map();
  const functions = {
    loadItemData: extractAs2FunctionFromCache(root, ITEMUTIL_PATH, "loadItemData", cache),
    require: extractAs2FunctionFromCache(root, ITEMUTIL_PATH, "require", cache),
    acquire: extractAs2FunctionFromCache(root, ITEMUTIL_PATH, "acquire", cache),
    getVacancies: extractAs2FunctionFromCache(root, ARRAY_INVENTORY_PATH, "getVacancies", cache),
    rebuildIndexesFromItems: extractAs2FunctionFromCache(root, ARRAY_INVENTORY_PATH,
      "rebuildIndexesFromItems", cache),
    getValidatedIndexes: extractAs2FunctionFromCache(root, ARRAY_INVENTORY_PATH,
      "getValidatedIndexes", cache),
    isIndexArrayValid: extractAs2FunctionFromCache(root, ARRAY_INVENTORY_PATH,
      "isIndexArrayValid", cache),
  };
  Object.entries(functions).forEach(([name, extracted]) =>
    assertItemUtilSemanticAnchor(name, extracted));
  const value = { schema: ITEMUTIL_DELIVERY_SOURCE_SCHEMA,
    classifier: "ItemUtil.type-use-precedence.v1",
    equipmentPoststate: "ArrayInventory.getVacancies.first-vacancy.v1",
    semanticAnchorVersion: ITEMUTIL_DELIVERY_ANCHOR_VERSION,
    tokenCanonicalization: AS2_TOKEN_CANONICALIZATION,
    sourceFiles: [ITEMUTIL_PATH, ARRAY_INVENTORY_PATH],
    functionSpans: Object.fromEntries(Object.entries(functions).map(([name, entry]) =>
      [name, { relativePath: entry.relativePath, start: entry.start, end: entry.end,
        codeUnits: entry.codeUnits, bytes: entry.bytes }])),
    functionSha256: Object.fromEntries(Object.entries(functions)
      .map(([name, entry]) => [name, entry.sourceSha256])),
    functionTokenCount: Object.fromEntries(Object.entries(functions)
      .map(([name, entry]) => [name, entry.tokenCount])),
    functionTokenSha256: Object.fromEntries(Object.entries(functions)
      .map(([name, entry]) => [name, entry.tokenSha256])),
    invariants: [
      "equipment_before_material_before_information",
      "material_to_collection_material",
      "information_to_collection_information",
      "equipped_grenade_before_drug_then_backpack",
      "mergeable_drug_then_backpack",
      "equipment_to_sorted_first_backpack_vacancy",
      "require_precedes_all_acquire_mutations",
    ],
  };
  value.contractSha256 = sha256Text(canonicalJson(value));
  return value;
}

function localWebPath(parentRelativePath, reference, phase) {
  const raw = String(reference || "").trim().replace(/[?#].*$/, "");
  if (!raw || /^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.startsWith("//")
      || raw.startsWith("/")) {
    fail("production_web_reference_invalid", phase || "production_closure",
      "production Web declaration is not one local bounded resource", { parentRelativePath, reference });
  }
  const relative = path.posix.normalize(path.posix.join(path.posix.dirname(
    parentRelativePath.replace(/\\/g, "/")), raw.replace(/\\/g, "/")));
  if (!relative.startsWith("launcher/web/") || relative.includes("../")) {
    fail("production_web_reference_escape", phase || "production_closure",
      "production Web declaration escaped launcher/web", { parentRelativePath, reference, relative });
  }
  return relative;
}

function localCssAssetPath(parentRelativePath, reference) {
  const raw = String(reference || "").trim().replace(/[?#].*$/, "");
  if (!raw || /^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.startsWith("//")
      || raw.startsWith("/")) {
    fail("production_css_asset_reference_invalid", "production_closure",
      "production CSS asset is not one relative Web resource", {
        parentRelativePath, reference,
      });
  }
  const relative = path.posix.normalize(path.posix.join(path.posix.dirname(
    parentRelativePath.replace(/\\/g, "/")), raw.replace(/\\/g, "/")));
  if (!relative.startsWith("launcher/web/") || relative.includes("../")) {
    fail("production_css_asset_reference_escape", "production_closure",
      "production CSS asset escaped launcher/web", {
        parentRelativePath, reference, relative,
      });
  }
  return relative;
}

function parseCssImports(root, entryStyles) {
  const seen = new Set();
  const visiting = new Set();
  const edges = [];
  const assetEdges = [];
  const fontUrls = [];
  function visit(relativePath) {
    if (visiting.has(relativePath)) fail("production_css_import_cycle", "production_closure",
      "stylesheet import graph contains a cycle", { relativePath });
    if (seen.has(relativePath)) return;
    visiting.add(relativePath);
    const text = readExactText(root, relativePath).text;
    const imported = Array.from(text.matchAll(/@import\s+(?:url\(\s*)?["']?([^"')\s;]+)["']?\s*\)?\s*;/gi))
      .map((match) => localWebPath(relativePath, match[1], "production_closure"));
    if (new Set(imported).size !== imported.length) fail("production_css_import_duplicate",
      "production_closure", "stylesheet repeats one import", { relativePath, imported });
    imported.forEach((child) => {
      if (path.posix.extname(child).toLowerCase() !== ".css") {
        fail("production_css_import_invalid", "production_closure",
          "stylesheet import is not CSS", { relativePath, child });
      }
      edges.push({ parent: relativePath, child });
      visit(child);
    });
    Array.from(text.matchAll(/url\(\s*(?:(['"])(.*?)\1|([^'"\s][^)]*?))\s*\)/gi))
      .map((match) => String(match[2] || match[3] || "").trim())
      .filter((reference) => reference && !reference.startsWith("data:")
        && !reference.startsWith("#"))
      .forEach((reference) => {
        if (/^https:\/\/cfn-fonts\.local\/[A-Za-z0-9._-]+$/.test(reference)) {
          fontUrls.push(reference);
          return;
        }
        if (/^[a-z][a-z0-9+.-]*:/i.test(reference) || reference.startsWith("//")) {
          fail("production_css_external_resource_invalid", "production_closure",
            "production CSS declares an ungoverned external resource", {
              parent: relativePath, reference,
            });
        }
        const child = localCssAssetPath(relativePath, reference);
        if (path.posix.extname(child).toLowerCase() === ".css") return;
        if (![".png", ".jpg", ".jpeg", ".svg", ".webp"].includes(
          path.posix.extname(child).toLowerCase())) {
          fail("production_css_asset_type_invalid", "production_closure",
            "production CSS declares an unsupported local asset", {
              parent: relativePath, reference, child,
            });
        }
        assetEdges.push({ parent: relativePath, reference, child });
      });
    visiting.delete(relativePath);
    seen.add(relativePath);
  }
  entryStyles.forEach(visit);
  const assets = Array.from(new Set(assetEdges.map((entry) => entry.child))).sort();
  return { styles: Array.from(seen).sort(),
    edges: edges.sort((left, right) => canonicalJson(left).localeCompare(canonicalJson(right))),
    assets, assetEdges: assetEdges.sort((left, right) =>
      canonicalJson(left).localeCompare(canonicalJson(right))),
    fontUrls: Array.from(new Set(fontUrls)).sort() };
}

function deriveFontPack(root, cssFontUrls) {
  const relativePath = "launcher/web/assets/fonts/font-pack-manifest.json";
  const source = readExactText(root, relativePath);
  let manifest;
  try { manifest = JSON.parse(source.text.replace(/^\uFEFF/, "")); } catch (_error) { manifest = null; }
  if (!manifest || manifest.schemaVersion !== 1 || !manifest.groups
      || typeof manifest.groups !== "object" || Array.isArray(manifest.groups)) {
    fail("production_font_manifest_invalid", "production_closure",
      "font-pack manifest is missing or unsupported");
  }
  const catalogSha256 = sha256Bytes(fs.readFileSync(path.resolve(root, FONT_CATALOG_XML)));
  if (manifest.generatedBy !== "tools/fontctl" || manifest.gate !== "E"
      || manifest.sourceSha256 !== catalogSha256) {
    fail("production_font_manifest_invalid", "production_closure",
      "font-pack compatibility projection is detached from fonts.xml");
  }
  const resources = [];
  Object.keys(manifest.groups).forEach((groupName) => {
    const group = manifest.groups[groupName];
    if (!group || !Array.isArray(group.files)) {
      fail("production_font_manifest_invalid", "production_closure",
        "font-pack group lacks a files array", { groupName });
    }
    group.files.forEach((entry) => {
      const name = String(entry && entry.name || "");
      if (!/^[A-Za-z0-9._-]+\.(?:ttf|otf|woff2)$/.test(name)
          || path.basename(name) !== name || !Number.isSafeInteger(entry.bytes)
          || entry.bytes < 1 || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
          || typeof entry.shippedFallback !== "boolean" || !Array.isArray(entry.urls)
          || entry.urls.length < 1) {
        fail("production_font_manifest_invalid", "production_closure",
          "font-pack file declaration is malformed", { groupName, name });
      }
      resources.push({ group: groupName, name,
        url: "https://cfn-fonts.local/" + name, bytes: entry.bytes,
        sha256: entry.sha256, shippedFallback: entry.shippedFallback });
    });
  });
  if (resources.length < 1 || new Set(resources.map((entry) => entry.name)).size !== resources.length
      || canonicalJson(resources.map((entry) => entry.url).sort())
        !== canonicalJson(cssFontUrls.slice().sort())) {
    fail("production_font_css_projection_invalid", "production_closure",
      "CSS cfn-fonts URLs and font-pack manifest are not one exact set", {
        manifest: resources.map((entry) => entry.url), css: cssFontUrls,
      });
  }
  return { relativePath, schemaVersion: manifest.schemaVersion, resources };
}

function deriveIconManifest(root) {
  const relativePath = "launcher/web/icons/manifest.json";
  const source = readExactText(root, relativePath);
  let manifest;
  try { manifest = JSON.parse(source.text.replace(/^\uFEFF/, "")); } catch (_error) { manifest = null; }
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    fail("production_icon_manifest_invalid", "production_closure",
      "icon manifest is not one JSON object");
  }
  const names = Object.keys(manifest);
  if (!names.length || names.some((name) => !name.trim()
      || !manifest[name] || typeof manifest[name] !== "object" || Array.isArray(manifest[name]))) {
    fail("production_icon_manifest_invalid", "production_closure",
      "icon manifest contains an empty name or malformed entry");
  }
  return { relativePath, entryCount: names.length,
    nameSetSha256: sha256Text(canonicalJson(names.slice().sort())) };
}

function deriveIdlePrewarmResources(root, overlayText) {
  const calls = Array.from(overlayText.matchAll(
    /\bMapPanelData\.prewarmAssets\(\s*(['"])([^'"]+)\1\s*\)/g));
  if (calls.length !== 1 || calls[0][2] !== "base") {
    fail("production_idle_prewarm_declaration_invalid", "production_closure",
      "Overlay must declare one exact base-map idle prewarm call", {
        calls: calls.map((entry) => entry[2]),
      });
  }
  const relativePath = "launcher/web/modules/map-panel-data.js";
  const mapText = readExactText(root, relativePath).text;
  [
    "if (page.backgroundUrl) urls.push(page.backgroundUrl);",
    "var visuals = page.sceneVisuals || [];",
    "if (visuals[i] && visuals[i].assetUrl) urls.push(visuals[i].assetUrl);",
    "img.src = resolveAssetUrlForPrewarm(urls[j]);",
  ].forEach((statement) => {
    if (mapText.split(statement).length !== 2) {
      fail("production_idle_prewarm_contract_invalid", "production_closure",
        "map prewarm projection no longer has its one exact source statement", { statement });
    }
  });
  const pagesStart = mapText.indexOf("var _pages = {");
  const baseStart = mapText.indexOf("\n        base: {", pagesStart);
  const factionStart = mapText.indexOf("\n        faction: {", baseStart);
  if (pagesStart < 0 || baseStart < 0 || factionStart < 0) {
    fail("production_idle_prewarm_page_invalid", "production_closure",
      "map base-page declaration cannot be bounded exactly");
  }
  const basePage = mapText.slice(baseStart, factionStart);
  const backgrounds = Array.from(basePage.matchAll(/\bbackgroundUrl:\s*(['"])([^'"]+)\1/g));
  const visualsStart = basePage.indexOf("sceneVisuals: [");
  const visualsEnd = basePage.indexOf("\n            ],", visualsStart);
  if (backgrounds.length !== 1 || visualsStart < 0 || visualsEnd < 0) {
    fail("production_idle_prewarm_page_invalid", "production_closure",
      "map base page lacks one background and one bounded sceneVisuals list");
  }
  const visualBlock = basePage.slice(visualsStart, visualsEnd);
  const visuals = Array.from(visualBlock.matchAll(/\bassetUrl:\s*(['"])([^'"]+)\1/g))
    .map((entry) => entry[2]);
  const assets = [backgrounds[0][2]].concat(visuals);
  if (visuals.length !== 14 || new Set(assets).size !== 15) {
    fail("production_idle_prewarm_asset_set_invalid", "production_closure",
      "base map idle prewarm must project one background and fourteen unique scene visuals", {
        background: backgrounds[0] && backgrounds[0][2], visualCount: visuals.length,
      });
  }
  const resources = assets.map((reference) => {
    const assetPath = localWebPath("launcher/web/overlay.html", reference,
      "production_closure");
    if (path.posix.extname(assetPath).toLowerCase() !== ".webp") {
      fail("production_idle_prewarm_asset_type_invalid", "production_closure",
        "base map idle prewarm contains a non-WebP asset", { reference, assetPath });
    }
    return { type: "Image", relativePath: assetPath };
  });
  return { pageId: calls[0][2], source: relativePath, resources };
}

function deriveDeclaredWebClosure(root) {
  const registry = readExactText(root, "launcher/web/modules/panels-lazy-registry.js").text;
  const registrations = Array.from(registry.matchAll(/Panels\.registerLazy\(\s*['"]kshop['"]\s*,\s*\[([\s\S]*?)\]\s*,\s*noop\s*\)/g));
  if (registrations.length !== 1) {
    fail("production_kshop_registry_invalid", "production_closure",
      "lazy registry must contain one exact KShop declaration");
  }
  const declared = Array.from(registrations[0][1].matchAll(/['"]([^'"]+)['"]/g))
    .map((match) => "launcher/web/" + match[1]);
  if (canonicalJson(declared) !== canonicalJson(REQUIRED_KSHOP_LAZY_WEB)) {
    fail("production_kshop_registry_mismatch", "production_closure",
      "KShop declared lazy dependency order differs from the closed production set", {
        declared, expected: REQUIRED_KSHOP_LAZY_WEB,
      });
  }
  const overlay = readExactText(root, "launcher/web/overlay.html").text;
  const scriptTags = Array.from(overlay.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi));
  const scriptExecutionOrder = scriptTags.map((match, index) => {
    const source = /\bsrc\s*=\s*['"]([^'"]+)['"]/i.exec(match[1]);
    if (source) return { kind: "external", relativePath: localWebPath(
      "launcher/web/overlay.html", source[1], "production_closure") };
    const bytes = Buffer.from(match[2], "utf8");
    if (!bytes.length) fail("production_overlay_inline_script_invalid", "production_closure",
      "Overlay contains an empty inline executable", { index });
    return { kind: "inline", inlineIndex: index,
      sha256: sha256Bytes(bytes), bytes: bytes.length };
  });
  const sources = scriptExecutionOrder.filter((entry) => entry.kind === "external")
    .map((entry) => entry.relativePath);
  if (sources.length < 1 || new Set(sources).size !== sources.length
      || !sources.includes("launcher/web/modules/panels-lazy-registry.js")) {
    fail("production_overlay_script_declarations_invalid", "production_closure",
      "Overlay script declarations are empty, duplicated, or omit the lazy registry", { sources });
  }
  const entryStyles = Array.from(overlay.matchAll(/<link\b(?=[^>]*\brel\s*=\s*['"]stylesheet['"])[^>]*\bhref\s*=\s*['"]([^'"]+)['"][^>]*>/gi))
    .map((match) => localWebPath("launcher/web/overlay.html", match[1], "production_closure"));
  if (entryStyles.length < 1 || new Set(entryStyles).size !== entryStyles.length) {
    fail("production_overlay_style_declarations_invalid", "production_closure",
      "Overlay stylesheet declarations are empty or duplicated", { entryStyles });
  }
  const css = parseCssImports(root, entryStyles);
  const idlePrewarm = deriveIdlePrewarmResources(root, overlay);
  const fontPack = deriveFontPack(root, css.fontUrls);
  const iconManifest = deriveIconManifest(root);
  return { overlayScripts: sources, scriptExecutionOrder, declaredLazyWeb: declared,
    entryStyles, importedStyles: css.styles.filter((entry) => !entryStyles.includes(entry)),
    cssImportEdges: css.edges, cssConditionalAssets: css.assets,
    cssConditionalAssetEdges: css.assetEdges, idlePrewarm, fontPack, iconManifest };
}

function decodeXmlText(value) {
  return String(value || "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&#x([0-9a-f]+);/gi, (_match, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#([0-9]+);/g, (_match, decimal) => String.fromCodePoint(parseInt(decimal, 10)))
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'").replace(/&amp;/g, "&");
}

function exactXmlValues(text, tag, phase) {
  const pattern = new RegExp("<" + tag + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + tag + "\\s*>", "gi");
  return Array.from(String(text || "").replace(/<!--[\s\S]*?-->/g, "").matchAll(pattern))
    .map((match) => decodeXmlText(match[1]).trim());
}

function directXmlValues(text, tag) {
  const source = String(text || "").replace(/<!--[\s\S]*?-->/g, "");
  const token = /<\/?([A-Za-z_][A-Za-z0-9_.:-]*)\b[^>]*>/g;
  const values = [];
  let depth = 0;
  let capture = null;
  let match;
  while ((match = token.exec(source)) !== null) {
    const raw = match[0];
    const name = match[1];
    const closing = raw.startsWith("</");
    const selfClosing = /\/\s*>$/.test(raw);
    if (!closing) {
      if (depth === 0 && name.toLowerCase() === String(tag).toLowerCase()) {
        capture = { start: token.lastIndex, name };
      }
      if (!selfClosing) depth += 1;
      else if (capture && depth === 0) {
        values.push("");
        capture = null;
      }
      continue;
    }
    depth -= 1;
    if (depth < 0) fail("production_item_xml_invalid", "production_closure",
      "item XML direct-child scanner observed an unmatched closing tag", { tag: name });
    if (capture && depth === 0 && name === capture.name) {
      values.push(decodeXmlText(source.slice(capture.start, match.index)).trim());
      capture = null;
    }
  }
  if (depth !== 0 || capture) fail("production_item_xml_invalid", "production_closure",
    "item XML direct-child scanner observed an unclosed tag", { tag });
  return values;
}

function exactXmlValue(text, tag, options) {
  const settings = options || {};
  const values = settings.direct ? directXmlValues(text, tag)
    : exactXmlValues(text, tag, settings.phase);
  if (values.length > 1 || (!settings.optional && values.length !== 1)) {
    fail("production_item_xml_invalid", "production_closure",
      "item XML field is missing or duplicated", { tag, phase: settings.phase, count: values.length });
  }
  return values.length ? values[0] : "";
}

function itemDataDeclarations(root) {
  const manifestRelative = "data/items/list.xml";
  const manifestText = readExactText(root, manifestRelative).text;
  const names = exactXmlValues(manifestText, "items", manifestRelative);
  if (!names.length || new Set(names).size !== names.length
      || names.some((name) => !name || path.posix.basename(name) !== name
        || path.posix.extname(name).toLowerCase() !== ".xml")) {
    fail("production_item_data_declaration_invalid", "production_closure",
      "data/items/list.xml does not declare one unique bounded item XML sequence", { names });
  }
  const itemByName = new Map();
  let itemDefinitionCount = 0;
  let duplicateItemDefinitionCount = 0;
  names.forEach((name) => {
    const relativePath = "data/items/" + name;
    const text = readExactText(root, relativePath).text;
    const blocks = Array.from(text.replace(/<!--[\s\S]*?-->/g, "")
      .matchAll(/<item(?:\s[^>]*)?>([\s\S]*?)<\/item\s*>/gi));
    if (!blocks.length) fail("production_item_data_empty", "production_closure",
      "declared item XML contains no item", { relativePath });
    blocks.forEach((match, index) => {
      const block = match[1];
      const phase = relativePath + "#item-" + (index + 1);
      const nameValue = exactXmlValue(block, "name", { phase, direct: true });
      const dataValues = directXmlValues(block, "data");
      if (!nameValue || dataValues.length > 1) {
        fail("production_item_identity_invalid", "production_closure",
          "item XML name is empty or has multiple data containers", {
            relativePath, name: nameValue, dataContainers: dataValues.length,
          });
      }
      const levelText = dataValues.length
        ? exactXmlValue(dataValues[0], "level", { optional: true, phase }) : "";
      const level = levelText === "" ? 0 : Number(levelText);
      if (!Number.isInteger(level) || level < 0) fail("production_item_level_invalid",
        "production_closure", "item level is outside the AS2 catalog integer contract", {
          relativePath, name: nameValue, level: levelText,
        });
      const projection = {
        name: nameValue,
        displayName: exactXmlValue(block, "displayname", {
          optional: true, phase, direct: true }) || nameValue,
        icon: exactXmlValue(block, "icon", { optional: true, phase, direct: true }) || nameValue,
        majorType: exactXmlValue(block, "type", { optional: true, phase, direct: true }),
        subType: exactXmlValue(block, "use", { optional: true, phase, direct: true }),
        level,
        source: relativePath,
      };
      const prior = itemByName.get(nameValue);
      // The production item loader combines files in manifest order into one
      // name-keyed object; later declarations replace earlier duplicate names.
      // Preserve that exact rule instead of inventing a stricter data policy.
      if (prior) duplicateItemDefinitionCount += 1;
      itemByName.set(nameValue, projection);
      itemDefinitionCount += 1;
    });
  });
  return { manifestRelative, names, itemByName, itemDefinitionCount,
    duplicateItemDefinitionCount };
}

function deriveDataFiles(root) {
  const listRelative = "data/kshop/list.xml";
  const listText = readExactText(root, listRelative).text;
  const declaredNames = Array.from(listText.matchAll(/<kshop>\s*([^<]+?)\s*<\/kshop>/g))
    .map((match) => match[1]);
  const dataDirectory = path.resolve(root, "data", "kshop");
  const actualNames = fs.readdirSync(dataDirectory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && !entry.isSymbolicLink()
      && path.extname(entry.name).toLowerCase() === ".json")
    .map((entry) => entry.name).sort();
  if (declaredNames.length !== 13 || new Set(declaredNames).size !== declaredNames.length
      || canonicalJson(declaredNames.slice().sort()) !== canonicalJson(actualNames)) {
    fail("production_kshop_data_declaration_invalid", "production_closure",
      "data/kshop list.xml must exactly declare the complete 13-JSON catalog", {
        declaredNames, actualNames,
      });
  }
  const items = itemDataDeclarations(root);
  const deliverySourceContract = captureItemUtilDeliverySourceContract(root);
  const catalog = [];
  declaredNames.forEach((name) => {
    const relativePath = "data/kshop/" + name;
    let rows;
    try { rows = JSON.parse(readExactText(root, relativePath).text.replace(/^\uFEFF/, "")); }
    catch (error) { fail("production_kshop_data_json_invalid", "production_closure",
      "KShop catalog JSON cannot be parsed", { relativePath, error: error.message }); }
    if (!Array.isArray(rows) || !rows.length) fail("production_kshop_data_json_invalid",
      "production_closure", "KShop catalog JSON must contain a non-empty array", { relativePath });
    rows.forEach((row) => {
      const item = row && items.itemByName.get(String(row.item || ""));
      const price = Number(row && row.price);
      if (!row || typeof row.id !== "string" || !row.id || typeof row.item !== "string"
          || !row.item || typeof row.type !== "string" || !row.type
          || !Number.isInteger(price) || price < 0 || !item) {
        fail("production_kshop_catalog_entry_invalid", "production_closure",
          "KShop row cannot project one exact current item-data identity", {
            relativePath, catalogIndex: catalog.length, itemName: row && row.item,
          });
      }
      const entry = { idx: catalog.length, id: row.id, item: row.item, type: row.type,
        price, displayname: item.displayName, icon: item.icon,
        majorType: item.majorType, subType: item.subType, level: item.level,
        maxQuantity: item.majorType === "武器" || item.majorType === "防具" ? 1 : 999999 };
      entry.deliveryContract = classifyCatalogDelivery(entry);
      catalog.push(entry);
    });
  });
  const positiveSale = catalog.filter((entry) => entry.price > 0 && entry.type !== "非卖品")
    .sort((left, right) => left.price - right.price || left.idx - right.idx
      || left.item.localeCompare(right.item));
  const physical = positiveSale.filter((entry) => entry.deliveryContract.executableJourneyEligible);
  if (!positiveSale.length || !physical.length) fail("production_catalog_executable_path_missing",
    "production_closure", "current production catalog has no deterministic physical-slot journey");
  const project = (entry) => ({ catalogIndex: entry.idx, itemName: entry.item,
    displayName: entry.displayname, icon: entry.icon, shopType: entry.type,
    majorType: entry.majorType, subType: entry.subType, price: entry.price,
    requiredLevel: entry.level, maxQuantity: entry.maxQuantity,
    deliveryContract: entry.deliveryContract });
  const counts = Object.create(null);
  catalog.forEach((entry) => {
    const key = entry.deliveryContract.classification;
    counts[key] = Number(counts[key] || 0) + 1;
  });
  const catalogProjection = catalog.map(project);
  const catalogDeliveryContract = {
    schema: CATALOG_DELIVERY_SCHEMA,
    classifier: "ItemUtil.type-use-precedence.v1",
    catalogEntryCount: catalog.length,
    itemDefinitionCount: items.itemDefinitionCount,
    uniqueItemNameCount: items.itemByName.size,
    duplicateItemDefinitionCount: items.duplicateItemDefinitionCount,
    itemUtilDeliverySourceContract: deliverySourceContract,
    classificationCounts: counts,
    globalLowestPositiveSale: project(positiveSale[0]),
    lowestProvenPhysicalCandidate: project(physical[0]),
    minimumExecutableProfile: { balance: physical[0].price,
      playerLevel: physical[0].level, reverseLevel: 0 },
    catalogProjectionSha256: sha256Text(canonicalJson(catalogProjection)),
  };
  catalogDeliveryContract.contractSha256 = sha256Text(canonicalJson(catalogDeliveryContract));
  const descriptors = [{ role: "kshop_data_manifest", relativePath: listRelative }]
    .concat(declaredNames.map((name) => ({ role: "kshop_data", relativePath: "data/kshop/" + name })))
    .concat([{ role: "item_data_manifest", relativePath: items.manifestRelative }])
    .concat(items.names.map((name) => ({ role: "item_data", relativePath: "data/items/" + name })));
  return { descriptors, catalogDeliveryContract };
}

function productionDescriptors(root) {
  verifyBuildFileInventory(root);
  const data = deriveDataFiles(root);
  const declarations = Object.assign({}, deriveDeclaredWebClosure(root), {
    catalogDeliveryContract: data.catalogDeliveryContract,
  });
  const descriptors = [
    { role: "page", relativePath: "launcher/web/overlay.html" },
    ...declarations.overlayScripts.map((relativePath) => ({
      role: relativePath === "launcher/web/modules/panels-lazy-registry.js"
        ? "lazy_registry" : "overlay_script", relativePath,
    })),
    ...declarations.declaredLazyWeb.map((relativePath) => ({ role: "kshop_lazy_web", relativePath })),
    ...declarations.entryStyles.map((relativePath) => ({ role: "style_entry", relativePath })),
    ...declarations.importedStyles.map((relativePath) => ({ role: "style_import", relativePath })),
    ...declarations.idlePrewarm.resources.map((entry) => ({
      role: "idle_prewarm_image", relativePath: entry.relativePath,
    })),
    ...declarations.cssConditionalAssets.map((relativePath) => ({
      role: "css_conditional_asset", relativePath,
    })),
    { role: "font_pack_manifest", relativePath: declarations.fontPack.relativePath },
    { role: "font_catalog_xml", relativePath: FONT_CATALOG_XML },
    { role: "font_runtime_projection", relativePath: FONT_RUNTIME_PROJECTION },
    ...PERMANENT_FONT_FILES.map((relativePath) => ({ role: "permanent_font_asset", relativePath })),
    { role: "icon_manifest", relativePath: declarations.iconManifest.relativePath },
    ...HOST_FILES, ...BUILD_FILES, ...AS2_FILES, ...data.descriptors,
  ];
  const deduplicated = [];
  const seen = new Set();
  descriptors.forEach((entry) => {
    const key = entry.relativePath.toLowerCase();
    if (seen.has(key)) fail("production_closure_descriptor_duplicate", "production_closure",
      "production closure contains a duplicate path", { relativePath: entry.relativePath });
    seen.add(key);
    deduplicated.push(entry);
  });
  return { declarations, descriptors: deduplicated };
}

const PRODUCTION_FILES = Object.freeze(productionDescriptors(CANONICAL_ROOT).descriptors);

function safeRuntimeRelativePath(value) {
  const normalized = String(value || "").replace(/\\/g, "/");
  const withoutTrailingSlash = normalized.replace(/\/+$/, "");
  if (!normalized || normalized.startsWith("/") || /^[A-Za-z]:/.test(normalized)
      || !withoutTrailingSlash
      || withoutTrailingSlash.split("/").some((part) => !part || part === "." || part === "..")) {
    fail("runtime_input_path_invalid", "production_closure",
      "runtime input path is not one normalized relative file", { value });
  }
  return normalized;
}

function readRuntimeInputConfig(root) {
  const configPath = path.resolve(root, "config", "build", "runtime-inputs.v2.json");
  let config;
  try { config = JSON.parse(fs.readFileSync(configPath, "utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime input config cannot be parsed", { message: error.message });
  }
  const domainNames = ["artifactSource", "producerRecipe", "toolchainLock"];
  if (!config || config.schema !== "cf7-runtime-inputs.v2" || !config.domains
      || domainNames.some((name) => !config.domains[name]
        || !Array.isArray(config.domains[name].fixedFiles)
        || !Array.isArray(config.domains[name].trees))
      || !config.payload || !Array.isArray(config.payload.fixedRoots)
      || !Array.isArray(config.payload.trees) || !Array.isArray(config.payload.excludePaths)
      || !Array.isArray(config.payload.excludePrefixes)) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime artifact-source config is missing or unsupported");
  }
  return config;
}

function enumerateRuntimeDomainFiles(root, config, domainName) {
  const domain = config.domains[domainName];
  const values = new Set((domain.fixedFiles || []).map(safeRuntimeRelativePath));
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const full = path.join(directory, entry.name);
      const relative = (base ? base + "/" : "") + entry.name;
      const normalized = safeRuntimeRelativePath(
        String(tree.path).replace(/\\/g, "/").replace(/\/$/, "") + "/" + relative);
      if (entry.isSymbolicLink()) fail("runtime_input_tree_invalid", "production_closure",
        "runtime input tree contains an indirect entry", { relativePath: normalized });
      if (entry.isDirectory()) return walk(full, relative, tree);
      if (!entry.isFile()) return;
      const extension = path.extname(normalized).toLowerCase();
      if (Array.isArray(tree.includeExtensions) && tree.includeExtensions.length > 0
          && !tree.includeExtensions.map((value) => String(value).toLowerCase()).includes(extension)) return;
      if ((tree.excludePaths || []).map(safeRuntimeRelativePath)
        .includes(normalized)) return;
      if ((tree.excludePrefixes || []).map(safeRuntimeRelativePath)
        .some((prefix) => normalized.startsWith(prefix))) return;
      values.add(normalized);
    });
  }
  (domain.trees || []).forEach((tree) => {
    const relative = safeRuntimeRelativePath(tree.path);
    const base = path.resolve(root, relative.replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(base); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("runtime_input_tree_invalid", "production_closure",
        "runtime artifact-source tree is missing", { path: tree.path });
    }
    walk(base, "", tree);
  });
  return Array.from(values).sort();
}

function verifyBuildFileInventory(root) {
  const config = readRuntimeInputConfig(root);
  const expectedProducer = enumerateRuntimeDomainFiles(root, config, "producerRecipe");
  const expectedToolchain = enumerateRuntimeDomainFiles(root, config, "toolchainLock");
  const declaredProducer = BUILD_FILES.filter((entry) => entry.role === "runtime_producer_source")
    .map((entry) => entry.relativePath).sort();
  const declaredToolchain = BUILD_FILES.filter((entry) => entry.role === "runtime_toolchain_lock")
    .map((entry) => entry.relativePath).sort();
  if (canonicalJson(expectedProducer) !== canonicalJson(declaredProducer)
      || canonicalJson(expectedToolchain) !== canonicalJson(declaredToolchain)) {
    fail("production_build_inventory_invalid", "production_closure",
      "runtime producer/toolchain surface drifted from runtime-inputs.v2", {
        expectedProducer, declaredProducer, expectedToolchain, declaredToolchain,
      });
  }
}

function currentProducerInputs(root) {
  const resolvedRoot = path.resolve(root);
  const config = readRuntimeInputConfig(resolvedRoot);
  const domainNames = ["artifactSource", "producerRecipe", "toolchainLock"];
  const rowsByDomain = Object.create(null);
  const owners = new Map();
  domainNames.forEach((name) => {
    rowsByDomain[name] = enumerateRuntimeDomainFiles(resolvedRoot, config, name).map((relativePath) => {
      if (owners.has(relativePath)) fail("runtime_input_domain_overlap", "production_closure",
        "runtime input belongs to more than one identity domain", { relativePath });
      owners.set(relativePath, name);
      const exact = exactFile(resolvedRoot, { role: "runtime_input", relativePath });
      return { relativePath, sha256: exact.sha256, bytes: exact.bytes };
    });
  });
  const configFile = exactFile(resolvedRoot, {
    role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json",
  });
  const payload = {
    fixedRoots: config.payload.fixedRoots.map(safeRuntimeRelativePath),
    trees: config.payload.trees.map(safeRuntimeRelativePath),
    excludePaths: config.payload.excludePaths.map(safeRuntimeRelativePath),
    excludePrefixes: config.payload.excludePrefixes.map(safeRuntimeRelativePath),
  };
  const fingerprint = sha256Text(canonicalJson({ configFile, rowsByDomain, payload }));
  const cached = producerInputsCache.get(resolvedRoot.toLowerCase());
  if (cached && cached.fingerprint === fingerprint) return JSON.parse(JSON.stringify(cached.value));
  const script = [
    "$ErrorActionPreference='Stop'",
    "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)",
    ". (Join-Path $env:CF7_KSHOP_SOURCE_ROOT 'tools/runtime-build-v2-common.ps1')",
    "$a=Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $env:CF7_KSHOP_SOURCE_ROOT -Mode Worktree",
    "$p=Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $env:CF7_KSHOP_SOURCE_ROOT -Mode Worktree",
    "$t=Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $env:CF7_KSHOP_SOURCE_ROOT -Mode Worktree",
    "$b=Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $a -ProducerRecipeHash $p -ToolchainLockHash $t",
    "[ordered]@{artifactSourceHash=$a;producerRecipeHash=$p;toolchainLockHash=$t;buildIdentityHash=$b}|ConvertTo-Json -Compress",
  ].join("\n");
  const result = childProcess.spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass",
    "-Command", script], { cwd: resolvedRoot, encoding: "utf8", windowsHide: true,
    maxBuffer: 4 * 1024 * 1024,
    env: Object.assign({}, process.env, { CF7_KSHOP_SOURCE_ROOT: resolvedRoot }) });
  let hashes;
  try { hashes = JSON.parse(String(result.stdout || "").trim()); } catch (_error) { hashes = null; }
  const hashFields = ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash",
    "buildIdentityHash"];
  if (result.status !== 0 || !hashes
      || hashFields.some((name) => !SHA256_RE.test(String(hashes[name] || "")))) {
    fail("runtime_producer_hash_failed", "production_closure",
      "canonical runtime producer identity could not be recomputed", {
        status: result.status, stderr: String(result.stderr || "").slice(0, 400),
      });
  }
  const normalizedHashes = Object.create(null);
  hashFields.forEach((name) => { normalizedHashes[name] = String(hashes[name]).toUpperCase(); });
  const expectedBuildIdentity = sha256Text("artifactSourceHash\t"
    + normalizedHashes.artifactSourceHash + "\nproducerRecipeHash\t"
    + normalizedHashes.producerRecipeHash + "\ntoolchainLockHash\t"
    + normalizedHashes.toolchainLockHash + "\n").toUpperCase();
  if (normalizedHashes.buildIdentityHash !== expectedBuildIdentity) {
    fail("runtime_producer_build_identity_invalid", "production_closure",
      "canonical runtime domain hashes do not form their declared build identity");
  }
  const domains = Object.create(null);
  domainNames.forEach((name) => {
    const files = rowsByDomain[name];
    domains[name] = { hash: normalizedHashes[name + "Hash"], fileCount: files.length,
      fingerprintSha256: sha256Text(canonicalJson(files)), files };
  });
  const value = { schema: PRODUCER_INPUTS_SCHEMA, root: resolvedRoot,
    config: configFile, domains, payload,
    buildIdentityHash: normalizedHashes.buildIdentityHash };
  value.inputsSha256 = sha256Text(canonicalJson(value));
  producerInputsCache.set(resolvedRoot.toLowerCase(), { fingerprint, value });
  return JSON.parse(JSON.stringify(value));
}

function captureProductionClosure(root, capturedAt) {
  const derived = productionDescriptors(root);
  const declarations = derived.declarations;
  const producerInputs = currentProducerInputs(root);
  const semanticContracts = {
    inventoryPhysicalSurface: captureInventoryPhysicalSurfaceContract(root),
  };
  const value = { schema: CLOSURE_SCHEMA, capturedAt: capturedAt || new Date().toISOString(),
    root: path.resolve(root), files: derived.descriptors.map((entry) => exactFile(root, entry)),
    declarations,
    producerInputs,
    semanticContracts };
  value.closureSha256 = sha256Text(canonicalJson(value));
  return value;
}

function verifyItemUtilDeliverySourceContract(contract) {
  const expectedKeys = ["schema", "classifier", "equipmentPoststate", "semanticAnchorVersion",
    "tokenCanonicalization", "sourceFiles", "functionSpans", "functionSha256",
    "functionTokenCount", "functionTokenSha256", "invariants", "contractSha256"].sort();
  const expectedFunctions = ["loadItemData", "require", "acquire", "getVacancies",
    "rebuildIndexesFromItems", "getValidatedIndexes", "isIndexArrayValid"];
  const expectedInvariants = [
    "equipment_before_material_before_information",
    "material_to_collection_material",
    "information_to_collection_information",
    "equipped_grenade_before_drug_then_backpack",
    "mergeable_drug_then_backpack",
    "equipment_to_sorted_first_backpack_vacancy",
    "require_precedes_all_acquire_mutations",
  ];
  const unsigned = Object.assign({}, contract);
  delete unsigned.contractSha256;
  const exactFunctionKeys = (value) => value
    && canonicalJson(Object.keys(value)) === canonicalJson(expectedFunctions);
  const functionsValid = contract && exactFunctionKeys(contract.functionSpans)
    && exactFunctionKeys(contract.functionSha256)
    && exactFunctionKeys(contract.functionTokenCount)
    && exactFunctionKeys(contract.functionTokenSha256)
    && expectedFunctions.every((name) => {
      const anchor = ITEMUTIL_DELIVERY_FUNCTION_ANCHORS[name];
      const span = contract.functionSpans[name];
      return anchor && span
        && canonicalJson(Object.keys(span).sort()) === canonicalJson(
          ["relativePath", "start", "end", "codeUnits", "bytes"].sort())
        && span.relativePath === anchor.relativePath
        && Number.isInteger(span.start) && span.start >= 0
        && Number.isInteger(span.end) && span.end > span.start
        && span.codeUnits === span.end - span.start
        && Number.isInteger(span.bytes) && span.bytes >= span.codeUnits
        && SHA256_RE.test(String(contract.functionSha256[name] || ""))
        && contract.functionTokenCount[name] === anchor.tokenCount
        && contract.functionTokenSha256[name] === anchor.tokenSha256;
    });
  if (!contract || canonicalJson(Object.keys(contract).sort()) !== canonicalJson(expectedKeys)
      || contract.schema !== ITEMUTIL_DELIVERY_SOURCE_SCHEMA
      || contract.classifier !== "ItemUtil.type-use-precedence.v1"
      || contract.equipmentPoststate !== "ArrayInventory.getVacancies.first-vacancy.v1"
      || contract.semanticAnchorVersion !== ITEMUTIL_DELIVERY_ANCHOR_VERSION
      || contract.tokenCanonicalization !== AS2_TOKEN_CANONICALIZATION
      || canonicalJson(contract.sourceFiles) !== canonicalJson([ITEMUTIL_PATH, ARRAY_INVENTORY_PATH])
      || !functionsValid
      || canonicalJson(contract.invariants) !== canonicalJson(expectedInvariants)
      || contract.contractSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("production_itemutil_delivery_source_contract_invalid", "production_closure",
      "ItemUtil delivery source declaration is malformed or detached");
  }
  return contract;
}

function verifyCatalogDeliveryContract(contract) {
  const unsigned = Object.assign({}, contract);
  delete unsigned.contractSha256;
  const lowest = contract && contract.globalLowestPositiveSale;
  const physical = contract && contract.lowestProvenPhysicalCandidate;
  const profile = contract && contract.minimumExecutableProfile;
  const counts = contract && contract.classificationCounts;
  const sourceContract = contract && contract.itemUtilDeliverySourceContract;
  const classifiedCount = counts && Object.values(counts).reduce((sum, value) =>
    sum + Number(value || 0), 0);
  if (!contract || contract.schema !== CATALOG_DELIVERY_SCHEMA
      || contract.classifier !== "ItemUtil.type-use-precedence.v1"
      || verifyItemUtilDeliverySourceContract(sourceContract) !== sourceContract
      || !Number.isInteger(contract.catalogEntryCount) || contract.catalogEntryCount < 1
      || classifiedCount !== contract.catalogEntryCount
      || !lowest || !lowest.deliveryContract
      || lowest.deliveryContract.executableJourneyEligible !== false
      || !physical || !physical.deliveryContract
      || physical.deliveryContract.classification !== "equipment"
      || physical.deliveryContract.authorityItemKind !== "equipment"
      || physical.deliveryContract.destination !== "backpack_first_vacancy"
      || physical.deliveryContract.verifierPoststate
        !== "complete_50_slot_backpack_physical_delta"
      || physical.deliveryContract.executableJourneyEligible !== true
      || !profile || profile.balance !== physical.price
      || profile.playerLevel !== physical.requiredLevel || profile.reverseLevel !== 0
      || !SHA256_RE.test(String(contract.catalogProjectionSha256 || ""))
      || contract.contractSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("production_catalog_delivery_contract_invalid", "production_closure",
      "catalog/item-data projection does not expose one exact AS2 destination contract");
  }
  return contract;
}

function verifyProductionClosure(root, closure) {
  const derived = productionDescriptors(root);
  if (!closure || closure.schema !== CLOSURE_SCHEMA || path.resolve(closure.root || "")
      .toLowerCase() !== path.resolve(root).toLowerCase()
      || !Array.isArray(closure.files) || closure.files.length !== derived.descriptors.length) {
    fail("production_closure_invalid", "production_closure",
      "KShop production closure envelope is missing or incomplete");
  }
  const unsigned = Object.assign({}, closure);
  delete unsigned.closureSha256;
  if (closure.closureSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("production_closure_digest_invalid", "production_closure",
      "KShop production closure digest is detached");
  }
  const current = derived.descriptors.map((entry) => exactFile(root, entry));
  if (canonicalJson(current) !== canonicalJson(closure.files)) {
    fail("production_closure_current_tree_mismatch", "production_closure",
      "captured KShop production bytes differ from the current canonical tree");
  }
  const declarations = derived.declarations;
  verifyCatalogDeliveryContract(declarations.catalogDeliveryContract);
  if (canonicalJson(declarations) !== canonicalJson(closure.declarations)) {
    fail("production_declaration_current_tree_mismatch", "production_closure",
      "captured KShop Web declarations differ from the current canonical tree");
  }
  const producerInputs = currentProducerInputs(root);
  if (canonicalJson(producerInputs) !== canonicalJson(closure.producerInputs)) {
    fail("production_producer_inputs_current_tree_mismatch", "production_closure",
      "candidate producer inputs differ from the current canonical tree");
  }
  const semanticContracts = closure.semanticContracts;
  if (!semanticContracts
      || canonicalJson(Object.keys(semanticContracts))
        !== canonicalJson(["inventoryPhysicalSurface"])) {
    fail("production_inventory_surface_contract_invalid", "production_closure",
      "KShop production closure lacks its exact inventory semantic contract");
  }
  verifyInventoryPhysicalSurfaceContract(root, semanticContracts.inventoryPhysicalSurface);
  return closure;
}

function safeCandidateRelativePath(value, code) {
  const normalized = String(value || "").replace(/\\/g, "/");
  const withoutTrailingSlash = normalized.replace(/\/+$/, "");
  if (!normalized || normalized.startsWith("/") || path.isAbsolute(normalized)
      || /(^|\/)\.\.(\/|$)/.test(normalized) || /[\t\r\n]/.test(normalized)
      || !withoutTrailingSlash
      || withoutTrailingSlash.split("/").some((entry) => !entry || entry === ".")) {
    fail(code, "production_closure", "candidate payload contains an unsafe relative path", { value });
  }
  return normalized;
}

function exactCandidateFile(candidateRoot, relativePath, maximumBytes, allowEmpty) {
  const resolvedRoot = path.resolve(candidateRoot);
  let rootStat;
  let rootReal;
  try { rootStat = fs.lstatSync(resolvedRoot); rootReal = fs.realpathSync.native(resolvedRoot); }
  catch (_error) { rootStat = null; rootReal = null; }
  if (!rootStat || !rootStat.isDirectory() || rootStat.isSymbolicLink()
      || path.resolve(rootReal).toLowerCase() !== resolvedRoot.toLowerCase()) {
    fail("candidate_producer_root_invalid", "production_closure",
      "candidate producer root is missing or indirect");
  }
  const safe = safeCandidateRelativePath(relativePath, "candidate_producer_path_invalid");
  const filePath = path.resolve(resolvedRoot, safe.replace(/\//g, path.sep));
  if (!filePath.toLowerCase().startsWith((resolvedRoot + path.sep).toLowerCase())) {
    fail("candidate_producer_path_invalid", "production_closure",
      "candidate producer evidence escaped the exact candidate root");
  }
  let stat;
  let real;
  try {
    stat = fs.lstatSync(filePath);
    real = fs.realpathSync.native(filePath);
  } catch (_error) {
    fail("candidate_producer_file_missing", "production_closure",
      "candidate producer evidence file is missing", { relativePath: safe });
  }
  if (!stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || stat.size < (allowEmpty === true ? 0 : 1) || stat.size > maximumBytes) {
    fail("candidate_producer_file_invalid", "production_closure",
      "candidate producer evidence is not one bounded exact regular file", { relativePath });
  }
  const bytes = fs.readFileSync(filePath);
  return { filePath, bytes, sha256: sha256Bytes(bytes).toUpperCase(), size: bytes.length };
}

function computeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash) {
  return sha256Text("artifactSourceHash\t" + normalizedHash(artifactSourceHash, "artifactSourceHash")
    + "\nproducerRecipeHash\t" + normalizedHash(producerRecipeHash, "producerRecipeHash")
    + "\ntoolchainLockHash\t" + normalizedHash(toolchainLockHash, "toolchainLockHash") + "\n")
    .toUpperCase();
}

function excludedPayloadPath(relativePath, payload) {
  return payload.excludePaths.includes(relativePath)
    || payload.excludePrefixes.some((prefix) => relativePath.startsWith(prefix));
}

function enumerateCandidatePayload(candidateRoot, payload) {
  if (!payload || !Array.isArray(payload.fixedRoots) || !Array.isArray(payload.trees)
      || !Array.isArray(payload.excludePaths) || !Array.isArray(payload.excludePrefixes)) {
    fail("candidate_payload_config_invalid", "production_closure",
      "candidate payload inventory lacks the canonical runtime-input declaration");
  }
  const normalized = {
    fixedRoots: payload.fixedRoots.map((entry) => safeCandidateRelativePath(entry,
      "candidate_payload_config_invalid")),
    trees: payload.trees.map((entry) => safeCandidateRelativePath(entry,
      "candidate_payload_config_invalid")),
    excludePaths: payload.excludePaths.map((entry) => safeCandidateRelativePath(entry,
      "candidate_payload_config_invalid")),
    excludePrefixes: payload.excludePrefixes.map((entry) => safeCandidateRelativePath(entry,
      "candidate_payload_config_invalid")),
  };
  const values = new Set();
  normalized.fixedRoots.forEach((relativePath) => {
    if (!excludedPayloadPath(relativePath, normalized)) values.add(relativePath);
  });
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const relative = tree + "/" + (base ? base + "/" : "") + entry.name;
      const full = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) fail("candidate_payload_file_invalid", "production_closure",
        "candidate payload contains a symbolic link", { path: relative });
      if (entry.isDirectory()) { walk(full, (base ? base + "/" : "") + entry.name, tree); return; }
      if (entry.isFile() && !excludedPayloadPath(relative, normalized)) values.add(relative);
    });
  }
  normalized.trees.forEach((tree) => {
    const directory = path.resolve(candidateRoot, tree.replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(directory); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("candidate_payload_tree_invalid", "production_closure",
        "candidate payload tree is missing or indirect", { tree });
    }
    walk(directory, "", tree);
  });
  return Array.from(values).sort().map((relativePath) => {
    const file = exactCandidateFile(candidateRoot, relativePath, 1024 * 1024 * 1024, true);
    return { path: relativePath, size: file.size, sha256: file.sha256 };
  });
}

function canonicalPayloadClosureHash(files) {
  const sorted = files.slice().sort((left, right) => left.path < right.path ? -1
    : left.path > right.path ? 1 : 0);
  if (!sorted.length || new Set(sorted.map((entry) => String(entry.path).toLowerCase())).size
      !== sorted.length || canonicalJson(files) !== canonicalJson(sorted)) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload file rows are empty, duplicated, or unordered");
  }
  const canonical = sorted.map((row) => {
    const relative = safeCandidateRelativePath(row.path, "candidate_payload_manifest_invalid");
    const size = Number(row.size);
    const digest = normalizedHash(row.sha256, "payload.sha256");
    if (!Number.isSafeInteger(size) || size < 0) fail("candidate_payload_manifest_invalid",
      "production_closure", "candidate payload size is malformed", { relative, size });
    return relative + "\t" + size + "\t" + digest;
  }).join("\n") + "\n";
  return sha256Text(canonical).toUpperCase();
}

function parseCandidateManifest(candidateRoot, manifestFile, payload) {
  const lines = manifestFile.bytes.toString("utf8").replace(/\r/g, "").split("\n");
  if (lines.pop() !== "" || lines.shift() !== "cf7-runtime-manifest-v2") {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest header or terminal newline is unsupported");
  }
  const metadataNames = ["publishMode", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "toolchainBaseline", "buildIdentityHash", "payloadClosureHash"];
  const metadata = Object.create(null);
  const files = [];
  lines.forEach((line) => {
    const fields = line.split("\t");
    if (fields[0] === "file") {
      if (fields.length !== 4 || !/^\d+$/.test(fields[2])) fail("candidate_payload_manifest_invalid",
        "production_closure", "candidate payload row is malformed");
      files.push({ path: safeCandidateRelativePath(fields[1], "candidate_payload_manifest_invalid"),
        size: Number(fields[2]), sha256: normalizedHash(fields[3], "payload.sha256") });
      return;
    }
    if (fields.length !== 2 || !metadataNames.includes(fields[0])
        || Object.prototype.hasOwnProperty.call(metadata, fields[0]) || !fields[1]) {
      fail("candidate_producer_manifest_invalid", "production_closure",
        "candidate runtime manifest metadata is missing, duplicated, or extra", { line });
    }
    metadata[fields[0]] = fields[1];
  });
  if (Object.keys(metadata).length !== metadataNames.length
      || metadata.publishMode !== "framework-dependent" || !metadata.toolchainBaseline.trim()) {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest metadata set is incomplete or unsupported");
  }
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((name) => { metadata[name] = normalizedHash(metadata[name], name); });
  const actualFiles = enumerateCandidatePayload(candidateRoot, payload);
  if (canonicalJson(files) !== canonicalJson(files.slice().sort((left, right) =>
    left.path < right.path ? -1 : left.path > right.path ? 1 : 0))) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload rows are not in canonical ordinal order");
  }
  if (canonicalJson(files) !== canonicalJson(actualFiles)) fail("candidate_payload_file_mismatch",
    "production_closure", "candidate payload manifest differs from exact candidate files");
  if (canonicalPayloadClosureHash(files) !== metadata.payloadClosureHash) {
    fail("candidate_payload_closure_mismatch", "production_closure",
      "candidate payload closure differs from its exact manifest rows");
  }
  return { metadata, files };
}

function normalizedHash(value, field) {
  const normalized = String(value || "").toUpperCase();
  if (!SHA256_RE.test(normalized)) {
    fail("candidate_producer_hash_invalid", "production_closure",
      "candidate producer field is not SHA-256", { field });
  }
  return normalized;
}

function captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure) {
  const metadataFile = exactCandidateFile(candidateRoot, "runtime-build-metadata.v2.json", 64 * 1024);
  const manifestFile = exactCandidateFile(candidateRoot,
    "runtime/cf7-runtime-manifest.tsv", 8 * 1024 * 1024);
  let metadata;
  try { metadata = JSON.parse(metadataFile.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (_error) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata is not valid JSON");
  }
  const metadataKeys = ["schema", "builderLabel", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "buildIdentityHash", "payloadClosureHash", "createdAtUtc"].sort();
  if (!metadata || metadata.schema !== "cf7-runtime-candidate-metadata.v2"
      || canonicalJson(Object.keys(metadata).sort()) !== canonicalJson(metadataKeys)
      || typeof metadata.builderLabel !== "string" || !metadata.builderLabel.trim()
      || !Number.isFinite(Date.parse(metadata.createdAtUtc))) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata does not have the exact v2 producer schema");
  }
  const hashes = {};
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((field) => { hashes[field] = normalizedHash(metadata[field], field); });
  const parsed = parseCandidateManifest(candidateRoot, manifestFile, closure.producerInputs.payload);
  if (Object.keys(hashes).some((field) => parsed.metadata[field] !== hashes[field])) {
    fail("candidate_producer_manifest_mismatch", "production_closure",
      "candidate metadata and runtime manifest identity rows differ");
  }
  const expectedBuildIdentity = computeBuildIdentityHash(hashes.artifactSourceHash,
    hashes.producerRecipeHash, hashes.toolchainLockHash);
  const current = closure.producerInputs;
  if (hashes.buildIdentityHash !== expectedBuildIdentity
      || !current || !current.domains
      || hashes.artifactSourceHash !== current.domains.artifactSource.hash
      || hashes.producerRecipeHash !== current.domains.producerRecipe.hash
      || hashes.toolchainLockHash !== current.domains.toolchainLock.hash
      || hashes.buildIdentityHash !== current.buildIdentityHash
      || hashes.buildIdentityHash !== normalizedHash(candidateIdentity.buildIdentity, "candidateIdentity.buildIdentity")
      || hashes.payloadClosureHash !== normalizedHash(candidateIdentity.payloadClosure, "candidateIdentity.payloadClosure")) {
    fail("candidate_producer_identity_mismatch", "production_closure",
      "candidate producer/source identity is detached from current tree or authenticated runtime");
  }
  const core = parsed.files.filter((entry) => entry.path.toLowerCase()
    === "runtime/crazyflasher7mercenaryempire.core.dll");
  if (core.length !== 1 || core[0].sha256 !== normalizedHash(candidateIdentity.coreSha256,
    "candidateIdentity.coreSha256")) {
    fail("candidate_core_identity_mismatch", "production_closure",
      "candidate process identity is detached from the payload manifest Core DLL row");
  }
  const resolvedCandidateRoot = path.resolve(candidateRoot);
  const processPath = path.resolve(candidateIdentity.processPath || "");
  const processRelative = path.relative(resolvedCandidateRoot, processPath).replace(/\\/g, "/");
  if (!processRelative || processRelative.startsWith("../") || path.isAbsolute(processRelative)
      || parsed.files.filter((entry) => entry.path.toLowerCase()
        === processRelative.toLowerCase()).length !== 1
      || path.resolve(candidateIdentity.installRoot || "").toLowerCase()
        !== resolvedCandidateRoot.toLowerCase()) {
    fail("candidate_process_identity_mismatch", "production_closure",
      "authenticated process path/install root is not one exact payload manifest file");
  }
  const value = { schema: CANDIDATE_PRODUCER_SCHEMA, candidateRoot: path.resolve(candidateRoot),
    metadata: { locator: "candidate:runtime-build-metadata.v2.json",
      sha256: metadataFile.sha256, bytes: metadataFile.size },
    manifest: { locator: "candidate:runtime/cf7-runtime-manifest.tsv",
      sha256: manifestFile.sha256, bytes: manifestFile.size },
    builderLabel: metadata.builderLabel, createdAtUtc: metadata.createdAtUtc,
    producerInputsSha256: current.inputsSha256,
    artifactSourceHash: hashes.artifactSourceHash,
    producerRecipeHash: hashes.producerRecipeHash,
    toolchainLockHash: hashes.toolchainLockHash,
    buildIdentityHash: hashes.buildIdentityHash,
    payloadClosureHash: hashes.payloadClosureHash,
    payloadFileCount: parsed.files.length };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function verifyCandidateProducerBinding(candidateRoot, candidateIdentity, closure, evidence) {
  const current = captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure);
  if (!evidence || evidence.schema !== CANDIDATE_PRODUCER_SCHEMA
      || canonicalJson(current) !== canonicalJson(evidence)) {
    fail("candidate_producer_evidence_mismatch", "production_closure",
      "captured candidate producer evidence differs from exact current files");
  }
  return evidence;
}

function bindProductionClosure(closure, candidateIdentity, runId, candidateProducer) {
  const identity = {
    runtimeMode: candidateIdentity.runtimeMode,
    processPath: path.resolve(candidateIdentity.processPath || ""),
    coreSha256: candidateIdentity.coreSha256,
    buildIdentity: candidateIdentity.buildIdentity,
    payloadClosure: candidateIdentity.payloadClosure,
  };
  const value = { schema: BINDING_SCHEMA, runId,
    productionClosureSha256: closure.closureSha256,
    candidateIdentitySha256: sha256Text(canonicalJson(identity)),
    candidateProducerSha256: candidateProducer && candidateProducer.evidenceSha256 };
  value.bindingSha256 = sha256Text(canonicalJson(value));
  return value;
}

function webFiles(closure) {
  return closure.files.filter((entry) => ["page", "overlay_script", "lazy_registry", "kshop_lazy_web",
    "style_entry", "style_import"]
    .includes(entry.role));
}

function scriptFiles(closure) {
  return webFiles(closure).filter((entry) => ["overlay_script", "lazy_registry", "kshop_lazy_web"]
    .includes(entry.role));
}

function styleFiles(closure) {
  return webFiles(closure).filter((entry) => ["style_entry", "style_import"].includes(entry.role));
}

function idlePrewarmFiles(closure) {
  return closure.files.filter((entry) => entry.role === "idle_prewarm_image");
}

function cssConditionalAssetFiles(closure) {
  return closure.files.filter((entry) => entry.role === "css_conditional_asset");
}

function cssConditionalResourceSet(closure) {
  function mimeType(locator) {
    const extension = path.posix.extname(locator).toLowerCase();
    if (extension === ".png") return "image/png";
    if ([".jpg", ".jpeg"].includes(extension)) return "image/jpeg";
    if (extension === ".svg") return "image/svg+xml";
    if (extension === ".webp") return "image/webp";
    return "";
  }
  return cssConditionalAssetFiles(closure).map((entry) => ({
    locator: entry.locator,
    url: "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length),
    type: "Image", urlOrigin: "https://overlay.local", mimeType: mimeType(entry.locator),
    sha256: entry.sha256, bytes: entry.bytes,
  }));
}

function declaredFontResources(closure) {
  const fontPack = closure && closure.declarations && closure.declarations.fontPack;
  if (!fontPack || !Array.isArray(fontPack.resources)) {
    fail("production_font_declaration_invalid", "production_closure",
      "production closure lacks its exact font-pack projection");
  }
  return fontPack.resources.map((entry) => Object.assign({}, entry));
}

function fontSourceRoots(root) {
  return [
    { source: "temporary/custom", root: path.resolve(root, "fonts", "temporary", "custom"), custom: true },
    { source: "temporary/cache", root: path.resolve(root, "fonts", "temporary", "cache"), custom: false },
    { source: "permanent/runtime", root: path.resolve(root, "fonts", "permanent", "runtime"), custom: false },
  ];
}

function captureFontEnvironment(root, closure, environment) {
  void environment;
  const sourceRoots = fontSourceRoots(root);
  const resources = declaredFontResources(closure);
  const manifest = requireObjectFile(closure.files, "font_pack_manifest",
    "production_font_declaration_invalid");
  const fingerprint = resources.flatMap((entry) => sourceRoots.map((candidate) => {
    const filePath = path.resolve(candidate.root, entry.name);
    let stat;
    try { stat = fs.lstatSync(filePath); } catch (_error) { stat = null; }
    return candidate.source + ":" + entry.name + ":" + (stat ? [stat.size, stat.mtimeMs,
      stat.isFile(), stat.isSymbolicLink()].join(":") : "missing");
  })).join("|");
  const cacheKey = sourceRoots.map((entry) => entry.root.toLowerCase()).join("|")
    + "|" + manifest.sha256;
  const cached = fontEnvironmentCache.get(cacheKey);
  if (cached && cached.fingerprint === fingerprint) {
    return JSON.parse(JSON.stringify(cached.value));
  }
  const installed = [];
  resources.forEach((entry) => {
    for (const candidate of sourceRoots) {
      const filePath = path.resolve(candidate.root, entry.name);
      let stat;
      let real;
      try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
      catch (_error) { stat = null; real = null; }
      if (!stat) continue;
      if (!stat.isFile() || stat.isSymbolicLink() || path.resolve(real) !== filePath) {
        fail("font_environment_file_invalid", "production_closure",
          "font candidate is not one exact regular file", { name: entry.name, source: candidate.source });
      }
      const bytes = fs.readFileSync(filePath);
      const digest = sha256Bytes(bytes);
      if (!candidate.custom && (bytes.length !== entry.bytes || digest !== entry.sha256)) continue;
      installed.push({ name: entry.name, url: entry.url, path: filePath, source: candidate.source,
        integrity: candidate.custom ? "custom-override" : "verified",
        bytes: bytes.length, sha256: digest });
      break;
    }
  });
  const value = { schema: FONT_ENVIRONMENT_SCHEMA,
    sourceRoots: sourceRoots.map((entry) => ({ source: entry.source, root: entry.root })),
    manifestLocator: manifest.locator, manifestSha256: manifest.sha256, installed };
  value.environmentSha256 = sha256Text(canonicalJson(value));
  fontEnvironmentCache.set(cacheKey, { fingerprint, value });
  return JSON.parse(JSON.stringify(value));
}

function requireObjectFile(files, role, code) {
  const matches = (files || []).filter((entry) => entry && entry.role === role);
  if (matches.length !== 1) {
    fail(code, "production_closure", "production closure lacks one exact role", { role });
  }
  return matches[0];
}

function verifyFontEnvironment(root, closure, evidence, environment) {
  const current = captureFontEnvironment(root, closure, environment || process.env);
  if (!evidence || evidence.schema !== FONT_ENVIRONMENT_SCHEMA
      || canonicalJson(current) !== canonicalJson(evidence)) {
    fail("font_environment_mismatch", "production_closure",
      "loaded font mapping evidence differs from the current installed manifest subset");
  }
  return evidence;
}

function iconFrameUri(frame) {
  return frame && (frame.uri || frame.file || frame.filename) || null;
}

function normalizedIconFrames(entry) {
  const raw = Array.isArray(entry.timelineFrames) && entry.timelineFrames.length
    ? entry.timelineFrames : Array.isArray(entry.frames) ? entry.frames : [];
  const frames = [];
  const seen = new Set();
  raw.forEach((frame, index) => {
    const uri = iconFrameUri(frame);
    if (!uri) return;
    const number = frame.frame || frame.index || index + 1;
    frames.push(Object.assign({}, frame, { frame: number, uri }));
    seen.add(String(number));
  });
  if (entry.f1 && !seen.has("1")) frames.unshift({ frame: 1, uri: entry.f1 });
  if (entry.f2 && !seen.has("2")) frames.push({ frame: 2, uri: entry.f2 });
  return frames.sort((left, right) => Number(left.frame || 0) - Number(right.frame || 0));
}

function normalizedLayerFrames(layer) {
  let raw = Array.isArray(layer && layer.timelineFrames) && layer.timelineFrames.length
    ? layer.timelineFrames : Array.isArray(layer && layer.frames) ? layer.frames : [];
  if ((!raw || !raw.length) && layer && layer.export) {
    raw = Array.isArray(layer.export.timelineFrames) && layer.export.timelineFrames.length
      ? layer.export.timelineFrames : Array.isArray(layer.export.frames) ? layer.export.frames : [];
  }
  return (raw || []).map((frame, index) => Object.assign({}, frame, {
    frame: frame.frame || frame.index || index + 1, uri: iconFrameUri(frame),
  })).filter((frame) => frame.uri)
    .sort((left, right) => Number(left.frame || 0) - Number(right.frame || 0));
}

function distinctIconFrames(frames) {
  const keys = ["uri", "cropX", "cropY", "cropWidth", "cropHeight",
    "canvasWidth", "canvasHeight"];
  return new Set(frames.map((frame) => canonicalJson(keys.map((key) =>
    Object.prototype.hasOwnProperty.call(frame, key) ? frame[key] : null)))).size;
}

function iconEntryUris(entry) {
  if (entry.format === "webp-animated") {
    const frames = normalizedIconFrames(entry);
    const uri = entry.uri || frames[0] && frames[0].uri || entry.f1;
    return uri ? [uri] : [];
  }
  const nested = entry.nestedAnimation && typeof entry.nestedAnimation === "object"
    ? entry.nestedAnimation : null;
  const layers = nested && Array.isArray(nested.layers) ? nested.layers : [];
  const base = nested && (typeof nested.base === "string" ? nested.base
    : nested.base && nested.base.uri) || entry.f1 || null;
  if (layers.length && base) {
    const values = [base];
    layers.forEach((layer) => normalizedLayerFrames(layer).forEach((frame) => {
      values.push(frame.uri);
    }));
    return Array.from(new Set(values));
  }
  const frames = normalizedIconFrames(entry);
  if (!frames.length) return [];
  const staticPlayback = ["static", "static-first-frame"].includes(entry.playback);
  const animated = !staticPlayback && distinctIconFrames(frames) > 1
    && (entry.animated === true || !!entry.playback);
  return Array.from(new Set((animated ? frames : frames.slice(0, 1))
    .map((frame) => frame.uri)));
}

function iconResourceSetForNames(root, closure, iconNames) {
  const manifestFile = requireObjectFile(closure.files, "icon_manifest",
    "production_icon_manifest_invalid");
  const currentManifest = exactFile(root, {
    role: "icon_manifest", relativePath: "launcher/web/icons/manifest.json",
  });
  if (canonicalJson(currentManifest) !== canonicalJson(manifestFile)) {
    fail("production_icon_manifest_mismatch", "production_closure",
      "icon manifest differs from the bound production closure");
  }
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(path.resolve(root,
      "launcher", "web", "icons", "manifest.json"), "utf8").replace(/^\uFEFF/, ""));
  } catch (_error) { manifest = null; }
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    fail("production_icon_manifest_invalid", "production_closure",
      "icon manifest cannot be parsed");
  }
  const names = [];
  (iconNames || []).forEach((value) => {
    const name = String(value || "").trim();
    if (name && !names.includes(name)) names.push(name);
  });
  const bindings = [];
  const resourceByUrl = new Map();
  names.forEach((iconName) => {
    const entry = manifest[iconName];
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      fail("dynamic_icon_name_unbound", "production_closure",
        "authoritative catalog/inventory iconName is absent from the current icon manifest", {
          iconName,
        });
    }
    const uris = iconEntryUris(entry);
    if (!uris.length) {
      fail("dynamic_icon_entry_empty", "production_closure",
        "authoritative iconName resolves to no production image", { iconName });
    }
    const urls = [];
    uris.forEach((uri) => {
      const normalized = String(uri || "").replace(/\\/g, "/");
      if (!normalized || normalized.startsWith("/") || /^[a-z][a-z0-9+.-]*:/i.test(normalized)
          || normalized.split("/").some((part) => !part || part === "." || part === "..")
          || ![".png", ".webp"].includes(path.posix.extname(normalized).toLowerCase())) {
        fail("dynamic_icon_uri_invalid", "production_closure",
          "manifest icon URI is not one bounded PNG/WebP", { iconName, uri });
      }
      const relativePath = "launcher/web/icons/" + normalized;
      const file = exactFile(root, { role: "dynamic_icon_asset", relativePath });
      const url = "https://overlay.local/icons/" + normalized;
      const resource = { locator: file.locator, url, type: "Image",
        urlOrigin: "https://overlay.local",
        mimeType: path.posix.extname(normalized).toLowerCase() === ".png"
          ? "image/png" : "image/webp",
        sha256: file.sha256, bytes: file.bytes };
      urls.push(url);
      if (!resourceByUrl.has(url)) resourceByUrl.set(url, resource);
    });
    bindings.push({ iconName, urls });
  });
  return { schema: ICON_PROJECTION_SCHEMA,
    manifestLocator: manifestFile.locator, manifestSha256: manifestFile.sha256,
    iconNames: names, bindings,
    // Preserve authority-name/manifest-frame insertion order.  Page occurrence
    // verification consumes this exact sequence; URL sorting would erase a
    // cross-layer or within-icon reorder.
    resources: Array.from(resourceByUrl.values()) };
}

function expectedStaticResourceSet(closure) {
  const overlayUrl = "https://overlay.local/overlay.html";
  function url(entry) {
    return "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length);
  }
  return [{ url: overlayUrl, type: "Document", urlOrigin: "https://overlay.local" }]
    .concat(styleFiles(closure).map((entry) => ({
      url: url(entry), type: "Stylesheet", urlOrigin: "https://overlay.local",
    })))
    .concat(scriptFiles(closure).map((entry) => ({
      url: url(entry), type: "Script", urlOrigin: "https://overlay.local",
    })))
    .concat(idlePrewarmFiles(closure).map((entry) => ({
      url: url(entry), type: "Image", urlOrigin: "https://overlay.local",
    })));
}

function expectedExecutableOccurrences(closure) {
  const files = new Map(scriptFiles(closure).map((entry) => [entry.locator.slice(5), entry]));
  const overlay = closure && closure.declarations;
  if (!overlay || !Array.isArray(overlay.scriptExecutionOrder)
      || !Array.isArray(overlay.declaredLazyWeb)) {
    fail("production_executable_declaration_invalid", "production_closure",
      "production closure lacks exact executable declaration order");
  }
  const occurrences = overlay.scriptExecutionOrder.map((entry) => {
    if (entry.kind === "inline") return { kind: "inline", role: "page_inline_script",
      locator: "root:launcher/web/overlay.html#inline-" + entry.inlineIndex,
      url: "https://overlay.local/overlay.html", sha256: entry.sha256, bytes: entry.bytes };
    const file = files.get(entry.relativePath);
    if (!file) fail("production_executable_declaration_invalid", "production_closure",
      "Overlay executable declaration is outside the exact Web closure", entry);
    return { kind: "external", role: file.role, locator: file.locator,
      url: "https://overlay.local/" + entry.relativePath.slice("launcher/web/".length),
      sha256: file.sha256, bytes: file.bytes };
  });
  overlay.declaredLazyWeb.forEach((relativePath) => {
    const file = files.get(relativePath);
    if (!file) fail("production_executable_declaration_invalid", "production_closure",
      "lazy executable declaration is outside the exact Web closure", { relativePath });
    occurrences.push({ kind: "external", role: file.role, locator: file.locator,
      url: "https://overlay.local/" + relativePath.slice("launcher/web/".length),
      sha256: file.sha256, bytes: file.bytes });
  });
  return occurrences;
}

module.exports = {
  BINDING_SCHEMA,
  CATALOG_DELIVERY_SCHEMA,
  CANDIDATE_PRODUCER_SCHEMA,
  CLOSURE_SCHEMA,
  FONT_ENVIRONMENT_SCHEMA,
  ICON_PROJECTION_SCHEMA,
  INVENTORY_SURFACE_CONTRACT_SCHEMA,
  INVENTORY_SURFACE_SOURCE_SCHEMA,
  ITEMUTIL_DELIVERY_SOURCE_SCHEMA,
  PRODUCER_INPUTS_SCHEMA,
  REQUIRED_KSHOP_LAZY_WEB,
  LOADED_SCHEMA,
  PRODUCTION_FILES,
  bindProductionClosure,
  captureInventoryPhysicalSurfaceContract,
  captureItemUtilDeliverySourceContract,
  captureFontEnvironment,
  captureCandidateProducerBinding,
  captureProductionClosure,
  currentProducerInputs,
  cssConditionalAssetFiles,
  cssConditionalResourceSet,
  declaredFontResources,
  extractAs2Function,
  iconResourceSetForNames,
  inspectInventorySurfaceSourceContract,
  expectedStaticResourceSet,
  verifyCatalogDeliveryContract,
  verifyItemUtilDeliverySourceContract,
  verifyBuildFileInventory,
  verifyProductionClosure,
  verifyCandidateProducerBinding,
  verifyFontEnvironment,
  verifyInventoryPhysicalSurfaceContract,
  expectedExecutableOccurrences,
  idlePrewarmFiles,
  scriptFiles,
  styleFiles,
  webFiles,
};
