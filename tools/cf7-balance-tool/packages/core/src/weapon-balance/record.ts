export const WEAPON_BALANCE_FORMULA_FAMILY = "weapon";
export const WEAPON_BALANCE_SCHEMA_VERSION = 1;
export const WEAPON_BALANCE_FORMULA_VERSION = 1;
export const CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION = 1;
export const WEAPON_BALANCE_WORKBOOK_SHA256_BY_VERSION: Readonly<
  Record<number, string>
> = Object.freeze({
  1: "BAC3D341DB2B2BF966C3D473ED4793725BAF0B68BE01BA0D2804A76D6DCB840A"
});
export const CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256 =
  WEAPON_BALANCE_WORKBOOK_SHA256_BY_VERSION[
    CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION
  ]!;

export const WEAPON_BALANCE_AUDIT_STATUSES = [
  "confirmed",
  "unresolved",
  "invalid"
] as const;

export const WEAPON_BALANCE_FORMULA_INPUT_KEYS = [
  "dualWield",
  "pierce",
  "damageType",
  "shotgun",
  "magPrice",
  "weightLayers",
  "category",
  "formula"
] as const;

export const WEAPON_BALANCE_BUDGET_CODES = [
  "acquisition.gold-standard",
  "acquisition.crafting",
  "acquisition.kshop",
  "acquisition.high-price",
  "acquisition.unverified"
] as const;

export type WeaponBalanceAuditStatus =
  (typeof WEAPON_BALANCE_AUDIT_STATUSES)[number];
export type WeaponBalanceFormulaInputKey =
  (typeof WEAPON_BALANCE_FORMULA_INPUT_KEYS)[number];
export type WeaponBalanceBudgetCode =
  (typeof WEAPON_BALANCE_BUDGET_CODES)[number];

export interface WeaponBalanceFormulaInputs {
  dualWield: number;
  pierce: number;
  damageType: number;
  shotgun: number;
  magPrice: number;
  weightLayers: number;
  category: number;
  formula: number;
}

/**
 * 物品 XML 中的紧凑运行时副本。profileKey 由 `<profiles>` 下的标签派生，
 * 不重复写入 XML。
 */
export interface WeaponBalanceProfile extends WeaponBalanceFormulaInputs {
  profileKey: string;
  status: WeaponBalanceAuditStatus;
  displayEligible: boolean;
  inputDigest: string;
  auditRef: string;
}

export interface WeaponBalanceContainer {
  formulaFamily: typeof WEAPON_BALANCE_FORMULA_FAMILY;
  schemaVersion: typeof WEAPON_BALANCE_SCHEMA_VERSION;
  workbookVersion: number;
  profiles: Record<string, WeaponBalanceProfile>;
}

export interface WeaponBalanceBudgetEntry {
  code: string;
  delta: number;
  ruleRef: string;
  evidenceRef?: string;
}

export interface WeaponBalanceRuleReference {
  id: string;
  target: string;
  evidenceRef?: string;
}

/** ledger record 是完整审计真源；inline profile 必须由它派生。 */
export interface WeaponBalanceAuditRecord extends WeaponBalanceFormulaInputs {
  /** 仅供价格证据反验；不属于 DPS 输入，不投影到物品 balance。 */
  priceLayers?: number;
  auditRef: string;
  itemName: string;
  profileKey: string;
  status: WeaponBalanceAuditStatus;
  displayEligible: boolean;
  inputDigest: string;
  sourceDigest: string;
  budgetBreakdown: WeaponBalanceBudgetEntry[];
  ruleRefs: WeaponBalanceRuleReference[];
  note?: string;
}

export interface WeaponBalanceAuditLedger {
  formulaFamily: typeof WEAPON_BALANCE_FORMULA_FAMILY;
  schemaVersion: typeof WEAPON_BALANCE_SCHEMA_VERSION;
  workbookVersion: number;
  workbookSha256: string;
  records: WeaponBalanceAuditRecord[];
}

export class WeaponBalanceParseError extends Error {
  readonly path: string;

  constructor(path: string, message: string) {
    super(`${path}: ${message}`);
    this.name = "WeaponBalanceParseError";
    this.path = path;
  }
}

/** 严格解析未上线的最终 v1；不读取 v2 或更早的平铺结构。 */
export function parseWeaponBalanceContainer(value: unknown): WeaponBalanceContainer {
  const source = requireObject(value, "balance");
  assertOnlyKeys(source, [
    "formulaFamily",
    "schemaVersion",
    "workbookVersion",
    "profiles"
  ], "balance");

  const formulaFamily = readRequiredString(source, "formulaFamily", "balance");
  const schemaVersion = readRequiredFiniteNumber(
    source,
    "schemaVersion",
    "balance"
  );
  if (formulaFamily !== WEAPON_BALANCE_FORMULA_FAMILY) {
    throw new WeaponBalanceParseError(
      "balance.formulaFamily",
      `expected ${WEAPON_BALANCE_FORMULA_FAMILY}`
    );
  }
  if (schemaVersion !== WEAPON_BALANCE_SCHEMA_VERSION) {
    throw new WeaponBalanceParseError(
      "balance.schemaVersion",
      `expected ${WEAPON_BALANCE_SCHEMA_VERSION}`
    );
  }
  const workbookVersion = parseKnownWorkbookVersion(
    source,
    "workbookVersion",
    "balance"
  );

  const rawProfiles = readRawValue(source, "profiles");
  const profileSource = requireObject(rawProfiles, "balance.profiles");
  const profileEntries = Object.entries(profileSource).filter(
    ([key]) => key !== "#text"
  );
  if (profileEntries.length === 0) {
    throw new WeaponBalanceParseError(
      "balance.profiles",
      "expected at least the data profile"
    );
  }

  const profiles: Record<string, WeaponBalanceProfile> = {};
  for (const [rawKey, rawProfile] of profileEntries) {
    const profileKey = normalizeProfileKey(rawKey, "balance.profiles");
    profiles[profileKey] = parseWeaponBalanceProfile(rawProfile, profileKey);
  }

  return {
    formulaFamily: WEAPON_BALANCE_FORMULA_FAMILY,
    schemaVersion: WEAPON_BALANCE_SCHEMA_VERSION,
    workbookVersion,
    profiles
  };
}

export function parseWeaponBalanceProfile(
  value: unknown,
  profileKey: string
): WeaponBalanceProfile {
  const path = `balance.profiles.${normalizeProfileKey(profileKey, "balance.profiles")}`;
  const source = requireObject(value, path);
  assertOnlyKeys(source, [
    ...WEAPON_BALANCE_FORMULA_INPUT_KEYS,
    "status",
    "displayEligible",
    "inputDigest",
    "auditRef"
  ], path);

  return {
    profileKey,
    ...parseFormulaInputs(source, path),
    status: parseAuditStatus(source, path),
    displayEligible: readRequiredBoolean(source, "displayEligible", path),
    inputDigest: readRequiredString(source, "inputDigest", path),
    auditRef: readRequiredString(source, "auditRef", path)
  };
}

export function parseWeaponBalanceAuditLedger(
  value: unknown
): WeaponBalanceAuditLedger {
  const source = requireObject(value, "weaponBalanceAudit");
  assertOnlyKeys(source, [
    "formulaFamily",
    "schemaVersion",
    "workbookVersion",
    "workbookSha256",
    "records"
  ], "weaponBalanceAudit");

  const formulaFamily = readRequiredString(
    source,
    "formulaFamily",
    "weaponBalanceAudit"
  );
  const schemaVersion = readRequiredFiniteNumber(
    source,
    "schemaVersion",
    "weaponBalanceAudit"
  );
  if (formulaFamily !== WEAPON_BALANCE_FORMULA_FAMILY) {
    throw new WeaponBalanceParseError(
      "weaponBalanceAudit.formulaFamily",
      `expected ${WEAPON_BALANCE_FORMULA_FAMILY}`
    );
  }
  if (schemaVersion !== WEAPON_BALANCE_SCHEMA_VERSION) {
    throw new WeaponBalanceParseError(
      "weaponBalanceAudit.schemaVersion",
      `expected ${WEAPON_BALANCE_SCHEMA_VERSION}`
    );
  }
  const workbookVersion = parseKnownWorkbookVersion(
    source,
    "workbookVersion",
    "weaponBalanceAudit"
  );
  const workbookSha256 = readRequiredString(
    source,
    "workbookSha256",
    "weaponBalanceAudit"
  );
  assertWorkbookVersionShaMapping(
    workbookVersion,
    workbookSha256,
    "weaponBalanceAudit.workbookSha256"
  );

  const rawRecords = readContainerList(
    readRawValue(source, "records"),
    "record",
    "weaponBalanceAudit.records"
  );
  const records = rawRecords.map((record, index) =>
    parseWeaponBalanceAuditRecord(
      record,
      `weaponBalanceAudit.records.record[${index}]`
    )
  );
  assertUniqueLedgerRecords(records);

  return {
    formulaFamily: WEAPON_BALANCE_FORMULA_FAMILY,
    schemaVersion: WEAPON_BALANCE_SCHEMA_VERSION,
    workbookVersion,
    workbookSha256,
    records
  };
}

export function parseWeaponBalanceAuditRecord(
  value: unknown,
  path = "weaponBalanceAudit.records.record"
): WeaponBalanceAuditRecord {
  const source = requireObject(value, path);
  assertOnlyKeys(source, [
    "auditRef",
    "itemName",
    "profileKey",
    ...WEAPON_BALANCE_FORMULA_INPUT_KEYS,
    "priceLayers",
    "status",
    "displayEligible",
    "inputDigest",
    "sourceDigest",
    "budgetBreakdown",
    "ruleRefs",
    "note"
  ], path);

  const record: WeaponBalanceAuditRecord = {
    auditRef: readRequiredString(source, "auditRef", path),
    itemName: readRequiredString(source, "itemName", path),
    profileKey: normalizeProfileKey(
      readRequiredString(source, "profileKey", path),
      `${path}.profileKey`
    ),
    ...parseFormulaInputs(source, path),
    status: parseAuditStatus(source, path),
    displayEligible: readRequiredBoolean(source, "displayEligible", path),
    inputDigest: readRequiredString(source, "inputDigest", path),
    sourceDigest: readRequiredString(source, "sourceDigest", path),
    budgetBreakdown: parseBudgetBreakdown(source, path),
    ruleRefs: parseRuleRefs(source, path)
  };
  const note = readOptionalString(source, "note");
  if (note !== undefined) record.note = note;
  if (readRawValue(source, "priceLayers") !== undefined) {
    record.priceLayers = readRequiredFiniteNumber(source, "priceLayers", path);
  }
  return record;
}

export function createWeaponBalanceProfileFromAuditRecord(
  record: WeaponBalanceAuditRecord
): WeaponBalanceProfile {
  return {
    profileKey: record.profileKey,
    ...pickWeaponBalanceFormulaInputs(record),
    status: record.status,
    displayEligible: record.displayEligible,
    inputDigest: record.inputDigest,
    auditRef: record.auditRef
  };
}

export function pickWeaponBalanceFormulaInputs(
  source: WeaponBalanceFormulaInputs
): WeaponBalanceFormulaInputs {
  return {
    dualWield: source.dualWield,
    pierce: source.pierce,
    damageType: source.damageType,
    shotgun: source.shotgun,
    magPrice: source.magPrice,
    weightLayers: source.weightLayers,
    category: source.category,
    formula: source.formula
  };
}

export function indexWeaponBalanceAuditRecords(
  ledger: WeaponBalanceAuditLedger
): ReadonlyMap<string, WeaponBalanceAuditRecord> {
  const result = new Map<string, WeaponBalanceAuditRecord>();
  for (const record of ledger.records) {
    if (result.has(record.auditRef)) {
      throw new WeaponBalanceParseError(
        "weaponBalanceAudit.records",
        `duplicate auditRef ${record.auditRef}`
      );
    }
    result.set(record.auditRef, record);
  }
  return result;
}

function parseFormulaInputs(
  source: Record<string, unknown>,
  path: string
): WeaponBalanceFormulaInputs {
  const inputs: WeaponBalanceFormulaInputs = {
    dualWield: readRequiredFiniteNumber(source, "dualWield", path),
    pierce: readRequiredFiniteNumber(source, "pierce", path),
    damageType: readRequiredFiniteNumber(source, "damageType", path),
    shotgun: readRequiredFiniteNumber(source, "shotgun", path),
    magPrice: readRequiredFiniteNumber(source, "magPrice", path),
    weightLayers: readRequiredFiniteNumber(source, "weightLayers", path),
    category: readRequiredFiniteNumber(source, "category", path),
    formula: readRequiredFiniteNumber(source, "formula", path)
  };
  if (inputs.formula !== WEAPON_BALANCE_FORMULA_VERSION) {
    throw new WeaponBalanceParseError(
      `${path}.formula`,
      `expected implemented formula version ${WEAPON_BALANCE_FORMULA_VERSION}`
    );
  }
  return inputs;
}

function parseAuditStatus(
  source: Record<string, unknown>,
  path: string
): WeaponBalanceAuditStatus {
  const status = readRequiredString(source, "status", path);
  if (!(WEAPON_BALANCE_AUDIT_STATUSES as readonly string[]).includes(status)) {
    throw new WeaponBalanceParseError(
      `${path}.status`,
      `expected one of ${WEAPON_BALANCE_AUDIT_STATUSES.join(", ")}`
    );
  }
  return status as WeaponBalanceAuditStatus;
}

function parseBudgetBreakdown(
  source: Record<string, unknown>,
  path: string
): WeaponBalanceBudgetEntry[] {
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
    const entry: WeaponBalanceBudgetEntry = {
      code: readRequiredString(entrySource, "code", entryPath),
      delta: readRequiredFiniteNumber(entrySource, "delta", entryPath),
      ruleRef: readRequiredString(entrySource, "ruleRef", entryPath)
    };
    const evidenceRef = readOptionalString(entrySource, "evidenceRef");
    if (evidenceRef !== undefined) entry.evidenceRef = evidenceRef;
    return entry;
  });
}

function parseRuleRefs(
  source: Record<string, unknown>,
  path: string
): WeaponBalanceRuleReference[] {
  const rawRefs = readContainerList(
    readRawValue(source, "ruleRefs"),
    "ref",
    `${path}.ruleRefs`
  );
  return rawRefs.map((rawRef, index) => {
    const refPath = `${path}.ruleRefs.ref[${index}]`;
    const refSource = requireObject(rawRef, refPath);
    assertOnlyKeys(refSource, ["id", "target", "evidenceRef"], refPath);
    const ref: WeaponBalanceRuleReference = {
      id: readRequiredString(refSource, "id", refPath),
      target: readRequiredString(refSource, "target", refPath)
    };
    const evidenceRef = readOptionalString(refSource, "evidenceRef");
    if (evidenceRef !== undefined) ref.evidenceRef = evidenceRef;
    return ref;
  });
}

function assertUniqueLedgerRecords(records: WeaponBalanceAuditRecord[]): void {
  const auditRefs = new Set<string>();
  const identities = new Set<string>();
  for (const record of records) {
    if (auditRefs.has(record.auditRef)) {
      throw new WeaponBalanceParseError(
        "weaponBalanceAudit.records",
        `duplicate auditRef ${record.auditRef}`
      );
    }
    auditRefs.add(record.auditRef);

    const identity = `${record.itemName}\u0000${record.profileKey}`;
    if (identities.has(identity)) {
      throw new WeaponBalanceParseError(
        "weaponBalanceAudit.records",
        `duplicate item/profile ${record.itemName}/${record.profileKey}`
      );
    }
    identities.add(identity);
  }
}

function normalizeProfileKey(value: string, path: string): string {
  const key = value.trim();
  if (key !== "data" && (!key.startsWith("data_") || key.length <= 5)) {
    throw new WeaponBalanceParseError(
      path,
      `expected an effective data profile key, got ${key || "<empty>"}`
    );
  }
  return key;
}

function parseKnownWorkbookVersion(
  source: Record<string, unknown>,
  key: string,
  path: string
): number {
  const version = readRequiredFiniteNumber(source, key, path);
  if (!Number.isInteger(version) || version <= 0) {
    throw new WeaponBalanceParseError(
      `${path}.${key}`,
      "expected a positive integer workbook version"
    );
  }
  if (WEAPON_BALANCE_WORKBOOK_SHA256_BY_VERSION[version] === undefined) {
    throw new WeaponBalanceParseError(
      `${path}.${key}`,
      `unsupported workbook version ${version}`
    );
  }
  return version;
}

function assertWorkbookVersionShaMapping(
  version: number,
  sha256: string,
  path: string
): void {
  if (!/^[0-9A-F]{64}$/.test(sha256)) {
    throw new WeaponBalanceParseError(
      path,
      "expected 64 upper-case hex digits"
    );
  }
  const expected = WEAPON_BALANCE_WORKBOOK_SHA256_BY_VERSION[version];
  if (sha256 !== expected) {
    throw new WeaponBalanceParseError(
      path,
      `does not match workbookVersion ${version}`
    );
  }
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
      throw new WeaponBalanceParseError(`${path}.${key}`, "unexpected field");
    }
  }
}

function requireObject(value: unknown, path: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new WeaponBalanceParseError(path, "expected an object");
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
    throw new WeaponBalanceParseError(`${path}.${key}`, "expected a finite number");
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
    throw new WeaponBalanceParseError(`${path}.${key}`, "expected a non-empty string");
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

function readRequiredBoolean(
  source: Record<string, unknown>,
  key: string,
  path: string
): boolean {
  const raw = readRawValue(source, key);
  if (raw === true || raw === 1 || raw === "1" || raw === "true") return true;
  if (raw === false || raw === 0 || raw === "0" || raw === "false") return false;
  throw new WeaponBalanceParseError(`${path}.${key}`, "expected a boolean");
}
