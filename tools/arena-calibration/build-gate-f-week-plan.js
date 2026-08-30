#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const {
  normalizeManifest,
  readJsonFile,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const { assertSchemaInstance } = require("./lib/schema-registry");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");
const { createGateFDecisionEvidence, verifyManifestIntegrity } = require("./lib/gate-f-campaign");
const {
  verifyDerivedFactionCoverage,
  verifySoakAdmissionDocument,
  withoutHash,
} = require("./lib/gate-f-soak-admission");

const ROOT = path.resolve(__dirname, "../..");
const LONG_TIMEOUT_FRAMES = 5400;
const NORMAL_PHASE_RUNS = Object.freeze([10, 20, 25]);
const LONG_PHASE_RUNS = Object.freeze([10, 10, 10, 10, 10, 10]);

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const directCheck = argv[0] === "--check";
  const args = {
    candidates: null,
    exceptions: null,
    empiricalTimeoutOverrides: null,
    soakAdmission: null,
    outputDir: null,
    completed: [],
    planId: "gate-f-week-full-v1",
    campaignId: "gate-f-week-full-v1",
    battleSemanticsCohortId: "arena-cohort-20260827-stage-outcome-v2",
    battleBuildCommit: null,
    createdAt: null,
    updateExisting: false,
    rebindRuntimeSource: false,
    check: directCheck,
  };
  for (let index = directCheck ? 1 : 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--candidates") args.candidates = argv[++index];
    else if (token === "--exceptions") args.exceptions = argv[++index];
    else if (token === "--empirical-timeout-overrides") args.empiricalTimeoutOverrides = argv[++index];
    else if (token === "--soak-admission") args.soakAdmission = argv[++index];
    else if (token === "--output-dir") args.outputDir = argv[++index];
    else if (token === "--completed") args.completed.push(argv[++index]);
    else if (token === "--plan-id") args.planId = argv[++index];
    else if (token === "--campaign-id") args.campaignId = argv[++index];
    else if (token === "--battle-semantics-cohort") args.battleSemanticsCohortId = argv[++index];
    else if (token === "--battle-build-commit") args.battleBuildCommit = argv[++index];
    else if (token === "--created-at") args.createdAt = argv[++index];
    else if (token === "--update-existing") args.updateExisting = true;
    else if (token === "--rebind-runtime-source") args.rebindRuntimeSource = true;
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail(`unknown argument: ${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/build-gate-f-week-plan.js [options]

  --candidates <normalized-candidates.json>
  --exceptions <exceptions.json>
  [--empirical-timeout-overrides <evidence-bound overrides.json>]
  --soak-admission <same-runtime stable-soak-admission.json>
  --completed <candidateId=sha256:...>   Repeat for prior completed candidates.
  --output-dir <new project-relative directory>
  [--plan-id <id>] [--campaign-id <id>] [--battle-semantics-cohort <id>]
  [--battle-build-commit <40-hex release source>]
  [--created-at <ISO-8601>]
  [--update-existing]                     Verify matching manifests before adding derived evidence.
  [--rebind-runtime-source]               With --update-existing, replace a verified draft after deployment or an evidence-bound plan revision.
  --check

The generator never reads or writes the original workbook. It consumes the
hash/cell-bound normalized intake and emits frozen-source manifest inputs plus
a pre-runtime Gate F draft. Runtime and Git identities are bound later by
gate-fctl freeze after deployment is stable. Empirical timeout overrides act
only on the generated plan; they never rewrite normalized intake or workbook
facts, and candidate-runtime evidence always requires a formal-runtime replay.
Every infrastructure-soak cell must be admitted by schema-valid, exact-policy,
two-orientation formal-runtime evidence with unchanged protected saves. Gate F
week plans require v2 admission with observed red and blue derived-unit spawns;
the bound faction cases are replayed in every infrastructure soak.
`);
}

function requireArg(args, field) {
  if (!args[field]) fail(`--${field.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)} is required`);
  return args[field];
}

function resolveInsideRoot(candidate, label, mustExist) {
  const resolved = path.resolve(ROOT, candidate);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) fail(`${label} is outside the project root`);
  if (mustExist && !fs.existsSync(resolved)) fail(`${label} does not exist: ${candidate}`);
  return resolved;
}

function relative(filePath) {
  return path.relative(ROOT, filePath).replace(/\\/g, "/");
}

function parseCompleted(entries) {
  const completed = new Map();
  entries.forEach((entry) => {
    const separator = String(entry || "").indexOf("=");
    if (separator <= 0) fail("--completed must be candidateId=sha256:...");
    const candidateId = entry.slice(0, separator);
    const evidenceRef = entry.slice(separator + 1);
    if (!/^sha256:[a-f0-9]{64}$/.test(evidenceRef)) fail(`invalid completed evidence hash for ${candidateId}`);
    if (completed.has(candidateId)) fail(`duplicate --completed candidate: ${candidateId}`);
    completed.set(candidateId, evidenceRef);
  });
  return completed;
}

function sourceCell(candidate) {
  return candidate && candidate.source && candidate.source.cell;
}

function validateProbeOrientations(probe, label) {
  const orientations = probe.observations.map((entry) => entry.orientation).sort();
  if (orientations.join(",") !== "original,swapped") {
    fail(`${label} must contain exactly one original and one swapped observation`);
  }
}

function applyEmpiricalTimeoutOverrides(candidates, document, planId) {
  if (!document) return { candidates, documentRef: null, applied: [] };
  assertSchemaInstance(document.schema, document, "empirical timeout overrides");
  if (document.planId !== planId) fail(`empirical timeout override planId mismatch: ${document.planId}`);
  const byId = new Map(candidates.map((candidate) => [candidate.candidateId, candidate]));
  const seenIds = new Set();
  const seenCells = new Set();
  const documentRef = sha256OfValue(document);
  const replacements = new Map();

  document.overrides.forEach((override) => {
    if (seenIds.has(override.candidateId)) fail(`duplicate empirical timeout candidate: ${override.candidateId}`);
    if (seenCells.has(override.source.cell)) fail(`duplicate empirical timeout source cell: ${override.source.cell}`);
    seenIds.add(override.candidateId);
    seenCells.add(override.source.cell);
    const candidate = byId.get(override.candidateId);
    if (!candidate) fail(`empirical timeout candidate is absent from normalized intake: ${override.candidateId}`);
    if (candidate.candidateHash !== override.candidateHash
        || candidate.source.workbookSha256 !== override.source.workbookSha256
        || candidate.source.sheetName !== override.source.sheetName
        || candidate.source.cell !== override.source.cell
        || candidate.source.cellValueSha256 !== override.source.cellValueSha256) {
      fail(`empirical timeout source binding mismatch: ${override.overrideId}`);
    }
    if (candidate.caseTemplate.timeoutFrames !== override.originalTimeoutFrames) {
      fail(`empirical timeout original frame mismatch: ${override.overrideId}`);
    }
    if (override.promotedTimeoutFrames < LONG_TIMEOUT_FRAMES
        || override.promotedTimeoutFrames <= override.originalTimeoutFrames) {
      fail(`empirical timeout promotion is not a long-timeout increase: ${override.overrideId}`);
    }
    const standardProbe = override.evidence.standardProbe;
    const longProbe = override.evidence.longProbe;
    validateProbeOrientations(standardProbe, `${override.overrideId} standard probe`);
    validateProbeOrientations(longProbe, `${override.overrideId} long probe`);
    if (standardProbe.timeoutFrames !== override.originalTimeoutFrames
        || standardProbe.reportErrors !== 0
        || standardProbe.reportTimeouts < 2
        || standardProbe.observations.some((entry) => entry.status !== "timeout"
          || entry.winner !== "timeout" || entry.frames !== override.originalTimeoutFrames)) {
      fail(`empirical timeout standard probe does not preserve the two-sided timeout: ${override.overrideId}`);
    }
    if (longProbe.timeoutFrames !== override.promotedTimeoutFrames
        || longProbe.reportErrors !== 0
        || longProbe.reportTimeouts !== 0
        || longProbe.observations.some((entry) => entry.status !== "finished"
          || entry.winner === "timeout" || entry.frames <= override.originalTimeoutFrames
          || entry.frames > override.promotedTimeoutFrames)) {
      fail(`empirical timeout long probe did not finish both sides inside the promoted window: ${override.overrideId}`);
    }

    const effective = JSON.parse(JSON.stringify(candidate));
    effective.caseTemplate.timeoutFrames = override.promotedTimeoutFrames;
    effective.caseTemplate.tags = Array.from(new Set([
      ...(effective.caseTemplate.tags || []),
      "long_timeout",
      "empirical_timeout_override",
    ]));
    effective.caseTemplate.plannerReason = `${effective.caseTemplate.plannerReason}; ${override.reason}`;
    effective.riskTags = Array.from(new Set([
      ...(effective.riskTags || []),
      "long_timeout",
      "empirical_timeout_override",
    ]));
    effective.empiricalTimeoutOverride = {
      overrideId: override.overrideId,
      evidenceRef: documentRef,
      originalTimeoutFrames: override.originalTimeoutFrames,
      promotedTimeoutFrames: override.promotedTimeoutFrames,
    };
    replacements.set(candidate.candidateId, effective);
  });

  return {
    candidates: candidates.map((candidate) => replacements.get(candidate.candidateId) || candidate),
    documentRef,
    applied: Array.from(replacements.values()).map((candidate) => candidate.empiricalTimeoutOverride),
  };
}

function cloneCase(candidate, repeat, orientation, phaseTag) {
  const source = JSON.parse(JSON.stringify(candidate.caseTemplate));
  delete source.caseHash;
  source.repeat = repeat;
  source.tags = Array.from(new Set([...(source.tags || []), "gate-f-week", phaseTag]));
  source.plannerReason = `${source.plannerReason}; Gate F ${phaseTag} ${orientation}`;
  if (orientation === "swapped") {
    const blueRoster = source.blueRoster;
    source.blueRoster = source.redRoster;
    source.redRoster = blueRoster;
    const blueFormation = source.blueFormation;
    source.blueFormation = source.redFormation;
    source.redFormation = blueFormation;
    source.caseId = `${candidate.candidateId}-side-swap`;
    source.tags.push("side-swap");
  } else {
    source.caseId = candidate.candidateId;
  }
  return source;
}

function buildManifest(candidates, batchId, totalRuns, phaseTag, createdAt, plannerExtra, battleBuildCommit) {
  if (!Number.isInteger(totalRuns) || totalRuns < 10 || totalRuns > 25) fail(`invalid shard run count: ${totalRuns}`);
  const cases = [];
  if (candidates.length === 1) {
    const originalRuns = Math.floor(totalRuns / 2);
    const swappedRuns = totalRuns - originalRuns;
    cases.push(cloneCase(candidates[0], originalRuns, "original", phaseTag));
    cases.push(cloneCase(candidates[0], swappedRuns, "swapped", phaseTag));
  } else {
    if (totalRuns !== candidates.length * 2) fail("mixed soak shards require one original and one swapped run per candidate");
    candidates.forEach((candidate) => {
      cases.push(cloneCase(candidate, 1, "original", phaseTag));
      cases.push(cloneCase(candidate, 1, "swapped", phaseTag));
    });
  }
  return normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId,
    createdAt,
    buildCommit: battleBuildCommit || "gate-f-runtime-bound-at-freeze",
    planner: {
      name: "gate-f-week-plan",
      version: 1,
      phase: phaseTag,
      candidateIds: candidates.map((entry) => entry.candidateId).sort(),
      ...plannerExtra,
    },
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: Math.max(...candidates.map((entry) => entry.caseTemplate.timeoutFrames)),
    blueBench: null,
    cases,
  });
}

function appendDerivedFactionCases(manifest, evidence, shardId) {
  if (!evidence || !evidence.caseTemplates || !evidence.caseTemplates.original
      || !evidence.caseTemplates.sideSwap) {
    fail("Gate F soak lacks verified derived-faction case templates");
  }
  const raw = JSON.parse(JSON.stringify(manifest));
  delete raw.manifestHash;
  raw.cases.forEach((entry) => { delete entry.caseHash; });
  const appendCase = (source, orientation) => {
    const entry = JSON.parse(JSON.stringify(source));
    delete entry.caseHash;
    entry.caseId = `${shardId}-derived-faction-${orientation}`;
    entry.tags = Array.from(new Set([
      ...(entry.tags || []),
      "gate-f-week",
      "soak",
      "derived-faction-replay",
      ...(orientation === "side-swap" ? ["side-swap"] : []),
    ]));
    entry.plannerReason = `${entry.plannerReason}; Gate F ${shardId} hash-bound derived-faction replay`;
    raw.cases.push(entry);
  };
  appendCase(evidence.caseTemplates.original, "original");
  appendCase(evidence.caseTemplates.sideSwap, "side-swap");
  raw.timeoutFrames = Math.max(...raw.cases.map((entry) => entry.timeoutFrames));
  raw.planner.derivedFactionEvidenceRunId = evidence.evidenceRunId;
  raw.planner.derivedFactionParentUnitType = evidence.parentUnitType;
  raw.planner.derivedFactionUnitType = evidence.derivedUnitType;
  const totalRuns = raw.cases.reduce((total, entry) => total + entry.repeat, 0);
  if (totalRuns < 10 || totalRuns > 25) {
    fail(`derived-faction soak ${shardId} must remain a 10-25 run shard, got ${totalRuns}`);
  }
  return normalizeManifest(raw);
}

function quarantineBaselines(exceptions) {
  return exceptions.map((item) => {
    assertSchemaInstance("arena-calibration.exception-inbox-item.v1", item, "intake exception");
    const cellScope = item.affectedScopes.find((scope) => /^cell:[A-Z]+[0-9]+$/.test(scope));
    const suffix = cellScope ? cellScope.slice(5).toLowerCase() : item.exceptionId.toLowerCase();
    return {
      candidateId: `quarantine-${suffix}`,
      initialState: "quarantined",
      evidenceRef: sha256OfValue(item),
    };
  });
}

function buildWeekPlan(candidates, exceptions, options) {
  const ids = new Set();
  const cells = new Set();
  candidates.forEach((candidate) => {
    if (!candidate.empiricalTimeoutOverride) {
      assertSchemaInstance("arena-calibration.normalized-candidate.v1", candidate, "Gate F normalized candidate");
    }
    if (ids.has(candidate.candidateId)) fail(`duplicate candidateId: ${candidate.candidateId}`);
    if (!sourceCell(candidate) || cells.has(sourceCell(candidate))) fail(`duplicate or missing source cell: ${sourceCell(candidate)}`);
    ids.add(candidate.candidateId);
    cells.add(sourceCell(candidate));
  });
  const completed = options.completed;
  completed.forEach((_value, candidateId) => {
    if (!ids.has(candidateId)) fail(`completed candidate is not in normalized intake: ${candidateId}`);
  });
  const byCell = new Map(candidates.map((candidate) => [sourceCell(candidate), candidate]));
  const scheduled = candidates.filter((candidate) => !completed.has(candidate.candidateId));
  const baselines = candidates.map((candidate) => ({
    candidateId: candidate.candidateId,
    initialState: completed.has(candidate.candidateId) ? "completed_prior" : "scheduled",
    evidenceRef: completed.get(candidate.candidateId) || candidate.candidateHash,
  })).concat(quarantineBaselines(exceptions)).sort((left, right) => left.candidateId.localeCompare(right.candidateId));
  const createdAt = options.createdAt;
  const manifests = [];
  const shards = [];
  if (!Array.isArray(options.soakAdmission.derivedFactionEvidence)
      || options.soakAdmission.derivedFactionEvidence.length !== 1) {
    fail("Gate F week plan requires exactly one verified derived-faction evidence run");
  }
  const derivedFactionEvidence = options.soakAdmission.derivedFactionEvidence[0];

  options.soakAdmission.groups.forEach((group, index) => {
    const groupCandidates = group.map((cell) => byCell.get(cell)).filter(Boolean)
      .filter((candidate) => !completed.has(candidate.candidateId));
    if (groupCandidates.length !== 5) fail(`soak shard ${index + 1} lost a required scheduled candidate`);
    const shardId = `f-soak-${String(index + 1).padStart(2, "0")}`;
    const baseManifest = buildManifest(groupCandidates, `gate-f-week-${shardId}`, 10, "soak", createdAt, {
      soakIndex: index + 1,
      soakAdmissionRef: options.soakAdmission.documentRef,
      coverage: Array.from(new Set(groupCandidates.flatMap((entry) => entry.riskTags))).sort(),
      ...(groupCandidates.some((entry) => entry.empiricalTimeoutOverride) ? {
        empiricalTimeoutOverrideRefs: Array.from(new Set(groupCandidates
          .map((entry) => entry.empiricalTimeoutOverride && entry.empiricalTimeoutOverride.evidenceRef)
          .filter(Boolean))).sort(),
      } : {}),
    }, options.battleBuildCommit);
    const manifest = appendDerivedFactionCases(baseManifest, derivedFactionEvidence, shardId);
    manifests.push({ shardId, manifest });
  });

  scheduled.forEach((candidate) => {
    const phaseRuns = candidate.caseTemplate.timeoutFrames >= LONG_TIMEOUT_FRAMES ? LONG_PHASE_RUNS : NORMAL_PHASE_RUNS;
    phaseRuns.forEach((runCount, index) => {
      const cell = sourceCell(candidate).toLowerCase();
      const shardId = `f-${cell}-p${index + 1}`;
      const phaseTag = candidate.caseTemplate.timeoutFrames >= LONG_TIMEOUT_FRAMES ? "long" : "standard";
      const manifest = buildManifest([candidate], `gate-f-week-${cell}-p${index + 1}`, runCount, phaseTag, createdAt, {
        sourceCell: sourceCell(candidate),
        sourceCandidateHash: candidate.candidateHash,
        ...(candidate.empiricalTimeoutOverride ? {
          empiricalTimeoutOverrideRef: candidate.empiricalTimeoutOverride.evidenceRef,
        } : {}),
        phaseIndex: index + 1,
        phaseRuns: runCount,
      }, options.battleBuildCommit);
      manifests.push({ shardId, manifest });
    });
  });

  manifests.forEach(({ shardId, manifest }) => {
    const candidateIds = Array.from(new Set(manifest.planner.candidateIds)).sort();
    const relativeManifestPath = `${options.outputRelative}/manifests/${shardId}.json`;
    const relativeDecisionPath = `${options.outputRelative}/decisions/${shardId}.json`;
    const decision = createGateFDecisionEvidence({
      decisionId: `decision-${shardId}`,
      planId: options.planId,
      campaignId: options.campaignId,
      shardId,
      candidateIds,
      manifestPath: relativeManifestPath,
      manifestHash: manifest.manifestHash,
      plannedRuns: manifest.cases.reduce((total, entry) => total + entry.repeat, 0),
      evidenceRefs: [
        manifest.manifestHash,
        ...(manifest.planner.phase === "soak" ? [options.soakAdmission.documentRef] : []),
        ...candidateIds.map((candidateId) => candidates.find((entry) => entry.candidateId === candidateId).candidateHash),
        ...candidateIds.flatMap((candidateId) => {
          const candidate = candidates.find((entry) => entry.candidateId === candidateId);
          return candidate.empiricalTimeoutOverride ? [candidate.empiricalTimeoutOverride.evidenceRef] : [];
        }),
      ],
      createdAt,
    });
    const manifestEntry = manifests.find((entry) => entry.shardId === shardId);
    manifestEntry.decision = decision;
    shards.push({
      shardId,
      candidateIds,
      manifestPath: relativeManifestPath,
      manifestHash: manifest.manifestHash,
      plannedRuns: manifest.cases.reduce((total, entry) => total + entry.repeat, 0),
      maxRecoveryAttempts: 1,
      maxWallClockMinutes: 40,
      eligibleEpoch: true,
      decisionEvidencePath: relativeDecisionPath,
      decisionEvidenceRef: decision.decisionHash,
    });
  });

  const draft = {
    planId: options.planId,
    campaignId: options.campaignId,
    battleSemanticsCohortId: options.battleSemanticsCohortId,
    candidateIds: baselines.map((entry) => entry.candidateId),
    candidateBaselines: baselines,
    soakAdmissionPath: options.soakAdmission.path,
    soakAdmissionRef: options.soakAdmission.documentRef,
    slot: "cf7_agent_arena_calibration",
    seedSlot: "crazyflasher7_saves",
    healthPolicy: {
      minimumFreeBytes: 10737418240,
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
    shards,
    createdAt,
  };
  const summary = {
    schema: "arena-calibration.gate-f-week-plan-summary.v1",
    normalizedCandidates: candidates.length,
    scheduledCandidates: scheduled.length,
    completedPriorCandidates: completed.size,
    quarantinedScopes: baselines.filter((entry) => entry.initialState === "quarantined").length,
    empiricalTimeoutOverrides: options.empiricalTimeoutOverrides.applied.length,
    empiricalTimeoutOverrideRef: options.empiricalTimeoutOverrides.documentRef,
    empiricalTimeoutOverrideCells: candidates
      .filter((candidate) => candidate.empiricalTimeoutOverride)
      .map(sourceCell),
    soakAdmissionRef: options.soakAdmission.documentRef,
    soakAdmissionId: options.soakAdmission.admissionId,
    soakCells: options.soakAdmission.groups,
    shards: shards.length,
    plannedRuns: shards.reduce((total, shard) => total + shard.plannedRuns, 0),
    eligibleEpochs: shards.filter((shard) => shard.eligibleEpoch).length,
    decisionEvidenceItems: shards.length,
    firstSoakShards: shards.slice(0, 3).map((shard) => ({
      shardId: shard.shardId,
      candidateIds: shard.candidateIds,
      plannedRuns: shard.plannedRuns,
    })),
    riskCoverage: candidates.reduce((counts, candidate) => {
      candidate.riskTags.forEach((tag) => { counts[tag] = (counts[tag] || 0) + 1; });
      return counts;
    }, {}),
    sourceCells: candidates.map(sourceCell),
    createdAt,
    summaryHash: "",
  };
  summary.summaryHash = sha256OfValue(Object.fromEntries(Object.entries(summary).filter(([key]) => key !== "summaryHash")));
  return { draft, manifests, summary };
}

function runCheck() {
  const expectRejected = (label, callback) => {
    let rejected = false;
    try { callback(); }
    catch (_error) { rejected = true; }
    if (!rejected) throw new Error(`${label} was not rejected`);
  };
  const fixture = (candidateId, cell, timeoutFrames, riskTags) => ({
    schema: "arena-calibration.normalized-candidate.v1",
    candidateId,
    candidateHash: sha256OfValue({ candidateId }),
    source: { cell },
    caseTemplate: {
      caseId: candidateId,
      blueRoster: [{ type: "兵种1", level: 10 }],
      redRoster: [{ type: "兵种2", level: 10 }],
      repeat: 1,
      timeoutFrames,
      spawnDistance: 650,
      blueFormation: "line",
      redFormation: "wedge",
      formationSpacing: 54,
      tags: [],
      plannerReason: `fixture ${cell}`,
    },
    riskTags,
  });
  const normal = fixture("candidate-normal", "B2", 1800, []);
  const long = fixture("candidate-long", "C7", 9000, ["long_timeout"]);
  const c9 = fixture("candidate-c9", "C9", 1800, ["source_corrected"]);
  const fixtureHash = (character) => `sha256:${character.repeat(64)}`;
  const soakAdmission = {
    schema: "arena-calibration.soak-admission.v2",
    admissionId: "fixture-stable-soak-admission",
    planId: "gate-f-week-full-v1",
    battleSemanticsCohortId: "arena-cohort-fixture",
    runtimeIdentity: {
      runtimeMode: "formal_runtime",
      processPath: "C:/fixture/runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe",
      coreSha256: "A".repeat(64),
      buildIdentity: "B".repeat(64),
      payloadClosure: "C".repeat(64),
      verified: true,
    },
    groups: [1, 2, 3].map((soakIndex) => ({
      soakIndex,
      cells: ["B2", "C7", "G2", "F3", "E10"],
    })),
    evidenceRuns: [{
      evidenceRunId: "fixture-soak-run",
      manifestPath: "fixture/manifest.json",
      manifestHash: fixtureHash("1"),
      manifestFileSha256: fixtureHash("2"),
      resultPath: "fixture/results.jsonl",
      resultFileSha256: fixtureHash("3"),
      reportPath: "fixture/report.json",
      reportFileSha256: fixtureHash("4"),
    }],
    derivedFactionEvidenceRuns: [{
      evidenceRunId: "fixture-derived-faction-run",
      manifestPath: "fixture/derived-manifest.json",
      manifestHash: fixtureHash("5"),
      manifestFileSha256: fixtureHash("6"),
      resultPath: "fixture/derived-results.jsonl",
      resultFileSha256: fixtureHash("7"),
      reportPath: "fixture/derived-report.json",
      reportFileSha256: fixtureHash("8"),
      originalCaseId: "fixture-derived-original",
      sideSwapCaseId: "fixture-derived-side-swap",
      parentUnitType: "兵种39",
      derivedUnitType: "敌人-裸体兽化僵尸1",
      minimumSpawnedUnitsBySide: { red: 1, blue: 1 },
    }],
    createdAt: "2026-08-28T00:00:00.000Z",
    admissionHash: "",
  };
  soakAdmission.admissionHash = sha256OfValue(withoutHash(soakAdmission, "admissionHash"));
  const checkedAdmission = verifySoakAdmissionDocument(ROOT, soakAdmission, {
    planId: "gate-f-week-full-v1",
    battleSemanticsCohortId: "arena-cohort-fixture",
    requireDerivedFactionEvidence: true,
  });
  const legacyAdmission = JSON.parse(JSON.stringify(soakAdmission));
  legacyAdmission.schema = "arena-calibration.soak-admission.v1";
  delete legacyAdmission.derivedFactionEvidenceRuns;
  legacyAdmission.admissionHash = sha256OfValue(withoutHash(legacyAdmission, "admissionHash"));
  expectRejected("legacy admission for a new week plan", () => {
    verifySoakAdmissionDocument(ROOT, legacyAdmission, { requireDerivedFactionEvidence: true });
  });
  const tamperedAdmission = JSON.parse(JSON.stringify(soakAdmission));
  tamperedAdmission.groups[2].cells[4] = "C9";
  expectRejected("tampered stable-soak admission", () => {
    verifySoakAdmissionDocument(ROOT, tamperedAdmission, { planId: "gate-f-week-full-v1" });
  });
  const derivedFactionManifest = {
    cases: [{
      caseId: "fixture-derived-original",
      blueRoster: [{ type: "兵种27", level: 10 }],
      redRoster: [{ type: "兵种39", level: 20 }],
      repeat: 1,
      timeoutFrames: 1800,
      spawnDistance: 650,
      blueFormation: "line",
      redFormation: "line",
      formationSpacing: 54,
      tags: ["original"],
      plannerReason: "fixture derived-faction original",
    }, {
      caseId: "fixture-derived-side-swap",
      blueRoster: [{ type: "兵种39", level: 20 }],
      redRoster: [{ type: "兵种27", level: 10 }],
      repeat: 1,
      timeoutFrames: 1800,
      spawnDistance: 650,
      blueFormation: "line",
      redFormation: "line",
      formationSpacing: 54,
      tags: ["side-swap"],
      plannerReason: "fixture derived-faction side swap",
    }],
  };
  const derivedFactionRows = [{
    runId: "fixture-derived-red",
    caseId: "fixture-derived-original",
    phaseSpawnCount: 1,
    spawnedUnits: [{ from: "兵种39", unit: "敌人-裸体兽化僵尸1", side: "red" }],
  }, {
    runId: "fixture-derived-blue",
    caseId: "fixture-derived-side-swap",
    phaseSpawnCount: 1,
    spawnedUnits: [{ from: "兵种39", unit: "敌人-裸体兽化僵尸1", side: "blue" }],
  }];
  const factionCoverage = verifyDerivedFactionCoverage(
    derivedFactionManifest,
    derivedFactionRows,
    soakAdmission.derivedFactionEvidenceRuns[0],
  );
  if (factionCoverage.red !== 1 || factionCoverage.blue !== 1) {
    throw new Error("Gate F derived-faction positive coverage check failed");
  }
  const factionMismatchRows = JSON.parse(JSON.stringify(derivedFactionRows));
  factionMismatchRows[1].spawnedUnits[0].side = "red";
  expectRejected("wrong-side derived spawn", () => {
    verifyDerivedFactionCoverage(
      derivedFactionManifest,
      factionMismatchRows,
      soakAdmission.derivedFactionEvidenceRuns[0],
    );
  });
  const missingFactionRows = JSON.parse(JSON.stringify(derivedFactionRows));
  missingFactionRows[1].spawnedUnits = [];
  missingFactionRows[1].phaseSpawnCount = 0;
  expectRejected("unobserved blue derived spawn", () => {
    verifyDerivedFactionCoverage(
      derivedFactionManifest,
      missingFactionRows,
      soakAdmission.derivedFactionEvidenceRuns[0],
    );
  });
  const factionReplayManifest = appendDerivedFactionCases(
    buildManifest([normal], "gate-f-check-soak", 10, "soak", "2026-08-28T00:00:00.000Z", {}),
    {
      evidenceRunId: "fixture-derived-faction-run",
      parentUnitType: "兵种39",
      derivedUnitType: "敌人-裸体兽化僵尸1",
      caseTemplates: {
        original: derivedFactionManifest.cases[0],
        sideSwap: derivedFactionManifest.cases[1],
      },
    },
    "f-soak-check",
  );
  assertSchemaInstance(factionReplayManifest.schema, factionReplayManifest, "Gate F derived-faction replay manifest");
  if (factionReplayManifest.cases.reduce((total, entry) => total + entry.repeat, 0) !== 12
      || factionReplayManifest.planner.derivedFactionEvidenceRunId !== "fixture-derived-faction-run"
      || !factionReplayManifest.cases.some((entry) => entry.caseId === "f-soak-check-derived-faction-original")
      || !factionReplayManifest.cases.some((entry) => entry.caseId === "f-soak-check-derived-faction-side-swap")) {
    throw new Error("Gate F derived-faction replay manifest check failed");
  }
  normal.source = {
    workbookSha256: fixtureHash("a"),
    sheetName: "fixture",
    cell: "B2",
    cellValueSha256: fixtureHash("b"),
  };
  const overrideDocument = {
    schema: "arena-calibration.empirical-timeout-overrides.v1",
    planId: "gate-f-week-full-v1",
    createdAt: "2026-08-27T00:00:00.000Z",
    overrides: [{
      overrideId: "fixture-timeout-promotion",
      candidateId: normal.candidateId,
      candidateHash: normal.candidateHash,
      source: { ...normal.source },
      originalTimeoutFrames: 1800,
      promotedTimeoutFrames: 5400,
      reason: "fixture evidence-bound timeout promotion",
      preserveOriginalTimeoutEvidence: true,
      evidence: {
        runtimeIdentity: {
          state: "candidate_executed",
          coreSha256: "A".repeat(64),
          buildIdentity: "B".repeat(64),
          payloadClosure: "C".repeat(64),
          formalReplayRequired: true,
        },
        saveProtection: { snapshotHash: fixtureHash("c"), unchanged: true },
        standardProbe: {
          batchId: "fixture-standard",
          manifestHash: fixtureHash("d"),
          manifestFileSha256: fixtureHash("e"),
          resultFileSha256: fixtureHash("f"),
          reportFileSha256: fixtureHash("1"),
          timeoutFrames: 1800,
          reportRows: 2,
          reportErrors: 0,
          reportTimeouts: 2,
          observations: [
            { orientation: "original", caseHash: fixtureHash("2"), status: "timeout", winner: "timeout", frames: 1800, durationMs: 70000 },
            { orientation: "swapped", caseHash: fixtureHash("3"), status: "timeout", winner: "timeout", frames: 1800, durationMs: 71000 },
          ],
        },
        longProbe: {
          batchId: "fixture-long",
          manifestHash: fixtureHash("4"),
          manifestFileSha256: fixtureHash("5"),
          resultFileSha256: fixtureHash("6"),
          reportFileSha256: fixtureHash("7"),
          timeoutFrames: 5400,
          reportRows: 2,
          reportErrors: 0,
          reportTimeouts: 0,
          observations: [
            { orientation: "original", caseHash: fixtureHash("8"), status: "finished", winner: "blue", frames: 2700, durationMs: 110000 },
            { orientation: "swapped", caseHash: fixtureHash("9"), status: "finished", winner: "red", frames: 3500, durationMs: 145000 },
          ],
        },
      },
    }],
  };
  const promoted = applyEmpiricalTimeoutOverrides([normal], overrideDocument, "gate-f-week-full-v1");
  const schemaInvalidOverride = JSON.parse(JSON.stringify(overrideDocument));
  schemaInvalidOverride.overrides[0].promotedTimeoutFrames = "5400";
  expectRejected("schema-invalid empirical timeout override", () => {
    applyEmpiricalTimeoutOverrides([normal], schemaInvalidOverride, "gate-f-week-full-v1");
  });
  const semanticallyInvalidOverride = JSON.parse(JSON.stringify(overrideDocument));
  semanticallyInvalidOverride.overrides[0].evidence.longProbe.observations[1].orientation = "original";
  expectRejected("one-sided empirical timeout override", () => {
    applyEmpiricalTimeoutOverrides([normal], semanticallyInvalidOverride, "gate-f-week-full-v1");
  });
  const standardManifest = buildManifest([normal], "gate-f-check-standard", 25, "standard", "2026-08-27T00:00:00.000Z", {});
  const longManifest = buildManifest([long], "gate-f-check-long", 10, "long", "2026-08-27T00:00:00.000Z", {});
  const promotedManifest = buildManifest(promoted.candidates, "gate-f-check-promoted", 10, "long", "2026-08-27T00:00:00.000Z", {
    empiricalTimeoutOverrideRef: promoted.documentRef,
  });
  assertSchemaInstance(standardManifest.schema, standardManifest, "Gate F standard check manifest");
  assertSchemaInstance(longManifest.schema, longManifest, "Gate F long check manifest");
  assertSchemaInstance(promotedManifest.schema, promotedManifest, "Gate F promoted check manifest");
  if (standardManifest.cases.reduce((sum, entry) => sum + entry.repeat, 0) !== 25
      || longManifest.cases.reduce((sum, entry) => sum + entry.repeat, 0) !== 10
      || !longManifest.cases.some((entry) => entry.tags.includes("side-swap"))
      || promoted.applied.length !== 1
      || promotedManifest.timeoutFrames !== 5400
      || promotedManifest.cases.some((entry) => entry.timeoutFrames !== 5400
        || !entry.tags.includes("empirical_timeout_override"))
      || promotedManifest.cases[0].caseHash === standardManifest.cases[0].caseHash) {
    throw new Error("Gate F week manifest split check failed");
  }
  const soakCells = new Set(checkedAdmission.groups.flat());
  const c9PhaseRuns = c9.caseTemplate.timeoutFrames >= LONG_TIMEOUT_FRAMES
    ? LONG_PHASE_RUNS
    : NORMAL_PHASE_RUNS;
  if (!soakCells.has("B2")
      || !soakCells.has("G2")
      || !soakCells.has("C7")
      || !soakCells.has("E10")
      || soakCells.has("C9")
      || c9PhaseRuns !== NORMAL_PHASE_RUNS
      || c9PhaseRuns.reduce((total, count) => total + count, 0) !== 55) {
    throw new Error("Gate F infrastructure-soak routing check failed");
  }
  console.log(JSON.stringify({
    ok: true,
    check: "gate-f-week-plan-contract",
    standardCandidateRuns: 55,
    longTimeoutCandidateRuns: 60,
    firstSoakShards: 3,
    sideSwapAlwaysPlanned: true,
    evidenceBoundTimeoutPromotion: true,
    invalidTimeoutOverridesRejected: true,
    infrastructureSoakRequiresHashBoundStableAdmission: true,
    newWeekPlanRequiresDerivedFactionAdmissionV2: true,
    wrongSideOrUnobservedDerivedSpawnsRejected: true,
    everyInfrastructureSoakReplaysDerivedFactionCases: true,
    allSoaksCoverOrdinaryPayloadFormationLongTimeoutAndHighLevel: true,
    stochasticC9RetainedInStandardPhases: true,
  }));
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  if (args.check) return runCheck();
  const candidatePath = resolveInsideRoot(requireArg(args, "candidates"), "normalized candidates", true);
  const exceptionPath = resolveInsideRoot(requireArg(args, "exceptions"), "intake exceptions", true);
  const empiricalTimeoutOverridePath = args.empiricalTimeoutOverrides
    ? resolveInsideRoot(args.empiricalTimeoutOverrides, "empirical timeout overrides", true)
    : null;
  const soakAdmissionPath = resolveInsideRoot(requireArg(args, "soakAdmission"), "Gate F soak admission", true);
  const outputDir = resolveInsideRoot(requireArg(args, "outputDir"), "Gate F week plan output", false);
  if (fs.existsSync(outputDir) && fs.readdirSync(outputDir).length > 0 && !args.updateExisting) {
    fail(`output directory must be absent or empty: ${relative(outputDir)}`);
  }
  const candidates = readJsonFile(candidatePath);
  const exceptions = readJsonFile(exceptionPath);
  if (!Array.isArray(candidates) || !Array.isArray(exceptions)) fail("candidate and exception inputs must be JSON arrays");
  candidates.forEach((candidate) => {
    assertSchemaInstance("arena-calibration.normalized-candidate.v1", candidate, "Gate F normalized source candidate");
  });
  const createdAt = args.createdAt || new Date().toISOString();
  if (args.battleBuildCommit && !/^[a-f0-9]{40}$/i.test(args.battleBuildCommit)) {
    fail("--battle-build-commit must be a full 40-hex commit");
  }
  if (args.rebindRuntimeSource && (!args.updateExisting || !args.battleBuildCommit)) {
    fail("--rebind-runtime-source requires --update-existing and --battle-build-commit");
  }
  const empiricalTimeoutOverrides = applyEmpiricalTimeoutOverrides(
    candidates,
    empiricalTimeoutOverridePath ? readJsonFile(empiricalTimeoutOverridePath) : null,
    args.planId,
  );
  const soakAdmissionDocument = readJsonFile(soakAdmissionPath);
  const verifiedSoakAdmission = verifySoakAdmissionDocument(ROOT, soakAdmissionDocument, {
    planId: args.planId,
    battleSemanticsCohortId: args.battleSemanticsCohortId,
    candidates: empiricalTimeoutOverrides.candidates,
    verifyRawEvidence: true,
    requireDerivedFactionEvidence: true,
  });
  const result = buildWeekPlan(empiricalTimeoutOverrides.candidates, exceptions, {
    completed: parseCompleted(args.completed),
    planId: args.planId,
    campaignId: args.campaignId,
    battleSemanticsCohortId: args.battleSemanticsCohortId,
    battleBuildCommit: args.battleBuildCommit,
    createdAt,
    outputRelative: relative(outputDir),
    empiricalTimeoutOverrides,
    soakAdmission: {
      admissionId: soakAdmissionDocument.admissionId,
      path: relative(soakAdmissionPath),
      documentRef: verifiedSoakAdmission.documentRef,
      groups: verifiedSoakAdmission.groups,
      derivedFactionEvidence: verifiedSoakAdmission.derivedFactionEvidence,
    },
  });
  fs.mkdirSync(path.join(outputDir, "manifests"), { recursive: true });
  fs.mkdirSync(path.join(outputDir, "decisions"), { recursive: true });
  if (args.updateExisting) {
    result.manifests.forEach(({ shardId, manifest }) => {
      const manifestPath = path.join(outputDir, "manifests", `${shardId}.json`);
      if (!fs.existsSync(manifestPath)) return;
      const existing = readJsonFile(manifestPath);
      verifyManifestIntegrity(existing, `existing Gate F manifest ${shardId}`);
      if (existing.manifestHash !== manifest.manifestHash && !args.rebindRuntimeSource) {
        fail(`existing manifest drifted: ${relative(manifestPath)}`);
      }
    });
  }
  result.manifests.forEach(({ shardId, manifest, decision }) => {
    const manifestPath = path.join(outputDir, "manifests", `${shardId}.json`);
    writeJsonAtomic(manifestPath, manifest);
    writeJsonAtomic(path.join(outputDir, "decisions", `${shardId}.json`), decision);
  });
  writeJsonAtomic(path.join(outputDir, "plan-draft.json"), result.draft);
  writeJsonAtomic(path.join(outputDir, "schedule-summary.json"), result.summary);
  writeJsonAtomic(path.join(outputDir, "source-provenance.json"), {
    schema: "arena-calibration.gate-f-week-source-provenance.v1",
    normalizedCandidatesRef: sha256OfValue(candidates),
    intakeExceptionsRef: sha256OfValue(exceptions),
    empiricalTimeoutOverridesRef: empiricalTimeoutOverrides.documentRef,
    empiricalTimeoutOverridesPath: empiricalTimeoutOverridePath ? relative(empiricalTimeoutOverridePath) : null,
    soakAdmissionRef: verifiedSoakAdmission.documentRef,
    soakAdmissionPath: relative(soakAdmissionPath),
    completedCandidates: Array.from(parseCompleted(args.completed).entries()).map(([candidateId, evidenceRef]) => ({ candidateId, evidenceRef })),
    battleBuildCommit: args.battleBuildCommit || null,
    workbookRefs: Array.from(new Set(candidates.map((entry) => entry.source.workbookSha256))).sort(),
    sourceCells: candidates.map(sourceCell),
    generatedAt: createdAt,
  });
  console.log(JSON.stringify({
    ok: true,
    outputDir: relative(outputDir),
    ...result.summary,
  }, null, 2));
}

try { main(process.argv.slice(2)); }
catch (error) {
  console.error(error.message);
  process.exit(error.isUsageError ? 2 : 1);
}
