import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { XMLParser, XMLValidator } from "fast-xml-parser";
import { readItemIdentityNames } from "./item-identity-names.js";
import {
  derivePlayerWeaponBalanceProjection,
  validateWeaponBalanceRecord,
  type PlayerWeaponBalanceProjection,
  type WeaponBalanceAuditLedger,
  type WeaponBalanceValidationIssue
} from "@cf7-balance-tool/core";
import {
  DEFAULT_WEAPON_BALANCE_AUDIT_LEDGER, parseWeaponBalanceAuditLedgerFromXml,
  parseWeaponBalanceItemObject
} from "./weapon-balance.js";
import {
  buildWeaponAcquisitionIndex, validateWeaponBalanceEvidence, type WeaponAcquisitionIndex
} from "./weapon-balance-evidence.js";
import {
  AS2_WEAPON_SUMMARY_SOURCE, modelAs2WeaponSummary, verifyAs2WeaponSummaryModelSource
} from "./weapon-summary-as2-model.js";

type Node = Record<string, unknown>;
const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "@_", parseTagValue: true, trimValues: true });

export interface WeaponSummaryComparison {
  profileKey: string;
  as2Model: { projection: PlayerWeaponBalanceProjection | null; reason: string };
  tool: { projection: PlayerWeaponBalanceProjection | null; valid: boolean | null; parseError: string | null;
    issueCodes: string[]; issues: WeaponBalanceValidationIssue[] };
  balanceCheck: { projection: PlayerWeaponBalanceProjection | null; issueCodes: string[];
    issues: Array<{ code: string; message: string }>; evidenceChecked: boolean };
  equal: boolean;
  balanceCheckEqual: boolean;
}

/** Compare current tool APIs unchanged; never repair or normalize a residual away. */
export function compareWeaponSummaryItem(
  item: Node, profileKey: string, ledger?: WeaponBalanceAuditLedger,
  acquisitionIndex?: WeaponAcquisitionIndex
): WeaponSummaryComparison {
  const as2Model = modelAs2WeaponSummary(item, item.balance, profileKey);
  let projection: PlayerWeaponBalanceProjection | null = null;
  let checkedProjection: PlayerWeaponBalanceProjection | null = null;
  let parseError: string | null = null;
  let valid: boolean | null = null;
  const validationIssues: WeaponBalanceValidationIssue[] = [];
  const issueCodes: string[] = [];
  const checkIssueCodes: string[] = [];
  const checkIssues: Array<{ code: string; message: string }> = [];
  const family = object(item.balance)?.formulaFamily;
  if (item.balance === undefined) {
    issueCodes.push("balance_absent");
  } else if (typeof family === "string" && family !== "weapon") {
    issueCodes.push("outside_weapon_balance_family");
  } else {
    try {
      const parsed = parseWeaponBalanceItemObject(item).find((entry) => entry.profileKey === profileKey);
      if (!parsed) throw new Error(`selected profile ${profileKey} is absent`);
      const auditRecord = ledger?.records.find((record) => record.auditRef === parsed.profile.auditRef);
      const options = {
        container: parsed.container, ...(ledger ? { ledger } : {}), ...(auditRecord ? { auditRecord } : {}),
        itemName: parsed.itemName, profileKey, digestInput: parsed.digestInput,
        currentInputDigest: parsed.currentInputDigest, currentSourceDigest: parsed.currentSourceDigest,
        runtimeInputs: parsed.runtimeInputs
      };
      const validation = validateWeaponBalanceRecord(parsed.profile, options);
      valid = validation.valid;
      validationIssues.push(...validation.issues);
      issueCodes.push(...validation.issues.map((issue) => issue.code));
      projection = derivePlayerWeaponBalanceProjection(parsed.profile, options);
      if (acquisitionIndex && auditRecord) {
        const evidence = validateWeaponBalanceEvidence(parsed.itemName, auditRecord, acquisitionIndex, parsed);
        checkIssues.push(...evidence.issues.filter((issue) => issue.severity === "error")
          .map(({ code, message }) => ({ code, message })));
      }
      if (parsed.itemUse && parsed.profile.dualWield !== (["手枪", "手枪2"].includes(parsed.itemUse) ? 2 : 1)) {
        checkIssueCodes.push("dual_wield_use_mismatch");
        checkIssues.push({ code: "dual_wield_use_mismatch", message: `use=${parsed.itemUse}, dualWield=${parsed.profile.dualWield}` });
      }
      checkIssueCodes.push(...checkIssues.map((issue) => issue.code));
      checkedProjection = checkIssueCodes.length === 0 ? projection : null;
    } catch (error) {
      parseError = error instanceof Error ? error.message : String(error);
      issueCodes.push("parse_error");
    }
  }
  return {
    profileKey, as2Model,
    tool: { projection, valid, parseError, issueCodes: [...new Set(issueCodes)].sort(), issues: validationIssues },
    balanceCheck: { projection: checkedProjection, issueCodes: [...new Set(checkIssueCodes)].sort(), issues: checkIssues,
      evidenceChecked: acquisitionIndex !== undefined },
    equal: same(as2Model.projection, projection),
    balanceCheckEqual: same(as2Model.projection, checkedProjection)
  };
}

/** Full source occurrence inventory in production list order; no name deduplication. */
export function buildWeaponSummaryParityReport(repositoryRoot: string) {
  const root = path.resolve(repositoryRoot);
  const inputFiles: Array<{ path: string; sha256: string }> = [];
  const read = (relative: string): string => {
    const bytes = fs.readFileSync(path.join(root, relative));
    inputFiles.push({ path: relative, sha256: createHash("sha256").update(bytes).digest("hex") });
    return bytes.toString("utf8");
  };
  const as2SourceHash = verifyAs2WeaponSummaryModelSource(read(AS2_WEAPON_SUMMARY_SOURCE));
  const list = object(parser.parse(read("data/items/list.xml")))?.root;
  const filenames = array(object(list)?.items).map(String);
  if (filenames.length === 0) throw new Error("data/items/list.xml has no items");
  const ledger = parseWeaponBalanceAuditLedgerFromXml(read(DEFAULT_WEAPON_BALANCE_AUDIT_LEDGER));
  const acquisitionIndex = buildWeaponAcquisitionIndex(root);
  const rows: Array<WeaponSummaryComparison & { sourceFile: string; listOrdinal: number; itemOrdinal: number;
    occurrence: number; itemName: string; balanceFamily: string | null; auditRef: string | null;
    declaredStatus: string | null }> = [];
  filenames.forEach((filename, listOrdinal) => {
    if (path.basename(filename) !== filename) throw new Error(`non-leaf item file ${filename}`);
    const sourceFile = `data/items/${filename}`;
    const xml = read(sourceFile);
    const valid = XMLValidator.validate(xml);
    if (valid !== true) throw new Error(`${sourceFile}: ${valid.err.msg}`);
    const items = array(object(object(parser.parse(xml))?.root)?.item);
    const occurrences = new Map<string, number>();
    const names = readItemIdentityNames(xml);
    if (items.length !== names.length) throw new Error(`${sourceFile}: item identity count mismatch`);
    items.forEach((value, itemOrdinal) => {
      const item = object(value);
      if (!item) throw new Error(`${sourceFile}: non-object item ${itemOrdinal}`);
      const itemName = names[itemOrdinal]!;
      const occurrence = (occurrences.get(itemName) ?? 0) + 1;
      occurrences.set(itemName, occurrence);
      const family = object(item.balance)?.formulaFamily;
      if (item.type !== "武器" && family !== "weapon") return;
      const profiles = ["data", ...Object.keys(item).filter((key) => key.startsWith("data_") && key.length > 5).sort()];
      for (const profileKey of profiles) {
        const compact = object(object(object(item.balance)?.profiles)?.[profileKey]);
        rows.push({ sourceFile, listOrdinal, itemOrdinal, occurrence, itemName,
          balanceFamily: typeof family === "string" ? family : null,
          auditRef: typeof compact?.auditRef === "string" ? compact.auditRef : null,
          declaredStatus: typeof compact?.status === "string" ? compact.status : null,
          ...compareWeaponSummaryItem(item, profileKey, ledger, acquisitionIndex) });
      }
    });
  });
  // High-price evidence scans data/config/scripts by exact names. Bind that broad text
  // boundary plus explicit rule references and implementation sources to the report.
  const evidenceFiles = new Set<string>();
  const collectInputs = (directory: string): void => {
    for (const entry of fs.readdirSync(path.join(root, directory), { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
      const relative = `${directory}/${entry.name}`;
      if (entry.isSymbolicLink() || relative === "data/dictionaries") continue;
      if (entry.isDirectory()) collectInputs(relative);
      else if (/\.(xml|json|as)$/i.test(entry.name)) evidenceFiles.add(relative);
    }
  };
  for (const directory of ["data", "config", "scripts"]) collectInputs(directory);
  const toolBase = "tools/cf7-balance-tool/packages";
  for (const file of ["core/src/weapon-balance/record.ts", "core/src/weapon-balance/digest.ts",
    "core/src/weapon-balance/validation.ts", "core/src/weapon-balance/projection.ts",
    "core/src/weapon-balance/rule-catalog.ts", "core/src/formulas/weapons.ts", "core/src/formulas/economy.ts",
    "xml-io/src/weapon-balance.ts", "xml-io/src/weapon-balance-evidence.ts",
    "xml-io/src/weapon-summary-as2-model.ts", "xml-io/src/weapon-summary-parity.ts"]) {
    if (fs.existsSync(path.join(root, toolBase, file))) evidenceFiles.add(`${toolBase}/${file}`);
  }
  for (const record of ledger.records) {
    for (const ref of [...record.ruleRefs, ...record.budgetBreakdown]) {
      const file = ref.evidenceRef?.split("#")[0];
      if (file && fs.existsSync(path.resolve(root, file)) && fs.statSync(path.resolve(root, file)).isFile()) evidenceFiles.add(file);
    }
  }
  const alreadyRead = new Set(inputFiles.map((file) => file.path));
  for (const file of [...evidenceFiles].sort()) if (!alreadyRead.has(file)) read(file);
  const sourceMismatchRows = rows.filter((row) => !row.equal);
  const balanceCheckMismatchRows = rows.filter((row) => !row.balanceCheckEqual);
  const joinCounts = new Map<string, number>();
  for (const row of rows) {
    if (row.balanceFamily !== "weapon" || row.tool.parseError !== null) continue;
    const identity = ledger.records.find((record) => record.auditRef === row.auditRef)?.auditRef;
    if (identity) joinCounts.set(identity, (joinCounts.get(identity) ?? 0) + 1);
  }
  return {
    schema: "cf7.weapon-summary-parity.v1", evidenceKind: "offline_typescript_model_not_avm1",
    repositoryCommit: execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim(),
    as2Model: { source: AS2_WEAPON_SUMMARY_SOURCE, reviewedSourceSha256: as2SourceHash },
    scope: "all weapon item source occurrences and all data/data_* profiles in data/items/list.xml order; no name deduplication",
    summary: {
      itemFileCount: filenames.length, profileCount: rows.length,
      weaponFamilyProfileCount: rows.filter((row) => row.balanceFamily === "weapon").length,
      dataVariantProfileCount: rows.filter((row) => row.profileKey !== "data").length,
      as2ModelVisible: rows.filter((row) => row.as2Model.projection !== null).length,
      toolVisible: rows.filter((row) => row.tool.projection !== null).length,
      balanceCheckVisible: rows.filter((row) => row.balanceCheck.projection !== null).length,
      projectionMismatchCount: sourceMismatchRows.length,
      balanceCheckMismatchCount: balanceCheckMismatchRows.length,
      toolParseErrorCount: rows.filter((row) => row.tool.parseError !== null).length,
      validationErrorProfileCount: rows.filter((row) => row.tool.valid === false).length,
      validationErrorCount: rows.flatMap((row) => row.tool.issues).filter((issue) => issue.severity === "error").length,
      additionalEvidenceErrorProfileCount: rows.filter((row) => row.balanceCheck.issues.length > 0).length
    },
    globalLedgerChecks: {
      missingAuditRefs: rows.filter((row) => row.tool.issues.some((issue) => issue.code === "audit_record_missing"))
        .map((row) => ({ itemName: row.itemName, profileKey: row.profileKey, auditRef: row.auditRef })),
      orphanAuditRefs: ledger.records.filter((record) => !joinCounts.has(record.auditRef)).map((record) => record.auditRef),
      duplicateRuntimeAuditRefs: [...joinCounts].filter(([, count]) => count > 1).map(([auditRef, count]) => ({ auditRef, count }))
    },
    inputFiles, rows,
    limitations: [
      "TS models reviewed AS2 source; AVM1 Number/String/XMLParser/enumeration and the deployed SWF were not executed.",
      "Source occurrences are retained, including repeated names; ItemUtil reverse enumeration/defaulting/name overwrite is not asserted by this source comparison.",
      "No production XML/cache references were removed; runtime mutation of raw data/cache must rerun exact current-input validation.",
      "Tool projection and the additional balance-check evidence/use gates are reported separately; neither is substituted for current AS2 visibility."
    ]
  };
}

function object(value: unknown): Node | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Node : null;
}
function array(value: unknown): unknown[] { return value === undefined ? [] : Array.isArray(value) ? value : [value]; }
function same(left: PlayerWeaponBalanceProjection | null, right: PlayerWeaponBalanceProjection | null): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}
