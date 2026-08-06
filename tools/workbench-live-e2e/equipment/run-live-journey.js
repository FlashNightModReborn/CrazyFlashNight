"use strict";

const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const RuntimeGuard = require("../lib/runtime-guard");
const IdentityFixture = require("../../equipment-tuning/fixtures/item-identity-triple.json");
const {
  API_VERSION,
  AUTHORIZATION_SCHEMA,
  BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA,
  OWNED_BASE_RELATIVE,
  atomicWriteJson,
  buildArtifactManifest,
  fail,
  readJsonFile,
} = require("./common");
const { attachPassiveObserver } = require("./cdp-passive-observer");
const { ControlChannel } = require("./control-channel");
const Protocol = require("./protocol");
const ProductionClosure = require("./production-closure");
const { finalizePreSealVerification, persistPreSealSidecars,
  verifyBundlePreSeal } = require("./evidence-verifier");

const ROOT = path.resolve(__dirname, "..", "..", "..");
const DEFAULT_SEED_SLOT = "cf7_agent_a3_equipment_seed";
const DEFAULT_TARGET_SLOT = "cf7_agent_a3_equipment_run";
const CANDIDATE_A = IdentityFixture.allDistinct[1];
const CANDIDATE_B = IdentityFixture.allDistinct[0];

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function take(argv, index, flag) {
  if (!argv[index + 1] || argv[index + 1].startsWith("--")) usage(flag + " requires a value");
  return argv[index + 1];
}

function parseArgs(argv) {
  const args = { candidateRoot: null, seedSlot: DEFAULT_SEED_SLOT,
    targetSlot: DEFAULT_TARGET_SLOT, sourceContainer: "背包", sourceSlot: 7,
    allowIsolatedCommit: false, allowCodexCuFallback: false,
    readyTimeoutMs: 180000, controlTimeoutMs: 900000, evidenceTimeoutMs: 120000,
    stableTimeoutMs: 30000, stableMs: 2000, pollMs: 250,
    check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--help" || token === "-h") args.help = true;
    else if (token === "--check") args.check = true;
    else if (token === "--allow-isolated-commit") args.allowIsolatedCommit = true;
    else if (token === "--allow-codex-cu-fallback") args.allowCodexCuFallback = true;
    else if (["--candidate-root", "--seed-slot", "--target-slot", "--source-container",
      "--source-slot", "--ready-timeout-ms", "--control-timeout-ms", "--evidence-timeout-ms",
      "--stable-timeout-ms", "--stable-ms", "--poll-ms"].includes(token)) {
      const key = token.slice(2).replace(/-([a-z])/g, (_all, letter) => letter.toUpperCase());
      args[key] = take(argv, index, token);
      index += 1;
    } else usage("unknown argument: " + token);
  }
  ["sourceSlot", "readyTimeoutMs", "controlTimeoutMs", "evidenceTimeoutMs",
    "stableTimeoutMs", "stableMs", "pollMs"].forEach((key) => { args[key] = Number(args[key]); });
  return args;
}

function validateArgs(args) {
  if (args.help || args.check) return args;
  if (!args.candidateRoot) usage("--candidate-root is required; formal runtime is never used");
  CloneGuard.assertSourceSlot(args.seedSlot);
  CloneGuard.assertDedicatedSlot(args.targetSlot);
  if (args.seedSlot === args.targetSlot) usage("seed and target slots must differ");
  if (!args.allowIsolatedCommit) usage("--allow-isolated-commit is required for the one bounded write");
  if (!args.allowCodexCuFallback) {
    usage("--allow-codex-cu-fallback is required because authenticated legacy HTTP disables Launcher Agent Runtime admission");
  }
  if (args.sourceContainer !== "背包" || !Number.isInteger(args.sourceSlot)
      || args.sourceSlot < 0 || args.sourceSlot > 49) {
    usage("the v2 journey requires one exact 背包 slot in 0..49");
  }
  ["readyTimeoutMs", "controlTimeoutMs", "evidenceTimeoutMs", "stableTimeoutMs",
    "stableMs", "pollMs"].forEach((key) => {
    if (!Number.isFinite(args[key]) || args[key] < 100 || args[key] > 3600000) {
      usage("invalid timing option: " + key);
    }
  });
  if (args.stableTimeoutMs < args.stableMs) usage("stable timeout must cover stable window");
  return args;
}

function printHelp() {
  console.log(JSON.stringify({ status: "HELP", usage: [
    "Equipment Tuning isolated two-process production journey (tooling only)",
    "",
    "Fixed entry:",
    "  node tools/workbench-live-e2e/equipment/bootstrap.js --candidate-root <candidate> \\",
    "    --allow-isolated-commit --allow-codex-cu-fallback",
    "",
    "Defaults: --seed-slot " + DEFAULT_SEED_SLOT + " --target-slot " + DEFAULT_TARGET_SLOT,
    "          --source-container 背包 --source-slot 7",
    "",
    "No existing-slot or reseed shortcut exists. The target is always an exact cf7_agent_* clone.",
    "The runner never calls Equipment business APIs and never synthesizes input. It emits bounded",
    "computer-use requests; authenticated legacy HTTP proves Launcher Agent Runtime unavailable,",
    "so only the explicitly authorized Codex computer-use fallback may acknowledge them.",
  ].join("\n") }));
}

function timestampId() {
  return new Date().toISOString().replace(/[-:.TZ]/g, "") + "-" + process.pid;
}

function createRunDirectory(targetSlot) {
  const base = path.join(ROOT, OWNED_BASE_RELATIVE);
  fs.mkdirSync(base, { recursive: true });
  Evidence.assertExactDirectory(base, "run_directory");
  const runDir = path.join(base, timestampId() + "-" + targetSlot);
  fs.mkdirSync(runDir);
  Evidence.assertOwnedRunDirectory(ROOT, runDir, OWNED_BASE_RELATIVE, "run_directory");
  return runDir;
}

function formatLocalTimestamp(value) {
  const now = value || new Date();
  const part = (number) => String(number).padStart(2, "0");
  return now.getFullYear() + "-" + part(now.getMonth() + 1) + "-" + part(now.getDate())
    + " " + part(now.getHours()) + ":" + part(now.getMinutes()) + ":" + part(now.getSeconds());
}

function validSave(data) {
  const player = data && data["0"];
  return !!data && data.version === "3.0" && !!data.lastSaved
    && Array.isArray(player) && player.length >= 14 && player[0] != null && player[0] !== ""
    && player[3] != null && Number.isFinite(Number(player[3]))
    && Array.isArray(data["1"]) && data["1"].length >= 28
    && Array.isArray(data["4"]) && data["4"].length >= 2
    && Array.isArray(data["5"]) && Array.isArray(data["7"]) && data["7"].length >= 5
    && !!data.inventory && !!data.collection && !!data.infrastructure && !!data.tasks
    && Array.isArray(data.tasks.tasks_to_do) && !!data.tasks.tasks_finished
    && !!data.tasks.task_chains_progress && !!data.pets && !!data.shop;
}

function noRuntime() {
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  return true;
}

function parseMessage(event) {
  if (!event || !event.message) return null;
  if (Evidence.isPlainObject(event.message)) return event.message;
  try { return JSON.parse(event.message); } catch (_error) { return null; }
}

function domainRequests(transcript, domain) {
  return transcript.events.map((event) => ({ event, message: parseMessage(event) }))
    .filter((entry) => entry.event.kind === "bridge_send" && entry.message
      && entry.message.domain === domain && typeof entry.message.cmd === "string");
}

function exactResponse(transcript, requestEntry) {
  const values = transcript.events.map((event) => ({ event, message: parseMessage(event) }))
    .filter((entry) => entry.event.kind === "webview_message" && entry.message
      && entry.message.domain === requestEntry.message.domain
      && entry.message.cmd === requestEntry.message.cmd
      && entry.message.callId === requestEntry.message.callId
      && entry.message.panelInstanceId === requestEntry.message.panelInstanceId
      && entry.event.sequence > requestEntry.event.sequence);
  return values.length === 1 ? values[0] : null;
}

async function waitForTranscript(observer, predicate, args, label) {
  const deadline = Date.now() + args.evidenceTimeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    await observer.health();
    last = observer.snapshot();
    if (predicate(last)) return last;
    await new Promise((resolve) => setTimeout(resolve, args.pollMs));
  }
  fail("journey_evidence_timeout", label, "independent observer evidence did not settle", {
    eventCount: last && last.eventCount,
  });
}

async function waitForExactCloseReceipt(session, panelInstanceId, args, label) {
  const expected = "event=panel_exact_close_completed panel=workbench panelInstanceId="
    + encodeURIComponent(panelInstanceId);
  const deadline = Date.now() + args.evidenceTimeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    last = await session.readTerminalLogSnapshot(2000);
    const matches = last.records.filter((record) => String(record.line || "").includes(expected));
    if (matches.length === 1) return last;
    if (matches.length > 1) {
      fail("host_close_receipt_duplicate", label,
        "Host emitted duplicate exact close-completion receipts", { count: matches.length });
    }
    await new Promise((resolve) => setTimeout(resolve, args.pollMs));
  }
  fail("host_close_receipt_timeout", label,
    "Host did not emit the exact owner close-completion receipt before lifecycle continuation");
}

function expectedCounts(transcript, tuningCommands, inventoryCount) {
  const tuning = domainRequests(transcript, "equipment_tuning");
  const inventory = domainRequests(transcript, "inventory");
  if (JSON.stringify(tuning.map((entry) => entry.message.cmd)) !== JSON.stringify(tuningCommands)
      || inventory.length !== inventoryCount) return false;
  return tuning.concat(inventory).every((entry) => exactResponse(transcript, entry));
}

function sourceRecord(data, source) {
  const container = data && data.inventory && data.inventory[source.containerId];
  if (!container) return null;
  const record = Array.isArray(container) ? container[source.slot] : container[String(source.slot)];
  return Evidence.isPlainObject(record) && Evidence.isPlainObject(record.value) ? record : null;
}

function quantityOf(record) {
  if (!record) return 0;
  if (Number.isFinite(Number(record.value)) && typeof record.value !== "object") return Number(record.value);
  if (record.value && Number.isFinite(Number(record.value.quantity))) return Number(record.value.quantity);
  return 1;
}

function materialCounts(data, identities) {
  const output = {};
  identities.forEach((identity) => { output[identity.itemName] = 0; });
  const inventory = data && data.inventory || {};
  Object.keys(inventory).forEach((containerName) => {
    const container = inventory[containerName];
    Object.keys(container || {}).forEach((slot) => {
      const record = container[slot];
      if (record && Object.prototype.hasOwnProperty.call(output, String(record.name))) {
        output[String(record.name)] += quantityOf(record);
      }
    });
  });
  return output;
}

function diskEquipmentProjection(record) {
  if (!record || !Evidence.isPlainObject(record.value)) return null;
  const value = record.value;
  const level = Number(value.level != null ? value.level : value.enhancementLevel);
  const tier = value.tier == null ? "" : String(value.tier);
  const mods = Array.isArray(value.mods) ? value.mods.slice() : null;
  if (!Number.isInteger(level) || level < 0 || !mods
      || mods.some((entry) => typeof entry !== "string" || !entry)) return null;
  return { name: String(record.name || ""), level, tier, mods,
    lastUpdate: Number(record.lastUpdate) };
}

function authorityDiskProjection(equipment) {
  return { name: String(equipment.name || equipment.itemName || ""),
    level: Number(equipment.level != null ? equipment.level : equipment.enhancementLevel),
    tier: equipment.tier == null ? "" : String(equipment.tier),
    mods: Array.isArray(equipment.mods) ? equipment.mods.slice() : [],
    lastUpdate: Number(equipment.lastUpdate) };
}

function captureDiskProjection(root, slot, source, equipment, materialIdentities) {
  const file = Evidence.readExactRegularFile(CloneGuard.saveJsonPath(root, slot), {
    phase: "disk_projection", maximumBytes: 128 * 1024 * 1024,
  });
  const text = file.bytes.toString("utf8");
  let data;
  try { data = JSON.parse(text); }
  catch (error) { fail("disk_json_invalid", "disk_projection", error.message); }
  if (!validSave(data)) fail("disk_schema_invalid", "disk_projection", "target save schema is invalid");
  const record = sourceRecord(data, source);
  const persistedEquipment = diskEquipmentProjection(record);
  const expectedEquipment = authorityDiskProjection(equipment);
  if (!persistedEquipment
      || Evidence.canonicalJson(persistedEquipment) !== Evidence.canonicalJson(expectedEquipment)) {
    fail("disk_source_record_invalid", "disk_projection",
      "persisted source record does not match authoritative equipment identity/level/tier/mods/timestamp");
  }
  const counts = materialCounts(data, materialIdentities);
  const persistedSource = { containerId: source.containerId, slot: source.slot,
      name: String(record.name), lastUpdate: Number(record.lastUpdate),
      valueSha256: Evidence.sha256Text(Evidence.canonicalJson(record.value)),
      recordSha256: Evidence.sha256Text(Evidence.canonicalJson(record)) };
  return { sha256: file.sha256, bytes: file.length, textCharacters: text.length,
    semanticSha256: Evidence.sha256Text(Evidence.canonicalJson({
      equipment: persistedEquipment, materials: counts, persistedSource,
    })), equipment: persistedEquipment, materials: counts, persistedSource };
}

async function stableTargetSet(appData, targetSlot, args) {
  return CloneGuard.captureStableSlotArtifactSet({ root: ROOT, appData, slot: targetSlot,
    requireJson: true, timeoutMs: args.stableTimeoutMs, stableMs: args.stableMs,
    pollMs: args.pollMs });
}

async function startLifecycle(args, preparation, expectedIdentity) {
  const cdpBinding = await RuntimeGuard.allocateLoopbackCdpPort();
  LauncherObservation.startLauncherCandidate({ root: ROOT,
    candidateRoot: path.resolve(args.candidateRoot), expectedIdentity, cdpPort: cdpBinding.port });
  const session = await LauncherObservation.waitForAuthenticatedLegacyHttp({ root: ROOT,
    timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
  const identity = session.verifyRuntimeIdentity(expectedIdentity);
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), identity.pid);
  const processContract = LauncherObservation.attestAuthenticatedLauncherProcess({ root: ROOT,
    sessionEvidence: session.evidence, runtimeIdentity: identity });
  cdpBinding.runtimePid = identity.pid;
  cdpBinding.configurationSource = "CF7_WEBVIEW2_ARGS";
  cdpBinding.developerMode = true;
  const startBoundary = LauncherObservation.createTerminalLogBoundary(
    await session.readTerminalLogSnapshot(2000));
  await LauncherObservation.waitForAgentControl(session, {
    timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
  });
  const startResponse = await session.agentControl("start", { slot: preparation.targetSlot,
    fresh: false, deferReveal: false, requireFlashReveal: true, rememberSlot: false });
  LauncherObservation.assertResponseSucceeded(startResponse, "launcher", "agent_control start");
  const ready = await LauncherObservation.waitForRuntimeReady(session, {
    slot: preparation.targetSlot, timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
    startBoundary, startResponse,
  });
  return { identity, attemptId: ready.expectedAttemptId, session,
    sessionEvidence: session.evidence, processContract, cdpBinding, startBoundary };
}

async function controlStep(state, step, options) {
  const request = state.controlChannel.issue(step, Object.assign({
    timeoutMs: state.args.controlTimeoutMs,
    allowedTransports: [state.selectedTransport],
  }, options || {}));
  state.controlRequests.push(request);
  const ack = await state.controlChannel.wait(request, { pollMs: state.args.pollMs });
  state.controlAcks.push(ack);
  return ack;
}

function candidateFromInitial(transcript, candidateIdentity) {
  const snapshotRequest = domainRequests(transcript, "equipment_tuning")[0];
  const snapshotResponse = snapshotRequest && exactResponse(transcript, snapshotRequest);
  if (!snapshotResponse || !snapshotResponse.message.snapshot) return null;
  const parsed = Protocol.snapshot(snapshotResponse.message.snapshot, "runner.initial");
  const matches = parsed.candidates.filter((entry) => entry.itemName === candidateIdentity.itemName
    && entry.displayName === candidateIdentity.displayName && entry.icon === candidateIdentity.icon);
  if (matches.length !== 1) return null;
  const candidate = matches[0];
  return candidate && candidate.available && candidate.owned > 0
    ? { parsed, candidate } : null;
}

function capability(processContract) {
  const artifact = { schema: "workbench-live-e2e.equipment.launch-capability.v2",
    processContractSha256: processContract.artifactSha256,
    launchMode: "legacy_http_automation", agentRuntimeAdmission: false };
  return { schema: CAPABILITY_SCHEMA, available: false,
    source: "authenticated_legacy_http_process_contract", artifact,
    artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(artifact)) };
}

function authorization(args, candidateKey) {
  const decision = { schema: AUTHORIZATION_SCHEMA,
    decisionId: "equipment-commit-" + timestampId(), issuedAt: new Date().toISOString(),
    source: "cli_explicit_flag", oneShot: true, allowedStep: "commit_candidate_b",
    scope: { journey: "equipment-install-mod-v2", slot: args.targetSlot,
      candidateKey, operation: "install_mod",
      candidateRoot: path.resolve(args.candidateRoot) } };
  return { decision, sha256: Evidence.sha256Text(Evidence.canonicalJson(decision)) };
}

async function waitForNoRuntime(lifecycle, args) {
  return LauncherObservation.waitForCleanResidue({ root: ROOT,
    runtimeIdentity: lifecycle.identity, sessionEvidence: lifecycle.sessionEvidence,
    cdpBinding: lifecycle.cdpBinding,
    timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs, stableSamples: 3 });
}

async function execute(args, lifecycle) {
  validateArgs(args);
  const runDir = createRunDirectory(args.targetSlot);
  const runId = path.basename(runDir);
  const productionClosure = ProductionClosure.captureProductionClosure(ROOT);
  const state = { args, runDir, controlRequests: [], controlAcks: [],
    selectedTransport: "codex_computer_use", observer: null };
  let lock = null;
  let preparation = null;
  let first = null;
  let restart = null;
  let candidateProducer = null;
  let mutationPossible = false;
  let safeExitCompleted = false;
  try {
    if (!process.env.APPDATA) fail("appdata_root_missing", "clone_prepare",
      "APPDATA is required to prove the complete owned SOL set");
    const appData = Evidence.assertExactDirectory(path.resolve(process.env.APPDATA), "clone_prepare");
    const resolved = RuntimeGuard.resolveCandidateIdentityBeforeMutation({ root: ROOT,
      candidateRoot: path.resolve(args.candidateRoot), assertNoRuntime: noRuntime,
      prepareClone: (identity, candidateBeforeClone) => {
        ProductionClosure.verifyProductionClosure(ROOT, productionClosure);
        candidateProducer = ProductionClosure.captureCandidateProducerBinding(
          path.resolve(args.candidateRoot), identity, productionClosure);
        lock = CloneGuard.acquireCloneLock({ root: ROOT, slot: args.targetSlot,
          runDir, ownedBaseRelative: OWNED_BASE_RELATIVE });
        try {
          preparation = CloneGuard.prepareDedicatedClone({ root: ROOT, appData, runDir,
            ownedBaseRelative: OWNED_BASE_RELATIVE, seedSlot: args.seedSlot,
            targetSlot: args.targetSlot, lock, validateSeed: validSave,
            transformJson(data) { data.lastSaved = formatLocalTimestamp(); return data; },
            transformId: "equipment-clone-lastSaved-v2", validateTarget: validSave });
          return { preparation, candidateBeforeClone };
        } catch (error) {
          try { CloneGuard.releaseCloneLock(lock); } catch (_releaseError) {}
          throw error;
        }
      } });
    lifecycle.checkpoint("clone_prepared");
    const expectedIdentity = resolved.identity;
    const productionBinding = ProductionClosure.bindProductionClosure(
      productionClosure, expectedIdentity, runId, candidateProducer);
    first = await startLifecycle(args, preparation, expectedIdentity);
    state.controlChannel = new ControlChannel(ROOT, runDir);
    if (state.controlChannel.runId !== runId) {
      fail("control_run_id_invalid", "control", "control channel crossed the live run identity");
    }
    state.observer = await attachPassiveObserver({ root: ROOT, runDir,
      observerId: "equipment-first", cdpBinding: first.cdpBinding,
      runtimeIdentity: first.identity, timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
    await controlStep(state, "open_tuning", {
      instructions: "Use the native HUD Equipment/调制 entry to open the direct production workbench once.",
      selectors: ["native HUD equipment tuning entry"],
      expectedIndependentEvidence: ["one production workbench owner becomes visible"],
    });
    await controlStep(state, "select_source", {
      instructions: "Click 背包 physical slot " + args.sourceSlot + " exactly once; do not drag or mutate.",
      selectors: ["button[data-physical-slot=\"" + args.sourceSlot + "\"]"],
      expectedIndependentEvidence: ["first tuning snapshot", "first inventory snapshot"],
    });
    let firstTranscript = await waitForTranscript(state.observer,
      (value) => expectedCounts(value, ["snapshot"], 1), args, "initial_snapshot");
    const initialA = candidateFromInitial(firstTranscript, CANDIDATE_A);
    const initialB = candidateFromInitial(firstTranscript, CANDIDATE_B);
    if (!initialA || !initialB || initialA.parsed.source.containerId !== args.sourceContainer
        || initialA.parsed.source.slot !== args.sourceSlot
        || initialA.candidate.candidateKey === initialB.candidate.candidateKey) {
      fail("canonical_fixture_unavailable", "initial_snapshot",
        "dedicated seed does not expose both frozen all-distinct candidates at the exact source");
    }
    const initialDisk = captureDiskProjection(ROOT, args.targetSlot,
      initialA.parsed.source, initialA.parsed.equipment.raw,
      [initialA.candidate, initialB.candidate]);
    const targetPreparedStable = await stableTargetSet(appData, args.targetSlot, args);
    const targetPrepared = targetPreparedStable.set;
    await controlStep(state, "preview_candidate_a", {
      instructions: "Click the plugin candidate with candidateKey "
        + initialA.candidate.candidateKey + " once.",
      selectors: ["button[data-candidate-key=\"" + initialA.candidate.candidateKey + "\"]"],
      expectedIndependentEvidence: ["one preview request/response for candidate A"],
    });
    await waitForTranscript(state.observer,
      (value) => expectedCounts(value, ["snapshot", "preview"], 1), args, "preview_a");
    await controlStep(state, "preview_candidate_b", {
      instructions: "Click the frozen all-distinct plugin candidate "
        + initialB.candidate.candidateKey + " once.",
      selectors: ["button[data-candidate-key=\"" + initialB.candidate.candidateKey + "\"]"],
      expectedIndependentEvidence: ["second distinct preview replaces candidate A authority"],
    });
    await waitForTranscript(state.observer,
      (value) => expectedCounts(value, ["snapshot", "preview", "preview"], 1), args, "preview_b");
    const commitAuthorization = authorization(args, initialB.candidate.candidateKey);
    // From this point forward the external controller may have delivered the real
    // commit even if its acknowledgement or later evidence is lost. Never replace
    // the required SAFEEXIT path with a transport shutdown on that uncertainty.
    mutationPossible = true;
    await controlStep(state, "commit_candidate_b", {
      instructions: "Click the visible Equipment confirmation button exactly once; do not use keyboard automation or retry.",
      selectors: [".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]"],
      expectedIndependentEvidence: ["one commit consumes final preview", "one inventory refresh"],
      requiresCommitAuthorization: true,
      authorizationRef: { decisionId: commitAuthorization.decision.decisionId,
        decisionSha256: commitAuthorization.sha256 },
    });
    await waitForTranscript(state.observer,
      (value) => expectedCounts(value, ["snapshot", "preview", "preview", "commit"], 2),
    args, "commit");
    await controlStep(state, "reselect_source", {
      instructions: "After refresh settles, click the same 背包 physical slot " + args.sourceSlot
        + " exactly once to force a new authoritative tuning snapshot.",
      selectors: ["button[data-physical-slot=\"" + args.sourceSlot + "\"]"],
      expectedIndependentEvidence: ["fresh post-commit tuning snapshot"],
    });
    firstTranscript = await waitForTranscript(state.observer,
      (value) => expectedCounts(value,
        ["snapshot", "preview", "preview", "commit", "snapshot"], 2),
    args, "fresh_postcommit_snapshot");
    await controlStep(state, "close_first_tuning", {
      instructions: "Click the production workbench header close button once.",
      selectors: ["button[data-header-action=\"close\"]"],
      expectedIndependentEvidence: ["one tuning detach response"],
    });
    firstTranscript = await waitForTranscript(state.observer,
      (value) => expectedCounts(value,
        ["snapshot", "preview", "preview", "commit", "snapshot", "detach"], 2),
    args, "first_detach");
    const firstCheckpoint = Protocol.verifyFirstTranscript(firstTranscript, {
      requireObserverDetached: false,
    });
    await waitForExactCloseReceipt(first.session, firstCheckpoint.pairs.panelInstanceId,
      args, "first_close");
    const firstTerminalCapture = await state.observer.terminalCapture(
      productionClosure, productionBinding, "first", runId);
    const firstLoadedProduction = firstTerminalCapture.loadedProduction;
    const firstTranscriptClosed = firstTerminalCapture.transcript;
    state.observer = null;
    const firstSemantic = Protocol.verifyFirstTranscript(firstTranscriptClosed);
    await controlStep(state, "safe_exit", {
      instructions: "Click Launcher native SAFEEXIT once and wait until the save reaches Done. Do not click confirm yet.",
      selectors: ["native SAFEEXIT"],
      expectedIndependentEvidence: ["sv:1", "sv:2", "one exact archive"],
    });
    let firstFinalLog = null;
    let firstDisk = null;
    let archiveEvidence = null;
    const archiveDeadline = Date.now() + args.evidenceTimeoutMs;
    while (Date.now() <= archiveDeadline && !archiveEvidence) {
      try {
        firstFinalLog = await first.session.readTerminalLogSnapshot(2000);
        firstDisk = LauncherObservation.captureDiskSaveEvidence({ root: ROOT,
          slot: args.targetSlot });
        archiveEvidence = LauncherObservation.verifyArchiveSaveEvidence({ root: ROOT,
          slot: args.targetSlot, boundary: first.startBoundary, snapshot: firstFinalLog,
          diskEvidence: firstDisk, requiredOrder: ["sv1", "sv2", "archive"] });
      } catch (_error) { archiveEvidence = null; }
      if (!archiveEvidence) await new Promise((resolve) => setTimeout(resolve, args.pollMs));
    }
    if (!archiveEvidence) fail("archive_evidence_timeout", "safe_exit",
      "SAFEEXIT did not produce one exact sv1/sv2/archive/disk closure");
    const afterCommitStable = await stableTargetSet(appData, args.targetSlot, args);
    const afterCommit = afterCommitStable.set;
    const diskAfterCommit = captureDiskProjection(ROOT, args.targetSlot,
      firstCheckpoint.initial.source, firstCheckpoint.commit.after.equipment.raw,
      [firstCheckpoint.candidateA, firstCheckpoint.candidateB]);
    await controlStep(state, "exit_confirm", {
      instructions: "Only after the native save state is Done, click Launcher native EXIT_CONFIRM exactly once.",
      selectors: ["native EXIT_CONFIRM"],
      expectedIndependentEvidence: ["authenticated first runtime exits", "no PID/port/credential residue"],
    });
    const afterSafeExitResidue = await waitForNoRuntime(first, args);
    safeExitCompleted = true;
    lifecycle.checkpoint("first_captured");

    noRuntime();
    restart = await startLifecycle(args, preparation, expectedIdentity);
    LauncherObservation.assertFreshAuthenticatedRestart({ first: first.identity,
      restart: restart.identity, firstAttemptId: first.attemptId,
      restartAttemptId: restart.attemptId, firstSession: first.sessionEvidence,
      restartSession: restart.sessionEvidence });
    state.observer = await attachPassiveObserver({ root: ROOT, runDir,
      observerId: "equipment-restart", cdpBinding: restart.cdpBinding,
      runtimeIdentity: restart.identity, timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
    await controlStep(state, "restart_open_tuning", {
      instructions: "Open the production Equipment workbench once after restart; do not mutate.",
      selectors: ["native HUD equipment tuning entry"],
      expectedIndependentEvidence: ["fresh panel/view owner"],
    });
    await controlStep(state, "restart_select_source", {
      instructions: "Click the same 背包 physical slot " + args.sourceSlot + " exactly once; readback only.",
      selectors: ["button[data-physical-slot=\"" + args.sourceSlot + "\"]"],
      expectedIndependentEvidence: ["fresh tuning and inventory readback"],
    });
    let restartTranscript = await waitForTranscript(state.observer,
      (value) => expectedCounts(value, ["snapshot"], 1), args, "restart_readback");
    await controlStep(state, "restart_close_tuning", {
      instructions: "Close the restart workbench once without selecting any candidate.",
      selectors: ["button[data-header-action=\"close\"]"],
      expectedIndependentEvidence: ["one restart detach response", "no mutation command"],
    });
    restartTranscript = await waitForTranscript(state.observer,
      (value) => expectedCounts(value, ["snapshot", "detach"], 1), args, "restart_detach");
    const restartCheckpoint = Protocol.verifyRestartTranscript(restartTranscript, firstSemantic, {
      requireObserverDetached: false,
    });
    const restartFinalLog = await waitForExactCloseReceipt(restart.session,
      restartCheckpoint.pairs.panelInstanceId, args, "restart_close");
    const restartTerminalCapture = await state.observer.terminalCapture(
      productionClosure, productionBinding, "restart", runId);
    const restartLoadedProduction = restartTerminalCapture.loadedProduction;
    const restartTranscriptClosed = restartTerminalCapture.transcript;
    state.observer = null;
    const restartSemantic = Protocol.verifyRestartTranscript(
      restartTranscriptClosed, firstSemantic);
    const afterRestartStable = await stableTargetSet(appData, args.targetSlot, args);
    const afterRestart = afterRestartStable.set;
    const diskAfterRestart = captureDiskProjection(ROOT, args.targetSlot,
      restartCheckpoint.readback.source, restartCheckpoint.readback.equipment.raw,
      [firstSemantic.candidateA, firstSemantic.candidateB]);
    Protocol.verifyInventory(firstTranscriptClosed, restartTranscriptClosed,
      firstSemantic, restartSemantic);
    const shutdownRequestedAt = new Date().toISOString();
    const shutdown = await restart.session.agentControl("shutdown");
    LauncherObservation.assertResponseSucceeded(shutdown, "shutdown", "agent_control shutdown");
    const shutdownEvidence = {
      schema: "workbench-live-e2e.equipment.authenticated-shutdown.v1",
      requestedAt: shutdownRequestedAt,
      completedAt: new Date().toISOString(),
      pid: restart.identity.pid,
      sessionEvidenceSha256: restart.sessionEvidence.sessionEvidenceSha256,
      response: shutdown,
    };
    shutdownEvidence.evidenceSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(shutdownEvidence));
    const finalResidue = await waitForNoRuntime(restart, args);
    const seedEnd = CloneGuard.captureSlotArtifactSet({ root: ROOT, appData,
      slot: args.seedSlot, requireJson: true });
    CloneGuard.assertArtifactSetInvariant(preparation.seedBegin, seedEnd);
    const release = CloneGuard.releaseDedicatedClone({ preparation, lock, appData });
    lifecycle.checkpoint("restart_captured");

    const bundle = { schema: BUNDLE_SCHEMA, apiVersion: API_VERSION,
      status: "captured_unverified", deployment: "NOT_DEPLOYED",
      generatedAt: new Date().toISOString(), runId,
      evidenceMode: "live_capture", fixtureProvenance: null,
      safeExitUiJourneyVerified: true, exitMethod: "native_safe_exit_then_exit_confirm",
      root: ROOT, runDir, seedSlot: args.seedSlot, targetSlot: args.targetSlot,
      candidateRoot: path.resolve(args.candidateRoot), allowIsolatedCommit: true,
      allowCodexCuFallback: true,
      productionClosure, productionBinding, candidateProducer,
      runtime: { expectedIdentity,
        trustedCdpExpectations: { expectedPageUrl: "https://overlay.local/overlay.html",
          expectedPageOrigin: "https://overlay.local",
          expectedUserDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
          expectedListenerExecutableName: "msedgewebview2.exe" },
        first: { identity: first.identity, attemptId: first.attemptId,
          sessionEvidence: first.sessionEvidence, processContract: first.processContract,
          cdpBinding: first.cdpBinding, loadedProduction: firstLoadedProduction,
          startBoundary: first.startBoundary,
          finalLogSnapshot: firstFinalLog },
        restart: { identity: restart.identity, attemptId: restart.attemptId,
          sessionEvidence: restart.sessionEvidence, processContract: restart.processContract,
          cdpBinding: restart.cdpBinding, loadedProduction: restartLoadedProduction,
          startBoundary: restart.startBoundary,
          finalLogSnapshot: restartFinalLog, shutdownEvidence } },
      control: { selectedTransport: state.selectedTransport, fallbackAllowed: true,
        capability: capability(first.processContract), authorization: commitAuthorization.decision,
        authorizationSha256: commitAuthorization.sha256,
        requests: state.controlRequests, acks: state.controlAcks },
      transcripts: { first: firstTranscriptClosed, restart: restartTranscriptClosed },
      persistence: { seedBegin: preparation.seedBegin, seedEnd,
        targetPrepared, afterCommit, afterRestart, diskInitial: initialDisk,
        diskAfterCommit, diskAfterRestart, archiveEvidence, release,
        stability: { targetPrepared: targetPreparedStable,
          afterCommit: afterCommitStable, afterRestart: afterRestartStable } },
      residue: { afterSafeExit: afterSafeExitResidue, final: finalResidue },
      moduleJournal: null };
    return {
      runDir,
      finalize(moduleManifest) {
        bundle.moduleJournal = { manifest: moduleManifest, artifact: null };
        persistPreSealSidecars(bundle);
        const preSealVerification = verifyBundlePreSeal(bundle);
        return {
          preSealVerification: { status: "PRESEAL_VERIFIED",
            semanticSha256: preSealVerification.bundleProjectionSha256,
            evidenceSha256: preSealVerification.evidenceSha256 },
          complete(moduleArtifact) {
            bundle.moduleJournal = { manifest: moduleManifest, artifact: moduleArtifact };
            const bundlePath = path.join(runDir, "journey-bundle.json");
            atomicWriteJson(bundlePath, bundle);
            const roleByPath = { "journey-bundle.json": "verified_input",
              "equipment-first-passive-transcript.json": "raw_transcript",
              "equipment-first-passive-transcript.jsonl": "raw_transcript",
              "equipment-restart-passive-transcript.json": "raw_transcript",
              "equipment-restart-passive-transcript.jsonl": "raw_transcript",
              "evidence/host-first-final-log.json": "host_log_snapshot",
              "evidence/host-restart-final-log.json": "host_log_snapshot",
              "evidence/persistence.json": "persistence_evidence" };
            bundle.control.requests.forEach((request) => {
              roleByPath["control/requests/" + request.requestId + ".json"] = "control_request";
            });
            bundle.control.acks.forEach((ack) => {
              roleByPath["control/acks/" + ack.requestId + ".json"] = "control_ack";
              roleByPath[ack.capture.relativePath] = "provider_capture";
              roleByPath[ack.providerReceipt.artifact] = "provider_receipt";
              const provider = readJsonFile(path.join(runDir,
                ack.providerReceipt.artifact.replace(/\//g, path.sep)),
              "provider_receipt", 64 * 1024).value;
              roleByPath[provider.captureEventRef.artifact] = "provider_capture_event";
              if (provider.inputEvidence && provider.inputEvidence.kind === "native_input") {
                roleByPath[provider.inputEvidence.eventRef.artifact] = "native_input_event";
              }
            });
            const artifactManifest = buildArtifactManifest({ root: ROOT, runDir,
              runId: bundle.runId, ownedBaseRelative: OWNED_BASE_RELATIVE,
              roleByPath });
            atomicWriteJson(path.join(runDir, "artifact-manifest.json"), artifactManifest);
            const receipt = finalizePreSealVerification(bundle, preSealVerification);
            atomicWriteJson(path.join(runDir, "verified-receipt.json"), receipt);
            return { receipt, preSealVerification, bundlePath,
              receiptPath: path.join(runDir, "verified-receipt.json") };
          },
        };
      },
    };
  } catch (error) {
    if (state.observer) {
      try { await state.observer.detach(); } catch (_observerError) {}
    }
    if (!mutationPossible && first && first.session) {
      try { await first.session.agentControl("shutdown"); } catch (_shutdownError) {}
    } else if (safeExitCompleted && restart && restart.session) {
      try { await restart.session.agentControl("shutdown"); } catch (_shutdownError) {}
    }
    const diagnostic = { schema: "workbench-live-e2e.equipment.failure.v2",
      failedAt: new Date().toISOString(), code: error.code || "unhandled_error",
      phase: error.phase || "unknown", message: String(error.message || error),
      recovery: mutationPossible && !safeExitCompleted
        ? "A clone mutation may have occurred. Keep the process under operator control and use the real SAFEEXIT UI; do not reseed, overwrite, or delete evidence."
        : safeExitCompleted
          ? "The write was archived by real SAFEEXIT. Any read-only restart is eligible only for supported agent_control shutdown; preserve clone evidence."
          : preparation
            ? "No commit step was authorized. The prepared clone remains protected by durable recovery state; do not reseed or delete evidence."
            : "No clone preparation completed." };
    try { atomicWriteJson(path.join(runDir, "failure.json"), diagnostic); } catch (_persistError) {}
    throw error;
  }
}

function main(argv, lifecycle) {
  const args = validateArgs(parseArgs(argv));
  if (args.help) { printHelp(); return { checkOnly: true, output: null }; }
  if (args.check) {
    return { checkOnly: true, output: { ok: true, schema: BUNDLE_SCHEMA,
      defaultSeedSlot: DEFAULT_SEED_SLOT, defaultTargetSlot: DEFAULT_TARGET_SLOT,
      fixedEntry: "node tools/workbench-live-e2e/equipment/bootstrap.js" } };
  }
  return execute(args, lifecycle);
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
  console.error("Equipment live journey requires: node tools/workbench-live-e2e/equipment/bootstrap.js");
  process.exit(2);
}
