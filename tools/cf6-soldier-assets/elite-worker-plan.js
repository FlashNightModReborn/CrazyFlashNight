"use strict";

const fs = require("fs");
const path = require("path");
const cp = require("child_process");
const {
  ROOT,
  SOURCE_PATHS,
  bindSources,
  buildCases,
  hashFile,
  positiveInteger,
  validateAuthorities,
} = require("./elite-arena-plan");
const { normalizeManifest } = require("../arena-calibration/lib/arena-calibration-core");
const { resolveExpectedRuntimeIdentity } = require("../lib/runtime-process-identity");

const WORKER_SOURCE_PATHS = Object.freeze([
  ...SOURCE_PATHS,
  "tools/cf6-soldier-assets/elite-worker-plan.js",
]);

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function writeJson(filePath, value) {
  fs.writeFileSync(path.toNamespacedPath(filePath), `${JSON.stringify(value, null, 2)}\n`, { flag: "wx" });
}

function defaultProfiles() {
  return [
    [
      { variant: "ordinary", level: 60, side: "red", weapon: "M4A1战术版" },
      { variant: "ordinary", level: 60, side: "red", weapon: "M4A1战术版", sidearm: "FR506", sidearm2: "FR506", toughnessCoefficient: 50 },
    ],
    [
      { variant: "elite", level: 60, side: "red", weapon: "M4A1战术版" },
      { variant: "noSidearm", level: 60, side: "red", weapon: "M4A1战术版" },
    ],
  ];
}

function createPlan(config, dependencies = {}) {
  if (!config || typeof config !== "object" || Array.isArray(config)) throw Error("Explicit Worker config required");
  if (!/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId || "")) throw Error("Fresh experimentId required");
  if (!path.isAbsolute(config.outputDirectory || "")
      || !path.resolve(config.outputDirectory).startsWith(path.join(ROOT, "tmp") + path.sep)) {
    throw Error("New absolute output directory in this checkout's tmp required");
  }
  if (!Array.isArray(config.workers) || config.workers.length !== 2) throw Error("Exactly two explicit Workers required");
  if (!path.isAbsolute(config.resourceListPath || "")) throw Error("Explicit frozen resource list required");
  const resourceList = JSON.parse(fs.readFileSync(path.toNamespacedPath(config.resourceListPath), "utf8"));
  const resourcePaths = resourceList.resourcePaths;
  if (!Array.isArray(resourcePaths) || resourcePaths.length === 0
      || resourcePaths.some((entry) => typeof entry !== "string" || path.isAbsolute(entry)
        || entry.split(/[\\/]/).includes(".."))) {
    throw Error("Existing relative resource observation list required");
  }
  for (const required of SOURCE_PATHS.filter((entry) =>
    entry.startsWith("flashswf/") || entry === "scripts/asLoader.swf" || entry.startsWith("data/"))) {
    if (!resourcePaths.includes(required)) throw Error(`Missing observed combat resource: ${required}`);
  }
  const hash = dependencies.hashFile || hashFile;
  const resolveIdentity = dependencies.resolveRuntimeIdentity || resolveExpectedRuntimeIdentity;
  const realPath = dependencies.realPath || fs.realpathSync.native;
  const sourceBindings = bindSources(ROOT, WORKER_SOURCE_PATHS, hash);
  const authorities = validateAuthorities(ROOT);
  const canonicalRoots = [];
  const workers = config.workers.map((worker, index) => {
    for (const key of ["projectRoot", "candidateRoot", "seedPath"]) {
      if (!path.isAbsolute(worker[key] || "")) throw Error(`Explicit Worker ${key} required`);
    }
    const projectRoot = path.resolve(worker.projectRoot);
    const candidateRoot = path.resolve(worker.candidateRoot);
    const candidateBase = path.join(projectRoot, "tmp", "runtime-candidates", "v2");
    if (!samePath(path.dirname(candidateRoot), candidateBase)) {
      throw Error("Owned direct-child isolated candidate required");
    }
    for (const binding of sourceBindings) {
      if (hash(path.join(projectRoot, binding.path)) !== binding.sha256) {
        throw Error(`Worker input differs: ${binding.path}`);
      }
    }
    const canonicalRoot = realPath(projectRoot);
    if (canonicalRoots.some((existing) => samePath(existing, canonicalRoot))) {
      throw Error("Independent resource roots required");
    }
    canonicalRoots.push(canonicalRoot);
    return {
      ...worker,
      projectRoot,
      candidateRoot,
      workerId: `elite-w0${index + 1}`,
      resourcePaths,
    };
  });
  const identities = workers.map((worker) => resolveIdentity(worker.projectRoot, worker.candidateRoot));
  for (const identity of identities) {
    if (!identity || identity.runtimeMode !== "isolated_candidate") throw Error("Worker must use an isolated candidate");
  }
  for (const field of ["coreSha256", "buildIdentity", "payloadClosure"]) {
    if (identities[0][field] !== identities[1][field]) throw Error(`Worker payloads differ: ${field}`);
  }
  const appData = dependencies.appData === undefined ? process.env.APPDATA : dependencies.appData;
  if (typeof appData !== "string" || !path.isAbsolute(appData)) throw Error("APPDATA is required for save protection");
  if (config.revision !== undefined && (typeof config.revision !== "string" || !config.revision.trim())) {
    throw Error("revision must be a non-empty string when present");
  }
  const profiles = config.profiles === undefined ? defaultProfiles() : config.profiles;
  const repeat = positiveInteger(config.repeat, 3, "repeat");
  const timeoutFrames = positiveInteger(config.timeoutFrames, 1800, "timeoutFrames");
  if (repeat > 3 || !Array.isArray(profiles) || profiles.length !== 2
      || profiles.some((profile) => !Array.isArray(profile) || profile.length < 1 || profile.length > 8)) {
    throw Error("Bounded explicit profiles required");
  }
  const commonOpponent = {
    id: positiveInteger(config.opponentId, 464, "opponentId"),
    level: positiveInteger(config.opponentLevel, 60, "opponentLevel"),
    weapon: config.opponentWeapon === undefined ? null : config.opponentWeapon,
  };
  if (commonOpponent.weapon !== null
      && (commonOpponent.id !== 449 || typeof commonOpponent.weapon !== "string" || !commonOpponent.weapon)) {
    throw Error("Opponent primary override is only verified for unit 449");
  }
  const plannedRows = [];
  profiles.forEach((profile, workerIndex) => {
    profile.forEach((row, index) => {
      if (!row || typeof row !== "object" || Array.isArray(row)) throw Error("Invalid elite Worker profile");
      for (const [field, value] of [["opponentId", commonOpponent.id], ["opponentLevel", commonOpponent.level],
        ["opponentWeapon", commonOpponent.weapon]]) {
        if (row[field] !== undefined && row[field] !== value) throw Error("All elite Workers must use the common opponent");
      }
      const caseId = `w${workerIndex + 1}-${index}-${row.variant || "unknown"}-${row.level === undefined ? 60 : row.level}-${row.side || "red"}`;
      plannedRows.push({
        workerIndex,
        row: {
          ...row,
          id: caseId,
          pairKey: row.pairKey === undefined ? `${commonOpponent.id}|${row.side || "red"}|${index}` : row.pairKey,
          opponentId: commonOpponent.id,
          opponentLevel: commonOpponent.level,
          opponentWeapon: commonOpponent.weapon,
          repeat,
          timeoutFrames: row.timeoutFrames === undefined ? timeoutFrames : row.timeoutFrames,
        },
      });
    });
  });
  const allCases = buildCases(plannedRows.map((entry) => entry.row), { sourceBindings, authorities });
  const casesById = new Map(allCases.map((testCase) => [testCase.caseId, testCase]));
  const output = path.resolve(config.outputDirectory);
  fs.mkdirSync(output, { recursive: true });
  const jobs = [];
  const manifestPaths = [];
  let expectedRows = 0;
  let redRows = 0;
  let blueRows = 0;
  for (let workerIndex = 0; workerIndex < workers.length; workerIndex += 1) {
    const worker = workers[workerIndex];
    const cases = plannedRows.filter((entry) => entry.workerIndex === workerIndex)
      .map((entry) => casesById.get(entry.row.id));
    const workerRows = cases.reduce((sum, testCase) => sum + testCase.repeat, 0);
    if (workerRows < 1 || workerRows > 25) throw Error("Each Worker shard must contain 1..25 runs");
    const worstCaseMs = cases.reduce((sum, testCase) =>
      sum + testCase.repeat * testCase.timeoutFrames / 30 * 1000, 0);
    if (!Number.isFinite(worstCaseMs) || worstCaseMs > 900000) {
      throw Error("Split elite Worker comparison into batches under 15 minutes");
    }
    expectedRows += workerRows;
    redRows += cases.filter((testCase) => testCase.authorityContext.candidateSide === "red")
      .reduce((sum, testCase) => sum + testCase.repeat, 0);
    blueRows += cases.filter((testCase) => testCase.authorityContext.candidateSide === "blue")
      .reduce((sum, testCase) => sum + testCase.repeat, 0);
    const buildCommit = dependencies.buildCommit
      ? dependencies.buildCommit(worker.projectRoot)
      : cp.execFileSync("git", ["rev-parse", "HEAD"], {
        cwd: worker.projectRoot, encoding: "utf8", windowsHide: true,
      }).trim();
    const manifest = normalizeManifest({
      batchId: `${config.experimentId}-w${workerIndex + 1}`,
      buildCommit,
      planner: { name: "cf6-elite-two-worker-comparison", version: 1 },
      repeat,
      timeoutFrames,
      cases,
    });
    const manifestPath = path.join(output, `worker-${workerIndex + 1}-manifest.json`);
    writeJson(manifestPath, manifest);
    manifestPaths.push(manifestPath);
    jobs.push({
      jobId: `elite-w${workerIndex + 1}`,
      workerId: worker.workerId,
      manifestPath,
      batchTimeoutMs: 900000,
    });
  }
  const plan = {
    schema: "arena-worker.experiment-plan.v1",
    experimentId: config.experimentId,
    workers,
    saveRoots: [...new Set([path.join(ROOT, "saves"), ...workers.map((worker) => path.join(worker.projectRoot, "saves"))])],
    sharedObjectsRoot: path.join(appData, "Macromedia", "Flash Player", "#SharedObjects"),
    groups: [{
      groupId: "elite-comparison",
      mode: "parallel",
      condition: config.revision || "elite-behavioral-ablation",
      visibility: "background-visible",
      performance: { preset: "performance", mode: "fixed", maxRenderHeight: 180 },
      jobs,
    }],
    comparisons: [],
  };
  const planPath = path.join(output, "experiment-plan.json");
  writeJson(planPath, plan);
  writeJson(path.join(output, "input-identity.json"), {
    schema: "cf6-soldier.elite-worker-inputs.v1",
    sourceBindings,
    runtimeIdentities: identities,
    independentResourceRoots: true,
    sourceHashesMatched: true,
    candidateIdentityAndClosureMatched: true,
    commonOpponent,
    expectedRows,
    redRows,
    blueRows,
    blueFriendlyHpMultiplierReportedSeparately: true,
    noPairwiseRngClaim: true,
    passiveMatchScope: "standard equipment weight and cross-slot projections only",
    fullEffectivePanelEqualityClaim: "not-claimed",
    claimsNoSpeedBenchmark: true,
    candidateExecutedByPlanner: false,
    worktreeCreatedByPlanner: false,
  });
  return {
    planPath,
    manifestPaths,
    rows: expectedRows,
    redRows,
    blueRows,
    workers: 2,
    candidateExecuted: false,
  };
}

if (require.main === module) {
  try {
    if (process.argv.length !== 3) throw Error("Usage: node elite-worker-plan.js <explicit-config.json>");
    console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2], "utf8")))));
  } catch (error) {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  }
}

module.exports = {
  WORKER_SOURCE_PATHS,
  createPlan,
  defaultProfiles,
};
