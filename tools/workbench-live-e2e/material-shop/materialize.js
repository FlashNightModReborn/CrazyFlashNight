"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Common = require("./common");
const Scope = require("./scope-manifest");

const RECEIPT_SCHEMA = "workbench-live-e2e.material-shop.materialization.v2";
const MATERIALIZED_DIRECTORY = "materialized";
const PRODUCTION_MODE = "head_worktree_scope_overlay";
const FIXTURE_MODE = "fixture_scope_copy";
const LEGACY_IGNORED_OUTPUT_SCHEMA =
  "workbench-live-e2e.material-shop.ignored-output-inventory.v2";
const IGNORED_OUTPUT_SCHEMA = "workbench-live-e2e.material-shop.ignored-output-inventory.v3";
const A5_RUNTIME_LOG_RELATIVE_PATHS = Object.freeze([
  "logs/bootstrap.log",
  "logs/launcher.log",
  "logs/perf-latest.jsonl",
]);
const A5_WEBVIEW2_USERDATA_RELATIVE_PREFIXES = Object.freeze([
  "launcher/webview2_overlay_userdata/",
  "launcher/webview2_userdata/",
]);
const A5_LAUNCHER_VERSION_MARKER_RELATIVE_PATH =
  "saves/.launcher-version-marker.json";
const SUPPLEMENTAL_GENERATED_OUTPUT_PREFIX =
  "tmp/workbench-live-e2e/offline-recovery-receipts/";
const MAXIMUM_SUPPLEMENTAL_GENERATED_OUTPUTS = 8;
const MAXIMUM_IGNORED_OUTPUT_FILES = 8192;
const MAXIMUM_IGNORED_OUTPUT_BYTES = 2 * 1024 * 1024 * 1024;
// The Launcher is not declared longPathAware. MAX_PATH includes the terminating NUL,
// so every physical file path consumed by the materialized candidate must stay <= 259.
const MAXIMUM_WINDOWS_LEGACY_PATH_LENGTH = 259;
const CREATION_INTENT_SCHEMA = "workbench-live-e2e.material-shop.materialization-create-intent.v1";
const CREATION_INTENT_NAME = "materialization-create-intent.json";
const CREATION_RESOLVED_PREFIX = "materialization-create-resolved-";
const CLEANUP_RECEIPT_SCHEMA = "workbench-live-e2e.material-shop.materialization-cleanup.v2";
const CLEANUP_RECEIPT_NAME = "materialization-cleanup.json";
const CLEANUP_RESOLVED_PREFIX = "materialization-cleanup-resolved-";
const PRODUCER_LEASE_SCHEMA = "workbench-live-e2e.material-shop.materialization-producer-lease.v1";
const PRODUCER_LEASE_NAME = "materialization-producer-lease.json";
const PRODUCER_TERMINAL_PREFIX = "materialization-producer-terminal-";
const PRODUCER_STALE_PREFIX = "materialization-producer-stale-resolved-";
const PREPARATION_FINALIZATION_SCHEMA =
  "workbench-live-e2e.material-shop.preparation-materialization-finalization.v1";
const PREPARATION_FINALIZATION_NAME = "preparation-materialization-finalization.json";
const ACTIVE_PRODUCER_HANDLES = new Map();

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function compareOrdinal(leftValue, rightValue) {
  const left = String(leftValue);
  const right = String(rightValue);
  return left < right ? -1 : left > right ? 1 : 0;
}

function assertMaterializedPathBudget(destinationValue, scope) {
  const destination = path.resolve(destinationValue || "");
  if (!scope || !Array.isArray(scope.files) || scope.files.length < 1) {
    Common.fail("material_shop_materialized_path_budget_invalid", "materialize",
      "materialized path budget requires the full sealed scope file set");
  }
  let longest = null;
  scope.files.forEach((entry) => {
    const resolved = Common.resolveWithin(destination, entry.relativePath, "materialize");
    const projection = { relativePath: resolved.relative, absolutePath: resolved.absolute,
      pathLength: resolved.absolute.length };
    if (!longest || projection.pathLength > longest.pathLength
        || projection.pathLength === longest.pathLength
          && projection.relativePath < longest.relativePath) {
      longest = projection;
    }
  });
  const runId = path.basename(path.dirname(destination));
  const budget = {
    destination,
    runId,
    runIdLength: runId.length,
    longestRelativePath: longest.relativePath,
    longestAbsolutePath: longest.absolutePath,
    longestPathLength: longest.pathLength,
    maximumPathLength: MAXIMUM_WINDOWS_LEGACY_PATH_LENGTH,
    safeRunIdMax: Math.max(0, runId.length
      + MAXIMUM_WINDOWS_LEGACY_PATH_LENGTH - longest.pathLength),
  };
  if (longest.pathLength > MAXIMUM_WINDOWS_LEGACY_PATH_LENGTH) {
    Common.fail("material_shop_materialized_path_budget_exceeded", "materialize",
      "materialized scope exceeds the non-longPathAware Windows path budget: relative="
        + longest.relativePath + ", absolute=" + longest.absolutePath
        + ", projected=" + longest.pathLength
        + ", maximum=" + MAXIMUM_WINDOWS_LEGACY_PATH_LENGTH
        + ", safeRunIdMax=" + budget.safeRunIdMax, budget);
  }
  return budget;
}

function run(command, args, options) {
  const result = childProcess.spawnSync(command, args, Object.assign({
    encoding: "utf8", windowsHide: true, maxBuffer: 64 * 1024 * 1024,
  }, options || {}));
  if (result.error || result.status !== 0) {
    Common.fail("material_shop_materialize_command_failed", "materialize",
      "candidate-ready worktree command failed", {
        command, args, status: result.status,
        stderr: String(result.stderr || result.error && result.error.message || "").slice(0, 4000),
      });
  }
  return String(result.stdout || "").trim();
}

function runGit(root, args) {
  return run("git", ["-C", path.resolve(root)].concat(args));
}

function digestWithout(value, key) {
  const unsigned = Object.assign({}, value);
  delete unsigned[key];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function writeJsonAtomicNew(filePath, value, options) {
  const output = path.resolve(filePath);
  const digest = Evidence.sha256Text(Evidence.canonicalJson(value));
  const staged = output + ".staged-" + digest.slice(0, 16);
  const writer = options && options.writeFile || ((target, bytes) =>
    fs.writeFileSync(target, bytes, { encoding: "utf8", mode: 0o600, flag: "wx" }));
  try {
    writer(staged, JSON.stringify(value, null, 2) + "\n");
    fs.renameSync(staged, output);
  } catch (error) {
    if (fs.existsSync(staged)) fs.unlinkSync(staged);
    throw error;
  }
  return output;
}

function creationResolvedName(intent) {
  return CREATION_RESOLVED_PREFIX + intent.intentSha256.slice(0, 16) + ".json";
}

function cleanupResolvedName(intent) {
  return CLEANUP_RESOLVED_PREFIX + intent.intentSha256.slice(0, 16) + ".json";
}

function materializationMarkerFiles(runDirValue) {
  const runDir = path.resolve(runDirValue);
  return fs.readdirSync(runDir, { withFileTypes: true }).filter((entry) => entry.isFile()
    && (entry.name === CREATION_INTENT_NAME
      || new RegExp("^" + CREATION_RESOLVED_PREFIX + "[a-f0-9]{16}\\.json$").test(entry.name)
      || new RegExp("^" + CLEANUP_RESOLVED_PREFIX + "[a-f0-9]{16}\\.json$").test(entry.name)))
    .map((entry) => entry.name).sort();
}

function materializationStagedFiles(runDirValue) {
  return fs.readdirSync(path.resolve(runDirValue), { withFileTypes: true })
    .filter((entry) => entry.isFile()
      && /^materialization-(?:create-intent|cleanup)\.json\.staged-[a-f0-9]{16}$/.test(
        entry.name)).map((entry) => entry.name).sort();
}

function assertCreationIntentAvailable(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "materialize_recovery");
  const markers = materializationMarkerFiles(runDir);
  const staged = materializationStagedFiles(runDir);
  const receipt = path.join(runDir, CLEANUP_RECEIPT_NAME);
  if (markers.length !== 0 || staged.length !== 0 || fs.existsSync(receipt)) {
    Common.fail("material_shop_materialization_recovery_state_invalid",
      "materialize_recovery", "materialization recovery names must be absent before creation", {
        markers, staged,
      });
  }
  return runDir;
}

function validateCreationIntent(value) {
  Common.exactKeys(value, ["schema", "createdAt", "runId", "root", "runDir",
    "ownedBase", "destination", "head", "scopeSha256", "scopePaths",
    "scopePathsSha256", "commonDir", "removeCommand", "cleanupCommand", "intentSha256"],
  "material_shop_materialization_intent_invalid", "materialize_recovery");
  const root = Common.assertCanonicalRoot(value.root);
  const base = path.resolve(root, Common.OWNED_BASE_RELATIVE);
  const runDir = Evidence.assertOwnedRunDirectory(root, value.runDir,
    Common.OWNED_BASE_RELATIVE, "materialize_recovery");
  const destination = path.resolve(value.destination || "");
  const paths = Array.isArray(value.scopePaths) ? value.scopePaths : [];
  const normalized = paths.map((entry) => Common.normalizeRelative(entry));
  const expectedCommonDir = path.resolve(root, runGit(root, ["rev-parse", "--git-common-dir"]));
  if (value.schema !== CREATION_INTENT_SCHEMA
      || !Number.isFinite(Date.parse(value.createdAt))
      || !Common.ID_RE.test(String(value.runId || ""))
      || path.basename(runDir) !== value.runId
      || !samePath(runDir, path.join(base, "runs", value.runId))
      || !samePath(value.ownedBase, base)
      || !samePath(destination, path.join(base, MATERIALIZED_DIRECTORY,
        value.runId, "resources"))
      || !Common.GIT_OID_RE.test(String(value.head || ""))
      || !Common.SHA256_RE.test(String(value.scopeSha256 || ""))
      || paths.length < 1 || paths.length > Scope.MAXIMUM_FILES
      || Evidence.canonicalJson(paths) !== Evidence.canonicalJson(normalized.slice().sort())
      || new Set(paths.map((entry) => entry.toLowerCase())).size !== paths.length
      || value.scopePathsSha256 !== Evidence.sha256Text(Evidence.canonicalJson(paths))
      || !samePath(value.commonDir, expectedCommonDir)
      || Evidence.canonicalJson(value.removeCommand) !== Evidence.canonicalJson([
        "git", "worktree", "remove", "--force", destination,
      ])
      || Evidence.canonicalJson(value.cleanupCommand) !== Evidence.canonicalJson([
        "node", "tools/workbench-live-e2e/material-shop/materialize.js",
        "--cleanup-failed-materialization", "--run-dir", runDir,
        "--acknowledge-remove-failed-worktree",
      ])
      || value.intentSha256 !== digestWithout(value, "intentSha256")) {
    Common.fail("material_shop_materialization_intent_invalid", "materialize_recovery",
      "materialization creation intent is malformed or outside its exact owned run");
  }
  return value;
}

function createCreationIntent(options) {
  const settings = options || {};
  const paths = settings.scope.files.map((entry) => entry.relativePath).slice().sort();
  const value = { schema: CREATION_INTENT_SCHEMA,
    createdAt: settings.createdAt || new Date().toISOString(), runId: settings.runId,
    root: Common.CANONICAL_ROOT, runDir: path.resolve(settings.runDir),
    ownedBase: path.resolve(settings.ownedBase), destination: path.resolve(settings.destination),
    head: settings.scope.head, scopeSha256: settings.scope.scopeSha256,
    scopePaths: paths,
    scopePathsSha256: Evidence.sha256Text(Evidence.canonicalJson(paths)),
    commonDir: path.resolve(Common.CANONICAL_ROOT,
      runGit(Common.CANONICAL_ROOT, ["rev-parse", "--git-common-dir"])),
    removeCommand: ["git", "worktree", "remove", "--force",
      path.resolve(settings.destination)],
    cleanupCommand: ["node", "tools/workbench-live-e2e/material-shop/materialize.js",
      "--cleanup-failed-materialization", "--run-dir", path.resolve(settings.runDir),
      "--acknowledge-remove-failed-worktree"] };
  value.intentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateCreationIntent(value);
}

function loadCreationState(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "materialize_recovery");
  const names = materializationMarkerFiles(runDir);
  const staged = materializationStagedFiles(runDir);
  if (names.length !== 1 || staged.length !== 0) {
    Common.fail("material_shop_materialization_recovery_state_invalid", "materialize_recovery",
      "exactly one active, materialized, or cleanup-resolved creation marker is required", {
        names, staged,
      });
  }
  const markerPath = path.join(runDir, names[0]);
  const marker = Evidence.readExactRegularFile(markerPath, {
    phase: "materialize_recovery", maximumBytes: 16 * 1024 * 1024,
  });
  let intent;
  try { intent = validateCreationIntent(JSON.parse(marker.bytes.toString("utf8"))); }
  catch (error) {
    if (error && error.code) throw error;
    Common.fail("material_shop_materialization_intent_invalid", "materialize_recovery",
      error.message);
  }
  const expectedCreation = creationResolvedName(intent);
  const expectedCleanup = cleanupResolvedName(intent);
  if (![CREATION_INTENT_NAME, expectedCreation, expectedCleanup].includes(names[0])) {
    Common.fail("material_shop_materialization_recovery_state_invalid", "materialize_recovery",
      "materialization marker name is detached from its sealed intent");
  }
  return { runDir, intent, markerPath, markerName: names[0],
    active: names[0] === CREATION_INTENT_NAME,
    materialized: names[0] === expectedCreation,
    cleanupResolved: names[0] === expectedCleanup,
    creationResolvedPath: path.join(runDir, expectedCreation),
    cleanupResolvedPath: path.join(runDir, expectedCleanup) };
}

function resolveCreationIntent(runDirValue, materialization, scope) {
  const state = loadCreationState(runDirValue);
  if (state.cleanupResolved) {
    Common.fail("material_shop_materialization_already_cleaned", "materialize_recovery",
      "cleaned materialization cannot be resolved as successful");
  }
  if (!materialization || !scope || materialization.mode !== PRODUCTION_MODE
      || !samePath(materialization.destination, state.intent.destination)
      || materialization.head !== state.intent.head
      || materialization.scopeSha256 !== state.intent.scopeSha256
      || scope.scopeSha256 !== state.intent.scopeSha256) {
    Common.fail("material_shop_materialization_resolution_invalid", "materialize_recovery",
      "creation intent cannot resolve without its exact verified materialization");
  }
  const producerKey = path.join(state.runDir, PRODUCER_LEASE_NAME).toLowerCase();
  const producerHandle = ACTIVE_PRODUCER_HANDLES.get(producerKey);
  try {
    verifyMaterialization(materialization, scope, {
      ownedBase: state.intent.ownedBase, fixtureMode: false,
    });
  } catch (error) {
    // A synchronous verification failure ends this producer's write authority;
    // archive the exact lease so the acknowledged failed-worktree cleanup can proceed.
    if (producerHandle && producerHandle.active) releaseMaterializationProducer(producerHandle);
    throw error;
  }
  if (!producerHandle || producerHandle.active !== true
      || Evidence.canonicalJson(producerHandle.intent)
        !== Evidence.canonicalJson(state.intent)) {
    Common.fail("material_shop_materialization_producer_incomplete", "materialize_recovery",
      "successful materialization resolution requires its exact in-process active producer");
  }
  // Archive the creation intent first. Cleanup rejects a materialized marker, so
  // no other process can delete the worktree in the final lease-release window.
  if (state.active) fs.renameSync(state.markerPath, state.creationResolvedPath);
  const producer = releaseMaterializationProducer(producerHandle);
  if (producer.kind !== "terminal") {
    Common.fail("material_shop_materialization_producer_incomplete", "materialize_recovery",
      "successful materialization requires one exact terminal producer lease");
  }
  const replay = loadCreationState(state.runDir);
  if (!replay.materialized
      || Evidence.canonicalJson(replay.intent) !== Evidence.canonicalJson(state.intent)) {
    Common.fail("material_shop_materialization_resolution_invalid", "materialize_recovery",
      "creation marker did not archive the exact successful materialization intent");
  }
  return replay;
}

function readPreparedArtifact(runDir, reference, phase) {
  Common.exactKeys(reference, ["relativePath", "bytes", "sha256"],
    "material_shop_preparation_finalization_invalid", phase);
  const absolute = Common.resolveWithin(runDir, reference.relativePath, phase).absolute;
  const file = Evidence.readExactRegularFile(absolute, {
    phase, maximumBytes: 128 * 1024 * 1024,
  });
  if (file.length !== reference.bytes || file.sha256 !== reference.sha256) {
    Common.fail("material_shop_preparation_finalization_artifact_drift", phase,
      "preparation artifact bytes changed before typed finalization", {
        relativePath: reference.relativePath,
      });
  }
  let value;
  try { value = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_preparation_finalization_artifact_invalid", phase,
      error.message, { relativePath: reference.relativePath });
  }
  return { file, value };
}

function loadPreparedMaterializationContext(runDirValue) {
  const phase = "preparation_finalization";
  const state = loadCreationState(runDirValue);
  if (state.cleanupResolved) {
    Common.fail("material_shop_preparation_finalization_invalid", phase,
      "a cleaned materialization cannot become a completed preparation");
  }
  const preparationPath = path.join(state.runDir, "preparation.json");
  const preparationFile = Evidence.readExactRegularFile(preparationPath, {
    phase, maximumBytes: 16 * 1024 * 1024,
  });
  let preparation;
  try { preparation = JSON.parse(preparationFile.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_preparation_finalization_invalid", phase, error.message);
  }
  const Prepare = require("./prepare");
  Common.exactKeys(preparation, ["schema", "createdAt", "runId", "root", "runDir",
    "resourcesRoot", "slots", "scopeSha256", "closureSha256",
    "externalToolchainSha256", "applicabilitySha256", "materializationSha256",
    "planSha256", "artifacts", "boundaries", "preparationSha256"],
  "material_shop_preparation_finalization_invalid", phase);
  const expectedArtifacts = ["applicability", "authorization", "closure",
    "externalToolchain", "materialization", "plan", "scope"];
  if (preparation.schema !== Prepare.PREPARATION_SCHEMA
      || !Number.isFinite(Date.parse(preparation.createdAt))
      || preparation.runId !== state.intent.runId
      || !samePath(preparation.root, state.intent.root)
      || !samePath(preparation.runDir, state.runDir)
      || !samePath(preparation.resourcesRoot, state.intent.destination)
      || Evidence.canonicalJson(Object.keys(preparation.artifacts).sort())
        !== Evidence.canonicalJson(expectedArtifacts)
      || preparation.preparationSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(Prepare.stablePreparation(preparation)))) {
    Common.fail("material_shop_preparation_finalization_invalid", phase,
      "preparation envelope is incomplete, foreign, or detached from creation intent");
  }
  const artifacts = {};
  expectedArtifacts.forEach((name) => {
    artifacts[name] = readPreparedArtifact(state.runDir, preparation.artifacts[name], phase);
  });
  const closure = artifacts.closure.value;
  const scope = artifacts.scope.value;
  const materialization = artifacts.materialization.value;
  const Production = require("./production-closure");
  Production.verifyProductionClosure(closure, { currentTree: false });
  Scope.verifyScopeManifest(scope, { currentTree: false });
  if (Evidence.canonicalJson(scope) !== Evidence.canonicalJson(closure.scope)
      || preparation.scopeSha256 !== scope.scopeSha256
      || preparation.closureSha256 !== closure.closureSha256
      || preparation.materializationSha256 !== materialization.materializationSha256
      || state.intent.scopeSha256 !== scope.scopeSha256) {
    Common.fail("material_shop_preparation_finalization_invalid", phase,
      "preparation hashes differ from their exact closure/materialization artifacts");
  }
  verifyMaterialization(materialization, scope, {
    ownedBase: state.intent.ownedBase, fixtureMode: false,
  });
  const producer = readMaterializationProducer(state.runDir, state.intent);
  if (producer.kind !== "stale_recovery") {
    Common.fail("material_shop_preparation_finalization_producer_invalid", phase,
      "typed finalization requires an explicitly recovered stale producer", {
        producerKind: producer.kind,
      });
  }
  return { state, preparation, preparationFile, artifacts, closure, scope,
    materialization, producer };
}

function validatePreparedMaterializationFinalization(value, contextValue) {
  const context = contextValue || loadPreparedMaterializationContext(
    value && value.runDir);
  Common.exactKeys(value, ["schema", "finalizedAt", "runId", "runDir",
    "preparationSha256", "preparationArtifactSha256", "materializationSha256",
    "scopeSha256", "intentSha256", "resolvedMarkerName", "producerKind",
    "producerMarkerName", "producerLeaseSha256", "producerArtifactSha256",
    "finalizationSha256"], "material_shop_preparation_finalization_invalid",
  "preparation_finalization");
  const unsigned = Object.assign({}, value);
  delete unsigned.finalizationSha256;
  if (value.schema !== PREPARATION_FINALIZATION_SCHEMA
      || !Number.isFinite(Date.parse(value.finalizedAt))
      || value.runId !== context.preparation.runId
      || !samePath(value.runDir, context.state.runDir)
      || value.preparationSha256 !== context.preparation.preparationSha256
      || value.preparationArtifactSha256 !== context.preparationFile.sha256
      || value.materializationSha256 !== context.materialization.materializationSha256
      || value.scopeSha256 !== context.scope.scopeSha256
      || value.intentSha256 !== context.state.intent.intentSha256
      || value.resolvedMarkerName !== creationResolvedName(context.state.intent)
      || value.producerKind !== "stale_recovery"
      || value.producerMarkerName !== context.producer.name
      || value.producerLeaseSha256 !== context.producer.lease.leaseSha256
      || value.producerArtifactSha256 !== context.producer.artifact.sha256
      || value.finalizationSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_preparation_finalization_invalid", "preparation_finalization",
      "typed preparation finalization receipt is malformed or detached");
  }
  return value;
}

function preparedMaterializationFinalizationReceipt(context, finalizedAt) {
  const value = { schema: PREPARATION_FINALIZATION_SCHEMA,
    finalizedAt: finalizedAt || new Date().toISOString(),
    runId: context.preparation.runId, runDir: context.state.runDir,
    preparationSha256: context.preparation.preparationSha256,
    preparationArtifactSha256: context.preparationFile.sha256,
    materializationSha256: context.materialization.materializationSha256,
    scopeSha256: context.scope.scopeSha256,
    intentSha256: context.state.intent.intentSha256,
    resolvedMarkerName: creationResolvedName(context.state.intent),
    producerKind: context.producer.kind,
    producerMarkerName: context.producer.name,
    producerLeaseSha256: context.producer.lease.leaseSha256,
    producerArtifactSha256: context.producer.artifact.sha256 };
  value.finalizationSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validatePreparedMaterializationFinalization(value, context);
}

function finalizeStalePreparedMaterialization(runDirValue, options) {
  const settings = options || {};
  if (settings.acknowledge !== true) {
    Common.fail("material_shop_preparation_finalization_ack_required",
      "preparation_finalization",
      "stale prepared materialization finalization requires explicit acknowledgement");
  }
  const context = loadPreparedMaterializationContext(runDirValue);
  const output = path.join(context.state.runDir, PREPARATION_FINALIZATION_NAME);
  if (context.state.active && fs.existsSync(output)) {
    Common.fail("material_shop_preparation_finalization_output_exists",
      "preparation_finalization",
      "an active creation intent cannot trust a preexisting finalization receipt");
  }
  if (context.state.materialized && fs.existsSync(output)) {
    const persisted = Evidence.readExactRegularFile(output, {
      phase: "preparation_finalization", maximumBytes: 1024 * 1024,
    });
    let parsed;
    try { parsed = JSON.parse(persisted.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
    catch (error) {
      Common.fail("material_shop_preparation_finalization_invalid",
        "preparation_finalization", error.message);
    }
    return validatePreparedMaterializationFinalization(parsed, context);
  }
  if (context.state.active) {
    fs.renameSync(context.state.markerPath, context.state.creationResolvedPath);
  }
  const replayState = loadCreationState(context.state.runDir);
  if (!replayState.materialized
      || Evidence.canonicalJson(replayState.intent)
        !== Evidence.canonicalJson(context.state.intent)) {
    Common.fail("material_shop_preparation_finalization_invalid",
      "preparation_finalization", "creation intent did not become its exact resolved marker");
  }
  const replayContext = loadPreparedMaterializationContext(context.state.runDir);
  const value = preparedMaterializationFinalizationReceipt(replayContext,
    settings.finalizedAt);
  writeJsonAtomicNew(output, value);
  const persisted = Evidence.readExactRegularFile(output, {
    phase: "preparation_finalization", maximumBytes: 1024 * 1024,
  });
  let parsed;
  try { parsed = JSON.parse(persisted.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_preparation_finalization_invalid",
      "preparation_finalization", error.message);
  }
  return validatePreparedMaterializationFinalization(parsed, replayContext);
}

function loadPreparedMaterializationFinalization(runDirValue) {
  const context = loadPreparedMaterializationContext(runDirValue);
  const output = path.join(context.state.runDir, PREPARATION_FINALIZATION_NAME);
  const file = Evidence.readExactRegularFile(output, {
    phase: "preparation_finalization", maximumBytes: 1024 * 1024,
  });
  let value;
  try { value = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_preparation_finalization_invalid",
      "preparation_finalization", error.message);
  }
  return validatePreparedMaterializationFinalization(value, context);
}

function producerTerminalName(lease) {
  return PRODUCER_TERMINAL_PREFIX + lease.leaseSha256.slice(0, 16) + ".json";
}

function producerStaleName(lease) {
  return PRODUCER_STALE_PREFIX + lease.leaseSha256.slice(0, 16) + ".json";
}

function producerMarkerNames(runDirValue) {
  return fs.readdirSync(path.resolve(runDirValue), { withFileTypes: true })
    .filter((entry) => entry.isFile() && (entry.name === PRODUCER_LEASE_NAME
      || new RegExp("^" + PRODUCER_TERMINAL_PREFIX + "[a-f0-9]{16}\\.json$").test(entry.name)
      || new RegExp("^" + PRODUCER_STALE_PREFIX + "[a-f0-9]{16}\\.json$").test(entry.name)))
    .map((entry) => entry.name).sort();
}

function validateMaterializationProducerLease(value, intent) {
  validateCreationIntent(intent);
  Common.exactKeys(value, ["schema", "createdAt", "runId", "runDir", "destination",
    "intentSha256", "ownerPid", "ownerProcessStartUtcTicks", "ownerNonceSha256",
    "leaseSha256"], "material_shop_materialization_producer_lease_invalid",
  "materialize_recovery");
  if (value.schema !== PRODUCER_LEASE_SCHEMA
      || !Number.isFinite(Date.parse(value.createdAt))
      || value.runId !== intent.runId || !samePath(value.runDir, intent.runDir)
      || !samePath(value.destination, intent.destination)
      || value.intentSha256 !== intent.intentSha256
      || !Number.isInteger(value.ownerPid) || value.ownerPid < 1
      || !/^\d{12,20}$/.test(String(value.ownerProcessStartUtcTicks || ""))
      || !Common.SHA256_RE.test(String(value.ownerNonceSha256 || ""))
      || value.leaseSha256 !== digestWithout(value, "leaseSha256")) {
    Common.fail("material_shop_materialization_producer_lease_invalid", "materialize_recovery",
      "materialization producer lease is malformed or detached from its creation intent");
  }
  return value;
}

function createMaterializationProducerLease(intent, owner) {
  const settings = owner || {};
  const value = { schema: PRODUCER_LEASE_SCHEMA,
    createdAt: settings.createdAt || new Date().toISOString(), runId: intent.runId,
    runDir: intent.runDir, destination: intent.destination,
    intentSha256: intent.intentSha256, ownerPid: settings.ownerPid,
    ownerProcessStartUtcTicks: settings.ownerProcessStartUtcTicks,
    ownerNonceSha256: settings.ownerNonceSha256 };
  value.leaseSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateMaterializationProducerLease(value, intent);
}

function materializationProducerProcessProbe(pid, override) {
  const probe = override || require("./run-operation-lease").processStartProbe;
  return probe(pid);
}

function producerOwnerState(lease, override) {
  const observed = materializationProducerProcessProbe(lease.ownerPid, override);
  if (!observed || !["found", "not_found", "unverifiable"].includes(observed.state)) {
    return { ownerState: "unverifiable", observed: { state: "unverifiable", ticks: null } };
  }
  if (observed.state === "found" && !/^\d{12,20}$/.test(String(observed.ticks || ""))) {
    return { ownerState: "unverifiable", observed: { state: "unverifiable", ticks: null } };
  }
  const ownerState = observed.state === "not_found" ? "not_found"
    : observed.state === "unverifiable" ? "unverifiable"
      : observed.ticks === lease.ownerProcessStartUtcTicks ? "same_process" : "pid_reused";
  return { ownerState, observed };
}

function writeProducerLeaseNew(filePath, value) {
  const bytes = Buffer.from(JSON.stringify(value, null, 2) + "\n", "utf8");
  let descriptor;
  try {
    descriptor = fs.openSync(filePath, "wx");
    let offset = 0;
    while (offset < bytes.length) {
      offset += fs.writeSync(descriptor, bytes, offset, bytes.length - offset, null);
    }
    fs.fsyncSync(descriptor);
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
  }
  return { bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes) };
}

function readMaterializationProducer(runDirValue, intentValue, options) {
  const state = loadCreationState(runDirValue);
  const intent = intentValue || state.intent;
  if (Evidence.canonicalJson(intent) !== Evidence.canonicalJson(state.intent)) {
    Common.fail("material_shop_materialization_producer_lease_invalid", "materialize_recovery",
      "producer lease lookup is detached from the exact creation intent");
  }
  const names = producerMarkerNames(state.runDir);
  if (names.length === 0) return { kind: "absent", active: false,
    runDir: state.runDir, intent, name: null, lease: null, artifact: null,
    ownerState: "absent" };
  if (names.length !== 1) {
    Common.fail("material_shop_materialization_producer_state_invalid", "materialize_recovery",
      "exactly zero or one materialization producer marker is allowed", { names });
  }
  const name = names[0];
  const file = Evidence.readExactRegularFile(path.join(state.runDir, name), {
    phase: "materialize_recovery", maximumBytes: 1024 * 1024,
  });
  let lease;
  try { lease = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_materialization_producer_lease_invalid", "materialize_recovery",
      error.message);
  }
  validateMaterializationProducerLease(lease, intent);
  const kind = name === PRODUCER_LEASE_NAME ? "active"
    : name === producerTerminalName(lease) ? "terminal"
      : name === producerStaleName(lease) ? "stale_recovery" : null;
  if (!kind) {
    Common.fail("material_shop_materialization_producer_state_invalid", "materialize_recovery",
      "materialization producer marker name is detached from its lease");
  }
  const owner = kind === "active"
    ? producerOwnerState(lease, options && options.processProbe)
    : { ownerState: "inactive", observed: null };
  return { kind, active: kind === "active", runDir: state.runDir, intent, name,
    path: path.join(state.runDir, name), lease,
    artifact: { bytes: file.length, sha256: file.sha256 },
    ownerState: owner.ownerState, observed: owner.observed };
}

function acquireMaterializationProducer(runDirValue, options) {
  const settings = options || {};
  const state = loadCreationState(runDirValue);
  if (!state.active || producerMarkerNames(state.runDir).length !== 0) {
    Common.fail("material_shop_materialization_producer_busy", "materialize_recovery",
      "creation intent is not exclusively available to a new producer");
  }
  const current = materializationProducerProcessProbe(process.pid, settings.processProbe);
  if (!current || current.state !== "found" || !/^\d{12,20}$/.test(String(current.ticks || ""))) {
    Common.fail("material_shop_materialization_producer_owner_unavailable", "materialize_recovery",
      "current producer process start identity is unavailable");
  }
  const nonce = require("crypto").randomBytes(32).toString("hex");
  const lease = createMaterializationProducerLease(state.intent, {
    ownerPid: process.pid, ownerProcessStartUtcTicks: current.ticks,
    ownerNonceSha256: Evidence.sha256Text(nonce),
  });
  const leasePath = path.join(state.runDir, PRODUCER_LEASE_NAME);
  let artifact;
  try { artifact = writeProducerLeaseNew(leasePath, lease); }
  catch (error) {
    if (error && error.code === "EEXIST") {
      Common.fail("material_shop_materialization_producer_busy", "materialize_recovery",
        "another materialization producer acquired the creation intent concurrently");
    }
    throw error;
  }
  const handle = { active: true, runDir: state.runDir, intent: state.intent,
    leasePath, lease, nonce, artifact };
  ACTIVE_PRODUCER_HANDLES.set(leasePath.toLowerCase(), handle);
  return handle;
}

function assertMaterializationProducerOwner(handle) {
  if (!handle || handle.active !== true
      || ACTIVE_PRODUCER_HANDLES.get(String(handle.leasePath).toLowerCase()) !== handle
      || Evidence.sha256Text(String(handle.nonce || "")) !== handle.lease.ownerNonceSha256) {
    Common.fail("material_shop_materialization_producer_owner_mismatch", "materialize_recovery",
      "only the exact in-process producer may archive its active lease");
  }
  const current = readMaterializationProducer(handle.runDir, handle.intent);
  if (!current.active || current.ownerState !== "same_process"
      || Evidence.canonicalJson(current.lease) !== Evidence.canonicalJson(handle.lease)
      || current.artifact.bytes !== handle.artifact.bytes
      || current.artifact.sha256 !== handle.artifact.sha256) {
    Common.fail("material_shop_materialization_producer_lease_drift", "materialize_recovery",
      "producer lease bytes or process owner changed before archive");
  }
  return current;
}

function releaseMaterializationProducer(handle) {
  assertMaterializationProducerOwner(handle);
  const terminalPath = path.join(handle.runDir, producerTerminalName(handle.lease));
  if (fs.existsSync(terminalPath)) {
    Common.fail("material_shop_materialization_producer_state_invalid", "materialize_recovery",
      "producer terminal marker already exists");
  }
  fs.renameSync(handle.leasePath, terminalPath);
  handle.active = false;
  ACTIVE_PRODUCER_HANDLES.delete(handle.leasePath.toLowerCase());
  const terminal = readMaterializationProducer(handle.runDir, handle.intent);
  if (terminal.kind !== "terminal"
      || Evidence.canonicalJson(terminal.lease) !== Evidence.canonicalJson(handle.lease)) {
    Common.fail("material_shop_materialization_producer_state_invalid", "materialize_recovery",
      "producer lease did not atomically become its exact terminal marker");
  }
  return terminal;
}

function recoverStaleMaterializationProducer(runDirValue, options) {
  const settings = options || {};
  if (settings.acknowledge !== true) {
    Common.fail("material_shop_materialization_producer_recovery_ack_required",
      "materialize_recovery", "stale producer recovery requires explicit acknowledgement");
  }
  const current = readMaterializationProducer(runDirValue, null, settings);
  if (!current.active || !["not_found", "pid_reused"].includes(current.ownerState)) {
    Common.fail("material_shop_materialization_producer_not_stale", "materialize_recovery",
      "producer owner is active, unverifiable, or no stale lease exists", {
        ownerState: current.ownerState,
      });
  }
  const fresh = readMaterializationProducer(runDirValue, current.intent, settings);
  if (!fresh.active || !["not_found", "pid_reused"].includes(fresh.ownerState)
      || Evidence.canonicalJson(fresh.lease) !== Evidence.canonicalJson(current.lease)
      || fresh.artifact.bytes !== current.artifact.bytes
      || fresh.artifact.sha256 !== current.artifact.sha256) {
    Common.fail("material_shop_materialization_producer_recovery_drift", "materialize_recovery",
      "stale producer lease changed during explicit recovery");
  }
  const resolvedPath = path.join(fresh.runDir, producerStaleName(fresh.lease));
  if (fs.existsSync(resolvedPath)) {
    Common.fail("material_shop_materialization_producer_state_invalid", "materialize_recovery",
      "stale producer recovery marker already exists");
  }
  fs.renameSync(fresh.path, resolvedPath);
  return readMaterializationProducer(fresh.runDir, fresh.intent);
}

function assertMaterializationProducerInactive(runDirValue, intent, options) {
  const value = readMaterializationProducer(runDirValue, intent, options);
  if (value.active) {
    const code = ["not_found", "pid_reused"].includes(value.ownerState)
      ? "material_shop_materialization_producer_recovery_required"
      : "material_shop_materialization_producer_busy";
    Common.fail(code, "materialize_recovery",
      "failed-worktree cleanup cannot race an active or unverified materialization producer", {
        ownerState: value.ownerState, leaseSha256: value.lease.leaseSha256,
      });
  }
  if (!["terminal", "stale_recovery"].includes(value.kind)) {
    Common.fail("material_shop_materialization_producer_evidence_missing", "materialize_recovery",
      "failed-worktree cleanup requires exact inactive producer evidence");
  }
  return value;
}

function assertDirectDirectory(directory, phase) {
  let stat;
  let real;
  const resolved = path.resolve(directory);
  try {
    stat = fs.lstatSync(resolved);
    real = fs.realpathSync.native(resolved);
  } catch (error) {
    Common.fail("material_shop_materialize_directory_missing", phase,
      error.message, { directory: resolved });
  }
  if (!stat.isDirectory() || stat.isSymbolicLink() || !samePath(real, resolved)) {
    Common.fail("material_shop_materialize_directory_invalid", phase,
      "materialization directory must be a direct regular directory", { directory: resolved });
  }
  return resolved;
}

function ensureDirectDirectoryChain(rootValue, directory, phase) {
  const root = assertDirectDirectory(rootValue, phase);
  const target = path.resolve(directory);
  if (!Evidence.pathInside(root, target) && !samePath(root, target)) {
    Common.fail("material_shop_materialize_directory_escape", phase,
      "materialization directory escaped its owned root", { root, target });
  }
  const relative = path.relative(root, target);
  let cursor = root;
  relative.split(path.sep).filter(Boolean).forEach((part) => {
    if (!/^[A-Za-z0-9._-]{1,100}$/.test(part)) {
      Common.fail("material_shop_materialize_directory_name_invalid", phase,
        "materialization directory segment is not closed", { part });
    }
    cursor = path.join(cursor, part);
    if (!fs.existsSync(cursor)) fs.mkdirSync(cursor);
    assertDirectDirectory(cursor, phase);
  });
  return target;
}

function ownedBase(root, override) {
  const canonical = Common.assertCanonicalRoot(root);
  const expected = path.resolve(canonical, Common.OWNED_BASE_RELATIVE);
  const value = override ? path.resolve(override) : expected;
  if (!Evidence.pathInside(canonical, value)
      || (!samePath(value, expected) && !Evidence.pathInside(expected, value))) {
    Common.fail("material_shop_owned_base_invalid", "materialize",
      "materialization owned base must stay under the dedicated workspace subtree",
      { expected, actual: value });
  }
  ensureDirectDirectoryChain(canonical, value, "materialize");
  return value;
}

function assertDestination(base, destination) {
  const materializedBase = ensureDirectDirectoryChain(
    base, path.join(base, MATERIALIZED_DIRECTORY), "materialize");
  const resolved = path.resolve(destination);
  const runDirectory = path.dirname(resolved);
  if (!Evidence.pathInside(materializedBase, resolved)
      || path.basename(resolved).toLowerCase() !== "resources"
      || path.dirname(runDirectory).toLowerCase() !== materializedBase.toLowerCase()
      || !/^[A-Za-z0-9._-]{1,100}$/.test(path.basename(runDirectory))) {
    Common.fail("material_shop_destination_invalid", "materialize",
      "destination must be materialized/<closed-run-id>/resources",
      { materializedBase, destination: resolved });
  }
  ensureDirectDirectoryChain(materializedBase, runDirectory, "materialize");
  if (fs.existsSync(resolved)) {
    Common.fail("material_shop_destination_exists", "materialize",
      "materialization never overwrites or merges an existing destination", { destination: resolved });
  }
  return resolved;
}

function readExactSource(sourceRoot, entry) {
  const resolved = Common.resolveWithin(sourceRoot, entry.relativePath, "materialize");
  const file = Evidence.readExactRegularFile(resolved.absolute, {
    phase: "materialize", maximumBytes: Math.max(entry.bytes, 1),
  });
  if (file.length !== entry.bytes || file.sha256 !== entry.sha256) {
    Common.fail("material_shop_materialize_source_drift", "materialize",
      "source bytes differ from the bound scope manifest", { relativePath: entry.relativePath });
  }
  return file;
}

function ensureDestinationParent(destination, relativePath) {
  const root = assertDirectDirectory(destination, "materialize");
  const resolved = Common.resolveWithin(root, relativePath, "materialize");
  const parts = resolved.relative.split("/").slice(0, -1);
  let cursor = root;
  parts.forEach((part) => {
    // Repository paths are already closed by the exact scope manifest and
    // resolveWithin. Unlike owned control/run directories, valid repository
    // names are not restricted to ASCII.
    cursor = path.join(cursor, part);
    if (!fs.existsSync(cursor)) fs.mkdirSync(cursor);
    assertDirectDirectory(cursor, "materialize");
  });
  const expected = path.dirname(resolved.absolute);
  if (!samePath(cursor, expected)) {
    Common.fail("material_shop_materialize_directory_escape", "materialize",
      "materialized repository parent escaped its bound relative path", {
        destination: root, relativePath: resolved.relative, expected, actual: cursor,
      });
  }
  return cursor;
}

function readExactTreeFile(filePath, options) {
  const settings = options || {};
  const phase = settings.phase || "materialize_verify";
  const maximumBytes = Number(settings.maximumBytes ?? Scope.MAXIMUM_TOTAL_BYTES);
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    Common.fail("material_shop_tree_file_limit_invalid", phase,
      "materialized tree file byte limit is invalid");
  }
  const resolved = path.resolve(filePath);
  let initial;
  let initialReal;
  try {
    initial = fs.lstatSync(resolved);
    initialReal = fs.realpathSync.native(resolved);
  } catch (error) {
    Common.fail("material_shop_tree_file_unavailable", phase, error.message,
      { filePath: resolved });
  }
  if (!initial.isFile() || initial.isSymbolicLink() || !samePath(initialReal, resolved)
      || initial.size < 0 || initial.size > maximumBytes) {
    Common.fail("material_shop_tree_file_invalid", phase,
      "materialized tree entry must be an exact bounded regular file", {
        filePath: resolved, bytes: initial && initial.size,
      });
  }
  let descriptor = null;
  let before;
  let after;
  let bytes;
  let finalStat;
  let finalReal;
  try {
    descriptor = fs.openSync(resolved, "r");
    before = fs.fstatSync(descriptor);
    bytes = fs.readFileSync(descriptor);
    after = fs.fstatSync(descriptor);
    finalStat = fs.lstatSync(resolved);
    finalReal = fs.realpathSync.native(resolved);
  } catch (error) {
    Common.fail("material_shop_tree_file_read_failed", phase, error.message,
      { filePath: resolved });
  } finally {
    if (descriptor !== null) {
      try { fs.closeSync(descriptor); } catch (_error) {}
    }
  }
  const sameIdentity = String(before.dev) === String(after.dev)
    && String(before.ino) === String(after.ino)
    && String(after.dev) === String(finalStat.dev)
    && String(after.ino) === String(finalStat.ino);
  if (!before.isFile() || !after.isFile() || !finalStat.isFile()
      || finalStat.isSymbolicLink() || !samePath(finalReal, resolved) || !sameIdentity
      || before.size !== after.size || after.size !== finalStat.size
      || bytes.length !== after.size || before.mtimeMs !== after.mtimeMs
      || before.ctimeMs !== after.ctimeMs || bytes.length < 0
      || bytes.length > maximumBytes) {
    Common.fail("material_shop_tree_file_changed_during_read", phase,
      "materialized tree file identity or bytes changed during capture", {
        filePath: resolved,
      });
  }
  return { path: resolved, bytes, length: bytes.length,
    sha256: Evidence.sha256Bytes(bytes) };
}

function collectDestinationFiles(destination) {
  const output = [];
  function walk(directory, relative) {
    fs.readdirSync(directory, { withFileTypes: true }).slice()
      .sort((left, right) => left.name.localeCompare(right.name)).forEach((entry) => {
        const childRelative = relative ? relative + "/" + entry.name : entry.name;
        if (!relative && entry.name === ".git") return;
        const child = Common.resolveWithin(destination, childRelative, "materialize_verify");
        if (entry.isSymbolicLink()) {
          Common.fail("material_shop_materialize_reparse_forbidden", "materialize_verify",
            "materialized tree contains a symbolic link", { relativePath: childRelative });
        }
        if (entry.isDirectory()) {
          assertDirectDirectory(child.absolute, "materialize_verify");
          walk(child.absolute, childRelative);
        } else if (entry.isFile()) {
          const file = readExactTreeFile(child.absolute, {
            phase: "materialize_verify", maximumBytes: Scope.MAXIMUM_TOTAL_BYTES,
          });
          output.push({ relativePath: childRelative, bytes: file.length, sha256: file.sha256 });
        } else {
          Common.fail("material_shop_materialize_entry_invalid", "materialize_verify",
            "materialized tree contains a non-file entry", { relativePath: childRelative });
        }
      });
  }
  walk(assertDirectDirectory(destination, "materialize_verify"), "");
  return output.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
}

function filesDigest(files) {
  return Evidence.sha256Text(Evidence.canonicalJson(files.map((entry) => ({
    relativePath: entry.relativePath, bytes: entry.bytes, sha256: entry.sha256,
  }))));
}

function worktreeIdentity(destination, expectedHead) {
  const inside = runGit(destination, ["rev-parse", "--is-inside-work-tree"]);
  const topLevel = path.resolve(runGit(destination, ["rev-parse", "--show-toplevel"]));
  const head = runGit(destination, ["rev-parse", "HEAD"]).toLowerCase();
  const commonDir = path.resolve(destination,
    runGit(destination, ["rev-parse", "--git-common-dir"]));
  const gitDir = path.resolve(destination, runGit(destination, ["rev-parse", "--git-dir"]));
  const symbolic = childProcess.spawnSync("git", ["-C", destination,
    "symbolic-ref", "-q", "HEAD"], {
    encoding: "utf8", windowsHide: true, maxBuffer: 1024 * 1024,
  });
  const detached = !symbolic.error && symbolic.status === 1
    && String(symbolic.stdout || "").trim() === "";
  const gitFile = Evidence.readExactRegularFile(path.join(destination, ".git"), {
    phase: "materialize_verify", maximumBytes: 16 * 1024,
  });
  if (inside !== "true" || !samePath(topLevel, destination) || head !== expectedHead
      || !detached || !fs.existsSync(commonDir) || !fs.existsSync(gitDir)
      || !Evidence.pathInside(commonDir, gitDir)) {
    Common.fail("material_shop_git_worktree_invalid", "materialize_verify",
      "materialized resources is not the exact detached HEAD Git worktree", {
        inside, topLevel, destination, head, expectedHead, commonDir, gitDir, detached,
      });
  }
  return { inside: true, detached: true, topLevel, head, commonDir, gitDir,
    gitFileSha256: gitFile.sha256, gitFileBytes: gitFile.length };
}

function worktreeListed(root, destination) {
  const target = path.resolve(destination).toLowerCase();
  return runGit(root, ["worktree", "list", "--porcelain"])
    .split(/\r?\n/).filter((line) => line.startsWith("worktree "))
    .some((line) => path.resolve(line.slice("worktree ".length)).toLowerCase() === target);
}

function cleanupPresence(presentValue, listedValue) {
  const present = presentValue === true;
  const listed = listedValue === true;
  if (present !== listed) {
    Common.fail("material_shop_materialization_cleanup_partial_state",
      "materialize_recovery", "filesystem and Git disagree about the failed worktree");
  }
  return present ? "present" : "absent";
}

function assertCleanupDirtyPaths(intent, status) {
  validateCreationIntent(intent);
  const value = status || {};
  const staged = Array.isArray(value.staged) ? value.staged : [];
  const modified = Array.isArray(value.modified) ? value.modified : [];
  const untracked = Array.isArray(value.untracked) ? value.untracked : [];
  const ignored = Array.isArray(value.ignored) ? value.ignored : [];
  const allowed = new Set(intent.scopePaths.map((entry) => entry.toLowerCase()));
  const foreign = Array.from(new Set(modified.concat(untracked, ignored)
    .map((entry) => Common.normalizeRelative(entry))))
    .filter((entry) => !allowed.has(entry.toLowerCase())).sort();
  if (staged.length !== 0 || foreign.length !== 0) {
    Common.fail("material_shop_materialization_cleanup_tree_invalid", "materialize_recovery",
      "failed materialization contains staged or scope-external bytes", {
        staged, foreign,
      });
  }
  return { modified, untracked, ignored };
}

function verifyFailedMaterializationWorktree(intent) {
  validateCreationIntent(intent);
  const destination = path.resolve(intent.destination);
  const base = path.resolve(intent.ownedBase);
  [base, path.join(base, MATERIALIZED_DIRECTORY), path.dirname(destination), destination]
    .forEach((entry) => assertDirectDirectory(entry, "materialize_recovery"));
  const identity = worktreeIdentity(destination, intent.head);
  if (!samePath(identity.commonDir, intent.commonDir)) {
    Common.fail("material_shop_materialization_cleanup_identity_invalid",
      "materialize_recovery", "failed worktree commonDir differs from its creation intent");
  }
  const gitFile = Evidence.readExactRegularFile(path.join(destination, ".git"), {
    phase: "materialize_recovery", maximumBytes: 16 * 1024,
  });
  const match = /^gitdir: ([^\r\n]+)\r?\n?$/.exec(gitFile.bytes.toString("utf8"));
  if (!match || !samePath(path.resolve(destination, match[1]), identity.gitDir)) {
    Common.fail("material_shop_materialization_cleanup_identity_invalid",
      "materialize_recovery", "worktree administrative backpointer is not exact");
  }
  const adminBackpointer = Evidence.readExactRegularFile(path.join(identity.gitDir, "gitdir"), {
    phase: "materialize_recovery", maximumBytes: 16 * 1024,
  });
  const adminTarget = adminBackpointer.bytes.toString("utf8").trim();
  if (!adminTarget || !samePath(path.resolve(identity.gitDir, adminTarget),
    path.join(destination, ".git"))) {
    Common.fail("material_shop_materialization_cleanup_identity_invalid",
      "materialize_recovery", "Git administrative directory does not point back to destination");
  }
  const staged = gitPathSet(destination,
    ["diff", "--cached", "--name-only", "-z", "HEAD", "--"]);
  const modified = gitPathSet(destination,
    ["diff", "--no-ext-diff", "--name-only", "-z", "HEAD", "--"]);
  const untracked = gitPathSet(destination,
    ["ls-files", "--others", "--exclude-standard", "-z"]);
  const ignored = gitPathSet(destination,
    ["ls-files", "--others", "--ignored", "--exclude-standard", "-z"]);
  assertCleanupDirtyPaths(intent, { staged, modified, untracked, ignored });
  const files = collectDestinationFiles(destination);
  return { identity, modified, untracked, ignored,
    fileCount: files.length,
    totalBytes: files.reduce((sum, entry) => sum + entry.bytes, 0),
    filesSha256: filesDigest(files) };
}

function assertStableCleanupProbes(first, second) {
  if (!first || !second
      || Evidence.canonicalJson(first) !== Evidence.canonicalJson(second)) {
    Common.fail("material_shop_materialization_cleanup_tree_invalid",
      "materialize_recovery", "failed worktree changed between cleanup safety probes");
  }
  return second;
}

function cleanupReceiptFromIntent(intent, producer, completedAt) {
  if (!producer || !["terminal", "stale_recovery"].includes(producer.kind)) {
    Common.fail("material_shop_materialization_producer_evidence_missing", "materialize_recovery",
      "cleanup receipt requires one exact inactive producer marker");
  }
  const value = { schema: CLEANUP_RECEIPT_SCHEMA,
    completedAt: completedAt || new Date().toISOString(), runId: intent.runId,
    destination: intent.destination, intentSha256: intent.intentSha256,
    head: intent.head, scopeSha256: intent.scopeSha256,
    producerKind: producer.kind, producerMarkerName: producer.name,
    producerLeaseSha256: producer.lease.leaseSha256,
    producerArtifactSha256: producer.artifact.sha256,
    removeCommand: intent.removeCommand, worktreeAbsent: true };
  value.cleanupSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateCleanupReceipt(value, intent, producer);
}

function validateCleanupReceipt(value, intent, producerValue) {
  validateCreationIntent(intent);
  Common.exactKeys(value, ["schema", "completedAt", "runId", "destination",
    "intentSha256", "head", "scopeSha256", "producerKind", "producerMarkerName",
    "producerLeaseSha256", "producerArtifactSha256", "removeCommand",
    "worktreeAbsent", "cleanupSha256"],
  "material_shop_materialization_cleanup_receipt_invalid",
  "materialize_recovery");
  const unsigned = Object.assign({}, value);
  delete unsigned.cleanupSha256;
  const producer = producerValue || readMaterializationProducer(intent.runDir, intent);
  if (value.schema !== CLEANUP_RECEIPT_SCHEMA
      || !Number.isFinite(Date.parse(value.completedAt))
      || value.runId !== intent.runId || !samePath(value.destination, intent.destination)
      || value.intentSha256 !== intent.intentSha256 || value.head !== intent.head
      || value.scopeSha256 !== intent.scopeSha256
      || !producer || !["terminal", "stale_recovery"].includes(producer.kind)
      || value.producerKind !== producer.kind
      || value.producerMarkerName !== producer.name
      || value.producerLeaseSha256 !== producer.lease.leaseSha256
      || value.producerArtifactSha256 !== producer.artifact.sha256
      || Evidence.canonicalJson(value.removeCommand)
        !== Evidence.canonicalJson(intent.removeCommand)
      || value.worktreeAbsent !== true
      || value.cleanupSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_materialization_cleanup_receipt_invalid",
      "materialize_recovery", "cleanup receipt is malformed or detached from its intent");
  }
  return value;
}

function readCleanupReceipt(filePath, intent, producer) {
  const file = Evidence.readExactRegularFile(filePath, {
    phase: "materialize_recovery", maximumBytes: 1024 * 1024,
  });
  try { return validateCleanupReceipt(JSON.parse(file.bytes.toString("utf8")), intent, producer); }
  catch (error) {
    if (error && error.code) throw error;
    Common.fail("material_shop_materialization_cleanup_receipt_invalid",
      "materialize_recovery", error.message);
  }
}

function cleanupFailedMaterialization(runDirValue, options) {
  const settings = options || {};
  if (settings.acknowledge !== true) {
    Common.fail("material_shop_materialization_cleanup_ack_required", "materialize_recovery",
      "exact failed-worktree cleanup requires explicit acknowledgement");
  }
  const state = loadCreationState(runDirValue);
  const intent = state.intent;
  const receiptPath = path.join(state.runDir, CLEANUP_RECEIPT_NAME);
  if (fs.existsSync(path.join(state.runDir, "preparation.json"))) {
    Common.fail("material_shop_materialization_cleanup_preparation_exists",
      "materialize_recovery", "a completed preparation cannot be discarded by recovery cleanup");
  }
  const present = fs.existsSync(intent.destination);
  const listed = worktreeListed(intent.root, intent.destination);
  cleanupPresence(present, listed);
  if (state.cleanupResolved) {
    if (present || !fs.existsSync(receiptPath)) {
      Common.fail("material_shop_materialization_cleanup_state_invalid",
        "materialize_recovery", "resolved cleanup is missing its exact terminal state");
    }
    return readCleanupReceipt(receiptPath, intent);
  }
  if (state.materialized) {
    Common.fail("material_shop_materialization_cleanup_completed_materialization",
      "materialize_recovery",
      "a resolved materialization cannot enter failed-worktree cleanup without a preparation outcome");
  }
  if (fs.existsSync(receiptPath) && present) {
    Common.fail("material_shop_materialization_cleanup_state_invalid",
      "materialize_recovery", "cleanup receipt cannot predate exact worktree removal");
  }
  const producerBefore = assertMaterializationProducerInactive(state.runDir, intent,
    settings.producerOptions);
  if (present) {
    const verified = verifyFailedMaterializationWorktree(intent);
    const fresh = verifyFailedMaterializationWorktree(intent);
    assertStableCleanupProbes(verified, fresh);
    const producerFresh = assertMaterializationProducerInactive(state.runDir, intent,
      settings.producerOptions);
    if (producerFresh.kind !== producerBefore.kind
        || producerFresh.name !== producerBefore.name
        || producerFresh.artifact.sha256 !== producerBefore.artifact.sha256
        || Evidence.canonicalJson(producerFresh.lease)
          !== Evidence.canonicalJson(producerBefore.lease)) {
      Common.fail("material_shop_materialization_producer_recovery_drift",
        "materialize_recovery", "inactive producer evidence changed before worktree removal");
    }
    const remover = settings.removeWorktree || (() =>
      runGit(intent.root, ["worktree", "remove", "--force", intent.destination]));
    remover(intent);
  }
  if (fs.existsSync(intent.destination) || worktreeListed(intent.root, intent.destination)) {
    Common.fail("material_shop_materialization_cleanup_incomplete", "materialize_recovery",
      "exact failed worktree remains after cleanup");
  }
  const receipt = fs.existsSync(receiptPath)
    ? readCleanupReceipt(receiptPath, intent, producerBefore)
      : cleanupReceiptFromIntent(intent, producerBefore);
  if (!fs.existsSync(receiptPath)) {
    writeJsonAtomicNew(receiptPath, receipt, { writeFile: settings.writeReceipt });
  }
  if (fs.existsSync(state.cleanupResolvedPath)) {
    Common.fail("material_shop_materialization_cleanup_state_invalid",
      "materialize_recovery", "active/materialized and cleanup-resolved markers coexist");
  }
  fs.renameSync(state.markerPath, state.cleanupResolvedPath);
  const replay = loadCreationState(state.runDir);
  if (!replay.cleanupResolved
      || Evidence.canonicalJson(replay.intent) !== Evidence.canonicalJson(intent)) {
    Common.fail("material_shop_materialization_cleanup_state_invalid",
      "materialize_recovery", "cleanup marker archive did not preserve the exact intent");
  }
  return readCleanupReceipt(receiptPath, intent, producerBefore);
}

function captureWorktreeBuildIdentity(destination) {
  const commonPath = path.join(destination, "tools", "runtime-build-v2-common.ps1");
  const escapedRoot = destination.replace(/'/g, "''");
  const escapedCommon = commonPath.replace(/'/g, "''");
  const script = "$ErrorActionPreference='Stop'; . '" + escapedCommon
    + "'; $v=Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot '" + escapedRoot
    + "' -Mode Worktree; $v|ConvertTo-Json -Compress";
  let value;
  try { value = JSON.parse(run("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass",
    "-Command", script], { cwd: destination })); }
  catch (error) {
    if (error && error.code) throw error;
    Common.fail("material_shop_worktree_identity_invalid", "materialize_verify",
      "Worktree build identity preflight did not return JSON", { message: error.message });
  }
  Common.exactKeys(value, ["schema", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "policyHash", "buildIdentityHash"],
  "material_shop_worktree_identity_invalid", "materialize_verify");
  if (value.schema !== "cf7-runtime-build-identity.v2"
      || [value.artifactSourceHash, value.producerRecipeHash, value.toolchainLockHash,
        value.policyHash, value.buildIdentityHash]
        .some((entry) => !/^[A-F0-9]{64}$/.test(String(entry || "")))) {
    Common.fail("material_shop_worktree_identity_invalid", "materialize_verify",
      "materialized resources failed the canonical Worktree identity contract");
  }
  value.identitySha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function gitPathSet(destination, args) {
  const output = runGit(destination, args);
  return output ? output.split("\0").filter(Boolean)
    .map((entry) => entry.replace(/\\/g, "/")).sort(compareOrdinal) : [];
}

function ignoredOutputPolicyIdentity(destinationValue, options) {
  const settings = options || {};
  const destination = path.resolve(destinationValue);
  const candidateRoot = path.resolve(settings.candidateRoot || "");
  const runId = String(settings.runId || "");
  const scope = Scope.verifyScopeManifest(settings.scope, { currentTree: false });
  if (!Evidence.pathInside(destination, candidateRoot)
      || !Common.ID_RE.test(runId)) {
    Common.fail("material_shop_ignored_output_policy_invalid", "materialize_verify",
      "ignored-output inventory requires exact candidate and run identities");
  }
  const candidateRelativeRoot = path.relative(destination, candidateRoot).replace(/\\/g, "/");
  if (!candidateRelativeRoot.startsWith("tmp/runtime-candidates/v2/")
      || candidateRelativeRoot.split("/").length !== 4) {
    Common.fail("material_shop_ignored_output_policy_invalid", "materialize_verify",
      "candidate output is outside the exact runtime-candidates leaf");
  }
  return { settings, runId, candidateRelativeRoot, scope };
}

function legacyIgnoredOutputPolicy(destinationValue, options) {
  const identity = ignoredOutputPolicyIdentity(destinationValue, options);
  const seedSlot = String(identity.settings.seedSlot || "");
  if (!Common.SEED_SLOT_RE.test(seedSlot)) {
    Common.fail("material_shop_ignored_output_policy_invalid", "materialize_verify",
      "legacy ignored-output inventory requires the exact seed identity");
  }
  return {
    runId: identity.runId,
    candidateRelativeRoot: identity.candidateRelativeRoot,
    seedRelativePath: "saves/" + seedSlot + ".json",
    internalRunPrefix: "tmp/workbench-live-e2e/material-shop/" + identity.runId + "/",
    pointerRelativePath: "tmp/runtime-dev/active.v1.json",
    protectedScopeSha256: identity.scope.scopeSha256,
  };
}

function normalizeSupplementalGeneratedOutputs(options) {
  const supplied = options && options.supplementalGeneratedOutputs;
  if (supplied == null) return [];
  if (!Array.isArray(supplied) || supplied.length < 1
      || supplied.length > MAXIMUM_SUPPLEMENTAL_GENERATED_OUTPUTS) {
    Common.fail("material_shop_ignored_output_policy_invalid", "materialize_verify",
      "supplemental generated outputs require one bounded exact descriptor set");
  }
  const values = supplied.map((entry) => {
    Common.exactKeys(entry, ["relativePath", "bytes", "sha256"],
      "material_shop_ignored_output_policy_invalid", "materialize_verify");
    const relativePath = Common.normalizeRelative(entry.relativePath);
    if (!relativePath.startsWith(SUPPLEMENTAL_GENERATED_OUTPUT_PREFIX)
        || !/^[A-Za-z0-9._~-]+\.json$/.test(
          relativePath.slice(SUPPLEMENTAL_GENERATED_OUTPUT_PREFIX.length))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || entry.bytes > 512 * 1024 * 1024
        || !Common.SHA256_RE.test(String(entry.sha256 || ""))) {
      Common.fail("material_shop_ignored_output_policy_invalid", "materialize_verify",
        "supplemental generated output is not one exact offline-inspection receipt", {
          relativePath,
        });
    }
    return { relativePath, bytes: entry.bytes, sha256: entry.sha256 };
  }).sort((left, right) => compareOrdinal(left.relativePath, right.relativePath));
  if (values.some((entry, index) => index > 0
      && values[index - 1].relativePath.toLowerCase() === entry.relativePath.toLowerCase())) {
    Common.fail("material_shop_ignored_output_policy_invalid", "materialize_verify",
      "supplemental generated output descriptors must be unique");
  }
  return values;
}

function ignoredOutputPolicy(destinationValue, options) {
  const identity = ignoredOutputPolicyIdentity(destinationValue, options);
  const slots = Common.assertDedicatedSlots(identity.settings.seedSlot,
    identity.settings.targetSlot, identity.settings.recoverySlot);
  return {
    runId: identity.runId,
    candidateRelativeRoot: identity.candidateRelativeRoot,
    seedRelativePath: "saves/" + slots.seedSlot + ".json",
    targetRelativePath: "saves/" + slots.targetSlot + ".json",
    recoveryRelativePath: "saves/" + slots.recoverySlot + ".json",
    launcherVersionMarkerRelativePath: A5_LAUNCHER_VERSION_MARKER_RELATIVE_PATH,
    runtimeLogRelativePaths: A5_RUNTIME_LOG_RELATIVE_PATHS.slice(),
    webView2UserDataRelativePrefixes: A5_WEBVIEW2_USERDATA_RELATIVE_PREFIXES.slice(),
    supplementalGeneratedOutputs: normalizeSupplementalGeneratedOutputs(identity.settings),
    internalRunPrefix: "tmp/workbench-live-e2e/material-shop/" + identity.runId + "/",
    pointerRelativePath: "tmp/runtime-dev/active.v1.json",
    protectedScopeSha256: identity.scope.scopeSha256,
  };
}

function classifyIgnoredOutputPath(relativePathValue, policy, scopeValue) {
  const relativePath = Common.normalizeRelative(relativePathValue);
  const scope = Scope.verifyScopeManifest(scopeValue, { currentTree: false });
  if (scope.scopeSha256 !== policy.protectedScopeSha256) {
    Common.fail("material_shop_ignored_output_policy_invalid", "materialize_verify",
      "ignored-output policy is detached from the exact protected scope");
  }
  const protectedEntry = scope.files.find((entry) => entry.relativePath === relativePath);
  if (protectedEntry) {
    return { relativePath, kind: "protected_scope_input", protectedEntry };
  }
  const exactGeneratedPaths = [policy.pointerRelativePath, policy.seedRelativePath,
    policy.targetRelativePath, policy.recoveryRelativePath,
    policy.launcherVersionMarkerRelativePath].filter(Boolean);
  const runtimeLogRelativePaths = Array.isArray(policy.runtimeLogRelativePaths)
    ? policy.runtimeLogRelativePaths : [];
  const webView2UserDataRelativePrefixes =
    Array.isArray(policy.webView2UserDataRelativePrefixes)
      ? policy.webView2UserDataRelativePrefixes : [];
  const supplementalEntry = Array.isArray(policy.supplementalGeneratedOutputs)
    ? policy.supplementalGeneratedOutputs.find(
      (entry) => entry.relativePath === relativePath) : null;
  if (exactGeneratedPaths.includes(relativePath)
      || runtimeLogRelativePaths.includes(relativePath)
      || webView2UserDataRelativePrefixes.some((prefix) => relativePath.startsWith(prefix))
      || supplementalEntry
      || relativePath.startsWith(policy.candidateRelativeRoot + "/")
      || relativePath.startsWith(policy.internalRunPrefix)) {
    return { relativePath, kind: "generated_output", protectedEntry: null,
      supplementalEntry };
  }
  Common.fail("material_shop_ignored_output_foreign", "materialize_verify",
    "ignored file is outside the exact protected-input/candidate/A5 output closure", {
      relativePath,
    });
}

function assertIgnoredOutputPath(relativePathValue, policy, scope) {
  return classifyIgnoredOutputPath(relativePathValue, policy, scope).relativePath;
}

function captureIgnoredOutputInventoryForSchema(destinationValue, options, schema) {
  const destination = path.resolve(destinationValue);
  const policy = schema === LEGACY_IGNORED_OUTPUT_SCHEMA
    ? legacyIgnoredOutputPolicy(destination, options)
    : ignoredOutputPolicy(destination, options);
  const paths = gitPathSet(destination,
    ["ls-files", "--others", "--ignored", "--exclude-standard", "-z"]);
  if (paths.length > MAXIMUM_IGNORED_OUTPUT_FILES) {
    Common.fail("material_shop_ignored_output_inventory_too_large", "materialize_verify",
      "ignored-output file count exceeds the release policy", { fileCount: paths.length });
  }
  let totalBytes = 0;
  const files = paths.map((entry) => {
    const classification = classifyIgnoredOutputPath(entry, policy, options && options.scope);
    const relativePath = classification.relativePath;
    const file = Evidence.readExactRegularFile(
      Common.resolveWithin(destination, relativePath, "materialize_verify").absolute,
      { phase: "materialize_verify", maximumBytes: classification.protectedEntry
        ? Math.max(512 * 1024 * 1024, classification.protectedEntry.bytes)
        : 512 * 1024 * 1024,
      allowEmpty: !classification.protectedEntry });
    if (classification.protectedEntry
        && (file.length !== classification.protectedEntry.bytes
          || file.sha256 !== classification.protectedEntry.sha256)) {
      Common.fail("material_shop_worktree_scope_mismatch", "materialize_verify",
        "ignored protected input changed after current-tree overlay", { relativePath });
    }
    if (classification.supplementalEntry
        && (file.length !== classification.supplementalEntry.bytes
          || file.sha256 !== classification.supplementalEntry.sha256)) {
      Common.fail("material_shop_ignored_output_inventory_invalid", "materialize_verify",
        "supplemental generated output bytes differ from its eligibility descriptor", {
          relativePath,
        });
    }
    totalBytes += file.length;
    if (totalBytes > MAXIMUM_IGNORED_OUTPUT_BYTES) {
      Common.fail("material_shop_ignored_output_inventory_too_large", "materialize_verify",
        "ignored-output bytes exceed the release policy", { totalBytes });
    }
    return { relativePath, kind: classification.kind,
      bytes: file.length, sha256: file.sha256 };
  });
  const supplemental = Array.isArray(policy.supplementalGeneratedOutputs)
    ? policy.supplementalGeneratedOutputs : [];
  if (supplemental.some((descriptor) => !files.some((entry) =>
    entry.relativePath === descriptor.relativePath
      && entry.bytes === descriptor.bytes && entry.sha256 === descriptor.sha256))) {
    Common.fail("material_shop_ignored_output_inventory_invalid", "materialize_verify",
      "every supplemental generated output must exist in the ignored inventory");
  }
  const value = { schema, policy,
    fileCount: files.length, totalBytes, files,
    filesSha256: Evidence.sha256Text(Evidence.canonicalJson(files)) };
  value.inventorySha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function captureIgnoredOutputInventory(destinationValue, options) {
  return captureIgnoredOutputInventoryForSchema(
    destinationValue, options, IGNORED_OUTPUT_SCHEMA);
}

function validateIgnoredOutputInventory(value, destination, options) {
  Common.exactKeys(value, ["schema", "policy", "fileCount", "totalBytes", "files",
    "filesSha256", "inventorySha256"],
  "material_shop_ignored_output_inventory_invalid", "materialize_verify");
  const unsigned = Object.assign({}, value);
  delete unsigned.inventorySha256;
  if (![IGNORED_OUTPUT_SCHEMA, LEGACY_IGNORED_OUTPUT_SCHEMA].includes(value.schema)) {
    Common.fail("material_shop_ignored_output_inventory_invalid", "materialize_verify",
      "ignored candidate/A5 output inventory schema is unsupported");
  }
  const legacy = value.schema === LEGACY_IGNORED_OUTPUT_SCHEMA;
  const policy = legacy ? legacyIgnoredOutputPolicy(destination, options)
    : ignoredOutputPolicy(destination, options);
  const files = Array.isArray(value.files) ? value.files : [];
  if (value.inventorySha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))
      || Evidence.canonicalJson(value.policy) !== Evidence.canonicalJson(policy)
      || !Number.isInteger(value.fileCount) || value.fileCount < 1
      || value.fileCount > MAXIMUM_IGNORED_OUTPUT_FILES
      || !Number.isInteger(value.totalBytes) || value.totalBytes < (legacy ? 1 : 0)
      || value.totalBytes > MAXIMUM_IGNORED_OUTPUT_BYTES
      || value.fileCount !== files.length
      || value.totalBytes !== files.reduce((sum, entry) => sum + Number(entry.bytes || 0), 0)
      || value.filesSha256 !== Evidence.sha256Text(Evidence.canonicalJson(files))
      || files.some((entry, index) => !Evidence.isPlainObject(entry)
        || Evidence.canonicalJson(Object.keys(entry).sort())
          !== Evidence.canonicalJson(["bytes", "kind", "relativePath", "sha256"].sort())
        || !Number.isInteger(entry.bytes) || entry.bytes < 0
        || !["generated_output", "protected_scope_input"].includes(entry.kind)
        || (legacy || entry.kind === "protected_scope_input") && entry.bytes < 1
        || !Common.SHA256_RE.test(String(entry.sha256 || ""))
        || index > 0 && compareOrdinal(
          files[index - 1].relativePath, entry.relativePath) >= 0)) {
    Common.fail("material_shop_ignored_output_inventory_invalid", "materialize_verify",
      "ignored candidate/A5 output inventory is malformed or detached");
  }
  files.forEach((entry) => {
    const classification = classifyIgnoredOutputPath(
      entry.relativePath, policy, options && options.scope);
    if (entry.kind !== classification.kind
        || classification.protectedEntry
        && (entry.bytes !== classification.protectedEntry.bytes
          || entry.sha256 !== classification.protectedEntry.sha256)
        || classification.supplementalEntry
        && (entry.bytes !== classification.supplementalEntry.bytes
          || entry.sha256 !== classification.supplementalEntry.sha256)) {
      Common.fail("material_shop_ignored_output_inventory_invalid", "materialize_verify",
        "ignored inventory entry is detached from its protected-input classification", {
          relativePath: entry.relativePath,
      });
    }
  });
  const supplemental = legacy || !Array.isArray(policy.supplementalGeneratedOutputs)
    ? [] : policy.supplementalGeneratedOutputs;
  if (supplemental.some((descriptor) => !files.some((entry) =>
    entry.relativePath === descriptor.relativePath
      && entry.bytes === descriptor.bytes && entry.sha256 === descriptor.sha256))) {
    Common.fail("material_shop_ignored_output_inventory_invalid", "materialize_verify",
      "ignored inventory omitted an eligibility-bound supplemental generated output");
  }
  return value;
}

function verifyIgnoredOutputInventory(value, destination, options) {
  validateIgnoredOutputInventory(value, destination, options);
  const current = captureIgnoredOutputInventoryForSchema(
    destination, options, value.schema);
  if (Evidence.canonicalJson(value) !== Evidence.canonicalJson(current)) {
    Common.fail("material_shop_ignored_output_inventory_invalid", "materialize_verify",
      "ignored candidate/A5 output inventory changed after acceptance");
  }
  return value;
}

function verifyOverlayStatus(destination, basePaths, scope) {
  const base = new Set(basePaths);
  const scopeByPath = new Map(scope.files.map((entry) => [entry.relativePath, entry]));
  const modified = gitPathSet(destination,
    ["diff", "--no-ext-diff", "--name-only", "-z", "HEAD", "--"]);
  const staged = gitPathSet(destination,
    ["diff", "--cached", "--name-only", "-z", "HEAD", "--"]);
  const untracked = gitPathSet(destination,
    ["ls-files", "--others", "--exclude-standard", "-z"]);
  if (staged.length !== 0 || modified.some((entry) => !scopeByPath.has(entry))
      || untracked.some((entry) => !scopeByPath.has(entry))
      || untracked.some((entry) => base.has(entry))) {
    Common.fail("material_shop_worktree_overlay_escape", "materialize_verify",
      "materialized worktree drift escaped the exact current-tree A5 scope",
      { modified, staged, untracked });
  }
  verifyScopeFiles(destination, scope);
  return { modified, untracked };
}

function verifyScopeFiles(destination, scope) {
  scope.files.forEach((entry) => {
    const file = Evidence.readExactRegularFile(
      Common.resolveWithin(destination, entry.relativePath, "materialize_verify").absolute,
      { phase: "materialize_verify", maximumBytes: Math.max(1, entry.bytes) });
    if (file.length !== entry.bytes || file.sha256 !== entry.sha256) {
      Common.fail("material_shop_worktree_scope_mismatch", "materialize_verify",
        "materialized Worktree scope overlay changed", { relativePath: entry.relativePath });
    }
  });
  return scope.files.length;
}

function verifyPostBuildProtectedScope(destinationValue, scope, options) {
  const destination = path.resolve(destinationValue);
  Scope.verifyScopeManifest(scope, { currentTree: false });
  const basePaths = runGit(destination, ["ls-files", "-z"]).split("\0").filter(Boolean)
    .map((entry) => entry.replace(/\\/g, "/"));
  const overlayStatus = verifyOverlayStatus(destination, basePaths, scope);
  const ignoredOutputInventory = captureIgnoredOutputInventory(destination,
    Object.assign({}, options || {}, { scope }));
  return { scopeSha256: scope.scopeSha256, overlayStatus, ignoredOutputInventory };
}

function stableReceipt(value) {
  return {
    schema: value.schema, mode: value.mode, sourceRoot: value.sourceRoot,
    destination: value.destination, ownedBase: value.ownedBase, head: value.head,
    scopeSha256: value.scopeSha256, baseFileCount: value.baseFileCount,
    baseTotalBytes: value.baseTotalBytes, baseFilesSha256: value.baseFilesSha256,
    fileCount: value.fileCount, totalBytes: value.totalBytes,
    filesSha256: value.filesSha256, overlayStatus: value.overlayStatus,
    gitWorktree: value.gitWorktree, worktreeBuildIdentity: value.worktreeBuildIdentity,
  };
}

function materializeScope(options) {
  const settings = options || {};
  const root = Common.assertCanonicalRoot(settings.root || Common.CANONICAL_ROOT);
  const base = ownedBase(root, settings.ownedBase);
  const sourceRoot = path.resolve(settings.sourceRoot || root);
  const fixtureMode = settings.fixtureMode === true;
  if (fixtureMode) {
    if (!Evidence.pathInside(base, sourceRoot)) {
      Common.fail("material_shop_fixture_source_invalid", "materialize",
        "fixture source must remain under the dedicated owned base");
    }
  } else if (!samePath(sourceRoot, root)) {
    Common.fail("material_shop_materialize_source_invalid", "materialize",
      "production materialization source must be the canonical current tree");
  }
  Scope.verifyScopeManifest(settings.scope, { currentTree: !fixtureMode });
  if (!samePath(settings.scope.root, sourceRoot)) {
    Common.fail("material_shop_materialize_scope_root_invalid", "materialize",
      "scope root differs from the selected materialization source");
  }
  // Pure projection only: reject unsafe paths before destination creation, producer
  // markers, Git worktree creation, candidate output, or any other materialized write.
  assertMaterializedPathBudget(settings.destination, settings.scope);
  // Every current-tree overlay source can be validated before creating a Git worktree.
  // Re-read again during copy so a concurrent change still fails closed.
  settings.scope.files.forEach((entry) => readExactSource(sourceRoot, entry));
  const destination = assertDestination(base, settings.destination);
  let baseFiles = [];
  let gitWorktree = null;
  let creationIntent = null;
  let producerHandle = null;
  try {
    if (fixtureMode) {
      fs.mkdirSync(destination);
    } else {
      const runDir = assertCreationIntentAvailable(settings.runDir);
      creationIntent = createCreationIntent({ runId: path.basename(runDir), runDir,
        ownedBase: base, destination, scope: settings.scope });
      writeJsonAtomicNew(path.join(runDir, CREATION_INTENT_NAME), creationIntent);
      // The producer lease is CreateNew + fsync and precedes the first Git/worktree
      // side effect. A killed outer runner therefore cannot race recovery cleanup.
      producerHandle = acquireMaterializationProducer(runDir);
      runGit(root, ["worktree", "add", "--detach", destination, settings.scope.head]);
      assertDirectDirectory(destination, "materialize");
      gitWorktree = worktreeIdentity(destination, settings.scope.head);
      baseFiles = collectDestinationFiles(destination);
    }
    settings.scope.files.forEach((entry) => {
      const source = readExactSource(sourceRoot, entry);
      ensureDestinationParent(destination, entry.relativePath);
      const target = Common.resolveWithin(destination, entry.relativePath, "materialize").absolute;
      fs.copyFileSync(source.path, target);
    });
    const files = collectDestinationFiles(destination);
    const basePaths = baseFiles.map((entry) => entry.relativePath);
    const overlayStatus = fixtureMode ? { modified: [], untracked: [] }
      : verifyOverlayStatus(destination, basePaths, settings.scope);
    const worktreeBuildIdentity = fixtureMode ? null : captureWorktreeBuildIdentity(destination);
    const value = {
      schema: RECEIPT_SCHEMA,
      createdAt: settings.createdAt || new Date().toISOString(),
      mode: fixtureMode ? FIXTURE_MODE : PRODUCTION_MODE,
      sourceRoot, destination, ownedBase: base, head: settings.scope.head,
      scopeSha256: settings.scope.scopeSha256,
      baseFileCount: baseFiles.length,
      baseTotalBytes: baseFiles.reduce((sum, entry) => sum + entry.bytes, 0),
      baseFilesSha256: filesDigest(baseFiles),
      fileCount: files.length,
      totalBytes: files.reduce((sum, entry) => sum + entry.bytes, 0),
      filesSha256: filesDigest(files),
      overlayStatus,
      gitWorktree,
      worktreeBuildIdentity,
    };
    value.materializationSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableReceipt(value)));
    const verified = verifyMaterialization(value, settings.scope, {
      ownedBase: base, fixtureMode,
    });
    return verified;
  } catch (error) {
    if (producerHandle && producerHandle.active) {
      try { releaseMaterializationProducer(producerHandle); }
      catch (releaseError) {
        releaseError.originalMaterializationError = {
          code: error && error.code || null, message: error && error.message || String(error),
        };
        throw releaseError;
      }
    }
    throw error;
  }
}

function verifyMaterialization(value, scope, options) {
  const settings = options || {};
  Common.exactKeys(value, ["schema", "createdAt", "mode", "sourceRoot", "destination",
    "ownedBase", "head", "scopeSha256", "baseFileCount", "baseTotalBytes",
    "baseFilesSha256", "fileCount", "totalBytes", "filesSha256", "overlayStatus",
    "gitWorktree", "worktreeBuildIdentity", "materializationSha256"],
  "material_shop_materialization_receipt_invalid", "materialize_verify");
  const fixtureMode = value.mode === FIXTURE_MODE;
  if (value.schema !== RECEIPT_SCHEMA || ![PRODUCTION_MODE, FIXTURE_MODE].includes(value.mode)
      || !Number.isFinite(Date.parse(value.createdAt)) || value.head !== scope.head
      || value.scopeSha256 !== scope.scopeSha256
      || !Number.isInteger(value.baseFileCount) || value.baseFileCount < 0
      || !Number.isInteger(value.baseTotalBytes) || value.baseTotalBytes < 0
      || !Common.SHA256_RE.test(String(value.baseFilesSha256 || ""))
      || !Number.isInteger(value.fileCount) || value.fileCount < scope.fileCount
      || !Number.isInteger(value.totalBytes) || value.totalBytes < scope.totalBytes
      || !Common.SHA256_RE.test(String(value.filesSha256 || ""))
      || value.materializationSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableReceipt(value)))) {
    Common.fail("material_shop_materialization_receipt_invalid", "materialize_verify",
      "materialization receipt is malformed or detached from its scope");
  }
  if (settings.fixtureMode != null && fixtureMode !== (settings.fixtureMode === true)) {
    Common.fail("material_shop_materialization_mode_mismatch", "materialize_verify",
      "materialization mode differs from the verifier boundary");
  }
  const base = path.resolve(settings.ownedBase || value.ownedBase);
  if (!samePath(base, value.ownedBase)) {
    Common.fail("material_shop_materialization_owned_base_mismatch", "materialize_verify",
      "receipt owned base differs from the verifier boundary");
  }
  const materializedBase = path.join(base, MATERIALIZED_DIRECTORY);
  if (!Evidence.pathInside(materializedBase, value.destination)
      || path.basename(value.destination).toLowerCase() !== "resources"
      || path.dirname(path.dirname(value.destination)).toLowerCase()
        !== path.resolve(materializedBase).toLowerCase()) {
    Common.fail("material_shop_materialization_destination_escape", "materialize_verify",
      "receipt destination escaped the owned materialized directory");
  }
  const allowBuildOutputs = settings.allowBuildOutputs === true;
  if (allowBuildOutputs && fixtureMode) {
    Common.fail("material_shop_materialization_release_mode_invalid", "materialize_verify",
      "post-build release verification is valid only for a production Git worktree");
  }
  if (!allowBuildOutputs) {
    const files = collectDestinationFiles(value.destination);
    if (value.fileCount !== files.length
        || value.totalBytes !== files.reduce((sum, entry) => sum + entry.bytes, 0)
        || value.filesSha256 !== filesDigest(files)) {
      Common.fail("material_shop_materialization_tree_mismatch", "materialize_verify",
        "materialized pre-build worktree file set or bytes changed");
    }
  }
  if (fixtureMode) {
    if (value.gitWorktree !== null || value.worktreeBuildIdentity !== null
        || value.baseFileCount !== 0 || value.baseTotalBytes !== 0) {
      Common.fail("material_shop_fixture_receipt_invalid", "materialize_verify",
        "fixture materialization claimed a Git Worktree identity");
    }
  } else {
    const currentGit = worktreeIdentity(value.destination, scope.head);
    if (Evidence.canonicalJson(currentGit) !== Evidence.canonicalJson(value.gitWorktree)) {
      Common.fail("material_shop_git_worktree_drift", "materialize_verify",
        "materialized resources lost its detached Git Worktree identity");
    }
    const basePaths = runGit(value.destination, ["ls-files", "-z"]).split("\0").filter(Boolean)
      .map((entry) => entry.replace(/\\/g, "/"));
    const status = verifyOverlayStatus(value.destination, basePaths, scope);
    if (Evidence.canonicalJson(status) !== Evidence.canonicalJson(value.overlayStatus)) {
      Common.fail("material_shop_worktree_status_drift", "materialize_verify",
        "materialized Worktree overlay status changed");
    }
    const identity = captureWorktreeBuildIdentity(value.destination);
    if (Evidence.canonicalJson(identity) !== Evidence.canonicalJson(value.worktreeBuildIdentity)) {
      Common.fail("material_shop_worktree_identity_drift", "materialize_verify",
        "canonical Worktree build identity changed after materialization");
    }
  }
  return value;
}

function parseRecoveryArgs(argv) {
  const args = { mode: null, runDir: null, acknowledge: false };
  let acknowledgement = null;
  const selectMode = (mode) => {
    if (args.mode !== null) Common.fail(
      "material_shop_materialization_recovery_arguments_invalid",
      "materialize_recovery", "recovery accepts one exact mode flag");
    args.mode = mode;
  };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--cleanup-failed-materialization") selectMode("cleanup");
    else if (argv[index] === "--inspect-materialization-producer") {
      selectMode("inspect_producer");
    }
    else if (argv[index] === "--recover-stale-materialization-producer") {
      selectMode("recover_producer");
    }
    else if (argv[index] === "--finalize-stale-preparation") {
      selectMode("finalize_preparation");
    }
    else if (argv[index] === "--run-dir") args.runDir = argv[++index];
    else if (argv[index] === "--acknowledge-remove-failed-worktree") {
      if (acknowledgement) Common.fail(
        "material_shop_materialization_recovery_arguments_invalid",
        "materialize_recovery", "recovery accepts one exact acknowledgement flag");
      acknowledgement = "cleanup";
    } else if (argv[index] === "--acknowledge-stale-materialization-producer") {
      if (acknowledgement) Common.fail(
        "material_shop_materialization_recovery_arguments_invalid",
        "materialize_recovery", "recovery accepts one exact acknowledgement flag");
      acknowledgement = "recover_producer";
    } else if (argv[index] === "--acknowledge-stale-preparation-finalization") {
      if (acknowledgement) Common.fail(
        "material_shop_materialization_recovery_arguments_invalid",
        "materialize_recovery", "recovery accepts one exact acknowledgement flag");
      acknowledgement = "finalize_preparation";
    } else {
      Common.fail("material_shop_materialization_recovery_argument_unknown",
        "materialize_recovery", argv[index]);
    }
  }
  const expectedAcknowledgement = args.mode === "inspect_producer" ? null : args.mode;
  if (!args.runDir || !["cleanup", "inspect_producer", "recover_producer",
      "finalize_preparation"].includes(args.mode)
      || acknowledgement !== expectedAcknowledgement) {
    Common.fail("material_shop_materialization_recovery_arguments_invalid",
      "materialize_recovery",
      "use exact producer inspection, acknowledged stale recovery/finalization, or acknowledged failed-worktree cleanup");
  }
  args.acknowledge = acknowledgement !== null;
  return args;
}

function main() {
  try {
    const args = parseRecoveryArgs(process.argv.slice(2));
    if (args.mode === "inspect_producer") {
      const value = readMaterializationProducer(args.runDir);
      process.stdout.write(JSON.stringify({ ok: true, producer: value }) + "\n");
    } else if (args.mode === "recover_producer") {
      const value = recoverStaleMaterializationProducer(args.runDir, {
        acknowledge: args.acknowledge,
      });
      process.stdout.write(JSON.stringify({ ok: true, producer: value }) + "\n");
    } else if (args.mode === "finalize_preparation") {
      const value = finalizeStalePreparedMaterialization(args.runDir, {
        acknowledge: args.acknowledge,
      });
      process.stdout.write(JSON.stringify({ ok: true, runId: value.runId,
        preparationSha256: value.preparationSha256,
        finalizationSha256: value.finalizationSha256 }) + "\n");
    } else {
      const value = cleanupFailedMaterialization(args.runDir, {
        acknowledge: args.acknowledge,
      });
      process.stdout.write(JSON.stringify({ ok: true, runId: value.runId,
        destination: value.destination, cleanupSha256: value.cleanupSha256 }) + "\n");
    }
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

module.exports = {
  CLEANUP_RECEIPT_NAME,
  CLEANUP_RECEIPT_SCHEMA,
  CLEANUP_RESOLVED_PREFIX,
  CREATION_INTENT_NAME,
  CREATION_INTENT_SCHEMA,
  CREATION_RESOLVED_PREFIX,
  FIXTURE_MODE,
  IGNORED_OUTPUT_SCHEMA,
  LEGACY_IGNORED_OUTPUT_SCHEMA,
  MATERIALIZED_DIRECTORY,
  MAXIMUM_WINDOWS_LEGACY_PATH_LENGTH,
  PRODUCTION_MODE,
  PRODUCER_LEASE_NAME,
  PRODUCER_LEASE_SCHEMA,
  PRODUCER_STALE_PREFIX,
  PRODUCER_TERMINAL_PREFIX,
  PREPARATION_FINALIZATION_NAME,
  PREPARATION_FINALIZATION_SCHEMA,
  RECEIPT_SCHEMA,
  captureWorktreeBuildIdentity,
  assertMaterializedPathBudget,
  captureIgnoredOutputInventory,
  compareOrdinal,
  assertCleanupDirtyPaths,
  assertStableCleanupProbes,
  cleanupFailedMaterialization,
  cleanupPresence,
  cleanupReceiptFromIntent,
  cleanupResolvedName,
  collectDestinationFiles,
  createCreationIntent,
  createMaterializationProducerLease,
  creationResolvedName,
  filesDigest,
  ensureDestinationParent,
  ensureDirectDirectoryChain,
  finalizeStalePreparedMaterialization,
  loadCreationState,
  loadPreparedMaterializationContext,
  loadPreparedMaterializationFinalization,
  readMaterializationProducer,
  acquireMaterializationProducer,
  releaseMaterializationProducer,
  recoverStaleMaterializationProducer,
  assertMaterializationProducerInactive,
  producerStaleName,
  producerTerminalName,
  materializationMarkerFiles,
  materializeScope,
  parseRecoveryArgs,
  preparedMaterializationFinalizationReceipt,
  readExactTreeFile,
  resolveCreationIntent,
  assertIgnoredOutputPath,
  ignoredOutputPolicy,
  legacyIgnoredOutputPolicy,
  stableReceipt,
  validateIgnoredOutputInventory,
  validateCleanupReceipt,
  validateCreationIntent,
  validatePreparedMaterializationFinalization,
  verifyFailedMaterializationWorktree,
  verifyMaterialization,
  verifyIgnoredOutputInventory,
  verifyPostBuildProtectedScope,
  verifyScopeFiles,
  worktreeIdentity,
  worktreeListed,
  writeJsonAtomicNew,
};

if (require.main === module) main();
