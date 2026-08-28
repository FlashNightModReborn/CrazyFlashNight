"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  normalizeManifest,
  readJsonFile,
  readJsonLines,
  sha256OfValue,
} = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");

const SOAK_ADMISSION_SCHEMA = "arena-calibration.soak-admission.v1";
const RUNTIME_FIELDS = Object.freeze([
  "runtimeMode",
  "processPath",
  "coreSha256",
  "buildIdentity",
  "payloadClosure",
  "verified",
]);

function fail(message) {
  throw new Error(message);
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

function resolveInsideRoot(projectRoot, candidate, label) {
  const root = path.resolve(projectRoot);
  const resolved = path.resolve(root, candidate);
  const relative = path.relative(root, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    fail(`${label} is outside the project root: ${candidate}`);
  }
  if (!fs.existsSync(resolved)) fail(`${label} does not exist: ${candidate}`);
  return resolved;
}

function compareRuntimeIdentity(expected, actual, label) {
  const mismatches = RUNTIME_FIELDS.filter((field) => String(expected && expected[field]) !== String(actual && actual[field]));
  if (mismatches.length > 0) fail(`${label || "soak admission runtime"} identity mismatch: ${mismatches.join(", ")}`);
}

function verifyManifestIntegrity(manifest, label) {
  assertSchemaInstance("arena-calibration.case-manifest.v1", manifest, label);
  const normalized = normalizeManifest(manifest);
  if (normalized.manifestHash !== manifest.manifestHash
      || normalized.cases.some((entry, index) => entry.caseHash !== manifest.cases[index].caseHash)) {
    fail(`${label} canonical hash mismatch`);
  }
}

function verifyEvidenceRun(projectRoot, evidenceRun, runtimeIdentity, candidatesById) {
  const manifestPath = resolveInsideRoot(projectRoot, evidenceRun.manifestPath, `${evidenceRun.evidenceRunId} manifest`);
  const resultPath = resolveInsideRoot(projectRoot, evidenceRun.resultPath, `${evidenceRun.evidenceRunId} result`);
  const reportPath = resolveInsideRoot(projectRoot, evidenceRun.reportPath, `${evidenceRun.evidenceRunId} report`);
  if (sha256File(manifestPath) !== evidenceRun.manifestFileSha256
      || sha256File(resultPath) !== evidenceRun.resultFileSha256
      || sha256File(reportPath) !== evidenceRun.reportFileSha256) {
    fail(`${evidenceRun.evidenceRunId} raw evidence file hash mismatch`);
  }

  const manifest = readJsonFile(manifestPath);
  verifyManifestIntegrity(manifest, `${evidenceRun.evidenceRunId} manifest`);
  if (manifest.manifestHash !== evidenceRun.manifestHash
      || !manifest.planner || manifest.planner.phase !== "soak") {
    fail(`${evidenceRun.evidenceRunId} is not bound to the declared soak manifest`);
  }

  const report = readJsonFile(reportPath);
  const rows = readJsonLines(resultPath);
  if (report.status !== "completed" || report.batchId !== manifest.batchId
      || report.manifestHash !== manifest.manifestHash || report.resultPath !== evidenceRun.resultPath
      || report.rows !== rows.length || report.expectedRows !== rows.length
      || !report.summaryTotals || report.summaryTotals.rows !== rows.length
      || report.summaryTotals.errors !== 0 || report.summaryTotals.timeouts !== 0
      || (report.failures || []).length !== 0 || report.recoveryAttemptsUsed !== 0
      || !report.saveProtection || report.saveProtection.unchanged !== true
      || report.saveProtection.before.snapshotHash !== report.saveProtection.after.snapshotHash
      || (report.saveProtection.differences || []).length !== 0
      || !report.postRunShutdown || report.postRunShutdown.stopped !== true) {
    fail(`${evidenceRun.evidenceRunId} report is not a clean, completed, save-isolated soak`);
  }
  compareRuntimeIdentity(runtimeIdentity, report.runtimeIdentity, `${evidenceRun.evidenceRunId} report runtime`);

  const casesById = new Map(manifest.cases.map((entry) => [entry.caseId, entry]));
  if (casesById.size !== manifest.cases.length
      || rows.length !== manifest.cases.reduce((total, entry) => total + entry.repeat, 0)) {
    fail(`${evidenceRun.evidenceRunId} manifest/result cardinality mismatch`);
  }
  const rowsByCase = new Map();
  rows.forEach((row) => {
    assertSchemaInstance("arena-calibration.result.v1", row, `${evidenceRun.evidenceRunId} result row`);
    const manifestCase = casesById.get(row.caseId);
    if (!manifestCase || row.batchId !== manifest.batchId || row.manifestHash !== manifest.manifestHash
        || row.caseHash !== manifestCase.caseHash || row.status !== "finished" || row.winner === "timeout"
        || (row.errors || []).length !== 0) {
      fail(`${evidenceRun.evidenceRunId} contains a non-finished or unbound result row: ${row.runId}`);
    }
    const values = rowsByCase.get(row.caseId) || [];
    values.push(row);
    rowsByCase.set(row.caseId, values);
  });

  const admitted = [];
  const manifestCandidateIds = Array.from(new Set(manifest.planner.candidateIds || []));
  manifestCandidateIds.forEach((candidateId) => {
    const candidate = candidatesById.get(candidateId);
    if (!candidate) fail(`${evidenceRun.evidenceRunId} references an absent normalized candidate: ${candidateId}`);
    const original = casesById.get(candidateId);
    const swapped = casesById.get(`${candidateId}-side-swap`);
    if (!original || !swapped || original.repeat < 1 || swapped.repeat < 1
        || original.timeoutFrames !== candidate.caseTemplate.timeoutFrames
        || swapped.timeoutFrames !== candidate.caseTemplate.timeoutFrames
        || !swapped.tags.includes("side-swap") || original.tags.includes("side-swap")
        || (rowsByCase.get(original.caseId) || []).length !== original.repeat
        || (rowsByCase.get(swapped.caseId) || []).length !== swapped.repeat) {
      fail(`${evidenceRun.evidenceRunId} lacks exact-policy finished evidence for both orientations of ${candidateId}`);
    }
    admitted.push(candidateId);
  });
  return admitted;
}

function verifyCoverage(groupCandidates, soakIndex) {
  const riskTags = new Set(groupCandidates.flatMap((candidate) => candidate.riskTags || []));
  const hasOrdinary = groupCandidates.some((candidate) => (candidate.riskTags || []).length === 0
    && candidate.caseTemplate.timeoutFrames < 5400);
  const missing = [];
  if (!hasOrdinary) missing.push("ordinary_parameters");
  ["unit_payload", "formation", "long_timeout", "high_level"].forEach((tag) => {
    if (!riskTags.has(tag)) missing.push(tag);
  });
  if (missing.length > 0) fail(`soak group ${soakIndex} lacks required representative coverage: ${missing.join(", ")}`);
}

function verifySoakAdmissionDocument(projectRoot, document, options) {
  options = options || {};
  assertSchemaInstance(SOAK_ADMISSION_SCHEMA, document, "Gate F soak admission");
  const documentRef = sha256OfValue(withoutHash(document, "admissionHash"));
  if (document.admissionHash !== documentRef) fail("Gate F soak admission hash mismatch");
  if (options.expectedRef && options.expectedRef !== documentRef) fail("Gate F soak admission reference drifted");
  if (options.planId && document.planId !== options.planId) fail(`Gate F soak admission planId mismatch: ${document.planId}`);
  if (options.battleSemanticsCohortId
      && document.battleSemanticsCohortId !== options.battleSemanticsCohortId) {
    fail(`Gate F soak admission cohort mismatch: ${document.battleSemanticsCohortId}`);
  }
  if (options.runtimeIdentity) compareRuntimeIdentity(options.runtimeIdentity, document.runtimeIdentity, "Gate F soak admission runtime");

  const groupIndexes = document.groups.map((group) => group.soakIndex).sort((left, right) => left - right);
  if (groupIndexes.join(",") !== "1,2,3") fail("Gate F soak admission must declare soak indexes 1,2,3 exactly once");

  if (options.verifyRawEvidence !== true) {
    return { documentRef, groups: document.groups.map((group) => group.cells.slice()), runtimeIdentity: document.runtimeIdentity };
  }
  const candidates = options.candidates || [];
  const candidatesById = new Map(candidates.map((candidate) => [candidate.candidateId, candidate]));
  const candidatesByCell = new Map(candidates.map((candidate) => [candidate.source && candidate.source.cell, candidate]));
  if (candidatesById.size !== candidates.length || candidatesByCell.size !== candidates.length) {
    fail("Gate F soak admission candidate intake contains duplicate identities or cells");
  }
  const admittedCandidateIds = new Set();
  const evidenceRunIds = new Set();
  document.evidenceRuns.forEach((evidenceRun) => {
    if (evidenceRunIds.has(evidenceRun.evidenceRunId)) fail(`duplicate soak evidence run: ${evidenceRun.evidenceRunId}`);
    evidenceRunIds.add(evidenceRun.evidenceRunId);
    verifyEvidenceRun(projectRoot, evidenceRun, document.runtimeIdentity, candidatesById)
      .forEach((candidateId) => admittedCandidateIds.add(candidateId));
  });
  document.groups.forEach((group) => {
    const groupCandidates = group.cells.map((cell) => {
      const candidate = candidatesByCell.get(cell);
      if (!candidate) fail(`soak group ${group.soakIndex} references an absent source cell: ${cell}`);
      if (!admittedCandidateIds.has(candidate.candidateId)) {
        fail(`soak group ${group.soakIndex} lacks same-runtime, exact-policy evidence for ${cell}`);
      }
      return candidate;
    });
    verifyCoverage(groupCandidates, group.soakIndex);
  });
  return {
    documentRef,
    groups: document.groups.slice().sort((left, right) => left.soakIndex - right.soakIndex).map((group) => group.cells.slice()),
    runtimeIdentity: document.runtimeIdentity,
    admittedCandidateIds: Array.from(admittedCandidateIds).sort(),
  };
}

module.exports = {
  SOAK_ADMISSION_SCHEMA,
  compareRuntimeIdentity,
  verifySoakAdmissionDocument,
  withoutHash,
};
