#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { assertRuntimeIdentity, resolveExpectedRuntimeIdentity } = require("../lib/runtime-process-identity");
const { sha256OfValue } = require("./lib/arena-calibration-core");
const { resolveWorkerRuntimeIdentity } = require("./lib/arena-worker-evidence");
const { verifyManifestIntegrity } = require("./lib/gate-f-campaign");
const { sha256Bytes, writeImmutableJson, writeNewBytes } = require("./lib/immutable-evidence");
const { captureGlobalProtectionSnapshot } = require("./lib/unattended-save-safety");
const { assertNoReparse, assertTuple, normalizePerformance, normalizeProjection, readJson, resolveInside, safeId, samePath, verifyGitRoot } = require("./lib/arena-worker-client");
const { compareProtectedSaveSnapshots, isValidSaveData } = require("./run-unattended");
const { normalizeExperiment, runWorkerShard, workerAttemptDirectory } = require("./run-worker-shard");
const { measurePlan } = require("./measure-worker-p0");

const PROJECT_ROOT = path.resolve(__dirname, "../..");

function requireValue(condition, message) { if (!condition) throw new Error(message); }
function hashFile(file) { return sha256Bytes(fs.readFileSync(file)); }
function readExperimentPlan(filePath) { return readJson(filePath, 8 * 1024 * 1024); }
function groupTiming(startedAt) {
  const completedAt = new Date().toISOString();
  return { startedAt, completedAt, wallDurationMs: Date.parse(completedAt) - Date.parse(startedAt) };
}

function verifySeedSources(workers) {
  return workers.map((worker) => {
    const result = { workerId: worker.workerId, seedPath: worker.seedPath, expectedSha256: worker.seedSha256,
      actualSha256: null, unchanged: false };
    try { result.actualSha256 = hashFile(worker.seedPath); result.unchanged = result.actualSha256 === worker.seedSha256; }
    catch (error) { result.error = error.message; }
    return result;
  });
}

function prepareExperiment(plan, dependencies = {}) {
  requireValue(plan && plan.schema === "arena-worker.experiment-plan.v1", "unsupported Worker experiment plan");
  safeId(plan.experimentId, "experimentId");
  requireValue(Array.isArray(plan.workers) && plan.workers.length >= 1 && plan.workers.length <= 2, "P0/P1 requires one or two declared Workers");
  requireValue(Array.isArray(plan.groups) && plan.groups.length > 0, "experiment groups must be declared before running");
  if (plan.faultIntent !== undefined) {
    requireValue(plan.faultIntent && plan.faultIntent.action === "host_atomic_fault_stop_flash_once"
      && plan.faultIntent.maximumAttempts === 1 && plan.faultIntent.speedQualification === false
      && plan.workers.length === 2 && plan.workers.some((worker) => worker.workerId === plan.faultIntent.faultWorkerId)
      && plan.groups.length === 1 && plan.groups[0].mode === "parallel"
      && (!plan.comparisons || plan.comparisons.length === 0), "fault injection requires the declared one-shot isolation plan");
    safeId(plan.faultIntent.faultId, "faultId");
  }
  const sourceRoot = dependencies.fixture === true ? path.resolve(dependencies.projectRoot) : PROJECT_ROOT;
  const appData = dependencies.fixture === true ? dependencies.appData : process.env.APPDATA;
  requireValue(typeof appData === "string" && path.isAbsolute(appData), "APPDATA is required for global save protection");
  const sharedObjectsRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  requireValue(samePath(plan.sharedObjectsRoot, sharedObjectsRoot), "sharedObjectsRoot must be the actual current-user Flash storage root");
  requireValue(Array.isArray(plan.saveRoots) && plan.saveRoots.length > 0, "all protected save roots must be explicitly declared");
  const saveRoots = [...new Set(plan.saveRoots.map((root) => assertNoReparse(root)))];
  const workerIds = new Set();
  const projectRoots = new Set();
  const workers = plan.workers.map((worker) => {
    const workerId = safeId(worker.workerId, "workerId");
    requireValue(!workerIds.has(workerId), "duplicate Worker id"); workerIds.add(workerId);
    const projectRoot = assertNoReparse(worker.projectRoot);
    verifyGitRoot(projectRoot);
    requireValue(!projectRoots.has(projectRoot.toLowerCase()), "each Worker must have its own resource checkout");
    projectRoots.add(projectRoot.toLowerCase());
    const candidateRoot = assertNoReparse(worker.candidateRoot);
    const runtimeIdentity = (dependencies.resolveRuntime || resolveExpectedRuntimeIdentity)(projectRoot, candidateRoot);
    requireValue(runtimeIdentity.runtimeMode === "isolated_candidate", "experiment cannot run a formal runtime");
    const seedPath = assertNoReparse(worker.seedPath);
    requireValue(fs.statSync(seedPath).isFile(), "seedPath must be a read-only source file");
    const seedBytes = fs.readFileSync(seedPath);
    requireValue(isValidSaveData(JSON.parse(seedBytes.toString("utf8").replace(/^\uFEFF/, ""))), "seedPath is not a valid save shadow");
    const saveRoot = path.join(projectRoot, "saves");
    requireValue(saveRoots.some((root) => samePath(root, saveRoot)), "global protection must include every Worker save root");
    if (path.basename(path.dirname(seedPath)).toLowerCase() === "saves") {
      requireValue(saveRoots.some((root) => samePath(root, path.dirname(seedPath))), "global protection must include the seed's source saves root");
    }
    return { workerId, projectRoot, candidateRoot, runtimeIdentity, seedPath, seedSha256: sha256Bytes(seedBytes),
      saveRoot, resourcePaths: worker.resourcePaths || [] };
  });
  const byWorker = new Map(workers.map((entry) => [entry.workerId, entry]));
  const groupIds = new Set();
  const jobIds = new Set();
  const groups = plan.groups.map((group) => {
    const groupId = safeId(group.groupId, "groupId");
    requireValue(!groupIds.has(groupId), "duplicate experiment group"); groupIds.add(groupId);
    requireValue(["serial", "parallel"].includes(group.mode), "group mode must be serial or parallel");
    requireValue(Array.isArray(group.jobs) && group.jobs.length >= 1 && group.jobs.length <= 2,
      "a short P0/P1 group must declare one or two jobs");
    requireValue(group.mode !== "parallel" || group.jobs.length === 2, "parallel group requires two explicit jobs");
    const experiment = normalizeExperiment({ groupId, condition: group.condition || groupId,
      concurrency: group.mode === "parallel" ? 2 : 1, sessionState: "cold", visibility: group.visibility || "unknown",
      qualityRequested: group.qualityRequested || "unknown" });
    const groupWorkers = new Set();
    const performance = normalizePerformance(group.performance);
    const projection = normalizeProjection(group.projection);
    const jobs = group.jobs.map((job, index) => {
      const jobId = safeId(job.jobId || `${groupId}-${index + 1}`, "jobId");
      requireValue(!jobIds.has(jobId), "duplicate experiment job"); jobIds.add(jobId);
      const worker = byWorker.get(job.workerId);
      requireValue(worker, "job references an undeclared Worker");
      requireValue(group.mode !== "parallel" || !groupWorkers.has(job.workerId), "parallel jobs cannot share a Worker checkout");
      groupWorkers.add(job.workerId);
      const manifestPath = assertNoReparse(job.manifestPath);
      const manifestBytes = fs.readFileSync(manifestPath);
      const manifest = JSON.parse(manifestBytes.toString("utf8").replace(/^\uFEFF/, ""));
      verifyManifestIntegrity(manifest, `job ${jobId}`);
      const expectedRuns = manifest.cases.reduce((sum, entry) => sum + entry.repeat, 0);
      requireValue(expectedRuns >= 1 && expectedRuns <= 25, "P0/P1 short shard must contain 1..25 runs");
      const batchTimeoutMs = job.batchTimeoutMs === undefined ? 300000 : job.batchTimeoutMs;
      requireValue(Number.isSafeInteger(batchTimeoutMs) && batchTimeoutMs > 0 && batchTimeoutMs <= 900000,
        "P0/P1 shard wall timeout must be within 15 minutes");
      const nonce = crypto.randomUUID().replace(/-/g, "");
      const identity = { workerId: worker.workerId, sessionEpoch: `session-${nonce}`,
        assignmentId: `assignment-${nonce}`, attemptId: `attempt-${nonce}` };
      const launch = { schema: "arena-worker.launch.v1", workerId: worker.workerId, sessionEpoch: identity.sessionEpoch,
        projectRoot: worker.projectRoot, stateRoot: path.join(worker.projectRoot, "tmp", "arena-worker", identity.sessionEpoch),
        saveRoot: worker.saveRoot, outputRoot: path.join(worker.projectRoot, "tmp", "arena-calibration"),
        swfOrigin: path.join(worker.projectRoot, "CRAZYFLASHER7MercenaryEmpire.swf"), slot: `cf7_agent_aw_${nonce}`, performance,
        allowFaultInjection: !!plan.faultIntent && worker.workerId === plan.faultIntent.faultWorkerId };
      if (projection !== undefined) Object.assign(launch, { schema: "arena-worker.launch.v2" }, JSON.parse(JSON.stringify(projection)));
      return { jobId, ...identity, batchId: manifest.batchId, manifestHash: manifest.manifestHash,
        sourceManifestPath: manifestPath, manifestSha256: sha256Bytes(manifestBytes), expectedRuns, batchTimeoutMs,
        launch, launchPath: path.join(launch.stateRoot, "launch.json"),
        expectedReceiptPath: path.join(workerAttemptDirectory(launch, identity), "shard-receipt.json") };
    });
    return { groupId, mode: group.mode, experiment, performance, projection, jobs };
  });
  requireValue(plan.comparisons === undefined || Array.isArray(plan.comparisons), "comparisons must be an array");
  for (const comparison of plan.comparisons || []) {
    requireValue(comparison && groupIds.has(comparison.baseline) && groupIds.has(comparison.candidate)
      && comparison.baseline !== comparison.candidate, "comparison must reference two declared groups");
  }
  const experimentRoot = resolveInside(sourceRoot, path.join("tmp", "arena-worker-experiments", plan.experimentId), "experiment output");
  fs.mkdirSync(path.dirname(experimentRoot), { recursive: true });
  fs.mkdirSync(experimentRoot); // Create-new experiment boundary; no resume/replay in P0/P1.
  const measurementPlan = { schema: "arena-worker.p0-plan.v1", groups: [], comparisons: plan.comparisons || [] };
  for (const group of groups) {
    group.saveProtectionPath = path.join(experimentRoot, "groups", group.groupId, "save-protection.json");
    group.groupReportPath = path.join(experimentRoot, "groups", group.groupId, "group-report.json");
    measurementPlan.groups.push({ groupId: group.groupId, expectedConcurrency: group.experiment.concurrency,
      receiptPaths: group.jobs.map((job) => job.expectedReceiptPath), saveProtectionPath: group.saveProtectionPath,
      groupReportPath: group.groupReportPath });
    for (const job of group.jobs) {
      const worker = byWorker.get(job.workerId);
      const bytes = fs.readFileSync(job.sourceManifestPath);
      requireValue(sha256Bytes(bytes) === job.manifestSha256, "manifest changed during experiment freeze");
      job.manifestPath = path.join(experimentRoot, "inputs", `${job.jobId}-manifest.json`);
      writeNewBytes(job.manifestPath, bytes);
      const launchBytes = Buffer.from(`${JSON.stringify(job.launch, null, 2)}\n`, "utf8");
      job.launchSha256 = sha256Bytes(launchBytes);
      writeNewBytes(job.launchPath, launchBytes);
      const seedBytes = fs.readFileSync(worker.seedPath);
      requireValue(sha256Bytes(seedBytes) === worker.seedSha256, "seed source changed during experiment freeze");
      job.seedTargetPath = path.join(worker.saveRoot, `${job.launch.slot}.json`);
      writeNewBytes(job.seedTargetPath, seedBytes);
    }
  }
  const frozen = { schema: "arena-worker.frozen-experiment.v1", experimentId: plan.experimentId,
    createdAt: new Date().toISOString(), sourceRoot, experimentRoot, inputPlanHash: sha256OfValue(plan),
    faultIntent: plan.faultIntent ? JSON.parse(JSON.stringify(plan.faultIntent)) : null,
    sharedObjectsRoot, saveRoots, workers, groups, measurementPlan, frozenPlanHash: "" };
  const hashInput = { ...frozen }; delete hashInput.frozenPlanHash;
  frozen.frozenPlanHash = sha256OfValue(hashInput);
  writeImmutableJson(path.join(experimentRoot, "frozen-plan.json"), frozen);
  writeImmutableJson(path.join(experimentRoot, "measurement-plan.json"), measurementPlan);
  writeImmutableJson(path.join(experimentRoot, "expected-receipts.json"), {
    frozenPlanHash: frozen.frozenPlanHash, receipts: groups.flatMap((group) => group.jobs.map((job) => ({
      groupId: group.groupId, jobId: job.jobId, workerId: job.workerId, sessionEpoch: job.sessionEpoch,
      assignmentId: job.assignmentId, attemptId: job.attemptId, receiptPath: job.expectedReceiptPath }))) });
  return frozen;
}

async function executeExperiment(frozen, dependencies = {}) {
  const hashInput = { ...frozen }; delete hashInput.frozenPlanHash;
  requireValue(sha256OfValue(hashInput) === frozen.frozenPlanHash, "frozen experiment plan integrity mismatch");
  const journalPath = path.join(frozen.experimentRoot, "experiment-report.json");
  requireValue(!fs.existsSync(journalPath), "experiment already has a terminal report");
  writeNewBytes(path.join(frozen.experimentRoot, "execution-started.json"), JSON.stringify({
    frozenPlanHash: frozen.frozenPlanHash, processId: process.pid, startedAt: new Date().toISOString(),
  }));
  const workerMap = new Map(frozen.workers.map((worker) => [worker.workerId, worker]));
  const groupResults = [];
  const errors = [];
  let stopped = false;
  let activeGroup = null;
  try {
  for (const group of frozen.groups) {
    if (stopped) break;
    activeGroup = { group, startedAt: new Date().toISOString(), outcomes: [] };
    const sourceBefore = verifySeedSources(frozen.workers);
    if (!sourceBefore.every((entry) => entry.unchanged)) {
      stopped = true;
      const rejected = { groupId: group.groupId, mode: group.mode, outcomes: [], seedSources: sourceBefore,
        seedSourcesUnchanged: false, globalSaveUnchanged: false, stopBeforeNextGroup: true,
        error: "read-only seed source changed before a group", ...groupTiming(activeGroup.startedAt) };
      writeImmutableJson(group.groupReportPath, rejected);
      groupResults.push(rejected);
      activeGroup = null;
      break;
    }
    const protectionOptions = { saveRoots: frozen.saveRoots, sharedObjectsRoot: frozen.sharedObjectsRoot,
      allowedTargets: group.jobs.map((job) => ({ swfOrigin: job.launch.swfOrigin, slot: job.launch.slot })) };
    const before = captureGlobalProtectionSnapshot(protectionOptions);
    const groupRoot = path.dirname(group.saveProtectionPath);
    writeImmutableJson(path.join(groupRoot, "save-before.json"), before);
    const runJob = async (job) => {
      const worker = workerMap.get(job.workerId);
      assertRuntimeIdentity(worker.runtimeIdentity,
        await (dependencies.resolveRuntime || resolveWorkerRuntimeIdentity)(worker.projectRoot, worker.candidateRoot));
      requireValue(hashFile(job.manifestPath) === job.manifestSha256, "frozen manifest bytes changed before launch");
      requireValue(hashFile(job.launchPath) === job.launchSha256, "frozen launch bytes changed before execution");
      requireValue(hashFile(job.seedTargetPath) === worker.seedSha256, "fresh dedicated seed bytes changed before launch");
      return (dependencies.runShard || runWorkerShard)({ launchPath: job.launchPath, candidateRoot: worker.candidateRoot,
        manifestPath: job.manifestPath, assignmentId: job.assignmentId, attemptId: job.attemptId,
        expectedLaunch: job.launch, expectedLaunchSha256: job.launchSha256,
        batchTimeoutMs: job.batchTimeoutMs, experiment: group.experiment, resourcePaths: worker.resourcePaths },
      dependencies.shardDependencies || {});
    };
    let settled;
    if (group.mode === "parallel") settled = await Promise.allSettled(group.jobs.map(runJob));
    else {
      settled = [];
      for (const job of group.jobs) {
        const result = (await Promise.allSettled([runJob(job)]))[0];
        settled.push(result);
        let safeToContinue = false;
        try {
          const receipt = readJson(job.expectedReceiptPath, 16 * 1024 * 1024);
          safeToContinue = receipt.shutdown && receipt.shutdown.hostExited === true && receipt.shutdown.flashExited === true
            && (!receipt.shutdown.forced || receipt.shutdown.forced.length === 0)
            && receipt.saveProtection && receipt.saveProtection.unchanged === true;
        } catch (_error) { }
        if (!safeToContinue) break;
      }
      while (settled.length < group.jobs.length) settled.push({ status: "rejected", reason: new Error("not started after unverified cleanup/protection") });
    }
    const outcomes = group.jobs.map((job, index) => {
      const result = settled[index];
      const outcome = { jobId: job.jobId, expectedReceiptPath: job.expectedReceiptPath,
        promiseStatus: result.status, error: result.status === "rejected" ? result.reason.message : null,
        receiptPresent: false, status: "unknown", cleanupVerified: false, protectedSavesVerified: false };
      try {
        requireValue(result.status !== "fulfilled" || result.value.receiptPath === job.expectedReceiptPath,
          "runner returned an unexpected receipt path");
        const receipt = readJson(job.expectedReceiptPath, 16 * 1024 * 1024);
        assertTuple(receipt, job, ["workerId", "sessionEpoch", "assignmentId", "attemptId", "batchId", "manifestHash"]);
        outcome.receiptPresent = true;
        outcome.receiptSha256 = hashFile(job.expectedReceiptPath);
        outcome.status = receipt.status;
        outcome.cleanupVerified = !!receipt.shutdown && receipt.shutdown.hostExited === true && receipt.shutdown.flashExited === true;
        outcome.protectedSavesVerified = !!receipt.saveProtection && receipt.saveProtection.unchanged === true;
        outcome.runtimeResourcesVerified = receipt.runtimeUnchanged === true && receipt.resourcesUnchanged === true;
        outcome.forcedRecycling = !!receipt.shutdown && Array.isArray(receipt.shutdown.forced) && receipt.shutdown.forced.length > 0;
      } catch (error) { outcome.error = outcome.error || error.message; }
      return outcome;
    });
    activeGroup.outcomes = outcomes;
    let protection = { before, after: null, unchanged: false, differences: [], error: null };
    try {
      protection.after = captureGlobalProtectionSnapshot(protectionOptions);
      protection.differences = compareProtectedSaveSnapshots(before, protection.after);
      protection.unchanged = protection.differences.length === 0;
    } catch (error) { protection.error = error.message; }
    writeImmutableJson(group.saveProtectionPath, protection);
    const sourceAfter = verifySeedSources(frozen.workers);
    const seedSourcesUnchanged = sourceAfter.every((entry) => entry.unchanged);
    stopped = !protection.unchanged || !seedSourcesUnchanged || outcomes.some((entry) => !entry.cleanupVerified
      || !entry.protectedSavesVerified || !entry.runtimeResourcesVerified || entry.forcedRecycling);
    const groupResult = { groupId: group.groupId, mode: group.mode, outcomes, seedSources: sourceAfter,
      seedSourcesUnchanged, saveProtectionPath: group.saveProtectionPath, globalSaveUnchanged: protection.unchanged,
      stopBeforeNextGroup: stopped, ...groupTiming(activeGroup.startedAt) };
    writeImmutableJson(group.groupReportPath, groupResult);
    groupResults.push(groupResult);
    activeGroup = null;
  }
  } catch (error) {
    stopped = true;
    errors.push({ phase: "coordinator", message: error.message });
    if (activeGroup) {
      const sourceAfter = verifySeedSources(frozen.workers);
      const rejected = { groupId: activeGroup.group.groupId, mode: activeGroup.group.mode, outcomes: activeGroup.outcomes,
        seedSources: sourceAfter, seedSourcesUnchanged: sourceAfter.every((entry) => entry.unchanged),
        globalSaveUnchanged: false, stopBeforeNextGroup: true, error: error.message, ...groupTiming(activeGroup.startedAt) };
      try { writeImmutableJson(activeGroup.group.groupReportPath, rejected); }
      catch (reportError) { errors.push({ phase: "group_report", message: reportError.message }); }
      groupResults.push(rejected);
    }
  }
  const measurement = measurePlan(frozen.measurementPlan, frozen.experimentRoot,
    dependencies.fixture === true ? { allowFixtureEvidence: true } : {});
  const measurementPath = path.join(frozen.experimentRoot, "measurement.json");
  writeImmutableJson(measurementPath, measurement);
  const report = { schema: "arena-worker.experiment-report.v1", experimentId: frozen.experimentId,
    frozenPlanHash: frozen.frozenPlanHash, completedAt: new Date().toISOString(), stopped,
    expectedGroups: frozen.groups.length, completedGroups: groupResults.length, groups: groupResults, errors,
    seedSources: verifySeedSources(frozen.workers),
    measurementPath, qualified: measurement.qualified,
    status: !stopped && measurement.qualified ? "completed" : "unqualified" };
  writeImmutableJson(journalPath, report);
  return { report, reportPath: journalPath, frozenPlan: frozen };
}

async function runExperiment(plan, dependencies = {}) {
  const frozen = prepareExperiment(plan, dependencies);
  return executeExperiment(frozen, dependencies);
}

if (require.main === module) {
  Promise.resolve().then(async () => {
    const args = process.argv.slice(2);
    if (args.length === 1 && args[0] === "--help") {
      console.log([
        "Usage: node run-worker-experiment.js --plan <experiment-plan.json>",
        "Plan schema: arena-worker.experiment-plan.v1",
        "Declare experimentId, workers, groups, saveRoots, sharedObjectsRoot, and optional comparisons.",
        "Each worker names workerId, projectRoot, candidateRoot, and a read-only seedPath.",
        "Groups use mode=serial or parallel and 1..2 explicit jobs with workerId and manifestPath.",
        "Optional group.performance: {preset:balanced|performance|quality, mode:auto|fixed, maxRenderHeight:0|360|540|720|900|1080|1440|2160}.",
        "Every job gets a fresh session and dedicated slot. Existing experiments and evidence are never replayed or overwritten.",
      ].join("\n"));
      return;
    }
    requireValue(args.length === 2 && args[0] === "--plan", "Usage: node run-worker-experiment.js --plan <experiment-plan.json>");
    const result = await runExperiment(readExperimentPlan(path.resolve(args[1])));
    console.log(JSON.stringify({ status: result.report.status, qualified: result.report.qualified,
      reportPath: result.reportPath, completedGroups: result.report.completedGroups }, null, 2));
    if (!result.report.qualified) process.exitCode = 1;
  }).catch((error) => { console.error(error.message); process.exitCode = 1; });
}

module.exports = { executeExperiment, prepareExperiment, readExperimentPlan, runExperiment, verifySeedSources };
