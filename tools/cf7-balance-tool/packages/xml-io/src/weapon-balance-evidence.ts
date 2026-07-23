import fs from "node:fs";
import path from "node:path";

import {
  WEAPON_BALANCE_BUDGET_CODES,
  type WeaponBalanceAuditRecord
} from "@cf7-balance-tool/core";

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
  index: WeaponAcquisitionIndex
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
      addError(
        issues,
        "high_price_mapping_unverified",
        issuePath,
        "confirmed high-price layers require an implemented exact price-layer mapping gate"
      );
    }
  });

  const valid = !issues.some((issue) => issue.severity === "error");
  return {
    valid,
    displayEligible: valid && record.displayEligible,
    issues
  };
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
