"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const CASE_MANIFEST_SCHEMA = "arena-calibration.case-manifest.v1";
const RESULT_SCHEMA = "arena-calibration.result.v1";
const SUMMARY_SCHEMA = "arena-calibration.summary.v1";
const NEXT_BATCH_SCHEMA = "arena-calibration.next-batch.v1";

const RESULT_STATUSES = new Set([
  "finished",
  "timeout",
  "aborted",
  "spawn_failed",
  "invalid_case",
  "stage_failed",
  "bridge_lost",
  "error",
]);

const WINNERS = new Set(["blue", "red", "draw", "timeout", "none", null]);

const ECONOMY_KEYS = new Set([
  "money",
  "cash",
  "gold",
  "coin",
  "coins",
  "kpoint",
  "kpoints",
  "reward",
  "rewards",
  "drop",
  "drops",
  "loot",
  "item",
  "items",
  "equipment",
  "equip",
  "exp",
  "xp",
]);

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function readJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJsonFile(filePath, value) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function readJsonLines(filePath) {
  const text = fs.readFileSync(filePath, "utf8");
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        fail(`${filePath}:${index + 1}: invalid JSONL row: ${error.message}`);
      }
    });
}

function writeJsonLines(filePath, rows) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, rows.map((row) => JSON.stringify(row)).join("\n") + "\n", "utf8");
}

function stableClone(value) {
  if (Array.isArray(value)) {
    return value.map(stableClone);
  }
  if (value && typeof value === "object") {
    const result = {};
    Object.keys(value)
      .filter((key) => value[key] !== undefined)
      .sort()
      .forEach((key) => {
        result[key] = stableClone(value[key]);
      });
    return result;
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableClone(value));
}

function sha256OfString(text) {
  return `sha256:${crypto.createHash("sha256").update(text, "utf8").digest("hex")}`;
}

function sha256OfValue(value) {
  return sha256OfString(stableStringify(value));
}

function nowIso() {
  return new Date().toISOString();
}

function localDateString(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function getShortCommit() {
  try {
    const childProcess = require("child_process");
    const output = childProcess.execFileSync("git", ["rev-parse", "--short=12", "HEAD"], {
      cwd: path.resolve(__dirname, "../../.."),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return output.trim();
  } catch (_error) {
    return "unknown";
  }
}

function assertString(value, fieldName, errors) {
  if (typeof value !== "string" || value.trim() === "") {
    errors.push(`${fieldName} must be a non-empty string`);
    return "";
  }
  return value.trim();
}

function parsePositiveInteger(value, fieldName, errors) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0 || Math.floor(number) !== number) {
    errors.push(`${fieldName} must be a positive integer`);
    return 1;
  }
  return number;
}

function parseNonNegativeNumber(value, fieldName, errors) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    errors.push(`${fieldName} must be a non-negative number`);
    return 0;
  }
  return number;
}

function findEconomyKeys(value, prefix, errors) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => findEconomyKeys(entry, `${prefix}[${index}]`, errors));
    return;
  }
  if (!value || typeof value !== "object") {
    return;
  }
  Object.keys(value).forEach((key) => {
    if (ECONOMY_KEYS.has(key.toLowerCase())) {
      errors.push(`${prefix}.${key} is not allowed in arena calibration manifests`);
    }
    findEconomyKeys(value[key], `${prefix}.${key}`, errors);
  });
}

function normalizeRosterEntry(entry, fieldName, errors) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    errors.push(`${fieldName} must be an object`);
    return { type: "", level: 1 };
  }

  const type = entry.type !== undefined ? entry.type : entry["兵种"];
  const level = entry.level !== undefined ? entry.level : entry["等级"];
  const normalizedType = assertString(type, `${fieldName}.type`, errors);
  if (normalizedType && !/^兵种\d+$/.test(normalizedType)) {
    errors.push(`${fieldName}.type must use a 兵种N identifier`);
  }
  return {
    type: normalizedType,
    level: parsePositiveInteger(level, `${fieldName}.level`, errors),
  };
}

function normalizeRoster(roster, fieldName, errors) {
  if (!Array.isArray(roster) || roster.length === 0) {
    errors.push(`${fieldName} must be a non-empty array`);
    return [];
  }
  return roster.map((entry, index) => normalizeRosterEntry(entry, `${fieldName}[${index}]`, errors));
}

function normalizeTags(tags, fieldName, errors) {
  if (tags === undefined) {
    return [];
  }
  if (!Array.isArray(tags)) {
    errors.push(`${fieldName} must be an array when present`);
    return [];
  }
  return tags.map((tag, index) => assertString(tag, `${fieldName}[${index}]`, errors));
}

function buildCaseHashInput(testCase) {
  return {
    caseId: testCase.caseId,
    blueRoster: testCase.blueRoster,
    redRoster: testCase.redRoster,
    repeat: testCase.repeat,
    timeoutFrames: testCase.timeoutFrames,
  };
}

function normalizeCase(input, defaults, index, errors) {
  const fieldName = `cases[${index}]`;
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    errors.push(`${fieldName} must be an object`);
    return {
      caseId: "",
      blueRoster: [],
      redRoster: [],
      repeat: defaults.repeat,
      timeoutFrames: defaults.timeoutFrames,
      tags: [],
      plannerReason: "",
      caseHash: "",
    };
  }

  const testCase = {
    caseId: assertString(input.caseId, `${fieldName}.caseId`, errors),
    blueRoster: normalizeRoster(input.blueRoster, `${fieldName}.blueRoster`, errors),
    redRoster: normalizeRoster(input.redRoster, `${fieldName}.redRoster`, errors),
    repeat: parsePositiveInteger(input.repeat || defaults.repeat, `${fieldName}.repeat`, errors),
    timeoutFrames: parsePositiveInteger(
      input.timeoutFrames || defaults.timeoutFrames,
      `${fieldName}.timeoutFrames`,
      errors
    ),
    tags: normalizeTags(input.tags, `${fieldName}.tags`, errors),
    plannerReason:
      input.plannerReason === undefined
        ? ""
        : assertString(input.plannerReason, `${fieldName}.plannerReason`, errors),
  };
  testCase.caseHash = sha256OfValue(buildCaseHashInput(testCase));
  return testCase;
}

function buildManifestHashInput(manifest) {
  return {
    schema: manifest.schema,
    batchId: manifest.batchId,
    buildCommit: manifest.buildCommit,
    planner: manifest.planner,
    arenaMode: manifest.arenaMode,
    repeat: manifest.repeat,
    timeoutFrames: manifest.timeoutFrames,
    blueBench: manifest.blueBench,
    cases: manifest.cases,
  };
}

function normalizeManifest(input) {
  const errors = [];
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    fail("manifest must be a JSON object");
  }
  findEconomyKeys(input, "$", errors);

  const repeat = parsePositiveInteger(input.repeat || 5, "repeat", errors);
  const timeoutFrames = parsePositiveInteger(input.timeoutFrames || 5400, "timeoutFrames", errors);
  const manifest = {
    schema: input.schema || CASE_MANIFEST_SCHEMA,
    batchId: assertString(input.batchId, "batchId", errors),
    createdAt: input.createdAt || nowIso(),
    buildCommit: input.buildCommit || getShortCommit(),
    planner: input.planner || { name: "manual", version: 1 },
    arenaMode: input.arenaMode || "calibration",
    repeat,
    timeoutFrames,
    blueBench: input.blueBench || null,
    cases: [],
  };

  if (manifest.schema !== CASE_MANIFEST_SCHEMA) {
    errors.push(`schema must be ${CASE_MANIFEST_SCHEMA}`);
  }
  if (manifest.arenaMode !== "calibration") {
    errors.push("arenaMode must be calibration");
  }
  if (!Array.isArray(input.cases) || input.cases.length === 0) {
    errors.push("cases must be a non-empty array");
  } else {
    const defaults = { repeat, timeoutFrames };
    manifest.cases = input.cases.map((testCase, index) =>
      normalizeCase(testCase, defaults, index, errors)
    );
  }

  const ids = new Set();
  manifest.cases.forEach((testCase) => {
    if (ids.has(testCase.caseId)) {
      errors.push(`caseId must be unique: ${testCase.caseId}`);
    }
    ids.add(testCase.caseId);
  });

  if (errors.length > 0) {
    fail(`invalid case manifest:\n- ${errors.join("\n- ")}`);
  }
  manifest.manifestHash = sha256OfValue(buildManifestHashInput(manifest));
  return manifest;
}

function createPilotManifest(options) {
  const batchId = options.batchId || `pilot-${localDateString(new Date())}-a`;
  const thiefRoster = [
    { type: "兵种44", level: 30 },
    { type: "兵种45", level: 30 },
    { type: "兵种48", level: 30 },
    { type: "兵种49", level: 30 },
  ];
  return normalizeManifest({
    schema: CASE_MANIFEST_SCHEMA,
    batchId,
    createdAt: options.createdAt || nowIso(),
    buildCommit: options.buildCommit || getShortCommit(),
    planner: {
      name: "manual-anchor",
      version: 1,
      reason: "复用 _root.测试角斗场怪物 默认盗贼组作为通路锚点",
    },
    arenaMode: "calibration",
    repeat: options.repeat || 5,
    timeoutFrames: options.timeoutFrames || 5400,
    blueBench: {
      benchId: "thief-lv30x4",
      roster: thiefRoster,
    },
    cases: [
      {
        caseId: "pilot-thief-lv30x4-mirror",
        blueRoster: thiefRoster,
        redRoster: thiefRoster,
        repeat: options.repeat || 5,
        timeoutFrames: options.timeoutFrames || 5400,
        tags: ["pilot", "manual-anchor", "mirror"],
        plannerReason: "复用现有 _root.测试角斗场怪物 默认盗贼组作为通路锚点",
      },
    ],
  });
}

function normalizeSideSummary(input, fieldName, errors) {
  const source = input || {};
  const maxHp = parseNonNegativeNumber(source.maxHp || 0, `${fieldName}.maxHp`, errors);
  const remainHp = parseNonNegativeNumber(source.remainHp || 0, `${fieldName}.remainHp`, errors);
  const aliveCount = parseNonNegativeNumber(source.aliveCount || 0, `${fieldName}.aliveCount`, errors);
  return {
    maxHp,
    remainHp,
    aliveCount,
  };
}

function normalizeErrors(input, fieldName, errors) {
  if (input === undefined || input === null) {
    return [];
  }
  if (!Array.isArray(input)) {
    errors.push(`${fieldName} must be an array`);
    return [];
  }
  return input.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(`${fieldName}[${index}] must be an object`);
      return { code: "invalid_error_entry", message: "" };
    }
    return {
      code: assertString(entry.code || "error", `${fieldName}[${index}].code`, errors),
      side: entry.side || null,
      unit: entry.unit || null,
      message: entry.message || "",
    };
  });
}

function normalizeResultRow(input) {
  const errors = [];
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    fail("result row must be a JSON object");
  }
  const status = input.status || "error";
  const winner = input.winner === undefined ? null : input.winner;
  if (!RESULT_STATUSES.has(status)) {
    errors.push(`status must be one of ${Array.from(RESULT_STATUSES).join(", ")}`);
  }
  if (!WINNERS.has(winner)) {
    errors.push("winner must be blue, red, draw, timeout, none, or null");
  }
  const row = {
    schema: input.schema || RESULT_SCHEMA,
    batchId: assertString(input.batchId, "batchId", errors),
    manifestHash: assertString(input.manifestHash, "manifestHash", errors),
    caseId: assertString(input.caseId, "caseId", errors),
    caseHash: assertString(input.caseHash, "caseHash", errors),
    runId: assertString(input.runId, "runId", errors),
    repeatIndex: parsePositiveInteger(input.repeatIndex || 1, "repeatIndex", errors),
    status,
    winner,
    frames:
      input.frames === undefined || input.frames === null
        ? null
        : parseNonNegativeNumber(input.frames, "frames", errors),
    durationMs:
      input.durationMs === undefined || input.durationMs === null
        ? null
        : parseNonNegativeNumber(input.durationMs, "durationMs", errors),
    blue: normalizeSideSummary(input.blue, "blue", errors),
    red: normalizeSideSummary(input.red, "red", errors),
    errors: normalizeErrors(input.errors, "errors", errors),
    startedAt: input.startedAt || null,
    completedAt: input.completedAt || null,
  };
  if (row.schema !== RESULT_SCHEMA) {
    errors.push(`schema must be ${RESULT_SCHEMA}`);
  }
  if (errors.length > 0) {
    fail(`invalid result row ${input.caseId || ""}/${input.runId || ""}:\n- ${errors.join("\n- ")}`);
  }
  return row;
}

function ratio(numerator, denominator) {
  if (!denominator) {
    return 0;
  }
  return numerator / denominator;
}

function average(values) {
  const numeric = values.filter((value) => Number.isFinite(value));
  if (numeric.length === 0) {
    return null;
  }
  return numeric.reduce((sum, value) => sum + value, 0) / numeric.length;
}

function round4(value) {
  if (value === null || value === undefined) {
    return null;
  }
  return Math.round(value * 10000) / 10000;
}

function classifyCase(samples, blueWinRate, timeoutRate, errorCount) {
  if (errorCount > 0) {
    return "error";
  }
  if (timeoutRate > 0.2) {
    return "unstable_timeout";
  }
  if (samples < 5) {
    return "undersampled";
  }
  if (blueWinRate >= 0.4 && blueWinRate <= 0.6) {
    return "balanced_candidate";
  }
  if (blueWinRate > 0.6) {
    return "blue_favored";
  }
  return "red_favored";
}

function recommendAction(classification, samples) {
  if (classification === "balanced_candidate" && samples >= 5) {
    return "append_repeat";
  }
  if (classification === "undersampled") {
    return "append_repeat";
  }
  if (classification === "error" || classification === "unstable_timeout") {
    return "review";
  }
  return "append_counter_case";
}

function analyzeRows(rows, options) {
  const normalizedRows = rows.map(normalizeResultRow);
  const grouped = new Map();
  normalizedRows.forEach((row) => {
    const key = `${row.caseId}|${row.caseHash}`;
    if (!grouped.has(key)) {
      grouped.set(key, []);
    }
    grouped.get(key).push(row);
  });

  const cases = Array.from(grouped.values())
    .map((caseRows) => {
      const first = caseRows[0];
      const samples = caseRows.length;
      const blueWins = caseRows.filter((row) => row.winner === "blue").length;
      const redWins = caseRows.filter((row) => row.winner === "red").length;
      const draws = caseRows.filter((row) => row.winner === "draw").length;
      const timeouts = caseRows.filter((row) => row.status === "timeout").length;
      const errorCount = caseRows.filter((row) => row.status !== "finished").length;
      const blueRemainRatio = average(caseRows.map((row) => ratio(row.blue.remainHp, row.blue.maxHp)));
      const redRemainRatio = average(caseRows.map((row) => ratio(row.red.remainHp, row.red.maxHp)));
      const avgWinnerRemainHpRatio = average(
        caseRows.map((row) => {
          if (row.winner === "blue") {
            return ratio(row.blue.remainHp, row.blue.maxHp);
          }
          if (row.winner === "red") {
            return ratio(row.red.remainHp, row.red.maxHp);
          }
          return null;
        })
      );
      const blueWinRate = ratio(blueWins, samples);
      const timeoutRate = ratio(timeouts, samples);
      const classification = classifyCase(samples, blueWinRate, timeoutRate, errorCount);
      return {
        caseId: first.caseId,
        caseHash: first.caseHash,
        samples,
        blueWins,
        redWins,
        draws,
        blueWinRate: round4(blueWinRate),
        redWinRate: round4(ratio(redWins, samples)),
        drawRate: round4(ratio(draws, samples)),
        timeoutRate: round4(timeoutRate),
        errorCount,
        avgFrames: round4(average(caseRows.map((row) => row.frames))),
        avgDurationMs: round4(average(caseRows.map((row) => row.durationMs))),
        avgBlueRemainHpRatio: round4(blueRemainRatio),
        avgRedRemainHpRatio: round4(redRemainRatio),
        avgWinnerRemainHpRatio: round4(avgWinnerRemainHpRatio),
        varianceFlag: samples < 5 || (blueWinRate > 0.25 && blueWinRate < 0.75),
        classification,
        recommendedAction: recommendAction(classification, samples),
      };
    })
    .sort((a, b) => a.caseId.localeCompare(b.caseId));

  const batchId = options.batchId || (normalizedRows[0] && normalizedRows[0].batchId) || "";
  const manifestHash = options.manifestHash || (normalizedRows[0] && normalizedRows[0].manifestHash) || "";
  const summary = {
    schema: SUMMARY_SCHEMA,
    generatedAt: nowIso(),
    buildCommit: options.buildCommit || getShortCommit(),
    batchId,
    manifestHash,
    resultPath: options.resultPath || null,
    totals: {
      cases: cases.length,
      rows: normalizedRows.length,
      errors: cases.reduce((sum, item) => sum + item.errorCount, 0),
      timeouts: normalizedRows.filter((row) => row.status === "timeout").length,
    },
    cases,
  };
  validateSummary(summary);
  return summary;
}

function validateSummary(summary) {
  const errors = [];
  if (!summary || typeof summary !== "object" || Array.isArray(summary)) {
    fail("summary must be a JSON object");
  }
  if (summary.schema !== SUMMARY_SCHEMA) {
    errors.push(`schema must be ${SUMMARY_SCHEMA}`);
  }
  assertString(summary.batchId, "batchId", errors);
  assertString(summary.manifestHash, "manifestHash", errors);
  if (!Array.isArray(summary.cases)) {
    errors.push("cases must be an array");
  } else {
    summary.cases.forEach((testCase, index) => {
      assertString(testCase.caseId, `cases[${index}].caseId`, errors);
      assertString(testCase.caseHash, `cases[${index}].caseHash`, errors);
      parsePositiveInteger(testCase.samples, `cases[${index}].samples`, errors);
      if (typeof testCase.recommendedAction !== "string") {
        errors.push(`cases[${index}].recommendedAction must be a string`);
      }
    });
  }
  if (errors.length > 0) {
    fail(`invalid summary:\n- ${errors.join("\n- ")}`);
  }
  return true;
}

function planNextBatch(summary, options) {
  validateSummary(summary);
  const decisions = summary.cases.map((testCase) => {
    let action = testCase.recommendedAction;
    let suggestedRepeat = 5;
    let reason = `${testCase.classification}; samples=${testCase.samples}; blueWinRate=${testCase.blueWinRate}`;

    if (testCase.errorCount > 0 || testCase.timeoutRate > 0.2) {
      action = "review";
      suggestedRepeat = 0;
      reason = `requires manual review before expansion; ${reason}`;
    } else if (testCase.samples < 10 && action === "append_repeat") {
      suggestedRepeat = Math.max(1, 10 - testCase.samples);
      reason = `increase sample count toward 10; ${reason}`;
    } else if (action === "append_counter_case") {
      suggestedRepeat = 5;
      reason = `add a counter-side or adjacent-level case; ${reason}`;
    }

    return {
      caseId: testCase.caseId,
      caseHash: testCase.caseHash,
      action,
      suggestedRepeat,
      reason,
    };
  });

  const plan = {
    schema: NEXT_BATCH_SCHEMA,
    generatedAt: nowIso(),
    planner: {
      name: options.planner || "rule",
      version: 1,
    },
    sourceBatchId: summary.batchId,
    sourceManifestHash: summary.manifestHash,
    sourceSummaryHash: sha256OfValue(summary),
    decisions,
  };
  validateNextBatch(plan);
  return plan;
}

function validateNextBatch(plan) {
  const errors = [];
  if (!plan || typeof plan !== "object" || Array.isArray(plan)) {
    fail("next batch plan must be a JSON object");
  }
  if (plan.schema !== NEXT_BATCH_SCHEMA) {
    errors.push(`schema must be ${NEXT_BATCH_SCHEMA}`);
  }
  assertString(plan.sourceBatchId, "sourceBatchId", errors);
  assertString(plan.sourceManifestHash, "sourceManifestHash", errors);
  if (!Array.isArray(plan.decisions)) {
    errors.push("decisions must be an array");
  } else {
    plan.decisions.forEach((decision, index) => {
      assertString(decision.caseId, `decisions[${index}].caseId`, errors);
      assertString(decision.caseHash, `decisions[${index}].caseHash`, errors);
      assertString(decision.action, `decisions[${index}].action`, errors);
      parseNonNegativeNumber(decision.suggestedRepeat, `decisions[${index}].suggestedRepeat`, errors);
    });
  }
  if (errors.length > 0) {
    fail(`invalid next batch plan:\n- ${errors.join("\n- ")}`);
  }
  return true;
}

function createFixtureRows() {
  const manifest = createPilotManifest({
    batchId: "pilot-fixture",
    createdAt: "2026-06-29T00:00:00.000Z",
    buildCommit: "fixture",
    repeat: 5,
  });
  const testCase = manifest.cases[0];
  const winners = ["blue", "red", "blue", "draw", "red"];
  return winners.map((winner, index) =>
    normalizeResultRow({
      schema: RESULT_SCHEMA,
      batchId: manifest.batchId,
      manifestHash: manifest.manifestHash,
      caseId: testCase.caseId,
      caseHash: testCase.caseHash,
      runId: `${testCase.caseId}-r${index + 1}`,
      repeatIndex: index + 1,
      status: "finished",
      winner,
      frames: 1200 + index * 20,
      durationMs: 40000 + index * 500,
      blue: {
        maxHp: 1000,
        remainHp: winner === "blue" ? 320 : winner === "draw" ? 0 : 0,
        aliveCount: winner === "blue" ? 1 : 0,
      },
      red: {
        maxHp: 1000,
        remainHp: winner === "red" ? 280 : winner === "draw" ? 0 : 0,
        aliveCount: winner === "red" ? 1 : 0,
      },
      errors: [],
      startedAt: "2026-06-29T00:00:00.000Z",
      completedAt: "2026-06-29T00:01:00.000Z",
    })
  );
}

function formatSummaryMarkdown(summary) {
  validateSummary(summary);
  const lines = [
    `# Arena Calibration Summary`,
    ``,
    `- batchId: \`${summary.batchId}\``,
    `- manifestHash: \`${summary.manifestHash}\``,
    `- rows: ${summary.totals.rows}`,
    `- errors: ${summary.totals.errors}`,
    ``,
    `| caseId | samples | blueWinRate | timeoutRate | classification | action |`,
    `| --- | ---: | ---: | ---: | --- | --- |`,
  ];
  summary.cases.forEach((testCase) => {
    lines.push(
      `| ${testCase.caseId} | ${testCase.samples} | ${testCase.blueWinRate} | ${testCase.timeoutRate} | ${testCase.classification} | ${testCase.recommendedAction} |`
    );
  });
  lines.push("");
  return lines.join("\n");
}

module.exports = {
  CASE_MANIFEST_SCHEMA,
  RESULT_SCHEMA,
  SUMMARY_SCHEMA,
  NEXT_BATCH_SCHEMA,
  analyzeRows,
  createFixtureRows,
  createPilotManifest,
  fail,
  formatSummaryMarkdown,
  normalizeManifest,
  normalizeResultRow,
  planNextBatch,
  readJsonFile,
  readJsonLines,
  sha256OfValue,
  validateNextBatch,
  validateSummary,
  writeJsonFile,
  writeJsonLines,
};
