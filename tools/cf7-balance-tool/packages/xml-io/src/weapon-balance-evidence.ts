import fs from "node:fs";
import path from "node:path";
import { XMLParser } from "fast-xml-parser";

import {
  WEAPON_BALANCE_BUDGET_CODES,
  computeWeaponPrice,
  type WeaponBalanceAuditRecord
} from "@cf7-balance-tool/core";
import type { ResolvedWeaponItemProfile } from "./weapon-balance.js";

export type WeaponPriceEvidenceContext = Pick<ResolvedWeaponItemProfile,
  "itemName" | "profileKey" | "itemUse" | "itemPrice" | "runtimeInputs">;

export interface WeaponAcquisitionIndex {
  repositoryRoot: string;
  craftingFilesByItem: ReadonlyMap<string, readonly string[]>;
  goldShopFilesByItem: ReadonlyMap<string, readonly string[]>;
  kshopFilesByItem: ReadonlyMap<string, readonly string[]>;
}

export interface WeaponBalanceEvidenceIssue {
  severity: "error" | "warning";
  code: string;
  path: string;
  message: string;
}

export interface WeaponBalanceEvidenceValidationResult {
  valid: boolean;
  displayEligible: boolean;
  issues: WeaponBalanceEvidenceIssue[];
}

/** 构建现役合成、金币商店和 K 点商店的精确物品名索引。 */
export function buildWeaponAcquisitionIndex(
  repositoryRoot: string
): WeaponAcquisitionIndex {
  const root = path.resolve(repositoryRoot);
  return {
    repositoryRoot: root,
    craftingFilesByItem: indexJsonDirectory(
      root,
      "data/crafting",
      extractCraftingNames
    ),
    goldShopFilesByItem: indexJsonDirectory(
      root,
      "data/shops/npcs",
      extractNpcShopNames
    ),
    kshopFilesByItem: indexJsonDirectory(
      root,
      "data/kshop",
      extractKshopNames
    )
  };
}

/**
 * 校验 displayEligible attestation 所引用的仓库证据。
 * 领域 validator 与本结果必须同时通过，玩家投影才可进入显示层。
 */
export function validateWeaponBalanceEvidence(
  itemName: string,
  record: WeaponBalanceAuditRecord,
  index: WeaponAcquisitionIndex,
  priceContext?: WeaponPriceEvidenceContext
): WeaponBalanceEvidenceValidationResult {
  const issues: WeaponBalanceEvidenceIssue[] = [];

  if (record.status !== "confirmed") {
    return { valid: true, displayEligible: false, issues };
  }

  record.ruleRefs.forEach((ref, refIndex) => {
    validateEvidencePath(
      ref.evidenceRef,
        `weaponBalanceAudit.ruleRefs.ref[${refIndex}].evidenceRef`,
      index.repositoryRoot,
      issues
    );
  });

  record.budgetBreakdown.forEach((entry, entryIndex) => {
    const issuePath = `weaponBalanceAudit.budgetBreakdown.entry[${entryIndex}]`;
    if (!(WEAPON_BALANCE_BUDGET_CODES as readonly string[]).includes(entry.code)) {
      addError(
        issues,
        "budget_code_unknown",
        `${issuePath}.code`,
        `unsupported weapon balance budget code ${entry.code}`
      );
    }
    const evidencePath = validateEvidencePath(
      entry.evidenceRef,
      `${issuePath}.evidenceRef`,
      index.repositoryRoot,
      issues
    );

    if (entry.code === "acquisition.crafting") {
      const matches = index.craftingFilesByItem.get(itemName) ?? [];
      if (matches.length === 0) {
        addError(
          issues,
          "crafting_output_not_found",
          issuePath,
          `no active crafting recipe has exact output name ${itemName}`
        );
      } else if (evidencePath && !matches.includes(evidencePath)) {
        addError(
          issues,
          "crafting_evidence_mismatch",
          `${issuePath}.evidenceRef`,
          `referenced file does not contain an exact ${itemName} recipe output`
        );
      }
    }

    if (entry.code === "acquisition.gold-standard") {
      const goldMatches = index.goldShopFilesByItem.get(itemName) ?? [];
      const craftingMatches = index.craftingFilesByItem.get(itemName) ?? [];
      const kshopMatches = index.kshopFilesByItem.get(itemName) ?? [];

      if (goldMatches.length === 0) {
        addError(
          issues,
          "gold_shop_item_not_found",
          issuePath,
          `no active NPC gold shop contains exact item ${itemName}`
        );
      } else if (evidencePath && !goldMatches.includes(evidencePath)) {
        addError(
          issues,
          "gold_shop_evidence_mismatch",
          `${issuePath}.evidenceRef`,
          `referenced file does not contain exact NPC shop item ${itemName}`
        );
      }

      if (craftingMatches.length > 0) {
        addError(
          issues,
          "gold_standard_has_crafting_source",
          issuePath,
          `${itemName} also appears as a crafting output`
        );
      }
      if (kshopMatches.length > 0) {
        addError(
          issues,
          "gold_standard_has_kshop_source",
          issuePath,
          `${itemName} also appears in a K-point shop`
        );
      }
    }

    if (entry.code === "acquisition.kshop") {
      const matches = index.kshopFilesByItem.get(itemName) ?? [];
      if (matches.length === 0) {
        addError(
          issues,
          "kshop_item_not_found",
          issuePath,
          `no active K-point shop contains exact item ${itemName}`
        );
      } else if (evidencePath && !matches.includes(evidencePath)) {
        addError(
          issues,
          "kshop_evidence_mismatch",
          `${issuePath}.evidenceRef`,
          `referenced file does not contain exact K-point shop item ${itemName}`
        );
      }
    }

    if (entry.code === "acquisition.unverified") {
      addError(
        issues,
        "unverified_acquisition_confirmed",
        issuePath,
        "acquisition.unverified can never support a confirmed record"
      );
    }

    if (entry.code === "acquisition.high-price") {
      validateHighPriceEvidence(itemName, record, index, priceContext,
        entry.delta, evidencePath, issuePath, issues);
    }
  });

  const valid = !issues.some((issue) => issue.severity === "error");
  return {
    valid,
    displayEligible: valid && record.displayEligible,
    issues
  };
}

/** 只支持已独立裁定的购买限定金币 +1；不推断其他物品的价格层。 */
function validateHighPriceEvidence(
  itemName: string,
  record: WeaponBalanceAuditRecord,
  index: WeaponAcquisitionIndex,
  context: WeaponPriceEvidenceContext | undefined,
  delta: number,
  evidencePath: string | undefined,
  issuePath: string,
  issues: WeaponBalanceEvidenceIssue[]
): void {
  const requiredRules = [
    ["WBR-MAP-002", "pricing.priceLayers"],
    ["WBR-PL-001", "pricing.priceLayers"],
    ["WBR-PL-003", "pricing.priceLayers"],
    ["WBR-PRICE-001", "pricing.goldPrice"],
    ["WBR-PRICE-002", "pricing.priceRatio"],
    ["WBR-PRICE-003", "pricing.priceLayers"]
  ];
  if (record.priceLayers !== 1 || delta !== 1 || requiredRules.some(([id, target]) =>
    !record.ruleRefs.some((ref) => ref.id === id && ref.target === target))) {
    addError(issues, "high_price_mapping_unverified", issuePath,
      "gold high-price +1 requires independent priceLayers=1 and explicit mapping/price rule references");
    return;
  }

  const goldFiles = index.goldShopFilesByItem.get(itemName) ?? [];
  if (!evidencePath || !goldFiles.includes(evidencePath)) {
    addError(issues, "high_price_gold_shop_mismatch", issuePath,
      `evidence must name an NPC gold shop containing exact item ${itemName}`);
  }
  if ((index.craftingFilesByItem.get(itemName)?.length ?? 0) > 0 ||
      (index.kshopFilesByItem.get(itemName)?.length ?? 0) > 0) {
    addError(issues, "high_price_other_acquisition", issuePath,
      `${itemName} also has crafting or K-point acquisition; gold-only +1 cannot be confirmed`);
  }
  const unreviewed = findUnreviewedItemReferences(index.repositoryRoot, itemName, goldFiles);
  if (unreviewed.length > 0) {
    addError(issues, "high_price_unreviewed_acquisition", issuePath,
      `review named references outside the weapon definition and gold shops: ${unreviewed.join(", ")}`);
  }

  if (!context || context.itemName !== itemName || context.profileKey !== record.profileKey ||
      !["长枪", "手枪", "手枪2"].includes(context.itemUse ?? "") ||
      !Number.isFinite(context.itemPrice) || context.itemPrice <= 0 ||
      !Number.isFinite(context.runtimeInputs.level) || context.runtimeInputs.level <= 0 ||
      !Number.isFinite(record.category) || record.category <= 0 ||
      !Number.isFinite(record.damageType) || record.damageType < 1) {
    addError(issues, "high_price_context_invalid", issuePath,
      "price verification requires current item identity, price, use, effective level and audited factors");
    return;
  }
  const recommendedPrice = computeWeaponPrice({
    level: context.runtimeInputs.level,
    weightLayers: record.priceLayers,
    dualWieldFactor: context.itemUse === "长枪" ? 1 : 1.5,
    categoryFactor: record.category,
    damageTypeFactor: record.damageType
  }).goldPrice;
  const priceRatio = context.itemPrice / recommendedPrice;
  if (!Number.isFinite(priceRatio) || priceRatio < 0.8 || priceRatio > 1.25) {
    addError(issues, "high_price_outside_audit_band", issuePath,
      `price=${context.itemPrice}, recommended=${recommendedPrice}, ratio=${priceRatio}; expected 0.8..1.25`);
  }
}

/**
 * 保守检查具名获取引用：XML/JSON 精确叶值，AS 源码文本。
 * 定义自身、派生字典及资产索引不是获取路径；其余命中须人工语义复核，
 * 不因它看似 NPC 预装就自动放行。动态拼接/通用随机池仍须规则证据说明。
 */
function findUnreviewedItemReferences(
  repositoryRoot: string, itemName: string, goldFiles: readonly string[]
): string[] {
  const matches: string[] = [];
  const xmlParser = new XMLParser({ ignoreAttributes: false, trimValues: true });
  const scan = (directory: string): void => {
    if (!fs.existsSync(directory)) return;
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) continue;
      const absolute = path.join(directory, entry.name);
      const relative = toRepositoryPath(repositoryRoot, absolute);
      if (relative === "data/dictionaries") continue;
      if (entry.isDirectory()) { scan(absolute); continue; }
      const ext = path.extname(entry.name).toLowerCase();
      if (![".xml", ".json", ".as"].includes(ext) || goldFiles.includes(relative) ||
          relative === "data/items/asset_source_map.xml") continue;
      const source = fs.readFileSync(absolute, "utf8").replace(/^\uFEFF/, "");
      if (ext === ".as") {
        if (source.includes(itemName)) matches.push(relative);
        continue;
      }
      const parsed: unknown = ext === ".json" ? JSON.parse(source) : xmlParser.parse(source);
      if (containsItemName(parsed, itemName, relative.startsWith("data/items/"))) {
        matches.push(relative);
      }
    }
  };
  for (const directory of ["data", "config", "scripts"]) scan(path.join(repositoryRoot, directory));
  return matches.sort();
}

function containsItemName(value: unknown, itemName: string, skipDefinition: boolean): boolean {
  if (value === itemName) return true;
  if (Array.isArray(value)) return value.some((part) => containsItemName(part, itemName, skipDefinition));
  if (!isObject(value)) return false;
  if (skipDefinition && value.name === itemName && value.type === "武器") return false;
  return Object.values(value).some((part) => containsItemName(part, itemName, skipDefinition));
}

function validateEvidencePath(
  evidenceRef: string | undefined,
  issuePath: string,
  repositoryRoot: string,
  issues: WeaponBalanceEvidenceIssue[]
): string | undefined {
  if (!evidenceRef?.trim()) {
    addError(
      issues,
      "evidence_ref_missing",
      issuePath,
      "display-eligible records require a repository evidence path"
    );
    return undefined;
  }

  const pathPart = evidenceRef.split("#", 1)[0]?.trim();
  if (!pathPart) {
    addError(
      issues,
      "evidence_ref_path_missing",
      issuePath,
      "evidenceRef must begin with a repository-relative file path"
    );
    return undefined;
  }

  const resolved = path.resolve(repositoryRoot, pathPart.replaceAll("/", path.sep));
  const relative = path.relative(repositoryRoot, resolved);
  if (
    path.isAbsolute(pathPart) ||
    relative === "" ||
    relative.startsWith("..") ||
    path.isAbsolute(relative)
  ) {
    addError(
      issues,
      "evidence_ref_outside_repository",
      issuePath,
      "evidenceRef must resolve to a file inside the repository"
    );
    return undefined;
  }

  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    addError(
      issues,
      "evidence_ref_not_found",
      issuePath,
      `evidence file does not exist: ${pathPart}`
    );
    return undefined;
  }

  return toRepositoryPath(repositoryRoot, resolved);
}

function indexJsonDirectory(
  repositoryRoot: string,
  relativeDirectory: string,
  extractNames: (value: unknown) => string[]
): ReadonlyMap<string, readonly string[]> {
  const directory = path.join(repositoryRoot, ...relativeDirectory.split("/"));
  const mutable = new Map<string, string[]>();

  if (!fs.existsSync(directory)) {
    return mutable;
  }

  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.toLowerCase().endsWith(".json")) {
      continue;
    }

    const absolutePath = path.join(directory, entry.name);
    const parsed = JSON.parse(
      fs.readFileSync(absolutePath, "utf8").replace(/^\uFEFF/, "")
    ) as unknown;
    const repositoryPath = toRepositoryPath(repositoryRoot, absolutePath);

    for (const itemName of extractNames(parsed)) {
      const files = mutable.get(itemName) ?? [];
      if (!files.includes(repositoryPath)) {
        files.push(repositoryPath);
      }
      mutable.set(itemName, files);
    }
  }

  return mutable;
}

function extractCraftingNames(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (isObject(entry) ? entry.name : undefined))
    .filter((name): name is string => typeof name === "string");
}

function extractNpcShopNames(value: unknown): string[] {
  if (!isObject(value) || !isObject(value.catalog)) return [];

  return Object.values(value.catalog)
    .map((entry) => {
      if (typeof entry === "string") return entry;
      return isObject(entry) && typeof entry.name === "string"
        ? entry.name
        : undefined;
    })
    .filter((name): name is string => typeof name === "string");
}

function extractKshopNames(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (isObject(entry) ? entry.item : undefined))
    .filter((name): name is string => typeof name === "string");
}

function toRepositoryPath(repositoryRoot: string, absolutePath: string): string {
  return path.relative(repositoryRoot, absolutePath).split(path.sep).join("/");
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function addError(
  issues: WeaponBalanceEvidenceIssue[],
  code: string,
  issuePath: string,
  message: string
): void {
  issues.push({ severity: "error", code, path: issuePath, message });
}
