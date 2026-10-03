/**
 * 怪物标识普查 — 清点 data/enemy_properties 里每个敌人模板的标识完备度，
 * 并在阶段可查、档次已知时对面板做反推，产出可复核的候选标识。
 *
 * 面板到标识的可辨识性约束见 core/formulas/monster-solve.ts：档次系数与攻击节奏三系数
 * 不能由面板推出，所以普查只对「阶段可查 + 档次已知」的行给出反推候选，其余行只登记缺什么。
 */
import fs from "node:fs";
import path from "node:path";

import { scanTierFactor, solveMonsterCoefficients } from "@cf7-balance-tool/core";
import type { MonsterCoefficientName, MonsterInput, MonsterPanel, MonsterSolveResult } from "@cf7-balance-tool/core";

import { loadXmlDocument } from "./document.js";
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
  solve?: MonsterSolveResult & { tierSource: "flag" | "hint" | "fallback" };
  /**
   * 档次系数候选（--scan-tier 才计算）。只是拟合排序：面板单独定档不可靠，
   * 实测无其余标识时 top1 命中 7/29 且整体偏低，带其余标识时 24/29。人工定档后请以 solve 为准。
   */
  tierCandidates?: Array<{ tierFactor: number; fitError: number }>;
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
    solved: number;
    skipped: number;
  };
  rows: MonsterFlagRow[];
}

export interface MonsterCensusOptions {
  /** 人工给出的档次系数：spritename → 档次系数，优先于行内标识。 */
  tierHints?: Record<string, number>;
  /** 没有档次标注时统一使用的档次；不给就不产出反推候选，避免伪造结论。 */
  fallbackTier?: number;
  /** 只为这些模板生成反推候选，用于小批量复核。 */
  only?: string[];
  /** 跳过反推，只清点缺项。 */
  skipSolve?: boolean;
  /** 对未定档的行做档次扫描（较慢，且只作人工定档的排序参考）。 */
  scanTier?: boolean;
  /** 档次扫描保留前几条候选。 */
  tierCandidateCount?: number;
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
      solved: rows.filter((row) => row.solve !== undefined).length,
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
  const stageNumber = flaggedStage ?? resolution?.stageNumber;

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
  };

  if (options.skipSolve === true) return row;
  if (options.only !== undefined && !options.only.includes(row.spritename)) return row;

  const solved = solveRow(row, options);
  if (solved.result) row.solve = solved.result;
  else if (solved.skipReason !== undefined) row.skipReason = solved.skipReason;

  if (options.scanTier === true && row.solve === undefined && row.stageNumber !== undefined) {
    const ranked = scanTierFactor({
      stage: row.stageNumber,
      panel: row.panel,
      known: knownCoefficients(row),
      ...(row.moveSpeed === undefined ? {} : { moveSpeed: row.moveSpeed }),
    });
    const take = options.tierCandidateCount ?? 3;
    if (ranked.length > 0) row.tierCandidates = ranked.slice(0, take).map(({ tierFactor, fitError }) => ({ tierFactor, fitError }));
  }
  return row;
}

function knownCoefficients(row: MonsterFlagRow): Partial<MonsterInput> {
  const known: Record<string, number> = {};
  for (const [field, value] of Object.entries(row.flags)) {
    const name = MONSTER_FLAG_TO_COEFFICIENT[field];
    if (name === undefined || name === "stage" || name === "tierFactor") continue;
    Object.assign(known, { [name]: value });
  }
  return known as Partial<MonsterInput>;
}

function solveRow(
  row: MonsterFlagRow,
  options: MonsterCensusOptions,
): { result?: MonsterSolveResult & { tierSource: "flag" | "hint" | "fallback" }; skipReason?: string } {
  const stage = row.stageNumber;
  if (stage === undefined) return { skipReason: "阶段既无标识也无法由首次出场关卡推出" };

  const flaggedTier = row.flags["档次系数"];
  const hintedTier = options.tierHints?.[row.spritename];
  const tier = hintedTier ?? flaggedTier ?? options.fallbackTier;
  if (tier === undefined) return { skipReason: "档次系数待人工标注" };
  const tierSource: "flag" | "hint" | "fallback" = hintedTier !== undefined ? "hint" : flaggedTier !== undefined ? "flag" : "fallback";

  if (Object.keys(row.panel).length === 0) return { skipReason: "没有任何面板字段可读" };

  const result = solveMonsterCoefficients({
    stage,
    tierFactor: tier,
    panel: row.panel,
    known: knownCoefficients(row),
    ...(row.moveSpeed === undefined ? {} : { moveSpeed: row.moveSpeed }),
  });
  return { result: { ...result, tierSource } };
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
    document.setLeafText(child, formatFlagValue(value));
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
