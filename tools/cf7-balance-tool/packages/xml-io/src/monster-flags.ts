/**
 * 怪物标识普查 — 清点 data/enemy_properties 里每个敌人模板的标识完备度，
 * 并按面板拟合出工具该补的标识，产出可复核的候选。
 *
 * 反推的可辨识性与分工见 core/formulas/monster-solve.ts：档次系数、成长系数、高攻低血防系数、高防低血系数
 * 四个量由面板联立拟合，其余系数只认观测。人工权威按 `data/monster-flag-ledger.json` 判 —— HEAD 已提交的标识里
 * 台账登记过同值的格是工具上一批自己写的，本次可以重算；其余永不覆盖，所以 `humanFlags` 由调用方判好读进来；
 * 制作组点名的档次判定写在 data/monster-census.json 的 `humanTierFactors`。
 */
import fs from "node:fs";
import path from "node:path";

import { MONSTER_FIT_PANEL_FIELDS, MONSTER_OBSERVED_COEFFICIENTS, fitMonsterCoefficients, snapMonsterCoefficient, speedFactorFromMoveSpeed } from "@cf7-balance-tool/core";
import type { MonsterCoefficientName, MonsterFitResult, MonsterInput, MonsterPanel } from "@cf7-balance-tool/core";

import { loadXmlDocument, parseXmlDocument } from "./document.js";
import type { XmlDocument, XmlDocumentNode } from "./document.js";
import { buildStageIndex, resolveFirstAppearance } from "./monster-stage.js";
import type { MonsterCensusConfig, StageIndex, StageResolution } from "./monster-stage.js";

/** 标识子节点名 → 正算输入的系数名，与 Excel《怪物大致面板》C~L 列一致。 */
export const MONSTER_FLAG_TO_COEFFICIENT: Record<string, MonsterCoefficientName> = {
  阶段: "stage",
  档次系数: "tierFactor",
  成长系数: "growthFactor",
  攻速系数: "atkSpeedFactor",
  攻击倍率: "atkMultiplier",
  段数系数: "segmentFactor",
  速度系数: "speedFactor",
  高攻低血防系数: "highAtkFactor",
  霸体系数: "superArmorFactor",
  高防低血系数: "highDefFactor",
};

/** 反查用：系数名 → 标识子节点名。 */
export const MONSTER_COEFFICIENT_TO_FLAG: Record<MonsterCoefficientName, string> = Object.fromEntries(
  Object.entries(MONSTER_FLAG_TO_COEFFICIENT).map(([field, name]) => [name, field]),
) as Record<MonsterCoefficientName, string>;

export type MonsterFlagStatus = "complete" | "partial" | "missing";

export interface MonsterFlagRow {
  spritename: string;
  sourceFile: string;
  displayName?: string;
  status: MonsterFlagStatus;
  flags: Record<string, number>;
  missingFlags: string[];
  panel: MonsterPanel;
  missingPanelFields: string[];
  moveSpeed?: { min: number; max: number };
  tenacity?: number;
  /** 阶段来源：已有标识 > 首次出场关卡反查 > 无。 */
  stageSource: "flag" | "first-appearance" | "none";
  stageNumber?: number;
  stageStatus?: StageResolution["status"];
  stageBasis?: string;
  spawnStages?: string[];
  /** 人工权威标识：HEAD 已提交标识摘掉台账登记的自写格、并上人工认领格，再加配置点名的档次判定。工具不覆盖这些字段。 */
  humanFlags?: Record<string, number>;
  /** 配置 `noFlagTemplates` 认定这一行无需标识：不反查阶段、不拟合、不写盘。 */
  waived?: boolean;
  /**
   * 行内 `<阶段>` 写成 0 = 制作组把这行整只排除出面板体系（待重做/临时下线的怪）。
   * 与 `waived` 的分工：waived 是"这单位根本不挂面板"，阶段 0 是"观测值可以留档，但反推、统计、查验表都不算它"。
   * 所以阶段 0 的行还留着攻速/攻击倍率/段数/霸体 的实测值，只是不再产候选、不再进表。
   */
  excluded?: boolean;
  fit?: MonsterFitResult;
  skipReason?: string;
}

export interface MonsterFlagCensus {
  configVersion: number;
  sourceFiles: string[];
  excludedSourceFiles: string[];
  /** 在纳入统计的关卡里没有出场记录的模板（含被排除规则挡掉的魔神图等），供人工确认排除是否过头。 */
  unreferencedSprites: string[];
  totals: {
    templates: number;
    complete: number;
    partial: number;
    missing: number;
    stageResolved: number;
    fitted: number;
    waived: number;
    /** 阶段 0 排除的行数：观测值留档，但不参与反推、不进查验表。 */
    excluded: number;
    skipped: number;
  };
  rows: MonsterFlagRow[];
}

export interface MonsterCensusOptions {
  /** 只为这些模板跑拟合，用于小批量复核。 */
  only?: string[];
  /** 只清点缺项与面板，不跑反推。 */
  skipFit?: boolean;
  /** 人工权威标识：spritename → 标识字段 → 数值。由调用方按标识来源台账判好读进来，工具侧不解释来源。 */
  humanFlags?: Record<string, Record<string, number>>;
  /**
   * 让 档次系数 也进本次搜索：只放开配置 `humanTierFactors` 里制作组点名的那批档次，
   * 人工权威（HEAD 那份过台账过滤后的标识）仍钉住、不参与拟合也不覆盖。
   */
  freeTier?: boolean;
}

export interface MonsterFlagUpdate {
  sourceFile: string;
  spritename: string;
  flags: Record<string, number>;
}

const DEFAULT_INDENT = "    ";

/** XmlDocument.root 是 #document 容器，模板/登记项挂在它的第一个子元素上。 */
function rootElement(document: XmlDocument): XmlDocumentNode {
  return document.root.children[0] ?? document.root;
}

export function loadMonsterCensusConfig(configPath: string): MonsterCensusConfig {
  const raw = JSON.parse(fs.readFileSync(configPath, "utf8")) as MonsterCensusConfig;
  if (!Array.isArray(raw.flagFields) || raw.panelFields === undefined) {
    throw new Error(`怪物普查配置缺少 flagFields/panelFields：${configPath}`);
  }
  return raw;
}

export function censusMonsterFlags(
  repoRoot: string,
  config: MonsterCensusConfig,
  options: MonsterCensusOptions = {},
): MonsterFlagCensus {
  const stageIndex = buildStageIndex(repoRoot, config);
  const propertiesRoot = path.join(repoRoot, "data", "enemy_properties");
  const registry = readAllRegistry(path.join(propertiesRoot, "list.xml"));
  const sourceFiles = registry.filter((file) => !config.excludedSourceFiles.includes(file));

  const rows: MonsterFlagRow[] = [];
  for (const file of sourceFiles) {
    const document = loadXmlDocument(path.join(propertiesRoot, file));
    for (const node of rootElement(document).children) {
      if (!node.name.startsWith(config.templatePrefix)) continue;
      rows.push(buildRow(document, node, file, config, stageIndex, options));
    }
  }
  rows.sort((left, right) => left.sourceFile.localeCompare(right.sourceFile) || left.spritename.localeCompare(right.spritename));

  const referenced = new Set(stageIndex.spawnStagesBySprite.keys());
  return {
    configVersion: config.version,
    sourceFiles,
    excludedSourceFiles: registry.filter((file) => config.excludedSourceFiles.includes(file)),
    unreferencedSprites: rows.filter((row) => !referenced.has(row.spritename)).map((row) => row.spritename),
    totals: {
      templates: rows.length,
      complete: rows.filter((row) => row.status === "complete").length,
      partial: rows.filter((row) => row.status === "partial").length,
      missing: rows.filter((row) => row.status === "missing").length,
      stageResolved: rows.filter((row) => row.stageNumber !== undefined).length,
      fitted: rows.filter((row) => row.fit !== undefined).length,
      waived: rows.filter((row) => row.waived === true).length,
      excluded: rows.filter((row) => row.excluded === true).length,
      skipped: rows.filter((row) => row.skipReason !== undefined).length,
    },
    rows,
  };
}

function buildRow(
  document: XmlDocument,
  node: XmlDocumentNode,
  file: string,
  config: MonsterCensusConfig,
  stageIndex: StageIndex,
  options: MonsterCensusOptions,
): MonsterFlagRow {
  const flags = readFlags(document, node, config);
  const missingFlags = config.flagFields.filter((field) => flags[field] === undefined);
  const status: MonsterFlagStatus =
    missingFlags.length === 0 ? "complete" : missingFlags.length === config.flagFields.length ? "missing" : "partial";

  const panel: MonsterPanel = {};
  const missingPanelFields: string[] = [];
  for (const [xmlField, coefficient] of Object.entries(config.panelFields)) {
    const value = toNumber(document.childText(node, xmlField));
    if (value === undefined) missingPanelFields.push(xmlField);
    else assignPanel(panel, coefficient as keyof MonsterPanel, value);
  }

  const speedMin = toNumber(document.childText(node, config.moveSpeedFields.min));
  const speedMax = toNumber(document.childText(node, config.moveSpeedFields.max));
  const displayName = document.childText(node, config.displayNameField);
  const tenacity = toNumber(document.childText(node, config.tenacityField));

  const appearance = resolveFirstAppearance(node.name, stageIndex);
  const resolution = appearance.resolution;
  const flaggedStage = flags["阶段"];
  // 人工判定「无需标识」的模板（分身、投影、召唤物）不参与关卡反查，否则下次普查又会自己长出阶段来
  const waived = config.noFlagTemplates?.includes(node.name) === true;
  // 阶段 0 是制作组写在行内的排除标记（不是"阶段还没定"）：这一行的观测系数照留档，但反推、写回、查验表都不算它。
  const excluded = !waived && flaggedStage === 0;
  const stageNumber = flaggedStage ?? (waived ? undefined : resolution?.stageNumber);

  const human = humanFlagsOf(node.name, config, options);

  const row: MonsterFlagRow = {
    spritename: node.name,
    sourceFile: file,
    status,
    flags,
    missingFlags,
    panel,
    missingPanelFields,
    stageSource: flaggedStage !== undefined ? "flag" : stageNumber === undefined ? "none" : "first-appearance",
    ...(displayName === undefined ? {} : { displayName }),
    ...(speedMin === undefined || speedMax === undefined ? {} : { moveSpeed: { min: speedMin, max: speedMax } }),
    ...(tenacity === undefined ? {} : { tenacity }),
    ...(stageNumber === undefined ? {} : { stageNumber }),
    ...(resolution === undefined ? {} : { stageStatus: resolution.status, stageBasis: resolution.basis }),
    ...(appearance.candidates.length === 0 ? {} : { spawnStages: appearance.candidates }),
    ...(Object.keys(human).length === 0 ? {} : { humanFlags: human }),
    ...(waived ? { waived: true } : {}),
    ...(excluded ? { excluded: true } : {}),
  };

  if (waived) return row;
  // 阶段 0 的行不拟合：面板是待重做的旧数，拿它反推只会把档次解拽到端点上去凑。
  if (excluded) return row;
  if (options.skipFit === true) return row;
  if (options.only !== undefined && !options.only.includes(row.spritename)) return row;

  const fitted = fitRow(row);
  if (fitted.result) row.fit = fitted.result;
  else if (fitted.skipReason !== undefined) row.skipReason = fitted.skipReason;
  return row;
}

/**
 * 人工权威标识 = HEAD 已提交的 `<标识>` 过标识来源台账（摘掉工具自写格、并上人工认领格）∪ 配置里点名的档次判定。
 * 档次判定写在 `humanTierFactors` 而不是行内标识，是因为它来自制作组的口头分档、不来自面板；
 * 写进行又会让普查把它当已有标识，读不出"这条是人工钉的"。
 * `freeTier` 只摘掉后一半：点名的档次回到搜索空间，人工权威的其余格照旧不动。
 * 配置 `estimatedTierTemplates` 点名的行例外：HEAD 里那颗档次按制作组口径只是预估，摘掉让本次重算，
 * 同一行其余已提交字段（阶段等）照旧钉住。
 */
function humanFlagsOf(
  spritename: string,
  config: MonsterCensusConfig,
  options: MonsterCensusOptions,
): Record<string, number> {
  const committed = { ...(options.humanFlags?.[spritename] ?? {}) };
  if (config.estimatedTierTemplates?.includes(spritename)) delete committed["档次系数"];
  const tier = options.freeTier === true ? undefined : config.humanTierFactors?.[spritename];
  return tier === undefined ? committed : { ...committed, 档次系数: tier };
}

/**
 * 进拟合的钉住集合（`known`）：
 * - 观测系数（速度系数/攻速系数/攻击倍率/段数系数/霸体系数）只要盘上有值就钉住，来源是实测或移动速度定义档，
 *   面板不能替动画做判断；盘上没有 速度系数 时由 fitMonsterCoefficients 走移动速度定义档通道。
 * - 档次系数/成长系数/高攻低血防系数/高防低血系数 只有人工给过才钉住：工具上一批自写的值要让本次重算，
 *   否则旧输出会把自己冻成输入。
 */
export function fitPinnedCoefficients(row: MonsterFlagRow): Partial<MonsterInput> {
  const known: Partial<MonsterInput> = {};
  for (const name of [...MONSTER_OBSERVED_COEFFICIENTS, "speedFactor"] as MonsterCoefficientName[]) {
    const value = row.flags[MONSTER_COEFFICIENT_TO_FLAG[name]];
    if (value !== undefined) Object.assign(known, { [name]: value });
  }
  for (const [field, value] of Object.entries(row.humanFlags ?? {})) {
    const name = MONSTER_FLAG_TO_COEFFICIENT[field];
    if (name === undefined || name === "stage") continue;
    Object.assign(known, { [name]: value });
  }
  return known;
}

function fitRow(row: MonsterFlagRow): { result?: MonsterFitResult; skipReason?: string } {
  const stage = row.stageNumber;
  if (stage === undefined) return { skipReason: "阶段既无标识也无法由首次出场关卡推出" };
  const hasFitField = MONSTER_FIT_PANEL_FIELDS.some((field) => row.panel[field] !== undefined);
  if (!hasFitField) return { skipReason: "空手/HP/防御 六项面板一项都读不到，没有可拟合的方程" };

  return {
    result: fitMonsterCoefficients({
      stage,
      panel: row.panel,
      known: fitPinnedCoefficients(row),
      ...(row.moveSpeed === undefined ? {} : { moveSpeed: row.moveSpeed }),
    }),
  };
}

/** 面板字段按联合键写入，收敛到一次 Object.assign 以满足 exactOptionalPropertyTypes。 */
function assignPanel(panel: MonsterPanel, key: keyof MonsterPanel, value: number): void {
  Object.assign(panel, { [key]: value });
}

function readFlags(document: XmlDocument, node: XmlDocumentNode, config: MonsterCensusConfig): Record<string, number> {
  const flags: Record<string, number> = {};
  const block = document.childrenNamed(node, config.flagElement)[0];
  if (!block) return flags;
  for (const child of block.children) {
    const value = toNumber(document.leafText(child));
    if (value !== undefined) flags[child.name] = value;
  }
  return flags;
}

function readAllRegistry(listPath: string): string[] {
  if (!fs.existsSync(listPath)) return [];
  const document = loadXmlDocument(listPath);
  return rootElement(document).children
    .map((node) => document.leafText(node))
    .filter((value): value is string => value !== undefined);
}

/**
 * 不需要人工输入就能定的标识：阶段来自首次出场规则，速度系数来自 Excel D15 的移动速度档次。
 * 这两个都只在盘上缺值时补，已有值不动 —— 补出来的来源仍是这两条定义通道，重算不会改它。
 */
export function mechanicalFlags(row: MonsterFlagRow): Record<string, number> {
  const flags: Record<string, number> = {};
  if (row.flags["阶段"] === undefined && row.stageNumber !== undefined) Object.assign(flags, { 阶段: row.stageNumber });
  if (row.flags["速度系数"] === undefined && row.moveSpeed) {
    Object.assign(flags, { 速度系数: speedFactorFromMoveSpeed(row.moveSpeed.min, row.moveSpeed.max).value });
  }
  return flags;
}

/**
 * 工具这一批该写的标识 = 机械可定项 ＋ 本次拟合的自由量（归到整数/半档/十分档的取值词表）。
 * 人工权威（过台账的已提交标识、配置点名的档次）给过的字段一律不写；
 * 读不到面板方程的行只写机械项，免得把默认值当反推结论写进数据。
 */
export function toolFlagProposal(row: MonsterFlagRow): Record<string, number> {
  if (row.waived === true) return {};
  // 阶段 0：机械项（阶段、速度系数）与反推四项都不写，这行的标识只认实测的那四项。
  if (row.excluded === true) return {};
  const flags = mechanicalFlags(row);
  const fit = row.fit;
  if (fit === undefined || fit.equations === 0) return flags;
  const human = row.humanFlags ?? {};
  for (const name of fit.freeCoefficients) {
    const field = MONSTER_COEFFICIENT_TO_FLAG[name];
    if (human[field] !== undefined) continue;
    Object.assign(flags, { [field]: snapMonsterCoefficient(fit.coefficients[name]).value });
  }
  return flags;
}

/**
 * 人工完整打标：人工权威（HEAD 过台账后的标识并上人工认领格）把除 速度系数 以外的系数都给了值。
 * 速度系数 来自移动速度的定义档、不算人工输入，所以是唯一豁免项。
 * 这类行的标识不是本次统计得出的，不跟工具识别的行混在同一张查验表里；
 * 制作组 2026-10-07 口径：三张表只统计工具自己识别的，人工已打标的另出一张对照表。
 */
export function isFullyHumanFlagged(row: MonsterFlagRow, config: MonsterCensusConfig): boolean {
  const human = row.humanFlags;
  if (human === undefined) return false;
  return config.flagFields.every((field) => field === "速度系数" || human[field] !== undefined);
}

/**
 * 从一份 `<标识>` 的原文（git HEAD 里的那份敌人属性 XML）读出 模板名 → 标识字段 → 数值。
 * 只看已提交版本，不看工作树 —— 工作树里全是这一批刚改的值；但已提交版本里也躺着工具自写的格，
 * 所以这份原文还要过 `monster-flag-ledger.ts` 的台账才算人工权威。
 */
export function readFlagsFromSource(source: string, config: MonsterCensusConfig): Record<string, Record<string, number>> {
  const document = parseXmlDocument(source);
  const out: Record<string, Record<string, number>> = {};
  for (const node of rootElement(document).children) {
    if (!node.name.startsWith(config.templatePrefix)) continue;
    const flags = readFlags(document, node, config);
    if (Object.keys(flags).length > 0) out[node.name] = flags;
  }
  return out;
}

/** 阶段数字 → 主线进度描述（配置 `stageLabels`，对应 Excel B19~C32 的阶次表）。 */
export function stageProgressLabel(config: MonsterCensusConfig, stage: number | undefined): string {
  if (stage === undefined) return "";
  const hits = labelsOf(config.stageLabels ?? [], stage);
  return hits.length === 0 ? `阶段 ${stage} 未列主线进度` : hits.join("／");
}

/**
 * 档次系数 → 中文档次描述（配置 `tierLabels`）。
 * 门槛只取各档的**下限**（制作组 2026-10-06 口径）：8~9 这种浮动档一律从 8 起算，
 * 于是 9 只归 低级boss，不再和 高级精英 并列报同一段。
 * 落点按「离哪一档的门槛更近」判：
 * - 正好踩在某档门槛上 → 直接写该档名；
 * - 达到了本档门槛、但离本档门槛更近 → 写「本档+」；
 * - 达到了本档门槛、但离上一档门槛更近 → 写「上一档−」；
 * - 不偏不倚正好压在两级正中 → 按四舍五入归到上一档，写「上一档−」；
 * - 连最低档门槛都没到 → 「最低档−」；已在最高档门槛之上 → 「最高档+」（档次搜索已放开到参考区间之外，这里照实描述）。
 */
export function tierLabel(config: MonsterCensusConfig, tier: number | undefined): string {
  if (tier === undefined) return "";
  const bands = tierThresholds(config.tierLabels ?? []);
  if (bands.length === 0) return `档次 ${tier} 未列描述`;

  const reached = bands.filter((band) => band.threshold <= tier + 1e-9).at(-1);
  if (reached === undefined) return `${bands[0]!.label}-`;
  if (isAtThreshold(tier, reached.threshold)) return reached.label;

  const next = bands.find((band) => band.threshold > tier + 1e-9);
  if (next === undefined) return `${reached.label}+`;
  const midpoint = (reached.threshold + next.threshold) / 2;
  return tier < midpoint ? `${reached.label}+` : `${next.label}-`;
}

/** 同一门槛上的多个档名并成一个档（配置真重叠时不至于报出两个门槛）。 */
function tierThresholds(bands: Array<{ from: number; to: number; label: string }>): Array<{ threshold: number; label: string }> {
  const byThreshold = new Map<number, string[]>();
  for (const band of [...bands].sort((left, right) => left.from - right.from)) {
    const labels = byThreshold.get(band.from) ?? [];
    if (!labels.includes(band.label)) labels.push(band.label);
    byThreshold.set(band.from, labels);
  }
  return [...byThreshold].map(([threshold, labels]) => ({ threshold, label: labels.join("／") }));
}

function isAtThreshold(tier: number, threshold: number): boolean {
  return Math.abs(tier - threshold) <= 1e-9;
}

function labelsOf(bands: Array<{ from: number; to: number; label: string }>, value: number): string[] {
  return bands.filter((band) => value >= band.from && value <= band.to).map((band) => band.label);
}

/**
 * 把候选标识写回 data/enemy_properties 的模板里。
 * 只改写目标节点内部文本或在其闭合标签前插入新节点，注释与其余排版保持原样。
 */
export function applyMonsterFlagUpdates(repoRoot: string, updates: MonsterFlagUpdate[], config: MonsterCensusConfig): string[] {
  const propertiesRoot = path.join(repoRoot, "data", "enemy_properties");
  const byFile = new Map<string, MonsterFlagUpdate[]>();
  for (const update of updates) {
    const list = byFile.get(update.sourceFile) ?? [];
    list.push(update);
    byFile.set(update.sourceFile, list);
  }

  const written: string[] = [];
  for (const [file, fileUpdates] of byFile) {
    const filePath = path.join(propertiesRoot, file);
    const document = loadXmlDocument(filePath);
    let changed = false;

    for (const update of fileUpdates) {
      const template = rootElement(document).children.find((node) => node.name === update.spritename);
      if (!template) throw new Error(`找不到敌人模板：${file} / ${update.spritename}`);
      changed = writeFlags(document, template, update.flags, config) || changed;
    }

    if (changed) {
      document.save(filePath);
      written.push(filePath);
    }
  }
  return written;
}

function writeFlags(
  document: XmlDocument,
  template: XmlDocumentNode,
  flags: Record<string, number>,
  config: MonsterCensusConfig,
): boolean {
  const templateIndent = indentOf(document, template);
  const block = document.childrenNamed(template, config.flagElement)[0];

  if (!block) {
    if (template.selfClosing) throw new Error(`模板 ${template.name} 是自关闭节点，无法插入 <${config.flagElement}>`);
    // 现网文件里模板子节点的缩进不统一，新块跟最后一个子节点同一层，空模板才退回模板缩进 + 一级。
    const blockIndent = lastChildIndent(document, template) ?? `${templateIndent}${DEFAULT_INDENT}`;
    const entryIndent = `${blockIndent}${DEFAULT_INDENT}`;
    const lines = Object.entries(flags).map(([field, value]) => `${entryIndent}<${field}>${formatFlagValue(value)}</${field}>`).join("\n");
    // 插在最后一个子节点之后，原有换行与闭合标签缩进保持不动；空模板才需要补尾随换行。
    const anchor = lastChildEnd(template);
    const tail = template.children.length === 0 ? `\n${templateIndent}` : "";
    document.insertTextAt(anchor, `\n${blockIndent}<${config.flagElement}>\n${lines}\n${blockIndent}</${config.flagElement}>${tail}`);
    return true;
  }

  // 已有标识块的新字段按兄弟行缩进对齐：天网.xml 这类文件里标识块本身用制表符，子节点却用空格。
  const entryIndent = lastChildIndent(document, block) ?? `${indentOf(document, block)}${DEFAULT_INDENT}`;
  let changed = false;
  const additions: string[] = [];
  for (const child of block.children) {
    const value = flags[child.name];
    if (value === undefined) continue;
    const text = formatFlagValue(value);
    // 同值重写不动文件：全量重算会把没变的行也送进来，留下改动就分不清这批写了什么
    if (document.leafText(child) === text) continue;
    document.setLeafText(child, text);
    changed = true;
  }
  for (const [field, value] of Object.entries(flags)) {
    if (block.children.some((child) => child.name === field)) continue;
    additions.push(`${entryIndent}<${field}>${formatFlagValue(value)}</${field}>`);
  }
  if (additions.length > 0) {
    if (block.children.length === 0) {
      const blockIndent = indentOf(document, block);
      document.setLeafText(block, `\n${additions.join("\n")}\n${blockIndent}`);
    } else {
      document.insertTextAt(lastChildEnd(block), `\n${additions.join("\n")}`);
    }
    changed = true;
  }
  return changed;
}

/** 最后一个子节点所在行的缩进；没有子节点时返回 undefined，由调用方退回上一层缩进。 */
function lastChildIndent(document: XmlDocument, node: XmlDocumentNode): string | undefined {
  const last = node.children[node.children.length - 1];
  return last ? indentOf(document, last) : undefined;
}

/** 节点（含其闭合标签）在源文本里的结束偏移；自关闭节点没有 endTagEnd，用内部偏移即为标签尾。 */
function lastChildEnd(node: XmlDocumentNode): number {
  const last = node.children[node.children.length - 1];
  return last ? (last.endTagEnd ?? last.innerEnd) : node.innerEnd;
}

function indentOf(document: XmlDocument, node: XmlDocumentNode): string {
  const match = /([ \t]*)$/.exec(document.originalSource.slice(0, node.startTagStart));
  return match?.[1] ?? "";
}

/** 面板反推的小数位按工作表习惯截到两位；整数不补零。 */
function formatFlagValue(value: number): string {
  return String(Math.round(value * 100) / 100);
}

function toNumber(value: string | undefined): number | undefined {
  if (value === undefined) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}
