import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { XMLParser } from "fast-xml-parser";
import {
  computePotionV2Row,
  type PotionV2Input,
  type PotionV2Output,
} from "@cf7-balance-tool/core";

const FORMULA_FAMILY = "potion";
const SCHEMA_VERSION = 1;
const FORMULA_VERSION = 2;
const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const PLAN_PATH = path.join(TOOL_ROOT, "records", "potion-balance-plan.xml");
const AUDIT_PATH = path.join(TOOL_ROOT, "records", "potion-balance-audit.xml");
const WORKBOOK_PATH = path.join(
  REPO_ROOT,
  "0.说明文件与教程",
  "武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx",
);

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "",
  parseAttributeValue: false,
  trimValues: true,
});

interface PlanRecord {
  itemName: string;
  sourceFile: string;
  sourceLevel: number;
  domain: string;
  balanceMode: "formula" | "exception";
  status: "proposed" | "runtime-test-pending";
  exceptionCode?: string;
  note?: string;
}

interface Plan {
  authorityStatus: string;
  sourceWorkbookSha256: string;
  records: PlanRecord[];
}

interface ItemSnapshot {
  itemName: string;
  sourceFile: string;
  marketPrice: number;
  itemBlock: string;
  cleanItemBlock: string;
  input: PotionV2Input;
  output: PotionV2Output;
  inputDigest: string;
  sourceDigest: string;
  hasUnsupportedFormulaEffect: boolean;
}

interface AuditRecord extends PlanRecord, ItemSnapshot {
  auditRef: string;
}

function main(): void {
  const command = process.argv[2] ?? "check";
  if (command !== "check" && command !== "sync") {
    throw new Error("用法: potion-balance.ts [check|sync]");
  }

  const plan = readPlan();
  verifyWorkbookSnapshot(plan);
  const records = buildAuditRecords(plan);
  verifyCoverage(plan, records);
  const auditXml = buildAuditXml(plan, records);
  const syncedFiles = buildSyncedItemFiles(plan, records);

  if (command === "sync") {
    fs.writeFileSync(AUDIT_PATH, auditXml, "utf8");
    for (const [absolutePath, source] of syncedFiles) {
      fs.writeFileSync(absolutePath, source, "utf8");
    }
    console.log(`potion-balance-sync: ${records.length} records, ${syncedFiles.size} item files`);
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
    throw new Error(`${errors.join("\n")}\n请运行 npm run potion-balance-sync`);
  }
  console.log(`potion-balance-check: ${records.length}/${records.length} records verified`);
}

function readPlan(): Plan {
  const parsed = parser.parse(fs.readFileSync(PLAN_PATH, "utf8")) as Record<string, unknown>;
  const root = requireObject(parsed.potionBalancePlan, "potionBalancePlan");
  const recordsContainer = requireObject(root.records, "potionBalancePlan.records");
  const rawRecords = asArray(recordsContainer.record);
  const records = rawRecords.map((raw, index) => parsePlanRecord(raw, index));

  const formulaFamily = String(root.formulaFamily ?? "");
  const schemaVersion = readNumber(root.schemaVersion, "schemaVersion");
  const formulaVersion = readNumber(root.formulaVersion, "formulaVersion");
  if (formulaFamily !== FORMULA_FAMILY || schemaVersion !== SCHEMA_VERSION || formulaVersion !== FORMULA_VERSION) {
    throw new Error("potionBalancePlan 的公式族或版本不受当前实现支持");
  }

  const authorityStatus = String(root.authorityStatus ?? "");
  const sourceWorkbookSha256 = String(root.sourceWorkbookSha256 ?? "");
  if (authorityStatus !== "workbook-registration-pending") {
    throw new Error("当前只允许显式的 workbook-registration-pending 提案状态");
  }
  if (!/^[0-9A-F]{64}$/.test(sourceWorkbookSha256)) {
    throw new Error("sourceWorkbookSha256 必须是大写 SHA-256");
  }

  const identities = new Set<string>();
  for (const record of records) {
    if (identities.has(record.itemName)) throw new Error(`重复的药剂记录: ${record.itemName}`);
    identities.add(record.itemName);
  }
  return { authorityStatus, sourceWorkbookSha256, records };
}

function parsePlanRecord(raw: unknown, index: number): PlanRecord {
  const source = requireObject(raw, `records.record[${index}]`);
  const balanceMode = String(source.balanceMode ?? "") as PlanRecord["balanceMode"];
  const status = String(source.status ?? "") as PlanRecord["status"];
  if (balanceMode !== "formula" && balanceMode !== "exception") {
    throw new Error(`records.record[${index}].balanceMode 无效`);
  }
  if (status !== "proposed" && status !== "runtime-test-pending") {
    throw new Error(`records.record[${index}].status 无效`);
  }

  const record: PlanRecord = {
    itemName: readText(source.itemName, `records.record[${index}].itemName`),
    sourceFile: readText(source.sourceFile, `records.record[${index}].sourceFile`),
    sourceLevel: readNumber(source.sourceLevel, `records.record[${index}].sourceLevel`),
    domain: readText(source.domain, `records.record[${index}].domain`),
    balanceMode,
    status,
  };
  if (source.exceptionCode !== undefined) record.exceptionCode = String(source.exceptionCode);
  if (source.note !== undefined) record.note = String(source.note);
  if (!Number.isInteger(record.sourceLevel) || record.sourceLevel < 0) {
    throw new Error(`${record.itemName}: sourceLevel 必须是非负整数`);
  }
  if (record.balanceMode === "exception" && !record.exceptionCode) {
    throw new Error(`${record.itemName}: exception 记录缺少 exceptionCode`);
  }
  return record;
}

function verifyWorkbookSnapshot(plan: Plan): void {
  const actual = crypto.createHash("sha256").update(fs.readFileSync(WORKBOOK_PATH)).digest("hex").toUpperCase();
  if (actual !== plan.sourceWorkbookSha256) {
    throw new Error(`工作簿快照漂移: plan=${plan.sourceWorkbookSha256}, actual=${actual}`);
  }
}

function buildAuditRecords(plan: Plan): AuditRecord[] {
  const fileCache = new Map<string, Map<string, string>>();
  return plan.records.map((record) => {
    const absolutePath = path.join(REPO_ROOT, "data", "items", record.sourceFile);
    let blocks = fileCache.get(absolutePath);
    if (!blocks) {
      blocks = indexItemBlocks(fs.readFileSync(absolutePath, "utf8"), record.sourceFile);
      fileCache.set(absolutePath, blocks);
    }
    const itemBlock = blocks.get(record.itemName);
    if (!itemBlock) throw new Error(`${record.sourceFile}: 找不到 ${record.itemName}`);
    const snapshot = createItemSnapshot(record, itemBlock);
    if (record.balanceMode === "formula" && snapshot.hasUnsupportedFormulaEffect) {
      throw new Error(`${record.itemName}: formula 记录包含尚未定价的特殊效果`);
    }
    if (record.balanceMode === "formula" && snapshot.output.currentValue > snapshot.output.valueCap + 1e-6) {
      throw new Error(
        `${record.itemName}: currentValue ${formatNumber(snapshot.output.currentValue)} 超过 cap ${snapshot.output.valueCap}`,
      );
    }
    return { ...record, ...snapshot, auditRef: `potion:${record.itemName}` };
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
  const effectsContainer = requireObject(data.effects, `${record.itemName}.effects`);
  const effects = asArray(effectsContainer.effect).map((effect, index) =>
    requireObject(effect, `${record.itemName}.effect[${index}]`),
  );
  const { input, hasUnsupportedFormulaEffect } = deriveFormulaInput(record.sourceLevel, effects);
  const output = computePotionV2Row(input);
  const canonical = JSON.stringify({
    formulaFamily: FORMULA_FAMILY,
    formulaVersion: FORMULA_VERSION,
    itemName,
    sourceLevel: record.sourceLevel,
    domain: record.domain,
    balanceMode: record.balanceMode,
    marketPrice,
    input,
  });
  const inputDigest = `fnv1a32:${fnv1a32Utf16(canonical)}`;
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
    input,
    output,
    inputDigest,
    sourceDigest,
    hasUnsupportedFormulaEffect,
  };
}

function deriveFormulaInput(sourceLevel: number, effects: Array<Record<string, unknown>>): {
  input: PotionV2Input;
  hasUnsupportedFormulaEffect: boolean;
} {
  const input: PotionV2Input = {
    instantHp: 0,
    instantMp: 0,
    regenHp: 0,
    regenMp: 0,
    regenFrames: 0,
    playerLevel: sourceLevel,
    isGroup: 0,
    purifyValue: 0,
    toxicity: 0,
    buffHp: 0,
    buffMp: 0,
    buffDefence: 0,
    buffMagicResist: 0,
    buffDamage: 0,
    buffPunch: 0,
    buffSpeed: 0,
    buffToughness: 0,
    buffDuration: 0,
  };
  let hasUnsupportedFormulaEffect = false;

  for (const effect of effects) {
    const type = String(effect.type ?? "");
    switch (type) {
      case "heal":
        input.instantHp += readOptionalNumber(effect.hp);
        input.instantMp += readOptionalNumber(effect.mp);
        if (String(effect.target ?? "self") === "group") input.isGroup = 1;
        break;
      case "regen": {
        if (String(effect.mode ?? "perTick") !== "total") {
          hasUnsupportedFormulaEffect = true;
          break;
        }
        input.regenHp += readOptionalNumber(effect.hp);
        input.regenMp += readOptionalNumber(effect.mp);
        const duration = readNumber(effect.duration, "regen.duration");
        if (input.regenFrames !== 0 && input.regenFrames !== duration) {
          hasUnsupportedFormulaEffect = true;
        }
        input.regenFrames = Math.max(input.regenFrames, duration);
        break;
      }
      case "purify":
        input.purifyValue += readOptionalNumber(effect.value);
        break;
      case "state":
        if (String(effect.key ?? "") === "淬毒") input.toxicity += readOptionalNumber(effect.value);
        else hasUnsupportedFormulaEffect = true;
        break;
      case "buff": {
        const property = String(effect.property ?? "");
        const value = readOptionalNumber(effect.value);
        setBuffDuration(input, readOptionalNumber(effect.duration));
        if (property === "hp满血值") input.buffHp += value;
        else if (property === "mp满血值") input.buffMp += value;
        else if (property === "防御力") input.buffDefence += value;
        else if (property === "伤害加成") input.buffDamage += value;
        else if (property === "空手攻击力") input.buffPunch += value;
        else if (property === "行走X速度") input.buffSpeed += (value - 1) * 50;
        else hasUnsupportedFormulaEffect = true;
        break;
      }
      case "resistanceBuff":
        input.buffMagicResist += readOptionalNumber(effect.value) * 2;
        setBuffDuration(input, readOptionalNumber(effect.duration));
        break;
      case "toughnessBuff":
        input.buffToughness += readOptionalNumber(effect.value);
        setBuffDuration(input, readOptionalNumber(effect.duration));
        break;
      case "buffDomain":
      case "playEffect":
      case "message":
        break;
      case "restoreToughness":
      case "grantItem":
      case "global":
        hasUnsupportedFormulaEffect = true;
        break;
      default:
        hasUnsupportedFormulaEffect = true;
        break;
    }
  }
  return { input, hasUnsupportedFormulaEffect };
}

function setBuffDuration(input: PotionV2Input, duration: number): void {
  if (duration <= 0) return;
  if (input.buffDuration !== 0 && input.buffDuration !== duration) {
    throw new Error(`同一物品的 Buff 持续时间不一致: ${input.buffDuration}/${duration}`);
  }
  input.buffDuration = duration;
}

function verifyCoverage(plan: Plan, records: AuditRecord[]): void {
  const planned = new Set(records.map((record) => `${record.sourceFile}\u0000${record.itemName}`));
  const sourceFiles = [...new Set(plan.records.map((record) => record.sourceFile))];
  for (const sourceFile of sourceFiles) {
    const absolutePath = path.join(REPO_ROOT, "data", "items", sourceFile);
    const blocks = indexItemBlocks(fs.readFileSync(absolutePath, "utf8"), sourceFile);
    for (const itemName of blocks.keys()) {
      if (!planned.has(`${sourceFile}\u0000${itemName}`)) {
        throw new Error(`${sourceFile}: ${itemName} 未进入全量药剂审计计划`);
      }
    }
  }
}

function buildAuditXml(plan: Plan, records: AuditRecord[]): string {
  const lines: string[] = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<potionBalanceAudit>",
    `  <formulaFamily>${FORMULA_FAMILY}</formulaFamily>`,
    `  <schemaVersion>${SCHEMA_VERSION}</schemaVersion>`,
    `  <formulaVersion>${FORMULA_VERSION}</formulaVersion>`,
    `  <authorityStatus>${escapeXml(plan.authorityStatus)}</authorityStatus>`,
    `  <sourceWorkbookSha256>${plan.sourceWorkbookSha256}</sourceWorkbookSha256>`,
    "  <records>",
  ];
  for (const record of records) {
    lines.push(
      "    <record>",
      `      <auditRef>${escapeXml(record.auditRef)}</auditRef>`,
      `      <itemName>${escapeXml(record.itemName)}</itemName>`,
      `      <sourceFile>${escapeXml(record.sourceFile)}</sourceFile>`,
      `      <sourceLevel>${record.sourceLevel}</sourceLevel>`,
      `      <domain>${escapeXml(record.domain)}</domain>`,
      `      <balanceMode>${record.balanceMode}</balanceMode>`,
      `      <status>${record.status}</status>`,
      `      <marketPrice>${record.marketPrice}</marketPrice>`,
      `      <inputDigest>${record.inputDigest}</inputDigest>`,
      `      <sourceDigest>${record.sourceDigest}</sourceDigest>`,
      `      <inputs ${serializeAttributes({ ...record.input })} />`,
      `      <outputs ${serializeAttributes({
        recoveryStrength: record.output.recoveryStrength,
        purifyStrength: record.output.purifyStrength,
        toxicStrength: record.output.toxicStrength,
        buffStrength: record.output.buffStrength,
        toughnessStrength: record.output.toughnessStrength,
        currentValue: record.output.currentValue,
        valueCap: record.output.valueCap,
        rawPrice: record.output.rawPrice,
        recommendedPrice: record.output.recommendedPrice,
      })} />`,
    );
    if (record.exceptionCode) lines.push(`      <exceptionCode>${escapeXml(record.exceptionCode)}</exceptionCode>`);
    if (record.note) lines.push(`      <note>${escapeXml(record.note)}</note>`);
    lines.push("    </record>");
  }
  lines.push("  </records>", "</potionBalanceAudit>", "");
  return lines.join("\n");
}

function buildSyncedItemFiles(plan: Plan, records: AuditRecord[]): Map<string, string> {
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
    const absolutePath = path.join(REPO_ROOT, "data", "items", sourceFile);
    const source = fs.readFileSync(absolutePath, "utf8");
    const itemRegex = /(^[ \t]*<item(?:\s[^>]*)?>[\s\S]*?^[ \t]*<\/item>)/gm;
    const replaced = source.replace(itemRegex, (block) => {
      const itemName = extractItemName(block, sourceFile);
      const record = fileRecords.get(itemName);
      if (!record) return block;
      return insertBalance(stripBalance(block), buildInlineBalance(record, plan.authorityStatus));
    });
    result.set(absolutePath, replaced);
  }
  return result;
}

function buildInlineBalance(record: AuditRecord, authorityStatus: string): string {
  const lines = [
    "<balance>",
    `  <formulaFamily>${FORMULA_FAMILY}</formulaFamily>`,
    `  <schemaVersion>${SCHEMA_VERSION}</schemaVersion>`,
    `  <formulaVersion>${FORMULA_VERSION}</formulaVersion>`,
    `  <authorityStatus>${authorityStatus}</authorityStatus>`,
    `  <sourceLevel>${record.sourceLevel}</sourceLevel>`,
    `  <domain>${escapeXml(record.domain)}</domain>`,
    `  <balanceMode>${record.balanceMode}</balanceMode>`,
    `  <status>${record.status}</status>`,
    `  <currentValue>${formatNumber(record.output.currentValue)}</currentValue>`,
    `  <valueCap>${formatNumber(record.output.valueCap)}</valueCap>`,
    `  <formulaPrice>${formatNumber(record.output.recommendedPrice)}</formulaPrice>`,
    `  <marketPrice>${record.marketPrice}</marketPrice>`,
    `  <inputDigest>${record.inputDigest}</inputDigest>`,
    `  <sourceDigest>${record.sourceDigest}</sourceDigest>`,
    `  <auditRef>${escapeXml(record.auditRef)}</auditRef>`,
  ];
  if (record.exceptionCode) lines.push(`  <exceptionCode>${escapeXml(record.exceptionCode)}</exceptionCode>`);
  lines.push("</balance>");
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

function formatNumber(value: number): string {
  if (!Number.isFinite(value)) throw new Error(`非有限数值: ${value}`);
  const rounded = Math.round(value * 1_000_000) / 1_000_000;
  return String(Object.is(rounded, -0) ? 0 : rounded);
}

function readOptionalNumber(value: unknown): number {
  if (value === undefined || value === null || value === "") return 0;
  return readNumber(value, "number");
}

function readNumber(value: unknown, field: string): number {
  if (typeof value === "string" && value.includes("%")) {
    throw new Error(`${field}: 百分比输入尚未进入药剂 v2 公式`);
  }
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

function asArray(value: unknown): unknown[] {
  if (value === undefined || value === null) return [];
  return Array.isArray(value) ? value : [value];
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
