#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { createFixtureRows, normalizeManifest, sha256OfValue } = require("./lib/arena-calibration-core");
const { sha256Bytes } = require("./lib/immutable-evidence");
const { measurePlan: measureLivePlan, peakConcurrency, summarizeProcessObservations,
  summarizeWindowObservations, summarizePerformanceObservations } = require("./measure-worker-p0");
const measurePlan = (plan, directory) => measureLivePlan(plan, directory, { allowFixtureEvidence: true });

const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), "arena-p0-metrics-"));
let count = 0;
const baseTime = Date.parse("2026-10-11T01:00:00.000Z");
const iso = (offset) => new Date(baseTime + offset).toISOString();
const hash = (label) => sha256OfValue(label);

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
  return sha256Bytes(fs.readFileSync(filePath));
}

function protection() {
  return { unchanged: true,
    before: { files: [], snapshotHash: sha256OfValue([]) },
    after: { files: [], snapshotHash: sha256OfValue([]) } };
}

function fixture(name, groupId, workerId, start, options = {}) {
  const directory = path.join(testRoot, name);
  fs.mkdirSync(directory, { recursive: true });
  const manifest = normalizeManifest({
    batchId: name, createdAt: iso(0), buildCommit: "fixture", repeat: 1,
    cases: [{ caseId: "frozen-case", blueRoster: [{ type: "兵种44", level: 30 }],
      redRoster: [{ type: "兵种11", level: options.level || 30 }], timeoutFrames: 1500, plannerReason: "P0 metrics fixture" }],
  });
  const testCase = manifest.cases[0];
  const manifestPath = path.join(directory, "manifest.json");
  const resultPath = path.join(directory, "results.jsonl");
  const receiptPath = path.join(directory, "receipt.json");
  const row = { ...createFixtureRows()[0],
    workerId, sessionEpoch: `epoch-${name}`, assignmentId: `assignment-${name}`, attemptId: `attempt-${name}`,
    batchId: name, manifestHash: manifest.manifestHash, caseId: testCase.caseId, caseHash: testCase.caseHash,
    runId: "frozen-case-r1", repeatIndex: 1, status: options.status || "finished",
    winner: options.status === "timeout" ? "timeout" : "blue", frames: 300, durationMs: 10000,
    startedAt: iso(start + 10000), completedAt: iso(start + 35000), errors: [],
  };
  const resourceFiles = [{ path: "CRAZYFLASHER7MercenaryEmpire.swf", size: 100, sha256: hash("main-swf") },
    { path: "scripts/asLoader.swf", size: 20, sha256: hash("asLoader-swf") }];
  const workerRoot = path.join(testRoot, "runtime-roots", workerId);
  const owner = { hostPid: workerId === "w1" ? 11 : 22,
    projectRoot: workerRoot, stateRoot: path.join(workerRoot, "tmp", name),
    saveRoot: path.join(workerRoot, "saves"), outputRoot: path.join(workerRoot, "tmp", "arena-calibration"),
    swfOrigin: path.join(workerRoot, "CRAZYFLASHER7MercenaryEmpire.swf"),
    httpPort: workerId === "w1" ? 15001 : 15003, socketPort: workerId === "w1" ? 15002 : 15004 };
  fs.writeFileSync(resultPath, `${JSON.stringify(row)}\n`);
  const receipt = {
    schema: "arena-worker.shard-receipt.v1", executionMode: "arena_worker", evidenceKind: "isolated_fixture",
    workerId, sessionEpoch: row.sessionEpoch, assignmentId: row.assignmentId, attemptId: row.attemptId,
    batchId: name, manifestHash: manifest.manifestHash, expectedRunCount: 1,
    startedAt: iso(start), hostStartedAt: iso(start + 1000), gameReadyAt: iso(start + 9000),
    batchStartedAt: iso(start + 10000), completedAt: iso(start + 35000), finalizedAt: iso(start + 40000),
    wallDurationMs: 40000, terminalStatus: "completed", status: "completed", errors: [], ownerSnapshot: owner,
    flashProcessObserved: true, runtimeUnchanged: true,
    shutdown: { requested: true, hostExited: true, flashExited: true },
    experiment: { groupId, condition: "fixture", concurrency: groupId === "parallel" ? 2 : 1,
      sessionState: "cold", visibility: "background-visible" },
    manifestSnapshotPath: manifestPath, manifestSha256: writeJson(manifestPath, manifest),
    resultPath, resultSha256: sha256Bytes(fs.readFileSync(resultPath)), saveProtection: protection(),
    runtimeIdentity: { verified: true, runtimeMode: "isolated_candidate", processPath: "C:/fixture/Core.exe",
      coreSha256: hash("core"), buildIdentity: hash(options.runtime || "build"), payloadClosure: hash("payload") },
    resourcesUnchanged: true, resourceClosureAfterHash: sha256OfValue(resourceFiles),
    resourceClosure: { scope: "observed_runtime_resources", closureHash: sha256OfValue(resourceFiles), files: resourceFiles,
      completeResourceClosure: false },
  };
  writeJson(receiptPath, receipt);
  return { manifest, row, receipt, receiptPath, resultPath, manifestPath };
}

let serial = 0;
function scenario(options = {}) {
  const prefix = `s${serial++}`;
  const entries = [
    fixture(`${prefix}-a`, "serial", "w1", 0),
    fixture(`${prefix}-b`, "serial", "w1", 40000),
    fixture(`${prefix}-c`, "parallel", "w1", 100000, options),
    fixture(`${prefix}-d`, "parallel", "w2", 100000, options),
  ];
  const protectionPath = path.join(testRoot, `${prefix}-global-save.json`);
  writeJson(protectionPath, protection());
  const plan = { schema: "arena-worker.p0-plan.v1", groups: [
    { groupId: "serial", expectedConcurrency: 1, receiptPaths: entries.slice(0, 2).map((item) => item.receiptPath) },
    { groupId: "parallel", expectedConcurrency: 2, receiptPaths: entries.slice(2).map((item) => item.receiptPath),
      saveProtectionPath: protectionPath },
  ], comparisons: [{ baseline: "serial", candidate: "parallel" }] };
  return { entries, plan, protectionPath };
}

function persist(entry, rewriteRaw = false) {
  if (rewriteRaw) {
    fs.writeFileSync(entry.resultPath, `${JSON.stringify(entry.row)}\n`);
    entry.receipt.resultSha256 = sha256Bytes(fs.readFileSync(entry.resultPath));
  }
  writeJson(entry.receiptPath, entry.receipt);
}

function addGroupTiming(s, index, started, completed) {
  const group = s.plan.groups[index];
  const file = path.join(testRoot, `group-${serial}-${index}.json`);
  const report = { groupId: group.groupId, startedAt: iso(started), completedAt: iso(completed),
    wallDurationMs: completed - started, seedSourcesUnchanged: true, globalSaveUnchanged: true, stopBeforeNextGroup: false,
    outcomes: group.receiptPaths.map((expectedReceiptPath) => ({ expectedReceiptPath,
      receiptSha256: sha256Bytes(fs.readFileSync(expectedReceiptPath)) })) };
  group.groupReportPath = file; writeJson(file, report);
  return { file, report };
}

function check(label, fn) {
  fn(); count++; console.log(`[PASS] ${label}`);
}

try {
  check("lifecycle denominator includes serial startup and final shutdown", () => {
    const s = scenario();
    const result = measurePlan(s.plan, testRoot);
    assert.strictEqual(result.qualified, true, JSON.stringify(result.groups.map(({ reasons, rejectedAttempts }) => ({ reasons, rejectedAttempts }))));
    assert.strictEqual(result.evidenceLevel, "isolated_fixture");
    assert.strictEqual(result.groups[0].wallDurationMs, 80000);
    assert.strictEqual(result.groups[1].wallDurationMs, 40000);
    assert.strictEqual(result.groups[1].observedConcurrency, 2);
    assert.strictEqual(result.comparisons[0].throughputRatio, 2);
    assert.strictEqual(result.groups[1].attempts[0].cadence[0].framesPerSecond, 30);
    assert.strictEqual(result.groups[1].attempts[0].completeResourceClosure, false);
  });
  check("missing receipt cannot disappear from the speedup denominator", () => {
    const s = scenario();
    s.plan.groups[1].receiptPaths.push(path.join(testRoot, "never-written.json"));
    const result = measurePlan(s.plan, testRoot);
    assert.strictEqual(result.groups[1].wallDurationMs, null);
    assert.strictEqual(result.groups[1].rejectedAttempts.length, 1);
    assert.strictEqual(result.comparisons[0].throughputRatio, null);
  });
  check("hash mismatch preserves invalid evidence instead of counting a rewritten result", () => {
    const s = scenario();
    fs.appendFileSync(s.entries[2].resultPath, " ");
    const result = measurePlan(s.plan, testRoot);
    assert.match(result.groups[1].rejectedAttempts[0].reason, /hash mismatch/);
    assert.strictEqual(result.qualified, false);
  });
  check("partial raw set is observed but cannot qualify throughput", () => {
    const s = scenario(); const entry = s.entries[2];
    fs.writeFileSync(entry.resultPath, "");
    entry.receipt.resultSha256 = sha256Bytes(Buffer.alloc(0)); persist(entry);
    const result = measurePlan(s.plan, testRoot);
    assert.ok(result.groups[1].reasons.includes("incomplete_run_set"));
    assert.strictEqual(result.groups[1].counts.observed, 1);
    assert.strictEqual(result.groups[1].qualifiedStrengthSamplesPerHour, null);
  });
  check("natural combat timeout remains a fact and is excluded from strength samples", () => {
    const s = scenario({ status: "timeout" });
    const result = measurePlan(s.plan, testRoot);
    assert.strictEqual(result.groups[1].qualified, true);
    assert.strictEqual(result.groups[1].counts.combatTimeouts, 2);
    assert.strictEqual(result.groups[1].counts.failed, 0);
    assert.strictEqual(result.groups[1].qualifiedStrengthSamplesPerHour, 0);
    assert.strictEqual(result.comparisons[0].throughputRatio, 0);
  });
  check("successful status with error payload does not become an accepted sample", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.row.errors = [{ code: "unexpected", message: "fixture" }]; persist(entry, true);
    const result = measurePlan(s.plan, testRoot);
    assert.strictEqual(result.groups[1].counts.strengthSamples, 1);
    assert.strictEqual(result.groups[1].counts.failed, 1);
    assert.strictEqual(result.comparisons[0].throughputRatio, null);
  });
  check("another worker epoch cannot be relabeled by a matching raw file digest", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.row.sessionEpoch = "foreign-epoch"; persist(entry, true);
    assert.match(measurePlan(s.plan, testRoot).groups[1].rejectedAttempts[0].reason, /sessionEpoch mismatch/);
  });
  check("same physical attempt copied to another pathname is counted only as invalid", () => {
    const s = scenario(); const duplicate = path.join(testRoot, "duplicate-receipt.json");
    fs.copyFileSync(s.entries[2].receiptPath, duplicate);
    s.plan.groups[1].receiptPaths.push(duplicate);
    assert.ok(measurePlan(s.plan, testRoot).groups[1].reasons.includes("duplicate_physical_attempt"));
  });
  check("two sequential workers do not count as actual two-worker concurrency", () => {
    const s = scenario(); const entry = s.entries[3];
    for (const key of ["startedAt", "hostStartedAt", "gameReadyAt", "batchStartedAt", "completedAt", "finalizedAt"]) {
      entry.receipt[key] = new Date(Date.parse(entry.receipt[key]) + 40000).toISOString();
    }
    persist(entry);
    const group = measurePlan(s.plan, testRoot).groups[1];
    assert.strictEqual(group.observedConcurrency, 1);
    assert.ok(group.reasons.includes("observed_concurrency_differs_from_plan"));
  });
  check("different frozen roster invalidates the cross-group ratio", () => {
    const s = scenario({ level: 31 });
    const result = measurePlan(s.plan, testRoot);
    assert.ok(result.comparisons[0].reasons.includes("different_workload"));
    assert.strictEqual(result.comparisons[0].throughputRatio, null);
  });
  check("different candidate runtime invalidates the cross-group ratio", () => {
    const s = scenario({ runtime: "other-build" });
    assert.ok(measurePlan(s.plan, testRoot).comparisons[0].reasons.includes("different_runtime"));
  });
  check("global protected save mutation blocks a successful pair", () => {
    const s = scenario(); const changed = protection(); changed.unchanged = false;
    writeJson(s.protectionPath, changed);
    assert.ok(measurePlan(s.plan, testRoot).groups[1].reasons.includes("global_save_protection_failed"));
  });
  check("claimed unchanged snapshot must itself hash to its stored bytes", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.receipt.saveProtection.after.files.push({ key: "player", sha256: hash("new-save"), size: 1 });
    persist(entry);
    assert.ok(measurePlan(s.plan, testRoot).groups[1].reasons.includes("protected_save_unverified"));
  });
  check("unknown shutdown and changed resources both deny qualification", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.receipt.shutdown.hostExited = false;
    entry.receipt.resourcesUnchanged = false; persist(entry);
    const result = measurePlan(s.plan, testRoot);
    assert.ok(result.groups[1].reasons.includes("host_exit_unverified"));
    assert.ok(result.groups[1].reasons.includes("observed_resource_closure_unverified"));
  });
  check("a receipt cannot be reused in multiple comparison positions", () => {
    const s = scenario(); s.plan.groups[1].receiptPaths.push(s.entries[0].receiptPath);
    assert.throws(() => measurePlan(s.plan, testRoot), /more than one experiment position/);
  });
  check("wall duration cannot silently omit teardown", () => {
    const s = scenario(); const entry = s.entries[2]; entry.receipt.wallDurationMs = 25000; persist(entry);
    assert.match(measurePlan(s.plan, testRoot).groups[1].rejectedAttempts[0].reason, /final shutdown/);
  });
  check("half-open intervals do not invent concurrency at a handover", () => {
    assert.strictEqual(peakConcurrency([[0, 1000], [1000, 2000]]), 1);
    assert.strictEqual(peakConcurrency([[0, 1001], [1000, 2000]]), 2);
  });
  check("isolated fixtures cannot be promoted to live evidence by the measurement CLI", () => {
    const s = scenario(); const result = measureLivePlan(s.plan, testRoot);
    assert.strictEqual(result.qualified, false);
    assert.ok(result.groups[0].reasons.includes("live_execution_evidence_missing"));
  });
  check("completed batch cannot hide a runner failure", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.receipt.status = "failed"; entry.receipt.errors.push({ phase: "shutdown_delivery", message: "unknown" }); persist(entry);
    assert.ok(measurePlan(s.plan, testRoot).groups[1].reasons.includes("runner_reported_failure"));
  });
  check("synthetic timeout without a Flash clock is an infrastructure failure", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.row.status = "timeout"; entry.row.winner = "timeout"; entry.row.frames = null; entry.row.durationMs = null;
    persist(entry, true);
    const group = measurePlan(s.plan, testRoot).groups[1];
    assert.strictEqual(group.counts.combatTimeouts, 0);
    assert.strictEqual(group.counts.failed, 1);
    assert.strictEqual(group.qualified, false);
  });
  check("overlapping jobs cannot claim independence while sharing process or save roots", () => {
    const s = scenario(); const entry = s.entries[3];
    entry.receipt.ownerSnapshot = { ...s.entries[2].receipt.ownerSnapshot }; persist(entry);
    const reasons = measurePlan(s.plan, testRoot).groups[1].reasons;
    assert.ok(reasons.includes("overlapping_process_ownership_not_independent"));
    assert.ok(reasons.includes("overlapping_saveRoot_not_independent"));
    assert.ok(reasons.includes("overlapping_endpoints_not_independent"));
  });
  check("resource closure claim is recomputed from the recorded file set", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.receipt.resourceClosure.files[0].sha256 = hash("changed-main"); persist(entry);
    assert.ok(measurePlan(s.plan, testRoot).groups[1].reasons.includes("observed_resource_closure_unverified"));
  });
  check("an unobserved Flash or changed candidate denies lifecycle qualification", () => {
    const s = scenario(); const entry = s.entries[2];
    entry.receipt.flashProcessObserved = false; entry.receipt.runtimeUnchanged = false; persist(entry);
    const reasons = measurePlan(s.plan, testRoot).groups[1].reasons;
    assert.ok(reasons.includes("live_flash_process_unverified"));
    assert.ok(reasons.includes("candidate_runtime_changed_or_unverified"));
  });
  const processSample = (offset, overrides = {}) => ({ observed: true, sampledAtUtc: iso(offset),
    pid: 10, processStartUtcTicks: "639273060000000000", processPath: "C:/fixture/Core.exe",
    totalProcessorTimeMs: offset / 2, workingSetBytes: 100 + offset, privateMemoryBytes: 50 + offset, ...overrides });
  check("process CPU uses the sampled same-process interval and leaves child processes outside scope", () => {
    const s = scenario(); const entry = s.entries[0];
    entry.receipt.hostProcessObservations = [processSample(1000), processSample(3000)]; persist(entry);
    const resources = measurePlan(s.plan, testRoot).groups[0].attempts[0].observations.processResources;
    assert.strictEqual(resources.scope, "host_and_flash_only");
    assert.strictEqual(resources.webViewChildrenIncluded, false);
    assert.strictEqual(resources.host.streams[0].cpuInterval.cpuTimeMs, 1000);
    assert.strictEqual(resources.host.streams[0].cpuInterval.averageLogicalCores, 0.5);
    assert.strictEqual(resources.host.streams[0].sampledPeakWorkingSetBytes, 3100);
    assert.strictEqual(resources.flash.identityCount, 0);
  });
  check("missing or null process counters are unknown rather than zero CPU or RAM", () => {
    const result = summarizeProcessObservations([{ observed: false }, processSample(1000,
      { totalProcessorTimeMs: null, workingSetBytes: null, privateMemoryBytes: undefined })]);
    assert.strictEqual(result.unavailableSamples, 1);
    assert.strictEqual(result.streams[0].cpuSamples, 0);
    assert.strictEqual(result.streams[0].cpuInterval, null);
    assert.strictEqual(result.streams[0].sampledPeakWorkingSetBytes, null);
    assert.strictEqual(result.streams[0].sampledPeakPrivateMemoryBytes, null);
  });
  check("PID reuse cannot bridge CPU samples across a new process identity", () => {
    const result = summarizeProcessObservations([processSample(1000),
      processSample(3000, { processStartUtcTicks: "639273060010000000" })]);
    assert.strictEqual(result.identityCount, 2);
    assert.ok(result.streams.every((stream) => stream.cpuInterval === null));
  });
  check("regressing counters do not produce invented negative or partial CPU estimates", () => {
    const result = summarizeProcessObservations([processSample(1000),
      processSample(2000, { totalProcessorTimeMs: 100 }), processSample(3000)]);
    assert.strictEqual(result.streams[0].cpuCounterRegressed, true);
    assert.strictEqual(result.streams[0].cpuInterval, null);
  });
  check("window point samples distinguish background, foreground, hidden and minimized states", () => {
    const background = { observed: true, guardianVisible: true, flashVisible: true, guardianMinimized: false,
      flashMinimized: false, hostForeground: false, flashForeground: false };
    const result = summarizeWindowObservations([background, { ...background, flashForeground: true },
      { ...background, guardianMinimized: true }, { ...background, flashVisible: false }, { observed: false }]);
    assert.deepStrictEqual(result.counts, { backgroundVisible: 1, foreground: 1, minimized: 1, hidden: 1, unavailable: 1 });
    assert.strictEqual(result.continuousVisibilityVerified, false);
    assert.strictEqual(summarizeWindowObservations([{ observed: true }]).counts.unavailable, 1);
  });
  check("requested performance remains distinct from observed inactive or stale display state", () => {
    const request = { preset: "performance", mode: "fixed", maxRenderHeight: 540 };
    const sample = { observed: true, preset: "balanced", mode: "auto", status: "inactive", width: 1920,
      height: 1080, quality: "HIGH", effectLevel: 0, reason: "background" };
    const result = summarizePerformanceObservations([sample, sample, { observed: false, width: 0, height: 0 }], request);
    assert.deepStrictEqual(result.requested, request);
    assert.strictEqual(result.states[0].preset, "balanced");
    assert.strictEqual(result.states[0].status, "inactive");
    assert.strictEqual(result.states[0].height, 1080);
    assert.strictEqual(result.states[0].samples, 2);
    assert.strictEqual(result.unavailableSamples, 1);
  });
  check("coordinator denominator includes group preparation and global protection after all recycling", () => {
    const s = scenario(); addGroupTiming(s, 0, -3000, 84000); addGroupTiming(s, 1, 97000, 144000);
    const result = measurePlan(s.plan, testRoot);
    assert.strictEqual(result.qualified, true);
    assert.strictEqual(result.groups[0].wallDenominatorScope, "coordinator_group");
    assert.strictEqual(result.groups[0].receiptEnvelopeWallDurationMs, 80000);
    assert.strictEqual(result.groups[0].wallDurationMs, 87000);
    assert.strictEqual(result.groups[1].wallDurationMs, 47000);
    assert.ok(Math.abs(result.comparisons[0].throughputRatio - 87000 / 47000) < 1e-12);
  });
  check("coordinator timing cannot omit a known startup or shutdown interval", () => {
    const s = scenario(); addGroupTiming(s, 1, 101000, 139000);
    const group = measurePlan(s.plan, testRoot).groups[1];
    assert.strictEqual(group.qualified, false);
    assert.strictEqual(group.wallDurationMs, null);
    assert.ok(group.reasons.some((reason) => /omits an attempt lifecycle/.test(reason)));
  });
  check("coordinator timing must bind the same receipt bytes used by the measurement", () => {
    const s = scenario(); const g = addGroupTiming(s, 1, 97000, 144000);
    g.report.outcomes[0].receiptSha256 = hash("replacement"); writeJson(g.file, g.report);
    assert.ok(measurePlan(s.plan, testRoot).groups[1].reasons.some((reason) => /coordinator receipt hash mismatch/.test(reason)));
  });
  check("coordinator timing cannot silently drop a failed planned attempt", () => {
    const s = scenario(); const g = addGroupTiming(s, 1, 97000, 144000);
    g.report.outcomes.pop(); writeJson(g.file, g.report);
    assert.ok(measurePlan(s.plan, testRoot).groups[1].reasons.some((reason) => /omitted or replaced/.test(reason)));
  });
  console.log(`Worker P0 metrics: ${count}/${count} passed`);
} finally {
  if (!testRoot.startsWith(path.join(os.tmpdir(), "arena-p0-metrics-"))) throw new Error("unsafe fixture cleanup path");
  fs.rmSync(testRoot, { recursive: true, force: true });
}
