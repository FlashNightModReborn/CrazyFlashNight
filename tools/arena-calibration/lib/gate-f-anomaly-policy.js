"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { sha256OfValue } = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");

const CANDIDATE_ANOMALY_STATUSES = new Set([
  "contamination",
  "error",
  "invalid_case",
  "spawn_failed",
]);
const NON_FAILURE_STATUSES = new Set(["finished", "timeout"]);
const ALLOWED_RECOMMENDATIONS = Object.freeze([
  "confirm_quarantine",
  "likely_legitimate_spawn",
  "request_method_change",
  "abstain",
]);

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

function rowStatusCounts(rows) {
  return (rows || []).reduce((counts, row) => {
    const status = String(row && row.status || "unknown");
    counts[status] = (counts[status] || 0) + 1;
    return counts;
  }, {});
}

function errorSignals(rows) {
  const aggregated = new Map();
  (rows || []).forEach((row) => {
    (row && Array.isArray(row.errors) ? row.errors : []).forEach((entry) => {
      const code = String(entry && entry.code || "unknown_error");
      const name = entry && entry.name !== undefined ? String(entry.name) : null;
      const unit = entry && entry.unit !== undefined ? String(entry.unit) : null;
      const key = JSON.stringify([code, name, unit]);
      const previous = aggregated.get(key) || { code, name, unit, count: 0 };
      previous.count += 1;
      aggregated.set(key, previous);
    });
  });
  return Array.from(aggregated.values())
    .sort((left, right) => right.count - left.count
      || left.code.localeCompare(right.code)
      || String(left.name || "").localeCompare(String(right.name || "")))
    .slice(0, 32);
}

function candidateIdForCase(candidateIds, caseId) {
  const value = String(caseId || "");
  return candidateIds.find((candidateId) => value === candidateId || value.startsWith(`${candidateId}-`)) || null;
}

function affectedCandidateIds(manifest, rows, fallbackCandidateIds) {
  const candidateIds = Array.from(new Set(
    (manifest && manifest.planner && manifest.planner.candidateIds) || fallbackCandidateIds || [],
  )).sort();
  const affected = new Set();
  (rows || []).forEach((row) => {
    if (!CANDIDATE_ANOMALY_STATUSES.has(String(row && row.status || ""))) return;
    const candidateId = candidateIdForCase(candidateIds, row.caseId);
    if (candidateId) affected.add(candidateId);
  });
  return Array.from(affected).sort();
}

function classifyCandidateAnomaly(input) {
  const manifest = input.manifest || {};
  const rows = input.rows || [];
  const phase = String(manifest.planner && manifest.planner.phase || "");
  const statuses = rows.map((row) => String(row && row.status || "unknown"));
  const hasCandidateAnomaly = statuses.some((status) => CANDIDATE_ANOMALY_STATUSES.has(status));
  const statusesAreScoped = statuses.every((status) => NON_FAILURE_STATUSES.has(status)
    || CANDIDATE_ANOMALY_STATUSES.has(status));
  const candidates = affectedCandidateIds(manifest, rows, input.candidateIds);
  const infrastructureHealthy = input.saveUnchanged === true
    && input.runtimeVerified === true
    && input.diskOk === true
    && input.withinWallClock === true;
  const cardinalityClosed = rows.length >= Number(input.plannedRuns || 0);
  const eligible = ["standard", "long"].includes(phase)
    && infrastructureHealthy
    && cardinalityClosed
    && statusesAreScoped
    && hasCandidateAnomaly
    && candidates.length > 0;
  return {
    eligible,
    phase,
    affectedCandidateIds: candidates,
    rowStatusCounts: rowStatusCounts(rows),
    errorSignals: errorSignals(rows),
    infrastructureHealthy,
    cardinalityClosed,
    statusesAreScoped,
  };
}

function quarantinedCandidateIds(plan, latestReceipts) {
  const quarantined = new Set(
    (plan.candidateBaselines || [])
      .filter((entry) => entry.initialState === "quarantined")
      .map((entry) => entry.candidateId),
  );
  Array.from(latestReceipts.values()).forEach((receipt) => {
    if (receipt.state !== "quarantined") return;
    const shard = plan.shards.find((entry) => entry.shardId === receipt.shardId);
    const ids = Array.isArray(receipt.affectedCandidateIds) && receipt.affectedCandidateIds.length > 0
      ? receipt.affectedCandidateIds
      : (shard ? shard.candidateIds : []);
    ids.forEach((candidateId) => quarantined.add(candidateId));
  });
  return quarantined;
}

function selectRunnableShards(plan, latestReceipts, maximum) {
  const quarantined = quarantinedCandidateIds(plan, latestReceipts);
  const runnable = plan.shards.filter((shard) => {
    const latest = latestReceipts.get(shard.shardId);
    if (latest && ["completed", "quarantined"].includes(latest.state)) return false;
    return !shard.candidateIds.some((candidateId) => quarantined.has(candidateId));
  });
  return {
    runnable: runnable.slice(0, maximum),
    quarantinedCandidateIds: quarantined,
    quarantinedShardIds: new Set(plan.shards
      .filter((shard) => {
        const latest = latestReceipts.get(shard.shardId);
        if (latest && latest.state === "completed") return false;
        return (latest && latest.state === "quarantined")
          || shard.candidateIds.some((candidateId) => quarantined.has(candidateId));
      })
      .map((shard) => shard.shardId)),
  };
}

function createExceptionReviewRequest(input) {
  const receipt = input.receipt;
  if (!receipt || receipt.state !== "quarantined") {
    throw new Error("exception review request requires one quarantined Gate F receipt");
  }
  const request = {
    schema: "arena-calibration.exception-review-request.v1",
    requestId: `review-${receipt.receiptId}`,
    campaignId: receipt.campaignId,
    planHash: receipt.planHash,
    shardId: receipt.shardId,
    manifestHash: receipt.manifestHash,
    candidateIds: Array.from(new Set(input.candidateIds || receipt.affectedCandidateIds || [])).sort(),
    receiptHash: receipt.receiptHash,
    runReportPath: receipt.runReportPath,
    runReportSha256: receipt.runReportSha256,
    rowStatusCounts: { ...input.rowStatusCounts },
    errorSignals: (input.errorSignals || []).map((entry) => ({ ...entry })),
    reason: receipt.reason,
    policy: {
      defaultDisposition: "quarantine_candidate",
      campaignAction: "defer_and_continue",
      mayAcceptSample: false,
      mayResumeCandidate: false,
      allowedRecommendations: ALLOWED_RECOMMENDATIONS.slice(),
    },
    createdAt: input.createdAt || new Date().toISOString(),
    requestHash: "",
  };
  request.requestHash = sha256OfValue(withoutHash(request, "requestHash"));
  assertSchemaInstance(request.schema, request, "Gate F exception review request");
  return request;
}

function executableCandidates(explicitPath) {
  const candidates = [];
  [explicitPath, process.env.CF7_CODEX_EXE, process.env.CODEX_EXE]
    .filter(Boolean)
    .forEach((entry) => candidates.push(path.resolve(entry)));
  try {
    const located = childProcess.execFileSync("where.exe", ["codex.exe"], {
      encoding: "utf8",
      windowsHide: true,
      timeout: 5000,
    });
    String(located || "").split(/\r?\n/).map((entry) => entry.trim()).filter(Boolean)
      .forEach((entry) => candidates.push(path.resolve(entry)));
  } catch (_error) { }
  const userProfile = process.env.USERPROFILE;
  const extensionsRoot = userProfile && path.join(userProfile, ".vscode", "extensions");
  if (extensionsRoot && fs.existsSync(extensionsRoot)) {
    fs.readdirSync(extensionsRoot)
      .filter((name) => /^openai\.chatgpt-/i.test(name))
      .sort().reverse()
      .forEach((name) => candidates.push(path.join(
        extensionsRoot, name, "bin", "windows-x86_64", "codex.exe",
      )));
  }
  return Array.from(new Set(candidates));
}

function discoverCodexExecutable(explicitPath) {
  return executableCandidates(explicitPath).find((entry) => {
    try { return fs.statSync(entry).isFile(); } catch (_error) { return false; }
  }) || null;
}

module.exports = {
  ALLOWED_RECOMMENDATIONS,
  CANDIDATE_ANOMALY_STATUSES,
  affectedCandidateIds,
  classifyCandidateAnomaly,
  createExceptionReviewRequest,
  discoverCodexExecutable,
  errorSignals,
  quarantinedCandidateIds,
  rowStatusCounts,
  selectRunnableShards,
  sha256File,
  withoutHash,
};
