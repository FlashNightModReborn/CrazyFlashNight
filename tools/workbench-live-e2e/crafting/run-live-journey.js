"use strict";

const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const RuntimeGuard = require("../lib/runtime-guard");
const {
  API_VERSION,
  AUTHORIZATION_SCHEMA,
  BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA,
  OWNED_BASE_RELATIVE,
  atomicWriteJson,
  buildArtifactManifest,
  fail,
} = require("./common");
const { attachPassiveObserver } = require("./cdp-passive-observer");
const { ControlChannel, expectedControlIntent } = require("./control-channel");
const Protocol = require("./protocol");
const SourceContract = require("./source-contract");
const { artifactRolesForBundle, finalizePreSealVerification,
  verifyBundlePreSeal } = require("./evidence-verifier");

const ROOT = path.resolve(__dirname, "..", "..", "..");
const DEFAULT_SEED_SLOT = "cf7_agent_a3_crafting_seed";
const DEFAULT_TARGET_SLOT = "cf7_agent_a3_crafting_run";

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
  const args = {
    candidateRoot: null,
    seedSlot: DEFAULT_SEED_SLOT,
    targetSlot: DEFAULT_TARGET_SLOT,
    category: null,
    recipeIndex: null,
    craftCount: 1,
    allowIsolatedCommit: false,
    allowCodexCuFallback: false,
    readyTimeoutMs: 180000,
    controlTimeoutMs: 900000,
    evidenceTimeoutMs: 120000,
    stableTimeoutMs: 30000,
    stableMs: 2000,
    pollMs: 250,
    check: false,
    help: false,
  };
  const seen = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token.startsWith("--") || token === "-h") {
      const canonical = token === "-h" ? "--help" : token;
      if (seen.has(canonical)) usage("duplicate argument: " + token);
      seen.add(canonical);
    }
    if (token === "--help" || token === "-h") args.help = true;
    else if (token === "--check") args.check = true;
    else if (token === "--allow-isolated-commit") args.allowIsolatedCommit = true;
    else if (token === "--allow-codex-cu-fallback") args.allowCodexCuFallback = true;
    else if (["--candidate-root", "--seed-slot", "--target-slot", "--category",
      "--recipe-index", "--craft-count", "--ready-timeout-ms", "--control-timeout-ms",
      "--evidence-timeout-ms", "--stable-timeout-ms", "--stable-ms", "--poll-ms"].includes(token)) {
      const key = token.slice(2).replace(/-([a-z])/g, (_all, letter) => letter.toUpperCase());
      args[key] = take(argv, index, token);
      index += 1;
    } else usage("unknown argument: " + token);
  }
  ["recipeIndex", "craftCount", "readyTimeoutMs", "controlTimeoutMs",
    "evidenceTimeoutMs", "stableTimeoutMs", "stableMs", "pollMs"].forEach((key) => {
    if (args[key] != null) args[key] = Number(args[key]);
  });
  return args;
}

function validateArgs(args) {
  if (args.help || args.check) return args;
  if (!args.candidateRoot) usage("--candidate-root is required; formal runtime is never used");
  CloneGuard.assertSourceSlot(args.seedSlot);
  CloneGuard.assertDedicatedSlot(args.targetSlot);
  if (args.seedSlot === args.targetSlot) usage("seed and target slots must differ");
  if (args.category != null && !Protocol.CATEGORY_SET.has(args.category)) {
    usage("--category must be one canonical Crafting category when supplied");
  }
  if (args.recipeIndex != null && (!Number.isInteger(args.recipeIndex)
      || args.recipeIndex < 0 || args.recipeIndex > 999)) {
    usage("--recipe-index must be an integer in 0..999");
  }
  if (!Number.isInteger(args.craftCount) || args.craftCount < 1 || args.craftCount > 99) {
    usage("--craft-count must be an integer in 1..99");
  }
  if (!args.allowIsolatedCommit) {
    usage("--allow-isolated-commit is required for the one bounded Crafting write");
  }
  if (!args.allowCodexCuFallback) {
    usage("--allow-codex-cu-fallback is required when actual Launcher argv denies Agent Runtime admission");
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
  return { usage: [
    "Crafting isolated two-process production journey (tooling only)",
    "",
    "Fixed entry (shared journal FROZEN-v2/GO; Crafting live remains separately blocked):",
    "  node tools/workbench-live-e2e/crafting/bootstrap.js --candidate-root <candidate> \\",
    "    [--category <canonical-category>] [--recipe-index <0..999>] --craft-count <1..99> \\",
    "    --allow-isolated-commit --allow-codex-cu-fallback",
    "",
    "The runner chooses the lowest recipeIndex with canCraftOne=true from the live snapshot",
    "unless optional category/recipe constraints are supplied. It always prepares a dedicated clone.",
    "It never calls Crafting",
    "business APIs and never synthesizes input. It emits bounded computer-use requests.",
    "The commit needs one exact CLI authorization and one exact external acknowledgement.",
  ].join("\n") };
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

function formatLocalTimestamp(value) {
  const now = value || new Date();
  const part = (number) => String(number).padStart(2, "0");
  return now.getFullYear() + "-" + part(now.getMonth() + 1) + "-" + part(now.getDate())
    + " " + part(now.getHours()) + ":" + part(now.getMinutes()) + ":" + part(now.getSeconds());
}

function noRuntime() {
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  return true;
}

function parseObservedMessage(event) {
  if (!event || !event.message) return null;
  if (Evidence.isPlainObject(event.message)) return event.message;
  try { return JSON.parse(String(event.message)); } catch (_error) { return null; }
}

function domainEntries(transcript, kind) {
  return transcript.events.map((event) => ({ event, message: parseObservedMessage(event) }))
    .filter((entry) => entry.event.kind === kind && entry.message
      && entry.message.domain === "crafting" && typeof entry.message.cmd === "string");
}

function exactResponse(transcript, request) {
  const matches = transcript.events.map((event) => ({ event, message: parseObservedMessage(event) }))
    .filter((entry) => entry.event.kind === "webview_message" && entry.message
      && entry.message.type === "panel_resp"
      && entry.message.domain === request.message.domain
      && entry.message.callId === request.message.callId
      && entry.message.panelInstanceId === request.message.panelInstanceId
      && entry.message.cmd === request.message.cmd
      && entry.event.sequence > request.event.sequence);
  return matches.length === 1 ? matches[0] : null;
}

function exactCommands(transcript, expected) {
  const requests = domainEntries(transcript, "bridge_send");
  return Evidence.canonicalJson(requests.map((entry) => entry.message.cmd))
      === Evidence.canonicalJson(expected)
    && requests.every((entry) => exactResponse(transcript, entry));
}

function exactInventoryCommands(transcript, expected) {
  const requests = transcript.events.map((event) => ({ event, message: parseObservedMessage(event) }))
    .filter((entry) => entry.event.kind === "bridge_send" && entry.message
      && entry.message.domain === "inventory");
  return Evidence.canonicalJson(requests.map((entry) => entry.message.cmd))
      === Evidence.canonicalJson(expected)
    && requests.every((entry) => exactResponse(transcript, entry));
}

function exactCloseOwner(transcript) {
  const clicks = transcript.events.filter((event) => event.kind === "dom_input"
    && event.eventType === "click" && event.isTrusted === true && event.target
    && event.target.attributes && event.target.attributes["data-header-action"] === "close");
  const sends = transcript.events.map((event) => ({ event, message: parseObservedMessage(event) }))
    .filter((entry) => entry.event.kind === "bridge_send" && entry.message
      && entry.message.type === "panel" && entry.message.cmd === "close"
      && entry.message.panel === "crafting");
  if (clicks.length !== 1 || sends.length !== 1
      || clicks[0].sequence >= sends[0].event.sequence
      || typeof sends[0].message.panelInstanceId !== "string"
      || !sends[0].message.panelInstanceId) return null;
  return sends[0].message.panelInstanceId;
}

function exactCloseObserved(transcript) {
  return exactCloseOwner(transcript) !== null;
}

function chooseSelection(transcript, args) {
  const requests = domainEntries(transcript, "bridge_send");
  const snapshot = requests.find((entry) => entry.message.cmd === "snapshot");
  const response = snapshot && exactResponse(transcript, snapshot);
  if (!response || !Protocol.CATEGORY_SET.has(response.message.category)
      || args.category != null && response.message.category !== args.category
      || !Array.isArray(response.message.recipes)) return null;
  const candidates = response.message.recipes.filter((entry) => entry.canCraftOne === true
    && (args.recipeIndex == null || entry.recipeIndex === args.recipeIndex))
    .sort((left, right) => left.recipeIndex - right.recipeIndex);
  if (!candidates.length) return null;
  return { category: response.message.category, recipeIndex: candidates[0].recipeIndex,
    craftCount: args.craftCount };
}

async function waitForTranscript(observer, predicate, args, phase) {
  const deadline = Date.now() + args.evidenceTimeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    await observer.health();
    last = observer.snapshot();
    if (predicate(last)) return last;
    await new Promise((resolve) => setTimeout(resolve, args.pollMs));
  }
  fail("journey_evidence_timeout", phase,
    "independent passive evidence did not settle", {
      eventCount: last && last.eventCount,
    });
}

function candidateProjection(transcript, args, selected) {
  const requests = domainEntries(transcript, "bridge_send");
  const snapshot = requests.find((entry) => entry.message.cmd === "snapshot");
  const previews = requests.filter((entry) => entry.message.cmd === "preview");
  const snapshotResponse = snapshot && exactResponse(transcript, snapshot);
  const previewResponse = previews.length && exactResponse(transcript, previews[previews.length - 1]);
  if (!snapshotResponse || !previewResponse) return null;
  const category = selected ? selected.category : args.category || snapshotResponse.message.category;
  const candidates = Array.isArray(snapshotResponse.message.recipes)
    ? snapshotResponse.message.recipes.filter((entry) => entry.canCraftOne === true
      && (selected ? entry.recipeIndex === selected.recipeIndex
        : args.recipeIndex == null || entry.recipeIndex === args.recipeIndex)) : [];
  candidates.sort((left, right) => left.recipeIndex - right.recipeIndex);
  const recipe = candidates.length ? [candidates[0]] : [];
  const preview = previewResponse.message;
  if (recipe.length !== 1 || preview.category !== category
      || preview.recipeIndex !== recipe[0].recipeIndex || preview.craftCount !== args.craftCount
      || preview.canCommit !== true || !preview.craftTokenRef) return null;
  return { recipe: recipe[0], preview,
    selector: { category, recipeIndex: recipe[0].recipeIndex, craftCount: args.craftCount } };
}

async function startLifecycle(args, preparation, expectedIdentity) {
  const cdpBinding = await RuntimeGuard.allocateLoopbackCdpPort();
  LauncherObservation.startLauncherCandidate({
    root: ROOT, candidateRoot: path.resolve(args.candidateRoot),
    expectedIdentity, cdpPort: cdpBinding.port,
  });
  const session = await LauncherObservation.waitForAuthenticatedLegacyHttp({
    root: ROOT, timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
  });
  const identity = session.verifyRuntimeIdentity(expectedIdentity);
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), identity.pid);
  const processContract = LauncherObservation.attestAuthenticatedLauncherProcess({
    root: ROOT, sessionEvidence: session.evidence, runtimeIdentity: identity,
  });
  cdpBinding.runtimePid = identity.pid;
  cdpBinding.configurationSource = "CF7_WEBVIEW2_ARGS";
  cdpBinding.developerMode = true;
  const startBoundary = LauncherObservation.createTerminalLogBoundary(
    await session.readTerminalLogSnapshot(2000));
  await LauncherObservation.waitForAgentControl(session, {
    timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
  });
  const startResponse = await session.agentControl("start", {
    slot: preparation.targetSlot, fresh: false, deferReveal: false,
    requireFlashReveal: true, rememberSlot: false,
  });
  LauncherObservation.assertResponseSucceeded(startResponse, "launcher", "agent_control start");
  const ready = await LauncherObservation.waitForRuntimeReady(session, {
    slot: preparation.targetSlot, timeoutMs: args.readyTimeoutMs,
    pollMs: args.pollMs, startBoundary, startResponse,
  });
  return { identity, attemptId: ready.expectedAttemptId, session,
    sessionEvidence: session.evidence, processContract, cdpBinding, startBoundary };
}

async function controlStep(state, step, options) {
  const exactIntent = expectedControlIntent(step, {
    recipeIndex: state.selected && state.selected.recipeIndex,
  });
  const request = state.controlChannel.issue(step, Object.assign({}, options || {}, exactIntent, {
    timeoutMs: state.args.controlTimeoutMs,
    allowedTransports: [state.selectedTransport],
  }));
  state.controlRequests.push(request);
  const ack = await state.controlChannel.wait(request, { pollMs: state.args.pollMs });
  state.controlAcks.push(ack);
  return ack;
}

function capability(processContract, sessionEvidence) {
  if (processContract.agentRuntimeAdmission !== false
      || processContract.legacyHttpAutomationArg !== true) {
    fail("crafting_agent_runtime_contract_unsupported", "control",
      "Crafting v1 admits only the authenticated legacy HTTP lifecycle");
  }
  const artifact = {
    schema: "workbench-live-e2e.crafting.launch-capability.v3",
    processContractSha256: processContract.artifactSha256,
    commandLineSha256: processContract.commandLineSha256,
    argvSha256: processContract.argvSha256,
    launchMode: "legacy_http_automation",
    agentRuntimeAdmission: false,
    legacyHttpAutomationArg: true,
    credentialCapabilitiesSha256: Evidence.sha256Text(
      Evidence.canonicalJson(sessionEvidence.capabilities)),
  };
  return { schema: CAPABILITY_SCHEMA, available: false,
    source: "authenticated_process_contract", artifact,
    artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(artifact)) };
}

function authorization(args, selector) {
  const decision = {
    schema: AUTHORIZATION_SCHEMA,
    decisionId: "crafting-commit-" + timestampId(),
    issuedAt: new Date().toISOString(),
    source: "cli_explicit_flag",
    oneShot: true,
    allowedStep: "commit_recipe",
    scope: {
      journey: "crafting-commit-v3",
      slot: args.targetSlot,
      category: selector.category,
      recipeIndex: selector.recipeIndex,
      craftCount: selector.craftCount,
      operation: "craft",
      candidateRoot: path.resolve(args.candidateRoot),
    },
  };
  return { decision, sha256: Evidence.sha256Text(Evidence.canonicalJson(decision)) };
}

async function waitForNoRuntime(lifecycle, args) {
  return LauncherObservation.waitForCleanResidue({
    root: ROOT, runtimeIdentity: lifecycle.identity,
    sessionEvidence: lifecycle.sessionEvidence, cdpBinding: lifecycle.cdpBinding,
    timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs, stableSamples: 3,
  });
}

async function stableTarget(appData, args) {
  return CloneGuard.captureStableSlotArtifactSet({
    root: ROOT, appData, slot: args.targetSlot, requireJson: true,
    timeoutMs: args.stableTimeoutMs, stableMs: args.stableMs, pollMs: args.pollMs,
  });
}

function rawHostArtifact(label, lifecycle, finalLogSnapshot) {
  return {
    schema: "workbench-live-e2e.crafting.host-as2-tail.v3",
    label,
    sessionEvidence: lifecycle.sessionEvidence,
    startBoundary: lifecycle.startBoundary,
    finalLogSnapshot,
    records: LauncherObservation.recordsAfterTerminalBoundary(
      lifecycle.startBoundary, finalLogSnapshot),
  };
}

async function waitForExactCloseCompletion(lifecycle, owner, args, phase) {
  const expected = "event=panel_exact_close_completed panel=crafting panelInstanceId=" + owner;
  const deadline = Date.now() + args.evidenceTimeoutMs;
  while (Date.now() <= deadline) {
    const snapshot = await lifecycle.session.readTerminalLogSnapshot(2000);
    const records = LauncherObservation.recordsAfterTerminalBoundary(
      lifecycle.startBoundary, snapshot);
    const matches = records.filter((record) => String(record.line || "").includes(expected));
    if (matches.length > 1) {
      fail("host_close_completion_count_invalid", phase,
        "exact Crafting close completion was duplicated", { owner, count: matches.length });
    }
    if (matches.length === 1) return { snapshot, record: matches[0] };
    await new Promise((resolve) => setTimeout(resolve, args.pollMs));
  }
  fail("host_close_completion_timeout", phase,
    "Host did not emit the exact Crafting owner close completion", { owner });
}

function captureSourcePhase(root, records, baseline, phase) {
  const fingerprint = phase === "initial" ? baseline
    : SourceContract.captureSourceFingerprint(root);
  SourceContract.assertSameFingerprint(baseline, fingerprint, "source_" + phase);
  records.push({ phase, observedAt: new Date().toISOString(), fingerprint });
  return fingerprint;
}

async function execute(args, lifecycle) {
  validateArgs(args);
  const runDir = createRunDirectory(args.targetSlot);
  const state = {
    args, runDir, selectedTransport: null,
    controlRequests: [], controlAcks: [], controlChannel: null, observer: null,
  };
  let lock = null;
  let preparation = null;
  let first = null;
  let restart = null;
  let safeExitStarted = false;
  let commitMayHaveReachedAuthority = false;
  let selected = null;
  let sourceBinding = null;
  let candidateProducer = null;
  let firstLoadedProduction = null;
  let restartLoadedProduction = null;
  let restartShutdownEvidence = null;
  try {
    const sourceRecords = [];
    const sourceBaseline = SourceContract.captureSourceFingerprint(ROOT);
    captureSourcePhase(ROOT, sourceRecords, sourceBaseline, "initial");
    if (!process.env.APPDATA) {
      fail("appdata_root_missing", "clone_prepare",
        "APPDATA is required to prove the complete owned SOL set");
    }
    const appData = Evidence.assertExactDirectory(path.resolve(process.env.APPDATA), "clone_prepare");
    const resolved = RuntimeGuard.resolveCandidateIdentityBeforeMutation({
      root: ROOT,
      candidateRoot: path.resolve(args.candidateRoot),
      assertNoRuntime: noRuntime,
      prepareClone: (_identity, candidateBeforeClone) => {
        lock = CloneGuard.acquireCloneLock({
          root: ROOT, slot: args.targetSlot, runDir,
          ownedBaseRelative: OWNED_BASE_RELATIVE,
        });
        try {
          preparation = CloneGuard.prepareDedicatedClone({
            root: ROOT, appData, runDir, ownedBaseRelative: OWNED_BASE_RELATIVE,
            seedSlot: args.seedSlot, targetSlot: args.targetSlot, lock,
            validateSeed: validSave,
            transformJson(data) { data.lastSaved = formatLocalTimestamp(); return data; },
            transformId: "crafting-clone-lastSaved-v3",
            validateTarget: validSave,
          });
          return { preparationSha256: preparation.preparationSha256, candidateBeforeClone };
        } catch (error) {
          try { CloneGuard.releaseCloneLock(lock); } catch (_releaseError) {}
          throw error;
        }
      },
    });
    lifecycle.checkpoint("clone_prepared");
    const preparedStable = await stableTarget(appData, args);
    CloneGuard.assertArtifactSetInvariant(
      preparation.targetPrepared, preparedStable.set, "target_prepared_changed");
    const expectedIdentity = resolved.identity;
    candidateProducer = SourceContract.captureCandidateProducerBinding(
      args.candidateRoot, expectedIdentity, sourceBaseline);
    sourceBinding = SourceContract.bindSourceClosure(sourceBaseline,
      expectedIdentity, path.basename(runDir), args.candidateRoot, candidateProducer);
    captureSourcePhase(ROOT, sourceRecords, sourceBaseline, "before_first_start");

    first = await startLifecycle(args, preparation, expectedIdentity);
    const firstCapability = capability(first.processContract, first.sessionEvidence);
    state.selectedTransport = "codex_computer_use";
    state.controlChannel = new ControlChannel(ROOT, runDir);
    state.observer = await attachPassiveObserver({
      root: ROOT, runDir, observerId: "crafting-first",
      cdpBinding: first.cdpBinding, runtimeIdentity: first.identity,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
    });
    await controlStep(state, "open_crafting", {
      instructions: "Use the in-game world Crafting entry to open the production Crafting workbench once.",
      selectors: ["world crafting entry"],
      expectedIndependentEvidence: ["panel_cmd open from world_crafting_entry", "snapshot and auto preview"],
    });
    const initialTranscript = await waitForTranscript(state.observer,
      (value) => exactCommands(value, ["snapshot", "preview"])
        && !!chooseSelection(value, args), args, "initial_candidate");
    selected = chooseSelection(initialTranscript, args);
    state.selected = selected;
    await controlStep(state, "select_recipe", {
      instructions: "Click the exact production recipe card for recipeIndex "
        + selected.recipeIndex + " once.",
      selectors: [".crafting-recipe-card[data-workbench-key=\""
        + selected.recipeIndex + "\"]"],
      expectedIndependentEvidence: ["one trusted recipe click", "one new exact preview"],
    });
    await waitForTranscript(state.observer,
      (value) => exactCommands(value, ["snapshot", "preview", "preview"])
        && !!candidateProjection(value, args, selected), args, "selected_candidate");
    await controlStep(state, "capture_inventory_before", {
      instructions: "Click the visible 背包 / 战备箱 header action once and wait for both full panes.",
      selectors: [".crafting-organizer-btn"],
      expectedIndependentEvidence: ["Crafting pre-organizer snapshot", "one Inventory full snapshot"],
    });
    await waitForTranscript(state.observer, (value) =>
      exactCommands(value, Protocol.FIRST_COMMANDS.slice(0, 4))
        && exactInventoryCommands(value, ["snapshot"]), args, "inventory_before");
    await controlStep(state, "return_from_inventory_before", {
      instructions: "Click 返回合成 once and wait for the same recipe preview to refresh.",
      selectors: [".inventory-return-crafting-btn"],
      expectedIndependentEvidence: ["fresh Crafting snapshot and preview"],
    });
    const preCommitTranscript = await waitForTranscript(state.observer, (value) =>
      exactCommands(value, Protocol.FIRST_COMMANDS.slice(0, 6))
      && exactInventoryCommands(value, ["snapshot"])
      && !!candidateProjection(value, args, selected), args, "return_before_commit");
    // This admission runs before authorization construction and, critically, before
    // the provider receives any commit control request.  It uses the same physical
    // bag planner later used for postcondition verification.
    const preCommitAdmission = Protocol.verifyPreCommitAuthority(preCommitTranscript, selected);
    const commitAuthorization = authorization(args, selected);
    commitMayHaveReachedAuthority = true;
    await controlStep(state, "commit_recipe", {
      instructions: "Click the visible production Crafting commit button exactly once; do not retry.",
      selectors: [".crafting-commit-btn[data-commit-primary]"],
      expectedIndependentEvidence: [
        "one commit consumes selected preview token",
        "one fresh snapshot and preview prove the postcondition",
      ],
      requiresCommitAuthorization: true,
      authorizationRef: {
        decisionId: commitAuthorization.decision.decisionId,
        decisionSha256: commitAuthorization.sha256,
      },
    });
    let firstTranscript = await waitForTranscript(state.observer,
      (value) => exactCommands(value, Protocol.FIRST_COMMANDS.slice(0, 9))
        && exactInventoryCommands(value, ["snapshot"]),
    args, "commit_postcondition");
    await controlStep(state, "capture_inventory_after", {
      instructions: "After the fresh Crafting preview settles, open 背包 / 战备箱 once for poststate.",
      selectors: [".crafting-organizer-btn"],
      expectedIndependentEvidence: ["post-commit Inventory full snapshot"],
    });
    await waitForTranscript(state.observer, (value) =>
      exactCommands(value, Protocol.FIRST_COMMANDS.slice(0, 10))
        && exactInventoryCommands(value, ["snapshot", "snapshot"]),
    args, "inventory_after");
    await controlStep(state, "return_from_inventory_after", {
      instructions: "Click 返回合成 once and wait for final fresh Crafting snapshot/preview.",
      selectors: [".inventory-return-crafting-btn"],
      expectedIndependentEvidence: ["final Crafting postcondition"],
    });
    firstTranscript = await waitForTranscript(state.observer, (value) =>
      exactCommands(value, Protocol.FIRST_COMMANDS)
        && exactInventoryCommands(value, ["snapshot", "snapshot"]),
    args, "final_postcondition");
    await controlStep(state, "close_first_crafting", {
      instructions: "Close the production Crafting workbench with its header close button once.",
      selectors: ["[data-header-action=\"close\"]"],
      expectedIndependentEvidence: [
        "one trusted close input after fresh postcondition",
        "one exact owner-bound close Bridge.send",
      ],
    });
    firstTranscript = await waitForTranscript(state.observer, (value) => {
      if (!exactCommands(value, Protocol.FIRST_COMMANDS)) return false;
      return exactCloseObserved(value);
    }, args, "first_close");
    await state.observer.recordPanelState("after_close");
    firstTranscript = state.observer.snapshot();
    const firstCloseOwner = exactCloseOwner(firstTranscript);
    if (!firstCloseOwner) {
      fail("first_close_owner_missing", "first_close",
        "the exact owner-bound Crafting close was not observable before Host completion");
    }
    await waitForExactCloseCompletion(first, firstCloseOwner, args, "first_close");
    captureSourcePhase(ROOT, sourceRecords, sourceBaseline, "after_commit");

    await controlStep(state, "safe_exit", {
      instructions: "Click Launcher native SAFEEXIT once and wait for save state Done. Do not confirm exit yet.",
      selectors: ["native SAFEEXIT"],
      expectedIndependentEvidence: ["sv:1", "sv:2", "one exact archive"],
      requiresCaptureSha256: true,
    });
    safeExitStarted = true;
    let firstFinalLog = null;
    let firstDisk = null;
    let archiveEvidence = null;
    const archiveDeadline = Date.now() + args.evidenceTimeoutMs;
    while (Date.now() <= archiveDeadline && !archiveEvidence) {
      try {
        firstFinalLog = await first.session.readTerminalLogSnapshot(2000);
        firstDisk = LauncherObservation.captureDiskSaveEvidence({
          root: ROOT, slot: args.targetSlot,
        });
        archiveEvidence = LauncherObservation.verifyArchiveSaveEvidence({
          root: ROOT, slot: args.targetSlot, boundary: first.startBoundary,
          snapshot: firstFinalLog, diskEvidence: firstDisk,
          requiredOrder: ["sv1", "sv2", "archive"],
        });
      } catch (_error) { archiveEvidence = null; }
      if (!archiveEvidence) {
        await new Promise((resolve) => setTimeout(resolve, args.pollMs));
      }
    }
    if (!archiveEvidence) {
      fail("archive_evidence_timeout", "safe_exit",
        "SAFEEXIT did not produce one exact sv1/sv2/archive/disk closure");
    }
    const afterCommitStable = await stableTarget(appData, args);
    const firstDetach = await state.observer.detach(
      sourceBaseline, sourceBinding, "first", path.basename(runDir));
    const firstTranscriptClosed = firstDetach.transcript;
    firstLoadedProduction = firstDetach.loadedProduction;
    state.observer = null;
    const firstSemantic = Protocol.verifyFirstTranscript(firstTranscriptClosed);
    await controlStep(state, "exit_confirm", {
      instructions: "Only after save state Done, click Launcher native EXIT_CONFIRM exactly once.",
      selectors: ["native EXIT_CONFIRM"],
      expectedIndependentEvidence: [
        "first runtime exits", "PID/ports/rendezvous/credential residue are absent",
      ],
      requiresCaptureSha256: true,
    });
    const afterSafeExitResidue = await waitForNoRuntime(first, args);
    lifecycle.checkpoint("first_captured");

    noRuntime();
    captureSourcePhase(ROOT, sourceRecords, sourceBaseline, "before_restart");
    restart = await startLifecycle(args, preparation, expectedIdentity);
    LauncherObservation.assertFreshAuthenticatedRestart({
      first: first.identity, restart: restart.identity,
      firstAttemptId: first.attemptId, restartAttemptId: restart.attemptId,
      firstSession: first.sessionEvidence, restartSession: restart.sessionEvidence,
    });
    state.observer = await attachPassiveObserver({
      root: ROOT, runDir, observerId: "crafting-restart",
      cdpBinding: restart.cdpBinding, runtimeIdentity: restart.identity,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
    });
    await controlStep(state, "restart_open_crafting", {
      instructions: "Open the same production world Crafting entry after restart; readback only.",
      selectors: ["world crafting entry"],
      expectedIndependentEvidence: ["fresh panel owner", "fresh snapshot and auto preview"],
    });
    await waitForTranscript(state.observer,
      (value) => exactCommands(value, ["snapshot", "preview"]),
    args, "restart_initial_readback");
    await controlStep(state, "restart_select_recipe", {
      instructions: "Click the same recipeIndex " + selected.recipeIndex + " once; do not commit.",
      selectors: [".crafting-recipe-card[data-workbench-key=\""
        + selected.recipeIndex + "\"]"],
      expectedIndependentEvidence: ["fresh readback preview", "no commit"],
    });
    await waitForTranscript(state.observer,
      (value) => exactCommands(value, Protocol.RESTART_COMMANDS.slice(0, 3)),
    args, "restart_selected_readback");
    await controlStep(state, "restart_capture_inventory", {
      instructions: "Open 背包 / 战备箱 once for same-clone restart readback.",
      selectors: [".crafting-organizer-btn"],
      expectedIndependentEvidence: ["restart Inventory full snapshot"],
    });
    await waitForTranscript(state.observer, (value) =>
      exactCommands(value, Protocol.RESTART_COMMANDS.slice(0, 4))
        && exactInventoryCommands(value, ["snapshot"]), args, "restart_inventory");
    await controlStep(state, "restart_return_from_inventory", {
      instructions: "Click 返回合成 once and wait for final restart Crafting readback.",
      selectors: [".inventory-return-crafting-btn"],
      expectedIndependentEvidence: ["restart Crafting snapshot and preview"],
    });
    let restartTranscript = await waitForTranscript(state.observer, (value) =>
      exactCommands(value, Protocol.RESTART_COMMANDS)
        && exactInventoryCommands(value, ["snapshot"]), args, "restart_final_readback");
    await controlStep(state, "restart_close_crafting", {
      instructions: "Close the restart Crafting workbench once without committing.",
      selectors: ["[data-header-action=\"close\"]"],
      expectedIndependentEvidence: [
        "trusted close input", "one exact owner-bound close Bridge.send", "zero restart commit",
      ],
    });
    restartTranscript = await waitForTranscript(state.observer, (value) =>
      exactCommands(value, Protocol.RESTART_COMMANDS)
        && exactCloseObserved(value),
    args, "restart_close");
    await state.observer.recordPanelState("after_close");
    restartTranscript = state.observer.snapshot();
    const restartCloseOwner = exactCloseOwner(restartTranscript);
    if (!restartCloseOwner) {
      fail("restart_close_owner_missing", "restart_close",
        "the exact owner-bound restart Crafting close was not observable before Host completion");
    }
    await waitForExactCloseCompletion(restart, restartCloseOwner, args, "restart_close");
    const restartFinalLog = await restart.session.readTerminalLogSnapshot(2000);
    const diskAfterRestart = LauncherObservation.captureDiskSaveEvidence({
      root: ROOT, slot: args.targetSlot,
    });
    const restartStable = await stableTarget(appData, args);
    captureSourcePhase(ROOT, sourceRecords, sourceBaseline, "after_readback");
    CloneGuard.assertArtifactSetInvariant(afterCommitStable.set,
      restartStable.set, "restart_artifact_set_changed");
    const restartDetach = await state.observer.detach(
      sourceBaseline, sourceBinding, "restart", path.basename(runDir));
    const restartTranscriptClosed = restartDetach.transcript;
    restartLoadedProduction = restartDetach.loadedProduction;
    state.observer = null;
    Protocol.verifyRestartTranscript(restartTranscriptClosed, firstSemantic);
    const shutdownRequestedAt = new Date().toISOString();
    const shutdown = await restart.session.agentControl("shutdown");
    LauncherObservation.assertResponseSucceeded(shutdown, "shutdown", "agent_control shutdown");
    restartShutdownEvidence = {
      schema: "workbench-live-e2e.crafting.authenticated-shutdown.v1",
      requestedAt: shutdownRequestedAt, completedAt: new Date().toISOString(),
      pid: restart.identity.pid,
      sessionEvidenceSha256: restart.sessionEvidence.sessionEvidenceSha256,
      response: shutdown,
    };
    restartShutdownEvidence.evidenceSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(restartShutdownEvidence));
    const finalResidue = await waitForNoRuntime(restart, args);
    const seedEnd = CloneGuard.captureSlotArtifactSet({
      root: ROOT, appData, slot: args.seedSlot, requireJson: true,
    });
    CloneGuard.assertArtifactSetInvariant(preparation.seedBegin, seedEnd);
    const release = CloneGuard.releaseDedicatedClone({ preparation, lock, appData });
    captureSourcePhase(ROOT, sourceRecords, sourceBaseline, "final");
    const sourceClosure = SourceContract.sealSourceClosure(sourceRecords);
    lifecycle.checkpoint("restart_captured");

    const firstHostArtifact = rawHostArtifact("first", first, firstFinalLog);
    const restartHostArtifact = rawHostArtifact("restart", restart, restartFinalLog);
    const persistence = {
      preparation,
      stability: {
        targetPrepared: preparedStable,
        afterCommit: afterCommitStable,
        afterRestart: restartStable,
      },
      afterCommit: afterCommitStable.set,
      afterRestart: restartStable.set,
      seedEnd,
      diskAfterCommit: firstDisk,
      diskAfterRestart,
      archiveEvidence,
      release,
    };
    const runtime = {
      expectedIdentity,
      trustedCdpExpectations: {
        expectedPageUrl: "https://overlay.local/overlay.html",
        expectedPageOrigin: "https://overlay.local",
        expectedUserDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
        expectedListenerExecutableName: "msedgewebview2.exe",
      },
      first: {
        identity: first.identity, attemptId: first.attemptId,
        sessionEvidence: first.sessionEvidence, processContract: first.processContract,
        cdpBinding: first.cdpBinding, startBoundary: first.startBoundary,
        finalLogSnapshot: firstFinalLog, loadedProduction: firstLoadedProduction,
      },
      restart: {
        identity: restart.identity, attemptId: restart.attemptId,
        sessionEvidence: restart.sessionEvidence, processContract: restart.processContract,
        cdpBinding: restart.cdpBinding, startBoundary: restart.startBoundary,
        finalLogSnapshot: restartFinalLog, loadedProduction: restartLoadedProduction,
        shutdownEvidence: restartShutdownEvidence,
      },
    };
    const bundle = {
      schema: BUNDLE_SCHEMA, apiVersion: API_VERSION,
      status: "captured_unverified", deployment: "NOT_DEPLOYED",
      evidenceClass: "production_capture",
      evidenceMode: "live_capture", fixtureProvenance: null,
      safeExitUiJourneyVerified: true, exitMethod: "safeexit_ui",
      generatedAt: new Date().toISOString(), runId: path.basename(runDir),
      root: ROOT, runDir, seedSlot: args.seedSlot, targetSlot: args.targetSlot,
      candidateRoot: path.resolve(args.candidateRoot),
      allowIsolatedCommit: args.allowIsolatedCommit,
      allowCodexCuFallback: args.allowCodexCuFallback,
      runtime,
      control: {
        selectedTransport: state.selectedTransport,
        fallbackAllowed: true,
        capability: firstCapability,
        authorization: commitAuthorization.decision,
        authorizationSha256: commitAuthorization.sha256,
        preCommitAdmission: {
          status: "admitted",
          selector: preCommitAdmission.selector,
          acceptedCraftTokenRef: preCommitAdmission.acceptedPreview.craftTokenRef,
          inventoryCallId: preCommitAdmission.inventoryPair.request.callId,
          delivery: preCommitAdmission.plan.delivery,
        },
        requests: state.controlRequests,
        acks: state.controlAcks,
      },
      transcripts: { first: firstTranscriptClosed, restart: restartTranscriptClosed },
      hostArtifacts: { first: firstHostArtifact, restart: restartHostArtifact },
      sourceClosure,
      sourceBinding,
      candidateProducer,
      persistence,
      residue: { afterSafeExit: afterSafeExitResidue, final: finalResidue },
      moduleJournal: null,
    };
    atomicWriteJson(path.join(runDir, "first-host-as2-tail.json"), firstHostArtifact);
    atomicWriteJson(path.join(runDir, "restart-host-as2-tail.json"), restartHostArtifact);
    atomicWriteJson(path.join(runDir, "persistence-phases.json"), persistence);
    atomicWriteJson(path.join(runDir, "runtime-lifecycles.json"), runtime);
    atomicWriteJson(path.join(runDir, "source-closure.json"), sourceClosure);
    atomicWriteJson(path.join(runDir, "source-binding.json"), sourceBinding);
    atomicWriteJson(path.join(runDir, "candidate-producer.json"), candidateProducer);
    return {
      runDir,
      prepare(moduleManifest) {
        if (bundle.moduleJournal !== null) {
          fail("preseal_verification_reused", "module_journal",
            "live Crafting evidence may be prepared exactly once");
        }
        bundle.moduleJournal = { manifest: moduleManifest, artifact: null };
        const preSealVerification = verifyBundlePreSeal(bundle);
        let completed = false;
        return { complete(moduleArtifact) {
          if (completed) {
            fail("sealed_finalization_reused", "module_journal",
              "sealed Crafting finalization is one-shot");
          }
          completed = true;
          bundle.moduleJournal.artifact = moduleArtifact;
          const bundlePath = path.join(runDir, "journey-bundle.json");
          atomicWriteJson(bundlePath, bundle);
          const roleByPath = artifactRolesForBundle(bundle, true);
          const manifest = buildArtifactManifest({
            root: ROOT, runDir, runId: bundle.runId,
            ownedBaseRelative: OWNED_BASE_RELATIVE,
            roleByPath,
          });
          atomicWriteJson(path.join(runDir, "artifact-manifest.json"), manifest);
          const receipt = finalizePreSealVerification(bundle, preSealVerification);
          const receiptPath = path.join(runDir, "verified-receipt.json");
          atomicWriteJson(receiptPath, receipt);
          return { receipt, bundlePath, receiptPath };
        } };
      },
    };
  } catch (error) {
    if (state.observer) {
      try { await state.observer.detach(); } catch (_observerError) {}
    }
    if (commitMayHaveReachedAuthority && first && first.session) {
      try {
        if (!state.controlRequests.some((entry) => entry.step === "safe_exit")) {
          await controlStep(state, "safe_exit", {
            instructions: "Recovery: click Launcher native SAFEEXIT once and wait for save state Done.",
            selectors: ["native SAFEEXIT"], requiresCaptureSha256: true,
            expectedIndependentEvidence: ["recovery save completes"],
          });
        }
        safeExitStarted = true;
        if (!state.controlRequests.some((entry) => entry.step === "exit_confirm")) {
          await controlStep(state, "exit_confirm", {
            instructions: "Recovery: after save state Done, click EXIT_CONFIRM exactly once.",
            selectors: ["native EXIT_CONFIRM"], requiresCaptureSha256: true,
            expectedIndependentEvidence: ["recovery runtime exits"],
          });
        }
        await waitForNoRuntime(first, args);
      } catch (_recoveryError) {}
    } else if (!safeExitStarted && first && first.session) {
      try {
        await first.session.agentControl("shutdown");
        await waitForNoRuntime(first, args);
        if (preparation && lock && process.env.APPDATA) {
          CloneGuard.releaseDedicatedClone({ preparation, lock,
            appData: path.resolve(process.env.APPDATA) });
        }
      } catch (_shutdownError) {}
    }
    const diagnostic = {
      schema: "workbench-live-e2e.crafting.failure.v3",
      failedAt: new Date().toISOString(),
      code: error.code || "unhandled_error",
      phase: error.phase || "unknown",
      message: String(error.message || error),
      recovery: preparation
        ? "Prepared clone/recovery evidence remains protected; do not reseed or delete it."
        : "No clone preparation completed.",
    };
    try { atomicWriteJson(path.join(runDir, "failure.json"), diagnostic); }
    catch (_persistError) {}
    throw error;
  }
}

function main(argv, lifecycle) {
  const args = validateArgs(parseArgs(argv));
  if (args.help) { return { checkOnly: true, output: printHelp() }; }
  if (args.check) {
    return { checkOnly: true, output: {
      ok: true, schema: BUNDLE_SCHEMA,
      sharedAdmission: "FROZEN-v2_GO",
      consumerAdmission: "OFFLINE_VERIFIED",
      liveAdmission: "LIVE_BLOCKED",
      deployment: "NOT_DEPLOYED",
      fixedEntry: "tools/workbench-live-e2e/crafting/bootstrap.js",
      defaultSeedSlot: DEFAULT_SEED_SLOT,
      defaultTargetSlot: DEFAULT_TARGET_SLOT,
    } };
  }
  if (!lifecycle || typeof lifecycle.checkpoint !== "function") {
    fail("module_journal_admission_missing", "bootstrap",
      "Crafting live journey requires the fixed module-journal bootstrap");
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
  console.error("Crafting live journey requires the fixed bootstrap; shared admission is still reopened.");
  process.exit(2);
}
