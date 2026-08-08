#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const CloneSaveGuard = require("./lib/clone-save-guard");
const LauncherObservation = require("./lib/launcher-observation");
const SharedEvidence = require("./lib/evidence-artifact");
const {
  LIVE_SLOT_RE,
  assertSafeSeed,
  assertSafeSlot,
  atomicWriteJson,
  canonicalJson,
  fail,
  sha256Bytes,
  sha256Text,
  sleep,
  timestampId,
} = require("./kshop/common");
const { TranscriptWriter, attachPassiveObserver } = require("./kshop/cdp-passive-observer");
const {
  assertNoLauncherBeforeMutation,
  openGenericRuntime,
  restartGenericRuntime,
} = require("./kshop/generic-opener");

const ROOT = path.resolve(__dirname, "..", "..");
const OWNED_BASE = path.join(ROOT, "tmp", "workbench-live-e2e", "kshop");
const DEFAULT_SEED_SLOT = "crazyflasher7_saves";
const DEFAULT_TARGET_SLOT = "cf7_agent_p5_kshop_legacy";
const DEFAULT_CATALOG_COUNT = 227;

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = {
    candidateRoot: null,
    seedSlot: DEFAULT_SEED_SLOT,
    slot: DEFAULT_TARGET_SLOT,
    expectedCatalogCount: DEFAULT_CATALOG_COUNT,
    allowReadOnlyLiveSeed: false,
    readyTimeoutMs: 180000,
    operatorTimeoutMs: 900000,
    pollMs: 250,
    cloneBaselineTimeoutMs: 30000,
    cloneBaselineStableMs: 2000,
    preserveSeedBytes: true,
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
    else if (token === "--candidate-root") args.candidateRoot = take(index++, token);
    else if (token === "--seed-slot") args.seedSlot = take(index++, token);
    else if (token === "--slot") args.slot = take(index++, token);
    else if (token === "--expected-catalog-count") {
      args.expectedCatalogCount = Number(take(index++, token));
    } else if (token === "--allow-read-only-live-seed") args.allowReadOnlyLiveSeed = true;
    else if (["--ready-timeout-ms", "--operator-timeout-ms", "--poll-ms",
      "--clone-baseline-timeout-ms", "--clone-baseline-stable-ms"].includes(token)) {
      const key = token.slice(2).replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
      args[key] = Number(take(index++, token));
    } else usage("unknown argument: " + token);
  }
  return args;
}

function validateArgs(args) {
  if (args.help) return args;
  assertSafeSlot(args.slot);
  assertSafeSeed(args.seedSlot, args.slot);
  if (LIVE_SLOT_RE.test(args.seedSlot) && args.allowReadOnlyLiveSeed !== true) {
    usage("a live save may only be used as a read-only seed with --allow-read-only-live-seed");
  }
  if (!args.candidateRoot) usage("--candidate-root is required");
  if (!Number.isInteger(args.expectedCatalogCount) || args.expectedCatalogCount < 1) {
    usage("--expected-catalog-count must be a positive integer");
  }
  ["readyTimeoutMs", "operatorTimeoutMs", "pollMs", "cloneBaselineTimeoutMs",
    "cloneBaselineStableMs"].forEach((key) => {
    if (!Number.isFinite(args[key]) || args[key] < 100 || args[key] > 3600000) {
      usage("invalid timeout: " + key);
    }
  });
  return args;
}

function printHelp() {
  console.log([
    "KShop legacy-save read-only live browser journey",
    "",
    "Usage:",
    "  node tools/workbench-live-e2e/kshop-legacy-readback.js \\",
    "    --candidate-root <tmp/runtime-candidates/v2/direct-child> \\",
    "    --allow-read-only-live-seed",
    "",
    "Defaults: --seed-slot " + DEFAULT_SEED_SLOT + " --slot " + DEFAULT_TARGET_SLOT,
    "The seed is copied byte-for-byte. No KShop write request is issued. The operator only",
    "opens and closes KShop twice, then repeats the readback after a supported restart.",
  ].join("\n"));
}

function exactRunDirectory(slot) {
  fs.mkdirSync(OWNED_BASE, { recursive: true });
  SharedEvidence.assertExactDirectory(OWNED_BASE, "run_directory");
  const runDir = path.join(OWNED_BASE, timestampId() + "-legacy-" + slot);
  fs.mkdirSync(runDir);
  SharedEvidence.assertOwnedRunDirectory(ROOT, runDir,
    path.join("tmp", "workbench-live-e2e", "kshop"), "run_directory");
  return runDir;
}

function readExactSave(slot) {
  const filePath = path.join(ROOT, "saves", slot + ".json");
  const stat = fs.lstatSync(filePath);
  const real = fs.realpathSync.native(filePath);
  if (!stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== path.resolve(filePath).toLowerCase()) {
    fail("save_path_invalid", "seed_contract", "save JSON is not an exact regular file");
  }
  const bytes = fs.readFileSync(filePath);
  let data;
  try { data = JSON.parse(bytes.toString("utf8")); }
  catch (error) { fail("save_json_invalid", "seed_contract", error.message); }
  return { filePath: path.resolve(filePath), bytes, sha256: sha256Bytes(bytes), data };
}

function expectedSeedContract(save) {
  const player = save.data && save.data["0"];
  const shop = save.data && save.data.shop;
  const purchased = shop && shop["商城已购买物品"];
  const row = Array.isArray(purchased) && purchased.length === 1 ? purchased[0] : null;
  if (!Array.isArray(player) || !Number.isFinite(Number(player[9]))
      || !Array.isArray(row) || row.length !== 5 || typeof row[3] !== "string"
      || !String(row[3]).trim() || !Number.isFinite(Number(row[3]))
      || !Number.isInteger(Number(row[4])) || Number(row[4]) < 1) {
    fail("legacy_seed_contract_invalid", "seed_contract",
      "seed must contain one numeric-string legacy pending row and a finite K-point balance");
  }
  return {
    seedSlot: path.basename(save.filePath, ".json"),
    seedSha256: save.sha256,
    seedBytes: save.bytes.length,
    kpoints: Number(player[9]),
    rawPending: {
      id: String(row[0]),
      item: String(row[1]),
      source: String(row[2]),
      priceText: String(row[3]),
      price: Number(row[3]),
      quantity: Number(row[4]),
    },
    originalShopSha256: sha256Text(canonicalJson(shop)),
  };
}

function messageOf(event) {
  if (!event || !["bridge_send", "webview_message"].includes(event.kind)) return null;
  if (event.message && typeof event.message === "object" && !Array.isArray(event.message)) {
    return event.message;
  }
  if (typeof event.message !== "string") return null;
  try { return JSON.parse(event.message); }
  catch (_error) { return null; }
}

function entries(writer, kind) {
  return writer.events.map((event) => ({ event, message: messageOf(event) }))
    .filter((entry) => entry.event.kind === kind && entry.message);
}

function findResponse(writer, requestEntry) {
  return entries(writer, "webview_message").find((entry) =>
    entry.event.sequence > requestEntry.event.sequence
    && entry.message.type === "panel_resp"
    && entry.message.panel === "kshop"
    && entry.message.panelInstanceId === requestEntry.message.panelInstanceId
    && entry.message.callId === requestEntry.message.callId
    && entry.message.cmd === requestEntry.message.cmd) || null;
}

function openEntries(writer, afterSequence) {
  return entries(writer, "webview_message").filter((entry) =>
    entry.event.sequence > afterSequence
    && entry.message.type === "panel_cmd" && entry.message.cmd === "open"
    && entry.message.panel === "kshop" && entry.message.panelInstanceId);
}

function bulkRequest(writer, panelInstanceId) {
  return entries(writer, "bridge_send").find((entry) =>
    entry.message.type === "panel" && entry.message.panel === "kshop"
    && entry.message.panelInstanceId === panelInstanceId
    && entry.message.cmd === "bulkQuery") || null;
}

function normalizedProjection(message, expected, expectedCatalogCount) {
  const pending = message && Array.isArray(message.purchased) && message.purchased.length === 1
    ? message.purchased[0] : null;
  if (!message || message.success !== true || !Array.isArray(message.catalog)
      || message.catalog.length !== expectedCatalogCount
      || Number(message.kpoints) !== expected.kpoints
      || !pending || pending.purchasedIdx !== 0
      || pending.item !== expected.rawPending.item
      || Number(pending.quantity) !== expected.rawPending.quantity) {
    fail("legacy_projection_mismatch", "browser_readback",
      "live KShop projection differs from the exact seed contract", {
        expectedCatalogCount,
        actualCatalogCount: message && Array.isArray(message.catalog) ? message.catalog.length : null,
        expectedKpoints: expected.kpoints,
        actualKpoints: message && message.kpoints,
        expectedPendingItem: expected.rawPending.item,
        expectedPendingQuantity: expected.rawPending.quantity,
        actualPending: pending,
      });
  }
  return {
    catalogCount: message.catalog.length,
    kpoints: Number(message.kpoints),
    cartCount: Array.isArray(message.cart) ? message.cart.length : null,
    pendingCount: message.purchased.length,
    pending: {
      purchasedIdx: pending.purchasedIdx,
      item: pending.item,
      displayname: pending.displayname,
      icon: pending.icon,
      quantity: pending.quantity,
    },
  };
}

async function waitUntil(label, timeoutMs, pollMs, predicate) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const value = await predicate();
    if (value) return value;
    await sleep(pollMs);
  }
  fail("live_evidence_timeout", label, "expected live evidence did not arrive before timeout");
}

async function waitForOpen(writer, observer, afterSequence, expected, args, excludedIds) {
  return waitUntil("kshop_open", args.operatorTimeoutMs, args.pollMs, async () => {
    const open = openEntries(writer, afterSequence).find((entry) =>
      !(excludedIds || []).includes(entry.message.panelInstanceId));
    if (!open) return null;
    const request = bulkRequest(writer, open.message.panelInstanceId);
    const response = request && findResponse(writer, request);
    if (!response) return null;
    const state = await observer.panelState();
    if (state.kshopVisible !== true) return null;
    return {
      panelInstanceId: open.message.panelInstanceId,
      openSequence: open.event.sequence,
      bulkRequestSequence: request.event.sequence,
      bulkResponseSequence: response.event.sequence,
      projection: normalizedProjection(response.message, expected, args.expectedCatalogCount),
    };
  });
}

function closeInputEvidence(events, requestEvent, afterSequence) {
  const trustedClick = events.find((event) => event.sequence > afterSequence
    && event.sequence < requestEvent.sequence
    && event.kind === "dom_input" && event.eventType === "click"
    && event.isTrusted === true && Number(event.button) === 0
    && event.panelState && event.panelState.panel === "kshop"
    && event.panelState.hidden === false
    && event.target && event.target.selector === "[data-header-action=\"close\"]"
    && event.target.visible === true && event.target.enabled === true
    && event.target.hitTargetMatches === true);
  if (trustedClick) {
    return {
      inputRoute: "trusted_dom_close_click",
      inputSequence: trustedClick.sequence,
      inputEventHash: trustedClick.eventHash,
      browserIsTrusted: true,
      physicalInputAttestation: true,
    };
  }

  const panelEsc = events.find((event) => event.sequence === requestEvent.sequence + 1
    && event.prevHash === requestEvent.eventHash
    && event.kind === "webview_message"
    && event.panelState && event.panelState.panel === ""
    && event.panelState.hidden === true
    && messageOf(event) && messageOf(event).type === "panel_esc");
  if (!panelEsc) return null;
  return {
    inputRoute: "host_panel_esc",
    inputSequence: panelEsc.sequence,
    inputEventHash: panelEsc.eventHash,
    browserIsTrusted: false,
    physicalInputAttestation: false,
  };
}

async function waitForClose(writer, observer, panelInstanceId, afterSequence, args) {
  return waitUntil("kshop_close", args.operatorTimeoutMs, args.pollMs, async () => {
    const request = entries(writer, "bridge_send").find((entry) =>
      entry.event.sequence > afterSequence && entry.message.type === "panel"
      && entry.message.panel === "kshop"
      && entry.message.panelInstanceId === panelInstanceId
      && entry.message.cmd === "close");
    if (!request) return null;
    const input = closeInputEvidence(writer.events, request.event, afterSequence);
    if (!input) return null;
    const state = await observer.panelState();
    if (state.kshopVisible === true) return null;
    return Object.assign({
      closeRequestSequence: request.event.sequence,
    }, input);
  });
}

async function waitNoLauncher(timeoutMs, pollMs) {
  return waitUntil("launcher_shutdown", timeoutMs, pollMs, async () => {
    try { return assertNoLauncherBeforeMutation() === true; }
    catch (_error) { return false; }
  });
}

function writeStage(runDir, stage, details) {
  const value = Object.assign({
    schema: "workbench-live-e2e.kshop-legacy-stage.v1",
    stage,
    updatedAt: new Date().toISOString(),
  }, details || {});
  atomicWriteJson(path.join(runDir, "current-stage.json"), value);
  console.log("[KShop legacy readback] " + stage + " | " + runDir);
}

async function shutdownRuntime(runtime, args) {
  const response = await runtime.session.agentControl("shutdown");
  LauncherObservation.assertResponseSucceeded(response, "launcher", "agent_control shutdown");
  await waitNoLauncher(args.readyTimeoutMs, args.pollMs);
  return { requestedAt: new Date().toISOString(), responseSucceeded: true };
}

function assertSeedAndCloneShop(seedBefore, targetSlot, expected) {
  const seedAfter = readExactSave(expected.seedSlot);
  if (seedAfter.sha256 !== seedBefore.sha256 || !seedAfter.bytes.equals(seedBefore.bytes)) {
    fail("live_seed_changed", "terminal_invariant", "the original player save changed");
  }
  const target = readExactSave(targetSlot);
  const targetShopSha256 = sha256Text(canonicalJson(target.data.shop));
  if (targetShopSha256 !== expected.originalShopSha256
      || Number(target.data["0"] && target.data["0"][9]) !== expected.kpoints) {
    fail("clone_shop_changed", "terminal_invariant",
      "the read-only journey modified the clone shop projection or K-point balance");
  }
  return {
    seedAfterSha256: seedAfter.sha256,
    seedByteInvariant: true,
    targetAfterSha256: target.sha256,
    targetShopSha256,
    cloneShopInvariant: true,
  };
}

function releaseSeedScopedClone(runtime) {
  const release = CloneSaveGuard.releaseDedicatedClone({
    preparation: runtime.preparation,
    lock: runtime.lock,
    appData: runtime.appData,
  });
  return {
    schema: "workbench-live-e2e.kshop-legacy-clone-release.v1",
    scope: "exact_seed_and_dedicated_target",
    seedAndTargetVerified: true,
    unrelatedSaveUniverseNotClaimed: true,
    release,
  };
}

async function main(argv) {
  const args = validateArgs(parseArgs(argv));
  if (args.help) return printHelp();
  const runDir = exactRunDirectory(args.slot);
  const seedBefore = readExactSave(args.seedSlot);
  const expected = expectedSeedContract(seedBefore);
  const writer = new TranscriptWriter(runDir, "kshop-legacy-" + timestampId());
  const report = {
    schema: "workbench-live-e2e.kshop-legacy-readback.v1",
    runId: path.basename(runDir),
    startedAt: new Date().toISOString(),
    status: "running",
    runDir,
    candidateRoot: path.resolve(args.candidateRoot),
    expected,
    phases: [],
  };
  let firstRuntime = null;
  let currentRuntime = null;
  let observer = null;
  let cloneReleased = false;
  function persist() { atomicWriteJson(path.join(runDir, "report.json"), report); }
  persist();
  try {
    writeStage(runDir, "launching_candidate", { seedSlot: args.seedSlot, targetSlot: args.slot });
    firstRuntime = await openGenericRuntime(ROOT, args, runDir);
    currentRuntime = firstRuntime;
    report.candidate = {
      buildIdentity: firstRuntime.identity.buildIdentity,
      payloadClosureSha256: firstRuntime.identity.payloadClosureSha256,
      pid: firstRuntime.identity.pid,
      executablePath: firstRuntime.identity.executablePath,
    };
    if (firstRuntime.preparation.transformId !== "exact-byte-copy") {
      fail("clone_not_exact", "clone_prepare", "legacy readback requires an exact-byte clone");
    }
    const preparedJson = firstRuntime.preparation.targetPrepared.artifacts
      .find((entry) => entry.kind === "json");
    if (!preparedJson || preparedJson.sha256 !== seedBefore.sha256) {
      fail("clone_bytes_mismatch", "clone_prepare", "prepared clone differs from seed bytes");
    }
    observer = await attachPassiveObserver({
      root: ROOT, runDir, writer,
      cdpBinding: firstRuntime.cdpBinding,
      runtimeIdentity: firstRuntime.identity,
      timeoutMs: args.readyTimeoutMs,
      pollMs: args.pollMs,
      requirePanelRequestMux: false,
    });
    writeStage(runDir, "open_first", { pid: firstRuntime.identity.pid });
    const firstOpen = await waitForOpen(writer, observer, writer.events.length,
      expected, args, []);
    report.phases.push({ phase: "first_open", pid: firstRuntime.identity.pid, evidence: firstOpen });
    persist();

    writeStage(runDir, "close_first", { panelInstanceId: firstOpen.panelInstanceId });
    const firstClose = await waitForClose(writer, observer, firstOpen.panelInstanceId,
      firstOpen.bulkResponseSequence, args);
    report.phases.push({ phase: "first_close", pid: firstRuntime.identity.pid, evidence: firstClose });
    persist();

    writeStage(runDir, "open_second_same_process", { pid: firstRuntime.identity.pid });
    const secondOpen = await waitForOpen(writer, observer, firstClose.closeRequestSequence,
      expected, args, [firstOpen.panelInstanceId]);
    if (canonicalJson(secondOpen.projection) !== canonicalJson(firstOpen.projection)) {
      fail("same_process_projection_changed", "browser_readback",
        "close/reopen changed the KShop projection");
    }
    report.phases.push({ phase: "second_open_same_process", pid: firstRuntime.identity.pid,
      evidence: secondOpen });
    persist();

    writeStage(runDir, "close_second_same_process", { panelInstanceId: secondOpen.panelInstanceId });
    const secondClose = await waitForClose(writer, observer, secondOpen.panelInstanceId,
      secondOpen.bulkResponseSequence, args);
    report.phases.push({ phase: "second_close_same_process", pid: firstRuntime.identity.pid,
      evidence: secondClose });
    persist();

    await observer.detach();
    observer = null;
    writeStage(runDir, "restart_candidate", { firstPid: firstRuntime.identity.pid });
    report.firstShutdown = await shutdownRuntime(firstRuntime, args);
    const restarted = await restartGenericRuntime(ROOT, args, firstRuntime.preparation,
      firstRuntime.expectedIdentity, firstRuntime);
    currentRuntime = restarted;
    report.restart = { pid: restarted.identity.pid, executablePath: restarted.identity.executablePath,
      buildIdentity: restarted.identity.buildIdentity,
      payloadClosureSha256: restarted.identity.payloadClosureSha256 };
    observer = await attachPassiveObserver({
      root: ROOT, runDir, writer,
      cdpBinding: restarted.cdpBinding,
      runtimeIdentity: restarted.identity,
      timeoutMs: args.readyTimeoutMs,
      pollMs: args.pollMs,
      requirePanelRequestMux: false,
    });
    writeStage(runDir, "open_after_restart", { pid: restarted.identity.pid });
    const restartOpen = await waitForOpen(writer, observer, writer.events.length,
      expected, args, [firstOpen.panelInstanceId, secondOpen.panelInstanceId]);
    if (canonicalJson(restartOpen.projection) !== canonicalJson(firstOpen.projection)) {
      fail("restart_projection_changed", "browser_readback",
        "process restart changed the KShop projection");
    }
    report.phases.push({ phase: "open_after_restart", pid: restarted.identity.pid,
      evidence: restartOpen });
    persist();

    writeStage(runDir, "close_after_restart", { panelInstanceId: restartOpen.panelInstanceId });
    const restartClose = await waitForClose(writer, observer, restartOpen.panelInstanceId,
      restartOpen.bulkResponseSequence, args);
    report.phases.push({ phase: "close_after_restart", pid: restarted.identity.pid,
      evidence: restartClose });
    await observer.detach();
    observer = null;
    report.restartShutdown = await shutdownRuntime(restarted, args);
    currentRuntime = null;

    report.terminalInvariant = assertSeedAndCloneShop(seedBefore, args.slot, expected);
    report.cloneLifecycle = releaseSeedScopedClone(firstRuntime);
    cloneReleased = true;
    report.transcript = writer.flush({ journeyComplete: true,
      detachedAt: new Date().toISOString() });
    report.status = "passed";
    report.completedAt = new Date().toISOString();
    const digestPayload = Object.assign({}, report);
    delete digestPayload.reportSha256;
    report.reportSha256 = sha256Text(canonicalJson(digestPayload));
    persist();
    writeStage(runDir, "complete", { reportSha256: report.reportSha256,
      reportPath: path.join(runDir, "report.json") });
    console.log(JSON.stringify({ ok: true, runDir, reportSha256: report.reportSha256,
      projection: firstOpen.projection }, null, 2));
  } catch (error) {
    report.status = "failed_closed";
    report.failedAt = new Date().toISOString();
    report.failure = { code: error.code || "unhandled_error",
      phase: error.phase || "unknown", message: String(error.message || error),
      details: error.details || null };
    try { if (observer) await observer.detach(); } catch (_detachError) {}
    try { if (currentRuntime && currentRuntime.session) await shutdownRuntime(currentRuntime, args); }
    catch (_shutdownError) {}
    try {
      if (firstRuntime && !cloneReleased) {
        report.cloneLifecycle = releaseSeedScopedClone(firstRuntime);
        cloneReleased = true;
      }
    } catch (releaseError) {
      report.cloneReleaseFailure = { code: releaseError.code || "unhandled_error",
        message: String(releaseError.message || releaseError) };
    }
    try { report.transcript = writer.flush({ journeyComplete: false }); } catch (_flushError) {}
    persist();
    writeStage(runDir, "failed_closed", { code: report.failure.code, phase: report.failure.phase });
    throw error;
  }
}

module.exports = { closeInputEvidence };

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error && error.stack || error);
    process.exit(error && error.isUsageError ? 2 : 1);
  });
}
