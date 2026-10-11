#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { assertRuntimeIdentity } = require("../lib/runtime-process-identity");
const { sha256OfValue } = require("./lib/arena-calibration-core");
const { sha256Bytes, writeNewBytes } = require("./lib/immutable-evidence");
const { ID_FIELDS, RUN_FIELDS, assertTuple, createWorkerClient, queryProcess, readJson, resolveInside,
  safeId, samePath, validateOwner, validateProcessObservation,
  verifyProcessOwner } = require("./lib/arena-worker-client");
const { verifyManifestIntegrity } = require("./lib/gate-f-campaign");
const { inspectReceipt, saveProtectionIsValid } = require("./measure-worker-p0");
const { prepareExperiment, executeExperiment, readExperimentPlan } = require("./run-worker-experiment");
const { runWorkerShard } = require("./run-worker-shard");

const MAX_OBSERVATION_AGE_MS = 10000;
const BATCH_FIELDS = [...ID_FIELDS, "batchId", "manifestHash"];
const clone = (value) => JSON.parse(JSON.stringify(value));
const requireValue = (value, message) => { if (!value) throw new Error(message); };
const writeNewJson = (file, value) => writeNewBytes(file, `${JSON.stringify(value, null, 2)}\n`);

function fresh(value, now, label) {
  const time = Date.parse(value);
  requireValue(Number.isFinite(time) && time <= now && now - time <= MAX_OBSERVATION_AGE_MS,
    `${label} is stale, future, or missing`);
}

function processIdentity(value, label) {
  requireValue(value && Number.isSafeInteger(value.pid) && value.pid > 0, `${label} has no exact PID`);
  validateProcessObservation(value, value.pid);
  return { pid: value.pid, processStartUtcTicks: value.processStartUtcTicks, processPath: value.processPath };
}

function sameProcess(left, right) {
  return left.pid === right.pid && left.processStartUtcTicks === right.processStartUtcTicks
    && samePath(left.processPath, right.processPath);
}

function assertRunTuple(actual, expected) {
  RUN_FIELDS.forEach((field) => requireValue(actual && actual[field] === expected[field], `run tuple mismatch: ${field}`));
}

function validateProbePlan(plan, faultWorkerId) {
  safeId(faultWorkerId, "fault-worker");
  requireValue(plan && plan.schema === "arena-worker.experiment-plan.v1"
    && Array.isArray(plan.workers) && plan.workers.length === 2
    && Array.isArray(plan.groups) && plan.groups.length === 1,
  "isolation probe requires exactly two declared Workers and one group");
  const group = plan.groups[0];
  requireValue(group.mode === "parallel" && Array.isArray(group.jobs) && group.jobs.length === 2,
    "isolation probe requires one parallel group with exactly two jobs");
  const ids = plan.workers.map((worker) => worker.workerId);
  requireValue(new Set(ids).size === 2 && ids.includes(faultWorkerId)
    && new Set(group.jobs.map((job) => job.workerId)).size === 2
    && group.jobs.every((job) => ids.includes(job.workerId)), "fault-worker and neighbor must be the two declared jobs");
  requireValue((plan.comparisons === undefined || Array.isArray(plan.comparisons) && plan.comparisons.length === 0)
    && plan.faultIntent === undefined, "isolation probe cannot contain speed comparisons or replace a prior fault intent");
}

// Host exposes its current case/run IDs. Hash and repeat are derived only from
// the frozen manifest; this is not an AS2 success echo before the fault.
function selectFaultTarget(contexts, faultWorkerId, observations, now) {
  requireValue(contexts.length === 2 && new Set(contexts.map((entry) => entry.job.workerId)).size === 2,
    "two independent assignments are required");
  requireValue(contexts.some((entry) => entry.job.workerId === faultWorkerId), "unknown fault-worker");
  const samples = contexts.map(({ job, manifest, runtimeIdentity }) => {
    requireValue(job.launch.allowFaultInjection === (job.workerId === faultWorkerId),
      "only the declared fault target may enable atomic fault injection");
    const sample = observations.get(job.workerId);
    requireValue(sample, `no status for ${job.workerId}`);
    fresh(sample.receivedAtUtc, now, "Worker status");
    validateOwner(sample.owner, job.launch, runtimeIdentity);
    const response = sample.response;
    requireValue(response && response.success === true && response.ok === true, "Worker response was not accepted");
    assertTuple(response, job, ID_FIELDS);
    assertRuntimeIdentity(runtimeIdentity, response.runtimeIdentity);
    const arena = response.arenaStatus;
    assertTuple(arena, job, BATCH_FIELDS);
    requireValue(arena.state === "running" && arena.transportPoisoned === false,
      "both exact Worker batches must still be running and unpoisoned");
    requireValue(typeof arena.currentRunId === "string" && arena.currentRunId.length > 0, "currentRunId is required");
    const testCase = manifest.cases.find((entry) => entry.caseId === arena.currentCaseId);
    requireValue(testCase, "current case is not in the frozen manifest");
    let repeatIndex = null;
    for (let index = 1; index <= testCase.repeat; index++) {
      if (arena.currentRunId === `${testCase.caseId}-r${String(index).padStart(3, "0")}`) repeatIndex = index;
    }
    requireValue(repeatIndex !== null, "current run is not an exact frozen case/repeat");
    const host = processIdentity({ ...sample.owner, pid: sample.owner.hostPid }, "Worker Host");
    const flash = processIdentity(response.flashProcess, "Worker Flash");
    resolveInside(job.launch.projectRoot, flash.processPath, "owned Flash executable");
    if (job.workerId === faultWorkerId) {
      const observed = response.flashProcessObservation;
      requireValue(observed && observed.observed === true, "target Flash must have an actual process observation");
      fresh(observed.sampledAtUtc, now, "target Flash observation");
      requireValue(sameProcess(flash, processIdentity(observed, "observed target Flash")), "target Flash observation identity mismatch");
    }
    return { workerId: job.workerId, host, flash, owner: clone(sample.owner), response: clone(response),
      receivedAtUtc: sample.receivedAtUtc,
      tuple: { ...Object.fromEntries(BATCH_FIELDS.map((field) => [field, job[field]])),
        caseId: testCase.caseId, caseHash: testCase.caseHash, runId: arena.currentRunId, repeatIndex } };
  });
  requireValue(!samePath(contexts[0].job.launch.projectRoot, contexts[1].job.launch.projectRoot), "Worker roots must differ");
  requireValue(new Set(samples.flatMap((sample) => [sample.host.pid, sample.flash.pid])).size === 4,
    "target Flash, neighbor Flash, and both Hosts must have distinct PIDs");
  requireValue(new Set(samples.flatMap((sample) => [sample.owner.httpPort, sample.owner.socketPort])).size === 4,
    "Worker endpoints must be independent");
  return { tupleSource: "host_current_ids_plus_frozen_manifest", samples,
    target: samples.find((sample) => sample.workerId === faultWorkerId),
    neighbor: samples.find((sample) => sample.workerId !== faultWorkerId) };
}

function validateAtomicFaultReceipt(receipt, before, faultId, startedAtUtc, requireComplete = true) {
  requireValue(receipt && receipt.schema === "arena-worker.fault-receipt.v1"
    && receipt.faultId === faultId, "missing or foreign atomic fault receipt");
  assertRunTuple(receipt, before.target.tuple);
  requireValue(sameProcess(processIdentity(receipt.flashProcess, "fault receipt Flash"), before.target.flash),
    "atomic fault receipt process identity mismatch");
  requireValue(Number.isSafeInteger(receipt.socketGeneration) && receipt.socketGeneration > 0,
    "atomic fault receipt has no socket generation");
  const claimed = Date.parse(receipt.claimedAtUtc);
  const started = Date.parse(startedAtUtc);
  requireValue(Number.isFinite(started) && Number.isFinite(claimed) && claimed >= started,
    "atomic fault claim time does not follow this request");
  requireValue(["claimed", "kill_issued", "killed", "unknown"].includes(receipt.outcome), "unknown atomic fault receipt outcome");
  if (!requireComplete) return receipt;
  const issued = Date.parse(receipt.killIssuedAtUtc);
  const returned = Date.parse(receipt.killReturnedAtUtc);
  const exited = Date.parse(receipt.exitObservedAtUtc);
  requireValue(receipt.outcome === "killed" && receipt.killAttempted === true && receipt.killIssued === true
    && receipt.processExitObserved === true && !receipt.error
    && Number.isFinite(issued) && Number.isFinite(returned) && Number.isFinite(exited)
    && claimed <= issued && issued <= returned && returned <= exited,
  "no exact successful atomic fault termination was observed");
  return receipt;
}

async function requestAtomicFault(client, before, faultId, startedAtUtc) {
  const result = { hostReceipt: null, delivery: "acknowledged", deliveryError: null,
    receiptReads: [], error: null };
  try {
    const response = await client.call("faultStopFlash", { ...before.target.tuple, faultId });
    result.hostReceipt = response.faultReceipt || null;
  } catch (error) {
    result.delivery = error.response ? "rejected" : "unknown";
    result.deliveryError = error.message;
    result.hostReceipt = error.response && error.response.faultReceipt || null;
  }
  try {
    // The one POST is consumed even if delivery is unknown. Only this same
    // pinned owner's read-only status can reconcile its exact session-cached
    // claim. A missing receipt remains unknown; Host memory is not durable.
    if (result.delivery === "unknown" || result.hostReceipt
        && ["claimed", "kill_issued"].includes(result.hostReceipt.outcome)) {
      for (let index = 0; index < 3; index++) {
        const response = await client.call("status");
        const receipt = response.faultReceipt || null;
        result.receiptReads.push({ receivedAtUtc: new Date().toISOString(), faultReceipt: receipt });
        if (!receipt) break;
        validateAtomicFaultReceipt(receipt, before, faultId, startedAtUtc, false);
        result.hostReceipt = receipt;
        if (!["claimed", "kill_issued"].includes(receipt.outcome)) break;
        if (index < 2) await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }
    validateAtomicFaultReceipt(result.hostReceipt, before, faultId, startedAtUtc);
  } catch (error) { result.error = error.message; }
  return result;
}

function verifyBoundFaultRun(receipt, rows, before, target, hostReceipt) {
  const current = rows.find((row) => row.runId === before.tuple.runId);
  assertRunTuple(current, before.tuple);
  if (target) {
    requireValue(sha256OfValue(receipt.faultReceipt) === sha256OfValue(hostReceipt),
      "target shard did not retain the same atomic fault receipt");
    requireValue(receipt.status === "failed" && receipt.terminalStatus === "failed"
      && receipt.finalArenaStatus && receipt.finalArenaStatus.transportPoisoned === true
      && current.status === "bridge_lost"
      && Date.parse(current.completedAt) >= Date.parse(hostReceipt.killIssuedAtUtc),
    "target did not report the bound in-flight bridge_lost failure");
  } else {
    const killedAt = Date.parse(hostReceipt.exitObservedAtUtc);
    requireValue(receipt.status === "completed" && receipt.terminalStatus === "completed"
      && ["finished", "timeout"].includes(current.status)
      && Date.parse(current.completedAt) > killedAt && Date.parse(receipt.completedAt) > killedAt,
    "neighbor must complete its observed run after the actual fault termination");
  }
  return current;
}

// Potentially slow process screening finishes before the final status refresh.
// The durable claim then binds only that fresh tuple and the already screened
// process/endpoint identities; it never queries processes or rewrites a claim.
function createInjectionGate(contexts, faultWorkerId, { processProbe = queryProcess, now = Date.now } = {}) {
  let claimed = false;
  let screened = null;
  return {
    get claimed() { return claimed; },
    preview: (observations) => selectFaultTarget(contexts, faultWorkerId, observations, now()),
    screen(observations) {
      requireValue(!claimed, "fault injection was already claimed; it cannot be retried");
      screened = null;
      const selected = selectFaultTarget(contexts, faultWorkerId, observations, now());
      const processes = selected.samples.flatMap((sample) => [sample.host, sample.flash]);
      const verifiedProcesses = processes.map((identity) => verifyProcessOwner({ ...identity, hostPid: identity.pid }, processProbe));
      screened = { ...selected, verifiedProcesses, verifiedAtUtc: new Date(now()).toISOString() };
      return screened;
    },
    claim(observations) {
      requireValue(!claimed, "fault injection was already claimed; it cannot be retried");
      requireValue(screened, "fault process screening must complete before final status and claim");
      const selected = selectFaultTarget(contexts, faultWorkerId, observations, now());
      for (const sample of selected.samples) {
        const prior = screened.samples.find((entry) => entry.workerId === sample.workerId);
        requireValue(prior && sameProcess(sample.host, prior.host) && sameProcess(sample.flash, prior.flash)
          && sample.owner.httpPort === prior.owner.httpPort && sample.owner.socketPort === prior.owner.socketPort,
        "Worker process or endpoint changed after fault screening");
        requireValue(Date.parse(sample.receivedAtUtc) >= Date.parse(screened.verifiedAtUtc),
          "final Worker status must follow process screening");
      }
      claimed = true;
      return { ...selected, verifiedProcesses: screened.verifiedProcesses, verifiedAtUtc: screened.verifiedAtUtc };
    },
  };
}

function verifyProbeOutcome(frozen, fault, contexts, experiment) {
  requireValue(fault && fault.before && !fault.error, "no exact successful fault termination was observed");
  const hostReceipt = validateAtomicFaultReceipt(fault.hostReceipt, fault.before, fault.faultId, fault.startedAtUtc);
  requireValue(frozen.faultIntent && frozen.faultIntent.action === "host_atomic_fault_stop_flash_once"
    && frozen.faultIntent.faultId === fault.faultId
    && frozen.faultIntent.faultWorkerId === fault.before.target.workerId,
  "atomic fault receipt does not match the initially frozen fault intent");
  const group = frozen.groups[0];
  const receipts = contexts.map(({ job, runtimeIdentity }) => {
    const inspected = inspectReceipt(job.expectedReceiptPath, group.groupId);
    const receipt = inspected.receipt;
    assertTuple(receipt, job, BATCH_FIELDS);
    assertRuntimeIdentity(runtimeIdentity, receipt.runtimeIdentity);
    validateOwner(receipt.ownerSnapshot, job.launch, runtimeIdentity);
    const before = fault.before.samples.find((entry) => entry.workerId === job.workerId);
    requireValue(sameProcess(before.host, processIdentity({ ...receipt.ownerSnapshot, pid: receipt.ownerSnapshot.hostPid }, "receipt Host"))
      && sameProcess(before.flash, processIdentity(receipt.flashProcess, "receipt Flash")), "receipt process identity changed after the fault");
    requireValue(receipt.errors.length === 0 && (!receipt.shutdown.forced || receipt.shutdown.forced.length === 0),
      "Worker cleanup or control delivery has unresolved errors");
    const target = job.workerId === fault.before.target.workerId;
    const expectedFailureReasons = new Set(["attempt_failed", "runner_reported_failure", "incomplete_run_set", "failed_results_present"]);
    requireValue(inspected.reasons.every((reason) => target && expectedFailureReasons.has(reason)),
      `Worker receipt is unqualified: ${inspected.reasons.join(", ")}`);
    const rows = fs.readFileSync(receipt.resultPath, "utf8").split(/\r?\n/).filter((line) => line.trim()).map(JSON.parse);
    const current = verifyBoundFaultRun(receipt, rows, before, target, hostReceipt);
    return { workerId: job.workerId, receiptPath: job.expectedReceiptPath, receiptSha256: inspected.receiptSha256,
      resultPath: receipt.resultPath, resultSha256: receipt.resultSha256, status: receipt.status,
      boundRun: current, expectedFailureReasons: target ? inspected.reasons : [] };
  });
  const protection = readJson(group.saveProtectionPath, 16 * 1024 * 1024);
  requireValue(saveProtectionIsValid(protection), "global non-target save protection is not verified");
  requireValue(experiment.report.qualified === false && experiment.report.groups.length === 1
    && experiment.report.groups[0].seedSourcesUnchanged === true
    && experiment.report.seedSources.every((entry) => entry.unchanged === true),
  "expected fault must remain speed-unqualified and preserve seed sources");
  return { receipts, globalProtectionPath: group.saveProtectionPath,
    globalProtectionSha256: sha256Bytes(fs.readFileSync(group.saveProtectionPath)) };
}

async function runIsolationProbe(plan, faultWorkerId) {
  validateProbePlan(plan, faultWorkerId);
  const intent = { action: "host_atomic_fault_stop_flash_once", faultWorkerId, faultId: `fault-${crypto.randomUUID()}`, maximumAttempts: 1,
    maximumObservationAgeMs: MAX_OBSERVATION_AGE_MS, speedQualification: false };
  const declared = { ...clone(plan), faultIntent: intent };
  const frozen = prepareExperiment(declared);
  const contexts = frozen.groups[0].jobs.map((job) => {
    const bytes = fs.readFileSync(job.manifestPath);
    requireValue(sha256Bytes(bytes) === job.manifestSha256, "frozen probe manifest changed");
    const manifest = JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, ""));
    verifyManifestIntegrity(manifest, "isolation probe");
    const worker = frozen.workers.find((entry) => entry.workerId === job.workerId);
    return { job, manifest, runtimeIdentity: worker.runtimeIdentity };
  });
  const probePlanPath = path.join(frozen.experimentRoot, "isolation-plan.json");
  writeNewJson(probePlanPath, { schema: "arena-worker.isolation-plan.v1", faultIntent: intent,
    inputPlan: declared, inputPlanHash: sha256OfValue(declared), frozenPlanHash: frozen.frozenPlanHash,
    assignments: contexts.map(({ job }) => job), createdAtUtc: new Date().toISOString() });
  const observations = new Map();
  const clients = new Map();
  const gate = createInjectionGate(contexts, faultWorkerId);
  let checking = false;
  let fault = null;
  let lastRejection = "both running Workers have not been observed";
  const record = (workerId, response, client) => observations.set(workerId,
    { response: clone(response), owner: client.readOwner(), receivedAtUtc: new Date().toISOString() });
  async function maybeInject() {
    if (checking || gate.claimed) return;
    try { gate.preview(observations); } catch (error) { lastRejection = error.message; return; }
    checking = true;
    try {
      gate.screen(observations);
      // Refresh only read-only status through the same authenticated clients.
      await Promise.all(contexts.map(async ({ job }) => {
        const client = clients.get(job.workerId);
        record(job.workerId, await client.call("status"), client);
      }));
      const before = gate.claim(observations);
      fault = { before, faultId: intent.faultId, startedAtUtc: new Date().toISOString(),
        completedAtUtc: null, hostReceipt: null, error: null };
      writeNewJson(path.join(frozen.experimentRoot, "fault-attempt.json"), { schema: "arena-worker.fault-attempt.v1",
        probePlanPath, frozenPlanHash: frozen.frozenPlanHash, faultIntent: intent, ...fault });
      try {
        // This observation remains a prefilter. Only the target Host's atomic
        // pending-run/held-process check can admit the already selected tuple.
        selectFaultTarget(contexts, faultWorkerId, observations, Date.now());
        Object.assign(fault, await requestAtomicFault(clients.get(faultWorkerId), before, fault.faultId, fault.startedAtUtc));
      }
      catch (error) { fault.error = error.message; } // Unknown termination is never retried.
      fault.completedAtUtc = new Date().toISOString();
      writeNewJson(path.join(frozen.experimentRoot, "fault-result.json"), { schema: "arena-worker.fault-result.v1", ...fault });
    } catch (error) { lastRejection = error.message; if (fault) fault.error = fault.error || error.message; }
    finally { checking = false; }
  }
  let experiment = null;
  let proof = null;
  const errors = [];
  try {
    experiment = await executeExperiment(frozen, { runShard: (options) => {
      const context = contexts.find(({ job }) => job.workerId === options.expectedLaunch.workerId);
      requireValue(context, "unexpected Worker assignment");
      assertTuple(options, context.job, ["assignmentId", "attemptId"]);
      const client = createWorkerClient(context.job.launch, context.runtimeIdentity);
      clients.set(context.job.workerId, client);
      return runWorkerShard(options, { client: { readOwner: () => client.readOwner(), async call(action, fields) {
        const response = await client.call(action, fields);
        if (action === "status" || action === "startBatch") {
          record(context.job.workerId, response, client);
          await maybeInject();
        }
        return response;
      } } });
    } });
    proof = verifyProbeOutcome(frozen, fault, contexts, experiment);
  } catch (error) { errors.push(error.message); }
  const reportPath = path.join(frozen.experimentRoot, "isolation-report.json");
  const report = { schema: "arena-worker.isolation-report.v1", evidenceKind: "worker_live_execution",
    status: proof ? "isolation_verified" : "failed", speedQualified: false,
    probePlanPath, frozenPlanHash: frozen.frozenPlanHash, faultWorkerId,
    faultClaimed: gate.claimed, fault, lastRejection: fault && !fault.error ? null : lastRejection,
    experimentReportPath: experiment && experiment.reportPath,
    expectedReceiptPaths: contexts.map(({ job }) => job.expectedReceiptPath),
    globalProtectionPath: frozen.groups[0].saveProtectionPath, proof, errors,
    completedAtUtc: new Date().toISOString() };
  writeNewJson(reportPath, report);
  return { report, reportPath };
}

function parseArgs(args) {
  requireValue(args.length === 4, "Usage: node run-worker-isolation-probe.js --plan <plan.json> --fault-worker <workerId>");
  const parsed = {};
  for (let index = 0; index < args.length; index += 2) {
    requireValue(["--plan", "--fault-worker"].includes(args[index]) && !Object.hasOwn(parsed, args[index])
      && typeof args[index + 1] === "string" && args[index + 1].length > 0, "explicit unique --plan and --fault-worker are required");
    parsed[args[index]] = args[index + 1];
  }
  return { planPath: path.resolve(parsed["--plan"]), faultWorkerId: safeId(parsed["--fault-worker"], "fault-worker") };
}

if (require.main === module) {
  Promise.resolve().then(async () => {
    const args = process.argv.slice(2);
    if (args.length === 1 && args[0] === "--help") {
      console.log("Usage: node run-worker-isolation-probe.js --plan <arena-worker.experiment-plan.v1.json> --fault-worker <workerId>\nExactly two Workers, one parallel group, one exact owned Flash termination. Isolation evidence only; never speed qualification.");
      return;
    }
    const options = parseArgs(args);
    const result = await runIsolationProbe(readExperimentPlan(options.planPath), options.faultWorkerId);
    console.log(JSON.stringify({ status: result.report.status, speedQualified: false, reportPath: result.reportPath }, null, 2));
    if (result.report.status !== "isolation_verified") process.exitCode = 1;
  }).catch((error) => { console.error(error.message); process.exitCode = 1; });
}

module.exports = { MAX_OBSERVATION_AGE_MS, createInjectionGate, parseArgs, requestAtomicFault, selectFaultTarget,
  validateAtomicFaultReceipt, validateProbePlan, verifyBoundFaultRun, verifyProbeOutcome, runIsolationProbe };
