/**
 * 全量表回写 — 把 data/monster-flag-table.csv 上人工改过的系数写回 data/enemy_properties/*.xml。
 *
 * 用法：
 *   npm run monster-flags-table-apply              只看会改哪些格
 *   npm run monster-flags-table-apply -- --write    落盘
 *   npm run monster-flags-table-apply -- --only 敌人-A,敌人-B
 *
 * 表是全量查验面：一行一怪，十项系数各一列。空格表示"这一项不改"，不是"删掉这一项"；
 * 只有与盘上现值不同的单元格才进写盘名单，所以重跑一遍不改表不会产生任何文件改动。
 * 表上的 主线进度/档次描述/超出范围/误差值 是派生列，回写时一律忽略（列按表头名定位，少一列不影响读回）——
 * 改完整张表跑一次
 * `npm run monster-census && npm run monster-flags-csv` 才会重算这几列。
 * 唯一的特殊值是 阶段=0：那是制作组的排除标记（待重做/临时下线的怪），这一行只写阶段、其余九列整行忽略；
 * 阶段 0 的行不再参与反推，也不会再出现在下一次生成的表上。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  censusMonsterFlags,
  loadMonsterCensusConfig,
  parseCsvRows,
  applyMonsterFlagUpdates,
} from "@cf7-balance-tool/xml-io";
import type { MonsterCensusConfig, MonsterFlagRow } from "@cf7-balance-tool/xml-io";

import { headFlags } from "./monster-flag-provenance.js";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const CONFIG_PATH = path.join(TOOL_ROOT, "data", "monster-census.json");
const TABLE_PATH = path.join(TOOL_ROOT, "data", "monster-flag-table.csv");

/** 一行的改动：只收与盘上现值不同的单元格。 */
interface CellChange {
  sourceFile: string;
  spritename: string;
  flags: Record<string, number>;
  /** git HEAD 里已有值的字段：人工在表上改的，照改，但单独列出来让人看见自己动了已提交的标识。 */
  committed: string[];
}

function main(argv: string[]): void {
  const { flags } = parseFlags(argv);
  const config = loadMonsterCensusConfig(CONFIG_PATH);
  if (!fs.existsSync(TABLE_PATH)) throw new Error(`找不到全量表 ${TABLE_PATH}，先跑 npm run monster-flags-csv`);

  const rows = readTable(TABLE_PATH, config);
  const census = censusMonsterFlags(REPO_ROOT, config, { skipFit: true, humanFlags: headFlags(REPO_ROOT, config) });
  const bySprite = new Map(census.rows.map((row) => [row.spritename, row]));

  const unknown = rows.filter((row) => !bySprite.has(row.spritename)).map((row) => row.spritename);
  if (unknown.length > 0) {
    throw new Error(`全量表里有 ${unknown.length} 个模板在敌人属性里找不到：${unknown.slice(0, 10).join("、")}${unknown.length > 10 ? " …" : ""}`);
  }

  let only: Set<string> | undefined;
  if (typeof flags.only === "string") only = new Set(flags.only.split(",").map((entry) => entry.trim()).filter(Boolean));

  const changes: CellChange[] = [];
  for (const row of rows) {
    if (only !== undefined && !only.has(row.spritename)) continue;
    const change = diffOf(row, bySprite.get(row.spritename)!, config);
    if (change !== undefined) changes.push(change);
  }

  const touched = changes.reduce((sum, change) => sum + Object.keys(change.flags).length, 0);
  const committedFields = changes.flatMap((change) => change.committed);
  console.log(`全量表 ${rows.length} 行，要改 ${changes.length} 行 / ${touched} 个系数`);
  if (committedFields.length > 0) {
    console.log(`  其中 ${committedFields.length} 项落在 git HEAD 已提交的标识上（人工在表上改的，照改）：${committedFields.slice(0, 12).join("、")}`);
  }
  for (const change of changes.slice(0, 40)) {
    console.log(`  ${change.spritename}：${Object.entries(change.flags).map(([field, value]) => `${field} ${value}`).join("、")}`);
  }
  if (changes.length > 40) console.log(`  … 共 ${changes.length} 行`);

  if (flags.write !== true) {
    console.log("未写入（加 --write 才落盘）");
    return;
  }
  if (changes.length === 0) {
    console.log("没有差异可写");
    return;
  }
  const written = applyMonsterFlagUpdates(
    REPO_ROOT,
    changes.map((change) => ({ sourceFile: change.sourceFile, spritename: change.spritename, flags: change.flags })),
    config,
  );
  console.log(`已写入 ${written.length} 个文件：\n${written.map((file) => `  ${path.relative(REPO_ROOT, file)}`).join("\n")}`);
}

interface TableRow {
  spritename: string;
  values: Record<string, number | undefined>;
}

/** 按表头定位列，人工在 Excel 里挪过列序也不影响读回。 */
function readTable(csvPath: string, config: MonsterCensusConfig): TableRow[] {
  const rows = parseCsvRows(fs.readFileSync(csvPath, "utf8"));
  const head = rows.shift() ?? [];
  const nameColumn = head.indexOf("模板");
  if (nameColumn < 0) throw new Error(`${csvPath} 的表头缺少「模板」列`);
  const columns = config.flagFields.map((field) => ({ field, index: head.indexOf(field) }));
  const missing = columns.filter((column) => column.index < 0).map((column) => column.field);
  if (missing.length > 0) throw new Error(`${csvPath} 的表头缺少系数列：${missing.join("、")}`);

  const out: TableRow[] = [];
  const bad: string[] = [];
  for (const row of rows) {
    const spritename = (row[nameColumn] ?? "").trim();
    if (spritename === "") continue;
    const values: Record<string, number | undefined> = {};
    for (const { field, index } of columns) {
      const raw = (row[index] ?? "").trim();
      if (raw === "") {
        Object.assign(values, { [field]: undefined });
        continue;
      }
      const parsed = Number(raw);
      if (!Number.isFinite(parsed)) {
        bad.push(`${spritename} 的 ${field}="${raw}"`);
        Object.assign(values, { [field]: undefined });
        continue;
      }
      Object.assign(values, { [field]: parsed });
    }
    out.push({ spritename, values });
  }
  // 表用 Excel 改，写错格式要在第一次读时就顶回去，别让它静默变成"这格没填"
  if (bad.length > 0) throw new Error(`${csvPath} 有 ${bad.length} 个单元格不是数：${bad.slice(0, 10).join("、")}`);
  return out;
}

function diffOf(row: TableRow, disk: MonsterFlagRow, config: MonsterCensusConfig): CellChange | undefined {
  const committed = disk.humanFlags ?? {};
  const changed: Record<string, number> = {};
  const hitCommitted: string[] = [];
  // 阶段填 0 = 制作组把这一整只摘出面板体系。这时只写阶段，其余九列一并忽略：
  // 阶段 0 的行不再反推、不再进表，表上残留的旧系数不该被当成人工指令写回标识。
  const excludedByTable = row.values["阶段"] === 0;
  const fields = excludedByTable ? ["阶段"] : config.flagFields;
  for (const field of fields) {
    const value = row.values[field];
    if (value === undefined) continue;
    if (disk.flags[field] === value) continue;
    Object.assign(changed, { [field]: value });
    // 人工在表上改已提交的标识是明确指令，照改；这里只负责把"动了哪一项"报出来
    if (committed[field] !== undefined) hitCommitted.push(`${row.spritename}.${field}`);
  }
  if (Object.keys(changed).length === 0) return undefined;
  return { sourceFile: disk.sourceFile, spritename: row.spritename, flags: changed, committed: hitCommitted };
}

function parseFlags(argv: string[]): { flags: Record<string, string | boolean> } {
  const flags: Record<string, string | boolean> = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]!;
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      flags[key] = true;
      continue;
    }
    flags[key] = next;
    index += 1;
  }
  return { flags };
}

main(process.argv.slice(2));
