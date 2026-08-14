#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const CloneGuard = require("../lib/clone-save-guard");
const LauncherObservation = require("../lib/launcher-observation");
const Build = require("./build-candidate");
const Common = require("./common");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const Production = require("./production-closure");
const RunOperationLease = require("./run-operation-lease");

const LEGACY_PREPARATION_SCHEMA = "workbench-live-e2e.material-shop.preparation.v1";
const LEGACY_BUILD_SCHEMA = "workbench-live-e2e.material-shop.candidate-build.v1";
const INTENT_SCHEMA = "workbench-live-e2e.material-shop.built-run-discard-intent.v2";
const RECEIPT_SCHEMA = "workbench-live-e2e.material-shop.built-run-discard.v2";
const INTENT_NAME = "built-run-discard-intent.json";
const RECEIPT_NAME = "built-run-discard.json";
const RESOLVED_PREFIX = "built-run-discard-resolved-";

function digestWithout(value, key) {
  const copy = Object.assign({}, value);
  delete copy[key];
  return Evidence.sha256Text(Evidence.canonicalJson(copy));
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function readBoundArtifact(runDir, reference, phase) {
  const absolute = path.resolve(runDir,
    String(reference && reference.relativePath || "").replace(/\//g, path.sep));
  if (!Evidence.pathInside(runDir, absolute)) {
    Common.fail("material_shop_built_discard_artifact_escape", phase,
      "built-only discard artifact escaped its exact run directory");
  }
  const file = Evidence.readExactRegularFile(absolute, {
    phase, maximumBytes: 128 * 1024 * 1024,
  });
  if (file.sha256 !== reference.sha256 || file.length !== reference.bytes) {
    Common.fail("material_shop_built_discard_artifact_drift", phase,
      "built-only discard artifact changed after preparation", { absolute });
  }
  try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_built_discard_artifact_invalid", phase, error.message); }
}

function legacyStablePreparation(value) {
  return { schema: value.schema, runId: value.runId, root: value.root,
    runDir: value.runDir, resourcesRoot: value.resourcesRoot,
    slots: value.slots, scopeSha256: value.scopeSha256,
    closureSha256: value.closureSha256,
    applicabilitySha256: value.applicabilitySha256,
    materializationSha256: value.materializationSha256,
    planSha256: value.planSha256, artifacts: value.artifacts,
    boundaries: value.boundaries };
}

function loadLegacyPreparation(filePath) {
  const value = Prepare.readJson(filePath, "built_discard");
  Common.exactKeys(value, ["schema", "createdAt", "runId", "root", "runDir",
    "resourcesRoot", "slots", "scopeSha256", "closureSha256", "applicabilitySha256",
    "materializationSha256", "planSha256", "artifacts", "boundaries",
    "preparationSha256"], "material_shop_built_discard_legacy_preparation_invalid",
  "built_discard");
  const expectedRunDir = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "runs", String(value.runId || ""));
  const expectedResources = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    Materialize.MATERIALIZED_DIRECTORY, String(value.runId || ""), "resources");
  if (value.schema !== LEGACY_PREPARATION_SCHEMA
      || !Common.ID_RE.test(String(value.runId || ""))
      || !samePath(value.root, Common.CANONICAL_ROOT)
      || !samePath(value.runDir, expectedRunDir)
      || !samePath(path.dirname(filePath), expectedRunDir)
      || !samePath(value.resourcesRoot, expectedResources)
      || value.preparationSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(legacyStablePreparation(value)))) {
    Common.fail("material_shop_built_discard_legacy_preparation_invalid", "built_discard",
      "legacy preparation is not the exact pre-toolchain A5 preparation");
  }
  Common.assertDedicatedSlots(value.slots.seedSlot,
    value.slots.targetSlot, value.slots.recoverySlot);
  return value;
}

function loadAnyPreparation(filePathValue) {
  const filePath = path.resolve(filePathValue);
  const raw = Prepare.readJson(filePath, "built_discard");
  if (raw.schema === Prepare.PREPARATION_SCHEMA) return Build.loadPreparation(filePath);
  if (raw.schema === LEGACY_PREPARATION_SCHEMA) return loadLegacyPreparation(filePath);
  Common.fail("material_shop_built_discard_preparation_invalid", "built_discard",
    "built-only discard accepts only current or sealed pre-toolchain A5 preparation");
}

function validateLegacyBuild(value, preparation, closure, buildPath) {
  Common.exactKeys(value, ["schema", "createdAt", "startedAt", "preparationSha256",
    "materializationSha256", "command", "candidateRoot", "candidateIdentity",
    "candidateBinding", "materializedProducerBinding", "liveAdmission", "boundaries",
    "buildSha256"], "material_shop_built_discard_legacy_build_invalid", "built_discard");
  const unsigned = Object.assign({}, value);
  delete unsigned.buildSha256;
  const expectedRoot = Build.candidateProjection(preparation).candidateRoot;
  if (value.schema !== LEGACY_BUILD_SCHEMA
      || !samePath(buildPath, path.join(preparation.runDir, "candidate-build.json"))
      || value.preparationSha256 !== preparation.preparationSha256
      || value.materializationSha256 !== preparation.materializationSha256
      || !samePath(value.candidateRoot, expectedRoot)
      || value.buildSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))
      || !value.boundaries || value.boundaries.candidateBuilt !== true
      || value.boundaries.candidateExecuted !== false || value.boundaries.e2eVerified !== false
      || value.boundaries.promoted !== false || value.boundaries.standardEntryVerified !== false) {
    Common.fail("material_shop_built_discard_legacy_build_invalid", "built_discard",
      "legacy candidate_built receipt is malformed or detached");
  }
  Build.validateExecutedCommand(value.command, preparation, "built_discard");
  Materialize.verifyPostBuildProtectedScope(preparation.resourcesRoot, closure.scope,
    Build.protectedScopeOptions(preparation, value.candidateRoot));
  const binding = Production.captureMaterializedSharedProducers(
    preparation.resourcesRoot, closure);
  Production.verifyMaterializedSharedProducers(value.materializedProducerBinding,
    preparation.resourcesRoot, closure);
  if (Evidence.canonicalJson(binding)
      !== Evidence.canonicalJson(value.materializedProducerBinding)) {
    Common.fail("material_shop_built_discard_legacy_build_invalid", "built_discard",
      "legacy build producer binding differs from the exact materialized worktree");
  }
  const producerPath = path.join(preparation.resourcesRoot, "tools", "workbench-live-e2e",
    "material-shop", "production-closure.js");
  const resolved = require.resolve(producerPath);
  if (!samePath(resolved, producerPath)) {
    Common.fail("material_shop_built_discard_legacy_build_invalid", "built_discard",
      "legacy production verifier did not resolve from the materialized worktree");
  }
  const producer = require(resolved);
  producer.verifyProductionClosure(closure, { currentTree: false });
  producer.verifyCandidateBinding(value.candidateRoot, value.candidateIdentity,
    closure, value.candidateBinding);
  return value;
}

function loadAnyBuild(filePathValue, preparation, closure) {
  const filePath = path.resolve(filePathValue);
  if (!samePath(filePath, path.join(preparation.runDir, "candidate-build.json"))) {
    Common.fail("material_shop_built_discard_build_path_invalid", "built_discard",
      "built-only discard requires the canonical candidate-build receipt path");
  }
  if (preparation.schema === Prepare.PREPARATION_SCHEMA) {
    return Build.loadBuildReceipt(filePath, preparation, closure, "built_discard");
  }
  return validateLegacyBuild(Prepare.readJson(filePath, "built_discard"),
    preparation, closure, filePath);
}

function loadAnyBuildEnvelope(filePathValue, preparation) {
  const filePath = path.resolve(filePathValue);
  if (!samePath(filePath, path.join(preparation.runDir, "candidate-build.json"))) {
    Common.fail("material_shop_built_discard_build_path_invalid", "built_discard",
      "built-only operation lease requires the canonical build receipt path");
  }
  const value = Prepare.readJson(filePath, "built_discard_operation_lease");
  const unsigned = Object.assign({}, value);
  delete unsigned.buildSha256;
  const expectedSchema = preparation.schema === Prepare.PREPARATION_SCHEMA
    ? Build.BUILD_SCHEMA : LEGACY_BUILD_SCHEMA;
  if (value.schema !== expectedSchema
      || value.preparationSha256 !== preparation.preparationSha256
      || !Common.SHA256_RE.test(String(value.buildSha256 || ""))
      || value.buildSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_built_discard_build_invalid", "built_discard",
      "built-only operation lease cannot bind a malformed build envelope");
  }
  return value;
}

function allowedRunFileNames(preparation, buildPath, creation, discardState, operationState,
  materializationProducer) {
  const names = Object.values(preparation.artifacts).map((reference) =>
    String(reference.relativePath || ""));
  names.push(path.basename(buildPath), "preparation.json",
    path.basename(creation.markerPath));
  if (materializationProducer) names.push(materializationProducer.name);
  if (discardState && discardState.active) names.push(INTENT_NAME);
  if (operationState.active) names.push(RunOperationLease.LEASE_NAME);
  operationState.history.forEach((entry) => names.push(entry.name));
  return Array.from(new Set(names)).sort();
}

function captureMaterializationProducerHistory(preparation, materialization, creation) {
  const bindingValid = creation && creation.materialized === true
    && creation.active === false && creation.cleanupResolved === false
    && creation.intent && creation.intent.runId === preparation.runId
    && samePath(creation.intent.runDir, preparation.runDir)
    && samePath(creation.intent.destination, preparation.resourcesRoot)
    && materialization && materialization.mode === Materialize.PRODUCTION_MODE
    && samePath(materialization.destination, preparation.resourcesRoot)
    && materialization.head === creation.intent.head
    && materialization.scopeSha256 === creation.intent.scopeSha256
    && materialization.scopeSha256 === preparation.scopeSha256
    && materialization.materializationSha256 === preparation.materializationSha256;
  if (!bindingValid) {
    Common.fail("material_shop_built_discard_materialization_state_invalid", "built_discard",
      "materialization producer history is detached from the validated preparation and creation context");
  }
  const producer = Materialize.readMaterializationProducer(
    preparation.runDir, creation.intent);
  // Sealed v1 preparations predate the producer marker. Current preparations must retain
  // exactly one validated inactive producer marker; readMaterializationProducer rejects
  // multiple, malformed, misnamed, or creation-detached markers before this allowance.
  if (producer.kind === "absent" && preparation.schema === LEGACY_PREPARATION_SCHEMA) {
    return null;
  }
  const expectedName = producer.kind === "terminal"
    ? Materialize.producerTerminalName(producer.lease)
    : producer.kind === "stale_recovery"
      ? Materialize.producerStaleName(producer.lease) : null;
  if (!expectedName || producer.name !== expectedName || producer.active !== false
      || !producer.artifact || !Number.isSafeInteger(producer.artifact.bytes)
      || producer.artifact.bytes < 1
      || !Common.SHA256_RE.test(String(producer.artifact.sha256 || ""))) {
    Common.fail("material_shop_built_discard_materialization_state_invalid", "built_discard",
      "built-only discard requires one exact terminal or stale-resolved materialization producer marker");
  }
  return { name: producer.name, kind: producer.kind,
    bytes: producer.artifact.bytes, sha256: producer.artifact.sha256,
    leaseSha256: producer.lease.leaseSha256 };
}

function operationHistoryProjection(entry) {
  return { name: entry.name, bytes: entry.bytes, sha256: entry.sha256,
    kind: entry.kind, lease: Object.assign({}, entry.lease) };
}

function validateOperationHistoryEntry(entry, runDir, preparationSha256, buildSha256) {
  Common.exactKeys(entry, ["name", "bytes", "sha256", "kind", "lease"],
    "material_shop_built_discard_operation_invalid", "built_discard");
  RunOperationLease.validateLease(entry.lease, runDir);
  const expectedName = entry.kind === "terminal"
    ? RunOperationLease.terminalName(entry.lease)
    : entry.kind === "stale_recovery" ? RunOperationLease.resolvedName(entry.lease) : null;
  if (!expectedName || entry.name !== expectedName
      || !Number.isSafeInteger(entry.bytes) || entry.bytes < 1
      || !Common.SHA256_RE.test(String(entry.sha256 || ""))
      || entry.lease.mode !== "built_only_discard"
      || entry.lease.preparationSha256 !== preparationSha256
      || entry.lease.buildSha256 !== buildSha256) {
    Common.fail("material_shop_built_discard_operation_invalid", "built_discard",
      "discard operation history is foreign, live, or detached from this build");
  }
  return entry;
}

function validateOperationBinding(value, runDir, preparationSha256, buildSha256) {
  Common.exactKeys(value, ["lease", "leaseArtifact", "preexistingHistory",
    "operationSha256"], "material_shop_built_discard_operation_invalid", "built_discard");
  RunOperationLease.validateLease(value.lease, runDir);
  Common.exactKeys(value.leaseArtifact, ["bytes", "sha256"],
    "material_shop_built_discard_operation_invalid", "built_discard");
  const historiesValid = Array.isArray(value.preexistingHistory)
    && value.preexistingHistory.every((entry, index) => {
      validateOperationHistoryEntry(entry, runDir, preparationSha256, buildSha256);
      return index === 0 || value.preexistingHistory[index - 1].name.localeCompare(entry.name) < 0;
    });
  const uniqueLeases = historiesValid && new Set(value.preexistingHistory.map((entry) =>
    entry.lease.leaseSha256)).size === value.preexistingHistory.length;
  if (value.lease.mode !== "built_only_discard"
      || value.lease.preparationSha256 !== preparationSha256
      || value.lease.buildSha256 !== buildSha256
      || !Number.isSafeInteger(value.leaseArtifact.bytes) || value.leaseArtifact.bytes < 1
      || !Common.SHA256_RE.test(String(value.leaseArtifact.sha256 || ""))
      || !historiesValid || !uniqueLeases
      || value.preexistingHistory.some((entry) =>
        entry.lease.leaseSha256 === value.lease.leaseSha256)
      || value.operationSha256 !== digestWithout(value, "operationSha256")) {
    Common.fail("material_shop_built_discard_operation_invalid", "built_discard",
      "discard operation lease/history binding is malformed or detached");
  }
  return value;
}

function captureDiscardOperation(runDir, preparationSha256, buildSha256) {
  const active = RunOperationLease.readLease(runDir);
  if (!active.active) {
    Common.fail("material_shop_run_operation_busy", "built_discard",
      "built-only destructive probes require their exact active operation lease");
  }
  const history = RunOperationLease.historyMarkers(runDir).map(operationHistoryProjection);
  if (history.some((entry) => entry.lease.mode === "live_execution")) {
    Common.fail("material_shop_built_discard_candidate_may_have_executed", "built_discard",
      "live-execution operation history forbids a built-never-executed discard");
  }
  const value = { lease: Object.assign({}, active.lease),
    leaseArtifact: { bytes: active.artifact.bytes, sha256: active.artifact.sha256 },
    preexistingHistory: history };
  value.operationSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateOperationBinding(value, runDir, preparationSha256, buildSha256);
}

function assertNoLiveOperationHistory(runDir) {
  if (RunOperationLease.historyMarkers(runDir).some((entry) =>
    entry.lease.mode === "live_execution")) {
    Common.fail("material_shop_built_discard_candidate_may_have_executed", "built_discard",
      "live-execution operation history forbids a built-never-executed discard");
  }
}

function captureRunArtifactInventory(preparation, buildPath, materialization, creation,
  discardState) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT,
    preparation.runDir, Common.OWNED_BASE_RELATIVE, "built_discard");
  const materializationProducer = captureMaterializationProducerHistory(
    preparation, materialization, creation);
  const buildEnvelope = loadAnyBuildEnvelope(buildPath, preparation);
  const operation = captureDiscardOperation(runDir, preparation.preparationSha256,
    buildEnvelope.buildSha256);
  const operationState = { active: true, history: operation.preexistingHistory };
  const entries = fs.readdirSync(runDir, { withFileTypes: true });
  if (entries.some((entry) => !entry.isFile())) {
    Common.fail("material_shop_built_discard_live_side_effect", "built_discard",
      "built-never-executed run directory must contain no control/capture subdirectory");
  }
  const actualNames = entries.map((entry) => entry.name).sort();
  const allowed = allowedRunFileNames(preparation, buildPath, creation, discardState,
    operationState, materializationProducer);
  if (Evidence.canonicalJson(actualNames) !== Evidence.canonicalJson(allowed)) {
    Common.fail("material_shop_built_discard_live_side_effect", "built_discard",
      "run directory contains a live/raw/recovery or foreign artifact", {
        actualNames, allowed,
      });
  }
  const excluded = new Set([INTENT_NAME, RunOperationLease.LEASE_NAME].concat(
    operationState.history.map((entry) => entry.name)));
  const files = actualNames.filter((name) => !excluded.has(name)).map((name) => {
    const file = Evidence.readExactRegularFile(path.join(runDir, name), {
      phase: "built_discard", maximumBytes: 128 * 1024 * 1024,
    });
    return { name, bytes: file.length, sha256: file.sha256 };
  });
  return { files, filesSha256: Evidence.sha256Text(Evidence.canonicalJson(files)),
    operation };
}

function emptySlotProjection(root, slot) {
  const lock = CloneGuard.inspectCloneLock({ root, slot });
  const artifacts = CloneGuard.captureSlotArtifactSet({ root, slot,
    appData: process.env.APPDATA, requireJson: false });
  if (lock.lockPresent !== false || lock.recoveryPresent !== false
      || artifacts.artifacts.length !== 0) {
    Common.fail("material_shop_built_discard_clone_side_effect", "built_discard",
      "built-never-executed discard found a clone lock, recovery, JSON, or SOL mutation", {
        slot, lockPresent: lock.lockPresent, recoveryPresent: lock.recoveryPresent,
        artifactCount: artifacts.artifacts.length,
      });
  }
  return { slot, lockPresent: false, recoveryPresent: false, artifactCount: 0 };
}

function stableProbe(value) {
  return { runArtifacts: value.runArtifacts,
    operation: value.operation,
    postBuildScope: value.postBuildScope,
    slots: value.slots,
    materializationSha256: value.materializationSha256,
    buildSha256: value.buildSha256,
    candidateRoot: value.candidateRoot,
    gitWorktreeIdentitySha256: value.gitWorktreeIdentitySha256 };
}

function loadContext(options, state) {
  const preparation = loadAnyPreparation(options.preparation);
  const closure = readBoundArtifact(preparation.runDir,
    preparation.artifacts.closure, "built_discard");
  const materialization = readBoundArtifact(preparation.runDir,
    preparation.artifacts.materialization, "built_discard");
  Materialize.verifyMaterialization(materialization, closure.scope, {
    ownedBase: materialization.ownedBase, fixtureMode: false, allowBuildOutputs: true,
  });
  const build = loadAnyBuild(options.build, preparation, closure);
  const creation = Materialize.loadCreationState(preparation.runDir);
  if (!creation.materialized || creation.active || creation.cleanupResolved
      || !samePath(creation.intent.destination, preparation.resourcesRoot)) {
    Common.fail("material_shop_built_discard_materialization_state_invalid", "built_discard",
      "built-only discard requires one resolved successful materialization marker");
  }
  const postBuild = Materialize.verifyPostBuildProtectedScope(
    preparation.resourcesRoot, closure.scope,
    Build.protectedScopeOptions(preparation, build.candidateRoot));
  const slots = [preparation.slots.seedSlot, preparation.slots.targetSlot,
    preparation.slots.recoverySlot].map((slot) =>
    emptySlotProjection(preparation.resourcesRoot, slot));
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  const runArtifacts = captureRunArtifactInventory(preparation, options.build,
    materialization, creation, state);
  const probe = { runArtifacts, operation: runArtifacts.operation,
    postBuildScope: { scopeSha256: postBuild.scopeSha256,
      ignoredOutputInventorySha256: postBuild.ignoredOutputInventory.inventorySha256,
      ignoredFileCount: postBuild.ignoredOutputInventory.fileCount,
      ignoredTotalBytes: postBuild.ignoredOutputInventory.totalBytes },
    slots, materializationSha256: materialization.materializationSha256,
    buildSha256: build.buildSha256, candidateRoot: build.candidateRoot,
    gitWorktreeIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(materialization.gitWorktree)) };
  probe.probeSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableProbe(probe)));
  return { preparation, closure, materialization, build, creation, probe };
}

function resolvedName(intent) {
  return RESOLVED_PREFIX + intent.intentSha256.slice(0, 16) + ".json";
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
    "scopeSha256", "buildSha256", "candidateRoot", "probeSha256", "runArtifacts",
    "operation", "gitWorktreeIdentitySha256", "head", "commonDir", "command",
    "acknowledgedBuiltNeverExecutedDiscard", "intentSha256"],
  "material_shop_built_discard_intent_invalid", "built_discard");
  const expectedBase = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const runArtifactsValid = Array.isArray(value.runArtifacts) && value.runArtifacts.length > 0
    && value.runArtifacts.every((entry, index) => entry
      && Evidence.canonicalJson(Object.keys(entry).sort())
        === Evidence.canonicalJson(["bytes", "name", "sha256"].sort())
      && /^[A-Za-z0-9._-]{1,160}$/.test(String(entry.name || ""))
      && entry.name !== INTENT_NAME && entry.name !== RECEIPT_NAME
      && !entry.name.startsWith(RESOLVED_PREFIX)
      && Number.isSafeInteger(entry.bytes) && entry.bytes > 0
      && Common.SHA256_RE.test(String(entry.sha256 || ""))
      && (index === 0 || value.runArtifacts[index - 1].name.localeCompare(entry.name) < 0));
  let operationValid = true;
  try {
    validateOperationBinding(value.operation, value.runDir,
      value.preparationSha256, value.buildSha256);
  } catch (error) {
    operationValid = false;
  }
  if (value.schema !== INTENT_SCHEMA || !Number.isFinite(Date.parse(value.createdAt))
      || !Common.ID_RE.test(String(value.runId || ""))
      || !samePath(value.canonicalRoot, Common.CANONICAL_ROOT)
      || !samePath(value.runDir, path.join(expectedBase, "runs", value.runId))
      || !samePath(value.destination, path.join(expectedBase,
        Materialize.MATERIALIZED_DIRECTORY, value.runId, "resources"))
      || !samePath(value.candidateRoot,
        path.join(value.destination, "tmp", "runtime-candidates", "v2", Build.CANDIDATE_LEAF))
      || [value.preparationSha256, value.materializationSha256, value.closureSha256,
        value.scopeSha256, value.buildSha256, value.probeSha256,
        value.gitWorktreeIdentitySha256].some((digest) => !Common.SHA256_RE.test(String(digest || "")))
      || !Common.GIT_OID_RE.test(String(value.head || ""))
      || typeof value.commonDir !== "string" || value.command !== "git worktree remove --force"
      || !runArtifactsValid || !operationValid
      || value.acknowledgedBuiltNeverExecutedDiscard !== true
      || value.intentSha256 !== digestWithout(value, "intentSha256")) {
    Common.fail("material_shop_built_discard_intent_invalid", "built_discard",
      "built-only discard intent is malformed, foreign, or detached");
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
    buildSha256: context.build.buildSha256, candidateRoot: context.build.candidateRoot,
    probeSha256: context.probe.probeSha256,
    runArtifacts: context.probe.runArtifacts.files.map((entry) => Object.assign({}, entry)),
    operation: JSON.parse(JSON.stringify(context.probe.operation)),
    gitWorktreeIdentitySha256: context.probe.gitWorktreeIdentitySha256,
    head: context.materialization.gitWorktree.head,
    commonDir: context.materialization.gitWorktree.commonDir,
    command: "git worktree remove --force",
    acknowledgedBuiltNeverExecutedDiscard: true };
  value.intentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateIntent(value);
}

function loadState(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "built_discard");
  const names = markerNames(runDir);
  if (names.length > 1) Common.fail("material_shop_built_discard_state_invalid",
    "built_discard", "multiple discard markers coexist", { names });
  if (names.length === 0) return { runDir, active: false, intent: null, markerPath: null };
  const markerPath = path.join(runDir, names[0]);
  const intent = validateIntent(Prepare.readJson(markerPath, "built_discard"));
  if (!samePath(runDir, intent.runDir)) {
    Common.fail("material_shop_built_discard_state_invalid", "built_discard",
      "discard marker belongs to a different exact run directory");
  }
  const resolved = resolvedName(intent);
  if (names[0] !== INTENT_NAME && names[0] !== resolved) {
    Common.fail("material_shop_built_discard_state_invalid", "built_discard",
      "resolved discard marker name differs from its sealed intent");
  }
  return { runDir, active: names[0] === INTENT_NAME, intent, markerPath,
    resolvedPath: path.join(runDir, resolved) };
}

function assertLiveExecutionAvailable(runDirValue) {
  const state = loadState(runDirValue);
  const preControlMarkers = fs.readdirSync(state.runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && (entry.name === "pre-control-failure-discard-intent.json"
      || entry.name === "pre-control-failure-discard.json"
      || /^pre-control-failure-discard-resolved-[a-f0-9]{16}\.json$/.test(entry.name)))
    .map((entry) => entry.name);
  if (state.intent || fs.existsSync(path.join(state.runDir, RECEIPT_NAME))
      || preControlMarkers.length !== 0) {
    Common.fail("material_shop_run_blocked_by_built_discard", "run_operation_lease",
      "a built-only or pre-control discard intent, resolved marker, or receipt permanently blocks live execution for this run");
  }
  return { available: true, runDir: state.runDir };
}

function receiptFromIntent(intent, operationClosure, completedAt) {
  validateIntent(intent);
  const value = { schema: RECEIPT_SCHEMA, startedAt: intent.createdAt,
    completedAt: completedAt || new Date().toISOString(), runId: intent.runId,
    destination: intent.destination, preparationSha256: intent.preparationSha256,
    materializationSha256: intent.materializationSha256,
    closureSha256: intent.closureSha256, scopeSha256: intent.scopeSha256,
    buildSha256: intent.buildSha256, candidateRoot: intent.candidateRoot,
    probeSha256: intent.probeSha256, removalIntentSha256: intent.intentSha256,
    operationLeaseSha256: intent.operation.lease.leaseSha256,
    operationOutcomeName: operationClosure.outcome.name,
    operationOutcomeKind: operationClosure.outcome.kind,
    operationOutcomeSha256: operationClosure.outcome.sha256,
    operationHistorySha256: operationClosure.historySha256,
    command: intent.command, candidateExecuted: false, rawEvidenceCreated: false,
    worktreeRemoved: true, acknowledgedBuiltNeverExecutedDiscard: true };
  value.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateReceipt(value, intent);
}

function validateReceipt(value, intent) {
  Common.exactKeys(value, ["schema", "startedAt", "completedAt", "runId", "destination",
    "preparationSha256", "materializationSha256", "closureSha256", "scopeSha256",
    "buildSha256", "candidateRoot", "probeSha256", "removalIntentSha256", "command",
    "operationLeaseSha256", "operationOutcomeName", "operationOutcomeKind",
    "operationOutcomeSha256", "operationHistorySha256",
    "candidateExecuted", "rawEvidenceCreated", "worktreeRemoved",
    "acknowledgedBuiltNeverExecutedDiscard", "receiptSha256"],
  "material_shop_built_discard_receipt_invalid", "built_discard");
  const operationClosure = assertDiscardOperationClosure(intent);
  const expected = receiptFromIntentProjection(intent, operationClosure);
  const actual = Object.assign({}, value);
  delete actual.completedAt;
  delete actual.receiptSha256;
  if (value.schema !== RECEIPT_SCHEMA || !Number.isFinite(Date.parse(value.completedAt))
      || Date.parse(value.completedAt) < Date.parse(intent.createdAt)
      || Evidence.canonicalJson(actual) !== Evidence.canonicalJson(expected)
      || value.receiptSha256 !== digestWithout(value, "receiptSha256")) {
    Common.fail("material_shop_built_discard_receipt_invalid", "built_discard",
      "built-only discard receipt is malformed or detached from its intent");
  }
  return value;
}

function receiptFromIntentProjection(intent, operationClosure) {
  return { schema: RECEIPT_SCHEMA, startedAt: intent.createdAt, runId: intent.runId,
    destination: intent.destination, preparationSha256: intent.preparationSha256,
    materializationSha256: intent.materializationSha256,
    closureSha256: intent.closureSha256, scopeSha256: intent.scopeSha256,
    buildSha256: intent.buildSha256, candidateRoot: intent.candidateRoot,
    probeSha256: intent.probeSha256, removalIntentSha256: intent.intentSha256,
    operationLeaseSha256: intent.operation.lease.leaseSha256,
    operationOutcomeName: operationClosure.outcome.name,
    operationOutcomeKind: operationClosure.outcome.kind,
    operationOutcomeSha256: operationClosure.outcome.sha256,
    operationHistorySha256: operationClosure.historySha256,
    command: intent.command, candidateExecuted: false, rawEvidenceCreated: false,
    worktreeRemoved: true, acknowledgedBuiltNeverExecutedDiscard: true };
}

function runGitRemove(destination) {
  const result = childProcess.spawnSync("git", ["-C", Common.CANONICAL_ROOT,
    "worktree", "remove", "--force", destination], {
    encoding: "utf8", windowsHide: true, maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    Common.fail("material_shop_built_discard_remove_failed", "built_discard",
      "exact Git worktree removal failed", { status: result.status,
        stderr: String(result.stderr || result.error && result.error.message || "").slice(0, 4000) });
  }
}

function assertDiscardOperationClosure(intent) {
  validateOperationBinding(intent.operation, intent.runDir,
    intent.preparationSha256, intent.buildSha256);
  const active = RunOperationLease.readLease(intent.runDir);
  if (active.active) {
    Common.fail("material_shop_run_operation_busy", "built_discard",
      "built-only finalization requires the sealed discard lease to be terminal or explicitly stale-recovered");
  }
  const actual = RunOperationLease.historyMarkers(intent.runDir)
    .map(operationHistoryProjection);
  if (actual.some((entry) => entry.lease.mode === "live_execution")) {
    Common.fail("material_shop_built_discard_candidate_may_have_executed", "built_discard",
      "live-execution operation history forbids a built-never-executed receipt");
  }
  const prior = intent.operation.preexistingHistory;
  prior.forEach((expected) => {
    const found = actual.find((entry) => entry.name === expected.name);
    if (!found || Evidence.canonicalJson(found) !== Evidence.canonicalJson(expected)) {
      Common.fail("material_shop_built_discard_operation_drift", "built_discard",
        "sealed preexisting discard-operation history changed before finalization", {
          name: expected.name,
        });
    }
  });
  const terminalName = RunOperationLease.terminalName(intent.operation.lease);
  const staleName = RunOperationLease.resolvedName(intent.operation.lease);
  const outcomes = actual.filter((entry) =>
    entry.name === terminalName || entry.name === staleName);
  const expectedNames = prior.map((entry) => entry.name)
    .concat(outcomes.map((entry) => entry.name)).sort();
  const actualNames = actual.map((entry) => entry.name).sort();
  if (outcomes.length !== 1
      || Evidence.canonicalJson(actualNames) !== Evidence.canonicalJson(expectedNames)) {
    Common.fail("material_shop_built_discard_operation_drift", "built_discard",
      "finalizer accepts only sealed prior history plus one exact outcome for its bound lease", {
        actualNames, expectedNames, terminalName, staleName,
      });
  }
  const outcome = outcomes[0];
  if (Evidence.canonicalJson(outcome.lease)
        !== Evidence.canonicalJson(intent.operation.lease)
      || outcome.bytes !== intent.operation.leaseArtifact.bytes
      || outcome.sha256 !== intent.operation.leaseArtifact.sha256) {
    Common.fail("material_shop_built_discard_operation_drift", "built_discard",
      "discard lease outcome bytes differ from the exact lease sealed by the removal intent");
  }
  const history = actual.slice().sort((left, right) => left.name.localeCompare(right.name));
  return { outcome, history,
    historySha256: Evidence.sha256Text(Evidence.canonicalJson(history)) };
}

function assertSealedFinalizerInventory(state) {
  const entries = fs.readdirSync(state.runDir, { withFileTypes: true });
  if (entries.some((entry) => !entry.isFile())) {
    Common.fail("material_shop_built_discard_live_side_effect", "built_discard",
      "built-only finalizer found a control/capture directory after removal");
  }
  const operationClosure = assertDiscardOperationClosure(state.intent);
  const controlNames = [path.basename(state.markerPath)].concat(
    operationClosure.history.map((entry) => entry.name));
  const output = path.join(state.runDir, RECEIPT_NAME);
  if (fs.existsSync(output)) controlNames.push(RECEIPT_NAME);
  const expectedNames = state.intent.runArtifacts.map((entry) => entry.name)
    .concat(controlNames).sort();
  const actualNames = entries.map((entry) => entry.name).sort();
  if (Evidence.canonicalJson(actualNames) !== Evidence.canonicalJson(expectedNames)) {
    Common.fail("material_shop_built_discard_live_side_effect", "built_discard",
      "built-only finalizer found foreign, live, or missing run artifacts", {
        actualNames, expectedNames,
      });
  }
  state.intent.runArtifacts.forEach((expected) => {
    const file = Evidence.readExactRegularFile(path.join(state.runDir, expected.name), {
      phase: "built_discard", maximumBytes: 128 * 1024 * 1024,
    });
    if (file.length !== expected.bytes || file.sha256 !== expected.sha256) {
      Common.fail("material_shop_built_discard_artifact_drift", "built_discard",
        "sealed pre-removal run artifact changed before finalization", {
          name: expected.name,
        });
    }
  });
  return { fileCount: state.intent.runArtifacts.length,
    filesSha256: Evidence.sha256Text(Evidence.canonicalJson(state.intent.runArtifacts)),
    operationClosure };
}

function finalize(runDirValue) {
  const state = loadState(runDirValue);
  if (!state.intent) {
    Common.fail("material_shop_built_discard_finalize_state_invalid", "built_discard",
      "finalizer requires one active durable discard intent");
  }
  if (fs.existsSync(state.intent.destination)
      || Materialize.worktreeListed(Common.CANONICAL_ROOT, state.intent.destination)) {
    Common.fail("material_shop_built_discard_remove_incomplete", "built_discard",
      "bare finalizer cannot remove a present worktree");
  }
  const inventory = assertSealedFinalizerInventory(state);
  const output = path.join(state.runDir, RECEIPT_NAME);
  if (!state.active) {
    if (!fs.existsSync(output)) {
      Common.fail("material_shop_built_discard_receipt_missing", "built_discard",
        "resolved built-only discard cannot recreate a missing receipt");
    }
    return validateReceipt(Prepare.readJson(output, "built_discard"), state.intent);
  }
  const receipt = fs.existsSync(output)
    ? validateReceipt(Prepare.readJson(output, "built_discard"), state.intent)
    : receiptFromIntent(state.intent, inventory.operationClosure);
  if (!fs.existsSync(output)) Materialize.writeJsonAtomicNew(output, receipt);
  assertSealedFinalizerInventory(state);
  fs.renameSync(state.markerPath, state.resolvedPath);
  const replay = loadState(state.runDir);
  if (replay.active || !replay.intent
      || Evidence.canonicalJson(replay.intent) !== Evidence.canonicalJson(state.intent)) {
    Common.fail("material_shop_built_discard_finalize_state_invalid", "built_discard",
      "discard marker archive did not preserve its exact intent");
  }
  assertSealedFinalizerInventory(replay);
  return validateReceipt(Prepare.readJson(output, "built_discard"), state.intent);
}

function discard(options) {
  const settings = options || {};
  if (settings.acknowledge !== true) {
    Common.fail("material_shop_built_discard_ack_required", "built_discard",
      "built-never-executed worktree discard requires explicit acknowledgement");
  }
  const preparationPath = path.resolve(settings.preparation || "");
  const buildPath = path.resolve(settings.build || "");
  const initialPreparation = loadAnyPreparation(preparationPath);
  const buildEnvelope = loadAnyBuildEnvelope(buildPath, initialPreparation);
  const preAcquireState = loadState(initialPreparation.runDir);
  if (preAcquireState.intent) {
    Common.fail("material_shop_built_discard_manual_recovery_required", "built_discard",
      "an existing discard intent cannot acquire a new destructive lease; inspect/recover the bound lease and use the bare finalizer only after exact worktree removal");
  }
  assertNoLiveOperationHistory(initialPreparation.runDir);
  const operationHandle = RunOperationLease.acquire({ runDir: initialPreparation.runDir,
    runId: initialPreparation.runId, mode: "built_only_discard",
    preparationSha256: initialPreparation.preparationSha256,
    buildSha256: buildEnvelope.buildSha256 });
  try {
    assertNoLiveOperationHistory(initialPreparation.runDir);
    const initialState = loadState(initialPreparation.runDir);
    if (initialState.intent) {
      Common.fail("material_shop_built_discard_manual_recovery_required", "built_discard",
        "a discard intent appeared during lease acquisition; no destructive retry is allowed");
    }
    const context = loadContext({ preparation: preparationPath, build: buildPath },
      { active: false, markerPath: null });
    const expectedIntent = createIntent(context);
    const output = path.join(context.preparation.runDir, RECEIPT_NAME);
    if (fs.existsSync(output)) Common.fail("material_shop_built_discard_output_exists",
      "built_discard", "canonical built-only discard receipt already exists");
    Materialize.writeJsonAtomicNew(path.join(context.preparation.runDir, INTENT_NAME),
      expectedIntent);
    const freshState = loadState(context.preparation.runDir);
    const fresh = loadContext({ preparation: preparationPath, build: buildPath },
      { active: true, markerPath: freshState.markerPath });
    if (fresh.probe.probeSha256 !== context.probe.probeSha256
        || Evidence.canonicalJson(fresh.probe) !== Evidence.canonicalJson(context.probe)) {
      Common.fail("material_shop_built_discard_probe_drift", "built_discard",
        "built-only worktree changed between the two fresh destructive probes");
    }
    if (!fs.existsSync(fresh.preparation.resourcesRoot)
        || !Materialize.worktreeListed(Common.CANONICAL_ROOT, fresh.preparation.resourcesRoot)) {
      Common.fail("material_shop_built_discard_split_state", "built_discard",
        "worktree filesystem/Git state split before exact removal");
    }
    runGitRemove(fresh.preparation.resourcesRoot);
    if (fs.existsSync(fresh.preparation.resourcesRoot)
        || Materialize.worktreeListed(Common.CANONICAL_ROOT, fresh.preparation.resourcesRoot)) {
      Common.fail("material_shop_built_discard_remove_incomplete", "built_discard",
        "exact worktree remained after Git removal");
    }
    RunOperationLease.release(operationHandle);
    return finalize(fresh.preparation.runDir);
  } finally {
    if (operationHandle.active) RunOperationLease.release(operationHandle);
  }
}

function parseArgs(argv) {
  const args = { mode: null, runDir: null, preparation: null, build: null,
    acknowledge: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--discard-built-never-executed") args.mode = "discard";
    else if (argv[index] === "--finalize-built-discard") args.mode = "finalize";
    else if (argv[index] === "--run-dir") args.runDir = argv[++index];
    else if (argv[index] === "--preparation") args.preparation = argv[++index];
    else if (argv[index] === "--build") args.build = argv[++index];
    else if (argv[index] === "--acknowledge-built-never-executed-discard") {
      args.acknowledge = true;
    } else Common.fail("material_shop_built_discard_argument_unknown", "built_discard",
      argv[index]);
  }
  if (args.mode === "finalize") {
    if (!args.runDir || args.preparation || args.build || args.acknowledge) {
      Common.fail("material_shop_built_discard_arguments_invalid", "built_discard",
        "bare finalizer accepts only one exact run directory");
    }
  } else if (args.mode !== "discard" || !args.preparation || !args.build
      || args.runDir || !args.acknowledge) {
    Common.fail("material_shop_built_discard_arguments_invalid", "built_discard",
      "discard requires exact preparation/build receipts and explicit acknowledgement");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const value = args.mode === "finalize" ? finalize(args.runDir) : discard(args);
    process.stdout.write(JSON.stringify({ ok: true, status: "built_never_executed_discarded",
      runId: value.runId, receiptSha256: value.receiptSha256 }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  INTENT_NAME,
  INTENT_SCHEMA,
  LEGACY_BUILD_SCHEMA,
  LEGACY_PREPARATION_SCHEMA,
  RECEIPT_NAME,
  RECEIPT_SCHEMA,
  RESOLVED_PREFIX,
  assertLiveExecutionAvailable,
  assertDiscardOperationClosure,
  assertNoLiveOperationHistory,
  captureRunArtifactInventory,
  captureMaterializationProducerHistory,
  captureDiscardOperation,
  assertSealedFinalizerInventory,
  createIntent,
  discard,
  emptySlotProjection,
  finalize,
  loadAnyBuild,
  loadAnyBuildEnvelope,
  loadAnyPreparation,
  loadContext,
  loadState,
  parseArgs,
  receiptFromIntent,
  resolvedName,
  validateIntent,
  validateLegacyBuild,
  validateOperationBinding,
  validateReceipt,
};
