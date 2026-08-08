#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const LauncherObservation = require("./lib/launcher-observation");
const SharedEvidence = require("./lib/evidence-artifact");
const {
  LIVE_SLOT_RE, assertSafeSeed, assertSafeSlot, atomicWriteJson, canonicalJson,
  fail, sha256Bytes, sha256Text, sleep, timestampId,
} = require("./kshop/common");
const { TranscriptWriter, attachPassiveObserver } = require("./kshop/cdp-passive-observer");
const {
  assertNoLauncherBeforeMutation, openGenericRuntime, releaseGenericClone,
} = require("./kshop/generic-opener");
const { openArenaInputChannel } = require("./arena/cdp-input-channel");

const ROOT = path.resolve(__dirname, "..", "..");
const OWNED_RELATIVE = path.join("tmp", "workbench-live-e2e", "arena");
const OWNED_BASE = path.join(ROOT, OWNED_RELATIVE);
const DEFAULT_SEED_SLOT = "crazyflasher7_saves";
const DEFAULT_TARGET_SLOT = "cf7_agent_p5_arena_authority";
const FORBIDDEN_WEB_AUTHORITY_FIELDS = Object.freeze([
  "authorityId", "authorityMode", "authoritySourceDigest", "levelMin", "levelMax",
  "opponentCount", "economyMultiplier", "benchLevel", "expr", "deposit", "reward",
  "pool", "baseCount", "baseLevelMin", "baseLevelMax", "maxWaves", "faction",
]);

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = { candidateRoot: null, seedSlot: DEFAULT_SEED_SLOT, slot: DEFAULT_TARGET_SLOT,
    allowReadOnlyLiveSeed: false, readyTimeoutMs: 180000, operatorTimeoutMs: 180000,
    pollMs: 200, cloneBaselineTimeoutMs: 30000, cloneBaselineStableMs: 2000,
    preserveSeedBytes: true, ownedBaseRelative: OWNED_RELATIVE, help: false };
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
    else if (token === "--allow-read-only-live-seed") args.allowReadOnlyLiveSeed = true;
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
    "Arena P5 real WebView2 -> Host -> AS2 authority journey",
    "",
    "Usage:",
    "  node tools/workbench-live-e2e/arena-live-e2e.js \\",
    "    --candidate-root <tmp/runtime-candidates/v2/direct-child> \\",
    "    --allow-read-only-live-seed",
    "",
    "The live seed is copied byte-for-byte to a dedicated cf7_agent_* slot.",
    "Positive selection/confirm uses CDP Input trusted browser clicks; the only direct Bridge",
    "message is a non-writing retired-card adversarial probe that must fail before Flash.",
  ].join("\n"));
}

function exactRunDirectory(slot) {
  fs.mkdirSync(OWNED_BASE, { recursive: true });
  SharedEvidence.assertExactDirectory(OWNED_BASE, "run_directory");
  const runDir = path.join(OWNED_BASE, timestampId() + "-p5-" + slot);
  fs.mkdirSync(runDir);
  SharedEvidence.assertOwnedRunDirectory(ROOT, runDir, OWNED_RELATIVE, "run_directory");
  return runDir;
}

function exactSave(slot) {
  const filePath = path.join(ROOT, "saves", slot + ".json");
  const bytes = fs.readFileSync(filePath);
  return { path: filePath, bytes, length: bytes.length, sha256: sha256Bytes(bytes) };
}

function messageOf(event) {
  if (!event || !["bridge_send", "webview_message"].includes(event.kind)) return null;
  if (event.message && typeof event.message === "object" && !Array.isArray(event.message)) {
    return event.message;
  }
  if (typeof event.message !== "string") return null;
  try { return JSON.parse(event.message); } catch (_error) { return null; }
}

function entries(writer, kind) {
  return writer.events.map((event) => ({ event, message: messageOf(event) }))
    .filter((entry) => entry.event.kind === kind && entry.message);
}

function responseFor(writer, request) {
  return entries(writer, "webview_message").find((entry) => entry.event.sequence > request.event.sequence
    && entry.message.type === "panel_resp" && entry.message.panel === "arena"
    && entry.message.cmd === request.message.cmd
    && entry.message.callId === request.message.callId) || null;
}

function snapshotExchangeForOpen(writer, openerAfterSequence, openSequence) {
  const requests = entries(writer, "bridge_send").filter((entry) =>
    entry.event.sequence > openerAfterSequence && entry.message.type === "panel"
    && entry.message.panel === "arena" && entry.message.cmd === "snapshot");
  for (const request of requests) {
    const response = responseFor(writer, request);
    if (response && response.event.sequence > openSequence) return { request, response };
  }
  return null;
}

function closeRequestAfter(writer, afterSequence) {
  return entries(writer, "bridge_send").find((entry) =>
    entry.event.sequence > afterSequence && entry.message.type === "panel"
    && entry.message.panel === "arena" && entry.message.cmd === "close") || null;
}

async function waitUntil(label, timeoutMs, pollMs, predicate) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    last = await predicate();
    if (last) return last;
    await sleep(pollMs);
  }
  fail("arena_live_timeout", label, "expected real Arena evidence did not arrive", { last });
}

function validateAuthoritySnapshot(message) {
  const snapshot = message && message.snapshot;
  const authority = snapshot && snapshot.arenaAuthority;
  const cards = authority && authority.cards;
  if (!message || message.success !== true || !snapshot || !Number.isFinite(Number(snapshot.money))
      || !authority || authority.schemaVersion !== 1
      || authority.source !== "data/arena/arena_config.xml+meta_teams.json+arena_factions.json"
      || !/^[0-9A-F]{64}$/.test(String(authority.sourceDigest || ""))
      || !Array.isArray(cards) || cards.length < 12) {
    fail("arena_authority_snapshot_invalid", "arena_open",
      "real Arena snapshot lacks the P5 authority catalog", { message });
  }
  const standard = cards.filter((card) => card && card.mode === "standard");
  if (standard.length !== 10 || standard.some((card) =>
    !/^[a-f0-9]{32}:arena-[0-9]+$/.test(String(card.id || ""))
      || !Number.isInteger(card.previewIndex) || typeof card.expr !== "string"
      || !Number.isFinite(Number(card.deposit)) || !Number.isFinite(Number(card.reward)))) {
    fail("arena_session_cards_invalid", "arena_open",
      "real standard cards are not scoped authority capabilities", { standard });
  }
  return { money: Number(snapshot.money), playerLevel: Number(snapshot.playerLevel),
    source: authority.source, sourceDigest: authority.sourceDigest, cardCount: cards.length,
    standardCards: standard.map((card) => ({ id: card.id, index: card.index,
      mode: card.mode,
      previewIndex: card.previewIndex, expr: card.expr, deposit: Number(card.deposit),
      reward: Number(card.reward), opponentCount: card.opponentCount })) };
}

function visibleStandardCards(cards) {
  return Array.isArray(cards)
    ? cards.filter((card) => card && card.mode === "standard")
    : [];
}

async function requestArenaOpen(runtime, writer) {
  const afterSequence = writer.events.length;
  const response = await runtime.session.agentControl("openArena", {
    expectedSlot: runtime.preparation.targetSlot,
    expectedAttemptId: runtime.ready.expectedAttemptId,
  });
  LauncherObservation.assertResponseSucceeded(response, "arena_open", "agent_control openArena");
  if (response.note !== "arena_panel_open_requested") {
    fail("arena_opener_note_invalid", "arena_open", "fixed AS2 opener did not acknowledge its request",
      { response });
  }
  return { afterSequence, response };
}

async function waitForArenaOpen(writer, observer, input, opener, args, excludedInstances) {
  return waitUntil("arena_open", args.operatorTimeoutMs, args.pollMs, async () => {
    const open = entries(writer, "webview_message").find((entry) =>
      entry.event.sequence > opener.afterSequence && entry.message.type === "panel_cmd"
      && entry.message.cmd === "open" && entry.message.panel === "arena"
      && entry.message.panelInstanceId
      && !(excludedInstances || []).includes(entry.message.panelInstanceId));
    if (!open) return null;
    const initData = open.message.initData || {};
    if (initData.source !== "stage_select_arena_redirect" || initData.difficulty !== "冒险"
        || initData.mode !== "runtime" || initData.debug !== false) {
      fail("arena_formal_route_invalid", "arena_open",
        "Arena did not arrive through the AS2 stage-select redirect contract", { initData });
    }
    const snapshotExchange = snapshotExchangeForOpen(writer, opener.afterSequence,
      open.event.sequence);
    if (!snapshotExchange) return null;
    const snapshotRequest = snapshotExchange.request;
    const snapshotResponse = snapshotExchange.response;
    const authority = validateAuthoritySnapshot(snapshotResponse.message);
    const panelState = await observer.panelState();
    const visible = await input.readState();
    const visibleStandard = visibleStandardCards(visible.cards);
    if (panelState.panel !== "arena" || panelState.hidden === true
        || visible.panel !== "arena" || visible.hidden === true || !visible.snapshot
        || visibleStandard.length !== authority.standardCards.length) return null;
    if (canonicalJson(visibleStandard.map((card) => card.id))
        !== canonicalJson(authority.standardCards.map((card) => card.id))) {
      fail("arena_dom_authority_mismatch", "arena_open",
        "visible Arena cards differ from the Host authority snapshot");
    }
    return { panelInstanceId: open.message.panelInstanceId, openSequence: open.event.sequence,
      snapshotRequestSequence: snapshotRequest.event.sequence,
      snapshotResponseSequence: snapshotResponse.event.sequence, initData, authority, visible };
  });
}

function trustedClickEvidence(writer, afterSequence, geometry) {
  const event = writer.events.find((candidate) => candidate.sequence > afterSequence
    && candidate.kind === "dom_input" && candidate.eventType === "click"
    && candidate.isTrusted === true && candidate.panelState
    && candidate.panelState.panel === "arena" && candidate.panelState.hidden === false
    && candidate.target && candidate.target.visible === true && candidate.target.enabled === true
    && candidate.target.hitTargetMatches === true && candidate.clientX >= geometry.rect.left
    && candidate.clientX <= geometry.rect.left + geometry.rect.width
    && candidate.clientY >= geometry.rect.top
    && candidate.clientY <= geometry.rect.top + geometry.rect.height);
  if (!event) fail("arena_trusted_click_missing", "arena_input",
    "CDP Input did not produce a trusted click on the visible target", { geometry });
  return { sequence: event.sequence, eventHash: event.eventHash, browserIsTrusted: true,
    candidatePageInput: true, physicalInputAttestation: false,
    selector: event.target.selector, text: event.target.text };
}

async function clickAndProve(writer, input, targetName) {
  const afterSequence = writer.events.length;
  const geometry = await input.click(targetName);
  return { geometry, input: await waitUntil("arena_trusted_click", 10000, 50, async () => {
    try { return trustedClickEvidence(writer, afterSequence, geometry); }
    catch (_error) { return null; }
  }) };
}

async function waitForClose(writer, observer, afterSequence, args) {
  return waitUntil("arena_close", args.operatorTimeoutMs, args.pollMs, async () => {
    const request = closeRequestAfter(writer, afterSequence);
    if (!request) return null;
    const state = await observer.panelState();
    if (state.panel === "arena" && state.hidden === false) return null;
    return { closeRequestSequence: request.event.sequence, panelState: state,
      dismissReturnStack: request.message.dismissReturnStack === true };
  });
}

function arenaFlashCommands(snapshot) {
  const marker = "[ArenaTask] -> Flash: ";
  return (Array.isArray(snapshot && snapshot.records) ? snapshot.records : [])
    .map((record) => record && record.line).filter((line) => typeof line === "string")
    .map((line) => {
    const index = line.indexOf(marker);
    if (index < 0) return null;
    try { return { line, command: JSON.parse(line.slice(index + marker.length).trim()) }; }
    catch (_error) { return null; }
  }).filter(Boolean);
}

async function proveRetiredCardRejection(runtime, writer, input, secondOpen, firstOpen, args) {
  await waitUntil("arena_preview_settled", args.operatorTimeoutMs, args.pollMs, async () => {
    const state = await input.readState();
    return state.previewPendingCount === 0 ? state : null;
  });
  const before = await runtime.session.readTerminalLogSnapshot(2000);
  const oldCard = firstOpen.authority.standardCards[0];
  const issued = await input.sendRetiredCardProbe({
    panelInstanceId: secondOpen.panelInstanceId,
    retiredCardId: oldCard.id,
    cardIndex: oldCard.previewIndex,
  });
  const exchange = await waitUntil("arena_stale_probe", args.operatorTimeoutMs, args.pollMs,
    async () => {
      const request = entries(writer, "bridge_send").find((entry) =>
        entry.message.callId === issued.callId && entry.message.cmd === "preview");
      const response = request && responseFor(writer, request);
      return response ? { request, response } : null;
    });
  if (exchange.response.message.success !== false
      || exchange.response.message.error !== "stale_authority") {
    fail("arena_retired_card_not_rejected", "arena_stale_probe",
      "retired card capability was not rejected", { response: exchange.response.message });
  }
  FORBIDDEN_WEB_AUTHORITY_FIELDS.forEach((field) => {
    if (Object.prototype.hasOwnProperty.call(exchange.request.message, field)) {
      fail("arena_stale_probe_authority_smuggled", "arena_stale_probe",
        "retired-card probe carried an authority field", { field });
    }
  });
  await sleep(500);
  const after = await runtime.session.readTerminalLogSnapshot(2000);
  if (arenaFlashCommands(after).length !== arenaFlashCommands(before).length) {
    fail("arena_stale_probe_reached_flash", "arena_stale_probe",
      "retired card probe crossed the Host fail-closed boundary");
  }
  return { callId: issued.callId, retiredCardId: oldCard.id,
    currentCardId: secondOpen.authority.standardCards[0].id,
    requestSequence: exchange.request.event.sequence,
    responseSequence: exchange.response.event.sequence,
    error: exchange.response.message.error, flashDispatchDelta: 0,
    adversarialNonWritingProbe: true, physicalInputAttestation: false };
}

async function provePositiveEnter(runtime, writer, observer, input, open, args, runDir) {
  const readyState = await waitUntil("arena_first_card_preview", args.operatorTimeoutMs, args.pollMs,
    async () => {
      const state = await input.readState();
      return state.previewReady.includes(0) ? state : null;
    });
  const card = readyState.cards[0];
  if (readyState.snapshot.money < card.deposit) {
    fail("arena_seed_money_insufficient", "arena_enter",
      "real save clone cannot afford the lowest authority card", { money: readyState.snapshot.money,
        deposit: card.deposit });
  }
  const select = await clickAndProve(writer, input, "firstCard");
  const selected = await waitUntil("arena_card_selected", 10000, args.pollMs, async () => {
    const state = await input.readState();
    return state.selectedCardIdx === 0 && state.confirm.present && !state.confirm.disabled ? state : null;
  });
  const screenshot = await input.captureScreenshot(path.join(runDir, "arena-authority-selected.png"),
    "authority card selected before real enter");
  const beforeEnterSequence = writer.events.length;
  const confirm = await clickAndProve(writer, input, "confirm");
  const exchange = await waitUntil("arena_enter", args.operatorTimeoutMs, args.pollMs, async () => {
    const request = entries(writer, "bridge_send").find((entry) =>
      entry.event.sequence > beforeEnterSequence && entry.message.type === "panel"
      && entry.message.panel === "arena" && entry.message.cmd === "enter");
    const response = request && responseFor(writer, request);
    return response ? { request, response } : null;
  });
  FORBIDDEN_WEB_AUTHORITY_FIELDS.forEach((field) => {
    if (Object.prototype.hasOwnProperty.call(exchange.request.message, field)) {
      fail("arena_web_authority_smuggled", "arena_enter",
        "positive Web enter payload carried a Host/AS2 authority field", { field });
    }
  });
  if (exchange.request.message.cardId !== card.id || exchange.request.message.cardIndex !== 0
      || exchange.response.message.success !== true || exchange.response.message.closePanel !== true) {
    fail("arena_enter_exchange_invalid", "arena_enter",
      "real Arena enter exchange did not close successfully", {
        request: exchange.request.message, response: exchange.response.message,
      });
  }
  const terminal = await runtime.session.readTerminalLogSnapshot(2000);
  const host = arenaFlashCommands(terminal).filter((entry) =>
    entry.command.action === "arenaEnter").slice(-1)[0];
  if (!host) fail("arena_host_enter_missing", "arena_enter",
    "Host did not log its reconstructed arenaEnter command");
  const accepted = exchange.response.message;
  if (host.command.authoritySourceDigest !== open.authority.sourceDigest
      || host.command.authorityId !== card.id.slice(card.id.indexOf(":") + 1)
      || host.command.expr !== card.expr || Number(host.command.deposit) !== card.deposit
      || Number(host.command.reward) !== card.reward
      || accepted.expr !== host.command.expr
      || Number(accepted.deposit) !== Number(host.command.deposit)
      || Number(accepted.reward) !== Number(host.command.reward)) {
    fail("arena_authority_roundtrip_mismatch", "arena_enter",
      "Host reconstruction and AS2 accepted values differ", {
        card, host: host.command, accepted,
      });
  }
  const closed = await waitForClose(writer, observer, exchange.request.event.sequence, args);
  if (closed.dismissReturnStack !== true) fail("arena_enter_return_stack_not_dismissed", "arena_enter",
    "successful Arena enter did not dismiss the stage-select return stack");
  return { card, selectedState: selected, select, confirm, screenshot,
    webRequest: exchange.request.message, webRequestSequence: exchange.request.event.sequence,
    hostFlashCommand: host.command, hostLogLine: host.line,
    as2Accepted: accepted, responseSequence: exchange.response.event.sequence,
    close: closed, browserTrustedSelectionAndConfirm: true,
    physicalInputAttestation: false };
}

function writeStage(runDir, stage, details) {
  const value = Object.assign({ schema: "workbench-live-e2e.arena-stage.v1", stage,
    updatedAt: new Date().toISOString() }, details || {});
  atomicWriteJson(path.join(runDir, "current-stage.json"), value);
  console.log("[Arena P5 live] " + stage + " | " + runDir);
}

async function waitNoLauncher(timeoutMs, pollMs) {
  return waitUntil("launcher_shutdown", timeoutMs, pollMs, async () => {
    try { return assertNoLauncherBeforeMutation() === true; } catch (_error) { return false; }
  });
}

async function shutdownRuntime(runtime, args) {
  const requestedAt = new Date().toISOString();
  const response = await runtime.session.agentControl("shutdown");
  LauncherObservation.assertResponseSucceeded(response, "launcher", "agent_control shutdown");
  await waitNoLauncher(args.readyTimeoutMs, args.pollMs);
  return { requestedAt, completedAt: new Date().toISOString(), responseSucceeded: true };
}

async function main(argv) {
  const args = validateArgs(parseArgs(argv));
  if (args.help) return printHelp();
  const runDir = exactRunDirectory(args.slot);
  const seedBefore = exactSave(args.seedSlot);
  const writer = new TranscriptWriter(runDir, "arena-p5-" + timestampId());
  const report = { schema: "workbench-live-e2e.arena-p5-authority.v1",
    runId: path.basename(runDir), startedAt: new Date().toISOString(), status: "running",
    runDir, candidateRoot: path.resolve(args.candidateRoot), seed: {
      slot: args.seedSlot, path: seedBefore.path, bytes: seedBefore.length, sha256: seedBefore.sha256,
    }, targetSlot: args.slot, phases: [] };
  let runtime = null;
  let observer = null;
  let input = null;
  let cloneReleased = false;
  function persist() { atomicWriteJson(path.join(runDir, "report.json"), report); }
  persist();
  try {
    writeStage(runDir, "launching_candidate", { seedSlot: args.seedSlot, targetSlot: args.slot });
    runtime = await openGenericRuntime(ROOT, args, runDir);
    if (runtime.preparation.transformId !== "exact-byte-copy") {
      fail("arena_clone_not_exact", "clone_prepare", "Arena P5 requires an exact-byte save clone");
    }
    report.candidate = { buildIdentity: runtime.identity.buildIdentity,
      payloadClosureSha256: runtime.identity.payloadClosureSha256, pid: runtime.identity.pid,
      executablePath: runtime.identity.executablePath };
    report.saveUniverseBefore = runtime.collateralBefore;
    observer = await attachPassiveObserver({ root: ROOT, runDir, writer,
      cdpBinding: runtime.cdpBinding, runtimeIdentity: runtime.identity,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs, requirePanelRequestMux: false });
    input = await openArenaInputChannel({ cdpBinding: runtime.cdpBinding,
      runtimeIdentity: runtime.identity, writer, timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });

    writeStage(runDir, "formal_open_first", { pid: runtime.identity.pid });
    const opener1 = await requestArenaOpen(runtime, writer);
    const open1 = await waitForArenaOpen(writer, observer, input, opener1, args, []);
    report.phases.push({ phase: "formal_open_first", opener: opener1.response, evidence: open1 });
    persist();

    writeStage(runDir, "trusted_close_first", { panelInstanceId: open1.panelInstanceId });
    const closeStart = writer.events.length;
    const closeInput = await clickAndProve(writer, input, "close");
    const close1 = await waitForClose(writer, observer, closeStart, args);
    report.phases.push({ phase: "trusted_close_first", input: closeInput, evidence: close1 });
    persist();

    writeStage(runDir, "formal_reopen", { priorPanelInstanceId: open1.panelInstanceId });
    const opener2 = await requestArenaOpen(runtime, writer);
    const open2 = await waitForArenaOpen(writer, observer, input, opener2, args,
      [open1.panelInstanceId]);
    const oldIds = new Set(open1.authority.standardCards.map((card) => card.id));
    if (open2.authority.standardCards.some((card) => oldIds.has(card.id))) {
      fail("arena_card_capability_reused", "arena_reopen",
        "close/reopen reused an old session-scoped card capability");
    }
    report.phases.push({ phase: "formal_reopen", opener: opener2.response, evidence: open2 });

    writeStage(runDir, "retired_card_rejection", {});
    const stale = await proveRetiredCardRejection(runtime, writer, input, open2, open1, args);
    report.phases.push({ phase: "retired_card_rejection", evidence: stale });
    persist();

    writeStage(runDir, "trusted_select_and_enter", { panelInstanceId: open2.panelInstanceId });
    const enter = await provePositiveEnter(runtime, writer, observer, input, open2, args, runDir);
    report.phases.push({ phase: "trusted_select_and_enter", evidence: enter });
    persist();

    input.close();
    input = null;
    await observer.detach();
    observer = null;
    report.terminalLog = await runtime.session.readTerminalLogSnapshot(2000);
    report.shutdown = await shutdownRuntime(runtime, args);
    const seedAfter = exactSave(args.seedSlot);
    if (seedAfter.sha256 !== seedBefore.sha256 || !seedAfter.bytes.equals(seedBefore.bytes)) {
      fail("arena_seed_changed", "seed_invariant", "real save seed changed during clone E2E");
    }
    report.seedInvariant = { unchanged: true, sha256: seedAfter.sha256, bytes: seedAfter.length };
    report.targetAfter = (() => { const value = exactSave(args.slot); return {
      path: value.path, sha256: value.sha256, bytes: value.length }; })();
    report.cloneLifecycle = releaseGenericClone(runtime);
    cloneReleased = true;
    report.transcript = writer.flush({ journeyComplete: true, detachedAt: new Date().toISOString() });
    report.status = "passed";
    report.completedAt = new Date().toISOString();
    const digestPayload = Object.assign({}, report);
    delete digestPayload.reportSha256;
    report.reportSha256 = sha256Text(canonicalJson(digestPayload));
    persist();
    writeStage(runDir, "complete", { reportSha256: report.reportSha256,
      reportPath: path.join(runDir, "report.json") });
    console.log(JSON.stringify({ ok: true, runDir, reportSha256: report.reportSha256,
      candidate: report.candidate, stale, enter: { card: enter.card,
        accepted: enter.as2Accepted, screenshot: enter.screenshot } }, null, 2));
  } catch (error) {
    report.status = "failed_closed";
    report.failedAt = new Date().toISOString();
    report.failure = { code: error.code || "unhandled_error", phase: error.phase || "unknown",
      message: String(error.message || error), details: error.details || null };
    try { if (input) input.close(); } catch (_inputError) {}
    try { if (observer) await observer.detach(); } catch (_observerError) {}
    try { if (runtime && runtime.session) await shutdownRuntime(runtime, args); } catch (_shutdownError) {}
    try {
      if (runtime && !cloneReleased) {
        report.cloneLifecycle = releaseGenericClone(runtime);
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

module.exports = { FORBIDDEN_WEB_AUTHORITY_FIELDS, arenaFlashCommands, closeRequestAfter,
  messageOf, snapshotExchangeForOpen, trustedClickEvidence, validateAuthoritySnapshot,
  visibleStandardCards };

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error && error.stack || error);
    process.exit(error && error.isUsageError ? 2 : 1);
  });
}
