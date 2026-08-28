#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  createPilotManifest,
  normalizeResultRow,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const {
  createIdleGrant,
  createProducerRegistry,
} = require("./lib/campaign-resource-arbiter");
const { CampaignSupervisor } = require("./lib/campaign-supervisor");
const {
  aggregateAttention,
  captureDiskHealth,
  classifyShardRowHealth,
  createAttentionMeasurement,
  createGateFDecisionEvidence,
  createExceptionInboxItem,
  createIdleWindow,
  createProducerObservations,
  evaluateShardHealth,
  freezeGateFPlan,
  verifyGateFPlan,
  verifyIdleWindow,
} = require("./lib/gate-f-campaign");

const REPO_ROOT = path.resolve(__dirname, "../..");
const NOW = "2026-08-27T12:00:00.000Z";
const HASH = (text) => sha256OfValue({ text });
const RUNTIME = {
  runtimeMode: "formal_runtime",
  processPath: "C:/fixture/runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe",
  coreSha256: "A".repeat(64),
  buildIdentity: "B".repeat(64),
  payloadClosure: "C".repeat(64),
  pid: null,
  httpPort: null,
  verified: true,
};

function expectError(action, code) {
  let observed = null;
  try { action(); } catch (error) { observed = error; }
  assert(observed, `expected ${code || "an error"}`);
  if (code) assert.strictEqual(observed.code, code);
  return observed;
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function writeRows(filePath, rows) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${rows.map((row) => JSON.stringify(row)).join("\n")}\n`, "utf8");
}

function copyExecutionClosure(tempRoot) {
  [
    "tools/arena-calibration/lib/arena-calibration-core.js",
    "tools/arena-calibration/run-unattended.js",
    "tools/arena-calibration/schemas/case-manifest.schema.json",
    "tools/arena-calibration/schemas/result.schema.json",
    "launcher/web/modules/arena-custom-match-code.js",
    "launcher/src/Tasks/ArenaCalibrationTask.cs",
  ].forEach((relative) => {
    const destination = path.join(tempRoot, relative);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.copyFileSync(path.join(REPO_ROOT, relative), destination);
  });
}

function attentionMeasurement(id, options) {
  options = options || {};
  const minute = options.minute || 0;
  const startedAt = new Date(Date.parse(NOW) + minute * 60000).toISOString();
  const finishedAt = new Date(Date.parse(startedAt) + 30000).toISOString();
  return createAttentionMeasurement({
    measurementId: id,
    campaignId: options.campaignId || "gate-f-campaign-fixture",
    shardId: options.shardId || "gate-f-shard-01",
    shardKind: options.shardKind || "unattended",
    shardKindDeclaredAt: startedAt,
    shardStartedAt: startedAt,
    shardFinishedAt: finishedAt,
    automationEvidence: {
      driver: "gate-f-fixture",
      stdinMode: "disabled",
      interactivePromptCount: 0,
      operatorSignalCount: options.operatorSignalCount || 0,
    },
    shardHumanActionCount: options.shardHumanActionCount || 0,
    opsBreakdown: options.opsBreakdown || { startup: 0, recovery: 0, exception: 0, closeout: 0, total: 0 },
    humanBlockedMinutes: options.humanBlockedMinutes || 0,
    interruptCount: options.interruptCount || 0,
    eligibleEpochDelta: options.eligible === false ? 0 : 1,
    humanTouchDelta: options.touch ? 1 : 0,
    manualEditDelta: options.edit ? 1 : 0,
    exceptionCounts: options.exceptionCounts || { items: 0, occurrences: 0, affectedScopes: 0 },
    evidenceRefs: [HASH(id)],
    createdAt: finishedAt,
  });
}

function idleObservations(at) {
  return [
    ["fixture-launcher", "launcher"],
    ["fixture-flash", "flash"],
    ["fixture-runner", "arena_runner"],
    ["fixture-content", "content_development"],
  ].map(([producerId, scope]) => ({
    producerId,
    scope,
    online: true,
    leaseState: "idle",
    observedAt: at,
    evidenceRef: HASH(producerId),
  }));
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-arena-gate-f-"));
  try {
    copyExecutionClosure(tempRoot);
    const manifest = createPilotManifest({ batchId: "gate-f-fixture-batch", repeat: 10, timeoutFrames: 1800 });
    const manifestPath = path.join(tempRoot, "tmp", "gate-f-fixture", "case_manifest.json");
    writeJson(manifestPath, manifest);
    const candidateId = "candidate-gate-f-fixture";
    const relativeManifestForPlan = path.relative(tempRoot, manifestPath).replace(/\\/g, "/");
    const decisionEvidence = createGateFDecisionEvidence({
      decisionId: "decision-gate-f-shard-01",
      planId: "gate-f-plan-fixture",
      campaignId: "gate-f-campaign-fixture",
      shardId: "gate-f-shard-01",
      candidateIds: [candidateId],
      manifestPath: relativeManifestForPlan,
      manifestHash: manifest.manifestHash,
      plannedRuns: 10,
      evidenceRefs: [HASH("candidate-baseline")],
      createdAt: NOW,
    });
    const decisionEvidencePath = path.join(tempRoot, "tmp", "gate-f-fixture", "decision.json");
    writeJson(decisionEvidencePath, decisionEvidence);
    const soakAdmission = {
      schema: "arena-calibration.soak-admission.v1",
      admissionId: "gate-f-fixture-soak-admission",
      planId: "gate-f-plan-fixture",
      battleSemanticsCohortId: "cohort-gate-f-fixture",
      runtimeIdentity: {
        runtimeMode: RUNTIME.runtimeMode,
        processPath: RUNTIME.processPath,
        coreSha256: RUNTIME.coreSha256,
        buildIdentity: RUNTIME.buildIdentity,
        payloadClosure: RUNTIME.payloadClosure,
        verified: true,
      },
      groups: [1, 2, 3].map((soakIndex) => ({
        soakIndex,
        cells: ["B2", "C7", "G2", "F3", "E10"],
      })),
      evidenceRuns: [{
        evidenceRunId: "gate-f-fixture-soak-evidence",
        manifestPath: "tmp/fixture-soak/manifest.json",
        manifestHash: HASH("soak-manifest"),
        manifestFileSha256: HASH("soak-manifest-file"),
        resultPath: "tmp/fixture-soak/results.jsonl",
        resultFileSha256: HASH("soak-result-file"),
        reportPath: "tmp/fixture-soak/report.json",
        reportFileSha256: HASH("soak-report-file"),
      }],
      createdAt: NOW,
      admissionHash: "",
    };
    const soakAdmissionWithoutHash = JSON.parse(JSON.stringify(soakAdmission));
    delete soakAdmissionWithoutHash.admissionHash;
    soakAdmission.admissionHash = sha256OfValue(soakAdmissionWithoutHash);
    const soakAdmissionPath = path.join(tempRoot, "tmp", "gate-f-fixture", "soak-admission.json");
    writeJson(soakAdmissionPath, soakAdmission);
    const draft = {
      planId: "gate-f-plan-fixture",
      campaignId: "gate-f-campaign-fixture",
      battleSemanticsCohortId: "cohort-gate-f-fixture",
      candidateIds: [candidateId],
      candidateBaselines: [{ candidateId, initialState: "scheduled", evidenceRef: HASH("candidate-baseline") }],
      runtimeIdentity: RUNTIME,
      soakAdmissionPath: path.relative(tempRoot, soakAdmissionPath).replace(/\\/g, "/"),
      soakAdmissionRef: soakAdmission.admissionHash,
      slot: "cf7_agent_arena_calibration",
      seedSlot: "crazyflasher7_saves",
      healthPolicy: {
        minimumFreeBytes: 1073741824,
        maximumErrorRate: 0.02,
        maximumTimeoutRate: 0.05,
        maximumConsecutiveShardFailures: 2,
        maximumDurationDriftRatio: 3,
      },
      attentionPolicy: {
        minimumEligibleEpochs: 20,
        maximumTouchRate: 0.1,
        maximumOpsMinutesPer24Hours: 10,
        maximumStartupMinutes: 5,
        maximumCloseoutMinutes: 10,
        maximumDeferredItems: 5,
        maximumDeferredScopeRate: 0.1,
        targetYieldSeconds: 60,
        maximumYieldSeconds: 300,
      },
      shards: [{
        shardId: "gate-f-shard-01",
        candidateIds: [candidateId],
        manifestPath: relativeManifestForPlan,
        maxRecoveryAttempts: 1,
        maxWallClockMinutes: 40,
        eligibleEpoch: true,
        decisionEvidencePath: path.relative(tempRoot, decisionEvidencePath).replace(/\\/g, "/"),
        decisionEvidenceRef: decisionEvidence.decisionHash,
      }],
      createdAt: NOW,
    };
    const sourceIdentity = {
      commit: "1".repeat(40),
      tree: "2".repeat(40),
      worktreeClean: true,
      statusHash: HASH("clean"),
    };
    const mismatchedRuntimeDraft = JSON.parse(JSON.stringify(draft));
    mismatchedRuntimeDraft.runtimeIdentity.buildIdentity = "D".repeat(64);
    expectError(() => freezeGateFPlan(tempRoot, mismatchedRuntimeDraft, { sourceIdentity, runtimeIdentity: RUNTIME }), "runtime_identity_drift");
    const plan = freezeGateFPlan(tempRoot, draft, { sourceIdentity, runtimeIdentity: RUNTIME });
    assert.strictEqual(verifyGateFPlan(tempRoot, plan, { skipSource: true, skipRuntime: true }), true);
    assert.strictEqual(plan.shards[0].plannedRuns, 10);
    assert.strictEqual(Object.hasOwn(plan.runtimeIdentity, "pid"), false);
    assert.strictEqual(Object.hasOwn(plan.runtimeIdentity, "httpPort"), false);
    assert.strictEqual(plan.soakAdmissionRef, soakAdmission.admissionHash);

    const originalAdmission = fs.readFileSync(soakAdmissionPath, "utf8");
    const driftedAdmission = JSON.parse(originalAdmission);
    driftedAdmission.groups[2].cells[4] = "C9";
    writeJson(soakAdmissionPath, driftedAdmission);
    expectError(() => verifyGateFPlan(tempRoot, plan, { skipSource: true, skipRuntime: true }));
    fs.writeFileSync(soakAdmissionPath, originalAdmission, "utf8");

    const originalDecision = fs.readFileSync(decisionEvidencePath, "utf8");
    const driftedDecision = JSON.parse(originalDecision);
    driftedDecision.plannedRuns = 11;
    writeJson(decisionEvidencePath, driftedDecision);
    expectError(() => verifyGateFPlan(tempRoot, plan, { skipSource: true, skipRuntime: true }), "decision_evidence_hash_mismatch");
    fs.writeFileSync(decisionEvidencePath, originalDecision, "utf8");

    const originalManifest = fs.readFileSync(manifestPath, "utf8");
    const drifted = JSON.parse(originalManifest);
    drifted.cases[0].redRoster[0].level += 1;
    writeJson(manifestPath, drifted);
    expectError(() => verifyGateFPlan(tempRoot, plan, { skipSource: true, skipRuntime: true }), "manifest_integrity_mismatch");
    fs.writeFileSync(manifestPath, originalManifest, "utf8");

    const window = createIdleWindow(tempRoot, plan, {
      issuedAt: NOW,
      durationMs: 60 * 60 * 1000,
      verifyOptions: { skipSource: true, skipRuntime: true },
    });
    assert.strictEqual(verifyIdleWindow(tempRoot, plan, window, { now: "2026-08-27T12:30:00.000Z" }), true);
    const laterWindow = createIdleWindow(tempRoot, plan, {
      issuedAt: "2026-08-27T14:00:00.000Z",
      durationMs: 60 * 60 * 1000,
      verifyOptions: { skipSource: true, skipRuntime: true },
    });
    assert.notStrictEqual(laterWindow.revokeFile, window.revokeFile);
    expectError(() => verifyIdleWindow(tempRoot, plan, window, { now: "2026-08-27T13:00:00.000Z" }), "idle_window_inactive");
    const revokePath = path.join(tempRoot, window.revokeFile);
    fs.mkdirSync(path.dirname(revokePath), { recursive: true });
    fs.writeFileSync(revokePath, "revoked\n", "utf8");
    expectError(() => verifyIdleWindow(tempRoot, plan, window, { now: "2026-08-27T12:30:00.000Z" }), "idle_window_revoked");
    fs.unlinkSync(revokePath);

    const lowDisk = captureDiskHealth(tempRoot, draft.healthPolicy.minimumFreeBytes, { freeBytes: 1024, checkedAt: NOW });
    assert.strictEqual(lowDisk.ok, false);
    const timeoutRows = Array.from({ length: 20 }, (_unused, index) => ({
      status: index < 15 ? "finished" : "timeout",
      durationMs: index < 15 ? 1000 + index : 30000,
    }));
    const timeoutHealth = evaluateShardHealth(timeoutRows, draft.healthPolicy, null);
    const soakTimeoutDisposition = classifyShardRowHealth(timeoutHealth, { allowCandidateTimeoutAnomaly: false });
    const timeoutDisposition = classifyShardRowHealth(timeoutHealth, { allowCandidateTimeoutAnomaly: true });
    assert.strictEqual(timeoutHealth.timeoutRate, 0.25);
    assert.deepStrictEqual(timeoutHealth.reasons, ["timeout_rate"]);
    assert.strictEqual(soakTimeoutDisposition.executionOk, false);
    assert.strictEqual(soakTimeoutDisposition.candidateTimeoutAnomaly, false);
    assert.strictEqual(timeoutDisposition.executionOk, true);
    assert.strictEqual(timeoutDisposition.candidateQualityOk, false);
    assert.strictEqual(timeoutDisposition.candidateTimeoutAnomaly, true);
    const errorHealth = evaluateShardHealth([
      ...timeoutRows.slice(0, 19),
      { status: "error", durationMs: 1000 },
    ], draft.healthPolicy, null);
    const errorDisposition = classifyShardRowHealth(errorHealth, { allowCandidateTimeoutAnomaly: true });
    assert.strictEqual(errorDisposition.executionOk, false);
    assert.strictEqual(errorDisposition.candidateTimeoutAnomaly, false);
    const producerWindow = createIdleWindow(tempRoot, plan, {
      issuedAt: NOW,
      durationMs: 60 * 60 * 1000,
      revokeFile: "tmp/gate-f-fixture/producer-revoke.signal",
      verifyOptions: { skipSource: true, skipRuntime: true },
    });
    const activeObservations = createProducerObservations(tempRoot, plan, producerWindow, {
      observedAt: NOW,
      processes: [{ ProcessId: 77, Name: "Flash.exe", ExecutablePath: "C:/fixture/Flash.exe", CommandLine: "Flash.exe" }],
    });
    const activeRegistry = createProducerRegistry(activeObservations, {
      registryId: "gate-f-active-registry",
      generatedAt: NOW,
    });
    expectError(() => createIdleGrant(activeRegistry, { issuedAt: NOW }), "producer_not_idle");

    const selfObservations = createProducerObservations(tempRoot, plan, producerWindow, {
      observedAt: NOW,
      currentProcessId: 99,
      processes: [
        { ProcessId: 99, ParentProcessId: 88, Name: "node.exe", ExecutablePath: "C:/fixture/node.exe", CommandLine: "node gate-fctl.js arm" },
        { ProcessId: 88, ParentProcessId: 1, Name: "powershell.exe", ExecutablePath: "C:/fixture/powershell.exe", CommandLine: "powershell node gate-fctl.js arm" },
        { ProcessId: 55, ParentProcessId: 99, Name: "node.exe", ExecutablePath: "C:/fixture/node.exe", CommandLine: "node run-unattended.js --check" },
        { ProcessId: 54, ParentProcessId: 55, Name: "node.exe", ExecutablePath: "C:/fixture/node.exe", CommandLine: "node gate-fctl.js --check" },
        { ProcessId: 77, ParentProcessId: 1, Name: "node.exe", ExecutablePath: "C:/fixture/node.exe", CommandLine: "node unrelated.js" },
      ],
    });
    assert.strictEqual(selfObservations.find((entry) => entry.scope === "arena_runner").leaseState, "idle");
    const competingObservations = createProducerObservations(tempRoot, plan, producerWindow, {
      observedAt: NOW,
      currentProcessId: 99,
      processes: [
        { ProcessId: 99, ParentProcessId: 88, Name: "node.exe", ExecutablePath: "C:/fixture/node.exe", CommandLine: "node gate-fctl.js arm" },
        { ProcessId: 88, ParentProcessId: 1, Name: "powershell.exe", ExecutablePath: "C:/fixture/powershell.exe", CommandLine: "powershell node gate-fctl.js arm" },
        { ProcessId: 66, ParentProcessId: 1, Name: "node.exe", ExecutablePath: "C:/fixture/node.exe", CommandLine: "node run-unattended.js --manifest other.json" },
      ],
    });
    assert.strictEqual(competingObservations.find((entry) => entry.scope === "arena_runner").leaseState, "active");

    const rows = Array.from({ length: 10 }, (_unused, index) => normalizeResultRow({
      schema: "arena-calibration.result.v1",
      batchId: manifest.batchId,
      manifestHash: manifest.manifestHash,
      caseId: manifest.cases[0].caseId,
      caseHash: manifest.cases[0].caseHash,
      runId: `${manifest.cases[0].caseId}-r${String(index + 1).padStart(3, "0")}`,
      repeatIndex: index + 1,
      status: "finished",
      winner: index % 2 === 0 ? "blue" : "red",
      durationMs: 1000 + index,
      frames: 60 + index,
    }));
    const firstResult = path.join(tempRoot, "tmp", "gate-f-fixture", "first.jsonl");
    const secondResult = path.join(tempRoot, "tmp", "gate-f-fixture", "second.jsonl");
    writeRows(firstResult, rows.slice(0, 5));
    writeRows(secondResult, rows.slice(5));
    const reportPath = path.join(tempRoot, "tmp", "gate-f-fixture", "run-report.json");
    const relativeManifest = path.relative(tempRoot, manifestPath).replace(/\\/g, "/");
    const relativeFirst = path.relative(tempRoot, firstResult).replace(/\\/g, "/");
    const relativeSecond = path.relative(tempRoot, secondResult).replace(/\\/g, "/");
    const report = {
      schema: "arena-calibration.unattended-run.v1",
      status: "completed",
      batchId: manifest.batchId,
      rows: 5,
      startedAt: NOW,
      completedAt: "2026-08-27T12:01:00.000Z",
      runtimeIdentity: RUNTIME,
      saveProtection: {
        before: { snapshotHash: HASH("save") },
        after: { snapshotHash: HASH("save") },
        unchanged: true,
      },
      attempts: [
        { index: 1, batchId: manifest.batchId, manifestHash: manifest.manifestHash, manifestPath: relativeManifest, resultPath: relativeFirst, resultRows: 5 },
        { index: 2, batchId: manifest.batchId, manifestHash: manifest.manifestHash, manifestPath: relativeManifest, resultPath: relativeSecond, resultRows: 5 },
      ],
    };
    writeJson(reportPath, report);

    const registry = createProducerRegistry(idleObservations(NOW), {
      registryId: "gate-f-fixture-registry",
      generatedAt: NOW,
      observationTtlSeconds: 60,
    });
    const grant = createIdleGrant(registry, {
      grantId: "gate-f-fixture-grant",
      issuedAt: NOW,
      ttlSeconds: 120,
    });
    let clockNow = NOW;
    const supervisor = new CampaignSupervisor({
      projectRoot: tempRoot,
      journalRoot: path.join(tempRoot, "journal"),
      campaignId: draft.campaignId,
      clock: () => clockNow,
    });
    supervisor.initialize({
      profile: "gate_f_week_v1",
      decisionPolicyId: "gate-f-fixture-policy",
      battleSemanticsCohortId: draft.battleSemanticsCohortId,
      executionArtifactPolicy: "row-exactly-once-fixture",
      retentionDays: 90,
    }, registry, grant);
    const gateFControlSource = fs.readFileSync(path.join(REPO_ROOT, "tools/arena-calibration/gate-fctl.js"), "utf8");
    const receiptEventMatch = gateFControlSource.match(
      /supervisor\.journal\.append\("([^"]+)",\s*\{\s*shardId: receipt\.shardId/
    );
    assert(receiptEventMatch, "Gate F receipt journal event literal must remain discoverable by the schema regression");
    const receiptEvent = supervisor.journal.append(receiptEventMatch[1], {
      shardId: "gate-f-schema-fixture",
      state: "completed",
      receiptId: "gate-f-schema-fixture-receipt",
      receiptHash: HASH("gate-f-schema-fixture-receipt"),
      committedRows: 10,
      duplicatesExcluded: 0,
    });
    assert.strictEqual(receiptEvent.event.eventType, "gate_f_shard_receipt_recorded");
    clockNow = "2026-08-27T12:20:00.000Z";

    expectError(() => supervisor.importShard({
      shardId: "missing-attention",
      shardKind: "unattended",
      manifestPath: relativeManifest,
      resultPath: relativeSecond,
      runReportPath: path.relative(tempRoot, reportPath),
      battleSemanticsCohortId: draft.battleSemanticsCohortId,
      allowPartial: true,
      complete: true,
    }));

    expectError(() => supervisor.importShard({
      shardId: "gate-f-shard-01",
      shardKind: "unattended",
      manifestPath: relativeManifest,
      resultPath: relativeFirst,
      runReportPath: path.relative(tempRoot, reportPath),
      battleSemanticsCohortId: draft.battleSemanticsCohortId,
      allowPartial: true,
      complete: true,
      gateFPlanHash: plan.planHash,
      attentionMeasurement: attentionMeasurement("premature-complete"),
      attentionPolicy: draft.attentionPolicy,
    }));

    const first = supervisor.importShard({
      shardId: "gate-f-shard-01",
      shardKind: "unattended",
      manifestPath: relativeManifest,
      resultPath: relativeFirst,
      runReportPath: path.relative(tempRoot, reportPath),
      battleSemanticsCohortId: draft.battleSemanticsCohortId,
      allowPartial: true,
      complete: false,
      gateFPlanHash: plan.planHash,
      recordAttention: false,
    });
    assert.strictEqual(first.disposition.acceptedCount, 5);
    const measurement = attentionMeasurement("gate-f-measurement-01");
    const second = supervisor.importShard({
      shardId: "gate-f-shard-01",
      shardKind: "unattended",
      manifestPath: relativeManifest,
      resultPath: relativeSecond,
      runReportPath: path.relative(tempRoot, reportPath),
      battleSemanticsCohortId: draft.battleSemanticsCohortId,
      allowPartial: true,
      complete: true,
      gateFPlanHash: plan.planHash,
      attentionMeasurement: measurement,
      attentionPolicy: draft.attentionPolicy,
    });
    assert.strictEqual(second.disposition.acceptedCount, 5);
    assert.strictEqual(second.attention.event.proposalWindow.status, "insufficient_data");
    const duplicate = supervisor.importShard({
      shardId: "gate-f-shard-01",
      shardKind: "unattended",
      manifestPath: relativeManifest,
      resultPath: relativeSecond,
      runReportPath: path.relative(tempRoot, reportPath),
      battleSemanticsCohortId: draft.battleSemanticsCohortId,
      allowPartial: true,
      complete: true,
      gateFPlanHash: plan.planHash,
      attentionMeasurement: measurement,
      attentionPolicy: draft.attentionPolicy,
    });
    assert.strictEqual(duplicate.disposition.acceptedCount, 0);
    assert.strictEqual(duplicate.disposition.duplicateCount, 5);
    assert.strictEqual(duplicate.attention.duplicate, true);
    assert.strictEqual(supervisor.snapshot().committedRunKeys.length, 10);

    const wrongBinding = JSON.parse(JSON.stringify(measurement));
    wrongBinding.shardId = "wrong-shard";
    wrongBinding.measurementHash = HASH("tampered");
    expectError(() => supervisor.recordAttentionMeasurement(wrongBinding, draft.attentionPolicy));
    expectError(() => attentionMeasurement("nonzero-unattended", { operatorSignalCount: 1 }), "unattended_attention_nonzero");

    const nineteen = Array.from({ length: 19 }, (_unused, index) => attentionMeasurement(`eligible-${index + 1}`, { minute: index }));
    assert.strictEqual(aggregateAttention(nineteen, draft.attentionPolicy, nineteen[18].createdAt).status, "insufficient_data");
    const twenty = nineteen.concat([attentionMeasurement("eligible-20", { minute: 19 })]);
    const lowTouch = aggregateAttention(twenty, draft.attentionPolicy, twenty[19].createdAt);
    assert.strictEqual(lowTouch.status, "within_threshold");
    assert.strictEqual(lowTouch.rollingEligibleEpochs, 20);
    const touched = Array.from({ length: 20 }, (_unused, index) => attentionMeasurement(`touched-${index + 1}`, {
      minute: index,
      touch: index < 3,
      edit: index === 0,
    }));
    assert.strictEqual(aggregateAttention(touched, draft.attentionPolicy, touched[19].createdAt).status, "exceeds_threshold");

    const firstException = createExceptionInboxItem({
      exceptionId: "gate-f-exception-01",
      campaignId: draft.campaignId,
      dedupeKey: "gate-f|fixture|timeout",
      category: "gate_f_shard_failure",
      severity: "warning",
      status: "deferred",
      summary: "fixture timeout",
      affectedScopes: ["work:gate-f-shard-01"],
      occurrences: [{ occurrenceId: "occ-01", observedAt: NOW, evidenceRef: HASH("occ-01") }],
      defaultAction: "pause_scope",
      reviewDeadline: "2026-08-28T12:00:00.000Z",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const secondException = createExceptionInboxItem({
      ...firstException,
      exceptionId: "gate-f-exception-02",
      affectedScopes: ["candidate:candidate-gate-f-fixture"],
      occurrences: [{ occurrenceId: "occ-02", observedAt: "2026-08-27T12:02:00.000Z", evidenceRef: HASH("occ-02") }],
      updatedAt: "2026-08-27T12:02:00.000Z",
    });
    supervisor.recordException(firstException);
    const merged = supervisor.recordException(secondException);
    assert.strictEqual(merged.occurrences.length, 2);
    assert.deepStrictEqual(merged.affectedScopes, ["candidate:candidate-gate-f-fixture", "work:gate-f-shard-01"]);
    supervisor.pause("gate_f_fixture_complete", { resourcesReleased: true });

    console.log(JSON.stringify({
      ok: true,
      gate: "F0",
      frozenPlanHashBound: true,
      manifestTamperRejected: true,
      decisionEvidenceTamperRejected: true,
      diskAndProducerGatesFailClosed: true,
      infrastructureSoakTimeoutStillBlocks: true,
      candidateTimeoutDeferredWithoutInfrastructureFailure: true,
      expiredExecutionGrantStillCommitsFacts: true,
      prematureCompleteRejected: true,
      partialRowsDurablyCommitted: 10,
      duplicateRowsExcluded: 5,
      attentionDefaultsRemoved: true,
      eligibleEpochMinimum: 20,
      exceptionInboxDeduped: true,
      gateFReceiptEventSchemaValidated: true,
    }, null, 2));
  } finally {
    const resolvedTemp = path.resolve(tempRoot);
    const resolvedBase = path.resolve(os.tmpdir());
    if (!resolvedTemp.startsWith(`${resolvedBase}${path.sep}`)) {
      throw new Error(`refusing to remove unexpected fixture path: ${resolvedTemp}`);
    }
    fs.rmSync(resolvedTemp, { recursive: true, force: true });
  }
}

main();
