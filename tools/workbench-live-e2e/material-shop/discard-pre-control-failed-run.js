#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const Applicability = require("./applicability");
const Build = require("./build-candidate");
const Common = require("./common");
const DiscardBuilt = require("./discard-built-run");
const LiveRun = require("./run-live-journey");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const Production = require("./production-closure");
const Protocol = require("./protocol");
const RunOperationLease = require("./run-operation-lease");

const INTENT_SCHEMA = "workbench-live-e2e.material-shop.pre-control-failure-discard-intent.v1";
const RECEIPT_SCHEMA = "workbench-live-e2e.material-shop.pre-control-failure-discard.v1";
const INTENT_NAME = "pre-control-failure-discard-intent.json";
const RECEIPT_NAME = "pre-control-failure-discard.json";
const RESOLVED_PREFIX = "pre-control-failure-discard-resolved-";
const RESUME_SCHEMA = "workbench-live-e2e.material-shop.pre-control-failure-discard-resume.v1";
const RESUME_PREFIX = "pre-control-failure-discard-resume-";
const FIXTURE_RUNTIME_TOKEN = Symbol("pre-control-discard-fixture-runtime");

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function digestWithout(value, key) {
  const copy = Object.assign({}, value);
  delete copy[key];
  return Evidence.sha256Text(Evidence.canonicalJson(copy));
}

function readBoundJson(runDir, reference, phase) {
  const absolute = Common.resolveWithin(runDir,
    String(reference && reference.relativePath || ""), phase).absolute;
  const file = Evidence.readExactRegularFile(absolute, {
    phase, maximumBytes: 128 * 1024 * 1024,
  });
  if (file.length !== reference.bytes || file.sha256 !== reference.sha256) {
    Common.fail("material_shop_pre_control_discard_artifact_drift", phase,
      "bound run artifact changed before pre-control discard", {
        relativePath: reference.relativePath,
      });
  }
  try {
    return { file, value: JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")) };
  } catch (error) {
    Common.fail("material_shop_pre_control_discard_artifact_invalid", phase, error.message);
  }
}

function operationProjection(entry) {
  return { name: entry.name, bytes: entry.bytes, sha256: entry.sha256,
    kind: entry.kind, lease: JSON.parse(JSON.stringify(entry.lease)) };
}

function expectedLiveHistory(receipt, runDir, sourceHistory) {
  const history = (sourceHistory || RunOperationLease.historyMarkers(runDir))
    .filter((entry) => entry.lease.mode === "live_execution")
    .map(operationProjection);
  if (history.length !== 1) {
    Common.fail("material_shop_pre_control_discard_live_history_invalid",
      "pre_control_discard",
      "pre-control discard requires exactly one receipt-bound live terminal", {
        historyCount: history.length,
      });
  }
  const entry = history[0];
  const terminal = receipt.operationTerminal;
  if (entry.kind !== "terminal" || entry.name !== terminal.archiveName
      || entry.bytes !== terminal.archiveBytes || entry.sha256 !== terminal.archiveSha256
      || Evidence.canonicalJson(entry.lease)
        !== Evidence.canonicalJson(receipt.operationLease)) {
    Common.fail("material_shop_pre_control_discard_live_history_invalid",
      "pre_control_discard",
      "live operation history differs from the exact pre-control cleanup receipt");
  }
  return entry;
}

function admissibleHistory(context) {
  const histories = RunOperationLease.historyMarkers(context.preparation.runDir);
  const live = expectedLiveHistory(context.failureReceipt.value,
    context.preparation.runDir, histories);
  const foreign = histories.filter((entry) => entry.lease.mode !== "live_execution"
    && (entry.lease.mode !== "built_only_discard"
      || entry.lease.preparationSha256 !== context.preparation.preparationSha256
      || entry.lease.buildSha256 !== context.build.buildSha256));
  if (histories.filter((entry) => entry.lease.mode === "live_execution").length !== 1
      || foreign.length !== 0) {
    Common.fail("material_shop_pre_control_discard_operation_invalid",
      "pre_control_discard",
      "pre-control discard operation history is foreign or has multiple live owners");
  }
  return { histories, live };
}

function readFailureReceipt(preparation, build, plan, applicability) {
  const receiptPath = path.join(preparation.runDir, LiveRun.PRE_CONTROL_FAILURE_RECEIPT_NAME);
  const file = Evidence.readExactRegularFile(receiptPath, {
    phase: "pre_control_discard", maximumBytes: 128 * 1024 * 1024,
  });
  let value;
  try { value = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_pre_control_discard_receipt_invalid",
      "pre_control_discard", error.message);
  }
  LiveRun.validatePreControlFailureCleanupReceipt(value, {
    runDir: preparation.runDir,
  });
  if (value.runId !== preparation.runId
      || value.preparationSha256 !== preparation.preparationSha256
      || value.buildSha256 !== build.buildSha256
      || value.planSha256 !== plan.planSha256
      || value.targetSlot !== preparation.slots.targetSlot
      || value.itemName !== applicability.selectedUnlockedTarget.itemName
      || value.sideEffects.controlCount !== 0
      || value.sideEffects.rawPresent !== false
      || value.sideEffects.evidencePresent !== false
      || value.sideEffects.releasePresent !== false
      || value.sideEffects.recoveryBlockerCount !== 0) {
    Common.fail("material_shop_pre_control_discard_receipt_invalid",
      "pre_control_discard",
      "pre-control cleanup receipt is detached from preparation/build/route or claims side effects");
  }
  return { value, file, path: receiptPath };
}

function exactResumeMarkerInventory(runDir, state) {
  const resumeNamePattern = new RegExp("^" + RESUME_PREFIX
    + "[0-9]{4}-[a-f0-9]{16}\\.json$");
  const resumeNames = fs.readdirSync(runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && resumeNamePattern.test(entry.name))
    .map((entry) => entry.name).sort();
  if (!state || !state.intent) {
    if (resumeNames.length !== 0) {
      Common.fail("material_shop_pre_control_discard_resume_invalid",
        "pre_control_discard",
        "a fresh pre-control discard cannot inherit a foreign resume marker");
    }
  } else {
    const validatedNames = loadResumeMarkers(state.intent).map((entry) => entry.name);
    if (Evidence.canonicalJson(resumeNames) !== Evidence.canonicalJson(validatedNames)) {
      Common.fail("material_shop_pre_control_discard_resume_invalid",
        "pre_control_discard", "resume marker inventory is incomplete or foreign");
    }
  }
  return resumeNames;
}

function exactRunArtifactInventory(context, state) {
  const receipt = context.failureReceipt.value;
  const creation = context.creation;
  const producer = Materialize.readMaterializationProducer(
    context.preparation.runDir, creation.intent);
  const allowed = Object.values(context.preparation.artifacts)
    .map((entry) => entry.relativePath)
    .concat(["preparation.json", "candidate-build.json",
      LiveRun.PRE_CONTROL_FAILURE_RECEIPT_NAME, "passive-transcript.jsonl",
      receipt.baselineSaveState.relativePath, creation.markerName, producer.name])
    .concat(receipt.controlSurface.files.map((entry) => entry.relativePath));
  if (producer.kind === "stale_recovery") {
    allowed.push(Materialize.PREPARATION_FINALIZATION_NAME);
  }
  const excluded = new Set([RunOperationLease.LEASE_NAME,
    state && state.markerName].filter(Boolean));
  const operationName = /^(?:run-operation-terminal-|run-operation-stale-resolved-)[a-f0-9]{16}\.json$/;
  const resumeNamePattern = new RegExp("^" + RESUME_PREFIX
    + "[0-9]{4}-[a-f0-9]{16}\\.json$");
  exactResumeMarkerInventory(context.preparation.runDir, state);
  const files = Materialize.collectDestinationFiles(context.preparation.runDir)
    .filter((entry) => !excluded.has(entry.relativePath)
      && !operationName.test(entry.relativePath)
      && !resumeNamePattern.test(entry.relativePath));
  const actual = files.map((entry) => entry.relativePath).sort();
  const expected = Array.from(new Set(allowed)).sort();
  if (Evidence.canonicalJson(actual) !== Evidence.canonicalJson(expected)) {
    Common.fail("material_shop_pre_control_discard_run_inventory_invalid",
      "pre_control_discard",
      "pre-control discard found a raw/control/recovery/foreign or missing run artifact", {
        actual, expected,
      });
  }
  const forbidden = actual.filter((name) => /(?:raw-candidate-journey|journey-evidence|release|acceptance|recovery-blocker|clone-release-intent)/i.test(name));
  if (forbidden.length !== 0) {
    Common.fail("material_shop_pre_control_discard_run_inventory_invalid",
      "pre_control_discard", "authority or recovery artifacts forbid pre-control discard", {
        forbidden,
      });
  }
  return { files, filesSha256: Materialize.filesDigest(files) };
}

function lockProjection(root, slot) {
  const value = CloneGuard.inspectCloneLock({ root, slot });
  if (value.lockPresent !== false || value.recoveryPresent !== false) {
    Common.fail("material_shop_pre_control_discard_clone_active", "pre_control_discard",
      "pre-control discard requires absent clone lock and recovery record", {
        slot, lockPresent: value.lockPresent, recoveryPresent: value.recoveryPresent,
      });
  }
  return { slot, lockPresent: false, recoveryPresent: false };
}

function operationBinding(context) {
  const current = RunOperationLease.readLease(context.preparation.runDir);
  if (!current.active || current.lease.mode !== "built_only_discard"
      || current.lease.preparationSha256 !== context.preparation.preparationSha256
      || current.lease.buildSha256 !== context.build.buildSha256) {
    Common.fail("material_shop_pre_control_discard_operation_invalid",
      "pre_control_discard", "destructive probe lacks its exact built-only operation lease");
  }
  const admitted = admissibleHistory(context);
  const histories = admitted.histories;
  const live = admitted.live;
  const value = { lease: JSON.parse(JSON.stringify(current.lease)),
    leaseArtifact: { bytes: current.artifact.bytes, sha256: current.artifact.sha256 },
    liveHistory: live,
    preexistingHistory: histories.map(operationProjection) };
  value.operationSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function safetyProbe(value) {
  return { runArtifacts: value.runArtifacts,
    postBuildScope: value.postBuildScope, slots: value.slots,
    targetSetSha256: value.targetSetSha256,
    targetArtifactsSha256: value.targetArtifactsSha256,
    materializationSha256: value.materializationSha256,
    buildSha256: value.buildSha256, candidateRoot: value.candidateRoot,
    gitWorktreeIdentitySha256: value.gitWorktreeIdentitySha256,
    failureReceiptSha256: value.failureReceiptSha256 };
}

function stableProbe(value) {
  return Object.assign(safetyProbe(value), { operation: value.operation });
}

function captureSafetyProbe(context, state) {
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  const postBuild = Materialize.verifyPostBuildProtectedScope(
    context.preparation.resourcesRoot, context.closure.scope,
    Build.protectedScopeOptions(context.preparation, context.build.candidateRoot));
  const slots = [context.preparation.slots.seedSlot,
    context.preparation.slots.targetSlot,
    context.preparation.slots.recoverySlot].map((slot) =>
    lockProjection(context.preparation.resourcesRoot, slot));
  const target = CloneGuard.captureSlotArtifactSet({
    root: context.preparation.resourcesRoot, appData: process.env.APPDATA,
    slot: context.preparation.slots.targetSlot, requireJson: true,
  });
  CloneGuard.assertArtifactSetInvariant(
    context.failureReceipt.value.cleanup.cloneRelease.targetEnd, target,
    "material_shop_pre_control_discard_target_changed");
  const value = {
    runArtifacts: exactRunArtifactInventory(context, state),
    postBuildScope: { scopeSha256: postBuild.scopeSha256,
      ignoredOutputInventorySha256: postBuild.ignoredOutputInventory.inventorySha256,
      ignoredFileCount: postBuild.ignoredOutputInventory.fileCount,
      ignoredTotalBytes: postBuild.ignoredOutputInventory.totalBytes },
    slots, targetSetSha256: target.setSha256,
    targetArtifactsSha256: Evidence.sha256Text(Evidence.canonicalJson(target.artifacts)),
    materializationSha256: context.materialization.materializationSha256,
    buildSha256: context.build.buildSha256, candidateRoot: context.build.candidateRoot,
    gitWorktreeIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(context.materialization.gitWorktree)),
    failureReceiptSha256: context.failureReceipt.value.receiptSha256,
  };
  value.safetyProbeSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function captureProbe(context, state) {
  const safety = captureSafetyProbe(context, state);
  const value = Object.assign({}, safety, { operation: operationBinding(context) });
  value.probeSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableProbe(value)));
  return value;
}

function loadStaticContext(options) {
  const preparation = DiscardBuilt.loadAnyPreparation(path.resolve(options.preparation));
  const closureArtifact = readBoundJson(preparation.runDir,
    preparation.artifacts.closure, "pre_control_discard");
  const closure = Production.verifyProductionClosure(closureArtifact.value, {
    currentTree: false,
  });
  const materialization = readBoundJson(preparation.runDir,
    preparation.artifacts.materialization, "pre_control_discard").value;
  Materialize.verifyMaterialization(materialization, closure.scope, {
    ownedBase: materialization.ownedBase, fixtureMode: false, allowBuildOutputs: true,
  });
  const build = DiscardBuilt.loadAnyBuild(path.resolve(options.build), preparation, closure);
  const creation = Materialize.loadCreationState(preparation.runDir);
  if (!creation.materialized || !samePath(creation.intent.destination,
    preparation.resourcesRoot)) {
    Common.fail("material_shop_pre_control_discard_materialization_invalid",
      "pre_control_discard", "discard requires one resolved exact materialization");
  }
  const plan = Protocol.validateControlPlan(readBoundJson(preparation.runDir,
    preparation.artifacts.plan, "pre_control_discard").value);
  const applicability = Applicability.validateApplicability(readBoundJson(preparation.runDir,
    preparation.artifacts.applicability, "pre_control_discard").value);
  const failureReceipt = readFailureReceipt(preparation, build, plan, applicability);
  return { preparation, closure, materialization, build, creation,
    plan, applicability, failureReceipt };
}

function loadContext(options, state, staticValue) {
  const context = staticValue || loadStaticContext(options);
  context.probe = captureProbe(context, state || { markerName: null });
  return context;
}

function resolvedName(intent) {
  return RESOLVED_PREFIX + intent.intentSha256.slice(0, 16) + ".json";
}

function validateOperationHistoryEntry(entry, runDir, preparationSha256, buildSha256) {
  Common.exactKeys(entry, ["name", "bytes", "sha256", "kind", "lease"],
    "material_shop_pre_control_discard_operation_invalid", "pre_control_discard");
  RunOperationLease.validateLease(entry.lease, runDir);
  const expectedName = entry.kind === "terminal"
    ? RunOperationLease.terminalName(entry.lease)
    : entry.kind === "stale_recovery" ? RunOperationLease.resolvedName(entry.lease) : null;
  if (!expectedName || entry.name !== expectedName
      || !Number.isSafeInteger(entry.bytes) || entry.bytes < 1
      || !Common.SHA256_RE.test(String(entry.sha256 || ""))
      || entry.lease.preparationSha256 !== preparationSha256
      || entry.lease.buildSha256 !== buildSha256) {
    Common.fail("material_shop_pre_control_discard_operation_invalid",
      "pre_control_discard", "operation history entry is malformed or foreign");
  }
  return entry;
}

function validateOperationBinding(value, runDir, preparationSha256, buildSha256) {
  Common.exactKeys(value, ["lease", "leaseArtifact", "liveHistory",
    "preexistingHistory", "operationSha256"],
    "material_shop_pre_control_discard_operation_invalid", "pre_control_discard");
  RunOperationLease.validateLease(value.lease, runDir);
  Common.exactKeys(value.leaseArtifact, ["bytes", "sha256"],
    "material_shop_pre_control_discard_operation_invalid", "pre_control_discard");
  Common.exactKeys(value.liveHistory, ["name", "bytes", "sha256", "kind", "lease"],
    "material_shop_pre_control_discard_operation_invalid", "pre_control_discard");
  validateOperationHistoryEntry(value.liveHistory, runDir,
    preparationSha256, buildSha256);
  const historiesValid = Array.isArray(value.preexistingHistory)
    && value.preexistingHistory.length >= 1
    && value.preexistingHistory.every((entry, index) => {
      validateOperationHistoryEntry(entry, runDir, preparationSha256, buildSha256);
      return index === 0 || value.preexistingHistory[index - 1].name
        .localeCompare(entry.name) < 0;
    });
  if (value.lease.mode !== "built_only_discard"
      || value.lease.preparationSha256 !== preparationSha256
      || value.lease.buildSha256 !== buildSha256
      || !Number.isSafeInteger(value.leaseArtifact.bytes) || value.leaseArtifact.bytes < 1
      || !Common.SHA256_RE.test(String(value.leaseArtifact.sha256 || ""))
      || value.liveHistory.kind !== "terminal"
      || value.liveHistory.lease.mode !== "live_execution"
      || value.liveHistory.lease.preparationSha256 !== preparationSha256
      || value.liveHistory.lease.buildSha256 !== buildSha256
      || value.liveHistory.name !== RunOperationLease.terminalName(value.liveHistory.lease)
      || value.liveHistory.bytes < 1
      || !Common.SHA256_RE.test(String(value.liveHistory.sha256 || ""))
      || !historiesValid
      || value.preexistingHistory.filter((entry) =>
        entry.lease.mode === "live_execution").length !== 1
      || !value.preexistingHistory.some((entry) =>
        Evidence.canonicalJson(entry) === Evidence.canonicalJson(value.liveHistory))
      || value.preexistingHistory.some((entry) =>
        entry.lease.leaseSha256 === value.lease.leaseSha256)
      || value.operationSha256 !== digestWithout(value, "operationSha256")) {
    Common.fail("material_shop_pre_control_discard_operation_invalid",
      "pre_control_discard", "discard operation binding is malformed, foreign, or widened");
  }
  return value;
}

function markerNames(runDir) {
  return fs.readdirSync(runDir, { withFileTypes: true }).filter((entry) => entry.isFile()
    && (entry.name === INTENT_NAME
      || new RegExp("^" + RESOLVED_PREFIX + "[a-f0-9]{16}\\.json$").test(entry.name)))
    .map((entry) => entry.name).sort();
}

function validateIntent(value) {
  Common.exactKeys(value, ["schema", "createdAt", "runId", "canonicalRoot", "runDir",
    "destination", "preparationSha256", "materializationSha256", "closureSha256",
    "scopeSha256", "buildSha256", "candidateRoot", "failureReceiptSha256",
    "probeSha256", "safetyProbe", "safetyProbeSha256", "runArtifacts", "operation",
    "head", "commonDir", "command",
    "acknowledgedPreControlFailureDiscard", "intentSha256"],
  "material_shop_pre_control_discard_intent_invalid", "pre_control_discard");
  const base = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const filesValid = Array.isArray(value.runArtifacts) && value.runArtifacts.length > 0
    && value.runArtifacts.every((entry, index) => entry
      && Common.normalizeRelative(entry.relativePath) === entry.relativePath
      && Number.isSafeInteger(entry.bytes) && entry.bytes >= 0
      && Common.SHA256_RE.test(String(entry.sha256 || ""))
      && (index === 0 || value.runArtifacts[index - 1].relativePath
        .localeCompare(entry.relativePath) < 0));
  let operationValid = true;
  try {
    validateOperationBinding(value.operation, value.runDir,
      value.preparationSha256, value.buildSha256);
  } catch (_error) { operationValid = false; }
  if (value.schema !== INTENT_SCHEMA || !Number.isFinite(Date.parse(value.createdAt))
      || !Common.ID_RE.test(String(value.runId || ""))
      || !samePath(value.canonicalRoot, Common.CANONICAL_ROOT)
      || !samePath(value.runDir, path.join(base, "runs", value.runId))
      || !samePath(value.destination, path.join(base, Materialize.MATERIALIZED_DIRECTORY,
        value.runId, "resources"))
      || !samePath(value.candidateRoot, path.join(value.destination,
        "tmp", "runtime-candidates", "v2", Build.CANDIDATE_LEAF))
      || [value.preparationSha256, value.materializationSha256, value.closureSha256,
        value.scopeSha256, value.buildSha256, value.failureReceiptSha256,
        value.probeSha256, value.safetyProbeSha256].some((digest) =>
        !Common.SHA256_RE.test(String(digest || "")))
      || !value.safetyProbe
      || value.safetyProbeSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(value.safetyProbe))
      || value.probeSha256 !== Evidence.sha256Text(Evidence.canonicalJson(
        Object.assign({}, value.safetyProbe, { operation: value.operation })))
      || !value.safetyProbe.runArtifacts
      || Evidence.canonicalJson(value.runArtifacts)
        !== Evidence.canonicalJson(value.safetyProbe.runArtifacts.files)
      || value.safetyProbe.materializationSha256 !== value.materializationSha256
      || value.safetyProbe.buildSha256 !== value.buildSha256
      || !samePath(value.safetyProbe.candidateRoot, value.candidateRoot)
      || value.safetyProbe.failureReceiptSha256 !== value.failureReceiptSha256
      || !filesValid || !operationValid
      || !Common.GIT_OID_RE.test(String(value.head || ""))
      || typeof value.commonDir !== "string"
      || value.command !== "git worktree remove --force"
      || value.acknowledgedPreControlFailureDiscard !== true
      || value.intentSha256 !== digestWithout(value, "intentSha256")) {
    Common.fail("material_shop_pre_control_discard_intent_invalid", "pre_control_discard",
      "pre-control discard intent is malformed, foreign, or widened");
  }
  return value;
}

function createIntent(context, createdAt) {
  const value = { schema: INTENT_SCHEMA, createdAt: createdAt || new Date().toISOString(),
    runId: context.preparation.runId, canonicalRoot: Common.CANONICAL_ROOT,
    runDir: context.preparation.runDir, destination: context.preparation.resourcesRoot,
    preparationSha256: context.preparation.preparationSha256,
    materializationSha256: context.materialization.materializationSha256,
    closureSha256: context.closure.closureSha256,
    scopeSha256: context.closure.scope.scopeSha256,
    buildSha256: context.build.buildSha256,
    candidateRoot: context.build.candidateRoot,
    failureReceiptSha256: context.failureReceipt.value.receiptSha256,
    probeSha256: context.probe.probeSha256,
    safetyProbe: safetyProbe(context.probe),
    safetyProbeSha256: context.probe.safetyProbeSha256,
    runArtifacts: context.probe.runArtifacts.files.map((entry) => Object.assign({}, entry)),
    operation: JSON.parse(JSON.stringify(context.probe.operation)),
    head: context.materialization.gitWorktree.head,
    commonDir: context.materialization.gitWorktree.commonDir,
    command: "git worktree remove --force",
    acknowledgedPreControlFailureDiscard: true };
  value.intentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateIntent(value);
}

function assertStaticContextMatchesIntent(context, state, currentSafety) {
  const intent = state && state.intent;
  if (!intent || !state.active
      || context.preparation.runId !== intent.runId
      || !samePath(context.preparation.runDir, intent.runDir)
      || !samePath(context.preparation.resourcesRoot, intent.destination)
      || context.preparation.preparationSha256 !== intent.preparationSha256
      || context.materialization.materializationSha256 !== intent.materializationSha256
      || context.closure.closureSha256 !== intent.closureSha256
      || context.closure.scope.scopeSha256 !== intent.scopeSha256
      || context.build.buildSha256 !== intent.buildSha256
      || !samePath(context.build.candidateRoot, intent.candidateRoot)
      || context.failureReceipt.value.receiptSha256 !== intent.failureReceiptSha256
      || context.materialization.gitWorktree.head !== intent.head
      || !samePath(context.materialization.gitWorktree.commonDir, intent.commonDir)
      || currentSafety.safetyProbeSha256 !== intent.safetyProbeSha256
      || Evidence.canonicalJson(safetyProbe(currentSafety))
        !== Evidence.canonicalJson(intent.safetyProbe)
      || Evidence.canonicalJson(currentSafety.runArtifacts.files)
        !== Evidence.canonicalJson(intent.runArtifacts)) {
    Common.fail("material_shop_pre_control_discard_resume_binding_invalid",
      "pre_control_discard",
      "active removal intent differs from the fully replayed preparation, build, receipt, or safety probe");
  }
  return intent;
}

function loadState(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "pre_control_discard");
  const names = markerNames(runDir);
  if (names.length > 1) Common.fail("material_shop_pre_control_discard_state_invalid",
    "pre_control_discard", "multiple pre-control discard markers coexist");
  if (names.length === 0) return { runDir, intent: null, active: false, markerName: null };
  const markerName = names[0];
  const markerPath = path.join(runDir, markerName);
  const intent = validateIntent(Prepare.readJson(markerPath, "pre_control_discard"));
  if (!samePath(intent.runDir, runDir)
      || markerName !== INTENT_NAME && markerName !== resolvedName(intent)) {
    Common.fail("material_shop_pre_control_discard_state_invalid", "pre_control_discard",
      "pre-control discard marker is foreign or misnamed");
  }
  return { runDir, intent, active: markerName === INTENT_NAME,
    markerName, markerPath, resolvedPath: path.join(runDir, resolvedName(intent)) };
}

function resumeName(sequence, lease) {
  return RESUME_PREFIX + String(sequence).padStart(4, "0") + "-"
    + lease.leaseSha256.slice(0, 16) + ".json";
}

function validateResumeMarker(value, intent) {
  Common.exactKeys(value, ["schema", "createdAt", "sequence", "runId",
    "intentSha256", "operation", "markerSha256"],
  "material_shop_pre_control_discard_resume_invalid", "pre_control_discard");
  if (value.schema !== RESUME_SCHEMA || !Number.isFinite(Date.parse(value.createdAt))
      || !Number.isInteger(value.sequence) || value.sequence < 1 || value.sequence > 9999
      || value.runId !== intent.runId || value.intentSha256 !== intent.intentSha256
      || value.markerSha256 !== digestWithout(value, "markerSha256")) {
    Common.fail("material_shop_pre_control_discard_resume_invalid",
      "pre_control_discard", "resume marker is malformed or detached from removal intent");
  }
  validateOperationBinding(value.operation, intent.runDir,
    intent.preparationSha256, intent.buildSha256);
  return value;
}

function loadResumeMarkers(intent) {
  const matcher = new RegExp("^" + RESUME_PREFIX + "([0-9]{4})-([a-f0-9]{16})\\.json$");
  return fs.readdirSync(intent.runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && matcher.test(entry.name))
    .map((entry) => {
      const match = matcher.exec(entry.name);
      const file = Evidence.readExactRegularFile(path.join(intent.runDir, entry.name), {
        phase: "pre_control_discard", maximumBytes: 1024 * 1024,
      });
      let value;
      try { value = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
      catch (error) {
        Common.fail("material_shop_pre_control_discard_resume_invalid",
          "pre_control_discard", error.message);
      }
      validateResumeMarker(value, intent);
      if (Number(match[1]) !== value.sequence
          || match[2] !== value.operation.lease.leaseSha256.slice(0, 16)) {
        Common.fail("material_shop_pre_control_discard_resume_invalid",
          "pre_control_discard", "resume marker name differs from its sequence/lease");
      }
      return { name: entry.name, bytes: file.length, sha256: file.sha256, value };
    }).sort((left, right) => left.value.sequence - right.value.sequence);
}

function bindResumeMarkerArtifact(intent, marker) {
  const name = resumeName(marker.sequence, marker.operation.lease);
  const matches = loadResumeMarkers(intent).filter((entry) => entry.name === name);
  if (matches.length !== 1
      || Evidence.canonicalJson(matches[0].value) !== Evidence.canonicalJson(marker)) {
    Common.fail("material_shop_pre_control_discard_resume_invalid",
      "pre_control_discard", "durable resume marker differs from the created exact marker");
  }
  return { name, bytes: matches[0].bytes, sha256: matches[0].sha256,
    markerSha256: matches[0].value.markerSha256 };
}

function assertResumeMarkerArtifact(intent, marker, expected) {
  const current = bindResumeMarkerArtifact(intent, marker);
  if (Evidence.canonicalJson(current) !== Evidence.canonicalJson(expected)) {
    Common.fail("material_shop_pre_control_discard_resume_invalid",
      "pre_control_discard", "resume marker bytes changed across the destructive fence");
  }
  return current;
}

function operationOutcome(binding, histories) {
  const matches = histories.filter((entry) =>
    entry.lease.leaseSha256 === binding.lease.leaseSha256);
  if (matches.length !== 1
      || Evidence.canonicalJson(matches[0].lease) !== Evidence.canonicalJson(binding.lease)
      || matches[0].bytes !== binding.leaseArtifact.bytes
      || matches[0].sha256 !== binding.leaseArtifact.sha256
      || ![RunOperationLease.terminalName(binding.lease),
        RunOperationLease.resolvedName(binding.lease)].includes(matches[0].name)) {
    Common.fail("material_shop_pre_control_discard_operation_invalid",
      "pre_control_discard", "attempt outcome differs from its sealed operation lease");
  }
  return matches[0];
}

function historyIncludes(history, expected) {
  return expected.every((entry) => history.some((actual) =>
    Evidence.canonicalJson(actual) === Evidence.canonicalJson(entry)));
}

function assertResumeHistory(intent, options) {
  const settings = options || {};
  const histories = RunOperationLease.historyMarkers(intent.runDir).map(operationProjection);
  if (histories.filter((entry) => entry.lease.mode === "live_execution").length !== 1
      || !historyIncludes(histories, intent.operation.preexistingHistory)) {
    Common.fail("material_shop_pre_control_discard_operation_invalid",
      "pre_control_discard", "operation history lost the intent-sealed live/prior chain");
  }
  let binding = intent.operation;
  let expected = binding.preexistingHistory.concat(operationOutcome(binding, histories));
  const markers = loadResumeMarkers(intent);
  markers.forEach((marker, index) => {
    if (marker.value.sequence !== index + 1
        || !historyIncludes(marker.value.operation.preexistingHistory, expected)
        || !historyIncludes(histories, marker.value.operation.preexistingHistory)) {
      Common.fail("material_shop_pre_control_discard_resume_invalid",
        "pre_control_discard", "resume marker does not append to the prior exact outcome chain");
    }
    binding = marker.value.operation;
    expected = binding.preexistingHistory.concat(operationOutcome(binding, histories));
  });
  const extra = histories.filter((entry) => !expected.some((item) =>
    Evidence.canonicalJson(item) === Evidence.canonicalJson(entry)));
  if (extra.some((entry) => entry.lease.mode !== "built_only_discard"
      || entry.lease.preparationSha256 !== intent.preparationSha256
      || entry.lease.buildSha256 !== intent.buildSha256)
      || settings.requireClosed === true && extra.length !== 0) {
    Common.fail("material_shop_pre_control_discard_operation_invalid",
      "pre_control_discard", "operation history contains an unsealed foreign or late outcome");
  }
  return { histories, markers, binding, expected, extra };
}

function createResumeMarker(intent, operation, sequence, createdAt) {
  const value = { schema: RESUME_SCHEMA, createdAt: createdAt || new Date().toISOString(),
    sequence, runId: intent.runId, intentSha256: intent.intentSha256,
    operation: JSON.parse(JSON.stringify(operation)) };
  value.markerSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateResumeMarker(value, intent);
}

function operationClosure(intent) {
  const active = RunOperationLease.readLease(intent.runDir);
  if (active.active) Common.fail("material_shop_run_operation_busy", "pre_control_discard",
    "pre-control discard finalization requires an inactive operation lease");
  const chain = assertResumeHistory(intent, { requireClosed: true });
  const outcome = operationOutcome(chain.binding, chain.histories);
  const resumeMarkers = chain.markers.map((entry) => ({ name: entry.name,
      bytes: entry.bytes, sha256: entry.sha256,
      markerSha256: entry.value.markerSha256 }));
  return { live: intent.operation.liveHistory, outcome,
    history: chain.histories, resumeMarkers,
    resumeMarkersSha256: Evidence.sha256Text(Evidence.canonicalJson(resumeMarkers)),
    historySha256: Evidence.sha256Text(Evidence.canonicalJson(chain.histories)) };
}

function staticInventoryFromIntent(state, closure) {
  const all = Materialize.collectDestinationFiles(state.runDir);
  const excluded = new Set([state.markerName, RECEIPT_NAME,
    closure.live.name, closure.outcome.name].filter(Boolean));
  closure.history.forEach((entry) => excluded.add(entry.name));
  closure.resumeMarkers.forEach((entry) => excluded.add(entry.name));
  const actual = all.filter((entry) => !excluded.has(entry.relativePath));
  if (Evidence.canonicalJson(actual) !== Evidence.canonicalJson(state.intent.runArtifacts)) {
    Common.fail("material_shop_pre_control_discard_run_inventory_invalid",
      "pre_control_discard", "sealed run artifacts changed before finalization");
  }
  return actual;
}

function receiptFromIntent(intent, closure, completedAt) {
  const value = { schema: RECEIPT_SCHEMA, startedAt: intent.createdAt,
    completedAt: completedAt || new Date().toISOString(), runId: intent.runId,
    destination: intent.destination, preparationSha256: intent.preparationSha256,
    materializationSha256: intent.materializationSha256,
    closureSha256: intent.closureSha256, scopeSha256: intent.scopeSha256,
    buildSha256: intent.buildSha256, candidateRoot: intent.candidateRoot,
    failureReceiptSha256: intent.failureReceiptSha256,
    removalIntentSha256: intent.intentSha256,
    operationOutcomeName: closure.outcome.name,
    operationOutcomeSha256: closure.outcome.sha256,
    operationHistorySha256: closure.historySha256,
    resumeMarkersSha256: closure.resumeMarkersSha256,
    command: intent.command, candidateExecuted: true, controlIssued: false,
    authorityMutationPossible: false, worktreeRemoved: true,
    acknowledgedPreControlFailureDiscard: true };
  value.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateReceipt(value, intent, closure);
}

function validateReceipt(value, intent, closureValue) {
  Common.exactKeys(value, ["schema", "startedAt", "completedAt", "runId",
    "destination", "preparationSha256", "materializationSha256", "closureSha256",
    "scopeSha256", "buildSha256", "candidateRoot", "failureReceiptSha256",
    "removalIntentSha256", "operationOutcomeName", "operationOutcomeSha256",
    "operationHistorySha256", "resumeMarkersSha256", "command",
    "candidateExecuted", "controlIssued",
    "authorityMutationPossible", "worktreeRemoved",
    "acknowledgedPreControlFailureDiscard", "receiptSha256"],
  "material_shop_pre_control_discard_receipt_invalid", "pre_control_discard");
  const closure = closureValue || operationClosure(intent);
  if (value.schema !== RECEIPT_SCHEMA || value.startedAt !== intent.createdAt
      || !Number.isFinite(Date.parse(value.completedAt))
      || Date.parse(value.completedAt) < Date.parse(intent.createdAt)
      || value.runId !== intent.runId || !samePath(value.destination, intent.destination)
      || value.preparationSha256 !== intent.preparationSha256
      || value.materializationSha256 !== intent.materializationSha256
      || value.closureSha256 !== intent.closureSha256
      || value.scopeSha256 !== intent.scopeSha256 || value.buildSha256 !== intent.buildSha256
      || !samePath(value.candidateRoot, intent.candidateRoot)
      || value.failureReceiptSha256 !== intent.failureReceiptSha256
      || value.removalIntentSha256 !== intent.intentSha256
      || value.operationOutcomeName !== closure.outcome.name
      || value.operationOutcomeSha256 !== closure.outcome.sha256
      || value.operationHistorySha256 !== closure.historySha256
      || value.resumeMarkersSha256 !== closure.resumeMarkersSha256
      || value.command !== intent.command || value.candidateExecuted !== true
      || value.controlIssued !== false || value.authorityMutationPossible !== false
      || value.worktreeRemoved !== true
      || value.acknowledgedPreControlFailureDiscard !== true
      || value.receiptSha256 !== digestWithout(value, "receiptSha256")) {
    Common.fail("material_shop_pre_control_discard_receipt_invalid",
      "pre_control_discard", "pre-control discard receipt is malformed or detached");
  }
  return value;
}

function removeWorktree(destination) {
  const result = childProcess.spawnSync("git", ["-C", Common.CANONICAL_ROOT,
    "worktree", "remove", "--force", destination], {
    encoding: "utf8", windowsHide: true, maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    Common.fail("material_shop_pre_control_discard_remove_failed", "pre_control_discard",
      "exact pre-control worktree removal failed", { status: result.status,
        stderr: String(result.stderr || result.error && result.error.message || "").slice(0, 4000) });
  }
}

function assertPresentWorktree(destination) {
  const present = fs.existsSync(destination);
  const listed = Materialize.worktreeListed(Common.CANONICAL_ROOT, destination);
  if (present !== listed) {
    Common.fail("material_shop_pre_control_discard_split_state", "pre_control_discard",
      "worktree filesystem/Git state is split before exact removal", { present, listed });
  }
  if (!present) {
    Common.fail("material_shop_pre_control_discard_remove_incomplete", "pre_control_discard",
      "worktree is already absent; use the bare receipt finalizer instead of deleting again");
  }
  return { present, listed };
}

function assertSameSafetyProbe(left, right) {
  if (left.safetyProbeSha256 !== right.safetyProbeSha256
      || Evidence.canonicalJson(safetyProbe(left))
        !== Evidence.canonicalJson(safetyProbe(right))) {
    Common.fail("material_shop_pre_control_discard_probe_drift", "pre_control_discard",
      "pre-control worktree changed across its exact destructive safety fence");
  }
}

function finalize(runDirValue) {
  const state = loadState(runDirValue);
  if (!state.intent) Common.fail("material_shop_pre_control_discard_finalize_state_invalid",
    "pre_control_discard", "finalizer requires one durable pre-control discard intent");
  if (fs.existsSync(state.intent.destination)
      || Materialize.worktreeListed(Common.CANONICAL_ROOT, state.intent.destination)) {
    Common.fail("material_shop_pre_control_discard_remove_incomplete", "pre_control_discard",
      "bare finalizer cannot remove a present worktree");
  }
  const closure = operationClosure(state.intent);
  staticInventoryFromIntent(state, closure);
  const output = path.join(state.runDir, RECEIPT_NAME);
  if (!state.active) {
    if (!fs.existsSync(output)) Common.fail("material_shop_pre_control_discard_receipt_missing",
      "pre_control_discard", "resolved discard is missing its exact receipt");
    return validateReceipt(Prepare.readJson(output, "pre_control_discard"),
      state.intent, closure);
  }
  const receipt = fs.existsSync(output)
    ? validateReceipt(Prepare.readJson(output, "pre_control_discard"), state.intent, closure)
    : receiptFromIntent(state.intent, closure);
  if (!fs.existsSync(output)) Materialize.writeJsonAtomicNew(output, receipt);
  staticInventoryFromIntent(state, closure);
  fs.renameSync(state.markerPath, state.resolvedPath);
  const replay = loadState(state.runDir);
  if (replay.active || Evidence.canonicalJson(replay.intent)
      !== Evidence.canonicalJson(state.intent)) {
    Common.fail("material_shop_pre_control_discard_finalize_state_invalid",
      "pre_control_discard", "discard marker did not become its exact resolved marker");
  }
  return validateReceipt(Prepare.readJson(output, "pre_control_discard"),
    replay.intent, operationClosure(replay.intent));
}

function executeDiscard(options, injectedRuntime, fixtureToken) {
  const settings = options || {};
  if (settings.acknowledge !== true) {
    Common.fail("material_shop_pre_control_discard_ack_required", "pre_control_discard",
      "pre-control failure discard requires explicit acknowledgement");
  }
  const paths = { preparation: path.resolve(settings.preparation || ""),
    build: path.resolve(settings.build || "") };
  if (injectedRuntime && fixtureToken !== FIXTURE_RUNTIME_TOKEN) {
    Common.fail("material_shop_pre_control_discard_fixture_forbidden",
      "pre_control_discard", "only the closed offline fixture entry may inject runtime seams");
  }
  const runtime = Object.assign({ loadStaticContext, captureSafetyProbe, loadContext,
    removeWorktree, finalize }, injectedRuntime || {});

  // Mandatory cleanup receipt, preparation/build envelopes, protected scope, save baseline,
  // and current no-process/no-clone state are replayed before any operation-lease mutation.
  const staticContext = runtime.loadStaticContext(paths);
  if (injectedRuntime && (!/^pre-control-discard-fixture-[a-z0-9-]+$/.test(
    staticContext.preparation.runId)
      || !samePath(staticContext.preparation.runDir, path.join(Common.CANONICAL_ROOT,
        Common.OWNED_BASE_RELATIVE, "runs", staticContext.preparation.runId))
      || !samePath(staticContext.preparation.resourcesRoot,
        path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
          Materialize.MATERIALIZED_DIRECTORY, staticContext.preparation.runId,
          "resources")))) {
    Common.fail("material_shop_pre_control_discard_fixture_forbidden",
      "pre_control_discard", "offline fixture runtime is outside its exact owned test run");
  }
  const state = loadState(staticContext.preparation.runDir);
  const output = path.join(staticContext.preparation.runDir, RECEIPT_NAME);
  if (!state.active && state.intent) {
    Common.fail("material_shop_pre_control_discard_manual_recovery_required",
      "pre_control_discard", "resolved discard state may only use the bare finalizer");
  }
  if (fs.existsSync(output)) {
    Common.fail("material_shop_pre_control_discard_output_exists",
      "pre_control_discard", "canonical pre-control discard output already exists");
  }
  assertPresentWorktree(staticContext.preparation.resourcesRoot);
  admissibleHistory(staticContext);
  if (state.intent) {
    const active = RunOperationLease.readLease(staticContext.preparation.runDir);
    if (active.active) {
      Common.fail("material_shop_run_operation_busy", "pre_control_discard",
        "active pre-control discard intent is still owned; inspect or explicitly recover the exact stale lease", {
          mode: active.lease.mode, ownerPid: active.lease.ownerPid,
          ownerState: active.ownerState, leaseSha256: active.lease.leaseSha256,
        });
    }
    assertResumeHistory(state.intent, { requireClosed: false });
  }
  const preflightSafety = runtime.captureSafetyProbe(staticContext, state);
  if (state.intent) {
    assertStaticContextMatchesIntent(staticContext, state, preflightSafety);
  }

  const operationHandle = RunOperationLease.acquire({
    runDir: staticContext.preparation.runDir,
    runId: staticContext.preparation.runId, mode: "built_only_discard",
    preparationSha256: staticContext.preparation.preparationSha256,
    buildSha256: staticContext.build.buildSha256,
  });
  try {
    const context = runtime.loadContext(paths, state, staticContext);
    assertSameSafetyProbe(preflightSafety, context.probe);

    let intent;
    let resumeMarker = null;
    let resumeArtifact = null;
    if (!state.intent) {
      intent = createIntent(context);
      Materialize.writeJsonAtomicNew(path.join(context.preparation.runDir, INTENT_NAME), intent);
    } else {
      intent = state.intent;
      const prior = assertResumeHistory(intent, { requireClosed: false });
      if (Evidence.canonicalJson(context.probe.operation.preexistingHistory)
          !== Evidence.canonicalJson(prior.histories)) {
        Common.fail("material_shop_pre_control_discard_resume_invalid",
          "pre_control_discard",
          "resume mutex does not adopt the exact closed and append-only prior history");
      }
      resumeMarker = createResumeMarker(intent, context.probe.operation,
        prior.markers.length + 1);
      Materialize.writeJsonAtomicNew(path.join(context.preparation.runDir,
        resumeName(resumeMarker.sequence, resumeMarker.operation.lease)), resumeMarker);
      resumeArtifact = bindResumeMarkerArtifact(intent, resumeMarker);
    }

    const activeState = loadState(context.preparation.runDir);
    if (!activeState.active || activeState.intent.intentSha256 !== intent.intentSha256) {
      Common.fail("material_shop_pre_control_discard_state_invalid", "pre_control_discard",
        "durable pre-control discard intent changed before its second destructive probe");
    }
    const freshStatic = runtime.loadStaticContext(paths);
    const fresh = runtime.loadContext(paths, activeState, freshStatic);
    assertStaticContextMatchesIntent(freshStatic, activeState, fresh.probe);
    if (fresh.probe.probeSha256 !== context.probe.probeSha256
        || Evidence.canonicalJson(fresh.probe) !== Evidence.canonicalJson(context.probe)) {
      Common.fail("material_shop_pre_control_discard_probe_drift", "pre_control_discard",
        "pre-control worktree changed between two exact destructive probes");
    }
    if (resumeMarker) {
      assertResumeMarkerArtifact(intent, resumeMarker, resumeArtifact);
    }
    assertPresentWorktree(context.preparation.resourcesRoot);
    if (resumeMarker) {
      assertResumeMarkerArtifact(intent, resumeMarker, resumeArtifact);
    }
    runtime.removeWorktree(context.preparation.resourcesRoot);
    if (fs.existsSync(context.preparation.resourcesRoot)
        || Materialize.worktreeListed(Common.CANONICAL_ROOT,
          context.preparation.resourcesRoot)) {
      Common.fail("material_shop_pre_control_discard_remove_incomplete", "pre_control_discard",
        "exact worktree remained after removal");
    }
    RunOperationLease.release(operationHandle);
    return runtime.finalize(context.preparation.runDir);
  } finally {
    if (operationHandle.active) RunOperationLease.release(operationHandle);
  }
}

function discard(options) {
  return executeDiscard(options, null, null);
}

function discardFixture(options, runtime) {
  const keys = Object.keys(runtime || {}).sort();
  const expected = ["captureSafetyProbe", "finalize", "loadContext",
    "loadStaticContext", "removeWorktree"].sort();
  if (Evidence.canonicalJson(keys) !== Evidence.canonicalJson(expected)
      || keys.some((key) => typeof runtime[key] !== "function")) {
    Common.fail("material_shop_pre_control_discard_fixture_forbidden",
      "pre_control_discard", "offline fixture runtime must provide the exact closed seam set");
  }
  return executeDiscard(options, runtime, FIXTURE_RUNTIME_TOKEN);
}

function parseArgs(argv) {
  const args = { mode: null, runDir: null, preparation: null, build: null,
    acknowledge: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (["--discard-pre-control-failure",
      "--finalize-pre-control-failure-discard"].includes(argv[index])) {
      if (args.mode !== null) Common.fail(
        "material_shop_pre_control_discard_arguments_invalid", "pre_control_discard",
        "exactly one pre-control discard mode is allowed");
      args.mode = argv[index] === "--discard-pre-control-failure" ? "discard" : "finalize";
    }
    else if (argv[index] === "--run-dir") args.runDir = argv[++index];
    else if (argv[index] === "--preparation") args.preparation = argv[++index];
    else if (argv[index] === "--build") args.build = argv[++index];
    else if (argv[index] === "--acknowledge-pre-control-failure-discard") {
      args.acknowledge = true;
    } else Common.fail("material_shop_pre_control_discard_argument_unknown",
      "pre_control_discard", argv[index]);
  }
  if (args.mode === "finalize") {
    if (!args.runDir || args.preparation || args.build || args.acknowledge) {
      Common.fail("material_shop_pre_control_discard_arguments_invalid",
        "pre_control_discard", "bare finalizer accepts only one exact run directory");
    }
  } else if (args.mode !== "discard" || !args.preparation || !args.build
      || args.runDir || !args.acknowledge) {
    Common.fail("material_shop_pre_control_discard_arguments_invalid",
      "pre_control_discard",
      "discard requires exact preparation/build and explicit acknowledgement");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const value = args.mode === "finalize" ? finalize(args.runDir) : discard(args);
    process.stdout.write(JSON.stringify({ ok: true,
      status: "pre_control_failure_discarded", runId: value.runId,
      receiptSha256: value.receiptSha256 }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  INTENT_NAME,
  INTENT_SCHEMA,
  RECEIPT_NAME,
  RECEIPT_SCHEMA,
  RESUME_PREFIX,
  RESUME_SCHEMA,
  admissibleHistory,
  assertResumeHistory,
  assertResumeMarkerArtifact,
  assertSameSafetyProbe,
  assertStaticContextMatchesIntent,
  captureSafetyProbe,
  RESOLVED_PREFIX,
  captureProbe,
  createIntent,
  createResumeMarker,
  bindResumeMarkerArtifact,
  discard,
  discardFixture,
  exactResumeMarkerInventory,
  exactRunArtifactInventory,
  expectedLiveHistory,
  finalize,
  loadContext,
  loadResumeMarkers,
  loadState,
  loadStaticContext,
  operationClosure,
  operationBinding,
  removeWorktree,
  parseArgs,
  readFailureReceipt,
  receiptFromIntent,
  resumeName,
  resolvedName,
  safetyProbe,
  validateOperationBinding,
  validateResumeMarker,
  validateIntent,
  validateReceipt,
};
