"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { assertSchemaInstance } = require("./schema-registry");

const CASE_MANIFEST_SCHEMA = "arena-calibration.case-manifest.v1";
const RESULT_SCHEMA = "arena-calibration.result.v1";
const SUMMARY_SCHEMA = "arena-calibration.summary.v1";
const NEXT_BATCH_SCHEMA = "arena-calibration.next-batch.v1";
const DEFAULT_SPAWN_DISTANCE = 650;
const DEFAULT_FORMATION = "line";
const DEFAULT_FORMATION_SPACING = 54;
const DEFAULT_EXPLORATION_TIMEOUT_FRAMES = 1800;
const FORMATIONS = new Set(["column", "line", "wedge", "shield", "grid"]);

const RESULT_STATUSES = new Set([
  "finished",
  "timeout",
  "aborted",
  "spawn_failed",
  "invalid_case",
  "stage_failed",
  "bridge_lost",
  "contamination",
  "error",
]);

const WINNERS = new Set(["blue", "red", "draw", "timeout", "none", null]);
const BATCH_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;

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

function assertBatchId(value, fieldName, errors) {
  const batchId = assertString(value, fieldName, errors);
  if (batchId && !BATCH_ID_PATTERN.test(batchId)) {
    errors.push(`${fieldName} must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`);
  }
  return batchId;
}

function parsePositiveInteger(value, fieldName, errors) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0 || Math.floor(number) !== number) {
    errors.push(`${fieldName} must be a positive integer`);
    return 1;
  }
  return number;
}

function defaultWhenMissing(value, defaultValue) {
  return value === undefined || value === null ? defaultValue : value;
}

function parseNonNegativeNumber(value, fieldName, errors) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    errors.push(`${fieldName} must be a non-negative number`);
    return 0;
  }
  return number;
}

function normalizeFormation(value, fieldName, errors) {
  const formation = value === undefined || value === null || value === ""
    ? DEFAULT_FORMATION
    : String(value);
  if (!FORMATIONS.has(formation)) {
    errors.push(`${fieldName} must be one of ${Array.from(FORMATIONS).join(", ")}`);
    return DEFAULT_FORMATION;
  }
  return formation;
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
  const normalized = {
    type: normalizedType,
    level: parsePositiveInteger(level, `${fieldName}.level`, errors),
  };
  const sourceId = entry.sourceId === undefined ? entry["来源ID"] : entry.sourceId;
  if (sourceId !== undefined && sourceId !== null) {
    normalized.sourceId = assertString(sourceId, `${fieldName}.sourceId`, errors);
  }
  const hpPermille = entry.hpPermille === undefined ? entry["生命千分比"] : entry.hpPermille;
  if (hpPermille !== undefined && hpPermille !== null) {
    const parsed = parsePositiveInteger(hpPermille, `${fieldName}.hpPermille`, errors);
    if (parsed > 1000) errors.push(`${fieldName}.hpPermille must be at most 1000`);
    normalized.hpPermille = parsed;
  }
  const parameters = entry.parameters !== undefined
    ? entry.parameters
    : entry.Parameters !== undefined
      ? entry.Parameters
      : entry["参数"];
  if (parameters !== undefined && parameters !== null) {
    if (!parameters || typeof parameters !== "object" || Array.isArray(parameters)) {
      errors.push(`${fieldName}.parameters must be a non-empty JSON object`);
    } else if (Object.keys(parameters).length === 0) {
      errors.push(`${fieldName}.parameters must be a non-empty JSON object`);
    } else {
      normalized.parameters = stableClone(parameters);
    }
  }
  return normalized;
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
  const hashInput = {
    caseId: testCase.caseId,
    blueRoster: testCase.blueRoster,
    redRoster: testCase.redRoster,
    repeat: testCase.repeat,
    timeoutFrames: testCase.timeoutFrames,
  };
  hashInput.spawnDistance = testCase.spawnDistance;
  hashInput.blueFormation = testCase.blueFormation;
  hashInput.redFormation = testCase.redFormation;
  hashInput.formationSpacing = testCase.formationSpacing;
  if (Object.prototype.hasOwnProperty.call(testCase, "authorityContext")) {
    hashInput.authorityContext = testCase.authorityContext;
  }
  return hashInput;
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
    repeat: parsePositiveInteger(
      defaultWhenMissing(input.repeat, defaults.repeat),
      `${fieldName}.repeat`,
      errors
    ),
    timeoutFrames: parsePositiveInteger(
      defaultWhenMissing(input.timeoutFrames, defaults.timeoutFrames),
      `${fieldName}.timeoutFrames`,
      errors
    ),
    tags: normalizeTags(input.tags, `${fieldName}.tags`, errors),
    plannerReason:
      input.plannerReason === undefined
        ? ""
        : assertString(input.plannerReason, `${fieldName}.plannerReason`, errors),
    spawnDistance: parsePositiveInteger(
      defaultWhenMissing(input.spawnDistance, defaults.spawnDistance),
      `${fieldName}.spawnDistance`,
      errors
    ),
    blueFormation: normalizeFormation(
      defaultWhenMissing(input.blueFormation, defaults.blueFormation),
      `${fieldName}.blueFormation`,
      errors
    ),
    redFormation: normalizeFormation(
      defaultWhenMissing(input.redFormation, defaults.redFormation),
      `${fieldName}.redFormation`,
      errors
    ),
    formationSpacing: parsePositiveInteger(
      defaultWhenMissing(input.formationSpacing, defaults.formationSpacing),
      `${fieldName}.formationSpacing`,
      errors
    ),
  };
  if (input.authorityContext !== undefined && input.authorityContext !== null) {
    if (!input.authorityContext || typeof input.authorityContext !== "object" || Array.isArray(input.authorityContext)) {
      errors.push(`${fieldName}.authorityContext must be an object`);
    } else {
      testCase.authorityContext = stableClone(input.authorityContext);
    }
  }
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

  const repeat = parsePositiveInteger(defaultWhenMissing(input.repeat, 5), "repeat", errors);
  const timeoutFrames = parsePositiveInteger(
    defaultWhenMissing(input.timeoutFrames, DEFAULT_EXPLORATION_TIMEOUT_FRAMES),
    "timeoutFrames",
    errors
  );
  const manifest = {
    schema: input.schema || CASE_MANIFEST_SCHEMA,
    batchId: assertBatchId(input.batchId, "batchId", errors),
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
    const defaults = {
      repeat,
      timeoutFrames,
      spawnDistance: DEFAULT_SPAWN_DISTANCE,
      blueFormation: DEFAULT_FORMATION,
      redFormation: DEFAULT_FORMATION,
      formationSpacing: DEFAULT_FORMATION_SPACING,
    };
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
  assertSchemaInstance(CASE_MANIFEST_SCHEMA, manifest, "normalized case manifest");
  return manifest;
}

function createPilotManifest(options) {
  const batchId = options.batchId || `pilot-${localDateString(new Date())}-a`;
  const repeat = defaultWhenMissing(options.repeat, 5);
  const timeoutFrames = defaultWhenMissing(options.timeoutFrames, DEFAULT_EXPLORATION_TIMEOUT_FRAMES);
  const spawnDistance = defaultWhenMissing(options.spawnDistance, DEFAULT_SPAWN_DISTANCE);
  const blueFormation = defaultWhenMissing(options.blueFormation, DEFAULT_FORMATION);
  const redFormation = defaultWhenMissing(options.redFormation, DEFAULT_FORMATION);
  const formationSpacing = defaultWhenMissing(options.formationSpacing, DEFAULT_FORMATION_SPACING);
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
    repeat,
    timeoutFrames,
    blueBench: {
      benchId: "thief-lv30x4",
      roster: thiefRoster,
    },
    cases: [
      {
        caseId: "pilot-thief-lv30x4-mirror",
        blueRoster: thiefRoster,
        redRoster: thiefRoster,
        repeat,
        timeoutFrames,
        spawnDistance,
        blueFormation,
        redFormation,
        formationSpacing,
        tags: ["pilot", "manual-anchor", "mirror"],
        plannerReason: "复用现有 _root.测试角斗场怪物 默认盗贼组作为通路锚点",
      },
    ],
  });
}

function normalizeSpawnedUnits(input, fieldName, errors) {
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
      return { side: "", unit: "", from: "", name: "", frame: null };
    }
    const side = entry.side === "blue" || entry.side === "red" ? entry.side : "";
    if (!side) errors.push(`${fieldName}[${index}].side must be blue or red`);
    const normalized = {
      side,
      unit: entry.unit == null ? "" : String(entry.unit),
      from: entry.from == null
        ? (entry.parentUnit == null ? "" : String(entry.parentUnit))
        : String(entry.from),
      name: entry.name == null ? "" : String(entry.name),
      frame: entry.frame === undefined || entry.frame === null
        ? null
        : parseNonNegativeNumber(entry.frame, `${fieldName}[${index}].frame`, errors),
    };
    if (entry.auxiliary !== undefined && entry.auxiliary !== null) {
      if (typeof entry.auxiliary !== "boolean") {
        errors.push(`${fieldName}[${index}].auxiliary must be a boolean`);
      } else {
        normalized.auxiliary = entry.auxiliary;
      }
    }
    return normalized;
  });
}

function normalizeJsonObject(input, fieldName, errors) {
  if (input === undefined || input === null) return {};
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    errors.push(`${fieldName} must be an object`);
    return {};
  }
  return stableClone(input);
}

function normalizeUnitResults(input, fieldName, errors) {
  if (input === undefined || input === null) return [];
  if (!Array.isArray(input)) {
    errors.push(`${fieldName} must be an array`);
    return [];
  }
  return input.map((entry, index) => {
    const itemField = `${fieldName}[${index}]`;
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(`${itemField} must be an object`);
      return {
        sourceId: "", petId: -1, identifier: "", resolvedType: "", level: 1,
        strategicPromotions: [], strategicPromotionsValid: false,
        startMaxHp: 0, remainHp: 0, hpPermille: 0, alive: false,
      };
    }
    const sourceId = assertString(entry.sourceId, `${itemField}.sourceId`, errors);
    if (sourceId && !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(sourceId)) {
      errors.push(`${itemField}.sourceId is invalid`);
    }
    function integerInRange(value, name, minimum, maximum, fallback) {
      const number = Number(value);
      if (!Number.isInteger(number) || number < minimum || number > maximum) {
        errors.push(`${name} must be an integer from ${minimum} to ${maximum}`);
        return fallback;
      }
      return number;
    }
    let promotions = entry.strategicPromotions;
    if (!Array.isArray(promotions)) {
      errors.push(`${itemField}.strategicPromotions must be an array`);
      promotions = [];
    }
    const allowedPromotions = new Set(["基础训练", "强化药剂", "超级血清"]);
    const seenPromotions = new Set();
    promotions = promotions.map((value, promotionIndex) => {
      const promotion = String(value);
      if (!allowedPromotions.has(promotion) || seenPromotions.has(promotion)) {
        errors.push(`${itemField}.strategicPromotions[${promotionIndex}] is invalid or duplicated`);
      }
      seenPromotions.add(promotion);
      return promotion;
    });
    if (promotions.length > 3) errors.push(`${itemField}.strategicPromotions must have at most 3 entries`);
    if (typeof entry.strategicPromotionsValid !== "boolean") {
      errors.push(`${itemField}.strategicPromotionsValid must be a boolean`);
    }
    if (typeof entry.alive !== "boolean") errors.push(`${itemField}.alive must be a boolean`);
    return {
      sourceId,
      petId: integerInRange(entry.petId, `${itemField}.petId`, -1, 1000000, -1),
      identifier: entry.identifier == null ? "" : String(entry.identifier),
      resolvedType: entry.resolvedType == null ? "" : String(entry.resolvedType),
      level: integerInRange(entry.level, `${itemField}.level`, 1, 1000000, 1),
      strategicPromotions: promotions,
      strategicPromotionsValid: entry.strategicPromotionsValid === true,
      startMaxHp: parseNonNegativeNumber(entry.startMaxHp, `${itemField}.startMaxHp`, errors),
      remainHp: parseNonNegativeNumber(entry.remainHp, `${itemField}.remainHp`, errors),
      hpPermille: integerInRange(entry.hpPermille, `${itemField}.hpPermille`, 0, 1000, 0),
      alive: entry.alive === true,
    };
  });
}

function normalizeSpawnPositions(input, fieldName, errors) {
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
      return { side: "", index: 0, unit: "", level: 0, name: "", x: 0, y: 0 };
    }
    const side = entry.side === "blue" || entry.side === "red" ? entry.side : "";
    if (!side) {
      errors.push(`${fieldName}[${index}].side must be blue or red`);
    }
    return {
      side,
      index:
        entry.index === undefined || entry.index === null
          ? null
          : parseNonNegativeNumber(entry.index, `${fieldName}[${index}].index`, errors),
      unit: entry.unit == null ? "" : String(entry.unit),
      level:
        entry.level === undefined || entry.level === null
          ? 0
          : parseNonNegativeNumber(entry.level, `${fieldName}[${index}].level`, errors),
      name: entry.name == null ? "" : String(entry.name),
      x: entry.x === undefined || entry.x === null
        ? null
        : parseNonNegativeNumber(entry.x, `${fieldName}[${index}].x`, errors),
      y: entry.y === undefined || entry.y === null
        ? null
        : parseNonNegativeNumber(entry.y, `${fieldName}[${index}].y`, errors),
    };
  });
}

function normalizeFormationAudit(input, errors) {
  if (input !== undefined && input !== null && (!input || typeof input !== "object" || Array.isArray(input))) {
    errors.push("formationAudit must be an object");
  }
  const source = input && typeof input === "object" && !Array.isArray(input) ? input : {};
  return {
    blue: normalizeFormationAuditSide(source.blue, "formationAudit.blue", errors),
    red: normalizeFormationAuditSide(source.red, "formationAudit.red", errors),
  };
}

function normalizeFormationAuditSide(input, fieldName, errors) {
  if (input !== undefined && input !== null && (!input || typeof input !== "object" || Array.isArray(input))) {
    errors.push(`${fieldName} must be an object`);
  }
  const source = input && typeof input === "object" && !Array.isArray(input) ? input : {};
  return {
    count: parseNonNegativeNumber(source.count || 0, `${fieldName}.count`, errors),
    minX: parseNonNegativeNumber(source.minX || 0, `${fieldName}.minX`, errors),
    maxX: parseNonNegativeNumber(source.maxX || 0, `${fieldName}.maxX`, errors),
    minY: parseNonNegativeNumber(source.minY || 0, `${fieldName}.minY`, errors),
    maxY: parseNonNegativeNumber(source.maxY || 0, `${fieldName}.maxY`, errors),
    xRange: parseNonNegativeNumber(source.xRange || 0, `${fieldName}.xRange`, errors),
    yRange: parseNonNegativeNumber(source.yRange || 0, `${fieldName}.yRange`, errors),
    distinctX: parseNonNegativeNumber(source.distinctX || 0, `${fieldName}.distinctX`, errors),
    distinctY: parseNonNegativeNumber(source.distinctY || 0, `${fieldName}.distinctY`, errors),
  };
}

function normalizeSideSummary(input, fieldName, errors) {
  const source = input || {};
  const maxHp = parseNonNegativeNumber(source.maxHp || 0, `${fieldName}.maxHp`, errors);
  const remainHp = parseNonNegativeNumber(source.remainHp || 0, `${fieldName}.remainHp`, errors);
  const aliveCount = parseNonNegativeNumber(source.aliveCount || 0, `${fieldName}.aliveCount`, errors);
  const startMaxHp = parseNonNegativeNumber(
    source.startMaxHp === undefined ? maxHp : source.startMaxHp,
    `${fieldName}.startMaxHp`,
    errors
  );
  const startCount = parseNonNegativeNumber(
    source.startCount === undefined ? aliveCount : source.startCount,
    `${fieldName}.startCount`,
    errors
  );
  return {
    maxHp,
    remainHp,
    aliveCount,
    startMaxHp,
    startCount,
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
    const normalized = {
      code: assertString(entry.code || "error", `${fieldName}[${index}].code`, errors),
      side: entry.side || null,
      unit: entry.unit || null,
      message: entry.message || "",
    };
    ["identifier", "name"].forEach((field) => {
      if (entry[field] !== undefined && entry[field] !== null) normalized[field] = String(entry[field]);
    });
    ["petId", "count"].forEach((field) => {
      if (entry[field] !== undefined && entry[field] !== null) {
        normalized[field] = parseNonNegativeNumber(entry[field], `${fieldName}[${index}].${field}`, errors);
      }
    });
    return normalized;
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
    batchId: assertBatchId(input.batchId, "batchId", errors),
    manifestHash: assertString(input.manifestHash, "manifestHash", errors),
    caseId: assertString(input.caseId, "caseId", errors),
    caseHash: assertString(input.caseHash, "caseHash", errors),
    runId: assertString(input.runId, "runId", errors),
    repeatIndex: parsePositiveInteger(defaultWhenMissing(input.repeatIndex, 1), "repeatIndex", errors),
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
    requestedSpawnDistance:
      input.requestedSpawnDistance === undefined || input.requestedSpawnDistance === null
        ? null
        : parseNonNegativeNumber(input.requestedSpawnDistance, "requestedSpawnDistance", errors),
    spawnDistance:
      input.spawnDistance === undefined || input.spawnDistance === null
        ? null
        : parseNonNegativeNumber(input.spawnDistance, "spawnDistance", errors),
    blueFormation: normalizeFormation(input.blueFormation, "blueFormation", errors),
    redFormation: normalizeFormation(input.redFormation, "redFormation", errors),
    formationSpacing: parsePositiveInteger(
      defaultWhenMissing(input.formationSpacing, DEFAULT_FORMATION_SPACING),
      "formationSpacing",
      errors
    ),
    phaseSpawnCount:
      input.phaseSpawnCount === undefined || input.phaseSpawnCount === null
        ? 0
        : parseNonNegativeNumber(input.phaseSpawnCount, "phaseSpawnCount", errors),
    spawnedUnits: normalizeSpawnedUnits(input.spawnedUnits, "spawnedUnits", errors),
    blueX:
      input.blueX === undefined || input.blueX === null
        ? null
        : parseNonNegativeNumber(input.blueX, "blueX", errors),
    redX:
      input.redX === undefined || input.redX === null
        ? null
        : parseNonNegativeNumber(input.redX, "redX", errors),
    blueSpawnPositions: normalizeSpawnPositions(input.blueSpawnPositions, "blueSpawnPositions", errors),
    redSpawnPositions: normalizeSpawnPositions(input.redSpawnPositions, "redSpawnPositions", errors),
    formationAudit: normalizeFormationAudit(input.formationAudit, errors),
    authorityContext: normalizeJsonObject(input.authorityContext, "authorityContext", errors),
    blue: normalizeSideSummary(input.blue, "blue", errors),
    red: normalizeSideSummary(input.red, "red", errors),
    blueUnitResults: normalizeUnitResults(input.blueUnitResults, "blueUnitResults", errors),
    redUnitResults: normalizeUnitResults(input.redUnitResults, "redUnitResults", errors),
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
  assertSchemaInstance(RESULT_SCHEMA, row, "normalized result row");
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
      const errorCount = caseRows.filter(
        (row) => row.status !== "finished" && row.status !== "timeout"
      ).length;
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
  assertBatchId(summary.batchId, "batchId", errors);
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
  assertSchemaInstance(SUMMARY_SCHEMA, summary, "arena calibration summary");
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
  assertSchemaInstance(NEXT_BATCH_SCHEMA, plan, "arena calibration next batch");
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
        startMaxHp: 1000,
        startCount: 4,
      },
      red: {
        maxHp: 1000,
        remainHp: winner === "red" ? 280 : winner === "draw" ? 0 : 0,
        aliveCount: winner === "red" ? 1 : 0,
        startMaxHp: 1000,
        startCount: 4,
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
  DEFAULT_SPAWN_DISTANCE,
  DEFAULT_FORMATION,
  DEFAULT_FORMATION_SPACING,
  DEFAULT_EXPLORATION_TIMEOUT_FRAMES,
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
