#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

import {
  applyXmlBatchUpdates,
  discoverXmlFiles,
  loadProjectContext,
  loadXmlDocument,
  previewXmlBatchUpdates,
  runXmlRoundtripCheck,
  scanProjectFields
} from "@cf7-balance-tool/xml-io";
import type { XmlBatchOptions, XmlBatchUpdate } from "@cf7-balance-tool/xml-io";
import {
  computeWeaponRow,
  computeArmorRow,
  computeMeleeRow,
  computeExplosivesRow,
  computePhysicalDamage,
  computeMagicDamage,
  computeWeaponPrice,
  computeArmorPrice,
  computeSynthesis,
  computeDungeonReward,
  computePotionRow,
  computeMonsterRow,
} from "@cf7-balance-tool/core";

interface CliOptions {
  attribute?: string;
  file?: string;
  filter?: string;
  inPlace: boolean;
  input?: string;
  input2?: string;
  limit?: number;
  output?: string;
  outputDir?: string;
  path?: string;
  project?: string;
  sort?: string;
  value?: string;
}

interface BatchCommandContext {
  inputPath: string;
  projectConfigPath: string;
  projectRoot: string;
  updates: XmlBatchUpdate[];
  batchOptions: XmlBatchOptions;
}

function main(): void {
  const args = process.argv.slice(2);
  const [group, action] = args;

  if (group === "project" && action === "scan") {
    runProjectScan(args.slice(2));
    return;
  }

  if (group === "project" && action === "fields") {
    runFieldScan(args.slice(2));
    return;
  }

  if (group === "project" && action === "roundtrip-check") {
    runProjectRoundtripCheck(args.slice(2));
    return;
  }

  if (group === "project" && action === "batch-preview") {
    runProjectBatchPreview(args.slice(2));
    return;
  }

  if (group === "project" && action === "batch-set") {
    runProjectBatchSet(args.slice(2));
    return;
  }

  if (group === "xml" && action === "get") {
    runXmlGet(args.slice(2));
    return;
  }

  if (group === "xml" && action === "set") {
    runXmlSet(args.slice(2));
    return;
  }

  if (group === "calibrate") {
    runCalibrate(args.slice(1));
    return;
  }

  if (group === "calc") {
    runCalc(args.slice(1));
    return;
  }

  if (group === "query") {
    runQuery(args.slice(1));
    return;
  }

  if (group === "diff") {
    runDiff(args.slice(1));
    return;
  }

  if (group === "validate") {
    runValidate(args.slice(1));
    return;
  }

  printHelp();
  process.exitCode = 1;
}

function runProjectScan(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const files = discoverXmlFiles(projectConfigPath);

  emitJson(
    {
      projectConfigPath,
      totals: {
        files: files.length
      },
      files
    },
    options.output
  );
}

function runFieldScan(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const report = scanProjectFields(projectConfigPath);

  emitJson(report, options.output);
}

function runProjectRoundtripCheck(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const files = discoverXmlFiles(projectConfigPath);
  const report = runXmlRoundtripCheck(files.map((file) => file.absolutePath));

  emitJson(
    {
      projectConfigPath,
      ...report
    },
    options.output
  );
}

function runProjectBatchPreview(args: string[]): void {
  const context = resolveBatchCommandContext(args);
  const result = previewXmlBatchUpdates(context.updates, context.batchOptions);

  emitJson(
    {
      projectConfigPath: context.projectConfigPath,
      inputPath: context.inputPath,
      ...result
    },
    parseOptions(args).output
  );
}

function runProjectBatchSet(args: string[]): void {
  const context = resolveBatchCommandContext(args);
  const result = applyXmlBatchUpdates(context.updates, context.batchOptions);

  emitJson(
    {
      projectConfigPath: context.projectConfigPath,
      inputPath: context.inputPath,
      ...result
    },
    parseOptions(args).output
  );
}

function runXmlGet(args: string[]): void {
  const options = parseOptions(args);
  const filePath = resolveRequiredFilePath(options.file);
  const xmlPath = requireOption(options.path, "--path");
  const document = loadXmlDocument(filePath);
  const value = options.attribute
    ? document.getAttribute(xmlPath, options.attribute)
    : document.getNodeText(xmlPath);

  if (value === undefined) {
    throw new Error(`XML value not found: ${xmlPath}`);
  }

  emitJson(
    {
      file: filePath,
      xmlPath,
      attribute: options.attribute ?? null,
      value
    },
    options.output
  );
}

function runXmlSet(args: string[]): void {
  const options = parseOptions(args);
  const filePath = resolveRequiredFilePath(options.file);
  const xmlPath = requireOption(options.path, "--path");
  const nextValue = requireOption(options.value, "--value");
  const document = loadXmlDocument(filePath);

  if (options.attribute) {
    document.setAttribute(xmlPath, options.attribute, nextValue);
  } else {
    document.setNodeText(xmlPath, nextValue);
  }

  const serialized = document.serialize();

  if (options.inPlace) {
    document.save(filePath);
    process.stdout.write(`${filePath}\n`);
    return;
  }

  if (options.output) {
    const outputPath = path.resolve(process.cwd(), options.output);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, serialized, "utf8");
    process.stdout.write(`${outputPath}\n`);
    return;
  }

  process.stdout.write(serialized);
}

function resolveBatchCommandContext(args: string[]): BatchCommandContext {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const projectContext = loadProjectContext(projectConfigPath);
  const inputPath = path.resolve(process.cwd(), requireOption(options.input, "--input"));
  const updates = loadBatchUpdates(inputPath).map((update) => ({
    ...update,
    filePath: resolveBatchFilePath(update.filePath, inputPath, projectContext.projectRoot)
  }));
  const baseDir = resolveCommonBaseDir([
    projectContext.projectRoot,
    projectContext.resolvedDirs.items,
    projectContext.resolvedDirs.mods,
    projectContext.resolvedDirs.enemies
  ]);
  const batchOptions = createBatchOptions(options, baseDir);

  return {
    inputPath,
    projectConfigPath,
    projectRoot: projectContext.projectRoot,
    updates,
    batchOptions
  };
}

function createBatchOptions(options: CliOptions, baseDir?: string): XmlBatchOptions {
  return {
    ...(baseDir ? { baseDir } : {}),
    ...(options.inPlace ? { inPlace: true } : {}),
    ...(options.outputDir ? { outputDir: options.outputDir } : {})
  };
}

function emitJson(payload: unknown, output?: string): void {
  const serialized = JSON.stringify(payload, null, 2);

  if (output) {
    const absoluteOutputPath = path.resolve(process.cwd(), output);
    fs.mkdirSync(path.dirname(absoluteOutputPath), { recursive: true });
    fs.writeFileSync(absoluteOutputPath, serialized, "utf8");
    process.stdout.write(`${absoluteOutputPath}\n`);
    return;
  }

  process.stdout.write(`${serialized}\n`);
}

function loadBatchUpdates(inputPath: string): XmlBatchUpdate[] {
  const rawInput = fs.readFileSync(inputPath, "utf8");
  const parsed = JSON.parse(rawInput) as unknown;
  const rawUpdates = Array.isArray(parsed)
    ? parsed
    : isRecord(parsed) && Array.isArray(parsed.updates)
      ? parsed.updates
      : undefined;

  if (!rawUpdates) {
    throw new Error("Batch input must be an array or an object with an updates array.");
  }

  return rawUpdates.map((entry, index) => parseBatchUpdate(entry, index));
}

function parseBatchUpdate(entry: unknown, index: number): XmlBatchUpdate {
  if (!isRecord(entry)) {
    throw new Error(`Batch update at index ${index} must be an object.`);
  }

  const filePath = requireStringOption(entry.filePath, `updates[${index}].filePath`);
  const xmlPath = requireStringOption(entry.xmlPath, `updates[${index}].xmlPath`);
  const value = requireStringOption(entry.value, `updates[${index}].value`);
  const attribute = entry.attribute;
  const update: XmlBatchUpdate = {
    filePath,
    xmlPath,
    value
  };

  if (attribute !== undefined) {
    if (typeof attribute !== "string") {
      throw new Error(`updates[${index}].attribute must be a string when provided.`);
    }

    update.attribute = attribute;
  }

  return update;
}

function parseOptions(args: string[]): CliOptions {
  const options: CliOptions = {
    inPlace: false
  };

  for (let index = 0; index < args.length; index += 1) {
    const current = args[index];
    const next = args[index + 1];

    if ((current === "--attribute" || current === "--attr") && next) {
      options.attribute = next;
      index += 1;
      continue;
    }

    if (current === "--file" && next) {
      options.file = next;
      index += 1;
      continue;
    }

    if (current === "--input" && next) {
      options.input = next;
      index += 1;
      continue;
    }

    if (current === "--output" && next) {
      options.output = next;
      index += 1;
      continue;
    }

    if (current === "--output-dir" && next) {
      options.outputDir = next;
      index += 1;
      continue;
    }

    if (current === "--path" && next) {
      options.path = next;
      index += 1;
      continue;
    }

    if (current === "--project" && next) {
      options.project = next;
      index += 1;
      continue;
    }

    if (current === "--input2" && next) {
      options.input2 = next;
      index += 1;
      continue;
    }

    if (current === "--filter" && next) {
      options.filter = next;
      index += 1;
      continue;
    }

    if (current === "--sort" && next) {
      options.sort = next;
      index += 1;
      continue;
    }

    if (current === "--limit" && next) {
      options.limit = parseInt(next, 10);
      index += 1;
      continue;
    }

    if (current === "--value" && next) {
      options.value = next;
      index += 1;
      continue;
    }

    if (current === "--in-place") {
      options.inPlace = true;
    }
  }

  return options;
}

function resolveProjectConfigPath(value?: string): string {
  if (value) {
    const directPath = path.resolve(process.cwd(), value);

    if (fs.existsSync(directPath)) {
      return directPath;
    }

    const fallbackFromValue = findProjectConfig(
      path.dirname(directPath),
      path.basename(value)
    );
    if (fallbackFromValue) {
      return fallbackFromValue;
    }

    return directPath;
  }

  const fallback = findProjectConfig(process.cwd(), "project.json");
  return fallback ?? path.resolve(process.cwd(), "project.json");
}

function resolveRequiredFilePath(value?: string): string {
  return path.resolve(process.cwd(), requireOption(value, "--file"));
}

function requireOption(value: string | undefined, flagName: string): string {
  if (!value) {
    throw new Error(`Missing required option: ${flagName}`);
  }

  return value;
}

function requireStringOption(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty string.`);
  }

  return value;
}

function findProjectConfig(startDir: string, fileName: string): string | undefined {
  let currentDir = path.resolve(startDir);

  while (true) {
    const candidate = path.join(currentDir, fileName);
    if (fs.existsSync(candidate)) {
      return candidate;
    }

    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) {
      return undefined;
    }

    currentDir = parentDir;
  }
}

function resolveBatchFilePath(filePath: string, inputPath: string, projectRoot: string): string {
  if (path.isAbsolute(filePath)) {
    return filePath;
  }

  const inputRelativePath = path.resolve(path.dirname(inputPath), filePath);
  if (fs.existsSync(inputRelativePath)) {
    return inputRelativePath;
  }

  const projectRelativePath = path.resolve(projectRoot, filePath);
  if (fs.existsSync(projectRelativePath)) {
    return projectRelativePath;
  }

  return projectRelativePath;
}

function resolveCommonBaseDir(values: Array<string | undefined>): string | undefined {
  const normalizedValues = values
    .filter((value): value is string => Boolean(value))
    .map((value) => path.resolve(value));

  const [firstValue, ...restValues] = normalizedValues;

  if (!firstValue) {
    return undefined;
  }

  let currentBase = firstValue;

  for (const value of restValues) {
    currentBase = findCommonAncestor(currentBase, value);
  }

  return currentBase;
}

function findCommonAncestor(left: string, right: string): string {
  const leftPath = splitResolvedPath(left);
  const rightPath = splitResolvedPath(right);

  if (leftPath.root.toLowerCase() !== rightPath.root.toLowerCase()) {
    return leftPath.root;
  }

  const sharedSegments: string[] = [];
  const sharedLength = Math.min(leftPath.segments.length, rightPath.segments.length);

  for (let index = 0; index < sharedLength; index += 1) {
    const leftSegment = leftPath.segments[index];
    const rightSegment = rightPath.segments[index];

    if (!leftSegment || !rightSegment || leftSegment.toLowerCase() !== rightSegment.toLowerCase()) {
      break;
    }

    sharedSegments.push(leftSegment);
  }

  return sharedSegments.length > 0
    ? path.join(leftPath.root, ...sharedSegments)
    : leftPath.root;
}

function splitResolvedPath(value: string): { root: string; segments: string[] } {
  const absolutePath = path.resolve(value);
  const parsedPath = path.parse(absolutePath);

  return {
    root: parsedPath.root,
    segments: absolutePath.slice(parsedPath.root.length).split(path.sep).filter(Boolean)
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

// ─── Formula engine types ───

type FormulaCategory = "weapons" | "armor" | "melee" | "explosives" | "potions" | "monsters"
  | "physicalDamage" | "magicDamage" | "weaponPrice" | "armorPrice" | "synthesis" | "dungeonRewards";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyFn = (input: any) => any;
const FORMULA_REGISTRY: Record<FormulaCategory, AnyFn> = {
  weapons: computeWeaponRow,
  armor: computeArmorRow,
  melee: computeMeleeRow,
  explosives: computeExplosivesRow,
  potions: computePotionRow,
  monsters: computeMonsterRow,
  physicalDamage: computePhysicalDamage,
  magicDamage: computeMagicDamage,
  weaponPrice: computeWeaponPrice,
  armorPrice: computeArmorPrice,
  synthesis: computeSynthesis,
  dungeonRewards: computeDungeonReward,
};

// ─── calibrate command ───

interface CalibrationResult {
  category: string;
  row: number;
  field: string;
  cached: number;
  computed: number;
  relativeError: number;
  pass: boolean;
}

function runCalibrate(args: string[]): void {
  const options = parseOptions(args);
  const baselinePath = requireOption(options.input, "--input");
  const absolutePath = path.resolve(process.cwd(), baselinePath);
  const rawBaseline = JSON.parse(fs.readFileSync(absolutePath, "utf8")) as Record<string, unknown>;

  const THRESHOLD = 0.001;
  const results: CalibrationResult[] = [];

  const WEAPONS_MAP: Array<[string, string]> = [
    ["伤害加成", "damageBonus"], ["剧毒", "poison"], ["单段伤害", "singleShotDamage"],
    ["周期伤害", "cycleDamage"], ["平均dps", "averageDPS"], ["平均射速", "averageFireRate"],
    ["吃拐率", "hitRate"], ["吃拐系数", "hitRateCoeff"], ["冲击力系数", "impactCoeff"],
    ["裸伤dps", "nakedDPS"], ["经济加成dps", "economicDPS"], ["平衡裸伤dps", "balanceNakedDPS"],
    ["增益dps", "boostDPS"], ["平衡增益dps", "balanceBoostDPS"], ["平衡dps", "balanceDPS"],
    ["加权dps", "weightedDPS"], ["平衡周期伤害", "balanceCycleDamage"],
    ["加权周期伤害", "weightedCycleDamage"], ["周期伤害系数", "cycleDamageCoeff"],
    ["平衡基础dps", "balanceBaseDPS"], ["旧平衡dps", "oldBalanceDPS"],
    ["周期dps", "cycleDPS"], ["周期dps系数", "cycleDPSCoeff"], ["dps总公式", "dpsFormula"],
  ];
  const ARMOR_MAP: Array<[string, string]> = [
    ["当前总分", "currentScore"], ["平衡总分", "balanceScore"], ["加权总分", "weightedScore"],
    ["法抗均值上限", "magicDefAvgCap"], ["法抗最高上限", "magicDefMaxCap"],
  ];
  const MELEE_MAP: Array<[string, string]> = [["推荐锋利度", "recommendedSharpness"]];
  const EXPLOSIVES_MAP: Array<[string, string]> = [["推荐单发威力", "recommendedPower"]];
  const POTIONS_MAP: Array<[string, string]> = [
    ["恢复药强度", "recoveryStrength"], ["净化强度", "purifyStrength"],
    ["剧毒强度", "toxicStrength"], ["buff强度", "buffStrength"],
    ["当前数值", "currentValue"], ["数值上限", "valueCap"],
    ["原始推荐价格", "rawPrice"], ["推荐价格", "recommendedPrice"],
  ];
  const MONSTERS_MAP: Array<[string, string]> = [
    ["空手攻击MIN", "atkMin"], ["空手攻击MAX", "atkMax"],
    ["HP最小值", "hpMin"], ["HP最大值", "hpMax"],
    ["防御力MIX", "defMin"], ["防御力MAX", "defMax"],
    ["经验MIN", "expMin"], ["经验MAX", "expMax"],
    ["金币价格", "goldPrice"], ["K点价格", "kPointPrice"],
  ];

  // Weapons
  calibrateCategory(rawBaseline, "weapons", results, THRESHOLD, (row) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const inp = row.input as any;
    if (inp["子弹威力"] == null) return undefined;
    return computeWeaponRow({
      level: inp["限制等级"], bulletPower: inp["子弹威力"], shootInterval: inp["射击间隔"],
      magSize: inp["弹容量"], magPrice: inp["弹夹价格"], weight: inp["重量"],
      dualWieldFactor: inp["双枪系数"], pierceFactor: inp["穿刺系数"],
      damageTypeFactor: inp["伤害类型系数"], shotgunValue: inp["霰弹值"],
      impact: inp["冲击力"], extraWeightLayers: inp["额外加权层数"],
    });
  }, WEAPONS_MAP);

  // Armor
  calibrateCategory(rawBaseline, "armor", results, THRESHOLD, (row) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const inp = row.input as any;
    if (inp["防御"] == null) return undefined;
    const t = String(inp["类型"] ?? "");
    const name = String(inp["具体装备"] ?? "");
    const type = t.includes("手套") ? "glove" as const
      : (t === "项链" || name.includes("项链")) ? "necklace" as const
      : "standard" as const;
    return computeArmorRow({
      level: inp["限制等级"], defence: inp["防御"],
      hp: inp["HP"], mp: inp["MP"],
      damageBonus: inp["伤害加成"], weaponBonus: inp["刀/枪总加成"],
      weight: inp["重量"], punchBonus: inp["空手加成"],
      magicDefence: inp["法抗"], extraWeightLayers: inp["额外加权层数"],
      type,
    });
  }, ARMOR_MAP);

  // Melee
  calibrateCategory(rawBaseline, "melee", results, THRESHOLD, (row) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const inp = row.input as any;
    if (typeof inp["限制等级"] !== "number") return undefined;
    return computeMeleeRow({
      level: inp["限制等级"], weight: inp["重量"],
      damageTypeFactor: inp["伤害类型系数"], weightLayers: inp["加权层数"],
    });
  }, MELEE_MAP);

  // Explosives (gun-type only)
  calibrateCategory(rawBaseline, "explosives", results, THRESHOLD, (row) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const inp = row.input as any;
    if (typeof inp["弹夹价格"] !== "number" || row._row > 10) return undefined;
    return computeExplosivesRow({
      magPrice: inp["弹夹价格"], magSize: inp["弹容量"],
      level: inp["限制等级"], weightLayers: inp["加权层级"] ?? 0,
    });
  }, EXPLOSIVES_MAP);

  // Potions
  calibrateCategory(rawBaseline, "potions", results, THRESHOLD, (row) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const inp = row.input as any;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const cached = row.cached as any;
    if (typeof inp["玩家等级"] !== "number") return undefined;
    return computePotionRow({
      hp: cached["hp"] ?? 0, mp: cached["mp"] ?? 0,
      sustainFrames: cached["缓释持续帧"] ?? 0,
      playerLevel: inp["玩家等级"], isGroup: inp["是否群体"] ?? 0,
      purifyValue: inp["净化值"] ?? 0, toxicity: inp["剧毒性"] ?? 0,
      buffHp: inp["buff-hp"] ?? 0, buffMp: inp["buff-mp"] ?? 0,
      buffDefence: inp["buff-防御"] ?? 0, buffMagicResist: inp["buff-魔抗"] ?? 0,
      buffDamage: inp["buff-伤害"] ?? 0, buffPunch: inp["buff-空手"] ?? 0,
      buffSpeed: inp["buff-速度"] ?? 0, buffDuration: inp["buff-持续帧"] ?? 0,
    });
  }, POTIONS_MAP);

  // Monsters
  calibrateCategory(rawBaseline, "monsters", results, THRESHOLD, (row) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const inp = row.input as any;
    if (typeof inp["阶段"] !== "number" || typeof inp["档次系数"] !== "number") return undefined;
    return computeMonsterRow({
      stage: inp["阶段"], tierFactor: inp["档次系数"], growthFactor: inp["成长系数"],
      atkSpeedFactor: inp["攻速系数"], atkMultiplier: inp["攻击倍率"],
      segmentFactor: inp["段数系数"], speedFactor: inp["速度系数"],
      highAtkFactor: inp["高攻低血防系数"], superArmorFactor: inp["霸体系数"],
      highDefFactor: inp["高防低血系数"],
    });
  }, MONSTERS_MAP);

  const passed = results.filter(r => r.pass).length;
  const failed = results.filter(r => !r.pass).length;

  emitJson({
    summary: { total: results.length, passed, failed, threshold: THRESHOLD },
    failures: results.filter(r => !r.pass),
    details: results,
  }, options.output);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type BaselineRowRaw = { _row: number; input: any; cached: any };

function calibrateCategory(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  baseline: any,
  category: string,
  results: CalibrationResult[],
  threshold: number,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  computeFn: (row: BaselineRowRaw) => any,
  columnMap?: Array<[string, string]>,
): void {
  const rows = baseline[category] as BaselineRowRaw[] | undefined;
  if (!rows) return;

  for (const row of rows) {
    const computed = computeFn(row);
    if (!computed) continue;

    if (columnMap) {
      for (const [cnName, fieldKey] of columnMap) {
        const cachedVal = (row.cached as Record<string, unknown>)[cnName];
        if (typeof cachedVal !== "number") continue;
        const computedVal = (computed as Record<string, unknown>)[fieldKey];
        if (typeof computedVal !== "number") continue;

        const relErr = Math.abs(computedVal - cachedVal) / (Math.abs(cachedVal) + 1e-10);
        results.push({
          category, row: row._row, field: cnName,
          cached: cachedVal, computed: computedVal,
          relativeError: relErr, pass: relErr < threshold,
        });
      }
    } else {
      for (const [key, cachedVal] of Object.entries(row.cached as Record<string, unknown>)) {
        if (typeof cachedVal !== "number") continue;
        const computedVal = (computed as Record<string, unknown>)[key];
        if (typeof computedVal !== "number") continue;

        const relErr = Math.abs(computedVal - cachedVal) / (Math.abs(cachedVal) + 1e-10);
        results.push({
          category, row: row._row, field: key,
          cached: cachedVal, computed: computedVal,
          relativeError: relErr, pass: relErr < threshold,
        });
      }
    }
  }
}

// ─── calc command ───

function runCalc(args: string[]): void {
  const options = parseOptions(args);
  const category = args[0] as FormulaCategory | undefined;

  if (!category || !(category in FORMULA_REGISTRY)) {
    const categories = Object.keys(FORMULA_REGISTRY).join(", ");
    throw new Error(`Usage: calc <category> --input <file>\nCategories: ${categories}`);
  }

  const inputPath = requireOption(options.input, "--input");
  const absolutePath = path.resolve(process.cwd(), inputPath);
  const rawInput = JSON.parse(fs.readFileSync(absolutePath, "utf8")) as unknown;
  const inputs = Array.isArray(rawInput) ? rawInput : [rawInput];
  const compute = FORMULA_REGISTRY[category];

  const outputs = inputs.map((input, index) => {
    const result = compute(input as Record<string, unknown>);
    return { index, input, output: result };
  });

  emitJson({ category, count: outputs.length, results: outputs }, options.output);
}

// ─── query command ───

type BaselineCategory = "weapons" | "armor" | "melee" | "explosives" | "potions" | "monsters";

const BASELINE_CATEGORIES: Record<BaselineCategory, {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  compute: (row: BaselineRowRaw) => any;
  nameField: string;
  columnMap: Array<[string, string]>;
}> = {
  weapons: {
    compute: (row) => {
      const inp = row.input;
      if (inp["子弹威力"] == null) return undefined;
      return computeWeaponRow({
        level: inp["限制等级"], bulletPower: inp["子弹威力"], shootInterval: inp["射击间隔"],
        magSize: inp["弹容量"], magPrice: inp["弹夹价格"], weight: inp["重量"],
        dualWieldFactor: inp["双枪系数"], pierceFactor: inp["穿刺系数"],
        damageTypeFactor: inp["伤害类型系数"], shotgunValue: inp["霰弹值"],
        impact: inp["冲击力"], extraWeightLayers: inp["额外加权层数"],
      });
    },
    nameField: "具体武器",
    columnMap: [
      ["伤害加成", "damageBonus"], ["剧毒", "poison"], ["单段伤害", "singleShotDamage"],
      ["周期伤害", "cycleDamage"], ["平均dps", "averageDPS"], ["平衡dps", "balanceDPS"],
      ["加权dps", "weightedDPS"],
    ],
  },
  armor: {
    compute: (row) => {
      const inp = row.input;
      if (inp["防御"] == null) return undefined;
      const t = String(inp["类型"] ?? "");
      const name = String(inp["具体装备"] ?? "");
      const type = t.includes("手套") ? "glove" as const
        : (t === "项链" || name.includes("项链")) ? "necklace" as const
        : "standard" as const;
      return computeArmorRow({
        level: inp["限制等级"], defence: inp["防御"], hp: inp["HP"], mp: inp["MP"],
        damageBonus: inp["伤害加成"], weaponBonus: inp["刀/枪总加成"],
        weight: inp["重量"], punchBonus: inp["空手加成"],
        magicDefence: inp["法抗"], extraWeightLayers: inp["额外加权层数"], type,
      });
    },
    nameField: "具体装备",
    columnMap: [
      ["当前总分", "currentScore"], ["平衡总分", "balanceScore"],
      ["加权总分", "weightedScore"], ["法抗均值上限", "magicDefAvgCap"],
    ],
  },
  melee: {
    compute: (row) => {
      const inp = row.input;
      if (typeof inp["限制等级"] !== "number") return undefined;
      return computeMeleeRow({
        level: inp["限制等级"], weight: inp["重量"],
        damageTypeFactor: inp["伤害类型系数"], weightLayers: inp["加权层数"],
      });
    },
    nameField: "C",
    columnMap: [["推荐锋利度", "recommendedSharpness"]],
  },
  explosives: {
    compute: (row) => {
      const inp = row.input;
      if (typeof inp["弹夹价格"] !== "number" || row._row > 10) return undefined;
      return computeExplosivesRow({
        magPrice: inp["弹夹价格"], magSize: inp["弹容量"],
        level: inp["限制等级"], weightLayers: inp["加权层级"] ?? 0,
      });
    },
    nameField: "C",
    columnMap: [["推荐单发威力", "recommendedPower"]],
  },
  potions: {
    compute: (row) => {
      const inp = row.input;
      const cached = row.cached;
      if (typeof inp["玩家等级"] !== "number") return undefined;
      return computePotionRow({
        hp: cached["hp"] ?? 0, mp: cached["mp"] ?? 0,
        sustainFrames: cached["缓释持续帧"] ?? 0,
        playerLevel: inp["玩家等级"], isGroup: inp["是否群体"] ?? 0,
        purifyValue: inp["净化值"] ?? 0, toxicity: inp["剧毒性"] ?? 0,
        buffHp: inp["buff-hp"] ?? 0, buffMp: inp["buff-mp"] ?? 0,
        buffDefence: inp["buff-防御"] ?? 0, buffMagicResist: inp["buff-魔抗"] ?? 0,
        buffDamage: inp["buff-伤害"] ?? 0, buffPunch: inp["buff-空手"] ?? 0,
        buffSpeed: inp["buff-速度"] ?? 0, buffDuration: inp["buff-持续帧"] ?? 0,
      });
    },
    nameField: "C",
    columnMap: [
      ["恢复药强度", "recoveryStrength"], ["当前数值", "currentValue"],
      ["数值上限", "valueCap"], ["推荐价格", "recommendedPrice"],
    ],
  },
  monsters: {
    compute: (row) => {
      const inp = row.input;
      if (typeof inp["阶段"] !== "number" || typeof inp["档次系数"] !== "number") return undefined;
      return computeMonsterRow({
        stage: inp["阶段"], tierFactor: inp["档次系数"], growthFactor: inp["成长系数"],
        atkSpeedFactor: inp["攻速系数"], atkMultiplier: inp["攻击倍率"],
        segmentFactor: inp["段数系数"], speedFactor: inp["速度系数"],
        highAtkFactor: inp["高攻低血防系数"], superArmorFactor: inp["霸体系数"],
        highDefFactor: inp["高防低血系数"],
      });
    },
    nameField: "C",
    columnMap: [
      ["空手攻击MIN", "atkMin"], ["空手攻击MAX", "atkMax"],
      ["HP最小值", "hpMin"], ["HP最大值", "hpMax"],
      ["金币价格", "goldPrice"], ["K点价格", "kPointPrice"],
    ],
  },
};

function runQuery(args: string[]): void {
  const options = parseOptions(args);
  const category = args[0] as BaselineCategory | undefined;

  if (!category || !(category in BASELINE_CATEGORIES)) {
    const cats = Object.keys(BASELINE_CATEGORIES).join(", ");
    throw new Error(`Usage: query <category> --input <baseline.json> [--filter <expr>] [--sort <field>] [--limit <n>]\nCategories: ${cats}`);
  }

  const baselinePath = requireOption(options.input, "--input");
  const absolutePath = path.resolve(process.cwd(), baselinePath);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rawBaseline = JSON.parse(fs.readFileSync(absolutePath, "utf8")) as any;
  const config = BASELINE_CATEGORIES[category];
  const rows = rawBaseline[category] as BaselineRowRaw[] | undefined;
  if (!rows) {
    emitJson({ category, count: 0, items: [] }, options.output);
    return;
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let items: Array<{ row: number; name: string; computed: any }> = [];
  for (const row of rows) {
    const computed = config.compute(row);
    if (!computed) continue;
    const name = String(row.input[config.nameField] ?? `row${row._row}`);
    items.push({ row: row._row, name, computed });
  }

  // Filter: --filter "field>value" or "field<value" or "field=value"
  if (options.filter) {
    const m = options.filter.match(/^(\w+)([><=!]+)(.+)$/);
    if (m) {
      const [, field, op, rawVal] = m as unknown as [string, string, string, string];
      const val = parseFloat(rawVal);
      items = items.filter((item) => {
        const v = (item.computed as Record<string, unknown>)[field];
        if (typeof v !== "number") return false;
        switch (op) {
          case ">": return v > val;
          case ">=": return v >= val;
          case "<": return v < val;
          case "<=": return v <= val;
          case "=": case "==": return Math.abs(v - val) < 1e-10;
          case "!=": return Math.abs(v - val) >= 1e-10;
          default: return true;
        }
      });
    }
  }

  // Sort: --sort "field" or "--sort -field" (descending)
  if (options.sort) {
    const desc = options.sort.startsWith("-");
    const sortField = desc ? options.sort.slice(1) : options.sort;
    items.sort((a, b) => {
      const va = (a.computed as Record<string, unknown>)[sortField];
      const vb = (b.computed as Record<string, unknown>)[sortField];
      if (typeof va !== "number" || typeof vb !== "number") return 0;
      return desc ? vb - va : va - vb;
    });
  }

  // Limit
  if (options.limit && options.limit > 0) {
    items = items.slice(0, options.limit);
  }

  // Build summary with column map for readable output
  const output = items.map((item) => {
    const summary: Record<string, unknown> = { row: item.row, name: item.name };
    for (const [cnName, fieldKey] of config.columnMap) {
      summary[cnName] = (item.computed as Record<string, unknown>)[fieldKey];
    }
    return summary;
  });

  emitJson({ category, count: output.length, items: output }, options.output);
}

// ─── diff command ───

function runDiff(args: string[]): void {
  const options = parseOptions(args);
  const category = args[0] as BaselineCategory | undefined;

  if (!category || !(category in BASELINE_CATEGORIES)) {
    const cats = Object.keys(BASELINE_CATEGORIES).join(", ");
    throw new Error(`Usage: diff <category> --input <baseline1.json> --input2 <baseline2.json>\nCategories: ${cats}`);
  }

  const path1 = path.resolve(process.cwd(), requireOption(options.input, "--input"));
  const path2 = path.resolve(process.cwd(), requireOption(options.input2, "--input2"));
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const baseline1 = JSON.parse(fs.readFileSync(path1, "utf8")) as any;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const baseline2 = JSON.parse(fs.readFileSync(path2, "utf8")) as any;

  const config = BASELINE_CATEGORIES[category];
  const rows1 = (baseline1[category] as BaselineRowRaw[] | undefined) ?? [];
  const rows2 = (baseline2[category] as BaselineRowRaw[] | undefined) ?? [];

  // Build index by row number
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const map1 = new Map<number, any>();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const map2 = new Map<number, any>();

  for (const row of rows1) {
    const computed = config.compute(row);
    if (computed) map1.set(row._row, { name: String(row.input[config.nameField] ?? `row${row._row}`), computed });
  }
  for (const row of rows2) {
    const computed = config.compute(row);
    if (computed) map2.set(row._row, { name: String(row.input[config.nameField] ?? `row${row._row}`), computed });
  }

  const allRows = new Set([...map1.keys(), ...map2.keys()]);
  const diffs: Array<{
    row: number;
    name: string;
    changes: Array<{ field: string; before: number | null; after: number | null; delta: number | null; relChange: number | null }>;
  }> = [];

  for (const rowNum of [...allRows].sort((a, b) => a - b)) {
    const entry1 = map1.get(rowNum);
    const entry2 = map2.get(rowNum);
    if (!entry1 && !entry2) continue;

    const name = (entry2 ?? entry1).name as string;
    const changes: Array<{ field: string; before: number | null; after: number | null; delta: number | null; relChange: number | null }> = [];

    for (const [cnName, fieldKey] of config.columnMap) {
      const v1 = entry1 ? (entry1.computed as Record<string, unknown>)[fieldKey] : undefined;
      const v2 = entry2 ? (entry2.computed as Record<string, unknown>)[fieldKey] : undefined;
      const n1 = typeof v1 === "number" ? v1 : null;
      const n2 = typeof v2 === "number" ? v2 : null;
      if (n1 === null && n2 === null) continue;
      if (n1 !== null && n2 !== null && Math.abs(n1 - n2) < 1e-10) continue;

      const delta = n1 !== null && n2 !== null ? n2 - n1 : null;
      const relChange = n1 !== null && n2 !== null && Math.abs(n1) > 1e-10 ? (n2 - n1) / n1 : null;
      changes.push({ field: cnName, before: n1, after: n2, delta, relChange });
    }

    if (changes.length > 0) {
      diffs.push({ row: rowNum, name, changes });
    }
  }

  emitJson({
    category,
    input1: path1,
    input2: path2,
    changedItems: diffs.length,
    diffs,
  }, options.output);
}

// ─── validate command ───

interface ValidationIssue {
  row: number;
  name: string;
  field: string;
  value: number;
  threshold: number;
  severity: "warning" | "error";
  message: string;
}

function runValidate(args: string[]): void {
  const options = parseOptions(args);
  const baselinePath = requireOption(options.input, "--input");
  const absolutePath = path.resolve(process.cwd(), baselinePath);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rawBaseline = JSON.parse(fs.readFileSync(absolutePath, "utf8")) as any;

  const issues: ValidationIssue[] = [];

  // Validate armor: currentScore should not exceed weightedScore by more than 20%
  validateArmorBalance(rawBaseline, issues);

  // Validate weapons: check for extreme DPS outliers
  validateWeaponBalance(rawBaseline, issues);

  // Validate potions: currentValue should not exceed valueCap
  validatePotionBalance(rawBaseline, issues);

  const errors = issues.filter(i => i.severity === "error").length;
  const warnings = issues.filter(i => i.severity === "warning").length;

  emitJson({
    summary: { total: issues.length, errors, warnings },
    issues,
  }, options.output);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function validateArmorBalance(baseline: any, issues: ValidationIssue[]): void {
  const rows = baseline.armor as BaselineRowRaw[] | undefined;
  if (!rows) return;
  const config = BASELINE_CATEGORIES.armor;

  for (const row of rows) {
    const computed = config.compute(row);
    if (!computed) continue;
    const name = String(row.input[config.nameField] ?? `row${row._row}`);
    const current = computed.currentScore as number;
    const weighted = computed.weightedScore as number;

    if (weighted > 0 && current > weighted * 1.2) {
      issues.push({
        row: row._row, name, field: "currentScore",
        value: current, threshold: weighted * 1.2,
        severity: "warning",
        message: `当前总分(${current.toFixed(1)})超出加权总分(${weighted.toFixed(1)})的120%`,
      });
    }
    if (weighted > 0 && current > weighted * 1.5) {
      issues.push({
        row: row._row, name, field: "currentScore",
        value: current, threshold: weighted * 1.5,
        severity: "error",
        message: `当前总分(${current.toFixed(1)})严重超出加权总分(${weighted.toFixed(1)})的150%`,
      });
    }
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function validateWeaponBalance(baseline: any, issues: ValidationIssue[]): void {
  const rows = baseline.weapons as BaselineRowRaw[] | undefined;
  if (!rows) return;
  const config = BASELINE_CATEGORIES.weapons;

  for (const row of rows) {
    const computed = config.compute(row);
    if (!computed) continue;
    const name = String(row.input[config.nameField] ?? `row${row._row}`);
    const avg = computed.averageDPS as number;
    const balance = computed.balanceDPS as number;

    if (balance > 0 && avg > balance * 1.3) {
      issues.push({
        row: row._row, name, field: "averageDPS",
        value: avg, threshold: balance * 1.3,
        severity: "warning",
        message: `平均DPS(${avg.toFixed(1)})超出平衡DPS(${balance.toFixed(1)})的130%`,
      });
    }
    if (balance > 0 && avg < balance * 0.5) {
      issues.push({
        row: row._row, name, field: "averageDPS",
        value: avg, threshold: balance * 0.5,
        severity: "warning",
        message: `平均DPS(${avg.toFixed(1)})低于平衡DPS(${balance.toFixed(1)})的50%`,
      });
    }
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function validatePotionBalance(baseline: any, issues: ValidationIssue[]): void {
  const rows = baseline.potions as BaselineRowRaw[] | undefined;
  if (!rows) return;
  const config = BASELINE_CATEGORIES.potions;

  for (const row of rows) {
    const computed = config.compute(row);
    if (!computed) continue;
    const name = String(row.input[config.nameField] ?? `row${row._row}`);
    const current = computed.currentValue as number;
    const cap = computed.valueCap as number;

    if (cap > 0 && current > cap * 1.1) {
      issues.push({
        row: row._row, name, field: "currentValue",
        value: current, threshold: cap * 1.1,
        severity: "warning",
        message: `当前数值(${current.toFixed(1)})超出数值上限(${cap.toFixed(1)})的110%`,
      });
    }
  }
}

function printHelp(): void {
  process.stdout.write(
    [
      "CF7 Balance Tool CLI",
      "",
      "Commands:",
      "  project scan [--project <file>] [--output <file>]",
      "  project fields [--project <file>] [--output <file>]",
      "  project roundtrip-check [--project <file>] [--output <file>]",
      "  project batch-preview --input <file> [--project <file>] [--output <file>] [--output-dir <dir>] [--in-place]",
      "  project batch-set --input <file> [--project <file>] [--output <file>] (--output-dir <dir> | --in-place)",
      "  xml get --file <file> --path <xmlPath> [--attr <name>] [--output <file>]",
      "  xml set --file <file> --path <xmlPath> --value <value> [--attr <name>] [--output <file>] [--in-place]",
      "  calibrate --input <baseline.json> [--output <file>]",
      "  calc <category> --input <file> [--output <file>]",
      "  query <category> --input <baseline.json> [--filter <expr>] [--sort <field>] [--limit <n>] [--output <file>]",
      "  diff <category> --input <baseline1.json> --input2 <baseline2.json> [--output <file>]",
      "  validate --input <baseline.json> [--output <file>]",
      "",
      "Formula categories (calc): weapons, armor, melee, explosives, potions, monsters,",
      "  physicalDamage, magicDamage, weaponPrice, armorPrice, synthesis, dungeonRewards",
      "",
      "Baseline categories (query/diff): weapons, armor, melee, explosives, potions, monsters",
      "",
      "Filter examples: --filter 'averageDPS>2000' --sort '-averageDPS' --limit 10",
    ].join("\n")
  );
}

main();