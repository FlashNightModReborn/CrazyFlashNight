#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const CloneSaveGuard = require("../lib/clone-save-guard");
const SharedEvidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const {
  TOOL_SCHEMA,
  LIVE_SLOT_RE,
  assertNoRawTokens,
  assertSafeSeed,
  assertSafeSlot,
  atomicWriteJson,
  buildRawBundleManifest,
  canonicalJson,
  chooseCatalogSelection,
  fail,
  sha256Text,
  sleep,
  timestampId,
} = require("./common");
const { TranscriptWriter, attachPassiveObserver } = require("./cdp-passive-observer");
const { ControlChannel } = require("./control-channel");
const {
  openGenericRuntime,
  releaseGenericClone,
  restartGenericRuntime,
} = require("./generic-opener");
const { finalizePreSealVerification, validateInventorySurface,
  verifyBundlePreSeal } = require("./evidence-verifier");
const ProductionClosure = require("./production-closure");

const ROOT = path.resolve(__dirname, "..", "..", "..");
const DEFAULT_SEED_SLOT = "cf7_agent_a3_kshop";
const DEFAULT_TARGET_SLOT = "cf7_agent_a3_kshop_run";
const CDP_TRUSTED_EXPECTATIONS = Object.freeze({
  expectedPageUrl: "https://overlay.local/overlay.html",
  expectedPageOrigin: "https://overlay.local",
  expectedUserDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
  expectedListenerExecutableName: "msedgewebview2.exe",
});
const CONTROL_ACTIONS = Object.freeze({
  open_kshop: { action: "open_kshop", expectedWebCommands: ["bulkQuery", "snapshot"] },
  add_selected_item: { action: "add_selected_item", expectedWebCommands: ["saveCart"] },
  open_checkout: { action: "open_checkout", expectedWebCommands: ["checkoutPreview"] },
  commit_checkout: { action: "commit_checkout", expectedWebCommands: ["checkoutCommit", "snapshot"] },
  close_kshop: { action: "close_kshop", expectedWebCommands: ["close"] },
  safe_exit: { action: "safe_exit", expectedWebCommands: [] },
  exit_confirm: { action: "exit_confirm", expectedWebCommands: [] },
  restart_readback_open_kshop: { action: "open_kshop", expectedWebCommands: ["bulkQuery", "snapshot"] },
  restart_readback_close_kshop: { action: "close_kshop", expectedWebCommands: ["close"] },
});

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = {
    seedSlot: DEFAULT_SEED_SLOT,
    slot: DEFAULT_TARGET_SLOT,
    candidateRoot: null,
    allowReadOnlyLiveSeed: false,
    allowIsolatedPurchase: false,
    allowCodexCuFallback: false,
    readyTimeoutMs: 180000,
    operatorTimeoutMs: 900000,
    evidenceTimeoutMs: 60000,
    cloneBaselineTimeoutMs: 30000,
    cloneBaselineStableMs: 2000,
    pollMs: 250,
    check: false,
    help: false,
  };
  function take(index, flag) {
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) usage(flag + " requires a value");
    return value;
  }
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--help" || token === "-h") args.help = true;
    else if (token === "--check") args.check = true;
    else if (token === "--candidate-root") args.candidateRoot = take(index++, token);
    else if (token === "--seed-slot") args.seedSlot = take(index++, token);
    else if (token === "--slot") args.slot = take(index++, token);
    else if (token === "--existing-slot") usage("--existing-slot is retired: every live journey must prepare and prove a fresh full JSON+SOL clone");
    else if (token === "--allow-read-only-live-seed") args.allowReadOnlyLiveSeed = true;
    else if (token === "--allow-isolated-purchase") args.allowIsolatedPurchase = true;
    else if (token === "--allow-codex-cu-fallback") args.allowCodexCuFallback = true;
    else if (["--ready-timeout-ms", "--operator-timeout-ms", "--evidence-timeout-ms",
      "--clone-baseline-timeout-ms", "--clone-baseline-stable-ms", "--poll-ms"].includes(token)) {
      const key = token.slice(2).replace(/-([a-z])/g, (_m, letter) => letter.toUpperCase());
      args[key] = Number(take(index++, token));
    } else usage("unknown argument: " + token);
  }
  return args;
}

function validateArgs(args) {
  if (args.check || args.help) return args;
  assertSafeSlot(args.slot);
  assertSafeSeed(args.seedSlot, args.slot);
  if (LIVE_SLOT_RE.test(args.seedSlot) && args.allowReadOnlyLiveSeed !== true) {
    usage("a live save may only be used as a read-only seed with --allow-read-only-live-seed");
  }
  if (!args.candidateRoot) usage("--candidate-root is required; KShop purchase E2E never uses formal runtime");
  if (!args.allowIsolatedPurchase) {
    usage("--allow-isolated-purchase is required for the one explicitly bounded clone purchase");
  }
  if (!args.allowCodexCuFallback) {
    usage("--allow-codex-cu-fallback is required: this recorder uses legacy HTTP control, which disables Launcher Agent Runtime admission");
  }
  ["readyTimeoutMs", "operatorTimeoutMs", "evidenceTimeoutMs", "cloneBaselineTimeoutMs",
    "cloneBaselineStableMs", "pollMs"].forEach((key) => {
    if (!Number.isFinite(args[key]) || args[key] < 100 || args[key] > 3600000) {
      usage("invalid timeout: " + key);
    }
  });
  return args;
}

function printHelp() {
  console.log([
    "KShop isolated live journey recorder (tooling only)",
    "",
    "Usage:",
    "  node tools/workbench-live-e2e/kshop/bootstrap.js \\",
    "    --candidate-root <tmp/runtime-candidates/v2/direct-child> \\",
    "    --allow-isolated-purchase --allow-codex-cu-fallback",
    "",
    "Defaults: --seed-slot " + DEFAULT_SEED_SLOT + " --slot " + DEFAULT_TARGET_SLOT,
    "Existing-slot reuse is retired: every run prepares a fresh full JSON+SOL clone.",
    "A live player slot is never a target. A live seed needs explicit read-only authorization.",
    "The runner never calls KShop business APIs and never synthesizes clicks. It emits bounded",
    "control requests and waits for Launcher Agent Runtime computer use, or the explicitly allowed",
    "Codex computer-use fallback, while CDP and Host/AS2 evidence are observed independently.",
  ].join("\n"));
}

function exactRunDirectory(slot) {
  const base = path.join(ROOT, "tmp", "workbench-live-e2e", "kshop");
  fs.mkdirSync(base, { recursive: true });
  SharedEvidence.assertExactDirectory(base, "run_directory");
  const runDir = path.join(base, timestampId() + "-" + slot);
  fs.mkdirSync(runDir);
  SharedEvidence.assertOwnedRunDirectory(ROOT, runDir,
    path.join("tmp", "workbench-live-e2e", "kshop"), "run_directory");
  return runDir;
}

function publicError(error) {
  return {
    code: error.code || "unhandled_error",
    phase: error.phase || "unknown",
    message: String(error.message || error),
    details: error.details || null,
  };
}

function residueWithMethod(evidence, method) {
  const value = Object.assign({}, evidence, { method });
  delete value.evidenceSha256;
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function messageOf(event) {
  if (!event || !["bridge_send", "webview_message"].includes(event.kind)) return null;
  if (event.message && typeof event.message === "object" && !Array.isArray(event.message)) return event.message;
  if (typeof event.message !== "string") return null;
  try { return JSON.parse(event.message); } catch (_error) { return null; }
}

function eventEntries(writer, kind) {
  return writer.events.map((event) => ({ event, message: messageOf(event) }))
    .filter((entry) => entry.event.kind === kind && entry.message);
}

function findResponse(writer, requestEntry) {
  return eventEntries(writer, "webview_message").find((entry) => entry.event.sequence
    > requestEntry.event.sequence && entry.message.type === "panel_resp"
    && entry.message.panel === "kshop"
    && entry.message.panelInstanceId === requestEntry.message.panelInstanceId
    && entry.message.callId === requestEntry.message.callId
    && entry.message.cmd === requestEntry.message.cmd
    && (Object.prototype.hasOwnProperty.call(requestEntry.message, "domain")
      ? entry.message.domain === requestEntry.message.domain
      : !Object.prototype.hasOwnProperty.call(entry.message, "domain"))) || null;
}

function panelRequestEntries(writer, panelInstanceId, cmd, domain) {
  return eventEntries(writer, "bridge_send").filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "kshop" && entry.message.panelInstanceId === panelInstanceId
    && entry.message.cmd === cmd
    && (domain === "inventory" ? entry.message.domain === "inventory"
      : !Object.prototype.hasOwnProperty.call(entry.message, "domain")));
}

function exactCart(value, expectedCart) {
  if (!Array.isArray(value) || !Array.isArray(expectedCart)
      || value.length !== expectedCart.length) return false;
  const projected = value.map((entry) => ({ idx: Number(entry.idx), qty: Number(entry.qty) }))
    .sort((left, right) => left.idx - right.idx);
  const expected = expectedCart.map((entry) => ({ idx: Number(entry.idx), qty: Number(entry.qty) }))
    .sort((left, right) => left.idx - right.idx);
  return canonicalJson(projected) === canonicalJson(expected);
}

function assertLivePrePurchaseSnapshot(message) {
  if (!message || message.success !== true || !Array.isArray(message.cart)
      || message.cart.length !== 0 || !Array.isArray(message.catalog)
      || !Number.isFinite(Number(message.kpoints))) {
    fail("seed_shop_snapshot_invalid", "pre_purchase",
      "dedicated clone must expose an empty authoritative KShop snapshot");
  }
  const selection = chooseCatalogSelection(message.catalog, Number(message.kpoints),
    Number(message.playerLevel), Number(message.reverseLevel));
  return { balance: Number(message.kpoints), selection };
}

async function waitForEvidence(writer, label, timeoutMs, pollMs, predicate) {
  const deadline = Date.now() + timeoutMs;
  let value = null;
  while (Date.now() <= deadline) {
    value = predicate();
    if (value) return value;
    await sleep(pollMs);
  }
  fail("live_evidence_timeout", label, "independent evidence did not arrive within timeout");
}

function kshopOpens(writer, afterSequence) {
  return eventEntries(writer, "webview_message").filter((entry) => entry.event.sequence > afterSequence
    && entry.message.type === "panel_cmd" && entry.message.cmd === "open"
    && entry.message.panel === "kshop" && entry.message.panelInstanceId
    && entry.message.initData
    && entry.message.initData.panelInstanceId === entry.message.panelInstanceId);
}

function declaredInventoryPairCount(response) {
  const snapshots = response && response.message && response.message.snapshots;
  const battle = Array.isArray(snapshots) && snapshots.length === 2 ? snapshots[1] : null;
  const accessibleCapacity = Number(battle && battle.containerId === "战备箱"
    ? battle.accessibleCapacity : NaN);
  if (![0, 40, 80, 120, 160, 200, 240].includes(accessibleCapacity)) {
    fail("inventory_battle_access_invalid", "inventory",
      "the first live Inventory probe did not declare one production battle-box tier");
  }
  return 1 + (accessibleCapacity > 100 ? 1 : 0) + (accessibleCapacity > 200 ? 1 : 0);
}

async function waitForInventorySurface(writer, panelInstanceId, afterSequence,
  label, timeoutMs, pollMs) {
  return waitForEvidence(writer, label, timeoutMs, pollMs, () => {
    const requests = panelRequestEntries(writer, panelInstanceId, "snapshot", "inventory")
      .filter((entry) => entry.event.sequence > afterSequence);
    const firstRequest = requests[0];
    const firstResponse = firstRequest && findResponse(writer, firstRequest);
    if (!firstResponse) return null;
    const expectedCount = declaredInventoryPairCount(firstResponse);
    if (requests.length < expectedCount) return null;
    if (requests.length > expectedCount) {
      fail("inventory_surface_extra_call", "inventory",
        label + " issued an extra Inventory call beyond its declared tail");
    }
    const pairs = requests.slice(0, expectedCount)
      .map((request) => ({request, response: findResponse(writer, request)}));
    if (pairs.some((pair) => !pair.response)) return null;
    return validateInventorySurface(pairs, label);
  });
}

async function waitForPanelReady(writer, afterSequence, timeoutMs, pollMs, excludedIds,
  surfaceLabel) {
  const ready = await waitForEvidence(writer, "panel_ready", timeoutMs, pollMs, () => {
    const open = kshopOpens(writer, afterSequence).find((entry) => !(excludedIds || []).includes(
      entry.message.panelInstanceId));
    if (!open) return null;
    const id = open.message.panelInstanceId;
    const bulkRequest = panelRequestEntries(writer, id, "bulkQuery", "shop")[0];
    const bulk = bulkRequest && findResponse(writer, bulkRequest);
    if (!bulk || bulk.message.success !== true) return null;
    return { open, bulkRequest, bulk };
  });
  const inventorySurface = await waitForInventorySurface(writer,
    ready.open.message.panelInstanceId, ready.open.event.sequence,
    surfaceLabel || "initial inventory", timeoutMs, pollMs);
  return Object.assign(ready, {inventorySurface,
    inventoryRequest: inventorySurface.firstPair.request,
    inventory: inventorySurface.firstPair.response});
}

function issueNotice(runDir, request) {
  console.error("\n[KShop CU request] " + request.step);
  console.error("  " + path.join(runDir, "control", "current-request.json"));
  console.error("  requestId=" + request.requestId);
  console.error("  " + request.instructions);
}

async function controlStep(state, step, options) {
  const settings = Object.assign({}, options || {});
  const skipObserverHealth = settings.skipObserverHealth === true;
  delete settings.skipObserverHealth;
  const intent = CONTROL_ACTIONS[step];
  if (!intent) fail("control_action_unknown", "control", "control step has no fixed domain action", { step });
  const request = state.channel.issue(step, Object.assign({
    timeoutMs: state.args.operatorTimeoutMs,
    allowedTransports: [state.selectedTransport],
    runId: state.bundle.runId,
    domainIntent: { action: intent.action,
      browserSequenceStart: state.writer ? state.writer.events.length : 0,
      expectedWebCommands: intent.expectedWebCommands.slice() },
  }, settings));
  if (step === "commit_checkout" && typeof state.markCommitPossible === "function") {
    state.markCommitPossible();
  }
  state.bundle.controlRequests.push(request);
  issueNotice(state.runDir, request);
  state.persistDiagnostic();
  const exchange = await state.channel.wait(request, state.args.pollMs);
  const ack = exchange.ack;
  state.bundle.controlAcks.push(ack);
  state.bundle.controlProviderReceipts.push(exchange.providerReceipt);
  if (exchange.capture) state.bundle.controlCaptures.push(exchange.capture.capture);
  state.bundle.controlBindings.push({ requestId: request.requestId, step,
    runId: request.runId, action: request.domainIntent.action,
    browserSequenceStart: request.domainIntent.browserSequenceStart,
    browserSequenceEnd: state.writer ? state.writer.events.length : request.domainIntent.browserSequenceStart,
    requestSha256: sha256Text(canonicalJson(request)), ackSha256: sha256Text(canonicalJson(ack)) });
  state.persistDiagnostic();
  if (ack.result !== "completed") {
    fail("operator_step_failed", "control", "operator did not complete " + step, ack);
  }
  if (!skipObserverHealth) await state.observer.health();
  return { request, ack, providerReceipt: exchange.providerReceipt,
    capture: exchange.capture ? exchange.capture.capture : null };
}

async function waitForTrustedSelectionAndSavedCart(state, panelInstanceId, afterSequence, selection) {
  return waitForEvidence(state.writer, "target_cart", state.args.evidenceTimeoutMs,
    state.args.pollMs, () => {
      const clicks = state.writer.events.filter((event) => event.sequence > afterSequence
        && event.kind === "dom_input" && event.eventType === "click" && event.isTrusted === true
        && event.target && event.target.attributes);
      const targetClicks = selection.cart.map((target) => clicks.find((event) =>
        String(event.target.attributes["data-idx"]) === String(target.idx)
        && String(event.target.attributes.class || "").split(/\s+/).includes("kshop-add-btn")));
      if (targetClicks.some((entry) => !entry)) return null;
      const saved = panelRequestEntries(state.writer, panelInstanceId, "saveCart", "shop")
        .map((request) => ({ request, response: findResponse(state.writer, request) }))
        .find((pair) => pair.response && pair.response.message.success === true
          && exactCart(pair.response.message.cart, selection.cart));
      return saved ? { targetClicks, saved } : null;
    });
}

async function waitForPreview(state, panelInstanceId, afterSequence, selection) {
  return waitForEvidence(state.writer, "checkout_preview", state.args.evidenceTimeoutMs,
    state.args.pollMs, () => {
      const request = panelRequestEntries(state.writer, panelInstanceId, "checkoutPreview", "shop")
        .find((entry) => entry.event.sequence > afterSequence
          && exactCart(entry.message.cart, selection.cart));
      const response = request && findResponse(state.writer, request);
      return response && response.message.success === true && response.message.canCommit === true
        ? { request, response } : null;
    });
}

async function waitForCommitAndInventory(state, panelInstanceId, afterSequence) {
  const commit = await waitForEvidence(state.writer, "checkout_commit", state.args.evidenceTimeoutMs,
    state.args.pollMs, () => {
      const request = panelRequestEntries(state.writer, panelInstanceId, "checkoutCommit", "shop")
        .find((entry) => entry.event.sequence > afterSequence);
      const response = request && findResponse(state.writer, request);
      if (!response || response.message.success !== true) return null;
      return {request, response};
    });
  const inventorySurface = await waitForInventorySurface(state.writer, panelInstanceId,
    commit.response.event.sequence, "post-commit inventory",
    state.args.evidenceTimeoutMs, state.args.pollMs);
  return Object.assign(commit, {inventorySurface,
    inventory: {request: inventorySurface.firstPair.request,
      response: inventorySurface.firstPair.response}});
}

async function waitForClose(state, panelInstanceId, afterSequence) {
  const request = await waitForEvidence(state.writer, "panel_close", state.args.evidenceTimeoutMs,
    state.args.pollMs, () => eventEntries(state.writer, "bridge_send").find((entry) =>
      entry.event.sequence > afterSequence && entry.message.type === "panel"
      && entry.message.panel === "kshop" && entry.message.panelInstanceId === panelInstanceId
      && entry.message.cmd === "close") || null);
  const deadline = Date.now() + state.args.evidenceTimeoutMs;
  while (Date.now() <= deadline) {
    const panel = await state.observer.panelState();
    if (panel.kshopVisible !== true) return request;
    await sleep(state.args.pollMs);
  }
  fail("panel_close_visual_timeout", "panel_close", "KShop remained visually active after close request");
}

async function waitForSafeArchive(runtime, slot, args) {
  const deadline = Date.now() + args.evidenceTimeoutMs;
  let lastError = null;
  while (Date.now() <= deadline) {
    const snapshot = await runtime.session.readTerminalLogSnapshot(2000);
    const diskEvidence = LauncherObservation.captureDiskSaveEvidence({ root: ROOT, slot });
    try {
      const evidence = LauncherObservation.verifyArchiveSaveEvidence({ root: ROOT, slot,
        boundary: runtime.startBoundary, snapshot, diskEvidence,
        requiredOrder: ["sv1", "sv2", "archive"] });
      return { evidence, snapshot };
    } catch (error) { lastError = error; }
    await sleep(args.pollMs);
  }
  fail("safe_archive_timeout", "safe_exit", "exact sv:1→sv:2→archive evidence was not observed", {
    lastCode: lastError && lastError.code,
    lastMessage: lastError && lastError.message,
  });
}

async function execute(args, admission) {
  if (!admission || !admission.controller || !admission.manifest) {
    fail("module_admission_required", "bootstrap",
      "live KShop journey must run through the fixed bootstrap/module journal");
  }
  const runDir = exactRunDirectory(args.slot);
  const generatedAt = new Date().toISOString();
  const runId = path.basename(runDir);
  const commitRequestId = "commit-" + runId;
  const productionClosure = ProductionClosure.captureProductionClosure(ROOT, generatedAt);
  const bundle = {
    schema: TOOL_SCHEMA,
    status: "recording",
    evidenceMode: "live_capture",
    generatedAt,
    runId,
    root: ROOT,
    runDir: path.relative(ROOT, runDir).replace(/\\/g, "/"),
    slot: args.slot,
    seedSlot: args.seedSlot,
    candidateRoot: path.resolve(args.candidateRoot),
    productionClosure,
    productionBinding: null,
    selection: null,
    moduleAdmission: { manifest: admission.manifest, journal: null },
    authorization: {
      isolatedPurchaseAllowed: args.allowIsolatedPurchase === true,
      codexFallbackAllowed: args.allowCodexCuFallback === true,
      selectedTransport: "codex_computer_use",
      launcherAgentRuntime: null,
      commitDecision: null,
      commitDecisionSha256: null,
    },
    controlRequests: [],
    controlAcks: [],
    controlProviderReceipts: [],
    controlCaptures: [],
    controlBindings: [],
    runtime: {},
    cloneLifecycle: { preparation: null, phases: {}, release: null,
      collateralBefore: null, collateralEnd: null },
    residue: {},
    transcript: null,
    hostLog: null,
  };
  const diagnosticPath = path.join(runDir, "diagnostic-bundle.json");
  const persistDiagnostic = () => {
    const publicBundle = JSON.parse(JSON.stringify(bundle));
    assertNoRawTokens(publicBundle);
    atomicWriteJson(diagnosticPath, publicBundle);
  };
  const state = {
    args, runDir, bundle, persistDiagnostic,
    channel: null, writer: null, observer: null, selectedTransport: null,
  };
  let firstRuntime = null;
  let commitMayHaveOccurred = false;
  state.markCommitPossible = () => { commitMayHaveOccurred = true; };
  let safeExitCompleted = false;
  let finalShutdownCompleted = false;
  try {
    persistDiagnostic();
    firstRuntime = await openGenericRuntime(ROOT, args, runDir);
    bundle.runtime.first = {
      identity: firstRuntime.identity,
      identityVerified: true,
      ready: firstRuntime.ready,
      cdpBinding: firstRuntime.cdpBinding,
      sessionEvidence: firstRuntime.sessionEvidence,
      processContract: firstRuntime.processContract,
      launch: firstRuntime.launch,
      trustedCdpExpectations: CDP_TRUSTED_EXPECTATIONS,
    };
    bundle.authorization.launcherAgentRuntime = {
      available: false,
      source: "authenticated_process_contract",
      preferredTransport: "launcher_agent_runtime",
      requiredCapabilities: ["computer.use.kshop", "native.safe_exit"],
      observedCapabilities: firstRuntime.sessionEvidence.capabilities.slice().sort(),
      reasonCode: "authenticated_process_lacks_kshop_computer_use",
      reason: "actual PID-bound argv proves this journey is in legacy HTTP mode; its authenticated capability list does not expose KShop computer use or native SAFEEXIT",
      artifact: firstRuntime.processContract,
      artifactSha256: sha256Text(canonicalJson(firstRuntime.processContract)),
    };
    bundle.candidateBeforeClone = firstRuntime.candidateBeforeClone;
    bundle.candidateProducer = ProductionClosure.captureCandidateProducerBinding(
      args.candidateRoot, firstRuntime.identity, productionClosure);
    bundle.productionBinding = ProductionClosure.bindProductionClosure(
      productionClosure, firstRuntime.identity, runId, bundle.candidateProducer);
    bundle.cloneLifecycle.preparation = firstRuntime.preparation;
    bundle.cloneLifecycle.collateralBefore = firstRuntime.collateralBefore;
    bundle.cloneLifecycle.phases.runtimeBaseline = firstRuntime.baseline;
    admission.controller.checkpoint("clone_prepared");
    state.writer = new TranscriptWriter(runDir);
    state.observer = await attachPassiveObserver({
      root: ROOT, runDir, writer: state.writer,
      cdpBinding: firstRuntime.cdpBinding,
      runtimeIdentity: firstRuntime.identity,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
    });
    state.channel = new ControlChannel(ROOT, runDir);
    state.selectedTransport = "codex_computer_use";
    state.persistDiagnostic();

    const initialSeq = state.writer.events.length;
    await controlStep(state, "open_kshop", {
      instructions: "Using the selected computer-use transport, click the native HUD SHOP/商城 control once. Do not use CDP evaluate or call any panel/business API.",
      selectors: ["native HUD SHOP/商城"],
      expectedIndependentEvidence: ["new panel_cmd open(kshop)", "fresh bulkQuery", "fresh inventory snapshot"],
    });
    const firstPanel = await waitForPanelReady(state.writer, initialSeq,
      args.evidenceTimeoutMs, args.pollMs, []);
    bundle.prePurchase = assertLivePrePurchaseSnapshot(firstPanel.bulk.message);
    bundle.selection = bundle.prePurchase.selection;
    const commitDecision = {
      schema: "workbench-live-e2e.authorization-decision.v1",
      decisionId: "kshop-purchase-" + path.basename(runDir),
      issuedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + args.operatorTimeoutMs * 4).toISOString(),
      source: "cli_explicit_flag",
      oneShot: true,
      allowedStep: "commit_checkout",
      scope: {
        journey: "kshop-dynamic-single-item-purchase.v1",
        runId,
        exactRequestId: commitRequestId,
        slot: args.slot,
        candidateRoot: path.resolve(args.candidateRoot),
        selection: bundle.selection,
        cart: bundle.selection.cart,
        total: bundle.selection.total,
      },
    };
    const commitDecisionSha256 = sha256Text(canonicalJson(commitDecision));
    bundle.authorization.commitDecision = commitDecision;
    bundle.authorization.commitDecisionSha256 = commitDecisionSha256;
    await controlStep(state, "add_selected_item", {
      instructions: "In KShop, locate catalog index " + bundle.selection.catalogIndex
        + " with exact identity “" + bundle.selection.displayName + "” and click its add control once. "
        + "The authoritative cart must settle to quantity " + bundle.selection.quantity
        + ". Do not add any other item.",
      selectors: ["button[data-idx=\"" + bundle.selection.catalogIndex + "\"]"],
      expectedIndependentEvidence: ["isTrusted selected-item click", "authoritative saveCart selected cart"],
    });
    await waitForTrustedSelectionAndSavedCart(state, firstPanel.open.message.panelInstanceId,
      firstPanel.open.event.sequence, bundle.selection);

    const checkoutSeq = state.writer.events.length;
    await controlStep(state, "open_checkout", {
      instructions: "Click #kshop-checkout once and wait for the authoritative settlement preview. Do not click commit yet.",
      selectors: ["#kshop-checkout"],
      expectedIndependentEvidence: ["trusted checkout click", "single authoritative checkoutPreview"],
    });
    const preview = await waitForPreview(state, firstPanel.open.message.panelInstanceId,
      checkoutSeq, bundle.selection, args.evidenceTimeoutMs, args.pollMs);

    const commitSeq = state.writer.events.length;
    await controlStep(state, "commit_checkout", {
      requestId: commitRequestId,
      requiresCommitAuthorization: true,
      authorizationRef: {
        decisionId: commitDecision.decisionId,
        decisionSha256: commitDecisionSha256,
      },
      instructions: "AUTHORIZED ISOLATED CLONE PURCHASE: verify the preview shows only “"
        + bundle.selection.displayName + "” x" + bundle.selection.quantity + ", total "
        + bundle.selection.total + ", then click [data-kshop-settlement-commit] exactly once. Do not retry on ambiguity.",
      selectors: ["[data-kshop-settlement-commit]"],
      expectedIndependentEvidence: ["trusted one-shot commit click", "exact preview-token commit", "fresh inventory refresh"],
    });
    await waitForCommitAndInventory(state, firstPanel.open.message.panelInstanceId,
      commitSeq, args.evidenceTimeoutMs, args.pollMs);
    bundle.cloneLifecycle.phases.afterCommit = await CloneSaveGuard.captureStableSlotArtifactSet({
      root: ROOT, appData: firstRuntime.appData, slot: args.slot, requireJson: true,
      timeoutMs: args.cloneBaselineTimeoutMs, stableMs: args.cloneBaselineStableMs,
      pollMs: args.pollMs,
    });

    const firstCloseSeq = state.writer.events.length;
    await controlStep(state, "close_kshop", {
      instructions: "Click the current KShop header close button once and wait until the workbench is no longer visible.",
      selectors: ["[data-header-action=\"close\"]"],
      expectedIndependentEvidence: ["exact first-instance close", "KShop no longer visible"],
    });
    await waitForClose(state, firstPanel.open.message.panelInstanceId, firstCloseSeq);
    await controlStep(state, "safe_exit", {
      requiresCaptureSha256: true,
      instructions: "Click the native HUD SAFEEXIT control once. Wait until the native safe-exit panel reports save complete. Supply a capture SHA-256 in the acknowledgement.",
      selectors: ["native HUD SAFEEXIT"],
      expectedIndependentEvidence: ["sv:1", "sv:2", "exact clone archive"],
    });
    const safeExitLog = await waitForSafeArchive(firstRuntime, args.slot, args);
    bundle.safeExitEvidence = safeExitLog.evidence;
    bundle.cloneLifecycle.phases.afterSafeExit = await CloneSaveGuard.captureStableSlotArtifactSet({
      root: ROOT, appData: firstRuntime.appData, slot: args.slot, requireJson: true,
      timeoutMs: args.cloneBaselineTimeoutMs, stableMs: args.cloneBaselineStableMs,
      pollMs: args.pollMs,
    });
    const firstDetach = await state.observer.detach(
      productionClosure, bundle.productionBinding, "first");
    bundle.runtime.first.loadedProduction = firstDetach.loadedProduction;
    admission.controller.checkpoint("first_captured");
    await controlStep(state, "exit_confirm", {
      skipObserverHealth: true,
      requiresCaptureSha256: true,
      instructions: "Click the native safe-exit EXIT_CONFIRM/退出 control once. Do not use Ctrl+Q, ForceExit, taskkill, or agent_control shutdown. Supply a capture SHA-256.",
      selectors: ["native SafeExit EXIT_CONFIRM/退出"],
      expectedIndependentEvidence: ["old PID exits", "legacy HTTP port closes"],
    });
    bundle.residue.afterSafeExit = residueWithMethod(
      await LauncherObservation.waitForCleanResidue({ root: ROOT,
        runtimeIdentity: firstRuntime.identity, sessionEvidence: firstRuntime.sessionEvidence,
        cdpBinding: firstRuntime.cdpBinding, timeoutMs: args.evidenceTimeoutMs,
        pollMs: args.pollMs, stableSamples: 3 }), "SAFEEXIT_UI");
    safeExitCompleted = true;

    const restartRuntime = await restartGenericRuntime(ROOT, args,
      firstRuntime.preparation, firstRuntime.expectedIdentity, firstRuntime);
    bundle.runtime.restart = {
      identity: restartRuntime.identity,
      identityVerified: true,
      ready: restartRuntime.ready,
      cdpBinding: restartRuntime.cdpBinding,
      sessionEvidence: restartRuntime.sessionEvidence,
      processContract: restartRuntime.processContract,
      launch: restartRuntime.launch,
      trustedCdpExpectations: CDP_TRUSTED_EXPECTATIONS,
    };
    state.observer = await attachPassiveObserver({
      root: ROOT, runDir, writer: state.writer,
      cdpBinding: restartRuntime.cdpBinding,
      runtimeIdentity: restartRuntime.identity,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
    });
    const restartSeq = state.writer.events.length;
    await controlStep(state, "restart_readback_open_kshop", {
      instructions: "After the same clone restarts, click native HUD SHOP/商城 once. Do not mutate the cart or inventory.",
      selectors: ["native HUD SHOP/商城"],
      expectedIndependentEvidence: ["second fresh panel instance", "fresh bulk/inventory readback"],
    });
    const secondPanel = await waitForPanelReady(state.writer, restartSeq,
      args.evidenceTimeoutMs, args.pollMs,
      [firstPanel.open.message.panelInstanceId], "restart inventory");
    const secondCloseSeq = state.writer.events.length;
    await controlStep(state, "restart_readback_close_kshop", {
      instructions: "Click the restarted KShop header close button once. Do not change cart or inventory.",
      selectors: ["[data-header-action=\"close\"]"],
      expectedIndependentEvidence: ["exact restarted-instance close"],
    });
    await waitForClose(state, secondPanel.open.message.panelInstanceId, secondCloseSeq);
    bundle.cloneLifecycle.phases.afterRestart = await CloneSaveGuard.captureStableSlotArtifactSet({
      root: ROOT, appData: firstRuntime.appData, slot: args.slot, requireJson: true,
      timeoutMs: args.cloneBaselineTimeoutMs, stableMs: args.cloneBaselineStableMs,
      pollMs: args.pollMs,
    });
    const restartDetach = await state.observer.detach(
      productionClosure, bundle.productionBinding, "restart");
    bundle.runtime.restart.loadedProduction = restartDetach.loadedProduction;
    admission.controller.checkpoint("restart_captured");
    bundle.transcript = state.writer.flush({
      detachedAt: new Date().toISOString(),
      journeyComplete: true,
    });
    const restartTerminalSnapshot = await restartRuntime.session.readTerminalLogSnapshot(2000);
    bundle.hostLog = { schema: "workbench-live-e2e.kshop.host-lifecycles.v1",
      lifecycles: [{ label: "first", sessionEvidence: firstRuntime.sessionEvidence,
        boundary: firstRuntime.startBoundary, terminalSnapshot: safeExitLog.snapshot },
      { label: "restart", sessionEvidence: restartRuntime.sessionEvidence,
        boundary: restartRuntime.startBoundary, terminalSnapshot: restartTerminalSnapshot }] };
    const shutdownRequestedAt = new Date().toISOString();
    const shutdown = await restartRuntime.session.agentControl("shutdown");
    LauncherObservation.assertResponseSucceeded(shutdown, "final_shutdown", "agent_control shutdown");
    const shutdownEvidence = { schema: "workbench-live-e2e.kshop.authenticated-shutdown.v1",
      requestedAt: shutdownRequestedAt, completedAt: new Date().toISOString(),
      pid: restartRuntime.identity.pid,
      sessionEvidenceSha256: restartRuntime.sessionEvidence.sessionEvidenceSha256,
      response: shutdown };
    shutdownEvidence.evidenceSha256 = sha256Text(canonicalJson(shutdownEvidence));
    bundle.runtime.restart.shutdownEvidence = shutdownEvidence;
    bundle.residue.final = residueWithMethod(
      await LauncherObservation.waitForCleanResidue({ root: ROOT,
        runtimeIdentity: restartRuntime.identity, sessionEvidence: restartRuntime.sessionEvidence,
        cdpBinding: restartRuntime.cdpBinding, timeoutMs: args.evidenceTimeoutMs,
        pollMs: args.pollMs, stableSamples: 3 }), "agent_control.shutdown");
    finalShutdownCompleted = true;
    const released = releaseGenericClone(firstRuntime);
    bundle.cloneLifecycle.release = released.release;
    bundle.cloneLifecycle.collateralEnd = released.collateralEnd;
    bundle.cloneLifecycle.collateral = released.collateral;
    bundle.status = "captured_unverified";
    bundle.completedAt = new Date().toISOString();
    assertNoRawTokens(bundle);
    const preSeal = verifyBundlePreSeal(bundle);
    admission.controller.checkpoint("verification_executed");
    admission.controller.seal("terminal");
    bundle.moduleAdmission.journal = admission.controller.reverifyAndRestore();
    admission.finished = true;
    bundle.rawBundleManifest = buildRawBundleManifest(bundle);
    const receipt = finalizePreSealVerification(bundle, preSeal);
    const bundlePath = path.join(runDir, "journey-bundle.json");
    atomicWriteJson(bundlePath, bundle);
    atomicWriteJson(path.join(runDir, "verified-receipt.json"), receipt);
    console.log(JSON.stringify({
      status: receipt.status,
      deployment: receipt.deployment,
      runDir,
      bundlePath,
      receiptPath: path.join(runDir, "verified-receipt.json"),
    }, null, 2));
    return receipt;
  } catch (error) {
    bundle.status = "failed_closed";
    bundle.failedAt = new Date().toISOString();
    bundle.failure = publicError(error);
    bundle.recovery = finalShutdownCompleted
      ? "Both runs are closed; inspect the failed evidence gate without reopening or overwriting the clone."
      : safeExitCompleted
        ? "The purchase was archived by real SAFEEXIT. A restarted read-only process may remain; close KShop and use supported agent_control shutdown."
        : commitMayHaveOccurred
          ? "A clone mutation may have occurred. Leave the process under operator control and use the real SAFEEXIT UI; do not call ForceExit or overwrite evidence."
          : "No KShop mutation step was issued; a supported agent_control shutdown may be used if the authenticated process is still present.";
    bundle.failureCleanup = {
      schema: "workbench-live-e2e.kshop.failure-cleanup.v1",
      commitMayHaveOccurred,
      directShutdownAttempted: false,
      directShutdownSucceeded: false,
      reason: commitMayHaveOccurred
        ? "forbidden_after_possible_commit"
        : "eligible_before_commit",
    };
    try {
      if (state.writer) bundle.transcript = state.writer.flush({ journeyComplete: false });
      persistDiagnostic();
    } catch (_persistError) { /* preserve the original failure */ }
    if (!commitMayHaveOccurred && firstRuntime && firstRuntime.session) {
      bundle.failureCleanup.directShutdownAttempted = true;
      try {
        const response = await firstRuntime.session.agentControl("shutdown");
        LauncherObservation.assertResponseSucceeded(response,
          "failure_cleanup", "pre-commit agent_control shutdown");
        bundle.failureCleanup.directShutdownSucceeded = true;
        bundle.failureCleanup.reason = "supported_pre_commit_shutdown_completed";
      } catch (shutdownError) {
        bundle.failureCleanup.reason = "supported_pre_commit_shutdown_failed";
        bundle.failureCleanup.error = publicError(shutdownError);
      }
      try { persistDiagnostic(); } catch (_persistCleanupError) {}
    }
    throw error;
  }
}

async function main(argv, admission) {
  const args = validateArgs(parseArgs(argv));
  if (args.help) return printHelp();
  if (args.check) {
    if (!admission || !admission.controller || !admission.manifest) {
      fail("module_admission_required", "bootstrap", "--check must also run through bootstrap.js");
    }
    admission.controller.seal("terminal");
    const journal = admission.controller.reverifyAndRestore();
    admission.finished = true;
    console.log(JSON.stringify({ ok: true, schema: TOOL_SCHEMA,
      defaultSeedSlot: DEFAULT_SEED_SLOT, defaultTargetSlot: DEFAULT_TARGET_SLOT,
      moduleAdmission: journal.admissionStatus,
      manifestSha256: admission.manifest.manifestSha256,
      journalSha256: journal.evidenceSha256 }, null, 2));
    return journal;
  }
  return execute(args, admission);
}

module.exports = {
  DEFAULT_SEED_SLOT,
  DEFAULT_TARGET_SLOT,
  execute,
  main,
  parseArgs,
  validateArgs,
};

if (require.main === module) {
  console.error(JSON.stringify({ status: "NOT_ADMITTED", entrypoint: "Superseded",
    canonicalEntrypoint: "node tools/workbench-live-e2e/kshop/bootstrap.js" }));
  process.exit(2);
}
