#!/usr/bin/env node
"use strict";

// Read-only measurement of a predeclared set of attempts. A missing, partial,
// corrupt or unsafe attempt remains in the denominator and blocks qualification.
const fs = require("fs");
const path = require("path");
const { normalizeManifest, sha256OfValue } = require("./lib/arena-calibration-core");
const { assertSchemaInstance } = require("./lib/schema-registry");
const { sha256Bytes, writeImmutableJson } = require("./lib/immutable-evidence");

const CONTEXT_FIELDS = ["workerId", "sessionEpoch", "assignmentId", "attemptId", "batchId", "manifestHash"];

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function time(value, label) {
  const result = typeof value === "string" ? Date.parse(value) : NaN;
  requireValue(Number.isFinite(result), `${label} must be a timestamp`);
  return result;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function readBoundJson(filePath, digest) {
  const bytes = fs.readFileSync(filePath);
  requireValue(sha256Bytes(bytes) === digest, `evidence hash mismatch: ${filePath}`);
  return JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, ""));
}

function saveProtectionIsValid(protection) {
  if (!protection || protection.unchanged !== true) return false;
  const snapshots = [protection.before, protection.after];
  return snapshots.every((snapshot) => snapshot && Array.isArray(snapshot.files)
    && snapshot.snapshotHash === sha256OfValue(snapshot.files.map(({ key, sha256, size }) => ({ key, sha256, size }))))
    && snapshots[0].snapshotHash === snapshots[1].snapshotHash;
}

function runDefinition(testCase) {
  // Case labels and the number of repeats may differ when a frozen workload is
  // sharded. Only identical actual battle inputs can count as equal work.
  return {
    blueRoster: testCase.blueRoster, redRoster: testCase.redRoster,
    timeoutFrames: testCase.timeoutFrames, spawnDistance: testCase.spawnDistance,
    blueFormation: testCase.blueFormation, redFormation: testCase.redFormation,
    formationSpacing: testCase.formationSpacing,
    authorityContext: testCase.authorityContext || {},
  };
}

function peakConcurrency(intervals) {
  const points = intervals.flatMap(([start, end]) => [[start, 1], [end, -1]]);
  points.sort((left, right) => left[0] - right[0] || left[1] - right[1]);
  let current = 0;
  let peak = 0;
  for (const [, change] of points) { current += change; peak = Math.max(peak, current); }
  return peak;
}

function finiteNonnegative(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function summarizeProcessObservations(observations) {
  const samples = Array.isArray(observations) ? observations : [];
  const streams = new Map();
  let unavailableSamples = 0;
  for (const sample of samples) {
    const sampledAt = sample && typeof sample.sampledAtUtc === "string" ? Date.parse(sample.sampledAtUtc) : NaN;
    if (!sample || sample.observed !== true || !Number.isInteger(sample.pid) || sample.pid <= 0
        || typeof sample.processStartUtcTicks !== "string" || !/^\d+$/.test(sample.processStartUtcTicks)
        || typeof sample.processPath !== "string" || !sample.processPath || !Number.isFinite(sampledAt)) {
      unavailableSamples++; continue;
    }
    const identity = { pid: sample.pid, processStartUtcTicks: sample.processStartUtcTicks, processPath: sample.processPath };
    const key = JSON.stringify([identity.pid, identity.processStartUtcTicks, path.resolve(identity.processPath).toLowerCase()]);
    if (!streams.has(key)) streams.set(key, { identity, samples: [] });
    streams.get(key).samples.push({ ...sample, sampledAt });
  }
  return { totalSamples: samples.length, unavailableSamples, identityCount: streams.size,
    streams: [...streams.values()].map(({ identity, samples: points }) => {
      points.sort((left, right) => left.sampledAt - right.sampledAt);
      const cpu = points.filter((point) => finiteNonnegative(point.totalProcessorTimeMs));
      const cpuMonotonic = cpu.every((point, index) => index === 0 || point.totalProcessorTimeMs >= cpu[index - 1].totalProcessorTimeMs);
      const elapsedMs = cpu.length > 1 ? cpu[cpu.length - 1].sampledAt - cpu[0].sampledAt : null;
      const cpuTimeMs = cpuMonotonic && elapsedMs > 0 ? cpu[cpu.length - 1].totalProcessorTimeMs - cpu[0].totalProcessorTimeMs : null;
      const peak = (field) => {
        const values = points.map((point) => point[field]).filter(finiteNonnegative);
        return values.length ? Math.max(...values) : null;
      };
      return { identity, observedSamples: points.length, cpuSamples: cpu.length,
        cpuInterval: cpuTimeMs === null ? null : { startedAt: cpu[0].sampledAtUtc,
          endedAt: cpu[cpu.length - 1].sampledAtUtc, elapsedMs, cpuTimeMs, averageLogicalCores: cpuTimeMs / elapsedMs },
        cpuCounterRegressed: !cpuMonotonic,
        sampledPeakWorkingSetBytes: peak("workingSetBytes"), sampledPeakPrivateMemoryBytes: peak("privateMemoryBytes") };
    }) };
}

function summarizeWindowObservations(observations) {
  const samples = Array.isArray(observations) ? observations : [];
  const counts = { backgroundVisible: 0, foreground: 0, minimized: 0, hidden: 0, unavailable: 0 };
  for (const sample of samples) {
    if (!sample || sample.observed !== true
        || !["guardianVisible", "flashVisible", "guardianMinimized", "flashMinimized", "hostForeground", "flashForeground"]
          .every((field) => typeof sample[field] === "boolean")) counts.unavailable++;
    else if (sample.guardianMinimized || sample.flashMinimized) counts.minimized++;
    else if (!sample.guardianVisible || !sample.flashVisible) counts.hidden++;
    else if (sample.hostForeground || sample.flashForeground) counts.foreground++;
    else counts.backgroundVisible++;
  }
  return { scope: "window_point_samples", continuousVisibilityVerified: false, totalSamples: samples.length, counts };
}

function summarizePerformanceObservations(observations, requested) {
  const samples = Array.isArray(observations) ? observations : [];
  const states = new Map();
  let unavailableSamples = 0;
  for (const sample of samples) {
    if (!sample || sample.observed !== true || !finiteNonnegative(sample.width) || sample.width === 0
        || !finiteNonnegative(sample.height) || sample.height === 0) { unavailableSamples++; continue; }
    const state = Object.fromEntries(["preset", "mode", "status", "width", "height", "quality", "effectLevel", "reason"]
      .map((field) => [field, sample[field] === undefined ? null : sample[field]]));
    const key = JSON.stringify(state);
    if (!states.has(key)) states.set(key, { ...state, samples: 0 });
    states.get(key).samples++;
  }
  return { scope: "last_applied_display_state_samples", requested: requested || null,
    totalSamples: samples.length, unavailableSamples, states: [...states.values()] };
}

function inspectReceipt(filePath, groupId, options = {}) {
  const receipt = readJson(filePath);
  requireValue(receipt.schema === "arena-worker.shard-receipt.v1", "unsupported shard receipt schema");
  requireValue(receipt.executionMode === "arena_worker", "receipt is not an Arena worker attempt");
  requireValue(receipt.experiment && receipt.experiment.groupId === groupId, "experiment group identity mismatch");
  CONTEXT_FIELDS.forEach((key) => requireValue(typeof receipt[key] === "string" && receipt[key].length > 0,
    `receipt has no ${key}`));
  const started = time(receipt.startedAt, "startedAt");
  const finalized = time(receipt.finalizedAt, "finalizedAt");
  requireValue(finalized > started && receipt.wallDurationMs === finalized - started,
    "lifecycle wall duration must include startup and final shutdown");
  const reasons = [];
  if (receipt.evidenceKind !== "worker_live_execution"
      && !(options.allowFixtureEvidence === true && receipt.evidenceKind === "isolated_fixture")) {
    reasons.push("live_execution_evidence_missing");
  }
  if (receipt.terminalStatus !== "completed") reasons.push(`attempt_${receipt.terminalStatus || "unknown"}`);
  if (receipt.status !== "completed" || !Array.isArray(receipt.errors) || receipt.errors.length > 0) {
    reasons.push("runner_reported_failure");
  }
  if (!receipt.shutdown || receipt.shutdown.hostExited !== true) reasons.push("host_exit_unverified");
  if (!receipt.shutdown || receipt.shutdown.flashExited !== true) reasons.push("flash_exit_unverified");
  if (receipt.flashProcessObserved !== true) reasons.push("live_flash_process_unverified");
  if (receipt.runtimeUnchanged !== true) reasons.push("candidate_runtime_changed_or_unverified");
  if (!saveProtectionIsValid(receipt.saveProtection)) reasons.push("protected_save_unverified");
  const identity = receipt.runtimeIdentity || {};
  if (identity.verified !== true || identity.runtimeMode !== "isolated_candidate"
      || !identity.coreSha256 || !identity.buildIdentity || !identity.payloadClosure || !identity.processPath) {
    reasons.push("candidate_identity_unverified");
  }
  if (!receipt.resourceClosure || !receipt.resourceClosure.closureHash
      || receipt.resourcesUnchanged !== true
      || !Array.isArray(receipt.resourceClosure.files)
      || sha256OfValue(receipt.resourceClosure.files) !== receipt.resourceClosure.closureHash
      || receipt.resourceClosureAfterHash !== receipt.resourceClosure.closureHash) reasons.push("observed_resource_closure_unverified");

  const manifest = readBoundJson(receipt.manifestSnapshotPath, receipt.manifestSha256);
  const normalized = normalizeManifest(manifest);
  requireValue(normalized.manifestHash === manifest.manifestHash
    && normalized.manifestHash === receipt.manifestHash && manifest.batchId === receipt.batchId,
  "manifest identity does not match its content and attempt");
  const expectedCount = normalized.cases.reduce((sum, testCase) => sum + testCase.repeat, 0);
  requireValue(receipt.expectedRunCount === expectedCount, "expected run cardinality differs from the frozen manifest");
  const raw = fs.readFileSync(receipt.resultPath);
  requireValue(sha256Bytes(raw) === receipt.resultSha256, "raw result hash mismatch");
  const rows = raw.toString("utf8").replace(/^\uFEFF/, "").split(/\r?\n/).filter((line) => line.trim()).map(JSON.parse);
  const seenRuns = new Set();
  const seenRepeats = new Set();
  const cases = new Map(normalized.cases.map((testCase) => [testCase.caseId, testCase]));
  const counts = { observed: rows.length, finished: 0, strengthSamples: 0, combatTimeouts: 0, failed: 0 };
  const cadence = [];
  const skillStates = [];
  for (const row of rows) {
    // Validate the unmodified production row, before counting any result.
    assertSchemaInstance("arena-calibration.result.v1", row, "raw worker result");
    CONTEXT_FIELDS.forEach((key) => requireValue(row[key] === receipt[key], `result ${key} mismatch`));
    const testCase = cases.get(row.caseId);
    requireValue(testCase && row.caseHash === testCase.caseHash && Number.isInteger(row.repeatIndex)
      && row.repeatIndex > 0 && row.repeatIndex <= testCase.repeat, "result is outside the manifest run set");
    const repeatKey = JSON.stringify([row.caseId, row.repeatIndex]);
    requireValue(!seenRepeats.has(repeatKey) && !seenRuns.has(row.runId), "duplicate run in the physical attempt");
    seenRepeats.add(repeatKey);
    seenRuns.add(row.runId);
    const hasClock = typeof row.frames === "number" && row.frames > 0
      && typeof row.durationMs === "number" && row.durationMs > 0;
    if (row.status === "finished") {
      counts.finished++;
      if (row.errors.length === 0 && hasClock && ["blue", "red", "draw"].includes(row.winner)) counts.strengthSamples++;
      else counts.failed++;
    } else if (row.status === "timeout" && hasClock && row.errors.length === 0 && row.winner === "timeout") counts.combatTimeouts++;
    else counts.failed++;
    if (hasClock) {
      cadence.push({ runId: row.runId, frames: row.frames, durationMs: row.durationMs,
        framesPerSecond: row.frames * 1000 / row.durationMs,
        qualityApplied: row.presentationAudit && row.presentationAudit.qualityApplied || "unknown",
        presentationAtStart: row.presentationAudit && row.presentationAudit.atStart || null,
        presentationAtEnd: row.presentationAudit && row.presentationAudit.atEnd || null });
    }
    if (row.skillStateAudit) skillStates.push({ runId: row.runId, repeatIndex: row.repeatIndex, audit: row.skillStateAudit });
  }
  if (rows.length !== expectedCount) reasons.push("incomplete_run_set");
  if (counts.failed > 0) reasons.push("failed_results_present");
  const batchStart = time(receipt.batchStartedAt, "batchStartedAt");
  const batchEnd = time(receipt.completedAt, "completedAt");
  requireValue(started <= batchStart && batchStart < batchEnd && batchEnd <= finalized,
    "batch timestamps are outside the measured lifecycle");
  return {
    receiptPath: filePath, receiptSha256: sha256Bytes(fs.readFileSync(filePath)),
    tuple: CONTEXT_FIELDS.map((field) => receipt[field]), receipt, reasons,
    expectedCount, counts, cadence, skillStates,
    interval: [started, finalized], batchInterval: [batchStart, batchEnd],
    runtimeKey: sha256OfValue({ runtimeMode: identity.runtimeMode, coreSha256: identity.coreSha256,
      buildIdentity: identity.buildIdentity, payloadClosure: identity.payloadClosure,
      resourceClosure: receipt.resourceClosure ? {
        scope: receipt.resourceClosure.scope, closureHash: receipt.resourceClosure.closureHash,
        completeResourceClosure: receipt.resourceClosure.completeResourceClosure === true,
      } : null }),
    work: normalized.cases.map((testCase) => ({ key: sha256OfValue(runDefinition(testCase)), count: testCase.repeat })),
  };
}

function measureGroup(group, planDirectory, usedReceipts, options) {
  requireValue(typeof group.groupId === "string" && group.groupId.length > 0, "groupId required");
  requireValue(Number.isInteger(group.expectedConcurrency) && group.expectedConcurrency > 0,
    "expectedConcurrency must be a positive integer");
  requireValue(Array.isArray(group.receiptPaths) && group.receiptPaths.length > 0, "declare every receipt path before measuring");
  const inspected = [];
  const rejected = [];
  for (const relative of group.receiptPaths) {
    const filePath = path.resolve(planDirectory, relative);
    const pathKey = filePath.toLowerCase();
    requireValue(!usedReceipts.has(pathKey), "receipt cannot be counted in more than one experiment position");
    usedReceipts.add(pathKey);
    try { inspected.push(inspectReceipt(filePath, group.groupId, options)); }
    catch (error) { rejected.push({ receiptPath: filePath, reason: error.message }); }
  }
  const reasons = inspected.flatMap((entry) => entry.reasons);
  if (rejected.length) reasons.push("missing_or_invalid_attempt_evidence");
  const tuples = inspected.map((entry) => JSON.stringify(entry.tuple));
  if (new Set(tuples).size !== tuples.length) reasons.push("duplicate_physical_attempt");
  const runtimeKeys = new Set(inspected.map((entry) => entry.runtimeKey));
  if (runtimeKeys.size !== 1) reasons.push("mixed_or_missing_runtime_identity");
  const observedConcurrency = peakConcurrency(inspected.map((entry) => entry.batchInterval));
  if (observedConcurrency !== group.expectedConcurrency) reasons.push("observed_concurrency_differs_from_plan");
  for (let first = 0; first < inspected.length; first++) {
    for (let second = first + 1; second < inspected.length; second++) {
      const left = inspected[first]; const right = inspected[second];
      if (Math.max(left.interval[0], right.interval[0]) >= Math.min(left.interval[1], right.interval[1])) continue;
      const leftOwner = left.receipt.ownerSnapshot || {};
      const rightOwner = right.receipt.ownerSnapshot || {};
      if (!Number.isInteger(leftOwner.hostPid) || !Number.isInteger(rightOwner.hostPid)
          || leftOwner.hostPid === rightOwner.hostPid || left.receipt.sessionEpoch === right.receipt.sessionEpoch
          || left.receipt.workerId === right.receipt.workerId) reasons.push("overlapping_process_ownership_not_independent");
      for (const field of ["projectRoot", "stateRoot", "saveRoot", "outputRoot", "swfOrigin"]) {
        if (typeof leftOwner[field] !== "string" || typeof rightOwner[field] !== "string"
            || path.resolve(leftOwner[field]).toLowerCase() === path.resolve(rightOwner[field]).toLowerCase()) {
          reasons.push(`overlapping_${field}_not_independent`);
        }
      }
      if (![leftOwner.httpPort, leftOwner.socketPort, rightOwner.httpPort, rightOwner.socketPort].every(Number.isInteger)
          || new Set([leftOwner.httpPort, leftOwner.socketPort, rightOwner.httpPort, rightOwner.socketPort]).size !== 4) {
        reasons.push("overlapping_endpoints_not_independent");
      }
    }
  }
  if (group.saveProtectionPath) {
    try {
      if (!saveProtectionIsValid(readJson(path.resolve(planDirectory, group.saveProtectionPath)))) reasons.push("global_save_protection_failed");
    } catch (error) { reasons.push(`global_save_protection_unreadable: ${error.message}`); }
  } else if (group.expectedConcurrency > 1) reasons.push("global_save_protection_missing");
  const work = new Map();
  for (const entry of inspected) for (const item of entry.work) work.set(item.key, (work.get(item.key) || 0) + item.count);
  const workloadHash = sha256OfValue([...work].sort((a, b) => a[0].localeCompare(b[0])));
  const receiptEnvelopeWallDurationMs = inspected.length && !rejected.length
    ? Math.max(...inspected.map((entry) => entry.interval[1])) - Math.min(...inspected.map((entry) => entry.interval[0])) : null;
  let wallDurationMs = receiptEnvelopeWallDurationMs;
  let wallDenominatorScope = "receipt_envelope";
  let coordinatorTiming = null;
  if (group.groupReportPath) {
    wallDenominatorScope = "coordinator_group";
    wallDurationMs = null;
    try {
      const reportPath = path.resolve(planDirectory, group.groupReportPath);
      const report = readJson(reportPath);
      requireValue(report.groupId === group.groupId && Array.isArray(report.outcomes), "coordinator group identity mismatch");
      const groupStart = time(report.startedAt, "group startedAt");
      const groupEnd = time(report.completedAt, "group completedAt");
      requireValue(groupEnd > groupStart && report.wallDurationMs === groupEnd - groupStart,
        "coordinator wall duration does not bind its full group interval");
      const expectedPaths = group.receiptPaths.map((file) => path.resolve(planDirectory, file).toLowerCase()).sort();
      const actualPaths = report.outcomes.map((outcome) => path.resolve(planDirectory, outcome.expectedReceiptPath).toLowerCase()).sort();
      requireValue(JSON.stringify(expectedPaths) === JSON.stringify(actualPaths), "coordinator report omitted or replaced an expected attempt");
      for (const entry of inspected) {
        const outcome = report.outcomes.find((value) => path.resolve(planDirectory, value.expectedReceiptPath).toLowerCase() === entry.receiptPath.toLowerCase());
        requireValue(outcome.receiptSha256 === entry.receiptSha256, "coordinator receipt hash mismatch");
        requireValue(groupStart <= entry.interval[0] && entry.interval[1] <= groupEnd,
          "coordinator interval omits an attempt lifecycle");
      }
      if (report.seedSourcesUnchanged !== true || report.globalSaveUnchanged !== true || report.stopBeforeNextGroup !== false) {
        reasons.push("coordinator_protection_or_recycling_failed");
      }
      wallDurationMs = report.wallDurationMs;
      coordinatorTiming = { reportPath, reportSha256: sha256Bytes(fs.readFileSync(reportPath)),
        startedAt: report.startedAt, completedAt: report.completedAt, wallDurationMs };
    } catch (error) { reasons.push(`coordinator_timing_unverified: ${error.message}`); }
  }
  const counts = inspected.reduce((sum, entry) => {
    for (const key of Object.keys(sum)) sum[key] += entry.counts[key];
    return sum;
  }, { observed: 0, finished: 0, strengthSamples: 0, combatTimeouts: 0, failed: 0 });
  const qualified = reasons.length === 0;
  return {
    groupId: group.groupId, qualified, reasons: [...new Set(reasons)],
    expectedReceipts: group.receiptPaths.length, observedReceipts: inspected.length,
    expectedConcurrency: group.expectedConcurrency, observedConcurrency,
    expectedRuns: inspected.reduce((sum, entry) => sum + entry.expectedCount, 0), counts,
    wallDurationMs, wallDenominatorScope, receiptEnvelopeWallDurationMs, coordinatorTiming,
    workloadHash, runtimeKey: runtimeKeys.size === 1 ? [...runtimeKeys][0] : null,
    observedStrengthSamplesPerHour: wallDurationMs ? counts.strengthSamples * 3600000 / wallDurationMs : null,
    qualifiedStrengthSamplesPerHour: qualified && wallDurationMs ? counts.strengthSamples * 3600000 / wallDurationMs : null,
    rejectedAttempts: rejected,
    attempts: inspected.map((entry) => ({
      receiptPath: entry.receiptPath, receiptSha256: entry.receiptSha256,
      identity: Object.fromEntries(CONTEXT_FIELDS.map((key) => [key, entry.receipt[key]])),
      reasons: entry.reasons, counts: entry.counts, experiment: entry.receipt.experiment,
      resourceClosureScope: entry.receipt.resourceClosure && entry.receipt.resourceClosure.scope || "unknown",
      completeResourceClosure: !!(entry.receipt.resourceClosure && entry.receipt.resourceClosure.completeResourceClosure === true),
      wallDurationMs: entry.interval[1] - entry.interval[0], cadence: entry.cadence, skillStates: entry.skillStates,
      observations: {
        windows: summarizeWindowObservations(entry.receipt.windowObservations),
        performance: summarizePerformanceObservations(entry.receipt.performanceObservations,
          entry.receipt.ownerSnapshot && entry.receipt.ownerSnapshot.performance),
        processResources: { scope: "host_and_flash_only", webViewChildrenIncluded: false,
          host: summarizeProcessObservations(entry.receipt.hostProcessObservations),
          flash: summarizeProcessObservations(entry.receipt.flashProcessObservations) },
      },
    })),
  };
}

function measurePlan(plan, planDirectory, options = {}) {
  requireValue(plan.schema === "arena-worker.p0-plan.v1" && Array.isArray(plan.groups) && plan.groups.length > 0,
    "unsupported P0 measurement plan");
  const seenGroups = new Set();
  const usedReceipts = new Set();
  const groups = plan.groups.map((group) => {
    requireValue(!seenGroups.has(group.groupId), "duplicate experiment group");
    seenGroups.add(group.groupId);
    return measureGroup(group, planDirectory, usedReceipts, options);
  });
  const comparisons = (plan.comparisons || []).map(({ baseline, candidate }) => {
    const before = groups.find((group) => group.groupId === baseline);
    const after = groups.find((group) => group.groupId === candidate);
    const reasons = [];
    if (!before || !after) reasons.push("unknown_comparison_group");
    else {
      if (!before.qualified || !after.qualified) reasons.push("unqualified_group");
      if (before.workloadHash !== after.workloadHash) reasons.push("different_workload");
      if (before.runtimeKey !== after.runtimeKey) reasons.push("different_runtime");
      if (!(before.qualifiedStrengthSamplesPerHour > 0)) reasons.push("zero_baseline_samples");
    }
    return { baseline, candidate, qualified: reasons.length === 0, reasons,
      throughputRatio: reasons.length === 0 ? after.qualifiedStrengthSamplesPerHour / before.qualifiedStrengthSamplesPerHour : null };
  });
  return { schema: "arena-worker.p0-measurement.v1", measuredAt: new Date().toISOString(),
    planHash: sha256OfValue(plan), evidenceLevel: options.allowFixtureEvidence === true ? "isolated_fixture" : "candidate_measurement",
    qualified: groups.every((group) => group.qualified) && comparisons.every((entry) => entry.qualified), groups, comparisons };
}

function main(argv) {
  requireValue(argv.length === 4 && argv[0] === "--plan" && argv[2] === "--output",
    "Usage: node measure-worker-p0.js --plan <frozen-plan.json> --output <new-report.json>");
  const planPath = path.resolve(argv[1]);
  const report = measurePlan(readJson(planPath), path.dirname(planPath));
  report.planPath = planPath;
  report.planSha256 = sha256Bytes(fs.readFileSync(planPath));
  writeImmutableJson(path.resolve(argv[3]), report);
  console.log(JSON.stringify({ qualified: report.qualified, groups: report.groups.length, output: path.resolve(argv[3]) }));
  if (!report.qualified) process.exitCode = 1;
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}

module.exports = { inspectReceipt, measurePlan, peakConcurrency, saveProtectionIsValid,
  summarizeProcessObservations, summarizeWindowObservations, summarizePerformanceObservations };
