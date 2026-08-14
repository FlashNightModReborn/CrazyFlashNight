#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const Applicability = require("./applicability");
const Build = require("./build-candidate");
const Common = require("./common");
const DiscardBuilt = require("./discard-built-run");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const RunOperationLease = require("./run-operation-lease");

const ELIGIBILITY_KIND = "pre_candidate_seed_audit_failure";
const INTENT_SCHEMA = "workbench-live-e2e.material-shop.seed-audit-failure-discard-intent.v2";
const RECEIPT_SCHEMA = "workbench-live-e2e.material-shop.seed-audit-failure-discard.v2";
const INTENT_NAME = "seed-audit-failure-discard-intent.json";
const RECEIPT_NAME = "seed-audit-failure-discard.json";
const RESUME_PREFIX = "seed-audit-failure-discard-resume-";
const RESOLVED_PREFIX = "seed-audit-failure-discard-resolved-";
const EMPTY_SHA256 = Evidence.sha256Bytes(Buffer.alloc(0));
const EXPECTED_ERROR = Object.freeze({
  ok: false,
  code: "material_shop_seed_audit_incomplete",
  phase: "applicability",
  message: "each audited fixture must bind one JSON and a non-empty complete owned SOL set",
});
const HISTORICAL_FAILURE_SOURCES = Object.freeze([
  Object.freeze({ relativePath: "tools/workbench-live-e2e/material-shop/run-live-journey.js",
    bytes: 22005,
    sha256: "7a0bc766833cc92d86521b9440c147d00e9deb62b1c6e58232baec04bc485ffe" }),
  Object.freeze({ relativePath: "tools/workbench-live-e2e/material-shop/candidate-lifecycle.js",
    bytes: 14901,
    sha256: "af4dd24aa2d63e1c7287f3df55f47d97a31d7e65d6bc98b5d9001cfb918daa0a" }),
  Object.freeze({ relativePath: "tools/workbench-live-e2e/material-shop/applicability.js",
    bytes: 23186,
    sha256: "8256d346d99fd362501ae398b97c351a01f8ba4bac4bc09b20a7a7a447fbd86a" }),
]);

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
    Common.fail("material_shop_seed_failure_artifact_escape", phase,
      "pre-candidate failure artifact escaped its exact run directory");
  }
  const file = Evidence.readExactRegularFile(absolute, {
    phase, maximumBytes: 128 * 1024 * 1024,
  });
  if (file.sha256 !== reference.sha256 || file.length !== reference.bytes) {
    Common.fail("material_shop_seed_failure_artifact_drift", phase,
      "pre-candidate failure artifact changed after preparation", { absolute });
  }
  try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_seed_failure_artifact_invalid", phase, error.message);
  }
}

function exactOperatorLogPaths(runId) {
  if (!Common.ID_RE.test(String(runId || ""))) {
    Common.fail("material_shop_seed_failure_run_invalid", "seed_failure_discard",
      "operator log derivation requires one exact A5 run id");
  }
  const base = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "operator-attestations");
  Evidence.assertExactDirectory(base, "seed_failure_discard");
  return {
    base,
    stdout: path.join(base, runId + ".runner.stdout.log"),
    stderr: path.join(base, runId + ".runner.stderr.log"),
  };
}

function captureRunnerLogs(runId, leaseCreatedAt) {
  const paths = exactOperatorLogPaths(runId);
  const stdout = Materialize.readExactTreeFile(paths.stdout, {
    phase: "seed_failure_discard", maximumBytes: 1024 * 1024,
  });
  const stderr = Materialize.readExactTreeFile(paths.stderr, {
    phase: "seed_failure_discard", maximumBytes: 1024 * 1024,
  });
  const expectedBytes = Buffer.from(JSON.stringify(EXPECTED_ERROR) + "\n", "utf8");
  if (stdout.length !== 0 || stdout.sha256 !== EMPTY_SHA256
      || stderr.length !== expectedBytes.length
      || stderr.sha256 !== Evidence.sha256Bytes(expectedBytes)
      || !stderr.bytes.equals(expectedBytes)) {
    Common.fail("material_shop_seed_failure_runner_log_invalid", "seed_failure_discard",
      "derived runner logs do not prove the one exact pre-candidate seed audit failure");
  }
  const stderrStat = fs.statSync(stderr.path);
  if (!Number.isFinite(Date.parse(leaseCreatedAt))
      || stderrStat.mtimeMs + 1000 < Date.parse(leaseCreatedAt)) {
    Common.fail("material_shop_seed_failure_runner_log_stale", "seed_failure_discard",
      "runner stderr predates the qualifying live operation lease");
  }
  const relative = (filePath) => path.relative(path.join(Common.CANONICAL_ROOT,
    Common.OWNED_BASE_RELATIVE), filePath).replace(/\\/g, "/");
  return {
    stdout: { derivedRelativePath: relative(stdout.path), bytes: stdout.length,
      sha256: stdout.sha256 },
    stderr: { derivedRelativePath: relative(stderr.path), bytes: stderr.length,
      sha256: stderr.sha256 },
    parsedError: Object.assign({}, EXPECTED_ERROR),
  };
}

function qualifyingLiveTerminal(runDir, preparationSha256, buildSha256) {
  const active = RunOperationLease.readLease(runDir);
  if (active.active) {
    Common.fail("material_shop_seed_failure_operation_busy", "seed_failure_discard",
      "pre-candidate failure cleanup requires no preexisting active operation lease");
  }
  const history = RunOperationLease.historyMarkers(runDir);
  if (history.length !== 1 || history[0].kind !== "terminal"
      || history[0].lease.mode !== "live_execution"
      || history[0].lease.preparationSha256 !== preparationSha256
      || history[0].lease.buildSha256 !== buildSha256) {
    Common.fail("material_shop_seed_failure_live_terminal_invalid", "seed_failure_discard",
      "cleanup admits exactly one bound live terminal and never stale or arbitrary live history");
  }
  return history[0];
}

function operationProjection(entry) {
  return { name: entry.name, bytes: entry.bytes, sha256: entry.sha256,
    kind: entry.kind, lease: Object.assign({}, entry.lease) };
}

function cleanupOutcomeOrder(left, right) {
  const created = Date.parse(left.lease.createdAt) - Date.parse(right.lease.createdAt);
  return created || left.name.localeCompare(right.name);
}

function cleanupChainEntry(outcome, ordinal) {
  return { ordinal, lease: JSON.parse(JSON.stringify(outcome.lease)),
    leaseArtifact: { bytes: outcome.bytes, sha256: outcome.sha256 },
    outcome: JSON.parse(JSON.stringify(outcome)) };
}

function validateBoundCleanupOutcome(outcome, runDir, preparationSha256, buildSha256,
  earliestCreatedAt) {
  const leaseArtifact = { bytes: outcome.bytes, sha256: outcome.sha256 };
  validateOutcome(outcome, outcome.lease, leaseArtifact, runDir);
  if (outcome.lease.mode !== "built_only_discard"
      || outcome.lease.preparationSha256 !== preparationSha256
      || outcome.lease.buildSha256 !== buildSha256
      || Date.parse(outcome.lease.createdAt) < Date.parse(earliestCreatedAt)) {
    Common.fail("material_shop_seed_failure_operation_chain_invalid",
      "seed_failure_discard",
      "orphan cleanup outcome is foreign to the exact pre-candidate failure chain");
  }
  return outcome;
}

function preIntentOperationHistory(runDir, preparationSha256, buildSha256) {
  const active = RunOperationLease.readLease(runDir);
  if (active.active) {
    Common.fail("material_shop_seed_failure_operation_busy", "seed_failure_discard",
      "pre-intent cleanup retry requires the prior lease to be terminal or stale-recovered");
  }
  const history = RunOperationLease.historyMarkers(runDir).map(operationProjection);
  const live = history.filter((entry) => entry.kind === "terminal"
    && entry.lease.mode === "live_execution"
    && entry.lease.preparationSha256 === preparationSha256
    && entry.lease.buildSha256 === buildSha256);
  if (live.length !== 1) {
    Common.fail("material_shop_seed_failure_live_terminal_invalid", "seed_failure_discard",
      "cleanup admits exactly one bound live terminal and never arbitrary live history");
  }
  const prior = history.filter((entry) => entry.name !== live[0].name)
    .map((entry) => validateBoundCleanupOutcome(entry, runDir, preparationSha256,
      buildSha256, live[0].lease.createdAt)).sort(cleanupOutcomeOrder)
    .map((entry, ordinal) => cleanupChainEntry(entry, ordinal));
  if (prior.length > 0) validateOperationChain(prior, runDir, preparationSha256,
    buildSha256, null, true);
  return { qualifyingLiveTerminal: live[0], priorOperationChain: prior };
}

function operationOutcomeName(lease, kind) {
  return kind === "terminal" ? RunOperationLease.terminalName(lease)
    : kind === "stale_recovery" ? RunOperationLease.resolvedName(lease) : null;
}

function validateOutcome(value, lease, leaseArtifact, runDir) {
  Common.exactKeys(value, ["name", "bytes", "sha256", "kind", "lease"],
    "material_shop_seed_failure_operation_chain_invalid", "seed_failure_discard");
  RunOperationLease.validateLease(value.lease, runDir);
  const expectedName = operationOutcomeName(lease, value.kind);
  if (!expectedName || value.name !== expectedName
      || Evidence.canonicalJson(value.lease) !== Evidence.canonicalJson(lease)
      || value.bytes !== leaseArtifact.bytes || value.sha256 !== leaseArtifact.sha256) {
    Common.fail("material_shop_seed_failure_operation_chain_invalid",
      "seed_failure_discard",
      "cleanup operation outcome differs from its exact sealed lease bytes");
  }
  return value;
}

function validateOperationChain(chain, runDir, preparationSha256, buildSha256,
  latestOperation, fullySealed) {
  if (!Array.isArray(chain) || chain.length < 1) {
    Common.fail("material_shop_seed_failure_operation_chain_invalid",
      "seed_failure_discard", "cleanup intent lacks its append-only operation chain");
  }
  const seen = new Set();
  chain.forEach((entry, index) => {
    Common.exactKeys(entry, ["ordinal", "lease", "leaseArtifact", "outcome"],
      "material_shop_seed_failure_operation_chain_invalid", "seed_failure_discard");
    RunOperationLease.validateLease(entry.lease, runDir);
    Common.exactKeys(entry.leaseArtifact, ["bytes", "sha256"],
      "material_shop_seed_failure_operation_chain_invalid", "seed_failure_discard");
    if (entry.ordinal !== index || entry.lease.mode !== "built_only_discard"
        || entry.lease.preparationSha256 !== preparationSha256
        || entry.lease.buildSha256 !== buildSha256
        || !Number.isSafeInteger(entry.leaseArtifact.bytes)
        || entry.leaseArtifact.bytes < 1
        || !Common.SHA256_RE.test(String(entry.leaseArtifact.sha256 || ""))
        || seen.has(entry.lease.leaseSha256)
        || index < chain.length - 1 && !entry.outcome
        || index === chain.length - 1
          && (fullySealed === true ? !entry.outcome : entry.outcome !== null)) {
      Common.fail("material_shop_seed_failure_operation_chain_invalid",
        "seed_failure_discard",
        "cleanup operation chain is foreign, unordered, duplicated, or not append-only");
    }
    seen.add(entry.lease.leaseSha256);
    if (entry.outcome) validateOutcome(entry.outcome, entry.lease,
      entry.leaseArtifact, runDir);
  });
  const last = chain[chain.length - 1];
  if (latestOperation && (Evidence.canonicalJson(last.lease)
        !== Evidence.canonicalJson(latestOperation.lease)
      || Evidence.canonicalJson(last.leaseArtifact)
        !== Evidence.canonicalJson(latestOperation.leaseArtifact))) {
    Common.fail("material_shop_seed_failure_operation_chain_invalid",
      "seed_failure_discard",
      "latest cleanup operation differs from the lease sealed by the current probe");
  }
  return chain;
}

function sealPriorOperationChain(intent) {
  const active = RunOperationLease.readLease(intent.runDir);
  if (active.active) {
    Common.fail("material_shop_seed_failure_operation_busy", "seed_failure_discard",
      "resume requires the prior cleanup lease to be terminal or explicitly stale-recovered");
  }
  const history = RunOperationLease.historyMarkers(intent.runDir).map(operationProjection);
  const live = intent.probe.qualifyingLiveTerminal;
  const liveReplay = history.filter((entry) => entry.name === live.name);
  if (liveReplay.length !== 1
      || Evidence.canonicalJson(liveReplay[0]) !== Evidence.canonicalJson(live)) {
    Common.fail("material_shop_seed_failure_operation_chain_invalid",
      "seed_failure_discard", "qualifying live terminal drifted before cleanup resume");
  }
  const sealed = intent.operationChain.map((entry) => JSON.parse(JSON.stringify(entry)));
  sealed.forEach((entry) => {
    const terminalName = RunOperationLease.terminalName(entry.lease);
    const staleName = RunOperationLease.resolvedName(entry.lease);
    const outcomes = history.filter((candidate) =>
      candidate.name === terminalName || candidate.name === staleName);
    if (outcomes.length !== 1) {
      Common.fail("material_shop_seed_failure_operation_chain_invalid",
        "seed_failure_discard",
        "resume requires one exact terminal or stale outcome for the prior cleanup lease");
    }
    validateOutcome(outcomes[0], entry.lease, entry.leaseArtifact, intent.runDir);
    if (entry.outcome && Evidence.canonicalJson(entry.outcome)
        !== Evidence.canonicalJson(outcomes[0])) {
      Common.fail("material_shop_seed_failure_operation_chain_invalid",
        "seed_failure_discard",
        "sealed cleanup outcome differs from its exact retained marker bytes");
    }
    entry.outcome = outcomes[0];
  });
  const knownNames = new Set([live.name].concat(
    sealed.map((entry) => entry.outcome.name)));
  const earliest = sealed[sealed.length - 1].lease.createdAt;
  history.filter((entry) => !knownNames.has(entry.name))
    .map((entry) => validateBoundCleanupOutcome(entry, intent.runDir,
      intent.preparationSha256, intent.buildSha256, earliest))
    .sort(cleanupOutcomeOrder).forEach((entry) => {
      sealed.push(cleanupChainEntry(entry, sealed.length));
      knownNames.add(entry.name);
    });
  const allowed = [live.name].concat(sealed.map((entry) => entry.outcome.name)).sort();
  const actual = history.map((entry) => entry.name).sort();
  if (new Set(actual).size !== actual.length
      || Evidence.canonicalJson(actual) !== Evidence.canonicalJson(allowed)) {
    Common.fail("material_shop_seed_failure_operation_chain_invalid",
      "seed_failure_discard",
      "foreign or unsealed operation history appeared before cleanup resume");
  }
  validateOperationChain(sealed, intent.runDir, intent.preparationSha256,
    intent.buildSha256, null, true);
  return sealed;
}

function captureCleanupOperation(runDir, preparationSha256, buildSha256,
  priorOperationChain) {
  const active = RunOperationLease.readLease(runDir);
  if (!active.active || active.lease.mode !== "built_only_discard"
      || active.lease.preparationSha256 !== preparationSha256
      || active.lease.buildSha256 !== buildSha256) {
    Common.fail("material_shop_seed_failure_cleanup_lease_invalid", "seed_failure_discard",
      "destructive probes require one exact bound built-only mutex lease");
  }
  const history = RunOperationLease.historyMarkers(runDir).map(operationProjection);
  const liveHistory = history.filter((entry) => entry.kind === "terminal"
    && entry.lease.mode === "live_execution");
  if (liveHistory.length !== 1
      || liveHistory[0].lease.preparationSha256 !== preparationSha256
      || liveHistory[0].lease.buildSha256 !== buildSha256) {
    Common.fail("material_shop_seed_failure_live_terminal_invalid", "seed_failure_discard",
      "the cleanup mutex may coexist only with its one qualifying live terminal");
  }
  const prior = priorOperationChain || [];
  if (prior.length > 0) validateOperationChain(prior.concat([{
    ordinal: prior.length, lease: active.lease,
    leaseArtifact: { bytes: active.artifact.bytes, sha256: active.artifact.sha256 },
    outcome: null,
  }]), runDir, preparationSha256, buildSha256, {
    lease: active.lease, leaseArtifact: active.artifact,
  });
  const expectedHistory = [liveHistory[0].name]
    .concat(prior.map((entry) => entry.outcome && entry.outcome.name)).sort();
  const actualHistory = history.map((entry) => entry.name).sort();
  const priorOutcomeDrift = prior.some((entry) => {
    const actual = history.find((candidate) => entry.outcome
      && candidate.name === entry.outcome.name);
    return !actual || Evidence.canonicalJson(actual)
      !== Evidence.canonicalJson(entry.outcome);
  });
  if (prior.some((entry) => !entry.outcome)
      || priorOutcomeDrift
      || Evidence.canonicalJson(actualHistory) !== Evidence.canonicalJson(expectedHistory)) {
    Common.fail("material_shop_seed_failure_operation_chain_invalid",
      "seed_failure_discard",
      "cleanup probe found foreign or unsealed prior operation history");
  }
  const value = { lease: Object.assign({}, active.lease),
    leaseArtifact: { bytes: active.artifact.bytes, sha256: active.artifact.sha256 },
    qualifyingLiveTerminal: liveHistory[0],
    priorCleanupOutcomes: prior.map((entry) => operationProjection(entry.outcome)) };
  value.operationSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function coreTopLevelNames(preparation, buildPath, creation) {
  const names = Object.values(preparation.artifacts).map((reference) => {
    const relative = String(reference.relativePath || "").replace(/\\/g, "/");
    if (!relative || relative.includes("/")) {
      Common.fail("material_shop_seed_failure_run_layout_invalid", "seed_failure_discard",
        "preparation artifacts must be direct files in the exact run directory");
    }
    return relative;
  });
  names.push("preparation.json", path.basename(buildPath),
    path.basename(creation.markerPath), "passive-transcript.jsonl", "control");
  return Array.from(new Set(names)).sort();
}

function captureCoreRunLayout(preparation, buildPath, creation, dynamicNames) {
  const runDir = preparation.runDir;
  const coreNames = coreTopLevelNames(preparation, buildPath, creation);
  const expectedTop = coreNames.concat(dynamicNames || []).sort();
  const entries = fs.readdirSync(runDir, { withFileTypes: true });
  const actualTop = entries.map((entry) => entry.name).sort();
  if (Evidence.canonicalJson(actualTop) !== Evidence.canonicalJson(expectedTop)) {
    Common.fail("material_shop_seed_failure_run_layout_invalid", "seed_failure_discard",
      "run contains a candidate admission, raw, clone, recovery, or foreign artifact", {
        actualTop, expectedTop,
      });
  }
  const control = path.join(runDir, "control");
  Evidence.assertExactDirectory(control, "seed_failure_discard");
  const controlNames = fs.readdirSync(control, { withFileTypes: true });
  if (Evidence.canonicalJson(controlNames.map((entry) => entry.name).sort())
        !== Evidence.canonicalJson(["acks", "captures", "requests"])
      || controlNames.some((entry) => !entry.isDirectory() || entry.isSymbolicLink())) {
    Common.fail("material_shop_seed_failure_control_invalid", "seed_failure_discard",
      "control evidence must contain exactly three direct empty directories");
  }
  ["acks", "captures", "requests"].forEach((name) => {
    const directory = Evidence.assertExactDirectory(path.join(control, name),
      "seed_failure_discard");
    if (fs.readdirSync(directory).length !== 0) {
      Common.fail("material_shop_seed_failure_control_invalid", "seed_failure_discard",
        "pre-candidate failure control directories must remain empty", { name });
    }
  });
  const inventory = [
    { relativePath: "control", kind: "directory" },
    { relativePath: "control/acks", kind: "directory" },
    { relativePath: "control/captures", kind: "directory" },
    { relativePath: "control/requests", kind: "directory" },
  ];
  coreNames.filter((name) => name !== "control").forEach((name) => {
    const file = Materialize.readExactTreeFile(path.join(runDir, name), {
      phase: "seed_failure_discard", maximumBytes: 128 * 1024 * 1024,
    });
    inventory.push({ relativePath: name, kind: "file", bytes: file.length,
      sha256: file.sha256 });
  });
  inventory.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  const passive = inventory.find((entry) => entry.relativePath === "passive-transcript.jsonl");
  if (!passive || passive.bytes !== 0 || passive.sha256 !== EMPTY_SHA256) {
    Common.fail("material_shop_seed_failure_transcript_invalid", "seed_failure_discard",
      "pre-candidate failure requires one preserved zero-byte passive transcript");
  }
  return { topLevelCoreNames: coreNames, entries: inventory,
    fileCount: inventory.filter((entry) => entry.kind === "file").length,
    layoutSha256: Evidence.sha256Text(Evidence.canonicalJson(inventory)) };
}

function captureProcessAbsence(candidateRoot) {
  const processes = LauncherObservation.queryLauncherCoreProcesses();
  LauncherObservation.assertExclusiveLauncherProcess(processes, null);
  const candidateCount = processes.filter((entry) => {
    const processPath = entry && (entry.processPath || entry.path || entry.executablePath);
    return processPath && Evidence.pathInside(candidateRoot, path.resolve(processPath));
  }).length;
  if (processes.length !== 0 || candidateCount !== 0) {
    Common.fail("material_shop_seed_failure_process_present", "seed_failure_discard",
      "pre-candidate cleanup requires zero Launcher/Core process inventory");
  }
  return { launcherCoreProcessCount: 0, candidateProcessCount: 0,
    processInventorySha256: Evidence.sha256Text(Evidence.canonicalJson([])) };
}

function validateHistoricalFailureSources(value) {
  if (Evidence.canonicalJson(value) !== Evidence.canonicalJson(
    HISTORICAL_FAILURE_SOURCES)) {
    Common.fail("material_shop_seed_failure_historical_source_invalid",
      "seed_failure_discard",
      "special cleanup accepts only the three exact historical root-coupling source bytes");
  }
  return value;
}

function assertHistoricalRootBug(resourcesRoot) {
  const projection = HISTORICAL_FAILURE_SOURCES.map((expected) => {
    const file = Evidence.readExactRegularFile(path.join(resourcesRoot,
      expected.relativePath.replace(/\//g, path.sep)), {
      phase: "seed_failure_discard", maximumBytes: 4 * 1024 * 1024,
    });
    return { relativePath: expected.relativePath, bytes: file.length,
      sha256: file.sha256 };
  });
  return validateHistoricalFailureSources(projection);
}

function lifecycleBaseAbsent(preparation) {
  const location = path.join(preparation.resourcesRoot, "tmp", "workbench-live-e2e",
    "material-shop", preparation.runId);
  if (fs.existsSync(location)) {
    Common.fail("material_shop_seed_failure_lifecycle_side_effect", "seed_failure_discard",
      "lifecycle internal state exists despite the pre-candidate seed audit failure");
  }
  return false;
}

function stableProbe(value) {
  const copy = Object.assign({}, value);
  delete copy.probeSha256;
  return copy;
}

function validateProbe(value) {
  Common.exactKeys(value, ["eligibilityKind", "preparationSha256", "materializationSha256",
    "closureSha256", "scopeSha256", "applicabilitySha256", "buildSha256",
    "candidateRoot", "historicalRootBug", "runnerLogs", "qualifyingLiveTerminal",
    "preCandidateState", "runLayout", "postBuildScope", "gitWorktreeIdentitySha256",
    "operation", "probeSha256"], "material_shop_seed_failure_probe_invalid",
  "seed_failure_discard");
  const state = value.preCandidateState || {};
  const live = value.qualifyingLiveTerminal || {};
  const operation = value.operation || {};
  Common.exactKeys(operation, ["lease", "leaseArtifact", "qualifyingLiveTerminal",
    "priorCleanupOutcomes", "operationSha256"],
  "material_shop_seed_failure_probe_invalid", "seed_failure_discard");
  const operationUnsigned = Object.assign({}, operation);
  delete operationUnsigned.operationSha256;
  if (value.eligibilityKind !== ELIGIBILITY_KIND
      || [value.preparationSha256, value.materializationSha256, value.closureSha256,
        value.scopeSha256, value.applicabilitySha256, value.buildSha256,
        value.gitWorktreeIdentitySha256].some((digest) =>
        !Common.SHA256_RE.test(String(digest || "")))
      || live.kind !== "terminal" || !live.lease || live.lease.mode !== "live_execution"
      || live.lease.preparationSha256 !== value.preparationSha256
      || live.lease.buildSha256 !== value.buildSha256
      || !operation.lease || operation.lease.mode !== "built_only_discard"
      || operation.lease.preparationSha256 !== value.preparationSha256
      || operation.lease.buildSha256 !== value.buildSha256
      || !Array.isArray(operation.priorCleanupOutcomes)
      || operation.operationSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(operationUnsigned))
      || state.launcherCoreProcessCount !== 0 || state.candidateProcessCount !== 0
      || state.passiveTranscriptBytes !== 0 || state.passiveTranscriptSha256 !== EMPTY_SHA256
      || state.admissionCount !== 0 || state.rawEvidenceCount !== 0
      || state.cloneMutationCount !== 0 || state.lifecycleBasePresent !== false
      || !Array.isArray(state.slots) || state.slots.length !== 3
      || state.slots.some((slot) => slot.artifactCount !== 0
        || slot.lockPresent !== false || slot.recoveryPresent !== false)
      || Evidence.canonicalJson(value.runnerLogs.parsedError)
        !== Evidence.canonicalJson(EXPECTED_ERROR)
      || value.probeSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableProbe(value)))) {
    Common.fail("material_shop_seed_failure_probe_invalid", "seed_failure_discard",
      "pre-candidate seed audit failure probe is malformed or semantically widened");
  }
  return value;
}

function captureProbe(context, state, priorOperationChain) {
  const operation = captureCleanupOperation(context.preparation.runDir,
    context.preparation.preparationSha256, context.build.buildSha256,
    priorOperationChain);
  const dynamicNames = [RunOperationLease.LEASE_NAME,
    operation.qualifyingLiveTerminal.name].concat(
    operation.priorCleanupOutcomes.map((entry) => entry.name));
  if (state && Array.isArray(state.markerNames)) {
    dynamicNames.push.apply(dynamicNames, state.markerNames);
  }
  const runLayout = captureCoreRunLayout(context.preparation, context.buildPath,
    context.creation, dynamicNames);
  const runnerLogs = captureRunnerLogs(context.preparation.runId,
    operation.qualifyingLiveTerminal.lease.createdAt);
  const processAbsence = captureProcessAbsence(context.build.candidateRoot);
  const slots = [context.preparation.slots.seedSlot, context.preparation.slots.targetSlot,
    context.preparation.slots.recoverySlot].map((slot) =>
    DiscardBuilt.emptySlotProjection(context.preparation.resourcesRoot, slot));
  const postBuild = Materialize.verifyPostBuildProtectedScope(
    context.preparation.resourcesRoot, context.closure.scope,
    Build.protectedScopeOptions(context.preparation, context.build.candidateRoot));
  const value = {
    eligibilityKind: ELIGIBILITY_KIND,
    preparationSha256: context.preparation.preparationSha256,
    materializationSha256: context.materialization.materializationSha256,
    closureSha256: context.closure.closureSha256,
    scopeSha256: context.closure.scope.scopeSha256,
    applicabilitySha256: context.applicability.applicabilitySha256,
    buildSha256: context.build.buildSha256,
    candidateRoot: context.build.candidateRoot,
    historicalRootBug: assertHistoricalRootBug(context.preparation.resourcesRoot),
    runnerLogs,
    qualifyingLiveTerminal: operation.qualifyingLiveTerminal,
    preCandidateState: Object.assign({}, processAbsence, {
      passiveTranscriptBytes: 0, passiveTranscriptSha256: EMPTY_SHA256,
      admissionCount: 0, rawEvidenceCount: 0, cloneMutationCount: 0,
      lifecycleBasePresent: lifecycleBaseAbsent(context.preparation), slots,
    }),
    runLayout,
    postBuildScope: { scopeSha256: postBuild.scopeSha256,
      ignoredOutputInventorySha256: postBuild.ignoredOutputInventory.inventorySha256,
      ignoredFileCount: postBuild.ignoredOutputInventory.fileCount,
      ignoredTotalBytes: postBuild.ignoredOutputInventory.totalBytes },
    gitWorktreeIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(context.materialization.gitWorktree)),
    operation,
  };
  value.probeSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableProbe(value)));
  return validateProbe(value);
}

function loadBaseContext(options) {
  const preparationPath = path.resolve(options.preparation || "");
  const buildPath = path.resolve(options.build || "");
  const preparation = Build.loadPreparation(preparationPath);
  const closure = readBoundArtifact(preparation.runDir,
    preparation.artifacts.closure, "seed_failure_discard");
  const materialization = readBoundArtifact(preparation.runDir,
    preparation.artifacts.materialization, "seed_failure_discard");
  Materialize.verifyMaterialization(materialization, closure.scope, {
    ownedBase: materialization.ownedBase, fixtureMode: false, allowBuildOutputs: true,
  });
  const build = Build.loadBuildReceipt(buildPath, preparation, closure,
    "seed_failure_discard");
  const applicability = Applicability.validateApplicability(readBoundArtifact(
    preparation.runDir, preparation.artifacts.applicability, "seed_failure_discard"));
  const creation = Materialize.loadCreationState(preparation.runDir);
  if (!creation.materialized || creation.active || creation.cleanupResolved
      || !samePath(creation.intent.destination, preparation.resourcesRoot)) {
    Common.fail("material_shop_seed_failure_materialization_invalid",
      "seed_failure_discard",
      "special cleanup requires one resolved successful materialization marker");
  }
  if (!fs.existsSync(preparation.resourcesRoot)
      || !Materialize.worktreeListed(Common.CANONICAL_ROOT, preparation.resourcesRoot)) {
    Common.fail("material_shop_seed_failure_worktree_split", "seed_failure_discard",
      "special cleanup requires one present filesystem/Git worktree");
  }
  return { preparationPath, buildPath, preparation, closure, materialization,
    applicability, build, creation };
}

function loadContext(options, state, priorOperationChain) {
  const context = loadBaseContext(options);
  context.probe = captureProbe(context, state, priorOperationChain);
  return context;
}

function resolvedName(intent) {
  return RESOLVED_PREFIX + intent.intentSha256.slice(0, 16) + ".json";
}

function intentMarkerName(intent) {
  return intent.sequence === 0 ? INTENT_NAME
    : RESUME_PREFIX + String(intent.sequence).padStart(4, "0") + "-"
      + intent.intentSha256.slice(0, 16) + ".json";
}

function validateIntent(value) {
  Common.exactKeys(value, ["schema", "createdAt", "eligibilityKind", "runId",
    "canonicalRoot", "runDir", "destination", "preparationSha256",
    "materializationSha256", "closureSha256", "scopeSha256", "applicabilitySha256",
    "buildSha256", "candidateRoot", "sequence", "parentIntent", "operationChain",
    "probe", "head", "commonDir", "command", "acknowledgedSeedAuditFailureDiscard",
    "intentSha256"],
  "material_shop_seed_failure_intent_invalid", "seed_failure_discard");
  validateProbe(value.probe);
  const expectedBase = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const parentValid = value.sequence === 0 ? value.parentIntent === null
    : value.parentIntent && Evidence.canonicalJson(Object.keys(value.parentIntent).sort())
      === Evidence.canonicalJson(["name", "intentSha256"].sort())
      && new RegExp("^(?:" + RESUME_PREFIX + "[0-9]{4}-[a-f0-9]{16}\\.json|"
        + INTENT_NAME.replace(/\./g, "\\.") + ")$").test(value.parentIntent.name)
      && Common.SHA256_RE.test(String(value.parentIntent.intentSha256 || ""));
  validateOperationChain(value.operationChain, value.runDir,
    value.preparationSha256, value.buildSha256, value.probe.operation, false);
  const expectedPriorOutcomes = value.operationChain.slice(0, -1)
    .map((entry) => operationProjection(entry.outcome));
  if (value.schema !== INTENT_SCHEMA || value.eligibilityKind !== ELIGIBILITY_KIND
      || !Number.isFinite(Date.parse(value.createdAt))
      || !Common.ID_RE.test(String(value.runId || ""))
      || !samePath(value.canonicalRoot, Common.CANONICAL_ROOT)
      || !samePath(value.runDir, path.join(expectedBase, "runs", value.runId))
      || !samePath(value.destination, path.join(expectedBase,
        Materialize.MATERIALIZED_DIRECTORY, value.runId, "resources"))
      || !samePath(value.candidateRoot, value.probe.candidateRoot)
      || value.preparationSha256 !== value.probe.preparationSha256
      || value.materializationSha256 !== value.probe.materializationSha256
      || value.closureSha256 !== value.probe.closureSha256
      || value.scopeSha256 !== value.probe.scopeSha256
      || value.applicabilitySha256 !== value.probe.applicabilitySha256
      || value.buildSha256 !== value.probe.buildSha256
      || !Number.isInteger(value.sequence) || value.sequence < 0 || !parentValid
      || Evidence.canonicalJson(value.probe.operation.qualifyingLiveTerminal)
        !== Evidence.canonicalJson(value.probe.qualifyingLiveTerminal)
      || Evidence.canonicalJson(value.probe.operation.priorCleanupOutcomes)
        !== Evidence.canonicalJson(expectedPriorOutcomes)
      || !Common.GIT_OID_RE.test(String(value.head || ""))
      || typeof value.commonDir !== "string"
      || value.command !== "git worktree remove --force"
      || value.acknowledgedSeedAuditFailureDiscard !== true
      || value.intentSha256 !== digestWithout(value, "intentSha256")) {
    Common.fail("material_shop_seed_failure_intent_invalid", "seed_failure_discard",
      "seed-audit failure discard intent is malformed, foreign, or widened");
  }
  return value;
}

function createIntent(context, createdAt, priorOperationChain) {
  const prior = priorOperationChain || [];
  if (prior.length > 0) validateOperationChain(prior, context.preparation.runDir,
    context.preparation.preparationSha256, context.build.buildSha256, null, true);
  const operationChain = prior.map((entry) => JSON.parse(JSON.stringify(entry)));
  operationChain.push({ ordinal: operationChain.length,
    lease: JSON.parse(JSON.stringify(context.probe.operation.lease)),
    leaseArtifact: JSON.parse(JSON.stringify(context.probe.operation.leaseArtifact)),
    outcome: null });
  const value = { schema: INTENT_SCHEMA, createdAt: createdAt || new Date().toISOString(),
    eligibilityKind: ELIGIBILITY_KIND, runId: context.preparation.runId,
    canonicalRoot: Common.CANONICAL_ROOT, runDir: context.preparation.runDir,
    destination: context.preparation.resourcesRoot,
    preparationSha256: context.preparation.preparationSha256,
    materializationSha256: context.materialization.materializationSha256,
    closureSha256: context.closure.closureSha256,
    scopeSha256: context.closure.scope.scopeSha256,
    applicabilitySha256: context.applicability.applicabilitySha256,
    buildSha256: context.build.buildSha256, candidateRoot: context.build.candidateRoot,
    sequence: 0, parentIntent: null, operationChain,
    probe: JSON.parse(JSON.stringify(context.probe)),
    head: context.materialization.gitWorktree.head,
    commonDir: context.materialization.gitWorktree.commonDir,
    command: "git worktree remove --force",
    acknowledgedSeedAuditFailureDiscard: true };
  value.intentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateIntent(value);
}

function createResumeIntent(context, state, sealedPriorChain, createdAt) {
  if (!state || state.active !== true || !state.intent
      || !Array.isArray(sealedPriorChain) || sealedPriorChain.length < 1) {
    Common.fail("material_shop_seed_failure_resume_state_invalid",
      "seed_failure_discard",
      "resume intent requires one active parent and its fully sealed operation chain");
  }
  validateOperationChain(sealedPriorChain, state.intent.runDir,
    state.intent.preparationSha256, state.intent.buildSha256, null, true);
  const sequence = state.intent.sequence + 1;
  const operationChain = sealedPriorChain.map((entry) => JSON.parse(JSON.stringify(entry)));
  operationChain.push({ ordinal: operationChain.length,
    lease: JSON.parse(JSON.stringify(context.probe.operation.lease)),
    leaseArtifact: JSON.parse(JSON.stringify(context.probe.operation.leaseArtifact)),
    outcome: null });
  const value = { schema: INTENT_SCHEMA, createdAt: createdAt || new Date().toISOString(),
    eligibilityKind: ELIGIBILITY_KIND, runId: context.preparation.runId,
    canonicalRoot: Common.CANONICAL_ROOT, runDir: context.preparation.runDir,
    destination: context.preparation.resourcesRoot,
    preparationSha256: context.preparation.preparationSha256,
    materializationSha256: context.materialization.materializationSha256,
    closureSha256: context.closure.closureSha256,
    scopeSha256: context.closure.scope.scopeSha256,
    applicabilitySha256: context.applicability.applicabilitySha256,
    buildSha256: context.build.buildSha256, candidateRoot: context.build.candidateRoot,
    sequence, parentIntent: { name: path.basename(state.markerPath),
      intentSha256: state.intent.intentSha256 }, operationChain,
    probe: JSON.parse(JSON.stringify(context.probe)),
    head: context.materialization.gitWorktree.head,
    commonDir: context.materialization.gitWorktree.commonDir,
    command: "git worktree remove --force",
    acknowledgedSeedAuditFailureDiscard: true };
  value.intentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateIntent(value);
}

function markerNames(runDir) {
  return fs.readdirSync(runDir, { withFileTypes: true }).filter((entry) => entry.isFile()
    && (entry.name === INTENT_NAME
      || new RegExp("^" + RESUME_PREFIX + "[0-9]{4}-[a-f0-9]{16}\\.json$")
        .test(entry.name)
      || new RegExp("^" + RESOLVED_PREFIX + "[a-f0-9]{16}\\.json$").test(entry.name)))
    .map((entry) => entry.name).sort();
}

function loadState(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "seed_failure_discard");
  const names = markerNames(runDir);
  if (names.length === 0) return { runDir, active: false, intent: null,
    markerPath: null, resolvedPath: null, markerNames: [], intents: [] };
  const records = names.map((name) => {
    const markerPath = path.join(runDir, name);
    const intent = validateIntent(Prepare.readJson(markerPath, "seed_failure_discard"));
    return { name, markerPath, intent,
      resolved: name.startsWith(RESOLVED_PREFIX) };
  }).sort((left, right) => left.intent.sequence - right.intent.sequence);
  if (records.filter((entry) => entry.resolved).length > 1
      || new Set(records.map((entry) => entry.intent.sequence)).size !== records.length
      || records.some((entry, index) => entry.intent.sequence !== index)) {
    Common.fail("material_shop_seed_failure_state_invalid", "seed_failure_discard",
      "intent chain has duplicate, missing, or multiple resolved generations");
  }
  records.forEach((entry, index) => {
    const intent = entry.intent;
    const expectedName = entry.resolved ? resolvedName(intent) : intentMarkerName(intent);
    const previous = index > 0 ? records[index - 1] : null;
    if (!samePath(intent.runDir, runDir) || entry.name !== expectedName
        || entry.resolved && index !== records.length - 1
        || index === 0 && intent.parentIntent !== null
        || index > 0 && (intent.parentIntent.name !== previous.name
          || intent.parentIntent.intentSha256 !== previous.intent.intentSha256)
        || previous && (intent.operationChain.length <= previous.intent.operationChain.length
          || previous.intent.operationChain.some((prior, ordinal) => {
            const current = intent.operationChain[ordinal];
            return prior.ordinal !== current.ordinal
              || Evidence.canonicalJson(prior.lease) !== Evidence.canonicalJson(current.lease)
              || Evidence.canonicalJson(prior.leaseArtifact)
                !== Evidence.canonicalJson(current.leaseArtifact)
              || prior.outcome && Evidence.canonicalJson(prior.outcome)
                !== Evidence.canonicalJson(current.outcome)
              || !prior.outcome && current.outcome == null;
          })
          || intent.operationChain.slice(previous.intent.operationChain.length, -1)
            .some((current) => current.outcome == null))) {
      Common.fail("material_shop_seed_failure_state_invalid", "seed_failure_discard",
        "append-only intent generation is foreign, detached, or rewrites prior operations");
    }
  });
  const latest = records[records.length - 1];
  const active = !latest.resolved;
  return { runDir, active, intent: latest.intent, markerPath: latest.markerPath,
    resolvedPath: path.join(runDir, resolvedName(latest.intent)), markerNames: names,
    intents: records.map((entry) => ({ name: entry.name,
      intentSha256: entry.intent.intentSha256, sequence: entry.intent.sequence,
      resolved: entry.resolved })) };
}

function operationClosure(intent) {
  const active = RunOperationLease.readLease(intent.runDir);
  if (active.active) {
    Common.fail("material_shop_seed_failure_operation_busy", "seed_failure_discard",
      "finalizer requires the cleanup mutex to be terminal or explicitly stale-recovered");
  }
  const actual = RunOperationLease.historyMarkers(intent.runDir).map(operationProjection);
  const live = intent.probe.qualifyingLiveTerminal;
  const liveReplay = actual.filter((entry) => entry.name === live.name);
  const outcomes = intent.operationChain.map((entry) => {
    const terminalName = RunOperationLease.terminalName(entry.lease);
    const staleName = RunOperationLease.resolvedName(entry.lease);
    const matches = actual.filter((candidate) =>
      candidate.name === terminalName || candidate.name === staleName);
    if (matches.length !== 1) return null;
    validateOutcome(matches[0], entry.lease, entry.leaseArtifact, intent.runDir);
    if (entry.outcome
        && Evidence.canonicalJson(entry.outcome) !== Evidence.canonicalJson(matches[0])) {
      return null;
    }
    return matches[0];
  });
  const expectedNames = [live.name].concat(outcomes.filter(Boolean)
    .map((entry) => entry.name)).sort();
  const actualNames = actual.map((entry) => entry.name).sort();
  if (liveReplay.length !== 1 || outcomes.some((entry) => !entry)
      || Evidence.canonicalJson(liveReplay[0]) !== Evidence.canonicalJson(live)
      || Evidence.canonicalJson(actualNames) !== Evidence.canonicalJson(expectedNames)) {
    Common.fail("material_shop_seed_failure_operation_drift", "seed_failure_discard",
      "finalizer accepts only the qualifying live terminal and full sealed cleanup chain");
  }
  return { outcome: outcomes[outcomes.length - 1], outcomes, history: actual,
    historySha256: Evidence.sha256Text(Evidence.canonicalJson(actual)) };
}

function replayControlTopology(runDir) {
  const control = Evidence.assertExactDirectory(path.join(runDir, "control"),
    "seed_failure_discard");
  const entries = fs.readdirSync(control, { withFileTypes: true });
  if (Evidence.canonicalJson(entries.map((entry) => entry.name).sort())
        !== Evidence.canonicalJson(["acks", "captures", "requests"])
      || entries.some((entry) => !entry.isDirectory() || entry.isSymbolicLink())) {
    Common.fail("material_shop_seed_failure_control_invalid", "seed_failure_discard",
      "retained control topology differs from the exact three-directory preflight shape");
  }
  entries.forEach((entry) => {
    const child = Evidence.assertExactDirectory(path.join(control, entry.name),
      "seed_failure_discard");
    if (fs.readdirSync(child).length !== 0) {
      Common.fail("material_shop_seed_failure_control_invalid", "seed_failure_discard",
        "retained control directory is no longer empty", { name: entry.name });
    }
  });
  return { directories: ["acks", "captures", "requests"], fileCount: 0 };
}

function replayRetainedEvidence(state, receiptMayExist) {
  const intent = state.intent;
  const closure = operationClosure(intent);
  const expectedTop = intent.probe.runLayout.topLevelCoreNames.concat(
    closure.history.map((entry) => entry.name), state.markerNames);
  if (receiptMayExist && fs.existsSync(path.join(state.runDir, RECEIPT_NAME))) {
    expectedTop.push(RECEIPT_NAME);
  }
  const actualTop = fs.readdirSync(state.runDir, { withFileTypes: true })
    .map((entry) => entry.name).sort();
  expectedTop.sort();
  if (Evidence.canonicalJson(actualTop) !== Evidence.canonicalJson(expectedTop)) {
    Common.fail("material_shop_seed_failure_run_layout_invalid", "seed_failure_discard",
      "finalizer found foreign, missing, admission, raw, or recovery artifacts");
  }
  replayControlTopology(state.runDir);
  intent.probe.runLayout.entries.forEach((entry) => {
    const absolute = path.join(state.runDir, entry.relativePath.replace(/\//g, path.sep));
    if (entry.kind === "directory") {
      Evidence.assertExactDirectory(absolute, "seed_failure_discard");
      if (entry.relativePath !== "control" && fs.readdirSync(absolute).length !== 0) {
        Common.fail("material_shop_seed_failure_control_invalid", "seed_failure_discard",
          "sealed pre-candidate control directory is no longer empty");
      }
      return;
    }
    const file = Materialize.readExactTreeFile(absolute, {
      phase: "seed_failure_discard", maximumBytes: 128 * 1024 * 1024,
    });
    if (file.length !== entry.bytes || file.sha256 !== entry.sha256) {
      Common.fail("material_shop_seed_failure_artifact_drift", "seed_failure_discard",
        "sealed pre-candidate run evidence changed before finalization", {
          relativePath: entry.relativePath,
        });
    }
  });
  const logs = captureRunnerLogs(intent.runId,
    intent.probe.qualifyingLiveTerminal.lease.createdAt);
  if (Evidence.canonicalJson(logs) !== Evidence.canonicalJson(intent.probe.runnerLogs)) {
    Common.fail("material_shop_seed_failure_runner_log_invalid", "seed_failure_discard",
      "derived runner logs drifted after the destructive probe");
  }
  captureProcessAbsence(intent.candidateRoot);
  return closure;
}

function validateReceipt(value, intent) {
  Common.exactKeys(value, ["schema", "startedAt", "completedAt", "eligibilityKind",
    "runId", "destination", "preparationSha256", "materializationSha256",
    "closureSha256", "scopeSha256", "applicabilitySha256", "buildSha256",
    "candidateRoot", "failureCode", "runnerStderrSha256", "qualifyingLiveLeaseSha256",
    "cleanupLeaseSha256", "cleanupOutcomeName", "cleanupOutcomeKind",
    "cleanupOutcomeSha256", "cleanupOperationCount", "operationChainSha256",
    "resumedCleanup", "operationHistorySha256", "probeSha256",
    "removalIntentSha256", "command", "candidateBuilt", "liveLeaseEntered",
    "candidateProcessStarted", "candidateExecuted", "rawEvidenceCreated",
    "worktreeRemoved", "acknowledgedSeedAuditFailureDiscard", "receiptSha256"],
  "material_shop_seed_failure_receipt_invalid", "seed_failure_discard");
  const unsigned = Object.assign({}, value);
  delete unsigned.completedAt;
  delete unsigned.receiptSha256;
  const expected = receiptProjection(intent, operationClosure(intent));
  if (value.schema !== RECEIPT_SCHEMA || !Number.isFinite(Date.parse(value.completedAt))
      || Date.parse(value.completedAt) < Date.parse(intent.createdAt)
      || Evidence.canonicalJson(unsigned) !== Evidence.canonicalJson(expected)
      || value.receiptSha256 !== digestWithout(value, "receiptSha256")) {
    Common.fail("material_shop_seed_failure_receipt_invalid", "seed_failure_discard",
      "seed-audit failure discard receipt is malformed or detached");
  }
  return value;
}

function receiptProjection(intent, closure) {
  const closedOperationChain = intent.operationChain.map((entry, index) => {
    const closed = JSON.parse(JSON.stringify(entry));
    closed.outcome = JSON.parse(JSON.stringify(closure.outcomes[index]));
    return closed;
  });
  return { schema: RECEIPT_SCHEMA, startedAt: intent.createdAt,
    eligibilityKind: ELIGIBILITY_KIND, runId: intent.runId,
    destination: intent.destination, preparationSha256: intent.preparationSha256,
    materializationSha256: intent.materializationSha256,
    closureSha256: intent.closureSha256, scopeSha256: intent.scopeSha256,
    applicabilitySha256: intent.applicabilitySha256, buildSha256: intent.buildSha256,
    candidateRoot: intent.candidateRoot, failureCode: EXPECTED_ERROR.code,
    runnerStderrSha256: intent.probe.runnerLogs.stderr.sha256,
    qualifyingLiveLeaseSha256: intent.probe.qualifyingLiveTerminal.lease.leaseSha256,
    cleanupLeaseSha256: intent.probe.operation.lease.leaseSha256,
    cleanupOutcomeName: closure.outcome.name, cleanupOutcomeKind: closure.outcome.kind,
    cleanupOutcomeSha256: closure.outcome.sha256,
    cleanupOperationCount: intent.operationChain.length,
    operationChainSha256: Evidence.sha256Text(
      Evidence.canonicalJson(closedOperationChain)),
    resumedCleanup: intent.operationChain.length > 1,
    operationHistorySha256: closure.historySha256,
    probeSha256: intent.probe.probeSha256,
    removalIntentSha256: intent.intentSha256, command: intent.command,
    candidateBuilt: true, liveLeaseEntered: true, candidateProcessStarted: false,
    candidateExecuted: false, rawEvidenceCreated: false, worktreeRemoved: true,
    acknowledgedSeedAuditFailureDiscard: true };
}

function receiptFromIntent(intent, closure, completedAt) {
  const value = Object.assign(receiptProjection(intent, closure), {
    completedAt: completedAt || new Date().toISOString(),
  });
  value.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateReceipt(value, intent);
}

function runGitRemove(destination) {
  const result = childProcess.spawnSync("git", ["-C", Common.CANONICAL_ROOT,
    "worktree", "remove", "--force", destination], {
    encoding: "utf8", windowsHide: true, maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    Common.fail("material_shop_seed_failure_remove_failed", "seed_failure_discard",
      "exact Git worktree removal failed", { status: result.status,
        stderr: String(result.stderr || result.error && result.error.message || "")
          .slice(0, 4000) });
  }
}

function assertFinalizeWorktreeAbsent(destination, listedImplementation) {
  const listed = listedImplementation || ((value) =>
    Materialize.worktreeListed(Common.CANONICAL_ROOT, value));
  if (fs.existsSync(destination) || listed(destination)) {
    Common.fail("material_shop_seed_failure_remove_incomplete", "seed_failure_discard",
      "bare finalizer cannot remove a present worktree");
  }
  return { destination: path.resolve(destination), present: false, listed: false };
}

function finalize(runDirValue) {
  const state = loadState(runDirValue);
  if (!state.intent) {
    Common.fail("material_shop_seed_failure_finalize_state_invalid",
      "seed_failure_discard", "finalizer requires one durable special cleanup intent");
  }
  assertFinalizeWorktreeAbsent(state.intent.destination);
  const closure = replayRetainedEvidence(state, true);
  const output = path.join(state.runDir, RECEIPT_NAME);
  if (!state.active) {
    if (!fs.existsSync(output)) Common.fail("material_shop_seed_failure_receipt_missing",
      "seed_failure_discard", "resolved cleanup cannot recreate a missing receipt");
    return validateReceipt(Prepare.readJson(output, "seed_failure_discard"), state.intent);
  }
  const receipt = fs.existsSync(output)
    ? validateReceipt(Prepare.readJson(output, "seed_failure_discard"), state.intent)
    : receiptFromIntent(state.intent, closure);
  if (!fs.existsSync(output)) Materialize.writeJsonAtomicNew(output, receipt);
  replayRetainedEvidence(state, true);
  fs.renameSync(state.markerPath, state.resolvedPath);
  const replay = loadState(state.runDir);
  if (replay.active || !replay.intent
      || Evidence.canonicalJson(replay.intent) !== Evidence.canonicalJson(state.intent)) {
    Common.fail("material_shop_seed_failure_finalize_state_invalid",
      "seed_failure_discard", "cleanup marker archive did not preserve its exact intent");
  }
  replayRetainedEvidence(replay, true);
  return validateReceipt(Prepare.readJson(output, "seed_failure_discard"), replay.intent);
}

function probeEligibilityProjection(probe) {
  const value = JSON.parse(JSON.stringify(probe));
  delete value.operation;
  delete value.probeSha256;
  return value;
}

function assertResumeContext(context, state) {
  const intent = state && state.intent;
  if (!intent || state.active !== true
      || context.preparation.preparationSha256 !== intent.preparationSha256
      || context.materialization.materializationSha256 !== intent.materializationSha256
      || context.closure.closureSha256 !== intent.closureSha256
      || context.closure.scope.scopeSha256 !== intent.scopeSha256
      || context.applicability.applicabilitySha256 !== intent.applicabilitySha256
      || context.build.buildSha256 !== intent.buildSha256
      || !samePath(context.preparation.runDir, intent.runDir)
      || !samePath(context.preparation.resourcesRoot, intent.destination)
      || !samePath(context.build.candidateRoot, intent.candidateRoot)
      || context.materialization.gitWorktree.head !== intent.head
      || !samePath(context.materialization.gitWorktree.commonDir, intent.commonDir)) {
    Common.fail("material_shop_seed_failure_resume_context_invalid",
      "seed_failure_discard",
      "full-context resume differs from the active intent's exact preparation/build/worktree");
  }
  return intent;
}

function removeAfterFreshProbe(context, operationHandle) {
  if (!fs.existsSync(context.preparation.resourcesRoot)
      || !Materialize.worktreeListed(Common.CANONICAL_ROOT,
        context.preparation.resourcesRoot)) {
    Common.fail("material_shop_seed_failure_worktree_split", "seed_failure_discard",
      "filesystem/Git worktree state split before exact removal");
  }
  runGitRemove(context.preparation.resourcesRoot);
  if (fs.existsSync(context.preparation.resourcesRoot)
      || Materialize.worktreeListed(Common.CANONICAL_ROOT,
        context.preparation.resourcesRoot)) {
    Common.fail("material_shop_seed_failure_remove_incomplete", "seed_failure_discard",
      "exact worktree remained after Git removal");
  }
  RunOperationLease.release(operationHandle);
  return finalize(context.preparation.runDir);
}

function resumeDiscard(settings, initial, initialState) {
  assertResumeContext(initial, initialState);
  if (fs.existsSync(path.join(initial.preparation.runDir, RECEIPT_NAME))) {
    Common.fail("material_shop_seed_failure_output_exists", "seed_failure_discard",
      "active pre-remove intent cannot coexist with a cleanup receipt");
  }
  const sealedPriorChain = sealPriorOperationChain(initialState.intent);
  const operationHandle = RunOperationLease.acquire({ runDir: initial.preparation.runDir,
    runId: initial.preparation.runId, mode: "built_only_discard",
    preparationSha256: initial.preparation.preparationSha256,
    buildSha256: initial.build.buildSha256 });
  try {
    const context = loadContext(settings, initialState, sealedPriorChain);
    assertResumeContext(context, initialState);
    if (Evidence.canonicalJson(probeEligibilityProjection(context.probe))
        !== Evidence.canonicalJson(
          probeEligibilityProjection(initialState.intent.probe))) {
      Common.fail("material_shop_seed_failure_resume_evidence_drift",
        "seed_failure_discard",
        "retained pre-candidate evidence changed after the active intent was written");
    }
    const intent = createResumeIntent(context, initialState, sealedPriorChain);
    const markerPath = path.join(context.preparation.runDir, intentMarkerName(intent));
    Materialize.writeJsonAtomicNew(markerPath, intent);
    const freshState = loadState(context.preparation.runDir);
    const fresh = loadContext(settings, freshState, sealedPriorChain);
    assertResumeContext(fresh, freshState);
    if (fresh.probe.probeSha256 !== context.probe.probeSha256
        || Evidence.canonicalJson(fresh.probe) !== Evidence.canonicalJson(context.probe)) {
      Common.fail("material_shop_seed_failure_probe_drift", "seed_failure_discard",
        "resume evidence changed between its two fresh destructive probes");
    }
    return removeAfterFreshProbe(fresh, operationHandle);
  } finally {
    if (operationHandle.active) RunOperationLease.release(operationHandle);
  }
}

function discard(options) {
  const settings = options || {};
  if (settings.acknowledge !== true) {
    Common.fail("material_shop_seed_failure_ack_required", "seed_failure_discard",
      "special pre-candidate failure cleanup requires explicit acknowledgement");
  }
  const initial = loadBaseContext(settings);
  const initialState = loadState(initial.preparation.runDir);
  if (initialState.intent) {
    if (initialState.active) return resumeDiscard(settings, initial, initialState);
    Common.fail("material_shop_seed_failure_manual_recovery_required",
      "seed_failure_discard",
      "resolved special cleanup state forbids a destructive retry");
  }
  if (fs.existsSync(path.join(initial.preparation.runDir, RECEIPT_NAME))) {
    Common.fail("material_shop_seed_failure_output_exists", "seed_failure_discard",
      "special cleanup receipt exists without its required intent chain");
  }
  const priorHistory = preIntentOperationHistory(initial.preparation.runDir,
    initial.preparation.preparationSha256, initial.build.buildSha256);
  captureRunnerLogs(initial.preparation.runId,
    priorHistory.qualifyingLiveTerminal.lease.createdAt);
  const operationHandle = RunOperationLease.acquire({ runDir: initial.preparation.runDir,
    runId: initial.preparation.runId, mode: "built_only_discard",
    preparationSha256: initial.preparation.preparationSha256,
    buildSha256: initial.build.buildSha256 });
  try {
    const context = loadContext(settings, { active: false, markerNames: [] },
      priorHistory.priorOperationChain);
    const intent = createIntent(context, null, priorHistory.priorOperationChain);
    const output = path.join(context.preparation.runDir, RECEIPT_NAME);
    if (fs.existsSync(output)) Common.fail("material_shop_seed_failure_output_exists",
      "seed_failure_discard", "canonical special cleanup receipt already exists");
    Materialize.writeJsonAtomicNew(path.join(context.preparation.runDir, INTENT_NAME), intent);
    const state = loadState(context.preparation.runDir);
    const fresh = loadContext(settings, state, priorHistory.priorOperationChain);
    if (fresh.probe.probeSha256 !== context.probe.probeSha256
        || Evidence.canonicalJson(fresh.probe) !== Evidence.canonicalJson(context.probe)) {
      Common.fail("material_shop_seed_failure_probe_drift", "seed_failure_discard",
        "pre-candidate evidence changed between the two fresh destructive probes");
    }
    return removeAfterFreshProbe(fresh, operationHandle);
  } finally {
    if (operationHandle.active) RunOperationLease.release(operationHandle);
  }
}

function parseArgs(argv) {
  const args = { mode: null, runDir: null, preparation: null, build: null,
    acknowledge: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--discard-seed-audit-pre-candidate-failure") args.mode = "discard";
    else if (argv[index] === "--finalize-seed-audit-failure-discard") args.mode = "finalize";
    else if (argv[index] === "--run-dir") args.runDir = argv[++index];
    else if (argv[index] === "--preparation") args.preparation = argv[++index];
    else if (argv[index] === "--build") args.build = argv[++index];
    else if (argv[index] === "--acknowledge-seed-audit-failure-discard") {
      args.acknowledge = true;
    } else Common.fail("material_shop_seed_failure_argument_unknown",
      "seed_failure_discard", argv[index]);
  }
  if (args.mode === "finalize") {
    if (!args.runDir || args.preparation || args.build || args.acknowledge) {
      Common.fail("material_shop_seed_failure_arguments_invalid", "seed_failure_discard",
        "bare finalizer accepts only the exact run directory");
    }
  } else if (args.mode !== "discard" || !args.preparation || !args.build
      || args.runDir || !args.acknowledge) {
    Common.fail("material_shop_seed_failure_arguments_invalid", "seed_failure_discard",
      "special cleanup requires exact preparation/build and explicit acknowledgement");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const value = args.mode === "finalize" ? finalize(args.runDir) : discard(args);
    process.stdout.write(JSON.stringify({ ok: true,
      status: "pre_candidate_seed_audit_failure_discarded", runId: value.runId,
      receiptSha256: value.receiptSha256 }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  ELIGIBILITY_KIND,
  EMPTY_SHA256,
  EXPECTED_ERROR,
  HISTORICAL_FAILURE_SOURCES,
  INTENT_NAME,
  INTENT_SCHEMA,
  RECEIPT_NAME,
  RECEIPT_SCHEMA,
  RESUME_PREFIX,
  RESOLVED_PREFIX,
  assertFinalizeWorktreeAbsent,
  assertHistoricalRootBug,
  captureCleanupOperation,
  captureCoreRunLayout,
  captureProbe,
  captureRunnerLogs,
  createIntent,
  createResumeIntent,
  discard,
  exactOperatorLogPaths,
  finalize,
  loadBaseContext,
  loadContext,
  loadState,
  operationClosure,
  parseArgs,
  preIntentOperationHistory,
  probeEligibilityProjection,
  qualifyingLiveTerminal,
  receiptFromIntent,
  replayRetainedEvidence,
  replayControlTopology,
  resumeDiscard,
  resolvedName,
  sealPriorOperationChain,
  intentMarkerName,
  validateIntent,
  validateHistoricalFailureSources,
  validateOperationChain,
  validateOutcome,
  validateProbe,
  validateReceipt,
};
