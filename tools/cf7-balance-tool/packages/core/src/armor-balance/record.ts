export const ARMOR_BALANCE_FORMULA_FAMILY = "armor";
export const ARMOR_BALANCE_SCHEMA_VERSION = 1;
export const ARMOR_BALANCE_FORMULA_VERSION = 1;
export const ARMOR_BALANCE_WORKBOOK_VERSION = 1;
/**
 * 现役只读工作簿实算快照，与 potion 家族 pin 的同一文件一致。
 * weapon 家族注册的 v1（BAC3D341…）是 2026-07-23 基线，其门禁不实算现役文件；
 * armor 的门禁要求 plan 声明值等于现役 xlsx 实算 SHA，故以现役快照为准。
 */
export const ARMOR_BALANCE_WORKBOOK_SHA256 =
  "357E07955281D4CB3884902B58165E19E97852216AE5A76965D3EBD04FB4E107";

export const ARMOR_BALANCE_AUDIT_STATUSES = [
  "confirmed",
  "unresolved",
  "invalid"
] as const;

export const ARMOR_BALANCE_BUDGET_CODES = [
  "acquisition.kshop",
  "acquisition.crafting",
  "acquisition.high-price",
  "acquisition.dungeon-drop",
  "acquisition.gold-standard",
  "version-bonus",
  "debuff-trade",
  "level-band.40plus-float"
] as const;

/** 数值加权（M 层）只承认这些条目；价格加权（E 层）只由高价条目产生。 */
export const ARMOR_BALANCE_PRICE_LAYER_CODE = "acquisition.high-price";

export type ArmorBalanceAuditStatus =
  (typeof ARMOR_BALANCE_AUDIT_STATUSES)[number];
export type ArmorBalanceBudgetCode =
  (typeof ARMOR_BALANCE_BUDGET_CODES)[number];

export interface ArmorBalanceBudgetEntry {
  code: string;
  delta: number;
  ruleRef: string;
  evidenceRef?: string;
}

/** plan 是唯一人工真源；audit 与物品内联 `<balance>` 均由它派生。 */
export interface ArmorBalancePlanRecord {
  itemName: string;
  sourceFile: string;
  weightLayers: number;
  priceLayers: number;
  category: number;
  damageTypeFactor: number;
  adoptedGoldPrice: number;
  expectedKPointPrice: number;
  kpointEvidenceRef: string;
  status: ArmorBalanceAuditStatus;
  budgetBreakdown: ArmorBalanceBudgetEntry[];
  note?: string;
}

export interface ArmorBalancePlan {
  formulaFamily: typeof ARMOR_BALANCE_FORMULA_FAMILY;
  schemaVersion: typeof ARMOR_BALANCE_SCHEMA_VERSION;
  formulaVersion: typeof ARMOR_BALANCE_FORMULA_VERSION;
  workbookVersion: number;
  workbookSha256: string;
  records: ArmorBalancePlanRecord[];
}

export class ArmorBalanceParseError extends Error {
  readonly path: string;

  constructor(path: string, message: string) {
    super(`${path}: ${message}`);
    this.name = "ArmorBalanceParseError";
    this.path = path;
  }
}

export function parseArmorBalancePlan(value: unknown): ArmorBalancePlan {
  const document = requireObject(value, "armorBalancePlan");
  const source = requireObject(
    readRawValue(document, "armorBalancePlan"),
    "armorBalancePlan"
  );
  assertOnlyKeys(source, [
    "formulaFamily",
    "schemaVersion",
    "formulaVersion",
    "workbookVersion",
    "workbookSha256",
    "records"
  ], "armorBalancePlan");

  const formulaFamily = readRequiredString(
    source,
    "formulaFamily",
    "armorBalancePlan"
  );
  const schemaVersion = readRequiredFiniteNumber(
    source,
    "schemaVersion",
    "armorBalancePlan"
  );
  const formulaVersion = readRequiredFiniteNumber(
    source,
    "formulaVersion",
    "armorBalancePlan"
  );
  if (formulaFamily !== ARMOR_BALANCE_FORMULA_FAMILY) {
    throw new ArmorBalanceParseError(
      "armorBalancePlan.formulaFamily",
      `expected ${ARMOR_BALANCE_FORMULA_FAMILY}`
    );
  }
  if (schemaVersion !== ARMOR_BALANCE_SCHEMA_VERSION) {
    throw new ArmorBalanceParseError(
      "armorBalancePlan.schemaVersion",
      `expected ${ARMOR_BALANCE_SCHEMA_VERSION}`
    );
  }
  if (formulaVersion !== ARMOR_BALANCE_FORMULA_VERSION) {
    throw new ArmorBalanceParseError(
      "armorBalancePlan.formulaVersion",
      `expected implemented formula version ${ARMOR_BALANCE_FORMULA_VERSION}`
    );
  }
  const workbookVersion = readRequiredFiniteNumber(
    source,
    "workbookVersion",
    "armorBalancePlan"
  );
  if (workbookVersion !== ARMOR_BALANCE_WORKBOOK_VERSION) {
    throw new ArmorBalanceParseError(
      "armorBalancePlan.workbookVersion",
      `unsupported workbook version ${workbookVersion}`
    );
  }
  const workbookSha256 = readRequiredString(
    source,
    "workbookSha256",
    "armorBalancePlan"
  );
  if (!/^[0-9A-F]{64}$/.test(workbookSha256)) {
    throw new ArmorBalanceParseError(
      "armorBalancePlan.workbookSha256",
      "expected 64 upper-case hex digits"
    );
  }
  if (workbookSha256 !== ARMOR_BALANCE_WORKBOOK_SHA256) {
    throw new ArmorBalanceParseError(
      "armorBalancePlan.workbookSha256",
      `does not match workbookVersion ${workbookVersion}`
    );
  }

  const rawRecords = readContainerList(
    readRawValue(source, "records"),
    "record",
    "armorBalancePlan.records"
  );
  if (rawRecords.length === 0) {
    throw new ArmorBalanceParseError(
      "armorBalancePlan.records",
      "expected at least one record"
    );
  }
  const records = rawRecords.map((record, index) =>
    parseArmorBalancePlanRecord(
      record,
      `armorBalancePlan.records.record[${index}]`
    )
  );
  const identities = new Set<string>();
  for (const record of records) {
    if (identities.has(record.itemName)) {
      throw new ArmorBalanceParseError(
        "armorBalancePlan.records",
        `duplicate itemName ${record.itemName}`
      );
    }
    identities.add(record.itemName);
  }

  return {
    formulaFamily: ARMOR_BALANCE_FORMULA_FAMILY,
    schemaVersion: ARMOR_BALANCE_SCHEMA_VERSION,
    formulaVersion: ARMOR_BALANCE_FORMULA_VERSION,
    workbookVersion,
    workbookSha256,
    records
  };
}

export function parseArmorBalancePlanRecord(
  value: unknown,
  path = "armorBalancePlan.records.record"
): ArmorBalancePlanRecord {
  const source = requireObject(value, path);
  assertOnlyKeys(source, [
    "itemName",
    "sourceFile",
    "weightLayers",
    "priceLayers",
    "category",
    "damageTypeFactor",
    "adoptedGoldPrice",
    "expectedKPointPrice",
    "kpointEvidenceRef",
    "status",
    "budgetBreakdown",
    "note"
  ], path);

  const record: ArmorBalancePlanRecord = {
    itemName: readRequiredString(source, "itemName", path),
    sourceFile: readRequiredString(source, "sourceFile", path),
    weightLayers: readRequiredFiniteNumber(source, "weightLayers", path),
    priceLayers: readRequiredFiniteNumber(source, "priceLayers", path),
    category: readRequiredFiniteNumber(source, "category", path),
    damageTypeFactor: readRequiredFiniteNumber(source, "damageTypeFactor", path),
    adoptedGoldPrice: readRequiredFiniteNumber(source, "adoptedGoldPrice", path),
    expectedKPointPrice: readRequiredFiniteNumber(
      source,
      "expectedKPointPrice",
      path
    ),
    kpointEvidenceRef: readRequiredString(source, "kpointEvidenceRef", path),
    status: parseAuditStatus(source, path),
    budgetBreakdown: parseBudgetBreakdown(source, path)
  };
  const note = readOptionalString(source, "note");
  if (note !== undefined) record.note = note;

  if (!/^data\/items\/防具_[^/]+\.xml$/.test(record.sourceFile)) {
    throw new ArmorBalanceParseError(
      `${path}.sourceFile`,
      "armor 家族只允许登记 data/items/防具_*.xml"
    );
  }
  if (!Number.isInteger(record.weightLayers) || record.weightLayers < 0) {
    throw new ArmorBalanceParseError(
      `${path}.weightLayers`,
      "expected a non-negative integer"
    );
  }
  if (!Number.isInteger(record.priceLayers)) {
    throw new ArmorBalanceParseError(
      `${path}.priceLayers`,
      "expected an integer"
    );
  }
  if (record.category <= 0 || record.damageTypeFactor <= 0) {
    throw new ArmorBalanceParseError(
      `${path}.category`,
      "category/damageTypeFactor must be positive"
    );
  }
  if (record.adoptedGoldPrice <= 0) {
    throw new ArmorBalanceParseError(
      `${path}.adoptedGoldPrice`,
      "expected a positive adopted price"
    );
  }
  if (
    !Number.isInteger(record.expectedKPointPrice) ||
    record.expectedKPointPrice < 0
  ) {
    throw new ArmorBalanceParseError(
      `${path}.expectedKPointPrice`,
      "expected a non-negative integer"
    );
  }

  assertBudgetClosure(record, path);
  return record;
}

/** M 层闭合：预算 delta 之和等于 weightLayers；E 层只计高价条目。 */
function assertBudgetClosure(
  record: ArmorBalancePlanRecord,
  path: string
): void {
  if (record.budgetBreakdown.length === 0) {
    throw new ArmorBalanceParseError(
      `${path}.budgetBreakdown`,
      "expected at least one entry"
    );
  }
  const sum = record.budgetBreakdown.reduce(
    (total, entry) => total + entry.delta,
    0
  );
  if (sum !== record.weightLayers) {
    throw new ArmorBalanceParseError(
      `${path}.budgetBreakdown`,
      `delta sum ${sum} does not close to weightLayers ${record.weightLayers}`
    );
  }
  const priceLayers = record.budgetBreakdown
    .filter((entry) => entry.code === ARMOR_BALANCE_PRICE_LAYER_CODE)
    .reduce((total, entry) => total + entry.delta, 0);
  if (priceLayers !== record.priceLayers) {
    throw new ArmorBalanceParseError(
      `${path}.priceLayers`,
      `expected ${ARMOR_BALANCE_PRICE_LAYER_CODE} delta ${priceLayers} to equal priceLayers ${record.priceLayers}`
    );
  }
}

function parseAuditStatus(
  source: Record<string, unknown>,
  path: string
): ArmorBalanceAuditStatus {
  const status = readRequiredString(source, "status", path);
  if (!(ARMOR_BALANCE_AUDIT_STATUSES as readonly string[]).includes(status)) {
    throw new ArmorBalanceParseError(
      `${path}.status`,
      `expected one of ${ARMOR_BALANCE_AUDIT_STATUSES.join(", ")}`
    );
  }
  return status as ArmorBalanceAuditStatus;
}

function parseBudgetBreakdown(
  source: Record<string, unknown>,
  path: string
): ArmorBalanceBudgetEntry[] {
  const rawEntries = readContainerList(
    readRawValue(source, "budgetBreakdown"),
    "entry",
    `${path}.budgetBreakdown`
  );
  return rawEntries.map((rawEntry, index) => {
    const entryPath = `${path}.budgetBreakdown.entry[${index}]`;
    const entrySource = requireObject(rawEntry, entryPath);
    assertOnlyKeys(
      entrySource,
      ["code", "delta", "ruleRef", "evidenceRef"],
      entryPath
    );
    const code = readRequiredString(entrySource, "code", entryPath);
    if (!(ARMOR_BALANCE_BUDGET_CODES as readonly string[]).includes(code)) {
      throw new ArmorBalanceParseError(
        `${entryPath}.code`,
        `expected one of ${ARMOR_BALANCE_BUDGET_CODES.join(", ")}`
      );
    }
    const entry: ArmorBalanceBudgetEntry = {
      code,
      delta: readRequiredFiniteNumber(entrySource, "delta", entryPath),
      ruleRef: readRequiredString(entrySource, "ruleRef", entryPath)
    };
    const evidenceRef = readOptionalString(entrySource, "evidenceRef");
    if (evidenceRef !== undefined) entry.evidenceRef = evidenceRef;
    return entry;
  });
}

function readContainerList(
  container: unknown,
  childName: string,
  path: string
): unknown[] {
  if (container === undefined || container === null || container === "") {
    return [];
  }
  if (Array.isArray(container)) return container;
  const source = requireObject(container, path);
  const children = readRawValue(source, childName);
  if (children === undefined || children === null || children === "") return [];
  return Array.isArray(children) ? children : [children];
}

function assertOnlyKeys(
  source: Record<string, unknown>,
  allowed: readonly string[],
  path: string
): void {
  const allowedSet = new Set(allowed);
  for (const rawKey of Object.keys(source)) {
    if (rawKey === "#text") continue;
    const key = rawKey.startsWith("@_") ? rawKey.slice(2) : rawKey;
    if (!allowedSet.has(key)) {
      throw new ArmorBalanceParseError(`${path}.${key}`, "unexpected field");
    }
  }
}

function requireObject(value: unknown, path: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ArmorBalanceParseError(path, "expected an object");
  }
  return value as Record<string, unknown>;
}

function readRawValue(source: Record<string, unknown>, key: string): unknown {
  if (Object.prototype.hasOwnProperty.call(source, key)) return source[key];
  const attributeKey = `@_${key}`;
  return Object.prototype.hasOwnProperty.call(source, attributeKey)
    ? source[attributeKey]
    : undefined;
}

function readRequiredFiniteNumber(
  source: Record<string, unknown>,
  key: string,
  path: string
): number {
  const raw = readRawValue(source, key);
  let parsed = Number.NaN;
  if (typeof raw === "number") {
    parsed = raw;
  } else if (typeof raw === "string") {
    const normalized = raw.trim();
    if (
      normalized !== "" &&
      /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(normalized)
    ) {
      parsed = Number(normalized);
    }
  }
  if (!Number.isFinite(parsed)) {
    throw new ArmorBalanceParseError(`${path}.${key}`, "expected a finite number");
  }
  return parsed;
}

function readRequiredString(
  source: Record<string, unknown>,
  key: string,
  path: string
): string {
  const parsed = readOptionalString(source, key);
  if (parsed === undefined) {
    throw new ArmorBalanceParseError(`${path}.${key}`, "expected a non-empty string");
  }
  return parsed;
}

function readOptionalString(
  source: Record<string, unknown>,
  key: string
): string | undefined {
  const raw = readRawValue(source, key);
  if (raw === undefined || raw === null || Array.isArray(raw)) return undefined;
  const parsed = String(raw).trim();
  return parsed.length > 0 ? parsed : undefined;
}
