#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");
const {
  readJsonFile,
  readJsonLines,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const { analyzePairedStrength, rosterIdentity } = require("./lib/paired-strength");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");

const ROOT = path.resolve(__dirname, "../..");
const PRODUCTION_PROFILE = Object.freeze({
  spawnDistance: 650,
  blueFormation: "line",
  redFormation: "line",
  formationSpacing: 54,
});
const TARGET_PATH = "data/arena/arena_calibrated_rosters.json";
const IMPLEMENTATION_PATHS = Object.freeze([
  "data/arena/arena_config.xml",
  "data/units/units.json",
  "launcher/src/Tasks/ArenaAuthorityCatalog.cs",
  "launcher/src/Tasks/ArenaTask.cs",
  "launcher/tests/Tasks/ArenaAuthorityCatalogTests.cs",
  "launcher/web/modules/arena/arena-preview-authority.js",
  "launcher/web/modules/arena/arena-challenge-browser.js",
  "launcher/web/modules/arena/dev/harness.html",
  "launcher/web/modules/arena/dev/qa-suite.js",
  "config/build/runtime-inputs.v2.json",
  "tools/prepare-launcher-release-assets.ps1",
  "tools/validate-launcher-release-policy.ps1",
  "tools/workbench-live-e2e/arena-live-e2e.js",
  "tools/workbench-live-e2e/arena-live-e2e.self-test.js",
  "tools/arena-calibration/run-checks.js",
  "tools/arena-calibration/build-production-recommendation.js",
  "tools/arena-calibration/apply-production-recommendation.js",
]);

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = {
    pairedInput: null,
    candidateMetrics: null,
    human650: null,
    human820: null,
    outputDir: null,
    createdAt: null,
    check: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--paired-input") args.pairedInput = argv[++index];
    else if (token === "--candidate-metrics") args.candidateMetrics = argv[++index];
    else if (token === "--human-650") args.human650 = argv[++index];
    else if (token === "--human-820") args.human820 = argv[++index];
    else if (token === "--output-dir") args.outputDir = argv[++index];
    else if (token === "--created-at") args.createdAt = argv[++index];
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail(`unknown argument: ${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/build-production-recommendation.js [options]

  --paired-input <paired-strength-final-input.json>
  --candidate-metrics <candidate-metrics.json>
  --human-650 <pve-equivalence-response.json>
  --human-820 <pve-equivalence-response.json>
  --output-dir <project-relative-dir>
  [--created-at <ISO-8601>]
  [--check]

This command never edits formal arena configuration. It selects only machine-
completion-eligible candidates whose physical semantics match the production
proxy profile (650/line/line/54), refits their within-domain paired graph,
binds exact combinations to their workbook tier, applies the exact G2 human
PVE override, and emits a hash-bound recommendation bundle. Disconnected
components are never coerced onto a fabricated cross-tier continuous scale.
`);
}

function required(args, name) {
  if (!args[name]) fail(`--${name.replace(/[A-Z]/g, (value) => `-${value.toLowerCase()}`)} is required`);
  return args[name];
}

function resolveInsideRoot(value, label, mustExist = true) {
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) fail(`${label} is outside project root`);
  if (mustExist && !fs.existsSync(resolved)) fail(`${label} does not exist: ${value}`);
  return resolved;
}

function relative(filePath) {
  return path.relative(ROOT, filePath).replace(/\\/g, "/");
}

function sha256Buffer(value) {
  return `sha256:${crypto.createHash("sha256").update(value).digest("hex")}`;
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function implementationClosure() {
  const files = IMPLEMENTATION_PATHS.map((relativePath) => {
    const filePath = resolveInsideRoot(relativePath, `implementation ${relativePath}`);
    return { path: relativePath, sha256: sha256File(filePath) };
  });
  return { files, closureHash: sha256OfValue(files) };
}

function parseLevelBand(label) {
  const match = String(label || "").match(/^(\d+)\s*-\s*(\d+)级$/);
  if (!match) fail(`weak prior is not a level band: ${label}`);
  const levelMin = Number(match[1]);
  const levelMax = Number(match[2]);
  if (!Number.isInteger(levelMin) || !Number.isInteger(levelMax) || levelMin < 1 || levelMax <= levelMin) {
    fail(`weak prior has invalid bounds: ${label}`);
  }
  return {
    label: String(label),
    levelMin,
    levelMax,
    midpoint: (levelMin + levelMax) / 2,
  };
}

function productionCompatible(testCase) {
  return testCase.spawnDistance === PRODUCTION_PROFILE.spawnDistance
    && testCase.blueFormation === PRODUCTION_PROFILE.blueFormation
    && testCase.redFormation === PRODUCTION_PROFILE.redFormation
    && testCase.formationSpacing === PRODUCTION_PROFILE.formationSpacing;
}

function firstOriginalCase(manifest) {
  return manifest.cases.find((entry) => !String(entry.caseId).endsWith("-side-swap"));
}

function loadShard(entry) {
  const manifestPath = resolveInsideRoot(entry.manifestPath, `manifest ${entry.shardId}`);
  const resultPath = resolveInsideRoot(entry.resultPath, `result ${entry.shardId}`);
  return {
    shardId: entry.shardId,
    manifest: readJsonFile(manifestPath),
    rows: readJsonLines(resultPath),
    inputRef: sha256OfValue({ manifestSha256: sha256File(manifestPath), resultSha256: sha256File(resultPath) }),
  };
}

function collectCandidateDefinitions(input, metricsByCell) {
  const result = new Map();
  input.shards.forEach((entry) => {
    if (!/^f-[b-g]\d+-p1$/i.test(entry.shardId)) return;
    const manifest = readJsonFile(resolveInsideRoot(entry.manifestPath, `candidate manifest ${entry.shardId}`));
    const cell = String(manifest.planner && manifest.planner.sourceCell || "").toUpperCase();
    if (!metricsByCell.has(cell) || result.has(cell)) return;
    const testCase = firstOriginalCase(manifest);
    if (!testCase) fail(`candidate ${cell} has no original case`);
    result.set(cell, { manifest, testCase, metric: metricsByCell.get(cell) });
  });
  metricsByCell.forEach((_metric, cell) => {
    if (!result.has(cell)) fail(`paired input has no p1 candidate definition for ${cell}`);
  });
  return result;
}

function filteredStrengthInput(input, definitions) {
  const activeCells = new Set();
  const contextualCells = [];
  const provisionalCells = [];
  definitions.forEach((entry, cell) => {
    if (!entry.metric.completionEligible) {
      provisionalCells.push(cell);
    } else if (!productionCompatible(entry.testCase)) {
      contextualCells.push(cell);
    } else {
      activeCells.add(cell);
    }
  });
  const activeNodeIds = new Set();
  activeCells.forEach((cell) => {
    const testCase = definitions.get(cell).testCase;
    activeNodeIds.add(rosterIdentity(testCase, "blue"));
    activeNodeIds.add(rosterIdentity(testCase, "red"));
  });

  const shards = [];
  input.shards.forEach((entry) => {
    const loaded = loadShard(entry);
    const planner = loaded.manifest.planner || {};
    let cases = [];
    if (activeCells.has(String(planner.sourceCell || "").toUpperCase())) {
      cases = loaded.manifest.cases.filter(productionCompatible);
    } else if (planner.name === "gate-d-active-sampling") {
      // Bridge-only nodes are allowed to connect the production-domain graph,
      // but they are never copied into the runtime catalog. Publication remains
      // restricted to completion-eligible source candidates below.
      cases = loaded.manifest.cases.filter(productionCompatible);
    }
    if (!cases.length) return;
    const caseIds = new Set(cases.map((testCase) => testCase.caseId));
    const rows = loaded.rows.filter((row) => caseIds.has(row.caseId));
    const manifest = JSON.parse(JSON.stringify(loaded.manifest));
    manifest.cases = cases;
    shards.push({ manifest, rows, inputRef: loaded.inputRef });
  });
  if (!shards.length) fail("production refit selected no shards");
  return {
    shards,
    activeCells: Array.from(activeCells).sort(),
    contextualCells: contextualCells.sort(),
    provisionalCells: provisionalCells.sort(),
    activeNodeIds,
  };
}

function verifyHumanAnchor(response, expectedLevels, label) {
  if (response.schema !== "arena-calibration.pve-equivalence-response.v1"
      || response.calibrationObjective !== "monster_group_to_humanoid_mercenary_equivalence"
      || response.evidenceStatus !== "human_equivalence_labels_complete"
      || !Array.isArray(response.labels) || response.labels.length !== expectedLevels.length) {
    fail(`${label} human response is not a complete equivalence response`);
  }
  const actual = response.labels.map((item) => item.equivalentHumanoidLevel);
  if (actual.some((value, index) => value !== expectedLevels[index])) {
    fail(`${label} human response levels changed: ${actual.join(",")}`);
  }
}

function tierForBand(band, tiers) {
  const matches = tiers.filter((tier) => band.levelMin >= tier.levelMin && band.levelMax <= tier.levelMax);
  if (matches.length !== 1) fail(`level band ${band.label} maps to ${matches.length} arena tiers`);
  return matches[0];
}

function tierForHumanLevel(level, tiers) {
  const matches = tiers.filter((tier, index) => (
    level <= tier.levelMax && (index === 0 ? level >= tier.levelMin : level > tier.levelMin)
  ));
  if (matches.length !== 1) fail(`human equivalent level ${level} maps to ${matches.length} arena tiers`);
  return matches[0];
}

function readTiers() {
  const xml = fs.readFileSync(path.join(ROOT, "data/arena/arena_config.xml"), "utf8");
  const tiers = [];
  xml.replace(/<Card\b([^>]*)\/>/g, (_match, attributes) => {
    const read = (name) => {
      const match = attributes.match(new RegExp(`${name}="([^"]+)"`));
      return match ? match[1] : null;
    };
    const id = read("id");
    if (id && /^arena-\d+$/.test(id)) {
      tiers.push({ id, levelMin: Number(read("levelMin")), levelMax: Number(read("levelMax")) });
    }
    return _match;
  });
  if (tiers.length !== 10 || tiers.some((tier) => !tier.levelMin || !tier.levelMax)) {
    fail("arena_config.xml standard tiers could not be parsed");
  }
  return tiers;
}

function unitCatalog() {
  const values = readJsonFile(path.join(ROOT, "data/units/units.json"));
  return new Map(values.map((entry) => [`兵种${entry.id}`, entry]));
}

function canonicalMember(entry, units) {
  const unit = units.get(entry.type);
  if (!unit) fail(`calibrated roster references unknown unit type: ${entry.type}`);
  const result = {
    type: entry.type,
    level: entry.level,
    count: 1,
    name: String(unit.name || unit.spritename || entry.type),
    spritename: String(unit.spritename || ""),
    humanoid: /主角/.test(String(unit.spritename || "")),
  };
  if (!result.spritename) fail(`calibrated roster unit has no spritename: ${entry.type}`);
  if (entry.parameters) result.parameters = JSON.parse(JSON.stringify(entry.parameters));
  return result;
}

function compactMembers(roster, units) {
  const result = [];
  roster.forEach((entry) => {
    const member = canonicalMember(entry, units);
    const signature = sha256OfValue({
      type: member.type,
      level: member.level,
      parameters: member.parameters || null,
    });
    const existing = result.find((value) => value.signature === signature);
    if (existing) existing.member.count += 1;
    else result.push({ signature, member });
  });
  return result.map((entry) => entry.member);
}

function displayName(members) {
  const text = members.map((member) => `${member.name} Lv${member.level}${member.count > 1 ? `×${member.count}` : ""}`).join(" + ");
  return text.length <= 160 ? text : `${text.slice(0, 157)}…`;
}

function buildCatalog(options) {
  const metricsDocument = readJsonFile(options.candidateMetricsPath);
  const input = readJsonFile(options.pairedInputPath);
  if (!Array.isArray(metricsDocument.candidates) || !Array.isArray(input.shards)) {
    fail("production recommendation inputs have invalid top-level shape");
  }
  const metricsByCell = new Map(metricsDocument.candidates.map((entry) => [entry.sourceCell.toUpperCase(), entry]));
  const definitions = collectCandidateDefinitions(input, metricsByCell);
  const selected = filteredStrengthInput(input, definitions);
  const refit = analyzePairedStrength(selected.shards, {
    reportId: `${input.campaignId}-production-compatible-refit`,
    planId: `${input.campaignId}-production-compatible-refit`,
    cohortId: input.cohortId,
    createdAt: options.createdAt,
  });
  const human650 = readJsonFile(options.human650Path);
  const human820 = readJsonFile(options.human820Path);
  verifyHumanAnchor(human650, [10, 10], "650-domain");
  verifyHumanAnchor(human820, [45, 55], "820-domain raw");
  const g2 = definitions.get("G2");
  const b11 = definitions.get("B11");
  if (!g2 || !selected.activeCells.includes("G2")) fail("G2 production anchor candidate is missing");
  if (!b11 || !selected.contextualCells.includes("B11")) fail("B11 contextual credibility candidate is missing");
  if (!String(human650.packetId || "").startsWith(`pve-${g2.metric.candidateId}-`)) {
    fail("650-domain human response is not bound to G2");
  }
  if (!String(human820.packetId || "").startsWith(`pve-${b11.metric.candidateId}-`)) {
    fail("820-domain human response is not bound to B11");
  }
  const nodeById = new Map(refit.report.nodes.map((node) => [node.nodeId, node]));
  const g2Ids = [rosterIdentity(g2.testCase, "blue"), rosterIdentity(g2.testCase, "red")];
  const tiers = readTiers();
  const nodeSources = new Map();
  selected.activeCells.forEach((cell) => {
    const definition = definitions.get(cell);
    const band = parseLevelBand(definition.metric.weakPrior);
    const sourceTier = tierForBand(band, tiers);
    ["blue", "red"].forEach((side) => {
      const nodeId = rosterIdentity(definition.testCase, side);
      const node = nodeById.get(nodeId);
      if (!node) fail(`production refit omitted accepted node ${nodeId}`);
      if (!nodeSources.has(nodeId)) {
        nodeSources.set(nodeId, {
          cells: [],
          candidateIds: [],
          bands: [],
          sourceTierIds: [],
          metrics: [],
          roster: null,
        });
      }
      const source = nodeSources.get(nodeId);
      source.cells.push(cell);
      source.candidateIds.push(definition.metric.candidateId);
      source.bands.push(band);
      source.sourceTierIds.push(sourceTier.id);
      source.metrics.push(definition.metric);
      source.roster = JSON.parse(JSON.stringify(side === "blue" ? definition.testCase.blueRoster : definition.testCase.redRoster));
    });
  });

  const componentTierIds = new Map();
  nodeSources.forEach((source, nodeId) => {
    const node = nodeById.get(nodeId);
    if (!componentTierIds.has(node.component)) componentTierIds.set(node.component, new Set());
    source.sourceTierIds.forEach((tierId) => componentTierIds.get(node.component).add(tierId));
  });
  const publishedComponents = Array.from(componentTierIds.entries()).map(([component, tierIds]) => {
    return {
      component,
      tierIds: Array.from(tierIds).sort(),
      publishedNodes: Array.from(nodeSources.keys()).filter((nodeId) => nodeById.get(nodeId).component === component).length,
    };
  }).sort((left, right) => left.component - right.component);

  const publishedCycles = refit.report.nonTransitiveCycles.filter((cycle) => (
    cycle.nodes.every((nodeId) => nodeSources.has(nodeId))
  )).map((cycle) => {
    const tierIds = new Set();
    cycle.nodes.forEach((nodeId) => {
      nodeSources.get(nodeId).sourceTierIds.forEach((tierId) => tierIds.add(tierId));
    });
    return { ...cycle, runtimeTierIds: Array.from(tierIds).sort() };
  });

  const humanOverrides = new Map(g2Ids.map((nodeId, index) => [nodeId, {
    sourceCell: "G2",
    encounterId: human650.labels[index].encounterId,
    equivalentHumanoidCount: human650.labels[index].equivalentHumanoidCount,
    equivalentHumanoidLevel: human650.labels[index].equivalentHumanoidLevel,
    responseHash: human650.responseHash,
  }]));
  const units = unitCatalog();
  const rosters = Array.from(nodeSources.entries()).map(([nodeId, source]) => {
    const node = nodeById.get(nodeId);
    const uniqueBands = Array.from(new Map(source.bands.map((band) => [band.label, band])).values())
      .sort((left, right) => left.levelMin - right.levelMin || left.levelMax - right.levelMax);
    const sourceTierIds = Array.from(new Set(source.sourceTierIds));
    if (sourceTierIds.length !== 1) fail(`published roster ${nodeId} crosses runtime tiers`);
    let tier = tiers.find((entry) => entry.id === sourceTierIds[0]);
    let equivalentLevel = Math.round(uniqueBands.reduce((sum, band) => sum + band.midpoint, 0) / uniqueBands.length);
    let equivalentLevelMin = Math.min(...uniqueBands.map((band) => band.levelMin));
    let equivalentLevelMax = Math.max(...uniqueBands.map((band) => band.levelMax));
    let assignmentBasis = "workbook_source_band";
    const humanOverride = humanOverrides.get(nodeId) || null;
    if (humanOverride) {
      equivalentLevel = humanOverride.equivalentHumanoidLevel;
      equivalentLevelMin = equivalentLevel;
      equivalentLevelMax = equivalentLevel;
      tier = tierForHumanLevel(equivalentLevel, tiers);
      assignmentBasis = "exact_human_pve_override";
    }
    const members = compactMembers(source.roster, units);
    const sourceMetrics = Array.from(new Map(source.metrics.map((metric) => [metric.sourceCell, metric])).values());
    const roster = {
      id: nodeId,
      displayName: displayName(members),
      equivalentLevel,
      equivalentLevelMin,
      equivalentLevelMax,
      tierId: tier.id,
      assignmentBasis,
      sourceBands: uniqueBands.map((band) => band.label),
      sourceCells: Array.from(new Set(source.cells)).sort(),
      candidateIds: Array.from(new Set(source.candidateIds)).sort(),
      samples: node.samples,
      sourceCandidateMinSamples: Math.min(...sourceMetrics.map((metric) => metric.samples)),
      machineValidation: {
        component: node.component,
        withinComponentStrength: Number(node.strength.toFixed(8)),
        lower95: Number(node.lower95.toFixed(8)),
        upper95: Number(node.upper95.toFixed(8)),
        sourceCandidateTimeoutRateMax: Math.max(...sourceMetrics.map((metric) => metric.timeoutRate)),
        sourceCandidateErrorCount: sourceMetrics.reduce((sum, metric) => sum + metric.errors, 0),
        sideSwapReviewed: sourceMetrics.every((metric) => metric.sideSwapReviewed),
      },
      members,
      requiredKnownEnemies: Array.from(new Set(members
        .filter((member) => !member.humanoid)
        .map((member) => member.spritename))).sort(),
    };
    if (humanOverride) roster.humanOverride = humanOverride;
    return roster;
  }).sort((left, right) => (
    tiers.findIndex((tier) => tier.id === left.tierId) - tiers.findIndex((tier) => tier.id === right.tierId)
      || left.equivalentLevel - right.equivalentLevel
      || left.id.localeCompare(right.id)
  ));

  const catalog = {
    schemaVersion: 1,
    active: true,
    catalogId: `${input.campaignId}-production-compatible-v1`,
    campaignId: input.campaignId,
    cohortId: input.cohortId,
    source: {
      workbookSha256: "sha256:840b30af82ca686e954dc4a6378a5c2b297506070e034ed79ea91da9e0b3b793",
      sheetName: "斗兽标定组合",
      arenaConfigSha256: sha256File(path.join(ROOT, "data/arena/arena_config.xml")),
      unitCatalogSha256: sha256File(path.join(ROOT, "data/units/units.json")),
      candidateMetricsSha256: sha256File(options.candidateMetricsPath),
      pairedInputSha256: sha256File(options.pairedInputPath),
      productionRefitHash: refit.report.reportHash,
      human650ResponseHash: human650.responseHash,
      human820ResponseHash: human820.responseHash,
    },
    model: {
      method: "workbook-tier-exact-combination-with-production-domain-pairwise-validation-v1",
      strengthModel: refit.report.model,
      graphComponentCount: refit.report.componentCount,
      publishedComponents,
      bridgeOnlyNodes: refit.report.nodes.filter((node) => !nodeSources.has(node.nodeId)).length,
      publishedNonTransitiveCycles: publishedCycles,
      humanOverrides: [{
        sourceCell: "G2",
        nodeIds: g2Ids,
        equivalentHumanoidLevel: 10,
        responseHash: human650.responseHash,
      }],
      absoluteScaleBoundary: "workbook bands assign runtime tiers; pairwise component strengths are retained only within each connected tier and are not converted into a cross-tier continuous level",
      productionProxyProfile: PRODUCTION_PROFILE,
      transferBoundary: "only 650/line/line/54 machine-completion-eligible candidates are active; 820 or non-line evidence is retained outside the runtime catalog",
    },
    rosters,
    catalogHash: "",
  };
  catalog.catalogHash = sha256OfValue(withoutHash(catalog, "catalogHash"));
  return {
    catalog,
    refit,
    selected,
    metricsDocument,
    human650,
    human820,
  };
}

function unifiedReplacementDiff(baseText, proposedText) {
  const before = baseText.replace(/\r\n/g, "\n").split("\n");
  const after = proposedText.replace(/\r\n/g, "\n").split("\n");
  return [
    `--- a/${TARGET_PATH}`,
    `+++ b/${TARGET_PATH}`,
    `@@ -1,${before.length} +1,${after.length} @@`,
    ...before.map((line) => `-${line}`),
    ...after.map((line) => `+${line}`),
    "",
  ].join("\n");
}

function buildRecommendation(options) {
  const result = buildCatalog(options);
  const targetPath = path.join(ROOT, TARGET_PATH);
  const baseBytes = fs.readFileSync(targetPath);
  const baseSha256 = sha256Buffer(baseBytes);
  const proposedText = `${JSON.stringify(result.catalog, null, 2)}\n`;
  const proposedSha256 = sha256Buffer(Buffer.from(proposedText, "utf8"));
  const outputDir = options.outputDir;
  fs.mkdirSync(outputDir, { recursive: true });
  const proposedPath = path.join(outputDir, "proposed-arena-calibrated-rosters.json");
  const rollbackPath = path.join(outputDir, "rollback-arena-calibrated-rosters.json");
  const diffPath = path.join(outputDir, "dry-run.patch");
  const refitDir = path.join(outputDir, "production-refit");
  fs.mkdirSync(refitDir, { recursive: true });
  fs.writeFileSync(proposedPath, proposedText, "utf8");
  fs.writeFileSync(rollbackPath, baseBytes);
  fs.writeFileSync(diffPath, unifiedReplacementDiff(baseBytes.toString("utf8"), proposedText), "utf8");
  writeJsonAtomic(path.join(refitDir, "paired-strength-report.json"), result.refit.report);
  writeJsonAtomic(path.join(refitDir, "active-sampling-plan.json"), result.refit.plan);
  writeJsonAtomic(path.join(refitDir, "excluded-results.json"), result.refit.excluded);

  const sourceRevision = childProcess.execFileSync("git", ["rev-parse", "HEAD"], { cwd: ROOT, encoding: "utf8" }).trim();
  const eligible = result.metricsDocument.candidates.filter((entry) => entry.completionEligible);
  const provisional = result.metricsDocument.candidates.filter((entry) => !entry.completionEligible);
  const bundle = {
    schema: "arena-calibration.production-recommendation-bundle.v1",
    bundleId: `${result.catalog.catalogId}-recommendation`,
    state: "AWAITING_HUMAN_APPROVAL",
    createdAt: options.createdAt,
    sourceRevision,
    recommendation: {
      target: "standard arena monster roster tier selection",
      activeRosterCount: result.catalog.rosters.length,
      machineCompletionEligibleCandidates: eligible.length,
      productionCompatibleCandidates: result.selected.activeCells.length,
      contextOnlyEligibleCandidates: result.selected.contextualCells,
      timeoutProvisionalCandidates: provisional.map((entry) => entry.sourceCell).sort(),
      quarantinedCandidates: ["D10", "B12"],
      disposition: "activate exact combination-level catalog; do not write faction benchLevel",
    },
    evidence: {
      campaignId: result.catalog.campaignId,
      cohortId: result.catalog.cohortId,
      productionRefitHash: result.catalog.source.productionRefitHash,
      human650ResponseHash: result.human650.responseHash,
      human820ResponseHash: result.human820.responseHash,
      human820OperatorInterpretation: "both B11 rosters remain a 50-60 tier credibility check; excluded from active default profile because their 820/wedge semantics differ",
    },
    implementationClosure: implementationClosure(),
    target: {
      path: TARGET_PATH,
      symbol: "root calibrated roster catalog",
      baseSha256,
      sourceRevision,
    },
    patch: {
      operation: "replace_file_exact",
      expectedBaseSha256: baseSha256,
      replacementPath: relative(proposedPath),
      replacementSha256: proposedSha256,
      dryRunDiffPath: relative(diffPath),
    },
    verification: {
      commands: [
        "node tools/arena-calibration/build-production-recommendation.js --check",
        "node tools/arena-calibration/apply-production-recommendation.js --check",
        "dotnet test launcher/tests/Launcher.Tests.csproj --filter ArenaAuthorityCatalogTests",
        "node tools/run-arena-harness.js",
        "node --check tools/workbench-live-e2e/arena-live-e2e.js",
        "node --check tools/workbench-live-e2e/arena-live-e2e.self-test.js",
        "node tools/validate-doc-governance.js",
      ],
      expected: [
        "catalog hash and exact base hash valid",
        "Host rejects forged calibratedRosterId/roster and accepts canonical snapshot roster",
        "arena harness selects calibrated roster only in its bound tier",
        "documentation governance passes",
      ],
    },
    rollback: {
      operation: "replace_file_exact",
      expectedAppliedSha256: proposedSha256,
      replacementPath: relative(rollbackPath),
      replacementSha256: baseSha256,
    },
    failClosed: [
      "base hash drift",
      "catalog hash mismatch",
      "unknown tier or unit",
      "non-production physical semantics",
      "provisional or quarantined source candidate",
      "implementation closure drift",
      "consumer verification failure",
    ],
    bundleHash: "",
  };
  bundle.bundleHash = sha256OfValue(withoutHash(bundle, "bundleHash"));
  writeJsonAtomic(path.join(outputDir, "recommendation-bundle.json"), bundle);
  return { bundle, result, proposedSha256 };
}

function runCheck() {
  const tiers = readTiers();
  const workbookTier = tierForBand(parseLevelBand("20-25级"), tiers);
  const humanTier = tierForHumanLevel(10, tiers);
  if (workbookTier.id !== "arena-5" || humanTier.id !== "arena-2") {
    fail("discrete arena tier mapping contract failed");
  }
  const fake = {
    spawnDistance: 650,
    blueFormation: "line",
    redFormation: "line",
    formationSpacing: 54,
  };
  if (!productionCompatible(fake) || productionCompatible({ ...fake, spawnDistance: 820 })) {
    fail("production physical-profile gate contract failed");
  }
  console.log(JSON.stringify({
    ok: true,
    check: "arena-production-recommendation-contract",
    formalWrite: false,
    productionProfile: PRODUCTION_PROFILE,
    workbookBandExample: { source: "20-25级", tierId: workbookTier.id },
    humanOverrideExample: { equivalentHumanoidLevel: 10, tierId: humanTier.id },
    crossTierContinuousFit: false,
  }, null, 2));
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  if (args.check) return runCheck();
  const createdAt = args.createdAt || new Date().toISOString();
  const outputDir = resolveInsideRoot(required(args, "outputDir"), "output directory", false);
  const built = buildRecommendation({
    pairedInputPath: resolveInsideRoot(required(args, "pairedInput"), "paired input"),
    candidateMetricsPath: resolveInsideRoot(required(args, "candidateMetrics"), "candidate metrics"),
    human650Path: resolveInsideRoot(required(args, "human650"), "650 human response"),
    human820Path: resolveInsideRoot(required(args, "human820"), "820 human response"),
    outputDir,
    createdAt,
  });
  console.log(JSON.stringify({
    ok: true,
    outputDir: relative(outputDir),
    bundleHash: built.bundle.bundleHash,
    baseSha256: built.bundle.target.baseSha256,
    proposedSha256: built.proposedSha256,
    activeRosterCount: built.result.catalog.rosters.length,
    productionCompatibleCandidates: built.result.selected.activeCells.length,
    contextOnlyEligibleCandidates: built.result.selected.contextualCells,
    timeoutProvisionalCandidates: built.result.selected.provisionalCells.length,
    formalWrite: false,
  }, null, 2));
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(error.stack || error.message);
    process.exit(error.isUsageError ? 2 : 1);
  }
}

module.exports = {
  PRODUCTION_PROFILE,
  parseLevelBand,
  productionCompatible,
  tierForBand,
  tierForHumanLevel,
};
