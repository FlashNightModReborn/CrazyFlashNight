#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { normalizeManifest } = require("../arena-calibration/lib/arena-calibration-core");
const {
  ROOT,
  SOURCE_PATHS,
  buildCases,
  create: createArenaPlan,
  validateAuthorities,
} = require("./elite-arena-plan");
const { WORKER_SOURCE_PATHS, createPlan } = require("./elite-worker-plan");
const {
  inspectCohort,
  loadCohort,
  normalizeBootstrap,
  summarizeCohorts,
} = require("./elite-arena-summary");

function fixtureManifest() {
  const comparisons = [];
  for (const distance of [650, 700]) {
    comparisons.push(
      { id: `ordinary-${distance}`, pairKey: String(distance), variant: "ordinary", opponentId: 464, distance, repeat: 2 },
      { id: `elite-${distance}`, pairKey: String(distance), variant: "elite", opponentId: 464, distance, repeat: 2 },
      { id: `ordinary-matched-${distance}`, pairKey: String(distance), variant: "ordinary", opponentId: 464, distance, repeat: 2,
        sidearm: "FR506", sidearm2: "FR506", toughnessCoefficient: 50 },
      { id: `no-sidearm-${distance}`, pairKey: String(distance), variant: "noSidearm", opponentId: 464, distance, repeat: 2 },
    );
  }
  comparisons.push(
    { id: "blue-ordinary", variant: "ordinary", opponentId: 464, side: "blue" },
    { id: "blue-elite", variant: "elite", opponentId: 464, side: "blue" },
  );
  return normalizeManifest({
    batchId: "elite-summary-fixture",
    createdAt: "2026-10-17T00:00:00.000Z",
    buildCommit: "fixture",
    planner: { name: "elite-summary-fixture", version: 1 },
    repeat: 1,
    timeoutFrames: 1800,
    cases: buildCases(comparisons, { sourceBindings: [] }),
  });
}

function fixtureChip(testCase, repeatIndex) {
  const context = testCase.authorityContext;
  const bases = { ordinary: 0.2, elite: 0.5, noSidearm: 0.4 };
  let chip = bases[context.variant];
  if (context.variant === "ordinary" && context.equipmentProfile === "custom") chip = 0.3;
  if (context.candidateSide === "blue") chip -= 0.05;
  return chip + (repeatIndex - 1) * 0.02 + (testCase.spawnDistance === 700 ? 0.01 : 0);
}

function sideHp(startMaxHp, chip) {
  return {
    maxHp: startMaxHp,
    remainHp: startMaxHp * (1 - chip),
    aliveCount: chip >= 1 ? 0 : 1,
    startMaxHp,
    startCount: 1,
  };
}

function fixtureRow(manifest, testCase, repeatIndex) {
  const context = testCase.authorityContext;
  const timeout = repeatIndex === 2;
  const chip = fixtureChip(testCase, repeatIndex);
  const opponent = sideHp(1000, chip);
  const own = sideHp(context.candidateSide === "blue" ? 3000 : 1000, 0.2);
  return {
    schema: "arena-calibration.result.v1",
    batchId: manifest.batchId,
    manifestHash: manifest.manifestHash,
    caseId: testCase.caseId,
    caseHash: testCase.caseHash,
    runId: `${testCase.caseId}-r${repeatIndex}`,
    repeatIndex,
    status: timeout ? "timeout" : "finished",
    winner: timeout ? "timeout" : context.candidateSide,
    frames: timeout ? testCase.timeoutFrames : 900,
    durationMs: timeout ? 60000 : 30000,
    requestedSpawnDistance: testCase.spawnDistance,
    spawnDistance: testCase.spawnDistance,
    blueFormation: "line",
    redFormation: "line",
    formationSpacing: 54,
    authorityContext: testCase.authorityContext,
    blue: context.candidateSide === "blue" ? own : opponent,
    red: context.candidateSide === "red" ? own : opponent,
    errors: [],
    startedAt: "2026-10-17T00:00:00.000Z",
    completedAt: "2026-10-17T00:01:00.000Z",
  };
}

function fixtureRows(manifest) {
  return manifest.cases.flatMap((testCase) => Array.from({ length: testCase.repeat }, (_unused, index) =>
    fixtureRow(manifest, testCase, index + 1)));
}

function closeTo(actual, expected, label) {
  assert(Math.abs(actual - expected) < 1e-12, `${label}: expected ${expected}, got ${actual}`);
}

function comparison(summary, side, id) {
  return summary.analyses[side].comparisons.find((entry) => entry.comparisonId === id);
}

function checkPlan() {
  const authorities = validateAuthorities();
  assert.deepStrictEqual(authorities.fireEventCounts, {
    retreat: { primary: 4, secondary: 4 },
    stand: { primary: 5, secondary: 0 },
    run: { primary: 8, secondary: 0 },
    slide: { primary: 5, secondary: 0 },
  });
  for (const required of [
    "tools/cf6-soldier-assets/elite.py",
    "tools/cf6-soldier-assets/elite_anatomy.py",
    "tools/cf6-soldier-assets/elite-motion-profile.json",
    "tools/cf6-soldier-assets/EliteAI.as",
    "tools/cf6-soldier-assets/SoldierRoles.as",
    "tools/cf6-soldier-assets/TacticalAI.as",
    "tools/cf6-soldier-assets/tactical-profiles.json",
    "data/items/武器_手枪_大威力手枪.xml",
    "tools/cf6-soldier-assets/elite-campaign.js",
    "flashswf/arts/new/Codex特种兵素材.swf",
    "flashswf/arts/new/CodexWings素材.swf",
    "flashswf/arts/new/Codex大刀机器人素材.swf",
    "tools/cf6-bladebot-assets/BladebotAI.as",
    "scripts/asLoader.swf",
    "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as",
    "scripts/逻辑/单位函数/单位函数_lsy_主角射击函数.as",
  ]) assert(SOURCE_PATHS.includes(required), `missing source binding ${required}`);
  const variants = ["ordinary", "elite", "stationary", "ordinaryBrain", "noSidearm", "shieldOrdinary", "shieldElite"];
  const cases = buildCases(variants.map((variant) => ({
    id: `variant-${variant}`,
    variant,
    opponentId: 464,
    sidearm: "FR506", sidearm2: "FR506",
    toughnessCoefficient: 50,
  })), { sourceBindings: [] });
  assert.strictEqual(cases.length, variants.length);
  for (const testCase of cases) {
    const context = testCase.authorityContext;
    assert.strictEqual(context.sidearm, "FR506");
    assert.strictEqual(context.passiveMatched, true);
    assert.strictEqual(context.fullEffectivePanelEqualityClaim, "not-claimed");
    assert.strictEqual(context.noPairwiseRngClaim, true);
    assert.strictEqual(context.blueFriendlyHpMultiplierReportedSeparately, true);
    assert.strictEqual(testCase.redRoster[0].parameters["手枪"], "FR506");
    assert.strictEqual(testCase.repeat, 1);
    assert.strictEqual(testCase.timeoutFrames, 1800);
  }
  const elite = cases.find((testCase) => testCase.authorityContext.variant === "elite");
  const ablated = cases.find((testCase) => testCase.authorityContext.variant === "noSidearm");
  assert.deepStrictEqual(ablated.redRoster[0].parameters, {
    ...elite.redRoster[0].parameters,
    "特种兵精英消融": "noSidearm",
  });
  assert.strictEqual(elite.authorityContext.matchKey, ablated.authorityContext.matchKey);
  assert.strictEqual(ablated.authorityContext.sidearmBehavior, "disabled-noSidearm");
  assert.strictEqual(ablated.authorityContext.dualWieldState, "equipped-ablated-noSidearm");
  assert.strictEqual(cases.find((testCase) => testCase.authorityContext.variant === "shieldOrdinary")
    .redRoster[0].type, "兵种467");
  const shieldElite = cases.find((testCase) => testCase.authorityContext.variant === "shieldElite");
  assert.strictEqual(shieldElite.redRoster[0].type, "兵种479");
  assert.strictEqual(shieldElite.authorityContext.dualWieldState, "equipped-phase2-only");
  for (const field of ["repeat", "timeoutFrames"]) {
    for (const value of [0, -1, 1.5, "1", null]) {
      assert.throws(() => buildCases([{ id: "invalid", variant: "elite", opponentId: 464, [field]: value }],
        { sourceBindings: [] }), /positive integer/, `${field}=${value} was accepted`);
    }
  }
  assert.throws(() => buildCases([{ id: "strip", variant: "noSidearm", opponentId: 464, sidearm: null }],
    { sourceBindings: [] }), /retain FR506/);
  assert.throws(() => buildCases([{ id: "distance", variant: "elite", opponentId: 464, distance: 0 }],
    { sourceBindings: [] }), /positive integer/);
}

function checkSinglePlanOutput() {
  const temporary = fs.mkdtempSync(path.join(ROOT, "tmp", "elite-single-plan-fixture-"));
  try {
    const candidateRoot = path.join(ROOT, "tmp", "runtime-candidates", "v2", `${path.basename(temporary)}-not-built`);
    const result = createArenaPlan({
      candidateRoot,
      outputDirectory: path.join(temporary, "plan"),
      batchId: "elite-single-fixture",
      comparisons: [
        { id: "single-ordinary", variant: "ordinary", opponentId: 464 },
        { id: "single-elite", variant: "elite", opponentId: 464 },
        { id: "single-no-sidearm", variant: "noSidearm", opponentId: 464 },
      ],
    }, { sourceBindings: [], buildCommit: "F".repeat(40) });
    assert.strictEqual(result.rows, 3);
    assert.strictEqual(result.worstCaseMs, 180000);
    const manifest = JSON.parse(fs.readFileSync(result.manifestPath, "utf8"));
    assert.strictEqual(manifest.planner.name, "cf6-elite-controlled-comparison");
    assert.strictEqual(manifest.cases.length, 3);
    const identity = JSON.parse(fs.readFileSync(path.join(path.dirname(result.manifestPath), "source-identity.json"), "utf8"));
    assert.strictEqual(identity.fullEffectivePanelEqualityClaim, "not-claimed");
    const evidence = JSON.parse(fs.readFileSync(path.join(path.dirname(result.manifestPath), "evidence-config.json"), "utf8"));
    assert.strictEqual(evidence.resourceRoot, ROOT);
    assert.strictEqual(evidence.candidateRoot, candidateRoot);
    assert.strictEqual(evidence.manifestPath, result.manifestPath);
    assert.strictEqual(evidence.slot, "cf7_agent_elite_single_fixture");
    assert.strictEqual(evidence.allowNaturalTimeout, true);
    return { singlePlanFiles: 3 };
  } finally {
    assert(path.resolve(temporary).startsWith(path.join(ROOT, "tmp") + path.sep));
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

function checkCohortRejection(manifest, rows) {
  const valid = inspectCohort({ cohortId: "valid", manifest, rows });
  assert.strictEqual(valid.report.qualified, true, valid.report.reasons.join("\n"));
  assert.strictEqual(valid.samples.length, rows.length);
  for (const status of ["error", "bridge_lost", "spawn_failed", "contamination"]) {
    const changed = rows.map((row) => ({ ...row }));
    changed[0].status = status;
    const inspected = inspectCohort({ cohortId: `bad-${status}`, manifest, rows: changed });
    assert.strictEqual(inspected.report.qualified, false);
    assert(inspected.report.reasons.some((reason) => reason.includes(`disqualifying_status:${status}`)));
    assert.strictEqual(inspected.samples.length, 0, "an invalid cohort must not leak valid-looking rows");
  }
  const missing = inspectCohort({ cohortId: "missing", manifest, rows: rows.slice(1) });
  assert.strictEqual(missing.report.qualified, false);
  assert(missing.report.reasons.some((reason) => reason.startsWith("missing_case_repeat:")));
  const duplicate = inspectCohort({ cohortId: "duplicate", manifest, rows: [...rows, { ...rows[0] }] });
  assert.strictEqual(duplicate.report.qualified, false);
  assert(duplicate.report.reasons.some((reason) => reason.startsWith("duplicate_runId:")));
  const nonNatural = rows.map((row) => ({ ...row }));
  nonNatural[1].frames -= 1;
  const timeout = inspectCohort({ cohortId: "timeout", manifest, rows: nonNatural });
  assert.strictEqual(timeout.report.qualified, false);
  assert(timeout.report.reasons.some((reason) => reason.startsWith("non_natural_timeout:")));
  const rawHp = rows.map((row) => ({ ...row, blue: { ...row.blue }, red: { ...row.red } }));
  delete rawHp[0].blue.startMaxHp;
  const invalidHp = inspectCohort({ cohortId: "hp", manifest, rows: rawHp });
  assert.strictEqual(invalidHp.report.qualified, false);
  assert(invalidHp.report.reasons.some((reason) => reason.startsWith("invalid_raw_hp:")));
  const context = rows.map((row) => ({ ...row, authorityContext: { ...row.authorityContext } }));
  context[0].authorityContext.weapon = "unbound-weapon";
  const invalidContext = inspectCohort({ cohortId: "context", manifest, rows: context });
  assert.strictEqual(invalidContext.report.qualified, false);
  assert(invalidContext.report.reasons.some((reason) => reason.startsWith("authority_context_mismatch:")));
}

function checkSummary(manifest, rows) {
  const cohort = { cohortId: "fixture", manifest, rows };
  const options = { bootstrap: { iterations: 10000, seed: 123456789 }, minimumPairsPerLayer: 2 };
  const summary = summarizeCohorts([cohort], options);
  assert.strictEqual(summary.qualification.cohortsQualified, true);
  assert.strictEqual(summary.qualification.qualified, true);
  assert.strictEqual(summary.qualification.observedRows, 18);
  assert.strictEqual(summary.analyses.red.role, "primary");
  assert.strictEqual(summary.analyses.blue.role, "separate-friendly-hp-context");
  assert.strictEqual(summary.analyses.red.samples, 16);
  assert.strictEqual(summary.analyses.blue.samples, 2);
  const overall = comparison(summary, "red", "ordinary-vs-elite-overall");
  const sameToughness = comparison(summary, "red", "ordinary-vs-elite-same-toughness");
  const sidearm = comparison(summary, "red", "elite-vs-no-sidearm");
  for (const entry of [overall, sameToughness, sidearm]) {
    assert.strictEqual(entry.qualified, true, entry.qualification.reasons.join(","));
    assert.strictEqual(entry.bootstrap.iterations, 10000);
    assert.strictEqual(entry.bootstrap.pairedByRepeatIndex, false);
    assert.strictEqual(entry.bootstrap.independentWithinArmAndStratum, true);
    assert.strictEqual(entry.layers.length, 2);
    closeTo(entry.layerWeightSum, 1, `${entry.comparisonId} weights`);
    assert(entry.ci95.lower <= entry.effect && entry.effect <= entry.ci95.upper);
  }
  assert.strictEqual(overall.pairedContrast.qualified, true, overall.pairedContrast.qualification.reasons.join(","));
  assert.strictEqual(overall.pairedContrast.pairedSamples, 4);
  assert.strictEqual(overall.pairedContrast.bootstrap.sharedRng, false);
  assert.strictEqual(overall.pairedContrast.bootstrap.pairedByComparisonKeyAndRepeatIndex, true);
  assert(overall.pairs === undefined);
  for (const pair of overall.pairedContrast.pairs) {
    const baseline = rows.find((row) => row.caseId === pair.baselineSampleKey.split("|")[1].replace(/-r\d+$/, ""));
    assert(baseline);
    closeTo(pair.effect, pair.candidateChip - pair.baselineChip, "paired effect");
  }
  closeTo(overall.pairedContrast.effect, overall.effect, "paired and independent point effects agree");
  assert.strictEqual(summary.qualification.primaryPairedContrastQualified, true);
  assert.strictEqual(summary.qualification.performanceGatePassed, true);
  assert.strictEqual(sameToughness.pairedContrast, null);
  closeTo(overall.effect, 0.3, "overall stock effect");
  closeTo(sameToughness.effect, 0.2, "same toughness effect");
  closeTo(sidearm.effect, 0.1, "sidearm behavior effect");
  assert.deepStrictEqual(sameToughness.outOfScopeSamples, { baseline: 4, candidate: 0 });
  assert.deepStrictEqual(sidearm.outOfScopeSamples, { baseline: 0, candidate: 0 });
  const elite = summary.analyses.red.variants.find((entry) => entry.variant === "elite");
  assert.strictEqual(elite.samples, 4);
  assert.strictEqual(elite.finished, 2);
  assert.strictEqual(elite.timeouts, 2);
  assert.strictEqual(elite.wins, 2);
  assert.strictEqual(elite.winRate, 1, "natural timeouts must not become losses or enter win/loss counts");
  closeTo(elite.meanChip, 0.515, "timeout chip inclusion");
  assert(summary.analyses.red.strata.every((entry) =>
    Object.hasOwn(entry.stratum, "opponentId") && Object.hasOwn(entry.stratum, "equipment")
    && Object.hasOwn(entry.stratum, "toughnessCoefficient") && Object.hasOwn(entry.stratum, "dualWieldState")
    && Object.hasOwn(entry.stratum, "spawnDistance") && Object.hasOwn(entry.stratum, "timeoutFrames")
    && Object.hasOwn(entry.stratum, "timeout")));
  const repeated = summarizeCohorts([cohort], options);
  assert.deepStrictEqual(repeated.analyses.red.comparisons, summary.analyses.red.comparisons,
    "same seed must reproduce every bootstrap interval");
  const shuffled = rows.map((row) => ({ ...row }));
  for (const testCase of manifest.cases.filter((entry) => entry.repeat === 2)) {
    const indices = shuffled.flatMap((row, index) => row.caseId === testCase.caseId ? [index] : []);
    const first = shuffled[indices[0]].repeatIndex;
    shuffled[indices[0]].repeatIndex = shuffled[indices[1]].repeatIndex;
    shuffled[indices[1]].repeatIndex = first;
  }
  const relabeled = summarizeCohorts([{ cohortId: "fixture", manifest, rows: shuffled }], options);
  const relabeledOverall = comparison(relabeled, "red", "ordinary-vs-elite-overall");
  assert.deepStrictEqual(relabeledOverall.layers, overall.layers,
    "repeatIndex relabeling preserves the independent estimate");
  assert.deepStrictEqual(relabeledOverall.ci95, overall.ci95);
  assert.deepStrictEqual(relabeledOverall.pairedContrast.ci95, overall.pairedContrast.ci95);
  const pairIdentities = (entry) => entry.pairedContrast.pairs.map((pair) => JSON.stringify([
    pair.baselineSampleKey, pair.candidateSampleKey, pair.effect,
  ])).sort();
  assert.deepStrictEqual(pairIdentities(relabeledOverall), pairIdentities(overall),
    "paired identities are unchanged even when their output order changes");
  const changedRows = shuffled.map((row) => ({ ...row, blue: { ...row.blue }, red: { ...row.red } }));
  const changed = changedRows.find((row) => row.runId === "elite-650-r2");
  changed.blue.remainHp = 0;
  const changedSummary = summarizeCohorts([{ cohortId: "fixture", manifest, rows: changedRows }], options);
  const changedOverall = comparison(changedSummary, "red", "ordinary-vs-elite-overall");
  const changedPair = changedOverall.pairedContrast.pairs.find((pair) =>
    pair.candidateSampleKey.endsWith("|elite-650-r2"));
  closeTo(changedPair.candidateChip, 1, "paired candidate is bound to the changed raw row");
  closeTo(changedOverall.pairedContrast.effect, changedOverall.effect, "paired and independent effects still agree");
  assert.throws(() => normalizeBootstrap({ iterations: 9999 }), /at least 10000/);
  assert.throws(() => normalizeBootstrap({ iterations: 10000.5 }), /at least 10000/);
  assert.throws(() => normalizeBootstrap({ seed: -1 }), /uint32/);
  const invalidSummary = summarizeCohorts([{ cohortId: "fixture", manifest, rows: rows.slice(1) }], options);
  assert.strictEqual(invalidSummary.qualification.cohortsQualified, false);
  assert.strictEqual(invalidSummary.qualification.qualified, false);
  assert(invalidSummary.analyses.red.comparisons.every((entry) => !entry.qualified));
  return { overallEffect: overall.effect, sameToughnessEffect: sameToughness.effect, sidearmEffect: sidearm.effect };
}

function checkPairedRejection() {
  const makeCohort = (id, comparisons) => {
    const manifest = normalizeManifest({
      batchId: id, createdAt: "2026-10-17T00:00:00.000Z", buildCommit: "fixture",
      planner: { name: "elite-pairing-fixture", version: 1 },
      repeat: 1, timeoutFrames: 1800, cases: buildCases(comparisons, { sourceBindings: [] }),
    });
    return { cohortId: id, manifest, rows: fixtureRows(manifest) };
  };
  const options = { bootstrap: { iterations: 10000, seed: 123456789 }, minimumPairsPerLayer: 1 };
  const missing = summarizeCohorts([makeCohort("missing-pair", [
    { id: "ordinary", pairKey: "a", variant: "ordinary", opponentId: 449 },
    { id: "elite", pairKey: "b", variant: "elite", opponentId: 449 },
  ])], options);
  const missingOverall = comparison(missing, "red", "ordinary-vs-elite-overall");
  assert(missing.qualification.cohortsQualified);
  assert(missingOverall.qualified);
  assert(!missingOverall.pairedContrast.qualified);
  assert(missingOverall.pairedContrast.qualification.reasons.some((reason) => reason.startsWith("unmatched_comparison_pair:")));
  assert(!missing.qualification.qualified);
  const duplicate = summarizeCohorts([makeCohort("duplicate-pair", [
    { id: "ordinary", pairKey: "a", variant: "ordinary", opponentId: 449 },
    { id: "elite-a", pairKey: "a", variant: "elite", opponentId: 449, repeat: 2 },
    { id: "elite-b", pairKey: "a", variant: "elite", opponentId: 449 },
  ])], options);
  const duplicateOverall = comparison(duplicate, "red", "ordinary-vs-elite-overall");
  assert(duplicateOverall.qualified);
  assert(!duplicateOverall.pairedContrast.qualified);
  assert(duplicateOverall.pairedContrast.qualification.reasons.some((reason) => reason.startsWith("duplicate_comparison_pair:")));
  assert(!duplicate.qualification.qualified);
}

function checkRawJsonl(manifest, rows) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "cf6-elite-summary-"));
  try {
    const manifestPath = path.join(temporary, "manifest.json");
    const resultPath = path.join(temporary, "results.jsonl");
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    fs.writeFileSync(resultPath, `${rows.map((row) => JSON.stringify(row)).join("\n")}\n`);
    const cohort = loadCohort({ cohortId: "raw", manifestPath, resultPath });
    const inspected = inspectCohort(cohort);
    assert.strictEqual(inspected.report.qualified, true, inspected.report.reasons.join("\n"));
    assert.strictEqual(inspected.samples.length, 18);
    assert(/^[a-f0-9]{64}$/.test(inspected.report.resultSha256));
    const outputPath = path.join(temporary, "summary.json");
    const cli = childProcess.spawnSync(process.execPath, [
      path.join(__dirname, "elite-arena-summary.js"),
      "--manifest", manifestPath,
      "--input", resultPath,
      "--cohort-id", "raw-cli",
      "--output", outputPath,
      "--seed", "123456789",
      "--minimum-pairs-per-layer", "2",
    ], { cwd: ROOT, encoding: "utf8", windowsHide: true });
    assert.strictEqual(cli.status, 0, `${cli.stdout}\n${cli.stderr}\n${cli.error || ""}`);
    const cliSummary = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.strictEqual(cliSummary.qualification.qualified, true);
    closeTo(cliSummary.analyses.red.comparisons.find((entry) =>
      entry.comparisonId === "ordinary-vs-elite-overall").effect, 0.3, "raw JSONL CLI effect");
    const malformedPath = path.join(temporary, "malformed.jsonl");
    fs.writeFileSync(malformedPath, "{not-json}\n");
    const malformed = inspectCohort(loadCohort({ cohortId: "malformed", manifestPath, resultPath: malformedPath }));
    assert.strictEqual(malformed.report.qualified, false);
    assert(malformed.report.reasons.some((reason) => reason.startsWith("result_json:1:")));
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

function checkWorkerPlan() {
  const temporary = fs.mkdtempSync(path.join(ROOT, "tmp", "elite-worker-fixture-"));
  try {
    const resourceListPath = path.join(temporary, "resources.json");
    fs.writeFileSync(resourceListPath, JSON.stringify({ resourcePaths: WORKER_SOURCE_PATHS }));
    const workerRoots = [1, 2].map((index) => path.join(temporary, `worker-${index}`));
    workerRoots.forEach((root) => fs.mkdirSync(root, { recursive: true }));
    const seedPath = path.join(temporary, "read-only-seed.json");
    fs.writeFileSync(seedPath, "{}\n");
    const config = (experimentId) => ({
      experimentId,
      outputDirectory: path.join(temporary, experimentId),
      resourceListPath,
      workers: workerRoots.map((projectRoot) => ({
        projectRoot,
        candidateRoot: path.join(projectRoot, "tmp", "runtime-candidates", "v2", "fixture-candidate"),
        seedPath,
      })),
    });
    const sourceRelative = (filePath) => {
      const normalized = path.resolve(filePath).replace(/\\/g, "/");
      const markers = ["/tools/", "/flashswf/", "/scripts/", "/data/"];
      const index = markers.map((marker) => normalized.indexOf(marker)).find((value) => value >= 0);
      assert(index !== undefined, `unrecognized fixture source path ${normalized}`);
      return normalized.slice(index + 1);
    };
    const fakeHash = (filePath) => crypto.createHash("sha256").update(sourceRelative(filePath)).digest("hex");
    const identity = (projectRoot, candidateRoot) => ({
      runtimeMode: "isolated_candidate",
      processPath: path.join(candidateRoot, "runtime", "Core.exe"),
      installRoot: candidateRoot,
      coreSha256: "A".repeat(64),
      buildIdentity: "B".repeat(64),
      payloadClosure: "C".repeat(64),
    });
    const dependencies = {
      hashFile: fakeHash,
      resolveRuntimeIdentity: identity,
      buildCommit: () => "F".repeat(40),
      appData: temporary,
    };
    const result = createPlan(config("worker-good"), dependencies);
    assert.strictEqual(result.rows, 12);
    assert.strictEqual(result.redRows, 12);
    assert.strictEqual(result.blueRows, 0);
    assert.strictEqual(result.workers, 2);
    assert.strictEqual(result.candidateExecuted, false);
    const plan = JSON.parse(fs.readFileSync(result.planPath, "utf8"));
    assert.strictEqual(plan.schema, "arena-worker.experiment-plan.v1");
    assert.strictEqual(plan.workers.length, 2);
    assert.notStrictEqual(plan.workers[0].projectRoot, plan.workers[1].projectRoot);
    assert.strictEqual(plan.groups.length, 1);
    assert.strictEqual(plan.groups[0].mode, "parallel");
    assert.strictEqual(plan.groups[0].jobs.length, 2);
    assert(plan.groups[0].jobs.every((job) => job.batchTimeoutMs === 900000));
    const manifests = result.manifestPaths.map((filePath) => JSON.parse(fs.readFileSync(filePath, "utf8")));
    const cases = manifests.flatMap((manifest) => manifest.cases);
    assert.strictEqual(cases.length, 4);
    assert(cases.every((testCase) => testCase.repeat === 3 && testCase.timeoutFrames === 1800));
    assert(cases.every((testCase) => testCase.authorityContext.opponentId === 464
      && testCase.authorityContext.opponentLevel === 60));
    const ordinaryMatched = cases.find((testCase) => testCase.authorityContext.variant === "ordinary"
      && testCase.authorityContext.equipmentProfile === "custom");
    const ordinaryStock = cases.find((testCase) => testCase.authorityContext.equipmentProfile === "ordinary-stock");
    const elite = cases.find((testCase) => testCase.authorityContext.variant === "elite");
    const ablated = cases.find((testCase) => testCase.authorityContext.variant === "noSidearm");
    assert.strictEqual(ordinaryMatched.authorityContext.passiveMatched, true);
    assert.strictEqual(ordinaryStock.authorityContext.passiveMatched, false);
    assert.strictEqual(elite.authorityContext.passiveMatched, true);
    assert.strictEqual(ablated.authorityContext.passiveMatched, true);
    assert.strictEqual(elite.authorityContext.matchKey, ordinaryMatched.authorityContext.matchKey);
    assert.strictEqual(elite.authorityContext.matchKey, ablated.authorityContext.matchKey);
    const identityEvidence = JSON.parse(fs.readFileSync(path.join(path.dirname(result.planPath), "input-identity.json"), "utf8"));
    assert.strictEqual(identityEvidence.sourceHashesMatched, true);
    assert.strictEqual(identityEvidence.candidateIdentityAndClosureMatched, true);
    assert.strictEqual(identityEvidence.candidateExecutedByPlanner, false);
    assert.strictEqual(identityEvidence.worktreeCreatedByPlanner, false);
    assert(identityEvidence.sourceBindings.some((binding) => binding.path === "tools/cf6-soldier-assets/elite.py"));
    assert(identityEvidence.sourceBindings.some((binding) => binding.path === "data/items/武器_手枪_大威力手枪.xml"));
    const sameRoot = config("worker-same-root");
    sameRoot.workers[1] = { ...sameRoot.workers[0] };
    assert.throws(() => createPlan(sameRoot, dependencies), /Independent resource roots/);
    assert.throws(() => createPlan(config("worker-source-mismatch"), {
      ...dependencies,
      hashFile: (filePath) => path.resolve(filePath).replace(/\\/g, "/").includes("/worker-2/") && filePath.endsWith("EliteAI.as")
        ? "0".repeat(64) : fakeHash(filePath),
    }), /Worker input differs/);
    assert.throws(() => createPlan(config("worker-identity-mismatch"), {
      ...dependencies,
      resolveRuntimeIdentity: (projectRoot, candidateRoot) => ({
        ...identity(projectRoot, candidateRoot),
        payloadClosure: projectRoot.includes("worker-2") ? "D".repeat(64) : "C".repeat(64),
      }),
    }), /Worker payloads differ: payloadClosure/);
    assert.throws(() => createPlan({ ...config("worker-zero-repeat"), repeat: 0 }, dependencies), /positive integer/);
    const wrongOpponent = config("worker-opponent-mismatch");
    wrongOpponent.profiles = [[{ variant: "ordinary", opponentId: 449 }], [{ variant: "elite" }]];
    assert.throws(() => createPlan(wrongOpponent, dependencies), /common opponent/);
    return { workerRows: result.rows, workerManifests: manifests.length, identityClosureMatched: true };
  } finally {
    assert(path.resolve(temporary).startsWith(path.join(ROOT, "tmp") + path.sep));
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

function checkNaturalTimeoutAcceptance() {
  const { validNaturalTimeout, acceptedRows } = require("./foreground-evidence");
  const testCase = { caseId: "match", timeoutFrames: 1800 };
  const manifest = { cases: [testCase] };
  const natural = { caseId: "match", status: "timeout", winner: "timeout", frames: 1800, durationMs: 60000, errors: [] };
  assert.strictEqual(validNaturalTimeout(natural, testCase), true);
  assert.strictEqual(validNaturalTimeout({ ...natural, frames: 1799 }, testCase), false);
  assert.strictEqual(validNaturalTimeout({ ...natural, errors: ["bridge_lost"] }, testCase), false);
  assert.strictEqual(acceptedRows([natural], 1, false, manifest), false);
  assert.strictEqual(acceptedRows([natural], 1, true, manifest), true);
  assert.strictEqual(acceptedRows([{ ...natural, status: "error" }], 1, true, manifest), false);
  assert.strictEqual(acceptedRows([natural], 2, true, manifest), false);
  assert.strictEqual(acceptedRows([{ caseId: "match", status: "finished", errors: [] }], 1, false, manifest), true);
}

function checkCampaign() {
  const { buildCampaign, reportOutput, execute } = require("./elite-campaign");
  // Synthetic planner input only: no local campaign files or combat runs.
  const protocol = {
    schema: "cf6-soldier.elite-arena-protocol.v1",
    matchRules: { primaryOpponents: [
      { unitId: 449, opponentWeapon: "M4A1战术版" },
      { unitId: 465, opponentWeapon: null },
    ] },
    phases: [
      { phase: "smoke", runsPerArmPerOpponent: 1 },
      { phase: "exploration", runsPerArmPerOpponent: 6 },
      { phase: "confirmation", runsPerArmPerOpponent: 30 },
    ],
    ablations: [
      { comparison: "same toughness", runsPerArm: 12 },
      { comparison: "sidearm", runsPerArm: 12 },
      { comparison: "mobility and brain", runsPerArmPerVariant: 8 },
      { comparison: "shield boundary", runsPerArm: 4 },
      { comparison: "side swap", runsPerArmPerOpponent: 4 },
    ],
  };
  const batches = buildCampaign(protocol, "r04");
  assert.strictEqual(batches.length, 30);
  assert.strictEqual(batches.reduce((sum, batch) => sum + batch.expectedRows, 0), 244);
  for (const batch of batches) {
    assert(batch.expectedRows <= 10);
    assert.strictEqual(batch.worstCaseMs <= 900000, true);
    if (["smoke", "exploration"].includes(batch.phase)) assert.strictEqual(batch.includeInSummary, false);
  }
  const output = "unrelated prefix\n" + JSON.stringify({ status: "completed", resultPath: "logs/arena-calibration/example.jsonl",
    report: "tmp/arena-calibration/example/run-report.json" }, null, 2) + "\nTemporary display request released: True";
  const parsed = reportOutput(output);
  assert.strictEqual(parsed.report.status, "completed");
  assert(parsed.reportPath.endsWith("run-report.json"));
  const temporary = fs.mkdtempSync(path.join(ROOT, "tmp", "elite-execute-test-"));
  try {
    const logPath = path.join(temporary, "run.log");
    for (const status of [0, 7]) {
      const result = execute("fixture-only", [], logPath, () => ({ status, stdout: output, stderr: "\nfixture stderr" }));
      assert.strictEqual(result.status, status);
      assert.strictEqual(fs.readFileSync(logPath, "utf8"), result.output);
      assert.strictEqual(reportOutput(result.output).reportPath, parsed.reportPath);
      if (status !== 0) assert.notStrictEqual(result.status, 0, "A report must not hide a failed process");
    }
    const failure = new Error("fixture spawn failure");
    assert.throws(() => execute("fixture-only", [], logPath, () => ({ error: failure, status: null, stderr: "failed to spawn" })),
      (error) => error === failure);
    assert.strictEqual(fs.readFileSync(logPath, "utf8"), "failed to spawn");
    assert.throws(() => reportOutput("no report emitted"), /did not emit a report path/);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

function run() {
  checkPlan();
  checkNaturalTimeoutAcceptance();
  checkCampaign();
  const manifest = fixtureManifest();
  const rows = fixtureRows(manifest);
  checkCohortRejection(manifest, rows);
  checkPairedRejection();
  const effects = checkSummary(manifest, rows);
  checkRawJsonl(manifest, rows);
  const single = checkSinglePlanOutput();
  const worker = checkWorkerPlan();
  return {
    ok: true,
    evidenceKind: "static_fixture",
    variants: 7,
    rawRows: rows.length,
    bootstrapIterations: 10000,
    independentResampling: true,
    comparisonKeyRepeatIndexPairing: true,
    noSharedRngClaim: true,
    naturalTimeoutChip: true,
    disqualifyingCohorts: ["error", "bridge_lost", "spawn_failed", "contamination", "missing", "duplicate"],
    ...effects,
    ...single,
    ...worker,
  };
}

if (require.main === module) {
  try {
    if (process.argv.length !== 3 || process.argv[2] !== "--check") throw Error("Usage: node test-elite-arena.js --check");
    console.log(JSON.stringify(run(), null, 2));
  } catch (error) {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  }
}

module.exports = { fixtureManifest, fixtureRows, run };
