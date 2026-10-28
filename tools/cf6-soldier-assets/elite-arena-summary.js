#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  normalizeManifest,
  normalizeResultRow,
} = require("../arena-calibration/lib/arena-calibration-core");

const SCHEMA = "cf6-soldier.elite-arena-summary.v2";
const DEFAULT_BOOTSTRAP_ITERATIONS = 10000;
const DEFAULT_SEED = 20261017;
const CONFIDENCE = 0.95;
const COMPARISON_CONTEXT_FIELDS = Object.freeze([
  "baseUnitId",
  "opponentId",
  "opponentLevel",
  "opponentWeapon",
  "level",
  "weapon",
  "candidateSide",
  "phase",
  "spawnDistance",
  "timeoutFrames",
]);
const STRATIFICATION_DIMENSIONS = Object.freeze([
  "opponentId",
  "opponentLevel",
  "level",
  "equipment",
  "candidateSide",
  "phase",
  "toughnessCoefficient",
  "dualWieldState",
  "spawnDistance",
  "timeoutFrames",
  "timeout",
]);
const COMPARISONS = Object.freeze([
  {
    id: "ordinary-vs-elite-overall",
    baseline: "ordinary",
    candidate: "elite",
    baselineFilter: { equipmentProfile: "ordinary-stock" },
    candidateFilter: { equipmentProfile: "elite-stock" },
    fields: COMPARISON_CONTEXT_FIELDS,
    pairedContrastRequired: true,
    attribution: "stock ordinary versus stock elite; toughness, FR506 and elite behavior vary together",
  },
  {
    id: "ordinary-vs-elite-same-toughness",
    baseline: "ordinary",
    candidate: "elite",
    fields: [...COMPARISON_CONTEXT_FIELDS, "toughnessCoefficient"],
    sharedStratumField: "toughnessCoefficient",
    attribution: "toughness is held within each stratum; remaining equipment and behavior differences are not erased",
  },
  {
    id: "elite-vs-no-sidearm",
    baseline: "noSidearm",
    candidate: "elite",
    fields: [...COMPARISON_CONTEXT_FIELDS, "matchKey"],
    sharedStratumField: "matchKey",
    attribution: "identical passive matchKey; only elite sidearm behavior is contrasted, without a full-effective-panel equality claim",
  },
]);

function stableClone(value) {
  if (Array.isArray(value)) return value.map(stableClone);
  if (value && typeof value === "object") {
    const result = {};
    for (const key of Object.keys(value).sort()) {
      if (value[key] !== undefined) result[key] = stableClone(value[key]);
    }
    return result;
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableClone(value));
}

function mean(values) {
  if (!values.length) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(path.toNamespacedPath(filePath), "utf8").replace(/^\uFEFF/, ""));
}

function loadCohort(spec, baseDirectory = process.cwd()) {
  if (!spec || typeof spec !== "object" || Array.isArray(spec)) throw Error("Each cohort must be an object");
  const cohortId = spec.cohortId || spec.id;
  if (typeof cohortId !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(cohortId)) {
    throw Error("Each cohort requires a bounded cohortId");
  }
  if (typeof spec.manifestPath !== "string" || typeof spec.resultPath !== "string") {
    throw Error(`Cohort ${cohortId} requires manifestPath and resultPath`);
  }
  const manifestPath = path.resolve(baseDirectory, spec.manifestPath);
  const resultPath = path.resolve(baseDirectory, spec.resultPath);
  const cohort = {
    cohortId,
    manifestPath,
    resultPath,
    manifestSha256: null,
    resultSha256: null,
    manifest: null,
    rows: [],
    loadErrors: [],
  };
  try {
    const bytes = fs.readFileSync(path.toNamespacedPath(manifestPath));
    cohort.manifestSha256 = sha256(bytes);
    cohort.manifest = JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, ""));
  } catch (error) {
    cohort.loadErrors.push(`manifest_load:${error.message}`);
  }
  let text;
  try {
    const bytes = fs.readFileSync(path.toNamespacedPath(resultPath));
    cohort.resultSha256 = sha256(bytes);
    text = bytes.toString("utf8").replace(/^\uFEFF/, "");
  } catch (error) {
    cohort.loadErrors.push(`result_load:${error.message}`);
    return cohort;
  }
  text.split(/\r?\n/).forEach((line, index) => {
    if (!line.trim()) return;
    try {
      cohort.rows.push(JSON.parse(line));
    } catch (error) {
      cohort.loadErrors.push(`result_json:${index + 1}:${error.message}`);
    }
  });
  return cohort;
}

function rawChip(side, label, reasons) {
  if (!side || typeof side !== "object"
      || !Object.prototype.hasOwnProperty.call(side, "startMaxHp")
      || !Object.prototype.hasOwnProperty.call(side, "remainHp")
      || typeof side.startMaxHp !== "number" || !Number.isFinite(side.startMaxHp) || side.startMaxHp <= 0
      || typeof side.remainHp !== "number" || !Number.isFinite(side.remainHp) || side.remainHp < 0) {
    reasons.push(`invalid_raw_hp:${label}`);
    return null;
  }
  return 1 - side.remainHp / side.startMaxHp;
}

function validContext(context) {
  if (!context || typeof context !== "object" || Array.isArray(context)) return false;
  const strings = ["comparisonKey", "variant", "candidateSide", "weapon", "sidearmBehavior", "matchKey", "equipmentProfile", "dualWieldState"];
  const numbers = ["unitId", "baseUnitId", "opponentId", "opponentLevel", "level", "effectiveToughnessCoefficient", "initialPhase"];
  return strings.every((key) => typeof context[key] === "string" && context[key].length > 0)
    && numbers.every((key) => typeof context[key] === "number" && Number.isFinite(context[key]))
    && ["red", "blue"].includes(context.candidateSide)
    && (context.sidearm === null || typeof context.sidearm === "string")
    && (context.opponentWeapon === null || typeof context.opponentWeapon === "string")
    && typeof context.passiveMatched === "boolean"
    && context.noPairwiseRngClaim === true
    && context.blueFriendlyHpMultiplierReportedSeparately === true;
}

function inspectCohort(cohort) {
  const reasons = [...(cohort.loadErrors || [])];
  const reasonSet = new Set(reasons);
  const reject = (reason) => {
    if (!reasonSet.has(reason)) {
      reasonSet.add(reason);
      reasons.push(reason);
    }
  };
  const report = {
    cohortId: cohort.cohortId,
    manifestPath: cohort.manifestPath || null,
    resultPath: cohort.resultPath || null,
    manifestSha256: cohort.manifestSha256 || null,
    resultSha256: cohort.resultSha256 || null,
    manifestHash: null,
    expectedRows: null,
    observedRows: Array.isArray(cohort.rows) ? cohort.rows.length : 0,
    qualified: false,
    reasons,
  };
  let manifest;
  try {
    manifest = normalizeManifest(cohort.manifest);
    if (cohort.manifest.manifestHash !== manifest.manifestHash) reject("manifest_hash_mismatch");
  } catch (error) {
    reject(`manifest_invalid:${error.message}`);
    report.reasons = reasons;
    return { report, samples: [] };
  }
  report.manifestHash = manifest.manifestHash;
  const cases = new Map(manifest.cases.map((testCase) => [testCase.caseId, testCase]));
  const expectedRepeats = new Set();
  for (const testCase of manifest.cases) {
    for (let repeatIndex = 1; repeatIndex <= testCase.repeat; repeatIndex += 1) {
      expectedRepeats.add(`${testCase.caseId}|${repeatIndex}`);
    }
  }
  report.expectedRows = expectedRepeats.size;
  if (report.observedRows !== report.expectedRows) reject("row_count_mismatch");
  const seenRuns = new Set();
  const seenRepeats = new Set();
  const samples = [];
  const rows = Array.isArray(cohort.rows) ? cohort.rows : [];
  rows.forEach((raw, index) => {
    let row;
    try {
      row = normalizeResultRow(raw);
    } catch (error) {
      reject(`invalid_result_row:${index + 1}:${error.message}`);
      return;
    }
    if (row.batchId !== manifest.batchId || row.manifestHash !== manifest.manifestHash) {
      reject(`batch_manifest_mismatch:${index + 1}`);
      return;
    }
    const testCase = cases.get(row.caseId);
    if (!testCase || row.caseHash !== testCase.caseHash) {
      reject(`case_binding_mismatch:${index + 1}`);
      return;
    }
    if (row.repeatIndex > testCase.repeat) reject(`repeat_out_of_range:${index + 1}`);
    if (seenRuns.has(row.runId)) reject(`duplicate_runId:${row.runId}`);
    seenRuns.add(row.runId);
    const repeatKey = `${row.caseId}|${row.repeatIndex}`;
    if (seenRepeats.has(repeatKey)) reject(`duplicate_case_repeat:${repeatKey}`);
    seenRepeats.add(repeatKey);
    if (stableStringify(row.authorityContext) !== stableStringify(testCase.authorityContext || {})) {
      reject(`authority_context_mismatch:${index + 1}`);
      return;
    }
    if ((row.requestedSpawnDistance !== null && row.requestedSpawnDistance !== testCase.spawnDistance)
        || (row.spawnDistance !== null && row.spawnDistance !== testCase.spawnDistance)) {
      reject(`spawn_distance_mismatch:${index + 1}`);
      return;
    }
    const context = testCase.authorityContext;
    if (!validContext(context)) {
      reject(`invalid_elite_authority_context:${index + 1}`);
      return;
    }
    const hasClock = typeof row.frames === "number" && row.frames > 0
      && typeof row.durationMs === "number" && row.durationMs > 0;
    let naturalTimeout = false;
    if (row.status === "finished") {
      if (!hasClock || row.errors.length !== 0 || !["blue", "red", "draw"].includes(row.winner)) {
        reject(`invalid_finished_row:${index + 1}`);
        return;
      }
    } else if (row.status === "timeout") {
      naturalTimeout = hasClock && row.errors.length === 0 && row.winner === "timeout"
        && row.frames === testCase.timeoutFrames;
      if (!naturalTimeout) {
        reject(`non_natural_timeout:${index + 1}`);
        return;
      }
    } else {
      reject(`disqualifying_status:${row.status}:${index + 1}`);
      return;
    }
    const blueChip = rawChip(raw.blue, `${index + 1}:blue`, reasons);
    const redChip = rawChip(raw.red, `${index + 1}:red`, reasons);
    if (blueChip === null || redChip === null) return;
    const opponentChip = context.candidateSide === "red" ? blueChip : redChip;
    const ownChip = context.candidateSide === "red" ? redChip : blueChip;
    const opposingSide = context.candidateSide === "red" ? "blue" : "red";
    samples.push({
      sampleKey: `${cohort.cohortId}|${row.runId}`,
      cohortId: cohort.cohortId,
      runId: row.runId,
      manifestHash: row.manifestHash,
      caseId: row.caseId,
      repeatIndex: row.repeatIndex,
      comparisonKey: context.comparisonKey,
      variant: context.variant,
      unitId: context.unitId,
      baseUnitId: context.baseUnitId,
      candidateSide: context.candidateSide,
      opponentId: context.opponentId,
      opponentLevel: context.opponentLevel,
      opponentWeapon: context.opponentWeapon,
      level: context.level,
      equipment: { primary: context.weapon, secondary: context.sidearm, secondary2: context.sidearm2 },
      weapon: context.weapon,
      sidearm: context.sidearm,
      sidearm2: context.sidearm2,
      sidearmBehavior: context.sidearmBehavior,
      passiveMatched: context.passiveMatched,
      matchKey: context.matchKey,
      equipmentProfile: context.equipmentProfile,
      phase: context.initialPhase,
      toughnessCoefficient: context.effectiveToughnessCoefficient,
      dualWieldState: context.dualWieldState,
      spawnDistance: testCase.spawnDistance,
      timeoutFrames: testCase.timeoutFrames,
      timeout: naturalTimeout,
      status: row.status,
      winner: row.winner,
      won: row.status === "finished" && row.winner === context.candidateSide,
      lost: row.status === "finished" && row.winner === opposingSide,
      draw: row.status === "finished" && row.winner === "draw",
      chip: opponentChip,
      ownChip,
    });
  });
  for (const repeatKey of expectedRepeats) {
    if (!seenRepeats.has(repeatKey)) reject(`missing_case_repeat:${repeatKey}`);
  }
  report.reasons = reasons;
  report.qualified = reasons.length === 0 && samples.length === report.expectedRows;
  if (!report.qualified && !reasons.length) reject("cohort_not_qualified");
  report.reasons = reasons;
  return { report, samples: report.qualified ? samples : [] };
}

function summarizeSamples(samples) {
  const finished = samples.filter((sample) => sample.status === "finished").length;
  return {
    samples: samples.length,
    finished,
    timeouts: samples.filter((sample) => sample.timeout).length,
    wins: samples.filter((sample) => sample.won).length,
    losses: samples.filter((sample) => sample.lost).length,
    draws: samples.filter((sample) => sample.draw).length,
    winRate: finished > 0 ? samples.filter((sample) => sample.won).length / finished : null,
    meanChip: mean(samples.map((sample) => sample.chip)),
    meanOwnChip: mean(samples.map((sample) => sample.ownChip)),
    negativeChipSamples: samples.filter((sample) => sample.chip < 0).length,
    cohortIds: [...new Set(samples.map((sample) => sample.cohortId))].sort(),
  };
}

function groupedSummaries(samples, fields) {
  const groups = new Map();
  for (const sample of samples) {
    const stratum = {};
    for (const field of fields) stratum[field] = sample[field];
    const key = stableStringify(stratum);
    if (!groups.has(key)) groups.set(key, { stratum, samples: [] });
    groups.get(key).samples.push(sample);
  }
  return [...groups.values()].sort((left, right) =>
    stableStringify(left.stratum).localeCompare(stableStringify(right.stratum)));
}

function buildDescriptiveStrata(samples) {
  return groupedSummaries(samples, ["variant", ...STRATIFICATION_DIMENSIONS]).map((group) => ({
    stratum: group.stratum,
    layerWeight: samples.length ? group.samples.length / samples.length : 0,
    ...summarizeSamples(group.samples),
  }));
}

function mulberry32(seed) {
  let state = seed >>> 0;
  return function random() {
    state = (state + 0x6D2B79F5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function resampleMean(values, random) {
  let total = 0;
  for (let index = 0; index < values.length; index += 1) {
    total += values[Math.floor(random() * values.length)];
  }
  return total / values.length;
}

function quantile(sorted, probability) {
  if (!sorted.length) return null;
  const position = (sorted.length - 1) * probability;
  const lower = Math.floor(position);
  const fraction = position - lower;
  return sorted[lower] + fraction * (sorted[Math.min(lower + 1, sorted.length - 1)] - sorted[lower]);
}

function comparisonSeed(baseSeed, side, comparisonId) {
  const digest = crypto.createHash("sha256").update(`${baseSeed}|${side}|${comparisonId}`, "utf8").digest();
  return digest.readUInt32BE(0);
}

function matchesFilter(sample, filter) {
  return Object.entries(filter || {}).every(([key, value]) => sample[key] === value);
}

function buildPairedContrast(layers, options, definition) {
  const minimumPairs = options.side === "red" ? options.minimumPairsPerLayer : 0;
  const reasons = [...(options.cohortsQualified ? [] : ["unqualified_cohorts"])];
  const pairs = [];
  const pairedLayers = [];
  for (const layer of layers) {
    const indexes = {};
    const rejected = new Set();
    for (const [arm, samples] of [["baseline", layer.baselineRows], ["candidate", layer.candidateRows]]) {
      const index = new Map();
      for (const sample of samples) {
        if (!Number.isSafeInteger(sample.repeatIndex) || sample.repeatIndex < 1) {
          reasons.push(`invalid_pair_repeat:${layer.key}:${sample.sampleKey}`);
          continue;
        }
        const key = JSON.stringify([sample.comparisonKey, sample.repeatIndex]);
        if (index.has(key)) {
          rejected.add(key);
          reasons.push(`duplicate_comparison_pair:${arm}:${layer.key}:${key}`);
        } else index.set(key, sample);
      }
      indexes[arm] = index;
    }
    const layerPairs = [];
    const keys = [...new Set([...indexes.baseline.keys(), ...indexes.candidate.keys()])].sort();
    for (const key of keys) {
      const baseline = indexes.baseline.get(key);
      const candidate = indexes.candidate.get(key);
      if (rejected.has(key)) continue;
      if (!baseline || !candidate) {
        reasons.push(`unmatched_comparison_pair:${layer.key}:${key}`);
        continue;
      }
      const pair = {
        stratumKey: layer.key,
        comparisonKey: baseline.comparisonKey,
        repeatIndex: baseline.repeatIndex,
        baselineSampleKey: baseline.sampleKey,
        candidateSampleKey: candidate.sampleKey,
        baselineChip: baseline.chip,
        candidateChip: candidate.chip,
        effect: candidate.chip - baseline.chip,
      };
      layerPairs.push(pair);
      pairs.push(pair);
    }
    if (layerPairs.length < minimumPairs) reasons.push(`insufficient_comparison_pairs:${layer.key}`);
    pairedLayers.push({
      stratum: layer.stratum,
      weight: layer.weight,
      pairs: layerPairs.length,
      baselineMeanChip: layer.baselineMeanChip,
      candidateMeanChip: layer.candidateMeanChip,
      effect: mean(layerPairs.map((pair) => pair.effect)),
      values: layerPairs.map((pair) => pair.effect),
    });
  }
  const uniqueReasons = [...new Set(reasons)];
  const qualified = uniqueReasons.length === 0 && layers.length > 0 && pairs.length > 0;
  const seed = comparisonSeed(options.seed, options.side, definition.id + "|paired-case-contrast");
  let effect = null;
  let ci95 = { lower: null, upper: null, confidence: CONFIDENCE, method: "percentile" };
  if (qualified) {
    effect = pairedLayers.reduce((sum, layer) => sum + layer.weight * layer.effect, 0);
    const random = mulberry32(seed);
    const bootstrapEffects = [];
    for (let iteration = 0; iteration < options.iterations; iteration += 1) {
      let bootstrapEffect = 0;
      for (const layer of pairedLayers) bootstrapEffect += layer.weight * resampleMean(layer.values, random);
      bootstrapEffects.push(bootstrapEffect);
    }
    bootstrapEffects.sort((left, right) => left - right);
    ci95 = { lower: quantile(bootstrapEffects, 0.025), upper: quantile(bootstrapEffects, 0.975),
      confidence: CONFIDENCE, method: "percentile" };
  }
  return {
    method: "pre-registered comparisonKey and repeatIndex paired contrast; no shared RNG claim",
    pairedSamples: pairs.length,
    minimumPairsPerLayer: minimumPairs,
    layerWeightSum: pairedLayers.reduce((sum, layer) => sum + layer.weight, 0),
    layers: pairedLayers.map(({ values, ...layer }) => layer),
    pairs,
    effect,
    ci95,
    bootstrap: {
      iterations: options.iterations,
      seed,
      baseSeed: options.seed,
      algorithm: "mulberry32-uint32",
      method: "stratified paired-case percentile bootstrap",
      pairedByComparisonKeyAndRepeatIndex: true,
      sharedRng: false,
    },
    qualification: { qualified, reasons: uniqueReasons },
    qualified,
  };
}

function compareVariants(samples, definition, options) {
  const baselinePool = samples.filter((sample) => sample.variant === definition.baseline
    && matchesFilter(sample, definition.baselineFilter));
  const candidatePool = samples.filter((sample) => sample.variant === definition.candidate
    && matchesFilter(sample, definition.candidateFilter));
  let baseline = baselinePool;
  let candidate = candidatePool;
  if (definition.sharedStratumField) {
    const field = definition.sharedStratumField;
    const baselineValues = new Set(baselinePool.map((sample) => sample[field]));
    const candidateValues = new Set(candidatePool.map((sample) => sample[field]));
    const sharedValues = new Set([...baselineValues].filter((value) => candidateValues.has(value)));
    baseline = baselinePool.filter((sample) => sharedValues.has(sample[field]));
    candidate = candidatePool.filter((sample) => sharedValues.has(sample[field]));
  }
  const outOfScopeSamples = {
    baseline: baselinePool.length - baseline.length,
    candidate: candidatePool.length - candidate.length,
  };
  const baselineGroups = new Map(groupedSummaries(baseline, definition.fields)
    .map((group) => [stableStringify(group.stratum), group]));
  const candidateGroups = new Map(groupedSummaries(candidate, definition.fields)
    .map((group) => [stableStringify(group.stratum), group]));
  const keys = [...new Set([...baselineGroups.keys(), ...candidateGroups.keys()])].sort();
  const totalSamples = baseline.length + candidate.length;
  const layers = keys.map((key) => {
    const baselineGroup = baselineGroups.get(key);
    const candidateGroup = candidateGroups.get(key);
    const baselineSamples = baselineGroup ? baselineGroup.samples : [];
    const candidateSamples = candidateGroup ? candidateGroup.samples : [];
    const baselineValues = baselineSamples.sort((left, right) => left.sampleKey.localeCompare(right.sampleKey))
      .map((sample) => sample.chip);
    const candidateValues = candidateSamples.sort((left, right) => left.sampleKey.localeCompare(right.sampleKey))
      .map((sample) => sample.chip);
    const baselineMean = mean(baselineValues);
    const candidateMean = mean(candidateValues);
    return {
      key,
      stratum: (baselineGroup || candidateGroup).stratum,
      baselineRows: baselineSamples,
      candidateRows: candidateSamples,
      baselineSamples: baselineValues.length,
      candidateSamples: candidateValues.length,
      weight: totalSamples ? (baselineValues.length + candidateValues.length) / totalSamples : 0,
      baselineMeanChip: baselineMean,
      candidateMeanChip: candidateMean,
      effect: baselineMean === null || candidateMean === null ? null : candidateMean - baselineMean,
      baselineValues,
      candidateValues,
    };
  });
  const reasons = [...(options.cohortsQualified ? [] : ["unqualified_cohorts"])];
  if (!baseline.length) reasons.push("missing_baseline_samples");
  if (!candidate.length) reasons.push("missing_candidate_samples");
  if (definition.sharedStratumField && baselinePool.length && candidatePool.length
      && (!baseline.length || !candidate.length)) reasons.push("no_shared_stratification_values");
  const unmatchedSamples = layers.reduce((sum, layer) => sum
    + (layer.baselineSamples === 0 ? layer.candidateSamples : 0)
    + (layer.candidateSamples === 0 ? layer.baselineSamples : 0), 0);
  if (unmatchedSamples > 0) reasons.push("unmatched_strata");
  const qualified = reasons.length === 0 && layers.length > 0;
  const seed = comparisonSeed(options.seed, options.side, definition.id);
  let effect = null;
  let ci95 = { lower: null, upper: null, confidence: CONFIDENCE, method: "percentile" };
  if (qualified) {
    effect = layers.reduce((sum, layer) => sum + layer.weight * layer.effect, 0);
    const random = mulberry32(seed);
    const bootstrapEffects = [];
    for (let iteration = 0; iteration < options.iterations; iteration += 1) {
      let bootstrapEffect = 0;
      for (const layer of layers) {
        const baselineMean = resampleMean(layer.baselineValues, random);
        const candidateMean = resampleMean(layer.candidateValues, random);
        bootstrapEffect += layer.weight * (candidateMean - baselineMean);
      }
      bootstrapEffects.push(bootstrapEffect);
    }
    bootstrapEffects.sort((left, right) => left - right);
    ci95 = {
      lower: quantile(bootstrapEffects, 0.025),
      upper: quantile(bootstrapEffects, 0.975),
      confidence: CONFIDENCE,
      method: "percentile",
    };
  }
  return {
    comparisonId: definition.id,
    candidateSide: options.side,
    baselineVariant: definition.baseline,
    candidateVariant: definition.candidate,
    baselineFilter: definition.baselineFilter || null,
    candidateFilter: definition.candidateFilter || null,
    sharedStratumField: definition.sharedStratumField || null,
    effectDefinition: "candidate mean opponent chip - baseline mean opponent chip; positive favors elite",
    attribution: definition.attribution,
    stratificationFields: definition.fields,
    sampleCount: { baseline: baseline.length, candidate: candidate.length, total: totalSamples },
    poolSampleCount: { baseline: baselinePool.length, candidate: candidatePool.length },
    outOfScopeSamples,
    unmatchedSamples,
    layers: layers.map((layer) => ({
      stratum: layer.stratum,
      baselineSamples: layer.baselineSamples,
      candidateSamples: layer.candidateSamples,
      weight: layer.weight,
      baselineMeanChip: layer.baselineMeanChip,
      candidateMeanChip: layer.candidateMeanChip,
      effect: layer.effect,
    })),
    pairedContrast: definition.pairedContrastRequired ? buildPairedContrast(layers, options, definition) : null,
    layerWeightSum: layers.reduce((sum, layer) => sum + layer.weight, 0),
    effect,
    ci95,
    bootstrap: {
      iterations: options.iterations,
      seed,
      baseSeed: options.seed,
      algorithm: "mulberry32-uint32",
      method: "stratified independent percentile bootstrap",
      independentWithinArmAndStratum: true,
      pairedByRepeatIndex: false,
    },
    qualification: { qualified, reasons },
    qualified,
  };
}

function analyzeSide(samples, side, options) {
  const sideSamples = samples.filter((sample) => sample.candidateSide === side);
  const variants = groupedSummaries(sideSamples, ["variant"]).map((group) => ({
    variant: group.stratum.variant,
    ...summarizeSamples(group.samples),
  }));
  return {
    candidateSide: side,
    role: side === "red" ? "primary" : "separate-friendly-hp-context",
    samples: sideSamples.length,
    metric: "opponent chip = 1 - opponent remainHp / opponent startMaxHp",
    stratificationDimensions: STRATIFICATION_DIMENSIONS,
    variants,
    strata: buildDescriptiveStrata(sideSamples),
    comparisons: COMPARISONS.map((definition) => compareVariants(sideSamples, definition, {
      ...options,
      side,
    })),
  };
}

function normalizeBootstrap(options = {}) {
  const source = options.bootstrap || options;
  const iterations = source.iterations === undefined ? DEFAULT_BOOTSTRAP_ITERATIONS : source.iterations;
  const seed = source.seed === undefined ? DEFAULT_SEED : source.seed;
  if (!Number.isSafeInteger(iterations) || iterations < DEFAULT_BOOTSTRAP_ITERATIONS) {
    throw Error("bootstrap iterations must be an integer of at least 10000");
  }
  if (!Number.isSafeInteger(seed) || seed < 0 || seed > 0xFFFFFFFF) {
    throw Error("bootstrap seed must be a uint32 integer");
  }
  return { iterations, seed };
}

function summarizeCohorts(cohorts, options = {}) {
  if (!Array.isArray(cohorts) || cohorts.length === 0) throw Error("At least one cohort is required");
  const ids = new Set();
  for (const cohort of cohorts) {
    if (!cohort || typeof cohort.cohortId !== "string" || ids.has(cohort.cohortId)) {
      throw Error("Cohort ids must be present and unique");
    }
    ids.add(cohort.cohortId);
  }
  const minimumPairsPerLayer = options.minimumPairsPerLayer === undefined ? 30 : options.minimumPairsPerLayer;
  if (!Number.isSafeInteger(minimumPairsPerLayer) || minimumPairsPerLayer < 1) {
    throw Error("minimumPairsPerLayer must be a positive integer");
  }
  const bootstrap = normalizeBootstrap(options);
  const inspected = cohorts.map(inspectCohort);
  const cohortReports = inspected.map((entry) => entry.report);
  const cohortsQualified = cohortReports.every((report) => report.qualified);
  const samples = inspected.flatMap((entry) => entry.samples);
  const red = analyzeSide(samples, "red", { ...bootstrap, cohortsQualified, minimumPairsPerLayer });
  const blue = analyzeSide(samples, "blue", { ...bootstrap, cohortsQualified, minimumPairsPerLayer });
  const primary = red.comparisons.find((comparison) => comparison.comparisonId === "ordinary-vs-elite-overall");
  const primaryPairedContrastQualified = primary !== undefined && primary.pairedContrast.qualified;
  const primaryComparisonsQualified = red.comparisons.every((comparison) => comparison.qualified
    && (comparison.pairedContrast === null || comparison.pairedContrast.qualified));
  const structurallyQualified = cohortsQualified && primaryComparisonsQualified && primaryPairedContrastQualified;
  const performanceGatePassed = structurallyQualified && primary.ci95.lower > 0
    && primary.pairedContrast.ci95.lower > 0 && primary.layers.every((layer) => layer.effect > 0);
  return {
    schema: SCHEMA,
    generatedAt: new Date().toISOString(),
    metric: {
      name: "chip",
      formula: "1 - remainHp / startMaxHp",
      measuredOn: "the opponent of the candidate; ownChip is reported separately",
      rawHpFields: ["startMaxHp", "remainHp"],
      finishedIncluded: true,
      naturalTimeoutIncluded: true,
      naturalTimeoutDefinition: "status=timeout, winner=timeout, zero errors, positive duration, frames=manifest timeoutFrames",
      timeoutCountsAsWinOrLoss: false,
      primaryCandidateSide: "red",
      blueCandidateSide: "separate",
    },
    qualification: {
      qualified: structurallyQualified,
      performanceGatePassed,
      cohortsQualified,
      primaryComparisonsQualified,
      primaryPairedContrastQualified,
      minimumPairsPerLayer,
      cohortCount: cohortReports.length,
      qualifiedCohortCount: cohortReports.filter((report) => report.qualified).length,
      observedRows: cohortReports.reduce((sum, report) => sum + report.observedRows, 0),
      expectedRows: cohortReports.reduce((sum, report) => sum + (report.expectedRows || 0), 0),
      disqualificationScope: "any invalid, polluted, missing or duplicate row disqualifies its entire cohort",
    },
    cohorts: cohortReports,
    analyses: { red, blue },
    bootstrap: {
      iterations: bootstrap.iterations,
      baseSeed: bootstrap.seed,
      confidence: CONFIDENCE,
      algorithm: "mulberry32-uint32 with comparison-specific SHA-256 seed derivation",
      independentWithinArmAndStratum: true,
      pairedByComparisonKeyAndRepeatIndex: true,
      noPairwiseRngClaim: true,
      layerWeights: "fixed combined arm sample counts within each comparison stratum",
    },
    evidenceBoundary: {
      staticSummaryOnly: true,
      combatExecutedByThisTool: false,
      fullEffectivePanelEqualityClaim: "not-claimed",
      passiveMatchScope: "standard equipment weight and cross-slot projections only",
      blueFriendlyHpMultiplierReportedSeparately: true,
    },
  };
}

function parseArgs(argv) {
  const args = { check: false, iterations: undefined, seed: undefined };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") args.check = true;
    else if (token === "--config") args.config = argv[++index];
    else if (token === "--manifest") args.manifest = argv[++index];
    else if (token === "--input") args.input = argv[++index];
    else if (token === "--cohort-id") args.cohortId = argv[++index];
    else if (token === "--output") args.output = argv[++index];
    else if (token === "--iterations") args.iterations = Number(argv[++index]);
    else if (token === "--seed") args.seed = Number(argv[++index]);
    else if (token === "--minimum-pairs-per-layer") args.minimumPairsPerLayer = Number(argv[++index]);
    else if (token === "--help" || token === "-h") args.help = true;
    else throw Error(`Unknown argument: ${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`Usage:
  node tools/cf6-soldier-assets/elite-arena-summary.js --check
  node tools/cf6-soldier-assets/elite-arena-summary.js --manifest <manifest.json> --input <results.jsonl> [--cohort-id id] [--output summary.json]
  node tools/cf6-soldier-assets/elite-arena-summary.js --config <cohorts.json> [--output summary.json]

Config: {cohorts:[{cohortId,manifestPath,resultPath}], bootstrap:{iterations:10000,seed:20261017},minimumPairsPerLayer:30}.
Config-relative paths are supported. Bootstrap iterations must be at least 10000. Pairing uses comparisonKey and repeatIndex without a shared-RNG claim.`);
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }
  let cohorts;
  let configBootstrap = {};
  let configuredMinimumPairs;
  if (args.config) {
    if (args.manifest || args.input || args.cohortId) throw Error("--config cannot be combined with direct cohort arguments");
    const configPath = path.resolve(args.config);
    const config = readJson(configPath);
    if (!Array.isArray(config.cohorts)) throw Error("Config requires a cohorts array");
    cohorts = config.cohorts.map((spec) => loadCohort(spec, path.dirname(configPath)));
    configBootstrap = config.bootstrap || {};
    configuredMinimumPairs = config.minimumPairsPerLayer;
  } else {
    if (!args.manifest || !args.input) throw Error("--manifest and --input are required unless --config or --check is used");
    cohorts = [loadCohort({
      cohortId: args.cohortId || "elite-arena",
      manifestPath: args.manifest,
      resultPath: args.input,
    })];
  }
  const summary = summarizeCohorts(cohorts, {
    bootstrap: {
      iterations: args.iterations === undefined ? configBootstrap.iterations : args.iterations,
      seed: args.seed === undefined ? configBootstrap.seed : args.seed,
    },
    minimumPairsPerLayer: args.minimumPairsPerLayer === undefined ? configuredMinimumPairs : args.minimumPairsPerLayer,
  });
  if (args.output) {
    const outputPath = path.resolve(args.output);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(path.toNamespacedPath(outputPath), `${JSON.stringify(summary, null, 2)}\n`, { flag: "wx" });
    console.log(JSON.stringify({
      schema: summary.schema,
      qualified: summary.qualification.qualified,
      cohorts: summary.cohorts.length,
      rows: summary.qualification.observedRows,
      output: outputPath,
    }, null, 2));
  } else {
    console.log(JSON.stringify(summary, null, 2));
  }
  if (!summary.qualification.qualified) process.exitCode = 1;
}

module.exports = {
  COMPARISONS,
  DEFAULT_BOOTSTRAP_ITERATIONS,
  DEFAULT_SEED,
  STRATIFICATION_DIMENSIONS,
  compareVariants,
  inspectCohort,
  loadCohort,
  main,
  normalizeBootstrap,
  stableStringify,
  summarizeCohorts,
  summarizeSamples,
};

if (require.main === module) {
  try {
    if (process.argv.length === 3 && process.argv[2] === "--check") {
      const { run } = require("./test-elite-arena");
      console.log(JSON.stringify(run(), null, 2));
    } else {
      main(process.argv.slice(2));
    }
  } catch (error) {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  }
}
