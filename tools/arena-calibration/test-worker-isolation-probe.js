#!/usr/bin/env node
"use strict";

const assert = require("assert");
const os = require("os");
const path = require("path");
const { MAX_OBSERVATION_AGE_MS, createInjectionGate, parseArgs, requestAtomicFault, selectFaultTarget,
  validateAtomicFaultReceipt, validateProbePlan, verifyBoundFaultRun, verifyProbeOutcome } = require("./run-worker-isolation-probe");

const NOW = Date.parse("2026-10-11T00:00:10.000Z");
const clone = (value) => JSON.parse(JSON.stringify(value));
let assertions = 0;
function rejects(action, pattern) { assert.throws(action, pattern); assertions++; }

function fixture() {
  const contexts = ["w01", "w02"].map((workerId, index) => {
    const root = path.join(os.tmpdir(), "cf7-isolation-readonly-fixture", workerId, "resources");
    const launch = { schema: "arena-worker.launch.v1", workerId, sessionEpoch: `session-${workerId}`,
      projectRoot: root, stateRoot: path.join(root, "tmp", "arena-worker", `session-${workerId}`),
      saveRoot: path.join(root, "saves"), outputRoot: path.join(root, "tmp", "arena-calibration"),
      swfOrigin: path.join(root, "CRAZYFLASHER7MercenaryEmpire.swf"), slot: `cf7_agent_${workerId}`,
      performance: { preset: "balanced", mode: "auto", maxRenderHeight: 0 }, allowFaultInjection: index === 0 };
    const runtimeIdentity = { runtimeMode: "isolated_candidate", processPath: path.join(root, "candidate", "Core.exe"),
      coreSha256: "A".repeat(64), buildIdentity: "B".repeat(64), payloadClosure: "C".repeat(64) };
    const job = { workerId, sessionEpoch: launch.sessionEpoch, assignmentId: `assignment-${workerId}`,
      attemptId: `attempt-${workerId}`, batchId: "batch-fixture", manifestHash: "sha256:manifest-fixture", launch };
    const manifest = { cases: [{ caseId: "case-fixture", caseHash: "sha256:case-fixture", repeat: 2 }] };
    const appData = path.join(os.tmpdir(), "cf7-isolation-readonly-fixture", "appdata");
    const owner = { ...launch, schema: "arena-worker.owner.v1", executionMode: "arena_worker",
      hostPid: 910 + index * 2, processStartUtcTicks: `63840000000000000${index + 1}`,
      processPath: runtimeIdentity.processPath, runtimeIdentity, httpPort: 33000 + index * 2,
      socketPort: 33001 + index * 2, appData,
      sharedObjectsRoot: path.join(appData, "Macromedia", "Flash Player", "#SharedObjects") };
    const flash = { pid: 911 + index * 2, processStartUtcTicks: `63840000000000001${index + 1}`,
      processPath: path.join(root, "Flash.exe") };
    const tuple = Object.fromEntries(["workerId", "sessionEpoch", "assignmentId", "attemptId", "batchId", "manifestHash"]
      .map((field) => [field, job[field]]));
    const response = { ...tuple, success: true, ok: true, runtimeIdentity, flashProcess: flash,
      flashProcessObservation: { ...flash, observed: true, sampledAtUtc: new Date(NOW - 100).toISOString() },
      arenaStatus: { ...tuple, state: "running", transportPoisoned: false,
        currentCaseId: "case-fixture", currentRunId: "case-fixture-r001" } };
    return { job, runtimeIdentity, manifest, sample: { owner, response, receivedAtUtc: new Date(NOW).toISOString() } };
  });
  const observations = new Map(contexts.map((entry) => [entry.job.workerId, clone(entry.sample)]));
  const processes = new Map();
  for (const sample of observations.values()) {
    processes.set(sample.owner.hostPid, { pid: sample.owner.hostPid, processPath: sample.owner.processPath,
      processStartUtcTicks: sample.owner.processStartUtcTicks });
    processes.set(sample.response.flashProcess.pid, clone(sample.response.flashProcess));
  }
  return { contexts, observations, processes, probe: (pid) => processes.get(pid) || null };
}

function rejectSelection(mutate, pattern) {
  const f = fixture();
  mutate(f, f.observations.get("w01"), f.observations.get("w02"));
  rejects(() => selectFaultTarget(f.contexts, "w01", f.observations, NOW), pattern);
}

async function main() {
  rejects(() => parseArgs(["--plan", "x.json"]), /Usage/);
  rejects(() => parseArgs(["--plan", "x.json", "--plan", "y.json"]), /unique/);
  rejects(() => parseArgs(["--plan", "x.json", "--fault-worker", "../other"]), /fault-worker/);
  const plan = { schema: "arena-worker.experiment-plan.v1", workers: [{ workerId: "w01" }, { workerId: "w02" }],
    groups: [{ mode: "parallel", jobs: [{ workerId: "w01" }, { workerId: "w02" }] }] };
  rejects(() => validateProbePlan(plan, "w03"), /declared jobs/);
  rejects(() => validateProbePlan({ ...plan, workers: plan.workers.slice(0, 1) }, "w01"), /exactly two/);
  rejects(() => validateProbePlan({ ...plan, groups: [...plan.groups, ...plan.groups] }, "w01"), /one group/);
  rejects(() => validateProbePlan({ ...plan, groups: [{ ...plan.groups[0], mode: "serial" }] }, "w01"), /parallel/);
  rejects(() => validateProbePlan({ ...plan, comparisons: [{}] }, "w01"), /speed comparisons/);
  rejects(() => validateProbePlan({ ...plan, faultIntent: {} }, "w01"), /prior fault intent/);
  rejectSelection((f) => f.observations.delete("w02"), /no status/);
  rejectSelection((f) => { f.contexts[0].job.launch.allowFaultInjection = false; }, /declared fault target/);
  rejectSelection((f) => { f.contexts[1].job.launch.allowFaultInjection = true; }, /declared fault target/);
  rejectSelection((_f, target) => { target.response.assignmentId = "foreign"; }, /assignmentId/);
  rejectSelection((_f, target) => { target.response.arenaStatus.sessionEpoch = "old-session"; }, /sessionEpoch/);
  rejectSelection((_f, _target, neighbor) => { neighbor.response.arenaStatus.attemptId = "foreign"; }, /attemptId/);
  rejectSelection((_f, target) => { target.owner.hostPid = 999; target.owner.processPath = path.join(os.tmpdir(), "foreign.exe"); }, /exact isolated candidate/);
  rejectSelection((_f, target) => { target.receivedAtUtc = new Date(NOW - MAX_OBSERVATION_AGE_MS - 1).toISOString(); }, /stale/);
  rejectSelection((_f, _target, neighbor) => { neighbor.receivedAtUtc = new Date(NOW + 1).toISOString(); }, /future/);
  rejectSelection((_f, target) => { target.response.flashProcessObservation.sampledAtUtc = new Date(NOW - MAX_OBSERVATION_AGE_MS - 1).toISOString(); }, /stale/);
  rejectSelection((_f, target) => { target.response.flashProcessObservation.observed = false; }, /actual process observation/);
  rejectSelection((_f, target) => { target.response.flashProcessObservation.processStartUtcTicks = "638400000000000099"; }, /observation identity/);
  rejectSelection((_f, target) => { target.response.arenaStatus.state = "completed"; }, /still be running/);
  rejectSelection((_f, _target, neighbor) => { neighbor.response.arenaStatus.state = "failed"; }, /still be running/);
  rejectSelection((_f, target) => { target.response.arenaStatus.transportPoisoned = true; }, /unpoisoned/);
  rejectSelection((_f, target) => { target.response.arenaStatus.currentRunId = null; }, /currentRunId/);
  rejectSelection((_f, target) => { target.response.arenaStatus.currentRunId = "case-fixture-r999"; }, /exact frozen case/);
  rejectSelection((_f, target) => { target.response.arenaStatus.currentCaseId = "unfrozen-case"; }, /frozen manifest/);
  rejectSelection((_f, target) => { target.response.flashProcess.processPath = path.join(os.tmpdir(), "outside.exe"); }, /strictly inside/);
  rejectSelection((_f, target) => { target.response.flashProcess.pid = target.owner.hostPid;
    target.response.flashProcessObservation.pid = target.owner.hostPid; }, /distinct PIDs/);
  rejectSelection((_f, target, neighbor) => { target.response.flashProcess.pid = neighbor.response.flashProcess.pid;
    target.response.flashProcessObservation.pid = neighbor.response.flashProcess.pid; }, /distinct PIDs/);
  rejectSelection((_f, target, neighbor) => { neighbor.owner.socketPort = target.owner.httpPort; }, /endpoints must be independent/);
  for (const changed of ["target-exit", "neighbor-exit", "host-exit", "pid-reuse", "path-changed"]) {
    const f = fixture();
    const identity = changed === "neighbor-exit" ? f.observations.get("w02").response.flashProcess
      : changed === "host-exit" ? f.processes.get(910) : f.observations.get("w01").response.flashProcess;
    if (changed.endsWith("exit")) f.processes.delete(identity.pid);
    else f.processes.set(identity.pid, { ...identity, ...(changed === "pid-reuse"
      ? { processStartUtcTicks: "638400000000000099" } : { processPath: path.join(os.tmpdir(), "changed.exe") }) });
    const gate = createInjectionGate(f.contexts, "w01", { processProbe: f.probe, now: () => NOW });
    rejects(() => gate.screen(f.observations), /process identity mismatch/);
    assert.strictEqual(gate.claimed, false);
  }
  const f = fixture();
  let clock = NOW;
  const staleGate = createInjectionGate(f.contexts, "w01", { now: () => clock,
    processProbe: (pid) => { clock += MAX_OBSERVATION_AGE_MS; return f.probe(pid); } });
  staleGate.screen(f.observations);
  rejects(() => staleGate.claim(f.observations), /stale/);
  const gate = createInjectionGate(f.contexts, "w01", { processProbe: f.probe, now: () => NOW });
  rejects(() => gate.claim(f.observations), /screening must complete/);
  gate.screen(f.observations);
  const claim = gate.claim(f.observations); // Pure authorization fixture; no termination function is invoked.
  assert.strictEqual(claim.target.tuple.repeatIndex, 1);
  assert.strictEqual(claim.tupleSource, "host_current_ids_plus_frozen_manifest");
  rejects(() => gate.claim(f.observations), /already claimed/);
  const refreshed = fixture();
  let screenClock = NOW; let processQueries = 0;
  const refreshGate = createInjectionGate(refreshed.contexts, "w01", { now: () => screenClock,
    processProbe: (pid) => { screenClock += 50; processQueries++; return refreshed.probe(pid); } });
  refreshGate.screen(refreshed.observations);
  rejects(() => refreshGate.claim(refreshed.observations), /must follow process screening/);
  for (const sample of refreshed.observations.values()) {
    sample.receivedAtUtc = new Date(screenClock).toISOString();
    sample.response.flashProcessObservation.sampledAtUtc = sample.receivedAtUtc;
    sample.response.arenaStatus.currentRunId = "case-fixture-r002";
  }
  const refreshedClaim = refreshGate.claim(refreshed.observations);
  assert.strictEqual(refreshedClaim.target.tuple.repeatIndex, 2, "only the final pre-claim status chooses the tuple");
  assert.strictEqual(processQueries, 4, "the fresh tuple-to-claim interval cannot contain more process probes");
  rejects(() => refreshGate.claim(refreshed.observations), /already claimed/);
  for (const change of ["pid", "start", "path", "port"]) {
    const shifted = fixture();
    const shiftGate = createInjectionGate(shifted.contexts, "w01", { now: () => NOW, processProbe: shifted.probe });
    shiftGate.screen(shifted.observations);
    const target = shifted.observations.get("w01");
    if (change === "port") target.owner.httpPort = 34000;
    else {
      const flash = target.response.flashProcess;
      if (change === "pid") flash.pid = 951;
      if (change === "start") flash.processStartUtcTicks = "638400000000000099";
      if (change === "path") flash.processPath = path.join(shifted.contexts[0].job.launch.projectRoot, "changed-Flash.exe");
      Object.assign(target.response.flashProcessObservation, flash);
    }
    rejects(() => shiftGate.claim(shifted.observations), /changed after fault screening/);
    assert.strictEqual(shiftGate.claimed, false);
  }
  rejects(() => verifyProbeOutcome({}, null, [], {}), /no exact successful fault/);
  rejects(() => verifyProbeOutcome({}, { before: claim, hostReceipt: null }, [], {}), /atomic fault receipt/);
  const faultId = "fault-fixture";
  const startedAtUtc = new Date(NOW).toISOString();
  const hostReceipt = { schema: "arena-worker.fault-receipt.v1", faultId, ...claim.target.tuple,
    flashProcess: claim.target.flash, socketGeneration: 2, claimedAtUtc: new Date(NOW + 1).toISOString(),
    killIssuedAtUtc: new Date(NOW + 2).toISOString(), killReturnedAtUtc: new Date(NOW + 3).toISOString(),
    exitObservedAtUtc: new Date(NOW + 4).toISOString(), outcome: "killed", killAttempted: true,
    killIssued: true, processExitObserved: true };
  assert.strictEqual(validateAtomicFaultReceipt(hostReceipt, claim, faultId, startedAtUtc), hostReceipt);
  for (const field of Object.keys(claim.target.tuple)) {
    const changed = { ...hostReceipt, [field]: field === "repeatIndex" ? 2 : "foreign" };
    rejects(() => validateAtomicFaultReceipt(changed, claim, faultId, startedAtUtc), /run tuple mismatch/);
  }
  for (const mutation of [{ faultId: "foreign" }, { socketGeneration: 0 }, { outcome: "unknown" },
    { killAttempted: false }, { processExitObserved: false }, { killIssued: null },
    { claimedAtUtc: new Date(NOW - 1).toISOString() }, { exitObservedAtUtc: new Date(NOW).toISOString() },
    { flashProcess: { ...claim.target.flash, processStartUtcTicks: "638400000000000099" } }]) {
    rejects(() => validateAtomicFaultReceipt({ ...hostReceipt, ...mutation }, claim, faultId, startedAtUtc), /fault|claim/);
  }
  const acceptedCalls = [];
  const accepted = await requestAtomicFault({ async call(action, fields) {
    acceptedCalls.push({ action, fields }); return { faultReceipt: clone(hostReceipt) };
  } }, claim, faultId, startedAtUtc);
  assert.strictEqual(accepted.error, null);
  assert.deepStrictEqual(acceptedCalls, [{ action: "faultStopFlash", fields: { ...claim.target.tuple, faultId } }]);
  for (const observedReceipt of [hostReceipt, null, { ...hostReceipt, runId: "case-fixture-r002", repeatIndex: 2 }]) {
    const calls = [];
    const reconciled = await requestAtomicFault({ async call(action, fields) {
      calls.push({ action, fields });
      if (action === "faultStopFlash") throw new Error("control timeout; delivery outcome is unknown");
      return { faultReceipt: observedReceipt };
    } }, claim, faultId, startedAtUtc);
    assert.deepStrictEqual(calls.map((entry) => entry.action), ["faultStopFlash", "status"]);
    assert.deepStrictEqual(calls[0].fields, { ...claim.target.tuple, faultId }, "the preselected tuple must never be rebound");
    assert.strictEqual(reconciled.delivery, "unknown");
    assert(reconciled.deliveryError.includes("delivery outcome is unknown"));
    assert.strictEqual(reconciled.error === null, observedReceipt === hostReceipt);
  }
  const rejectedCalls = [];
  const rejected = await requestAtomicFault({ async call(action, fields) {
    rejectedCalls.push({ action, fields });
    const error = new Error("stale tuple rejected before claim"); error.response = { faultReceipt: null }; throw error;
  } }, claim, faultId, startedAtUtc);
  assert.strictEqual(rejected.delivery, "rejected");
  assert(rejected.error);
  assert.deepStrictEqual(rejectedCalls.map((entry) => entry.action), ["faultStopFlash"]);
  const targetReceipt = { status: "failed", terminalStatus: "failed", faultReceipt: hostReceipt,
    finalArenaStatus: { transportPoisoned: true } };
  const targetRow = { ...claim.target.tuple, status: "bridge_lost", completedAt: new Date(NOW + 5).toISOString() };
  assert.strictEqual(verifyBoundFaultRun(targetReceipt, [targetRow], claim.target, true, hostReceipt), targetRow);
  rejects(() => verifyBoundFaultRun(targetReceipt, [{ ...targetRow, status: "finished", completedAt: new Date(NOW - 1).toISOString() },
    { ...targetRow, runId: "case-fixture-r002", repeatIndex: 2 }], claim.target, true, hostReceipt), /bound in-flight/);
  rejects(() => verifyBoundFaultRun(targetReceipt, [{ ...targetRow, runId: "case-fixture-r002", repeatIndex: 2 }],
    claim.target, true, hostReceipt), /run tuple mismatch/);
  const neighborReceipt = { status: "completed", terminalStatus: "completed", completedAt: new Date(NOW + 20).toISOString() };
  const neighborRow = { ...claim.neighbor.tuple, status: "finished", completedAt: new Date(NOW + 10).toISOString() };
  assert.strictEqual(verifyBoundFaultRun(neighborReceipt, [neighborRow], claim.neighbor, false, hostReceipt), neighborRow);
  rejects(() => verifyBoundFaultRun(neighborReceipt, [{ ...neighborRow, completedAt: new Date(NOW - 1).toISOString() },
    { ...neighborRow, runId: "case-fixture-r002", repeatIndex: 2 }], claim.neighbor, false, hostReceipt), /observed run after/);
  console.log(JSON.stringify({ ok: true, evidenceKind: "isolated_fixture", rejectionChecks: assertions,
    exactAtomicFaultReceipt: true, unknownDeliveryNeverResubmitted: true, staleTupleNeverRebound: true,
    neighborSelectedRunAfterKillRequired: true, actualProcessQueries: 0, actualTerminations: 0, liveIsolationVerified: false }));
}

main().catch((error) => { console.error(error.stack || error.message); process.exitCode = 1; });
