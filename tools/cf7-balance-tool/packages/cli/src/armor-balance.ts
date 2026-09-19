import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { XMLParser } from "fast-xml-parser";
import {
  ARMOR_BALANCE_FORMULA_FAMILY,
  ARMOR_BALANCE_FORMULA_VERSION,
  ARMOR_BALANCE_SCHEMA_VERSION,
  ARMOR_BALANCE_WORKBOOK_VERSION,
  computeArmorBalanceInputDigest,
  computeArmorRow,
  parseArmorBalancePlan,
  type ArmorBalancePlan,
  type ArmorBalancePlanRecord,
  type ArmorOutput,
} from "@cf7-balance-tool/core";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const PLAN_PATH = path.join(TOOL_ROOT, "records", "armor-balance-plan.xml");
const AUDIT_PATH = path.join(TOOL_ROOT, "records", "armor-balance-audit.xml");
const WORKBOOK_PATH = path.join(
  REPO_ROOT,
  "0.说明文件与教程",
  "武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx",
);

const SCORE_FIT_TOLERANCE = 0.05;
const ADOPTED_PRICE_BAND = { min: 0.8, max: 1.25 };
const KPOINT_PRICE_TOLERANCE = 0.05;

const parser = new XMLParser({
  ignoreAttributes: false,
  parseAttributeValue: false,
  trimValues: true,
});

interface ArmorItemStats {
  level: number;
  defence: number;
  hp: number;
  mp: number;
  damage: number;
  weaponBonus: number;
  weight: number;
  punch: number;
  magicDefence: number;
}

interface ItemSnapshot {
  itemName: string;
  sourceFile: string;
  marketPrice: number;
  itemBlock: string;
  cleanItemBlock: string;
  stats: ArmorItemStats;
  scoreOutput: ArmorOutput;
  priceOutput: ArmorOutput;
  inputDigest: string;
  sourceDigest: string;
}

interface AuditRecord extends ArmorBalancePlanRecord, ItemSnapshot {
  auditRef: string;
}

function main(): void {
  const command = process.argv[2] ?? "check";
  if (command !== "check" && command !== "sync") {
    throw new Error("用法: armor-balance.ts [check|sync]");
  }

  const plan = readPlan();
  verifyWorkbookSnapshot(plan);
  const records = buildAuditRecords(plan);
  const auditXml = buildAuditXml(plan, records);
  const syncedFiles = buildSyncedItemFiles(records);

  if (command === "sync") {
    atomicWriteTextFile(AUDIT_PATH, auditXml);
    for (const [absolutePath, source] of syncedFiles) {
      atomicWriteTextFile(absolutePath, source);
    }
    console.log(`armor-balance-sync: ${records.length} records, ${syncedFiles.size} item files`);
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
    throw new Error(`${errors.join("\n")}\n请运行 npm run armor-balance-sync`);
  }
  console.log(`armor-balance-check: ${records.length}/${records.length} records verified`);
}

function readPlan(): ArmorBalancePlan {
  const parsed = parser.parse(fs.readFileSync(PLAN_PATH, "utf8")) as Record<string, unknown>;
  return parseArmorBalancePlan(parsed);
}

function verifyWorkbookSnapshot(plan: ArmorBalancePlan): void {
  const actual = crypto.createHash("sha256").update(fs.readFileSync(WORKBOOK_PATH)).digest("hex").toUpperCase();
  if (actual !== plan.workbookSha256) {
    throw new Error(`工作簿快照漂移: plan=${plan.workbookSha256}, actual=${actual}`);
  }
}

function buildAuditRecords(plan: ArmorBalancePlan): AuditRecord[] {
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
    verifyScoreFit(record, snapshot);
    verifyGoldPrice(record, snapshot);
    verifyKPointPrice(record, snapshot, kshopCache);
    return { ...record, ...snapshot, auditRef: `armor:${record.itemName}` };
  });
}

function createItemSnapshot(record: ArmorBalancePlanRecord, itemBlock: string): ItemSnapshot {
  const cleanItemBlock = stripBalance(itemBlock);
  const parsed = parser.parse(`<root>${cleanItemBlock}</root>`) as Record<string, unknown>;
  const root = requireObject(parsed.root, "root");
  const item = requireObject(root.item, record.itemName);
  const itemName = readText(item.name, `${record.itemName}.name`);
  if (itemName !== record.itemName) {
    throw new Error(`${record.itemName}: item 块 name 漂移为 ${itemName}`);
  }
  const marketPrice = readNumber(item.price, `${record.itemName}.price`);
  const stats = readArmorStats(record.itemName, requireObject(item.data, `${record.itemName}.data`));

  const formulaBase = {
    level: stats.level,
    defence: stats.defence,
    hp: stats.hp,
    mp: stats.mp,
    damageBonus: stats.damage,
    weaponBonus: stats.weaponBonus,
    weight: stats.weight,
    punchBonus: stats.punch,
    magicDefence: stats.magicDefence,
    categoryFactor: record.category,
    damageTypeFactor: record.damageTypeFactor,
  };
  // 数值加权用 M 层（weightLayers）；价格加权用 E 层（priceLayers，只计价格产生层）。
  const scoreOutput = computeArmorRow({ ...formulaBase, extraWeightLayers: record.weightLayers });
  const priceOutput = computeArmorRow({ ...formulaBase, extraWeightLayers: record.priceLayers });

  const inputDigest = computeArmorBalanceInputDigest({
    formulaFamily: ARMOR_BALANCE_FORMULA_FAMILY,
    formulaVersion: ARMOR_BALANCE_FORMULA_VERSION,
    itemName,
    ...stats,
    weightLayers: record.weightLayers,
    priceLayers: record.priceLayers,
    category: record.category,
    damageTypeFactor: record.damageTypeFactor,
    adoptedGoldPrice: record.adoptedGoldPrice,
  });
  const sourceDigest = `sha256:${crypto
    .createHash("sha256")
    .update(normalizeNewlines(cleanItemBlock).trim(), "utf8")
    .digest("hex")}`;
  return {
    itemName,
    sourceFile: record.sourceFile,
    marketPrice,
    itemBlock,
    cleanItemBlock,
    stats,
    scoreOutput,
    priceOutput,
    inputDigest,
    sourceDigest,
  };
}

function readArmorStats(itemName: string, data: Record<string, unknown>): ArmorItemStats {
  const field = (key: string): number => readOptionalNumber(data[key], `${itemName}.data.${key}`);
  return {
    level: readNumber(data.level, `${itemName}.data.level`),
    defence: field("defence"),
    hp: field("hp"),
    mp: field("mp"),
    damage: field("damage"),
    weaponBonus: field("knifepower") + field("gunpower"),
    weight: readNumber(data.weight, `${itemName}.data.weight`),
    punch: field("punch"),
    magicDefence: sumMagicDefence(data.magicdefence, `${itemName}.data.magicdefence`),
  };
}

function sumMagicDefence(value: unknown, field: string): number {
  if (value === undefined || value === null || value === "") return 0;
  const source = requireObject(value, field);
  let total = 0;
  for (const [key, raw] of Object.entries(source)) {
    if (key === "#text") continue;
    total += readOptionalNumber(raw, `${field}.${key}`);
  }
  return total;
}

function verifyScoreFit(record: ArmorBalancePlanRecord, snapshot: ItemSnapshot): void {
  const { currentScore, weightedScore, magicDefMaxCap } = snapshot.scoreOutput;
  if (weightedScore <= 0) {
    throw new Error(`${record.itemName}: weightedScore 必须为正`);
  }
  const fit = currentScore / weightedScore;
  if (Math.abs(fit - 1) > SCORE_FIT_TOLERANCE) {
    throw new Error(
      `${record.itemName}: currentScore/weightedScore=${formatNumber(fit)} 超出 ±${SCORE_FIT_TOLERANCE} 带`,
    );
  }
  if (snapshot.stats.magicDefence > magicDefMaxCap + 1e-6) {
    throw new Error(
      `${record.itemName}: magicDefence ${formatNumber(snapshot.stats.magicDefence)} 超过上限 ${formatNumber(magicDefMaxCap)}`,
    );
  }
}

function verifyGoldPrice(record: ArmorBalancePlanRecord, snapshot: ItemSnapshot): void {
  if (snapshot.marketPrice !== record.adoptedGoldPrice) {
    throw new Error(
      `${record.itemName}: marketPrice ${snapshot.marketPrice} 与 adoptedGoldPrice ${record.adoptedGoldPrice} 不一致`,
    );
  }
  const ratio = record.adoptedGoldPrice / snapshot.priceOutput.recommendedGoldPrice;
  if (ratio < ADOPTED_PRICE_BAND.min || ratio > ADOPTED_PRICE_BAND.max) {
    throw new Error(
      `${record.itemName}: adoptedGoldPrice/recommendedGoldPrice=${formatNumber(ratio)} 超出 [${ADOPTED_PRICE_BAND.min}, ${ADOPTED_PRICE_BAND.max}] 带`,
    );
  }
}

function verifyKPointPrice(
  record: ArmorBalancePlanRecord,
  snapshot: ItemSnapshot,
  kshopCache: Map<string, Map<string, number>>,
): void {
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
    throw new Error(
      `${record.itemName}: K 点实售 ${actual} 与 expectedKPointPrice ${record.expectedKPointPrice} 不一致`,
    );
  }
  const deviation = Math.abs(actual / snapshot.priceOutput.recommendedKPointPrice - 1);
  if (deviation > KPOINT_PRICE_TOLERANCE) {
    throw new Error(
      `${record.itemName}: K 点实售对公式值偏差 ${formatNumber(deviation)} 超出 ${KPOINT_PRICE_TOLERANCE}`,
    );
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

function buildAuditXml(plan: ArmorBalancePlan, records: AuditRecord[]): string {
  const lines: string[] = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<armorBalanceAudit>",
    `  <formulaFamily>${ARMOR_BALANCE_FORMULA_FAMILY}</formulaFamily>`,
    `  <schemaVersion>${ARMOR_BALANCE_SCHEMA_VERSION}</schemaVersion>`,
    `  <formulaVersion>${ARMOR_BALANCE_FORMULA_VERSION}</formulaVersion>`,
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
      `      <priceLayers>${record.priceLayers}</priceLayers>`,
      `      <category>${formatNumber(record.category)}</category>`,
      `      <damageTypeFactor>${formatNumber(record.damageTypeFactor)}</damageTypeFactor>`,
      `      <adoptedGoldPrice>${formatNumber(record.adoptedGoldPrice)}</adoptedGoldPrice>`,
      `      <expectedKPointPrice>${record.expectedKPointPrice}</expectedKPointPrice>`,
      `      <kpointEvidenceRef>${escapeXml(record.kpointEvidenceRef)}</kpointEvidenceRef>`,
      `      <status>${record.status}</status>`,
      `      <marketPrice>${formatNumber(record.marketPrice)}</marketPrice>`,
      `      <currentScore>${formatNumber(record.scoreOutput.currentScore)}</currentScore>`,
      `      <balanceScore>${formatNumber(record.scoreOutput.balanceScore)}</balanceScore>`,
      `      <weightedScore>${formatNumber(record.scoreOutput.weightedScore)}</weightedScore>`,
      `      <magicDefAvgCap>${formatNumber(record.scoreOutput.magicDefAvgCap)}</magicDefAvgCap>`,
      `      <magicDefMaxCap>${formatNumber(record.scoreOutput.magicDefMaxCap)}</magicDefMaxCap>`,
      `      <recommendedGoldPrice>${formatNumber(record.priceOutput.recommendedGoldPrice)}</recommendedGoldPrice>`,
      `      <recommendedKPointPrice>${formatNumber(record.priceOutput.recommendedKPointPrice)}</recommendedKPointPrice>`,
      `      <inputs ${serializeAttributes({ ...record.stats })} />`,
      "      <budgetBreakdown>",
    );
    for (const entry of record.budgetBreakdown) {
      lines.push(`        <entry ${serializeAttributes({ ...entry })} />`);
    }
    lines.push(
      "      </budgetBreakdown>",
      `      <inputDigest>${record.inputDigest}</inputDigest>`,
      `      <sourceDigest>${record.sourceDigest}</sourceDigest>`,
    );
    if (record.note) lines.push(`      <note>${escapeXml(record.note)}</note>`);
    lines.push("    </record>");
  }
  lines.push("  </records>", "</armorBalanceAudit>", "");
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
    `  <formulaFamily>${ARMOR_BALANCE_FORMULA_FAMILY}</formulaFamily>`,
    `  <schemaVersion>${ARMOR_BALANCE_SCHEMA_VERSION}</schemaVersion>`,
    `  <formulaVersion>${ARMOR_BALANCE_FORMULA_VERSION}</formulaVersion>`,
    `  <workbookVersion>${ARMOR_BALANCE_WORKBOOK_VERSION}</workbookVersion>`,
    `  <weightLayers>${record.weightLayers}</weightLayers>`,
    `  <priceLayers>${record.priceLayers}</priceLayers>`,
    `  <category>${formatNumber(record.category)}</category>`,
    `  <damageTypeFactor>${formatNumber(record.damageTypeFactor)}</damageTypeFactor>`,
    `  <currentScore>${formatNumber(record.scoreOutput.currentScore)}</currentScore>`,
    `  <balanceScore>${formatNumber(record.scoreOutput.balanceScore)}</balanceScore>`,
    `  <weightedScore>${formatNumber(record.scoreOutput.weightedScore)}</weightedScore>`,
    `  <recommendedGoldPrice>${formatNumber(record.priceOutput.recommendedGoldPrice)}</recommendedGoldPrice>`,
    `  <recommendedKPointPrice>${formatNumber(record.priceOutput.recommendedKPointPrice)}</recommendedKPointPrice>`,
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
  const balanceIndent = `${itemIndent}  `;
  const indented = balance.split("\n").map((line) => `${balanceIndent}${line}`).join("\n");
  return cleanBlock.replace(/\r?\n[ \t]*<\/item>\s*$/, `\n${indented}\n${itemIndent}</item>`);
}

function atomicWriteTextFile(target: string, contents: string): void {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temp = path.join(
    path.dirname(target),
    `.${path.basename(target)}.armor-balance-sync-${process.pid}-${Date.now()}.tmp`,
  );
  try {
    fs.writeFileSync(temp, contents, "utf8");
    fs.renameSync(temp, target);
  } finally {
    if (fs.existsSync(temp)) fs.rmSync(temp, { force: true });
  }
}

function serializeAttributes(source: Record<string, unknown>): string {
  return Object.entries(source)
    .map(([key, value]) => `${key}="${escapeXml(typeof value === "number" ? formatNumber(value) : String(value))}"`)
    .join(" ");
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
