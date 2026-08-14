"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const RuntimeIdentity = require("../../lib/runtime-process-identity");
const RuntimeGuard = require("../lib/runtime-guard");
const Evidence = require("../lib/evidence-artifact");
const ExternalToolchain = require("../lib/playwright-websocket-toolchain");
const Common = require("./common");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const CanonicalProduction = require("./production-closure");
const Protocol = require("./protocol");

const BUILD_SCHEMA = "workbench-live-e2e.material-shop.candidate-build.v2";
const BUILD_FAILURE_SCHEMA = "workbench-live-e2e.material-shop.candidate-build-failure.v3";
const BUILD_FAILURE_NAME = "candidate-build-failure.json";
const CANDIDATE_LEAF = "a5";
const MAXIMUM_FAILURE_TAIL_BYTES = 4096;

function artifact(runDir, reference, phase) {
  const filePath = path.resolve(runDir, String(reference.relativePath || "").replace(/\//g, path.sep));
  if (!Evidence.pathInside(runDir, filePath)) Common.fail("material_shop_artifact_escape", phase, "artifact escaped run directory");
  const file = Evidence.readExactRegularFile(filePath, { phase, maximumBytes: 64 * 1024 * 1024 });
  if (file.sha256 !== reference.sha256 || file.length !== reference.bytes) {
    Common.fail("material_shop_artifact_mismatch", phase, "artifact bytes changed", { filePath });
  }
  try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_artifact_json_invalid", phase, error.message); }
}

function loadPreparation(filePath) {
  const value = Prepare.readJson(filePath, "candidate_build");
  Common.exactKeys(value, ["schema", "createdAt", "runId", "root", "runDir",
    "resourcesRoot", "slots", "scopeSha256", "closureSha256",
    "externalToolchainSha256", "applicabilitySha256", "materializationSha256",
    "planSha256", "artifacts", "boundaries",
    "preparationSha256"], "material_shop_preparation_invalid", "candidate_build");
  const runId = String(value.runId || "");
  const expectedRunDir = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "runs", runId);
  const expectedResources = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    Materialize.MATERIALIZED_DIRECTORY, runId, "resources");
  const normalized = (entry) => path.resolve(String(entry || "")).toLowerCase();
  if (value.schema !== Prepare.PREPARATION_SCHEMA || !Common.ID_RE.test(runId)
      || normalized(value.root) !== normalized(Common.CANONICAL_ROOT)
      || normalized(value.runDir) !== normalized(expectedRunDir)
      || normalized(value.runDir) !== normalized(path.dirname(path.resolve(filePath)))
      || normalized(value.resourcesRoot) !== normalized(expectedResources)
      || value.preparationSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(Prepare.stablePreparation(value)))) {
    Common.fail("material_shop_preparation_invalid", "candidate_build",
      "candidate build is detached from its exact A5 preparation");
  }
  const creation = Materialize.loadCreationState(value.runDir);
  const producer = Materialize.readMaterializationProducer(value.runDir, creation.intent);
  const staleFinalized = producer.kind === "stale_recovery"
    ? Materialize.loadPreparedMaterializationFinalization(value.runDir) : null;
  if (!creation.materialized
      || producer.kind !== "terminal" && !staleFinalized) {
    Common.fail("material_shop_preparation_incomplete", "candidate_build",
      "candidate build requires resolved materialization plus terminal producer or exact stale finalization", {
        creationState: creation.markerName, producerKind: producer.kind,
      });
  }
  return value;
}

function loadExternalToolchain(preparation, closure, phase) {
  const descriptor = artifact(preparation.runDir,
    preparation.artifacts.externalToolchain, phase || "external_toolchain");
  const packageLock = closure.scope.files.find((entry) =>
    entry.relativePath === "launcher/perf/package-lock.json");
  if (!packageLock || descriptor.descriptorSha256 !== preparation.externalToolchainSha256) {
    Common.fail("material_shop_external_toolchain_unbound", phase || "external_toolchain",
      "Playwright WebSocket descriptor is detached from preparation or protected scope");
  }
  return ExternalToolchain.validateDescriptor(descriptor, preparation.root, {
    expectedPackageLock: packageLock,
  });
}

function candidateProjection(preparation) {
  const resourcesRoot = path.resolve(preparation.resourcesRoot || "");
  const candidateBase = path.join(resourcesRoot, "tmp", "runtime-candidates", "v2");
  const candidateRoot = path.join(candidateBase, CANDIDATE_LEAF);
  const budgetProbe = path.join(candidateRoot, "runtime",
    "CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json");
  return { candidateBase, candidateRoot, budgetProbe,
    projectedLength: budgetProbe.length };
}

function candidateContract(preparation) {
  const projection = candidateProjection(preparation);
  const { candidateBase, candidateRoot, budgetProbe } = projection;
  if (!sameDirectChild(candidateRoot, candidateBase) || budgetProbe.length >= 260) {
    Common.fail("material_shop_candidate_path_budget_exceeded", "candidate_build",
      "exact A5 candidate root exceeds the bootstrap MAX_PATH budget: candidateRoot="
        + candidateRoot + ", projected=" + budgetProbe.length + ", maximum=259", {
        candidateRoot, projected: budgetProbe.length, maximum: 259,
      });
  }
  return projection;
}

function uncheckedBuildCommand(preparation) {
  return {
    executable: "powershell.exe",
    args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
      path.join(preparation.resourcesRoot, "automation", "dev.ps1"),
      "-ForceBuild", "-BuildOnly", "-CandidateLeaf", CANDIDATE_LEAF],
    cwd: preparation.resourcesRoot,
  };
}

function buildCommand(preparation) {
  candidateContract(preparation);
  return uncheckedBuildCommand(preparation);
}

function publicCommand(command) {
  return { executable: command.executable, args: command.args.slice(), cwd: command.cwd };
}

function validateExecutedCommand(value, preparation, phase) {
  const label = phase || "candidate_build";
  Common.exactKeys(value, ["executable", "args", "cwd", "stdoutSha256",
    "stderrSha256", "exitCode"], "material_shop_build_command_invalid", label);
  const expected = buildCommand(preparation);
  if (typeof value.executable !== "string" || !Array.isArray(value.args)
      || value.args.some((entry) => typeof entry !== "string") || typeof value.cwd !== "string"
      || Evidence.canonicalJson(publicCommand(value)) !== Evidence.canonicalJson(expected)
      || !Common.SHA256_RE.test(String(value.stdoutSha256 || ""))
      || !Common.SHA256_RE.test(String(value.stderrSha256 || ""))
      || value.exitCode !== 0) {
    Common.fail("material_shop_build_command_invalid", label,
      "candidate build command is not the exact short-leaf BuildOnly invocation");
  }
  return value;
}

function boundedUtf8Tail(value, maximumBytes) {
  const bytes = Buffer.from(String(value || ""), "utf8");
  let start = Math.max(0, bytes.length - maximumBytes);
  while (start < bytes.length && (bytes[start] & 0xc0) === 0x80) start += 1;
  return bytes.subarray(start).toString("utf8");
}

function streamEvidence(value) {
  const bytes = Buffer.from(String(value || ""), "utf8");
  return { bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes),
    tail: boundedUtf8Tail(value, MAXIMUM_FAILURE_TAIL_BYTES) };
}

function stableBuildFailure(value) {
  const unsigned = Object.assign({}, value);
  delete unsigned.failureSha256;
  return unsigned;
}

function validateBuildFailure(value, preparation, materialization, phase) {
  const label = phase || "candidate_build_failure";
  Common.exactKeys(value, ["schema", "createdAt", "startedAt", "preparationSha256",
    "materializationSha256", "externalToolchainSha256", "command", "commandExecuted",
    "failureStage", "failureCode",
    "candidateRoot", "projectedPathLength", "maximumPathLength", "status", "signal",
    "producerExitCode", "spawnError", "validationError", "candidateObserved",
    "candidateAcceptance", "stdout", "stderr", "diagnosticOnly", "candidateBuilt",
    "failureSha256"],
  "material_shop_build_failure_invalid", label);
  [value.stdout, value.stderr].forEach((stream) => {
    Common.exactKeys(stream, ["bytes", "sha256", "tail"],
      "material_shop_build_failure_invalid", label);
  });
  const statusValid = value.status === null
    || (Number.isInteger(value.status) && value.status >= 0);
  const signalValid = value.signal === null
    || (typeof value.signal === "string" && value.signal.length >= 1 && value.signal.length <= 64);
  const spawnErrorValid = value.spawnError === null
    || (typeof value.spawnError === "string" && value.spawnError.length >= 1
      && Buffer.byteLength(value.spawnError, "utf8") <= 1024);
  const validationErrorValid = value.validationError === null
    || (typeof value.validationError === "string" && value.validationError.length >= 1
      && Buffer.byteLength(value.validationError, "utf8") <= 4096);
  const producerExitCodeValid = value.producerExitCode === null
    || (Number.isInteger(value.producerExitCode) && value.producerExitCode >= 0);
  const projection = candidateProjection(preparation);
  const producerFailure = value.failureStage === "producer"
    && value.commandExecuted === true
    && ((Number.isInteger(value.status) && value.status !== 0)
      || value.signal !== null || value.spawnError !== null)
    && value.validationError === null;
  const preflightFailure = value.failureStage === "preflight"
    && value.commandExecuted === false && value.status === null
    && value.signal === null && value.spawnError === null
    && value.producerExitCode === null && value.validationError !== null
    && value.candidateObserved === false
    && value.stdout.bytes === 0 && value.stderr.bytes === 0;
  const postSpawnAcceptanceFailure = value.failureStage === "postspawn_acceptance"
    && value.commandExecuted === true && value.status === 0 && value.producerExitCode === 0
    && value.signal === null && value.spawnError === null && value.validationError !== null;
  if (value.schema !== BUILD_FAILURE_SCHEMA
      || !Number.isFinite(Date.parse(value.createdAt))
      || !Number.isFinite(Date.parse(value.startedAt))
      || value.preparationSha256 !== preparation.preparationSha256
      || value.materializationSha256 !== materialization.materializationSha256
      || value.externalToolchainSha256 !== preparation.externalToolchainSha256
      || Evidence.canonicalJson(value.command)
        !== Evidence.canonicalJson(uncheckedBuildCommand(preparation))
      || typeof value.failureCode !== "string"
      || !/^material_shop_[a-z0-9_]{1,96}$/.test(value.failureCode)
      || value.candidateRoot !== projection.candidateRoot
      || value.projectedPathLength !== projection.projectedLength
      || value.maximumPathLength !== 259
      || !statusValid || !signalValid || !producerExitCodeValid || !spawnErrorValid
      || !validationErrorValid || value.producerExitCode !== value.status
      || typeof value.candidateObserved !== "boolean"
      || (!producerFailure && !preflightFailure && !postSpawnAcceptanceFailure)
      || value.candidateAcceptance !== false
      || value.diagnosticOnly !== true || value.candidateBuilt !== false
      || value.failureSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableBuildFailure(value)))) {
    Common.fail("material_shop_build_failure_invalid", label,
      "candidate build failure artifact is malformed or detached from preparation");
  }
  [value.stdout, value.stderr].forEach((stream) => {
    const tailBytes = typeof stream.tail === "string"
      ? Buffer.byteLength(stream.tail, "utf8") : Number.MAX_SAFE_INTEGER;
    if (!Number.isSafeInteger(stream.bytes) || stream.bytes < 0
        || !Common.SHA256_RE.test(String(stream.sha256 || ""))
        || typeof stream.tail !== "string"
        || tailBytes > MAXIMUM_FAILURE_TAIL_BYTES || tailBytes > stream.bytes
        || (stream.bytes <= MAXIMUM_FAILURE_TAIL_BYTES
          && stream.sha256 !== Evidence.sha256Text(stream.tail))) {
      Common.fail("material_shop_build_failure_invalid", label,
        "candidate build failure stream evidence is malformed");
    }
  });
  return value;
}

function createBuildFailure(preparation, materialization, command, result, startedAt, createdAt,
  options) {
  const settings = options || {};
  const projection = candidateProjection(preparation);
  const failureStage = settings.failureStage || "producer";
  const value = { schema: BUILD_FAILURE_SCHEMA,
    createdAt: createdAt || new Date().toISOString(), startedAt,
    preparationSha256: preparation.preparationSha256,
    materializationSha256: materialization.materializationSha256,
    externalToolchainSha256: preparation.externalToolchainSha256,
    command: publicCommand(command),
    commandExecuted: settings.commandExecuted !== false,
    failureStage,
    failureCode: settings.failureCode || "material_shop_candidate_build_failed",
    candidateRoot: projection.candidateRoot,
    projectedPathLength: projection.projectedLength,
    maximumPathLength: 259,
    status: Number.isInteger(result.status) ? result.status : null,
    signal: result.signal == null ? null : String(result.signal),
    producerExitCode: Number.isInteger(result.status) ? result.status : null,
    spawnError: result.error == null ? null
      : boundedUtf8Tail(result.error.message || result.error, 1024),
    validationError: settings.validationError == null ? null
      : boundedUtf8Tail(settings.validationError.message || settings.validationError, 4096),
    candidateObserved: settings.candidateObserved === true,
    candidateAcceptance: false,
    stdout: streamEvidence(result.stdout), stderr: streamEvidence(result.stderr),
    diagnosticOnly: true, candidateBuilt: false };
  value.failureSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateBuildFailure(value, preparation, materialization, "candidate_build_failure");
}

function writeBuildFailureNew(runDirValue, value) {
  const runDir = path.resolve(runDirValue);
  const output = path.join(runDir, BUILD_FAILURE_NAME);
  const text = JSON.stringify(value, null, 2) + "\n";
  const staged = output + ".staged-" + Evidence.sha256Text(text).slice(0, 16);
  try {
    fs.writeFileSync(staged, text, { encoding: "utf8", mode: 0o600, flag: "wx" });
    // A same-volume hard link is an atomic CreateNew publication: unlike rename on Windows,
    // link never replaces an existing diagnostic artifact.
    fs.linkSync(staged, output);
    fs.unlinkSync(staged);
  } catch (error) {
    if (fs.existsSync(staged)) fs.unlinkSync(staged);
    throw error;
  }
  const file = Evidence.readExactRegularFile(output, {
    phase: "candidate_build_failure", maximumBytes: 16 * 1024 * 1024,
  });
  return { path: file.path, sha256: file.sha256, bytes: file.length };
}

function assertBuildAdmission(liveAdmission) {
  const value = String(liveAdmission || "");
  if (value === "blocked_route_seed_probe_required") {
    Common.fail("material_shop_candidate_build_admission_blocked", "candidate_build",
      "candidate build execution requires seed-resolved route applicability",
      { liveAdmission: value });
  }
  if (!["candidate_ui_probe_required",
    "blocked_environment_computer_use_unavailable"].includes(value)) {
    Common.fail("material_shop_candidate_build_admission_invalid", "candidate_build",
      "candidate build admission state is unknown", { liveAdmission: value });
  }
  return value;
}

function validatedProtectedScopeBootstrap(preparation, options) {
  if (options == null) return null;
  Common.exactKeys(options, ["protectedScopeBootstrap"],
    "material_shop_build_bootstrap_invalid", "candidate_build");
  if (!options.protectedScopeBootstrap) {
    Common.fail("material_shop_build_bootstrap_invalid", "candidate_build",
      "build bootstrap options require one sealed protected-scope ticket");
  }
  const adapter = require("./admit-post-release-finalization");
  if (typeof adapter.validateProtectedScopeBootstrap !== "function") {
    Common.fail("material_shop_build_bootstrap_invalid", "candidate_build",
      "post-release adapter does not expose its frozen bootstrap validator");
  }
  return adapter.validateProtectedScopeBootstrap(options.protectedScopeBootstrap, preparation);
}

function protectedScopeOptions(preparation, candidateRoot, options) {
  const value = { runId: preparation.runId, seedSlot: preparation.slots.seedSlot,
    targetSlot: preparation.slots.targetSlot,
    recoverySlot: preparation.slots.recoverySlot,
    candidateRoot };
  const bootstrap = validatedProtectedScopeBootstrap(preparation, options);
  if (bootstrap) {
    value.supplementalGeneratedOutputs = bootstrap.supplementalGeneratedOutputs.map(
      (entry) => Object.assign({}, entry));
  }
  return value;
}

function loadMaterializedProduction(preparation, closure, candidateRoot, options) {
  if (candidateRoot) {
    Materialize.verifyPostBuildProtectedScope(preparation.resourcesRoot, closure.scope,
      protectedScopeOptions(preparation, candidateRoot, options));
  } else {
    Materialize.verifyScopeFiles(preparation.resourcesRoot, closure.scope);
  }
  const binding = CanonicalProduction.captureMaterializedSharedProducers(
    preparation.resourcesRoot, closure);
  const modulePath = path.join(preparation.resourcesRoot, "tools", "workbench-live-e2e",
    "material-shop", "production-closure.js");
  const resolved = require.resolve(modulePath);
  if (path.resolve(resolved) !== path.resolve(modulePath)) {
    Common.fail("material_shop_materialized_producer_module_invalid", "candidate_build",
      "candidate producer did not resolve from the materialized resources worktree");
  }
  const producer = require(resolved);
  if (!producer || typeof producer.captureCandidateBinding !== "function"
      || typeof producer.verifyCandidateBinding !== "function"
      || typeof producer.verifyProductionClosure !== "function") {
    Common.fail("material_shop_materialized_producer_module_invalid", "candidate_build",
      "materialized production-closure module lacks its exact producer surface");
  }
  return { producer, binding };
}

function validateBuildReceipt(value, preparation, closure, phase, options) {
  const label = phase || "candidate_build";
  Common.exactKeys(value, ["schema", "createdAt", "startedAt", "preparationSha256",
    "materializationSha256", "externalToolchain", "command", "candidateRoot", "candidateIdentity",
    "candidateBinding", "materializedProducerBinding", "liveAdmission", "boundaries",
    "buildSha256"],
  "material_shop_build_receipt_invalid", label);
  const unsigned = Object.assign({}, value);
  delete unsigned.buildSha256;
  if (!value.boundaries || typeof value.boundaries !== "object") {
    Common.fail("material_shop_build_receipt_invalid", label,
      "candidate build receipt boundaries are missing");
  }
  Common.exactKeys(value.boundaries, ["candidateBuilt", "candidateExecuted", "e2eVerified",
    "promoted", "standardEntryVerified"],
  "material_shop_build_receipt_invalid", label);
  if (value.schema !== BUILD_SCHEMA
      || value.preparationSha256 !== preparation.preparationSha256
      || value.materializationSha256 !== preparation.materializationSha256
      || !value.externalToolchain
      || value.externalToolchain.descriptorSha256 !== preparation.externalToolchainSha256
      || value.buildSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))
      || !["candidate_ui_probe_required",
        "blocked_environment_computer_use_unavailable"].includes(value.liveAdmission)
      || value.boundaries.candidateBuilt !== true
      || value.boundaries.candidateExecuted !== false
      || value.boundaries.e2eVerified !== false
      || value.boundaries.promoted !== false
      || value.boundaries.standardEntryVerified !== false
      || typeof value.candidateRoot !== "string") {
    Common.fail("material_shop_build_receipt_invalid", label,
      "candidate build receipt is malformed or detached from preparation");
  }
  validateExecutedCommand(value.command, preparation, label);
  const externalToolchain = loadExternalToolchain(preparation, closure, label);
  if (Evidence.canonicalJson(value.externalToolchain)
      !== Evidence.canonicalJson(externalToolchain)) {
    Common.fail("material_shop_external_toolchain_drift", label,
      "candidate build bound a different Playwright WebSocket toolchain");
  }
  const expectedCandidate = candidateContract(preparation);
  if (path.resolve(value.candidateRoot).toLowerCase()
      !== expectedCandidate.candidateRoot.toLowerCase()) {
    Common.fail("material_shop_build_receipt_invalid", label,
      "candidate build receipt names a non-canonical A5 candidate root");
  }
  const materialized = loadMaterializedProduction(
    preparation, closure, value.candidateRoot, options);
  CanonicalProduction.verifyMaterializedSharedProducers(value.materializedProducerBinding,
    preparation.resourcesRoot, closure);
  if (Evidence.canonicalJson(value.materializedProducerBinding)
      !== Evidence.canonicalJson(materialized.binding)) {
    Common.fail("material_shop_materialized_producer_drift", label,
      "candidate build producer binding differs from the materialized resources worktree");
  }
  materialized.producer.verifyCandidateBinding(value.candidateRoot, value.candidateIdentity,
    closure, value.candidateBinding);
  return value;
}

function loadBuildEnvelope(filePathValue, preparation, phase) {
  const label = phase || "candidate_build";
  const filePath = path.resolve(filePathValue);
  if (path.resolve(path.join(preparation.runDir, "candidate-build.json")).toLowerCase()
      !== filePath.toLowerCase()) {
    Common.fail("material_shop_build_receipt_path_invalid", label,
      "candidate build receipt is outside the exact prepared run");
  }
  const value = Prepare.readJson(filePath, label);
  const unsigned = Object.assign({}, value);
  delete unsigned.buildSha256;
  if (value.schema !== BUILD_SCHEMA
      || value.preparationSha256 !== preparation.preparationSha256
      || !Common.SHA256_RE.test(String(value.buildSha256 || ""))
      || value.buildSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_build_receipt_invalid", label,
      "candidate build envelope is malformed or detached before operation acquisition");
  }
  return value;
}

function loadBuildReceipt(filePath, preparation, closure, phase, options) {
  return validateBuildReceipt(loadBuildEnvelope(filePath, preparation,
    phase || "candidate_build"), preparation, closure, phase || "candidate_build", options);
}

function executeBuild(preparationFile) {
  const preparation = loadPreparation(preparationFile);
  const closure = artifact(preparation.runDir, preparation.artifacts.closure, "candidate_build");
  const materialization = artifact(preparation.runDir,
    preparation.artifacts.materialization, "candidate_build");
  const plan = Protocol.validateControlPlan(artifact(preparation.runDir,
    preparation.artifacts.plan, "candidate_build"));
  const externalToolchain = loadExternalToolchain(preparation, closure, "candidate_build");
  assertBuildAdmission(plan.transportPolicy.liveAdmission);
  Materialize.verifyMaterialization(materialization, closure.scope, {
    ownedBase: materialization.ownedBase, fixtureMode: false,
  });
  const materialized = loadMaterializedProduction(preparation, closure);
  materialized.producer.verifyProductionClosure(closure, { currentTree: false });
  const command = uncheckedBuildCommand(preparation);
  const buildArtifactPath = path.join(preparation.runDir, "candidate-build.json");
  const failureArtifactPath = path.join(preparation.runDir, BUILD_FAILURE_NAME);
  const stagedFailurePrefix = BUILD_FAILURE_NAME + ".staged-";
  if (fs.existsSync(buildArtifactPath) || fs.existsSync(failureArtifactPath)
      || fs.readdirSync(preparation.runDir).some((name) => name.startsWith(stagedFailurePrefix))) {
    Common.fail("material_shop_candidate_build_state_exists", "candidate_build",
      "candidate build receipts are CreateNew and cannot be reused or overwritten");
  }
  const startedAt = new Date().toISOString();
  let candidate;
  try {
    candidate = candidateContract(preparation);
  } catch (error) {
    const failureCode = error && error.code || "material_shop_candidate_preflight_failed";
    const failure = createBuildFailure(preparation, materialization, command, {
      status: null, signal: null, error: null,
      stdout: "", stderr: "",
    }, startedAt, null, { commandExecuted: false, failureStage: "preflight",
      failureCode, validationError: error });
    const failureArtifact = writeBuildFailureNew(preparation.runDir, failure);
    Common.fail(failureCode, "candidate_build",
      String(error && error.message || error) + "; diagnostic="
        + path.basename(failureArtifact.path) + "; failureSha256=" + failure.failureSha256, {
        candidateRoot: failure.candidateRoot,
        projected: failure.projectedPathLength,
        maximum: failure.maximumPathLength,
      });
  }
  const result = childProcess.spawnSync(command.executable, command.args, {
    cwd: command.cwd, encoding: "utf8", windowsHide: true,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    const failure = createBuildFailure(preparation, materialization, command, result, startedAt,
      null, { commandExecuted: true, failureStage: "producer",
        candidateObserved: candidateRootObserved(candidate.candidateRoot),
        failureCode: "material_shop_candidate_build_failed" });
    const failureArtifact = writeBuildFailureNew(preparation.runDir, failure);
    Common.fail("material_shop_candidate_build_failed", "candidate_build",
      "automation/dev.ps1 -ForceBuild -BuildOnly -CandidateLeaf a5 failed; diagnostic="
        + path.basename(failureArtifact.path) + "; failureSha256=" + failure.failureSha256, {
        status: failure.status, signal: failure.signal,
        failureArtifact: path.basename(failureArtifact.path),
        failureSha256: failure.failureSha256,
      });
  }
  try {
    const pointerPath = path.join(preparation.resourcesRoot,
      "tmp", "runtime-dev", "active.v1.json");
    const pointer = Prepare.readJson(pointerPath, "candidate_build");
  Common.exactKeys(pointer, ["schema", "candidateRelativePath", "artifactSourceHash",
    "producerRecipeHash", "toolchainLockHash", "buildIdentityHash", "payloadClosureHash",
    "coreSha256", "activatedAtUtc", "trust"],
  "material_shop_dev_pointer_invalid", "candidate_build");
    const candidateRoot = path.resolve(preparation.resourcesRoot,
      String(pointer.candidateRelativePath || "").replace(/\//g, path.sep));
    const candidateBase = path.join(preparation.resourcesRoot,
      "tmp", "runtime-candidates", "v2");
    if (pointer.schema !== "cf7-local-dev-runtime-selection.v1"
      || !sameDirectChild(candidateRoot, candidateBase)
      || candidateRoot.toLowerCase() !== candidate.candidateRoot.toLowerCase()
      || pointer.buildIdentityHash !== materialization.worktreeBuildIdentity.buildIdentityHash
      || pointer.trust !== "INDEX_ONLY_REVERIFY_BEFORE_EXECUTION") {
      Common.fail("material_shop_dev_pointer_invalid", "candidate_build",
        "local dev candidate pointer is foreign or detached from Worktree identity");
    }
    const identity = RuntimeIdentity.resolveExpectedRuntimeIdentity(
      preparation.resourcesRoot, candidateRoot);
    RuntimeGuard.validateCandidateIdentity(identity, candidateRoot);
    Materialize.verifyPostBuildProtectedScope(preparation.resourcesRoot, closure.scope,
      protectedScopeOptions(preparation, candidateRoot));
    const binding = materialized.producer.captureCandidateBinding(
      candidateRoot, identity, closure);
    const value = {
      schema: BUILD_SCHEMA,
      createdAt: new Date().toISOString(),
      startedAt,
      preparationSha256: preparation.preparationSha256,
      materializationSha256: materialization.materializationSha256,
      externalToolchain,
      command: { executable: command.executable, args: command.args,
        cwd: command.cwd, stdoutSha256: Evidence.sha256Text(String(result.stdout || "")),
        stderrSha256: Evidence.sha256Text(String(result.stderr || "")),
        exitCode: result.status },
      candidateRoot,
      candidateIdentity: RuntimeGuard.publicCandidateIdentity(identity),
      candidateBinding: binding,
      materializedProducerBinding: materialized.binding,
      liveAdmission: plan.transportPolicy.liveAdmission,
      boundaries: { candidateBuilt: true, candidateExecuted: false,
        e2eVerified: false, promoted: false, standardEntryVerified: false },
    };
    value.buildSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
    Prepare.writeJsonNew(buildArtifactPath, value);
    return value;
  } catch (error) {
    const errorCode = String(error && error.code || "");
    const failureCode = /^material_shop_[a-z0-9_]{1,96}$/.test(errorCode)
      ? errorCode : "material_shop_candidate_acceptance_failed";
    const failure = createBuildFailure(preparation, materialization, command, result, startedAt,
      null, { commandExecuted: true, failureStage: "postspawn_acceptance", failureCode,
        validationError: error,
        candidateObserved: candidateRootObserved(candidate.candidateRoot) });
    const failureArtifact = writeBuildFailureNew(preparation.runDir, failure);
    Common.fail(failureCode, "candidate_build",
      String(error && error.message || error) + "; producerExitCode=0; candidateObserved="
        + failure.candidateObserved + "; candidateAcceptance=false; diagnostic="
        + path.basename(failureArtifact.path) + "; failureSha256=" + failure.failureSha256, {
        candidateRoot: failure.candidateRoot,
        failureArtifact: path.basename(failureArtifact.path),
        failureSha256: failure.failureSha256,
      });
  }
}

function sameDirectChild(child, parent) {
  return path.dirname(path.resolve(child)).toLowerCase() === path.resolve(parent).toLowerCase();
}

function candidateRootObserved(candidateRootValue) {
  const candidateRoot = path.resolve(candidateRootValue);
  try {
    const stat = fs.lstatSync(candidateRoot);
    const real = fs.realpathSync.native(candidateRoot);
    return stat.isDirectory() && !stat.isSymbolicLink()
      && path.resolve(real).toLowerCase() === candidateRoot.toLowerCase();
  } catch (_error) {
    return false;
  }
}

function parseArgs(argv) {
  let preparation = null;
  let execute = false;
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--preparation") preparation = argv[++index];
    else if (argv[index] === "--execute-build") execute = true;
    else Common.fail("material_shop_argument_unknown", "candidate_build", "unknown argument", { token: argv[index] });
  }
  if (!preparation) Common.fail("material_shop_preparation_missing", "candidate_build", "--preparation is required");
  return { preparation: path.resolve(preparation), execute };
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const preparation = loadPreparation(args.preparation);
    if (!args.execute) {
      process.stdout.write(JSON.stringify({ ok: true, execute: false,
        command: buildCommand(preparation), stopLine: "no candidate was built" }) + "\n");
      return;
    }
    const value = executeBuild(args.preparation);
    process.stdout.write(JSON.stringify({ ok: true, candidateRoot: value.candidateRoot,
      buildSha256: value.buildSha256, status: "candidate_built" }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  BUILD_FAILURE_NAME,
  BUILD_FAILURE_SCHEMA,
  BUILD_SCHEMA,
  CANDIDATE_LEAF,
  MAXIMUM_FAILURE_TAIL_BYTES,
  assertBuildAdmission,
  boundedUtf8Tail,
  buildCommand,
  candidateContract,
  candidateProjection,
  createBuildFailure,
  executeBuild,
  loadBuildReceipt,
  loadBuildEnvelope,
  loadExternalToolchain,
  loadMaterializedProduction,
  loadPreparation,
  parseArgs,
  protectedScopeOptions,
  sameDirectChild,
  stableBuildFailure,
  streamEvidence,
  uncheckedBuildCommand,
  validateBuildFailure,
  validateBuildReceipt,
  validateExecutedCommand,
  validatedProtectedScopeBootstrap,
  writeBuildFailureNew,
};
