/**
 * 怪物标识查验表 — 反推结果与人工标识的人工查验面，一共四张。
 *
 * 用法：
 *   npm run monster-census                先出 reports/monster-flag-census.json（反推就在这一步算）
 *   npm run monster-flags-csv             写 data/ 下的四张表
 *   npm run monster-flags-csv -- --high-error-threshold 0.3   放宽偏差大表的门槛
 *
 * 四张表的分工：
 * - `monster-flag-table.csv` 全量表：工具自己识别出来的怪，一行一怪，十项系数各一列，人直接在这张表上改数，
 *   改完用 `npm run monster-flags-table-apply` 写回 `data/enemy_properties/*.xml`。
 * - `monster-flag-out-of-range.csv` 超范围表：系数落在参考区间外的行，只看/不改。
 * - `monster-flag-high-error.csv` 偏差大表：复算面板与盘上面板对不上的行（含制作组指定档次的全部行），只看/不改。
 * - `monster-flag-human.csv` 人工表：制作组在 git HEAD 里已经完整打过标的行（除 速度系数 外十项齐全），
 *   记的是 HEAD 那份原文的值，只看/不改，也不参与上面三张表的任何统计。
 *
 * **人工完整打标的行为什么要摘出去（制作组 2026-10-07 口径）**：那批行的攻速系数/攻击倍率/段数系数 是人工按手感填的，
 * 混进统计面就看不出「脚本识别得对不对」，误差也会被人工值一起承担。摘出来后三张表只数工具识别的行，
 * 人工那批另存一张表，留着以后逐行对照「人工标的」与「脚本测的」是否一致。
 * 注意人工表印的是 HEAD 的值，与盘上现值可能不同（例如 骨刺僵尸 的 阶段：HEAD 4、盘上 5）—— 那正是对照要看的东西。
 *
 * 表里的数按「盘上现值 ∪ 工具这批该写的值」给，误差也由这组数复算，所以表上看到的误差能由 XML 里的标识重现，
 * 不是拟合中间过程的连续解。超范围/偏差大/人工三张是只读投影，改数值只改全量表。
 *
 * 各表排序（都是为了让同类连片、一眼看出问题）：
 * - 全量表 / 人工表：阶段从低到高（缺阶段的排最后）→ 同阶段内按 档次系数 从小到大（缺档次的排最后）→ 同一数据文件聚在一起
 *   → 文件内按模板名。同一条阶段链上的怪往往出自同一份 XML，这样排能把「一批同阶段的怪系数齐不齐」直接看出来。
 *   数据文件在全量表参与排序但不占一列（2026-10-06 制作组口径：这一列没用人工看）；人工表要按文件回查人工批次，所以给它留了列。
 * - 超范围表：档次系数 越界的行整块置顶（这一类是「面板超出档次表」的账，要先看），块内与其后的行都按最严重那一格的
 *   超出倍数降序 → 阶段升序 → 模板名。超出倍数 = 上界外 `值/上限`、下界外 `下限/值`，1 倍就是贴线、2 倍是差一个量级的一半；
 *   除原有列外另给「最越界的系数」「超出倍数」两列，供人按轻重处置。倍数与误差都按表上印出来的精度分桶比较，
 *   浮点尾差不许把看着同倍数的两行拆到两处。
 * - 偏差大表：误差值降序，同误差按模板名。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  MONSTER_COEFFICIENT_DEFAULTS,
  MONSTER_COEFFICIENT_RANGES,
  MONSTER_FIT_PANEL_FIELDS,
  computeMonsterRow,
} from "@cf7-balance-tool/core";
import type { MonsterInput, MonsterPanelField, MonsterPanelResidual } from "@cf7-balance-tool/core";
import {
  MONSTER_FLAG_TO_COEFFICIENT,
  isFullyHumanFlagged,
  loadMonsterCensusConfig,
  stageProgressLabel,
  tierLabel,
  toolFlagProposal,
} from "@cf7-balance-tool/xml-io";
import type { MonsterCensusConfig, MonsterFlagCensus, MonsterFlagRow } from "@cf7-balance-tool/xml-io";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const CONFIG_PATH = path.join(TOOL_ROOT, "data", "monster-census.json");
const CENSUS_PATH = path.join(TOOL_ROOT, "reports", "monster-flag-census.json");
const DATA_DIR = path.join(TOOL_ROOT, "data");

const TABLE_PATH = path.join(DATA_DIR, "monster-flag-table.csv");
const OUT_OF_RANGE_PATH = path.join(DATA_DIR, "monster-flag-out-of-range.csv");
const HIGH_ERROR_PATH = path.join(DATA_DIR, "monster-flag-high-error.csv");
const HUMAN_PATH = path.join(DATA_DIR, "monster-flag-human.csv");

/** 默认偏差门槛：全量拟合的误差中位在 15% 上下，20% 以上才算"这组标识配不上这块面板"。 */
const DEFAULT_HIGH_ERROR_THRESHOLD = 0.2;

/** 面板列的中文短名，与 reports 里一直用的叫法一致。 */
const PANEL_LABELS: Record<MonsterPanelField, string> = {
  atkMin: "空手MIN",
  atkMax: "空手MAX",
  hpMin: "HPmin",
  hpMax: "HPmax",
  defMin: "防御min",
  defMax: "防御max",
  expMin: "经验min",
  expMax: "经验max",
  goldPrice: "金币价格",
  kPointPrice: "K点价格",
};

/** 排序只用到这两样：行本身与要印出来的取值。全量表与人工表共用同一条排序。 */
interface Sortable {
  row: MonsterFlagRow;
  values: Record<string, number | undefined>;
}

interface RowView extends Sortable {
  error: number;
  worst: MonsterPanelResidual | undefined;
  outOfRange: string[];
  /** 越界项按倍数从大到小排好，超范围表就按第一项排序。 */
  exceedances: Exceedance[];
}

/**
 * 一格越界的多严重：上界外看 `值/上限`，下界外看 `下限/值`，所以 1 就是贴线，2 表示差一个量级的一半。
 * 光有「越界」两字分不出轻重 —— 段数 10.4 与段数 22.1 都算越界，但只有后者值得先看上去。
 */
interface Exceedance {
  field: string;
  value: number;
  low: number;
  high: number;
  ratio: number;
}

function main(argv: string[]): void {
  const { flags } = parseFlags(argv);
  const config = loadMonsterCensusConfig(CONFIG_PATH);
  const census = readCensus();
  const threshold = flags["high-error-threshold"] === undefined ? DEFAULT_HIGH_ERROR_THRESHOLD : Number(flags["high-error-threshold"]);

  const views = census.rows
    .filter((row) => !isWaived(row, config) && !isExcluded(row) && !isFullyHumanFlagged(row, config))
    .map((row) => viewOf(row, config));
  const human = census.rows.filter((row) => isFullyHumanFlagged(row, config));
  const named = views.filter((view) => isNamedTier(view.row, config));
  const high = views.filter((view) => isHighError(view, config, threshold));

  writeTableCsv(views, config);
  writeOutOfRangeCsv(views);
  writeHighErrorCsv(high, config);
  writeHumanCsv(human, config);

  console.log(`全量表 → ${TABLE_PATH}（${views.length} 行）`);
  console.log(`超范围表 → ${OUT_OF_RANGE_PATH}（${views.filter((view) => view.outOfRange.length > 0).length} 行）`);
  console.log(`偏差大表 → ${HIGH_ERROR_PATH}（${high.length} 行，门槛 ${(threshold * 100).toFixed(0)}%）`);
  console.log(`  其中制作组点名档次的 ${named.length} 行全部列入，不看过不过门槛`);
  console.log(`人工表 → ${HUMAN_PATH}（${human.length} 行，git HEAD 里除 速度系数 外十项都已人工打标，不进上面三张表的统计）`);
  console.log(`  未参与：无需标识 ${census.totals.waived} 行、阶段 0 排除 ${census.rows.filter(isExcluded).length} 行`);
}

function readCensus(): MonsterFlagCensus {
  if (!fs.existsSync(CENSUS_PATH)) {
    throw new Error(`找不到普查结果 ${CENSUS_PATH}，先跑 npm run monster-census`);
  }
  return JSON.parse(fs.readFileSync(CENSUS_PATH, "utf8")) as MonsterFlagCensus;
}

/** 无需标识的行按配置判，不看盘上有没有残留值。 */
function isWaived(row: MonsterFlagRow, config: MonsterCensusConfig): boolean {
  return row.waived === true || config.noFlagTemplates?.includes(row.spritename) === true;
}

/** 阶段 0 的行按盘上标识判：制作组用它把待重做的怪整只摘出面板体系，四张表都不列。 */
function isExcluded(row: MonsterFlagRow): boolean {
  return row.excluded === true || row.flags["阶段"] === 0;
}

/**
 * 制作组点名的档次判定（配置 `humanTierFactors`）无条件进偏差大表：
 * 档次是人工按样貌与招式钉的，面板合不上只能说明面板或阶段有问题，必须让人看见，不能被门槛挡掉。
 * git HEAD 已提交的标识里也带档次系数，那批是按老口径校准过的，过门槛才进表。
 */
function isNamedTier(row: MonsterFlagRow, config: MonsterCensusConfig): boolean {
  return config.humanTierFactors?.[row.spritename] !== undefined;
}

/** 档次系数的来源，只用来解释这一行为什么钉在这个档次上。 */
function tierSource(row: MonsterFlagRow, config: MonsterCensusConfig): string {
  if (isNamedTier(row, config)) return "制作组点名";
  if (row.humanFlags?.["档次系数"] !== undefined) return "已提交标识";
  return "拟合";
}

function isHighError(view: RowView, config: MonsterCensusConfig, threshold: number): boolean {
  if (isNamedTier(view.row, config)) return true;
  return view.worst !== undefined && view.error >= threshold;
}

function viewOf(row: MonsterFlagRow, config: MonsterCensusConfig): RowView {
  const values: Record<string, number | undefined> = {};
  for (const field of config.flagFields) Object.assign(values, { [field]: row.flags[field] });
  for (const [field, value] of Object.entries(toolFlagProposal(row))) Object.assign(values, { [field]: value });

  const computed = computeMonsterRow(toCoefficientInput(values));
  const residuals: MonsterPanelResidual[] = [];
  for (const field of MONSTER_FIT_PANEL_FIELDS) {
    const observed = row.panel[field];
    if (observed === undefined || !Number.isFinite(observed)) continue;
    residuals.push({ field, observed, computed: computed[field], relativeError: Math.abs(computed[field] - observed) / (Math.abs(observed) + 1e-9) });
  }
  residuals.sort((left, right) => right.relativeError - left.relativeError);

  const exceedances: Exceedance[] = [];
  for (const [field, value] of Object.entries(values)) {
    if (value === undefined) continue;
    const name = MONSTER_FLAG_TO_COEFFICIENT[field];
    if (name === undefined) continue;
    const [low, high] = MONSTER_COEFFICIENT_RANGES[name];
    if (value < low || value > high) {
      exceedances.push({ field, value, low, high, ratio: value > high ? value / high : low / (value === 0 ? 1e-9 : value) });
    }
  }
  exceedances.sort((left, right) => ratioKey(right.ratio) - ratioKey(left.ratio) || left.field.localeCompare(right.field, "zh"));
  const outOfRange = exceedances.map((item) => `${item.field} ${trim(item.value)}（参考 ${trim(item.low)}~${trim(item.high)}）`);

  const worst = residuals[0];
  return {
    row,
    values,
    error: residuals.length === 0 ? 0 : Math.sqrt(residuals.reduce((sum, item) => sum + item.relativeError ** 2, 0) / residuals.length),
    worst,
    outOfRange,
    exceedances,
  };
}

/** 缺的系数按工作簿默认值补着复算：面板读不全的行照样要报错差，但缺项本身留空让人工看见。 */
function toCoefficientInput(values: Record<string, number | undefined>): MonsterInput {
  const parsed: Record<string, number> = { stage: 1, tierFactor: 1, ...MONSTER_COEFFICIENT_DEFAULTS };
  for (const [field, value] of Object.entries(values)) {
    const name = MONSTER_FLAG_TO_COEFFICIENT[field];
    if (name === undefined || value === undefined) continue;
    Object.assign(parsed, { [name]: value });
  }
  return parsed as unknown as MonsterInput;
}

// ---------------------------------------------------------------- 全量表

function writeTableCsv(views: RowView[], config: MonsterCensusConfig): void {
  const head = ["模板", "别名", "主线进度", "档次描述", ...config.flagFields, "超出范围", "误差值"];
  const lines = [head.join(",")];
  for (const view of [...views].sort(byStageThenTierThenFile)) {
    lines.push(
      [
        view.row.spritename,
        view.row.displayName ?? "",
        stageProgressLabel(config, view.values["阶段"]),
        tierLabel(config, view.values["档次系数"]),
        ...config.flagFields.map((field) => cell(view.values[field])),
        view.outOfRange.join("；"),
        view.worst === undefined ? "" : percent(view.error),
      ]
        .map(escapeCell)
        .join(","),
    );
  }
  writeCsv(TABLE_PATH, lines);
}

// ---------------------------------------------------------------- 超范围表

function writeOutOfRangeCsv(views: RowView[]): void {
  const rows = views.filter((view) => view.outOfRange.length > 0).sort(byTierFirstThenExceedance);
  const lines = ["模板,别名,数据文件,标识行,阶段,档次系数,最越界的系数,超出倍数,超出的系数与参考区间,误差值"];
  for (const view of rows) {
    const worst = view.exceedances[0];
    lines.push(
      [
        view.row.spritename,
        view.row.displayName ?? "",
        view.row.sourceFile,
        cell(flagLine(view.row.sourceFile, view.row.spritename)),
        cell(view.values["阶段"]),
        cell(view.values["档次系数"]),
        worst?.field ?? "",
        worst === undefined ? "" : `${trim(worst.ratio)}倍`,
        view.outOfRange.join("；"),
        view.worst === undefined ? "" : percent(view.error),
      ]
        .map(escapeCell)
        .join(","),
    );
  }
  writeCsv(OUT_OF_RANGE_PATH, lines);
}

// ---------------------------------------------------------------- 偏差大表

function writeHighErrorCsv(rows: RowView[], config: MonsterCensusConfig): void {
  const lines = [
    [
      "模板", "别名", "数据文件", "阶段", "主线进度", "档次系数", "档次描述", "档次来源",
      "误差值", "最差项", "面板值", "复算值", "该项偏差", "经验偏差", "偏差在哪",
    ].join(","),
  ];
  for (const view of [...rows].sort((left, right) => errorKey(right.error) - errorKey(left.error) || left.row.spritename.localeCompare(right.row.spritename, "zh"))) {
    const worst = view.worst;
    lines.push(
      [
        view.row.spritename,
        view.row.displayName ?? "",
        view.row.sourceFile,
        cell(view.values["阶段"]),
        stageProgressLabel(config, view.values["阶段"]),
        cell(view.values["档次系数"]),
        tierLabel(config, view.values["档次系数"]),
        tierSource(view.row, config),
        view.worst === undefined ? "无可比面板" : percent(view.error),
        worst === undefined ? "—" : PANEL_LABELS[worst.field],
        worst === undefined ? "" : trim(worst.observed),
        worst === undefined ? "" : trim(worst.computed),
        worst === undefined ? "" : percent(worst.relativeError),
        expDeviations(view),
        noteCell(view),
      ]
        .map(escapeCell)
        .join(","),
    );
  }
  writeCsv(HIGH_ERROR_PATH, lines);
}

/** 经验两项按制作组口径随时可重算，不进误差值，但复算差多少还是列出来，方便判断是不是整条阶段链都偏了。 */
function expDeviations(view: RowView): string {
  return (view.row.fit?.expResiduals ?? [])
    .map((residual) => `${PANEL_LABELS[residual.field]} 面板 ${trim(residual.observed)}/复算 ${trim(residual.computed)}（${percent(residual.relativeError)}）`)
    .join("；");
}

/** 偏差在哪：先说面板读不到的项，再说反推自身的报警，最后给最差项的方向。 */
function noteCell(view: RowView): string {
  const parts: string[] = [];
  const missing = MONSTER_FIT_PANEL_FIELDS.filter((field) => view.row.panel[field] === undefined).map((field) => PANEL_LABELS[field]);
  if (missing.length > 0) parts.push(`面板缺 ${missing.join("、")}`);
  view.row.fit?.notes.forEach((note) => parts.push(note));
  if (view.worst !== undefined) {
    parts.push(`${PANEL_LABELS[view.worst.field]} ${view.worst.computed > view.worst.observed ? "复算偏高" : "复算偏低"}`);
  }
  return [...new Set(parts)].join("；");
}

// ---------------------------------------------------------------- 人工表

/**
 * 人工表：值直接取 git HEAD 那份 `<标识>`（`row.humanFlags`），不掺盘上现值、也不算工具候选 ——
 * 这张表的用途是日后逐行对照「人工标的」与「脚本测的」，掺进工具侧的值就不是人工账了。
 * 所以表上的 阶段 可能与全量表/盘上不同（骨刺僵尸 HEAD 4、盘上 5），这类差异正是要对照的东西。
 */
function writeHumanCsv(rows: MonsterFlagRow[], config: MonsterCensusConfig): void {
  const head = ["模板", "别名", "数据文件", "标识行", "主线进度", "档次描述", ...config.flagFields];
  const lines = [head.join(",")];
  const sortable: Sortable[] = rows.map((row) => ({ row, values: row.humanFlags ?? {} }));
  for (const view of [...sortable].sort(byStageThenTierThenFile)) {
    lines.push(
      [
        view.row.spritename,
        view.row.displayName ?? "",
        view.row.sourceFile,
        cell(flagLine(view.row.sourceFile, view.row.spritename)),
        stageProgressLabel(config, view.values["阶段"]),
        tierLabel(config, view.values["档次系数"]),
        ...config.flagFields.map((field) => cell(view.values[field])),
      ]
        .map(escapeCell)
        .join(","),
    );
  }
  writeCsv(HUMAN_PATH, lines);
}

// ---------------------------------------------------------------- 公共写法

/** 全量表：阶段从低到高（缺阶段排最后）→ 同阶段内按 档次系数 从小到大（缺档次排最后）→ 同一数据文件聚在一起 → 文件内按模板名。 */
function byStageThenTierThenFile(left: Sortable, right: Sortable): number {
  // 缺阶段/缺档次的行两边都是 +∞，不能相减（∞-∞ 是 NaN），所以逐边比较而不是作差。
  const byStage = before(left, right, stageOf);
  if (byStage !== 0) return byStage;
  const byTier = before(left, right, tierOf);
  if (byTier !== 0) return byTier;
  return (
    left.row.sourceFile.localeCompare(right.row.sourceFile, "zh") ||
    left.row.spritename.localeCompare(right.row.spritename, "zh")
  );
}

function stageOf(view: Sortable): number {
  const stage = view.values["阶段"];
  return stage === undefined || !Number.isFinite(stage) ? Number.POSITIVE_INFINITY : stage;
}

function tierOf(view: Sortable): number {
  const tier = view.values["档次系数"];
  return tier === undefined || !Number.isFinite(tier) ? Number.POSITIVE_INFINITY : tier;
}

/**
 * 超范围表：档次系数 越界的行整块置顶（制作组 2026-10-06 口径：档次搜索已放开到参考区间之外，
 * 这一类是「面板超出档次表」的账，要先看），块内与其后的行都按最严重那一格的超出倍数降序 → 阶段升序 → 模板名。
 */
function byTierFirstThenExceedance(left: RowView, right: RowView): number {
  const leftTier = tierExceedanceOf(left) === undefined ? 0 : 1;
  const rightTier = tierExceedanceOf(right) === undefined ? 0 : 1;
  if (leftTier !== rightTier) return rightTier - leftTier;
  return byExceedanceThenStage(left, right);
}

function tierExceedanceOf(view: RowView): Exceedance | undefined {
  return view.exceedances.find((item) => item.field === "档次系数");
}

/** 按最严重那格的超出倍数降序，同倍数再按阶段从低到高（越界的成因常沿同一条阶段链连片）。 */
function byExceedanceThenStage(left: RowView, right: RowView): number {
  const byRatio = before(right, left, (view) => ratioKey(view.exceedances[0]?.ratio ?? 0));
  if (byRatio !== 0) return byRatio;
  const byStage = before(left, right, stageOf);
  if (byStage !== 0) return byStage;
  return left.row.spritename.localeCompare(right.row.spritename, "zh");
}

/**
 * 排序按表上印出来的倍数（两位小数）分桶，不按浮点原值。
 * 4.2/3 与 2.8/2 在浮点里差 3e-17，屏幕上都写着 `1.4倍` —— 按原值排会让两行看着同倍数的行各归各处，
 * 阶段那条次级键永远轮不到。
 */
function ratioKey(ratio: number): number {
  return Math.round(ratio * 100) / 100;
}

/** 误差同理按表上印出来的 0.1% 粒度分桶，不然同写 19.4% 的换皮三兄弟会被浮点尾差拆散。 */
function errorKey(error: number): number {
  return Math.round(error * 1000) / 1000;
}

/** key(left) 严格小于 key(right) 返回 -1，严格大于返回 1，其余 0（含两key相等与 NaN 情形）。 */
function before<T>(left: T, right: T, key: (value: T) => number): number {
  const a = key(left);
  const b = key(right);
  if (a < b) return -1;
  return a > b ? 1 : 0;
}

function writeCsv(target: string, lines: string[]): void {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  // Excel 直接打开要 BOM，行尾按 Windows 口径给 CRLF
  fs.writeFileSync(target, `\uFEFF${lines.join("\r\n")}\r\n`, "utf8");
}

/** `<标识>` 在工作树里的行号，纯给人工跳转用；读不到留空，不拿近似值糊人。 */
const flagLineCache = new Map<string, string[]>();

function flagLine(sourceFile: string, spritename: string): number | undefined {
  const file = path.join(REPO_ROOT, "data", "enemy_properties", sourceFile);
  let lines = flagLineCache.get(file);
  if (lines === undefined) {
    lines = fs.existsSync(file) ? fs.readFileSync(file, "utf8").split(/\r?\n/) : [];
    flagLineCache.set(file, lines);
  }
  const open = lines.findIndex((line) => line.trim() === `<${spritename}>`);
  if (open < 0) return undefined;
  for (let index = open; index < lines.length; index += 1) {
    if (lines[index]!.trim() === "<标识>") return index + 1;
  }
  return undefined;
}

function cell(value: number | undefined): string {
  return value === undefined ? "" : trim(value);
}

function trim(value: number): string {
  return String(Math.round(value * 100) / 100);
}

function percent(value: number): string {
  return `${Math.round(value * 1000) / 10}%`;
}

function escapeCell(value: string): string {
  return /[",\r\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
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

main(process.argv.slice(2));
