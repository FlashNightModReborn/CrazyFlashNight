"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const ExternalToolchain = require("../lib/playwright-websocket-toolchain");
const LauncherObservation = require("../lib/launcher-observation");
const RuntimeGuard = require("../lib/runtime-guard");
const Admission = require("./admission");
const Applicability = require("./applicability");
const Build = require("./build-candidate");
const CandidateLifecycleContract = require("./candidate-lifecycle");
const Common = require("./common");
const Control = require("./control-channel");
const FinalizeCloneRelease = require("./finalize-clone-release");
const JourneyVerifier = require("./journey-verifier");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const Production = require("./production-closure");
const Protocol = require("./protocol");
const RunOperationLease = require("./run-operation-lease");
const DiscardBuilt = require("./discard-built-run");
const CaptureVerifier = require("./capture-verifier");
const AgentRuntimeJourney = require("./agent-runtime-journey");

const PRE_CONTROL_FAILURE_RECEIPT_SCHEMA =
  "workbench-live-e2e.material-shop.pre-control-failure-cleanup.v1";
const PRE_CONTROL_FAILURE_RECEIPT_NAME = "pre-control-failure-cleanup.json";

function parseArgs(argv) {
  const args = { preparation: null, build: null, timeoutMs: 900000, pollMs: 250 };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const take = () => { index += 1; return argv[index]; };
    if (token === "--preparation") args.preparation = take();
    else if (token === "--build") args.build = take();
    else if (token === "--timeout-ms") args.timeoutMs = Number(take());
    else if (token === "--poll-ms") args.pollMs = Number(take());
    else Common.fail("material_shop_run_argument_unknown", "run", token);
  }
  if (!args.preparation || !args.build || !Number.isInteger(args.timeoutMs)
      || args.timeoutMs < 60000 || args.timeoutMs > 3600000
      || !Number.isInteger(args.pollMs) || args.pollMs < 100 || args.pollMs > 5000) {
    Common.fail("material_shop_run_arguments_invalid", "run",
      "preparation, build receipt, and bounded polling controls are required");
  }
  return args;
}

function artifact(runDir, reference, phase) {
  const filePath = path.resolve(runDir, String(reference.relativePath || "").replace(/\//g, path.sep));
  if (!Evidence.pathInside(runDir, filePath)) {
    Common.fail("material_shop_run_artifact_escape", phase, "run artifact escaped its directory");
  }
  const file = Evidence.readExactRegularFile(filePath, { phase, maximumBytes: 128 * 1024 * 1024 });
  if (file.sha256 !== reference.sha256 || file.length !== reference.bytes) {
    Common.fail("material_shop_run_artifact_drift", phase, "run artifact changed after preparation");
  }
  try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_run_artifact_json_invalid", phase, error.message); }
}

function loadBuild(filePath, preparation, closure) {
  return Build.loadBuildReceipt(filePath, preparation, closure, "run");
}

function verifyLifecycleApplicability(preparation) {
  if (!process.env.APPDATA) {
    Common.fail("appdata_root_missing", "applicability", "APPDATA is required");
  }
  const appData = Evidence.assertExactDirectory(path.resolve(process.env.APPDATA),
    "applicability");
  const value = artifact(preparation.runDir, preparation.artifacts.applicability,
    "applicability");
  const applicability = Applicability.verifyCurrentDataApplicability(
    preparation.resourcesRoot, value, {
    appData,
    fixtureAuthorityRoot: preparation.root,
  });
  const fixtureAuthorityBinding = Applicability.createFixtureAuthorityBinding(
    preparation.root, applicability, applicability.capturedAt);
  return { applicability, fixtureAuthorityBinding,
    verificationSha256: Evidence.sha256Text(Evidence.canonicalJson({
      applicabilitySha256: applicability.applicabilitySha256,
      fixtureAuthorityBindingSha256: fixtureAuthorityBinding.bindingSha256,
    })) };
}

function writeJsonNew(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
}

async function waitJson(filePath, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    if (fs.existsSync(filePath)) return Prepare.readJson(filePath, "candidate_admission");
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  Common.fail("material_shop_candidate_admission_timeout", "candidate_admission",
    "candidate-bound Computer Use admission timed out", { filePath });
}

function publicRunningIdentity(runtime) {
  const observed = Object.assign({}, runtime.identity);
  if (!observed.installRoot && typeof observed.processPath === "string") {
    observed.installRoot = path.dirname(path.dirname(path.resolve(observed.processPath)));
  }
  return Object.assign({}, RuntimeGuard.publicCandidateIdentity(observed), {
    pid: Number(observed.pid),
  });
}

async function admitCandidate(runDir, plan, label, runtime, timeoutMs, pollMs) {
  const request = Admission.createCandidateRequest({ runId: plan.runId,
    planSha256: plan.planSha256, candidateIdentity: publicRunningIdentity(runtime) });
  const requestPath = path.join(runDir, "control", "candidate-admission-" + label + "-request.json");
  const bundlePath = path.join(runDir, "control", "candidate-admission-" + label + ".json");
  writeJsonNew(requestPath, request);
  process.stdout.write(JSON.stringify({ event: "candidate_ui_admission_required", label,
    requestPath, outputPath: bundlePath,
    command: ["node", "tools/workbench-live-e2e/material-shop/admission.js", "--candidate",
      "--request", requestPath, "--provider-receipt", "<computer-use-receipt.json>",
      "--out", bundlePath] }) + "\n");
  const bundle = await waitJson(bundlePath, timeoutMs, pollMs);
  Admission.validateCandidateAdmissionBundle(bundle);
  if (Evidence.canonicalJson(bundle.request) !== Evidence.canonicalJson(request)) {
    Common.fail("material_shop_candidate_admission_request_drift", "candidate_admission",
      "candidate admission bundle changed its issued request");
  }
  if (!Evidence.pathInside(runDir,
    path.resolve(bundle.operatorAttestation.rawOperationArtifact.sourcePath))) {
    Common.fail("material_shop_candidate_operation_artifact_foreign", "candidate_admission",
      "candidate Computer Use raw operation artifact must remain in the exact run directory");
  }
  return bundle;
}

function runnerAck(channel, request, result) {
  return Control.createAck({ root: Common.CANONICAL_ROOT, runDir: channel.runDir,
    plan: channel.plan, request, transport: Protocol.RUNNER_TRANSPORT, result: "completed",
    operationId: "runner-" + request.step + "-" + crypto.randomBytes(5).toString("hex"),
    completedAt: new Date().toISOString(), capturePath: null, captureSha256: null });
}

function latestPanelClose(transcript, panel) {
  const matches = (transcript.events || []).map((event) => ({
    event,
    message: JourneyVerifier.message(event),
  })).filter((entry) => entry.event.kind === "bridge_send" && entry.message
    && entry.message.type === "panel" && entry.message.panel === panel
    && entry.message.cmd === "close");
  if (matches.length !== 1 || !Common.ID_RE.test(String(
    matches[0].message.panelInstanceId || ""))) {
    Common.fail("material_shop_ordinary_close_capture_invalid", "run",
      "owner close requires one exact panel envelope before Host settlement", { panel });
  }
  return matches[0].message;
}

function latestNpcshopClose(transcript) {
  return latestPanelClose(transcript, "npcshop");
}

function loadMaterializedRuntimeModules(preparation, closure, candidateRoot) {
  if (candidateRoot) {
    Materialize.verifyPostBuildProtectedScope(preparation.resourcesRoot, closure.scope,
      Build.protectedScopeOptions(preparation, candidateRoot));
  } else {
    Materialize.verifyScopeFiles(preparation.resourcesRoot, closure.scope);
  }
  const producerBinding = Production.captureMaterializedSharedProducers(
    preparation.resourcesRoot, closure);
  const passivePath = path.join(preparation.resourcesRoot, "tools", "workbench-live-e2e",
    "npc", "passive-recorder.js");
  const lifecyclePath = path.join(preparation.resourcesRoot, "tools", "workbench-live-e2e",
    "material-shop", "candidate-lifecycle.js");
  const NpcPassive = require(passivePath);
  const CandidateLifecycle = require(lifecyclePath);
  if (!NpcPassive || typeof NpcPassive.TranscriptWriter !== "function"
      || typeof NpcPassive.attachPassiveRecorder !== "function"
      || !CandidateLifecycle || typeof CandidateLifecycle.prepare !== "function") {
    Common.fail("material_shop_materialized_runtime_producer_invalid", "run",
      "candidate execution did not load the passive/lifecycle producers from resources");
  }
  return { CandidateLifecycle, NpcPassive, producerBinding };
}

function loadMaterializedAgentRuntimeModules(preparation, closure, candidateRoot) {
  Materialize.verifyPostBuildProtectedScope(preparation.resourcesRoot, closure.scope,
    Build.protectedScopeOptions(preparation, candidateRoot));
  const producerBinding = Production.captureMaterializedSharedProducers(
    preparation.resourcesRoot, closure);
  const lifecyclePath = path.join(preparation.resourcesRoot, "tools",
    "workbench-live-e2e", "material-shop", "candidate-lifecycle.js");
  const controllerPath = path.join(preparation.resourcesRoot, "tools",
    "workbench-live-e2e", "material-shop", "trusted-runtime-controller.js");
  const CandidateLifecycle = require(lifecyclePath);
  const TrustedRuntimeController = require(controllerPath);
  if (!CandidateLifecycle || typeof CandidateLifecycle.prepare !== "function"
      || !TrustedRuntimeController || typeof TrustedRuntimeController.start !== "function") {
    Common.fail("material_shop_materialized_runtime_producer_invalid", "run",
      "Agent Runtime execution did not load the lifecycle/controller producers from resources");
  }
  return { CandidateLifecycle, TrustedRuntimeController, producerBinding };
}

function assertCompletedControlAck(ack, stepId) {
  if (!ack || ack.result !== "completed") {
    Common.fail("material_shop_control_not_completed", "run",
      "non-completed visible control result halts the journey immediately", {
        step: stepId, result: ack && ack.result || null,
      });
  }
  return ack;
}

function authorityRiskBeforeIssue(stepId, current) {
  return current === true || stepId === "unlocked_commit";
}

function requiresRecoveryBlocker(commitMayHaveReachedAuthority, cleanupResult, cleanupError) {
  return commitMayHaveReachedAuthority === true || !!cleanupError
    || !!(cleanupResult && cleanupResult.preservedForManualRecovery === true);
}

const RELEASE_PHASE_TRANSITIONS = Object.freeze({
  not_started: "intent_written",
  intent_written: "release_in_progress",
  release_in_progress: "released",
  released: "receipt_created",
  receipt_created: "receipt_written",
});

function advanceReleasePhase(current, next) {
  if (RELEASE_PHASE_TRANSITIONS[current] !== next) {
    Common.fail("material_shop_release_phase_invalid", "clone_release",
      "clone release phase transition is not exact", { current, next });
  }
  return next;
}

function isPostReleaseFinalizationPhase(value) {
  return value === "released" || value === "receipt_created";
}

function validateFreshReleasedCloneInspection(value, preparation) {
  Common.exactKeys(value, ["schema", "apiVersion", "observedAt", "slot", "lockPath",
    "lockPresent", "recordSha256", "ownerPid", "ownerProcessStartUtcTicks",
    "observedProcessStartUtcTicks", "ownerState", "recoveryPresent", "recoveryStatus",
    "recoveryRecordSha256", "evidenceSha256"],
  "material_shop_post_release_inspection_invalid", "clone_release");
  const unsigned = Object.assign({}, value);
  delete unsigned.evidenceSha256;
  if (value.schema !== "workbench-live-e2e.clone-lock-inspection.v1"
      || value.apiVersion !== CloneGuard.API_VERSION
      || value.slot !== preparation.slots.targetSlot
      || !Number.isFinite(Date.parse(value.observedAt))
      || value.lockPresent !== false || value.recordSha256 !== null
      || value.ownerPid !== null || value.ownerProcessStartUtcTicks !== null
      || value.observedProcessStartUtcTicks !== null || value.ownerState !== "absent"
      || value.recoveryPresent !== false || value.recoveryStatus !== null
      || value.recoveryRecordSha256 !== null
      || value.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_post_release_inspection_invalid", "clone_release",
      "post-release receipt recovery requires a fresh absent lock/recovery inspection");
  }
  return value;
}

function persistPostReleaseFinalizationRequired(options) {
  const settings = options || {};
  if (!isPostReleaseFinalizationPhase(settings.releasePhase)) return null;
  if (!settings.releasedClone || settings.releasedClone.cloneLockReleased !== true
      || settings.releasedClone.recoveryCleared !== true
      || !settings.releaseIntentPath) {
    Common.fail("material_shop_post_release_state_invalid", "clone_release",
      "post-release finalization requires the returned release and durable intent");
  }
  const inspect = settings.inspectCloneLock || CloneGuard.inspectCloneLock;
  const inspection = validateFreshReleasedCloneInspection(inspect({
    root: settings.preparation.resourcesRoot,
    slot: settings.preparation.slots.targetSlot,
  }), settings.preparation);
  const cleanupResult = {
    releasedBeforeCommit: false,
    cloneAlreadyReleased: true,
    runtimeCleanupVerified: true,
    shutdownSucceeded: true,
    preservedForManualRecovery: false,
    releasePhase: settings.releasePhase,
    released: settings.releasedClone,
    cloneInspection: inspection,
  };
  const writer = settings.writeBlocker || writeRecoveryBlocker;
  const persisted = writer({
    runDir: settings.runDir,
    plan: settings.plan,
    preparation: settings.preparation,
    preparationPath: path.resolve(settings.preparationPath),
    buildPath: path.resolve(settings.buildPath),
    releaseIntentPath: path.resolve(settings.releaseIntentPath),
    commitMayHaveReachedAuthority: true,
    error: settings.error,
    cleanupResult,
    cleanupError: null,
  });
  if (!persisted || path.basename(String(persisted.blockerPath || ""))
      !== FinalizeCloneRelease.FINALIZATION_REQUIRED_NAME
      || !persisted.blocker
      || persisted.blocker.schema !== FinalizeCloneRelease.FINALIZATION_BLOCKER_SCHEMA) {
    Common.fail("material_shop_release_finalization_marker_invalid", "clone_release",
      "post-release receipt failure did not create the exact required marker");
  }
  return { persisted, cleanupResult };
}

function agentRuntimePoint(capture, designX, designY) {
  if (!capture || !Number.isSafeInteger(capture.width)
      || !Number.isSafeInteger(capture.height)) {
    Common.fail("material_shop_agent_runtime_capture_geometry_invalid", "run",
      "Agent Runtime click mapping requires one exact WGC frame");
  }
  const scale = Math.min(capture.width / 1024, capture.height / 576);
  const offsetX = (capture.width - 1024 * scale) / 2;
  const offsetY = (capture.height - 576 * scale) / 2;
  const x = Math.round(offsetX + designX * scale);
  const y = Math.round(offsetY + designY * scale);
  if (!(scale > 0) || x < 0 || y < 0 || x >= capture.width || y >= capture.height) {
    Common.fail("material_shop_agent_runtime_click_geometry_invalid", "run",
      "design-space control point is outside the fresh WGC frame", {
        designX, designY, width: capture.width, height: capture.height,
      });
  }
  return { x, y };
}

function agentRuntimeCoordinateProvider(stepId, capture, role) {
  const points = {
    ordinary_search_input: [98, 130],
    ordinary_filtered_card: [43, 182],
    ordinary_shop_cta: [582, 320],
    unlocked_search_input: [98, 130],
    unlocked_filtered_card: [43, 182],
    chef_shop_cta: [582, 320],
    restart_search_input: [98, 130],
    restart_filtered_card: [43, 182],
    npcshop_checkout: [943, 25],
    settlement_commit: [935, 540],
    return_to_materials: [852, 25],
    npcshop_close: [998, 25],
    crafting_close: [998, 25],
  };
  const pair = points[role];
  if (!pair) {
    Common.fail("material_shop_agent_runtime_control_geometry_unknown", "run",
      "Agent Runtime journey requested an unfrozen visible control", { stepId, role });
  }
  return agentRuntimePoint(capture, pair[0], pair[1]);
}

async function executeAgentRuntimeOwned(args, preparation, operationHandle,
  preflightApplicability, context) {
  const runDir = preparation.runDir;
  const { closure, authority, applicability, plan, build } = context;
  const materialized = loadMaterializedAgentRuntimeModules(preparation, closure,
    build.candidateRoot);
  const lifecycleAuthority = verifyLifecycleApplicability(preparation);
  if (preflightApplicability
      && preflightApplicability.verificationSha256 !== lifecycleAuthority.verificationSha256
      || lifecycleAuthority.verificationSha256 !== authority.verificationSha256) {
    Common.fail("material_shop_applicability_drift", "applicability",
      "fixture/data authority changed before Agent Runtime lifecycle preparation");
  }
  const lifecycle = await materialized.CandidateLifecycle.prepare({
    canonicalRoot: preparation.resourcesRoot,
    fixtureAuthorityBinding: lifecycleAuthority.fixtureAuthorityBinding,
    resourcesRoot: preparation.resourcesRoot,
    candidateRoot: build.candidateRoot,
    runId: preparation.runId,
    seedSlot: preparation.slots.seedSlot,
    targetSlot: preparation.slots.targetSlot,
    recoverySlot: preparation.slots.recoverySlot,
    applicability: lifecycleAuthority.applicability,
    evidenceRoot: preparation.root,
    evidenceRunDir: runDir,
  });
  let state = null;
  let releaseIntentPath = null;
  let releasePhase = "not_started";
  let releasedClone = null;
  let archiveSaveState = null;
  let restartSaveState = null;
  try {
    state = await AgentRuntimeJourney.execute({
      plan, preparation, runDir,
      controllerFactory: ({ sessionLabel }) => materialized.TrustedRuntimeController.start(
        Object.assign({}, preparation, {
          candidateRoot: build.candidateRoot,
          candidateIdentity: build.candidateIdentity,
          buildSha256: build.buildSha256,
        }), { sessionLabel }),
      captureWriter: CaptureVerifier.createAgentRuntimeCapture,
      coordinateProvider: (step, capture, role) =>
        agentRuntimeCoordinateProvider(step.id, capture, role),
      onFirstFinished: async () => {
        archiveSaveState = await lifecycle.captureTargetSaveState("archive");
      },
      onRestartFinished: async () => {
        restartSaveState = await lifecycle.captureTargetSaveState("restart");
      },
    });
    state.archiveSaveState = archiveSaveState;
    state.restartSaveState = restartSaveState;
    state.captureByStep = Object.fromEntries(state.captures.map((entry) =>
      [entry.stepId, entry]));
    const seedInvariant = await lifecycle.journey.captureSeedInvariant();
    const recoveryInvariant = await lifecycle.captureRecoveryInvariant();
    const targetAfterRestart = await lifecycle.journey.captureCloneAfterRestart();
    const saveStates = {
      baseline: lifecycle.evidence.baselineSaveState,
      archive: state.archiveSaveState,
      restart: state.restartSaveState,
    };
    const unitPrice = saveStates.baseline.money - saveStates.archive.money;
    if (!Number.isSafeInteger(unitPrice) || unitPrice < 1) {
      Common.fail("material_shop_agent_runtime_settlement_projection_invalid", "run",
        "sealed save bytes do not prove one positive-price purchase", { unitPrice });
    }
    const target = JSON.parse(JSON.stringify(applicability.selectedUnlockedTarget));
    const raw = {
      schema: JourneyVerifier.AGENT_RUNTIME_RAW_SCHEMA,
      capturedAt: new Date().toISOString(),
      runId: plan.runId,
      planSha256: plan.planSha256,
      buildSha256: build.buildSha256,
      operationLease: operationHandle.lease,
      materializedProducerBinding: materialized.producerBinding,
      lifecycle: lifecycle.evidence,
      sessions: state.sessions,
      controls: state.controls,
      captures: state.captures,
      authority: {
        target,
        settlementProjection: {
          quantity: 1, saleCount: 0,
          baselineBalance: saveStates.baseline.money,
          unitPrice,
          buyTotal: unitPrice,
          projectedBalance: saveStates.archive.money,
          beforeOwned: saveStates.baseline.owned,
          afterOwned: saveStates.archive.owned,
          intentCaptureSha256: state.captureByStep.unlocked_intent_qty1.captureSha256,
          settlementCaptureSha256: state.captureByStep.unlocked_settlement.captureSha256,
        },
        commitDispatch: {
          stepId: "unlocked_commit",
          authorizationDecisionId: plan.authorization.decisionId,
          authorizationDecisionSha256: plan.authorization.decisionSha256,
          actionReceiptSha256: state.commitDispatch.actionReceiptSha256,
        },
        saveProjection: {
          baselineMoney: saveStates.baseline.money,
          archiveMoney: saveStates.archive.money,
          restartMoney: saveStates.restart.money,
          beforeOwned: saveStates.baseline.owned,
          archiveOwned: saveStates.archive.owned,
          restartOwned: saveStates.restart.owned,
        },
        restartReadback: {
          itemName: target.itemName, owned: saveStates.restart.owned,
          captureSha256: state.captureByStep.restart_readback.captureSha256,
        },
      },
      persistence: {
        seedInvariant, recoveryInvariant, targetAfterRestart, saveStates,
        firstShutdown: state.firstShutdown,
        restartShutdown: state.restartShutdown,
      },
      boundaries: {
        realGuiExecuted: true, candidateBuilt: true, candidateExecuted: true,
        e2eVerified: false, promoted: false, standardEntryVerified: false,
      },
    };
    raw.rawSha256 = Evidence.sha256Text(Evidence.canonicalJson(raw));
    writeJsonNew(path.join(runDir, "raw-candidate-journey.json"), raw);
    const verified = JourneyVerifier.verifyRawCandidateJourney(raw, plan,
      applicability, runDir, build);
    writeJsonNew(path.join(runDir, "journey-evidence.json"), verified.evidence);
    const releaseContext = {
      preparation, build, raw, evidence: verified.evidence, plan, closure,
    };
    const releaseIntent = FinalizeCloneRelease.createIntent(releaseContext);
    releaseIntentPath = path.join(runDir, "clone-release-intent.json");
    writeJsonNew(releaseIntentPath, releaseIntent);
    releasePhase = advanceReleasePhase(releasePhase, "intent_written");
    releasePhase = advanceReleasePhase(releasePhase, "release_in_progress");
    releasedClone = await lifecycle.journey.release();
    releasePhase = advanceReleasePhase(releasePhase, "released");
    const release = FinalizeCloneRelease.createReleaseReceipt(
      releaseContext, releaseIntent, releasedClone);
    releasePhase = advanceReleasePhase(releasePhase, "receipt_created");
    FinalizeCloneRelease.writeReleaseReceipt(path.join(runDir, "release.json"),
      release, runDir);
    releasePhase = advanceReleasePhase(releasePhase, "receipt_written");
    const operationTerminal = RunOperationLease.release(operationHandle);
    return { raw, evidence: verified.evidence, release, operationTerminal };
  } catch (error) {
    if (isPostReleaseFinalizationPhase(releasePhase)) {
      const finalization = persistPostReleaseFinalizationRequired({
        releasePhase, releasedClone, releaseIntentPath, error,
        runDir, plan, preparation,
        preparationPath: args.preparation, buildPath: args.build,
      });
      Common.fail("material_shop_release_finalization_required", "run",
        "clone release completed; only release receipt finalization remains", {
          blockerPath: finalization.persisted.blockerPath,
          releasePhase,
          originalCode: error && error.code || null,
        });
    }
    if (releasePhase === "receipt_written") throw error;
    const failureState = error && error.agentRuntimeState || state || {};
    const commitMayHaveReachedAuthority =
      failureState.commitMayHaveReachedAuthority === true;
    let cleanupResult = null;
    let cleanupError = null;
    if (failureState.controller
        && typeof failureState.controller.finish === "function") {
      try { await failureState.controller.finish(); }
      catch (failure) { cleanupError = failure; }
    }
    if (!commitMayHaveReachedAuthority && !cleanupError) {
      try {
        const released = await lifecycle.journey.release();
        cleanupResult = {
          releasedBeforeCommit: true, cloneAlreadyReleased: true,
          runtimeCleanupVerified: true, shutdownSucceeded: true,
          preservedForManualRecovery: false, released,
        };
      } catch (failure) { cleanupError = failure; }
    } else if (commitMayHaveReachedAuthority) {
      cleanupResult = {
        releasedBeforeCommit: false, cloneAlreadyReleased: false,
        runtimeCleanupVerified: cleanupError === null,
        shutdownSucceeded: cleanupError === null,
        preservedForManualRecovery: true,
      };
    }
    if (requiresRecoveryBlocker(commitMayHaveReachedAuthority,
      cleanupResult, cleanupError)) {
      const persisted = writeRecoveryBlocker({
        runDir, plan, preparation,
        preparationPath: path.resolve(args.preparation),
        buildPath: path.resolve(args.build),
        releaseIntentPath,
        commitMayHaveReachedAuthority,
        error, cleanupResult, cleanupError,
      });
      Common.fail("material_shop_manual_recovery_required", "run",
        "Agent Runtime failure preserved the isolated target for exact manual recovery", {
          blockerPath: persisted.blockerPath,
          originalCode: error && error.code || null,
          cleanupCode: cleanupError && cleanupError.code || null,
        });
    }
    throw error;
  }
}

function writeRecoveryBlocker(options) {
  const settings = options || {};
  const resumableRelease = !!(settings.cleanupResult
    && settings.cleanupResult.cloneAlreadyReleased === true && settings.releaseIntentPath);
  const common = {
    recordedAt: new Date().toISOString(), runId: settings.plan.runId,
    targetSlot: settings.preparation.slots.targetSlot,
    resourcesRoot: settings.preparation.resourcesRoot,
    commitMayHaveReachedAuthority: settings.commitMayHaveReachedAuthority === true,
    originalError: Common.publicError(settings.error),
    cleanupResult: settings.cleanupResult || null,
    cleanupError: settings.cleanupError ? Common.publicError(settings.cleanupError) : null };
  const blocker = resumableRelease
    ? Object.assign({ schema: FinalizeCloneRelease.FINALIZATION_BLOCKER_SCHEMA }, common, {
      preparationPath: path.resolve(settings.preparationPath),
      buildPath: path.resolve(settings.buildPath),
      rawPath: path.join(settings.runDir, "raw-candidate-journey.json"),
      evidencePath: path.join(settings.runDir, "journey-evidence.json"),
      releaseIntentPath: path.resolve(settings.releaseIntentPath),
      releaseOutputPath: path.join(settings.runDir, "release.json"),
      stopLine: "Clone is already released. Run only recoveryCommand to finalize the release receipt; do not retry the live journey or release the worktree.",
    })
    : Object.assign({ schema: "workbench-live-e2e.material-shop.recovery-blocker.v1" },
      common, { recoveryCommand: ["node", path.join(settings.preparation.resourcesRoot, "tools",
        "workbench-live-e2e", "lib", "offline-clone-recovery.js"), "inspect",
        "--slot", settings.preparation.slots.targetSlot],
      stopLine: "Do not retry, reseed, release the worktree, or edit the target before exact offline recovery inspection.",
    });
  if (resumableRelease) {
    blocker.recoveryCommand = FinalizeCloneRelease.expectedRecoveryCommand(blocker);
  }
  blocker.blockerSha256 = Evidence.sha256Text(Evidence.canonicalJson(blocker));
  const blockerPath = resumableRelease
    ? path.join(settings.runDir, FinalizeCloneRelease.FINALIZATION_REQUIRED_NAME)
    : path.join(settings.runDir,
      "recovery-blocker-" + Date.now() + "-" + crypto.randomBytes(4).toString("hex") + ".json");
  writeJsonNew(blockerPath, blocker);
  return { blocker, blockerPath };
}

function captureExactRunArtifact(runDirValue, relativePathValue) {
  const runDir = path.resolve(runDirValue);
  const relativePath = Common.normalizeRelative(relativePathValue);
  const filePath = Common.resolveWithin(runDir, relativePath, "pre_control_cleanup").absolute;
  const before = fs.lstatSync(filePath);
  const real = fs.realpathSync.native(filePath);
  const bytes = fs.readFileSync(filePath);
  const after = fs.lstatSync(filePath);
  if (!before.isFile() || before.isSymbolicLink() || real.toLowerCase() !== filePath.toLowerCase()
      || before.size !== after.size || before.mtimeMs !== after.mtimeMs
      || before.ctimeMs !== after.ctimeMs || bytes.length !== before.size
      || bytes.length > 128 * 1024 * 1024) {
    Common.fail("material_shop_pre_control_artifact_invalid", "pre_control_cleanup",
      "pre-control evidence must remain one bounded exact regular file", { relativePath });
  }
  return { relativePath, bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes) };
}

function replayExactRunArtifact(runDirValue, descriptor) {
  if (!descriptor || !Number.isSafeInteger(descriptor.bytes) || descriptor.bytes < 0
      || !Common.SHA256_RE.test(String(descriptor.sha256 || ""))) {
    Common.fail("material_shop_pre_control_artifact_invalid", "pre_control_cleanup",
      "pre-control artifact descriptor is malformed");
  }
  const actual = captureExactRunArtifact(runDirValue, descriptor.relativePath);
  if (Evidence.canonicalJson(actual) !== Evidence.canonicalJson(descriptor)) {
    Common.fail("material_shop_pre_control_artifact_drift", "pre_control_cleanup",
      "pre-control evidence bytes changed after capture", {
        relativePath: descriptor.relativePath,
      });
  }
  return actual;
}

function capturePreControlSurface(runDirValue) {
  const runDir = path.resolve(runDirValue);
  const controlRoot = path.join(runDir, "control");
  const directories = ["requests", "acks", "captures"].map((name) => {
    const directory = path.join(controlRoot, name);
    const stat = fs.lstatSync(directory);
    const real = fs.realpathSync.native(directory);
    const entries = fs.readdirSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()
        || real.toLowerCase() !== path.resolve(directory).toLowerCase()
        || entries.length !== 0) {
      Common.fail("material_shop_pre_control_surface_not_empty", "pre_control_cleanup",
        "pre-control channel directories must be exact and empty", { name, entries });
    }
    return { name, entryCount: 0 };
  });
  const currentRequest = path.join(controlRoot, "current-request.json");
  if (fs.existsSync(currentRequest)) {
    Common.fail("material_shop_pre_control_surface_not_empty", "pre_control_cleanup",
      "pre-control failure cannot expose a current control request");
  }
  const allowedFiles = new Set(["candidate-admission-first-request.json",
    "candidate-admission-first.json"]);
  const rootEntries = fs.readdirSync(controlRoot, { withFileTypes: true });
  const files = rootEntries.filter((entry) => entry.isFile()).map((entry) => entry.name).sort();
  if (rootEntries.some((entry) => entry.isSymbolicLink()
      || entry.isDirectory() && !["requests", "acks", "captures"].includes(entry.name))
      || files.some((name) => !allowedFiles.has(name))) {
    Common.fail("material_shop_pre_control_surface_not_empty", "pre_control_cleanup",
      "pre-control surface contains a control, foreign, or reparse entry", { files });
  }
  return { directories, currentRequestPresent: false,
    files: files.map((name) => captureExactRunArtifact(runDir,
      path.posix.join("control", name))) };
}

function verifyPreControlBaselineInvariant(runDir, value) {
  const baseline = CandidateLifecycleContract.verifySaveStateArtifact(runDir,
    value.baselineSaveState, "baseline", value.targetSlot, value.itemName);
  const release = value.cleanup && value.cleanup.cloneRelease;
  const releaseUnsigned = release && Object.assign({}, release);
  if (releaseUnsigned) delete releaseUnsigned.releaseSha256;
  if (!release || release.schema !== CloneGuard.RELEASE_SCHEMA
      || release.releaseSha256 !== Evidence.sha256Text(Evidence.canonicalJson(releaseUnsigned))
      || !release.targetEnd || release.targetEnd.slot !== value.targetSlot
      || release.backupsVerified !== true
      || !release.lockRelease || release.lockRelease.lockFileAbsent !== true
      || !release.recoveryClear || release.recoveryClear.recoveryFileAbsent !== true) {
    Common.fail("material_shop_pre_control_baseline_invalid", "pre_control_cleanup",
      "clone release is not a complete exact pre-control terminal");
  }
  CloneGuard.verifyArtifactSet(release.targetEnd);
  const jsonArtifact = release.targetEnd.artifacts.find((entry) => entry.kind === "json");
  if (!jsonArtifact || release.targetEnd.setSha256 !== value.baselineSaveState.artifactSetSha256
      || jsonArtifact.sha256 !== value.baselineSaveState.sha256
      || jsonArtifact.bytes !== value.baselineSaveState.bytes) {
    Common.fail("material_shop_pre_control_baseline_changed", "pre_control_cleanup",
      "target JSON/SOL set changed before the pre-control failure cleanup");
  }
  return { money: baseline.projection.money, owned: baseline.projection.owned,
    artifactSetSha256: release.targetEnd.setSha256 };
}

function validateCandidateRequestSurface(request, value) {
  Common.exactKeys(request, ["schema", "runId", "planSha256", "issuedAt",
    "candidateIdentity", "instructions", "requestSha256"],
  "material_shop_pre_control_admission_invalid", "pre_control_cleanup");
  const unsigned = Object.assign({}, request);
  delete unsigned.requestSha256;
  if (request.schema !== Admission.CANDIDATE_REQUEST_SCHEMA
      || request.runId !== value.runId || request.planSha256 !== value.planSha256
      || !Number.isFinite(Date.parse(request.issuedAt))
      || request.requestSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))
      || !value.runtime
      || Evidence.canonicalJson(request.candidateIdentity)
        !== Evidence.canonicalJson(value.runtime)) {
    Common.fail("material_shop_pre_control_admission_invalid", "pre_control_cleanup",
      "pre-control candidate request is malformed or detached from its runtime");
  }
  return request;
}

function validatePreControlFailureCleanupReceipt(value, context) {
  Common.exactKeys(value, ["schema", "recordedAt", "runId", "preparationSha256",
    "buildSha256", "planSha256", "operationLease", "operationTerminal", "targetSlot",
    "itemName", "originalError", "cleanup", "baselineSaveState", "transcript",
    "controlSurface", "runtime", "admissions", "sideEffects", "receiptSha256"],
  "material_shop_pre_control_cleanup_receipt_invalid", "pre_control_cleanup");
  const unsigned = Object.assign({}, value);
  delete unsigned.receiptSha256;
  const cleanup = value && value.cleanup;
  const shutdown = cleanup && cleanup.shutdown;
  const sideEffects = value && value.sideEffects;
  const transcript = value && value.transcript;
  const control = value && value.controlSurface;
  const shutdownUnsigned = shutdown && Object.assign({}, shutdown);
  if (shutdownUnsigned) delete shutdownUnsigned.evidenceSha256;
  if (value.schema !== PRE_CONTROL_FAILURE_RECEIPT_SCHEMA
      || !Number.isFinite(Date.parse(value.recordedAt))
      || !Common.ID_RE.test(String(value.runId || ""))
      || !Common.SHA256_RE.test(String(value.preparationSha256 || ""))
      || !Common.SHA256_RE.test(String(value.buildSha256 || ""))
      || !Common.SHA256_RE.test(String(value.planSha256 || ""))
      || !value.operationLease || value.operationLease.mode !== "live_execution"
      || value.operationLease.runId !== value.runId
      || value.operationLease.preparationSha256 !== value.preparationSha256
      || value.operationLease.buildSha256 !== value.buildSha256
      || !value.operationTerminal
      || !Common.ID_RE.test(String(value.targetSlot || ""))
      || typeof value.itemName !== "string" || value.itemName.length < 1
      || !value.originalError || typeof value.originalError.code !== "string"
      || cleanup.runtimeCleanupVerified !== true || cleanup.shutdownSucceeded !== true
      || cleanup.releasedBeforeCommit !== true || cleanup.cloneAlreadyReleased !== true
      || cleanup.preservedForManualRecovery !== false
      || !shutdown || shutdown.schema !== "workbench-live-e2e.npc.failure-cleanup-shutdown.v1"
      || shutdown.responseSucceeded !== true
      || shutdown.responseSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(shutdown.response))
      || shutdown.evidenceSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(shutdownUnsigned))
      || !cleanup.residue || !value.baselineSaveState
      || !transcript || transcript.relativePath !== "passive-transcript.jsonl"
      || !Number.isSafeInteger(transcript.bytes) || transcript.bytes < 0
      || !Common.SHA256_RE.test(String(transcript.sha256 || ""))
      || !control || control.currentRequestPresent !== false
      || !Array.isArray(control.directories) || control.directories.length !== 3
      || control.directories.some((entry, index) => entry.entryCount !== 0
        || entry.name !== ["requests", "acks", "captures"][index])
      || !Array.isArray(control.files)
      || control.files.some((entry, index) => !entry
        || !["control/candidate-admission-first-request.json",
          "control/candidate-admission-first.json"].includes(entry.relativePath)
        || index > 0 && control.files[index - 1].relativePath.localeCompare(entry.relativePath) >= 0)
      || !Array.isArray(value.admissions) || value.admissions.length > 1
      || !sideEffects || Evidence.canonicalJson(sideEffects) !== Evidence.canonicalJson({
        admissionCount: value.admissions.length, controlCount: 0,
        firstRuntimeAssigned: value.runtime !== null,
        restartRuntimeAssigned: false, observerAttached: false,
        rawPresent: false, evidencePresent: false, releasePresent: false,
        recoveryBlockerCount: 0,
      })
      || value.receiptSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_pre_control_cleanup_receipt_invalid",
      "pre_control_cleanup", "pre-control cleanup receipt is malformed or detached");
  }
  RunOperationLease.validateLease(value.operationLease,
    context && context.runDir || value.operationLease.runDir);
  RunOperationLease.validateTerminal(value.operationTerminal, value.operationLease);
  LauncherObservation.verifySessionEvidenceEnvelope(shutdown.sessionEvidence);
  LauncherObservation.assertResponseSucceeded(shutdown.response,
    "pre_control_cleanup", "authenticated cleanup shutdown");
  LauncherObservation.assertResidueClean(cleanup.residue);
  if (shutdown.pid !== shutdown.runtimeIdentity.pid
      || shutdown.pid !== shutdown.sessionEvidence.pid
      || shutdown.cdpBinding.runtimePid !== shutdown.pid) {
    Common.fail("material_shop_pre_control_cleanup_receipt_invalid",
      "pre_control_cleanup", "shutdown session, runtime, and CDP identities diverged");
  }
  if (value.runtime) {
    const expectedRuntime = publicRunningIdentity({ identity: shutdown.runtimeIdentity });
    if (Evidence.canonicalJson(value.runtime) !== Evidence.canonicalJson(expectedRuntime)) {
      Common.fail("material_shop_pre_control_cleanup_receipt_invalid", "pre_control_cleanup",
        "assigned runtime differs from authenticated shutdown identity");
    }
  }
  value.admissions.forEach((entry) => Admission.validateCandidateAdmissionBundle(entry));
  if (context && context.runDir) {
    const runDir = path.resolve(context.runDir);
    replayExactRunArtifact(runDir, transcript);
    control.files.forEach((entry) => replayExactRunArtifact(runDir, entry));
    const terminal = RunOperationLease.terminalFromArchive(runDir, value.operationLease);
    if (Evidence.canonicalJson(terminal) !== Evidence.canonicalJson(value.operationTerminal)) {
      Common.fail("material_shop_pre_control_cleanup_receipt_invalid", "pre_control_cleanup",
        "operation terminal archive differs from the cleanup receipt");
    }
    const requestEntry = control.files.find((entry) =>
      entry.relativePath.endsWith("-request.json"));
    const bundleEntry = control.files.find((entry) =>
      entry.relativePath === "control/candidate-admission-first.json");
    if (value.runtime === null && (requestEntry || bundleEntry || value.admissions.length !== 0)
        || value.runtime !== null && (!requestEntry || !bundleEntry)
        || value.admissions.length === 1 && !bundleEntry) {
      Common.fail("material_shop_pre_control_admission_invalid", "pre_control_cleanup",
        "candidate admission surface is incomplete, still writable, or detached from runtime state");
    }
    if (requestEntry) {
      const requestPath = Common.resolveWithin(runDir, requestEntry.relativePath,
        "pre_control_cleanup").absolute;
      validateCandidateRequestSurface(JSON.parse(fs.readFileSync(requestPath, "utf8")), value);
    }
    if (value.admissions.length === 1) {
      const bundlePath = Common.resolveWithin(runDir, bundleEntry.relativePath,
        "pre_control_cleanup").absolute;
      const bundle = JSON.parse(fs.readFileSync(bundlePath, "utf8"));
      if (Evidence.canonicalJson(bundle) !== Evidence.canonicalJson(value.admissions[0])) {
        Common.fail("material_shop_pre_control_admission_invalid", "pre_control_cleanup",
          "admission bundle bytes differ from the sealed admitted bundle");
      }
    }
    verifyPreControlBaselineInvariant(runDir, value);
  }
  return value;
}

function writePreControlFailureCleanupReceipt(options) {
  const settings = options || {};
  const runDir = path.resolve(settings.runDir);
  const forbidden = ["raw-candidate-journey.json", "journey-evidence.json",
    "release.json", "clone-release-intent.json"];
  const recoveryBlockers = fs.readdirSync(runDir).filter((name) =>
    /^recovery-blocker-.*\.json$/.test(name));
  if (forbidden.some((name) => fs.existsSync(path.join(runDir, name)))
      || recoveryBlockers.length !== 0) {
    Common.fail("material_shop_pre_control_surface_not_empty", "pre_control_cleanup",
      "pre-control cleanup cannot coexist with raw/release/recovery artifacts");
  }
  const runtime = settings.firstRuntime
    ? publicRunningIdentity(settings.firstRuntime) : null;
  const value = { schema: PRE_CONTROL_FAILURE_RECEIPT_SCHEMA,
    recordedAt: new Date().toISOString(), runId: settings.preparation.runId,
    preparationSha256: settings.preparation.preparationSha256,
    buildSha256: settings.build.buildSha256,
    planSha256: settings.plan.planSha256,
    operationLease: JSON.parse(JSON.stringify(settings.operationHandle.lease)),
    operationTerminal: JSON.parse(JSON.stringify(settings.operationTerminal)),
    targetSlot: settings.preparation.slots.targetSlot,
    itemName: settings.itemName,
    originalError: Common.publicError(settings.error),
    cleanup: JSON.parse(JSON.stringify(settings.cleanupResult)),
    baselineSaveState: JSON.parse(JSON.stringify(settings.baselineSaveState)),
    transcript: captureExactRunArtifact(runDir, "passive-transcript.jsonl"),
    controlSurface: capturePreControlSurface(runDir),
    runtime,
    admissions: JSON.parse(JSON.stringify(settings.admissions || [])),
    sideEffects: { admissionCount: (settings.admissions || []).length, controlCount: 0,
      firstRuntimeAssigned: runtime !== null, restartRuntimeAssigned: false,
      observerAttached: false, rawPresent: false, evidencePresent: false,
      releasePresent: false, recoveryBlockerCount: 0 } };
  value.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  validatePreControlFailureCleanupReceipt(value, { runDir });
  const output = path.join(runDir, PRE_CONTROL_FAILURE_RECEIPT_NAME);
  writeJsonNew(output, value);
  return { receipt: value, receiptPath: output };
}

async function executeOwned(args, preparation, operationHandle, preflightApplicability) {
  const runDir = preparation.runDir;
  const closure = artifact(runDir, preparation.artifacts.closure, "run");
  const authority = verifyLifecycleApplicability(preparation);
  const applicability = authority.applicability;
  if (preflightApplicability && preflightApplicability.verificationSha256
      !== authority.verificationSha256) {
    Common.fail("material_shop_applicability_drift", "applicability",
      "materialized data or canonical fixture evidence changed after live preflight");
  }
  const plan = Protocol.validateControlPlan(artifact(runDir, preparation.artifacts.plan, "run"));
  const build = loadBuild(path.resolve(args.build), preparation, closure);
  if (build.liveAdmission !== plan.transportPolicy.liveAdmission
      || plan.transportPolicy.liveAdmission !== "candidate_ui_probe_required") {
    Common.fail("material_shop_live_admission_blocked", "run",
      "environment capability or route applicability blocks live execution", {
        admission: plan.transportPolicy.liveAdmission,
      });
  }
  Materialize.verifyPostBuildProtectedScope(preparation.resourcesRoot, closure.scope,
    Build.protectedScopeOptions(preparation, build.candidateRoot));
  if (plan.schema === Protocol.AGENT_RUNTIME_PLAN_SCHEMA) {
    return executeAgentRuntimeOwned(args, preparation, operationHandle, preflightApplicability, {
      closure, authority, applicability, plan, build,
    });
  }
  const materialized = loadMaterializedRuntimeModules(preparation, closure,
    build.candidateRoot);
  const externalToolchain = Build.loadExternalToolchain(preparation, closure, "run");
  if (Evidence.canonicalJson(externalToolchain)
      !== Evidence.canonicalJson(build.externalToolchain)) {
    Common.fail("material_shop_external_toolchain_drift", "run",
      "live runner toolchain differs from the candidate build binding");
  }
  const externalRuntime = ExternalToolchain.guardedLoad(externalToolchain);
  const NpcPassive = materialized.NpcPassive;
  const CandidateLifecycle = materialized.CandidateLifecycle;
  const lifecycleAuthority = verifyLifecycleApplicability(preparation);
  const lifecycleApplicability = lifecycleAuthority.applicability;
  if (lifecycleAuthority.verificationSha256 !== authority.verificationSha256) {
    Common.fail("material_shop_applicability_drift", "applicability",
      "materialized data or canonical fixture evidence changed before lifecycle preparation");
  }
  const channel = new Control.ControlChannel(Common.CANONICAL_ROOT, runDir, plan);
  const writer = new NpcPassive.TranscriptWriter(runDir);
  const lifecycle = await CandidateLifecycle.prepare({ canonicalRoot: preparation.resourcesRoot,
    fixtureAuthorityBinding: lifecycleAuthority.fixtureAuthorityBinding,
    resourcesRoot: preparation.resourcesRoot, candidateRoot: build.candidateRoot,
    runId: preparation.runId, seedSlot: preparation.slots.seedSlot,
    targetSlot: preparation.slots.targetSlot, recoverySlot: preparation.slots.recoverySlot,
    applicability: lifecycleApplicability,
    evidenceRoot: preparation.root, evidenceRunDir: runDir });
  let journey = lifecycle.journey;
  let firstRuntime = null;
  let restartRuntime = null;
  let observer = null;
  let commitMayHaveReachedAuthority = false;
  const controls = [];
  const admissions = [];
  let hostLogs = null;
  let archive = null;
  let archiveSaveState = null;
  let shutdown = null;
  let releaseIntentPath = null;
  let releasePhase = "not_started";
  let releasedClone = null;
  try {
    firstRuntime = await journey.start("first", {
      readyTimeoutMs: args.timeoutMs, timeoutMs: args.timeoutMs, pollMs: args.pollMs,
    });
    admissions.push(await admitCandidate(runDir, plan, "first", firstRuntime,
      args.timeoutMs, args.pollMs));
    observer = await NpcPassive.attachPassiveRecorder({ root: preparation.resourcesRoot,
      runDir, writer, cdpBinding: firstRuntime.cdpBinding, runtimeIdentity: firstRuntime.identity,
      webSocketImplementation: externalRuntime.WebSocket,
      observerId: plan.runId + ".first", timeoutMs: 30000, pollMs: args.pollMs });

    for (const step of plan.steps) {
      // issue() publishes current-request.json. Fence purchase authority before that
      // publication so every failure from this point preserves the isolated clone.
      commitMayHaveReachedAuthority = authorityRiskBeforeIssue(step.id,
        commitMayHaveReachedAuthority);
      const request = channel.issue(step.id, args.timeoutMs);
      process.stdout.write(JSON.stringify({ event: "visible_control_required", step: step.id,
        requestPath: path.join(runDir, "control", "requests", request.requestId + ".json"),
        currentRequestPath: path.join(runDir, "control", "current-request.json") }) + "\n");
      let ack;
      if (step.id === "restart_candidate") {
        restartRuntime = await journey.start("restart", {
          readyTimeoutMs: args.timeoutMs, timeoutMs: args.timeoutMs, pollMs: args.pollMs,
        });
        admissions.push(await admitCandidate(runDir, plan, "restart", restartRuntime,
          args.timeoutMs, args.pollMs));
        observer = await NpcPassive.attachPassiveRecorder({ root: preparation.resourcesRoot,
          runDir, writer, cdpBinding: restartRuntime.cdpBinding,
          runtimeIdentity: restartRuntime.identity, observerId: plan.runId + ".restart",
          webSocketImplementation: ExternalToolchain.reverifyLoaded(
            externalToolchain, externalRuntime.binding).WebSocket,
          timeoutMs: 30000, pollMs: args.pollMs });
        ack = runnerAck(channel, request, { restarted: true,
          admissionSha256: admissions[1].admission.admissionSha256 });
      } else if (step.id === "supported_shutdown") {
        if (observer) { await observer.detach(); observer = null; }
        shutdown = await journey.shutdownFinal("restart", {
          timeoutMs: args.timeoutMs, pollMs: args.pollMs,
        });
        ack = runnerAck(channel, request, shutdown.shutdown);
      } else {
        ack = await channel.wait(request, args.pollMs);
      }
      assertCompletedControlAck(ack, step.id);
      controls.push({ request, ack });
      if (step.id === "ordinary_close") {
        const close = latestNpcshopClose(writer.snapshot({
          completedAt: new Date().toISOString(),
        }));
        await journey.awaitExactClose("first", close.panelInstanceId, {
          timeoutMs: args.timeoutMs, pollMs: args.pollMs,
        });
      }
      if (step.id === "restart_close") {
        const close = latestPanelClose(writer.snapshot({
          completedAt: new Date().toISOString(),
        }), "crafting");
        await journey.awaitExactClose("restart", "crafting", close.panelInstanceId, {
          timeoutMs: args.timeoutMs, pollMs: args.pollMs,
        });
      }
      if (step.id === "safeexit") {
        archive = await journey.awaitArchive("first", {
          timeoutMs: args.timeoutMs, pollMs: args.pollMs,
        });
        archiveSaveState = await lifecycle.captureTargetSaveState("archive");
        if (observer) { await observer.detach(); observer = null; }
      }
      if (step.id === "exit_confirm") {
        await journey.awaitExit("first", { timeoutMs: args.timeoutMs, pollMs: args.pollMs });
      }
    }
    const seedInvariant = await journey.captureSeedInvariant();
    const recoveryInvariant = await lifecycle.captureRecoveryInvariant();
    const targetAfterRestart = await journey.captureCloneAfterRestart();
    const restartSaveState = await lifecycle.captureTargetSaveState("restart");
    const residue = await journey.verifyResidue();
    hostLogs = await journey.captureHostLog();
    ExternalToolchain.reverifyLoaded(externalToolchain, externalRuntime.binding);
    const raw = {
      schema: JourneyVerifier.RAW_SCHEMA,
      capturedAt: new Date().toISOString(),
      runId: plan.runId,
      planSha256: plan.planSha256,
      buildSha256: build.buildSha256,
      operationLease: operationHandle.lease,
      externalToolchainRuntime: externalRuntime.binding,
      materializedProducerBinding: materialized.producerBinding,
      lifecycle: lifecycle.evidence,
      admissions,
      controls,
      transcript: writer.snapshot({ completedAt: new Date().toISOString() }),
      hostLogs,
      persistence: { archive, seedInvariant, recoveryInvariant, targetAfterRestart,
        saveStates: { baseline: lifecycle.evidence.baselineSaveState,
          archive: archiveSaveState, restart: restartSaveState }, shutdown, residue },
      boundaries: { realGuiExecuted: true, candidateBuilt: true, candidateExecuted: true,
        e2eVerified: false, promoted: false, standardEntryVerified: false },
    };
    raw.rawSha256 = Evidence.sha256Text(Evidence.canonicalJson(raw));
    writeJsonNew(path.join(runDir, "raw-candidate-journey.json"), raw);
    const verified = JourneyVerifier.verifyRawCandidateJourney(raw, plan, applicability, runDir,
      build);
    writeJsonNew(path.join(runDir, "journey-evidence.json"), verified.evidence);
    const releaseContext = { preparation, build, raw, evidence: verified.evidence, plan };
    const releaseIntent = FinalizeCloneRelease.createIntent(releaseContext);
    releaseIntentPath = path.join(runDir, "clone-release-intent.json");
    writeJsonNew(releaseIntentPath, releaseIntent);
    releasePhase = advanceReleasePhase(releasePhase, "intent_written");
    releasePhase = advanceReleasePhase(releasePhase, "release_in_progress");
    releasedClone = await journey.release();
    releasePhase = advanceReleasePhase(releasePhase, "released");
    const release = FinalizeCloneRelease.createReleaseReceipt(releaseContext,
      releaseIntent, releasedClone);
    releasePhase = advanceReleasePhase(releasePhase, "receipt_created");
    FinalizeCloneRelease.writeReleaseReceipt(path.join(runDir, "release.json"),
      release, runDir);
    releasePhase = advanceReleasePhase(releasePhase, "receipt_written");
    const operationTerminal = RunOperationLease.release(operationHandle);
    return { raw, evidence: verified.evidence, release, operationTerminal };
  } catch (error) {
    if (isPostReleaseFinalizationPhase(releasePhase)) {
      const finalization = persistPostReleaseFinalizationRequired({
        releasePhase, releasedClone, releaseIntentPath, error,
        runDir, plan, preparation,
        preparationPath: args.preparation, buildPath: args.build,
      });
      Common.fail("material_shop_release_finalization_required", "run",
        "clone release completed; only release receipt finalization remains", {
          blockerPath: finalization.persisted.blockerPath,
          releasePhase,
          originalCode: error && error.code || null,
        });
    }
    if (releasePhase === "receipt_written") throw error;
    if (observer) { try { await observer.detach(); } catch (_detachError) {} }
    let cleanupResult = null;
    let cleanupError = null;
    if (journey && typeof journey.cleanupFailure === "function") {
      try { cleanupResult = await journey.cleanupFailure({ commitMayHaveReachedAuthority }); }
      catch (failure) { cleanupError = failure; }
    }
    const preControlCleanupEligible = !cleanupError
        && commitMayHaveReachedAuthority !== true
        && cleanupResult && cleanupResult.runtimeCleanupVerified === true
        && cleanupResult.shutdownSucceeded === true
        && cleanupResult.releasedBeforeCommit === true
        && cleanupResult.cloneAlreadyReleased === true
        && restartRuntime === null && observer === null
        && admissions.length <= 1 && controls.length === 0;
    if (preControlCleanupEligible) {
      try {
        const operationTerminal = RunOperationLease.release(operationHandle);
        writePreControlFailureCleanupReceipt({ runDir, preparation, build, plan,
          operationHandle, operationTerminal, error, cleanupResult, firstRuntime,
          admissions,
          itemName: applicability.selectedUnlockedTarget.itemName,
          baselineSaveState: lifecycle.evidence.baselineSaveState });
      } catch (failure) { cleanupError = failure; }
    } else if (!cleanupError && commitMayHaveReachedAuthority !== true
        && cleanupResult && cleanupResult.cloneAlreadyReleased === true) {
      cleanupError = Object.assign(new Error(
        "a safely released clone lacks the exact pre-control cleanup receipt contract"), {
        code: "material_shop_pre_control_cleanup_receipt_ineligible",
      });
    }
    if (requiresRecoveryBlocker(commitMayHaveReachedAuthority, cleanupResult, cleanupError)) {
      const persisted = writeRecoveryBlocker({ runDir, plan, preparation,
        preparationPath: path.resolve(args.preparation), buildPath: path.resolve(args.build),
        releaseIntentPath, commitMayHaveReachedAuthority, error, cleanupResult, cleanupError });
      Common.fail("material_shop_manual_recovery_required", "run",
        "live failure preserved an isolated target for exact manual recovery", {
          blockerPath: persisted.blockerPath, originalCode: error && error.code || null,
          cleanupCode: cleanupError && cleanupError.code || null,
        });
    }
    throw error;
  }
}

async function execute(args) {
  const preparation = Build.loadPreparation(path.resolve(args.preparation));
  const buildEnvelope = Build.loadBuildEnvelope(path.resolve(args.build), preparation,
    "run_operation_lease");
  const preflightApplicability = verifyLifecycleApplicability(preparation);
  DiscardBuilt.assertLiveExecutionAvailable(preparation.runDir);
  const operationHandle = RunOperationLease.acquire({ runDir: preparation.runDir,
    runId: preparation.runId, mode: "live_execution",
    preparationSha256: preparation.preparationSha256,
    buildSha256: buildEnvelope.buildSha256 });
  try {
    try {
      DiscardBuilt.assertLiveExecutionAvailable(preparation.runDir);
    } catch (error) {
      RunOperationLease.cancelBeforeExecution(operationHandle);
      throw error;
    }
    RunOperationLease.markExecutionStarted(operationHandle);
    return await executeOwned(args, preparation, operationHandle, preflightApplicability);
  } finally {
    if (operationHandle.active) RunOperationLease.release(operationHandle);
  }
}

async function main() {
  try {
    const result = await execute(parseArgs(process.argv.slice(2)));
    process.stdout.write(JSON.stringify({ ok: true, result: "CANDIDATE_CAPTURED",
      evidenceSha256: result.evidence.evidenceSha256,
      e2eVerified: false, promoted: false }) + "\n");
  } catch (error) {
    const output = Common.publicError(error);
    if (error && error.code === "material_shop_agent_action_receipt_invalid"
        && error.details && typeof error.details === "object") {
      const details = error.details;
      output.actionReceiptDiagnostic = {
        stepId: typeof details.stepId === "string" ? details.stepId : null,
        role: typeof details.role === "string" ? details.role : null,
        actionId: typeof details.actionId === "string" ? details.actionId : null,
        terminal: typeof details.terminal === "boolean" ? details.terminal : null,
        outcome: typeof details.outcome === "string" ? details.outcome : null,
        evidenceKind: typeof details.evidenceKind === "string"
          ? details.evidenceKind : null,
        reasonCode: typeof details.reasonCode === "string" ? details.reasonCode : null,
        reconcileKind: typeof details.reconcileKind === "string"
          ? details.reconcileKind : null,
        retryable: typeof details.retryable === "boolean" ? details.retryable : null,
      };
    }
    process.stderr.write(JSON.stringify(output) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  PRE_CONTROL_FAILURE_RECEIPT_NAME,
  PRE_CONTROL_FAILURE_RECEIPT_SCHEMA,
  advanceReleasePhase,
  admitCandidate,
  assertCompletedControlAck,
  authorityRiskBeforeIssue,
  execute,
  executeOwned,
  latestNpcshopClose,
  latestPanelClose,
  loadBuild,
  loadMaterializedRuntimeModules,
  parseArgs,
  publicRunningIdentity,
  requiresRecoveryBlocker,
  runnerAck,
  agentRuntimeCoordinateProvider,
  agentRuntimePoint,
  executeAgentRuntimeOwned,
  loadMaterializedAgentRuntimeModules,
  isPostReleaseFinalizationPhase,
  persistPostReleaseFinalizationRequired,
  verifyLifecycleApplicability,
  validateFreshReleasedCloneInspection,
  validatePreControlFailureCleanupReceipt,
  verifyPreControlBaselineInvariant,
  writePreControlFailureCleanupReceipt,
  writeRecoveryBlocker,
};
