"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  normalizeManifest,
  readJsonFile,
  sha256OfValue,
} = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");
const { verifySoakAdmissionDocument } = require("./gate-f-soak-admission");
const {
  publicRuntimeIdentity,
  resolveExpectedRuntimeIdentity,
} = require("../../lib/runtime-process-identity");

const PLAN_SCHEMA = "arena-calibration.gate-f-plan.v1";
const WINDOW_SCHEMA = "arena-calibration.gate-f-idle-window.v1";
const DECISION_EVIDENCE_SCHEMA = "arena-calibration.gate-f-decision-evidence.v1";
const ATTENTION_MEASUREMENT_SCHEMA = "arena-calibration.attention-measurement.v1";
const SHARD_RECEIPT_SCHEMA = "arena-calibration.gate-f-shard-receipt.v1";
const STATUS_SCHEMA = "arena-calibration.gate-f-status.v1";
const EXCEPTION_SCHEMA = "arena-calibration.exception-inbox-item.v1";
const MAX_IDLE_WINDOW_MS = 24 * 60 * 60 * 1000;
const FAILURE_STATUSES = new Set([
  "error", "spawn_failed", "stage_failed", "bridge_lost", "invalid_case", "contamination",
]);

function fail(message, code, details) {
  const error = new Error(message);
  error.code = code || "gate_f_invalid";
  error.details = details || null;
  throw error;
}

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return `sha256:${hash.digest("hex")}`;
}

function resolveInsideRoot(projectRoot, candidate, label, mustExist = true) {
  const root = path.resolve(projectRoot);
  const resolved = path.resolve(root, candidate);
  const relative = path.relative(root, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    fail(`${label} is outside the project root: ${candidate}`, "path_outside_project");
  }
  if (mustExist && !fs.existsSync(resolved)) fail(`${label} does not exist: ${candidate}`, "path_missing");
  return resolved;
}

function projectRelative(projectRoot, filePath) {
  return path.relative(path.resolve(projectRoot), path.resolve(filePath)).replace(/\\/g, "/");
}

function runGit(projectRoot, args) {
  const result = childProcess.spawnSync("git", args, {
    cwd: projectRoot,
    encoding: "utf8",
    windowsHide: true,
  });
  if (result.status !== 0) fail(`git ${args.join(" ")} failed: ${(result.stderr || "").trim()}`, "git_failed");
  return String(result.stdout || "").trim();
}

function verifyManifestIntegrity(manifest, label) {
  assertSchemaInstance("arena-calibration.case-manifest.v1", manifest, label || "case manifest");
  const normalized = normalizeManifest(manifest);
  if (normalized.manifestHash !== manifest.manifestHash
      || normalized.cases.some((entry, index) => entry.caseHash !== manifest.cases[index].caseHash)) {
    fail(`${label || "case manifest"} hash does not match its canonical contents`, "manifest_integrity_mismatch");
  }
  return true;
}

function captureGitSourceIdentity(projectRoot) {
  const status = runGit(projectRoot, ["status", "--porcelain=v1", "--untracked-files=all"]);
  const identity = {
    commit: runGit(projectRoot, ["rev-parse", "HEAD"]),
    tree: runGit(projectRoot, ["rev-parse", "HEAD^{tree}"]),
    worktreeClean: status.length === 0,
    statusHash: sha256OfValue({ porcelainV1: status }),
  };
  if (!identity.worktreeClean) {
    fail("Gate F source freeze requires a clean worktree", "source_worktree_dirty", { statusHash: identity.statusHash });
  }
  return identity;
}

function compareRuntimeIdentity(expected, actual) {
  const fields = ["runtimeMode", "processPath", "coreSha256", "buildIdentity", "payloadClosure"];
  const mismatches = fields.filter((field) => String(expected[field]) !== String(actual[field]));
  if (mismatches.length > 0) {
    fail(`formal runtime identity drifted: ${mismatches.join(", ")}`, "runtime_identity_drift", { mismatches });
  }
}

function freezeRuntimeIdentity(identity) {
  return {
    runtimeMode: identity.runtimeMode,
    processPath: identity.processPath,
    coreSha256: identity.coreSha256,
    buildIdentity: identity.buildIdentity,
    payloadClosure: identity.payloadClosure,
    verified: true,
  };
}

function createGateFDecisionEvidence(input) {
  const evidence = {
    schema: DECISION_EVIDENCE_SCHEMA,
    decisionId: input.decisionId,
    planId: input.planId,
    campaignId: input.campaignId,
    shardId: input.shardId,
    action: "schedule_shard",
    riskLevel: "auto_execute",
    candidateIds: Array.from(new Set(input.candidateIds || [])).sort(),
    manifestPath: input.manifestPath,
    manifestHash: input.manifestHash,
    plannedRuns: input.plannedRuns,
    humanApprovalRequired: false,
    evidenceRefs: Array.from(new Set(input.evidenceRefs || [])).sort(),
    createdAt: input.createdAt,
    decisionHash: "",
  };
  evidence.decisionHash = sha256OfValue(withoutHash(evidence, "decisionHash"));
  assertSchemaInstance(DECISION_EVIDENCE_SCHEMA, evidence, "Gate F decision evidence");
  return evidence;
}

function verifyGateFDecisionEvidence(evidence, expected) {
  assertSchemaInstance(DECISION_EVIDENCE_SCHEMA, evidence, "Gate F decision evidence");
  if (evidence.decisionHash !== sha256OfValue(withoutHash(evidence, "decisionHash"))) {
    fail("Gate F decision evidence hash mismatch", "decision_evidence_hash_mismatch");
  }
  if (expected) {
    const candidateIds = Array.from(new Set(expected.candidateIds || [])).sort();
    if (evidence.planId !== expected.planId || evidence.campaignId !== expected.campaignId
        || evidence.shardId !== expected.shardId || evidence.manifestPath !== expected.manifestPath
        || evidence.manifestHash !== expected.manifestHash || evidence.plannedRuns !== expected.plannedRuns
        || JSON.stringify(evidence.candidateIds) !== JSON.stringify(candidateIds)) {
      fail("Gate F decision evidence is not bound to its shard", "decision_evidence_binding_mismatch");
    }
  }
  return true;
}

function freezeGateFPlan(projectRoot, draft, options) {
  options = options || {};
  const sourceIdentity = options.sourceIdentity || captureGitSourceIdentity(projectRoot);
  if (sourceIdentity.worktreeClean !== true) fail("Gate F source identity must be clean", "source_worktree_dirty");
  const observedRuntimeIdentity = options.runtimeIdentity
    || publicRuntimeIdentity(resolveExpectedRuntimeIdentity(projectRoot, null));
  if (draft.runtimeIdentity) compareRuntimeIdentity(draft.runtimeIdentity, observedRuntimeIdentity);
  const runtimeIdentity = freezeRuntimeIdentity(observedRuntimeIdentity);
  let soakAdmissionPath = null;
  let soakAdmissionRef = null;
  if (draft.soakAdmissionPath || draft.soakAdmissionRef) {
    if (!draft.soakAdmissionPath || !draft.soakAdmissionRef) {
      fail("Gate F soak admission path and reference must be supplied together", "soak_admission_binding_missing");
    }
    const admissionPath = resolveInsideRoot(projectRoot, draft.soakAdmissionPath, "Gate F soak admission");
    const admission = readJsonFile(admissionPath);
    const verifiedAdmission = verifySoakAdmissionDocument(projectRoot, admission, {
      planId: draft.planId,
      battleSemanticsCohortId: draft.battleSemanticsCohortId,
      runtimeIdentity,
      expectedRef: draft.soakAdmissionRef,
    });
    soakAdmissionPath = projectRelative(projectRoot, admissionPath);
    soakAdmissionRef = verifiedAdmission.documentRef;
  }
  const candidateIds = Array.from(new Set(draft.candidateIds || [])).sort();
  const candidateBaselines = (draft.candidateBaselines || []).map((entry) => ({ ...entry }))
    .sort((left, right) => left.candidateId.localeCompare(right.candidateId));
  const baselineIds = candidateBaselines.map((entry) => entry.candidateId);
  if (candidateIds.length !== baselineIds.length || candidateIds.some((entry, index) => entry !== baselineIds[index])) {
    fail("Gate F candidateIds must exactly match candidateBaselines", "candidate_baseline_mismatch");
  }
  const scheduledCandidates = new Set(candidateBaselines
    .filter((entry) => entry.initialState === "scheduled")
    .map((entry) => entry.candidateId));
  const shardIds = new Set();
  const shards = (draft.shards || []).map((entry) => {
    if (shardIds.has(entry.shardId)) fail(`duplicate Gate F shardId: ${entry.shardId}`, "duplicate_shard_id");
    shardIds.add(entry.shardId);
    const shardCandidateIds = Array.from(new Set(entry.candidateIds || [])).sort();
    if (shardCandidateIds.some((candidateId) => !scheduledCandidates.has(candidateId))) {
      fail(`Gate F shard ${entry.shardId} references a non-scheduled candidate`, "shard_candidate_invalid");
    }
    const manifestPath = resolveInsideRoot(projectRoot, entry.manifestPath, `Gate F manifest ${entry.shardId}`);
    const manifest = readJsonFile(manifestPath);
    verifyManifestIntegrity(manifest, `Gate F manifest ${entry.shardId}`);
    const plannedRuns = manifest.cases.reduce((sum, item) => sum + item.repeat, 0);
    if (entry.manifestHash && entry.manifestHash !== manifest.manifestHash) {
      fail(`Gate F manifest hash drifted for ${entry.shardId}`, "manifest_hash_drift");
    }
    if (entry.plannedRuns !== undefined && entry.plannedRuns !== plannedRuns) {
      fail(`Gate F plannedRuns drifted for ${entry.shardId}`, "manifest_run_count_drift");
    }
    let decisionEvidencePath = null;
    let decisionEvidenceRef = null;
    if (entry.eligibleEpoch === true) {
      decisionEvidencePath = resolveInsideRoot(projectRoot, entry.decisionEvidencePath, `Gate F decision evidence ${entry.shardId}`);
      const decisionEvidence = readJsonFile(decisionEvidencePath);
      verifyGateFDecisionEvidence(decisionEvidence, {
        planId: draft.planId,
        campaignId: draft.campaignId,
        shardId: entry.shardId,
        candidateIds: shardCandidateIds,
        manifestPath: projectRelative(projectRoot, manifestPath),
        manifestHash: manifest.manifestHash,
        plannedRuns,
      });
      if (entry.decisionEvidenceRef && entry.decisionEvidenceRef !== decisionEvidence.decisionHash) {
        fail(`Gate F decision evidence reference drifted for ${entry.shardId}`, "decision_evidence_ref_drift");
      }
      decisionEvidenceRef = decisionEvidence.decisionHash;
    }
    return {
      shardId: entry.shardId,
      candidateIds: shardCandidateIds,
      manifestPath: projectRelative(projectRoot, manifestPath),
      manifestHash: manifest.manifestHash,
      plannedRuns,
      maxRecoveryAttempts: entry.maxRecoveryAttempts === undefined ? 1 : entry.maxRecoveryAttempts,
      maxWallClockMinutes: entry.maxWallClockMinutes === undefined ? 40 : entry.maxWallClockMinutes,
      eligibleEpoch: entry.eligibleEpoch === true,
      decisionEvidencePath: decisionEvidencePath ? projectRelative(projectRoot, decisionEvidencePath) : null,
      decisionEvidenceRef,
    };
  });
  scheduledCandidates.forEach((candidateId) => {
    if (!shards.some((entry) => entry.candidateIds.includes(candidateId))) {
      fail(`scheduled Gate F candidate has no shard: ${candidateId}`, "scheduled_candidate_uncovered");
    }
  });
  const plan = {
    schema: PLAN_SCHEMA,
    planId: draft.planId,
    campaignId: draft.campaignId,
    battleSemanticsCohortId: draft.battleSemanticsCohortId,
    candidateIds,
    candidateBaselines,
    sourceIdentity,
    runtimeIdentity,
    ...(soakAdmissionPath ? { soakAdmissionPath, soakAdmissionRef } : {}),
    slot: draft.slot || "cf7_agent_arena_calibration",
    seedSlot: draft.seedSlot,
    healthPolicy: { ...draft.healthPolicy },
    attentionPolicy: { ...draft.attentionPolicy },
    shards,
    createdAt: draft.createdAt || new Date().toISOString(),
    planHash: "",
  };
  plan.planHash = sha256OfValue(withoutHash(plan, "planHash"));
  assertSchemaInstance(PLAN_SCHEMA, plan, "Gate F plan");
  return plan;
}

function verifyGateFPlan(projectRoot, plan, options) {
  options = options || {};
  assertSchemaInstance(PLAN_SCHEMA, plan, "Gate F plan");
  if (plan.planHash !== sha256OfValue(withoutHash(plan, "planHash"))) fail("Gate F plan hash mismatch", "plan_hash_mismatch");
  if (plan.soakAdmissionPath || plan.soakAdmissionRef) {
    const admissionPath = resolveInsideRoot(projectRoot, plan.soakAdmissionPath, "Gate F soak admission");
    verifySoakAdmissionDocument(projectRoot, readJsonFile(admissionPath), {
      planId: plan.planId,
      battleSemanticsCohortId: plan.battleSemanticsCohortId,
      runtimeIdentity: plan.runtimeIdentity,
      expectedRef: plan.soakAdmissionRef,
    });
  }
  plan.shards.forEach((entry) => {
    const manifestPath = resolveInsideRoot(projectRoot, entry.manifestPath, `Gate F manifest ${entry.shardId}`);
    const manifest = readJsonFile(manifestPath);
    verifyManifestIntegrity(manifest, `Gate F manifest ${entry.shardId}`);
    const plannedRuns = manifest.cases.reduce((sum, item) => sum + item.repeat, 0);
    if (manifest.manifestHash !== entry.manifestHash || plannedRuns !== entry.plannedRuns) {
      fail(`Gate F manifest changed after freeze: ${entry.shardId}`, "manifest_drift");
    }
    if (entry.eligibleEpoch) {
      const evidencePath = resolveInsideRoot(projectRoot, entry.decisionEvidencePath, `Gate F decision evidence ${entry.shardId}`);
      const evidence = readJsonFile(evidencePath);
      verifyGateFDecisionEvidence(evidence, {
        planId: plan.planId,
        campaignId: plan.campaignId,
        shardId: entry.shardId,
        candidateIds: entry.candidateIds,
        manifestPath: entry.manifestPath,
        manifestHash: entry.manifestHash,
        plannedRuns: entry.plannedRuns,
      });
      if (evidence.decisionHash !== entry.decisionEvidenceRef) {
        fail(`Gate F decision evidence changed after freeze: ${entry.shardId}`, "decision_evidence_drift");
      }
    }
  });
  if (!options.skipSource) {
    const currentSource = captureGitSourceIdentity(projectRoot);
    if (currentSource.commit !== plan.sourceIdentity.commit || currentSource.tree !== plan.sourceIdentity.tree
        || currentSource.statusHash !== plan.sourceIdentity.statusHash) {
      fail("Gate F source identity changed after freeze", "source_identity_drift");
    }
  }
  if (!options.skipRuntime) {
    const currentRuntime = publicRuntimeIdentity(resolveExpectedRuntimeIdentity(projectRoot, null));
    compareRuntimeIdentity(plan.runtimeIdentity, currentRuntime);
  }
  return true;
}

function createIdleWindow(projectRoot, plan, options) {
  options = options || {};
  verifyGateFPlan(projectRoot, plan, options.verifyOptions);
  const issuedAt = options.issuedAt || new Date().toISOString();
  const durationMs = options.durationMs === undefined ? 8 * 60 * 60 * 1000 : options.durationMs;
  if (!Number.isInteger(durationMs) || durationMs < 60 * 1000 || durationMs > MAX_IDLE_WINDOW_MS) {
    fail("Gate F idle window duration must be 1 minute..24 hours", "idle_window_duration_invalid");
  }
  const windowId = options.windowId || `idle-${plan.planId}-${issuedAt.replace(/[^0-9]/g, "").slice(0, 14)}`;
  const revokePath = resolveInsideRoot(
    projectRoot,
    options.revokeFile || path.join("tmp", "arena-calibration", "gate-f", plan.planId, `${windowId}.revoke.signal`),
    "Gate F revoke file",
    false
  );
  const window = {
    schema: WINDOW_SCHEMA,
    windowId,
    campaignId: plan.campaignId,
    planHash: plan.planHash,
    sourceTree: plan.sourceIdentity.tree,
    issuedAt,
    expiresAt: new Date(Date.parse(issuedAt) + durationMs).toISOString(),
    revokeFile: projectRelative(projectRoot, revokePath),
    windowHash: "",
  };
  window.windowHash = sha256OfValue(withoutHash(window, "windowHash"));
  assertSchemaInstance(WINDOW_SCHEMA, window, "Gate F idle window");
  return window;
}

function verifyIdleWindow(projectRoot, plan, window, options) {
  options = options || {};
  assertSchemaInstance(WINDOW_SCHEMA, window, "Gate F idle window");
  if (window.windowHash !== sha256OfValue(withoutHash(window, "windowHash"))) fail("Gate F idle window hash mismatch", "idle_window_hash_mismatch");
  if (window.campaignId !== plan.campaignId || window.planHash !== plan.planHash || window.sourceTree !== plan.sourceIdentity.tree) {
    fail("Gate F idle window is not bound to the frozen plan", "idle_window_plan_mismatch");
  }
  const nowMs = Date.parse(options.now || new Date().toISOString());
  const issuedMs = Date.parse(window.issuedAt);
  const expiresMs = Date.parse(window.expiresAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(issuedMs) || !Number.isFinite(expiresMs)
      || expiresMs <= issuedMs || expiresMs - issuedMs > MAX_IDLE_WINDOW_MS) {
    fail("Gate F idle window time range is invalid", "idle_window_time_invalid");
  }
  if (nowMs < issuedMs - 5000 || nowMs >= expiresMs) fail("Gate F idle window is not active", "idle_window_inactive");
  const revokePath = resolveInsideRoot(projectRoot, window.revokeFile, "Gate F revoke file", false);
  if (fs.existsSync(revokePath)) fail("Gate F idle window was revoked", "idle_window_revoked", { revokeFile: window.revokeFile });
  return true;
}

function captureDiskHealth(projectRoot, minimumFreeBytes, options) {
  options = options || {};
  let freeBytes;
  if (options.freeBytes !== undefined) {
    freeBytes = Number(options.freeBytes);
  } else if (typeof fs.statfsSync === "function") {
    const stats = fs.statfsSync(projectRoot, { bigint: true });
    freeBytes = Number(stats.bavail * stats.bsize);
  } else {
    fail("Node runtime does not expose statfsSync", "disk_probe_unavailable");
  }
  if (!Number.isSafeInteger(freeBytes) || freeBytes < 0) fail("disk free-space probe returned an invalid value", "disk_probe_invalid");
  return {
    freeBytes,
    minimumFreeBytes,
    ok: freeBytes >= minimumFreeBytes,
    checkedAt: options.checkedAt || new Date().toISOString(),
  };
}

function listWindowsProcesses() {
  if (process.platform !== "win32") return [];
  const command = "$p=Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine; @($p) | ConvertTo-Json -Depth 3 -Compress";
  const result = childProcess.spawnSync("powershell.exe", ["-NoProfile", "-Command", command], {
    encoding: "utf8",
    windowsHide: true,
    maxBuffer: 8 * 1024 * 1024,
  });
  if (result.status !== 0) fail(`process observation failed: ${(result.stderr || "").trim()}`, "process_probe_failed");
  const parsed = JSON.parse(String(result.stdout || "[]").trim() || "[]");
  return Array.isArray(parsed) ? parsed : [parsed];
}

function collectControlProcessIds(processes, rootProcessIds) {
  const parentByPid = new Map();
  processes.forEach((entry) => {
    const pid = Number(entry.ProcessId);
    const parentPid = Number(entry.ParentProcessId);
    if (Number.isInteger(pid) && pid > 0) parentByPid.set(pid, parentPid);
  });
  const excluded = new Set();
  (rootProcessIds || []).forEach((value) => {
    let pid = Number(value);
    while (Number.isInteger(pid) && pid > 0 && !excluded.has(pid)) {
      excluded.add(pid);
      pid = parentByPid.get(pid);
    }
  });
  return excluded;
}

function createProducerObservations(projectRoot, plan, window, options) {
  options = options || {};
  verifyIdleWindow(projectRoot, plan, window, { now: options.observedAt });
  const observedAt = options.observedAt || new Date().toISOString();
  const processes = options.processes || listWindowsProcesses();
  const controlProcessIds = collectControlProcessIds(processes, [
    options.currentProcessId === undefined ? process.pid : options.currentProcessId,
  ]);
  const active = {
    launcher: processes.filter((entry) => /^(?:CRAZYFLASHER7MercenaryEmpire(?:\.Core)?|CrazyFlasher7StandAloneStarter)\.exe$/i.test(String(entry.Name || ""))),
    flash: processes.filter((entry) => /^(Flash|FlashPlayer.*|flashplayer.*)\.exe$/i.test(String(entry.Name || ""))),
    arena_runner: processes.filter((entry) => !controlProcessIds.has(Number(entry.ProcessId))
      && /(?:run-unattended|gate-fctl)\.js/i.test(String(entry.CommandLine || ""))),
  };
  const descriptions = [
    ["gate-f-launcher-observer", "launcher", active.launcher],
    ["gate-f-flash-observer", "flash", active.flash],
    ["gate-f-arena-runner-observer", "arena_runner", active.arena_runner],
    ["gate-f-content-window", "content_development", []],
  ];
  return descriptions.map(([producerId, scope, matches]) => {
    const evidence = {
      producerId,
      scope,
      observedAt,
      activeProcesses: matches.map((entry) => ({ pid: Number(entry.ProcessId), name: entry.Name, path: entry.ExecutablePath || null })),
      idleWindowHash: window.windowHash,
      sourceTree: plan.sourceIdentity.tree,
    };
    return {
      producerId,
      scope,
      online: true,
      leaseState: matches.length === 0 ? "idle" : "active",
      observedAt,
      evidenceRef: sha256OfValue(evidence),
    };
  });
}

function createAttentionMeasurement(input) {
  const ops = input.opsBreakdown;
  if (!ops) fail("attention measurement requires opsBreakdown", "attention_measurement_missing");
  const sum = Number(ops.startup) + Number(ops.recovery) + Number(ops.exception) + Number(ops.closeout);
  if (![ops.startup, ops.recovery, ops.exception, ops.closeout, ops.total].every(Number.isFinite)
      || Math.abs(sum - Number(ops.total)) > 1e-9) {
    fail("attention opsBreakdown.total must equal its four buckets", "attention_ops_total_mismatch");
  }
  if (input.manualEditDelta > input.humanTouchDelta || input.humanTouchDelta > input.eligibleEpochDelta) {
    fail("attention proposal deltas are inconsistent", "attention_delta_invalid");
  }
  if (input.shardKind === "unattended" && (input.shardHumanActionCount !== 0
      || input.humanBlockedMinutes !== 0 || input.automationEvidence.operatorSignalCount !== 0)) {
    fail("unattended shard attention must report zero human actions, blocks, and operator signals", "unattended_attention_nonzero");
  }
  const startedMs = Date.parse(input.shardStartedAt);
  const finishedMs = Date.parse(input.shardFinishedAt);
  const declaredMs = Date.parse(input.shardKindDeclaredAt);
  if (![startedMs, finishedMs, declaredMs].every(Number.isFinite)
      || declaredMs > startedMs || finishedMs < startedMs) {
    fail("attention shard timestamps are invalid", "attention_time_invalid");
  }
  const measurement = {
    schema: ATTENTION_MEASUREMENT_SCHEMA,
    measurementId: input.measurementId,
    campaignId: input.campaignId,
    shardId: input.shardId,
    shardKind: input.shardKind,
    shardKindDeclaredAt: input.shardKindDeclaredAt,
    shardStartedAt: input.shardStartedAt,
    shardFinishedAt: input.shardFinishedAt,
    automationEvidence: { ...input.automationEvidence },
    shardHumanActionCount: input.shardHumanActionCount,
    opsBreakdown: { ...ops },
    humanBlockedMinutes: input.humanBlockedMinutes,
    interruptCount: input.interruptCount,
    eligibleEpochDelta: input.eligibleEpochDelta,
    humanTouchDelta: input.humanTouchDelta,
    manualEditDelta: input.manualEditDelta,
    exceptionCounts: { ...input.exceptionCounts },
    evidenceRefs: Array.from(new Set(input.evidenceRefs || [])).sort(),
    createdAt: input.createdAt,
    measurementHash: "",
  };
  measurement.measurementHash = sha256OfValue(withoutHash(measurement, "measurementHash"));
  assertSchemaInstance(ATTENTION_MEASUREMENT_SCHEMA, measurement, "attention measurement");
  return measurement;
}

function verifyAttentionMeasurement(measurement, expected) {
  assertSchemaInstance(ATTENTION_MEASUREMENT_SCHEMA, measurement, "attention measurement");
  if (measurement.measurementHash !== sha256OfValue(withoutHash(measurement, "measurementHash"))) {
    fail("attention measurement hash mismatch", "attention_measurement_hash_mismatch");
  }
  if (expected && (measurement.campaignId !== expected.campaignId || measurement.shardId !== expected.shardId
      || measurement.shardKind !== expected.shardKind)) {
    fail("attention measurement is not bound to the imported shard", "attention_measurement_binding_mismatch");
  }
  const ops = measurement.opsBreakdown;
  const sum = ops.startup + ops.recovery + ops.exception + ops.closeout;
  if (Math.abs(sum - ops.total) > 1e-9) fail("attention ops total drifted", "attention_ops_total_mismatch");
  if (measurement.manualEditDelta > measurement.humanTouchDelta
      || measurement.humanTouchDelta > measurement.eligibleEpochDelta) {
    fail("attention proposal deltas drifted", "attention_delta_invalid");
  }
  if (measurement.shardKind === "unattended" && (measurement.shardHumanActionCount !== 0
      || measurement.humanBlockedMinutes !== 0 || measurement.automationEvidence.operatorSignalCount !== 0)) {
    fail("unattended shard attention is not zero-touch", "unattended_attention_nonzero");
  }
  const startedMs = Date.parse(measurement.shardStartedAt);
  const finishedMs = Date.parse(measurement.shardFinishedAt);
  const declaredMs = Date.parse(measurement.shardKindDeclaredAt);
  if (![startedMs, finishedMs, declaredMs].every(Number.isFinite)
      || declaredMs > startedMs || finishedMs < startedMs) {
    fail("attention shard timestamps drifted", "attention_time_invalid");
  }
  return true;
}

function aggregateAttention(measurements, policy, now) {
  const verified = measurements.map((entry) => {
    verifyAttentionMeasurement(entry);
    return entry;
  }).sort((left, right) => left.createdAt.localeCompare(right.createdAt));
  const measurementIds = new Set();
  verified.forEach((entry) => {
    if (measurementIds.has(entry.measurementId)) fail(`duplicate attention measurementId: ${entry.measurementId}`, "attention_measurement_duplicate");
    measurementIds.add(entry.measurementId);
  });
  const eligible = verified.filter((entry) => entry.eligibleEpochDelta === 1);
  const rolling = eligible.slice(-20);
  const sum = (items, field) => items.reduce((total, entry) => total + Number(entry[field] || 0), 0);
  const rollingHumanTouches = sum(rolling, "humanTouchDelta");
  const rollingManualEdits = sum(rolling, "manualEditDelta");
  const campaignHumanTouches = sum(eligible, "humanTouchDelta");
  const campaignManualEdits = sum(eligible, "manualEditDelta");
  const touchRate = rolling.length >= policy.minimumEligibleEpochs ? rollingHumanTouches / rolling.length : null;
  const manualEditRate = rolling.length >= policy.minimumEligibleEpochs ? rollingManualEdits / rolling.length : null;
  const campaignTouchRate = eligible.length >= policy.minimumEligibleEpochs ? campaignHumanTouches / eligible.length : null;
  const campaignManualEditRate = eligible.length >= policy.minimumEligibleEpochs ? campaignManualEdits / eligible.length : null;
  const nowMs = Date.parse(now || new Date().toISOString());
  const last24Hours = verified.filter((entry) => {
    const ageMs = nowMs - Date.parse(entry.createdAt);
    return ageMs >= 0 && ageMs <= 24 * 60 * 60 * 1000;
  });
  const opsLast24Hours = last24Hours.reduce((total, entry) => total + entry.opsBreakdown.total, 0);
  const perShardOpsWithinBudget = verified.every((entry) => entry.opsBreakdown.startup <= policy.maximumStartupMinutes
    && entry.opsBreakdown.closeout <= policy.maximumCloseoutMinutes);
  return {
    measurementCount: verified.length,
    eligibleEpochs: eligible.length,
    rollingEligibleEpochs: rolling.length,
    rollingHumanTouches,
    rollingManualEdits,
    rollingTouchRate: touchRate,
    rollingManualEditRate: manualEditRate,
    campaignHumanTouches,
    campaignManualEdits,
    campaignTouchRate,
    campaignManualEditRate,
    manualEdits: campaignManualEdits,
    shardHumanActionCount: sum(verified, "shardHumanActionCount"),
    humanBlockedMinutes: sum(verified, "humanBlockedMinutes"),
    interruptCount: sum(verified, "interruptCount"),
    opsActiveMinutesLast24Hours: opsLast24Hours,
    perShardOpsWithinBudget,
    status: rolling.length < policy.minimumEligibleEpochs || eligible.length < policy.minimumEligibleEpochs
      ? "insufficient_data"
      : (touchRate <= policy.maximumTouchRate && campaignTouchRate <= policy.maximumTouchRate
        && manualEditRate <= policy.maximumTouchRate && campaignManualEditRate <= policy.maximumTouchRate
        && opsLast24Hours <= policy.maximumOpsMinutesPer24Hours && perShardOpsWithinBudget
        ? "within_threshold" : "exceeds_threshold"),
  };
}

function evaluateShardHealth(rows, policy, baselineMedianDurationMs) {
  const total = rows.length;
  const errors = rows.filter((row) => FAILURE_STATUSES.has(row.status)).length;
  const timeouts = rows.filter((row) => row.status === "timeout").length;
  const durations = rows.map((row) => row.durationMs).filter((value) => Number.isFinite(value) && value >= 0).sort((a, b) => a - b);
  const medianDurationMs = durations.length === 0 ? null : durations[Math.floor(durations.length / 2)];
  const durationDriftRatio = medianDurationMs !== null && Number.isFinite(baselineMedianDurationMs) && baselineMedianDurationMs > 0
    ? medianDurationMs / baselineMedianDurationMs : null;
  const errorRate = total === 0 ? 1 : errors / total;
  const timeoutRate = total === 0 ? 1 : timeouts / total;
  const reasons = [];
  if (errorRate > policy.maximumErrorRate) reasons.push("error_rate");
  if (timeoutRate > policy.maximumTimeoutRate) reasons.push("timeout_rate");
  if (durationDriftRatio !== null && durationDriftRatio > policy.maximumDurationDriftRatio) reasons.push("duration_drift");
  return { total, errors, timeouts, errorRate, timeoutRate, medianDurationMs, durationDriftRatio, ok: reasons.length === 0, reasons };
}

function resultRunKey(manifestHash, row) {
  return `${manifestHash}|${row.runId}`;
}

function createExceptionInboxItem(input) {
  const createdAt = input.createdAt || new Date().toISOString();
  const item = {
    schema: EXCEPTION_SCHEMA,
    exceptionId: input.exceptionId,
    campaignId: input.campaignId,
    dedupeKey: input.dedupeKey,
    category: input.category,
    severity: input.severity,
    status: input.status || "deferred",
    summary: input.summary,
    affectedScopes: Array.from(new Set(input.affectedScopes)).sort(),
    occurrences: input.occurrences.map((entry) => ({ ...entry })),
    defaultAction: input.defaultAction,
    reviewDeadline: input.reviewDeadline,
    createdAt,
    updatedAt: input.updatedAt || createdAt,
  };
  assertSchemaInstance(EXCEPTION_SCHEMA, item, "Gate F exception inbox item");
  return item;
}

function createGateFStatus(input) {
  const status = {
    schema: STATUS_SCHEMA,
    planId: input.plan.planId,
    planHash: input.plan.planHash,
    campaignId: input.plan.campaignId,
    state: input.state,
    shards: { ...input.shards },
    rows: { ...input.rows },
    attention: { ...input.attention },
    exceptions: { ...input.exceptions },
    health: { ...input.health },
    createdAt: input.createdAt || new Date().toISOString(),
    statusHash: "",
  };
  status.statusHash = sha256OfValue(withoutHash(status, "statusHash"));
  assertSchemaInstance(STATUS_SCHEMA, status, "Gate F status");
  return status;
}

function createGateFShardReceipt(input) {
  const receipt = {
    schema: SHARD_RECEIPT_SCHEMA,
    receiptId: input.receiptId,
    planHash: input.planHash,
    campaignId: input.campaignId,
    shardId: input.shardId,
    manifestHash: input.manifestHash,
    state: input.state,
    runReportPath: input.runReportPath || null,
    runReportSha256: input.runReportSha256 || null,
    executionArtifactIds: Array.from(new Set(input.executionArtifactIds || [])).sort(),
    committedRows: input.committedRows || 0,
    duplicatesExcluded: input.duplicatesExcluded || 0,
    recoveryAttemptsUsed: input.recoveryAttemptsUsed || 0,
    health: { ...input.health },
    startedAt: input.startedAt,
    finishedAt: input.finishedAt,
    wallClockMinutes: input.wallClockMinutes,
    yieldLatencySeconds: input.yieldLatencySeconds === undefined ? null : input.yieldLatencySeconds,
    reason: input.reason || null,
    receiptHash: "",
  };
  receipt.receiptHash = sha256OfValue(withoutHash(receipt, "receiptHash"));
  assertSchemaInstance(SHARD_RECEIPT_SCHEMA, receipt, "Gate F shard receipt");
  return receipt;
}

module.exports = {
  ATTENTION_MEASUREMENT_SCHEMA,
  DECISION_EVIDENCE_SCHEMA,
  MAX_IDLE_WINDOW_MS,
  PLAN_SCHEMA,
  SHARD_RECEIPT_SCHEMA,
  STATUS_SCHEMA,
  WINDOW_SCHEMA,
  aggregateAttention,
  captureDiskHealth,
  captureGitSourceIdentity,
  collectControlProcessIds,
  compareRuntimeIdentity,
  createAttentionMeasurement,
  createGateFDecisionEvidence,
  createExceptionInboxItem,
  createGateFStatus,
  createGateFShardReceipt,
  createIdleWindow,
  createProducerObservations,
  evaluateShardHealth,
  freezeGateFPlan,
  listWindowsProcesses,
  projectRelative,
  resolveInsideRoot,
  resultRunKey,
  sha256File,
  verifyAttentionMeasurement,
  verifyGateFDecisionEvidence,
  verifyGateFPlan,
  verifyIdleWindow,
  verifyManifestIntegrity,
  withoutHash,
};
