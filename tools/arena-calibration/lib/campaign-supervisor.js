"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  readJsonFile,
  readJsonLines,
  sha256OfValue,
} = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");
const {
  validateIdleGrant,
} = require("./campaign-resource-arbiter");
const {
  DurableCampaignJournal,
  writeJsonAtomic,
} = require("./durable-campaign-journal");
const {
  aggregateAttention,
  resultRunKey,
  verifyAttentionMeasurement,
  verifyManifestIntegrity,
} = require("./gate-f-campaign");

const EXECUTION_ARTIFACT_SCHEMA = "arena-calibration.execution-artifact.v1";
const COMPATIBILITY_SCHEMA = "arena-calibration.cohort-compatibility-receipt.v1";
const ATTENTION_SCHEMA = "arena-calibration.attention-event.v1";

function safeId(value, fallback) {
  const normalized = String(value || "").replace(/[^A-Za-z0-9._:-]+/g, "-").slice(0, 150);
  return normalized && /^[A-Za-z0-9]/.test(normalized) ? normalized : fallback;
}

function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return `sha256:${hash.digest("hex")}`;
}

function relativePath(root, filePath) {
  return path.relative(root, filePath).replace(/\\/g, "/");
}

function resolveInsideRoot(root, candidate, label) {
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(root, candidate);
  const relative = path.relative(resolvedRoot, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`${label} is outside the project root: ${candidate}`);
  }
  if (!fs.existsSync(resolved)) throw new Error(`${label} does not exist: ${candidate}`);
  return resolved;
}

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function validateResultRowsAgainstManifest(rows, manifest, label, options) {
  options = options || {};
  verifyManifestIntegrity(manifest, `${label} manifest`);
  const cases = new Map(manifest.cases.map((entry) => [entry.caseId, entry]));
  const seenRunIds = new Set();
  const seenRepeats = new Set();
  rows.forEach((row, index) => {
    assertSchemaInstance("arena-calibration.result.v1", row, `${label} row ${index + 1}`);
    const testCase = cases.get(row.caseId);
    if (!testCase) throw new Error(`${label} row ${index + 1} references unknown caseId ${row.caseId}`);
    if (row.batchId !== manifest.batchId || row.manifestHash !== manifest.manifestHash || row.caseHash !== testCase.caseHash) {
      throw new Error(`${label} row ${index + 1} does not bind to the exact manifest/case hash`);
    }
    if (row.repeatIndex < 1 || row.repeatIndex > testCase.repeat) {
      throw new Error(`${label} row ${index + 1} repeatIndex is outside the case budget`);
    }
    if (seenRunIds.has(row.runId)) throw new Error(`${label} contains duplicate runId ${row.runId}`);
    seenRunIds.add(row.runId);
    const repeatKey = `${row.caseId}|${row.repeatIndex}`;
    if (seenRepeats.has(repeatKey)) throw new Error(`${label} contains duplicate case repeat ${repeatKey}`);
    seenRepeats.add(repeatKey);
  });
  const expectedRows = manifest.cases.reduce((sum, entry) => sum + entry.repeat, 0);
  if (rows.length < 1 || rows.length > expectedRows) {
    throw new Error(`${label} has ${rows.length} rows; expected 1..${expectedRows}`);
  }
  if (options.allowPartial !== true && rows.length !== expectedRows) {
    throw new Error(`${label} has ${rows.length} rows; expected ${expectedRows}`);
  }
  return { expectedRows, complete: rows.length === expectedRows };
}

function executionClosureIdentity(root, manifestHash, runtimeIdentity) {
  const sourcePaths = [
    "tools/arena-calibration/lib/arena-calibration-core.js",
    "tools/arena-calibration/run-unattended.js",
    "tools/arena-calibration/schemas/case-manifest.schema.json",
    "tools/arena-calibration/schemas/result.schema.json",
    "launcher/web/modules/arena-custom-match-code.js",
    "launcher/src/Tasks/ArenaCalibrationTask.cs",
  ];
  const files = sourcePaths.map((entry) => {
    const resolved = resolveInsideRoot(root, entry, "execution closure source");
    return { path: entry, sha256: sha256File(resolved) };
  });
  return sha256OfValue({ manifestHash, runtimeIdentity, files });
}

function createCompatibilityReceipt(input) {
  const receipt = {
    schema: COMPATIBILITY_SCHEMA,
    receiptId: safeId(input.receiptId, `compat-${input.shardId}`),
    executionArtifactIdentity: input.executionArtifactIdentity,
    battleSemanticsCohortId: input.battleSemanticsCohortId,
    changedPaths: (input.changedPaths || []).slice().sort(),
    classifierVersion: input.classifierVersion || "arena-battle-closure-v1",
    negativeChecks: (input.negativeChecks || []).slice(),
    compatible: input.compatible === true,
    reason: input.reason,
    createdAt: input.createdAt,
    receiptHash: "",
  };
  receipt.receiptHash = sha256OfValue(withoutHash(receipt, "receiptHash"));
  assertSchemaInstance(COMPATIBILITY_SCHEMA, receipt, "cohort compatibility receipt");
  return receipt;
}

function createAttentionEvent(input) {
  if (!input || !input.measurement || !input.aggregate) {
    throw new Error("attention event requires one verified measurement and its aggregate");
  }
  const measurement = input.measurement;
  verifyAttentionMeasurement(measurement, {
    campaignId: input.campaignId,
    shardId: input.shardId,
    shardKind: input.shardKind,
  });
  const aggregate = input.aggregate;
  const eligibleEpochs = aggregate.rollingEligibleEpochs;
  const humanTouches = aggregate.rollingHumanTouches;
  const manualEdits = aggregate.rollingManualEdits;
  const event = {
    schema: ATTENTION_SCHEMA,
    eventId: safeId(input.eventId, `attention-${measurement.measurementId}`),
    campaignId: measurement.campaignId,
    shardId: measurement.shardId,
    shardKind: measurement.shardKind,
    shardKindDeclaredAt: measurement.shardKindDeclaredAt,
    shardStartedAt: measurement.shardStartedAt,
    shardHumanActionCount: measurement.shardHumanActionCount,
    opsActiveMinutes: measurement.opsBreakdown.total,
    humanBlockedMinutes: measurement.humanBlockedMinutes,
    interruptCount: measurement.interruptCount,
    measurementRef: measurement.measurementId,
    measurementHash: measurement.measurementHash,
    opsBreakdown: { ...measurement.opsBreakdown },
    evidenceRefs: measurement.evidenceRefs.slice(),
    proposalWindow: {
      windowKind: "rolling_20",
      minimumDenominator: 20,
      eligibleEpochs,
      humanTouches,
      manualEdits,
      touchRate: aggregate.rollingTouchRate,
      manualEditRate: aggregate.rollingManualEditRate,
      status: aggregate.status,
    },
    exceptionCounts: { ...measurement.exceptionCounts },
    createdAt: measurement.createdAt,
  };
  assertSchemaInstance(ATTENTION_SCHEMA, event, "attention event");
  return event;
}

function attentionPolicy(input) {
  const policy = input || {};
  return {
    minimumEligibleEpochs: policy.minimumEligibleEpochs === undefined ? 20 : policy.minimumEligibleEpochs,
    maximumTouchRate: policy.maximumTouchRate === undefined ? 0.1 : policy.maximumTouchRate,
    maximumOpsMinutesPer24Hours: policy.maximumOpsMinutesPer24Hours === undefined
      ? 10 : policy.maximumOpsMinutesPer24Hours,
    maximumStartupMinutes: policy.maximumStartupMinutes === undefined ? 5 : policy.maximumStartupMinutes,
    maximumCloseoutMinutes: policy.maximumCloseoutMinutes === undefined ? 10 : policy.maximumCloseoutMinutes,
  };
}

function readAttentionMeasurements(artifactDir) {
  if (!fs.existsSync(artifactDir)) return [];
  return fs.readdirSync(artifactDir)
    .filter((name) => /^attention-measurement-.*\.json$/i.test(name))
    .sort()
    .map((name) => readJsonFile(path.join(artifactDir, name)));
}

class CampaignSupervisor {
  constructor(options) {
    options = options || {};
    this.projectRoot = path.resolve(options.projectRoot);
    this.campaignId = safeId(options.campaignId, "campaign");
    this.clock = options.clock || (() => new Date().toISOString());
    this.trustedIssuers = options.trustedIssuers || ["cf7-local-development-arbiter"];
    this.journal = new DurableCampaignJournal({
      root: options.journalRoot || path.join(this.projectRoot, "logs/arena-calibration/campaigns"),
      campaignId: this.campaignId,
      clock: this.clock,
      leaseTtlMs: options.leaseTtlMs,
    });
    this.activeGrant = null;
    this.activeRegistry = null;
    this.config = options.config || null;
  }

  acquire(options) {
    return this.journal.acquireWriter(options);
  }

  release(reason) {
    return this.journal.releaseWriter(reason);
  }

  initialize(config, registry, grant) {
    if (!this.journal.lease) this.acquire({ allowStaleRecovery: true });
    const snapshot = this.journal.snapshot();
    if (snapshot.eventCount === 0) {
      this.journal.append("campaign_created", {
        profile: config.profile,
        decisionPolicyId: config.decisionPolicyId,
        battleSemanticsCohortId: config.battleSemanticsCohortId,
        executionArtifactPolicy: config.executionArtifactPolicy,
        retentionDays: config.retentionDays,
      });
    }
    this.config = { ...config };
    return this.resume(registry, grant, "campaign_initialize");
  }

  resume(registry, grant, reason) {
    if (!this.journal.lease) this.acquire({ allowStaleRecovery: true });
    validateIdleGrant(grant, registry, { now: this.clock(), trustedIssuers: this.trustedIssuers });
    const previousState = this.journal.state.campaignState;
    this.activeRegistry = JSON.parse(JSON.stringify(registry));
    this.activeGrant = JSON.parse(JSON.stringify(grant));
    this.journal.append("producer_registry_observed", {
      registryId: registry.registryId,
      registryHash: registry.registryHash,
      producerSetHash: registry.producerSetHash,
      producerCount: registry.producers.length,
    });
    this.journal.append("idle_grant_accepted", {
      grantId: grant.grantId,
      grantHash: grant.grantHash,
      issuer: grant.issuer,
      scope: grant.scope,
      expiresAt: grant.expiresAt,
      reason: reason || "campaign_resume",
    });
    if (previousState !== "RUNNING") {
      this.journal.append("campaign_resumed", { grantId: grant.grantId, reason: reason || "campaign_resume" });
    }
    return this.journal.snapshot();
  }

  _requireGrant(options) {
    options = options || {};
    try {
      validateIdleGrant(this.activeGrant, this.activeRegistry, {
        now: options.allowExpiredForCommit === true && this.activeGrant
          ? this.activeGrant.issuedAt : this.clock(),
        trustedIssuers: this.trustedIssuers,
      });
    } catch (error) {
      if (this.journal.state && this.journal.state.campaignState === "RUNNING") {
        this.journal.append("campaign_paused", { reason: error.code || "idle_grant_invalid", detail: error.message });
      }
      throw error;
    }
  }

  scheduleShard(input) {
    this._requireGrant();
    const manifestPath = resolveInsideRoot(this.projectRoot, input.manifestPath, "shard manifest");
    const manifest = readJsonFile(manifestPath);
    assertSchemaInstance("arena-calibration.case-manifest.v1", manifest, "scheduled shard manifest");
    this.journal.append("shard_scheduled", {
      shardId: safeId(input.shardId, "shard"),
      shardKind: input.shardKind || "unattended",
      manifestPath: relativePath(this.projectRoot, manifestPath),
      manifestHash: manifest.manifestHash,
      plannedRuns: manifest.cases.reduce((sum, entry) => sum + entry.repeat, 0),
      grantId: this.activeGrant.grantId,
    });
    return manifest;
  }

  importShard(input) {
    // Durable import must preserve already-produced facts even when a short
    // execution idleGrant expires during a 20-40 minute shard. Revalidate the
    // exact hash-bound grant at its issue time; this path never starts a game.
    this._requireGrant({ allowExpiredForCommit: true });
    const manifestPath = resolveInsideRoot(this.projectRoot, input.manifestPath, "shard manifest");
    const resultPath = resolveInsideRoot(this.projectRoot, input.resultPath, "shard result JSONL");
    const runReportPath = resolveInsideRoot(this.projectRoot, input.runReportPath, "shard run report");
    const manifest = readJsonFile(manifestPath);
    const rows = readJsonLines(resultPath);
    const report = readJsonFile(runReportPath);
    const validation = validateResultRowsAgainstManifest(rows, manifest, input.shardId, {
      allowPartial: input.allowPartial === true,
    });
    const resultPathRelative = relativePath(this.projectRoot, resultPath);
    const reportAttempt = Array.isArray(report.attempts)
      ? report.attempts.find((entry) => entry.batchId === manifest.batchId
        && entry.manifestHash === manifest.manifestHash
        && entry.resultPath === resultPathRelative)
      : null;
    const topLevelBinding = report.batchId === manifest.batchId && report.rows === rows.length;
    const attemptBinding = reportAttempt && reportAttempt.resultRows === rows.length;
    if (input.allowPartial === true) {
      if (!attemptBinding && !topLevelBinding) {
        throw new Error("run report does not bind to the imported partial shard result");
      }
    } else if (report.status !== "completed" || !topLevelBinding) {
      throw new Error("run report does not bind to a completed exact shard result");
    }
    if (!report.runtimeIdentity || report.runtimeIdentity.verified !== true) {
      throw new Error("run report runtime identity is not verified");
    }
    if (
      !report.saveProtection
      || report.saveProtection.unchanged !== true
      || !report.saveProtection.before
      || !report.saveProtection.after
      || report.saveProtection.before.snapshotHash !== report.saveProtection.after.snapshotHash
    ) {
      throw new Error("protected player save snapshot changed or was not verified");
    }
    if (input.recordAttention !== false && !input.attentionMeasurement) {
      throw new Error("shard import requires an explicit attention measurement");
    }
    if (input.recordAttention === false && (input.allowPartial !== true || input.complete === true)) {
      throw new Error("attention may only be deferred for an incomplete partial import");
    }

    const createdAt = this.clock();
    const executionArtifactIdentity = executionClosureIdentity(this.projectRoot, manifest.manifestHash, {
      runtimeMode: report.runtimeIdentity.runtimeMode,
      processPath: report.runtimeIdentity.processPath,
      coreSha256: report.runtimeIdentity.coreSha256,
      buildIdentity: report.runtimeIdentity.buildIdentity,
      payloadClosure: report.runtimeIdentity.payloadClosure,
      verified: report.runtimeIdentity.verified,
    });
    const compatibility = createCompatibilityReceipt({
      receiptId: `compat-${safeId(input.shardId, "shard")}-${manifest.manifestHash.slice(7, 23)}`,
      shardId: input.shardId,
      executionArtifactIdentity,
      battleSemanticsCohortId: input.battleSemanticsCohortId,
      changedPaths: input.changedPaths || [],
      classifierVersion: input.classifierVersion,
      negativeChecks: input.negativeChecks || [
        "raw_result_schema_and_manifest_binding",
        "formal_runtime_identity_exact",
        "protected_live_save_snapshot_unchanged",
      ],
      compatible: input.compatible !== false,
      reason: input.compatibilityReason || "Campaign-only orchestration changes do not enter the frozen battle semantics closure.",
      createdAt,
    });
    if (!compatibility.compatible) throw new Error("execution artifact is not compatible with the requested battle semantics cohort");
    const statusCounts = {};
    rows.forEach((row) => { statusCounts[row.status] = (statusCounts[row.status] || 0) + 1; });
    const resultSha256 = sha256File(resultPath);
    const artifactSuffix = resultSha256.slice("sha256:".length, "sha256:".length + 16);
    const runKey = `${input.shardId}|${manifest.manifestHash}|${resultSha256}`;
    const rowRunKeys = rows.map((row) => resultRunKey(manifest.manifestHash, row));
    const committedForShard = this.journal.state.events
      .map((entry) => entry.event)
      .filter((event) => event.eventType === "result_committed"
        && event.payload.shardId === safeId(input.shardId, "shard")
        && event.payload.manifestHash === manifest.manifestHash)
      .map((event) => event.payload.runKey);
    const projectedRunKeys = new Set(committedForShard.concat(rowRunKeys));
    if (input.complete === true && projectedRunKeys.size !== validation.expectedRows) {
      throw new Error(`completed shard has ${projectedRunKeys.size} durable rows; expected ${validation.expectedRows}`);
    }
    const complete = input.complete === true
      || (input.complete !== false && validation.complete && report.status === "completed");
    const artifact = {
      schema: EXECUTION_ARTIFACT_SCHEMA,
      artifactId: safeId(`execution-${input.shardId}-${artifactSuffix}`, "execution-artifact"),
      campaignId: this.campaignId,
      shardId: safeId(input.shardId, "shard"),
      runKey,
      manifestPath: relativePath(this.projectRoot, manifestPath),
      manifestHash: manifest.manifestHash,
      resultPath: resultPathRelative,
      resultSha256,
      runReportPath: relativePath(this.projectRoot, runReportPath),
      runReportSha256: sha256File(runReportPath),
      runtimeIdentity: {
        runtimeMode: report.runtimeIdentity.runtimeMode,
        processPath: report.runtimeIdentity.processPath,
        coreSha256: report.runtimeIdentity.coreSha256,
        buildIdentity: report.runtimeIdentity.buildIdentity,
        payloadClosure: report.runtimeIdentity.payloadClosure,
        verified: report.runtimeIdentity.verified,
      },
      battleSemanticsCohortId: input.battleSemanticsCohortId,
      cohortCompatibilityReceiptRef: compatibility.receiptHash,
      rows: rows.length,
      expectedRows: validation.expectedRows,
      complete,
      rowRunKeys,
      gateFPlanHash: input.gateFPlanHash || null,
      statusCounts,
      protectedSaveSnapshot: report.saveProtection.before.snapshotHash,
      protectedSaveUnchanged: true,
      createdAt,
      artifactHash: "",
    };
    artifact.artifactHash = sha256OfValue(withoutHash(artifact, "artifactHash"));
    assertSchemaInstance(EXECUTION_ARTIFACT_SCHEMA, artifact, "execution artifact");

    const artifactDir = path.join(this.journal.root, "artifacts");
    writeJsonAtomic(path.join(artifactDir, `${artifact.artifactId}.json`), artifact);
    writeJsonAtomic(path.join(artifactDir, `${compatibility.receiptId}.json`), compatibility);
    const dispositions = rows.map((row, index) => this.journal.appendResultOnce(rowRunKeys[index], {
      shardId: artifact.shardId,
      artifactId: artifact.artifactId,
      artifactHash: artifact.artifactHash,
      manifestHash: artifact.manifestHash,
      runId: row.runId,
      caseId: row.caseId,
      repeatIndex: row.repeatIndex,
      status: row.status,
      compatibilityReceiptHash: compatibility.receiptHash,
    }, index === 0 ? input.journalOptions : undefined));
    const disposition = {
      accepted: dispositions.some((entry) => entry.accepted),
      acceptedCount: dispositions.filter((entry) => entry.accepted).length,
      duplicateCount: dispositions.filter((entry) => !entry.accepted).length,
      rows: dispositions,
    };

    const attention = input.recordAttention === false ? null : this.recordAttentionMeasurement(
      input.attentionMeasurement,
      input.attentionPolicy
    );
    return { artifact, compatibility, attention, disposition };
  }

  recordAttentionMeasurement(measurement, policy) {
    if (!this.journal.lease) throw new Error("attention measurement requires the active campaign writer lease");
    verifyAttentionMeasurement(measurement, {
      campaignId: this.campaignId,
      shardId: measurement && measurement.shardId,
      shardKind: measurement && measurement.shardKind,
    });
    const artifactDir = path.join(this.journal.root, "artifacts");
    fs.mkdirSync(artifactDir, { recursive: true });
    const measurementPath = path.join(
      artifactDir,
      `attention-measurement-${safeId(measurement.measurementId, "measurement")}.json`
    );
    if (fs.existsSync(measurementPath)) {
      const existing = readJsonFile(measurementPath);
      verifyAttentionMeasurement(existing);
      if (existing.measurementHash !== measurement.measurementHash) {
        throw new Error(`attention measurement id collision: ${measurement.measurementId}`);
      }
      const eventPath = path.join(artifactDir, `attention-${safeId(measurement.measurementId, "measurement")}.json`);
      return {
        measurement: existing,
        event: fs.existsSync(eventPath) ? readJsonFile(eventPath) : null,
        duplicate: true,
      };
    }
    const measurements = readAttentionMeasurements(artifactDir).concat([measurement]);
    const aggregate = aggregateAttention(measurements, attentionPolicy(policy), measurement.createdAt);
    const event = createAttentionEvent({
      eventId: `attention-${measurement.measurementId}`,
      campaignId: this.campaignId,
      shardId: measurement.shardId,
      shardKind: measurement.shardKind,
      measurement,
      aggregate,
    });
    writeJsonAtomic(measurementPath, measurement);
    writeJsonAtomic(path.join(artifactDir, `${event.eventId}.json`), event);
    this.journal.append("attention_recorded", {
      shardId: event.shardId,
      attentionEventId: event.eventId,
      attentionEventHash: sha256OfValue(event),
      measurementId: measurement.measurementId,
      measurementHash: measurement.measurementHash,
      shardHumanActionCount: event.shardHumanActionCount,
      humanBlockedMinutes: event.humanBlockedMinutes,
    });
    return { measurement, event, aggregate, duplicate: false };
  }

  recordException(item) {
    if (!this.journal.lease) throw new Error("exception recording requires the active campaign writer lease");
    assertSchemaInstance("arena-calibration.exception-inbox-item.v1", item, "exception inbox item");
    if (item.campaignId !== this.campaignId) throw new Error("exception item is not bound to this campaign");
    const artifactDir = path.join(this.journal.root, "artifacts");
    fs.mkdirSync(artifactDir, { recursive: true });
    const candidates = fs.readdirSync(artifactDir)
      .filter((name) => /^exception-.*\.json$/i.test(name))
      .map((name) => ({ name, value: readJsonFile(path.join(artifactDir, name)) }))
      .filter((entry) => entry.value.schema === "arena-calibration.exception-inbox-item.v1"
        && entry.value.dedupeKey === item.dedupeKey);
    if (candidates.length > 1) throw new Error(`multiple exception items share dedupeKey ${item.dedupeKey}`);
    let merged = JSON.parse(JSON.stringify(item));
    let fileName = `exception-${safeId(item.exceptionId, "item")}.json`;
    if (candidates.length === 1) {
      const existing = candidates[0].value;
      const occurrences = new Map(existing.occurrences.map((entry) => [entry.occurrenceId, entry]));
      item.occurrences.forEach((entry) => {
        const previous = occurrences.get(entry.occurrenceId);
        if (previous && sha256OfValue(previous) !== sha256OfValue(entry)) {
          throw new Error(`exception occurrence id collision: ${entry.occurrenceId}`);
        }
        occurrences.set(entry.occurrenceId, entry);
      });
      const severityOrder = ["info", "warning", "blocking_scope", "failed_closed"];
      const strongest = severityOrder[Math.max(severityOrder.indexOf(existing.severity), severityOrder.indexOf(item.severity))];
      merged = {
        ...existing,
        severity: strongest,
        status: item.status,
        summary: item.summary,
        affectedScopes: Array.from(new Set(existing.affectedScopes.concat(item.affectedScopes))).sort(),
        occurrences: Array.from(occurrences.values()).sort((left, right) => left.observedAt.localeCompare(right.observedAt)),
        defaultAction: item.defaultAction,
        reviewDeadline: item.reviewDeadline,
        updatedAt: item.updatedAt,
      };
      fileName = candidates[0].name;
    }
    assertSchemaInstance("arena-calibration.exception-inbox-item.v1", merged, "merged exception inbox item");
    writeJsonAtomic(path.join(artifactDir, fileName), merged);
    this.journal.append("exception_recorded", {
      exceptionId: merged.exceptionId,
      dedupeKey: merged.dedupeKey,
      severity: merged.severity,
      status: merged.status,
      occurrences: merged.occurrences.length,
      affectedScopes: merged.affectedScopes.length,
      evidenceHash: sha256OfValue(merged),
    });
    return merged;
  }

  pause(reason, options) {
    if (!this.journal.lease) this.acquire({ allowStaleRecovery: true });
    const receipt = this.journal.append("campaign_paused", {
      reason: reason || "operator_requested_process_boundary",
      targetYieldLatencySeconds: 60,
      maxYieldLatencySeconds: 300,
      resourcesReleased: options && options.resourcesReleased === true,
    });
    const closed = this.journal.closeSegment("campaign_pause");
    const snapshot = this.journal.snapshot();
    this.activeGrant = null;
    this.activeRegistry = null;
    this.release("campaign_pause");
    return { receipt, closed, snapshot };
  }

  snapshot() {
    return this.journal.snapshot();
  }
}

module.exports = {
  ATTENTION_SCHEMA,
  COMPATIBILITY_SCHEMA,
  CampaignSupervisor,
  EXECUTION_ARTIFACT_SCHEMA,
  createAttentionEvent,
  createCompatibilityReceipt,
  executionClosureIdentity,
  sha256File,
  validateResultRowsAgainstManifest,
};
