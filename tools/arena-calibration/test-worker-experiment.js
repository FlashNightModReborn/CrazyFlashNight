#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { createPilotManifest, normalizeResultRow, sha256OfValue } = require("./lib/arena-calibration-core");
const { sha256Bytes, writeImmutableJson } = require("./lib/immutable-evidence");
const { readJson } = require("./lib/arena-worker-client");
const { captureResourceClosure, workerAttemptDirectory } = require("./run-worker-shard");
const { executeExperiment, prepareExperiment, readExperimentPlan, runExperiment } = require("./run-worker-experiment");

function write(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof value === "string" ? value : JSON.stringify(value));
}

function validSeed() {
  const player = Array(14).fill(0); player[0] = "fixture"; player[3] = 30;
  return { version: "3.0", lastSaved: "2026-10-11 10:00:00", "0": player, "1": Array(28).fill(null),
    "4": [[], []], "5": [], "7": Array(5).fill(null), inventory: {}, collection: {}, infrastructure: {},
    tasks: { tasks_to_do: [], tasks_finished: {}, task_chains_progress: {} },
    pets: { "宠物信息": Array(5).fill(null), "宠物领养限制": 0 }, shop: { "商城已购买物品": [], "商城购物车": [] } };
}

function fixture(temp, name) {
  const root = path.join(temp, name);
  const sourceRoot = path.join(root, "coordinator");
  fs.mkdirSync(sourceRoot, { recursive: true });
  const seedPath = path.join(root, "player", "saves", "original.json");
  write(seedPath, validSeed());
  const appData = path.join(root, "appdata");
  const workers = ["w01", "w02"].map((workerId) => {
    const projectRoot = path.join(root, workerId, "resources");
    fs.mkdirSync(projectRoot, { recursive: true });
    const init = childProcess.spawnSync("git", ["init", "--quiet", projectRoot], { encoding: "utf8", windowsHide: true });
    assert.strictEqual(init.status, 0, init.stderr);
    write(path.join(projectRoot, "CRAZYFLASHER7MercenaryEmpire.swf"), "fixture main");
    write(path.join(projectRoot, "scripts", "asLoader.swf"), "fixture loader");
    write(path.join(projectRoot, "data", "units.xml"), "<units />");
    return { workerId, projectRoot, candidateRoot: path.join(projectRoot, "tmp", "runtime-candidates", "v2", "fixture"), seedPath };
  });
  const manifestPath = path.join(root, "manifest.json");
  write(manifestPath, createPilotManifest({ batchId: "experiment-fixture", repeat: 1 }));
  const plan = { schema: "arena-worker.experiment-plan.v1", experimentId: name,
    workers, sharedObjectsRoot: path.join(appData, "Macromedia", "Flash Player", "#SharedObjects"),
    saveRoots: [path.dirname(seedPath), ...workers.map((entry) => path.join(entry.projectRoot, "saves"))],
    groups: [{ groupId: "parallel", mode: "parallel", visibility: "unknown", jobs: [
      { workerId: "w01", manifestPath }, { workerId: "w02", manifestPath }] },
    { groupId: "later", mode: "serial", jobs: [{ workerId: "w01", manifestPath }] }], comparisons: [] };
  const dependencies = { fixture: true, projectRoot: sourceRoot, appData,
    resolveRuntime: (_projectRoot, candidateRoot) => ({ runtimeMode: "isolated_candidate",
      processPath: path.join(candidateRoot, "runtime", "Core.exe"), coreSha256: "A".repeat(64),
      buildIdentity: "B".repeat(64), payloadClosure: "C".repeat(64) }) };
  return { root, sourceRoot, seedPath, plan, dependencies };
}

async function fakeReceipt(options, runtime, ordinal) {
  const started = options.fixtureStartedAt === undefined ? Date.now() : options.fixtureStartedAt;
  const launch = JSON.parse(fs.readFileSync(options.launchPath, "utf8"));
  const manifestBytes = fs.readFileSync(options.manifestPath);
  const manifest = JSON.parse(manifestBytes);
  const tuple = { workerId: launch.workerId, sessionEpoch: launch.sessionEpoch,
    assignmentId: options.assignmentId, attemptId: options.attemptId };
  const output = workerAttemptDirectory(launch, tuple);
  const manifestPath = path.join(output, "manifest.json");
  const resultPath = path.join(output, "results.jsonl");
  write(manifestPath, manifestBytes.toString("utf8"));
  const row = normalizeResultRow({ ...tuple, schema: "arena-calibration.result.v1",
    batchId: manifest.batchId, manifestHash: manifest.manifestHash, caseId: manifest.cases[0].caseId,
    caseHash: manifest.cases[0].caseHash, runId: `${tuple.attemptId}-r1`, repeatIndex: 1,
    status: "finished", winner: "blue", frames: 60, durationMs: 2000 });
  write(resultPath, JSON.stringify(row) + "\n");
  await new Promise((resolve) => setTimeout(resolve, 5));
  const completed = Date.now();
  const iso = (millis) => new Date(millis).toISOString();
  const protection = { unchanged: true, before: { files: [], snapshotHash: sha256OfValue([]) },
    after: { files: [], snapshotHash: sha256OfValue([]) } };
  const resourceClosure = captureResourceClosure(launch.projectRoot);
  const receipt = { schema: "arena-worker.shard-receipt.v1", executionMode: "arena_worker", evidenceKind: "isolated_fixture",
    ...tuple, batchId: manifest.batchId, manifestHash: manifest.manifestHash, expectedRunCount: 1,
    experiment: options.experiment, startedAt: iso(started), batchStartedAt: iso(started), completedAt: iso(completed), finalizedAt: iso(completed),
    wallDurationMs: completed - started, terminalStatus: "completed", status: "completed", errors: [],
    shutdown: { requested: true, hostExited: true, flashExited: true }, flashProcessObserved: true, runtimeUnchanged: true,
    saveProtection: protection, resourcesUnchanged: true, resourceClosure, resourceClosureAfterHash: resourceClosure.closureHash,
    runtimeIdentity: { ...runtime, verified: true }, manifestSnapshotPath: manifestPath, manifestSha256: sha256Bytes(manifestBytes),
    resultPath, resultSha256: sha256Bytes(fs.readFileSync(resultPath)), ownerSnapshot: { ...launch,
      hostPid: 1000 + ordinal, httpPort: 32000 + ordinal * 2, socketPort: 32001 + ordinal * 2 } };
  const receiptPath = path.join(output, "shard-receipt.json");
  writeImmutableJson(receiptPath, receipt);
  return { receipt, receiptPath };
}

async function main() {
  const help = childProcess.spawnSync(process.execPath, [path.join(__dirname, "run-worker-experiment.js"), "--help"],
    { encoding: "utf8", windowsHide: true });
  assert.strictEqual(help.status, 0, help.stderr);
  assert(help.stdout.includes("arena-worker.experiment-plan.v1"));
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-worker-experiment-"));
  try {
    const invalid = fixture(temp, "invalid-plan");
    invalid.plan.groups[0].jobs[1].workerId = "w01";
    assert.throws(() => prepareExperiment(invalid.plan, invalid.dependencies), /cannot share a Worker/);
    assert.strictEqual(fs.existsSync(path.join(invalid.sourceRoot, "tmp", "arena-worker-experiments", "invalid-plan")), false);

    const good = fixture(temp, "complete-plan");
    const largeResources = Array.from({ length: 11691 }, (_unused, index) =>
      `flashswf/人物单位/双实例输入/representative-resource-${String(index).padStart(5, "0")}.swf`);
    const largePlan = { ...good.plan, experimentId: "large-resource-plan",
      workers: good.plan.workers.map((worker) => ({ ...worker, resourcePaths: largeResources })) };
    const largePath = path.join(temp, "large-resource-plan.json");
    write(largePath, largePlan);
    const largeBytes = fs.readFileSync(largePath);
    assert(largeBytes.length > 1024 * 1024 && largeBytes.length < 8 * 1024 * 1024,
      "fixture must exercise a real two-Worker plan larger than the descriptor limit");
    const readLargePlan = readExperimentPlan(largePath);
    assert.deepStrictEqual(readLargePlan, largePlan, "all 11691 resource paths per Worker must survive plan loading");
    assert.throws(() => readJson(largePath), /invalid Worker descriptor file/,
      "ordinary owner/credential descriptor loading must retain its original 1 MiB cap");
    const oversizedPath = path.join(temp, "oversized-resource-plan.json");
    fs.writeFileSync(oversizedPath, Buffer.concat([largeBytes,
      Buffer.alloc(8 * 1024 * 1024 + 1 - largeBytes.length, 0x20)]));
    assert.throws(() => readExperimentPlan(oversizedPath), /invalid Worker descriptor file/,
      "the dedicated plan cap must still reject valid JSON larger than 8 MiB");
    const originalSeed = fs.readFileSync(good.seedPath);
    const frozen = prepareExperiment(good.plan, good.dependencies);
    const jobs = frozen.groups.flatMap((group) => group.jobs);
    assert.strictEqual(new Set(jobs.map((job) => job.launch.slot)).size, jobs.length);
    assert.strictEqual(new Set(jobs.map((job) => job.sessionEpoch)).size, jobs.length);
    for (const job of jobs) {
      assert.deepStrictEqual(fs.readFileSync(job.seedTargetPath), originalSeed);
      assert.strictEqual(fs.existsSync(job.expectedReceiptPath), false);
      assert.strictEqual(sha256Bytes(fs.readFileSync(job.launchPath)), job.launchSha256);
      assert.deepStrictEqual(job.launch.performance, { preset: "performance", mode: "fixed", maxRenderHeight: 180 });
      assert.strictEqual(job.launch.allowFaultInjection, false);
    }
    assert(fs.existsSync(path.join(frozen.experimentRoot, "expected-receipts.json")));
    assert(fs.existsSync(path.join(frozen.experimentRoot, "measurement-plan.json")));
    for (const group of frozen.groups) {
      assert.strictEqual(frozen.measurementPlan.groups.find((entry) => entry.groupId === group.groupId).groupReportPath, group.groupReportPath);
      assert.strictEqual(fs.existsSync(group.groupReportPath), false, "group report location is frozen before execution");
    }
    let active = 0; let maximum = 0; let ordinal = 0;
    const complete = await executeExperiment(frozen, { ...good.dependencies, runShard: async (options) => {
      assert.deepStrictEqual(options.expectedLaunch, JSON.parse(fs.readFileSync(options.launchPath)));
      assert.strictEqual(options.expectedLaunchSha256, sha256Bytes(fs.readFileSync(options.launchPath)));
      const current = ++ordinal;
      const fixtureStartedAt = Date.now();
      active++; maximum = Math.max(maximum, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      try { return fakeReceipt({ ...options, fixtureStartedAt }, good.dependencies.resolveRuntime(null, options.candidateRoot), current); }
      finally { active--; }
    } });
    assert.strictEqual(maximum, 2);
    assert.strictEqual(active, 0);
    assert.strictEqual(complete.report.status, "completed", JSON.stringify(complete.report));
    for (const group of complete.report.groups) {
      assert.strictEqual(group.wallDurationMs, Date.parse(group.completedAt) - Date.parse(group.startedAt));
      for (const outcome of group.outcomes) {
        const receipt = JSON.parse(fs.readFileSync(outcome.expectedReceiptPath));
        assert(Date.parse(group.startedAt) <= Date.parse(receipt.startedAt));
        assert(Date.parse(group.completedAt) >= Date.parse(receipt.finalizedAt));
      }
    }
    const completeMeasurement = JSON.parse(fs.readFileSync(complete.report.measurementPath));
    assert(completeMeasurement.groups.every((group) => group.wallDenominatorScope === "coordinator_group"));
    assert.deepStrictEqual(fs.readFileSync(good.seedPath), originalSeed);
    assert.throws(() => prepareExperiment(good.plan, good.dependencies), /EEXIST/);
    await assert.rejects(() => executeExperiment(frozen, good.dependencies), /terminal report/);

    const faultOnly = fixture(temp, "fault-policy-plan");
    faultOnly.plan.groups = faultOnly.plan.groups.slice(0, 1);
    faultOnly.plan.faultIntent = { action: "host_atomic_fault_stop_flash_once", faultWorkerId: "w01", faultId: "fault-fixture",
      maximumAttempts: 1, speedQualification: false };
    const faultFrozen = prepareExperiment(faultOnly.plan, faultOnly.dependencies);
    assert.strictEqual(faultFrozen.faultIntent.faultId, "fault-fixture");
    assert.deepStrictEqual(faultFrozen.groups[0].jobs.map((job) => [job.workerId, job.launch.allowFaultInjection]),
      [["w01", true], ["w02", false]]);
    assert.throws(() => prepareExperiment({ ...faultOnly.plan, faultIntent: { ...faultOnly.plan.faultIntent, maximumAttempts: 2 } },
      faultOnly.dependencies), /one-shot isolation plan/);

    const missing = fixture(temp, "missing-receipt");
    let finished = 0; let started = 0;
    const absent = await runExperiment(missing.plan, { ...missing.dependencies, runShard: async (options) => {
      const current = ++started;
      await new Promise((resolve) => setTimeout(resolve, current === 1 ? 2 : 7));
      finished++;
      if (current === 1) throw new Error("fixture interrupted before durable receipt");
      return fakeReceipt(options, missing.dependencies.resolveRuntime(null, options.candidateRoot), current);
    } });
    assert.strictEqual(started, 2, "a missing receipt must stop the later group");
    assert.strictEqual(finished, 2, "both in-flight jobs must finish their cleanup boundary before the global snapshot");
    assert.strictEqual(absent.report.stopped, true);
    assert.strictEqual(absent.report.qualified, false);
    assert.strictEqual(absent.report.completedGroups, 1);
    const absentMeasurement = JSON.parse(fs.readFileSync(absent.report.measurementPath));
    assert.strictEqual(absentMeasurement.groups[0].expectedReceipts, 2);
    assert.strictEqual(absentMeasurement.groups[0].observedReceipts, 1);
    assert(absentMeasurement.groups[0].rejectedAttempts.length > 0);

    const changed = fixture(temp, "seed-changed");
    let calls = 0;
    const mutation = await runExperiment(changed.plan, { ...changed.dependencies, runShard: async (options) => {
      const current = ++calls;
      const receipt = fakeReceipt(options, changed.dependencies.resolveRuntime(null, options.candidateRoot), current);
      if (current === 1) write(changed.seedPath, "changed source bytes retained");
      return receipt;
    } });
    assert.strictEqual(calls, 2);
    assert.strictEqual(mutation.report.stopped, true);
    assert.strictEqual(mutation.report.groups[0].seedSourcesUnchanged, false);
    assert.strictEqual(fs.readFileSync(changed.seedPath, "utf8"), "changed source bytes retained", "coordinator must never restore over a changed source");

    const drift = fixture(temp, "launch-drift");
    drift.plan.groups[0].performance = { preset: "performance", mode: "fixed", maxRenderHeight: 540 };
    const driftFrozen = prepareExperiment(drift.plan, drift.dependencies);
    const driftJob = driftFrozen.groups[0].jobs[0];
    assert.deepStrictEqual(driftJob.launch.performance, drift.plan.groups[0].performance);
    write(driftJob.launchPath, { ...driftJob.launch, slot: "cf7_agent_wrong_slot" });
    let driftCalls = 0;
    const driftResult = await executeExperiment(driftFrozen, { ...drift.dependencies, runShard: async (options) => {
      driftCalls++;
      return fakeReceipt(options, drift.dependencies.resolveRuntime(null, options.candidateRoot), 2);
    } });
    assert.strictEqual(driftCalls, 1, "the changed launch must be rejected before spawning; the already scheduled other Worker still settles");
    assert.strictEqual(driftResult.report.stopped, true);
    assert(driftResult.report.groups[0].outcomes[0].error.includes("frozen launch bytes changed"));
    const invalidPerformance = fixture(temp, "invalid-performance");
    invalidPerformance.plan.groups[0].performance = { preset: "performance", mode: "fixed", maxRenderHeight: 541 };
    assert.throws(() => prepareExperiment(invalidPerformance.plan, invalidPerformance.dependencies), /performance policy value/);
    const projected = fixture(temp, "v2-projection-frozen");
    projected.plan.groups[0].projection = {
      presentationPolicy: "full", projectionConsumers: { playerHud: "none", ordinaryBullet: "none", ray: "none", chain: "none",
        combatDecoration: "none", sceneLighting: "full", equipmentLighting: "full" },
      controlFrameFormat: "f-visual-v1", visualSeedRevision: "visual-event-v1",
      simulationRngConsumptionRevision: "legacy-global-consume-v1", sessionVisualSeed: 104729 };
    const projectedFrozen = prepareExperiment(projected.plan, projected.dependencies);
    assert.strictEqual(projectedFrozen.groups[0].jobs[0].launch.schema, "arena-worker.launch.v2");
    assert.deepStrictEqual(projectedFrozen.groups[0].jobs[0].launch.projectionConsumers, projected.plan.groups[0].projection.projectionConsumers);
    assert.strictEqual(projectedFrozen.groups[1].jobs[0].launch.schema, "arena-worker.launch.v1");

    const beforeGroup = fixture(temp, "source-changed-before-group");
    const beforeFrozen = prepareExperiment(beforeGroup.plan, beforeGroup.dependencies);
    write(beforeGroup.seedPath, "changed source before any attempt starts");
    let prematureStarts = 0;
    const rejectedBeforeGroup = await executeExperiment(beforeFrozen, { ...beforeGroup.dependencies,
      runShard: async () => { prematureStarts++; throw new Error("must not start"); } });
    assert.strictEqual(prematureStarts, 0);
    assert.strictEqual(rejectedBeforeGroup.report.groups[0].outcomes.length, 0);
    const beforeReport = JSON.parse(fs.readFileSync(beforeFrozen.groups[0].groupReportPath));
    assert.strictEqual(beforeReport.wallDurationMs, Date.parse(beforeReport.completedAt) - Date.parse(beforeReport.startedAt));
    assert(beforeFrozen.groups.every((group) => group.jobs.every((job) => !fs.existsSync(job.expectedReceiptPath))), "unstarted jobs must not receive fake receipts");

    const snapshotFault = fixture(temp, "global-snapshot-fault");
    const extraProtectedRoot = path.join(snapshotFault.root, "extra-protected-saves");
    snapshotFault.plan.saveRoots.push(extraProtectedRoot);
    const snapshotFrozen = prepareExperiment(snapshotFault.plan, snapshotFault.dependencies);
    write(extraProtectedRoot, "a protected directory became a file before the group");
    const rejectedSnapshot = await executeExperiment(snapshotFrozen, { ...snapshotFault.dependencies,
      runShard: async () => { prematureStarts++; throw new Error("must not start"); } });
    assert.strictEqual(prematureStarts, 0);
    assert.strictEqual(rejectedSnapshot.report.stopped, true);
    assert(rejectedSnapshot.report.errors.some((entry) => entry.phase === "coordinator"));
    const snapshotReport = JSON.parse(fs.readFileSync(snapshotFrozen.groups[0].groupReportPath));
    assert.strictEqual(snapshotReport.outcomes.length, 0);
    assert.strictEqual(snapshotReport.globalSaveUnchanged, false);
    assert.strictEqual(snapshotReport.wallDurationMs, Date.parse(snapshotReport.completedAt) - Date.parse(snapshotReport.startedAt));
    assert(snapshotFrozen.groups.every((group) => group.jobs.every((job) => !fs.existsSync(job.expectedReceiptPath))));
    console.log(JSON.stringify({ ok: true, evidenceKind: "isolated_fixture", frozenReceiptSet: true,
      exactFreshSlots: true, parallelAllSettled: true, missingReceiptStopsLaterGroups: true,
      seedSourceMutationPreserved: true, experimentReplayRejected: true }));
  } finally {
    assert(path.resolve(temp).startsWith(`${path.resolve(os.tmpdir())}${path.sep}cf7-worker-experiment-`));
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

main().catch((error) => { console.error(error.stack); process.exitCode = 1; });
