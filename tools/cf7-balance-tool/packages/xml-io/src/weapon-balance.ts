import { createHash } from "node:crypto";

import {
  buildWeaponBalanceInputDigestSource,
  computeWeaponBalanceInputDigest,
  createWeaponBalanceProfileFromAuditRecord,
  parseWeaponBalanceAuditLedger,
  parseWeaponBalanceContainer,
  type WeaponBalanceAuditLedger,
  type WeaponBalanceAuditRecord,
  type WeaponBalanceContainer,
  type WeaponBalanceDigestContext,
  type WeaponBalanceFormulaInputs,
  type WeaponBalanceInputDigestSource,
  type WeaponBalanceMechanicalInputs,
  type WeaponBalanceProfile,
  type WeaponBalanceRuntimeInputs
} from "@cf7-balance-tool/core";
import { XMLParser } from "fast-xml-parser";

export const DEFAULT_WEAPON_BALANCE_AUDIT_LEDGER =
  "tools/cf7-balance-tool/records/weapon-balance-audit.xml";

const VARIANT_TOP_LEVEL_FIELDS = new Set([
  "icon",
  "displayname",
  "description",
  "skill",
  "lifecycle"
]);

export interface ResolvedWeaponItemProfile {
  itemName: string;
  profileKey: string;
  itemUse: string | undefined;
  itemPrice: number;
  effectiveData: Record<string, unknown>;
  effectiveSkill: unknown;
  effectiveLifecycle: unknown;
  runtimeInputs: WeaponBalanceRuntimeInputs;
  mechanicalInputs: WeaponBalanceMechanicalInputs;
  digestContext: WeaponBalanceDigestContext;
  currentSourceDigest: string;
}

export interface ParsedWeaponBalanceItem extends ResolvedWeaponItemProfile {
  container: WeaponBalanceContainer;
  profile: WeaponBalanceProfile;
  /** @deprecated Use profile. */
  record: WeaponBalanceProfile;
  digestInput: WeaponBalanceInputDigestSource;
  currentInputDigest: string;
}

export interface WeaponBalanceSyncPlan {
  itemName: string;
  profileKeys: string[];
  container: WeaponBalanceContainer;
  updatedAuditRecords: WeaponBalanceAuditRecord[];
  balanceXml: string;
  inSync: boolean;
  differences: string[];
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  parseTagValue: true,
  trimValues: true
});

/** 从 XML 中发现所有带 balance 的 item，并逐有效 data profile 严格解析。 */
export function parseWeaponBalanceItemsFromXml(
  source: string
): ParsedWeaponBalanceItem[] {
  const parsed = parser.parse(source) as unknown;
  const items: ParsedWeaponBalanceItem[] = [];
  for (const item of collectWeaponItemObjects(parsed)) {
    if (item.balance === undefined) continue;
    items.push(...parseWeaponBalanceItemObject(item));
  }
  return items;
}

/** 一个 item 会展开成 data + 每个 data_* 的独立审计 profile。 */
export function parseWeaponBalanceItemObject(
  value: unknown
): ParsedWeaponBalanceItem[] {
  const item = requireObject(value, "weapon item");
  const container = parseWeaponBalanceContainer(item.balance);
  const expectedKeys = enumerateWeaponItemEffectiveProfileKeys(item);
  const actualKeys = Object.keys(container.profiles).sort(compareProfileKeys);
  assertExactProfileCoverage(normalizeItemName(item.name), expectedKeys, actualKeys);

  return expectedKeys.map((profileKey) => {
    const resolved = resolveWeaponItemEffectiveProfile(
      item,
      profileKey,
      container.workbookVersion
    );
    const profile = container.profiles[profileKey];
    if (!profile) {
      throw new Error(`${resolved.itemName}/${profileKey}: balance profile missing`);
    }
    const digestInput = buildWeaponBalanceProfileDigestInput(resolved, profile);
    return {
      ...resolved,
      container,
      profile,
      record: profile,
      digestInput,
      currentInputDigest: computeWeaponBalanceInputDigest(digestInput)
    };
  });
}

/** 列举 TierSystem 可由物品自身应用的所有有效数据键；永远包含 data。 */
export function enumerateWeaponItemEffectiveProfileKeys(value: unknown): string[] {
  const item = requireObject(value, "weapon item");
  requireObject(item.data, "weapon item.data");
  const keys = [
    "data",
    ...Object.keys(item).filter((key) => key.startsWith("data_") && key.length > 5)
  ];
  return [...new Set(keys)].sort(compareProfileKeys);
}

/**
 * 复刻 TierSystem.applyTierDataToItem：普通字段浅覆盖 data；五个顶层特例
 * 分别覆盖 root。缺少指定 data_* 时直接报错，不回退基础 profile。
 */
export function resolveWeaponItemEffectiveProfile(
  value: unknown,
  profileKey: string,
  workbookVersion: number
): ResolvedWeaponItemProfile {
  const item = requireObject(value, "weapon item");
  const itemName = normalizeItemName(item.name);
  if (!itemName) throw new Error("weapon item.name must be non-empty");
  if (profileKey !== "data" && (!profileKey.startsWith("data_") || profileKey.length <= 5)) {
    throw new Error(`${itemName}: invalid profile key ${profileKey}`);
  }

  const baseData = requireObject(item.data, `${itemName}.data`);
  const effectiveData: Record<string, unknown> = {};
  copyEffectiveDataFields(effectiveData, baseData, false);

  let variant: Record<string, unknown> | undefined;
  if (profileKey !== "data") {
    if (!Object.prototype.hasOwnProperty.call(item, profileKey)) {
      throw new Error(`${itemName}/${profileKey}: variant source missing; base fallback is forbidden`);
    }
    variant = requireObject(item[profileKey], `${itemName}.${profileKey}`);
    copyEffectiveDataFields(effectiveData, variant, true);
  }

  const effectiveSkill =
    variant && Object.prototype.hasOwnProperty.call(variant, "skill")
      ? variant.skill ?? null
      : item.skill ?? null;
  const effectiveLifecycle =
    variant && Object.prototype.hasOwnProperty.call(variant, "lifecycle")
      ? variant.lifecycle ?? null
      : item.lifecycle ?? null;
  const itemUse = normalizeOptionalScalar(item.use);
  const runtimeInputs: WeaponBalanceRuntimeInputs = {
    level: toFiniteNumber(effectiveData.level),
    power: toFiniteNumber(effectiveData.power),
    interval: toFiniteNumber(effectiveData.interval),
    capacity: toFiniteNumber(effectiveData.capacity),
    weight: toFiniteNumber(effectiveData.weight),
    impact: toFiniteNumber(effectiveData.impact)
  };
  const mechanicalInputs: WeaponBalanceMechanicalInputs = {
    bullet: effectiveData.bullet,
    clipname: effectiveData.clipname,
    split: effectiveData.split,
    damagetype: effectiveData.damagetype,
    magictype: effectiveData.magictype,
    singleshoot: effectiveData.singleshoot
  };
  const digestContext: WeaponBalanceDigestContext = {
    itemName,
    profileKey,
    workbookVersion,
    use: itemUse,
    ...mechanicalInputs,
    ...runtimeInputs
  };
  const resolvedBase = {
    itemName,
    profileKey,
    itemUse,
    itemPrice: toFiniteNumber(item.price),
    effectiveData,
    effectiveSkill,
    effectiveLifecycle,
    runtimeInputs,
    mechanicalInputs,
    digestContext
  };
  const resolved: ResolvedWeaponItemProfile = {
    ...resolvedBase,
    currentSourceDigest: computeWeaponBalanceSourceDigest(resolvedBase)
  };
  return resolved;
}

export function buildWeaponBalanceProfileDigestInput(
  resolved: ResolvedWeaponItemProfile,
  inputs: WeaponBalanceFormulaInputs
): WeaponBalanceInputDigestSource {
  return buildWeaponBalanceInputDigestSource(resolved.digestContext, inputs);
}

/** SHA-256 绑定完整有效 data、skill、lifecycle；属性名稳定排序。 */
export function computeWeaponBalanceSourceDigest(
  source: Pick<
    ResolvedWeaponItemProfile,
    | "itemName"
    | "profileKey"
    | "itemUse"
    | "effectiveData"
    | "effectiveSkill"
    | "effectiveLifecycle"
  >
): string {
  const canonical = stableStringify({
    itemName: source.itemName,
    profileKey: source.profileKey,
    use: source.itemUse ?? null,
    effectiveData: source.effectiveData,
    effectiveSkill: source.effectiveSkill ?? null,
    effectiveLifecycle: source.effectiveLifecycle ?? null
  });
  return `sha256:${createHash("sha256").update(canonical, "utf8").digest("hex")}`;
}

export function parseWeaponBalanceAuditLedgerFromXml(
  source: string
): WeaponBalanceAuditLedger {
  const parsed = parser.parse(source) as unknown;
  const root = requireObject(parsed, "XML document");
  if (!Object.prototype.hasOwnProperty.call(root, "weaponBalanceAudit")) {
    throw new Error("weaponBalanceAudit root element is required");
  }
  return parseWeaponBalanceAuditLedger(root.weaponBalanceAudit);
}

/**
 * 由 ledger 决策真源 + 当前机械源生成 runtime container，并同时刷新 ledger
 * 两类 digest。该纯函数不读取旧 balance 字段，因而不构成 v2 兼容。
 */
export function buildWeaponBalanceSyncPlanForItemObject(
  value: unknown,
  ledger: WeaponBalanceAuditLedger,
  indent = ""
): WeaponBalanceSyncPlan {
  const item = requireObject(value, "weapon item");
  const itemName = normalizeItemName(item.name);
  const profileKeys = enumerateWeaponItemEffectiveProfileKeys(item);
  const byIdentity = indexLedgerByIdentity(ledger);
  const profiles: Record<string, WeaponBalanceProfile> = {};
  const updatedAuditRecords: WeaponBalanceAuditRecord[] = [];

  for (const profileKey of profileKeys) {
    const identity = ledgerIdentity(itemName, profileKey);
    const audit = byIdentity.get(identity);
    if (!audit) {
      throw new Error(`${itemName}/${profileKey}: ledger record missing; base fallback is forbidden`);
    }
    const resolved = resolveWeaponItemEffectiveProfile(
      item,
      profileKey,
      ledger.workbookVersion
    );
    const digestInput = buildWeaponBalanceProfileDigestInput(resolved, audit);
    const updatedAudit: WeaponBalanceAuditRecord = {
      ...audit,
      inputDigest: computeWeaponBalanceInputDigest(digestInput),
      sourceDigest: resolved.currentSourceDigest
    };
    updatedAuditRecords.push(updatedAudit);
    profiles[profileKey] = createWeaponBalanceProfileFromAuditRecord(updatedAudit);
  }

  const unexpected = ledger.records.filter(
    (record) => record.itemName === itemName && !profileKeys.includes(record.profileKey)
  );
  if (unexpected.length > 0) {
    throw new Error(
      `${itemName}: ledger contains profiles without an effective data source: ${unexpected
        .map((record) => record.profileKey)
        .join(", ")}`
    );
  }

  const container: WeaponBalanceContainer = {
    formulaFamily: "weapon",
    schemaVersion: 1,
    workbookVersion: ledger.workbookVersion,
    profiles
  };
  const differences: string[] = [];
  if (item.balance === undefined) {
    differences.push("inline balance missing");
  } else {
    try {
      const existing = parseWeaponBalanceContainer(item.balance);
      if (stableStringify(existing) !== stableStringify(container)) {
        differences.push("inline balance differs from ledger-derived v1");
      }
    } catch (error) {
      differences.push(
        `inline balance is not strict v1: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }
  for (const updated of updatedAuditRecords) {
    const original = byIdentity.get(ledgerIdentity(updated.itemName, updated.profileKey));
    if (
      original &&
      (original.inputDigest !== updated.inputDigest ||
        original.sourceDigest !== updated.sourceDigest)
    ) {
      differences.push(`ledger digest drift: ${updated.profileKey}`);
    }
  }

  return {
    itemName,
    profileKeys,
    container,
    updatedAuditRecords,
    balanceXml: serializeWeaponBalanceContainerXml(container, indent),
    inSync: differences.length === 0,
    differences
  };
}

export function buildWeaponBalanceSyncPlansFromXml(
  source: string,
  ledger: WeaponBalanceAuditLedger
): WeaponBalanceSyncPlan[] {
  const parsed = parser.parse(source) as unknown;
  const ledgerItems = new Set(ledger.records.map((record) => record.itemName));
  return collectWeaponItemObjects(parsed)
    .filter((item) => {
      const itemName = normalizeItemName(item.name);
      return item.balance !== undefined || ledgerItems.has(itemName);
    })
    .map((item) => buildWeaponBalanceSyncPlanForItemObject(item, ledger));
}

export function mergeWeaponBalanceSyncPlanIntoLedger(
  ledger: WeaponBalanceAuditLedger,
  plans: readonly WeaponBalanceSyncPlan[]
): WeaponBalanceAuditLedger {
  const updates = new Map<string, WeaponBalanceAuditRecord>();
  for (const plan of plans) {
    for (const record of plan.updatedAuditRecords) updates.set(record.auditRef, record);
  }
  return {
    ...ledger,
    records: ledger.records.map((record) => updates.get(record.auditRef) ?? record)
  };
}

/** 写入前的全局闭合门：每条 ledger 真源必须且只能命中一个 item/profile。 */
export function assertWeaponBalanceSyncCoverage(
  ledger: WeaponBalanceAuditLedger,
  plans: readonly WeaponBalanceSyncPlan[]
): void {
  const counts = new Map<string, number>();
  const knownAuditRefs = new Set(ledger.records.map((record) => record.auditRef));
  for (const plan of plans) {
    if (plan.updatedAuditRecords.length !== plan.profileKeys.length) {
      throw new Error(`${plan.itemName}: sync plan profile/ledger count mismatch`);
    }
    for (const record of plan.updatedAuditRecords) {
      if (!knownAuditRefs.has(record.auditRef)) {
        throw new Error(`${record.auditRef}: sync plan references an unknown ledger record`);
      }
      counts.set(record.auditRef, (counts.get(record.auditRef) ?? 0) + 1);
    }
  }
  for (const record of ledger.records) {
    const count = counts.get(record.auditRef) ?? 0;
    if (count !== 1) {
      throw new Error(
        `${record.auditRef}: ledger record must join exactly one weapon item/profile, joined ${count}`
      );
    }
  }
}

/** canonical runtime `<balance>` 片段。 */
export function serializeWeaponBalanceContainerXml(
  container: WeaponBalanceContainer,
  indent = ""
): string {
  const one = `${indent}  `;
  const two = `${indent}    `;
  const three = `${indent}      `;
  const lines = [
    `${indent}<balance>`,
    `${one}<formulaFamily>${escapeXml(container.formulaFamily)}</formulaFamily>`,
    `${one}<schemaVersion>${container.schemaVersion}</schemaVersion>`,
    `${one}<workbookVersion>${container.workbookVersion}</workbookVersion>`,
    `${one}<profiles>`
  ];
  for (const profileKey of Object.keys(container.profiles).sort(compareProfileKeys)) {
    const profile = container.profiles[profileKey]!;
    lines.push(`${two}<${profileKey}>`);
    for (const key of [
      "dualWield",
      "pierce",
      "damageType",
      "shotgun",
      "magPrice",
      "weightLayers",
      "category",
      "formula"
    ] as const) {
      lines.push(`${three}<${key}>${profile[key]}</${key}>`);
    }
    lines.push(
      `${three}<status>${profile.status}</status>`,
      `${three}<displayEligible>${profile.displayEligible}</displayEligible>`,
      `${three}<inputDigest>${profile.inputDigest}</inputDigest>`,
      `${three}<auditRef>${escapeXml(profile.auditRef)}</auditRef>`,
      `${two}</${profileKey}>`
    );
  }
  lines.push(`${one}</profiles>`, `${indent}</balance>`);
  return lines.join("\n");
}

export function serializeWeaponBalanceAuditLedgerXml(
  ledger: WeaponBalanceAuditLedger
): string {
  const lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<weaponBalanceAudit>",
    `  <formulaFamily>${escapeXml(ledger.formulaFamily)}</formulaFamily>`,
    `  <schemaVersion>${ledger.schemaVersion}</schemaVersion>`,
    `  <workbookVersion>${ledger.workbookVersion}</workbookVersion>`,
    `  <workbookSha256>${escapeXml(ledger.workbookSha256)}</workbookSha256>`,
    "  <records>"
  ];
  for (const record of ledger.records) {
    lines.push(
      "    <record>",
      `      <auditRef>${escapeXml(record.auditRef)}</auditRef>`,
      `      <itemName>${escapeXml(record.itemName)}</itemName>`,
      `      <profileKey>${escapeXml(record.profileKey)}</profileKey>`
    );
    for (const key of [
      "dualWield",
      "pierce",
      "damageType",
      "shotgun",
      "magPrice",
      "weightLayers",
      "category",
      "formula"
    ] as const) {
      lines.push(`      <${key}>${record[key]}</${key}>`);
    }
    if (record.priceLayers !== undefined) {
      lines.push(`      <priceLayers>${record.priceLayers}</priceLayers>`);
    }
    lines.push(
      `      <status>${record.status}</status>`,
      `      <displayEligible>${record.displayEligible}</displayEligible>`,
      `      <inputDigest>${record.inputDigest}</inputDigest>`,
      `      <sourceDigest>${record.sourceDigest}</sourceDigest>`,
      "      <budgetBreakdown>"
    );
    for (const entry of record.budgetBreakdown) {
      lines.push(
        "        <entry>",
        `          <code>${escapeXml(entry.code)}</code>`,
        `          <delta>${entry.delta}</delta>`,
        `          <ruleRef>${escapeXml(entry.ruleRef)}</ruleRef>`
      );
      if (entry.evidenceRef !== undefined) {
        lines.push(`          <evidenceRef>${escapeXml(entry.evidenceRef)}</evidenceRef>`);
      }
      lines.push("        </entry>");
    }
    lines.push("      </budgetBreakdown>", "      <ruleRefs>");
    for (const ref of record.ruleRefs) {
      lines.push(
        "        <ref>",
        `          <id>${escapeXml(ref.id)}</id>`,
        `          <target>${escapeXml(ref.target)}</target>`
      );
      if (ref.evidenceRef !== undefined) {
        lines.push(`          <evidenceRef>${escapeXml(ref.evidenceRef)}</evidenceRef>`);
      }
      lines.push("        </ref>");
    }
    lines.push("      </ruleRefs>");
    if (record.note !== undefined) lines.push(`      <note>${escapeXml(record.note)}</note>`);
    lines.push("    </record>");
  }
  lines.push("  </records>", "</weaponBalanceAudit>", "");
  return lines.join("\n");
}

/**
 * 只替换/插入目标 item 根下的 balance 区块，保留其余 XML 文本。调用方应在
 * 写盘前后分别重新 parse 校验。
 */
export function applyWeaponBalanceSyncPlansToXml(
  source: string,
  ledger: WeaponBalanceAuditLedger
): { source: string; plans: WeaponBalanceSyncPlan[] } {
  const plans: WeaponBalanceSyncPlan[] = [];
  const ledgerItems = new Set(ledger.records.map((record) => record.itemName));
  // 历史 XML 的 item 开/闭标签缩进并不总一致，不能依赖反向引用。
  const itemPattern = /^([ \t]*)<item\b[^>]*>[\s\S]*?^[ \t]*<\/item>/gm;
  const output = source.replace(itemPattern, (itemBlock: string, itemIndent: string) => {
    const parsed = parser.parse(`<root>${itemBlock}</root>`) as Record<string, unknown>;
    const root = requireObject(parsed.root, "root");
    const rawItem = Array.isArray(root.item) && root.item.length === 1
      ? root.item[0]
      : root.item;
    const item = requireObject(
      rawItem,
      `item (${itemBlock.slice(0, 80).replace(/\s+/g, " ").trim()})`
    );
    const itemName = normalizeItemName(item.name);
    if (item.balance === undefined && !ledgerItems.has(itemName)) return itemBlock;

    const balancePattern = /^([ \t]*)<balance\b[^>]*>[\s\S]*?^[ \t]*<\/balance>/m;
    const existingBalance = balancePattern.exec(itemBlock);
    const dataIndent = /^([ \t]*)<data\b[^>]*>/m.exec(itemBlock)?.[1];
    const childIndent = existingBalance?.[1] ?? dataIndent ?? `${itemIndent}  `;
    const plan = buildWeaponBalanceSyncPlanForItemObject(item, ledger, childIndent);
    plans.push(plan);
    if (existingBalance) return itemBlock.replace(balancePattern, plan.balanceXml);
    const dataClosePattern = new RegExp(`^(\\s*)<\\/data>`, "m");
    const match = dataClosePattern.exec(itemBlock);
    if (!match || match.index === undefined) {
      throw new Error(`${itemName}: cannot locate base </data> insertion point`);
    }
    const insertionPoint = match.index + match[0].length;
    return `${itemBlock.slice(0, insertionPoint)}\n${plan.balanceXml}${itemBlock.slice(insertionPoint)}`;
  });
  return { source: output, plans };
}

function collectWeaponItemObjects(value: unknown): Record<string, unknown>[] {
  const result: Record<string, unknown>[] = [];
  visit(value);
  return result;

  function visit(current: unknown): void {
    if (Array.isArray(current)) {
      current.forEach(visit);
      return;
    }
    if (!isObject(current)) return;
    if (
      Object.prototype.hasOwnProperty.call(current, "name") &&
      (Object.prototype.hasOwnProperty.call(current, "data") ||
        Object.prototype.hasOwnProperty.call(current, "balance"))
    ) {
      result.push(current);
      return;
    }
    Object.values(current).forEach(visit);
  }
}

function assertExactProfileCoverage(
  itemName: string,
  expected: string[],
  actual: string[]
): void {
  const missing = expected.filter((key) => !actual.includes(key));
  const extra = actual.filter((key) => !expected.includes(key));
  if (missing.length > 0 || extra.length > 0) {
    throw new Error(
      `${itemName}: balance profile coverage mismatch` +
        (missing.length > 0 ? `; missing ${missing.join(", ")}` : "") +
        (extra.length > 0 ? `; no effective source for ${extra.join(", ")}` : "")
    );
  }
}

function copyEffectiveDataFields(
  target: Record<string, unknown>,
  source: Record<string, unknown>,
  isVariant: boolean
): void {
  for (const [key, value] of Object.entries(source)) {
    if (
      (isVariant && VARIANT_TOP_LEVEL_FIELDS.has(key)) ||
      key === "balance" ||
      key.startsWith("data_")
    ) {
      continue;
    }
    target[key] = value;
  }
}

function indexLedgerByIdentity(
  ledger: WeaponBalanceAuditLedger
): ReadonlyMap<string, WeaponBalanceAuditRecord> {
  const index = new Map<string, WeaponBalanceAuditRecord>();
  for (const record of ledger.records) {
    const key = ledgerIdentity(record.itemName, record.profileKey);
    if (index.has(key)) throw new Error(`duplicate ledger identity ${record.itemName}/${record.profileKey}`);
    index.set(key, record);
  }
  return index;
}

function ledgerIdentity(itemName: string, profileKey: string): string {
  return `${itemName}\u0000${profileKey}`;
}

function stableStringify(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    return Number.isFinite(value) ? JSON.stringify(value) : JSON.stringify(String(value));
  }
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (isObject(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(String(value));
}

function compareProfileKeys(left: string, right: string): number {
  if (left === "data") return right === "data" ? 0 : -1;
  if (right === "data") return 1;
  return left.localeCompare(right, "en");
}

function normalizeItemName(value: unknown): string {
  if (Array.isArray(value)) return value.length === 1 ? normalizeItemName(value[0]) : "";
  if (value === undefined || value === null) return "";
  return String(value).trim();
}

function normalizeOptionalScalar(value: unknown): string | undefined {
  if (
    value === undefined ||
    value === null ||
    (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean")
  ) {
    return undefined;
  }
  const parsed = String(value).trim();
  return parsed.length > 0 ? parsed : undefined;
}

function toFiniteNumber(value: unknown): number {
  if (value === undefined || value === null || value === "") return Number.NaN;
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function requireObject(value: unknown, path: string): Record<string, unknown> {
  if (!isObject(value)) throw new Error(`${path}: expected an object`);
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}
