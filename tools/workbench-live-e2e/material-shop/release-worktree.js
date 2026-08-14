"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const CloneGuard = require("../lib/clone-save-guard");
const LauncherObservation = require("../lib/launcher-observation");
const Accept = require("./accept-run");
const Common = require("./common");
const FinalizeCloneRelease = require("./finalize-clone-release");
const JourneyVerifier = require("./journey-verifier");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const Production = require("./production-closure");
const VerifyRun = require("./verify-run");

const RELEASE_SCHEMA = "workbench-live-e2e.material-shop.worktree-release.v2";
const REMOVAL_INTENT_SCHEMA = "workbench-live-e2e.material-shop.worktree-removal-intent.v1";
const REMOVAL_INTENT_NAME = "worktree-removal-intent.json";
const REMOVAL_OUTPUT_NAME = "worktree-release.json";
const REMOVAL_RESOLVED_PREFIX = "worktree-removal-resolved-";

function runGit(root, args) {
  const result = childProcess.spawnSync("git", ["-C", root].concat(args), {
    encoding: "utf8", windowsHide: true, maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    Common.fail("material_shop_worktree_release_failed", "release_worktree",
      "git worktree removal failed", { status: result.status,
        stderr: String(result.stderr || result.error && result.error.message || "").slice(0, 4000) });
  }
}

function gitOutput(root, args) {
  const result = childProcess.spawnSync("git", ["-C", root].concat(args), {
    encoding: "utf8", windowsHide: true, maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    Common.fail("material_shop_worktree_release_git_probe_failed", "release_worktree",
      "Git identity probe failed before exact worktree removal", { status: result.status });
  }
  return String(result.stdout || "").trim();
}

function digestWithout(value, key) {
  const unsigned = Object.assign({}, value);
  delete unsigned[key];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function writeJsonAtomicNew(filePath, value) {
  const output = path.resolve(filePath);
  const digest = Evidence.sha256Text(Evidence.canonicalJson(value));
  const staged = output + ".staged-" + digest.slice(0, 16);
  try {
    fs.writeFileSync(staged, JSON.stringify(value, null, 2) + "\n",
      { encoding: "utf8", mode: 0o600, flag: "wx" });
    fs.renameSync(staged, output);
  } catch (error) {
    if (fs.existsSync(staged)) fs.unlinkSync(staged);
    throw error;
  }
  return output;
}

function resolvedRemovalName(intent) {
  return REMOVAL_RESOLVED_PREFIX + intent.intentSha256.slice(0, 16) + ".json";
}

function removalMarkerFiles(runDirValue) {
  const runDir = path.resolve(runDirValue);
  return fs.readdirSync(runDir, { withFileTypes: true }).filter((entry) => entry.isFile()
    && (entry.name === REMOVAL_INTENT_NAME
      || new RegExp("^" + REMOVAL_RESOLVED_PREFIX + "[a-f0-9]{16}\\.json$")
        .test(entry.name))).map((entry) => entry.name).sort();
}

function validateRemovalIntent(value) {
  Common.exactKeys(value, ["schema", "createdAt", "runId", "canonicalRoot", "runDir",
    "destination", "outputPath", "materializationSha256", "preparationSha256",
    "closureSha256", "buildSha256", "rawSha256", "journeyEvidenceSha256",
    "cloneReleaseSha256", "acceptanceSha256", "cloneInspectionSha256",
    "gitWorktreeIdentitySha256", "head", "commonDir", "command",
    "acknowledgedIsolatedDiscard", "intentSha256"],
  "material_shop_worktree_removal_intent_invalid", "release_worktree");
  const canonicalRoot = path.resolve(value.canonicalRoot || "");
  const ownedBase = path.resolve(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const runDir = path.resolve(value.runDir || "");
  const destination = path.resolve(value.destination || "");
  const output = path.resolve(value.outputPath || "");
  const digests = [value.materializationSha256, value.preparationSha256,
    value.closureSha256, value.buildSha256, value.rawSha256,
    value.journeyEvidenceSha256, value.cloneReleaseSha256, value.acceptanceSha256,
    value.cloneInspectionSha256, value.gitWorktreeIdentitySha256];
  if (value.schema !== REMOVAL_INTENT_SCHEMA || !Number.isFinite(Date.parse(value.createdAt))
      || !Common.ID_RE.test(String(value.runId || ""))
      || canonicalRoot.toLowerCase() !== Common.CANONICAL_ROOT.toLowerCase()
      || !Evidence.pathInside(path.join(ownedBase, "runs"), runDir)
      || path.basename(runDir) !== value.runId
      || output.toLowerCase() !== path.join(runDir, REMOVAL_OUTPUT_NAME).toLowerCase()
      || !Evidence.pathInside(path.join(ownedBase, Materialize.MATERIALIZED_DIRECTORY),
        destination)
      || path.basename(destination).toLowerCase() !== "resources"
      || path.basename(path.dirname(destination)) !== value.runId
      || digests.some((entry) => !Common.SHA256_RE.test(String(entry || "")))
      || !Common.GIT_OID_RE.test(String(value.head || ""))
      || path.resolve(value.commonDir || "").toLowerCase()
        !== path.resolve(canonicalRoot, gitOutput(canonicalRoot,
          ["rev-parse", "--git-common-dir"])).toLowerCase()
      || value.command !== "git worktree remove --force"
      || value.acknowledgedIsolatedDiscard !== true
      || value.intentSha256 !== digestWithout(value, "intentSha256")) {
    Common.fail("material_shop_worktree_removal_intent_invalid", "release_worktree",
      "worktree removal intent is malformed, foreign, or detached from acceptance");
  }
  return value;
}

function createRemovalIntent(options) {
  const settings = options || {};
  const value = { schema: REMOVAL_INTENT_SCHEMA,
    createdAt: settings.createdAt || new Date().toISOString(), runId: settings.runId,
    canonicalRoot: Common.CANONICAL_ROOT, runDir: path.resolve(settings.runDir),
    destination: path.resolve(settings.destination), outputPath: path.resolve(settings.outputPath),
    materializationSha256: settings.materializationSha256,
    preparationSha256: settings.preparationSha256, closureSha256: settings.closureSha256,
    buildSha256: settings.buildSha256, rawSha256: settings.rawSha256,
    journeyEvidenceSha256: settings.journeyEvidenceSha256,
    cloneReleaseSha256: settings.cloneReleaseSha256,
    acceptanceSha256: settings.acceptanceSha256,
    cloneInspectionSha256: settings.cloneInspectionSha256,
    gitWorktreeIdentitySha256: settings.gitWorktreeIdentitySha256,
    head: settings.head, commonDir: path.resolve(settings.commonDir),
    command: "git worktree remove --force", acknowledgedIsolatedDiscard: true };
  value.intentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateRemovalIntent(value);
}

function assertRemovalOutputsAvailable(runDirValue, outputPathValue) {
  const runDir = path.resolve(runDirValue);
  const output = path.resolve(outputPathValue);
  const staging = fs.readdirSync(runDir, { withFileTypes: true }).filter((entry) => entry.isFile()
    && /^(?:worktree-release|worktree-removal-intent)\.json\.staged-[a-f0-9]{16}$/.test(
      entry.name)).map((entry) => entry.name);
  if (output.toLowerCase() !== path.join(runDir, REMOVAL_OUTPUT_NAME).toLowerCase()
      || fs.existsSync(output) || removalMarkerFiles(runDir).length !== 0
      || staging.length !== 0) {
    Common.fail("material_shop_worktree_release_output_invalid", "release_worktree",
      "canonical worktree release output and removal-intent names must all be absent");
  }
  return output;
}

function inspectRemovalAttempt(runDirValue, outputPathValue) {
  const runDir = path.resolve(runDirValue);
  const output = path.resolve(outputPathValue);
  const staging = fs.readdirSync(runDir, { withFileTypes: true }).filter((entry) => entry.isFile()
    && /^(?:worktree-release|worktree-removal-intent)\.json\.staged-[a-f0-9]{16}$/.test(
      entry.name)).map((entry) => entry.name);
  const names = removalMarkerFiles(runDir);
  if (output.toLowerCase() !== path.join(runDir, REMOVAL_OUTPUT_NAME).toLowerCase()
      || fs.existsSync(output) || staging.length !== 0 || names.length > 1
      || (names.length === 1 && names[0] !== REMOVAL_INTENT_NAME)) {
    Common.fail("material_shop_worktree_release_output_invalid", "release_worktree",
      "release may start clean or resume one exact active removal intent only");
  }
  return { output, activeIntent: names.length === 1
    ? loadRemovalState(runDir).intent : null };
}

function bindRemovalAttempt(activeIntent, expectedIntent, state) {
  const expected = validateRemovalIntent(expectedIntent);
  if (!activeIntent) return { intent: expected, resumed: false };
  const active = validateRemovalIntent(activeIntent);
  const destinationPresent = state && state.destinationPresent === true;
  const listed = state && state.worktreeListed === true;
  if (destinationPresent !== listed) {
    Common.fail("material_shop_worktree_removal_partial_state_invalid", "release_worktree",
      "active intent found a split filesystem/Git worktree state; do not retry deletion");
  }
  if (!destinationPresent) {
    Common.fail("material_shop_worktree_removal_already_completed", "release_worktree",
      "worktree is already absent; finish the durable receipt with --finalize-removal");
  }
  if (Evidence.canonicalJson(active) !== Evidence.canonicalJson(expected)) {
    Common.fail("material_shop_worktree_removal_resume_binding_invalid", "release_worktree",
      "active removal intent does not byte-match the fully revalidated acceptance context");
  }
  return { intent: active, resumed: true };
}

function validateLockInspection(value, slot) {
  Common.exactKeys(value, ["schema", "apiVersion", "observedAt", "slot", "lockPath",
    "lockPresent", "recordSha256", "ownerPid", "ownerProcessStartUtcTicks",
    "observedProcessStartUtcTicks", "ownerState", "recoveryPresent", "recoveryStatus",
    "recoveryRecordSha256", "evidenceSha256"],
  "material_shop_release_clone_inspection_invalid", "release_worktree");
  const unsigned = Object.assign({}, value);
  delete unsigned.evidenceSha256;
  if (value.schema !== "workbench-live-e2e.clone-lock-inspection.v1"
      || value.apiVersion !== CloneGuard.API_VERSION
      || value.slot !== slot || !Number.isFinite(Date.parse(value.observedAt))
      || value.lockPresent !== false || value.ownerState !== "absent"
      || value.recoveryPresent !== false || value.recoveryStatus !== null
      || value.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_release_clone_inspection_invalid", "release_worktree",
      "worktree release requires no active/stale clone lock or recovery record");
  }
  return value;
}

function cloneInspectionStateSha256(value, slot) {
  const inspection = validateLockInspection(value, slot);
  const stable = Object.assign({}, inspection);
  delete stable.observedAt;
  delete stable.evidenceSha256;
  return Evidence.sha256Text(Evidence.canonicalJson(stable));
}

function assertReleaseSafetySignals(options) {
  const settings = options || {};
  const acceptance = settings.acceptance;
  const raw = settings.raw;
  const cloneRelease = settings.cloneRelease;
  const blockerFiles = settings.blockerFiles || [];
  const inspection = validateLockInspection(settings.lockInspection,
    settings.targetSlot);
  const controls = raw && Array.isArray(raw.controls) ? raw.controls : [];
  const legacyCompleted = (step) => controls.some((entry) => entry.request
    && entry.request.step === step && entry.ack && entry.ack.result === "completed");
  const commonInvalid = !acceptance || acceptance.status !== "e2e_verified"
      || acceptance.deployment !== "NOT_DEPLOYED"
      || !acceptance.boundaries || acceptance.boundaries.e2eVerified !== true
      || acceptance.boundaries.promoted !== false
      || !raw || !raw.boundaries || raw.boundaries.candidateExecuted !== true
      || raw.boundaries.e2eVerified !== false
      || !cloneRelease || cloneRelease.cloneLockReleased !== true
      || cloneRelease.recoveryCleared !== true
      || blockerFiles.length !== 0;
  const agentRuntime = raw && raw.schema === JourneyVerifier.AGENT_RUNTIME_RAW_SCHEMA;
  let lifecycleInvalid;
  if (agentRuntime) {
    const completed = (step) => controls.some((entry) => entry.stepId === step
      && Number.isFinite(Date.parse(entry.completedAt)));
    const required = ["trusted_runner_persistence_shutdown", "restart_candidate",
      "restart_readback", "restart_close", "trusted_runner_final_shutdown"];
    const sessions = Array.isArray(raw.sessions) ? raw.sessions : [];
    const persistence = raw.persistence || {};
    const shutdowns = [persistence.firstShutdown, persistence.restartShutdown];
    const expectedLabels = ["first", "restart"];
    const cleanSessions = sessions.length === expectedLabels.length
      && sessions.every((session, index) => {
        const shutdown = shutdowns[index];
        const completionSha256 = session && session.completion
          ? Evidence.sha256Text(Evidence.canonicalJson(session.completion)) : null;
        return session && session.label === expectedLabels[index]
          && session.cleanExit === true && completionSha256
          && shutdown && shutdown.sessionLabel === expectedLabels[index]
          && shutdown.cleanExit === true
          && shutdown.completionSha256 === completionSha256;
      });
    const archive = persistence.saveStates && persistence.saveStates.archive;
    const restart = persistence.saveStates && persistence.saveStates.restart;
    const target = persistence.targetAfterRestart;
    const targetRestartExact = archive && restart && target
      && Common.SHA256_RE.test(String(archive.sha256 || ""))
      && Common.SHA256_RE.test(String(restart.sha256 || ""))
      && Common.SHA256_RE.test(String(archive.semanticSha256 || ""))
      && Common.SHA256_RE.test(String(restart.semanticSha256 || ""))
      && archive.semanticSha256 === restart.semanticSha256
      && target.jsonSha256 === restart.sha256;
    lifecycleInvalid = required.some((step) => !completed(step))
      || !cleanSessions || !targetRestartExact;
  } else {
    lifecycleInvalid = !raw || !legacyCompleted("safeexit") || !legacyCompleted("exit_confirm")
      || !legacyCompleted("restart_candidate") || !legacyCompleted("restart_readback")
      || !legacyCompleted("restart_close") || !legacyCompleted("supported_shutdown")
      || !raw.persistence || !raw.persistence.archive || !raw.persistence.shutdown;
  }
  if (commonInvalid || lifecycleInvalid) {
    Common.fail("material_shop_worktree_release_not_admitted", "release_worktree",
      agentRuntime
        ? "exact e2e acceptance, trusted-runner restart persistence, clone release, and zero blockers are required"
        : "exact e2e acceptance, SAFEEXIT/restart/shutdown, clone release, and zero blockers are required", {
        blockerFiles,
      });
  }
  if (agentRuntime) {
    return { inspection, trustedRunnerPersistenceShutdownComplete: true,
      restartReadbackComplete: true, trustedRunnerFinalShutdownComplete: true,
      targetRestartExact: true, archiveRestartSemanticEqual: true, accepted: true };
  }
  return { inspection, safeExitComplete: true, restartReadbackComplete: true,
    accepted: true };
}

function validateReleaseBinding(options) {
  const settings = options || {};
  const materialization = settings.materialization;
  const context = settings.context;
  const destination = path.resolve(settings.destination || "");
  if (!materialization || !context || materialization.mode !== Materialize.PRODUCTION_MODE
      || materialization.materializationSha256
        !== context.preparation.materializationSha256
      || destination.toLowerCase()
        !== path.resolve(context.preparation.resourcesRoot).toLowerCase()
      || !Evidence.pathInside(settings.expectedBase, destination)
      || path.basename(destination).toLowerCase() !== "resources"
      || settings.gitMetadataPresent !== true
      || !materialization.gitWorktree || materialization.gitWorktree.detached !== true
      || materialization.gitWorktree.head !== context.closure.head
      || path.resolve(materialization.gitWorktree.commonDir).toLowerCase()
        !== path.resolve(settings.canonicalCommonDir).toLowerCase()) {
    Common.fail("material_shop_worktree_release_target_invalid", "release_worktree",
      "release target is not the exact accepted detached materialized Git worktree");
  }
  return materialization;
}

function worktreeListed(canonicalRoot, destination) {
  const target = path.resolve(destination).toLowerCase();
  return gitOutput(canonicalRoot, ["worktree", "list", "--porcelain"])
    .split(/\r?\n/).filter((line) => line.startsWith("worktree "))
    .some((line) => path.resolve(line.slice("worktree ".length)).toLowerCase() === target);
}

function receiptFromIntent(intent, completedAt) {
  validateRemovalIntent(intent);
  const value = { schema: RELEASE_SCHEMA, startedAt: intent.createdAt,
    completedAt: completedAt || new Date().toISOString(), runId: intent.runId,
    destination: intent.destination, materializationSha256: intent.materializationSha256,
    preparationSha256: intent.preparationSha256, closureSha256: intent.closureSha256,
    buildSha256: intent.buildSha256, rawSha256: intent.rawSha256,
    journeyEvidenceSha256: intent.journeyEvidenceSha256,
    cloneReleaseSha256: intent.cloneReleaseSha256,
    acceptanceSha256: intent.acceptanceSha256,
    cloneInspectionSha256: intent.cloneInspectionSha256,
    gitWorktreeIdentitySha256: intent.gitWorktreeIdentitySha256,
    removalIntentSha256: intent.intentSha256, removalMarkerResolved: true,
    command: intent.command, recoverable: false,
    acknowledgedIsolatedDiscard: intent.acknowledgedIsolatedDiscard };
  value.releaseSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateRemovalReceipt(value, intent);
}

function validateRemovalReceipt(value, intent) {
  validateRemovalIntent(intent);
  Common.exactKeys(value, ["schema", "startedAt", "completedAt", "runId", "destination",
    "materializationSha256", "preparationSha256", "closureSha256", "buildSha256",
    "rawSha256", "journeyEvidenceSha256", "cloneReleaseSha256", "acceptanceSha256",
    "cloneInspectionSha256", "gitWorktreeIdentitySha256", "removalIntentSha256",
    "removalMarkerResolved", "command", "recoverable", "acknowledgedIsolatedDiscard",
    "releaseSha256"], "material_shop_worktree_release_receipt_invalid",
  "release_worktree");
  const expected = receiptFromIntentProjection(intent);
  const actual = Object.assign({}, value);
  delete actual.completedAt;
  delete actual.releaseSha256;
  if (value.schema !== RELEASE_SCHEMA || !Number.isFinite(Date.parse(value.completedAt))
      || Date.parse(value.completedAt) < Date.parse(intent.createdAt)
      || Evidence.canonicalJson(actual) !== Evidence.canonicalJson(expected)
      || value.releaseSha256 !== digestWithout(value, "releaseSha256")) {
    Common.fail("material_shop_worktree_release_receipt_invalid", "release_worktree",
      "worktree release receipt is malformed or detached from its durable removal intent");
  }
  return value;
}

function receiptFromIntentProjection(intent) {
  return { schema: RELEASE_SCHEMA, startedAt: intent.createdAt, runId: intent.runId,
    destination: intent.destination, materializationSha256: intent.materializationSha256,
    preparationSha256: intent.preparationSha256, closureSha256: intent.closureSha256,
    buildSha256: intent.buildSha256, rawSha256: intent.rawSha256,
    journeyEvidenceSha256: intent.journeyEvidenceSha256,
    cloneReleaseSha256: intent.cloneReleaseSha256,
    acceptanceSha256: intent.acceptanceSha256,
    cloneInspectionSha256: intent.cloneInspectionSha256,
    gitWorktreeIdentitySha256: intent.gitWorktreeIdentitySha256,
    removalIntentSha256: intent.intentSha256, removalMarkerResolved: true,
    command: intent.command, recoverable: false,
    acknowledgedIsolatedDiscard: intent.acknowledgedIsolatedDiscard };
}

function loadRemovalState(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "release_worktree");
  const names = removalMarkerFiles(runDir);
  if (names.length !== 1) {
    Common.fail("material_shop_worktree_removal_state_invalid", "release_worktree",
      "exactly one active or resolved worktree removal intent is required", { names });
  }
  const markerPath = path.join(runDir, names[0]);
  const intent = validateRemovalIntent(Prepare.readJson(markerPath, "release_worktree"));
  const expectedResolved = resolvedRemovalName(intent);
  if (names[0] !== REMOVAL_INTENT_NAME && names[0] !== expectedResolved) {
    Common.fail("material_shop_worktree_removal_state_invalid", "release_worktree",
      "resolved removal marker name differs from its sealed intent");
  }
  return { runDir, intent, markerPath, active: names[0] === REMOVAL_INTENT_NAME,
    resolvedPath: path.join(runDir, expectedResolved) };
}

function finalizeRemoval(runDirValue, options) {
  const state = loadRemovalState(runDirValue);
  const intent = state.intent;
  if (fs.existsSync(intent.destination)
      || worktreeListed(intent.canonicalRoot, intent.destination)) {
    Common.fail("material_shop_worktree_removal_incomplete", "release_worktree",
      "durable removal intent cannot finalize while the exact worktree still exists");
  }
  const output = path.resolve(intent.outputPath);
  if (!state.active && !fs.existsSync(output)) {
    Common.fail("material_shop_worktree_release_receipt_missing", "release_worktree",
      "resolved worktree removal marker cannot recreate a missing receipt");
  }
  const value = fs.existsSync(output)
    ? validateRemovalReceipt(Prepare.readJson(output, "release_worktree"), intent)
    : receiptFromIntent(intent);
  if (!fs.existsSync(output)) {
    const writer = options && options.writeReceipt || writeJsonAtomicNew;
    writer(output, value);
  }
  if (state.active) {
    if (fs.existsSync(state.resolvedPath)) {
      Common.fail("material_shop_worktree_removal_state_invalid", "release_worktree",
        "active and resolved worktree removal markers coexist");
    }
    fs.renameSync(state.markerPath, state.resolvedPath);
  }
  const replay = loadRemovalState(state.runDir);
  if (replay.active || replay.resolvedPath.toLowerCase() !== state.resolvedPath.toLowerCase()
      || Evidence.canonicalJson(replay.intent) !== Evidence.canonicalJson(intent)) {
    Common.fail("material_shop_worktree_removal_state_invalid", "release_worktree",
      "worktree removal marker archive did not preserve the exact intent");
  }
  return validateRemovalReceipt(Prepare.readJson(output, "release_worktree"), intent);
}

function release(options) {
  const settings = options || {};
  const context = Accept.loadContext({ preparation: settings.preparation,
    build: settings.build, raw: settings.raw, evidence: settings.evidence,
    release: settings.cloneRelease });
  const staticGate = Accept.validateStaticGate(
    Prepare.readJson(settings.staticGate, "release_worktree"), context);
  const reviewRequest = Accept.validateReviewRequest(
    Prepare.readJson(settings.reviewRequest, "release_worktree"), context, staticGate);
  const reviewReceipt = Accept.validateReviewReceipt(
    Prepare.readJson(settings.reviewReceipt, "release_worktree"), reviewRequest);
  const acceptance = Accept.validateAcceptance(
    Prepare.readJson(settings.acceptance, "release_worktree"), context, staticGate,
    reviewRequest, reviewReceipt);
  const materialization = Prepare.readJson(settings.materialization, "release_worktree");
  const boundMaterialization = VerifyRun.artifact(context.preparation.runDir,
    context.preparation.artifacts.materialization);
  if (Evidence.canonicalJson(materialization) !== Evidence.canonicalJson(boundMaterialization)) {
    Common.fail("material_shop_worktree_release_materialization_drift", "release_worktree",
      "provided materialization differs from the preparation-bound artifact");
  }
  Materialize.verifyMaterialization(materialization, context.closure.scope, {
    ownedBase: materialization.ownedBase, fixtureMode: false, allowBuildOutputs: true,
  });
  const destination = path.resolve(materialization.destination || "");
  const expectedBase = path.resolve(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    Materialize.MATERIALIZED_DIRECTORY);
  const canonicalCommonDir = path.resolve(Common.CANONICAL_ROOT,
    gitOutput(Common.CANONICAL_ROOT, ["rev-parse", "--git-common-dir"]));
  validateReleaseBinding({ materialization, context, destination, expectedBase,
    canonicalCommonDir, gitMetadataPresent: fs.existsSync(path.join(destination, ".git")) });
  const outputPath = path.resolve(settings.out || "");
  const removalAttempt = inspectRemovalAttempt(context.preparation.runDir, outputPath);
  if (!settings.acknowledge) {
    Common.fail("material_shop_worktree_release_ack_required", "release_worktree",
      "isolated worktree discard requires the explicit acknowledgement flag");
  }
  Production.verifyMaterializedSharedProducers(
    context.build.materializedProducerBinding, destination, context.closure);
  Materialize.verifyIgnoredOutputInventory(context.release.ignoredOutputInventory,
    destination, FinalizeCloneRelease.ignoredOutputOptions(
      context, context.release.markerEvidence));
  const blockerFiles = FinalizeCloneRelease.unresolvedBlockerFiles(
    context.preparation.runDir, context, context.release.markerEvidence);
  const lockInspection = CloneGuard.inspectCloneLock({ root: destination,
    slot: context.plan.slots.targetSlot });
  const safety = assertReleaseSafetySignals({ acceptance, raw: context.raw,
    cloneRelease: context.release, blockerFiles, lockInspection,
    targetSlot: context.plan.slots.targetSlot });
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  const startedAt = removalAttempt.activeIntent
    ? removalAttempt.activeIntent.createdAt : new Date().toISOString();
  const expectedIntent = createRemovalIntent({ createdAt: startedAt, runId: context.plan.runId,
    runDir: context.preparation.runDir, destination, outputPath,
    materializationSha256: materialization.materializationSha256,
    preparationSha256: context.preparation.preparationSha256,
    closureSha256: context.closure.closureSha256,
    buildSha256: context.build.buildSha256, rawSha256: context.raw.rawSha256,
    journeyEvidenceSha256: context.evidence.evidenceSha256,
    cloneReleaseSha256: context.release.releaseSha256,
    acceptanceSha256: acceptance.acceptanceSha256,
    cloneInspectionSha256: cloneInspectionStateSha256(safety.inspection,
      context.plan.slots.targetSlot),
    gitWorktreeIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(materialization.gitWorktree)),
    head: materialization.gitWorktree.head, commonDir: canonicalCommonDir });
  const binding = bindRemovalAttempt(removalAttempt.activeIntent, expectedIntent, {
    destinationPresent: fs.existsSync(destination),
    worktreeListed: worktreeListed(Common.CANONICAL_ROOT, destination),
  });
  const intent = binding.intent;
  if (!binding.resumed) {
    writeJsonAtomicNew(path.join(context.preparation.runDir, REMOVAL_INTENT_NAME), intent);
  }
  runGit(Common.CANONICAL_ROOT, ["worktree", "remove", "--force", destination]);
  if (fs.existsSync(destination)) {
    Common.fail("material_shop_worktree_release_incomplete", "release_worktree",
      "git worktree remove left the exact resources directory present");
  }
  return finalizeRemoval(context.preparation.runDir);
}

function parseArgs(argv) {
  const args = { mode: "release", runDir: null, preparation: null, build: null, raw: null, evidence: null,
    cloneRelease: null, staticGate: null, reviewRequest: null, reviewReceipt: null,
    acceptance: null, materialization: null, acknowledge: false, out: null };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--finalize-removal") args.mode = "finalize";
    else if (argv[index] === "--run-dir") args.runDir = argv[++index];
    else if (argv[index] === "--preparation") args.preparation = argv[++index];
    else if (argv[index] === "--build") args.build = argv[++index];
    else if (argv[index] === "--raw") args.raw = argv[++index];
    else if (argv[index] === "--evidence") args.evidence = argv[++index];
    else if (argv[index] === "--clone-release") args.cloneRelease = argv[++index];
    else if (argv[index] === "--static-gate") args.staticGate = argv[++index];
    else if (argv[index] === "--review-request") args.reviewRequest = argv[++index];
    else if (argv[index] === "--review-receipt") args.reviewReceipt = argv[++index];
    else if (argv[index] === "--acceptance") args.acceptance = argv[++index];
    else if (argv[index] === "--materialization") args.materialization = argv[++index];
    else if (argv[index] === "--out") args.out = argv[++index];
    else if (argv[index] === "--acknowledge-discard-isolated-worktree") args.acknowledge = true;
    else Common.fail("material_shop_release_argument_unknown", "release_worktree", argv[index]);
  }
  if (args.mode === "finalize") {
    if (!args.runDir || Object.keys(args).some((key) => !["mode", "runDir"].includes(key)
      && args[key] !== null && args[key] !== false)) {
      Common.fail("material_shop_release_arguments_invalid", "release_worktree",
        "removal finalization accepts only one exact run directory");
    }
    return args;
  }
  if (args.runDir) {
    Common.fail("material_shop_release_arguments_invalid", "release_worktree",
      "run directory is accepted only by the removal finalizer mode");
  }
  if (![args.preparation, args.build, args.raw, args.evidence, args.cloneRelease,
    args.staticGate, args.reviewRequest, args.reviewReceipt, args.acceptance,
    args.materialization, args.out].every(Boolean) || !args.acknowledge) {
    Common.fail("material_shop_release_arguments_invalid", "release_worktree",
      "full accepted journey closure, materialization, output, and discard acknowledgement are required");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const value = args.mode === "finalize" ? finalizeRemoval(args.runDir) : release(args);
    process.stdout.write(JSON.stringify({ ok: true, destination: value.destination,
      releaseSha256: value.releaseSha256 }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = { RELEASE_SCHEMA, REMOVAL_INTENT_NAME, REMOVAL_INTENT_SCHEMA,
  REMOVAL_OUTPUT_NAME, REMOVAL_RESOLVED_PREFIX, assertReleaseSafetySignals,
  assertRemovalOutputsAvailable, bindRemovalAttempt, createRemovalIntent, finalizeRemoval,
  cloneInspectionStateSha256, inspectRemovalAttempt, loadRemovalState, parseArgs,
  receiptFromIntent, release,
  removalMarkerFiles, resolvedRemovalName,
  validateLockInspection, validateReleaseBinding, validateRemovalIntent,
  validateRemovalReceipt, writeJsonAtomicNew };
