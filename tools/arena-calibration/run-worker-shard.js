#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { assertRuntimeIdentity } = require("../lib/runtime-process-identity");
const { sha256OfValue } = require("./lib/arena-calibration-core");
const { validateResultRowsAgainstManifest } = require("./lib/campaign-supervisor");
const { verifyManifestIntegrity } = require("./lib/gate-f-campaign");
const { sha256Bytes, snapshotBytes, writeImmutableBytes, writeImmutableJson } = require("./lib/immutable-evidence");
const { captureResourceClosure, runEvidenceTask } = require("./lib/arena-worker-evidence");
const { coreEnvironment, detectDotnetRuntime } = require("./lib/arena-worker-dotnet");
const { compareProtectedSaveSnapshots } = require("./run-unattended");
const { assertRuntimeReadyStatus } = require("../equipment-tuning/run-unattended");
const { ID_FIELDS, assertNoReparse, assertTuple, createWorkerClient, queryProcess, readJson,
  resolveInside, safeId, samePath, terminateExactProcess, validateLaunch,
  validateProcessObservation, verifyProcessOwner } = require("./lib/arena-worker-client");

const TERMINAL = new Set(["completed", "failed", "aborted"]);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function timestamp() { return new Date().toISOString(); }
function relative(root, file) { return path.relative(root, file).replace(/\\/g, "/"); }

function workerAttemptDirectory(launch, identity) {
  ID_FIELDS.forEach((field) => safeId(identity[field], field));
  return resolveInside(launch.outputRoot, path.join("worker-runs", identity.sessionEpoch, identity.assignmentId, identity.attemptId), "attempt output");
}

function readBoundLaunch(filePath, expectedLaunch, expectedSha256) {
  assertNoReparse(filePath);
  const stat = fs.lstatSync(filePath);
  if (!stat.isFile() || stat.size > 32768) throw new Error("Worker launch file is missing or too large");
  const bytes = fs.readFileSync(filePath);
  const sha256 = sha256Bytes(bytes);
  const launch = JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, ""));
  if ((expectedLaunch === undefined) !== (expectedSha256 === undefined)) throw new Error("frozen launch value and byte hash must be supplied together");
  if (expectedLaunch !== undefined && (sha256 !== expectedSha256 || sha256OfValue(launch) !== sha256OfValue(expectedLaunch))) {
    throw new Error("Worker launch differs from the frozen experiment assignment");
  }
  validateLaunch(launch);
  return { launch, bytes, sha256 };
}

function workloadHash(manifest) {
  return sha256OfValue({ arenaMode: manifest.arenaMode, repeat: manifest.repeat,
    timeoutFrames: manifest.timeoutFrames, blueBench: manifest.blueBench,
    cases: manifest.cases.map((entry) => { const value = { ...entry }; delete value.caseId; delete value.caseHash; return value; }) });
}

function assertArenaStatus(status, identity, manifest) {
  assertTuple(status, identity);
  assertTuple(status, manifest, ["batchId", "manifestHash"]);
  if (status.transportPoisoned === true && status.state === "completed") throw new Error("poisoned Worker cannot claim completed");
  return status;
}

function exactAttemptResultPath(value, launch, identity, manifest) {
  if (typeof value !== "string" || !value || path.isAbsolute(value)) throw new Error("Worker resultPath must be an observed project-relative attempt path");
  const actual = resolveInside(launch.outputRoot, path.resolve(launch.projectRoot, value), "Worker raw result");
  const expected = path.join(launch.outputRoot, "batches", manifest.batchId, "attempts", identity.attemptId, "results.jsonl");
  if (!samePath(actual, expected)) throw new Error("Worker resultPath does not name the exact assigned attempt");
  return actual;
}

function validateRawRows(bytes, manifest, identity, requireComplete) {
  const rows = bytes.toString("utf8").split(/\r?\n/).filter((line) => line.trim()).map((line) => JSON.parse(line));
  validateResultRowsAgainstManifest(rows, manifest, "Worker raw results", { allowPartial: !requireComplete });
  rows.forEach((row) => assertTuple(row, identity));
  return rows;
}

function validateProjectionProof(status, launch) {
  const same = require("util").isDeepStrictEqual;
  const hash = (value) => typeof value === "string" && /^sha256:[0-9a-f]{64}$/.test(value);
  const policy = status && status.policy, receipt = status && status.installReceipt;
  if (!status || status.state !== "committed" || status.committed !== true || status.failure
      || !Number.isSafeInteger(status.connectionGeneration) || status.connectionGeneration < 1
      || !/^[0-9a-f]{32}$/.test(status.contractId || "") || !policy || !receipt) throw new Error("Worker projection installation is unproven");
  const names = ["bulletStyles", "combatFxStyles", "rayStyles", "sceneLights"];
  const bindings = policy.catalogBindings;
  if (!bindings || Object.keys(bindings).length !== names.length || names.some((name) => !hash(bindings[name])))
    throw new Error("Worker projection catalog binding is invalid");
  const canonical = { presentation: launch.presentationPolicy, readinessKind: "arena.presented.v1",
    projectionConsumers: Object.fromEntries(require("./lib/arena-worker-client").PROJECTION_CONSUMERS.map((name) => [name, launch.projectionConsumers[name]])),
    controlFrameFormat: launch.controlFrameFormat, ownership: "as2-gameplay-native-model-v1",
    catalogBindings: Object.fromEntries(names.map((name) => [name, bindings[name]])), visualSeedRevision: launch.visualSeedRevision,
    simulationRngConsumptionRevision: launch.simulationRngConsumptionRevision, sessionVisualSeed: launch.sessionVisualSeed };
  if (!same(policy, canonical)) throw new Error("Worker installed policy differs from launch");
  for (const [name, value] of Object.entries(canonical))
    if (!same(receipt[name], value)) throw new Error(`Worker installed receipt mismatch: ${name}`);
  if (receipt.task !== "worker_projection_committed" || receipt.version !== 1 || receipt.sequence !== 2
      || receipt.workerId !== launch.workerId || receipt.sessionEpoch !== launch.sessionEpoch
      || receipt.contractId !== status.contractId || receipt.connectionGeneration !== status.connectionGeneration
      || receipt.installClockKind !== "flashRootEnterFrame" || !Number.isSafeInteger(receipt.installEpoch) || receipt.installEpoch < 1
      || !Number.isSafeInteger(receipt.installTick) || receipt.installTick < 1
      || receipt.policyDigest !== sha256Bytes(Buffer.from(JSON.stringify(canonical), "utf8")))
    throw new Error("Worker actual root-frame receipt is invalid");
  return status;
}

function validateProjectionRows(rows, launch, proof) {
  validateProjectionProof(proof, launch);
  for (const row of rows)
    if (row.presentationPolicy !== "full" || row.presentationContractVersion !== 1
        || row.presentationContractId !== proof.contractId || row.readinessKind !== "arena.presented.v1"
        || row.visualSeedRevision !== launch.visualSeedRevision || row.simulationRngConsumptionRevision !== launch.simulationRngConsumptionRevision
        || !require("util").isDeepStrictEqual(row.projectionConsumers, launch.projectionConsumers)
        || !require("util").isDeepStrictEqual(row.projectionInstallReceipt, proof.installReceipt))
      throw new Error("Worker raw result lacks the exact installed projection contract");
  return rows;
}

function normalizeExperiment(value = {}) {
  if (!value.groupId || !value.condition) throw new Error("experiment groupId and condition are required");
  safeId(value.groupId, "experiment.groupId");
  safeId(value.condition, "experiment.condition");
  if (![1, 2].includes(value.concurrency)) throw new Error("P0/P1 experiment concurrency must be 1 or 2");
  if (!["cold", "warm"].includes(value.sessionState)) throw new Error("experiment sessionState must be explicit");
  if (!["foreground", "background-visible", "minimized", "unknown"].includes(value.visibility)) throw new Error("invalid experiment visibility");
  return { ...value, qualityRequested: value.qualityRequested || "unknown", qualityApplied: "unknown" };
}

async function waitFor(test, timeoutMs, pollMs, label) {
  const deadline = Date.now() + timeoutMs;
  do {
    const result = await test();
    if (result) return result;
    await sleep(pollMs);
  } while (Date.now() < deadline);
  throw new Error(`${label} timed out`);
}

function isSameProcessAlive(identity, probe = queryProcess) {
  if (!identity) return false;
  const pid = identity.pid || identity.hostPid;
  const current = validateProcessObservation(probe(pid), pid);
  return current !== null && current.processStartUtcTicks === identity.processStartUtcTicks && samePath(current.processPath, identity.processPath);
}

function childHasExited(child) {
  return child && ((child.exitCode !== null && child.exitCode !== undefined)
    || (typeof child.signalCode === "string" && child.signalCode.length > 0));
}

async function runWorkerShard(options, dependencies = {}) {
  const startedAt = timestamp();
  const boundLaunch = readBoundLaunch(path.resolve(options.launchPath), options.expectedLaunch, options.expectedLaunchSha256);
  const launch = boundLaunch.launch;
  const experiment = normalizeExperiment(options.experiment);
  const manifestBytes = fs.readFileSync(path.resolve(options.manifestPath));
  const manifest = JSON.parse(manifestBytes.toString("utf8").replace(/^\uFEFF/, ""));
  verifyManifestIntegrity(manifest, "Worker shard manifest");
  const identity = { workerId: launch.workerId, sessionEpoch: launch.sessionEpoch,
    assignmentId: safeId(options.assignmentId || `assignment-${crypto.randomUUID()}`, "assignmentId"),
    attemptId: safeId(options.attemptId || `attempt-${crypto.randomUUID()}`, "attemptId") };
  const runDir = workerAttemptDirectory(launch, identity);
  if (fs.existsSync(runDir)) throw new Error("Worker attempt output already exists; an attempt cannot be replayed");
  for (const file of ["owner.json", "control-credential.json"]) {
    if (fs.existsSync(path.join(launch.stateRoot, file))) throw new Error("Worker stateRoot already has an owner; use a fresh session");
  }
  if (!fs.existsSync(path.join(launch.saveRoot, `${launch.slot}.json`))) throw new Error("Worker dedicated seed shadow is missing");
  fs.mkdirSync(runDir, { recursive: true });
  const manifestPath = path.join(runDir, "manifest.json");
  writeImmutableBytes(manifestPath, manifestBytes);
  const launchSnapshotPath = path.join(runDir, "launch.json");
  writeImmutableBytes(launchSnapshotPath, boundLaunch.bytes);
  const receiptPath = path.join(runDir, "shard-receipt.json");
  const sampleEvidence = (operation) => (dependencies.sampleEvidence || runEvidenceTask)({ operation,
    projectRoot: launch.projectRoot, candidateRoot: options.candidateRoot, slot: launch.slot,
    resourcePaths: options.resourcePaths || [], saveOptions: dependencies.saveOptions,
    fixture: dependencies.fixture === true,
    fixtureRuntimeIdentity: dependencies.fixture === true ? dependencies.expectedRuntime : undefined });
  const before = await sampleEvidence("before");
  const expectedRuntime = before.runtimeIdentity;
  if (expectedRuntime.runtimeMode !== "isolated_candidate") throw new Error("Worker execution requires an isolated candidate");
  if (dependencies.expectedRuntime) assertRuntimeIdentity(dependencies.expectedRuntime, expectedRuntime);
  const beforeResources = before.resourceClosure;
  const beforeSave = before.protectedSave;
  const client = dependencies.client || createWorkerClient(launch, expectedRuntime, dependencies.clientOptions);
  const receipt = {
    schema: "arena-worker.shard-receipt.v1", executionMode: "arena_worker",
    evidenceKind: dependencies.fixture === true ? "isolated_fixture" : "worker_live_execution",
    ...identity, batchId: manifest.batchId, manifestHash: manifest.manifestHash, workloadHash: workloadHash(manifest),
    expectedRunCount: manifest.cases.reduce((sum, entry) => sum + entry.repeat, 0), experiment,
    slot: launch.slot, projectRoot: launch.projectRoot, stateRoot: launch.stateRoot, outputRoot: launch.outputRoot,
    swfOrigin: launch.swfOrigin, startedAt, preflightCompletedAt: null, hostStartedAt: null, gameReadyAt: null,
    batchStartedAt: null, completedAt: null, finalizedAt: null, lifecycleCompletedAt: null, wallDurationMs: null,
    manifestSnapshotPath: manifestPath, manifestSha256: sha256Bytes(manifestBytes), resultPath: null, resultSha256: null,
    launchSnapshotPath, launchSha256: boundLaunch.sha256, windowObservations: [], performanceObservations: [], projectionObservations: [],
    hostProcessObservations: [], flashProcessObservations: [],
    evidenceSampling: { before: before.sampling, after: null },
    runtimeIdentity: { ...expectedRuntime, verified: false }, runtimeUnchanged: null,
    resourceClosure: beforeResources, resourcesUnchanged: null, flashProcessObserved: false,
    saveProtection: { before: beforeSave, after: null, unchanged: null, differences: [] },
    ownerSnapshot: null, terminalStatus: null, finalArenaStatus: null, faultReceipt: null, status: "running", rows: 0, errors: [],
    shutdown: { requested: false, hostExited: false, flashExited: false, completedAt: null },
  };
  let child = null;
  let owner = null;
  let flashProcess = null;
  let startRequested = false;
  let batchSubmitted = false;
  let resultResponse = null;
  let boundResultPath = null;
  const pollMs = options.pollMs || 1000;
  const observe = (response, phase) => {
    const receivedAtUtc = timestamp();
    if (response && response.faultReceipt && typeof response.faultReceipt === "object") {
      receipt.faultReceipt = JSON.parse(JSON.stringify(response.faultReceipt));
    }
    if (response && response.windowObservation && typeof response.windowObservation === "object") {
      receipt.windowObservations.push({ ...JSON.parse(JSON.stringify(response.windowObservation)), phase, receivedAtUtc });
    }
    if (response && response.performanceObservation && typeof response.performanceObservation === "object") {
      receipt.performanceObservations.push({ ...JSON.parse(JSON.stringify(response.performanceObservation)), phase, receivedAtUtc });
    }
    if (response && response.projectionStatus && typeof response.projectionStatus === "object")
      receipt.projectionObservations.push({ ...JSON.parse(JSON.stringify(response.projectionStatus)), phase, receivedAtUtc });
    for (const [field, destination] of [["hostProcessObservation", "hostProcessObservations"], ["flashProcessObservation", "flashProcessObservations"]]) {
      if (response && response[field] && typeof response[field] === "object") {
        receipt[destination].push({ ...JSON.parse(JSON.stringify(response[field])), phase, receivedAtUtc });
      }
    }
    return response;
  };
  try {
    receipt.dotnetRuntime = await (dependencies.detectDotnetRuntime
      || (dependencies.fixture === true ? () => ({ source: "isolated_fixture", available: true, environment: {} }) : detectDotnetRuntime))(launch.projectRoot);
    const childEnvironment = coreEnvironment(process.env, receipt.dotnetRuntime);
    const tempDir = resolveInside(launch.stateRoot, "temp", "Worker TEMP");
    fs.mkdirSync(tempDir, { recursive: true });
    if (sha256Bytes(fs.readFileSync(options.launchPath)) !== boundLaunch.sha256) {
      throw new Error("Worker launch bytes changed before spawning the Host");
    }
    receipt.preflightCompletedAt = timestamp();
    const stdout = fs.openSync(path.join(runDir, "host-stdout.log"), "wx");
    const stderr = fs.openSync(path.join(runDir, "host-stderr.log"), "wx");
    try {
      child = (dependencies.spawn || childProcess.spawn)(expectedRuntime.processPath,
        ["--project-root", launch.projectRoot, "--arena-worker", path.resolve(options.launchPath)],
        { cwd: launch.projectRoot, env: { ...childEnvironment, TEMP: tempDir, TMP: tempDir }, windowsHide: true, stdio: ["ignore", stdout, stderr] });
    } finally { fs.closeSync(stdout); fs.closeSync(stderr); }
    let spawnError = null;
    child.on("error", (error) => { spawnError = error; });
    owner = await waitFor(() => {
      if (spawnError) throw spawnError;
      if (childHasExited(child)) throw new Error("Worker Host exited before owner descriptor was ready");
      if (!dependencies.fixture && !fs.existsSync(path.join(launch.stateRoot, "owner.json"))) return false;
      const observed = client.readOwner();
      if (observed.hostPid !== child.pid) throw new Error("Worker owner PID does not belong to the spawned Host");
      verifyProcessOwner(observed, dependencies.processProbe);
      return observed;
    }, options.startupTimeoutMs || 120000, pollMs, "Worker owner");
    receipt.ownerSnapshot = owner;
    const expectedAppData = dependencies.saveOptions && dependencies.saveOptions.appData || process.env.APPDATA;
    if (!samePath(owner.appData, expectedAppData)) throw new Error("Worker owner APPDATA does not match the protected Flash storage root");
    receipt.hostStartedAt = owner.startTimeUtc;
    assertRuntimeIdentity(expectedRuntime, owner.runtimeIdentity);
    receipt.runtimeIdentity = { ...owner.runtimeIdentity, verified: true };
    startRequested = true;
    const start = observe(await client.call("start"), "start");
    flashProcess = start.flashProcess || null;
    await waitFor(async () => {
      const status = observe(await client.call("status"), "ready");
      if (status.flashProcess) flashProcess = status.flashProcess;
      const agent = status.agentStatus;
      if (agent && agent.readyForRuntimeAutomation === true) {
        if (launch.schema === "arena-worker.launch.v2") {
          const projection = status.projectionStatus;
          if (projection && projection.failure) throw new Error(`Worker projection failed: ${projection.failure}`);
          if (!projection || projection.committed !== true) return false;
          validateProjectionProof(projection, launch);
          receipt.projectionEntryProof = JSON.parse(JSON.stringify(projection));
        }
        if (!agent.save || agent.save.slot !== launch.slot) throw new Error("Worker ready state has the wrong save slot");
        assertRuntimeReadyStatus(agent, launch.slot, agent.save.attemptId);
        receipt.agentEntryProof = { attemptId: agent.save.attemptId, gameEnteredAttemptId: agent.gameEnteredAttemptId,
          save: agent.save, saveRuntime: agent.saveRuntime };
        return status;
      }
      if (agent && agent.failureReason) throw new Error(`Worker entry failed: ${agent.failureReason}`);
      return false;
    }, options.startupTimeoutMs || 120000, pollMs, "Worker game readiness");
    receipt.gameReadyAt = timestamp();
    if (!flashProcess) throw new Error("Worker ready state has no owned Flash process identity");
    if (flashProcess.pid === owner.hostPid) throw new Error("Worker Host and Flash must be independent processes");
    resolveInside(launch.projectRoot, flashProcess.processPath, "owned Flash executable");
    verifyProcessOwner({ ...flashProcess, hostPid: flashProcess.pid }, dependencies.processProbe);
    receipt.flashProcessObserved = true;
    const assignment = { ...identity, batchId: manifest.batchId, manifestHash: manifest.manifestHash,
      manifestPath: relative(launch.projectRoot, manifestPath) };
    receipt.batchStartedAt = timestamp();
    batchSubmitted = true;
    const started = observe(await client.call("startBatch", assignment), "batch_start");
    assertArenaStatus(started.arenaStatus, identity, manifest);
    boundResultPath = exactAttemptResultPath(started.arenaStatus.resultPath, launch, identity, manifest);
    receipt.observedResultPath = boundResultPath;
    const terminal = await waitFor(async () => {
      const status = observe(await client.call("status"), "batch_poll");
      if (status.flashProcess) flashProcess = status.flashProcess;
      const arena = assertArenaStatus(status.arenaStatus, identity, manifest);
      return TERMINAL.has(arena.state) ? arena : false;
    }, options.batchTimeoutMs || 300000, pollMs, "Worker shard");
    receipt.terminalStatus = terminal.state;
    receipt.finalArenaStatus = terminal;
    receipt.completedAt = timestamp();
    resultResponse = observe(await client.call("result", identity), "result");
    assertArenaStatus(resultResponse.arenaStatus, identity, manifest);
    receipt.status = terminal.state;
  } catch (error) {
    receipt.status = "failed";
    receipt.completedAt = receipt.completedAt || timestamp();
    receipt.errors.push({ phase: "execution", message: error.message });
    if (owner && startRequested && !batchSubmitted) {
      // DeliveryUnknown is not a failed start. Query the same owner once to
      // recover its Flash process identity for cleanup; never replay start.
      try {
        const observed = observe(await client.call("status"), "startup_reconcile");
        if (observed.flashProcess) {
          const candidate = observed.flashProcess;
          if (candidate.pid === owner.hostPid) throw new Error("Worker Host and Flash must be independent processes");
          resolveInside(launch.projectRoot, candidate.processPath, "reconciled Flash executable");
          verifyProcessOwner({ ...candidate, hostPid: candidate.pid }, dependencies.processProbe);
          flashProcess = candidate;
          receipt.flashProcessObserved = true;
        }
        receipt.startupReconciliation = { action: "status", observedAt: timestamp(),
          flashProcessObserved: receipt.flashProcessObserved, flashProcess };
      } catch (reconcileError) { receipt.errors.push({ phase: "startup_reconcile", message: reconcileError.message }); }
    }
    if (batchSubmitted && owner) {
      try {
        const aborted = await client.call("abort", identity);
        if (aborted.arenaStatus) {
          receipt.finalArenaStatus = assertArenaStatus(aborted.arenaStatus, identity, manifest);
          receipt.terminalStatus = receipt.finalArenaStatus.state;
        }
        resultResponse = await client.call("result", identity);
      } catch (abortError) { receipt.errors.push({ phase: "abort_or_result", message: abortError.message }); }
    }
  } finally {
    if (owner) {
      receipt.shutdown.requested = true;
      try {
        const stopped = observe(await client.call("shutdown"), "shutdown");
        if (stopped.flashProcess) flashProcess = stopped.flashProcess;
      } catch (error) { receipt.errors.push({ phase: "shutdown_delivery", message: error.message }); }
      try {
        await waitFor(() => !isSameProcessAlive(owner, dependencies.processProbe)
          && !isSameProcessAlive(flashProcess, dependencies.processProbe), options.shutdownTimeoutMs || 30000, pollMs, "Worker process recycling");
        receipt.shutdown.hostExited = true;
        receipt.shutdown.flashExited = flashProcess !== null;
      } catch (error) {
        receipt.errors.push({ phase: "shutdown", message: error.message });
        receipt.shutdown.forced = [];
        for (const owned of [flashProcess, owner]) {
          if (!owned) continue;
          try {
            if (isSameProcessAlive(owned, dependencies.processProbe)) {
              receipt.shutdown.forced.push((dependencies.terminateExactProcess || terminateExactProcess)(owned));
            }
          } catch (forceError) { receipt.errors.push({ phase: "forced_recycling", message: forceError.message }); }
        }
        try {
          receipt.shutdown.hostExited = !isSameProcessAlive(owner, dependencies.processProbe);
          receipt.shutdown.flashExited = flashProcess !== null && !isSameProcessAlive(flashProcess, dependencies.processProbe);
        } catch (probeError) { receipt.errors.push({ phase: "recycling_verification", message: probeError.message }); }
      }
      receipt.shutdown.completedAt = timestamp();
    } else if (child) {
      // No game-start request is sent until an exact owner is verified. Before
      // that point only this directly spawned child can need cleanup.
      receipt.shutdown.requested = true;
      if (!childHasExited(child)) child.kill();
      try {
        await waitFor(() => childHasExited(child), options.shutdownTimeoutMs || 30000, pollMs, "unready Worker Host recycling");
        receipt.shutdown.hostExited = true;
        receipt.shutdown.flashExited = true;
        receipt.shutdown.earlyHostExit = { exitCode: child.exitCode === undefined ? null : child.exitCode,
          signalCode: child.signalCode === undefined ? null : child.signalCode };
      } catch (error) { receipt.errors.push({ phase: "startup_cleanup", message: error.message }); }
      receipt.shutdown.completedAt = timestamp();
    }
    let evidencePath = boundResultPath;
    receipt.rawEvidenceSource = evidencePath ? "observed_start_response" : null;
    if (resultResponse) {
      try {
        assertArenaStatus(resultResponse.arenaStatus, identity, manifest);
        evidencePath = exactAttemptResultPath(resultResponse.resultPath, launch, identity, manifest);
        receipt.rawEvidenceSource = "observed_result_response";
      } catch (error) { receipt.errors.push({ phase: "result_path", message: error.message }); }
    }
    if (evidencePath) {
      try {
        // A failed RPC never authorizes replay. Only an already observed exact
        // attempt path can preserve bytes after that owned process is recycled.
        assertNoReparse(evidencePath);
        const bytes = fs.readFileSync(evidencePath);
        const raw = snapshotBytes(path.join(runDir, "raw"), bytes, "jsonl");
        receipt.sourceResultPath = evidencePath;
        receipt.resultPath = raw.filePath;
        receipt.resultSha256 = raw.sha256;
        const rows = validateRawRows(bytes, manifest, identity, receipt.status === "completed");
        if (launch.schema === "arena-worker.launch.v2" && receipt.status === "completed")
          validateProjectionRows(rows, launch, receipt.projectionEntryProof);
        receipt.rows = rows.length;
        const applied = new Set(rows.map((row) => row.presentationAudit && row.presentationAudit.qualityApplied || "unknown"));
        receipt.experiment.qualityApplied = applied.size === 1 ? [...applied][0] : "mixed";
      } catch (error) { receipt.errors.push({ phase: "raw_evidence", message: error.message }); }
    }
    const recordAfter = (after) => {
      receipt.evidenceSampling.after = after.sampling;
      if (after.protectedSave) {
        receipt.saveProtection.after = after.protectedSave;
        receipt.saveProtection.differences = compareProtectedSaveSnapshots(beforeSave, after.protectedSave);
        receipt.saveProtection.unchanged = receipt.saveProtection.differences.length === 0;
      }
      if (after.resourceClosure) {
        receipt.resourcesUnchanged = after.resourceClosure.closureHash === beforeResources.closureHash;
        receipt.resourceClosureAfterHash = after.resourceClosure.closureHash;
      }
      if (after.runtimeIdentity) {
        assertRuntimeIdentity(expectedRuntime, after.runtimeIdentity);
        receipt.runtimeUnchanged = true;
      }
    };
    try { recordAfter(await sampleEvidence("after")); }
    catch (error) {
      if (error.partialEvidence) recordAfter(error.partialEvidence);
      receipt.errors.push({ phase: "protection", message: error.message });
    }
    if (!receipt.shutdown.hostExited || !receipt.shutdown.flashExited || !receipt.saveProtection.unchanged
        || !receipt.runtimeUnchanged || !receipt.resourcesUnchanged || !receipt.flashProcessObserved
        || !receipt.resultPath || receipt.errors.length > 0) receipt.status = "failed";
    receipt.finalizedAt = timestamp();
    receipt.lifecycleCompletedAt = receipt.finalizedAt;
    receipt.wallDurationMs = Date.parse(receipt.finalizedAt) - Date.parse(receipt.startedAt);
    receipt.flashProcess = flashProcess;
    writeImmutableJson(receiptPath, receipt);
  }
  return { receipt, receiptPath };
}

function parseArgs(argv) {
  const result = { resourcePaths: [], experiment: { concurrency: 1, sessionState: "cold", visibility: "unknown" } };
  const names = { "--launch": "launchPath", "--candidate-root": "candidateRoot", "--manifest": "manifestPath",
    "--assignment-id": "assignmentId", "--attempt-id": "attemptId", "--poll-ms": "pollMs",
    "--startup-timeout-ms": "startupTimeoutMs", "--batch-timeout-ms": "batchTimeoutMs", "--shutdown-timeout-ms": "shutdownTimeoutMs" };
  const experimentNames = { "--group-id": "groupId", "--condition": "condition", "--concurrency": "concurrency",
    "--session-state": "sessionState", "--visibility": "visibility", "--quality-requested": "qualityRequested" };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--help") { result.help = true; continue; }
    const value = argv[++index];
    if (value === undefined) throw new Error(`missing value for ${token}`);
    if (names[token]) result[names[token]] = /-ms$/.test(token) ? Number(value) : value;
    else if (experimentNames[token]) result.experiment[experimentNames[token]] = token === "--concurrency" ? Number(value) : value;
    else if (token === "--resource-path") result.resourcePaths.push(value);
    else throw new Error(`unknown option ${token}`);
  }
  for (const key of ["pollMs", "startupTimeoutMs", "batchTimeoutMs", "shutdownTimeoutMs"]) {
    if (result[key] !== undefined && (!Number.isSafeInteger(result[key]) || result[key] < 1)) throw new Error(`${key} must be a positive integer`);
  }
  if (!result.help && (!result.launchPath || !result.candidateRoot || !result.manifestPath)) throw new Error("--launch, --candidate-root and --manifest are required");
  return result;
}

if (require.main === module) {
  Promise.resolve().then(async () => {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      console.log("node run-worker-shard.js --launch <launch.json> --candidate-root <exact candidate> --manifest <manifest.json> --group-id <id> --condition <id> [--concurrency 1|2] [--visibility foreground|background-visible|minimized|unknown]");
      return;
    }
    const result = await runWorkerShard(options);
    console.log(JSON.stringify({ ok: result.receipt.status === "completed", status: result.receipt.status,
      receiptPath: result.receiptPath, rows: result.receipt.rows, wallDurationMs: result.receipt.wallDurationMs }, null, 2));
    if (result.receipt.status !== "completed") process.exitCode = 1;
  }).catch((error) => { console.error(error.message); process.exitCode = 1; });
}

module.exports = { assertArenaStatus, captureResourceClosure, childHasExited, exactAttemptResultPath, isSameProcessAlive, normalizeExperiment,
  parseArgs, readBoundLaunch, runWorkerShard, validateRawRows, validateProjectionProof, validateProjectionRows, workerAttemptDirectory, workloadHash };
