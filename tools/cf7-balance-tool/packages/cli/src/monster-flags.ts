/**
 * 怪物标识普查与反推 CLI — 长期复用的数值工具入口。
 *
 * 用法：
 *   npm run monster-census                     清点全部敌人模板，写 reports/monster-flag-census.json
 *     --markdown <路径>                        同时输出人工复核用表格（默认 reports/monster-flag-census.md）
 *     --tier-hints <路径.json>                 读入 spritename → 档次系数 的人工标注
 *     --fallback-tier <n>                      未标注档次时统一按该档次反推
 *     --only 敌人-A,敌人-B                      只反推指定模板
 *     --no-solve                              只清点缺项，不跑反推
 *     --scan-tier                             对未定档的行做档次扫描（慢，仅作人工定档排序参考）
 *   npm run monster-solve -- 敌人-体育老师 --stage 4 --tier 12 --known 速度系数=2.5
 *   npm run monster-solve -- 敌人-XX --stage 3 --scan              只扫描档次候选
 *   npm run monster-flags-apply -- --from reports/monster-flag-census.json [--write]
 *     --only 敌人-A,敌人-B                      只写指定模板，用于小批试点
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { scanTierFactor, snapMonsterCoefficient, solveMonsterCoefficients, speedFactorFromMoveSpeed } from "@cf7-balance-tool/core";
import type { MonsterInput } from "@cf7-balance-tool/core";
import {
  MONSTER_FLAG_TO_COEFFICIENT,
  applyMonsterFlagUpdates,
  censusMonsterFlags,
  loadMonsterCensusConfig,
} from "@cf7-balance-tool/xml-io";
import type { MonsterCensusOptions, MonsterFlagCensus, MonsterFlagRow, MonsterFlagUpdate } from "@cf7-balance-tool/xml-io";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const CONFIG_PATH = path.join(TOOL_ROOT, "data", "monster-census.json");
const CENSUS_PATH = path.join(TOOL_ROOT, "reports", "monster-flag-census.json");
const CENSUS_MARKDOWN_PATH = path.join(TOOL_ROOT, "reports", "monster-flag-census.md");

const COEFFICIENT_ORDER: Array<keyof MonsterInput> = [
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
    ...(typeof flags["tier-hints"] === "string" ? { tierHints: readTierHints(path.resolve(TOOL_ROOT, flags["tier-hints"])) } : {}),
    ...(flags["fallback-tier"] === undefined ? {} : { fallbackTier: Number(flags["fallback-tier"]) }),
    ...(typeof flags.only === "string" ? { only: splitList(flags.only) } : positional.length > 0 ? { only: positional } : {}),
    ...(flags["no-solve"] === true ? { skipSolve: true } : {}),
    ...(flags["scan-tier"] === true ? { scanTier: true } : {}),
  };

  const census = censusMonsterFlags(REPO_ROOT, config, options);
  writeJson(CENSUS_PATH, census);
  console.log(`普查完成：${census.totals.templates} 个模板，完整 ${census.totals.complete}，残缺 ${census.totals.partial}，无标识 ${census.totals.missing}，阶段可查 ${census.totals.stageResolved}，已反推 ${census.totals.solved}`);
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
  if (flags.stage === undefined && flags.tier === undefined) throw new Error("solve 需要 --stage（或同时给 --tier）");

  const config = loadMonsterCensusConfig(CONFIG_PATH);
  const census = censusMonsterFlags(REPO_ROOT, config, { skipSolve: true, only: [spritename] });
  const row = census.rows.find((entry) => entry.spritename === spritename);
  if (!row) throw new Error(`普查里找不到 ${spritename}`);

  const stage = Number(flags.stage ?? row.stageNumber);
  if (!Number.isFinite(stage)) throw new Error(`${spritename} 没有阶段，请用 --stage 指定`);
  const known = parseKnown(flags.known);
  const moveSpeed = row.moveSpeed === undefined ? {} : { moveSpeed: row.moveSpeed };

  if (flags.scan === true || flags.tier === undefined) {
    const ranked = scanTierFactor({ stage, panel: row.panel, known, ...moveSpeed });
    console.log(`${spritename}（阶段 ${stage}）档次候选（按面板拟合误差排序，仅供人工定档参考）：`);
    for (const candidate of ranked.slice(0, Number(flags.limit ?? 6))) {
      console.log(`  档次 ${candidate.tierFactor}：拟合误差 ${Math.round(candidate.fitError * 1000) / 10}%`);
    }
    console.log("  注意：没有其余标识时档次单独拟合会整体偏低，请结合样貌与招式定档。");
    if (flags.tier === undefined) return;
  }

  const result = solveMonsterCoefficients({
    stage,
    tierFactor: Number(flags.tier),
    panel: row.panel,
    known,
    ...moveSpeed,
  });

  console.log(`${spritename}（阶段 ${stage}，档次 ${flags.tier}）`);
  for (const name of COEFFICIENT_ORDER) {
    const estimate = result.estimates.find((entry) => entry.name === name);
    const flagName = Object.keys(MONSTER_FLAG_TO_COEFFICIENT).find((key) => MONSTER_FLAG_TO_COEFFICIENT[key] === name);
    console.log(`  ${flagName ?? name}: ${result.coefficients[name]}${estimate ? `（${estimate.confidence}｜${estimate.basis}）` : ""}`);
  }
  console.log(`  未定：${result.unresolved.join("、") || "无"}`);
  if (result.attackTempoTarget !== undefined) console.log(`  攻击节奏乘积目标：${result.attackTempoTarget}`);
  for (const residual of result.residuals) {
    console.log(`  ${PANEL_LABELS[residual.field] ?? residual.field}：面板 ${residual.observed} / 复算 ${round(residual.computed, 1)}（差 ${Math.round(residual.relativeError * 1000) / 10}%）`);
  }
  result.notes.forEach((note) => console.log(`  提示：${note}`));
}

function runApply(flags: Record<string, string | boolean>, positional: string[]): void {
  const source = typeof flags.from === "string" ? flags.from : positional[0];
  if (!source) throw new Error("apply 需要给出候选 JSON 路径（--from <路径>）");
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

function readTierHints(filePath: string): Record<string, number> {
  const raw = JSON.parse(fs.readFileSync(filePath, "utf8")) as Record<string, unknown>;
  const hints: Record<string, number> = {};
  for (const [key, value] of Object.entries(raw)) {
    const number = typeof value === "number" ? value : Number(value);
    if (Number.isFinite(number)) hints[key] = number;
  }
  return hints;
}

/** 候选文件既接受普查 JSON 的子集，也接受人工整理的 spritename → 标识 映射。 */
function readUpdates(filePath: string): MonsterFlagUpdate[] {
  const raw = JSON.parse(fs.readFileSync(filePath, "utf8")) as unknown;
  if (Array.isArray(raw)) return raw as MonsterFlagUpdate[];
  if (isRecord(raw) && Array.isArray(raw.rows)) {
    return (raw.rows as MonsterFlagRow[])
      .map((row) => ({
        sourceFile: row.sourceFile,
        spritename: row.spritename,
        flags: row.solve === undefined ? mechanicalFlags(row) : proposalFlags(row),
      }))
      .filter((update) => Object.keys(update.flags).length > 0);
  }
  throw new Error(`候选文件格式不认识：${filePath}`);
}

function proposalFlags(row: MonsterFlagRow): Record<string, number> {
  const solve = row.solve;
  if (!solve) return {};
  const flags: Record<string, number> = {};
  for (const [field, name] of Object.entries(MONSTER_FLAG_TO_COEFFICIENT)) {
    if (row.flags[field] !== undefined) continue;
    // fallback 档次只是让反推跑起来的假设，不是设计判断，不能写进数据。
    if (name === "tierFactor" && solve.tierSource === "fallback") continue;
    if (solve.unresolved.includes(name)) continue;
    if (name === "atkSpeedFactor" || name === "atkMultiplier" || name === "segmentFactor") continue;
    // 连续解不能直接进数据：先归到 整数 → 半档 → 十分档 的取值词表上。
    flags[field] = snapMonsterCoefficient(solve.coefficients[name]).value;
  }
  return flags;
}

/** 展示反推候选：归档后的取值后面括号给出连续解，便于人工判断半档是不是真有必要。 */
function proposalCells(row: MonsterFlagRow): string[] {
  const solve = row.solve;
  if (!solve) return [];
  const cells: string[] = [];
  for (const [field, value] of Object.entries(proposalFlags(row))) {
    const name = MONSTER_FLAG_TO_COEFFICIENT[field];
    const continuous = name === undefined ? value : solve.coefficients[name];
    cells.push(`${field} ${value}${Math.abs(continuous - value) > 1e-9 ? `（连续 ${continuous.toFixed(3)}）` : ""}`);
  }
  return cells;
}

/** 不需要人工输入就能定的标识：阶段来自首次出场规则，速度系数来自 Excel D15 的移动速度档次。 */
function mechanicalFlags(row: MonsterFlagRow): Record<string, number> {
  const flags: Record<string, number> = {};
  if (row.flags["阶段"] === undefined && row.stageNumber !== undefined) Object.assign(flags, { 阶段: row.stageNumber });
  if (row.flags["速度系数"] === undefined && row.moveSpeed) {
    Object.assign(flags, { 速度系数: speedFactorFromMoveSpeed(row.moveSpeed.min, row.moveSpeed.max).value });
  }
  return flags;
}

function autoFillFlags(row: MonsterFlagRow): string[] {
  return Object.entries(mechanicalFlags(row)).map(([field, value]) => `${field} ${value}`);
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

/** 备注列把「速度系数定义档与面板/标识不符」这类必须人工回查的报警顶到前面，再附原有首条说明。 */
function notesCell(row: MonsterFlagRow): string {
  if (row.skipReason) return row.skipReason;
  const notes = row.solve?.notes ?? [];
  const first = notes[0] ?? "";
  const speed = notes.find((note) => note.includes("速度系数定义档"));
  if (!speed || speed === first) return first;
  return `${speed}；${first}`;
}

function renderMarkdown(census: MonsterFlagCensus): string {
  const lines: string[] = [];
  const autoStage = census.rows.filter((row) => row.stageSource === "first-appearance").length;
  const autoSpeed = census.rows.filter((row) => row.flags["速度系数"] === undefined && row.moveSpeed !== undefined).length;

  lines.push(`# 怪物标识普查（配置 v${census.configVersion}）`);
  lines.push("");
  lines.push(`- 纳入模板：${census.totals.templates}（来源 ${census.sourceFiles.length} 个文件，排除 ${census.excludedSourceFiles.join("、")}）`);
  lines.push(`- 标识完整 ${census.totals.complete}／残缺 ${census.totals.partial}／全无 ${census.totals.missing}`);
  lines.push(`- 阶段可查 ${census.totals.stageResolved}，已产出反推候选 ${census.totals.solved}，跳过 ${census.totals.skipped}`);
  lines.push(`- 无需人工输入即可补：阶段 ${autoStage} 个（首次出场规则）、速度系数 ${autoSpeed} 个（Excel D15 移动速度档次）`);
  lines.push(`- 无出场记录（多为魔神图等被排除关卡）：${census.unreferencedSprites.length}`);
  lines.push("");

  const groups: Array<[string, MonsterFlagRow[]]> = [
    ["标识完整", census.rows.filter((row) => row.status === "complete")],
    ["标识残缺", census.rows.filter((row) => row.status === "partial")],
    ["完全没有标识", census.rows.filter((row) => row.status === "missing")],
  ];

  for (const [title, rows] of groups) {
    lines.push(`## ${title}（${rows.length}）`);
    lines.push("");
    if (rows.length === 0) {
      lines.push("（无）");
      lines.push("");
      continue;
    }
    lines.push("| 模板 | 来源 | 缺的标识 | 阶段 | 阶段依据 | 可自动补 | 档次候选 | 反推候选 | 复算最大偏差 | 备注 |");
    lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const row of rows) {
      const proposal = proposalCells(row).join("；");
      const worst = row.solve?.residuals[0];
      const candidates = (row.tierCandidates ?? []).map((entry) => `${entry.tierFactor}(${Math.round(entry.fitError * 100)}%)`).join(" ");
      const auto = autoFillFlags(row).join("；");
      const allFlags = row.missingFlags.length >= ALL_FLAG_FIELDS;
      lines.push(
        `| ${row.spritename} | ${row.sourceFile} | ${row.missingFlags.length === 0 ? "—" : allFlags ? `全部 ${ALL_FLAG_FIELDS} 项` : row.missingFlags.join("、")} | ${row.stageNumber ?? "—"} | ${row.stageSource === "flag" ? "沿用已有标识" : (row.stageBasis ?? "—")} | ${auto || "—"} | ${candidates || "—"} | ${proposal || "—"} | ${worst ? `${PANEL_LABELS[worst.field] ?? worst.field} ${Math.round(worst.relativeError * 100)}%` : "—"} | ${notesCell(row)} |`,
      );
    }
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
