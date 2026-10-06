/**
 * 怪物标识普查与反推 CLI — 长期复用的数值工具入口。
 *
 * 用法：
 *   npm run monster-census                     清点全部敌人模板并按面板反推，写 reports/monster-flag-census.json
 *     --markdown <路径>                         同时输出人工复核用表格（默认 reports/monster-flag-census.md）
 *     --only 敌人-A,敌人-B                       只反推指定模板
 *     --free-tier                                 让 档次系数 回到搜索空间（只放开 humanTierFactors 点名的行，HEAD 已提交标识仍钉住）
 *     --no-solve                                只清点缺项，不跑反推
 *   npm run monster-solve -- 敌人-体育老师 [--stage 4] [--known 档次系数=9,速度系数=2.5]
 *   npm run monster-flags-apply -- --from reports/monster-flag-census.json [--write]
 *     --only 敌人-A,敌人-B                       只写指定模板，用于小批试点
 *
 * 反推的分工见 core/formulas/monster-solve.ts：档次系数/成长系数/高攻低血防系数/高防低血系数 由面板联立拟合，
 * 攻速系数/攻击倍率/段数系数/霸体系数 只认攻击与击退元件的实测值。人工权威按 git HEAD 判 —— 已提交的 `<标识>`
 * 永不覆盖，所以 census 与 apply 都先读 HEAD 那份文件；未进 HEAD 的新文件整份按工具侧处理。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { MONSTER_COEFFICIENT_RANGES, fitMonsterCoefficients, snapMonsterCoefficient } from "@cf7-balance-tool/core";
import type { MonsterCoefficientName, MonsterInput } from "@cf7-balance-tool/core";
import {
  MONSTER_COEFFICIENT_TO_FLAG,
  MONSTER_FLAG_TO_COEFFICIENT,
  applyMonsterFlagUpdates,
  censusMonsterFlags,
  fitPinnedCoefficients,
  loadMonsterCensusConfig,
  toolFlagProposal,
} from "@cf7-balance-tool/xml-io";
import type { MonsterCensusOptions, MonsterFlagCensus, MonsterFlagRow, MonsterFlagUpdate } from "@cf7-balance-tool/xml-io";

import { headFlags } from "./monster-flag-provenance.js";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const CONFIG_PATH = path.join(TOOL_ROOT, "data", "monster-census.json");
const CENSUS_PATH = path.join(TOOL_ROOT, "reports", "monster-flag-census.json");
const CENSUS_MARKDOWN_PATH = path.join(TOOL_ROOT, "reports", "monster-flag-census.md");

const COEFFICIENT_ORDER: MonsterCoefficientName[] = [
  "stage",
  "tierFactor",
  "growthFactor",
  "atkSpeedFactor",
  "atkMultiplier",
  "segmentFactor",
  "speedFactor",
  "highAtkFactor",
  "superArmorFactor",
  "highDefFactor",
];

const ALL_FLAG_FIELDS = Object.keys(MONSTER_FLAG_TO_COEFFICIENT).length;

const PANEL_LABELS: Record<string, string> = {
  atkMin: "空手MIN",
  atkMax: "空手MAX",
  hpMin: "HPmin",
  hpMax: "HPmax",
  defMin: "防御min",
  defMax: "防御max",
  expMin: "经验min",
  expMax: "经验max",
};

function main(argv: string[]): void {
  const [command = "census", ...rest] = argv;
  const { flags, positional } = parseFlags(rest);

  switch (command) {
    case "census":
      runCensus(flags, positional);
      break;
    case "solve":
      runSolve(flags, positional);
      break;
    case "apply":
      runApply(flags, positional);
      break;
    default:
      throw new Error(`未知命令：${command}（支持 census / solve / apply）`);
  }
}

function runCensus(flags: Record<string, string | boolean>, positional: string[]): void {
  const config = loadMonsterCensusConfig(CONFIG_PATH);
  const options: MonsterCensusOptions = {
    ...(typeof flags.only === "string" ? { only: splitList(flags.only) } : positional.length > 0 ? { only: positional } : {}),
    ...(flags["no-solve"] === true ? { skipFit: true } : {}),
    ...(flags["free-tier"] === true ? { freeTier: true } : {}),
    humanFlags: headFlags(REPO_ROOT, config),
  };

  const census = censusMonsterFlags(REPO_ROOT, config, options);
  writeJson(CENSUS_PATH, census);
  console.log(
    `普查完成：${census.totals.templates} 个模板，完整 ${census.totals.complete}，残缺 ${census.totals.partial}，无标识 ${census.totals.missing}，阶段可查 ${census.totals.stageResolved}，已反推 ${census.totals.fitted}，无需标识 ${census.totals.waived}，阶段 0 排除 ${census.totals.excluded}`,
  );
  console.log(`  人工权威取自 git HEAD：${Object.keys(options.humanFlags ?? {}).length} 个模板有已提交标识`);
  const estimated = config.estimatedTierTemplates ?? [];
  if (estimated.length > 0) {
    console.log(`  HEAD 的 档次系数 按预估处理、本次重算的 ${estimated.length} 行：${estimated.join("、")}（同一行其余已提交标识照旧钉住）`);
  }
  if (options.freeTier === true) {
    console.log(`  本批放开档次系数进搜索：配置点名的 ${Object.keys(config.humanTierFactors ?? {}).length} 行档次不再钉住，HEAD 已提交的标识照旧钉住`);
  }
  console.log(`JSON → ${CENSUS_PATH}`);

  const markdownPath = typeof flags.markdown === "string" ? path.resolve(TOOL_ROOT, flags.markdown) : CENSUS_MARKDOWN_PATH;
  if (flags["no-markdown"] !== true) {
    fs.mkdirSync(path.dirname(markdownPath), { recursive: true });
    fs.writeFileSync(markdownPath, renderMarkdown(census), "utf8");
    console.log(`Markdown → ${markdownPath}`);
  }
}

function runSolve(flags: Record<string, string | boolean>, positional: string[]): void {
  const [spritename] = positional;
  if (!spritename) throw new Error("solve 需要指定 spritename");

  const config = loadMonsterCensusConfig(CONFIG_PATH);
  const census = censusMonsterFlags(REPO_ROOT, config, { skipFit: true, only: [spritename], humanFlags: headFlags(REPO_ROOT, config) });
  const row = census.rows.find((entry) => entry.spritename === spritename);
  if (!row) throw new Error(`普查里找不到 ${spritename}`);

  const stage = flags.stage === undefined ? row.stageNumber : Number(flags.stage);
  if (stage === undefined || !Number.isFinite(stage)) throw new Error(`${spritename} 没有阶段，请用 --stage 指定`);

  const known: Partial<MonsterInput> = { ...fitPinnedCoefficients(row), ...parseKnown(flags.known) };
  const result = fitMonsterCoefficients({
    stage,
    panel: row.panel,
    known,
    ...(row.moveSpeed === undefined ? {} : { moveSpeed: row.moveSpeed }),
  });

  console.log(`${spritename}（阶段 ${stage}）四元联立反推`);
  console.log(`  面板参与：${result.equations} 项／自由量：${result.freeCoefficients.map((name) => MONSTER_COEFFICIENT_TO_FLAG[name]).join("、") || "无"}`);
  console.log(`  拟合误差（空手/HP/防御，经验不计入）：${Math.round(result.fitError * 1000) / 10}%`);
  for (const name of COEFFICIENT_ORDER) {
    const estimate = result.estimates.find((entry) => entry.name === name);
    const flag = MONSTER_COEFFICIENT_TO_FLAG[name];
    const snapped = snapMonsterCoefficient(result.coefficients[name]).value;
    const range = MONSTER_COEFFICIENT_RANGES[name];
    const outside = result.coefficients[name] < range[0] || result.coefficients[name] > range[1] ? `｜超参考区间 ${range[0]}~${range[1]}` : "";
    console.log(`  ${flag}：${result.coefficients[name]}${snapped !== result.coefficients[name] ? `（写盘取 ${snapped}）` : ""}${estimate ? `｜${CONFIDENCE_LABEL[estimate.confidence] ?? estimate.confidence}` : "｜未定"}${outside}`);
  }
  console.log(`  未定（缺观测或面板定不了）：${result.unresolved.map((name) => MONSTER_COEFFICIENT_TO_FLAG[name]).join("、") || "无"}`);
  for (const residual of result.residuals) {
    console.log(`  ${PANEL_LABELS[residual.field] ?? residual.field}：面板 ${residual.observed} / 复算 ${round(residual.computed, 1)}（差 ${Math.round(residual.relativeError * 1000) / 10}%）`);
  }
  for (const residual of result.expResiduals) {
    console.log(`  ${PANEL_LABELS[residual.field] ?? residual.field}（只对照，不参与拟合）：面板 ${residual.observed} / 复算 ${round(residual.computed, 1)}（差 ${Math.round(residual.relativeError * 1000) / 10}%）`);
  }
  result.notes.forEach((note) => console.log(`  提示：${note}`));
}

const CONFIDENCE_LABEL: Record<string, string> = {
  given: "人工或观测钉住",
  "definition-band": "移动速度定义档",
  "panel-fit": "面板反推",
};

function runApply(flags: Record<string, string | boolean>, positional: string[]): void {
  const source = typeof flags.from === "string" ? flags.from : positional[0];
  if (!source) throw new Error("apply 需要给出普查 JSON 路径（--from <路径>）");
  let updates = readUpdates(path.resolve(TOOL_ROOT, source));
  if (typeof flags.only === "string") {
    const only = new Set(splitList(flags.only));
    updates = updates.filter((update) => only.has(update.spritename));
  }
  const config = loadMonsterCensusConfig(CONFIG_PATH);

  if (flags.write !== true) {
    console.log(`候选 ${updates.length} 条，未写入（加 --write 才落盘）：`);
    for (const update of updates) {
      console.log(`  ${update.sourceFile} / ${update.spritename}: ${Object.entries(update.flags).map(([key, value]) => `${key}=${value}`).join(" ")}`);
    }
    return;
  }
  const written = applyMonsterFlagUpdates(REPO_ROOT, updates, config);
  console.log(`已写入 ${written.length} 个文件：\n${written.map((file) => `  ${path.relative(REPO_ROOT, file)}`).join("\n")}`);
}

function writeJson(target: string, value: unknown): void {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function splitList(value: string): string[] {
  return value.split(",").map((entry) => entry.trim()).filter(Boolean);
}

/** 候选文件既接受普查 JSON，也接受人工整理的 spritename → 标识 映射。 */
function readUpdates(filePath: string): MonsterFlagUpdate[] {
  const raw = JSON.parse(fs.readFileSync(filePath, "utf8")) as unknown;
  if (Array.isArray(raw)) return raw as MonsterFlagUpdate[];
  if (isRecord(raw) && Array.isArray(raw.rows)) {
    return (raw.rows as MonsterFlagRow[])
      .map((row) => ({ sourceFile: row.sourceFile, spritename: row.spritename, flags: toolFlagProposal(row) }))
      .filter((update) => Object.keys(update.flags).length > 0);
  }
  throw new Error(`候选文件格式不认识：${filePath}`);
}

/** 展示反推候选：归档后的取值后面括号给出连续解，便于人工判断半档是不是真有必要。 */
function proposalCells(row: MonsterFlagRow): string[] {
  const fit = row.fit;
  if (fit === undefined) return [];
  const cells: string[] = [];
  for (const [field, value] of Object.entries(toolFlagProposal(row))) {
    if (fit.freeCoefficients.length === 0 && field !== "阶段" && field !== "速度系数") continue;
    const name = MONSTER_FLAG_TO_COEFFICIENT[field];
    const continuous = name === undefined ? value : fit.coefficients[name];
    if (Math.abs(continuous - value) <= 1e-9) {
      cells.push(`${field} ${value}`);
      continue;
    }
    cells.push(`${field} ${value}（连续 ${continuous.toFixed(3)}）`);
  }
  return cells;
}

function notesCell(row: MonsterFlagRow): string {
  if (row.waived === true) return "配置认定无需标识";
  if (row.skipReason !== undefined) return row.skipReason;
  return row.fit?.notes[0] ?? "";
}

function renderMarkdown(census: MonsterFlagCensus): string {
  const lines: string[] = [];
  const autoStage = census.rows.filter((row) => row.stageSource === "first-appearance").length;
  const autoSpeed = census.rows.filter((row) => row.flags["速度系数"] === undefined && row.moveSpeed !== undefined).length;

  lines.push(`# 怪物标识普查（配置 v${census.configVersion}）`);
  lines.push("");
  lines.push(`- 纳入模板：${census.totals.templates}（来源 ${census.sourceFiles.length} 个文件，排除 ${census.excludedSourceFiles.join("、")}）`);
  lines.push(`- 标识完整 ${census.totals.complete}／残缺 ${census.totals.partial}／全无 ${census.totals.missing}`);
  lines.push(`- 阶段可查 ${census.totals.stageResolved}，已产出反推候选 ${census.totals.fitted}，跳过 ${census.totals.skipped}，无需标识 ${census.totals.waived}，阶段 0 排除 ${census.totals.excluded}`);
  lines.push(`- 阶段 0 的 ${census.totals.excluded} 行是制作组写在行内的排除标记：标识里只留实测的攻速/攻击倍率/段数系数/霸体系数，不反推、不写回、不进查验表。`);
  lines.push(`- 无需人工输入即可补：阶段 ${autoStage} 个（首次出场规则）、速度系数 ${autoSpeed} 个（Excel D15 移动速度档次）`);
  lines.push("- 反推的自由量：档次系数、成长系数、高攻低血防系数、高防低血系数；攻速系数/攻击倍率/段数系数/霸体系数 只认实测值。");
  lines.push("- 逐行查验与改数都在 `data/monster-flag-table.csv`（`npm run monster-flags-csv` 出，`npm run monster-flags-table-apply` 回写）。");
  lines.push(`- 无出场记录（多为魔神图等被排除关卡）：${census.unreferencedSprites.length}`);
  lines.push("");

  // 阶段 0 的行不进分组：它们有观测标识但不是待反推的账，混在"完整/残缺"里会把统计带偏。
  const onBoard = census.rows.filter((row) => row.excluded !== true);
  const groups: Array<[string, MonsterFlagRow[]]> = [
    ["标识完整", onBoard.filter((row) => row.status === "complete")],
    ["标识残缺", onBoard.filter((row) => row.status === "partial")],
    ["完全没有标识", onBoard.filter((row) => row.status === "missing")],
  ];

  for (const [title, rows] of groups) {
    lines.push(`## ${title}（${rows.length}）`);
    lines.push("");
    if (rows.length === 0) {
      lines.push("（无）");
      lines.push("");
      continue;
    }
    lines.push("| 模板 | 来源 | 缺的标识 | 阶段 | 阶段依据 | 反推候选 | 复算最大偏差 | 备注 |");
    lines.push("| --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const row of rows) {
      const proposal = proposalCells(row).join("；");
      const worst = row.fit?.residuals[0];
      const allFlags = row.missingFlags.length >= ALL_FLAG_FIELDS;
      lines.push(
        `| ${row.spritename} | ${row.sourceFile} | ${row.missingFlags.length === 0 ? "—" : allFlags ? `全部 ${ALL_FLAG_FIELDS} 项` : row.missingFlags.join("、")} | ${row.stageNumber ?? "—"} | ${row.stageSource === "flag" ? "沿用已有标识" : (row.stageBasis ?? "—")} | ${proposal || "—"} | ${worst ? `${PANEL_LABELS[worst.field] ?? worst.field} ${Math.round(worst.relativeError * 100)}%` : "—"} | ${notesCell(row)} |`,
      );
    }
    lines.push("");
  }

  const outOfRangeRows = census.rows.filter((row) => row.fit?.outOfRange !== undefined);
  if (outOfRangeRows.length > 0) {
    const tally = new Map<string, number>();
    for (const row of outOfRangeRows) {
      for (const entry of row.fit?.outOfRange ?? []) {
        tally.set(MONSTER_COEFFICIENT_TO_FLAG[entry.name], (tally.get(MONSTER_COEFFICIENT_TO_FLAG[entry.name]) ?? 0) + 1);
      }
    }
    lines.push(`## 反推值超出参考区间（${outOfRangeRows.length} 行）`);
    lines.push("");
    lines.push(`- 按系数计：${[...tally].map(([flag, count]) => `${flag} ${count} 行`).join("、")}`);
    lines.push("- 区间是参考区间，取值已按实算登记；明细见 `data/monster-flag-out-of-range.csv`，改数值改 `data/monster-flag-table.csv`。");
    lines.push("");
  }

  if (census.unreferencedSprites.length > 0) {
    lines.push(`## 无出场记录（${census.unreferencedSprites.length}）`);
    lines.push("");
    lines.push("这些模板在纳入统计的关卡里查不到注册，多数是被排除的魔神图与待登场单位；请人工确认排除没有过头。");
    lines.push("");
    lines.push(census.unreferencedSprites.join("、"));
    lines.push("");
  }

  return `${lines.join("\n")}\n`;
}

function parseKnown(value: string | boolean | undefined): Partial<MonsterInput> {
  if (typeof value !== "string") return {};
  const known: Record<string, number> = {};
  for (const pair of value.split(",")) {
    const [field, number] = pair.split("=");
    const name = MONSTER_FLAG_TO_COEFFICIENT[(field ?? "").trim()];
    const parsed = Number(number);
    if (name === undefined || !Number.isFinite(parsed)) throw new Error(`--known 需要 标识字段=数值 形式：${pair}`);
    Object.assign(known, { [name]: parsed });
  }
  return known as Partial<MonsterInput>;
}

function parseFlags(argv: string[]): { flags: Record<string, string | boolean>; positional: string[] } {
  const flags: Record<string, string | boolean> = {};
  const positional: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]!;
    if (!token.startsWith("--")) {
      positional.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      flags[key] = true;
      continue;
    }
    flags[key] = next;
    index += 1;
  }
  return { flags, positional };
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

main(process.argv.slice(2));
