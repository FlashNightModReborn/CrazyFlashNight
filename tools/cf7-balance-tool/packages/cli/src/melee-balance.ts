import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { XMLParser } from "fast-xml-parser";
import { computeMeleeRow, type MeleeInput, type MeleeOutput } from "@cf7-balance-tool/core";

const FORMULA_FAMILY = "melee";
const SCHEMA_VERSION = 1;
const FORMULA_VERSION = 1;
const WORKBOOK_VERSION = 1;
const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const PLAN_PATH = path.join(TOOL_ROOT, "records", "melee-balance-plan.xml");
const AUDIT_PATH = path.join(TOOL_ROOT, "records", "melee-balance-audit.xml");
const WORKBOOK_PATH = path.join(
  REPO_ROOT,
  "0.说明文件与教程",
  "武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx",
);

const SHARPNESS_FIT_TOLERANCE = 0.05;
const ADOPTED_PRICE_BAND = { min: 0.8, max: 1.25 };
const KPOINT_PRICE_TOLERANCE = 0.05;

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "",
  parseAttributeValue: false,
  trimValues: true,
});

interface PlanRecord {
  itemName: string;
  sourceFile: string;
  weightLayers: number;
  damageTypeFactor: number;
  categoryFactor: number;
  balanceMode: "formula" | "exception";
  status: "confirmed" | "unresolved" | "proposed";
  adoptedGoldPrice?: number;
  expectedKPointPrice?: number;
  kpointEvidenceRef?: string;
  exceptionCode?: string;
  note?: string;
}

interface Plan {
  workbookVersion: number;
  workbookSha256: string;
  coverageFiles: string[];
  records: PlanRecord[];
}

interface MeleeItemStats {
  level: number;
  weight: number;
  sharpness: number;
}

interface ItemSnapshot {
  itemName: string;
  sourceFile: string;
  marketPrice: number;
  cleanItemBlock: string;
  stats: MeleeItemStats;
  output: MeleeOutput;
  inputDigest: string;
  sourceDigest: string;
}

interface AuditRecord extends PlanRecord, ItemSnapshot {
  auditRef: string;
}

function main(): void {
  const command = process.argv[2] ?? "check";
  if (command !== "check" && command !== "sync") {
    throw new Error("用法: melee-balance.ts [check|sync]");
  }

  const plan = readPlan();
  verifyWorkbookSnapshot(plan);
  const records = buildAuditRecords(plan);
  verifyCoverage(plan, records);
  const auditXml = buildAuditXml(plan, records);
  const syncedFiles = buildSyncedItemFiles(records);

  if (command === "sync") {
    fs.writeFileSync(AUDIT_PATH, auditXml, "utf8");
    for (const [absolutePath, source] of syncedFiles) {
      fs.writeFileSync(absolutePath, source, "utf8");
    }
    console.log(`melee-balance-sync: ${records.length} records, ${syncedFiles.size} item files`);
    return;
  }

  const errors: string[] = [];
  const currentAudit = fs.existsSync(AUDIT_PATH)
    ? normalizeNewlines(fs.readFileSync(AUDIT_PATH, "utf8"))
    : "";
  if (currentAudit !== normalizeNewlines(auditXml)) {
    errors.push("审计账本不是 plan 与当前物品数据的最新派生结果");
  }
  for (const [absolutePath, expected] of syncedFiles) {
    const current = normalizeNewlines(fs.readFileSync(absolutePath, "utf8"));
    if (current !== normalizeNewlines(expected)) {
      errors.push(`${path.relative(REPO_ROOT, absolutePath)} 的 <balance> 摘要已漂移`);
    }
  }
  if (errors.length > 0) {
    throw new Error(`${errors.join("\n")}\n请运行 npm run melee-balance-sync`);
  }
  console.log(`melee-balance-check: ${records.length}/${records.length} records verified`);
}

function readPlan(): Plan {
  const parsed = parser.parse(fs.readFileSync(PLAN_PATH, "utf8")) as Record<string, unknown>;
  const root = requireObject(parsed.meleeBalancePlan, "meleeBalancePlan");
  if (String(root.formulaFamily ?? "") !== FORMULA_FAMILY) {
    throw new Error("meleeBalancePlan.formulaFamily 必须为 melee");
  }
  if (readNumber(root.schemaVersion, "schemaVersion") !== SCHEMA_VERSION) {
    throw new Error("meleeBalancePlan.schemaVersion 不受支持");
  }
  if (readNumber(root.formulaVersion, "formulaVersion") !== FORMULA_VERSION) {
    throw new Error("meleeBalancePlan.formulaVersion 不受支持");
  }
  const workbookVersion = readNumber(root.workbookVersion, "workbookVersion");
  const workbookSha256 = String(root.workbookSha256 ?? "");
  if (!/^[0-9A-F]{64}$/.test(workbookSha256)) {
    throw new Error("workbookSha256 必须是大写 SHA-256");
  }
  const coverageContainer = root.coverageFiles;
  const coverageFiles =
    coverageContainer === undefined || coverageContainer === null || coverageContainer === ""
      ? []
      : asArray(requireObject(coverageContainer, "coverageFiles").file).map((entry) =>
          readText(entry, "coverageFiles.file"),
        );
  const rawRecords = asArray(requireObject(root.records, "records").record);
  const records = rawRecords.map((raw, index) => parsePlanRecord(raw, index));
  const identities = new Set<string>();
  for (const record of records) {
    if (identities.has(record.itemName)) throw new Error(`重复的近战记录: ${record.itemName}`);
    identities.add(record.itemName);
  }
  return { workbookVersion, workbookSha256, coverageFiles, records };
}

function parsePlanRecord(raw: unknown, index: number): PlanRecord {
  const source = requireObject(raw, `records.record[${index}]`);
  const balanceMode = String(source.balanceMode ?? "formula") as PlanRecord["balanceMode"];
  const status = String(source.status ?? "") as PlanRecord["status"];
  if (balanceMode !== "formula" && balanceMode !== "exception") {
    throw new Error(`records.record[${index}].balanceMode 无效`);
  }
  if (status !== "confirmed" && status !== "unresolved" && status !== "proposed") {
    throw new Error(`records.record[${index}].status 无效`);
  }
  const record: PlanRecord = {
    itemName: readText(source.itemName, `records.record[${index}].itemName`),
    sourceFile: readText(source.sourceFile, `records.record[${index}].sourceFile`),
    weightLayers: readNumber(source.weightLayers ?? 0, `records.record[${index}].weightLayers`),
    damageTypeFactor: readNumber(
      source.damageTypeFactor ?? 1,
      `records.record[${index}].damageTypeFactor`,
    ),
    categoryFactor: readNumber(source.categoryFactor ?? 1, `records.record[${index}].categoryFactor`),
    balanceMode,
    status,
  };
  if (source.adoptedGoldPrice !== undefined) {
    record.adoptedGoldPrice = readNumber(source.adoptedGoldPrice, `${record.itemName}.adoptedGoldPrice`);
  }
  if (source.expectedKPointPrice !== undefined) {
    record.expectedKPointPrice = readNumber(
      source.expectedKPointPrice,
      `${record.itemName}.expectedKPointPrice`,
    );
  }
  if (source.kpointEvidenceRef !== undefined) record.kpointEvidenceRef = String(source.kpointEvidenceRef);
  if (source.exceptionCode !== undefined) record.exceptionCode = String(source.exceptionCode);
  if (source.note !== undefined) record.note = String(source.note);
  if (record.balanceMode === "exception" && !record.exceptionCode) {
    throw new Error(`${record.itemName}: exception 记录缺少 exceptionCode`);
  }
  if ((record.expectedKPointPrice === undefined) !== (record.kpointEvidenceRef === undefined)) {
    throw new Error(`${record.itemName}: expectedKPointPrice 与 kpointEvidenceRef 必须成对出现`);
  }
  return record;
}

function verifyWorkbookSnapshot(plan: Plan): void {
  const actual = crypto.createHash("sha256").update(fs.readFileSync(WORKBOOK_PATH)).digest("hex").toUpperCase();
  if (actual !== plan.workbookSha256) {
    throw new Error(`工作簿快照漂移: plan=${plan.workbookSha256}, actual=${actual}`);
  }
}

function buildAuditRecords(plan: Plan): AuditRecord[] {
  const fileCache = new Map<string, Map<string, string>>();
  const kshopCache = new Map<string, Map<string, number>>();
  return plan.records.map((record) => {
    const absolutePath = path.join(REPO_ROOT, record.sourceFile);
    let blocks = fileCache.get(absolutePath);
    if (!blocks) {
      blocks = indexItemBlocks(fs.readFileSync(absolutePath, "utf8"), record.sourceFile);
      fileCache.set(absolutePath, blocks);
    }
    const itemBlock = blocks.get(record.itemName);
    if (!itemBlock) throw new Error(`${record.sourceFile}: 找不到 ${record.itemName}`);
    const snapshot = createItemSnapshot(record, itemBlock);
    if (record.balanceMode === "formula") {
      verifySharpnessFit(record, snapshot);
      verifyGoldPrice(record, snapshot);
      verifyKPointPrice(record, snapshot, kshopCache);
    }
    return { ...record, ...snapshot, auditRef: `melee:${record.itemName}` };
  });
}

function createItemSnapshot(record: PlanRecord, itemBlock: string): ItemSnapshot {
  const cleanItemBlock = stripBalance(itemBlock);
  const parsed = parser.parse(`<root>${cleanItemBlock}</root>`) as Record<string, unknown>;
  const root = requireObject(parsed.root, "root");
  const item = requireObject(root.item, record.itemName);
  const itemName = readText(item.name, `${record.itemName}.name`);
  const marketPrice = readNumber(item.price, `${record.itemName}.price`);
  const data = requireObject(item.data, `${record.itemName}.data`);
  const stats: MeleeItemStats = {
    level: readNumber(data.level, `${record.itemName}.data.level`),
    weight: readNumber(data.weight, `${record.itemName}.data.weight`),
    sharpness: readNumber(data.power, `${record.itemName}.data.power`),
  };
  const formulaInput: MeleeInput = {
    level: stats.level,
    weight: stats.weight,
    damageTypeFactor: record.damageTypeFactor,
    weightLayers: record.weightLayers,
    categoryFactor: record.categoryFactor,
  };
  const output = computeMeleeRow(formulaInput);
  const inputDigest = `fnv1a32:${fnv1a32Utf16(
    JSON.stringify({
      formulaFamily: FORMULA_FAMILY,
      formulaVersion: FORMULA_VERSION,
      itemName,
      ...stats,
      ...formulaInput,
      marketPrice,
      balanceMode: record.balanceMode,
      adoptedGoldPrice: record.adoptedGoldPrice ?? null,
    }),
  )}`;
  const sourceDigest = `sha256:${crypto
    .createHash("sha256")
    .update(normalizeNewlines(cleanItemBlock).trim(), "utf8")
    .digest("hex")}`;
  return { itemName, sourceFile: record.sourceFile, marketPrice, cleanItemBlock, stats, output, inputDigest, sourceDigest };
}

function verifySharpnessFit(record: PlanRecord, snapshot: ItemSnapshot): void {
  const recommended = snapshot.output.recommendedSharpness;
  if (recommended <= 0) {
    throw new Error(`${record.itemName}: recommendedSharpness 必须为正`);
  }
  const residual = snapshot.stats.sharpness / recommended - 1;
  if (Math.abs(residual) > SHARPNESS_FIT_TOLERANCE) {
    throw new Error(
      `${record.itemName}: sharpness 残差 ${formatNumber(residual * 100)}% 超出 ±${SHARPNESS_FIT_TOLERANCE * 100}% 带`,
    );
  }
}

function verifyGoldPrice(record: PlanRecord, snapshot: ItemSnapshot): void {
  const adopted = record.adoptedGoldPrice ?? snapshot.marketPrice;
  if (adopted !== snapshot.marketPrice) {
    throw new Error(`${record.itemName}: adoptedGoldPrice 与市场价不一致`);
  }
  const recommended = snapshot.output.recommendedGoldPrice;
  if (recommended <= 0) return;
  const ratio = adopted / recommended;
  if (ratio < ADOPTED_PRICE_BAND.min || ratio > ADOPTED_PRICE_BAND.max) {
    throw new Error(
      `${record.itemName}: adoptedGoldPrice/recommendedGoldPrice=${formatNumber(ratio)} 超出 [${ADOPTED_PRICE_BAND.min}, ${ADOPTED_PRICE_BAND.max}] 带`,
    );
  }
}

function verifyKPointPrice(
  record: PlanRecord,
  snapshot: ItemSnapshot,
  kshopCache: Map<string, Map<string, number>>,
): void {
  if (record.kpointEvidenceRef === undefined) return;
  const evidencePath = path.join(REPO_ROOT, record.kpointEvidenceRef);
  let prices = kshopCache.get(evidencePath);
  if (!prices) {
    prices = readKshopPrices(evidencePath, record.kpointEvidenceRef);
    kshopCache.set(evidencePath, prices);
  }
  const actual = prices.get(record.itemName);
  if (actual === undefined) {
    throw new Error(`${record.kpointEvidenceRef}: 找不到 ${record.itemName} 的 K 点售价`);
  }
  if (actual !== record.expectedKPointPrice) {
    throw new Error(`${record.itemName}: K 点实售 ${actual} 与 expectedKPointPrice ${record.expectedKPointPrice} 不一致`);
  }
  const deviation = Math.abs(actual / snapshot.output.recommendedKPointPrice - 1);
  if (deviation > KPOINT_PRICE_TOLERANCE) {
    throw new Error(`${record.itemName}: K 点实售对公式值偏差 ${formatNumber(deviation)} 超出 ${KPOINT_PRICE_TOLERANCE}`);
  }
}

function readKshopPrices(absolutePath: string, evidenceRef: string): Map<string, number> {
  const parsed = JSON.parse(fs.readFileSync(absolutePath, "utf8")) as unknown;
  if (!Array.isArray(parsed)) throw new Error(`${evidenceRef}: 需要条目数组`);
  const result = new Map<string, number>();
  for (const [index, raw] of parsed.entries()) {
    const entry = requireObject(raw, `${evidenceRef}[${index}]`);
    const itemName = readText(entry.item, `${evidenceRef}[${index}].item`);
    const price = readNumber(entry.price, `${evidenceRef}[${index}].price`);
    if (result.has(itemName)) throw new Error(`${evidenceRef}: 重复条目 ${itemName}`);
    result.set(itemName, price);
  }
  return result;
}

function verifyCoverage(plan: Plan, records: AuditRecord[]): void {
  const planned = new Set(records.map((record) => `${record.sourceFile}\u0000${record.itemName}`));
  for (const sourceFile of plan.coverageFiles) {
    const absolutePath = path.join(REPO_ROOT, sourceFile);
    const blocks = indexItemBlocks(fs.readFileSync(absolutePath, "utf8"), sourceFile);
    for (const itemName of blocks.keys()) {
      if (!planned.has(`${sourceFile}\u0000${itemName}`)) {
        throw new Error(`${sourceFile}: ${itemName} 未进入近战审计计划`);
      }
    }
  }
}

function buildAuditXml(plan: Plan, records: AuditRecord[]): string {
  const lines: string[] = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<meleeBalanceAudit>",
    `  <formulaFamily>${FORMULA_FAMILY}</formulaFamily>`,
    `  <schemaVersion>${SCHEMA_VERSION}</schemaVersion>`,
    `  <formulaVersion>${FORMULA_VERSION}</formulaVersion>`,
    `  <workbookVersion>${plan.workbookVersion}</workbookVersion>`,
    `  <workbookSha256>${plan.workbookSha256}</workbookSha256>`,
    "  <records>",
  ];
  for (const record of records) {
    lines.push(
      "    <record>",
      `      <auditRef>${escapeXml(record.auditRef)}</auditRef>`,
      `      <itemName>${escapeXml(record.itemName)}</itemName>`,
      `      <sourceFile>${escapeXml(record.sourceFile)}</sourceFile>`,
      `      <weightLayers>${record.weightLayers}</weightLayers>`,
      `      <damageTypeFactor>${formatNumber(record.damageTypeFactor)}</damageTypeFactor>`,
      `      <categoryFactor>${formatNumber(record.categoryFactor)}</categoryFactor>`,
      `      <balanceMode>${record.balanceMode}</balanceMode>`,
      `      <status>${record.status}</status>`,
      `      <marketPrice>${formatNumber(record.marketPrice)}</marketPrice>`,
      `      <recommendedSharpness>${formatNumber(record.output.recommendedSharpness)}</recommendedSharpness>`,
      `      <sharpnessResidual>${formatNumber(record.stats.sharpness / record.output.recommendedSharpness - 1)}</sharpnessResidual>`,
      `      <recommendedGoldPrice>${formatNumber(record.output.recommendedGoldPrice)}</recommendedGoldPrice>`,
      `      <recommendedKPointPrice>${formatNumber(record.output.recommendedKPointPrice)}</recommendedKPointPrice>`,
      `      <inputs ${serializeAttributes({ ...record.stats })} />`,
      `      <inputDigest>${record.inputDigest}</inputDigest>`,
      `      <sourceDigest>${record.sourceDigest}</sourceDigest>`,
    );
    if (record.exceptionCode) lines.push(`      <exceptionCode>${escapeXml(record.exceptionCode)}</exceptionCode>`);
    if (record.note) lines.push(`      <note>${escapeXml(record.note)}</note>`);
    lines.push("    </record>");
  }
  lines.push("  </records>", "</meleeBalanceAudit>", "");
  return lines.join("\n");
}

function buildSyncedItemFiles(records: AuditRecord[]): Map<string, string> {
  const byFile = new Map<string, Map<string, AuditRecord>>();
  for (const record of records) {
    let items = byFile.get(record.sourceFile);
    if (!items) {
      items = new Map<string, AuditRecord>();
      byFile.set(record.sourceFile, items);
    }
    items.set(record.itemName, record);
  }
  const result = new Map<string, string>();
  for (const [sourceFile, fileRecords] of byFile) {
    const absolutePath = path.join(REPO_ROOT, sourceFile);
    const source = fs.readFileSync(absolutePath, "utf8");
    const itemRegex = /(^[ \t]*<item(?:\s[^>]*)?>[\s\S]*?^[ \t]*<\/item>)/gm;
    const replaced = source.replace(itemRegex, (block) => {
      const itemName = extractItemName(block, sourceFile);
      const record = fileRecords.get(itemName);
      if (!record) return block;
      return insertBalance(stripBalance(block), buildInlineBalance(record));
    });
    result.set(absolutePath, replaced);
  }
  return result;
}

function buildInlineBalance(record: AuditRecord): string {
  const lines = [
    "<balance>",
    `  <formulaFamily>${FORMULA_FAMILY}</formulaFamily>`,
    `  <schemaVersion>${SCHEMA_VERSION}</schemaVersion>`,
    `  <formulaVersion>${FORMULA_VERSION}</formulaVersion>`,
    `  <workbookVersion>${WORKBOOK_VERSION}</workbookVersion>`,
    `  <weightLayers>${record.weightLayers}</weightLayers>`,
    `  <damageTypeFactor>${formatNumber(record.damageTypeFactor)}</damageTypeFactor>`,
    `  <categoryFactor>${formatNumber(record.categoryFactor)}</categoryFactor>`,
    `  <balanceMode>${record.balanceMode}</balanceMode>`,
    `  <recommendedSharpness>${formatNumber(record.output.recommendedSharpness)}</recommendedSharpness>`,
    `  <recommendedGoldPrice>${formatNumber(record.output.recommendedGoldPrice)}</recommendedGoldPrice>`,
    `  <recommendedKPointPrice>${formatNumber(record.output.recommendedKPointPrice)}</recommendedKPointPrice>`,
    `  <marketPrice>${formatNumber(record.marketPrice)}</marketPrice>`,
    `  <status>${record.status}</status>`,
    `  <inputDigest>${record.inputDigest}</inputDigest>`,
    `  <sourceDigest>${record.sourceDigest}</sourceDigest>`,
    `  <auditRef>${escapeXml(record.auditRef)}</auditRef>`,
    "</balance>",
  ];
  return lines.join("\n");
}

function indexItemBlocks(source: string, sourceFile: string): Map<string, string> {
  const result = new Map<string, string>();
  const itemRegex = /(^[ \t]*<item(?:\s[^>]*)?>[\s\S]*?^[ \t]*<\/item>)/gm;
  for (const match of source.matchAll(itemRegex)) {
    const block = match[0];
    const itemName = extractItemName(block, sourceFile);
    if (result.has(itemName)) throw new Error(`${sourceFile}: 重复 item ${itemName}`);
    result.set(itemName, block);
  }
  return result;
}

function extractItemName(block: string, sourceFile: string): string {
  const match = block.match(/<name>([\s\S]*?)<\/name>/);
  if (!match) throw new Error(`${sourceFile}: item 缺少 name`);
  return decodeXml(match[1]!.trim());
}

function stripBalance(block: string): string {
  return block.replace(/\r?\n[ \t]*<balance>[\s\S]*?<\/balance>/g, "");
}

function insertBalance(cleanBlock: string, balance: string): string {
  const match = cleanBlock.match(/\r?\n([ \t]*)<\/item>\s*$/);
  if (!match) throw new Error("item block 缺少结束标签");
  const itemIndent = match[1];
  const indented = balance
    .split("\n")
    .map((line) => `${itemIndent}  ${line}`)
    .join("\n");
  return cleanBlock.replace(/\r?\n[ \t]*<\/item>\s*$/, `\n${indented}\n${itemIndent}</item>`);
}

function serializeAttributes(source: Record<string, unknown>): string {
  return Object.entries(source)
    .map(([key, value]) => `${key}="${escapeXml(typeof value === "number" ? formatNumber(value) : String(value))}"`)
    .join(" ");
}

function fnv1a32Utf16(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

function asArray<T>(value: T | T[] | undefined): T[] {
  if (value === undefined) return [];
  return Array.isArray(value) ? value : [value];
}

function formatNumber(value: number): string {
  if (!Number.isFinite(value)) throw new Error(`非有限数值: ${value}`);
  const rounded = Math.round(value * 1_000_000) / 1_000_000;
  return String(Object.is(rounded, -0) ? 0 : rounded);
}

function readOptionalNumber(value: unknown, field: string): number {
  if (value === undefined || value === null || value === "") return 0;
  return readNumber(value, field);
}

function readNumber(value: unknown, field: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) throw new Error(`${field}: 需要有限数值`);
  return parsed;
}

function readText(value: unknown, field: string): string {
  const result = String(value ?? "").trim();
  if (!result) throw new Error(`${field}: 需要非空文本`);
  return result;
}

function requireObject(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${field}: 需要对象`);
  }
  return value as Record<string, unknown>;
}

function normalizeNewlines(value: string): string {
  return value.replace(/\r\n/g, "\n");
}

function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function decodeXml(value: string): string {
  return value
    .replace(/&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&gt;/g, ">")
    .replace(/&lt;/g, "<")
    .replace(/&amp;/g, "&");
}

main();
